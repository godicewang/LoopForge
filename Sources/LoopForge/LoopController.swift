import AppKit
import Combine
import Foundation

@MainActor
final class LoopController: ObservableObject {
    private enum RequestedTerminalAction {
        case pause
        case stop
    }

    @Published private(set) var runningTaskID: UUID?
    @Published private(set) var activeTurnStartedAt: Date?
    @Published private(set) var clock = Date()

    let store: TaskStore
    private let ollama: OllamaManager
    private let codex: CodexRunner
    private let auditor: WorkspaceAuditor
    private let supervisor: LocalSupervisor
    private let evidenceCollector: WorkspaceEvidenceCollector
    private let reportGenerator: CompletionReportGenerator
    private let desktopAutomationPreflight: DesktopAutomationPreflight
    private let permissionAutomator: SystemPermissionAutomator
    private let permissionCenter: PermissionCenter
    private let agentCatalog: AgentCatalog
    private let auxiliaryRouter: AuxiliaryModelRouter
    private let graphEngine: GraphLoopEngine
    private let promptCompiler = PromptCompiler()
    private var job: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var activityToken: NSObjectProtocol?
    private var activeTurnCheckpointedSeconds: TimeInterval = 0
    private let workspaceMutationRecoveryTask: Task<
        WorkspaceMutationRecoveryStartupReport,
        Never
    >?
    private var workspaceMutationRecoveryReport: WorkspaceMutationRecoveryStartupReport?
    private var hostResourceRecoveryTask: Task<GraphHostResourceRecoveryReport, Never>?
    /// User intent must outlive concurrent Graph status writes. A final audit
    /// can finish or retry while cancellation is propagating and temporarily
    /// overwrite `.pausing`/`.stopping`; the controller still owns the terminal
    /// transition after the process tree is reaped.
    private var requestedTerminalAction: (taskID: UUID, action: RequestedTerminalAction)?

    init(
        store: TaskStore,
        ollama: OllamaManager = OllamaManager(),
        codex: CodexRunner = CodexRunner(),
        auditor: WorkspaceAuditor = WorkspaceAuditor(),
        supervisor: LocalSupervisor = LocalSupervisor(),
        evidenceCollector: WorkspaceEvidenceCollector = WorkspaceEvidenceCollector(),
        reportGenerator: CompletionReportGenerator = CompletionReportGenerator(),
        desktopAutomationPreflight: DesktopAutomationPreflight = DesktopAutomationPreflight(),
        permissionAutomator: SystemPermissionAutomator? = nil,
        permissionCenter: PermissionCenter? = nil,
        agentCatalog: AgentCatalog? = nil,
        auxiliaryRouter: AuxiliaryModelRouter = AuxiliaryModelRouter(),
        hostResources: any GraphHostResourceLeaseManaging = GraphHostResourceLeaseRegistry(),
        workspaceMutationRecoveryTask: Task<
            WorkspaceMutationRecoveryStartupReport,
            Never
        >? = nil
    ) {
        self.store = store
        self.ollama = ollama
        self.codex = codex
        self.auditor = auditor
        self.supervisor = supervisor
        self.evidenceCollector = evidenceCollector
        self.reportGenerator = reportGenerator
        self.desktopAutomationPreflight = desktopAutomationPreflight
        self.permissionAutomator = permissionAutomator ?? SystemPermissionAutomator()
        self.permissionCenter = permissionCenter ?? PermissionCenter()
        self.agentCatalog = agentCatalog ?? AgentCatalog()
        self.auxiliaryRouter = auxiliaryRouter
        self.workspaceMutationRecoveryTask = workspaceMutationRecoveryTask
        self.graphEngine = GraphLoopEngine(
            store: store,
            codex: codex,
            auditor: auditor,
            evidenceCollector: evidenceCollector,
            reportGenerator: reportGenerator,
            agentCatalog: self.agentCatalog,
            router: auxiliaryRouter,
            hostResources: hostResources
        )
        let graphEngine = self.graphEngine
        let kernelRecovery = workspaceMutationRecoveryTask
        self.hostResourceRecoveryTask = Task {
            if let kernelRecovery {
                let report = await kernelRecovery.value
                guard !report.requiresAttention else { return .empty }
            }
            return await graphEngine.recoverDanglingHostResources()
        }
    }

    /// Runtime checkpoints and visible duration labels have different needs.
    /// Keep the lightweight timer frequent enough to checkpoint a long turn,
    /// but publish the shared SwiftUI clock much less often: every publication
    /// invalidates the complete task detail, including large Graph and log trees.
    /// The timer remains dormant while no task is running.
    static let clockRefreshInterval: TimeInterval = 5
    static let clockPublicationInterval: TimeInterval = 30

    var isClockTickerActive: Bool { timer != nil }

    /// Every stored `LoopTask` checkpoint was authorized by the retired
    /// narrative controller rather than a ratified journal-kernel contract.
    /// Keep its evidence inspectable, but never let a resume flag, direct
    /// start, or candidate-selection call cross the production boundary.
    @discardableResult
    func blockRetiredTaskExecution(
        taskID: UUID,
        source: String
    ) -> Bool {
        guard let task = store.task(id: taskID) else { return false }

        let mode = task.resolvedExecutionMode
        let stage = LegacyTaskExecutionRetirementPolicy.stage(for: mode)
        let message = "Retired \(mode.title) execution was blocked at the controller boundary (\(source)). Its workspace, logs, graph or candidate evidence, and checkpoints remain unchanged; no timer, agent, process, mutation, integration, selection, or automatic retry started. Create and confirm a new journaled Auto Graph contract before future execution."
        let alreadyBlocked = task.status == .blocked
            && task.stage == stage
            && task.resumeOnNextLaunch == false
        store.update(id: taskID) {
            $0.status = .blocked
            $0.stage = stage
            $0.resumeOnNextLaunch = false
            $0.externalBlockerKind = nil
            $0.externalBlockerMessage =
                LegacyTaskExecutionRetirementPolicy.blocker(for: mode)
            $0.externalBlockerRetryAfter = nil
            $0.checkpointedAt = Date()
        }
        if !alreadyBlocked {
            store.appendLog(id: taskID, kind: .warning, message)
        }
        return true
    }

    private func startClockTicker() {
        guard timer == nil else { return }
        clock = Date()
        timer = Timer.publish(
            every: Self.clockRefreshInterval,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] date in
            guard let self else { return }
            if date.timeIntervalSince(self.clock) >= Self.clockPublicationInterval {
                self.clock = date
            }
            if let taskID = self.runningTaskID,
               let started = self.activeTurnStartedAt,
               date.timeIntervalSince(started) >= 15 {
                self.checkpointActiveTurn(taskID: taskID, preserveRunning: true, now: date)
            }
        }
    }

    private func stopClockTicker() {
        timer?.cancel()
        timer = nil
        clock = Date()
    }

    func liveAccumulatedSeconds(for task: LoopTask) -> TimeInterval {
        if task.resolvedExecutionMode != .singleLoop, let graph = task.graphState {
            return graph.nodes.reduce(0) { $0 + $1.liveActiveSeconds(at: clock) }
        }
        guard runningTaskID == task.id, let activeTurnStartedAt else { return task.accumulatedCodexSeconds }
        return task.accumulatedCodexSeconds + max(0, clock.timeIntervalSince(activeTurnStartedAt))
    }

    func start(taskID: UUID) {
        _ = blockRetiredTaskExecution(
            taskID: taskID,
            source: "direct start request"
        )
    }

#if DEBUG
    /// Characterization-only access to the retired controller lifecycle. This
    /// symbol is absent from non-DEBUG builds and cannot authorize production.
    func startRetiredExecutionForTesting(taskID: UUID) {
        startRetiredExecution(taskID: taskID)
    }

    private func startRetiredExecution(taskID: UUID) {
        guard runningTaskID == nil, let task = store.task(id: taskID) else { return }
        guard task.canResume || task.status == .preparing else { return }
        runningTaskID = taskID
        requestedTerminalAction = nil
        startClockTicker()
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .automaticTerminationDisabled],
            reason: "LoopForge is supervising an autonomous agent task"
        )
        store.update(id: taskID) {
            $0.status = .preparing
            $0.stage = "Checking the Loop Control Agent and Sub Agent"
            $0.consecutiveFailures = 0
            $0.externalBlockerKind = nil
            $0.externalBlockerMessage = nil
            $0.externalBlockerRetryAfter = nil
            $0.resumeOnNextLaunch = true
            $0.checkpointedAt = Date()
        }
        job = Task { [weak self] in await self?.runLoop(taskID: taskID) }
    }
#endif

    func pause(taskID: UUID) {
        guard runningTaskID == taskID else { return }
        requestedTerminalAction = (taskID, .pause)
        store.flushPendingGraphLogs(taskID: taskID)
        checkpointActiveTurn(taskID: taskID, preserveRunning: false)
        stopClockTicker()
        store.update(id: taskID) {
            $0.status = .pausing
            $0.stage = "Pausing safely · saving progress and ending the active agent process"
            $0.resumeOnNextLaunch = false
            $0.checkpointedAt = Date()
        }
        store.appendLog(id: taskID, kind: .warning, "Pause requested by the user. Accumulated active Sub Agent runtime was checkpointed; LoopForge is waiting for the active agent process to exit safely.")
        graphEngine.cancel()
        job?.cancel()
    }

    func stop(taskID: UUID) {
        guard let task = store.task(id: taskID), task.status != .completed else { return }
        if runningTaskID == taskID {
            requestedTerminalAction = (taskID, .stop)
            store.flushPendingGraphLogs(taskID: taskID)
            checkpointActiveTurn(taskID: taskID, preserveRunning: false)
            stopClockTicker()
            store.update(id: taskID) {
                $0.status = .stopping
                $0.stage = "Ending the task safely · saving progress and stopping the active agent process"
                $0.resumeOnNextLaunch = false
                $0.checkpointedAt = Date()
            }
            store.appendLog(id: taskID, kind: .warning, "End requested by the user. Progress and project files are preserved while the active agent process exits.")
            graphEngine.cancel()
            job?.cancel()
            return
        }
        store.update(id: taskID) {
            $0.status = .stopped
            $0.stage = "Stopped · progress and project files are saved"
            $0.resumeOnNextLaunch = false
            $0.checkpointedAt = Date()
        }
        store.appendLog(id: taskID, kind: .warning, "Task ended by the user. Progress and project files were preserved.")
        Task { [graphEngine] in
            _ = await graphEngine.releaseHostResources(
                taskID: taskID,
                reason: "Task ended while no Graph worker was active"
            )
        }
    }

    func chooseParallelCandidate(taskID: UUID, candidateID: String) {
        _ = candidateID
        _ = blockRetiredTaskExecution(
            taskID: taskID,
            source: "parallel candidate selection"
        )
    }

    func discardParallelCandidateWorkspaces(for task: LoopTask) {
        guard task.resolvedExecutionMode == .parallelCandidates else { return }
        Task { [graphEngine] in
            await graphEngine.cleanupParallelCandidateWorkspaces(task: task)
        }
    }

    func shutdown() {
        store.flushPendingGraphLogs()
        if let id = runningTaskID {
            checkpointActiveTurn(taskID: id, preserveRunning: false)
            let status = store.task(id: id)?.status
            store.update(id: id) {
                if status == .stopping {
                    $0.status = .stopped
                    $0.stage = "Stopped · progress and project files are saved"
                    $0.resumeOnNextLaunch = false
                } else if status == .pausing {
                    $0.status = .paused
                    $0.stage = "Paused · progress saved and no agent process is running"
                    $0.resumeOnNextLaunch = false
                } else {
                    $0.status = .paused
                    $0.stage = "Checkpoint saved; this task will continue automatically next launch"
                    $0.resumeOnNextLaunch = true
                }
                $0.checkpointedAt = Date()
            }
        }
        job?.cancel()
        graphEngine.cancel()
        ollama.stopOwnedServer()
        stopClockTicker()
        endActivity()
    }

    /// Gives ProcessRunner's interrupt/terminate/kill escalation enough time to
    /// reap the active Codex process tree before macOS tears down LoopForge.
    /// The task checkpoint is written synchronously by `shutdown()` first.
    func prepareForApplicationTermination(
        timeout: TimeInterval = 4,
        forceProcessCleanupGrace: Bool = false
    ) async {
        let hadActiveRuntime = runningTaskID != nil || forceProcessCleanupGrace
        let minimumGraceDeadline = hadActiveRuntime
            ? Date().addingTimeInterval(min(3.25, max(0, timeout)))
            : Date()
        shutdown()
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while Date() < deadline,
              runningTaskID != nil || Date() < minimumGraceDeadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if workspaceMutationRecoveryReport == nil,
           let workspaceMutationRecoveryTask {
            workspaceMutationRecoveryReport = await workspaceMutationRecoveryTask.value
        }
        _ = await graphEngine.releaseAllHostResources(
            reason: "LoopForge application termination"
        )
    }

    private func runLoop(taskID: UUID) async {
        defer {
            let finishingStatus = store.task(id: taskID)?.status
            let requestedAction = requestedTerminalAction?.taskID == taskID
                ? requestedTerminalAction?.action
                : nil
            activeTurnStartedAt = nil
            activeTurnCheckpointedSeconds = 0
            runningTaskID = nil
            job = nil
            if requestedTerminalAction?.taskID == taskID {
                requestedTerminalAction = nil
            }
            permissionAutomator.stop()
            stopClockTicker()
            endActivity()
            if requestedAction == .pause || finishingStatus == .pausing {
                store.update(id: taskID) {
                    $0.status = .paused
                    $0.stage = "Paused · progress saved and no agent process is running"
                    $0.resumeOnNextLaunch = false
                    $0.checkpointedAt = Date()
                }
                store.appendLog(id: taskID, kind: .system, "Pause complete. No agent process is running; this task can now be resumed or deleted safely.")
            } else if requestedAction == .stop || finishingStatus == .stopping {
                store.update(id: taskID) {
                    $0.status = .stopped
                    $0.stage = "Stopped · progress and project files are saved"
                    $0.resumeOnNextLaunch = false
                    $0.checkpointedAt = Date()
                }
                store.appendLog(id: taskID, kind: .system, "Task ended safely. No agent process is running; the saved task can still be resumed or deleted.")
            }
            Task { [graphEngine, store] in
                let report = await graphEngine.releaseHostResources(
                    taskID: taskID,
                    reason: "Loop task runtime ended"
                )
                guard report.failedTaskIDs.contains(taskID) else { return }
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = "Host resource cleanup needs attention"
                    $0.externalBlockerMessage = "LoopForge could not restore a host resource owned by this task. The durable lease will be retried at the next cleanup or app launch."
                    $0.resumeOnNextLaunch = false
                    $0.checkpointedAt = Date()
                }
                store.appendLog(
                    id: taskID,
                    kind: .error,
                    "A host resource could not be restored after the task runtime ended. LoopForge stopped automatic continuation and retained the lease for recovery."
                )
            }
        }
        guard !Task.isCancelled else { return }
        guard var task = store.task(id: taskID) else { return }
        var stagnantRounds = 0
        var previousAuditScore = task.auditScore
        var preparedPrompt: String?
        var preparedImages: [String] = []
        var desktopWorkerContext = ""

        do {
            guard await allowWorkAfterWorkspaceMutationRecovery(taskID: taskID) else {
                return
            }
            if let recoveryTask = hostResourceRecoveryTask {
                let report = await recoveryTask.value
                hostResourceRecoveryTask = nil
                if report.failedTaskIDs.contains(taskID) {
                    store.update(id: taskID) {
                        $0.status = .blocked
                        $0.stage = "Host resource cleanup needs attention"
                        $0.externalBlockerMessage = "LoopForge could not restore a host resource left by an interrupted Graph node. Resolve the recorded resource before resuming this task."
                        $0.resumeOnNextLaunch = false
                        $0.checkpointedAt = Date()
                    }
                    store.appendLog(
                        id: taskID,
                        kind: .error,
                        "Startup recovery could not restore one or more host resources owned by this Graph task. The task was not restarted, preventing another resource leak."
                    )
                    return
                }
                if !report.releasedLeaseIDs.isEmpty {
                    store.appendLog(
                        id: taskID,
                        kind: .system,
                        "Recovered \(report.releasedLeaseIDs.count) host resource lease\(report.releasedLeaseIDs.count == 1 ? "" : "s") left by an interrupted Graph execution."
                    )
                }
            }
            store.appendLog(
                id: taskID,
                kind: .system,
                "Architecture: \(task.resolvedControlAgent.summary) controls \(task.resolvedSubAgent.summary). Control-agent review time never counts toward the hard Sub Agent runtime."
            )
            if task.reportBaseline == nil {
                let baseline = auditor.snapshot(workspacePath: task.workspacePath, logs: task.logs)
                store.update(id: taskID) {
                    $0.reportBaseline = TaskNamePolicy.baseline(from: baseline)
                }
                task = store.task(id: taskID) ?? task
            }
            let permissionReadiness = await permissionCenter.prepareForTask(task)
            guard permissionReadiness.ready else {
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = permissionReadiness.summary
                    $0.externalBlockerKind = .automationPermission
                    $0.externalBlockerMessage = permissionReadiness.summary
                    $0.externalBlockerRetryAfter = nil
                    $0.resumeOnNextLaunch = true
                    $0.checkpointedAt = Date()
                }
                store.appendLog(id: taskID, kind: .warning, permissionReadiness.summary)
                return
            }
            if task.workerAccessMode == .fullAccess {
                store.appendLog(id: taskID, kind: .system, permissionReadiness.summary)
            }
            store.update(id: taskID) { $0.stage = "Checking the selected Sub Agent runtime" }
            let workerStatus = try await codex.verifyWorker(task: task)
            store.appendLog(id: taskID, kind: .system, workerStatus)
            permissionAutomator.start(fullAccess: task.workerAccessMode == .fullAccess) { [weak self] message in
                self?.store.appendLog(id: taskID, kind: .system, message)
            }

            if task.category == .desktopAutomation {
                store.update(id: taskID) {
                    $0.status = .preparing
                    $0.stage = "Verifying direct control of the requested signed-in app"
                }
                let readiness = await desktopAutomationPreflight.check(task: task)
                guard readiness.ready else {
                    store.update(id: taskID) {
                        $0.status = .blocked
                        $0.stage = readiness.summary
                        $0.externalBlockerKind = .automationPermission
                        $0.externalBlockerMessage = readiness.summary
                        $0.externalBlockerRetryAfter = nil
                        $0.resumeOnNextLaunch = false
                        $0.checkpointedAt = Date()
                    }
                    store.appendLog(id: taskID, kind: .warning, readiness.summary)
                    return
                }
                desktopWorkerContext = readiness.workerContext
                store.appendLog(id: taskID, kind: .system, readiness.summary)
            }

            let localProfiles = [task.resolvedControlAgent.localProfile, task.resolvedSubAgent.localProfile]
                .compactMap { $0 }
                .reduce(into: [String: ModelProfile]()) { $0[$1.ollamaName] = $1 }
                .map(\.value)
            if !localProfiles.isEmpty {
                let maximumContext = localProfiles.map(\.contextWindow).max() ?? 32_768
                try await ollama.ensureReady(contextWindow: maximumContext) { [weak self] message in
                    Task { @MainActor in self?.store.appendLog(id: taskID, kind: .system, message) }
                }
                guard !Task.isCancelled else { return }
                let progress = ProgressLogThrottler { [weak self] message in
                    Task { @MainActor in
                        self?.store.update(id: taskID) { $0.stage = message.singleLine.prefixText(100) }
                        self?.store.appendLog(id: taskID, kind: .system, message)
                    }
                }
                for profile in localProfiles {
                    store.update(id: taskID) {
                        $0.status = .preparing
                        $0.stage = "Verifying \(profile.displayName)"
                    }
                    try await ollama.requireInstalledModel(profile, onProgress: { progress.emit($0) })
                }
            }

            if task.resolvedControlAgent.provider == .codex,
               task.resolvedSubAgent.provider != .codex {
                store.appendLog(
                    id: taskID,
                    kind: .system,
                    try await codex.verifyOfficialWorker(workspacePath: task.workspacePath)
                )
            }

            task = await prepareMissionRewriteIfNeeded(taskID: taskID, task: task)

            if task.resolvedExecutionMode != .singleLoop {
                store.appendLog(
                    id: taskID,
                    kind: .system,
                    task.resolvedExecutionMode == .autoGraph
                        ? "Architecture: Main Graph Agent plans and audits a dynamic DAG; every node is an independent Sub Agent loop. Main-agent review time and blocked intervals do not count as node working time."
                        : "Architecture: independent full-goal candidates run in isolated Git worktrees. Every candidate has its own hard active-work ledger and evidence review; only the selected winner can modify the primary project."
                )
                try await graphEngine.run(
                    taskID: taskID,
                    desktopContext: desktopWorkerContext
                )
                return
            }

            if task.taskNamingCompleted != true {
                store.update(id: taskID) { $0.stage = "Loop Control Agent is creating a descriptive task label" }
                do {
                    let identity = try await supervisor.projectIdentity(for: task)
                    store.update(id: taskID) {
                        $0.title = identity.displayName
                        $0.shortTitle = identity.shortName
                        $0.taskNamingCompleted = true
                        $0.taskNamingVersion = TaskNamePolicy.currentVersion
                        $0.checkpointedAt = Date()
                    }
                    store.appendLog(id: taskID, kind: .system, "Task label: \(identity.shortName) · project: \(identity.displayName)")
                    task = store.task(id: taskID) ?? task
                } catch {
                    store.appendLog(id: taskID, kind: .warning, "The Loop Control Agent could not refine the project name; LoopForge kept the safe workspace-derived title. \(sanitizedLogText(error.localizedDescription).prefixText(240))")
                }
            }

            while !Task.isCancelled {
                guard let current = store.task(id: taskID) else { return }
                task = current

                if preparedPrompt == nil {
                    let deterministic: String
                    let phase: String
                    let observation = auditor.observe(task: task)
                    let audit = auditor.audit(task: task, snapshot: observation.snapshot)
                    if task.threadID == nil {
                        deterministic = promptCompiler.initialPrompt(for: task)
                        phase = "Initial task planning"
                    } else {
                        deterministic = promptCompiler.continuationPrompt(
                            for: task,
                            audit: audit,
                            snapshot: observation.snapshot
                        )
                        phase = "Recovered or resumed evidence audit"
                    }
                    store.update(id: taskID) {
                        $0.status = .preparing
                        $0.stage = "Loop Control Agent is reviewing the goal, code state, harness, and visual evidence"
                    }
                    let evidence = await evidenceCollector.collect(
                        task: task,
                        workerFeedback: task.lastAgentMessage,
                        audit: audit,
                        before: [:],
                        repositoryIndex: observation.repositoryIndex,
                        repositoryIndexError: observation.repositoryIndexError
                    )
                    let decision = await supervisorDecision(
                        taskID: taskID,
                        task: task,
                        deterministicBrief: deterministic,
                        phase: phase,
                        evidence: evidence
                    )
                    guard !Task.isCancelled else { return }
                    preparedPrompt = prependDesktopContext(
                        to: composePrompt(deterministic: deterministic, decision: decision, evidence: evidence),
                        context: desktopWorkerContext
                    )
                    preparedImages = task.needsVisualAudit ? evidence.screenshotPaths : []
                }

                let before = evidenceCollector.fingerprint(workspacePath: task.workspacePath)
                store.update(id: taskID) {
                    $0.status = .running
                    $0.stage = "Iteration \($0.iteration + 1): Sub Agent is executing and verifying"
                    $0.agentWaitState = .waitingForSubAgent
                    $0.lastSubAgentHeartbeatAt = Date()
                }
                store.appendLog(id: taskID, kind: .system, "Starting Sub Agent iteration \(task.iteration + 1); hard cumulative active-runtime target: \(task.targetSeconds.compactDuration).")

                let officialPrompt = preparedPrompt ?? prependDesktopContext(
                    to: promptCompiler.initialPrompt(for: task),
                    context: desktopWorkerContext
                )
                store.update(id: taskID) {
                    $0.controlInteractionCount = $0.officialInteractions + 1
                    $0.checkpointedAt = Date()
                }
                let interaction = store.task(id: taskID)?.officialInteractions ?? (task.iteration + 1)
                store.appendLog(
                    id: taskID,
                    kind: .control,
                    "LoopForge → Sub Agent #\(interaction)\n\(LocalSupervisor.boundedReviewText(officialPrompt, limit: 30_000))"
                )

                activeTurnStartedAt = Date()
                activeTurnCheckpointedSeconds = 0
                let turn = try await codex.runTurn(
                    task: task,
                    prompt: officialPrompt,
                    imagePaths: preparedImages,
                    onThreadStarted: { [weak self] threadID in
                        Task { @MainActor in self?.store.update(id: taskID) { $0.threadID = threadID } }
                    },
                    onEvent: { [weak self] kind, message in
                        Task { @MainActor in self?.store.appendLog(id: taskID, kind: kind, message) }
                    },
                    onAgentSignal: { [weak self] signal in
                        Task { @MainActor in
                            guard let self else { return }
                            switch signal {
                            case .productive:
                                self.store.update(id: taskID) {
                                    $0.agentWaitState = .signalReceived
                                    $0.lastSubAgentHeartbeatAt = Date()
                                }
                            case .transportDegraded(_):
                                self.store.update(id: taskID) {
                                    $0.agentWaitState = .waitingForSubAgent
                                }
                            case .terminalCompletion:
                                self.store.update(id: taskID) {
                                    $0.agentWaitState = .signalReceived
                                    $0.lastSubAgentHeartbeatAt = Date()
                                }
                            case .diagnostic:
                                break
                            }
                        }
                    },
                    onRuntimeEligibilityChanged: { [weak self] eligible, reason in
                        Task { @MainActor in
                            self?.handleRuntimeEligibilityChange(
                                taskID: taskID,
                                eligible: eligible,
                                reason: reason
                            )
                        }
                    }
                )
                // pause/stop already checkpointed the live segment before cancelling
                // the child process. Do not let its cancellation exit reverse those
                // persisted seconds as though it were an infrastructure failure.
                if Task.isCancelled {
                    activeTurnStartedAt = nil
                    activeTurnCheckpointedSeconds = 0
                    return
                }
                let checkpointedThisTurn = activeTurnCheckpointedSeconds
                let runtimeAdjustment = ActiveRuntimeLedger.completionAdjustment(
                    reportedTurnSeconds: turn.eligibleElapsed,
                    checkpointedSeconds: checkpointedThisTurn,
                    exitCode: turn.exitCode
                )
                activeTurnStartedAt = nil
                activeTurnCheckpointedSeconds = 0
                store.update(id: taskID) { item in
                    // A crashed or rejected automatic turn is infrastructure time, not
                    // normal official-Codex work; its saved checkpoints are reversed.
                    item.accumulatedCodexSeconds = max(0, item.accumulatedCodexSeconds + runtimeAdjustment)
                    item.threadID = turn.threadID ?? item.threadID
                    if !turn.lastAgentMessage.isEmpty { item.lastAgentMessage = turn.lastAgentMessage }
                    item.agentWaitState = .processingCompletion
                    item.lastSubAgentHeartbeatAt = Date()
                    item.checkpointedAt = Date()
                    item.logs.append(TaskLogEntry(
                        kind: .command,
                        message: "Sub Agent iteration: \(turn.commandSuccesses) commands succeeded / \(turn.commandFailures) failed; eligible active runtime \(turn.eligibleElapsed.compactDuration) of \(turn.elapsed.compactDuration) wall time; exit code \(turn.exitCode)"
                    ))
                    if item.logs.count > AppConstants.maxStoredLogs { item.logs.removeFirst(item.logs.count - AppConstants.maxStoredLogs) }
                }

                if Task.isCancelled { return }
                if turn.exitCode != 0 {
                    let detail = sanitizedLogText(turn.stderr).prefixText(800)
                    let recentFailureEvidence = (store.task(id: taskID)?.logs ?? []).suffix(30)
                        .filter { $0.kind == .error || $0.kind == .warning || $0.kind == .system }
                        .map(\.message)
                        .joined(separator: "\n")
                    let completeFailureText = [
                        detail,
                        turn.eventErrors.joined(separator: "\n"),
                        recentFailureEvidence
                    ]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    if task.threadID != nil,
                       CodexRunner.reportsMissingThread(completeFailureText) {
                        store.update(id: taskID) {
                            $0.threadID = nil
                            $0.consecutiveFailures = 0
                            $0.stage = "Saved Codex session expired; reconstructing a fresh session"
                            $0.checkpointedAt = Date()
                        }
                        store.appendLog(
                            id: taskID,
                            kind: .warning,
                            "The saved Codex session expired during resume. The failed turn was not counted; LoopForge is starting a fresh session from preserved workspace evidence."
                        )
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    if let recoveryReason = turn.recoveryReason {
                        store.update(id: taskID) {
                            $0.agentWaitState = .diagnosingSilence
                            $0.lastLoopInterventionAt = Date()
                            $0.stage = "Sub Agent heartbeat stopped; LoopForge is diagnosing retained evidence"
                        }
                        let diagnosis = await diagnoseSilentTurn(
                            task: store.task(id: taskID) ?? task,
                            reason: recoveryReason
                        )
                        store.appendLog(
                            id: taskID,
                            kind: .audit,
                            "Signal-driven intervention: \(diagnosis)"
                        )
                        store.update(id: taskID) {
                            $0.threadID = nil
                            $0.stage = "Unhealthy Codex turn ended; rebuilding a fresh session"
                            $0.checkpointedAt = Date()
                        }
                        store.appendLog(
                            id: taskID,
                            kind: .warning,
                            "\(recoveryReason) The unhealthy interval was excluded from the hard timer; the next retry will reconstruct a fresh official Codex session from durable workspace evidence."
                        )
                    }
                    if let blocker = ExternalBlockerPolicy.classifyProcessFailure(
                        completeFailureText
                    ) {
                        markBlocked(taskID: taskID, blocker: blocker)
                        return
                    }
                    store.update(id: taskID) {
                        $0.consecutiveFailures += 1
                        $0.stage = "Sub Agent exited unexpectedly; preparing an automatic retry"
                    }
                    store.appendLog(id: taskID, kind: .error, "Sub Agent exit code \(turn.exitCode): \(detail)")
                    if (store.task(id: taskID)?.consecutiveFailures ?? 0) >= InfrastructureRetryPolicy.maximumAutomaticFailures {
                        store.update(id: taskID) {
                            $0.status = .failed
                            $0.stage = "Paused after \(InfrastructureRetryPolicy.maximumAutomaticFailures) independent Codex recovery attempts; the workspace and runtime checkpoint are safe"
                            $0.resumeOnNextLaunch = false
                        }
                        return
                    }
                    let failureCount = store.task(id: taskID)?.consecutiveFailures ?? 1
                    if InfrastructureRetryPolicy.shouldStartFreshSession(afterFailureCount: failureCount) {
                        store.update(id: taskID) { $0.threadID = nil }
                        store.appendLog(id: taskID, kind: .warning, "The existing Codex session failed repeatedly. The next retry will start a fresh session and reconstruct context from the workspace evidence.")
                    }
                    let delay = InfrastructureRetryPolicy.delaySeconds(afterFailureCount: failureCount)
                    store.update(id: taskID) {
                        $0.stage = "Codex recovery \(failureCount)/\(InfrastructureRetryPolicy.maximumAutomaticFailures) in \(delay.compactDuration)"
                    }
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                preparedPrompt = nil
                preparedImages = []
                let blockerClaimed = ExternalBlockerPolicy.isClaimed(in: turn.lastAgentMessage)
                let blockerVerified = ExternalBlockerPolicy.isVerified(
                    agentMessage: turn.lastAgentMessage,
                    recentLogs: store.task(id: taskID)?.logs ?? [],
                    commandFailures: turn.commandFailures
                )
                if blockerVerified {
                    let blocker = ExternalBlockerPolicy.assessmentForVerifiedClaim(turn.lastAgentMessage)
                    markBlocked(taskID: taskID, blocker: blocker)
                    store.appendLog(id: taskID, kind: .warning, "Loop stopped safely at a command-confirmed external boundary. No further Codex runtime will be consumed until the requirement is resolved and the task is resumed.")
                    return
                }
                if blockerClaimed {
                    store.update(id: taskID) { $0.threadID = nil }
                    store.appendLog(id: taskID, kind: .warning, "An unsupported blocker claim was rejected; the next iteration will re-inspect the workspace.")
                }

                guard var postTurnTask = store.task(id: taskID) else { return }
                postTurnTask.visualAuditPassed = postTurnTask.needsVisualAudit ? nil : postTurnTask.visualAuditPassed
                // The preliminary scan deliberately omits the visual-approval gate: the
                // local VLM is the component about to make that decision. The final scan
                // below reinstates the gate, preventing a circular approval dependency.
                let observation = auditor.observe(task: postTurnTask)
                let preliminaryAudit = auditor.audit(
                    task: postTurnTask,
                    snapshot: observation.snapshot,
                    requireVisualApproval: false
                )
                let evidence = await evidenceCollector.collect(
                    task: postTurnTask,
                    workerFeedback: turn.lastAgentMessage,
                    audit: preliminaryAudit,
                    before: before,
                    repositoryIndex: observation.repositoryIndex,
                    repositoryIndexError: observation.repositoryIndexError
                )
                let snapshot = observation.snapshot
                let deterministic = promptCompiler.continuationPrompt(for: postTurnTask, audit: preliminaryAudit, snapshot: snapshot)
                store.update(id: taskID) {
                    $0.status = .auditing
                    $0.stage = "Loop Control Agent is auditing Sub Agent feedback against code, harness, and screenshots"
                    $0.agentWaitState = .processingCompletion
                }
                let decision = await supervisorDecision(
                    taskID: taskID,
                    task: postTurnTask,
                    deterministicBrief: deterministic,
                    phase: "Post-official-Codex stage \(postTurnTask.iteration + 1)",
                    evidence: evidence
                )
                guard !Task.isCancelled else { return }
                let basicVisualPassed = evidence.visualInspection?.passedBasicIntegrity == true
                let visualPassed: Bool? = postTurnTask.needsVisualAudit
                    ? (basicVisualPassed && decision.visualPassed == true)
                    : nil
                store.update(id: taskID) {
                    $0.visualAuditPassed = visualPassed
                    $0.visualAuditSummary = decision.visualSummary ?? evidence.visualInspection?.summary
                    $0.visualEvidencePaths = evidence.screenshotPaths
                    $0.lastEvidenceCoverage = evidence.coverage.map {
                        "\($0.requirement): \($0.state.rawValue)"
                    }
                    $0.supervisorCompletionApproved = decision.completionApproved && decision.status.lowercased() == "approve"
                    $0.lastSupervisorReview = decision.workerBrief
                    $0.lastControlGapKeys = decision.gapKeys
                    $0.consecutiveFailures = 0
                }

                guard let reviewedTask = store.task(id: taskID) else { return }
                let finalAudit = auditor.audit(task: reviewedTask, snapshot: snapshot)
                if finalAudit.score <= previousAuditScore { stagnantRounds += 1 } else { stagnantRounds = 0 }
                previousAuditScore = finalAudit.score
                store.update(id: taskID) {
                    $0.auditScore = finalAudit.score
                    $0.auditSummary = finalAudit.summary
                    $0.iteration += 1
                }
                let findingText = (finalAudit.findings + decision.findings).prefix(10).joined(separator: "; ")
                store.appendLog(id: taskID, kind: .audit, "Control decision: \(decision.status). \(findingText)")
                if let visualSummary = reviewedTask.visualAuditSummary, reviewedTask.needsVisualAudit {
                    store.appendLog(id: taskID, kind: .audit, "Visual audit: \(visualSummary)")
                }

                guard let audited = store.task(id: taskID) else { return }
                let supervisorApproved = audited.supervisorCompletionApproved == true
                let visualGatePassed = !audited.needsVisualAudit || audited.visualAuditPassed == true
                let currentSnapshot = snapshot
                do {
                    let statusPath = try reportGenerator.generate(
                        task: audited,
                        audit: finalAudit,
                        snapshot: currentSnapshot,
                        narrative: nil,
                        isFinal: false
                    )
                    store.update(id: taskID) {
                        $0.completionReportPath = statusPath
                        $0.reportGeneratedAt = Date()
                        if $0.reportGenerationProvider == nil {
                            $0.reportGenerationProvider = "Live deterministic evidence"
                        }
                    }
                } catch {
                    store.appendLog(
                        id: taskID,
                        kind: .warning,
                        "The live task status page could not be refreshed: \(sanitizedLogText(error.localizedDescription).prefixText(240))"
                    )
                }
                if CompletionGate.shouldComplete(
                    accumulated: audited.accumulatedCodexSeconds,
                    target: audited.targetSeconds,
                    auditPassed: finalAudit.passed && supervisorApproved && visualGatePassed
                ) {
                    store.update(id: taskID) { $0.stage = "Creating the model-authored evidence report" }
                    var reportTask = store.task(id: taskID) ?? audited
                    let reportSnapshot = snapshot
                    let authored = await completionNarrative(
                        task: reportTask,
                        audit: finalAudit,
                        snapshot: reportSnapshot
                    )
                    store.update(id: taskID) {
                        $0.reportGenerationProvider = authored.provider
                    }
                    reportTask = store.task(id: taskID) ?? reportTask
                    let reportPath = try reportGenerator.generate(
                        task: reportTask,
                        audit: finalAudit,
                        snapshot: reportSnapshot,
                        narrative: authored.narrative,
                        isFinal: true
                    )
                    store.update(id: taskID) {
                        $0.status = .completed
                        $0.stage = "Delivered · runtime, code, verification, and visual gates passed"
                        $0.completedAt = Date()
                        $0.completionReportPath = reportPath
                        $0.reportGeneratedAt = Date()
                        $0.resumeOnNextLaunch = false
                        $0.checkpointedAt = Date()
                        $0.agentWaitState = .idle
                    }
                    store.appendLog(id: taskID, kind: .audit, "Delivery report generated at \(reportPath)")
                    NSSound(named: "Glass")?.play()
                    return
                }

                if let replacement = ModelFallbackPolicy.replacement(
                    for: audited.model,
                    unchangedAuditTransitions: stagnantRounds
                ), await ollama.hasModel(replacement.ollamaName) {
                    store.update(id: taskID) {
                        $0.model = replacement
                        if $0.resolvedControlAgent.provider == .local {
                            $0.controlAgent = .local(
                                profile: replacement,
                                reasoning: $0.resolvedControlAgent.reasoningEffort,
                                access: $0.resolvedControlAgent.accessMode
                            )
                        }
                        $0.threadID = nil
                    }
                    store.appendLog(id: taskID, kind: .warning, "Evidence review stalled; switching the local Loop Control Agent to \(replacement.displayName) while preserving the Sub Agent runtime ledger.")
                    try await ollama.requireInstalledModel(replacement) { [weak self] message in
                        Task { @MainActor in self?.store.appendLog(id: taskID, kind: .system, message) }
                    }
                    stagnantRounds = 0
                } else if stagnantRounds >= 2 {
                    store.update(id: taskID) { $0.threadID = nil }
                    store.appendLog(
                        id: taskID,
                        kind: .warning,
                        "Two audits produced no score improvement. The next official turn will start a fresh Codex session and rebuild context from the goal, workspace, failures, and retained evidence."
                    )
                    stagnantRounds = 0
                }

                let remaining = max(0, audited.targetSeconds - audited.accumulatedCodexSeconds)
                store.update(id: taskID) {
                    $0.stage = remaining > 0
                        ? "Hard official-Codex runtime has \(remaining.compactDuration) remaining; continuing the audited development plan"
                        : "Runtime gate passed, but one or more evidence gates failed; continuing targeted repairs"
                }
                preparedPrompt = prependDesktopContext(
                    to: composePrompt(deterministic: deterministic, decision: decision, evidence: evidence),
                    context: desktopWorkerContext
                )
                preparedImages = audited.needsVisualAudit ? evidence.screenshotPaths : []
            }
        } catch is CancellationError {
            let status = store.task(id: taskID)?.status
            if status != .pausing, status != .stopping, status?.isActive == true {
                store.update(id: taskID) { $0.status = .paused; $0.stage = "Paused"; $0.checkpointedAt = Date() }
            }
        } catch {
            if Task.isCancelled { return }
            let message = sanitizedLogText(error.localizedDescription).prefixText(800)
            if let blocker = ExternalBlockerPolicy.classifyProcessFailure(message) {
                markBlocked(taskID: taskID, blocker: blocker)
                return
            }
            store.update(id: taskID) {
                $0.status = .failed
                $0.stage = message
                $0.resumeOnNextLaunch = false
                $0.checkpointedAt = Date()
            }
            store.appendLog(id: taskID, kind: .error, message)
        }
    }

    private func prepareMissionRewriteIfNeeded(
        taskID: UUID,
        task: LoopTask
    ) async -> LoopTask {
        guard task.missionRewriteAttempts == nil else { return task }
        let controlName = task.resolvedExecutionMode == .autoGraph
            ? "Main Graph Agent"
            : (task.resolvedExecutionMode == .parallelCandidates
               ? "Selection Agent"
               : "Loop Control Agent")
        if task.resolvedControlAgent.provider == .local {
            store.update(id: taskID) {
                $0.status = .preparing
                $0.stage = "Generating three independent mission briefs in parallel"
            }
            store.appendLog(
                id: taskID,
                kind: .control,
                "Local-model mission refinement: three independent rewrites are running in parallel. A separate semantic audit must prove fidelity to the verbatim user request before any rewrite can reach a node agent."
            )
            let refinement = await supervisor.refineMission(for: task)
            store.update(id: taskID) {
                $0.refinedRequest = refinement.selectedRequest
                $0.missionRewriteAuditSummary = refinement.auditSummary
                $0.missionRewriteAttempts = refinement.attempts
                $0.checkpointedAt = Date()
            }
            if refinement.usedOriginalFallback {
                store.appendLog(
                    id: taskID,
                    kind: .warning,
                    "Mission audit rejected every rewrite after \(refinement.attempts) round(s). The original request was preserved verbatim; no unverified rewrite was sent to a node agent. \(refinement.auditSummary)"
                )
            } else {
                store.appendLog(
                    id: taskID,
                    kind: .control,
                    "Independent mission audit selected \(refinement.selectedCandidateID ?? "the highest-fidelity candidate") after \(refinement.attempts) round(s).\n\(refinement.auditSummary)\n\nAUDITED EXECUTION BRIEF\n\(LocalSupervisor.boundedReviewText(refinement.selectedRequest, limit: 20_000))"
                )
            }
        } else {
            store.update(id: taskID) {
                $0.refinedRequest = nil
                $0.missionRewriteAuditSummary = "Not required for \(task.resolvedControlAgent.provider.title) \(controlName); the user request is used verbatim."
                $0.missionRewriteAttempts = 0
                $0.checkpointedAt = Date()
            }
            store.appendLog(
                id: taskID,
                kind: .system,
                "Mission rewriting skipped: the \(controlName) uses \(task.resolvedControlAgent.provider.title). Three-way rewriting and its audit run only for Local Deployment control models."
            )
        }
        return store.task(id: taskID) ?? task
    }

    private func supervisorDecision(
        taskID: UUID,
        task: LoopTask,
        deterministicBrief: String,
        phase: String,
        evidence: AuditEvidence
    ) async -> SupervisorDecision {
        do {
            let decision = try await supervisor.review(
                task: task,
                deterministicBrief: deterministicBrief,
                phase: phase,
                evidence: evidence
            )
            store.appendLog(id: taskID, kind: .system, "Loop Control Agent completed a targeted evidence audit; review time was excluded from the hard runtime ledger.")
            return decision
        } catch {
            store.appendLog(id: taskID, kind: .warning, "Loop Control Agent audit failed, so completion is denied and a conservative continuation brief will be used: \(sanitizedLogText(error.localizedDescription).prefixText(400))")
            return .unavailable
        }
    }

    private func diagnoseSilentTurn(task: LoopTask, reason: String) async -> String {
        let snapshot = auditor.snapshot(workspacePath: task.workspacePath, logs: task.logs)
        let system = """
        You are LoopForge's incident triage controller. A Sub Agent produced no
        semantic heartbeat for 30 minutes (or its transport deadline expired).
        Diagnose conservatively from the supplied evidence. Do not claim the
        user's task is complete. Return one concise paragraph stating the most
        likely failure layer and the safest next recovery action. A healthy
        long command may be retried from durable workspace evidence; never
        invent successful work or recommend counting the silent interval.
        """
        let user = """
        SIGNAL REASON: \(reason)
        TASK: \(task.request)
        WORKSPACE: \(task.workspacePath)
        FILES: \(snapshot.totalFiles), SOURCE: \(snapshot.sourceFiles), TESTS: \(snapshot.testFiles)
        LAST AGENT MESSAGE:
        \(LocalSupervisor.boundedReviewText(task.lastAgentMessage, limit: 4_000))
        RECENT EVENTS:
        \(task.logs.suffix(20).map { "[\($0.kind.rawValue)] \($0.message)" }.joined(separator: "\n"))
        """
        do {
            let reply = try await auxiliaryRouter.complete(
                task: task,
                codex: auxiliaryCodexSelection(for: task),
                apiConnections: agentCatalog.apiConnections,
                localProfiles: orderedLocalProfiles(for: task),
                system: system,
                user: user,
                maxTokens: 700
            )
            return "\(reply.providerLabel): \(sanitizedLogText(reply.text).prefixText(900))"
        } catch {
            return "Deterministic recovery: the silent or degraded interval is excluded, the stale child is ended, and a fresh session will reconstruct context from the saved workspace. \(sanitizedLogText(error.localizedDescription).prefixText(300))"
        }
    }

    private func completionNarrative(
        task: LoopTask,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot
    ) async -> (narrative: CompletionReportNarrative?, provider: String) {
        let system = """
        You author LoopForge's final user-facing task report from grounded
        evidence. Return only JSON matching:
        {
          "executiveSummary":"plain-language outcome",
          "completedWork":["verified item"],
          "currentExperience":"what the real product or project now does",
          "notableChanges":["specific verified change"],
          "evaluation":[{"dimension":"Quality dimension","score":0,"evidence":"specific proof"}],
          "limitations":["honest remaining gap"],
          "recommendedNextSteps":["optional follow-up"]
        }
        Scores are 0–100. Never infer a screenshot, test result, App Store
        readiness, production backend, signing state, performance gain, or
        before/after effect that is not in the supplied evidence. Clearly label
        missing proof as a limitation. Write for a user who will not inspect
        source code.
        """
        let user = """
        ORIGINAL REQUEST:
        \(LocalSupervisor.boundedReviewText(task.originalRequest ?? task.request, limit: 12_000))

        FINAL AUDIT: \(audit.score)/100 · passed=\(audit.passed)
        \(audit.summary)
        FINDINGS: \(audit.findings.joined(separator: " | "))
        NEXT: \(audit.nextActions.joined(separator: " | "))

        WORKSPACE COUNTS:
        files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles),
        docs=\(snapshot.documentationFiles), screenshots=\(snapshot.screenshotFiles)
        baseline=\(String(describing: task.reportBaseline))

        REAL SCREENSHOT PATHS:
        \((task.visualEvidencePaths ?? []).joined(separator: "\n"))

        EVIDENCE COVERAGE:
        \((task.lastEvidenceCoverage ?? []).joined(separator: "\n"))

        LAST SUB AGENT RESULT:
        \(LocalSupervisor.boundedReviewText(task.lastAgentMessage, limit: 10_000))

        RECENT VERIFIED EVENTS:
        \(task.logs.suffix(40).map { "[\($0.kind.rawValue)] \($0.message)" }.joined(separator: "\n"))
        """
        do {
            let reply = try await auxiliaryRouter.complete(
                task: task,
                codex: auxiliaryCodexSelection(for: task),
                apiConnections: agentCatalog.apiConnections,
                localProfiles: orderedLocalProfiles(for: task),
                system: system,
                user: user,
                imagePaths: task.visualEvidencePaths ?? [],
                maxTokens: 5_000
            )
            guard let narrative = CompletionReportGenerator.decodeNarrative(reply.text) else {
                throw LoopForgeError.runtimeUnavailable("The report model returned malformed JSON.")
            }
            return (narrative, reply.providerLabel)
        } catch {
            store.appendLog(
                id: task.id,
                kind: .warning,
                "Model-authored report narration was unavailable; the evidence-safe local renderer was used. \(sanitizedLogText(error.localizedDescription).prefixText(300))"
            )
            return (nil, "Deterministic evidence fallback")
        }
    }

    private func auxiliaryCodexSelection(for task: LoopTask) -> AgentSelection? {
        if task.resolvedControlAgent.provider == .codex { return task.resolvedControlAgent }
        if task.resolvedSubAgent.provider == .codex { return task.resolvedSubAgent }
        guard CodexRuntime.executable != nil else { return nil }
        return .codex(
            model: AppConstants.officialWorkerModel,
            displayName: AppConstants.officialWorkerModel,
            reasoning: "high",
            access: .workspaceOnly
        )
    }

    private func orderedLocalProfiles(for task: LoopTask) -> [ModelProfile] {
        var result: [ModelProfile] = []
        if let selected = task.resolvedControlAgent.localProfile { result.append(selected) }
        if let selected = task.resolvedSubAgent.localProfile,
           !result.contains(where: { $0.ollamaName == selected.ollamaName }) {
            result.append(selected)
        }
        for profile in agentCatalog.localModels
        where agentCatalog.isLocalModelReady(profile)
            && !result.contains(where: { $0.ollamaName == profile.ollamaName }) {
            result.append(profile)
        }
        return result
    }

    private func composePrompt(deterministic: String, decision: SupervisorDecision, evidence: AuditEvidence) -> String {
        """
        \(deterministic)

        <local_post_turn_audit authoritative="true">
        \(decision.workerBrief)

        Requirement-to-evidence inventory:
        \(evidence.coverageText)

        Evidence paths supplied to this turn: \(evidence.screenshotPaths.isEmpty ? "none" : evidence.screenshotPaths.joined(separator: ", "))
        Candidate evidence is not automatic proof. Conversely, “not observed”
        means the bounded bundle did not show the requirement; inspect the real
        workspace before claiming the feature is absent or expanding scope.
        </local_post_turn_audit>
        """
    }

    private func prependDesktopContext(to prompt: String, context: String) -> String {
        guard !context.isEmpty else { return prompt }
        return "\(context)\n\n\(prompt)"
    }

    private func markBlocked(taskID: UUID, blocker: ExternalBlockerAssessment) {
        let retryText = blocker.retryAfter.map { date in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return " Retry after \(formatter.string(from: date))."
        } ?? ""
        store.update(id: taskID) {
            $0.status = .blocked
            $0.stage = "\(blocker.kind.title) requires action before this loop can continue.\(retryText)"
            $0.externalBlockerKind = blocker.kind
            $0.externalBlockerMessage = blocker.summary
            $0.externalBlockerRetryAfter = blocker.retryAfter
            $0.resumeOnNextLaunch = false
            $0.checkpointedAt = Date()
        }
        store.appendLog(
            id: taskID,
            kind: .warning,
            "Loop paused at a verified external boundary: \(blocker.kind.title). \(blocker.summary)"
        )
    }

    private func endActivity() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    private func allowWorkAfterWorkspaceMutationRecovery(taskID: UUID) async -> Bool {
        let report: WorkspaceMutationRecoveryStartupReport
        if let workspaceMutationRecoveryReport {
            report = workspaceMutationRecoveryReport
        } else if let workspaceMutationRecoveryTask {
            report = await workspaceMutationRecoveryTask.value
            self.workspaceMutationRecoveryReport = report
        } else {
            return true
        }

        guard report.requiresAttention else {
            if report.registeredRunCount > 0 {
                let recoveredIntentCount = report.runReports.reduce(0) {
                    $0 + $1.completedIntentIDs.count
                }
                let runLabel = report.registeredRunCount == 1 ? "run" : "runs"
                let intentLabel = recoveredIntentCount == 1 ? "intent" : "intents"
                store.appendLog(
                    id: taskID,
                    kind: .system,
                    "New-kernel startup recovery completed for \(report.registeredRunCount) registered \(runLabel); \(recoveredIntentCount) durable workspace \(intentLabel) completed before agent work was admitted."
                )
            }
            return true
        }

        let attentionRunCount = report.runReports.filter(\.requiresAttention).count
        let reason = report.startupFailure?.rawValue
            ?? (!report.ownershipAcquired ? "recovery ownership unavailable" : "registered run requires attention")
        let attentionRunLabel = attentionRunCount == 1 ? "run" : "runs"
        store.update(id: taskID) {
            $0.status = .blocked
            $0.stage = "New-kernel workspace recovery needs attention"
            $0.externalBlockerKind = nil
            $0.externalBlockerMessage = "LoopForge blocked all agent and legacy Graph work because startup workspace recovery did not finish cleanly (\(reason); \(attentionRunCount) registered \(attentionRunLabel) need attention)."
            $0.externalBlockerRetryAfter = nil
            $0.resumeOnNextLaunch = false
            $0.checkpointedAt = Date()
        }
        store.appendLog(
            id: taskID,
            kind: .error,
            "Startup workspace recovery failed closed before any Codex or legacy Graph work began. Resolve the typed new-kernel recovery report before resuming this task."
        )
        return false
    }

    private func handleRuntimeEligibilityChange(taskID: UUID, eligible: Bool, reason: String) {
        guard runningTaskID == taskID,
              let task = store.task(id: taskID),
              task.status == .running else { return }
        if eligible {
            if activeTurnStartedAt == nil { activeTurnStartedAt = Date() }
            store.update(id: taskID) {
                $0.stage = "Official Codex transport recovered · productive work resumed"
                $0.checkpointedAt = Date()
            }
            store.appendLog(id: taskID, kind: .system, "Official Codex transport recovered. The hard active-runtime timer resumed.")
        } else {
            checkpointActiveTurn(taskID: taskID, preserveRunning: false)
            store.update(id: taskID) {
                $0.stage = "Official Codex is reconnecting · hard active-runtime timer paused"
                $0.checkpointedAt = Date()
            }
            store.appendLog(
                id: taskID,
                kind: .warning,
                "Official Codex transport degraded. The hard active-runtime timer is paused until semantic work resumes. \(sanitizedLogText(reason).prefixText(240))"
            )
        }
    }

    private func checkpointActiveTurn(taskID: UUID, preserveRunning: Bool, now: Date = Date()) {
        guard runningTaskID == taskID, let started = activeTurnStartedAt else { return }
        let elapsed = ActiveRuntimeLedger.segmentSeconds(from: started, to: now)
        guard elapsed > 0 else { return }
        store.update(id: taskID) {
            $0.accumulatedCodexSeconds += elapsed
            $0.checkpointedAt = now
        }
        activeTurnCheckpointedSeconds += elapsed
        activeTurnStartedAt = preserveRunning ? now : nil
    }
}

private final class ProgressLogThrottler {
    private let lock = NSLock()
    private var lastEmission = Date.distantPast
    private var lastMessage = ""
    private let callback: (String) -> Void

    init(callback: @escaping (String) -> Void) { self.callback = callback }

    func emit(_ raw: String) {
        let message = sanitizedLogText(raw)
        guard !message.isEmpty else { return }
        lock.lock()
        let shouldEmit = Date().timeIntervalSince(lastEmission) > 1.0
            || message.contains("success") || message.contains("verifying") || message.lowercased().contains("resum")
        guard shouldEmit && message != lastMessage else { lock.unlock(); return }
        lastEmission = Date()
        lastMessage = message
        lock.unlock()
        callback(message)
    }
}

private extension String {
    var singleLine: String { replacingOccurrences(of: "\n", with: " ") }
    func prefixText(_ count: Int) -> String { String(prefix(count)) }
}
