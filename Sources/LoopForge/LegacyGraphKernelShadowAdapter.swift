import CryptoKit
import Foundation

enum LegacyGraphShadowError: Error, Equatable {
    case missingGraph
    case encodingFailed
}

struct LegacyGraphStructureIssue: Codable, Hashable, Sendable {
    var code: String
    var subjectIDs: [String]
}

struct LegacyGraphNodeObservation: Codable, Hashable, Sendable {
    var rawNodeDigest: ContentDigest
    var historicalNodeID: String
    var objectiveClaim: String
    var dependencyClaims: [String]
    var writeScopeClaims: [String]
    var verificationClaims: [String]
    var readOnlyClaim: Bool
    var statusClaim: String
    var iterationObservation: Int
    var rawActiveSeconds: Double
    var acceptedActiveSeconds: Double
    var reviewClaim: String?
    var acceptedReceiptIDs: Set<ReceiptID>
    var maySchedule: Bool
    var mayIntegrate: Bool
}

struct LegacyGraphShadowSnapshot: Codable, Hashable, Sendable {
    var rawTaskDigest: ContentDigest
    var historicalTaskID: String
    var objectiveClaim: String
    var taskStatusClaim: String
    var graphPhaseClaim: String
    var visualApprovalClaim: Bool?
    var nodeObservations: [LegacyGraphNodeObservation]
    var structureIssues: [LegacyGraphStructureIssue]
    var acceptedReceiptIDs: Set<ReceiptID>
    var mayAutoResume: Bool
    var mayWriteLegacyState: Bool
    var mayAuthorizeEffects: Bool

    var completedNodeClaimCount: Int {
        nodeObservations.filter { $0.statusClaim == GraphNodeStatus.completed.rawValue }.count
    }

    var workingNodeClaimCount: Int {
        let working = Set([
            GraphNodeStatus.preparing.rawValue,
            GraphNodeStatus.running.rawValue,
            GraphNodeStatus.auditing.rawValue,
            GraphNodeStatus.integrating.rawValue
        ])
        return nodeObservations.filter { working.contains($0.statusClaim) }.count
    }
}

enum GraphKernelShadowSeverity: String, Codable, Hashable, Sendable {
    case information
    case warning
    case critical
}

struct GraphKernelShadowDivergence: Codable, Hashable, Sendable {
    var code: String
    var severity: GraphKernelShadowSeverity
    var legacyValue: String
    var kernelValue: String
}

struct GraphKernelShadowComparison: Codable, Hashable, Sendable {
    var legacyTaskDigest: ContentDigest
    var kernelRunID: KernelRunID
    var kernelSequence: UInt64
    var divergences: [GraphKernelShadowDivergence]
    var comparisonDigest: ContentDigest
    var blocksCutover: Bool
    var writeBackPermitted: Bool
}

/// Imports the mutable Graph checkpoint strictly as read-only claims. Shadow
/// mode has no method that returns RunCommand, receipt, mutation, scheduling,
/// integration, publication, or legacy-store write authority.
enum LegacyGraphKernelShadowAdapter {
    static func snapshot(task: LoopTask) throws -> LegacyGraphShadowSnapshot {
        guard let graph = task.graphState else { throw LegacyGraphShadowError.missingGraph }
        let taskData = try encoded(task)
        let nodeIDs = graph.nodes.map(\.id)
        let knownIDs = Set(nodeIDs)
        var issues: [LegacyGraphStructureIssue] = []
        let duplicateIDs = Dictionary(grouping: nodeIDs, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        if !duplicateIDs.isEmpty {
            issues.append(LegacyGraphStructureIssue(
                code: "duplicate-node-identifiers",
                subjectIDs: duplicateIDs
            ))
        }
        let unknownDependencies = Set(graph.nodes.flatMap { node in
            node.dependencies.filter { !knownIDs.contains($0) }
        }).sorted()
        if !unknownDependencies.isEmpty {
            issues.append(LegacyGraphStructureIssue(
                code: "unknown-dependency-identifiers",
                subjectIDs: unknownDependencies
            ))
        }
        if !isAcyclic(graph.nodes) {
            issues.append(LegacyGraphStructureIssue(
                code: "dependency-cycle",
                subjectIDs: nodeIDs.sorted()
            ))
        }
        let emptyObjectives = graph.nodes.filter {
            $0.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map(\.id).sorted()
        if !emptyObjectives.isEmpty {
            issues.append(LegacyGraphStructureIssue(
                code: "empty-objective-claim",
                subjectIDs: emptyObjectives
            ))
        }

        let observations = try graph.nodes.map { node in
            LegacyGraphNodeObservation(
                rawNodeDigest: digest(try encoded(node)),
                historicalNodeID: node.id,
                objectiveClaim: node.objective,
                dependencyClaims: node.dependencies,
                writeScopeClaims: node.writeScopes,
                verificationClaims: node.verification,
                readOnlyClaim: node.readOnly,
                statusClaim: node.status.rawValue,
                iterationObservation: node.iteration,
                rawActiveSeconds: node.liveActiveSeconds(at: task.updatedAt),
                acceptedActiveSeconds: 0,
                reviewClaim: node.lastReview.isEmpty ? nil : node.lastReview,
                acceptedReceiptIDs: [],
                maySchedule: false,
                mayIntegrate: false
            )
        }
        return LegacyGraphShadowSnapshot(
            rawTaskDigest: digest(taskData),
            historicalTaskID: task.id.uuidString,
            objectiveClaim: task.originalRequest ?? task.request,
            taskStatusClaim: task.status.rawValue,
            graphPhaseClaim: graph.phase.rawValue,
            visualApprovalClaim: task.visualAuditPassed,
            nodeObservations: observations,
            structureIssues: issues.sorted { $0.code < $1.code },
            acceptedReceiptIDs: [],
            mayAutoResume: false,
            mayWriteLegacyState: false,
            mayAuthorizeEffects: false
        )
    }

    static func compare(
        legacy: LegacyGraphShadowSnapshot,
        kernel: KernelRunProjection
    ) -> GraphKernelShadowComparison {
        var differences: [GraphKernelShadowDivergence] = legacy.structureIssues.map {
            GraphKernelShadowDivergence(
                code: "legacy-structure-\($0.code)",
                severity: .critical,
                legacyValue: $0.subjectIDs.joined(separator: ","),
                kernelValue: "rejected"
            )
        }
        let legacyCompleted = legacy.taskStatusClaim == LoopTaskStatus.completed.rawValue
            || legacy.graphPhaseClaim == GraphLoopPhase.completed.rawValue
        if legacyCompleted && kernel.phase != .completed {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-terminal-without-kernel-authority",
                severity: .critical,
                legacyValue: "completed",
                kernelValue: kernel.phase.rawValue
            ))
        }
        if legacyCompleted && !kernel.quiescent {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-completion-without-kernel-quiescence",
                severity: .critical,
                legacyValue: "completed",
                kernelValue: "not-quiescent"
            ))
        }
        if legacy.taskStatusClaim == LoopTaskStatus.stopped.rawValue && !kernel.quiescent {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-stop-without-kernel-quiescence",
                severity: .critical,
                legacyValue: "stopped",
                kernelValue: "not-quiescent"
            ))
        }
        if legacy.completedNodeClaimCount > kernel.acceptedRequirementCount {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-node-approval-exceeds-kernel-evidence",
                severity: .critical,
                legacyValue: String(legacy.completedNodeClaimCount),
                kernelValue: String(kernel.acceptedRequirementCount)
            ))
        }
        if legacy.visualApprovalClaim == true && kernel.latestVisualAccepted != true {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-visual-pass-without-kernel-gate",
                severity: .critical,
                legacyValue: "passed",
                kernelValue: kernel.latestVisualAccepted.map(String.init) ?? "missing"
            ))
        }
        if kernel.phase == .completed && !legacyCompleted {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-projection-lags-kernel-completion",
                severity: .information,
                legacyValue: legacy.taskStatusClaim,
                kernelValue: "completed"
            ))
        }
        if kernel.activeAttemptID != nil && legacy.workingNodeClaimCount == 0 {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-projection-lags-kernel-attempt",
                severity: .information,
                legacyValue: "none",
                kernelValue: kernel.activeAttemptID?.rawValue ?? "none"
            ))
        }
        let kernelByNodeID = Dictionary(uniqueKeysWithValues: kernel.nodes.map {
            ($0.nodeID.rawValue, $0)
        })
        let activeLegacyNodes = legacy.nodeObservations.filter {
            $0.statusClaim != GraphNodeStatus.superseded.rawValue
        }
        let legacyNodeIDs = Set(activeLegacyNodes.map(\.historicalNodeID))
        let workingStatuses = Set([
            GraphNodeStatus.preparing.rawValue,
            GraphNodeStatus.running.rawValue,
            GraphNodeStatus.auditing.rawValue,
            GraphNodeStatus.integrating.rawValue
        ])
        for observation in activeLegacyNodes {
            guard let projected = kernelByNodeID[observation.historicalNodeID] else {
                differences.append(GraphKernelShadowDivergence(
                    code: "legacy-active-node-missing-kernel-contract",
                    severity: .critical,
                    legacyValue: observation.historicalNodeID,
                    kernelValue: "missing"
                ))
                continue
            }
            let legacyDependencies = Set(observation.dependencyClaims)
            let kernelDependencies = Set(projected.dependencyNodeIDs.map(\.rawValue))
            if legacyDependencies != kernelDependencies {
                differences.append(GraphKernelShadowDivergence(
                    code: "legacy-dependency-contract-mismatch",
                    severity: .critical,
                    legacyValue: legacyDependencies.sorted().joined(separator: ","),
                    kernelValue: kernelDependencies.sorted().joined(separator: ",")
                ))
            }
            let legacyScopes = Set(observation.writeScopeClaims)
            if legacyScopes != projected.writablePaths
                || (observation.readOnlyClaim && !projected.writablePaths.isEmpty) {
                differences.append(GraphKernelShadowDivergence(
                    code: "legacy-mutation-scope-contract-mismatch",
                    severity: .critical,
                    legacyValue: legacyScopes.sorted().joined(separator: ","),
                    kernelValue: projected.writablePaths.sorted().joined(separator: ",")
                ))
            }
            if observation.statusClaim == GraphNodeStatus.completed.rawValue,
               projected.status != .accepted || !projected.allRequirementsAccepted {
                differences.append(GraphKernelShadowDivergence(
                    code: "legacy-completed-node-lacks-kernel-acceptance",
                    severity: .critical,
                    legacyValue: observation.historicalNodeID,
                    kernelValue: projected.status.rawValue
                ))
            }
            if workingStatuses.contains(observation.statusClaim),
               projected.activeAttemptID == nil {
                differences.append(GraphKernelShadowDivergence(
                    code: "legacy-work-without-kernel-attempt",
                    severity: .critical,
                    legacyValue: observation.historicalNodeID,
                    kernelValue: "none"
                ))
            }
        }
        for projected in kernel.nodes where !legacyNodeIDs.contains(projected.nodeID.rawValue) {
            differences.append(GraphKernelShadowDivergence(
                code: "legacy-projection-missing-kernel-node",
                severity: .information,
                legacyValue: "missing",
                kernelValue: projected.nodeID.rawValue
            ))
        }
        differences.sort {
            ($0.code, $0.legacyValue, $0.kernelValue)
                < ($1.code, $1.legacyValue, $1.kernelValue)
        }
        let material = ComparisonDigestEnvelope(
            legacyTaskDigest: legacy.rawTaskDigest,
            kernelRunID: kernel.runID,
            kernelSequence: kernel.sequence,
            divergences: differences
        )
        let comparisonDigest = (try? encoded(material)).map(digest) ?? ContentDigest("")
        return GraphKernelShadowComparison(
            legacyTaskDigest: legacy.rawTaskDigest,
            kernelRunID: kernel.runID,
            kernelSequence: kernel.sequence,
            divergences: differences,
            comparisonDigest: comparisonDigest,
            blocksCutover: differences.contains { $0.severity == .critical },
            writeBackPermitted: false
        )
    }

    private struct ComparisonDigestEnvelope: Encodable {
        var legacyTaskDigest: ContentDigest
        var kernelRunID: KernelRunID
        var kernelSequence: UInt64
        var divergences: [GraphKernelShadowDivergence]
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else {
            throw LegacyGraphShadowError.encodingFailed
        }
        return data
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func isAcyclic(_ nodes: [GraphLoopNode]) -> Bool {
        let known = Set(nodes.map(\.id))
        let dependencies = nodes.reduce(into: [String: [String]]()) { result, node in
            if result[node.id] == nil {
                result[node.id] = node.dependencies.filter(known.contains)
            }
        }
        var visiting: Set<String> = []
        var visited: Set<String> = []
        func visit(_ id: String) -> Bool {
            if visiting.contains(id) { return false }
            if visited.contains(id) { return true }
            visiting.insert(id)
            for dependency in dependencies[id] ?? [] where !visit(dependency) {
                return false
            }
            visiting.remove(id)
            visited.insert(id)
            return true
        }
        return known.allSatisfy(visit)
    }
}
