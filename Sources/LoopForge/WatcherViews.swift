import AppKit
import SwiftUI

enum WatcherGuideStep: Int, CaseIterable {
    case target
    case project
    case cadence
    case continuity
    case model
    case safeguards
    case build

    var title: String {
        switch self {
        case .target: return "Describe the target"
        case .project: return "Choose its workspace"
        case .cadence: return "Set the cadence"
        case .continuity: return "Keep it continuous"
        case .model: return "Choose the Agent"
        case .safeguards: return "Verify authority"
        case .build: return "Build the Watcher"
        }
    }

    var symbol: String {
        switch self {
        case .target: return "scope"
        case .project: return "folder"
        case .cadence: return "clock"
        case .continuity: return "arrow.triangle.2.circlepath"
        case .model: return "cpu"
        case .safeguards: return "checkmark.shield"
        case .build: return "sparkles"
        }
    }

    var summary: String {
        switch self {
        case .target:
            return "State the recurring outcome in plain language. Include the condition, action, and evidence you expect."
        case .project:
            return "Use an existing project or create a dedicated folder. The pipeline, checkpoints, telemetry, and generated reports stay there."
        case .cadence:
            return "Routine pass runs the inexpensive deterministic pipeline. Agent review wakes the selected model to inspect evidence and adapt the pipeline."
        case .continuity:
            return "Notifications surface meaningful changes. Launch at login restores active watchers after a restart from their saved checkpoint."
        case .model:
            return "Choose one Codex, configured API, or downloaded local model. That exact selection is retained for building, reviews, and recovery."
        case .safeguards:
            return "A fresh read-only reviewer must approve the exact candidate artifacts. Completion also requires deterministic telemetry, checkpoint, verification, and goal-evidence receipts."
        case .build:
            return "LoopForge asks the Agent to create and verify a bounded local pipeline, then schedules it. You can pause, resume, inspect, or stop it at any time."
        }
    }

    var notes: [String] {
        switch self {
        case .target:
            return [
                "Be specific about what should be checked or processed.",
                "Say when to notify, repair, report, or finish."
            ]
        case .project:
            return [
                "Existing Project keeps work beside the system it operates.",
                "New Project is useful for a standalone monitor or batch pipeline."
            ]
        case .cadence:
            return [
                "Routine pass: frequent script run without model cost.",
                "Agent review: deeper analysis, never scheduled more often than every 2 hours.",
                "The Agent may safely tune both after observing real data."
            ]
        case .continuity:
            return [
                "Closing the window does not stop active watchers.",
                "Quitting saves state; the next launch resumes from the checkpoint."
            ]
        case .model:
            return [
                "Codex uses your authenticated ChatGPT account.",
                "API uses a tested provider connection; Local uses a verified download.",
                "Workspace Only keeps generated work inside the chosen project."
            ]
        case .safeguards:
            return [
                "The author and reviewer must have distinct conversation lineages.",
                "The reviewer is read-only and cannot repair or mutate the workspace.",
                "A COMPLETE marker alone has no completion authority.",
                "Telemetry, checkpoint bytes, verification results, goal coverage, and independent approval must remain digest-bound."
            ]
        case .build:
            return [
                "The first build includes policy checks and real verification.",
                "Only signals, failures, scheduled reviews, or your actions wake the Agent."
            ]
        }
    }
}

struct ContinuumSidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: WatcherStore
    @ObservedObject var controller: WatcherController
    @State private var pendingDeletion: ContinuumWatcher?

    var body: some View {
        VStack(spacing: 0) {
            ModuleSwitcher()

            Button {
                model.startNewWatcherFlow()
            } label: {
                Label("New Watcher", systemImage: "plus")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 42)
                    .background(
                        model.showingNewWatcher
                            ? Color.accentColor.opacity(0.13)
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .accessibilityIdentifier("new-watcher")

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.watchers) { watcher in
                        Button {
                            store.select(id: watcher.id)
                            model.showingNewWatcher = false
                        } label: {
                            ContinuumSidebarRow(
                                watcher: watcher,
                                selected: !model.showingNewWatcher
                                    && store.selectedWatcherID == watcher.id
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    URL(fileURLWithPath: watcher.workspacePath)
                                ])
                            }
                            Divider()
                            Button("Delete Watcher Record…", role: .destructive) {
                                pendingDeletion = watcher
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
            }

            Button {
                model.showWatcherGuide(startingAtCadence: true)
            } label: {
                Label("Watcher Guide", systemImage: "questionmark.circle")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("watcher-guide")

            Divider()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(controller.runningWatcherIDs.isEmpty ? Color.secondary : Color.green)
                        .frame(width: 8, height: 8)
                    Text(controller.runningWatcherIDs.isEmpty ? "Scheduler ready" : "Watcher engine active")
                        .font(.caption)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.codexConnection.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(model.codexConnection.isConnected ? "Codex Connected" : "Fallback providers available")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(13)
        }
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "Delete this watcher record?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let watcher = pendingDeletion {
                Button("Delete Record", role: .destructive) {
                    controller.delete(watcherID: watcher.id)
                    pendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The generated pipeline, checkpoint, telemetry, and project folder will be kept.")
        }
    }
}

private struct ContinuumSidebarRow: View {
    let watcher: ContinuumWatcher
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(watcher.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text(watcher.operationalStatusTitle)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if watcher.status.isWorking {
                WatcherSpinner(color: .accentColor)
            } else if watcher.requiresUserAttention {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Watching and needs attention")
            } else if watcher.status == .active {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Scheduled and healthy")
            } else if watcher.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            selected ? Color.accentColor.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch watcher.status {
        case .needsAttention: return .red
        case .completed: return .green
        default: return watcher.requiresUserAttention ? .red : .secondary
        }
    }
}

struct ContinuumNewWatcherView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Continuum Watcher")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Turn recurring work into a durable local pipeline. Agent intelligence wakes only when it adds value.")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                WatcherCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Target", systemImage: "scope")
                            .font(.headline)
                        TextEditor(text: $model.watcherDraftRequest)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 174)
                            .background(
                                Color(nsColor: .textBackgroundColor).opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(alignment: .topLeading) {
                                if model.watcherDraftRequest.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Try one of these:")
                                            .fontWeight(.medium)
                                        Text("• Check a service's error rate and notify me if it stays abnormal.")
                                        Text("• Process new data in a folder without handling anything twice.")
                                        Text("• Watch for an event condition, then generate a report.")
                                        Text("• Check data quality on a schedule and safely repair deterministic issues.")
                                        Text("• Run a long experiment, analyze each stage, and adjust its parameters.")
                                    }
                                        .font(.callout)
                                        .foregroundStyle(Color.secondary.opacity(0.68))
                                        .padding(.horizontal, 15)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .accessibilityIdentifier("watcher-request")
                        Text("Good fits: anomaly monitoring, condition tracking, large batch processing, scheduled checks, and long-running operational work.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                WatcherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Project", systemImage: "folder")
                            .font(.headline)
                        if let path = model.watcherDraftWorkspacePath {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(NSString(string: path).abbreviatingWithTildeInPath)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Change") { model.changeWatcherProjectSelection() }
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button {
                                    model.chooseExistingWatcherProject()
                                } label: {
                                    Label("Existing Project", systemImage: "folder")
                                        .frame(maxWidth: .infinity)
                                }
                                Button {
                                    model.createNewWatcherProjectFolder()
                                } label: {
                                    Label("New Project", systemImage: "folder.badge.plus")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    WatcherCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Cadence", systemImage: "clock")
                                .font(.headline)
                            Picker("Routine pass", selection: $model.watcherDraftPollSeconds) {
                                Text("5 min").tag(TimeInterval(300))
                                Text("15 min").tag(TimeInterval(900))
                                Text("30 min").tag(TimeInterval(1_800))
                                Text("1 hour").tag(TimeInterval(3_600))
                                Text("2 hours").tag(TimeInterval(7_200))
                            }
                            Picker("Agent review", selection: $model.watcherDraftReviewSeconds) {
                                Text("2 hours").tag(TimeInterval(7_200))
                                Text("4 hours").tag(TimeInterval(14_400))
                                Text("8 hours").tag(TimeInterval(28_800))
                                Text("12 hours").tag(TimeInterval(43_200))
                                Text("24 hours").tag(TimeInterval(86_400))
                            }
                            Text("Codex may tune both after measuring the real task. Agent reviews never run more often than every 2 hours.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    WatcherCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Continuity", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                            Toggle("Notify on meaningful events", isOn: $model.watcherDraftNotifications)
                            Toggle("Launch LoopForge at login", isOn: $model.watcherDraftLaunchAtLogin)
                            Text("Closing the window keeps active watchers running. Quitting saves the checkpoint and resumes on next launch.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                WatcherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Agent Model", systemImage: "cpu")
                                .font(.headline)
                            Spacer()
                            Text("Workspace Only")
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.13), in: Capsule())
                                .foregroundStyle(.blue)
                        }

                        HStack(alignment: .top, spacing: 14) {
                            watcherSettingField("Source") {
                                Picker("Source", selection: Binding(
                                    get: { model.watcherDraftProvider },
                                    set: { model.setWatcherProvider($0) }
                                )) {
                                    ForEach(
                                        [
                                            AgentProviderKind.codex,
                                            AgentProviderKind.api,
                                            AgentProviderKind.local
                                        ]
                                    ) { provider in
                                        Label(provider.title, systemImage: provider.symbol)
                                            .tag(provider)
                                    }
                                }
                                .labelsHidden()
                            }

                            watcherSettingField("Model") {
                                if model.watcherModelChoices.isEmpty {
                                    Button(model.watcherDraftProvider == .local ? "Download…" : "Configure…") {
                                        model.openModelManager(
                                            preferredProvider: model.watcherDraftProvider
                                        )
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Picker("Model", selection: Binding(
                                        get: { model.watcherDraftModelReference },
                                        set: { model.setWatcherModelReference($0) }
                                    )) {
                                        ForEach(model.watcherModelChoices) { choice in
                                            Text(choice.displayName).tag(choice.id)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }

                            if !model.watcherReasoningOptions.isEmpty {
                                watcherSettingField("Reasoning") {
                                    Picker("Reasoning", selection: Binding(
                                        get: { model.watcherDraftReasoningEffort },
                                        set: { model.setWatcherReasoningEffort($0) }
                                    )) {
                                        ForEach(model.watcherReasoningOptions, id: \.self) {
                                            Text($0.capitalized).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Configuration")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Manage Models…") {
                                    model.openModelManager(
                                        preferredProvider: model.watcherDraftProvider
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text(model.watcherAgentSetupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                WatcherCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Authority & completion", systemImage: "checkmark.shield")
                                .font(.headline)
                            Spacer()
                            Text("Fail closed")
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.13), in: Capsule())
                                .foregroundStyle(.green)
                        }

                        HStack(alignment: .top, spacing: 22) {
                            watcherSafetyControl(
                                title: "Independent approval",
                                symbol: "person.2.badge.gearshape",
                                detail: "A fresh read-only reviewer with a distinct conversation lineage checks the exact pipeline and assessment digests."
                            )
                            watcherSafetyControl(
                                title: "Deterministic completion",
                                symbol: "checkmark.seal",
                                detail: "Telemetry, checkpoint bytes, verification results, goal evidence, and independent approval must form one valid receipt chain."
                            )
                        }

                        Text("An Agent's COMPLETE marker is only a proposal. Missing, stale, altered, self-approved, or rejected evidence cannot complete the Watcher.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        model.buildWatcher()
                    } label: {
                        Label("Build Watcher", systemImage: "sparkles")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.watcherDraftRequest.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                            || model.watcherDraftWorkspacePath == nil
                            || model.selectedWatcherAgent() == nil
                    )
                    .accessibilityIdentifier("build-watcher")
                }
            }
            .frame(maxWidth: 900)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            model.presentWatcherGuideIfNeeded()
        }
    }

    private func watcherSettingField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func watcherSafetyControl(
        title: String,
        symbol: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatcherGuideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex: Int

    init(startIndex: Int) {
        let upper = max(0, WatcherGuideStep.allCases.count - 1)
        _stepIndex = State(initialValue: min(max(0, startIndex), upper))
    }

    private var step: WatcherGuideStep {
        WatcherGuideStep(rawValue: stepIndex) ?? .target
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Continuum Watcher Guide")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(stepIndex + 1) of \(WatcherGuideStep.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            ProgressView(
                value: Double(stepIndex + 1),
                total: Double(WatcherGuideStep.allCases.count)
            )
            .progressViewStyle(.linear)
            .tint(.accentColor)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: step.symbol)
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(step.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(step.notes, id: \.self) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(note)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Button("Skip All") {
                    model.finishWatcherGuide()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Back") {
                    stepIndex = max(0, stepIndex - 1)
                }
                .disabled(stepIndex == 0)

                Button(stepIndex == WatcherGuideStep.allCases.count - 1 ? "Done" : "Next") {
                    if stepIndex == WatcherGuideStep.allCases.count - 1 {
                        model.finishWatcherGuide()
                        dismiss()
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            stepIndex += 1
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 600, height: 470)
    }
}

struct ContinuumWatcherDetailView: View {
    private enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case details = "Details"

        var id: String { rawValue }
    }

    let watcherID: UUID
    @ObservedObject var store: WatcherStore
    @ObservedObject var controller: WatcherController
    @State private var selectedTab: DetailTab = .overview

    private var watcher: ContinuumWatcher? { store.watcher(id: watcherID) }

    var body: some View {
        if let watcher {
            VStack(spacing: 0) {
                HStack {
                    Picker("Watcher page", selection: $selectedTab) {
                        ForEach(DetailTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                    .accessibilityIdentifier("watcher-detail-tab-picker")
                    Spacer()
                    if selectedTab == .overview {
                        Text("Task-focused live view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pipeline configuration and evidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 11)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(watcher)
                        if selectedTab == .overview {
                            focusOverview(watcher)
                        } else {
                            healthOverview(watcher)
                            configurationCard(watcher)
                            pipelineCard(watcher)
                            signalsCard(watcher)
                            timelineCard(watcher)
                        }
                    }
                    .frame(maxWidth: 1_080)
                    .padding(30)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier(
                    selectedTab == .overview
                        ? "watcher-overview"
                        : "watcher-details"
                )
            }
            .accessibilityIdentifier("watcher-detail")
        } else {
            ContentUnavailableView("Watcher not found", systemImage: "waveform.path.ecg")
        }
    }

    @ViewBuilder
    private func focusOverview(_ watcher: ContinuumWatcher) -> some View {
        let focus = WatcherFocusProjector.snapshot(for: watcher)
        let preset = watcher.pipeline?.dashboard?.preset ?? .general

        WatcherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    Image(systemName: preset.focusSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(preset.focusColor)
                        .frame(width: 42, height: 42)
                        .background(
                            preset.focusColor.opacity(0.1),
                            in: RoundedRectangle(
                                cornerRadius: 11,
                                style: .continuous
                            )
                        )
                    VStack(alignment: .leading, spacing: 7) {
                        Text(preset.focusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(preset.focusColor)
                        Text(focus.headline)
                            .font(.system(size: 24, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(focus.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 18)
                    if focus.needsUserActionCount > 0 {
                        Label(
                            "\(focus.needsUserActionCount) need you",
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1), in: Capsule())
                    }
                }

                if let progress = focus.progressSignal,
                   let value = watcher.runtime.latestSignals[progress.key] {
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(progress.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(WatcherFocusProjector.format(value, signal: progress))
                                .font(.caption.weight(.semibold))
                        }
                        if progress.expectedMaximum == 1 || progress.unit == "ratio" {
                            ProgressView(value: min(1, max(0, value)))
                                .tint(Color.accentColor)
                        }
                    }
                }
            }
        }

        HStack(spacing: 12) {
            FocusSummaryMetric(
                title: "Pipeline findings",
                value: "\(focus.pipelineIssues.count)",
                subtitle: focus.pipelineIssues.isEmpty
                    ? "No active anomalies"
                    : "\(focus.pendingIssues.count) await Agent judgment",
                symbol: focus.pipelineIssues.isEmpty
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill",
                color: focus.pipelineIssues.contains { $0.severity == .critical }
                    ? .red
                    : (focus.pipelineIssues.isEmpty ? .green : .orange)
            )
            FocusSummaryMetric(
                title: "Agent assessment",
                value: "\(focus.confirmedIssues.count) confirmed",
                subtitle: "\(focus.dismissedIssues.count) dismissed · \(focus.resolvedIssues.count) resolved",
                symbol: "checkmark.seal.fill",
                color: focus.confirmedIssues.contains { $0.severity == .critical }
                    ? .red
                    : .accentColor
            )
            FocusSummaryMetric(
                title: "Important for you",
                value: "\(focus.importantInformation.count)",
                subtitle: focus.needsUserActionCount == 0
                    ? "Nothing requires action"
                    : "\(focus.needsUserActionCount) require action",
                symbol: "sparkles",
                color: focus.needsUserActionCount == 0 ? .accentColor : .orange
            )
        }

        pipelineFindingsCard(focus)
        agentAssessmentCard(focus)
        importantInformationCard(watcher: watcher, focus: focus)
    }

    @ViewBuilder
    private func pipelineFindingsCard(_ focus: WatcherFocusSnapshot) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Pipeline findings", systemImage: "waveform.path.ecg.rectangle")
                        .font(.headline)
                    Spacer()
                    Text("\(focus.pipelineIssues.count) active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if focus.pipelineIssues.isEmpty {
                    FocusEmptyState(
                        title: "No active findings",
                        detail: "The latest bounded pass did not detect a current anomaly.",
                        symbol: "checkmark.circle.fill",
                        color: .green
                    )
                } else {
                    ForEach(focus.pipelineIssues) { issue in
                        FocusIssueRow(
                            title: issue.title,
                            detail: issue.detail,
                            badge: focus.pendingIssues.contains { $0.id == issue.id }
                                ? "Awaiting Agent"
                                : "Reviewed",
                            severity: issue.severity,
                            timestamp: issue.lastSeenAt,
                            userActionRequired: issue.userActionRequired
                        )
                        if issue.id != focus.pipelineIssues.last?.id { Divider() }
                    }
                }
            }
        }
        .accessibilityIdentifier("pipeline-findings-section")
    }

    @ViewBuilder
    private func agentAssessmentCard(_ focus: WatcherFocusSnapshot) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Agent assessment", systemImage: "checkmark.seal")
                        .font(.headline)
                    Spacer()
                    if let reviewedAt = focus.reviewedAt {
                        Text("Reviewed \(reviewedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Structured judgment pending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if focus.confirmedIssues.isEmpty
                    && focus.dismissedIssues.isEmpty
                    && focus.resolvedIssues.isEmpty {
                    FocusEmptyState(
                        title: "No item-level Agent decision yet",
                        detail: focus.pipelineIssues.isEmpty
                            ? "The latest pipeline state has no anomaly requiring classification."
                            : "The next Agent review will confirm or dismiss each current finding.",
                        symbol: "brain.head.profile",
                        color: .accentColor
                    )
                } else {
                    assessmentGroup(
                        title: "Confirmed",
                        symbol: "exclamationmark.circle.fill",
                        color: .orange,
                        issues: focus.confirmedIssues
                    )
                    assessmentGroup(
                        title: "Dismissed",
                        symbol: "xmark.circle.fill",
                        color: .secondary,
                        issues: focus.dismissedIssues
                    )
                    assessmentGroup(
                        title: "Resolved",
                        symbol: "checkmark.circle.fill",
                        color: .green,
                        issues: focus.resolvedIssues
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func assessmentGroup(
        title: String,
        symbol: String,
        color: Color,
        issues: [WatcherAgentIssueAssessment]
    ) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(title) · \(issues.count)", systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(issue.title)
                                .font(.subheadline.weight(.semibold))
                            if issue.userActionRequired {
                                Text("Needs you")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        Text(issue.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !issue.evidence.isEmpty {
                            Text(issue.evidence)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        color.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier(
                title == "Confirmed"
                    ? "agent-confirmed-section"
                    : (title == "Dismissed"
                        ? "agent-dismissed-section"
                        : "agent-resolved-section")
            )
        }
    }

    @ViewBuilder
    private func importantInformationCard(
        watcher: ContinuumWatcher,
        focus: WatcherFocusSnapshot
    ) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Important for your target", systemImage: "scope")
                        .font(.headline)
                    Spacer()
                    Text("\(focus.importantInformation.count) updates")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if focus.importantInformation.isEmpty {
                    FocusEmptyState(
                        title: "Nothing important changed",
                        detail: "Routine technical signals remain available in Details.",
                        symbol: "checkmark.circle",
                        color: .green
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 245), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(focus.importantInformation) { information in
                            ImportantInformationTile(
                                information: information,
                                signal: information.signalKey.flatMap { key in
                                    watcher.pipeline?.signals.first { $0.key == key }
                                }
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("user-important-section")
    }

    @ViewBuilder
    private func header(_ watcher: ContinuumWatcher) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(watcher.displayTitle)
                        .font(.system(size: 27, weight: .semibold))
                    Text(watcher.operationalStatusTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            watcher.requiresUserAttention
                                ? Color.red
                                : statusColor(watcher.status)
                        )
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            (watcher.requiresUserAttention
                                ? Color.red
                                : statusColor(watcher.status))
                                .opacity(0.12),
                            in: Capsule()
                        )
                }
                Text(NSString(string: watcher.workspacePath).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: watcher.workspacePath)
                ])
            } label: {
                Image(systemName: "folder")
            }
            .help("Show project in Finder")

            if watcher.status == .paused || watcher.status == .needsAttention
                || watcher.status == .stopped {
                Button("Resume") { controller.resume(watcherID: watcher.id) }
                    .buttonStyle(.borderedProminent)
            } else if watcher.status != .completed {
                Button("Pause") { controller.pause(watcherID: watcher.id) }
            }
            Menu {
                Button("Run Pipeline Now") { controller.runNow(watcherID: watcher.id) }
                Button("Review with Agent Now") { controller.reviewNow(watcherID: watcher.id) }
                Button("Open Live Report") { controller.openReport(watcherID: watcher.id) }
                Divider()
                Button("Stop Watcher", role: .destructive) {
                    controller.stop(watcherID: watcher.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(watcher.status == .completed)
        }
    }

    @ViewBuilder
    private func configurationCard(_ watcher: ContinuumWatcher) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("Watcher configuration", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    if watcher.reportPath != nil {
                        Button("Open Live Report") {
                            controller.openReport(watcherID: watcher.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Text(watcher.request)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 18)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    DetailColumn(
                        title: "Agent",
                        value: watcher.agentSelection?.summary
                            ?? watcher.lastProvider
                            ?? "Not selected"
                    )
                    DetailColumn(
                        title: "Reasoning",
                        value: watcher.agentSelection?.reasoningEffort?.capitalized
                            ?? "Provider default"
                    )
                    DetailColumn(
                        title: "Access",
                        value: watcher.agentSelection?.accessMode.title ?? "Workspace"
                    )
                    DetailColumn(
                        title: "Requested pass",
                        value: (watcher.requestedPollIntervalSeconds
                            ?? watcher.pipeline?.pollIntervalSeconds
                            ?? 900).compactDuration
                    )
                    DetailColumn(
                        title: "Requested review",
                        value: (watcher.requestedReviewIntervalSeconds
                            ?? watcher.pipeline?.reviewIntervalSeconds
                            ?? 14_400).compactDuration
                    )
                    DetailColumn(
                        title: "Continuity",
                        value: [
                            watcher.notificationsEnabled ? "Notifications on" : "Notifications off",
                            watcher.launchAtLogin ? "Launch at login" : "Manual launch"
                        ].joined(separator: " · ")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func healthOverview(_ watcher: ContinuumWatcher) -> some View {
        HStack(spacing: 12) {
            WatcherMetric(
                title: "Next pass",
                value: relative(watcher.runtime.nextRunAt),
                symbol: "arrow.clockwise"
            )
            WatcherMetric(
                title: "Next Agent review",
                value: relative(watcher.runtime.nextReviewAt),
                symbol: "brain.head.profile"
            )
            WatcherMetric(
                title: "Pipeline runs",
                value: "\(watcher.runtime.totalRuns)",
                symbol: "gearshape.2"
            )
            WatcherMetric(
                title: "Agent wakeups",
                value: "\(watcher.runtime.agentWakeups)",
                symbol: "bolt"
            )
        }
    }

    @ViewBuilder
    private func pipelineCard(_ watcher: ContinuumWatcher) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Solidified pipeline", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Spacer()
                    if let pipeline = watcher.pipeline {
                        Text("Revision \(pipeline.revision)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let pipeline = watcher.pipeline {
                    HStack(alignment: .top, spacing: 28) {
                        DetailColumn(
                            title: "Command",
                            value: pipeline.command.joined(separator: " ")
                        )
                        DetailColumn(
                            title: "Routine cadence",
                            value: pipeline.pollIntervalSeconds.compactDuration
                        )
                        DetailColumn(
                            title: "Adaptive review",
                            value: pipeline.reviewIntervalSeconds.compactDuration
                        )
                        DetailColumn(
                            title: "Coverage",
                            value: "\(pipeline.signals.count) signals · \(pipeline.rules.count) rules"
                        )
                    }
                    Divider()
                    Text(watcher.runtime.lastSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(
                                watcher.events.last?.message
                                    ?? "The selected Agent is building the first verified pipeline."
                            )
                            .foregroundStyle(.secondary)
                        }
                        if !watcher.lastAgentMessage.isEmpty {
                            Text(watcher.lastAgentMessage)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func signalsCard(_ watcher: ContinuumWatcher) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Live signals", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                if let signals = watcher.pipeline?.signals, !signals.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 185), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(signals) { signal in
                            WatcherSignalTile(
                                signal: signal,
                                value: watcher.runtime.latestSignals[signal.key],
                                capturedAt: watcher.runtime.latestSignalAt[signal.key]
                            )
                        }
                    }
                } else {
                    Text("Signal definitions appear after the pipeline is built.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func timelineCard(_ watcher: ContinuumWatcher) -> some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Timeline", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Text("\(watcher.events.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(watcher.events.suffix(16).reversed()) { event in
                    HStack(alignment: .top, spacing: 11) {
                        Circle()
                            .fill(eventColor(event.severity))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.message)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text(event.timestamp, style: .relative)
                                if let provider = event.provider {
                                    Text(provider)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if event.id != watcher.events.last?.id { Divider() }
                }
            }
        }
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        if date <= Date() { return "Now" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func statusColor(_ status: WatcherStatus) -> Color {
        switch status {
        case .active, .runningPipeline, .reviewing: return .green
        case .needsAttention: return .red
        case .completed: return .blue
        case .preparing: return .accentColor
        default: return .secondary
        }
    }

    private func eventColor(_ severity: WatcherSeverity) -> Color {
        switch severity {
        case .info: return .accentColor
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

private extension WatcherDashboardPreset {
    var focusLabel: String {
        switch self {
        case .general: return "Live task focus"
        case .operations: return "Operational focus"
        case .batch: return "Batch outcome"
        case .experiment: return "Experiment outcome"
        case .condition: return "Condition outcome"
        case .research: return "Research outcome"
        case .dataQuality: return "Data-quality outcome"
        }
    }

    var focusSymbol: String {
        switch self {
        case .general: return "scope"
        case .operations: return "waveform.path.ecg"
        case .batch: return "shippingbox"
        case .experiment: return "chart.xyaxis.line"
        case .condition: return "bell.badge"
        case .research: return "magnifyingglass"
        case .dataQuality: return "checkmark.shield"
        }
    }

    var focusColor: Color {
        switch self {
        case .general, .batch, .research: return .accentColor
        case .operations: return .green
        case .experiment: return .purple
        case .condition: return .orange
        case .dataQuality: return .teal
        }
    }
}

private struct FocusSummaryMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), \(subtitle)")
    }
}

private struct FocusEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            color.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct FocusIssueRow: View {
    let title: String
    let detail: String
    let badge: String
    let severity: WatcherSeverity
    let timestamp: Date
    let userActionRequired: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: severity == .critical
                ? "exclamationmark.octagon.fill"
                : "exclamationmark.triangle.fill")
                .foregroundStyle(severity == .critical ? Color.red : Color.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    if userActionRequired {
                        Text("Needs you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Seen \(timestamp, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ImportantInformationTile: View {
    let information: WatcherImportantInformation
    let signal: WatcherSignalSpec?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: information.userActionRequired
                    ? "person.crop.circle.badge.exclamationmark"
                    : "sparkles")
                    .foregroundStyle(information.userActionRequired ? Color.orange : Color.accentColor)
                Text(information.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
            }
            if let value = information.value {
                Text(formatted(value))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                if let signal,
                   (signal.kind == .ratio || signal.kind == .progress),
                   signal.expectedMaximum == 1 || signal.unit == "ratio" {
                    ProgressView(value: min(1, max(0, value)))
                        .tint(Color.accentColor)
                }
            }
            Text(information.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            Color.accentColor.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.11))
        }
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ value: Double) -> String {
        if let signal {
            return WatcherFocusProjector.format(value, signal: signal)
        }
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        guard let unit = information.unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }
}

private struct WatcherMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        WatcherCard {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WatcherSignalTile: View {
    let signal: WatcherSignalSpec
    let value: Double?
    let capturedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(signal.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(isHealthy ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
            }
            Text(value.map(formattedValue) ?? "Waiting")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(expectedText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private var isHealthy: Bool {
        guard let value else { return false }
        if let minimum = signal.expectedMinimum, value < minimum { return false }
        if let maximum = signal.expectedMaximum, value > maximum { return false }
        if let stale = signal.staleAfterSeconds,
           let capturedAt,
           Date().timeIntervalSince(capturedAt) > stale { return false }
        return true
    }

    private func formattedValue(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return signal.unit.isEmpty ? number : "\(number) \(signal.unit)"
    }

    private var expectedText: String {
        switch (signal.expectedMinimum, signal.expectedMaximum) {
        case let (minimum?, maximum?):
            return "Expected \(minimum.formatted())–\(maximum.formatted()) \(signal.unit)"
        case let (minimum?, nil):
            return "Expected ≥ \(minimum.formatted()) \(signal.unit)"
        case let (nil, maximum?):
            return "Expected ≤ \(maximum.formatted()) \(signal.unit)"
        default:
            return signal.description
        }
    }
}

private struct DetailColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatcherCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.68),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.primary.opacity(0.075))
            }
    }
}

private struct WatcherSpinner: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            Circle()
                .fill(color.opacity(0.9))
                .frame(width: 2.5, height: 2.5)
                .offset(y: -6.5)
        }
        .rotationEffect(.degrees(28))
        .frame(width: 13, height: 13)
    }
}
