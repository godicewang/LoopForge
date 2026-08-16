import Darwin
import Foundation
import XCTest
@testable import LoopForge

final class ProcessGroupRuntimeAdapterTests: XCTestCase {
    func testRejectsInvalidSpecificationAndNonOwnedProcessLease() async {
        let adapter = ProcessGroupRuntimeAdapter()
        let valid = specification("/usr/bin/true")

        await XCTAssertThrowsAdapterError(.invalidSpecification) {
            _ = try await adapter.launch(
                lease: self.lease("relative"),
                specification: self.specification("usr/bin/true")
            )
        }

        var borrowed = lease("borrowed")
        borrowed.request.ownership = .borrowed
        await XCTAssertThrowsAdapterError(.invalidLease) {
            _ = try await adapter.launch(lease: borrowed, specification: valid)
        }

        var wrongKind = lease("timer")
        wrongKind.request.kind = .timer
        await XCTAssertThrowsAdapterError(.invalidLease) {
            _ = try await adapter.launch(lease: wrongKind, specification: valid)
        }

        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)
    }

    func testExpectedEnvironmentDigestMismatchRejectsBeforeSpawn() async {
        let adapter = ProcessGroupRuntimeAdapter()
        var mismatched = specification("/usr/bin/true")
        mismatched.expectedEnvironmentContentDigest = ContentDigest(
            String(repeating: "0", count: 64)
        )

        await XCTAssertThrowsAdapterError(.environmentContentMismatch) {
            _ = try await adapter.launch(
                lease: self.lease("environment-mismatch"),
                specification: mismatched
            )
        }

        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)
    }

    func testExpectedArgumentVectorDigestMismatchRejectsBeforeSpawn() async {
        let adapter = ProcessGroupRuntimeAdapter()
        var mismatched = specification("/usr/bin/true", arguments: ["authorized"])
        mismatched.expectedArgumentVectorContentDigest =
            KernelProviderInvocationCompiler.argumentVectorDigest(["different"])

        await XCTAssertThrowsAdapterError(.argumentVectorContentMismatch) {
            _ = try await adapter.launch(
                lease: self.lease("argument-vector-mismatch"),
                specification: mismatched
            )
        }

        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)
    }

    func testUnicodeHexLookalikeDigestIsInvalidSpecification() async {
        let adapter = ProcessGroupRuntimeAdapter()
        var invalid = specification("/usr/bin/true")
        invalid.expectedArgumentVectorContentDigest = ContentDigest(
            String(repeating: "１", count: 64)
        )

        await XCTAssertThrowsAdapterError(.invalidSpecification) {
            _ = try await adapter.launch(
                lease: self.lease("unicode-digest"),
                specification: invalid
            )
        }
    }

    func testNaturalExitRequiresWholeProcessGroupToDisappear() async throws {
        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("natural")
        let handle = try await adapter.launch(
            lease: value,
            specification: specification("/usr/bin/true")
        )

        let receipt = try await adapter.join(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )

        XCTAssertEqual(receipt.handle, handle)
        XCTAssertEqual(receipt.exitCode, 0)
        XCTAssertNil(receipt.terminationSignal)
        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)
    }

    func testFileBackedIOUsesExclusiveNoFollowFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ManagedProcessIO-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("prompt.txt")
        try Data("exact worker input\n".utf8).write(
            to: input,
            options: .withoutOverwriting
        )
        var secured = specification("/bin/cat")
        secured.ioFiles = ManagedProcessIOFiles(
            directoryPath: root.path,
            standardInputFileName: "prompt.txt",
            standardOutputFileName: "stdout.jsonl",
            standardErrorFileName: "stderr.txt"
        )
        let adapter = ProcessGroupRuntimeAdapter()
        let firstLease = lease("file-io")
        _ = try await adapter.launch(lease: firstLease, specification: secured)
        let exit = try await adapter.join(
            resourceID: firstLease.request.resourceID,
            leaseID: firstLease.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )

        XCTAssertEqual(exit.exitCode, 0)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("stdout.jsonl")),
            "exact worker input\n"
        )
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("stderr.txt")),
            Data()
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("stdout.jsonl").path
        )
        // The parent keeps the already-open write descriptor while pathname
        // reopen by the same user is denied before the child starts.
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o400)

        await XCTAssertThrowsAdapterError(.launchFailed(errno: EEXIST)) {
            _ = try await adapter.launch(
                lease: self.lease("file-io-overwrite"),
                specification: secured
            )
        }
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("stdout.jsonl")),
            "exact worker input\n"
        )
    }

    func testFileBackedIORejectsTraversalAndSymlinkInput() async throws {
        let adapter = ProcessGroupRuntimeAdapter()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ManagedProcessIOSymlink-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let realInput = root.appendingPathComponent("real.txt")
        try Data("do not follow\n".utf8).write(to: realInput)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("prompt-link.txt").path,
            withDestinationPath: realInput.path
        )

        var traversal = specification("/bin/cat")
        traversal.ioFiles = ManagedProcessIOFiles(
            directoryPath: root.path,
            standardInputFileName: "../real.txt",
            standardOutputFileName: nil,
            standardErrorFileName: nil
        )
        await XCTAssertThrowsAdapterError(.invalidSpecification) {
            _ = try await adapter.launch(
                lease: self.lease("io-traversal"),
                specification: traversal
            )
        }

        var symlink = specification("/bin/cat")
        symlink.ioFiles = ManagedProcessIOFiles(
            directoryPath: root.path,
            standardInputFileName: "prompt-link.txt",
            standardOutputFileName: "should-not-exist.txt",
            standardErrorFileName: nil
        )
        await XCTAssertThrowsAdapterError(.launchFailed(errno: ELOOP)) {
            _ = try await adapter.launch(
                lease: self.lease("io-symlink"),
                specification: symlink
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("should-not-exist.txt").path
            )
        )
    }

    func testFileBackedIOCleanupStaysBoundToOriginalDirectoryDescriptor() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ManagedProcessIOCleanup-\(UUID().uuidString)",
            isDirectory: true
        )
        let original = parent.appendingPathComponent("run", isDirectory: true)
        let moved = parent.appendingPathComponent("moved-run", isDirectory: true)
        try FileManager.default.createDirectory(
            at: original,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let directoryDescriptor = Darwin.open(
            original.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        XCTAssertGreaterThanOrEqual(directoryDescriptor, 0)
        defer { _ = Darwin.close(directoryDescriptor) }

        let createdName = "stdout.jsonl"
        let outside = parent.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside, options: .withoutOverwriting)
        let originalCreated = original.appendingPathComponent(createdName)
        try Data("owned-output".utf8).write(
            to: originalCreated,
            options: .withoutOverwriting
        )
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createDirectory(
            at: original,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let replacementSentinel = original.appendingPathComponent(createdName)
        try Data("unrelated-replacement".utf8).write(
            to: replacementSentinel,
            options: .withoutOverwriting
        )

        ProcessGroupRuntimeAdapter.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: [createdName, "../outside.txt"]
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: moved.appendingPathComponent(createdName).path
            )
        )
        XCTAssertEqual(
            try String(contentsOf: replacementSentinel),
            "unrelated-replacement"
        )
        XCTAssertEqual(try String(contentsOf: outside), "outside")
    }

    func testLeaderExitDoesNotManufactureGroupQuiescence() async throws {
        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("descendant")
        let handle = try await adapter.launch(
            lease: value,
            specification: specification(
                "/bin/sh",
                arguments: ["-c", "/bin/sleep 30 & exit 0"]
            )
        )

        await XCTAssertThrowsAdapterError(.terminationTimedOut) {
            _ = try await adapter.join(
                resourceID: value.request.resourceID,
                leaseID: value.request.leaseID,
                timeoutNanoseconds: 50_000_000
            )
        }
        let retainedProjection = await adapter.projection()
        XCTAssertEqual(retainedProjection.liveHandles.count, 1)

        let cleanup = try await adapter.terminate(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            graceNanoseconds: 100_000_000
        )
        XCTAssertEqual(cleanup.handle, handle)
        errno = 0
        XCTAssertEqual(Darwin.kill(-handle.processGroupID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        let cleanupProjection = await adapter.projection()
        XCTAssertTrue(cleanupProjection.liveHandles.isEmpty)
    }

    func testStaleLeaseCannotTerminateOwnedGroup() async throws {
        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("stale")
        _ = try await adapter.launch(
            lease: value,
            specification: specification("/bin/sleep", arguments: ["30"])
        )

        await XCTAssertThrowsAdapterError(
            .staleLease(
                expected: value.request.leaseID,
                supplied: ResourceLeaseID("stale-token")
            )
        ) {
            _ = try await adapter.terminate(
                resourceID: value.request.resourceID,
                leaseID: ResourceLeaseID("stale-token"),
                graceNanoseconds: 10_000_000
            )
        }
        let retainedProjection = await adapter.projection()
        XCTAssertEqual(retainedProjection.liveHandles.count, 1)

        _ = try await adapter.terminate(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            graceNanoseconds: 100_000_000
        )
    }

    func testGracefulResistanceForcesWholeGroupWithoutTouchingUnrelatedProcess() async throws {
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["30"]
        try unrelated.run()
        defer {
            if unrelated.isRunning {
                _ = Darwin.kill(unrelated.processIdentifier, SIGKILL)
            }
        }

        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("resistant")
        let handle = try await adapter.launch(
            lease: value,
            specification: specification(
                "/bin/sh",
                arguments: ["-c", "trap '' TERM; while :; do /bin/sleep 1; done"]
            )
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        let receipt = try await adapter.terminate(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            graceNanoseconds: 50_000_000
        )

        XCTAssertTrue(receipt.forced)
        XCTAssertEqual(receipt.exit.terminationSignal, SIGKILL)
        errno = 0
        XCTAssertEqual(Darwin.kill(-handle.processGroupID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        XCTAssertTrue(unrelated.isRunning)
        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)

        unrelated.terminate()
        for _ in 0..<20 where unrelated.isRunning {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        if unrelated.isRunning {
            _ = Darwin.kill(unrelated.processIdentifier, SIGKILL)
        }
        for _ in 0..<200 where unrelated.isRunning {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(unrelated.isRunning)
    }

    func testDuplicateLeaseIsIdempotentAndConflictingLeaseIsRejected() async throws {
        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("duplicate")
        let first = try await adapter.launch(
            lease: value,
            specification: specification("/bin/sleep", arguments: ["30"])
        )
        let duplicate = try await adapter.launch(
            lease: value,
            specification: specification("/usr/bin/true")
        )
        XCTAssertEqual(duplicate, first)

        var conflict = value
        conflict.request.leaseID = ResourceLeaseID("different-lease")
        await XCTAssertThrowsAdapterError(
            .duplicateResource(existingLeaseID: value.request.leaseID)
        ) {
            _ = try await adapter.launch(
                lease: conflict,
                specification: self.specification("/usr/bin/true")
            )
        }
        let projection = await adapter.projection()
        XCTAssertEqual(projection.liveHandles, [first])

        _ = try await adapter.terminate(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            graceNanoseconds: 100_000_000
        )
    }

    func testRecoveryReattachesOnlyToExactProcessStartIdentity() async throws {
        let original = ProcessGroupRuntimeAdapter()
        var value = lease("recover-exact")
        let launched = try await original.launch(
            lease: value,
            specification: specification("/bin/sleep", arguments: ["30"])
        )
        XCTAssertNotNil(launched.externalIdentity.processStartSystemNanoseconds)
        value.request.externalIdentity = launched.externalIdentity

        let recoveredAdapter = ProcessGroupRuntimeAdapter()
        let recovered = try await recoveredAdapter.recover(lease: value)
        XCTAssertEqual(recovered, launched)
        let recoveredProjection = await recoveredAdapter.projection()
        XCTAssertEqual(recoveredProjection.liveHandles, [launched])

        _ = try await recoveredAdapter.terminate(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            graceNanoseconds: 100_000_000
        )
        _ = try await original.join(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            timeoutNanoseconds: 1_000_000_000
        )
    }

    func testRecoveryRejectsPIDReuseIdentityWithoutSignallingProcess() async throws {
        let original = ProcessGroupRuntimeAdapter()
        var value = lease("recover-mismatch")
        let launched = try await original.launch(
            lease: value,
            specification: specification("/bin/sleep", arguments: ["30"])
        )
        var mismatchedIdentity = launched.externalIdentity
        mismatchedIdentity.processStartSystemNanoseconds =
            (mismatchedIdentity.processStartSystemNanoseconds ?? 0) + 1
        value.request.externalIdentity = mismatchedIdentity

        let recoveredAdapter = ProcessGroupRuntimeAdapter()
        await XCTAssertThrowsAdapterError(.recoveryIdentityMismatch) {
            _ = try await recoveredAdapter.recover(lease: value)
        }
        XCTAssertEqual(Darwin.kill(launched.processID, 0), 0)
        let mismatchProjection = await recoveredAdapter.projection()
        XCTAssertTrue(mismatchProjection.liveHandles.isEmpty)

        _ = try await original.terminate(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            graceNanoseconds: 100_000_000
        )
    }

    func testRecoveryDistinguishesMissingIdentityAndAbsentProcess() async throws {
        let adapter = ProcessGroupRuntimeAdapter()
        let missing = lease("recover-missing")
        await XCTAssertThrowsAdapterError(.recoveryIdentityMissing) {
            _ = try await adapter.recover(lease: missing)
        }

        var absent = lease("recover-absent")
        let launched = try await adapter.launch(
            lease: absent,
            specification: specification("/usr/bin/true")
        )
        _ = try await adapter.join(
            resourceID: absent.request.resourceID,
            leaseID: absent.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )
        absent.request.externalIdentity = launched.externalIdentity
        let recoveredAdapter = ProcessGroupRuntimeAdapter()
        await XCTAssertThrowsAdapterError(.recoveryProcessAbsent) {
            _ = try await recoveredAdapter.recover(lease: absent)
        }
        let absentProjection = await recoveredAdapter.projection()
        XCTAssertTrue(absentProjection.liveHandles.isEmpty)
    }

    private func lease(_ id: String) -> RuntimeResourceLease {
        RuntimeResourceLease(
            request: RuntimeLeaseRequest(
                leaseID: ResourceLeaseID("lease-\(id)"),
                resourceID: OwnedResourceID("resource-\(id)"),
                runID: KernelRunID("process-adapter-run"),
                occurrenceID: OccurrenceID("occurrence-\(id)"),
                attemptID: AttemptID("attempt-\(id)"),
                kind: .processTree,
                purpose: .productive,
                ownership: .owned,
                releasePolicy: .gracefulThenTerminate,
                externalIdentity: nil,
                reservation: ResourceVector(
                    cpuWeight: 1,
                    memoryBytes: 1,
                    diskIOWeight: 0,
                    gpuWeight: 0,
                    networkWeight: 0,
                    guiSessionCount: 0,
                    processCount: 1
                ),
                requestedAtMonotonicNanoseconds: 1,
                renewalDeadlineMonotonicNanoseconds: nil,
                progressReceiptID: nil
            ),
            admittedAtMonotonicNanoseconds: 1,
            lastProgressReceiptID: nil
        )
    }

    private func specification(
        _ path: String,
        arguments: [String] = []
    ) -> ManagedProcessSpecification {
        ManagedProcessSpecification(
            executablePath: path,
            arguments: arguments,
            environment: ["PATH": "/usr/bin:/bin"]
        )
    }

    private func XCTAssertThrowsAdapterError<T>(
        _ expected: ProcessGroupAdapterError,
        operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ProcessGroupAdapterError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
