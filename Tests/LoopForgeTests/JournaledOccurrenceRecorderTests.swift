import Foundation
import XCTest
@testable import LoopForge

final class JournaledOccurrenceRecorderTests: XCTestCase {
    private let runID = KernelRunID("occurrence-recorder-run")
    private let actor = ActorIdentity(
        id: ActorID("occurrence-recorder"),
        role: "runtime",
        lineageDigest: ContentDigest("occurrence-recorder-lineage")
    )

    func testRecorderOwnsClockDispositionSleepDetectionAndSingleUseToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-JournaledOccurrenceRecorder-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        var journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transactAtCurrentSequence(
            .createRun(durationContract()),
            commandID: RunCommandID("create"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(epochID: "epoch", budget: convergenceBudget()),
            commandID: RunCommandID("initialize"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        let strategy = causalStrategy()
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest(strategy)),
            commandID: RunCommandID("admit"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .recordCausalProgress(
                strategy: strategy.fingerprint,
                previous: progress(unresolved: [RequirementID("requirement")]),
                current: progress(accepted: [RequirementID("requirement")])
            ),
            commandID: RunCommandID("accepted-progress"),
            issuedAt: Date(timeIntervalSince1970: 4),
            actor: actor
        )

        let boot = BootSessionID("boot-a")
        let samples = SampleClock(samples: [
            OccurrenceClockSample(
                bootSessionID: boot,
                monotonicNanoseconds: 0,
                wallTime: Date(timeIntervalSince1970: 10)
            ),
            OccurrenceClockSample(
                bootSessionID: boot,
                monotonicNanoseconds: 5_000_000_000,
                wallTime: Date(timeIntervalSince1970: 15)
            ),
            OccurrenceClockSample(
                bootSessionID: boot,
                monotonicNanoseconds: 5_000_000_000,
                wallTime: Date(timeIntervalSince1970: 15)
            ),
            OccurrenceClockSample(
                bootSessionID: boot,
                monotonicNanoseconds: 10_000_000_000,
                wallTime: Date(timeIntervalSince1970: 30)
            )
        ])
        let recorder = JournaledOccurrenceRecorder(
            journal: journal,
            actorIdentity: actor,
            clock: { samples.next() }
        )

        let first = try await recorder.begin(
            occurrenceID: OccurrenceID("scheduled-1"),
            invocation: .scheduled(scheduleID: ScheduleID("schedule"), ordinal: 1)
        )
        let firstReceipt = try await recorder.close(
            first,
            outcome: .succeeded,
            evidenceReceiptIDs: [ReceiptID("accepted-progress")],
            progressReceiptID: ReceiptID("accepted-progress"),
            receiptID: ReceiptID("occurrence-receipt-1"),
            commandID: RunCommandID("record-occurrence-1")
        )
        XCTAssertEqual(firstReceipt.occurrence.intervalDisposition, .acceptedScheduled)
        XCTAssertEqual(firstReceipt.occurrence.clock.elapsedNanoseconds, 5_000_000_000)
        XCTAssertTrue(firstReceipt.occurrence.clock.discontinuities.isEmpty)

        do {
            _ = try await recorder.close(
                first,
                outcome: .succeeded,
                evidenceReceiptIDs: [ReceiptID("accepted-progress")],
                progressReceiptID: ReceiptID("accepted-progress"),
                receiptID: ReceiptID("forged-reuse"),
                commandID: RunCommandID("forged-reuse")
            )
            XCTFail("A consumed in-memory capability must not close twice")
        } catch {
            XCTAssertEqual(
                error as? JournaledOccurrenceRecorderError,
                .unknownOrConsumedToken
            )
        }

        let second = try await recorder.begin(
            occurrenceID: OccurrenceID("scheduled-2"),
            invocation: .scheduled(scheduleID: ScheduleID("schedule"), ordinal: 2)
        )
        let secondReceipt = try await recorder.close(
            second,
            outcome: .succeeded,
            evidenceReceiptIDs: [ReceiptID("accepted-progress")],
            progressReceiptID: ReceiptID("accepted-progress"),
            receiptID: ReceiptID("occurrence-receipt-2"),
            commandID: RunCommandID("record-occurrence-2")
        )
        XCTAssertEqual(secondReceipt.occurrence.intervalDisposition, .acceptedScheduled)
        XCTAssertEqual(secondReceipt.occurrence.clock.discontinuities, [.sleep])
        let openOccurrenceCount = await recorder.openOccurrenceCount()
        XCTAssertEqual(openOccurrenceCount, 0)

        let liveCoverageSnapshot = await journal.currentDurationCoverage()
        let liveCoverage = try XCTUnwrap(liveCoverageSnapshot)
        XCTAssertEqual(liveCoverage.cumulativeAcceptedSeconds, 5)
        XCTAssertEqual(liveCoverage.excludedSecondsByReason[.excludedSleep], 5)

        journal = try RunJournal(rootDirectory: root, runID: runID)
        let replayedCoverageSnapshot = await journal.currentDurationCoverage()
        let replayedCoverage = try XCTUnwrap(replayedCoverageSnapshot)
        XCTAssertEqual(replayedCoverage, liveCoverage)
    }

    private func durationContract() -> TaskContract {
        TaskContract(
            id: TaskContractID("occurrence-recorder-contract"),
            schemaVersion: 1,
            verbatimObjective: "Count only clock-owned accepted execution.",
            objectiveDigest: ContentDigest("occurrence-recorder-objective"),
            requirements: [],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: DurationAcceptancePolicy(
                    requiredSeconds: 5,
                    eligibleClass: .acceptedScheduledExecution
                ),
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func convergenceBudget() -> ConvergenceBudget {
        ConvergenceBudget(
            maximumAttempts: 2,
            maximumEquivalentFailures: 2,
            maximumStrategies: 2,
            maximumPlanExpansions: 1,
            maximumMutationCost: 2,
            maximumVerificationCost: 2,
            maximumDamageEvents: 0,
            maximumExternalEffects: 0
        )
    }

    private func causalStrategy() -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [RequirementID("requirement")],
            hypothesisClass: "repair",
            actionClass: "act",
            workspaceTopology: "isolated",
            capabilityRoute: ["shell"],
            evidenceSources: ["deterministic"],
            measurementBoundary: "before-after",
            verificationOracles: ["oracle"],
            mutationSurfaceDigest: ContentDigest("surface"),
            baselineRevision: ContentDigest("baseline"),
            expectedObservationIDs: ["passes"],
            falsificationPredicateIDs: ["fails"],
            inheritedLessonDigests: []
        )
    }

    private func causalRequest(
        _ strategy: CausalStrategyDescriptor
    ) -> AttemptAdmissionRequest {
        AttemptAdmissionRequest(
            attemptID: AttemptID("attempt"),
            strategy: strategy,
            predictedObservationIDs: strategy.expectedObservationIDs,
            falsificationPredicateIDs: strategy.falsificationPredicateIDs,
            rollbackPoint: ContentDigest("rollback"),
            mutationCost: 1,
            verificationCost: 1,
            externalEffects: 0
        )
    }

    private func progress(
        accepted: Set<RequirementID> = [],
        unresolved: Set<RequirementID> = []
    ) -> ConvergenceProgressVector {
        ConvergenceProgressVector(
            acceptedRequirements: accepted,
            unresolvedRequirements: unresolved,
            blockerDigests: [],
            acceptedEvidence: [],
            unresolvedVerifierFailures: [],
            acceptedQualityDimensions: [],
            unresolvedClaims: [],
            protectedInvariantRegressions: []
        )
    }
}

private final class SampleClock: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [OccurrenceClockSample]

    init(samples: [OccurrenceClockSample]) {
        self.samples = samples
    }

    func next() -> OccurrenceClockSample {
        lock.lock()
        defer { lock.unlock() }
        precondition(!samples.isEmpty, "test clock exhausted")
        return samples.removeFirst()
    }
}
