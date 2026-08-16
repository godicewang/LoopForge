import CryptoKit
import Darwin
import Foundation

/// Canonical regular-file state observed inside one owner-private rehearsal
/// replica. Inode identity is deliberately excluded: rollback proves exact
/// path/content/mode restoration even though a deleted file receives a new
/// inode when the inverse create is executed.
struct WorkspaceMutationRollbackRehearsalPathState:
    Codable,
    Hashable,
    Sendable
{
    var path: String
    var exists: Bool
    var mode: UInt32?
    var size: UInt64
    var contentDigest: ContentDigest?
}

/// Durable evidence produced only after executing an exact forward manifest
/// and its deterministic inverse in an owner-private replica outside the
/// canonical workspace. It remains inert until the run journal accepts the
/// retained live authority in a later boundary.
struct WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var proposalReceiptDigest: ContentDigest
    var preparationFactsReceiptDigest: ContentDigest
    var preparationFactsJournalFrameDigest: ContentDigest
    var rehearsalManifest: MutationManifest
    var rollbackManifest: RollbackManifest
    var forwardManifestDigest: ContentDigest
    var rollbackManifestDigest: ContentDigest
    var contentObjectSetDigest: ContentDigest
    var initialAffectedStateDigest: ContentDigest
    var appliedAffectedStateDigest: ContentDigest
    var restoredAffectedStateDigest: ContentDigest
    var affectedPaths: [String]
    var forwardOperationCount: Int
    var inverseOperationCount: Int
    var rollbackRehearsal: MutationRollbackRehearsalPreparationReceipt
    var rehearsedBy: ActorIdentity
    var rehearsedAt: Date
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported completed-candidate rollback-rehearsal schema")
        }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || attemptID.rawValue.isEmpty || nodeID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty || rehearsedBy.id.rawValue.isEmpty
            || rehearsedBy.role.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || rehearsedBy.lineageDigest.rawValue.isEmpty {
            issues.append("completed-candidate rollback-rehearsal identity is incomplete")
        }
        for digest in [
            canonicalRootDigest,
            proposalReceiptDigest,
            preparationFactsReceiptDigest,
            preparationFactsJournalFrameDigest,
            forwardManifestDigest,
            rollbackManifestDigest,
            contentObjectSetDigest,
            initialAffectedStateDigest,
            appliedAffectedStateDigest,
            restoredAffectedStateDigest,
            receiptDigest,
        ] where !Self.isSHA256(digest) {
            issues.append("completed-candidate rollback-rehearsal digest is invalid")
        }
        if affectedPaths.isEmpty || affectedPaths != affectedPaths.sorted()
            || Set(affectedPaths).count != affectedPaths.count
            || affectedPaths.contains(where: {
                !WorkspaceSourceRevisionCollector.validRelativePath($0)
            }) {
            issues.append("rollback-rehearsal affected paths are malformed")
        }
        if forwardOperationCount <= 0
            || inverseOperationCount != forwardOperationCount
            || rollbackRehearsal.forwardManifestDigest != forwardManifestDigest
            || rollbackRehearsal.rehearsedOperationCount != forwardOperationCount
            || initialAffectedStateDigest != restoredAffectedStateDigest
            || initialAffectedStateDigest == appliedAffectedStateDigest {
            issues.append("rollback rehearsal did not prove an exact forward/inverse cycle")
        }
        if TransactionalMutationKernel.manifestDigest(rehearsalManifest) !=
                forwardManifestDigest
            || TransactionalMutationKernel.rollbackDigest(rollbackManifest) !=
                rollbackManifestDigest
            || rollbackManifest != TransactionalMutationKernel.rollbackPlan(
                forward: rehearsalManifest,
                preimageDigest: rehearsalManifest.basePreimageDigest
            )
            || rehearsalManifest.rollbackRehearsalReceiptID !=
                rollbackRehearsal.id {
            issues.append("rollback-rehearsal manifests are not exact")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("completed-candidate rollback-rehearsal receipt digest mismatch")
        }
        return issues
    }

    static func digest(
        for receipt: WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
    ) -> ContentDigest? {
        var material = receipt
        material.receiptDigest = ContentDigest("")
        return canonicalDigest(material)
    }

    static func stateDigest(
        _ states: [WorkspaceMutationRollbackRehearsalPathState]
    ) -> ContentDigest? {
        canonicalDigest(states.sorted { $0.path < $1.path })
    }

    private static func canonicalDigest<T: Encodable>(
        _ value: T
    ) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else { return nil }
        return ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

/// Non-serializable proof retaining the exact accepted preparation and exact
/// inert manifest whose forward/inverse cycle was actually executed.
struct AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal:
    Sendable
{
    let receipt: WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
    let preparation:
        AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts
    let manifest: MutationManifest
    let rollbackManifest: RollbackManifest

    fileprivate init(
        receipt: WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt,
        preparation:
            AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts,
        manifest: MutationManifest,
        rollbackManifest: RollbackManifest
    ) {
        self.receipt = receipt
        self.preparation = preparation
        self.manifest = manifest
        self.rollbackManifest = rollbackManifest
    }

    func validationIssues() -> [String] {
        journalValidationIssues() + externalArtifactValidationIssues()
    }

    func journalValidationIssues() -> [String] {
        var issues = receipt.validationIssues()
        issues.append(contentsOf: preparation.journalValidationIssues())
        let prepared = preparation.receipt
        let proposed = preparation.proposal.receipt
        if receipt.runID != prepared.runID
            || receipt.contractID != prepared.contractID
            || receipt.attemptID != prepared.attemptID
            || receipt.nodeID != prepared.nodeID
            || receipt.workspaceID != prepared.workspaceID
            || receipt.canonicalRootDigest != prepared.canonicalRootDigest
            || receipt.proposalReceiptDigest != proposed.receiptDigest
            || receipt.preparationFactsReceiptDigest != prepared.receiptDigest
            || manifest.transactionID != proposed.transactionID
            || manifest.candidateID != proposed.candidateID
            || manifest.contractDigest != proposed.contractDigest
            || manifest.planNodeDigest != proposed.planNodeDigest
            || manifest.basePreimageDigest != proposed.basePreimageDigest
            || manifest.expectedPostimageDigest != proposed.expectedPostimageDigest
            || manifest.touchedRequirementIDs != proposed.touchedRequirementIDs
            || manifest.writeAuthorityReceiptID != prepared.writeAuthority.id
            || manifest.mutationBudgetReceiptID != prepared.mutationBudget.id
            || manifest.candidateQuiescenceReceiptID !=
                prepared.candidateQuiescence.id
            || manifest.rollbackRehearsalReceiptID !=
                receipt.rollbackRehearsal.id
            || receipt.rehearsalManifest != manifest
            || receipt.rollbackManifest != rollbackManifest
            || manifest.operations != Self.operations(
                proposal: proposed,
                pathResolutionReceiptID: prepared.pathResolution.id
            )
            || TransactionalMutationKernel.manifestDigest(manifest) !=
                receipt.forwardManifestDigest
            || TransactionalMutationKernel.rollbackDigest(rollbackManifest) !=
                receipt.rollbackManifestDigest
            || rollbackManifest != TransactionalMutationKernel.rollbackPlan(
                forward: manifest,
                preimageDigest: proposed.basePreimageDigest
            ) {
            issues.append("completed-candidate rollback-rehearsal composition is inconsistent")
        }
        return issues
    }

    func externalArtifactValidationIssues() -> [String] {
        preparation.externalArtifactValidationIssues()
    }

    static func operations(
        proposal: WorkspaceCompletedCandidateMutationManifestProposalReceipt,
        pathResolutionReceiptID: ReceiptID
    ) -> [MutationOperation] {
        proposal.operations.map {
            MutationOperation(
                sequence: $0.sequence,
                kind: $0.kind,
                sourcePath: $0.sourcePath,
                destinationPath: $0.destinationPath,
                expectedPreimage: $0.expectedPreimage,
                desiredPostimage: $0.desiredPostimage,
                entryKindBefore: $0.entryKindBefore,
                entryKindAfter: $0.entryKindAfter,
                modeBefore: $0.modeBefore,
                modeAfter: $0.modeAfter,
                requirementIDs: $0.requirementIDs,
                pathResolutionReceiptID: pathResolutionReceiptID
            )
        }
    }
}

/// Immutable reference boundary for the rich live authority carried by the
/// central command enum. Keeping it boxed prevents unrelated reducer commands
/// from reserving stack for both manifests and their retained object evidence.
final class WorkspaceCompletedCandidateMutationRollbackRehearsalAuthorityBox:
    @unchecked Sendable
{
    let authority:
        AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal

    init(
        _ authority:
            AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
    ) {
        self.authority = authority
    }
}

enum WorkspaceCompletedCandidateMutationRollbackRehearsalError:
    Error,
    Equatable,
    Sendable
{
    case invalidPreparationAuthority
    case invalidManifest
    case canonicalWorkspaceChanged
    case unsafeStorageRoot
    case storageRootOverlapsCanonicalWorkspace
    case storageRootNotOwnerPrivate
    case unsupportedOperation(sequence: Int)
    case missingContentObject(ContentDigest)
    case corruptContentObject(ContentDigest)
    case compareAndSwapConflict(path: String)
    case postimageMismatch(path: String)
    case restorationMismatch
    case encodingFailed
    case cleanupFailed
    case systemCallFailed(operation: String, errno: Int32)
}

/// Executes no canonical-workspace effect. It materializes the exact affected
/// preimage in a fresh owner-private directory, executes the complete forward
/// plan, executes the kernel-derived inverse plan, proves byte/mode equality,
/// and removes the replica before returning a live inert authority.
struct WorkspaceCompletedCandidateMutationRollbackRehearsalExecutor: Sendable {
    func rehearse(
        preparation:
            WorkspaceCompletedCandidateMutationPreparationFactsInstallation,
        manifest: MutationManifest,
        canonicalWorkspaceRoot: URL,
        storageRoot: URL,
        rehearsedAt: Date
    ) throws
        -> AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal {
        guard preparation.authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .invalidPreparationAuthority
        }
        let prepared = preparation.authority.receipt
        let proposed = preparation.authority.proposal.receipt
        let rehearsalID =
            WorkspaceCompletedCandidateMutationPreparationFactsReceipt.factID(
                role: "rollback-rehearsal",
                proposalReceiptDigest: proposed.receiptDigest
            )
        let expectedOperations =
            AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
                .operations(
                    proposal: proposed,
                    pathResolutionReceiptID: prepared.pathResolution.id
                )
        guard manifest.transactionID == proposed.transactionID,
              manifest.candidateID == proposed.candidateID,
              manifest.contractDigest == proposed.contractDigest,
              manifest.planNodeDigest == proposed.planNodeDigest,
              manifest.basePreimageDigest == proposed.basePreimageDigest,
              manifest.expectedPostimageDigest == proposed.expectedPostimageDigest,
              manifest.operations == expectedOperations,
              manifest.touchedRequirementIDs == proposed.touchedRequirementIDs,
              manifest.writeAuthorityReceiptID == prepared.writeAuthority.id,
              manifest.mutationBudgetReceiptID == prepared.mutationBudget.id,
              manifest.candidateQuiescenceReceiptID ==
                prepared.candidateQuiescence.id,
              manifest.rollbackRehearsalReceiptID == rehearsalID,
              !manifest.candidateVerificationReceiptIDs.isEmpty,
              !manifest.independentReviewReceiptID.rawValue.isEmpty else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .invalidManifest
        }
        let objects = try validatedObjects(
            preparation.authority.proposal.contentStore.objects
        )
        let forwardDigest = TransactionalMutationKernel.manifestDigest(manifest)
        let rollback = TransactionalMutationKernel.rollbackPlan(
            forward: manifest,
            preimageDigest: proposed.basePreimageDigest
        )
        do {
            try WorkspaceCompletedCandidateMutationPreparationFactsCoordinator
                .revalidateCanonicalWorkspace(
                    preparation: prepared,
                    proposal: proposed,
                    canonicalWorkspaceRoot: canonicalWorkspaceRoot
                )
        } catch {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .canonicalWorkspaceChanged
        }
        let replica = try WorkspaceMutationOwnerPrivateRollbackReplica(
            canonicalWorkspaceRoot: canonicalWorkspaceRoot,
            storageRoot: storageRoot
        )
        let evidence: WorkspaceMutationRollbackReplicaEvidence
        do {
            evidence = try replica.executeCycle(
                forward: manifest.operations,
                inverse: rollback.operations,
                objects: objects
            )
            try replica.cleanup()
        } catch {
            do {
                try replica.cleanup()
            } catch {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .cleanupFailed
            }
            throw error
        }
        do {
            try WorkspaceCompletedCandidateMutationPreparationFactsCoordinator
                .revalidateCanonicalWorkspace(
                    preparation: prepared,
                    proposal: proposed,
                    canonicalWorkspaceRoot: canonicalWorkspaceRoot
                )
        } catch {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .canonicalWorkspaceChanged
        }
        let fact = MutationRollbackRehearsalPreparationReceipt(
            id: rehearsalID,
            binding: proposed.preparationBinding,
            forwardManifestDigest: forwardDigest,
            rehearsedOperationCount: manifest.operations.count
        )
        var receipt =
            WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt(
                schemaVersion: 1,
                runID: prepared.runID,
                contractID: prepared.contractID,
                attemptID: prepared.attemptID,
                nodeID: prepared.nodeID,
                workspaceID: prepared.workspaceID,
                canonicalRootDigest: prepared.canonicalRootDigest,
                proposalReceiptDigest: proposed.receiptDigest,
                preparationFactsReceiptDigest: prepared.receiptDigest,
                preparationFactsJournalFrameDigest:
                    preparation.journalTransaction.frameDigest,
                rehearsalManifest: manifest,
                rollbackManifest: rollback,
                forwardManifestDigest: forwardDigest,
                rollbackManifestDigest:
                    TransactionalMutationKernel.rollbackDigest(rollback),
                contentObjectSetDigest:
                    preparation.authority.proposal.contentStore.receipt
                        .verificationReceipt.objectSetDigest,
                initialAffectedStateDigest: evidence.initialDigest,
                appliedAffectedStateDigest: evidence.appliedDigest,
                restoredAffectedStateDigest: evidence.restoredDigest,
                affectedPaths: evidence.paths,
                forwardOperationCount: manifest.operations.count,
                inverseOperationCount: rollback.operations.count,
                rollbackRehearsal: fact,
                rehearsedBy: prepared.preparedBy,
                rehearsedAt: rehearsedAt,
                receiptDigest: ContentDigest("")
            )
        guard let digest =
                WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
                    .digest(for: receipt) else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .encodingFailed
        }
        receipt.receiptDigest = digest
        let authority =
            AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal(
                receipt: receipt,
                preparation: preparation.authority,
                manifest: manifest,
                rollbackManifest: rollback
            )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .encodingFailed
        }
        return authority
    }

    private func validatedObjects(
        _ objects: [WorkspaceMutationContentObject]
    ) throws -> [ContentDigest: Data] {
        var result: [ContentDigest: Data] = [:]
        for object in objects {
            guard result[object.digest] == nil else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .corruptContentObject(object.digest)
            }
            guard WorkspaceMutationFilesystemExecutor.contentDigest(object.data)
                    == object.digest else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .corruptContentObject(object.digest)
            }
            result[object.digest] = object.data
        }
        return result
    }
}

struct WorkspaceCompletedCandidateMutationRollbackRehearsalInstallation:
    Sendable
{
    let authority:
        AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
    let journalTransaction: JournalTransactionReceipt
}

enum WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError:
    Error,
    Equatable,
    Sendable
{
    case invalidPreparationAuthority
    case originNotAccepted
    case acceptedEvidenceAmbiguous
    case visualGateMissing
    case retainedReceiptMismatch
}

/// Selects one exact effective verifier/reviewer/visual evidence chain from
/// reducer authority, executes the bound owner-private rehearsal, and journals
/// only the inert receipt. It cannot mint `AuthorizedMutationPreflight` or
/// issue a canonical-workspace effect.
actor WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinator {
    private let journal: RunJournal
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func rehearse(
        preparation:
            WorkspaceCompletedCandidateMutationPreparationFactsInstallation,
        canonicalWorkspaceRoot: URL,
        storageRoot: URL,
        commandID: RunCommandID,
        durability: JournalDurability = .boundary
    ) async throws
        -> WorkspaceCompletedCandidateMutationRollbackRehearsalInstallation {
        guard preparation.authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError
                .invalidPreparationAuthority
        }
        guard await journal.completedCandidateMutationPreparationFactsReceipt(
            transaction: preparation.journalTransaction
        ) == preparation.authority.receipt else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError
                .originNotAccepted
        }
        let state = await journal.state
        let proposed = preparation.authority.proposal.receipt
        let requirements = proposed.touchedRequirementIDs
        let verifications = state.verificationReceipts.values.filter {
            verification in
            verification.attemptID == proposed.attemptID
                && verification.sourceRevision == proposed.expectedPostimageDigest
                && verification.result == .accepted
                && verification.requirementIDs == requirements
                && requirements.allSatisfy {
                    state.verificationIsEffective(
                        verification,
                        requirementID: $0
                    )
                }
        }
        guard verifications.count == 1, let verification = verifications.first
        else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError
                .acceptedEvidenceAmbiguous
        }
        let reviews = state.reviewReceipts.values.filter {
            $0.attemptID == proposed.attemptID
                && $0.sourceRevision == proposed.expectedPostimageDigest
                && $0.requirementIDs == requirements
                && $0.decision == .approveCandidate
                && state.reviewMatchesVerification($0, verification: verification)
        }
        guard reviews.count == 1, let review = reviews.first else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError
                .acceptedEvidenceAmbiguous
        }
        let visualRequirements = state.designBaseline.map {
            $0.requirementIDs.intersection(requirements)
        } ?? []
        let visualReceiptID: ReceiptID?
        if visualRequirements.isEmpty {
            visualReceiptID = nil
        } else {
            let visuals = state.visualGateReceipts.values.filter {
                $0.attemptID == proposed.attemptID
                    && $0.requirementIDs.isSuperset(of: visualRequirements)
                    && $0.candidateSourceTree == proposed.expectedPostimageDigest
                    && $0.result.accepted
            }
            guard visuals.count == 1, let visual = visuals.first else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError
                    .visualGateMissing
            }
            visualReceiptID = visual.id
        }
        let rehearsalID =
            WorkspaceCompletedCandidateMutationPreparationFactsReceipt.factID(
                role: "rollback-rehearsal",
                proposalReceiptDigest: proposed.receiptDigest
            )
        let prepared = preparation.authority.receipt
        let manifest = MutationManifest(
            transactionID: proposed.transactionID,
            candidateID: proposed.candidateID,
            contractDigest: proposed.contractDigest,
            planNodeDigest: proposed.planNodeDigest,
            basePreimageDigest: proposed.basePreimageDigest,
            operations:
                AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
                    .operations(
                        proposal: proposed,
                        pathResolutionReceiptID: prepared.pathResolution.id
                    ),
            touchedRequirementIDs: requirements,
            writeAuthorityReceiptID: prepared.writeAuthority.id,
            mutationBudgetReceiptID: prepared.mutationBudget.id,
            candidateVerificationReceiptIDs: [verification.id],
            independentReviewReceiptID: review.id,
            rollbackRehearsalReceiptID: rehearsalID,
            candidateQuiescenceReceiptID: prepared.candidateQuiescence.id,
            visualGateReceiptID: visualReceiptID,
            expectedPostimageDigest: proposed.expectedPostimageDigest
        )
        let retained = await journal
            .completedCandidateMutationRollbackRehearsalReceipt(
                proposalReceiptDigest: proposed.receiptDigest
            )
        let authority = try
            WorkspaceCompletedCandidateMutationRollbackRehearsalExecutor()
                .rehearse(
                    preparation: preparation,
                    manifest: manifest,
                    canonicalWorkspaceRoot: canonicalWorkspaceRoot,
                    storageRoot: storageRoot,
                    rehearsedAt: retained?.rehearsedAt ?? wallClock()
                )
        if let retained, retained != authority.receipt {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalCoordinatorError
                .retainedReceiptMismatch
        }
        let transaction = try await journal
            .recordCompletedCandidateMutationRollbackRehearsal(
                authority,
                canonicalWorkspaceRoot: canonicalWorkspaceRoot,
                commandID: commandID,
                durability: durability
            )
        return WorkspaceCompletedCandidateMutationRollbackRehearsalInstallation(
            authority: authority,
            journalTransaction: transaction
        )
    }
}

struct WorkspaceMutationRollbackReplicaEvidence {
    var paths: [String]
    var initialDigest: ContentDigest
    var appliedDigest: ContentDigest
    var restoredDigest: ContentDigest
}

/// Descriptor-relative owner-private replica. No path component underneath the
/// supplied storage root is followed through a symbolic link.
final class WorkspaceMutationOwnerPrivateRollbackReplica: @unchecked Sendable {
    private let storageDescriptor: Int32
    private let replicaDescriptor: Int32
    private let replicaName: String
    private var directories: Set<String> = []
    private var affectedPaths: Set<String> = []
    private var cleaned = false

    init(canonicalWorkspaceRoot: URL, storageRoot: URL) throws {
        let canonical = try Self.resolvedDirectory(canonicalWorkspaceRoot)
        let storage = try Self.resolvedDirectory(storageRoot)
        let canonicalPath = canonical.path
        let storagePath = storage.path
        guard canonicalPath != storagePath,
              !storagePath.hasPrefix(canonicalPath + "/"),
              !canonicalPath.hasPrefix(storagePath + "/") else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .storageRootOverlapsCanonicalWorkspace
        }
        var storageStatus = stat()
        guard Darwin.lstat(storagePath, &storageStatus) == 0,
              storageStatus.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .unsafeStorageRoot
        }
        guard storageStatus.st_uid == Darwin.geteuid(),
              storageStatus.st_mode & 0o077 == 0 else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .storageRootNotOwnerPrivate
        }
        let parent = Darwin.open(
            storagePath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard parent >= 0 else {
            throw Self.systemCallFailure("open(rehearsal-storage-root)")
        }
        let name = "rollback-rehearsal-\(UUID().uuidString.lowercased())"
        let created = name.withCString {
            Darwin.mkdirat(parent, $0, 0o700)
        }
        guard created == 0 else {
            let failure = errno
            _ = Darwin.close(parent)
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .systemCallFailed(
                    operation: "mkdirat(rehearsal-replica)",
                    errno: failure
                )
        }
        let replica = name.withCString {
            Darwin.openat(
                parent,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard replica >= 0 else {
            let failure = errno
            _ = name.withCString { Darwin.unlinkat(parent, $0, AT_REMOVEDIR) }
            _ = Darwin.close(parent)
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .systemCallFailed(
                    operation: "openat(rehearsal-replica)",
                    errno: failure
                )
        }
        storageDescriptor = parent
        replicaDescriptor = replica
        replicaName = name
    }

    deinit {
        _ = Darwin.close(replicaDescriptor)
        _ = Darwin.close(storageDescriptor)
    }

    func executeCycle(
        forward: [MutationOperation],
        inverse: [MutationOperation],
        objects: [ContentDigest: Data]
    ) throws -> WorkspaceMutationRollbackReplicaEvidence {
        let paths = Set(forward.compactMap {
            $0.sourcePath ?? $0.destinationPath
        }).sorted()
        affectedPaths = Set(paths)
        try createParentTopology(paths: paths)
        for operation in forward.sorted(by: { $0.sequence < $1.sequence })
        where operation.expectedPreimage != nil {
            guard let path = operation.sourcePath ?? operation.destinationPath,
                  let digest = operation.expectedPreimage,
                  let data = objects[digest],
                  let mode = operation.modeBefore else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .invalidManifest
            }
            if try state(path: path).exists { continue }
            try write(path: path, data: data, mode: mode, create: true)
        }
        let initial = try states(paths: paths)
        try validate(states: initial, against: forward, before: true)
        for operation in forward.sorted(by: { $0.sequence < $1.sequence }) {
            try execute(operation, objects: objects)
        }
        let applied = try states(paths: paths)
        try validate(states: applied, against: forward, before: false)
        for operation in inverse.sorted(by: { $0.sequence < $1.sequence }) {
            try execute(operation, objects: objects)
        }
        let restored = try states(paths: paths)
        guard restored == initial else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .restorationMismatch
        }
        guard let initialDigest =
                WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
                    .stateDigest(initial),
              let appliedDigest =
                WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
                    .stateDigest(applied),
              let restoredDigest =
                WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
                    .stateDigest(restored),
              initialDigest == restoredDigest else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .restorationMismatch
        }
        return WorkspaceMutationRollbackReplicaEvidence(
            paths: paths,
            initialDigest: initialDigest,
            appliedDigest: appliedDigest,
            restoredDigest: restoredDigest
        )
    }

    func cleanup() throws {
        guard !cleaned else { return }
        for path in affectedPaths.sorted(by: { $0.count > $1.count }) {
            let parent = try openParent(path)
            defer { _ = Darwin.close(parent.descriptor) }
            let result = parent.name.withCString {
                Darwin.unlinkat(parent.descriptor, $0, 0)
            }
            if result != 0 && errno != ENOENT {
                throw Self.systemCallFailure("unlinkat(rehearsal-cleanup-file)")
            }
        }
        for path in directories.sorted(by: {
            let left = $0.split(separator: "/").count
            let right = $1.split(separator: "/").count
            return left == right ? $0 > $1 : left > right
        }) {
            let parent = try openParent(path)
            defer { _ = Darwin.close(parent.descriptor) }
            let result = parent.name.withCString {
                Darwin.unlinkat(parent.descriptor, $0, AT_REMOVEDIR)
            }
            if result != 0 && errno != ENOENT {
                throw Self.systemCallFailure("unlinkat(rehearsal-cleanup-directory)")
            }
        }
        guard replicaName.withCString({
            Darwin.unlinkat(storageDescriptor, $0, AT_REMOVEDIR)
        }) == 0 else {
            throw Self.systemCallFailure("unlinkat(rehearsal-cleanup-root)")
        }
        cleaned = true
    }

    private func execute(
        _ operation: MutationOperation,
        objects: [ContentDigest: Data]
    ) throws {
        guard let path = operation.sourcePath ?? operation.destinationPath else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .unsupportedOperation(sequence: operation.sequence)
        }
        try validate(
            state: state(path: path),
            path: path,
            digest: operation.expectedPreimage,
            mode: operation.modeBefore,
            before: true
        )
        switch operation.kind {
        case .create, .modify:
            guard let digest = operation.desiredPostimage,
                  let data = objects[digest],
                  let mode = operation.modeAfter else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .missingContentObject(
                        operation.desiredPostimage ?? ContentDigest("")
                    )
            }
            try write(
                path: path,
                data: data,
                mode: mode,
                create: operation.kind == .create
            )
        case .delete:
            let parent = try openParent(path)
            defer { _ = Darwin.close(parent.descriptor) }
            guard parent.name.withCString({
                Darwin.unlinkat(parent.descriptor, $0, 0)
            }) == 0 else {
                throw Self.systemCallFailure("unlinkat(rehearsal-delete)")
            }
        case .chmod:
            guard let mode = operation.modeAfter else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .invalidManifest
            }
            let descriptor = try openRegularFile(path, flags: O_RDONLY)
            defer { _ = Darwin.close(descriptor) }
            guard Darwin.fchmod(descriptor, mode_t(mode & 0o7777)) == 0,
                  Darwin.fsync(descriptor) == 0 else {
                throw Self.systemCallFailure("fchmod(rehearsal-file)")
            }
        case .rename, .symbolicLink, .submodule:
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .unsupportedOperation(sequence: operation.sequence)
        }
        try validate(
            state: state(path: path),
            path: path,
            digest: operation.desiredPostimage,
            mode: operation.modeAfter,
            before: false
        )
    }

    private func validate(
        states: [WorkspaceMutationRollbackRehearsalPathState],
        against operations: [MutationOperation],
        before: Bool
    ) throws {
        let byPath = Dictionary(uniqueKeysWithValues: states.map { ($0.path, $0) })
        for operation in operations {
            guard let path = operation.sourcePath ?? operation.destinationPath,
                  let observed = byPath[path] else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .invalidManifest
            }
            try validate(
                state: observed,
                path: path,
                digest: before
                    ? operation.expectedPreimage : operation.desiredPostimage,
                mode: before ? operation.modeBefore : operation.modeAfter,
                before: before
            )
        }
    }

    private func validate(
        state: WorkspaceMutationRollbackRehearsalPathState,
        path: String,
        digest: ContentDigest?,
        mode: UInt32?,
        before: Bool
    ) throws {
        let valid: Bool
        if let digest {
            valid = state.exists && state.contentDigest == digest
                && state.mode == mode
        } else {
            valid = !state.exists && state.mode == nil
                && state.contentDigest == nil && state.size == 0
        }
        guard valid else {
            if before {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .compareAndSwapConflict(path: path)
            }
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .postimageMismatch(path: path)
        }
    }

    private func createParentTopology(paths: [String]) throws {
        let parents = Set(paths.flatMap { path -> [String] in
            let components = path.split(separator: "/").map(String.init)
            guard components.count > 1 else { return [] }
            return (1..<components.count).map {
                components.prefix($0).joined(separator: "/")
            }
        }).sorted {
            let left = $0.split(separator: "/").count
            let right = $1.split(separator: "/").count
            return left == right ? $0 < $1 : left < right
        }
        for path in parents {
            let parent = try openParent(path)
            defer { _ = Darwin.close(parent.descriptor) }
            let result = parent.name.withCString {
                Darwin.mkdirat(parent.descriptor, $0, 0o700)
            }
            guard result == 0 || errno == EEXIST else {
                throw Self.systemCallFailure("mkdirat(rehearsal-parent)")
            }
            directories.insert(path)
        }
    }

    private func states(
        paths: [String]
    ) throws -> [WorkspaceMutationRollbackRehearsalPathState] {
        try paths.sorted().map(state(path:))
    }

    private func state(
        path: String
    ) throws -> WorkspaceMutationRollbackRehearsalPathState {
        let parent = try openParent(path)
        defer { _ = Darwin.close(parent.descriptor) }
        var status = stat()
        let result = parent.name.withCString {
            Darwin.fstatat(
                parent.descriptor,
                $0,
                &status,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if result != 0 {
            guard errno == ENOENT else {
                throw Self.systemCallFailure("fstatat(rehearsal-state)")
            }
            return WorkspaceMutationRollbackRehearsalPathState(
                path: path,
                exists: false,
                mode: nil,
                size: 0,
                contentDigest: nil
            )
        }
        guard status.st_mode & S_IFMT == S_IFREG, status.st_size >= 0 else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .postimageMismatch(path: path)
        }
        let descriptor = try openRegularFile(path, flags: O_RDONLY)
        defer { _ = Darwin.close(descriptor) }
        let data = try readAll(descriptor)
        return WorkspaceMutationRollbackRehearsalPathState(
            path: path,
            exists: true,
            mode: UInt32(status.st_mode & 0o7777),
            size: UInt64(data.count),
            contentDigest:
                WorkspaceMutationFilesystemExecutor.contentDigest(data)
        )
    }

    private func write(
        path: String,
        data: Data,
        mode: UInt32,
        create: Bool
    ) throws {
        let parent = try openParent(path)
        defer { _ = Darwin.close(parent.descriptor) }
        let flags = O_WRONLY | O_CLOEXEC | O_NOFOLLOW
            | (create ? (O_CREAT | O_EXCL) : O_TRUNC)
        let descriptor = parent.name.withCString {
            Darwin.openat(parent.descriptor, $0, flags, 0o600)
        }
        guard descriptor >= 0 else {
            throw Self.systemCallFailure("openat(rehearsal-write)")
        }
        defer { _ = Darwin.close(descriptor) }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    data.count - offset
                )
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                throw Self.systemCallFailure("write(rehearsal-file)")
            }
            offset += count
        }
        guard Darwin.fchmod(descriptor, mode_t(mode & 0o7777)) == 0,
              Darwin.fsync(descriptor) == 0 else {
            throw Self.systemCallFailure("fsync(rehearsal-file)")
        }
    }

    private func readAll(_ descriptor: Int32) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw Self.systemCallFailure("lseek(rehearsal-file)")
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                throw Self.systemCallFailure("read(rehearsal-file)")
            }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    private func openRegularFile(
        _ path: String,
        flags: Int32
    ) throws -> Int32 {
        let parent = try openParent(path)
        defer { _ = Darwin.close(parent.descriptor) }
        let descriptor = parent.name.withCString {
            Darwin.openat(parent.descriptor, $0, flags | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw Self.systemCallFailure("openat(rehearsal-file)")
        }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG else {
            let failure = errno
            _ = Darwin.close(descriptor)
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .systemCallFailed(
                    operation: "fstat(rehearsal-file)",
                    errno: failure
                )
        }
        return descriptor
    }

    private func openParent(
        _ path: String
    ) throws -> (descriptor: Int32, name: String) {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(
                WorkspaceSourceRevisionCollector.validPathComponent
              ) else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .invalidManifest
        }
        var descriptor = Darwin.dup(replicaDescriptor)
        guard descriptor >= 0 else {
            throw Self.systemCallFailure("dup(rehearsal-root)")
        }
        for component in components.dropLast() {
            let next = component.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            let failure = errno
            _ = Darwin.close(descriptor)
            guard next >= 0 else {
                throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                    .systemCallFailed(
                        operation: "openat(rehearsal-parent)",
                        errno: failure
                    )
            }
            descriptor = next
        }
        return (descriptor, components.last!)
    }

    private static func resolvedDirectory(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        guard standardized.isFileURL, standardized.path.hasPrefix("/"),
              let pointer = standardized.path.withCString({
                Darwin.realpath($0, nil)
              }) else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .unsafeStorageRoot
        }
        defer { Darwin.free(pointer) }
        let resolved = URL(
            fileURLWithPath: String(cString: pointer),
            isDirectory: true
        )
        var status = stat()
        guard Darwin.lstat(resolved.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceCompletedCandidateMutationRollbackRehearsalError
                .unsafeStorageRoot
        }
        return resolved
    }

    private static func systemCallFailure(
        _ operation: String
    ) -> WorkspaceCompletedCandidateMutationRollbackRehearsalError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
