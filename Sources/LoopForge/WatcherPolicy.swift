import Foundation

enum WatcherPolicyError: LocalizedError, Equatable {
    case emptyCommand
    case unsafeCommand(String)
    case pathEscapesWorkspace(String)
    case unsupportedSchema(Int)
    case invalidManifest(String)
    case invalidTelemetry(String)
    case oversizedFile(String)

    var errorDescription: String? {
        switch self {
        case .emptyCommand: return "The watcher manifest has no executable command."
        case .unsafeCommand(let command):
            return "The watcher command uses an unsafe shell form: \(command)"
        case .pathEscapesWorkspace(let path):
            return "The watcher path escapes the selected project: \(path)"
        case .unsupportedSchema(let version):
            return "Watcher manifest schema \(version) is not supported."
        case .invalidManifest(let reason):
            return "The watcher manifest is invalid: \(reason)"
        case .invalidTelemetry(let reason):
            return "The watcher telemetry is invalid: \(reason)"
        case .oversizedFile(let path):
            return "The watcher file exceeds its safe size limit: \(path)"
        }
    }
}

enum WatcherPolicy {
    static let manifestRelativePath = ".loopforge/watcher/manifest.json"
    static let defaultTelemetryRelativePath = ".loopforge/watcher/telemetry.json"
    static let defaultCheckpointRelativePath = ".loopforge/watcher/checkpoint.json"
    static let minimumPollInterval: TimeInterval = 60
    static let minimumReviewInterval: TimeInterval = 2 * 60 * 60
    static let maximumReviewInterval: TimeInterval = 7 * 24 * 60 * 60
    static let maximumSignalCount = 100
    static let maximumRuleCount = 100
    static let maximumGeneratedPathCount = 100
    static let maximumVerificationCommandCount = 12
    static let maximumTelemetryEventCount = 100
    static let maximumManifestBytes = 512 * 1_024
    static let maximumTelemetryBytes = 1_024 * 1_024
    static let maximumCheckpointBytes = 8 * 1_024 * 1_024
    private static let prohibitedShellTokens = ["|", "&&", "||", ";", ">", "<", "`", "$("]

    static func normalized(
        _ pipeline: WatcherPipeline,
        workspacePath: String
    ) throws -> WatcherPipeline {
        guard pipeline.schemaVersion == 1 else {
            throw WatcherPolicyError.unsupportedSchema(pipeline.schemaVersion)
        }
        guard let executable = pipeline.command.first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !executable.isEmpty else {
            throw WatcherPolicyError.emptyCommand
        }
        try validateCommand(pipeline.command)
        guard pipeline.revision >= 1 else {
            throw WatcherPolicyError.invalidManifest("revision must be at least 1")
        }
        guard pipeline.pollIntervalSeconds.isFinite,
              pipeline.reviewIntervalSeconds.isFinite,
              pipeline.timeoutSeconds.isFinite else {
            throw WatcherPolicyError.invalidManifest("cadence and timeout values must be finite")
        }
        guard !pipeline.verificationCommands.isEmpty else {
            throw WatcherPolicyError.invalidManifest(
                "at least one independently runnable verification command is required"
            )
        }

        var result = pipeline
        result.command[0] = executable
        result.pollIntervalSeconds = min(
            24 * 60 * 60,
            max(minimumPollInterval, pipeline.pollIntervalSeconds)
        )
        result.reviewIntervalSeconds = min(
            maximumReviewInterval,
            max(minimumReviewInterval, pipeline.reviewIntervalSeconds)
        )
        result.timeoutSeconds = min(
            60 * 60,
            max(10, min(pipeline.timeoutSeconds, result.pollIntervalSeconds))
        )
        result.generatedPaths = Array(
            pipeline.generatedPaths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqued()
                .prefix(maximumGeneratedPathCount)
        )
        result.verificationCommands = Array(
            pipeline.verificationCommands.prefix(maximumVerificationCommandCount)
        )
        for command in result.verificationCommands {
            try validateCommand(command)
            guard command.count <= 64 else {
                throw WatcherPolicyError.invalidManifest(
                    "a verification command has more than 64 arguments"
                )
            }
        }

        let signals = Array(pipeline.signals.prefix(maximumSignalCount))
        let signalKeys = signals.map(\.key)
        guard Set(signalKeys).count == signalKeys.count else {
            throw WatcherPolicyError.invalidManifest("signal keys must be unique")
        }
        for signal in signals {
            guard isSafeIdentifier(signal.key) else {
                throw WatcherPolicyError.invalidManifest(
                    "signal key '\(signal.key)' is not a bounded identifier"
                )
            }
            guard signal.expectedMinimum?.isFinite != false,
                  signal.expectedMaximum?.isFinite != false,
                  signal.staleAfterSeconds?.isFinite != false else {
                throw WatcherPolicyError.invalidManifest(
                    "signal '\(signal.key)' contains a non-finite range"
                )
            }
            if let lower = signal.expectedMinimum,
               let upper = signal.expectedMaximum,
               lower > upper {
                throw WatcherPolicyError.invalidManifest(
                    "signal '\(signal.key)' has an inverted expected range"
                )
            }
        }
        result.signals = signals

        let declaredSignals = Set(signalKeys)
        let rules = Array(pipeline.rules.prefix(maximumRuleCount))
        let ruleIDs = rules.map(\.id)
        guard Set(ruleIDs).count == ruleIDs.count else {
            throw WatcherPolicyError.invalidManifest("rule IDs must be unique")
        }
        result.rules = try rules.map { rule in
            guard isSafeIdentifier(rule.id) else {
                throw WatcherPolicyError.invalidManifest(
                    "rule ID '\(rule.id)' is not a bounded identifier"
                )
            }
            guard declaredSignals.contains(rule.signalKey) else {
                throw WatcherPolicyError.invalidManifest(
                    "rule '\(rule.id)' references undeclared signal '\(rule.signalKey)'"
                )
            }
            try validateThresholds(rule)
            var normalized = rule
            normalized.requiredConsecutiveMatches = min(
                20,
                max(1, rule.requiredConsecutiveMatches)
            )
            normalized.cooldownSeconds = min(
                7 * 24 * 60 * 60,
                max(result.pollIntervalSeconds, rule.cooldownSeconds)
            )
            return normalized
        }

        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .standardizedFileURL
        for candidate in [
            result.workingDirectory,
            result.telemetryPath,
            result.checkpointPath
        ] + result.generatedPaths {
            _ = try resolvedPath(candidate, workspace: workspace)
        }
        return result
    }

    static func resolvedPath(_ path: String, workspace: URL) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WatcherPolicyError.invalidManifest("a required workspace path is empty")
        }
        let rootURL = workspace.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = URL(
            fileURLWithPath: trimmed,
            relativeTo: workspace
        ).standardizedFileURL
        let resolvedCandidate = resolvedThroughExistingAncestor(candidate)
        let root = rootURL.path
        guard resolvedCandidate.path == root
                || resolvedCandidate.path.hasPrefix(root + "/") else {
            throw WatcherPolicyError.pathEscapesWorkspace(path)
        }
        return candidate
    }

    static func executableAndArguments(
        pipeline: WatcherPipeline,
        workspacePath: String
    ) throws -> (URL, [String], URL) {
        let normalized = try normalized(pipeline, workspacePath: workspacePath)
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .standardizedFileURL
        let workingDirectory = try resolvedPath(normalized.workingDirectory, workspace: workspace)
        let first = normalized.command[0]
        if first.hasPrefix("/") {
            return (URL(fileURLWithPath: first), Array(normalized.command.dropFirst()), workingDirectory)
        }
        // `/usr/bin/env` resolves tools using the controlled PATH without ever
        // passing the command through a shell or evaluating metacharacters.
        return (
            URL(fileURLWithPath: "/usr/bin/env"),
            normalized.command,
            workingDirectory
        )
    }

    static func verificationExecutions(
        pipeline: WatcherPipeline,
        workspacePath: String
    ) throws -> [(URL, [String], URL)] {
        let normalized = try normalized(pipeline, workspacePath: workspacePath)
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
            .standardizedFileURL
        let workingDirectory = try resolvedPath(
            normalized.workingDirectory,
            workspace: workspace
        )
        return try normalized.verificationCommands.map { command in
            try validateCommand(command)
            if command[0].hasPrefix("/") {
                return (
                    URL(fileURLWithPath: command[0]),
                    Array(command.dropFirst()),
                    workingDirectory
                )
            }
            return (
                URL(fileURLWithPath: "/usr/bin/env"),
                command,
                workingDirectory
            )
        }
    }

    static func loadPipeline(workspacePath: String) throws -> WatcherPipeline {
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let url = try resolvedPath(manifestRelativePath, workspace: workspace)
        let data = try boundedData(at: url, maximumBytes: maximumManifestBytes)
        let decoded = try JSONDecoder.loopForge.decode(WatcherPipeline.self, from: data)
        return try normalized(decoded, workspacePath: workspacePath)
    }

    static func loadTelemetry(
        pipeline: WatcherPipeline,
        workspacePath: String,
        notOlderThan: Date? = nil,
        now: Date = Date()
    ) throws -> WatcherTelemetryEnvelope {
        let normalizedPipeline = try normalized(
            pipeline,
            workspacePath: workspacePath
        )
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let url = try resolvedPath(normalizedPipeline.telemetryPath, workspace: workspace)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let notOlderThan,
           let modified = attributes[.modificationDate] as? Date,
           modified < notOlderThan.addingTimeInterval(-2) {
            throw WatcherPolicyError.invalidTelemetry(
                "the pipeline did not replace telemetry during this run"
            )
        }
        let data = try boundedData(at: url, maximumBytes: maximumTelemetryBytes)
        let decoded = try JSONDecoder.loopForge.decode(
            WatcherTelemetryEnvelope.self,
            from: data
        )
        return try normalizedTelemetry(
            decoded,
            pipeline: normalizedPipeline,
            notOlderThan: notOlderThan,
            now: now
        )
    }

    static func validateCheckpoint(
        pipeline: WatcherPipeline,
        workspacePath: String
    ) throws {
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let url = try resolvedPath(pipeline.checkpointPath, workspace: workspace)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WatcherPolicyError.invalidTelemetry(
                "the durable checkpoint was not created"
            )
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumCheckpointBytes else {
            throw WatcherPolicyError.oversizedFile(url.lastPathComponent)
        }
    }

    static func normalizedTelemetry(
        _ telemetry: WatcherTelemetryEnvelope,
        pipeline: WatcherPipeline,
        notOlderThan: Date? = nil,
        now: Date = Date()
    ) throws -> WatcherTelemetryEnvelope {
        guard telemetry.schemaVersion == 1 else {
            throw WatcherPolicyError.invalidTelemetry("schemaVersion must be 1")
        }
        guard let capturedAt = telemetry.capturedAt else {
            throw WatcherPolicyError.invalidTelemetry("capturedAt is required")
        }
        if let notOlderThan,
           capturedAt < notOlderThan.addingTimeInterval(-2) {
            throw WatcherPolicyError.invalidTelemetry(
                "capturedAt predates the current pipeline run"
            )
        }
        guard capturedAt <= now.addingTimeInterval(5 * 60) else {
            throw WatcherPolicyError.invalidTelemetry(
                "capturedAt is implausibly far in the future"
            )
        }
        let allowedStatuses = Set(["ok", "degraded", "failed"])
        let status = telemetry.status?.lowercased() ?? ""
        guard allowedStatuses.contains(status) else {
            throw WatcherPolicyError.invalidTelemetry(
                "status must be ok, degraded, or failed"
            )
        }
        let declared = Set(pipeline.signals.map(\.key))
        let unknownSignals = Set(telemetry.signals.keys).subtracting(declared)
        guard unknownSignals.isEmpty else {
            throw WatcherPolicyError.invalidTelemetry(
                "undeclared or high-cardinality signals were emitted: "
                    + unknownSignals.sorted().prefix(5).joined(separator: ", ")
            )
        }
        var result = telemetry
        result.status = status
        result.summary = (telemetry.summary ?? "Pipeline pass completed")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefixText(400)
        result.checkpoint = telemetry.checkpoint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefixText(160)
        result.events = Array(
            (telemetry.events ?? [])
                .prefix(maximumTelemetryEventCount)
                .map {
                    WatcherTelemetryEvent(
                        name: $0.name.prefixText(120),
                        severity: $0.severity,
                        message: $0.message?.prefixText(500)
                    )
                }
        )
        return result
    }

    static func evaluate(
        pipeline: WatcherPipeline,
        telemetry: WatcherTelemetryEnvelope,
        state: inout WatcherRuntimeState,
        now: Date = Date()
    ) -> WatcherEvaluation {
        var events: [WatcherEvent] = []
        var shouldWake = false
        var highest: WatcherSeverity = .info
        let declaredSignals = Set(pipeline.signals.map(\.key))
        let declaredRules = Set(pipeline.rules.map(\.id))
        state.latestSignals = state.latestSignals.filter {
            declaredSignals.contains($0.key)
        }
        state.latestSignalAt = state.latestSignalAt.filter {
            declaredSignals.contains($0.key)
        }
        state.ruleMatchCounts = state.ruleMatchCounts.filter {
            declaredRules.contains($0.key)
        }
        state.ruleLastTriggeredAt = state.ruleLastTriggeredAt.filter {
            declaredRules.contains($0.key)
        }

        for (key, value) in telemetry.signals where declaredSignals.contains(key) {
            state.latestSignals[key] = value
            state.latestSignalAt[key] = telemetry.capturedAt ?? now
        }

        for event in telemetry.events ?? [] {
            let severity = event.severity ?? .warning
            highest = max(highest, severity)
            events.append(WatcherEvent(
                timestamp: telemetry.capturedAt ?? now,
                kind: .anomaly,
                severity: severity,
                message: event.message ?? event.name
            ))
            shouldWake = shouldWake || severity >= .warning
        }

        for rule in pipeline.rules {
            let value = rule.comparator == .missing
                ? telemetry.signals[rule.signalKey]
                : (telemetry.signals[rule.signalKey] ?? state.latestSignals[rule.signalKey])
            let matched = matches(
                rule: rule,
                value: value,
                lastCapturedAt: state.latestSignalAt[rule.signalKey],
                now: now
            )
            state.ruleMatchCounts[rule.id] = matched
                ? (state.ruleMatchCounts[rule.id] ?? 0) + 1
                : 0
            guard matched,
                  (state.ruleMatchCounts[rule.id] ?? 0) >= rule.requiredConsecutiveMatches else {
                continue
            }
            let lastTriggered = state.ruleLastTriggeredAt[rule.id] ?? .distantPast
            guard now.timeIntervalSince(lastTriggered) >= rule.cooldownSeconds else { continue }

            state.ruleLastTriggeredAt[rule.id] = now
            state.ruleMatchCounts[rule.id] = 0
            highest = max(highest, rule.severity)
            shouldWake = shouldWake || rule.wakesAgent
            events.append(WatcherEvent(
                timestamp: now,
                kind: rule.comparator == .stale ? .staleSignal : .threshold,
                severity: rule.severity,
                message: rule.title,
                signalKey: rule.signalKey,
                value: value
            ))
        }

        return WatcherEvaluation(
            events: events,
            shouldWakeAgent: shouldWake,
            highestSeverity: highest
        )
    }

    private static func matches(
        rule: WatcherRule,
        value: Double?,
        lastCapturedAt: Date?,
        now: Date
    ) -> Bool {
        switch rule.comparator {
        case .missing:
            return value == nil
        case .stale:
            guard let lastCapturedAt else { return true }
            return now.timeIntervalSince(lastCapturedAt) >= (rule.threshold ?? 0)
        case .changed:
            // Explicit change detection should be emitted by the deterministic
            // pipeline as a 0/1 signal, keeping state semantics out of the UI.
            return value.map { $0 != 0 } ?? false
        case .above:
            guard let value, let threshold = rule.threshold else { return false }
            return value > threshold
        case .below:
            guard let value, let threshold = rule.threshold else { return false }
            return value < threshold
        case .outside:
            guard let value, let lower = rule.threshold, let upper = rule.upperThreshold else {
                return false
            }
            return value < lower || value > upper
        case .equals:
            guard let value, let threshold = rule.threshold else { return false }
            return abs(value - threshold) < 0.000_001
        }
    }

    private static func validateCommand(_ command: [String]) throws {
        guard let executable = command.first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !executable.isEmpty else {
            throw WatcherPolicyError.emptyCommand
        }
        if command.contains(where: { argument in
            prohibitedShellTokens.contains(where: argument.contains)
        }) {
            throw WatcherPolicyError.unsafeCommand(command.joined(separator: " "))
        }
        guard command.allSatisfy({ $0.count <= 4_096 }) else {
            throw WatcherPolicyError.invalidManifest(
                "command arguments must be at most 4096 characters"
            )
        }
    }

    private static func validateThresholds(_ rule: WatcherRule) throws {
        let finiteThreshold = rule.threshold?.isFinite != false
        let finiteUpper = rule.upperThreshold?.isFinite != false
        guard finiteThreshold, finiteUpper else {
            throw WatcherPolicyError.invalidManifest(
                "rule '\(rule.id)' contains a non-finite threshold"
            )
        }
        switch rule.comparator {
        case .above, .below, .equals:
            guard rule.threshold != nil else {
                throw WatcherPolicyError.invalidManifest(
                    "rule '\(rule.id)' requires a threshold"
                )
            }
        case .outside:
            guard let lower = rule.threshold,
                  let upper = rule.upperThreshold,
                  lower <= upper else {
                throw WatcherPolicyError.invalidManifest(
                    "outside rule '\(rule.id)' requires ordered lower and upper thresholds"
                )
            }
        case .stale:
            guard let threshold = rule.threshold, threshold > 0 else {
                throw WatcherPolicyError.invalidManifest(
                    "stale rule '\(rule.id)' requires a positive age threshold"
                )
            }
        case .missing, .changed:
            break
        }
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 96 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || $0 == "." || $0 == "_" || $0 == "-" || $0 == ":"
        }
    }

    private static func resolvedThroughExistingAncestor(_ url: URL) -> URL {
        var ancestor = url
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path),
              ancestor.path != "/" {
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        var result = ancestor.resolvingSymlinksInPath()
        for component in suffix { result.appendPathComponent(component) }
        return result.standardizedFileURL
    }

    private static func boundedData(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumBytes else {
            throw WatcherPolicyError.oversizedFile(url.lastPathComponent)
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

enum WatcherReviewDecision: String, Equatable {
    case healthy
    case repaired
    case needsUser
    case complete

    static func parse(_ response: String) throws -> WatcherReviewDecision {
        let markers: [(String, WatcherReviewDecision)] = [
            ("LOOPFORGE_WATCHER_STATUS: HEALTHY", .healthy),
            ("LOOPFORGE_WATCHER_STATUS: REPAIRED", .repaired),
            ("LOOPFORGE_WATCHER_STATUS: NEEDS_USER", .needsUser),
            ("LOOPFORGE_WATCHER_STATUS: COMPLETE", .complete)
        ]
        let upper = response.uppercased()
        let matches = markers.filter { upper.contains($0.0) }
        guard matches.count == 1, let decision = matches.first?.1 else {
            throw WatcherPolicyError.invalidTelemetry(
                "Agent review must end with exactly one watcher status marker"
            )
        }
        return decision
    }
}

enum WatcherRuntimeEnvironment {
    /// Deterministic pipelines receive only ordinary process context plus
    /// explicitly watcher-scoped values. Unrelated API keys and CI credentials
    /// from the parent process are never leaked into generated scripts.
    static func sanitized(
        _ source: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let allowed = Set([
            "HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
            "TZ", "SHELL", "USER", "LOGNAME", "SSH_AUTH_SOCK"
        ])
        var result = source.filter {
            allowed.contains($0.key) || $0.key.hasPrefix("LOOPFORGE_WATCHER_")
        }
        let usefulPaths = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        result["PATH"] = (usefulPaths + [result["PATH"] ?? ""])
            .joined(separator: ":")
        result["NO_COLOR"] = "1"
        return result
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "…"
    }
}
