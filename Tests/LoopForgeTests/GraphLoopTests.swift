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

    func testPlanNormalizationRejectsNarrativeWriteScopeInsteadOfWideningIt() {
        let proposal = GraphPlanNodeProposal(
            id: "repair-community",
            title: "Repair Community",
            objective: "Repair the measured Community entry delay.",
            dependencies: [],
            writeScopes: [
                "iOS client files related to the Community entry point",
                "docs/us-graph-round1-audit.md"
            ],
            verification: ["Run the focused response deadline test."],
            readOnly: false
        )

        XCTAssertTrue(
            GraphPlanPolicy.normalizedNodes([proposal]).isEmpty,
            "Narrative scope text must fail before a writer is launched; retaining only the doc path would produce an impossible contract."
        )
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
        XCTAssertTrue(GraphSchedulingPolicy.writeScopesOverlap(
            ["EasyBusiness/**"],
            ["EasyBusiness/AppStore.swift"]
        ))
        XCTAssertTrue(GraphDeclaredScopePolicy.allows(
            changedPath: "EasyBusiness/AppStore.swift",
            declaredScopes: ["EasyBusiness/**"],
            relativeWorkspace: ""
        ))
        XCTAssertTrue(GraphDeclaredScopePolicy.allows(
            changedPath: "NestedProject/EasyBusiness/AppStore.swift",
            declaredScopes: ["EasyBusiness/**"],
            relativeWorkspace: "NestedProject"
        ))
        XCTAssertFalse(GraphDeclaredScopePolicy.allows(
            changedPath: "backend/app/service.py",
            declaredScopes: ["EasyBusiness/**"],
            relativeWorkspace: ""
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

    func testOnlyApprovedIsolatedNodesEnterIntegrationRecovery() {
        var approved = node(id: "approved-integration", scopes: ["Sources"])
        approved.status = .blocked
        approved.workspaceStrategy = .gitWorktree
        approved.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Complete the bounded work.",
                startedAt: Date(),
                finishedAt: Date(),
                threadID: "approved-thread",
                exitCode: 0,
                agentSummary: "LOOPFORGE_STATUS: COMPLETE",
                mainReview: "Approved with retained evidence.",
                nextInstruction: "",
                decision: .approved,
                activeSeconds: 12
            )
        ]

        XCTAssertTrue(GraphIntegrationRecoveryPolicy.requiresRecovery(approved))

        approved.iterationHistory?[0].decision = .continueWork
        XCTAssertFalse(GraphIntegrationRecoveryPolicy.requiresRecovery(approved))

        approved.iterationHistory?[0].decision = .approved
        approved.status = .completed
        XCTAssertFalse(GraphIntegrationRecoveryPolicy.requiresRecovery(approved))
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

    func testNodeTimingSeparatesAllIterationsFromLiveCurrentIteration() {
        let now = Date(timeIntervalSince1970: 10_000)
        var current = node(id: "current", scopes: [])
        current.status = .running
        current.iteration = 3
        current.accumulatedActiveSeconds = 120
        current.activeStartedAt = now.addingTimeInterval(-15)
        current.iterationHistory = [
            GraphNodeIterationRecord(
                number: 3,
                instruction: "Verify the current candidate.",
                startedAt: now.addingTimeInterval(-60),
                finishedAt: nil,
                threadID: "thread-3",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending,
                activeSeconds: 45
            )
        ]

        XCTAssertEqual(current.liveCurrentIterationActiveSeconds(at: now), 60)
        XCTAssertEqual(current.liveActiveSeconds(at: now), 180)

        current.activeStartedAt = nil
        current.accumulatedActiveSeconds = 180
        current.iterationHistory?[0].activeSeconds = 60
        current.iterationHistory?[0].finishedAt = now
        current.iterationHistory?[0].decision = .approved

        XCTAssertEqual(current.liveCurrentIterationActiveSeconds(at: now), 60)
        XCTAssertEqual(current.liveActiveSeconds(at: now), 180)
    }

    func testNodeTimingIncludesRejectedIterationsInAllIterationsTotal() {
        let now = Date(timeIntervalSince1970: 20_000)
        var current = node(id: "rejected-timing", scopes: [])
        current.status = .blocked
        current.iteration = 1
        current.accumulatedActiveSeconds = 0
        current.activeStartedAt = nil
        current.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Verify the candidate.",
                startedAt: now.addingTimeInterval(-1_100),
                finishedAt: now,
                threadID: "thread-1",
                exitCode: 0,
                agentSummary: "Evidence retained.",
                mainReview: "Continue with a bounded repair.",
                nextInstruction: "Instrument the slow interaction.",
                decision: .continueWork,
                activeSeconds: 1_058.7054460048676
            )
        ]

        XCTAssertEqual(
            current.liveCurrentIterationActiveSeconds(at: now),
            1_058.7054460048676
        )
        XCTAssertEqual(
            current.liveActiveSeconds(at: now),
            1_058.7054460048676
        )

        current.status = .running
        current.iteration = 2
        current.activeStartedAt = now.addingTimeInterval(-10)
        current.iterationHistory?.append(
            GraphNodeIterationRecord(
                number: 2,
                instruction: "Instrument the slow interaction.",
                startedAt: now.addingTimeInterval(-10),
                finishedAt: nil,
                threadID: "thread-2",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending,
                activeSeconds: 0
            )
        )

        XCTAssertEqual(current.liveCurrentIterationActiveSeconds(at: now), 10)
        XCTAssertEqual(
            current.liveActiveSeconds(at: now),
            1_068.7054460048676
        )
    }

    func testLegacyIterationTimingDecodesWithoutActiveSeconds() throws {
        let record = GraphNodeIterationRecord(
            number: 1,
            instruction: "Inspect.",
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_030),
            threadID: "legacy",
            exitCode: 0,
            agentSummary: "Done.",
            mainReview: "Approved.",
            nextInstruction: "",
            decision: .approved,
            activeSeconds: 30
        )
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "activeSeconds")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(GraphNodeIterationRecord.self, from: legacy)
        XCTAssertNil(decoded.activeSeconds)
        XCTAssertEqual(decoded.decision, .approved)
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
                    writeScopes: ["Sources/A"],
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

    func testRedundantFinalRepairRetirementNeverRefundsDurableBudgets() throws {
        var completed = node(id: "completed-frontier", scopes: [])
        markAuditedAndIntegrated(&completed)
        let repairA = node(
            id: "repair-first-gap",
            scopes: ["Sources/A"],
            dependencies: [completed.id]
        )
        let repairB = node(
            id: "repair-second-gap",
            scopes: ["Sources/B"],
            dependencies: [completed.id]
        )
        var graph = state(
            nodes: [completed, repairA, repairB],
            supportsWorktrees: true
        )
        graph.finalRepairRounds = GraphPlanPolicy.maximumFinalRepairRounds
        let retiredAt = Date(timeIntervalSince1970: 4_200)

        let retirement = GraphPlanPolicy.retiringRedundantPendingRepairs(
            in: graph,
            at: retiredAt
        )

        XCTAssertEqual(
            retirement.retiredNodeIDs,
            ["repair-first-gap", "repair-second-gap"]
        )
        XCTAssertEqual(
            retirement.graph.finalRepairRounds,
            GraphPlanPolicy.maximumFinalRepairRounds,
            "Retiring two nodes from one repair round must not refund two rounds—or any round."
        )
        XCTAssertEqual(retirement.graph.nodes.count, 3)
        XCTAssertEqual(retirement.graph.supersededNodeCount, 2)
        XCTAssertEqual(
            retirement.graph.nodes
                .filter { $0.id.hasPrefix("repair-") }
                .map(\.supersededAt),
            [retiredAt, retiredAt]
        )
        XCTAssertTrue(
            retirement.graph.nodes
                .filter { $0.id.hasPrefix("repair-") }
                .allSatisfy {
                    $0.strategyLesson == GraphPlanPolicy.defaultRetiredStrategyLesson
                },
            "Every new retirement must persist an anti-repeat lesson for final review and crash replay."
        )
        XCTAssertFalse(GraphPlanPolicy.canCreateFinalRepair(in: retirement.graph))

        let encoded = try JSONEncoder().encode(retirement.graph)
        let restored = try JSONDecoder().decode(GraphLoopState.self, from: encoded)
        XCTAssertEqual(
            restored.finalRepairRounds,
            GraphPlanPolicy.maximumFinalRepairRounds
        )
        XCTAssertEqual(restored.nodes.count, 3)
        XCTAssertEqual(restored.supersededNodeCount, 2)
        XCTAssertFalse(
            GraphPlanPolicy.canCreateFinalRepair(in: restored),
            "Crash/relaunch replay must remain exhausted after redundant branch cleanup."
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
        graph.nodes[0].strategyEscalationRequired = true
        graph.nodes[0].strategyLesson = "Do not repeat the retired artifact search."
        graph.nodes[0].strategyDecision = GraphExhaustedNodeAction.reframe.rawValue
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
        XCTAssertEqual(restored.nodes[0].strategyEscalationRequired, true)
        XCTAssertEqual(
            restored.nodes[0].strategyLesson,
            "Do not repeat the retired artifact search."
        )
        XCTAssertEqual(restored.nodes[0].strategyDecision, "reframe")
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
        nodeObjects[0].removeValue(forKey: "strategyEscalationRequired")
        nodeObjects[0].removeValue(forKey: "strategyLesson")
        nodeObjects[0].removeValue(forKey: "strategyDecision")
        object["nodes"] = nodeObjects
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacy = try decoder.decode(GraphLoopState.self, from: legacyData)
        XCTAssertNil(legacy.reviewedJoinGroupIDs)
        XCTAssertNil(legacy.incrementallyReviewedNodeIDs)
        XCTAssertNil(legacy.nodes[0].joinGroupID)
        XCTAssertNil(legacy.nodes[0].replacesNodeIDs)
        XCTAssertNil(legacy.nodes[0].iterationHistory)
        XCTAssertNil(legacy.nodes[0].strategyEscalationRequired)
        XCTAssertNil(legacy.nodes[0].strategyLesson)
        XCTAssertNil(legacy.nodes[0].strategyDecision)
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
                    writeScopes: ["Sources"],
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

    func testConservativeFinalRepairFallbackPreservesAuthorizedScopeAndDropsUnsafeDependencies() throws {
        var baseline = node(id: "integrated-baseline", scopes: [])
        markAuditedAndIntegrated(&baseline)
        var retired = node(id: "repair-1", scopes: ["backend"])
        retired.status = .superseded
        retired.objective = "Align the canonical branch to the published repair."
        retired.currentInstruction = retired.objective
        retired.dependencies = ["integrated-baseline"]
        retired.strategyLesson = "Canonical alignment is now complete; do not repeat it."
        let unsafe = GraphPlanNodeProposal(
            id: "repair-1",
            title: "Unify the report entry path",
            objective: retired.objective,
            dependencies: ["future-report-verification"],
            writeScopes: ["backend/reporting"],
            verification: ["Run the report contract and native failure-state path."],
            readOnly: false
        )

        XCTAssertTrue(
            GraphPlanPolicy.finalRepairBatchNodes(
                [unsafe],
                existingNodes: [baseline, retired]
            ).isEmpty,
            "The reviewer's future dependency must remain fail-closed."
        )

        let fallback = try XCTUnwrap(GraphPlanPolicy.conservativeFinalRepairProposal(
            proposed: [unsafe],
            reviewerSummary: "The latest final audit found a new report-entry defect.",
            nextInstruction: "",
            verification: ["Run the whole-project path."],
            existingNodes: [baseline, retired],
            finalRepairRounds: 0
        ))
        XCTAssertEqual(fallback.id, "repair-2")
        XCTAssertEqual(fallback.dependencies, [])
        XCTAssertEqual(fallback.writeScopes, ["backend/reporting"])
        XCTAssertEqual(
            fallback.objective,
            "The latest final audit found a new report-entry defect."
        )
        XCTAssertEqual(fallback.verification, unsafe.verification)

        let repairs = GraphPlanPolicy.finalRepairBatchNodes(
            [fallback],
            existingNodes: [baseline, retired]
        )
        XCTAssertEqual(repairs.map(\.id), ["repair-2"])
        XCTAssertEqual(repairs[0].dependencies, ["integrated-baseline"])
    }

    func testFinalRepairScopeCannotBeInventedOrWidenedByReviewer() {
        var writer = node(id: "bounded-writer", scopes: ["Sources/Feature"])
        markAuditedAndIntegrated(&writer)

        func proposal(scopes: [String]?, readOnly: Bool = false) -> GraphPlanNodeProposal {
            GraphPlanNodeProposal(
                id: "repair",
                title: "Repair",
                objective: "Repair the audited bounded gap.",
                dependencies: [],
                writeScopes: scopes,
                verification: ["Run the bounded verification."],
                readOnly: readOnly
            )
        }

        XCTAssertNil(GraphPlanPolicy.conservativeFinalRepairProposal(
            proposed: [],
            reviewerSummary: "Repair required.",
            nextInstruction: "Repair it.",
            verification: ["Verify"],
            existingNodes: [writer],
            finalRepairRounds: 0
        ))
        for scopes in [[], ["."], ["Sources"], ["../Sources"], ["the relevant source files"]] {
            XCTAssertFalse(GraphPlanPolicy.finalRepairScopeIsAuthorized(
                proposal(scopes: scopes),
                existingNodes: [writer]
            ))
            XCTAssertTrue(GraphPlanPolicy.finalRepairBatchNodes(
                [proposal(scopes: scopes)],
                existingNodes: [writer]
            ).isEmpty)
        }
        XCTAssertTrue(GraphPlanPolicy.finalRepairScopeIsAuthorized(
            proposal(scopes: ["Sources/Feature/Subtree"]),
            existingNodes: [writer]
        ))
        XCTAssertTrue(GraphPlanPolicy.finalRepairScopeIsAuthorized(
            proposal(scopes: [], readOnly: true),
            existingNodes: [writer]
        ))
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
                    writeScopes: ["pulseboard/static"],
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
        XCTAssertEqual(
            CodexAccessMode.nativeWorkerSelectableCases,
            [.readOnly, .workspaceOnly, .fullAccess]
        )
        XCTAssertEqual(
            CodexAccessMode.independentReviewerSelectableCases,
            [.readOnly]
        )
    }

    func testParallelWriterPreservesExplicitFullAccessAcrossNodeObjectives() {
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
            .fullAccess
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

    func testReadOnlyHandoffNodeRequiresDisposableRuntime() {
        var evidenceNode = node(id: "evidence", scopes: [])
        evidenceNode.readOnly = true
        evidenceNode.objective = "Write the validated JSON to US_R1_HANDOFF."

        XCTAssertTrue(GraphVerificationPolicy.requiresDisposableRuntime(for: evidenceNode))
    }

    func testBlockedWorkerTurnDoesNotCountAsSuccessfulRuntime() {
        let blocked = CodexTurnResult(
            exitCode: 0,
            elapsed: 120,
            eligibleElapsed: 117,
            threadID: "thread",
            lastAgentMessage: "LOOPFORGE_STATUS: BLOCKED\nNo writable scratch.",
            commandSuccesses: 4,
            commandFailures: 1,
            stderr: "",
            eventErrors: [],
            recoveryReason: nil
        )
        let completed = CodexTurnResult(
            exitCode: 0,
            elapsed: 120,
            eligibleElapsed: 117,
            threadID: "thread",
            lastAgentMessage: "LOOPFORGE_STATUS: COMPLETE\nVerified.",
            commandSuccesses: 5,
            commandFailures: 0,
            stderr: "",
            eventErrors: [],
            recoveryReason: nil
        )

        XCTAssertFalse(GraphWorkerRuntimePolicy.countsAsSuccessfulWork(blocked))
        XCTAssertTrue(GraphWorkerRuntimePolicy.countsAsSuccessfulWork(completed))
        XCTAssertEqual(
            GraphWorkerRuntimePolicy.reviewAdjustment(for: blocked, approved: true),
            117
        )
        XCTAssertEqual(
            GraphWorkerRuntimePolicy.reviewAdjustment(for: completed, approved: false),
            -117
        )
        XCTAssertEqual(
            GraphWorkerRuntimePolicy.reviewAdjustment(for: completed, approved: true),
            0
        )
    }

    func testRuntimePathVariablesAreDiscoveredFromNodeContract() {
        XCTAssertEqual(
            Set(CodexRunner.requestedRuntimePathVariables(
                in: "Write US_R1_HANDOFF and compare US_R1_BEFORE_STATUS with US_R1_AFTER_STATUS."
            )),
            Set(["US_R1_HANDOFF", "US_R1_BEFORE_STATUS", "US_R1_AFTER_STATUS"])
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

    func testGraphDoesNotRepeatAProvenExternalCapabilityBoundary() {
        let guidance = GraphCompletionPolicy.disclosedGapGuidance
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        XCTAssertTrue(guidance.contains("external operating dependency"))
        XCTAssertTrue(guidance.contains("bounded capability or evidence audit is complete"))
        XCTAssertTrue(guidance.contains("do not reject, reschedule, or repeatedly probe"))
        XCTAssertTrue(guidance.contains("feasible local preparation remains incomplete"))
    }

    func testRejectedNodeReviewDecodesExactScopeRecoveryWithoutAddingWork() throws {
        let raw = #"{"approved":false,"summary":"Readiness is still wrong.","nextInstruction":"Repair readiness.","verification":["Run health tests"],"addedNodes":[],"requiredWriteScopes":["backend/app/main.py","backend/tests/test_api_health.py"]}"#

        let decoded = try XCTUnwrap(
            GraphLoopEngine.decode(GraphNodeReviewEnvelope.self, from: raw)
        )

        XCTAssertFalse(decoded.approved)
        XCTAssertEqual(decoded.addedNodes, [])
        XCTAssertEqual(
            decoded.requiredWriteScopes,
            ["backend/app/main.py", "backend/tests/test_api_health.py"]
        )
    }

    func testNodeScopeRecoveryAcceptsOnlyDisjointPreciseRepositoryPaths() {
        var current = node(id: "provider", scopes: ["backend/app/provider.py"])
        current.joinGroupID = "frontier-2"
        var sibling = node(id: "finance", scopes: ["backend/app/schemas.py"])
        sibling.joinGroupID = "frontier-2"
        let graph = state(nodes: [current, sibling], supportsWorktrees: true)

        let decision = GraphNodeScopeRecoveryPolicy.decision(
            requestedScopes: [
                "./backend/app/main.py",
                "backend/tests/test_api_health.py/",
                ".",
                "../outside",
                "backend/app/schemas.py"
            ],
            currentNode: current,
            state: graph
        )

        XCTAssertEqual(
            decision.acceptedScopes,
            ["backend/app/main.py", "backend/tests/test_api_health.py"]
        )
        XCTAssertEqual(
            decision.rejectedScopes,
            [".", "../outside", "backend/app/schemas.py"]
        )
    }

    func testThreeConsecutiveBlockedTurnsRequireReplanInsteadOfAnotherRetry() {
        let start = Date(timeIntervalSince1970: 1_000)
        var current = node(id: "blocked", scopes: ["backend/app/provider.py"])
        current.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Implement.",
                startedAt: start,
                finishedAt: start.addingTimeInterval(10),
                threadID: "one",
                exitCode: 0,
                agentSummary: "LOOPFORGE_STATUS: BLOCKED\nMissing scope.",
                mainReview: "Continue.",
                nextInstruction: "Repair readiness.",
                decision: .continueWork
            ),
            GraphNodeIterationRecord(
                number: 2,
                instruction: "Repair readiness.",
                startedAt: start.addingTimeInterval(20),
                finishedAt: start.addingTimeInterval(30),
                threadID: "two",
                exitCode: 0,
                agentSummary: "LOOPFORGE_STATUS: BLOCKED\nThe same scope is missing.",
                mainReview: "Continue.",
                nextInstruction: "Repair readiness.",
                decision: .continueWork
            ),
            GraphNodeIterationRecord(
                number: 3,
                instruction: "Repair readiness.",
                startedAt: start.addingTimeInterval(40),
                finishedAt: nil,
                threadID: "three",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending
            )
        ]

        XCTAssertTrue(
            GraphRejectedTurnPolicy.shouldStopRetrying(
                node: current,
                currentAgentSummary: "LOOPFORGE_STATUS: BLOCKED\nStill missing scope."
            )
        )
        XCTAssertFalse(
            GraphRejectedTurnPolicy.shouldStopRetrying(
                node: current,
                currentAgentSummary: "Implemented and verified the requested change."
            )
        )

        current.threadID = "blocked-causal-route"
        GraphRejectedTurnPolicy.freezeForRepeatedBlockerReview(
            &current,
            at: start.addingTimeInterval(50)
        )
        XCTAssertEqual(current.status, .blocked)
        XCTAssertTrue(GraphRejectedTurnPolicy.isAutomaticRetryDisabled(current))
        XCTAssertEqual(current.strategyEscalationRequired, true)
        XCTAssertNil(current.threadID)
        XCTAssertTrue(GraphNodeStrategyEscalationPolicy.requiresStrategyReview(current))
        XCTAssertEqual(
            GraphNodeStrategyEscalationPolicy.pendingNodeID(
                in: state(nodes: [current], supportsWorktrees: true)
            ),
            current.id
        )
    }

    func testTerminallyBlockedNodeKeepsProductiveSiblingRunningAndStaysFrozenAfterRelaunch() {
        var frozen = node(id: "missing-artifact", scopes: [])
        frozen.status = .blocked
        frozen.automaticRetryDisabled = true
        var productive = node(id: "financial-contracts", scopes: ["Sources/Reports"])
        productive.status = .running
        var graph = state(nodes: [frozen, productive], supportsWorktrees: true)

        XCTAssertTrue(GraphRejectedTurnPolicy.isAutomaticRetryDisabled(frozen))
        XCTAssertTrue(
            GraphRejectedTurnPolicy.hasViablePeer(
                afterFreezing: frozen.id,
                state: graph
            ),
            "A terminal blocker in one branch must not cancel a productive sibling."
        )

        productive.status = .completed
        productive.completedAt = Date()
        productive.lastReview = "Approved and integrated."
        graph.nodes[1] = productive
        XCTAssertFalse(
            GraphRejectedTurnPolicy.hasViablePeer(
                afterFreezing: frozen.id,
                state: graph
            ),
            "A graph with no running or ready peer still needs an explicit Main Graph replan."
        )

        frozen.automaticRetryDisabled = nil
        frozen.logs.append(TaskLogEntry(
            kind: .warning,
            message: "Stopped after 3 consecutive blocked turns with no safe scope recovery. The same node will not be relaunched automatically."
        ))
        frozen.status = .waiting
        frozen.logs.append(TaskLogEntry(
            kind: .warning,
            message: "Recovered the task checkpoint after relaunch."
        ))
        XCTAssertTrue(
            GraphRejectedTurnPolicy.isAutomaticRetryDisabled(frozen),
            "Older checkpoints must stay frozen even after status normalization and later recovery warnings."
        )
        XCTAssertTrue(GraphRejectedTurnPolicy.hasRepeatedBlockerStopProvenance(frozen))
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(frozen),
            "A legacy repeated-blocker warning is durable exhausted-budget provenance, not an ordinary retry pause."
        )
        XCTAssertFalse(GraphRejectedTurnPolicy.shouldResumeAfterExplicitReplan(frozen))

        frozen.planAdjustment = "Capture fresh product screenshots from the current integrated HEAD."
        XCTAssertFalse(
            GraphRejectedTurnPolicy.shouldResumeAfterExplicitReplan(frozen),
            "A plan adjustment cannot reactivate the same node after its repeated-blocker budget is exhausted."
        )
        frozen.threadID = "rejected-historical-artifact-thread"
        GraphRejectedTurnPolicy.applyExplicitReplan(
            to: &frozen,
            replacementPlan: frozen.planAdjustment ?? ""
        )
        XCTAssertEqual(frozen.status, .blocked)
        XCTAssertTrue(GraphRejectedTurnPolicy.isAutomaticRetryDisabled(frozen))
        XCTAssertEqual(frozen.strategyEscalationRequired, true)
        XCTAssertEqual(frozen.threadID, "rejected-historical-artifact-thread")

        var replannable = node(id: "ordinary-terminal-pause", scopes: [])
        replannable.status = .blocked
        replannable.automaticRetryDisabled = true
        replannable.planAdjustment = "Capture fresh product screenshots from the current integrated HEAD."
        replannable.threadID = "ordinary-rejected-thread"
        XCTAssertTrue(
            GraphRejectedTurnPolicy.shouldResumeAfterExplicitReplan(replannable),
            "An ordinary non-exhausted pause may still consume one explicit bounded replacement plan."
        )
        GraphRejectedTurnPolicy.applyExplicitReplan(
            to: &replannable,
            replacementPlan: replannable.planAdjustment ?? ""
        )
        XCTAssertEqual(replannable.status, .waiting)
        XCTAssertFalse(GraphRejectedTurnPolicy.isAutomaticRetryDisabled(replannable))
        XCTAssertNil(
            replannable.threadID,
            "A replacement plan must not inherit the rejected turn's reasoning context."
        )
        XCTAssertEqual(replannable.replacementPlanStartedFreshThread, true)
        XCTAssertEqual(
            replannable.replacementPlanContractVersion,
            GraphRejectedTurnPolicy.currentReplacementContractVersion
        )
        XCTAssertFalse(GraphRejectedTurnPolicy.requiresFreshThreadMigration(replannable))
        XCTAssertEqual(
            replannable.currentInstruction,
            "MAIN GRAPH REPLACEMENT PLAN:\nCapture fresh product screenshots from the current integrated HEAD."
        )

        var build117Checkpoint = replannable
        build117Checkpoint.threadID = "stale-build-117-thread"
        build117Checkpoint.replacementPlanStartedFreshThread = nil
        build117Checkpoint.replacementPlanContractVersion = nil
        XCTAssertTrue(
            GraphRejectedTurnPolicy.requiresFreshThreadMigration(build117Checkpoint),
            "A persisted build-117 replacement plan must detach from its stale thread exactly once."
        )
        GraphRejectedTurnPolicy.applyExplicitReplan(
            to: &build117Checkpoint,
            replacementPlan: build117Checkpoint.planAdjustment ?? ""
        )
        XCTAssertNil(build117Checkpoint.threadID)
        XCTAssertFalse(GraphRejectedTurnPolicy.requiresFreshThreadMigration(build117Checkpoint))
        XCTAssertTrue(
            GraphActiveNodeContractPolicy.hasAuthoritativeReplacement(build117Checkpoint)
        )
        XCTAssertEqual(
            GraphActiveNodeContractPolicy.activeObjective(for: build117Checkpoint),
            "Capture fresh product screenshots from the current integrated HEAD."
        )
        let replacementVerification =
            GraphActiveNodeContractPolicy.verificationGuidance(for: build117Checkpoint)
        XCTAssertTrue(replacementVerification.contains("replacement outcome"))
        XCTAssertTrue(replacementVerification.contains("incompatible clauses are superseded"))

        var build118Checkpoint = build117Checkpoint
        build118Checkpoint.threadID = "fresh-but-conflicting-build-118-thread"
        build118Checkpoint.replacementPlanStartedFreshThread = true
        build118Checkpoint.replacementPlanContractVersion = nil
        XCTAssertTrue(GraphRejectedTurnPolicy.requiresFreshThreadMigration(build118Checkpoint))
        GraphRejectedTurnPolicy.applyExplicitReplan(
            to: &build118Checkpoint,
            replacementPlan: build118Checkpoint.planAdjustment ?? ""
        )
        XCTAssertNil(build118Checkpoint.threadID)
        XCTAssertEqual(
            build118Checkpoint.replacementPlanContractVersion,
            GraphRejectedTurnPolicy.currentReplacementContractVersion
        )
    }

    func testCanonicalWorkspaceTransitionRequiresImmediateStructuralReplan() {
        var isolated = node(id: "published-repair", scopes: ["."])
        isolated.workspaceStrategy = .gitWorktree
        isolated.isolationRootPath = "/tmp/loopforge-isolated-repair"

        XCTAssertTrue(
            GraphRejectedTurnPolicy.requiresCanonicalWorkspaceTransition(
                node: isolated,
                nextInstruction: "Rematerialize this node with its actual WORKSPACE/cwd bound to the canonical EasyBusiness worktree."
            )
        )
        isolated.currentInstruction = "Rematerialize this node with its actual WORKSPACE/cwd bound to the canonical EasyBusiness worktree."
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(isolated),
            "A persisted immutable-cwd transition must enter structural review immediately after relaunch."
        )
        XCTAssertTrue(
            GraphRejectedTurnPolicy.requiresCanonicalWorkspaceTransition(
                node: isolated,
                nextInstruction: "将节点实际 environment_context.cwd 物化为目标工作树，再完成收口。"
            )
        )
        XCTAssertFalse(
            GraphRejectedTurnPolicy.requiresCanonicalWorkspaceTransition(
                node: isolated,
                nextInstruction: "Inspect the canonical API contract from the current isolated workspace."
            ),
            "Merely mentioning canonical product behavior must not force a workspace transition."
        )
    }

    func testSeventhUnapprovedCycleRequiresStructuralStrategyReview() {
        let start = Date(timeIntervalSince1970: 2_000)
        var exhausted = node(id: "stalled-evidence", scopes: [".loopforge/evidence"])
        exhausted.iteration = 7
        exhausted.status = .waiting
        var records: [GraphNodeIterationRecord] = []
        for number in 1...6 {
            let startedAt = start.addingTimeInterval(Double(number * 20))
            let finishedAt = start.addingTimeInterval(Double(number * 20 + 10))
            let summary = number.isMultiple(of: 2)
                ? "LOOPFORGE_STATUS: BLOCKED\nNo new evidence."
                : "The result remains incomplete."
            records.append(GraphNodeIterationRecord(
                number: number,
                instruction: "Repeat unavailable evidence path \(number).",
                startedAt: startedAt,
                finishedAt: finishedAt,
                threadID: "thread-\(number)",
                exitCode: 0,
                agentSummary: summary,
                mainReview: "The same gap remains.",
                nextInstruction: "Try the same evidence path again.",
                decision: .continueWork
            ))
        }
        records.append(GraphNodeIterationRecord(
            number: 7,
            instruction: "Resume the replacement plan.",
            startedAt: start.addingTimeInterval(200),
            finishedAt: nil,
            threadID: "pending-seven",
            exitCode: nil,
            agentSummary: "",
            mainReview: "",
            nextInstruction: "",
            decision: .pending
        ))
        exhausted.iterationHistory = records

        XCTAssertEqual(
            GraphNodeStrategyEscalationPolicy.unapprovedDecisionCount(exhausted),
            6
        )
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(exhausted)
        )
        XCTAssertEqual(
            GraphNodeStrategyEscalationPolicy.pendingNodeID(
                in: state(nodes: [exhausted], supportsWorktrees: true)
            ),
            exhausted.id
        )
    }

    func testExhaustedNodeCannotConsumeAnotherExplicitPlanAdjustment() {
        var exhausted = node(id: "stalled", scopes: [])
        exhausted.status = .blocked
        exhausted.iteration = 7
        exhausted.strategyEscalationRequired = true
        exhausted.automaticRetryDisabled = true
        exhausted.threadID = "must-not-resume"
        exhausted.planAdjustment = "Try the same objective from a new thread."

        XCTAssertFalse(GraphRejectedTurnPolicy.shouldResumeAfterExplicitReplan(exhausted))
        GraphRejectedTurnPolicy.applyExplicitReplan(
            to: &exhausted,
            replacementPlan: exhausted.planAdjustment ?? ""
        )

        XCTAssertEqual(exhausted.status, .blocked)
        XCTAssertTrue(GraphRejectedTurnPolicy.isAutomaticRetryDisabled(exhausted))
        XCTAssertEqual(exhausted.strategyEscalationRequired, true)
        XCTAssertEqual(exhausted.threadID, "must-not-resume")
    }

    func testResumeFreezeNeverReactivatesCompletedOrSupersededHistory() {
        var blocked = node(id: "blocked", scopes: [])
        blocked.status = .blocked
        blocked.automaticRetryDisabled = true
        XCTAssertTrue(GraphRejectedTurnPolicy.shouldRemainFrozenOnResume(blocked))

        var superseded = blocked
        superseded.status = .superseded
        superseded.supersededAt = Date(timeIntervalSince1970: 1_000)
        superseded.planAdjustment = "A stale historical replacement plan."
        XCTAssertFalse(
            GraphRejectedTurnPolicy.shouldRemainFrozenOnResume(superseded),
            "Resume normalization must not turn retired graph history back into an active blocker."
        )
        XCTAssertFalse(
            GraphRejectedTurnPolicy.shouldResumeAfterExplicitReplan(superseded),
            "A plan adjustment cannot reactivate a node with terminal superseded provenance."
        )
        XCTAssertFalse(GraphNodeStrategyEscalationPolicy.requiresStrategyReview(superseded))

        var completed = blocked
        completed.status = .completed
        completed.completedAt = Date(timeIntervalSince1970: 1_100)
        XCTAssertFalse(GraphRejectedTurnPolicy.shouldRemainFrozenOnResume(completed))
    }

    func testCorruptWaitingStatusRestoresFromSupersededProvenance() {
        var corrupted = node(id: "retired-history", scopes: [])
        corrupted.status = .waiting
        corrupted.supersededAt = Date(timeIntervalSince1970: 2_000)
        corrupted.automaticRetryDisabled = true
        corrupted.planAdjustment = "Stale adjustment that must never run."
        corrupted.iteration = 7

        XCTAssertTrue(GraphRejectedTurnPolicy.shouldRestoreSupersededHistory(corrupted))
        XCTAssertFalse(GraphRejectedTurnPolicy.shouldResumeAfterExplicitReplan(corrupted))
        XCTAssertFalse(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(corrupted),
            "Durable terminal provenance must prevent another Main retirement review even when an older status was corrupted."
        )
    }

    func testStructuralReplacementUsesNewNodeAndRejectsRetiredContract() {
        var exhausted = node(id: "old-screenshots", scopes: [".loopforge/evidence"])
        exhausted.objective = "Recover the two missing historical PNG byte objects."
        exhausted.currentInstruction = exhausted.objective
        exhausted.verification = ["Compare every historical PNG byte for byte."]
        exhausted.dependencies = ["baseline"]
        exhausted.joinGroupID = "frontier-4"

        let duplicate = GraphPlanNodeProposal(
            id: "same-work-new-id",
            title: "Same work",
            objective: exhausted.objective,
            dependencies: [],
            writeScopes: [".loopforge/evidence"],
            verification: exhausted.verification,
            readOnly: false
        )
        XCTAssertFalse(
            GraphNodeStrategyEscalationPolicy.isMateriallyDifferent(
                duplicate,
                from: exhausted
            )
        )
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.replacementNodes(
                from: [duplicate],
                action: .replace,
                exhaustedNode: exhausted,
                existingNodes: [node(id: "baseline", scopes: []), exhausted]
            ).isEmpty
        )

        let replacement = GraphPlanNodeProposal(
            id: "audit-current-product-evidence",
            title: "Audit current product evidence",
            objective: "Independently audit already captured current-HEAD product evidence and document only reproducible coverage boundaries.",
            dependencies: [],
            writeScopes: [],
            verification: ["Hash and decode retained current-HEAD evidence without recovering historical objects."],
            readOnly: true
        )
        let nodes = GraphNodeStrategyEscalationPolicy.replacementNodes(
            from: [replacement],
            action: .reframe,
            exhaustedNode: exhausted,
            existingNodes: [node(id: "baseline", scopes: []), exhausted]
        )

        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].id, "audit-current-product-evidence")
        XCTAssertEqual(nodes[0].iteration, 0)
        XCTAssertNil(nodes[0].threadID)
        XCTAssertEqual(nodes[0].dependencies, ["baseline"])
        XCTAssertEqual(nodes[0].joinGroupID, "frontier-4")
        XCTAssertEqual(nodes[0].replacesNodeIDs, [exhausted.id])
    }

    func testStructuralReplacementRejectsParaphraseWhenCausalRouteIsUnchanged() {
        var exhausted = node(id: "same-route", scopes: ["Sources/Feature/**"])
        exhausted.objective = "Replace the failing implementation and rerun its focused check."
        exhausted.verification = ["Run the focused check."]

        let paraphrase = GraphPlanNodeProposal(
            id: "fresh-id-and-wording",
            title: "Try a newly worded repair",
            objective: "Rework the broken feature using a substantially improved implementation.",
            dependencies: [],
            writeScopes: ["./Sources/Feature"],
            verification: ["Execute that same focused verification again."],
            readOnly: false
        )
        XCTAssertFalse(
            GraphNodeStrategyEscalationPolicy.isMateriallyDifferent(
                paraphrase,
                from: exhausted
            ),
            "New prose and a fresh ID cannot prove a new causal strategy when the mutation route is unchanged."
        )
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.replacementNodes(
                from: [paraphrase],
                action: .replace,
                exhaustedNode: exhausted,
                existingNodes: [exhausted]
            ).isEmpty
        )

        let changedSurface = GraphPlanNodeProposal(
            id: "bounded-subtree-repair",
            title: "Repair a bounded subtree",
            objective: "Repair the independently isolated subtree.",
            dependencies: [],
            writeScopes: ["Sources/Feature", "Sources/Feature/Subtree"],
            verification: ["Verify the bounded subtree."],
            readOnly: false
        )
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.isMateriallyDifferent(
                changedSurface,
                from: exhausted
            ),
            "A mechanically observable mutation-topology change remains eligible for one bounded replacement."
        )
    }

    func testStructuralReplacementNormalizesScopeNoiseAndRejectsMalformedTopology() {
        let exhausted = node(
            id: "normalized-route",
            scopes: ["Sources/A", "Sources/B/**"]
        )
        let reordered = GraphPlanNodeProposal(
            id: "scope-noise",
            title: "Reordered scopes",
            objective: "Use reordered and duplicated spellings.",
            dependencies: [],
            writeScopes: ["./Sources/B", "Sources/A/**", "Sources/A"],
            verification: ["Repeat the same route."],
            readOnly: false
        )
        XCTAssertFalse(
            GraphNodeStrategyEscalationPolicy.isMateriallyDifferent(
                reordered,
                from: exhausted
            )
        )

        for invalidScope in [
            "/tmp/escape",
            "../outside",
            "files related to the broken feature"
        ] {
            let malformed = GraphPlanNodeProposal(
                id: "invalid-\(invalidScope)",
                title: "Malformed route",
                objective: "Attempt a replacement with an untrusted route.",
                dependencies: [],
                writeScopes: [invalidScope],
                verification: ["Run a check."],
                readOnly: false
            )
            XCTAssertFalse(
                GraphNodeStrategyEscalationPolicy.isMateriallyDifferent(
                    malformed,
                    from: exhausted
                ),
                "Malformed, escaping, or narrative scope descriptions must fail closed."
            )
        }
    }

    func testStalePendingContinuationRequiresStructuralReplanBeforeRelaunch() {
        let start = Date(timeIntervalSince1970: 1_000)
        var stale = node(id: "integration-evidence", scopes: ["Evidence/**"])
        stale.status = .waiting
        stale.iteration = 2
        stale.currentInstruction = "Repeat the full integration evidence run."
        stale.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: "Repeat the full integration evidence run.",
                startedAt: start,
                finishedAt: start.addingTimeInterval(1_058),
                threadID: "old-thread",
                exitCode: 0,
                agentSummary: "Completed, but the Community tap took 980 seconds.",
                mainReview: "The tap latency is unexplained.",
                nextInstruction: "Time the Community tap itself and repair only its root cause.",
                decision: .continueWork,
                activeSeconds: 1_058
            ),
            GraphNodeIterationRecord(
                number: 2,
                instruction: "Repeat the full integration evidence run.",
                startedAt: start.addingTimeInterval(1_100),
                finishedAt: nil,
                threadID: "old-thread",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending,
                activeSeconds: 320
            )
        ]

        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.hasStalePendingContinuation(stale)
        )
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(stale),
            "A relaunch must retire the stale cycle before the old instruction can run again."
        )

        var corrected = stale
        corrected.iterationHistory?[1].instruction =
            "Time the Community tap itself and repair only its root cause."
        XCTAssertFalse(
            GraphNodeStrategyEscalationPolicy.hasStalePendingContinuation(corrected)
        )
    }

    func testPendingWriterWithNarrativeScopesRequiresStructuralReplan() {
        var invalid = node(
            id: "repair-community-entry",
            scopes: [
                "iOS client files related to Community",
                "docs/us-graph-round1-audit.md"
            ]
        )
        invalid.status = .waiting
        invalid.iteration = 1
        invalid.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: invalid.objective,
                startedAt: Date(timeIntervalSince1970: 1_000),
                finishedAt: nil,
                threadID: "invalid-scope-thread",
                exitCode: nil,
                agentSummary: "",
                mainReview: "",
                nextInstruction: "",
                decision: .pending,
                activeSeconds: 59
            )
        ]

        XCTAssertTrue(GraphPlanPolicy.hasNarrativeWriteScope(invalid.writeScopes))
        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(invalid),
            "A persisted invalid-scope replacement must be intercepted before its thread resumes."
        )
    }

    func testStructuralReplacementMayAdoptUnexecutedTargetedNextInstruction() {
        let start = Date(timeIntervalSince1970: 2_000)
        var retired = node(id: "evidence-only", scopes: ["Evidence/**"])
        retired.objective = "Integrate and publish the existing runtime evidence."
        retired.currentInstruction = retired.objective
        retired.iterationHistory = [
            GraphNodeIterationRecord(
                number: 1,
                instruction: retired.objective,
                startedAt: start,
                finishedAt: start.addingTimeInterval(20),
                threadID: "evidence-thread",
                exitCode: 0,
                agentSummary: "The Community tap latency needs a product repair.",
                mainReview: "Repair requires a product source scope outside this node.",
                nextInstruction: "Diagnose and repair the Community tap root cause.",
                decision: .continueWork,
                activeSeconds: 20
            )
        ]

        let repair = GraphPlanNodeProposal(
            id: "repair-community-tap-latency",
            title: "Repair Community tap latency",
            objective: "Diagnose and repair the Community tap root cause.",
            dependencies: [],
            writeScopes: ["EasyBusiness/**", "EasyBusinessUITests/**"],
            verification: ["Bound the tap call and rerun only Community and Friends."],
            readOnly: false
        )

        XCTAssertTrue(
            GraphNodeStrategyEscalationPolicy.isMateriallyDifferent(repair, from: retired),
            "A targeted instruction that was proposed but never executed must remain eligible under a fresh safe scope."
        )
    }

    func testStructuralReplacementAtomicallyRewiresUnstartedDependents() {
        var exhausted = node(id: "old-strategy", scopes: [])
        exhausted.status = .blocked
        var dependent = node(id: "later-consumer", scopes: [])
        dependent.status = .waiting
        dependent.dependencies = [exhausted.id, "stable-baseline"]

        let rewired = GraphNodeStrategyEscalationPolicy.rewiringDependents(
            in: [exhausted, dependent],
            exhaustedNodeID: exhausted.id,
            replacementNodeIDs: ["replacement-a", "replacement-b"]
        )

        XCTAssertEqual(
            rewired?.first(where: { $0.id == dependent.id })?.dependencies,
            ["replacement-a", "replacement-b", "stable-baseline"]
        )
    }

    func testStructuralReplacementFailsClosedAfterDependentStarts() {
        var exhausted = node(id: "old-strategy", scopes: [])
        exhausted.status = .blocked
        var dependent = node(id: "active-consumer", scopes: [])
        dependent.status = .running
        dependent.dependencies = [exhausted.id]

        XCTAssertNil(
            GraphNodeStrategyEscalationPolicy.rewiringDependents(
                in: [exhausted, dependent],
                exhaustedNodeID: exhausted.id,
                replacementNodeIDs: ["replacement"]
            )
        )
    }

    func testFinalAuditCannotRecreateRetiredStrategyUnderNewID() {
        var completed = node(id: "integrated-baseline", scopes: [])
        markAuditedAndIntegrated(&completed)
        var retired = node(id: "retired-artifact-search", scopes: [])
        retired.status = .superseded
        retired.objective = "Recover the two missing historical PNG byte objects."
        retired.currentInstruction = retired.objective
        retired.verification = ["Compare every historical PNG byte for byte."]
        retired.strategyLesson = "The historical byte objects are unavailable; do not search for them again."

        let duplicate = GraphPlanNodeProposal(
            id: "repair-with-same-contract",
            title: "Repeat artifact recovery",
            objective: retired.objective,
            dependencies: [],
            writeScopes: [],
            verification: retired.verification,
            readOnly: true
        )
        XCTAssertTrue(
            GraphPlanPolicy.finalRepairBatchNodes(
                [duplicate],
                existingNodes: [completed, retired]
            ).isEmpty
        )

        let different = GraphPlanNodeProposal(
            id: "audit-current-evidence",
            title: "Audit current evidence",
            objective: "Audit only current-HEAD product screenshots already retained in the evidence archive.",
            dependencies: [],
            writeScopes: [],
            verification: ["Decode and hash current-HEAD screenshots without recovering historical bytes."],
            readOnly: true
        )
        XCTAssertTrue(
            GraphPlanPolicy.finalRepairBatchNodes(
                [different],
                existingNodes: [completed, retired]
            ).isEmpty,
            "Different prose and evidence nouns still use the same read-only causal route and cannot revive a retired strategy."
        )
    }

    func testFinalAuditTreatsLegacyLessonlessRetirementAsStrategyTombstone() {
        var completed = node(id: "integrated-baseline", scopes: [])
        markAuditedAndIntegrated(&completed)
        var retired = node(id: "legacy-retired-search", scopes: [])
        retired.status = .waiting
        retired.supersededAt = Date(timeIntervalSince1970: 7_200)
        retired.supersededReason = "Retired by an older incremental review checkpoint."
        retired.strategyLesson = nil

        let renamedDuplicate = GraphPlanNodeProposal(
            id: "fresh-evidence-audit",
            title: "Audit evidence again",
            objective: "Inspect the available screenshots under a new repair identifier.",
            dependencies: [],
            writeScopes: [],
            verification: ["List and inspect the retained screenshot evidence."],
            readOnly: true
        )

        XCTAssertTrue(
            GraphPlanPolicy.finalRepairBatchNodes(
                [renamedDuplicate],
                existingNodes: [completed, retired]
            ).isEmpty,
            "A legacy durable tombstone must remain anti-repeat evidence even when its lesson or terminal status was not fully persisted."
        )
    }

    func testApprovedHistoricalNodeNeverRequiresStrategyEscalation() {
        var completed = node(id: "completed-long-node", scopes: [])
        completed.status = .completed
        completed.iteration = 11
        completed.iterationHistory = [
            GraphNodeIterationRecord(
                number: 11,
                instruction: "Finish.",
                startedAt: Date(),
                finishedAt: Date(),
                threadID: "approved",
                exitCode: 0,
                agentSummary: "Complete.",
                mainReview: "Approved.",
                nextInstruction: "",
                decision: .approved
            )
        ]
        XCTAssertFalse(
            GraphNodeStrategyEscalationPolicy.requiresStrategyReview(completed)
        )
    }

    func testWholeGraphAuditBudgetSupportsMultimodalUltraReviewWithoutUnboundedWait() {
        XCTAssertEqual(GraphReviewBudgetPolicy.finalAuditTimeout, 45 * 60)
        XCTAssertEqual(GraphReviewBudgetPolicy.standardReviewTimeout, 20 * 60)
        XCTAssertGreaterThan(
            GraphReviewBudgetPolicy.finalAuditTimeout,
            GraphReviewBudgetPolicy.standardReviewTimeout
        )
        XCTAssertLessThanOrEqual(GraphReviewBudgetPolicy.finalAuditTimeout, 60 * 60)
        XCTAssertEqual(GraphReviewBudgetPolicy.recoveryReviewTimeout, 5 * 60)
        XCTAssertEqual(GraphReviewBudgetPolicy.reportNarrativeTimeout, 10 * 60)
    }

    func testGraphReviewFailureCannotOverwritePauseOrStopRequest() {
        XCTAssertTrue(GraphRunInterruptionPolicy.shouldStop(
            taskStatus: .pausing,
            engineIsCancelling: false,
            taskIsCancelled: false
        ))
        XCTAssertTrue(GraphRunInterruptionPolicy.shouldStop(
            taskStatus: .stopping,
            engineIsCancelling: false,
            taskIsCancelled: false
        ))
        XCTAssertTrue(GraphRunInterruptionPolicy.shouldStop(
            taskStatus: .auditing,
            engineIsCancelling: true,
            taskIsCancelled: false
        ))
        XCTAssertFalse(GraphRunInterruptionPolicy.shouldStop(
            taskStatus: .auditing,
            engineIsCancelling: false,
            taskIsCancelled: false
        ))
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

    func testWholeGraphDecisionRejectsAnythingExceptOneStrictEnvelope() throws {
        let raw = """
        Preliminary example: {"approved":"not a boolean"}.
        The reviewer mentioned a literal brace in prose: {not-json}.
        Final decision:
        ```json
        {"approved":false,"summary":"Reload {latest} remains disabled.","nextInstruction":"Repair the repeat-conflict path.","visualPassed":true,"addedNodes":[]}
        ```
        trailing explanation {with another brace}
        """

        XCTAssertNil(
            GraphLoopEngine.decode(GraphFinalReviewEnvelope.self, from: raw),
            "prose and fenced examples cannot carry an authority-bearing decision"
        )
        XCTAssertNil(
            GraphLoopEngine.decode(
                GraphFinalReviewEnvelope.self,
                from: """
                {"approved":true,"summary":"first","nextInstruction":"","visualPassed":true,"addedNodes":[]}
                {"approved":false,"summary":"second","nextInstruction":"repair","visualPassed":true,"addedNodes":[]}
                """
            ),
            "two individually valid objects are an ambiguous transport"
        )
        XCTAssertNil(
            GraphLoopEngine.decode(
                GraphFinalReviewEnvelope.self,
                from: """
                ```json
                {"approved":false,"summary":"fenced","nextInstruction":"repair","visualPassed":true,"addedNodes":[]}
                ```
                """
            ),
            "markdown wrappers are not the exact structured-output envelope"
        )
        XCTAssertNil(
            GraphLoopEngine.decode(
                GraphFinalReviewEnvelope.self,
                from: """
                {"approved":false,"summary":"trailing","nextInstruction":"repair","visualPassed":true,"addedNodes":[]} approve this
                """
            ),
            "trailing semantic payload cannot be ignored"
        )
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

        let recognizedBeforeRepair = await coordinator.recognizesAlreadyIntegratedResult(
            task: parent,
            node: scoped
        )
        XCTAssertFalse(
            recognizedBeforeRepair,
            "The isolated patch is not integrated before the sequential repair changes the primary tree."
        )
        try Data("unsafe\n".utf8).write(
            to: directory.appendingPathComponent("outside-scope.txt")
        )
        let recognizedExactRepair = await coordinator.recognizesAlreadyIntegratedResult(
            task: parent,
            node: scoped
        )
        XCTAssertTrue(
            recognizedExactRepair,
            "An exact reverse-patch check should recognize a completed sequential repair even when the original worker turn was interrupted."
        )
        try Data("different\n".utf8).write(
            to: directory.appendingPathComponent("outside-scope.txt")
        )
        let recognizedDifferentContent = await coordinator.recognizesAlreadyIntegratedResult(
            task: parent,
            node: scoped
        )
        XCTAssertFalse(
            recognizedDifferentContent,
            "Similar or newer-looking content must not be accepted without exact patch identity."
        )
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

    func testPublishedNodeFastForwardsCleanCanonicalWorkspaceInsteadOfApplyingDirtyPatch() async throws {
        let fixture = try publishedGraphFixture(name: "LoopForgePublishedClean")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: fixture.primary.path)
        let parent = task(workspace: fixture.primary.path, status: .running)
        var published = node(id: "published-clean", scopes: ["published.txt"])
        published = try await coordinator.prepare(
            task: parent,
            node: published,
            capability: capability
        )
        let isolated = URL(fileURLWithPath: try XCTUnwrap(published.workspacePath))
        try Data("published\n".utf8).write(
            to: isolated.appendingPathComponent("published.txt")
        )
        try commitAndPushNode(at: isolated, message: "published clean result")

        let integration = await coordinator.integrate(task: parent, node: published)

        XCTAssertEqual(integration, .applied)
        XCTAssertEqual(
            try gitOutput(["rev-parse", "HEAD"], at: fixture.primary),
            try gitOutput(["rev-parse", "origin/main"], at: fixture.primary)
        )
        XCTAssertEqual(try gitOutput(["status", "--porcelain"], at: fixture.primary), "")
        XCTAssertEqual(
            try String(
                contentsOf: fixture.primary.appendingPathComponent("published.txt"),
                encoding: .utf8
            ),
            "published\n"
        )
    }

    func testPublishedNodeStashesOnlyExactUpstreamDirtyContentBeforeFastForward() async throws {
        let fixture = try publishedGraphFixture(name: "LoopForgePublishedDirty")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("retained prior stash\n".utf8).write(
            to: fixture.primary.appendingPathComponent("prior-stash.txt")
        )
        try runGit(
            ["stash", "push", "--include-untracked", "-m", "pre-existing safety backup"],
            at: fixture.primary
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: fixture.primary.path)
        let parent = task(workspace: fixture.primary.path, status: .running)
        var published = node(
            id: "published-dirty",
            scopes: ["base.txt", "published.txt"]
        )
        published = try await coordinator.prepare(
            task: parent,
            node: published,
            capability: capability
        )
        let isolated = URL(fileURLWithPath: try XCTUnwrap(published.workspacePath))
        try Data("intermediate base\n".utf8).write(
            to: isolated.appendingPathComponent("base.txt")
        )
        try Data("intermediate new file\n".utf8).write(
            to: isolated.appendingPathComponent("published.txt")
        )
        try commitAndPushNode(at: isolated, message: "published intermediate result")

        // Reproduce the coordinator bug: the exact already-published result
        // exists as tracked and untracked dirt in the canonical worktree, but
        // a later published commit changed some of the same paths again.
        try Data("intermediate base\n".utf8).write(
            to: fixture.primary.appendingPathComponent("base.txt")
        )
        try Data("intermediate new file\n".utf8).write(
            to: fixture.primary.appendingPathComponent("published.txt")
        )
        try Data("final upstream base\n".utf8).write(
            to: isolated.appendingPathComponent("base.txt")
        )
        try Data("final upstream new file\n".utf8).write(
            to: isolated.appendingPathComponent("published.txt")
        )
        try commitAndPushNode(at: isolated, message: "published final result")

        let integration = await coordinator.integrate(task: parent, node: published)

        XCTAssertEqual(integration, .applied)
        XCTAssertEqual(try gitOutput(["status", "--porcelain"], at: fixture.primary), "")
        XCTAssertEqual(
            try gitOutput(["rev-parse", "HEAD"], at: fixture.primary),
            try gitOutput(["rev-parse", "origin/main"], at: fixture.primary)
        )
        XCTAssertEqual(
            try String(
                contentsOf: fixture.primary.appendingPathComponent("published.txt"),
                encoding: .utf8
            ),
            "final upstream new file\n"
        )
        let stashes = try gitOutput(["stash", "list"], at: fixture.primary)
        XCTAssertTrue(stashes.contains("published-dirty"))
        XCTAssertTrue(stashes.contains("pre-existing safety backup"))
    }

    func testPublishedNodeRefusesToStashUnrelatedCanonicalDirt() async throws {
        let fixture = try publishedGraphFixture(name: "LoopForgePublishedUnrelated")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalHead = try gitOutput(["rev-parse", "HEAD"], at: fixture.primary)
        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: fixture.primary.path)
        let parent = task(workspace: fixture.primary.path, status: .running)
        var published = node(id: "published-unrelated", scopes: ["published.txt"])
        published = try await coordinator.prepare(
            task: parent,
            node: published,
            capability: capability
        )
        let isolated = URL(fileURLWithPath: try XCTUnwrap(published.workspacePath))
        try Data("published\n".utf8).write(
            to: isolated.appendingPathComponent("published.txt")
        )
        try commitAndPushNode(at: isolated, message: "published result")
        try Data("user-owned unrelated edit\n".utf8).write(
            to: fixture.primary.appendingPathComponent("unrelated.txt")
        )

        let integration = await coordinator.integrate(task: parent, node: published)

        guard case .conflict(let detail) = integration else {
            return XCTFail("Unrelated canonical dirt must fail closed.")
        }
        XCTAssertTrue(detail.contains("unrelated dirty paths"))
        XCTAssertEqual(try gitOutput(["rev-parse", "HEAD"], at: fixture.primary), originalHead)
        XCTAssertEqual(
            try String(
                contentsOf: fixture.primary.appendingPathComponent("unrelated.txt"),
                encoding: .utf8
            ),
            "user-owned unrelated edit\n"
        )
        XCTAssertEqual(try gitOutput(["stash", "list"], at: fixture.primary), "")
        await coordinator.cleanup(task: parent, node: published)
    }

    func testApprovedRecoveryRejectsStaleNodeIDMarkerWithoutCurrentWorktree() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeStaleIntegrationMarker-\(UUID().uuidString)", isDirectory: true)
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
        var firstIteration = node(id: "reused-node-id", scopes: ["allowed.txt"])
        firstIteration = try await coordinator.prepare(
            task: parent,
            node: firstIteration,
            capability: capability
        )
        let firstIntegration = await coordinator.integrate(
            task: parent,
            node: firstIteration
        )
        XCTAssertEqual(firstIntegration, .noChanges)

        var laterIteration = node(id: "reused-node-id", scopes: ["allowed.txt"])
        laterIteration = try await coordinator.prepare(
            task: parent,
            node: laterIteration,
            capability: capability
        )
        let laterWorkspace = URL(
            fileURLWithPath: try XCTUnwrap(laterIteration.workspacePath)
        )
        try Data("outside current scope\n".utf8).write(
            to: laterWorkspace.appendingPathComponent("outside.txt")
        )
        guard case .conflict = await coordinator.integrate(
            task: parent,
            node: laterIteration
        ) else {
            return XCTFail("The later iteration should require conflict-aware integration.")
        }
        await coordinator.cleanup(task: parent, node: laterIteration)

        let recognizedWithoutCurrentWorktree = await coordinator
            .recognizesAlreadyIntegratedResult(task: parent, node: laterIteration)
        XCTAssertFalse(
            recognizedWithoutCurrentWorktree,
            "A no-change marker from an earlier iteration with the same node ID must not approve a later result after its current worktree disappears."
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
        XCTAssertTrue(html.contains("data-loopforge-report-schema=\"3\""))
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

    func testCandidateCapabilityProbeNeverInitializesUserWorkspace() async throws {
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
        let emptyManifestBefore = try FileManager.default.contentsOfDirectory(
            atPath: empty.path
        ).sorted()
        let nonemptyManifestBefore = try FileManager.default.contentsOfDirectory(
            atPath: nonempty.path
        ).sorted()

        let coordinator = GraphWorkspaceCoordinator()
        let emptyCapability = await coordinator.candidateCapability(workspacePath: empty.path)
        let nonemptyCapability = await coordinator.candidateCapability(workspacePath: nonempty.path)

        XCTAssertFalse(emptyCapability.supportsParallelWorktrees)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: empty.path).sorted(),
            emptyManifestBefore,
            "a capability probe must leave an empty user directory byte/file-identical"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty.appendingPathComponent(".git").path))
        XCTAssertFalse(nonemptyCapability.supportsParallelWorktrees)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: nonempty.path).sorted(),
            nonemptyManifestBefore,
            "a capability probe must not add metadata to a non-Git workspace"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonempty.appendingPathComponent(".git").path))
    }

    func testCapabilityProbeDoesNotRefreshCleanRepositoryIndex() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeCapabilityObservation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("baseline\n".utf8).write(to: directory.appendingPathComponent("baseline.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "baseline"
            ],
            at: directory
        )
        let index = directory.appendingPathComponent(".git/index")
        let indexBefore = try Data(contentsOf: index)
        let namesBefore = try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()

        let capability = await GraphWorkspaceCoordinator().capability(
            workspacePath: directory.path
        )

        XCTAssertTrue(capability.supportsParallelWorktrees)
        XCTAssertEqual(try Data(contentsOf: index), indexBefore)
        XCTAssertEqual(
            try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted(),
            namesBefore
        )
    }

    func testNonGitParallelCandidateUsesOwnedRepositoryAndAppliesWinner() async throws {
        let canonical = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeOwnedCandidate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: canonical) }
        let product = canonical.appendingPathComponent("product.txt")
        try Data("baseline\n".utf8).write(to: product)
        let namesBefore = try FileManager.default.subpathsOfDirectory(atPath: canonical.path).sorted()
        let baselineBefore = try Data(contentsOf: product)

        var parent = task(workspace: canonical.path, status: .running)
        parent.executionMode = .parallelCandidates
        let coordinator = GraphWorkspaceCoordinator()
        defer { coordinator.cleanupOwnedCandidateRepository(task: parent) }

        let capability = try await coordinator.prepareOwnedCandidateCapability(task: parent)
        XCTAssertTrue(capability.supportsParallelWorktrees)
        XCTAssertTrue(capability.loopForgeOwned)
        let ownedRoot = try XCTUnwrap(capability.gitRoot)
        XCTAssertFalse(ownedRoot.hasPrefix(canonical.path + "/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.appendingPathComponent(".git").path))
        XCTAssertEqual(try Data(contentsOf: product), baselineBefore)
        XCTAssertEqual(
            try FileManager.default.subpathsOfDirectory(atPath: canonical.path).sorted(),
            namesBefore
        )

        var winner = node(id: "owned-winner", scopes: ["."])
        winner = try await coordinator.prepare(
            task: parent,
            node: winner,
            capability: capability
        )
        XCTAssertEqual(winner.workspaceStrategy, .gitWorktree)
        let winnerRoot = URL(fileURLWithPath: try XCTUnwrap(winner.workspacePath))
        try Data("winner\n".utf8).write(to: winnerRoot.appendingPathComponent("product.txt"))
        try Data([0x00, 0xFF, 0x41]).write(to: winnerRoot.appendingPathComponent("asset.bin"))

        let integration = await coordinator.integrate(task: parent, node: winner)
        XCTAssertEqual(integration, .applied)
        XCTAssertEqual(try Data(contentsOf: product), Data("winner\n".utf8))
        XCTAssertEqual(
            try Data(contentsOf: canonical.appendingPathComponent("asset.bin")),
            Data([0x00, 0xFF, 0x41])
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.appendingPathComponent(".git").path))

        coordinator.cleanupOwnedCandidateRepository(task: parent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ownedRoot))
    }

    func testOwnedCandidateIsolationFailureLeavesNoRepositoryOrCanonicalMutation() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeMissingCandidate-\(UUID().uuidString)", isDirectory: true)
        var parent = task(workspace: missing.path, status: .running)
        parent.executionMode = .parallelCandidates
        let ownerRoot = TaskStore.applicationSupportDirectory()
            .appendingPathComponent("GraphOwnedRepositories", isDirectory: true)
            .appendingPathComponent(parent.id.uuidString.lowercased(), isDirectory: true)
        try? FileManager.default.removeItem(at: ownerRoot)
        defer { try? FileManager.default.removeItem(at: ownerRoot) }

        do {
            _ = try await GraphWorkspaceCoordinator().prepareOwnedCandidateCapability(
                task: parent
            )
            XCTFail("missing canonical input must fail before candidate launch")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: ownerRoot.path))
        }
    }

    func testIsolatedScopeGateRejectsUndeclaredPathsBeforeReview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeScopeGate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("Sources/base.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "baseline"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        let parent = task(workspace: directory.path, status: .running)
        var isolated = node(id: "scope-gate", scopes: ["Sources"])
        isolated = try await coordinator.prepare(
            task: parent,
            node: isolated,
            capability: capability
        )
        let root = URL(fileURLWithPath: try XCTUnwrap(isolated.workspacePath))
        try Data("allowed\n".utf8).write(to: root.appendingPathComponent("Sources/allowed.txt"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Outside"),
            withIntermediateDirectories: true
        )
        let escapedName = "Outside/line\nbreak.bin"
        try Data([0x00, 0x7F]).write(to: root.appendingPathComponent(escapedName))

        let validation = await coordinator.validateDeclaredChanges(node: isolated)
        await coordinator.cleanup(task: parent, node: isolated)
        guard case .violated(let paths) = validation else {
            return XCTFail("undeclared isolated mutation must fail before model review")
        }
        XCTAssertEqual(paths, [escapedName])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(escapedName).path
            )
        )
    }

    func testIsolatedScopeGateAcceptsCompleteAllowedDeltaAndFailsWhenMissing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeScopeGateAllowed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try Data("base\n".utf8).write(to: directory.appendingPathComponent("Sources/base.txt"))
        try runGit(["init"], at: directory)
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "baseline"
            ],
            at: directory
        )

        let coordinator = GraphWorkspaceCoordinator()
        let capability = await coordinator.capability(workspacePath: directory.path)
        let parent = task(workspace: directory.path, status: .running)
        var isolated = node(id: "scope-gate-allowed", scopes: ["Sources"])
        isolated = try await coordinator.prepare(
            task: parent,
            node: isolated,
            capability: capability
        )
        let root = URL(fileURLWithPath: try XCTUnwrap(isolated.workspacePath))
        try Data("changed\n".utf8).write(to: root.appendingPathComponent("Sources/base.txt"))
        try Data("new\n".utf8).write(to: root.appendingPathComponent("Sources/new.txt"))

        let valid = await coordinator.validateDeclaredChanges(node: isolated)
        XCTAssertEqual(
            valid,
            .valid(changedPaths: ["Sources/base.txt", "Sources/new.txt"])
        )
        await coordinator.cleanup(task: parent, node: isolated)
        let missing = await coordinator.validateDeclaredChanges(node: isolated)
        guard case .unavailable = missing else {
            return XCTFail("missing isolation must fail closed before review")
        }
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
        XCTAssertTrue(html.contains("verified candidate time"))
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

    private func publishedGraphFixture(name: String) throws -> (
        root: URL,
        remote: URL,
        primary: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        let remote = root.appendingPathComponent("origin.git", isDirectory: true)
        let seed = root.appendingPathComponent("seed", isDirectory: true)
        let primary = root.appendingPathComponent("primary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try runGit(["init", "--bare", "--initial-branch=main", remote.path], at: root)
        try FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try runGit(["init", "--initial-branch=main"], at: seed)
        try Data("base\n".utf8).write(to: seed.appendingPathComponent("base.txt"))
        try Data("unchanged\n".utf8).write(to: seed.appendingPathComponent("unrelated.txt"))
        try runGit(["add", "-A"], at: seed)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", "base"
            ],
            at: seed
        )
        try runGit(["remote", "add", "origin", remote.path], at: seed)
        try runGit(["push", "-u", "origin", "main"], at: seed)
        try runGit(["clone", "--branch", "main", remote.path, primary.path], at: root)
        return (root, remote, primary)
    }

    private func commitAndPushNode(at directory: URL, message: String) throws {
        try runGit(["add", "-A"], at: directory)
        try runGit(
            [
                "-c", "user.name=LoopForge Tests",
                "-c", "user.email=tests@localhost",
                "commit", "-m", message
            ],
            at: directory
        )
        try runGit(["push", "origin", "HEAD:main"], at: directory)
    }

    private func gitOutput(_ arguments: [String], at directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
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
        return (String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
