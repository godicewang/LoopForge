import Foundation
import XCTest
@testable import LoopForge

@MainActor
final class GraphLoopTests: XCTestCase {
    func testPlanNormalizationRejectsUnsafeScopesAndKeepsGraphAcyclic() {
        let proposals = [
            GraphPlanNodeProposal(
                id: "Inspect current behavior",
                title: "Inspect",
                objective: "Map the current behavior.",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain findings"],
                readOnly: true
            ),
            GraphPlanNodeProposal(
                id: "Implement!",
                title: "Implement",
                objective: "Make the bounded change.",
                dependencies: ["Inspect current behavior"],
                writeScopes: ["./Sources/Feature", "../outside", "/tmp/escape"],
                verification: ["Run focused tests"],
                readOnly: false
            )
        ]

        let nodes = GraphPlanPolicy.normalizedNodes(proposals)

        XCTAssertEqual(nodes.map(\.id), ["inspect-current-behavior", "implement"])
        XCTAssertEqual(nodes[1].dependencies, ["inspect-current-behavior"])
        XCTAssertEqual(nodes[1].writeScopes, ["Sources/Feature"])
        XCTAssertTrue(GraphPlanPolicy.isAcyclic(nodes))

        var cyclic = nodes
        cyclic[0].dependencies = ["implement"]
        XCTAssertFalse(GraphPlanPolicy.isAcyclic(cyclic))
    }

    func testSchedulerParallelizesOnlyNonOverlappingIsolatedWriters() {
        let source = node(id: "source", scopes: ["Sources/Feature"])
        let tests = node(id: "tests", scopes: ["Tests/Feature"])
        let overlapping = node(id: "nested", scopes: ["Sources/Feature/UI"])
        let graph = state(nodes: [source, tests, overlapping], supportsWorktrees: true)

        let ready = GraphSchedulingPolicy.readyNodeIDs(
            state: graph,
            runningIDs: [],
            maximumToStart: 3
        )

        XCTAssertEqual(ready, ["source", "tests"])
        XCTAssertTrue(GraphSchedulingPolicy.writeScopesOverlap(
            ["Sources/Feature"],
            ["Sources/Feature/UI"]
        ))
        XCTAssertFalse(GraphSchedulingPolicy.writeScopesOverlap(
            ["Sources/Feature"],
            ["Tests/Feature"]
        ))
    }

    func testSchedulerSerializesWritersWithoutCleanGitIsolation() {
        let first = node(id: "one", scopes: ["Sources/One"])
        let second = node(id: "two", scopes: ["Sources/Two"])
        let graph = state(nodes: [first, second], supportsWorktrees: false)

        XCTAssertEqual(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: [],
                maximumToStart: 3
            ),
            ["one"]
        )
    }

    func testSchedulerWaitsForTheEntireFrontierBatchBeforeStartingASuccessor() {
        var first = node(id: "first-root", scopes: ["Sources/First"])
        var second = node(id: "second-root", scopes: ["Sources/Second"])
        let successor = node(
            id: "successor",
            scopes: ["Sources/Successor"],
            dependencies: ["first-root"]
        )

        markAuditedAndIntegrated(&first)
        var graph = state(
            nodes: [first, second, successor],
            supportsWorktrees: true
        )

        XCTAssertEqual(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: [],
                maximumToStart: 3
            ),
            ["second-root"],
            "A successor must not leapfrog another unfinished node in the current frontier."
        )
        XCTAssertEqual(
            GraphSchedulingPolicy.revealedNodes(state: graph).map(\.id),
            ["first-root", "second-root"],
            "Future dependency batches must remain absent from the visible graph."
        )

        second.status = .completed
        second.completedAt = Date()
        graph.nodes[1] = second
        XCTAssertTrue(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: [],
                maximumToStart: 3
            ).isEmpty,
            "A completion marker without a durable Main Graph audit cannot unlock the next batch."
        )
        XCTAssertEqual(
            GraphSchedulingPolicy.revealedNodes(state: graph).map(\.id),
            ["first-root", "second-root"]
        )

        markAuditedAndIntegrated(&second)
        graph.nodes[1] = second
        graph.reviewedJoinGroupIDs = [
            GraphSchedulingPolicy.joinGroupID(for: first, state: graph)
        ]
        XCTAssertEqual(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: [],
                maximumToStart: 3
            ),
            ["successor"]
        )
        XCTAssertEqual(
            GraphSchedulingPolicy.revealedNodes(state: graph).map(\.id),
            ["first-root", "second-root", "successor"]
        )
    }

    func testDefaultFrontierUsesOneConservativeJoinBarrier() {
        let proposals = (1...3).map { index in
            GraphPlanNodeProposal(
                id: "root-\(index)",
                title: "Root \(index)",
                objective: "Inspect concern \(index).",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain evidence"],
                readOnly: true
            )
        }
        var nodes = GraphPlanPolicy.initialBatchNodes(proposals)
        XCTAssertEqual(Set(nodes.compactMap(\.joinGroupID)).count, 1)

        markAuditedAndIntegrated(&nodes[0])
        markAuditedAndIntegrated(&nodes[1])
        var graph = state(nodes: nodes, supportsWorktrees: true)
        XCTAssertTrue(
            GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph).isEmpty,
            "Two completed nodes must not wake the Main Graph Agent while the third node in their default join group is unfinished."
        )

        markAuditedAndIntegrated(&nodes[2])
        graph.nodes = nodes
        graph.incrementallyReviewedNodeIDs = nodes.map(\.id)
        XCTAssertEqual(
            GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph),
            [try! XCTUnwrap(nodes[0].joinGroupID)]
        )
    }

    func testExplicitIndependentJoinGroupCanAdvanceWhileSiblingGroupRuns() {
        let proposals = [
            GraphPlanNodeProposal(
                id: "schema",
                title: "Schema",
                objective: "Inspect the schema contract.",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain schema evidence"],
                readOnly: true,
                joinGroup: "combined-core"
            ),
            GraphPlanNodeProposal(
                id: "runtime",
                title: "Runtime",
                objective: "Inspect the runtime contract.",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain runtime evidence"],
                readOnly: true,
                joinGroup: "combined-core"
            ),
            GraphPlanNodeProposal(
                id: "independent-research",
                title: "Independent research",
                objective: "Research an unrelated delivery concern.",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain sources"],
                readOnly: true,
                joinGroup: "independent-research"
            )
        ]
        var nodes = GraphPlanPolicy.initialBatchNodes(proposals)
        markAuditedAndIntegrated(&nodes[0])
        markAuditedAndIntegrated(&nodes[1])
        nodes[2].status = .running
        var graph = state(nodes: nodes, supportsWorktrees: true)
        let completedGroup = try! XCTUnwrap(nodes[0].joinGroupID)
        graph.incrementallyReviewedNodeIDs = [nodes[0].id, nodes[1].id]

        XCTAssertEqual(
            GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph),
            [completedGroup],
            "Only the predeclared completed group may wake the Main Graph Agent."
        )
        graph.reviewedJoinGroupIDs = [completedGroup]
        let successors = GraphPlanPolicy.nextBatchNodes(
            [
                GraphPlanNodeProposal(
                    id: "implement-core",
                    title: "Implement core",
                    objective: "Implement only from the audited schema and runtime evidence.",
                    dependencies: ["schema", "runtime"],
                    writeScopes: ["Sources/Core"],
                    verification: ["Run core tests"],
                    readOnly: false
                )
            ],
            existingNodes: graph.nodes,
            predecessorIDs: ["schema", "runtime"]
        )
        graph.nodes.append(contentsOf: successors)

        XCTAssertEqual(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: ["independent-research"],
                maximumToStart: 2
            ),
            ["implement-core"],
            "A successor may run early only because all of its dependency group's nodes were completed and the Main Graph Agent durably reviewed that group."
        )
    }

    func testEndRemainsDisconnectedUntilFinalDelivery() {
        var completed = node(id: "completed-root", scopes: [])
        markAuditedAndIntegrated(&completed)
        var graph = state(nodes: [completed], supportsWorktrees: true)
        graph.reviewedJoinGroupIDs = [
            GraphSchedulingPolicy.joinGroupID(for: completed, state: graph)
        ]

        graph.phase = .finalAudit
        graph.completedAt = nil
        XCTAssertFalse(GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph))

        graph.phase = .reporting
        XCTAssertFalse(GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph))

        graph.phase = .completed
        graph.completedAt = Date()
        XCTAssertTrue(GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph))
        XCTAssertEqual(GraphPresentationPolicy.terminalNodeIDs(state: graph), ["completed-root"])
    }

    func testEveryCompletedJoinMemberRequiresAnIncrementalCheckpointBeforeGroupReview() {
        var first = node(id: "first", scopes: [])
        var second = node(id: "second", scopes: [])
        first.joinGroupID = "frontier-1"
        second.joinGroupID = "frontier-1"
        markAuditedAndIntegrated(&first)
        markAuditedAndIntegrated(&second)
        var graph = state(nodes: [first, second], supportsWorktrees: true)

        XCTAssertEqual(
            GraphIncrementalReviewPolicy.pendingCompletedNodeID(state: graph),
            "first"
        )
        XCTAssertTrue(GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph).isEmpty)

        graph.incrementallyReviewedNodeIDs = ["first"]
        XCTAssertEqual(
            GraphIncrementalReviewPolicy.pendingCompletedNodeID(state: graph),
            "second"
        )
        XCTAssertTrue(GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph).isEmpty)

        graph.incrementallyReviewedNodeIDs = ["first", "second"]
        XCTAssertEqual(
            GraphSchedulingPolicy.reviewableJoinGroupIDs(state: graph),
            ["frontier-1"]
        )
    }

    func testIncrementalReviewEnvelopeDefaultsToNoGraphChurn() throws {
        let data = Data(#"{"summary":"Current plan remains valid."}"#.utf8)
        let decoded = try JSONDecoder().decode(
            GraphIncrementalJoinReviewEnvelope.self,
            from: data
        )
        XCTAssertEqual(decoded.summary, "Current plan remains valid.")
        XCTAssertTrue(decoded.retireNodeIDs.isEmpty)
        XCTAssertTrue(decoded.adjustments.isEmpty)
        XCTAssertTrue(decoded.addedNodes.isEmpty)
    }

    func testLegacyIterationLogsReconstructEveryInstructionAndMainDecision() {
        let start = Date(timeIntervalSince1970: 1_000)
        var historical = node(id: "keyboard-repair", scopes: ["Sources"])
        historical.iteration = 3
        historical.status = .completed
        historical.lastReview = "Approved from final evidence."
        historical.logs = [
            TaskLogEntry(
                kind: .control,
                message: iterationPrompt(1, "Implement the bounded repair."),
                timestamp: start
            ),
            TaskLogEntry(
                kind: .agent,
                message: "Implemented the repair but browser evidence is missing.",
                timestamp: start.addingTimeInterval(5)
            ),
            TaskLogEntry(
                kind: .control,
                message: iterationPrompt(2, "Exercise the rendered browser path."),
                timestamp: start.addingTimeInterval(20)
            ),
            TaskLogEntry(
                kind: .warning,
                message: "Recovered this node from its last durable checkpoint.",
                timestamp: start.addingTimeInterval(25)
            ),
            TaskLogEntry(
                kind: .control,
                message: iterationPrompt(3, "Retry the rendered browser path safely."),
                timestamp: start.addingTimeInterval(30)
            )
        ]
        var parent = task(workspace: "/tmp/iteration-history", status: .completed)
        parent.logs = [
            TaskLogEntry(
                kind: .audit,
                message: "Main Graph Agent: Keyboard-Repair: Conflict recovery is implemented, but browser evidence is missing; continue.",
                timestamp: start.addingTimeInterval(10)
            ),
            TaskLogEntry(
                kind: .audit,
                message: "Main Graph Agent: Keyboard-Repair: Approved from final evidence.",
                timestamp: start.addingTimeInterval(40)
            )
        ]

        let records = GraphIterationHistoryPolicy.records(
            task: parent,
            node: historical
        )

        XCTAssertEqual(records.map(\.number), [1, 2, 3])
        XCTAssertEqual(
            records.map(\.instruction),
            [
                "Implement the bounded repair.",
                "Exercise the rendered browser path.",
                "Retry the rendered browser path safely."
            ]
        )
        XCTAssertEqual(
            records.map(\.decision),
            [.continueWork, .recovery, .approved]
        )
        XCTAssertEqual(
            records[0].nextInstruction,
            "Exercise the rendered browser path."
        )
        XCTAssertEqual(
            GraphIterationHistoryPolicy.countLabel(3),
            "Iterations 3"
        )
    }

    func testPersistedIterationDecisionOverridesLegacyReconstruction() {
        var current = node(id: "current", scopes: [])
        current.iteration = 1
        current.logs = [
            TaskLogEntry(
                kind: .control,
                message: iterationPrompt(1, "Legacy instruction."),
                timestamp: Date(timeIntervalSince1970: 1_000)
            )
        ]
        current.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Durable instruction.",
                startedAt: Date(timeIntervalSince1970: 2_000),
                finishedAt: Date(timeIntervalSince1970: 2_100),
                threadID: "thread-1",
                exitCode: 0,
                agentSummary: "Evidence retained.",
                mainReview: "Approved.",
                nextInstruction: "",
                decision: .approved
            )
        ]

        let records = GraphIterationHistoryPolicy.records(
            task: task(workspace: "/tmp/iteration-history", status: .completed),
            node: current
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].instruction, "Durable instruction.")
        XCTAssertEqual(records[0].decision, .approved)
    }

    func testPendingIterationResumesWithoutInflatingPublicIterationCount() {
        var current = node(id: "current", scopes: [])
        current.iteration = 2
        current.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Initial work.",
                startedAt: Date(timeIntervalSince1970: 1_000),
                finishedAt: Date(timeIntervalSince1970: 1_100),
                threadID: "thread-1",
                exitCode: 0,
                agentSummary: "Implemented.",
                mainReview: "Continue with real verification.",
                nextInstruction: "Verify.",
                decision: .continueWork
            ),
            GraphNodeIterationRecord(
                number: 2,
                instruction: "Verify.",
                startedAt: Date(timeIntervalSince1970: 1_200),
                finishedAt: nil,
                threadID: "thread-2",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending
            )
        ]
        let parent = task(workspace: "/tmp/iteration-history", status: .paused)

        XCTAssertEqual(
            GraphIterationHistoryPolicy.nextTurnNumber(task: parent, node: current),
            2
        )

        current.iterationHistory?[1].mainReview = "Approved."
        current.iterationHistory?[1].decision = .approved
        XCTAssertEqual(
            GraphIterationHistoryPolicy.nextTurnNumber(task: parent, node: current),
            3
        )
    }

    func testRepeatedPromptForOnePendingIterationReconstructsOneCycle() {
        let start = Date(timeIntervalSince1970: 2_000)
        var historical = node(id: "legacy", scopes: [])
        historical.iteration = 1
        historical.logs = [
            TaskLogEntry(
                kind: .control,
                message: iterationPrompt(1, "Resume the same bounded work."),
                timestamp: start
            ),
            TaskLogEntry(
                kind: .control,
                message: iterationPrompt(1, "Resume the same bounded work."),
                timestamp: start.addingTimeInterval(30)
            )
        ]
        let parent = task(workspace: "/tmp/iteration-history", status: .paused)

        let records = GraphIterationHistoryPolicy.records(
            task: parent,
            node: historical
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.number, 1)
        XCTAssertEqual(records.first?.decision, .pending)
        XCTAssertEqual(
            GraphIterationHistoryPolicy.nextTurnNumber(
                task: parent,
                node: historical
            ),
            1
        )
    }

    func testIncrementalReplacementStaysInJoinGroupAndInheritsSafePredecessors() {
        var completed = node(id: "completed", scopes: [])
        completed.joinGroupID = "frontier-2"
        markAuditedAndIntegrated(&completed)
        var obsolete = node(
            id: "obsolete",
            scopes: ["Sources/Old"],
            dependencies: ["baseline"]
        )
        obsolete.joinGroupID = "frontier-2"
        obsolete.workspaceStrategy = .gitWorktree

        let replacements = GraphPlanPolicy.incrementalJoinNodes(
            [
                GraphPlanNodeProposal(
                    id: "replacement",
                    title: "Replacement",
                    objective: "Explore the corrected design.",
                    dependencies: ["completed"],
                    writeScopes: ["Sources/New"],
                    verification: ["Run focused tests"],
                    readOnly: false,
                    joinGroup: "ignored",
                    replacesNodeIDs: ["obsolete"]
                )
            ],
            existingNodes: [
                node(id: "baseline", scopes: []),
                completed,
                obsolete
            ],
            groupID: "frontier-2",
            completedGroupNodeIDs: ["completed"],
            retiredNodes: [obsolete],
            triggerNodeID: "completed"
        )

        XCTAssertEqual(replacements.map(\.id), ["replacement"])
        XCTAssertEqual(replacements[0].joinGroupID, "frontier-2")
        XCTAssertEqual(
            Set(replacements[0].dependencies),
            Set(["completed", "baseline"])
        )
        XCTAssertEqual(replacements[0].replacesNodeIDs, ["obsolete"])
    }

    func testSameJoinGroupIncrementalNodeCanRunBeforeFullGroupTransition() {
        var completed = node(id: "completed", scopes: [])
        completed.joinGroupID = "frontier-1"
        markAuditedAndIntegrated(&completed)
        var sibling = node(id: "sibling", scopes: [])
        sibling.joinGroupID = "frontier-1"
        sibling.status = .running
        var added = node(
            id: "new-exploration",
            scopes: [],
            dependencies: ["completed"]
        )
        added.joinGroupID = "frontier-1"
        let graph = state(
            nodes: [completed, sibling, added],
            supportsWorktrees: true
        )

        XCTAssertEqual(
            GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: ["sibling"],
                maximumToStart: 2
            ),
            ["new-exploration"],
            "An evidence-seeking node inside the same open join group is not a downstream frontier."
        )
    }

    func testRetirementRejectsSharedActiveWriterAndLiveDependent() {
        var sharedWriter = node(id: "shared-writer", scopes: ["Sources"])
        sharedWriter.status = .running
        sharedWriter.workspaceStrategy = .exclusiveWorkspace
        var isolatedWriter = node(id: "isolated-writer", scopes: ["Sources/Feature"])
        isolatedWriter.status = .running
        isolatedWriter.workspaceStrategy = .gitWorktree
        var dependent = node(
            id: "dependent",
            scopes: [],
            dependencies: ["isolated-writer"]
        )
        dependent.status = .waiting
        let graph = state(
            nodes: [sharedWriter, isolatedWriter, dependent],
            supportsWorktrees: true
        )

        XCTAssertFalse(
            GraphIncrementalReviewPolicy.canRetire(
                sharedWriter,
                in: graph,
                requestedRetirements: ["shared-writer"]
            )
        )
        XCTAssertFalse(
            GraphIncrementalReviewPolicy.canRetire(
                isolatedWriter,
                in: graph,
                requestedRetirements: ["isolated-writer"]
            )
        )
        XCTAssertTrue(
            GraphIncrementalReviewPolicy.canRetire(
                isolatedWriter,
                in: graph,
                requestedRetirements: ["isolated-writer", "dependent"]
            )
        )
        var protectedDependent = dependent
        markAuditedAndIntegrated(&protectedDependent)
        let protectedGraph = state(
            nodes: [isolatedWriter, protectedDependent],
            supportsWorktrees: true
        )
        XCTAssertFalse(
            GraphIncrementalReviewPolicy.canRetire(
                isolatedWriter,
                in: protectedGraph,
                requestedRetirements: ["isolated-writer", "dependent"]
            ),
            "A requested dependent that is completed and therefore non-disposable must still protect its predecessor."
        )
    }

    func testSupersededHistoryIsVisibleButExcludedFromCompletionAndEnd() {
        var completed = node(id: "completed", scopes: [])
        markAuditedAndIntegrated(&completed)
        var historical = node(id: "historical", scopes: ["Sources/Old"])
        historical.status = .superseded
        historical.accumulatedActiveSeconds = 812
        historical.supersededReason = "The integrated contract invalidated this approach."
        var graph = state(nodes: [completed, historical], supportsWorktrees: true)
        graph.phase = .completed
        graph.completedAt = Date()

        XCTAssertEqual(GraphSchedulingPolicy.revealedNodes(state: graph).count, 2)
        XCTAssertEqual(graph.completedNodeCount, 1)
        XCTAssertTrue(graph.allNodesCompleted)
        XCTAssertEqual(GraphPresentationPolicy.terminalNodeIDs(state: graph), ["completed"])
        XCTAssertEqual(
            GraphPresentationPolicy.incomingEdgeDisposition(for: historical),
            .superseded
        )
        XCTAssertTrue(GraphPresentationPolicy.shouldConnectLeavesToEnd(state: graph))
    }

    func testFinalRepairConvergesEveryCompletedTerminalBranch() {
        var rootA = node(id: "root-a", scopes: [])
        var successorA = node(
            id: "successor-a",
            scopes: ["Sources/A"],
            dependencies: ["root-a"]
        )
        var rootB = node(id: "root-b", scopes: [])
        markAuditedAndIntegrated(&rootA)
        markAuditedAndIntegrated(&successorA)
        markAuditedAndIntegrated(&rootB)

        let repairs = GraphPlanPolicy.finalRepairBatchNodes(
            [
                GraphPlanNodeProposal(
                    id: "integrated-repair",
                    title: "Integrated repair",
                    objective: "Repair the combined result from both independent branches.",
                    dependencies: ["root-a", "successor-a", "root-b"],
                    writeScopes: ["."],
                    verification: ["Run the whole-project path"],
                    readOnly: false
                )
            ],
            existingNodes: [rootA, successorA, rootB]
        )

        XCTAssertEqual(repairs.map(\.id), ["integrated-repair"])
        XCTAssertEqual(
            Set(repairs[0].dependencies),
            Set(["successor-a", "root-b"]),
            "The final repair must join every terminal branch, not only the numerically deepest branch."
        )
    }

    func testJoinGroupCheckpointRoundTripsAndLegacyStateStillDecodes() throws {
        var grouped = node(id: "grouped", scopes: [])
        grouped.joinGroupID = "frontier-1-core"
        var graph = state(nodes: [grouped], supportsWorktrees: true)
        graph.reviewedJoinGroupIDs = ["frontier-1-core"]
        graph.incrementallyReviewedNodeIDs = ["grouped"]
        graph.nodes[0].replacesNodeIDs = ["legacy-branch"]
        graph.nodes[0].planAdjustment = "Retain the verified contract."
        graph.nodes[0].iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Inspect.",
                startedAt: Date(timeIntervalSince1970: 100),
                finishedAt: Date(timeIntervalSince1970: 200),
                threadID: "thread",
                exitCode: 0,
                agentSummary: "Done.",
                mainReview: "Approved.",
                nextInstruction: "",
                decision: .approved
            )
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(graph)
        let restored = try decoder.decode(GraphLoopState.self, from: encoded)
        XCTAssertEqual(restored.nodes[0].joinGroupID, "frontier-1-core")
        XCTAssertEqual(restored.reviewedJoinGroupIDs, ["frontier-1-core"])
        XCTAssertEqual(restored.incrementallyReviewedNodeIDs, ["grouped"])
        XCTAssertEqual(restored.nodes[0].replacesNodeIDs, ["legacy-branch"])
        XCTAssertEqual(restored.nodes[0].planAdjustment, "Retain the verified contract.")
        XCTAssertEqual(restored.nodes[0].iterationHistory?.first?.decision, .approved)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "reviewedJoinGroupIDs")
        object.removeValue(forKey: "incrementallyReviewedNodeIDs")
        var nodeObjects = try XCTUnwrap(object["nodes"] as? [[String: Any]])
        nodeObjects[0].removeValue(forKey: "joinGroupID")
        nodeObjects[0].removeValue(forKey: "replacesNodeIDs")
        nodeObjects[0].removeValue(forKey: "planAdjustment")
        nodeObjects[0].removeValue(forKey: "iterationHistory")
        object["nodes"] = nodeObjects
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacy = try decoder.decode(GraphLoopState.self, from: legacyData)
        XCTAssertNil(legacy.reviewedJoinGroupIDs)
        XCTAssertNil(legacy.incrementallyReviewedNodeIDs)
        XCTAssertNil(legacy.nodes[0].joinGroupID)
        XCTAssertNil(legacy.nodes[0].replacesNodeIDs)
        XCTAssertNil(legacy.nodes[0].iterationHistory)
    }

    func testOnlyPredecessorFreeNodesAppearInTheInitialGraphBatch() {
        let proposals = [
            GraphPlanNodeProposal(
                id: "inspect",
                title: "Inspect",
                objective: "Inspect the workspace.",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain evidence"],
                readOnly: true
            ),
            GraphPlanNodeProposal(
                id: "research",
                title: "Research",
                objective: "Research an independent question.",
                dependencies: [],
                writeScopes: [],
                verification: ["Retain sources"],
                readOnly: true
            ),
            GraphPlanNodeProposal(
                id: "implement",
                title: "Implement",
                objective: "Implement after inspection.",
                dependencies: ["inspect", "research"],
                writeScopes: ["Sources"],
                verification: ["Run tests"],
                readOnly: false
            ),
            GraphPlanNodeProposal(
                id: "verify",
                title: "Verify",
                objective: "Verify after implementation.",
                dependencies: ["implement"],
                writeScopes: [],
                verification: ["Run the suite"],
                readOnly: true
            )
        ]

        let materialized = GraphPlanPolicy.initialBatchNodes(proposals)

        XCTAssertEqual(materialized.map(\.id), ["inspect", "research"])
        XCTAssertTrue(materialized.allSatisfy(\.dependencies.isEmpty))
        XCTAssertFalse(
            materialized.contains { $0.id == "implement" || $0.id == "verify" },
            "Dependent work must not exist in the initial graph state."
        )
    }

    func testSameFrontierOverlappingWriterIsNotMaterializedEarly() {
        let proposals = [
            GraphPlanNodeProposal(
                id: "runtime-owner",
                title: "Runtime owner",
                objective: "Implement the runtime source of truth.",
                dependencies: [],
                writeScopes: ["Sources/Runtime"],
                verification: ["Run runtime tests"],
                readOnly: false
            ),
            GraphPlanNodeProposal(
                id: "premature-consumer",
                title: "Premature consumer",
                objective: "Change a nested runtime consumer.",
                dependencies: [],
                writeScopes: ["Sources/Runtime/UI"],
                verification: ["Run UI tests"],
                readOnly: false
            ),
            GraphPlanNodeProposal(
                id: "independent-tests",
                title: "Independent tests",
                objective: "Implement an independent test harness.",
                dependencies: [],
                writeScopes: ["Tests/Harness"],
                verification: ["Run harness tests"],
                readOnly: false
            )
        ]

        let firstBatch = GraphPlanPolicy.initialBatchNodes(proposals)

        XCTAssertEqual(firstBatch.map(\.id), ["runtime-owner", "independent-tests"])
        XCTAssertFalse(
            firstBatch.contains { $0.id == "premature-consumer" },
            "An overlapping writer must not be pre-assigned in the same frontier."
        )
    }

    func testWriterWithoutDeclaredScopeOwnsWholeWorkspaceAndBlocksSiblingMaterialization() {
        let proposals = [
            GraphPlanNodeProposal(
                id: "whole-project-repair",
                title: "Whole project repair",
                objective: "Repair the integrated project.",
                dependencies: [],
                writeScopes: [],
                verification: ["Run all tests"],
                readOnly: false
            ),
            GraphPlanNodeProposal(
                id: "source-edit",
                title: "Source edit",
                objective: "Edit one source subtree.",
                dependencies: [],
                writeScopes: ["Sources"],
                verification: ["Run focused tests"],
                readOnly: false
            )
        ]

        let firstBatch = GraphPlanPolicy.initialBatchNodes(proposals)

        XCTAssertEqual(firstBatch.map(\.id), ["whole-project-repair"])
        XCTAssertEqual(firstBatch[0].writeScopes, ["."])
    }

    func testNextBatchMaterializesOnlyImmediateWorkAgainstTheCompletedFrontier() {
        var first = node(id: "inspect", scopes: [])
        var second = node(id: "baseline", scopes: [])
        markAuditedAndIntegrated(&first)
        markAuditedAndIntegrated(&second)
        let proposals = [
            GraphPlanNodeProposal(
                id: "implement",
                title: "Implement",
                objective: "Implement the now-understood change.",
                dependencies: ["inspect"],
                writeScopes: ["Sources"],
                verification: ["Run focused tests"],
                readOnly: false
            ),
            GraphPlanNodeProposal(
                id: "future-verify",
                title: "Verify",
                objective: "Attempted same-response downstream assignment.",
                dependencies: ["implement"],
                writeScopes: [],
                verification: ["Run all tests"],
                readOnly: true
            )
        ]

        let next = GraphPlanPolicy.nextBatchNodes(
            proposals,
            existingNodes: [first, second],
            predecessorIDs: ["inspect", "baseline"]
        )

        XCTAssertEqual(next.map(\.id), ["implement"])
        XCTAssertEqual(next[0].dependencies, ["inspect"])
        XCTAssertTrue(
            next.flatMap(\.dependencies).allSatisfy { ["inspect", "baseline"].contains($0) }
        )
        XCTAssertFalse(
            next.contains { $0.id == "future-verify" },
            "A proposal that depends on another new node is a future batch and must not be materialized."
        )
    }

    func testFinalRepairRebasesHistoricalDependenciesOntoLatestAuditedFrontier() {
        var inspect = node(id: "inspect", scopes: [])
        var implement = node(
            id: "implement",
            scopes: ["Sources"],
            dependencies: ["inspect"]
        )
        var verify = node(
            id: "verify",
            scopes: [],
            dependencies: ["implement"]
        )
        markAuditedAndIntegrated(&inspect)
        markAuditedAndIntegrated(&implement)
        markAuditedAndIntegrated(&verify)

        let repairs = GraphPlanPolicy.finalRepairBatchNodes(
            [
                GraphPlanNodeProposal(
                    id: "repair-final",
                    title: "Repair final audit gap",
                    objective: "Close the verified whole-project gap.",
                    dependencies: ["inspect", "implement", "verify"],
                    writeScopes: ["."],
                    verification: ["Rerun the complete path"],
                    readOnly: false
                )
            ],
            existingNodes: [inspect, implement, verify]
        )

        XCTAssertEqual(repairs.map(\.id), ["repair-final"])
        XCTAssertEqual(
            repairs[0].dependencies,
            ["verify"],
            "The latest audited frontier transitively represents all historical predecessors."
        )
    }

    func testFinalRepairRejectsUnmaterializedFutureDependency() {
        var inspect = node(id: "inspect", scopes: [])
        markAuditedAndIntegrated(&inspect)

        let repairs = GraphPlanPolicy.finalRepairBatchNodes(
            [
                GraphPlanNodeProposal(
                    id: "repair-now",
                    title: "Repair",
                    objective: "Repair now.",
                    dependencies: ["future-node"],
                    writeScopes: ["Sources"],
                    verification: ["Verify"],
                    readOnly: false
                )
            ],
            existingNodes: [inspect]
        )

        XCTAssertTrue(repairs.isEmpty)
    }

    func testFinalRepairPreservesExactLegacyTruncatedPredecessorID() {
        var inspect = node(id: "inspect", scopes: [])
        var legacy = node(
            id: "repair-intent-aware-conflict-and-keyboard-",
            scopes: ["pulseboard/static"],
            dependencies: ["inspect"]
        )
        markAuditedAndIntegrated(&inspect)
        markAuditedAndIntegrated(&legacy)

        let repairs = GraphPlanPolicy.finalRepairBatchNodes(
            [
                GraphPlanNodeProposal(
                    id: "refresh-final-evidence",
                    title: "Refresh final evidence",
                    objective: "Rerun the final integrated product evidence.",
                    dependencies: ["repair-intent-aware-conflict-and-keyboard-"],
                    writeScopes: ["README.md", "artifacts/screenshots"],
                    verification: ["Run the complete suite and browser path"],
                    readOnly: false
                )
            ],
            existingNodes: [inspect, legacy]
        )

        XCTAssertEqual(repairs.map(\.id), ["refresh-final-evidence"])
        XCTAssertEqual(
            repairs.first?.dependencies,
            ["repair-intent-aware-conflict-and-keyboard-"]
        )
    }

    func testBatchTransitionMustChooseExactlyOneControlFlow() {
        let nodeProposal = GraphPlanNodeProposal(
            id: "next",
            title: "Next",
            objective: "Immediate next work",
            dependencies: ["current"],
            writeScopes: [],
            verification: ["Verify"],
            readOnly: true
        )

        XCTAssertTrue(GraphPlanPolicy.isValidBatchTransition(
            GraphBatchTransitionEnvelope(
                readyForFinalAudit: true,
                summary: "Ready",
                nextNodes: []
            )
        ))
        XCTAssertTrue(GraphPlanPolicy.isValidBatchTransition(
            GraphBatchTransitionEnvelope(
                readyForFinalAudit: false,
                summary: "Continue",
                nextNodes: [nodeProposal]
            )
        ))
        XCTAssertFalse(GraphPlanPolicy.isValidBatchTransition(
            GraphBatchTransitionEnvelope(
                readyForFinalAudit: true,
                summary: "Contradictory",
                nextNodes: [nodeProposal]
            )
        ))
        XCTAssertFalse(GraphPlanPolicy.isValidBatchTransition(
            GraphBatchTransitionEnvelope(
                readyForFinalAudit: false,
                summary: "Missing work",
                nextNodes: []
            )
        ))
    }

    func testReadOnlyNodeUsesRealReadOnlyCodexSandbox() {
        let now = Date()
        var parent = task(workspace: "/tmp", status: .running)
        parent.subAgent = .codex(
            model: "gpt-test",
            displayName: "GPT Test",
            reasoning: "high",
            access: .fullAccess
        )
        let readOnlyNode = GraphLoopNode(
            id: "inspect",
            title: "Inspect",
            objective: "Inspect only",
            dependencies: [],
            writeScopes: [],
            verification: [],
            readOnly: true,
            status: .waiting,
            iteration: 0,
            accumulatedActiveSeconds: 0,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: "/tmp",
            isolationRootPath: nil,
            workspaceStrategy: .sharedReadOnly,
            integrationBaseCommit: nil,
            currentInstruction: "Inspect.",
            lastAgentMessage: "",
            lastReview: "",
            consecutiveFailures: 0,
            createdAt: now,
            completedAt: nil,
            logs: []
        )
        let selection = parent.resolvedSubAgent
        let isolated = AgentSelection(
            provider: selection.provider,
            modelID: selection.modelID,
            displayName: selection.displayName,
            reasoningEffort: selection.reasoningEffort,
            accessMode: readOnlyNode.readOnly ? .readOnly : selection.accessMode,
            localProfile: selection.localProfile,
            apiConnection: selection.apiConnection
        )

        XCTAssertEqual(isolated.accessMode, .readOnly)
        XCTAssertEqual(isolated.accessMode.sandboxMode, "read-only")
        XCTAssertFalse(CodexAccessMode.selectableCases.contains(.readOnly))
    }

    func testParallelWriterNarrowsFullAccessUnlessItsObjectiveNeedsHostTools() {
        let parent = AgentSelection.codex(
            model: "gpt-test",
            displayName: "GPT Test",
            reasoning: "high",
            access: .fullAccess
        )
        var codeNode = node(id: "backend", scopes: ["src/"])
        codeNode.objective = "Implement and unit test the persistence layer."
        var visualNode = node(id: "visual-qa", scopes: ["artifacts/screenshots/"])
        visualNode.objective = "Launch the real browser and capture screenshots."
        var interactionNode = node(id: "interaction-qa", scopes: ["tests/frontend/"])
        interactionNode.objective = "Repair focus restoration after rerender."
        interactionNode.verification = [
            "Use actual keyboard events in a real browser and assert focus after every rerender."
        ]

        XCTAssertEqual(
            GraphNodeAccessPolicy.selection(
                parent: parent,
                node: codeNode,
                category: .web
            ).accessMode,
            .workspaceOnly
        )
        XCTAssertEqual(
            GraphNodeAccessPolicy.selection(
                parent: parent,
                node: visualNode,
                category: .web
            ).accessMode,
            .fullAccess
        )
        XCTAssertEqual(
            GraphNodeAccessPolicy.selection(
                parent: parent,
                node: interactionNode,
                category: .web
            ).accessMode,
            .fullAccess
        )
        XCTAssertTrue(
            CodexHostToolingPolicy.objectiveRequiresInstalledTools(
                GraphNodeAccessPolicy.capabilityRequest(for: interactionNode),
                category: .web
            ),
            "The same objective-plus-verification request must drive installed tool loading."
        )
    }

    func testHostToolingSignalsRequireEnglishWordBoundaries() {
        XCTAssertFalse(
            CodexHostToolingPolicy.objectiveRequiresInstalledTools(
                "Distinguish a genuinely new database from an existing empty schema.",
                category: .web
            ),
            "`gui` inside `distinguish` must not grant host-tool access."
        )
        XCTAssertTrue(
            CodexHostToolingPolicy.objectiveRequiresInstalledTools(
                "Launch the real GUI and inspect the browser.",
                category: .web
            )
        )
        XCTAssertTrue(
            CodexHostToolingPolicy.objectiveRequiresInstalledTools(
                "启动应用并完成界面验收与截图。",
                category: .web
            )
        )
    }

    func testGraphNodeGuidanceBoundsAndCleansUpLongRunningProcesses() {
        let guidance = GraphNodeOperationalPolicy.longRunningProcessGuidance
        let normalized = guidance.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        XCTAssertTrue(normalized.contains("bounded deadline"))
        XCTAssertTrue(normalized.contains("retained PID"))
        XCTAssertTrue(normalized.contains("Never use shell `exec`"))
        XCTAssertTrue(normalized.contains("capture `$!`"))
        XCTAssertTrue(normalized.contains("terminate and reap"))
        XCTAssertTrue(normalized.contains("Never kill unrelated"))
    }

    func testGraphDelegationGuidanceForbidsHiddenNestedAgents() {
        let guidance = GraphDelegationPolicy.noNestedAgentsGuidance

        XCTAssertTrue(guidance.contains("persisted graph is the only"))
        XCTAssertTrue(guidance.contains("Do not call collaboration"))
        XCTAssertTrue(guidance.contains("spawn_agent"))
        XCTAssertTrue(guidance.contains("only the Main Graph"))
    }

    func testGraphConflictIntegrationTurnCannotDelegateOutsidePersistedGraph() {
        let prompt = GraphDelegationPolicy.boundedTurn(
            "Integrate the verified isolated result into the primary workspace."
        )
        let normalized = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        XCTAssertTrue(prompt.hasPrefix("Integrate the verified isolated result"))
        XCTAssertTrue(normalized.contains("persisted graph is the only concurrency"))
        XCTAssertTrue(normalized.contains("Do not call collaboration"))
        XCTAssertTrue(normalized.contains("Do not create a hidden subordinate agent"))
    }

    func testGraphVerificationUsesObservedCountsInsteadOfInventedFixedTotals() {
        let guidance = GraphVerificationPolicy.observedTestCountGuidance

        XCTAssertTrue(guidance.contains("verbatim user goal explicitly"))
        XCTAssertTrue(guidance.contains("observed pass/fail totals"))
        XCTAssertTrue(guidance.contains("obsolete number"))
    }

    func testGraphEscalatesWorkerDisclosedProductGapsBeyondNodeScope() {
        let guidance = GraphCompletionPolicy.disclosedGapGuidance
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        XCTAssertTrue(guidance.contains("remaining issue disclosed by any worker"))
        XCTAssertTrue(guidance.contains("write scope limits that worker"))
        XCTAssertTrue(guidance.contains("smallest safe repair-and-regression node"))
        XCTAssertTrue(guidance.contains("harness error"))
    }

    func testWholeGraphAuditBudgetSupportsMultimodalUltraReviewWithoutUnboundedWait() {
        XCTAssertEqual(GraphReviewBudgetPolicy.finalAuditTimeout, 20 * 60)
        XCTAssertLessThan(GraphReviewBudgetPolicy.finalAuditTimeout, 30 * 60)
    }

    func testWholeGraphDecisionAcceptsMissingOptionalRepairFields() throws {
        let raw = """
        {"approved":true,"summary":"All required paths passed.","visualPassed":true}
        """

        let decoded = try XCTUnwrap(
            GraphLoopEngine.decode(GraphFinalReviewEnvelope.self, from: raw)
        )

        XCTAssertTrue(decoded.approved)
        XCTAssertEqual(decoded.summary, "All required paths passed.")
        XCTAssertEqual(decoded.nextInstruction, "")
        XCTAssertEqual(decoded.visualPassed, true)
        XCTAssertNil(decoded.addedNodes)
    }

    func testWholeGraphCodexOutputSchemaRequiresACompleteStrictEnvelope() throws {
        let data = try XCTUnwrap(GraphLoopEngine.finalReviewOutputSchema.data(using: .utf8))
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(root["type"] as? String, "object")
        XCTAssertEqual(root["additionalProperties"] as? Bool, false)
        let required = Set(try XCTUnwrap(root["required"] as? [String]))
        XCTAssertEqual(
            required,
            ["approved", "summary", "nextInstruction", "visualPassed", "addedNodes"]
        )
        let properties = try XCTUnwrap(root["properties"] as? [String: Any])
        let nodes = try XCTUnwrap(properties["addedNodes"] as? [String: Any])
        let item = try XCTUnwrap(nodes["items"] as? [String: Any])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
    }

    func testWholeGraphDecisionFindsBalancedJSONInsideNoisyReview() throws {
        let raw = """
        Preliminary example: {"approved":"not a boolean"}.
        The reviewer mentioned a literal brace in prose: {not-json}.
        Final decision:
        ```json
        {"approved":false,"summary":"Reload {latest} remains disabled.","nextInstruction":"Repair the repeat-conflict path.","visualPassed":true,"addedNodes":[]}
        ```
        trailing explanation {with another brace}
        """

        let decoded = try XCTUnwrap(
            GraphLoopEngine.decode(GraphFinalReviewEnvelope.self, from: raw)
        )

        XCTAssertFalse(decoded.approved)
        XCTAssertEqual(decoded.summary, "Reload {latest} remains disabled.")
        XCTAssertEqual(decoded.nextInstruction, "Repair the repeat-conflict path.")
        XCTAssertEqual(decoded.visualPassed, true)
        XCTAssertEqual(decoded.addedNodes, [])
    }

    func testReadOnlyVerificationUsesPrimaryWorkspaceWhenGitIsClean() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeReadOnlyGraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("base.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "base"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        let parent = task(workspace: directory.path, status: .running)
        var verifier = node(id: "verify", scopes: [])
        verifier.workspacePath = directory.path
        verifier.workspaceStrategy = .sharedReadOnly
        verifier = try await coordinator.prepare(
            task: parent,
            node: verifier,
            capability: capability
        )

        XCTAssertEqual(verifier.workspaceStrategy, .sharedReadOnly)
        XCTAssertEqual(verifier.workspacePath, directory.path)
        let verifierWorkspace = URL(fileURLWithPath: try XCTUnwrap(verifier.workspacePath))
        XCTAssertEqual(
            try String(contentsOf: verifierWorkspace.appendingPathComponent("base.txt"), encoding: .utf8),
            "base\n"
        )
        let integration = await coordinator.integrate(task: parent, node: verifier)
        XCTAssertEqual(integration, .noChanges)
        XCTAssertNil(verifier.isolationRootPath)
    }

    func testReadOnlyTestRunnerUsesDisposableWritableWorktree() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeWritableVerifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("base.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "base"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        let parent = task(workspace: directory.path, status: .running)
        var verifier = node(id: "suite-verifier", scopes: [])
        verifier.objective = "Run complete integrated suite without modifying product files."
        verifier.verification = ["python3.12 -m unittest discover -s tests/backend -v"]
        verifier = try await coordinator.prepare(
            task: parent,
            node: verifier,
            capability: capability
        )

        XCTAssertEqual(verifier.workspaceStrategy, .isolatedVerification)
        XCTAssertNotEqual(verifier.workspacePath, directory.path)
        let verifierWorkspace = URL(fileURLWithPath: try XCTUnwrap(verifier.workspacePath))
        try Data("temporary\n".utf8).write(
            to: verifierWorkspace.appendingPathComponent("runtime-output.txt")
        )

        let integration = await coordinator.integrate(task: parent, node: verifier)
        XCTAssertEqual(integration, .noChanges)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("runtime-output.txt").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: verifierWorkspace.path))
    }

    func testNonGitReadOnlyTestRunnerUsesDiscardedWritableCopy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeNonGitVerifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("base.txt"))

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        XCTAssertFalse(capability.supportsParallelWorktrees)
        let parent = task(workspace: directory.path, status: .running)
        var verifier = node(id: "non-git-suite", scopes: [])
        verifier.objective = "Run the complete automated suite without modifying product files."
        verifier = try await coordinator.prepare(
            task: parent,
            node: verifier,
            capability: capability
        )

        XCTAssertEqual(verifier.workspaceStrategy, .isolatedVerification)
        let verifierWorkspace = URL(fileURLWithPath: try XCTUnwrap(verifier.workspacePath))
        XCTAssertNotEqual(verifierWorkspace.path, directory.path)
        try Data("temporary\n".utf8).write(
            to: verifierWorkspace.appendingPathComponent("runtime-output.txt")
        )

        let integration = await coordinator.integrate(task: parent, node: verifier)
        XCTAssertEqual(integration, .noChanges)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("runtime-output.txt").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: verifierWorkspace.path))
    }

    func testExplicitMainGraphModelRunsBeforeFixedRecoveryPriority() {
        let preferred = AgentSelection.local(
            profile: .efficientAgent,
            access: .fullAccess
        )
        let codex = AgentSelection.codex(
            model: "gpt-latest",
            displayName: "GPT Latest",
            reasoning: "high",
            access: .fullAccess
        )

        let ordered = AuxiliaryModelRouter.orderedSelections(
            codex: codex,
            apiConnections: [],
            localProfiles: [.advancedVisualAuditor],
            preferred: preferred
        )

        XCTAssertEqual(ordered.map(\.provider), [.local, .codex, .local])
        XCTAssertEqual(ordered.first?.modelID, preferred.modelID)
        XCTAssertTrue(ordered.allSatisfy { $0.accessMode == .readOnly })
    }

    func testRecoveredGraphExcludesOfflineTimeAndReturnsWorkingNodeToWaiting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(storageURL: storage)
        var persisted = task(workspace: directory.path, status: .running)
        var working = node(id: "work", scopes: ["Sources"])
        working.status = .running
        working.accumulatedActiveSeconds = 11
        working.activeStartedAt = Date().addingTimeInterval(-600)
        persisted.executionMode = .autoGraph
        persisted.graphState = state(nodes: [working], supportsWorktrees: false)
        store.add(persisted)

        let restored = TaskStore(storageURL: storage)
        let recovered = try XCTUnwrap(restored.tasks.first)
        let recoveredNode = try XCTUnwrap(recovered.graphState?.nodes.first)

        XCTAssertEqual(recovered.status, .paused)
        XCTAssertEqual(recoveredNode.status, .waiting)
        XCTAssertNil(recoveredNode.activeStartedAt)
        XCTAssertEqual(recoveredNode.accumulatedActiveSeconds, 11)
        XCTAssertTrue(recoveredNode.logs.last?.message.contains("Offline time was excluded") == true)
    }

    func testDependentWorktreeInheritsIntegratedUncommittedGraphState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeGraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("base.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "base"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        XCTAssertTrue(capability.supportsParallelWorktrees)
        let parent = task(workspace: directory.path, status: .running)

        var first = node(id: "first", scopes: ["first.txt"])
        first = try await coordinator.prepare(
            task: parent,
            node: first,
            capability: capability
        )
        let firstWorkspace = try XCTUnwrap(first.workspacePath)
        try Data("first\n".utf8).write(
            to: URL(fileURLWithPath: firstWorkspace).appendingPathComponent("first.txt")
        )
        let firstIntegration = await coordinator.integrate(task: parent, node: first)
        XCTAssertEqual(firstIntegration, .applied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("first.txt").path))

        var second = node(id: "second", scopes: ["second.txt"], dependencies: ["first"])
        second = try await coordinator.prepare(
            task: parent,
            node: second,
            capability: capability
        )
        let secondWorkspace = try XCTUnwrap(second.workspacePath)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: secondWorkspace).appendingPathComponent("first.txt").path
            )
        )
        try Data("second\n".utf8).write(
            to: URL(fileURLWithPath: secondWorkspace).appendingPathComponent("second.txt")
        )
        let secondIntegration = await coordinator.integrate(task: parent, node: second)
        XCTAssertEqual(secondIntegration, .applied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("first.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second.txt").path))

        var scoped = node(id: "scoped", scopes: ["Allowed"])
        scoped = try await coordinator.prepare(
            task: parent,
            node: scoped,
            capability: capability
        )
        let scopedWorkspace = URL(fileURLWithPath: try XCTUnwrap(scoped.workspacePath))
        try Data("unsafe\n".utf8).write(
            to: scopedWorkspace.appendingPathComponent("outside-scope.txt")
        )
        let scopedIntegration = await coordinator.integrate(task: parent, node: scoped)
        guard case .conflict(let detail) = scopedIntegration else {
            return XCTFail("Expected an out-of-scope write to require sequential integration.")
        }
        XCTAssertTrue(detail.contains("outside its declared"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("outside-scope.txt").path))
        await coordinator.cleanup(task: parent, node: scoped)
    }

    func testWorktreeIntegrationPreservesBinaryAssetsByteForByte() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeBinaryGraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("base.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "base"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        let parent = task(workspace: directory.path, status: .running)
        var assetNode = node(id: "binary-assets", scopes: ["artifacts"])
        assetNode = try await coordinator.prepare(
            task: parent,
            node: assetNode,
            capability: capability
        )
        let workspace = URL(fileURLWithPath: try XCTUnwrap(assetNode.workspacePath))
        let assetDirectory = workspace.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        let binary = Data((0..<32_768).map { UInt8(($0 * 37) % 256) })
        try binary.write(to: assetDirectory.appendingPathComponent("evidence.png"))

        let integration = await coordinator.integrate(task: parent, node: assetNode)
        XCTAssertEqual(integration, .applied)
        XCTAssertEqual(
            try Data(contentsOf: directory.appendingPathComponent("artifacts/evidence.png")),
            binary
        )
    }

    func testGraphDeliveryReportIncludesNodeEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var completedNode = node(id: "verified-ui", scopes: ["Sources/UI"])
        completedNode.title = "Verify the UI"
        completedNode.objective = "Build and inspect the real interface."
        completedNode.status = .completed
        completedNode.iteration = 2
        completedNode.accumulatedActiveSeconds = 95
        completedNode.lastAgentMessage = "18 tests passed. LOOPFORGE_STATUS: COMPLETE"
        completedNode.lastReview = "Build and visual evidence passed."
        completedNode.logs = [
            TaskLogEntry(
                kind: .command,
                message: "python3 -m unittest\n18 tests passed\nexit code 0"
            )
        ]
        var reportTask = task(workspace: directory.path, status: .auditing)
        reportTask.executionMode = .autoGraph
        reportTask.graphState = state(nodes: [completedNode], supportsWorktrees: true)
        reportTask.reportGenerationProvider = "Codex · Test"
        let audit = AuditResult(
            score: 92,
            passed: true,
            summary: "Verified",
            findings: [],
            nextActions: []
        )

        let path = try CompletionReportGenerator().generate(
            task: reportTask,
            audit: audit,
            snapshot: WorkspaceSnapshot()
        )
        let html = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(html.contains("Graph execution"))
        XCTAssertTrue(html.contains("Verify the UI"))
        XCTAssertTrue(html.contains("Build and visual evidence passed."))
        XCTAssertTrue(html.contains("Auto Graph Loop"))
        XCTAssertTrue(html.contains("18 tests passed"))
        XCTAssertTrue(html.contains("Codex · Test"))
        XCTAssertTrue(html.contains("data-loopforge-report-schema=\"2\""))
    }

    func testParallelCandidatePolicyBoundsCountAndRejectsUnknownWinner() {
        XCTAssertEqual(ParallelCandidatePolicy.normalizedCount(1), 2)
        XCTAssertEqual(ParallelCandidatePolicy.normalizedCount(3), 3)
        XCTAssertEqual(ParallelCandidatePolicy.normalizedCount(99), 8)
        XCTAssertTrue(ParallelCandidatePolicy.validWinner(
            "candidate-2",
            completedCandidateIDs: ["candidate-1", "candidate-2", "candidate-3"]
        ))
        XCTAssertFalse(ParallelCandidatePolicy.validWinner(
            "candidate-9",
            completedCandidateIDs: ["candidate-1", "candidate-2", "candidate-3"]
        ))
    }

    func testParallelCandidateCodexTurnDisablesHiddenFanout() {
        var candidateTask = task(workspace: "/tmp", status: .running)
        candidateTask.executionMode = .parallelCandidates
        let arguments = CodexRunner().initialArguments(task: candidateTask)

        XCTAssertTrue(arguments.contains("multi_agent"))
        XCTAssertTrue(arguments.contains("multi_agent_v2"))
        XCTAssertTrue(arguments.contains("enable_fanout"))
    }

    func testCandidateCapabilityInitializesOnlyAnEmptyProject() async throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeCandidateEmpty-\(UUID().uuidString)", isDirectory: true)
        let nonempty = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeCandidateNonempty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nonempty, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: empty)
            try? FileManager.default.removeItem(at: nonempty)
        }
        try Data("user work\n".utf8).write(to: nonempty.appendingPathComponent("existing.txt"))

        let coordinator = GraphWorkspaceCoordinator()
        let emptyCapability = await coordinator.candidateCapability(workspacePath: empty.path)
        let nonemptyCapability = await coordinator.candidateCapability(workspacePath: nonempty.path)

        XCTAssertTrue(emptyCapability.supportsParallelWorktrees)
        XCTAssertTrue(FileManager.default.fileExists(atPath: empty.appendingPathComponent(".git").path))
        XCTAssertFalse(nonemptyCapability.supportsParallelWorktrees)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonempty.appendingPathComponent(".git").path))
    }

    func testParallelCandidateWorktreeKeepsOnlyAppliedResult() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeCandidateWinner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("product.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "base"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.candidateCapability(workspacePath: directory.path)
        var parent = task(workspace: directory.path, status: .running)
        parent.executionMode = .parallelCandidates
        var winner = node(id: "candidate-1", scopes: ["."])
        var loser = node(id: "candidate-2", scopes: ["."])
        winner = try await coordinator.prepare(task: parent, node: winner, capability: capability)
        loser = try await coordinator.prepare(task: parent, node: loser, capability: capability)
        try Data("winner\n".utf8).write(
            to: URL(fileURLWithPath: try XCTUnwrap(winner.workspacePath))
                .appendingPathComponent("product.txt")
        )
        try Data("loser\n".utf8).write(
            to: URL(fileURLWithPath: try XCTUnwrap(loser.workspacePath))
                .appendingPathComponent("product.txt")
        )

        let winnerIntegration = await coordinator.integrate(task: parent, node: winner)
        XCTAssertEqual(winnerIntegration, .applied)
        let resumedIntegration = await coordinator.integrate(task: parent, node: winner)
        XCTAssertEqual(
            resumedIntegration,
            .applied,
            "Replaying a selected winner after its worktree was cleaned must recognize the already-applied patch."
        )
        await coordinator.cleanup(task: parent, node: loser)
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("product.txt"), encoding: .utf8),
            "winner\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(loser.isolationRootPath)))
    }

    func testParallelCandidateReportExplainsComparisonAndWinner() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeCandidateReport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var first = node(id: "candidate-1", scopes: ["."])
        first.status = .completed
        first.completedAt = Date()
        first.lastReview = "Passed independent review."
        var second = node(id: "candidate-2", scopes: ["."])
        second.status = .completed
        second.completedAt = Date()
        second.lastReview = "Passed independent review."
        var reportTask = task(workspace: directory.path, status: .completed)
        reportTask.executionMode = .parallelCandidates
        reportTask.parallelCandidateCount = 2
        reportTask.parallelSelectionMode = .agent
        reportTask.selectedCandidateID = "candidate-2"
        reportTask.parallelSelectionSummary = "Candidate 2 had stronger verification."
        reportTask.graphState = state(nodes: [first, second], supportsWorktrees: true)

        let path = try CompletionReportGenerator().generate(
            task: reportTask,
            audit: AuditResult(
                score: 95,
                passed: true,
                summary: "Verified winner",
                findings: [],
                nextActions: []
            ),
            snapshot: WorkspaceSnapshot()
        )
        let html = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(html.contains("Parallel Candidates"))
        XCTAssertTrue(html.contains("Candidate comparison"))
        XCTAssertTrue(html.contains("Candidate performance"))
        XCTAssertTrue(html.contains("total candidate work"))
    }

    private func node(
        id: String,
        scopes: [String],
        dependencies: [String] = []
    ) -> GraphLoopNode {
        GraphLoopNode(
            id: id,
            title: id.capitalized,
            objective: "Complete \(id)",
            dependencies: dependencies,
            writeScopes: scopes,
            verification: ["Verify \(id)"],
            readOnly: scopes.isEmpty,
            status: .waiting,
            iteration: 0,
            accumulatedActiveSeconds: 0,
            accumulatedBlockedSeconds: 0,
            activeStartedAt: nil,
            blockedAt: nil,
            threadID: nil,
            workspacePath: nil,
            isolationRootPath: nil,
            workspaceStrategy: nil,
            integrationBaseCommit: nil,
            currentInstruction: "Complete \(id)",
            lastAgentMessage: "",
            lastReview: "",
            consecutiveFailures: 0,
            createdAt: Date(),
            completedAt: nil,
            logs: []
        )
    }

    private func state(
        nodes: [GraphLoopNode],
        supportsWorktrees: Bool
    ) -> GraphLoopState {
        GraphLoopState(
            phase: .executing,
            planSummary: "Test graph",
            nodes: nodes,
            mainInteractionCount: 0,
            mainLastReview: "",
            maxConcurrentNodes: 3,
            supportsParallelWorktrees: supportsWorktrees,
            finalRepairRounds: 0,
            createdAt: Date(),
            completedAt: nil
        )
    }

    private func markAuditedAndIntegrated(_ node: inout GraphLoopNode) {
        node.status = .completed
        node.completedAt = Date()
        node.lastReview = "Main Graph Agent approved retained evidence and integration."
    }

    private func iterationPrompt(_ number: Int, _ instruction: String) -> String {
        """
        NODE: Test

        CURRENT MAIN-GRAPH INSTRUCTION (iteration \(number)):
        \(instruction)

        DECLARED WRITE SCOPES:
        Sources
        """
    }

    private func task(workspace: String, status: LoopTaskStatus) -> LoopTask {
        let now = Date()
        return LoopTask(
            id: UUID(),
            title: "Graph Test",
            request: "Complete a bounded graph test.",
            quality: .lightweight,
            category: .script,
            workspacePath: workspace,
            targetSeconds: 0,
            accumulatedCodexSeconds: 0,
            model: .visualAuditor,
            status: status,
            stage: "Graph",
            iteration: 0,
            threadID: nil,
            auditScore: 0,
            auditSummary: "",
            lastAgentMessage: "",
            consecutiveFailures: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            logs: [],
            executionMode: .autoGraph
        )
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            XCTFail(message)
            throw NSError(domain: "GraphLoopTests.git", code: Int(process.terminationStatus))
        }
    }
}
