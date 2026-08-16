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

        SELECTED WORKSPACE BOUNDARY
        Treat the exact directory above as the project root even if it is nested inside another Git
        repository. Do not read, search, or modify its parent or sibling directories. In particular,
        do not inspect LoopForge's own source code or tests to rediscover this contract: the complete
        manifest, telemetry, safety, and verification contract is provided below.

        Build and verify a production-minded, deterministic local pipeline that can replace an
        always-running AI agent for the routine portion of this request. You have full workspace
        access. Inspect the existing project before editing. The pipeline may be a script,
        scheduler-friendly program, monitor, batch processor, or another appropriate local form.

        NON-NEGOTIABLE OPERATING CONTRACT
        - Work as the single selected Agent. Do not call collaboration, spawn_agent, send_message,
          followup_task, or any equivalent delegation/fan-out mechanism. Do not create hidden
          subordinate Agents. LoopForge owns all Agent scheduling and user-visible concurrency.
        - The entry point performs ONE bounded, idempotent pass and exits. LoopForge owns cadence.
        - Persist a durable checkpoint so retries and app restarts never duplicate destructive work.
        - Use atomic writes and explicit timeouts. Never use an unbounded busy loop.
        - Never store secrets, raw API keys, credentials, private content, or full user identifiers
          in telemetry. Bound label cardinality; aggregate IDs, paths, and URLs.
        - Instrument health, input freshness, output/progress, error rate, duration, and task-specific
          signals. Establish realistic expected ranges from evidence or an explicit conservative baseline.
        - Build a bounded task-specific Overview from the original outcome. Extract a small set of explicit
          goal anchors, then bind only goal-relevant signals to the dashboard. The native app owns layout
          and rendering: never generate HTML, SwiftUI, JavaScript, remote embeds, or executable UI code.
        - Avoid alert storms: require sustained evidence where appropriate and set a cooldown.
        - Do not wake the Agent for a condition the deterministic pipeline already resolved
          successfully (for example, a parameter adjustment it applied and checkpointed). Such a
          condition may remain an informational rule with `wakesAgent: false`. Every rule with
          `wakesAgent: true` must use `warning` or `critical` severity and represent unresolved,
          sustained evidence that benefits from adaptive Agent intervention.
        - A periodic Agent review must be at least 2 hours apart. Choose a useful cadence, neither
          needlessly short nor too slow for the requested outcome.
        - Add tests or a safe dry-run fixture and execute all verification commands. LoopForge will
          independently rerun each verification command as a direct argument array, never through a shell.
        - Document installation prerequisites and any operation that still requires user approval.
        - Keep the manifest below 512 KiB, telemetry below 1 MiB, checkpoint below 8 MiB, and use at
          most 100 bounded signal keys, 100 rules, 100 generated paths, and 12 verification commands.
        - Keep discovery proportional. For a minimal workspace, use at most three bounded discovery
          tool calls before creating the first runnable pipeline files. Implement early, then use
          verification evidence to refine the design. Do not spend the turn auditing LoopForge itself.

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
          }],
          "dashboard": {
            "headline": "Short task-specific status headline",
            "preset": "general|operations|batch|experiment|condition|research|dataQuality",
            "goalAnchors": [{
              "id": "stable-bounded-id",
              "title": "A concrete concern explicitly present in the user outcome"
            }],
            "progressSignalKey": "declared.signal.key-or-null",
            "primarySignalKeys": ["declared.signal.key"],
            "importantSignalKeys": ["declared.goal.relevant.signal"]
          }
        }

        Rule severity must be exactly `info`, `warning`, or `critical`.
        Dashboard signal keys must all be declared above. Include 1–12 goal anchors grounded directly in
        USER OUTCOME, no generic infrastructure concerns unless the user asked about them. The native
        Overview has a fixed safe component set and dynamically selects progress, status, comparison, and
        metric presentation from this declaration and current telemetry.
        Informational rules never wake the Agent, even if `wakesAgent` is mistakenly true.
        Every successful pass must atomically replace the telemetry JSON:
        {
          "schemaVersion": 1,
          "capturedAt": "ISO-8601 timestamp",
          "status": "ok|degraded|failed",
          "summary": "short user-safe summary",
          "signals": {"bounded.signal.name": 1.0},
          "events": [{"name": "bounded_event_name", "severity": "info|warning|critical", "message": "short user-safe detail"}],
          "completed": false,
          "checkpoint": "short non-sensitive checkpoint label"
        }

        Omit `events` or emit an empty array when there is no event. Informational events do not wake
        the Agent; warning and critical events do. Use the canonical `name` field shown above.
        Treat every source record according to its actual schema and declared role. A record marked
        `surfaceAsSummary: true`, or otherwise identified as task-relevant information, is evidence for
        the user's Overview—not an anomaly candidate—and must never be rejected merely because it lacks
        fields used by another record type. Preserve a bounded monotonic knowledge register in the
        checkpoint: later observations may update a fact, but must not silently erase earlier
        goal-relevant facts needed to explain the outcome. Keep technical decoys, diagnostics, and
        internal counters outside dashboard signal lists and user-safe summaries.
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
        let activeIssues = watcher.runtime.activeIssues.flatMap {
            try? JSONEncoder.loopForge.encode($0)
        }.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let previousAssessment = watcher.latestAssessment.flatMap {
            try? JSONEncoder.loopForge.encode($0)
        }.flatMap { String(data: $0, encoding: .utf8) }
            ?? "No previous Agent assessment was retained."

        return """
        You are the adaptive reviewer for an existing LoopForge Continuum Watcher.

        ORIGINAL OUTCOME
        \(watcher.request)

        SELECTED WORKSPACE BOUNDARY
        \(watcher.workspacePath)
        Treat that exact directory as the project root even if it is nested inside another Git
        repository. Do not read, search, or modify parent or sibling directories, and do not inspect
        LoopForge's own source or tests. This prompt contains the complete review contract.

        WAKE REASON
        \(reason)

        CURRENT MANIFEST
        \(watcher.pipeline.flatMap { try? JSONEncoder.loopForge.encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "Manifest missing")

        LATEST TELEMETRY
        \(telemetryText)

        RECENT EVENTS
        \(eventText.isEmpty ? "No retained events." : eventText)

        CURRENT ACTIVE PIPELINE FINDINGS
        \(activeIssues)

        PREVIOUS AGENT ASSESSMENT
        \(previousAssessment)

        Inspect the live workspace, code, checkpoint, bounded logs, and source conditions. On EVERY
        wake, determine both (1) what the current data/system state means and (2) whether the solidified
        pipeline itself is healthy, stale, biased, incomplete, or generating false positives.

        Work as the single selected Agent. Do not call collaboration, spawn_agent, send_message,
        followup_task, or any equivalent delegation/fan-out mechanism. Do not create hidden
        subordinate Agents. LoopForge owns all Agent scheduling and user-visible concurrency.

        If evidence warrants it, repair the implementation and adapt instrumentation, baselines,
        thresholds, sustained-match counts, cooldowns, or cadence. Do not loosen thresholds merely to
        hide a real anomaly, do not invent facts, do not log secrets/high-cardinality identifiers, and
        do not replace a deterministic step with a permanent AI loop. Preserve idempotency and checkpoint
        compatibility or migrate it explicitly. Keep periodic reviews at least 2 hours apart.

        USER-FACING OVERVIEW CONTRACT
        The Overview must answer only:
        1. Which current findings were detected by the deterministic pipeline?
        2. Which findings did you confirm, dismiss, or resolve, and why?
        3. What new information matters to the ORIGINAL OUTCOME?

        Maintain the manifest's `dashboard` declaration. If it is absent, stale, misleading, or no longer
        fits the task, update it and increment the manifest revision. Use only the supported preset names,
        declared signal keys, and goal anchors grounded directly in ORIGINAL OUTCOME. Do not generate
        executable UI code or arbitrary markup. Current telemetry values will continue updating the native
        Overview without waking you.

        Audit source schemas independently before judging semantics. Informational updates, anomaly
        candidates, recovery records, and control records may have different shapes. Do not apply
        anomaly-required fields to informational records. Reconcile the checkpoint's bounded knowledge
        register with the latest source so every new goal-relevant fact remains represented in telemetry,
        dashboard signals, or `importantInformation`; later events must not silently erase it. Keep
        technical decoys and internal implementation counters out of the task-focused Overview.

        When reporting a relative regression, comparison, or threshold, name the correct baseline and
        keep it distinct from any absolute target. A relative regression can be confirmed while the
        absolute value remains inside a separate target; do not imply an absolute breach unless the
        evidence proves one.

        Atomically write `.loopforge/watcher/review.json` on every review:
        {
          "schemaVersion": 1,
          "reviewedAt": "current ISO-8601 timestamp",
          "headline": "Short task-specific conclusion",
          "summary": "Evidence-grounded explanation of the present outcome",
          "issues": [{
            "id": "exact id from CURRENT ACTIVE PIPELINE FINDINGS",
            "title": "Short finding title",
            "detail": "What the finding means now",
            "disposition": "confirmed|dismissed|resolved",
            "severity": "info|warning|critical",
            "evidence": "Bounded concrete evidence or reason",
            "userActionRequired": false
          }],
          "importantInformation": [{
            "id": "stable-bounded-id",
            "title": "Information important to the original outcome",
            "detail": "Why it matters now",
            "severity": "info|warning|critical",
            "signalKey": "declared.signal.key-or-null",
            "value": null,
            "unit": null,
            "goalAnchorID": "an id declared in manifest.dashboard.goalAnchors",
            "userActionRequired": false
          }]
        }
        Classify every active finding you actually inspected. Never claim an individual confirmation or
        dismissal only in prose. A dismissed finding remains visible with its evidence; do not delete its
        audit record. Reconcile every previously confirmed or user-action finding: retain it as confirmed
        only while evidence still supports it, otherwise emit the same id with `resolved`. This prevents a
        stale red attention state while preserving the decision history. Important information without a
        valid goal anchor is rejected so operational noise
        cannot displace the user's objective.

        Run every relevant verification. LoopForge will independently rerun manifest verification commands
        before accepting your result. Increment `revision` only when the manifest or pipeline changes, and
        never decrease it. Atomically update `.loopforge/watcher/manifest.json`; leave it valid under schema
        version 1. Conclude with a concise assessment. The final line must be exactly one status marker from
        the allowed contract below. Do not quote, list, or mention any of the other markers in your response:
        LOOPFORGE_WATCHER_STATUS: HEALTHY
        Or use the corresponding single final marker for REPAIRED, NEEDS_USER, or COMPLETE.
        """
    }

    static func independentReviewPrompt(
        watcher: ContinuumWatcher,
        authorDecision: WatcherReviewDecision,
        pipeline: WatcherPipeline,
        assessment: WatcherAgentAssessment,
        pipelineDigest: ContentDigest,
        assessmentDigest: ContentDigest,
        authorThreadID: String,
        completionReceipt: WatcherDeterministicCompletionReceipt? = nil
    ) -> String {
        let manifest = (try? JSONEncoder.loopForge.encode(pipeline))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "Manifest unavailable"
        let review = (try? JSONEncoder.loopForge.encode(assessment))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "Assessment unavailable"
        let completionEvidence: String
        if let completionReceipt,
           let data = try? JSONEncoder.loopForge.encode(completionReceipt),
           let encoded = String(data: data, encoding: .utf8),
           let digest = try? WatcherIndependentReviewPolicy.digest(completionReceipt) {
            completionEvidence = """
            EXACT DETERMINISTIC COMPLETION RECEIPT
            SHA-256: \(digest.rawValue)
            \(encoded)
            """
        } else {
            completionEvidence = """
            DETERMINISTIC COMPLETION RECEIPT
            None. The author is not permitted to claim COMPLETE without one.
            """
        }
        return """
        You are the independent, adversarial reviewer for a LoopForge Continuum Watcher.
        You did not author the candidate pipeline or assessment. Your session is read-only: do not
        create, edit, delete, rename, restore, or format any file, and do not run commands that can
        mutate the workspace. Do not delegate or create subordinate Agents.

        ORIGINAL OUTCOME
        \(watcher.request)

        SELECTED WORKSPACE BOUNDARY
        \(watcher.workspacePath)
        Treat that exact directory as the project root. Do not inspect its parent or siblings.

        AUTHOR CLAIM
        Decision: \(authorDecision.rawValue.uppercased())
        Author thread: \(authorThreadID)

        EXACT CANDIDATE MANIFEST
        SHA-256: \(pipelineDigest.rawValue)
        \(manifest)

        EXACT CANDIDATE ASSESSMENT
        SHA-256: \(assessmentDigest.rawValue)
        \(review)

        \(completionEvidence)

        Independently inspect the live, bounded evidence needed to test the claim. Reject the claim if
        the assessment invents evidence, omits an active finding, launders an Agent opinion as a fact,
        weakens a threshold without objective support, declares completion without deterministic proof,
        or if the manifest/assessment no longer matches the exact digests above. For REPAIRED, verify
        that the revision increased and the repair addresses the stated fault. For COMPLETE, require the
        exact deterministic completion receipt above and independently test its telemetry, checkpoint,
        verification-plan, unresolved-issue, and goal-anchor bindings. For HEALTHY or NEEDS_USER, require the item-level dispositions
        and evidence to support the status. A successful command alone is never sufficient.

        Give a concise evidence-grounded rationale. Your final line must be exactly one of the independent
        review markers; do not quote or mention the other marker anywhere else in your response. Use the
        approval marker only when the exact candidate is supported. Otherwise use the rejection marker.
        LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED
        For rejection, use the same prefix with REJECTED as its final word.
        """
    }
}
