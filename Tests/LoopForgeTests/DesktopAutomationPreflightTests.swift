import XCTest
@testable import LoopForge

final class DesktopAutomationPreflightTests: XCTestCase {
    func testChromeJavaScriptChannelPassesAndPreservesExactSession() {
        let result = DesktopAutomationPreflight.assessChrome(DesktopAutomationProbeFacts(
            targetApplicationRunning: true,
            targetWindowAvailable: true,
            chromeJavaScriptAvailable: true,
            accessibilityUIAvailable: false,
            chromeProbeDetail: "CHROME_JS_OK:ChatGPT"
        ))

        XCTAssertTrue(result.ready)
        XCTAssertTrue(result.workerContext.contains("existing signed-in Google Chrome"))
        XCTAssertTrue(result.workerContext.contains("Do not request an API key"))
        XCTAssertTrue(result.workerContext.contains("do not switch to GPT-3.5"))
        XCTAssertTrue(result.workerContext.contains("do not substitute Selenium"))
    }

    func testAccessibilityChannelPassesWhenChromeJavaScriptIsDisabled() {
        let result = DesktopAutomationPreflight.assessChrome(DesktopAutomationProbeFacts(
            targetApplicationRunning: true,
            targetWindowAvailable: true,
            chromeJavaScriptAvailable: false,
            accessibilityUIAvailable: true,
            chromeProbeDetail: "Executing JavaScript through AppleScript is turned off."
        ))

        XCTAssertTrue(result.ready)
        XCTAssertTrue(result.summary.contains("Accessibility"))
    }

    func testMissingChromeControlBlocksBeforeRuntime() {
        let result = DesktopAutomationPreflight.assessChrome(DesktopAutomationProbeFacts(
            targetApplicationRunning: true,
            targetWindowAvailable: true,
            chromeJavaScriptAvailable: false,
            accessibilityUIAvailable: false,
            chromeProbeDetail: "Executing JavaScript through AppleScript is turned off."
        ))

        XCTAssertFalse(result.ready)
        XCTAssertTrue(result.summary.contains("Allow JavaScript from Apple Events"))
        XCTAssertTrue(result.summary.contains("timer has not started"))
        XCTAssertFalse(result.summary.localizedCaseInsensitiveContains("API key"))
    }

    func testClosedChromeRequiresTheExactSignedInProfile() {
        let result = DesktopAutomationPreflight.assessChrome(DesktopAutomationProbeFacts(
            targetApplicationRunning: false,
            targetWindowAvailable: false,
            chromeJavaScriptAvailable: false,
            accessibilityUIAvailable: false,
            chromeProbeDetail: "Google Chrome is not running."
        ))

        XCTAssertFalse(result.ready)
        XCTAssertTrue(result.summary.contains("signed-in profile"))
        XCTAssertTrue(result.summary.contains("timer has not started"))
    }
}
