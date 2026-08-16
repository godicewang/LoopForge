import CryptoKit
import Foundation
import XCTest
@testable import LoopForge

final class LegacyGraphKernelShadowAdapterTests: XCTestCase {
    func testLegacySnapshotProducesClaimsAndNeverMintsAuthority() throws {
        var first = node(id: "inspect", status: .completed)
        first.accumulatedActiveSeconds = 90
        first.lastReview = "Legacy reviewer approved this node."
        let task = task(status: .completed, nodes: [first])

        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: task)

        XCTAssertTrue(snapshot.acceptedReceiptIDs.isEmpty)
        XCTAssertFalse(snapshot.mayAutoResume)
        XCTAssertFalse(snapshot.mayWriteLegacyState)
        XCTAssertFalse(snapshot.mayAuthorizeEffects)
        XCTAssertEqual(snapshot.nodeObservations.count, 1)
        XCTAssertEqual(snapshot.nodeObservations[0].rawActiveSeconds, 90)
        XCTAssertEqual(snapshot.nodeObservations[0].acceptedActiveSeconds, 0)
        XCTAssertTrue(snapshot.nodeObservations[0].acceptedReceiptIDs.isEmpty)
        XCTAssertFalse(snapshot.nodeObservations[0].maySchedule)
        XCTAssertFalse(snapshot.nodeObservations[0].mayIntegrate)
        XCTAssertEqual(snapshot.nodeObservations[0].reviewClaim, first.lastReview)
    }

    func testSnapshotDigestIsStableAndChangesWithLegacyBytes() throws {
        let original = task(status: .paused, nodes: [node(id: "one")])
        let repeated = try LegacyGraphKernelShadowAdapter.snapshot(task: original)
        XCTAssertEqual(
            repeated.rawTaskDigest,
            try LegacyGraphKernelShadowAdapter.snapshot(task: original).rawTaskDigest
        )

        var changed = original
        changed.graphState?.nodes[0].status = .running
        let changedSnapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: changed)
        XCTAssertNotEqual(repeated.rawTaskDigest, changedSnapshot.rawTaskDigest)
        XCTAssertNotEqual(
            repeated.nodeObservations[0].rawNodeDigest,
            changedSnapshot.nodeObservations[0].rawNodeDigest
        )
    }

    func testDuplicateUnknownAndCyclicStructureRemainBlockingClaims() throws {
        var duplicateA = node(id: "duplicate")
        duplicateA.dependencies = ["missing"]
        let duplicateB = node(id: "duplicate")
        var cycleA = node(id: "cycle-a")
        cycleA.dependencies = ["cycle-b"]
        var cycleB = node(id: "cycle-b")
        cycleB.dependencies = ["cycle-a"]
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(
            task: task(
                status: .paused,
                nodes: [duplicateA, duplicateB, cycleA, cycleB]
            )
        )

        XCTAssertEqual(
            Set(snapshot.structureIssues.map(\.code)),
            [
                "dependency-cycle",
                "duplicate-node-identifiers",
                "unknown-dependency-identifiers"
            ]
        )
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: projection()
        )
        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertTrue(comparison.divergences.allSatisfy { $0.severity == .critical })
        XCTAssertFalse(comparison.writeBackPermitted)
    }

    func testLegacyCompletionCannotOverrideKernelPhaseOrQuiescence() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(
            task: task(status: .completed, nodes: [node(id: "done", status: .completed)])
        )
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: projection(phase: .executing, nodeIDs: ["done"])
        )

        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertEqual(
            Set(comparison.divergences.map(\.code)),
            [
                "legacy-completion-without-kernel-quiescence",
                "legacy-completed-node-lacks-kernel-acceptance",
                "legacy-node-approval-exceeds-kernel-evidence",
                "legacy-terminal-without-kernel-authority"
            ]
        )
    }

    func testLegacyWorkingStatusCannotManufactureKernelAttempt() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(
            task: task(status: .running, nodes: [node(id: "worker", status: .running)])
        )
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: projection(phase: .executing, nodeIDs: ["worker"])
        )

        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertEqual(comparison.divergences.map(\.code), [
            "legacy-work-without-kernel-attempt"
        ])
    }

    func testLegacyVisualApprovalCannotReplaceKernelVisualGate() throws {
        var value = task(status: .paused, nodes: [node(id: "visual")])
        value.visualAuditPassed = true
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: value)
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: projection(nodeIDs: ["visual"])
        )

        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertEqual(comparison.divergences.map(\.code), [
            "legacy-visual-pass-without-kernel-gate"
        ])
    }

    func testLegacyStoppedClaimCannotBypassKernelQuiescence() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(
            task: task(status: .stopped, nodes: [node(id: "stopped")])
        )
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: projection(phase: .stopped, quiescent: false, nodeIDs: ["stopped"])
        )

        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertEqual(comparison.divergences.map(\.code), [
            "legacy-stop-without-kernel-quiescence"
        ])
    }

    func testKernelAheadOfLegacyIsInformationalAndNeverWritesBack() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(
            task: task(status: .paused, nodes: [node(id: "waiting")])
        )
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: projection(
                phase: .completed,
                quiescent: true,
                nodeIDs: ["waiting"]
            )
        )

        XCTAssertFalse(comparison.blocksCutover)
        XCTAssertFalse(comparison.writeBackPermitted)
        XCTAssertEqual(comparison.divergences.count, 1)
        XCTAssertEqual(comparison.divergences[0].severity, .information)
        XCTAssertEqual(
            comparison.divergences[0].code,
            "legacy-projection-lags-kernel-completion"
        )
        XCTAssertEqual(comparison.comparisonDigest.rawValue.count, 64)
    }

    func testTaskWithoutGraphCannotBeSilentlyImported() {
        var value = task(status: .paused, nodes: [])
        value.graphState = nil

        XCTAssertThrowsError(try LegacyGraphKernelShadowAdapter.snapshot(task: value)) {
            XCTAssertEqual($0 as? LegacyGraphShadowError, .missingGraph)
        }
    }

    func testKernelProjectionExposesStableNodeRequirementAndMutationParity() {
        let projected = projection(nodeIDs: ["zeta", "alpha"])

        XCTAssertEqual(projected.nodes.map(\.nodeID.rawValue), ["alpha", "zeta"])
        XCTAssertEqual(projected.nodes[0].requirementIDs, [RequirementID("requirement-alpha")])
        XCTAssertTrue(projected.nodes[0].acceptedRequirementIDs.isEmpty)
        XCTAssertFalse(projected.nodes[0].allRequirementsAccepted)
        XCTAssertEqual(projected.nodes[0].writablePaths, ["Sources/alpha"])
        XCTAssertEqual(projected.nodes[0].maximumChangedFiles, 1)
        XCTAssertEqual(projected.nodes[0].maximumChangedBytes, 1_024)
        XCTAssertEqual(projected.nodes[0].capabilityIDs, ["workspace-write"])
        XCTAssertEqual(projected.nodes[0].verificationReceiptCount, 0)
        XCTAssertEqual(projected.nodes[0].reviewReceiptCount, 0)
        XCTAssertEqual(projected.nodes[0].visualReceiptCount, 0)
    }

    func testRetainedLegacyGraphSnapshotReplayWhenEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["LOOPFORGE_LEGACY_GRAPH_SNAPSHOT"],
              let outputPath = environment["LOOPFORGE_LEGACY_GRAPH_REPLAY_OUTPUT"] else {
            throw XCTSkip(
                "Set LOOPFORGE_LEGACY_GRAPH_SNAPSHOT and LOOPFORGE_LEGACY_GRAPH_REPLAY_OUTPUT for retained read-only replay."
            )
        }
        let inputURL = URL(fileURLWithPath: inputPath)
        let inputBefore = try Data(contentsOf: inputURL)
        let retainedTask = try JSONDecoder.loopForge.decode(LoopTask.self, from: inputBefore)
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: retainedTask)
        let kernel = projection()
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: kernel
        )
        let inputAfter = try Data(contentsOf: inputURL)

        XCTAssertEqual(inputAfter, inputBefore)
        XCTAssertFalse(snapshot.mayAutoResume)
        XCTAssertFalse(snapshot.mayWriteLegacyState)
        XCTAssertFalse(snapshot.mayAuthorizeEffects)
        XCTAssertTrue(snapshot.acceptedReceiptIDs.isEmpty)
        XCTAssertTrue(snapshot.nodeObservations.allSatisfy {
            $0.acceptedActiveSeconds == 0
                && $0.acceptedReceiptIDs.isEmpty
                && !$0.maySchedule
                && !$0.mayIntegrate
        })
        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertFalse(comparison.writeBackPermitted)

        let replay = RetainedReplayEnvelope(
            schemaVersion: 1,
            inputByteCount: inputBefore.count,
            inputSHA256: SHA256.hash(data: inputBefore).map {
                String(format: "%02x", $0)
            }.joined(),
            inputUnchanged: inputBefore == inputAfter,
            legacyNodeCount: snapshot.nodeObservations.count,
            completedNodeClaimCount: snapshot.completedNodeClaimCount,
            workingNodeClaimCount: snapshot.workingNodeClaimCount,
            acceptedLegacySeconds: snapshot.nodeObservations
                .reduce(0) { $0 + $1.acceptedActiveSeconds },
            acceptedLegacyReceiptCount: snapshot.acceptedReceiptIDs.count,
            structuralIssueCount: snapshot.structureIssues.count,
            divergenceCount: comparison.divergences.count,
            criticalDivergenceCount: comparison.divergences.filter {
                $0.severity == .critical
            }.count,
            blocksCutover: comparison.blocksCutover,
            writeBackPermitted: comparison.writeBackPermitted,
            snapshot: snapshot,
            comparison: comparison
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let output = try encoder.encode(replay)
        try output.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    private struct RetainedReplayEnvelope: Codable {
        var schemaVersion: Int
        var inputByteCount: Int
        var inputSHA256: String
        var inputUnchanged: Bool
        var legacyNodeCount: Int
        var completedNodeClaimCount: Int
        var workingNodeClaimCount: Int
        var acceptedLegacySeconds: Double
        var acceptedLegacyReceiptCount: Int
        var structuralIssueCount: Int
        var divergenceCount: Int
        var criticalDivergenceCount: Int
        var blocksCutover: Bool
        var writeBackPermitted: Bool
        var snapshot: LegacyGraphShadowSnapshot
        var comparison: GraphKernelShadowComparison
    }

    private func projection(
        phase: KernelRunPhase = .uninitialized,
        quiescent: Bool = false,
        nodeIDs: [String] = []
    ) -> KernelRunProjection {
        var state = KernelRunState.empty(runID: KernelRunID("shadow-run"))
        state.phase = phase
        state.sequence = 7
        for id in nodeIDs {
            let nodeID = KernelNodeID(id)
            let requirementID = RequirementID("requirement-\(id)")
            let contract = KernelNodeContract(
                id: nodeID,
                requirementIDs: [requirementID],
                objective: "Complete \(id)",
                dependencies: [],
                mutationScope: KernelMutationScope(
                    writablePaths: ["Sources/\(id)"],
                    maximumChangedFiles: 1,
                    maximumChangedBytes: 1_024
                ),
                capabilityIDs: ["workspace-write"],
                strategyFingerprint: StrategyFingerprint("strategy-\(id)")
            )
            state.nodes[nodeID] = KernelNodeState(
                contract: contract,
                status: .proposed,
                attemptIDs: []
            )
        }
        if quiescent {
            state.quiescenceReceipt = QuiescenceReceipt(
                id: ReceiptID("quiescence"),
                runID: state.runID,
                intent: phase == .completed ? .complete : .stop,
                observedAt: Date(timeIntervalSince1970: 100),
                observedAtMonotonicNanoseconds: 100,
                liveResources: [],
                failedReleases: [],
                queuedLeaseIDs: []
            )
        }
        return KernelRunProjection(state: state)
    }

    private func task(status: LoopTaskStatus, nodes: [GraphLoopNode]) -> LoopTask {
        let now = Date(timeIntervalSince1970: 100)
        var value = LoopTask(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Synthetic graph",
            request: "Perform a bounded synthetic task.",
            quality: .lightweight,
            category: .script,
            workspacePath: "/synthetic/workspace",
            targetSeconds: 0,
            accumulatedCodexSeconds: 0,
            model: .efficientAgent,
            status: status,
            stage: "Shadow",
            iteration: 0,
            threadID: nil,
            auditScore: 0,
            auditSummary: "",
            lastAgentMessage: "",
            consecutiveFailures: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: status == .completed ? now : nil,
            logs: [],
            originalRequest: "Perform a bounded synthetic task.",
            executionMode: .autoGraph
        )
        value.graphState = GraphLoopState(
            phase: status == .completed ? .completed : .executing,
            planSummary: "Synthetic plan",
            nodes: nodes,
            mainInteractionCount: 0,
            mainLastReview: "",
            maxConcurrentNodes: 2,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: now,
            completedAt: status == .completed ? now : nil
        )
        return value
    }

    private func node(
        id: String,
        status: GraphNodeStatus = .waiting
    ) -> GraphLoopNode {
        let now = Date(timeIntervalSince1970: 100)
        return GraphLoopNode(
            id: id,
            title: "Node \(id)",
            objective: "Complete \(id)",
            dependencies: [],
            writeScopes: ["Sources/\(id)"],
            verification: ["Run deterministic verification"],
            readOnly: false,
            status: status,
            iteration: 1,
            accumulatedActiveSeconds: 0,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: "/synthetic/workspace",
            isolationRootPath: "/synthetic/isolation/\(id)",
            workspaceStrategy: .gitWorktree,
            integrationBaseCommit: "baseline",
            currentInstruction: "Complete the bounded node.",
            lastAgentMessage: "",
            lastReview: "",
            consecutiveFailures: 0,
            createdAt: now,
            completedAt: status == .completed ? now : nil,
            logs: []
        )
    }
}
