import XCTest
@testable import LoopForge

final class EstimatorTests: XCTestCase {
    func testPublicQualityNamesAndDefaultRuntimes() {
        XCTAssertEqual(QualityTier.allCases.map(\.title), ["Lightweight", "Normal", "Enhanced", "Ultra"])
        XCTAssertEqual(QualityTier.allCases.map(\.defaultRuntimeMinutes), [60, 120, 300, 600])
    }

    func testQualityRaisesTimeAndRoutesModel() {
        let estimator = TaskEstimator()
        let request = "做一个完整的 macOS 应用，包含登录、数据库、同步、自动化测试和打包"
        let low = estimator.estimate(request: request, quality: .low, physicalMemory: 48 * 1_073_741_824)
        let high = estimator.estimate(request: request, quality: .high, physicalMemory: 48 * 1_073_741_824)

        XCTAssertEqual(high.category, .nativeApp)
        XCTAssertGreaterThan(high.recommendedSeconds, low.recommendedSeconds)
        XCTAssertEqual(high.model, .advancedVisualAuditor)
        XCTAssertTrue(high.visualAuditRequired)
    }

    func testWebProductWithMacOSLauncherIsStillClassifiedAsWeb() {
        let request = """
        Build a local-first web application with a Python backend and a
        dependency-free HTML/CSS/JavaScript frontend. Include a double-clickable
        macOS launcher that opens the product in a normal browser.
        """

        XCTAssertEqual(TaskEstimator().classify(request.lowercased()), .web)
    }

    func testExistingSignedInChromeTaskIsAutomationNotGameOrAPIWork() {
        let request = """
        帮我在当前已经打开并登录 GPT 账号的 Google 浏览器中打开10个新窗口，
        分别输入提示词生成10张武侠 RPG gameplay 照片并保存到当前文件夹。
        """
        let estimate = TaskEstimator().estimate(
            request: request,
            quality: .lightweight,
            physicalMemory: 48 * 1_073_741_824
        )

        XCTAssertEqual(estimate.category, .desktopAutomation)
        XCTAssertTrue(estimate.category.prefersOfficialControlAgent)
        XCTAssertTrue(estimate.visualAuditRequired)
        XCTAssertNotEqual(estimate.category, .game)
    }

    func testTargetMacGetsAdvancedVisualSupervisorWithUserVisibleResourceLimits() {
        let model = ModelProfile.advancedVisualAuditor
        XCTAssertEqual(model.ollamaName, "qwen3.6:35b")
        XCTAssertEqual(model.estimatedMemoryGB, 29)
        XCTAssertEqual(model.contextWindow, 65_536)
        XCTAssertEqual(model.maximumContextWindow, 262_144)
        XCTAssertTrue(model.supportsVision)
        XCTAssertTrue(model.resourceLabel.contains("29 GB"))
        XCTAssertTrue(ModelProfile.all.contains(.visualAuditor))
        XCTAssertEqual(ModelProfile.all.count, 5)
    }

    func testSmallMachineAlwaysUsesEcoModel() {
        let result = TaskEstimator().estimate(
            request: "建立复杂实验 baseline 并输出报告",
            quality: .high,
            physicalMemory: 16 * 1_073_741_824
        )
        XCTAssertEqual(result.model, .ecoCoder)
    }

    func testExperimentUsesReasoningModelOnTargetMac() {
        let result = TaskEstimator().estimate(
            request: "复现论文实验，建立 baseline，保存指标并做消融",
            quality: .medium,
            physicalMemory: 48 * 1_073_741_824
        )
        XCTAssertEqual(result.category, .experiment)
        XCTAssertEqual(result.model, .balancedAgent)
    }

    func testMediumCodingTaskUsesSpecializedCoderOnTargetMac() {
        let result = TaskEstimator().estimate(
            request: "创建一个 Python CLI 和完整单元测试",
            quality: .medium,
            physicalMemory: 48 * 1_073_741_824
        )
        XCTAssertEqual(result.category, .library)
        XCTAssertEqual(result.model, .deepCoder)
        XCTAssertEqual(result.model.contextWindow, 65_536)
    }

    func testExistingProjectRepairAndOptimizationAreFirstClassTasks() {
        let estimator = TaskEstimator()
        let repair = estimator.estimate(
            request: "修复现有 Swift 项目的偶发崩溃并补齐回归测试",
            quality: .medium,
            physicalMemory: 48 * 1_073_741_824
        )
        let optimization = estimator.estimate(
            request: "提升程序运行效率，降低内存和延迟，并提供 benchmark",
            quality: .high,
            physicalMemory: 48 * 1_073_741_824
        )
        XCTAssertEqual(repair.category, .maintenance)
        XCTAssertEqual(optimization.category, .optimization)
        XCTAssertEqual(repair.model, .deepCoder)
        XCTAssertEqual(optimization.model, .deepCoder)
        XCTAssertGreaterThan(optimization.recommendedSeconds, repair.recommendedSeconds)

        let quickRepair = estimator.estimate(
            request: "修复一个小 bug",
            quality: .low,
            physicalMemory: 48 * 1_073_741_824
        )
        XCTAssertEqual(quickRepair.category, .maintenance)
        XCTAssertEqual(quickRepair.model, .ecoCoder)
    }

    func testEnglishSmallWorkspaceRepairUsesMaintenanceScaleEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "def total(x): return x".write(
            to: directory.appendingPathComponent("invoice.py"), atomically: true, encoding: .utf8
        )
        try "# Run tests".write(
            to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
        )

        let result = TaskEstimator().estimate(
            request: "Fix the invoice defect, add regression tests, and explain the root cause",
            quality: .medium,
            physicalMemory: 48 * 1_073_741_824,
            workspacePath: directory.path
        )

        XCTAssertEqual(result.category, .maintenance)
        XCTAssertEqual(result.model, .deepCoder)
        XCTAssertGreaterThanOrEqual(result.recommendedSeconds, 5 * 60 * 60)
        XCTAssertLessThanOrEqual(result.recommendedSeconds, 6 * 60 * 60)
        XCTAssertTrue(result.explanation.contains("2 project files"))
    }

    func testAuthorizationDistinguishesReadOnlyDiagnosisFromRepair() {
        let estimator = TaskEstimator()
        XCTAssertEqual(estimator.inferAuthorization("diagnose why the server crashes; do not change code"), .diagnosis)
        XCTAssertEqual(estimator.inferAuthorization("diagnose and fix the server crash"), .buildOrModify)
        XCTAssertEqual(estimator.inferAuthorization("audit this repository and report findings only"), .audit)
    }

    func testResearchRoutesToBalancedReasoningModel() {
        let estimate = TaskEstimator().estimate(
            request: "Research three database options and deliver an evidence-backed report",
            quality: .medium,
            physicalMemory: 48 * 1_073_741_824
        )
        XCTAssertEqual(estimate.category, .research)
        XCTAssertEqual(estimate.authorization, .research)
        XCTAssertEqual(estimate.model, .balancedAgent)
    }

    func testTerminalControlSequencesAreRemovedFromLogs() {
        let raw = "\u{001B}[?2026h\u{001B}[1Gpulling model 42%\u{001B}[K\u{001B}[?2026l\r"
        XCTAssertEqual(sanitizedLogText(raw), "pulling model 42%")
    }

    func testAPISecretsAreRedactedFromProviderErrorsAndLogs() {
        let secret = "sk-test_abcdefghijklmnopqrstuvwxyz123456"
        let sanitized = sanitizedLogText(
            #"HTTP 401 {"api_key":"\#(secret)","detail":"Authorization: Bearer \#(secret)"}"#
        )
        XCTAssertFalse(sanitized.contains(secret))
        XCTAssertTrue(sanitized.contains("[REDACTED"))
    }

    func testHarmlessLocalModelTelemetryNoiseIsHidden() {
        XCTAssertTrue(shouldIgnoreCodexStderr("warn codex_otel::events::session_telemetry: metrics failed"))
        XCTAssertTrue(shouldIgnoreCodexStderr("model_verbosity is set but ignored"))
        XCTAssertFalse(shouldIgnoreCodexStderr("error: tool execution failed"))
    }

    func testRetryableCodexTransportDiagnosticsAreNotPresentedAsActionBlockers() {
        XCTAssertEqual(
            codexPresentationKind(
                for: "Reconnecting... 1/5 (stream disconnected before completion: network error)",
                fallback: .error
            ),
            .system
        )
        XCTAssertEqual(
            codexPresentationKind(
                for: "ERROR codex_models_manager::manager: failed to refresh available models: timeout waiting for child process to exit",
                fallback: .error
            ),
            .system
        )
        XCTAssertEqual(
            codexPresentationKind(
                for: "ERROR codex_api::endpoint::responses_websocket: failed to connect to websocket: tls handshake eof",
                fallback: .error
            ),
            .system
        )
        XCTAssertEqual(
            codexPresentationKind(
                for: "Falling back from WebSockets to HTTPS transport. stream disconnected before completion",
                fallback: .error
            ),
            .system
        )
        XCTAssertEqual(
            codexPresentationKind(for: "error: tool execution failed", fallback: .error),
            .error
        )
        XCTAssertEqual(
            codexPresentationKind(for: "You've hit your usage limit", fallback: .error),
            .error
        )
    }

    func testCompletionGateRequiresBothHardTimeAndAudit() {
        XCTAssertFalse(CompletionGate.shouldComplete(accumulated: 59, target: 60, auditPassed: true))
        XCTAssertFalse(CompletionGate.shouldComplete(accumulated: 600, target: 60, auditPassed: false))
        XCTAssertTrue(CompletionGate.shouldComplete(accumulated: 60, target: 60, auditPassed: true))
    }

    func testOnlyNormalOfficialTurnsRemainOnTheRuntimeLedger() {
        XCTAssertEqual(
            ActiveRuntimeLedger.completionAdjustment(reportedTurnSeconds: 47, checkpointedSeconds: 30, exitCode: 0),
            17
        )
        XCTAssertEqual(
            ActiveRuntimeLedger.completionAdjustment(reportedTurnSeconds: 47, checkpointedSeconds: 30, exitCode: 1),
            -30
        )
    }

    func testSuccessfulSigningProbeCanVerifyExternalPublisherBlocker() {
        let message = """
        App Store submission needs an Apple Distribution certificate and publisher-controlled App Store Connect access.
        LOOPFORGE_STATUS: BLOCKED
        """
        let logs = [
            TaskLogEntry(
                kind: .command,
                message: "security find-identity -v -p codesigning\n0 valid identities found\nexit code 0"
            )
        ]
        XCTAssertTrue(ExternalBlockerPolicy.isVerified(agentMessage: message, recentLogs: logs, commandFailures: 0))
    }

    func testUnsupportedBlockerClaimStillRequiresCommandEvidence() {
        let message = "Apple Distribution may be difficult. LOOPFORGE_STATUS: BLOCKED"
        XCTAssertFalse(ExternalBlockerPolicy.isVerified(agentMessage: message, recentLogs: [], commandFailures: 0))
    }

    func testOfficialCodexUsageLimitExitIsClassifiedWithoutAgentMarker() throws {
        let assessment = try XCTUnwrap(ExternalBlockerPolicy.classifyProcessFailure(
            "You've hit your usage limit. Purchase more credits or try again at Jul 29th, 2026 1:28 AM."
        ))
        XCTAssertEqual(assessment.kind, .usageLimit)
        XCTAssertTrue(assessment.summary.contains("usage limit"))
        XCTAssertFalse(assessment.summary.contains("infrastructure failures"))
        let retry = try XCTUnwrap(assessment.retryAfter)
        XCTAssertEqual(Calendar.current.component(.year, from: retry), 2026)
        XCTAssertEqual(Calendar.current.component(.day, from: retry), 29)
    }

    func testOrdinaryWebSocketFailureRemainsRetryableInfrastructure() {
        XCTAssertNil(ExternalBlockerPolicy.classifyProcessFailure("WebSocket closed while compacting the turn"))
        XCTAssertEqual(InfrastructureRetryPolicy.delaySeconds(afterFailureCount: 1), 4)
        XCTAssertEqual(InfrastructureRetryPolicy.delaySeconds(afterFailureCount: 2), 8)
        XCTAssertTrue(InfrastructureRetryPolicy.shouldStartFreshSession(afterFailureCount: 2))
        XCTAssertEqual(InfrastructureRetryPolicy.maximumAutomaticFailures, 5)
    }

    func testLocalModelFallbackRequiresTwoUnchangedAudits() {
        XCTAssertNil(ModelFallbackPolicy.replacement(for: .deepCoder, unchangedAuditTransitions: 1))
        XCTAssertEqual(
            ModelFallbackPolicy.replacement(for: .deepCoder, unchangedAuditTransitions: 2),
            .efficientAgent
        )
    }

    func testCodexExecUsesSupportedNonInteractiveApprovalConfig() {
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Args", request: "x", quality: .low, category: .script,
            workspacePath: "/tmp/loopforge-args", targetSeconds: 60, accumulatedCodexSeconds: 0,
            model: .ecoCoder, status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        let arguments = CodexRunner().initialArguments(task: task)
        XCTAssertFalse(arguments.contains("--ask-for-approval"))
        XCTAssertTrue(arguments.contains("approval_policy=\"never\""))
        XCTAssertTrue(arguments.contains(AppConstants.officialWorkerModel))
        XCTAssertTrue(arguments.contains("--ignore-user-config"))
        XCTAssertFalse(arguments.contains("--oss"))
        XCTAssertFalse(arguments.contains("--local-provider"))
        XCTAssertTrue(arguments.contains("model_reasoning_effort=\"low\""))
        XCTAssertTrue(arguments.contains("plugins"))

        var resumedTask = task
        resumedTask.threadID = "019f0000-0000-7000-8000-000000000000"
        let resumeArguments = CodexRunner().resumeArguments(task: resumedTask)
        XCTAssertTrue(resumeArguments.contains(AppConstants.officialWorkerModel))
        XCTAssertTrue(resumeArguments.contains("sandbox_mode=\"workspace-write\""))
        XCTAssertFalse(resumeArguments.contains("model_provider=\"ollama\""))
        XCTAssertFalse(resumeArguments.contains("--color"))
    }

    func testFullAccessVisualCodexTurnLoadsInstalledHostTools() {
        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Visual QA", request: "Launch the real UI in a browser and capture screenshots",
            quality: .medium, category: .web,
            workspacePath: "/tmp/loopforge-visual-args", targetSeconds: 60, accumulatedCodexSeconds: 0,
            model: .ecoCoder, status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        task.subAgent = AgentSelection.codex(
            model: AppConstants.officialWorkerModel,
            displayName: "Codex",
            reasoning: "ultra",
            access: .fullAccess
        )

        let arguments = CodexRunner().initialArguments(task: task)
        XCTAssertTrue(arguments.contains("--enable"))
        XCTAssertTrue(arguments.contains("plugins"))
        XCTAssertFalse(arguments.contains("--ignore-user-config"))
        XCTAssertFalse(arguments.contains("--disable"))
    }

    func testHostToolingPolicyDistinguishesCodeFromRealGUIWork() {
        XCTAssertFalse(CodexHostToolingPolicy.objectiveRequiresInstalledTools(
            "Implement and unit test the persistence layer.",
            category: .web
        ))
        XCTAssertTrue(CodexHostToolingPolicy.objectiveRequiresInstalledTools(
            "Launch the real browser and retain screenshots.",
            category: .web
        ))
        XCTAssertTrue(CodexHostToolingPolicy.objectiveRequiresInstalledTools(
            "Complete the assigned workflow.",
            category: .desktopAutomation
        ))
    }

    func testAutoGraphCodexTurnDisablesHiddenNestedFanout() {
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Graph node", request: "Implement one bounded node.",
            quality: .medium, category: .web,
            workspacePath: "/tmp/loopforge-graph-args", targetSeconds: 0,
            accumulatedCodexSeconds: 0, model: .ecoCoder, status: .preparing,
            stage: "", iteration: 0, threadID: nil, auditScore: 0,
            auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [],
            executionMode: .autoGraph
        )

        let arguments = CodexRunner().initialArguments(task: task)
        for feature in ["multi_agent", "multi_agent_v2", "enable_fanout"] {
            XCTAssertTrue(arguments.contains(feature))
            let featureIndex = try? XCTUnwrap(arguments.firstIndex(of: feature))
            if let featureIndex {
                XCTAssertEqual(arguments[featureIndex - 1], "--disable")
            }
        }
    }

    func testVisualDetectionDoesNotMistakeBuildForUI() {
        let estimator = TaskEstimator()
        XCTAssertFalse(estimator.requiresVisualAudit(request: "Build a command-line parser", category: .library))
        XCTAssertTrue(estimator.requiresVisualAudit(request: "Polish the UI and capture screenshots", category: .maintenance))
    }

    func testCodexResumeAttachesFreshScreenshotEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let screenshot = directory.appendingPathComponent("screen.png")
        try Data("image".utf8).write(to: screenshot)
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Visual", request: "Fix UI", quality: .medium, category: .nativeApp,
            workspacePath: directory.path, targetSeconds: 60, accumulatedCodexSeconds: 0,
            model: .visualAuditor, status: .running, stage: "", iteration: 1, threadID: "thread-id",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        let arguments = CodexRunner().resumeArguments(task: task, imagePaths: [screenshot.path])
        let imageIndex = try XCTUnwrap(arguments.firstIndex(of: "--image"))
        XCTAssertEqual(arguments[imageIndex + 1], screenshot.path)
        XCTAssertLessThan(imageIndex, try XCTUnwrap(arguments.firstIndex(of: "thread-id")))
    }
}
