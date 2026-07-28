import XCTest
@testable import LoopForge

final class CodexCapabilitiesTests: XCTestCase {
    func testShortLivedProcessClosesItsOutputPipes() async throws {
        let result = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["ready"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ready")
    }

    func testLiveCatalogKeepsVisibleModelsInPriorityOrder() throws {
        let json = #"""
        {"models":[
          {"slug":"hidden","display_name":"Hidden","description":"x","supported_reasoning_levels":[{"effort":"high","description":"High"}],"visibility":"hide","priority":0},
          {"slug":"gpt-new","display_name":"GPT New","description":"new","supported_reasoning_levels":[{"effort":"low","description":"Low"},{"effort":"max","description":"Max"},{"effort":"ultra","description":"Ultra"}],"visibility":"list","priority":1},
          {"slug":"gpt-fast","display_name":"GPT Fast","description":"fast","supported_reasoning_levels":[{"effort":"low","description":"Low"},{"effort":"high","description":"High"}],"visibility":"list","priority":2}
        ]}
        """#

        let models = try CodexCatalog.decode(Data(json.utf8))
        XCTAssertEqual(models.map(\.slug), ["gpt-new", "gpt-fast"])
        XCTAssertEqual(CodexCatalog.recommendedModel(in: models).slug, "gpt-new")
        XCTAssertEqual(CodexCatalog.strongestReasoning(for: models[0]), "ultra")
        XCTAssertEqual(CodexCatalog.strongestReasoning(for: models[1]), "high")
    }

    func testResolvedLatestCodexWinsEvenIfCatalogPriorityIsStale() {
        let stale = CodexModelOption(
            slug: "gpt-older",
            displayName: "Older",
            description: "",
            supportedReasoningLevels: [CodexReasoningOption(effort: "high", description: "")],
            visibility: "list",
            priority: 0
        )
        XCTAssertEqual(
            CodexCatalog.recommendedModel(in: [stale, .fallback]).slug,
            AppConstants.officialWorkerModel
        )
    }

    func testSelectedCodexCapabilitiesDriveFullAccessArguments() {
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Capabilities", request: "Build it", quality: .high, category: .nativeApp,
            workspacePath: "/tmp/loopforge-capabilities", targetSeconds: 43_200, accumulatedCodexSeconds: 0,
            model: .visualAuditor, status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [],
            officialModel: "gpt-new", officialReasoningEffort: "ultra", codexAccessMode: .fullAccess
        )

        let initial = CodexRunner().initialArguments(task: task)
        XCTAssertTrue(initial.contains("gpt-new"))
        XCTAssertTrue(initial.contains("model_reasoning_effort=\"ultra\""))
        XCTAssertTrue(initial.contains("danger-full-access"))
        XCTAssertTrue(initial.contains("approval_policy=\"never\""))

        var resumed = task
        resumed.threadID = "thread"
        let continuation = CodexRunner().resumeArguments(task: resumed)
        XCTAssertTrue(continuation.contains("sandbox_mode=\"danger-full-access\""))
        XCTAssertTrue(continuation.contains("gpt-new"))
    }
}
