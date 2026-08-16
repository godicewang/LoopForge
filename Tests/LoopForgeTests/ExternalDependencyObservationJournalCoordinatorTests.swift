import Foundation
import XCTest

@testable import LoopForge

final class ExternalDependencyObservationJournalCoordinatorTests:
  XCTestCase
{
  func testJournaledRuntimeLaunchesExactActivationThroughNativeSandbox()
    async throws
  {
    let root = try privateTemporaryDirectory()
    let workspace = try privateTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: workspace)
    }
    let fixture = try await activatedFixture(
      root: root,
      workspace: workspace
    )
    let enforcement = AuthorizedKernelResidentMemoryEnforcement.testOnly(
      externalDependencyActivation: fixture.invocation.receipt
    )
    let decision = try await ExternalDependencyObservationLaunchReadinessCoordinator(
      journal: fixture.journal
    ).evaluate(
      invocation: fixture.invocation,
      request: ExternalDependencyObservationLaunchReadinessRequest(
        vetoReceiptID: ReceiptID("native-observer-veto"),
        vetoCommandID: RunCommandID("native-observer-veto-command"),
        observedAt: Date(timeIntervalSince1970: 21)
      ),
      residentMemoryEnforcement: enforcement
    )
    guard case .ready(let readiness) = decision else {
      return XCTFail("expected test-only external observer readiness")
    }
    let supervisor = RuntimeSupervisor(
      runID: fixture.runID,
      budget: HostResourceBudget(
        nominal: ResourceVector(
          cpuWeight: 4,
          memoryBytes: 1_073_741_824,
          diskIOWeight: 4,
          gpuWeight: 0,
          networkWeight: 4,
          guiSessionCount: 0,
          processCount: 4
        )
      )
    )
    let runtime = JournaledProcessRuntime(
      supervisor: supervisor,
      journal: fixture.journal,
      actorIdentity: fixture.observer,
      residentMemoryEnforcement: enforcement
    )
    let start =
      try await runtime
      .admitAndLaunchExternalDependencyObserver(
        readiness: readiness,
        request: ExternalDependencyObservationRuntimeRequest(
          leaseID: ResourceLeaseID("native-observer-lease"),
          resourceID: OwnedResourceID("native-observer-resource"),
          standardOutputFileName: "native-observer.stdout",
          standardErrorFileName: "native-observer.stderr",
          admissionReceiptID: ReceiptID("native-observer-admission"),
          admissionCommandID: RunCommandID("native-observer-admit"),
          bindingReceiptID: ReceiptID("native-observer-binding"),
          launchReceiptID: ReceiptID("native-observer-launch"),
          bindingCommandID: RunCommandID("native-observer-bind"),
          launchFailureReleaseReceiptID:
            ReceiptID("native-observer-launch-failure-release"),
          launchFailureReleaseCommandID:
            RunCommandID("native-observer-launch-failure-release-command")
        )
      )
    XCTAssertEqual(
      start.observerLaunch.activationReceiptID,
      fixture.invocation.receipt.id
    )
    XCTAssertEqual(
      start.observerLaunch.requestArtifact,
      fixture.invocation.receipt.requestArtifact
    )
    XCTAssertEqual(
      start.observerLaunch.nativeSandbox.candidateWorkingDirectory,
      nil
    )
    XCTAssertEqual(start.launch.journalTransaction.eventIDs.count, 2)
    let journaledLaunch = await fixture.journal
      .externalDependencyObservationRuntimeLaunchReceipt(
        transaction: start.launch.journalTransaction
      )
    XCTAssertEqual(
      journaledLaunch,
      start.observerLaunch
    )
    let projectedBoundLease = await fixture.journal.runtimeLease(
      resourceID: start.observerLaunch.resourceID
    )
    let boundLease = try XCTUnwrap(projectedBoundLease)
    let release = try await runtime.joinAndRelease(
      lease: boundLease,
      releaseReceiptID: ReceiptID("native-observer-release"),
      commandID: RunCommandID("native-observer-release-command"),
      timeoutNanoseconds: 2_000_000_000
    )
    XCTAssertEqual(release.exit.exitCode, 0)
    XCTAssertNil(release.exit.terminationSignal)
    let runDirectory = await fixture.journal.runDirectory
    XCTAssertEqual(
      try String(
        contentsOf: runDirectory.appendingPathComponent(
          "native-observer.stdout"
        ),
        encoding: .utf8
      ),
      "external-dependency-request-read\n"
    )
    XCTAssertTrue(
      try Data(
        contentsOf: runDirectory.appendingPathComponent(
          "native-observer.stderr"
        )
      ).isEmpty
    )
    do {
      _ = try await runtime.completeExternalDependencyObservation(
        launchReceiptID: start.observerLaunch.id,
        request: ExternalDependencyObservationCompletionRequest(
          releaseReceiptID: release.release.id,
          releaseCommandID:
            RunCommandID("native-observer-release-command"),
          observationCommandID:
            RunCommandID("invalid-native-observer-observation-command")
        )
      )
      XCTFail("expected noncanonical retained output rejection")
    } catch let error as JournaledProcessRuntimeError {
      XCTAssertEqual(
        error,
        .externalDependencyObservationResultInvalid
      )
    }
    let state = await fixture.journal.state
    XCTAssertTrue((state.externalDependencyReceipts ?? [:]).isEmpty)
    let runtimeProjection = await runtime.projection()
    let supervisorProjection = await supervisor.projection()
    XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    XCTAssertTrue(runtimeProjection.inDoubtResourceIDs.isEmpty)
    XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
  }

  func testJournaledRuntimeCompletesNativeObservationAndReplaysExactly()
    async throws
  {
    let root = try privateTemporaryDirectory()
    let workspace = try privateTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: workspace)
    }
    let fixture = try await activatedFixture(
      root: root,
      workspace: workspace,
      emitsCanonicalResult: true
    )
    let enforcement = AuthorizedKernelResidentMemoryEnforcement.testOnly(
      externalDependencyActivation: fixture.invocation.receipt
    )
    let decision = try await ExternalDependencyObservationLaunchReadinessCoordinator(
      journal: fixture.journal
    ).evaluate(
      invocation: fixture.invocation,
      request: ExternalDependencyObservationLaunchReadinessRequest(
        vetoReceiptID: ReceiptID("native-completion-veto"),
        vetoCommandID: RunCommandID("native-completion-veto-command"),
        observedAt: Date(timeIntervalSince1970: 22)
      ),
      residentMemoryEnforcement: enforcement
    )
    guard case .ready(let readiness) = decision else {
      return XCTFail("expected test-only external observer readiness")
    }
    let supervisor = RuntimeSupervisor(
      runID: fixture.runID,
      budget: HostResourceBudget(
        nominal: ResourceVector(
          cpuWeight: 4,
          memoryBytes: 1_073_741_824,
          diskIOWeight: 4,
          gpuWeight: 0,
          networkWeight: 4,
          guiSessionCount: 0,
          processCount: 4
        )
      )
    )
    let runtime = JournaledProcessRuntime(
      supervisor: supervisor,
      journal: fixture.journal,
      actorIdentity: fixture.observer,
      residentMemoryEnforcement: enforcement
    )
    let start = try await runtime.admitAndLaunchExternalDependencyObserver(
      readiness: readiness,
      request: ExternalDependencyObservationRuntimeRequest(
        leaseID: ResourceLeaseID("native-completion-lease"),
        resourceID: OwnedResourceID("native-completion-resource"),
        standardOutputFileName: "native-completion.stdout",
        standardErrorFileName: "native-completion.stderr",
        admissionReceiptID: ReceiptID("native-completion-admission"),
        admissionCommandID: RunCommandID("native-completion-admit"),
        bindingReceiptID: ReceiptID("native-completion-binding"),
        launchReceiptID: ReceiptID("native-completion-launch"),
        bindingCommandID: RunCommandID("native-completion-bind"),
        launchFailureReleaseReceiptID:
          ReceiptID("native-completion-launch-failure-release"),
        launchFailureReleaseCommandID:
          RunCommandID("native-completion-launch-failure-release-command")
      )
    )
    let completionRequest = ExternalDependencyObservationCompletionRequest(
      releaseReceiptID: ReceiptID("native-completion-release"),
      releaseCommandID: RunCommandID("native-completion-release-command"),
      observationCommandID:
        RunCommandID("native-completion-observation-command")
    )
    let completed = try await runtime.completeExternalDependencyObservation(
      launchReceiptID: start.observerLaunch.id,
      request: completionRequest
    )
    XCTAssertEqual(completed.release.exit.exitCode, 0)
    XCTAssertNil(completed.release.exit.terminationSignal)
    XCTAssertEqual(completed.result.mapping.availability, .available)
    XCTAssertEqual(
      completed.result.parse.requestNonce,
      fixture.invocation.receipt.requestArtifact.requestNonce
    )
    XCTAssertEqual(completed.result.standardError.byteCount, 0)
    XCTAssertEqual(completed.observation.observation.availability, .available)
    XCTAssertEqual(
      completed.observation.observation.sourceResultID,
      completed.result.id
    )
    let runtimeProjection = await runtime.projection()
    let supervisorProjection = await supervisor.projection()
    XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    XCTAssertTrue(runtimeProjection.inDoubtResourceIDs.isEmpty)
    XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)

    let retried = try await runtime.completeExternalDependencyObservation(
      launchReceiptID: start.observerLaunch.id,
      request: completionRequest
    )
    XCTAssertEqual(retried.release.release, completed.release.release)
    XCTAssertEqual(retried.result, completed.result)
    XCTAssertEqual(retried.observation.observation, completed.observation.observation)
    XCTAssertEqual(retried.observation.transaction, completed.observation.transaction)

    let recoveredJournal = try RunJournal(
      rootDirectory: root,
      runID: fixture.runID
    )
    let recoveredRuntime = JournaledProcessRuntime(
      supervisor: RuntimeSupervisor(
        runID: fixture.runID,
        budget: HostResourceBudget(nominal: .zero)
      ),
      journal: recoveredJournal,
      actorIdentity: fixture.observer
    )
    let replayed =
      try await recoveredRuntime
      .completeExternalDependencyObservation(
        launchReceiptID: start.observerLaunch.id,
        request: completionRequest
      )
    XCTAssertEqual(replayed.release.release, completed.release.release)
    XCTAssertEqual(replayed.result, completed.result)
    XCTAssertEqual(replayed.observation.observation, completed.observation.observation)
    XCTAssertEqual(replayed.observation.transaction, completed.observation.transaction)
    let recoveredProjection = await recoveredRuntime.projection()
    XCTAssertTrue(recoveredProjection.adapter.liveHandles.isEmpty)
    XCTAssertTrue(recoveredProjection.inDoubtResourceIDs.isEmpty)
  }

  func testRuntimeLaunchIsActivationExactAndReplayStable() async throws {
    let root = try privateTemporaryDirectory()
    let workspace = try privateTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: workspace)
    }
    let fixture = try await activatedFixture(
      root: root,
      workspace: workspace
    )
    let launched = try await journalRuntimeLaunch(fixture)
    XCTAssertFalse(launched.transaction.duplicate)
    let retainedLaunch = await fixture.journal
      .externalDependencyObservationRuntimeLaunchReceipt(
        transaction: launched.transaction
      )
    XCTAssertEqual(
      retainedLaunch,
      launched.launch
    )
    let state = await fixture.journal.state
    XCTAssertEqual(
      state.externalDependencyObservationRuntimeLaunchReceipts?[
        launched.launch.id
      ],
      launched.launch
    )
    XCTAssertEqual(
      state.runtimeBindingReceipts[launched.binding.id],
      launched.binding
    )

    var forgedBinding = launched.binding
    forgedBinding.id = ReceiptID("forged-runtime-binding")
    var forged = launched.launch
    forged.id = ReceiptID("forged-runtime-launch")
    forged.bindingReceiptID = forgedBinding.id
    forged.dependencyID = ExternalDependencyID("crosswired-dependency")
    do {
      _ = try await fixture.journal.transactAtCurrentSequence(
        .testOnlyRecordExternalDependencyObservationRuntimeBinding(
          binding: forgedBinding,
          launch: forged
        ),
        commandID: RunCommandID("forged-runtime-launch-command"),
        issuedAt: forged.launchedAt,
        actor: fixture.observer
      )
      XCTFail("expected crosswired launch rejection")
    } catch RunJournalError.reducerRejected(let rejection) {
      guard case .invalidRuntimeReceipt = rejection else {
        return XCTFail("unexpected rejection: \(rejection)")
      }
    }

    let recovered = try RunJournal(
      rootDirectory: root,
      runID: fixture.runID
    )
    let recoveredState = await recovered.state
    XCTAssertEqual(
      recoveredState
        .externalDependencyObservationRuntimeLaunchReceipts?[
          launched.launch.id
        ],
      launched.launch
    )
  }

  func testLiveReleaseBoundResultIsJournaledExactlyOnceAndReplays()
    async throws
  {
    let root = try privateTemporaryDirectory()
    let workspace = try privateTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: workspace)
    }
    let fixture = try await activatedFixture(
      root: root,
      workspace: workspace
    )
    let release = try await journalNaturalRelease(
      fixture,
      observedAt: Date(timeIntervalSince1970: 30)
    )
    let envelope = ExternalDependencyObservationResultEnvelope(
      dependencyID: fixture.dependencyID,
      evidenceDigest: ContentDigest(String(repeating: "e", count: 64)),
      evidenceRecipeID: fixture.recipeID,
      requestNonce:
        fixture.invocation.receipt.requestArtifact.requestNonce,
      resultCode: "available",
      schemaVersion: 1
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var outputData = try encoder.encode(envelope)
    outputData.append(0x0a)
    let parse = try ExternalDependencyObservationProbe().parse(
      standardOutput: outputData,
      expectation: ExternalDependencyObservationParseExpectation(
        dependencyID: fixture.dependencyID,
        evidenceRecipeID: fixture.recipeID,
        requestNonce:
          fixture.invocation.receipt.requestArtifact.requestNonce,
        parser: fixture.probe.parser
      )
    ).receipt
    let mapping = try XCTUnwrap(
      ExternalDependencyObservationResultMapper.expectedReceipt(
        activation: fixture.invocation.receipt,
        probe: fixture.probe,
        nativeExitCode: 0,
        parse: parse
      )
    )
    let result = try XCTUnwrap(
      ExternalDependencyObservationResultAuthority.expectedReceipt(
        activation: fixture.invocation.receipt,
        probe: fixture.probe,
        release: release.receipt,
        releaseTransaction: release.transaction,
        standardOutput:
          ExternalDependencyObservationOutputFileReceipt(
            fileName: "dependency.stdout",
            byteCount: UInt64(outputData.count),
            contentDigest:
              ExternalDependencyObservationProbe.digest(
                outputData
              )
          ),
        standardError:
          ExternalDependencyObservationOutputFileReceipt(
            fileName: "dependency.stderr",
            byteCount: 0,
            contentDigest:
              ExternalDependencyObservationProbe.digest(Data())
          ),
        parse: parse,
        mapping: mapping
      )
    )
    let authorized =
      AuthorizedExternalDependencyObservationResult
      .testOnly(
        receipt: result,
        release: release.receipt,
        releaseTransaction: release.transaction
      )
    let coordinator = ExternalDependencyObservationJournalCoordinator(
      journal: fixture.journal
    )
    let request = ExternalDependencyObservationJournalRequest(
      commandID: RunCommandID("record-dependency-observation")
    )
    let recorded = try await coordinator.record(
      authorized,
      request: request
    )
    XCTAssertFalse(recorded.transaction.duplicate)
    XCTAssertEqual(recorded.observation.availability, .available)
    XCTAssertEqual(recorded.observation.sourceResultID, result.id)
    XCTAssertEqual(
      recorded.observation.sourceResultEvidenceSetDigest,
      result.evidenceSetDigest
    )
    XCTAssertEqual(
      recorded.observation.sourceReleaseFrameDigest,
      release.transaction.frameDigest
    )
    let state = await fixture.journal.state
    XCTAssertEqual(
      state.externalDependencyReceipts?[recorded.observation.id],
      recorded.observation
    )

    let retried = try await coordinator.record(
      authorized,
      request: request
    )
    XCTAssertEqual(retried.observation, recorded.observation)
    XCTAssertEqual(retried.transaction, recorded.transaction)

    var forged = result
    forged.mapping.availability = .unavailable
    do {
      _ = try await coordinator.record(
        .testOnly(
          receipt: forged,
          release: release.receipt,
          releaseTransaction: release.transaction
        ),
        request: ExternalDependencyObservationJournalRequest(
          commandID: RunCommandID("forged-observation")
        )
      )
      XCTFail("expected forged result rejection")
    } catch let error as ExternalDependencyObservationJournalError {
      XCTAssertEqual(error, .resultNotCurrent)
    }

    let recovered = try RunJournal(
      rootDirectory: root,
      runID: fixture.runID
    )
    let recoveredState = await recovered.state
    XCTAssertEqual(
      recoveredState.externalDependencyReceipts?[
        recorded.observation.id
      ],
      recorded.observation
    )
  }

  private struct Fixture {
    var runID: KernelRunID
    var attemptID: AttemptID
    var dependencyID: ExternalDependencyID
    var recipeID: ExternalDependencyEvidenceRecipeID
    var observer: ActorIdentity
    var probe: ExternalDependencyObservationExecutableProbe
    var journal: RunJournal
    var invocation: AuthorizedExternalDependencyObservationInvocation
  }

  private struct ReleaseFixture {
    var receipt: RuntimeReleaseOutcomeReceipt
    var transaction: JournalTransactionReceipt
  }

  private struct RuntimeLaunchFixture {
    var binding: RuntimeExternalBindingReceipt
    var launch: ExternalDependencyObservationRuntimeLaunchReceipt
    var transaction: JournalTransactionReceipt
    var identity: RuntimeExternalIdentity
  }

  private func activatedFixture(
    root: URL,
    workspace: URL,
    emitsCanonicalResult: Bool = false
  ) async throws
    -> Fixture
  {
    let runID = KernelRunID("observation-run")
    let attemptID = AttemptID("observation-attempt")
    let requirementID = RequirementID("observation-requirement")
    let dependencyID = ExternalDependencyID("observation-dependency")
    let recipeID = ExternalDependencyEvidenceRecipeID(
      "observation-recipe"
    )
    let worker = ActorIdentity(
      id: ActorID("observation-worker"),
      role: "executor",
      lineageDigest: ContentDigest(String(repeating: "1", count: 64))
    )
    let observer = ActorIdentity(
      id: ActorID("observation-observer"),
      role: "external-observer",
      lineageDigest: ContentDigest(String(repeating: "2", count: 64))
    )
    var probe = externalDependencyObservationProbeFixture()
    probe.fixedArguments = [
      emitsCanonicalResult
        ? "--observe-external-dependency"
        : "--consume-external-dependency-request",
      "--request",
      ExternalDependencyObservationExecutableProbe.requestArgumentToken,
    ]
    probe.executableContentDigest = try XCTUnwrap(
      ProcessGroupRuntimeAdapter.executableContentDigest(
        atPath: kernelProcessFixturePath
      )
    )
    let strategy = CausalStrategyDescriptor(
      requirementIDs: [requirementID],
      hypothesisClass: "dependency-observation",
      actionClass: "observe-dependency",
      workspaceTopology: "read-only-workspace",
      capabilityRoute: ["local-direct-process"],
      evidenceSources: ["external-dependency"],
      measurementBoundary: "dependency",
      verificationOracles: ["independent-observer"],
      mutationSurfaceDigest: ContentDigest("no-mutation"),
      baselineRevision: ContentDigest("observation-baseline"),
      expectedObservationIDs: ["dependency-observed"],
      falsificationPredicateIDs: ["dependency-unobserved"],
      inheritedLessonDigests: []
    )
    let canonicalWorkspace = workspace.standardizedFileURL
      .resolvingSymlinksInPath()
    let contract = TaskContract(
      id: TaskContractID("observation-contract"),
      schemaVersion: 1,
      verbatimObjective: "Observe one declared external dependency.",
      objectiveDigest: ContentDigest("observation-objective"),
      requirements: [
        RequirementContract(
          id: requirementID,
          statement: "Observe the declared dependency.",
          mandatory: true,
          evidenceRecipeIDs: []
        )
      ],
      constraints: [],
      nonGoals: [],
      protectedBaselines: [],
      workspaceBinding: TaskContractWorkspaceBinding(
        workspaceID: WorkspaceID("observation-workspace"),
        canonicalRootDigest:
          WorkspaceRepositoryIndexer
          .canonicalRootDigest(canonicalWorkspace)
      ),
      externalDependencies: [
        ExternalDependencyContract(
          id: dependencyID,
          kind: .authority,
          requirementIDs: [requirementID],
          evidenceRecipeID: recipeID,
          authorizedObserverLineageDigests: [observer.lineageDigest],
          executableProbe: probe
        )
      ],
      authorityCeiling: .readOnly,
      acceptancePolicy: TaskAcceptancePolicy(
        duration: nil,
        requiresIndependentReview: true,
        requiresQuiescence: true
      ),
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let journal = try RunJournal(rootDirectory: root, runID: runID)
    var index = 0
    func transact(_ command: RunCommand, actor: ActorIdentity) async throws {
      index += 1
      _ = try await journal.transactAtCurrentSequence(
        command,
        commandID: RunCommandID("observation-setup-\(index)"),
        issuedAt: Date(timeIntervalSince1970: TimeInterval(index)),
        actor: actor
      )
    }
    try await transact(.createRun(contract), actor: worker)
    try await transact(
      .proposePlan(
        KernelPlanProposal(
          contractDigest: contract.objectiveDigest,
          nodes: [
            KernelNodeContract(
              id: KernelNodeID("observation-node"),
              requirementIDs: [requirementID],
              objective: "Observe dependency",
              dependencies: [],
              mutationScope: .readOnly,
              capabilityIDs: [],
              strategyFingerprint: strategy.fingerprint
            )
          ]
        )), actor: worker)
    try await transact(
      .authorizeNode(KernelNodeID("observation-node")),
      actor: observer
    )
    try await transact(
      .initializeConvergence(
        epochID: "observation-epoch",
        budget: ConvergenceBudget(
          maximumAttempts: 1,
          maximumEquivalentFailures: 1,
          maximumStrategies: 1,
          maximumPlanExpansions: 1,
          maximumMutationCost: 0,
          maximumVerificationCost: 1,
          maximumDamageEvents: 0,
          maximumExternalEffects: 1
        )
      ), actor: observer)
    try await transact(
      .admitCausalAttempt(
        AttemptAdmissionRequest(
          attemptID: attemptID,
          strategy: strategy,
          predictedObservationIDs: ["dependency-observed"],
          falsificationPredicateIDs: ["dependency-unobserved"],
          rollbackPoint: ContentDigest("observation-rollback"),
          mutationCost: 0,
          verificationCost: 1,
          externalEffects: 1
        )), actor: observer)
    try await transact(
      .startAttempt(
        attemptID: attemptID,
        nodeID: KernelNodeID("observation-node"),
        requirementIDs: [requirementID],
        strategyFingerprint: strategy.fingerprint
      ), actor: worker)
    let invocation = try await ExternalDependencyObservationActivationCoordinator(
      journal: journal
    ).activate(
      ExternalDependencyObservationActivationRequest(
        receiptID: ReceiptID("observation-activation"),
        commandID: RunCommandID("observation-activate-command"),
        dependencyID: dependencyID,
        observer: observer,
        executablePath: kernelProcessFixturePath,
        workspaceRoot: canonicalWorkspace,
        activatedAt: Date(timeIntervalSince1970: 20)
      ))
    return Fixture(
      runID: runID,
      attemptID: attemptID,
      dependencyID: dependencyID,
      recipeID: recipeID,
      observer: observer,
      probe: probe,
      journal: journal,
      invocation: invocation
    )
  }

  private func journalNaturalRelease(
    _ fixture: Fixture,
    observedAt: Date
  ) async throws -> ReleaseFixture {
    let launched = try await journalRuntimeLaunch(fixture)
    let binding = launched.binding
    let identity = launched.identity
    let resourceID = binding.resourceID
    let leaseID = binding.leaseID
    let monotonic = binding.observedAtMonotonicNanoseconds - 2
    let handle = ManagedProcessHandle(
      runID: fixture.runID,
      resourceID: resourceID,
      leaseID: leaseID,
      processID: 42,
      processGroupID: 42,
      externalIdentity: identity
    )
    let releaseID = ReceiptID("observation-release")
    let release = RuntimeReleaseOutcomeReceipt(
      id: releaseID,
      runID: fixture.runID,
      resourceID: resourceID,
      leaseID: leaseID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: monotonic + 3,
      outcome: .released(
        RuntimeReleaseReceipt(
          id: releaseID,
          runID: fixture.runID,
          leaseID: leaseID,
          resourceID: resourceID,
          releasedAtMonotonicNanoseconds: monotonic + 3,
          duplicate: false
        )),
      managedProcessExit: ManagedProcessExitReceipt(
        handle: handle,
        observedAtMonotonicNanoseconds: monotonic + 3,
        exitCode: 0,
        terminationSignal: nil
      )
    )
    let transaction = try await fixture.journal.transactAtCurrentSequence(
      .testOnlyRecordRuntimeRelease(release),
      commandID: RunCommandID("observation-release-command"),
      issuedAt: observedAt,
      actor: fixture.observer
    )
    return ReleaseFixture(receipt: release, transaction: transaction)
  }

  private func journalRuntimeLaunch(
    _ fixture: Fixture
  ) async throws -> RuntimeLaunchFixture {
    let resourceID = OwnedResourceID("observation-resource")
    let leaseID = ResourceLeaseID("observation-lease")
    let monotonic: UInt64 = 10_000
    let request = RuntimeLeaseRequest(
      leaseID: leaseID,
      resourceID: resourceID,
      runID: fixture.runID,
      occurrenceID: nil,
      attemptID: fixture.attemptID,
      kind: .processTree,
      purpose: .productive,
      ownership: .owned,
      releasePolicy: .gracefulThenTerminate,
      externalIdentity: nil,
      reservation: .zero,
      requestedAtMonotonicNanoseconds: monotonic,
      renewalDeadlineMonotonicNanoseconds: nil,
      progressReceiptID: nil
    )
    let lease = RuntimeResourceLease(
      request: request,
      admittedAtMonotonicNanoseconds: monotonic + 1,
      lastProgressReceiptID: nil
    )
    let admission = RuntimeAdmissionReceipt(
      id: ReceiptID("observation-admission"),
      runID: fixture.runID,
      request: request,
      outcome: .accepted(lease, duplicate: false),
      observedAt: Date(timeIntervalSince1970: 28),
      observedAtMonotonicNanoseconds: monotonic + 1
    )
    _ = try await fixture.journal.transactAtCurrentSequence(
      .testOnlyRecordRuntimeAdmission(admission),
      commandID: RunCommandID("observation-admission-command"),
      issuedAt: admission.observedAt,
      actor: fixture.observer
    )
    let ioDirectory = await fixture.journal.runDirectory.path
    let io = ManagedProcessIOFiles(
      directoryPath: ioDirectory,
      standardInputFileName:
        fixture.invocation.receipt.requestArtifact.fileName,
      standardOutputFileName: "dependency.stdout",
      standardErrorFileName: "dependency.stderr"
    )
    let sandboxAuthorization = KernelNativeSandboxReceipt(
      schemaVersion: 1,
      sandbox: .readOnly,
      networkPolicy: fixture.invocation.receipt.networkPolicy,
      launcherPath: "/usr/bin/sandbox-exec",
      launcherContentDigest:
        ContentDigest(String(repeating: "3", count: 64)),
      gateExecutablePath: "/tmp/KernelSandboxGate",
      gateExecutableContentDigest:
        ContentDigest(String(repeating: "4", count: 64)),
      profileDigest:
        ContentDigest(String(repeating: "5", count: 64)),
      parameterDigest:
        ContentDigest(String(repeating: "6", count: 64)),
      workspaceRootPathDigest:
        KernelNativeSandboxAuthorizer.workspacePathDigest(
          fixture.invocation.receipt.workspaceRootPath
        ),
      journalRunDirectoryPathDigest:
        KernelNativeSandboxAuthorizer.journalRunDirectoryPathDigest(
          ioDirectory
        ),
      standardOutputPathDigest:
        KernelNativeSandboxAuthorizer.outputPathDigest(
          directoryPath: ioDirectory,
          fileName: io.standardOutputFileName
        ),
      standardErrorPathDigest:
        KernelNativeSandboxAuthorizer.errorPathDigest(
          directoryPath: ioDirectory,
          fileName: io.standardErrorFileName
        ),
      journalWritesDefaultDenied: true,
      nativeAttestationRequired: true
    )
    let sandbox = KernelNativeSandboxAttestationReceipt(
      authorization: sandboxAuthorization,
      processID: 42,
      observedAtMonotonicNanoseconds: monotonic + 2,
      nativeSandboxCheckResult: 1,
      gateObservedStopped: true,
      targetExecHandshakeSucceeded: true,
      candidateWorkingDirectory: nil
    )
    let limits = ManagedProcessKernelResourceLimits(
      maximumOutputFileBytes: fixture.invocation.receipt.resourceLimits
        .maximumCapturedOutputBytes / 2,
      maximumProcessCount: 1
    )
    let identity = RuntimeExternalIdentity(
      stableDigest: ContentDigest(String(repeating: "9", count: 64)),
      processID: 42,
      processStartMonotonicNanoseconds: monotonic + 2,
      executableContentDigest:
        fixture.invocation.receipt.executableStaging.contentDigest,
      environmentContentDigest:
        fixture.invocation.receipt.environmentIdentityDigest,
      argumentVectorContentDigest:
        fixture.invocation.receipt.argumentVectorDigest,
      nativeSandboxAttestation: sandbox,
      kernelResourceLimits: limits
    )
    let binding = RuntimeExternalBindingReceipt(
      id: ReceiptID("observation-binding"),
      runID: fixture.runID,
      resourceID: resourceID,
      leaseID: leaseID,
      identity: identity,
      accepted: true,
      observedAt: Date(timeIntervalSince1970: 29),
      observedAtMonotonicNanoseconds: monotonic + 2
    )
    let launch = ExternalDependencyObservationRuntimeLaunchReceipt(
      schemaVersion: 1,
      id: ReceiptID("observation-runtime-launch"),
      runID: fixture.runID,
      activationReceiptID: fixture.invocation.receipt.id,
      activationJournalFrameDigest:
        fixture.invocation.activationTransaction.frameDigest,
      attemptID: fixture.attemptID,
      dependencyID: fixture.dependencyID,
      evidenceRecipeID: fixture.recipeID,
      observer: fixture.observer,
      resourceID: resourceID,
      leaseID: leaseID,
      bindingReceiptID: binding.id,
      executableStaging: fixture.invocation.receipt.executableStaging,
      requestArtifact: fixture.invocation.receipt.requestArtifact,
      resolvedArguments: fixture.invocation.receipt.resolvedArguments,
      argumentVectorDigest:
        fixture.invocation.receipt.argumentVectorDigest,
      processEnvironment: KernelProcessEnvironmentReceipt(
        policy: .minimalKernelAllowlist,
        variableNames: KernelProcessEnvironmentAuthorizer
          .minimalEnvironment.keys.sorted(),
        environmentDigest:
          fixture.invocation.receipt.environmentIdentityDigest
      ),
      processIOFiles: io,
      nativeSandbox: sandbox,
      parser: fixture.invocation.receipt.parser,
      resultMappings: fixture.invocation.receipt.resultMappings,
      networkPolicy: fixture.invocation.receipt.networkPolicy,
      resourceLimits: fixture.invocation.receipt.resourceLimits,
      residentMemoryCeilingBytes:
        fixture.invocation.receipt.resourceLimits.maximumResidentBytes,
      launchedAt: binding.observedAt
    )
    let transaction = try await fixture.journal.transactAtCurrentSequence(
      .testOnlyRecordExternalDependencyObservationRuntimeBinding(
        binding: binding,
        launch: launch
      ),
      commandID: RunCommandID("observation-binding-command"),
      issuedAt: binding.observedAt,
      actor: fixture.observer
    )
    return RuntimeLaunchFixture(
      binding: binding,
      launch: launch,
      transaction: transaction,
      identity: identity
    )
  }

  private func privateTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )
    return directory
  }

  private var kernelProcessFixturePath: String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/debug/KernelProcessFixture")
      .standardizedFileURL.path
  }
}
