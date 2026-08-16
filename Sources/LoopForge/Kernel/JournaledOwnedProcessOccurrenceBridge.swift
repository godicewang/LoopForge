import Foundation

/// A process-exit clock bound that cannot be initialized by persisted state or
/// a generic controller. The occurrence recorder may read it, but only this
/// file can mint one from an exact release receipt.
struct JournaledOwnedExecutionEndBound: Sendable {
    let monotonicNanoseconds: UInt64
    let wallTime: Date

    fileprivate init(monotonicNanoseconds: UInt64, wallTime: Date) {
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
    }
}

/// An in-memory capability binding one clock-owned occurrence to one exact
/// journaled process lease. Persisted controllers cannot synthesize it.
struct JournaledOwnedProcessOccurrenceToken: Equatable, Sendable {
    fileprivate var nonce: UUID
    var occurrenceID: OccurrenceID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
}

enum JournaledOwnedProcessOccurrenceBridgeError: Error, Equatable {
    case invalidStart
    case duplicateAdmission
    case unjournaledStart
    case ownershipDiverged
    case unknownOrConsumedToken
    case releaseMismatch
    case unjournaledRelease
}

/// Bridges the runtime ownership journal and the sole occurrence clock issuer.
///
/// A duration interval can begin only after a new productive process-tree lease
/// and its exact PID/process-group identity are both journaled. It can close
/// only after the same native handle exits and the same lease is released by a
/// journal transaction. The execution outcome is derived from the native exit;
/// callers cannot label a failed or signalled process as successful.
actor JournaledOwnedProcessOccurrenceBridge {
    private struct OpenExecution: Sendable {
        var recorderToken: JournaledOccurrenceStartToken
        var handle: ManagedProcessHandle
    }

    private let journal: RunJournal
    private let supervisor: RuntimeSupervisor
    private let recorder: JournaledOccurrenceRecorder
    private var openByNonce: [UUID: OpenExecution] = [:]

    init(
        journal: RunJournal,
        supervisor: RuntimeSupervisor,
        recorder: JournaledOccurrenceRecorder
    ) {
        self.journal = journal
        self.supervisor = supervisor
        self.recorder = recorder
    }

    func begin(
        start: JournaledProcessStartReceipt,
        invocation: InvocationKind
    ) async throws -> JournaledOwnedProcessOccurrenceToken {
        guard case .accepted(let admittedLease, let duplicate) = start.admission.outcome else {
            throw JournaledOwnedProcessOccurrenceBridgeError.invalidStart
        }
        guard !duplicate else {
            throw JournaledOwnedProcessOccurrenceBridgeError.duplicateAdmission
        }
        let request = admittedLease.request
        guard let occurrenceID = request.occurrenceID,
              request == start.admission.request,
              request.kind == .processTree,
              request.purpose == .productive,
              request.ownership == .owned,
              request.releasePolicy == .gracefulThenTerminate,
              request.externalIdentity == nil,
              start.admission.runID == request.runID,
              start.launch.binding.accepted,
              start.launch.binding.runID == request.runID,
              start.launch.binding.resourceID == request.resourceID,
              start.launch.binding.leaseID == request.leaseID,
              start.launch.handle.runID == request.runID,
              start.launch.handle.resourceID == request.resourceID,
              start.launch.handle.leaseID == request.leaseID,
              start.launch.handle.processID > 0,
              start.launch.handle.processGroupID == start.launch.handle.processID,
              start.launch.handle.externalIdentity == start.launch.binding.identity,
              start.launch.handle.externalIdentity.processID == start.launch.handle.processID else {
            throw JournaledOwnedProcessOccurrenceBridgeError.invalidStart
        }

        guard await journal.runtimeAdmissionReceipt(
                  transaction: start.admissionTransaction
              ) == start.admission,
              await journal.runtimeBindingReceipt(
                  transaction: start.launch.journalTransaction
              ) == start.launch.binding else {
            throw JournaledOwnedProcessOccurrenceBridgeError.unjournaledStart
        }

        var boundLease = admittedLease
        boundLease.request.externalIdentity = start.launch.binding.identity
        let supervisorLease = await supervisor.projection().liveLeases.first {
            $0.request.resourceID == request.resourceID
        }
        guard await journal.runtimeLease(resourceID: request.resourceID) == boundLease,
              supervisorLease == boundLease else {
            throw JournaledOwnedProcessOccurrenceBridgeError.ownershipDiverged
        }

        let recorderToken = try await recorder.begin(
            occurrenceID: occurrenceID,
            invocation: invocation
        )
        let nonce = UUID()
        openByNonce[nonce] = OpenExecution(
            recorderToken: recorderToken,
            handle: start.launch.handle
        )
        return JournaledOwnedProcessOccurrenceToken(
            nonce: nonce,
            occurrenceID: occurrenceID,
            resourceID: request.resourceID,
            leaseID: request.leaseID
        )
    }

    func close(
        _ token: JournaledOwnedProcessOccurrenceToken,
        release: JournaledProcessReleaseReceipt,
        evidenceReceiptIDs: Set<ReceiptID>,
        progressReceiptID: ReceiptID?,
        occurrenceReceiptID: ReceiptID,
        occurrenceCommandID: RunCommandID
    ) async throws -> JournaledOccurrenceRecordReceipt {
        guard let open = openByNonce[token.nonce],
              open.recorderToken.occurrenceID == token.occurrenceID,
              open.handle.resourceID == token.resourceID,
              open.handle.leaseID == token.leaseID else {
            throw JournaledOwnedProcessOccurrenceBridgeError.unknownOrConsumedToken
        }
        guard release.termination.handle == open.handle,
              release.termination.exit.handle == open.handle,
              release.release.managedProcessTermination == release.termination,
              release.release.runID == open.handle.runID,
              release.release.resourceID == token.resourceID,
              release.release.leaseID == token.leaseID,
              release.release.observedAtMonotonicNanoseconds >=
                release.termination.exit.observedAtMonotonicNanoseconds,
              case .released(let releasedLease) = release.release.outcome,
              releasedLease.id == release.release.id,
              releasedLease.runID == open.handle.runID,
              releasedLease.resourceID == token.resourceID,
              releasedLease.leaseID == token.leaseID,
              !releasedLease.duplicate else {
            throw JournaledOwnedProcessOccurrenceBridgeError.releaseMismatch
        }
        return try await closeValidated(
            token,
            open: open,
            exit: release.termination.exit,
            release: release.release,
            journalTransaction: release.journalTransaction,
            evidenceReceiptIDs: evidenceReceiptIDs,
            progressReceiptID: progressReceiptID,
            occurrenceReceiptID: occurrenceReceiptID,
            occurrenceCommandID: occurrenceCommandID
        )
    }

    func closeNaturally(
        _ token: JournaledOwnedProcessOccurrenceToken,
        release: JournaledProcessNaturalReleaseReceipt,
        evidenceReceiptIDs: Set<ReceiptID>,
        progressReceiptID: ReceiptID?,
        occurrenceReceiptID: ReceiptID,
        occurrenceCommandID: RunCommandID
    ) async throws -> JournaledOccurrenceRecordReceipt {
        guard let open = openByNonce[token.nonce],
              open.recorderToken.occurrenceID == token.occurrenceID,
              open.handle.resourceID == token.resourceID,
              open.handle.leaseID == token.leaseID else {
            throw JournaledOwnedProcessOccurrenceBridgeError.unknownOrConsumedToken
        }
        guard release.exit.handle == open.handle,
              release.release.managedProcessExit == release.exit,
              release.release.managedProcessTermination == nil,
              release.release.runID == open.handle.runID,
              release.release.resourceID == token.resourceID,
              release.release.leaseID == token.leaseID,
              release.release.observedAtMonotonicNanoseconds >=
                release.exit.observedAtMonotonicNanoseconds,
              case .released(let releasedLease) = release.release.outcome,
              releasedLease.id == release.release.id,
              releasedLease.runID == open.handle.runID,
              releasedLease.resourceID == token.resourceID,
              releasedLease.leaseID == token.leaseID,
              !releasedLease.duplicate else {
            throw JournaledOwnedProcessOccurrenceBridgeError.releaseMismatch
        }
        return try await closeValidated(
            token,
            open: open,
            exit: release.exit,
            release: release.release,
            journalTransaction: release.journalTransaction,
            evidenceReceiptIDs: evidenceReceiptIDs,
            progressReceiptID: progressReceiptID,
            occurrenceReceiptID: occurrenceReceiptID,
            occurrenceCommandID: occurrenceCommandID
        )
    }

    @discardableResult
    func abandon(_ token: JournaledOwnedProcessOccurrenceToken) async -> Bool {
        guard let open = openByNonce[token.nonce],
              open.recorderToken.occurrenceID == token.occurrenceID,
              open.handle.resourceID == token.resourceID,
              open.handle.leaseID == token.leaseID else { return false }
        guard await recorder.abandon(open.recorderToken) else { return false }
        openByNonce[token.nonce] = nil
        return true
    }

    func openExecutionCount() -> Int {
        openByNonce.count
    }

    private func closeValidated(
        _ token: JournaledOwnedProcessOccurrenceToken,
        open: OpenExecution,
        exit: ManagedProcessExitReceipt,
        release: RuntimeReleaseOutcomeReceipt,
        journalTransaction: JournalTransactionReceipt,
        evidenceReceiptIDs: Set<ReceiptID>,
        progressReceiptID: ReceiptID?,
        occurrenceReceiptID: ReceiptID,
        occurrenceCommandID: RunCommandID
    ) async throws -> JournaledOccurrenceRecordReceipt {
        let supervisorProjection = await supervisor.projection()
        guard await journal.runtimeReleaseReceipt(
                  transaction: journalTransaction
              ) == release,
              await journal.runtimeLease(resourceID: token.resourceID) == nil,
              !supervisorProjection.liveLeases.contains(where: {
                  $0.request.resourceID == token.resourceID
              }),
              !supervisorProjection.failedReleases.contains(token.resourceID) else {
            throw JournaledOwnedProcessOccurrenceBridgeError.unjournaledRelease
        }
        let exitToReleaseNanoseconds =
            release.observedAtMonotonicNanoseconds - exit.observedAtMonotonicNanoseconds
        let executionEnd = JournaledOwnedExecutionEndBound(
            monotonicNanoseconds: exit.observedAtMonotonicNanoseconds,
            wallTime: release.observedAt.addingTimeInterval(
                -Double(exitToReleaseNanoseconds) / 1_000_000_000
            )
        )
        let receipt = try await recorder.closeOwnedExecution(
            open.recorderToken,
            outcome: Self.executionDisposition(exit),
            authoritativeEnd: executionEnd,
            evidenceReceiptIDs: evidenceReceiptIDs,
            progressReceiptID: progressReceiptID,
            receiptID: occurrenceReceiptID,
            commandID: occurrenceCommandID
        )
        openByNonce[token.nonce] = nil
        return receipt
    }

    private static func executionDisposition(
        _ exit: ManagedProcessExitReceipt
    ) -> ExecutionDisposition {
        switch (exit.exitCode, exit.terminationSignal) {
        case (.some(0), .none): return .succeeded
        case (.some, .none): return .failed
        case (.none, .some): return .cancelled
        default: return .unverified
        }
    }
}
