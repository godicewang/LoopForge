import Foundation

enum WatcherPromptCompiler {
    static func bootstrapPrompt(
        watcher: ContinuumWatcher,
        requestedPollSeconds: TimeInterval,
        requestedReviewSeconds: TimeInterval
    ) -> String {
        """
        You are the pipeline builder for LoopForge Continuum Watcher.

        USER OUTCOME
        \(watcher.request)

        WORKSPACE
        \(watcher.workspacePath)

        Build and verify a production-minded, deterministic local pipeline that can replace an
        always-running AI agent for the routine portion of this request. You have full workspace
        access. Inspect the existing project before editing. The pipeline may be a script,
        scheduler-friendly program, monitor, batch processor, or another appropriate local form.

        NON-NEGOTIABLE OPERATING CONTRACT
        - The entry point performs ONE bounded, idempotent pass and exits. LoopForge owns cadence.
        - Persist a durable checkpoint so retries and app restarts never duplicate destructive work.
        - Use atomic writes and explicit timeouts. Never use an unbounded busy loop.
        - Never store secrets, raw API keys, credentials, private content, or full user identifiers
          in telemetry. Bound label cardinality; aggregate IDs, paths, and URLs.
        - Instrument health, input freshness, output/progress, error rate, duration, and task-specific
          signals. Establish realistic expected ranges from evidence or an explicit conservative baseline.
        - Avoid alert storms: require sustained evidence where appropriate and set a cooldown.
        - A periodic Agent review must be at least 2 hours apart. Choose a useful cadence, neither
          needlessly short nor too slow for the requested outcome.
        - Add tests or a safe dry-run fixture and execute all verification commands. LoopForge will
          independently rerun each verification command as a direct argument array, never through a shell.
        - Document installation prerequisites and any operation that still requires user approval.
        - Keep the manifest below 512 KiB, telemetry below 1 MiB, checkpoint below 8 MiB, and use at
          most 100 bounded signal keys, 100 rules, 100 generated paths, and 12 verification commands.

        USER CADENCE PREFERENCE
        Routine pass: about \(requestedPollSeconds.compactDuration)
        Agent review: about \(max(WatcherPolicy.minimumReviewInterval, requestedReviewSeconds).compactDuration)

        REQUIRED MACHINE-READABLE FILES
        Write `.loopforge/watcher/manifest.json` using exactly this schema:
        {
          "schemaVersion": 1,
          "revision": 1,
          "command": ["executable-or-tool", "argument", "..."],
          "workingDirectory": ".",
          "telemetryPath": ".loopforge/watcher/telemetry.json",
          "checkpointPath": ".loopforge/watcher/checkpoint.json",
          "generatedPaths": ["relative/path"],
          "verificationCommands": [["tool", "arg"]],
          "pollIntervalSeconds": 900,
          "reviewIntervalSeconds": 14400,
          "timeoutSeconds": 300,
          "signals": [{
            "key": "pipeline.duration_seconds",
            "title": "Pipeline duration",
            "kind": "duration",
            "unit": "s",
            "description": "Bounded runtime for one pass",
            "expectedMinimum": 0,
            "expectedMaximum": 300,
            "staleAfterSeconds": 3600
          }],
          "rules": [{
            "id": "pipeline-slow",
            "title": "Pipeline duration is repeatedly high",
            "signalKey": "pipeline.duration_seconds",
            "comparator": "above",
            "threshold": 300,
            "upperThreshold": null,
            "requiredConsecutiveMatches": 2,
            "cooldownSeconds": 7200,
            "severity": "warning",
            "wakesAgent": true
          }]
        }

        Every successful pass must atomically replace the telemetry JSON:
        {
          "schemaVersion": 1,
          "capturedAt": "ISO-8601 timestamp",
          "status": "ok|degraded|failed",
          "summary": "short user-safe summary",
          "signals": {"bounded.signal.name": 1.0},
          "events": [],
          "completed": false,
          "checkpoint": "short non-sensitive checkpoint label"
        }

        Shell metacharacters and compound shell commands are forbidden in all command arrays. Emit only
        signal keys declared in the manifest. Replace telemetry during every pass and set `capturedAt`
        to the current pass time; never reuse a prior pass as success. Finish only after the entry point,
        telemetry contract, checkpoint/recovery path, and verification commands work. In your final
        response, briefly name the files created and evidence verified.
        """
    }

    static func reviewPrompt(
        watcher: ContinuumWatcher,
        reason: String,
        telemetry: WatcherTelemetryEnvelope?,
        recentEvents: [WatcherEvent]
    ) -> String {
        let telemetryText = telemetry.flatMap { try? JSONEncoder.loopForge.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "No valid telemetry document was available."
        let eventText = recentEvents.suffix(20).map {
            "[\($0.timestamp.ISO8601Format())] \($0.severity.rawValue) · \($0.message)"
        }.joined(separator: "\n")

        return """
        You are the adaptive reviewer for an existing LoopForge Continuum Watcher.

        ORIGINAL OUTCOME
        \(watcher.request)

        WAKE REASON
        \(reason)

        CURRENT MANIFEST
        \(watcher.pipeline.flatMap { try? JSONEncoder.loopForge.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "Manifest missing")

        LATEST TELEMETRY
        \(telemetryText)

        RECENT EVENTS
        \(eventText.isEmpty ? "No retained events." : eventText)

        Inspect the live workspace, code, checkpoint, bounded logs, and source conditions. On EVERY
        wake, determine both (1) what the current data/system state means and (2) whether the solidified
        pipeline itself is healthy, stale, biased, incomplete, or generating false positives.

        If evidence warrants it, repair the implementation and adapt instrumentation, baselines,
        thresholds, sustained-match counts, cooldowns, or cadence. Do not loosen thresholds merely to
        hide a real anomaly, do not invent facts, do not log secrets/high-cardinality identifiers, and
        do not replace a deterministic step with a permanent AI loop. Preserve idempotency and checkpoint
        compatibility or migrate it explicitly. Keep periodic reviews at least 2 hours apart.

        Run every relevant verification. LoopForge will independently rerun manifest verification commands
        before accepting your result. Increment `revision` only when the manifest or pipeline changes, and
        never decrease it. Atomically update `.loopforge/watcher/manifest.json`; leave it valid under schema
        version 1. Conclude with a concise assessment. The final line must be exactly one status marker from
        the allowed contract below. Do not quote, list, or mention any of the other markers in your response:
        LOOPFORGE_WATCHER_STATUS: HEALTHY
        Or use the corresponding single final marker for REPAIRED, NEEDS_USER, or COMPLETE.
        """
    }
}
