import AppKit
import Foundation
import XCTest
@testable import LoopForge

/// A fresh second release-candidate pass aimed at failure recovery, pressure,
/// and cross-module lifecycle boundaries that were not exercised in round one.
@MainActor
final class ReleaseScenarioRoundTwoTests: XCTestCase {
    func testR2SingleLoopRetainsFreshVisualEvidenceThroughFinalAudit() async throws {
        let root = try temporaryDirectory("single-visual")
        try "# Visual app\n\nRun `swift test`.\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "struct Dashboard { let title = \"Live operations\" }\n".write(
            to: root.appendingPathComponent("Dashboard.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "import XCTest\nfinal class DashboardTests: XCTestCase { func testTitle() { XCTAssertTrue(true) } }\n".write(
            to: root.appendingPathComponent("DashboardTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "// swift-tools-version: 6.0\n".write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        var task = releaseTask(
            workspace: root,
            mode: .singleLoop,
            category: .nativeApp,
            request: "Build and visually verify a polished native operations dashboard."
        )
        task.visualAuditRequired = true
        task.lastAgentMessage = "The running product was inspected. LOOPFORGE_STATUS: COMPLETE"
        task.logs = [
            TaskLogEntry(kind: .command, message: "swift test: 1 passed; exit code 0")
        ]
        let collector = WorkspaceEvidenceCollector()
        let before = collector.fingerprint(workspacePath: root.path)
        let evidenceDirectory = root.appendingPathComponent(
            ".loopforge/evidence/iteration-1",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: evidenceDirectory,
            withIntermediateDirectories: true
        )
        try makeScreenshot().write(
            to: evidenceDirectory.appendingPathComponent("dashboard-appshot.png")
        )
        let pendingAudit = WorkspaceAuditor().audit(task: task)
        let evidence = await collector.collect(
            task: task,
            workerFeedback: "Captured the running dashboard.",
            audit: pendingAudit,
            before: before
        )
        XCTAssertEqual(evidence.screenshotPaths.count, 1)
        XCTAssertEqual(evidence.visualInspection?.passedBasicIntegrity, true)
        XCTAssertFalse(pendingAudit.passed)

        task.visualAuditPassed = evidence.visualInspection?.passedBasicIntegrity == true
        XCTAssertTrue(WorkspaceAuditor().audit(task: task).passed)
    }

    func testR2SingleLoopRapidCheckpointUpdatesReloadLatestAtomicState() throws {
        let root = try temporaryDirectory("single-checkpoint-pressure")
        let storage = root.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: storage)
        var task = releaseTask(
            workspace: root,
            mode: .singleLoop,
            category: .maintenance,
            request: "Repair a data migration while preserving every user record."
        )
        task.status = .running
        task.resumeOnNextLaunch = true
        store.add(task)
        for index in 1...150 {
            store.update(id: task.id) {
                $0.stage = "Durable migration checkpoint \(index)"
                $0.accumulatedCodexSeconds = TimeInterval(index * 7)
                $0.auditSummary = "Verified batch \(index)"
            }
        }

        let recovered = TaskStore(storageURL: storage).task(id: task.id)
        XCTAssertEqual(
            recovered?.stage,
            "Recovered the last checkpoint; waiting for permissions and Codex before continuing"
        )
        XCTAssertEqual(recovered?.accumulatedCodexSeconds, 1_050)
        XCTAssertEqual(recovered?.auditSummary, "Verified batch 150")
        XCTAssertEqual(recovered?.status, .paused)
        XCTAssertEqual(recovered?.resumeOnNextLaunch, true)
    }

    func testR2GraphIncrementalReviewReplacesUnsafeBranchWithoutErasingHistory() {
        var trigger = graphNode(id: "contract", dependencies: [])
        trigger.joinGroupID = "frontier-2"
        markCompleted(&trigger)
        var obsolete = graphNode(id: "legacy-storage", dependencies: [])
        obsolete.joinGroupID = "frontier-2"
        obsolete.status = .running
        obsolete.workspaceStrategy = .gitWorktree
        obsolete.accumulatedActiveSeconds = 932
        var sibling = graphNode(id: "accessibility", dependencies: [])
        sibling.joinGroupID = "frontier-2"
        sibling.status = .running
        sibling.workspaceStrategy = .gitWorktree
        var graph = graphState(nodes: [trigger, obsolete, sibling])
        graph.incrementallyReviewedNodeIDs = ["contract"]

        let safe = GraphIncrementalReviewPolicy.safeRetirementIDs(
            ["legacy-storage"],
            in: graph
        )
        XCTAssertEqual(safe, ["legacy-storage"])
        let replacements = GraphPlanPolicy.incrementalJoinNodes(
            [
                GraphPlanNodeProposal(
                    id: "transactional-storage",
                    title: "Implement transactional storage",
                    objective: "Replace the invalid storage plan without touching the useful accessibility branch.",
                    dependencies: ["contract"],
                    writeScopes: ["Sources/Storage"],
                    verification: ["Run migration and recovery tests"],
                    readOnly: false,
                    joinGroup: "frontier-2",
                    replacesNodeIDs: ["legacy-storage"]
                )
            ],
            existingNodes: graph.nodes,
            groupID: "frontier-2",
            completedGroupNodeIDs: ["contract"],
            retiredNodes: [obsolete],
            triggerNodeID: "contract"
        )
        XCTAssertEqual(replacements.count, 1)
        graph.nodes[1].status = .superseded
        graph.nodes[1].supersededAt = Date()
        graph.nodes[1].supersededReason = "The completed contract proved that this branch could lose user edits."
        graph.nodes[1].supersededByNodeIDs = [replacements[0].id]
        graph.nodes.append(replacements[0])

        XCTAssertEqual(GraphSchedulingPolicy.revealedNodes(state: graph).count, 4)
        XCTAssertEqual(
            GraphPresentationPolicy.incomingEdgeDisposition(for: graph.nodes[1]),
            .superseded
        )
        XCTAssertEqual(graph.nodes[1].accumulatedActiveSeconds, 932)
        XCTAssertFalse(GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph))
        XCTAssertEqual(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: ["accessibility"],
                maximumToStart: 2
            ),
            ["transactional-storage"]
        )
    }

    func testR2GraphParallelWorktreesIntegrateDisjointTextAndBinaryResults() async throws {
        let root = try temporaryDirectory("graph-binary-integration")
        try "baseline\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try await git(["init"], at: root)
        try await git(["add", "README.md"], at: root)
        try await git(
            [
                "-c", "user.name=LoopForge",
                "-c", "user.email=loopforge@localhost",
                "commit", "-m", "baseline"
            ],
            at: root
        )
        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: root.path)
        XCTAssertTrue(capability.supportsParallelWorktrees)
        let task = releaseTask(
            workspace: root,
            mode: .autoGraph,
            category: .nativeApp,
            request: "Build a native product with parallel source and binary asset work."
        )
        var sourceNode = graphNode(id: "source", dependencies: [])
        sourceNode.writeScopes = ["Sources"]
        var assetNode = graphNode(id: "assets", dependencies: [])
        assetNode.writeScopes = ["Assets"]
        let preparedSource = try await coordinator.prepare(
            task: task,
            node: sourceNode,
            capability: capability
        )
        let preparedAsset = try await coordinator.prepare(
            task: task,
            node: assetNode,
            capability: capability
        )
        let sourceRoot = URL(fileURLWithPath: try XCTUnwrap(preparedSource.workspacePath))
        let assetRoot = URL(fileURLWithPath: try XCTUnwrap(preparedAsset.workspacePath))
        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: assetRoot.appendingPathComponent("Assets"),
            withIntermediateDirectories: true
        )
        try "struct ReleaseFeature {}\n".write(
            to: sourceRoot.appendingPathComponent("Sources/ReleaseFeature.swift"),
            atomically: true,
            encoding: .utf8
        )
        let binary = Data((0..<8_192).map { UInt8(($0 * 31) % 251) })
        try binary.write(to: assetRoot.appendingPathComponent("Assets/hero.bin"))

        let sourceIntegration = await coordinator.integrate(
            task: task,
            node: preparedSource
        )
        let assetIntegration = await coordinator.integrate(
            task: task,
            node: preparedAsset
        )
        XCTAssertEqual(sourceIntegration, .applied)
        XCTAssertEqual(assetIntegration, .applied)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/ReleaseFeature.swift").path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("Assets/hero.bin")),
            binary
        )
    }

    func testR2WatcherBoundsChildOutputWithoutHangingOrMemoryAmplification() async throws {
        let root = try temporaryDirectory("watcher-output-pressure")
        let script = root.appendingPathComponent("flood.py")
        try """
        import sys
        sys.stdout.write("x" * 25_000_000)
        """.write(to: script, atomically: true, encoding: .utf8)
        let started = Date()
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [script.path],
            currentDirectory: root,
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertLessThan(result.stdout.utf8.count, 5 * 1_024 * 1_024)
        XCTAssertTrue(result.stdout.contains("[output truncated]"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testR2WatcherTimeoutReclaimsChildAndRunnerRemainsReusable() async throws {
        let root = try temporaryDirectory("watcher-timeout")
        let script = root.appendingPathComponent("stall.py")
        try "import time\ntime.sleep(60)\n".write(
            to: script,
            atomically: true,
            encoding: .utf8
        )
        let started = Date()
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [script.path],
                currentDirectory: root,
                timeout: 0.2
            )
            XCTFail("The stalled watcher pass must time out.")
        } catch ProcessRunnerError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
        let recovery = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            currentDirectory: root,
            timeout: 2
        )
        XCTAssertEqual(recovery.exitCode, 0)
    }

    func testR2WatcherRejectsOversizedTelemetryAndCheckpointArtifacts() throws {
        let root = try temporaryDirectory("watcher-size-limits")
        let pipeline = watcherPipeline(signals: [signal("pipeline.duration_seconds")])
        let base = root.appendingPathComponent(".loopforge/watcher", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data(
            repeating: 0x20,
            count: WatcherPolicy.maximumTelemetryBytes + 1
        ).write(to: base.appendingPathComponent("telemetry.json"))
        XCTAssertThrowsError(
            try WatcherPolicy.loadTelemetry(
                pipeline: pipeline,
                workspacePath: root.path
            )
        ) { error in
            XCTAssertEqual(
                error as? WatcherPolicyError,
                .oversizedFile("telemetry.json")
            )
        }

        try Data(
            repeating: 0,
            count: WatcherPolicy.maximumCheckpointBytes + 1
        ).write(to: base.appendingPathComponent("checkpoint.json"))
        XCTAssertThrowsError(
            try WatcherPolicy.validateCheckpoint(
                pipeline: pipeline,
                workspacePath: root.path
            )
        ) { error in
            XCTAssertEqual(
                error as? WatcherPolicyError,
                .oversizedFile("checkpoint.json")
            )
        }
    }

    func testR2WatcherPrunesObsoleteCardinalityAndIgnoresInformationalEvents() throws {
        var pipeline = watcherPipeline(signals: [signal("queue.backlog")])
        pipeline.rules = [
            WatcherRule(
                id: "queue-high",
                title: "Queue backlog is high",
                signalKey: "queue.backlog",
                comparator: .above,
                threshold: 100,
                upperThreshold: nil,
                requiredConsecutiveMatches: 2,
                cooldownSeconds: 7_200,
                severity: .warning,
                wakesAgent: true
            )
        ]
        var state = WatcherRuntimeState.empty
        for index in 0..<20_000 {
            state.latestSignals["tenant.\(index)"] = Double(index)
            state.latestSignalAt["tenant.\(index)"] = Date()
            state.ruleMatchCounts["legacy.\(index)"] = 1
        }
        let telemetry = WatcherTelemetryEnvelope(
            schemaVersion: 1,
            capturedAt: Date(),
            status: "ok",
            summary: "Routine batch completed",
            signals: ["queue.backlog": 12],
            events: [
                WatcherTelemetryEvent(
                    name: "checkpoint-advanced",
                    severity: .info,
                    message: "Routine checkpoint advanced"
                )
            ],
            completed: false,
            checkpoint: "batch-42"
        )
        let evaluation = WatcherPolicy.evaluate(
            pipeline: pipeline,
            telemetry: telemetry,
            state: &state
        )
        XCTAssertEqual(state.latestSignals, ["queue.backlog": 12])
        XCTAssertEqual(state.latestSignalAt.count, 1)
        XCTAssertEqual(state.ruleMatchCounts, ["queue-high": 0])
        XCTAssertFalse(evaluation.shouldWakeAgent)
        XCTAssertEqual(evaluation.highestSeverity, .info)
    }

    private func releaseTask(
        workspace: URL,
        mode: LoopExecutionMode,
        category: TaskCategory,
        request: String
    ) -> LoopTask {
        let now = Date()
        return LoopTask(
            id: UUID(),
            title: "Second-round release scenario",
            request: request,
            quality: .medium,
            category: category,
            workspacePath: workspace.path,
            targetSeconds: TimeInterval(QualityTier.medium.defaultRuntimeMinutes * 60),
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
            originalRequest: request,
            executionMode: mode
        )
    }

    private func graphNode(id: String, dependencies: [String]) -> GraphLoopNode {
        GraphLoopNode(
            id: id,
            title: id.replacingOccurrences(of: "-", with: " ").capitalized,
            objective: "Complete \(id) and verify its exact scope.",
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
            workspacePath: nil,
            isolationRootPath: nil,
            workspaceStrategy: .gitWorktree,
            integrationBaseCommit: nil,
            currentInstruction: "Complete \(id).",
            lastAgentMessage: "",
            lastReview: "",
            consecutiveFailures: 0,
            createdAt: Date(),
            completedAt: nil,
            logs: []
        )
    }

    private func graphState(nodes: [GraphLoopNode]) -> GraphLoopState {
        GraphLoopState(
            phase: .executing,
            planSummary: "Incremental review fixture",
            nodes: nodes,
            mainInteractionCount: 2,
            mainLastReview: "The first completed node exposed a material plan risk.",
            maxConcurrentNodes: 3,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: Date(),
            completedAt: nil
        )
    }

    private func markCompleted(_ node: inout GraphLoopNode) {
        node.status = .completed
        node.completedAt = Date()
        node.lastReview = "Approved and integrated."
    }

    private func watcherPipeline(
        signals: [WatcherSignalSpec]
    ) -> WatcherPipeline {
        WatcherPipeline(
            schemaVersion: 1,
            revision: 1,
            command: ["/usr/bin/true"],
            workingDirectory: ".",
            telemetryPath: ".loopforge/watcher/telemetry.json",
            checkpointPath: ".loopforge/watcher/checkpoint.json",
            generatedPaths: [".loopforge/watcher"],
            verificationCommands: [["/usr/bin/true"]],
            pollIntervalSeconds: 60,
            reviewIntervalSeconds: 7_200,
            timeoutSeconds: 30,
            signals: signals,
            rules: []
        )
    }

    private func signal(_ key: String) -> WatcherSignalSpec {
        WatcherSignalSpec(
            key: key,
            title: key,
            kind: .gauge,
            unit: "count",
            description: "Second-round release signal",
            expectedMinimum: nil,
            expectedMaximum: nil,
            staleAfterSeconds: nil
        )
    }

    private func git(_ arguments: [String], at root: URL) async throws {
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            currentDirectory: root,
            timeout: 20
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
    }

    private func makeScreenshot() throws -> Data {
        let image = NSImage(size: NSSize(width: 1_280, height: 800))
        image.lockFocus()
        NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1_280, height: 800).fill()
        NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 110, y: 120, width: 1_060, height: 560),
            xRadius: 36,
            yRadius: 36
        ).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LoopForgeReleaseScenarios", code: 1)
        }
        return png
    }

    private func temporaryDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LoopForge-R2-\(label)-\(UUID().uuidString)",
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
