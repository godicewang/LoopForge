import CryptoKit
import Foundation

/// Non-serializable authority for one integration transition. Production
/// construction is file-private to the journaled workspace runtime, after it
/// has validated exact live lease ownership. Other transition issuers remain
/// absent until their independent runtimes are composed.
struct AuthorizedKernelIntegrationTransition: Sendable {
    let transition: IntegrationTransitionCommand
    let issuer: KernelIntegrationTransitionIssuer

    private init(
        transition: IntegrationTransitionCommand,
        issuer: KernelIntegrationTransitionIssuer
    ) {
        self.transition = transition
        self.issuer = issuer
    }

    fileprivate static func runtimeIssued(
        _ transition: IntegrationTransitionCommand
    ) -> AuthorizedKernelIntegrationTransition {
        AuthorizedKernelIntegrationTransition(
            transition: transition,
            issuer: .workspaceMutationRuntime
        )
    }

    static func issuedByProcessRuntime(
        _ transition: IntegrationTransitionCommand,
        issuer: JournaledProcessRuntimeCommandIssuer
    ) -> AuthorizedKernelIntegrationTransition {
        AuthorizedKernelIntegrationTransition(
            transition: transition,
            issuer: .processRuntime
        )
    }

    static func issuedByCompletedCandidatePreflightRuntime(
        _ transition: IntegrationTransitionCommand,
        rehearsal:
            AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal,
        preflight: AuthorizedMutationPreflight
    ) -> AuthorizedKernelIntegrationTransition? {
        guard rehearsal.validationIssues().isEmpty,
              preflight.manifest == rehearsal.manifest else {
            return nil
        }
        switch transition {
        case .propose(let proposal):
            let receipt = rehearsal.receipt
            let manifest = rehearsal.manifest
            guard proposal.runID == receipt.runID,
                  proposal.transactionID == manifest.transactionID,
                  proposal.candidateID == manifest.candidateID,
                  proposal.attemptID == receipt.attemptID,
                  proposal.nodeID == receipt.nodeID,
                  proposal.contractDigest == manifest.contractDigest,
                  proposal.planNodeDigest == manifest.planNodeDigest,
                  proposal.manifestDigest == receipt.forwardManifestDigest,
                  proposal.canonicalPreimageDigest ==
                    manifest.basePreimageDigest,
                  proposal.expectedPostimageDigest ==
                    manifest.expectedPostimageDigest,
                  proposal.proposedAt >= receipt.rehearsedAt else {
                return nil
            }
        case .acceptPreflight(let receipt, let rollback):
            guard TransactionalMutationKernel.preflight(preflight) ==
                .admitted(receipt: receipt, rollback: rollback),
                  rollback == rehearsal.rollbackManifest else {
                return nil
            }
        case .startApply, .recordApply, .recordPostimageVerification,
             .recordIndependentAcceptance, .requestRollback,
             .recordRollback:
            return nil
        }
        return AuthorizedKernelIntegrationTransition(
            transition: transition,
            issuer: .completedCandidatePreflightRuntime
        )
    }

    static func issuedByCompletedCandidateApplyPreparationRuntime(
        _ transition: IntegrationTransitionCommand,
        preflight: AuthorizedWorkspaceCompletedCandidateMutationPreflight,
        admission: JournaledWorkspaceMutationLeaseAdmission
    ) -> AuthorizedKernelIntegrationTransition? {
        guard preflight.validationIssues().isEmpty,
              case .accepted(let runtimeLease, _) =
                admission.runtimeAdmission.outcome,
              runtimeLease.request.runID == preflight.proposal.runID,
              runtimeLease.request.occurrenceID?.rawValue ==
                preflight.proposal.transactionID.rawValue,
              runtimeLease.request.attemptID == preflight.proposal.attemptID,
              runtimeLease.request.kind == .workspaceMutation,
              runtimeLease.request.purpose == .productive,
              runtimeLease.request.ownership == .owned,
              runtimeLease.request.releasePolicy == .join,
              runtimeLease.request.externalIdentity?.stableDigest ==
                admission.executionLease.rootIdentity,
              runtimeLease.request.renewalDeadlineMonotonicNanoseconds != nil,
              admission.executionLease.receiptID ==
                admission.runtimeAdmission.id,
              admission.executionLease.transactionID ==
                preflight.proposal.transactionID,
              admission.executionLease.workspaceID ==
                preflight.rehearsal.receipt.workspaceID,
              admission.executionLease.exclusive,
              admission.executionLease.remoteAccessDisabled else {
            return nil
        }
        guard case .startApply(let intent) = transition,
              intent.transactionID == preflight.proposal.transactionID,
              intent.preflightReceiptID == preflight.receipt.id,
              intent.manifestDigest ==
                preflight.rehearsal.receipt.forwardManifestDigest,
              intent.canonicalPreimageDigest ==
                preflight.proposal.canonicalPreimageDigest,
              intent.rollbackManifestDigest ==
                preflight.rehearsal.receipt.rollbackManifestDigest,
              intent.stagedObjectSetDigest ==
                preflight.rehearsal.receipt.contentObjectSetDigest,
              intent.exclusiveLeaseReceiptID ==
                admission.executionLease.receiptID,
              intent.remoteAccessDisabled,
              intent.requestedAt == admission.executionLease.issuedAt,
              intent.candidatePostimageCapturePolicyDigest ==
                preflight.rehearsal.preparation.proposal.contentStore.receipt
                    .derivation.capturePolicyDigest else {
            return nil
        }
        return AuthorizedKernelIntegrationTransition(
            transition: transition,
            issuer: .completedCandidateApplyPreparationRuntime
        )
    }

#if DEBUG
    static func testOnly(
        _ transition: IntegrationTransitionCommand
    ) -> AuthorizedKernelIntegrationTransition {
        AuthorizedKernelIntegrationTransition(
            transition: transition,
            issuer: .testOnly
        )
    }
#endif
}

enum KernelIntegrationTransitionIssuer: Equatable, Sendable {
    case workspaceMutationRuntime
    case processRuntime
    case completedCandidatePreflightRuntime
    case completedCandidateApplyPreparationRuntime
    case testOnly
}

struct JournaledWorkspaceApplyResult: Sendable {
    var startTransaction: JournalTransactionReceipt?
    var applyReceipt: IntegrationApplyReceipt
    var recordTransaction: JournalTransactionReceipt?
    var release: JournaledWorkspaceMutationLeaseRelease
    var recoveredFromJournal: Bool
    var treeGenerationReceipt: WorkspaceTreeGenerationReceipt?
    var candidatePostimageAttestation:
        WorkspaceCandidatePostimageAttestationReceipt?
}

struct JournaledWorkspaceRollbackResult: Sendable {
    var startTransaction: JournalTransactionReceipt?
    var rollbackReceipt: IntegrationRollbackReceipt
    var recordTransaction: JournalTransactionReceipt?
    var release: JournaledWorkspaceMutationLeaseRelease
    var recoveredFromJournal: Bool
    var treeGenerationReceipt: WorkspaceTreeGenerationReceipt?
}

enum JournaledWorkspaceMutationRuntimeError: Error, Codable, Equatable {
    case actorMismatch
    case transactionMissing
    case intentMismatch
    case invalidPhase(IntegrationTransactionPhase)
    case journalWriteFailed
    case journalProjectionDiverged
    case authorityUnavailable
    case authorityRejected
    case authorityReleaseFailed
    case failedOwnershipRequiresRepair(OwnedResourceID)
    case preEffectRejectedAndReleased(WorkspaceMutationPreEffectRejection)
    case executionFailed(WorkspaceMutationExecutionError)
    case unexpectedExecutionFailure
}

enum WorkspaceMutationPreEffectRejection: String, Codable, Equatable, Sendable {
    case leaseExpired
}

struct WorkspaceMutationEffectDispatchFailure: Codable, Equatable, Sendable {
    var intentID: IntegrationEffectIntentID
    var error: JournaledWorkspaceMutationRuntimeError
}

struct WorkspaceMutationEffectDispatchReport: Equatable, Sendable {
    var scannedCount: Int
    var completedIntentIDs: [IntegrationEffectIntentID]
    var quarantinedIntentIDs: [IntegrationEffectIntentID] = []
    var failures: [WorkspaceMutationEffectDispatchFailure]
    var treeGenerationReceipts: [WorkspaceTreeGenerationReceipt] = []
    var candidatePostimageAttestations:
        [WorkspaceCandidatePostimageAttestationReceipt] = []
}

/// Journal-first coordinator for bounded workspace effects.
///
/// An effect intent is durable before the executor may touch the workspace.
/// Recovery first consults the journal: an already-recorded receipt is returned
/// without re-entering the filesystem executor. An in-flight intent is replayed
/// only through the executor's content-addressed recovery checkpoint.
actor JournaledWorkspaceMutationRuntime {
    private let journal: RunJournal
    private let executor: WorkspaceMutationFilesystemExecutor
    private let actorIdentity: ActorIdentity
    private let authority: JournaledWorkspaceMutationLeaseAuthority?
    private let wallClock: @Sendable () -> Date
    private let monotonicClock: @Sendable () -> UInt64

    init(
        journal: RunJournal,
        executor: WorkspaceMutationFilesystemExecutor =
            WorkspaceMutationFilesystemExecutor(),
        actorIdentity: ActorIdentity,
        authority: JournaledWorkspaceMutationLeaseAuthority? = nil,
        wallClock: @escaping @Sendable () -> Date = { Date() },
        monotonicClock: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.journal = journal
        self.executor = executor
        self.actorIdentity = actorIdentity
        self.authority = authority
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
    }

    func apply(
        _ request: WorkspaceMutationExecutionRequest,
        startCommandID: RunCommandID,
        recordCommandID: RunCommandID,
        releaseReceiptID: ReceiptID,
        releaseCommandID: RunCommandID,
        failureReceiptID: ReceiptID,
        failureCommandID: RunCommandID
    ) async throws -> JournaledWorkspaceApplyResult {
        guard request.executor == actorIdentity else {
            throw JournaledWorkspaceMutationRuntimeError.actorMismatch
        }
        guard let initial = await journal.integrationTransaction(
            transactionID: request.manifest.transactionID
        ) else {
            throw JournaledWorkspaceMutationRuntimeError.transactionMissing
        }
        guard initial.proposal.transactionID == request.intent.transactionID else {
            throw JournaledWorkspaceMutationRuntimeError.intentMismatch
        }
        if let recorded = initial.applyReceipt {
            guard initial.applyIntent == request.intent,
                  recorded.intentID == request.intent.id else {
                throw JournaledWorkspaceMutationRuntimeError.intentMismatch
            }
            let release = try await releaseAuthority(
                request.lease,
                receiptID: releaseReceiptID,
                commandID: releaseCommandID
            )
            let treeGenerationReceipt = try await acceptedApplyGeneration(
                recorded,
                request: request
            )
            let candidatePostimageAttestation =
                try await acceptedCandidatePostimageAttestation(
                    recorded,
                    request: request
                )
            return JournaledWorkspaceApplyResult(
                startTransaction: nil,
                applyReceipt: recorded,
                recordTransaction: nil,
                release: release,
                recoveredFromJournal: true,
                treeGenerationReceipt: treeGenerationReceipt,
                candidatePostimageAttestation: candidatePostimageAttestation
            )
        }
        try await rejectFailedOwnership(request.lease)
        guard Self.requestClaimsLease(
            intentTransactionID: request.intent.transactionID,
            intentLeaseReceiptID: request.intent.exclusiveLeaseReceiptID,
            requestWorkspaceID: request.workspaceID,
            preimageWorkspaceID: request.preimage.workspaceID,
            lease: request.lease
        ) else {
            throw JournaledWorkspaceMutationRuntimeError.intentMismatch
        }
        let executionTime = wallClock()
        guard executionTime >= request.lease.issuedAt,
              executionTime <= request.lease.expiresAt else {
            try await retireExpiredPreEffect(
                request.lease,
                receiptID: releaseReceiptID,
                commandID: releaseCommandID
            )
        }
        guard let authority else {
            throw JournaledWorkspaceMutationRuntimeError.authorityUnavailable
        }
        do {
            try await authority.validate(
                request.lease,
                operation: .apply,
                at: executionTime,
                atMonotonicNanoseconds: monotonicClock()
            )
        } catch JournaledWorkspaceMutationLeaseAuthorityError.authorityExpired {
            try await retireExpiredPreEffect(
                request.lease,
                receiptID: releaseReceiptID,
                commandID: releaseCommandID
            )
        } catch {
            throw JournaledWorkspaceMutationRuntimeError.authorityRejected
        }

        let startTransaction: JournalTransactionReceipt?
        switch initial.phase {
        case .rollbackPrepared:
            do {
                startTransaction = try await journal.transactAtCurrentSequence(
                    .advanceIntegration(.runtimeIssued(.startApply(request.intent))),
                    commandID: startCommandID,
                    issuedAt: request.intent.requestedAt,
                    actor: actorIdentity
                )
            } catch {
                throw JournaledWorkspaceMutationRuntimeError.journalWriteFailed
            }
        case .applying:
            guard initial.applyIntent == request.intent else {
                throw JournaledWorkspaceMutationRuntimeError.intentMismatch
            }
            startTransaction = nil
        default:
            throw JournaledWorkspaceMutationRuntimeError.invalidPhase(initial.phase)
        }

        guard let applying = await journal.integrationTransaction(
            transactionID: request.manifest.transactionID
        ), applying.phase == .applying,
           applying.applyIntent == request.intent else {
            throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
        }

        // Completion time is an observation owned by the live runtime, not a
        // caller prediction sealed into a durable outbox payload. Recovery
        // artifacts retain the first completed timestamp, so replay after an
        // effect/journal crash still reconstructs the identical receipt.
        var executionRequest = request
        executionRequest.completedAt = executionTime
        let applyReceipt: IntegrationApplyReceipt
        do {
            applyReceipt = try executor.apply(executionRequest)
        } catch let error as WorkspaceMutationExecutionError {
            try await recordAuthorityFailure(
                request.lease,
                receiptID: failureReceiptID,
                commandID: failureCommandID,
                reasonDigest: Self.failureDigest(error)
            )
            throw JournaledWorkspaceMutationRuntimeError.executionFailed(error)
        } catch {
            try await recordAuthorityFailure(
                request.lease,
                receiptID: failureReceiptID,
                commandID: failureCommandID,
                reasonDigest: Self.failureDigest("unexpected-apply-execution-failure")
            )
            throw JournaledWorkspaceMutationRuntimeError.unexpectedExecutionFailure
        }

        let recordTransaction: JournalTransactionReceipt
        do {
            recordTransaction = try await journal.transactAtCurrentSequence(
                .advanceIntegration(.runtimeIssued(.recordApply(applyReceipt))),
                commandID: recordCommandID,
                issuedAt: applyReceipt.completedAt,
                actor: actorIdentity
            )
        } catch {
            throw JournaledWorkspaceMutationRuntimeError.journalWriteFailed
        }
        guard let recorded = await journal.integrationTransaction(
            transactionID: request.manifest.transactionID
        ), recorded.applyReceipt == applyReceipt else {
            throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
        }
        let release = try await releaseAuthority(
            request.lease,
            receiptID: releaseReceiptID,
            commandID: releaseCommandID
        )
        let treeGenerationReceipt = try await acceptedApplyGeneration(
            applyReceipt,
            request: request
        )
        let candidatePostimageAttestation =
            try await acceptedCandidatePostimageAttestation(
                applyReceipt,
                request: request
            )
        return JournaledWorkspaceApplyResult(
            startTransaction: startTransaction,
            applyReceipt: applyReceipt,
            recordTransaction: recordTransaction,
            release: release,
            recoveredFromJournal: false,
            treeGenerationReceipt: treeGenerationReceipt,
            candidatePostimageAttestation: candidatePostimageAttestation
        )
    }

    func rollback(
        _ request: WorkspaceMutationRollbackRequest,
        startCommandID: RunCommandID,
        recordCommandID: RunCommandID,
        releaseReceiptID: ReceiptID,
        releaseCommandID: RunCommandID,
        failureReceiptID: ReceiptID,
        failureCommandID: RunCommandID
    ) async throws -> JournaledWorkspaceRollbackResult {
        guard request.executor == actorIdentity else {
            throw JournaledWorkspaceMutationRuntimeError.actorMismatch
        }
        guard let initial = await journal.integrationTransaction(
            transactionID: request.manifest.transactionID
        ) else {
            throw JournaledWorkspaceMutationRuntimeError.transactionMissing
        }
        if let recorded = initial.rollbackReceipt {
            guard initial.rollbackIntent == request.intent,
                  recorded.intentID == request.intent.id else {
                throw JournaledWorkspaceMutationRuntimeError.intentMismatch
            }
            let release = try await releaseAuthority(
                request.lease,
                receiptID: releaseReceiptID,
                commandID: releaseCommandID
            )
            let treeGenerationReceipt = try await acceptedRollbackGeneration(
                recorded,
                request: request
            )
            return JournaledWorkspaceRollbackResult(
                startTransaction: nil,
                rollbackReceipt: recorded,
                recordTransaction: nil,
                release: release,
                recoveredFromJournal: true,
                treeGenerationReceipt: treeGenerationReceipt
            )
        }
        try await rejectFailedOwnership(request.lease)
        guard Self.requestClaimsLease(
            intentTransactionID: request.intent.transactionID,
            intentLeaseReceiptID: request.intent.exclusiveLeaseReceiptID,
            requestWorkspaceID: request.workspaceID,
            preimageWorkspaceID: request.preimage.workspaceID,
            lease: request.lease
        ) else {
            throw JournaledWorkspaceMutationRuntimeError.intentMismatch
        }
        let executionTime = wallClock()
        guard executionTime >= request.lease.issuedAt,
              executionTime <= request.lease.expiresAt else {
            try await retireExpiredPreEffect(
                request.lease,
                receiptID: releaseReceiptID,
                commandID: releaseCommandID
            )
        }
        guard let authority else {
            throw JournaledWorkspaceMutationRuntimeError.authorityUnavailable
        }
        do {
            try await authority.validate(
                request.lease,
                operation: .rollback,
                at: executionTime,
                atMonotonicNanoseconds: monotonicClock()
            )
        } catch JournaledWorkspaceMutationLeaseAuthorityError.authorityExpired {
            try await retireExpiredPreEffect(
                request.lease,
                receiptID: releaseReceiptID,
                commandID: releaseCommandID
            )
        } catch {
            throw JournaledWorkspaceMutationRuntimeError.authorityRejected
        }

        let startTransaction: JournalTransactionReceipt?
        switch initial.phase {
        case .rollbackRequired, .appliedUnverified, .postimageVerified:
            do {
                startTransaction = try await journal.transactAtCurrentSequence(
                    .advanceIntegration(.runtimeIssued(.requestRollback(request.intent))),
                    commandID: startCommandID,
                    issuedAt: request.intent.requestedAt,
                    actor: actorIdentity
                )
            } catch {
                throw JournaledWorkspaceMutationRuntimeError.journalWriteFailed
            }
        case .rollingBack:
            guard initial.rollbackIntent == request.intent else {
                throw JournaledWorkspaceMutationRuntimeError.intentMismatch
            }
            startTransaction = nil
        default:
            throw JournaledWorkspaceMutationRuntimeError.invalidPhase(initial.phase)
        }

        guard let rollingBack = await journal.integrationTransaction(
            transactionID: request.manifest.transactionID
        ), rollingBack.phase == .rollingBack,
           rollingBack.rollbackIntent == request.intent else {
            throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
        }

        var executionRequest = request
        executionRequest.completedAt = executionTime
        let rollbackReceipt: IntegrationRollbackReceipt
        do {
            rollbackReceipt = try executor.rollback(executionRequest)
        } catch let error as WorkspaceMutationExecutionError {
            try await recordAuthorityFailure(
                request.lease,
                receiptID: failureReceiptID,
                commandID: failureCommandID,
                reasonDigest: Self.failureDigest(error)
            )
            throw JournaledWorkspaceMutationRuntimeError.executionFailed(error)
        } catch {
            try await recordAuthorityFailure(
                request.lease,
                receiptID: failureReceiptID,
                commandID: failureCommandID,
                reasonDigest: Self.failureDigest("unexpected-rollback-execution-failure")
            )
            throw JournaledWorkspaceMutationRuntimeError.unexpectedExecutionFailure
        }

        let recordTransaction: JournalTransactionReceipt
        do {
            recordTransaction = try await journal.transactAtCurrentSequence(
                .advanceIntegration(.runtimeIssued(.recordRollback(rollbackReceipt))),
                commandID: recordCommandID,
                issuedAt: rollbackReceipt.completedAt,
                actor: actorIdentity
            )
        } catch {
            throw JournaledWorkspaceMutationRuntimeError.journalWriteFailed
        }
        guard let recorded = await journal.integrationTransaction(
            transactionID: request.manifest.transactionID
        ), recorded.rollbackReceipt == rollbackReceipt else {
            throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
        }
        let release = try await releaseAuthority(
            request.lease,
            receiptID: releaseReceiptID,
            commandID: releaseCommandID
        )
        let treeGenerationReceipt = try await acceptedRollbackGeneration(
            rollbackReceipt,
            request: request
        )
        return JournaledWorkspaceRollbackResult(
            startTransaction: startTransaction,
            rollbackReceipt: rollbackReceipt,
            recordTransaction: recordTransaction,
            release: release,
            recoveredFromJournal: false,
            treeGenerationReceipt: treeGenerationReceipt
        )
    }

    private func acceptedApplyGeneration(
        _ receipt: IntegrationApplyReceipt,
        request: WorkspaceMutationExecutionRequest
    ) async throws -> WorkspaceTreeGenerationReceipt? {
        guard case .exactPostimage = receipt.outcome else { return nil }
        do {
            let resolution = try await journal
                .latestAcceptedWorkspaceTreeGenerationReceipt(
                    workspaceID: request.workspaceID,
                    root: request.workspaceRoot
                )
            guard case .accepted(let generation) = resolution,
                  generation.authority == .journaledMutationCommit,
                  generation.generationDigest == receipt.observedPostimageDigest else {
                throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
            }
            return generation
        } catch {
            // The mutation receipt remains authoritative even when an older
            // journal used a non-SHA generation identity. Withhold cache
            // authority without turning successful recovery into a failure.
            return nil
        }
    }

    private func acceptedCandidatePostimageAttestation(
        _ receipt: IntegrationApplyReceipt,
        request: WorkspaceMutationExecutionRequest
    ) async throws -> WorkspaceCandidatePostimageAttestationReceipt? {
        guard case .exactPostimage = receipt.outcome,
              let candidatePostimage = receipt.candidatePostimage else {
            return nil
        }
        do {
            let resolution = try await journal
                .latestAcceptedWorkspaceCandidatePostimageAttestation(
                    workspaceID: request.workspaceID,
                    root: request.workspaceRoot
                )
            guard case .accepted(let attestation) = resolution,
                  attestation.applyReceiptID == receipt.id,
                  attestation.candidatePostimage == candidatePostimage else {
                throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
            }
            return attestation
        } catch {
            // Exact legacy journals and a newer ambiguous workspace transition
            // deliberately withhold verifier authority without rewriting the
            // already-recorded mutation receipt.
            return nil
        }
    }

    private func acceptedRollbackGeneration(
        _ receipt: IntegrationRollbackReceipt,
        request: WorkspaceMutationRollbackRequest
    ) async throws -> WorkspaceTreeGenerationReceipt? {
        guard case .restored = receipt.outcome else { return nil }
        do {
            let resolution = try await journal
                .latestAcceptedWorkspaceTreeGenerationReceipt(
                    workspaceID: request.workspaceID,
                    root: request.workspaceRoot
                )
            guard case .accepted(let generation) = resolution,
                  generation.authority == .journaledRecoveryReconciliation,
                  generation.generationDigest == receipt.observedPreimageDigest else {
                throw JournaledWorkspaceMutationRuntimeError.journalProjectionDiverged
            }
            return generation
        } catch {
            return nil
        }
    }

    private func releaseAuthority(
        _ lease: WorkspaceMutationExecutionLease,
        receiptID: ReceiptID,
        commandID: RunCommandID
    ) async throws -> JournaledWorkspaceMutationLeaseRelease {
        guard let authority else {
            throw JournaledWorkspaceMutationRuntimeError.authorityUnavailable
        }
        do {
            return try await authority.release(
                lease,
                receiptID: receiptID,
                commandID: commandID,
                observedAt: wallClock(),
                observedAtMonotonicNanoseconds: monotonicClock()
            )
        } catch {
            throw JournaledWorkspaceMutationRuntimeError.authorityReleaseFailed
        }
    }

    /// A cleanup failure means the preceding executor invocation may have
    /// partially mutated the workspace. The durable outbox may retain the
    /// request, but ordinary recovery must never re-enter that executor until
    /// a separate repair path has proved and journaled ownership resolution.
    private func rejectFailedOwnership(
        _ lease: WorkspaceMutationExecutionLease
    ) async throws {
        let resourceID = JournaledWorkspaceMutationLeaseAuthority.resourceID(
            workspaceID: lease.workspaceID,
            rootIdentity: lease.rootIdentity
        )
        guard !(await journal.runtimeReleaseFailed(resourceID: resourceID)) else {
            throw JournaledWorkspaceMutationRuntimeError
                .failedOwnershipRequiresRepair(resourceID)
        }
    }

    /// Expired authority cannot be renewed implicitly. Because this branch is
    /// reached before executor entry and only after the request proves it
    /// carries the exact admitted lease identity, the original lease is
    /// journal-released and the stale effect is retired for explicit replan.
    private func retireExpiredPreEffect(
        _ lease: WorkspaceMutationExecutionLease,
        receiptID: ReceiptID,
        commandID: RunCommandID
    ) async throws -> Never {
        _ = try await releaseAuthority(
            lease,
            receiptID: receiptID,
            commandID: commandID
        )
        throw JournaledWorkspaceMutationRuntimeError
            .preEffectRejectedAndReleased(.leaseExpired)
    }

    private static func requestClaimsLease(
        intentTransactionID: IntegrationTransactionID,
        intentLeaseReceiptID: ReceiptID,
        requestWorkspaceID: WorkspaceID,
        preimageWorkspaceID: WorkspaceID,
        lease: WorkspaceMutationExecutionLease
    ) -> Bool {
        intentTransactionID == lease.transactionID &&
            intentLeaseReceiptID == lease.receiptID &&
            requestWorkspaceID == lease.workspaceID &&
            preimageWorkspaceID == lease.workspaceID
    }

    private func recordAuthorityFailure(
        _ lease: WorkspaceMutationExecutionLease,
        receiptID: ReceiptID,
        commandID: RunCommandID,
        reasonDigest: ContentDigest
    ) async throws {
        guard let authority else {
            throw JournaledWorkspaceMutationRuntimeError.authorityUnavailable
        }
        do {
            _ = try await authority.recordReleaseFailure(
                lease,
                receiptID: receiptID,
                commandID: commandID,
                reasonDigest: reasonDigest,
                observedAt: wallClock(),
                observedAtMonotonicNanoseconds: monotonicClock()
            )
        } catch {
            throw JournaledWorkspaceMutationRuntimeError.authorityReleaseFailed
        }
    }

    private static func failureDigest<T: Encodable>(_ value: T) -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data()
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}

/// Serial, bounded recovery dispatcher for the durable effect outbox.
/// Pending entries are never acknowledged before the journaled runtime returns
/// a reducer-accepted receipt. Failed entries stay pending for explicit repair
/// or a later exact replay; this dispatcher does not renew or mint authority.
actor JournaledWorkspaceMutationDispatcher {
    private let outbox: WorkspaceMutationEffectOutbox
    private let runtime: JournaledWorkspaceMutationRuntime
    private let wallClock: @Sendable () -> Date

    init(
        outbox: WorkspaceMutationEffectOutbox,
        runtime: JournaledWorkspaceMutationRuntime,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.outbox = outbox
        self.runtime = runtime
        self.wallClock = wallClock
    }

    func recoverPending(limit: Int) async throws -> WorkspaceMutationEffectDispatchReport {
        let pending = try await outbox.pending(limit: limit)
        var completed: [IntegrationEffectIntentID] = []
        var quarantined: [IntegrationEffectIntentID] = []
        var failures: [WorkspaceMutationEffectDispatchFailure] = []
        var treeGenerationReceipts: [WorkspaceTreeGenerationReceipt] = []
        var candidatePostimageAttestations:
            [WorkspaceCandidatePostimageAttestationReceipt] = []
        for envelope in pending {
            do {
                let receiptDigest: ContentDigest
                let completedAt: Date
                switch envelope.payload {
                case .apply(let request):
                    let result = try await runtime.apply(
                        request,
                        startCommandID: envelope.startCommandID,
                        recordCommandID: envelope.recordCommandID,
                        releaseReceiptID: envelope.releaseReceiptID,
                        releaseCommandID: envelope.releaseCommandID,
                        failureReceiptID: envelope.failureReceiptID,
                        failureCommandID: envelope.failureCommandID
                    )
                    receiptDigest = Self.receiptDigest(result.applyReceipt)
                    completedAt = result.applyReceipt.completedAt
                    if let generation = result.treeGenerationReceipt {
                        treeGenerationReceipts.append(generation)
                    }
                    if let attestation = result.candidatePostimageAttestation {
                        candidatePostimageAttestations.append(attestation)
                    }
                case .rollback(let request):
                    let result = try await runtime.rollback(
                        request,
                        startCommandID: envelope.startCommandID,
                        recordCommandID: envelope.recordCommandID,
                        releaseReceiptID: envelope.releaseReceiptID,
                        releaseCommandID: envelope.releaseCommandID,
                        failureReceiptID: envelope.failureReceiptID,
                        failureCommandID: envelope.failureCommandID
                    )
                    receiptDigest = Self.receiptDigest(result.rollbackReceipt)
                    completedAt = result.rollbackReceipt.completedAt
                    if let generation = result.treeGenerationReceipt {
                        treeGenerationReceipts.append(generation)
                    }
                }
                _ = try await outbox.markCompleted(
                    intentID: envelope.intentID,
                    receiptDigest: receiptDigest,
                    completedAt: completedAt
                )
                completed.append(envelope.intentID)
            } catch let error as JournaledWorkspaceMutationRuntimeError {
                let failureDigest = Self.receiptDigest(error)
                switch error {
                case .actorMismatch,
                     .transactionMissing,
                     .intentMismatch,
                     .invalidPhase,
                     .authorityUnavailable,
                     .authorityRejected,
                     .failedOwnershipRequiresRepair,
                     .preEffectRejectedAndReleased,
                     .executionFailed,
                     .unexpectedExecutionFailure:
                    _ = try await outbox.markQuarantined(
                        intentID: envelope.intentID,
                        failureDigest: failureDigest,
                        quarantinedAt: wallClock()
                    )
                    quarantined.append(envelope.intentID)
                case .journalWriteFailed,
                     .journalProjectionDiverged,
                     .authorityReleaseFailed:
                    let updated = try await outbox.recordRetryableFailure(
                        intentID: envelope.intentID,
                        failureDigest: failureDigest,
                        attemptedAt: wallClock()
                    )
                    if case .quarantined = updated.state {
                        quarantined.append(envelope.intentID)
                    }
                }
                failures.append(WorkspaceMutationEffectDispatchFailure(
                    intentID: envelope.intentID,
                    error: error
                ))
            }
        }
        return WorkspaceMutationEffectDispatchReport(
            scannedCount: pending.count,
            completedIntentIDs: completed,
            quarantinedIntentIDs: quarantined,
            failures: failures,
            treeGenerationReceipts: treeGenerationReceipts,
            candidatePostimageAttestations: candidatePostimageAttestations
        )
    }

    private static func receiptDigest<T: Encodable>(_ receipt: T) -> ContentDigest {
        WorkspaceMutationEffectOutbox.durableReceiptDigest(receipt)
    }
}
