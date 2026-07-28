import SwiftUI

@MainActor
final class LoopForgeApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var controller: LoopController?
    static weak var watcherController: WatcherController?

    // Closing a window must not silently stop a multi-hour worker. Quitting from
    // the app menu still reaches applicationWillTerminate and checkpoints the
    // active-runtime ledger before the child process is cancelled.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.controller?.shutdown()
        Self.watcherController?.shutdown()
    }
}

@main
@MainActor
struct LoopForgeApp: App {
    @NSApplicationDelegateAdaptor(LoopForgeApplicationDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel

    init() {
        let model = AppModel()
        _appModel = StateObject(wrappedValue: model)
        LoopForgeApplicationDelegate.controller = model.controller
        LoopForgeApplicationDelegate.watcherController = model.watcherController
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 1_060, minHeight: 700)
        }
        .defaultSize(width: 1_240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(appModel.selectedModule == .autoLoop ? "New Task" : "New Watcher") {
                    appModel.startNewTaskFlow()
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Codex") {
                Button("Connection Status") { appModel.codexConnection.presentStatus() }
                Button("Refresh Models") { appModel.codexConnection.reconnect() }
                Divider()
                Button("Review Automation Permissions") {
                    appModel.permissionCenter.showOnboardingAgain()
                }
            }
        }
    }
}
