import Foundation

enum WorkspaceTreeGenerationAuthority: String, Codable, Hashable, Sendable {
    case journaledMutationCommit
    case journaledRecoveryReconciliation
}

/// Internal journal evidence used to issue an opaque repository-generation
/// receipt. It can only be projected by RunJournal after matching the exact
/// reducer-accepted integration event to recovered journal bytes.
struct AcceptedWorkspaceTreeGenerationEvent: Sendable {
    let transactionID: IntegrationTransactionID
    let generationDigest: ContentDigest
    let authority: WorkspaceTreeGenerationAuthority
    let journalTransaction: JournalTransactionReceipt
    let candidatePostimage: WorkspaceSourceRevisionArtifact?
    let applyReceiptID: ReceiptID?
}

enum WorkspaceTreeGenerationJournalProjection: Sendable {
    case noWorkspaceTransition
    case accepted(AcceptedWorkspaceTreeGenerationEvent)
    case ambiguousLatestTransition
}

enum WorkspaceTreeGenerationReceiptResolution: Sendable {
    case noWorkspaceTransition
    case accepted(WorkspaceTreeGenerationReceipt)
    case ambiguousLatestTransition
}

enum WorkspaceCandidatePostimageAttestationResolution: Sendable {
    case noWorkspaceTransition
    case accepted(WorkspaceCandidatePostimageAttestationReceipt)
    case unavailableForLatestTransition
    case ambiguousLatestTransition
}

enum WorkspaceRepositoryIndexError: Error, Equatable, LocalizedError {
    case invalidRoot(String)
    case invalidGenerationReceipt(String)
    case invalidCandidatePostimageAttestation(String)
    case workspaceRootMismatch
    case enumerationFailed(String)
    case escapedWorkspace(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRoot(path):
            return "The workspace repository root is not a readable directory: \(path)"
        case let .invalidGenerationReceipt(reason):
            return "The workspace tree-generation receipt is invalid: \(reason)"
        case let .invalidCandidatePostimageAttestation(reason):
            return "The candidate-postimage attestation is invalid: \(reason)"
        case .workspaceRootMismatch:
            return "The tree-generation receipt belongs to a different canonical workspace root."
        case let .enumerationFailed(path):
            return "Repository indexing stopped after a filesystem enumeration error at \(path)."
        case let .escapedWorkspace(path):
            return "Repository indexing rejected a path outside the canonical workspace: \(path)"
        }
    }
}

/// Journal-owned authority for the exact, content-complete source tree that a
/// later verifier is allowed to inspect. An executor receipt alone cannot mint
/// this value: issuance requires the matching reducer-accepted apply event and
/// its recovered journal frame.
struct WorkspaceCandidatePostimageAttestationReceipt: Equatable, Sendable {
    let integrationTransactionID: IntegrationTransactionID
    let workspaceID: WorkspaceID
    let canonicalRootDigest: ContentDigest
    let candidatePostimage: WorkspaceSourceRevisionArtifact
    let applyReceiptID: ReceiptID
    let journalTransaction: JournalTransactionReceipt

    private init(
        integrationTransactionID: IntegrationTransactionID,
        workspaceID: WorkspaceID,
        canonicalRootDigest: ContentDigest,
        candidatePostimage: WorkspaceSourceRevisionArtifact,
        applyReceiptID: ReceiptID,
        journalTransaction: JournalTransactionReceipt
    ) {
        self.integrationTransactionID = integrationTransactionID
        self.workspaceID = workspaceID
        self.canonicalRootDigest = canonicalRootDigest
        self.candidatePostimage = candidatePostimage
        self.applyReceiptID = applyReceiptID
        self.journalTransaction = journalTransaction
    }

    fileprivate static func accepted(
        integrationTransactionID: IntegrationTransactionID,
        workspaceID: WorkspaceID,
        root: URL,
        candidatePostimage: WorkspaceSourceRevisionArtifact,
        applyReceiptID: ReceiptID,
        journalTransaction: JournalTransactionReceipt
    ) throws -> WorkspaceCandidatePostimageAttestationReceipt {
        let receipt = WorkspaceCandidatePostimageAttestationReceipt(
            integrationTransactionID: integrationTransactionID,
            workspaceID: workspaceID,
            canonicalRootDigest: WorkspaceRepositoryIndexer.canonicalRootDigest(root),
            candidatePostimage: candidatePostimage,
            applyReceiptID: applyReceiptID,
            journalTransaction: journalTransaction
        )
        return try receipt.validated(for: root)
    }

#if DEBUG
    /// Synthetic authority for materialization-mechanics tests only. Release
    /// builds retain no caller-mintable attestation initializer.
    static func testOnlyAccepted(
        integrationTransactionID: IntegrationTransactionID =
            IntegrationTransactionID("test-integration"),
        workspaceID: WorkspaceID,
        root: URL,
        candidatePostimage: WorkspaceSourceRevisionArtifact,
        applyReceiptID: ReceiptID,
        journalTransaction: JournalTransactionReceipt
    ) throws -> WorkspaceCandidatePostimageAttestationReceipt {
        try accepted(
            integrationTransactionID: integrationTransactionID,
            workspaceID: workspaceID,
            root: root,
            candidatePostimage: candidatePostimage,
            applyReceiptID: applyReceiptID,
            journalTransaction: journalTransaction
        )
    }
#endif

    func validated(
        for root: URL
    ) throws -> WorkspaceCandidatePostimageAttestationReceipt {
        guard !integrationTransactionID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !workspaceID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !applyReceiptID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw WorkspaceRepositoryIndexError
                .invalidCandidatePostimageAttestation(
                    "workspace and apply identities must be present"
                )
        }
        guard candidatePostimage.validationIssues().isEmpty,
              candidatePostimage.workspaceID == workspaceID,
              candidatePostimage.canonicalRootDigest == canonicalRootDigest else {
            throw WorkspaceRepositoryIndexError
                .invalidCandidatePostimageAttestation(
                    "candidate artifact does not match the workspace binding"
                )
        }
        guard canonicalRootDigest == WorkspaceRepositoryIndexer.canonicalRootDigest(root) else {
            throw WorkspaceRepositoryIndexError.workspaceRootMismatch
        }
        guard !journalTransaction.commandID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !journalTransaction.eventIDs.isEmpty,
        Set(journalTransaction.eventIDs.map(\.rawValue)).count ==
            journalTransaction.eventIDs.count,
        journalTransaction.endingSequence >= journalTransaction.startingSequence,
        journalTransaction.endingSequence - journalTransaction.startingSequence ==
            UInt64(journalTransaction.eventIDs.count - 1) else {
            throw WorkspaceRepositoryIndexError
                .invalidCandidatePostimageAttestation(
                    "journal provenance is incomplete or internally inconsistent"
                )
        }
        return self
    }
}

/// Authority for a cross-observation repository-index cache key.
///
/// A caller cannot mint this from a path, mtime, task label, or model claim.
/// It must supply the exact journal transaction that accepted the source-tree
/// generation. The generation digest is the immutable source revision or
/// mutation-result digest accepted by that transaction.
struct WorkspaceTreeGenerationReceipt: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let canonicalRootDigest: ContentDigest
    let generationDigest: ContentDigest
    let authority: WorkspaceTreeGenerationAuthority
    let journalTransaction: JournalTransactionReceipt

    private init(
        workspaceID: WorkspaceID,
        canonicalRootDigest: ContentDigest,
        generationDigest: ContentDigest,
        authority: WorkspaceTreeGenerationAuthority,
        journalTransaction: JournalTransactionReceipt
    ) {
        self.workspaceID = workspaceID
        self.canonicalRootDigest = canonicalRootDigest
        self.generationDigest = generationDigest
        self.authority = authority
        self.journalTransaction = journalTransaction
    }

    fileprivate static func accepted(
        workspaceID: WorkspaceID,
        root: URL,
        generationDigest: ContentDigest,
        authority: WorkspaceTreeGenerationAuthority,
        journalTransaction: JournalTransactionReceipt
    ) throws -> WorkspaceTreeGenerationReceipt {
        let receipt = WorkspaceTreeGenerationReceipt(
            workspaceID: workspaceID,
            canonicalRootDigest: WorkspaceRepositoryIndexer.canonicalRootDigest(root),
            generationDigest: generationDigest,
            authority: authority,
            journalTransaction: journalTransaction
        )
        return try receipt.validated(for: root)
    }

#if DEBUG
    /// Synthetic authority for cache-mechanics tests only. Release builds do
    /// not contain a caller-mintable receipt initializer.
    static func testOnlyAccepted(
        workspaceID: WorkspaceID,
        root: URL,
        generationDigest: ContentDigest,
        authority: WorkspaceTreeGenerationAuthority,
        journalTransaction: JournalTransactionReceipt
    ) throws -> WorkspaceTreeGenerationReceipt {
        try accepted(
            workspaceID: workspaceID,
            root: root,
            generationDigest: generationDigest,
            authority: authority,
            journalTransaction: journalTransaction
        )
    }
#endif

    func validated(for root: URL) throws -> WorkspaceTreeGenerationReceipt {
        guard !workspaceID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceRepositoryIndexError.invalidGenerationReceipt("workspace identity is empty")
        }
        guard Self.isSHA256(canonicalRootDigest),
              Self.isSHA256(generationDigest),
              Self.isSHA256(journalTransaction.frameDigest) else {
            throw WorkspaceRepositoryIndexError.invalidGenerationReceipt("all authority digests must be SHA-256")
        }
        guard !journalTransaction.commandID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !journalTransaction.eventIDs.isEmpty,
              Set(journalTransaction.eventIDs.map(\.rawValue)).count == journalTransaction.eventIDs.count,
              journalTransaction.endingSequence >= journalTransaction.startingSequence,
              journalTransaction.endingSequence - journalTransaction.startingSequence ==
                UInt64(journalTransaction.eventIDs.count - 1) else {
            throw WorkspaceRepositoryIndexError.invalidGenerationReceipt("journal provenance is incomplete or internally inconsistent")
        }
        guard canonicalRootDigest == WorkspaceRepositoryIndexer.canonicalRootDigest(root) else {
            throw WorkspaceRepositoryIndexError.workspaceRootMismatch
        }
        return self
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64
            && digest.rawValue.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
            }
    }
}

extension RunJournal {
    /// Issues only the latest unambiguous tree generation. A caller cannot
    /// select an older successful transaction after a newer effect made the
    /// workspace state uncertain.
    func latestAcceptedWorkspaceTreeGenerationReceipt(
        workspaceID: WorkspaceID,
        root: URL
    ) throws -> WorkspaceTreeGenerationReceiptResolution {
        switch latestWorkspaceTreeGenerationEvent() {
        case .noWorkspaceTransition:
            return .noWorkspaceTransition
        case .ambiguousLatestTransition:
            return .ambiguousLatestTransition
        case .accepted(let event):
            return .accepted(try WorkspaceTreeGenerationReceipt.accepted(
                workspaceID: workspaceID,
                root: root,
                generationDigest: event.generationDigest,
                authority: event.authority,
                journalTransaction: event.journalTransaction
            ))
        }
    }

    /// Issues only the newest unambiguous candidate tree. Rollback, failed
    /// effects, and exact legacy applies without a complete capture all
    /// withhold attestation instead of falling back to older source bytes.
    func latestAcceptedWorkspaceCandidatePostimageAttestation(
        workspaceID: WorkspaceID,
        root: URL
    ) throws -> WorkspaceCandidatePostimageAttestationResolution {
        switch latestWorkspaceTreeGenerationEvent() {
        case .noWorkspaceTransition:
            return .noWorkspaceTransition
        case .ambiguousLatestTransition:
            return .ambiguousLatestTransition
        case .accepted(let event):
            guard event.authority == .journaledMutationCommit,
                  let candidatePostimage = event.candidatePostimage,
                  let applyReceiptID = event.applyReceiptID else {
                return .unavailableForLatestTransition
            }
            return .accepted(try WorkspaceCandidatePostimageAttestationReceipt.accepted(
                integrationTransactionID: event.transactionID,
                workspaceID: workspaceID,
                root: root,
                candidatePostimage: candidatePostimage,
                applyReceiptID: applyReceiptID,
                journalTransaction: event.journalTransaction
            ))
        }
    }
}

struct WorkspaceRepositoryEntry: Codable, Equatable, Sendable {
    let relativePath: String
    let size: Int64
    let modifiedAt: TimeInterval
}

struct WorkspaceRepositoryIndex: Codable, Equatable, Sendable {
    let canonicalRootDigest: ContentDigest
    let entries: [WorkspaceRepositoryEntry]
    let observedMetadataDigest: ContentDigest

    var fingerprint: [String: WorkspaceFileStamp] {
        Dictionary(uniqueKeysWithValues: entries.map {
            ($0.relativePath, WorkspaceFileStamp(size: $0.size, modifiedAt: $0.modifiedAt))
        })
    }
}

enum WorkspaceRepositoryIndexDisposition: String, Codable, Equatable, Sendable {
    case sharedObservation
    case uncachedObservation
    case computed
    case memoryHit
    case diskHit
    case coalescedHit
}

struct WorkspaceRepositoryIndexResolution: Sendable {
    let index: WorkspaceRepositoryIndex
    let disposition: WorkspaceRepositoryIndexDisposition
    let authority: WorkspaceTreeGenerationAuthority?
    let sourceSequence: UInt64?
    let cacheReceipt: HeavyEvidenceCacheReceipt?

    var evidenceSummary: String {
        if let authority, let sourceSequence, let cacheReceipt {
            return "\(disposition.rawValue); authority \(authority.rawValue); source sequence \(sourceSequence); generation-key \(cacheReceipt.keyDigest.rawValue.prefix(12)); observed-index \(index.observedMetadataDigest.rawValue.prefix(12))"
        }
        if disposition == .sharedObservation {
            return "sharedObservation; caller-shared single-observation projection; no cross-observation authority; observed-index \(index.observedMetadataDigest.rawValue.prefix(12))"
        }
        return "uncachedObservation; no authoritative tree-generation receipt; observed-index \(index.observedMetadataDigest.rawValue.prefix(12))"
    }
}

/// Produces one deterministic metadata projection per workspace observation.
/// Cross-observation reuse is allowed only when a journal-bound generation
/// receipt is present. Without one, every call scans once and cannot report a
/// cache hit.
struct WorkspaceRepositoryIndexer: Sendable {
    static let runtimeIgnoredDirectories: Set<String> = [
        ".git", ".build", "build", "dist", "DerivedData", "node_modules", "Pods", ".venv", "venv", "__pycache__"
    ]

    private let heavyEvidenceCache: HeavyEvidenceCache
    private let ignoredDirectories: Set<String>

    init(
        heavyEvidenceCache: HeavyEvidenceCache = .shared,
        ignoredDirectories: Set<String> = Self.runtimeIgnoredDirectories
    ) {
        self.heavyEvidenceCache = heavyEvidenceCache
        self.ignoredDirectories = ignoredDirectories
    }

    func resolve(
        root: URL,
        generationReceipt: WorkspaceTreeGenerationReceipt?
    ) async throws -> WorkspaceRepositoryIndexResolution {
        guard let generationReceipt else {
            return WorkspaceRepositoryIndexResolution(
                index: try Self.scan(root: root, ignoredDirectories: ignoredDirectories),
                disposition: .uncachedObservation,
                authority: nil,
                sourceSequence: nil,
                cacheReceipt: nil
            )
        }

        let receipt = try generationReceipt.validated(for: root)
        let parameters = "workspace-repository-index-v2|ignored=\(ignoredDirectories.sorted().joined(separator: ","))|symlinks=reject-files|errors=fail-closed"
        let key = HeavyEvidenceCacheKey(
            operation: .repositoryIndex,
            collectorID: "loopforge.workspace-repository-index",
            collectorVersion: 2,
            inputs: [
                HeavyEvidenceInput(role: "canonical-root", digest: receipt.canonicalRootDigest),
                HeavyEvidenceInput(role: "tree-generation", digest: receipt.generationDigest),
                HeavyEvidenceInput(
                    role: "workspace-identity",
                    digest: HeavyEvidenceCache.sha256(receipt.workspaceID.rawValue)
                ),
                HeavyEvidenceInput(role: "journal-authority", digest: receipt.journalTransaction.frameDigest)
            ],
            parametersDigest: HeavyEvidenceCache.sha256(parameters)
        )
        let ignored = ignoredDirectories
        let resolution: HeavyEvidenceCacheResolution<WorkspaceRepositoryIndex> = try await heavyEvidenceCache.resolve(
            key: key
        ) {
            try Self.scan(root: root, ignoredDirectories: ignored)
        }
        return WorkspaceRepositoryIndexResolution(
            index: resolution.value,
            disposition: Self.disposition(resolution.receipt.disposition),
            authority: receipt.authority,
            sourceSequence: receipt.journalTransaction.endingSequence,
            cacheReceipt: resolution.receipt
        )
    }

    static func scan(
        root: URL,
        ignoredDirectories: Set<String> = runtimeIgnoredDirectories
    ) throws -> WorkspaceRepositoryIndex {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootValues = try? canonicalRoot.resourceValues(forKeys: [.isDirectoryKey])
        guard rootValues?.isDirectory == true else {
            throw WorkspaceRepositoryIndexError.invalidRoot(canonicalRoot.path)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .contentModificationDateKey
        ]
        var failedPath: String?
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { url, _ in
                failedPath = url.path
                return false
            }
        ) else {
            throw WorkspaceRepositoryIndexError.invalidRoot(canonicalRoot.path)
        }

        let rootPath = canonicalRoot.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var entries: [WorkspaceRepositoryEntry] = []
        for case let url as URL in enumerator {
            if ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                throw WorkspaceRepositoryIndexError.enumerationFailed(url.path)
            }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let standardized = url.standardizedFileURL.path
            guard standardized.hasPrefix(prefix) else {
                throw WorkspaceRepositoryIndexError.escapedWorkspace(standardized)
            }
            let relative = String(standardized.dropFirst(prefix.count))
            guard !relative.isEmpty, !relative.hasPrefix("../"), !relative.contains("/../") else {
                throw WorkspaceRepositoryIndexError.escapedWorkspace(standardized)
            }
            entries.append(
                WorkspaceRepositoryEntry(
                    relativePath: relative,
                    size: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
                )
            )
        }
        if let failedPath {
            throw WorkspaceRepositoryIndexError.enumerationFailed(failedPath)
        }
        entries.sort { $0.relativePath < $1.relativePath }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let observedDigest = HeavyEvidenceCache.sha256(try encoder.encode(entries))
        return WorkspaceRepositoryIndex(
            canonicalRootDigest: canonicalRootDigest(canonicalRoot),
            entries: entries,
            observedMetadataDigest: observedDigest
        )
    }

    static func canonicalRootDigest(_ root: URL) -> ContentDigest {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL.path
        return HeavyEvidenceCache.sha256("canonical-workspace-root-v1|\(canonical)")
    }

    private static func disposition(_ value: HeavyEvidenceCacheDisposition) -> WorkspaceRepositoryIndexDisposition {
        switch value {
        case .computed: return .computed
        case .memoryHit: return .memoryHit
        case .diskHit: return .diskHit
        case .coalescedHit: return .coalescedHit
        }
    }
}
