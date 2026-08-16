import CryptoKit
import Foundation

/// A regular-file delta derived only from two validated, content-complete
/// source-revision artifacts. This is inert evidence: it deliberately carries
/// no journal receipt IDs and therefore cannot authorize filesystem effects.
struct WorkspaceSourceDeltaOperation: Codable, Hashable, Sendable {
    var sequence: Int
    var kind: MutationOperationKind
    var path: String
    var expectedPreimage: ContentDigest?
    var desiredPostimage: ContentDigest?
    var modeBefore: UInt32?
    var modeAfter: UInt32?
    var requirementIDs: Set<RequirementID>
}

struct WorkspaceMutationContentReference: Codable, Hashable, Sendable {
    var contentDigest: ContentDigest
    var size: UInt64
}

/// Content-addressed proposal evidence. A journal-owned runtime must still
/// bind these operations to a ratified node, issue path/write/budget facts,
/// assemble a MutationManifest, rehearse rollback, and authorize preflight.
struct WorkspaceMutationOperationDerivationReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var capturePolicyDigest: ContentDigest
    var baseSourceRevision: ContentDigest
    var candidateSourceRevision: ContentDigest
    var operations: [WorkspaceSourceDeltaOperation]
    var touchedRequirementIDs: Set<RequirementID>
    var contentObjects: [WorkspaceMutationContentReference]
    var derivationDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported derivation schema") }
        if operations.isEmpty { issues.append("derived operation set must not be empty") }
        if operations.map(\.sequence) != Array(1...operations.count) {
            issues.append("derived operations must have contiguous sequence numbers")
        }
        if operations != operations.sorted(by: {
            ($0.path, $0.kind.rawValue) < ($1.path, $1.kind.rawValue)
        }) {
            issues.append("derived operations must be canonically path-sorted")
        }
        if Set(operations.map(\.path)).count != operations.count {
            issues.append("derived operation paths must be unique")
        }
        let observedRequirements = operations.reduce(into: Set<RequirementID>()) {
            $0.formUnion($1.requirementIDs)
        }
        if observedRequirements != touchedRequirementIDs
            || touchedRequirementIDs.isEmpty {
            issues.append("derived requirement ownership is inconsistent")
        }
        if contentObjects != contentObjects.sorted(by: {
            $0.contentDigest.rawValue < $1.contentDigest.rawValue
        }) || Set(contentObjects.map(\.contentDigest)).count != contentObjects.count {
            issues.append("content references must be uniquely digest-sorted")
        }
        if Self.digest(for: self) != derivationDigest {
            issues.append("derivation digest mismatch")
        }
        return issues
    }

    fileprivate static func digest(
        for receipt: WorkspaceMutationOperationDerivationReceipt
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            workspaceID: receipt.workspaceID,
            canonicalRootDigest: receipt.canonicalRootDigest,
            capturePolicyDigest: receipt.capturePolicyDigest,
            baseSourceRevision: receipt.baseSourceRevision,
            candidateSourceRevision: receipt.candidateSourceRevision,
            operations: receipt.operations.map {
                CanonicalOperation(
                    sequence: $0.sequence,
                    kind: $0.kind,
                    path: $0.path,
                    expectedPreimage: $0.expectedPreimage,
                    desiredPostimage: $0.desiredPostimage,
                    modeBefore: $0.modeBefore,
                    modeAfter: $0.modeAfter,
                    requirementIDs: $0.requirementIDs.sorted {
                        $0.rawValue < $1.rawValue
                    }
                )
            },
            touchedRequirementIDs: receipt.touchedRequirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            contentObjects: receipt.contentObjects
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var workspaceID: WorkspaceID
        var canonicalRootDigest: ContentDigest
        var capturePolicyDigest: ContentDigest
        var baseSourceRevision: ContentDigest
        var candidateSourceRevision: ContentDigest
        var operations: [CanonicalOperation]
        var touchedRequirementIDs: [RequirementID]
        var contentObjects: [WorkspaceMutationContentReference]
    }

    private struct CanonicalOperation: Codable {
        var sequence: Int
        var kind: MutationOperationKind
        var path: String
        var expectedPreimage: ContentDigest?
        var desiredPostimage: ContentDigest?
        var modeBefore: UInt32?
        var modeAfter: UInt32?
        var requirementIDs: [RequirementID]
    }
}

enum WorkspaceMutationOperationDerivationError: Error, Equatable, Sendable {
    case invalidBaseArtifact
    case invalidCandidateArtifact
    case workspaceMismatch
    case canonicalRootMismatch
    case capturePolicyMismatch
    case emptyRequirementAuthority
    case invalidRequirementAuthority(String)
    case invalidPathAuthority(String)
    case pathOutsideAuthority(String)
    case caseFoldedPathCollision(String, String)
    case unsupportedParentTopology(String)
    case simultaneousContentAndModeChange(String)
    case inconsistentContentObjectSize(ContentDigest)
    case emptyDelta
    case encodingFailed
}

struct WorkspaceMutationOperationDeriver: Sendable {
    func derive(
        base: WorkspaceSourceRevisionArtifact,
        candidate: WorkspaceSourceRevisionArtifact,
        requirementIDs: Set<RequirementID>,
        authorizedPaths: Set<String>
    ) throws -> WorkspaceMutationOperationDerivationReceipt {
        guard base.validationIssues().isEmpty else {
            throw WorkspaceMutationOperationDerivationError.invalidBaseArtifact
        }
        guard candidate.validationIssues().isEmpty else {
            throw WorkspaceMutationOperationDerivationError.invalidCandidateArtifact
        }
        guard base.workspaceID == candidate.workspaceID else {
            throw WorkspaceMutationOperationDerivationError.workspaceMismatch
        }
        guard base.canonicalRootDigest == candidate.canonicalRootDigest else {
            throw WorkspaceMutationOperationDerivationError.canonicalRootMismatch
        }
        guard base.capturePolicyDigest == candidate.capturePolicyDigest else {
            throw WorkspaceMutationOperationDerivationError.capturePolicyMismatch
        }
        guard !requirementIDs.isEmpty else {
            throw WorkspaceMutationOperationDerivationError.emptyRequirementAuthority
        }
        if let invalidRequirement = requirementIDs.map(\.rawValue).sorted().first(
            where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ) {
            throw WorkspaceMutationOperationDerivationError
                .invalidRequirementAuthority(invalidRequirement)
        }
        if let invalidPath = authorizedPaths.sorted().first(where: {
            !WorkspaceSourceRevisionCollector.validRelativePath($0)
        }) {
            throw WorkspaceMutationOperationDerivationError.invalidPathAuthority(
                invalidPath
            )
        }

        let baseByPath = Dictionary(uniqueKeysWithValues: base.entries.map {
            ($0.relativePath, $0)
        })
        let candidateByPath = Dictionary(uniqueKeysWithValues: candidate.entries.map {
            ($0.relativePath, $0)
        })
        let baseDirectories = impliedDirectories(in: base.entries)
        let paths = Set(baseByPath.keys).union(candidateByPath.keys).sorted()
        try rejectFoldedPathCollisions(paths)
        var operations: [WorkspaceSourceDeltaOperation] = []
        var contentSizes: [ContentDigest: UInt64] = [:]

        for path in paths {
            let before = baseByPath[path]
            let after = candidateByPath[path]
            guard before != after else { continue }
            guard authorizedPaths.contains(path) else {
                throw WorkspaceMutationOperationDerivationError
                    .pathOutsideAuthority(path)
            }
            if before == nil,
               let parent = parentPath(of: path),
               !baseDirectories.contains(parent) {
                throw WorkspaceMutationOperationDerivationError
                    .unsupportedParentTopology(path)
            }

            let operation: WorkspaceSourceDeltaOperation
            switch (before, after) {
            case (nil, let after?):
                operation = WorkspaceSourceDeltaOperation(
                    sequence: 0,
                    kind: .create,
                    path: path,
                    expectedPreimage: nil,
                    desiredPostimage: after.contentDigest,
                    modeBefore: nil,
                    modeAfter: after.mode,
                    requirementIDs: requirementIDs
                )
            case (let before?, nil):
                operation = WorkspaceSourceDeltaOperation(
                    sequence: 0,
                    kind: .delete,
                    path: path,
                    expectedPreimage: before.contentDigest,
                    desiredPostimage: nil,
                    modeBefore: before.mode,
                    modeAfter: nil,
                    requirementIDs: requirementIDs
                )
            case (let before?, let after?):
                let contentChanged = before.contentDigest != after.contentDigest
                let modeChanged = before.mode != after.mode
                guard !(contentChanged && modeChanged) else {
                    throw WorkspaceMutationOperationDerivationError
                        .simultaneousContentAndModeChange(path)
                }
                operation = WorkspaceSourceDeltaOperation(
                    sequence: 0,
                    kind: contentChanged ? .modify : .chmod,
                    path: path,
                    expectedPreimage: before.contentDigest,
                    desiredPostimage: after.contentDigest,
                    modeBefore: before.mode,
                    modeAfter: after.mode,
                    requirementIDs: requirementIDs
                )
            case (nil, nil):
                continue
            }
            operations.append(operation)
            if let before {
                try recordContent(before, in: &contentSizes)
            }
            if let after {
                try recordContent(after, in: &contentSizes)
            }
        }
        guard !operations.isEmpty else {
            throw WorkspaceMutationOperationDerivationError.emptyDelta
        }
        for index in operations.indices {
            operations[index].sequence = index + 1
        }
        let contentObjects = contentSizes.map {
            WorkspaceMutationContentReference(contentDigest: $0.key, size: $0.value)
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        var receipt = WorkspaceMutationOperationDerivationReceipt(
            schemaVersion: 1,
            workspaceID: base.workspaceID,
            canonicalRootDigest: base.canonicalRootDigest,
            capturePolicyDigest: base.capturePolicyDigest,
            baseSourceRevision: base.sourceRevision,
            candidateSourceRevision: candidate.sourceRevision,
            operations: operations,
            touchedRequirementIDs: requirementIDs,
            contentObjects: contentObjects,
            derivationDigest: ContentDigest("")
        )
        guard let digest = WorkspaceMutationOperationDerivationReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceMutationOperationDerivationError.encodingFailed
        }
        receipt.derivationDigest = digest
        return receipt
    }

    private func impliedDirectories(
        in entries: [WorkspaceSourceRevisionEntry]
    ) -> Set<String> {
        entries.reduce(into: Set<String>()) { result, entry in
            let components = entry.relativePath.split(separator: "/").map(String.init)
            guard components.count > 1 else { return }
            for count in 1..<components.count {
                result.insert(components.prefix(count).joined(separator: "/"))
            }
        }
    }

    private func parentPath(of path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    private func recordContent(
        _ entry: WorkspaceSourceRevisionEntry,
        in sizes: inout [ContentDigest: UInt64]
    ) throws {
        if let existing = sizes[entry.contentDigest], existing != entry.size {
            throw WorkspaceMutationOperationDerivationError
                .inconsistentContentObjectSize(entry.contentDigest)
        }
        sizes[entry.contentDigest] = entry.size
    }

    private func rejectFoldedPathCollisions(_ paths: [String]) throws {
        var observed: [String: String] = [:]
        for path in paths.sorted() {
            let folded = path.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            if let prior = observed[folded], prior != path {
                throw WorkspaceMutationOperationDerivationError
                    .caseFoldedPathCollision(prior, path)
            }
            observed[folded] = path
        }
    }
}
