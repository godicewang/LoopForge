import Foundation
import XCTest

@testable import LoopForge

final class NativeIndependentVisualReviewAdapterTests: XCTestCase {
  func testDistinctRatifiedReviewerProducesCompleteAdapterOwnedReview() async throws {
    let fixture = try await makeFixture()
    let harness = StubIndependentVisualReviewHarness(
      identity: "signed-independent-reviewer-v1",
      reviewer: reviewer,
      mode: .pass
    )
    let adapter = reviewAdapter(harness)

    let authority = try await adapter.review(fixture.request)
    let review = try XCTUnwrap(authority.candidate.independentReview)

    XCTAssertEqual(review.reviewer, reviewer)
    XCTAssertEqual(review.workerLineageDigest, worker.lineageDigest)
    XCTAssertEqual(review.provider, "fixture-provider")
    XCTAssertEqual(review.model, "fixture-model")
    XCTAssertTrue(review.blindToWorkerNarrative)
    XCTAssertEqual(review.decision, .pass)
    XCTAssertEqual(review.inspectedCellIDs, [cellID])
    XCTAssertEqual(authority.candidate.reviewBatches.count, 1)
    XCTAssertTrue(authority.candidate.reviewBatches[0].isComplete)
    XCTAssertEqual(authority.captureAttestationDigests.count, 1)
    XCTAssertEqual(authority.measurementAttestationDigests.count, 1)
    XCTAssertEqual(authority.requestDigest.rawValue.count, 64)
    XCTAssertTrue(
      DesignBaselineGate.evaluate(
        baseline: fixture.request.baseline,
        candidate: authority.candidate
      ).accepted
    )
    XCTAssertFalse(
      AuthorizedNativeIndependentVisualReview.self is any Codable.Type
    )
  }

  func testReviewerLineageMustDifferBeforeHarnessInvocation() async throws {
    let fixture = try await makeFixture()
    let harness = StubIndependentVisualReviewHarness(
      identity: "signed-independent-reviewer-v1",
      reviewer: ActorIdentity(
        id: ActorID("reviewer"),
        role: "independentProductDesignReviewer",
        lineageDigest: worker.lineageDigest
      ),
      mode: .pass
    )
    await assertError(.reviewerLineageNotIndependent) {
      _ = try await self.reviewAdapter(harness).review(fixture.request)
    }
    let invocationCount = await harness.invocationCount
    XCTAssertEqual(invocationCount, 0)
  }

  func testIncompleteDecisionMatrixCannotBecomeReviewAuthority() async throws {
    let fixture = try await makeFixture()
    let harness = StubIndependentVisualReviewHarness(
      identity: "signed-independent-reviewer-v1",
      reviewer: reviewer,
      mode: .incomplete
    )
    await assertError(.incompleteDecisionMatrix) {
      _ = try await self.reviewAdapter(harness).review(fixture.request)
    }
  }

  func testBaselineImageBytesAreRevalidatedAgainstFrozenReceipt() async throws {
    var fixture = try await makeFixture()
    fixture.request.baselineEncodedImages[cellID] = Data("not-a-png".utf8)
    let harness = StubIndependentVisualReviewHarness(
      identity: "signed-independent-reviewer-v1",
      reviewer: reviewer,
      mode: .pass
    )
    await assertError(.invalidBaselineImage(cellID)) {
      _ = try await self.reviewAdapter(harness).review(fixture.request)
    }
    let invocationCount = await harness.invocationCount
    XCTAssertEqual(invocationCount, 0)
  }

  func testIndependentVetoIsDerivedAndRemainsDurableRedEvidence() async throws {
    let fixture = try await makeFixture()
    let harness = StubIndependentVisualReviewHarness(
      identity: "signed-independent-reviewer-v1",
      reviewer: reviewer,
      mode: .fail
    )

    let authority = try await reviewAdapter(harness).review(fixture.request)
    let review = try XCTUnwrap(authority.candidate.independentReview)
    let result = DesignBaselineGate.evaluate(
      baseline: fixture.request.baseline,
      candidate: authority.candidate
    )

    XCTAssertEqual(review.decision, .fail)
    XCTAssertFalse(result.accepted)
    XCTAssertTrue(
      result.failingDimensions.contains(.independentProductDesignVerdict)
    )
  }

  func testCoordinatorJournalsLiveNativeReviewAndRecoversExactly() async throws {
    let fixture = try await makeFixture()
    let reviewAuthority = try await reviewAdapter(
      StubIndependentVisualReviewHarness(
        identity: "signed-independent-reviewer-v1",
        reviewer: reviewer,
        mode: .pass
      )
    ).review(fixture.request)
    let journalFixture = try await makeJournalFixture(
      baseline: fixture.request.baseline
    )
    defer { try? FileManager.default.removeItem(at: journalFixture.root) }
    let coordinator = JournaledNativeVisualEvaluationCoordinator(
      journal: journalFixture.journal,
      evaluator: visualEvaluator,
      clock: { Date(timeIntervalSince1970: 180) }
    )

    let first = try await coordinator.evaluate(
      JournaledNativeVisualEvaluationRequest(
        execution: journalFixture.execution,
        review: reviewAuthority
      )
    )

    XCTAssertTrue(first.visualGateReceipt.result.accepted)
    XCTAssertEqual(first.kernelProjection.visualEvaluationCount, 1)
    XCTAssertEqual(first.kernelProjection.latestVisualAccepted, true)
    XCTAssertEqual(
      first.visualGateReceipt.nativeReviewRequestDigest,
      reviewAuthority.requestDigest
    )
    XCTAssertEqual(
      first.visualGateReceipt.nativeCaptureAttestationDigests,
      reviewAuthority.captureAttestationDigests
    )
    XCTAssertEqual(
      first.visualGateReceipt.nativeMeasurementAttestationDigests,
      reviewAuthority.measurementAttestationDigests
    )

    let duplicate = try await coordinator.evaluate(
      JournaledNativeVisualEvaluationRequest(
        execution: journalFixture.execution,
        review: reviewAuthority
      )
    )
    XCTAssertTrue(duplicate.journalTransaction.duplicate)
    XCTAssertEqual(duplicate.visualGateReceipt, first.visualGateReceipt)
    XCTAssertEqual(duplicate.kernelProjection.visualEvaluationCount, 1)

    let recovered = try RunJournal(
      rootDirectory: journalFixture.root,
      runID: journalFixture.execution.runID
    )
    let recoveredReceipt = await recovered.nativeVisualEvaluationReceipt(
      transaction: first.journalTransaction
    )
    let recoveredProjection = await recovered.currentProjection()
    XCTAssertEqual(recoveredReceipt, first.visualGateReceipt)
    XCTAssertEqual(recoveredProjection.visualEvaluationCount, 1)
  }

  func testProductionEvaluatorIdentityJournalsExactLiveReview() async throws {
    let fixture = try await makeFixture()
    let reviewAuthority = try await reviewAdapter(
      StubIndependentVisualReviewHarness(
        identity: "signed-independent-reviewer-v1",
        reviewer: reviewer,
        mode: .pass
      )
    ).review(fixture.request)
    let journalFixture = try await makeJournalFixture(
      baseline: fixture.request.baseline
    )
    defer { try? FileManager.default.removeItem(at: journalFixture.root) }

    let receipt = try await JournaledNativeVisualEvaluationCoordinator(
      journal: journalFixture.journal
    ).evaluate(
      JournaledNativeVisualEvaluationRequest(
        execution: journalFixture.execution,
        review: reviewAuthority
      )
    )

    XCTAssertTrue(receipt.visualGateReceipt.result.accepted)
    XCTAssertEqual(
      receipt.visualGateReceipt.evaluator,
      KernelNativeVisualEvaluationIdentity.deterministicEvaluator
    )
    XCTAssertEqual(receipt.kernelProjection.visualEvaluationCount, 1)
  }

  func testCoordinatorRejectsCrossWiredExecutionProofWithoutAppending() async throws {
    let fixture = try await makeFixture()
    let reviewAuthority = try await reviewAdapter(
      StubIndependentVisualReviewHarness(
        identity: "signed-independent-reviewer-v1",
        reviewer: reviewer,
        mode: .pass
      )
    ).review(fixture.request)
    let journalFixture = try await makeJournalFixture(
      baseline: fixture.request.baseline
    )
    defer { try? FileManager.default.removeItem(at: journalFixture.root) }
    let before = await journalFixture.journal.headSnapshot()
    var crossWiredTransaction = journalFixture.execution.activationTransaction
    crossWiredTransaction.frameDigest = ContentDigest(
      String(repeating: "d", count: 64)
    )
    let crossWired = JournaledKernelExecutionProof.testOnly(
      runID: journalFixture.execution.runID,
      attemptID: journalFixture.execution.attemptID,
      nodeID: journalFixture.execution.nodeID,
      strategyFingerprint: journalFixture.execution.strategyFingerprint,
      workerExecutionProfile:
        journalFixture.execution.workerExecutionProfile,
      workspaceRoot: journalFixture.execution.workspaceRoot,
      activationActor: journalFixture.execution.activationActor,
      activationTransaction: crossWiredTransaction
    )
    let coordinator = JournaledNativeVisualEvaluationCoordinator(
      journal: journalFixture.journal,
      evaluator: visualEvaluator,
      clock: { Date(timeIntervalSince1970: 180) }
    )

    do {
      _ = try await coordinator.evaluate(
        JournaledNativeVisualEvaluationRequest(
          execution: crossWired,
          review: reviewAuthority
        )
      )
      XCTFail("Expected cross-wired proof rejection")
    } catch let error as JournaledNativeVisualEvaluationError {
      XCTAssertEqual(error, .invalidExecutionProof)
    }
    let after = await journalFixture.journal.headSnapshot()
    let projection = await journalFixture.journal.currentProjection()
    XCTAssertEqual(after, before)
    XCTAssertEqual(projection.visualEvaluationCount, 0)
  }

  func testCoordinatorRejectsExecutionProfileSubstitution() async throws {
    let fixture = try await makeFixture()
    let reviewAuthority = try await reviewAdapter(
      StubIndependentVisualReviewHarness(
        identity: "signed-independent-reviewer-v1",
        reviewer: reviewer,
        mode: .pass
      )
    ).review(fixture.request)
    let journalFixture = try await makeJournalFixture(
      baseline: fixture.request.baseline
    )
    defer { try? FileManager.default.removeItem(at: journalFixture.root) }
    var substitutedProfile = journalFixture.execution.workerExecutionProfile
    substitutedProfile.modelID = "substituted-worker-model"
    let substituted = JournaledKernelExecutionProof.testOnly(
      runID: journalFixture.execution.runID,
      attemptID: journalFixture.execution.attemptID,
      nodeID: journalFixture.execution.nodeID,
      strategyFingerprint: journalFixture.execution.strategyFingerprint,
      workerExecutionProfile: substitutedProfile,
      workspaceRoot: journalFixture.execution.workspaceRoot,
      activationActor: journalFixture.execution.activationActor,
      activationTransaction:
        journalFixture.execution.activationTransaction
    )
    let coordinator = JournaledNativeVisualEvaluationCoordinator(
      journal: journalFixture.journal,
      evaluator: visualEvaluator,
      clock: { Date(timeIntervalSince1970: 180) }
    )

    do {
      _ = try await coordinator.evaluate(
        JournaledNativeVisualEvaluationRequest(
          execution: substituted,
          review: reviewAuthority
        )
      )
      XCTFail("Expected worker-profile substitution rejection")
    } catch let error as JournaledNativeVisualEvaluationError {
      guard case .invalidReviewAuthority = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
    let projection = await journalFixture.journal.currentProjection()
    XCTAssertEqual(projection.visualEvaluationCount, 0)
  }

  func testCoordinatorJournalsIndependentVetoAsDurableRedEvidence() async throws {
    let fixture = try await makeFixture()
    let reviewAuthority = try await reviewAdapter(
      StubIndependentVisualReviewHarness(
        identity: "signed-independent-reviewer-v1",
        reviewer: reviewer,
        mode: .fail
      )
    ).review(fixture.request)
    let journalFixture = try await makeJournalFixture(
      baseline: fixture.request.baseline
    )
    defer { try? FileManager.default.removeItem(at: journalFixture.root) }
    let coordinator = JournaledNativeVisualEvaluationCoordinator(
      journal: journalFixture.journal,
      evaluator: visualEvaluator,
      clock: { Date(timeIntervalSince1970: 180) }
    )

    let receipt = try await coordinator.evaluate(
      JournaledNativeVisualEvaluationRequest(
        execution: journalFixture.execution,
        review: reviewAuthority
      )
    )

    XCTAssertFalse(receipt.visualGateReceipt.result.accepted)
    XCTAssertTrue(
      receipt.visualGateReceipt.result.failingDimensions.contains(
        .independentProductDesignVerdict
      )
    )
    XCTAssertEqual(receipt.kernelProjection.latestVisualAccepted, false)
    XCTAssertEqual(receipt.kernelProjection.visualEvaluationCount, 1)
  }

  private struct Fixture {
    var request: NativeIndependentVisualReviewRequest
  }

  private struct JournalFixture {
    var root: URL
    var journal: RunJournal
    var execution: JournaledKernelExecutionProof
  }

  private func makeJournalFixture(
    baseline: DesignBaselineBundle
  ) async throws -> JournalFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "journaled-native-visual-\(UUID().uuidString)",
      isDirectory: true
    )
    let runID = KernelRunID("native-visual-run-\(UUID().uuidString)")
    let nodeID = KernelNodeID("native-visual-node")
    let attemptID = AttemptID("native-visual-attempt")
    let objectiveDigest = ContentDigest(String(repeating: "b", count: 64))
    let strategy = CausalStrategyDescriptor(
      requirementIDs: baseline.requirementIDs,
      hypothesisClass: "preserve-native-visual-baseline",
      actionClass: "evaluate-native-visual-candidate",
      workspaceTopology: "bounded-test-workspace",
      capabilityRoute: ["native-capture"],
      evidenceSources: ["native-capture", "deterministic-measurement"],
      measurementBoundary: "visual-cell",
      verificationOracles: ["deterministic-visual-gate"],
      mutationSurfaceDigest: ContentDigest(
        String(repeating: "c", count: 64)
      ),
      baselineRevision: baseline.sourceTree,
      expectedObservationIDs: ["native-candidate-compared"],
      falsificationPredicateIDs: ["visual-regression"],
      inheritedLessonDigests: []
    )
    let contract = TaskContract(
      id: baseline.contractID,
      schemaVersion: 1,
      verbatimObjective: "Evaluate the native candidate without visual regression.",
      objectiveDigest: objectiveDigest,
      requirements: baseline.requirementIDs.map {
        RequirementContract(
          id: $0,
          statement: "The protected visual baseline must not regress.",
          mandatory: true,
          evidenceRecipeIDs: [EvidenceRecipeID("native-visual-evidence")]
        )
      },
      constraints: [],
      nonGoals: [],
      protectedBaselines: [
        BaselineReference(
          id: baseline.protectedBaselineID,
          artifactDigest: baseline.builtArtifact,
          environmentDigest: nil,
          preservationRequired: true
        )
      ],
      executionProfile: executionProfile,
      authorityCeiling: KernelAuthorityCeiling(
        readableScopes: ["."],
        writableScopes: ["Sources"],
        capabilityIDs: ["native-capture"],
        permitsExternalPublication: false
      ),
      acceptancePolicy: TaskAcceptancePolicy(
        duration: nil,
        requiresIndependentReview: true,
        requiresQuiescence: false
      ),
      createdAt: Date(timeIntervalSince1970: 90)
    )
    let plan = KernelPlanProposal(
      contractDigest: objectiveDigest,
      nodes: [
        KernelNodeContract(
          id: nodeID,
          requirementIDs: baseline.requirementIDs,
          objective: "Produce one natively measured visual candidate.",
          dependencies: [],
          mutationScope: KernelMutationScope(
            writablePaths: ["Sources"],
            maximumChangedFiles: 1,
            maximumChangedBytes: 1_024
          ),
          capabilityIDs: ["native-capture"],
          strategyFingerprint: strategy.fingerprint
        )
      ]
    )
    let journal = try RunJournal(rootDirectory: root, runID: runID)
    _ = try await journal.transactAtCurrentSequence(
      .createRun(contract),
      commandID: RunCommandID("create"),
      issuedAt: Date(timeIntervalSince1970: 96),
      actor: baseline.authority.authority
    )
    _ = try await journal.transactAtCurrentSequence(
      .testOnlyFreezeDesignBaseline(baseline),
      commandID: RunCommandID("freeze"),
      issuedAt: Date(timeIntervalSince1970: 101),
      actor: baseline.authority.authority
    )
    _ = try await journal.transactAtCurrentSequence(
      .proposePlan(plan),
      commandID: RunCommandID("plan"),
      issuedAt: Date(timeIntervalSince1970: 102),
      actor: worker
    )
    _ = try await journal.transactAtCurrentSequence(
      .authorizeNode(nodeID),
      commandID: RunCommandID("authorize"),
      issuedAt: Date(timeIntervalSince1970: 103),
      actor: worker
    )
    _ = try await journal.transactAtCurrentSequence(
      .initializeConvergence(
        epochID: "native-visual-epoch",
        budget: ConvergenceBudget(
          maximumAttempts: 1,
          maximumEquivalentFailures: 1,
          maximumStrategies: 1,
          maximumPlanExpansions: 0,
          maximumMutationCost: 1_024,
          maximumVerificationCost: 1_024,
          maximumDamageEvents: 0,
          maximumExternalEffects: 1
        )
      ),
      commandID: RunCommandID("initialize-convergence"),
      issuedAt: Date(timeIntervalSince1970: 104),
      actor: baseline.authority.authority
    )
    _ = try await journal.transactAtCurrentSequence(
      .admitCausalAttempt(
        AttemptAdmissionRequest(
          attemptID: attemptID,
          strategy: strategy,
          predictedObservationIDs: ["native-candidate-compared"],
          falsificationPredicateIDs: ["visual-regression"],
          rollbackPoint: baseline.sourceTree,
          mutationCost: 1,
          verificationCost: 1,
          externalEffects: 1
        )),
      commandID: RunCommandID("admit-attempt"),
      issuedAt: Date(timeIntervalSince1970: 105),
      actor: baseline.authority.authority
    )
    let start = try await journal.transactAtCurrentSequence(
      .startAttempt(
        attemptID: attemptID,
        nodeID: nodeID,
        requirementIDs: baseline.requirementIDs,
        strategyFingerprint: strategy.fingerprint
      ),
      commandID: RunCommandID("start"),
      issuedAt: Date(timeIntervalSince1970: 106),
      actor: worker
    )
    try await journalTestWorkerDisposition(
      journal,
      runID: runID,
      attemptID: attemptID,
      actor: worker,
      prefix: "native-visual-execution",
      startingAt: 120
    )
    return JournalFixture(
      root: root,
      journal: journal,
      execution: JournaledKernelExecutionProof.testOnly(
        runID: runID,
        attemptID: attemptID,
        nodeID: nodeID,
        strategyFingerprint: strategy.fingerprint,
        workerExecutionProfile: executionProfile.worker,
        workspaceRoot: root,
        activationActor: worker,
        activationTransaction: start
      )
    )
  }

  private func makeFixture() async throws -> Fixture {
    let baselineAuthority = try await captureAuthority(
      source: baselineSource,
      artifact: baselineArtifact,
      capturedAt: 90
    )
    let candidateAuthority = try await captureAuthority(
      source: candidateSource,
      artifact: candidateArtifact,
      capturedAt: 150
    )
    let baseline = DesignBaselineBundle(
      id: DesignBaselineID("native-baseline"),
      contractID: TaskContractID("contract"),
      protectedBaselineID: BaselineID("protected-baseline"),
      requirementIDs: [RequirementID("requirement")],
      sourceTree: baselineSource,
      builtArtifact: baselineArtifact,
      captureProtocol: captureProtocol,
      designTokenSnapshot: ContentDigest(String(repeating: "7", count: 64)),
      semanticSurfaceManifest: ContentDigest(String(repeating: "8", count: 64)),
      captures: [baselineAuthority.attestation.receipt],
      protectedInvariants: measurableDimensions.map {
        DesignInvariant(
          id: "invariant-\($0.rawValue)",
          dimension: $0,
          cellIDs: [cellID]
        )
      },
      knownDebt: [],
      authority: DesignAuthorityReceipt(
        id: ReceiptID("design-authority"),
        baselineID: DesignBaselineID("native-baseline"),
        authority: ActorIdentity(
          id: ActorID("designer"),
          role: "productDesignAuthority",
          lineageDigest: ContentDigest("designer-lineage")
        ),
        authorityRole: "productDesignAuthority",
        issuedAt: Date(timeIntervalSince1970: 95)
      ),
      frozenAt: Date(timeIntervalSince1970: 100)
    )
    let measurementHarness = StubReviewMeasurementHarness(
      identity: "signed-visual-measurer-v1",
      output: NativeVisualMeasurementHarnessOutput(
        measurement: measurement,
        debtSeverityByID: [:],
        rawEvidence: Data(#"{"engine":"deterministic"}"#.utf8),
        processExitCode: 0
      )
    )
    let measurementAdapter = NativeVisualMeasurementAdapter(
      harness: measurementHarness,
      allowedHarnessIdentities: [measurementHarness.identity],
      clock: { Date(timeIntervalSince1970: 160) }
    )
    let measurementAuthority = try await measurementAdapter.measure(
      NativeVisualMeasurementRequest(
        baselineCapture: baselineAuthority.attestation.receipt,
        candidateCaptureAuthority: candidateAuthority,
        protectedDimensions: measurableDimensions,
        knownDebt: [],
        measurementProtocol: ContentDigest(String(repeating: "6", count: 64)),
        notBefore: Date(timeIntervalSince1970: 110)
      )
    )
    return Fixture(
      request: NativeIndependentVisualReviewRequest(
        baseline: baseline,
        baselineEncodedImages: [cellID: baselineAuthority.encodedImage],
        candidateSourceTree: candidateSource,
        candidateBuiltArtifact: candidateArtifact,
        mutationStartedAt: Date(timeIntervalSince1970: 110),
        candidateCaptures: [candidateAuthority],
        measurements: [measurementAuthority],
        mutationManifest: VisualMutationManifest(
          directlyAffectedCellIDs: [cellID],
          allBaselineCellIDs: [cellID],
          globalSemanticTokenMutation: false,
          touchedTokenFamilies: []
        ),
        executionProfile: executionProfile,
        worker: worker,
        maximumImagesPerBatch: 3,
        notBefore: Date(timeIntervalSince1970: 160)
      ))
  }

  private func captureAuthority(
    source: ContentDigest,
    artifact: ContentDigest,
    capturedAt: TimeInterval
  ) async throws -> AuthorizedNativeCapture {
    let harness = StubReviewCaptureHarness(
      identity: "signed-native-capture-v1",
      output: NativeCaptureHarnessOutput(
        encodedImage: onePixelPNG,
        accessibilityTree: Data(#"{"role":"window","children":[]}"#.utf8),
        observedTraits: traits,
        cleanInstallEvidence: Data(#"{"reset":true}"#.utf8),
        componentBoundaryTrace: Data(#"{"components":["root"]}"#.utf8),
        designTokenTrace: Data(#"{"tokens":["semantic.primary"]}"#.utf8),
        fullViewport: true,
        cleanInstall: true,
        processExitCode: 0
      )
    )
    let adapter = NativeVisualCaptureAdapter(
      harness: harness,
      allowedHarnessIdentities: [harness.identity],
      clock: { Date(timeIntervalSince1970: capturedAt) }
    )
    return try await adapter.captureAuthorized(
      NativeCaptureRequest(
        cellID: cellID,
        sourceTree: source,
        builtArtifact: artifact,
        captureProtocol: captureProtocol,
        expectedTraits: traits,
        navigationRecipe: Data(#"{"steps":["launch"]}"#.utf8),
        notBefore: Date(timeIntervalSince1970: capturedAt - 1),
        requiresComponentBoundaryTrace: true,
        requiresDesignTokenTrace: true
      ))
  }

  private func reviewAdapter(
    _ harness: StubIndependentVisualReviewHarness
  ) -> NativeIndependentVisualReviewAdapter {
    NativeIndependentVisualReviewAdapter(
      harness: harness,
      allowedHarnessIdentities: [harness.identity],
      clock: { Date(timeIntervalSince1970: 170) }
    )
  }

  private var executionProfile: KernelExecutionProfile {
    KernelExecutionProfile(
      schemaVersion: 1,
      worker: KernelAgentExecutionProfile(
        provider: .api,
        providerReference: "worker-provider",
        executableContentDigest: ContentDigest(String(repeating: "a", count: 64)),
        modelID: "worker-model",
        reasoningEffort: nil,
        sandbox: .workspaceOnly,
        networkPolicy: .disabled,
        pluginPolicy: .disabled,
        environmentPolicy: .minimalKernelAllowlist
      ),
      independentReviewer: KernelAgentExecutionProfile(
        provider: .api,
        providerReference: "fixture-provider",
        executableContentDigest: reviewerExecutableDigest,
        modelID: "fixture-model",
        reasoningEffort: "high",
        sandbox: .readOnly,
        networkPolicy: .disabled,
        pluginPolicy: .disabled,
        environmentPolicy: .minimalKernelAllowlist
      ),
      requiresDistinctActorLineage: true
    )
  }

  private var worker: ActorIdentity {
    ActorIdentity(
      id: ActorID("worker"),
      role: "worker",
      lineageDigest: ContentDigest("worker-lineage")
    )
  }

  private var reviewer: ActorIdentity {
    ActorIdentity(
      id: ActorID("reviewer"),
      role: "independentProductDesignReviewer",
      lineageDigest: ContentDigest("reviewer-lineage")
    )
  }

  private var visualEvaluator: ActorIdentity {
    ActorIdentity(
      id: ActorID("native-visual-gate"),
      role: "deterministicVisualGate",
      lineageDigest: ContentDigest("gate-lineage")
    )
  }

  private var measurement: VisualPairMeasurements {
    VisualPairMeasurements(
      cellID: cellID,
      evidenceReceiptIDs: [],
      productIdentityContinuous: true,
      primaryTaskWithinBoundary: true,
      typographyHierarchyInverted: false,
      maximumTypographyRatioDelta: 0.02,
      symmetricTitleLineCountDelta: 0,
      maximumAlignmentOffsetLineHeights: 0.1,
      maximumSpacingDeltaPoints: 0.5,
      maximumSpacingRelativeDelta: 0.02,
      contentOccupancyIncrease: 0.01,
      maximumShapeRatioDelta: 0.02,
      shapeContentFitPasses: true,
      undeclaredSemanticTokenCount: 0,
      newOcclusionPixels: 0,
      responsiveCompositionPasses: true,
      accessibilitySemanticsPasses: true,
      localizationQualityPasses: true,
      localizedCopyFitsSlot: true,
      perceptualDifference: 0.01
    )
  }

  private var measurableDimensions: Set<VisualGateDimension> {
    Set(
      VisualGateDimension.allCases.filter {
        $0 != .provenanceAndComparability
          && $0 != .independentProductDesignVerdict
      })
  }

  private var traits: VisualTraitSignature {
    VisualTraitSignature(
      deviceClass: "synthetic-desktop",
      viewportWidthPixels: 1,
      viewportHeightPixels: 1,
      scale: 1,
      operatingSystem: "synthetic-os-1",
      orientation: "landscape",
      locale: "en-US",
      calendar: "gregorian",
      layoutDirection: "left-to-right",
      appearance: "light",
      contrast: "standard",
      reducedMotion: false,
      boldText: false,
      contentSizeCategory: "large",
      fixtureDigest: ContentDigest(String(repeating: "9", count: 64))
    )
  }

  private var baselineSource: ContentDigest {
    ContentDigest(String(repeating: "1", count: 64))
  }
  private var baselineArtifact: ContentDigest {
    ContentDigest(String(repeating: "2", count: 64))
  }
  private var candidateSource: ContentDigest {
    ContentDigest(String(repeating: "3", count: 64))
  }
  private var candidateArtifact: ContentDigest {
    ContentDigest(String(repeating: "4", count: 64))
  }
  private var captureProtocol: ContentDigest {
    ContentDigest(String(repeating: "5", count: 64))
  }
  private var reviewerExecutableDigest: ContentDigest {
    ContentDigest(String(repeating: "f", count: 64))
  }
  private var cellID: VisualCellID { VisualCellID("cell-primary") }
  private var onePixelPNG: Data {
    Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
  }

  private func assertError(
    _ expected: NativeIndependentVisualReviewError,
    operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await operation()
      XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as NativeIndependentVisualReviewError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
  }
}

private enum StubReviewMode: Sendable {
  case pass
  case fail
  case incomplete
}

private actor StubIndependentVisualReviewHarness: NativeIndependentVisualReviewHarness {
  nonisolated let identity: String
  nonisolated let providerReference = "fixture-provider"
  nonisolated let modelID = "fixture-model"
  nonisolated let executableContentDigest = ContentDigest(String(repeating: "f", count: 64))
  nonisolated let reviewer: ActorIdentity
  let mode: StubReviewMode
  private(set) var invocationCount = 0

  init(identity: String, reviewer: ActorIdentity, mode: StubReviewMode) {
    self.identity = identity
    self.reviewer = reviewer
    self.mode = mode
  }

  func review(
    _ request: NativeIndependentVisualReviewHarnessRequest
  ) async throws -> NativeIndependentVisualReviewHarnessOutput {
    invocationCount += 1
    let baselineIDs = Set(request.imagePairs.map(\.baselineReceipt.id))
    let candidateIDs = Set(request.imagePairs.map(\.candidateReceipt.id))
    let allIDs = baselineIDs.union(candidateIDs)
    var imageDecisions = Dictionary(
      uniqueKeysWithValues:
        allIDs.map { ($0, VisualReviewDecision.pass) }
    )
    var pairDecisions = Dictionary(
      uniqueKeysWithValues:
        request.imagePairs.map { ($0.cellID, VisualReviewDecision.pass) }
    )
    var inspected = Set(request.imagePairs.map(\.cellID))
    switch mode {
    case .pass:
      break
    case .fail:
      if let candidate = candidateIDs.first { imageDecisions[candidate] = .fail }
      if let cell = inspected.first { pairDecisions[cell] = .fail }
    case .incomplete:
      imageDecisions.removeAll()
      inspected.removeAll()
    }
    return NativeIndependentVisualReviewHarnessOutput(
      perImageDecisions: imageDecisions,
      pairDecisions: pairDecisions,
      inspectedCellIDs: inspected,
      rawResponse: Data(#"{"review":"complete"}"#.utf8),
      processExitCode: 0
    )
  }
}

private actor StubReviewCaptureHarness: NativeCaptureHarness {
  nonisolated let identity: String
  let output: NativeCaptureHarnessOutput

  init(identity: String, output: NativeCaptureHarnessOutput) {
    self.identity = identity
    self.output = output
  }

  func capture(_ request: NativeCaptureRequest) async throws -> NativeCaptureHarnessOutput {
    output
  }
}

private actor StubReviewMeasurementHarness: NativeVisualMeasurementHarness {
  nonisolated let identity: String
  let output: NativeVisualMeasurementHarnessOutput

  init(identity: String, output: NativeVisualMeasurementHarnessOutput) {
    self.identity = identity
    self.output = output
  }

  func measure(
    _ request: NativeVisualMeasurementRequest
  ) async throws -> NativeVisualMeasurementHarnessOutput {
    output
  }
}
