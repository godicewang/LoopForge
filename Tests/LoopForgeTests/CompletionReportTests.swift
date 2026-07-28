import Foundation
import XCTest
@testable import LoopForge

final class CompletionReportTests: XCTestCase {
    func testModelNarrativeDecoderAndBeforeAfterDashboardAreGrounded() throws {
        let json = """
        {
          "executiveSummary":"The verified workflow is ready.",
          "completedWork":["Added recovery"],
          "currentExperience":"The user can resume safely.",
          "notableChanges":["Added an atomic checkpoint"],
          "evaluation":[{"dimension":"Reliability","score":91,"evidence":"Recovery test passed"}],
          "limitations":["No App Store signing was tested"],
          "recommendedNextSteps":["Sign with a distribution identity"]
        }
        """
        let narrative = CompletionReportGenerator.decodeNarrative("```json\n\(json)\n```")
        XCTAssertEqual(narrative?.evaluation.first?.score, 91)
        XCTAssertEqual(narrative?.limitations.first, "No App Store signing was tested")
    }

    func testDeliveryReportExplainsWorkAndCopiesVisualEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let screenshot = directory.appendingPathComponent("screen.png")
        try Data("fake image".utf8).write(to: screenshot)
        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Atlas <script>", request: "Build & verify the product", quality: .medium,
            category: .nativeApp, workspacePath: directory.path,
            targetSeconds: 18_000, accumulatedCodexSeconds: 18_020,
            model: .advancedVisualAuditor, status: .auditing, stage: "Final audit", iteration: 3, threadID: "thread",
            auditScore: 88, auditSummary: "Ready", lastAgentMessage: "Done", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil,
            logs: [
                TaskLogEntry(kind: .control, message: "LoopForge → official Codex #1\nImplement the primary flow."),
                TaskLogEntry(kind: .command, message: "swift test · 42 passed"),
                TaskLogEntry(kind: .audit, message: "Local review approved the release path.")
            ],
            visualAuditRequired: true, visualAuditPassed: true,
            visualAuditSummary: "Hierarchy and states approved", visualEvidencePaths: [screenshot.path],
            supervisorCompletionApproved: true, controlInteractionCount: 1,
            lastEvidenceCoverage: ["Primary workflow: candidate evidence attached"]
        )
        let node = GraphLoopNode(
            id: "verify-delivery",
            title: "Verify delivery",
            objective: "Exercise the integrated product.",
            dependencies: [],
            writeScopes: [],
            verification: ["swift test"],
            readOnly: true,
            status: .completed,
            iteration: 2,
            accumulatedActiveSeconds: 120,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: directory.path,
            isolationRootPath: nil,
            workspaceStrategy: .sharedReadOnly,
            integrationBaseCommit: nil,
            currentInstruction: "Verify.",
            lastAgentMessage: "Verified.",
            lastReview: "Approved.",
            consecutiveFailures: 0,
            createdAt: now,
            completedAt: now,
            logs: []
        )
        task.executionMode = .autoGraph
        task.graphState = GraphLoopState(
            phase: .completed,
            planSummary: "Verified graph",
            nodes: [node],
            mainInteractionCount: 1,
            mainLastReview: "Approved.",
            maxConcurrentNodes: 1,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: now,
            completedAt: now
        )
        var snapshot = WorkspaceSnapshot()
        snapshot.sourceFiles = 12
        snapshot.testFiles = 7
        let audit = AuditResult(
            score: 88, passed: true, summary: "Core flow is complete and verified.",
            findings: [], nextActions: []
        )

        let path = try CompletionReportGenerator().generate(task: task, audit: audit, snapshot: snapshot)
        let html = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(html.contains("LoopForge delivery report"))
        XCTAssertTrue(html.contains("Control history") || html.contains("control history"))
        XCTAssertTrue(html.contains("Product evidence"))
        XCTAssertTrue(html.contains("What changed"))
        XCTAssertTrue(html.contains("Product strengths"))
        XCTAssertTrue(html.contains("Requirement evidence coverage"))
        XCTAssertTrue(html.contains("Graph performance"))
        XCTAssertTrue(html.contains("parallel work factor"))
        XCTAssertTrue(html.contains("Primary workflow: candidate evidence attached"))
        XCTAssertTrue(html.contains("data-loopforge-report-schema=\"3\""))
        XCTAssertTrue(html.contains("Grounded in retained local evidence"))
        XCTAssertTrue(html.contains("Verification and audit trail"))
        XCTAssertTrue(html.contains("dialog class=\"lightbox\""))
        XCTAssertTrue(html.contains("aria-label=\"Report sections\""))
        XCTAssertTrue(html.contains("Atlas &lt;script&gt;"))
        XCTAssertFalse(html.contains("<h1>Atlas <script>"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("media/evidence-01.png").path))
    }

    func testParallelCandidateReportExplainsConfiguredWorktreeCount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Candidate comparison", request: "Build alternatives", quality: .low,
            category: .maintenance, workspacePath: directory.path,
            targetSeconds: 7_200, accumulatedCodexSeconds: 7_200,
            model: .advancedVisualAuditor, status: .completed, stage: "Done", iteration: 2, threadID: nil,
            auditScore: 90, auditSummary: "Winner verified", lastAgentMessage: "Done", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: now, logs: []
        )
        task.executionMode = .parallelCandidates
        task.parallelCandidateCount = 6
        let audit = AuditResult(score: 90, passed: true, summary: "Winner verified.", findings: [], nextActions: [])
        let path = try CompletionReportGenerator().generate(
            task: task,
            audit: audit,
            snapshot: WorkspaceSnapshot()
        )
        let html = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(html.contains("Candidate branches"))
        XCTAssertTrue(html.contains("6 isolated Git worktrees"))
    }
}
