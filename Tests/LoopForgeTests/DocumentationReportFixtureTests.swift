import Foundation
import XCTest
@testable import LoopForge

final class DocumentationReportFixtureTests: XCTestCase {
    /// Regenerates the checked-in documentation example only when explicitly
    /// requested by Scripts/generate_report_example.sh. Normal test runs remain
    /// hermetic and do not modify the repository.
    func testGenerateCompletionReportDocumentationFixtureWhenRequested() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["LOOPFORGE_REPORT_EXAMPLE_OUTPUT"],
              !outputPath.isEmpty else {
            XCTAssertTrue(true)
            return
        }

        let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopforge-report-example-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let now = Date()
        let screenshots = [
            repository.appendingPathComponent("docs/assets/auto-graph.png").path,
            repository.appendingPathComponent("docs/assets/single-loop.png").path,
            repository.appendingPathComponent("docs/assets/continuum-watcher.png").path
        ]
        XCTAssertTrue(screenshots.allSatisfy(FileManager.default.fileExists(atPath:)))

        var task = LoopTask(
            id: UUID(),
            title: "LoopForge Open-Source Release",
            request: "Prepare LoopForge for a trustworthy public v1.0 release.",
            quality: .high,
            category: .nativeApp,
            workspacePath: workspace.path,
            targetSeconds: 36_000,
            accumulatedCodexSeconds: 45_420,
            model: .advancedVisualAuditor,
            status: .completed,
            stage: "Delivery report ready",
            iteration: 18,
            threadID: nil,
            auditScore: 96,
            auditSummary: "Release gates passed with retained verification evidence.",
            lastAgentMessage: "The tested app, release archives, documentation, and recovery paths are ready.",
            consecutiveFailures: 0,
            createdAt: now.addingTimeInterval(-52_000),
            updatedAt: now,
            completedAt: now,
            logs: [
                TaskLogEntry(kind: .control, message: "Audit the public-release baseline and convert every material gap into an evidence-backed node."),
                TaskLogEntry(kind: .control, message: "Integrate the completed UI, runtime, and Watcher branches; preserve independent verification results."),
                TaskLogEntry(kind: .control, message: "Run the clean-room release pass, inspect real screenshots, and retain exact packaging limitations."),
                TaskLogEntry(kind: .command, message: "swift test · 208 executed · 0 failures · 6 external integrations skipped"),
                TaskLogEntry(kind: .command, message: "swift build -c release -Xswiftc -warnings-as-errors · passed"),
                TaskLogEntry(kind: .command, message: "codesign --verify --deep --strict dist/LoopForge.app · passed"),
                TaskLogEntry(kind: .command, message: "shasum -a 256 release archives · recorded"),
                TaskLogEntry(kind: .audit, message: "Approved: all three core workflows have real scenario evidence and recovery coverage."),
                TaskLogEntry(kind: .audit, message: "Approved with disclosed boundary: the community archive is ad-hoc signed, not Developer ID notarized.")
            ],
            visualAuditRequired: true,
            visualAuditPassed: true,
            visualAuditSummary: "Single Loop, Auto Graph, and Watcher presentation passed visual review.",
            visualEvidencePaths: screenshots,
            supervisorCompletionApproved: true,
            controlInteractionCount: 18,
            lastEvidenceCoverage: [
                "Single Loop: iterative control, pause/resume, and evidence-gated completion verified",
                "Auto Graph: predecessor barriers, worktree isolation, replanning history, and final integration verified",
                "Continuum Watcher: bounded passes, atomic telemetry, stale-signal recovery, and adaptation verified",
                "Distribution: release build, signature structure, archives, checksums, and bilingual documentation verified"
            ]
        )
        task.shortTitle = "LoopForge v1.0 Release"
        task.originalRequest = "Validate every core workflow, repair discovered defects, prepare a clean bilingual open-source release, and make the final state understandable without reading the code."
        task.reportBaseline = ReportWorkspaceBaseline(
            capturedAt: now.addingTimeInterval(-52_000),
            totalFiles: 104,
            sourceFiles: 41,
            testFiles: 24,
            documentationFiles: 4,
            screenshotFiles: 0
        )
        task.reportGenerationProvider = "Codex · evidence-grounded final narrative"
        task.controlAgent = .codex(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .fullAccess
        )
        task.subAgent = .codex(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .fullAccess
        )
        task.executionMode = .autoGraph

        let nodes = [
            node(
                id: "single-loop-validation",
                title: "Prove Single Loop recovery",
                objective: "Exercise active-time accounting, pause/resume, iteration history, and evidence gates.",
                dependencies: [],
                iterations: 4,
                activeSeconds: 7_820,
                review: "Approved after persistence and interrupted-turn regressions passed.",
                now: now
            ),
            node(
                id: "graph-validation",
                title: "Stress Auto Graph control flow",
                objective: "Verify join barriers, incremental reviews, worktree isolation, safe replanning, and integration.",
                dependencies: [],
                iterations: 6,
                activeSeconds: 12_440,
                review: "Approved after predecessor parsing and hidden fan-out defects were repaired.",
                now: now
            ),
            node(
                id: "watcher-validation",
                title: "Harden Continuum Watcher",
                objective: "Run diverse bounded pipelines against timeout, stale state, high cardinality, and recovery cases.",
                dependencies: [],
                iterations: 5,
                activeSeconds: 10_960,
                review: "Approved across monitoring, batch, threshold, and scheduled-review workloads.",
                now: now
            ),
            node(
                id: "release-delivery",
                title: "Integrate and package v1.0",
                objective: "Re-run the complete suite, package the macOS app, inspect screenshots, and publish honest delivery evidence.",
                dependencies: ["single-loop-validation", "graph-validation", "watcher-validation"],
                iterations: 3,
                activeSeconds: 14_200,
                review: "Approved: release artifacts, documentation, checksums, and known signing boundary match the tested state.",
                now: now
            )
        ]
        task.graphState = GraphLoopState(
            phase: .completed,
            planSummary: "Three independent validation tracks joined into one evidence-gated release pass.",
            nodes: nodes,
            mainInteractionCount: 18,
            mainLastReview: "All retained evidence supports the final release claim.",
            maxConcurrentNodes: 3,
            supportsParallelWorktrees: true,
            finalRepairRounds: 2,
            createdAt: now.addingTimeInterval(-52_000),
            completedAt: now
        )

        var snapshot = WorkspaceSnapshot()
        snapshot.totalFiles = 168
        snapshot.sourceFiles = 57
        snapshot.testFiles = 49
        snapshot.documentationFiles = 13
        snapshot.screenshotFiles = 4
        snapshot.imageFiles = 5
        snapshot.lastVerificationSucceeded = true
        snapshot.recentCommandSuccesses = 4
        snapshot.samplePaths = [
            "Sources/LoopForge/GraphLoopEngine.swift",
            "Sources/LoopForge/WatcherController.swift",
            "Sources/LoopForge/CompletionReportGenerator.swift",
            "Tests/LoopForgeTests/GraphLoopTests.swift",
            "Tests/LoopForgeTests/ReleaseScenarioRoundTwoTests.swift",
            "docs/RELEASE_VALIDATION.md",
            "README.md",
            "README.zh-CN.md"
        ]
        let audit = AuditResult(
            score: 96,
            passed: true,
            summary: "LoopForge v1.0 is locally complete, reproducibly tested, and packaged with its external signing boundary stated explicitly.",
            findings: [],
            nextActions: ["Replace the ad-hoc signature with a notarized Developer ID build before broad consumer distribution."]
        )
        let narrative = CompletionReportNarrative(
            executiveSummary: "LoopForge v1.0 is ready for a public source release: all three workflows were exercised in real scenarios, failures were repaired, release artifacts were rebuilt, and the remaining signing boundary is explicit.",
            completedWork: [
                "Validated Single Loop, Auto Graph, and Continuum Watcher across 17 comprehensive scenarios.",
                "Closed recovery, graph dependency, permissions, telemetry, API compatibility, and presentation defects found by those scenarios.",
                "Built the release app and archives, verified signature structure and checksums, and completed bilingual product documentation."
            ],
            currentExperience: "A user can describe a task, choose sequential, graph, or isolated-candidate execution, interrupt and resume safely, inspect retained Agent decisions, and open one local delivery page that summarizes outcomes, screenshots, checks, limits, and next steps.",
            notableChanges: [
                "Graph successors are materialized only after required predecessors are complete, integrated, and audited.",
                "Watcher runs bounded deterministic passes and wakes an Agent only on meaningful signals or scheduled review.",
                "Completion reporting now leads with outcomes and real visual evidence while keeping technical history available on demand."
            ],
            evaluation: [
                ReportEvaluationItem(dimension: "Reliability", score: 97, evidence: "208 tests executed with zero failures; interruption and recovery paths were exercised."),
                ReportEvaluationItem(dimension: "Control transparency", score: 96, evidence: "Instructions, iterations, join reviews, branch replacements, and verification evidence remain inspectable."),
                ReportEvaluationItem(dimension: "Release readiness", score: 94, evidence: "Release app, archives, checksums, README, and screenshots match the tested source state.")
            ],
            limitations: [
                "The community macOS archive is ad-hoc signed and has not been Apple-notarized.",
                "Six credential-, browser-, or local-model-dependent integrations remain explicit opt-in environment tests."
            ],
            recommendedNextSteps: [
                "Publish a notarized Developer ID build when signing credentials are available.",
                "Run the opt-in provider matrix before claiming support for a newly released third-party model."
            ]
        )

        let generatedPath = try CompletionReportGenerator().generate(
            task: task,
            audit: audit,
            snapshot: snapshot,
            narrative: narrative
        )
        let generatedDirectory = URL(fileURLWithPath: generatedPath).deletingLastPathComponent()
        let destination = URL(fileURLWithPath: outputPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: generatedDirectory, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("index.html").path))
    }

    private func node(
        id: String,
        title: String,
        objective: String,
        dependencies: [String],
        iterations: Int,
        activeSeconds: TimeInterval,
        review: String,
        now: Date
    ) -> GraphLoopNode {
        GraphLoopNode(
            id: id,
            title: title,
            objective: objective,
            dependencies: dependencies,
            writeScopes: [],
            verification: ["Run the scoped scenario and retain exact output."],
            readOnly: false,
            status: .completed,
            iteration: iterations,
            accumulatedActiveSeconds: activeSeconds,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: nil,
            isolationRootPath: nil,
            workspaceStrategy: .gitWorktree,
            integrationBaseCommit: nil,
            currentInstruction: "Complete and verify this scoped objective.",
            lastAgentMessage: "Scoped work and verification completed.",
            lastReview: review,
            consecutiveFailures: 0,
            createdAt: now.addingTimeInterval(-activeSeconds),
            completedAt: now,
            logs: []
        )
    }
}
