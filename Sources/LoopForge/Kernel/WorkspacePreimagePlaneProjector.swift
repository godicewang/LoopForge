import CryptoKit
import Foundation

enum WorkspacePreimagePlaneProvenance: String, Codable, Hashable, Sendable {
    /// Exact initial worktree bytes retained by user-confirmed source-revision
    /// authority. This proves neither Git HEAD/index nor untracked membership.
    case confirmedWorkspaceSourceRevision
    /// One atomic, journal-accepted Git observation of HEAD, index, and all
    /// untracked regular files within the ratified capture policy.
    case journaledGitPreimageCapture
}

/// Content-addressed evidence for exactly one preimage plane. It remains inert
/// data: decoding or projecting it cannot construct WorkspacePreimage or issue
/// mutation authority.
struct WorkspacePreimagePlaneArtifact: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var provenance: WorkspacePreimagePlaneProvenance
    var plane: WorkspaceEntryPlane
    var workspaceID: WorkspaceID
    var rootIdentity: ContentDigest
    var sourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var entries: [WorkspaceEntrySnapshot]
    var contentObjects: [WorkspaceMutationContentReference]
    var artifactDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported preimage-plane schema") }
        let supported =
            (plane == .worktree
                && provenance == .confirmedWorkspaceSourceRevision)
            || ([.head, .index, .untracked].contains(plane)
                && provenance == .journaledGitPreimageCapture)
        if !supported {
            issues.append("unsupported preimage-plane provenance")
        }
        if workspaceID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            issues.append("workspace identity must not be empty")
        }
        for digest in [rootIdentity, sourceRevision, capturePolicyDigest]
            where !Self.isSHA256(digest) {
            issues.append("preimage-plane authority digests must be SHA-256")
        }
        if entries != entries.sorted(by: { $0.path < $1.path })
            || Set(entries.map(\.path)).count != entries.count {
            issues.append("preimage-plane entries must be uniquely path-sorted")
        }
        for entry in entries {
            if entry.plane != plane
                || entry.kind != .regularFile
                || entry.ownership != .userExisting {
                issues.append("preimage-plane projection contains unsupported entry semantics")
            }
            if !WorkspaceSourceRevisionCollector.validRelativePath(entry.path) {
                issues.append("worktree projection entry path is invalid")
            }
            if entry.mode > 0o7777 {
                issues.append("worktree projection entry mode is invalid")
            }
            if !Self.isSHA256(entry.contentDigest) {
                issues.append("worktree projection entry digest must be SHA-256")
            }
        }
        if contentObjects != contentObjects.sorted(by: {
            $0.contentDigest.rawValue < $1.contentDigest.rawValue
        }) || Set(contentObjects.map(\.contentDigest)).count != contentObjects.count {
            issues.append("content references must be uniquely digest-sorted")
        }
        var observedSizes: [ContentDigest: UInt64] = [:]
        for entry in entries {
            if let prior = observedSizes[entry.contentDigest], prior != entry.size {
                issues.append("one content digest has inconsistent byte sizes")
            }
            observedSizes[entry.contentDigest] = entry.size
        }
        let expectedObjects = observedSizes.map {
            WorkspaceMutationContentReference(contentDigest: $0.key, size: $0.value)
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        if contentObjects != expectedObjects {
            issues.append("content references do not exactly cover projected entries")
        }
        if Self.digest(for: self) != artifactDigest {
            issues.append("preimage-plane artifact digest mismatch")
        }
        return issues
    }

    static func digest(
        for artifact: WorkspacePreimagePlaneArtifact
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: artifact.schemaVersion,
            provenance: artifact.provenance,
            plane: artifact.plane,
            workspaceID: artifact.workspaceID,
            rootIdentity: artifact.rootIdentity,
            sourceRevision: artifact.sourceRevision,
            capturePolicyDigest: artifact.capturePolicyDigest,
            entries: artifact.entries,
            contentObjects: artifact.contentObjects
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var provenance: WorkspacePreimagePlaneProvenance
        var plane: WorkspaceEntryPlane
        var workspaceID: WorkspaceID
        var rootIdentity: ContentDigest
        var sourceRevision: ContentDigest
        var capturePolicyDigest: ContentDigest
        var entries: [WorkspaceEntrySnapshot]
        var contentObjects: [WorkspaceMutationContentReference]
    }
}

struct WorkspacePreimagePlaneCoverageAssessment: Codable, Hashable, Sendable {
    var requiredPlanes: Set<WorkspaceEntryPlane>
    var acceptedPlanes: Set<WorkspaceEntryPlane>
    var missingPlanes: Set<WorkspaceEntryPlane>

    var isComplete: Bool {
        !requiredPlanes.isEmpty && missingPlanes.isEmpty
    }
}

enum WorkspacePreimagePlaneProjectionError: Error, Equatable, Sendable {
    case invalidSourceRevision
    case inconsistentContentObjectSize(ContentDigest)
    case encodingFailed
    case emptyRequiredPlanes
    case invalidPlaneArtifact(Int)
    case duplicatePlane(WorkspaceEntryPlane)
    case identityMismatch(WorkspaceEntryPlane)
}

struct WorkspacePreimagePlaneProjector: Sendable {
    /// Projects only the initial worktree plane. Every entry is user-existing
    /// because the input is the exact source revision ratified before task
    /// mutation; later accepted generations require separate journal evidence.
    func projectInitialWorktree(
        from source: WorkspaceSourceRevisionArtifact
    ) throws -> WorkspacePreimagePlaneArtifact {
        guard source.validationIssues().isEmpty else {
            throw WorkspacePreimagePlaneProjectionError.invalidSourceRevision
        }
        let entries = source.entries.map {
            WorkspaceEntrySnapshot(
                plane: .worktree,
                path: $0.relativePath,
                kind: .regularFile,
                mode: $0.mode,
                contentDigest: $0.contentDigest,
                size: $0.size,
                ownership: .userExisting
            )
        }
        var sizes: [ContentDigest: UInt64] = [:]
        for entry in source.entries {
            if let prior = sizes[entry.contentDigest], prior != entry.size {
                throw WorkspacePreimagePlaneProjectionError
                    .inconsistentContentObjectSize(entry.contentDigest)
            }
            sizes[entry.contentDigest] = entry.size
        }
        let contentObjects = sizes.map {
            WorkspaceMutationContentReference(contentDigest: $0.key, size: $0.value)
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        var artifact = WorkspacePreimagePlaneArtifact(
            schemaVersion: 1,
            provenance: .confirmedWorkspaceSourceRevision,
            plane: .worktree,
            workspaceID: source.workspaceID,
            rootIdentity: source.canonicalRootDigest,
            sourceRevision: source.sourceRevision,
            capturePolicyDigest: source.capturePolicyDigest,
            entries: entries,
            contentObjects: contentObjects,
            artifactDigest: ContentDigest("")
        )
        guard let digest = WorkspacePreimagePlaneArtifact.digest(for: artifact) else {
            throw WorkspacePreimagePlaneProjectionError.encodingFailed
        }
        artifact.artifactDigest = digest
        return artifact
    }

    /// Assesses exact coverage only. It does not compose WorkspacePreimage and
    /// does not treat an empty plane as observed without a plane artifact.
    func assessCoverage(
        requiredPlanes: Set<WorkspaceEntryPlane>,
        artifacts: [WorkspacePreimagePlaneArtifact]
    ) throws -> WorkspacePreimagePlaneCoverageAssessment {
        guard !requiredPlanes.isEmpty else {
            throw WorkspacePreimagePlaneProjectionError.emptyRequiredPlanes
        }
        var accepted: Set<WorkspaceEntryPlane> = []
        var identity: (
            workspaceID: WorkspaceID,
            root: ContentDigest,
            revision: ContentDigest
        )?
        for (index, artifact) in artifacts.enumerated() {
            guard artifact.validationIssues().isEmpty else {
                throw WorkspacePreimagePlaneProjectionError.invalidPlaneArtifact(index)
            }
            guard accepted.insert(artifact.plane).inserted else {
                throw WorkspacePreimagePlaneProjectionError
                    .duplicatePlane(artifact.plane)
            }
            if let identity {
                guard identity.workspaceID == artifact.workspaceID,
                      identity.root == artifact.rootIdentity,
                      identity.revision == artifact.sourceRevision else {
                    throw WorkspacePreimagePlaneProjectionError
                        .identityMismatch(artifact.plane)
                }
            } else {
                identity = (
                    artifact.workspaceID,
                    artifact.rootIdentity,
                    artifact.sourceRevision
                )
            }
        }
        let acceptedRequired = accepted.intersection(requiredPlanes)
        return WorkspacePreimagePlaneCoverageAssessment(
            requiredPlanes: requiredPlanes,
            acceptedPlanes: acceptedRequired,
            missingPlanes: requiredPlanes.subtracting(acceptedRequired)
        )
    }
}
