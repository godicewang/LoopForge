import AppKit
import XCTest
@testable import LoopForge

final class SystemPermissionAutomatorTests: XCTestCase {
    func testFullAccessApprovesOnlyTaskPermissionPrompt() {
        let candidate = PermissionPromptCandidate(
            applicationName: "Photos",
            windowText: "LoopForge would like to access your photo library.",
            buttonTitle: "Allow"
        )
        XCTAssertTrue(PermissionPromptPolicy.shouldApprove(candidate, fullAccess: true))
        XCTAssertFalse(PermissionPromptPolicy.shouldApprove(candidate, fullAccess: false))
    }

    func testPasswordOrLegalPromptIsNeverAutoApproved() {
        XCTAssertFalse(PermissionPromptPolicy.shouldApprove(
            PermissionPromptCandidate(
                applicationName: "SecurityAgent",
                windowText: "Enter your administrator password to allow Accessibility permission.",
                buttonTitle: "Allow"
            ),
            fullAccess: true
        ))
        XCTAssertFalse(PermissionPromptPolicy.shouldApprove(
            PermissionPromptCandidate(
                applicationName: "Installer",
                windowText: "Accept the license agreement and Terms of Service.",
                buttonTitle: "Continue"
            ),
            fullAccess: true
        ))
    }

    func testUnrelatedContinueButtonIsNeverAutoApproved() {
        XCTAssertFalse(PermissionPromptPolicy.shouldApprove(
            PermissionPromptCandidate(
                applicationName: "Game",
                windowText: "Continue to the next level.",
                buttonTitle: "Continue"
            ),
            fullAccess: true
        ))
    }

    func testPermissionScanSkipsBackgroundOnlyProcessesAndUsesCoalescedCadence() {
        XCTAssertTrue(PermissionPromptScanPolicy.shouldInspect(
            activationPolicy: .regular,
            isActive: false
        ))
        XCTAssertTrue(PermissionPromptScanPolicy.shouldInspect(
            activationPolicy: .accessory,
            isActive: true
        ))
        XCTAssertFalse(PermissionPromptScanPolicy.shouldInspect(
            activationPolicy: .accessory,
            isActive: false
        ))
        XCTAssertGreaterThanOrEqual(PermissionPromptScanPolicy.interval, 4)
        XCTAssertGreaterThan(PermissionPromptScanPolicy.timerTolerance, 0)
    }
}
