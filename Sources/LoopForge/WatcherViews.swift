import AppKit
import SwiftUI

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
                Text(watcher.status.title)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if watcher.status.isWorking || watcher.status == .active {
                WatcherSpinner(color: watcher.status == .active ? .secondary : .accentColor)
            } else if watcher.status == .needsAttention {
                Circle().fill(Color.red).frame(width: 7, height: 7)
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
        default: return .secondary
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
                        Label("Outcome", systemImage: "scope")
                            .font(.headline)
                        TextEditor(text: $model.watcherDraftRequest)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 126)
                            .background(
                                Color(nsColor: .textBackgroundColor).opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(alignment: .topLeading) {
                                if model.watcherDraftRequest.isEmpty {
                                    Text("Monitor, process, alert, or complete a long-running outcome…")
                                        .foregroundStyle(.tertiary)
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
                    HStack(spacing: 14) {
                        Image(systemName: "cpu")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Automatic Agent priority")
                                .font(.headline)
                            Text("Codex → configured API → downloaded local model")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Full Access")
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.13), in: Capsule())
                            .foregroundStyle(.orange)
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
                        ).isEmpty || model.watcherDraftWorkspacePath == nil
                    )
                    .accessibilityIdentifier("build-watcher")
                }
            }
            .frame(maxWidth: 900)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ContinuumWatcherDetailView: View {
    let watcherID: UUID
    @ObservedObject var store: WatcherStore
    @ObservedObject var controller: WatcherController

    private var watcher: ContinuumWatcher? { store.watcher(id: watcherID) }

    var body: some View {
        if let watcher {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(watcher)
                    healthOverview(watcher)
                    pipelineCard(watcher)
                    signalsCard(watcher)
                    timelineCard(watcher)
                }
                .frame(maxWidth: 1_080)
                .padding(30)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("watcher-detail")
        } else {
            ContentUnavailableView("Watcher not found", systemImage: "waveform.path.ecg")
        }
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
                    Text(watcher.status.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor(watcher.status))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(statusColor(watcher.status).opacity(0.12), in: Capsule())
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
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Codex is inspecting the project and building the first verified pipeline.")
                            .foregroundStyle(.secondary)
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
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.15) / 1.15 * 360
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
        .frame(width: 13, height: 13)
    }
}
