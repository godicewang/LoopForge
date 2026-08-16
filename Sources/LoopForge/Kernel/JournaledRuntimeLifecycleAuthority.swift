import Dispatch
import Foundation

/// File-owned proof that drain or quiescence evidence came from the
/// journal/supervisor lifecycle coordinator. It is never returned or persisted.
struct JournaledRuntimeLifecycleCommandIssuer: Sendable {
    fileprivate init() {}
}

struct JournaledRuntimeDrainRequest: Sendable {
    var intent: RuntimeDrainIntent
    var lifecycleCommandID: RunCommandID
    var drainReceiptID: ReceiptID
    var drainCommandID: RunCommandID
}

struct JournaledRuntimeDrainTransitionReceipt: Sendable {
    /// Nil only when recovering a retained lifecycle request whose drain
    /// receipt was not durably appended before the earlier caller stopped.
    var lifecycleTransaction: JournalTransactionReceipt?
    var drain: RuntimeDrainReceipt
    var drainTransaction: JournalTransactionReceipt
    var cleanupPlan: [RuntimeCleanupAction]
}

struct JournaledRuntimeQuiescenceRequest: Sendable {
    var receiptID: ReceiptID
    var commandID: RunCommandID
}

struct JournaledRuntimeQuiescenceTransitionReceipt: Sendable {
    var quiescence: QuiescenceReceipt
    var journalTransaction: JournalTransactionReceipt
}

enum JournaledRuntimeLifecycleAuthorityError: Error, Equatable, Sendable {
    case unsupportedIntent
    case journalWriteFailed
    case supervisorNotDraining
    case resourcesRemain(Set<OwnedResourceID>)
    case failedReleasesRemain(Set<OwnedResourceID>)
    case queuedCleanupRemains(Set<ResourceLeaseID>)
    case retainedLifecycleRequestUnavailable
}

/// The production bridge from a reducer-accepted lifecycle request to an
/// observed supervisor drain and, only after exact cleanup, quiescence.
/// Callers choose lifecycle intent and receipt identities but never provide
/// clocks, resource sets, failure sets, queue sets, or a quiescence verdict.
actor JournaledRuntimeLifecycleAuthority {
    private let supervisor: RuntimeSupervisor
    private let journal: RunJournal
    private let actorIdentity: ActorIdentity

    init(
        supervisor: RuntimeSupervisor,
        journal: RunJournal,
        actorIdentity: ActorIdentity
    ) {
        self.supervisor = supervisor
        self.journal = journal
        self.actorIdentity = actorIdentity
    }

    func requestDrain(
        _ request: JournaledRuntimeDrainRequest
    ) async throws -> JournaledRuntimeDrainTransitionReceipt {
        let lifecycleCommand: RunCommand
        switch request.intent {
        case .pause:
            lifecycleCommand = .requestPause
        case .complete:
            lifecycleCommand = .requestCompletion
        case .stop:
            lifecycleCommand = .requestStop
        case .quit:
            throw JournaledRuntimeLifecycleAuthorityError.unsupportedIntent
        }

        let lifecycleTransaction: JournalTransactionReceipt
        do {
            let transaction = try await journal.transactAtCurrentSequence(
                lifecycleCommand,
                commandID: request.lifecycleCommandID,
                issuedAt: Date(),
                actor: actorIdentity
            )
            guard !transaction.duplicate else {
                throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
            }
            lifecycleTransaction = transaction
        } catch {
            throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
        }

        // Enter draining before the second journal boundary. If that boundary
        // fails, the supervisor remains safely closed to new productive work.
        let observedAt = Date()
        let observedAtMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
        let drain = await supervisor.beginDrainReceipt(
            request.intent,
            receiptID: request.drainReceiptID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
        let drainTransaction: JournalTransactionReceipt
        do {
            let transaction = try await journal.transactAtCurrentSequence(
                .recordRuntimeDrain(.issuedByLifecycleRuntime(
                    drain,
                    issuer: .init()
                )),
                commandID: request.drainCommandID,
                issuedAt: observedAt,
                actor: actorIdentity
            )
            guard !transaction.duplicate else {
                throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
            }
            drainTransaction = transaction
        } catch {
            throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
        }
        return JournaledRuntimeDrainTransitionReceipt(
            lifecycleTransaction: lifecycleTransaction,
            drain: drain,
            drainTransaction: drainTransaction,
            cleanupPlan: await supervisor.cleanupPlan()
        )
    }

    /// Recovers only the second half of the lifecycle boundary when the stop
    /// request is durable but its runtime-drain frame is absent. This never
    /// replays the lifecycle command and cannot change the retained intent.
    func resumeRetainedStopDrain(
        _ request: JournaledRuntimeDrainRequest
    ) async throws -> JournaledRuntimeDrainTransitionReceipt {
        let state = await journal.state
        guard request.intent == .stop,
              state.phase == .stopRequested,
              state.lastRuntimeDrainReceiptID == nil else {
            throw JournaledRuntimeLifecycleAuthorityError
                .retainedLifecycleRequestUnavailable
        }
        let observedAt = Date()
        let observedAtMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
        let drain = await supervisor.beginDrainReceipt(
            .stop,
            receiptID: request.drainReceiptID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
        let drainTransaction: JournalTransactionReceipt
        do {
            let transaction = try await journal.transactAtCurrentSequence(
                .recordRuntimeDrain(.issuedByLifecycleRuntime(
                    drain,
                    issuer: .init()
                )),
                commandID: request.drainCommandID,
                issuedAt: observedAt,
                actor: actorIdentity
            )
            guard !transaction.duplicate else {
                throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
            }
            drainTransaction = transaction
        } catch {
            throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
        }
        return JournaledRuntimeDrainTransitionReceipt(
            lifecycleTransaction: nil,
            drain: drain,
            drainTransaction: drainTransaction,
            cleanupPlan: await supervisor.cleanupPlan()
        )
    }

    func recordQuiescence(
        _ request: JournaledRuntimeQuiescenceRequest
    ) async throws -> JournaledRuntimeQuiescenceTransitionReceipt {
        let observedAt = Date()
        let observedAtMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
        let decision = await supervisor.quiescenceReceipt(
            id: request.receiptID,
            observedAt: observedAt,
            monotonicNanoseconds: observedAtMonotonicNanoseconds
        )
        let receipt: QuiescenceReceipt
        switch decision {
        case .issued(let issued):
            receipt = issued
        case .notDraining:
            throw JournaledRuntimeLifecycleAuthorityError.supervisorNotDraining
        case .resourcesRemain(let resources):
            throw JournaledRuntimeLifecycleAuthorityError.resourcesRemain(resources)
        case .failedReleasesRemain(let resources):
            throw JournaledRuntimeLifecycleAuthorityError.failedReleasesRemain(resources)
        case .queuedCleanupRemains(let leases):
            throw JournaledRuntimeLifecycleAuthorityError.queuedCleanupRemains(leases)
        }
        let transaction: JournalTransactionReceipt
        do {
            let accepted = try await journal.transactAtCurrentSequence(
                .recordQuiescence(.issuedByLifecycleRuntime(
                    receipt,
                    issuer: .init()
                )),
                commandID: request.commandID,
                issuedAt: observedAt,
                actor: actorIdentity
            )
            guard !accepted.duplicate else {
                throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
            }
            transaction = accepted
        } catch {
            throw JournaledRuntimeLifecycleAuthorityError.journalWriteFailed
        }
        return JournaledRuntimeQuiescenceTransitionReceipt(
            quiescence: receipt,
            journalTransaction: transaction
        )
    }
}
