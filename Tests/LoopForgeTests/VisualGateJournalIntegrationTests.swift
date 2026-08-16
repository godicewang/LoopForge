import Foundation
import XCTest
@testable import LoopForge

final class VisualGateJournalIntegrationTests: XCTestCase {
    private enum FixtureError: Error {
        case reducerRejected(String)
    }
    private let runID = KernelRunID("visual-run")
    private let requirementID = RequirementID("visual-quality")
    private let nodeID = KernelNodeID("visual-node")
    private let attemptID = AttemptID("visual-attempt")
    private let cellID = VisualCellID("primary.standard.en.light")
    private let authority = ActorIdentity(
        id: ActorID("design-authority"),
        role: "productDesignAuthority",
        lineageDigest: ContentDigest("design-lineage")
    )
    private let worker = ActorIdentity(
        id: ActorID("worker"),
        role: "executor",
        lineageDigest: ContentDigest("worker-lineage")
    )
    private let reviewer = ActorIdentity(
        id: ActorID("reviewer"),
        role: "reviewer",
        lineageDigest: ContentDigest("reviewer-lineage")
    )
    private let evaluator = ActorIdentity(
        id: ActorID("visual-gate"),
        role: "deterministicVisualGate",
        lineageDigest: ContentDigest("gate-lineage")
    )

    func testBaselineMustBeAuthorityBoundToProtectedContractArtifact() throws {
        let created = try apply(
            .empty(runID: runID),
            .createRun(contract()),
            id: "create",
            actor: authority,
            at: 50
        )
        var mismatched = baseline()
        mismatched.builtArtifact = ContentDigest("unprotected-artifact")
        mismatched.captures[0].builtArtifact = mismatched.builtArtifact

        let decision = RunReducer.handle(
            state: created,
            command: .testOnlyFreezeDesignBaseline(mismatched),
            context: context("freeze", sequence: created.sequence, actor: authority, at: 110)
        )

        guard case .rejected(.invalidDesignBaseline(let reason)) = decision else {
            return XCTFail("Expected protected baseline mismatch")
        }
        XCTAssertTrue(reason.contains("preservation-required"))
        XCTAssertNil(created.designBaseline)
    }

    func testBaselineCannotBeFrozenAfterExecutionStarts() throws {
        var state = try createdState(freezeBaseline: false)
        state = try apply(state, .proposePlan(plan()), id: "plan", actor: worker, at: 120)
        state = try apply(state, .authorizeNode(nodeID), id: "authorize", actor: worker, at: 121)
        state = try prepareCausalAttempt(state, at: 121.25)
        state = try apply(
            state,
            .startAttempt(
                attemptID: attemptID,
                nodeID: nodeID,
                requirementIDs: [requirementID],
                strategyFingerprint: causalStrategy().fingerprint
            ),
            id: "start",
            actor: worker,
            at: 122
        )

        let decision = RunReducer.handle(
            state: state,
            command: .testOnlyFreezeDesignBaseline(baseline()),
            context: context("late-freeze", sequence: state.sequence, actor: authority, at: 123)
        )

        XCTAssertEqual(
            decision,
            .rejected(.invalidDesignBaseline(
                "baseline must be authority-recorded exactly once before execution"
            ))
        )
    }

    func testVerificationAndOrdinaryReviewCannotBypassMissingVisualGate() throws {
        let state = try evidenceApprovedState()

        XCTAssertEqual(state.verificationReceipts.count, 1)
        XCTAssertEqual(state.reviewReceipts.count, 1)
        XCTAssertEqual(state.acceptedRequirementIDs, [])
        XCTAssertEqual(state.nodes[nodeID]?.status, .awaitingVerification)
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .requestCompletion,
                context: context("complete", sequence: state.sequence, actor: worker, at: 240)
            ),
            .rejected(.evidenceIncomplete([requirementID]))
        )
    }

    func testRedVisualEvaluationIsDurableAndBlocksCompletion() throws {
        var state = try evidenceApprovedState()
        let redCandidate = candidate(typographyRatioDelta: 0.5, reviewID: "red-review")
        state = try apply(
            state,
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("red-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: redCandidate
            ),
            id: "evaluate-red",
            actor: evaluator,
            at: 230
        )

        let receipt = try XCTUnwrap(state.visualGateReceipts[ReceiptID("red-gate")])
        XCTAssertFalse(receipt.result.accepted)
        XCTAssertTrue(receipt.result.failingDimensions.contains(.typographyHierarchy))
        XCTAssertEqual(state.nodes[nodeID]?.status, .rejected)
        XCTAssertEqual(state.acceptedRequirementIDs, [])
        let projection = KernelRunProjection(state: state)
        XCTAssertEqual(projection.visualEvaluationCount, 1)
        XCTAssertEqual(projection.latestVisualAccepted, false)
        XCTAssertGreaterThan(projection.latestVisualFailingDimensionCount, 0)
    }

    func testGreenVisualEvaluationCompletesThreeWayAcceptanceIntersection() throws {
        var state = try evidenceApprovedState()
        let greenCandidate = candidate(reviewID: "green-review")
        state = try apply(
            state,
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("green-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: greenCandidate
            ),
            id: "evaluate-green",
            actor: evaluator,
            at: 230
        )

        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])
        XCTAssertEqual(state.nodes[nodeID]?.status, .accepted)
        XCTAssertEqual(KernelRunProjection(state: state).latestVisualAccepted, true)
        state = try apply(state, .requestCompletion, id: "complete", actor: worker, at: 240)
        XCTAssertEqual(state.phase, .completionRequested)
    }

    func testNewerRedVisualReceiptRevokesOlderGreenReceipt() throws {
        var state = try evidenceApprovedState()
        state = try apply(
            state,
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("older-green"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate(reviewID: "older-green-review")
            ),
            id: "older-green-command",
            actor: evaluator,
            at: 230
        )
        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])

        state = try apply(
            state,
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("newer-red"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate(typographyRatioDelta: 0.5, reviewID: "newer-red-review")
            ),
            id: "newer-red-command",
            actor: evaluator,
            at: 231
        )

        XCTAssertEqual(state.acceptedRequirementIDs, [])
        XCTAssertEqual(state.nodes[nodeID]?.status, .rejected)
        XCTAssertEqual(KernelRunProjection(state: state).latestVisualAccepted, false)
    }

    func testVisualReceiptCannotPairWithVerificationFromDifferentRevision() throws {
        var state = try evidenceApprovedState()
        state.verificationReceipts[ReceiptID("verification")]?.sourceRevision =
            ContentDigest("different-candidate-source")
        state = try apply(
            state,
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("revision-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate(reviewID: "revision-review")
            ),
            id: "revision-evaluate",
            actor: evaluator,
            at: 230
        )

        XCTAssertEqual(state.visualGateReceipts.values.first?.result.accepted, true)
        XCTAssertEqual(state.acceptedRequirementIDs, [])
        XCTAssertEqual(state.nodes[nodeID]?.status, .awaitingVerification)
    }

    func testMalformedVisualReplayEventCannotAdvanceReducer() throws {
        let state = try evidenceApprovedState()
        let candidate = candidate(reviewID: "event-review")
        let decision = RunReducer.handle(
            state: state,
            command: .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("event-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate
            ),
            context: context("event-command", sequence: state.sequence, actor: evaluator, at: 230)
        )
        guard case .accepted(let events, _) = decision,
              case .visualCandidateEvaluated(let recordedCandidate, var receipt) = events[0].payload else {
            return XCTFail("Expected visual evaluation event")
        }
        receipt.result.accepted.toggle()
        let malformed = OrchestrationEvent(
            id: events[0].id,
            runID: runID,
            sequence: state.sequence + 1,
            commandID: RunCommandID("malformed"),
            occurredAt: Date(timeIntervalSince1970: 230),
            payload: .visualCandidateEvaluated(candidate: recordedCandidate, receipt: receipt)
        )

        XCTAssertEqual(RunReducer.reduce(state: state, event: malformed), state)
    }

    func testJournalRecoveryRecomputesAndRestoresVisualDecision() async throws {
        let root = temporaryRoot("visual-recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        var journal: RunJournal? = try RunJournal(rootDirectory: root, runID: runID)
        try await buildJournalToEvidenceApproval(journal!)
        _ = try await journal!.transactAtCurrentSequence(
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("durable-red"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate(typographyRatioDelta: 0.5, reviewID: "durable-review")
            ),
            commandID: RunCommandID("durable-evaluate"),
            issuedAt: Date(timeIntervalSince1970: 230),
            actor: evaluator
        )
        journal = nil

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let state = await recovered.state
        let report = await recovered.recoveryReport
        XCTAssertEqual(state.visualGateReceipts.count, 1)
        XCTAssertEqual(state.visualGateReceipts.values.first?.result.accepted, false)
        XCTAssertNotNil(state.designBaseline)
        XCTAssertEqual(state.acceptedRequirementIDs, [])
        XCTAssertEqual(report.recoveredTransactions, 15)
    }

    func testDuplicateVisualCommandIsIdempotent() async throws {
        let root = temporaryRoot("visual-duplicate")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        try await buildJournalToEvidenceApproval(journal)
        let command = RunCommand.testOnlyEvaluateVisualCandidate(
            receiptID: ReceiptID("green-gate"),
            attemptID: attemptID,
            requirementIDs: [requirementID],
            candidate: candidate(reviewID: "green-review")
        )
        let first = try await journal.transactAtCurrentSequence(
            command,
            commandID: RunCommandID("evaluate-once"),
            issuedAt: Date(timeIntervalSince1970: 230),
            actor: evaluator
        )
        let duplicate = try await journal.transact(
            command,
            context: context("evaluate-once", sequence: 0, actor: evaluator, at: 999)
        )
        let state = await journal.state

        XCTAssertFalse(first.duplicate)
        XCTAssertTrue(duplicate.duplicate)
        XCTAssertEqual(state.visualGateReceipts.count, 1)
        XCTAssertEqual(state.sequence, first.endingSequence)
    }

    func testStaleJournalWriterCannotForkVisualVerdict() async throws {
        let root = temporaryRoot("visual-stale-writer")
        defer { try? FileManager.default.removeItem(at: root) }
        let current = try RunJournal(rootDirectory: root, runID: runID)
        try await buildJournalToEvidenceApproval(current)
        let stale = try RunJournal(rootDirectory: root, runID: runID)

        _ = try await current.transactAtCurrentSequence(
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("current-green"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate(reviewID: "current-review")
            ),
            commandID: RunCommandID("current-evaluate"),
            issuedAt: Date(timeIntervalSince1970: 230),
            actor: evaluator
        )
        do {
            _ = try await stale.transactAtCurrentSequence(
                .testOnlyEvaluateVisualCandidate(
                    receiptID: ReceiptID("stale-red"),
                    attemptID: attemptID,
                    requirementIDs: [requirementID],
                    candidate: candidate(typographyRatioDelta: 0.5, reviewID: "stale-review")
                ),
                commandID: RunCommandID("stale-evaluate"),
                issuedAt: Date(timeIntervalSince1970: 231),
                actor: evaluator
            )
            XCTFail("Expected stale writer rejection")
        } catch let error as RunJournalError {
            guard case .writerStale = error else { return XCTFail("Unexpected \(error)") }
        }

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let state = await recovered.state
        XCTAssertEqual(state.visualGateReceipts.count, 1)
        XCTAssertEqual(state.visualGateReceipts[ReceiptID("current-green")]?.result.accepted, true)
        XCTAssertNil(state.visualGateReceipts[ReceiptID("stale-red")])
    }

    func testVersionTwoJournalRejectsValidJSONEventByteTampering() async throws {
        let root = temporaryRoot("visual-byte-tamper")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        try await buildJournalToEvidenceApproval(journal)
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("tamper-target"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate(reviewID: "tamper-review")
            ),
            commandID: RunCommandID("tamper-evaluate"),
            issuedAt: Date(timeIntervalSince1970: 230),
            actor: evaluator
        )
        let journalURL = await journal.journalURL
        var lines = try String(contentsOf: journalURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        var frame = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[lines.count - 1].utf8))
                as? [String: Any]
        )
        let encoded = try XCTUnwrap(frame["encodedEvents"] as? String)
        let eventBytes = try XCTUnwrap(Data(base64Encoded: encoded))
        let eventText = try XCTUnwrap(String(data: eventBytes, encoding: .utf8))
        XCTAssertTrue(eventText.contains("candidate-source"))
        let tamperedText = eventText.replacingOccurrences(
            of: "candidate-source",
            with: "attacker--source"
        )
        XCTAssertEqual(tamperedText.utf8.count, eventText.utf8.count)
        frame["encodedEvents"] = Data(tamperedText.utf8).base64EncodedString()
        let rewritten = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys])
        lines[lines.count - 1] = try XCTUnwrap(String(data: rewritten, encoding: .utf8))
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: journalURL)

        XCTAssertThrowsError(try RunJournal(rootDirectory: root, runID: runID)) { error in
            XCTAssertEqual(error as? RunJournalError, .brokenHashChain(line: 15))
        }
    }

    func testIndependentReviewReceiptCannotAuthorizeTwoCandidates() throws {
        var state = try evidenceApprovedState()
        let candidate = candidate(reviewID: "single-review")
        state = try apply(
            state,
            .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("first-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate
            ),
            id: "first-evaluate",
            actor: evaluator,
            at: 230
        )

        let decision = RunReducer.handle(
            state: state,
            command: .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("second-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: candidate
            ),
            context: context("second-evaluate", sequence: state.sequence, actor: evaluator, at: 231)
        )
        XCTAssertEqual(
            decision,
            .rejected(.invalidVisualEvaluation(
                "independent review receipt cannot authorize multiple candidates"
            ))
        )
    }

    func testVisualReviewerCannotForgeWorkerLineageToSelfApprove() throws {
        let state = try evidenceApprovedState()
        var forged = candidate(reviewID: "forged-self-review")
        forged.independentReview?.reviewer = worker
        forged.independentReview?.workerLineageDigest = ContentDigest("invented-worker-lineage")

        let decision = RunReducer.handle(
            state: state,
            command: .testOnlyEvaluateVisualCandidate(
                receiptID: ReceiptID("forged-gate"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                candidate: forged
            ),
            context: context("forged-evaluate", sequence: state.sequence, actor: evaluator, at: 230)
        )
        XCTAssertEqual(
            decision,
            .rejected(.invalidVisualEvaluation(
                "independent visual review lineage does not match the actual worker"
            ))
        )
    }

    private func createdState(freezeBaseline: Bool = true) throws -> KernelRunState {
        var state = try apply(
            .empty(runID: runID),
            .createRun(contract()),
            id: "create",
            actor: authority,
            at: 50
        )
        if freezeBaseline {
            state = try apply(
                state,
                .testOnlyFreezeDesignBaseline(baseline()),
                id: "freeze",
                actor: authority,
                at: 110
            )
        }
        return state
    }

    private func evidenceApprovedState() throws -> KernelRunState {
        var state = try createdState()
        state = try apply(state, .proposePlan(plan()), id: "plan", actor: worker, at: 120)
        state = try apply(state, .authorizeNode(nodeID), id: "authorize", actor: worker, at: 121)
        state = try prepareCausalAttempt(state, at: 121.25)
        state = try apply(
            state,
            .startAttempt(
                attemptID: attemptID,
                nodeID: nodeID,
                requirementIDs: [requirementID],
                strategyFingerprint: causalStrategy().fingerprint
            ),
            id: "start",
            actor: worker,
            at: 122
        )
        state = RunReducer.reduce(
            state: state,
            event: OrchestrationEvent(
                id: OrchestrationEventID("legacy-execution.\(state.sequence + 1)"),
                runID: runID,
                sequence: state.sequence + 1,
                commandID: RunCommandID("legacy-execution"),
                occurredAt: Date(timeIntervalSince1970: 200),
                payload: .executionRecorded(attemptID: attemptID, disposition: .completed)
            )
        )
        state = try apply(
            state,
            .testOnlyRecordVerification(VerificationReceipt(
                id: ReceiptID("verification"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                sourceRevision: ContentDigest("candidate-source"),
                environmentDigest: ContentDigest("environment"),
                oracleDigest: ContentDigest("oracle"),
                result: .accepted
            )),
            id: "verification-command",
            actor: reviewer,
            at: 210
        )
        state = try apply(
            state,
            .testOnlyRecordReview(IndependentReviewReceipt(
                id: ReceiptID("ordinary-review"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                reviewer: reviewer,
                evidenceDigest: ContentDigest("ordinary-evidence"),
                sourceRevision: ContentDigest("candidate-source"),
                decision: .approveCandidate
            )),
            id: "ordinary-review-command",
            actor: reviewer,
            at: 220
        )
        return state
    }

    private func buildJournalToEvidenceApproval(_ journal: RunJournal) async throws {
        let setupCommands: [(RunCommandID, RunCommand, ActorIdentity, TimeInterval)] = [
            (RunCommandID("create"), .createRun(contract()), authority, 50),
            (RunCommandID("freeze"), .testOnlyFreezeDesignBaseline(baseline()), authority, 110),
            (RunCommandID("plan"), .proposePlan(plan()), worker, 120),
            (RunCommandID("authorize"), .authorizeNode(nodeID), worker, 121),
            (RunCommandID("initialize-convergence"), .initializeConvergence(
                epochID: "visual-epoch",
                budget: convergenceBudget()
            ), authority, 121.25),
            (RunCommandID("admit-attempt"), .admitCausalAttempt(causalAdmission()), authority, 121.5),
            (RunCommandID("start"), .startAttempt(
                attemptID: attemptID,
                nodeID: nodeID,
                requirementIDs: [requirementID],
                strategyFingerprint: causalStrategy().fingerprint
            ), worker, 122)
        ]
        for (id, command, actor, time) in setupCommands {
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: id,
                issuedAt: Date(timeIntervalSince1970: time),
                actor: actor
            )
        }
        try await journalTestWorkerDisposition(
            journal,
            runID: runID,
            attemptID: attemptID,
            actor: worker,
            prefix: "visual-evidence",
            startingAt: 200
        )
        let evidenceCommands: [(RunCommandID, RunCommand, ActorIdentity, TimeInterval)] = [
            (RunCommandID("verification-command"), .testOnlyRecordVerification(VerificationReceipt(
                id: ReceiptID("verification"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                sourceRevision: ContentDigest("candidate-source"),
                environmentDigest: ContentDigest("environment"),
                oracleDigest: ContentDigest("oracle"),
                result: .accepted
            )), reviewer, 210),
            (RunCommandID("ordinary-review-command"), .testOnlyRecordReview(IndependentReviewReceipt(
                id: ReceiptID("ordinary-review"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                reviewer: reviewer,
                evidenceDigest: ContentDigest("ordinary-evidence"),
                sourceRevision: ContentDigest("candidate-source"),
                decision: .approveCandidate
            )), reviewer, 220)
        ]
        for (id, command, actor, time) in evidenceCommands {
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: id,
                issuedAt: Date(timeIntervalSince1970: time),
                actor: actor
            )
        }
    }

    private func contract() -> TaskContract {
        TaskContract(
            id: TaskContractID("contract"),
            schemaVersion: 1,
            verbatimObjective: "Preserve the protected visual contract.",
            objectiveDigest: ContentDigest("objective"),
            requirements: [RequirementContract(
                id: requirementID,
                statement: "Visual quality must not regress.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("visual-evidence")]
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [BaselineReference(
                id: BaselineID("protected-design"),
                artifactDigest: ContentDigest("baseline-artifact"),
                environmentDigest: ContentDigest("baseline-environment"),
                preservationRequired: true
            )],
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
            createdAt: Date(timeIntervalSince1970: 40)
        )
    }

    private func plan() -> KernelPlanProposal {
        KernelPlanProposal(
            contractDigest: ContentDigest("objective"),
            nodes: [KernelNodeContract(
                id: nodeID,
                requirementIDs: [requirementID],
                objective: "Produce a visually safe candidate.",
                dependencies: [],
                mutationScope: KernelMutationScope(
                    writablePaths: ["Sources"],
                    maximumChangedFiles: 2,
                    maximumChangedBytes: 10_000
                ),
                capabilityIDs: ["native-capture"],
                strategyFingerprint: causalStrategy().fingerprint
            )]
        )
    }

    private func causalStrategy() -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [requirementID],
            hypothesisClass: "preserve-visual-baseline",
            actionClass: "produce-visual-candidate",
            workspaceTopology: "bounded-source-workspace",
            capabilityRoute: ["native-capture"],
            evidenceSources: ["native-before-after-capture"],
            measurementBoundary: "visual-cell",
            verificationOracles: ["deterministic-visual-gate", "independent-review"],
            mutationSurfaceDigest: ContentDigest("sources-scope"),
            baselineRevision: ContentDigest("baseline-source"),
            expectedObservationIDs: ["candidate-compared"],
            falsificationPredicateIDs: ["visual-regression"],
            inheritedLessonDigests: []
        )
    }

    private func convergenceBudget() -> ConvergenceBudget {
        ConvergenceBudget(
            maximumAttempts: 2,
            maximumEquivalentFailures: 2,
            maximumStrategies: 2,
            maximumPlanExpansions: 1,
            maximumMutationCost: 10_000,
            maximumVerificationCost: 10_000,
            maximumDamageEvents: 1,
            maximumExternalEffects: 2
        )
    }

    private func causalAdmission() -> AttemptAdmissionRequest {
        AttemptAdmissionRequest(
            attemptID: attemptID,
            strategy: causalStrategy(),
            predictedObservationIDs: ["candidate-compared"],
            falsificationPredicateIDs: ["visual-regression"],
            rollbackPoint: ContentDigest("baseline-source"),
            mutationCost: 2,
            verificationCost: 2,
            externalEffects: 1
        )
    }

    private func prepareCausalAttempt(
        _ input: KernelRunState,
        at: TimeInterval
    ) throws -> KernelRunState {
        var state = try apply(
            input,
            .initializeConvergence(epochID: "visual-epoch", budget: convergenceBudget()),
            id: "initialize-convergence",
            actor: authority,
            at: at
        )
        state = try apply(
            state,
            .admitCausalAttempt(causalAdmission()),
            id: "admit-attempt",
            actor: authority,
            at: at + 0.25
        )
        return state
    }

    private func baseline() -> DesignBaselineBundle {
        let dimensions = VisualGateDimension.allCases.filter {
            $0 != .provenanceAndComparability
                && $0 != .independentProductDesignVerdict
        }
        return DesignBaselineBundle(
            id: DesignBaselineID("design-baseline"),
            contractID: TaskContractID("contract"),
            protectedBaselineID: BaselineID("protected-design"),
            requirementIDs: [requirementID],
            sourceTree: ContentDigest("baseline-source"),
            builtArtifact: ContentDigest("baseline-artifact"),
            captureProtocol: ContentDigest("native-capture-v1"),
            designTokenSnapshot: ContentDigest("tokens-v1"),
            semanticSurfaceManifest: ContentDigest("surfaces-v1"),
            captures: [capture(baseline: true)],
            protectedInvariants: dimensions.map {
                DesignInvariant(id: "invariant-\($0.rawValue)", dimension: $0, cellIDs: [cellID])
            },
            knownDebt: [],
            authority: DesignAuthorityReceipt(
                id: ReceiptID("baseline-authority"),
                baselineID: DesignBaselineID("design-baseline"),
                authority: authority,
                authorityRole: "productDesignAuthority",
                issuedAt: Date(timeIntervalSince1970: 90)
            ),
            frozenAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func candidate(
        typographyRatioDelta: Double = 0.02,
        reviewID: String
    ) -> VisualCandidateBundle {
        let candidateCapture = capture(baseline: false)
        let batch = VisualReviewBatchReceipt(
            id: ReceiptID("batch-\(reviewID)"),
            candidateCaptureIDs: [candidateCapture.id],
            verdictRecordedCaptureIDs: [candidateCapture.id]
        )
        var candidate = VisualCandidateBundle(
            sourceTree: ContentDigest("candidate-source"),
            builtArtifact: ContentDigest("candidate-artifact"),
            mutationStartedAt: Date(timeIntervalSince1970: 150),
            captures: [candidateCapture],
            measurements: [measurement(typographyRatioDelta: typographyRatioDelta)],
            mutationManifest: VisualMutationManifest(
                directlyAffectedCellIDs: [cellID],
                allBaselineCellIDs: [cellID],
                globalSemanticTokenMutation: false,
                touchedTokenFamilies: []
            ),
            debtSeverityByID: [:],
            reviewBatches: [batch],
            independentReview: nil,
            amendments: []
        )
        let digest = DesignBaselineGate.deterministicEvidenceDigest(
            baseline: baseline(),
            candidate: candidate
        )
        let baselineCaptureID = NativeCaptureID("baseline-\(cellID.rawValue)")
        candidate.independentReview = IndependentVisualReviewReceipt(
            id: ReceiptID(reviewID),
            reviewer: reviewer,
            workerLineageDigest: worker.lineageDigest,
            provider: "fixture-provider",
            model: "fixture-model",
            contextDigest: ContentDigest("context-\(reviewID)"),
            systemPromptDigest: ContentDigest("system-\(reviewID)"),
            userPromptDigest: ContentDigest("user-\(reviewID)"),
            evidenceBundleDigest: ContentDigest("bundle-\(reviewID)"),
            deterministicResultsDigest: digest,
            baselineID: DesignBaselineID("design-baseline"),
            candidateSourceTree: ContentDigest("candidate-source"),
            baselineCaptureIDs: [baselineCaptureID],
            candidateCaptureIDs: [candidateCapture.id],
            attachedImageDigests: [
                ContentDigest("baseline-image"),
                ContentDigest("candidate-image")
            ],
            perImageDecisions: [
                baselineCaptureID: .pass,
                candidateCapture.id: .pass
            ],
            pairDecisions: [cellID: .pass],
            inspectedCellIDs: [cellID],
            batchReceiptIDs: [batch.id],
            blindToWorkerNarrative: true,
            decision: .pass,
            rawResponseDigest: ContentDigest("response-\(reviewID)")
        )
        return candidate
    }

    private func capture(baseline: Bool) -> NativeCaptureReceipt {
        NativeCaptureReceipt(
            id: NativeCaptureID("\(baseline ? "baseline" : "candidate")-\(cellID.rawValue)"),
            cellID: cellID,
            sourceTree: ContentDigest(baseline ? "baseline-source" : "candidate-source"),
            builtArtifact: ContentDigest(baseline ? "baseline-artifact" : "candidate-artifact"),
            captureProtocol: ContentDigest("native-capture-v1"),
            traits: VisualTraitSignature(
                deviceClass: "standard",
                viewportWidthPixels: 1200,
                viewportHeightPixels: 900,
                scale: 2,
                operatingSystem: "fixture-os",
                orientation: "landscape",
                locale: "en",
                calendar: "gregorian",
                layoutDirection: "leftToRight",
                appearance: "light",
                contrast: "normal",
                reducedMotion: false,
                boldText: false,
                contentSizeCategory: "large",
                fixtureDigest: ContentDigest("fixture")
            ),
            imageDigest: ContentDigest(baseline ? "baseline-image" : "candidate-image"),
            accessibilityTreeDigest: ContentDigest(baseline ? "baseline-ax" : "candidate-ax"),
            navigationRecipeDigest: ContentDigest("navigation"),
            componentBoundaryDigest: ContentDigest("components"),
            designTokenTraceDigest: ContentDigest("token-trace"),
            imageWidthPixels: 1200,
            imageHeightPixels: 900,
            fullViewport: true,
            cleanInstall: true,
            harnessIdentity: "native-fixture",
            processExitCode: 0,
            capturedAt: Date(timeIntervalSince1970: baseline ? 95 : 160)
        )
    }

    private func measurement(typographyRatioDelta: Double) -> VisualPairMeasurements {
        VisualPairMeasurements(
            cellID: cellID,
            evidenceReceiptIDs: [ReceiptID("geometry")],
            productIdentityContinuous: true,
            primaryTaskWithinBoundary: true,
            typographyHierarchyInverted: false,
            maximumTypographyRatioDelta: typographyRatioDelta,
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
            perceptualDifference: 0.02
        )
    }

    private func apply(
        _ state: KernelRunState,
        _ command: RunCommand,
        id: String,
        actor: ActorIdentity,
        at: TimeInterval
    ) throws -> KernelRunState {
        let decision = RunReducer.handle(
            state: state,
            command: command,
            context: context(id, sequence: state.sequence, actor: actor, at: at)
        )
        guard case .accepted(_, let next) = decision else {
            XCTFail("Unexpected reducer rejection: \(decision)")
            throw FixtureError.reducerRejected(String(describing: decision))
        }
        return next
    }

    private func context(
        _ id: String,
        sequence: UInt64,
        actor: ActorIdentity,
        at: TimeInterval
    ) -> KernelCommandContext {
        KernelCommandContext(
            commandID: RunCommandID(id),
            expectedSequence: sequence,
            issuedAt: Date(timeIntervalSince1970: at),
            actor: actor
        )
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loopforge-\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
