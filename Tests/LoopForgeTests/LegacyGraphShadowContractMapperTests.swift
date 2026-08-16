import CryptoKit
import XCTest
@testable import LoopForge

final class LegacyGraphShadowContractMapperTests: XCTestCase {
    func testExplicitManifestBuildsPopulatedEffectFreeKernelProjection() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        let manifest = makeManifest(snapshot: snapshot)
        let result = try LegacyGraphShadowContractMapper.bootstrap(
            snapshot: snapshot,
            manifest: manifest,
            runID: KernelRunID("shadow-run")
        )

        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.projection.phase, .ready)
        XCTAssertEqual(result.projection.nodes.map(\.nodeID.rawValue), ["first", "second"])
        XCTAssertTrue(result.projection.nodes.allSatisfy {
            $0.status == .proposed && $0.attemptIDs.isEmpty
        })
        XCTAssertEqual(result.projection.acceptedRequirementCount, 0)
        XCTAssertEqual(result.acceptedLegacySeconds, 0)
        XCTAssertEqual(result.acceptedLegacyReceiptCount, 0)
        XCTAssertFalse(result.permitsExecution)
        XCTAssertFalse(result.permitsMutation)
        XCTAssertFalse(result.permitsIntegration)
        XCTAssertFalse(result.permitsPublication)
        XCTAssertFalse(result.permitsLegacyWriteBack)

        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: result.projection
        )
        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertFalse(comparison.writeBackPermitted)
        XCTAssertFalse(comparison.divergences.contains {
            [
                "legacy-active-node-missing-kernel-contract",
                "legacy-dependency-contract-mismatch",
                "legacy-mutation-scope-contract-mismatch"
            ].contains($0.code)
        })
        XCTAssertTrue(comparison.divergences.contains {
            $0.code == "legacy-completed-node-lacks-kernel-acceptance"
        })
    }

    func testSourceAndObjectiveBindingsFailClosed() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        var sourceMismatch = makeManifest(snapshot: snapshot)
        sourceMismatch.sourceSnapshotDigest = ContentDigest("other")
        XCTAssertThrowsError(try bootstrap(snapshot, sourceMismatch)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .sourceDigestMismatch)
        }

        var objectiveMismatch = makeManifest(snapshot: snapshot)
        objectiveMismatch.taskContract.verbatimObjective = "Rewritten objective"
        XCTAssertThrowsError(try bootstrap(snapshot, objectiveMismatch)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .objectiveMismatch)
        }

        var digestMismatch = makeManifest(snapshot: snapshot)
        digestMismatch.taskContract.objectiveDigest = ContentDigest("unbound")
        XCTAssertThrowsError(try bootstrap(snapshot, digestMismatch)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .objectiveDigestMismatch)
        }
    }

    func testProjectionOnlyPurposeAndProvenanceAreMandatory() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        var malformed = makeManifest(snapshot: snapshot)
        malformed.schemaVersion = 0
        XCTAssertThrowsError(try bootstrap(snapshot, malformed)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .mappingIsNotProjectionOnly)
        }

        malformed = makeManifest(snapshot: snapshot)
        malformed.provenanceClaim.evidenceDigest = ContentDigest("")
        XCTAssertThrowsError(try bootstrap(snapshot, malformed)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .malformedProvenanceClaim)
        }

        malformed = makeManifest(snapshot: snapshot)
        malformed.taskContract.authorityCeiling.permitsExternalPublication = true
        XCTAssertThrowsError(try bootstrap(snapshot, malformed)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .externalPublicationForbidden)
        }
    }

    func testNodeCoverageAndRetirementCoverageMustBeExact() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        var missingActive = makeManifest(snapshot: snapshot)
        missingActive.nodeMappings.removeLast()
        XCTAssertThrowsError(try bootstrap(snapshot, missingActive)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .activeNodeCoverageMismatch)
        }

        var missingRetirement = makeManifest(snapshot: snapshot)
        missingRetirement.retirements = []
        XCTAssertThrowsError(try bootstrap(snapshot, missingRetirement)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .retiredNodeCoverageMismatch)
        }

        var duplicate = makeManifest(snapshot: snapshot)
        duplicate.nodeMappings.append(duplicate.nodeMappings[0])
        XCTAssertThrowsError(try bootstrap(snapshot, duplicate)) {
            XCTAssertEqual($0 as? LegacyGraphShadowMappingError, .duplicateHistoricalNodeID)
        }
    }

    func testNodeIdentityTopologyScopeAndBudgetCannotDrift() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        var manifest = makeManifest(snapshot: snapshot)
        manifest.nodeMappings[0].kernelNode.id = KernelNodeID("renamed")
        XCTAssertThrowsError(try bootstrap(snapshot, manifest)) {
            XCTAssertEqual(
                $0 as? LegacyGraphShadowMappingError,
                .nodeIdentityMismatch("first")
            )
        }

        manifest = makeManifest(snapshot: snapshot)
        manifest.nodeMappings[1].kernelNode.dependencies = []
        XCTAssertThrowsError(try bootstrap(snapshot, manifest)) {
            XCTAssertEqual(
                $0 as? LegacyGraphShadowMappingError,
                .nodeDependencyMismatch("second")
            )
        }

        manifest = makeManifest(snapshot: snapshot)
        manifest.nodeMappings[0].kernelNode.mutationScope.writablePaths = ["Other"]
        XCTAssertThrowsError(try bootstrap(snapshot, manifest)) {
            XCTAssertEqual(
                $0 as? LegacyGraphShadowMappingError,
                .nodeMutationScopeMismatch("first")
            )
        }

        manifest = makeManifest(snapshot: snapshot)
        manifest.nodeMappings[0].kernelNode.mutationScope.maximumChangedBytes = 0
        XCTAssertThrowsError(try bootstrap(snapshot, manifest)) {
            XCTAssertEqual(
                $0 as? LegacyGraphShadowMappingError,
                .nodeMutationBudgetInvalid("first")
            )
        }
    }

    func testRequirementsNeedRecipesAndExactlyOneMandatoryOwner() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        var missingRecipe = makeManifest(snapshot: snapshot)
        missingRecipe.taskContract.requirements[0].evidenceRecipeIDs = []
        XCTAssertThrowsError(try bootstrap(snapshot, missingRecipe)) {
            XCTAssertEqual(
                $0 as? LegacyGraphShadowMappingError,
                .requirementRecipeMissing("requirement-first")
            )
        }

        var duplicateOwner = makeManifest(snapshot: snapshot)
        duplicateOwner.nodeMappings[1].kernelNode.requirementIDs.insert(
            RequirementID("requirement-first")
        )
        XCTAssertThrowsError(try bootstrap(snapshot, duplicateOwner)) {
            XCTAssertEqual(
                $0 as? LegacyGraphShadowMappingError,
                .requirementOwnershipMismatch("requirement-first")
            )
        }
    }

    func testManifestDigestAndReducerEventsAreDeterministic() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        let manifest = makeManifest(snapshot: snapshot)
        let first = try bootstrap(snapshot, manifest)
        let second = try bootstrap(snapshot, manifest)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.manifestDigest, second.manifestDigest)
        XCTAssertEqual(first.events, second.events)
        XCTAssertEqual(first.projection, second.projection)
    }

    func testManifestDigestCanonicalizesSetsButPreservesDeclarationOrder() throws {
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: syntheticTask())
        let manifest = makeManifest(snapshot: snapshot)
        var reordered = manifest
        reordered.taskContract.authorityCeiling.writableScopes = Set(
            reordered.taskContract.authorityCeiling.writableScopes.sorted(by: >)
        )
        for index in reordered.nodeMappings.indices {
            reordered.nodeMappings[index].kernelNode.requirementIDs = Set(
                reordered.nodeMappings[index].kernelNode.requirementIDs.sorted {
                    $0.rawValue > $1.rawValue
                }
            )
            reordered.nodeMappings[index].kernelNode.dependencies = Set(
                reordered.nodeMappings[index].kernelNode.dependencies.sorted {
                    $0.rawValue > $1.rawValue
                }
            )
        }

        let original = try bootstrap(snapshot, manifest)
        let permuted = try bootstrap(snapshot, reordered)
        XCTAssertEqual(original.manifestDigest, permuted.manifestDigest)

        var declarationChanged = manifest
        declarationChanged.nodeMappings.reverse()
        let changed = try bootstrap(snapshot, declarationChanged)
        XCTAssertNotEqual(original.manifestDigest, changed.manifestDigest)
    }

    func testRetainedSnapshotProducesPopulatedCutoverVetoWhenEnabled() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["LOOPFORGE_LEGACY_GRAPH_SNAPSHOT"],
              let outputPath = environment[
                "LOOPFORGE_LEGACY_GRAPH_POPULATED_REPLAY_OUTPUT"
              ] else {
            throw XCTSkip(
                "Set retained snapshot and populated replay output paths to run this audit."
            )
        }
        let inputURL = URL(fileURLWithPath: inputPath)
        let inputBefore = try Data(contentsOf: inputURL)
        let task = try JSONDecoder.loopForge.decode(LoopTask.self, from: inputBefore)
        let snapshot = try LegacyGraphKernelShadowAdapter.snapshot(task: task)
        let manifest = makeManifest(snapshot: snapshot)
        let bootstrap = try LegacyGraphShadowContractMapper.bootstrap(
            snapshot: snapshot,
            manifest: manifest,
            runID: KernelRunID("retained-populated-shadow")
        )
        let comparison = LegacyGraphKernelShadowAdapter.compare(
            legacy: snapshot,
            kernel: bootstrap.projection
        )
        let inputAfter = try Data(contentsOf: inputURL)

        XCTAssertEqual(inputAfter, inputBefore)
        XCTAssertEqual(bootstrap.projection.nodes.count, 14)
        XCTAssertEqual(bootstrap.projection.acceptedRequirementCount, 0)
        XCTAssertTrue(bootstrap.projection.nodes.allSatisfy {
            $0.status == .proposed && $0.attemptIDs.isEmpty
        })
        XCTAssertEqual(bootstrap.acceptedLegacySeconds, 0)
        XCTAssertEqual(bootstrap.acceptedLegacyReceiptCount, 0)
        XCTAssertFalse(bootstrap.permitsExecution)
        XCTAssertFalse(bootstrap.permitsMutation)
        XCTAssertFalse(bootstrap.permitsIntegration)
        XCTAssertFalse(bootstrap.permitsPublication)
        XCTAssertFalse(bootstrap.permitsLegacyWriteBack)
        XCTAssertTrue(comparison.blocksCutover)
        XCTAssertFalse(comparison.writeBackPermitted)
        XCTAssertFalse(comparison.divergences.contains {
            [
                "legacy-active-node-missing-kernel-contract",
                "legacy-dependency-contract-mismatch",
                "legacy-mutation-scope-contract-mismatch"
            ].contains($0.code)
        })

        let envelope = PopulatedReplayEnvelope(
            schemaVersion: 1,
            inputByteCount: inputBefore.count,
            inputSHA256: digest(inputBefore).rawValue,
            inputUnchanged: inputBefore == inputAfter,
            legacyNodeCount: snapshot.nodeObservations.count,
            mappedActiveNodeCount: bootstrap.projection.nodes.count,
            retiredNodeCount: manifest.retirements.count,
            completedNodeClaimCount: snapshot.completedNodeClaimCount,
            acceptedLegacySeconds: bootstrap.acceptedLegacySeconds,
            acceptedLegacyReceiptCount: bootstrap.acceptedLegacyReceiptCount,
            criticalDivergenceCount: comparison.divergences.filter {
                $0.severity == .critical
            }.count,
            blocksCutover: comparison.blocksCutover,
            writeBackPermitted: comparison.writeBackPermitted,
            manifest: manifest,
            bootstrap: bootstrap,
            comparison: comparison
        )
        try LegacyGraphShadowContractMapper.canonicalArtifactData(envelope).write(
            to: URL(fileURLWithPath: outputPath),
            options: .atomic
        )
    }

    private struct PopulatedReplayEnvelope: Codable {
        var schemaVersion: Int
        var inputByteCount: Int
        var inputSHA256: String
        var inputUnchanged: Bool
        var legacyNodeCount: Int
        var mappedActiveNodeCount: Int
        var retiredNodeCount: Int
        var completedNodeClaimCount: Int
        var acceptedLegacySeconds: Double
        var acceptedLegacyReceiptCount: Int
        var criticalDivergenceCount: Int
        var blocksCutover: Bool
        var writeBackPermitted: Bool
        var manifest: LegacyGraphShadowContractManifest
        var bootstrap: LegacyGraphPopulatedShadowBootstrap
        var comparison: GraphKernelShadowComparison
    }

    private func bootstrap(
        _ snapshot: LegacyGraphShadowSnapshot,
        _ manifest: LegacyGraphShadowContractManifest
    ) throws -> LegacyGraphPopulatedShadowBootstrap {
        try LegacyGraphShadowContractMapper.bootstrap(
            snapshot: snapshot,
            manifest: manifest,
            runID: KernelRunID("shadow-run")
        )
    }

    private func makeManifest(
        snapshot: LegacyGraphShadowSnapshot
    ) -> LegacyGraphShadowContractManifest {
        let active = snapshot.nodeObservations.filter {
            $0.statusClaim != GraphNodeStatus.superseded.rawValue
        }.sorted { $0.historicalNodeID < $1.historicalNodeID }
        let retired = snapshot.nodeObservations.filter {
            $0.statusClaim == GraphNodeStatus.superseded.rawValue
        }.sorted { $0.historicalNodeID < $1.historicalNodeID }
        let requirements = active.map { observation in
            RequirementContract(
                id: RequirementID("requirement-\(observation.historicalNodeID)"),
                statement: observation.objectiveClaim,
                mandatory: true,
                evidenceRecipeIDs: [
                    EvidenceRecipeID("recipe-\(observation.historicalNodeID)")
                ]
            )
        }
        let writableScopes = Set(active.flatMap(\.writeScopeClaims))
        let contract = TaskContract(
            id: TaskContractID("shadow-contract-\(snapshot.rawTaskDigest.rawValue)"),
            schemaVersion: 1,
            verbatimObjective: snapshot.objectiveClaim,
            objectiveDigest: digest(Data(snapshot.objectiveClaim.utf8)),
            requirements: requirements,
            constraints: [
                ConstraintContract(
                    id: "projection-only",
                    kind: .prohibit,
                    statement: "This compatibility projection authorizes no effects."
                )
            ],
            nonGoals: ["Execution, mutation, integration, publication, and legacy writeback"],
            protectedBaselines: [],
            authorityCeiling: KernelAuthorityCeiling(
                readableScopes: [],
                writableScopes: writableScopes,
                capabilityIDs: [],
                permitsExternalPublication: false
            ),
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let mappings = active.map { observation in
            let scopes = Set(observation.writeScopeClaims)
            return LegacyGraphShadowNodeMapping(
                historicalNodeID: observation.historicalNodeID,
                historicalNodeDigest: observation.rawNodeDigest,
                kernelNode: KernelNodeContract(
                    id: KernelNodeID(observation.historicalNodeID),
                    requirementIDs: [
                        RequirementID("requirement-\(observation.historicalNodeID)")
                    ],
                    objective: observation.objectiveClaim,
                    dependencies: Set(observation.dependencyClaims.map {
                        KernelNodeID($0)
                    }),
                    mutationScope: KernelMutationScope(
                        writablePaths: scopes,
                        maximumChangedFiles: scopes.isEmpty ? 0 : max(1, scopes.count),
                        maximumChangedBytes: scopes.isEmpty ? 0 : 1
                    ),
                    capabilityIDs: [],
                    strategyFingerprint: StrategyFingerprint(
                        "shadow-strategy-\(observation.rawNodeDigest.rawValue)"
                    )
                )
            )
        }
        let retirements = retired.map { observation in
            LegacyGraphShadowRetirementMapping(
                historicalNodeID: observation.historicalNodeID,
                historicalNodeDigest: observation.rawNodeDigest,
                reasonDigest: ContentDigest(
                    "retired-\(observation.rawNodeDigest.rawValue)"
                ),
                inheritedLessonDigests: [ContentDigest(
                    "lesson-\(observation.rawNodeDigest.rawValue)"
                )]
            )
        }
        return LegacyGraphShadowContractManifest(
            schemaVersion: 1,
            purpose: .projectionOnly,
            sourceSnapshotDigest: snapshot.rawTaskDigest,
            taskContract: contract,
            nodeMappings: mappings,
            retirements: retirements,
            provenanceClaim: LegacyGraphShadowMappingProvenanceClaim(
                actor: ActorIdentity(
                    id: ActorID("shadow-mapping-author"),
                    role: "forensic projection mapper",
                    lineageDigest: ContentDigest("shadow-mapping-lineage")
                ),
                evidenceDigest: snapshot.rawTaskDigest,
                declaredAt: Date(timeIntervalSince1970: 200)
            )
        )
    }

    private func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private func syntheticTask() -> LoopTask {
        let now = Date(timeIntervalSince1970: 100)
        var task = LoopTask(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Synthetic mapping",
            request: "Preserve the exact synthetic objective.",
            quality: .lightweight,
            category: .script,
            workspacePath: "/synthetic/workspace",
            targetSeconds: 0,
            accumulatedCodexSeconds: 0,
            model: .efficientAgent,
            status: .paused,
            stage: "Shadow",
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
            originalRequest: "Preserve the exact synthetic objective.",
            executionMode: .autoGraph
        )
        task.graphState = GraphLoopState(
            phase: .executing,
            planSummary: "Synthetic plan",
            nodes: [
                syntheticNode(id: "first", status: .completed),
                syntheticNode(
                    id: "second",
                    dependencies: ["first"],
                    status: .waiting
                ),
                syntheticNode(id: "old", status: .superseded)
            ],
            mainInteractionCount: 0,
            mainLastReview: "",
            maxConcurrentNodes: 1,
            supportsParallelWorktrees: true,
            finalRepairRounds: 0,
            createdAt: now,
            completedAt: nil
        )
        return task
    }

    private func syntheticNode(
        id: String,
        dependencies: [String] = [],
        status: GraphNodeStatus
    ) -> GraphLoopNode {
        let now = Date(timeIntervalSince1970: 100)
        return GraphLoopNode(
            id: id,
            title: "Node \(id)",
            objective: "Produce bounded evidence for \(id).",
            dependencies: dependencies,
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
            currentInstruction: "Produce bounded evidence.",
            lastAgentMessage: "",
            lastReview: "",
            consecutiveFailures: 0,
            createdAt: now,
            completedAt: status == .completed ? now : nil,
            logs: []
        )
    }
}
