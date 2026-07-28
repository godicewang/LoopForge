import Foundation
import XCTest
@testable import LoopForge

@MainActor
final class LoopControllerLifecycleTests: XCTestCase {
    func testPauseReportsPausingUntilTheWorkerSlotIsReleased() async throws {
        let fixture = try makeFixture(status: .paused)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = LoopController(store: fixture.store)

        controller.start(taskID: fixture.task.id)
        XCTAssertEqual(controller.runningTaskID, fixture.task.id)

        controller.pause(taskID: fixture.task.id)

        XCTAssertEqual(fixture.store.task(id: fixture.task.id)?.status, .pausing)
        XCTAssertEqual(controller.runningTaskID, fixture.task.id)

        await waitForControllerToFinish(controller)

        XCTAssertNil(controller.runningTaskID)
        XCTAssertEqual(fixture.store.task(id: fixture.task.id)?.status, .paused)
        XCTAssertTrue(fixture.store.task(id: fixture.task.id)?.stage.contains("no agent process is running") == true)
    }

    func testEndReportsStoppingUntilTheWorkerSlotIsReleased() async throws {
        let fixture = try makeFixture(status: .paused)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = LoopController(store: fixture.store)

        controller.start(taskID: fixture.task.id)
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
