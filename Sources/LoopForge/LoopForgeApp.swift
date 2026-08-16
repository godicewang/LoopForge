import SwiftUI

@MainActor
final class LoopForgeApplicationDelegate: NSObject, NSApplicationDelegate {
    static weak var controller: LoopController?
    static weak var watcherController: WatcherController?
    static weak var appModel: AppModel?
    private var terminationPending = false

    // A closed last window must behave like an exit. Continuing an autonomous
    // worker invisibly after the user closes LoopForge is surprising and can
    // leave the Mac hot with no visible way to pause it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        let watcherWasActive = !(Self.watcherController?.runningWatcherIDs.isEmpty ?? true)
        let loopWasActive = Self.controller?.runningTaskID != nil
        terminationPending = true
        Task { @MainActor in
            let kernelReadyToTerminate = await Self.appModel?
                .prepareKernelSessionsForApplicationTermination() ?? true
            guard kernelReadyToTerminate else {
                terminationPending = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            Self.watcherController?.shutdown()
            if let controller = Self.controller {
                await controller.prepareForApplicationTermination(
                    timeout: watcherWasActive || loopWasActive ? 4 : 1,
                    forceProcessCleanupGrace: watcherWasActive
                )
            } else {
                if watcherWasActive {
                    try? await Task.sleep(nanoseconds: 3_250_000_000)
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

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
        let kernelRuntime = KernelProductionRuntime.startDefault()
        let model = AppModel(
            workspaceMutationRecoveryTask: kernelRuntime.recoveryTask,
            kernelRunEnrollmentCoordinator: kernelRuntime.enrollmentCoordinator,
            kernelExecutionCoordinator: kernelRuntime.executionCoordinator
        )
        _appModel = StateObject(wrappedValue: model)
        LoopForgeApplicationDelegate.controller = model.controller
        LoopForgeApplicationDelegate.watcherController = model.watcherController
        LoopForgeApplicationDelegate.appModel = model
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
