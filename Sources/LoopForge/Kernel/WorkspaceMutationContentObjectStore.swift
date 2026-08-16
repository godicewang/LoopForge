import CryptoKit
import Darwin
import Foundation

enum WorkspaceMutationContentObjectStoreMaterialization:
    String,
    Codable,
    Hashable,
    Sendable
{
    case streamWrite
    case existingArtifact
}

struct WorkspaceMutationContentObjectStoreReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var verificationReceiptDigest: ContentDigest
    var derivationDigest: ContentDigest
    var objectSetDigest: ContentDigest
    var artifactManifestDigest: ContentDigest
    var artifactPath: String
    var objectCount: Int
    var totalBytes: UInt64
    var deviceID: UInt64
    var inode: UInt64
    var materialization: WorkspaceMutationContentObjectStoreMaterialization
    var reusedExistingArtifact: Bool
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported content-object-store schema") }
        for digest in [
            verificationReceiptDigest,
            derivationDigest,
            objectSetDigest,
            artifactManifestDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("content-object-store authority digests must be SHA-256")
        }
        if artifactPath.isEmpty || !artifactPath.hasPrefix("/") {
            issues.append("content-object-store path must be absolute")
        }
        if objectCount <= 0 { issues.append("content-object-store must not be empty") }
        if Self.digest(for: self) != receiptDigest {
            issues.append("content-object-store receipt digest mismatch")
        }
        return issues
    }

    fileprivate static func digest(
        for receipt: WorkspaceMutationContentObjectStoreReceipt
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            verificationReceiptDigest: receipt.verificationReceiptDigest,
            derivationDigest: receipt.derivationDigest,
            objectSetDigest: receipt.objectSetDigest,
            artifactManifestDigest: receipt.artifactManifestDigest,
            artifactPath: receipt.artifactPath,
            objectCount: receipt.objectCount,
            totalBytes: receipt.totalBytes,
            deviceID: receipt.deviceID,
            inode: receipt.inode,
            materialization: receipt.materialization,
            reusedExistingArtifact: receipt.reusedExistingArtifact
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else { return nil }
        return Self.sha256(data)
    }

    fileprivate static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    fileprivate static func sha256(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var verificationReceiptDigest: ContentDigest
        var derivationDigest: ContentDigest
        var objectSetDigest: ContentDigest
        var artifactManifestDigest: ContentDigest
        var artifactPath: String
        var objectCount: Int
        var totalBytes: UInt64
        var deviceID: UInt64
        var inode: UInt64
        var materialization: WorkspaceMutationContentObjectStoreMaterialization
        var reusedExistingArtifact: Bool
    }
}

enum WorkspaceMutationContentObjectStoreError: Error, Equatable, Sendable {
    case invalidVerificationReceipt
    case invalidWorkspaceRoot
    case invalidStorageRoot
    case storageOverlapsWorkspace
    case unsafeStoreDirectory
    case inputObjectSetMismatch
    case unsafeExistingArtifact
    case existingArtifactMismatch
    case systemCallFailed(operation: String, errno: Int32)
    case encodingFailed
}

/// Atomically installs an already verified exact byte set into an owner-private
/// read-only content-addressed directory outside the workspace. The returned
/// receipt remains inert because its upstream verification has no journal
/// provenance and this type exposes no mutation-authority capability.
struct WorkspaceMutationContentObjectStore: Sendable {
    static let directoryName = "mutation-content-objects"
    private static let lockName = ".content-object-store.lock"

    func materialize(
        verification: WorkspaceMutationContentObjectSetReceipt,
        objects: [WorkspaceMutationContentObject],
        workspaceRoot: URL,
        storageRoot: URL
    ) throws -> WorkspaceMutationContentObjectStoreReceipt {
        guard verification.validationIssues().isEmpty else {
            throw WorkspaceMutationContentObjectStoreError.invalidVerificationReceipt
        }
        try validateInputObjects(objects, verification: verification)

        guard let workspace = canonicalExistingDirectory(workspaceRoot) else {
            throw WorkspaceMutationContentObjectStoreError.invalidWorkspaceRoot
        }
        guard let storage = canonicalExistingDirectory(storageRoot) else {
            throw WorkspaceMutationContentObjectStoreError.invalidStorageRoot
        }
        guard storage.path != workspace.path,
              !storage.path.hasPrefix(workspace.path + "/"),
              !workspace.path.hasPrefix(storage.path + "/") else {
            throw WorkspaceMutationContentObjectStoreError.storageOverlapsWorkspace
        }

        let storageDescriptor = try openAbsoluteDirectory(
            storage,
            error: .invalidStorageRoot
        )
        defer { _ = Darwin.close(storageDescriptor) }
        try validatePrivateDirectory(
            descriptor: storageDescriptor,
            error: .invalidStorageRoot,
            writable: true
        )

        if mkdirat(storageDescriptor, Self.directoryName, 0o700) != 0,
           errno != EEXIST {
            throw Self.systemCallFailure("mkdirat(content-object-store)")
        }
        let storeDescriptor = Darwin.openat(
            storageDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard storeDescriptor >= 0 else {
            throw WorkspaceMutationContentObjectStoreError.unsafeStoreDirectory
        }
        defer { _ = Darwin.close(storeDescriptor) }
        try validatePrivateDirectory(
            descriptor: storeDescriptor,
            error: .unsafeStoreDirectory,
            writable: true
        )

        let lockDescriptor = Darwin.openat(
            storeDescriptor,
            Self.lockName,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard lockDescriptor >= 0 else {
            throw Self.systemCallFailure("openat(content-object-store-lock)")
        }
        defer { _ = Darwin.close(lockDescriptor) }
        var lockStatus = stat()
        guard fstat(lockDescriptor, &lockStatus) == 0,
              lockStatus.st_mode & S_IFMT == S_IFREG,
              lockStatus.st_uid == geteuid(),
              lockStatus.st_nlink == 1,
              lockStatus.st_mode & 0o777 == 0o600 else {
            throw WorkspaceMutationContentObjectStoreError.unsafeStoreDirectory
        }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw Self.systemCallFailure("flock(content-object-store-lock)")
        }
        defer { _ = flock(lockDescriptor, LOCK_UN) }

        let artifactName = verification.receiptDigest.rawValue
        let storeRoot = storage.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
        let artifactPath = storeRoot.appendingPathComponent(
            artifactName,
            isDirectory: true
        )
        if try directoryExists(named: artifactName, parent: storeDescriptor) {
            return try validateInstalledArtifact(
                path: artifactPath,
                verification: verification,
                materialization: .existingArtifact,
                reused: true,
                parentDescriptor: storeDescriptor,
                artifactName: artifactName
            )
        }

        let temporaryName = ".\(artifactName).\(UUID().uuidString).tmp"
        guard mkdirat(storeDescriptor, temporaryName, 0o700) == 0 else {
            throw Self.systemCallFailure("mkdirat(content-object-temporary)")
        }
        var installed = false
        let temporaryDescriptor = Darwin.openat(
            storeDescriptor,
            temporaryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard temporaryDescriptor >= 0 else {
            let failure = Self.systemCallFailure(
                "openat(content-object-temporary)"
            )
            temporaryName.withCString {
                _ = unlinkat(storeDescriptor, $0, AT_REMOVEDIR)
            }
            throw failure
        }
        defer { _ = Darwin.close(temporaryDescriptor) }
        defer {
            if !installed {
                cleanupTemporaryArtifact(
                    named: temporaryName,
                    objects: objects,
                    directory: temporaryDescriptor,
                    store: storeDescriptor
                )
            }
        }

        for object in objects.sorted(by: {
            $0.digest.rawValue < $1.digest.rawValue
        }) {
            try write(object: object, directory: temporaryDescriptor)
        }
        guard fchmod(temporaryDescriptor, mode_t(0o500)) == 0,
              fsync(temporaryDescriptor) == 0 else {
            throw Self.systemCallFailure("seal(content-object-artifact)")
        }
        guard renameatx_np(
            storeDescriptor,
            temporaryName,
            storeDescriptor,
            artifactName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw Self.systemCallFailure("renameatx_np(content-object-artifact)")
        }
        installed = true
        guard fsync(storeDescriptor) == 0 else {
            throw Self.systemCallFailure("fsync(content-object-store)")
        }
        return try validateInstalledArtifact(
            path: artifactPath,
            verification: verification,
            materialization: .streamWrite,
            reused: false,
            parentDescriptor: storeDescriptor,
            artifactName: artifactName
        )
    }

    func revalidate(
        _ receipt: WorkspaceMutationContentObjectStoreReceipt,
        verification: WorkspaceMutationContentObjectSetReceipt
    ) throws -> WorkspaceMutationContentObjectStoreReceipt {
        guard receipt.validationIssues().isEmpty,
              verification.validationIssues().isEmpty,
              receipt.verificationReceiptDigest == verification.receiptDigest,
              receipt.derivationDigest == verification.derivationDigest,
              receipt.objectSetDigest == verification.objectSetDigest else {
            throw WorkspaceMutationContentObjectStoreError.invalidVerificationReceipt
        }
        let observed = try validateInstalledArtifact(
            path: URL(fileURLWithPath: receipt.artifactPath, isDirectory: true),
            verification: verification,
            materialization: receipt.materialization,
            reused: receipt.reusedExistingArtifact
        )
        guard observed == receipt else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
        return observed
    }

    private func validateInputObjects(
        _ objects: [WorkspaceMutationContentObject],
        verification: WorkspaceMutationContentObjectSetReceipt
    ) throws {
        guard objects.count == verification.objectCount,
              WorkspaceMutationFilesystemExecutor.objectSetDigest(objects)
                == verification.objectSetDigest else {
            throw WorkspaceMutationContentObjectStoreError.inputObjectSetMismatch
        }
        let expected = Dictionary(uniqueKeysWithValues: verification.contentObjects.map {
            ($0.contentDigest, $0.size)
        })
        var observed: Set<ContentDigest> = []
        var total: UInt64 = 0
        for object in objects {
            guard observed.insert(object.digest).inserted,
                  expected[object.digest] == UInt64(object.data.count),
                  WorkspaceMutationFilesystemExecutor.contentDigest(object.data)
                    == object.digest else {
                throw WorkspaceMutationContentObjectStoreError.inputObjectSetMismatch
            }
            let (next, overflow) = total.addingReportingOverflow(
                UInt64(object.data.count)
            )
            guard !overflow else {
                throw WorkspaceMutationContentObjectStoreError.inputObjectSetMismatch
            }
            total = next
        }
        guard observed == Set(expected.keys), total == verification.totalBytes else {
            throw WorkspaceMutationContentObjectStoreError.inputObjectSetMismatch
        }
    }

    private func write(
        object: WorkspaceMutationContentObject,
        directory: Int32
    ) throws {
        let descriptor = object.digest.rawValue.withCString {
            Darwin.openat(
                directory,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o400)
            )
        }
        guard descriptor >= 0 else {
            throw Self.systemCallFailure("openat(content-object)")
        }
        defer { _ = Darwin.close(descriptor) }
        var offset = 0
        while offset < object.data.count {
            let written = object.data.withUnsafeBytes { bytes in
                Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    object.data.count - offset
                )
            }
            guard written > 0 else {
                if written < 0, errno == EINTR { continue }
                throw Self.systemCallFailure("write(content-object)")
            }
            offset += Int(written)
        }
        guard fchmod(descriptor, mode_t(0o400)) == 0,
              fsync(descriptor) == 0 else {
            throw Self.systemCallFailure("seal(content-object)")
        }
    }

    private func validateInstalledArtifact(
        path: URL,
        verification: WorkspaceMutationContentObjectSetReceipt,
        materialization: WorkspaceMutationContentObjectStoreMaterialization,
        reused: Bool,
        parentDescriptor: Int32? = nil,
        artifactName: String? = nil
    ) throws -> WorkspaceMutationContentObjectStoreReceipt {
        let descriptor: Int32
        if let parentDescriptor, let artifactName {
            descriptor = artifactName.withCString {
                Darwin.openat(
                    parentDescriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
        } else {
            descriptor = try openAbsoluteDirectory(
                path,
                error: .unsafeExistingArtifact
            )
        }
        guard descriptor >= 0 else {
            throw WorkspaceMutationContentObjectStoreError.unsafeExistingArtifact
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFDIR,
              before.st_uid == geteuid(),
              before.st_mode & 0o222 == 0 else {
            throw WorkspaceMutationContentObjectStoreError.unsafeExistingArtifact
        }
        let expected = Dictionary(uniqueKeysWithValues: verification.contentObjects.map {
            ($0.contentDigest.rawValue, $0.size)
        })
        let firstNames = try listNames(directory: descriptor)
        guard firstNames == expected.keys.sorted() else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
        for name in firstNames {
            try validateObject(
                named: name,
                expectedSize: expected[name]!,
                directory: descriptor
            )
        }
        let secondNames = try listNames(directory: descriptor)
        var after = stat()
        guard firstNames == secondNames,
              fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
        let manifestDigest = artifactManifestDigest(
            references: verification.contentObjects
        )
        var receipt = WorkspaceMutationContentObjectStoreReceipt(
            schemaVersion: 1,
            verificationReceiptDigest: verification.receiptDigest,
            derivationDigest: verification.derivationDigest,
            objectSetDigest: verification.objectSetDigest,
            artifactManifestDigest: manifestDigest,
            artifactPath: path.path,
            objectCount: verification.objectCount,
            totalBytes: verification.totalBytes,
            deviceID: UInt64(before.st_dev),
            inode: UInt64(before.st_ino),
            materialization: materialization,
            reusedExistingArtifact: reused,
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspaceMutationContentObjectStoreReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceMutationContentObjectStoreError.encodingFailed
        }
        receipt.receiptDigest = digest
        return receipt
    }

    private func cleanupTemporaryArtifact(
        named temporaryName: String,
        objects: [WorkspaceMutationContentObject],
        directory: Int32,
        store: Int32
    ) {
        _ = fchmod(directory, mode_t(0o700))
        for object in objects {
            object.digest.rawValue.withCString {
                _ = unlinkat(directory, $0, 0)
            }
        }
        _ = fsync(directory)
        temporaryName.withCString {
            _ = unlinkat(store, $0, AT_REMOVEDIR)
        }
        _ = fsync(store)
    }

    private func validateObject(
        named name: String,
        expectedSize: UInt64,
        directory: Int32
    ) throws {
        guard WorkspaceMutationContentObjectStoreReceipt.isSHA256(
            ContentDigest(name)
        ) else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
        let descriptor = name.withCString {
            Darwin.openat(
                directory,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == geteuid(),
              before.st_mode & 0o222 == 0,
              before.st_size >= 0,
              UInt64(before.st_size) == expectedSize else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
        var hasher = SHA256()
        var readBytes: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw Self.systemCallFailure("read(content-object)")
            }
            readBytes += UInt64(count)
            guard readBytes <= expectedSize else {
                throw WorkspaceMutationContentObjectStoreError
                    .existingArtifactMismatch
            }
            hasher.update(data: Data(buffer[0..<Int(count)]))
        }
        var after = stat()
        let digest = ContentDigest(hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined())
        guard fstat(descriptor, &after) == 0,
              readBytes == expectedSize,
              digest.rawValue == name,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw WorkspaceMutationContentObjectStoreError.existingArtifactMismatch
        }
    }

    private func listNames(directory: Int32) throws -> [String] {
        let duplicate = Darwin.openat(
            directory,
            ".",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard duplicate >= 0, let stream = fdopendir(duplicate) else {
            if duplicate >= 0 { _ = Darwin.close(duplicate) }
            throw Self.systemCallFailure("fdopendir(content-object-artifact)")
        }
        defer { closedir(stream) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: &entry.pointee.d_name) {
                String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }
            names.append(name)
        }
        guard errno == 0 else {
            throw Self.systemCallFailure("readdir(content-object-artifact)")
        }
        return names.sorted()
    }

    private func artifactManifestDigest(
        references: [WorkspaceMutationContentReference]
    ) -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(references)) ?? Data()
        return WorkspaceMutationContentObjectStoreReceipt.sha256(data)
    }

    private func validatePrivateDirectory(
        descriptor: Int32,
        error: WorkspaceMutationContentObjectStoreError,
        writable: Bool
    ) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0,
              status.st_mode & 0o500 == 0o500,
              !writable || status.st_mode & 0o200 == 0o200 else {
            throw error
        }
    }

    private func openAbsoluteDirectory(
        _ url: URL,
        error: WorkspaceMutationContentObjectStoreError
    ) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw error }
        var descriptor = Darwin.open(
            "/",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw error }
        for component in url.pathComponents.dropFirst() {
            guard !component.isEmpty, component != ".", component != ".." else {
                _ = Darwin.close(descriptor)
                throw error
            }
            let next = component.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard next >= 0 else {
                _ = Darwin.close(descriptor)
                throw error
            }
            _ = Darwin.close(descriptor)
            descriptor = next
        }
        return descriptor
    }

    private func canonicalExistingDirectory(_ url: URL) -> URL? {
        guard url.isFileURL,
              let resolved = url.standardizedFileURL.path.withCString({
                  Darwin.realpath($0, nil)
              }) else {
            return nil
        }
        defer { Darwin.free(resolved) }
        return URL(
            fileURLWithPath: String(cString: resolved),
            isDirectory: true
        )
    }

    private func directoryExists(named name: String, parent: Int32) throws -> Bool {
        var status = stat()
        let result = name.withCString {
            fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0 {
            if errno == ENOENT { return false }
            throw Self.systemCallFailure("fstatat(content-object-artifact)")
        }
        guard status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid() else {
            throw WorkspaceMutationContentObjectStoreError.unsafeExistingArtifact
        }
        return true
    }

    private static func systemCallFailure(
        _ operation: String
    ) -> WorkspaceMutationContentObjectStoreError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
