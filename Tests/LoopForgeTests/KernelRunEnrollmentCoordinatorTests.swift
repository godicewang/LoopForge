import Darwin
import Foundation
import XCTest

@testable import LoopForge

final class KernelRunEnrollmentCoordinatorTests: XCTestCase {
  func testRatifiedContractIsJournaledBeforeRunBecomesRecoverable() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(candidate: try candidate(workspace: fixture.workspace))
    let request = fixture.request(ratifiedContract: ratified)

    let receipt = try await fixture.coordinator.enroll(request)

    XCTAssertEqual(receipt.schemaVersion, 1)
    XCTAssertEqual(receipt.runID, request.runID)
    XCTAssertEqual(receipt.contractID, ratified.contract.id)
    XCTAssertEqual(receipt.contractRevision, ratified.receipt.revision)
    XCTAssertEqual(receipt.candidateDigest, ratified.receipt.candidateDigest)
    XCTAssertEqual(receipt.ratificationReceiptID, ratified.receipt.receiptID)
    XCTAssertFalse(receipt.journalTransaction.duplicate)
    XCTAssertEqual(receipt.kernelProjection.phase, .ready)
    XCTAssertEqual(receipt.kernelProjection.runID, request.runID)
    let enrollmentEvidence = try XCTUnwrap(
      receipt.registration.enrollmentEvidence
    )
    XCTAssertEqual(enrollmentEvidence.authority, .ratifiedUserContract)
    XCTAssertEqual(enrollmentEvidence.runID, request.runID)
    XCTAssertEqual(enrollmentEvidence.contractID, ratified.contract.id)
    XCTAssertEqual(
      enrollmentEvidence.ratificationReceiptID,
      ratified.receipt.receiptID
    )
    XCTAssertEqual(
      enrollmentEvidence.journalFrameDigest,
      receipt.journalTransaction.frameDigest
    )
    XCTAssertEqual(
      enrollmentEvidence.journalEndingSequence,
      receipt.journalTransaction.endingSequence
    )
    let registrations = try await fixture.registry.registrations(limit: 8)
    XCTAssertEqual(registrations, [receipt.registration])

    let recoveredJournal = try RunJournal(
      rootDirectory: receipt.registration.journalRoot,
      runID: request.runID
    )
    let recoveredContract = await recoveredJournal.currentContract()
    XCTAssertEqual(recoveredContract, ratified.contract)
    let projection = await recoveredJournal.currentProjection()
    XCTAssertEqual(projection.phase, .ready)
    let recoveredTransaction = await recoveredJournal.transactionReceipt(
      commandID: request.createCommandID
    )
    XCTAssertEqual(
      receipt.journalTransaction,
      recoveredTransaction
    )

    let startup = try await WorkspaceMutationRecoveryCoordinator(
      registry: fixture.registry
    ).recoverRegisteredRuns()
    XCTAssertEqual(startup.registeredRunCount, 1)
    XCTAssertEqual(startup.runReports.first?.kernelProjection, projection)
    XCTAssertFalse(startup.requiresAttention)
  }

  func testReadOnlyDiscoveryRatificationCannotCreateJournalOrRegistration() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    var ambiguous = try candidate(workspace: fixture.workspace)
    let source = ambiguous.sources[0]
    ambiguous.ambiguities = [
      TaskContractAmbiguity(
        id: TaskContractAmbiguityID("authority-gap"),
        sourceSpans: [
          TaskContractSourceSpan(
            sourceID: source.id,
            sourceDigest: source.digest,
            lowerUTF8Offset: 0,
            upperUTF8Offset: source.exactUTF8.count
          )
        ],
        impact: .authorityScope,
        reversible: false,
        resolution: .denyPendingAuthority
      )
    ]
    let ratified = try ratifiedContract(candidate: ambiguous)
    XCTAssertEqual(ratified.receipt.executionEligibility, .readOnlyDiscovery)

    do {
      _ = try await fixture.coordinator.enroll(
        fixture.request(ratifiedContract: ratified)
      )
      XCTFail("read-only discovery authority must not enroll execution")
    } catch let error as KernelRunEnrollmentError {
      XCTAssertEqual(
        error,
        .executionAuthorityWithheld([TaskContractAmbiguityID("authority-gap")])
      )
    }
    let registrations = try await fixture.registry.registrations(limit: 8)
    XCTAssertTrue(registrations.isEmpty)
    let journalPath = fixture.container
      .appendingPathComponent(
        "registry/runs/enrollment-run/journal/enrollment-run/journal.ndjson"
      )
      .path
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: journalPath
      ))
  }

  func testLegacyContractWithoutExecutionIdentityCannotEnroll() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    var legacy = try candidate(workspace: fixture.workspace)
    legacy.contract.executionProfile = nil
    legacy.executionProfileSourceBinding = nil
    let ratified = try ratifiedContract(candidate: legacy)

    do {
      _ = try await fixture.coordinator.enroll(
        fixture.request(ratifiedContract: ratified)
      )
      XCTFail("execution identity must be ratified before enrollment")
    } catch let error as KernelRunEnrollmentError {
      XCTAssertEqual(error, .executionProfileMissing)
    }
    let registrations = try await fixture.registry.registrations(limit: 8)
    XCTAssertTrue(registrations.isEmpty)
  }

  func testDuplicateCommandIDCannotEnrollDifferentPreexistingContract() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(candidate: try candidate(workspace: fixture.workspace))
    let request = fixture.request(ratifiedContract: ratified)
    let registration = try await fixture.registry.registrationCandidate(
      runID: request.runID,
      actorIdentity: request.actorIdentity,
      workspaceID: request.workspaceID,
      workspaceRoot: request.workspaceRoot,
      hostBudget: request.hostBudget,
      maximumDispatchBatch: request.maximumDispatchBatch,
      registeredAt: request.enrolledAt
    )
    let journal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: request.runID
    )
    var conflictingContract = ratified.contract
    conflictingContract.id = TaskContractID("conflicting-contract")
    _ = try await journal.transactAtCurrentSequence(
      .createRun(conflictingContract),
      commandID: request.createCommandID,
      issuedAt: request.enrolledAt,
      actor: request.actorIdentity
    )

    do {
      _ = try await fixture.coordinator.enroll(request)
      XCTFail("an idempotency key must not hide a different run contract")
    } catch let error as KernelRunEnrollmentError {
      XCTAssertEqual(error, .journalProjectionMismatch)
    }
    let registrations = try await fixture.registry.registrations(limit: 8)
    XCTAssertTrue(registrations.isEmpty)
    let retainedContract = await journal.currentContract()
    XCTAssertEqual(retainedContract, conflictingContract)
  }

  func testRatificationReceiptCannotAuthorizeMoreThanOneRun() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(candidate: try candidate(workspace: fixture.workspace))
    let first = fixture.request(ratifiedContract: ratified)
    _ = try await fixture.coordinator.enroll(first)

    var replay = fixture.request(ratifiedContract: ratified)
    replay.runID = KernelRunID("replayed-enrollment-run")
    replay.createCommandID = RunCommandID("replayed-enrollment-create")
    replay.enrolledAt = Date(timeIntervalSince1970: 5)
    do {
      _ = try await fixture.coordinator.enroll(replay)
      XCTFail("one native confirmation must not authorize multiple runs")
    } catch let error as WorkspaceMutationRecoveryRegistryError {
      XCTAssertEqual(error, .ratificationReceiptAlreadyConsumed)
    }

    let registrations = try await fixture.registry.registrations(limit: 8)
    XCTAssertEqual(registrations.map(\.runID), [first.runID])
    let replayJournal = fixture.container.appendingPathComponent(
      "registry/runs/replayed-enrollment-run/journal/replayed-enrollment-run/journal.ndjson"
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: replayJournal.path))
  }

  func testWorkspaceSelectedByUserCannotBeSwappedBeforeEnrollment() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let otherWorkspace = fixture.container.appendingPathComponent(
      "other-workspace",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: otherWorkspace,
      withIntermediateDirectories: true
    )
    var swapped = fixture.request(ratifiedContract: ratified)
    swapped.workspaceRoot = otherWorkspace

    do {
      _ = try await fixture.coordinator.enroll(swapped)
      XCTFail("ratified workspace authority must not be transferable")
    } catch let error as KernelRunEnrollmentError {
      XCTAssertEqual(error, .workspaceBindingMismatch)
    }
    let registrations = try await fixture.registry.registrations(limit: 8)
    XCTAssertTrue(registrations.isEmpty)
    let journal = fixture.container.appendingPathComponent(
      "registry/runs/enrollment-run/journal/enrollment-run/journal.ndjson"
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
  }

  func testExecutionPreparationIsInertUntilExactActivation() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false
      ))
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let preparationRequest = try await fixture.preparationRequest(enrollment: enrollment)

    let prepared = try await fixture.executionCoordinator.prepare(
      preparationRequest
    )

    XCTAssertEqual(prepared.kernelProjection.phase, .ready)
    XCTAssertEqual(prepared.kernelProjection.activeAttemptID, nil)
    XCTAssertEqual(prepared.transactions.count, 4)
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let preparedState = await journal.state
    XCTAssertTrue(preparedState.runtimeLiveLeases.isEmpty)

    let activated = try await fixture.executionCoordinator.activate(
      KernelExecutionActivationRequest(
        enrollment: enrollment,
        preparation: prepared,
        actorIdentity: preparationRequest.actorIdentity,
        startCommandID: RunCommandID("activate-attempt"),
        issuedAt: Date(timeIntervalSince1970: 6)
      )
    )

    XCTAssertEqual(activated.kernelProjection.phase, .executing)
    XCTAssertEqual(
      activated.kernelProjection.activeAttemptID,
      preparationRequest.admission.attemptID
    )
    XCTAssertEqual(activated.proof.runID, enrollment.runID)
    XCTAssertEqual(activated.proof.attemptID, preparationRequest.admission.attemptID)
    XCTAssertEqual(
      activated.proof.workerExecutionProfile,
      ratified.contract.executionProfile?.worker
    )
    XCTAssertEqual(activated.proof.activationActor, preparationRequest.actorIdentity)
    XCTAssertEqual(
      activated.proof.activationTransaction,
      activated.journalTransaction
    )
    let activatedState = await journal.state
    XCTAssertTrue(activatedState.runtimeLiveLeases.isEmpty)
  }

  func testNativeConfirmedDesignBaselineFreezesThroughProductionPreparation()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let artifact = TaskContractCompiler.digest(Data("protected-artifact".utf8))
    var compilation = try candidate(
      workspace: fixture.workspace,
      mutationCapable: false
    )
    compilation.contract.protectedBaselines = [
      BaselineReference(
        id: BaselineID("protected-native-design"),
        artifactDigest: artifact,
        environmentDigest: TaskContractCompiler.digest(
          Data("native-environment".utf8)
        ),
        preservationRequired: true
      )
    ]
    let user = compilation.sources[0].author
    let ratified = try ratifiedContract(candidate: compilation)
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let selection = nativeDesignBaselineSelection(
      contractID: ratified.contract.id,
      artifact: artifact
    )
    let draft: NativeDesignBaselineConfirmationDraft
    switch NativeDesignBaselineAuthor.prepare(
      selection: selection,
      ratifiedContract: ratified,
      enrollment: enrollment,
      preparedAt: Date(timeIntervalSince1970: 5)
    ) {
    case .success(let value):
      draft = value
    case .failure(let error):
      XCTFail("unexpected baseline authoring failure: \(error)")
      return
    }

    let issuer = await MainActor.run {
      NativeDesignBaselineConfirmationIssuer()
    }
    let authorized: AuthorizedKernelDesignBaseline
    switch await MainActor.run(body: {
      issuer.confirmFromNativeUserAction(
        draft,
        displayedSelectionDigest: draft.selectionDigest,
        userActor: user,
        confirmedAt: Date(timeIntervalSince1970: 6)
      )
    }) {
    case .success(let value):
      authorized = value
    case .failure(let error):
      XCTFail("unexpected baseline confirmation failure: \(error)")
      return
    }

    let missingLiveBaseline =
      try await fixture
      .productionExecutionCoordinator.nativeExecutionReadiness(
        for: enrollment
      )
    XCTAssertEqual(
      missingLiveBaseline.blockers,
      [.designBaselineAuthorityMissing]
    )
    let baselineReady = try await fixture.productionExecutionCoordinator
      .nativeExecutionReadiness(
        for: enrollment,
        designBaseline: authorized
      )
    XCTAssertTrue(baselineReady.canPrepareAndActivate)
    XCTAssertTrue(baselineReady.blockers.isEmpty)

    var request = try await fixture.preparationRequest(
      enrollment: enrollment
    )
    request.designBaseline = authorized
    request.baselineCommandID = RunCommandID("prepare-native-baseline")
    request.issuedAt = Date(timeIntervalSince1970: 7)
    let prepared = try await fixture.executionCoordinator.prepare(request)

    XCTAssertEqual(prepared.transactions.count, 5)
    XCTAssertEqual(prepared.designBaselineID, selection.id)
    XCTAssertTrue(prepared.kernelProjection.designBaselineFrozen)
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await journal.state
    XCTAssertEqual(state.designBaseline, authorized.baseline)
    XCTAssertEqual(state.designBaseline?.authority.authority, user)
    XCTAssertEqual(
      state.designBaseline?.authority.authorityRole,
      "productDesignAuthority"
    )
    XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
  }

  func testNativeDesignBaselineAuthorityRejectsCrossWiringAndIsSingleUse()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let artifact = TaskContractCompiler.digest(Data("protected-artifact".utf8))
    var compilation = try candidate(
      workspace: fixture.workspace,
      mutationCapable: false
    )
    compilation.contract.protectedBaselines = [
      BaselineReference(
        id: BaselineID("protected-native-design"),
        artifactDigest: artifact,
        environmentDigest: nil,
        preservationRequired: true
      )
    ]
    let user = compilation.sources[0].author
    let ratified = try ratifiedContract(candidate: compilation)
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let selection = nativeDesignBaselineSelection(
      contractID: ratified.contract.id,
      artifact: artifact
    )

    var crossWiredEnrollment = enrollment
    crossWiredEnrollment.candidateDigest = TaskContractCompiler.digest(
      Data("other-candidate".utf8)
    )
    guard
      case .failure(let crossWireError) =
        NativeDesignBaselineAuthor.prepare(
          selection: selection,
          ratifiedContract: ratified,
          enrollment: crossWiredEnrollment,
          preparedAt: Date(timeIntervalSince1970: 5)
        )
    else {
      XCTFail("cross-wired enrollment must be rejected")
      return
    }
    XCTAssertEqual(crossWireError, .invalidEnrollment)

    var wrongArtifact = selection
    wrongArtifact.builtArtifact = TaskContractCompiler.digest(
      Data("wrong-artifact".utf8)
    )
    guard
      case .failure(.invalidSelection(let artifactIssues)) =
        NativeDesignBaselineAuthor.prepare(
          selection: wrongArtifact,
          ratifiedContract: ratified,
          enrollment: enrollment,
          preparedAt: Date(timeIntervalSince1970: 5)
        )
    else {
      XCTFail("cross-wired protected artifact must be rejected")
      return
    }
    XCTAssertTrue(
      artifactIssues.contains {
        $0.contains("preservation-required contract reference")
      })

    let draft: NativeDesignBaselineConfirmationDraft
    switch NativeDesignBaselineAuthor.prepare(
      selection: selection,
      ratifiedContract: ratified,
      enrollment: enrollment,
      preparedAt: Date(timeIntervalSince1970: 5)
    ) {
    case .success(let value): draft = value
    case .failure(let error):
      XCTFail("unexpected baseline authoring failure: \(error)")
      return
    }
    let issuer = await MainActor.run {
      NativeDesignBaselineConfirmationIssuer()
    }
    let changedDigest = TaskContractCompiler.digest(
      Data("changed-display".utf8)
    )
    let changedDisplayResult = await MainActor.run(body: {
      issuer.confirmFromNativeUserAction(
        draft,
        displayedSelectionDigest: changedDigest,
        userActor: user,
        confirmedAt: Date(timeIntervalSince1970: 6)
      )
    })
    guard case .failure(let changedDisplayError) = changedDisplayResult else {
      XCTFail("changed displayed baseline digest must be rejected")
      return
    }
    XCTAssertEqual(changedDisplayError, .displayedSelectionChanged)
    var wrongUser = user
    wrongUser.lineageDigest = TaskContractCompiler.digest(
      Data("other-user-lineage".utf8)
    )
    let crossWiredUser = wrongUser
    let wrongUserResult = await MainActor.run(body: {
      issuer.confirmFromNativeUserAction(
        draft,
        displayedSelectionDigest: draft.selectionDigest,
        userActor: crossWiredUser,
        confirmedAt: Date(timeIntervalSince1970: 6)
      )
    })
    guard case .failure(let wrongUserError) = wrongUserResult else {
      XCTFail("cross-wired user lineage must be rejected")
      return
    }
    XCTAssertEqual(wrongUserError, .userIdentityMismatch)

    let first = await MainActor.run(body: {
      issuer.confirmFromNativeUserAction(
        draft,
        displayedSelectionDigest: draft.selectionDigest,
        userActor: user,
        confirmedAt: Date(timeIntervalSince1970: 6)
      )
    })
    guard case .success(let authorized) = first else {
      XCTFail("exact native confirmation must mint authority")
      return
    }

    var rawEvidenceRequest = try await fixture.preparationRequest(
      enrollment: enrollment
    )
    rawEvidenceRequest.designBaseline = .testOnly(
      baseline: authorized.baseline
    )
    rawEvidenceRequest.baselineCommandID = RunCommandID(
      "unbound-baseline-evidence"
    )
    rawEvidenceRequest.issuedAt = Date(timeIntervalSince1970: 7)
    do {
      _ = try await fixture.executionCoordinator.prepare(
        rawEvidenceRequest
      )
      XCTFail("raw durable baseline evidence must not authorize preparation")
    } catch let error as KernelExecutionPreparationError {
      guard case .invalidPreparation(let reason) = error else {
        XCTFail("unexpected raw-evidence rejection: \(error)")
        return
      }
      XCTAssertTrue(reason.contains("exact enrollment"))
    }
    let untouchedJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let untouchedSequence = await untouchedJournal.state.sequence
    XCTAssertEqual(
      untouchedSequence,
      enrollment.journalTransaction.endingSequence
    )
    let duplicateResult = await MainActor.run(body: {
      issuer.confirmFromNativeUserAction(
        draft,
        displayedSelectionDigest: draft.selectionDigest,
        userActor: user,
        confirmedAt: Date(timeIntervalSince1970: 7)
      )
    })
    guard case .failure(let duplicateError) = duplicateResult else {
      XCTFail("one displayed selection must not mint duplicate authority")
      return
    }
    XCTAssertEqual(duplicateError, .alreadyConfirmed)
    XCTAssertFalse(
      AuthorizedKernelDesignBaseline.self is any Codable.Type
    )
    XCTAssertFalse(
      NativeDesignBaselineConfirmationDraft.self is any Codable.Type
    )
  }

  func testProductionCompositionCreatesTypedSessionWithoutLegacyController() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let preparation = try await fixture.preparationRequest(enrollment: enrollment)

    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: preparation,
        startCommandID: RunCommandID("production-start"),
        activatedAt: Date(timeIntervalSince1970: 6)
      )
    )

    let receipt = await session.receipt
    XCTAssertEqual(receipt.preparation.runID, enrollment.runID)
    XCTAssertEqual(receipt.preparation.kernelProjection.phase, .ready)
    XCTAssertEqual(receipt.kernelProjection.phase, .executing)
    XCTAssertEqual(
      receipt.kernelProjection.activeAttemptID,
      preparation.admission.attemptID
    )
    let runtime = await session.runtimeProjection()
    XCTAssertTrue(runtime.adapter.liveHandles.isEmpty)
    XCTAssertTrue(runtime.inDoubtResourceIDs.isEmpty)

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recovered.state
    XCTAssertEqual(state.phase, .executing)
    XCTAssertEqual(state.activeAttemptID, preparation.admission.attemptID)
    XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
  }

  func testProductionSessionFinalCompletionVetoPreservesExactJournalHead()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: try await fixture.preparationRequest(
          enrollment: enrollment
        ),
        startCommandID: RunCommandID("production-final-veto-start"),
        activatedAt: Date(timeIntervalSince1970: 6)
      )
    )
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let before = await journal.headSnapshot()

    do {
      _ = try await session.authorizeFinalCompletion()
      XCTFail("an active production attempt must not authorize completion")
    } catch let error as JournaledKernelCompletionError {
      guard case .invalidState(let issues) = error else {
        return XCTFail("unexpected completion rejection: \(error)")
      }
      XCTAssertTrue(issues.contains("completion must already be reducer-requested"))
      XCTAssertTrue(issues.contains("active attempt remains"))
      XCTAssertTrue(issues.contains("mandatory requirements remain unaccepted"))
    }
    let after = await journal.headSnapshot()
    let authorization = await journal.completionAuthorizationReceipt()
    let state = await journal.state
    XCTAssertEqual(after, before)
    XCTAssertNil(authorization)
    XCTAssertEqual(state.phase, .executing)
  }

  func testProductionSessionVisualEvaluationUsesExactRetainedExecutionState()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: try await fixture.preparationRequest(
          enrollment: enrollment
        ),
        startCommandID: RunCommandID("production-visual-veto-start"),
        activatedAt: Date(timeIntervalSince1970: 6)
      )
    )
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let before = await journal.headSnapshot()

    do {
      _ = try await session.evaluateNativeVisualReview(.testOnlyInvalid())
      XCTFail("an active production attempt must not evaluate visual evidence")
    } catch let error as JournaledNativeVisualEvaluationError {
      XCTAssertEqual(
        error,
        .invalidReducerState(
          "visual issuance requires one completed exact attempt and frozen baseline"
        )
      )
    }
    let after = await journal.headSnapshot()
    let projection = await journal.currentProjection()
    XCTAssertEqual(after, before)
    XCTAssertEqual(projection.phase, .executing)
    XCTAssertEqual(projection.visualEvaluationCount, 0)
  }

  func testProductionSessionInvokesExternalDependencyContainmentVeto()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let observer = externalDependencyObserver()
    let dependency = try externalDependencyContract(
      observer: observer,
      emitsCanonicalResult: false
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false,
        externalDependencies: [dependency]
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: try await fixture.preparationRequest(
          enrollment: enrollment
        ),
        startCommandID: RunCommandID(
          "production-dependency-veto-start"
        ),
        activatedAt: Date(timeIntervalSince1970: 6)
      )
    )
    let request = productionExternalDependencyRequest(
      observer: observer,
      workspace: fixture.workspace,
      prefix: "production-dependency-veto"
    )
    let outcome = try await session.observeExternalDependency(request)
    guard case .vetoed(let receipt, let transaction) = outcome else {
      return XCTFail("ordinary production must retain the containment veto")
    }
    XCTAssertEqual(
      receipt.reason,
      .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
    )
    XCTAssertFalse(transaction.duplicate)
    let retried = try await session.observeExternalDependency(request)
    guard case .vetoed(let retriedReceipt, let retriedTransaction) = retried else {
      return XCTFail("exact veto retry must return the retained veto")
    }
    XCTAssertEqual(retriedReceipt, receipt)
    XCTAssertEqual(retriedTransaction, transaction)

    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await journal.state
    XCTAssertEqual(
      state.externalDependencyObservationActivationReceipts?.count,
      1
    )
    XCTAssertEqual(
      state.externalDependencyObservationLaunchVetoReceipts?.count,
      1
    )
    XCTAssertTrue(
      (state.externalDependencyObservationRuntimeLaunchReceipts ?? [:])
        .isEmpty
    )
    XCTAssertTrue((state.externalDependencyReceipts ?? [:]).isEmpty)
    XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
    let projection = await session.runtimeProjection()
    XCTAssertTrue(projection.adapter.liveHandles.isEmpty)
    XCTAssertTrue(projection.inDoubtResourceIDs.isEmpty)
  }

  func testProductionSessionCompletesNativeExternalDependencyAndReplays()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let observer = externalDependencyObserver()
    let dependency = try externalDependencyContract(
      observer: observer,
      emitsCanonicalResult: true
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false,
        externalDependencies: [dependency]
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(
        ratifiedContract: ratified,
        hostBudget: HostResourceBudget(
          nominal: ResourceVector(
            cpuWeight: 4,
            memoryBytes: 1_073_741_824,
            diskIOWeight: 4,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 4
          ))
      )
    )
    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: try await fixture.preparationRequest(
          enrollment: enrollment
        ),
        startCommandID: RunCommandID(
          "production-dependency-observe-start"
        ),
        activatedAt: Date(timeIntervalSince1970: 6)
      )
    )
    let request = productionExternalDependencyRequest(
      observer: observer,
      workspace: fixture.workspace,
      prefix: "production-dependency-observe"
    )
    let outcome = try await session.observeExternalDependency(
      request,
      residentMemoryEnforcementResolver: { activation in
        .authorized(
          AuthorizedKernelResidentMemoryEnforcement.testOnly(
            externalDependencyActivation: activation
          )
        )
      }
    )
    guard case .observed(let completed) = outcome else {
      return XCTFail("test-only containment must exercise the native chain")
    }
    XCTAssertEqual(completed.release.exit.exitCode, 0)
    XCTAssertEqual(completed.result.mapping.availability, .available)
    XCTAssertEqual(
      completed.observation.observation.sourceResultID,
      completed.result.id
    )

    let replayed = try await session.observeExternalDependency(request)
    guard case .observed(let replayedCompletion) = replayed else {
      return XCTFail("exact controller retry must replay the observation")
    }
    XCTAssertEqual(replayedCompletion.result, completed.result)
    XCTAssertEqual(
      replayedCompletion.observation.observation,
      completed.observation.observation
    )
    XCTAssertEqual(
      replayedCompletion.observation.transaction,
      completed.observation.transaction
    )
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let sequenceBeforeCrossWire = await journal.state.sequence
    var crossWired = request
    crossWired.runtime.launchReceiptID = ReceiptID(
      "cross-wired-production-dependency-launch"
    )
    do {
      _ = try await session.observeExternalDependency(crossWired)
      XCTFail("recovery must reject a substituted native launch identity")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(
        error,
        .externalDependencyObservationRequestInvalid
      )
    }
    let state = await journal.state
    XCTAssertEqual(state.sequence, sequenceBeforeCrossWire)
    XCTAssertEqual(
      state.externalDependencyObservationRuntimeLaunchReceipts?.count,
      1
    )
    XCTAssertEqual(state.externalDependencyReceipts?.count, 1)
    XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
    let projection = await session.runtimeProjection()
    XCTAssertTrue(projection.adapter.liveHandles.isEmpty)
    XCTAssertTrue(projection.inDoubtResourceIDs.isEmpty)
  }

  func testProductionCompositionRejectsMutationBeforeCandidateIsolation()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(
        ratifiedContract: ratified,
        hostBudget: HostResourceBudget(
          nominal: ResourceVector(
            cpuWeight: 0,
            memoryBytes: 0,
            diskIOWeight: 1,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 0
          ))
      )
    )
    let preparation = try await fixture.preparationRequest(
      enrollment: enrollment
    )

    do {
      _ = try await fixture.productionExecutionCoordinator.activate(
        KernelProductionExecutionCompositionRequest(
          preparation: preparation,
          startCommandID: RunCommandID("mutation-start-must-not-exist"),
          activatedAt: Date(timeIntervalSince1970: 6)
        )
      )
      XCTFail("canonical-workspace mutation must require isolated candidate authority")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(
        error,
        .preApplyCandidateIsolationAuthorityMissing
      )
    }

    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await journal.state
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertEqual(state.phase, .ready)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertTrue(state.attempts.isEmpty)
  }

  func testPreApplyCandidateIsolationCopiesRatifiedBytesOutsideWorkspaceAndIsInert()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let sourceFile = fixture.workspace.appendingPathComponent("Sources/Main.swift")
    try FileManager.default.createDirectory(
      at: sourceFile.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("let baseline = 1\n".utf8).write(to: sourceFile)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let coordinator = WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    )

    let authority = try await coordinator.isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { authority.close() }

    let receipt = authority.receipt
    let candidateRoot = URL(
      fileURLWithPath: receipt.candidateRootPath,
      isDirectory: true
    )
    XCTAssertTrue(
      receipt.candidateRootPath.hasPrefix(
        enrollment.registration.journalRoot
          .deletingLastPathComponent()
          .appendingPathComponent("execution")
          .path + "/"
      ))
    XCTAssertFalse(
      receipt.candidateRootPath.hasPrefix(
        fixture.workspace.path + "/"
      ))
    XCTAssertEqual(receipt.runID, enrollment.runID)
    XCTAssertEqual(receipt.contractID, enrollment.contractID)
    XCTAssertEqual(receipt.attemptID, AttemptID("enrollment-attempt"))
    XCTAssertEqual(receipt.nodeID, KernelNodeID("enrollment-node"))
    XCTAssertEqual(receipt.sourceRevision, ratified.contract.sourceRevision?.sourceRevision)
    XCTAssertEqual(receipt.fileCount, 1)
    XCTAssertTrue(receipt.validationIssues().isEmpty)
    var tamperedReceipt = receipt
    tamperedReceipt.totalBytes += 1
    XCTAssertEqual(
      tamperedReceipt.validationIssues(),
      ["pre-apply isolation receipt digest mismatch"]
    )
    XCTAssertEqual(
      try Data(contentsOf: candidateRoot.appendingPathComponent("Sources/Main.swift")),
      Data("let baseline = 1\n".utf8)
    )
    let permissions =
      try FileManager.default.attributesOfItem(
        atPath: candidateRoot.appendingPathComponent("Sources/Main.swift").path
      )[.posixPermissions] as? NSNumber
    XCTAssertEqual((permissions?.intValue ?? 0) & 0o200, 0o200)
    XCTAssertEqual(
      try coordinator.revalidatePristine(authority),
      receipt
    )

    let readiness = try await fixture.productionExecutionCoordinator
      .nativeExecutionReadiness(for: enrollment)
    XCTAssertEqual(
      readiness.blockers,
      [
        .preApplyCandidateIsolationAuthorityMissing,
        .journaledMutationPreparationAuthorityMissing,
      ]
    )

    try Data("let baseline = 2\n".utf8).write(
      to: candidateRoot.appendingPathComponent("Sources/Main.swift")
    )
    XCTAssertEqual(
      try Data(contentsOf: sourceFile),
      Data("let baseline = 1\n".utf8)
    )
    XCTAssertThrowsError(try coordinator.revalidatePristine(authority))

    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await journal.state
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertEqual(state.phase, .ready)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertTrue(state.attempts.isEmpty)
  }

  func testPreApplyCandidateIsolationRejectsCandidateRootPathReplacement()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let sourceFile = fixture.workspace.appendingPathComponent("main.swift")
    try Data("let baseline = 1\n".utf8).write(to: sourceFile)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let coordinator = WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    )
    let authority = try await coordinator.isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { authority.close() }

    let root = URL(
      fileURLWithPath: authority.receipt.candidateRootPath,
      isDirectory: true
    )
    let displaced = root.deletingLastPathComponent()
      .appendingPathComponent("displaced", isDirectory: true)
    try FileManager.default.moveItem(at: root, to: displaced)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    try Data("let impostor = true\n".utf8).write(
      to: root.appendingPathComponent("main.swift")
    )

    XCTAssertThrowsError(try coordinator.revalidatePristine(authority))
  }

  func testPreApplyCandidateIsolationRejectsSourceDriftBeforeCreatingAuthority()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let sourceFile = fixture.workspace.appendingPathComponent("main.swift")
    try Data("let baseline = 1\n".utf8).write(to: sourceFile)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    try Data("let drift = true\n".utf8).write(to: sourceFile)

    do {
      _ = try await WorkspacePreApplyCandidateIsolationCoordinator(
        registry: fixture.registry
      ).isolate(
        enrollment: enrollment,
        attemptID: AttemptID("enrollment-attempt"),
        nodeID: KernelNodeID("enrollment-node"),
        isolatedAt: Date(timeIntervalSince1970: 5)
      )
      XCTFail("source drift must not issue candidate authority")
    } catch let error as WorkspacePreApplyCandidateIsolationError {
      XCTAssertEqual(error, .sourceRevisionMismatch)
    }
    let candidateDirectory = enrollment.registration.journalRoot
      .deletingLastPathComponent()
      .appendingPathComponent("execution")
      .appendingPathComponent("preapply-candidates")
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: candidateDirectory.path
      ))
  }

  func testPreApplyCandidateIsolationIsJournaledRecoveredReceiptOnlyAndRemainsInert()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = fixture.workspace.appendingPathComponent("main.swift")
    try Data("let isolatedBaseline = 1\n".utf8).write(to: source)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let authority = try await WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    ).isolate(
      enrollment: enrollment,
      attemptID: AttemptID("isolated-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { authority.close() }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )

    let transaction = try await journal.recordPreApplyCandidateIsolation(
      authority,
      commandID: RunCommandID("accept-preapply-isolation")
    )

    XCTAssertFalse(transaction.duplicate)
    let acceptedReceipt = await journal.preApplyCandidateIsolationReceipt(
      transaction: transaction
    )
    XCTAssertEqual(acceptedReceipt, authority.receipt)
    let state = await journal.state
    XCTAssertEqual(
      state.sequence,
      enrollment.journalTransaction.endingSequence + 1
    )
    XCTAssertEqual(state.phase, .ready)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertTrue(state.attempts.isEmpty)
    XCTAssertEqual(
      state.preApplyCandidateIsolationReceipts?[
        authority.receipt.attemptID
      ],
      authority.receipt
    )

    let journalURL = await journal.journalURL
    let serialized = try String(contentsOf: journalURL, encoding: .utf8)
    XCTAssertFalse(serialized.contains("rootDescriptor"))
    XCTAssertFalse(serialized.contains("let isolatedBaseline = 1"))

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let recoveredReceipt = await recovered.preApplyCandidateIsolationReceipt(
      attemptID: authority.receipt.attemptID
    )
    XCTAssertEqual(recoveredReceipt, authority.receipt)
    let recoveredTransaction = await recovered.transactionReceipt(
      commandID: RunCommandID("accept-preapply-isolation")
    )
    XCTAssertEqual(recoveredTransaction, transaction)

    let preparation = try await fixture.preparationRequest(
      enrollment: enrollment
    )
    do {
      _ = try await fixture.productionExecutionCoordinator.activate(
        KernelProductionExecutionCompositionRequest(
          preparation: preparation,
          startCommandID: RunCommandID("must-remain-inert"),
          activatedAt: Date(timeIntervalSince1970: 6)
        )
      )
      XCTFail("receipt acceptance must not activate mutation execution")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .preApplyCandidateIsolationAuthorityMissing)
    }
  }

  func testPreApplyCandidateIsolationDuplicateRequiresLivePristineAuthority()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = fixture.workspace.appendingPathComponent("main.swift")
    try Data("let isolatedBaseline = 1\n".utf8).write(to: source)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let authority = try await WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    ).isolate(
      enrollment: enrollment,
      attemptID: AttemptID("isolated-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { authority.close() }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let commandID = RunCommandID("accept-preapply-isolation")
    let first = try await journal.recordPreApplyCandidateIsolation(
      authority,
      commandID: commandID
    )
    let duplicate = try await journal.recordPreApplyCandidateIsolation(
      authority,
      commandID: commandID
    )
    XCTAssertFalse(first.duplicate)
    XCTAssertTrue(duplicate.duplicate)

    try Data("let candidateWasMutated = true\n".utf8).write(
      to: URL(
        fileURLWithPath: authority.receipt.candidateRootPath,
        isDirectory: true
      ).appendingPathComponent("main.swift")
    )
    let before = await journal.headSnapshot()
    do {
      _ = try await journal.recordPreApplyCandidateIsolation(
        authority,
        commandID: commandID
      )
      XCTFail("duplicate delivery must revalidate live pristine authority")
    } catch let error as RunJournalError {
      XCTAssertEqual(error, .preApplyCandidateIsolationAuthorityStale)
    }
    let after = await journal.headSnapshot()
    XCTAssertEqual(after, before)
  }

  func testPreApplyCandidateIsolationCommandIdempotencyIsReceiptExact()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Data("let isolatedBaseline = 1\n".utf8).write(
      to: fixture.workspace.appendingPathComponent("main.swift")
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let coordinator = WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    )
    let firstAuthority = try await coordinator.isolate(
      enrollment: enrollment,
      attemptID: AttemptID("isolated-attempt-a"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { firstAuthority.close() }
    let conflictingAuthority = try await coordinator.isolate(
      enrollment: enrollment,
      attemptID: AttemptID("isolated-attempt-b"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { conflictingAuthority.close() }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let commandID = RunCommandID("accept-preapply-isolation")
    _ = try await journal.recordPreApplyCandidateIsolation(
      firstAuthority,
      commandID: commandID
    )
    let before = await journal.headSnapshot()

    do {
      _ = try await journal.recordPreApplyCandidateIsolation(
        conflictingAuthority,
        commandID: commandID
      )
      XCTFail("one command ID cannot hide different isolation authority")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .preApplyCandidateIsolationCommandConflict(
          commandID: commandID
        )
      )
    }
    let after = await journal.headSnapshot()
    XCTAssertEqual(after, before)
    let conflictingReceipt = await journal.preApplyCandidateIsolationReceipt(
      attemptID: conflictingAuthority.receipt.attemptID
    )
    XCTAssertNil(conflictingReceipt)
  }

  func testMutationActivationConsumesExactLiveIsolationAndBindsCandidateRoot()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Data("let canonicalBaseline = 1\n".utf8).write(
      to: fixture.workspace.appendingPathComponent("main.swift")
    )
    let worker = KernelAgentExecutionProfile(
      provider: .local,
      providerReference: "candidate-native-worker",
      executableContentDigest: try XCTUnwrap(
        ProcessGroupRuntimeAdapter.executableContentDigest(
          atPath: kernelProcessFixturePath
        )
      ),
      modelID: "candidate-native-model",
      reasoningEffort: nil,
      sandbox: .workspaceOnly,
      networkPolicy: .disabled,
      pluginPolicy: .disabled,
      environmentPolicy: .minimalKernelAllowlist,
      providerProtocol: .loopForgeProviderHarnessV2,
      providerHarnessMode: .productive
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        workerExecutionProfile: worker
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(
        ratifiedContract: ratified,
        hostBudget: HostResourceBudget(
          nominal: ResourceVector(
            cpuWeight: 1,
            memoryBytes: 1,
            diskIOWeight: 1,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 1
          ))
      )
    )
    let authority = try await WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    ).isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { authority.close() }
    let setupJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    _ = try await setupJournal.recordPreApplyCandidateIsolation(
      authority,
      commandID: RunCommandID("accept-preapply-isolation")
    )
    let preparation = try await fixture.preparationRequest(
      enrollment: enrollment
    )

    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: preparation,
        startCommandID: RunCommandID("activate-isolated-attempt"),
        activatedAt: Date(timeIntervalSince1970: 6),
        preApplyCandidateIsolation: authority
      )
    )

    let receipt = await session.receipt
    XCTAssertEqual(receipt.kernelProjection.phase, .executing)
    XCTAssertEqual(
      receipt.kernelProjection.activeAttemptID,
      authority.receipt.attemptID
    )
    XCTAssertEqual(
      receipt.preApplyCandidateIsolation,
      authority.receipt
    )
    let nativeInvocationNonce = "d219acfd-0a66-4430-b754-e18280369ad2"
    let invocation = try await session.prepareNativeProviderInvocation(
      requestNonce: nativeInvocationNonce
    )
    XCTAssertEqual(
      invocation.receipt.preApplyCandidateIsolation,
      authority.receipt
    )
    XCTAssertEqual(
      invocation.receipt.executionProfile.sandbox,
      .workspaceOnly
    )
    XCTAssertEqual(
      invocation.receipt.promptArtifact.fileName,
      "native-provider-\(nativeInvocationNonce).json"
    )
    let promptData = try Data(
      contentsOf: enrollment.registration.journalRoot
        .appendingPathComponent(enrollment.runID.rawValue, isDirectory: true)
        .appendingPathComponent(invocation.receipt.promptArtifact.fileName))
    XCTAssertEqual(promptData.last, 0x0a)
    let prompt = try JSONDecoder().decode(
      KernelNativeProviderPromptEnvelope.self,
      from: Data(promptData.dropLast())
    )
    XCTAssertEqual(prompt.contract, ratified.contract)
    XCTAssertEqual(prompt.plan, preparation.plan)
    XCTAssertEqual(prompt.admission, preparation.admission)
    XCTAssertEqual(prompt.runID, enrollment.runID)
    XCTAssertEqual(prompt.attemptID, authority.receipt.attemptID)
    XCTAssertEqual(prompt.nodeID, authority.receipt.nodeID)
    XCTAssertEqual(prompt.requestNonce, invocation.receipt.requestNonce)
    XCTAssertEqual(prompt.outputProtocol.schemaVersion, 1)
    XCTAssertEqual(
      prompt.outputProtocol.invocationDigestSource,
      "kernel-owned-canonical-json-context-fd:196"
    )
    XCTAssertEqual(
      prompt.outputProtocol.requestNonceSource,
      "kernel-owned-canonical-json-context-fd:196"
    )
    XCTAssertTrue(prompt.outputProtocol.terminalRequired)
    XCTAssertFalse(prompt.outputProtocol.standardOutputMayContainOtherBytes)
    do {
      _ = try await session.prepareNativeProviderInvocation(
        requestNonce: "d55df985-07ed-4231-b8db-3f91cc9aef50"
      )
      XCTFail("one active attempt must not prepare multiple provider prompts")
    } catch let error as KernelNativeProviderInvocationPreparationError {
      XCTAssertEqual(error, .invocationAlreadyPrepared)
    }
    let start = try await session.launchProvider(
      KernelProductionProviderLaunchRequest(
        leaseID: ResourceLeaseID("candidate-native-worker-lease"),
        resourceID: OwnedResourceID("candidate-native-worker-resource"),
        occurrenceID: nil,
        reservation: ResourceVector(
          cpuWeight: 1,
          memoryBytes: 1,
          diskIOWeight: 1,
          gpuWeight: 0,
          networkWeight: 0,
          guiSessionCount: 0,
          processCount: 1
        ),
        requestedAtMonotonicNanoseconds: 1,
        renewalDeadlineMonotonicNanoseconds: nil,
        executablePath: kernelProcessFixturePath,
        standardOutputFileName: "candidate-native-worker-stdout.jsonl",
        standardErrorFileName: "candidate-native-worker-stderr.txt",
        admissionReceiptID: ReceiptID("candidate-native-worker-admission"),
        admissionCommandID: RunCommandID("candidate-native-worker-admit"),
        bindingReceiptID: ReceiptID("candidate-native-worker-binding"),
        providerLaunchReceiptID: ReceiptID("candidate-native-worker-launch"),
        bindingCommandID: RunCommandID("candidate-native-worker-bind"),
        launchFailureReleaseReceiptID:
          ReceiptID("candidate-native-worker-failed-release"),
        launchFailureReleaseCommandID:
          RunCommandID("candidate-native-worker-failed-release")
      ),
      invocation: invocation,
      secretCapability: nil
    )
    XCTAssertEqual(
      start.launch.handle.externalIdentity.nativeSandboxAttestation?
        .candidateWorkingDirectory,
      KernelCandidateWorkingDirectoryAttestationReceipt(
        binding: .posixSpawnFileActionsFchdir,
        deviceID: authority.receipt.deviceID,
        inode: authority.receipt.inode
      )
    )
    let contextTransport = try XCTUnwrap(
      start.launch.providerInvocationContextTransport
    )
    XCTAssertTrue(contextTransport.isValid(for: invocation.receipt))
    XCTAssertEqual(
      contextTransport,
      start.launch.providerLaunch?.invocationContextTransport
    )
    let completion = try await session.completeProviderExecution(
      start: start,
      request: KernelProductionProviderCompletionRequest(
        naturalExitTimeoutNanoseconds: 10_000_000_000,
        releaseReceiptID:
          ReceiptID("candidate-native-worker-release"),
        releaseCommandID:
          RunCommandID("candidate-native-worker-release"),
        parseReceiptID: ReceiptID("candidate-native-worker-parse"),
        parseCommandID: RunCommandID("candidate-native-worker-parse"),
        derivationReceiptID:
          ReceiptID("candidate-native-worker-derive"),
        derivationCommandID:
          RunCommandID("candidate-native-worker-derive")
      )
    )
    XCTAssertEqual(completion.release.exit.exitCode, 0)
    XCTAssertEqual(completion.parse.parse.proposedDisposition, .completed)
    XCTAssertEqual(completion.parse.parse.threadID, "fixture-provider")
    XCTAssertEqual(completion.execution.execution.disposition, .completed)
    let runtimeProjection = await session.runtimeProjection()
    XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    XCTAssertTrue(runtimeProjection.inDoubtResourceIDs.isEmpty)
    do {
      _ = try WorkspaceCandidatePostimageMaterializer()
        .revalidatePreApplyIsolation(authority)
      XCTFail("activation must consume the original descriptor authority")
    } catch {
      XCTAssertTrue(true)
    }
    XCTAssertEqual(
      try String(
        contentsOf: fixture.workspace.appendingPathComponent(
          "main.swift"
        ), encoding: .utf8),
      "let canonicalBaseline = 1\n"
    )
  }

  @MainActor
  func testApplicationCrashRecoveryStopsLiveProductionProviderAndJournalsRelease()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Data("let canonicalBaseline = 1\n".utf8).write(
      to: fixture.workspace.appendingPathComponent("main.swift")
    )
    let worker = KernelAgentExecutionProfile(
      provider: .local,
      providerReference: "live-termination-worker",
      executableContentDigest: try XCTUnwrap(
        ProcessGroupRuntimeAdapter.executableContentDigest(
          atPath: kernelProcessFixturePath
        )
      ),
      modelID: "fixture-live-termination-model",
      reasoningEffort: nil,
      sandbox: .workspaceOnly,
      networkPolicy: .disabled,
      pluginPolicy: .disabled,
      environmentPolicy: .minimalKernelAllowlist,
      providerProtocol: .loopForgeProviderHarnessV2,
      providerHarnessMode: .productive
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        workerExecutionProfile: worker
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(
        ratifiedContract: ratified,
        hostBudget: HostResourceBudget(
          nominal: ResourceVector(
            cpuWeight: 1,
            memoryBytes: 1,
            diskIOWeight: 1,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 1
          )
        )
      )
    )
    let authority = try await WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    ).isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { authority.close() }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    _ = try await journal.recordPreApplyCandidateIsolation(
      authority,
      commandID: RunCommandID("accept-live-termination-isolation")
    )
    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: try await fixture.preparationRequest(
          enrollment: enrollment
        ),
        startCommandID: RunCommandID("activate-live-termination-attempt"),
        activatedAt: Date(timeIntervalSince1970: 6),
        preApplyCandidateIsolation: authority
      )
    )
    let invocation = try await session.prepareNativeProviderInvocation(
      requestNonce: "ab6aa02e-5cae-4b4b-9327-bce5bfc94510"
    )
    let resourceID = OwnedResourceID("live-termination-worker-resource")
    let leaseID = ResourceLeaseID("live-termination-worker-lease")
    let start = try await session.launchProvider(
      KernelProductionProviderLaunchRequest(
        leaseID: leaseID,
        resourceID: resourceID,
        occurrenceID: nil,
        reservation: ResourceVector(
          cpuWeight: 1,
          memoryBytes: 1,
          diskIOWeight: 1,
          gpuWeight: 0,
          networkWeight: 0,
          guiSessionCount: 0,
          processCount: 1
        ),
        requestedAtMonotonicNanoseconds: 1,
        renewalDeadlineMonotonicNanoseconds: nil,
        executablePath: kernelProcessFixturePath,
        standardOutputFileName: "live-termination-worker-stdout.jsonl",
        standardErrorFileName: "live-termination-worker-stderr.txt",
        admissionReceiptID: ReceiptID("live-termination-worker-admission"),
        admissionCommandID: RunCommandID("live-termination-worker-admit"),
        bindingReceiptID: ReceiptID("live-termination-worker-binding"),
        providerLaunchReceiptID: ReceiptID("live-termination-worker-launch"),
        bindingCommandID: RunCommandID("live-termination-worker-bind"),
        launchFailureReleaseReceiptID:
          ReceiptID("live-termination-worker-failed-release"),
        launchFailureReleaseCommandID:
          RunCommandID("live-termination-worker-failed-release")
      ),
      invocation: invocation,
      secretCapability: nil
    )
    let processID = start.launch.handle.processID
    defer { _ = Darwin.kill(processID, SIGKILL) }
    XCTAssertEqual(
      Darwin.kill(processID, 0),
      0,
      "the production provider must be live before application termination"
    )

    let recoveryReport = try await WorkspaceMutationRecoveryCoordinator(
      registry: fixture.registry
    ).recoverRegisteredRuns()
    XCTAssertEqual(
      recoveryReport.runReports.first(where: {
        $0.runID == enrollment.runID
      })?.kernelProjection?.phase,
      .executing
    )
    let recoveredModel = AppModel(
      store: TaskStore(
        storageURL: fixture.container.appendingPathComponent("tasks.json")
      ),
      workspaceMutationRecoveryTask: Task { recoveryReport },
      kernelRunEnrollmentCoordinator: fixture.coordinator,
      kernelExecutionCoordinator: fixture.productionExecutionCoordinator
    )
    for _ in 0..<500 {
      if recoveredModel.kernelRunProjections.first(where: {
        $0.runID == enrollment.runID
      })?.phase == .stopped { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }

    XCTAssertFalse(recoveredModel.hasActiveKernelExecutionSessions)
    XCTAssertNil(recoveredModel.latestKernelExecutionSessionReceipt)
    XCTAssertNil(recoveredModel.latestKernelEnrollmentReceipt)
    XCTAssertEqual(Darwin.kill(processID, 0), -1)
    XCTAssertEqual(errno, ESRCH)
    let recoveredJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recoveredJournal.state
    let projection = await recoveredJournal.currentProjection()
    XCTAssertEqual(state.phase, .stopped)
    XCTAssertNil(state.activeAttemptID)
    XCTAssertEqual(
      state.attempts.values.first?.disposition,
      .interrupted
    )
    XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
    XCTAssertTrue(state.runtimeFailedReleases.isEmpty)
    let release = try XCTUnwrap(
      state.runtimeReleaseReceipts.values.first(where: {
        $0.resourceID == resourceID && $0.leaseID == leaseID
      })
    )
    guard case .released = release.outcome else {
      return XCTFail("application crash recovery did not journal a release")
    }
    XCTAssertTrue(
      release.id.rawValue.hasPrefix("native-crash-recovery-")
    )
    XCTAssertEqual(
      release.managedProcessTermination?.handle.processID,
      processID
    )
    XCTAssertTrue(projection.quiescent)
    XCTAssertEqual(projection.phase, .stopped)
    XCTAssertTrue(
      state.quiescenceReceipt?.id.rawValue.hasPrefix(
        "native-crash-recovery-"
      ) == true
    )
  }

  @MainActor
  func testApplicationTerminationFailsRedForLiveProductionPostimageVerifier()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let baselineBytes = Data("let canonicalBaseline = 1\n".utf8)
    let candidateBytes = Data("let canonicalCandidate = 2\n".utf8)
    let canonicalFile = fixture.workspace.appendingPathComponent("main.swift")
    try baselineBytes.write(to: canonicalFile)

    let verifierExecutableDigest = try XCTUnwrap(
      ProcessGroupRuntimeAdapter.executableContentDigest(
        atPath: kernelProcessFixturePath
      )
    )
    let worker = KernelAgentExecutionProfile(
      provider: .local,
      providerReference: "live-quit-postimage-worker",
      executableContentDigest: verifierExecutableDigest,
      modelID: "live-quit-postimage-worker-model",
      reasoningEffort: nil,
      sandbox: .workspaceOnly,
      networkPolicy: .disabled,
      pluginPolicy: .disabled,
      environmentPolicy: .minimalKernelAllowlist,
      providerProtocol: .loopForgeProviderHarnessV2,
      providerHarnessMode: .productive
    )
    let verifierEvidenceDigest = String(repeating: "b", count: 64)
    let verifierProbe = RequirementVerificationExecutableProbe(
      schemaVersion: 2,
      transport: .localDirectProcess,
      executableContentDigest: verifierExecutableDigest,
      fixedArguments: [
        "--emit-verifier-result-and-sleep",
        "accepted",
        verifierEvidenceDigest,
        "30",
        "@loopforge-input:candidate-postimage",
      ],
      inputBindings: [
        RequirementVerificationInputBinding(
          id: "candidate-postimage",
          kind: .candidatePostimage,
          artifactID: "live-quit-candidate-postimage",
          argumentToken: "@loopforge-input:candidate-postimage"
        )
      ],
      environmentPolicy: .minimalKernelAllowlist,
      environmentIdentityDigest:
        KernelProcessEnvironmentAuthorizer
        .environmentDigest(
          KernelProcessEnvironmentAuthorizer.minimalEnvironment
        ),
      captureIdentityDigest: KernelPostimageVerifierCapturePolicy
        .identityDigest,
      parser: RequirementVerificationParserContract(
        id: "live-quit-postimage-parser",
        schemaVersion: 1,
        contentDigest: RequirementVerificationParserFormat
          .canonicalJSONResultV1.implementationIdentityDigest,
        format: .canonicalJSONResultV1
      ),
      resultMappings: [
        RequirementVerificationResultMapping(
          exitCode: 0,
          parserResultCode: "accepted",
          outcome: .accepted
        )
      ],
      unmatchedOutcome: .rejected,
      networkPolicy: .disabled,
      resourceLimits: RequirementVerificationResourceLimits(
        maximumWallClockSeconds: 60,
        maximumCapturedOutputBytes: 64 * 1_024,
        maximumResidentBytes: 64 * 1_024 * 1_024,
        maximumChildProcesses: 0
      )
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        workerExecutionProfile: worker,
        evidenceProbe: verifierProbe,
        additionalEvidenceProbes: [verifierProbe],
        writablePaths: ["main.swift"]
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(
        ratifiedContract: ratified,
        hostBudget: HostResourceBudget(
          nominal: ResourceVector(
            cpuWeight: 2,
            memoryBytes: 128 * 1_024 * 1_024,
            diskIOWeight: 2,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 2
          )
        )
      )
    )
    let isolation = try await WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    ).isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { isolation.close() }
    var journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    _ = try await journal.recordPreApplyCandidateIsolation(
      isolation,
      commandID: RunCommandID("accept-live-quit-postimage-isolation")
    )
    let session = try await fixture.productionExecutionCoordinator.activate(
      KernelProductionExecutionCompositionRequest(
        preparation: try await fixture.preparationRequest(
          enrollment: enrollment
        ),
        startCommandID: RunCommandID("activate-live-quit-postimage-attempt"),
        activatedAt: Date(timeIntervalSince1970: 6),
        preApplyCandidateIsolation: isolation
      )
    )
    journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )

    let invocation = try await session.prepareNativeProviderInvocation(
      requestNonce: "a4f39ab9-567f-4cff-bb31-b9c6bb083b5c"
    )
    let providerStart = try await session.launchProvider(
      KernelProductionProviderLaunchRequest(
        leaseID: ResourceLeaseID("live-quit-postimage-worker-lease"),
        resourceID: OwnedResourceID("live-quit-postimage-worker-resource"),
        occurrenceID: nil,
        reservation: ResourceVector(
          cpuWeight: 1,
          memoryBytes: 1,
          diskIOWeight: 1,
          gpuWeight: 0,
          networkWeight: 0,
          guiSessionCount: 0,
          processCount: 1
        ),
        requestedAtMonotonicNanoseconds: 1,
        renewalDeadlineMonotonicNanoseconds: nil,
        executablePath: kernelProcessFixturePath,
        standardOutputFileName: "live-quit-postimage-worker.stdout",
        standardErrorFileName: "live-quit-postimage-worker.stderr",
        admissionReceiptID: ReceiptID("live-quit-postimage-worker-admission"),
        admissionCommandID: RunCommandID("admit-live-quit-postimage-worker"),
        bindingReceiptID: ReceiptID("live-quit-postimage-worker-binding"),
        providerLaunchReceiptID: ReceiptID(
          "live-quit-postimage-worker-launch"
        ),
        bindingCommandID: RunCommandID("bind-live-quit-postimage-worker"),
        launchFailureReleaseReceiptID: ReceiptID(
          "live-quit-postimage-worker-launch-failure"
        ),
        launchFailureReleaseCommandID: RunCommandID(
          "live-quit-postimage-worker-launch-failure"
        )
      ),
      invocation: invocation,
      secretCapability: nil
    )
    let providerCompletion = try await session.completeProviderExecution(
      start: providerStart,
      request: KernelProductionProviderCompletionRequest(
        naturalExitTimeoutNanoseconds: 10_000_000_000,
        releaseReceiptID: ReceiptID("live-quit-postimage-worker-release"),
        releaseCommandID: RunCommandID("release-live-quit-postimage-worker"),
        parseReceiptID: ReceiptID("live-quit-postimage-worker-parse"),
        parseCommandID: RunCommandID("parse-live-quit-postimage-worker"),
        derivationReceiptID: ReceiptID("live-quit-postimage-worker-derive"),
        derivationCommandID: RunCommandID("derive-live-quit-postimage-worker")
      )
    )
    try candidateBytes.write(
      to: URL(
        fileURLWithPath: isolation.receipt.candidateRootPath,
        isDirectory: true
      ).appendingPathComponent("main.swift")
    )
    let proposal = try await session.captureCompletedCandidateProposal(
      completion: providerCompletion,
      captureCommandID: RunCommandID("capture-live-quit-postimage-candidate"),
      capturedAt: Date()
    )
    journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let completedState = await journal.state
    XCTAssertEqual(
      completedState.attempts[isolation.receipt.attemptID]?.disposition,
      .completed
    )
    let expectedPostimage = proposal.derivation.candidateSourceRevision
    let attemptID = isolation.receipt.attemptID
    let requirementID = RequirementID("enrollment-outcome")
    let candidateVerification = VerificationReceipt(
      id: ReceiptID("live-quit-candidate-verification"),
      attemptID: attemptID,
      requirementIDs: [requirementID],
      sourceRevision: expectedPostimage,
      environmentDigest: ContentDigest("live-quit-candidate-environment"),
      oracleDigest: ContentDigest("live-quit-candidate-oracle"),
      result: .accepted
    )
    let candidateReviewer = ActorIdentity(
      id: ActorID("live-quit-candidate-reviewer"),
      role: "independent-reviewer",
      lineageDigest: ContentDigest("live-quit-candidate-reviewer-lineage")
    )
    let candidateReview = IndependentReviewReceipt(
      id: ReceiptID("live-quit-candidate-review"),
      attemptID: attemptID,
      requirementIDs: [requirementID],
      reviewer: candidateReviewer,
      evidenceDigest: ContentDigest("live-quit-candidate-review-evidence"),
      sourceRevision: expectedPostimage,
      decision: .approveCandidate
    )
    _ = try await session.testOnlyTransact(
      .testOnlyRecordVerification(candidateVerification),
      commandID: RunCommandID("record-live-quit-candidate-verification"),
      issuedAt: Date(timeIntervalSince1970: 16),
      actor: candidateReviewer
    )
    _ = try await session.testOnlyTransact(
      .testOnlyRecordReview(candidateReview),
      commandID: RunCommandID("record-live-quit-candidate-review"),
      issuedAt: Date(timeIntervalSince1970: 17),
      actor: candidateReviewer
    )

    let transactionID = IntegrationTransactionID("live-quit-integration")
    let candidateID = MutationCandidateID("live-quit-candidate")
    let manifestDigest = ContentDigest("live-quit-manifest")
    let preimageDigest = try XCTUnwrap(ratified.contract.sourceRevision)
      .sourceRevision
    let integrationProposal = IntegrationProposal(
      runID: enrollment.runID,
      transactionID: transactionID,
      candidateID: candidateID,
      attemptID: attemptID,
      nodeID: KernelNodeID("enrollment-node"),
      contractDigest: ratified.contract.objectiveDigest,
      planNodeDigest: ContentDigest("live-quit-plan-node"),
      manifestDigest: manifestDigest,
      canonicalPreimageDigest: preimageDigest,
      expectedPostimageDigest: expectedPostimage,
      proposedAt: Date(timeIntervalSince1970: 18)
    )
    _ = try await session.testOnlyTransact(
      .testOnlyAdvanceIntegration(.propose(integrationProposal)),
      commandID: RunCommandID("propose-live-quit-integration"),
      issuedAt: integrationProposal.proposedAt,
      actor: enrollment.registration.actorIdentity
    )
    let rollback = RollbackManifest(
      transactionID: transactionID,
      forwardManifestDigest: manifestDigest,
      expectedAppliedPostimageDigest: expectedPostimage,
      restoresPreimageDigest: preimageDigest,
      operations: [
        MutationOperation(
          sequence: 1,
          kind: .modify,
          sourcePath: nil,
          destinationPath: "main.swift",
          expectedPreimage: expectedPostimage,
          desiredPostimage: preimageDigest,
          entryKindBefore: .regularFile,
          entryKindAfter: .regularFile,
          modeBefore: 0o100644,
          modeAfter: 0o100644,
          requirementIDs: [requirementID],
          pathResolutionReceiptID: ReceiptID("live-quit-path")
        )
      ]
    )
    let preflight = MutationPreflightReceipt(
      id: ReceiptID("live-quit-preflight"),
      transactionID: transactionID,
      candidateID: candidateID,
      manifestDigest: manifestDigest,
      canonicalPreimageDigest: preimageDigest,
      rollbackManifestDigest: TransactionalMutationKernel.rollbackDigest(
        rollback
      ),
      affectedPaths: ["main.swift"],
      operationCount: 1,
      changedFileCount: 1,
      changedByteCount: UInt64(candidateBytes.count),
      writeAuthorityReceiptID: ReceiptID("live-quit-write-authority"),
      mutationBudgetReceiptID: ReceiptID("live-quit-mutation-budget"),
      candidateVerificationReceiptIDs: [candidateVerification.id],
      independentReviewReceiptID: candidateReview.id,
      rollbackRehearsalReceiptID: ReceiptID("live-quit-rollback-rehearsal"),
      candidateQuiescenceReceiptID: ReceiptID("live-quit-candidate-quiescence"),
      visualGateReceiptID: nil,
      observedAt: Date(timeIntervalSince1970: 19),
      eligibleForDeterministicApply: true,
      permitsPublication: false
    )
    _ = try await session.testOnlyTransact(
      .testOnlyAdvanceIntegration(
        .acceptPreflight(receipt: preflight, rollback: rollback)
      ),
      commandID: RunCommandID("preflight-live-quit-integration"),
      issuedAt: preflight.observedAt,
      actor: enrollment.registration.actorIdentity
    )
    var applyIntent = IntegrationApplyIntent(
      id: IntegrationEffectIntentID("live-quit-apply-intent"),
      transactionID: transactionID,
      preflightReceiptID: preflight.id,
      manifestDigest: manifestDigest,
      canonicalPreimageDigest: preimageDigest,
      rollbackManifestDigest: preflight.rollbackManifestDigest,
      stagedObjectSetDigest: ContentDigest("live-quit-staged-objects"),
      exclusiveLeaseReceiptID: ReceiptID("live-quit-exclusive-lease"),
      remoteAccessDisabled: true,
      requestedAt: Date(timeIntervalSince1970: 20)
    )
    applyIntent.candidatePostimageCapturePolicyDigest =
      proposal.derivation
      .capturePolicyDigest
    _ = try await session.testOnlyTransact(
      .testOnlyAdvanceIntegration(.startApply(applyIntent)),
      commandID: RunCommandID("start-live-quit-apply"),
      issuedAt: applyIntent.requestedAt,
      actor: enrollment.registration.actorIdentity
    )
    try candidateBytes.write(to: canonicalFile)
    var applyReceipt = IntegrationApplyReceipt(
      id: ReceiptID("live-quit-apply"),
      intentID: applyIntent.id,
      transactionID: transactionID,
      manifestDigest: manifestDigest,
      canonicalPreimageDigest: preimageDigest,
      observedPostimageDigest: expectedPostimage,
      unchangedPathProofDigest: ContentDigest("live-quit-unchanged-proof"),
      recoveryArtifactDigest: ContentDigest("live-quit-recovery-artifact"),
      appliedOperationCount: 1,
      executor: enrollment.registration.actorIdentity,
      completedAt: Date(timeIntervalSince1970: 21),
      outcome: .exactPostimage
    )
    applyReceipt.candidatePostimage = proposal.capture.candidateRevision
    _ = try await session.testOnlyTransact(
      .testOnlyAdvanceIntegration(.recordApply(applyReceipt)),
      commandID: RunCommandID("record-live-quit-apply"),
      issuedAt: applyReceipt.completedAt,
      actor: enrollment.registration.actorIdentity
    )

    journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let attestationResolution =
      try await journal
      .latestAcceptedWorkspaceCandidatePostimageAttestation(
        workspaceID: enrollment.registration.workspaceID,
        root: fixture.workspace
      )
    guard case .accepted(let attestation) = attestationResolution else {
      return XCTFail("the exact applied postimage must be attested")
    }
    let runDirectory = await journal.runDirectory
    _ = try KernelExecutableStager().stage(
      executablePath: kernelProcessFixturePath,
      expectedDigest: verifierExecutableDigest,
      runDirectory: runDirectory
    )
    let candidateInput = try WorkspaceCandidatePostimageMaterializer()
      .materialize(
        attestation: attestation,
        workspaceRoot: fixture.workspace,
        runDirectory: runDirectory
      )
    let postimageVerifier = ActorIdentity(
      id: ActorID("live-quit-postimage-verifier"),
      role: "postimage-verifier",
      lineageDigest: ContentDigest("live-quit-postimage-verifier-lineage")
    )
    let resourceID = OwnedResourceID("live-quit-postimage-process")
    let leaseID = ResourceLeaseID("live-quit-postimage-lease")
    let vetoRequest = KernelProductionPostimageVerifierLaunchRequest(
      activation: KernelPostimageVerifierActivationRequest(
        workspaceRoot: fixture.workspace,
        integrationTransactionID: transactionID,
        evidenceRecipeID: EvidenceRecipeID("enrollment-recipe"),
        verifier: ActorIdentity(
          id: ActorID("live-quit-postimage-veto-verifier"),
          role: "postimage-verifier",
          lineageDigest: ContentDigest(
            "live-quit-postimage-veto-verifier-lineage"
          )
        ),
        candidateInput: candidateInput,
        receiptID: ReceiptID("live-quit-postimage-veto-activation"),
        commandID: RunCommandID(
          "activate-live-quit-postimage-veto-verifier"
        ),
        activatedAt: Date(timeIntervalSince1970: 22)
      ),
      runtime: KernelPostimageVerifierRuntimeRequest(
        leaseID: ResourceLeaseID("live-quit-postimage-veto-lease"),
        resourceID: OwnedResourceID("live-quit-postimage-veto-process"),
        standardOutputFileName: "live-quit-postimage-veto.stdout",
        standardErrorFileName: "live-quit-postimage-veto.stderr",
        admissionReceiptID: ReceiptID(
          "live-quit-postimage-veto-admission"
        ),
        admissionCommandID: RunCommandID(
          "admit-live-quit-postimage-veto"
        ),
        bindingReceiptID: ReceiptID("live-quit-postimage-veto-binding"),
        launchReceiptID: ReceiptID("live-quit-postimage-veto-launch"),
        bindingCommandID: RunCommandID("bind-live-quit-postimage-veto"),
        launchFailureReleaseReceiptID: ReceiptID(
          "live-quit-postimage-veto-launch-failure"
        ),
        launchFailureReleaseCommandID: RunCommandID(
          "live-quit-postimage-veto-launch-failure"
        ),
        launchVetoReceiptID: ReceiptID(
          "live-quit-postimage-veto-receipt"
        ),
        launchVetoCommandID: RunCommandID(
          "live-quit-postimage-veto-command"
        )
      )
    )
    var collidingVetoRequest = vetoRequest
    collidingVetoRequest.runtime.admissionReceiptID =
      collidingVetoRequest.activation.receiptID
    do {
      _ = try await session.launchPostimageVerifier(collidingVetoRequest)
      XCTFail("colliding postimage receipt identities must not activate")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .postimageVerifierLaunchRequestInvalid)
    }
    let vetoOutcome = try await session.launchPostimageVerifier(vetoRequest)
    let vetoActivation: KernelPostimageVerifierActivationReceipt
    let vetoReceipt: KernelPostimageVerifierLaunchVetoReceipt
    let vetoTransaction: JournalTransactionReceipt
    switch vetoOutcome {
    case .vetoed(
      let activation,
      let activationTransaction,
      let receipt,
      let transaction
    ):
      XCTAssertEqual(activation.id, vetoRequest.activation.receiptID)
      XCTAssertEqual(
        receipt.activationJournalFrameDigest,
        activationTransaction.frameDigest
      )
      vetoActivation = activation
      vetoReceipt = receipt
      vetoTransaction = transaction
    case .launched:
      return XCTFail(
        "ordinary production must veto without resident-memory authority"
      )
    }
    XCTAssertEqual(
      vetoReceipt.reason,
      .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
    )
    XCTAssertEqual(
      vetoReceipt.requiredMaximumResidentBytes,
      verifierProbe.resourceLimits.maximumResidentBytes
    )
    XCTAssertFalse(vetoTransaction.duplicate)
    let vetoJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let vetoLease = await vetoJournal.runtimeLease(
      resourceID: vetoRequest.runtime.resourceID
    )
    let unexpectedVetoLaunch =
      await vetoJournal
      .postimageVerifierLaunchReceipt(
        receiptID: vetoRequest.runtime.launchReceiptID
      )
    XCTAssertNil(vetoLease)
    XCTAssertNil(unexpectedVetoLaunch)
    let retainedVetoOutcome = try await session.launchPostimageVerifier(
      vetoRequest
    )
    switch retainedVetoOutcome {
    case .vetoed(_, _, let retainedReceipt, let retainedTransaction):
      XCTAssertEqual(retainedReceipt, vetoReceipt)
      XCTAssertEqual(retainedTransaction, vetoTransaction)
    case .launched:
      return XCTFail("a retained veto must remain fail-closed on retry")
    }
    let launchRequest = KernelProductionPostimageVerifierLaunchRequest(
      activation: KernelPostimageVerifierActivationRequest(
        workspaceRoot: fixture.workspace,
        integrationTransactionID: transactionID,
        evidenceRecipeID: EvidenceRecipeID("enrollment-recipe-2"),
        verifier: postimageVerifier,
        candidateInput: candidateInput,
        receiptID: ReceiptID("live-quit-postimage-activation"),
        commandID: RunCommandID("activate-live-quit-postimage-verifier"),
        activatedAt: Date(timeIntervalSince1970: 22)
      ),
      runtime: KernelPostimageVerifierRuntimeRequest(
        leaseID: leaseID,
        resourceID: resourceID,
        standardOutputFileName: "live-quit-postimage.stdout",
        standardErrorFileName: "live-quit-postimage.stderr",
        admissionReceiptID: ReceiptID("live-quit-postimage-admission"),
        admissionCommandID: RunCommandID("admit-live-quit-postimage"),
        bindingReceiptID: ReceiptID("live-quit-postimage-binding"),
        launchReceiptID: ReceiptID("live-quit-postimage-launch"),
        bindingCommandID: RunCommandID("bind-live-quit-postimage"),
        launchFailureReleaseReceiptID: ReceiptID(
          "live-quit-postimage-launch-failure"
        ),
        launchFailureReleaseCommandID: RunCommandID(
          "live-quit-postimage-launch-failure"
        ),
        launchVetoReceiptID: ReceiptID("live-quit-postimage-veto"),
        launchVetoCommandID: RunCommandID("live-quit-postimage-veto")
      )
    )
    do {
      _ = try await session.launchPostimageVerifier(
        launchRequest,
        residentMemoryEnforcementResolver: { _ in
          .authorized(.testOnly(activation: vetoActivation))
        }
      )
      XCTFail("cross-wired resident-memory authority must not launch")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .postimageVerifierContainmentAuthorityMismatch)
    }
    let crossWiredJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let crossWiredLease = await crossWiredJournal.runtimeLease(
      resourceID: launchRequest.runtime.resourceID
    )
    let crossWiredLaunch =
      await crossWiredJournal
      .postimageVerifierLaunchReceipt(
        receiptID: launchRequest.runtime.launchReceiptID
      )
    let crossWiredVeto =
      await crossWiredJournal
      .postimageVerifierLaunchVetoReceipt(
        receiptID: launchRequest.runtime.launchVetoReceiptID
      )
    XCTAssertNil(crossWiredLease)
    XCTAssertNil(crossWiredLaunch)
    XCTAssertNil(crossWiredVeto)
    let verifierLaunchOutcome = try await session.launchPostimageVerifier(
      launchRequest,
      residentMemoryEnforcementResolver: { activation in
        .authorized(.testOnly(activation: activation))
      }
    )
    let start: JournaledPostimageVerifierStartReceipt
    switch verifierLaunchOutcome {
    case .launched(let receipt):
      start = receipt
    case .vetoed:
      return XCTFail(
        "the exact test-only containment capability must launch the verifier"
      )
    }
    let processID = start.launch.handle.processID
    defer { _ = Darwin.kill(processID, SIGKILL) }
    XCTAssertEqual(Darwin.kill(processID, 0), 0)

    let model = AppModel(
      store: TaskStore(
        storageURL: fixture.container.appendingPathComponent("tasks.json")
      ),
      kernelRunEnrollmentCoordinator: fixture.coordinator,
      kernelExecutionCoordinator: fixture.productionExecutionCoordinator
    )
    await model.testOnlyRetainKernelExecutionSession(session)
    XCTAssertTrue(model.hasActiveKernelExecutionSessions)
    let terminationReady =
      await model
      .prepareKernelSessionsForApplicationTermination()

    XCTAssertTrue(
      terminationReady,
      model.alertMessage ?? "live verifier cleanup was rejected"
    )
    XCTAssertFalse(model.hasActiveKernelExecutionSessions)
    XCTAssertEqual(Darwin.kill(processID, 0), -1)
    XCTAssertEqual(errno, ESRCH)
    let recoveredJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recoveredJournal.state
    let projection = await recoveredJournal.currentProjection()
    XCTAssertEqual(state.phase, .stopped)
    XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
    XCTAssertTrue(state.runtimeFailedReleases.isEmpty)
    let release = try XCTUnwrap(
      state.runtimeReleaseReceipts.values.first(where: {
        $0.resourceID == resourceID && $0.leaseID == leaseID
      })
    )
    guard case .released = release.outcome else {
      return XCTFail("application termination did not release the verifier")
    }
    let containment = try XCTUnwrap(release.postimageVerifierContainment)
    XCTAssertEqual(containment.disposition, .runtimeCleanupTermination)
    XCTAssertEqual(containment.activationReceiptID, start.activation.id)
    XCTAssertEqual(containment.launchReceiptID, start.verifierLaunch.id)
    XCTAssertEqual(
      release.managedProcessTermination?.handle.processID,
      processID
    )
    XCTAssertNil(release.managedProcessExit)
    XCTAssertNil(containment.postimageResult)
    XCTAssertNotNil(containment.postimageResultFailureDigest)
    XCTAssertTrue(
      state.verificationReceipts.values.allSatisfy {
        $0.postimageEvidenceBatch == nil
      })
    XCTAssertTrue(projection.quiescent)
    XCTAssertEqual(projection.phase, .stopped)
  }

  func testCompletedCandidateCaptureIsJournaledAndCrashReplayable()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Data("let canonicalBaseline = 1\n".utf8).write(
      to: fixture.workspace.appendingPathComponent("main.swift")
    )
    try git(fixture.workspace, ["init", "-q", "-b", "main"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(
      fixture.workspace,
      ["config", "user.email", "loopforge@example.invalid"]
    )
    try git(fixture.workspace, ["add", "main.swift"])
    try git(fixture.workspace, ["commit", "-qm", "baseline"])
    let verifierExecutableDigest = try XCTUnwrap(
      ProcessGroupRuntimeAdapter.executableContentDigest(
        atPath: kernelProcessFixturePath
      )
    )
    let verifierEvidenceDigest = String(repeating: "a", count: 64)
    let postimageVerificationProbe =
      RequirementVerificationExecutableProbe(
        schemaVersion: 2,
        transport: .localDirectProcess,
        executableContentDigest: verifierExecutableDigest,
        fixedArguments: [
          "--emit-verifier-result-and-sleep",
          "accepted",
          verifierEvidenceDigest,
          "0",
          "@loopforge-input:candidate-postimage",
        ],
        inputBindings: [
          RequirementVerificationInputBinding(
            id: "candidate-postimage",
            kind: .candidatePostimage,
            artifactID: "completed-candidate-postimage",
            argumentToken: "@loopforge-input:candidate-postimage"
          )
        ],
        environmentPolicy: .minimalKernelAllowlist,
        environmentIdentityDigest:
          KernelProcessEnvironmentAuthorizer
          .environmentDigest(
            KernelProcessEnvironmentAuthorizer.minimalEnvironment
          ),
        captureIdentityDigest:
          KernelPostimageVerifierCapturePolicy.identityDigest,
        parser: RequirementVerificationParserContract(
          id: "completed-candidate-postimage-parser",
          schemaVersion: 1,
          contentDigest: RequirementVerificationParserFormat
            .canonicalJSONResultV1.implementationIdentityDigest,
          format: .canonicalJSONResultV1
        ),
        resultMappings: [
          RequirementVerificationResultMapping(
            exitCode: 0,
            parserResultCode: "accepted",
            outcome: .accepted
          )
        ],
        unmatchedOutcome: .rejected,
        networkPolicy: .disabled,
        resourceLimits: RequirementVerificationResourceLimits(
          maximumWallClockSeconds: 1,
          maximumCapturedOutputBytes: 64 * 1_024,
          maximumResidentBytes: 64 * 1_024 * 1_024,
          maximumChildProcesses: 0
        )
      )
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        evidenceProbe: postimageVerificationProbe
      )
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(
        ratifiedContract: ratified,
        hostBudget: HostResourceBudget(
          nominal: ResourceVector(
            cpuWeight: 0,
            memoryBytes: 0,
            diskIOWeight: 1,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 0
          ))
      )
    )
    let isolation = try await WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    ).isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { isolation.close() }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    _ = try await journal.recordPreApplyCandidateIsolation(
      isolation,
      commandID: RunCommandID("accept-preapply-isolation")
    )
    let preparation = try await fixture.executionCoordinator.prepare(
      fixture.preparationRequest(enrollment: enrollment),
      acceptedPreApplyIsolation: isolation.receipt
    )
    _ = try await fixture.executionCoordinator.activate(
      KernelExecutionActivationRequest(
        enrollment: enrollment,
        preparation: preparation,
        actorIdentity: enrollment.registration.actorIdentity,
        startCommandID: RunCommandID("activate-capture-attempt"),
        issuedAt: Date(timeIntervalSince1970: 6)
      ),
      acceptedPreApplyIsolation: isolation.receipt
    )
    let activeJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let gitAuthority = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)
    _ = try await activeJournal.recordJournaledGitPreimageCapture(
      gitAuthority,
      commandID: RunCommandID("record-completed-candidate-git-preimage")
    )
    let canonicalAuthority = try await WorkspaceJournaledCanonicalPreimageIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)
    let canonicalTransaction =
      try await activeJournal
      .recordJournaledCanonicalPreimage(
        canonicalAuthority,
        commandID: RunCommandID(
          "record-completed-candidate-canonical-preimage"
        )
      )
    let materializer = WorkspaceCandidatePostimageMaterializer()
    let executionRoot = try materializer.activatePreApplyIsolation(isolation)
    defer { executionRoot.close() }
    let candidateFile = URL(
      fileURLWithPath: isolation.receipt.candidateRootPath,
      isDirectory: true
    ).appendingPathComponent("main.swift")
    let candidateBytes = Data("let canonicalCandidate = 2\n".utf8)
    try candidateBytes.write(to: candidateFile)
    let provenance = try await journalTestWorkerDisposition(
      activeJournal,
      runID: enrollment.runID,
      attemptID: isolation.receipt.attemptID,
      actor: enrollment.registration.actorIdentity,
      prefix: "completed-candidate",
      startingAt: 10
    )
    let completion = KernelProductionProviderCompletionReceipt(
      release: provenance.release,
      parse: provenance.parse,
      execution: provenance.execution
    )
    let capture = try materializer.captureCompletedCandidate(
      executionRoot,
      completion: completion,
      captureActor: enrollment.registration.actorIdentity,
      capturedAt: Date(timeIntervalSince1970: 15)
    )

    let transaction = try await activeJournal.recordCompletedCandidateCapture(
      capture,
      commandID: RunCommandID("record-completed-candidate")
    )

    XCTAssertFalse(transaction.duplicate)
    let journaledCapture = await activeJournal.completedCandidateCaptureReceipt(
      transaction: transaction
    )
    XCTAssertEqual(
      journaledCapture,
      capture.receipt
    )
    XCTAssertEqual(capture.objects.map(\.data), [candidateBytes])
    let base = try XCTUnwrap(ratified.contract.sourceRevision)
    let derivation = try WorkspaceMutationOperationDeriver().derive(
      base: base,
      candidate: capture.candidateRevision,
      requirementIDs: [RequirementID("enrollment-outcome")],
      authorizedPaths: ["main.swift"]
    )
    let baseline = try await WorkspaceRatifiedBaselineContentCaptureIssuer(
      registry: fixture.registry
    ).capture(
      enrollment: enrollment,
      derivation: derivation
    )
    _ = try await activeJournal.recordRatifiedBaselineContentCapture(
      baseline,
      commandID: RunCommandID("record-completed-candidate-baseline")
    )
    let storageRoot = fixture.container.appendingPathComponent(
      "completed-candidate-content-store",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: storageRoot,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    let proposal = KernelProductionCompletedCandidateProposal(
      capture: capture,
      derivation: derivation,
      journalTransaction: transaction
    )
    var substitutedProposal = proposal
    substitutedProposal.journalTransaction.frameDigest = ContentDigest(
      String(repeating: "0", count: 64)
    )
    do {
      _ = try await WorkspaceCompletedCandidateMutationContentStoreCoordinator(
        journal: activeJournal
      ).install(
        proposal: substitutedProposal,
        baseline: baseline,
        workspaceRoot: fixture.workspace,
        storageRoot: storageRoot,
        commandID: RunCommandID(
          "reject-substituted-completed-candidate-store"
        )
      )
      XCTFail("a substituted capture transaction must reject before store I/O")
    } catch let error as WorkspaceCompletedCandidateMutationContentStoreError {
      XCTAssertEqual(error, .invalidProposal)
    }
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath:
          storageRoot.appendingPathComponent(
            WorkspaceMutationContentObjectStore.directoryName
          ).path
      ))
    let installation = try await WorkspaceCompletedCandidateMutationContentStoreCoordinator(
      journal: activeJournal,
      wallClock: { Date(timeIntervalSince1970: 4_000_000_000) }
    ).install(
      proposal: proposal,
      baseline: baseline,
      workspaceRoot: fixture.workspace,
      storageRoot: storageRoot,
      commandID: RunCommandID(
        "record-completed-candidate-content-store"
      )
    )
    XCTAssertFalse(installation.journalTransaction.duplicate)
    XCTAssertTrue(installation.authority.validationIssues().isEmpty)
    XCTAssertEqual(
      Set(installation.authority.objects.map(\.data)),
      Set([
        Data("let canonicalBaseline = 1\n".utf8),
        candidateBytes,
      ])
    )
    XCTAssertNotEqual(
      installation.authority.receipt.objectStoreReceipt.artifactPath,
      fixture.workspace.path
    )
    let duplicateInstallation =
      try await WorkspaceCompletedCandidateMutationContentStoreCoordinator(
        journal: activeJournal,
        wallClock: { Date(timeIntervalSince1970: 4_000_000_001) }
      ).install(
        proposal: proposal,
        baseline: baseline,
        workspaceRoot: fixture.workspace,
        storageRoot: storageRoot,
        commandID: RunCommandID(
          "record-completed-candidate-content-store"
        )
      )
    XCTAssertTrue(duplicateInstallation.journalTransaction.duplicate)
    XCTAssertEqual(
      duplicateInstallation.authority.receipt,
      installation.authority.receipt
    )
    var substitutedCanonicalTransaction = canonicalTransaction
    substitutedCanonicalTransaction.frameDigest = ContentDigest(
      String(repeating: "0", count: 64)
    )
    do {
      _ = try await WorkspaceCompletedCandidateMutationManifestProposalCoordinator(
        journal: activeJournal
      ).propose(
        contentStore: installation,
        canonicalPreimage: canonicalAuthority,
        canonicalPreimageTransaction:
          substitutedCanonicalTransaction,
        commandID: RunCommandID(
          "reject-substituted-manifest-proposal-origin"
        )
      )
      XCTFail("a substituted canonical transaction must not propose")
    } catch let error as WorkspaceCompletedCandidateMutationManifestProposalError {
      XCTAssertEqual(error, .originNotAccepted)
    }
    let manifestProposal = try await WorkspaceCompletedCandidateMutationManifestProposalCoordinator(
      journal: activeJournal,
      wallClock: { Date(timeIntervalSince1970: 4_000_000_002) }
    ).propose(
      contentStore: installation,
      canonicalPreimage: canonicalAuthority,
      canonicalPreimageTransaction: canonicalTransaction,
      commandID: RunCommandID(
        "record-completed-candidate-manifest-proposal"
      )
    )
    XCTAssertFalse(manifestProposal.journalTransaction.duplicate)
    XCTAssertTrue(manifestProposal.authority.validationIssues().isEmpty)
    XCTAssertEqual(
      manifestProposal.authority.receipt.operations,
      WorkspaceCompletedCandidateMutationManifestProposalReceipt
        .operations(for: derivation)
    )
    XCTAssertEqual(
      manifestProposal.authority.receipt.changedFileCount,
      1
    )
    XCTAssertEqual(
      manifestProposal.authority.receipt.preparationBinding
        .canonicalPreimageDigest,
      canonicalAuthority.receipt.preimage.canonicalDigest
    )
    XCTAssertEqual(
      manifestProposal.authority.receipt.preparationBinding
        .expectedPostimageDigest,
      derivation.candidateSourceRevision
    )
    let encodedManifestProposal = try JSONEncoder().encode(
      manifestProposal.authority.receipt
    )
    let manifestProposalJSON = try XCTUnwrap(
      String(
        data: encodedManifestProposal,
        encoding: .utf8
      ))
    for executableAuthorityKey in [
      "pathResolutionReceiptID",
      "writeAuthorityReceiptID",
      "mutationBudgetReceiptID",
      "candidateVerificationReceiptIDs",
      "independentReviewReceiptID",
      "rollbackRehearsalReceiptID",
      "candidateQuiescenceReceiptID",
      "visualGateReceiptID",
    ] {
      XCTAssertFalse(
        manifestProposalJSON.contains(
          "\"\(executableAuthorityKey)\""
        ))
    }
    var substitutedManifestProposalTransaction =
      manifestProposal.journalTransaction
    substitutedManifestProposalTransaction.frameDigest = ContentDigest(
      String(repeating: "0", count: 64)
    )
    let substitutedManifestProposal =
      WorkspaceCompletedCandidateMutationManifestProposalInstallation(
        authority: manifestProposal.authority,
        journalTransaction: substitutedManifestProposalTransaction
      )
    do {
      _ = try await WorkspaceCompletedCandidateMutationPreparationFactsCoordinator(
        journal: activeJournal
      ).prepare(
        proposal: substitutedManifestProposal,
        canonicalWorkspaceRoot: fixture.workspace,
        commandID: RunCommandID(
          "reject-substituted-preparation-facts-origin"
        )
      )
      XCTFail("a substituted proposal transaction must not prepare facts")
    } catch let error as WorkspaceCompletedCandidateMutationPreparationFactsError {
      XCTAssertEqual(error, .originNotAccepted)
    }
    let canonicalFile = fixture.workspace.appendingPathComponent(
      "main.swift"
    )
    let displacedCanonicalFile = fixture.workspace.appendingPathComponent(
      "main.real"
    )
    try FileManager.default.moveItem(
      at: canonicalFile,
      to: displacedCanonicalFile
    )
    try FileManager.default.createSymbolicLink(
      atPath: canonicalFile.path,
      withDestinationPath: displacedCanonicalFile.lastPathComponent
    )
    do {
      _ = try await WorkspaceCompletedCandidateMutationPreparationFactsCoordinator(
        journal: activeJournal
      ).prepare(
        proposal: manifestProposal,
        canonicalWorkspaceRoot: fixture.workspace,
        commandID: RunCommandID(
          "reject-symlinked-preparation-path"
        )
      )
      XCTFail("a symlinked canonical path must not prepare path facts")
    } catch let error as WorkspaceCompletedCandidateMutationPreparationFactsError {
      XCTAssertEqual(error, .canonicalPathChanged("main.swift"))
    }
    try FileManager.default.removeItem(at: canonicalFile)
    try FileManager.default.moveItem(
      at: displacedCanonicalFile,
      to: canonicalFile
    )
    let preparationFacts = try await WorkspaceCompletedCandidateMutationPreparationFactsCoordinator(
      journal: activeJournal,
      wallClock: { Date(timeIntervalSince1970: 4_000_000_004) }
    ).prepare(
      proposal: manifestProposal,
      canonicalWorkspaceRoot: fixture.workspace,
      commandID: RunCommandID(
        "record-completed-candidate-preparation-facts"
      )
    )
    XCTAssertFalse(preparationFacts.journalTransaction.duplicate)
    XCTAssertTrue(preparationFacts.authority.validationIssues().isEmpty)
    XCTAssertEqual(
      preparationFacts.authority.receipt.writeAuthority.authorizedPaths,
      ["main.swift"]
    )
    XCTAssertEqual(
      preparationFacts.authority.receipt.mutationBudget
        .maximumChangedFiles,
      manifestProposal.authority.receipt.changedFileCount
    )
    XCTAssertEqual(
      preparationFacts.authority.receipt.mutationBudget
        .maximumChangedBytes,
      manifestProposal.authority.receipt.changedByteCount
    )
    XCTAssertTrue(
      preparationFacts.authority.receipt.candidateQuiescence
        .candidateScoped
    )
    XCTAssertEqual(
      preparationFacts.authority.receipt.candidateQuiescence
        .activeOwnedResourceCount,
      0
    )
    XCTAssertEqual(
      preparationFacts.authority.receipt.pathObservations.map(\.path),
      ["main.swift"]
    )
    XCTAssertEqual(
      preparationFacts.authority.receipt.pathObservations.first?
        .contentDigest,
      derivation.operations.first?.expectedPreimage
    )
    let rollbackRehearsalReceiptID =
      WorkspaceCompletedCandidateMutationPreparationFactsReceipt.factID(
        role: "rollback-rehearsal",
        proposalReceiptDigest:
          manifestProposal.authority.receipt.receiptDigest
      )
    let rehearsalManifest = MutationManifest(
      transactionID: manifestProposal.authority.receipt.transactionID,
      candidateID: manifestProposal.authority.receipt.candidateID,
      contractDigest: manifestProposal.authority.receipt.contractDigest,
      planNodeDigest: manifestProposal.authority.receipt.planNodeDigest,
      basePreimageDigest:
        manifestProposal.authority.receipt.basePreimageDigest,
      operations:
        AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
        .operations(
          proposal: manifestProposal.authority.receipt,
          pathResolutionReceiptID:
            preparationFacts.authority.receipt.pathResolution.id
        ),
      touchedRequirementIDs:
        manifestProposal.authority.receipt.touchedRequirementIDs,
      writeAuthorityReceiptID:
        preparationFacts.authority.receipt.writeAuthority.id,
      mutationBudgetReceiptID:
        preparationFacts.authority.receipt.mutationBudget.id,
      candidateVerificationReceiptIDs: [
        ReceiptID("test-only-accepted-verification")
      ],
      independentReviewReceiptID:
        ReceiptID("test-only-accepted-independent-review"),
      rollbackRehearsalReceiptID: rollbackRehearsalReceiptID,
      candidateQuiescenceReceiptID:
        preparationFacts.authority.receipt.candidateQuiescence.id,
      visualGateReceiptID: nil,
      expectedPostimageDigest:
        manifestProposal.authority.receipt.expectedPostimageDigest
    )
    let rehearsalExecutor =
      WorkspaceCompletedCandidateMutationRollbackRehearsalExecutor()
    do {
      _ = try rehearsalExecutor.rehearse(
        preparation: preparationFacts,
        manifest: rehearsalManifest,
        canonicalWorkspaceRoot: fixture.workspace,
        storageRoot: fixture.workspace,
        rehearsedAt: Date(timeIntervalSince1970: 4_000_000_005)
      )
      XCTFail("the rehearsal replica must be outside the canonical workspace")
    } catch let error as WorkspaceCompletedCandidateMutationRollbackRehearsalError {
      XCTAssertEqual(error, .storageRootOverlapsCanonicalWorkspace)
    }
    let rehearsalStorageRoot = fixture.container.appendingPathComponent(
      "rollback-rehearsal",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: rehearsalStorageRoot,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
    )
    let rollbackRehearsal = try rehearsalExecutor.rehearse(
      preparation: preparationFacts,
      manifest: rehearsalManifest,
      canonicalWorkspaceRoot: fixture.workspace,
      storageRoot: rehearsalStorageRoot,
      rehearsedAt: Date(timeIntervalSince1970: 4_000_000_005)
    )
    XCTAssertTrue(rollbackRehearsal.validationIssues().isEmpty)
    XCTAssertEqual(
      rollbackRehearsal.receipt.initialAffectedStateDigest,
      rollbackRehearsal.receipt.restoredAffectedStateDigest
    )
    XCTAssertNotEqual(
      rollbackRehearsal.receipt.initialAffectedStateDigest,
      rollbackRehearsal.receipt.appliedAffectedStateDigest
    )
    XCTAssertEqual(rollbackRehearsal.receipt.affectedPaths, ["main.swift"])
    XCTAssertEqual(
      rollbackRehearsal.receipt.forwardManifestDigest,
      TransactionalMutationKernel.manifestDigest(rehearsalManifest)
    )
    XCTAssertEqual(
      rollbackRehearsal.receipt.rollbackManifestDigest,
      TransactionalMutationKernel.rollbackDigest(
        rollbackRehearsal.rollbackManifest
      )
    )
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        atPath: rehearsalStorageRoot.path
      ),
      []
    )
    XCTAssertEqual(
      try String(contentsOf: canonicalFile, encoding: .utf8),
      "let canonicalBaseline = 1\n"
    )
    let verifier = ActorIdentity(
      id: ActorID("rollback-verifier"),
      role: "independent verifier",
      lineageDigest: ContentDigest("rollback-verifier-lineage")
    )
    let verification = VerificationReceipt(
      id: ReceiptID("rollback-verification"),
      attemptID: isolation.receipt.attemptID,
      requirementIDs: [RequirementID("enrollment-outcome")],
      sourceRevision: derivation.candidateSourceRevision,
      environmentDigest: ContentDigest("rollback-environment"),
      oracleDigest: ContentDigest("rollback-oracle"),
      result: .accepted
    )
    _ = try await activeJournal.transactAtCurrentSequence(
      .testOnlyRecordVerification(verification),
      commandID: RunCommandID("record-rollback-verification"),
      issuedAt: Date(timeIntervalSince1970: 4_000_000_006),
      actor: verifier
    )
    let reviewer = ActorIdentity(
      id: ActorID("rollback-reviewer"),
      role: "independent reviewer",
      lineageDigest: ContentDigest("rollback-reviewer-lineage")
    )
    let review = IndependentReviewReceipt(
      id: ReceiptID("rollback-review"),
      attemptID: isolation.receipt.attemptID,
      requirementIDs: [RequirementID("enrollment-outcome")],
      reviewer: reviewer,
      evidenceDigest: ContentDigest("rollback-review-evidence"),
      sourceRevision: derivation.candidateSourceRevision,
      decision: .approveCandidate
    )
    _ = try await activeJournal.transactAtCurrentSequence(
      .testOnlyRecordReview(review),
      commandID: RunCommandID("record-rollback-review"),
      issuedAt: Date(timeIntervalSince1970: 4_000_000_007),
      actor: reviewer
    )
    let journaledRollback =
      try await WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinator(
        journal: activeJournal,
        wallClock: { Date(timeIntervalSince1970: 4_000_000_008) }
      ).rehearse(
        preparation: preparationFacts,
        canonicalWorkspaceRoot: fixture.workspace,
        storageRoot: rehearsalStorageRoot,
        commandID: RunCommandID(
          "record-completed-candidate-rollback-rehearsal"
        )
      )
    XCTAssertFalse(journaledRollback.journalTransaction.duplicate)
    XCTAssertTrue(journaledRollback.authority.validationIssues().isEmpty)
    XCTAssertEqual(
      journaledRollback.authority.receipt.initialAffectedStateDigest,
      journaledRollback.authority.receipt.restoredAffectedStateDigest
    )
    let duplicateJournaledRollback =
      try await WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinator(
        journal: activeJournal,
        wallClock: { Date(timeIntervalSince1970: 4_000_000_009) }
      ).rehearse(
        preparation: preparationFacts,
        canonicalWorkspaceRoot: fixture.workspace,
        storageRoot: rehearsalStorageRoot,
        commandID: RunCommandID(
          "record-completed-candidate-rollback-rehearsal"
        )
      )
    XCTAssertTrue(
      duplicateJournaledRollback.journalTransaction.duplicate
    )
    XCTAssertEqual(
      duplicateJournaledRollback.authority.receipt,
      journaledRollback.authority.receipt
    )
    let executablePreflight = try await WorkspaceCompletedCandidateMutationPreflightCoordinator(
      journal: activeJournal,
      wallClock: { Date(timeIntervalSince1970: 4_000_000_010) }
    ).prepare(
      rehearsal: journaledRollback,
      canonicalWorkspaceRoot: fixture.workspace,
      proposalCommandID: RunCommandID(
        "propose-completed-candidate-integration"
      ),
      preflightCommandID: RunCommandID(
        "accept-completed-candidate-preflight"
      )
    )
    XCTAssertTrue(executablePreflight.authority.validationIssues().isEmpty)
    XCTAssertFalse(
      executablePreflight.proposalJournalTransaction.duplicate
    )
    XCTAssertFalse(
      executablePreflight.preflightJournalTransaction.duplicate
    )
    XCTAssertEqual(
      executablePreflight.authority.preflight.manifest,
      journaledRollback.authority.manifest
    )
    XCTAssertEqual(
      executablePreflight.authority.rollback,
      journaledRollback.authority.rollbackManifest
    )
    XCTAssertTrue(
      executablePreflight.authority.receipt
        .eligibleForDeterministicApply
    )
    XCTAssertFalse(executablePreflight.authority.receipt.permitsPublication)
    let retainedIntegration = await activeJournal.integrationTransaction(
      transactionID: journaledRollback.authority.manifest.transactionID
    )
    XCTAssertEqual(retainedIntegration?.phase, .rollbackPrepared)
    XCTAssertEqual(
      retainedIntegration?.preflightReceipt,
      executablePreflight.authority.receipt
    )
    let duplicateExecutablePreflight =
      try await WorkspaceCompletedCandidateMutationPreflightCoordinator(
        journal: activeJournal,
        wallClock: { Date(timeIntervalSince1970: 4_000_000_011) }
      ).prepare(
        rehearsal: journaledRollback,
        canonicalWorkspaceRoot: fixture.workspace,
        proposalCommandID: RunCommandID(
          "propose-completed-candidate-integration"
        ),
        preflightCommandID: RunCommandID(
          "accept-completed-candidate-preflight"
        )
      )
    XCTAssertTrue(
      duplicateExecutablePreflight.proposalJournalTransaction.duplicate
    )
    XCTAssertTrue(
      duplicateExecutablePreflight.preflightJournalTransaction.duplicate
    )
    XCTAssertEqual(
      duplicateExecutablePreflight.authority.receipt,
      executablePreflight.authority.receipt
    )
    let applyIssuedAt = Date(timeIntervalSince1970: 4_000_000_012)
    let applyRequest =
      WorkspaceCompletedCandidateMutationApplyPreparationRequest(
        preflight: executablePreflight,
        registration: enrollment.registration,
        containmentReadiness: nil,
        leaseID: ResourceLeaseID(
          "completed-candidate-workspace-lease"
        ),
        admissionReceiptID: ReceiptID(
          "completed-candidate-workspace-admission"
        ),
        admissionCommandID: RunCommandID(
          "admit-completed-candidate-workspace-lease"
        ),
        intentID: IntegrationEffectIntentID(
          "apply-completed-candidate"
        ),
        intentCommandID: RunCommandID(
          "start-completed-candidate-apply"
        ),
        startCommandID: RunCommandID(
          "confirm-completed-candidate-apply-start"
        ),
        recordCommandID: RunCommandID(
          "record-completed-candidate-apply"
        ),
        releaseReceiptID: ReceiptID(
          "release-completed-candidate-workspace-lease"
        ),
        releaseCommandID: RunCommandID(
          "release-completed-candidate-workspace-lease"
        ),
        failureReceiptID: ReceiptID(
          "fail-completed-candidate-workspace-lease"
        ),
        failureCommandID: RunCommandID(
          "fail-completed-candidate-workspace-lease"
        ),
        issuedAt: applyIssuedAt,
        expiresAt: applyIssuedAt.addingTimeInterval(60),
        requestedAtMonotonicNanoseconds: 1_000,
        expiresAtMonotonicNanoseconds: 60_000_001_000
      )
    let productionApplyRequest =
      KernelProductionMutationApplyPreparationRequest(
        preparation: applyRequest,
        containmentVetoReceiptID: ReceiptID(
          "completed-candidate-containment-veto"
        ),
        containmentVetoCommandID: RunCommandID(
          "record-completed-candidate-containment-veto"
        )
      )
    var collidingProductionApplyRequest = productionApplyRequest
    collidingProductionApplyRequest.containmentVetoReceiptID =
      applyRequest.admissionReceiptID
    do {
      _ = try await fixture.productionExecutionCoordinator
        .prepareCompletedCandidateMutation(collidingProductionApplyRequest)
      XCTFail("colliding containment-veto identity must reject")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .mutationApplyPreparationRequestInvalid)
    }
    let productionVetoOutcome =
      try await fixture
      .productionExecutionCoordinator.prepareCompletedCandidateMutation(
        productionApplyRequest
      )
    let productionVetoReceipt: KernelProductionMutationApplyVetoReceipt
    let productionVetoTransaction: JournalTransactionReceipt
    switch productionVetoOutcome {
    case .vetoed(let receipt, let transaction):
      productionVetoReceipt = receipt
      productionVetoTransaction = transaction
    case .prepared:
      return XCTFail(
        "ordinary production must retain the pre-effect containment veto"
      )
    }
    XCTAssertEqual(
      productionVetoReceipt.reason,
      .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
    )
    XCTAssertEqual(
      productionVetoReceipt.preflightReceiptID,
      executablePreflight.authority.receipt.id
    )
    XCTAssertEqual(
      productionVetoReceipt.integrationTransactionID,
      journaledRollback.authority.manifest.transactionID
    )
    XCTAssertEqual(
      productionVetoReceipt.requirements,
      AuthorizedKernelPostimageContainmentReadiness.requiredRequirements(
        ratified.contract
      )
    )
    XCTAssertFalse(productionVetoTransaction.duplicate)
    let retainedProductionVetoOutcome =
      try await fixture
      .productionExecutionCoordinator.prepareCompletedCandidateMutation(
        productionApplyRequest
      )
    switch retainedProductionVetoOutcome {
    case .vetoed(let receipt, let transaction):
      XCTAssertEqual(receipt, productionVetoReceipt)
      XCTAssertEqual(transaction, productionVetoTransaction)
    case .prepared:
      return XCTFail("unchanged production retry must replay the exact veto")
    }
    var mismatchedRetainedVetoRequest = productionApplyRequest
    mismatchedRetainedVetoRequest.containmentVetoReceiptID = ReceiptID(
      "different-completed-candidate-containment-veto"
    )
    do {
      _ = try await fixture.productionExecutionCoordinator
        .prepareCompletedCandidateMutation(mismatchedRetainedVetoRequest)
      XCTFail("a substituted retained-veto identity must reject")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .mutationApplyVetoReceiptMismatch)
    }
    let vetoJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let replayedProductionVeto =
      await vetoJournal.productionMutationApplyVetoReceipt(
        receiptID: productionVetoReceipt.id
      )
    XCTAssertEqual(
      replayedProductionVeto,
      productionVetoReceipt
    )
    let transactionBeforeReadiness =
      await vetoJournal
      .integrationTransaction(
        transactionID:
          journaledRollback.authority.manifest.transactionID
      )
    XCTAssertEqual(transactionBeforeReadiness?.phase, .rollbackPrepared)
    let leaseBeforeReadiness = await vetoJournal.runtimeLease(
      resourceID: JournaledWorkspaceMutationLeaseAuthority.resourceID(
        workspaceID: enrollment.registration.workspaceID,
        rootIdentity:
          journaledRollback.authority.receipt.canonicalRootDigest
      )
    )
    XCTAssertNil(leaseBeforeReadiness)
    let preReadinessOutbox = try WorkspaceMutationEffectOutbox(
      rootDirectory: enrollment.registration.outboxRoot,
      runID: enrollment.runID
    )
    let effectsBeforeReadiness = try await preReadinessOutbox.allEntries()
    XCTAssertTrue(effectsBeforeReadiness.isEmpty)
    let crossWiredReadiness = try XCTUnwrap(
      AuthorizedKernelPostimageContainmentReadiness.testOnly(
        runID: enrollment.runID,
        integrationTransactionID: IntegrationTransactionID(
          "different-completed-candidate-transaction"
        ),
        contract: ratified.contract
      )
    )
    do {
      _ = try await fixture.productionExecutionCoordinator
        .prepareCompletedCandidateMutation(
          productionApplyRequest,
          containmentReadinessResolver: { _, _, _ in
            .authorized(crossWiredReadiness)
          }
        )
      XCTFail("cross-wired containment readiness must not admit apply")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .mutationApplyContainmentAuthorityMismatch)
    }
    let crossWiredJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let crossWiredLease = await crossWiredJournal.runtimeLease(
      resourceID: JournaledWorkspaceMutationLeaseAuthority.resourceID(
        workspaceID: enrollment.registration.workspaceID,
        rootIdentity:
          journaledRollback.authority.receipt.canonicalRootDigest
      )
    )
    XCTAssertNil(crossWiredLease)
    let exactReadiness = try XCTUnwrap(
      AuthorizedKernelPostimageContainmentReadiness.testOnly(
        runID: enrollment.runID,
        integrationTransactionID:
          journaledRollback.authority.manifest.transactionID,
        contract: ratified.contract
      )
    )
    XCTAssertEqual(
      exactReadiness.requirements.map(\.evidenceRecipeID),
      ratified.contract.requirementEvidenceRecipes?.map(\.id).sorted {
        $0.rawValue < $1.rawValue
      }
    )
    XCTAssertTrue(
      exactReadiness.requirements.allSatisfy {
        $0.maximumResidentBytes > 0 && $0.maximumChildProcesses == 0
      })
    var smuggledReadinessRequest = productionApplyRequest
    smuggledReadinessRequest.preparation.containmentReadiness = exactReadiness
    do {
      _ = try await fixture.productionExecutionCoordinator
        .prepareCompletedCandidateMutation(
          smuggledReadinessRequest,
          containmentReadinessResolver: { _, _, _ in
            .authorized(exactReadiness)
          }
        )
      XCTFail("the inner request must not smuggle containment authority")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .mutationApplyPreparationRequestInvalid)
    }
    let exactProductionApplyOutcome =
      try await fixture
      .productionExecutionCoordinator.prepareCompletedCandidateMutation(
        productionApplyRequest,
        containmentReadinessResolver: { _, _, _ in
          .authorized(exactReadiness)
        }
      )
    let applyPreparation: WorkspaceCompletedCandidateMutationApplyPreparationInstallation
    switch exactProductionApplyOutcome {
    case .prepared(let installation):
      applyPreparation = installation
    case .vetoed:
      return XCTFail("exact test containment must prepare bounded apply")
    }
    XCTAssertFalse(
      applyPreparation.leaseAdmission.journalTransaction.duplicate
    )
    XCTAssertFalse(applyPreparation.intentJournalTransaction.duplicate)
    XCTAssertEqual(
      applyPreparation.intent.stagedObjectSetDigest,
      journaledRollback.authority.receipt.contentObjectSetDigest
    )
    XCTAssertEqual(
      applyPreparation.intent.candidatePostimageCapturePolicyDigest,
      derivation.capturePolicyDigest
    )
    XCTAssertEqual(
      applyPreparation.effectEnvelope.state,
      .pending
    )
    guard
      case .apply(let enqueuedApply) =
        applyPreparation.effectEnvelope.payload
    else {
      return XCTFail("completed candidate must enqueue one apply payload")
    }
    XCTAssertEqual(enqueuedApply.intent, applyPreparation.intent)
    XCTAssertEqual(
      enqueuedApply.contentObjects,
      journaledRollback.authority.preparation.proposal.contentStore
        .objects
    )
    XCTAssertEqual(
      enqueuedApply.candidatePostimageCapturePolicy?.capturePolicyDigest,
      derivation.capturePolicyDigest
    )
    let applyingJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let applyingTransaction = await applyingJournal.integrationTransaction(
      transactionID: journaledRollback.authority.manifest.transactionID
    )
    XCTAssertEqual(applyingTransaction?.phase, .applying)
    let liveMutationLease = await applyingJournal.runtimeLease(
      resourceID: JournaledWorkspaceMutationLeaseAuthority.resourceID(
        workspaceID: enrollment.registration.workspaceID,
        rootIdentity:
          journaledRollback.authority.receipt.canonicalRootDigest
      )
    )
    XCTAssertNotNil(liveMutationLease)
    XCTAssertEqual(
      try String(contentsOf: canonicalFile, encoding: .utf8),
      "let canonicalBaseline = 1\n"
    )
    let duplicateProductionApplyOutcome =
      try await fixture
      .productionExecutionCoordinator.prepareCompletedCandidateMutation(
        productionApplyRequest,
        containmentReadinessResolver: { _, _, _ in
          .authorized(exactReadiness)
        }
      )
    let duplicateApplyPreparation: WorkspaceCompletedCandidateMutationApplyPreparationInstallation
    switch duplicateProductionApplyOutcome {
    case .prepared(let installation):
      duplicateApplyPreparation = installation
    case .vetoed:
      return XCTFail("exact prepared apply must replay its installation")
    }
    XCTAssertTrue(
      duplicateApplyPreparation.leaseAdmission.journalTransaction
        .duplicate
    )
    XCTAssertTrue(
      duplicateApplyPreparation.intentJournalTransaction.duplicate
    )
    XCTAssertEqual(
      duplicateApplyPreparation.effectEnvelope.payloadDigest,
      applyPreparation.effectEnvelope.payloadDigest
    )
    XCTAssertEqual(
      duplicateApplyPreparation.effectEnvelope.intentID,
      applyPreparation.effectEnvelope.intentID
    )
    let retainedQuitPlans = try await fixture
      .productionExecutionCoordinator
      .workspaceMutationApplicationTerminationPlans()
    XCTAssertEqual(retainedQuitPlans.count, 1)
    XCTAssertEqual(retainedQuitPlans.first?.runID, enrollment.runID)
    XCTAssertEqual(
      retainedQuitPlans.first?.transactionID,
      journaledRollback.authority.manifest.transactionID
    )
    XCTAssertEqual(
      retainedQuitPlans.first?.intentID,
      applyPreparation.intent.id
    )
    XCTAssertEqual(
      retainedQuitPlans.first?.payloadDigest,
      applyPreparation.effectEnvelope.payloadDigest
    )
    XCTAssertEqual(
      retainedQuitPlans.first?.action,
      .awaitJoin(
        resourceID: JournaledWorkspaceMutationLeaseAuthority.resourceID(
          workspaceID: enrollment.registration.workspaceID,
          rootIdentity:
            applyPreparation.leaseAdmission.executionLease.rootIdentity
        ),
        leaseID: applyRequest.leaseID
      )
    )
    let encodedPreparationFacts = try JSONEncoder().encode(
      preparationFacts.authority.receipt
    )
    let preparationFactsJSON = try XCTUnwrap(
      String(
        data: encodedPreparationFacts,
        encoding: .utf8
      ))
    for absentAuthorityKey in [
      "rollbackRehearsal",
      "candidateVerificationReceiptIDs",
      "independentReviewReceiptID",
      "visualGateReceiptID",
    ] {
      XCTAssertFalse(
        preparationFactsJSON.contains(
          "\"\(absentAuthorityKey)\""
        ))
    }
    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let recoveredCapture = await recovered.completedCandidateCaptureReceipt(
      attemptID: isolation.receipt.attemptID
    )
    let recoveredStore =
      await recovered
      .completedCandidateMutationContentStoreReceipt(
        derivationDigest: derivation.derivationDigest
      )
    let recoveredProposal =
      await recovered
      .completedCandidateMutationManifestProposalReceipt(
        derivationDigest: derivation.derivationDigest
      )
    let recoveredPreparationFacts =
      await recovered
      .completedCandidateMutationPreparationFactsReceipt(
        proposalReceiptDigest:
          manifestProposal.authority.receipt.receiptDigest
      )
    let recoveredRollback =
      await recovered
      .completedCandidateMutationRollbackRehearsalReceipt(
        proposalReceiptDigest:
          manifestProposal.authority.receipt.receiptDigest
      )
    let recoveredReport = await recovered.recoveryReport
    XCTAssertEqual(
      recoveredCapture,
      capture.receipt
    )
    XCTAssertEqual(recoveredStore, installation.authority.receipt)
    XCTAssertEqual(
      recoveredProposal,
      manifestProposal.authority.receipt
    )
    XCTAssertEqual(
      recoveredPreparationFacts,
      preparationFacts.authority.receipt
    )
    XCTAssertEqual(
      recoveredRollback,
      journaledRollback.authority.receipt
    )
    XCTAssertEqual(
      recoveredReport.lastFrameDigest,
      applyPreparation.intentJournalTransaction.frameDigest
    )
    let recoveredState = await recovered.state
    XCTAssertEqual(
      recoveredState.integrationTransactions[
        journaledRollback.authority.manifest.transactionID
      ]?.phase,
      .applying
    )
    let recoveredOutbox = try WorkspaceMutationEffectOutbox(
      rootDirectory: enrollment.registration.outboxRoot,
      runID: enrollment.runID
    )
    let recoveredPending = try await recoveredOutbox.pending(limit: 1)
    XCTAssertEqual(
      recoveredPending.map(\.payloadDigest),
      [applyPreparation.effectEnvelope.payloadDigest]
    )
    XCTAssertEqual(
      try String(
        contentsOf: fixture.workspace.appendingPathComponent(
          "main.swift"
        ), encoding: .utf8),
      "let canonicalBaseline = 1\n"
    )

    let exactQuitPlan = try XCTUnwrap(retainedQuitPlans.first)
    let tamperedQuitPlan = WorkspaceMutationApplicationTerminationPlan(
      runID: exactQuitPlan.runID,
      transactionID: exactQuitPlan.transactionID,
      intentID: exactQuitPlan.intentID,
      payloadDigest: ContentDigest("substituted-payload"),
      action: exactQuitPlan.action,
      releaseReceiptID: exactQuitPlan.releaseReceiptID,
      releaseCommandID: exactQuitPlan.releaseCommandID
    )
    do {
      _ = try await fixture.productionExecutionCoordinator
        .joinWorkspaceMutationsForApplicationTermination(
          expectedPlans: [tamperedQuitPlan]
        )
      XCTFail("termination cannot substitute the preflighted effect")
    } catch let error as WorkspaceMutationApplicationTerminationJoinError {
      XCTAssertEqual(error, .expectedPlanChanged)
    }
    XCTAssertEqual(
      try String(
        contentsOf: fixture.workspace.appendingPathComponent(
          "main.swift"
        ), encoding: .utf8),
      "let canonicalBaseline = 1\n"
    )
    let pendingAfterTamperedQuit = try await recoveredOutbox.pending(limit: 1)
    XCTAssertEqual(pendingAfterTamperedQuit, recoveredPending)

    let quitJoinReceipts = try await fixture
      .productionExecutionCoordinator
      .joinWorkspaceMutationsForApplicationTermination(
        expectedPlans: retainedQuitPlans
      )
    XCTAssertEqual(quitJoinReceipts.count, 1)
    XCTAssertEqual(quitJoinReceipts.first?.plan, retainedQuitPlans.first)
    XCTAssertEqual(
      quitJoinReceipts.first?.releaseReceiptID,
      applyRequest.releaseReceiptID
    )
    XCTAssertEqual(
      quitJoinReceipts.first?.finalIntegrationPhase,
      .appliedUnverified
    )
    let remainingQuitPlans = try await fixture
      .productionExecutionCoordinator
      .workspaceMutationApplicationTerminationPlans()
    XCTAssertTrue(remainingQuitPlans.isEmpty)

    let executionObservedAt = applyIssuedAt.addingTimeInterval(1)
    let productionRecovery = try WorkspaceMutationRecoveryCoordinator(
      registry: fixture.registry,
      wallClock: { executionObservedAt },
      monotonicClock: { 1_000_001_000 }
    )
    let dispatched = try await productionRecovery.recoverRegisteredRuns()
    let dispatchedRun = try XCTUnwrap(dispatched.runReports.first)
    XCTAssertEqual(dispatchedRun.scannedCount, 0)
    XCTAssertEqual(dispatchedRun.completedIntentIDs, [])
    XCTAssertEqual(dispatchedRun.dispatchFailures, [])
    XCTAssertEqual(dispatchedRun.quarantinedIntentIDs, [])
    XCTAssertFalse(dispatchedRun.remainingExecutableEffects)
    XCTAssertEqual(
      dispatchedRun.unresolvedIntegrationTransactionCount,
      1
    )
    XCTAssertTrue(dispatched.requiresAttention)

    let appliedJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let optionalAppliedTransaction =
      await appliedJournal
      .integrationTransaction(
        transactionID:
          journaledRollback.authority.manifest.transactionID
      )
    let appliedTransaction = try XCTUnwrap(optionalAppliedTransaction)
    XCTAssertEqual(appliedTransaction.phase, .appliedUnverified)
    let applyReceipt = try XCTUnwrap(appliedTransaction.applyReceipt)
    guard case .exactPostimage = applyReceipt.outcome else {
      return XCTFail("the completed candidate must apply exactly")
    }
    XCTAssertEqual(applyReceipt.completedAt, executionObservedAt)
    XCTAssertEqual(
      applyReceipt.observedPostimageDigest,
      derivation.candidateSourceRevision
    )
    XCTAssertEqual(
      applyReceipt.candidatePostimage?.sourceRevision,
      derivation.candidateSourceRevision
    )
    XCTAssertEqual(
      try String(
        contentsOf: fixture.workspace.appendingPathComponent(
          "main.swift"
        ), encoding: .utf8),
      "let canonicalCandidate = 2\n"
    )
    let releasedLease = await appliedJournal.runtimeLease(
      resourceID: JournaledWorkspaceMutationLeaseAuthority.resourceID(
        workspaceID: enrollment.registration.workspaceID,
        rootIdentity:
          applyPreparation.leaseAdmission.executionLease.rootIdentity
      )
    )
    XCTAssertNil(releasedLease)
    let acceptedAttestation =
      try await appliedJournal
      .latestAcceptedWorkspaceCandidatePostimageAttestation(
        workspaceID: enrollment.registration.workspaceID,
        root: fixture.workspace
      )
    guard case .accepted(let attestation) = acceptedAttestation else {
      return XCTFail("exact apply must journal candidate postimage authority")
    }
    XCTAssertEqual(attestation.applyReceiptID, applyReceipt.id)
    XCTAssertEqual(
      attestation.candidatePostimage,
      applyReceipt.candidatePostimage
    )
    let appliedRunDirectory = await appliedJournal.runDirectory
    _ = try KernelExecutableStager().stage(
      executablePath: kernelProcessFixturePath,
      expectedDigest: verifierExecutableDigest,
      runDirectory: appliedRunDirectory
    )
    let candidateInput = try WorkspaceCandidatePostimageMaterializer()
      .materialize(
        attestation: attestation,
        workspaceRoot: fixture.workspace,
        runDirectory: appliedRunDirectory
      )
    let postimageVerifier = ActorIdentity(
      id: ActorID("completed-candidate-postimage-verifier"),
      role: "postimage-verifier",
      lineageDigest: ContentDigest(
        "completed-candidate-postimage-verifier-lineage"
      )
    )
    let verifierActivationRequest =
      KernelPostimageVerifierActivationRequest(
        workspaceRoot: fixture.workspace,
        integrationTransactionID:
          journaledRollback.authority.manifest.transactionID,
        evidenceRecipeID: EvidenceRecipeID("enrollment-recipe"),
        verifier: postimageVerifier,
        candidateInput: candidateInput,
        receiptID: ReceiptID(
          "completed-candidate-postimage-verifier-activation"
        ),
        commandID: RunCommandID(
          "activate-completed-candidate-postimage-verifier"
        ),
        activatedAt: executionObservedAt.addingTimeInterval(1)
      )
    let activatedVerifier = try await KernelPostimageVerifierActivationCoordinator(
      journal: appliedJournal
    ).activate(verifierActivationRequest)
    XCTAssertEqual(
      activatedVerifier.receipt.applyReceiptID,
      applyReceipt.id
    )
    XCTAssertEqual(
      activatedVerifier.receipt.sourceRevision,
      derivation.candidateSourceRevision
    )
    XCTAssertEqual(
      activatedVerifier.receipt.executableStaging.contentDigest,
      verifierExecutableDigest
    )
    XCTAssertEqual(
      activatedVerifier.receipt.resolvedArguments.last,
      KernelPostimageVerifierActivationCompiler
        .candidateInputDescriptorPath
    )
    let recoveredVerifierJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let recoveredRunDirectory = await recoveredVerifierJournal.runDirectory
    let recoveredCandidateInput = try WorkspaceCandidatePostimageMaterializer().materialize(
      attestation: attestation,
      workspaceRoot: fixture.workspace,
      runDirectory: recoveredRunDirectory
    )
    XCTAssertTrue(recoveredCandidateInput.receipt.reusedExistingArtifact)
    XCTAssertNotEqual(
      recoveredCandidateInput.receipt.materialization,
      candidateInput.receipt.materialization
    )
    var recoveredVerifierActivationRequest = verifierActivationRequest
    recoveredVerifierActivationRequest.candidateInput =
      recoveredCandidateInput
    let replayedVerifierActivation = try await KernelPostimageVerifierActivationCoordinator(
      journal: recoveredVerifierJournal
    ).activate(recoveredVerifierActivationRequest)
    XCTAssertEqual(
      replayedVerifierActivation.receipt,
      activatedVerifier.receipt
    )
    XCTAssertEqual(
      replayedVerifierActivation.activationTransaction,
      activatedVerifier.activationTransaction
    )
    let unavailableVerifierRuntime = JournaledProcessRuntime(
      supervisor: RuntimeSupervisor(
        runID: enrollment.runID,
        budget: enrollment.registration.hostBudget
      ),
      journal: recoveredVerifierJournal,
      actorIdentity: postimageVerifier
    )
    let verifierRuntimeRequest = KernelPostimageVerifierRuntimeRequest(
      leaseID: ResourceLeaseID(
        "completed-candidate-postimage-verifier-lease"
      ),
      resourceID: OwnedResourceID(
        "completed-candidate-postimage-verifier-process"
      ),
      standardOutputFileName:
        "completed-candidate-postimage-verifier.stdout",
      standardErrorFileName:
        "completed-candidate-postimage-verifier.stderr",
      admissionReceiptID: ReceiptID(
        "completed-candidate-postimage-verifier-admission"
      ),
      admissionCommandID: RunCommandID(
        "admit-completed-candidate-postimage-verifier"
      ),
      bindingReceiptID: ReceiptID(
        "completed-candidate-postimage-verifier-binding"
      ),
      launchReceiptID: ReceiptID(
        "completed-candidate-postimage-verifier-launch"
      ),
      bindingCommandID: RunCommandID(
        "bind-completed-candidate-postimage-verifier"
      ),
      launchFailureReleaseReceiptID: ReceiptID(
        "fail-completed-candidate-postimage-verifier-launch"
      ),
      launchFailureReleaseCommandID: RunCommandID(
        "fail-completed-candidate-postimage-verifier-launch"
      ),
      launchVetoReceiptID: ReceiptID(
        "completed-candidate-postimage-verifier-launch-veto"
      ),
      launchVetoCommandID: RunCommandID(
        "completed-candidate-postimage-verifier-launch-veto"
      )
    )
    do {
      _ =
        try await unavailableVerifierRuntime
        .admitAndLaunchPostimageVerifier(
          invocation: replayedVerifierActivation,
          request: verifierRuntimeRequest
        )
      XCTFail(
        "production verification must retain the resident-memory veto"
      )
    } catch JournaledProcessRuntimeError
      .residentMemoryEnforcementUnavailable
    {}
    let unavailableVerifierLease = await recoveredVerifierJournal.runtimeLease(
      resourceID: verifierRuntimeRequest.resourceID
    )
    XCTAssertNil(unavailableVerifierLease)
    let unavailableVerifierLaunch =
      await recoveredVerifierJournal
      .postimageVerifierLaunchReceipt(
        receiptID: verifierRuntimeRequest.launchReceiptID
      )
    XCTAssertNil(unavailableVerifierLaunch)
    let recordedUnavailableVerifierVeto =
      await recoveredVerifierJournal
      .postimageVerifierLaunchVetoReceipt(
        receiptID: verifierRuntimeRequest.launchVetoReceiptID
      )
    let unavailableVerifierVeto = try XCTUnwrap(
      recordedUnavailableVerifierVeto
    )
    XCTAssertEqual(
      unavailableVerifierVeto.activationReceiptID,
      replayedVerifierActivation.receipt.id
    )
    XCTAssertEqual(
      unavailableVerifierVeto.activationJournalFrameDigest,
      replayedVerifierActivation.activationTransaction.frameDigest
    )
    XCTAssertEqual(
      unavailableVerifierVeto.requiredMaximumResidentBytes,
      replayedVerifierActivation.receipt.resourceLimits
        .maximumResidentBytes
    )
    XCTAssertEqual(
      unavailableVerifierVeto.reason,
      .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
    )
    let vetoReplayJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let replayedUnavailableVerifierVeto =
      await vetoReplayJournal
      .postimageVerifierLaunchVetoReceipt(
        receiptID: verifierRuntimeRequest.launchVetoReceiptID
      )
    XCTAssertEqual(
      replayedUnavailableVerifierVeto,
      unavailableVerifierVeto
    )
    let verificationVetoTransaction =
      await recoveredVerifierJournal
      .integrationTransaction(
        transactionID:
          journaledRollback.authority.manifest.transactionID
      )
    XCTAssertEqual(
      verificationVetoTransaction?.phase,
      .appliedUnverified
    )
    let completedOutbox = try WorkspaceMutationEffectOutbox(
      rootDirectory: enrollment.registration.outboxRoot,
      runID: enrollment.runID
    )
    let remainingPending = try await completedOutbox.pending(limit: 1)
    XCTAssertTrue(remainingPending.isEmpty)
    let completedEntries = try await completedOutbox.allEntries()
    let completedEntry = try XCTUnwrap(completedEntries.first)
    guard case .completed(_, let completedAt) = completedEntry.state else {
      return XCTFail("the accepted journal receipt must retire the outbox effect")
    }
    XCTAssertEqual(completedAt, executionObservedAt)

    let rollbackObservedAt = max(
      unavailableVerifierVeto.observedAt,
      applyReceipt.completedAt
    ).addingTimeInterval(1)
    let rollbackPreparationJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let rollbackPreparationSupervisor = RuntimeSupervisor(
      runID: enrollment.runID,
      budget: enrollment.registration.hostBudget
    )
    guard
      case .restored = await rollbackPreparationSupervisor.restore(
        from:
          await rollbackPreparationJournal
          .runtimeSupervisorRecoverySnapshot()
      )
    else {
      return XCTFail("rollback preparation supervisor must restore")
    }
    let rollbackPreparationOutbox = try WorkspaceMutationEffectOutbox(
      rootDirectory: enrollment.registration.outboxRoot,
      runID: enrollment.runID
    )
    let rollbackPreparationAuthority =
      JournaledWorkspaceMutationLeaseAuthority(
        supervisor: rollbackPreparationSupervisor,
        journal: rollbackPreparationJournal,
        actorIdentity: enrollment.registration.actorIdentity
      )
    let preparedBeforeDispatch =
      try await WorkspacePostimageVerifierVetoRollbackPreparationCoordinator(
        registry: fixture.registry,
        registration: enrollment.registration,
        journal: rollbackPreparationJournal,
        outbox: rollbackPreparationOutbox,
        leaseAuthority: rollbackPreparationAuthority,
        wallClock: { rollbackObservedAt },
        monotonicClock: { 2_000_001_000 }
      ).prepareEligibleRollbacks(limit: 1)
    let firstPreparedRollback = try XCTUnwrap(
      preparedBeforeDispatch.first
    )
    XCTAssertFalse(
      firstPreparedRollback.leaseAdmission.journalTransaction.duplicate
    )
    XCTAssertEqual(firstPreparedRollback.effectEnvelope.state, .pending)

    // Simulate a crash after lease admission/outbox persistence but before
    // dispatch. Reopening every durable component can only replay the
    // exact admission and rollback payload.
    let replayPreparationJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let replayPreparationSupervisor = RuntimeSupervisor(
      runID: enrollment.runID,
      budget: enrollment.registration.hostBudget
    )
    guard
      case .restored = await replayPreparationSupervisor.restore(
        from:
          await replayPreparationJournal
          .runtimeSupervisorRecoverySnapshot()
      )
    else {
      return XCTFail("replayed rollback supervisor must restore")
    }
    let replayPreparationOutbox = try WorkspaceMutationEffectOutbox(
      rootDirectory: enrollment.registration.outboxRoot,
      runID: enrollment.runID
    )
    let replayPreparationAuthority =
      JournaledWorkspaceMutationLeaseAuthority(
        supervisor: replayPreparationSupervisor,
        journal: replayPreparationJournal,
        actorIdentity: enrollment.registration.actorIdentity
      )
    let replayedPreparation =
      try await WorkspacePostimageVerifierVetoRollbackPreparationCoordinator(
        registry: fixture.registry,
        registration: enrollment.registration,
        journal: replayPreparationJournal,
        outbox: replayPreparationOutbox,
        leaseAuthority: replayPreparationAuthority,
        wallClock: { rollbackObservedAt },
        monotonicClock: { 2_000_001_000 }
      ).prepareEligibleRollbacks(limit: 1)
    let replayedPreparedRollback = try XCTUnwrap(
      replayedPreparation.first
    )
    XCTAssertTrue(
      replayedPreparedRollback.leaseAdmission.journalTransaction.duplicate
    )
    XCTAssertEqual(
      replayedPreparedRollback.intent,
      firstPreparedRollback.intent
    )
    XCTAssertEqual(
      replayedPreparedRollback.effectEnvelope.payloadDigest,
      firstPreparedRollback.effectEnvelope.payloadDigest
    )

    let rollbackRecovery = try WorkspaceMutationRecoveryCoordinator(
      registry: fixture.registry,
      wallClock: { rollbackObservedAt },
      monotonicClock: { 2_000_001_000 }
    )
    let replayedDispatch =
      try await rollbackRecovery
      .recoverRegisteredRuns()
    let rollbackReport = try XCTUnwrap(replayedDispatch.runReports.first)
    XCTAssertNil(rollbackReport.failure)
    XCTAssertTrue(
      rollbackReport.dispatchFailures.isEmpty,
      "\(rollbackReport.dispatchFailures)"
    )
    XCTAssertTrue(rollbackReport.quarantinedIntentIDs.isEmpty)
    XCTAssertEqual(rollbackReport.scannedCount, 1)
    XCTAssertEqual(rollbackReport.preparedRollbackIntentIDs?.count, 1)
    XCTAssertEqual(
      rollbackReport.completedIntentIDs,
      rollbackReport.preparedRollbackIntentIDs ?? []
    )
    XCTAssertEqual(
      rollbackReport.unresolvedIntegrationTransactionCount,
      0
    )
    XCTAssertFalse(replayedDispatch.requiresAttention)
    XCTAssertEqual(
      try String(
        contentsOf: fixture.workspace.appendingPathComponent(
          "main.swift"
        ), encoding: .utf8),
      "let canonicalBaseline = 1\n"
    )
    let rolledBackJournal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let rolledBackTransaction =
      await rolledBackJournal
      .integrationTransaction(
        transactionID:
          journaledRollback.authority.manifest.transactionID
      )
    XCTAssertEqual(rolledBackTransaction?.phase, .rolledBack)
    guard case .restored = rolledBackTransaction?.rollbackReceipt?.outcome
    else {
      return XCTFail("the containment veto must recover the exact preimage")
    }

    let exactReplay = try await rollbackRecovery.recoverRegisteredRuns()
    XCTAssertEqual(exactReplay.runReports.first?.scannedCount, 0)
    XCTAssertEqual(
      exactReplay.runReports.first?.preparedRollbackIntentIDs,
      Optional([])
    )
    XCTAssertFalse(exactReplay.requiresAttention)
  }

  func testMutationActivationRejectsSubstitutedOrStaleIsolationBeforeStart()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try Data("let canonicalBaseline = 1\n".utf8).write(
      to: fixture.workspace.appendingPathComponent("main.swift")
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let coordinator = WorkspacePreApplyCandidateIsolationCoordinator(
      registry: fixture.registry
    )
    let accepted = try await coordinator.isolate(
      enrollment: enrollment,
      attemptID: AttemptID("enrollment-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { accepted.close() }
    let substituted = try await coordinator.isolate(
      enrollment: enrollment,
      attemptID: AttemptID("substituted-attempt"),
      nodeID: KernelNodeID("enrollment-node"),
      isolatedAt: Date(timeIntervalSince1970: 5)
    )
    defer { substituted.close() }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    _ = try await journal.recordPreApplyCandidateIsolation(
      accepted,
      commandID: RunCommandID("accept-preapply-isolation")
    )
    let preparation = try await fixture.preparationRequest(
      enrollment: enrollment
    )
    let before = await journal.headSnapshot()

    for authority in [substituted, accepted] {
      if authority === accepted {
        try Data("let candidateDrift = true\n".utf8).write(
          to: URL(
            fileURLWithPath: accepted.receipt.candidateRootPath,
            isDirectory: true
          ).appendingPathComponent("main.swift")
        )
      }
      do {
        _ = try await fixture.productionExecutionCoordinator.activate(
          KernelProductionExecutionCompositionRequest(
            preparation: preparation,
            startCommandID: RunCommandID(
              authority === accepted
                ? "stale-isolation-start"
                : "substituted-isolation-start"
            ),
            activatedAt: Date(timeIntervalSince1970: 6),
            preApplyCandidateIsolation: authority
          )
        )
        XCTFail("activation must reject substituted or stale authority")
      } catch let error as KernelProductionExecutionCompositionError {
        XCTAssertEqual(
          error,
          .preApplyCandidateIsolationAuthorityMissing
        )
      }
      let after = await journal.headSnapshot()
      XCTAssertEqual(after, before)
    }
  }

  func testReadOnlyReadinessDoesNotRequireMutationPreparationAuthority()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(
        workspace: fixture.workspace,
        mutationCapable: false
      ))
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )

    let readiness = try await fixture.productionExecutionCoordinator
      .nativeExecutionReadiness(for: enrollment)

    XCTAssertTrue(readiness.canPrepareAndActivate)
    XCTAssertTrue(readiness.blockers.isEmpty)
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await journal.state
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertEqual(state.phase, .ready)
  }

  func testProductionCompositionRejectsActorSwapBeforePreparation() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    var preparation = try await fixture.preparationRequest(enrollment: enrollment)
    preparation.actorIdentity = ActorIdentity(
      id: ActorID("legacy-controller"),
      role: "legacy-controller",
      lineageDigest: ContentDigest("legacy-controller-lineage")
    )

    do {
      _ = try await fixture.productionExecutionCoordinator.activate(
        KernelProductionExecutionCompositionRequest(
          preparation: preparation,
          startCommandID: RunCommandID("swapped-start"),
          activatedAt: Date(timeIntervalSince1970: 6)
        )
      )
      XCTFail("legacy controller identity must not enter production composition")
    } catch let error as KernelProductionExecutionCompositionError {
      XCTAssertEqual(error, .actorBoundaryMismatch)
    }

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recovered.state
    XCTAssertEqual(state.phase, .ready)
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertTrue(state.attempts.isEmpty)
  }

  func testAlteredConfirmedBudgetLeavesEnrolledRunUnchanged() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(candidate: try candidate(workspace: fixture.workspace))
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    var request = try await fixture.preparationRequest(enrollment: enrollment)
    request.convergenceBudget.maximumAttempts = 0

    do {
      _ = try await fixture.executionCoordinator.prepare(request)
      XCTFail("a caller cannot replace the user-confirmed convergence budget")
    } catch let error as KernelExecutionPreparationError {
      guard case .invalidPreparation(let reason) = error,
        reason.contains("user-confirmed strategy")
      else {
        return XCTFail("unexpected preparation error: \(error)")
      }
    }

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recovered.state
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertEqual(state.phase, .ready)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertNil(state.convergenceGovernor)
    XCTAssertTrue(state.attempts.isEmpty)
  }

  func testPreparationCannotSubstituteConfirmedPlanOrStrategy() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let exact = try await fixture.preparationRequest(enrollment: enrollment)

    var changedPlan = exact
    changedPlan.plan.nodes[0].objective = "Caller-substituted plan"
    do {
      _ = try await fixture.executionCoordinator.prepare(changedPlan)
      XCTFail("caller-substituted plan must fail before journaling")
    } catch let error as KernelExecutionPreparationError {
      guard case .invalidPreparation = error else {
        return XCTFail("unexpected plan-substitution error: \(error)")
      }
    }

    var changedStrategy = exact
    changedStrategy.admission.strategy.actionClass = "caller-substituted-action"
    do {
      _ = try await fixture.executionCoordinator.prepare(changedStrategy)
      XCTFail("caller-substituted strategy must fail before journaling")
    } catch let error as KernelExecutionPreparationError {
      guard case .invalidPreparation = error else {
        return XCTFail("unexpected strategy-substitution error: \(error)")
      }
    }

    var changedRollback = exact
    changedRollback.admission.rollbackPoint = ContentDigest("caller-rollback")
    do {
      _ = try await fixture.executionCoordinator.prepare(changedRollback)
      XCTFail("caller-substituted rollback revision must fail before journaling")
    } catch let error as KernelExecutionPreparationError {
      guard case .invalidPreparation = error else {
        return XCTFail("unexpected rollback-substitution error: \(error)")
      }
    }

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recovered.state
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertNil(state.convergenceGovernor)
  }

  func testPreparationCommandIDConflictLeavesEnrolledRunUnchanged() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let ratified = try ratifiedContract(candidate: try candidate(workspace: fixture.workspace))
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    var request = try await fixture.preparationRequest(enrollment: enrollment)
    request.planCommandID = enrollment.journalTransaction.commandID

    do {
      _ = try await fixture.executionCoordinator.prepare(request)
      XCTFail("a preparation command cannot reuse enrollment authority")
    } catch let error as KernelExecutionPreparationError {
      XCTAssertEqual(
        error,
        .journalRejected(
          .duplicateCommand(enrollment.journalTransaction.commandID)
        )
      )
    }

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let state = await recovered.state
    XCTAssertEqual(state.sequence, enrollment.journalTransaction.endingSequence)
    XCTAssertEqual(state.phase, .ready)
    XCTAssertTrue(state.nodes.isEmpty)
    XCTAssertNil(state.convergenceGovernor)
    XCTAssertTrue(state.attempts.isEmpty)
  }

  func testRatifiedBaselineCaptureIssuesOnlyDescriptorObservedPreimageBytes() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = fixture.workspace.appendingPathComponent("Sources/a.txt")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let old = Data("ratified-old".utf8)
    let new = Data("candidate-new".utf8)
    try old.write(to: source)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let base = try XCTUnwrap(ratified.contract.sourceRevision)
    try new.write(to: source)
    let candidate = try WorkspaceSourceRevisionCollector().capture(
      workspaceID: base.workspaceID,
      root: fixture.workspace,
      excludedDirectoryNames: Set(base.excludedDirectoryNames),
      limits: base.limits
    )
    let derivation = try WorkspaceMutationOperationDeriver().derive(
      base: base,
      candidate: candidate,
      requirementIDs: [RequirementID("enrollment-outcome")],
      authorizedPaths: ["Sources/a.txt"]
    )
    try old.write(to: source)

    let issuer = WorkspaceRatifiedBaselineContentCaptureIssuer(
      registry: fixture.registry
    )
    let authorized = try await issuer.capture(
      enrollment: enrollment,
      derivation: derivation
    )

    XCTAssertTrue(authorized.receipt.validationIssues().isEmpty)
    XCTAssertEqual(authorized.receipt.runID, enrollment.runID)
    XCTAssertEqual(
      authorized.receipt.enrollmentJournalFrameDigest,
      enrollment.journalTransaction.frameDigest
    )
    XCTAssertEqual(authorized.objects.map(\.data), [old])
    XCTAssertEqual(
      authorized.objects.map(\.digest),
      [WorkspaceMutationFilesystemExecutor.contentDigest(old)]
    )
    XCTAssertFalse(
      authorized.objects.contains {
        $0.digest == WorkspaceMutationFilesystemExecutor.contentDigest(new)
      })
    let revalidated = try await issuer.revalidate(authorized)
    XCTAssertEqual(revalidated, authorized.receipt)
  }

  func testRatifiedBaselineCaptureRejectsChangedOrSymlinkedBaseline() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = fixture.workspace.appendingPathComponent("Sources/a.txt")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("old".utf8).write(to: source)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let base = try XCTUnwrap(ratified.contract.sourceRevision)
    try Data("new".utf8).write(to: source)
    let candidate = try WorkspaceSourceRevisionCollector().capture(
      workspaceID: base.workspaceID,
      root: fixture.workspace,
      excludedDirectoryNames: Set(base.excludedDirectoryNames),
      limits: base.limits
    )
    let derivation = try WorkspaceMutationOperationDeriver().derive(
      base: base,
      candidate: candidate,
      requirementIDs: [RequirementID("enrollment-outcome")],
      authorizedPaths: ["Sources/a.txt"]
    )
    let issuer = WorkspaceRatifiedBaselineContentCaptureIssuer(
      registry: fixture.registry
    )

    do {
      _ = try await issuer.capture(
        enrollment: enrollment,
        derivation: derivation
      )
      XCTFail("a changed baseline must not issue byte authority")
    } catch {
      XCTAssertEqual(
        error as? WorkspaceRatifiedBaselineContentCaptureError,
        .baselineChanged
      )
    }

    try FileManager.default.removeItem(at: source)
    try FileManager.default.createSymbolicLink(
      at: source,
      withDestinationURL: fixture.container.appendingPathComponent("outside")
    )
    do {
      _ = try await issuer.capture(
        enrollment: enrollment,
        derivation: derivation
      )
      XCTFail("a symlinked baseline must not issue byte authority")
    } catch {
      XCTAssertEqual(
        error as? WorkspaceRatifiedBaselineContentCaptureError,
        .baselineChanged
      )
    }
  }

  func testRatifiedBaselineCaptureRejectsAnotherWorkspaceDerivation() async throws {
    let fixture = try Fixture()
    let other = try Fixture()
    defer {
      fixture.remove()
      other.remove()
    }
    let enrolledSource = fixture.workspace.appendingPathComponent("Sources/a.txt")
    let otherSource = other.workspace.appendingPathComponent("Sources/a.txt")
    try FileManager.default.createDirectory(
      at: enrolledSource.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: otherSource.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("enrolled".utf8).write(to: enrolledSource)
    try Data("other-old".utf8).write(to: otherSource)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let otherBase = try XCTUnwrap(
      try candidate(workspace: other.workspace).contract.sourceRevision
    )
    try Data("other-new".utf8).write(to: otherSource)
    let otherCandidate = try WorkspaceSourceRevisionCollector().capture(
      workspaceID: otherBase.workspaceID,
      root: other.workspace,
      excludedDirectoryNames: Set(otherBase.excludedDirectoryNames),
      limits: otherBase.limits
    )
    let otherDerivation = try WorkspaceMutationOperationDeriver().derive(
      base: otherBase,
      candidate: otherCandidate,
      requirementIDs: [RequirementID("enrollment-outcome")],
      authorizedPaths: ["Sources/a.txt"]
    )

    do {
      _ = try await WorkspaceRatifiedBaselineContentCaptureIssuer(
        registry: fixture.registry
      ).capture(
        enrollment: enrollment,
        derivation: otherDerivation
      )
      XCTFail("another workspace's derivation must not be transferable")
    } catch {
      XCTAssertEqual(
        error as? WorkspaceRatifiedBaselineContentCaptureError,
        .baselineAuthorityMismatch
      )
    }
  }

  func testRatifiedBaselineCaptureRejectsCallerSubstitutedEnrollment() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = fixture.workspace.appendingPathComponent("Sources/a.txt")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let old = Data("old".utf8)
    try old.write(to: source)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    var enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let base = try XCTUnwrap(ratified.contract.sourceRevision)
    try Data("new".utf8).write(to: source)
    let candidate = try WorkspaceSourceRevisionCollector().capture(
      workspaceID: base.workspaceID,
      root: fixture.workspace,
      excludedDirectoryNames: Set(base.excludedDirectoryNames),
      limits: base.limits
    )
    let derivation = try WorkspaceMutationOperationDeriver().derive(
      base: base,
      candidate: candidate,
      requirementIDs: [RequirementID("enrollment-outcome")],
      authorizedPaths: ["Sources/a.txt"]
    )
    try old.write(to: source)
    enrollment.registration.maximumDispatchBatch += 1

    do {
      _ = try await WorkspaceRatifiedBaselineContentCaptureIssuer(
        registry: fixture.registry
      ).capture(
        enrollment: enrollment,
        derivation: derivation
      )
      XCTFail("a caller-substituted enrollment must not issue authority")
    } catch {
      XCTAssertEqual(
        error as? WorkspaceRatifiedBaselineContentCaptureError,
        .registrationMismatch
      )
    }
  }

  func testRatifiedBaselineCaptureIsJournaledAndRecoveredAsReceiptOnly() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let prepared = try await prepareBaselineCapture(fixture)
    let journal = try RunJournal(
      rootDirectory: prepared.enrollment.registration.journalRoot,
      runID: prepared.enrollment.runID
    )

    let transaction = try await journal.recordRatifiedBaselineContentCapture(
      prepared.authority,
      commandID: RunCommandID("capture-baseline")
    )

    XCTAssertFalse(transaction.duplicate)
    let accepted = await journal.ratifiedBaselineContentCaptureReceipt(
      transaction: transaction
    )
    XCTAssertEqual(accepted, prepared.authority.receipt)
    let recovered = try RunJournal(
      rootDirectory: prepared.enrollment.registration.journalRoot,
      runID: prepared.enrollment.runID
    )
    let recoveredCapture = await recovered.ratifiedBaselineContentCaptureReceipt(
      derivationDigest: prepared.authority.receipt.derivationDigest
    )
    XCTAssertEqual(recoveredCapture, prepared.authority.receipt)
    let recoveredTransaction = await recovered.transactionReceipt(
      commandID: RunCommandID("capture-baseline")
    )
    XCTAssertEqual(recoveredTransaction, transaction)
  }

  func testRatifiedBaselineJournalRejectsCapabilityWhoseBytesDoNotMatchReceipt() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let prepared = try await prepareBaselineCapture(fixture)
    let journal = try RunJournal(
      rootDirectory: prepared.enrollment.registration.journalRoot,
      runID: prepared.enrollment.runID
    )
    let before = await journal.headSnapshot()
    let corrupt = AuthorizedWorkspaceRatifiedBaselineContent.testOnly(
      receipt: prepared.authority.receipt,
      objects: [
        WorkspaceMutationContentObject(
          digest: prepared.authority.objects[0].digest,
          data: Data("substituted".utf8)
        )
      ]
    )

    do {
      _ = try await journal.recordRatifiedBaselineContentCapture(
        corrupt,
        commandID: RunCommandID("capture-corrupt")
      )
      XCTFail("receipt-shaped data must not substitute different bytes")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .reducerRejected(
          .invalidBaselineContentCapture(
            "the live baseline-content capability does not match its receipt"
          ))
      )
    }
    let after = await journal.headSnapshot()
    XCTAssertEqual(after, before)
  }

  func testRatifiedBaselineJournalMakesCommandIdempotencyContentExact() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let prepared = try await prepareBaselineCapture(fixture)
    let journal = try RunJournal(
      rootDirectory: prepared.enrollment.registration.journalRoot,
      runID: prepared.enrollment.runID
    )
    let commandID = RunCommandID("capture-idempotent")
    let first = try await journal.recordRatifiedBaselineContentCapture(
      prepared.authority,
      commandID: commandID
    )
    let duplicate = try await journal.recordRatifiedBaselineContentCapture(
      prepared.authority,
      commandID: commandID
    )
    XCTAssertFalse(first.duplicate)
    XCTAssertTrue(duplicate.duplicate)

    let recaptured = try await WorkspaceRatifiedBaselineContentCaptureIssuer(
      registry: fixture.registry
    ).capture(
      enrollment: prepared.enrollment,
      derivation: prepared.derivation
    )
    XCTAssertNotEqual(recaptured.receipt, prepared.authority.receipt)
    do {
      _ = try await journal.recordRatifiedBaselineContentCapture(
        recaptured,
        commandID: commandID
      )
      XCTFail("one idempotency key cannot hide a different capture")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .baselineContentCaptureCommandConflict(commandID: commandID)
      )
    }
  }

  func testGitPreimageCaptureJournalsExactHeadIndexAndUntrackedPlanes()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try git(fixture.workspace, ["init", "-q", "-b", "main"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(fixture.workspace, ["config", "user.email", "loopforge@example.invalid"])
    let tracked = fixture.workspace.appendingPathComponent("tracked.txt")
    try Data("head-bytes".utf8).write(to: tracked)
    try git(fixture.workspace, ["add", "tracked.txt"])
    try git(fixture.workspace, ["commit", "-qm", "baseline"])
    try Data("index-bytes".utf8).write(to: tracked)
    try git(fixture.workspace, ["add", "tracked.txt"])
    try Data("untracked-bytes".utf8).write(
      to: fixture.workspace.appendingPathComponent("untracked.txt")
    )
    try Data("ignored.txt\n".utf8).write(
      to: fixture.workspace.appendingPathComponent(".git/info/exclude")
    )
    try Data("ignored-bytes".utf8).write(
      to: fixture.workspace.appendingPathComponent("ignored.txt")
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let authority = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)

    XCTAssertTrue(authority.validationIssues().isEmpty)
    XCTAssertEqual(authority.receipt.head.entries.map(\.path), ["tracked.txt"])
    XCTAssertEqual(authority.receipt.index.entries.map(\.path), ["tracked.txt"])
    XCTAssertEqual(
      authority.receipt.untracked.entries.map(\.path),
      ["ignored.txt", "untracked.txt"]
    )
    XCTAssertEqual(
      authority.receipt.head.entries[0].contentDigest,
      WorkspaceMutationFilesystemExecutor.contentDigest(Data("head-bytes".utf8))
    )
    XCTAssertEqual(
      authority.receipt.index.entries[0].contentDigest,
      WorkspaceMutationFilesystemExecutor.contentDigest(Data("index-bytes".utf8))
    )
    XCTAssertEqual(
      authority.receipt.untracked.entries[1].contentDigest,
      WorkspaceMutationFilesystemExecutor.contentDigest(Data("untracked-bytes".utf8))
    )
    XCTAssertEqual(
      authority.receipt.untracked.entries[0].contentDigest,
      WorkspaceMutationFilesystemExecutor.contentDigest(Data("ignored-bytes".utf8))
    )

    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let commandID = RunCommandID("capture-git-preimage")
    let first = try await journal.recordJournaledGitPreimageCapture(
      authority,
      commandID: commandID
    )
    let duplicate = try await journal.recordJournaledGitPreimageCapture(
      authority,
      commandID: commandID
    )
    XCTAssertFalse(first.duplicate)
    XCTAssertTrue(duplicate.duplicate)
    let accepted = await journal.journaledGitPreimageCaptureReceipt(
      transaction: first
    )
    XCTAssertEqual(accepted, authority.receipt)
    let recaptured = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)
    XCTAssertNotEqual(recaptured.receipt, authority.receipt)
    do {
      _ = try await journal.recordJournaledGitPreimageCapture(
        recaptured,
        commandID: commandID
      )
      XCTFail("one command identity cannot hide a different Git observation")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .gitPreimageCaptureCommandConflict(commandID: commandID)
      )
    }
    var tamperedReceipt = authority.receipt
    tamperedReceipt.head.entries[0].mode ^= 0o100
    let tampered = AuthorizedWorkspaceJournaledGitPreimageCapture.testOnly(
      receipt: tamperedReceipt
    )
    let beforeTamper = await journal.headSnapshot()
    do {
      _ = try await journal.recordJournaledGitPreimageCapture(
        tampered,
        commandID: RunCommandID("capture-git-preimage-tampered")
      )
      XCTFail("decoded artifact substitution must remain inert")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .reducerRejected(
          .invalidGitPreimageCapture(
            "the live Git preimage capability does not match its receipt"
          ))
      )
    }
    let afterTamper = await journal.headSnapshot()
    XCTAssertEqual(afterTamper, beforeTamper)

    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let recoveredReceipt =
      await recovered
      .journaledGitPreimageCaptureReceipt()
    XCTAssertEqual(recoveredReceipt, authority.receipt)
    let worktree = try WorkspacePreimagePlaneProjector()
      .projectInitialWorktree(from: try XCTUnwrap(ratified.contract.sourceRevision))
    let coverage = try WorkspacePreimagePlaneProjector().assessCoverage(
      requiredPlanes: [.head, .index, .worktree, .untracked],
      artifacts: [
        authority.receipt.head,
        authority.receipt.index,
        worktree,
        authority.receipt.untracked,
      ]
    )
    XCTAssertTrue(coverage.isComplete)
  }

  func testGitPreimageCaptureProvesThreeExplicitEmptyPlanes() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try git(fixture.workspace, ["init", "-q"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(fixture.workspace, ["config", "user.email", "loopforge@example.invalid"])
    try git(fixture.workspace, ["commit", "--allow-empty", "-qm", "empty"])
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )

    let authority = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)

    XCTAssertTrue(authority.receipt.head.entries.isEmpty)
    XCTAssertTrue(authority.receipt.index.entries.isEmpty)
    XCTAssertTrue(authority.receipt.untracked.entries.isEmpty)
    XCTAssertTrue(authority.receipt.head.contentObjects.isEmpty)
    XCTAssertTrue(authority.receipt.index.contentObjects.isEmpty)
    XCTAssertTrue(authority.receipt.untracked.contentObjects.isEmpty)
    XCTAssertTrue(authority.validationIssues().isEmpty)
  }

  func testGitPreimageCaptureRejectsConflictedIndexAtomically() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try git(fixture.workspace, ["init", "-q", "-b", "main"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(fixture.workspace, ["config", "user.email", "loopforge@example.invalid"])
    let source = fixture.workspace.appendingPathComponent("conflict.txt")
    try Data("base\n".utf8).write(to: source)
    try git(fixture.workspace, ["add", "conflict.txt"])
    try git(fixture.workspace, ["commit", "-qm", "base"])
    try git(fixture.workspace, ["checkout", "-qb", "side"])
    try Data("side\n".utf8).write(to: source)
    try git(fixture.workspace, ["commit", "-qam", "side"])
    try git(fixture.workspace, ["checkout", "-q", "main"])
    try Data("main\n".utf8).write(to: source)
    try git(fixture.workspace, ["commit", "-qam", "main"])
    XCTAssertNotEqual(
      try git(fixture.workspace, ["merge", "side"], allowFailure: true),
      0
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )

    do {
      _ = try await WorkspaceJournaledGitPreimageCaptureIssuer(
        registry: fixture.registry
      ).capture(enrollment: enrollment)
      XCTFail("a conflicted index must not mint partial plane authority")
    } catch {
      XCTAssertEqual(
        error as? WorkspaceJournaledGitPreimageCaptureError,
        .conflictedIndex
      )
    }
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let absent = await journal.journaledGitPreimageCaptureReceipt()
    XCTAssertNil(absent)
  }

  func testCanonicalPreimageJournalsMetadataIgnorePolicyAndFourPlanes()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try git(fixture.workspace, ["init", "-q", "-b", "main"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(fixture.workspace, ["config", "user.email", "loopforge@example.invalid"])
    try Data("ignored.txt\n".utf8).write(
      to: fixture.workspace.appendingPathComponent(".gitignore")
    )
    try Data("head".utf8).write(
      to: fixture.workspace.appendingPathComponent("tracked.txt")
    )
    try git(fixture.workspace, ["add", ".gitignore", "tracked.txt"])
    try git(fixture.workspace, ["commit", "-qm", "baseline"])
    try Data("index".utf8).write(
      to: fixture.workspace.appendingPathComponent("tracked.txt")
    )
    try git(fixture.workspace, ["add", "tracked.txt"])
    try Data("ignored".utf8).write(
      to: fixture.workspace.appendingPathComponent("ignored.txt")
    )
    try Data("ordinary".utf8).write(
      to: fixture.workspace.appendingPathComponent("ordinary.txt")
    )
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let gitAuthority = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)
    _ = try await journal.recordJournaledGitPreimageCapture(
      gitAuthority,
      commandID: RunCommandID("capture-git-for-canonical")
    )

    let authority = try await WorkspaceJournaledCanonicalPreimageIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)

    XCTAssertTrue(authority.validationIssues().isEmpty)
    XCTAssertEqual(
      authority.receipt.ignoredPathClassifications,
      [
        WorkspaceIgnoredPathClassification(
          path: "ignored.txt", isIgnored: true
        ),
        WorkspaceIgnoredPathClassification(
          path: "ordinary.txt", isIgnored: false
        ),
      ]
    )
    XCTAssertEqual(
      authority.receipt.preimage.requiredPlanes,
      [.head, .index, .worktree, .untracked]
    )
    XCTAssertEqual(
      authority.receipt.preimage.capturedPlanes,
      authority.receipt.preimage.requiredPlanes
    )
    XCTAssertEqual(
      authority.receipt.preimage.repositoryMetadataDigest,
      authority.receipt.repositoryMetadata.repositoryMetadataDigest
    )
    XCTAssertEqual(authority.receipt.repositoryMetadata.objectFormat, "sha1")
    XCTAssertEqual(authority.receipt.repositoryMetadata.symbolicHead, "refs/heads/main")
    XCTAssertEqual(
      authority.receipt.repositoryMetadata.policyFiles.map(\.role),
      ["git-info-exclude", "worktree:.gitignore"]
    )
    let roundTripped = try JSONDecoder().decode(
      WorkspaceJournaledCanonicalPreimageReceipt.self,
      from: JSONEncoder().encode(authority.receipt)
    )
    XCTAssertEqual(roundTripped, authority.receipt)
    XCTAssertEqual(roundTripped.validationIssues(), [])
    let commandID = RunCommandID("capture-canonical-preimage")
    let first = try await journal.recordJournaledCanonicalPreimage(
      authority,
      commandID: commandID
    )
    let duplicate = try await journal.recordJournaledCanonicalPreimage(
      authority,
      commandID: commandID
    )
    XCTAssertFalse(first.duplicate)
    XCTAssertTrue(duplicate.duplicate)
    let accepted = await journal.journaledCanonicalPreimageReceipt(
      transaction: first
    )
    XCTAssertEqual(accepted, authority.receipt)
    var conflictingReceipt = authority.receipt
    conflictingReceipt.capturedAt = authority.receipt.capturedAt
      .addingTimeInterval(1)
    let conflicting =
      AuthorizedWorkspaceJournaledCanonicalPreimage
      .testOnly(receipt: conflictingReceipt)
    do {
      _ = try await journal.recordJournaledCanonicalPreimage(
        conflicting,
        commandID: commandID
      )
      XCTFail("one command identity cannot hide a different assembly")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .canonicalPreimageCommandConflict(commandID: commandID)
      )
    }
    var tamperedReceipt = authority.receipt
    tamperedReceipt.ignoredPathClassifications[0].isIgnored = false
    let tampered = AuthorizedWorkspaceJournaledCanonicalPreimage.testOnly(
      receipt: tamperedReceipt
    )
    let beforeTamper = await journal.headSnapshot()
    do {
      _ = try await journal.recordJournaledCanonicalPreimage(
        tampered,
        commandID: RunCommandID("tampered-canonical-preimage")
      )
      XCTFail("decoded policy substitution must remain inert")
    } catch let error as RunJournalError {
      XCTAssertEqual(
        error,
        .reducerRejected(
          .invalidCanonicalPreimage(
            "the live canonical-preimage capability does not match its receipt"
          ))
      )
    }
    let afterTamper = await journal.headSnapshot()
    XCTAssertEqual(afterTamper, beforeTamper)
    let recovered = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let recoveredReceipt =
      await recovered
      .journaledCanonicalPreimageReceipt()
    XCTAssertEqual(recoveredReceipt, authority.receipt)
  }

  func testCanonicalPreimageRetainsExplicitEmptyIgnoreClassification()
    async throws
  {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try git(fixture.workspace, ["init", "-q", "-b", "main"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(fixture.workspace, ["config", "user.email", "loopforge@example.invalid"])
    try git(fixture.workspace, ["commit", "--allow-empty", "-qm", "empty"])
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let gitAuthority = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)
    _ = try await journal.recordJournaledGitPreimageCapture(
      gitAuthority,
      commandID: RunCommandID("capture-empty-git")
    )

    let authority = try await WorkspaceJournaledCanonicalPreimageIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)

    XCTAssertTrue(authority.receipt.ignoredPathClassifications.isEmpty)
    XCTAssertTrue(authority.receipt.preimage.entries.isEmpty)
    XCTAssertTrue(authority.validationIssues().isEmpty)
  }

  func testCanonicalPreimageRejectsExternalIgnoreAuthority() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try git(fixture.workspace, ["init", "-q", "-b", "main"])
    try git(fixture.workspace, ["config", "user.name", "LoopForge Test"])
    try git(fixture.workspace, ["config", "user.email", "loopforge@example.invalid"])
    try git(fixture.workspace, ["commit", "--allow-empty", "-qm", "empty"])
    try git(
      fixture.workspace,
      [
        "config", "core.excludesFile", "/tmp/loopforge-external-ignore",
      ])
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let journal = try RunJournal(
      rootDirectory: enrollment.registration.journalRoot,
      runID: enrollment.runID
    )
    let gitAuthority = try await WorkspaceJournaledGitPreimageCaptureIssuer(
      registry: fixture.registry
    ).capture(enrollment: enrollment)
    _ = try await journal.recordJournaledGitPreimageCapture(
      gitAuthority,
      commandID: RunCommandID("capture-external-ignore-git")
    )

    do {
      _ = try await WorkspaceJournaledCanonicalPreimageIssuer(
        registry: fixture.registry
      ).capture(enrollment: enrollment)
      XCTFail("external ignore authority must fail closed")
    } catch {
      XCTAssertEqual(
        error as? WorkspaceJournaledCanonicalPreimageError,
        .unsupportedRepositoryPolicy("external-excludes-file")
      )
    }
    let absent = await journal.journaledCanonicalPreimageReceipt()
    XCTAssertNil(absent)
  }

  @discardableResult
  private func git(
    _ root: URL,
    _ arguments: [String],
    allowFailure: Bool = false
  ) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    _ = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if !allowFailure && process.terminationStatus != 0 {
      throw NSError(
        domain: "KernelRunEnrollmentCoordinatorTests.git",
        code: Int(process.terminationStatus)
      )
    }
    return process.terminationStatus
  }

  private func prepareBaselineCapture(
    _ fixture: Fixture
  ) async throws -> (
    enrollment: KernelRunEnrollmentReceipt,
    derivation: WorkspaceMutationOperationDerivationReceipt,
    authority: AuthorizedWorkspaceRatifiedBaselineContent
  ) {
    let source = fixture.workspace.appendingPathComponent("Sources/a.txt")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let old = Data("ratified-baseline".utf8)
    try old.write(to: source)
    let ratified = try ratifiedContract(
      candidate: try candidate(workspace: fixture.workspace)
    )
    let enrollment = try await fixture.coordinator.enroll(
      fixture.request(ratifiedContract: ratified)
    )
    let base = try XCTUnwrap(ratified.contract.sourceRevision)
    try Data("candidate-postimage".utf8).write(to: source)
    let candidate = try WorkspaceSourceRevisionCollector().capture(
      workspaceID: base.workspaceID,
      root: fixture.workspace,
      excludedDirectoryNames: Set(base.excludedDirectoryNames),
      limits: base.limits
    )
    let derivation = try WorkspaceMutationOperationDeriver().derive(
      base: base,
      candidate: candidate,
      requirementIDs: [RequirementID("enrollment-outcome")],
      authorizedPaths: ["Sources/a.txt"]
    )
    try old.write(to: source)
    let authority = try await WorkspaceRatifiedBaselineContentCaptureIssuer(
      registry: fixture.registry
    ).capture(
      enrollment: enrollment,
      derivation: derivation
    )
    return (enrollment, derivation, authority)
  }

  private struct Fixture {
    let container: URL
    let workspace: URL
    let registry: WorkspaceMutationRecoveryRegistry
    let coordinator: KernelRunEnrollmentCoordinator
    let executionCoordinator: KernelExecutionPreparationCoordinator
    let productionExecutionCoordinator: KernelProductionExecutionCoordinator

    init() throws {
      container = FileManager.default.temporaryDirectory.appendingPathComponent(
        "LoopForgeKernelEnrollment-\(UUID().uuidString)",
        isDirectory: true
      )
      workspace = container.appendingPathComponent("workspace", isDirectory: true)
      try FileManager.default.createDirectory(
        at: workspace,
        withIntermediateDirectories: true
      )
      registry = try WorkspaceMutationRecoveryRegistry(
        rootDirectory: container.appendingPathComponent("registry", isDirectory: true)
      )
      coordinator = KernelRunEnrollmentCoordinator(registry: registry)
      executionCoordinator = KernelExecutionPreparationCoordinator(
        registry: registry
      )
      productionExecutionCoordinator = KernelProductionExecutionCoordinator(
        registry: registry,
        wallClock: { Date(timeIntervalSince1970: 4_000_000_013) },
        monotonicClock: { 1_000_001_000 }
      )
    }

    func request(
      ratifiedContract: RatifiedTaskContract,
      hostBudget: HostResourceBudget = HostResourceBudget(
        nominal: .zero
      )
    ) -> KernelRunEnrollmentRequest {
      KernelRunEnrollmentRequest(
        runID: KernelRunID("enrollment-run"),
        ratifiedContract: ratifiedContract,
        actorIdentity: ActorIdentity(
          id: ActorID("kernel-enrollment"),
          role: "kernel-enrollment",
          lineageDigest: ContentDigest("kernel-enrollment-lineage")
        ),
        workspaceID: WorkspaceID("enrollment-workspace"),
        workspaceRoot: workspace,
        hostBudget: hostBudget,
        maximumDispatchBatch: 4,
        createCommandID: RunCommandID("enrollment-create"),
        enrolledAt: Date(timeIntervalSince1970: 4)
      )
    }

    func remove() {
      try? makeWritable(container)
      try? FileManager.default.removeItem(at: container)
    }

    private func makeWritable(_ url: URL) throws {
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      if let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
      ) {
        var paths: [URL] = []
        for case let child as URL in enumerator { paths.append(child) }
        for child in paths.reversed() {
          try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: child.path
          )
        }
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: url.path
      )
    }

    func preparationRequest(
      enrollment: KernelRunEnrollmentReceipt
    ) async throws -> KernelExecutionPreparationRequest {
      let journal = try RunJournal(
        rootDirectory: enrollment.registration.journalRoot,
        runID: enrollment.runID
      )
      guard let contract = await journal.currentContract(),
        let authority = contract.initialCausalStrategyAuthority,
        let plan = contract.initialExecutionPlan,
        let node = plan.nodes.first,
        let budget = contract.executionBudgets
      else {
        throw KernelExecutionPreparationError.invalidPreparation(
          "fixture requires retained native strategy and plan authority"
        )
      }
      let strategy = authority.descriptor
      return KernelExecutionPreparationRequest(
        enrollment: enrollment,
        plan: plan,
        designBaseline: nil,
        convergenceEpochID: "enrollment-execution-epoch",
        convergenceBudget: budget.convergence,
        nodeID: node.id,
        admission: AttemptAdmissionRequest(
          attemptID: AttemptID("enrollment-attempt"),
          strategy: strategy,
          predictedObservationIDs: strategy.expectedObservationIDs,
          falsificationPredicateIDs:
            strategy.falsificationPredicateIDs,
          rollbackPoint: strategy.baselineRevision,
          mutationCost: node.mutationScope.writablePaths.isEmpty
            ? 0
            : 1,
          verificationCost: 1,
          externalEffects: 0
        ),
        actorIdentity: enrollment.registration.actorIdentity,
        issuedAt: Date(timeIntervalSince1970: 5),
        planCommandID: RunCommandID("prepare-plan"),
        baselineCommandID: nil,
        convergenceCommandID: RunCommandID("prepare-convergence"),
        authorizationCommandID: RunCommandID("prepare-authorize"),
        admissionCommandID: RunCommandID("prepare-admission")
      )
    }
  }

  private func candidate(
    workspace: URL,
    mutationCapable: Bool = true,
    workerExecutionProfile: KernelAgentExecutionProfile? = nil,
    evidenceProbe: RequirementVerificationExecutableProbe? = nil,
    additionalEvidenceProbes: [RequirementVerificationExecutableProbe] = [],
    externalDependencies: [ExternalDependencyContract] = [],
    writablePaths: [String]? = nil
  ) throws -> TaskContractCompilationCandidate {
    let mutationWritablePaths: Set<String> =
      writablePaths.map(Set.init)
      ?? (mutationCapable ? ["."] : [])
    let objective = "Apply only the exact confirmed contract authority."
    let user = ActorIdentity(
      id: ActorID("enrollment-user"),
      role: "user",
      lineageDigest: ContentDigest("enrollment-user-lineage")
    )
    let source = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-source"),
      exactUTF8: Data(objective.utf8),
      authority: .user,
      author: user,
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let resolvedWorkspace = workspace.standardizedFileURL.resolvingSymlinksInPath()
    let workspaceSource = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-workspace-source"),
      exactUTF8: Data(resolvedWorkspace.path.utf8),
      authority: .user,
      author: user,
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let executionProfile = KernelExecutionProfile(
      schemaVersion: 1,
      worker: workerExecutionProfile
        ?? KernelAgentExecutionProfile(
          provider: .codex,
          providerReference: "official-codex-session",
          executableContentDigest: ContentDigest(String(repeating: "a", count: 64)),
          modelID: "gpt-worker",
          reasoningEffort: "high",
          sandbox: mutationCapable ? .workspaceOnly : .readOnly,
          networkPolicy: .disabled,
          pluginPolicy: .disabled,
          environmentPolicy: .minimalKernelAllowlist
        ),
      independentReviewer: KernelAgentExecutionProfile(
        provider: .codex,
        providerReference: "official-codex-session",
        executableContentDigest: ContentDigest(String(repeating: "a", count: 64)),
        modelID: "gpt-reviewer",
        reasoningEffort: "high",
        sandbox: .readOnly,
        networkPolicy: .disabled,
        pluginPolicy: .disabled,
        environmentPolicy: .minimalKernelAllowlist
      ),
      requiresDistinctActorLineage: true
    )
    let executionData = TaskContractCompiler.executionProfileData(executionProfile)!
    let executionSource = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-execution-source"),
      exactUTF8: executionData,
      authority: .user,
      author: user,
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let span = TaskContractSourceSpan(
      sourceID: source.id,
      sourceDigest: source.digest,
      lowerUTF8Offset: 0,
      upperUTF8Offset: source.exactUTF8.count
    )
    let workspaceSpan = TaskContractSourceSpan(
      sourceID: workspaceSource.id,
      sourceDigest: workspaceSource.digest,
      lowerUTF8Offset: 0,
      upperUTF8Offset: workspaceSource.exactUTF8.count
    )
    let executionSpan = TaskContractSourceSpan(
      sourceID: executionSource.id,
      sourceDigest: executionSource.digest,
      lowerUTF8Offset: 0,
      upperUTF8Offset: executionSource.exactUTF8.count
    )
    let requirementID = RequirementID("enrollment-outcome")
    let recipeID = EvidenceRecipeID("enrollment-recipe")
    let evidenceRecipe = RequirementEvidenceRecipe(
      id: recipeID,
      requirementID: requirementID,
      verifierKind: .deterministic,
      expectedObservation: "The exact confirmed contract is reducer-owned.",
      requiresIndependentLineage: true,
      executableProbe: evidenceProbe
        ?? RequirementVerificationExecutableProbe(
          schemaVersion: 2,
          transport: .localDirectProcess,
          executableContentDigest: ContentDigest(
            String(repeating: "c", count: 64)
          ),
          fixedArguments: [
            "--input", "@loopforge-input:candidate-postimage", "--jsonl",
          ],
          inputBindings: [
            RequirementVerificationInputBinding(
              id: "candidate-postimage",
              kind: .candidatePostimage,
              artifactID: "candidate-postimage",
              argumentToken: "@loopforge-input:candidate-postimage"
            )
          ],
          environmentPolicy: .minimalKernelAllowlist,
          environmentIdentityDigest: ContentDigest(
            String(repeating: "d", count: 64)
          ),
          captureIdentityDigest: ContentDigest(
            String(repeating: "e", count: 64)
          ),
          parser: RequirementVerificationParserContract(
            id: "synthetic-jsonl-verifier",
            schemaVersion: 1,
            contentDigest: RequirementVerificationParserFormat
              .canonicalJSONResultV1.implementationIdentityDigest,
            format: .canonicalJSONResultV1
          ),
          resultMappings: [
            RequirementVerificationResultMapping(
              exitCode: 0,
              parserResultCode: "accepted",
              outcome: .accepted
            ),
            RequirementVerificationResultMapping(
              exitCode: 1,
              parserResultCode: "rejected",
              outcome: .rejected
            ),
          ],
          unmatchedOutcome: .rejected,
          networkPolicy: .disabled,
          resourceLimits: RequirementVerificationResourceLimits(
            maximumWallClockSeconds: 60,
            maximumCapturedOutputBytes: 1_048_576,
            maximumResidentBytes: 268_435_456,
            maximumChildProcesses: 0
          )
        )
    )
    let evidenceRecipes =
      [evidenceRecipe]
      + additionalEvidenceProbes.enumerated().map { offset, probe in
        RequirementEvidenceRecipe(
          id: EvidenceRecipeID("enrollment-recipe-\(offset + 2)"),
          requirementID: requirementID,
          verifierKind: .deterministic,
          expectedObservation:
            "The exact confirmed contract is reducer-owned (\(offset + 2)).",
          requiresIndependentLineage: true,
          executableProbe: probe
        )
      }
    let sourceRevision = try WorkspaceSourceRevisionCollector().capture(
      workspaceID: WorkspaceID("enrollment-workspace"),
      root: resolvedWorkspace,
      excludedDirectoryNames: [".build", ".git"],
      limits: WorkspaceSourceRevisionLimits(
        maximumFiles: 16,
        maximumTotalBytes: 1_048_576,
        maximumFileBytes: 1_048_576
      )
    )
    let executionBudgets = KernelExecutionBudgetPolicy(
      mutation: KernelMutationBudget(
        maximumChangedFiles: mutationCapable ? 1 : 0,
        maximumChangedBytes: mutationCapable ? 1_024 : 0
      ),
      convergence: ConvergenceBudget(
        maximumAttempts: 1,
        maximumEquivalentFailures: 1,
        maximumStrategies: 1,
        maximumPlanExpansions: 1,
        maximumMutationCost: mutationCapable ? 1_024 : 0,
        maximumVerificationCost: 4,
        maximumDamageEvents: 1,
        maximumExternalEffects: 0
      )
    )
    let provisionalNode = KernelNodeContract(
      id: KernelNodeID("enrollment-node"),
      requirementIDs: [requirementID],
      objective: "Prepare exact ratified work.",
      dependencies: [],
      mutationScope: KernelMutationScope(
        writablePaths: mutationWritablePaths,
        maximumChangedFiles: mutationCapable ? 1 : 0,
        maximumChangedBytes: mutationCapable ? 1_024 : 0
      ),
      capabilityIDs: [],
      strategyFingerprint: StrategyFingerprint("pending")
    )
    let provisionalPlan = KernelPlanProposal(
      contractDigest: TaskContractCompiler.digest(Data(objective.utf8)),
      nodes: [provisionalNode]
    )
    let strategy = CausalStrategyDescriptor(
      requirementIDs: [requirementID],
      hypothesisClass: "ratified-outcome",
      actionClass: "prepare-exact-work",
      workspaceTopology: "confirmed-workspace",
      capabilityRoute: [],
      evidenceSources: Set(evidenceRecipes.map(\.id.rawValue)),
      measurementBoundary: "enrollment-outcome",
      verificationOracles: Set(evidenceRecipes.map(\.verifierKind.rawValue)),
      mutationSurfaceDigest: try XCTUnwrap(
        TaskContractCompiler.planMutationSurfaceDigest(provisionalPlan)
      ),
      baselineRevision: sourceRevision.sourceRevision,
      expectedObservationIDs: Set(
        evidenceRecipes.enumerated().map {
          $0.offset == 0 ? "outcome-observed" : "outcome-observed-\($0.offset + 1)"
        }),
      falsificationPredicateIDs: Set(
        evidenceRecipes.enumerated().map {
          $0.offset == 0 ? "outcome-missing" : "outcome-missing-\($0.offset + 1)"
        }),
      inheritedLessonDigests: []
    )
    let strategyAuthority = KernelCausalStrategyAuthority(
      descriptor: strategy,
      expectedObservations: evidenceRecipes.enumerated().map { offset, recipe in
        KernelExpectedObservationContract(
          id: offset == 0 ? "outcome-observed" : "outcome-observed-\(offset + 1)",
          requirementID: requirementID,
          evidenceRecipeID: recipe.id,
          expectedObservationDigest: TaskContractCompiler.digest(
            Data(recipe.expectedObservation.utf8)
          )
        )
      },
      falsificationPredicates: evidenceRecipes.enumerated().map { offset, recipe in
        KernelFalsificationPredicateContract(
          id: offset == 0 ? "outcome-missing" : "outcome-missing-\(offset + 1)",
          requirementID: requirementID,
          evidenceRecipeID: recipe.id,
          kind: .requiredEvidenceMissing,
          boundSourceRevision: sourceRevision.sourceRevision
        )
      }
    )
    var planNode = provisionalNode
    planNode.strategyFingerprint = strategy.fingerprint
    let executionPlan = KernelPlanProposal(
      contractDigest: provisionalPlan.contractDigest,
      nodes: [planNode]
    )
    let budgetSource = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-budget-source"),
      exactUTF8: try XCTUnwrap(
        TaskContractCompiler.executionBudgetData(executionBudgets)
      ),
      authority: .user,
      author: user,
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let revisionSource = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-revision-source"),
      exactUTF8: try XCTUnwrap(
        TaskContractCompiler.sourceRevisionData(sourceRevision)
      ),
      authority: .workspaceObservation,
      author: ActorIdentity(
        id: ActorID("enrollment-revision-collector"),
        role: "workspace-source-revision-collector",
        lineageDigest: ContentDigest("enrollment-revision-lineage")
      ),
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let strategySource = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-strategy-source"),
      exactUTF8: try XCTUnwrap(
        TaskContractCompiler.causalStrategyAuthorityData(strategyAuthority)
      ),
      authority: .user,
      author: user,
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let planSource = TaskContractSourceArtifact(
      id: TaskContractSourceID("enrollment-plan-source"),
      exactUTF8: try XCTUnwrap(
        TaskContractCompiler.executionPlanData(executionPlan)
      ),
      authority: .user,
      author: user,
      recordedAt: Date(timeIntervalSince1970: 1)
    )
    let fullSpan: (TaskContractSourceArtifact) -> TaskContractSourceSpan = {
      TaskContractSourceSpan(
        sourceID: $0.id,
        sourceDigest: $0.digest,
        lowerUTF8Offset: 0,
        upperUTF8Offset: $0.exactUTF8.count
      )
    }
    let contract = TaskContract(
      id: TaskContractID("enrollment-contract"),
      schemaVersion: 1,
      verbatimObjective: objective,
      objectiveDigest: TaskContractCompiler.digest(Data(objective.utf8)),
      requirements: [
        RequirementContract(
          id: requirementID,
          statement: objective,
          mandatory: true,
          evidenceRecipeIDs: Set(evidenceRecipes.map(\.id))
        )
      ],
      constraints: [
        ConstraintContract(
          id: "enrollment-authority",
          kind: .requireAuthority,
          statement: "Mutation remains within the explicitly selected scope."
        )
      ],
      nonGoals: [],
      protectedBaselines: [],
      workspaceBinding: TaskContractWorkspaceBinding(
        workspaceID: WorkspaceID("enrollment-workspace"),
        canonicalRootDigest:
          WorkspaceRepositoryIndexer
          .canonicalRootDigest(resolvedWorkspace)
      ),
      externalDependencies:
        externalDependencies.isEmpty ? nil : externalDependencies,
      requirementEvidenceRecipes: evidenceRecipes,
      executionBudgets: executionBudgets,
      sourceRevision: sourceRevision,
      initialCausalStrategyAuthority: strategyAuthority,
      initialExecutionPlan: executionPlan,
      executionProfile: executionProfile,
      authorityCeiling: KernelAuthorityCeiling(
        readableScopes: ["."],
        writableScopes: mutationWritablePaths,
        capabilityIDs: [],
        permitsExternalPublication: false
      ),
      acceptancePolicy: TaskAcceptancePolicy(
        duration: nil,
        requiresIndependentReview: true,
        requiresQuiescence: true
      ),
      createdAt: Date(timeIntervalSince1970: 2)
    )
    return TaskContractCompilationCandidate(
      schemaVersion: 1,
      revision: 1,
      initialObjectiveSourceID: source.id,
      sources: [
        source,
        workspaceSource,
        executionSource,
        budgetSource,
        revisionSource,
        strategySource,
        planSource,
      ],
      contract: contract,
      requirementBindings: [
        RequirementSourceBinding(
          requirementID: requirementID,
          sourceSpans: [span],
          epistemicState: .explicit
        )
      ],
      constraintBindings: [
        ConstraintSourceBinding(
          constraintID: "enrollment-authority",
          sourceSpans: [workspaceSpan],
          epistemicState: .explicit
        )
      ],
      evidenceRecipes: evidenceRecipes,
      ambiguities: [],
      workspaceSourceBinding: WorkspaceSourceBinding(
        sourceSpans: [workspaceSpan],
        epistemicState: .explicit
      ),
      executionProfileSourceBinding: ExecutionProfileSourceBinding(
        sourceSpans: [executionSpan],
        epistemicState: .explicit
      ),
      executionBudgetSourceBinding: ExecutionBudgetSourceBinding(
        sourceSpans: [fullSpan(budgetSource)],
        epistemicState: .explicit
      ),
      sourceRevisionSourceBinding: SourceRevisionSourceBinding(
        sourceSpans: [fullSpan(revisionSource)],
        epistemicState: .workspaceObserved
      ),
      causalStrategyAuthoritySourceBinding:
        CausalStrategyAuthoritySourceBinding(
          sourceSpans: [fullSpan(strategySource)],
          epistemicState: .explicit
        ),
      executionPlanSourceBinding: ExecutionPlanSourceBinding(
        sourceSpans: [fullSpan(planSource)],
        epistemicState: .explicit
      ),
      externalDependencyBindings: externalDependencies.isEmpty
        ? nil
        : externalDependencies.map {
          ExternalDependencySourceBinding(
            dependencyID: $0.id,
            sourceSpans: [span],
            epistemicState: .explicit
          )
        },
      compilerActor: ActorIdentity(
        id: ActorID("enrollment-compiler"),
        role: "contract-compiler",
        lineageDigest: ContentDigest("enrollment-compiler-lineage")
      ),
      compiledAt: Date(timeIntervalSince1970: 2)
    )
  }

  private func externalDependencyObserver() -> ActorIdentity {
    ActorIdentity(
      id: ActorID("production-external-dependency-observer"),
      role: "external-dependency-observer",
      lineageDigest: ContentDigest(String(repeating: "2", count: 64))
    )
  }

  private func externalDependencyContract(
    observer: ActorIdentity,
    emitsCanonicalResult: Bool
  ) throws -> ExternalDependencyContract {
    var probe = externalDependencyObservationProbeFixture()
    probe.executableContentDigest = try XCTUnwrap(
      ProcessGroupRuntimeAdapter.executableContentDigest(
        atPath: kernelProcessFixturePath
      )
    )
    probe.fixedArguments = [
      emitsCanonicalResult
        ? "--observe-external-dependency"
        : "--consume-external-dependency-request",
      "--request",
      ExternalDependencyObservationExecutableProbe.requestArgumentToken,
    ]
    return ExternalDependencyContract(
      id: ExternalDependencyID("production-external-dependency"),
      kind: .externalCondition,
      requirementIDs: [RequirementID("enrollment-outcome")],
      evidenceRecipeID: ExternalDependencyEvidenceRecipeID(
        "production-external-dependency-recipe"
      ),
      authorizedObserverLineageDigests: [observer.lineageDigest],
      executableProbe: probe
    )
  }

  private func productionExternalDependencyRequest(
    observer: ActorIdentity,
    workspace: URL,
    prefix: String
  ) -> KernelProductionExternalDependencyObservationRequest {
    KernelProductionExternalDependencyObservationRequest(
      activation: ExternalDependencyObservationActivationRequest(
        receiptID: ReceiptID("\(prefix)-activation"),
        commandID: RunCommandID("\(prefix)-activate"),
        dependencyID: ExternalDependencyID(
          "production-external-dependency"
        ),
        observer: observer,
        executablePath: kernelProcessFixturePath,
        workspaceRoot: workspace,
        activatedAt: Date(timeIntervalSince1970: 7)
      ),
      readiness: ExternalDependencyObservationLaunchReadinessRequest(
        vetoReceiptID: ReceiptID("\(prefix)-veto"),
        vetoCommandID: RunCommandID("\(prefix)-veto"),
        observedAt: Date(timeIntervalSince1970: 8)
      ),
      runtime: ExternalDependencyObservationRuntimeRequest(
        leaseID: ResourceLeaseID("\(prefix)-lease"),
        resourceID: OwnedResourceID("\(prefix)-resource"),
        standardOutputFileName: "\(prefix).stdout",
        standardErrorFileName: "\(prefix).stderr",
        admissionReceiptID: ReceiptID("\(prefix)-admission"),
        admissionCommandID: RunCommandID("\(prefix)-admit"),
        bindingReceiptID: ReceiptID("\(prefix)-binding"),
        launchReceiptID: ReceiptID("\(prefix)-launch"),
        bindingCommandID: RunCommandID("\(prefix)-bind"),
        launchFailureReleaseReceiptID:
          ReceiptID("\(prefix)-launch-failure-release"),
        launchFailureReleaseCommandID:
          RunCommandID("\(prefix)-launch-failure-release")
      ),
      completion: ExternalDependencyObservationCompletionRequest(
        releaseReceiptID: ReceiptID("\(prefix)-release"),
        releaseCommandID: RunCommandID("\(prefix)-release"),
        observationCommandID: RunCommandID("\(prefix)-observation")
      )
    )
  }

  private var kernelProcessFixturePath: String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/debug/KernelProcessFixture")
      .standardizedFileURL.path
  }

  private func ratifiedContract(
    candidate: TaskContractCompilationCandidate
  ) throws -> RatifiedTaskContract {
    let compiled: CompiledTaskContractCandidate
    switch TaskContractCompiler.compile(candidate) {
    case .success(let value): compiled = value
    case .failure(let failure):
      XCTFail("unexpected compile failure: \(failure.issues)")
      throw failure
    }
    let confirmation = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
      candidateDigest: compiled.candidateDigest,
      confirmedAt: Date(timeIntervalSince1970: 3),
      userActor: candidate.sources[0].author
    )
    switch TaskContractCompiler.ratify(compiled, confirmation: confirmation) {
    case .success(let value): return value
    case .failure(let error):
      XCTFail("unexpected ratification failure: \(error)")
      throw error
    }
  }

  private func nativeDesignBaselineSelection(
    contractID: TaskContractID,
    artifact: ContentDigest
  ) -> NativeDesignBaselineSelection {
    let digest: (String) -> ContentDigest = {
      TaskContractCompiler.digest(Data($0.utf8))
    }
    let cell = VisualCellID("native-design-primary")
    let sourceTree = digest("native-design-source")
    let captureProtocol = digest("native-design-capture-protocol")
    return NativeDesignBaselineSelection(
      id: DesignBaselineID("native-confirmed-design-baseline"),
      contractID: contractID,
      protectedBaselineID: BaselineID("protected-native-design"),
      requirementIDs: [RequirementID("enrollment-outcome")],
      sourceTree: sourceTree,
      builtArtifact: artifact,
      captureProtocol: captureProtocol,
      designTokenSnapshot: digest("native-design-tokens"),
      semanticSurfaceManifest: digest("native-design-surfaces"),
      captures: [
        NativeCaptureReceipt(
          id: NativeCaptureID("native-design-capture-primary"),
          cellID: cell,
          sourceTree: sourceTree,
          builtArtifact: artifact,
          captureProtocol: captureProtocol,
          traits: VisualTraitSignature(
            deviceClass: "Mac",
            viewportWidthPixels: 1440,
            viewportHeightPixels: 900,
            scale: 2,
            operatingSystem: "macOS",
            orientation: "landscape",
            locale: "en_US",
            calendar: "gregorian",
            layoutDirection: "leftToRight",
            appearance: "light",
            contrast: "normal",
            reducedMotion: false,
            boldText: false,
            contentSizeCategory: "large",
            fixtureDigest: digest("native-design-fixture")
          ),
          imageDigest: digest("native-design-image"),
          accessibilityTreeDigest: digest("native-design-accessibility"),
          navigationRecipeDigest: digest("native-design-navigation"),
          componentBoundaryDigest: digest("native-design-components"),
          designTokenTraceDigest: digest("native-design-token-trace"),
          imageWidthPixels: 1440,
          imageHeightPixels: 900,
          fullViewport: true,
          cleanInstall: true,
          harnessIdentity: "native-design-harness-v1",
          processExitCode: 0,
          capturedAt: Date(timeIntervalSince1970: 4.5)
        )
      ],
      protectedInvariants: [
        DesignInvariant(
          id: "native-design-typography",
          dimension: .typographyHierarchy,
          cellIDs: [cell]
        )
      ],
      knownDebt: []
    )
  }
}
