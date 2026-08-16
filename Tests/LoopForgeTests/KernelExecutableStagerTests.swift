import Foundation
import XCTest
@testable import LoopForge

final class KernelExecutableStagerTests: XCTestCase {
    func testStagesExactExecutableOnceAndReusesContentAddressedArtifact() throws {
        let fixture = try makeFixture("reuse")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )

        let first = try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )
        let second = try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )

        XCTAssertFalse(first.reusedExistingArtifact)
        XCTAssertNotEqual(first.materialization, .existingArtifact)
        XCTAssertTrue(second.reusedExistingArtifact)
        XCTAssertEqual(second.materialization, .existingArtifact)
        XCTAssertEqual(first.stagedExecutablePath, second.stagedExecutablePath)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(first.inode, second.inode)
        XCTAssertEqual(first.contentDigest, digest)
        XCTAssertEqual(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: first.stagedExecutablePath
            ),
            digest
        )
    }

    func testStagedExecutableRunsWithoutDependingOnSourcePath() throws {
        let fixture = try makeFixture("runs")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )
        let receipt = try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: receipt.stagedExecutablePath)
        process.arguments = ["--exit", "0"]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testResolveStagedReopensOnlyEnrollmentOwnedArtifact() throws {
        let fixture = try makeFixture("resolve")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )
        let imported = try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )

        let resolved = try KernelExecutableStager().resolveStaged(
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )

        XCTAssertEqual(resolved.stagedExecutablePath, imported.stagedExecutablePath)
        XCTAssertEqual(resolved.sourceExecutablePath, imported.stagedExecutablePath)
        XCTAssertEqual(resolved.contentDigest, digest)
        XCTAssertEqual(resolved.deviceID, imported.deviceID)
        XCTAssertEqual(resolved.inode, imported.inode)
        XCTAssertEqual(resolved.materialization, .existingArtifact)
        XCTAssertTrue(resolved.reusedExistingArtifact)
    }

    func testResolveStagedDoesNotImportMissingCallerContent() throws {
        let fixture = try makeFixture("resolve-missing")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )

        XCTAssertThrowsError(try KernelExecutableStager().resolveStaged(
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? KernelExecutableStagingError,
                .stagedArtifactMissing
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.runDirectory.appendingPathComponent(
                KernelExecutableStager.directoryName,
                isDirectory: true
            ).path
        ))
    }

    func testSourceMutationCannotChangeInstalledArtifact() throws {
        let fixture = try makeFixture("source-mutation")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mutableSource = fixture.root.appendingPathComponent("mutable-worker")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: helperPath),
            to: mutableSource
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: mutableSource.path
        )
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: mutableSource.path)
        )
        let receipt = try KernelExecutableStager().stage(
            executablePath: mutableSource.path,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )

        let handle = try FileHandle(forWritingTo: mutableSource)
        try handle.truncate(atOffset: 8)
        try handle.close()

        XCTAssertEqual(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: receipt.stagedExecutablePath
            ),
            digest
        )
        XCTAssertNotEqual(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: mutableSource.path),
            digest
        )
    }

    func testSymlinkedStagingDirectoryFailsClosed() throws {
        let fixture = try makeFixture("symlink-directory")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let staging = fixture.runDirectory.appendingPathComponent(
            KernelExecutableStager.directoryName,
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: outside)
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )

        XCTAssertThrowsError(try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? KernelExecutableStagingError,
                .unsafeStagingDirectory
            )
        }
    }

    func testWrongExistingContentAddressedArtifactFailsClosed() throws {
        let fixture = try makeFixture("wrong-existing")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )
        let staging = fixture.runDirectory.appendingPathComponent(
            KernelExecutableStager.directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: staging.path
        )
        let artifact = staging.appendingPathComponent(digest.rawValue)
        try Data("wrong".utf8).write(to: artifact, options: .withoutOverwriting)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: artifact.path
        )

        XCTAssertThrowsError(try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? KernelExecutableStagingError,
                .existingArtifactDigestMismatch
            )
        }
    }

    func testResolveStagedRejectsTamperedEnrollmentArtifact() throws {
        let fixture = try makeFixture("resolve-tampered")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let digest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(atPath: helperPath)
        )
        let imported = try KernelExecutableStager().stage(
            executablePath: helperPath,
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )
        XCTAssertEqual(chmod(imported.stagedExecutablePath, 0o700), 0)
        try Data("tampered".utf8).write(
            to: URL(fileURLWithPath: imported.stagedExecutablePath),
            options: .atomic
        )
        XCTAssertEqual(chmod(imported.stagedExecutablePath, 0o500), 0)

        XCTAssertThrowsError(try KernelExecutableStager().resolveStaged(
            expectedDigest: digest,
            runDirectory: fixture.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? KernelExecutableStagingError,
                .existingArtifactDigestMismatch
            )
        }
    }

    private func makeFixture(_ name: String) throws -> (root: URL, runDirectory: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ExecutableStager-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let runDirectory = root.appendingPathComponent("run", isDirectory: true)
        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return (root, runDirectory)
    }

    private var helperPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/KernelProcessFixture")
            .standardizedFileURL.path
    }
}
