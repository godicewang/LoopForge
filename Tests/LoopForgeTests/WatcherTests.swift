import XCTest
@testable import LoopForge

final class WatcherTests: XCTestCase {
    func testModuleNamesExposeAutoLoopAndContinuumWatcher() {
        XCTAssertEqual(LoopForgeModule.allCases.map(\.title), [
            "Auto Loop",
            "Continuum Watcher"
        ])
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

        let review = WatcherPromptCompiler.reviewPrompt(
            watcher: watcher,
            reason: "threshold crossed",
            telemetry: nil,
            recentEvents: watcher.events
        )
        XCTAssertTrue(review.contains("On EVERY"))
        XCTAssertTrue(review.contains("pipeline itself is healthy"))
        XCTAssertTrue(review.contains("adapt instrumentation"))
        XCTAssertTrue(review.contains("Do not quote, list, or mention"))
        XCTAssertTrue(review.contains("corresponding single final marker for REPAIRED"))
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
