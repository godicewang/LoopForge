import CryptoKit
import Foundation

/// File-owned, non-serializable proof that a generic runtime fact came from
/// the journaled workspace-mutation lease authority. The token never leaves
/// this file and cannot be reconstructed from persisted lease receipts.
struct JournaledWorkspaceMutationRuntimeCommandIssuer: Sendable {
    fileprivate init() {}
}

enum WorkspaceMutationLeaseOperation: String, Codable, Hashable, Sendable {
    case apply
    case rollback
}

struct JournaledWorkspaceMutationLeaseAdmission: Sendable {
    var runtimeAdmission: RuntimeAdmissionReceipt
    var journalTransaction: JournalTransactionReceipt
    var executionLease: WorkspaceMutationExecutionLease
}

struct JournaledWorkspaceMutationLeaseRelease: Sendable {
    var runtimeRelease: RuntimeReleaseOutcomeReceipt
    var journalTransaction: JournalTransactionReceipt
}

struct JournaledWorkspaceMutationLeaseFailure: Sendable {
    var runtimeFailure: RuntimeReleaseOutcomeReceipt
    var journalTransaction: JournalTransactionReceipt
}

enum JournaledWorkspaceMutationLeaseAuthorityError: Error, Codable, Equatable, Sendable {
    case invalidRequest(String)
    case transactionMissing
    case transactionPhaseRejected(IntegrationTransactionPhase)
    case admissionConflict
    case admissionRejected(RuntimeAdmissionRejection)
    case journalWriteFailed
    case journalProjectionDiverged
    case supervisorCommitFailed
    case authorityExpired
    case authorityNotLive
    case releaseRejected(RuntimeReleaseRejection)
}

/// Trusted issuer and validator for the only lease that may authorize a
/// workspace mutation. The receipt is journaled before supervisor commit and
/// remains bound to one run, transaction, attempt, workspace, and canonical
/// root identity. Callers can transport this lease, but cannot mint it.
actor JournaledWorkspaceMutationLeaseAuthority {
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

    func admit(
        transactionID: IntegrationTransactionID,
        workspaceID: WorkspaceID,
        rootIdentity: ContentDigest,
        operation: WorkspaceMutationLeaseOperation,
        leaseID: ResourceLeaseID,
        admissionReceiptID: ReceiptID,
        admissionCommandID: RunCommandID,
        issuedAt: Date,
        expiresAt: Date,
        requestedAtMonotonicNanoseconds: UInt64,
        expiresAtMonotonicNanoseconds: UInt64
    ) async throws -> JournaledWorkspaceMutationLeaseAdmission {
        guard !transactionID.rawValue.isEmpty,
              !workspaceID.rawValue.isEmpty,
              !rootIdentity.rawValue.isEmpty,
              !leaseID.rawValue.isEmpty,
              !admissionReceiptID.rawValue.isEmpty,
              !admissionCommandID.rawValue.isEmpty,
              expiresAt > issuedAt,
              expiresAtMonotonicNanoseconds > requestedAtMonotonicNanoseconds else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.invalidRequest(
                "incomplete identity or non-positive lifetime"
            )
        }
        guard let transaction = await journal.integrationTransaction(
            transactionID: transactionID
        ) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.transactionMissing
        }
        let request = Self.runtimeRequest(
            runID: journal.runID,
            transaction: transaction,
            workspaceID: workspaceID,
            rootIdentity: rootIdentity,
            leaseID: leaseID,
            requestedAtMonotonicNanoseconds: requestedAtMonotonicNanoseconds,
            expiresAtMonotonicNanoseconds: expiresAtMonotonicNanoseconds
        )
        let expectedExpiry = Self.wallExpiry(
            issuedAt: issuedAt,
            requestedAtMonotonicNanoseconds: requestedAtMonotonicNanoseconds,
            expiresAtMonotonicNanoseconds: expiresAtMonotonicNanoseconds
        )
        guard abs(expectedExpiry.timeIntervalSince(expiresAt)) < 0.000_001 else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.invalidRequest(
                "wall and monotonic lifetimes differ"
            )
        }

        // A crash can occur after the admission frame reaches stable storage
        // but before the in-memory supervisor accepts the same receipt. Exact
        // replay must reconstruct that live authority from the journal rather
        // than previewing a second admission (which would look like a
        // conflicting duplicate to a restored supervisor).
        if let recorded = await journal.runtimeAdmissionReceipt(
            receiptID: admissionReceiptID
        ) {
            try Self.validatePhase(
                transaction.phase,
                operation: operation,
                beforeEffect: false
            )
            guard recorded.request == request,
                  recorded.observedAt == issuedAt,
                  recorded.observedAtMonotonicNanoseconds ==
                    requestedAtMonotonicNanoseconds,
                  var journalTransaction = await journal.transactionReceipt(
                    commandID: admissionCommandID
                  ), await journal.runtimeAdmissionReceipt(
                    transaction: journalTransaction
                  ) == recorded else {
                throw JournaledWorkspaceMutationLeaseAuthorityError
                    .admissionConflict
            }
            switch recorded.outcome {
            case .rejected(let rejection):
                throw JournaledWorkspaceMutationLeaseAuthorityError
                    .admissionRejected(rejection)
            case .accepted(let admittedLease, _):
                guard admittedLease.request == request else {
                    throw JournaledWorkspaceMutationLeaseAuthorityError
                        .admissionConflict
                }
            }
            try await reconcileSupervisorFromJournal()
            let projection = await supervisor.projection()
            guard case .accepted(let admittedLease, _) = recorded.outcome,
                  projection.liveLeases.contains(admittedLease) else {
                throw JournaledWorkspaceMutationLeaseAuthorityError
                    .authorityNotLive
            }
            let executionLease = WorkspaceMutationExecutionLease(
                receiptID: recorded.id,
                transactionID: transactionID,
                workspaceID: workspaceID,
                rootIdentity: rootIdentity,
                exclusive: true,
                remoteAccessDisabled: true,
                issuedAt: issuedAt,
                expiresAt: expiresAt
            )
            try await validate(
                executionLease,
                operation: operation,
                at: issuedAt,
                atMonotonicNanoseconds: requestedAtMonotonicNanoseconds
            )
            journalTransaction.duplicate = true
            return JournaledWorkspaceMutationLeaseAdmission(
                runtimeAdmission: recorded,
                journalTransaction: journalTransaction,
                executionLease: executionLease
            )
        }

        try Self.validatePhase(
            transaction.phase,
            operation: operation,
            beforeEffect: true
        )

        let candidate = await supervisor.previewAdmissionReceipt(
            request,
            receiptID: admissionReceiptID,
            observedAt: issuedAt,
            observedAtMonotonicNanoseconds: requestedAtMonotonicNanoseconds
        )
        let journalTransaction: JournalTransactionReceipt
        do {
            journalTransaction = try await journal.transactAtCurrentSequence(
                .recordRuntimeAdmission(.issuedByWorkspaceMutationRuntime(
                    candidate,
                    issuer: .init()
                )),
                commandID: admissionCommandID,
                issuedAt: issuedAt,
                actor: actorIdentity
            )
        } catch {
            throw JournaledWorkspaceMutationLeaseAuthorityError.journalWriteFailed
        }
        guard let recorded = await journal.runtimeAdmissionReceipt(
            receiptID: admissionReceiptID
        ), recorded.request == request,
           recorded.observedAt == issuedAt,
           recorded.observedAtMonotonicNanoseconds == requestedAtMonotonicNanoseconds else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.admissionConflict
        }
        guard await supervisor.applyAdmissionReceipt(recorded) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.supervisorCommitFailed
        }
        guard case .accepted = recorded.outcome else {
            if case .rejected(let rejection) = recorded.outcome {
                throw JournaledWorkspaceMutationLeaseAuthorityError.admissionRejected(rejection)
            }
            preconditionFailure("RuntimeAdmissionOutcome is exhaustive")
        }

        let executionLease = WorkspaceMutationExecutionLease(
            receiptID: recorded.id,
            transactionID: transactionID,
            workspaceID: workspaceID,
            rootIdentity: rootIdentity,
            exclusive: true,
            remoteAccessDisabled: true,
            issuedAt: issuedAt,
            expiresAt: expiresAt
        )
        try await validate(
            executionLease,
            operation: operation,
            at: issuedAt,
            atMonotonicNanoseconds: requestedAtMonotonicNanoseconds
        )
        return JournaledWorkspaceMutationLeaseAdmission(
            runtimeAdmission: recorded,
            journalTransaction: journalTransaction,
            executionLease: executionLease
        )
    }

    func validate(
        _ lease: WorkspaceMutationExecutionLease,
        operation: WorkspaceMutationLeaseOperation,
        at observedAt: Date,
        atMonotonicNanoseconds: UInt64
    ) async throws {
        guard lease.exclusive,
              lease.remoteAccessDisabled,
              !lease.receiptID.rawValue.isEmpty,
              !lease.transactionID.rawValue.isEmpty,
              !lease.workspaceID.rawValue.isEmpty,
              !lease.rootIdentity.rawValue.isEmpty,
              observedAt >= lease.issuedAt,
              observedAt <= lease.expiresAt else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityExpired
        }
        guard let transaction = await journal.integrationTransaction(
            transactionID: lease.transactionID
        ) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.transactionMissing
        }
        try Self.validatePhase(transaction.phase, operation: operation, beforeEffect: false)
        guard let admission = await journal.runtimeAdmissionReceipt(
            receiptID: lease.receiptID
        ), case .accepted(let admittedLease, _) = admission.outcome else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        let request = admittedLease.request
        let expected = Self.runtimeRequest(
            runID: journal.runID,
            transaction: transaction,
            workspaceID: lease.workspaceID,
            rootIdentity: lease.rootIdentity,
            leaseID: request.leaseID,
            requestedAtMonotonicNanoseconds: request.requestedAtMonotonicNanoseconds,
            expiresAtMonotonicNanoseconds:
                request.renewalDeadlineMonotonicNanoseconds ?? 0
        )
        guard admission.request == request,
              request == expected,
              admission.observedAt == lease.issuedAt,
              admission.observedAtMonotonicNanoseconds ==
                request.requestedAtMonotonicNanoseconds,
              let deadline = request.renewalDeadlineMonotonicNanoseconds,
              atMonotonicNanoseconds >= request.requestedAtMonotonicNanoseconds,
              atMonotonicNanoseconds <= deadline,
              abs(Self.wallExpiry(
                issuedAt: lease.issuedAt,
                requestedAtMonotonicNanoseconds: request.requestedAtMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds: deadline
              ).timeIntervalSince(lease.expiresAt)) < 0.000_001,
              await journal.runtimeLease(resourceID: request.resourceID) == admittedLease else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        try await reconcileSupervisorFromJournal()
        let projection = await supervisor.projection()
        guard projection.liveLeases.first(where: {
            $0.request.resourceID == request.resourceID
        }) == admittedLease else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
    }

    func release(
        _ lease: WorkspaceMutationExecutionLease,
        receiptID: ReceiptID,
        commandID: RunCommandID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) async throws -> JournaledWorkspaceMutationLeaseRelease {
        guard let admission = await journal.runtimeAdmissionReceipt(
            receiptID: lease.receiptID
        ), case .accepted(let runtimeLease, _) = admission.outcome,
           admission.observedAt == lease.issuedAt,
           runtimeLease.request.renewalDeadlineMonotonicNanoseconds.map({
               $0 > runtimeLease.request.requestedAtMonotonicNanoseconds
           }) == true,
           runtimeLease.request.resourceID == Self.resourceID(
            workspaceID: lease.workspaceID,
            rootIdentity: lease.rootIdentity
           ), runtimeLease.request.occurrenceID?.rawValue == lease.transactionID.rawValue,
           runtimeLease.request.renewalDeadlineMonotonicNanoseconds.map({
               abs(Self.wallExpiry(
                issuedAt: lease.issuedAt,
                requestedAtMonotonicNanoseconds:
                    runtimeLease.request.requestedAtMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds: $0
               ).timeIntervalSince(lease.expiresAt)) < 0.000_001
           }) == true else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        if let recordedRelease = await journal.runtimeReleaseReceipt(
            receiptID: receiptID
        ) {
            guard recordedRelease.id == receiptID,
                  recordedRelease.resourceID == runtimeLease.request.resourceID,
                  case .released = recordedRelease.outcome,
                  await journal.runtimeLease(
                    resourceID: runtimeLease.request.resourceID
                  ) == nil,
                  let transaction = await journal.transactionReceipt(
                    commandID: commandID
                  ) else {
                throw JournaledWorkspaceMutationLeaseAuthorityError.admissionConflict
            }
            let projection = await supervisor.projection()
            if projection.liveLeases.contains(where: { $0 == runtimeLease }) {
                guard await supervisor.applyReleaseOutcomeReceipt(recordedRelease) else {
                    throw JournaledWorkspaceMutationLeaseAuthorityError.supervisorCommitFailed
                }
            } else if projection.liveLeases.contains(where: {
                $0.request.resourceID == runtimeLease.request.resourceID
            }) {
                throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
            }
            guard !(await supervisor.projection()).liveLeases.contains(where: {
                $0.request.resourceID == runtimeLease.request.resourceID
            }) else {
                throw JournaledWorkspaceMutationLeaseAuthorityError.supervisorCommitFailed
            }
            return JournaledWorkspaceMutationLeaseRelease(
                runtimeRelease: recordedRelease,
                journalTransaction: transaction
            )
        }
        guard await journal.runtimeLease(
            resourceID: runtimeLease.request.resourceID
        ) == runtimeLease else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        try await reconcileSupervisorFromJournal()
        let release = await supervisor.previewReleaseOutcomeReceipt(
            resourceID: runtimeLease.request.resourceID,
            leaseID: runtimeLease.request.leaseID,
            receiptID: receiptID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
        guard case .released = release.outcome else {
            if case .rejected(let rejection) = release.outcome {
                throw JournaledWorkspaceMutationLeaseAuthorityError.releaseRejected(rejection)
            }
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        let transaction: JournalTransactionReceipt
        do {
            transaction = try await journal.transactAtCurrentSequence(
                .recordRuntimeRelease(.issuedByWorkspaceMutationRuntime(
                    release,
                    issuer: .init()
                )),
                commandID: commandID,
                issuedAt: observedAt,
                actor: actorIdentity
            )
        } catch {
            throw JournaledWorkspaceMutationLeaseAuthorityError.journalWriteFailed
        }
        guard await supervisor.applyReleaseOutcomeReceipt(release) else {
            await supervisor.markReleaseFailed(resourceID: runtimeLease.request.resourceID)
            throw JournaledWorkspaceMutationLeaseAuthorityError.supervisorCommitFailed
        }
        guard await journal.runtimeLease(resourceID: runtimeLease.request.resourceID) == nil else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.journalProjectionDiverged
        }
        return JournaledWorkspaceMutationLeaseRelease(
            runtimeRelease: release,
            journalTransaction: transaction
        )
    }

    func recordReleaseFailure(
        _ lease: WorkspaceMutationExecutionLease,
        receiptID: ReceiptID,
        commandID: RunCommandID,
        reasonDigest: ContentDigest,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) async throws -> JournaledWorkspaceMutationLeaseFailure {
        guard !reasonDigest.rawValue.isEmpty,
              let admission = await journal.runtimeAdmissionReceipt(
                receiptID: lease.receiptID
              ), case .accepted(let runtimeLease, _) = admission.outcome,
              admission.observedAt == lease.issuedAt,
              runtimeLease.request.resourceID == Self.resourceID(
                workspaceID: lease.workspaceID,
                rootIdentity: lease.rootIdentity
              ), runtimeLease.request.occurrenceID?.rawValue == lease.transactionID.rawValue else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        if let recorded = await journal.runtimeReleaseReceipt(receiptID: receiptID) {
            guard recorded.runID == journal.runID,
                  recorded.resourceID == runtimeLease.request.resourceID,
                  recorded.leaseID == runtimeLease.request.leaseID,
                  recorded.outcome == .cleanupFailed(reasonDigest: reasonDigest),
                  let transaction = await journal.transactionReceipt(commandID: commandID)
            else {
                throw JournaledWorkspaceMutationLeaseAuthorityError.admissionConflict
            }
            var projection = await supervisor.projection()
            if !projection.liveLeases.contains(runtimeLease) {
                try await reconcileSupervisorFromJournal()
                projection = await supervisor.projection()
            }
            guard projection.liveLeases.contains(runtimeLease) else {
                throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
            }
            if !projection.failedReleases.contains(runtimeLease.request.resourceID) {
                guard await supervisor.applyReleaseOutcomeReceipt(recorded) else {
                    throw JournaledWorkspaceMutationLeaseAuthorityError.supervisorCommitFailed
                }
            }
            return JournaledWorkspaceMutationLeaseFailure(
                runtimeFailure: recorded,
                journalTransaction: transaction
            )
        }
        guard await journal.runtimeLease(
            resourceID: runtimeLease.request.resourceID
        ) == runtimeLease else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        try await reconcileSupervisorFromJournal()
        let failure = await supervisor.previewReleaseFailureReceipt(
            resourceID: runtimeLease.request.resourceID,
            leaseID: runtimeLease.request.leaseID,
            receiptID: receiptID,
            reasonDigest: reasonDigest,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
        guard failure.outcome == .cleanupFailed(reasonDigest: reasonDigest) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        let transaction: JournalTransactionReceipt
        do {
            transaction = try await journal.transactAtCurrentSequence(
                .recordRuntimeRelease(.issuedByWorkspaceMutationRuntime(
                    failure,
                    issuer: .init()
                )),
                commandID: commandID,
                issuedAt: observedAt,
                actor: actorIdentity
            )
        } catch {
            throw JournaledWorkspaceMutationLeaseAuthorityError.journalWriteFailed
        }
        guard await supervisor.applyReleaseOutcomeReceipt(failure),
              await journal.runtimeReleaseFailed(
                resourceID: runtimeLease.request.resourceID
              ), (await supervisor.projection()).failedReleases.contains(
                runtimeLease.request.resourceID
              ) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.supervisorCommitFailed
        }
        return JournaledWorkspaceMutationLeaseFailure(
            runtimeFailure: failure,
            journalTransaction: transaction
        )
    }

    /// Rehydrates a pristine supervisor from the journal head after a crash.
    /// Any partially-mutated or conflicting supervisor is rejected rather than
    /// overwritten, preserving a visible in-doubt ownership state.
    func reconcileSupervisorFromJournal() async throws {
        let snapshot = await journal.runtimeSupervisorRecoverySnapshot()
        let projection = await supervisor.projection()
        if projection.phase == snapshot.phase,
           projection.liveLeases == snapshot.liveLeases,
           projection.failedReleases == snapshot.failedReleases {
            return
        }
        guard case .restored = await supervisor.restore(from: snapshot) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
        let restored = await supervisor.projection()
        guard restored.phase == snapshot.phase,
              restored.liveLeases == snapshot.liveLeases,
              restored.failedReleases == snapshot.failedReleases else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive
        }
    }

    static func resourceID(
        workspaceID: WorkspaceID,
        rootIdentity: ContentDigest
    ) -> OwnedResourceID {
        // One workspace identity owns one exclusive mutation lane. The live
        // root identity remains bound in the lease's external identity and is
        // revalidated by the executor, but must not partition exclusivity: a
        // replaced directory inode is a rejection signal, never a second lane.
        let material = "workspace-mutation\u{0}" + workspaceID.rawValue
        let digest = SHA256.hash(data: Data(material.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        return OwnedResourceID("workspace-mutation-" + digest)
    }

    private static let reservation = ResourceVector(
        cpuWeight: 0,
        memoryBytes: 0,
        diskIOWeight: 1,
        gpuWeight: 0,
        networkWeight: 0,
        guiSessionCount: 0,
        processCount: 0
    )

    private static func runtimeRequest(
        runID: KernelRunID,
        transaction: IntegrationTransactionState,
        workspaceID: WorkspaceID,
        rootIdentity: ContentDigest,
        leaseID: ResourceLeaseID,
        requestedAtMonotonicNanoseconds: UInt64,
        expiresAtMonotonicNanoseconds: UInt64
    ) -> RuntimeLeaseRequest {
        RuntimeLeaseRequest(
            leaseID: leaseID,
            resourceID: resourceID(workspaceID: workspaceID, rootIdentity: rootIdentity),
            runID: runID,
            occurrenceID: OccurrenceID(transaction.proposal.transactionID.rawValue),
            attemptID: transaction.proposal.attemptID,
            kind: .workspaceMutation,
            purpose: .productive,
            ownership: .owned,
            releasePolicy: .join,
            externalIdentity: RuntimeExternalIdentity(
                stableDigest: rootIdentity,
                processID: nil,
                processStartMonotonicNanoseconds: nil,
                processStartSystemNanoseconds: nil,
                parentResourceID: nil
            ),
            reservation: reservation,
            requestedAtMonotonicNanoseconds: requestedAtMonotonicNanoseconds,
            renewalDeadlineMonotonicNanoseconds: expiresAtMonotonicNanoseconds,
            progressReceiptID: nil
        )
    }

    private static func validatePhase(
        _ phase: IntegrationTransactionPhase,
        operation: WorkspaceMutationLeaseOperation,
        beforeEffect: Bool
    ) throws {
        let valid: Set<IntegrationTransactionPhase>
        switch operation {
        case .apply:
            valid = beforeEffect ? [.rollbackPrepared] : [.rollbackPrepared, .applying]
        case .rollback:
            valid = beforeEffect
                ? [.rollbackRequired, .appliedUnverified, .postimageVerified]
                : [.rollbackRequired, .appliedUnverified, .postimageVerified, .rollingBack]
        }
        guard valid.contains(phase) else {
            throw JournaledWorkspaceMutationLeaseAuthorityError.transactionPhaseRejected(phase)
        }
    }

    private static func wallExpiry(
        issuedAt: Date,
        requestedAtMonotonicNanoseconds: UInt64,
        expiresAtMonotonicNanoseconds: UInt64
    ) -> Date {
        let delta = expiresAtMonotonicNanoseconds - requestedAtMonotonicNanoseconds
        return issuedAt.addingTimeInterval(Double(delta) / 1_000_000_000)
    }
}
