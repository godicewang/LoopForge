import AppKit
import Foundation
import XCTest
@testable import LoopForge

@MainActor
final class LoopControllerLifecycleTests: XCTestCase {
    func testClosingTheLastWindowTerminatesInsteadOfLeavingHiddenWorkRunning() {
        let delegate = LoopForgeApplicationDelegate()
        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func testPauseReportsPausingUntilTheWorkerSlotIsReleased() async throws {
        let fixture = try makeFixture(status: .paused)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = LoopController(
            store: fixture.store,
            hostResources: isolatedHostResources(in: fixture.directory)
        )
        XCTAssertFalse(controller.isClockTickerActive)

        controller.startRetiredExecutionForTesting(taskID: fixture.task.id)
        XCTAssertEqual(controller.runningTaskID, fixture.task.id)
        XCTAssertTrue(controller.isClockTickerActive)

        controller.pause(taskID: fixture.task.id)

        XCTAssertEqual(fixture.store.task(id: fixture.task.id)?.status, .pausing)
        XCTAssertEqual(controller.runningTaskID, fixture.task.id)
        XCTAssertFalse(controller.isClockTickerActive)

        // A final-audit completion/retry can race with cancellation and write
        // an ordinary running state after `.pausing`. The controller's durable
        // user intent must still win once the process tree has exited.
        fixture.store.update(id: fixture.task.id) {
            $0.status = .auditing
            $0.stage = "Concurrent final audit retry"
            $0.resumeOnNextLaunch = true
        }

        await waitForControllerToFinish(controller)

        XCTAssertNil(controller.runningTaskID)
        XCTAssertEqual(fixture.store.task(id: fixture.task.id)?.status, .paused)
        XCTAssertTrue(fixture.store.task(id: fixture.task.id)?.stage.contains("no agent process is running") == true)
    }

    func testClockTickerUsesLowFrequencyActiveOnlyCadence() {
        XCTAssertGreaterThanOrEqual(LoopController.clockRefreshInterval, 5)
        XCTAssertGreaterThanOrEqual(LoopController.clockPublicationInterval, 30)
        XCTAssertGreaterThan(
            LoopController.clockPublicationInterval,
            LoopController.clockRefreshInterval
        )
    }

    func testEveryRetiredModeCannotCrossControllerStartBoundary() throws {
        for mode in LoopExecutionMode.allCases {
            let fixture = try makeFixture(status: .paused)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            fixture.store.update(id: fixture.task.id) {
                $0.executionMode = mode
                $0.resumeOnNextLaunch = true
            }
            let sentinel = fixture.directory.appendingPathComponent("workspace-sentinel.txt")
            try Data("unchanged".utf8).write(to: sentinel)
            let before = try Data(contentsOf: sentinel)
            let controller = LoopController(
                store: fixture.store,
                hostResources: isolatedHostResources(in: fixture.directory)
            )

            controller.start(taskID: fixture.task.id)

            let blocked = try XCTUnwrap(fixture.store.task(id: fixture.task.id))
            XCTAssertNil(controller.runningTaskID, mode.title)
            XCTAssertFalse(controller.isClockTickerActive, mode.title)
            XCTAssertEqual(blocked.status, .blocked, mode.title)
            XCTAssertEqual(
                blocked.stage,
                LegacyTaskExecutionRetirementPolicy.stage(for: mode),
                mode.title
            )
            XCTAssertEqual(blocked.resumeOnNextLaunch, false, mode.title)
            XCTAssertEqual(try Data(contentsOf: sentinel), before, mode.title)
            XCTAssertFalse(
                blocked.logs.contains(where: {
                    $0.message.contains("Architecture:")
                        || $0.message.contains("selected Sub Agent runtime")
                }),
                mode.title
            )

            let logCount = blocked.logs.count
            controller.start(taskID: fixture.task.id)
            XCTAssertEqual(
                fixture.store.task(id: fixture.task.id)?.logs.count,
                logCount,
                mode.title
            )
        }
    }

    func testRetiredParallelCandidateSelectionCannotCrossControllerBoundary() throws {
        let fixture = try makeFixture(status: .awaitingSelection)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.store.update(id: fixture.task.id) {
            $0.executionMode = .parallelCandidates
            $0.resumeOnNextLaunch = true
        }
        let sentinel = fixture.directory.appendingPathComponent("workspace-sentinel.txt")
        try Data("unchanged".utf8).write(to: sentinel)
        let before = try Data(contentsOf: sentinel)
        let controller = LoopController(
            store: fixture.store,
            hostResources: isolatedHostResources(in: fixture.directory)
        )

        controller.chooseParallelCandidate(
            taskID: fixture.task.id,
            candidateID: "candidate-1"
        )

        let blocked = try XCTUnwrap(fixture.store.task(id: fixture.task.id))
        XCTAssertNil(controller.runningTaskID)
        XCTAssertFalse(controller.isClockTickerActive)
        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertEqual(
            blocked.stage,
            LegacyTaskExecutionRetirementPolicy.stage(for: .parallelCandidates)
        )
        XCTAssertEqual(blocked.resumeOnNextLaunch, false)
        XCTAssertEqual(try Data(contentsOf: sentinel), before)
        XCTAssertTrue(
            blocked.logs.contains(where: {
                $0.message.contains("parallel candidate selection")
                    && $0.message.contains("no timer, agent, process, mutation")
            })
        )
    }

    func testNewKernelRecoveryFailureBlocksBeforeAgentOrLegacyGraphWork() async throws {
        let fixture = try makeFixture(status: .paused)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let recoveryTask = Task {
            WorkspaceMutationRecoveryStartupReport(
                ownershipAcquired: false,
                registeredRunCount: 0,
                runReports: [],
                startupFailure: .recoveryFailed
            )
        }
        let controller = LoopController(
            store: fixture.store,
            hostResources: isolatedHostResources(in: fixture.directory),
            workspaceMutationRecoveryTask: recoveryTask
        )

        controller.startRetiredExecutionForTesting(taskID: fixture.task.id)
        await waitForControllerToFinish(controller)

        let blocked = try XCTUnwrap(fixture.store.task(id: fixture.task.id))
        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertEqual(blocked.stage, "New-kernel workspace recovery needs attention")
        XCTAssertEqual(blocked.resumeOnNextLaunch, false)
        XCTAssertTrue(
            blocked.logs.contains(where: {
                $0.kind == .error &&
                    $0.message.contains("before any Codex or legacy Graph work began")
            })
        )
        XCTAssertFalse(
            blocked.logs.contains(where: {
                $0.message.contains("Architecture:") ||
                    $0.message.contains("selected Sub Agent runtime")
            })
        )
    }

    func testEndReportsStoppingUntilTheWorkerSlotIsReleased() async throws {
        let fixture = try makeFixture(status: .paused)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = LoopController(
            store: fixture.store,
            hostResources: isolatedHostResources(in: fixture.directory)
        )

        controller.startRetiredExecutionForTesting(taskID: fixture.task.id)
        controller.stop(taskID: fixture.task.id)

        XCTAssertEqual(fixture.store.task(id: fixture.task.id)?.status, .stopping)
        XCTAssertEqual(controller.runningTaskID, fixture.task.id)

        await waitForControllerToFinish(controller)

        XCTAssertNil(controller.runningTaskID)
        XCTAssertEqual(fixture.store.task(id: fixture.task.id)?.status, .stopped)
        XCTAssertTrue(fixture.store.task(id: fixture.task.id)?.stage.contains("project files are saved") == true)
    }

    private func waitForControllerToFinish(_ controller: LoopController) async {
        for _ in 0..<200 where controller.runningTaskID != nil {
            await Task.yield()
        }
    }

    private func isolatedHostResources(in directory: URL) -> GraphHostResourceLeaseRegistry {
        GraphHostResourceLeaseRegistry(
            storageURL: directory.appendingPathComponent("host-resource-test-leases.json"),
            providers: []
        )
    }

    private func makeFixture(status: LoopTaskStatus) throws -> (
        directory: URL,
        store: TaskStore,
        task: LoopTask
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Lifecycle", request: "Build a small local fixture",
            quality: .lightweight, category: .script, workspacePath: directory.path,
            targetSeconds: 3_600, accumulatedCodexSeconds: 12,
            model: .visualAuditor, status: status, stage: "Ready", iteration: 1, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        task.controlAgent = .local(profile: .visualAuditor, access: .workspaceOnly)
        task.subAgent = .local(profile: .efficientAgent, access: .workspaceOnly)
        store.add(task)
        return (directory, store, task)
    }
}
