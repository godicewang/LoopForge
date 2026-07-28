import Foundation
import XCTest
@testable import LoopForge

@MainActor
final class TaskStoreTests: XCTestCase {
    func testNewTaskDefaultsBothAgentsToLatestCodexAndFullAccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: TaskStore(storageURL: directory.appendingPathComponent("tasks.json")))

        XCTAssertEqual(model.draftControlProvider, .codex)
        XCTAssertEqual(model.draftSubProvider, .codex)
        XCTAssertEqual(model.draftControlModelReference, AppConstants.officialWorkerModel)
        XCTAssertEqual(model.draftSubModelReference, AppConstants.officialWorkerModel)
        XCTAssertEqual(model.draftControlAccessMode, .fullAccess)
        XCTAssertEqual(model.draftAccessMode, .fullAccess)

        model.draftControlProvider = .local
        model.draftControlAccessMode = .workspaceOnly
        model.resetDraft()
        XCTAssertEqual(model.draftControlProvider, .codex)
        XCTAssertEqual(model.draftControlAccessMode, .fullAccess)
    }

    func testParallelCandidateDraftDefaultsToThreeAndAgentSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(
            store: TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        )

        XCTAssertEqual(model.draftParallelCandidateCount, 3)
        XCTAssertEqual(model.draftParallelSelectionMode, .agent)
        model.setParallelCandidatesEnabled(true)
        model.setParallelCandidateCount(9)
        XCTAssertEqual(model.draftExecutionMode, .parallelCandidates)
        XCTAssertEqual(model.draftParallelCandidateCount, 8)
        model.resetDraft()
        XCTAssertEqual(model.draftExecutionMode, .singleLoop)
        XCTAssertEqual(model.draftParallelCandidateCount, 3)
        XCTAssertEqual(model.draftParallelSelectionMode, .agent)
    }

    func testTaskSummaryDescribesWorkInsteadOfReturningInitials() {
        XCTAssertEqual(
            TaskNamePolicy.descriptiveSummary(
                request: "Fix Unity package errors and verify the game scene.",
                fallback: "Game"
            ),
            "Fix Unity package errors verify game scene"
        )
        let chinese = TaskNamePolicy.descriptiveSummary(
            request: "修复当前Unity项目包错误，并验证场景可以运行。",
            fallback: "Game"
        )
        XCTAssertTrue(chinese.contains("Unity"))
        XCTAssertTrue(chinese.hasPrefix("修复"))

        XCTAssertEqual(
            TaskNamePolicy.descriptiveSummary(
                request: "请根据项目当前的设定和期许，将当前4人demo打磨到极致。完善NPC智能、物理引擎和高自由度游戏系统。",
                fallback: "Game"
            ),
            "打磨智能 NPC 与高自由度游戏系统"
        )
        XCTAssertEqual(
            TaskNamePolicy.descriptiveSummary(
                request: "完成一款中文的卡通风格iOS手游，拯救幸存者并不断建造领地。",
                fallback: "Game"
            ),
            "打造中文卡通生存建造 iOS 手游"
        )
    }

    func testCompletedTaskUnreadDotStateClearsOnlyAfterExplicitSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Done", request: "x", quality: .lightweight, category: .script,
            workspacePath: directory.path, targetSeconds: 1, accumulatedCodexSeconds: 1,
            model: .visualAuditor, status: .completed, stage: "Done", iteration: 1, threadID: nil,
            auditScore: 100, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: now, logs: []
        )
        store.add(task)
        XCTAssertNil(store.task(id: task.id)?.completionViewedAt)

        store.select(id: task.id)

        XCTAssertNotNil(store.task(id: task.id)?.completionViewedAt)
    }

    func testPausedTaskCanOpenDeletionConfirmation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Delete paused", request: "x", quality: .lightweight, category: .script,
            workspacePath: directory.path, targetSeconds: 3_600, accumulatedCodexSeconds: 10,
            model: .visualAuditor, status: .paused, stage: "Paused", iteration: 1, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        store.add(task)
        let model = AppModel(store: store)

        model.requestDeleteTask(task)

        XCTAssertEqual(model.pendingTaskDeletion?.id, task.id)
        XCTAssertNil(model.alertMessage)
    }

    func testTaskCannotBeDeletedWhilePauseIsStillFinishing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Still pausing", request: "x", quality: .lightweight, category: .script,
            workspacePath: directory.path, targetSeconds: 3_600, accumulatedCodexSeconds: 10,
            model: .visualAuditor, status: .pausing, stage: "Pausing", iteration: 1, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        store.add(task)
        let model = AppModel(store: store)

        model.requestDeleteTask(task)

        XCTAssertNil(model.pendingTaskDeletion)
        XCTAssertTrue(model.alertMessage?.contains("Pause is still finishing") == true)
    }

    func testInterruptedPauseAndEndRecoverToTheirRequestedFinalStates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: url)
        let now = Date()
        let pausing = LoopTask(
            id: UUID(), title: "Pausing", request: "x", quality: .lightweight, category: .script,
            workspacePath: directory.path, targetSeconds: 3_600, accumulatedCodexSeconds: 10,
            model: .visualAuditor, status: .pausing, stage: "Pausing", iteration: 1, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [], resumeOnNextLaunch: false
        )
        let stopping = LoopTask(
            id: UUID(), title: "Stopping", request: "y", quality: .lightweight, category: .script,
            workspacePath: directory.path, targetSeconds: 3_600, accumulatedCodexSeconds: 20,
            model: .visualAuditor, status: .stopping, stage: "Stopping", iteration: 2, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [], resumeOnNextLaunch: false
        )
        store.add(pausing)
        store.add(stopping)

        let restored = TaskStore(storageURL: url)
        let states = Dictionary(uniqueKeysWithValues: restored.tasks.map { ($0.id, $0.status) })

        XCTAssertEqual(states[pausing.id], .paused)
        XCTAssertEqual(states[stopping.id], .stopped)
        XCTAssertFalse(restored.tasks.contains { $0.resumeOnNextLaunch == true })
    }

    func testPersistsAndRecoversRunningTaskAsPaused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: url)
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Persist", request: "x", quality: .low, category: .script,
            workspacePath: directory.path, targetSeconds: 10, accumulatedCodexSeconds: 3,
            model: .ecoCoder, status: .running, stage: "run", iteration: 0, threadID: "thread",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        store.add(task)

        let restored = TaskStore(storageURL: url)
        XCTAssertEqual(restored.tasks.count, 1)
        XCTAssertEqual(restored.tasks[0].status, .paused)
        XCTAssertEqual(restored.tasks[0].threadID, "thread")
        XCTAssertEqual(restored.tasks[0].resumeOnNextLaunch, true)
        XCTAssertTrue(restored.tasks[0].stage.contains("Recovered"))
    }

    func testOnlyMostRecentInterruptedTaskOwnsAutomaticRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: url)
        let oldCheckpoint = Date(timeIntervalSince1970: 100)
        let newCheckpoint = Date(timeIntervalSince1970: 200)
        let older = LoopTask(
            id: UUID(), title: "Older", request: "x", quality: .low, category: .script,
            workspacePath: directory.appendingPathComponent("older").path,
            targetSeconds: 10, accumulatedCodexSeconds: 3,
            model: .ecoCoder, status: .running, stage: "run", iteration: 1, threadID: "old",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: oldCheckpoint, updatedAt: oldCheckpoint, completedAt: nil, logs: [],
            resumeOnNextLaunch: true, checkpointedAt: oldCheckpoint
        )
        let newer = LoopTask(
            id: UUID(), title: "Newer", request: "y", quality: .low, category: .script,
            workspacePath: directory.appendingPathComponent("newer").path,
            targetSeconds: 10, accumulatedCodexSeconds: 4,
            model: .ecoCoder, status: .auditing, stage: "audit", iteration: 2, threadID: "new",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: newCheckpoint, updatedAt: newCheckpoint, completedAt: nil, logs: [],
            resumeOnNextLaunch: true, checkpointedAt: newCheckpoint
        )
        store.add(older)
        store.add(newer)

        let restored = TaskStore(storageURL: url)
        let olderRestored = try XCTUnwrap(restored.task(id: older.id))
        let newerRestored = try XCTUnwrap(restored.task(id: newer.id))

        XCTAssertEqual(olderRestored.status, .paused)
        XCTAssertEqual(newerRestored.status, .paused)
        XCTAssertFalse(olderRestored.resumeOnNextLaunch == true)
        XCTAssertEqual(newerRestored.resumeOnNextLaunch, true)
        XCTAssertTrue(olderRestored.stage.contains("another task"))
        XCTAssertTrue(olderRestored.logs.contains { $0.message.contains("single automatic recovery slot") })
    }

    func testEditingRequestInvalidatesAStaleEstimate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let model = AppModel(store: store)
        model.draftProjectMode = .existing
        model.draftWorkspacePath = directory.path
        model.draftRequest = "Build a small CLI"
        model.calculateEstimate()
        XCTAssertNotNil(model.estimate)

        model.draftRequest = "Build a native app instead"
        XCTAssertNil(model.estimate)
    }

    func testDesktopAutomationRoutesBothRolesToStrongestOfficialCodex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(storageURL: directory.appendingPathComponent("tasks.json"))
        let model = AppModel(store: store)
        model.draftControlProvider = .local
        model.draftSubProvider = .local
        model.draftProjectMode = .existing
        model.draftWorkspacePath = directory.path
        model.draftRequest = "Use my already signed-in Google Chrome window to open 10 windows and generate 10 images in ChatGPT."

        model.calculateEstimate()

        let recommended = model.codexConnection.recommendedModel
        let strongest = CodexCatalog.strongestReasoning(for: recommended)
        XCTAssertEqual(model.estimate?.category, .desktopAutomation)
        XCTAssertEqual(model.draftControlProvider, .codex)
        XCTAssertEqual(model.draftSubProvider, .codex)
        XCTAssertEqual(model.draftControlModelReference, recommended.slug)
        XCTAssertEqual(model.draftSubModelReference, recommended.slug)
        XCTAssertEqual(model.draftControlReasoningEffort, strongest)
        XCTAssertEqual(model.draftReasoningEffort, strongest)
        XCTAssertEqual(model.draftControlAccessMode, .fullAccess)
        XCTAssertEqual(model.draftAccessMode, .fullAccess)
    }

    func testUserCanReduceRuntimeBelowModeDefaultAndRestoreRecommendation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: TaskStore(storageURL: directory.appendingPathComponent("tasks.json")))
        model.draftQuality = .high
        model.draftProjectMode = .existing
        model.draftWorkspacePath = directory.path
        model.draftRequest = "Build a polished macOS utility"
        model.calculateEstimate()

        XCTAssertGreaterThanOrEqual(model.draftTargetMinutes, QualityTier.high.defaultRuntimeMinutes)
        model.setDraftTargetHours(0.5)
        XCTAssertEqual(model.draftTargetMinutes, 30)
        model.adjustDraftTargetMinutes(by: -30)
        XCTAssertEqual(model.draftTargetMinutes, AppConstants.minimumCustomRuntimeMinutes)

        model.restoreRecommendedRuntime()
        XCTAssertGreaterThanOrEqual(model.draftTargetMinutes, QualityTier.high.defaultRuntimeMinutes)
    }

    func testReducedRuntimeSurvivesTaskStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Custom time", request: "Build a tool", quality: .high,
            category: .nativeApp, workspacePath: directory.path,
            targetSeconds: 30 * 60, accumulatedCodexSeconds: 0,
            model: .advancedVisualAuditor, status: .paused, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        TaskStore(storageURL: url).add(task)

        let restored = TaskStore(storageURL: url)

        XCTAssertEqual(restored.tasks[0].targetSeconds, 30 * 60)
    }

    func testObsoleteNonToolModelIsMigratedBeforeResume() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let oldModel = ModelProfile(
            id: "eco-coder", displayName: "Qwen2.5 Coder 7B", ollamaName: "qwen2.5-coder:7b",
            downloadSizeGB: 4.7, activeParameters: "7B", contextWindow: 32_768, reason: "historical"
        )
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Migrate", request: "Build a CLI", quality: .low, category: .library,
            workspacePath: directory.path, targetSeconds: 60, accumulatedCodexSeconds: 20,
            model: oldModel, status: .stopped, stage: "", iteration: 2, threadID: "old-thread",
            auditScore: 15, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        TaskStore(storageURL: url).add(task)

        let restored = TaskStore(storageURL: url)
        XCTAssertEqual(restored.tasks[0].model, .efficientAgent)
        XCTAssertNil(restored.tasks[0].threadID)
        XCTAssertTrue(restored.tasks[0].logs.contains { $0.message.contains("retired local-inference route") })
    }

    func testUserSelectedLocalModelSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Keep model", request: "Build a polished macOS UI", quality: .high,
            category: .nativeApp, workspacePath: directory.path,
            targetSeconds: 10 * 60 * 60, accumulatedCodexSeconds: 12,
            model: .visualAuditor, status: .paused, stage: "", iteration: 1, threadID: "thread",
            auditScore: 10, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [], visualAuditRequired: true
        )
        TaskStore(storageURL: url).add(task)
        let restored = TaskStore(storageURL: url)
        XCTAssertEqual(restored.tasks[0].model, .visualAuditor)
        XCTAssertEqual(restored.tasks[0].threadID, "thread")
    }

    func testCorruptNewestCheckpointFallsBackToAtomicBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: url)
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Recover me", request: "x", quality: .low, category: .script,
            workspacePath: directory.path, targetSeconds: 7_200, accumulatedCodexSeconds: 40,
            model: .ecoCoder, status: .paused, stage: "Paused", iteration: 1, threadID: "thread",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        store.add(task)
        store.update(id: task.id) { $0.accumulatedCodexSeconds = 55 }
        try Data("truncated".utf8).write(to: url, options: .atomic)

        let restored = TaskStore(storageURL: url)
        XCTAssertEqual(restored.tasks.first?.title, "Recover me")
        XCTAssertTrue(restored.tasks.first?.logs.contains { $0.message.contains("atomic backup") } == true)
    }

    func testLegacyQuotaFailureIsReclassifiedAsActionRequired() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.json")
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Quota", request: "Build a CLI", quality: .low, category: .library,
            workspacePath: directory.path, targetSeconds: 7_200, accumulatedCodexSeconds: 500,
            model: .efficientAgent, status: .failed, stage: "Three infrastructure failures", iteration: 1,
            threadID: "thread", auditScore: 20, auditSummary: "", lastAgentMessage: "",
            consecutiveFailures: 3, createdAt: now, updatedAt: now, completedAt: nil,
            logs: [TaskLogEntry(kind: .error, message: "You've hit your usage limit. Try again at Jul 29th, 2026 1:28 AM.")]
        )
        TaskStore(storageURL: url).add(task)

        let restored = TaskStore(storageURL: url)
        XCTAssertEqual(restored.tasks[0].status, .blocked)
        XCTAssertEqual(restored.tasks[0].externalBlockerKind, .usageLimit)
        XCTAssertTrue(restored.tasks[0].externalBlockerMessage?.contains("usage limit") == true)
        XCTAssertFalse(restored.tasks[0].externalBlockerMessage?.contains("infrastructure failures") == true)
        XCTAssertFalse(restored.tasks[0].resumeOnNextLaunch == true)
    }
}
