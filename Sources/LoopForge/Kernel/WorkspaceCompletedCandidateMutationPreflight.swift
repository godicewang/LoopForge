import Foundation

/// Retains the exact live rehearsal lineage and the deterministic preflight
/// product. Journal replay recovers the integration proposal/preflight
/// receipts, but cannot reconstruct this capability or authorize an effect.
struct AuthorizedWorkspaceCompletedCandidateMutationPreflight: Sendable {
    let rehearsal:
        AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
    let preflight: AuthorizedMutationPreflight
    let proposal: IntegrationProposal
    let receipt: MutationPreflightReceipt
    let rollback: RollbackManifest

    fileprivate init(
        rehearsal:
            AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal,
        preflight: AuthorizedMutationPreflight,
        proposal: IntegrationProposal,
        receipt: MutationPreflightReceipt,
        rollback: RollbackManifest
    ) {
        self.rehearsal = rehearsal
        self.preflight = preflight
        self.proposal = proposal
        self.receipt = receipt
        self.rollback = rollback
    }

    func validationIssues() -> [String] {
        var issues = rehearsal.validationIssues()
        let manifest = rehearsal.manifest
        let rehearsed = rehearsal.receipt
        if preflight.manifest != manifest
            || TransactionalMutationKernel.preflight(preflight) !=
                .admitted(receipt: receipt, rollback: rollback)
            || rollback != rehearsal.rollbackManifest
            || proposal.runID != rehearsed.runID
            || proposal.transactionID != manifest.transactionID
            || proposal.candidateID != manifest.candidateID
            || proposal.attemptID != rehearsed.attemptID
            || proposal.nodeID != rehearsed.nodeID
            || proposal.contractDigest != manifest.contractDigest
            || proposal.planNodeDigest != manifest.planNodeDigest
            || proposal.manifestDigest != rehearsed.forwardManifestDigest
            || proposal.canonicalPreimageDigest !=
                manifest.basePreimageDigest
            || proposal.expectedPostimageDigest !=
                manifest.expectedPostimageDigest
            || proposal.proposedAt < rehearsed.rehearsedAt {
            issues.append(
                "completed-candidate executable preflight composition is inconsistent"
            )
        }
        return issues
    }
}

struct WorkspaceCompletedCandidateMutationPreflightInstallation: Sendable {
    let authority: AuthorizedWorkspaceCompletedCandidateMutationPreflight
    let proposalJournalTransaction: JournalTransactionReceipt
    let preflightJournalTransaction: JournalTransactionReceipt
}

enum WorkspaceCompletedCandidateMutationPreflightError:
    Error,
    Equatable,
    Sendable
{
    case invalidRollbackRehearsalAuthority
    case originNotAccepted
    case canonicalWorkspaceChanged
    case journalStateMismatch
    case contextAssemblyFailed
    case preflightRejected(MutationPreflightRejection)
    case transitionAuthorityUnavailable
    case retainedTransactionMismatch
}

/// Assembles the executable manifest context from one exact journal-accepted
/// live rollback rehearsal. It revalidates canonical affected paths and the
/// immutable object store, then journals the ordinary integration proposal and
/// admitted preflight. It issues no apply intent, lease, filesystem effect, or
/// publication authority.
actor WorkspaceCompletedCandidateMutationPreflightCoordinator {
    private let journal: RunJournal
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func prepare(
        rehearsal:
            WorkspaceCompletedCandidateMutationRollbackRehearsalInstallation,
        canonicalWorkspaceRoot: URL,
        proposalCommandID: RunCommandID,
        preflightCommandID: RunCommandID,
        durability: JournalDurability = .boundary
    ) async throws
        -> WorkspaceCompletedCandidateMutationPreflightInstallation {
        let rehearsed = rehearsal.authority
        guard rehearsed.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .invalidRollbackRehearsalAuthority
        }
        guard await journal.completedCandidateMutationRollbackRehearsalReceipt(
            transaction: rehearsal.journalTransaction
        ) == rehearsed.receipt else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .originNotAccepted
        }
        do {
            try WorkspaceCompletedCandidateMutationPreparationFactsCoordinator
                .revalidateCanonicalWorkspace(
                    preparation: rehearsed.preparation.receipt,
                    proposal: rehearsed.preparation.proposal.receipt,
                    canonicalWorkspaceRoot: canonicalWorkspaceRoot
                )
        } catch {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .canonicalWorkspaceChanged
        }
        guard rehearsed.externalArtifactValidationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .originNotAccepted
        }

        let state = await journal.state
        let manifest = rehearsed.manifest
        let proposed = rehearsed.preparation.proposal
        let prepared = rehearsed.preparation.receipt
        guard state.phase == .evaluating,
              let contract = state.contract,
              contract.id == rehearsed.receipt.contractID,
              contract.objectiveDigest == manifest.contractDigest,
              let attempt = state.attempts[rehearsed.receipt.attemptID],
              attempt.disposition == .completed,
              attempt.nodeID == rehearsed.receipt.nodeID,
              let node = state.nodes[rehearsed.receipt.nodeID],
              node.status == .accepted,
              node.contract.strategyFingerprint ==
                rehearsed.preparation.receipt.strategyFingerprint,
              state.runtimeLiveLeases.isEmpty,
              state.runtimeFailedReleases.isEmpty,
              (state.completedCandidateMutationRollbackRehearsalReceipts
                ?? [:])[rehearsed.receipt.proposalReceiptDigest] ==
                    rehearsed.receipt else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .journalStateMismatch
        }
        let observedAt = state.integrationTransactions[
            manifest.transactionID
        ]?.proposal.proposedAt ?? wallClock()
        let currentWorktree: [WorkspaceEntrySnapshot]
        do {
            currentWorktree = try observeCurrentWorktree(
                contract: contract,
                canonicalWorkspaceRoot: canonicalWorkspaceRoot,
                preimage: proposed.canonicalPreimage.receipt.preimage
            )
        } catch {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .canonicalWorkspaceChanged
        }

        let context = MutationPreflightContext(
            currentContractDigest: manifest.contractDigest,
            currentPlanNodeDigest: manifest.planNodeDigest,
            preimage: proposed.canonicalPreimage.receipt.preimage,
            actualWorktreeEntries: currentWorktree,
            contentObjectSizes: contentObjectSizes(
                rehearsed.preparation.proposal.contentStore.objects
            ),
            acceptedCandidateVerificationReceiptIDs:
                manifest.candidateVerificationReceiptIDs,
            acceptedIndependentReviewReceiptIDs: [
                manifest.independentReviewReceiptID
            ],
            acceptedVisualGateReceiptIDs:
                Set([manifest.visualGateReceiptID].compactMap { $0 }),
            preparationFacts: MutationPreflightPreparationFacts(
                writeAuthority: prepared.writeAuthority,
                mutationBudget: prepared.mutationBudget,
                rollbackRehearsal:
                    MutationRollbackRehearsalPreparationReceipt(
                        id: rehearsed.receipt.rollbackRehearsal.id,
                        binding: prepared.preparationBinding,
                        forwardManifestDigest:
                            rehearsed.receipt.forwardManifestDigest,
                        rehearsedOperationCount:
                            rehearsed.receipt.forwardOperationCount
                    ),
                candidateQuiescence: prepared.candidateQuiescence,
                pathResolution: prepared.pathResolution
            ),
            visualGateRequired: manifest.visualGateReceiptID != nil,
            observedAt: observedAt,
            protectedWorkspaceEntries:
                contract.protectedWorkspaceEntryBindings
        )
        guard let preflight = AuthorizedMutationPreflight.completedCandidate(
            rehearsal: rehearsed,
            context: context
        ) else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .contextAssemblyFailed
        }
        let receipt: MutationPreflightReceipt
        let rollback: RollbackManifest
        switch TransactionalMutationKernel.preflight(preflight) {
        case .admitted(let admitted, let inverse):
            receipt = admitted
            rollback = inverse
        case .rejected(let rejection):
            throw WorkspaceCompletedCandidateMutationPreflightError
                .preflightRejected(rejection)
        }
        guard rollback == rehearsed.rollbackManifest else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .contextAssemblyFailed
        }

        let integrationProposal = IntegrationProposal(
            runID: rehearsed.receipt.runID,
            transactionID: manifest.transactionID,
            candidateID: manifest.candidateID,
            attemptID: rehearsed.receipt.attemptID,
            nodeID: rehearsed.receipt.nodeID,
            contractDigest: manifest.contractDigest,
            planNodeDigest: manifest.planNodeDigest,
            manifestDigest: rehearsed.receipt.forwardManifestDigest,
            canonicalPreimageDigest: manifest.basePreimageDigest,
            expectedPostimageDigest: manifest.expectedPostimageDigest,
            proposedAt: context.observedAt
        )
        let authority = AuthorizedWorkspaceCompletedCandidateMutationPreflight(
            rehearsal: rehearsed,
            preflight: preflight,
            proposal: integrationProposal,
            receipt: receipt,
            rollback: rollback
        )
        guard authority.validationIssues().isEmpty,
              let proposeTransition =
                AuthorizedKernelIntegrationTransition
                    .issuedByCompletedCandidatePreflightRuntime(
                        .propose(integrationProposal),
                        rehearsal: rehearsed,
                        preflight: preflight
                    ),
              let preflightTransition =
                AuthorizedKernelIntegrationTransition
                    .issuedByCompletedCandidatePreflightRuntime(
                        .acceptPreflight(
                            receipt: receipt,
                            rollback: rollback
                        ),
                        rehearsal: rehearsed,
                        preflight: preflight
                    ) else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .transitionAuthorityUnavailable
        }

        if let retained = state.integrationTransactions[
            manifest.transactionID
        ] {
            guard retained.proposal == integrationProposal,
                  var proposalTransaction = await journal.transactionReceipt(
                    commandID: proposalCommandID
                  ),
                  await journal.integrationTransitionEvent(
                    transaction: proposalTransaction
                  ) == .proposed(integrationProposal) else {
                throw WorkspaceCompletedCandidateMutationPreflightError
                    .retainedTransactionMismatch
            }
            proposalTransaction.duplicate = true
            switch retained.phase {
            case .proposed:
                let preflightTransaction = try await journal
                    .transactAtCurrentSequence(
                        .advanceIntegration(preflightTransition),
                        commandID: preflightCommandID,
                        issuedAt: receipt.observedAt,
                        actor: rehearsed.receipt.rehearsedBy,
                        durability: durability
                    )
                guard await journal.integrationTransitionEvent(
                    transaction: preflightTransaction
                ) == .rollbackPrepared(
                    receipt: receipt,
                    rollback: rollback
                ) else {
                    throw WorkspaceCompletedCandidateMutationPreflightError
                        .retainedTransactionMismatch
                }
                return WorkspaceCompletedCandidateMutationPreflightInstallation(
                    authority: authority,
                    proposalJournalTransaction: proposalTransaction,
                    preflightJournalTransaction: preflightTransaction
                )
            case .rollbackPrepared:
                guard retained.preflightReceipt == receipt,
                      retained.rollbackManifest == rollback,
                      var preflightTransaction = await journal
                        .transactionReceipt(
                            commandID: preflightCommandID
                        ),
                      await journal.integrationTransitionEvent(
                        transaction: preflightTransaction
                      ) == .rollbackPrepared(
                        receipt: receipt,
                        rollback: rollback
                      ) else {
                    throw WorkspaceCompletedCandidateMutationPreflightError
                        .retainedTransactionMismatch
                }
                preflightTransaction.duplicate = true
                return WorkspaceCompletedCandidateMutationPreflightInstallation(
                    authority: authority,
                    proposalJournalTransaction: proposalTransaction,
                    preflightJournalTransaction: preflightTransaction
                )
            case .applying, .appliedUnverified, .postimageVerified,
                 .independentlyAccepted, .rollbackRequired, .rollingBack,
                 .rolledBack, .rollbackFailedQuarantined:
                throw WorkspaceCompletedCandidateMutationPreflightError
                    .retainedTransactionMismatch
            }
        }

        let transactions = try await journal.transactBatch([
            JournalCommandEnvelope(
                command: .advanceIntegration(proposeTransition),
                context: KernelCommandContext(
                    commandID: proposalCommandID,
                    expectedSequence: state.sequence,
                    issuedAt: integrationProposal.proposedAt,
                    actor: rehearsed.receipt.rehearsedBy
                ),
                durability: durability
            ),
            JournalCommandEnvelope(
                command: .advanceIntegration(preflightTransition),
                context: KernelCommandContext(
                    commandID: preflightCommandID,
                    expectedSequence: state.sequence + 1,
                    issuedAt: receipt.observedAt,
                    actor: rehearsed.receipt.rehearsedBy
                ),
                durability: durability
            )
        ])
        guard transactions.count == 2,
              await journal.integrationTransitionEvent(
                transaction: transactions[0]
              ) == .proposed(integrationProposal),
              await journal.integrationTransitionEvent(
                transaction: transactions[1]
              ) == .rollbackPrepared(receipt: receipt, rollback: rollback)
        else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .retainedTransactionMismatch
        }
        return WorkspaceCompletedCandidateMutationPreflightInstallation(
            authority: authority,
            proposalJournalTransaction: transactions[0],
            preflightJournalTransaction: transactions[1]
        )
    }

    private func contentObjectSizes(
        _ objects: [WorkspaceMutationContentObject]
    ) -> [ContentDigest: UInt64] {
        var result: [ContentDigest: UInt64] = [:]
        for object in objects {
            result[object.digest] = UInt64(object.data.count)
        }
        return result
    }

    private func observeCurrentWorktree(
        contract: TaskContract,
        canonicalWorkspaceRoot: URL,
        preimage: WorkspacePreimage
    ) throws -> [WorkspaceEntrySnapshot] {
        guard let ratified = contract.sourceRevision,
              ratified.workspaceID == preimage.workspaceID,
              ratified.canonicalRootDigest == preimage.rootIdentity else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .contextAssemblyFailed
        }
        let observed = try WorkspaceSourceRevisionCollector().capture(
            workspaceID: ratified.workspaceID,
            root: canonicalWorkspaceRoot,
            excludedDirectoryNames: Set(ratified.excludedDirectoryNames),
            limits: ratified.limits
        )
        guard observed.canonicalRootDigest == preimage.rootIdentity,
              observed.capturePolicyDigest == ratified.capturePolicyDigest else {
            throw WorkspaceCompletedCandidateMutationPreflightError
                .canonicalWorkspaceChanged
        }
        var original: [String: WorkspaceOwnershipClass] = [:]
        for entry in preimage.entries where entry.plane == .worktree {
            guard original[entry.path] == nil else {
                throw WorkspaceCompletedCandidateMutationPreflightError
                    .contextAssemblyFailed
            }
            original[entry.path] = entry.ownership
        }
        return observed.entries.map {
            WorkspaceEntrySnapshot(
                plane: .worktree,
                path: $0.relativePath,
                kind: .regularFile,
                mode: $0.mode,
                contentDigest: $0.contentDigest,
                size: $0.size,
                ownership: original[$0.relativePath] ?? .userExisting
            )
        }
    }
}
