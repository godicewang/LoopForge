import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [LoopTask] = []
    @Published var selectedTaskID: UUID?

    /// Streaming Codex events can arrive several times per second. Publishing
    /// and atomically rewriting the complete task checkpoint for every event
    /// makes SwiftUI rebuild a large Graph/detail tree and repeatedly encodes
    /// megabytes of historical evidence on the main actor. Retain those events
    /// immediately in memory, expose them to reviewers through `task(id:)`,
    /// then publish/persist them as one bounded checkpoint.
    static let graphLogPublicationInterval: TimeInterval = 30
    private struct GraphLogKey: Hashable {
        let taskID: UUID
        let nodeID: String
    }
    private var pendingGraphLogs: [GraphLogKey: [TaskLogEntry]] = [:]
    private var pendingGraphLogFlushJobs: [UUID: Task<Void, Never>] = [:]

    let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    var selectedTask: LoopTask? {
        guard let selectedTaskID else { return tasks.first }
        return tasks.first { $0.id == selectedTaskID }
    }

    func add(_ task: LoopTask) {
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        save()
    }

    func task(id: UUID) -> LoopTask? {
        guard var task = tasks.first(where: { $0.id == id }),
              var graph = task.graphState else {
            return tasks.first { $0.id == id }
        }
        for (key, entries) in pendingGraphLogs where key.taskID == id {
            guard let index = graph.nodes.firstIndex(where: { $0.id == key.nodeID }) else {
                continue
            }
            Self.appendBounded(entries, to: &graph.nodes[index].logs)
        }
        task.graphState = graph
        return task
    }

    func select(id: UUID, markCompletionViewed: Bool = true) {
        selectedTaskID = id
        guard markCompletionViewed,
              let task = task(id: id),
              task.status == .completed,
              task.completionViewedAt == nil else { return }
        update(id: id) { $0.completionViewedAt = Date() }
    }

    func update(id: UUID, _ mutation: (inout LoopTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutation(&tasks[index])
        tasks[index].updatedAt = Date()
        save()
    }

    func appendLog(id: UUID, kind: LogKind, _ message: String) {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        update(id: id) { task in
            task.logs.append(TaskLogEntry(kind: kind, message: clean))
            if task.logs.count > AppConstants.maxStoredLogs {
                task.logs.removeFirst(task.logs.count - AppConstants.maxStoredLogs)
            }
        }
    }

    func updateGraphNode(
        taskID: UUID,
        nodeID: String,
        _ mutation: (inout GraphLoopNode) -> Void
    ) {
        let pending = takePendingGraphLogs(taskID: taskID, nodeID: nodeID)
        update(id: taskID) { task in
            guard var graph = task.graphState,
                  let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            Self.appendBounded(pending, to: &graph.nodes[index].logs)
            mutation(&graph.nodes[index])
            task.graphState = graph
            task.accumulatedCodexSeconds = graph.nodes.reduce(0) {
                $0 + $1.accumulatedActiveSeconds
            }
        }
    }

    func appendGraphNodeLog(
        taskID: UUID,
        nodeID: String,
        kind: LogKind,
        _ message: String
    ) {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if kind == .agent || kind == .command || kind == .system {
            let key = GraphLogKey(taskID: taskID, nodeID: nodeID)
            pendingGraphLogs[key, default: []].append(
                TaskLogEntry(kind: kind, message: clean)
            )
            scheduleGraphLogFlush(taskID: taskID)
            return
        }
        updateGraphNode(taskID: taskID, nodeID: nodeID) { node in
            node.logs.append(TaskLogEntry(kind: kind, message: clean))
            if node.logs.count > AppConstants.maxStoredLogs {
                node.logs.removeFirst(node.logs.count - AppConstants.maxStoredLogs)
            }
        }
    }

    func flushPendingGraphLogs(taskID: UUID? = nil) {
        let taskIDs = Set(pendingGraphLogs.keys.compactMap { key in
            taskID == nil || key.taskID == taskID ? key.taskID : nil
        })
        for id in taskIDs {
            let entriesByNode = pendingGraphLogs.reduce(into: [String: [TaskLogEntry]]()) {
                guard $1.key.taskID == id else { return }
                $0[$1.key.nodeID, default: []].append(contentsOf: $1.value)
            }
            guard !entriesByNode.isEmpty else { continue }
            pendingGraphLogs = pendingGraphLogs.filter { $0.key.taskID != id }
            pendingGraphLogFlushJobs[id]?.cancel()
            pendingGraphLogFlushJobs[id] = nil
            update(id: id) { task in
                guard var graph = task.graphState else { return }
                for (nodeID, entries) in entriesByNode {
                    guard let index = graph.nodes.firstIndex(where: { $0.id == nodeID }) else {
                        continue
                    }
                    Self.appendBounded(entries, to: &graph.nodes[index].logs)
                }
                task.graphState = graph
            }
        }
    }

    var pendingGraphLogCount: Int {
        pendingGraphLogs.values.reduce(0) { $0 + $1.count }
    }

    private func scheduleGraphLogFlush(taskID: UUID) {
        guard pendingGraphLogFlushJobs[taskID] == nil else { return }
        pendingGraphLogFlushJobs[taskID] = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(Self.graphLogPublicationInterval * 1_000_000_000)
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.flushPendingGraphLogs(taskID: taskID)
        }
    }

    private func takePendingGraphLogs(taskID: UUID, nodeID: String) -> [TaskLogEntry] {
        let key = GraphLogKey(taskID: taskID, nodeID: nodeID)
        let entries = pendingGraphLogs.removeValue(forKey: key) ?? []
        if !pendingGraphLogs.keys.contains(where: { $0.taskID == taskID }) {
            pendingGraphLogFlushJobs[taskID]?.cancel()
            pendingGraphLogFlushJobs[taskID] = nil
        }
        return entries
    }

    private static func appendBounded(
        _ entries: [TaskLogEntry],
        to logs: inout [TaskLogEntry]
    ) {
        guard !entries.isEmpty else { return }
        logs.append(contentsOf: entries)
        if logs.count > AppConstants.maxStoredLogs {
            logs.removeFirst(logs.count - AppConstants.maxStoredLogs)
        }
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id { selectedTaskID = tasks.first?.id }
        save()
    }

    private func load() {
        do {
            let persisted = try loadPersistedTasks()
            tasks = persisted.tasks
            var changed = persisted.usedBackup
            if persisted.usedBackup, !tasks.isEmpty {
                tasks[0].logs.append(TaskLogEntry(
                    kind: .warning,
                    message: "The newest checkpoint was unreadable, so LoopForge restored the previous atomic backup automatically."
                ))
            }
            for index in tasks.indices where tasks[index].status == .pausing {
                tasks[index].status = .paused
                tasks[index].resumeOnNextLaunch = false
                tasks[index].stage = "Paused · recovered after interruption with progress saved"
                tasks[index].logs.append(TaskLogEntry(kind: .warning, message: "LoopForge was interrupted while pausing. The task is now fully paused and safe to resume or delete."))
                changed = true
            }
            for index in tasks.indices where tasks[index].status == .stopping {
                tasks[index].status = .stopped
                tasks[index].resumeOnNextLaunch = false
                tasks[index].stage = "Stopped · recovered after interruption with progress saved"
                tasks[index].logs.append(TaskLogEntry(kind: .warning, message: "LoopForge was interrupted while ending this task. The task is now stopped and its project files remain preserved."))
                changed = true
            }
            for index in tasks.indices where tasks[index].status.isActive {
                tasks[index].status = .paused
                tasks[index].resumeOnNextLaunch = true
                tasks[index].stage = "Recovered the last checkpoint; waiting for permissions and Codex before continuing"
                tasks[index].logs.append(TaskLogEntry(kind: .warning, message: "Recovered an interrupted task from its last atomic checkpoint. Offline time was not added to active Sub Agent runtime; the agent session and workspace evidence will be resumed automatically."))
                if var graph = tasks[index].graphState {
                    for nodeIndex in graph.nodes.indices {
                        if graph.nodes[nodeIndex].status.isWorking {
                            graph.nodes[nodeIndex].status = .waiting
                            graph.nodes[nodeIndex].logs.append(TaskLogEntry(
                                kind: .warning,
                                message: "Recovered this node from its last durable checkpoint. Offline time was excluded."
                            ))
                        }
                        graph.nodes[nodeIndex].activeStartedAt = nil
                    }
                    tasks[index].graphState = graph
                }
                changed = true
            }
            let automaticResumeCandidates = tasks.indices.filter {
                tasks[$0].resumeOnNextLaunch == true && tasks[$0].canResume
            }
            if automaticResumeCandidates.count > 1 {
                let preferredIndex = automaticResumeCandidates.max { left, right in
                    let leftDate = tasks[left].checkpointedAt ?? tasks[left].updatedAt
                    let rightDate = tasks[right].checkpointedAt ?? tasks[right].updatedAt
                    if leftDate == rightDate {
                        return tasks[left].updatedAt < tasks[right].updatedAt
                    }
                    return leftDate < rightDate
                }
                for index in automaticResumeCandidates where index != preferredIndex {
                    tasks[index].resumeOnNextLaunch = false
                    tasks[index].stage = "Paused · another task owns automatic recovery"
                    tasks[index].logs.append(TaskLogEntry(
                        kind: .warning,
                        message: "Multiple interrupted tasks requested automatic recovery. LoopForge kept this task safely paused and reserved the single automatic recovery slot for the most recent durable checkpoint."
                    ))
                }
                changed = true
            }
            for index in tasks.indices where tasks[index].status == .failed {
                let failureEvidence = ([tasks[index].stage] + tasks[index].logs.suffix(40).map(\.message))
                    .joined(separator: "\n")
                guard let blocker = ExternalBlockerPolicy.classifyProcessFailure(failureEvidence) else { continue }
                tasks[index].status = .blocked
                tasks[index].stage = "\(blocker.kind.title) requires action before this loop can continue"
                tasks[index].externalBlockerKind = blocker.kind
                tasks[index].externalBlockerMessage = blocker.summary
                tasks[index].externalBlockerRetryAfter = blocker.retryAfter
                tasks[index].resumeOnNextLaunch = false
                tasks[index].logs.append(TaskLogEntry(
                    kind: .warning,
                    message: "A previous generic failure was reclassified from retained evidence as \(blocker.kind.title)."
                ))
                changed = true
            }
            for index in tasks.indices where tasks[index].status == .blocked {
                let retainedEvidence = tasks[index].logs.suffix(40).map(\.message).joined(separator: "\n")
                guard let blocker = ExternalBlockerPolicy.classifyProcessFailure(retainedEvidence) else { continue }
                if tasks[index].externalBlockerMessage != blocker.summary
                    || tasks[index].externalBlockerRetryAfter != blocker.retryAfter {
                    tasks[index].externalBlockerKind = blocker.kind
                    tasks[index].externalBlockerMessage = blocker.summary
                    tasks[index].externalBlockerRetryAfter = blocker.retryAfter
                    changed = true
                }
            }
            for index in tasks.indices {
                let existing = tasks[index].shortTitle?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isLegacyInitialism = existing.range(
                    of: "^[A-Z0-9]{2,5}$",
                    options: .regularExpression
                ) != nil
                if existing.isEmpty
                    || isLegacyInitialism
                    || (tasks[index].taskNamingVersion ?? 0) < TaskNamePolicy.currentVersion {
                    tasks[index].shortTitle = TaskNamePolicy.descriptiveSummary(
                        request: tasks[index].originalRequest ?? tasks[index].request,
                        fallback: tasks[index].title
                    )
                    tasks[index].taskNamingCompleted = false
                    tasks[index].taskNamingVersion = TaskNamePolicy.currentVersion
                    changed = true
                }
            }
            for index in tasks.indices where tasks[index].status != .completed
                && tasks[index].model.ollamaName == "qwen2.5-coder:7b" {
                tasks[index].model = .efficientAgent
                tasks[index].threadID = nil
                tasks[index].logs.append(TaskLogEntry(
                    kind: .warning,
                    message: "The retired local-inference route was replaced with the current local-supervisor / official-Codex architecture. A fresh official session will re-inspect the workspace."
                ))
                changed = true
            }
            for index in tasks.indices where tasks[index].status != .completed {
                let estimate = TaskEstimator().estimate(
                    request: tasks[index].request,
                    quality: tasks[index].quality,
                    workspacePath: tasks[index].workspacePath
                )
                if tasks[index].visualAuditRequired != estimate.visualAuditRequired {
                    changed = true
                }
                tasks[index].visualAuditRequired = estimate.visualAuditRequired
                // A user-selected local supervisor is durable. Re-estimation may
                // update whether screenshots are required, but never silently
                // replaces a model or discards an official Codex session.
            }
            selectedTaskID = tasks.first?.id
            if changed { save() }
        } catch {
            tasks = []
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let previous = try? Data(contentsOf: storageURL),
               (try? JSONDecoder.loopForge.decode([LoopTask].self, from: previous)) != nil {
                try previous.write(to: backupURL, options: .atomic)
            }
            let data = try JSONEncoder.loopForge.encode(tasks)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Persistence failure is surfaced on the next task mutation where logs remain in memory.
        }
    }

    private var backupURL: URL { storageURL.appendingPathExtension("backup") }

    private func loadPersistedTasks() throws -> (tasks: [LoopTask], usedBackup: Bool) {
        do {
            let data = try Data(contentsOf: storageURL)
            return (try JSONDecoder.loopForge.decode([LoopTask].self, from: data), false)
        } catch {
            let backup = try Data(contentsOf: backupURL)
            return (try JSONDecoder.loopForge.decode([LoopTask].self, from: backup), true)
        }
    }

    nonisolated static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppConstants.appName, isDirectory: true)
    }

    nonisolated static func defaultStorageURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("tasks.json")
    }
}

extension JSONEncoder {
    static var loopForge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var loopForge: JSONDecoder {
        let decoder = JSONDecoder()
        // Watcher pipelines are intentionally language-agnostic. Python's
        // `datetime.isoformat()` commonly emits six fractional digits, while
        // Foundation's built-in `.iso8601` strategy has accepted that format
        // inconsistently across macOS releases. Decode both fractional and
        // whole-second RFC 3339 timestamps so a pipeline behaves identically
        // on the user's Mac and on a clean release runner.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            if let date = fractional.date(from: value) {
                return date
            }

            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            if let date = wholeSeconds.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an RFC 3339 / ISO-8601 timestamp."
            )
        }
        return decoder
    }
}
