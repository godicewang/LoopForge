import SwiftUI

private enum ForgeStyle {
    static let accent = Color.accentColor
    static let panel = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let hairline = Color.primary.opacity(0.09)
    static let warning = Color.orange
}

private struct CircularWorkingIndicator: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(color.opacity(0.78), style: StrokeStyle(lineWidth: max(1.5, size * 0.14), lineCap: .round))
            Circle()
                .fill(color.opacity(0.9))
                .frame(
                    width: min(5, max(2.5, size * 0.16)),
                    height: min(5, max(2.5, size * 0.16))
                )
                .offset(y: -size / 2)
        }
        .rotationEffect(.degrees(28))
        .frame(width: size, height: size)
    }
}

private struct RuntimeClock: View {
    let progress: Double
    let remainingSeconds: TimeInterval
    let isWorking: Bool
    let targetReached: Bool
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.012, min(1, progress)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                Image(systemName: targetReached ? "checkmark" : "clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                Text(targetReached ? "100%+" : remainingSeconds.compactDuration)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(targetReached && isWorking ? "Working" : (targetReached ? "Reached" : "Remaining"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            if targetReached && isWorking {
                CircularWorkingIndicator(color: color, size: 88)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(targetReached ? "Runtime target reached" : "\(remainingSeconds.compactDuration) remaining")
        .accessibilityValue(isWorking ? "Task is working" : "Task is not running")
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if !model.permissionCenter.isReady {
                PermissionOnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else if model.codexConnection.shouldBlockInterface {
                CodexConnectionView()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                WorkspaceShell(store: model.store, controller: model.controller)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.permissionCenter.isReady)
        .animation(.easeInOut(duration: 0.28), value: model.codexConnection.shouldBlockInterface)
        .task { model.beginStartup() }
        .onChange(of: model.permissionCenter.isReady) { _, ready in
            if ready { model.permissionStateChanged() }
        }
        .onChange(of: model.codexConnection.phase) { _, phase in
            if phase == .ready { model.connectionStateChanged() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissionStateChanged()
        }
        .alert("LoopForge", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: Binding(
                get: { model.pendingTaskDeletion != nil },
                set: { if !$0 { model.pendingTaskDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let task = model.pendingTaskDeletion {
                Button("Delete Task Record", role: .destructive) {
                    model.deleteTaskRecord(task)
                }
                Button("Delete Record and Move Project to Trash", role: .destructive) {
                    model.deleteTaskAndMoveWorkspaceToTrash(task)
                }
            }
            Button("Cancel", role: .cancel) { model.pendingTaskDeletion = nil }
        } message: {
            Text("The project folder is kept by default. Choose the second option only if you also want to move it to Trash.")
        }
        .confirmationDialog(
            model.draftExecutionMode == .autoGraph
                ? "Refine this prompt before contract review?"
                : "Refine this prompt before starting?",
            isPresented: $model.showingPromptOptimizationOffer,
            titleVisibility: .visible
        ) {
            Button("Generate 3 Options") { model.beginPromptOptimization() }
            Button("Use Original Prompt") { model.startWithOriginalPrompt() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("LoopForge can clarify acceptance evidence without changing your intent. You will choose among three options or keep the original.")
        }
        .sheet(isPresented: $model.showingModelManager, onDismiss: {
            model.modelManagerRequestedRole = nil
        }) {
            ModelManagerView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showingPromptOptimization) {
            PromptOptimizationView()
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: {
                model.pendingNativeContractConfirmation != nil
                    || model.pendingNativeDesignBaselineConfirmation != nil
            },
            set: {
                if !$0 { model.cancelPendingNativeAuthorityConfirmation() }
            }
        )) {
            if model.pendingNativeDesignBaselineConfirmation != nil {
                NativeDesignBaselineConfirmationView()
                    .environmentObject(model)
            } else {
                NativeAutoGraphContractConfirmationView()
                    .environmentObject(model)
            }
        }
    }
}

private struct PermissionOnboardingView: View {
    @EnvironmentObject private var model: AppModel
    private var center: PermissionCenter { model.permissionCenter }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 28) {
                LoopForgeMark(size: 72)
                VStack(spacing: 7) {
                    Text("Ready the workspace")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Grant these once, before a long loop begins.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    permissionRow(
                        "Screen Recording", symbol: "rectangle.inset.filled.and.person.filled",
                        complete: center.screenCaptureGranted,
                        actionTitle: center.screenCaptureRequested ? "Settings" : "Allow",
                        action: center.screenCaptureRequested ? center.openScreenRecordingSettings : center.requestScreenCapture
                    )
                    Divider().padding(.leading, 54)
                    permissionRow(
                        "Accessibility", symbol: "accessibility",
                        complete: center.accessibilityGranted,
                        actionTitle: center.accessibilityRequested ? "Settings" : "Allow",
                        action: center.accessibilityRequested ? center.openAccessibilitySettings : center.requestAccessibility
                    )
                    Divider().padding(.leading, 54)
                    HStack(spacing: 14) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App Management")
                            Text("Needed when Codex updates app bundles")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if center.appManagementConfirmed {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Open Settings") { center.openAppManagementSettings() }
                            Button("Enabled") { center.confirmAppManagement() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal, 16).frame(height: 62)
                }
                .frame(width: 510)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(ForgeStyle.hairline))

                if center.screenCaptureNeedsRestart {
                    HStack {
                        Button("Continue") { center.continueIntoApp(); model.permissionStateChanged() }
                            .buttonStyle(.bordered)
                        Button("Restart LoopForge") { center.restartApplication() }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                } else if center.isRequesting {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(spacing: 10) {
                        HStack {
                            Button("Check Again") { center.refresh(); model.permissionStateChanged() }
                                .buttonStyle(.bordered)
                            Button("Continue") { center.continueIntoApp(); model.permissionStateChanged() }
                                .buttonStyle(.borderedProminent)
                        }
                        .controlSize(.large)
                        if !center.allCapabilitiesGranted {
                            Text("You can continue now. LoopForge will keep checking these capabilities before visual automation.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(48)
        }
        .accessibilityIdentifier("permission-onboarding-view")
    }

    private func permissionRow(
        _ title: String,
        symbol: String,
        complete: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary).frame(width: 24)
            Text(title)
            Spacer()
            if complete {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
    }
}

private struct CodexConnectionView: View {
    @EnvironmentObject private var model: AppModel
    private var connection: CodexConnectionManager { model.codexConnection }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 28) {
                LoopForgeMark(size: 72)

                VStack(spacing: 7) {
                    Text(connection.phase.title)
                        .font(.system(size: 30, weight: .semibold))
                    Text(connection.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                VStack(spacing: 0) {
                    connectionStep("Codex CLI", symbol: "shippingbox", complete: !connection.executablePath.isEmpty, active: connection.phase == .locating)
                    Divider().padding(.leading, 50)
                    connectionStep("Version", symbol: "arrow.triangle.2.circlepath", complete: !connection.version.isEmpty, active: connection.phase == .checkingVersion)
                    Divider().padding(.leading, 50)
                    connectionStep("ChatGPT sign-in", symbol: "person.crop.circle", complete: connection.authentication.lowercased().contains("logged in"), active: connection.phase == .checkingAuthentication || connection.phase == .signingIn)
                    Divider().padding(.leading, 50)
                    connectionStep("Models", symbol: "slider.horizontal.3", complete: connection.phase == .ready, active: connection.phase == .loadingModels)
                }
                .frame(width: 430)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(ForgeStyle.hairline))

                if connection.phase == .failed {
                    failureActions
                } else if connection.phase == .ready {
                    VStack(spacing: 12) {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Button("Continue") { connection.dismissReadyState() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(48)
        }
        .accessibilityIdentifier("codex-connection-view")
    }

    private var failureActions: some View {
        VStack(spacing: 14) {
            Text(connection.errorMessage ?? "Codex could not connect.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            HStack(spacing: 10) {
                Button("Connect with ChatGPT") { connection.signIn() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("codex-signin-button")
                Button("Try Again") { connection.reconnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Button("Continue with Local or API Models") { connection.continueWithoutCodex() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

            DisclosureGroup("Manual setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Run Codex sign-in once, then return to LoopForge.")
                        .foregroundStyle(.secondary)
                    Button("Copy command and open Terminal") { connection.copyManualCommand() }
                }
                .padding(.top, 8)
            }
            .font(.callout)
            .frame(width: 430)
        }
    }

    private func connectionStep(_ title: String, symbol: String, complete: Bool, active: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(active ? ForgeStyle.accent : .secondary)
                .frame(width: 22)
            Text(title).font(.body)
            Spacer()
            if complete {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if active {
                ProgressView().controlSize(.small)
            } else {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1).frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

struct LoopForgeMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(Color.accentColor)
            Image(systemName: "infinity")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.accentColor.opacity(0.18), radius: size * 0.18, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

private struct WorkspaceShell: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: LoopController

    var body: some View {
        NavigationSplitView {
            Group {
                if model.selectedModule == .autoLoop {
                    SidebarView(store: store, controller: controller)
                } else {
                    ContinuumSidebarView(
                        store: model.watcherStore,
                        controller: model.watcherController
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if model.selectedModule != .autoLoop
                    || model.showingNewTask
                    || store.selectedTask == nil {
                    ModuleContextLabel(
                        module: model.selectedModule,
                        kernelRuns: model.kernelRunProjections,
                        recoveryRuns: model.kernelRecoveryRunReports,
                        executionReadiness: model.kernelExecutionReadinessByRunID,
                        providerReadiness:
                            model.kernelProviderInvocationReadinessByRunID
                    )
                }

                Group {
                    if model.selectedModule == .autoLoop {
                        if model.showingNewTask || store.selectedTask == nil {
                            NewTaskView()
                        } else if let task = store.selectedTask {
                            TaskDetailView(taskID: task.id, store: store, controller: controller).id(task.id)
                        }
                    } else {
                        if model.showingNewWatcher || model.watcherStore.selectedWatcher == nil {
                            ContinuumNewWatcherView()
                        } else if let watcher = model.watcherStore.selectedWatcher {
                            ContinuumWatcherDetailView(
                                watcherID: watcher.id,
                                store: model.watcherStore,
                                controller: model.watcherController
                            )
                            .id(watcher.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $model.showingWatcherGuide) {
            WatcherGuideView(startIndex: model.watcherGuideStartIndex)
                .environmentObject(model)
        }
    }
}

private struct ModuleContextLabel: View {
    let module: LoopForgeModule
    let kernelRuns: [KernelRunProjection]
    let recoveryRuns: [WorkspaceMutationRecoveryRunReport]
    let executionReadiness:
        [KernelRunID: KernelNativeExecutionReadinessAssessment]
    let providerReadiness:
        [KernelRunID: KernelProviderInvocationProfileReadinessAssessment]
    @State private var showingKernelDiagnostics = false

    private var repositoryRuns: [WorkspaceMutationRecoveryRunReport] {
        recoveryRuns.filter { $0.repositoryIndexStatus != .notApplicable }
    }

    private var diagnosticRunCount: Int {
        Set(
            kernelRuns.map(\.runID.rawValue) + repositoryRuns.map(\.runID.rawValue)
        ).count
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: module.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(module.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if diagnosticRunCount > 0 {
                Button {
                    showingKernelDiagnostics = true
                } label: {
                    Label(
                        "Kernel diagnostics · \(diagnosticRunCount)",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("open-kernel-convergence-diagnostics")
                .help("Inspect receipt-backed convergence and repository-index diagnosis")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("module-context-label")
        .sheet(isPresented: $showingKernelDiagnostics) {
            KernelConvergenceDiagnosticsView(
                runs: kernelRuns,
                recoveryRuns: repositoryRuns,
                executionReadiness: executionReadiness,
                providerReadiness: providerReadiness
            )
        }
    }
}

/// Presentation-only lifecycle semantics for receipt-backed convergence
/// diagnostics. An unretired strategy is selectable only while its run can
/// execute. Once the run is terminal it remains immutable history, not an
/// "active" process, attempt, or authority.
enum KernelConvergenceDiagnosticPresentation {
    static func strategyLifecycleLabel(
        _ lifecycle: ConvergenceStrategyLifecycle,
        runPhase: KernelRunPhase
    ) -> String {
        if runPhase.isTerminal {
            switch lifecycle {
            case .active:
                return "unretired history · run \(runPhase.rawValue)"
            case .waitingForCondition:
                return "waiting history · run \(runPhase.rawValue)"
            case .retired:
                return "retired"
            }
        }
        switch lifecycle {
        case .active:
            return "active"
        case .waitingForCondition:
            return "waiting for condition"
        case .retired:
            return "retired"
        }
    }

    static func isInertTerminalHistory(
        _ lifecycle: ConvergenceStrategyLifecycle,
        runPhase: KernelRunPhase
    ) -> Bool {
        runPhase.isTerminal && lifecycle != .retired
    }
}

private struct KernelConvergenceDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let runs: [KernelRunProjection]
    let recoveryRuns: [WorkspaceMutationRecoveryRunReport]
    let executionReadiness:
        [KernelRunID: KernelNativeExecutionReadinessAssessment]
    let providerReadiness:
        [KernelRunID: KernelProviderInvocationProfileReadinessAssessment]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kernel diagnostics")
                        .font(.title2).fontWeight(.semibold)
                    Text("Receipt-backed projection and explicit native activation")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(runs, id: \.runID.rawValue) { run in
                        if let diagnosis = run.convergenceDiagnosis {
                            runSection(run: run, diagnosis: diagnosis)
                        } else {
                            enrolledRunSection(run)
                        }
                    }
                    ForEach(recoveryRuns, id: \.runID.rawValue) { report in
                        repositoryIndexSection(report)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 640, idealHeight: 760)
        .accessibilityIdentifier("kernel-convergence-diagnostics")
    }

    private func enrolledRunSection(_ run: KernelRunProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.runID.rawValue)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text("Journal sequence \(run.sequence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(run.phase.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(runStatusSummary(run))
            .font(.caption)
            .foregroundStyle(.secondary)
            Label(runBoundarySummary(run), systemImage: "checkmark.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
            if let readiness = executionReadiness[run.runID] {
                if readiness.canPrepareAndActivate {
                    Label(
                        "Ratified native authority is ready for one explicit activation.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Native execution blocked · \(readiness.blockers.count) missing authority receipts",
                        systemImage: "pause.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    ForEach(readiness.blockers, id: \.rawValue) { blocker in
                        Text("• \(blocker.displaySummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.latestKernelEnrollmentReceipt?.runID == run.runID {
                    Button("Activate Native Attempt") {
                        Task { await model.activateLatestEnrolledKernelRun() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.kernelExecutionStartInProgress
                            || !readiness.canPrepareAndActivate
                    )
                    .accessibilityIdentifier(
                        "activate-native-kernel-attempt-button"
                    )
                    Text(
                        "Activation uses only the unchanged enrolled plan, strategy, budgets, verifier, workspace, and actor. Provider launch remains separately gated."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            if let provider = providerReadiness[run.runID] {
                if provider.canCompileProviderInvocation {
                    Label(
                        "Provider profile authority is complete for V2 invocation compilation; no launch receipt is implied.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "Provider invocation blocked · \(provider.blockers.count) exact profile constraints",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(
                        "kernel-provider-invocation-blocked"
                    )
                    ForEach(provider.blockers, id: \.rawValue) { blocker in
                        Text("• \(blocker.displaySummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForgeStyle.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kernel-enrolled-ready-run")
    }

    private func runStatusSummary(_ run: KernelRunProjection) -> String {
        let requirements =
            "Requirements \(run.acceptedRequirementCount) / \(run.mandatoryRequirementCount)"
        switch run.phase {
        case .ready:
            return "\(requirements) · no native attempt admitted"
        case .executing:
            return "\(requirements) · one native attempt is active"
        default:
            return "\(requirements) · phase \(run.phase.rawValue)"
        }
    }

    private func runBoundarySummary(_ run: KernelRunProjection) -> String {
        switch run.phase {
        case .ready:
            return "Confirmed native contract enrolled; activation remains at the journal boundary."
        case .executing:
            return "Kernel attempt active; provider launch awaits its own receipt-gated authority."
        default:
            return "Kernel state is projected only from retained journal receipts."
        }
    }

    private func repositoryIndexSection(
        _ report: WorkspaceMutationRecoveryRunReport
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.runID.rawValue)
                        .font(.headline).textSelection(.enabled)
                    Text("Repository generation")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(report.repositoryIndexStatus.rawValue)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(
                        report.repositoryIndexStatus == .resolved
                            ? Color.green
                            : Color.orange
                    )
            }
            if let telemetry = report.repositoryIndexTelemetry {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(telemetry.entryCount)")
                            .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        Text("Indexed files")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(telemetry.disposition.rawValue)
                            .font(.subheadline).fontWeight(.semibold)
                        Text("Cache disposition")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(telemetry.sourceSequence)")
                            .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        Text("Journal sequence")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(
                    "Authority \(telemetry.authority.rawValue) · generation \(telemetry.generationDigest.rawValue) · observed \(telemetry.observedMetadataDigest.rawValue)"
                )
                .font(.caption2).foregroundStyle(.tertiary)
                .textSelection(.enabled)
            } else {
                Text("Cache reuse authority was withheld; inspect the typed recovery status before admitting work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForgeStyle.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kernel-repository-index-telemetry")
    }

    private func runSection(
        run: KernelRunProjection,
        diagnosis: ConvergenceDiagnosticProjection
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.runID.rawValue)
                        .font(.headline).textSelection(.enabled)
                    Text("Epoch \(diagnosis.epochID) · sequence \(diagnosis.sourceSequence)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(run.phase.rawValue)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                diagnosticMetric(
                    "Attempts",
                    consumed: diagnosis.budget.consumed.attempts,
                    maximum: diagnosis.budget.maximum.maximumAttempts
                )
                diagnosticMetric(
                    "Strategies",
                    consumed: diagnosis.budget.consumed.strategies,
                    maximum: diagnosis.budget.maximum.maximumStrategies
                )
                diagnosticMetric(
                    "Mutation cost",
                    consumed: diagnosis.budget.consumed.mutationCost,
                    maximum: diagnosis.budget.maximum.maximumMutationCost
                )
                diagnosticMetric(
                    "Verification cost",
                    consumed: diagnosis.budget.consumed.verificationCost,
                    maximum: diagnosis.budget.maximum.maximumVerificationCost
                )
                diagnosticMetric(
                    "Damage",
                    consumed: diagnosis.budget.consumed.damageEvents,
                    maximum: diagnosis.budget.maximum.maximumDamageEvents
                )
                if let required = run.durationRequiredSeconds {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accepted time")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(
                            "\(run.durationAcceptedSeconds.compactDuration) / \(TimeInterval(required).compactDuration)"
                        )
                        .font(.caption).fontWeight(.semibold).monospacedDigit()
                        Text(
                            "\(run.durationExcludedSeconds.compactDuration) excluded · \(run.durationCoverageViolations.count) violations"
                        )
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("kernel-accepted-duration")
                }
                Spacer()
            }

            Divider()
            VStack(alignment: .leading, spacing: 12) {
                ForEach(diagnosis.strategies) { strategy in
                    strategyRow(strategy, runPhase: run.phase)
                }
                if diagnosis.strategies.isEmpty {
                    Text("No admitted strategy receipt is present.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !diagnosis.replacementAuthorizations.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Replacement authorizations")
                        .font(.subheadline).fontWeight(.semibold)
                    ForEach(diagnosis.replacementAuthorizations) { replacement in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                "\(short(replacement.predecessorFingerprint.rawValue)) → \(short(replacement.replacementFingerprint.rawValue))"
                            )
                            .font(.caption).fontWeight(.semibold).monospaced()
                            Text(
                                "Changed axes: \(replacement.changedAxes.map(\.rawValue).joined(separator: ", ")) · failures: \(replacement.failureDigests.count) · \(replacement.consumed ? "consumed" : "authorized")"
                            )
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text(
                "Authority \(diagnosis.authority) · projection \(diagnosis.projectionDigest.rawValue)"
            )
            .font(.caption2).foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
        .padding(16)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForgeStyle.hairline))
    }

    private func strategyRow(
        _ strategy: ConvergenceStrategyDiagnostic,
        runPhase: KernelRunPhase
    ) -> some View {
        let inertHistory = KernelConvergenceDiagnosticPresentation
            .isInertTerminalHistory(
                strategy.lifecycle,
                runPhase: runPhase
            )
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(short(strategy.fingerprint.rawValue))
                    .font(.caption).fontWeight(.semibold).monospaced()
                Text(KernelConvergenceDiagnosticPresentation.strategyLifecycleLabel(
                    strategy.lifecycle,
                    runPhase: runPhase
                ))
                    .font(.caption2)
                    .foregroundStyle(
                        inertHistory
                            ? Color.secondary
                            : lifecycleColor(strategy.lifecycle)
                    )
                    .accessibilityIdentifier(
                        inertHistory
                            ? "kernel-terminal-strategy-history"
                            : "kernel-live-strategy-lifecycle"
                    )
                Spacer()
                Text("\(strategy.attemptIDs.count) attempt\(strategy.attemptIDs.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(
                "Requirements: \(strategy.requirementIDs.map(\.rawValue).joined(separator: ", "))"
            )
            .font(.caption2).foregroundStyle(.secondary)
            Text(
                "Mutation Δ \(strategy.mutationCostConsumed) · verification Δ \(strategy.verificationCostConsumed) · external effects \(strategy.externalEffectsConsumed) · failures \(strategy.failureDigests.count)"
            )
            .font(.caption2).foregroundStyle(.secondary)
            if let delta = strategy.lastProgressDelta {
                Text(
                    "Evidence Δ +\(delta.acceptedEvidenceReceiptIDsAdded.count) · requirements +\(delta.acceptedRequirementIDsAdded.count) · blockers resolved \(delta.blockerDigestsResolved.count) · invariants regressed \(delta.invariantRegressionIDsAdded.count)"
                )
                .font(.caption2)
                .foregroundStyle(
                    delta.invariantRegressionIDsAdded.isEmpty ? Color.secondary : Color.red
                )
            }
            if let action = strategy.retirementActionCode {
                Text("Retirement: \(action)")
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(.red)
            }
            if let lesson = strategy.lessonDigest {
                Text("Lesson: \(lesson.rawValue)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let waiting = strategy.waitingConditionDigest {
                Text("Waiting condition: \(waiting.rawValue)")
                    .font(.caption2).foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
        .help(
            inertHistory
                ? "The strategy was never retired, but the terminal run makes it inert historical state."
                : "Receipt-derived strategy lifecycle."
        )
    }

    private func diagnosticMetric<T: BinaryInteger>(
        _ title: String,
        consumed: T,
        maximum: T
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(consumed)/\(maximum)")
                .font(.subheadline).fontWeight(.semibold).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func short(_ value: String) -> String {
        value.count > 14 ? String(value.prefix(14)) + "…" : value
    }

    private func lifecycleColor(_ lifecycle: ConvergenceStrategyLifecycle) -> Color {
        switch lifecycle {
        case .active: return .green
        case .waitingForCondition: return .orange
        case .retired: return .red
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: LoopController

    var body: some View {
        VStack(spacing: 0) {
            ModuleSwitcher()

            Button {
                model.startNewTaskFlow()
            } label: {
                Label("New Task", systemImage: "plus")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 42)
                    .background(model.showingNewTask ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.tasks) { task in
                        Button {
                            store.select(id: task.id)
                            model.showingNewTask = false
                        } label: {
                            TaskSidebarRow(
                                task: task,
                                liveSeconds: controller.liveAccumulatedSeconds(for: task),
                                selected: !model.showingNewTask && store.selectedTaskID == task.id
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Show in Finder") { model.revealWorkspace(task) }
                            Divider()
                            Button("Delete Task…", role: .destructive) { model.requestDeleteTask(task) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
            }

            Divider()
            Button { model.codexConnection.presentStatus() } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.codexConnection.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(model.codexConnection.isConnected ? "Codex Connected" : "Codex Setup")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(13)
        }
        .background(.ultraThinMaterial)
    }
}

struct ModuleSwitcher: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovering = false
    @State private var showingModules = false

    var body: some View {
        Button {
            showingModules.toggle()
        } label: {
            HStack(spacing: 10) {
                LoopForgeMark(size: 34)
                Text("LoopForge")
                    .font(.headline)
                Spacer(minLength: 4)
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 50)
            .background(
                isHovering ? Color.primary.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovering = hovering }
        }
        .help("Switch LoopForge module")
        .popover(isPresented: $showingModules, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Modules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                ForEach(LoopForgeModule.allCases) { module in
                    Button {
                        model.selectModule(module)
                        showingModules = false
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: module.symbol)
                                .frame(width: 22)
                                .foregroundStyle(
                                    model.selectedModule == module
                                        ? Color.accentColor
                                        : Color.secondary
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.title)
                                    .fontWeight(.medium)
                                Text(module.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedModule == module {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(width: 270, height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .accessibilityIdentifier("module-switcher")
    }
}

private struct TaskSidebarRow: View {
    let task: LoopTask
    let liveSeconds: TimeInterval
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.displayTaskSummary)
                    .font(.subheadline).fontWeight(.medium).lineLimit(2)
                if task.status != .completed {
                    Text("\(task.status.title) · \(liveSeconds.compactDuration)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if task.status.isWorking {
                CircularWorkingIndicator(color: .secondary, size: 13)
                    .accessibilityLabel("Task is running")
            } else if task.status == .completed, task.completionViewedAt == nil {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Completed task not yet viewed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

}

private struct NewTaskView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.draftProjectMode == nil || model.draftWorkspacePath == nil {
                ProjectEntryChooser()
            } else {
                TaskComposer()
            }
        }
        .animation(.smooth(duration: 0.25), value: model.draftProjectMode)
    }
}

private struct ProjectEntryChooser: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text("Choose a project")
                    .font(.system(size: 32, weight: .semibold))
                Text("Open something on this Mac, or begin in a new folder.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                projectButton("Existing Project", symbol: "folder.fill", action: model.chooseExistingProject)
                    .accessibilityIdentifier("existing-project-button")
                projectButton("New Project", symbol: "folder.badge.plus", action: model.createNewProjectFolder)
                    .accessibilityIdentifier("new-project-button")
            }
            .frame(maxWidth: 650)
            Spacer()
        }
        .padding(50)
    }

    private func projectButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(17)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
        }
        .buttonStyle(.plain)
    }
}

private struct TaskComposer: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should LoopForge do?")
                        .font(.system(size: 30, weight: .semibold))
                    Text(model.draftWorkspacePath ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }

                requestEditor
                qualityPicker
                executionSettings
                providerAuthoritySettings
                sourceRevisionCapturePolicy
                exactImplementationAuthority
                exactDeliverableCardinalityAuthority
                verificationProbeSelection
                projectRow

                if let estimate = model.estimate {
                    EstimatePanel(estimate: estimate)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 46)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .animation(.smooth(duration: 0.25), value: model.estimate != nil)
    }

    private var requestEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.draftRequest)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 150)
                .accessibilityLabel("Task request")
                .accessibilityIdentifier("task-request-editor")
            if model.draftRequest.isEmpty {
                Text("Build, repair, optimize, investigate, test, or run an experiment…")
                    .foregroundStyle(.tertiary)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline))
    }

    private var qualityPicker: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Contract rigor")
                    .font(.headline)
                Picker("Contract rigor", selection: Binding(
                    get: { model.draftQuality },
                    set: {
                        model.draftQuality = $0
                        model.qualityChanged()
                    }
                )) {
                    ForEach(QualityTier.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("\(model.draftQuality.subtitle) · controls planning and evidence depth, not completion authority")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .stroke(ForgeStyle.hairline)
            )

            Button {
                model.selectAutoGraphLoop()
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("Journaled Auto Graph", systemImage: "point.3.filled.connected.trianglepath.dotted")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text("The only new-work path. Single Loop and Parallel Candidates remain read-only historical evidence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(width: 245, alignment: .topLeading)
                .frame(minHeight: 102, alignment: .topLeading)
                .background(
                    Color.accentColor.opacity(0.075),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.accentColor.opacity(0.34))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("auto-graph-loop-button")
        }
    }

    private var executionSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentConfigurationRow(
                role: .control,
                title: "Main Graph Agent"
            )
                .padding(16)
            Divider().padding(.horizontal, 16)
            AgentConfigurationRow(
                role: .subAgent,
                title: "Node Loop Agent"
            )
                .padding(16)
            Divider()
            HStack {
                Label("Keys stay in macOS Keychain", systemImage: "key.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Manage Models…") { model.openModelManager() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline))
    }

    private var providerAuthoritySettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $model.draftWorkerNetworkAccess) {
                Label("Allow worker network access", systemImage: "network")
                    .font(.headline)
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("worker-network-authority-toggle")
            Text("Off by default. Enabling this adds exactly kernel.network-access to the user-confirmed contract and enables networking only for the worker; the independent reviewer remains offline. It does not select, ratify, or launch a provider harness.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(
            ForgeStyle.panel,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline)
        )
    }

    private var sourceRevisionCapturePolicy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Exact source-revision scope", systemImage: "doc.badge.gearshape")
                .font(.headline)
            TextField(
                "Excluded directory names",
                text: $model.draftSourceRevisionExcludedDirectoryNames
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityLabel("Excluded source-revision directory names")
            .accessibilityIdentifier("source-revision-exclusions-field")
            Text("Comma- or newline-separated directory names apply at any depth. Paths, traversal, duplicates, symlink entries outside excluded trees, and silent inference all fail closed. The canonical policy and digest are shown again before confirmation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(
            ForgeStyle.panel,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline)
        )
    }

    private var exactImplementationAuthority: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Exact implementation identities", systemImage: "equal.circle")
                .font(.headline)
            TextField(
                "Optional opaque IDs, comma or newline separated",
                text: $model.draftPermittedImplementationIDs
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityLabel("Permitted exact implementation identities")
            .accessibilityIdentifier("exact-implementation-identities-field")
            Text("Leave empty when substitution is not part of the contract. When supplied, only these user-confirmed opaque identities may satisfy the requirement; duplicates, whitespace ambiguity, model inference, and product-name matching fail closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(
            ForgeStyle.panel,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline)
        )
    }

    private var exactDeliverableCardinalityAuthority: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Exact deliverable cardinality", systemImage: "number.circle")
                .font(.headline)
            HStack(spacing: 10) {
                TextField(
                    "Optional opaque collection ID",
                    text: $model.draftDeliverableCollectionID
                )
                .accessibilityLabel("Opaque deliverable collection identity")
                .accessibilityIdentifier("deliverable-collection-id-field")
                TextField(
                    "Exact positive count",
                    text: $model.draftDeliverableExactCount
                )
                .frame(maxWidth: 190)
                .accessibilityLabel("Exact deliverable member count")
                .accessibilityIdentifier("deliverable-exact-count-field")
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            Text("Leave both fields empty when the requirement has no exact-set obligation. When supplied, the user-confirmed opaque collection identity and canonical positive count are bound to the mandatory requirement; partial, inferred, zero, signed, padded, or whitespace-normalized values fail closed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(
            ForgeStyle.panel,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline)
        )
    }

    private var verificationProbeSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Exact postimage verifier", systemImage: "checkmark.shield")
                .font(.headline)
            if let selection = model.draftNativeVerificationProbeSelection {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selection.executableFileName)
                            .font(.subheadline.weight(.medium))
                        Text(selection.executablePath)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("SHA-256 \(selection.probe.executableContentDigest.rawValue)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Manifest \(selection.manifestFileName) · \(selection.probe.fixedArguments.count) fixed argv elements · \(selection.probe.resultMappings.count) result mappings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change…") {
                        model.chooseNativeVerificationProbeManifest()
                    }
                    .disabled(model.nativeVerificationProbeImportInProgress)
                    Button("Remove") {
                        model.clearNativeVerificationProbeSelection()
                    }
                    .disabled(model.nativeVerificationProbeImportInProgress)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Text("Select a schema-constrained local verifier. LoopForge hashes its exact bytes; shell, ambient environment, network, unmatched green results, and child processes remain unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.chooseNativeVerificationProbeManifest()
                    } label: {
                        if model.nativeVerificationProbeImportInProgress {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Importing…")
                            }
                        } else {
                            Text("Select Verifier Manifest…")
                        }
                    }
                    .disabled(model.nativeVerificationProbeImportInProgress)
                    .accessibilityIdentifier(
                        "select-native-verifier-manifest-button"
                    )
                }
            }
            Text("The displayed path is a staging hint, not durable authority. Confirmation binds the executable digest, exact argv/input token, canonical parser, result mappings, and resource ceilings; later activation must rehash the executable again.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(
            ForgeStyle.panel,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline)
        )
    }

    private var projectRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.draftProjectMode == .new ? "folder.badge.plus" : "folder.fill")
                .foregroundStyle(Color.accentColor)
            Text(model.draftProjectMode?.title ?? "Project").font(.subheadline).fontWeight(.medium)
            Spacer()
            Button("Change") { model.changeProjectSelection() }
                .accessibilityIdentifier("change-project-button")
            Button("Estimate") { model.calculateEstimate() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("estimate-button")
                .disabled(model.draftRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct AgentConfigurationRow: View {
    @EnvironmentObject private var model: AppModel
    let role: AgentRole
    var title: String? = nil

    private var provider: AgentProviderKind { model.provider(for: role) }
    private var choices: [AgentModelChoice] { model.modelChoices(provider: provider, role: role) }
    private var selectedChoice: AgentModelChoice? {
        choices.first { $0.id == model.modelReference(for: role) }
    }
    private var reasoningOptions: [String] { model.reasoningOptions(for: role) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title ?? role.title, systemImage: role == .control ? "point.3.connected.trianglepath.dotted" : "hammer.fill")
                    .font(.headline)
                Spacer()
                if provider == .codex {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                settingField("Source") {
                    Picker("Source", selection: Binding(
                        get: { provider },
                        set: { provider in
                            if provider == .local {
                                model.openLocalModelPicker(for: role)
                            } else {
                                model.setProvider(provider, role: role)
                            }
                        }
                    )) {
                        ForEach(AgentProviderKind.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    .labelsHidden()
                }

                settingField("Model") {
                    if choices.isEmpty {
                        Button("Configure…") {
                            if provider == .local {
                                model.openLocalModelPicker(for: role)
                            } else {
                                model.openModelManager()
                            }
                        }
                    } else if provider == .local {
                        Button {
                            model.openLocalModelPicker(for: role)
                        } label: {
                            HStack {
                                Text(selectedChoice?.displayName ?? "Choose Model")
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                        }
                    } else {
                        Picker("Model", selection: Binding(
                            get: { model.modelReference(for: role) },
                            set: { model.setModelReference($0, role: role) }
                        )) {
                            ForEach(choices) { choice in
                                Text(choice.displayName).tag(choice.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if !reasoningOptions.isEmpty {
                    settingField("Reasoning") {
                        Picker("Reasoning", selection: Binding(
                            get: { model.reasoningEffort(for: role) },
                            set: { model.setReasoningEffort($0, role: role) }
                        )) {
                            ForEach(reasoningOptions, id: \.self) { effort in
                                Text(effort.capitalized).tag(effort)
                            }
                        }
                        .labelsHidden()
                    }
                }

                settingField("Access") {
                    Picker("Access", selection: Binding(
                        get: { model.accessMode(for: role) },
                        set: { model.setAccessMode($0, role: role) }
                    )) {
                        ForEach(model.accessModes(for: role)) {
                            Text($0.title).tag($0)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: 8) {
                if let selectedChoice {
                    Text(selectedChoice.detail)
                } else if provider == .api && role == .subAgent {
                    Text("Connect an API model to use it through the Codex tool harness.")
                } else {
                    Text("Add or download a model in Manage Models.")
                }
                Spacer()
                Text(model.accessMode(for: role).subtitle)
                    .foregroundStyle(model.accessMode(for: role) == .fullAccess ? ForgeStyle.warning : .secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func settingField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelManagerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingConnection = APIModelConnection.qwenTemplate
    @State private var apiKey = ""
    @State private var showingAdvancedAPISettings = false
    @State private var customDisplayName = ""
    @State private var customOllamaName = ""
    @State private var customMemoryGB = 18.0
    @State private var customContext = 32_768
    @State private var customVision = false
    @State private var pendingDownloadPlan: LocalModelDownloadPlan?

    private var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || APIKeyVault.get(for: editingConnection.id) != nil
    }

    private var canSaveConnection: Bool {
        hasAPIKey
            && !editingConnection.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !editingConnection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Models").font(.title2).fontWeight(.semibold)
                    Text("One catalog for the Loop Control Agent and Sub Agent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    model.modelManagerRequestedRole = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()
            TabView(selection: $model.modelManagerPreferredProvider) {
                localModelsTab
                    .tabItem { Label("Local Deployment", systemImage: "desktopcomputer") }
                    .tag(AgentProviderKind.local)
                apiConnectionsTab
                    .tabItem { Label("API Connections", systemImage: "network") }
                    .tag(AgentProviderKind.api)
            }
            .padding(16)
        }
        .frame(width: 900, height: 660)
        .task { await model.agentCatalog.refreshInstalledModels() }
        .alert(
            "Download local model?",
            isPresented: Binding(
                get: { pendingDownloadPlan != nil },
                set: { if !$0 { pendingDownloadPlan = nil } }
            ),
            presenting: pendingDownloadPlan
        ) { plan in
            Button("Cancel", role: .cancel) { pendingDownloadPlan = nil }
            Button("Download \(plan.sizeLabel)") {
                pendingDownloadPlan = nil
                Task {
                    let ready = await model.agentCatalog.downloadLocalModel(plan)
                    if ready { useLocalModel(plan.profile) }
                }
            }
        } message: { plan in
            Text(
                "\(plan.profile.displayName) will download \(plan.sizeLabel) from the official Ollama Registry. "
                    + "Allow at least 6 GB of additional free space for runtime data. "
                    + "After downloading, LoopForge will validate capabilities and run a real local response check."
            )
        }
    }

    private var localModelsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.modelManagerRequestedRole.map { "Choose a model for \($0.title)" } ?? "Local models")
                        .font(.headline)
                    Text("No model weights are bundled. Download only the model you choose.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.agentCatalog.localStatus).font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await model.agentCatalog.refreshInstalledModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            List(model.agentCatalog.localModels, id: \.id) { profile in
                HStack(spacing: 12) {
                    Image(systemName: profile.supportsVision ? "eye.fill" : "cpu")
                        .foregroundStyle(profile.supportsVision ? Color.purple : Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(profile.displayName).fontWeight(.medium)
                            Text(profile.recommendationLabel.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text("\(profile.ollamaName) · ≈\(profile.downloadSizeGB.formatted(.number.precision(.fractionLength(1)))) GB download · \(profile.resourceLabel)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(profile.reason)
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    Spacer()
                    if model.agentCatalog.downloadingLocalModelID == profile.id {
                        ProgressView().controlSize(.small)
                        Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                    } else if model.agentCatalog.checkingLocalModelID == profile.id {
                        ProgressView().controlSize(.small)
                        Text("Checking…").font(.caption).foregroundStyle(.secondary)
                    } else if model.agentCatalog.isLocalModelReady(profile) {
                        if model.modelManagerRequestedRole != nil {
                            Button("Use") { useLocalModel(profile) }
                                .disabled(!canUse(profile))
                                .accessibilityIdentifier("use-local-\(profile.id)")
                        } else {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    } else if model.agentCatalog.isLocalModelInstalled(profile) {
                        Button("Verify") {
                            Task {
                                let ready = await model.agentCatalog.verifyInstalledLocalModel(profile)
                                if ready { useLocalModel(profile) }
                            }
                        }
                        .disabled(model.agentCatalog.downloadingLocalModelID != nil)
                        .accessibilityIdentifier("verify-local-\(profile.id)")
                    } else {
                        Button("Download") {
                            requestDownload(profile)
                        }
                        .disabled(model.agentCatalog.downloadingLocalModelID != nil)
                        .accessibilityIdentifier("download-local-\(profile.id)")
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .contain)
            }
            .frame(minHeight: 245)

            if !model.agentCatalog.downloadProgress.isEmpty {
                Text(model.agentCatalog.downloadProgress)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }

            DisclosureGroup("Add another Ollama model") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Display name", text: $customDisplayName)
                        TextField("Ollama name, e.g. qwen3:14b", text: $customOllamaName)
                    }
                    HStack {
                        TextField("Memory GB", value: $customMemoryGB, format: .number)
                            .frame(width: 110)
                        TextField("Context", value: $customContext, format: .number)
                            .frame(width: 130)
                        Toggle("Vision", isOn: $customVision)
                        Spacer()
                        Button("Add Model") {
                            model.agentCatalog.addCustomLocalModel(
                                displayName: customDisplayName,
                                ollamaName: customOllamaName,
                                estimatedMemoryGB: customMemoryGB,
                                contextWindow: customContext,
                                supportsVision: customVision
                            )
                            customDisplayName = ""
                            customOllamaName = ""
                        }
                        .disabled(customOllamaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 10)
            }
        }
    }

    private func requestDownload(_ profile: ModelProfile) {
        Task {
            do {
                pendingDownloadPlan = try await model.agentCatalog.prepareLocalModelDownload(profile)
            } catch {
                // The catalog presents the sanitized, actionable failure inline.
            }
        }
    }

    private func canUse(_ profile: ModelProfile) -> Bool {
        guard model.modelManagerRequestedRole == .control,
              model.estimate?.visualAuditRequired == true else { return true }
        return profile.supportsVision
    }

    private func useLocalModel(_ profile: ModelProfile) {
        guard let role = model.modelManagerRequestedRole, canUse(profile) else { return }
        model.setModelReference(profile.id, role: role)
        model.modelManagerRequestedRole = nil
        dismiss()
    }

    private var apiConnectionsTab: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Connections").font(.headline)
                    Spacer()
                    Button {
                        editingConnection = APIModelConnection.qwenTemplate
                        apiKey = ""
                        model.agentCatalog.apiTestStatus = .idle
                        model.agentCatalog.apiDiscoveryStatus = .idle
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                List(model.agentCatalog.apiConnections, selection: Binding<UUID?>(
                    get: { editingConnection.id },
                    set: { id in
                        guard let connection = model.agentCatalog.apiConnection(id: id) else { return }
                        editingConnection = connection
                        apiKey = ""
                        model.agentCatalog.apiTestStatus = .idle
                        model.agentCatalog.apiDiscoveryStatus = .idle
                    }
                )) { connection in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.displayName)
                        Text("\(connection.resolvedProviderKind.title) · \(connection.model)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(connection.id)
                }
                .frame(width: 230)
            }

            Divider()

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Connect a provider").font(.headline)
                    Spacer()
                    Label("Keychain protected", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker("Provider", selection: Binding(
                    get: { editingConnection.resolvedProviderKind },
                    set: { applyProvider($0) }
                )) {
                    ForEach(APIProviderKind.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                TextField("Base URL", text: $editingConnection.baseURL)

                if editingConnection.resolvedProviderKind == .custom {
                    TextField("Model ID", text: $editingConnection.model)
                } else {
                    Picker("Model", selection: $editingConnection.model) {
                        ForEach(editingConnection.selectableModels, id: \.self) { modelID in
                            Text(modelID).tag(modelID)
                        }
                    }
                }

                SecureField(
                    model.agentCatalog.apiConnections.contains(where: { $0.id == editingConnection.id })
                        ? "API key — leave blank to keep the saved key"
                        : "API key",
                    text: $apiKey
                )

                HStack {
                    Button {
                        connectLoadAndVerify()
                    } label: {
                        if model.agentCatalog.apiDiscoveryStatus == .loading
                            || model.agentCatalog.apiTestStatus == .testing {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Connecting…")
                            }
                        } else {
                            Text("Connect & Load Models")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        editingConnection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !hasAPIKey
                            || model.agentCatalog.apiDiscoveryStatus == .loading
                            || model.agentCatalog.apiTestStatus == .testing
                    )
                    Button("Save") { saveConnection() }
                        .disabled(!canSaveConnection)
                    Spacer()
                }

                apiDiscoveryStatus
                apiStatus

                Label(apiCompatibilityText, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)

                DisclosureGroup("Advanced", isExpanded: $showingAdvancedAPISettings) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Connection name", text: $editingConnection.name)
                        HStack {
                            Picker("Protocol", selection: $editingConnection.wireProtocol) {
                                ForEach(APIWireProtocol.allCases) { Text($0.title).tag($0) }
                            }
                            TextField("Context", value: $editingConnection.contextWindow, format: .number)
                                .frame(width: 160)
                        }
                        HStack {
                            TextField("Reasoning modes", text: Binding(
                                get: { editingConnection.reasoningOptions.joined(separator: ", ") },
                                set: {
                                    editingConnection.reasoningOptions = $0.split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                }
                            ))
                            Toggle("Vision", isOn: $editingConnection.supportsVision)
                        }
                    }
                    .padding(.top, 8)
                }

                HStack {
                    Spacer()
                    if model.agentCatalog.apiConnections.contains(where: { $0.id == editingConnection.id }) {
                        Button("Delete", role: .destructive) {
                            model.agentCatalog.deleteAPIConnection(editingConnection)
                            editingConnection = .qwenTemplate
                            apiKey = ""
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private var apiCompatibilityText: String {
        switch editingConnection.wireProtocol {
        case .automatic:
            return "LoopForge will detect Responses or Chat Completions before saving."
        case .responses:
            return "This endpoint connects directly to the Codex Responses harness."
        case .chatCompletions:
            return "Codex tools run through a private loopback Responses bridge."
        }
    }

    @ViewBuilder
    private var apiDiscoveryStatus: some View {
        switch model.agentCatalog.apiDiscoveryStatus {
        case .idle:
            EmptyView()
        case .loading:
            EmptyView()
        case .loaded(_, let usedFallback):
            Label(
                model.agentCatalog.apiDiscoveryStatus.title,
                systemImage: usedFallback ? "checkmark.circle" : "arrow.down.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(usedFallback ? Color.secondary : Color.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(3)
        }
    }

    @ViewBuilder
    private var apiStatus: some View {
        switch model.agentCatalog.apiTestStatus {
        case .idle:
            EmptyView()
        case .testing:
            HStack { ProgressView().controlSize(.small); Text("Testing authentication and response parsing…") }
                .font(.caption).foregroundStyle(.secondary)
        case .passed(_, let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(3)
        }
    }

    private func saveConnection() {
        do {
            try model.agentCatalog.saveAPIConnection(editingConnection, apiKey: apiKey)
            if model.draftControlProvider == .api,
               model.modelChoices(provider: .api, role: .control).contains(where: { $0.id == editingConnection.id.uuidString }) {
                model.setModelReference(editingConnection.id.uuidString, role: .control)
            }
            if model.draftSubProvider == .api,
               model.modelChoices(provider: .api, role: .subAgent).contains(where: { $0.id == editingConnection.id.uuidString }) {
                model.setModelReference(editingConnection.id.uuidString, role: .subAgent)
            }
            apiKey = ""
        } catch {
            model.alertMessage = error.localizedDescription
        }
    }

    private func applyProvider(_ provider: APIProviderKind) {
        let isSaved = model.agentCatalog.apiConnections.contains { $0.id == editingConnection.id }
        let id = isSaved ? UUID() : editingConnection.id
        editingConnection = provider.template()
        editingConnection.id = id
        apiKey = ""
        model.agentCatalog.apiTestStatus = .idle
        model.agentCatalog.apiDiscoveryStatus = .idle
    }

    private func connectLoadAndVerify() {
        let suppliedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = suppliedKey.isEmpty ? APIKeyVault.get(for: editingConnection.id) : suppliedKey
        guard let key, !key.isEmpty else {
            model.agentCatalog.apiTestStatus = .failed("Enter an API key.")
            return
        }
        let provider = editingConnection.resolvedProviderKind
        let baseURL = editingConnection.baseURL
        Task {
            let discovery = await model.agentCatalog.discoverAPIModels(
                provider: provider,
                baseURL: baseURL,
                apiKey: key
            )
            if !discovery.models.isEmpty {
                editingConnection.discoveredModels = discovery.models
                if !discovery.models.contains(editingConnection.model) {
                    editingConnection.model = discovery.models[0]
                }
                editingConnection.lastModelRefreshAt = Date()
            }
            let status = await model.agentCatalog.testAPIConnection(editingConnection, apiKey: key)
            if case .passed(let protocolUsed, _) = status {
                editingConnection.wireProtocol = protocolUsed
                saveConnection()
            }
        }
    }
}

private struct EstimatePanel: View {
    @EnvironmentObject private var model: AppModel
    let estimate: TaskEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dynamic execution plan")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Evidence-gated graph")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Execution")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Journaled Auto Graph")
                        .font(.headline)
                    Text("No artificial runtime minimum")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            "The Main Graph Agent expands, audits, and repairs node loops until the integrated result passes.",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Review Auto Graph Contract") {
                            model.requestStartLoop()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("start-task-button")
                    }
                    HStack(spacing: 10) {
                        if let baseline = model.draftNativeDesignBaselineSource {
                            Label(
                                "Protected baseline · \(baseline.captures.count) native capture\(baseline.captures.count == 1 ? "" : "s")",
                                systemImage: "lock.shield.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(baseline.builtArtifact.rawValue)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Remove") {
                                model.clearNativeDesignBaselineCaptureSource()
                            }
                            .disabled(model.nativeDesignBaselineImportInProgress)
                        } else {
                            Text("Visual or product-identity work can bind a protected native baseline before contract review.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                model.chooseNativeDesignBaselineCaptureSource()
                            } label: {
                                if model.nativeDesignBaselineImportInProgress {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Importing…")
                                    }
                                } else {
                                    Text("Select Design Baseline…")
                                }
                            }
                            .disabled(model.nativeDesignBaselineImportInProgress)
                            .accessibilityIdentifier(
                                "select-native-design-baseline-button"
                            )
                        }
                    }
            }

            if model.draftControlProvider == .local {
                Label(
                    "Local control models produce three parallel mission briefs, then independently check them against your original request.",
                    systemImage: "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if estimate.category == .desktopAutomation {
                Label(
                    "Uses the existing signed-in app directly. No API key. LoopForge verifies UI control before the timer starts.",
                    systemImage: "macwindow.and.cursorarrow"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.22)))
    }
}

private struct PromptOptimizationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose the clearest prompt")
                        .font(.title2).fontWeight(.semibold)
                    Text("Every option passed exact-value and constraint preservation checks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.cancelPromptOptimization() }
            }
            .padding(22)
            Divider()

            Group {
                switch model.promptOptimizationPhase {
                case .idle:
                    EmptyView()
                case .generating(let provider):
                    VStack(spacing: 18) {
                        CircularWorkingIndicator(color: .accentColor, size: 44)
                        Text("Creating and auditing three options…")
                            .font(.headline)
                        Text(provider)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34)).foregroundStyle(.orange)
                        Text("Prompt refinement was unavailable").font(.headline)
                        Text(message).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 520)
                        Button("Start with Original Prompt") { model.startWithOriginalPrompt() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    ScrollView {
                        VStack(spacing: 12) {
                            promptCard(
                                title: "Original prompt",
                                emphasis: "Exactly as entered",
                                prompt: model.draftRequest,
                                action: model.startWithOriginalPrompt
                            )
                            ForEach(model.promptOptimizationCandidates) { candidate in
                                promptCard(
                                    title: candidate.title,
                                    emphasis: candidate.emphasis,
                                    prompt: candidate.prompt,
                                    action: { model.startWithOptimizedPrompt(candidate) }
                                )
                            }
                            if !model.promptOptimizationProvider.isEmpty {
                                Label(
                                    "Generated by \(model.promptOptimizationProvider)",
                                    systemImage: "checkmark.seal"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.top, 4)
                            }
                        }
                        .padding(22)
                    }
                }
            }
        }
        .frame(width: 780, height: 650)
    }

    private func promptCard(
        title: String,
        emphasis: String,
        prompt: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(title).font(.headline)
                        Text(emphasis)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    Text(prompt)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(5).multilineTextAlignment(.leading)
                }
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2).foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NativeAutoGraphContractConfirmationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confirm Auto Graph authority")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("This creates one journaled ready run. It does not start a legacy worker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.cancelNativeContractConfirmation() }
                    .disabled(model.kernelEnrollmentInProgress)
            }
            .padding(22)
            Divider()

            if let draft = model.pendingNativeContractConfirmation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        contractSection("Exact objective") {
                            Text(draft.displayObjective)
                                .textSelection(.enabled)
                        }
                        contractSection("Selected workspace") {
                            Text(draft.displayWorkspacePath)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Read: \(draft.displayReadableScopes.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Write: \(draft.displayWritableScopes.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        contractSection("Acceptance") {
                            Text("Independent review and quiescence are mandatory.")
                            Text("No artificial duration requirement is declared for Auto Graph.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !draft.displayPermittedImplementationIDs.isEmpty {
                            contractSection("Exact implementation authority") {
                                ForEach(
                                    draft.displayPermittedImplementationIDs,
                                    id: \.self
                                ) { implementationID in
                                    Text(implementationID)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                Text("Only these opaque identities may satisfy the requirement. Confirmation binds the exact set; product names, objective prose, and verifier substitutions grant no equivalence.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let cardinality =
                                draft.displayDeliverableCardinality {
                            contractSection("Exact deliverable cardinality") {
                                Text(cardinality.collectionID)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("Exactly \(cardinality.exactCount) independently identifiable members")
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("Confirmation binds this opaque collection identity and exact count to the mandatory requirement. Objective prose, filenames, repository contents, model inference, and aggregate file counts cannot widen or replace it.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        contractSection("Bound execution budgets") {
                            let mutation = draft.displayExecutionBudgets.mutation
                            let convergence = draft.displayExecutionBudgets.convergence
                            Text("Mutation ceiling: \(mutation.maximumChangedFiles) files · \(mutation.maximumChangedBytes) bytes")
                            Text([
                                "attempts \(convergence.maximumAttempts)",
                                "equivalent failures \(convergence.maximumEquivalentFailures)",
                                "strategies \(convergence.maximumStrategies)",
                                "plan expansions \(convergence.maximumPlanExpansions)",
                                "mutation cost \(convergence.maximumMutationCost)",
                                "verification cost \(convergence.maximumVerificationCost)",
                                "damage events \(convergence.maximumDamageEvents)",
                                "external effects \(convergence.maximumExternalEffects)"
                            ].joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text("These ceilings do not manufacture strategy or plan authority. The separate proposals below become authoritative only through confirmation of the complete candidate; no worker starts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        contractSection("Captured source revision") {
                            let revision = draft.displaySourceRevision
                            Text(revision.sourceRevision.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .accessibilityIdentifier(
                                    "native-contract-source-revision"
                                )
                            Text("\(revision.entries.count) files · \(revision.totalBytes) bytes")
                            Text("Excluded directory names: \(revision.excludedDirectoryNames.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Capture limits: \(revision.limits.maximumFiles) files · \(revision.limits.maximumTotalBytes) total bytes · \(revision.limits.maximumFileBytes) bytes per file")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Confirming binds this exact content, path, permission, root, and capture-policy digest into the durable contract. Git state, timestamps, and model prose are not source authority. The observation alone authorizes no strategy, plan, or worker start.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let baseline = draft.displayDesignBaselineSelection {
                            contractSection("Selected protected design baseline") {
                                Text("Baseline: \(baseline.id.rawValue)")
                                Text("Protected artifact: \(baseline.protectedBaselineID.rawValue) · \(baseline.builtArtifact.rawValue)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("\(baseline.captures.count) adapter-attested native captures · \(baseline.protectedInvariants.count) protected invariants · \(baseline.knownDebt.count) declared debt records")
                                Text("Source tree: \(baseline.sourceTree.rawValue)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Text("The imported JSON did not grant authority. LoopForge reopened every referenced file without following symlinks, rehashed the protected source and built artifact, and recomputed native capture receipts from raw evidence. The complete selection is sealed into this contract candidate; freezing still requires a second explicit confirmation after journal enrollment.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        contractSection("Proposed causal strategy") {
                            let authority = draft.displayCausalStrategyAuthority
                            let strategy = authority.descriptor
                            Text("Fingerprint: \(strategy.fingerprint.rawValue)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .accessibilityIdentifier(
                                    "native-contract-strategy-fingerprint"
                                )
                            Text("Hypothesis: \(strategy.hypothesisClass)")
                            Text("Action: \(strategy.actionClass)")
                            Text("Measurement boundary: \(strategy.measurementBoundary)")
                            Text("Baseline revision: \(strategy.baselineRevision.rawValue)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Mutation surface: \(strategy.mutationSurfaceDigest.rawValue)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            ForEach(
                                authority.expectedObservations.sorted { $0.id < $1.id },
                                id: \.id
                            ) { observation in
                                Text("Prediction \(observation.id): requirement \(observation.requirementID.rawValue) must produce accepted recipe \(observation.evidenceRecipeID.rawValue) evidence (\(observation.expectedObservationDigest.rawValue)).")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            ForEach(
                                authority.falsificationPredicates.sorted {
                                    $0.id < $1.id
                                },
                                id: \.id
                            ) { predicate in
                                Text("Falsifier \(predicate.id): \(predicate.kind.rawValue) for requirement \(predicate.requirementID.rawValue), recipe \(predicate.evidenceRecipeID.rawValue), at revision \(predicate.boundSourceRevision.rawValue).")
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                            Text("This is a LoopForge proposal, not an inference from objective prose. It becomes authority only if you confirm the complete candidate digest below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        contractSection("Executable verification recipe") {
                            ForEach(
                                draft.compiled.candidate.evidenceRecipes.sorted {
                                    $0.id.rawValue < $1.id.rawValue
                                },
                                id: \.id
                            ) { recipe in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.id.rawValue).fontWeight(.semibold)
                                    Text("Requirement: \(recipe.requirementID.rawValue) · verifier: \(recipe.verifierKind.rawValue) · independent lineage required")
                                    if let probe = recipe.executableProbe {
                                        Text("Executable sha256: \(probe.executableContentDigest.rawValue)")
                                        Text("Transport: \(probe.transport.rawValue) · network: \(probe.networkPolicy.rawValue) · environment: \(probe.environmentPolicy.rawValue)")
                                        Text("Fixed argv: \(probe.fixedArguments.isEmpty ? "none" : probe.fixedArguments.joined(separator: " ␟ "))")
                                        Text("Inputs: \(probe.inputBindings.map { "\($0.id)=\($0.kind.rawValue):\($0.artifactID)" }.joined(separator: ", "))")
                                        Text("Environment identity: \(probe.environmentIdentityDigest.rawValue)")
                                        Text("Capture identity: \(probe.captureIdentityDigest.rawValue)")
                                        Text("Parser: \(probe.parser.id) v\(probe.parser.schemaVersion) · \(probe.parser.contentDigest.rawValue)")
                                        Text("Mappings: \(probe.resultMappings.map { "exit \($0.exitCode) + \($0.parserResultCode) → \($0.outcome.rawValue)" }.joined(separator: ", ")) · unmatched → \(probe.unmatchedOutcome.rawValue)")
                                        Text("Limits: \(probe.resourceLimits.maximumWallClockSeconds)s · \(probe.resourceLimits.maximumCapturedOutputBytes) output bytes · \(probe.resourceLimits.maximumResidentBytes) resident bytes · \(probe.resourceLimits.maximumChildProcesses) child processes")
                                    }
                                }
                                .font(.caption)
                                .textSelection(.enabled)
                            }
                            Text("The direct executable, exact inputs, parser, environment, result mapping, and resource ceilings are candidate authority only after whole-candidate confirmation. Shell, network, child-process, model-prose, and unmatched-result fallbacks remain denied.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        contractSection("Proposed requirement-owned plan") {
                            let plan = draft.displayExecutionPlan
                            Text("Contract objective digest: \(plan.contractDigest.rawValue)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            ForEach(
                                plan.nodes.sorted { $0.id.rawValue < $1.id.rawValue },
                                id: \.id
                            ) { node in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(node.id.rawValue).fontWeight(.semibold)
                                    Text(node.objective).textSelection(.enabled)
                                    Text("Requirements: \(node.requirementIDs.map(\.rawValue).sorted().joined(separator: ", "))")
                                    Text("Dependencies: \(node.dependencies.map(\.rawValue).sorted().joined(separator: ", ").isEmpty ? "none" : node.dependencies.map(\.rawValue).sorted().joined(separator: ", "))")
                                    Text("Writable paths: \(node.mutationScope.writablePaths.sorted().joined(separator: ", ").isEmpty ? "none" : node.mutationScope.writablePaths.sorted().joined(separator: ", "))")
                                    Text("Node ceiling: \(node.mutationScope.maximumChangedFiles) files · \(node.mutationScope.maximumChangedBytes) bytes")
                                    Text("Strategy: \(node.strategyFingerprint.rawValue)")
                                        .textSelection(.enabled)
                                }
                                .font(.caption)
                            }
                            Text("Every mandatory requirement has exactly one owner; plan scopes and aggregate ceilings must remain within the confirmed workspace and budgets. Confirmation still does not start a worker.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        contractSection("Bound execution identities") {
                            executionProfileRow(
                                title: "Worker",
                                profile: draft.displayExecutionProfile.worker
                            )
                            Divider()
                            executionProfileRow(
                                title: "Independent reviewer",
                                profile: draft.displayExecutionProfile.independentReviewer
                            )
                            Text("Capability ceiling: \(draft.displayAuthorityCapabilityIDs.isEmpty ? "none" : draft.displayAuthorityCapabilityIDs.joined(separator: ", "))")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Reviewer lineage must differ from the worker. The reviewer is always read-only, offline, plugin-free, and minimally isolated. Worker network access exists only when the exact kernel.network-access capability is shown above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        contractSection("Candidate digest shown for confirmation") {
                            Text(draft.compiled.candidateDigest.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .accessibilityIdentifier("native-contract-candidate-digest")
                        }
                        Label(
                            "The receipt is single-use and bound to this exact workspace. A changed digest or directory fails before journal creation.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(22)
                }
                Divider()
                HStack {
                    Text("Enrollment retains the confirmed source revision, evidence recipes, budgets, causal strategy, and requirement-owned plan. It still does not authorize or start a worker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Confirm & Enroll Ready Run") {
                        Task { await model.confirmAndEnrollNativeAutoGraphContract() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.kernelEnrollmentInProgress)
                    .accessibilityIdentifier("confirm-native-contract-button")
                }
                .padding(18)
            }
        }
        .frame(minWidth: 680, minHeight: 620)
        .interactiveDismissDisabled(model.kernelEnrollmentInProgress)
        .accessibilityIdentifier("native-contract-confirmation-sheet")
    }

    @ViewBuilder
    private func contractSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForgeStyle.hairline))
    }

    private func executionProfileRow(
        title: String,
        profile: KernelAgentExecutionProfile
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold)
            Text("\(profile.provider.rawValue) · \(profile.modelID)")
            Text([
                "provider \(profile.providerReference)",
                "executable sha256 \(profile.executableContentDigest.rawValue)",
                "reasoning \(profile.reasoningEffort ?? "default")",
                "sandbox \(profile.sandbox.rawValue)",
                "network \(profile.networkPolicy.rawValue)",
                "plugins \(profile.pluginPolicy.rawValue)",
                "environment \(profile.environmentPolicy.rawValue)",
                "protocol \(profile.providerProtocol.rawValue)",
                "harness mode \(profile.providerHarnessMode.rawValue)",
                "credential \(profile.credentialMode.rawValue)"
            ].joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
    }
}

private struct NativeDesignBaselineConfirmationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Freeze protected design baseline")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("The run is enrolled. This separate action freezes the exact native captures and protected artifact; it does not start work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Leave Unfrozen") {
                    model.cancelNativeDesignBaselineConfirmation()
                }
            }
            .padding(22)
            Divider()

            if let draft = model.pendingNativeDesignBaselineConfirmation {
                let selection = draft.selection
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        baselineSection("Protected identities") {
                            Text("Design baseline: \(selection.id.rawValue)")
                            Text("Contract: \(selection.contractID.rawValue)")
                            Text("Protected reference: \(selection.protectedBaselineID.rawValue)")
                            Text("Built artifact sha256: \(selection.builtArtifact.rawValue)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Source tree sha256: \(selection.sourceTree.rawValue)")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        baselineSection("Native capture matrix") {
                            ForEach(selection.captures.sorted {
                                $0.cellID.rawValue < $1.cellID.rawValue
                            }, id: \.id) { capture in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(capture.cellID.rawValue)
                                        .fontWeight(.semibold)
                                    Text("\(capture.imageWidthPixels)×\(capture.imageHeightPixels) · \(capture.traits.locale) · \(capture.traits.appearance) · \(capture.traits.contentSizeCategory)")
                                    Text("Pixels: \(capture.imageDigest.rawValue)")
                                    Text("Accessibility: \(capture.accessibilityTreeDigest.rawValue)")
                                    Text("Harness: \(capture.harnessIdentity)")
                                }
                                .font(.caption)
                                .textSelection(.enabled)
                            }
                        }
                        baselineSection("Protected dimensions") {
                            ForEach(selection.protectedInvariants.sorted {
                                $0.id < $1.id
                            }, id: \.id) { invariant in
                                Text("\(invariant.dimension.rawValue) · \(invariant.id) · \(invariant.cellIDs.map(\.rawValue).sorted().joined(separator: ", "))")
                                    .font(.caption)
                            }
                            if selection.knownDebt.isEmpty {
                                Text("No accepted baseline debt.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(selection.knownDebt.sorted {
                                    $0.id.rawValue < $1.id.rawValue
                                }, id: \.id) { debt in
                                    Text("Debt \(debt.id.rawValue): \(debt.dimension.rawValue) · baseline \(debt.baselineSeverity) · interim ceiling \(debt.maximumInterimSeverity) · \(debt.direction.rawValue)")
                                        .font(.caption)
                                }
                            }
                        }
                        baselineSection("Exact confirmation digest") {
                            Text(draft.selectionDigest.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .accessibilityIdentifier(
                                    "native-design-baseline-selection-digest"
                                )
                            Text("Confirmation is single-use and bound to the exact ratification receipt, enrollment journal frame, protected artifact, capture protocol, user identity, and lineage shown above. Decoded evidence cannot reproduce this live authority.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(22)
                }
                Divider()
                HStack {
                    Text("Freezing changes only journaled preparation authority. It creates no process, lease, mutation, verification result, or publication permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Confirm & Freeze Baseline") {
                        model.confirmNativeDesignBaseline()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier(
                        "confirm-native-design-baseline-button"
                    )
                }
                .padding(18)
            }
        }
        .frame(minWidth: 680, minHeight: 620)
        .interactiveDismissDisabled(model.kernelEnrollmentInProgress)
        .accessibilityIdentifier("native-design-baseline-confirmation-sheet")
    }

    @ViewBuilder
    private func baselineSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForgeStyle.hairline))
    }
}

private struct TaskDetailView: View {
    @EnvironmentObject private var model: AppModel
    let taskID: UUID
    @ObservedObject var store: TaskStore
    @ObservedObject var controller: LoopController
    @State private var showingEndConfirmation = false
    @State private var selectedGraphNode: GraphLoopNode?
    @State private var showingExpandedGraph = false
    @State private var showingKernelDiagnostics = false

    private var task: LoopTask? { store.task(id: taskID) }

    private var repositoryRecoveryRuns: [WorkspaceMutationRecoveryRunReport] {
        model.kernelRecoveryRunReports.filter {
            $0.repositoryIndexStatus != .notApplicable
        }
    }

    private var diagnosticRunCount: Int {
        Set(
            model.kernelRunProjections.map(\.runID.rawValue)
                + repositoryRecoveryRuns.map(\.runID.rawValue)
        ).count
    }

    var body: some View {
        if let task {
            VStack(spacing: 0) {
                taskHeader(task)
                Divider()
                ScrollView {
                    VStack(spacing: 16) {
                        if task.resolvedExecutionMode == .autoGraph {
                            GraphOverviewCard(
                                task: task,
                                clock: controller.clock
                            )
                            if let graph = task.graphState {
                                GraphLoopMap(
                                    graph: graph,
                                    clock: controller.clock,
                                    expanded: false,
                                    onSelect: { selectedGraphNode = $0 },
                                    onExpand: { showingExpandedGraph = true }
                                )
                            }
                            GraphMainControlCard(task: task)
                        } else if task.resolvedExecutionMode == .parallelCandidates {
                            ParallelCandidateOverviewCard(
                                task: task,
                                clock: controller.clock
                            )
                            ParallelCandidateGrid(
                                task: task,
                                clock: controller.clock,
                                onInspect: { selectedGraphNode = $0 }
                            )
                        } else {
                            progressCard(task)
                            deliveryGatesCard(task)
                            LoopForgeControlLog(task: task)
                        }
                        goalCard(task)
                        ActivityLog(entries: task.logs)
                    }
                    .frame(maxWidth: 900)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .confirmationDialog(
                "End this task?",
                isPresented: $showingEndConfirmation,
                titleVisibility: .visible
            ) {
                Button("End Task", role: .destructive) { model.stop(task) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Agent work will stop and automatic restart will be disabled. Progress, task history, the Codex session, and project files stay saved, so you can resume later.")
            }
            .sheet(item: $selectedGraphNode) { node in
                GraphNodeInspector(
                    task: task,
                    nodeID: node.id,
                    store: store,
                    clock: controller.clock
                )
            }
            .sheet(isPresented: $showingExpandedGraph) {
                ExpandedGraphSheet(
                    taskID: task.id,
                    store: store,
                    clock: controller.clock
                )
            }
            .sheet(isPresented: $showingKernelDiagnostics) {
                KernelConvergenceDiagnosticsView(
                    runs: model.kernelRunProjections,
                    recoveryRuns: repositoryRecoveryRuns,
                    executionReadiness: model.kernelExecutionReadinessByRunID,
                    providerReadiness:
                        model.kernelProviderInvocationReadinessByRunID
                )
            }
        } else {
            ContentUnavailableView("Task not found", systemImage: "questionmark.folder")
        }
    }

    private func taskHeader(_ task: LoopTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.displayTaskSummary)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    HStack(spacing: 8) {
                        Text({
                            switch task.resolvedExecutionMode {
                            case .autoGraph: return "Auto Graph"
                            case .parallelCandidates:
                                return "Parallel ×\(task.resolvedParallelCandidateCount)"
                            case .singleLoop: return task.quality.title
                            }
                        }())
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.11), in: Capsule())
                        Text(
                            "\(task.title) · "
                                + NSString(string: task.workspacePath).abbreviatingWithTildeInPath
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if diagnosticRunCount > 0 {
                        Button {
                            showingKernelDiagnostics = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .help("Kernel diagnostics · \(diagnosticRunCount)")
                        .accessibilityLabel("Kernel diagnostics, \(diagnosticRunCount) runs")
                        .accessibilityIdentifier("open-kernel-convergence-diagnostics")
                    }
                    if task.completionReportPath != nil {
                        Button(task.status == .completed ? "Final Report" : "Status Page", systemImage: "safari") {
                            model.openCompletionReport(task)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button { model.revealWorkspace(task) } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Show in Finder")
                }
            }

            HStack(spacing: 12) {
                if task.status == .pausing {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Pausing…").font(.callout).fontWeight(.medium)
                    }
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Color.orange.opacity(0.11), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("task-transition-status")
                } else if task.status == .stopping {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Ending task…").font(.callout).fontWeight(.medium)
                    }
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Color.red.opacity(0.09), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("task-transition-status")
                } else if controller.runningTaskID == task.id {
                    Button("Pause Task", systemImage: "pause.circle.fill") { model.pause(task) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .help("Save progress and safely stop the active agent process")
                        .accessibilityIdentifier("pause-task-button")
                } else if task.canResume {
                    Label(
                        LegacyTaskExecutionRetirementPolicy.stage(
                            for: task.resolvedExecutionMode
                        ),
                        systemImage: "lock.shield"
                    )
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("retired-legacy-task-migration-status")
                }
                Spacer(minLength: 0)
                if task.status != .pausing, task.status != .stopping,
                   task.status.isActive || task.status == .awaitingSelection || task.status == .paused || task.status == .blocked || task.status == .failed {
                    Button("End Task…", systemImage: "stop.circle", role: .destructive) {
                        showingEndConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .help("End agent work while preserving progress and project files")
                    .accessibilityIdentifier("end-task-button")
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial)
    }

    private func progressCard(_ task: LoopTask) -> some View {
        let live = controller.liveAccumulatedSeconds(for: task)
        let progress = min(1, live / max(1, task.targetSeconds))
        let remaining = max(0, task.targetSeconds - live)
        let workColor: Color = task.status.isWorking ? .accentColor : .secondary
        return HStack(alignment: .top, spacing: 22) {
            RuntimeClock(
                progress: progress,
                remainingSeconds: remaining,
                isWorking: task.status.isWorking,
                targetReached: live >= task.targetSeconds,
                color: workColor
            )
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    HStack(spacing: 8) {
                        if task.status.isWorking { CircularWorkingIndicator(color: .accentColor, size: 14) }
                        Text(task.status.title).font(.title3).fontWeight(.semibold)
                    }
                    Spacer()
                    if live >= task.targetSeconds, task.status.isWorking {
                        Text("Runtime reached · finishing evidence")
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(task.stage).font(.subheadline).foregroundStyle(.secondary)
                if task.status == .blocked {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.externalBlockerKind?.title ?? "External action required")
                                .font(.subheadline).fontWeight(.semibold)
                            if let retry = task.externalBlockerRetryAfter {
                                Text("Available again after \(retry.formatted(date: .abbreviated, time: .shortened)).")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let detail = task.externalBlockerMessage, !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(3).textSelection(.enabled)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    metric(live.compactDuration, "Active Sub Agent")
                    Divider().frame(height: 32)
                    metric(task.targetSeconds.compactDuration, "Hard target")
                    Divider().frame(height: 32)
                    metric("\(task.iteration)", "Iterations")
                    Divider().frame(height: 32)
                    metric("\(task.officialInteractions)", "Instructions")
                    Spacer()
                }
                HStack(spacing: 7) {
                    configPill("Control · \(task.resolvedControlAgent.displayName)", symbol: "point.3.connected.trianglepath.dotted")
                    configPill("Sub Agent · \(task.resolvedSubAgent.displayName)", symbol: "hammer.fill")
                    if let reasoning = task.resolvedSubAgent.reasoningEffort, !reasoning.isEmpty {
                        configPill(reasoning.capitalized, symbol: "brain")
                    }
                    configPill(task.workerAccessMode.title, symbol: task.workerAccessMode == .fullAccess ? "lock.open" : "folder.badge.gearshape")
                    Spacer()
                }
            }
        }
        .padding(19)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 100, alignment: .leading)
    }

    private func configPill(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private func deliveryGatesCard(_ task: LoopTask) -> some View {
        let live = controller.liveAccumulatedSeconds(for: task)
        return HStack(spacing: 18) {
            gate("Runtime", complete: live >= task.targetSeconds, symbol: "timer")
            gate("Code review", complete: task.supervisorCompletionApproved == true, symbol: "checkmark.seal")
            gate("Visual proof", complete: !task.needsVisualAudit || task.visualAuditPassed == true, symbol: "eye")
            gate("Status page", complete: task.completionReportPath != nil, symbol: "safari")
            Spacer()
            Text(gateSummary(task)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: 310, alignment: .trailing)
        }
        .padding(16)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gate(_ title: String, complete: Bool, symbol: String) -> some View {
        Label(title, systemImage: complete ? "checkmark.circle.fill" : symbol)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(complete ? .green : .secondary)
    }

    private func gateSummary(_ task: LoopTask) -> String {
        if task.status == .completed { return "All required evidence is verified." }
        if task.supervisorCompletionApproved != true { return "Local review is checking the goal, code, and real outcomes." }
        if task.needsVisualAudit && task.visualAuditPassed != true { return "Fresh visual evidence is still required." }
        return "Quality gates passed; the hard runtime or delivery report remains."
    }

    private func goalCard(_ task: LoopTask) -> some View {
        DisclosureGroup("Goal and contract") {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.request).textSelection(.enabled)
                if task.effectiveRequest != task.request {
                    Divider()
                    Label("Audited execution brief", systemImage: "checkmark.seal")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    Text(task.effectiveRequest).textSelection(.enabled)
                    if let summary = task.missionRewriteAuditSummary {
                        Text(summary).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text({
                    switch task.resolvedExecutionMode {
                    case .autoGraph:
                        return "The Main Graph Agent dynamically decomposes and audits the goal. Every node must pass its own evidence review, and the integrated project must pass a final whole-graph audit."
                    case .parallelCandidates:
                        return "Every candidate independently completes the full goal in an isolated Git worktree and satisfies its own active-work target. Only one evidence-reviewed winner is applied to the primary project."
                    case .singleLoop:
                        return task.quality.contract
                    }
                }())
                .font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.top, 10)
        }
        .padding(16)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct ParallelCandidateOverviewCard: View {
    let task: LoopTask
    let clock: Date

    private var candidates: [GraphLoopNode] {
        task.graphState?.nodes.filter { $0.id.hasPrefix("candidate-") } ?? []
    }

    private var completed: Int {
        candidates.filter { $0.status == .completed }.count
    }

    private var liveWork: TimeInterval {
        candidates.reduce(0) { $0 + $1.liveActiveSeconds(at: clock) }
    }

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 7)
                Circle()
                    .trim(
                        from: 0,
                        to: candidates.isEmpty
                            ? 0
                            : Double(completed) / Double(candidates.count)
                    )
                    .stroke(
                        task.status == .awaitingSelection ? Color.orange : Color.accentColor,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if task.status.isWorking {
                    CircularWorkingIndicator(color: .secondary, size: 19)
                } else {
                    Text("\(completed)/\(max(candidates.count, task.resolvedParallelCandidateCount))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.status.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(task.stage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("Parallel Candidates")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                }
                HStack(spacing: 22) {
                    metric("\(completed)/\(candidates.count)", "Ready results")
                    metric(task.targetSeconds.compactDuration, "Each candidate")
                    metric(liveWork.compactDuration, "Total active work")
                    metric(task.resolvedParallelSelectionMode.title, "Winner")
                    metric("Git worktrees", "Isolation")
                    Spacer()
                }
                if let winner = task.selectedCandidateID {
                    Label(
                        "\(winner.replacingOccurrences(of: "-", with: " ").capitalized) retained · \(task.parallelSelectionSummary ?? "final audit in progress")",
                        systemImage: "trophy.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
        }
        .padding(19)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ParallelCandidateGrid: View {
    let task: LoopTask
    let clock: Date
    let onInspect: (GraphLoopNode) -> Void

    private var candidates: [GraphLoopNode] {
        task.graphState?.nodes.filter { $0.id.hasPrefix("candidate-") } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Independent results", systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Spacer()
                Text(
                    task.status == .awaitingSelection
                        ? "Legacy candidate selection retired"
                        : "Candidates cannot inspect one another"
                )
                .font(.caption)
                .foregroundStyle(task.status == .awaitingSelection ? .orange : .secondary)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(candidates) { candidate in
                    candidateCard(candidate)
                }
            }
        }
        .padding(17)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
    }

    private func candidateCard(_ candidate: GraphLoopNode) -> some View {
        let live = candidate.liveActiveSeconds(at: clock)
        let progress = min(1, live / max(1, task.targetSeconds))
        let selected = task.selectedCandidateID == candidate.id
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: selected ? "trophy.fill" : statusSymbol(candidate.status))
                    .foregroundStyle(selected ? .yellow : statusColor(candidate.status))
                Text(candidate.title).font(.headline)
                Spacer()
                Text(candidate.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(candidate.status == .completed ? .green : Color.accentColor)
            HStack {
                Text("\(live.compactDuration) / \(task.targetSeconds.compactDuration)")
                Spacer()
                Text("Iteration \(candidate.iteration)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(
                candidate.lastReview.isEmpty
                    ? candidate.currentInstruction
                    : candidate.lastReview
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            HStack {
                Button("Inspect") { onInspect(candidate) }
                    .buttonStyle(.borderless)
                Spacer()
                if selected {
                    Label("Retained", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(
            selected ? Color.yellow.opacity(0.055) : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.yellow.opacity(0.35) : ForgeStyle.hairline)
        )
    }

    private func statusSymbol(_ status: GraphNodeStatus) -> String {
        switch status {
        case .completed: return "checkmark.circle.fill"
        case .blocked, .failed: return "exclamationmark.triangle.fill"
        case .superseded: return "xmark.circle.fill"
        case .running, .preparing, .auditing, .integrating: return "circle.dotted"
        case .waiting: return "circle"
        }
    }

    private func statusColor(_ status: GraphNodeStatus) -> Color {
        switch status {
        case .completed: return .green
        case .blocked, .failed, .superseded: return .red
        case .running, .preparing, .auditing, .integrating: return .secondary
        case .waiting: return Color.secondary.opacity(0.55)
        }
    }
}

private struct GraphOverviewCard: View {
    let task: LoopTask
    let clock: Date

    private var graph: GraphLoopState? { task.graphState }

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: task.progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if task.status.isWorking {
                    CircularWorkingIndicator(color: .secondary, size: 19)
                } else {
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption).fontWeight(.semibold).monospacedDigit()
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(graph?.phase.title ?? "Preparing the graph")
                            .font(.title3).fontWeight(.semibold)
                        Text(task.stage)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("Auto Graph Loop")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                }
                HStack(spacing: 22) {
                    graphMetric("\(revealedCompletedCount)/\(activeRevealedNodes.count)", "Assigned nodes")
                    graphMetric(currentBatchTitle, "Frontier")
                    graphMetric("\(graph?.workingNodeCount ?? 0)", "Working now")
                    graphMetric(liveActive.compactDuration, "Node-agent work")
                    graphMetric("\(graph?.mainInteractionCount ?? 0)", "Main reviews")
                    if let replanned = graph?.supersededNodeCount, replanned > 0 {
                        graphMetric("\(replanned)", "Replanned")
                    }
                    Spacer()
                }
            }
        }
        .padding(19)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
    }

    private var liveActive: TimeInterval {
        graph?.nodes.reduce(0) { $0 + $1.liveActiveSeconds(at: clock) } ?? 0
    }

    private var revealedNodes: [GraphLoopNode] {
        graph.map { GraphSchedulingPolicy.revealedNodes(state: $0) } ?? []
    }

    private var revealedCompletedCount: Int {
        activeRevealedNodes.filter(GraphSchedulingPolicy.isAuditedAndIntegrated).count
    }

    private var activeRevealedNodes: [GraphLoopNode] {
        revealedNodes.filter(GraphSchedulingPolicy.isActive)
    }

    private var currentBatchTitle: String {
        guard let graph else { return "Preparing" }
        let activeGroups = GraphSchedulingPolicy.activeJoinGroupIDs(state: graph)
        if activeGroups.isEmpty {
            return "Complete"
        }
        return activeGroups.count == 1
            ? "1 join group"
            : "\(activeGroups.count) join groups"
    }

    private func graphMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline).fontWeight(.semibold).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

enum GraphViewportFitPolicy {
    struct Metrics: Equatable {
        let canvasWidth: CGFloat
        let nodeWidth: CGFloat
        let columnGap: CGFloat
        let columnsPerViewport: Int
        let pageCount: Int
        let fitsViewport: Bool
    }

    static func resolve(
        viewportWidth: CGFloat,
        levelCount: Int,
        preferredNodeWidth: CGFloat,
        minimumNodeWidth: CGFloat,
        preferredColumnGap: CGFloat,
        minimumColumnGap: CGFloat,
        fixedTerminalAndInsetWidth: CGFloat
    ) -> Metrics {
        let viewportWidth = max(1, viewportWidth)
        let levelCount = max(1, levelCount)
        let availableForColumns = max(
            minimumNodeWidth,
            viewportWidth - fixedTerminalAndInsetWidth
        )
        let maximumColumnsPerViewport = max(
            1,
            Int(
                floor(
                    (availableForColumns + minimumColumnGap)
                        / (minimumNodeWidth + minimumColumnGap)
                )
            )
        )
        let columnsPerViewport = min(levelCount, maximumColumnsPerViewport)
        let columnsPerViewportValue = CGFloat(columnsPerViewport)
        let gapCount = CGFloat(max(0, columnsPerViewport - 1))
        let widthAtMinimumGap = (
            viewportWidth
                - fixedTerminalAndInsetWidth
                - gapCount * minimumColumnGap
        ) / columnsPerViewportValue
        let resolvedNodeWidth = min(
            preferredNodeWidth,
            max(minimumNodeWidth, widthAtMinimumGap)
        )
        let remainingForGaps = viewportWidth
            - fixedTerminalAndInsetWidth
            - columnsPerViewportValue * resolvedNodeWidth
        let resolvedColumnGap: CGFloat
        if gapCount > 0 {
            resolvedColumnGap = min(
                preferredColumnGap,
                max(minimumColumnGap, remainingForGaps / gapCount)
            )
        } else {
            resolvedColumnGap = 0
        }
        let requiredWidth = fixedTerminalAndInsetWidth
            + columnsPerViewportValue * resolvedNodeWidth
            + gapCount * resolvedColumnGap
        let pageCount = Int(
            ceil(Double(levelCount) / Double(columnsPerViewport))
        )
        return Metrics(
            canvasWidth: viewportWidth * CGFloat(pageCount),
            nodeWidth: resolvedNodeWidth,
            columnGap: resolvedColumnGap,
            columnsPerViewport: columnsPerViewport,
            pageCount: pageCount,
            fitsViewport: pageCount == 1 && requiredWidth <= viewportWidth + 0.5
        )
    }
}

enum GraphVerticalViewportPolicy {
    struct Metrics: Equatable {
        let canvasHeight: CGFloat
        let viewportHeight: CGFloat
        let rowsPerViewport: Int
        let pageCount: Int
        let hasContinuation: Bool
    }

    static func resolve(
        maximumRows: Int,
        nodeHeight: CGFloat,
        rowGap: CGFloat,
        expanded: Bool
    ) -> Metrics {
        let maximumRows = max(1, maximumRows)
        let showEveryRow = expanded
        let rowsPerViewport = showEveryRow ? maximumRows : 1
        let rowStep = nodeHeight + rowGap
        let canvasHeight = CGFloat(maximumRows) * rowStep + 20
        let viewportHeight = CGFloat(rowsPerViewport) * rowStep + 20
        let pageCount = Int(
            ceil(Double(maximumRows) / Double(rowsPerViewport))
        )
        return Metrics(
            canvasHeight: canvasHeight,
            viewportHeight: viewportHeight,
            rowsPerViewport: rowsPerViewport,
            pageCount: pageCount,
            hasContinuation: pageCount > 1
        )
    }
}

private struct GraphLoopMap: View {
    let graph: GraphLoopState
    let clock: Date
    let expanded: Bool
    let onSelect: (GraphLoopNode) -> Void
    let onExpand: (() -> Void)?

    private var preferredNodeWidth: CGFloat { expanded ? 240 : 196 }
    private var minimumNodeWidth: CGFloat { expanded ? 200 : 160 }
    private var nodeHeight: CGFloat { expanded ? 132 : 108 }
    private var preferredColumnGap: CGFloat { expanded ? 96 : 72 }
    private var minimumColumnGap: CGFloat { expanded ? 40 : 24 }
    private var rowGap: CGFloat { expanded ? 32 : 24 }
    private let fixedTerminalAndInsetWidth: CGFloat = 192

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Execution Graph", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                let activeGroups = GraphSchedulingPolicy.activeJoinGroupIDs(state: graph)
                if !activeGroups.isEmpty {
                    Text(
                        "\(activeGroups.count) active join group\(activeGroups.count == 1 ? "" : "s") · \(visibleNodes.count) nodes assigned"
                    )
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(graph.phase == .executing ? "Awaiting Main Graph decision" : "Current graph complete")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let onExpand {
                    Button {
                        onExpand()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Expand graph")
                    .accessibilityLabel("Expand Graph")
                    .accessibilityIdentifier("expand-execution-graph")
                }
            }

            GeometryReader { geometry in
                let metrics = GraphViewportFitPolicy.resolve(
                    viewportWidth: geometry.size.width,
                    levelCount: maximumLevel + 1,
                    preferredNodeWidth: preferredNodeWidth,
                    minimumNodeWidth: minimumNodeWidth,
                    preferredColumnGap: preferredColumnGap,
                    minimumColumnGap: minimumColumnGap,
                    fixedTerminalAndInsetWidth: fixedTerminalAndInsetWidth
                )
                let verticalMetrics = GraphVerticalViewportPolicy.resolve(
                    maximumRows: maximumRows,
                    nodeHeight: nodeHeight,
                    rowGap: rowGap,
                    expanded: expanded
                )
                let layoutPositions = positions(
                    canvasWidth: metrics.canvasWidth,
                    canvasHeight: verticalMetrics.canvasHeight,
                    viewportWidth: geometry.size.width,
                    metrics: metrics,
                    alignRowsToTop: verticalMetrics.hasContinuation
                )
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            drawEdges(
                                context: &context,
                                positions: layoutPositions,
                                nodeWidth: metrics.nodeWidth
                            )
                        }
                        .frame(
                            width: metrics.canvasWidth,
                            height: verticalMetrics.canvasHeight
                        )

                        GraphTerminalNode(title: "Begin", symbol: "play.fill", color: .accentColor)
                            .position(layoutPositions["__begin"] ?? .zero)

                        ForEach(visibleNodes) { node in
                            GraphNodeCard(node: node, clock: clock) {
                                onSelect(node)
                            }
                            .frame(width: metrics.nodeWidth, height: nodeHeight)
                            .position(layoutPositions[node.id] ?? .zero)
                        }

                        GraphTerminalNode(
                            title: "End",
                            symbol: graphComplete ? "checkmark" : "flag.fill",
                            color: graphComplete ? .green : .secondary
                        )
                        .position(layoutPositions["__end"] ?? .zero)
                    }
                    .frame(
                        width: metrics.canvasWidth,
                        height: verticalMetrics.canvasHeight
                    )
                }
                .scrollIndicators(.hidden)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        onExpand?()
                    }
                )
                .overlay(alignment: .trailing) {
                    if metrics.pageCount > 1 {
                        Label("Next levels", systemImage: "chevron.right")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if verticalMetrics.hasContinuation {
                        Label("More nodes below", systemImage: "chevron.down")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.trailing, 8)
                            .padding(.bottom, 3)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: verticalViewportHeight)
        }
        .padding(18)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ForgeStyle.hairline))
        .accessibilityHint(onExpand == nil ? "" : "Double-click the graph background to expand it")
    }

    private var graphComplete: Bool {
        GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph)
    }
    private var visibleNodes: [GraphLoopNode] {
        GraphSchedulingPolicy.revealedNodes(state: graph)
    }
    private var levelMap: [String: Int] { GraphLayoutPolicy.levels(for: graph.nodes) }
    private var maximumLevel: Int { levelMap.values.max() ?? 0 }
    private var grouped: [Int: [GraphLoopNode]] {
        Dictionary(grouping: visibleNodes) { levelMap[$0.id] ?? 0 }
    }
    private var maximumRows: Int { max(1, grouped.values.map(\.count).max() ?? 1) }
    private var verticalViewportHeight: CGFloat {
        GraphVerticalViewportPolicy.resolve(
            maximumRows: maximumRows,
            nodeHeight: nodeHeight,
            rowGap: rowGap,
            expanded: expanded
        ).viewportHeight
    }
    private func positions(
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        viewportWidth: CGFloat,
        metrics: GraphViewportFitPolicy.Metrics,
        alignRowsToTop: Bool
    ) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        let step = metrics.nodeWidth + metrics.columnGap
        result["__begin"] = CGPoint(x: 44, y: canvasHeight / 2)
        for level in 0...maximumLevel {
            let nodes = (grouped[level] ?? []).sorted { $0.createdAt < $1.createdAt }
            let total = CGFloat(nodes.count) * nodeHeight + CGFloat(max(0, nodes.count - 1)) * rowGap
            let startY = alignRowsToTop
                ? nodeHeight / 2 + 22
                : max(
                    nodeHeight / 2 + 8,
                    (canvasHeight - total) / 2 + nodeHeight / 2
                )
            let page = level / metrics.columnsPerViewport
            let columnOnPage = level % metrics.columnsPerViewport
            for (index, node) in nodes.enumerated() {
                result[node.id] = CGPoint(
                    x: CGFloat(page) * viewportWidth
                        + metrics.nodeWidth / 2
                        + 96
                        + CGFloat(columnOnPage) * step,
                    y: startY + CGFloat(index) * (nodeHeight + rowGap)
                )
            }
        }
        result["__end"] = CGPoint(
            x: canvasWidth - 44,
            y: canvasHeight / 2
        )
        return result
    }

    private func drawEdges(
        context: inout GraphicsContext,
        positions: [String: CGPoint],
        nodeWidth: CGFloat
    ) {
        for node in graph.nodes {
            guard let destination = positions[node.id] else { continue }
            let sources = node.dependencies.isEmpty ? ["__begin"] : node.dependencies
            for sourceID in sources {
                guard let source = positions[sourceID] else { continue }
                drawArrow(
                    context: &context,
                    from: CGPoint(x: source.x + (sourceID == "__begin" ? 28 : nodeWidth / 2), y: source.y),
                    to: CGPoint(x: destination.x - nodeWidth / 2, y: destination.y),
                    disposition: GraphPresentationPolicy.incomingEdgeDisposition(for: node)
                )
            }
        }
        if GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph) {
            let terminals = Set(GraphPresentationPolicy.terminalNodeIDs(state: graph))
            for leaf in visibleNodes where terminals.contains(leaf.id) {
                guard let source = positions[leaf.id],
                      let destination = positions["__end"] else { continue }
                drawArrow(
                    context: &context,
                    from: CGPoint(x: source.x + nodeWidth / 2, y: source.y),
                    to: CGPoint(x: destination.x - 28, y: destination.y),
                    disposition: .completed
                )
            }
        }
    }

    private func drawArrow(
        context: inout GraphicsContext,
        from source: CGPoint,
        to destination: CGPoint,
        disposition: GraphPresentationPolicy.EdgeDisposition
    ) {
        let middle = (source.x + destination.x) / 2
        var path = Path()
        path.move(to: source)
        path.addCurve(
            to: destination,
            control1: CGPoint(x: middle, y: source.y),
            control2: CGPoint(x: middle, y: destination.y)
        )
        let color: Color = switch disposition {
        case .completed: .green.opacity(0.62)
        case .superseded: .red.opacity(0.70)
        case .pending: .secondary.opacity(0.30)
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        var arrow = Path()
        arrow.move(to: destination)
        arrow.addLine(to: CGPoint(x: destination.x - 7, y: destination.y - 4))
        arrow.addLine(to: CGPoint(x: destination.x - 7, y: destination.y + 4))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }
}

private struct ExpandedGraphSheet: View {
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @ObservedObject var store: TaskStore
    let clock: Date
    @State private var selectedGraphNode: GraphLoopNode?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Execution Graph")
                        .font(.title2).fontWeight(.semibold)
                    Text("Each completion is incrementally reviewed; only same-group refinements may appear before the full join barrier. Downstream work waits for group review, and End waits for delivery.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("close-expanded-graph")
            }
            .padding(20)
            Divider()

            if let task = store.task(id: taskID), let graph = task.graphState {
                GraphLoopMap(
                    graph: graph,
                    clock: clock,
                    expanded: true,
                    onSelect: { selectedGraphNode = $0 },
                    onExpand: nil
                )
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .sheet(item: $selectedGraphNode) { node in
                    GraphNodeInspector(
                        task: task,
                        nodeID: node.id,
                        store: store,
                        clock: clock
                    )
                }
            } else {
                ContentUnavailableView(
                    "Graph unavailable",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1_080, idealWidth: 1_280, minHeight: 680, idealHeight: 780)
    }
}

private struct GraphTerminalNode: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption).fontWeight(.bold)
            Text(title).font(.caption2).fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .frame(width: 56, height: 56)
        .background(color.opacity(0.10), in: Circle())
        .overlay(Circle().stroke(color.opacity(0.30)))
    }
}

private struct GraphNodeCard: View {
    let node: GraphLoopNode
    let clock: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    statusIndicator
                    Text(node.title)
                        .font(.caption).fontWeight(.semibold)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(node.objective)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Label(
                        "\(node.iteration)",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Label(
                        node.liveActiveSeconds(at: clock).compactDuration,
                        systemImage: "sum"
                    )
                    Label(
                        node.liveCurrentIterationActiveSeconds(at: clock).compactDuration,
                        systemImage: "stopwatch"
                    )
                    .foregroundStyle(
                        node.status == .running
                            ? Color.accentColor
                            : Color.secondary
                    )
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if node.status == .blocked {
                    Label(
                        "Blocked \(node.liveBlockedSeconds(at: clock).compactDuration)",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(.red)
                } else if node.status == .superseded {
                    Label("Stopped by plan review", systemImage: "xmark.circle.fill")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(.red)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(nodeBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        nodeBorder,
                        lineWidth: node.status == .blocked || node.status == .superseded ? 1.4 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(node.title), \(node.status.title), \(GraphIterationHistoryPolicy.countLabel(node.iteration)), all iterations \(node.liveActiveSeconds(at: clock).compactDuration), this iteration \(node.liveCurrentIterationActiveSeconds(at: clock).compactDuration)"
        )
        .accessibilityIdentifier("graph-node-\(node.id)")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if node.status == .completed {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if node.status == .superseded {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if node.status == .blocked || node.status == .failed {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else if node.status.isWorking {
            CircularWorkingIndicator(color: .secondary, size: 12)
        } else {
            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 7, height: 7)
        }
    }

    private var nodeBackground: Color {
        switch node.status {
        case .completed: return .green.opacity(0.065)
        case .blocked, .failed, .superseded: return .red.opacity(0.075)
        case .running, .auditing, .integrating, .preparing: return .secondary.opacity(0.07)
        case .waiting: return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var nodeBorder: Color {
        switch node.status {
        case .completed: return .green.opacity(0.35)
        case .blocked, .failed, .superseded: return .red.opacity(0.55)
        default: return ForgeStyle.hairline
        }
    }
}

private struct GraphMainControlCard: View {
    let task: LoopTask

    private var graph: GraphLoopState? { task.graphState }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Main Graph Agent", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                Text("\(graph?.mainInteractionCount ?? 0) reviews")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 10) {
                ControlMetric(
                    title: "Phase",
                    value: graph?.phase.title ?? "Preparing",
                    symbol: "point.3.connected.trianglepath.dotted"
                )
                ControlMetric(
                    title: "Parallelism",
                    value: graph?.supportsParallelWorktrees == true
                        ? "Isolated worktrees"
                        : "Safe exclusive writes",
                    symbol: "arrow.triangle.branch"
                )
                ControlMetric(
                    title: "Graph",
                    value: graph.map {
                        "\(GraphSchedulingPolicy.revealedNodes(state: $0).count) assigned"
                    } ?? "Preparing",
                    symbol: "circle.grid.cross"
                )
            }
            if let summary = graph?.mainLastReview, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Latest graph decision")
                        .font(.caption).fontWeight(.semibold)
                    Text(summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(5).textSelection(.enabled)
                }
                .padding(13)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            if let plan = graph?.planSummary, !plan.isEmpty {
                DisclosureGroup("Graph plan") {
                    Text(plan)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 7)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.20)))
    }
}

private struct GraphNodeInspector: View {
    @Environment(\.dismiss) private var dismiss
    let task: LoopTask
    let nodeID: String
    @ObservedObject var store: TaskStore
    let clock: Date

    private var node: GraphLoopNode? {
        store.task(id: task.id)?.graphState?.nodes.first { $0.id == nodeID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node?.title ?? "Graph node")
                        .font(.title2).fontWeight(.semibold)
                    Text(node?.status.title ?? "Unavailable")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let node {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Main Graph Agent instruction", systemImage: "arrow.down.right.circle.fill")
                                .font(.headline)
                            Text(node.currentInstruction)
                                .font(.subheadline)
                                .textSelection(.enabled)
                            HStack(spacing: 14) {
                                Label(
                                    GraphIterationHistoryPolicy.countLabel(node.iteration),
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                                Label(
                                    "All iterations \(node.liveActiveSeconds(at: clock).compactDuration)",
                                    systemImage: "sum"
                                )
                                Label(
                                    "This iteration \(node.liveCurrentIterationActiveSeconds(at: clock).compactDuration)",
                                    systemImage: "stopwatch"
                                )
                                Label(node.workspaceStrategy?.title ?? "Preparing", systemImage: "square.stack.3d.up")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if !node.lastReview.isEmpty {
                                Text(node.lastReview)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                            }
                            if node.status == .superseded {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Replanned branch", systemImage: "xmark.circle.fill")
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(.red)
                                    Text(node.supersededReason ?? "The incremental join review proved that continuing this branch no longer had sufficient value.")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if let replacements = node.supersededByNodeIDs,
                                       !replacements.isEmpty {
                                        Text("Replacement: \(replacements.joined(separator: ", "))")
                                            .font(.caption2).foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(10)
                                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                        .padding(16)
                        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 13))

                        GraphIterationHistoryCard(task: task, node: node)

                        ActivityLog(entries: node.logs, contextLabel: "Node loop activity")
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 760, height: 680)
    }
}

private struct GraphIterationHistoryCard: View {
    let task: LoopTask
    let node: GraphLoopNode

    private var records: [GraphNodeIterationRecord] {
        GraphIterationHistoryPolicy.records(task: task, node: node)
    }

    private var decisionCount: Int {
        records.filter { $0.decision != .pending }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Iteration history", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                Text(
                    "\(records.count) iteration\(records.count == 1 ? "" : "s")"
                        + " · \(decisionCount) Main Agent decision\(decisionCount == 1 ? "" : "s")"
                )
                    .font(.caption).foregroundStyle(.secondary)
            }
            if records.isEmpty {
                Text("Iteration details will appear after the first Sub Agent turn.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    iterationRow(record)
                }
            }
        }
        .padding(16)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(ForgeStyle.hairline))
    }

    private func iterationRow(_ record: GraphNodeIterationRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Iteration \(record.number)")
                    .font(.subheadline).fontWeight(.semibold)
                Text(record.decision.title)
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(decisionColor(record.decision))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(
                        decisionColor(record.decision).opacity(0.10),
                        in: Capsule()
                    )
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.activeSeconds.map { $0.compactDuration + " active" } ?? "Legacy timing")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            iterationSection("Instruction", text: record.instruction)
            iterationSection(
                "Main Agent review",
                text: record.mainReview.isEmpty
                    ? "Awaiting a terminal result and Main Agent decision."
                    : record.mainReview
            )
            if !record.nextInstruction.isEmpty,
               record.nextInstruction != record.instruction {
                iterationSection("Next instruction", text: record.nextInstruction)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func iterationSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary)
            Text(text)
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func decisionColor(_ decision: GraphIterationDecision) -> Color {
        switch decision {
        case .approved: return .green
        case .continueWork: return .blue
        case .recovery: return .orange
        case .externalBlocker, .superseded: return .red
        case .pending: return .secondary
        }
    }
}

private struct ActivityLog: View {
    let entries: [TaskLogEntry]
    var contextLabel = "Sub Agent work"
    @State private var earlierExpanded = false
    @State private var commandsExpanded = false

    private var stageStart: Int {
        entries.lastIndex {
            $0.kind == .system && (
                $0.message.localizedCaseInsensitiveContains("Starting official Codex iteration")
                    || $0.message.localizedCaseInsensitiveContains("Starting Sub Agent iteration")
            )
        } ?? max(0, entries.count - 18)
    }

    private var currentMilestones: [TaskLogEntry] {
        guard !entries.isEmpty else { return [] }
        return Array(entries[stageStart...]).filter(isMilestone).suffixArray(10)
    }

    private var recentCommands: [TaskLogEntry] {
        guard !entries.isEmpty else { return [] }
        return Array(entries[stageStart...]).filter { $0.kind == .command }.suffixArray(5)
    }

    private var earlierMilestones: [TaskLogEntry] {
        guard stageStart > 0 else { return [] }
        return Array(entries[..<stageStart]).filter(isMilestone).suffixArray(80)
    }

    private func isMilestone(_ entry: TaskLogEntry) -> Bool {
        let kind = codexPresentationKind(for: entry.message, fallback: entry.kind)
        switch kind {
        case .agent, .audit, .warning, .error: return true
        case .system:
            let text = entry.message.lowercased()
            let signals = ["starting official codex", "starting sub agent", "loop control agent", "architecture:", "recovered", "model ready", "codex session", "checking", "delivery report"]
            return signals.contains(where: text.contains)
        case .command, .control: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text(contextLabel).font(.caption).foregroundStyle(.secondary)
            }

            if let latest = currentMilestones.last {
                ActivityMilestoneRow(entry: latest, emphasized: true)
            } else {
                Text("Work activity will appear when the loop begins.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            let preceding = Array(currentMilestones.dropLast())
            if !preceding.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(preceding) { entry in
                        ActivityMilestoneRow(entry: entry, emphasized: false)
                    }
                }
            }

            if !recentCommands.isEmpty {
                DisclosureGroup(isExpanded: $commandsExpanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(recentCommands) { entry in RecentCommandRow(entry: entry) }
                    }
                    .padding(.top, 6)
                } label: {
                    Label(
                        "\(recentCommands.count) recent tool result\(recentCommands.count == 1 ? "" : "s")",
                        systemImage: "terminal"
                    )
                    .font(.caption).foregroundStyle(.tertiary)
                }
            }

            if !earlierMilestones.isEmpty {
                DisclosureGroup(isExpanded: $earlierExpanded) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(earlierMilestones) { entry in LogRow(entry: entry) }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Earlier activity").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(ForgeStyle.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ForgeStyle.hairline))
    }
}

private struct LoopForgeControlLog: View {
    let task: LoopTask
    @State private var historyExpanded = false

    private var briefs: [TaskLogEntry] { task.logs.filter { $0.kind == .control } }
    private var latestAudit: TaskLogEntry? { task.logs.last { $0.kind == .audit } }
    private var latestBrief: TaskLogEntry? { briefs.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("LoopForge Control", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Text("\(task.officialInteractions) instruction\(task.officialInteractions == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }

            HStack(spacing: 10) {
                ControlMetric(
                    title: "Now",
                    value: concise(task.stage, limit: 92),
                    symbol: task.status.isActive ? "circle.dotted.circle.fill" : "pause.circle"
                )
                ControlMetric(
                    title: "Decision",
                    value: latestAudit.map { decisionLabel($0.message) } ?? "Awaiting first audit",
                    symbol: latestAudit == nil ? "hourglass" : "checkmark.seal"
                )
                ControlMetric(
                    title: "Loop",
                    value: "Iteration \(max(1, task.iteration + (task.status.isActive ? 1 : 0)))",
                    symbol: "arrow.triangle.2.circlepath"
                )
            }

            if let latestAudit {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark.seal").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Latest control review").font(.caption).fontWeight(.semibold)
                        Text(concise(latestAudit.message, limit: 360))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }

            if let latestBrief {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Next instruction", systemImage: "arrow.right.circle.fill")
                        .font(.caption).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                    Text(ControlBriefParser.action(from: latestBrief.message))
                        .font(.subheadline).fontWeight(.medium)
                        .lineLimit(5).textSelection(.enabled)
                    if let verification = ControlBriefParser.verification(from: latestBrief.message) {
                        Label(verification, systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                    DisclosureGroup("Full instruction") {
                        Text(String(latestBrief.message.prefix(30_000)))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 7)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
            } else {
                Text(task.iteration > 0
                     ? "Detailed control briefs begin with the next interaction; earlier work remains in Activity."
                     : "The first supervised instruction will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            let history = Array(briefs.dropLast())
            if !history.isEmpty {
                DisclosureGroup(isExpanded: $historyExpanded) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                            ControlBriefRow(entry: entry, number: index + 1, isLatest: false)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("\(history.count) earlier control instruction\(history.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.16)))
    }

    private func concise(_ raw: String, limit: Int) -> String {
        String(raw.replacingOccurrences(of: "\n", with: " ").prefix(limit))
    }

    private func decisionLabel(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("approve") { return "Approved" }
        if lower.contains("continue") { return "Continue and verify" }
        return "Review complete"
    }
}

private struct ControlMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption).foregroundStyle(Color.accentColor).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(value).font(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

private enum ControlBriefParser {
    static func action(from raw: String) -> String {
        section(
            in: raw,
            markers: ["REQUIRED NEXT DEVELOPMENT ACTION", "PRIORITIZED NEXT ACTIONS", "AUDITOR DIRECTIVE"]
        ) ?? preview(raw)
    }

    static func verification(from raw: String) -> String? {
        section(in: raw, markers: ["REQUIRED VERIFICATION"])
    }

    private static func section(in raw: String, markers: [String]) -> String? {
        for marker in markers {
            guard let markerRange = raw.range(of: marker, options: .caseInsensitive) else { continue }
            let tail = raw[markerRange.upperBound...]
            let lines = tail.components(separatedBy: .newlines)
            var collected: [String] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    if !collected.isEmpty { break }
                    continue
                }
                if !collected.isEmpty,
                   trimmed == trimmed.uppercased(),
                   trimmed.rangeOfCharacter(from: .letters) != nil {
                    break
                }
                collected.append(trimmed)
                if collected.joined(separator: " ").count > 600 { break }
            }
            let result = collected.joined(separator: " ")
            if !result.isEmpty { return result }
        }
        return nil
    }

    private static func preview(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<") }
        return String((lines.dropFirst().first ?? lines.first ?? "Supervised development brief").prefix(600))
    }
}

private struct ControlBriefRow: View {
    let entry: TaskLogEntry
    let number: Int
    let isLatest: Bool
    @State private var expanded: Bool

    init(entry: TaskLogEntry, number: Int, isLatest: Bool) {
        self.entry = entry
        self.number = number
        self.isLatest = isLatest
        _expanded = State(initialValue: false)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(String(entry.message.prefix(30_000)))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 8)
        } label: {
            HStack(spacing: 9) {
                Text("\(number)")
                    .font(.caption2.bold()).foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24).background(Color.accentColor.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLatest ? "Current instruction" : "Instruction to Sub Agent")
                        .font(.subheadline).fontWeight(.medium)
                    Text(preview).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Self.formatter.string(from: entry.timestamp)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private var preview: String {
        ControlBriefParser.action(from: entry.message)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; return formatter
    }()
}

private struct ActivityMilestoneRow: View {
    let entry: TaskLogEntry
    let emphasized: Bool
    private var presentationKind: LogKind {
        codexPresentationKind(for: entry.message, fallback: entry.kind)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(emphasized ? 0.16 : 0.08))
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            .frame(width: emphasized ? 30 : 24, height: emphasized ? 30 : 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.caption).fontWeight(.semibold)
                    Spacer()
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(String(entry.message.replacingOccurrences(of: "\n", with: " ").prefix(emphasized ? 520 : 280)))
                    .font(emphasized ? .subheadline : .caption)
                    .foregroundStyle(emphasized ? .primary : .secondary)
                    .lineLimit(emphasized ? 4 : 2)
                    .textSelection(.enabled)
            }
        }
        .padding(emphasized ? 12 : 8)
        .background(
            emphasized ? color.opacity(0.055) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var title: String {
        switch presentationKind {
        case .agent: return "Sub Agent update"
        case .audit: return "Control review"
        case .warning: return "Attention"
        case .error: return "Action needed"
        default: return "Progress"
        }
    }

    private var icon: String {
        switch presentationKind {
        case .agent: return "hammer.fill"
        case .audit: return "checkmark.seal"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        default: return "circle.fill"
        }
    }

    private var color: Color {
        switch presentationKind {
        case .agent: return .blue
        case .audit: return .green
        case .warning: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
}

private struct RecentCommandRow: View {
    let entry: TaskLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chevron.right").frame(width: 14)
            Text(String(entry.message.replacingOccurrences(of: "\n", with: " ").prefix(360)))
                .lineLimit(2).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.vertical, 4)
    }
}

private struct LogRow: View {
    let entry: TaskLogEntry
    private var presentationKind: LogKind {
        codexPresentationKind(for: entry.message, fallback: entry.kind)
    }
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"; return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.formatter.string(from: entry.timestamp)).foregroundStyle(.tertiary).frame(width: 56, alignment: .leading)
            Image(systemName: icon).foregroundStyle(color).frame(width: 14)
            Text(entry.message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.vertical, 6)
        .background(presentationKind == .error ? Color.red.opacity(0.045) : .clear)
    }

    private var icon: String {
        switch presentationKind {
        case .system: return "gearshape"
        case .agent: return "sparkles"
        case .command: return "chevron.right"
        case .audit: return "checkmark.seal"
        case .control: return "point.3.connected.trianglepath.dotted"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var color: Color {
        switch presentationKind {
        case .agent: return .blue
        case .command: return .cyan
        case .audit: return .green
        case .control: return .purple
        case .warning: return .orange
        case .error: return .red
        case .system: return .secondary
        }
    }
}

private extension Array {
    func suffixArray(_ maximumLength: Int) -> [Element] { Array(suffix(maximumLength)) }
}
