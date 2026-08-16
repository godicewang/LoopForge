import CryptoKit
import Foundation

/// Exact operation topology proposed from an accepted completed candidate.
/// Unlike `MutationOperation`, this type cannot carry a path-resolution
/// receipt. It is therefore evidence about intent, never executable authority.
struct WorkspaceCompletedCandidateMutationOperationProposal:
    Codable,
    Hashable,
    Sendable
{
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
}

/// Durable, inert manifest proposal bound to one exact accepted before/after
/// content set and one exact canonical preimage. Receipt-backed path, write,
/// budget, verification, review, rollback, quiescence, and visual authority is
/// deliberately absent. A later preparation boundary must independently mint
/// and journal every such fact before a `MutationManifest` can exist.
struct WorkspaceCompletedCandidateMutationManifestProposalReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var strategyFingerprint: StrategyFingerprint
    var transactionID: IntegrationTransactionID
    var candidateID: MutationCandidateID
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var completedCandidateContentStoreReceiptDigest: ContentDigest
    var completedCandidateContentStoreJournalFrameDigest: ContentDigest
    var canonicalPreimageReceiptDigest: ContentDigest
    var canonicalPreimageJournalFrameDigest: ContentDigest
    var contractDigest: ContentDigest
    var planNodeDigest: ContentDigest
    var basePreimageDigest: ContentDigest
    var expectedPostimageDigest: ContentDigest
    var operations: [WorkspaceCompletedCandidateMutationOperationProposal]
    var touchedRequirementIDs: Set<RequirementID>
    var changedFileCount: Int
    var changedByteCount: UInt64
    var preparationBinding: MutationPreparationBinding
    var proposedBy: ActorIdentity
    var proposedAt: Date
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported completed-candidate manifest-proposal schema")
        }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || attemptID.rawValue.isEmpty || nodeID.rawValue.isEmpty
            || strategyFingerprint.rawValue.isEmpty
            || transactionID.rawValue.isEmpty || candidateID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty || proposedBy.id.rawValue.isEmpty
            || proposedBy.role.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || proposedBy.lineageDigest.rawValue.isEmpty {
            issues.append("completed-candidate manifest-proposal identity is incomplete")
        }
        for digest in [
            canonicalRootDigest,
            completedCandidateContentStoreReceiptDigest,
            completedCandidateContentStoreJournalFrameDigest,
            canonicalPreimageReceiptDigest,
            canonicalPreimageJournalFrameDigest,
            contractDigest,
            planNodeDigest,
            basePreimageDigest,
            expectedPostimageDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("completed-candidate manifest-proposal digest is invalid")
        }
        if transactionID != Self.transactionID(
            contentStoreReceiptDigest:
                completedCandidateContentStoreReceiptDigest
        ) || candidateID != Self.candidateID(
            expectedPostimageDigest: expectedPostimageDigest
        ) {
            issues.append("manifest-proposal identity is not content-derived")
        }
        if operations.isEmpty
            || operations.map(\.sequence) != Array(1...operations.count)
            || operations != operations.sorted(by: Self.operationLessThan)
            || Set(operations.compactMap(Self.path)).count != operations.count {
            issues.append("manifest-proposal operations are not canonical")
        }
        if operations.contains(where: { !Self.operationIsValid($0) }) {
            issues.append("manifest-proposal contains an invalid operation shape")
        }
        let requirements = operations.reduce(into: Set<RequirementID>()) {
            $0.formUnion($1.requirementIDs)
        }
        if requirements != touchedRequirementIDs
            || touchedRequirementIDs.isEmpty {
            issues.append("manifest-proposal requirement ownership is inconsistent")
        }
        if changedFileCount != operations.count || changedFileCount <= 0 {
            issues.append("manifest-proposal changed-file count is inconsistent")
        }
        let expectedBinding = MutationPreparationBinding(
            transactionID: transactionID,
            candidateID: candidateID,
            contractDigest: contractDigest,
            planNodeDigest: planNodeDigest,
            canonicalPreimageDigest: basePreimageDigest,
            expectedPostimageDigest: expectedPostimageDigest
        )
        if preparationBinding != expectedBinding {
            issues.append("manifest-proposal preparation binding is inconsistent")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("completed-candidate manifest-proposal digest mismatch")
        }
        return issues
    }

    static func operations(
        for derivation: WorkspaceMutationOperationDerivationReceipt
    ) -> [WorkspaceCompletedCandidateMutationOperationProposal] {
        derivation.operations.map { operation in
            let source: String?
            let destination: String?
            switch operation.kind {
            case .delete:
                source = operation.path
                destination = nil
            case .create, .modify, .chmod:
                source = nil
                destination = operation.path
            case .rename, .symbolicLink, .submodule:
                source = nil
                destination = nil
            }
            return WorkspaceCompletedCandidateMutationOperationProposal(
                sequence: operation.sequence,
                kind: operation.kind,
                sourcePath: source,
                destinationPath: destination,
                expectedPreimage: operation.expectedPreimage,
                desiredPostimage: operation.desiredPostimage,
                entryKindBefore: operation.expectedPreimage == nil
                    ? nil : .regularFile,
                entryKindAfter: operation.desiredPostimage == nil
                    ? nil : .regularFile,
                modeBefore: operation.modeBefore,
                modeAfter: operation.modeAfter,
                requirementIDs: operation.requirementIDs
            )
        }
    }

    static func changedByteCount(
        derivation: WorkspaceMutationOperationDerivationReceipt
    ) -> UInt64? {
        let sizes = Dictionary(uniqueKeysWithValues:
            derivation.contentObjects.map { ($0.contentDigest, $0.size) }
        )
        var total: UInt64 = 0
        for operation in derivation.operations {
            let before: UInt64
            if let digest = operation.expectedPreimage {
                guard let size = sizes[digest] else { return nil }
                before = size
            } else {
                before = 0
            }
            let after: UInt64
            if let digest = operation.desiredPostimage {
                guard let size = sizes[digest] else { return nil }
                after = size
            } else {
                after = 0
            }
            let (next, overflow) = total.addingReportingOverflow(max(before, after))
            guard !overflow else { return nil }
            total = next
        }
        return total
    }

    static func planNodeDigest(_ node: KernelNodeContract) -> ContentDigest? {
        canonicalDigest(PlanNodeMaterial(
            id: node.id,
            requirementIDs: node.requirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            objective: node.objective,
            dependencies: node.dependencies.sorted { $0.rawValue < $1.rawValue },
            writablePaths: node.mutationScope.writablePaths.sorted(),
            maximumChangedFiles: node.mutationScope.maximumChangedFiles,
            maximumChangedBytes: node.mutationScope.maximumChangedBytes,
            capabilityIDs: node.capabilityIDs.sorted(),
            strategyFingerprint: node.strategyFingerprint
        ))
    }

    static func transactionID(
        contentStoreReceiptDigest: ContentDigest
    ) -> IntegrationTransactionID {
        IntegrationTransactionID(
            "integration-\(contentStoreReceiptDigest.rawValue)"
        )
    }

    static func candidateID(
        expectedPostimageDigest: ContentDigest
    ) -> MutationCandidateID {
        MutationCandidateID("candidate-\(expectedPostimageDigest.rawValue)")
    }

    static func digest(
        for receipt:
            WorkspaceCompletedCandidateMutationManifestProposalReceipt
    ) -> ContentDigest? {
        var material = receipt
        material.receiptDigest = ContentDigest("")
        return canonicalDigest(material)
    }

    private static func operationLessThan(
        _ lhs: WorkspaceCompletedCandidateMutationOperationProposal,
        _ rhs: WorkspaceCompletedCandidateMutationOperationProposal
    ) -> Bool {
        (path(lhs) ?? "", lhs.kind.rawValue, lhs.sequence)
            < (path(rhs) ?? "", rhs.kind.rawValue, rhs.sequence)
    }

    private static func path(
        _ operation: WorkspaceCompletedCandidateMutationOperationProposal
    ) -> String? {
        operation.sourcePath ?? operation.destinationPath
    }

    private static func operationIsValid(
        _ operation: WorkspaceCompletedCandidateMutationOperationProposal
    ) -> Bool {
        guard !operation.requirementIDs.isEmpty,
              let path = path(operation),
              WorkspaceSourceRevisionCollector.validRelativePath(path) else {
            return false
        }
        switch operation.kind {
        case .create:
            return operation.sourcePath == nil
                && operation.destinationPath == path
                && operation.expectedPreimage == nil
                && operation.desiredPostimage != nil
                && operation.entryKindBefore == nil
                && operation.entryKindAfter == .regularFile
                && operation.modeBefore == nil
                && operation.modeAfter != nil
        case .modify:
            return operation.sourcePath == nil
                && operation.destinationPath == path
                && operation.expectedPreimage != nil
                && operation.desiredPostimage != nil
                && operation.entryKindBefore == .regularFile
                && operation.entryKindAfter == .regularFile
                && operation.modeBefore != nil
                && operation.modeBefore == operation.modeAfter
        case .delete:
            return operation.sourcePath == path
                && operation.destinationPath == nil
                && operation.expectedPreimage != nil
                && operation.desiredPostimage == nil
                && operation.entryKindBefore == .regularFile
                && operation.entryKindAfter == nil
                && operation.modeBefore != nil
                && operation.modeAfter == nil
        case .chmod:
            return operation.sourcePath == nil
                && operation.destinationPath == path
                && operation.expectedPreimage != nil
                && operation.expectedPreimage == operation.desiredPostimage
                && operation.entryKindBefore == .regularFile
                && operation.entryKindAfter == .regularFile
                && operation.modeBefore != nil
                && operation.modeAfter != nil
                && operation.modeBefore != operation.modeAfter
        case .rename, .symbolicLink, .submodule:
            return false
        }
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

    private struct PlanNodeMaterial: Codable {
        var id: KernelNodeID
        var requirementIDs: [RequirementID]
        var objective: String
        var dependencies: [KernelNodeID]
        var writablePaths: [String]
        var maximumChangedFiles: Int
        var maximumChangedBytes: Int
        var capabilityIDs: [String]
        var strategyFingerprint: StrategyFingerprint
    }
}

/// Live composition proof. Replay can recover the proposal receipt but cannot
/// recreate either this capability or either retained byte/preimage authority.
struct AuthorizedWorkspaceCompletedCandidateMutationManifestProposal:
    Sendable
{
    let receipt:
        WorkspaceCompletedCandidateMutationManifestProposalReceipt
    let contentStore:
        AuthorizedWorkspaceCompletedCandidateMutationContentStore
    let canonicalPreimage: AuthorizedWorkspaceJournaledCanonicalPreimage

    fileprivate init(
        receipt:
            WorkspaceCompletedCandidateMutationManifestProposalReceipt,
        contentStore:
            AuthorizedWorkspaceCompletedCandidateMutationContentStore,
        canonicalPreimage: AuthorizedWorkspaceJournaledCanonicalPreimage
    ) {
        self.receipt = receipt
        self.contentStore = contentStore
        self.canonicalPreimage = canonicalPreimage
    }

    func journalValidationIssues() -> [String] {
        var issues = receipt.validationIssues()
        issues.append(contentsOf: contentStore.journalValidationIssues())
        issues.append(contentsOf: canonicalPreimage.validationIssues())
        let store = contentStore.receipt
        let preimage = canonicalPreimage.receipt
        guard let changedBytes =
                WorkspaceCompletedCandidateMutationManifestProposalReceipt
                    .changedByteCount(derivation: store.derivation) else {
            issues.append("manifest-proposal changed-byte count overflowed")
            return issues
        }
        if receipt.runID != store.runID || receipt.runID != preimage.runID
            || receipt.contractID != store.contractID
            || receipt.contractID != preimage.contractID
            || receipt.attemptID != store.attemptID
            || receipt.nodeID != store.nodeID
            || receipt.workspaceID != store.workspaceID
            || receipt.workspaceID != preimage.preimage.workspaceID
            || receipt.canonicalRootDigest != store.canonicalRootDigest
            || receipt.canonicalRootDigest != preimage.preimage.rootIdentity
            || receipt.completedCandidateContentStoreReceiptDigest !=
                store.receiptDigest
            || receipt.canonicalPreimageReceiptDigest != preimage.receiptDigest
            || receipt.contractDigest != preimage.preimage.contractDigest
            || receipt.basePreimageDigest != preimage.preimage.canonicalDigest
            || store.derivation.baseSourceRevision !=
                preimage.preimage.sourceRevision
            || receipt.expectedPostimageDigest !=
                store.derivation.candidateSourceRevision
            || receipt.operations !=
                WorkspaceCompletedCandidateMutationManifestProposalReceipt
                    .operations(for: store.derivation)
            || receipt.touchedRequirementIDs !=
                store.derivation.touchedRequirementIDs
            || receipt.changedFileCount != store.derivation.operations.count
            || receipt.changedByteCount != changedBytes
            || receipt.proposedBy != store.storedBy
            || receipt.proposedBy != preimage.captureActor
            || receipt.proposedAt < store.storedAt
            || receipt.proposedAt < preimage.capturedAt {
            issues.append("completed-candidate manifest-proposal composition is inconsistent")
        }
        return issues
    }

    func externalArtifactValidationIssues() -> [String] {
        contentStore.externalArtifactValidationIssues()
    }

    func validationIssues() -> [String] {
        journalValidationIssues() + externalArtifactValidationIssues()
    }
}

struct WorkspaceCompletedCandidateMutationManifestProposalInstallation:
    Sendable
{
    let authority:
        AuthorizedWorkspaceCompletedCandidateMutationManifestProposal
    let journalTransaction: JournalTransactionReceipt
}

enum WorkspaceCompletedCandidateMutationManifestProposalError:
    Error,
    Equatable,
    Sendable
{
    case invalidContentStoreAuthority
    case invalidCanonicalPreimageAuthority
    case originNotAccepted
    case budgetExceeded
    case encodingFailed
}

/// Builds and journals only the exact inert proposal. It issues no
/// `MutationManifest`, preparation receipt, rollback, preflight, integration,
/// effect-outbox, or filesystem executor authority.
actor WorkspaceCompletedCandidateMutationManifestProposalCoordinator {
    private let journal: RunJournal
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func propose(
        contentStore:
            WorkspaceCompletedCandidateMutationContentStoreInstallation,
        canonicalPreimage: AuthorizedWorkspaceJournaledCanonicalPreimage,
        canonicalPreimageTransaction: JournalTransactionReceipt,
        commandID: RunCommandID,
        durability: JournalDurability = .boundary
    ) async throws
        -> WorkspaceCompletedCandidateMutationManifestProposalInstallation {
        guard contentStore.authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .invalidContentStoreAuthority
        }
        guard canonicalPreimage.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .invalidCanonicalPreimageAuthority
        }
        guard await journal.completedCandidateMutationContentStoreReceipt(
            transaction: contentStore.journalTransaction
        ) == contentStore.authority.receipt,
        await journal.journaledCanonicalPreimageReceipt(
            transaction: canonicalPreimageTransaction
        ) == canonicalPreimage.receipt else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .originNotAccepted
        }

        let state = await journal.state
        let store = contentStore.authority.receipt
        if let retained = await journal
            .completedCandidateMutationManifestProposalReceipt(
                derivationDigest: store.derivationDigest
            ) {
            let authority =
                AuthorizedWorkspaceCompletedCandidateMutationManifestProposal(
                    receipt: retained,
                    contentStore: contentStore.authority,
                    canonicalPreimage: canonicalPreimage
                )
            guard authority.validationIssues().isEmpty else {
                throw WorkspaceCompletedCandidateMutationManifestProposalError
                    .originNotAccepted
            }
            let transaction = try await journal
                .recordCompletedCandidateMutationManifestProposal(
                    authority,
                    commandID: commandID,
                    durability: durability
                )
            return WorkspaceCompletedCandidateMutationManifestProposalInstallation(
                authority: authority,
                journalTransaction: transaction
            )
        }
        guard state.phase == .evaluating,
              let contract = state.contract,
              contract.id == store.contractID,
              let nodeState = state.nodes[store.nodeID],
              nodeState.status == .awaitingVerification,
              let attempt = state.attempts[store.attemptID],
              attempt.disposition == .completed,
              attempt.nodeID == store.nodeID,
              attempt.strategyFingerprint == nodeState.contract
                .strategyFingerprint,
              let contractMutationBudget = contract.executionBudgets?.mutation,
              let planNodeDigest =
                WorkspaceCompletedCandidateMutationManifestProposalReceipt
                    .planNodeDigest(nodeState.contract),
              nodeState.contract.mutationScope.maximumChangedFiles >= 0,
              nodeState.contract.mutationScope.maximumChangedBytes >= 0,
              contractMutationBudget.maximumChangedFiles >= 0,
              let changedBytes =
                WorkspaceCompletedCandidateMutationManifestProposalReceipt
                    .changedByteCount(derivation: store.derivation) else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .originNotAccepted
        }
        guard store.derivation.operations.count <=
                nodeState.contract.mutationScope.maximumChangedFiles,
              changedBytes <= UInt64(
                nodeState.contract.mutationScope.maximumChangedBytes
              ),
              store.derivation.operations.count <=
                contractMutationBudget.maximumChangedFiles,
              changedBytes <= contractMutationBudget.maximumChangedBytes else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .budgetExceeded
        }

        let transactionID =
            WorkspaceCompletedCandidateMutationManifestProposalReceipt
                .transactionID(
                    contentStoreReceiptDigest: store.receiptDigest
                )
        let candidateID =
            WorkspaceCompletedCandidateMutationManifestProposalReceipt
                .candidateID(
                    expectedPostimageDigest:
                        store.derivation.candidateSourceRevision
                )
        let binding = MutationPreparationBinding(
            transactionID: transactionID,
            candidateID: candidateID,
            contractDigest: contract.objectiveDigest,
            planNodeDigest: planNodeDigest,
            canonicalPreimageDigest:
                canonicalPreimage.receipt.preimage.canonicalDigest,
            expectedPostimageDigest:
                store.derivation.candidateSourceRevision
        )
        var receipt =
            WorkspaceCompletedCandidateMutationManifestProposalReceipt(
                schemaVersion: 1,
                runID: store.runID,
                contractID: store.contractID,
                attemptID: store.attemptID,
                nodeID: store.nodeID,
                strategyFingerprint: attempt.strategyFingerprint,
                transactionID: transactionID,
                candidateID: candidateID,
                workspaceID: store.workspaceID,
                canonicalRootDigest: store.canonicalRootDigest,
                completedCandidateContentStoreReceiptDigest:
                    store.receiptDigest,
                completedCandidateContentStoreJournalFrameDigest:
                    contentStore.journalTransaction.frameDigest,
                canonicalPreimageReceiptDigest:
                    canonicalPreimage.receipt.receiptDigest,
                canonicalPreimageJournalFrameDigest:
                    canonicalPreimageTransaction.frameDigest,
                contractDigest: contract.objectiveDigest,
                planNodeDigest: planNodeDigest,
                basePreimageDigest:
                    canonicalPreimage.receipt.preimage.canonicalDigest,
                expectedPostimageDigest:
                    store.derivation.candidateSourceRevision,
                operations:
                    WorkspaceCompletedCandidateMutationManifestProposalReceipt
                        .operations(for: store.derivation),
                touchedRequirementIDs:
                    store.derivation.touchedRequirementIDs,
                changedFileCount: store.derivation.operations.count,
                changedByteCount: changedBytes,
                preparationBinding: binding,
                proposedBy: store.storedBy,
                proposedAt: wallClock(),
                receiptDigest: ContentDigest("")
            )
        guard let digest =
                WorkspaceCompletedCandidateMutationManifestProposalReceipt
                    .digest(for: receipt) else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .encodingFailed
        }
        receipt.receiptDigest = digest
        let authority =
            AuthorizedWorkspaceCompletedCandidateMutationManifestProposal(
                receipt: receipt,
                contentStore: contentStore.authority,
                canonicalPreimage: canonicalPreimage
            )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationManifestProposalError
                .encodingFailed
        }
        let transaction = try await journal
            .recordCompletedCandidateMutationManifestProposal(
                authority,
                commandID: commandID,
                durability: durability
            )
        return WorkspaceCompletedCandidateMutationManifestProposalInstallation(
            authority: authority,
            journalTransaction: transaction
        )
    }
}
