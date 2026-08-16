import AppKit
import Foundation
import XCTest
@testable import LoopForge

final class AuditorTests: XCTestCase {
    func testBrowserAutomationAcceptsExactDownloadedImageCountWithoutSourceProject() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 1...10 {
            try Data("image-\(index)".utf8).write(
                to: directory.appendingPathComponent(String(format: "%02d-scene.png", index))
            )
        }
        var task = makeTask(
            path: directory.path,
            quality: .lightweight,
            category: .desktopAutomation,
            request: "Use my signed-in Chrome session to generate 10 images and save all 10张 to this folder."
        )
        task.lastAgentMessage = "All ten browser results were saved and inspected. LOOPFORGE_STATUS: COMPLETE"
        task.visualAuditRequired = true
        task.visualAuditPassed = true

        let audit = WorkspaceAuditor().audit(task: task)

        XCTAssertTrue(audit.passed)
        XCTAssertFalse(audit.findings.contains { $0.contains("implementation") })
        XCTAssertFalse(audit.findings.contains { $0.contains("entry point") })
    }

    func testBrowserAutomationRejectsIncompleteDownloadedImageCount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 1...9 {
            try Data("image-\(index)".utf8).write(
                to: directory.appendingPathComponent(String(format: "%02d-scene.png", index))
            )
        }
        var task = makeTask(
            path: directory.path,
            quality: .lightweight,
            category: .desktopAutomation,
            request: "Generate 10 images in my current browser and save 10张."
        )
        task.lastAgentMessage = "LOOPFORGE_STATUS: COMPLETE"
        task.visualAuditRequired = true
        task.visualAuditPassed = true

        let audit = WorkspaceAuditor().audit(task: task)

        XCTAssertFalse(audit.passed)
        XCTAssertTrue(audit.findings.contains { $0.contains("10 downloaded or generated image") })
    }

    func testCompleteWorkspacePassesMediumAudit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Demo\nRun tests.".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "print('ok')".write(to: directory.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
        try "def test_ok(): assert True".write(to: directory.appendingPathComponent("test_app.py"), atomically: true, encoding: .utf8)
        try "[project]\nname='demo'".write(to: directory.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)

        var task = makeTask(path: directory.path, quality: .medium)
        task.lastAgentMessage = "All tests passed. LOOPFORGE_STATUS: COMPLETE"
        task.logs.append(TaskLogEntry(kind: .command, message: "pytest: 1 passed; exit code 0"))
        let result = WorkspaceAuditor().audit(task: task)

        XCTAssertTrue(result.passed)
        XCTAssertGreaterThanOrEqual(result.score, QualityTier.medium.completionThreshold)
    }

    func testAutoGraphAuditUsesNodeCompletionAndCommandEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Demo\nRun the complete suite.".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "print('ok')".write(
            to: directory.appendingPathComponent("app.py"),
            atomically: true,
            encoding: .utf8
        )
        try "def test_ok(): assert True".write(
            to: directory.appendingPathComponent("test_app.py"),
            atomically: true,
            encoding: .utf8
        )
        try "[project]\nname='demo'".write(
            to: directory.appendingPathComponent("pyproject.toml"),
            atomically: true,
            encoding: .utf8
        )

        let now = Date()
        let node = GraphLoopNode(
            id: "verify",
            title: "Verify project",
            objective: "Run the complete test suite.",
            dependencies: [],
            writeScopes: [],
            verification: ["pytest"],
            readOnly: true,
            status: .completed,
            iteration: 1,
            accumulatedActiveSeconds: 10,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: directory.path,
            isolationRootPath: nil,
            workspaceStrategy: .sharedReadOnly,
            integrationBaseCommit: nil,
            currentInstruction: "Verify project.",
            lastAgentMessage: "All retained checks passed. LOOPFORGE_STATUS: COMPLETE",
            lastReview: "Approved from exact command evidence.",
            consecutiveFailures: 0,
            createdAt: now,
            completedAt: now,
            logs: [
                TaskLogEntry(
                    kind: .command,
                    message: "pytest\n18 passed\nexit code 0",
                    timestamp: now
                )
            ]
        )
        var task = makeTask(path: directory.path, quality: .medium)
        task.executionMode = .autoGraph
        task.graphState = GraphLoopState(
            phase: .finalAudit,
            planSummary: "Verify the project.",
            nodes: [node],
            mainInteractionCount: 1,
            mainLastReview: "Approved.",
            maxConcurrentNodes: 3,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: now,
            completedAt: nil
        )

        let result = WorkspaceAuditor().audit(task: task)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.score, 100)
        XCTAssertFalse(result.findings.contains { $0.contains("completion declaration") })
        XCTAssertFalse(result.findings.contains { $0.contains("verification command") })
    }

    func testClaimWithoutArtifactsFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var task = makeTask(path: directory.path, quality: .low)
        task.lastAgentMessage = "LOOPFORGE_STATUS: COMPLETE"
        let result = WorkspaceAuditor().audit(task: task)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.findings.contains { $0.contains("implementation") })
    }

    func testDependencyFreePythonModuleEntryPointPassesLowAuditWithoutManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# CLI\nRun with `python -m demo`.".write(
            to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
        )
        try "print('ok')\nif __name__ == '__main__':\n    print('run')".write(
            to: directory.appendingPathComponent("demo.py"), atomically: true, encoding: .utf8
        )

        var task = makeTask(path: directory.path, quality: .low, category: .library)
        task.lastAgentMessage = "Verified the real command. LOOPFORGE_STATUS: COMPLETE"
        task.logs.append(TaskLogEntry(kind: .command, message: "python -m demo\nrun\nexit code 0"))

        let result = WorkspaceAuditor().audit(task: task)
        XCTAssertTrue(result.passed)
        XCTAssertFalse(result.findings.contains { $0.contains("entry point") })
    }

    func testXcodeProjectBundleCountsAsAReproducibleBuildManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = directory.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "// !$*UTF8*$!".write(
            to: project.appendingPathComponent("project.pbxproj"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = WorkspaceAuditor().snapshot(workspacePath: directory.path, logs: [])
        XCTAssertEqual(snapshot.manifestFiles, 1)
    }

    func testMediumCannotPassWithoutRealVerification() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Demo\nRun tests.".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "print('ok')".write(to: directory.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
        try "def test_ok(): assert True".write(to: directory.appendingPathComponent("test_app.py"), atomically: true, encoding: .utf8)
        try "[project]\nname='demo'".write(to: directory.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)

        var task = makeTask(path: directory.path, quality: .medium)
        task.lastAgentMessage = "LOOPFORGE_STATUS: COMPLETE"
        let result = WorkspaceAuditor().audit(task: task)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.findings.contains { $0.contains("verification command") })
    }

    func testLaterSuccessfulVerificationResolvesEarlierFailedAttempt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Demo\nRun tests.".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "print('ok')".write(to: directory.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
        try "def test_ok(): assert True".write(to: directory.appendingPathComponent("test_app.py"), atomically: true, encoding: .utf8)
        try "[project]\nname='demo'".write(to: directory.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)

        var task = makeTask(path: directory.path, quality: .medium)
        task.lastAgentMessage = "The repaired suite passed. LOOPFORGE_STATUS: COMPLETE"
        task.logs.append(TaskLogEntry(kind: .command, message: "pytest\n1 failed\nexit code 1"))
        task.logs.append(TaskLogEntry(kind: .command, message: "pytest\n4 passed\nexit code 0"))

        let snapshot = WorkspaceAuditor().snapshot(workspacePath: directory.path, logs: task.logs)
        XCTAssertEqual(snapshot.unresolvedVerificationFailures, 0)
        XCTAssertEqual(snapshot.lastVerificationSucceeded, true)
        XCTAssertTrue(WorkspaceAuditor().audit(task: task).passed)
    }

    func testDiagnosisCanPassWithoutModifyingProductSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Diagnosis\nRoot cause and reproduction evidence.".write(
            to: directory.appendingPathComponent("DIAGNOSIS.md"), atomically: true, encoding: .utf8
        )

        var task = makeTask(path: directory.path, quality: .low)
        task = LoopTask(
            id: task.id, title: task.title, request: "Diagnose why the service exits; do not fix it", quality: .low,
            category: .maintenance, workspacePath: task.workspacePath, targetSeconds: task.targetSeconds,
            accumulatedCodexSeconds: task.accumulatedCodexSeconds, model: task.model, status: task.status,
            stage: task.stage, iteration: task.iteration, threadID: task.threadID, auditScore: task.auditScore,
            auditSummary: task.auditSummary, lastAgentMessage: "Evidence recorded. LOOPFORGE_STATUS: COMPLETE",
            consecutiveFailures: task.consecutiveFailures, createdAt: task.createdAt, updatedAt: task.updatedAt,
            completedAt: task.completedAt,
            logs: [TaskLogEntry(kind: .command, message: "python3 -m unittest: 1 passed; exit code 0")]
        )

        XCTAssertTrue(WorkspaceAuditor().audit(task: task).passed)
    }

    func testOptimizationRequiresRetainedBeforeAfterEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# Optimizer\nRun the benchmark.".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "def optimize(x): return x".write(to: directory.appendingPathComponent("optimizer.py"), atomically: true, encoding: .utf8)
        try "def test_ok(): assert True".write(to: directory.appendingPathComponent("test_optimizer.py"), atomically: true, encoding: .utf8)
        try "[project]\nname='optimizer'".write(to: directory.appendingPathComponent("pyproject.toml"), atomically: true, encoding: .utf8)

        var task = makeTask(path: directory.path, quality: .high)
        task = LoopTask(
            id: task.id, title: task.title, request: "Optimize runtime and report a before/after benchmark", quality: .high,
            category: .optimization, workspacePath: task.workspacePath, targetSeconds: task.targetSeconds,
            accumulatedCodexSeconds: task.accumulatedCodexSeconds, model: task.model, status: task.status,
            stage: task.stage, iteration: task.iteration, threadID: task.threadID, auditScore: task.auditScore,
            auditSummary: task.auditSummary, lastAgentMessage: "LOOPFORGE_STATUS: COMPLETE",
            consecutiveFailures: task.consecutiveFailures, createdAt: task.createdAt, updatedAt: task.updatedAt,
            completedAt: task.completedAt,
            logs: [TaskLogEntry(kind: .command, message: "python3 -m unittest: 1 passed; exit code 0")]
        )

        let withoutResults = WorkspaceAuditor().audit(task: task)
        XCTAssertFalse(withoutResults.passed)
        XCTAssertTrue(withoutResults.findings.contains { $0.contains("retained result") })

        try "{\"before_seconds\": 1.0, \"after_seconds\": 0.2}".write(
            to: directory.appendingPathComponent("benchmark-results.json"), atomically: true, encoding: .utf8
        )
        XCTAssertTrue(WorkspaceAuditor().audit(task: task).passed)
    }

    func testVisualTaskRequiresHiddenEvidenceAndLocalApproval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let evidenceDirectory = directory.appendingPathComponent(".loopforge/evidence/iteration-1")
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "# App\nRun `swift test`.".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "@main struct Demo { static func main() { print(\"A rendered app\") } }".write(to: directory.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        try "import XCTest\nfinal class AppTests: XCTestCase { func testApp() { XCTAssertTrue(true) } }".write(to: directory.appendingPathComponent("AppTests.swift"), atomically: true, encoding: .utf8)
        try "// swift-tools-version: 6.0".write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Data("candidate".utf8).write(to: evidenceDirectory.appendingPathComponent("main-screen.png"))

        var task = makeTask(path: directory.path, quality: .medium, category: .nativeApp)
        task.visualAuditRequired = true
        task.lastAgentMessage = "The running UI was verified. LOOPFORGE_STATUS: COMPLETE"
        task.logs.append(TaskLogEntry(kind: .command, message: "swift test: 1 passed; exit code 0"))

        let pending = WorkspaceAuditor().audit(task: task)
        XCTAssertFalse(pending.passed)
        XCTAssertTrue(pending.findings.contains { $0.contains("visual supervisor") })
        XCTAssertEqual(WorkspaceAuditor().snapshot(workspacePath: directory.path, logs: []).screenshotFiles, 1)

        task.visualAuditPassed = true
        XCTAssertTrue(WorkspaceAuditor().audit(task: task).passed)
    }

    @MainActor
    func testEvidenceCollectorInspectsFreshScreenshotInsideHiddenFolder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var task = makeTask(path: directory.path, quality: .medium, category: .nativeApp)
        task.visualAuditRequired = true
        let collector = WorkspaceEvidenceCollector()
        let before = collector.fingerprint(workspacePath: directory.path)
        let evidenceDirectory = directory.appendingPathComponent(".loopforge/evidence/iteration-1")
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        let screenshot = evidenceDirectory.appendingPathComponent("primary.png")
        try makeTestScreenshot().write(to: screenshot)
        let audit = AuditResult(score: 40, passed: false, summary: "Pending", findings: [], nextActions: [])

        let evidence = await collector.collect(task: task, workerFeedback: "Rendered current UI", audit: audit, before: before)
        XCTAssertEqual(evidence.screenshotPaths.count, 1)
        XCTAssertTrue(evidence.screenshotPaths[0].hasSuffix("/.loopforge/evidence/iteration-1/primary.png"))
        XCTAssertEqual(evidence.visualInspection?.passedBasicIntegrity, true)
        XCTAssertTrue(evidence.text.contains("primary.png"))
    }

    @MainActor
    func testEvidenceCollectorReusesDigestAddressedImageInspection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        var task = makeTask(path: directory.path, quality: .medium, category: .nativeApp)
        task.visualAuditRequired = true
        let cache = HeavyEvidenceCache(rootDirectory: cacheDirectory)
        let collector = WorkspaceEvidenceCollector(heavyEvidenceCache: cache)
        let before = collector.fingerprint(workspacePath: directory.path)
        let evidenceDirectory = directory.appendingPathComponent(".loopforge/evidence/iteration-1")
        try FileManager.default.createDirectory(at: evidenceDirectory, withIntermediateDirectories: true)
        try makeTestScreenshot().write(to: evidenceDirectory.appendingPathComponent("primary.png"))
        let audit = AuditResult(score: 40, passed: false, summary: "Pending", findings: [], nextActions: [])

        let first = await collector.collect(
            task: task,
            workerFeedback: "Rendered current UI",
            audit: audit,
            before: before
        )
        let second = await collector.collect(
            task: task,
            workerFeedback: "Rendered current UI",
            audit: audit,
            before: before
        )
        let metrics = await cache.snapshotMetrics()

        XCTAssertTrue(first.visualInspection?.summary.contains("cache computed") == true)
        XCTAssertTrue(second.visualInspection?.summary.contains("cache memoryHit") == true)
        XCTAssertEqual(metrics.computationCount, 1)
        XCTAssertEqual(metrics.memoryHitCount, 1)
    }

    func testEvidenceCollectorReportsDeletedCodePaths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let removed = directory.appendingPathComponent("Removed.swift")
        try "struct Removed {}".write(to: removed, atomically: true, encoding: .utf8)
        let collector = WorkspaceEvidenceCollector()
        let before = collector.fingerprint(workspacePath: directory.path)
        try FileManager.default.removeItem(at: removed)
        let task = makeTask(path: directory.path, quality: .low)
        let audit = AuditResult(score: 20, passed: false, summary: "Pending", findings: [], nextActions: [])

        let evidence = await collector.collect(task: task, workerFeedback: "Removed obsolete code", audit: audit, before: before)
        XCTAssertTrue(evidence.text.contains("Deleted files: Removed.swift"))
    }

    @MainActor
    func testAuditorAndCollectorShareOneObservationWithoutRescanningNewBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "struct Initial {}".write(
            to: directory.appendingPathComponent("Initial.swift"),
            atomically: true,
            encoding: .utf8
        )
        let task = makeTask(path: directory.path, quality: .low)
        let auditor = WorkspaceAuditor()
        let observation = auditor.observe(task: task)
        XCTAssertEqual(observation.snapshot.sourceFiles, 1)
        XCTAssertNil(observation.repositoryIndexError)

        try "struct CreatedAfterObservation {}".write(
            to: directory.appendingPathComponent("CreatedAfterObservation.swift"),
            atomically: true,
            encoding: .utf8
        )
        let audit = auditor.audit(task: task, snapshot: observation.snapshot)
        let collector = WorkspaceEvidenceCollector()
        let shared = await collector.collect(
            task: task,
            workerFeedback: "Review the observed tree",
            audit: audit,
            before: [:],
            repositoryIndex: observation.repositoryIndex
        )
        let fresh = await collector.collect(
            task: task,
            workerFeedback: "Review a fresh tree",
            audit: audit,
            before: [:]
        )

        XCTAssertTrue(shared.text.contains("Repository index: sharedObservation"))
        XCTAssertTrue(shared.text.contains("Initial.swift"))
        XCTAssertFalse(shared.text.contains("CreatedAfterObservation.swift"))
        XCTAssertTrue(fresh.text.contains("Repository index: uncachedObservation"))
        XCTAssertTrue(fresh.text.contains("CreatedAfterObservation.swift"))
    }

    func testCommandEvidenceLedgerRetainsEarlySetupAndLateExitEvidence() {
        var logs: [TaskLogEntry] = [
            TaskLogEntry(kind: .command, message: "pwd\n/tmp/exact-workspace\nexit code 0")
        ]
        for index in 0..<45 {
            logs.append(TaskLogEntry(
                kind: .command,
                message: "probe-\(index)\nresult-\(index)\nexit code 0"
            ))
        }
        logs.append(TaskLogEntry(
            kind: .command,
            message: "python3.12 -m unittest\n42 tests passed\nexit code 0"
        ))

        let ledger = CommandEvidenceLedger.render(logs: logs)
        XCTAssertTrue(ledger.contains("/tmp/exact-workspace"))
        XCTAssertTrue(ledger.contains("42 tests passed"))
        XCTAssertTrue(ledger.contains("exit code 0"))
        XCTAssertFalse(ledger.contains("probe-8"))
    }

    @MainActor
    func testEvidenceCollectorKeepsEarlierRequirementStatesWhenOnlyOneNewScreenshotChanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = directory.appendingPathComponent(".loopforge/evidence/iteration-1")
        let second = directory.appendingPathComponent(".loopforge/evidence/iteration-2")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeTestScreenshot().write(to: first.appendingPathComponent("01-onboarding.png"))
        try makeTestScreenshot().write(to: first.appendingPathComponent("02-recruit-heroes.png"))
        try makeTestScreenshot().write(to: first.appendingPathComponent("03-world-map.png"))

        var task = makeTask(path: directory.path, quality: .medium, category: .game)
        task.visualAuditRequired = true
        let collector = WorkspaceEvidenceCollector()
        let before = collector.fingerprint(workspacePath: directory.path)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try makeTestScreenshot().write(to: second.appendingPathComponent("04-settlement.png"))
        let audit = AuditResult(score: 60, passed: false, summary: "Pending", findings: [], nextActions: [])

        let evidence = await collector.collect(task: task, workerFeedback: "Improved settlement", audit: audit, before: before)
        let names = evidence.screenshotPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
        XCTAssertTrue(names.contains("01-onboarding.png"))
        XCTAssertTrue(names.contains("02-recruit-heroes.png"))
        XCTAssertTrue(names.contains("03-world-map.png"))
        XCTAssertTrue(names.contains("04-settlement.png"))
        XCTAssertTrue(evidence.coverageText.contains("Onboarding or guided introduction"))
        XCTAssertTrue(evidence.coverageText.contains("World exploration or competitive play"))
    }

    @MainActor
    private func makeTestScreenshot() throws -> Data {
        let image = NSImage(size: NSSize(width: 640, height: 480))
        image.lockFocus()
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 640, height: 480).fill()
        NSColor(calibratedRed: 0.42, green: 0.32, blue: 0.96, alpha: 1).setFill()
        NSRect(x: 80, y: 110, width: 480, height: 240).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LoopForgeTests", code: 1)
        }
        return png
    }

    private func makeTask(
        path: String,
        quality: QualityTier,
        category: TaskCategory = .script,
        request: String = "build test"
    ) -> LoopTask {
        LoopTask(
            id: UUID(), title: "Test", request: request, quality: quality, category: category,
            workspacePath: path, targetSeconds: 60, accumulatedCodexSeconds: 60,
            model: .ecoCoder, status: .auditing, stage: "", iteration: 1, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: Date(), updatedAt: Date(), completedAt: nil, logs: []
        )
    }
}
