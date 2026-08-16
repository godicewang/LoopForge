import Foundation
import XCTest
@testable import LoopForge

final class JournaledKernelCompletionCoordinatorTests: XCTestCase {
    func testExactCompletionHeadAuthorizesRecoversAndRetriesIdempotently() async throws {
        let fixture = try await makeFixture(includeQuiescence: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = JournaledKernelCompletionCoordinator(
            journal: fixture.journal,
            clock: { Date(timeIntervalSince1970: 40) }
        )

        let first = try await coordinator.authorize()
        XCTAssertEqual(first.kernelProjection.phase, .completed)
        XCTAssertEqual(first.journalTransaction.eventIDs.count, 2)
        XCTAssertFalse(first.journalTransaction.duplicate)
        XCTAssertEqual(
            first.kernelProjection.completionAuthorizationReceiptID,
            first.authorization.id
        )
        XCTAssertEqual(
            first.authorization.authorizer,
            KernelCompletionEvidenceCompiler.deterministicAuthorizer
        )

        let duplicate = try await coordinator.authorize()
        XCTAssertTrue(duplicate.journalTransaction.duplicate)
        XCTAssertEqual(duplicate.authorization, first.authorization)
        XCTAssertEqual(duplicate.kernelProjection.phase, .completed)

        let recovered = try RunJournal(
            rootDirectory: fixture.root,
            runID: fixture.runID
        )
        let recoveredAuthorization = await recovered.completionAuthorizationReceipt()
        XCTAssertEqual(recoveredAuthorization, first.authorization)
        let recoveredProjection = await recovered.currentProjection()
        XCTAssertEqual(recoveredProjection.phase, .completed)
        XCTAssertEqual(
            recoveredProjection.completionAuthorizationReceiptID,
            first.authorization.id
        )
    }

    func testExecutedRunWithoutTerminalQuiescenceCannotAuthorize() async throws {
        let fixture = try await makeFixture(includeQuiescence: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = await fixture.journal.headSnapshot()
        let coordinator = JournaledKernelCompletionCoordinator(
            journal: fixture.journal,
            clock: { Date(timeIntervalSince1970: 40) }
        )

        do {
            _ = try await coordinator.authorize()
            XCTFail("Expected terminal-quiescence veto")
        } catch let error as JournaledKernelCompletionError {
            guard case .invalidState(let issues) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(issues.contains {
                $0.contains("terminal quiescence")
            })
        }
        let after = await fixture.journal.headSnapshot()
        let authorization = await fixture.journal.completionAuthorizationReceipt()
        XCTAssertEqual(after, before)
        XCTAssertNil(authorization)
    }

    func testDeclaredExternalDependencyWithoutAvailableEvidenceVetoesFinalization() async throws {
        let fixture = try await makeFixture(
            includeQuiescence: true,
            includeExternalDependency: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = await fixture.journal.headSnapshot()

        do {
            _ = try await JournaledKernelCompletionCoordinator(
                journal: fixture.journal,
                clock: { Date(timeIntervalSince1970: 40) }
            ).authorize()
            XCTFail("Expected external-dependency evidence veto")
        } catch let error as JournaledKernelCompletionError {
            guard case .invalidState(let issues) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(issues.contains {
                $0.contains("external dependency")
            })
        }
        let after = await fixture.journal.headSnapshot()
        XCTAssertEqual(after, before)
    }

    func testPreservationRequiredBaselineWithoutFrozenAuthorityVetoesFinalization() async throws {
        let fixture = try await makeFixture(
            includeQuiescence: true,
            includeProtectedBaseline: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = await fixture.journal.headSnapshot()

        do {
            _ = try await JournaledKernelCompletionCoordinator(
                journal: fixture.journal,
                clock: { Date(timeIntervalSince1970: 40) }
            ).authorize()
            XCTFail("Expected missing frozen-baseline veto")
        } catch let error as JournaledKernelCompletionError {
            guard case .invalidState(let issues) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(issues.contains {
                $0.contains("frozen design authority")
            })
        }
        let after = await fixture.journal.headSnapshot()
        XCTAssertEqual(after, before)
    }

    func testTamperedCompletionEvidenceCannotAdvanceReplay() async throws {
        let source = try await makeFixture(includeQuiescence: true)
        defer { try? FileManager.default.removeItem(at: source.root) }
        let completed = try await JournaledKernelCompletionCoordinator(
            journal: source.journal,
            clock: { Date(timeIntervalSince1970: 40) }
        ).authorize()

        let target = try await makeFixture(includeQuiescence: true)
        defer { try? FileManager.default.removeItem(at: target.root) }
        let state = await target.journal.state
        var tampered = completed.authorization
        tampered.sourceEvidenceDigest = ContentDigest(
            String(repeating: "f", count: 64)
        )
        let event = OrchestrationEvent(
            id: OrchestrationEventID("tampered-completion"),
            runID: state.runID,
            sequence: state.sequence + 1,
            commandID: tampered.commandID,
            occurredAt: tampered.authorizedAt,
            payload: .completionAuthorizationRecorded(tampered)
        )

        XCTAssertEqual(RunReducer.reduce(state: state, event: event), state)
    }

    private struct Fixture {
        var root: URL
        var runID: KernelRunID
        var journal: RunJournal
    }

    private func makeFixture(
        includeQuiescence: Bool,
        includeExternalDependency: Bool = false,
        includeProtectedBaseline: Bool = false
    ) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "journaled-final-completion-\(UUID().uuidString)",
            isDirectory: true
        )
        let runID = KernelRunID("final-completion-run")
        let requirementID = RequirementID("requirement")
        let nodeID = KernelNodeID("node")
        let attemptID = AttemptID("attempt")
        let worker = ActorIdentity(
            id: ActorID("worker"),
            role: "worker",
            lineageDigest: ContentDigest("worker-lineage")
        )
        let reviewer = ActorIdentity(
            id: ActorID("reviewer"),
            role: "independentReviewer",
            lineageDigest: ContentDigest("reviewer-lineage")
        )
        let authority = ActorIdentity(
            id: ActorID("authority"),
            role: "taskAuthority",
            lineageDigest: ContentDigest("authority-lineage")
        )
        let strategy = CausalStrategyDescriptor(
            requirementIDs: [requirementID],
            hypothesisClass: "read-only-completion",
            actionClass: "observe-and-verify",
            workspaceTopology: "read-only-workspace",
            capabilityRoute: [],
            evidenceSources: ["typed-verification"],
            measurementBoundary: "requirement",
            verificationOracles: ["independent-review"],
            mutationSurfaceDigest: ContentDigest("read-only"),
            baselineRevision: ContentDigest("baseline"),
            expectedObservationIDs: ["verified"],
            falsificationPredicateIDs: ["not-verified"],
            inheritedLessonDigests: []
        )
        var contract = TaskContract(
            id: TaskContractID("contract"),
            schemaVersion: 1,
            verbatimObjective: "Complete one read-only verified requirement.",
            objectiveDigest: ContentDigest("objective"),
            requirements: [RequirementContract(
                id: requirementID,
                statement: "The observation must be independently verified.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("evidence")]
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: false
            ),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        if includeExternalDependency {
            contract.externalDependencies = [ExternalDependencyContract(
                id: ExternalDependencyID("dependency"),
                kind: .externalCondition,
                requirementIDs: [requirementID],
                evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe"),
                authorizedObserverLineageDigests: [reviewer.lineageDigest],
                executableProbe: externalDependencyObservationProbeFixture()
            )]
        }
        if includeProtectedBaseline {
            contract.protectedBaselines = [BaselineReference(
                id: BaselineID("protected-product"),
                artifactDigest: ContentDigest("protected-artifact"),
                environmentDigest: ContentDigest("protected-environment"),
                preservationRequired: true
            )]
        }
        let plan = KernelPlanProposal(
            contractDigest: contract.objectiveDigest,
            nodes: [KernelNodeContract(
                id: nodeID,
                requirementIDs: [requirementID],
                objective: "Observe without mutation.",
                dependencies: [],
                mutationScope: .readOnly,
                capabilityIDs: [],
                strategyFingerprint: strategy.fingerprint
            )]
        )
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        let setup: [(String, RunCommand, ActorIdentity, TimeInterval)] = [
            ("create", .createRun(contract), authority, 2),
            ("plan", .proposePlan(plan), worker, 3),
            ("authorize", .authorizeNode(nodeID), worker, 4),
            ("convergence", .initializeConvergence(
                epochID: "completion-epoch",
                budget: ConvergenceBudget(
                    maximumAttempts: 1,
                    maximumEquivalentFailures: 1,
                    maximumStrategies: 1,
                    maximumPlanExpansions: 0,
                    maximumMutationCost: 0,
                    maximumVerificationCost: 10,
                    maximumDamageEvents: 0,
                    maximumExternalEffects: 1
                )
            ), authority, 5),
            ("admit", .admitCausalAttempt(AttemptAdmissionRequest(
                attemptID: attemptID,
                strategy: strategy,
                predictedObservationIDs: ["verified"],
                falsificationPredicateIDs: ["not-verified"],
                rollbackPoint: ContentDigest("baseline"),
                mutationCost: 0,
                verificationCost: 1,
                externalEffects: 1
            )), authority, 6),
            ("start", .startAttempt(
                attemptID: attemptID,
                nodeID: nodeID,
                requirementIDs: [requirementID],
                strategyFingerprint: strategy.fingerprint
            ), worker, 7)
        ]
        for (id, command, actor, time) in setup {
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: RunCommandID(id),
                issuedAt: Date(timeIntervalSince1970: time),
                actor: actor
            )
        }
        try await journalTestWorkerDisposition(
            journal,
            runID: runID,
            attemptID: attemptID,
            actor: worker,
            prefix: "final-completion-worker",
            startingAt: 10
        )
        let sourceRevision = ContentDigest("candidate")
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordVerification(VerificationReceipt(
                id: ReceiptID("verification"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                sourceRevision: sourceRevision,
                environmentDigest: ContentDigest("environment"),
                oracleDigest: ContentDigest("oracle"),
                result: .accepted
            )),
            commandID: RunCommandID("verification"),
            issuedAt: Date(timeIntervalSince1970: 20),
            actor: reviewer
        )
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordReview(IndependentReviewReceipt(
                id: ReceiptID("review"),
                attemptID: attemptID,
                requirementIDs: [requirementID],
                reviewer: reviewer,
                evidenceDigest: ContentDigest("review-evidence"),
                sourceRevision: sourceRevision,
                decision: .approveCandidate
            )),
            commandID: RunCommandID("review"),
            issuedAt: Date(timeIntervalSince1970: 21),
            actor: reviewer
        )
        _ = try await journal.transactAtCurrentSequence(
            .requestCompletion,
            commandID: RunCommandID("request-completion"),
            issuedAt: Date(timeIntervalSince1970: 22),
            actor: worker
        )
        if includeQuiescence {
            _ = try await journal.transactAtCurrentSequence(
                .testOnlyRecordRuntimeDrain(RuntimeDrainReceipt(
                    id: ReceiptID("completion-drain"),
                    runID: runID,
                    snapshot: RuntimeDrainSnapshot(
                        intent: .complete,
                        liveResourceIDs: [],
                        cancelledQueuedLeaseIDs: []
                    ),
                    observedAt: Date(timeIntervalSince1970: 23),
                    observedAtMonotonicNanoseconds: 23
                )),
                commandID: RunCommandID("completion-drain"),
                issuedAt: Date(timeIntervalSince1970: 23),
                actor: authority
            )
            _ = try await journal.transactAtCurrentSequence(
                .testOnlyRecordQuiescence(QuiescenceReceipt(
                    id: ReceiptID("completion-quiescence"),
                    runID: runID,
                    intent: .complete,
                    observedAt: Date(timeIntervalSince1970: 24),
                    observedAtMonotonicNanoseconds: 24,
                    liveResources: [],
                    failedReleases: [],
                    queuedLeaseIDs: []
                )),
                commandID: RunCommandID("completion-quiescence"),
                issuedAt: Date(timeIntervalSince1970: 24),
                actor: authority
            )
        }
        return Fixture(root: root, runID: runID, journal: journal)
    }
}
