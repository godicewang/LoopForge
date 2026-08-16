import XCTest

@testable import LoopForge

final class KernelConvergenceDiagnosticPresentationTests: XCTestCase {
    func testTerminalRunNeverPresentsUnretiredStrategyAsActive() {
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.strategyLifecycleLabel(
                .active,
                runPhase: .stopped
            ),
            "unretired history · run stopped"
        )
        XCTAssertTrue(
            KernelConvergenceDiagnosticPresentation.isInertTerminalHistory(
                .active,
                runPhase: .stopped
            )
        )
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.strategyLifecycleLabel(
                .waitingForCondition,
                runPhase: .completed
            ),
            "waiting history · run completed"
        )
        XCTAssertTrue(
            KernelConvergenceDiagnosticPresentation.isInertTerminalHistory(
                .waitingForCondition,
                runPhase: .completed
            )
        )
    }

    func testExecutingAndRetiredStrategyLabelsRemainExact() {
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.strategyLifecycleLabel(
                .active,
                runPhase: .executing
            ),
            "active"
        )
        XCTAssertFalse(
            KernelConvergenceDiagnosticPresentation.isInertTerminalHistory(
                .active,
                runPhase: .executing
            )
        )
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.strategyLifecycleLabel(
                .waitingForCondition,
                runPhase: .blocked
            ),
            "waiting for condition"
        )
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.strategyLifecycleLabel(
                .retired,
                runPhase: .stopped
            ),
            "retired"
        )
        XCTAssertFalse(
            KernelConvergenceDiagnosticPresentation.isInertTerminalHistory(
                .retired,
                runPhase: .stopped
            )
        )
    }

    func testDiagnosticRunIDsUnionKernelAndRecoveryEvidenceExactlyOnce() {
        let shared = KernelRunID("run-shared")
        let kernelOnly = KernelRunID("run-kernel-only")
        let recoveryOnly = KernelRunID("run-recovery-only")

        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.orderedRunIDs(
                kernelRunIDs: [shared, kernelOnly],
                recoveryRunIDs: [recoveryOnly, shared]
            ).map(\.rawValue),
            ["run-kernel-only", "run-recovery-only", "run-shared"]
        )
    }

    func testRepositoryStatusTitlesDoNotImplyMissingAuthority() {
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.repositoryStatusTitle(nil),
            "Unavailable in current session"
        )
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.repositoryStatusTitle(.notApplicable),
            "No accepted workspace transition"
        )
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.repositoryStatusTitle(.resolved),
            "Resolved journal generation"
        )
        XCTAssertEqual(
            KernelConvergenceDiagnosticPresentation.repositoryStatusTitle(
                .withheldPendingEffects
            ),
            "Withheld · pending effects"
        )
    }
}
