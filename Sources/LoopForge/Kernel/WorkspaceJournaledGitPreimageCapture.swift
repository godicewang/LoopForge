import CryptoKit
import Darwin
import Foundation
import Security

/// One content-complete, read-only Git observation. Empty planes are retained
/// as explicit artifacts; absence of an artifact never means an empty plane.
struct WorkspaceJournaledGitPreimageCaptureReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var ratificationReceiptID: ReceiptID
    var enrollmentJournalFrameDigest: ContentDigest
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var baseSourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var captureActor: ActorIdentity
    var capturedAt: Date
    var headCommitObjectID: String
    var gitDirectoryIdentityDigest: ContentDigest
    var gitExecutableDigest: ContentDigest
    /// Exact policy identity for `git ls-files --others` with no excludes.
    /// This is not repository-metadata or ignored-path-policy authority.
    var untrackedObservationPolicyDigest: ContentDigest
    var head: WorkspacePreimagePlaneArtifact
    var index: WorkspacePreimagePlaneArtifact
    var untracked: WorkspacePreimagePlaneArtifact
    var repositoryObservationDigest: ContentDigest
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported Git preimage schema") }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || ratificationReceiptID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty
            || captureActor.id.rawValue.isEmpty
            || captureActor.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || captureActor.lineageDigest.rawValue.isEmpty {
            issues.append("Git preimage authority identity must not be empty")
        }
        for digest in [
            enrollmentJournalFrameDigest,
            canonicalRootDigest,
            baseSourceRevision,
            capturePolicyDigest,
            gitDirectoryIdentityDigest,
            gitExecutableDigest,
            untrackedObservationPolicyDigest,
            repositoryObservationDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("Git preimage authority digests must be SHA-256")
        }
        if !Self.validGitObjectID(headCommitObjectID) {
            issues.append("HEAD commit object identity is invalid")
        }
        let artifacts = [head, index, untracked]
        if artifacts.map(\.plane) != [.head, .index, .untracked] {
            issues.append("Git preimage artifacts must contain the three exact planes")
        }
        for artifact in artifacts {
            if !artifact.validationIssues().isEmpty
                || artifact.provenance != .journaledGitPreimageCapture
                || artifact.workspaceID != workspaceID
                || artifact.rootIdentity != canonicalRootDigest
                || artifact.sourceRevision != baseSourceRevision
                || artifact.capturePolicyDigest != capturePolicyDigest {
                issues.append("Git preimage artifact authority is inconsistent")
            }
        }
        if Self.repositoryDigest(
            headCommitObjectID: headCommitObjectID,
            gitDirectoryIdentityDigest: gitDirectoryIdentityDigest,
            gitExecutableDigest: gitExecutableDigest,
            untrackedObservationPolicyDigest: untrackedObservationPolicyDigest,
            head: head,
            index: index,
            untracked: untracked
        ) != repositoryObservationDigest {
            issues.append("Git repository observation digest mismatch")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("Git preimage receipt digest mismatch")
        }
        return issues
    }

    static func repositoryDigest(
        headCommitObjectID: String,
        gitDirectoryIdentityDigest: ContentDigest,
        gitExecutableDigest: ContentDigest,
        untrackedObservationPolicyDigest: ContentDigest,
        head: WorkspacePreimagePlaneArtifact,
        index: WorkspacePreimagePlaneArtifact,
        untracked: WorkspacePreimagePlaneArtifact
    ) -> ContentDigest? {
        canonicalDigest(RepositoryMaterial(
            headCommitObjectID: headCommitObjectID,
            gitDirectoryIdentityDigest: gitDirectoryIdentityDigest,
            gitExecutableDigest: gitExecutableDigest,
            untrackedObservationPolicyDigest: untrackedObservationPolicyDigest,
            headArtifactDigest: head.artifactDigest,
            indexArtifactDigest: index.artifactDigest,
            untrackedArtifactDigest: untracked.artifactDigest
        ))
    }

    static func digest(
        for receipt: WorkspaceJournaledGitPreimageCaptureReceipt
    ) -> ContentDigest? {
        canonicalDigest(DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            runID: receipt.runID,
            contractID: receipt.contractID,
            ratificationReceiptID: receipt.ratificationReceiptID,
            enrollmentJournalFrameDigest: receipt.enrollmentJournalFrameDigest,
            workspaceID: receipt.workspaceID,
            canonicalRootDigest: receipt.canonicalRootDigest,
            baseSourceRevision: receipt.baseSourceRevision,
            capturePolicyDigest: receipt.capturePolicyDigest,
            captureActor: receipt.captureActor,
            capturedAt: receipt.capturedAt,
            headCommitObjectID: receipt.headCommitObjectID,
            gitDirectoryIdentityDigest: receipt.gitDirectoryIdentityDigest,
            gitExecutableDigest: receipt.gitExecutableDigest,
            untrackedObservationPolicyDigest:
                receipt.untrackedObservationPolicyDigest,
            head: receipt.head,
            index: receipt.index,
            untracked: receipt.untracked,
            repositoryObservationDigest: receipt.repositoryObservationDigest
        ))
    }

    static func isSHA256(_ value: ContentDigest) -> Bool {
        value.rawValue.count == 64 && value.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func validGitObjectID(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func canonicalDigest<T: Encodable>(
        _ value: T
    ) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private struct RepositoryMaterial: Codable {
        var headCommitObjectID: String
        var gitDirectoryIdentityDigest: ContentDigest
        var gitExecutableDigest: ContentDigest
        var untrackedObservationPolicyDigest: ContentDigest
        var headArtifactDigest: ContentDigest
        var indexArtifactDigest: ContentDigest
        var untrackedArtifactDigest: ContentDigest
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var runID: KernelRunID
        var contractID: TaskContractID
        var ratificationReceiptID: ReceiptID
        var enrollmentJournalFrameDigest: ContentDigest
        var workspaceID: WorkspaceID
        var canonicalRootDigest: ContentDigest
        var baseSourceRevision: ContentDigest
        var capturePolicyDigest: ContentDigest
        var captureActor: ActorIdentity
        var capturedAt: Date
        var headCommitObjectID: String
        var gitDirectoryIdentityDigest: ContentDigest
        var gitExecutableDigest: ContentDigest
        var untrackedObservationPolicyDigest: ContentDigest
        var head: WorkspacePreimagePlaneArtifact
        var index: WorkspacePreimagePlaneArtifact
        var untracked: WorkspacePreimagePlaneArtifact
        var repositoryObservationDigest: ContentDigest
    }
}

/// Non-Codable proof that the issuer completed one live atomic observation.
/// Recovery retains the inert receipt, never this capability.
struct AuthorizedWorkspaceJournaledGitPreimageCapture: Sendable {
    let receipt: WorkspaceJournaledGitPreimageCaptureReceipt
    private let issuerNonce: Data

    fileprivate init(
        receipt: WorkspaceJournaledGitPreimageCaptureReceipt,
        issuerNonce: Data
    ) {
        self.receipt = receipt
        self.issuerNonce = issuerNonce
    }

    func validationIssues() -> [String] {
        var issues = receipt.validationIssues()
        if issuerNonce.count != 32 {
            issues.append("Git preimage capability nonce is invalid")
        }
        return issues
    }

#if DEBUG
    static func testOnly(
        receipt: WorkspaceJournaledGitPreimageCaptureReceipt
    ) -> AuthorizedWorkspaceJournaledGitPreimageCapture {
        AuthorizedWorkspaceJournaledGitPreimageCapture(
            receipt: receipt,
            issuerNonce: Data(repeating: 7, count: 32)
        )
    }
#endif
}

enum WorkspaceJournaledGitPreimageCaptureError:
    Error,
    Equatable,
    Sendable
{
    case invalidEnrollment
    case registrationMismatch
    case journalMismatch
    case baselineAuthorityMismatch
    case baselineChanged
    case notGitRepository
    case unbornHead
    case conflictedIndex
    case unsupportedGitEntry(String)
    case captureLimitExceeded
    case repositoryChanged
    case commandFailed(String)
    case encodingFailed
}

/// Captures HEAD, index, and untracked membership without writing the target
/// repository. Git listings and the ratified filesystem revision must repeat
/// exactly before a capability can be journaled.
actor WorkspaceJournaledGitPreimageCaptureIssuer {
    private let registry: WorkspaceMutationRecoveryRegistry
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    init(registry: WorkspaceMutationRecoveryRegistry) {
        self.registry = registry
    }

    func capture(
        enrollment: KernelRunEnrollmentReceipt
    ) async throws -> AuthorizedWorkspaceJournaledGitPreimageCapture {
        guard enrollment.schemaVersion == 1,
              enrollment.runID == enrollment.registration.runID,
              !enrollment.contractID.rawValue.isEmpty,
              !enrollment.ratificationReceiptID.rawValue.isEmpty else {
            throw WorkspaceJournaledGitPreimageCaptureError.invalidEnrollment
        }
        guard let registration = try await registry.registration(
            runID: enrollment.runID
        ), registration == enrollment.registration,
              registration.enrollmentEvidence?.authority == .ratifiedUserContract,
              registration.enrollmentEvidence?.contractID == enrollment.contractID,
              registration.enrollmentEvidence?.ratificationReceiptID ==
                enrollment.ratificationReceiptID,
              registration.enrollmentEvidence?.journalFrameDigest ==
                enrollment.journalTransaction.frameDigest else {
            throw WorkspaceJournaledGitPreimageCaptureError.registrationMismatch
        }
        let journal: RunJournal
        do {
            journal = try RunJournal(
                rootDirectory: registration.journalRoot,
                runID: registration.runID
            )
        } catch {
            throw WorkspaceJournaledGitPreimageCaptureError.journalMismatch
        }
        guard await journal.transactionReceipt(
            commandID: enrollment.journalTransaction.commandID
        ) == enrollment.journalTransaction,
              let contract = await journal.currentContract(),
              contract.id == enrollment.contractID,
              let baseline = contract.sourceRevision,
              let binding = contract.workspaceBinding,
              baseline.validationIssues().isEmpty,
              baseline.workspaceID == registration.workspaceID,
              baseline.canonicalRootDigest == binding.canonicalRootDigest else {
            throw WorkspaceJournaledGitPreimageCaptureError.journalMismatch
        }
        let root = registration.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        guard WorkspaceRepositoryIndexer.canonicalRootDigest(root) ==
                baseline.canonicalRootDigest else {
            throw WorkspaceJournaledGitPreimageCaptureError
                .baselineAuthorityMismatch
        }
        guard try recapture(root, baseline) == baseline else {
            throw WorkspaceJournaledGitPreimageCaptureError.baselineChanged
        }

        let gitDigest = try executableDigest()
        let first = try observe(root: root, baseline: baseline)
        guard try recapture(root, baseline) == baseline else {
            throw WorkspaceJournaledGitPreimageCaptureError.baselineChanged
        }
        let second = try observe(root: root, baseline: baseline)
        guard first == second else {
            throw WorkspaceJournaledGitPreimageCaptureError.repositoryChanged
        }
        guard try recapture(root, baseline) == baseline else {
            throw WorkspaceJournaledGitPreimageCaptureError.baselineChanged
        }
        guard try executableDigest() == gitDigest,
              try directoryIdentityDigest(first.gitDirectory) ==
                first.gitDirectoryIdentityDigest else {
            throw WorkspaceJournaledGitPreimageCaptureError.repositoryChanged
        }
        let policyDigest = Self.digest(Data(
            "git-ls-files-others-no-excludes-v1".utf8
        ))
        let gitDirectoryDigest = first.gitDirectoryIdentityDigest
        let head = try artifact(
            plane: .head,
            entries: first.head,
            baseline: baseline
        )
        let index = try artifact(
            plane: .index,
            entries: first.index,
            baseline: baseline
        )
        let untracked = try artifact(
            plane: .untracked,
            entries: first.untracked,
            baseline: baseline
        )
        guard let observation =
            WorkspaceJournaledGitPreimageCaptureReceipt.repositoryDigest(
                headCommitObjectID: first.headCommit,
                gitDirectoryIdentityDigest: gitDirectoryDigest,
                gitExecutableDigest: gitDigest,
                untrackedObservationPolicyDigest: policyDigest,
                head: head,
                index: index,
                untracked: untracked
            ) else {
            throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
        }
        var receipt = WorkspaceJournaledGitPreimageCaptureReceipt(
            schemaVersion: 1,
            runID: enrollment.runID,
            contractID: enrollment.contractID,
            ratificationReceiptID: enrollment.ratificationReceiptID,
            enrollmentJournalFrameDigest:
                enrollment.journalTransaction.frameDigest,
            workspaceID: baseline.workspaceID,
            canonicalRootDigest: baseline.canonicalRootDigest,
            baseSourceRevision: baseline.sourceRevision,
            capturePolicyDigest: baseline.capturePolicyDigest,
            captureActor: registration.actorIdentity,
            capturedAt: Date(),
            headCommitObjectID: first.headCommit,
            gitDirectoryIdentityDigest: gitDirectoryDigest,
            gitExecutableDigest: gitDigest,
            untrackedObservationPolicyDigest: policyDigest,
            head: head,
            index: index,
            untracked: untracked,
            repositoryObservationDigest: observation,
            receiptDigest: ContentDigest("")
        )
        guard let receiptDigest =
            WorkspaceJournaledGitPreimageCaptureReceipt.digest(for: receipt)
        else {
            throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
        }
        receipt.receiptDigest = receiptDigest
        guard receipt.validationIssues().isEmpty else {
            throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
        }
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
        }
        return AuthorizedWorkspaceJournaledGitPreimageCapture(
            receipt: receipt,
            issuerNonce: nonce
        )
    }

    private struct Observation: Equatable {
        var headCommit: String
        var gitDirectory: String
        var gitDirectoryIdentityDigest: ContentDigest
        var head: [WorkspaceEntrySnapshot]
        var index: [WorkspaceEntrySnapshot]
        var untracked: [WorkspaceEntrySnapshot]
    }

    private struct GitObjectEntry {
        var mode: UInt32
        var objectID: String
        var path: String
    }

    private func observe(
        root: URL,
        baseline: WorkspaceSourceRevisionArtifact
    ) throws -> Observation {
        let top = try text(root, ["rev-parse", "--show-toplevel"])
        guard URL(fileURLWithPath: top).standardizedFileURL
            .resolvingSymlinksInPath() == root else {
            throw WorkspaceJournaledGitPreimageCaptureError.notGitRepository
        }
        let gitDirectoryText = try text(
            root,
            ["rev-parse", "--path-format=absolute", "--git-dir"]
        )
        guard gitDirectoryText.hasPrefix("/") else {
            throw WorkspaceJournaledGitPreimageCaptureError.notGitRepository
        }
        let gitDirectoryURL = URL(fileURLWithPath: gitDirectoryText)
            .standardizedFileURL.resolvingSymlinksInPath()
        let gitDirectoryValues = try? gitDirectoryURL.resourceValues(
            forKeys: [.isDirectoryKey]
        )
        guard gitDirectoryValues?.isDirectory == true else {
            throw WorkspaceJournaledGitPreimageCaptureError.notGitRepository
        }
        let gitDirectory = gitDirectoryURL.path
        let gitDirectoryIdentityDigest = try directoryIdentityDigest(
            gitDirectory
        )
        let headCommit: String
        do {
            headCommit = try text(root, ["rev-parse", "--verify", "HEAD^{commit}"])
        } catch {
            throw WorkspaceJournaledGitPreimageCaptureError.unbornHead
        }
        let headRecords = try parseHead(try runGit(
            root,
            ["ls-tree", "-rz", "--full-tree", "HEAD"],
            maximumOutputBytes: baseline.limits.maximumTotalBytes * 2 + 1_048_576
        ))
        let indexRecords = try parseIndex(try runGit(
            root,
            ["ls-files", "--stage", "-z"],
            maximumOutputBytes: baseline.limits.maximumTotalBytes * 2 + 1_048_576
        ))
        let untrackedPaths = try parsePaths(try runGit(
            root,
            ["ls-files", "--others", "-z"],
            maximumOutputBytes: baseline.limits.maximumTotalBytes + 1_048_576
        ))
        let excluded = Set(baseline.excludedDirectoryNames)
        let filteredHead = headRecords.filter { !isExcluded($0.path, excluded) }
        let filteredIndex = indexRecords.filter { !isExcluded($0.path, excluded) }
        let filteredUntracked = untrackedPaths.filter { !isExcluded($0, excluded) }
        guard Set(filteredHead.map(\.path)).count == filteredHead.count,
              Set(filteredIndex.map(\.path)).count == filteredIndex.count else {
            throw WorkspaceJournaledGitPreimageCaptureError
                .unsupportedGitEntry("duplicate-path")
        }
        var cache: [String: Data] = [:]
        let head = try gitEntries(
            filteredHead,
            plane: .head,
            root: root,
            limits: baseline.limits,
            cache: &cache
        )
        let index = try gitEntries(
            filteredIndex,
            plane: .index,
            root: root,
            limits: baseline.limits,
            cache: &cache
        )
        let baselineByPath = Dictionary(
            uniqueKeysWithValues: baseline.entries.map { ($0.relativePath, $0) }
        )
        let untracked = try filteredUntracked.map { path -> WorkspaceEntrySnapshot in
            guard let entry = baselineByPath[path] else {
                throw WorkspaceJournaledGitPreimageCaptureError.baselineChanged
            }
            return WorkspaceEntrySnapshot(
                plane: .untracked,
                path: path,
                kind: .regularFile,
                mode: entry.mode,
                contentDigest: entry.contentDigest,
                size: entry.size,
                ownership: .userExisting
            )
        }
        try enforceLimits(untracked, baseline.limits)
        return Observation(
            headCommit: headCommit,
            gitDirectory: gitDirectory,
            gitDirectoryIdentityDigest: gitDirectoryIdentityDigest,
            head: head,
            index: index,
            untracked: untracked
        )
    }

    private func gitEntries(
        _ records: [GitObjectEntry],
        plane: WorkspaceEntryPlane,
        root: URL,
        limits: WorkspaceSourceRevisionLimits,
        cache: inout [String: Data]
    ) throws -> [WorkspaceEntrySnapshot] {
        var entries: [WorkspaceEntrySnapshot] = []
        for record in records {
            let data: Data
            if let retained = cache[record.objectID] {
                data = retained
            } else {
                guard let objectSize = UInt64(try text(
                    root,
                    ["cat-file", "-s", record.objectID]
                )), objectSize <= limits.maximumFileBytes else {
                    throw WorkspaceJournaledGitPreimageCaptureError
                        .captureLimitExceeded
                }
                data = try runGit(
                    root,
                    ["cat-file", "blob", record.objectID],
                    maximumOutputBytes: objectSize
                )
                guard UInt64(data.count) == objectSize else {
                    throw WorkspaceJournaledGitPreimageCaptureError
                        .repositoryChanged
                }
                cache[record.objectID] = data
            }
            entries.append(WorkspaceEntrySnapshot(
                plane: plane,
                path: record.path,
                kind: .regularFile,
                mode: record.mode,
                contentDigest: Self.digest(data),
                size: UInt64(data.count),
                ownership: .userExisting
            ))
        }
        entries.sort { $0.path < $1.path }
        try enforceLimits(entries, limits)
        return entries
    }

    private func enforceLimits(
        _ entries: [WorkspaceEntrySnapshot],
        _ limits: WorkspaceSourceRevisionLimits
    ) throws {
        guard entries.count <= limits.maximumFiles,
              entries.allSatisfy({ $0.size <= limits.maximumFileBytes }) else {
            throw WorkspaceJournaledGitPreimageCaptureError.captureLimitExceeded
        }
        var total: UInt64 = 0
        for entry in entries {
            let (next, overflow) = total.addingReportingOverflow(entry.size)
            guard !overflow, next <= limits.maximumTotalBytes else {
                throw WorkspaceJournaledGitPreimageCaptureError.captureLimitExceeded
            }
            total = next
        }
    }

    private func parseHead(_ data: Data) throws -> [GitObjectEntry] {
        try nulRecords(data).map { record in
            guard let tab = record.firstIndex(of: 0x09),
                  let header = String(data: record[..<tab], encoding: .utf8),
                  let path = String(data: record[record.index(after: tab)...], encoding: .utf8)
            else { throw WorkspaceJournaledGitPreimageCaptureError.commandFailed("parse-head") }
            let fields = header.split(separator: " ").map(String.init)
            guard fields.count == 3, fields[1] == "blob",
                  let mode = gitMode(fields[0]), validPath(path),
                  validObjectID(fields[2]) else {
                throw WorkspaceJournaledGitPreimageCaptureError.unsupportedGitEntry(path)
            }
            return GitObjectEntry(mode: mode, objectID: fields[2], path: path)
        }.sorted { $0.path < $1.path }
    }

    private func parseIndex(_ data: Data) throws -> [GitObjectEntry] {
        try nulRecords(data).map { record in
            guard let tab = record.firstIndex(of: 0x09),
                  let header = String(data: record[..<tab], encoding: .utf8),
                  let path = String(data: record[record.index(after: tab)...], encoding: .utf8)
            else { throw WorkspaceJournaledGitPreimageCaptureError.commandFailed("parse-index") }
            let fields = header.split(separator: " ").map(String.init)
            guard fields.count == 3 else {
                throw WorkspaceJournaledGitPreimageCaptureError.commandFailed("parse-index")
            }
            guard fields[2] == "0" else {
                throw WorkspaceJournaledGitPreimageCaptureError.conflictedIndex
            }
            guard let mode = gitMode(fields[0]), validPath(path),
                  validObjectID(fields[1]) else {
                throw WorkspaceJournaledGitPreimageCaptureError.unsupportedGitEntry(path)
            }
            return GitObjectEntry(mode: mode, objectID: fields[1], path: path)
        }.sorted { $0.path < $1.path }
    }

    private func parsePaths(_ data: Data) throws -> [String] {
        let paths = try nulRecords(data).map { record -> String in
            guard let path = String(data: record, encoding: .utf8), validPath(path) else {
                throw WorkspaceJournaledGitPreimageCaptureError
                    .unsupportedGitEntry("non-canonical-path")
            }
            return path
        }.sorted()
        guard Set(paths).count == paths.count else {
            throw WorkspaceJournaledGitPreimageCaptureError
                .unsupportedGitEntry("duplicate-path")
        }
        return paths
    }

    private func nulRecords(_ data: Data) throws -> [Data] {
        if data.isEmpty { return [] }
        guard data.last == 0 else {
            throw WorkspaceJournaledGitPreimageCaptureError.commandFailed("missing-nul")
        }
        var records: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            guard let end = data[start...].firstIndex(of: UInt8(0)) else {
                throw WorkspaceJournaledGitPreimageCaptureError
                    .commandFailed("missing-nul")
            }
            if start < end { records.append(Data(data[start..<end])) }
            start = data.index(after: end)
        }
        return records
    }

    private func gitMode(_ value: String) -> UInt32? {
        switch value {
        case "100644": return 0o644
        case "100755": return 0o755
        default: return nil
        }
    }

    private func validObjectID(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private func validPath(_ path: String) -> Bool {
        WorkspaceSourceRevisionCollector.validRelativePath(path)
            && !path.unicodeScalars.contains(where: { $0.value == 0 })
    }

    private func isExcluded(_ path: String, _ excluded: Set<String>) -> Bool {
        path.split(separator: "/").contains { excluded.contains(String($0)) }
    }

    private func artifact(
        plane: WorkspaceEntryPlane,
        entries: [WorkspaceEntrySnapshot],
        baseline: WorkspaceSourceRevisionArtifact
    ) throws -> WorkspacePreimagePlaneArtifact {
        var sizes: [ContentDigest: UInt64] = [:]
        for entry in entries {
            if let prior = sizes[entry.contentDigest], prior != entry.size {
                throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
            }
            sizes[entry.contentDigest] = entry.size
        }
        let objects = sizes.map {
            WorkspaceMutationContentReference(contentDigest: $0.key, size: $0.value)
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        var value = WorkspacePreimagePlaneArtifact(
            schemaVersion: 1,
            provenance: .journaledGitPreimageCapture,
            plane: plane,
            workspaceID: baseline.workspaceID,
            rootIdentity: baseline.canonicalRootDigest,
            sourceRevision: baseline.sourceRevision,
            capturePolicyDigest: baseline.capturePolicyDigest,
            entries: entries,
            contentObjects: objects,
            artifactDigest: ContentDigest("")
        )
        guard let digest = WorkspacePreimagePlaneArtifact.digest(for: value) else {
            throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
        }
        value.artifactDigest = digest
        guard value.validationIssues().isEmpty else {
            throw WorkspaceJournaledGitPreimageCaptureError.encodingFailed
        }
        return value
    }

    private func recapture(
        _ root: URL,
        _ expected: WorkspaceSourceRevisionArtifact
    ) throws -> WorkspaceSourceRevisionArtifact {
        do {
            return try WorkspaceSourceRevisionCollector().capture(
                workspaceID: expected.workspaceID,
                root: root,
                excludedDirectoryNames: Set(expected.excludedDirectoryNames),
                limits: expected.limits
            )
        } catch {
            throw WorkspaceJournaledGitPreimageCaptureError.baselineChanged
        }
    }

    private func directoryIdentityDigest(_ path: String) throws -> ContentDigest {
        var status = stat()
        guard lstat(path, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceJournaledGitPreimageCaptureError.notGitRepository
        }
        return Self.digest(Data(
            "\(path)\u{0}\(status.st_dev)\u{0}\(status.st_ino)".utf8
        ))
    }

    private func executableDigest() throws -> ContentDigest {
        let data: Data
        do {
            data = try Data(contentsOf: gitURL, options: [.mappedIfSafe])
        } catch {
            throw WorkspaceJournaledGitPreimageCaptureError
                .commandFailed("git-executable")
        }
        return Self.digest(data)
    }

    private func text(_ root: URL, _ arguments: [String]) throws -> String {
        let data = try runGit(root, arguments, maximumOutputBytes: 64 * 1_024)
        guard let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw WorkspaceJournaledGitPreimageCaptureError.commandFailed(
                arguments.first ?? "git"
            )
        }
        return value
    }

    private func runGit(
        _ root: URL,
        _ arguments: [String],
        maximumOutputBytes: UInt64
    ) throws -> Data {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LoopForgeGitObservation-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = temporary.appendingPathComponent("stdout")
        let error = temporary.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              FileManager.default.createFile(atPath: error.path, contents: nil)
        else {
            throw WorkspaceJournaledGitPreimageCaptureError.commandFailed("temporary-output")
        }
        let outputHandle = try FileHandle(forWritingTo: output)
        let errorHandle = try FileHandle(forWritingTo: error)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }
        let process = Process()
        process.executableURL = gitURL
        process.arguments = ["-C", root.path] + arguments
        process.environment = [
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_OPTIONAL_LOCKS": "0",
            "LANG": "C",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin"
        ]
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            throw WorkspaceJournaledGitPreimageCaptureError.commandFailed(
                arguments.first ?? "git"
            )
        }
        if finished.wait(timeout: .now() + 15) == .timedOut {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 2)
            throw WorkspaceJournaledGitPreimageCaptureError.commandFailed(
                "timeout:\(arguments.first ?? "git")"
            )
        }
        try outputHandle.synchronize()
        try errorHandle.synchronize()
        guard process.terminationReason == .exit,
              process.terminationStatus == 0 else {
            throw WorkspaceJournaledGitPreimageCaptureError.commandFailed(
                arguments.first ?? "git"
            )
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        guard let size = attributes[.size] as? NSNumber,
              size.uint64Value <= maximumOutputBytes else {
            throw WorkspaceJournaledGitPreimageCaptureError.captureLimitExceeded
        }
        return try Data(contentsOf: output, options: [.mappedIfSafe])
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}
