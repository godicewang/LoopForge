import CryptoKit
import Darwin
import Foundation

struct WorkspaceSourceRevisionLimits: Codable, Hashable, Sendable {
    var maximumFiles: Int
    var maximumTotalBytes: UInt64
    var maximumFileBytes: UInt64

    func validationIssues() -> [String] {
        var issues: [String] = []
        if maximumFiles <= 0 { issues.append("maximumFiles must be positive") }
        if maximumTotalBytes == 0 {
            issues.append("maximumTotalBytes must be positive")
        }
        if maximumFileBytes == 0 {
            issues.append("maximumFileBytes must be positive")
        }
        if maximumFileBytes > maximumTotalBytes {
            issues.append("maximumFileBytes must not exceed maximumTotalBytes")
        }
        return issues
    }
}

/// Exact, contract-bindable policy for a content-complete workspace capture.
///
/// Callers may transport this value to the mutation executor, but they cannot
/// change its exclusions or limits after the apply intent has journaled the
/// matching digest.
struct WorkspaceCandidatePostimageCapturePolicy: Codable, Hashable, Sendable {
    var excludedDirectoryNames: [String]
    var limits: WorkspaceSourceRevisionLimits

    var capturePolicyDigest: ContentDigest? {
        WorkspaceSourceRevisionArtifact.policyDigest(
            excludedDirectoryNames: excludedDirectoryNames,
            limits: limits
        )
    }

    func validationIssues() -> [String] {
        var issues = limits.validationIssues()
        if excludedDirectoryNames != excludedDirectoryNames.sorted()
            || Set(excludedDirectoryNames).count != excludedDirectoryNames.count
            || excludedDirectoryNames.contains(where: {
                !WorkspaceSourceRevisionCollector.validPathComponent($0)
            }) {
            issues.append(
                "excluded directory names must be unique canonical components"
            )
        }
        if capturePolicyDigest == nil {
            issues.append("capture policy digest could not be encoded")
        }
        return issues
    }

    init(
        excludedDirectoryNames: [String],
        limits: WorkspaceSourceRevisionLimits
    ) {
        self.excludedDirectoryNames = excludedDirectoryNames
        self.limits = limits
    }

    init(sourceRevision: WorkspaceSourceRevisionArtifact) {
        excludedDirectoryNames = sourceRevision.excludedDirectoryNames
        limits = sourceRevision.limits
    }
}

struct WorkspaceSourceRevisionEntry: Codable, Hashable, Sendable {
    var relativePath: String
    var mode: UInt32
    var size: UInt64
    var contentDigest: ContentDigest
}

/// Content-complete within one explicit capture policy. Timestamps, inode
/// numbers, enumeration order, and Git metadata do not define the revision.
/// This value is evidence only; user confirmation must bind it before it can
/// participate in strategy or plan authority.
struct WorkspaceSourceRevisionArtifact: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var excludedDirectoryNames: [String]
    var limits: WorkspaceSourceRevisionLimits
    var capturePolicyDigest: ContentDigest
    var entries: [WorkspaceSourceRevisionEntry]
    var totalBytes: UInt64
    var sourceRevision: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported source-revision schema") }
        if workspaceID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("workspace identity must not be empty")
        }
        if !Self.validDigest(canonicalRootDigest) {
            issues.append("canonical root digest must be SHA-256")
        }
        if excludedDirectoryNames != excludedDirectoryNames.sorted()
            || Set(excludedDirectoryNames).count != excludedDirectoryNames.count
            || excludedDirectoryNames.contains(where: {
                !WorkspaceSourceRevisionCollector.validPathComponent($0)
            }) {
            issues.append("excluded directory names must be unique canonical components")
        }
        issues.append(contentsOf: limits.validationIssues())
        if entries != entries.sorted(by: { $0.relativePath < $1.relativePath })
            || Set(entries.map(\.relativePath)).count != entries.count {
            issues.append("source-revision entries must be uniquely path-sorted")
        }
        if entries.count > limits.maximumFiles {
            issues.append("source-revision entry count exceeds its capture limit")
        }
        var observedTotal: UInt64 = 0
        for entry in entries {
            if !WorkspaceSourceRevisionCollector.validRelativePath(
                entry.relativePath
            ) {
                issues.append("source-revision entry path is invalid")
            }
            if entry.mode > 0o7777 {
                issues.append("source-revision entry mode is invalid")
            }
            if entry.size > limits.maximumFileBytes {
                issues.append("source-revision entry exceeds its file limit")
            }
            if !Self.validDigest(entry.contentDigest) {
                issues.append("source-revision entry digest must be SHA-256")
            }
            let (next, overflow) = observedTotal.addingReportingOverflow(entry.size)
            if overflow {
                issues.append("source-revision total byte count overflowed")
                observedTotal = .max
            } else {
                observedTotal = next
            }
        }
        if observedTotal != totalBytes || totalBytes > limits.maximumTotalBytes {
            issues.append("source-revision total bytes are inconsistent")
        }
        if Self.policyDigest(
            excludedDirectoryNames: excludedDirectoryNames,
            limits: limits
        ) != capturePolicyDigest {
            issues.append("source-revision capture policy digest mismatch")
        }
        if Self.revisionDigest(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            canonicalRootDigest: canonicalRootDigest,
            excludedDirectoryNames: excludedDirectoryNames,
            limits: limits,
            capturePolicyDigest: capturePolicyDigest,
            entries: entries,
            totalBytes: totalBytes
        ) != sourceRevision {
            issues.append("source-revision digest mismatch")
        }
        return issues
    }

    static func policyDigest(
        excludedDirectoryNames: [String],
        limits: WorkspaceSourceRevisionLimits
    ) -> ContentDigest? {
        guard let data = try? canonicalData(PolicyMaterial(
            excludedDirectoryNames: excludedDirectoryNames,
            limits: limits
        )) else { return nil }
        return digest(data)
    }

    static func revisionDigest(
        schemaVersion: Int,
        workspaceID: WorkspaceID,
        canonicalRootDigest: ContentDigest,
        excludedDirectoryNames: [String],
        limits: WorkspaceSourceRevisionLimits,
        capturePolicyDigest: ContentDigest,
        entries: [WorkspaceSourceRevisionEntry],
        totalBytes: UInt64
    ) -> ContentDigest? {
        guard let data = try? canonicalData(RevisionMaterial(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            canonicalRootDigest: canonicalRootDigest,
            excludedDirectoryNames: excludedDirectoryNames,
            limits: limits,
            capturePolicyDigest: capturePolicyDigest,
            entries: entries,
            totalBytes: totalBytes
        )) else { return nil }
        return digest(data)
    }

    private static func validDigest(_ value: ContentDigest) -> Bool {
        value.rawValue.count == 64 && value.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private struct PolicyMaterial: Codable {
        var excludedDirectoryNames: [String]
        var limits: WorkspaceSourceRevisionLimits
    }

    private struct RevisionMaterial: Codable {
        var schemaVersion: Int
        var workspaceID: WorkspaceID
        var canonicalRootDigest: ContentDigest
        var excludedDirectoryNames: [String]
        var limits: WorkspaceSourceRevisionLimits
        var capturePolicyDigest: ContentDigest
        var entries: [WorkspaceSourceRevisionEntry]
        var totalBytes: UInt64
    }
}

enum WorkspaceSourceRevisionError: Error, Equatable {
    case invalidWorkspace
    case invalidLimits([String])
    case invalidExcludedDirectoryName(String)
    case enumerationFailed(String)
    case escapedWorkspace(String)
    case symbolicLink(String)
    case unsupportedEntry(String)
    case fileLimitExceeded(actual: Int, maximum: Int)
    case fileByteLimitExceeded(path: String, actual: UInt64, maximum: UInt64)
    case totalByteLimitExceeded(actual: UInt64, maximum: UInt64)
    case fileChangedDuringCapture(String)
    case systemCallFailed(String)
    case encodingFailed
}

struct WorkspaceSourceRevisionCollector: Sendable {
    func capture(
        workspaceID: WorkspaceID,
        root: URL,
        excludedDirectoryNames: Set<String>,
        limits: WorkspaceSourceRevisionLimits
    ) throws -> WorkspaceSourceRevisionArtifact {
        guard !workspaceID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw WorkspaceSourceRevisionError.invalidWorkspace
        }
        let limitIssues = limits.validationIssues()
        guard limitIssues.isEmpty else {
            throw WorkspaceSourceRevisionError.invalidLimits(limitIssues)
        }
        for name in excludedDirectoryNames where !Self.validPathComponent(name) {
            throw WorkspaceSourceRevisionError.invalidExcludedDirectoryName(name)
        }

        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? canonicalRoot.resourceValues(forKeys: [.isDirectoryKey])
        guard canonicalRoot.isFileURL,
              canonicalRoot.path.hasPrefix("/"),
              values?.isDirectory == true else {
            throw WorkspaceSourceRevisionError.invalidWorkspace
        }
        let rootDescriptor = Darwin.open(
            canonicalRoot.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw WorkspaceSourceRevisionError.systemCallFailed("open(workspace-root)")
        }
        defer { Darwin.close(rootDescriptor) }

        let discovered = try discoverFiles(
            root: canonicalRoot,
            excludedDirectoryNames: excludedDirectoryNames,
            maximumFiles: limits.maximumFiles
        )
        var entries: [WorkspaceSourceRevisionEntry] = []
        entries.reserveCapacity(discovered.count)
        var totalBytes: UInt64 = 0
        for relativePath in discovered {
            let entry = try Self.hashEntry(
                relativePath: relativePath,
                rootDescriptor: rootDescriptor,
                maximumBytes: limits.maximumFileBytes
            )
            let (nextTotal, overflow) = totalBytes.addingReportingOverflow(entry.size)
            guard !overflow, nextTotal <= limits.maximumTotalBytes else {
                throw WorkspaceSourceRevisionError.totalByteLimitExceeded(
                    actual: overflow ? UInt64.max : nextTotal,
                    maximum: limits.maximumTotalBytes
                )
            }
            totalBytes = nextTotal
            entries.append(entry)
        }

        let rootDigest = WorkspaceRepositoryIndexer.canonicalRootDigest(canonicalRoot)
        let excludedNames = excludedDirectoryNames.sorted()
        guard let policyDigest = WorkspaceSourceRevisionArtifact.policyDigest(
            excludedDirectoryNames: excludedNames,
            limits: limits
        ), let sourceRevision = WorkspaceSourceRevisionArtifact.revisionDigest(
            schemaVersion: 1,
            workspaceID: workspaceID,
            canonicalRootDigest: rootDigest,
            excludedDirectoryNames: excludedNames,
            limits: limits,
            capturePolicyDigest: policyDigest,
            entries: entries,
            totalBytes: totalBytes
        ) else {
            throw WorkspaceSourceRevisionError.encodingFailed
        }
        let artifact = WorkspaceSourceRevisionArtifact(
            schemaVersion: 1,
            workspaceID: workspaceID,
            canonicalRootDigest: rootDigest,
            excludedDirectoryNames: excludedNames,
            limits: limits,
            capturePolicyDigest: policyDigest,
            entries: entries,
            totalBytes: totalBytes,
            sourceRevision: sourceRevision
        )
        guard artifact.validationIssues().isEmpty else {
            throw WorkspaceSourceRevisionError.encodingFailed
        }
        return artifact
    }

    private func discoverFiles(
        root: URL,
        excludedDirectoryNames: Set<String>,
        maximumFiles: Int
    ) throws -> [String] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        var enumerationFailure: String?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, _ in
                enumerationFailure = url.path
                return false
            }
        ) else {
            throw WorkspaceSourceRevisionError.enumerationFailed(root.path)
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: keys)
            } catch {
                throw WorkspaceSourceRevisionError.enumerationFailed(url.path)
            }
            let standardized = url.standardizedFileURL.path
            guard standardized.hasPrefix(prefix) else {
                throw WorkspaceSourceRevisionError.escapedWorkspace(standardized)
            }
            let relativePath = String(standardized.dropFirst(prefix.count))
            guard Self.validRelativePath(relativePath) else {
                throw WorkspaceSourceRevisionError.escapedWorkspace(relativePath)
            }
            if values.isSymbolicLink == true {
                throw WorkspaceSourceRevisionError.symbolicLink(relativePath)
            }
            if values.isDirectory == true,
               excludedDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else {
                throw WorkspaceSourceRevisionError.unsupportedEntry(relativePath)
            }
            paths.append(relativePath)
            if paths.count > maximumFiles {
                throw WorkspaceSourceRevisionError.fileLimitExceeded(
                    actual: paths.count,
                    maximum: maximumFiles
                )
            }
        }
        if let enumerationFailure {
            throw WorkspaceSourceRevisionError.enumerationFailed(enumerationFailure)
        }
        return paths.sorted()
    }

    static func hashEntry(
        relativePath: String,
        rootDescriptor: Int32,
        maximumBytes: UInt64
    ) throws -> WorkspaceSourceRevisionEntry {
        let descriptor = try Self.openRegularFile(
            relativePath,
            rootDescriptor: rootDescriptor
        )
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0 else {
            throw WorkspaceSourceRevisionError.systemCallFailed(
                "fstat(\(relativePath))"
            )
        }
        let expectedSize = UInt64(before.st_size)
        guard expectedSize <= maximumBytes else {
            throw WorkspaceSourceRevisionError.fileByteLimitExceeded(
                path: relativePath,
                actual: expectedSize,
                maximum: maximumBytes
            )
        }
        var hasher = SHA256()
        var observedSize: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR { continue }
                throw WorkspaceSourceRevisionError.systemCallFailed(
                    "read(\(relativePath))"
                )
            }
            if count == 0 { break }
            let (next, overflow) = observedSize.addingReportingOverflow(UInt64(count))
            guard !overflow, next <= maximumBytes else {
                throw WorkspaceSourceRevisionError.fileByteLimitExceeded(
                    path: relativePath,
                    actual: overflow ? UInt64.max : next,
                    maximum: maximumBytes
                )
            }
            observedSize = next
            hasher.update(data: Data(buffer.prefix(count)))
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0 else {
            throw WorkspaceSourceRevisionError.systemCallFailed(
                "fstat-after(\(relativePath))"
            )
        }
        guard observedSize == expectedSize,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw WorkspaceSourceRevisionError.fileChangedDuringCapture(relativePath)
        }
        let digest = ContentDigest(hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined())
        return WorkspaceSourceRevisionEntry(
            relativePath: relativePath,
            mode: UInt32(before.st_mode & 0o7777),
            size: observedSize,
            contentDigest: digest
        )
    }

    static func openRegularFile(
        _ relativePath: String,
        rootDescriptor: Int32
    ) throws -> Int32 {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(validPathComponent) else {
            throw WorkspaceSourceRevisionError.escapedWorkspace(relativePath)
        }
        var directory = Darwin.dup(rootDescriptor)
        guard directory >= 0 else {
            throw WorkspaceSourceRevisionError.systemCallFailed("dup(workspace-root)")
        }
        for component in components.dropLast() {
            let next = component.withCString {
                Darwin.openat(
                    directory,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            Darwin.close(directory)
            guard next >= 0 else {
                throw WorkspaceSourceRevisionError.symbolicLink(relativePath)
            }
            directory = next
        }
        let descriptor = components.last!.withCString {
            Darwin.openat(
                directory,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        Darwin.close(directory)
        guard descriptor >= 0 else {
            throw WorkspaceSourceRevisionError.symbolicLink(relativePath)
        }
        return descriptor
    }

    static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { validPathComponent(String($0)) }
    }

    static func validPathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
    }

}
