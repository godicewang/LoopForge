import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class WatcherController: ObservableObject {
    @Published private(set) var runningWatcherIDs = Set<UUID>()
    @Published private(set) var statusMessage = ""

    let store: WatcherStore
    private let codexConnection: CodexConnectionManager
    private let agentCatalog: AgentCatalog
    private let codexRunner = CodexRunner()
    private let processRunner = ProcessRunner()
    private var schedulerTasks: [UUID: Task<Void, Never>] = [:]
    private var activeOperations: [UUID: Task<Void, Never>] = [:]
    private var schedulerTokens: [UUID: UUID] = [:]
    private var operationTokens: [UUID: UUID] = [:]

    init(
        store: WatcherStore,
        codexConnection: CodexConnectionManager,
        agentCatalog: AgentCatalog
    ) {
        self.store = store
        self.codexConnection = codexConnection
        self.agentCatalog = agentCatalog
    }

    func beginStartup() {
        for watcher in store.watchers where watcher.resumeOnNextLaunch
            && watcher.pipeline != nil
            && watcher.status.shouldSchedule {
            schedule(watcherID: watcher.id, at: watcher.runtime.nextRunAt ?? Date())
        }
    }

    func buildAndStart(
        request: String,
        workspacePath: String,
        pollIntervalSeconds: TimeInterval,
        reviewIntervalSeconds: TimeInterval,
        notificationsEnabled: Bool,
        launchAtLogin: Bool,
        agentSelection: AgentSelection
    ) {
        guard isAgentAvailable(agentSelection) else {
            statusMessage = "The selected Agent is not available. Reconnect it or choose another model."
            return
        }
        let clean = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            statusMessage = "Describe the monitoring or processing outcome first."
            return
        }
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            statusMessage = "Choose a valid project folder."
            return
        }

        let watcher = ContinuumWatcher(
            id: UUID(),
            title: TaskNamePolicy.descriptiveSummary(request: clean, fallback: "Continuum Watcher"),
            request: clean,
            workspacePath: workspace.standardizedFileURL.path,
            status: .preparing,
            pipeline: nil,
            runtime: .empty,
            events: [WatcherEvent(
                kind: .created,
                message: "Creating a durable local pipeline with Codex → API → Local fallback."
            )],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil,
            resumeOnNextLaunch: true,
            notificationsEnabled: notificationsEnabled,
            launchAtLogin: launchAtLogin,
            agentSelection: agentSelection,
            lastProvider: nil,
            lastAgentMessage: "",
            bootstrapThreadID: nil,
            reviewThreadID: nil
        )
        store.add(watcher)
        if notificationsEnabled { requestNotificationAuthorization() }
        if launchAtLogin { setLaunchAtLogin(true) }
        startOperation(watcherID: watcher.id) { [weak self] in
            await self?.bootstrap(
                watcherID: watcher.id,
                requestedPollSeconds: pollIntervalSeconds,
                requestedReviewSeconds: reviewIntervalSeconds
            )
        }
    }

    func resume(watcherID: UUID) {
        guard let watcher = store.watcher(id: watcherID) else { return }
        if watcher.pipeline == nil {
            store.update(id: watcherID) {
                $0.status = .preparing
                $0.resumeOnNextLaunch = true
            }
            startOperation(watcherID: watcherID) { [weak self] in
                await self?.recoverExistingPipelineOrBootstrap(
                    watcherID: watcherID,
                    requestedPollSeconds: 15 * 60,
                    requestedReviewSeconds: 4 * 60 * 60
                )
            }
            return
        }
        store.update(id: watcherID) {
            $0.status = .active
            $0.resumeOnNextLaunch = true
            $0.runtime.nextRunAt = Date()
        }
        store.appendEvent(id: watcherID, WatcherEvent(
            kind: .lifecycle,
            message: "Watcher resumed from its durable checkpoint."
        ))
        schedule(watcherID: watcherID, at: Date())
    }

    func pause(watcherID: UUID) {
        cancelWork(watcherID: watcherID)
        store.update(id: watcherID) {
            $0.status = .paused
            $0.resumeOnNextLaunch = false
            $0.runtime.nextRunAt = nil
            if $0.pipeline == nil {
                // An interrupted bootstrap thread may be the very request that
                // went silent. The next explicit Resume gets a clean session
                // instead of repeatedly attaching to a poisoned stream.
                $0.bootstrapThreadID = nil
            }
        }
        store.appendEvent(id: watcherID, WatcherEvent(
            kind: .lifecycle,
            message: "Watcher paused. Its checkpoint and pipeline were preserved."
        ))
    }

    func stop(watcherID: UUID) {
        cancelWork(watcherID: watcherID)
        store.update(id: watcherID) {
            $0.status = .stopped
            $0.resumeOnNextLaunch = false
            $0.runtime.nextRunAt = nil
        }
        store.appendEvent(id: watcherID, WatcherEvent(
            kind: .lifecycle,
            message: "Watcher stopped. Project files were left untouched."
        ))
    }

    func runNow(watcherID: UUID) {
        guard activeOperations[watcherID] == nil else { return }
        schedulerTasks[watcherID]?.cancel()
        schedulerTasks[watcherID] = nil
        schedulerTokens[watcherID] = nil
        startOperation(watcherID: watcherID) { [weak self] in
            await self?.executeCycle(watcherID: watcherID)
        }
    }

    func reviewNow(watcherID: UUID) {
        guard activeOperations[watcherID] == nil else { return }
        schedulerTasks[watcherID]?.cancel()
        schedulerTasks[watcherID] = nil
        schedulerTokens[watcherID] = nil
        startOperation(watcherID: watcherID) { [weak self] in
            await self?.performReview(
                watcherID: watcherID,
                reason: "User requested a manual pipeline and data review.",
                kind: .manualReview
            )
        }
    }

    func delete(watcherID: UUID) {
        cancelWork(watcherID: watcherID)
        store.delete(id: watcherID)
    }

    func shutdown() {
        for watcher in store.watchers where watcher.status.shouldSchedule {
            store.update(id: watcher.id) {
                $0.resumeOnNextLaunch = true
                if $0.status == .runningPipeline || $0.status == .reviewing {
                    $0.status = .active
                }
            }
        }
        schedulerTasks.values.forEach { $0.cancel() }
        activeOperations.values.forEach { $0.cancel() }
        schedulerTasks.removeAll()
        activeOperations.removeAll()
        schedulerTokens.removeAll()
        operationTokens.removeAll()
        runningWatcherIDs.removeAll()
    }

    private func startOperation(
        watcherID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard activeOperations[watcherID] == nil else { return }
        let token = UUID()
        operationTokens[watcherID] = token
        runningWatcherIDs.insert(watcherID)
        let task = Task { [weak self] in
            await operation()
            guard let self, self.operationTokens[watcherID] == token else {
                return
            }
            self.activeOperations[watcherID] = nil
            self.operationTokens[watcherID] = nil
            self.runningWatcherIDs.remove(watcherID)
        }
        activeOperations[watcherID] = task
    }

    private func cancelWork(watcherID: UUID) {
        schedulerTasks[watcherID]?.cancel()
        activeOperations[watcherID]?.cancel()
        schedulerTasks[watcherID] = nil
        activeOperations[watcherID] = nil
        schedulerTokens[watcherID] = nil
        operationTokens[watcherID] = nil
        runningWatcherIDs.remove(watcherID)
    }

    private func isCancelledOrPaused(_ watcherID: UUID) -> Bool {
        if Task.isCancelled { return true }
        guard let status = store.watcher(id: watcherID)?.status else { return true }
        return status == .paused || status == .stopped || status == .completed
    }

    private func bootstrap(
        watcherID: UUID,
        requestedPollSeconds: TimeInterval,
        requestedReviewSeconds: TimeInterval
    ) async {
        guard var watcher = store.watcher(id: watcherID) else { return }
        let agents = agents(for: watcher)
        guard !agents.isEmpty else {
            fail(
                watcherID: watcherID,
                message: "The selected Agent is unavailable. Reconnect it or choose another model."
            )
            return
        }
        var failures: [String] = []
        for (attempt, agent) in agents.enumerated() {
            guard !isCancelledOrPaused(watcherID) else { return }
            watcher = store.watcher(id: watcherID) ?? watcher
            store.update(id: watcherID) {
                $0.status = .preparing
                $0.lastProvider = agent.summary
                if attempt > 0 { $0.bootstrapThreadID = nil }
            }
            do {
                let result = try await runWatcherAgentTurn(
                    watcherID: watcherID,
                    watcher: watcher,
                    agent: agent,
                    threadID: attempt == 0 ? watcher.bootstrapThreadID : nil,
                    threadKind: .bootstrap,
                    stage: "Building a Continuum Watcher pipeline",
                    prompt: WatcherPromptCompiler.bootstrapPrompt(
                        watcher: watcher,
                        requestedPollSeconds: requestedPollSeconds,
                        requestedReviewSeconds: requestedReviewSeconds
                    )
                )
                guard result.exitCode == 0 else {
                    throw LoopForgeError.runtimeUnavailable(
                        result.eventErrors.last ?? result.stderr
                    )
                }
                watcher = store.watcher(id: watcherID) ?? watcher
                let pipeline = try loadPipeline(for: watcher)
                try await verifyPipeline(
                    pipeline,
                    watcher: watcher,
                    stage: "bootstrap"
                )
                let now = Date()
                store.update(id: watcherID) {
                    $0.pipeline = pipeline
                    $0.status = .active
                    $0.resumeOnNextLaunch = true
                    $0.lastAgentMessage = result.lastAgentMessage
                    $0.runtime.nextRunAt = now
                    $0.runtime.nextReviewAt = now.addingTimeInterval(
                        pipeline.reviewIntervalSeconds
                    )
                }
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: .repaired,
                    message: "Pipeline revision \(pipeline.revision) built and validated. First bounded run is starting.",
                    provider: agent.summary
                ))
                await executeCycle(watcherID: watcherID)
                return
            } catch {
                guard !isCancelledOrPaused(watcherID) else { return }
                let message = "\(agent.summary): \(sanitizedLogText(error.localizedDescription))"
                failures.append(message)
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: .pipelineFailure,
                    severity: .warning,
                    message: "The selected Agent did not complete the pipeline build. \(message.prefixText(420))",
                    provider: agent.summary
                ))
            }
        }
        fail(
            watcherID: watcherID,
            message: "The selected Agent failed to build the pipeline. "
                + failures.joined(separator: " · ").prefixText(900)
        )
    }

    private func recoverExistingPipelineOrBootstrap(
        watcherID: UUID,
        requestedPollSeconds: TimeInterval,
        requestedReviewSeconds: TimeInterval
    ) async {
        if let watcher = store.watcher(id: watcherID) {
            do {
                let pipeline = try loadPipeline(for: watcher)
                try await verifyPipeline(
                    pipeline,
                    watcher: watcher,
                    stage: "recovery"
                )
                let now = Date()
                store.update(id: watcherID) {
                    $0.pipeline = pipeline
                    $0.status = .active
                    $0.resumeOnNextLaunch = true
                    $0.runtime.nextRunAt = now
                    $0.runtime.nextReviewAt = $0.runtime.nextReviewAt
                        ?? now.addingTimeInterval(pipeline.reviewIntervalSeconds)
                }
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: .repaired,
                    message: "Recovered and independently reverified the existing pipeline. No Agent rebuild was needed."
                ))
                await executeCycle(watcherID: watcherID)
                return
            } catch {
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: .pipelineFailure,
                    severity: .warning,
                    message: "The retained pipeline failed recovery verification and will be rebuilt safely: \(sanitizedLogText(error.localizedDescription).prefixText(420))"
                ))
            }
        }
        await bootstrap(
            watcherID: watcherID,
            requestedPollSeconds: requestedPollSeconds,
            requestedReviewSeconds: requestedReviewSeconds
        )
    }

    private func executeCycle(watcherID: UUID) async {
        guard var watcher = store.watcher(id: watcherID),
              let pipeline = watcher.pipeline,
              watcher.status != .paused,
              watcher.status != .stopped,
              watcher.status != .completed else { return }
        do {
            let normalized = try WatcherPolicy.normalized(
                pipeline,
                workspacePath: watcher.workspacePath
            )
            let execution = try WatcherPolicy.executableAndArguments(
                pipeline: normalized,
                workspacePath: watcher.workspacePath
            )
            store.update(id: watcherID) {
                $0.status = .runningPipeline
                $0.runtime.lastRunAt = Date()
                $0.runtime.nextRunAt = nil
            }
            let runStartedAt = Date()
            let result = try await processRunner.run(
                executable: execution.0,
                arguments: execution.1,
                environment: WatcherRuntimeEnvironment.sanitized(),
                currentDirectory: execution.2,
                timeout: normalized.timeoutSeconds
            )
            watcher = store.watcher(id: watcherID) ?? watcher
            var telemetry: WatcherTelemetryEnvelope?
            if result.exitCode == 0 {
                telemetry = try loadTelemetry(
                    for: watcher,
                    pipeline: normalized,
                    notOlderThan: runStartedAt
                )
                try WatcherPolicy.validateCheckpoint(
                    pipeline: normalized,
                    workspacePath: watcher.workspacePath
                )
            }
            let now = Date()
            var runtime = watcher.runtime
            runtime.totalRuns += 1
            runtime.lastExitCode = result.exitCode
            runtime.lastRunAt = now

            var reasons: [String] = []
            var severity: WatcherSeverity = .info
            if result.exitCode != 0 {
                runtime.consecutiveFailures += 1
                let summary = sanitizedLogText(
                    [result.stderr, result.stdout].joined(separator: "\n")
                )
                reasons.append("Pipeline exited with code \(result.exitCode): \(summary.prefix(600))")
                severity = .critical
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: .pipelineFailure,
                    severity: .critical,
                    message: reasons.last ?? "Pipeline failed"
                ))
            } else if let telemetry {
                runtime.consecutiveFailures = 0
                runtime.lastSuccessfulRunAt = now
                runtime.lastSummary = telemetry.summary ?? "Pipeline pass completed"
                let evaluation = WatcherPolicy.evaluate(
                    pipeline: normalized,
                    telemetry: telemetry,
                    state: &runtime,
                    now: now
                )
                for event in evaluation.events {
                    store.appendEvent(id: watcherID, event)
                }
                if evaluation.shouldWakeAgent {
                    reasons.append(evaluation.events.map(\.message).joined(separator: "; "))
                    severity = max(severity, evaluation.highestSeverity)
                }
                if telemetry.completed == true {
                    reasons.append("The deterministic pipeline reports that the requested batch outcome is complete.")
                }
            }

            let reviewDue = (runtime.nextReviewAt ?? now) <= now
            if reviewDue {
                reasons.append("The scheduled adaptive review is due.")
            }
            let failureBackoff = min(
                normalized.reviewIntervalSeconds,
                normalized.pollIntervalSeconds
                    * pow(2, Double(min(6, runtime.consecutiveFailures)))
            )
            runtime.nextRunAt = now.addingTimeInterval(
                runtime.consecutiveFailures > 0 ? failureBackoff : normalized.pollIntervalSeconds
            )
            store.update(id: watcherID) {
                $0.pipeline = normalized
                $0.runtime = runtime
                $0.status = .active
                $0.resumeOnNextLaunch = true
            }
            store.appendEvent(id: watcherID, WatcherEvent(
                kind: .pipelineRun,
                severity: result.exitCode == 0 ? .info : .critical,
                message: result.exitCode == 0
                    ? (telemetry?.summary ?? "Bounded pipeline pass completed.")
                    : "Pipeline pass failed; backoff and Agent diagnosis are active."
            ))

            if !reasons.isEmpty {
                if severity >= .warning {
                    notifyIfNeeded(
                        watcherID: watcherID,
                        title: severity == .critical ? "Continuum Watcher alert" : "Continuum Watcher review",
                        body: reasons.joined(separator: " ").prefixText(240)
                    )
                }
                await performReview(
                    watcherID: watcherID,
                    reason: reasons.joined(separator: "\n"),
                    kind: reviewDue ? .scheduledReview : .anomaly
                )
            } else {
                scheduleFromStoredState(watcherID: watcherID)
            }
        } catch {
            guard !isCancelledOrPaused(watcherID) else { return }
            store.update(id: watcherID) {
                $0.runtime.consecutiveFailures += 1
                $0.runtime.lastRunAt = Date()
                $0.runtime.nextRunAt = Date().addingTimeInterval(
                    min(
                        $0.pipeline?.reviewIntervalSeconds ?? 14_400,
                        ($0.pipeline?.pollIntervalSeconds ?? 900)
                            * pow(2, Double(min(6, $0.runtime.consecutiveFailures)))
                    )
                )
            }
            store.appendEvent(id: watcherID, WatcherEvent(
                kind: .pipelineFailure,
                severity: .critical,
                message: "Pipeline could not run: \(sanitizedLogText(error.localizedDescription))"
            ))
            await performReview(
                watcherID: watcherID,
                reason: "The deterministic pipeline could not run: \(error.localizedDescription)",
                kind: .pipelineFailure
            )
        }
    }

    private func performReview(
        watcherID: UUID,
        reason: String,
        kind: WatcherEventKind
    ) async {
        guard var watcher = store.watcher(id: watcherID),
              watcher.pipeline != nil,
              watcher.status != .paused,
              watcher.status != .stopped else { return }
        let agents = agents(for: watcher)
        guard !agents.isEmpty else {
            if store.watcher(id: watcherID)?.status != .paused {
                fail(
                    watcherID: watcherID,
                    message: "The watcher needs a review, but its selected Agent is unavailable."
                )
            }
            return
        }
        let telemetry = try? loadTelemetry(
            for: watcher,
            pipeline: watcher.pipeline!,
            notOlderThan: nil
        )
        store.update(id: watcherID) {
            $0.status = .reviewing
            $0.runtime.agentWakeups += 1
            $0.lastProvider = agents[0].summary
        }
        store.appendEvent(id: watcherID, WatcherEvent(
            kind: kind,
            severity: kind == .pipelineFailure ? .critical : .info,
            message: "Agent awakened: \(reason.prefixText(400))",
            provider: agents[0].summary
        ))

        var failures: [String] = []
        for (attempt, agent) in agents.enumerated() {
            guard !isCancelledOrPaused(watcherID) else { return }
            watcher = store.watcher(id: watcherID) ?? watcher
            store.update(id: watcherID) {
                $0.status = .reviewing
                $0.lastProvider = agent.summary
                if attempt > 0 { $0.reviewThreadID = nil }
            }
            do {
                let result = try await runWatcherAgentTurn(
                    watcherID: watcherID,
                    watcher: watcher,
                    agent: agent,
                    threadID: attempt == 0 ? watcher.reviewThreadID : nil,
                    threadKind: .review,
                    stage: "Reviewing a Continuum Watcher signal",
                    prompt: WatcherPromptCompiler.reviewPrompt(
                        watcher: watcher,
                        reason: reason,
                        telemetry: telemetry,
                        recentEvents: watcher.events
                    )
                )
                guard result.exitCode == 0 else {
                    throw LoopForgeError.runtimeUnavailable(
                        result.eventErrors.last ?? result.stderr
                    )
                }
                watcher = store.watcher(id: watcherID) ?? watcher
                let previousPipeline = watcher.pipeline!
                let decision = try WatcherReviewDecision.parse(
                    result.lastAgentMessage
                )
                let updatedPipeline = try loadPipeline(for: watcher)
                guard updatedPipeline.revision >= previousPipeline.revision else {
                    throw WatcherPolicyError.invalidManifest(
                        "an Agent review cannot decrease the pipeline revision"
                    )
                }
                if updatedPipeline != previousPipeline,
                   updatedPipeline.revision <= previousPipeline.revision {
                    throw WatcherPolicyError.invalidManifest(
                        "a changed pipeline must increase its revision"
                    )
                }
                if decision == .repaired,
                   updatedPipeline.revision <= previousPipeline.revision {
                    throw WatcherPolicyError.invalidManifest(
                        "REPAIRED requires a higher manifest revision"
                    )
                }
                try await verifyPipeline(
                    updatedPipeline,
                    watcher: watcher,
                    stage: "adaptive review"
                )
                let now = Date()
                let needsUser = decision == .needsUser
                let complete = decision == .complete
                let repaired = decision == .repaired
                store.update(id: watcherID) {
                    $0.pipeline = updatedPipeline
                    $0.runtime.lastReviewAt = now
                    $0.runtime.nextReviewAt = now.addingTimeInterval(
                        updatedPipeline.reviewIntervalSeconds
                    )
                    $0.runtime.nextRunAt = complete
                        ? nil
                        : now.addingTimeInterval(updatedPipeline.pollIntervalSeconds)
                    $0.lastAgentMessage = result.lastAgentMessage
                    $0.status = complete ? .completed : (needsUser ? .needsAttention : .active)
                    $0.resumeOnNextLaunch = !complete && !needsUser
                    $0.completedAt = complete ? now : nil
                }
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: complete ? .completed : (repaired ? .repaired : .scheduledReview),
                    severity: needsUser ? .warning : .info,
                    message: complete
                        ? "Agent verified that the requested watcher outcome is complete."
                        : (repaired
                            ? "Agent repaired or adapted pipeline revision \(updatedPipeline.revision)."
                            : "Agent reviewed current data and verified pipeline health."),
                    provider: agent.summary
                ))
                if complete {
                    notifyIfNeeded(
                        watcherID: watcherID,
                        title: "\(watcher.displayTitle) completed",
                        body: "Continuum Watcher verified the requested outcome."
                    )
                } else if !needsUser {
                    scheduleFromStoredState(watcherID: watcherID)
                } else {
                    notifyIfNeeded(
                        watcherID: watcherID,
                        title: "\(watcher.displayTitle) needs you",
                        body: result.lastAgentMessage.prefixText(220)
                    )
                }
                return
            } catch {
                guard !isCancelledOrPaused(watcherID) else { return }
                let message = "\(agent.summary): \(sanitizedLogText(error.localizedDescription))"
                failures.append(message)
                store.appendEvent(id: watcherID, WatcherEvent(
                    kind: .pipelineFailure,
                    severity: .warning,
                    message: "The selected Agent did not complete the review. \(message.prefixText(420))",
                    provider: agent.summary
                ))
            }
        }
        fail(
            watcherID: watcherID,
            message: "The selected Agent failed to complete the review. "
                + failures.joined(separator: " · ").prefixText(900),
            preserveSchedule: true
        )
    }

    private enum WatcherThreadKind {
        case bootstrap
        case review
    }

    private func runWatcherAgentTurn(
        watcherID: UUID,
        watcher: ContinuumWatcher,
        agent: AgentSelection,
        threadID: String?,
        threadKind: WatcherThreadKind,
        stage: String,
        prompt: String
    ) async throws -> CodexTurnResult {
        let task = harnessTask(
            watcher: watcher,
            agent: agent,
            threadID: threadID,
            stage: stage
        )
        return try await codexRunner.runTurn(
            task: task,
            prompt: prompt,
            watchdogPolicy: .continuumWatcher,
            onThreadStarted: { [weak self] threadID in
                Task { @MainActor in
                    self?.store.update(id: watcherID) {
                        switch threadKind {
                        case .bootstrap: $0.bootstrapThreadID = threadID
                        case .review: $0.reviewThreadID = threadID
                        }
                    }
                }
            },
            onEvent: { [weak self] kind, message in
                guard kind == .agent || kind == .error || kind == .warning else { return }
                Task { @MainActor in
                    self?.recordAgentEvent(watcherID: watcherID, kind: kind, message: message)
                }
            }
        )
    }

    private func agents(for watcher: ContinuumWatcher) -> [AgentSelection] {
        if let selected = watcher.agentSelection {
            return isAgentAvailable(selected) ? [selected] : []
        }

        // Records created before explicit Watcher model selection are migrated
        // once. Their first healthy provider becomes durable configuration so
        // later wakes and recovery never silently change models.
        guard let migrated = legacyPreferredAgent() else { return [] }
        store.update(id: watcher.id) {
            $0.agentSelection = migrated
            $0.lastProvider = migrated.summary
        }
        store.appendEvent(id: watcher.id, WatcherEvent(
            kind: .lifecycle,
            message: "Legacy watcher model fixed to \(migrated.summary).",
            provider: migrated.summary
        ))
        return [migrated]
    }

    private func isAgentAvailable(_ selection: AgentSelection) -> Bool {
        switch selection.provider {
        case .codex:
            return codexConnection.isConnected
        case .api:
            guard let connection = selection.apiConnection else { return false }
            return APIKeyVault.get(for: connection.id)?.isEmpty == false
        case .local:
            guard let profile = selection.localProfile else { return false }
            return agentCatalog.isLocalModelReady(profile)
        }
    }

    private func legacyPreferredAgent() -> AgentSelection? {
        if codexConnection.isConnected {
            let model = codexConnection.recommendedModel
            return .codex(
                model: model.slug,
                displayName: model.displayName,
                reasoning: CodexCatalog.strongestReasoning(for: model),
                access: .fullAccess
            )
        }
        if let api = agentCatalog.apiConnections.first(where: {
            APIKeyVault.get(for: $0.id)?.isEmpty == false
        }) {
            return .api(
                connection: api,
                reasoning: api.reasoningOptions.last,
                access: .fullAccess
            )
        }
        if let local = agentCatalog.localModels.first(where: agentCatalog.isLocalModelReady) {
            return .local(profile: local, access: .fullAccess)
        }
        return nil
    }

    private func harnessTask(
        watcher: ContinuumWatcher,
        agent: AgentSelection,
        threadID: String?,
        stage: String
    ) -> LoopTask {
        let now = Date()
        return LoopTask(
            id: watcher.id,
            title: watcher.displayTitle,
            request: watcher.request,
            quality: .lightweight,
            category: .general,
            workspacePath: watcher.workspacePath,
            targetSeconds: 0,
            accumulatedCodexSeconds: 0,
            model: agent.localProfile ?? .efficientAgent,
            status: .running,
            stage: stage,
            iteration: watcher.runtime.agentWakeups,
            threadID: threadID,
            auditScore: 0,
            auditSummary: "",
            lastAgentMessage: watcher.lastAgentMessage,
            consecutiveFailures: watcher.runtime.consecutiveFailures,
            createdAt: watcher.createdAt,
            updatedAt: now,
            completedAt: nil,
            logs: [],
            controlAgent: agent,
            subAgent: agent,
            originalRequest: watcher.request,
            executionMode: .singleLoop
        )
    }

    private func loadPipeline(for watcher: ContinuumWatcher) throws -> WatcherPipeline {
        try WatcherPolicy.loadPipeline(workspacePath: watcher.workspacePath)
    }

    private func loadTelemetry(
        for watcher: ContinuumWatcher,
        pipeline: WatcherPipeline,
        notOlderThan: Date?
    ) throws -> WatcherTelemetryEnvelope {
        try WatcherPolicy.loadTelemetry(
            pipeline: pipeline,
            workspacePath: watcher.workspacePath,
            notOlderThan: notOlderThan
        )
    }

    private func verifyPipeline(
        _ pipeline: WatcherPipeline,
        watcher: ContinuumWatcher,
        stage: String
    ) async throws {
        let executions = try WatcherPolicy.verificationExecutions(
            pipeline: pipeline,
            workspacePath: watcher.workspacePath
        )
        for (index, execution) in executions.enumerated() {
            guard !isCancelledOrPaused(watcher.id) else {
                throw CancellationError()
            }
            let result = try await processRunner.run(
                executable: execution.0,
                arguments: execution.1,
                environment: WatcherRuntimeEnvironment.sanitized(),
                currentDirectory: execution.2,
                timeout: min(120, max(10, pipeline.timeoutSeconds))
            )
            guard result.exitCode == 0 else {
                let output = sanitizedLogText(
                    [result.stderr, result.stdout]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                )
                throw WatcherPolicyError.invalidManifest(
                    "\(stage) verification \(index + 1) failed with exit code "
                        + "\(result.exitCode): \(output.prefixText(500))"
                )
            }
        }
    }

    private func recordAgentEvent(
        watcherID: UUID,
        kind: LogKind,
        message: String
    ) {
        let clean = sanitizedLogText(message)
        guard !clean.isEmpty else { return }
        store.update(id: watcherID) {
            if kind == .agent { $0.lastAgentMessage = clean }
        }
        if kind == .error || kind == .warning {
            store.appendEvent(id: watcherID, WatcherEvent(
                kind: .anomaly,
                severity: kind == .error ? .critical : .warning,
                message: clean.prefixText(600)
            ))
        }
    }

    private func scheduleFromStoredState(watcherID: UUID) {
        guard let watcher = store.watcher(id: watcherID),
              watcher.status == .active,
              watcher.resumeOnNextLaunch else { return }
        schedule(watcherID: watcherID, at: watcher.runtime.nextRunAt ?? Date())
    }

    private func schedule(watcherID: UUID, at date: Date) {
        schedulerTasks[watcherID]?.cancel()
        let token = UUID()
        schedulerTokens[watcherID] = token
        let delay = max(0, date.timeIntervalSinceNow)
        schedulerTasks[watcherID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.schedulerTokens[watcherID] == token else {
                return
            }
            self.schedulerTasks[watcherID] = nil
            self.schedulerTokens[watcherID] = nil
            self.startOperation(watcherID: watcherID) { [weak self] in
                await self?.executeCycle(watcherID: watcherID)
            }
        }
    }

    private func fail(
        watcherID: UUID,
        message: String,
        preserveSchedule: Bool = false
    ) {
        let clean = sanitizedLogText(message)
        store.update(id: watcherID) {
            $0.status = .needsAttention
            $0.resumeOnNextLaunch = preserveSchedule
            if !preserveSchedule { $0.runtime.nextRunAt = nil }
        }
        store.appendEvent(id: watcherID, WatcherEvent(
            kind: .pipelineFailure,
            severity: .critical,
            message: clean
        ))
        statusMessage = clean
        notifyIfNeeded(
            watcherID: watcherID,
            title: "Continuum Watcher needs attention",
            body: clean.prefixText(220)
        )
        if preserveSchedule {
            store.update(id: watcherID) {
                $0.status = .active
                $0.runtime.nextRunAt = Date().addingTimeInterval(
                    $0.pipeline?.pollIntervalSeconds ?? 900
                )
            }
            scheduleFromStoredState(watcherID: watcherID)
        }
    }

    private func requestNotificationAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func notifyIfNeeded(watcherID: UUID, title: String, body: String) {
        guard store.watcher(id: watcherID)?.notificationsEnabled == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "continuum-\(watcherID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusMessage = "Launch at Login could not be changed: \(error.localizedDescription)"
        }
    }
}

private extension String {
    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}
