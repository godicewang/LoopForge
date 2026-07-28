import AppKit
import Foundation

struct GraphPlanNodeProposal: Codable, Equatable {
    let id: String
    let title: String
    let objective: String
    let dependencies: [String]?
    let writeScopes: [String]?
    let verification: [String]?
    let readOnly: Bool?
    let joinGroup: String?
    let replacesNodeIDs: [String]?

    init(
        id: String,
        title: String,
        objective: String,
        dependencies: [String]?,
        writeScopes: [String]?,
        verification: [String]?,
        readOnly: Bool?,
        joinGroup: String? = nil,
        replacesNodeIDs: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.objective = objective
        self.dependencies = dependencies
        self.writeScopes = writeScopes
        self.verification = verification
        self.readOnly = readOnly
        self.joinGroup = joinGroup
        self.replacesNodeIDs = replacesNodeIDs
    }
}

struct GraphPlanEnvelope: Codable, Equatable {
    let summary: String
    let nodes: [GraphPlanNodeProposal]
}

struct GraphNodeReviewEnvelope: Codable, Equatable {
    let approved: Bool
    let summary: String
    let nextInstruction: String
    let verification: [String]?
    let addedNodes: [GraphPlanNodeProposal]?
}

struct GraphFinalReviewEnvelope: Codable, Equatable {
    let approved: Bool
    let summary: String
    let nextInstruction: String
    let visualPassed: Bool?
    let addedNodes: [GraphPlanNodeProposal]?

    init(
        approved: Bool,
        summary: String,
        nextInstruction: String,
        visualPassed: Bool?,
        addedNodes: [GraphPlanNodeProposal]?
    ) {
        self.approved = approved
        self.summary = summary
        self.nextInstruction = nextInstruction
        self.visualPassed = visualPassed
        self.addedNodes = addedNodes
    }

    private enum CodingKeys: String, CodingKey {
        case approved
        case summary
        case nextInstruction
        case visualPassed
        case addedNodes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        approved = try values.decode(Bool.self, forKey: .approved)
        summary = try values.decode(String.self, forKey: .summary)
        nextInstruction = try values.decodeIfPresent(String.self, forKey: .nextInstruction) ?? ""
        visualPassed = try values.decodeIfPresent(Bool.self, forKey: .visualPassed)
        addedNodes = try values.decodeIfPresent([GraphPlanNodeProposal].self, forKey: .addedNodes)
    }
}

struct ParallelCandidateSelectionEnvelope: Codable, Equatable {
    let winnerID: String
    let summary: String
    let rankedCandidateIDs: [String]
}

enum ParallelCandidatePolicy {
    static let minimumCount = 2
    static let maximumCount = 8

    static func normalizedCount(_ count: Int) -> Int {
        min(maximumCount, max(minimumCount, count))
    }

    static func validWinner(
        _ winnerID: String,
        completedCandidateIDs: [String]
    ) -> Bool {
        completedCandidateIDs.contains(winnerID)
    }
}

struct GraphBatchTransitionEnvelope: Codable, Equatable {
    let readyForFinalAudit: Bool
    let summary: String
    let nextNodes: [GraphPlanNodeProposal]
}

struct GraphNodePlanAdjustment: Codable, Equatable {
    let nodeID: String
    let instruction: String
    let verification: [String]?
}

/// A conservative, evidence-backed decision made after one member of a join
/// group completes. Empty actions are the normal result; graph churn is never
/// required merely because an incremental review ran.
struct GraphIncrementalJoinReviewEnvelope: Codable, Equatable {
    let summary: String
    let retireNodeIDs: [String]
    let adjustments: [GraphNodePlanAdjustment]
    let addedNodes: [GraphPlanNodeProposal]

    private enum CodingKeys: String, CodingKey {
        case summary
        case retireNodeIDs
        case adjustments
        case addedNodes
    }

    init(
        summary: String,
        retireNodeIDs: [String] = [],
        adjustments: [GraphNodePlanAdjustment] = [],
        addedNodes: [GraphPlanNodeProposal] = []
    ) {
        self.summary = summary
        self.retireNodeIDs = retireNodeIDs
        self.adjustments = adjustments
        self.addedNodes = addedNodes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        summary = try values.decodeIfPresent(String.self, forKey: .summary)
            ?? "No plan change is justified by the completed evidence."
        retireNodeIDs = try values.decodeIfPresent([String].self, forKey: .retireNodeIDs) ?? []
        adjustments = try values.decodeIfPresent([GraphNodePlanAdjustment].self, forKey: .adjustments) ?? []
        addedNodes = try values.decodeIfPresent([GraphPlanNodeProposal].self, forKey: .addedNodes) ?? []
    }
}

enum GraphPlanPolicy {
    static let maximumNodes = 32

    static func normalizedNodes(
        _ proposals: [GraphPlanNodeProposal],
        existingIDs: Set<String> = []
    ) -> [GraphLoopNode] {
        let now = Date()
        var used = existingIDs
        var aliases: [String: String] = [:]
        var normalized: [(proposal: GraphPlanNodeProposal, id: String)] = []

        for (index, proposal) in proposals.prefix(maximumNodes - existingIDs.count).enumerated() {
            let sourceID = proposal.id.trimmingCharacters(in: .whitespacesAndNewlines)
            var candidate = safeID(sourceID.isEmpty ? "node-\(index + 1)" : sourceID)
            if candidate.isEmpty { candidate = "node-\(index + 1)" }
            var unique = candidate
            var suffix = 2
            while used.contains(unique) {
                unique = "\(candidate)-\(suffix)"
                suffix += 1
            }
            used.insert(unique)
            aliases[sourceID] = unique
            aliases[candidate] = unique
            normalized.append((proposal, unique))
        }

        let allIDs = Set(normalized.map(\.id)).union(existingIDs)
        return normalized.map { item in
            let dependencies = (item.proposal.dependencies ?? [])
                .compactMap { dependency -> String? in
                    let trimmed = dependency.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolved = aliases[trimmed]
                        ?? (existingIDs.contains(trimmed) ? trimmed : safeID(trimmed))
                    return resolved != item.id && allIDs.contains(resolved) ? resolved : nil
                }
                .uniqued()
            let declaredScopes = (item.proposal.writeScopes ?? [])
                .map(normalizedScope)
                .filter { !$0.isEmpty }
                .uniqued()
            let isReadOnly = item.proposal.readOnly ?? false
            let scopes = isReadOnly
                ? []
                : (declaredScopes.isEmpty ? ["."] : declaredScopes)
            return GraphLoopNode(
                id: item.id,
                title: concise(item.proposal.title, fallback: item.id, limit: 54),
                objective: item.proposal.objective.trimmingCharacters(in: .whitespacesAndNewlines),
                dependencies: dependencies,
                writeScopes: scopes,
                verification: (item.proposal.verification ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                readOnly: isReadOnly,
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
                currentInstruction: item.proposal.objective,
                lastAgentMessage: "",
                lastReview: "",
                consecutiveFailures: 0,
                createdAt: now,
                completedAt: nil,
                logs: [],
                joinGroupID: normalizedJoinGroup(item.proposal.joinGroup),
                replacesNodeIDs: item.proposal.replacesNodeIDs
            )
        }
    }

    static func isAcyclic(_ nodes: [GraphLoopNode]) -> Bool {
        let map = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.dependencies) })
        var visiting = Set<String>()
        var visited = Set<String>()

        func visit(_ id: String) -> Bool {
            if visited.contains(id) { return true }
            if !visiting.insert(id).inserted { return false }
            for dependency in map[id] ?? [] where map[dependency] != nil {
                if !visit(dependency) { return false }
            }
            visiting.remove(id)
            visited.insert(id)
            return true
        }

        return nodes.allSatisfy { visit($0.id) }
    }

    static func fallbackNodes(for task: LoopTask) -> [GraphLoopNode] {
        assigningDefaultJoinGroup(
            normalizedNodes([
                GraphPlanNodeProposal(
                    id: "inspect",
                    title: "Inspect and map the real project",
                    objective: "Inspect the real workspace, reproduce the primary path, map requirements to current code and evidence, and retain a concise implementation brief. Do not modify product files.",
                    dependencies: [],
                    writeScopes: [],
                    verification: ["Cite concrete files, commands, failures, and acceptance gaps."],
                    readOnly: true
                )
            ]),
            defaultID: "frontier-1"
        )
    }

    /// The Main Graph Agent may create only the first predecessor-free
    /// frontier at task start. Dependent proposals are discarded rather than
    /// silently converted into root work.
    static func initialBatchNodes(_ proposals: [GraphPlanNodeProposal]) -> [GraphLoopNode] {
        let roots = proposals.filter {
            ($0.dependencies ?? []).allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        return assigningDefaultJoinGroup(
            independentImmediateNodes(normalizedNodes(roots), limit: 3),
            defaultID: "frontier-1"
        )
    }

    /// Materializes one immediate batch after the preceding batch has fully
    /// passed Main Graph review. New nodes may depend only on audited nodes
    /// from that just-finished frontier; they cannot depend on one another or
    /// encode a future batch.
    static func nextBatchNodes(
        _ proposals: [GraphPlanNodeProposal],
        existingNodes: [GraphLoopNode],
        predecessorIDs: [String]
    ) -> [GraphLoopNode] {
        let existingIDs = Set(existingNodes.map(\.id))
        let allowedPredecessors = predecessorIDs.filter(existingIDs.contains).uniqued()
        guard !allowedPredecessors.isEmpty else { return [] }
        let allowedSet = Set(allowedPredecessors)
        let immediate = proposals.compactMap { proposal -> GraphPlanNodeProposal? in
            let rawDependencies = (proposal.dependencies ?? []).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let declared = rawDependencies.compactMap {
                resolveDependencyReference($0, candidates: allowedPredecessors)
            }.uniqued()
            guard declared.count == rawDependencies.count else { return nil }
            guard declared.allSatisfy(allowedSet.contains) else {
                return nil
            }
            return GraphPlanNodeProposal(
                id: proposal.id,
                title: proposal.title,
                objective: proposal.objective,
                dependencies: declared.isEmpty ? allowedPredecessors : declared,
                writeScopes: proposal.writeScopes,
                verification: proposal.verification,
                readOnly: proposal.readOnly,
                joinGroup: proposal.joinGroup,
                replacesNodeIDs: proposal.replacesNodeIDs
            )
        }
        return assigningDefaultJoinGroup(
            independentImmediateNodes(
                normalizedNodes(immediate, existingIDs: existingIDs),
                limit: 3
            ),
            defaultID: "frontier-\(existingNodes.count + 1)"
        )
    }

    /// Whole-project repair work is created only after every materialized node
    /// has completed and passed review. Rebase repair proposals onto the
    /// latest audited frontier: that frontier already carries the transitive
    /// dependency on all earlier batches, while depending on every historical
    /// node would violate the immediate-frontier scheduler. A proposal that
    /// references an unmaterialized node is still future work and is rejected.
    static func finalRepairBatchNodes(
        _ proposals: [GraphPlanNodeProposal],
        existingNodes: [GraphLoopNode]
    ) -> [GraphLoopNode] {
        let dependedOn = Set(existingNodes.flatMap(\.dependencies))
        let predecessorIDs = existingNodes
            .filter {
                !dependedOn.contains($0.id)
                    && GraphSchedulingPolicy.isAuditedAndIntegrated($0)
            }
            .map(\.id)
        let existingIDs = existingNodes.map(\.id)
        let existingIDSet = Set(existingIDs)
        let rebased = proposals.compactMap { proposal -> GraphPlanNodeProposal? in
            let rawDependencies = (proposal.dependencies ?? []).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let declared = rawDependencies.compactMap {
                resolveDependencyReference($0, candidates: existingIDs)
            }.uniqued()
            guard declared.count == rawDependencies.count,
                  declared.allSatisfy(existingIDSet.contains) else { return nil }
            return GraphPlanNodeProposal(
                id: proposal.id,
                title: proposal.title,
                objective: proposal.objective,
                dependencies: predecessorIDs,
                writeScopes: proposal.writeScopes,
                verification: proposal.verification,
                readOnly: proposal.readOnly,
                joinGroup: proposal.joinGroup,
                replacesNodeIDs: proposal.replacesNodeIDs
            )
        }
        return nextBatchNodes(
            rebased,
            existingNodes: existingNodes,
            predecessorIDs: predecessorIDs
        )
    }

    /// Model output may quote an already-materialized ID exactly, including a
    /// legacy 42-character truncation that ends in "-". `safeID` intentionally
    /// removes trailing separators, so normalizing before exact lookup can make
    /// a valid predecessor disappear and block recovery. Preserve exact IDs
    /// first, then accept a normalized alias only when it resolves uniquely.
    private static func resolveDependencyReference(
        _ raw: String,
        candidates: [String]
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if candidates.contains(trimmed) { return trimmed }

        let normalized = safeID(trimmed)
        let matches = candidates.filter {
            $0 == normalized || safeID($0) == normalized
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func isValidBatchTransition(_ decision: GraphBatchTransitionEnvelope) -> Bool {
        (decision.readyForFinalAudit && decision.nextNodes.isEmpty)
            || (!decision.readyForFinalAudit && !decision.nextNodes.isEmpty)
    }

    /// Incremental additions remain inside the current join group. They may
    /// consume only completed evidence from that group (or inherit the
    /// predecessors of a branch they replace); they cannot smuggle in a
    /// future-group dependency.
    static func incrementalJoinNodes(
        _ proposals: [GraphPlanNodeProposal],
        existingNodes: [GraphLoopNode],
        groupID: String,
        completedGroupNodeIDs: [String],
        retiredNodes: [GraphLoopNode],
        triggerNodeID: String
    ) -> [GraphLoopNode] {
        let existingIDs = Set(existingNodes.map(\.id))
        let completed = completedGroupNodeIDs.filter(existingIDs.contains).uniqued()
        let completedSet = Set(completed)
        let retiredByID = Dictionary(uniqueKeysWithValues: retiredNodes.map { ($0.id, $0) })
        let accepted = proposals.prefix(2).compactMap { proposal -> GraphPlanNodeProposal? in
            let requestedReplacements = (proposal.replacesNodeIDs ?? []).uniqued()
            let replacements = requestedReplacements
                .filter { retiredByID[$0] != nil }
                .uniqued()
            guard requestedReplacements.isEmpty
                    || replacements.count == requestedReplacements.count else {
                return nil
            }
            let inherited = replacements
                .flatMap { retiredByID[$0]?.dependencies ?? [] }
                .filter(existingIDs.contains)
            let rawDependencies = (proposal.dependencies ?? []).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let declared = rawDependencies.compactMap {
                resolveDependencyReference($0, candidates: completed)
            }.uniqued()
            guard declared.count == rawDependencies.count,
                  declared.allSatisfy(completedSet.contains) else {
                return nil
            }
            let fallback = completedSet.contains(triggerNodeID) ? [triggerNodeID] : completed
            let dependencies = (declared + inherited + (declared.isEmpty ? fallback : []))
                .filter(existingIDs.contains)
                .uniqued()
            guard !dependencies.isEmpty else { return nil }
            return GraphPlanNodeProposal(
                id: proposal.id,
                title: proposal.title,
                objective: proposal.objective,
                dependencies: dependencies,
                writeScopes: proposal.writeScopes,
                verification: proposal.verification,
                readOnly: proposal.readOnly,
                joinGroup: groupID,
                replacesNodeIDs: replacements
            )
        }
        return normalizedNodes(accepted, existingIDs: existingIDs).map { node in
            var sameGroup = node
            sameGroup.joinGroupID = groupID
            return sameGroup
        }
    }

    static func safeID(_ raw: String) -> String {
        let lower = raw.lowercased()
        let mapped = lower.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "-"
        }
        return String(mapped)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefixText(42)
    }

    private static func normalizedScope(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("./") { value.removeFirst(2) }
        value = value.replacingOccurrences(of: "\\", with: "/")
        guard !value.hasPrefix("/"), !value.split(separator: "/").contains("..") else { return "" }
        return value.isEmpty ? "." : value
    }

    private static func concise(_ raw: String, fallback: String, limit: Int) -> String {
        let value = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((value.isEmpty ? fallback : value).prefix(limit))
    }

    private static func normalizedJoinGroup(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = safeID(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        return normalized.isEmpty ? nil : normalized
    }

    private static func assigningDefaultJoinGroup(
        _ nodes: [GraphLoopNode],
        defaultID: String
    ) -> [GraphLoopNode] {
        nodes.map { node in
            var assigned = node
            assigned.joinGroupID = normalizedJoinGroup(node.joinGroupID)
                .map { "\(defaultID)-\($0)" }
                ?? defaultID
            return assigned
        }
    }

    /// A same-frontier write overlap is objective evidence that two proposed
    /// nodes may consume or replace the same state. Materializing both and
    /// merely serializing them would still pre-assign potentially dependent
    /// work. Keep only the first safe immediate owner; the Main Graph Agent
    /// must inspect its audited integration before it can create another node
    /// for that scope in a later batch.
    private static func independentImmediateNodes(
        _ nodes: [GraphLoopNode],
        limit: Int
    ) -> [GraphLoopNode] {
        var selected: [GraphLoopNode] = []
        for node in nodes {
            let overlapsWriter = !node.readOnly && selected.contains {
                !$0.readOnly
                    && GraphSchedulingPolicy.writeScopesOverlap(
                        node.writeScopes,
                        $0.writeScopes
                    )
            }
            guard !overlapsWriter else { continue }
            selected.append(node)
            if selected.count == limit { break }
        }
        return selected
    }
}

enum GraphIncrementalReviewPolicy {
    /// Oldest completed node without a durable incremental checkpoint wins.
    /// This makes crash recovery deterministic and prevents duplicate
    /// additions when several node completions arrive close together.
    static func pendingCompletedNodeID(state: GraphLoopState) -> String? {
        let reviewed = Set(state.incrementallyReviewedNodeIDs ?? [])
        return state.activeNodes
            .filter {
                GraphSchedulingPolicy.isAuditedAndIntegrated($0)
                    && !reviewed.contains($0.id)
                    && !GraphSchedulingPolicy.reviewedJoinGroupIDs(state: state)
                        .contains(GraphSchedulingPolicy.joinGroupID(for: $0, state: state))
            }
            .sorted {
                let left = $0.completedAt ?? .distantFuture
                let right = $1.completedAt ?? .distantFuture
                return left == right ? $0.createdAt < $1.createdAt : left < right
            }
            .first?
            .id
    }

    /// A branch can be discarded only when its work cannot leak into the
    /// shared primary workspace. Waiting/recoverable nodes have no active
    /// changes; active writers require a disposable isolated workspace.
    static func canRetire(
        _ node: GraphLoopNode,
        in state: GraphLoopState,
        requestedRetirements: Set<String>
    ) -> Bool {
        safeRetirementIDs(
            requestedRetirements,
            in: state
        ).contains(node.id)
    }

    /// Computes a dependency-closed retirement set. Merely asking to retire a
    /// dependent is insufficient: that dependent must itself be disposable,
    /// otherwise its predecessor remains protected.
    static func safeRetirementIDs(
        _ requestedRetirements: Set<String>,
        in state: GraphLoopState
    ) -> Set<String> {
        var safe = Set(state.activeNodes.compactMap { node -> String? in
            requestedRetirements.contains(node.id) && isIndividuallyDisposable(node)
                ? node.id
                : nil
        })
        var changed = true
        while changed {
            changed = false
            for nodeID in safe {
                let hasRemainingDependent = state.activeNodes.contains {
                    $0.dependencies.contains(nodeID) && !safe.contains($0.id)
                }
                if hasRemainingDependent {
                    safe.remove(nodeID)
                    changed = true
                }
            }
        }
        return safe
    }

    private static func isIndividuallyDisposable(_ node: GraphLoopNode) -> Bool {
        guard node.status != .completed,
              node.status != .superseded else {
            return false
        }
        switch node.status {
        case .waiting, .blocked, .failed:
            return true
        case .preparing, .running, .auditing, .integrating:
            return node.readOnly
                || node.workspaceStrategy == .gitWorktree
                || node.workspaceStrategy == .isolatedVerification
        case .completed, .superseded:
            return false
        }
    }

    static func validAdjustments(
        _ adjustments: [GraphNodePlanAdjustment],
        groupID: String,
        state: GraphLoopState,
        retiredIDs: Set<String>
    ) -> [GraphNodePlanAdjustment] {
        adjustments.filter { adjustment in
            guard !adjustment.instruction
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !retiredIDs.contains(adjustment.nodeID),
                  let node = state.activeNodes.first(where: { $0.id == adjustment.nodeID }),
                  node.status != .completed else {
                return false
            }
            return GraphSchedulingPolicy.joinGroupID(for: node, state: state) == groupID
        }
    }
}

enum GraphSchedulingPolicy {
    static func isAuditedAndIntegrated(_ node: GraphLoopNode) -> Bool {
        node.status == .completed
            && node.completedAt != nil
            && !node.lastReview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isActive(_ node: GraphLoopNode) -> Bool {
        node.status != .superseded
    }

    /// Auto Graph Loop advances through strict frontier batches. A later
    /// topological level stays hidden and cannot be scheduled until every node
    /// in every earlier level has completed its independent Main Graph review
    /// and has been integrated into the primary workspace.
    static func currentBatchLevel(state: GraphLoopState) -> Int? {
        let levels = GraphLayoutPolicy.levels(for: state.nodes)
        return state.activeNodes
            .filter { !isAuditedAndIntegrated($0) }
            .compactMap { levels[$0.id] }
            .min()
    }

    static func currentBatchNodes(state: GraphLoopState) -> [GraphLoopNode] {
        guard let level = currentBatchLevel(state: state) else { return [] }
        let levels = GraphLayoutPolicy.levels(for: state.nodes)
        return state.activeNodes.filter { levels[$0.id] == level }
    }

    static func revealedNodes(state: GraphLoopState) -> [GraphLoopNode] {
        // Future work is never materialized. Every persisted node is therefore
        // safe to reveal, including an explicitly independent branch that the
        // Main Graph Agent unlocked while another join group is still running.
        // Legacy graphs may contain an old speculative tail with no join-group
        // provenance; keep that tail hidden until migration removes it.
        if state.nodes.allSatisfy({ $0.joinGroupID == nil }),
           let level = currentBatchLevel(state: state) {
            let levels = GraphLayoutPolicy.levels(for: state.nodes)
            return state.nodes.filter { (levels[$0.id] ?? 0) <= level }
        }
        return state.nodes
    }

    static func allNodesAuditedAndIntegrated(state: GraphLoopState) -> Bool {
        !state.activeNodes.isEmpty && state.activeNodes.allSatisfy(isAuditedAndIntegrated)
    }

    static func joinGroupID(
        for node: GraphLoopNode,
        state: GraphLoopState
    ) -> String {
        if let raw = node.joinGroupID {
            let explicit = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !explicit.isEmpty { return explicit }
        }
        let level = GraphLayoutPolicy.levels(for: state.nodes)[node.id] ?? 0
        return "legacy-frontier-\(level + 1)"
    }

    static func reviewedJoinGroupIDs(state: GraphLoopState) -> Set<String> {
        Set(state.reviewedJoinGroupIDs ?? [])
    }

    static func nodes(
        inJoinGroup groupID: String,
        state: GraphLoopState
    ) -> [GraphLoopNode] {
        state.activeNodes.filter { joinGroupID(for: $0, state: state) == groupID }
    }

    /// A join group becomes reviewable only after every node the Main Graph
    /// Agent placed in that group has independently passed review and its
    /// result is integrated. Different groups may complete asynchronously.
    static func reviewableJoinGroupIDs(state: GraphLoopState) -> [String] {
        let reviewed = reviewedJoinGroupIDs(state: state)
        let incrementallyReviewed = Set(state.incrementallyReviewedNodeIDs ?? [])
        let groups = Dictionary(grouping: state.activeNodes) {
            joinGroupID(for: $0, state: state)
        }
        return groups
            .filter { groupID, nodes in
                !reviewed.contains(groupID)
                    && !nodes.isEmpty
                    && nodes.allSatisfy(isAuditedAndIntegrated)
                    && nodes.allSatisfy { incrementallyReviewed.contains($0.id) }
            }
            .sorted {
                let left = $0.value.map(\.createdAt).min() ?? .distantFuture
                let right = $1.value.map(\.createdAt).min() ?? .distantFuture
                return left == right ? $0.key < $1.key : left < right
            }
            .map { $0.key }
    }

    static func allJoinGroupsReviewed(state: GraphLoopState) -> Bool {
        let groups = Set(state.activeNodes.map { joinGroupID(for: $0, state: state) })
        return !groups.isEmpty && groups.isSubset(of: reviewedJoinGroupIDs(state: state))
    }

    static func activeJoinGroupIDs(state: GraphLoopState) -> [String] {
        if state.phase == .completed { return [] }
        let reviewed = reviewedJoinGroupIDs(state: state)
        let groups = Dictionary(grouping: state.activeNodes) {
            joinGroupID(for: $0, state: state)
        }
        return groups
            .filter { !reviewed.contains($0.key) }
            .sorted {
                let left = $0.value.map(\.createdAt).min() ?? .distantFuture
                let right = $1.value.map(\.createdAt).min() ?? .distantFuture
                return left == right ? $0.key < $1.key : left < right
            }
            .map { $0.key }
    }

    static func readyNodeIDs(
        state: GraphLoopState,
        runningIDs: Set<String>,
        maximumToStart: Int
    ) -> [String] {
        guard maximumToStart > 0 else { return [] }
        let completed = Set(state.nodes.filter(isAuditedAndIntegrated).map(\.id))
        let reviewedGroups = reviewedJoinGroupIDs(state: state)
        let runningNodes = state.nodes.filter { runningIDs.contains($0.id) }
        let directWriterRunning = runningNodes.contains {
            !$0.readOnly && $0.workspaceStrategy != .gitWorktree
        }
        var selectedNodes: [GraphLoopNode] = []

        var result: [String] = []
        for node in state.nodes where node.status == .waiting && !runningIDs.contains(node.id) {
            guard node.dependencies.allSatisfy(completed.contains) else { continue }
            let dependencyGroups = Set(node.dependencies.compactMap { dependencyID in
                state.nodes.first(where: { $0.id == dependencyID }).map {
                    joinGroupID(for: $0, state: state)
                }
            })
            let nodeGroup = joinGroupID(for: node, state: state)
            guard node.dependencies.isEmpty
                    || dependencyGroups.allSatisfy({
                        reviewedGroups.contains($0) || $0 == nodeGroup
                    }) else {
                continue
            }
            let nodeRequiresExclusiveWorkspace = !node.readOnly
                && (!state.supportsParallelWorktrees || node.workspaceStrategy == .exclusiveWorkspace)
            if directWriterRunning || selectedNodes.contains(where: {
                !$0.readOnly && $0.workspaceStrategy == .exclusiveWorkspace
            }) {
                continue
            }
            if nodeRequiresExclusiveWorkspace && (!runningNodes.isEmpty || !selectedNodes.isEmpty) {
                continue
            }
            if node.readOnly && selectedNodes.contains(where: {
                !$0.readOnly && (!state.supportsParallelWorktrees || $0.workspaceStrategy == .exclusiveWorkspace)
            }) {
                continue
            }
            if !node.readOnly {
                let otherWriters = (runningNodes + selectedNodes).filter { !$0.readOnly }
                guard !otherWriters.contains(where: {
                    writeScopesOverlap(node.writeScopes, $0.writeScopes)
                }) else { continue }
            }
            result.append(node.id)
            selectedNodes.append(node)
            if result.count == maximumToStart { break }
        }
        return result
    }

    static func writeScopesOverlap(_ left: [String], _ right: [String]) -> Bool {
        let lhs = left.isEmpty ? ["."] : left
        let rhs = right.isEmpty ? ["."] : right
        return lhs.contains { a in rhs.contains { b in pathsOverlap(a, b) } }
    }

    private static func pathsOverlap(_ left: String, _ right: String) -> Bool {
        let a = normalizedScope(left)
        let b = normalizedScope(right)
        guard a != ".", b != "." else { return true }
        return a == b || a.hasPrefix("\(b)/") || b.hasPrefix("\(a)/")
    }

    private static func normalizedScope(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") { value.removeFirst(2) }
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? "." : value
    }

    static func interventionDeadline(blockedAt: Date) -> Date {
        blockedAt.addingTimeInterval(30 * 60)
    }
}

enum GraphPresentationPolicy {
    enum EdgeDisposition: Equatable {
        case pending
        case completed
        case superseded
    }

    /// End is a delivered-state terminal, not a placeholder for every current
    /// leaf. Until the final whole-project audit and report complete, it must
    /// remain visually isolated.
    static func shouldConnectLeavesToEnd(state: GraphLoopState) -> Bool {
        state.phase == .completed
            && state.completedAt != nil
            && GraphSchedulingPolicy.allNodesAuditedAndIntegrated(state: state)
    }

    static func terminalNodeIDs(state: GraphLoopState) -> [String] {
        let dependedOn = Set(state.activeNodes.flatMap(\.dependencies))
        return state.activeNodes
            .filter { !dependedOn.contains($0.id) }
            .map(\.id)
    }

    static func incomingEdgeDisposition(for node: GraphLoopNode) -> EdgeDisposition {
        switch node.status {
        case .completed: return .completed
        case .superseded: return .superseded
        default: return .pending
        }
    }
}

enum GraphIterationHistoryPolicy {
    static func records(task: LoopTask, node: GraphLoopNode) -> [GraphNodeIterationRecord] {
        let persisted = node.iterationHistory ?? []
        let legacy = reconstructedRecords(task: task, node: node)
        var byNumber: [Int: GraphNodeIterationRecord] = [:]
        for record in legacy { byNumber[record.number] = record }
        for record in persisted { byNumber[record.number] = record }
        return byNumber.values.sorted { $0.number < $1.number }
    }

    /// A process relaunch or user pause resumes the unfinished control cycle.
    /// Only a cycle that already received a terminal Main Agent decision may
    /// advance the public iteration count.
    static func nextTurnNumber(task: LoopTask, node: GraphLoopNode) -> Int {
        let history = records(task: task, node: node)
        if let last = history.last,
           last.number == node.iteration,
           last.decision == .pending {
            return max(1, node.iteration)
        }
        return node.iteration + 1
    }

    static func countLabel(_ count: Int) -> String {
        "Iterations \(max(1, count))"
    }

    /// 4.4.0 and earlier retained every execution prompt and Main review in
    /// logs but exposed only the latest pair. Reconstruct those historical
    /// cycles so existing tasks immediately gain a truthful timeline.
    private static func reconstructedRecords(
        task: LoopTask,
        node: GraphLoopNode
    ) -> [GraphNodeIterationRecord] {
        let rawPromptEntries = node.logs.compactMap { entry -> (Int, String, Date)? in
            guard entry.kind == .control,
                  let parsed = parseInstruction(entry.message) else {
                return nil
            }
            return (parsed.number, parsed.instruction, entry.timestamp)
        }.sorted { $0.2 < $1.2 }
        var promptEntries: [(Int, String, Date)] = []
        for entry in rawPromptEntries {
            if promptEntries.last?.0 == entry.0 {
                continue
            }
            promptEntries.append(entry)
        }
        guard !promptEntries.isEmpty else { return [] }

        return promptEntries.enumerated().map { index, item in
            let nextStart = index + 1 < promptEntries.count
                ? promptEntries[index + 1].2
                : .distantFuture
            let taskReviews = task.logs.filter {
                $0.timestamp >= item.2
                    && $0.timestamp < nextStart
                    && ($0.kind == .audit || $0.kind == .control || $0.kind == .warning)
                    && $0.message.localizedCaseInsensitiveContains(node.title)
            }
            let incidentReviews = node.logs.filter {
                $0.timestamp >= item.2
                    && $0.timestamp < nextStart
                    && ($0.kind == .warning || $0.kind == .audit)
                    && (
                        $0.message.localizedCaseInsensitiveContains("recover")
                            || $0.message.localizedCaseInsensitiveContains("blocked")
                            || $0.message.localizedCaseInsensitiveContains("interrupted")
                    )
            }
            let review = (taskReviews + incidentReviews)
                .sorted { $0.timestamp < $1.timestamp }
                .last?
                .message
                ?? (
                    index == promptEntries.count - 1 && !node.lastReview.isEmpty
                        ? node.lastReview
                        : ""
                )
            let agents = node.logs.filter {
                $0.kind == .agent
                    && $0.timestamp >= item.2
                    && $0.timestamp < nextStart
            }
            let nextInstruction = index + 1 < promptEntries.count
                ? promptEntries[index + 1].1
                : ""
            return GraphNodeIterationRecord(
                number: item.0,
                instruction: item.1,
                startedAt: item.2,
                finishedAt: (taskReviews + incidentReviews + agents)
                    .map(\.timestamp)
                    .max(),
                threadID: nil,
                exitCode: nil,
                agentSummary: agents.last?.message ?? "",
                mainReview: review,
                nextInstruction: nextInstruction,
                decision: decision(review: review, hasNextInstruction: !nextInstruction.isEmpty)
            )
        }
    }

    private static func parseInstruction(
        _ prompt: String
    ) -> (number: Int, instruction: String)? {
        let prefix = "CURRENT MAIN-GRAPH INSTRUCTION (iteration "
        guard let marker = prompt.range(of: prefix),
              let numberEnd = prompt[marker.upperBound...].range(of: "):\n"),
              let number = Int(prompt[marker.upperBound..<numberEnd.lowerBound]) else {
            return nil
        }
        let start = numberEnd.upperBound
        let suffix = prompt[start...]
        let delimiters = [
            "\n\nLATEST INCREMENTAL PLAN ADJUSTMENT:",
            "\n\nDECLARED WRITE SCOPES:"
        ]
        let end = delimiters
            .compactMap { suffix.range(of: $0)?.lowerBound }
            .min() ?? prompt.endIndex
        let instruction = prompt[start..<end]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return nil }
        return (number, instruction)
    }

    private static func decision(
        review: String,
        hasNextInstruction: Bool
    ) -> GraphIterationDecision {
        let normalized = review
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("approved") {
            return .approved
        }
        // Do not treat ordinary acceptance language such as “conflict recovery”
        // or “incident handling” as a LoopForge recovery event. Legacy recovery
        // records used these explicit control messages.
        if normalized.hasPrefix("recovered this node from")
            || normalized.hasPrefix("incident review ·")
            || normalized.hasPrefix("recovery review ·")
            || normalized.contains("main agent recovery review ·") {
            return .recovery
        }
        if normalized.contains("blocked") && !hasNextInstruction {
            return .externalBlocker
        }
        if hasNextInstruction || !review.isEmpty {
            return .continueWork
        }
        return .pending
    }
}

enum GraphLayoutPolicy {
    static func levels(for nodes: [GraphLoopNode]) -> [String: Int] {
        let dependencies = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.dependencies) })
        var cache: [String: Int] = [:]
        var visiting = Set<String>()

        func level(_ id: String) -> Int {
            if let cached = cache[id] { return cached }
            guard visiting.insert(id).inserted else { return 0 }
            let value = (dependencies[id] ?? []).map(level).max().map { $0 + 1 } ?? 0
            visiting.remove(id)
            cache[id] = value
            return value
        }

        for node in nodes { _ = level(node.id) }
        return cache
    }
}

private enum GraphNodeSignal {
    case turnFinished(String, CodexTurnResult)
    case turnFailed(String, String)
    case superseded(String)
    case interventionDue(String)
    case cancelled
}

private enum GraphBatchAdvanceResult {
    case expanded
    case readyForFinalAudit
    case retry
    case stopped
}

private actor GraphSignalSemaphore {
    private var pending: [GraphNodeSignal] = []
    private var waiters: [CheckedContinuation<GraphNodeSignal, Never>] = []

    func signal(_ value: GraphNodeSignal) {
        if waiters.isEmpty {
            pending.append(value)
        } else {
            waiters.removeFirst().resume(returning: value)
        }
    }

    func wait() async -> GraphNodeSignal {
        if !pending.isEmpty { return pending.removeFirst() }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

private final class GraphChildRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var children: [String: Task<Void, Never>] = [:]

    func set(_ task: Task<Void, Never>, for id: String) {
        lock.lock()
        children[id] = task
        lock.unlock()
    }

    func remove(_ id: String) {
        lock.lock()
        children[id] = nil
        lock.unlock()
    }

    func cancel(_ id: String) {
        lock.lock()
        let child = children[id]
        lock.unlock()
        child?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let values = Array(children.values)
        children.removeAll()
        lock.unlock()
        values.forEach { $0.cancel() }
    }
}

struct GraphWorkspaceCapability: Equatable {
    let gitRoot: String?
    let baseCommit: String?
    let clean: Bool

    var supportsParallelWorktrees: Bool {
        gitRoot != nil && baseCommit != nil && clean
    }
}

enum GraphIntegrationResult: Equatable {
    case noChanges
    case applied
    case conflict(String)
}

enum GraphNodeAccessPolicy {
    static func capabilityRequest(for node: GraphLoopNode) -> String {
        ([node.objective] + node.verification).joined(separator: "\n")
    }

    static func selection(
        parent: AgentSelection,
        node: GraphLoopNode,
        category: TaskCategory
    ) -> AgentSelection {
        var selected = parent
        if selected.accessMode == .fullAccess,
           !CodexHostToolingPolicy.objectiveRequiresInstalledTools(
               capabilityRequest(for: node),
               category: category
           ) {
            selected.accessMode = .workspaceOnly
        }
        return selected
    }
}

enum GraphNodeOperationalPolicy {
    static let longRunningProcessGuidance = """
    When verification starts a server, watcher, simulator, GUI, or any other
    long-lived process, never wait forever on a foreground command. Start only
    the process you need with an explicit retained PID. Never use shell `exec`
    to replace the tool process with a long-lived child. Start it in the
    background and capture `$!`, or use an execution session that explicitly
    yields control. Wait for a concrete readiness signal with a bounded
    deadline, exercise the required behavior, then terminate and reap that
    owned process. Prove cleanup (for example, the port is closed) before
    returning. Never kill unrelated or pre-existing user processes.
    """
}

enum GraphDelegationPolicy {
    static let noNestedAgentsGuidance = """
    LoopForge's persisted graph is the only concurrency and delegation layer.
    Do not call collaboration, spawn_agent, send_message, followup_task, or any
    equivalent sub-agent, delegation, thread, or fan-out tool. Do not create a
    hidden subordinate agent or ask another agent to review this work. Perform
    this bounded turn yourself. If distinct work should become a separate node,
    report that concrete dependency or gap to LoopForge; only the Main Graph
    control flow may materialize it after the current audited frontier.
    """

    static func boundedTurn(_ instruction: String) -> String {
        return """
        \(instruction)

        \(noNestedAgentsGuidance)
        """
    }
}

enum GraphVerificationPolicy {
    static let observedTestCountGuidance = """
    Verification may require exact commands, named behaviors, exit codes, and
    absence of failures. Never invent or freeze a predicted or historical test
    count as a success condition unless the verbatim user goal explicitly
    requires that count. A canonical suite may legitimately add, remove,
    consolidate, or parameterize tests as the graph integrates. Record the
    observed pass/fail totals and judge coverage and behavior; do not reject an
    otherwise passing current suite or manufacture tests solely to match an
    obsolete number.
    """

    /// A graph node can be logically read-only while still needing a writable
    /// runtime for test databases, compiler caches, browser profiles, or
    /// simulator state. Those nodes must run in a disposable copy rather than
    /// either failing in the system read-only sandbox or gaining write access
    /// to the user's primary workspace.
    static func requiresDisposableRuntime(for node: GraphLoopNode) -> Bool {
        let text = (
            [node.objective, node.currentInstruction] + node.verification
        )
        .joined(separator: "\n")
        .lowercased()

        let executionMarkers = [
            "python -m unittest",
            "python3 -m unittest",
            "python3.12 -m unittest",
            "pytest",
            "node --test",
            "npm test",
            "npm run test",
            "swift test",
            "xcodebuild",
            "cargo test",
            "go test",
            "dotnet test",
            "run complete integrated suite",
            "run the complete automated suite",
            "launch the real app",
            "exercise the real browser",
            "capture real ui",
            "capture screenshot",
            "simulator"
        ]
        return executionMarkers.contains { text.contains($0) }
    }
}

enum GraphCompletionPolicy {
    static let disclosedGapGuidance = """
    Treat every reproducible defect, failed workflow, disabled recovery action,
    unverified required behavior, or remaining issue disclosed by any
    worker as concrete graph work when it relates to the verbatim user goal.
    A worker's write scope limits that worker; it never waives the whole graph's
    obligation. Do not advance to final audit or approve completion merely
    because the reporting node was read-only or said the repair was outside its
    scope. Materialize the smallest safe repair-and-regression node at the next
    dependency frontier, unless retained evidence proves the issue is only a
    harness error and the product behavior is correct.
    """
}

enum GraphReviewBudgetPolicy {
    /// A whole-project multimodal review can include several large screenshots,
    /// the complete materialized graph, command evidence, and the integrated
    /// source tree. Keep it bounded below the 30-minute semantic watchdog while
    /// allowing Ultra reasoning more time than an ordinary node review.
    static let finalAuditTimeout: TimeInterval = 20 * 60
}

final class GraphWorkspaceCoordinator {
    private let runner = ProcessRunner()

    func capability(workspacePath: String) async -> GraphWorkspaceCapability {
        let directory = URL(fileURLWithPath: workspacePath, isDirectory: true)
        guard let root = try? await git(["rev-parse", "--show-toplevel"], at: directory),
              let commit = try? await git(["rev-parse", "HEAD"], at: directory),
              let status = try? await git(["status", "--porcelain"], at: directory) else {
            return GraphWorkspaceCapability(gitRoot: nil, baseCommit: nil, clean: false)
        }
        return GraphWorkspaceCapability(
            gitRoot: root.trimmingCharacters(in: .whitespacesAndNewlines),
            baseCommit: commit.trimmingCharacters(in: .whitespacesAndNewlines),
            clean: status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    func candidateCapability(workspacePath: String) async -> GraphWorkspaceCapability {
        let detected = await capability(workspacePath: workspacePath)
        if detected.supportsParallelWorktrees { return detected }

        // A newly created empty LoopForge project may safely gain a private
        // initial Git baseline. Existing non-empty or dirty projects are never
        // silently committed or rewritten.
        let directory = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let visibleEntries = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.lastPathComponent != ".loopforge" }
        guard visibleEntries.isEmpty else { return detected }
        do {
            _ = try await git(["init"], at: directory)
            _ = try await git(
                [
                    "-c", "user.name=LoopForge",
                    "-c", "user.email=loopforge@localhost",
                    "commit", "--allow-empty", "-m", "LoopForge parallel baseline"
                ],
                at: directory
            )
            return await capability(workspacePath: workspacePath)
        } catch {
            return detected
        }
    }

    func prepare(
        task: LoopTask,
        node: GraphLoopNode,
        capability: GraphWorkspaceCapability
    ) async throws -> GraphLoopNode {
        // Pure source inspection stays on the primary workspace under the real
        // read-only sandbox so exact paths and sibling inputs remain truthful.
        // Verification commands commonly need temporary writes even when they
        // must not change product files; those run in a disposable copy.
        if node.readOnly,
           !GraphVerificationPolicy.requiresDisposableRuntime(for: node) {
            var prepared = node
            prepared.workspacePath = task.workspacePath
            prepared.workspaceStrategy = .sharedReadOnly
            prepared.isolationRootPath = nil
            prepared.integrationBaseCommit = nil
            return prepared
        }
        if let path = node.workspacePath,
           FileManager.default.fileExists(atPath: path),
           !(node.readOnly && capability.supportsParallelWorktrees) {
            return node
        }
        var prepared = node
        guard capability.supportsParallelWorktrees,
              let gitRoot = capability.gitRoot,
              let baseCommit = capability.baseCommit else {
            if node.readOnly {
                return try await prepareDisposableVerificationCopy(
                    task: task,
                    node: node
                )
            }
            prepared.workspacePath = task.workspacePath
            prepared.workspaceStrategy = .exclusiveWorkspace
            return prepared
        }

        let rootURL = URL(fileURLWithPath: gitRoot, isDirectory: true).standardizedFileURL
        let workspaceURL = URL(fileURLWithPath: task.workspacePath, isDirectory: true).standardizedFileURL
        let relative = workspaceURL.path == rootURL.path
            ? ""
            : String(workspaceURL.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let worktreeRoot = TaskStore.applicationSupportDirectory()
            .appendingPathComponent("GraphWorkspaces", isDirectory: true)
            .appendingPathComponent(task.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(node.id, isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: worktreeRoot.path) {
            _ = try? await git(
                ["worktree", "remove", "--force", worktreeRoot.path],
                at: rootURL
            )
            try? FileManager.default.removeItem(at: worktreeRoot)
        }
        _ = try await git(
            ["worktree", "add", "--detach", worktreeRoot.path, baseCommit],
            at: rootURL
        )
        // The capability snapshot is intentionally taken before the graph
        // begins. Earlier graph-node patches remain uncommitted in the user's
        // primary workspace, so a later dependent worktree must inherit that
        // integrated state without changing the user's branch history.
        try await mirrorPrimaryWorkspace(from: rootURL, to: worktreeRoot)
        let mirroredStatus = try await git(["status", "--porcelain"], at: worktreeRoot)
        if !mirroredStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try await git(["add", "-A"], at: worktreeRoot)
            _ = try await git(
                [
                    "-c", "user.name=LoopForge",
                    "-c", "user.email=loopforge@localhost",
                    "commit", "-m", "LoopForge graph integration baseline"
                ],
                at: worktreeRoot
            )
        }
        let integrationBase = try await git(["rev-parse", "HEAD"], at: worktreeRoot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        prepared.workspacePath = relative.isEmpty
            ? worktreeRoot.path
            : worktreeRoot.appendingPathComponent(relative, isDirectory: true).path
        prepared.isolationRootPath = worktreeRoot.path
        prepared.workspaceStrategy = node.readOnly ? .isolatedVerification : .gitWorktree
        prepared.integrationBaseCommit = integrationBase
        return prepared
    }

    func integrate(task: LoopTask, node: GraphLoopNode) async -> GraphIntegrationResult {
        if node.workspaceStrategy == .isolatedVerification {
            await cleanup(task: task, node: node)
            return .noChanges
        }
        guard node.workspaceStrategy == .gitWorktree,
              let worktree = node.isolationRootPath,
              let baseCommit = node.integrationBaseCommit else {
            return .noChanges
        }
        let worktreeURL = URL(fileURLWithPath: worktree, isDirectory: true)
        let patchURL = integrationPatchURL(task: task, node: node)
        let markerURL = integrationMarkerURL(task: task, node: node)
        if !FileManager.default.fileExists(atPath: worktreeURL.path) {
            if FileManager.default.fileExists(atPath: markerURL.path) {
                return .noChanges
            }
            if FileManager.default.fileExists(atPath: patchURL.path) {
                return await applyOrRecognizeExistingPatch(
                    patchURL,
                    task: task,
                    node: node
                )
            }
            return .conflict(
                "The isolated candidate workspace disappeared before a durable integration patch or no-change marker was produced."
            )
        }
        do {
            let status = try await git(["status", "--porcelain"], at: worktreeURL)
            if !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try await git(["add", "-A"], at: worktreeURL)
                _ = try await git(
                    [
                        "-c", "user.name=LoopForge",
                        "-c", "user.email=loopforge@localhost",
                        "commit", "-m", "LoopForge graph node: \(node.title)"
                    ],
                    at: worktreeURL
                )
            }
            let changedPathOutput = try await git(
                ["diff", "--name-only", "\(baseCommit)..HEAD"],
                at: worktreeURL
            )
            let changedPaths = changedPathOutput
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            if changedPaths.isEmpty {
                try writeIntegrationMarker(to: markerURL)
                await cleanup(task: task, node: node)
                return .noChanges
            }
            let violations = changedPaths.filter {
                !path($0, isAllowedBy: node, worktreeRoot: worktreeURL)
            }
            if !violations.isEmpty {
                return .conflict(
                    """
                    The node changed paths outside its declared parallel-write scope: \(violations.prefix(12).joined(separator: ", ")). Main Graph Agent must integrate this result sequentially instead of applying an unsafe patch.
                    """
                )
            }
            try FileManager.default.createDirectory(
                at: patchURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Never route a binary Git patch through a Swift String or the
            // bounded command-output ledger. PNGs, databases, archives, model
            // assets, and other binary products can be truncated or altered
            // by text decoding. Ask Git to write the patch file itself, then
            // let Git validate that exact byte stream before application.
            try? FileManager.default.removeItem(at: patchURL)
            let patchResult = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "diff", "--binary",
                    "--output=\(patchURL.path)",
                    "\(baseCommit)..HEAD"
                ],
                environment: ProcessInfo.processInfo.environment,
                currentDirectory: worktreeURL,
                timeout: 120
            )
            guard patchResult.exitCode == 0 else {
                return .conflict(
                    "Git could not create the binary-safe node patch: \(sanitizedLogText(patchResult.stderr).prefixText(900))"
                )
            }
            let patchSize = (
                try? FileManager.default.attributesOfItem(atPath: patchURL.path)[.size]
                    as? NSNumber
            )?.int64Value ?? 0
            guard patchSize > 0 else {
                try writeIntegrationMarker(to: markerURL)
                await cleanup(task: task, node: node)
                return .noChanges
            }
            let result = await applyOrRecognizeExistingPatch(
                patchURL,
                task: task,
                node: node
            )
            switch result {
            case .applied, .noChanges:
                await cleanup(task: task, node: node)
            case .conflict:
                break
            }
            return result
        } catch {
            return .conflict(sanitizedLogText(error.localizedDescription).prefixText(900))
        }
    }

    private func applyOrRecognizeExistingPatch(
        _ patchURL: URL,
        task: LoopTask,
        node: GraphLoopNode
    ) async -> GraphIntegrationResult {
        let baseURL = URL(fileURLWithPath: task.workspacePath, isDirectory: true)
        do {
            _ = try await git(["apply", "--check", patchURL.path], at: baseURL)
            _ = try await git(["apply", patchURL.path], at: baseURL)
            return .applied
        } catch {
            // A successful reverse check proves this exact binary-safe patch is
            // already present. This makes winner integration idempotent across
            // a crash after `git apply` but before task-state persistence.
            do {
                _ = try await git(
                    ["apply", "--reverse", "--check", patchURL.path],
                    at: baseURL
                )
                return .applied
            } catch {
                return .conflict(
                    sanitizedLogText(error.localizedDescription).prefixText(900)
                )
            }
        }
    }

    private func integrationPatchURL(task: LoopTask, node: GraphLoopNode) -> URL {
        TaskStore.applicationSupportDirectory()
            .appendingPathComponent("GraphPatches", isDirectory: true)
            .appendingPathComponent(task.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("\(node.id).patch")
    }

    private func integrationMarkerURL(task: LoopTask, node: GraphLoopNode) -> URL {
        integrationPatchURL(task: task, node: node)
            .appendingPathExtension("no-changes")
    }

    private func writeIntegrationMarker(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("verified-no-changes\n".utf8).write(to: url, options: .atomic)
    }

    func cleanup(task: LoopTask, node: GraphLoopNode) async {
        guard node.workspaceStrategy == .gitWorktree || node.workspaceStrategy == .isolatedVerification,
              let worktree = node.isolationRootPath else { return }
        let baseURL = URL(fileURLWithPath: task.workspacePath, isDirectory: true)
        _ = try? await git(["worktree", "remove", "--force", worktree], at: baseURL)
        if node.workspaceStrategy == .isolatedVerification,
           FileManager.default.fileExists(atPath: worktree) {
            try? FileManager.default.removeItem(atPath: worktree)
        }
    }

    private func prepareDisposableVerificationCopy(
        task: LoopTask,
        node: GraphLoopNode
    ) async throws -> GraphLoopNode {
        let copyRoot = TaskStore.applicationSupportDirectory()
            .appendingPathComponent("GraphWorkspaces", isDirectory: true)
            .appendingPathComponent(task.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(node.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: copyRoot.path) {
            try FileManager.default.removeItem(at: copyRoot)
        }
        try FileManager.default.createDirectory(
            at: copyRoot,
            withIntermediateDirectories: true
        )
        let source = URL(fileURLWithPath: task.workspacePath, isDirectory: true)
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/rsync"),
            arguments: [
                "-a", "--delete",
                "--exclude", ".git",
                "--exclude", ".build",
                "--exclude", "DerivedData",
                "--exclude", ".loopforge",
                "\(source.path)/",
                "\(copyRoot.path)/"
            ],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: source,
            timeout: 120
        )
        guard result.exitCode == 0 else {
            throw LoopForgeError.processFailed(
                "prepare disposable verification copy",
                result.exitCode,
                String(result.stderr.suffix(800))
            )
        }
        var prepared = node
        prepared.workspacePath = copyRoot.path
        prepared.isolationRootPath = copyRoot.path
        prepared.workspaceStrategy = .isolatedVerification
        prepared.integrationBaseCommit = nil
        return prepared
    }

    private func git(_ arguments: [String], at directory: URL) async throws -> String {
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: directory,
            timeout: 120
        )
        guard result.exitCode == 0 else {
            throw LoopForgeError.processFailed(
                "git \(arguments.prefix(3).joined(separator: " "))",
                result.exitCode,
                String(result.stderr.suffix(800))
            )
        }
        return result.stdout
    }

    private func mirrorPrimaryWorkspace(from source: URL, to destination: URL) async throws {
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/rsync"),
            arguments: [
                "-a", "--delete",
                "--exclude", ".git",
                "--exclude", ".build",
                "--exclude", "DerivedData",
                "--exclude", ".loopforge",
                "\(source.path)/",
                "\(destination.path)/"
            ],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: source,
            timeout: 300
        )
        guard result.exitCode == 0 else {
            throw LoopForgeError.processFailed(
                "rsync graph baseline",
                result.exitCode,
                String(result.stderr.suffix(800))
            )
        }
    }

    private func path(
        _ changedPath: String,
        isAllowedBy node: GraphLoopNode,
        worktreeRoot: URL
    ) -> Bool {
        let relativeWorkspace: String = {
            guard let workspacePath = node.workspacePath else { return "" }
            let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true).standardizedFileURL.path
            let root = worktreeRoot.standardizedFileURL.path
            guard workspace != root, workspace.hasPrefix("\(root)/") else { return "" }
            return String(workspace.dropFirst(root.count + 1))
        }()
        let declared = node.writeScopes.isEmpty ? ["."] : node.writeScopes
        return declared.contains { rawScope in
            var scope = rawScope.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            while scope.hasPrefix("./") { scope.removeFirst(2) }
            let base = relativeWorkspace.isEmpty
                ? (scope.isEmpty || scope == "." ? "" : scope)
                : (scope.isEmpty || scope == "."
                    ? relativeWorkspace
                    : "\(relativeWorkspace)/\(scope)")
            return base.isEmpty
                || changedPath == base
                || changedPath.hasPrefix("\(base)/")
        }
    }
}

@MainActor
final class GraphLoopEngine {
    private let store: TaskStore
    private let codex: CodexRunner
    private let auditor: WorkspaceAuditor
    private let evidenceCollector: WorkspaceEvidenceCollector
    private let reportGenerator: CompletionReportGenerator
    private let agentCatalog: AgentCatalog
    private let router: AuxiliaryModelRouter
    private let workspaces: GraphWorkspaceCoordinator
    private let blockMonitorSeconds: TimeInterval
    private var activeRegistry: GraphChildRegistry?
    private var activeSemaphore: GraphSignalSemaphore?
    private var isCancelling = false
    private var activeTaskID: UUID?
    private var consecutiveBatchTransitionFailures = 0
    private var consecutiveFinalReviewFailures = 0

    init(
        store: TaskStore,
        codex: CodexRunner,
        auditor: WorkspaceAuditor,
        evidenceCollector: WorkspaceEvidenceCollector,
        reportGenerator: CompletionReportGenerator,
        agentCatalog: AgentCatalog,
        router: AuxiliaryModelRouter,
        workspaces: GraphWorkspaceCoordinator = GraphWorkspaceCoordinator(),
        blockMonitorSeconds: TimeInterval = 30 * 60
    ) {
        self.store = store
        self.codex = codex
        self.auditor = auditor
        self.evidenceCollector = evidenceCollector
        self.reportGenerator = reportGenerator
        self.agentCatalog = agentCatalog
        self.router = router
        self.workspaces = workspaces
        self.blockMonitorSeconds = blockMonitorSeconds
    }

    func run(taskID: UUID, desktopContext: String) async throws {
        guard var task = store.task(id: taskID) else { return }
        isCancelling = false
        consecutiveBatchTransitionFailures = 0
        consecutiveFinalReviewFailures = 0
        activeTaskID = taskID
        defer { activeTaskID = nil }
        await discardRedundantPendingRepairIfAlreadyApproved(taskID: taskID)
        migrateLegacyPreplannedNodes(taskID: taskID)
        resumeRecoverableNodes(taskID: taskID)
        task = store.task(id: taskID) ?? task
        let detectedCapability = task.resolvedExecutionMode == .parallelCandidates
            ? await workspaces.candidateCapability(workspacePath: task.workspacePath)
            : await workspaces.capability(workspacePath: task.workspacePath)
        // A graph that was created from a clean repository intentionally makes
        // the primary workspace dirty as node patches are integrated. Preserve
        // the already-proven worktree capability across pause/relaunch instead
        // of mistaking LoopForge's own accumulated graph state for an unsafe
        // repository. Every later worktree mirrors and commits that exact state
        // before a node starts, and patch application still detects conflicts.
        let capability = GraphWorkspaceCapability(
            gitRoot: detectedCapability.gitRoot,
            baseCommit: detectedCapability.baseCommit,
            clean: detectedCapability.clean
                || task.graphState?.supportsParallelWorktrees == true
        )
        if task.resolvedExecutionMode == .parallelCandidates {
            guard capability.supportsParallelWorktrees else {
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = "Parallel candidates need a clean Git project with at least one commit"
                    $0.externalBlockerMessage = "Commit or stash the current project changes, then resume. LoopForge never commits an existing non-empty project without permission."
                    $0.resumeOnNextLaunch = false
                }
                store.appendLog(
                    id: taskID,
                    kind: .warning,
                    "Safe parallel writes were not started because isolated Git worktrees are unavailable. Existing dirty or non-empty non-Git projects are never modified to manufacture a baseline."
                )
                return
            }
            if task.graphState == nil {
                createParallelCandidateGraph(taskID: taskID, capability: capability)
            }
            if let pendingWinner = store.task(id: taskID)?.selectedCandidateID,
               store.task(id: taskID)?.parallelWinnerIntegrated != true {
                try await integrateParallelWinner(
                    taskID: taskID,
                    winnerID: pendingWinner,
                    selectionSummary: store.task(id: taskID)?.parallelSelectionSummary
                        ?? "Resumed the previously selected candidate after an interruption."
                )
            } else if store.task(id: taskID)?.selectedCandidateID == nil {
                let selected = try await runParallelCandidates(
                    taskID: taskID,
                    capability: capability,
                    desktopContext: desktopContext
                )
                guard selected else { return }
            }
            task = store.task(id: taskID) ?? task
        } else if task.graphState == nil {
            try await createInitialGraph(taskID: taskID, capability: capability)
        }
        if task.taskNamingCompleted != true {
            store.update(id: taskID) {
                $0.shortTitle = TaskNamePolicy.descriptiveSummary(
                    request: $0.originalRequest ?? $0.request,
                    fallback: $0.title
                )
                $0.taskNamingCompleted = true
                $0.taskNamingVersion = TaskNamePolicy.currentVersion
            }
        }
        task = store.task(id: taskID) ?? task

        let semaphore = GraphSignalSemaphore()
        let registry = GraphChildRegistry()
        activeSemaphore = semaphore
        activeRegistry = registry
        var running = Set<String>()
        var blockMonitors: [String: Task<Void, Never>] = [:]
        defer {
            registry.cancelAll()
            blockMonitors.values.forEach { $0.cancel() }
            activeRegistry = nil
            activeSemaphore = nil
        }

        while !Task.isCancelled {
            guard let current = store.task(id: taskID),
                  let graph = current.graphState else { return }
            announceCurrentBatchIfNeeded(taskID: taskID, graph: graph)
            if current.resolvedExecutionMode == .autoGraph,
               let completedNodeID = GraphIncrementalReviewPolicy
                   .pendingCompletedNodeID(state: graph) {
                let stopped = await incrementallyReviewCompletedNode(
                    taskID: taskID,
                    completedNodeID: completedNodeID,
                    runningIDs: running,
                    registry: registry
                )
                if stopped { return }
                continue
            }
            if graph.phase != .finalAudit,
               let completedGroup = GraphSchedulingPolicy
                   .reviewableJoinGroupIDs(state: graph)
                   .first(where: { groupID in
                       graph.nodes
                           .filter {
                               GraphSchedulingPolicy.joinGroupID(for: $0, state: graph)
                                   == groupID
                           }
                           .allSatisfy { !running.contains($0.id) }
                   }) {
                switch await advanceAfterCompletedJoinGroup(
                    taskID: taskID,
                    groupID: completedGroup
                ) {
                case .expanded, .retry:
                    continue
                case .readyForFinalAudit:
                    continue
                case .stopped:
                    return
                }
            }
            if GraphSchedulingPolicy.allNodesAuditedAndIntegrated(state: graph),
               (
                   current.resolvedExecutionMode == .parallelCandidates
                       || GraphSchedulingPolicy.allJoinGroupsReviewed(state: graph)
               ),
               running.isEmpty {
                if try await finalizeOrExpand(taskID: taskID) { return }
                continue
            }

            let capacity = max(0, graph.maxConcurrentNodes - running.count)
            let ready = GraphSchedulingPolicy.readyNodeIDs(
                state: graph,
                runningIDs: running,
                maximumToStart: capacity
            )
            for nodeID in ready {
                guard let latestTask = store.task(id: taskID),
                      let latestGraph = latestTask.graphState,
                      let originalNode = latestGraph.nodes.first(where: { $0.id == nodeID }) else { continue }
                do {
                    let prepared = try await workspaces.prepare(
                        task: latestTask,
                        node: originalNode,
                        capability: capability
                    )
                    store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                        $0 = prepared
                        $0.status = .preparing
                    }
                    running.insert(nodeID)
                    let child = Task { [weak self] in
                        guard let self else { return }
                        await self.performNodeTurn(
                            taskID: taskID,
                            nodeID: nodeID,
                            desktopContext: desktopContext,
                            semaphore: semaphore
                        )
                    }
                    registry.set(child, for: nodeID)
                } catch {
                    let detail = sanitizedLogText(error.localizedDescription)
                    store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                        $0.workspacePath = latestTask.workspacePath
                        $0.workspaceStrategy = .exclusiveWorkspace
                        $0.isolationRootPath = nil
                        $0.integrationBaseCommit = nil
                        $0.status = .waiting
                        $0.currentInstruction = """
                        Workspace isolation could not be prepared. Continue safely in the primary workspace with exclusive write access. Preserve unrelated work and verify every modified path.
                        """
                    }
                    store.appendGraphNodeLog(
                        taskID: taskID,
                        nodeID: nodeID,
                        kind: .warning,
                        "Worktree isolation failed and this node was safely downgraded to exclusive execution. \(detail)"
                    )
                    running.insert(nodeID)
                    let child = Task { [weak self] in
                        guard let self else { return }
                        await self.performNodeTurn(
                            taskID: taskID,
                            nodeID: nodeID,
                            desktopContext: desktopContext,
                            semaphore: semaphore
                        )
                    }
                    registry.set(child, for: nodeID)
                }
            }

            guard !running.isEmpty || graph.nodes.contains(where: { $0.status == .blocked }) else {
                throw LoopForgeError.runtimeUnavailable(
                    "The graph has no runnable node. Check its dependency plan."
                )
            }

            let signal = await semaphore.wait()
            switch signal {
            case .turnFinished(let nodeID, let result):
                running.remove(nodeID)
                registry.remove(nodeID)
                try await handleNodeResult(
                    taskID: taskID,
                    nodeID: nodeID,
                    result: result,
                    capability: capability
                )
                if store.task(id: taskID)?.status == .blocked {
                    registry.cancelAll()
                    running.removeAll()
                    return
                }
                if store.task(id: taskID)?.graphState?.nodes
                    .first(where: { $0.id == nodeID })?.status == .blocked {
                    blockMonitors[nodeID]?.cancel()
                    blockMonitors[nodeID] = interventionTimer(
                        nodeID: nodeID,
                        semaphore: semaphore
                    )
                }
            case .turnFailed(let nodeID, let message):
                running.remove(nodeID)
                registry.remove(nodeID)
                await recoverNode(taskID: taskID, nodeID: nodeID, reason: message)
            case .superseded(let nodeID):
                running.remove(nodeID)
                registry.remove(nodeID)
                blockMonitors[nodeID]?.cancel()
                blockMonitors[nodeID] = nil
                if let latestTask = store.task(id: taskID),
                   let latestNode = latestTask.graphState?.nodes
                       .first(where: { $0.id == nodeID }) {
                    await workspaces.cleanup(task: latestTask, node: latestNode)
                }
            case .interventionDue(let nodeID):
                blockMonitors[nodeID]?.cancel()
                blockMonitors[nodeID] = nil
                guard store.task(id: taskID)?.graphState?.nodes.first(where: { $0.id == nodeID })?.status == .blocked else {
                    continue
                }
                await recoverNode(
                    taskID: taskID,
                    nodeID: nodeID,
                    reason: "This node remained blocked for 30 minutes without a successful recovery signal."
                )
            case .cancelled:
                return
            }
        }
    }

    func cancel() {
        isCancelling = true
        checkpointActiveNodesForCancellation()
        activeRegistry?.cancelAll()
        if let semaphore = activeSemaphore {
            Task { await semaphore.signal(.cancelled) }
        }
    }

    func integrateUserSelectedCandidate(
        taskID: UUID,
        candidateID: String
    ) async throws {
        guard let task = store.task(id: taskID),
              task.resolvedExecutionMode == .parallelCandidates,
              (task.status == .awaitingSelection || task.status == .auditing),
              let graph = task.graphState,
              graph.nodes.allSatisfy({ $0.status == .completed }),
              graph.nodes.contains(where: { $0.id == candidateID }) else {
            throw LoopForgeError.runtimeUnavailable(
                "That parallel candidate is not ready to be selected."
            )
        }
        try await integrateParallelWinner(
            taskID: taskID,
            winnerID: candidateID,
            selectionSummary: "Selected by the user after reviewing all completed candidates."
        )
    }

    func cleanupParallelCandidateWorkspaces(task: LoopTask) async {
        guard task.resolvedExecutionMode == .parallelCandidates else { return }
        for candidate in task.graphState?.nodes ?? [] where candidate.isolationRootPath != nil {
            await workspaces.cleanup(task: task, node: candidate)
        }
    }

    private func createParallelCandidateGraph(
        taskID: UUID,
        capability: GraphWorkspaceCapability
    ) {
        guard let task = store.task(id: taskID) else { return }
        let count = ParallelCandidatePolicy.normalizedCount(
            task.resolvedParallelCandidateCount
        )
        let proposals = (1...count).map { index in
            GraphPlanNodeProposal(
                id: "candidate-\(index)",
                title: "Candidate \(index)",
                objective: """
                Produce an independent, complete solution to the entire user goal. Explore your own implementation choices; do not inspect, copy, or coordinate with another candidate. Finish the real product, verification, and evidence in this isolated workspace.
                """,
                dependencies: [],
                writeScopes: ["."],
                verification: [
                    "Map every material user requirement to concrete implementation evidence.",
                    "Run the real primary build/test/launch path and repair failures.",
                    "Retain visual evidence when the requested outcome has a UI."
                ],
                readOnly: false
            )
        }
        let nodes = GraphPlanPolicy.normalizedNodes(proposals)
        let maximum = task.resolvedSubAgent.provider == .local ? 1 : count
        let graph = GraphLoopState(
            phase: .executing,
            planSummary: "\(count) independent full-goal candidates; only one verified winner will be retained.",
            nodes: nodes,
            mainInteractionCount: 0,
            mainLastReview: "Waiting for independent candidate evidence.",
            maxConcurrentNodes: maximum,
            supportsParallelWorktrees: capability.supportsParallelWorktrees,
            finalRepairRounds: 0,
            createdAt: Date(),
            completedAt: nil
        )
        store.update(id: taskID) {
            $0.graphState = graph
            $0.parallelCandidateCount = count
            $0.status = .preparing
            $0.stage = "Preparing \(count) isolated candidate worktrees"
            $0.checkpointedAt = Date()
        }
        store.appendLog(
            id: taskID,
            kind: .system,
            "Parallel Candidates: \(count) independent results · \(maximum) concurrent · clean Git worktree isolation · \(task.resolvedParallelSelectionMode.title). Each candidate must satisfy its own hard active-work target and evidence review."
        )
    }

    private func runParallelCandidates(
        taskID: UUID,
        capability: GraphWorkspaceCapability,
        desktopContext: String
    ) async throws -> Bool {
        let semaphore = GraphSignalSemaphore()
        let registry = GraphChildRegistry()
        activeSemaphore = semaphore
        activeRegistry = registry
        var running = Set<String>()
        defer {
            registry.cancelAll()
            activeRegistry = nil
            activeSemaphore = nil
        }

        while !Task.isCancelled {
            guard let task = store.task(id: taskID),
                  let graph = task.graphState else { return false }
            if graph.nodes.allSatisfy({ $0.status == .completed }), running.isEmpty {
                if task.resolvedParallelSelectionMode == .user {
                    store.update(id: taskID) {
                        $0.status = .awaitingSelection
                        $0.stage = "All candidates passed · choose the result to keep"
                        $0.graphState?.phase = .selectingCandidate
                        $0.resumeOnNextLaunch = false
                    }
                    store.appendLog(
                        id: taskID,
                        kind: .control,
                        "All isolated candidates passed their evidence reviews. No result has been applied to the primary project; the user must choose one."
                    )
                    return false
                }
                let decision = await chooseBestCandidate(task: task, graph: graph)
                try await integrateParallelWinner(
                    taskID: taskID,
                    winnerID: decision.winnerID,
                    selectionSummary: decision.summary
                )
                return true
            }

            let capacity = max(0, graph.maxConcurrentNodes - running.count)
            let ready = graph.nodes.filter {
                $0.status == .waiting && !running.contains($0.id)
            }.prefix(capacity)
            for candidate in ready {
                let prepared = try await workspaces.prepare(
                    task: task,
                    node: candidate,
                    capability: capability
                )
                guard prepared.workspaceStrategy == .gitWorktree else {
                    throw LoopForgeError.runtimeUnavailable(
                        "Candidate \(candidate.id) could not obtain an isolated Git worktree."
                    )
                }
                store.updateGraphNode(taskID: taskID, nodeID: candidate.id) {
                    $0 = prepared
                    $0.status = .preparing
                }
                running.insert(candidate.id)
                let child = Task { [weak self] in
                    guard let self else { return }
                    await self.performNodeTurn(
                        taskID: taskID,
                        nodeID: candidate.id,
                        desktopContext: desktopContext,
                        semaphore: semaphore
                    )
                }
                registry.set(child, for: candidate.id)
            }

            guard !running.isEmpty else {
                throw LoopForgeError.runtimeUnavailable(
                    "No parallel candidate can advance from its durable state."
                )
            }
            switch await semaphore.wait() {
            case .turnFinished(let candidateID, let result):
                running.remove(candidateID)
                registry.remove(candidateID)
                await handleParallelCandidateResult(
                    taskID: taskID,
                    candidateID: candidateID,
                    result: result
                )
                if store.task(id: taskID)?.status == .blocked { return false }
            case .turnFailed(let candidateID, let message):
                running.remove(candidateID)
                registry.remove(candidateID)
                await recoverNode(
                    taskID: taskID,
                    nodeID: candidateID,
                    reason: message
                )
            case .superseded(let candidateID):
                running.remove(candidateID)
                registry.remove(candidateID)
            case .interventionDue:
                continue
            case .cancelled:
                return false
            }
        }
        return false
    }

    private func handleParallelCandidateResult(
        taskID: UUID,
        candidateID: String,
        result: CodexTurnResult
    ) async {
        guard let task = store.task(id: taskID),
              let candidate = task.graphState?.nodes.first(where: { $0.id == candidateID }) else {
            return
        }
        if result.exitCode != 0 {
            let failure = ([result.stderr] + result.eventErrors)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if let blocker = ExternalBlockerPolicy.classifyProcessFailure(failure) {
                updateIterationRecord(
                    taskID: taskID,
                    nodeID: candidateID,
                    iteration: candidate.iteration
                ) {
                    $0.mainReview = "Main Graph Agent stopped this cycle at a verified external boundary: \(blocker.summary)"
                    $0.nextInstruction = ""
                    $0.decision = .externalBlocker
                }
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = blocker.summary
                    $0.externalBlockerKind = blocker.kind
                    $0.externalBlockerMessage = blocker.summary
                    $0.externalBlockerRetryAfter = blocker.retryAfter
                }
                return
            }
            await recoverNode(
                taskID: taskID,
                nodeID: candidateID,
                reason: result.recoveryReason ?? failure
            )
            return
        }

        let refreshed = store.task(id: taskID) ?? task
        let current = refreshed.graphState?.nodes.first(where: { $0.id == candidateID })
            ?? candidate
        let review = await reviewNode(task: refreshed, node: current)
        let remaining = max(0, refreshed.targetSeconds - current.accumulatedActiveSeconds)
        let continuation = remaining > 0
            ? """
              Continue this independent full-goal candidate. Its evidence review is: \(review.summary)
              The user-confirmed per-candidate active-work target still has \(remaining.compactDuration) remaining. Use it for concrete implementation, testing, visual inspection, performance, reliability, and polish; never idle to consume time.
              """
            : (
                review.nextInstruction.isEmpty
                    ? "Close every remaining evidence-backed gap in this independent candidate."
                    : review.nextInstruction
            )
        updateIterationRecord(
            taskID: taskID,
            nodeID: candidateID,
            iteration: current.iteration
        ) {
            $0.mainReview = review.summary
            $0.nextInstruction = remaining > 0 || !review.approved ? continuation : ""
            $0.decision = remaining > 0 || !review.approved ? .continueWork : .approved
        }
        store.appendGraphNodeLog(
            taskID: taskID,
            nodeID: candidateID,
            kind: .audit,
            "Iteration \(current.iteration) Main Agent review · \(review.summary)"
                + (
                    remaining > 0 || !review.approved
                        ? "\nNext instruction · \(continuation)"
                        : ""
                )
        )
        if remaining > 0 || !review.approved {
            store.updateGraphNode(taskID: taskID, nodeID: candidateID) {
                $0.status = .waiting
                $0.lastReview = review.summary
                $0.verification = review.verification ?? $0.verification
                $0.currentInstruction = continuation
            }
            return
        }
        store.updateGraphNode(taskID: taskID, nodeID: candidateID) {
            $0.status = .completed
            $0.completedAt = Date()
            $0.lastReview = review.summary
        }
        store.appendLog(
            id: taskID,
            kind: .audit,
            "\(candidate.title) passed its independent full-goal review. It remains isolated until selection."
        )
    }

    private func chooseBestCandidate(
        task: LoopTask,
        graph: GraphLoopState
    ) async -> ParallelCandidateSelectionEnvelope {
        var scoreByID: [String: Int] = [:]
        var evidenceLines: [String] = []
        var imagePaths: [String] = []
        for candidate in graph.nodes {
            let workspace = candidate.workspacePath ?? task.workspacePath
            let candidateTask = workerTask(
                parent: task,
                node: candidate,
                workspacePath: workspace
            )
            let audit = auditor.audit(task: candidateTask, requireVisualApproval: false)
            let snapshot = auditor.snapshot(workspacePath: workspace, logs: candidate.logs)
            let evidence = await evidenceCollector.collect(
                task: candidateTask,
                workerFeedback: candidate.lastAgentMessage,
                audit: audit,
                before: [:]
            )
            scoreByID[candidate.id] = audit.score
            imagePaths.append(contentsOf: evidence.screenshotPaths)
            evidenceLines.append("""
            \(candidate.id) · \(candidate.title)
            audit=\(audit.score)/100 · \(audit.summary)
            workspace files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles), screenshots=\(snapshot.screenshotFiles)
            independent review=\(candidate.lastReview)
            result=\(candidate.lastAgentMessage.prefixText(1_800))
            coverage=\(evidence.coverage.prefix(12).map { "\($0.requirement):\($0.state.rawValue)" }.joined(separator: " · "))
            """)
        }
        let completedIDs = graph.nodes.map(\.id)
        do {
            let reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: """
                You are LoopForge's independent candidate-selection judge. Choose exactly one completed candidate to retain. Compare fidelity to the verbatim goal, correctness, real verification, visual quality when relevant, usability, performance, reliability, maintainability, and honest limitations. Never reward verbosity or unsupported claims. Return only JSON:
                {"winnerID":"candidate-N","summary":"evidence-backed reason","rankedCandidateIDs":["candidate-N"]}
                Every ranked ID must come from the supplied candidate IDs.
                """,
                user: """
                VERBATIM USER GOAL:
                \(task.originalRequest ?? task.request)

                CANDIDATES:
                \(evidenceLines.joined(separator: "\n\n"))
                """,
                imagePaths: Array(imagePaths.uniqued().prefix(4)),
                maxTokens: 3_500,
                preferred: task.resolvedControlAgent
            )
            if let decoded = Self.decode(
                ParallelCandidateSelectionEnvelope.self,
                from: reply.text
            ), ParallelCandidatePolicy.validWinner(
                decoded.winnerID,
                completedCandidateIDs: completedIDs
            ) {
                return decoded
            }
        } catch {
            store.appendLog(
                id: task.id,
                kind: .warning,
                "Candidate judge was unavailable; LoopForge used the highest deterministic workspace-audit score. \(sanitizedLogText(error.localizedDescription).prefixText(240))"
            )
        }
        let winner = completedIDs.max {
            (scoreByID[$0] ?? 0) < (scoreByID[$1] ?? 0)
        } ?? completedIDs[0]
        return ParallelCandidateSelectionEnvelope(
            winnerID: winner,
            summary: "Deterministic fallback selected \(winner) with the strongest retained workspace-audit score (\(scoreByID[winner] ?? 0)/100).",
            rankedCandidateIDs: completedIDs.sorted {
                (scoreByID[$0] ?? 0) > (scoreByID[$1] ?? 0)
            }
        )
    }

    private func integrateParallelWinner(
        taskID: UUID,
        winnerID: String,
        selectionSummary: String
    ) async throws {
        guard let task = store.task(id: taskID),
              let graph = task.graphState,
              let winner = graph.nodes.first(where: { $0.id == winnerID }),
              winner.status == .completed else {
            throw LoopForgeError.runtimeUnavailable("The selected candidate is unavailable.")
        }
        store.update(id: taskID) {
            // Persist the decision before touching the primary workspace. If
            // LoopForge exits during patch application, run() resumes this
            // exact winner through the coordinator's idempotent integration.
            $0.selectedCandidateID = winnerID
            $0.parallelSelectionSummary = selectionSummary
            $0.parallelWinnerIntegrated = false
            $0.status = .auditing
            $0.stage = "Applying \(winner.title) to the primary project"
            $0.graphState?.phase = .selectingCandidate
        }
        let applied: Bool
        switch await workspaces.integrate(task: task, node: winner) {
        case .noChanges, .applied:
            applied = true
        case .conflict(let detail):
            store.appendGraphNodeLog(
                taskID: taskID,
                nodeID: winnerID,
                kind: .warning,
                "Winner integration needs conflict-aware repair. \(detail)"
            )
            applied = await repairIntegration(
                taskID: taskID,
                nodeID: winnerID,
                conflict: detail
            )
            if applied { await workspaces.cleanup(task: task, node: winner) }
        }
        guard applied else {
            throw LoopForgeError.runtimeUnavailable(
                "The selected candidate could not be integrated without overwriting newer project work."
            )
        }
        for candidate in graph.nodes where candidate.id != winnerID {
            await workspaces.cleanup(task: task, node: candidate)
        }
        store.update(id: taskID) {
            guard var state = $0.graphState else { return }
            for index in state.nodes.indices {
                state.nodes[index].workspacePath = nil
                state.nodes[index].isolationRootPath = nil
                state.nodes[index].integrationBaseCommit = nil
            }
            if let index = state.nodes.firstIndex(where: { $0.id == winnerID }) {
                state.nodes[index].workspacePath = $0.workspacePath
            }
            state.phase = .finalAudit
            state.mainLastReview = selectionSummary
            state.mainInteractionCount += 1
            state.reviewedJoinGroupIDs = Array(Set(state.nodes.map {
                GraphSchedulingPolicy.joinGroupID(for: $0, state: state)
            }))
            $0.graphState = state
            $0.selectedCandidateID = winnerID
            $0.parallelSelectionSummary = selectionSummary
            $0.parallelWinnerIntegrated = true
            $0.controlInteractionCount = state.mainInteractionCount
            $0.status = .auditing
            $0.stage = "\(winner.title) retained · running the whole-project audit"
            $0.resumeOnNextLaunch = true
        }
        store.appendLog(
            id: taskID,
            kind: .audit,
            "Parallel candidate selected: \(winner.title). \(selectionSummary)"
        )
    }

    private func createInitialGraph(
        taskID: UUID,
        capability: GraphWorkspaceCapability
    ) async throws {
        guard let task = store.task(id: taskID) else { return }
        store.update(id: taskID) {
            $0.status = .preparing
            $0.stage = "Main Graph Agent is designing the dependency graph"
        }
        store.appendLog(
            id: taskID,
            kind: .control,
            "Main Graph Agent is decomposing the original goal into independently auditable node loops. Parallel writes are enabled only through clean Git worktrees; otherwise writes remain exclusive."
        )

        let reply: AuxiliaryModelReply?
        do {
            reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: Self.planSystemPrompt,
                user: Self.planUserPrompt(task: task, capability: capability),
                maxTokens: 7_000,
                preferred: task.resolvedControlAgent
            )
        } catch {
            reply = nil
            store.appendLog(
                id: taskID,
                kind: .warning,
                "Every Main Graph Agent provider was unavailable, so LoopForge used its conservative inspect → implement → verify fallback graph. \(sanitizedLogText(error.localizedDescription).prefixText(360))"
            )
        }

        let decoded = reply.flatMap { Self.decode(GraphPlanEnvelope.self, from: $0.text) }
        var nodes = decoded.map { GraphPlanPolicy.initialBatchNodes($0.nodes) }
            ?? GraphPlanPolicy.fallbackNodes(for: task)
        if nodes.isEmpty || !GraphPlanPolicy.isAcyclic(nodes) {
            nodes = GraphPlanPolicy.fallbackNodes(for: task)
        }
        let maximum = task.resolvedSubAgent.provider == .local ? 1 : 3
        let graph = GraphLoopState(
            phase: .executing,
            planSummary: decoded?.summary ?? "Inspect the real workspace before the Main Graph Agent creates any dependent work.",
            nodes: nodes,
            mainInteractionCount: reply == nil ? 0 : 1,
            mainLastReview: "Graph created. Waiting for the first node signal.",
            maxConcurrentNodes: maximum,
            supportsParallelWorktrees: capability.supportsParallelWorktrees,
            finalRepairRounds: 0,
            createdAt: Date(),
            completedAt: nil
        )
        let firstBatchCount = GraphSchedulingPolicy.currentBatchNodes(state: graph).count
        let joinGroupCount = Set(nodes.compactMap(\.joinGroupID)).count
        store.update(id: taskID) {
            $0.graphState = graph
            $0.stage = "Batch 1 ready · \(firstBatchCount) independent node loop\(firstBatchCount == 1 ? "" : "s")"
            $0.controlInteractionCount = graph.mainInteractionCount
            $0.checkpointedAt = Date()
        }
        store.appendLog(
            id: taskID,
            kind: .system,
            "Only the first frontier exists: \(firstBatchCount) predecessor-free node\(firstBatchCount == 1 ? "" : "s") in \(joinGroupCount) predeclared join group\(joinGroupCount == 1 ? "" : "s") · up to \(maximum) concurrent · \(capability.supportsParallelWorktrees ? "isolated Git worktrees available" : "exclusive write safety enabled"). The conservative default is one shared barrier. No future node has been created."
        )
    }

    private func performNodeTurn(
        taskID: UUID,
        nodeID: String,
        desktopContext: String,
        semaphore: GraphSignalSemaphore
    ) async {
        guard let parent = store.task(id: taskID),
              let node = parent.graphState?.nodes.first(where: { $0.id == nodeID }),
              let workspace = node.workspacePath else {
            await semaphore.signal(.turnFailed(nodeID, "The node workspace checkpoint is missing."))
            return
        }
        if node.status == .superseded {
            await semaphore.signal(.superseded(nodeID))
            return
        }
        let existingHistory = GraphIterationHistoryPolicy.records(
            task: parent,
            node: node
        )
        let iteration = GraphIterationHistoryPolicy.nextTurnNumber(
            task: parent,
            node: node
        )
        let resumesPendingIteration = existingHistory.contains {
            $0.number == iteration && $0.decision == .pending
        }
        store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
            $0.status = .running
            $0.iteration = iteration
            $0.activeStartedAt = Date()
            $0.blockedAt = nil
            var history = existingHistory
            if let index = history.firstIndex(where: { $0.number == iteration }) {
                history[index].instruction = $0.currentInstruction
                history[index].finishedAt = nil
                history[index].threadID = $0.threadID
                history[index].exitCode = nil
                history[index].decision = .pending
            } else {
                history.append(
                    GraphNodeIterationRecord(
                        number: iteration,
                        instruction: $0.currentInstruction,
                        startedAt: Date(),
                        finishedAt: nil,
                        threadID: $0.threadID,
                        exitCode: nil,
                        agentSummary: "",
                        mainReview: "",
                        nextInstruction: "",
                        decision: .pending
                    )
                )
            }
            $0.iterationHistory = history
        }
        store.update(id: taskID) {
            $0.status = .running
            $0.stage = "Graph node \(node.title) · iteration \(iteration)"
            $0.checkpointedAt = Date()
        }
        store.appendGraphNodeLog(
            taskID: taskID,
            nodeID: nodeID,
            kind: .control,
            nodePrompt(parent: parent, node: node, iteration: iteration, desktopContext: desktopContext)
        )
        if resumesPendingIteration {
            store.appendGraphNodeLog(
                taskID: taskID,
                nodeID: nodeID,
                kind: .system,
                "Resumed pending iteration \(iteration) from its durable checkpoint. This process restart is not counted as a new iteration; the cycle advances only after a Main Graph Agent decision."
            )
        }
        let executionTask = workerTask(parent: parent, node: node, workspacePath: workspace)
        do {
            let result = try await codex.runTurn(
                task: executionTask,
                prompt: nodePrompt(parent: parent, node: node, iteration: iteration, desktopContext: desktopContext),
                onThreadStarted: { [weak self] threadID in
                    Task { @MainActor in
                        self?.store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                            $0.threadID = threadID
                            if let index = $0.iterationHistory?
                                .firstIndex(where: { $0.number == iteration }) {
                                $0.iterationHistory?[index].threadID = threadID
                            }
                        }
                    }
                },
                onEvent: { [weak self] kind, message in
                    Task { @MainActor in
                        self?.store.appendGraphNodeLog(
                            taskID: taskID,
                            nodeID: nodeID,
                            kind: kind,
                            message
                        )
                    }
                },
                onAgentSignal: { [weak self] signal in
                    guard case .productive = signal else { return }
                    Task { @MainActor in
                        guard let self, !self.isCancelling,
                              let current = self.store.task(id: taskID)?.graphState?.nodes.first(where: { $0.id == nodeID }),
                              current.status == .blocked else { return }
                        self.closeBlockedInterval(taskID: taskID, nodeID: nodeID)
                        self.store.updateGraphNode(taskID: taskID, nodeID: nodeID) { $0.status = .running }
                    }
                },
                onRuntimeEligibilityChanged: { [weak self] eligible, reason in
                    Task { @MainActor in
                        guard let self, !self.isCancelling,
                              let currentStatus = self.store.task(id: taskID)?
                                .graphState?.nodes
                                .first(where: { $0.id == nodeID })?.status,
                              currentStatus == .running || currentStatus == .blocked else {
                            return
                        }
                        if eligible {
                            self.closeBlockedInterval(taskID: taskID, nodeID: nodeID)
                            self.store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                                $0.status = .running
                                if $0.activeStartedAt == nil { $0.activeStartedAt = Date() }
                            }
                        } else {
                            self.store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                                $0.status = .blocked
                                $0.activeStartedAt = nil
                                if $0.blockedAt == nil { $0.blockedAt = Date() }
                            }
                            self.store.appendGraphNodeLog(
                                taskID: taskID,
                                nodeID: nodeID,
                                kind: .warning,
                                "Working-time display paused while transport is unhealthy. \(reason)"
                            )
                        }
                    }
                }
            )
            updateIterationRecord(
                taskID: taskID,
                nodeID: nodeID,
                iteration: iteration
            ) {
                $0.finishedAt = Date()
                $0.exitCode = Int(result.exitCode)
                $0.agentSummary = result.lastAgentMessage
            }
            if store.task(id: taskID)?.graphState?.nodes
                .first(where: { $0.id == nodeID })?.status == .superseded {
                updateIterationRecord(
                    taskID: taskID,
                    nodeID: nodeID,
                    iteration: iteration
                ) {
                    $0.mainReview = "The incremental Main Graph review replaced this branch while the turn was finishing."
                    $0.decision = .superseded
                }
                await semaphore.signal(.superseded(nodeID))
                return
            }
            if isCancelling {
                store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                    $0.activeStartedAt = nil
                    $0.blockedAt = nil
                    $0.status = .waiting
                }
                updateIterationRecord(
                    taskID: taskID,
                    nodeID: nodeID,
                    iteration: iteration
                ) {
                    $0.mainReview = "Interrupted by the user before Main Graph review; the durable node checkpoint was preserved."
                    $0.decision = .pending
                }
                return
            }
            store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                $0.activeStartedAt = nil
                if result.exitCode == 0 {
                    $0.accumulatedActiveSeconds += result.eligibleElapsed
                }
                $0.lastAgentMessage = result.lastAgentMessage
                $0.status = result.exitCode == 0 ? .auditing : .blocked
                if result.exitCode != 0, $0.blockedAt == nil { $0.blockedAt = Date() }
            }
            await semaphore.signal(.turnFinished(nodeID, result))
        } catch is CancellationError {
            if store.task(id: taskID)?.graphState?.nodes
                .first(where: { $0.id == nodeID })?.status == .superseded {
                store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                    if let started = $0.activeStartedAt {
                        $0.accumulatedActiveSeconds += max(0, Date().timeIntervalSince(started))
                    }
                    $0.activeStartedAt = nil
                    $0.blockedAt = nil
                }
                updateIterationRecord(
                    taskID: taskID,
                    nodeID: nodeID,
                    iteration: iteration
                ) {
                    $0.finishedAt = Date()
                    $0.mainReview = "The incremental Main Graph review safely stopped this branch."
                    $0.decision = .superseded
                }
                await semaphore.signal(.superseded(nodeID))
            } else {
                store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                    $0.activeStartedAt = nil
                    $0.blockedAt = nil
                    $0.status = .waiting
                }
                updateIterationRecord(
                    taskID: taskID,
                    nodeID: nodeID,
                    iteration: iteration
                ) {
                    $0.finishedAt = Date()
                    $0.mainReview = "Interrupted before Main Graph review; the node will resume from its durable checkpoint."
                    $0.decision = .pending
                }
            }
        } catch {
            store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                $0.activeStartedAt = nil
                $0.status = .blocked
                if $0.blockedAt == nil { $0.blockedAt = Date() }
            }
            updateIterationRecord(
                taskID: taskID,
                nodeID: nodeID,
                iteration: iteration
            ) {
                $0.finishedAt = Date()
                $0.mainReview = "Execution incident awaiting Main Graph recovery review: \(sanitizedLogText(error.localizedDescription))"
                $0.decision = .recovery
            }
            await semaphore.signal(.turnFailed(nodeID, sanitizedLogText(error.localizedDescription)))
        }
    }

    private func updateIterationRecord(
        taskID: UUID,
        nodeID: String,
        iteration: Int,
        _ mutation: (inout GraphNodeIterationRecord) -> Void
    ) {
        store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
            guard var history = $0.iterationHistory,
                  let index = history.firstIndex(where: { $0.number == iteration }) else {
                return
            }
            mutation(&history[index])
            $0.iterationHistory = history
        }
    }

    private func checkpointActiveNodesForCancellation(now: Date = Date()) {
        guard let taskID = activeTaskID else { return }
        guard let nodes = store.task(id: taskID)?.graphState?.nodes else { return }
        for node in nodes where node.activeStartedAt != nil {
            store.updateGraphNode(taskID: taskID, nodeID: node.id) {
                if let started = $0.activeStartedAt {
                    $0.accumulatedActiveSeconds += max(0, now.timeIntervalSince(started))
                }
                $0.activeStartedAt = nil
                $0.blockedAt = nil
                if $0.status != .completed && $0.status != .superseded {
                    $0.status = .waiting
                }
            }
        }
    }

    private func resumeRecoverableNodes(taskID: UUID) {
        guard let graph = store.task(id: taskID)?.graphState else { return }
        for node in graph.nodes where node.status == .blocked || node.status == .failed {
            store.updateGraphNode(taskID: taskID, nodeID: node.id) {
                $0.status = .waiting
                $0.blockedAt = nil
            }
            store.appendGraphNodeLog(
                taskID: taskID,
                nodeID: node.id,
                kind: .system,
                "Resumed this node from its durable checkpoint. Offline and user-paused time were excluded from working time."
            )
        }
        for node in graph.nodes
        where node.status == .completed && !GraphSchedulingPolicy.isAuditedAndIntegrated(node) {
            store.updateGraphNode(taskID: taskID, nodeID: node.id) {
                $0.status = .waiting
                $0.completedAt = nil
                $0.currentInstruction = """
                This recovered node had a completion marker but no durable Main Graph audit. Re-run its verification, retain exact evidence, and wait for independent approval before any dependent batch can unlock.
                """
            }
            store.appendGraphNodeLog(
                taskID: taskID,
                nodeID: node.id,
                kind: .warning,
                "Recovered a legacy completion without durable Main Graph approval. The node was safely returned to its current batch; no successor was unlocked."
            )
        }
    }

    private func migrateLegacyPreplannedNodes(taskID: UUID) {
        guard let graph = store.task(id: taskID)?.graphState,
              graph.nodes.allSatisfy({ $0.joinGroupID == nil }),
              let currentLevel = GraphSchedulingPolicy.currentBatchLevel(state: graph) else {
            return
        }
        let levels = GraphLayoutPolicy.levels(for: graph.nodes)
        let prematureIDs = Set(graph.nodes.compactMap { node -> String? in
            guard (levels[node.id] ?? 0) > currentLevel,
                  node.status == .waiting,
                  node.iteration == 0,
                  node.logs.isEmpty else {
                return nil
            }
            return node.id
        })
        guard !prematureIDs.isEmpty else { return }
        store.update(id: taskID) {
            $0.graphState?.nodes.removeAll { prematureIDs.contains($0.id) }
            $0.graphState?.planSummary = "Future work is generated one audited batch at a time."
            $0.supervisorCompletionApproved = false
        }
        store.appendLog(
            id: taskID,
            kind: .control,
            "Removed \(prematureIDs.count) unstarted node\(prematureIDs.count == 1 ? "" : "s") created by the legacy up-front planner. The Main Graph Agent will regenerate only the immediate next batch after the current frontier passes review."
        )
    }

    private func handleNodeResult(
        taskID: UUID,
        nodeID: String,
        result: CodexTurnResult,
        capability: GraphWorkspaceCapability
    ) async throws {
        guard let task = store.task(id: taskID),
              let node = task.graphState?.nodes.first(where: { $0.id == nodeID }) else { return }
        if node.status == .superseded {
            await workspaces.cleanup(task: task, node: node)
            return
        }
        if result.exitCode != 0 {
            let failure = ([result.stderr] + result.eventErrors)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if let blocker = ExternalBlockerPolicy.classifyProcessFailure(failure) {
                updateIterationRecord(
                    taskID: taskID,
                    nodeID: nodeID,
                    iteration: node.iteration
                ) {
                    $0.mainReview = "Main Graph Agent stopped this cycle at a verified external boundary: \(blocker.summary)"
                    $0.nextInstruction = ""
                    $0.decision = .externalBlocker
                }
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = blocker.summary
                    $0.externalBlockerKind = blocker.kind
                    $0.externalBlockerMessage = blocker.summary
                    $0.externalBlockerRetryAfter = blocker.retryAfter
                    $0.resumeOnNextLaunch = true
                }
                return
            }
            await recoverNode(
                taskID: taskID,
                nodeID: nodeID,
                reason: result.recoveryReason ?? failure
            )
            return
        }

        let review = await reviewNode(task: task, node: node)
        updateIterationRecord(
            taskID: taskID,
            nodeID: nodeID,
            iteration: node.iteration
        ) {
            $0.mainReview = review.summary
            $0.nextInstruction = review.approved
                ? ""
                : (
                    review.nextInstruction.isEmpty
                        ? "Re-inspect the node objective and retained evidence, then close every unverified gap."
                        : review.nextInstruction
                )
            $0.decision = review.approved ? .approved : .continueWork
        }
        appendMainReview(taskID: taskID, summary: "\(node.title): \(review.summary)")
        store.appendGraphNodeLog(
            taskID: taskID,
            nodeID: nodeID,
            kind: .audit,
            "Iteration \(node.iteration) Main Agent review · \(review.summary)"
                + (
                    review.approved
                        ? ""
                        : "\nNext instruction · \(review.nextInstruction.isEmpty ? "Re-inspect the node objective and retained evidence, then close every unverified gap." : review.nextInstruction)"
                )
        )
        if !review.approved {
            closeBlockedInterval(taskID: taskID, nodeID: nodeID)
            store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                $0.status = .waiting
                $0.currentInstruction = review.nextInstruction.isEmpty
                    ? "Re-inspect the node objective and retained evidence, then close every unverified gap."
                    : review.nextInstruction
                $0.verification = review.verification ?? $0.verification
                $0.lastReview = review.summary
            }
            return
        }

        store.updateGraphNode(taskID: taskID, nodeID: nodeID) { $0.status = .integrating }
        let refreshedTask = store.task(id: taskID) ?? task
        let refreshedNode = refreshedTask.graphState?.nodes.first(where: { $0.id == nodeID }) ?? node
        switch await workspaces.integrate(task: refreshedTask, node: refreshedNode) {
        case .noChanges, .applied:
            closeBlockedInterval(taskID: taskID, nodeID: nodeID)
            store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                $0.status = .completed
                $0.completedAt = Date()
                $0.lastReview = review.summary
                $0.workspacePath = task.workspacePath
                $0.isolationRootPath = nil
            }
            store.appendLog(
                id: taskID,
                kind: .audit,
                "Graph node completed: \(node.title) · \(review.summary)"
            )
        case .conflict(let detail):
            store.appendGraphNodeLog(
                taskID: taskID,
                nodeID: nodeID,
                kind: .warning,
                "The isolated result needs conflict-aware integration. \(detail)"
            )
            let integrated = await repairIntegration(
                taskID: taskID,
                nodeID: nodeID,
                conflict: detail
            )
            if integrated {
                if let latestTask = store.task(id: taskID),
                   let latestNode = latestTask.graphState?.nodes.first(where: { $0.id == nodeID }) {
                    await workspaces.cleanup(task: latestTask, node: latestNode)
                }
                store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                    $0.status = .completed
                    $0.completedAt = Date()
                    $0.lastReview = review.summary
                    $0.workspacePath = task.workspacePath
                    $0.isolationRootPath = nil
                }
            } else {
                markNodeBlocked(
                    taskID: taskID,
                    nodeID: nodeID,
                    message: "Conflict-aware integration did not produce a verified result."
                )
            }
        }
        _ = capability
    }

    private func announceCurrentBatchIfNeeded(taskID: UUID, graph: GraphLoopState) {
        let activeGroups = GraphSchedulingPolicy.activeJoinGroupIDs(state: graph)
        guard !activeGroups.isEmpty else { return }
        let marker = "Graph frontier unlocked:"
        guard store.task(id: taskID)?.logs.contains(where: { $0.message.hasPrefix(marker) }) != true else {
            return
        }
        let reviewed = GraphSchedulingPolicy.reviewedJoinGroupIDs(state: graph)
        let titles = graph.nodes
            .filter {
                !reviewed.contains(
                    GraphSchedulingPolicy.joinGroupID(for: $0, state: graph)
                )
            }
            .map(\.title)
            .joined(separator: " · ")
        store.appendLog(
            id: taskID,
            kind: .control,
            "\(marker) \(titles). The default barrier joins every node dispatched together. A successor can materialize early only for a separately declared join group after every node in that group completes, integrates, and passes Main Graph review."
        )
    }

    private func reviewNode(task: LoopTask, node: GraphLoopNode) async -> GraphNodeReviewEnvelope {
        let workspace = node.workspacePath ?? task.workspacePath
        let nodeTask = workerTask(parent: task, node: node, workspacePath: workspace)
        let snapshot = auditor.snapshot(workspacePath: workspace, logs: node.logs)
        let audit = auditor.audit(task: nodeTask, requireVisualApproval: false)
        let evidence = await evidenceCollector.collect(
            task: nodeTask,
            workerFeedback: node.lastAgentMessage,
            audit: audit,
            before: [:]
        )
        do {
            let reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: Self.nodeReviewSystemPrompt,
                user: Self.nodeReviewUserPrompt(
                    task: task,
                    node: node,
                    audit: audit,
                    snapshot: snapshot,
                    evidence: evidence
                ),
                imagePaths: evidence.screenshotPaths,
                maxTokens: 5_000,
                preferred: task.resolvedControlAgent
            )
            if let decoded = Self.decode(GraphNodeReviewEnvelope.self, from: reply.text) {
                return decoded
            }
        } catch {
            store.appendGraphNodeLog(
                taskID: task.id,
                nodeID: node.id,
                kind: .warning,
                "Main Graph Agent review failed safely: \(sanitizedLogText(error.localizedDescription).prefixText(320))"
            )
        }
        return GraphNodeReviewEnvelope(
            approved: false,
            summary: "The node could not be independently approved from retained evidence.",
            nextInstruction: "Run the node's verification commands, retain exact results, and return a concise evidence-backed completion summary.",
            verification: node.verification,
            addedNodes: nil
        )
    }

    /// Reviews accumulated join-group evidence immediately after each node
    /// completes. This is deliberately separate from the full-group barrier:
    /// it may refine work inside the same group, but it can never unlock a
    /// downstream frontier or consume an unfinished sibling's output.
    private func incrementallyReviewCompletedNode(
        taskID: UUID,
        completedNodeID: String,
        runningIDs: Set<String>,
        registry: GraphChildRegistry
    ) async -> Bool {
        guard var task = store.task(id: taskID),
              let graph = task.graphState,
              let trigger = graph.activeNodes.first(where: { $0.id == completedNodeID }),
              GraphSchedulingPolicy.isAuditedAndIntegrated(trigger) else {
            return false
        }
        let groupID = GraphSchedulingPolicy.joinGroupID(for: trigger, state: graph)
        let group = GraphSchedulingPolicy.nodes(inJoinGroup: groupID, state: graph)
        let completed = group.filter(GraphSchedulingPolicy.isAuditedAndIntegrated)
        guard !completed.isEmpty else { return false }

        store.update(id: taskID) {
            $0.status = .auditing
            $0.stage = "Main Graph Agent is incrementally reviewing \(completed.count)/\(group.count) completed node loops"
            $0.graphState?.phase = .planning
        }
        task = store.task(id: taskID) ?? task
        let audit = auditor.audit(task: task, requireVisualApproval: false)
        let snapshot = auditor.snapshot(workspacePath: task.workspacePath, logs: task.logs)
        let evidence = await evidenceCollector.collect(
            task: task,
            workerFeedback: completed.map(\.lastAgentMessage).joined(separator: "\n\n"),
            audit: audit,
            before: [:]
        )

        do {
            let reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: Self.incrementalJoinReviewSystemPrompt,
                user: Self.incrementalJoinReviewUserPrompt(
                    task: task,
                    graph: graph,
                    groupID: groupID,
                    triggeringNode: trigger,
                    completedNodes: completed,
                    audit: audit,
                    snapshot: snapshot,
                    evidence: evidence
                ),
                imagePaths: evidence.screenshotPaths,
                maxTokens: 6_000,
                preferred: task.resolvedControlAgent
            )
            guard let decision = Self.decode(
                GraphIncrementalJoinReviewEnvelope.self,
                from: reply.text
            ) else {
                throw LoopForgeError.runtimeUnavailable(
                    "The incremental join review did not return the required JSON object."
                )
            }

            let requestedRetirements = Set(decision.retireNodeIDs)
            let safeRetirements = group.filter {
                requestedRetirements.contains($0.id)
                    && $0.id != completedNodeID
                    && GraphIncrementalReviewPolicy.canRetire(
                        $0,
                        in: graph,
                        requestedRetirements: requestedRetirements
                    )
            }
            let safeRetiredIDs = Set(safeRetirements.map(\.id))
            let adjustments = GraphIncrementalReviewPolicy.validAdjustments(
                decision.adjustments,
                groupID: groupID,
                state: graph,
                retiredIDs: safeRetiredIDs
            )
            let additions = GraphPlanPolicy.incrementalJoinNodes(
                decision.addedNodes,
                existingNodes: graph.nodes,
                groupID: groupID,
                completedGroupNodeIDs: completed.map(\.id),
                retiredNodes: safeRetirements,
                triggerNodeID: completedNodeID
            )
            guard graph.nodes.count + additions.count <= GraphPlanPolicy.maximumNodes,
                  GraphPlanPolicy.isAcyclic(graph.nodes + additions) else {
                throw LoopForgeError.runtimeUnavailable(
                    "The incremental review proposed an unsafe, cyclic, or oversized graph change."
                )
            }

            let replacementMap: [String: [String]] = Dictionary(
                grouping: additions.flatMap { addition in
                    (addition.replacesNodeIDs ?? []).map { ($0, addition.id) }
                },
                by: \.0
            ).mapValues { $0.map(\.1).uniqued() }
            let now = Date()
            store.update(id: taskID) {
                guard var currentGraph = $0.graphState else { return }
                for index in currentGraph.nodes.indices {
                    let nodeID = currentGraph.nodes[index].id
                    if safeRetiredIDs.contains(nodeID) {
                        if let started = currentGraph.nodes[index].activeStartedAt {
                            currentGraph.nodes[index].accumulatedActiveSeconds += max(
                                0,
                                now.timeIntervalSince(started)
                            )
                        }
                        if let blockedAt = currentGraph.nodes[index].blockedAt {
                            currentGraph.nodes[index].accumulatedBlockedSeconds += max(
                                0,
                                now.timeIntervalSince(blockedAt)
                            )
                        }
                        currentGraph.nodes[index].activeStartedAt = nil
                        currentGraph.nodes[index].blockedAt = nil
                        currentGraph.nodes[index].status = .superseded
                        currentGraph.nodes[index].supersededAt = now
                        currentGraph.nodes[index].supersededReason = decision.summary
                        currentGraph.nodes[index].supersededByNodeIDs =
                            replacementMap[nodeID] ?? []
                    }
                    if let adjustment = adjustments.first(where: { $0.nodeID == nodeID }) {
                        currentGraph.nodes[index].planAdjustment = adjustment.instruction
                        currentGraph.nodes[index].currentInstruction +=
                            "\n\nMAIN GRAPH PLAN ADJUSTMENT:\n\(adjustment.instruction)"
                        if let verification = adjustment.verification,
                           !verification.isEmpty {
                            currentGraph.nodes[index].verification =
                                (currentGraph.nodes[index].verification + verification).uniqued()
                        }
                    }
                    if nodeID == completedNodeID {
                        currentGraph.nodes[index].incrementalReviewFailures = 0
                    }
                }
                currentGraph.nodes.append(contentsOf: additions)
                var reviewed = currentGraph.incrementallyReviewedNodeIDs ?? []
                if !reviewed.contains(completedNodeID) {
                    reviewed.append(completedNodeID)
                }
                currentGraph.incrementallyReviewedNodeIDs = reviewed
                currentGraph.mainInteractionCount += 1
                currentGraph.mainLastReview =
                    "Incremental review · \(trigger.title): \(decision.summary)"
                currentGraph.planSummary = decision.summary
                currentGraph.phase = .executing
                $0.graphState = currentGraph
                $0.controlInteractionCount = currentGraph.mainInteractionCount
                $0.status = .running
                $0.stage = additions.isEmpty && safeRetirements.isEmpty
                    ? "Incremental review passed · remaining node loops continue"
                    : "Graph plan refined · \(additions.count) added, \(safeRetirements.count) replanned"
                $0.supervisorCompletionApproved = false
            }

            let rejectedRetirements = requestedRetirements.subtracting(safeRetiredIDs)
            if !rejectedRetirements.isEmpty {
                store.appendLog(
                    id: taskID,
                    kind: .warning,
                    "Incremental review ignored unsafe retirement request(s): \(rejectedRetirements.sorted().joined(separator: ", ")). Active shared-workspace writes, completed evidence, and live dependents are never discarded."
                )
            }
            store.appendLog(
                id: taskID,
                kind: .audit,
                "Incremental join review after \(trigger.title): \(decision.summary) · \(completed.count)/\(group.count) completed · \(additions.count) added · \(safeRetirements.count) replanned · \(adjustments.count) adjusted."
            )
            for retired in safeRetirements {
                store.appendGraphNodeLog(
                    taskID: taskID,
                    nodeID: retired.id,
                    kind: .warning,
                    "This historical branch was stopped by an evidence-backed incremental plan review. Its record and working time are retained. \(decision.summary)"
                )
                if runningIDs.contains(retired.id) {
                    registry.cancel(retired.id)
                } else if let latestTask = store.task(id: taskID),
                          let latestNode = latestTask.graphState?.nodes
                              .first(where: { $0.id == retired.id }) {
                    await workspaces.cleanup(task: latestTask, node: latestNode)
                }
            }
            for addition in additions {
                store.appendGraphNodeLog(
                    taskID: taskID,
                    nodeID: addition.id,
                    kind: .control,
                    "Added inside join group \(groupID) by the incremental review after \(trigger.title). This is not a downstream frontier and cannot bypass the group barrier."
                )
            }
            return false
        } catch {
            let detail = sanitizedLogText(error.localizedDescription).prefixText(360)
            var failures = 1
            store.updateGraphNode(taskID: taskID, nodeID: completedNodeID) {
                failures = ($0.incrementalReviewFailures ?? 0) + 1
                $0.incrementalReviewFailures = failures
            }
            store.appendLog(
                id: taskID,
                kind: .warning,
                "Incremental join review failed safely; no graph change was applied. Attempt \(failures)/3. \(detail)"
            )
            if failures >= 3 {
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = "Incremental graph review paused after three provider failures · Resume to retry"
                    $0.resumeOnNextLaunch = true
                    $0.graphState?.phase = .planning
                }
                return true
            }
            store.update(id: taskID) {
                $0.status = .auditing
                $0.stage = "Incremental review temporarily unavailable · retrying without changing the graph"
                $0.graphState?.phase = .planning
            }
            try? await Task.sleep(for: .seconds(10))
            return false
        }
    }

    private func advanceAfterCompletedJoinGroup(
        taskID: UUID,
        groupID: String
    ) async -> GraphBatchAdvanceResult {
        guard var task = store.task(id: taskID),
              var graph = task.graphState else {
            return .retry
        }
        let completedGroup = GraphSchedulingPolicy.nodes(
            inJoinGroup: groupID,
            state: graph
        )
        guard !GraphSchedulingPolicy.reviewedJoinGroupIDs(state: graph)
                  .contains(groupID),
              !completedGroup.isEmpty,
              completedGroup.allSatisfy(GraphSchedulingPolicy.isAuditedAndIntegrated) else {
            return .retry
        }

        graph.phase = .planning
        store.update(id: taskID) {
            $0.status = .auditing
            $0.stage = "Main Graph Agent is reviewing a completed join group before creating any successor"
            $0.graphState = graph
        }
        task = store.task(id: taskID) ?? task
        let preliminary = auditor.audit(task: task, requireVisualApproval: false)
        let snapshot = auditor.snapshot(workspacePath: task.workspacePath, logs: task.logs)
        let evidence = await evidenceCollector.collect(
            task: task,
            workerFeedback: completedGroup.map(\.lastAgentMessage).joined(separator: "\n\n"),
            audit: preliminary,
            before: [:]
        )

        do {
            let reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: Self.batchTransitionSystemPrompt,
                user: Self.batchTransitionUserPrompt(
                    task: task,
                    graph: graph,
                    completedBatch: completedGroup,
                    audit: preliminary,
                    snapshot: snapshot,
                    evidence: evidence
                ),
                imagePaths: evidence.screenshotPaths,
                maxTokens: 6_000,
                preferred: task.resolvedControlAgent
            )
            guard let decision = Self.decode(GraphBatchTransitionEnvelope.self, from: reply.text),
                  GraphPlanPolicy.isValidBatchTransition(decision) else {
                throw LoopForgeError.runtimeUnavailable(
                    "The Main Graph Agent returned an invalid batch transition. It must choose either final audit or one non-empty immediate batch."
                )
            }
            consecutiveBatchTransitionFailures = 0
            appendMainReview(
                taskID: taskID,
                summary: "Join group \(groupID) transition: \(decision.summary)"
            )

            if decision.readyForFinalAudit {
                store.update(id: taskID) {
                    var reviewed = $0.graphState?.reviewedJoinGroupIDs ?? []
                    if !reviewed.contains(groupID) { reviewed.append(groupID) }
                    $0.graphState?.reviewedJoinGroupIDs = reviewed
                    if let updated = $0.graphState,
                       GraphSchedulingPolicy.allNodesAuditedAndIntegrated(state: updated),
                       GraphSchedulingPolicy.allJoinGroupsReviewed(state: updated) {
                        $0.graphState?.phase = .finalAudit
                        $0.status = .auditing
                        $0.stage = "Every join group passed · preparing the whole-project audit"
                    } else {
                        $0.graphState?.phase = .executing
                        $0.status = .running
                        $0.stage = "Independent branch reviewed · waiting for remaining node loops"
                    }
                }
                store.appendLog(
                    id: taskID,
                    kind: .audit,
                    "Join group \(groupID) passed Main Graph review with no safe independent successor. It is closed; the whole-project audit remains locked until every other materialized join group is also complete and reviewed."
                )
                if let updated = store.task(id: taskID)?.graphState,
                   GraphSchedulingPolicy.allNodesAuditedAndIntegrated(state: updated),
                   GraphSchedulingPolicy.allJoinGroupsReviewed(state: updated) {
                    return .readyForFinalAudit
                }
                return .expanded
            }

            let additions = GraphPlanPolicy.nextBatchNodes(
                decision.nextNodes,
                existingNodes: graph.nodes,
                predecessorIDs: completedGroup.map(\.id)
            )
            guard !additions.isEmpty,
                  graph.nodes.count + additions.count <= GraphPlanPolicy.maximumNodes,
                  GraphPlanPolicy.isAcyclic(graph.nodes + additions) else {
                throw LoopForgeError.runtimeUnavailable(
                    "The proposed immediate batch was empty, unsafe, cyclic, or exceeded the graph limit."
                )
            }
            store.update(id: taskID) {
                var reviewed = $0.graphState?.reviewedJoinGroupIDs ?? []
                if !reviewed.contains(groupID) { reviewed.append(groupID) }
                $0.graphState?.reviewedJoinGroupIDs = reviewed
                $0.graphState?.nodes.append(contentsOf: additions)
                $0.graphState?.phase = .executing
                $0.graphState?.planSummary = decision.summary
                $0.status = .running
                $0.stage = "Next frontier ready · \(additions.count) newly assigned node loop\(additions.count == 1 ? "" : "s")"
                $0.supervisorCompletionApproved = false
            }
            store.appendLog(
                id: taskID,
                kind: .control,
                "The Main Graph Agent created \(additions.count) immediate successor node\(additions.count == 1 ? "" : "s") only after every node in join group \(groupID) completed, integrated, and passed group review. Other independent groups may continue; no unreviewed dependency was consumed and no later node exists."
            )
            return .expanded
        } catch {
            consecutiveBatchTransitionFailures += 1
            let detail = sanitizedLogText(error.localizedDescription).prefixText(360)
            store.appendLog(
                id: taskID,
                kind: .warning,
                "Batch transition provider was temporarily unavailable or invalid; no successor node was created. \(detail)"
            )
            if consecutiveBatchTransitionFailures >= 3 {
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = "Join-group transition paused after three provider failures · Resume to retry"
                    $0.resumeOnNextLaunch = true
                    $0.graphState?.phase = .planning
                }
                return .stopped
            }
            store.update(id: taskID) {
                $0.status = .auditing
                $0.stage = "Join-group transition temporarily unavailable · retrying without pre-creating work"
                $0.graphState?.phase = .planning
            }
            try? await Task.sleep(for: .seconds(10))
            return .retry
        }
    }

    private func finalizeOrExpand(taskID: UUID) async throws -> Bool {
        guard var task = store.task(id: taskID), var graph = task.graphState else { return true }
        graph.phase = .finalAudit
        store.update(id: taskID) {
            $0.status = .auditing
            $0.stage = "Main Graph Agent is auditing the integrated outcome"
            $0.graphState = graph
        }
        task = store.task(id: taskID) ?? task
        let preliminary = auditor.audit(task: task, requireVisualApproval: false)
        let evidence = await evidenceCollector.collect(
            task: task,
            workerFeedback: graph.nodes.map(\.lastAgentMessage).joined(separator: "\n\n"),
            audit: preliminary,
            before: [:]
        )
        let snapshot = auditor.snapshot(workspacePath: task.workspacePath, logs: task.logs)
        let reusableApproval = task.supervisorCompletionApproved == true
            && auditor.audit(task: task).passed
            && !graph.mainLastReview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let finalDecision: GraphFinalReviewEnvelope
        if reusableApproval {
            finalDecision = GraphFinalReviewEnvelope(
                approved: true,
                summary: graph.mainLastReview,
                nextInstruction: "",
                visualPassed: task.needsVisualAudit ? task.visualAuditPassed : true,
                addedNodes: nil
            )
            store.appendLog(
                id: task.id,
                kind: .audit,
                "Reused the durable whole-graph approval because the graph and every objective evidence gate are unchanged."
            )
        } else {
            do {
                finalDecision = try await finalReview(
                    task: task,
                    graph: graph,
                    audit: preliminary,
                    snapshot: snapshot,
                    evidence: evidence
                )
                consecutiveFinalReviewFailures = 0
            } catch {
                consecutiveFinalReviewFailures += 1
                let detail = sanitizedLogText(error.localizedDescription).prefixText(360)
                store.appendLog(
                    id: task.id,
                    kind: .warning,
                    "Whole-graph review provider was temporarily unavailable; no repair node was created. \(detail)"
                )
                if consecutiveFinalReviewFailures >= 3 {
                    store.update(id: taskID) {
                        $0.status = .blocked
                        $0.stage = "Final audit paused after three provider failures · Resume to retry"
                        $0.resumeOnNextLaunch = true
                        $0.graphState?.phase = .finalAudit
                    }
                    return true
                }
                store.update(id: taskID) {
                    $0.status = .auditing
                    $0.stage = "Final audit temporarily unavailable · retrying without changing the graph"
                    $0.graphState?.phase = .finalAudit
                }
                try await Task.sleep(for: .seconds(10))
                return false
            }
        }
        let visualPassed = !task.needsVisualAudit || finalDecision.visualPassed == true
        store.update(id: taskID) {
            $0.visualEvidencePaths = evidence.screenshotPaths
            $0.visualAuditPassed = visualPassed
            $0.visualAuditSummary = finalDecision.summary
            $0.supervisorCompletionApproved = finalDecision.approved
            $0.auditScore = preliminary.score
            $0.auditSummary = preliminary.summary
            $0.lastEvidenceCoverage = evidence.coverage.map {
                "\($0.requirement): \($0.state.rawValue)"
            }
            $0.graphState?.mainLastReview = finalDecision.summary
            if !reusableApproval {
                $0.graphState?.mainInteractionCount += 1
            }
            $0.controlInteractionCount = $0.graphState?.mainInteractionCount
        }
        let refreshed = store.task(id: taskID) ?? task
        let finalAudit = auditor.audit(task: refreshed)
        guard finalDecision.approved && finalAudit.passed && visualPassed else {
            guard graph.nodes.count < GraphPlanPolicy.maximumNodes,
                  graph.finalRepairRounds < 8 else {
                store.update(id: taskID) {
                    $0.status = .failed
                    $0.stage = "Graph paused after repeated whole-project audits found the same unresolved evidence gap"
                    $0.resumeOnNextLaunch = false
                }
                return true
            }
            let fallbackRepair = GraphPlanNodeProposal(
                id: "repair-\(graph.finalRepairRounds + 1)",
                title: "Close final audit gaps",
                objective: finalDecision.nextInstruction.isEmpty
                    ? "Reproduce and close the unresolved whole-project evidence gaps, then rerun the primary verification path."
                    : finalDecision.nextInstruction,
                dependencies: [],
                writeScopes: ["."],
                verification: finalAudit.nextActions,
                readOnly: false
            )
            let proposed = finalDecision.addedNodes?.isEmpty == false
                ? finalDecision.addedNodes!
                : [fallbackRepair]
            var repairs = GraphPlanPolicy.finalRepairBatchNodes(
                proposed,
                existingNodes: graph.nodes
            )
            if repairs.isEmpty, finalDecision.addedNodes?.isEmpty == false {
                // A reviewer can identify a real gap yet emit a stale,
                // ambiguous, or future dependency ID. Never pre-create that
                // unsafe plan, but do not strand the task either: materialize
                // one conservative whole-workspace repair on the latest
                // audited frontier and let the next audit refine from reality.
                repairs = GraphPlanPolicy.finalRepairBatchNodes(
                    [fallbackRepair],
                    existingNodes: graph.nodes
                )
                store.appendLog(
                    id: taskID,
                    kind: .warning,
                    "The final reviewer proposed unsafe dependency references. LoopForge discarded them and created one conservative immediate repair on the latest audited frontier."
                )
            }
            guard !repairs.isEmpty,
                  graph.nodes.count + repairs.count <= GraphPlanPolicy.maximumNodes,
                  GraphPlanPolicy.isAcyclic(graph.nodes + repairs) else {
                store.update(id: taskID) {
                    $0.status = .blocked
                    $0.stage = "Final audit requested repair, but no safe immediate repair batch could be created"
                    $0.resumeOnNextLaunch = true
                }
                return true
            }
            store.update(id: taskID) {
                $0.graphState?.nodes.append(contentsOf: repairs)
                $0.status = .running
                $0.stage = "Final audit created \(repairs.count) immediate repair node\(repairs.count == 1 ? "" : "s")"
                $0.supervisorCompletionApproved = false
                $0.graphState?.phase = .executing
                $0.graphState?.finalRepairRounds += 1
            }
            store.appendLog(
                id: taskID,
                kind: .control,
                "The final audit created only the immediate repair batch. No downstream repair or verification node was pre-assigned."
            )
            return false
        }

        store.update(id: taskID) {
            $0.stage = task.resolvedExecutionMode == .parallelCandidates
                ? "Creating the winning-candidate delivery report"
                : "Creating the graph delivery report"
            $0.graphState?.phase = .reporting
        }
        var reportTask = store.task(id: taskID) ?? refreshed
        let narrative = await reportNarrative(
            task: reportTask,
            audit: finalAudit,
            snapshot: snapshot
        )
        reportTask.reportGenerationProvider = narrative.provider
        let path = try reportGenerator.generate(
            task: reportTask,
            audit: finalAudit,
            snapshot: snapshot,
            narrative: narrative.narrative,
            isFinal: true
        )
        store.update(id: taskID) {
            $0.status = .completed
            $0.stage = task.resolvedExecutionMode == .parallelCandidates
                ? "Delivered · the retained candidate and whole-project evidence gates passed"
                : "Delivered · every graph node and whole-project evidence gate passed"
            $0.completedAt = Date()
            $0.completionReportPath = path
            $0.reportGeneratedAt = Date()
            $0.reportGenerationProvider = narrative.provider
            $0.resumeOnNextLaunch = false
            $0.graphState?.phase = .completed
            $0.graphState?.completedAt = Date()
        }
        store.appendLog(
            id: taskID,
            kind: .audit,
            "\(task.resolvedExecutionMode == .parallelCandidates ? "Candidate" : "Graph") delivery report generated at \(path)"
        )
        NSSound(named: "Glass")?.play()
        return true
    }

    private func finalReview(
        task: LoopTask,
        graph: GraphLoopState,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot,
        evidence: AuditEvidence
    ) async throws -> GraphFinalReviewEnvelope {
        let reply = try await router.complete(
            task: task,
            codex: preferredCodex(for: task),
            apiConnections: orderedAPIs(for: task),
            localProfiles: orderedLocals(for: task),
            system: Self.finalReviewSystemPrompt,
            user: Self.finalReviewUserPrompt(
                task: task,
                graph: graph,
                audit: audit,
                snapshot: snapshot,
                evidence: evidence
            ),
            imagePaths: evidence.screenshotPaths,
            maxTokens: 6_000,
            outputSchema: Self.finalReviewOutputSchema,
            preferred: task.resolvedControlAgent,
            timeout: GraphReviewBudgetPolicy.finalAuditTimeout
        )
        if let decoded = Self.decode(GraphFinalReviewEnvelope.self, from: reply.text) {
            return decoded
        }

        store.appendLog(
            id: task.id,
            kind: .warning,
            "The whole-graph reviewer returned an unstructured decision. LoopForge is running one bounded format-repair pass; it will never reinterpret malformed output as approval."
        )
        do {
            let repaired = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: Self.finalReviewFormatRepairSystemPrompt,
                user: Self.finalReviewFormatRepairUserPrompt(raw: reply.text),
                imagePaths: [],
                maxTokens: 2_000,
                outputSchema: Self.finalReviewOutputSchema,
                preferred: task.resolvedControlAgent,
                timeout: 3 * 60
            )
            if let decoded = Self.decode(GraphFinalReviewEnvelope.self, from: repaired.text) {
                return decoded
            }
        } catch {
            store.appendLog(
                id: task.id,
                kind: .warning,
                "The final-review format-repair pass was unavailable. LoopForge will conservatively create a fresh evidence-and-repair node instead of treating malformed output as approval. \(sanitizedLogText(error.localizedDescription).prefixText(240))"
            )
        }

        return GraphFinalReviewEnvelope(
            approved: false,
            summary: "The whole-project reviewer returned an unstructured verdict that could not safely authorize completion.",
            nextInstruction: """
            Re-audit the integrated product from the verbatim goal and retained evidence. Reproduce every worker-disclosed product gap, especially any recovery action reported disabled after repeated use; fix confirmed defects, add regression coverage, rerun the complete primary path, and retain an exact concise result for the next whole-graph audit.
            """,
            visualPassed: false,
            addedNodes: nil
        )
    }

    private func discardRedundantPendingRepairIfAlreadyApproved(taskID: UUID) async {
        guard let task = store.task(id: taskID),
              task.supervisorCompletionApproved == true,
              var graph = task.graphState,
              auditor.audit(task: task).passed else { return }
        let completedIDs = Set(graph.nodes.filter { $0.status == .completed }.map(\.id))
        let redundant = graph.nodes.filter {
            $0.id.hasPrefix("repair-")
                && $0.status != .completed
                && Set($0.dependencies).isSubset(of: completedIDs)
        }
        guard !redundant.isEmpty else { return }

        for node in redundant {
            await workspaces.cleanup(task: task, node: node)
        }
        let redundantIDs = Set(redundant.map(\.id))
        graph.nodes.removeAll { redundantIDs.contains($0.id) }
        graph.finalRepairRounds = max(0, graph.finalRepairRounds - redundant.count)
        graph.phase = .finalAudit
        store.update(id: taskID) {
            $0.graphState = graph
            $0.status = .auditing
            $0.stage = "Removed a redundant repair branch after verified whole-graph approval"
        }
        store.appendLog(
            id: taskID,
            kind: .audit,
            "Removed \(redundant.count) redundant pending repair node(s): the Main Graph Agent had approved the project and all objective evidence gates pass."
        )
    }

    private func recoverNode(taskID: UUID, nodeID: String, reason: String) async {
        guard let task = store.task(id: taskID),
              let node = task.graphState?.nodes.first(where: { $0.id == nodeID }) else { return }
        let system = """
        You are LoopForge's Main Graph Agent handling a node incident. Diagnose
        the retained failure without claiming completion. Return one concise
        recovery instruction for the same node. Preserve work already present,
        avoid broad resets, distinguish transport failure from product failure,
        and include one exact verification step.

        \(GraphDelegationPolicy.noNestedAgentsGuidance)
        """
        let user = """
        ORIGINAL GOAL:
        \(task.originalRequest ?? task.request)

        NODE: \(node.title)
        OBJECTIVE: \(node.objective)
        FAILURE: \(reason)
        LAST RESULT: \(node.lastAgentMessage)
        RECENT NODE ACTIVITY:
        \(node.logs.suffix(18).map { "[\($0.kind.rawValue)] \($0.message)" }.joined(separator: "\n"))
        """
        let instruction: String
        do {
            let reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: system,
                user: user,
                maxTokens: 1_200,
                preferred: task.resolvedControlAgent
            )
            instruction = reply.text
        } catch {
            instruction = "Re-inspect the retained workspace and exact failure, start a fresh Codex session if the saved one is invalid, then rerun the node's primary verification. Do not discard unrelated work."
        }
        closeBlockedInterval(taskID: taskID, nodeID: nodeID)
        let recoveryReview = "Incident review · \(reason)"
        updateIterationRecord(
            taskID: taskID,
            nodeID: nodeID,
            iteration: node.iteration
        ) {
            $0.finishedAt = $0.finishedAt ?? Date()
            $0.mainReview = recoveryReview
            $0.nextInstruction = instruction
            $0.decision = .recovery
        }
        store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
            $0.status = .waiting
            $0.threadID = nil
            $0.currentInstruction = instruction
            $0.consecutiveFailures += 1
            $0.lastReview = "Main Graph Agent recovery: \(reason)"
        }
        store.appendGraphNodeLog(
            taskID: taskID,
            nodeID: nodeID,
            kind: .audit,
            "Iteration \(node.iteration) Main Agent recovery review · \(reason)\nNext instruction · \(instruction)"
        )
        appendMainReview(
            taskID: taskID,
            summary: "Recovered \(node.title): \(instruction.prefixText(360))"
        )
    }

    private func repairIntegration(
        taskID: UUID,
        nodeID: String,
        conflict: String
    ) async -> Bool {
        guard let parent = store.task(id: taskID),
              let node = parent.graphState?.nodes.first(where: { $0.id == nodeID }),
              let isolated = node.workspacePath else { return false }
        var integrationNode = node
        integrationNode.threadID = nil
        integrationNode.workspacePath = parent.workspacePath
        integrationNode.currentInstruction = GraphDelegationPolicy.boundedTurn("""
        Integrate the verified result from the isolated node workspace into the
        primary workspace without overwriting unrelated or newer work.
        Isolated workspace: \(isolated)
        Primary workspace: \(parent.workspacePath)
        Conflict detail: \(conflict)
        Inspect both trees, port only the intended node changes, resolve semantic
        conflicts deliberately, and run the node verification.
        """)
        let execution = workerTask(
            parent: parent,
            node: integrationNode,
            workspacePath: parent.workspacePath
        )
        do {
            let result = try await codex.runTurn(
                task: execution,
                prompt: integrationNode.currentInstruction,
                onThreadStarted: { _ in },
                onEvent: { [weak self] kind, message in
                    Task { @MainActor in
                        self?.store.appendGraphNodeLog(
                            taskID: taskID,
                            nodeID: nodeID,
                            kind: kind,
                            message
                        )
                    }
                }
            )
            store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
                if result.exitCode == 0 { $0.accumulatedActiveSeconds += result.eligibleElapsed }
                $0.lastAgentMessage = result.lastAgentMessage
            }
            return result.exitCode == 0
        } catch {
            store.appendGraphNodeLog(
                taskID: taskID,
                nodeID: nodeID,
                kind: .error,
                sanitizedLogText(error.localizedDescription)
            )
            return false
        }
    }

    private func reportNarrative(
        task: LoopTask,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot
    ) async -> (narrative: CompletionReportNarrative?, provider: String) {
        let system = """
        Author the final LoopForge graph-task report. Return only JSON:
        {"executiveSummary":"outcome","completedWork":["verified item"],
        "currentExperience":"what works now","notableChanges":["change"],
        "evaluation":[{"dimension":"quality","score":0,"evidence":"proof"}],
        "limitations":["honest gap"],"recommendedNextSteps":["optional step"]}
        Use only supplied evidence. Never invent tests, screenshots, performance,
        signing, backend, deployment, or store readiness.

        \(GraphDelegationPolicy.noNestedAgentsGuidance)
        """
        let graphText = task.graphState?.nodes.map {
            "\($0.title) · \($0.status.title) · iterations=\($0.iteration) · active=\($0.accumulatedActiveSeconds.compactDuration) · review=\($0.lastReview)"
        }.joined(separator: "\n") ?? ""
        let user = """
        ORIGINAL REQUEST:
        \(task.originalRequest ?? task.request)
        FINAL AUDIT: \(audit.score)/100 · passed=\(audit.passed)
        \(audit.summary)
        GRAPH NODES:
        \(graphText)
        WORKSPACE: files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles), screenshots=\(snapshot.screenshotFiles)
        EVIDENCE: \((task.lastEvidenceCoverage ?? []).joined(separator: "\n"))
        SCREENSHOTS: \((task.visualEvidencePaths ?? []).joined(separator: "\n"))
        """
        do {
            let reply = try await router.complete(
                task: task,
                codex: preferredCodex(for: task),
                apiConnections: orderedAPIs(for: task),
                localProfiles: orderedLocals(for: task),
                system: system,
                user: user,
                imagePaths: task.visualEvidencePaths ?? [],
                maxTokens: 5_000,
                preferred: task.resolvedControlAgent
            )
            let decoded = CompletionReportGenerator.decodeNarrative(reply.text)
            return decoded.map { ($0, reply.providerLabel) }
                ?? (
                    nil,
                    "Deterministic evidence fallback · \(reply.providerLabel) returned an invalid narrative"
                )
        } catch {
            return (nil, "Deterministic evidence fallback")
        }
    }

    private func nodePrompt(
        parent: LoopTask,
        node: GraphLoopNode,
        iteration: Int,
        desktopContext: String
    ) -> String {
        let roleIntroduction = parent.resolvedExecutionMode == .parallelCandidates
            ? """
            You are one independent full-goal candidate inside LoopForge's
            Parallel Candidates mode. Produce your own complete solution in
            this isolated Git worktree. Never inspect or coordinate with sibling
            candidates. A separate control Agent will audit every result and
            only one candidate will later be retained.
            """
            : """
            You are one independently supervised node loop inside LoopForge's
            Auto Graph Loop. Work only on this bounded node objective. A Main
            Graph Agent will inspect your real workspace and evidence after this
            turn and will either approve the node or return a targeted
            continuation instruction.
            """
        return """
        \(desktopContext)

        \(roleIntroduction)

        \(GraphDelegationPolicy.noNestedAgentsGuidance)

        ORIGINAL USER GOAL:
        \(parent.originalRequest ?? parent.request)

        \(parent.effectiveRequest == (parent.originalRequest ?? parent.request) ? "" : """
        INDEPENDENTLY AUDITED EXECUTION BRIEF:
        \(parent.effectiveRequest)
        """)

        NODE: \(node.title)
        NODE OBJECTIVE:
        \(node.objective)

        CURRENT MAIN-GRAPH INSTRUCTION (iteration \(iteration)):
        \(node.currentInstruction)

        \(node.planAdjustment.map { """
        LATEST INCREMENTAL PLAN ADJUSTMENT:
        \($0)
        """ } ?? "")

        DECLARED WRITE SCOPES:
        \(node.writeScopes.isEmpty ? "Read-only inspection; do not modify product files." : node.writeScopes.joined(separator: "\n"))

        REQUIRED VERIFICATION:
        \(node.verification.isEmpty ? "Run the real primary verification appropriate to this node." : node.verification.joined(separator: "\n"))

        ISOLATION: \(node.workspaceStrategy?.title ?? "Preparing")
        WORKSPACE: \(node.workspacePath ?? parent.workspacePath)

        Preserve unrelated user work. Do not reach beyond this node's declared
        scope. Do not merely describe work: inspect, implement when authorized,
        run real verification, repair failures, and return a concise evidence
        summary with exact paths and command results. If an external boundary is
        genuinely unavoidable, include `LOOPFORGE_STATUS: BLOCKED` and the exact
        failing command or retained evidence.

        PROCESS LIFECYCLE:
        \(GraphNodeOperationalPolicy.longRunningProcessGuidance)
        """
    }

    private func workerTask(
        parent: LoopTask,
        node: GraphLoopNode,
        workspacePath: String
    ) -> LoopTask {
        var task = LoopTask(
            id: parent.id,
            title: node.title,
            request: GraphNodeAccessPolicy.capabilityRequest(for: node),
            quality: parent.quality,
            category: parent.category,
            workspacePath: workspacePath,
            targetSeconds: parent.resolvedExecutionMode == .parallelCandidates
                ? parent.targetSeconds
                : 0,
            accumulatedCodexSeconds: node.accumulatedActiveSeconds,
            model: parent.model,
            status: .running,
            stage: node.status.title,
            iteration: node.iteration,
            threadID: node.threadID,
            auditScore: 0,
            auditSummary: node.lastReview,
            lastAgentMessage: node.lastAgentMessage,
            consecutiveFailures: node.consecutiveFailures,
            createdAt: node.createdAt,
            updatedAt: Date(),
            completedAt: node.completedAt,
            logs: node.logs,
            visualAuditRequired: parent.visualAuditRequired,
            originalRequest: parent.originalRequest ?? parent.request,
            executionMode: parent.resolvedExecutionMode
        )
        task.controlAgent = parent.controlAgent
        if node.readOnly {
            let selected = parent.resolvedSubAgent
            task.subAgent = AgentSelection(
                provider: selected.provider,
                modelID: selected.modelID,
                displayName: selected.displayName,
                reasoningEffort: selected.reasoningEffort,
                accessMode: node.workspaceStrategy == .isolatedVerification ? .workspaceOnly : .readOnly,
                localProfile: selected.localProfile,
                apiConnection: selected.apiConnection
            )
        } else {
            // Full Access remains available to the overall task, but a
            // parallel code-writing node must not inspect or mutate sibling
            // worktrees. Visual/GUI nodes retain Full Access because their
            // objective genuinely crosses the workspace boundary.
            task.subAgent = GraphNodeAccessPolicy.selection(
                parent: parent.resolvedSubAgent,
                node: node,
                category: parent.category
            )
        }
        return task
    }

    private func appendMainReview(taskID: UUID, summary: String) {
        store.update(id: taskID) {
            $0.graphState?.mainInteractionCount += 1
            $0.graphState?.mainLastReview = summary
            $0.controlInteractionCount = $0.graphState?.mainInteractionCount
        }
        store.appendLog(id: taskID, kind: .audit, "Main Graph Agent: \(summary)")
    }

    private func markNodeBlocked(taskID: UUID, nodeID: String, message: String) {
        store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
            $0.status = .blocked
            $0.activeStartedAt = nil
            if $0.blockedAt == nil { $0.blockedAt = Date() }
            $0.lastReview = message
        }
        store.appendGraphNodeLog(taskID: taskID, nodeID: nodeID, kind: .warning, message)
    }

    private func closeBlockedInterval(taskID: UUID, nodeID: String) {
        store.updateGraphNode(taskID: taskID, nodeID: nodeID) {
            if let blockedAt = $0.blockedAt {
                $0.accumulatedBlockedSeconds += max(0, Date().timeIntervalSince(blockedAt))
            }
            $0.blockedAt = nil
        }
    }

    private func interventionTimer(
        nodeID: String,
        semaphore: GraphSignalSemaphore
    ) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(blockMonitorSeconds * 1_000_000_000))
                await semaphore.signal(.interventionDue(nodeID))
            } catch {}
        }
    }

    private func preferredCodex(for task: LoopTask) -> AgentSelection? {
        if task.resolvedControlAgent.provider == .codex { return task.resolvedControlAgent }
        if task.resolvedSubAgent.provider == .codex { return task.resolvedSubAgent }
        guard CodexRuntime.executable != nil else { return nil }
        return .codex(
            model: AppConstants.officialWorkerModel,
            displayName: AppConstants.officialWorkerModel,
            reasoning: "high",
            access: .workspaceOnly
        )
    }

    private func orderedAPIs(for task: LoopTask) -> [APIModelConnection] {
        var result: [APIModelConnection] = []
        if let selected = task.resolvedControlAgent.apiConnection { result.append(selected) }
        if let selected = task.resolvedSubAgent.apiConnection,
           !result.contains(where: { $0.id == selected.id }) {
            result.append(selected)
        }
        for item in agentCatalog.apiConnections where !result.contains(where: { $0.id == item.id }) {
            result.append(item)
        }
        return result
    }

    private func orderedLocals(for task: LoopTask) -> [ModelProfile] {
        var result: [ModelProfile] = []
        if let selected = task.resolvedControlAgent.localProfile,
           agentCatalog.isLocalModelReady(selected) {
            result.append(selected)
        }
        if let selected = task.resolvedSubAgent.localProfile,
           agentCatalog.isLocalModelReady(selected),
           !result.contains(where: { $0.ollamaName == selected.ollamaName }) {
            result.append(selected)
        }
        for item in agentCatalog.localModels
        where agentCatalog.isLocalModelReady(item)
            && !result.contains(where: { $0.ollamaName == item.ollamaName }) {
            result.append(item)
        }
        return result
    }

    static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        }
        if let data = text.data(using: .utf8),
           let direct = try? JSONDecoder().decode(T.self, from: data) {
            return direct
        }
        for candidate in balancedJSONObjects(in: text) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(T.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    private static func balancedJSONObjects(in text: String) -> [String] {
        var results: [String] = []
        var start: String.Index?
        var depth = 0
        var inString = false
        var escaped = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    results.append(String(text[objectStart...index]))
                    // Keep scanning: a provider may emit an invalid example
                    // before the actual decision object.
                    start = nil
                }
            }
            index = text.index(after: index)
        }
        return results
    }

    private static let planSystemPrompt = """
    You are LoopForge's Main Graph Agent creating only the first executable
    frontier of a dynamic engineering graph. Return only
    JSON: {"summary":"plan rationale","nodes":[{"id":"stable-kebab-id",
    "title":"short task","objective":"bounded outcome","dependencies":[],
    "writeScopes":["relative/path"],"verification":["exact check"],
    "readOnly":false,"joinGroup":"frontier"}]}.

    Create 1–3 nodes that have no predecessor and can begin now from the untouched
    workspace. Every dependency array must be empty. Parallelize only genuinely
    independent inspection, research, baseline reproduction, or disjoint work.
    Disjoint paths are necessary but not sufficient: parallel nodes must not
    create competing implementations of the same runtime responsibility. Put
    one owner in charge of each source of truth and state any shared interface
    contract directly in every participating node objective. Require an
    executable handoff check when another concern will consume that interface.
    `joinGroup` is a control-flow barrier, not a visual label. By default give
    every node in this response exactly the same joinGroup. Use different group
    names only in the uncommon case where you can prove that a completed group
    can be reviewed and its immediate successor planned without consuming,
    reconciling, merging, or waiting for any node in another group. Nodes that
    must be considered together—because of a shared contract, combined
    evidence, integration, comparison, or uncertainty—must share one group.
    Decide these groups now, before any node starts; a worker may never split
    its own barrier later.
    Never include a downstream implementation, integration, repair, polish, or
    final-verification node merely because it may be useful later. Those nodes do
    not exist yet and will be decided only after this entire frontier completes
    and passes Main Graph review. Never outline or pre-assign future batches in
    the summary. Never create parallel write nodes with overlapping scopes.
    Preserve every original constraint; do not invent products, credentials,
    platforms, or outputs.

    \(GraphDelegationPolicy.noNestedAgentsGuidance)
    """

    private static func planUserPrompt(
        task: LoopTask,
        capability: GraphWorkspaceCapability
    ) -> String {
        """
        ORIGINAL GOAL:
        \(task.originalRequest ?? task.request)

        \(task.effectiveRequest == (task.originalRequest ?? task.request) ? "" : """
        INDEPENDENTLY AUDITED EXECUTION BRIEF:
        \(task.effectiveRequest)
        """)

        WORKSPACE: \(task.workspacePath)
        CATEGORY: \(task.category.title)
        ACCEPTANCE QUALITY: \(task.quality.title)
        VISUAL EVIDENCE REQUIRED: \(task.needsVisualAudit)
        PARALLEL WRITE ISOLATION: \(capability.supportsParallelWorktrees ? "clean Git worktrees available" : "not available; write nodes must be dependency-serialized")
        """
    }

    private static let nodeReviewSystemPrompt = """
    You are the skeptical Main Graph Agent reviewing one completed node turn.
    Return only JSON: {"approved":true,"summary":"grounded decision",
    "nextInstruction":"specific continuation if rejected","verification":["check"],
    "addedNodes":[]}. Approve only when the node objective is materially complete
    and its verification is supported by retained workspace or command-ledger
    evidence. Reject claims based only on prose, but do not demand that a known
    input be printed verbatim when its byte count, cryptographic hash, and an
    exact comparison already establish identity. Do not repeat a successful
    command merely to change report formatting. A capability-audit node is
    complete when it accurately proves both available and unavailable
    capabilities; an unavailable external tool is a planning constraint, not
    evidence that the audit itself failed. When rejecting, identify one
    concrete unmet outcome and preserve every already-proven check. Prefer
    material risk reduction over redundant evidence with negligible marginal
    value. Always return an empty addedNodes array:
    one node review must never pre-create downstream work. The Main Graph Agent
    will decide the next immediate work only after every node in this node's
    predeclared join group has completed, passed review, and integrated
    successfully. Most frontiers have one group, so this normally means the
    entire frontier.

    \(GraphVerificationPolicy.observedTestCountGuidance)

    \(GraphCompletionPolicy.disclosedGapGuidance)

    \(GraphDelegationPolicy.noNestedAgentsGuidance)
    """

    private static func nodeReviewUserPrompt(
        task: LoopTask,
        node: GraphLoopNode,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot,
        evidence: AuditEvidence
    ) -> String {
        """
        ORIGINAL GOAL: \(task.originalRequest ?? task.request)
        NODE: \(node.title)
        OBJECTIVE: \(node.objective)
        WRITE SCOPES: \(node.writeScopes.joined(separator: ", "))
        REQUIRED VERIFICATION: \(node.verification.joined(separator: " | "))
        INCREMENTAL PLAN ADJUSTMENT: \(node.planAdjustment ?? "None")
        NODE RESULT: \(node.lastAgentMessage)
        DETERMINISTIC AUDIT: \(audit.score)/100 · \(audit.summary)
        FINDINGS: \(audit.findings.joined(separator: " | "))
        WORKSPACE: files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles), screenshots=\(snapshot.screenshotFiles)
        EVIDENCE:
        \(evidence.text)
        """
    }

    private static let incrementalJoinReviewSystemPrompt = """
    You are LoopForge's Main Graph Agent performing a durable incremental review
    immediately after one node in a still-open join group completed, passed its
    independent review, and integrated. Review all completed nodes in this same
    group together. Confirm that the original plan is still safe and useful,
    identify newly exposed ambiguity or design risk, and pre-think the next
    full-group decision. Unfinished siblings remain untrusted: never consume
    their partial output and never create a downstream frontier.

    Return only JSON:
    {"summary":"evidence-backed incremental decision",
    "retireNodeIDs":[],
    "adjustments":[{"nodeID":"active-sibling-id",
    "instruction":"bounded refinement for a later iteration",
    "verification":["exact check"]}],
    "addedNodes":[{"id":"stable-kebab-id","title":"short exploration",
    "objective":"bounded immediate outcome","dependencies":["completed-node-id"],
    "writeScopes":[],"verification":["exact check"],"readOnly":true,
    "joinGroup":"current-group","replacesNodeIDs":[]}]}.

    The normal answer has all three action arrays empty. Change the graph only
    when retained evidence establishes material risk or a valuable ambiguity:
    - addedNodes: at most two immediate explorations or safe replacements inside
      this exact join group. They may depend only on completed nodes listed by
      the caller. A replacement must list every retired node it replaces.
    - adjustments: guidance for an unfinished sibling's future iteration. It
      does not interrupt its current turn; retire and replace only when the
      current work truly has no remaining value.
    - retireNodeIDs: never include completed/integrated nodes. Retire an active
      branch only when continuing it has no useful value and discarding it is
      safe. Shared-primary-workspace writes, nodes with live dependents, and
      evidence already integrated into the primary project are not disposable.

    Do not churn nodes, broaden the user's scope, pre-assign later work, or
    mistake a difference in approach for a defect. If evidence is insufficient,
    preserve the running plan. The full join-group transition still happens
    only after every surviving member—including additions—completes and this
    incremental checkpoint exists for each completed member.

    \(GraphVerificationPolicy.observedTestCountGuidance)

    \(GraphCompletionPolicy.disclosedGapGuidance)

    \(GraphDelegationPolicy.noNestedAgentsGuidance)
    """

    private static func incrementalJoinReviewUserPrompt(
        task: LoopTask,
        graph: GraphLoopState,
        groupID: String,
        triggeringNode: GraphLoopNode,
        completedNodes: [GraphLoopNode],
        audit: AuditResult,
        snapshot: WorkspaceSnapshot,
        evidence: AuditEvidence
    ) -> String {
        let completedIDs = completedNodes.map(\.id)
        let completedText = completedNodes.map {
            "\($0.id): \($0.title) · result=\($0.lastAgentMessage) · independentReview=\($0.lastReview)"
        }.joined(separator: "\n")
        let groupText = GraphSchedulingPolicy.nodes(inJoinGroup: groupID, state: graph)
            .map {
                "\($0.id): \($0.title) · status=\($0.status.title) · readOnly=\($0.readOnly) · isolation=\($0.workspaceStrategy?.title ?? "not started") · dependencies=\($0.dependencies.joined(separator: ","))"
            }
            .joined(separator: "\n")
        return """
        VERBATIM USER GOAL:
        \(task.originalRequest ?? task.request)

        JOIN GROUP: \(groupID)
        NEWLY COMPLETED TRIGGER: \(triggeringNode.id)

        ALL COMPLETED, INTEGRATED MEMBERS — ONLY THESE IDS MAY BE DEPENDENCIES:
        \(completedText)

        ALL CURRENT MEMBERS:
        \(groupText)

        ALLOWED COMPLETED IDS:
        \(completedIDs.joined(separator: ", "))

        WHOLE-WORKSPACE SIGNAL AFTER THE COMPLETED INTEGRATIONS:
        \(audit.score)/100 · \(audit.summary)
        FINDINGS: \(audit.findings.joined(separator: " | "))
        WORKSPACE: files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles), docs=\(snapshot.documentationFiles), screenshots=\(snapshot.screenshotFiles)

        RETAINED EVIDENCE:
        \(evidence.text)

        Decide whether the still-open group should continue unchanged, receive a
        narrow adjustment, gain an evidence-seeking/replacement node, or safely
        retire a no-longer-valuable branch. Do not infer unfinished results.
        """
    }

    private static let batchTransitionSystemPrompt = """
    You are LoopForge's Main Graph Agent awakened only after one predeclared join
    group finished: every node in that group passed its independent evidence
    review and every approved result integrated successfully. Other explicitly
    independent join groups may still be working. Decide this group's control
    flow now using only durable integrated evidence—not an earlier speculative
    plan and never an unfinished sibling's partial output.

    Return only JSON:
    {"readyForFinalAudit":false,"summary":"grounded batch decision",
    "nextNodes":[{"id":"stable-kebab-id","title":"short task",
    "objective":"bounded immediate outcome","dependencies":["completed-node-id"],
    "writeScopes":["relative/path"],"verification":["exact check"],
    "readOnly":false,"joinGroup":"next-frontier"}]}.

    Choose exactly one:
    1. If concrete work can safely continue from this completed group alone, set
       readyForFinalAudit=false and create 1–3 nodes for only that immediate
       successor frontier.
    2. If this branch has no safe independent successor—or its next meaningful
       action must wait to combine with another group—set
       readyForFinalAudit=true and nextNodes=[]. This closes only this branch.
       LoopForge starts the whole-project audit only after every materialized
       join group is complete and reviewed.

    Every next node must depend only on IDs from the just-completed join group.
    Nodes in the new batch must never depend on one another. Parallelize only
    genuinely independent, non-overlapping work. File-scope separation alone
    does not establish independence: assign a single owner for each runtime
    responsibility, prevent placeholder or duplicate implementations from
    becoming competing sources of truth, and embed the same concrete interface
    contract in every node that crosses a boundary. If the newly integrated
    group exposes a need for unfinished sibling-group results, close this branch
    and wait; never invent or consume those results. For the returned nextNodes,
    use one shared joinGroup by default. Split it only when the same strict,
    pre-execution independence proof applies. Do not include, outline, reserve,
    or pre-assign any later batch. Do not approve completion from prose alone.
    Preserve the verbatim user goal and never expand its scope.

    \(GraphVerificationPolicy.observedTestCountGuidance)

    \(GraphCompletionPolicy.disclosedGapGuidance)

    \(GraphDelegationPolicy.noNestedAgentsGuidance)
    """

    private static func batchTransitionUserPrompt(
        task: LoopTask,
        graph: GraphLoopState,
        completedBatch: [GraphLoopNode],
        audit: AuditResult,
        snapshot: WorkspaceSnapshot,
        evidence: AuditEvidence
    ) -> String {
        let history = graph.nodes.map {
            "\($0.id): \($0.title) · \($0.status.title) · review=\($0.lastReview)"
        }.joined(separator: "\n")
        let frontier = completedBatch.map {
            "\($0.id): \($0.title) · result=\($0.lastAgentMessage) · review=\($0.lastReview)"
        }.joined(separator: "\n")
        return """
        VERBATIM USER GOAL:
        \(task.originalRequest ?? task.request)

        MATERIALIZED GRAPH HISTORY (only work that was actually assigned):
        \(history)

        JUST-COMPLETED JOIN GROUP — THESE ARE THE ONLY ALLOWED PREDECESSOR IDS:
        \(frontier)

        CURRENT WORKSPACE:
        \(task.workspacePath)
        files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles), docs=\(snapshot.documentationFiles), screenshots=\(snapshot.screenshotFiles)

        DETERMINISTIC WHOLE-WORKSPACE SIGNAL:
        \(audit.score)/100 · \(audit.summary)
        FINDINGS: \(audit.findings.joined(separator: " | "))
        NEXT ACTION SIGNALS: \(audit.nextActions.joined(separator: " | "))

        RETAINED EVIDENCE:
        \(evidence.text)
        """
    }

    static let finalReviewOutputSchema = """
    {
      "$schema": "http://json-schema.org/draft-07/schema#",
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "approved": { "type": "boolean" },
        "summary": { "type": "string" },
        "nextInstruction": { "type": "string" },
        "visualPassed": { "type": "boolean" },
        "addedNodes": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "id": { "type": "string" },
              "title": { "type": "string" },
              "objective": { "type": "string" },
              "dependencies": {
                "type": "array",
                "items": { "type": "string" }
              },
              "writeScopes": {
                "type": "array",
                "items": { "type": "string" }
              },
              "verification": {
                "type": "array",
                "items": { "type": "string" }
              },
              "readOnly": { "type": "boolean" }
            },
            "required": [
              "id", "title", "objective", "dependencies",
              "writeScopes", "verification", "readOnly"
            ]
          }
        }
      },
      "required": [
        "approved", "summary", "nextInstruction",
        "visualPassed", "addedNodes"
      ]
    }
    """

    private static let finalReviewFormatRepairSystemPrompt = """
    You are a strict JSON formatter, not a new engineering worker. Convert the
    supplied whole-project review into exactly one JSON object with this schema:
    {"approved":false,"summary":"grounded verdict","nextInstruction":"specific repair or empty string","visualPassed":false,"addedNodes":[]}
    Preserve the review's actual approval/rejection and concrete findings. Never
    turn uncertainty, malformed output, or a disclosed product defect into
    approval. Emit no Markdown, analysis, tool calls, or text outside the object.
    """

    private static func finalReviewFormatRepairUserPrompt(raw: String) -> String {
        let cleaned = sanitizedLogText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bounded: String
        if cleaned.count <= 16_000 {
            bounded = cleaned
        } else {
            bounded = """
            \(cleaned.prefix(7_800))
            … \(cleaned.count - 15_600) review characters omitted …
            \(cleaned.suffix(7_800))
            """
        }
        return """
        FORMAT THIS PRIOR REVIEW CONSERVATIVELY:
        \(bounded)
        """
    }

    private static let finalReviewSystemPrompt = """
    You are LoopForge's Main Graph Agent performing the whole-project completion
    audit after every current DAG node passed its own review. Return only JSON:
    {"approved":true,"summary":"grounded whole-project verdict",
    "nextInstruction":"targeted repair if rejected","visualPassed":true,
    "addedNodes":[]}. Compare the verbatim user goal with the integrated
    workspace, real primary-path tests, failure paths, and fresh screenshots
    where required. Node completion is not sufficient. Approve only when the
    actual combined outcome meets the request. Explicitly detect parallel-node
    contract drift, duplicate runtime implementations, unintegrated artifacts,
    and tests that pass only in isolated node workspaces. A capability audit may
    accurately report a missing tool, but that report never waives a required
    user outcome; restore the capability or retain a truthful blocker instead.
    Add targeted repair nodes for
    concrete gaps; never claim store readiness, deployment, signing, backend,
    performance, or visual quality without direct evidence.

    \(GraphCompletionPolicy.disclosedGapGuidance)

    \(GraphDelegationPolicy.noNestedAgentsGuidance)
    """

    private static func finalReviewUserPrompt(
        task: LoopTask,
        graph: GraphLoopState,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot,
        evidence: AuditEvidence
    ) -> String {
        let nodes = graph.nodes.map {
            "\($0.id): \($0.title) · iterations=\($0.iteration) · active=\($0.accumulatedActiveSeconds.compactDuration) · review=\($0.lastReview)"
        }.joined(separator: "\n")
        return """
        VERBATIM USER GOAL:
        \(task.originalRequest ?? task.request)
        EXECUTION RECORD:
        \(nodes)
        \(task.resolvedExecutionMode == .parallelCandidates ? """
        PARALLEL-CANDIDATE CONTRACT:
        Only \(task.selectedCandidateID ?? "no candidate") was retained in the primary workspace.
        Selection review: \(task.parallelSelectionSummary ?? "Unavailable")
        Other candidate records are comparison evidence, not claims that their files were integrated.
        """ : "")
        DETERMINISTIC AUDIT: \(audit.score)/100 · passed=\(audit.passed)
        \(audit.summary)
        FINDINGS: \(audit.findings.joined(separator: " | "))
        WORKSPACE: files=\(snapshot.totalFiles), source=\(snapshot.sourceFiles), tests=\(snapshot.testFiles), screenshots=\(snapshot.screenshotFiles)
        REQUIREMENT EVIDENCE:
        \(evidence.coverageText)
        VISUAL REVIEW:
        \(evidence.visualInspection?.summary ?? "No visual review available")
        """
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    func prefixText(_ count: Int) -> String { String(prefix(count)) }
}
