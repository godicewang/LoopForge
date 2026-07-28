import AppKit
import Foundation

struct DesktopAutomationProbeFacts: Equatable {
    let targetApplicationRunning: Bool
    let targetWindowAvailable: Bool
    let chromeJavaScriptAvailable: Bool
    let accessibilityUIAvailable: Bool
    let chromeProbeDetail: String
}

struct DesktopAutomationReadiness: Equatable {
    let ready: Bool
    let summary: String
    let workerContext: String
}

/// Verifies that the selected official worker can reach the exact interactive
/// surface requested by the user before any hard-runtime seconds can accrue.
///
/// This is intentionally a capability probe, not an alternate implementation:
/// a missing browser bridge must never be silently replaced by an API, WebDriver,
/// a different model, or a newly generated automation project.
struct DesktopAutomationPreflight {
    private let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    @MainActor
    func check(task: LoopTask) async -> DesktopAutomationReadiness {
        guard task.category == .desktopAutomation else {
            return DesktopAutomationReadiness(
                ready: true,
                summary: "No interactive desktop preflight is required.",
                workerContext: ""
            )
        }

        let request = task.request.lowercased()
        let targetsChrome = request.contains("chrome")
            || request.contains("google浏览器")
            || request.contains("谷歌浏览器")
            || request.contains("谷歌 chrome")

        if targetsChrome {
            return await checkChrome()
        }

        let accessibility = await accessibilityUIProbe()
        return Self.assessGeneric(accessibilityUIAvailable: accessibility.available, detail: accessibility.detail)
    }

    static func assessChrome(_ facts: DesktopAutomationProbeFacts) -> DesktopAutomationReadiness {
        guard facts.targetApplicationRunning else {
            return DesktopAutomationReadiness(
                ready: false,
                summary: "Open Google Chrome with the signed-in profile requested by this task, then resume. The hard runtime timer has not started.",
                workerContext: ""
            )
        }
        guard facts.targetWindowAvailable else {
            return DesktopAutomationReadiness(
                ready: false,
                summary: "Open a Google Chrome window in the signed-in profile, then resume. The hard runtime timer has not started.",
                workerContext: ""
            )
        }

        if facts.chromeJavaScriptAvailable {
            return DesktopAutomationReadiness(
                ready: true,
                summary: "Existing Google Chrome session verified through direct Apple Events control.",
                workerContext: """
                <desktop_automation_preflight verified="true">
                The existing signed-in Google Chrome window is reachable through Apple Events JavaScript.
                Operate that exact browser session. Do not request an API key, do not switch to GPT-3.5,
                and do not substitute Selenium, WebDriver, or a generated automation project.
                </desktop_automation_preflight>
                """
            )
        }

        if facts.accessibilityUIAvailable {
            return DesktopAutomationReadiness(
                ready: true,
                summary: "Existing Google Chrome session verified through macOS Accessibility UI control.",
                workerContext: """
                <desktop_automation_preflight verified="true">
                The existing signed-in Google Chrome window is reachable through macOS Accessibility UI scripting.
                Operate that exact browser session. Do not request an API key, do not switch to GPT-3.5,
                and do not substitute Selenium, WebDriver, or a generated automation project.
                </desktop_automation_preflight>
                """
            )
        }

        let detail = facts.chromeProbeDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = detail.isEmpty ? "" : " Probe: \(String(sanitizedLogText(detail).prefix(180)))"
        return DesktopAutomationReadiness(
            ready: false,
            summary: "Chrome control is not enabled. In Google Chrome choose View › Developer › Allow JavaScript from Apple Events, then resume. Alternatively grant LoopForge Accessibility access in System Settings › Privacy & Security › Accessibility. The hard runtime timer has not started.\(suffix)",
            workerContext: ""
        )
    }

    static func assessGeneric(accessibilityUIAvailable: Bool, detail: String) -> DesktopAutomationReadiness {
        if accessibilityUIAvailable {
            return DesktopAutomationReadiness(
                ready: true,
                summary: "macOS Accessibility UI control verified for the requested interactive task.",
                workerContext: """
                <desktop_automation_preflight verified="true">
                Direct macOS Accessibility UI scripting is available. Preserve the exact user-selected app,
                account, session, and interaction surface. Do not silently replace it with an API, WebDriver,
                different model, or generated automation project.
                </desktop_automation_preflight>
                """
            )
        }
        let cleanDetail = String(sanitizedLogText(detail).prefix(180))
        return DesktopAutomationReadiness(
            ready: false,
            summary: "Direct UI control is unavailable. Grant LoopForge Accessibility access in System Settings › Privacy & Security › Accessibility, reopen the target app, then resume. The hard runtime timer has not started.\(cleanDetail.isEmpty ? "" : " Probe: \(cleanDetail)")",
            workerContext: ""
        )
    }

    @MainActor
    private func checkChrome() async -> DesktopAutomationReadiness {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.google.Chrome"
        }
        guard running else {
            return Self.assessChrome(DesktopAutomationProbeFacts(
                targetApplicationRunning: false,
                targetWindowAvailable: false,
                chromeJavaScriptAvailable: false,
                accessibilityUIAvailable: false,
                chromeProbeDetail: "Google Chrome is not running."
            ))
        }

        let script = """
        tell application "Google Chrome"
            if not running then return "CHROME_NOT_RUNNING"
            if (count of windows) is 0 then return "CHROME_NO_WINDOW"
            set currentTitle to execute active tab of front window javascript "document.title"
            return "CHROME_JS_OK:" & currentTitle
        end tell
        """
        let javascriptProbe = await runAppleScript(script)
        let combined = [javascriptProbe.stdout, javascriptProbe.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let noWindow = combined.contains("CHROME_NO_WINDOW")
        let javascriptAvailable = javascriptProbe.exitCode == 0 && combined.contains("CHROME_JS_OK:")
        let accessibility = await accessibilityUIProbe()

        return Self.assessChrome(DesktopAutomationProbeFacts(
            targetApplicationRunning: true,
            targetWindowAvailable: !noWindow,
            chromeJavaScriptAvailable: javascriptAvailable,
            accessibilityUIAvailable: accessibility.available,
            chromeProbeDetail: combined
        ))
    }

    private func accessibilityUIProbe() async -> (available: Bool, detail: String) {
        let result = await runAppleScript(
            #"tell application "System Events" to return UI elements enabled"#
        )
        let combined = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (result.exitCode == 0 && combined.lowercased().contains("true"), combined)
    }

    private func runAppleScript(_ script: String) async -> ProcessResult {
        do {
            return try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script]
            )
        } catch {
            return ProcessResult(
                exitCode: -1,
                elapsed: 0,
                stdout: "",
                stderr: sanitizedLogText(error.localizedDescription)
            )
        }
    }
}
