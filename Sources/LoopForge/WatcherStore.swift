import Combine
import Foundation

@MainActor
final class WatcherStore: ObservableObject {
    @Published private(set) var watchers: [ContinuumWatcher] = []
    @Published var selectedWatcherID: UUID?

    let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? TaskStore.applicationSupportDirectory().appendingPathComponent("watchers.json")
        load()
    }

    var selectedWatcher: ContinuumWatcher? {
        guard let selectedWatcherID else { return watchers.first }
        return watchers.first { $0.id == selectedWatcherID }
    }

    func watcher(id: UUID) -> ContinuumWatcher? {
        watchers.first { $0.id == id }
    }

    func add(_ watcher: ContinuumWatcher) {
        watchers.insert(watcher, at: 0)
        selectedWatcherID = watcher.id
        save()
    }

    func update(id: UUID, _ mutation: (inout ContinuumWatcher) -> Void) {
        guard let index = watchers.firstIndex(where: { $0.id == id }) else { return }
        mutation(&watchers[index])
        watchers[index].updatedAt = Date()
        save()
    }

    func appendEvent(id: UUID, _ event: WatcherEvent) {
        update(id: id) { watcher in
            watcher.events.append(event)
            if watcher.events.count > AppConstants.maxStoredLogs {
                watcher.events.removeFirst(watcher.events.count - AppConstants.maxStoredLogs)
            }
        }
    }

    func select(id: UUID) {
        selectedWatcherID = id
    }

    func delete(id: UUID) {
        watchers.removeAll { $0.id == id }
        if selectedWatcherID == id { selectedWatcherID = watchers.first?.id }
        save()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let previous = try? Data(contentsOf: storageURL),
               (try? JSONDecoder.loopForge.decode([ContinuumWatcher].self, from: previous)) != nil {
                try previous.write(to: backupURL, options: .atomic)
            }
            try JSONEncoder.loopForge.encode(watchers).write(to: storageURL, options: .atomic)
        } catch {
            // The next mutation retries the atomic checkpoint.
        }
    }

    private var backupURL: URL { storageURL.appendingPathExtension("backup") }

    private func load() {
        let primary = try? Data(contentsOf: storageURL)
        let backup = try? Data(contentsOf: backupURL)
        let decodedPrimary = primary.flatMap {
            try? JSONDecoder.loopForge.decode([ContinuumWatcher].self, from: $0)
        }
        let decodedBackup = backup.flatMap {
            try? JSONDecoder.loopForge.decode([ContinuumWatcher].self, from: $0)
        }
        watchers = decodedPrimary ?? decodedBackup ?? []
        selectedWatcherID = watchers.first?.id

        var changed = decodedPrimary == nil && decodedBackup != nil
        for index in watchers.indices where watchers[index].status == .runningPipeline
            || watchers[index].status == .reviewing
            || watchers[index].status == .preparing {
            watchers[index].status = watchers[index].pipeline == nil ? .needsAttention : .active
            watchers[index].resumeOnNextLaunch = watchers[index].pipeline != nil
            watchers[index].events.append(WatcherEvent(
                kind: .lifecycle,
                severity: watchers[index].pipeline == nil ? .warning : .info,
                message: watchers[index].pipeline == nil
                    ? "LoopForge recovered an interrupted pipeline build. Start it again to rebuild safely."
                    : "Recovered the last durable checkpoint. Offline time was not treated as pipeline work."
            ))
            changed = true
        }
        if changed { save() }
    }
}
