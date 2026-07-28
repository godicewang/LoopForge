import Foundation

protocol ProcessWatchdog: AnyObject {
    func arm(onExpiry: @escaping (String) -> Void)
    func disarm()
}

struct CodexTurnWatchdogPolicy: Equatable {
    let startupSilenceSeconds: TimeInterval
    let semanticIdleSeconds: TimeInterval
    let transportRecoverySeconds: TimeInterval

    static func policy(for task: LoopTask) -> CodexTurnWatchdogPolicy {
        let provider = task.resolvedSubAgent.provider
        let startup: TimeInterval
        switch provider {
        case .codex: startup = 15 * 60
        case .api: startup = 20 * 60
        case .local: startup = 30 * 60
        }
        return CodexTurnWatchdogPolicy(
            startupSilenceSeconds: startup,
            // LoopForge sleeps on the Sub Agent's event stream. Thirty minutes
            // without a semantic heartbeat is an intervention signal, not a
            // claim that the task failed. The outer loop then diagnoses the
            // retained process/evidence and reconstructs a turn if needed.
            semanticIdleSeconds: 30 * 60,
            transportRecoverySeconds: 8 * 60
        )
    }

    /// Watcher construction and wake reviews are bounded control-plane work,
    /// not multi-hour implementation turns. A provider that has already sent
    /// an opening message but then remains semantically silent for ten minutes
    /// should yield to the next configured provider instead of holding the
    /// resident scheduler for the general 30-minute loop threshold.
    static let continuumWatcher = CodexTurnWatchdogPolicy(
        startupSilenceSeconds: 6 * 60,
        semanticIdleSeconds: 10 * 60,
        transportRecoverySeconds: 4 * 60
    )
}

enum CodexRuntimeSignal: Equatable {
    case productive
    case transportDegraded(String)
    case terminalCompletion
    case diagnostic

    static func classify(message: String) -> CodexRuntimeSignal {
        let clean = sanitizedLogText(message)
        let lower = clean.lowercased()
        if isRetryableCodexTransportMessage(lower) {
            return .transportDegraded(clean)
        }
        if lower.contains("thread.started")
            || lower.contains("\"type\":\"agent_message\"")
            || lower.contains("\"type\": \"agent_message\"")
            || lower.contains("\"type\":\"command")
            || lower.contains("\"type\": \"command") {
            return .productive
        }
        return .diagnostic
    }
}

func isRetryableCodexTransportMessage(_ lowercasedText: String) -> Bool {
    lowercasedText.hasPrefix("reconnecting...")
        || lowercasedText.hasPrefix("falling back from websockets to https transport")
        || lowercasedText.contains("stream disconnected before completion")
        || lowercasedText.contains("websocket closed by server before response.completed")
        || lowercasedText.contains("responses_websocket: failed to connect to websocket")
}

/// A semantic watchdog for one official Codex turn.
///
/// Ordinary long-running commands receive a deliberately broad idle window.
/// Explicit transport degradation receives a shorter, non-sliding recovery
/// window: repeated reconnect messages do not keep an unhealthy turn alive.
final class CodexTurnWatchdog: ProcessWatchdog, @unchecked Sendable {
    private let lock = NSLock()
    private let policy: CodexTurnWatchdogPolicy
    private let queue: DispatchQueue
    private let onEligibilityChanged: (Bool, String) -> Void
    private var expiryHandler: ((String) -> Void)?
    private var pendingExpiry: DispatchWorkItem?
    private var transportDegraded = false
    private var armed = false
    private let terminalExitGraceSeconds: TimeInterval

    init(
        policy: CodexTurnWatchdogPolicy,
        queue: DispatchQueue = DispatchQueue(label: "com.loopforge.codex-turn-watchdog"),
        terminalExitGraceSeconds: TimeInterval = 8,
        onEligibilityChanged: @escaping (Bool, String) -> Void = { _, _ in }
    ) {
        self.policy = policy
        self.queue = queue
        self.terminalExitGraceSeconds = terminalExitGraceSeconds
        self.onEligibilityChanged = onEligibilityChanged
    }

    func arm(onExpiry: @escaping (String) -> Void) {
        lock.lock()
        armed = true
        expiryHandler = onExpiry
        scheduleLocked(
            after: policy.startupSilenceSeconds,
            reason: "Official Codex produced no semantic activity before the startup deadline."
        )
        lock.unlock()
    }

    func noteProductiveActivity() {
        var shouldResume = false
        lock.lock()
        guard armed else { lock.unlock(); return }
        if transportDegraded {
            transportDegraded = false
            shouldResume = true
        }
        scheduleLocked(
            after: policy.semanticIdleSeconds,
            reason: "Official Codex stopped producing semantic progress beyond the healthy long-command allowance."
        )
        lock.unlock()
        if shouldResume {
            onEligibilityChanged(true, "Official Codex transport recovered and productive work resumed.")
        }
    }

    func noteTransportDegraded(_ detail: String) {
        var shouldPause = false
        lock.lock()
        guard armed else { lock.unlock(); return }
        if !transportDegraded {
            transportDegraded = true
            shouldPause = true
            scheduleLocked(
                after: policy.transportRecoverySeconds,
                reason: "Official Codex transport did not recover within \(policy.transportRecoverySeconds.compactDuration)."
            )
        }
        lock.unlock()
        if shouldPause {
            onEligibilityChanged(false, detail)
        }
    }

    /// `turn.completed` is Codex's protocol-level terminal signal. If the CLI
    /// remains alive after this grace period, only its cleanup path is stuck;
    /// ProcessRunner may reclaim it without treating the finished turn as a
    /// failed or incomplete agent result.
    func noteTerminalCompletion() {
        lock.lock()
        guard armed else { lock.unlock(); return }
        transportDegraded = false
        scheduleLocked(
            after: terminalExitGraceSeconds,
            reason: "Official Codex emitted turn.completed but its CLI process did not exit within \(terminalExitGraceSeconds.compactDuration)."
        )
        lock.unlock()
    }

    func disarm() {
        lock.lock()
        armed = false
        pendingExpiry?.cancel()
        pendingExpiry = nil
        expiryHandler = nil
        transportDegraded = false
        lock.unlock()
    }

    private func scheduleLocked(after seconds: TimeInterval, reason: String) {
        pendingExpiry?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.armed else { self.lock.unlock(); return }
            let handler = self.expiryHandler
            self.armed = false
            self.pendingExpiry = nil
            self.lock.unlock()
            handler?(reason)
        }
        pendingExpiry = item
        queue.asyncAfter(deadline: .now() + max(0.01, seconds), execute: item)
    }
}

/// Records only intervals in which the official worker is eligible for the
/// user's hard runtime ledger. Network reconnect/fallback periods are excluded
/// even when the turn later succeeds.
final class ActiveWorkDurationTracker {
    private let lock = NSLock()
    private var eligible = true
    private var segmentStartedAt = Date()
    private var retained: TimeInterval = 0

    func setEligible(_ next: Bool, at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard eligible != next else { return }
        if eligible {
            retained += max(0, now.timeIntervalSince(segmentStartedAt))
        }
        eligible = next
        if next { segmentStartedAt = now }
    }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return retained + (eligible ? max(0, now.timeIntervalSince(segmentStartedAt)) : 0)
    }
}
