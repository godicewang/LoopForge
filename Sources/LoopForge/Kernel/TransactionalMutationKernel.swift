import CryptoKit
import Foundation

enum WorkspaceEntryPlane: String, Codable, Hashable, Sendable, CaseIterable {
    case head
    case index
    case worktree
    case untracked
}

enum WorkspaceEntryKind: String, Codable, Hashable, Sendable {
    case regularFile
    case directory
    case symbolicLink
    case submodule
}

enum WorkspaceOwnershipClass: String, Codable, Hashable, Sendable {
    case userExisting
    case taskPriorAccepted
    case generatedCache
}

struct WorkspaceEntrySnapshot: Codable, Hashable, Sendable {
    var plane: WorkspaceEntryPlane
    var path: String
    var kind: WorkspaceEntryKind
    var mode: UInt32
    var contentDigest: ContentDigest
    var size: UInt64
    var ownership: WorkspaceOwnershipClass
}

struct WorkspacePreimage: Codable, Hashable, Sendable {
    var workspaceID: WorkspaceID
    var rootIdentity: ContentDigest
    var contractDigest: ContentDigest
    var sourceRevision: ContentDigest
    var requiredPlanes: Set<WorkspaceEntryPlane>
    var capturedPlanes: Set<WorkspaceEntryPlane>
    var entries: [WorkspaceEntrySnapshot]
    var repositoryMetadataDigest: ContentDigest
    var ignoredPathPolicyDigest: ContentDigest
    var capturedAt: Date

    var canonicalDigest: ContentDigest {
        TransactionalMutationKernel.preimageDigest(self)
    }
}

enum MutationOperationKind: String, Codable, Hashable, Sendable {
    case create
    case modify
    case delete
    case rename
    case chmod
    case symbolicLink
    case submodule
}

struct MutationOperation: Codable, Hashable, Sendable {
    var sequence: Int
    var kind: MutationOperationKind
    var sourcePath: String?
    var destinationPath: String?
    var expectedPreimage: ContentDigest?
    var desiredPostimage: ContentDigest?
    var entryKindBefore: WorkspaceEntryKind?
    var entryKindAfter: WorkspaceEntryKind?
    var modeBefore: UInt32?
    var modeAfter: UInt32?
    var requirementIDs: Set<RequirementID>
    var pathResolutionReceiptID: ReceiptID
}

struct MutationManifest: Codable, Hashable, Sendable {
    var transactionID: IntegrationTransactionID
    var candidateID: MutationCandidateID
    var contractDigest: ContentDigest
    var planNodeDigest: ContentDigest
    var basePreimageDigest: ContentDigest
    var operations: [MutationOperation]
    var touchedRequirementIDs: Set<RequirementID>
    var writeAuthorityReceiptID: ReceiptID
    var mutationBudgetReceiptID: ReceiptID
    var candidateVerificationReceiptIDs: Set<ReceiptID>
    var independentReviewReceiptID: ReceiptID
    var rollbackRehearsalReceiptID: ReceiptID
    var candidateQuiescenceReceiptID: ReceiptID
    var visualGateReceiptID: ReceiptID?
    var expectedPostimageDigest: ContentDigest
}

/// Common identity carried by every preparation fact that is not already a
/// first-class run-journal receipt. These values remain inert data until a
/// journal-owned runtime reconstructs them and issues
/// `AuthorizedMutationPreflight`.
struct MutationPreparationBinding: Codable, Hashable, Sendable {
    var transactionID: IntegrationTransactionID
    var candidateID: MutationCandidateID
    var contractDigest: ContentDigest
    var planNodeDigest: ContentDigest
    var canonicalPreimageDigest: ContentDigest
    var expectedPostimageDigest: ContentDigest
}

struct MutationWriteAuthorityPreparationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var binding: MutationPreparationBinding
    var authorizedPaths: Set<String>
    var authorizedRequirementIDs: Set<RequirementID>
}

struct MutationBudgetPreparationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var binding: MutationPreparationBinding
    var maximumChangedFiles: Int
    var maximumChangedBytes: UInt64
}

struct MutationRollbackRehearsalPreparationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var binding: MutationPreparationBinding
    var forwardManifestDigest: ContentDigest
    var rehearsedOperationCount: Int
}

struct MutationCandidateQuiescencePreparationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var binding: MutationPreparationBinding
    var candidateScoped: Bool
    var activeOwnedResourceCount: Int
    var unreleasedLeaseCount: Int
    var externalEffectCount: UInt16
}

struct MutationPathResolutionBinding: Codable, Hashable, Sendable {
    var sequence: Int
    var sourcePath: String?
    var destinationPath: String?
}

struct MutationPathResolutionPreparationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var binding: MutationPreparationBinding
    var rootIdentity: ContentDigest
    var operations: Set<MutationPathResolutionBinding>
    var noSymbolicLinkTraversal: Bool
}

struct MutationPreflightPreparationFacts: Codable, Hashable, Sendable {
    var writeAuthority: MutationWriteAuthorityPreparationReceipt
    var mutationBudget: MutationBudgetPreparationReceipt
    var rollbackRehearsal: MutationRollbackRehearsalPreparationReceipt
    var candidateQuiescence: MutationCandidateQuiescencePreparationReceipt
    var pathResolution: MutationPathResolutionPreparationReceipt
}

struct MutationPreflightContext: Codable, Hashable, Sendable {
    var currentContractDigest: ContentDigest
    var currentPlanNodeDigest: ContentDigest
    var preimage: WorkspacePreimage
    var actualWorktreeEntries: [WorkspaceEntrySnapshot]
    var contentObjectSizes: [ContentDigest: UInt64]
    var acceptedCandidateVerificationReceiptIDs: Set<ReceiptID>
    var acceptedIndependentReviewReceiptIDs: Set<ReceiptID>
    var acceptedVisualGateReceiptIDs: Set<ReceiptID>
    var preparationFacts: MutationPreflightPreparationFacts
    var visualGateRequired: Bool
    var observedAt: Date
    /// Exact bindings must be projected from the current immutable task
    /// contract by the authority issuer. `nil` decodes legacy contexts that
    /// declared no workspace-resident protected baseline entries.
    var protectedWorkspaceEntries: Set<ProtectedWorkspaceEntryBinding>? = nil
}

enum MutationConflictClass: String, Codable, Hashable, Sendable {
    case newerUserChange
    case acceptedSiblingChange
    case baselineMismatch
    case pathTopologyChange
    case modeOrSymlinkConflict
    case requirementConflict
    case unknownPreimage
}

enum MutationPreflightRejection: Error, Codable, Hashable, Sendable {
    case malformedManifest(String)
    case staleContract
    case stalePlanNode
    case incompletePreimageCapture
    case preimageDigestMismatch
    case duplicateOperationSequence(Int)
    case invalidPath(String)
    case pathCollision(String)
    case pathOutsideAuthority(String)
    case missingPathResolutionReceipt(String)
    case invalidOperation(sequence: Int, reason: String)
    case requirementOwnershipMismatch
    case fileBudgetExceeded(actual: Int, maximum: Int)
    case byteBudgetExceeded(actual: UInt64, maximum: UInt64)
    case missingContentObject(ContentDigest)
    case contentObjectSizeMismatch(
        digest: ContentDigest,
        expected: UInt64,
        actual: UInt64
    )
    case compareAndSwapConflict(path: String, conflict: MutationConflictClass)
    case invalidProtectedBaseline(path: String)
    case protectedBaselineMutation(path: String, baselineID: BaselineID)
    case missingWriteAuthority
    case missingMutationBudgetAuthority
    case missingCandidateVerification(Set<ReceiptID>)
    case missingIndependentReview
    case missingRollbackRehearsal
    case missingCandidateQuiescence
    case missingVisualGate
    case candidateExternalEffectsForbidden
}

struct RollbackManifest: Codable, Hashable, Sendable {
    var transactionID: IntegrationTransactionID
    var forwardManifestDigest: ContentDigest
    var expectedAppliedPostimageDigest: ContentDigest
    var restoresPreimageDigest: ContentDigest
    var operations: [MutationOperation]
}

struct MutationPreflightReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var transactionID: IntegrationTransactionID
    var candidateID: MutationCandidateID
    var manifestDigest: ContentDigest
    var canonicalPreimageDigest: ContentDigest
    var rollbackManifestDigest: ContentDigest
    var affectedPaths: [String]
    var operationCount: Int
    var changedFileCount: Int
    var changedByteCount: UInt64
    var writeAuthorityReceiptID: ReceiptID
    var mutationBudgetReceiptID: ReceiptID
    var candidateVerificationReceiptIDs: Set<ReceiptID>
    var independentReviewReceiptID: ReceiptID
    var rollbackRehearsalReceiptID: ReceiptID
    var candidateQuiescenceReceiptID: ReceiptID
    var visualGateReceiptID: ReceiptID?
    var observedAt: Date
    var eligibleForDeterministicApply: Bool
    var permitsPublication: Bool
}

enum MutationPreflightDecision: Codable, Hashable, Sendable {
    case admitted(receipt: MutationPreflightReceipt, rollback: RollbackManifest)
    case rejected(MutationPreflightRejection)
}

/// Non-serializable authority for evaluating one exact mutation preflight.
/// The manifest and context remain durable evidence shapes; decoded values do
/// not become permission merely because their receipt-ID sets are populated.
/// The journal-owned completed-candidate preflight runtime reconstructs every
/// accepted fact and mints this capability from the exact retained live
/// rollback-rehearsal lineage. No decoded manifest/context pair can do so.
struct AuthorizedMutationPreflight: Sendable {
    let manifest: MutationManifest
    let context: MutationPreflightContext

    fileprivate init(
        manifest: MutationManifest,
        context: MutationPreflightContext
    ) {
        self.manifest = manifest
        self.context = context
    }

    static func completedCandidate(
        rehearsal:
            AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal,
        context: MutationPreflightContext
    ) -> AuthorizedMutationPreflight? {
        let prepared = rehearsal.preparation.receipt
        let proposal = rehearsal.preparation.proposal
        let manifest = rehearsal.manifest
        let facts = context.preparationFacts
        var expectedObjectSizes: [ContentDigest: UInt64] = [:]
        for object in proposal.contentStore.objects {
            guard expectedObjectSizes[object.digest] == nil else { return nil }
            expectedObjectSizes[object.digest] = UInt64(object.data.count)
        }
        guard rehearsal.validationIssues().isEmpty,
              context.currentContractDigest == manifest.contractDigest,
              context.currentPlanNodeDigest == manifest.planNodeDigest,
              context.preimage == proposal.canonicalPreimage.receipt.preimage,
              context.contentObjectSizes == expectedObjectSizes,
              context.protectedWorkspaceEntries != nil,
              context.observedAt >= rehearsal.receipt.rehearsedAt,
              context.acceptedCandidateVerificationReceiptIDs ==
                manifest.candidateVerificationReceiptIDs,
              context.acceptedIndependentReviewReceiptIDs ==
                [manifest.independentReviewReceiptID],
              context.acceptedVisualGateReceiptIDs ==
                Set([manifest.visualGateReceiptID].compactMap { $0 }),
              context.visualGateRequired ==
                (manifest.visualGateReceiptID != nil),
              facts.writeAuthority == prepared.writeAuthority,
              facts.mutationBudget == prepared.mutationBudget,
              facts.candidateQuiescence == prepared.candidateQuiescence,
              facts.pathResolution == prepared.pathResolution,
              facts.rollbackRehearsal.id ==
                rehearsal.receipt.rollbackRehearsal.id,
              facts.rollbackRehearsal.binding ==
                prepared.preparationBinding,
              facts.rollbackRehearsal.forwardManifestDigest ==
                rehearsal.receipt.forwardManifestDigest,
              facts.rollbackRehearsal.rehearsedOperationCount ==
                rehearsal.receipt.forwardOperationCount else {
            return nil
        }
        return AuthorizedMutationPreflight(
            manifest: manifest,
            context: context
        )
    }

#if DEBUG
    static func testOnly(
        manifest: MutationManifest,
        context: MutationPreflightContext
    ) -> AuthorizedMutationPreflight {
        AuthorizedMutationPreflight(
            manifest: manifest,
            context: context
        )
    }
#endif
}

/// Pure preflight and rollback planner. It never reads or writes a filesystem,
/// stages bytes, launches a process, changes Git state, or contacts a remote.
enum TransactionalMutationKernel {
    static func preflight(
        _ authorized: AuthorizedMutationPreflight
    ) -> MutationPreflightDecision {
        evaluate(
            manifest: authorized.manifest,
            context: authorized.context
        )
    }

#if DEBUG
    /// Compatibility surface for deterministic reducer fixtures only. Release
    /// code cannot call preflight with freely constructed Codable values.
    static func preflight(
        manifest: MutationManifest,
        context: MutationPreflightContext
    ) -> MutationPreflightDecision {
        preflight(.testOnly(manifest: manifest, context: context))
    }
#endif

    private static func evaluate(
        manifest: MutationManifest,
        context: MutationPreflightContext
    ) -> MutationPreflightDecision {
        if manifest.transactionID.rawValue.isEmpty
            || manifest.candidateID.rawValue.isEmpty
            || manifest.contractDigest.rawValue.isEmpty
            || manifest.planNodeDigest.rawValue.isEmpty
            || manifest.basePreimageDigest.rawValue.isEmpty
            || manifest.expectedPostimageDigest.rawValue.isEmpty
            || manifest.operations.isEmpty {
            return .rejected(.malformedManifest("required digests and operations must be present"))
        }
        guard !manifest.writeAuthorityReceiptID.rawValue.isEmpty,
              !manifest.mutationBudgetReceiptID.rawValue.isEmpty,
              !manifest.independentReviewReceiptID.rawValue.isEmpty,
              !manifest.rollbackRehearsalReceiptID.rawValue.isEmpty,
              !manifest.candidateQuiescenceReceiptID.rawValue.isEmpty,
              !manifest.candidateVerificationReceiptIDs.isEmpty,
              manifest.candidateVerificationReceiptIDs.allSatisfy({
                  !$0.rawValue.isEmpty
              }) else {
            return .rejected(.malformedManifest("all mandatory receipt IDs must be present"))
        }
        guard manifest.contractDigest == context.currentContractDigest else {
            return .rejected(.staleContract)
        }
        guard manifest.planNodeDigest == context.currentPlanNodeDigest else {
            return .rejected(.stalePlanNode)
        }
        guard context.preimage.requiredPlanes == context.preimage.capturedPlanes,
              !context.preimage.requiredPlanes.isEmpty else {
            return .rejected(.incompletePreimageCapture)
        }
        guard !context.preimage.workspaceID.rawValue.isEmpty,
              !context.preimage.rootIdentity.rawValue.isEmpty,
              !context.preimage.contractDigest.rawValue.isEmpty,
              !context.preimage.sourceRevision.rawValue.isEmpty,
              !context.preimage.repositoryMetadataDigest.rawValue.isEmpty,
              !context.preimage.ignoredPathPolicyDigest.rawValue.isEmpty else {
            return .rejected(.incompletePreimageCapture)
        }
        guard context.preimage.contractDigest == context.currentContractDigest else {
            return .rejected(.staleContract)
        }
        var preimageKeys: Set<String> = []
        for entry in context.preimage.entries {
            let key = "\(entry.plane.rawValue):\(entry.path)"
            guard WorkspacePathPolicy.canonical(entry.path) == entry.path,
                  !entry.contentDigest.rawValue.isEmpty,
                  preimageKeys.insert(key).inserted else {
                return .rejected(.incompletePreimageCapture)
            }
        }
        let preimageDigest = context.preimage.canonicalDigest
        guard manifest.basePreimageDigest == preimageDigest else {
            return .rejected(.preimageDigestMismatch)
        }
        let binding = MutationPreparationBinding(
            transactionID: manifest.transactionID,
            candidateID: manifest.candidateID,
            contractDigest: manifest.contractDigest,
            planNodeDigest: manifest.planNodeDigest,
            canonicalPreimageDigest: preimageDigest,
            expectedPostimageDigest: manifest.expectedPostimageDigest
        )
        let facts = context.preparationFacts
        guard facts.writeAuthority.id == manifest.writeAuthorityReceiptID,
              facts.writeAuthority.binding == binding else {
            return .rejected(.missingWriteAuthority)
        }
        guard facts.mutationBudget.id == manifest.mutationBudgetReceiptID,
              facts.mutationBudget.binding == binding,
              facts.mutationBudget.maximumChangedFiles >= 0 else {
            return .rejected(.missingMutationBudgetAuthority)
        }
        guard facts.candidateQuiescence.id == manifest.candidateQuiescenceReceiptID,
              facts.candidateQuiescence.binding == binding,
              facts.candidateQuiescence.candidateScoped,
              facts.candidateQuiescence.activeOwnedResourceCount == 0,
              facts.candidateQuiescence.unreleasedLeaseCount == 0 else {
            return .rejected(.missingCandidateQuiescence)
        }
        guard facts.candidateQuiescence.externalEffectCount == 0 else {
            return .rejected(.candidateExternalEffectsForbidden)
        }
        let missingVerification = manifest.candidateVerificationReceiptIDs.subtracting(
            context.acceptedCandidateVerificationReceiptIDs
        )
        guard missingVerification.isEmpty else {
            return .rejected(.missingCandidateVerification(missingVerification))
        }
        guard context.acceptedIndependentReviewReceiptIDs.contains(
            manifest.independentReviewReceiptID
        ) else { return .rejected(.missingIndependentReview) }
        if context.visualGateRequired {
            guard let visualReceiptID = manifest.visualGateReceiptID,
                  context.acceptedVisualGateReceiptIDs.contains(visualReceiptID) else {
                return .rejected(.missingVisualGate)
            }
        } else if let visualReceiptID = manifest.visualGateReceiptID,
                  !context.acceptedVisualGateReceiptIDs.contains(visualReceiptID) {
            return .rejected(.missingVisualGate)
        }

        let sorted = manifest.operations.sorted { $0.sequence < $1.sequence }
        guard sorted.map(\.sequence) == Array(1...sorted.count) else {
            return .rejected(.malformedManifest(
                "operation sequences must be contiguous and start at one"
            ))
        }
        var sequenceIDs: Set<Int> = []
        var affectedPaths: Set<String> = []
        var foldedPaths: [String: String] = [:]
        var operationRequirements: Set<RequirementID> = []
        var changedBytes: UInt64 = 0
        var worktreeByPath: [String: WorkspaceEntrySnapshot] = [:]
        var actualFoldedPaths: [String: String] = [:]
        for entry in context.actualWorktreeEntries where entry.plane == .worktree
            || entry.plane == .untracked {
            let folded = foldedPath(entry.path)
            guard WorkspacePathPolicy.canonical(entry.path) == entry.path,
                  !entry.contentDigest.rawValue.isEmpty,
                  worktreeByPath[entry.path] == nil,
                  actualFoldedPaths[folded] == nil else {
                return .rejected(.incompletePreimageCapture)
            }
            worktreeByPath[entry.path] = entry
            actualFoldedPaths[folded] = entry.path
        }

        var protectedByPath: [String: ProtectedWorkspaceEntryBinding] = [:]
        for binding in (context.protectedWorkspaceEntries ?? []).sorted(by: {
            (
                $0.baselineID.rawValue,
                $0.entry.path,
                $0.entry.contentDigest.rawValue,
                $0.entry.scope.rawValue
            ) < (
                $1.baselineID.rawValue,
                $1.entry.path,
                $1.entry.contentDigest.rawValue,
                $1.entry.scope.rawValue
            )
        }) {
            let entry = binding.entry
            guard !binding.baselineID.rawValue.isEmpty,
                  WorkspacePathPolicy.canonical(entry.path) == entry.path,
                  !entry.contentDigest.rawValue.isEmpty,
                  protectedByPath[entry.path] == nil else {
                return .rejected(.invalidProtectedBaseline(path: entry.path))
            }
            protectedByPath[entry.path] = binding
        }
        let protectedBindings = protectedByPath.values.sorted {
            ($0.baselineID.rawValue, $0.entry.path)
                < ($1.baselineID.rawValue, $1.entry.path)
        }
        for binding in protectedBindings {
            let entry = binding.entry
            if entry.scope == .exactEntry {
                guard worktreeByPath[entry.path]?.contentDigest == entry.contentDigest else {
                    return .rejected(.compareAndSwapConflict(
                        path: entry.path,
                        conflict: .baselineMismatch
                    ))
                }
            }
        }

        for operation in sorted {
            guard sequenceIDs.insert(operation.sequence).inserted,
                  operation.sequence > 0 else {
                return .rejected(.duplicateOperationSequence(operation.sequence))
            }
            let paths = [operation.sourcePath, operation.destinationPath].compactMap { $0 }
            for path in paths {
                guard WorkspacePathPolicy.canonical(path) == path else {
                    return .rejected(.invalidPath(path))
                }
                if let protected = protectedBindings.first(where: {
                    $0.entry.scope == .exactEntry
                        ? $0.entry.path == path
                        : WorkspacePathPolicy.contains(scope: $0.entry.path, path: path)
                }) {
                    return .rejected(.protectedBaselineMutation(
                        path: path,
                        baselineID: protected.baselineID
                    ))
                }
                guard facts.writeAuthority.authorizedPaths.contains(path) else {
                    return .rejected(.pathOutsideAuthority(path))
                }
                let folded = foldedPath(path)
                if let existing = actualFoldedPaths[folded], existing != path {
                    return .rejected(.pathCollision(path))
                }
                if let existing = foldedPaths[folded], existing != path {
                    return .rejected(.pathCollision(path))
                }
                foldedPaths[folded] = path
                guard affectedPaths.insert(path).inserted else {
                    return .rejected(.pathCollision(path))
                }
            }
            let pathBinding = MutationPathResolutionBinding(
                sequence: operation.sequence,
                sourcePath: operation.sourcePath,
                destinationPath: operation.destinationPath
            )
            guard !operation.pathResolutionReceiptID.rawValue.isEmpty,
                  facts.pathResolution.id == operation.pathResolutionReceiptID,
                  facts.pathResolution.binding == binding,
                  facts.pathResolution.rootIdentity == context.preimage.rootIdentity,
                  facts.pathResolution.noSymbolicLinkTraversal,
                  facts.pathResolution.operations.contains(pathBinding) else {
                return .rejected(.missingPathResolutionReceipt(
                    paths.first ?? "sequence-\(operation.sequence)"
                ))
            }
            guard !operation.requirementIDs.isEmpty,
                  operation.requirementIDs.isSubset(
                    of: facts.writeAuthority.authorizedRequirementIDs
                  ) else {
                return .rejected(.requirementOwnershipMismatch)
            }
            operationRequirements.formUnion(operation.requirementIDs)
            if let rejection = validateShape(operation) {
                return .rejected(rejection)
            }
            if let conflict = compareAndSwapConflict(
                operation,
                entries: worktreeByPath
            ) {
                return .rejected(conflict)
            }
            let footprint: UInt64
            switch mutationFootprint(
                operation,
                entries: worktreeByPath,
                contentObjectSizes: context.contentObjectSizes
            ) {
            case .success(let value):
                footprint = value
            case .failure(let rejection):
                return .rejected(rejection)
            }
            let (sum, overflow) = changedBytes.addingReportingOverflow(footprint)
            guard !overflow else {
                return .rejected(.byteBudgetExceeded(
                    actual: UInt64.max,
                    maximum: facts.mutationBudget.maximumChangedBytes
                ))
            }
            changedBytes = sum
        }

        guard operationRequirements == manifest.touchedRequirementIDs else {
            return .rejected(.requirementOwnershipMismatch)
        }
        guard affectedPaths.count <= facts.mutationBudget.maximumChangedFiles else {
            return .rejected(.fileBudgetExceeded(
                actual: affectedPaths.count,
                maximum: facts.mutationBudget.maximumChangedFiles
            ))
        }
        guard changedBytes <= facts.mutationBudget.maximumChangedBytes else {
            return .rejected(.byteBudgetExceeded(
                actual: changedBytes,
                maximum: facts.mutationBudget.maximumChangedBytes
            ))
        }

        let forwardManifestDigest = manifestDigest(manifest)
        guard facts.rollbackRehearsal.id == manifest.rollbackRehearsalReceiptID,
              facts.rollbackRehearsal.binding == binding,
              facts.rollbackRehearsal.forwardManifestDigest == forwardManifestDigest,
              facts.rollbackRehearsal.rehearsedOperationCount == manifest.operations.count else {
            return .rejected(.missingRollbackRehearsal)
        }
        let rollback = rollbackManifest(
            forward: manifest,
            forwardDigest: forwardManifestDigest,
            preimageDigest: preimageDigest
        )
        let rollbackDigest = digest(canonicalRollbackData(rollback))
        let receipt = MutationPreflightReceipt(
            id: ReceiptID("mutation-preflight-\(forwardManifestDigest.rawValue)"),
            transactionID: manifest.transactionID,
            candidateID: manifest.candidateID,
            manifestDigest: forwardManifestDigest,
            canonicalPreimageDigest: preimageDigest,
            rollbackManifestDigest: rollbackDigest,
            affectedPaths: affectedPaths.sorted(),
            operationCount: sorted.count,
            changedFileCount: affectedPaths.count,
            changedByteCount: changedBytes,
            writeAuthorityReceiptID: manifest.writeAuthorityReceiptID,
            mutationBudgetReceiptID: manifest.mutationBudgetReceiptID,
            candidateVerificationReceiptIDs: manifest.candidateVerificationReceiptIDs,
            independentReviewReceiptID: manifest.independentReviewReceiptID,
            rollbackRehearsalReceiptID: manifest.rollbackRehearsalReceiptID,
            candidateQuiescenceReceiptID: manifest.candidateQuiescenceReceiptID,
            visualGateReceiptID: manifest.visualGateReceiptID,
            observedAt: context.observedAt,
            eligibleForDeterministicApply: true,
            permitsPublication: false
        )
        return .admitted(receipt: receipt, rollback: rollback)
    }

    static func preimageDigest(_ preimage: WorkspacePreimage) -> ContentDigest {
        let entries = preimage.entries.sorted {
            ($0.plane.rawValue, $0.path, $0.kind.rawValue)
                < ($1.plane.rawValue, $1.path, $1.kind.rawValue)
        }
        let material = CanonicalPreimage(
            workspaceID: preimage.workspaceID.rawValue,
            rootIdentity: preimage.rootIdentity.rawValue,
            contractDigest: preimage.contractDigest.rawValue,
            sourceRevision: preimage.sourceRevision.rawValue,
            requiredPlanes: preimage.requiredPlanes.map(\.rawValue).sorted(),
            capturedPlanes: preimage.capturedPlanes.map(\.rawValue).sorted(),
            entries: entries,
            repositoryMetadataDigest: preimage.repositoryMetadataDigest.rawValue,
            ignoredPathPolicyDigest: preimage.ignoredPathPolicyDigest.rawValue,
            capturedAt: preimage.capturedAt
        )
        return digest(encoded(material))
    }

    static func rollbackDigest(_ rollback: RollbackManifest) -> ContentDigest {
        digest(canonicalRollbackData(rollback))
    }

    static func manifestDigest(_ manifest: MutationManifest) -> ContentDigest {
        digest(canonicalManifestData(manifest))
    }

    /// Deterministically derives the exact inverse plan without admitting the
    /// forward manifest. A rehearsal coordinator can execute this plan in an
    /// owner-private replica; only `preflight` can later admit canonical work.
    static func rollbackPlan(
        forward manifest: MutationManifest,
        preimageDigest: ContentDigest
    ) -> RollbackManifest {
        let forwardDigest = manifestDigest(manifest)
        return rollbackManifest(
            forward: manifest,
            forwardDigest: forwardDigest,
            preimageDigest: preimageDigest
        )
    }

    private static func validateShape(
        _ operation: MutationOperation
    ) -> MutationPreflightRejection? {
        let source = operation.sourcePath
        let destination = operation.destinationPath
        let before = operation.expectedPreimage
        let after = operation.desiredPostimage
        let valid: Bool
        switch operation.kind {
        case .create:
            valid = source == nil && destination != nil && before == nil && after != nil
                && operation.entryKindBefore == nil
                && (operation.entryKindAfter == .regularFile
                    || operation.entryKindAfter == .directory)
                && operation.modeBefore == nil && operation.modeAfter != nil
        case .modify:
            valid = source == nil && destination != nil && before != nil && after != nil
                && operation.entryKindBefore != nil
                && operation.entryKindBefore == operation.entryKindAfter
                && operation.modeBefore != nil
                && operation.modeBefore == operation.modeAfter
        case .delete:
            valid = source != nil && destination == nil && before != nil && after == nil
                && operation.entryKindBefore != nil && operation.entryKindAfter == nil
                && operation.modeBefore != nil && operation.modeAfter == nil
        case .rename:
            valid = source != nil && destination != nil && source != destination
                && before != nil && after != nil
                && operation.entryKindBefore != nil
                && operation.entryKindBefore == operation.entryKindAfter
                && operation.modeBefore != nil
                && operation.modeBefore == operation.modeAfter
        case .chmod:
            valid = source == nil && destination != nil && before != nil
                && after == before && operation.modeBefore != nil
                && operation.entryKindBefore != nil
                && operation.entryKindBefore == operation.entryKindAfter
                && operation.modeAfter != nil && operation.modeBefore != operation.modeAfter
        case .symbolicLink:
            valid = source == nil && destination != nil && after != nil
                && operation.entryKindAfter == .symbolicLink
                && operation.entryKindBefore == (before == nil ? nil : .symbolicLink)
                && operation.modeAfter != nil
                && (before == nil ? operation.modeBefore == nil : operation.modeBefore != nil)
        case .submodule:
            valid = source == nil && destination != nil && after != nil
                && operation.entryKindAfter == .submodule
                && operation.entryKindBefore == (before == nil ? nil : .submodule)
                && operation.modeAfter != nil
                && (before == nil ? operation.modeBefore == nil : operation.modeBefore != nil)
        }
        return valid ? nil : .invalidOperation(
            sequence: operation.sequence,
            reason: "operation fields do not match its declared kind"
        )
    }

    private static func compareAndSwapConflict(
        _ operation: MutationOperation,
        entries: [String: WorkspaceEntrySnapshot]
    ) -> MutationPreflightRejection? {
        switch operation.kind {
        case .create:
            guard let path = operation.destinationPath else { return nil }
            guard let existing = entries[path] else { return nil }
            return .compareAndSwapConflict(
                path: path,
                conflict: conflictClass(for: existing, topologyChanged: true)
            )
        case .delete, .rename:
            guard let path = operation.sourcePath,
                  let existing = entries[path] else {
                return .compareAndSwapConflict(
                    path: operation.sourcePath ?? "missing",
                    conflict: .pathTopologyChange
                )
            }
            guard existing.contentDigest == operation.expectedPreimage else {
                return .compareAndSwapConflict(
                    path: path,
                    conflict: conflictClass(for: existing)
                )
            }
            guard existing.kind == operation.entryKindBefore,
                  existing.mode == operation.modeBefore else {
                return .compareAndSwapConflict(
                    path: path,
                    conflict: .modeOrSymlinkConflict
                )
            }
            if operation.kind == .rename,
               let destination = operation.destinationPath,
               let existingDestination = entries[destination] {
                return .compareAndSwapConflict(
                    path: destination,
                    conflict: conflictClass(
                        for: existingDestination,
                        topologyChanged: true
                    )
                )
            }
            return nil
        case .modify, .chmod, .symbolicLink, .submodule:
            guard let path = operation.destinationPath else { return nil }
            if operation.expectedPreimage == nil {
                guard let existing = entries[path] else { return nil }
                return .compareAndSwapConflict(
                    path: path,
                    conflict: conflictClass(for: existing, topologyChanged: true)
                )
            }
            guard let existing = entries[path] else {
                return .compareAndSwapConflict(path: path, conflict: .pathTopologyChange)
            }
            guard existing.contentDigest == operation.expectedPreimage else {
                return .compareAndSwapConflict(
                    path: path,
                    conflict: conflictClass(for: existing)
                )
            }
            if existing.kind != operation.entryKindBefore
                || existing.mode != operation.modeBefore {
                return .compareAndSwapConflict(
                    path: path,
                    conflict: .modeOrSymlinkConflict
                )
            }
            return nil
        }
    }

    private static func conflictClass(
        for entry: WorkspaceEntrySnapshot,
        topologyChanged: Bool = false
    ) -> MutationConflictClass {
        switch entry.ownership {
        case .taskPriorAccepted:
            return .acceptedSiblingChange
        case .generatedCache:
            return .baselineMismatch
        case .userExisting:
            return topologyChanged ? .pathTopologyChange : .newerUserChange
        }
    }

    private static func mutationFootprint(
        _ operation: MutationOperation,
        entries: [String: WorkspaceEntrySnapshot],
        contentObjectSizes: [ContentDigest: UInt64]
    ) -> Result<UInt64, MutationPreflightRejection> {
        var beforeSize: UInt64 = 0
        if let before = operation.expectedPreimage {
            guard let storedSize = contentObjectSizes[before] else {
                return .failure(.missingContentObject(before))
            }
            let path = operation.sourcePath ?? operation.destinationPath
            if let path, let entry = entries[path], entry.contentDigest == before,
               entry.size != storedSize {
                return .failure(.contentObjectSizeMismatch(
                    digest: before,
                    expected: entry.size,
                    actual: storedSize
                ))
            }
            beforeSize = storedSize
        }
        var afterSize: UInt64 = 0
        if let after = operation.desiredPostimage {
            guard let storedSize = contentObjectSizes[after] else {
                return .failure(.missingContentObject(after))
            }
            afterSize = storedSize
        }
        return .success(max(beforeSize, afterSize))
    }

    private static func rollbackManifest(
        forward: MutationManifest,
        forwardDigest: ContentDigest,
        preimageDigest: ContentDigest
    ) -> RollbackManifest {
        let inverse = forward.operations.sorted { $0.sequence > $1.sequence }
            .enumerated().map { offset, operation in
                inverseOperation(operation, sequence: offset + 1)
            }
        return RollbackManifest(
            transactionID: forward.transactionID,
            forwardManifestDigest: forwardDigest,
            expectedAppliedPostimageDigest: forward.expectedPostimageDigest,
            restoresPreimageDigest: preimageDigest,
            operations: inverse
        )
    }

    private static func inverseOperation(
        _ operation: MutationOperation,
        sequence: Int
    ) -> MutationOperation {
        let kind: MutationOperationKind
        let source: String?
        let destination: String?
        switch operation.kind {
        case .create:
            kind = .delete
            source = operation.destinationPath
            destination = nil
        case .delete:
            kind = .create
            source = nil
            destination = operation.sourcePath
        case .rename:
            kind = .rename
            source = operation.destinationPath
            destination = operation.sourcePath
        case .modify:
            kind = .modify
            source = nil
            destination = operation.destinationPath
        case .symbolicLink, .submodule:
            if operation.expectedPreimage == nil {
                kind = .delete
                source = operation.destinationPath
                destination = nil
            } else {
                kind = operation.kind
                source = nil
                destination = operation.destinationPath
            }
        case .chmod:
            kind = .chmod
            source = nil
            destination = operation.destinationPath
        }
        return MutationOperation(
            sequence: sequence,
            kind: kind,
            sourcePath: source,
            destinationPath: destination,
            expectedPreimage: operation.desiredPostimage,
            desiredPostimage: operation.expectedPreimage,
            entryKindBefore: operation.entryKindAfter,
            entryKindAfter: operation.entryKindBefore,
            modeBefore: operation.modeAfter,
            modeAfter: operation.modeBefore,
            requirementIDs: operation.requirementIDs,
            pathResolutionReceiptID: operation.pathResolutionReceiptID
        )
    }

    private static func foldedPath(_ path: String) -> String {
        path.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private struct CanonicalPreimage: Codable {
        var workspaceID: String
        var rootIdentity: String
        var contractDigest: String
        var sourceRevision: String
        var requiredPlanes: [String]
        var capturedPlanes: [String]
        var entries: [WorkspaceEntrySnapshot]
        var repositoryMetadataDigest: String
        var ignoredPathPolicyDigest: String
        var capturedAt: Date
    }

    private struct CanonicalManifest: Codable {
        var transactionID: String
        var candidateID: String
        var contractDigest: String
        var planNodeDigest: String
        var basePreimageDigest: String
        var operations: [CanonicalOperation]
        var touchedRequirementIDs: [String]
        var writeAuthorityReceiptID: String
        var mutationBudgetReceiptID: String
        var candidateVerificationReceiptIDs: [String]
        var independentReviewReceiptID: String
        var rollbackRehearsalReceiptID: String
        var candidateQuiescenceReceiptID: String
        var visualGateReceiptID: String?
        var expectedPostimageDigest: String
    }

    private struct CanonicalOperation: Codable {
        var sequence: Int
        var kind: String
        var sourcePath: String?
        var destinationPath: String?
        var expectedPreimage: String?
        var desiredPostimage: String?
        var entryKindBefore: String?
        var entryKindAfter: String?
        var modeBefore: UInt32?
        var modeAfter: UInt32?
        var requirementIDs: [String]
        var pathResolutionReceiptID: String
    }

    private struct CanonicalRollback: Codable {
        var transactionID: String
        var forwardManifestDigest: String
        var expectedAppliedPostimageDigest: String
        var restoresPreimageDigest: String
        var operations: [CanonicalOperation]
    }

    private static func canonicalManifestData(_ manifest: MutationManifest) -> Data {
        encoded(CanonicalManifest(
            transactionID: manifest.transactionID.rawValue,
            candidateID: manifest.candidateID.rawValue,
            contractDigest: manifest.contractDigest.rawValue,
            planNodeDigest: manifest.planNodeDigest.rawValue,
            basePreimageDigest: manifest.basePreimageDigest.rawValue,
            operations: manifest.operations.sorted { $0.sequence < $1.sequence }
                .map(canonicalOperation),
            touchedRequirementIDs: manifest.touchedRequirementIDs.map(\.rawValue).sorted(),
            writeAuthorityReceiptID: manifest.writeAuthorityReceiptID.rawValue,
            mutationBudgetReceiptID: manifest.mutationBudgetReceiptID.rawValue,
            candidateVerificationReceiptIDs: manifest.candidateVerificationReceiptIDs
                .map(\.rawValue).sorted(),
            independentReviewReceiptID: manifest.independentReviewReceiptID.rawValue,
            rollbackRehearsalReceiptID: manifest.rollbackRehearsalReceiptID.rawValue,
            candidateQuiescenceReceiptID: manifest.candidateQuiescenceReceiptID.rawValue,
            visualGateReceiptID: manifest.visualGateReceiptID?.rawValue,
            expectedPostimageDigest: manifest.expectedPostimageDigest.rawValue
        ))
    }

    private static func canonicalRollbackData(_ rollback: RollbackManifest) -> Data {
        encoded(CanonicalRollback(
            transactionID: rollback.transactionID.rawValue,
            forwardManifestDigest: rollback.forwardManifestDigest.rawValue,
            expectedAppliedPostimageDigest:
                rollback.expectedAppliedPostimageDigest.rawValue,
            restoresPreimageDigest: rollback.restoresPreimageDigest.rawValue,
            operations: rollback.operations.map(canonicalOperation)
        ))
    }

    private static func canonicalOperation(
        _ operation: MutationOperation
    ) -> CanonicalOperation {
        CanonicalOperation(
            sequence: operation.sequence,
            kind: operation.kind.rawValue,
            sourcePath: operation.sourcePath,
            destinationPath: operation.destinationPath,
            expectedPreimage: operation.expectedPreimage?.rawValue,
            desiredPostimage: operation.desiredPostimage?.rawValue,
            entryKindBefore: operation.entryKindBefore?.rawValue,
            entryKindAfter: operation.entryKindAfter?.rawValue,
            modeBefore: operation.modeBefore,
            modeAfter: operation.modeAfter,
            requirementIDs: operation.requirementIDs.map(\.rawValue).sorted(),
            pathResolutionReceiptID: operation.pathResolutionReceiptID.rawValue
        )
    }

    private static func encoded<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}
