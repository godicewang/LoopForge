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

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch value {
        case "info", "information", "low":
            self = .info
        case "warning", "warn", "medium":
            self = .warning
        case "critical", "error", "fatal", "high", "severe":
            self = .critical
        default:
            // Agent-authored manifests occasionally use provider-specific
            // severity words. Keep the document executable while treating an
            // unknown alert level conservatively instead of failing the whole
            // verified pipeline or silently downgrading it to informational.
            self = .warning
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

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
    case agentProgress
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

enum WatcherDashboardPreset: String, Codable, CaseIterable {
    case general
    case operations
    case batch
    case experiment
    case condition
    case research
    case dataQuality

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .general
    }
}

struct WatcherGoalAnchor: Codable, Identifiable, Equatable {
    var id: String
    var title: String
}

struct WatcherDashboardSpec: Codable, Equatable {
    var headline: String
    var preset: WatcherDashboardPreset = .general
    var goalAnchors: [WatcherGoalAnchor] = []
    var progressSignalKey: String?
    var primarySignalKeys: [String]
    var importantSignalKeys: [String]
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
    var dashboard: WatcherDashboardSpec? = nil
}

struct WatcherTelemetryEvent: Codable, Equatable {
    var name: String
    var severity: WatcherSeverity?
    var message: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case kind
        case severity
        case message
    }

    init(name: String, severity: WatcherSeverity?, message: String?) {
        self.name = name
        self.severity = severity
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decodeIfPresent(String.self, forKey: .kind)
            ?? "pipeline_event"
        severity = try container.decodeIfPresent(WatcherSeverity.self, forKey: .severity)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(severity, forKey: .severity)
        try container.encodeIfPresent(message, forKey: .message)
    }
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
    var activeIssues: [WatcherDetectedIssue]? = nil

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
        ruleLastTriggeredAt: [:],
        activeIssues: []
    )
}

struct WatcherDetectedIssue: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var severity: WatcherSeverity
    var signalKey: String?
    var value: Double?
    var detectedAt: Date
    var lastSeenAt: Date
    var userActionRequired: Bool
}

enum WatcherIssueDisposition: String, Codable, CaseIterable {
    case confirmed
    case dismissed
    case resolved
}

struct WatcherAgentIssueAssessment: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var disposition: WatcherIssueDisposition
    var severity: WatcherSeverity
    var evidence: String
    var userActionRequired: Bool
}

struct WatcherImportantInformation: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var severity: WatcherSeverity
    var signalKey: String?
    var value: Double?
    var unit: String?
    var goalAnchorID: String?
    var userActionRequired: Bool
}

struct WatcherAgentAssessment: Codable, Equatable {
    var schemaVersion: Int
    var reviewedAt: Date
    var headline: String
    var summary: String
    var issues: [WatcherAgentIssueAssessment]
    var importantInformation: [WatcherImportantInformation]
}

enum WatcherIndependentReviewVerdict: String, Codable, Equatable {
    case approved
    case rejected

    static func parse(_ response: String) throws -> WatcherIndependentReviewVerdict {
        let markers: [(String, WatcherIndependentReviewVerdict)] = [
            ("LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED", .approved),
            ("LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: REJECTED", .rejected)
        ]
        let upper = response.uppercased()
        let matches = markers.filter { upper.contains($0.0) }
        guard matches.count == 1, let verdict = matches.first?.1 else {
            throw WatcherPolicyError.invalidTelemetry(
                "independent review must end with exactly one approval marker"
            )
        }
        return verdict
    }
}

/// An adaptive Watcher review is only advisory until a fresh, read-only
/// lineage approves the exact pipeline and assessment bytes. The receipt is
/// retained with the Watcher so a relaunch cannot silently turn an
/// unreviewed Agent assertion into authoritative product state.
struct WatcherIndependentReviewReceipt: Codable, Equatable {
    var schemaVersion: Int
    var reviewedAt: Date
    var authorThreadID: String
    var reviewerThreadID: String
    var authorLineageDigest: ContentDigest
    var reviewerLineageDigest: ContentDigest
    var pipelineDigest: ContentDigest
    var assessmentDigest: ContentDigest
    var completionReceiptDigest: ContentDigest? = nil
    var verdict: WatcherIndependentReviewVerdict
    var reviewerProvider: String
    var evidence: String
}

struct WatcherDeterministicCompletionObservation: Codable, Equatable {
    var schemaVersion: Int
    var pipelineRevision: Int
    var pipelineRunNumber: Int
    var capturedAt: Date
    var observedAt: Date
    var telemetryDigest: ContentDigest
    var checkpointDigest: ContentDigest
    var checkpointLabel: String
    var unresolvedIssueIDs: [String]
}

struct WatcherDeterministicCompletionReceipt: Codable, Equatable {
    var schemaVersion: Int
    var verifiedAt: Date
    var observation: WatcherDeterministicCompletionObservation
    var verificationPlanDigest: ContentDigest
    var assessmentDigest: ContentDigest
    var coveredGoalAnchorIDs: [String]
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
    var requestedPollIntervalSeconds: TimeInterval? = nil
    var requestedReviewIntervalSeconds: TimeInterval? = nil
    var reportPath: String? = nil
    var latestAssessment: WatcherAgentAssessment? = nil
    var latestIndependentReview: WatcherIndependentReviewReceipt? = nil
    var pendingCompletionObservation: WatcherDeterministicCompletionObservation? = nil
    var latestCompletionReceipt: WatcherDeterministicCompletionReceipt? = nil

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(64)) }
        return String(TaskNamePolicy.descriptiveSummary(request: request, fallback: "Watcher").prefix(64))
    }

    var independentlyApprovedAssessment: WatcherAgentAssessment? {
        guard let pipeline,
              let assessment = latestAssessment,
              let receipt = latestIndependentReview,
              receipt.verdict == .approved,
              (try? WatcherIndependentReviewPolicy.validate(
                  receipt,
                  pipeline: pipeline,
                  assessment: assessment,
                  completionReceipt: latestCompletionReceipt,
                  authorThreadID: receipt.authorThreadID
              )) != nil else { return nil }
        return assessment
    }

    var isDeterministicallyCompleted: Bool {
        guard status == .completed,
              let pipeline,
              let assessment = latestAssessment,
              let receipt = latestCompletionReceipt,
              independentlyApprovedAssessment != nil,
              (try? WatcherCompletionPolicy.validateReceipt(
                  receipt,
                  pipeline: pipeline,
                  runtime: runtime,
                  assessment: assessment
              )) != nil else { return false }
        return true
    }

    /// User attention is an overlay on operational state, not a scheduler
    /// state. A Watcher can require a decision while its deterministic,
    /// bounded passes continue to run and survive app relaunches.
    var requiresUserAttention: Bool {
        if status == .completed && !isDeterministicallyCompleted { return true }
        if status == .needsAttention { return true }
        let assessment = independentlyApprovedAssessment
        if assessment != nil,
           lastAgentMessage.contains("LOOPFORGE_WATCHER_STATUS: NEEDS_USER") {
            return true
        }
        if assessment?.issues.contains(where: {
            $0.disposition == .confirmed && $0.userActionRequired
        }) == true {
            return true
        }
        return assessment?.importantInformation.contains(where: {
            $0.userActionRequired
        }) == true
    }

    var operationalStatusTitle: String {
        if status == .completed && !isDeterministicallyCompleted {
            return "Completion evidence invalid"
        }
        return requiresUserAttention && status.shouldSchedule
            ? "Watching · Needs attention"
            : status.title
    }
}

struct WatcherEvaluation: Equatable {
    var events: [WatcherEvent]
    var shouldWakeAgent: Bool
    var highestSeverity: WatcherSeverity
    var activeIssues: [WatcherDetectedIssue]
}
