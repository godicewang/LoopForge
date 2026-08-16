import Foundation
import XCTest
@testable import LoopForge

final class IntervalLedgerTests: XCTestCase {
    private let boot = BootSessionID("boot-a")
    private let schedule = ScheduleID("schedule-a")

    func testProjectionSeparatesAllAcceptedRoundsFromCurrentLiveRound() {
        let closed = [
            receipt("one", ordinal: 1, start: 1, end: 4),
            receipt("two", ordinal: 2, start: 5, end: 10)
        ]
        let live = LiveAttemptInterval(
            occurrenceID: OccurrenceID("live"),
            invocation: .scheduled(scheduleID: schedule, ordinal: 3),
            bootSessionID: boot,
            retainedEligibleNanoseconds: seconds(2),
            liveSegmentStartedAtNanoseconds: seconds(20),
            provisionalDisposition: .acceptedScheduled,
            hasOwnedExecution: true
        )

        let result = IntervalLedger.project(
            receipts: closed,
            policy: scheduledPolicy(tolerance: 2),
            acceptedProgressReceiptIDs: progressIDs(closed),
            liveAttempt: live,
            currentBootSessionID: boot,
            currentMonotonicNanoseconds: seconds(24)
        )

        XCTAssertEqual(result.cumulativeAcceptedSeconds, 8)
        XCTAssertEqual(result.currentAttemptSeconds, 6)
        XCTAssertEqual(result.currentLiveSegmentSeconds, 4)
        XCTAssertEqual(result.rawClosedSeconds, 8)
        XCTAssertTrue(result.isLiveTimerAdvancing)
        XCTAssertEqual(result.contributions.count, 2)
    }

    func testPausedLiveAttemptKeepsRetainedTimeWithoutAnimating() {
        let live = LiveAttemptInterval(
            occurrenceID: OccurrenceID("paused"),
            invocation: .scheduled(scheduleID: schedule, ordinal: 1),
            bootSessionID: boot,
            retainedEligibleNanoseconds: seconds(7),
            liveSegmentStartedAtNanoseconds: nil,
            provisionalDisposition: .acceptedScheduled,
            hasOwnedExecution: true
        )
        let result = IntervalLedger.project(
            receipts: [],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: [],
            liveAttempt: live,
            currentBootSessionID: boot,
            currentMonotonicNanoseconds: seconds(100)
        )
        XCTAssertEqual(result.currentAttemptSeconds, 7)
        XCTAssertEqual(result.currentLiveSegmentSeconds, 0)
        XCTAssertFalse(result.isLiveTimerAdvancing)
    }

    func testBootBoundaryStopsLiveTimerAndDoesNotInventOfflineTime() {
        let live = LiveAttemptInterval(
            occurrenceID: OccurrenceID("old-boot"),
            invocation: .scheduled(scheduleID: schedule, ordinal: 1),
            bootSessionID: boot,
            retainedEligibleNanoseconds: seconds(3),
            liveSegmentStartedAtNanoseconds: seconds(10),
            provisionalDisposition: .acceptedScheduled,
            hasOwnedExecution: true
        )
        let result = IntervalLedger.project(
            receipts: [],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: [],
            liveAttempt: live,
            currentBootSessionID: BootSessionID("boot-b"),
            currentMonotonicNanoseconds: seconds(10_000)
        )
        XCTAssertEqual(result.currentAttemptSeconds, 3)
        XCTAssertFalse(result.isLiveTimerAdvancing)
        XCTAssertEqual(result.violations, [.invalidMonotonicInterval])
    }

    func testManualWorkCannotSatisfyScheduledCoverage() {
        let manual = receipt(
            "manual",
            invocation: .manual(ownerCommandID: RunCommandID("owner")),
            start: 1,
            end: 6,
            disposition: .acceptedInteractive
        )
        let result = IntervalLedger.project(
            receipts: [manual],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs([manual])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedManual], 5)
        XCTAssertEqual(result.violations, [.dispositionContradictsPolicy])
    }

    func testInteractivePolicyAcceptsManualExecution() {
        let manual = receipt(
            "manual",
            invocation: .manual(ownerCommandID: RunCommandID("owner")),
            start: 1,
            end: 6,
            disposition: .acceptedInteractive
        )
        let result = IntervalLedger.project(
            receipts: [manual],
            policy: CoveragePolicy(
                eligibleClass: .acceptedInteractiveExecution,
                continuityToleranceNanoseconds: 0
            ),
            acceptedProgressReceiptIDs: progressIDs([manual])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 5)
        XCTAssertEqual(result.continuitySegmentCount, 1)
    }

    func testRecoveryVerificationAndReviewNeverBecomeAcceptedExecution() {
        let receipts = [
            receipt(
                "recovery",
                invocation: .recovery(predecessor: nil),
                start: 1,
                end: 2,
                disposition: .acceptedScheduled
            ),
            receipt(
                "verify",
                invocation: .verification(requirementIDs: [RequirementID("r")]),
                start: 2,
                end: 3,
                disposition: .acceptedInteractive
            ),
            receipt(
                "review",
                invocation: .adaptiveReview(triggerID: "trigger"),
                start: 3,
                end: 4,
                disposition: .acceptedScheduled
            )
        ]
        let result = IntervalLedger.project(
            receipts: receipts,
            policy: CoveragePolicy(
                eligibleClass: .acceptedExecution,
                continuityToleranceNanoseconds: 0
            ),
            acceptedProgressReceiptIDs: progressIDs(receipts)
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.excludedClosedSeconds, 3)
        XCTAssertEqual(
            result.violations,
            Array(repeating: .dispositionContradictsInvocation, count: 3)
        )
    }

    func testFailureCancellationAndBlockUseTypedExclusions() {
        let receipts = [
            receipt("failed", ordinal: 1, start: 1, end: 3, outcome: .failed),
            receipt("cancelled", ordinal: 2, start: 3, end: 7, outcome: .cancelled),
            receipt("blocked", ordinal: 3, start: 7, end: 12, outcome: .blocked)
        ]
        let result = IntervalLedger.project(
            receipts: receipts,
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs(receipts)
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedFailure], 2)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedCancelled], 4)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedBlocked], 5)
        XCTAssertEqual(result.violations.count, 3)
    }

    func testSleepAndRebootDiscontinuitiesAreExcluded() {
        let asleep = receipt(
            "sleep",
            ordinal: 1,
            start: 1,
            end: 11,
            discontinuities: [.sleep]
        )
        let rebooted = receipt(
            "reboot",
            ordinal: 2,
            start: 12,
            end: 20,
            discontinuities: [.reboot]
        )
        let result = IntervalLedger.project(
            receipts: [asleep, rebooted],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs([asleep, rebooted])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedSleep], 10)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedDowntime], 8)
    }

    func testWallClockShiftDoesNotAlterMonotonicElapsed() {
        var shifted = receipt(
            "shifted",
            ordinal: 1,
            start: 1,
            end: 4,
            discontinuities: [.wallClockShift]
        )
        shifted.clock.wallEnd = shifted.clock.wallStart.addingTimeInterval(-3_600)
        let result = IntervalLedger.project(
            receipts: [shifted],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs([shifted])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 3)
        XCTAssertEqual(result.violations, [])
    }

    func testGapAndMissingOrdinalSplitContinuityWithoutFabricatingDuration() {
        let receipts = [
            receipt("one", ordinal: 1, start: 1, end: 2),
            receipt("two", ordinal: 2, start: 20, end: 22),
            receipt("four", ordinal: 4, start: 23, end: 26)
        ]
        let result = IntervalLedger.project(
            receipts: receipts,
            policy: scheduledPolicy(tolerance: 5),
            acceptedProgressReceiptIDs: progressIDs(receipts)
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 6)
        XCTAssertEqual(result.rawClosedSeconds, 6)
        XCTAssertEqual(result.continuitySegmentCount, 3)
        XCTAssertEqual(result.contributions.map(\.continuitySegment), [1, 2, 3])
    }

    func testDuplicateOccurrenceCannotCountTwice() {
        let first = receipt("same", ordinal: 1, start: 1, end: 4)
        var duplicate = first
        duplicate.id = ReceiptID("different-receipt")
        let result = IntervalLedger.project(
            receipts: [first, duplicate],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs([first, duplicate])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 3)
        XCTAssertEqual(result.rawClosedSeconds, 6)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedDuplicate], 3)
        XCTAssertEqual(result.violations, [.duplicateOccurrence])
    }

    func testInvalidMonotonicIntervalCannotUnderflow() {
        let invalid = receipt("invalid", ordinal: 1, start: 5, end: 2)
        let result = IntervalLedger.project(
            receipts: [invalid],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs([invalid])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.rawClosedSeconds, 0)
        XCTAssertEqual(result.violations, [.invalidMonotonicInterval])
    }

    func testAcceptedReceiptRequiresEvidence() {
        var unbound = receipt("unbound", ordinal: 1, start: 1, end: 2)
        unbound.evidenceReceiptIDs = []
        let result = IntervalLedger.project(
            receipts: [unbound],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs([unbound])
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedUnverified], 1)
        XCTAssertEqual(result.violations, [.acceptedWithoutEvidence])
    }

    func testScheduleOrdinalRegressionStartsNewSegmentAndIsReported() {
        let receipts = [
            receipt("two", ordinal: 2, start: 1, end: 2),
            receipt("one", ordinal: 1, start: 3, end: 4)
        ]
        let result = IntervalLedger.project(
            receipts: receipts,
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: progressIDs(receipts)
        )
        XCTAssertEqual(result.cumulativeAcceptedSeconds, 2)
        XCTAssertEqual(result.continuitySegmentCount, 2)
        XCTAssertEqual(result.violations, [.scheduleOrdinalRegression])
    }

    func testSucceededEvidenceWithoutAcceptedProgressIsExcluded() {
        let stagnant = receipt("stagnant", ordinal: 1, start: 1, end: 6)
        let result = IntervalLedger.project(
            receipts: [stagnant],
            policy: scheduledPolicy(),
            acceptedProgressReceiptIDs: []
        )

        XCTAssertEqual(result.cumulativeAcceptedSeconds, 0)
        XCTAssertEqual(result.excludedSecondsByReason[.excludedNoProgress], 5)
        XCTAssertEqual(result.violations, [.acceptedWithoutProgress])
    }

    private func scheduledPolicy(tolerance: UInt64 = 0) -> CoveragePolicy {
        CoveragePolicy(
            eligibleClass: .acceptedScheduledExecution,
            continuityToleranceNanoseconds: seconds(tolerance)
        )
    }

    private func receipt(
        _ id: String,
        ordinal: UInt64? = nil,
        invocation: InvocationKind? = nil,
        start: UInt64,
        end: UInt64,
        outcome: ExecutionDisposition = .succeeded,
        disposition: IntervalDisposition = .acceptedScheduled,
        discontinuities: [ClockDiscontinuity] = []
    ) -> OccurrenceReceipt {
        let invocation = invocation ?? .scheduled(
            scheduleID: schedule,
            ordinal: ordinal ?? 1
        )
        return OccurrenceReceipt(
            id: ReceiptID("receipt-\(id)"),
            occurrenceID: OccurrenceID("occurrence-\(id)"),
            invocation: invocation,
            clock: ClockReceipt(
                bootSessionID: boot,
                monotonicStartNanoseconds: seconds(start),
                monotonicEndNanoseconds: seconds(end),
                wallStart: Date(timeIntervalSince1970: TimeInterval(start)),
                wallEnd: Date(timeIntervalSince1970: TimeInterval(end)),
                discontinuities: discontinuities
            ),
            outcome: outcome,
            intervalDisposition: disposition,
            evidenceReceiptIDs: [ReceiptID("evidence-\(id)")],
            progressReceiptID: ReceiptID("progress-\(id)")
        )
    }

    private func progressIDs(_ receipts: [OccurrenceReceipt]) -> Set<ReceiptID> {
        Set(receipts.compactMap(\.progressReceiptID))
    }

    private func seconds(_ value: UInt64) -> UInt64 {
        value * 1_000_000_000
    }
}
