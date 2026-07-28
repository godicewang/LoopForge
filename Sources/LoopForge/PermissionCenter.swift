import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import Photos

struct PermissionProbe: @unchecked Sendable {
    let screenCaptureGranted: () -> Bool
    let accessibilityGranted: () -> Bool
    var photoLibraryStatus: () -> PHAuthorizationStatus = {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static let system = PermissionProbe(
        screenCaptureGranted: { CGPreflightScreenCaptureAccess() },
        accessibilityGranted: { AXIsProcessTrusted() },
        photoLibraryStatus: { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    )
}

struct TaskPermissionRequirements: Equatable {
    let accessibility: Bool
    let screenCapture: Bool
    let photoLibrary: Bool

    var isEmpty: Bool { !accessibility && !screenCapture && !photoLibrary }

    static func requirements(for task: LoopTask) -> TaskPermissionRequirements {
        guard task.workerAccessMode == .fullAccess else {
            return TaskPermissionRequirements(accessibility: false, screenCapture: false, photoLibrary: false)
        }
        let lower = task.request.lowercased()
        let photos = [
            "photo library", "photos app", "apple photos", "system photos",
            "照片图库", "系统相册", "苹果照片", "照片 app", "相册 app"
        ].contains(where: lower.contains)
        return TaskPermissionRequirements(
            // Only direct desktop-automation tasks require LoopForge itself to
            // drive another app through Accessibility. A Full Access coding
            // task still gives the selected agent unrestricted tools, but must
            // not be stranded by an ad-hoc LoopForge rebuild whose stale TCC
            // identity makes AXIsProcessTrusted() return false. Agent-provided
            // browser/computer-use bridges retain their own permission checks.
            accessibility: task.category == .desktopAutomation,
            screenCapture: task.category == .desktopAutomation,
            photoLibrary: photos
        )
    }
}

struct TaskPermissionReadiness: Equatable {
    let ready: Bool
    let summary: String
}

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var screenCaptureGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var photoLibraryStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var appManagementConfirmed = false
    @Published private(set) var isRequesting = false
    @Published private(set) var screenCaptureNeedsRestart = false
    @Published private(set) var screenCaptureRequested = false
    @Published private(set) var accessibilityRequested = false
    @Published private(set) var onboardingDismissed = false

    private let defaults: UserDefaults
    private let probe: PermissionProbe
    private var didBegin = false
    private let bypassed: Bool
    private let previewOnly: Bool

    init(defaults: UserDefaults = .standard, probe: PermissionProbe = .system) {
        self.defaults = defaults
        self.probe = probe
        self.bypassed = ProcessInfo.processInfo.environment["LOOPFORGE_SKIP_PERMISSION_ONBOARDING"] == "1"
        self.previewOnly = ProcessInfo.processInfo.environment["LOOPFORGE_PREVIEW_PERMISSION_ONBOARDING"] == "1"
        self.onboardingDismissed = defaults.bool(forKey: AppConstants.permissionOnboardingDismissedKey)
        refresh()
    }

    var visualAutomationReady: Bool {
        screenCaptureGranted && accessibilityGranted
    }

    var allCapabilitiesGranted: Bool {
        visualAutomationReady && appManagementConfirmed
    }

    var isReady: Bool {
        // App Management has no public preflight API. Requiring a local
        // "Enabled" acknowledgement here can strand someone whose System
        // Settings switch is already on, because LoopForge cannot verify it.
        // The two capabilities macOS can actually preflight are sufficient to
        // leave onboarding; App Management remains a non-blocking checklist
        // item and is checked again only when a task needs bundle mutation.
        bypassed || onboardingDismissed || visualAutomationReady
    }

    /// Called before Codex connection or model startup. Public macOS APIs allow
    /// proactive prompts for Screen Recording and Accessibility. App Management
    /// has a purpose string but no public preflight/request API, so the app opens
    /// the exact System Settings pane and asks the user to confirm the switch.
    func beginOnboarding() {
        guard !didBegin else { refresh(); return }
        didBegin = true
        refresh()
        guard !bypassed, !previewOnly else { return }
        isRequesting = true
        Task { [weak self] in
            guard let self else { return }
            if !screenCaptureGranted {
                screenCaptureRequested = true
                let granted = await Task.detached(priority: .userInitiated) {
                    CGRequestScreenCaptureAccess()
                }.value
                let live = probe.screenCaptureGranted()
                screenCaptureGranted = live
                screenCaptureNeedsRestart = granted && !live
            }
            if !accessibilityGranted {
                requestAccessibility()
            }
            isRequesting = false
            refresh()
        }
    }

    func refresh() {
        if bypassed {
            screenCaptureGranted = true
            accessibilityGranted = true
            appManagementConfirmed = true
            photoLibraryStatus = .authorized
            return
        }
        if previewOnly {
            screenCaptureGranted = false
            accessibilityGranted = false
            appManagementConfirmed = false
            photoLibraryStatus = .notDetermined
            return
        }
        screenCaptureGranted = probe.screenCaptureGranted()
        accessibilityGranted = probe.accessibilityGranted()
        photoLibraryStatus = probe.photoLibraryStatus()
        if screenCaptureGranted { screenCaptureNeedsRestart = false }
        appManagementConfirmed = defaults.bool(forKey: AppConstants.appManagementConfirmationKey)
        onboardingDismissed = defaults.bool(forKey: AppConstants.permissionOnboardingDismissedKey)
    }

    func requestScreenCapture() {
        screenCaptureRequested = true
        isRequesting = true
        Task { [weak self] in
            guard let self else { return }
            let granted = await Task.detached(priority: .userInitiated) {
                CGRequestScreenCaptureAccess()
            }.value
            let live = probe.screenCaptureGranted()
            screenCaptureGranted = live
            screenCaptureNeedsRestart = granted && !live
            isRequesting = false
            scheduleRefreshes()
        }
    }

    func requestAccessibility() {
        accessibilityRequested = true
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityGranted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        scheduleRefreshes()
    }

    func openScreenRecordingSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    func openAppManagementSettings() {
        openPrivacyPane(anchor: "Privacy_AppBundles")
    }

    func openPhotosSettings() {
        openPrivacyPane(anchor: "Privacy_Photos")
    }

    func requirementsSatisfied(for task: LoopTask) -> Bool {
        let requirements = TaskPermissionRequirements.requirements(for: task)
        let photosReady = photoLibraryStatus == .authorized || photoLibraryStatus == .limited
        return (!requirements.accessibility || accessibilityGranted)
            && (!requirements.screenCapture || screenCaptureGranted)
            && (!requirements.photoLibrary || photosReady)
    }

    /// Requests only the privacy capabilities this Full Access task actually
    /// needs. macOS remains authoritative: secure TCC toggles and credentials
    /// are never bypassed or fabricated.
    func prepareForTask(_ task: LoopTask) async -> TaskPermissionReadiness {
        let requirements = TaskPermissionRequirements.requirements(for: task)
        guard !requirements.isEmpty else {
            return TaskPermissionReadiness(ready: true, summary: "No additional macOS privacy capability is required.")
        }
        refresh()
        if requirements.screenCapture, !screenCaptureGranted {
            screenCaptureRequested = true
            isRequesting = true
            let granted = await Task.detached(priority: .userInitiated) {
                CGRequestScreenCaptureAccess()
            }.value
            let live = probe.screenCaptureGranted()
            screenCaptureGranted = live
            screenCaptureNeedsRestart = granted && !live
            isRequesting = false
        }
        if requirements.accessibility, !accessibilityGranted {
            requestAccessibility()
            // The system prompt is asynchronous. Give macOS a brief chance to
            // update TCC, then open the exact pane if the grant is still not
            // active. This also resolves the common local-build case where an
            // older LoopForge entry visibly remains On but its build-specific
            // ad-hoc identity is stale.
            try? await Task.sleep(nanoseconds: 700_000_000)
            refresh()
            if !accessibilityGranted { openAccessibilitySettings() }
        }
        if requirements.photoLibrary,
           photoLibraryStatus == .notDetermined {
            photoLibraryStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
        }
        refresh()
        guard !requirementsSatisfied(for: task) else {
            return TaskPermissionReadiness(
                ready: true,
                summary: "Full Access privacy preflight passed. Required permission prompts may be approved automatically while this task is active."
            )
        }
        var missing: [String] = []
        if requirements.accessibility, !accessibilityGranted { missing.append("Accessibility") }
        if requirements.screenCapture, !screenCaptureGranted { missing.append("Screen Recording") }
        if requirements.photoLibrary,
           photoLibraryStatus != .authorized,
           photoLibraryStatus != .limited { missing.append("Photos") }
        let recoveryHint = requirements.accessibility && !accessibilityGranted
            ? " If LoopForge already appears On in Accessibility, switch it Off and back On once to refresh this rebuilt copy."
            : ""
        return TaskPermissionReadiness(
            ready: false,
            summary: "Full Access is waiting for \(missing.joined(separator: ", ")). LoopForge opened or requested the exact macOS pane and will continue automatically after the system reports it granted.\(recoveryHint)"
        )
    }

    func confirmAppManagement() {
        defaults.set(true, forKey: AppConstants.appManagementConfirmationKey)
        appManagementConfirmed = true
    }

    /// Screen Recording and Accessibility improve visual and GUI verification,
    /// but must never trap the user outside LoopForge. In local ad-hoc builds,
    /// macOS ties TCC grants to a build-specific designated requirement, so a
    /// freshly rebuilt app can legitimately fail preflight even while an older
    /// LoopForge entry remains enabled in System Settings.
    func continueIntoApp() {
        defaults.set(true, forKey: AppConstants.permissionOnboardingDismissedKey)
        onboardingDismissed = true
    }

    func showOnboardingAgain() {
        defaults.set(false, forKey: AppConstants.permissionOnboardingDismissedKey)
        onboardingDismissed = false
        didBegin = false
        refresh()
    }

    func restartApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func scheduleRefreshes() {
        for delay in [1.0, 3.0, 8.0] {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.refresh()
            }
        }
    }

    private func openPrivacyPane(anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
