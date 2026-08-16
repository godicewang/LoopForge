import CryptoKit
import Foundation

struct WorkspacePostimageVerifierVetoRollbackPreparationInstallation:
    Sendable
{
    var launchVeto: KernelPostimageVerifierLaunchVetoReceipt
    var activation: KernelPostimageVerifierActivationReceipt
    var sourceApplyEnvelope: WorkspaceMutationEffectEnvelope
    var leaseAdmission: JournaledWorkspaceMutationLeaseAdmission
    var intent: IntegrationRollbackIntent
    var effectEnvelope: WorkspaceMutationEffectEnvelope
}

enum WorkspacePostimageVerifierVetoRollbackPreparationError:
    Error,
    Equatable,
    Sendable
{
    case invalidLimit
    case registrationMismatch
    case ambiguousLaunchVeto
    case activationMismatch
    case launchAlreadyRecorded
    case sourceApplyEnvelopeMissing
    case sourceApplyEnvelopeAmbiguous
    case sourceApplyEnvelopeMismatch
    case clockPrecedesCausalEvidence
    case canonicalWorkspaceChanged
    case leaseAdmissionRejected
    case outboxRejected(WorkspaceMutationEffectOutboxError)
}

/// Converts an exact, reducer-accepted verifier containment veto into a fresh,
/// durable rollback effect. The source apply envelope supplies the original
/// content-complete preimage, manifests, and recovery-artifact binding; this
/// coordinator never reconstructs mutation bytes from prose or from the live
/// workspace.
///
/// The admission receipt is journaled before the rollback request reaches the
/// external outbox. The dispatcher subsequently journals `requestRollback`
/// before entering the filesystem executor. Every generated identity is a
/// deterministic function of the accepted veto and apply receipt, so a crash
/// at either boundary can only replay the same lease and effect envelope.
actor WorkspacePostimageVerifierVetoRollbackPreparationCoordinator {
    private let registry: WorkspaceMutationRecoveryRegistry
    private let registration: WorkspaceMutationRecoveryRegistration
    private let journal: RunJournal
    private let outbox: WorkspaceMutationEffectOutbox
    private let leaseAuthority: JournaledWorkspaceMutationLeaseAuthority
    private let wallClock: @Sendable () -> Date
    private let monotonicClock: @Sendable () -> UInt64

    init(
        registry: WorkspaceMutationRecoveryRegistry,
        registration: WorkspaceMutationRecoveryRegistration,
        journal: RunJournal,
        outbox: WorkspaceMutationEffectOutbox,
        leaseAuthority: JournaledWorkspaceMutationLeaseAuthority,
        wallClock: @escaping @Sendable () -> Date = { Date() },
        monotonicClock: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.registry = registry
        self.registration = registration
        self.journal = journal
        self.outbox = outbox
        self.leaseAuthority = leaseAuthority
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
    }

    func prepareEligibleRollbacks(
        limit: Int,
        leaseLifetimeNanoseconds: UInt64 = 300_000_000_000
    ) async throws
        -> [WorkspacePostimageVerifierVetoRollbackPreparationInstallation] {
        guard limit > 0,
              leaseLifetimeNanoseconds > 0 else {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .invalidLimit
        }
        guard let retained = try? await registry.registration(
            runID: registration.runID
        ),
              retained == registration,
              registration.runID == journal.runID else {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .registrationMismatch
        }

        let state = await journal.state
        let entries: [WorkspaceMutationEffectEnvelope]
        do {
            entries = try await outbox.allEntries()
        } catch let error as WorkspaceMutationEffectOutboxError {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .outboxRejected(error)
        }
        var installations:
            [WorkspacePostimageVerifierVetoRollbackPreparationInstallation] = []
        let transactions = state.integrationTransactions.values
            .filter { $0.phase == .appliedUnverified }
            .sorted {
                $0.proposal.transactionID.rawValue <
                    $1.proposal.transactionID.rawValue
            }
        for transaction in transactions {
            guard installations.count < limit else { break }
            guard let applyReceipt = transaction.applyReceipt else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .sourceApplyEnvelopeMismatch
            }
            let vetoes = (state.postimageVerifierLaunchVetoReceipts ?? [:])
                .values.filter {
                    $0.integrationTransactionID ==
                        transaction.proposal.transactionID &&
                    $0.applyReceiptID == applyReceipt.id
                }
            guard !vetoes.isEmpty else { continue }
            guard vetoes.count == 1, let veto = vetoes.first else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .ambiguousLaunchVeto
            }
            guard let activation = (state
                .postimageVerifierActivationReceipts ?? [:])[
                    veto.activationReceiptID
                ], activation.runID == registration.runID,
                  activation.integrationTransactionID ==
                    transaction.proposal.transactionID,
                  activation.applyReceiptID == applyReceipt.id,
                  activation.attemptID == veto.attemptID,
                  activation.evidenceRecipeID == veto.evidenceRecipeID,
                  activation.verifier == veto.verifier,
                  activation.resourceLimits.maximumResidentBytes ==
                    veto.requiredMaximumResidentBytes else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .activationMismatch
            }
            guard !(state.postimageVerifierLaunchReceipts ?? [:]).values
                .contains(where: {
                    $0.activationReceiptID == veto.activationReceiptID
                }) else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .launchAlreadyRecorded
            }

            let matchingApplyEnvelopes = entries.filter { envelope in
                guard envelope.transactionID ==
                        transaction.proposal.transactionID,
                      case .apply(let request) = envelope.payload,
                      request.intent.id == applyReceipt.intentID else {
                    return false
                }
                return true
            }
            guard !matchingApplyEnvelopes.isEmpty else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .sourceApplyEnvelopeMissing
            }
            guard matchingApplyEnvelopes.count == 1,
                  let applyEnvelope = matchingApplyEnvelopes.first,
                  case .apply(let applyRequest) = applyEnvelope.payload else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .sourceApplyEnvelopeAmbiguous
            }
            guard Self.completedEnvelope(
                applyEnvelope,
                binds: applyReceipt
            ), Self.sourceApplyRequest(
                applyRequest,
                binds: transaction,
                registration: registration
            ) else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .sourceApplyEnvelopeMismatch
            }

            installations.append(try await prepare(
                transaction: transaction,
                applyReceipt: applyReceipt,
                applyRequest: applyRequest,
                applyEnvelope: applyEnvelope,
                veto: veto,
                activation: activation,
                leaseLifetimeNanoseconds: leaseLifetimeNanoseconds
            ))
        }
        return installations
    }

    private func prepare(
        transaction: IntegrationTransactionState,
        applyReceipt: IntegrationApplyReceipt,
        applyRequest: WorkspaceMutationExecutionRequest,
        applyEnvelope: WorkspaceMutationEffectEnvelope,
        veto: KernelPostimageVerifierLaunchVetoReceipt,
        activation: KernelPostimageVerifierActivationReceipt,
        leaseLifetimeNanoseconds: UInt64
    ) async throws
        -> WorkspacePostimageVerifierVetoRollbackPreparationInstallation {
        let identity = Self.identity(
            runID: registration.runID,
            transactionID: transaction.proposal.transactionID,
            applyReceiptID: applyReceipt.id,
            vetoReceiptID: veto.id
        )
        let ids = IdentitySet(identity: identity)
        let liveRootIdentity: ContentDigest
        do {
            liveRootIdentity = try WorkspaceMutationFilesystemExecutor
                .rootIdentity(registration.workspaceRoot)
        } catch {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .canonicalWorkspaceChanged
        }
        guard liveRootIdentity == applyRequest.lease.rootIdentity else {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .canonicalWorkspaceChanged
        }

        let issuedAt: Date
        let requestedAtMonotonicNanoseconds: UInt64
        let expiresAtMonotonicNanoseconds: UInt64
        if let recorded = await journal.runtimeAdmissionReceipt(
            receiptID: ids.admissionReceiptID
        ) {
            guard case .accepted(let lease, _) = recorded.outcome,
                  lease.request.leaseID == ids.leaseID,
                  let deadline =
                    lease.request.renewalDeadlineMonotonicNanoseconds,
                  deadline > lease.request.requestedAtMonotonicNanoseconds else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .leaseAdmissionRejected
            }
            issuedAt = recorded.observedAt
            requestedAtMonotonicNanoseconds =
                lease.request.requestedAtMonotonicNanoseconds
            expiresAtMonotonicNanoseconds = deadline
        } else {
            let observedAt = wallClock()
            issuedAt = Date(
                timeIntervalSince1970: floor(
                    observedAt.timeIntervalSince1970 * 1_000
                ) / 1_000
            )
            guard issuedAt >= veto.observedAt,
                  issuedAt >= applyReceipt.completedAt else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .clockPrecedesCausalEvidence
            }
            requestedAtMonotonicNanoseconds = monotonicClock()
            guard requestedAtMonotonicNanoseconds <=
                    UInt64.max - leaseLifetimeNanoseconds else {
                throw WorkspacePostimageVerifierVetoRollbackPreparationError
                    .leaseAdmissionRejected
            }
            expiresAtMonotonicNanoseconds =
                requestedAtMonotonicNanoseconds + leaseLifetimeNanoseconds
        }
        let expiresAt = issuedAt.addingTimeInterval(
            Double(
                expiresAtMonotonicNanoseconds -
                    requestedAtMonotonicNanoseconds
            ) / 1_000_000_000
        )

        let admission: JournaledWorkspaceMutationLeaseAdmission
        do {
            admission = try await leaseAuthority.admit(
                transactionID: transaction.proposal.transactionID,
                workspaceID: registration.workspaceID,
                rootIdentity: liveRootIdentity,
                operation: .rollback,
                leaseID: ids.leaseID,
                admissionReceiptID: ids.admissionReceiptID,
                admissionCommandID: ids.admissionCommandID,
                issuedAt: issuedAt,
                expiresAt: expiresAt,
                requestedAtMonotonicNanoseconds:
                    requestedAtMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds:
                    expiresAtMonotonicNanoseconds
            )
        } catch {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .leaseAdmissionRejected
        }

        let intent = IntegrationRollbackIntent(
            id: ids.intentID,
            transactionID: transaction.proposal.transactionID,
            rollbackManifestDigest:
                applyRequest.preflightReceipt.rollbackManifestDigest,
            expectedCurrentWorkspaceDigest:
                applyReceipt.observedPostimageDigest,
            recoveryArtifactDigest: applyReceipt.recoveryArtifactDigest,
            exclusiveLeaseReceiptID: admission.executionLease.receiptID,
            remoteAccessDisabled: true,
            requestedAt: issuedAt
        )
        let rollbackRequest = WorkspaceMutationRollbackRequest(
            workspaceRoot: applyRequest.workspaceRoot,
            recoveryRoot: applyRequest.recoveryRoot,
            workspaceID: applyRequest.workspaceID,
            preimage: applyRequest.preimage,
            manifest: applyRequest.manifest,
            rollbackManifest: applyRequest.rollbackManifest,
            preflightReceipt: applyRequest.preflightReceipt,
            applyReceipt: applyReceipt,
            intent: intent,
            lease: admission.executionLease,
            executor: applyRequest.executor,
            completedAt: issuedAt,
            limits: applyRequest.limits
        )
        let envelope: WorkspaceMutationEffectEnvelope
        do {
            envelope = try await outbox.enqueue(
                payload: .rollback(rollbackRequest),
                startCommandID: ids.startCommandID,
                recordCommandID: ids.recordCommandID,
                releaseReceiptID: ids.releaseReceiptID,
                releaseCommandID: ids.releaseCommandID,
                failureReceiptID: ids.failureReceiptID,
                failureCommandID: ids.failureCommandID,
                enqueuedAt: issuedAt
            )
        } catch let error as WorkspaceMutationEffectOutboxError {
            throw WorkspacePostimageVerifierVetoRollbackPreparationError
                .outboxRejected(error)
        }
        return WorkspacePostimageVerifierVetoRollbackPreparationInstallation(
            launchVeto: veto,
            activation: activation,
            sourceApplyEnvelope: applyEnvelope,
            leaseAdmission: admission,
            intent: intent,
            effectEnvelope: envelope
        )
    }

    private static func completedEnvelope(
        _ envelope: WorkspaceMutationEffectEnvelope,
        binds receipt: IntegrationApplyReceipt
    ) -> Bool {
        guard case .completed(let digest, let completedAt) = envelope.state
        else { return false }
        return completedAt == receipt.completedAt &&
            digest == WorkspaceMutationEffectOutbox.durableReceiptDigest(receipt)
    }

    private static func sourceApplyRequest(
        _ request: WorkspaceMutationExecutionRequest,
        binds transaction: IntegrationTransactionState,
        registration: WorkspaceMutationRecoveryRegistration
    ) -> Bool {
        request.workspaceID == registration.workspaceID &&
            request.preimage.workspaceID == registration.workspaceID &&
            request.workspaceRoot.standardizedFileURL.resolvingSymlinksInPath() ==
                registration.workspaceRoot &&
            request.executor == registration.actorIdentity &&
            request.manifest.transactionID == transaction.proposal.transactionID &&
            request.intent == transaction.applyIntent &&
            request.preflightReceipt == transaction.preflightReceipt &&
            request.rollbackManifest == transaction.rollbackManifest
    }

    private static func identity(
        runID: KernelRunID,
        transactionID: IntegrationTransactionID,
        applyReceiptID: ReceiptID,
        vetoReceiptID: ReceiptID
    ) -> String {
        let material = [
            "postimage-verifier-veto-rollback-v1",
            runID.rawValue,
            transactionID.rawValue,
            applyReceiptID.rawValue,
            vetoReceiptID.rawValue
        ].joined(separator: "\0")
        return SHA256.hash(data: Data(material.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private struct IdentitySet {
        var leaseID: ResourceLeaseID
        var admissionReceiptID: ReceiptID
        var admissionCommandID: RunCommandID
        var intentID: IntegrationEffectIntentID
        var startCommandID: RunCommandID
        var recordCommandID: RunCommandID
        var releaseReceiptID: ReceiptID
        var releaseCommandID: RunCommandID
        var failureReceiptID: ReceiptID
        var failureCommandID: RunCommandID

        init(identity: String) {
            leaseID = ResourceLeaseID("veto-rollback-lease-" + identity)
            admissionReceiptID = ReceiptID(
                "veto-rollback-admission-" + identity
            )
            admissionCommandID = RunCommandID(
                "veto-rollback-admit-" + identity
            )
            intentID = IntegrationEffectIntentID(
                "veto-rollback-intent-" + identity
            )
            startCommandID = RunCommandID(
                "veto-rollback-start-" + identity
            )
            recordCommandID = RunCommandID(
                "veto-rollback-record-" + identity
            )
            releaseReceiptID = ReceiptID(
                "veto-rollback-release-" + identity
            )
            releaseCommandID = RunCommandID(
                "veto-rollback-release-" + identity
            )
            failureReceiptID = ReceiptID(
                "veto-rollback-failure-" + identity
            )
            failureCommandID = RunCommandID(
                "veto-rollback-failure-" + identity
            )
        }
    }
}
