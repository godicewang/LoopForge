import CryptoKit
import Foundation

enum LegacyGraphShadowMappingError: Error, Equatable {
    case mappingIsNotProjectionOnly
    case malformedProvenanceClaim
    case sourceDigestMismatch
    case legacyStructureRejected
    case objectiveMismatch
    case objectiveDigestMismatch
    case externalPublicationForbidden
    case duplicateHistoricalNodeID
    case activeNodeCoverageMismatch
    case retiredNodeCoverageMismatch
    case sourceNodeDigestMismatch(String)
    case nodeIdentityMismatch(String)
    case nodeObjectiveMismatch(String)
    case nodeDependencyMismatch(String)
    case nodeMutationScopeMismatch(String)
    case nodeMutationBudgetInvalid(String)
    case retirementDigestMismatch(String)
    case retirementReasonMissing(String)
    case requirementRecipeMissing(String)
    case requirementOwnershipMismatch(String)
    case kernelRejected(String)
    case encodingFailed
}

enum LegacyGraphShadowMappingPurpose: String, Codable, Hashable, Sendable {
    case projectionOnly
}

struct LegacyGraphShadowMappingProvenanceClaim: Codable, Hashable, Sendable {
    var actor: ActorIdentity
    var evidenceDigest: ContentDigest
    var declaredAt: Date
}

struct LegacyGraphShadowNodeMapping: Codable, Hashable, Sendable {
    var historicalNodeID: String
    var historicalNodeDigest: ContentDigest
    var kernelNode: KernelNodeContract
}

struct LegacyGraphShadowRetirementMapping: Codable, Hashable, Sendable {
    var historicalNodeID: String
    var historicalNodeDigest: ContentDigest
    var reasonDigest: ContentDigest
    var inheritedLessonDigests: Set<ContentDigest>
}

/// A caller-declared compatibility manifest. It is never inferred from legacy
/// prose by production code and never carries execution, mutation, acceptance,
/// integration, publication, or legacy-write authority.
struct LegacyGraphShadowContractManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var purpose: LegacyGraphShadowMappingPurpose
    var sourceSnapshotDigest: ContentDigest
    var taskContract: TaskContract
    var nodeMappings: [LegacyGraphShadowNodeMapping]
    var retirements: [LegacyGraphShadowRetirementMapping]
    var provenanceClaim: LegacyGraphShadowMappingProvenanceClaim
}

struct LegacyGraphPopulatedShadowBootstrap: Codable, Equatable, Sendable {
    var sourceSnapshotDigest: ContentDigest
    var manifestDigest: ContentDigest
    var runID: KernelRunID
    var events: [OrchestrationEvent]
    var projection: KernelRunProjection
    var acceptedLegacySeconds: Double
    var acceptedLegacyReceiptCount: Int
    var permitsExecution: Bool
    var permitsMutation: Bool
    var permitsIntegration: Bool
    var permitsPublication: Bool
    var permitsLegacyWriteBack: Bool
}

/// Validates an explicit compatibility manifest and materializes only the pure
/// reducer's `runCreated` and `planAccepted` events. No node is authorized and
/// no attempt, receipt, resource lease, integration, or effect can be created.
enum LegacyGraphShadowContractMapper {
    static func bootstrap(
        snapshot: LegacyGraphShadowSnapshot,
        manifest: LegacyGraphShadowContractManifest,
        runID: KernelRunID
    ) throws -> LegacyGraphPopulatedShadowBootstrap {
        try validate(snapshot: snapshot, manifest: manifest)
        let manifestData = try canonicalArtifactData(manifest)
        let manifestDigest = digest(manifestData)
        let actor = manifest.provenanceClaim.actor
        var state = KernelRunState.empty(runID: runID)
        var events: [OrchestrationEvent] = []

        let create = RunReducer.handle(
            state: state,
            command: .createRun(manifest.taskContract),
            context: KernelCommandContext(
                commandID: RunCommandID("shadow-create-\(manifestDigest.rawValue)"),
                expectedSequence: state.sequence,
                issuedAt: manifest.provenanceClaim.declaredAt,
                actor: actor
            )
        )
        (state, events) = try accepted(create, priorEvents: events)

        let plan = KernelPlanProposal(
            contractDigest: manifest.taskContract.objectiveDigest,
            nodes: manifest.nodeMappings.map(\.kernelNode)
        )
        let propose = RunReducer.handle(
            state: state,
            command: .proposePlan(plan),
            context: KernelCommandContext(
                commandID: RunCommandID("shadow-plan-\(manifestDigest.rawValue)"),
                expectedSequence: state.sequence,
                issuedAt: manifest.provenanceClaim.declaredAt,
                actor: actor
            )
        )
        (state, events) = try accepted(propose, priorEvents: events)

        return LegacyGraphPopulatedShadowBootstrap(
            sourceSnapshotDigest: snapshot.rawTaskDigest,
            manifestDigest: manifestDigest,
            runID: runID,
            events: events,
            projection: KernelRunProjection(state: state),
            acceptedLegacySeconds: 0,
            acceptedLegacyReceiptCount: 0,
            permitsExecution: false,
            permitsMutation: false,
            permitsIntegration: false,
            permitsPublication: false,
            permitsLegacyWriteBack: false
        )
    }

    private static func validate(
        snapshot: LegacyGraphShadowSnapshot,
        manifest: LegacyGraphShadowContractManifest
    ) throws {
        guard manifest.schemaVersion > 0,
              manifest.purpose == .projectionOnly else {
            throw LegacyGraphShadowMappingError.mappingIsNotProjectionOnly
        }
        let provenance = manifest.provenanceClaim
        guard !provenance.actor.id.rawValue.isEmpty,
              !provenance.actor.role.isEmpty,
              !provenance.actor.lineageDigest.rawValue.isEmpty,
              !provenance.evidenceDigest.rawValue.isEmpty else {
            throw LegacyGraphShadowMappingError.malformedProvenanceClaim
        }
        guard manifest.sourceSnapshotDigest == snapshot.rawTaskDigest else {
            throw LegacyGraphShadowMappingError.sourceDigestMismatch
        }
        guard snapshot.structureIssues.isEmpty else {
            throw LegacyGraphShadowMappingError.legacyStructureRejected
        }
        guard manifest.taskContract.verbatimObjective == snapshot.objectiveClaim else {
            throw LegacyGraphShadowMappingError.objectiveMismatch
        }
        guard manifest.taskContract.objectiveDigest == digest(
            Data(manifest.taskContract.verbatimObjective.utf8)
        ) else {
            throw LegacyGraphShadowMappingError.objectiveDigestMismatch
        }
        guard !manifest.taskContract.authorityCeiling.permitsExternalPublication else {
            throw LegacyGraphShadowMappingError.externalPublicationForbidden
        }
        for requirement in manifest.taskContract.requirements
        where requirement.evidenceRecipeIDs.isEmpty {
            throw LegacyGraphShadowMappingError.requirementRecipeMissing(
                requirement.id.rawValue
            )
        }

        let allLegacy = Dictionary(
            uniqueKeysWithValues: snapshot.nodeObservations.map {
                ($0.historicalNodeID, $0)
            }
        )
        guard allLegacy.count == snapshot.nodeObservations.count else {
            throw LegacyGraphShadowMappingError.duplicateHistoricalNodeID
        }
        let activeLegacyIDs = Set(snapshot.nodeObservations.filter {
            $0.statusClaim != GraphNodeStatus.superseded.rawValue
        }.map(\.historicalNodeID))
        let retiredLegacyIDs = Set(snapshot.nodeObservations.filter {
            $0.statusClaim == GraphNodeStatus.superseded.rawValue
        }.map(\.historicalNodeID))
        let mappedIDs = manifest.nodeMappings.map(\.historicalNodeID)
        let declaredRetiredIDs = manifest.retirements.map(\.historicalNodeID)
        guard Set(mappedIDs).count == mappedIDs.count,
              Set(declaredRetiredIDs).count == declaredRetiredIDs.count else {
            throw LegacyGraphShadowMappingError.duplicateHistoricalNodeID
        }
        guard Set(mappedIDs) == activeLegacyIDs else {
            throw LegacyGraphShadowMappingError.activeNodeCoverageMismatch
        }
        guard Set(declaredRetiredIDs) == retiredLegacyIDs else {
            throw LegacyGraphShadowMappingError.retiredNodeCoverageMismatch
        }

        let knownRequirementIDs = Set(manifest.taskContract.requirements.map(\.id))
        var ownershipCounts: [RequirementID: Int] = [:]
        for mapping in manifest.nodeMappings {
            guard let observation = allLegacy[mapping.historicalNodeID] else {
                throw LegacyGraphShadowMappingError.activeNodeCoverageMismatch
            }
            let node = mapping.kernelNode
            guard mapping.historicalNodeDigest == observation.rawNodeDigest else {
                throw LegacyGraphShadowMappingError.sourceNodeDigestMismatch(
                    mapping.historicalNodeID
                )
            }
            guard node.id.rawValue == mapping.historicalNodeID else {
                throw LegacyGraphShadowMappingError.nodeIdentityMismatch(
                    mapping.historicalNodeID
                )
            }
            guard node.objective == observation.objectiveClaim else {
                throw LegacyGraphShadowMappingError.nodeObjectiveMismatch(
                    mapping.historicalNodeID
                )
            }
            let dependencies = Set(observation.dependencyClaims.map { KernelNodeID($0) })
            guard node.dependencies == dependencies else {
                throw LegacyGraphShadowMappingError.nodeDependencyMismatch(
                    mapping.historicalNodeID
                )
            }
            let scopes = Set(observation.writeScopeClaims)
            guard node.mutationScope.writablePaths == scopes,
                  !(observation.readOnlyClaim && !scopes.isEmpty) else {
                throw LegacyGraphShadowMappingError.nodeMutationScopeMismatch(
                    mapping.historicalNodeID
                )
            }
            let budget = node.mutationScope
            let validBudget = scopes.isEmpty
                ? budget.maximumChangedFiles == 0 && budget.maximumChangedBytes == 0
                : budget.maximumChangedFiles > 0 && budget.maximumChangedBytes > 0
            guard validBudget else {
                throw LegacyGraphShadowMappingError.nodeMutationBudgetInvalid(
                    mapping.historicalNodeID
                )
            }
            guard !node.requirementIDs.isEmpty,
                  node.requirementIDs.isSubset(of: knownRequirementIDs) else {
                throw LegacyGraphShadowMappingError.requirementOwnershipMismatch(
                    mapping.historicalNodeID
                )
            }
            for requirementID in node.requirementIDs {
                ownershipCounts[requirementID, default: 0] += 1
            }
        }
        for requirementID in manifest.taskContract.mandatoryRequirementIDs
        where ownershipCounts[requirementID] != 1 {
            throw LegacyGraphShadowMappingError.requirementOwnershipMismatch(
                requirementID.rawValue
            )
        }
        for retirement in manifest.retirements {
            guard let observation = allLegacy[retirement.historicalNodeID],
                  retirement.historicalNodeDigest == observation.rawNodeDigest else {
                throw LegacyGraphShadowMappingError.retirementDigestMismatch(
                    retirement.historicalNodeID
                )
            }
            guard !retirement.reasonDigest.rawValue.isEmpty,
                  !retirement.inheritedLessonDigests.isEmpty,
                  !retirement.inheritedLessonDigests.contains(where: {
                    $0.rawValue.isEmpty
                  }) else {
                throw LegacyGraphShadowMappingError.retirementReasonMissing(
                    retirement.historicalNodeID
                )
            }
        }
    }

    private static func accepted(
        _ decision: ReducerDecision,
        priorEvents: [OrchestrationEvent]
    ) throws -> (KernelRunState, [OrchestrationEvent]) {
        guard case .accepted(let newEvents, let state) = decision else {
            guard case .rejected(let rejection) = decision else {
                throw LegacyGraphShadowMappingError.kernelRejected("unknown")
            }
            throw LegacyGraphShadowMappingError.kernelRejected(String(describing: rejection))
        }
        return (state, priorEvents + newEvents)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(value)
        } catch {
            throw LegacyGraphShadowMappingError.encodingFailed
        }
    }

    /// Produces stable bytes across process hash seeds while preserving ordered
    /// arrays such as reducer events and manifest declarations. Only fields
    /// whose Swift types are sets are sorted by their own canonical bytes.
    static func canonicalArtifactData<T: Encodable>(_ value: T) throws -> Data {
        do {
            let object = try JSONSerialization.jsonObject(
                with: encoded(value),
                options: [.fragmentsAllowed]
            )
            let canonical = try canonicalized(object, fieldName: nil)
            return try JSONSerialization.data(
                withJSONObject: canonical,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch let error as LegacyGraphShadowMappingError {
            throw error
        } catch {
            throw LegacyGraphShadowMappingError.encodingFailed
        }
    }

    private static let unorderedArrayFieldNames: Set<String> = [
        "acceptedReceiptIDs",
        "acceptedRequirementIDs",
        "capabilityIDs",
        "dependencies",
        "dependencyNodeIDs",
        "evidenceRecipeIDs",
        "inheritedLessonDigests",
        "readableScopes",
        "requirementIDs",
        "writablePaths",
        "writableScopes"
    ]

    private static func canonicalized(
        _ value: Any,
        fieldName: String?
    ) throws -> Any {
        if let dictionary = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            for (key, child) in dictionary {
                normalized[key] = try canonicalized(child, fieldName: key)
            }
            return normalized
        }
        if let array = value as? [Any] {
            let normalized = try array.map {
                try canonicalized($0, fieldName: nil)
            }
            guard fieldName.map(unorderedArrayFieldNames.contains) == true else {
                return normalized
            }
            return try normalized.sorted {
                try canonicalSortKey($0).lexicographicallyPrecedes(
                    canonicalSortKey($1)
                )
            }
        }
        return value
    }

    private static func canonicalSortKey(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}
