import Foundation

enum InvocationKind: Codable, Hashable, Sendable {
    case scheduled(scheduleID: ScheduleID, ordinal: UInt64)
    case manual(ownerCommandID: RunCommandID)
    case recovery(predecessor: OccurrenceID?)
    case verification(requirementIDs: Set<RequirementID>)
    case adaptiveReview(triggerID: String)
    case ownerAmendment(commandID: RunCommandID)
}

enum ExecutionDisposition: String, Codable, Hashable, Sendable {
    case succeeded
    case failed
    case cancelled
    case blocked
    case unverified
}

enum ClockDiscontinuity: String, Codable, Hashable, Sendable {
    case sleep
    case reboot
    case monotonicReset
    case wallClockShift

    var breaksMonotonicCoverage: Bool {
        self != .wallClockShift
    }
}

struct ClockReceipt: Codable, Hashable, Sendable {
    var bootSessionID: BootSessionID
    var monotonicStartNanoseconds: UInt64
    var monotonicEndNanoseconds: UInt64
    var wallStart: Date
    var wallEnd: Date
    var discontinuities: [ClockDiscontinuity]

    var elapsedNanoseconds: UInt64? {
        guard monotonicEndNanoseconds >= monotonicStartNanoseconds else { return nil }
        return monotonicEndNanoseconds - monotonicStartNanoseconds
    }
}

enum IntervalDisposition: String, Codable, Hashable, Sendable {
    case acceptedScheduled
    case acceptedInteractive
    case excludedManual
    case excludedSleep
    case excludedDowntime
    case excludedGap
    case excludedEmpty
    case excludedFailure
    case excludedCancelled
    case excludedBlocked
    case excludedUnverified
    case excludedNoProgress
    case excludedDuplicate
}

struct OccurrenceReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var occurrenceID: OccurrenceID
    var invocation: InvocationKind
    var clock: ClockReceipt
    var outcome: ExecutionDisposition
    var intervalDisposition: IntervalDisposition
    var evidenceReceiptIDs: Set<ReceiptID>
    /// The journal transaction that accepted a causal progress evaluation for
    /// this occurrence. Optional only for decoding pre-kernel receipts; a
    /// missing or unrecognized value is fail-closed for accepted duration.
    var progressReceiptID: ReceiptID?
}

struct LiveAttemptInterval: Codable, Hashable, Sendable {
    var occurrenceID: OccurrenceID
    var invocation: InvocationKind
    var bootSessionID: BootSessionID
    var retainedEligibleNanoseconds: UInt64
    var liveSegmentStartedAtNanoseconds: UInt64?
    var provisionalDisposition: IntervalDisposition
    var hasOwnedExecution: Bool
}

struct CoveragePolicy: Codable, Hashable, Sendable {
    var eligibleClass: DurationAcceptancePolicy.EligibleClass
    var continuityToleranceNanoseconds: UInt64
}

enum CoverageViolation: String, Codable, Hashable, Sendable {
    case duplicateOccurrence
    case invalidMonotonicInterval
    case acceptedWithoutEvidence
    case acceptedWithoutProgress
    case dispositionContradictsOutcome
    case dispositionContradictsInvocation
    case dispositionContradictsPolicy
    case scheduleOrdinalRegression
}

struct CoverageContribution: Codable, Hashable, Sendable {
    var occurrenceID: OccurrenceID
    var receiptID: ReceiptID
    var acceptedNanoseconds: UInt64
    var continuitySegment: Int
    var previousAcceptedOccurrenceID: OccurrenceID?
    var formula: String
}

struct CoverageProjection: Codable, Equatable, Sendable {
    var cumulativeAcceptedSeconds: Double
    var currentAttemptSeconds: Double
    var currentLiveSegmentSeconds: Double
    var rawClosedSeconds: Double
    var excludedClosedSeconds: Double
    var excludedSecondsByReason: [IntervalDisposition: Double]
    var continuitySegmentCount: Int
    var contributions: [CoverageContribution]
    var lastAcceptedOccurrenceID: OccurrenceID?
    var liveOccurrenceID: OccurrenceID?
    var currentInvocation: InvocationKind?
    var isLiveTimerAdvancing: Bool
    var violations: [CoverageViolation]
}

/// Deterministically projects typed, closed occurrence receipts plus at most
/// one live monotonic segment. Wall-clock values are never used for elapsed
/// time. Views receive cumulative and current-attempt values separately, so a
/// new round cannot erase prior accepted work or masquerade as total runtime.
enum IntervalLedger {
    static func project(
        receipts: [OccurrenceReceipt],
        policy: CoveragePolicy,
        acceptedProgressReceiptIDs: Set<ReceiptID> = [],
        liveAttempt: LiveAttemptInterval? = nil,
        currentBootSessionID: BootSessionID? = nil,
        currentMonotonicNanoseconds: UInt64? = nil
    ) -> CoverageProjection {
        var seenOccurrences: Set<OccurrenceID> = []
        var acceptedNanoseconds: UInt64 = 0
        var rawNanoseconds: UInt64 = 0
        var excludedByReason: [IntervalDisposition: UInt64] = [:]
        var contributions: [CoverageContribution] = []
        var violations: [CoverageViolation] = []
        var previousAccepted: OccurrenceReceipt?
        var continuitySegment = 0

        for receipt in receipts {
            guard let elapsed = receipt.clock.elapsedNanoseconds else {
                violations.append(.invalidMonotonicInterval)
                continue
            }
            rawNanoseconds = adding(rawNanoseconds, elapsed)

            guard seenOccurrences.insert(receipt.occurrenceID).inserted else {
                violations.append(.duplicateOccurrence)
                excludedByReason[.excludedDuplicate, default: 0] = adding(
                    excludedByReason[.excludedDuplicate, default: 0], elapsed
                )
                continue
            }

            let adjudication = adjudicate(
                receipt,
                policy: policy,
                acceptedProgressReceiptIDs: acceptedProgressReceiptIDs
            )
            violations.append(contentsOf: adjudication.violations)
            guard adjudication.accepted else {
                excludedByReason[adjudication.disposition, default: 0] = adding(
                    excludedByReason[adjudication.disposition, default: 0], elapsed
                )
                continue
            }

            let startsNewSegment = previousAccepted.map {
                continuityBreak(
                    from: $0,
                    to: receipt,
                    tolerance: policy.continuityToleranceNanoseconds,
                    violations: &violations
                )
            } ?? true
            if startsNewSegment { continuitySegment += 1 }
            acceptedNanoseconds = adding(acceptedNanoseconds, elapsed)
            contributions.append(CoverageContribution(
                occurrenceID: receipt.occurrenceID,
                receiptID: receipt.id,
                acceptedNanoseconds: elapsed,
                continuitySegment: continuitySegment,
                previousAcceptedOccurrenceID: previousAccepted?.occurrenceID,
                formula: "monotonicEndNanoseconds - monotonicStartNanoseconds"
            ))
            previousAccepted = receipt
        }

        let live = liveProjection(
            liveAttempt,
            policy: policy,
            currentBootSessionID: currentBootSessionID,
            currentMonotonicNanoseconds: currentMonotonicNanoseconds
        )
        let excludedNanoseconds = excludedByReason.values.reduce(0, adding)
        return CoverageProjection(
            cumulativeAcceptedSeconds: seconds(acceptedNanoseconds),
            currentAttemptSeconds: seconds(live.attemptNanoseconds),
            currentLiveSegmentSeconds: seconds(live.segmentNanoseconds),
            rawClosedSeconds: seconds(rawNanoseconds),
            excludedClosedSeconds: seconds(excludedNanoseconds),
            excludedSecondsByReason: excludedByReason.mapValues(seconds),
            continuitySegmentCount: continuitySegment,
            contributions: contributions,
            lastAcceptedOccurrenceID: previousAccepted?.occurrenceID,
            liveOccurrenceID: liveAttempt?.occurrenceID,
            currentInvocation: liveAttempt?.invocation,
            isLiveTimerAdvancing: live.isAdvancing,
            violations: violations + live.violations
        )
    }

    private struct Adjudication {
        var accepted: Bool
        var disposition: IntervalDisposition
        var violations: [CoverageViolation]
    }

    private static func adjudicate(
        _ receipt: OccurrenceReceipt,
        policy: CoveragePolicy,
        acceptedProgressReceiptIDs: Set<ReceiptID>
    ) -> Adjudication {
        if let discontinuity = receipt.clock.discontinuities.first(where: \.breaksMonotonicCoverage) {
            return Adjudication(
                accepted: false,
                disposition: discontinuity == .sleep ? .excludedSleep : .excludedDowntime,
                violations: []
            )
        }
        switch receipt.outcome {
        case .failed:
            return excluded(.excludedFailure, receipt: receipt)
        case .cancelled:
            return excluded(.excludedCancelled, receipt: receipt)
        case .blocked:
            return excluded(.excludedBlocked, receipt: receipt)
        case .unverified:
            return excluded(.excludedUnverified, receipt: receipt)
        case .succeeded:
            break
        }
        guard receipt.clock.elapsedNanoseconds != 0 else {
            return Adjudication(accepted: false, disposition: .excludedEmpty, violations: [])
        }
        guard !receipt.evidenceReceiptIDs.isEmpty else {
            return Adjudication(
                accepted: false,
                disposition: .excludedUnverified,
                violations: [.acceptedWithoutEvidence]
            )
        }
        guard let progressReceiptID = receipt.progressReceiptID,
              acceptedProgressReceiptIDs.contains(progressReceiptID) else {
            return Adjudication(
                accepted: false,
                disposition: .excludedNoProgress,
                violations: [.acceptedWithoutProgress]
            )
        }

        let expectedDisposition: IntervalDisposition?
        switch receipt.invocation {
        case .scheduled:
            expectedDisposition = .acceptedScheduled
        case .manual:
            expectedDisposition = .acceptedInteractive
        case .recovery, .verification, .adaptiveReview, .ownerAmendment:
            expectedDisposition = nil
        }
        guard let expectedDisposition else {
            return Adjudication(
                accepted: false,
                disposition: manualExclusion(for: receipt.invocation),
                violations: receipt.intervalDisposition == .acceptedScheduled ||
                    receipt.intervalDisposition == .acceptedInteractive
                    ? [.dispositionContradictsInvocation]
                    : []
            )
        }
        guard receipt.intervalDisposition == expectedDisposition else {
            return Adjudication(
                accepted: false,
                disposition: manualExclusion(for: receipt.invocation),
                violations: [.dispositionContradictsInvocation]
            )
        }

        let policyAccepts: Bool
        switch policy.eligibleClass {
        case .acceptedScheduledExecution:
            policyAccepts = expectedDisposition == .acceptedScheduled
        case .acceptedInteractiveExecution:
            policyAccepts = expectedDisposition == .acceptedInteractive
        case .acceptedExecution:
            policyAccepts = true
        }
        guard policyAccepts else {
            return Adjudication(
                accepted: false,
                disposition: manualExclusion(for: receipt.invocation),
                violations: [.dispositionContradictsPolicy]
            )
        }
        return Adjudication(accepted: true, disposition: expectedDisposition, violations: [])
    }

    private static func excluded(
        _ disposition: IntervalDisposition,
        receipt: OccurrenceReceipt
    ) -> Adjudication {
        let declaredAccepted = receipt.intervalDisposition == .acceptedScheduled ||
            receipt.intervalDisposition == .acceptedInteractive
        return Adjudication(
            accepted: false,
            disposition: disposition,
            violations: declaredAccepted ? [.dispositionContradictsOutcome] : []
        )
    }

    private static func manualExclusion(for invocation: InvocationKind) -> IntervalDisposition {
        switch invocation {
        case .manual, .ownerAmendment:
            return .excludedManual
        case .recovery, .verification, .adaptiveReview:
            return .excludedUnverified
        case .scheduled:
            return .excludedUnverified
        }
    }

    private static func continuityBreak(
        from previous: OccurrenceReceipt,
        to current: OccurrenceReceipt,
        tolerance: UInt64,
        violations: inout [CoverageViolation]
    ) -> Bool {
        guard case .scheduled(let previousSchedule, let previousOrdinal) = previous.invocation,
              case .scheduled(let currentSchedule, let currentOrdinal) = current.invocation else {
            return false
        }
        if currentSchedule != previousSchedule || currentOrdinal != previousOrdinal + 1 {
            if currentSchedule == previousSchedule, currentOrdinal <= previousOrdinal {
                violations.append(.scheduleOrdinalRegression)
            }
            return true
        }
        guard current.clock.bootSessionID == previous.clock.bootSessionID,
              current.clock.monotonicStartNanoseconds >= previous.clock.monotonicEndNanoseconds else {
            return true
        }
        return current.clock.monotonicStartNanoseconds - previous.clock.monotonicEndNanoseconds > tolerance
    }

    private static func liveProjection(
        _ live: LiveAttemptInterval?,
        policy: CoveragePolicy,
        currentBootSessionID: BootSessionID?,
        currentMonotonicNanoseconds: UInt64?
    ) -> (attemptNanoseconds: UInt64, segmentNanoseconds: UInt64, isAdvancing: Bool, violations: [CoverageViolation]) {
        guard let live else { return (0, 0, false, []) }
        guard live.hasOwnedExecution,
              liveDispositionIsEligible(live, policy: policy) else {
            return (0, 0, false, [])
        }
        guard let start = live.liveSegmentStartedAtNanoseconds else {
            return (live.retainedEligibleNanoseconds, 0, false, [])
        }
        guard let currentBootSessionID,
              let now = currentMonotonicNanoseconds,
              currentBootSessionID == live.bootSessionID,
              now >= start else {
            return (live.retainedEligibleNanoseconds, 0, false, [.invalidMonotonicInterval])
        }
        let segment = now - start
        return (adding(live.retainedEligibleNanoseconds, segment), segment, true, [])
    }

    private static func liveDispositionIsEligible(
        _ live: LiveAttemptInterval,
        policy: CoveragePolicy
    ) -> Bool {
        switch (policy.eligibleClass, live.invocation, live.provisionalDisposition) {
        case (.acceptedScheduledExecution, .scheduled, .acceptedScheduled),
             (.acceptedInteractiveExecution, .manual, .acceptedInteractive),
             (.acceptedExecution, .scheduled, .acceptedScheduled),
             (.acceptedExecution, .manual, .acceptedInteractive):
            return true
        default:
            return false
        }
    }

    private static func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    private static func seconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000_000
    }
}
