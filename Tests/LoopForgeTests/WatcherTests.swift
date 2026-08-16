import XCTest
@testable import LoopForge

final class WatcherTests: XCTestCase {
    func testModuleNamesExposeAutoLoopAndContinuumWatcher() {
        XCTAssertEqual(LoopForgeModule.allCases.map(\.title), [
            "Auto Loop",
            "Continuum Watcher"
        ])
    }

    func testWatcherGuideCoversEveryConfigurationStage() {
        XCTAssertEqual(
            WatcherGuideStep.allCases.map(\.title),
            [
                "Describe the target",
                "Choose its workspace",
                "Set the cadence",
                "Keep it continuous",
                "Choose the Agent",
                "Build the Watcher"
            ]
        )
        XCTAssertTrue(
            WatcherGuideStep.cadence.notes.contains {
                $0.contains("Routine pass")
            }
        )
        XCTAssertTrue(
            WatcherGuideStep.cadence.notes.contains {
                $0.contains("Agent review")
            }
        )
        XCTAssertTrue(
            WatcherGuideStep.continuity.notes.contains {
                $0.contains("checkpoint")
            }
        )
    }

    func testWatcherPersistsItsExplicitAgentAcrossRestart() throws {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.agentSelection = .codex(
            model: "gpt-test-latest",
            displayName: "GPT Test Latest",
            reasoning: "ultra",
            access: .fullAccess
        )

        let data = try JSONEncoder.loopForge.encode(watcher)
        let restored = try JSONDecoder.loopForge.decode(
            ContinuumWatcher.self,
            from: data
        )

        XCTAssertEqual(restored.agentSelection, watcher.agentSelection)
        XCTAssertEqual(restored.agentSelection?.modelID, "gpt-test-latest")
        XCTAssertEqual(restored.agentSelection?.reasoningEffort, "ultra")
        XCTAssertEqual(restored.agentSelection?.accessMode, .fullAccess)
    }

    func testLegacyWatcherWithoutAgentSelectionStillDecodes() throws {
        let root = temporaryDirectory()
        let watcher = makeWatcher(workspace: root)
        let encoded = try JSONEncoder.loopForge.encode(watcher)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "agentSelection")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder.loopForge.decode(
            ContinuumWatcher.self,
            from: legacy
        )

        XCTAssertNil(restored.agentSelection)
        XCTAssertEqual(restored.request, watcher.request)
    }

    func testSignalKindsAcceptRatesRatiosAndFuturePresentationMetadata() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(WatcherSignalKind.self, from: Data(#""rate""#.utf8)),
            .rate
        )
        XCTAssertEqual(
            try decoder.decode(WatcherSignalKind.self, from: Data(#""ratio""#.utf8)),
            .ratio
        )
        XCTAssertEqual(
            try decoder.decode(WatcherSignalKind.self, from: Data(#""histogram""#.utf8)),
            .gauge
        )
    }

    func testAgentAuthoredSeverityAliasesDecodeConservatively() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(WatcherSeverity.self, from: Data(#""error""#.utf8)),
            .critical
        )
        XCTAssertEqual(
            try decoder.decode(
                WatcherSeverity.self,
                from: Data(#""provider-specific-high""#.utf8)
            ),
            .warning
        )
    }

    func testPolicyClampsCadenceAndBoundsCardinality() throws {
        var pipeline = makePipeline()
        pipeline.pollIntervalSeconds = 1
        pipeline.reviewIntervalSeconds = 30
        pipeline.timeoutSeconds = 9_999
        pipeline.signals = (0..<130).map {
            WatcherSignalSpec(
                key: "signal.\($0)",
                title: "Signal \($0)",
                kind: .gauge,
                unit: "count",
                description: "Bounded test signal",
                expectedMinimum: nil,
                expectedMaximum: nil,
                staleAfterSeconds: nil
            )
        }
        pipeline.rules = (0..<130).map {
            WatcherRule(
                id: "rule-\($0)",
                title: "Rule \($0)",
                signalKey: "signal.\($0)",
                comparator: .above,
                threshold: 1,
                upperThreshold: nil,
                requiredConsecutiveMatches: 200,
                cooldownSeconds: 0,
                severity: .warning,
                wakesAgent: true
            )
        }
        let root = temporaryDirectory()
        let normalized = try WatcherPolicy.normalized(pipeline, workspacePath: root.path)

        XCTAssertEqual(normalized.pollIntervalSeconds, 60)
        XCTAssertEqual(normalized.reviewIntervalSeconds, 7_200)
        XCTAssertEqual(normalized.timeoutSeconds, 60)
        XCTAssertEqual(normalized.signals.count, 100)
        XCTAssertEqual(normalized.rules.count, 100)
        XCTAssertEqual(normalized.rules.first?.requiredConsecutiveMatches, 20)
        XCTAssertEqual(normalized.rules.first?.cooldownSeconds, 60)
    }

    func testInformationalRuleCannotWakeAgentOrRepeatResolvedLocalWork() throws {
        var pipeline = makePipeline()
        pipeline.signals = [
            WatcherSignalSpec(
                key: "pipeline.duration",
                title: "Pipeline duration",
                kind: .duration,
                unit: "s",
                description: "Bounded runtime",
                expectedMinimum: 0,
                expectedMaximum: 300,
                staleAfterSeconds: 900
            )
        ]
        pipeline.rules = [
            WatcherRule(
                id: "resolved-plateau",
                title: "The local pipeline already handled this plateau",
                signalKey: "pipeline.duration",
                comparator: .above,
                threshold: 3,
                upperThreshold: nil,
                requiredConsecutiveMatches: 1,
                cooldownSeconds: 60,
                severity: .info,
                wakesAgent: true
            )
        ]
        let root = temporaryDirectory()
        let normalized = try WatcherPolicy.normalized(
            pipeline,
            workspacePath: root.path
        )
        XCTAssertFalse(normalized.rules[0].wakesAgent)

        var state = WatcherRuntimeState.empty
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let evaluation = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: WatcherTelemetryEnvelope(
                schemaVersion: 1,
                capturedAt: now,
                status: "ok",
                summary: "Handled locally",
                signals: ["pipeline.duration": 4],
                events: [],
                completed: false,
                checkpoint: "plateau-handled"
            ),
            state: &state,
            now: now
        )
        XCTAssertFalse(evaluation.shouldWakeAgent)
        XCTAssertEqual(evaluation.events.first?.severity, .info)
    }

    func testPolicyRejectsShellEvaluationAndWorkspaceEscape() throws {
        let root = temporaryDirectory()
        var shell = makePipeline()
        shell.command = ["python3", "job.py", "&&", "curl", "example.com"]
        XCTAssertThrowsError(
            try WatcherPolicy.normalized(shell, workspacePath: root.path)
        ) { error in
            XCTAssertEqual(
                error as? WatcherPolicyError,
                .unsafeCommand(shell.command.joined(separator: " "))
            )
        }

        var escaping = makePipeline()
        escaping.telemetryPath = "../private.json"
        XCTAssertThrowsError(
            try WatcherPolicy.normalized(escaping, workspacePath: root.path)
        ) { error in
            XCTAssertEqual(
                error as? WatcherPolicyError,
                .pathEscapesWorkspace("../private.json")
            )
        }
    }

    func testThresholdRequiresSustainedEvidenceAndHonorsCooldown() {
        var pipeline = makePipeline()
        pipeline.rules = [
            WatcherRule(
                id: "error-rate",
                title: "Error rate is repeatedly high",
                signalKey: "error_rate",
                comparator: .above,
                threshold: 0.1,
                upperThreshold: nil,
                requiredConsecutiveMatches: 2,
                cooldownSeconds: 7_200,
                severity: .critical,
                wakesAgent: true
            )
        ]
        var state = WatcherRuntimeState.empty
        let start = Date(timeIntervalSince1970: 10_000)
        let telemetry = WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: start,
            status: "degraded",
            summary: "Elevated errors",
            signals: ["error_rate": 0.3],
            events: [],
            completed: false,
            checkpoint: "1"
        )

        let first = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: telemetry,
            state: &state,
            now: start
        )
        XCTAssertFalse(first.shouldWakeAgent)

        let second = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: telemetry,
            state: &state,
            now: start.addingTimeInterval(60)
        )
        XCTAssertTrue(second.shouldWakeAgent)
        XCTAssertEqual(second.highestSeverity, .critical)

        _ = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: telemetry,
            state: &state,
            now: start.addingTimeInterval(120)
        )
        let cooldown = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: telemetry,
            state: &state,
            now: start.addingTimeInterval(180)
        )
        XCTAssertFalse(cooldown.shouldWakeAgent)
    }

    @MainActor
    func testStoreRecoversInterruptedPipelineWithoutCountingOfflineWork() throws {
        let root = temporaryDirectory()
        let storage = root.appendingPathComponent("watchers.json")
        var watcher = makeWatcher(workspace: root)
        watcher.status = .runningPipeline
        watcher.runtime.totalRuns = 7
        watcher.runtime.lastRunAt = Date()
        try JSONEncoder.loopForge.encode([watcher]).write(to: storage)

        let store = WatcherStore(storageURL: storage)

        XCTAssertEqual(store.watchers.first?.status, .active)
        XCTAssertEqual(store.watchers.first?.runtime.totalRuns, 7)
        XCTAssertEqual(store.watchers.first?.resumeOnNextLaunch, true)
        XCTAssertTrue(
            store.watchers.first?.events.last?.message.contains("Offline time was not treated") == true
        )
    }

    func testBootstrapAndReviewPromptsEnforceDurableAdaptiveContract() {
        let root = temporaryDirectory()
        let watcher = makeWatcher(workspace: root)
        let bootstrap = WatcherPromptCompiler.bootstrapPrompt(
            watcher: watcher,
            requestedPollSeconds: 300,
            requestedReviewSeconds: 300
        )
        XCTAssertTrue(bootstrap.contains("ONE bounded, idempotent pass"))
        XCTAssertTrue(bootstrap.contains("durable checkpoint"))
        XCTAssertTrue(bootstrap.contains("Bound label cardinality"))
        XCTAssertTrue(bootstrap.contains("at least 2 hours apart"))
        XCTAssertTrue(bootstrap.contains("manifest.json"))
        XCTAssertTrue(bootstrap.contains("telemetry.json"))
        XCTAssertTrue(bootstrap.contains("independently rerun"))
        XCTAssertTrue(bootstrap.contains("never reuse a prior pass"))
        XCTAssertTrue(bootstrap.contains("Do not call collaboration"))
        XCTAssertTrue(bootstrap.contains("Do not create hidden"))
        XCTAssertTrue(bootstrap.contains("Do not wake the Agent for a condition"))
        XCTAssertTrue(bootstrap.contains("Every rule with"))
        XCTAssertTrue(bootstrap.contains("Treat the exact directory above as the project root"))
        XCTAssertTrue(bootstrap.contains("at most three bounded discovery"))
        XCTAssertTrue(bootstrap.contains("do not inspect LoopForge's own source"))
        XCTAssertTrue(bootstrap.contains("\"dashboard\""))
        XCTAssertTrue(bootstrap.contains("goalAnchors"))
        XCTAssertTrue(bootstrap.contains("surfaceAsSummary: true"))
        XCTAssertTrue(bootstrap.contains("monotonic knowledge register"))
        XCTAssertTrue(bootstrap.contains("technical decoys"))

        let review = WatcherPromptCompiler.reviewPrompt(
            watcher: watcher,
            reason: "threshold crossed",
            telemetry: nil,
            recentEvents: watcher.events
        )
        XCTAssertTrue(review.contains("On EVERY"))
        XCTAssertTrue(review.contains("pipeline itself is healthy"))
        XCTAssertTrue(review.contains("adapt instrumentation"))
        XCTAssertTrue(review.contains("Do not call collaboration"))
        XCTAssertTrue(review.contains("Do not read, search, or modify parent"))
        XCTAssertTrue(review.contains("Do not quote, list, or mention"))
        XCTAssertTrue(review.contains("corresponding single final marker for REPAIRED"))
        XCTAssertTrue(review.contains("review.json"))
        XCTAssertTrue(review.contains("confirmed|dismissed|resolved"))
        XCTAssertTrue(review.contains("different shapes"))
        XCTAssertTrue(review.contains("must not silently erase"))
        XCTAssertTrue(review.contains("relative regression"))
        XCTAssertTrue(review.contains("PREVIOUS AGENT ASSESSMENT"))
        XCTAssertTrue(review.contains("stale red attention state"))
    }

    func testWatcherReportShowsConfigurationSignalsAndTimeline() throws {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.agentSelection = .codex(
            model: "gpt-test",
            displayName: "GPT Test",
            reasoning: "ultra",
            access: .fullAccess
        )
        watcher.requestedPollIntervalSeconds = 300
        watcher.requestedReviewIntervalSeconds = 7_200
        watcher.pipeline = makePipeline()
        watcher.pipeline?.pollIntervalSeconds = 300
        watcher.pipeline?.reviewIntervalSeconds = 7_200
        watcher.runtime.totalRuns = 4
        watcher.runtime.agentWakeups = 1
        watcher.runtime.latestSignals = ["error_rate": 0.02]

        let path = try WatcherReportGenerator().generate(watcher: watcher)
        let report = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(report.contains("data-loopforge-watcher-report=\"1\""))
        XCTAssertTrue(report.contains("GPT Test"))
        XCTAssertTrue(report.contains("Full Access"))
        XCTAssertTrue(report.contains("5m"))
        XCTAssertTrue(report.contains("2h"))
        XCTAssertTrue(report.contains("Pipeline runs"))
        XCTAssertTrue(report.contains("Pipeline findings"))
        XCTAssertTrue(report.contains("Agent assessment"))
        XCTAssertTrue(report.contains("Important for your target"))
        XCTAssertTrue(report.contains("Auditable timeline"))
    }

    func testNeedsUserAttentionDoesNotReplaceOperationalState() throws {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.status = .active
        watcher.resumeOnNextLaunch = true
        watcher.lastAgentMessage = """
        A confirmed issue requires a user decision.
        LOOPFORGE_WATCHER_STATUS: NEEDS_USER
        """
        watcher.latestAssessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(),
            headline: "Decision required",
            summary: "A bounded decision remains.",
            issues: [],
            importantInformation: []
        )
        approveLatestAssessment(&watcher)

        XCTAssertTrue(watcher.requiresUserAttention)
        XCTAssertTrue(watcher.status.shouldSchedule)
        XCTAssertTrue(watcher.resumeOnNextLaunch)
        XCTAssertEqual(
            watcher.operationalStatusTitle,
            "Watching · Needs attention"
        )

        let path = try WatcherReportGenerator().generate(watcher: watcher)
        let report = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(report.contains("Watching · Needs attention"))
        XCTAssertTrue(report.contains("status critical"))
    }

    func testRepeatedNeedsUserReviewDoesNotRenotifyUnchangedAction() {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.lastAgentMessage = "LOOPFORGE_WATCHER_STATUS: NEEDS_USER"
        let assessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(),
            headline: "Decision required",
            summary: "Choose the authoritative record.",
            issues: [
                WatcherAgentIssueAssessment(
                    id: "duplicate",
                    title: "Duplicate record",
                    detail: "Two authoritative candidates remain.",
                    disposition: .confirmed,
                    severity: .critical,
                    evidence: "bounded source evidence",
                    userActionRequired: true
                )
            ],
            importantInformation: []
        )
        watcher.latestAssessment = assessment
        approveLatestAssessment(&watcher)

        XCTAssertFalse(
            WatcherAttentionPolicy.shouldNotify(
                previous: watcher,
                decision: .needsUser,
                current: assessment
            )
        )

        var changed = assessment
        changed.issues.append(WatcherAgentIssueAssessment(
            id: "owner-approval",
            title: "Owner approval",
            detail: "A second decision is now required.",
            disposition: .confirmed,
            severity: .warning,
            evidence: "new bounded evidence",
            userActionRequired: true
        ))
        XCTAssertTrue(
            WatcherAttentionPolicy.shouldNotify(
                previous: watcher,
                decision: .needsUser,
                current: changed
            )
        )
    }

    func testTaskFocusedReportDoesNotLeakTechnicalDecoy() throws {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.pipeline?.signals = [
            WatcherSignalSpec(
                key: "task.progress",
                title: "Research progress",
                kind: .progress,
                unit: "ratio",
                description: "Progress toward the requested research result.",
                expectedMinimum: 0,
                expectedMaximum: 1,
                staleAfterSeconds: 900
            ),
            WatcherSignalSpec(
                key: "pipeline.decoy_cache_entries",
                title: "Internal cache entries",
                kind: .counter,
                unit: "count",
                description: "Technical decoy.",
                expectedMinimum: 0,
                expectedMaximum: 10_000,
                staleAfterSeconds: 900
            )
        ]
        watcher.pipeline?.dashboard = WatcherDashboardSpec(
            headline: "Research remains auditable",
            preset: .research,
            goalAnchors: [
                WatcherGoalAnchor(id: "result", title: "Auditable result")
            ],
            progressSignalKey: "task.progress",
            primarySignalKeys: ["task.progress"],
            importantSignalKeys: ["task.progress"]
        )
        watcher.runtime.latestSignals = [
            "task.progress": 0.75,
            "pipeline.decoy_cache_entries": 174
        ]

        let path = try WatcherReportGenerator().generate(watcher: watcher)
        let report = try String(contentsOfFile: path, encoding: .utf8)
        let taskOverview = try XCTUnwrap(
            report.components(separatedBy: "Technical details and evidence").first
        )

        XCTAssertTrue(taskOverview.contains("Research progress"))
        XCTAssertFalse(taskOverview.contains("Internal cache entries"))
        XCTAssertTrue(report.contains("Internal cache entries"))
    }

    func testPolicySurfacesOnlyActiveWarningAndCriticalTelemetryAsFindings() {
        var state = WatcherRuntimeState.empty
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let telemetry = WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: now,
            status: "degraded",
            summary: "Bounded pass complete",
            signals: [:],
            events: [
                WatcherTelemetryEvent(
                    name: "checkpoint_saved",
                    severity: .info,
                    message: "Checkpoint saved."
                ),
                WatcherTelemetryEvent(
                    name: "queue_growth",
                    severity: .warning,
                    message: "Queue grew for three passes."
                )
            ],
            completed: false,
            checkpoint: "pass-7"
        )

        let evaluation = WatcherPolicy.evaluate(
            pipeline: makePipeline(),
            telemetry: telemetry,
            state: &state,
            now: now
        )

        XCTAssertEqual(evaluation.activeIssues.map(\.id), ["event.queue_growth"])
        XCTAssertEqual(evaluation.activeIssues.first?.title, "Queue Growth")
        XCTAssertEqual(state.activeIssues, evaluation.activeIssues)
        XCTAssertTrue(evaluation.shouldWakeAgent)
    }

    func testAgentWakeContextExcludesInformationalDecoyEvents() {
        let evaluation = WatcherEvaluation(
            events: [
                WatcherEvent(
                    kind: .anomaly,
                    severity: .info,
                    message: "Unrelated cache sample"
                ),
                WatcherEvent(
                    kind: .anomaly,
                    severity: .warning,
                    message: "Transient latency candidate"
                )
            ],
            shouldWakeAgent: true,
            highestSeverity: .warning,
            activeIssues: []
        )

        XCTAssertEqual(
            WatcherReviewContext.triggeringMessages(from: evaluation),
            ["Transient latency candidate"]
        )
    }

    func testHealthyAgentReviewPreservesCadenceAndCannotImmediatelyRecurse() {
        let now = Date(timeIntervalSince1970: 1_775_000_000)

        XCTAssertEqual(
            WatcherPostReviewSchedule.nextRunAt(
                completed: false,
                now: now,
                pollIntervalSeconds: 900,
                existingNextRunAt: nil
            ),
            now.addingTimeInterval(900)
        )
        XCTAssertEqual(
            WatcherPostReviewSchedule.nextRunAt(
                completed: false,
                now: now,
                pollIntervalSeconds: 60,
                existingNextRunAt: now.addingTimeInterval(3_600)
            ),
            now.addingTimeInterval(3_600),
            "review completion must not shorten an existing failure backoff"
        )
        XCTAssertEqual(
            WatcherPostReviewSchedule.nextRunAt(
                completed: false,
                now: now,
                pollIntervalSeconds: 0,
                existingNextRunAt: now
            ),
            now.addingTimeInterval(WatcherPolicy.minimumPollInterval),
            "even malformed or stale cadence input cannot produce immediate recursion"
        )
        XCTAssertNil(
            WatcherPostReviewSchedule.nextRunAt(
                completed: true,
                now: now,
                pollIntervalSeconds: 900,
                existingNextRunAt: now.addingTimeInterval(900)
            )
        )
    }

    func testDashboardDropsUndeclaredSignalBindingsAndKeepsGoalAnchors() throws {
        let root = temporaryDirectory()
        var pipeline = makePipeline()
        pipeline.signals = [
            WatcherSignalSpec(
                key: "research.progress",
                title: "Search progress",
                kind: .progress,
                unit: "ratio",
                description: "Share of the scheduled research space covered.",
                expectedMinimum: 0,
                expectedMaximum: 1,
                staleAfterSeconds: 900
            )
        ]
        pipeline.dashboard = WatcherDashboardSpec(
            headline: "Find a robust candidate",
            preset: .research,
            goalAnchors: [
                WatcherGoalAnchor(id: "candidate", title: "Validated candidate")
            ],
            progressSignalKey: "missing.signal",
            primarySignalKeys: ["research.progress", "missing.signal"],
            importantSignalKeys: ["missing.signal", "research.progress"]
        )

        let normalized = try WatcherPolicy.normalized(
            pipeline,
            workspacePath: root.path
        )

        XCTAssertNil(normalized.dashboard?.progressSignalKey)
        XCTAssertEqual(
            normalized.dashboard?.primarySignalKeys,
            ["research.progress"]
        )
        XCTAssertEqual(
            normalized.dashboard?.importantSignalKeys,
            ["research.progress"]
        )
        XCTAssertEqual(normalized.dashboard?.goalAnchors.first?.id, "candidate")
    }

    func testAgentAssessmentMustBeFreshAndGoalRelevant() throws {
        let root = temporaryDirectory()
        var pipeline = makePipeline()
        pipeline.dashboard = WatcherDashboardSpec(
            headline: "Protect the queue",
            preset: .operations,
            goalAnchors: [WatcherGoalAnchor(id: "queue-health", title: "Queue health")],
            progressSignalKey: nil,
            primarySignalKeys: [],
            importantSignalKeys: []
        )
        let directory = root.appendingPathComponent(
            ".loopforge/watcher",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let start = Date(timeIntervalSince1970: 1_775_000_000)
        let assessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: start,
            headline: "Queue review",
            summary: "One issue confirmed.",
            issues: [
                WatcherAgentIssueAssessment(
                    id: "queue-high",
                    title: "Queue remains high",
                    detail: "Sustained over three passes.",
                    disposition: .confirmed,
                    severity: .warning,
                    evidence: "depth=120",
                    userActionRequired: true
                )
            ],
            importantInformation: [
                WatcherImportantInformation(
                    id: "relevant",
                    title: "Recovery estimate",
                    detail: "About 18 minutes.",
                    severity: .info,
                    signalKey: nil,
                    value: nil,
                    unit: nil,
                    goalAnchorID: "queue-health",
                    userActionRequired: false
                ),
                WatcherImportantInformation(
                    id: "irrelevant",
                    title: "Unrelated",
                    detail: "Must be filtered.",
                    severity: .info,
                    signalKey: nil,
                    value: nil,
                    unit: nil,
                    goalAnchorID: "other",
                    userActionRequired: false
                )
            ]
        )
        try JSONEncoder.loopForge.encode(assessment).write(
            to: directory.appendingPathComponent("review.json"),
            options: .atomic
        )

        let loaded = try WatcherPolicy.loadAgentAssessment(
            pipeline: pipeline,
            workspacePath: root.path,
            notOlderThan: start,
            now: start.addingTimeInterval(60)
        )
        XCTAssertEqual(loaded.importantInformation.map(\.id), ["relevant"])

        XCTAssertThrowsError(
            try WatcherPolicy.loadAgentAssessment(
                pipeline: pipeline,
                workspacePath: root.path,
                notOlderThan: start.addingTimeInterval(601),
                now: start.addingTimeInterval(601)
            )
        )
    }

    func testIndependentWatcherReviewBindsDistinctLineagesAndExactArtifacts() throws {
        let pipeline = makePipeline()
        let assessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(timeIntervalSince1970: 1_775_000_000),
            headline: "Queue is healthy",
            summary: "The deterministic evidence is current.",
            issues: [],
            importantInformation: []
        )
        let author = AgentSelection.codex(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .workspaceOnly
        )
        var reviewer = author
        reviewer.accessMode = .readOnly
        let receipt = try WatcherIndependentReviewPolicy.makeReceipt(
            pipeline: pipeline,
            assessment: assessment,
            authorAgent: author,
            authorThreadID: "author-thread",
            reviewerAgent: reviewer,
            reviewerThreadID: "reviewer-thread",
            verdict: .approved,
            response: "Evidence matches.\nLOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED"
        )

        XCTAssertNoThrow(
            try WatcherIndependentReviewPolicy.validate(
                receipt,
                pipeline: pipeline,
                assessment: assessment,
                authorThreadID: "author-thread"
            )
        )
        XCTAssertNotEqual(receipt.authorLineageDigest, receipt.reviewerLineageDigest)
        XCTAssertEqual(receipt.pipelineDigest, try WatcherIndependentReviewPolicy.digest(pipeline))
        XCTAssertEqual(receipt.assessmentDigest, try WatcherIndependentReviewPolicy.digest(assessment))
    }

    func testIndependentWatcherReviewRejectsSelfApprovalArtifactDriftAndRejection() throws {
        let pipeline = makePipeline()
        let assessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(timeIntervalSince1970: 1_775_000_000),
            headline: "Candidate conclusion",
            summary: "Candidate evidence.",
            issues: [],
            importantInformation: []
        )
        let author = AgentSelection.codex(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .workspaceOnly
        )
        var reviewer = author
        reviewer.accessMode = .readOnly

        let selfReview = try WatcherIndependentReviewPolicy.makeReceipt(
            pipeline: pipeline,
            assessment: assessment,
            authorAgent: author,
            authorThreadID: "same-thread",
            reviewerAgent: reviewer,
            reviewerThreadID: "same-thread",
            verdict: .approved,
            response: "LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED"
        )
        XCTAssertThrowsError(
            try WatcherIndependentReviewPolicy.validate(
                selfReview,
                pipeline: pipeline,
                assessment: assessment,
                authorThreadID: "same-thread"
            )
        )

        let rejection = try WatcherIndependentReviewPolicy.makeReceipt(
            pipeline: pipeline,
            assessment: assessment,
            authorAgent: author,
            authorThreadID: "author-thread",
            reviewerAgent: reviewer,
            reviewerThreadID: "reviewer-thread",
            verdict: .rejected,
            response: "LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: REJECTED"
        )
        XCTAssertThrowsError(
            try WatcherIndependentReviewPolicy.validate(
                rejection,
                pipeline: pipeline,
                assessment: assessment,
                authorThreadID: "author-thread"
            )
        )

        var changedPipeline = pipeline
        changedPipeline.revision += 1
        var approved = rejection
        approved.verdict = .approved
        XCTAssertThrowsError(
            try WatcherIndependentReviewPolicy.validate(
                approved,
                pipeline: changedPipeline,
                assessment: assessment,
                authorThreadID: "author-thread"
            )
        )
    }

    func testIndependentWatcherReviewMarkerIsUnambiguous() throws {
        XCTAssertEqual(
            try WatcherIndependentReviewVerdict.parse(
                "Evidence matches.\nLOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED"
            ),
            .approved
        )
        XCTAssertThrowsError(
            try WatcherIndependentReviewVerdict.parse(
                "LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED\n"
                    + "LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: REJECTED"
            )
        )
    }

    func testIndependentWatcherReviewPromptIsReadOnlyAndDigestBound() throws {
        let root = temporaryDirectory()
        let watcher = makeWatcher(workspace: root)
        let assessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(),
            headline: "Review",
            summary: "Assessment",
            issues: [],
            importantInformation: []
        )
        let prompt = WatcherPromptCompiler.independentReviewPrompt(
            watcher: watcher,
            authorDecision: .repaired,
            pipeline: try XCTUnwrap(watcher.pipeline),
            assessment: assessment,
            pipelineDigest: ContentDigest("pipeline-sha"),
            assessmentDigest: ContentDigest("assessment-sha"),
            authorThreadID: "author-thread"
        )

        XCTAssertTrue(prompt.contains("read-only"))
        XCTAssertTrue(prompt.contains("pipeline-sha"))
        XCTAssertTrue(prompt.contains("assessment-sha"))
        XCTAssertTrue(prompt.contains("author-thread"))
        XCTAssertTrue(prompt.contains("successful command alone is never sufficient"))
    }

    func testCompletionCheckpointRequiresNonemptyJSONObjectAndStableDigest() throws {
        let root = temporaryDirectory()
        let directory = root.appendingPathComponent(".loopforge/watcher", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let checkpoint = directory.appendingPathComponent("checkpoint.json")
        let pipeline = makePipeline()

        for invalid in ["", "null", "[]", "\"checkpoint\"", "{broken"] {
            try invalid.write(to: checkpoint, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(
                try WatcherPolicy.checkpointDigest(
                    pipeline: pipeline,
                    workspacePath: root.path
                )
            )
        }

        try #"{"cursor":12,"source":"bounded"}"#.write(
            to: checkpoint,
            atomically: true,
            encoding: .utf8
        )
        let first = try WatcherPolicy.checkpointDigest(
            pipeline: pipeline,
            workspacePath: root.path
        )
        let second = try WatcherPolicy.checkpointDigest(
            pipeline: pipeline,
            workspacePath: root.path
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rawValue.count, 64)

        let receipt = WatcherDeterministicCompletionReceipt(
            schemaVersion: 1,
            verifiedAt: Date(),
            observation: WatcherDeterministicCompletionObservation(
                schemaVersion: 1,
                pipelineRevision: pipeline.revision,
                pipelineRunNumber: 1,
                capturedAt: Date(),
                observedAt: Date(),
                telemetryDigest: ContentDigest(String(repeating: "a", count: 64)),
                checkpointDigest: first,
                checkpointLabel: "cursor-12",
                unresolvedIssueIDs: []
            ),
            verificationPlanDigest: ContentDigest(String(repeating: "b", count: 64)),
            assessmentDigest: ContentDigest(String(repeating: "c", count: 64)),
            coveredGoalAnchorIDs: []
        )
        XCTAssertNoThrow(try WatcherCompletionPolicy.validateCurrentCheckpoint(
            receipt,
            pipeline: pipeline,
            workspacePath: root.path
        ))
        try #"{"cursor":13,"source":"bounded"}"#.write(
            to: checkpoint,
            atomically: true,
            encoding: .utf8
        )
        XCTAssertThrowsError(try WatcherCompletionPolicy.validateCurrentCheckpoint(
            receipt,
            pipeline: pipeline,
            workspacePath: root.path
        ))
    }

    func testDeterministicCompletionReceiptBindsRunVerificationAssessmentAndGoalCoverage() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let pipeline = completionPipeline()
        let runtime = completionRuntime(at: now)
        let assessment = completionAssessment(at: now)
        let telemetry = completionTelemetry(at: now)
        let observation = try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: telemetry,
            runtime: runtime,
            checkpointDigest: ContentDigest(String(repeating: "a", count: 64)),
            observedAt: now
        )
        let receipt = try WatcherCompletionPolicy.makeReceipt(
            observation: observation,
            pipeline: pipeline,
            runtime: runtime,
            assessment: assessment,
            verifiedAt: now
        )

        XCTAssertNoThrow(
            try WatcherCompletionPolicy.validateReceipt(
                receipt,
                pipeline: pipeline,
                runtime: runtime,
                assessment: assessment
            )
        )
        XCTAssertEqual(receipt.coveredGoalAnchorIDs, ["queue-health"])
        XCTAssertEqual(receipt.observation.pipelineRunNumber, 1)
        XCTAssertEqual(
            receipt.verificationPlanDigest,
            try WatcherIndependentReviewPolicy.digest(pipeline.verificationCommands)
        )
        var malformedDigest = receipt
        malformedDigest.observation.telemetryDigest = ContentDigest(
            String(repeating: "١", count: 64)
        )
        XCTAssertThrowsError(try WatcherCompletionPolicy.validateReceipt(
            malformedDigest,
            pipeline: pipeline,
            runtime: runtime,
            assessment: assessment
        ))
    }

    func testCompletionObservationRejectsIncompleteDegradedUncheckpointedAndUnresolvedRuns() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let pipeline = completionPipeline()
        let runtime = completionRuntime(at: now)

        var incomplete = completionTelemetry(at: now)
        incomplete.completed = false
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: incomplete,
            runtime: runtime,
            checkpointDigest: ContentDigest("checkpoint")
        ))

        var degraded = completionTelemetry(at: now)
        degraded.status = "degraded"
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: degraded,
            runtime: runtime,
            checkpointDigest: ContentDigest("checkpoint")
        ))

        var uncheckpointed = completionTelemetry(at: now)
        uncheckpointed.checkpoint = "  "
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: uncheckpointed,
            runtime: runtime,
            checkpointDigest: ContentDigest("checkpoint")
        ))

        var unresolved = runtime
        unresolved.activeIssues = [WatcherDetectedIssue(
            id: "queue-open",
            title: "Queue remains open",
            detail: "A deterministic issue remains.",
            severity: .warning,
            signalKey: nil,
            value: nil,
            detectedAt: now,
            lastSeenAt: now,
            userActionRequired: false
        )]
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: completionTelemetry(at: now),
            runtime: unresolved,
            checkpointDigest: ContentDigest("checkpoint")
        ))
    }

    func testCompletionReceiptRejectsStaleRuntimeConfirmedIssueAndMissingGoalCoverage() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let pipeline = completionPipeline()
        let runtime = completionRuntime(at: now)
        let observation = try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: completionTelemetry(at: now),
            runtime: runtime,
            checkpointDigest: ContentDigest(String(repeating: "b", count: 64)),
            observedAt: now
        )

        var stale = runtime
        stale.totalRuns = 2
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeReceipt(
            observation: observation,
            pipeline: pipeline,
            runtime: stale,
            assessment: completionAssessment(at: now)
        ))

        var confirmed = completionAssessment(at: now)
        confirmed.issues = [WatcherAgentIssueAssessment(
            id: "still-open",
            title: "Still open",
            detail: "The goal is not complete.",
            disposition: .confirmed,
            severity: .warning,
            evidence: "bounded evidence",
            userActionRequired: false
        )]
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeReceipt(
            observation: observation,
            pipeline: pipeline,
            runtime: runtime,
            assessment: confirmed
        ))

        var uncovered = completionAssessment(at: now)
        uncovered.importantInformation = []
        XCTAssertThrowsError(try WatcherCompletionPolicy.makeReceipt(
            observation: observation,
            pipeline: pipeline,
            runtime: runtime,
            assessment: uncovered
        ))
    }

    func testIndependentReviewReceiptBindsExactCompletionReceipt() throws {
        let now = Date(timeIntervalSince1970: 1_775_000_000)
        let pipeline = completionPipeline()
        let runtime = completionRuntime(at: now)
        let assessment = completionAssessment(at: now)
        let observation = try WatcherCompletionPolicy.makeObservation(
            pipeline: pipeline,
            telemetry: completionTelemetry(at: now),
            runtime: runtime,
            checkpointDigest: ContentDigest(String(repeating: "b", count: 64)),
            observedAt: now
        )
        let completion = try WatcherCompletionPolicy.makeReceipt(
            observation: observation,
            pipeline: pipeline,
            runtime: runtime,
            assessment: assessment,
            verifiedAt: now
        )
        let author = AgentSelection.codex(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .workspaceOnly
        )
        var reviewer = author
        reviewer.accessMode = .readOnly
        let receipt = try WatcherIndependentReviewPolicy.makeReceipt(
            pipeline: pipeline,
            assessment: assessment,
            authorAgent: author,
            authorThreadID: "author-thread",
            reviewerAgent: reviewer,
            reviewerThreadID: "reviewer-thread",
            completionReceipt: completion,
            verdict: .approved,
            response: "LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED",
            reviewedAt: now
        )

        XCTAssertNoThrow(try WatcherIndependentReviewPolicy.validate(
            receipt,
            pipeline: pipeline,
            assessment: assessment,
            completionReceipt: completion,
            authorThreadID: "author-thread"
        ))
        XCTAssertThrowsError(try WatcherIndependentReviewPolicy.validate(
            receipt,
            pipeline: pipeline,
            assessment: assessment,
            completionReceipt: nil,
            authorThreadID: "author-thread"
        ))
        var tampered = completion
        tampered.coveredGoalAnchorIDs = ["different-goal"]
        XCTAssertThrowsError(try WatcherIndependentReviewPolicy.validate(
            receipt,
            pipeline: pipeline,
            assessment: assessment,
            completionReceipt: tampered,
            authorThreadID: "author-thread"
        ))

        var watcher = makeWatcher(workspace: temporaryDirectory())
        watcher.pipeline = pipeline
        watcher.runtime = runtime
        watcher.latestAssessment = assessment
        watcher.latestCompletionReceipt = completion
        watcher.latestIndependentReview = receipt
        watcher.status = .completed
        XCTAssertTrue(watcher.isDeterministicallyCompleted)

        watcher.latestIndependentReview = nil
        XCTAssertFalse(watcher.isDeterministicallyCompleted)
    }

    func testLegacyCompletedWatcherWithoutReceiptFailsClosed() {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.status = .completed
        watcher.completedAt = Date()
        watcher.resumeOnNextLaunch = false

        XCTAssertFalse(watcher.isDeterministicallyCompleted)
        XCTAssertTrue(watcher.requiresUserAttention)
        XCTAssertEqual(watcher.operationalStatusTitle, "Completion evidence invalid")
    }

    @MainActor
    func testStartupDemotesLegacyCompletionWithoutResumingWorkspace() {
        let root = temporaryDirectory()
        let store = WatcherStore(storageURL: root.appendingPathComponent("watchers.json"))
        var watcher = makeWatcher(workspace: root)
        watcher.status = .completed
        watcher.completedAt = Date()
        watcher.resumeOnNextLaunch = false
        store.add(watcher)
        let defaultsName = "LoopForgeWatcherCompletionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        let controller = WatcherController(
            store: store,
            codexConnection: CodexConnectionManager(defaults: defaults),
            agentCatalog: AgentCatalog(storageURL: root.appendingPathComponent("agents.json"))
        )

        controller.beginStartup()

        let restored = store.watcher(id: watcher.id)
        XCTAssertEqual(restored?.status, .needsAttention)
        XCTAssertEqual(restored?.resumeOnNextLaunch, false)
        XCTAssertNil(restored?.completedAt)
        XCTAssertTrue(restored?.events.last?.message.contains("did not resume or mutate") == true)
        XCTAssertFalse(controller.runningWatcherIDs.contains(watcher.id))
    }

    func testUnreviewedWatcherAssessmentRemainsAdvisoryAfterRelaunch() {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.runtime.activeIssues = [WatcherDetectedIssue(
            id: "candidate",
            title: "Candidate finding",
            detail: "Awaiting independent review.",
            severity: .warning,
            signalKey: nil,
            value: nil,
            detectedAt: Date(),
            lastSeenAt: Date(),
            userActionRequired: false
        )]
        watcher.latestAssessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(),
            headline: "Self-authored conclusion",
            summary: "This must remain advisory.",
            issues: [WatcherAgentIssueAssessment(
                id: "candidate",
                title: "Dismissed by author",
                detail: "No independent review exists.",
                disposition: .dismissed,
                severity: .info,
                evidence: "author opinion",
                userActionRequired: false
            )],
            importantInformation: []
        )
        watcher.lastAgentMessage = "LOOPFORGE_WATCHER_STATUS: NEEDS_USER"

        let focus = WatcherFocusProjector.snapshot(for: watcher)

        XCTAssertNil(watcher.independentlyApprovedAssessment)
        XCTAssertEqual(focus.pendingIssues.map(\.id), ["candidate"])
        XCTAssertTrue(focus.dismissedIssues.isEmpty)
        XCTAssertFalse(watcher.requiresUserAttention)
    }

    func testFocusProjectorSeparatesAgentVerdictsAndUsesLiveTaskSignal() {
        let root = temporaryDirectory()
        var watcher = makeWatcher(workspace: root)
        watcher.pipeline?.signals = [
            WatcherSignalSpec(
                key: "batch.progress",
                title: "Batch progress",
                kind: .progress,
                unit: "ratio",
                description: "Share of eligible files processed.",
                expectedMinimum: 0,
                expectedMaximum: 1,
                staleAfterSeconds: 900
            )
        ]
        watcher.pipeline?.dashboard = WatcherDashboardSpec(
            headline: "Process every eligible file once",
            preset: .batch,
            goalAnchors: [WatcherGoalAnchor(id: "batch", title: "Exactly-once batch")],
            progressSignalKey: "batch.progress",
            primarySignalKeys: ["batch.progress"],
            importantSignalKeys: ["batch.progress"]
        )
        watcher.runtime.latestSignals = ["batch.progress": 0.75]
        watcher.runtime.activeIssues = [
            WatcherDetectedIssue(
                id: "duplicate",
                title: "Possible duplicate",
                detail: "One duplicate hash was observed.",
                severity: .warning,
                signalKey: nil,
                value: nil,
                detectedAt: Date(),
                lastSeenAt: Date(),
                userActionRequired: false
            )
        ]
        watcher.latestAssessment = WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: Date(),
            headline: "Batch is progressing",
            summary: "The duplicate is legitimate.",
            issues: [
                WatcherAgentIssueAssessment(
                    id: "duplicate",
                    title: "Expected duplicate",
                    detail: "Hash and source match.",
                    disposition: .dismissed,
                    severity: .info,
                    evidence: "same source and digest",
                    userActionRequired: false
                )
            ],
            importantInformation: []
        )
        approveLatestAssessment(&watcher)

        let focus = WatcherFocusProjector.snapshot(for: watcher)

        XCTAssertEqual(focus.pipelineIssues.count, 1)
        XCTAssertEqual(focus.pendingIssues.count, 0)
        XCTAssertEqual(focus.confirmedIssues.count, 0)
        XCTAssertEqual(focus.dismissedIssues.map(\.id), ["duplicate"])
        XCTAssertEqual(focus.progressSignal?.key, "batch.progress")
        XCTAssertEqual(focus.importantInformation.first?.value, 0.75)
    }

    func testLegacyWatcherWithoutDashboardOrAssessmentStillDecodes() throws {
        let root = temporaryDirectory()
        let watcher = makeWatcher(workspace: root)
        let encoded = try JSONEncoder.loopForge.encode(watcher)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "latestAssessment")
        var pipeline = try XCTUnwrap(object["pipeline"] as? [String: Any])
        pipeline.removeValue(forKey: "dashboard")
        object["pipeline"] = pipeline

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder.loopForge.decode(
            ContinuumWatcher.self,
            from: legacy
        )

        XCTAssertNil(restored.latestAssessment)
        XCTAssertNil(restored.pipeline?.dashboard)
        XCTAssertEqual(restored.displayTitle, watcher.displayTitle)
    }

    func testContinuumWatcherCodexTurnDisablesHiddenFanout() {
        let root = temporaryDirectory()
        let now = Date()
        let selection = AgentSelection.codex(
            model: "gpt-test",
            displayName: "GPT Test",
            reasoning: "ultra",
            access: .fullAccess
        )
        let task = LoopTask(
            id: UUID(),
            title: "Watcher",
            request: "Build a watcher",
            quality: .lightweight,
            category: .general,
            workspacePath: root.path,
            targetSeconds: 0,
            accumulatedCodexSeconds: 0,
            model: .efficientAgent,
            status: .running,
            stage: "Building a Continuum Watcher pipeline",
            iteration: 0,
            threadID: nil,
            auditScore: 0,
            auditSummary: "",
            lastAgentMessage: "",
            consecutiveFailures: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            logs: [],
            controlAgent: selection,
            subAgent: selection,
            executionMode: .singleLoop
        )
        let arguments = CodexRunner().initialArguments(task: task)

        XCTAssertTrue(arguments.contains("multi_agent"))
        XCTAssertTrue(arguments.contains("multi_agent_v2"))
        XCTAssertTrue(arguments.contains("enable_fanout"))
    }

    func testReviewDecisionRequiresExactlyOneUnambiguousMarker() throws {
        XCTAssertEqual(
            try WatcherReviewDecision.parse(
                "All checks passed.\nLOOPFORGE_WATCHER_STATUS: HEALTHY"
            ),
            .healthy
        )
        XCTAssertThrowsError(
            try WatcherReviewDecision.parse(
                """
                LOOPFORGE_WATCHER_STATUS: HEALTHY
                LOOPFORGE_WATCHER_STATUS: REPAIRED
                """
            )
        )
        XCTAssertThrowsError(
            try WatcherReviewDecision.parse("All checks passed without a marker.")
        )
    }

    func testRuntimeEnvironmentExcludesUnrelatedCredentials() {
        let sanitized = WatcherRuntimeEnvironment.sanitized([
            "HOME": "/tmp/watcher-user",
            "PATH": "/custom/bin",
            "OPENAI_API_KEY": "must-not-leak",
            "AWS_SECRET_ACCESS_KEY": "must-not-leak",
            "LOOPFORGE_WATCHER_FIXTURE": "allowed"
        ])

        XCTAssertEqual(sanitized["HOME"], "/tmp/watcher-user")
        XCTAssertEqual(sanitized["LOOPFORGE_WATCHER_FIXTURE"], "allowed")
        XCTAssertNil(sanitized["OPENAI_API_KEY"])
        XCTAssertNil(sanitized["AWS_SECRET_ACCESS_KEY"])
        XCTAssertTrue(sanitized["PATH"]?.contains("/custom/bin") == true)
        XCTAssertEqual(sanitized["NO_COLOR"], "1")
    }

    func testPolicyRejectsDuplicateRulesAndUndeclaredSignals() {
        let root = temporaryDirectory()
        var duplicate = makePipeline()
        duplicate.signals = [
            WatcherSignalSpec(
                key: "queue.depth",
                title: "Queue depth",
                kind: .gauge,
                unit: "items",
                description: "Current queue depth",
                expectedMinimum: 0,
                expectedMaximum: 100,
                staleAfterSeconds: 900
            )
        ]
        duplicate.rules = [
            rule(id: "queue-high", signalKey: "queue.depth"),
            rule(id: "queue-high", signalKey: "queue.depth")
        ]
        XCTAssertThrowsError(
            try WatcherPolicy.normalized(duplicate, workspacePath: root.path)
        )

        var undeclared = duplicate
        undeclared.rules = [rule(id: "queue-high", signalKey: "tenant.123")]
        XCTAssertThrowsError(
            try WatcherPolicy.normalized(undeclared, workspacePath: root.path)
        )
    }

    func testRealOneShotPipelineWritesDecodableTelemetry() async throws {
        let root = temporaryDirectory()
        let script = root.appendingPathComponent("watch_once.py")
        let output = root.appendingPathComponent(".loopforge/watcher/telemetry.json")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        import json
        from datetime import datetime, timezone
        from pathlib import Path
        out = Path(".loopforge/watcher/telemetry.json")
        tmp = out.with_suffix(".tmp")
        tmp.write_text(json.dumps({
          "schemaVersion": 1,
          "capturedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
          "status": "ok",
          "summary": "Processed a bounded fixture batch",
          "signals": {"items.processed": 12, "pipeline.duration_seconds": 0.02},
          "events": [],
          "completed": False,
          "checkpoint": "fixture-12"
        }))
        tmp.replace(out)
        """.write(to: script, atomically: true, encoding: .utf8)

        var pipeline = makePipeline()
        pipeline.command = ["/usr/bin/python3", "watch_once.py"]
        let execution = try WatcherPolicy.executableAndArguments(
            pipeline: pipeline,
            workspacePath: root.path
        )
        let result = try await ProcessRunner().run(
            executable: execution.0,
            arguments: execution.1,
            currentDirectory: execution.2,
            timeout: 10
        )
        let telemetry = try JSONDecoder.loopForge.decode(
            WatcherTelemetryEnvelope.self,
            from: Data(contentsOf: output)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(telemetry.signals["items.processed"], 12)
        XCTAssertEqual(telemetry.checkpoint, "fixture-12")
    }

    func testPersistenceDecoderAcceptsPortableWatcherTimestampVariants() throws {
        let template = """
        {
          "schemaVersion": 1,
          "capturedAt": "%@",
          "status": "ok",
          "summary": "Portable timestamp",
          "signals": {},
          "events": [],
          "completed": false,
          "checkpoint": "portable"
        }
        """
        let variants = [
            "2026-07-28T12:13:09.123456Z",
            "2026-07-28T12:13:09.123Z",
            "2026-07-28T12:13:09Z",
            "2026-07-28T20:13:09.123456+08:00"
        ]

        for timestamp in variants {
            let payload = String(format: template, timestamp)
            XCTAssertNoThrow(
                try JSONDecoder.loopForge.decode(
                    WatcherTelemetryEnvelope.self,
                    from: Data(payload.utf8)
                ),
                "Failed to decode \(timestamp)"
            )
        }
    }

    func testTelemetryEventAliasesDoNotTurnInfoIntoFalseAgentWake() throws {
        let payload = """
        {
          "schemaVersion": 1,
          "capturedAt": "2026-07-28T12:13:09Z",
          "status": "ok",
          "summary": "No new input",
          "signals": {},
          "events": [{
            "type": "unchanged_input",
            "message": "No new stage was observed."
          }],
          "completed": false,
          "checkpoint": "stage-4"
        }
        """
        let decoded = try JSONDecoder.loopForge.decode(
            WatcherTelemetryEnvelope.self,
            from: Data(payload.utf8)
        )
        var state = WatcherRuntimeState.empty
        let evaluation = WatcherPolicy.evaluate(
            pipeline: makePipeline(),
            telemetry: decoded,
            state: &state,
            now: Date(timeIntervalSince1970: 1_775_000_000)
        )

        XCTAssertEqual(decoded.events?.first?.name, "unchanged_input")
        XCTAssertEqual(evaluation.events.first?.severity, .info)
        XCTAssertFalse(evaluation.shouldWakeAgent)
    }

    private func makePipeline() -> WatcherPipeline {
        WatcherPipeline(
            schemaVersion: 1,
            revision: 1,
            command: ["/usr/bin/true"],
            workingDirectory: ".",
            telemetryPath: ".loopforge/watcher/telemetry.json",
            checkpointPath: ".loopforge/watcher/checkpoint.json",
            generatedPaths: [".loopforge/watcher/output"],
            verificationCommands: [["/usr/bin/true"]],
            pollIntervalSeconds: 900,
            reviewIntervalSeconds: 14_400,
            timeoutSeconds: 300,
            signals: [],
            rules: []
        )
    }

    private func completionPipeline() -> WatcherPipeline {
        var pipeline = makePipeline()
        pipeline.dashboard = WatcherDashboardSpec(
            headline: "Finish the queue safely",
            goalAnchors: [WatcherGoalAnchor(
                id: "queue-health",
                title: "Queue is durably complete"
            )],
            progressSignalKey: nil,
            primarySignalKeys: [],
            importantSignalKeys: []
        )
        return pipeline
    }

    private func completionRuntime(at date: Date) -> WatcherRuntimeState {
        var runtime = WatcherRuntimeState.empty
        runtime.lastRunAt = date
        runtime.lastSuccessfulRunAt = date
        runtime.totalRuns = 1
        runtime.lastExitCode = 0
        runtime.lastSummary = "Bounded queue complete"
        runtime.activeIssues = []
        return runtime
    }

    private func completionTelemetry(at date: Date) -> WatcherTelemetryEnvelope {
        WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: date,
            status: "ok",
            summary: "Bounded queue complete",
            signals: [:],
            events: [],
            completed: true,
            checkpoint: "queue-complete-12"
        )
    }

    private func completionAssessment(at date: Date) -> WatcherAgentAssessment {
        WatcherAgentAssessment(
            schemaVersion: 1,
            reviewedAt: date,
            headline: "Queue completion is supported",
            summary: "The bounded queue and its durable checkpoint were verified.",
            issues: [],
            importantInformation: [WatcherImportantInformation(
                id: "queue-closure",
                title: "Queue is durably complete",
                detail: "The goal anchor is covered by the bounded checkpoint and verification pass.",
                severity: .info,
                signalKey: nil,
                value: nil,
                unit: nil,
                goalAnchorID: "queue-health",
                userActionRequired: false
            )]
        )
    }

    private func approveLatestAssessment(_ watcher: inout ContinuumWatcher) {
        guard let pipeline = watcher.pipeline,
              let assessment = watcher.latestAssessment else {
            XCTFail("The test Watcher must have a pipeline and assessment before approval.")
            return
        }
        let author = AgentSelection.codex(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .workspaceOnly
        )
        var reviewer = author
        reviewer.accessMode = .readOnly
        watcher.latestIndependentReview = try! WatcherIndependentReviewPolicy.makeReceipt(
            pipeline: pipeline,
            assessment: assessment,
            authorAgent: author,
            authorThreadID: "author-thread",
            reviewerAgent: reviewer,
            reviewerThreadID: "reviewer-thread",
            verdict: .approved,
            response: "LOOPFORGE_WATCHER_INDEPENDENT_REVIEW: APPROVED"
        )
    }

    private func makeWatcher(workspace: URL) -> ContinuumWatcher {
        ContinuumWatcher(
            id: UUID(),
            title: "Batch health",
            request: "Process a large queue and detect abnormal failures.",
            workspacePath: workspace.path,
            status: .active,
            pipeline: makePipeline(),
            runtime: .empty,
            events: [WatcherEvent(kind: .created, message: "Created")],
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil,
            resumeOnNextLaunch: true,
            notificationsEnabled: false,
            launchAtLogin: false,
            lastProvider: nil,
            lastAgentMessage: "",
            bootstrapThreadID: nil,
            reviewThreadID: nil
        )
    }

    private func rule(id: String, signalKey: String) -> WatcherRule {
        WatcherRule(
            id: id,
            title: "Queue is high",
            signalKey: signalKey,
            comparator: .above,
            threshold: 10,
            upperThreshold: nil,
            requiredConsecutiveMatches: 2,
            cooldownSeconds: 7_200,
            severity: .warning,
            wakesAgent: true
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
