import Foundation
import XCTest
@testable import LoopForge

/// First release-candidate scenario pass.
///
/// These are intentionally cross-component tasks rather than isolated parser
/// examples: each Watcher scenario executes a real bounded child pipeline,
/// consumes its durable checkpoint and telemetry, and evaluates the wake policy.
@MainActor
final class ReleaseScenarioRoundOneTests: XCTestCase {
    func testR1SingleLoopBuildVerifyAuditAndDeliveryReport() async throws {
        let root = try temporaryDirectory("single-delivery")
        try """
        def normalize(values):
            return sorted(dict.fromkeys(values))
        """.write(
            to: root.appendingPathComponent("tool.py"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import unittest
        from tool import normalize

        class ToolTests(unittest.TestCase):
            def test_deduplicates_and_sorts(self):
                self.assertEqual(normalize([3, 1, 3, 2]), [1, 2, 3])

        if __name__ == "__main__":
            unittest.main()
        """.write(
            to: root.appendingPathComponent("test_tool.py"),
            atomically: true,
            encoding: .utf8
        )
        try "# Verified CLI fixture\n\nRun `python3 -m unittest -v`.\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-m", "unittest", "-v"],
            currentDirectory: root,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)

        var task = releaseTask(
            workspace: root,
            mode: .singleLoop,
            quality: .lightweight
        )
        task.accumulatedCodexSeconds = task.targetSeconds + 3
        task.status = .auditing
        task.lastAgentMessage = "Implemented and verified. LOOPFORGE_STATUS: COMPLETE"
        task.logs = [
            TaskLogEntry(
                kind: .command,
                message: "python3 -m unittest -v · tests passed · exit code 0"
            ),
            TaskLogEntry(
                kind: .audit,
                message: "Primary behavior, edge case, documentation, and entry point verified."
            )
        ]
        let auditor = WorkspaceAuditor()
        let audit = auditor.audit(task: task, requireVisualApproval: false)
        XCTAssertTrue(audit.passed, audit.summary)
        let snapshot = auditor.snapshot(
            workspacePath: root.path,
            logs: task.logs
        )
        let report = try CompletionReportGenerator().generate(
            task: task,
            audit: audit,
            snapshot: snapshot
        )
        let reportHTML = try String(contentsOfFile: report, encoding: .utf8)
        XCTAssertTrue(reportHTML.contains("LoopForge delivery report"))
        XCTAssertTrue(reportHTML.contains("Verification"))
    }

    func testR1SingleLoopCrashRecoveryKeepsWorkspaceAndExcludesOfflineTime() throws {
        let root = try temporaryDirectory("single-recovery")
        let storage = root.appendingPathComponent("tasks.json")
        let marker = root.appendingPathComponent("durable-output.txt")
        try "preserve me".write(to: marker, atomically: true, encoding: .utf8)
        let store = TaskStore(storageURL: storage)
        var task = releaseTask(
            workspace: root,
            mode: .singleLoop,
            quality: .medium
        )
        task.status = .running
        task.accumulatedCodexSeconds = 1_234
        task.resumeOnNextLaunch = true
        task.checkpointedAt = Date()
        store.add(task)
        store.update(id: task.id) {
            $0.stage = "Durable checkpoint 1"
            $0.checkpointedAt = Date()
        }
        store.update(id: task.id) {
            $0.stage = "Durable checkpoint 2"
            $0.checkpointedAt = Date()
        }
        try Data("{corrupt".utf8).write(to: storage, options: .atomic)

        let recovered = TaskStore(storageURL: storage).task(id: task.id)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.accumulatedCodexSeconds, 1_234)
        XCTAssertEqual(recovered?.status, .paused)
        XCTAssertEqual(recovered?.resumeOnNextLaunch, true)
        XCTAssertEqual(
            try String(contentsOf: marker, encoding: .utf8),
            "preserve me"
        )
    }

    func testR1GraphJoinBarrierHidesFutureWorkUntilWholeGroupReview() {
        var baseline = graphNode(
            id: "baseline",
            title: "Audit baseline",
            dependencies: []
        )
        baseline.joinGroupID = "frontier-1"
        markCompleted(&baseline)
        var api = graphNode(
            id: "api",
            title: "Build API",
            dependencies: ["baseline"]
        )
        api.joinGroupID = "frontier-2"
        var ui = graphNode(
            id: "ui",
            title: "Build UI",
            dependencies: ["baseline"]
        )
        ui.joinGroupID = "frontier-2"
        var graph = GraphLoopState(
            phase: .executing,
            planSummary: "Only materialized work exists.",
            nodes: [baseline, api, ui],
            mainInteractionCount: 1,
            mainLastReview: "Baseline approved.",
            maxConcurrentNodes: 2,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: Date(),
            completedAt: nil,
            reviewedJoinGroupIDs: ["frontier-1"],
            incrementallyReviewedNodeIDs: ["baseline"]
        )

        XCTAssertEqual(
            Set(GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: [],
                maximumToStart: 2
            )),
            Set(["api", "ui"])
        )
        markCompleted(&api)
        graph.nodes[1] = api
        graph.incrementallyReviewedNodeIDs = ["baseline", "api"]
        XCTAssertTrue(
            GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph).isEmpty
        )
        XCTAssertEqual(graph.nodes.count, 3, "No successor may exist yet")

        markCompleted(&ui)
        graph.nodes[2] = ui
        graph.incrementallyReviewedNodeIDs = ["baseline", "api", "ui"]
        XCTAssertEqual(
            GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph),
            ["frontier-2"]
        )
        XCTAssertEqual(graph.nodes.count, 3, "The Main Agent must review before expansion")
    }

    func testR1GraphIncidentResumeDoesNotManufactureAnIteration() {
        var node = graphNode(
            id: "verify",
            title: "Verify recovery",
            dependencies: []
        )
        node.iteration = 2
        node.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Implement.",
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 20),
                threadID: "one",
                exitCode: 0,
                agentSummary: "Implemented.",
                mainReview: "Continue with real UI evidence.",
                nextInstruction: "Verify in the real UI.",
                decision: .continueWork
            ),
            GraphNodeIterationRecord(
                number: 2,
                instruction: "Verify in the real UI.",
                startedAt: Date(timeIntervalSince1970: 30),
                finishedAt: nil,
                threadID: "two",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending
            )
        ]
        var task = releaseTask(
            workspace: URL(fileURLWithPath: "/tmp"),
            mode: .autoGraph,
            quality: .medium
        )
        task.graphState = GraphLoopState(
            phase: .executing,
            planSummary: "Recovery fixture",
            nodes: [node],
            mainInteractionCount: 2,
            mainLastReview: "Waiting.",
            maxConcurrentNodes: 1,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: Date(),
            completedAt: nil
        )

        XCTAssertEqual(
            GraphIterationHistoryPolicy.nextTurnNumber(task: task, node: node),
            2
        )
        node.iterationHistory?[1].decision = .recovery
        node.iterationHistory?[1].mainReview = "Incident review completed."
        XCTAssertEqual(
            GraphIterationHistoryPolicy.nextTurnNumber(task: task, node: node),
            3
        )
    }

    func testR1WatcherServiceHealthUsesSustainedEvidenceAndCooldown() async throws {
        let root = try temporaryDirectory("watcher-health")
        try writeWatcherScript(
            """
            import json
            from datetime import datetime, timezone
            from pathlib import Path
            base = Path(".loopforge/watcher")
            base.mkdir(parents=True, exist_ok=True)
            cfg = json.loads(Path("service.json").read_text())
            cp_path = base / "checkpoint.json"
            cp = json.loads(cp_path.read_text()) if cp_path.exists() else {"run": 0}
            cp["run"] += 1
            tmp_cp = cp_path.with_suffix(".tmp")
            tmp_cp.write_text(json.dumps(cp))
            tmp_cp.replace(cp_path)
            payload = {
              "schemaVersion": 1,
              "capturedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
              "status": "degraded" if cfg["error_rate"] > 0.1 else "ok",
              "summary": "Service health sampled",
              "signals": {"service.error_rate": cfg["error_rate"], "pipeline.duration_seconds": 0.01},
              "events": [],
              "completed": False,
              "checkpoint": f"run-{cp['run']}"
            }
            out = base / "telemetry.json"
            tmp = out.with_suffix(".tmp")
            tmp.write_text(json.dumps(payload))
            tmp.replace(out)
            """,
            name: "health.py",
            root: root
        )
        try #"{"error_rate":0.25}"#.write(
            to: root.appendingPathComponent("service.json"),
            atomically: true,
            encoding: .utf8
        )
        let pipeline = watcherPipeline(
            script: "health.py",
            signals: [
                signal("service.error_rate", kind: .rate),
                signal("pipeline.duration_seconds", kind: .duration)
            ],
            rules: [
                WatcherRule(
                    id: "error-rate",
                    title: "Service error rate is repeatedly high",
                    signalKey: "service.error_rate",
                    comparator: .above,
                    threshold: 0.1,
                    upperThreshold: nil,
                    requiredConsecutiveMatches: 2,
                    cooldownSeconds: 7_200,
                    severity: .critical,
                    wakesAgent: true
                )
            ]
        )
        var state = WatcherRuntimeState.empty
        let first = try await runWatcherPass(pipeline, root: root)
        XCTAssertFalse(
            WatcherPolicy.evaluate(
                pipeline: pipeline,
                telemetry: first,
                state: &state
            ).shouldWakeAgent
        )
        let second = try await runWatcherPass(pipeline, root: root)
        XCTAssertTrue(
            WatcherPolicy.evaluate(
                pipeline: pipeline,
                telemetry: second,
                state: &state
            ).shouldWakeAgent
        )
        let third = try await runWatcherPass(pipeline, root: root)
        XCTAssertFalse(
            WatcherPolicy.evaluate(
                pipeline: pipeline,
                telemetry: third,
                state: &state
            ).shouldWakeAgent,
            "Cooldown must prevent an alert storm"
        )
    }

    func testR1WatcherLargeBatchIsIdempotentAcrossRepeatedPasses() async throws {
        let root = try temporaryDirectory("watcher-batch")
        let items = (0..<2_000).map { "item-\($0)" }.joined(separator: "\n")
        try items.write(
            to: root.appendingPathComponent("items.txt"),
            atomically: true,
            encoding: .utf8
        )
        try writeWatcherScript(
            """
            import json
            from datetime import datetime, timezone
            from pathlib import Path
            base = Path(".loopforge/watcher")
            base.mkdir(parents=True, exist_ok=True)
            items = Path("items.txt").read_text().splitlines()
            cp_path = base / "checkpoint.json"
            cp = json.loads(cp_path.read_text()) if cp_path.exists() else {"index": 0}
            out_path = base / "output.json"
            output = json.loads(out_path.read_text()) if out_path.exists() else []
            end = min(len(items), cp["index"] + 500)
            output.extend(items[cp["index"]:end])
            cp["index"] = end
            tmp_output = out_path.with_suffix(".tmp")
            tmp_output.write_text(json.dumps(output))
            tmp_output.replace(out_path)
            tmp_cp = cp_path.with_suffix(".tmp")
            tmp_cp.write_text(json.dumps(cp))
            tmp_cp.replace(cp_path)
            telemetry = {
              "schemaVersion": 1,
              "capturedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
              "status": "ok",
              "summary": f"Processed {end} of {len(items)} items",
              "signals": {
                "batch.processed_total": end,
                "batch.progress_ratio": end / len(items),
                "pipeline.duration_seconds": 0.02
              },
              "events": [],
              "completed": end == len(items),
              "checkpoint": f"index-{end}"
            }
            target = base / "telemetry.json"
            tmp = target.with_suffix(".tmp")
            tmp.write_text(json.dumps(telemetry))
            tmp.replace(target)
            """,
            name: "batch.py",
            root: root
        )
        let pipeline = watcherPipeline(
            script: "batch.py",
            signals: [
                signal("batch.processed_total", kind: .counter),
                signal("batch.progress_ratio", kind: .progress),
                signal("pipeline.duration_seconds", kind: .duration)
            ]
        )
        var telemetry: WatcherTelemetryEnvelope?
        let started = Date()
        for _ in 0..<5 {
            telemetry = try await runWatcherPass(pipeline, root: root)
        }
        let output = try JSONDecoder().decode(
            [String].self,
            from: Data(
                contentsOf: root.appendingPathComponent(
                    ".loopforge/watcher/output.json"
                )
            )
        )
        XCTAssertEqual(output.count, 2_000)
        XCTAssertEqual(Set(output).count, 2_000)
        XCTAssertEqual(telemetry?.completed, true)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testR1WatcherSecurityAggregationDoesNotLeakSecretsOrCardinality() async throws {
        let root = try temporaryDirectory("watcher-security")
        let lines = (0..<1_000).map {
            "failed_login ip=10.0.\($0 / 255).\($0 % 255) token=secret-\($0)"
        }.joined(separator: "\n")
        try lines.write(
            to: root.appendingPathComponent("access.log"),
            atomically: true,
            encoding: .utf8
        )
        try writeWatcherScript(
            """
            import json, os
            from datetime import datetime, timezone
            from pathlib import Path
            base = Path(".loopforge/watcher")
            base.mkdir(parents=True, exist_ok=True)
            failures = sum(1 for line in Path("access.log").read_text().splitlines() if "failed_login" in line)
            cp = base / "checkpoint.json"
            tmp_cp = cp.with_suffix(".tmp")
            tmp_cp.write_text(json.dumps({"offset": Path("access.log").stat().st_size}))
            tmp_cp.replace(cp)
            payload = {
              "schemaVersion": 1,
              "capturedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
              "status": "degraded",
              "summary": "Authentication anomaly aggregated",
              "signals": {
                "security.failed_login_count": failures,
                "security.parent_secret_visible": 1 if os.getenv("PRIVATE_API_KEY") else 0
              },
              "events": [{"name": "auth-spike", "severity": "warning", "message": "Sustained authentication failures"}],
              "completed": False,
              "checkpoint": "access-log-offset"
            }
            out = base / "telemetry.json"
            tmp = out.with_suffix(".tmp")
            tmp.write_text(json.dumps(payload))
            tmp.replace(out)
            """,
            name: "security.py",
            root: root
        )
        let pipeline = watcherPipeline(
            script: "security.py",
            signals: [
                signal("security.failed_login_count", kind: .counter),
                signal("security.parent_secret_visible", kind: .gauge)
            ],
            rules: [
                WatcherRule(
                    id: "failed-logins",
                    title: "Failed logins crossed the safe range",
                    signalKey: "security.failed_login_count",
                    comparator: .above,
                    threshold: 100,
                    upperThreshold: nil,
                    requiredConsecutiveMatches: 1,
                    cooldownSeconds: 7_200,
                    severity: .critical,
                    wakesAgent: true
                )
            ]
        )
        var source = ProcessInfo.processInfo.environment
        source["PRIVATE_API_KEY"] = "must-not-cross-process-boundary"
        XCTAssertNil(WatcherRuntimeEnvironment.sanitized(source)["PRIVATE_API_KEY"])
        let telemetry = try await runWatcherPass(pipeline, root: root)
        XCTAssertEqual(telemetry.signals["security.failed_login_count"], 1_000)
        XCTAssertEqual(telemetry.signals["security.parent_secret_visible"], 0)
        let raw = try String(
            contentsOf: root.appendingPathComponent(
                ".loopforge/watcher/telemetry.json"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(raw.contains("10.0."))
        XCTAssertFalse(raw.contains("secret-"))
        var state = WatcherRuntimeState.empty
        XCTAssertTrue(
            WatcherPolicy.evaluate(
                pipeline: pipeline,
                telemetry: telemetry,
                state: &state
            ).shouldWakeAgent
        )
    }

    func testR1WatcherMissingAndStaleSignalsUseCurrentPassSemantics() throws {
        var pipeline = watcherPipeline(
            script: "unused.py",
            signals: [signal("feed.heartbeat", kind: .heartbeat)],
            rules: [
                WatcherRule(
                    id: "heartbeat-missing",
                    title: "Feed heartbeat disappeared",
                    signalKey: "feed.heartbeat",
                    comparator: .missing,
                    threshold: nil,
                    upperThreshold: nil,
                    requiredConsecutiveMatches: 1,
                    cooldownSeconds: 7_200,
                    severity: .critical,
                    wakesAgent: true
                )
            ]
        )
        pipeline.verificationCommands = [["/usr/bin/true"]]
        var state = WatcherRuntimeState.empty
        let now = Date()
        let healthy = WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: now,
            status: "ok",
            summary: "Heartbeat present",
            signals: ["feed.heartbeat": 1],
            events: [],
            completed: false,
            checkpoint: "healthy"
        )
        _ = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: healthy,
            state: &state,
            now: now
        )
        let missing = WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: now.addingTimeInterval(60),
            status: "degraded",
            summary: "Heartbeat missing",
            signals: [:],
            events: [
                WatcherTelemetryEvent(
                    name: "ordinary-progress",
                    severity: .info,
                    message: "An informational event must not wake the Agent"
                )
            ],
            completed: false,
            checkpoint: "missing"
        )
        let evaluation = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: missing,
            state: &state,
            now: now.addingTimeInterval(60)
        )
        XCTAssertTrue(evaluation.shouldWakeAgent)
        XCTAssertEqual(evaluation.events.filter { $0.severity == .critical }.count, 1)
    }

    func testR1WatcherRejectsStaleTelemetryAndSymlinkWorkspaceEscape() throws {
        let root = try temporaryDirectory("watcher-boundaries")
        let outside = try temporaryDirectory("watcher-outside")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escaped"),
            withDestinationURL: outside
        )
        var escaping = watcherPipeline(
            script: "noop.py",
            signals: [signal("pipeline.duration_seconds", kind: .duration)]
        )
        escaping.telemetryPath = "escaped/telemetry.json"
        XCTAssertThrowsError(
            try WatcherPolicy.normalized(escaping, workspacePath: root.path)
        )

        try writeWatcherScript(
            """
            from pathlib import Path
            base = Path(".loopforge/watcher")
            base.mkdir(parents=True, exist_ok=True)
            (base / "checkpoint.json").write_text("{}")
            """,
            name: "noop.py",
            root: root
        )
        let pipeline = watcherPipeline(
            script: "noop.py",
            signals: [signal("pipeline.duration_seconds", kind: .duration)]
        )
        let telemetryURL = root.appendingPathComponent(
            ".loopforge/watcher/telemetry.json"
        )
        try FileManager.default.createDirectory(
            at: telemetryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let old = Date().addingTimeInterval(-3_600)
        let payload = WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: old,
            status: "ok",
            summary: "Old result",
            signals: ["pipeline.duration_seconds": 0.01],
            events: [],
            completed: false,
            checkpoint: "old"
        )
        try JSONEncoder.loopForge.encode(payload).write(to: telemetryURL)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: telemetryURL.path
        )
        XCTAssertThrowsError(
            try WatcherPolicy.loadTelemetry(
                pipeline: pipeline,
                workspacePath: root.path,
                notOlderThan: Date()
            )
        )
    }

    private func runWatcherPass(
        _ pipeline: WatcherPipeline,
        root: URL
    ) async throws -> WatcherTelemetryEnvelope {
        let normalized = try WatcherPolicy.normalized(
            pipeline,
            workspacePath: root.path
        )
        let execution = try WatcherPolicy.executableAndArguments(
            pipeline: normalized,
            workspacePath: root.path
        )
        let startedAt = Date()
        let result = try await ProcessRunner().run(
            executable: execution.0,
            arguments: execution.1,
            environment: WatcherRuntimeEnvironment.sanitized(),
            currentDirectory: execution.2,
            timeout: normalized.timeoutSeconds
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let telemetry = try WatcherPolicy.loadTelemetry(
            pipeline: normalized,
            workspacePath: root.path,
            notOlderThan: startedAt
        )
        try WatcherPolicy.validateCheckpoint(
            pipeline: normalized,
            workspacePath: root.path
        )
        return telemetry
    }

    private func watcherPipeline(
        script: String,
        signals: [WatcherSignalSpec],
        rules: [WatcherRule] = []
    ) -> WatcherPipeline {
        WatcherPipeline(
            schemaVersion: 1,
            revision: 1,
            command: ["/usr/bin/python3", script],
            workingDirectory: ".",
            telemetryPath: ".loopforge/watcher/telemetry.json",
            checkpointPath: ".loopforge/watcher/checkpoint.json",
            generatedPaths: [".loopforge/watcher"],
            verificationCommands: [
                ["/usr/bin/python3", "-m", "py_compile", script]
            ],
            pollIntervalSeconds: 60,
            reviewIntervalSeconds: 7_200,
            timeoutSeconds: 30,
            signals: signals,
            rules: rules
        )
    }

    private func signal(
        _ key: String,
        kind: WatcherSignalKind
    ) -> WatcherSignalSpec {
        WatcherSignalSpec(
            key: key,
            title: key,
            kind: kind,
            unit: "count",
            description: "Release scenario signal",
            expectedMinimum: nil,
            expectedMaximum: nil,
            staleAfterSeconds: nil
        )
    }

    private func writeWatcherScript(
        _ source: String,
        name: String,
        root: URL
    ) throws {
        try source.write(
            to: root.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    private func releaseTask(
        workspace: URL,
        mode: LoopExecutionMode,
        quality: QualityTier
    ) -> LoopTask {
        let now = Date()
        return LoopTask(
            id: UUID(),
            title: "Release scenario",
            request: "Build and verify a complete local script with documentation.",
            quality: quality,
            category: .script,
            workspacePath: workspace.path,
            targetSeconds: TimeInterval(quality.defaultRuntimeMinutes * 60),
            accumulatedCodexSeconds: 0,
            model: .efficientAgent,
            status: .paused,
            stage: "Scenario",
            iteration: 1,
            threadID: nil,
            auditScore: 0,
            auditSummary: "",
            lastAgentMessage: "",
            consecutiveFailures: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            logs: [],
            controlAgent: .codex(
                model: AppConstants.officialWorkerModel,
                displayName: "Codex",
                reasoning: "high",
                access: .fullAccess
            ),
            subAgent: .codex(
                model: AppConstants.officialWorkerModel,
                displayName: "Codex",
                reasoning: "high",
                access: .fullAccess
            ),
            originalRequest: "Build and verify a complete local script with documentation.",
            executionMode: mode
        )
    }

    private func graphNode(
        id: String,
        title: String,
        dependencies: [String]
    ) -> GraphLoopNode {
        GraphLoopNode(
            id: id,
            title: title,
            objective: title,
            dependencies: dependencies,
            writeScopes: ["Sources/\(id)"],
            verification: ["swift test"],
            readOnly: false,
            status: .waiting,
            iteration: 0,
            accumulatedActiveSeconds: 0,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: "/tmp",
            isolationRootPath: nil,
            workspaceStrategy: .gitWorktree,
            integrationBaseCommit: nil,
            currentInstruction: title,
            lastAgentMessage: "",
            lastReview: "",
            consecutiveFailures: 0,
            createdAt: Date(),
            completedAt: nil,
            logs: []
        )
    }

    private func markCompleted(_ node: inout GraphLoopNode) {
        node.status = .completed
        node.completedAt = Date()
        node.lastReview = "Approved."
    }

    private func temporaryDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LoopForge-R1-\(label)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
