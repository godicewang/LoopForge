import Foundation

enum WorkspacePreApplyCandidateIsolationError: Error, Equatable {
    case invalidEnrollment
    case registrationMismatch
    case journalProjectionMismatch
    case invalidMutationAttempt
    case sourceRevisionMismatch
    case materializationFailed
    case receiptEncodingFailed
}

/// Issues only an inert candidate-isolation capability. A later reducer-owned
/// command must journal and accept its receipt before production activation
/// may consume it.
actor WorkspacePreApplyCandidateIsolationCoordinator {
    private let registry: WorkspaceMutationRecoveryRegistry

    init(registry: WorkspaceMutationRecoveryRegistry) {
        self.registry = registry
    }

    func isolate(
        enrollment: KernelRunEnrollmentReceipt,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        isolatedAt: Date
    ) async throws -> AuthorizedWorkspacePreApplyCandidateIsolation {
        guard enrollment.schemaVersion == 1,
              enrollment.runID == enrollment.registration.runID,
              let evidence = enrollment.registration.enrollmentEvidence,
              evidence.authority == .ratifiedUserContract,
              evidence.runID == enrollment.runID,
              evidence.contractID == enrollment.contractID,
              evidence.contractRevision == enrollment.contractRevision,
              evidence.candidateDigest == enrollment.candidateDigest,
              evidence.ratificationReceiptID == enrollment.ratificationReceiptID,
              evidence.journalFrameDigest ==
                enrollment.journalTransaction.frameDigest,
              evidence.journalEndingSequence ==
                enrollment.journalTransaction.endingSequence,
              !attemptID.rawValue.isEmpty,
              !nodeID.rawValue.isEmpty,
              isolatedAt >= enrollment.registration.registeredAt else {
            throw WorkspacePreApplyCandidateIsolationError.invalidEnrollment
        }
        guard let registration = try await registry.registration(
            runID: enrollment.runID
        ), registration == enrollment.registration else {
            throw WorkspacePreApplyCandidateIsolationError.registrationMismatch
        }

        let journal = try RunJournal(
            rootDirectory: registration.journalRoot,
            runID: registration.runID
        )
        guard let contract = await journal.currentContract(),
              contract.id == enrollment.contractID,
              let source = contract.sourceRevision,
              let plan = contract.initialExecutionPlan,
              source.workspaceID == registration.workspaceID,
              source.canonicalRootDigest ==
                WorkspaceRepositoryIndexer.canonicalRootDigest(
                    registration.workspaceRoot
                ),
              contract.requiresWorkspaceMutationAuthority,
              plan.requiresWorkspaceMutation,
              let node = plan.nodes.first(where: { $0.id == nodeID }),
              (!node.mutationScope.writablePaths.isEmpty
                || node.mutationScope.maximumChangedFiles > 0
                || node.mutationScope.maximumChangedBytes > 0) else {
            throw WorkspacePreApplyCandidateIsolationError
                .invalidMutationAttempt
        }
        let state = await journal.state
        guard state.sequence == enrollment.journalTransaction.endingSequence,
              state.phase == .ready,
              state.nodes.isEmpty,
              state.attempts.isEmpty else {
            throw WorkspacePreApplyCandidateIsolationError
                .journalProjectionMismatch
        }

        do {
            return try WorkspaceCandidatePostimageMaterializer()
                .materializePreApplyIsolation(
                    runID: enrollment.runID,
                    contractID: contract.id,
                    attemptID: attemptID,
                    nodeID: nodeID,
                    strategyFingerprint: node.strategyFingerprint,
                    isolationActor: registration.actorIdentity,
                    sourceRevision: source,
                    enrollmentJournalFrameDigest:
                        enrollment.journalTransaction.frameDigest,
                    workspaceRoot: registration.workspaceRoot,
                    runDirectory: journal.runDirectory,
                    isolatedAt: isolatedAt
                )
        } catch let error as WorkspacePreApplyCandidateIsolationError {
            throw error
        } catch let error as WorkspaceCandidatePostimageMaterializationError {
            if error == .sourceRevisionMismatch {
                throw WorkspacePreApplyCandidateIsolationError
                    .sourceRevisionMismatch
            }
            throw WorkspacePreApplyCandidateIsolationError.materializationFailed
        } catch {
            throw WorkspacePreApplyCandidateIsolationError.materializationFailed
        }
    }

    /// Revalidates the pristine tree immediately before future journal
    /// acceptance. Once a worker is activated and begins mutation this check
    /// is intentionally no longer expected to pass.
    nonisolated func revalidatePristine(
        _ authority: AuthorizedWorkspacePreApplyCandidateIsolation
    ) throws -> WorkspacePreApplyCandidateIsolationReceipt {
        try WorkspaceCandidatePostimageMaterializer()
            .revalidatePreApplyIsolation(authority)
    }
}
