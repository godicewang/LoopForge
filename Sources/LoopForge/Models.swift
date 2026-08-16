import Foundation

enum QualityTier: String, Codable, CaseIterable, Identifiable {
    case lightweight, low, medium, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightweight: return "Lightweight"
        case .low: return "Normal"
        case .medium: return "Enhanced"
        case .high: return "Ultra"
        }
    }

    var subtitle: String {
        switch self {
        case .lightweight: return "Fast, bounded, and practical"
        case .low: return "Focused, complete, efficient"
        case .medium: return "Deeper validation and refinement"
        case .high: return "Maximum craft, coverage, and proof"
        }
    }

    var cardSummary: String {
        switch self {
        case .lightweight: return "1h default · usable result · focused verification"
        case .low: return "2h default · complete core · real smoke test"
        case .medium: return "5h default · deeper tests and refinement"
        case .high: return "10h default · release-grade proof and polish"
        }
    }

    var completionThreshold: Int {
        switch self {
        case .lightweight: return 42
        case .low: return 55
        case .medium: return 72
        case .high: return 86
        }
    }

    var defaultRuntimeMinutes: Int {
        switch self {
        case .lightweight: return 60
        case .low: return 2 * 60
        case .medium: return 5 * 60
        case .high: return 10 * 60
        }
    }

    var maximumRecommendedRuntimeMinutes: Int {
        switch self {
        case .lightweight: return 8 * 60
        case .low: return 12 * 60
        case .medium: return 24 * 60
        case .high: return 72 * 60
        }
    }

    var contract: String {
        switch self {
        case .lightweight:
            return "Deliver a focused, usable result with a repeatable entry point and one real verification path. Honor the user-confirmed active-work target."
        case .low:
            return "Deliver a complete, runnable core, concise usage instructions, and real smoke tests. Honor the user-confirmed active-work target."
        case .medium:
            return "Deliver the complete primary workflow, refined UI or API, recoverable errors, automated tests, a reproducible build, and usage documentation. No blocking TODOs. Honor the user-confirmed active-work target."
        case .high:
            return "Deliver to a release-grade bar: complete behavior, exceptional experience, edge and failure paths, performance, security and accessibility checks, systematic tests, packaging, and thorough documentation. Honor the user-confirmed active-work target."
        }
    }
}

enum LoopExecutionMode: String, Codable, CaseIterable, Identifiable {
    case singleLoop
    case parallelCandidates
    case autoGraph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleLoop: return "Single Loop"
        case .parallelCandidates: return "Parallel Candidates"
        case .autoGraph: return "Auto Graph Loop"
        }
    }

    var subtitle: String {
        switch self {
        case .singleLoop: return "One deeply supervised agent loop"
        case .parallelCandidates: return "Independent solutions, one verified winner"
        case .autoGraph: return "Dynamic parallel execution for complex work"
        }
    }
}

/// Stored `LoopTask` execution belongs to the retired narrative controller.
/// New work is enrolled as a journaled kernel run and never enters this enum.
/// Keep the enum decodable so historical tasks remain inspectable, but bind
/// every legacy mode to one fail-closed migration disposition.
enum LegacyTaskExecutionRetirementPolicy {
    static func stage(for mode: LoopExecutionMode) -> String {
        "Legacy \(mode.title) preserved · migration required"
    }

    static func blocker(for mode: LoopExecutionMode) -> String {
        "This historical \(mode.title) checkpoint has no ratified journal-kernel contract and cannot execute."
    }

    static func authoringMessage(for mode: LoopExecutionMode) -> String {
        "\(mode.title) creation is retired. Existing checkpoints remain read-only; new work requires journaled Auto Graph contract review and enrollment."
    }
}

enum ParallelCandidateSelectionMode: String, Codable, CaseIterable, Identifiable {
    case agent
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return "Agent chooses"
        case .user: return "I choose"
        }
    }
}

enum TaskCategory: String, Codable {
    case script, web, nativeApp, miniProgram, game, desktopAutomation, experiment, data, library, maintenance, optimization, research, general

    var title: String {
        switch self {
        case .script: return "Script / Automation"
        case .web: return "Web Application"
        case .nativeApp: return "Native Application"
        case .miniProgram: return "Mini Program"
        case .game: return "Game"
        case .desktopAutomation: return "Browser / Desktop Automation"
        case .experiment: return "Experiment / Baseline"
        case .data: return "Data / AI Engineering"
        case .library: return "Library / CLI"
        case .maintenance: return "Repair / Refactor"
        case .optimization: return "Performance Optimization"
        case .research: return "Research / Technical Report"
        case .general: return "General Engineering"
        }
    }

    var normallyRequiresVisualAudit: Bool {
        switch self {
        case .web, .nativeApp, .miniProgram, .game, .desktopAutomation: return true
        default: return false
        }
    }

    var prefersOfficialControlAgent: Bool {
        self == .desktopAutomation
    }
}

enum TaskAuthorization: String, Equatable {
    case buildOrModify
    case diagnosis
    case audit
    case research

    var title: String {
        switch self {
        case .buildOrModify: return "Build or modify"
        case .diagnosis: return "Diagnose only"
        case .audit: return "Audit only"
        case .research: return "Research and report"
        }
    }

    var boundary: String {
        switch self {
        case .buildOrModify:
            return "Implementation changes inside the selected workspace are authorized. Preserve unrelated user work and avoid unrelated refactors."
        case .diagnosis:
            return "Diagnose and verify the root cause. Do not change product behavior unless the request explicitly also asks for a fix. A diagnostic report may be created."
        case .audit:
            return "Inspect, test, and report evidence-backed findings. Do not implement fixes unless the request explicitly authorizes changes."
        case .research:
            return "Research and produce reproducible evidence or a report. Do not turn the task into an unrelated product implementation."
        }
    }
}

enum CodexAccessMode: String, Codable, CaseIterable, Identifiable {
    case fullAccess
    case workspaceOnly
    /// Inspection-only authority. Journaled native authoring exposes this as
    /// the mutation-free worker option, and graph-node planning also derives
    /// it for read-only nodes.
    case readOnly

    var id: String { rawValue }
    static var nativeWorkerSelectableCases: [CodexAccessMode] {
        [.readOnly, .workspaceOnly, .fullAccess]
    }
    static var independentReviewerSelectableCases: [CodexAccessMode] {
        [.readOnly]
    }
    var title: String {
        switch self {
        case .fullAccess: return "Full Access"
        case .workspaceOnly: return "Workspace Only"
        case .readOnly: return "Read Only"
        }
    }
    var subtitle: String {
        switch self {
        case .fullAccess: return "Unrestricted local tools and network"
        case .workspaceOnly: return "Changes stay inside the project folder"
        case .readOnly: return "Inspection only; product files cannot be changed"
        }
    }
    var sandboxMode: String {
        switch self {
        case .fullAccess: return "danger-full-access"
        case .workspaceOnly: return "workspace-write"
        case .readOnly: return "read-only"
        }
    }
}

struct ModelProfile: Codable, Equatable {
    let id: String
    let displayName: String
    let ollamaName: String
    let downloadSizeGB: Double
    let activeParameters: String
    let contextWindow: Int
    let reason: String
    var estimatedMemoryGBOverride: Double? = nil
    var supportsVisionOverride: Bool? = nil

    var estimatedMemoryGB: Double {
        if let estimatedMemoryGBOverride { return estimatedMemoryGBOverride }
        switch id {
        case "advanced-visual-auditor": return 29
        case "visual-auditor": return 20
        case "deep-coder": return 24
        case "reasoning-controller": return 24
        default: return 18
        }
    }

    var maximumContextWindow: Int {
        switch id {
        case "visual-auditor": return 393_216
        case "advanced-visual-auditor", "deep-coder": return 262_144
        case "reasoning-controller": return 202_752
        case "efficient-agent": return 131_072
        default: return contextWindow
        }
    }

    var supportsVision: Bool {
        supportsVisionOverride
            ?? (ollamaName.hasPrefix("qwen3.6:") || ollamaName.hasPrefix("devstral-small-2:"))
    }

    var isLoopForgeRecommendation: Bool {
        Self.all.contains { $0.id == id && $0.ollamaName == ollamaName }
    }

    var requiredOllamaCapabilities: Set<String> {
        var capabilities: Set<String> = ["completion"]
        if isLoopForgeRecommendation { capabilities.insert("tools") }
        if supportsVision { capabilities.insert("vision") }
        return capabilities
    }

    var recommendationLabel: String {
        switch id {
        case "advanced-visual-auditor": return "Best overall"
        case "visual-auditor": return "Agentic coding + vision"
        case "deep-coder": return "Code specialist"
        case "reasoning-controller": return "Deep control reasoning"
        default: return "Efficient agent"
        }
    }

    var officialLibraryURL: URL? {
        let repository = ollamaName.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ollamaName
        return URL(string: "https://ollama.com/library/\(repository)")
    }

    var resourceLabel: String {
        let active = contextWindow / 1_024
        let maximum = maximumContextWindow / 1_024
        let context = active == maximum ? "\(active)K context" : "\(active)K active · \(maximum)K max"
        return "≈\(Int(estimatedMemoryGB)) GB memory · \(context)"
    }

    static let efficientAgent = ModelProfile(
        id: "efficient-agent",
        displayName: "OpenAI gpt-oss 20B",
        ollamaName: "gpt-oss:20b",
        downloadSizeGB: 13.8,
        activeParameters: "~3.6B active / 20B total",
        contextWindow: 65_536,
        reason: "The efficient option for short audits and utility work: native function calling, structured output, and configurable reasoning with a much smaller working set."
    )

    // Compatibility aliases keep persisted tasks and routing terminology simple
    // while all efficient/reasoning work uses the same tool-capable runtime.
    static let ecoCoder = efficientAgent
    static var balancedAgent: ModelProfile { reasoningController }

    static let deepCoder = ModelProfile(
        id: "deep-coder",
        displayName: "Qwen3 Coder 30B-A3B",
        ollamaName: "qwen3-coder:30b",
        downloadSizeGB: 18.6,
        activeParameters: "3.3B active / 30B total",
        contextWindow: 65_536,
        reason: "A code-specialized MoE trained for long-horizon repository work, tool use, execution-driven repair, and large-codebase understanding."
    )

    static let visualAuditor = ModelProfile(
        id: "visual-auditor",
        displayName: "Devstral Small 2 24B",
        ollamaName: "devstral-small-2:24b",
        downloadSizeGB: 15.2,
        activeParameters: "24B agentic vision-language",
        contextWindow: 65_536,
        reason: "A strong software-engineering agent for exploring repositories, editing multiple files, using tools, and pairing screenshot evidence with code-state review."
    )

    static let advancedVisualAuditor = ModelProfile(
        id: "advanced-visual-auditor",
        displayName: "Qwen3.6 35B-A3B",
        ollamaName: "qwen3.6:35b",
        downloadSizeGB: 23.9,
        activeParameters: "~3B active / 35B total multimodal MoE",
        contextWindow: 65_536,
        reason: "The preferred M4 Pro 48GB Loop Control Agent: current agentic coding, preserved multi-turn reasoning, tool use, and visual inspection at an approximately 29GB working set."
    )

    static let reasoningController = ModelProfile(
        id: "reasoning-controller",
        displayName: "GLM-4.7-Flash 30B-A3B",
        ollamaName: "glm-4.7-flash:q4_K_M",
        downloadSizeGB: 19.0,
        activeParameters: "~3B active / 30B total reasoning MoE",
        contextWindow: 65_536,
        reason: "A text-first control and audit model with strong reasoning, coding, tool calling, and a large context window; ideal when screenshots are not required."
    )

    static let all: [ModelProfile] = [
        .advancedVisualAuditor,
        .visualAuditor,
        .deepCoder,
        .reasoningController,
        .efficientAgent
    ]

    static func profile(id: String) -> ModelProfile? { all.first { $0.id == id } }
}

struct TaskEstimate: Equatable {
    let category: TaskCategory
    let authorization: TaskAuthorization
    let recommendedSeconds: TimeInterval
    let model: ModelProfile
    let complexityScore: Int
    let explanation: String
    let visualAuditRequired: Bool
}

enum LoopTaskStatus: String, Codable {
    case preparing, downloadingModel, running, auditing, awaitingSelection, pausing, paused, blocked, completed, stopping, stopped, failed

    var title: String {
        switch self {
        case .preparing: return "Preparing"
        case .downloadingModel: return "Preparing local model"
        case .running: return "Sub Agent is working"
        case .auditing: return "Auditing deliverables"
        case .awaitingSelection: return "Choose a result"
        case .pausing: return "Pausing…"
        case .paused: return "Paused"
        case .blocked: return "Action required"
        case .completed: return "Completed"
        case .stopping: return "Ending task…"
        case .stopped: return "Stopped"
        case .failed: return "Needs attention"
        }
    }

    var isActive: Bool {
        self == .preparing || self == .downloadingModel || self == .running || self == .auditing
            || self == .pausing || self == .stopping
    }

    /// A task is visually "working" only while an agent or its preparation /
    /// audit pipeline is genuinely running. Selection and window focus never
    /// participate in this state.
    var isWorking: Bool {
        self == .preparing || self == .downloadingModel || self == .running || self == .auditing
    }
}

enum AgentWaitState: String, Codable, Equatable {
    case idle
    case waitingForSubAgent
    case signalReceived
    case diagnosingSilence
    case processingCompletion

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .waitingForSubAgent: return "Waiting for Sub Agent signal"
        case .signalReceived: return "Sub Agent heartbeat received"
        case .diagnosingSilence: return "Diagnosing missing heartbeat"
        case .processingCompletion: return "Reviewing Sub Agent completion"
        }
    }
}

enum GraphLoopPhase: String, Codable, Equatable {
    case planning
    case executing
    case selectingCandidate
    case finalAudit
    case reporting
    case completed

    var title: String {
        switch self {
        case .planning: return "Planning the graph"
        case .executing: return "Running node loops"
        case .selectingCandidate: return "Selecting the best candidate"
        case .finalAudit: return "Auditing the complete graph"
        case .reporting: return "Creating the delivery report"
        case .completed: return "Graph complete"
        }
    }
}

enum GraphNodeStatus: String, Codable, Equatable {
    case waiting
    case preparing
    case running
    case auditing
    case blocked
    case integrating
    case completed
    case failed
    /// The Main Graph Agent proved that this historical branch no longer has
    /// value after an incremental join-group review. It remains inspectable
    /// and is never treated as completed work or scheduled again.
    case superseded

    var title: String {
        switch self {
        case .waiting: return "Waiting"
        case .preparing: return "Preparing"
        case .running: return "Working"
        case .auditing: return "Under review"
        case .blocked: return "Blocked"
        case .integrating: return "Integrating"
        case .completed: return "Completed"
        case .failed: return "Needs recovery"
        case .superseded: return "Replanned"
        }
    }

    var isWorking: Bool {
        self == .preparing || self == .running || self == .auditing || self == .integrating
    }
}

enum GraphWorkspaceStrategy: String, Codable, Equatable {
    case sharedReadOnly
    case isolatedVerification
    case exclusiveWorkspace
    case gitWorktree

    var title: String {
        switch self {
        case .sharedReadOnly: return "Shared read-only"
        case .isolatedVerification: return "Disposable verification copy"
        case .exclusiveWorkspace: return "Exclusive workspace"
        case .gitWorktree: return "Isolated Git worktree"
        }
    }
}

enum GraphIterationDecision: String, Codable, Equatable {
    case pending
    case continueWork
    case recovery
    case approved
    case externalBlocker
    case superseded

    var title: String {
        switch self {
        case .pending: return "Awaiting review"
        case .continueWork: return "Continue"
        case .recovery: return "Recovery"
        case .approved: return "Approved"
        case .externalBlocker: return "Blocked"
        case .superseded: return "Replanned"
        }
    }
}

/// One durable Sub Agent execution → Main Graph Agent decision cycle. A node's
/// iteration count must never imply invisible control decisions.
struct GraphNodeIterationRecord: Codable, Identifiable, Equatable {
    var id: Int { number }
    let number: Int
    var instruction: String
    var startedAt: Date
    var finishedAt: Date?
    var threadID: String?
    var exitCode: Int?
    var agentSummary: String
    var mainReview: String
    var nextInstruction: String
    var decision: GraphIterationDecision
    /// Eligible Sub Agent runtime retained for this control cycle. Optional so
    /// checkpoints produced before build 121 continue to decode safely.
    var activeSeconds: TimeInterval? = nil
}

struct GraphLoopNode: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var objective: String
    var dependencies: [String]
    var writeScopes: [String]
    var verification: [String]
    var readOnly: Bool
    var status: GraphNodeStatus
    var iteration: Int
    var accumulatedActiveSeconds: TimeInterval
    var accumulatedBlockedSeconds: TimeInterval
    var activeStartedAt: Date?
    var blockedAt: Date?
    var threadID: String?
    var workspacePath: String?
    var isolationRootPath: String?
    var workspaceStrategy: GraphWorkspaceStrategy?
    var integrationBaseCommit: String?
    var currentInstruction: String
    var lastAgentMessage: String
    var lastReview: String
    var consecutiveFailures: Int
    var createdAt: Date
    var completedAt: Date?
    var logs: [TaskLogEntry]
    /// Nodes dispatched together normally share one join group. The Main Graph
    /// Agent may advance a completed subset only when it explicitly assigned a
    /// different group before any of those node loops started.
    var joinGroupID: String? = nil
    /// Durable replanning provenance. These fields intentionally live on the
    /// historical node so a cancelled branch remains explainable after a
    /// crash, relaunch, or later graph expansion.
    var supersededAt: Date? = nil
    var supersededReason: String? = nil
    var supersededByNodeIDs: [String]? = nil
    var replacesNodeIDs: [String]? = nil
    var planAdjustment: String? = nil
    var incrementalReviewFailures: Int? = nil
    var iterationHistory: [GraphNodeIterationRecord]? = nil
    /// A bounded node can exhaust automatic retries without freezing an
    /// otherwise productive join group. Persist this separately from
    /// `blocked` so relaunch recovery does not silently restart the same
    /// impossible turn.
    var automaticRetryDisabled: Bool? = nil
    /// Marks that a Main Graph replacement plan has already detached from the
    /// rejected Codex thread. Optional for backward-compatible checkpoint
    /// migration; build 117 checkpoints did not persist this provenance.
    var replacementPlanStartedFreshThread: Bool? = nil
    /// Version of the replacement-contract prompt semantics used to start the
    /// current thread. A newer contract can detach an already-fresh but
    /// semantically stale thread exactly once.
    var replacementPlanContractVersion: Int? = nil
    /// A node that consumes its bounded strategy budget may never be resumed
    /// as the same node. It waits for an explicit Main Graph abandon/reframe/
    /// split/replace decision instead of starting another Sub Agent turn.
    var strategyEscalationRequired: Bool? = nil
    /// Durable lesson extracted when an exhausted strategy is retired. Later
    /// planning prompts treat this as a hard anti-repeat constraint.
    var strategyLesson: String? = nil
    var strategyDecision: String? = nil

    func liveActiveSeconds(at date: Date) -> TimeInterval {
        let records = iterationHistory ?? []
        let recordedTotal = records.compactMap(\.activeSeconds).reduce(0, +)
        let recordedApprovedTotal = records
            .filter { $0.decision == .approved }
            .compactMap(\.activeSeconds)
            .reduce(0, +)
        // `accumulatedActiveSeconds` predates per-iteration timing and retains
        // accepted legacy runtime. Subtract the approved records that now have
        // exact durations so they are not counted twice, then add every known
        // iteration (approved, rejected, blocked, superseded, or pending).
        let legacyAcceptedBaseline = max(
            0,
            accumulatedActiveSeconds - recordedApprovedTotal
        )
        let liveSegment = activeStartedAt.map {
            max(0, date.timeIntervalSince($0))
        } ?? 0
        return legacyAcceptedBaseline + recordedTotal + liveSegment
    }

    /// The current control cycle's own eligible runtime. Persisted segments
    /// survive transport pauses and safe task resume; only the live segment
    /// advances with the UI clock.
    func liveCurrentIterationActiveSeconds(at date: Date) -> TimeInterval {
        let retained = iterationHistory?
            .first(where: { $0.number == iteration })?
            .activeSeconds ?? 0
        let live = activeStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return retained + live
    }

    func liveBlockedSeconds(at date: Date) -> TimeInterval {
        accumulatedBlockedSeconds + (blockedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}

struct GraphLoopState: Codable, Equatable {
    var phase: GraphLoopPhase
    var planSummary: String
    var nodes: [GraphLoopNode]
    var mainInteractionCount: Int
    var mainLastReview: String
    var maxConcurrentNodes: Int
    var supportsParallelWorktrees: Bool
    var finalRepairRounds: Int
    var createdAt: Date
    var completedAt: Date?
    /// Durable Main Graph transition barriers already reviewed. Persisting this
    /// separately from per-node approval prevents a crash or relaunch from
    /// creating the same successor frontier twice.
    var reviewedJoinGroupIDs: [String]? = nil
    /// Each independently completed node is incrementally reviewed exactly
    /// once before its join group may cross the full-group transition barrier.
    var incrementallyReviewedNodeIDs: [String]? = nil

    var activeNodes: [GraphLoopNode] { nodes.filter { $0.status != .superseded } }
    var completedNodeCount: Int { activeNodes.filter { $0.status == .completed }.count }
    var workingNodeCount: Int { nodes.filter { $0.status.isWorking }.count }
    var blockedNodeCount: Int { nodes.filter { $0.status == .blocked }.count }
    var supersededNodeCount: Int { nodes.filter { $0.status == .superseded }.count }
    var allNodesCompleted: Bool {
        !activeNodes.isEmpty && completedNodeCount == activeNodes.count
    }
    var accumulatedActiveSeconds: TimeInterval {
        nodes.reduce(0) { $0 + $1.accumulatedActiveSeconds }
    }
}

struct ReportWorkspaceBaseline: Codable, Equatable {
    let capturedAt: Date
    let totalFiles: Int
    let sourceFiles: Int
    let testFiles: Int
    let documentationFiles: Int
    let screenshotFiles: Int
}

enum LogKind: String, Codable {
    case system, agent, command, audit, control, warning, error
}

enum ExternalBlockerKind: String, Codable, Equatable {
    case usageLimit
    case authentication
    case billing
    case publisherCredential
    case legalAcceptance
    case hardware
    case requiredData
    case automationPermission

    var title: String {
        switch self {
        case .usageLimit: return "Official Codex usage limit"
        case .authentication: return "Official Codex authentication"
        case .billing: return "Account billing"
        case .publisherCredential: return "Publisher credentials"
        case .legalAcceptance: return "Legal acceptance"
        case .hardware: return "Required hardware"
        case .requiredData: return "Required external data"
        case .automationPermission: return "Interactive app control"
        }
    }
}

struct TaskLogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: LogKind
    let message: String

    init(kind: LogKind, message: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
    }
}

struct LoopTask: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let request: String
    let quality: QualityTier
    let category: TaskCategory
    let workspacePath: String
    var targetSeconds: TimeInterval
    var accumulatedCodexSeconds: TimeInterval
    var model: ModelProfile
    var status: LoopTaskStatus
    var stage: String
    var iteration: Int
    var threadID: String?
    var auditScore: Int
    var auditSummary: String
    var lastAgentMessage: String
    var consecutiveFailures: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var logs: [TaskLogEntry]
    var visualAuditRequired: Bool? = nil
    var visualAuditPassed: Bool? = nil
    var visualAuditSummary: String? = nil
    var visualEvidencePaths: [String]? = nil
    var supervisorCompletionApproved: Bool? = nil
    var lastSupervisorReview: String? = nil
    var officialModel: String? = nil
    var officialReasoningEffort: String? = nil
    var codexAccessMode: CodexAccessMode? = nil
    var shortTitle: String? = nil
    var resumeOnNextLaunch: Bool? = nil
    var checkpointedAt: Date? = nil
    var controlInteractionCount: Int? = nil
    var completionReportPath: String? = nil
    var externalBlockerKind: ExternalBlockerKind? = nil
    var externalBlockerMessage: String? = nil
    var externalBlockerRetryAfter: Date? = nil
    var lastEvidenceCoverage: [String]? = nil
    var controlAgent: AgentSelection? = nil
    var subAgent: AgentSelection? = nil
    var lastControlGapKeys: [String]? = nil
    var refinedRequest: String? = nil
    var missionRewriteAuditSummary: String? = nil
    var missionRewriteAttempts: Int? = nil
    var originalRequest: String? = nil
    var promptOptimizationSource: String? = nil
    var completionViewedAt: Date? = nil
    var reportBaseline: ReportWorkspaceBaseline? = nil
    var reportGeneratedAt: Date? = nil
    var reportGenerationProvider: String? = nil
    var agentWaitState: AgentWaitState? = nil
    var lastSubAgentHeartbeatAt: Date? = nil
    var lastLoopInterventionAt: Date? = nil
    var taskNamingCompleted: Bool? = nil
    var taskNamingVersion: Int? = nil
    var executionMode: LoopExecutionMode? = nil
    var graphState: GraphLoopState? = nil
    var parallelCandidateCount: Int? = nil
    var parallelSelectionMode: ParallelCandidateSelectionMode? = nil
    var selectedCandidateID: String? = nil
    var parallelSelectionSummary: String? = nil
    var parallelWinnerIntegrated: Bool? = nil

    var progress: Double {
        if resolvedExecutionMode != .singleLoop, let graphState {
            guard !graphState.activeNodes.isEmpty else { return 0 }
            return Double(graphState.completedNodeCount) / Double(graphState.activeNodes.count)
        }
        guard targetSeconds > 0 else { return 0 }
        return min(1, accumulatedCodexSeconds / targetSeconds)
    }

    var canResume: Bool { status == .paused || status == .blocked || status == .failed || status == .stopped }

    var needsVisualAudit: Bool {
        visualAuditRequired ?? TaskEstimator().requiresVisualAudit(request: request, category: category)
    }


    var workerModel: String { subAgent?.modelID ?? officialModel ?? AppConstants.officialWorkerModel }
    var workerReasoningEffort: String {
        subAgent?.reasoningEffort ?? officialReasoningEffort ?? {
            switch quality {
            case .lightweight: return "low"
            case .low: return "low"
            case .medium: return "medium"
            case .high: return "high"
            }
        }()
    }
    var workerAccessMode: CodexAccessMode { subAgent?.accessMode ?? codexAccessMode ?? .workspaceOnly }

    var resolvedControlAgent: AgentSelection {
        controlAgent ?? .local(profile: model, access: .workspaceOnly)
    }

    var resolvedSubAgent: AgentSelection {
        subAgent ?? .codex(
            model: workerModel,
            displayName: workerModel,
            reasoning: workerReasoningEffort,
            access: workerAccessMode
        )
    }

    var displayTaskSummary: String {
        let supplied = shortTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !supplied.isEmpty { return String(supplied.prefix(64)) }
        return TaskNamePolicy.descriptiveSummary(request: originalRequest ?? request, fallback: title)
    }

    var officialInteractions: Int { controlInteractionCount ?? iteration }

    var resolvedExecutionMode: LoopExecutionMode { executionMode ?? .singleLoop }

    var resolvedParallelCandidateCount: Int {
        min(8, max(2, parallelCandidateCount ?? 3))
    }

    var resolvedParallelSelectionMode: ParallelCandidateSelectionMode {
        parallelSelectionMode ?? .agent
    }

    var effectiveRequest: String {
        guard resolvedControlAgent.provider == .local else { return request }
        let refined = refinedRequest?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return refined.isEmpty ? request : refined
    }
}

enum TaskNamePolicy {
    static let currentVersion = 2

    /// A deterministic fallback for times when the naming model is unavailable.
    /// It intentionally describes the action and subject instead of producing
    /// an opaque initialism.
    static func descriptiveSummary(request: String, fallback: String) -> String {
        let clean = request
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return String(fallback.prefix(64)) }

        let terminators = CharacterSet(charactersIn: "。！？!?；;\n")
        let firstClause = clean.components(separatedBy: terminators).first ?? clean
        let chineseCount = firstClause.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        if chineseCount >= 2 {
            let lower = clean.lowercased()
            let action: String
            if lower.contains("修复") || lower.contains("错误") || lower.contains("bug") {
                action = "修复"
            } else if lower.contains("优化") || lower.contains("提升") || lower.contains("改进") {
                action = "优化"
            } else if lower.contains("打磨") || lower.contains("完善") {
                action = "打磨"
            } else {
                action = "打造"
            }

            if lower.contains("ios"),
               lower.contains("游戏") || lower.contains("手游") {
                var attributes: [String] = []
                if lower.contains("中文") { attributes.append("中文") }
                if lower.contains("卡通") { attributes.append("卡通") }
                if lower.contains("生存") || lower.contains("幸存者") { attributes.append("生存") }
                if lower.contains("建造") || lower.contains("领地") { attributes.append("建造") }
                return "\(action)\(attributes.prefix(4).joined()) iOS 手游"
            }
            if lower.contains("unity") && (lower.contains("包错误") || lower.contains("package")) {
                return "\(action) Unity 包与项目运行错误"
            }
            if lower.contains("npc") && (lower.contains("游戏") || lower.contains("demo")) {
                if lower.contains("物理") || lower.contains("自由度") {
                    return "\(action)智能 NPC 与高自由度游戏系统"
                }
                return "\(action)智能 NPC 游戏系统"
            }
            if lower.contains("浏览器") || lower.contains("chrome") {
                return "\(action)浏览器自动化任务"
            }

            let clauses = clean.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;：:\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let scored = clauses.enumerated().max { lhs, rhs in
                clauseScore(lhs.element) < clauseScore(rhs.element)
            }?.element ?? firstClause
            let stripped = scored.replacingOccurrences(
                of: #"^(?:请|请帮我|帮我|需要|要求|根据)[，,\s]*"#,
                with: "",
                options: .regularExpression
            )
            return String(stripped.prefix(24))
        }

        let ignored: Set<String> = [
            "please", "could", "would", "should", "the", "a", "an", "this", "that",
            "current", "project", "deeply", "carefully", "help", "me", "to", "and"
        ]
        let words = firstClause.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !ignored.contains($0.lowercased()) }
        let selected = words.prefix(7).joined(separator: " ")
        return selected.isEmpty ? String(fallback.prefix(64)) : String(selected.prefix(64))
    }

    static func baseline(from snapshot: WorkspaceSnapshot, at date: Date = Date()) -> ReportWorkspaceBaseline {
        ReportWorkspaceBaseline(
            capturedAt: date,
            totalFiles: snapshot.totalFiles,
            sourceFiles: snapshot.sourceFiles,
            testFiles: snapshot.testFiles,
            documentationFiles: snapshot.documentationFiles,
            screenshotFiles: snapshot.screenshotFiles
        )
    }

    private static func clauseScore(_ clause: String) -> Int {
        let lower = clause.lowercased()
        let positive = [
            "修复", "优化", "实现", "开发", "构建", "完成", "打磨", "完善",
            "npc", "unity", "ios", "游戏", "应用", "脚本", "实验", "性能", "错误"
        ].reduce(0) { $0 + (lower.contains($1) ? 4 : 0) }
        let negative = ["请根据", "当前的设定", "我希望", "主要包括如下"].reduce(0) {
            $0 + (lower.contains($1) ? 3 : 0)
        }
        return positive - negative - max(0, clause.count - 80) / 20
    }
}

struct WorkspaceSnapshot: Equatable {
    var totalFiles = 0
    var sourceFiles = 0
    var sourceBytes: Int64 = 0
    var testFiles = 0
    var documentationFiles = 0
    var manifestFiles = 0
    var executionEntryPointFiles = 0
    var resultFiles = 0
    var screenshotFiles = 0
    var imageFiles = 0
    var recentCommandFailures = 0
    var recentCommandSuccesses = 0
    var unresolvedVerificationFailures = 0
    var lastVerificationSucceeded: Bool? = nil
    var samplePaths: [String] = []
}

struct AuditResult: Equatable {
    let score: Int
    let passed: Bool
    let summary: String
    let findings: [String]
    let nextActions: [String]
}

enum CompletionGate {
    static func shouldComplete(accumulated: TimeInterval, target: TimeInterval, auditPassed: Bool) -> Bool {
        accumulated >= target && auditPassed
    }
}

enum ActiveRuntimeLedger {
    static func segmentSeconds(from startedAt: Date, to now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }

    static func remainingUncheckpointed(reportedTurnSeconds: TimeInterval, checkpointedSeconds: TimeInterval) -> TimeInterval {
        max(0, reportedTurnSeconds - checkpointedSeconds)
    }

    /// Checkpoints are already persisted while a turn is alive. A normal turn
    /// receives only the remainder; a failed automatic turn reverses its
    /// checkpoints so infrastructure failures cannot satisfy the hard gate.
    static func completionAdjustment(
        reportedTurnSeconds: TimeInterval,
        checkpointedSeconds: TimeInterval,
        exitCode: Int32
    ) -> TimeInterval {
        exitCode == 0
            ? remainingUncheckpointed(reportedTurnSeconds: reportedTurnSeconds, checkpointedSeconds: checkpointedSeconds)
            : -max(0, checkpointedSeconds)
    }
}

enum ModelFallbackPolicy {
    static func replacement(for model: ModelProfile, unchangedAuditTransitions: Int) -> ModelProfile? {
        guard unchangedAuditTransitions >= 2, model == .deepCoder else { return nil }
        return .efficientAgent
    }
}

struct ExternalBlockerAssessment: Equatable {
    let kind: ExternalBlockerKind
    let summary: String
    let retryAfter: Date?
}

enum InfrastructureRetryPolicy {
    static let maximumAutomaticFailures = 5

    static func delaySeconds(afterFailureCount count: Int) -> TimeInterval {
        switch count {
        case ..<2: return 4
        case 2: return 8
        case 3: return 30
        case 4: return 120
        default: return 300
        }
    }

    static func shouldStartFreshSession(afterFailureCount count: Int) -> Bool {
        count >= 2
    }
}

enum ExternalBlockerPolicy {
    private static let marker = "loopforge_status: blocked"
    private static let externalSignals = [
        "unauthorized", "authentication required", "login required", "invalid api key", "missing api key",
        "forbidden", "permission denied", "payment required", "billing required", "quota exceeded",
        "usage limit", "license acceptance required", "hardware unavailable", "required dataset is missing",
        "apple distribution", "mac app distribution", "distribution certificate", "signing identity",
        "developer team", "app store connect", "provisioning profile", "publisher-controlled"
    ]
    /// Some external checks report a conclusive absence while still exiting 0.
    /// `security find-identity`, for example, prints `0 valid identities found`.
    private static let conclusiveEvidenceSignals = [
        "0 valid identities found", "code object is not signed at all", "source=no usable signature",
        "no matching provisioning profiles found", "no accounts with app store connect access",
        "certificate records: 0"
    ]

    static func isClaimed(in agentMessage: String) -> Bool {
        agentMessage.lowercased().contains(marker)
    }

    static func isVerified(agentMessage: String, recentLogs: [TaskLogEntry], commandFailures: Int) -> Bool {
        let claim = agentMessage.lowercased()
        guard claim.contains(marker), externalSignals.contains(where: claim.contains) else { return false }
        let evidence = recentLogs.suffix(40)
            .filter { $0.kind == .command || $0.kind == .error }
            .map(\.message).joined(separator: "\n").lowercased()
        if conclusiveEvidenceSignals.contains(where: evidence.contains) { return true }
        return commandFailures > 0 && externalSignals.contains(where: evidence.contains)
    }

    /// Process-level account failures are authoritative even when Codex cannot
    /// produce a final LOOPFORGE_STATUS marker. This path catches quota and
    /// authentication exits before they are mistaken for retryable crashes.
    static func classifyProcessFailure(_ rawEvidence: String) -> ExternalBlockerAssessment? {
        let evidence = rawEvidence.lowercased()
        let kind: ExternalBlockerKind?
        if ["usage limit", "quota exceeded", "you've hit your usage limit", "too many requests for your account"]
            .contains(where: evidence.contains) {
            kind = .usageLimit
        } else if ["not authenticated", "authentication required", "login required", "please run codex login", "unauthorized"]
            .contains(where: evidence.contains) {
            kind = .authentication
        } else if ["payment required", "billing required", "purchase more credits"]
            .contains(where: evidence.contains) {
            kind = evidence.contains("usage limit") ? .usageLimit : .billing
        } else {
            kind = nil
        }
        guard let kind else { return nil }
        return ExternalBlockerAssessment(
            kind: kind,
            summary: conciseSummary(from: rawEvidence, kind: kind),
            retryAfter: retryDate(in: rawEvidence)
        )
    }

    static func assessmentForVerifiedClaim(_ agentMessage: String) -> ExternalBlockerAssessment {
        let lower = agentMessage.lowercased()
        let kind: ExternalBlockerKind
        if lower.contains("usage limit") || lower.contains("quota") {
            kind = .usageLimit
        } else if lower.contains("authentication") || lower.contains("login") || lower.contains("api key") {
            kind = .authentication
        } else if lower.contains("payment") || lower.contains("billing") {
            kind = .billing
        } else if lower.contains("license") || lower.contains("legal") {
            kind = .legalAcceptance
        } else if lower.contains("hardware") {
            kind = .hardware
        } else if lower.contains("dataset") || lower.contains("required data") {
            kind = .requiredData
        } else {
            kind = .publisherCredential
        }
        return ExternalBlockerAssessment(
            kind: kind,
            summary: sanitizedLogText(agentMessage).prefixText(800),
            retryAfter: retryDate(in: agentMessage)
        )
    }

    private static func retryDate(in text: String) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?:try again|retry)(?:\s+at|\s+after)?\s+([A-Z][a-z]{2,8}\s+\d{1,2}(?:st|nd|rd|th)?,\s+\d{4}\s+\d{1,2}:\d{2}\s+(?:AM|PM))"#
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        let cleaned = String(text[valueRange])
            .replacingOccurrences(of: #"(\d+)(st|nd|rd|th)"#, with: "$1", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter.date(from: cleaned)
    }

    private static func conciseSummary(from text: String, kind: ExternalBlockerKind) -> String {
        let preferredSignals: [String]
        switch kind {
        case .usageLimit:
            preferredSignals = ["you've hit your usage limit", "usage limit", "quota exceeded", "purchase more credits"]
        case .authentication:
            preferredSignals = ["not authenticated", "authentication required", "login required", "please run codex login", "unauthorized"]
        case .billing:
            preferredSignals = ["payment required", "billing required"]
        default:
            preferredSignals = externalSignals
        }
        let lines = sanitizedLogText(text).split(separator: "\n").map(String.init)
        let candidates = lines.filter { line in
            let lower = line.lowercased()
            return preferredSignals.contains(where: lower.contains)
        }
        let best = candidates.min { $0.count < $1.count }
            ?? sanitizedLogText(text)
        return best.prefixText(800)
    }
}

enum AppConstants {
    static let appName = "LoopForge"
    static let bundleIdentifier = "com.loopforge.autocoder"
    static let officialWorkerModel = "gpt-5.6-sol"
    static let maxStoredLogs = 2_000
    static let minimumCustomRuntimeMinutes = 15
    static let ollamaHost = "127.0.0.1:11434"
    static let codexOnboardingKey = "loopforge.codex-onboarding-complete.v3"
    static let watcherGuideCompletedKey = "loopforge.watcher-guide-complete.v1"
    static let appManagementConfirmationKey = "loopforge.app-management-confirmed.v1"
    static let permissionOnboardingDismissedKey = "loopforge.permission-onboarding-dismissed.v1"
}

extension TimeInterval {
    var compactDuration: String {
        let seconds = max(0, Int(self))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, secs) }
        return "\(secs)s"
    }
}

private extension String {
    func prefixText(_ count: Int) -> String { String(prefix(count)) }
}
