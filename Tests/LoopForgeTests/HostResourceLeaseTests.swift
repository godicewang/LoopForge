import Darwin
import Foundation
import XCTest
@testable import LoopForge

final class HostResourceLeaseTests: XCTestCase {
    func testBorrowedSimulatorIsNeverReleased() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .active])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "borrowed", iteration: 1
        )
        let lease = try await fixture.registry.declareAcquisition(
            scopeID: scope.id,
            kind: .iosSimulatorBoot,
            identifier: Self.firstUDID
        )
        XCTAssertEqual(lease.ownership, .borrowed)

        try await fixture.registry.markAcquired(leaseID: lease.id)
        _ = await fixture.registry.releaseScope(id: scope.id, reason: "test")

        let released = await fixture.provider.releasedIdentifiers()
        let finalLease = await fixture.registry.lease(id: lease.id)
        XCTAssertEqual(released, [])
        XCTAssertEqual(finalLease?.state, .released)
    }

    func testOwnedTransitionReleasesOnlyTheExactIdentifier() async throws {
        let fixture = try makeFixture(states: [
            Self.firstUDID: .inactive,
            Self.secondUDID: .active
        ])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "owner", iteration: 1
        )
        let lease = try await fixture.registry.declareAcquisition(
            scopeID: scope.id,
            kind: .iosSimulatorBoot,
            identifier: Self.firstUDID
        )
        try await fixture.registry.markAcquired(leaseID: lease.id)
        await fixture.provider.setState(.active, for: Self.firstUDID)

        _ = await fixture.registry.releaseScope(id: scope.id, reason: "test")

        let released = await fixture.provider.releasedIdentifiers()
        let untouchedState = await fixture.provider.state(for: Self.secondUDID)
        XCTAssertEqual(released, [Self.firstUDID])
        XCTAssertEqual(untouchedState, .active)
    }

    func testSharedLeaseReleasesOnlyAfterLastScopeEnds() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let taskID = UUID()
        let first = try await fixture.registry.beginNodeScope(
            taskID: taskID, nodeID: "first", iteration: 1
        )
        let second = try await fixture.registry.beginNodeScope(
            taskID: taskID, nodeID: "second", iteration: 1
        )
        let lease = try await fixture.registry.declareAcquisition(
            scopeID: first.id,
            kind: .iosSimulatorBoot,
            identifier: Self.firstUDID
        )
        _ = try await fixture.registry.declareAcquisition(
            scopeID: second.id,
            kind: .iosSimulatorBoot,
            identifier: Self.firstUDID
        )
        try await fixture.registry.markAcquired(leaseID: lease.id)
        await fixture.provider.setState(.active, for: Self.firstUDID)

        _ = await fixture.registry.releaseScope(id: first.id, reason: "first done")
        let releasedAfterFirst = await fixture.provider.releasedIdentifiers()
        XCTAssertEqual(releasedAfterFirst, [])

        _ = await fixture.registry.releaseScope(id: second.id, reason: "second done")
        let releasedAfterSecond = await fixture.provider.releasedIdentifiers()
        XCTAssertEqual(releasedAfterSecond, [Self.firstUDID])
    }

    func testNewRegistryRecoversPersistedInterruptedAcquisition() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let taskID = UUID()
        let scope = try await fixture.registry.beginNodeScope(
            taskID: taskID, nodeID: "crashed", iteration: 3
        )
        _ = try await fixture.registry.declareAcquisition(
            scopeID: scope.id,
            kind: .iosSimulatorBoot,
            identifier: Self.firstUDID
        )
        await fixture.provider.setState(.active, for: Self.firstUDID)

        let restarted = GraphHostResourceLeaseRegistry(
            storageURL: fixture.storageURL,
            providers: [fixture.provider]
        )
        let report = await restarted.reconcileDanglingLeases()

        let released = await fixture.provider.releasedIdentifiers()
        XCTAssertEqual(released, [Self.firstUDID])
        XCTAssertEqual(report.releasedLeaseIDs.count, 1)
        XCTAssertTrue(report.failedTaskIDs.isEmpty)
    }

    func testReleaseFailureRemainsDurableAndCanBeRetried() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let taskID = UUID()
        let scope = try await fixture.registry.beginNodeScope(
            taskID: taskID, nodeID: "failure", iteration: 1
        )
        let lease = try await fixture.registry.declareAcquisition(
            scopeID: scope.id,
            kind: .iosSimulatorBoot,
            identifier: Self.firstUDID
        )
        try await fixture.registry.markAcquired(leaseID: lease.id)
        await fixture.provider.setState(.active, for: Self.firstUDID)
        await fixture.provider.setReleaseFailure(true)

        let failed = await fixture.registry.releaseScope(id: scope.id, reason: "test")
        let failedLease = await fixture.registry.lease(id: lease.id)
        XCTAssertEqual(failed.failedTaskIDs, [taskID])
        XCTAssertEqual(failedLease?.state, .releaseFailed)

        await fixture.provider.setReleaseFailure(false)
        let restarted = GraphHostResourceLeaseRegistry(
            storageURL: fixture.storageURL,
            providers: [fixture.provider]
        )
        let recovered = await restarted.reconcileDanglingLeases()
        let released = await fixture.provider.releasedIdentifiers()
        XCTAssertTrue(recovered.failedTaskIDs.isEmpty)
        XCTAssertEqual(released, [Self.firstUDID])
    }

    func testExecutionScopeReleasesWhenTurnIsCancelled() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let acquired = expectation(description: "lease acquired")
        let execution = GraphHostResourceExecutionScope(registry: fixture.registry)

        let turn = Task {
            try await execution.run(taskID: UUID(), nodeID: "cancelled", iteration: 1) { scope in
                let lease = try await fixture.registry.declareAcquisition(
                    scopeID: scope.id,
                    kind: .iosSimulatorBoot,
                    identifier: Self.firstUDID
                )
                try await fixture.registry.markAcquired(leaseID: lease.id)
                await fixture.provider.setState(.active, for: Self.firstUDID)
                acquired.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return true
            }
        }

        await fulfillment(of: [acquired], timeout: 2)
        turn.cancel()
        do {
            _ = try await turn.value
            XCTFail("The cancelled turn unexpectedly completed.")
        } catch is CancellationError {
            // Expected. The resource scope must still have been released.
        }
        let released = await fixture.provider.releasedIdentifiers()
        XCTAssertEqual(released, [Self.firstUDID])
    }

    func testExecutionScopeFailsClosedWhenOwnedResourceCannotBeReleased() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let taskID = UUID()
        let execution = GraphHostResourceExecutionScope(registry: fixture.registry)
        await fixture.provider.setReleaseFailure(true)

        do {
            _ = try await execution.run(taskID: taskID, nodeID: "failure", iteration: 1) { scope in
                let lease = try await fixture.registry.declareAcquisition(
                    scopeID: scope.id,
                    kind: .iosSimulatorBoot,
                    identifier: Self.firstUDID
                )
                try await fixture.registry.markAcquired(leaseID: lease.id)
                await fixture.provider.setState(.active, for: Self.firstUDID)
                return true
            }
            XCTFail("The node should not report success after cleanup failed.")
        } catch GraphHostResourceLeaseError.releaseFailed(let failedTaskID) {
            XCTAssertEqual(failedTaskID, taskID)
        }
    }

    func testSimulatorJSONParserUsesExactUDID() {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
          {"udid":"\(Self.firstUDID)","state":"Booted"},
          {"udid":"\(Self.secondUDID)","state":"Shutdown"}
        ]}}
        """

        XCTAssertEqual(
            IOSSimulatorHostResourceProvider.observedState(
                identifier: Self.firstUDID,
                json: json
            ),
            .active
        )
        XCTAssertEqual(
            IOSSimulatorHostResourceProvider.observedState(
                identifier: Self.secondUDID,
                json: json
            ),
            .inactive
        )
        XCTAssertEqual(
            IOSSimulatorHostResourceProvider.observedState(
                identifier: "00000000-0000-0000-0000-000000000003",
                json: json
            ),
            .missing
        )
    }

    func testSimulatorBootingStateIsStillTreatedAsActive() {
        let json = """
        {"devices":{"runtime":[
          {"udid":"\(Self.firstUDID)","state":"Booting"}
        ]}}
        """

        XCTAssertEqual(
            IOSSimulatorHostResourceProvider.observedState(
                identifier: Self.firstUDID,
                json: json
            ),
            .active
        )
    }

    func testBrokerRequestIsValidatedAndPersistedBeforeAcquisition() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "broker", iteration: 1
        )
        let requestID = UUID()
        let request = GraphHostResourceBrokerRequest(
            schemaVersion: 1,
            requestID: requestID,
            scopeID: scope.id,
            token: try XCTUnwrap(scope.brokerToken),
            operation: .declareIOSSimulatorBoot,
            identifier: Self.firstUDID.lowercased(),
            leaseID: nil
        )
        let directory = URL(
            fileURLWithPath: try XCTUnwrap(scope.brokerDirectory),
            isDirectory: true
        )
        try JSONEncoder().encode(request).write(
            to: directory.appendingPathComponent("\(requestID.uuidString).request.json"),
            options: .atomic
        )

        await fixture.registry.processBrokerRequests(scopeID: scope.id)

        let responseData = try Data(contentsOf: directory.appendingPathComponent(
            "\(requestID.uuidString).response.json"
        ))
        let response = try JSONDecoder().decode(
            GraphHostResourceBrokerResponse.self,
            from: responseData
        )
        let responseLeaseID = try XCTUnwrap(response.leaseID)
        let persistedLease = await fixture.registry.lease(id: responseLeaseID)
        let lease = try XCTUnwrap(persistedLease)
        XCTAssertTrue(response.success)
        XCTAssertTrue(response.performAcquisition)
        XCTAssertEqual(lease.identifier, Self.firstUDID)
        XCTAssertEqual(lease.state, .acquiring)
    }

    func testBrokerRejectsWrongScopeTokenWithoutCreatingLease() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "untrusted", iteration: 1
        )
        let requestID = UUID()
        let request = GraphHostResourceBrokerRequest(
            schemaVersion: 1,
            requestID: requestID,
            scopeID: scope.id,
            token: UUID().uuidString,
            operation: .declareIOSSimulatorBoot,
            identifier: Self.firstUDID,
            leaseID: nil
        )
        let directory = URL(
            fileURLWithPath: try XCTUnwrap(scope.brokerDirectory),
            isDirectory: true
        )
        try JSONEncoder().encode(request).write(
            to: directory.appendingPathComponent("\(requestID.uuidString).request.json"),
            options: .atomic
        )

        await fixture.registry.processBrokerRequests(scopeID: scope.id)

        let response = try JSONDecoder().decode(
            GraphHostResourceBrokerResponse.self,
            from: Data(contentsOf: directory.appendingPathComponent(
                "\(requestID.uuidString).response.json"
            ))
        )
        XCTAssertFalse(response.success)
        let activeLeases = await fixture.registry.activeLeases()
        XCTAssertTrue(activeLeases.isEmpty)
    }

    func testPackagedBrokerBootsExactUDIDThroughFakeXcrun() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .inactive])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "script", iteration: 1
        )
        let fakeXcrun = fixture.directory.appendingPathComponent("fake-xcrun")
        let invocationLog = fixture.directory.appendingPathComponent("xcrun.log")
        try Data("""
        #!/bin/zsh
        print -r -- "$*" > "$LOOPFORGE_FAKE_XCRUN_LOG"
        """.utf8).write(to: fakeXcrun, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeXcrun.path
        )
        let service = Task {
            await fixture.registry.serviceBrokerRequests(scopeID: scope.id)
        }
        let result = try await runBroker(
            arguments: ["ios-simulator", "boot", Self.firstUDID.lowercased()],
            scope: scope,
            extraEnvironment: [
                "LOOPFORGE_HOST_RESOURCE_BROKER_TEST_XCRUN": fakeXcrun.path,
                "LOOPFORGE_FAKE_XCRUN_LOG": invocationLog.path
            ]
        )
        service.cancel()
        await service.value

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: invocationLog, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "simctl boot \(Self.firstUDID)"
        )
        let leases = await fixture.registry.activeLeases()
        XCTAssertEqual(leases.count, 1)
        XCTAssertEqual(leases.first?.state, .active)
    }

    func testPackagedBrokerPreservesAlreadyBootedSimulator() async throws {
        let fixture = try makeFixture(states: [Self.firstUDID: .active])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "borrowed-script", iteration: 1
        )
        let fakeXcrun = fixture.directory.appendingPathComponent("must-not-run")
        try Data("#!/bin/zsh\nexit 99\n".utf8).write(to: fakeXcrun, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeXcrun.path
        )
        let service = Task {
            await fixture.registry.serviceBrokerRequests(scopeID: scope.id)
        }
        let result = try await runBroker(
            arguments: ["ios-simulator", "boot", Self.firstUDID],
            scope: scope,
            extraEnvironment: [
                "LOOPFORGE_HOST_RESOURCE_BROKER_TEST_XCRUN": fakeXcrun.path
            ]
        )
        service.cancel()
        await service.value

        XCTAssertEqual(result.status, 0, result.stderr)
        let activeLeases = await fixture.registry.activeLeases()
        let lease = try XCTUnwrap(activeLeases.first)
        XCTAssertEqual(lease.ownership, .borrowed)
        _ = await fixture.registry.releaseScope(id: scope.id, reason: "test")
        let released = await fixture.provider.releasedIdentifiers()
        XCTAssertTrue(released.isEmpty)
    }

    func testPackagedBrokerRejectsShutdownAll() async throws {
        let result = try await runProcess(
            executable: try brokerExecutable(),
            arguments: ["ios-simulator", "shutdown", "all"],
            environment: ProcessInfo.processInfo.environment
        )
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("only 'ios-simulator boot"))
    }

    func testPackageScriptInstallsBrokerInResourcesBin() throws {
        let packageScript = projectRoot.appendingPathComponent("Scripts/package_app.sh")
        let source = try String(contentsOf: packageScript, encoding: .utf8)
        XCTAssertTrue(source.contains("Resources/bin/loopforge-host-resource-broker"))
        XCTAssertTrue(source.contains("$RESOURCES_DIR/bin/loopforge-host-resource-broker"))
    }

    func testPackageScriptAtomicallyRefreshesChecksumsAfterBinaryArtifacts() throws {
        let packageScript = projectRoot.appendingPathComponent("Scripts/package_app.sh")
        let source = try String(contentsOf: packageScript, encoding: .utf8)
        let dmgCreation = try XCTUnwrap(source.range(of: "/usr/bin/hdiutil create"))
        let checksumGeneration = try XCTUnwrap(
            source.range(of: "/usr/bin/shasum -a 256 \"${checksum_artifacts[@]}\"")
        )

        XCTAssertLessThan(dmgCreation.lowerBound, checksumGeneration.lowerBound)
        XCTAssertTrue(source.contains("CHECKSUM_TMP"))
        XCTAssertTrue(source.contains("/bin/mv -f \"$CHECKSUM_TMP\" \"$CHECKSUM_PATH\""))
        XCTAssertTrue(source.contains("\"${ZIP_PATH:t}\" \"${DMG_PATH:t}\""))
    }

    func testExecutableStartupProbeRejectsCrashAndReapsLiveChild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeExecutableProbe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let crashing = directory.appendingPathComponent("crashing")
        let live = directory.appendingPathComponent("live")
        let pidPath = directory.appendingPathComponent("child.pid")
        try Data("#!/bin/zsh\nexit 7\n".utf8).write(to: crashing)
        try Data(
            """
            #!/bin/zsh
            print -r -- $$ > "$LOOPFORGE_PROBE_CHILD_PID_PATH"
            trap 'exit 0' TERM INT
            /bin/sleep 30
            """.utf8
        ).write(to: live)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: crashing.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: live.path
        )
        let probe = projectRoot.appendingPathComponent(
            "Scripts/probe_executable_startup.sh"
        )

        let rejected = try await runProcess(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [probe.path, crashing.path],
            environment: ProcessInfo.processInfo.environment
        )
        XCTAssertNotEqual(rejected.status, 0)
        XCTAssertTrue(rejected.stderr.contains("status 7"))

        var environment = ProcessInfo.processInfo.environment
        environment["LOOPFORGE_PROBE_CHILD_PID_PATH"] = pidPath.path
        let accepted = try await runProcess(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [probe.path, live.path],
            environment: environment
        )
        XCTAssertEqual(accepted.status, 0, accepted.stderr)
        let pidText = try String(contentsOf: pidPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let childPID = try XCTUnwrap(pid_t(pidText))
        XCTAssertEqual(kill(childPID, 0), -1, "the successful probe must reap its child")
        XCTAssertEqual(errno, ESRCH)
    }

    func testPackageSmokeLaunchesOnlyTheIsolatedInspectionProfile() throws {
        let smoke = projectRoot.appendingPathComponent("Scripts/smoke_test.sh")
        let source = try String(contentsOf: smoke, encoding: .utf8)

        XCTAssertTrue(source.contains("probe_executable_startup.sh"))
        XCTAssertTrue(source.contains("--isolated-inspection-profile"))
    }

    func testCodexEnvironmentExposesBrokerButNotLeaseRegistry() async throws {
        let fixture = try makeFixture(states: [:])
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let scope = try await fixture.registry.beginNodeScope(
            taskID: UUID(), nodeID: "environment", iteration: 7
        )
        let broker = URL(fileURLWithPath: "/tmp/fake-loopforge-broker")

        let environment = CodexRunner.hostResourceEnvironment(
            scope: scope,
            brokerURL: broker
        )

        XCTAssertEqual(environment["LOOPFORGE_HOST_RESOURCE_BROKER"], broker.path)
        XCTAssertEqual(
            environment["LOOPFORGE_HOST_RESOURCE_BROKER_DIRECTORY"],
            scope.brokerDirectory
        )
        XCTAssertEqual(
            environment["LOOPFORGE_HOST_RESOURCE_BROKER_TOKEN"],
            scope.brokerToken
        )
        XCTAssertNil(environment["LOOPFORGE_HOST_RESOURCE_REGISTRY"])
    }

    func testGraphOperationalPromptRequiresBrokerAndForbidsBroadShutdown() {
        let guidance = GraphNodeOperationalPolicy.longRunningProcessGuidance
        XCTAssertTrue(guidance.contains("$LOOPFORGE_HOST_RESOURCE_BROKER"))
        XCTAssertTrue(guidance.contains("never invoke `xcrun simctl boot` directly"))
        XCTAssertTrue(guidance.contains("simctl shutdown all"))
    }

    private func makeFixture(
        states: [String: GraphHostResourceObservedState]
    ) throws -> (
        directory: URL,
        storageURL: URL,
        provider: FakeHostResourceProvider,
        registry: GraphHostResourceLeaseRegistry
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeHostResourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storageURL = directory.appendingPathComponent("leases.json")
        let provider = FakeHostResourceProvider(states: states)
        let registry = GraphHostResourceLeaseRegistry(
            storageURL: storageURL,
            providers: [provider]
        )
        return (directory, storageURL, provider, registry)
    }

    private static let firstUDID = "00000000-0000-0000-0000-000000000001"
    private static let secondUDID = "00000000-0000-0000-0000-000000000002"

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func brokerExecutable() throws -> URL {
        let url = projectRoot.appendingPathComponent(
            "Resources/bin/loopforge-host-resource-broker"
        )
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
        return url
    }

    private func runBroker(
        arguments: [String],
        scope: GraphHostResourceScope,
        extraEnvironment: [String: String]
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        var environment = ProcessInfo.processInfo.environment
        environment["LOOPFORGE_HOST_RESOURCE_SCOPE_ID"] = scope.id.uuidString
        environment["LOOPFORGE_HOST_RESOURCE_BROKER_DIRECTORY"] = try XCTUnwrap(
            scope.brokerDirectory
        )
        environment["LOOPFORGE_HOST_RESOURCE_BROKER_TOKEN"] = try XCTUnwrap(
            scope.brokerToken
        )
        for (key, value) in extraEnvironment { environment[key] = value }
        return try await runProcess(
            executable: brokerExecutable(),
            arguments: arguments,
            environment: environment
        )
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        return (
            process.terminationStatus,
            String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }
}

private actor FakeHostResourceProvider: GraphHostResourceProvider {
    nonisolated let kind = GraphHostResourceKind.iosSimulatorBoot

    private var states: [String: GraphHostResourceObservedState]
    private var releaseCalls: [String] = []
    private var shouldFailRelease = false

    init(states: [String: GraphHostResourceObservedState]) {
        self.states = states
    }

    func observedState(identifier: String) async throws -> GraphHostResourceObservedState {
        states[identifier] ?? .missing
    }

    func release(identifier: String) async throws {
        if shouldFailRelease {
            throw FakeHostResourceError.releaseFailed
        }
        releaseCalls.append(identifier)
        states[identifier] = .inactive
    }

    func setState(_ state: GraphHostResourceObservedState, for identifier: String) {
        states[identifier] = state
    }

    func state(for identifier: String) -> GraphHostResourceObservedState {
        states[identifier] ?? .missing
    }

    func setReleaseFailure(_ shouldFail: Bool) {
        shouldFailRelease = shouldFail
    }

    func releasedIdentifiers() -> [String] {
        releaseCalls
    }
}

private enum FakeHostResourceError: Error {
    case releaseFailed
}
