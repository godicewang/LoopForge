import CryptoKit
import Darwin
import Foundation

enum KernelExecutableStagingMaterialization: String, Codable, Hashable, Sendable {
    case cloneOnWrite
    case streamCopy
    case existingArtifact
}

struct KernelExecutableStagingReceipt: Codable, Hashable, Sendable {
    var sourceExecutablePath: String
    var stagedExecutablePath: String
    var contentDigest: ContentDigest
    var byteCount: UInt64
    var deviceID: UInt64
    var inode: UInt64
    var materialization: KernelExecutableStagingMaterialization
    var reusedExistingArtifact: Bool
}

enum KernelExecutableStagingError: Error, Equatable {
    case invalidExpectedDigest
    case invalidRunDirectory
    case unsafeStagingDirectory
    case invalidSourceExecutable
    case executableTooLarge(maximumBytes: UInt64)
    case sourceDigestMismatch
    case stagedArtifactMissing
    case unsafeExistingArtifact
    case existingArtifactDigestMismatch
    case systemCallFailed(operation: String, errno: Int32)
}

/// Materializes an exact, content-addressed executable inside the journal's
/// owner-private run directory. The launch path therefore stops depending on
/// a mutable source pathname when native enrollment commits the run.
struct KernelExecutableStager: Sendable {
    static let directoryName = "runtime-executables"
    static let maximumExecutableBytes: UInt64 = 512 * 1_024 * 1_024

    func stage(
        executablePath: String,
        expectedDigest: ContentDigest,
        runDirectory: URL
    ) throws -> KernelExecutableStagingReceipt {
        guard Self.digestIsValid(expectedDigest) else {
            throw KernelExecutableStagingError.invalidExpectedDigest
        }

        let runDirectoryPath = runDirectory.standardizedFileURL.path
        let runDirectoryDescriptor = open(
            runDirectoryPath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard runDirectoryDescriptor >= 0 else {
            throw KernelExecutableStagingError.invalidRunDirectory
        }
        defer { close(runDirectoryDescriptor) }

        if mkdirat(runDirectoryDescriptor, Self.directoryName, 0o700) != 0,
           errno != EEXIST {
            throw Self.systemCallFailure("mkdirat(runtime-executables)")
        }

        let directoryDescriptor = openat(
            runDirectoryDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw KernelExecutableStagingError.unsafeStagingDirectory
        }
        defer { close(directoryDescriptor) }
        try Self.validatePrivateDirectory(descriptor: directoryDescriptor)

        let artifactName = expectedDigest.rawValue
        if let existing = try Self.existingArtifact(
            directoryDescriptor: directoryDescriptor,
            artifactName: artifactName,
            expectedDigest: expectedDigest,
            sourceExecutablePath: executablePath,
            runDirectoryPath: runDirectoryPath
        ) {
            return existing
        }

        let resolvedSourcePath = URL(
            fileURLWithPath: executablePath
        ).standardizedFileURL.resolvingSymlinksInPath().path
        let sourceDescriptor = open(
            resolvedSourcePath,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard sourceDescriptor >= 0 else {
            throw KernelExecutableStagingError.invalidSourceExecutable
        }
        defer { close(sourceDescriptor) }

        var sourceStatus = stat()
        guard fstat(sourceDescriptor, &sourceStatus) == 0,
              (sourceStatus.st_mode & S_IFMT) == S_IFREG,
              (sourceStatus.st_mode & 0o111) != 0,
              sourceStatus.st_size >= 0 else {
            throw KernelExecutableStagingError.invalidSourceExecutable
        }
        let sourceByteCount = UInt64(sourceStatus.st_size)
        guard sourceByteCount <= Self.maximumExecutableBytes else {
            throw KernelExecutableStagingError.executableTooLarge(
                maximumBytes: Self.maximumExecutableBytes
            )
        }

        let temporaryName = ".\(artifactName).\(UUID().uuidString).tmp"
        let cloned = fclonefileat(
            sourceDescriptor,
            directoryDescriptor,
            temporaryName,
            0
        ) == 0
        if !cloned,
           errno != ENOTSUP,
           errno != EOPNOTSUPP,
           errno != EXDEV,
           errno != EINVAL {
            throw Self.systemCallFailure("fclonefileat(staging-temporary)")
        }
        let destinationDescriptor = cloned
            ? openat(
                directoryDescriptor,
                temporaryName,
                O_RDWR | O_CLOEXEC | O_NOFOLLOW
            )
            : openat(
                directoryDescriptor,
                temporaryName,
                O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o500)
            )
        guard destinationDescriptor >= 0 else {
            _ = unlinkat(directoryDescriptor, temporaryName, 0)
            throw Self.systemCallFailure("openat(staging-temporary)")
        }
        var temporaryInstalled = false
        defer {
            close(destinationDescriptor)
            if !temporaryInstalled {
                _ = unlinkat(directoryDescriptor, temporaryName, 0)
            }
        }

        let observedDigest: ContentDigest
        if cloned {
            var clonedStatus = stat()
            guard fstat(destinationDescriptor, &clonedStatus) == 0,
                  (clonedStatus.st_mode & S_IFMT) == S_IFREG,
                  clonedStatus.st_size >= 0,
                  UInt64(clonedStatus.st_size) == sourceByteCount else {
                throw KernelExecutableStagingError.invalidSourceExecutable
            }
            observedDigest = try Self.digest(descriptor: destinationDescriptor)
        } else {
            observedDigest = try Self.copyAndDigest(
                sourceDescriptor: sourceDescriptor,
                destinationDescriptor: destinationDescriptor,
                expectedByteCount: sourceByteCount,
                sourceStatus: sourceStatus
            )
        }
        guard observedDigest == expectedDigest else {
            throw KernelExecutableStagingError.sourceDigestMismatch
        }
        guard fchmod(destinationDescriptor, mode_t(0o500)) == 0 else {
            throw Self.systemCallFailure("fchmod(staged-executable)")
        }
        guard fsync(destinationDescriptor) == 0 else {
            throw Self.systemCallFailure("fsync(staged-executable)")
        }

        if linkat(
            directoryDescriptor,
            temporaryName,
            directoryDescriptor,
            artifactName,
            0
        ) == 0 {
            guard unlinkat(directoryDescriptor, temporaryName, 0) == 0 else {
                throw Self.systemCallFailure("unlinkat(staging-temporary)")
            }
            temporaryInstalled = true
            guard fsync(directoryDescriptor) == 0 else {
                throw Self.systemCallFailure("fsync(runtime-executables)")
            }
        } else if errno == EEXIST {
            guard let existing = try Self.existingArtifact(
                directoryDescriptor: directoryDescriptor,
                artifactName: artifactName,
                expectedDigest: expectedDigest,
                sourceExecutablePath: executablePath,
                runDirectoryPath: runDirectoryPath
            ) else {
                throw KernelExecutableStagingError.unsafeExistingArtifact
            }
            return existing
        } else {
            throw Self.systemCallFailure("linkat(staged-executable)")
        }

        guard let installed = try Self.existingArtifact(
            directoryDescriptor: directoryDescriptor,
            artifactName: artifactName,
            expectedDigest: expectedDigest,
            sourceExecutablePath: executablePath,
            runDirectoryPath: runDirectoryPath,
            materialization: cloned ? .cloneOnWrite : .streamCopy,
            reused: false
        ) else {
            throw KernelExecutableStagingError.unsafeExistingArtifact
        }
        return installed
    }

    /// Re-opens the exact content-addressed executable imported at enrollment.
    /// This path never creates or imports an artifact and therefore cannot turn
    /// a later caller-controlled pathname into launch authority.
    func resolveStaged(
        expectedDigest: ContentDigest,
        runDirectory: URL
    ) throws -> KernelExecutableStagingReceipt {
        guard Self.digestIsValid(expectedDigest) else {
            throw KernelExecutableStagingError.invalidExpectedDigest
        }

        let runDirectoryPath = runDirectory.standardizedFileURL.path
        let runDirectoryDescriptor = open(
            runDirectoryPath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard runDirectoryDescriptor >= 0 else {
            throw KernelExecutableStagingError.invalidRunDirectory
        }
        defer { close(runDirectoryDescriptor) }

        let directoryDescriptor = openat(
            runDirectoryDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            if errno == ENOENT {
                throw KernelExecutableStagingError.stagedArtifactMissing
            }
            throw KernelExecutableStagingError.unsafeStagingDirectory
        }
        defer { close(directoryDescriptor) }
        try Self.validatePrivateDirectory(descriptor: directoryDescriptor)

        let stagedPath = URL(fileURLWithPath: runDirectoryPath, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(expectedDigest.rawValue, isDirectory: false)
            .path
        guard let existing = try Self.existingArtifact(
            directoryDescriptor: directoryDescriptor,
            artifactName: expectedDigest.rawValue,
            expectedDigest: expectedDigest,
            sourceExecutablePath: stagedPath,
            runDirectoryPath: runDirectoryPath
        ) else {
            throw KernelExecutableStagingError.stagedArtifactMissing
        }
        return existing
    }

    private static func existingArtifact(
        directoryDescriptor: Int32,
        artifactName: String,
        expectedDigest: ContentDigest,
        sourceExecutablePath: String,
        runDirectoryPath: String,
        materialization: KernelExecutableStagingMaterialization = .existingArtifact,
        reused: Bool = true
    ) throws -> KernelExecutableStagingReceipt? {
        let descriptor = openat(
            directoryDescriptor,
            artifactName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw KernelExecutableStagingError.unsafeExistingArtifact
        }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == geteuid(),
              (status.st_mode & 0o022) == 0,
              (status.st_mode & 0o100) != 0,
              status.st_nlink == 1,
              status.st_size >= 0,
              UInt64(status.st_size) <= maximumExecutableBytes else {
            throw KernelExecutableStagingError.unsafeExistingArtifact
        }
        let observedDigest = try digest(descriptor: descriptor)
        guard observedDigest == expectedDigest else {
            throw KernelExecutableStagingError.existingArtifactDigestMismatch
        }
        let stagedPath = URL(fileURLWithPath: runDirectoryPath, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(artifactName, isDirectory: false)
            .path
        return KernelExecutableStagingReceipt(
            sourceExecutablePath: sourceExecutablePath,
            stagedExecutablePath: stagedPath,
            contentDigest: expectedDigest,
            byteCount: UInt64(status.st_size),
            deviceID: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            materialization: materialization,
            reusedExistingArtifact: reused
        )
    }

    private static func copyAndDigest(
        sourceDescriptor: Int32,
        destinationDescriptor: Int32,
        expectedByteCount: UInt64,
        sourceStatus: stat
    ) throws -> ContentDigest {
        var hasher = SHA256()
        var copiedBytes: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(sourceDescriptor, bytes.baseAddress, bytes.count)
            }
            if readCount == 0 { break }
            guard readCount > 0 else {
                if errno == EINTR { continue }
                throw systemCallFailure("read(source-executable)")
            }
            let count = Int(readCount)
            copiedBytes += UInt64(count)
            guard copiedBytes <= maximumExecutableBytes else {
                throw KernelExecutableStagingError.executableTooLarge(
                    maximumBytes: maximumExecutableBytes
                )
            }
            hasher.update(data: Data(buffer[0..<count]))
            var written = 0
            while written < count {
                let writeCount = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        destinationDescriptor,
                        bytes.baseAddress!.advanced(by: written),
                        count - written
                    )
                }
                guard writeCount > 0 else {
                    if writeCount < 0, errno == EINTR { continue }
                    throw systemCallFailure("write(staged-executable)")
                }
                written += Int(writeCount)
            }
        }

        var sourceStatusAfterCopy = stat()
        guard fstat(sourceDescriptor, &sourceStatusAfterCopy) == 0,
              sourceStatusAfterCopy.st_dev == sourceStatus.st_dev,
              sourceStatusAfterCopy.st_ino == sourceStatus.st_ino,
              sourceStatusAfterCopy.st_size == sourceStatus.st_size,
              copiedBytes == expectedByteCount else {
            throw KernelExecutableStagingError.invalidSourceExecutable
        }
        return ContentDigest(
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func validatePrivateDirectory(descriptor: Int32) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR,
              status.st_uid == geteuid(),
              (status.st_mode & 0o077) == 0,
              (status.st_mode & 0o500) == 0o500 else {
            throw KernelExecutableStagingError.unsafeStagingDirectory
        }
    }

    private static func digest(descriptor: Int32) throws -> ContentDigest {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw systemCallFailure("lseek(staged-executable)")
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw systemCallFailure("read(staged-executable)")
            }
            hasher.update(data: Data(buffer[0..<Int(count)]))
        }
        return ContentDigest(
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func digestIsValid(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64
            && digest.rawValue.unicodeScalars.allSatisfy {
                (48...57).contains($0.value) || (97...102).contains($0.value)
            }
    }

    private static func systemCallFailure(
        _ operation: String
    ) -> KernelExecutableStagingError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
