import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceCandidatePostimageMaterializerTests: XCTestCase {
    func testMaterializesReadOnlyContentAddressedTreeAndReusesExactBytes() throws {
        let fixture = try makeFixture("materialize")
        defer { makeRemovableAndDelete(fixture.container) }
        let materializer = WorkspaceCandidatePostimageMaterializer()

        let firstInput = try materializer.materialize(
            attestation: fixture.attestation,
            workspaceRoot: fixture.workspace,
            runDirectory: fixture.runDirectory
        )
        let first = firstInput.receipt
        let second = try materializer.materialize(
            attestation: fixture.attestation,
            workspaceRoot: fixture.workspace,
            runDirectory: fixture.runDirectory
        ).receipt

        XCTAssertEqual(first.workspaceID, fixture.artifact.workspaceID)
        XCTAssertEqual(first.applyReceiptID, ReceiptID("apply-receipt"))
        XCTAssertEqual(first.sourceRevision, fixture.artifact.sourceRevision)
        XCTAssertEqual(first.fileCount, 2)
        XCTAssertEqual(first.totalBytes, fixture.artifact.totalBytes)
        XCTAssertEqual(first.materialization, .streamCopy)
        XCTAssertFalse(first.reusedExistingArtifact)
        XCTAssertEqual(second.materialization, .existingArtifact)
        XCTAssertTrue(second.reusedExistingArtifact)
        XCTAssertEqual(first.snapshotRootPath, second.snapshotRootPath)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(first.inode, second.inode)
        XCTAssertEqual(try materializer.revalidate(firstInput), first)
        let descriptorAuthority = try materializer.openRevalidatedDescriptor(
            firstInput
        )
        defer { descriptorAuthority.close() }
        let heldDescriptor = try descriptorAuthority.descriptorForLaunch(
            matching: first
        )
        var heldStatus = stat()
        XCTAssertEqual(fstat(heldDescriptor, &heldStatus), 0)
        XCTAssertEqual(UInt64(heldStatus.st_dev), first.deviceID)
        XCTAssertEqual(UInt64(heldStatus.st_ino), first.inode)

        let snapshot = URL(
            fileURLWithPath: first.snapshotRootPath,
            isDirectory: true
        )
        XCTAssertEqual(
            try String(contentsOf: snapshot.appendingPathComponent("Sources/a.swift")),
            "let value = 1\n"
        )
        XCTAssertEqual(try materializer.revalidate(firstInput), first)
        XCTAssertEqual(
            try String(contentsOf: snapshot.appendingPathComponent("README.md")),
            "candidate\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: snapshot.appendingPathComponent(".build/cache.bin").path
        ))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: snapshot.appendingPathComponent("Sources/a.swift").path
        )
        let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
            .uint16Value
        XCTAssertEqual(mode & 0o222, 0)

        try Data("let value = 200\n".utf8).write(
            to: fixture.workspace.appendingPathComponent("Sources/a.swift"),
            options: .atomic
        )
        XCTAssertEqual(
            try String(contentsOf: snapshot.appendingPathComponent("Sources/a.swift")),
            "let value = 1\n"
        )
    }

    func testHeldDescriptorSurvivesPathReplacementAndRemainsExact() throws {
        let fixture = try makeFixture("descriptor-replacement")
        defer { makeRemovableAndDelete(fixture.container) }
        let materializer = WorkspaceCandidatePostimageMaterializer()
        let input = try materializer.materialize(
            attestation: fixture.attestation,
            workspaceRoot: fixture.workspace,
            runDirectory: fixture.runDirectory
        )
        let authority = try materializer.openRevalidatedDescriptor(input)
        defer { authority.close() }
        let descriptor = try authority.descriptorForLaunch(
            matching: input.receipt
        )
        let original = URL(
            fileURLWithPath: input.receipt.snapshotRootPath,
            isDirectory: true
        )
        let retained = original.deletingLastPathComponent()
            .appendingPathComponent("retained-exact-root", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: retained)
        try FileManager.default.createDirectory(
            at: original,
            withIntermediateDirectories: false
        )
        try Data("replacement\n".utf8).write(
            to: original.appendingPathComponent("README.md")
        )

        let heldREADME = Darwin.openat(
            descriptor,
            "README.md",
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        XCTAssertGreaterThanOrEqual(heldREADME, 0)
        defer { if heldREADME >= 0 { _ = Darwin.close(heldREADME) } }
        var bytes = [UInt8](repeating: 0, count: 32)
        let byteCount = Darwin.read(heldREADME, &bytes, bytes.count)
        XCTAssertEqual(
            String(decoding: bytes.prefix(max(0, byteCount)), as: UTF8.self),
            "candidate\n"
        )
        XCTAssertEqual(
            try String(contentsOf: original.appendingPathComponent("README.md")),
            "replacement\n"
        )
        XCTAssertThrowsError(try materializer.openRevalidatedDescriptor(input))
    }

    func testWorkspaceDriftAndOverlappingStorageFailBeforeSnapshot() throws {
        let drift = try makeFixture("drift")
        defer { makeRemovableAndDelete(drift.container) }
        try Data("changed\n".utf8).write(
            to: drift.workspace.appendingPathComponent("README.md"),
            options: .atomic
        )
        XCTAssertThrowsError(try WorkspaceCandidatePostimageMaterializer().materialize(
            attestation: drift.attestation,
            workspaceRoot: drift.workspace,
            runDirectory: drift.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceCandidatePostimageMaterializationError,
                .sourceRevisionMismatch
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: drift.runDirectory.appendingPathComponent(
                WorkspaceCandidatePostimageMaterializer.directoryName
            ).path
        ))

        let overlap = try makeFixture("overlap")
        defer { makeRemovableAndDelete(overlap.container) }
        let overlappingRun = overlap.workspace.appendingPathComponent("run")
        try FileManager.default.createDirectory(
            at: overlappingRun,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        XCTAssertThrowsError(try WorkspaceCandidatePostimageMaterializer().materialize(
            attestation: overlap.attestation,
            workspaceRoot: overlap.workspace,
            runDirectory: overlappingRun
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceCandidatePostimageMaterializationError,
                .storageOverlapsWorkspace
            )
        }
    }

    func testTamperedExistingSnapshotAndSymlinkedSourceFailClosed() throws {
        let tampered = try makeFixture("tampered")
        defer { makeRemovableAndDelete(tampered.container) }
        let materializer = WorkspaceCandidatePostimageMaterializer()
        let input = try materializer.materialize(
            attestation: tampered.attestation,
            workspaceRoot: tampered.workspace,
            runDirectory: tampered.runDirectory
        )
        let receipt = input.receipt
        let snapshot = URL(fileURLWithPath: receipt.snapshotRootPath, isDirectory: true)
        let sourceDirectory = snapshot.appendingPathComponent("Sources", isDirectory: true)
        let snapshotFile = sourceDirectory.appendingPathComponent("a.swift")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: snapshot.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: sourceDirectory.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: snapshotFile.path
        )
        try Data("tampered\n".utf8).write(to: snapshotFile, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: sourceDirectory.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: snapshot.path
        )
        XCTAssertThrowsError(try materializer.revalidate(input)) { error in
            XCTAssertEqual(
                error as? WorkspaceCandidatePostimageMaterializationError,
                .existingArtifactMismatch
            )
        }
        XCTAssertThrowsError(try materializer.materialize(
            attestation: tampered.attestation,
            workspaceRoot: tampered.workspace,
            runDirectory: tampered.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceCandidatePostimageMaterializationError,
                .existingArtifactMismatch
            )
        }

        let symlink = try makeFixture("symlink")
        defer { makeRemovableAndDelete(symlink.container) }
        let source = symlink.workspace.appendingPathComponent("Sources/a.swift")
        let outside = symlink.container.appendingPathComponent("outside.swift")
        try Data("let value = 1\n".utf8).write(to: outside)
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        XCTAssertThrowsError(try materializer.materialize(
            attestation: symlink.attestation,
            workspaceRoot: symlink.workspace,
            runDirectory: symlink.runDirectory
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceCandidatePostimageMaterializationError,
                .sourceRevisionMismatch
            )
        }
    }

    private func makeFixture(_ name: String) throws -> (
        container: URL,
        workspace: URL,
        runDirectory: URL,
        artifact: WorkspaceSourceRevisionArtifact,
        attestation: WorkspaceCandidatePostimageAttestationReceipt
    ) {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-CandidateMaterializer-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = container.appendingPathComponent("workspace", isDirectory: true)
        let runDirectory = container.appendingPathComponent("run", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent(".build", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("let value = 1\n".utf8).write(
            to: workspace.appendingPathComponent("Sources/a.swift")
        )
        try Data("candidate\n".utf8).write(
            to: workspace.appendingPathComponent("README.md")
        )
        try Data("generated".utf8).write(
            to: workspace.appendingPathComponent(".build/cache.bin")
        )
        let workspaceID = WorkspaceID("workspace-\(name)")
        let artifact = try WorkspaceSourceRevisionCollector().capture(
            workspaceID: workspaceID,
            root: workspace,
            excludedDirectoryNames: [".build"],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 100,
                maximumTotalBytes: 1_024 * 1_024,
                maximumFileBytes: 1_024 * 1_024
            )
        )
        let transaction = JournalTransactionReceipt(
            commandID: RunCommandID("apply-command"),
            startingSequence: 9,
            endingSequence: 9,
            eventIDs: [OrchestrationEventID("apply-event")],
            frameDigest: HeavyEvidenceCache.sha256("apply-frame"),
            duplicate: false
        )
        let attestation = try WorkspaceCandidatePostimageAttestationReceipt
            .testOnlyAccepted(
                workspaceID: workspaceID,
                root: workspace,
                candidatePostimage: artifact,
                applyReceiptID: ReceiptID("apply-receipt"),
                journalTransaction: transaction
            )
        return (container, workspace, runDirectory, artifact, attestation)
    }

    private func makeRemovableAndDelete(_ root: URL) {
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            var directories: [URL] = []
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey])
                    .isDirectory) == true {
                    directories.append(url)
                }
            }
            for directory in directories.reversed() {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: directory.path
                )
            }
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        try? FileManager.default.removeItem(at: root)
    }
}
