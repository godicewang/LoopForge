import AppKit
import ApplicationServices
import Foundation

struct PermissionPromptCandidate: Equatable {
    let applicationName: String
    let windowText: String
    let buttonTitle: String
}

enum PermissionPromptPolicy {
    private static let approvalButtons = [
        "allow", "ok", "continue", "open system settings",
        "允许", "好", "继续", "打开系统设置"
    ]
    private static let permissionSignals = [
        "would like to access", "wants to access", "requests access",
        "screen recording", "screen & system audio", "record your screen",
        "photos", "photo library", "camera", "microphone", "local network",
        "bluetooth", "accessibility", "control this computer", "control other applications",
        "想要访问", "请求访问", "文件与文件夹", "录屏", "屏幕录制",
        "屏幕与系统音频", "照片", "相册", "摄像头", "相机", "麦克风",
        "本地网络", "蓝牙", "辅助功能", "控制这台电脑", "控制其他应用"
    ]
    private static let forbiddenSignals = [
        "password", "passcode", "touch id", "administrator", "admin privileges",
        "terms of service", "license agreement", "eula", "purchase", "payment",
        "subscribe", "delete", "erase", "format", "security key", "recovery key",
        "密码", "触控 id", "管理员", "条款", "协议", "许可协议", "购买",
        "付款", "订阅", "删除", "抹掉", "格式化", "恢复密钥"
    ]

    static func shouldApprove(_ candidate: PermissionPromptCandidate, fullAccess: Bool) -> Bool {
        guard fullAccess else { return false }
        let button = candidate.buttonTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard approvalButtons.contains(button) else { return false }
        let context = candidate.windowText.lowercased()
        guard permissionSignals.contains(where: context.contains) else { return false }
        return !forbiddenSignals.contains(where: context.contains)
    }

    static func permissionFamily(in text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("screen") || lower.contains("录屏") || lower.contains("屏幕") { return "Screen Recording" }
        if lower.contains("photo") || lower.contains("照片") || lower.contains("相册") { return "Photos" }
        if lower.contains("camera") || lower.contains("相机") || lower.contains("摄像头") { return "Camera" }
        if lower.contains("microphone") || lower.contains("麦克风") { return "Microphone" }
        if lower.contains("accessibility") || lower.contains("辅助功能") { return "Accessibility" }
        if lower.contains("file") || lower.contains("文件") || lower.contains("folder") || lower.contains("文件夹") { return "Files & Folders" }
        return "System permission"
    }
}

enum PermissionPromptScanPolicy {
    static let interval: TimeInterval = 4
    static let timerTolerance: TimeInterval = 1

    static func shouldInspect(
        activationPolicy: NSApplication.ActivationPolicy,
        isActive: Bool
    ) -> Bool {
        // Permission sheets belong to foreground-capable applications. Scanning
        // every accessory/background process traversed thousands of AX nodes
        // every 1.25 seconds during Full Access Graph runs.
        isActive || activationPolicy == .regular
    }
}

/// Safely presses ordinary Allow/OK permission buttons during a Full Access
/// task. It never toggles TCC settings, enters credentials, accepts legal or
/// payment terms, selects arbitrary files, or bypasses a secure system prompt.
@MainActor
final class SystemPermissionAutomator {
    private var timer: Timer?
    private var loggedCandidates = Set<String>()
    private var onAction: ((String) -> Void)?

    func start(fullAccess: Bool, onAction: @escaping (String) -> Void) {
        stop()
        guard fullAccess, AXIsProcessTrusted() else { return }
        self.onAction = onAction
        scan()
        let scheduled = Timer.scheduledTimer(
            withTimeInterval: PermissionPromptScanPolicy.interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        scheduled.tolerance = PermissionPromptScanPolicy.timerTolerance
        timer = scheduled
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onAction = nil
        loggedCandidates.removeAll()
    }

    private func scan() {
        guard AXIsProcessTrusted() else { stop(); return }
        for application in NSWorkspace.shared.runningApplications where application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            guard PermissionPromptScanPolicy.shouldInspect(
                activationPolicy: application.activationPolicy,
                isActive: application.isActive
            ) else { continue }
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = values(of: kAXWindowsAttribute, in: appElement) else { continue }
            for window in windows.prefix(2) {
                let nodes = descendants(of: window, remainingDepth: 4, remainingNodes: 64)
                let context = nodes.compactMap(textValue).joined(separator: " ")
                guard !context.isEmpty else { continue }
                for button in nodes where role(of: button) == kAXButtonRole as String {
                    guard let title = textValue(button), !title.isEmpty else { continue }
                    let candidate = PermissionPromptCandidate(
                        applicationName: application.localizedName ?? application.bundleIdentifier ?? "macOS",
                        windowText: context,
                        buttonTitle: title
                    )
                    guard PermissionPromptPolicy.shouldApprove(candidate, fullAccess: true) else { continue }
                    let key = "\(application.processIdentifier)|\(title)|\(PermissionPromptPolicy.permissionFamily(in: context))"
                    guard loggedCandidates.insert(key).inserted else { continue }
                    let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
                    if result == .success {
                        onAction?("Full Access approved a required \(PermissionPromptPolicy.permissionFamily(in: context)) prompt in \(candidate.applicationName).")
                    }
                }
            }
        }
    }

    private func values(of attribute: String, in element: AXUIElement) -> [AXUIElement]? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? [AXUIElement]
    }

    private func descendants(of root: AXUIElement, remainingDepth: Int, remainingNodes: Int) -> [AXUIElement] {
        guard remainingDepth > 0, remainingNodes > 0 else { return [root] }
        var result = [root]
        guard let children = values(of: kAXChildrenAttribute, in: root) else { return result }
        for child in children {
            guard result.count < remainingNodes else { break }
            result.append(contentsOf: descendants(
                of: child,
                remainingDepth: remainingDepth - 1,
                remainingNodes: remainingNodes - result.count
            ))
        }
        return result
    }

    private func role(of element: AXUIElement) -> String? {
        stringAttribute(kAXRoleAttribute, of: element)
    }

    private func textValue(_ element: AXUIElement) -> String? {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            if let value = stringAttribute(attribute, of: element), !value.isEmpty { return value }
        }
        return nil
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}
