import CryptoKit
import Darwin
import Foundation
import Security

struct WorkspaceIgnoredPathClassification: Codable, Hashable, Sendable {
    var path: String
    var isIgnored: Bool
}

struct WorkspaceRepositoryPolicyFileObservation: Codable, Hashable, Sendable {
    var role: String
    var present: Bool
    var contentDigest: ContentDigest
    var size: UInt64
}

/// Exact repository facts that cannot be inferred from plane membership. Raw
/// Git configuration never enters the journal; unsupported external policy is
/// rejected and relevant effective semantics are retained as typed values.
struct WorkspaceRepositoryMetadataObservation: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var objectFormat: String
    var symbolicHead: String?
    var isShallow: Bool
    var headCommitObjectID: String
    var gitDirectoryIdentityDigest: ContentDigest
    var gitCommonDirectoryIdentityDigest: ContentDigest
    var gitExecutableDigest: ContentDigest
    var gitPlaneObservationDigest: ContentDigest
    var policyFiles: [WorkspaceRepositoryPolicyFileObservation]
    var metadataPolicyDigest: ContentDigest
    var repositoryMetadataDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported repository metadata schema") }
        if objectFormat != "sha1" && objectFormat != "sha256" {
            issues.append("unsupported Git object format")
        }
        if !Self.validGitObjectID(headCommitObjectID) {
            issues.append("repository metadata HEAD object identity is invalid")
        }
        if let symbolicHead,
           !symbolicHead.hasPrefix("refs/heads/")
            || symbolicHead.contains("\0") {
            issues.append("symbolic HEAD is not canonical")
        }
        if !Self.isSHA256(gitDirectoryIdentityDigest)
            || !Self.isSHA256(gitCommonDirectoryIdentityDigest)
            || !Self.isSHA256(gitExecutableDigest)
            || !Self.isSHA256(gitPlaneObservationDigest)
            || !Self.isSHA256(metadataPolicyDigest)
            || !Self.isSHA256(repositoryMetadataDigest) {
            issues.append("repository metadata digests must be SHA-256")
        }
        if policyFiles != policyFiles.sorted(by: { $0.role < $1.role })
            || Set(policyFiles.map(\.role)).count != policyFiles.count {
            issues.append("repository policy files must be uniquely role-sorted")
        }
        for file in policyFiles where file.role.isEmpty
            || !Self.isSHA256(file.contentDigest)
            || (!file.present && file.size != 0) {
            issues.append("repository policy-file observation is malformed")
        }
        if Self.digest(for: self) != repositoryMetadataDigest {
            issues.append("repository metadata digest mismatch")
        }
        return issues
    }

    static func digest(
        for value: WorkspaceRepositoryMetadataObservation
    ) -> ContentDigest? {
        canonicalDigest(Material(
            schemaVersion: value.schemaVersion,
            objectFormat: value.objectFormat,
            symbolicHead: value.symbolicHead,
            isShallow: value.isShallow,
            headCommitObjectID: value.headCommitObjectID,
            gitDirectoryIdentityDigest: value.gitDirectoryIdentityDigest,
            gitCommonDirectoryIdentityDigest:
                value.gitCommonDirectoryIdentityDigest,
            gitExecutableDigest: value.gitExecutableDigest,
            gitPlaneObservationDigest: value.gitPlaneObservationDigest,
            policyFiles: value.policyFiles,
            metadataPolicyDigest: value.metadataPolicyDigest
        ))
    }

    fileprivate static func canonicalDigest<T: Encodable>(
        _ value: T
    ) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    fileprivate static func isSHA256(_ value: ContentDigest) -> Bool {
        value.rawValue.count == 64 && value.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func validGitObjectID(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private struct Material: Codable {
        var schemaVersion: Int
        var objectFormat: String
        var symbolicHead: String?
        var isShallow: Bool
        var headCommitObjectID: String
        var gitDirectoryIdentityDigest: ContentDigest
        var gitCommonDirectoryIdentityDigest: ContentDigest
        var gitExecutableDigest: ContentDigest
        var gitPlaneObservationDigest: ContentDigest
        var policyFiles: [WorkspaceRepositoryPolicyFileObservation]
        var metadataPolicyDigest: ContentDigest
    }
}

/// Journal-owned canonical assembly of four independently observed planes plus
/// repository and ignore-policy facts. It is evidence only: it cannot issue a
/// manifest, preflight receipt, write authority, or filesystem effect.
struct WorkspaceJournaledCanonicalPreimageReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var gitPreimageCaptureReceiptDigest: ContentDigest
    var captureActor: ActorIdentity
    var capturedAt: Date
    var repositoryMetadata: WorkspaceRepositoryMetadataObservation
    var ignoredPathClassifications: [WorkspaceIgnoredPathClassification]
    var ignoredPathPolicyDigest: ContentDigest
    var worktree: WorkspacePreimagePlaneArtifact
    var preimage: WorkspacePreimage
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported canonical preimage schema") }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || captureActor.id.rawValue.isEmpty
            || captureActor.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || captureActor.lineageDigest.rawValue.isEmpty {
            issues.append("canonical preimage authority identity must not be empty")
        }
        if !WorkspaceRepositoryMetadataObservation.isSHA256(
            gitPreimageCaptureReceiptDigest
        ) || !WorkspaceRepositoryMetadataObservation.isSHA256(
            ignoredPathPolicyDigest
        ) || !WorkspaceRepositoryMetadataObservation.isSHA256(receiptDigest) {
            issues.append("canonical preimage authority digests must be SHA-256")
        }
        issues.append(contentsOf: repositoryMetadata.validationIssues())
        if ignoredPathClassifications != ignoredPathClassifications.sorted(by: {
            $0.path < $1.path
        }) || Set(ignoredPathClassifications.map(\.path)).count !=
            ignoredPathClassifications.count {
            issues.append("ignored-path classifications must be uniquely path-sorted")
        }
        if ignoredPathClassifications.contains(where: {
            !WorkspaceSourceRevisionCollector.validRelativePath($0.path)
        }) {
            issues.append("ignored-path classification contains a noncanonical path")
        }
        if Self.ignoredPolicyDigest(
            metadata: repositoryMetadata,
            classifications: ignoredPathClassifications
        ) != ignoredPathPolicyDigest {
            issues.append("ignored-path policy digest mismatch")
        }
        if !worktree.validationIssues().isEmpty
            || worktree.plane != .worktree
            || worktree.provenance != .confirmedWorkspaceSourceRevision {
            issues.append("canonical preimage worktree artifact is invalid")
        }
        let expectedEntries = preimage.entries.sorted {
            ($0.plane.rawValue, $0.path) < ($1.plane.rawValue, $1.path)
        }
        if preimage.entries != expectedEntries
            || preimage.requiredPlanes != Set(WorkspaceEntryPlane.allCases)
            || preimage.capturedPlanes != preimage.requiredPlanes
            || preimage.repositoryMetadataDigest !=
                repositoryMetadata.repositoryMetadataDigest
            || preimage.ignoredPathPolicyDigest != ignoredPathPolicyDigest
            || preimage.capturedAt != capturedAt
            || preimage.workspaceID != worktree.workspaceID
            || preimage.rootIdentity != worktree.rootIdentity
            || preimage.sourceRevision != worktree.sourceRevision {
            issues.append("canonical preimage assembly is inconsistent")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("canonical preimage receipt digest mismatch")
        }
        return issues
    }

    static func ignoredPolicyDigest(
        metadata: WorkspaceRepositoryMetadataObservation,
        classifications: [WorkspaceIgnoredPathClassification]
    ) -> ContentDigest? {
        WorkspaceRepositoryMetadataObservation.canonicalDigest(
            IgnoreMaterial(
                schemaVersion: 1,
                metadataPolicyDigest: metadata.metadataPolicyDigest,
                policyFiles: metadata.policyFiles,
                classifications: classifications
            )
        )
    }

    static func digest(
        for receipt: WorkspaceJournaledCanonicalPreimageReceipt
    ) -> ContentDigest? {
        WorkspaceRepositoryMetadataObservation.canonicalDigest(DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            runID: receipt.runID,
            contractID: receipt.contractID,
            gitPreimageCaptureReceiptDigest:
                receipt.gitPreimageCaptureReceiptDigest,
            captureActor: receipt.captureActor,
            capturedAt: receipt.capturedAt,
            repositoryMetadata: receipt.repositoryMetadata,
            ignoredPathClassifications: receipt.ignoredPathClassifications,
            ignoredPathPolicyDigest: receipt.ignoredPathPolicyDigest,
            worktree: receipt.worktree,
            canonicalPreimageDigest: receipt.preimage.canonicalDigest
        ))
    }

    private struct IgnoreMaterial: Codable {
        var schemaVersion: Int
        var metadataPolicyDigest: ContentDigest
        var policyFiles: [WorkspaceRepositoryPolicyFileObservation]
        var classifications: [WorkspaceIgnoredPathClassification]
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var runID: KernelRunID
        var contractID: TaskContractID
        var gitPreimageCaptureReceiptDigest: ContentDigest
        var captureActor: ActorIdentity
        var capturedAt: Date
        var repositoryMetadata: WorkspaceRepositoryMetadataObservation
        var ignoredPathClassifications: [WorkspaceIgnoredPathClassification]
        var ignoredPathPolicyDigest: ContentDigest
        var worktree: WorkspacePreimagePlaneArtifact
        var canonicalPreimageDigest: ContentDigest
    }
}

struct AuthorizedWorkspaceJournaledCanonicalPreimage: Sendable {
    let receipt: WorkspaceJournaledCanonicalPreimageReceipt
    private let issuerNonce: Data

    fileprivate init(
        receipt: WorkspaceJournaledCanonicalPreimageReceipt,
        issuerNonce: Data
    ) {
        self.receipt = receipt
        self.issuerNonce = issuerNonce
    }

    func validationIssues() -> [String] {
        receipt.validationIssues() + (issuerNonce.count == 32
            ? [] : ["canonical preimage capability nonce is invalid"])
    }

#if DEBUG
    static func testOnly(
        receipt: WorkspaceJournaledCanonicalPreimageReceipt
    ) -> AuthorizedWorkspaceJournaledCanonicalPreimage {
        AuthorizedWorkspaceJournaledCanonicalPreimage(
            receipt: receipt,
            issuerNonce: Data(repeating: 11, count: 32)
        )
    }
#endif
}

enum WorkspaceJournaledCanonicalPreimageError: Error, Equatable, Sendable {
    case invalidEnrollment
    case registrationMismatch
    case journalMismatch
    case missingGitPreimageCapture
    case repositoryChanged
    case unsupportedRepositoryPolicy(String)
    case commandFailed(String)
    case captureLimitExceeded
    case encodingFailed
}

actor WorkspaceJournaledCanonicalPreimageIssuer {
    private let registry: WorkspaceMutationRecoveryRegistry
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    init(registry: WorkspaceMutationRecoveryRegistry) {
        self.registry = registry
    }

    func capture(
        enrollment: KernelRunEnrollmentReceipt
    ) async throws -> AuthorizedWorkspaceJournaledCanonicalPreimage {
        guard enrollment.schemaVersion == 1,
              enrollment.runID == enrollment.registration.runID else {
            throw WorkspaceJournaledCanonicalPreimageError.invalidEnrollment
        }
        guard let registration = try await registry.registration(
            runID: enrollment.runID
        ), registration == enrollment.registration else {
            throw WorkspaceJournaledCanonicalPreimageError.registrationMismatch
        }
        let journal: RunJournal
        do {
            journal = try RunJournal(
                rootDirectory: registration.journalRoot,
                runID: registration.runID
            )
        } catch {
            throw WorkspaceJournaledCanonicalPreimageError.journalMismatch
        }
        guard let contract = await journal.currentContract(),
              contract.id == enrollment.contractID,
              let source = contract.sourceRevision,
              let retainedGit = await journal
                .journaledGitPreimageCaptureReceipt(),
              retainedGit.validationIssues().isEmpty,
              retainedGit.contractID == contract.id,
              retainedGit.runID == enrollment.runID else {
            throw WorkspaceJournaledCanonicalPreimageError
                .missingGitPreimageCapture
        }
        let root = registration.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        let gitIssuer = WorkspaceJournaledGitPreimageCaptureIssuer(
            registry: registry
        )
        let before = try await gitIssuer.capture(enrollment: enrollment).receipt
        guard sameObservation(before, retainedGit) else {
            throw WorkspaceJournaledCanonicalPreimageError.repositoryChanged
        }
        let first = try observe(
            root: root,
            source: source,
            git: retainedGit
        )
        let second = try observe(
            root: root,
            source: source,
            git: retainedGit
        )
        guard first == second else {
            throw WorkspaceJournaledCanonicalPreimageError.repositoryChanged
        }
        let after = try await gitIssuer.capture(enrollment: enrollment).receipt
        guard sameObservation(after, retainedGit) else {
            throw WorkspaceJournaledCanonicalPreimageError.repositoryChanged
        }
        let worktree: WorkspacePreimagePlaneArtifact
        do {
            worktree = try WorkspacePreimagePlaneProjector()
                .projectInitialWorktree(from: source)
        } catch {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        let planes = [retainedGit.head, retainedGit.index, worktree,
                      retainedGit.untracked]
        guard (try? WorkspacePreimagePlaneProjector().assessCoverage(
            requiredPlanes: Set(WorkspaceEntryPlane.allCases),
            artifacts: planes
        ).isComplete) == true else {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        guard let ignoredDigest =
            WorkspaceJournaledCanonicalPreimageReceipt.ignoredPolicyDigest(
                metadata: first.metadata,
                classifications: first.classifications
            ) else {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        let capturedAt = Date()
        let entries = planes.flatMap(\.entries).sorted {
            ($0.plane.rawValue, $0.path) < ($1.plane.rawValue, $1.path)
        }
        let preimage = WorkspacePreimage(
            workspaceID: source.workspaceID,
            rootIdentity: source.canonicalRootDigest,
            contractDigest: contract.objectiveDigest,
            sourceRevision: source.sourceRevision,
            requiredPlanes: Set(WorkspaceEntryPlane.allCases),
            capturedPlanes: Set(WorkspaceEntryPlane.allCases),
            entries: entries,
            repositoryMetadataDigest:
                first.metadata.repositoryMetadataDigest,
            ignoredPathPolicyDigest: ignoredDigest,
            capturedAt: capturedAt
        )
        var receipt = WorkspaceJournaledCanonicalPreimageReceipt(
            schemaVersion: 1,
            runID: enrollment.runID,
            contractID: contract.id,
            gitPreimageCaptureReceiptDigest: retainedGit.receiptDigest,
            captureActor: registration.actorIdentity,
            capturedAt: capturedAt,
            repositoryMetadata: first.metadata,
            ignoredPathClassifications: first.classifications,
            ignoredPathPolicyDigest: ignoredDigest,
            worktree: worktree,
            preimage: preimage,
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspaceJournaledCanonicalPreimageReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        receipt.receiptDigest = digest
        guard receipt.validationIssues().isEmpty else {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        var nonce = Data(count: 32)
        guard nonce.withUnsafeMutableBytes({
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }) == errSecSuccess else {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        return AuthorizedWorkspaceJournaledCanonicalPreimage(
            receipt: receipt,
            issuerNonce: nonce
        )
    }

    private struct Observation: Equatable {
        var metadata: WorkspaceRepositoryMetadataObservation
        var classifications: [WorkspaceIgnoredPathClassification]
    }

    private func observe(
        root: URL,
        source: WorkspaceSourceRevisionArtifact,
        git: WorkspaceJournaledGitPreimageCaptureReceipt
    ) throws -> Observation {
        guard try text(root, ["rev-parse", "--is-bare-repository"]) == "false"
        else {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy("bare-repository")
        }
        if try optionalText(root, ["config", "--get", "core.excludesFile"])
            != nil {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy("external-excludes-file")
        }
        if let sparseCheckout = try optionalText(
            root,
            ["config", "--get", "core.sparseCheckout"]
        ), sparseCheckout.lowercased() == "true" {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy("sparse-checkout")
        }
        let objectFormat = try text(root, ["rev-parse", "--show-object-format"])
        let commonText = try text(
            root,
            ["rev-parse", "--path-format=absolute", "--git-common-dir"]
        )
        let common = URL(fileURLWithPath: commonText).standardizedFileURL
            .resolvingSymlinksInPath()
        let commonIdentity = try directoryIdentity(common.path)
        let infoExcludeText = try text(
            root,
            ["rev-parse", "--path-format=absolute", "--git-path", "info/exclude"]
        )
        guard infoExcludeText.hasPrefix("/") else {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy("git-info-exclude")
        }
        let infoExclude = URL(fileURLWithPath: infoExcludeText)
            .standardizedFileURL
        let symbolicHead = try optionalText(root, ["symbolic-ref", "-q", "HEAD"])
        let isShallow = try text(
            root, ["rev-parse", "--is-shallow-repository"]
        ) == "true"
        var files = source.entries.filter {
            $0.relativePath.split(separator: "/").last == ".gitignore"
        }.map {
            WorkspaceRepositoryPolicyFileObservation(
                role: "worktree:\($0.relativePath)",
                present: true,
                contentDigest: $0.contentDigest,
                size: $0.size
            )
        }
        files.append(try policyFile(
            role: "git-info-exclude",
            url: infoExclude
        ))
        files.sort { $0.role < $1.role }
        let policy = digest(Data(
            "loopforge-repository-metadata-policy-v1\0global-config-disabled\0system-config-disabled\0external-excludes-rejected\0sparse-checkout-rejected".utf8
        ))
        var metadata = WorkspaceRepositoryMetadataObservation(
            schemaVersion: 1,
            objectFormat: objectFormat,
            symbolicHead: symbolicHead,
            isShallow: isShallow,
            headCommitObjectID: git.headCommitObjectID,
            gitDirectoryIdentityDigest: git.gitDirectoryIdentityDigest,
            gitCommonDirectoryIdentityDigest: commonIdentity,
            gitExecutableDigest: git.gitExecutableDigest,
            gitPlaneObservationDigest: git.repositoryObservationDigest,
            policyFiles: files,
            metadataPolicyDigest: policy,
            repositoryMetadataDigest: ContentDigest("")
        )
        guard let metadataDigest = WorkspaceRepositoryMetadataObservation
            .digest(for: metadata) else {
            throw WorkspaceJournaledCanonicalPreimageError.encodingFailed
        }
        metadata.repositoryMetadataDigest = metadataDigest
        let classifications = try git.untracked.entries.map { entry in
            let result = try runGit(
                root,
                ["check-ignore", "-q", "--", entry.path],
                maximumOutputBytes: 0,
                acceptedStatuses: [0, 1]
            )
            return WorkspaceIgnoredPathClassification(
                path: entry.path,
                isIgnored: result.status == 0
            )
        }.sorted { $0.path < $1.path }
        return Observation(metadata: metadata, classifications: classifications)
    }

    private func sameObservation(
        _ lhs: WorkspaceJournaledGitPreimageCaptureReceipt,
        _ rhs: WorkspaceJournaledGitPreimageCaptureReceipt
    ) -> Bool {
        lhs.runID == rhs.runID
            && lhs.contractID == rhs.contractID
            && lhs.workspaceID == rhs.workspaceID
            && lhs.canonicalRootDigest == rhs.canonicalRootDigest
            && lhs.baseSourceRevision == rhs.baseSourceRevision
            && lhs.capturePolicyDigest == rhs.capturePolicyDigest
            && lhs.headCommitObjectID == rhs.headCommitObjectID
            && lhs.gitDirectoryIdentityDigest == rhs.gitDirectoryIdentityDigest
            && lhs.gitExecutableDigest == rhs.gitExecutableDigest
            && lhs.untrackedObservationPolicyDigest ==
                rhs.untrackedObservationPolicyDigest
            && lhs.head == rhs.head && lhs.index == rhs.index
            && lhs.untracked == rhs.untracked
            && lhs.repositoryObservationDigest == rhs.repositoryObservationDigest
    }

    private func policyFile(
        role: String,
        url: URL
    ) throws -> WorkspaceRepositoryPolicyFileObservation {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if descriptor < 0 {
            guard errno == ENOENT else {
                throw WorkspaceJournaledCanonicalPreimageError
                    .unsupportedRepositoryPolicy(role)
            }
            return WorkspaceRepositoryPolicyFileObservation(
                role: role,
                present: false,
                contentDigest: digest(Data("absent".utf8)),
                size: 0
            )
        }
        defer { _ = close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0, before.st_size <= 1_048_576 else {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy(role)
        }
        let first = try readPolicyFile(
            descriptor: descriptor,
            expectedSize: Int(before.st_size),
            role: role
        )
        guard lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy(role)
        }
        let second = try readPolicyFile(
            descriptor: descriptor,
            expectedSize: Int(before.st_size),
            role: role
        )
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              first == second else {
            throw WorkspaceJournaledCanonicalPreimageError.repositoryChanged
        }
        return WorkspaceRepositoryPolicyFileObservation(
            role: role,
            present: true,
            contentDigest: digest(first),
            size: UInt64(first.count)
        )
    }

    private func readPolicyFile(
        descriptor: Int32,
        expectedSize: Int,
        role: String
    ) throws -> Data {
        var data = Data(count: expectedSize)
        let bytesRead = data.withUnsafeMutableBytes { buffer -> Int in
            var total = 0
            while total < expectedSize {
                let result = Darwin.read(
                    descriptor,
                    buffer.baseAddress!.advanced(by: total),
                    expectedSize - total
                )
                if result <= 0 { return result < 0 ? -1 : total }
                total += result
            }
            return total
        }
        guard bytesRead == expectedSize else {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy(role)
        }
        return data
    }

    private func directoryIdentity(_ path: String) throws -> ContentDigest {
        var status = stat()
        guard lstat(path, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceJournaledCanonicalPreimageError
                .unsupportedRepositoryPolicy("git-common-directory")
        }
        return digest(Data("\(path)\0\(status.st_dev)\0\(status.st_ino)".utf8))
    }

    private func text(_ root: URL, _ arguments: [String]) throws -> String {
        guard let value = try optionalText(root, arguments) else {
            throw WorkspaceJournaledCanonicalPreimageError.commandFailed(
                arguments.first ?? "git"
            )
        }
        return value
    }

    private func optionalText(
        _ root: URL,
        _ arguments: [String]
    ) throws -> String? {
        let result = try runGit(
            root,
            arguments,
            maximumOutputBytes: 64 * 1_024,
            acceptedStatuses: [0, 1]
        )
        if result.status == 1 { return nil }
        guard let value = String(data: result.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else { return nil }
        return value
    }

    private struct CommandResult {
        var status: Int32
        var data: Data
    }

    private func runGit(
        _ root: URL,
        _ arguments: [String],
        maximumOutputBytes: UInt64,
        acceptedStatuses: Set<Int32> = [0]
    ) throws -> CommandResult {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeGitMetadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = temporary.appendingPathComponent("stdout")
        guard FileManager.default.createFile(atPath: output.path, contents: nil)
        else {
            throw WorkspaceJournaledCanonicalPreimageError.commandFailed("temporary-output")
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", root.path] + arguments
        process.environment = [
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_OPTIONAL_LOCKS": "0",
            "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"
        ]
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            throw WorkspaceJournaledCanonicalPreimageError.commandFailed(
                arguments.first ?? "git"
            )
        }
        if finished.wait(timeout: .now() + 15) == .timedOut {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 2)
            throw WorkspaceJournaledCanonicalPreimageError.commandFailed("timeout")
        }
        try handle.synchronize()
        guard process.terminationReason == .exit,
              acceptedStatuses.contains(process.terminationStatus) else {
            throw WorkspaceJournaledCanonicalPreimageError.commandFailed(
                arguments.first ?? "git"
            )
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: output.path
        )
        guard let size = attributes[.size] as? NSNumber,
              size.uint64Value <= maximumOutputBytes else {
            throw WorkspaceJournaledCanonicalPreimageError.captureLimitExceeded
        }
        return CommandResult(
            status: process.terminationStatus,
            data: try Data(contentsOf: output, options: [.mappedIfSafe])
        )
    }

    private func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}
