import Foundation
import XCTest
@testable import LoopForge

final class LocalSupervisorTests: XCTestCase {
    func testMissionRewriteSelectionRequiresIndependentSemanticFidelity() {
        let candidates = [
            MissionRewriteCandidate(id: "coverage", rewrittenRequest: "Preserves all ten images in signed-in Chrome.", preservationNotes: []),
            MissionRewriteCandidate(id: "execution", rewrittenRequest: "Uses an API instead.", preservationNotes: []),
            MissionRewriteCandidate(id: "boundary", rewrittenRequest: "Preserves all ten images and exact browser.", preservationNotes: [])
        ]
        let audit = MissionRewriteAudit(
            assessments: [
                MissionCandidateAssessment(
                    id: "coverage", meaningPreserved: true, materialOmissions: [],
                    unauthorizedAdditions: [], contradictions: [], score: 0.94
                ),
                MissionCandidateAssessment(
                    id: "execution", meaningPreserved: false, materialOmissions: ["signed-in Chrome"],
                    unauthorizedAdditions: ["API"], contradictions: [], score: 0.40
                ),
                MissionCandidateAssessment(
                    id: "boundary", meaningPreserved: true, materialOmissions: [],
                    unauthorizedAdditions: [], contradictions: [], score: 0.97
                )
            ],
            recommendedCandidateID: "boundary",
            retryRequired: false,
            summary: "Boundary preserves every explicit constraint."
        )

        let selected = LocalSupervisor.bestConsistentCandidate(candidates: candidates, audit: audit)

        XCTAssertEqual(selected?.id, "boundary")
        XCTAssertNotEqual(selected?.id, "execution")
    }

    func testMissionRewriteSelectionRetriesWhenNoCandidatePasses() {
        let candidates = ["coverage", "execution", "boundary"].map {
            MissionRewriteCandidate(id: $0, rewrittenRequest: $0, preservationNotes: [])
        }
        let audit = MissionRewriteAudit(
            assessments: candidates.map {
                MissionCandidateAssessment(
                    id: $0.id, meaningPreserved: true, materialOmissions: [],
                    unauthorizedAdditions: [], contradictions: [], score: 0.89
                )
            },
            recommendedCandidateID: nil,
            retryRequired: true,
            summary: "Every candidate needs another rewrite."
        )

        XCTAssertNil(LocalSupervisor.bestConsistentCandidate(candidates: candidates, audit: audit))
    }

    func testCodexAndAPIControlAgentsBypassMissionRewriting() async {
        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Bypass", request: "Keep this exact request", quality: .low,
            category: .library, workspacePath: FileManager.default.currentDirectoryPath,
            targetSeconds: 1_800, accumulatedCodexSeconds: 0, model: .advancedVisualAuditor,
            status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [],
            refinedRequest: "A stale local rewrite that must be ignored"
        )
        task.controlAgent = .codex(
            model: AppConstants.officialWorkerModel,
            displayName: "GPT-5.6 Sol",
            reasoning: "ultra",
            access: .fullAccess
        )

        let codexResult = await LocalSupervisor().refineMission(for: task)

        XCTAssertEqual(codexResult.attempts, 0)
        XCTAssertEqual(codexResult.selectedRequest, task.request)
        XCTAssertEqual(task.effectiveRequest, task.request)

        let connection = APIModelConnection(
            id: UUID(), name: "Test API", baseURL: "https://example.invalid",
            model: "test-model", wireProtocol: .responses, reasoningOptions: [],
            contextWindow: 32_768, supportsVision: false
        )
        task.controlAgent = .api(connection: connection, reasoning: nil, access: .workspaceOnly)

        let apiResult = await LocalSupervisor().refineMission(for: task)

        XCTAssertEqual(apiResult.attempts, 0)
        XCTAssertEqual(apiResult.selectedRequest, task.request)
        XCTAssertEqual(task.effectiveRequest, task.request)
    }

    func testDecisionRendersAConcreteWorkerBrief() {
        let decision = SupervisorDecision(
            status: "continue",
            completionApproved: false,
            findings: ["The primary failure state has no screenshot."],
            nextInstruction: "Render the failure state, fix the clipped action, and capture it again.",
            verification: ["Run the UI harness at desktop and narrow widths."],
            visualPassed: false,
            visualSummary: "The primary screen is readable, but failure-state evidence is absent."
        )
        XCTAssertTrue(decision.workerBrief.contains("COMPLETION APPROVED: no"))
        XCTAssertTrue(decision.workerBrief.contains("fix the clipped action"))
        XCTAssertTrue(decision.workerBrief.contains("desktop and narrow widths"))
    }

    func testCompletionApprovalIsDeniedWhenRequirementCoverageIsMissing() {
        var decision = SupervisorDecision(
            status: "approve",
            completionApproved: true,
            findings: [],
            nextInstruction: "Deliver.",
            verification: ["Tests passed."],
            visualPassed: true,
            visualSummary: "Looks ready."
        )
        decision.requirementCoverage = ["Running-product primary visual state": "supported"]
        let evidence = AuditEvidence(
            text: "Evidence",
            screenshotPaths: [],
            visualInspection: nil,
            coverage: [
                EvidenceCoverageItem(requirement: "Running-product primary visual state", state: .candidate, evidence: ["main.png"]),
                EvidenceCoverageItem(requirement: "World exploration", state: .notObserved, evidence: [])
            ]
        )

        let validated = LocalSupervisor.enforcingCoverageForApproval(decision, evidence: evidence)
        XCTAssertFalse(validated.completionApproved)
        XCTAssertEqual(validated.status, "continue")
        XCTAssertTrue(validated.findings.contains { $0.contains("World exploration") })
    }

    func testCompletionApprovalAcceptsEvidencedExternalDependency() {
        var decision = SupervisorDecision(
            status: "approve",
            completionApproved: true,
            findings: [],
            nextInstruction: "Deliver the verified workspace and publisher handoff.",
            verification: ["Release build and store metadata validation passed."],
            visualPassed: true,
            visualSummary: "The supplied product states are visually acceptable."
        )
        decision.requirementCoverage = [
            "Release build": "supported",
            "App Store submission": "externally_blocked"
        ]
        decision.externalDependencies = [
            "The user must supply an Apple Distribution identity and App Store Connect account."
        ]
        decision.evidenceCitations = [
            "build/release.log: BUILD SUCCEEDED",
            "docs/APP_STORE_HANDOFF.md"
        ]
        let evidence = AuditEvidence(
            text: "Evidence",
            screenshotPaths: [],
            visualInspection: nil,
            coverage: [
                EvidenceCoverageItem(requirement: "Release build", state: .candidate, evidence: ["build/release.log"]),
                EvidenceCoverageItem(requirement: "App Store submission", state: .candidate, evidence: ["docs/APP_STORE_HANDOFF.md"])
            ]
        )

        let validated = LocalSupervisor.enforcingCoverageForApproval(decision, evidence: evidence)

        XCTAssertTrue(validated.completionApproved)
        XCTAssertEqual(validated.status, "approve")
    }

    func testCompletionApprovalIsDeniedWithoutConcreteCitation() {
        var decision = SupervisorDecision(
            status: "approve",
            completionApproved: true,
            findings: [],
            nextInstruction: "Deliver.",
            verification: ["Tests passed."],
            visualPassed: true,
            visualSummary: "Looks ready."
        )
        decision.requirementCoverage = ["Release build": "supported"]
        let evidence = AuditEvidence(
            text: "Evidence",
            screenshotPaths: [],
            visualInspection: nil,
            coverage: [
                EvidenceCoverageItem(requirement: "Release build", state: .candidate, evidence: ["build/release.log"])
            ]
        )

        let validated = LocalSupervisor.enforcingCoverageForApproval(decision, evidence: evidence)

        XCTAssertFalse(validated.completionApproved)
        XCTAssertTrue(validated.findings.contains { $0.contains("did not cite") })
    }

    func testDecisionDecoderAcceptsOneJSONEnvelopeWithTrailingProse() {
        let raw = """
        Audit result:
        ```json
        {
          "status": "continue",
          "completionApproved": false,
          "findings": ["A deterministic test is still failing."],
          "nextInstruction": "Fix the failing test and retain its exact output.",
          "verification": ["Run swift test."],
          "visualPassed": null,
          "visualSummary": null,
          "requirementCoverage": {"Build": "partial"},
          "externalDependencies": [],
          "evidenceCitations": ["Tests.log"],
          "confidence": 0.91,
          "gapKeys": ["test-failure"]
        }
        ```
        Continue only after verification.
        """

        let decision = LocalSupervisor.decodeDecision(from: raw)

        XCTAssertEqual(decision?.status, "continue")
        XCTAssertEqual(decision?.gapKeys, ["test-failure"])
        XCTAssertEqual(decision?.confidence, 0.91)
    }

    func testReviewPromptIsBoundedForSmallLocalModelContext() {
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Bounded", request: "Review the app", quality: .low,
            category: .nativeApp, workspacePath: "/tmp/loopforge-bounded",
            targetSeconds: 2 * 60 * 60, accumulatedCodexSeconds: 0,
            model: .visualAuditor, status: .auditing, stage: "", iteration: 1, threadID: "thread",
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        let evidence = AuditEvidence(
            text: "EVIDENCE_HEAD" + String(repeating: "x", count: 100_000) + "EVIDENCE_TAIL",
            screenshotPaths: [],
            visualInspection: nil,
            coverage: [
                EvidenceCoverageItem(
                    requirement: "World exploration",
                    state: .notObserved,
                    evidence: []
                )
            ]
        )
        let prompt = LocalSupervisor.reviewUserMessage(
            task: task,
            deterministicBrief: "BRIEF_HEAD" + String(repeating: "y", count: 40_000) + "BRIEF_TAIL",
            phase: String(repeating: "phase", count: 1_000),
            evidence: evidence
        )
        XCTAssertLessThan(prompt.count, 30_000)
        XCTAssertTrue(prompt.contains("BRIEF_HEAD"))
        XCTAssertTrue(prompt.contains("BRIEF_TAIL"))
        XCTAssertTrue(prompt.contains("EVIDENCE_HEAD"))
        XCTAssertTrue(prompt.contains("EVIDENCE_TAIL"))
        XCTAssertTrue(prompt.contains("characters omitted"))
        XCTAssertTrue(prompt.contains("World exploration"))
        XCTAssertTrue(prompt.contains("not observed in attached evidence"))
    }

    func testRealQwen3VLReviewThroughProductPathWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LOOPFORGE_RUN_LOCAL_MODEL_TESTS"] == "1",
              let screenshot = environment["LOOPFORGE_VISUAL_FIXTURE"],
              FileManager.default.fileExists(atPath: screenshot) else {
            throw XCTSkip("Set LOOPFORGE_RUN_LOCAL_MODEL_TESTS=1 and LOOPFORGE_VISUAL_FIXTURE to run the real local VLM integration test.")
        }
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Visual integration", request: "Verify the project-entry UI", quality: .medium,
            category: .nativeApp, workspacePath: FileManager.default.currentDirectoryPath,
            targetSeconds: 6 * 60 * 60, accumulatedCodexSeconds: 120,
            model: .visualAuditor, status: .auditing, stage: "", iteration: 1, threadID: "integration",
            auditScore: 60, auditSummary: "Visual decision pending", lastAgentMessage: "Stage complete",
            consecutiveFailures: 0, createdAt: now, updatedAt: now, completedAt: nil, logs: [],
            visualAuditRequired: true
        )
        let evidence = AuditEvidence(
            text: "The deterministic scan requires a fresh visual decision. The screenshot should visibly contain both an existing-project and a new-project choice.",
            screenshotPaths: [screenshot],
            visualInspection: VisualInspection(passedBasicIntegrity: true, summary: "Usable 2560x1600 PNG", recognizedText: [])
        )
        let decision = try await LocalSupervisor().review(
            task: task,
            deterministicBrief: "Continue until the original goal, visual gate, and hard runtime all pass.",
            phase: "Real local VLM integration test",
            evidence: evidence
        )
        XCTAssertFalse(decision.completionApproved)
        XCTAssertNotNil(decision.visualPassed)
        XCTAssertFalse((decision.visualSummary ?? "").isEmpty)
        XCTAssertFalse(decision.nextInstruction.isEmpty)
    }

    func testRealLocalProjectIdentityWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LOOPFORGE_RUN_LOCAL_MODEL_TESTS"] == "1" else {
            throw XCTSkip("Set LOOPFORGE_RUN_LOCAL_MODEL_TESTS=1 to run the real local naming integration test.")
        }
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Temporary", request: "Build a refined macOS app that automatically supervises official Codex until verified delivery.",
            quality: .medium, category: .nativeApp, workspacePath: FileManager.default.currentDirectoryPath,
            targetSeconds: 18_000, accumulatedCodexSeconds: 0, model: .visualAuditor,
            status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        let identity = try await LocalSupervisor().projectIdentity(for: task)
        XCTAssertGreaterThanOrEqual(identity.displayName.count, 2)
        XCTAssertGreaterThanOrEqual(identity.shortName.count, 2)
        XCTAssertLessThanOrEqual(identity.shortName.count, 5)
        XCTAssertEqual(identity.shortName, identity.shortName.uppercased())
    }

    func testRealCodexControlPreservesExistingChromeSessionWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LOOPFORGE_RUN_BROWSER_ROUTING_TESTS"] == "1" else {
            throw XCTSkip("Set LOOPFORGE_RUN_BROWSER_ROUTING_TESTS=1 to run the real official-Codex browser-routing review.")
        }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/browser-ten-wuxia-images.txt")
        let request = try String(contentsOf: fixture, encoding: .utf8)
        let estimate = TaskEstimator().estimate(
            request: request,
            quality: .lightweight,
            physicalMemory: 48 * 1_073_741_824
        )
        XCTAssertEqual(estimate.category, .desktopAutomation)

        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Chrome Ten Images", request: request, quality: .lightweight,
            category: estimate.category, workspacePath: FileManager.default.temporaryDirectory.path,
            targetSeconds: 3_600, accumulatedCodexSeconds: 0, model: .advancedVisualAuditor,
            status: .auditing, stage: "", iteration: 0, threadID: nil, auditScore: 0,
            auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: [],
            visualAuditRequired: true
        )
        task.controlAgent = .codex(
            model: AppConstants.officialWorkerModel,
            displayName: "GPT-5.6-Sol",
            reasoning: "ultra",
            access: .fullAccess
        )
        task.subAgent = task.controlAgent

        let evidence = AuditEvidence(
            text: """
            The user explicitly requires the already signed-in Google Chrome session.
            No API key was requested or supplied. No direct Chrome-control capability
            has yet been verified. The selected workspace currently contains no result images.
            """,
            screenshotPaths: [],
            visualInspection: nil,
            coverage: [
                EvidenceCoverageItem(
                    requirement: "Requested browser result assets",
                    state: .notObserved,
                    evidence: []
                ),
                EvidenceCoverageItem(
                    requirement: "Direct target-surface verification",
                    state: .notObserved,
                    evidence: []
                )
            ]
        )
        let decision = try await LocalSupervisor().review(
            task: task,
            deterministicBrief: PromptCompiler().initialPrompt(for: task),
            phase: "Initial browser automation capability audit",
            evidence: evidence
        )
        let review = (
            decision.findings
            + [decision.nextInstruction]
            + decision.verification
            + (decision.externalDependencies ?? [])
        ).joined(separator: "\n").lowercased()

        XCTAssertTrue(review.contains("chrome") || review.contains("browser"))
        XCTAssertFalse(review.contains("gpt-3.5"))
        let instruction = decision.nextInstruction.lowercased()
        XCTAssertFalse(instruction.contains("provide an api key"))
        XCTAssertFalse(instruction.contains("enter an api key"))
        XCTAssertFalse(instruction.contains("configure an api key"))
        XCTAssertFalse(instruction.contains("request an api key"))
        XCTAssertFalse(instruction.contains("install selenium"))
        XCTAssertFalse(instruction.contains("create a selenium"))
        XCTAssertFalse(instruction.contains("use selenium instead"))
        XCTAssertFalse(instruction.contains("webdriver script"))
    }

    func testRealLocalParallelMissionRefinementPreservesComplexGoalWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LOOPFORGE_RUN_MISSION_REWRITE_TESTS"] == "1" else {
            throw XCTSkip("Set LOOPFORGE_RUN_MISSION_REWRITE_TESTS=1 to run the real local-model three-candidate mission-refinement audit.")
        }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/browser-ten-wuxia-images.txt")
        let request = try String(contentsOf: fixture, encoding: .utf8)
        let now = Date()
        var task = LoopTask(
            id: UUID(), title: "Mission refinement", request: request, quality: .lightweight,
            category: .desktopAutomation, workspacePath: FileManager.default.currentDirectoryPath,
            targetSeconds: 60 * 60, accumulatedCodexSeconds: 0,
            model: .advancedVisualAuditor, status: .preparing, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        task.controlAgent = .local(profile: .visualAuditor, access: .workspaceOnly)

        let result = await LocalSupervisor().refineMission(for: task)
        let selected = result.selectedRequest.lowercased()

        XCTAssertTrue((1...3).contains(result.attempts))
        if result.usedOriginalFallback {
            XCTAssertEqual(result.selectedRequest, request)
            XCTAssertNil(result.selectedCandidateID)
        } else {
            XCTAssertNotNil(result.selectedCandidateID)
        }
        XCTAssertTrue(selected.contains("10"))
        XCTAssertTrue(selected.contains("chrome"))
        XCTAssertTrue(selected.contains("gpt"))
        XCTAssertTrue(selected.contains("16:9"))
        XCTAssertFalse(result.auditSummary.isEmpty)
    }
}
