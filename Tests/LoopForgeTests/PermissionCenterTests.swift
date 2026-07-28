import Foundation
import XCTest
@testable import LoopForge

@MainActor
final class PermissionCenterTests: XCTestCase {
    func testMissingAutomationPermissionsNeverCreateAnUnescapableGate() {
        let defaults = isolatedDefaults()
        let center = PermissionCenter(
            defaults: defaults,
            probe: PermissionProbe(screenCaptureGranted: { false }, accessibilityGranted: { false })
        )

        XCTAssertFalse(center.visualAutomationReady)
        XCTAssertFalse(center.isReady)

        center.continueIntoApp()
        XCTAssertTrue(center.isReady)
        XCTAssertTrue(center.onboardingDismissed)

        let restored = PermissionCenter(
            defaults: defaults,
            probe: PermissionProbe(screenCaptureGranted: { false }, accessibilityGranted: { false })
        )
        XCTAssertTrue(restored.isReady)
        restored.showOnboardingAgain()
        XCTAssertFalse(restored.isReady)
    }

    func testAlreadyGrantedCapabilitiesEnterAutomatically() {
        let defaults = isolatedDefaults()
        let center = PermissionCenter(
            defaults: defaults,
            probe: PermissionProbe(screenCaptureGranted: { true }, accessibilityGranted: { true })
        )

        XCTAssertTrue(center.visualAutomationReady)
        XCTAssertFalse(center.appManagementConfirmed)
        XCTAssertFalse(center.allCapabilitiesGranted)
        XCTAssertTrue(center.isReady)
    }

    func testRefreshUsesLivePermissionStateInsteadOfStickyHistoricalGrant() {
        let defaults = isolatedDefaults()
        let state = PermissionStateBox()
        state.screen = true
        state.accessibility = true
        let center = PermissionCenter(
            defaults: defaults,
            probe: PermissionProbe(
                screenCaptureGranted: { state.screen },
                accessibilityGranted: { state.accessibility }
            )
        )
        XCTAssertTrue(center.visualAutomationReady)

        state.screen = false
        state.accessibility = false
        center.refresh()
        XCTAssertFalse(center.screenCaptureGranted)
        XCTAssertFalse(center.accessibilityGranted)
        XCTAssertFalse(center.visualAutomationReady)
    }

    func testFullAccessRequestsOnlyTaskRelevantCapabilities() {
        var task = makeTask(category: .maintenance, request: "Repair the parser")
        task.subAgent = .codex(model: "gpt-5.6-sol", displayName: "Codex", reasoning: "high", access: .fullAccess)
        XCTAssertEqual(
            TaskPermissionRequirements.requirements(for: task),
            TaskPermissionRequirements(accessibility: false, screenCapture: false, photoLibrary: false)
        )

        task = makeTask(category: .desktopAutomation, request: "Use Chrome to create ten images")
        task.subAgent = .codex(model: "gpt-5.6-sol", displayName: "Codex", reasoning: "high", access: .fullAccess)
        XCTAssertEqual(
            TaskPermissionRequirements.requirements(for: task),
            TaskPermissionRequirements(accessibility: true, screenCapture: true, photoLibrary: false)
        )

        task = makeTask(category: .desktopAutomation, request: "Import the selected result into the system Photos app")
        task.subAgent = .codex(model: "gpt-5.6-sol", displayName: "Codex", reasoning: "high", access: .fullAccess)
        XCTAssertTrue(TaskPermissionRequirements.requirements(for: task).photoLibrary)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "LoopForgeTests.PermissionCenter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeTask(category: TaskCategory, request: String) -> LoopTask {
        let now = Date()
        return LoopTask(
            id: UUID(), title: "Permissions", request: request, quality: .lightweight,
            category: category, workspacePath: FileManager.default.temporaryDirectory.path,
            targetSeconds: 3_600, accumulatedCodexSeconds: 0, model: .advancedVisualAuditor,
            status: .paused, stage: "Ready", iteration: 0, threadID: nil, auditScore: 0,
            auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
    }
}

private final class PermissionStateBox {
    var screen = false
    var accessibility = false
}
