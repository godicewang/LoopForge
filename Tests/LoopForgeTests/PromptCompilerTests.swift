import XCTest
@testable import LoopForge

final class PromptCompilerTests: XCTestCase {
    func testPromptOptimizationDecoderRequiresThreeStructuredChoices() throws {
        let json = """
        {"candidates":[
          {"id":"A","title":"Evidence first","prompt":"Build iOS 17 app in /tmp/demo for 5 hours","emphasis":"Proof"},
          {"id":"B","title":"Product first","prompt":"Build iOS 17 app in /tmp/demo for 5 hours","emphasis":"UX"},
          {"id":"C","title":"Release first","prompt":"Build iOS 17 app in /tmp/demo for 5 hours","emphasis":"Delivery"}
        ]}
        """
        let decoded = PromptOptimizer.decodeEnvelope(json)
        XCTAssertEqual(decoded?.candidates.count, 3)
        XCTAssertEqual(Set(decoded?.candidates.map(\.id) ?? []), Set(["A", "B", "C"]))
    }

    func testPromptOptimizationContractTokensRetainNumbersPathsAndQuotes() {
        let tokens = PromptOptimizer.contractTokens(
            in: #"Use "/Users/me/Game" with iOS 17 for 5 hours and call it “Jianghu”."#
        )
        XCTAssertTrue(tokens.contains("/Users/me/Game"))
        XCTAssertTrue(tokens.contains("17"))
        XCTAssertTrue(tokens.contains("5"))
        XCTAssertTrue(tokens.contains("Jianghu"))
    }

    func testGameWorkOrderRequiresConceptDivergenceBeforeProductionPolish() {
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Game", request: "Build an addictive original macOS game", quality: .low,
            category: .game, workspacePath: "/tmp/game", targetSeconds: 7_200, accumulatedCodexSeconds: 0,
            model: .advancedVisualAuditor, status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [], visualAuditRequired: true
        )
        let prompt = PromptCompiler().initialPrompt(for: task)
        XCTAssertTrue(prompt.contains("three mechanically distinct concepts"))
        XCTAssertTrue(prompt.contains("prototype or simulate the top two"))
        XCTAssertTrue(prompt.contains("replay depth"))
    }

    func testInitialPromptPreservesGoalAndBuildsExplicitContract() {
        var task = makeTask(request: "Fix <parser> & add regression tests", quality: .high, category: .maintenance)
        task.refinedRequest = "Repair the existing <parser> and add regression coverage without replacing unrelated code."
        task.missionRewriteAuditSummary = "All explicit requirements were preserved."
        let prompt = PromptCompiler().initialPrompt(for: task)

        XCTAssertTrue(prompt.contains("<loopforge_work_order version=\"2\">"))
        XCTAssertTrue(prompt.contains("Fix &lt;parser&gt; &amp; add regression tests"))
        XCTAssertTrue(prompt.contains("Repair the existing &lt;parser&gt;"))
        XCTAssertTrue(prompt.contains("independently_verified=\"true\""))
        XCTAssertTrue(prompt.contains("All explicit requirements were preserved"))
        XCTAssertTrue(prompt.contains("<task_mode>Build or modify</task_mode>"))
        XCTAssertTrue(prompt.contains("<definition_of_done>"))
        XCTAssertTrue(prompt.contains("ACCEPTANCE EVIDENCE"))
        XCTAssertTrue(prompt.contains("LOOPFORGE_STATUS: BLOCKED"))
        XCTAssertTrue(prompt.contains("Use official Codex tools normally"))
        XCTAssertTrue(prompt.contains("Write actual workspace files"))
        XCTAssertTrue(prompt.contains("not shown in the latest evidence bundle"))
        XCTAssertTrue(prompt.contains("publisher account"))
    }

    func testVisualPromptRequiresRunningProductScreenshots() {
        let task = makeTask(request: "Build a polished macOS UI", quality: .high, category: .nativeApp)
        let prompt = PromptCompiler().initialPrompt(for: task)
        XCTAssertTrue(prompt.contains("Launch the real UI"))
        XCTAssertTrue(prompt.contains(".loopforge/evidence/iteration-2/"))
        XCTAssertTrue(prompt.contains("asset images or design mockups do not count"))
    }

    func testBrowserAutomationPromptPreservesSignedInSurfaceAndRejectsAPISubstitution() {
        let task = makeTask(
            request: "Use my already signed-in Google Chrome window to open 10 windows and generate 10 images in ChatGPT.",
            quality: .lightweight,
            category: .desktopAutomation
        )
        let prompt = PromptCompiler().initialPrompt(for: task)

        XCTAssertTrue(prompt.contains("<project_type>Browser / Desktop Automation</project_type>"))
        XCTAssertTrue(prompt.contains("current signed-in session"))
        XCTAssertTrue(prompt.contains("Never request or synthesize an API key"))
        XCTAssertTrue(prompt.contains("do not invent a model such as GPT-3.5"))
        XCTAssertTrue(prompt.contains("Creating code is optional and never substitutes"))
        XCTAssertTrue(prompt.contains("Save every requested downloaded or generated result into the selected workspace"))
        XCTAssertFalse(prompt.contains("three mechanically distinct concepts"))
    }

    func testOfficialControlUsesVerbatimGoalWithoutLocalRewritePipeline() {
        var task = makeTask(
            request: "Use the exact user wording",
            quality: .lightweight,
            category: .library
        )
        task.refinedRequest = "Stale local rewrite"
        task.missionRewriteAuditSummary = "Stale local audit"
        task.controlAgent = .codex(
            model: AppConstants.officialWorkerModel,
            displayName: "GPT-5.6 Sol",
            reasoning: "ultra",
            access: .fullAccess
        )

        let prompt = PromptCompiler().initialPrompt(for: task)

        XCTAssertTrue(prompt.contains("<original_goal>Use the exact user wording</original_goal>"))
        XCTAssertTrue(prompt.contains("mode=\"not-required-for-codex\""))
        XCTAssertFalse(prompt.contains("Stale local rewrite"))
        XCTAssertFalse(prompt.contains("Stale local audit"))
    }

    func testDiagnosisPromptEnforcesReadOnlyProductBoundary() {
        let task = makeTask(request: "Diagnose why tests are flaky; do not fix them", quality: .medium, category: .maintenance)
        let prompt = PromptCompiler().initialPrompt(for: task)

        XCTAssertTrue(prompt.contains("<task_mode>Diagnose only</task_mode>"))
        XCTAssertTrue(prompt.contains("Do not change product behavior"))
    }

    func testContinuationIncludesSpecificFindingsAndPrioritizedActions() {
        let task = makeTask(request: "Build a CLI", quality: .medium, category: .library)
        let audit = AuditResult(
            score: 45,
            passed: false,
            summary: "Missing proof",
            findings: ["No successful real verification command was captured"],
            nextActions: ["Run the CLI's real smoke path", "Add an invalid-input regression test"]
        )
        var snapshot = WorkspaceSnapshot()
        snapshot.sourceFiles = 2
        snapshot.samplePaths = ["Sources/main.swift", "README.md"]
        let prompt = PromptCompiler().continuationPrompt(for: task, audit: audit, snapshot: snapshot)

        XCTAssertTrue(prompt.contains("No successful real verification command was captured"))
        XCTAssertTrue(prompt.contains("1. Run the CLI's real smoke path"))
        XCTAssertTrue(prompt.contains("2. Add an invalid-input regression test"))
        XCTAssertTrue(prompt.contains("Sources/main.swift"))
    }

    private func makeTask(request: String, quality: QualityTier, category: TaskCategory) -> LoopTask {
        let now = Date()
        return LoopTask(
            id: UUID(), title: "Prompt", request: request, quality: quality, category: category,
            workspacePath: "/tmp/loopforge-prompt", targetSeconds: 600, accumulatedCodexSeconds: 120,
            model: .deepCoder, status: .running, stage: "", iteration: 1, threadID: "thread",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
    }
}
