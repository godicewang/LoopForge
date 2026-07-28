import Foundation

enum LoopForgeModule: String, CaseIterable, Identifiable {
    case autoLoop
    case continuumWatcher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoLoop: return "Auto Loop"
        case .continuumWatcher: return "Continuum Watcher"
        }
    }

    var subtitle: String {
        switch self {
        case .autoLoop: return "Autonomous project work"
        case .continuumWatcher: return "Durable monitoring and batch pipelines"
        }
    }

    var symbol: String {
        switch self {
        case .autoLoop: return "infinity"
        case .continuumWatcher: return "waveform.path.ecg"
        }
    }
}

enum WatcherStatus: String, Codable, CaseIterable {
    case preparing
    case active
    case runningPipeline
    case reviewing
    case paused
    case needsAttention
    case completed
    case stopped

    var title: String {
        switch self {
        case .preparing: return "Building pipeline"
        case .active: return "Watching"
        case .runningPipeline: return "Pipeline is running"
        case .reviewing: return "Agent is reviewing"
        case .paused: return "Paused"
        case .needsAttention: return "Needs attention"
        case .completed: return "Completed"
        case .stopped: return "Stopped"
        }
    }

    var isWorking: Bool {
        self == .preparing || self == .runningPipeline || self == .reviewing
    }

    var shouldSchedule: Bool {
        self == .active || self == .runningPipeline || self == .reviewing
    }
}

enum WatcherSeverity: String, Codable, Comparable {
    case info
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    static func < (lhs: WatcherSeverity, rhs: WatcherSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum WatcherEventKind: String, Codable {
    case created
    case pipelineRun
    case threshold
    case anomaly
    case staleSignal
    case pipelineFailure
    case scheduledReview
    case manualReview
    case repaired
    case notification
    case lifecycle
    case completed
}

struct WatcherEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: WatcherEventKind
    let severity: WatcherSeverity
    let message: String
    let signalKey: String?
    let value: Double?
    let provider: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: WatcherEventKind,
        severity: WatcherSeverity = .info,
        message: String,
        signalKey: String? = nil,
        value: Double? = nil,
        provider: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.severity = severity
        self.message = message
        self.signalKey = signalKey
        self.value = value
        self.provider = provider
    }
}

enum WatcherSignalKind: String, Codable, CaseIterable {
    case gauge
    case counter
    case duration
    case rate
    case ratio
    case progress
    case dataQuality
    case heartbeat
    case event

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // This field controls presentation only. A future or Agent-authored
        // kind must not invalidate an otherwise safe, executable manifest.
        self = Self(rawValue: value) ?? .gauge
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct WatcherSignalSpec: Codable, Identifiable, Equatable {
    var id: String { key }
    var key: String
    var title: String
    var kind: WatcherSignalKind
    var unit: String
    var description: String
    var expectedMinimum: Double?
    var expectedMaximum: Double?
    var staleAfterSeconds: TimeInterval?
}

enum WatcherRuleComparator: String, Codable, CaseIterable {
    case above
    case below
    case outside
    case equals
    case missing
    case stale
    case changed
}

struct WatcherRule: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var signalKey: String
    var comparator: WatcherRuleComparator
    var threshold: Double?
    var upperThreshold: Double?
    var requiredConsecutiveMatches: Int
    var cooldownSeconds: TimeInterval
    var severity: WatcherSeverity
    var wakesAgent: Bool
}

struct WatcherPipeline: Codable, Equatable {
    var schemaVersion: Int
    var revision: Int
    var command: [String]
    var workingDirectory: String
    var telemetryPath: String
    var checkpointPath: String
    var generatedPaths: [String]
    var verificationCommands: [[String]]
    var pollIntervalSeconds: TimeInterval
    var reviewIntervalSeconds: TimeInterval
    var timeoutSeconds: TimeInterval
    var signals: [WatcherSignalSpec]
    var rules: [WatcherRule]
}

struct WatcherTelemetryEvent: Codable, Equatable {
    var name: String
    var severity: WatcherSeverity?
    var message: String?
}

struct WatcherTelemetryEnvelope: Codable, Equatable {
    var schemaVersion: Int?
    var capturedAt: Date?
    var status: String?
    var summary: String?
    var signals: [String: Double]
    var events: [WatcherTelemetryEvent]?
    var completed: Bool?
    var checkpoint: String?
}

struct WatcherRuntimeState: Codable, Equatable {
    var lastRunAt: Date?
    var nextRunAt: Date?
    var lastSuccessfulRunAt: Date?
    var lastReviewAt: Date?
    var nextReviewAt: Date?
    var totalRuns: Int
    var agentWakeups: Int
    var consecutiveFailures: Int
    var lastExitCode: Int32?
    var lastSummary: String
    var latestSignals: [String: Double]
    var latestSignalAt: [String: Date]
    var ruleMatchCounts: [String: Int]
    var ruleLastTriggeredAt: [String: Date]

    static let empty = WatcherRuntimeState(
        lastRunAt: nil,
        nextRunAt: nil,
        lastSuccessfulRunAt: nil,
        lastReviewAt: nil,
        nextReviewAt: nil,
        totalRuns: 0,
        agentWakeups: 0,
        consecutiveFailures: 0,
        lastExitCode: nil,
        lastSummary: "Waiting for the first pipeline run",
        latestSignals: [:],
        latestSignalAt: [:],
        ruleMatchCounts: [:],
        ruleLastTriggeredAt: [:]
    )
}

struct ContinuumWatcher: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let request: String
    let workspacePath: String
    var status: WatcherStatus
    var pipeline: WatcherPipeline?
    var runtime: WatcherRuntimeState
    var events: [WatcherEvent]
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var resumeOnNextLaunch: Bool
    var notificationsEnabled: Bool
    var launchAtLogin: Bool
    var agentSelection: AgentSelection? = nil
    var lastProvider: String?
    var lastAgentMessage: String
    var bootstrapThreadID: String?
    var reviewThreadID: String?

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(64)) }
        return String(TaskNamePolicy.descriptiveSummary(request: request, fallback: "Watcher").prefix(64))
    }
}

struct WatcherEvaluation: Equatable {
    var events: [WatcherEvent]
    var shouldWakeAgent: Bool
    var highestSeverity: WatcherSeverity
}
