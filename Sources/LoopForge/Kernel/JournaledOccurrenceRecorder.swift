import Darwin
import Dispatch
import Foundation

/// Non-serializable authority to record one closed occurrence. The production
/// factory is file-private so only the clock-owning recorder below can turn a
/// measured interval into a reducer command; decoded receipts cannot.
struct AuthorizedKernelOccurrence: Sendable {
    let receipt: OccurrenceReceipt

    fileprivate init(receipt: OccurrenceReceipt) {
        self.receipt = receipt
    }

    fileprivate static func runtimeIssued(
        _ receipt: OccurrenceReceipt
    ) -> AuthorizedKernelOccurrence {
        AuthorizedKernelOccurrence(receipt: receipt)
    }

#if DEBUG
    static func testOnly(
        _ receipt: OccurrenceReceipt
    ) -> AuthorizedKernelOccurrence {
        AuthorizedKernelOccurrence(receipt: receipt)
    }
#endif
}

struct OccurrenceClockSample: Equatable, Sendable {
    var bootSessionID: BootSessionID
    var monotonicNanoseconds: UInt64
    var wallTime: Date
}

/// An in-memory capability for one open occurrence. It is intentionally not
/// Codable, and its nonce is visible only to this file, so persisted model or
/// controller data cannot synthesize an already-running interval.
struct JournaledOccurrenceStartToken: Equatable, Sendable {
    fileprivate var nonce: UUID
    var occurrenceID: OccurrenceID
    var invocation: InvocationKind
}

struct JournaledOccurrenceRecordReceipt: Sendable {
    var occurrence: OccurrenceReceipt
    var journalTransaction: JournalTransactionReceipt
}

enum JournaledOccurrenceRecorderError: Error, Equatable {
    case invalidOccurrence
    case occurrenceAlreadyOpen
    case unknownOrConsumedToken
    case journalRejected(KernelRejection)
    case journalWriteFailed
}

/// The sole clock-owning issuer for new-kernel occurrence receipts.
///
/// Callers choose an invocation and report an execution outcome, but never
/// supply clock bounds or an accepted/excluded disposition. The recorder owns
/// a non-serializable start capability, samples the boot-bound monotonic clock,
/// derives discontinuities and disposition, then commits the closed receipt to
/// RunJournal. A crash with an open token records no time and therefore fails
/// closed.
actor JournaledOccurrenceRecorder {
    private struct OpenOccurrence: Sendable {
        var occurrenceID: OccurrenceID
        var invocation: InvocationKind
        var started: OccurrenceClockSample
    }

    private let journal: RunJournal
    private let actorIdentity: ActorIdentity
    private let clock: @Sendable () -> OccurrenceClockSample
    private let sleepToleranceNanoseconds: UInt64
    private var openByNonce: [UUID: OpenOccurrence] = [:]
    private var nonceByOccurrenceID: [OccurrenceID: UUID] = [:]

    init(
        journal: RunJournal,
        actorIdentity: ActorIdentity,
        sleepToleranceNanoseconds: UInt64 = 5_000_000_000,
        clock: @escaping @Sendable () -> OccurrenceClockSample = {
            OccurrenceClockSample(
                bootSessionID: JournaledOccurrenceRecorder.currentBootSessionID(),
                monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
                wallTime: Date()
            )
        }
    ) {
        self.journal = journal
        self.actorIdentity = actorIdentity
        self.sleepToleranceNanoseconds = sleepToleranceNanoseconds
        self.clock = clock
    }

    func begin(
        occurrenceID: OccurrenceID,
        invocation: InvocationKind
    ) throws -> JournaledOccurrenceStartToken {
        guard !occurrenceID.rawValue.isEmpty,
              Self.invocationIsValid(invocation) else {
            throw JournaledOccurrenceRecorderError.invalidOccurrence
        }
        guard nonceByOccurrenceID[occurrenceID] == nil else {
            throw JournaledOccurrenceRecorderError.occurrenceAlreadyOpen
        }
        let started = clock()
        guard !started.bootSessionID.rawValue.isEmpty,
              started.wallTime.timeIntervalSince1970.isFinite else {
            throw JournaledOccurrenceRecorderError.invalidOccurrence
        }
        let nonce = UUID()
        openByNonce[nonce] = OpenOccurrence(
            occurrenceID: occurrenceID,
            invocation: invocation,
            started: started
        )
        nonceByOccurrenceID[occurrenceID] = nonce
        return JournaledOccurrenceStartToken(
            nonce: nonce,
            occurrenceID: occurrenceID,
            invocation: invocation
        )
    }

    func close(
        _ token: JournaledOccurrenceStartToken,
        outcome: ExecutionDisposition,
        evidenceReceiptIDs: Set<ReceiptID>,
        progressReceiptID: ReceiptID?,
        receiptID: ReceiptID,
        commandID: RunCommandID
    ) async throws -> JournaledOccurrenceRecordReceipt {
        try await close(
            token,
            outcome: outcome,
            authoritativeEnd: nil,
            evidenceReceiptIDs: evidenceReceiptIDs,
            progressReceiptID: progressReceiptID,
            receiptID: receiptID,
            commandID: commandID
        )
    }

    /// This overload is reachable only with a non-serializable end bound whose
    /// initializer is private to the owned-process bridge file. It prevents
    /// release-journal latency from being counted as process execution.
    func closeOwnedExecution(
        _ token: JournaledOccurrenceStartToken,
        outcome: ExecutionDisposition,
        authoritativeEnd: JournaledOwnedExecutionEndBound,
        evidenceReceiptIDs: Set<ReceiptID>,
        progressReceiptID: ReceiptID?,
        receiptID: ReceiptID,
        commandID: RunCommandID
    ) async throws -> JournaledOccurrenceRecordReceipt {
        try await close(
            token,
            outcome: outcome,
            authoritativeEnd: authoritativeEnd,
            evidenceReceiptIDs: evidenceReceiptIDs,
            progressReceiptID: progressReceiptID,
            receiptID: receiptID,
            commandID: commandID
        )
    }

    private func close(
        _ token: JournaledOccurrenceStartToken,
        outcome: ExecutionDisposition,
        authoritativeEnd: JournaledOwnedExecutionEndBound?,
        evidenceReceiptIDs: Set<ReceiptID>,
        progressReceiptID: ReceiptID?,
        receiptID: ReceiptID,
        commandID: RunCommandID
    ) async throws -> JournaledOccurrenceRecordReceipt {
        guard let open = openByNonce[token.nonce],
              open.occurrenceID == token.occurrenceID,
              open.invocation == token.invocation,
              nonceByOccurrenceID[token.occurrenceID] == token.nonce else {
            throw JournaledOccurrenceRecorderError.unknownOrConsumedToken
        }
        let sampledEnd = clock()
        let ended: OccurrenceClockSample
        if let authoritativeEnd {
            guard authoritativeEnd.wallTime.timeIntervalSince1970.isFinite,
                  authoritativeEnd.monotonicNanoseconds <=
                    sampledEnd.monotonicNanoseconds else {
                throw JournaledOccurrenceRecorderError.invalidOccurrence
            }
            ended = OccurrenceClockSample(
                bootSessionID: sampledEnd.bootSessionID,
                monotonicNanoseconds: authoritativeEnd.monotonicNanoseconds,
                wallTime: authoritativeEnd.wallTime
            )
        } else {
            ended = sampledEnd
        }
        guard !receiptID.rawValue.isEmpty,
              !commandID.rawValue.isEmpty,
              !ended.bootSessionID.rawValue.isEmpty,
              ended.wallTime.timeIntervalSince1970.isFinite else {
            throw JournaledOccurrenceRecorderError.invalidOccurrence
        }

        var discontinuities: [ClockDiscontinuity] = []
        if ended.bootSessionID != open.started.bootSessionID {
            discontinuities.append(.reboot)
        }
        let monotonicEnd: UInt64
        if ended.monotonicNanoseconds < open.started.monotonicNanoseconds {
            discontinuities.append(.monotonicReset)
            monotonicEnd = open.started.monotonicNanoseconds
        } else {
            monotonicEnd = ended.monotonicNanoseconds
        }
        let monotonicElapsed = monotonicEnd - open.started.monotonicNanoseconds
        let wallElapsed = max(
            0,
            ended.wallTime.timeIntervalSince(open.started.wallTime)
        )
        let wallElapsedNanoseconds = Self.nanoseconds(wallElapsed)
        if ended.bootSessionID == open.started.bootSessionID,
           wallElapsedNanoseconds > Self.adding(
               monotonicElapsed,
               sleepToleranceNanoseconds
           ) {
            discontinuities.append(.sleep)
        }

        let occurrence = OccurrenceReceipt(
            id: receiptID,
            occurrenceID: open.occurrenceID,
            invocation: open.invocation,
            clock: ClockReceipt(
                bootSessionID: open.started.bootSessionID,
                monotonicStartNanoseconds: open.started.monotonicNanoseconds,
                monotonicEndNanoseconds: monotonicEnd,
                wallStart: open.started.wallTime,
                wallEnd: ended.wallTime,
                discontinuities: discontinuities
            ),
            outcome: outcome,
            intervalDisposition: Self.disposition(
                invocation: open.invocation,
                outcome: outcome
            ),
            evidenceReceiptIDs: evidenceReceiptIDs,
            progressReceiptID: progressReceiptID
        )
        let transaction: JournalTransactionReceipt
        do {
            transaction = try await journal.transactAtCurrentSequence(
                .recordOccurrence(.runtimeIssued(occurrence)),
                commandID: commandID,
                issuedAt: ended.wallTime,
                actor: actorIdentity
            )
        } catch RunJournalError.reducerRejected(let rejection) {
            throw JournaledOccurrenceRecorderError.journalRejected(rejection)
        } catch {
            throw JournaledOccurrenceRecorderError.journalWriteFailed
        }
        openByNonce[token.nonce] = nil
        nonceByOccurrenceID[token.occurrenceID] = nil
        return JournaledOccurrenceRecordReceipt(
            occurrence: occurrence,
            journalTransaction: transaction
        )
    }

    @discardableResult
    func abandon(_ token: JournaledOccurrenceStartToken) -> Bool {
        guard let open = openByNonce[token.nonce],
              open.occurrenceID == token.occurrenceID,
              open.invocation == token.invocation else { return false }
        openByNonce[token.nonce] = nil
        nonceByOccurrenceID[token.occurrenceID] = nil
        return true
    }

    func openOccurrenceCount() -> Int {
        openByNonce.count
    }

    private static func disposition(
        invocation: InvocationKind,
        outcome: ExecutionDisposition
    ) -> IntervalDisposition {
        switch outcome {
        case .failed: return .excludedFailure
        case .cancelled: return .excludedCancelled
        case .blocked: return .excludedBlocked
        case .unverified: return .excludedUnverified
        case .succeeded:
            switch invocation {
            case .scheduled: return .acceptedScheduled
            case .manual: return .acceptedInteractive
            case .recovery, .verification, .adaptiveReview, .ownerAmendment:
                return .excludedManual
            }
        }
    }

    private static func invocationIsValid(_ invocation: InvocationKind) -> Bool {
        switch invocation {
        case .scheduled(let scheduleID, _):
            return !scheduleID.rawValue.isEmpty
        case .manual(let commandID), .ownerAmendment(let commandID):
            return !commandID.rawValue.isEmpty
        case .recovery:
            return true
        case .verification(let requirementIDs):
            return !requirementIDs.isEmpty
        case .adaptiveReview(let triggerID):
            return !triggerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let scaled = seconds * 1_000_000_000
        guard scaled < Double(UInt64.max) else { return UInt64.max }
        return UInt64(scaled.rounded(.down))
    }

    private static func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : value
    }

    private static func currentBootSessionID() -> BootSessionID {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0,
           bootTime.tv_sec > 0 {
            return BootSessionID("darwin-\(bootTime.tv_sec)-\(bootTime.tv_usec)")
        }
        let estimatedBoot = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        return BootSessionID("estimated-\(Int64(estimatedBoot.rounded(.down)))")
    }
}
