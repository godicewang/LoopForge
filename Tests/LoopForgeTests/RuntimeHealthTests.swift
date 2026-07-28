import XCTest
@testable import LoopForge

final class RuntimeHealthTests: XCTestCase {
    func testTerminalCompletionReclaimsOnlyAfterProtocolTerminalSignal() async throws {
        let watchdog = CodexTurnWatchdog(
            policy: CodexTurnWatchdogPolicy(
                startupSilenceSeconds: 5,
                semanticIdleSeconds: 5,
                transportRecoverySeconds: 5
            ),
            terminalExitGraceSeconds: 0.05
        )
        let runner = ProcessRunner()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
            watchdog.noteTerminalCompletion()
        }
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", "sleep 5"],
                watchdog: watchdog,
                onStdout: { _ in },
                onStderr: { _ in }
            )
            XCTFail("Expected terminal cleanup watchdog to reclaim the child")
        } catch ProcessRunnerError.stalled(let reason) {
            XCTAssertTrue(reason.contains("turn.completed"))
        }

        let nonTerminalWatchdog = CodexTurnWatchdog(
            policy: CodexTurnWatchdogPolicy(
                startupSilenceSeconds: 0.05,
                semanticIdleSeconds: 5,
                transportRecoverySeconds: 5
            ),
            terminalExitGraceSeconds: 0.01
        )
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", "sleep 5"],
                watchdog: nonTerminalWatchdog
            )
            XCTFail("Expected ordinary startup watchdog")
        } catch ProcessRunnerError.stalled(let reason) {
            XCTAssertFalse(reason.contains("turn.completed"))
        }
    }
    func testProductPolicyIntervenesAfterThirtyMinutesWithoutSemanticHeartbeat() {
        let now = Date()
        let task = LoopTask(
            id: UUID(), title: "Signal policy", request: "Build", quality: .medium, category: .script,
            workspacePath: "/tmp", targetSeconds: 1, accumulatedCodexSeconds: 0,
            model: .visualAuditor, status: .running, stage: "", iteration: 0, threadID: nil,
            auditScore: 0, auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
        let policy = CodexTurnWatchdogPolicy.policy(for: task)
        XCTAssertEqual(policy.semanticIdleSeconds, 30 * 60)
        XCTAssertLessThan(policy.transportRecoverySeconds, policy.semanticIdleSeconds)
    }

    func testRepeatedReconnectMessagesDoNotSlideTheRecoveryDeadline() async throws {
        let expired = expectation(description: "transport watchdog expired")
        let watchdog = CodexTurnWatchdog(policy: CodexTurnWatchdogPolicy(
            startupSilenceSeconds: 2,
            semanticIdleSeconds: 2,
            transportRecoverySeconds: 0.08
        ))
        watchdog.arm { reason in
            XCTAssertTrue(reason.contains("transport"))
            expired.fulfill()
        }
        watchdog.noteTransportDegraded("Reconnecting... 1/5")
        try await Task.sleep(nanoseconds: 40_000_000)
        watchdog.noteTransportDegraded("Reconnecting... 2/5")
        await fulfillment(of: [expired], timeout: 0.4)
    }

    func testProductiveEventCancelsTransportRecoveryAndAllowsLongCommand() async throws {
        let unexpectedlyExpired = expectation(description: "must not expire")
        unexpectedlyExpired.isInverted = true
        let watchdog = CodexTurnWatchdog(policy: CodexTurnWatchdogPolicy(
            startupSilenceSeconds: 0.6,
            semanticIdleSeconds: 0.6,
            transportRecoverySeconds: 0.3
        ))
        watchdog.arm { _ in unexpectedlyExpired.fulfill() }
        watchdog.noteTransportDegraded("Reconnecting... 1/5")
        try await Task.sleep(nanoseconds: 20_000_000)
        watchdog.noteProductiveActivity()
        await fulfillment(of: [unexpectedlyExpired], timeout: 0.18)
        watchdog.disarm()
    }

    func testProcessRunnerEndsAStalledProcessThroughTheWatchdog() async throws {
        let watchdog = CodexTurnWatchdog(policy: CodexTurnWatchdogPolicy(
            startupSilenceSeconds: 0.08,
            semanticIdleSeconds: 1,
            transportRecoverySeconds: 1
        ))
        let started = Date()
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"],
                watchdog: watchdog
            )
            XCTFail("Expected semantic startup deadline.")
        } catch ProcessRunnerError.stalled(let reason) {
            XCTAssertTrue(reason.contains("startup"))
            XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testActiveWorkTrackerExcludesTransportDowntime() async throws {
        let tracker = ActiveWorkDurationTracker()
        try await Task.sleep(nanoseconds: 30_000_000)
        tracker.setEligible(false)
        let beforeDowntime = tracker.elapsed()
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterDowntime = tracker.elapsed()
        XCTAssertEqual(afterDowntime, beforeDowntime, accuracy: 0.015)
        tracker.setEligible(true)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertGreaterThan(tracker.elapsed(), afterDowntime + 0.015)
    }

    func testRuntimeSignalSeparatesTransportFromOrdinaryDiagnostics() {
        XCTAssertEqual(
            CodexRuntimeSignal.classify(message: "Reconnecting... 2/5 (stream disconnected before completion: websocket closed by server before response.completed)"),
            .transportDegraded("Reconnecting... 2/5 (stream disconnected before completion: websocket closed by server before response.completed)")
        )
        XCTAssertEqual(
            CodexRuntimeSignal.classify(message: "model metadata refreshed"),
            .diagnostic
        )
    }
}
