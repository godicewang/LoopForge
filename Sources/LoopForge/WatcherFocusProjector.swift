import Foundation

struct WatcherFocusSnapshot: Equatable {
    var headline: String
    var summary: String
    var pipelineIssues: [WatcherDetectedIssue]
    var pendingIssues: [WatcherDetectedIssue]
    var confirmedIssues: [WatcherAgentIssueAssessment]
    var dismissedIssues: [WatcherAgentIssueAssessment]
    var resolvedIssues: [WatcherAgentIssueAssessment]
    var importantInformation: [WatcherImportantInformation]
    var primarySignals: [WatcherSignalSpec]
    var progressSignal: WatcherSignalSpec?
    var reviewedAt: Date?

    var needsUserActionCount: Int {
        pipelineIssues.filter(\.userActionRequired).count
            + confirmedIssues.filter(\.userActionRequired).count
            + importantInformation.filter(\.userActionRequired).count
    }
}

enum WatcherFocusProjector {
    static func snapshot(for watcher: ContinuumWatcher) -> WatcherFocusSnapshot {
        let active = watcher.runtime.activeIssues ?? inferredIssues(for: watcher)
        // Persisted Agent prose is advisory. The task-focused overview only
        // exposes it after a distinct read-only lineage approves the exact
        // pipeline and assessment digests retained on the Watcher.
        let assessment = watcher.independentlyApprovedAssessment
        let confirmed = assessment?.issues.filter {
            $0.disposition == .confirmed
        } ?? []
        let dismissed = assessment?.issues.filter {
            $0.disposition == .dismissed
        } ?? []
        let resolved = assessment?.issues.filter {
            $0.disposition == .resolved
        } ?? []
        let decidedIDs = Set((confirmed + dismissed + resolved).map(\.id))
        let pending = active.filter { !decidedIDs.contains($0.id) }
        let primary = selectedSignals(
            watcher.pipeline?.dashboard?.primarySignalKeys ?? [],
            watcher: watcher,
            limit: 6
        )
        let progress = progressSignal(for: watcher, primary: primary)
        let information = importantInformation(
            watcher: watcher,
            explicit: assessment?.importantInformation ?? []
        )

        return WatcherFocusSnapshot(
            headline: nonEmpty(watcher.pipeline?.dashboard?.headline)
                ?? nonEmpty(assessment?.headline)
                ?? watcher.displayTitle,
            summary: nonEmpty(assessment?.summary)
                ?? watcher.runtime.lastSummary,
            pipelineIssues: active,
            pendingIssues: pending,
            confirmedIssues: confirmed,
            dismissedIssues: dismissed,
            resolvedIssues: resolved,
            importantInformation: information,
            primarySignals: primary,
            progressSignal: progress,
            reviewedAt: assessment?.reviewedAt
        )
    }

    private static func inferredIssues(
        for watcher: ContinuumWatcher
    ) -> [WatcherDetectedIssue] {
        guard let pipeline = watcher.pipeline else {
            guard watcher.requiresUserAttention else { return [] }
            return [WatcherDetectedIssue(
                id: "system.pipeline-unavailable",
                title: "Pipeline needs attention",
                detail: watcher.events.last?.message
                    ?? "The pipeline has not been built successfully.",
                severity: .critical,
                signalKey: nil,
                value: nil,
                detectedAt: watcher.updatedAt,
                lastSeenAt: watcher.updatedAt,
                userActionRequired: true
            )]
        }
        let now = Date()
        return pipeline.signals.compactMap { signal in
            guard let value = watcher.runtime.latestSignals[signal.key] else {
                return nil
            }
            let outside = signal.expectedMinimum.map { value < $0 } == true
                || signal.expectedMaximum.map { value > $0 } == true
                || (
                    signal.staleAfterSeconds.flatMap { stale in
                        watcher.runtime.latestSignalAt[signal.key].map {
                            now.timeIntervalSince($0) > stale
                        }
                    } == true
                )
            guard outside else { return nil }
            return WatcherDetectedIssue(
                id: "signal.\(signal.key)",
                title: "\(signal.title) needs review",
                detail: "\(signal.description) Current value: \(format(value, signal: signal)).",
                severity: .warning,
                signalKey: signal.key,
                value: value,
                detectedAt: watcher.runtime.latestSignalAt[signal.key] ?? watcher.updatedAt,
                lastSeenAt: watcher.runtime.latestSignalAt[signal.key] ?? watcher.updatedAt,
                userActionRequired: false
            )
        }
    }

    private static func progressSignal(
        for watcher: ContinuumWatcher,
        primary: [WatcherSignalSpec]
    ) -> WatcherSignalSpec? {
        if let key = watcher.pipeline?.dashboard?.progressSignalKey,
           let signal = watcher.pipeline?.signals.first(where: { $0.key == key }) {
            return signal
        }
        return (primary + (watcher.pipeline?.signals ?? [])).first {
            $0.kind == .progress
                || $0.key.localizedCaseInsensitiveContains("progress")
                || $0.key.localizedCaseInsensitiveContains("completion")
        }
    }

    private static func importantInformation(
        watcher: ContinuumWatcher,
        explicit: [WatcherImportantInformation]
    ) -> [WatcherImportantInformation] {
        var result = explicit.map { information in
            var live = information
            if let key = information.signalKey,
               let signal = watcher.pipeline?.signals.first(where: { $0.key == key }),
               let value = watcher.runtime.latestSignals[key] {
                live.value = value
                live.unit = signal.unit
            }
            return live
        }
        let explicitKeys = Set(result.compactMap(\.signalKey))
        let configuredKeys = watcher.pipeline?.dashboard?.importantSignalKeys ?? []
        var signals = selectedSignals(configuredKeys, watcher: watcher, limit: 8)
        if signals.isEmpty {
            signals = fallbackImportantSignals(for: watcher)
        }
        for signal in signals where !explicitKeys.contains(signal.key) {
            result.append(WatcherImportantInformation(
                id: "signal.\(signal.key)",
                title: signal.title,
                detail: signal.description,
                severity: .info,
                signalKey: signal.key,
                value: watcher.runtime.latestSignals[signal.key],
                unit: signal.unit,
                goalAnchorID: watcher.pipeline?.dashboard?.goalAnchors.first?.id,
                userActionRequired: false
            ))
        }
        if result.isEmpty,
           !watcher.runtime.lastSummary.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty {
            result.append(WatcherImportantInformation(
                id: "pipeline.latest-result",
                title: "Latest result",
                detail: watcher.runtime.lastSummary,
                severity: .info,
                signalKey: nil,
                value: nil,
                unit: nil,
                goalAnchorID: nil,
                userActionRequired: false
            ))
        }
        return Array(result.prefix(12))
    }

    private static func selectedSignals(
        _ keys: [String],
        watcher: ContinuumWatcher,
        limit: Int
    ) -> [WatcherSignalSpec] {
        let byKey = Dictionary(
            uniqueKeysWithValues: (watcher.pipeline?.signals ?? []).map {
                ($0.key, $0)
            }
        )
        return Array(keys.compactMap { byKey[$0] }.prefix(limit))
    }

    private static func fallbackImportantSignals(
        for watcher: ContinuumWatcher
    ) -> [WatcherSignalSpec] {
        let preferredTerms = [
            "progress", "result", "candidate", "completed", "processed",
            "remaining", "best", "score", "quality", "backlog", "recovery",
            "excess", "return"
        ]
        let technicalPrefixes = ["pipeline.", "input.", "model.", "runtime."]
        return Array((watcher.pipeline?.signals ?? []).filter { signal in
            !technicalPrefixes.contains { signal.key.hasPrefix($0) }
                && preferredTerms.contains {
                    signal.key.localizedCaseInsensitiveContains($0)
                        || signal.title.localizedCaseInsensitiveContains($0)
                }
        }.prefix(6))
    }

    static func format(_ value: Double, signal: WatcherSignalSpec) -> String {
        if (signal.kind == .ratio || signal.kind == .progress),
           signal.expectedMaximum == 1 || signal.unit == "ratio" {
            return value.formatted(.percent.precision(.fractionLength(0...1)))
        }
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return signal.unit.isEmpty ? number : "\(number) \(signal.unit)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clean.isEmpty else { return nil }
        return clean
    }
}
