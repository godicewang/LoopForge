import Foundation
import XCTest
@testable import LoopForge

final class KernelRunReducerTests: XCTestCase {
    private let runID = KernelRunID("run")
    private let requirementID = RequirementID("requirement")
    private let nodeID = KernelNodeID("node")
    private let attemptID = AttemptID("attempt")
    private let externalDependencyID = ExternalDependencyID("opaque-dependency")
    private let worker = ActorIdentity(
        id: ActorID("worker"),
        role: "executor",
        lineageDigest: ContentDigest("worker-lineage")
    )
    private let reviewer = ActorIdentity(
        id: ActorID("reviewer"),
        role: "reviewer",
        lineageDigest: ContentDigest("reviewer-lineage")
    )

    func testInvalidContractFailsClosedWithoutAdvancingSequence() {
        let state = KernelRunState.empty(runID: runID)
        var contract = makeContract()
        contract.verbatimObjective = "  "

        let result = RunReducer.handle(
            state: state,
            command: .createRun(contract),
            context: context("create", sequence: 0, actor: worker)
        )

        guard case .rejected(.invalidContract(let issues)) = result else {
            return XCTFail("Expected invalid contract rejection")
        }
        XCTAssertTrue(issues.contains("verbatimObjective must not be empty"))
        XCTAssertEqual(state.sequence, 0)
        XCTAssertEqual(state.phase, .uninitialized)
    }

    func testStaleSequenceAndDuplicateCommandAreRejected() throws {
        let created = try accepted(
            RunReducer.handle(
                state: .empty(runID: runID),
                command: .createRun(makeContract()),
                context: context("create", sequence: 0, actor: worker)
            )
        )

        XCTAssertEqual(
            RunReducer.handle(
                state: created,
                command: .requestStop,
                context: context("stale", sequence: 0, actor: worker)
            ),
            .rejected(.staleSequence(expected: 0, actual: 1))
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: created,
                command: .requestStop,
                context: context("create", sequence: 1, actor: worker)
            ),
            .rejected(.duplicateCommand(RunCommandID("create")))
        )
    }

    func testPlanRejectsUnknownRequirementWithExactNodeAndRequirementIdentity() throws {
        let state = try createdState()
        var node = makeNode()
        let unknownRequirementID = RequirementID("unknown")
        node.requirementIDs = [unknownRequirementID]

        let result = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [node]
            )),
            context: context("plan", sequence: state.sequence, actor: worker)
        )

        XCTAssertEqual(
            result,
            .rejected(.invalidNodeRequirementOwnership(
                nodeID: nodeID,
                unknownRequirementIDs: [unknownRequirementID]
            ))
        )
    }

    func testPlanRejectsNodeWithoutRequirementOwnership() throws {
        let state = try createdState()
        var node = makeNode()
        node.requirementIDs = []

        let result = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [node]
            )),
            context: context("plan-empty-owner", sequence: state.sequence, actor: worker)
        )

        XCTAssertEqual(
            result,
            .rejected(.invalidNodeRequirementOwnership(
                nodeID: nodeID,
                unknownRequirementIDs: []
            ))
        )
    }

    func testPlanRejectsUnownedMandatoryRequirement() throws {
        let optionalRequirementID = RequirementID("optional")
        var contract = makeContract()
        contract.requirements.append(RequirementContract(
            id: optionalRequirementID,
            statement: "Retain optional diagnostic context.",
            mandatory: false,
            evidenceRecipeIDs: []
        ))
        let state = try createdState(contract: contract)
        var node = makeNode()
        node.requirementIDs = [optionalRequirementID]

        let result = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [node]
            )),
            context: context("plan-unowned-mandatory", sequence: state.sequence, actor: worker)
        )

        XCTAssertEqual(
            result,
            .rejected(.invalidMandatoryRequirementOwnership(
                requirementID: requirementID,
                ownerNodeIDs: []
            ))
        )
    }

    func testPlanRejectsDuplicateMandatoryRequirementOwnership() throws {
        let state = try createdState()
        let first = makeNode()
        var second = makeNode()
        second.id = KernelNodeID("second")
        second.strategyFingerprint = StrategyFingerprint("second-strategy")

        let result = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [first, second]
            )),
            context: context("plan-duplicate-owner", sequence: state.sequence, actor: worker)
        )

        XCTAssertEqual(
            result,
            .rejected(.invalidMandatoryRequirementOwnership(
                requirementID: requirementID,
                ownerNodeIDs: [nodeID, KernelNodeID("second")]
            ))
        )
    }

    func testPlanOwnershipRejectionIsDeterministicAcrossRequirementOrdering() throws {
        let alphaRequirementID = RequirementID("alpha")
        let zetaRequirementID = RequirementID("zeta")
        var contract = makeContract()
        contract.requirements = [
            RequirementContract(
                id: zetaRequirementID,
                statement: "Produce the second mandatory receipt.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("zeta-recipe")]
            ),
            RequirementContract(
                id: alphaRequirementID,
                statement: "Produce the first mandatory receipt.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("alpha-recipe")]
            ),
            RequirementContract(
                id: requirementID,
                statement: "Retain optional execution context.",
                mandatory: false,
                evidenceRecipeIDs: []
            )
        ]
        let state = try createdState(contract: contract)

        let result = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [makeNode()]
            )),
            context: context("plan-deterministic-owner", sequence: state.sequence, actor: worker)
        )

        XCTAssertEqual(
            result,
            .rejected(.invalidMandatoryRequirementOwnership(
                requirementID: alphaRequirementID,
                ownerNodeIDs: []
            ))
        )
    }

    func testPlanCannotClaimAWriteScopeContainingAProtectedBaselineEntry() throws {
        let baselineID = BaselineID("protected-design")
        var contract = makeContract()
        contract.protectedBaselines = [BaselineReference(
            id: baselineID,
            artifactDigest: ContentDigest("protected-artifact"),
            environmentDigest: ContentDigest("protected-environment"),
            preservationRequired: true,
            protectedWorkspaceEntries: [ProtectedWorkspaceEntry(
                path: "Design/Baseline.json",
                contentDigest: ContentDigest("baseline-manifest"),
                scope: .exactEntry
            )]
        )]
        contract.authorityCeiling = KernelAuthorityCeiling(
            readableScopes: ["Design"],
            writableScopes: ["Design"],
            capabilityIDs: [],
            permitsExternalPublication: false
        )
        let state = try createdState(contract: contract)
        var node = makeNode()
        node.mutationScope = KernelMutationScope(
            writablePaths: ["Design"],
            maximumChangedFiles: 1,
            maximumChangedBytes: 1
        )

        let result = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [node]
            )),
            context: context("plan-protected-baseline", sequence: state.sequence, actor: worker)
        )

        XCTAssertEqual(
            result,
            .rejected(.protectedBaselineScopeViolation(
                nodeID: nodeID,
                baselineID: baselineID,
                protectedPath: "Design/Baseline.json",
                writableScope: "Design"
            ))
        )
    }

    func testContractRejectsAmbiguousOrNoncanonicalProtectedBaselineEntries() {
        var contract = makeContract()
        let shared = ProtectedWorkspaceEntry(
            path: "Design/../Baseline.json",
            contentDigest: ContentDigest("entry"),
            scope: .exactEntry
        )
        contract.protectedBaselines = [
            BaselineReference(
                id: BaselineID("first-baseline"),
                artifactDigest: ContentDigest("first-artifact"),
                environmentDigest: nil,
                preservationRequired: true,
                protectedWorkspaceEntries: [shared]
            ),
            BaselineReference(
                id: BaselineID("second-baseline"),
                artifactDigest: ContentDigest("second-artifact"),
                environmentDigest: nil,
                preservationRequired: false,
                protectedWorkspaceEntries: [shared]
            )
        ]

        let issues = contract.validationIssues()

        XCTAssertTrue(issues.contains(
            "protected workspace entries require canonical paths and digests"
        ))
        XCTAssertTrue(issues.contains(
            "protected workspace entries require baseline preservation"
        ))
        XCTAssertTrue(issues.contains(
            "protected workspace paths must have one baseline owner"
        ))
    }

    func testLegacyBaselineReferenceDecodesWithoutWorkspaceBindings() throws {
        let data = Data(#"""
        {
          "id": "legacy-baseline",
          "artifactDigest": "legacy-artifact",
          "environmentDigest": null,
          "preservationRequired": true
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(BaselineReference.self, from: data)

        XCTAssertEqual(decoded.id, BaselineID("legacy-baseline"))
        XCTAssertNil(decoded.protectedWorkspaceEntries)
    }

    func testPlanRejectsCyclesAndScopeBeyondContractCeiling() throws {
        let optionalRequirementID = RequirementID("cycle-support")
        var contract = makeContract()
        contract.requirements.append(RequirementContract(
            id: optionalRequirementID,
            statement: "Retain cycle-analysis context.",
            mandatory: false,
            evidenceRecipeIDs: []
        ))
        let state = try createdState(contract: contract)
        var first = makeNode()
        first.id = KernelNodeID("first")
        first.dependencies = [KernelNodeID("second")]
        var second = makeNode()
        second.id = KernelNodeID("second")
        second.requirementIDs = [optionalRequirementID]
        second.dependencies = [KernelNodeID("first")]

        let cycle = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [first, second]
            )),
            context: context("cycle", sequence: state.sequence, actor: worker)
        )
        XCTAssertEqual(cycle, .rejected(.invalidPlan("plan dependencies must be acyclic")))

        var writer = makeNode()
        writer.mutationScope = KernelMutationScope(
            writablePaths: ["Sources"],
            maximumChangedFiles: 1,
            maximumChangedBytes: 10
        )
        let widened = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [writer]
            )),
            context: context("widened", sequence: state.sequence, actor: worker)
        )
        XCTAssertEqual(
            widened,
            .rejected(.invalidPlan("node mutation scope exceeds the contract authority ceiling"))
        )

        var capabilityEscalation = makeNode()
        capabilityEscalation.capabilityIDs = ["external-effect"]
        let widenedCapabilities = RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [capabilityEscalation]
            )),
            context: context("widened-capabilities", sequence: state.sequence, actor: worker)
        )
        XCTAssertEqual(
            widenedCapabilities,
            .rejected(.invalidPlan("node capabilities exceed the contract authority ceiling"))
        )
    }

    func testExplicitWorkspaceRootScopeContainsCanonicalRelativePaths() throws {
        var contract = makeContract()
        contract.authorityCeiling = KernelAuthorityCeiling(
            readableScopes: ["."],
            writableScopes: ["."],
            capabilityIDs: [],
            permitsExternalPublication: false
        )
        let state = try createdState(contract: contract)
        var writer = makeNode()
        writer.mutationScope = KernelMutationScope(
            writablePaths: ["Sources/LoopForge"],
            maximumChangedFiles: 2,
            maximumChangedBytes: 1_024
        )

        let planned = try accepted(RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [writer]
            )),
            context: context("root-scope", sequence: state.sequence, actor: worker)
        ))

        XCTAssertEqual(planned.phase, .ready)
        XCTAssertEqual(
            planned.nodes[nodeID]?.contract.mutationScope.writablePaths,
            ["Sources/LoopForge"]
        )
    }

    func testBlockedExecutionCannotBeVerifiedOrApproved() throws {
        var state = try authorizedState()
        state = try startAttempt(in: state)
        state = legacyDispositionState(
            state,
            .blocked(reasonDigest: ContentDigest("blocked")),
            id: "legacy-blocked"
        )

        let receipt = verificationReceipt()
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(receipt),
                context: context("verify", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.executionNotVerifiable)
        )
        XCTAssertEqual(state.acceptedRequirementIDs, [])
        XCTAssertEqual(state.phase, .blocked)
    }

    func testReviewRequiresMatchingVerificationAndIndependentLineage() throws {
        var state = try completedAttemptState()
        let review = reviewReceipt(reviewer: reviewer)

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordReview(review),
                context: context("review-before-verify", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.verificationMissing)
        )

        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(verificationReceipt()),
            context: context("verify", sequence: state.sequence, actor: reviewer)
        ))

        let selfReview = reviewReceipt(reviewer: worker)
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordReview(selfReview),
                context: context("self-review", sequence: state.sequence, actor: worker)
            ),
            .rejected(.reviewNotIndependent)
        )

        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordReview(review),
            context: context("review", sequence: state.sequence, actor: reviewer)
        ))
        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])
        XCTAssertEqual(state.nodes[nodeID]?.status, .accepted)
    }

    func testLatestPostimageRedRevokesOnlyExactVerificationIdentity() throws {
        var contract = makeContract()
        contract.acceptancePolicy.requiresIndependentReview = false
        var state = try completedAttemptState(contract: contract)

        let firstGreen = postimageVerificationReceipt(
            suffix: "a",
            releaseSequence: 10,
            result: .accepted
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(firstGreen),
            context: context(
                "postimage-green-1",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])

        let laterRed = postimageVerificationReceipt(
            suffix: "b",
            releaseSequence: 20,
            result: .rejected
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(laterRed),
            context: context(
                "postimage-red-2",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertTrue(state.acceptedRequirementIDs.isEmpty)
        XCTAssertFalse(state.verificationIsEffective(
            firstGreen,
            requirementID: requirementID
        ))
        var matchingLegacyGreen = verificationReceipt()
        matchingLegacyGreen.sourceRevision = firstGreen.sourceRevision
        matchingLegacyGreen.environmentDigest = firstGreen.environmentDigest
        matchingLegacyGreen.oracleDigest = firstGreen.oracleDigest
        XCTAssertFalse(state.verificationIsEffective(
            matchingLegacyGreen,
            requirementID: requirementID
        ))

        let otherOracleRed = postimageVerificationReceipt(
            suffix: "c",
            releaseSequence: 40,
            result: .rejected,
            oracleDigest: ContentDigest(String(repeating: "d", count: 64))
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(otherOracleRed),
            context: context(
                "postimage-other-oracle-red",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertTrue(state.acceptedRequirementIDs.isEmpty)

        let newestGreen = postimageVerificationReceipt(
            suffix: "d",
            releaseSequence: 30,
            result: .accepted
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(newestGreen),
            context: context(
                "postimage-green-3",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])
        XCTAssertTrue(state.verificationIsEffective(
            newestGreen,
            requirementID: requirementID
        ))
    }

    func testPostimageReviewMustRebindAfterRedAndNewerGreen() throws {
        var state = try completedAttemptState()
        let firstGreen = postimageVerificationReceipt(
            suffix: "a",
            releaseSequence: 10,
            result: .accepted
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(firstGreen),
            context: context(
                "review-rebind-green-1",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        var firstReview = reviewReceipt(reviewer: reviewer)
        firstReview.sourceRevision = firstGreen.sourceRevision
        firstReview.verificationEvidenceSetDigest = try XCTUnwrap(
            firstGreen.postimageEvidenceBatch?.evidenceSetDigest
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordReview(firstReview),
            context: context(
                "review-rebind-review-1",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])
        XCTAssertEqual(state.nodes[nodeID]?.status, .accepted)

        let red = postimageVerificationReceipt(
            suffix: "b",
            releaseSequence: 20,
            result: .rejected
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(red),
            context: context(
                "review-rebind-red-2",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertTrue(state.acceptedRequirementIDs.isEmpty)
        XCTAssertEqual(state.nodes[nodeID]?.status, .awaitingVerification)

        let newestGreen = postimageVerificationReceipt(
            suffix: "c",
            releaseSequence: 30,
            result: .accepted
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(newestGreen),
            context: context(
                "review-rebind-green-3",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertTrue(state.acceptedRequirementIDs.isEmpty)

        var reboundReview = reviewReceipt(reviewer: reviewer)
        reboundReview.id = ReceiptID("review-rebound")
        reboundReview.sourceRevision = newestGreen.sourceRevision
        reboundReview.verificationEvidenceSetDigest = try XCTUnwrap(
            newestGreen.postimageEvidenceBatch?.evidenceSetDigest
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordReview(reboundReview),
            context: context(
                "review-rebind-review-3",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertEqual(state.acceptedRequirementIDs, [requirementID])
        XCTAssertEqual(state.nodes[nodeID]?.status, .accepted)
    }

    func testLaterEffectiveRedRequiresRollbackForRelyingIntegration() throws {
        var contract = makeContract()
        contract.acceptancePolicy.requiresIndependentReview = false
        var state = try completedAttemptState(contract: contract)
        let firstGreen = postimageVerificationReceipt(
            suffix: "a",
            releaseSequence: 10,
            result: .accepted
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(firstGreen),
            context: context(
                "integration-revocation-green",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        let transactionID = IntegrationTransactionID(
            "integration-revocation"
        )
        state.integrationTransactions[transactionID] =
            IntegrationTransactionState(
                proposal: IntegrationProposal(
                    runID: state.runID,
                    transactionID: transactionID,
                    candidateID: MutationCandidateID("candidate"),
                    attemptID: attemptID,
                    nodeID: nodeID,
                    contractDigest: ContentDigest("contract"),
                    planNodeDigest: ContentDigest("plan"),
                    manifestDigest: ContentDigest("manifest"),
                    canonicalPreimageDigest: ContentDigest("preimage"),
                    expectedPostimageDigest: firstGreen.sourceRevision,
                    proposedAt: Date(timeIntervalSince1970: 1)
                ),
                phase: .independentlyAccepted,
                preflightReceipt: nil,
                rollbackManifest: nil,
                applyIntent: nil,
                applyReceipt: nil,
                postimageVerificationReceipt:
                    IntegrationPostimageVerificationReceipt(
                        id: ReceiptID("integration-verification"),
                        transactionID: transactionID,
                        applyReceiptID: ReceiptID("apply"),
                        canonicalPostimageDigest:
                            firstGreen.sourceRevision,
                        evidenceSetDigest: try XCTUnwrap(
                            firstGreen.postimageEvidenceBatch?
                                .evidenceSetDigest
                        ),
                        processQuiescenceReceiptID:
                            ReceiptID("release"),
                        verifier: reviewer,
                        verifiedAt: Date(timeIntervalSince1970: 2),
                        result: .accepted,
                        sourceVerificationReceiptID: firstGreen.id
                    ),
                acceptanceReceipt: nil,
                rollbackIntent: nil,
                rollbackReceipt: nil
            )

        let laterRed = postimageVerificationReceipt(
            suffix: "b",
            releaseSequence: 20,
            result: .rejected
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(laterRed),
            context: context(
                "integration-revocation-red",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        XCTAssertEqual(
            state.integrationTransactions[transactionID]?.phase,
            .rollbackRequired
        )
        XCTAssertFalse(
            state.integrationTransactions[transactionID]?
                .permitsPublication ?? true
        )
    }

    func testSubstitutionConstraintMustBindKnownRequirementsAndExactIdentities() {
        var missingRule = makeContract()
        missingRule.constraints = [ConstraintContract(
            id: "surface",
            kind: .prohibitSubstitution,
            statement: "Use the contracted interaction surface."
        )]
        XCTAssertTrue(missingRule.validationIssues().contains(
            "prohibitSubstitution constraint surface requires a typed rule"
        ))

        var unknownRequirement = makeContract()
        unknownRequirement.constraints = [ConstraintContract(
            id: "surface",
            kind: .prohibitSubstitution,
            statement: "Use the contracted interaction surface.",
            substitutionRule: ExactImplementationConstraint(
                requirementIDs: [RequirementID("unknown")],
                permittedImplementationIDs: ["opaque-surface-a"]
            )
        )]
        XCTAssertTrue(unknownRequirement.validationIssues().contains(
            "substitution constraint surface must bind known requirement IDs"
        ))

        var emptyIdentity = makeContract()
        emptyIdentity.constraints = [ConstraintContract(
            id: "surface",
            kind: .prohibitSubstitution,
            statement: "Use the contracted interaction surface.",
            substitutionRule: ExactImplementationConstraint(
                requirementIDs: [requirementID],
                permittedImplementationIDs: ["  "]
            )
        )]
        XCTAssertTrue(emptyIdentity.validationIssues().contains(
            "substitution constraint surface requires exact implementation IDs"
        ))
    }

    func testLegacyConstraintAndVerificationReceiptDecodeWithoutBindingFields() throws {
        let legacyContract = makeContract()
        let contractData = try JSONEncoder().encode(legacyContract)
        let contractObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: contractData) as? [String: Any]
        )
        XCTAssertNil(contractObject["externalDependencies"])
        let decodedContract = try JSONDecoder().decode(TaskContract.self, from: contractData)
        XCTAssertNil(decodedContract.externalDependencies)

        let legacyRequirement = RequirementContract(
            id: requirementID,
            statement: "Keep the declared outcome.",
            mandatory: true,
            evidenceRecipeIDs: [EvidenceRecipeID("recipe")]
        )
        let requirementData = try JSONEncoder().encode(legacyRequirement)
        let requirementObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: requirementData) as? [String: Any]
        )
        XCTAssertNil(requirementObject["deliverableCardinality"])
        let requirement = try JSONDecoder().decode(
            RequirementContract.self,
            from: requirementData
        )
        XCTAssertNil(requirement.deliverableCardinality)

        let legacyConstraint = ConstraintContract(
            id: "legacy",
            kind: .preserve,
            statement: "Keep it."
        )
        let constraintData = try JSONEncoder().encode(legacyConstraint)
        let constraintObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: constraintData) as? [String: Any]
        )
        XCTAssertNil(constraintObject["substitutionRule"])
        let constraint = try JSONDecoder().decode(
            ConstraintContract.self,
            from: constraintData
        )
        XCTAssertNil(constraint.substitutionRule)

        let legacyReceipt = VerificationReceipt(
            id: ReceiptID("legacy-receipt"),
            attemptID: attemptID,
            requirementIDs: [requirementID],
            sourceRevision: ContentDigest("revision"),
            environmentDigest: ContentDigest("environment"),
            oracleDigest: ContentDigest("oracle"),
            result: .accepted
        )
        let receiptData = try JSONEncoder().encode(legacyReceipt)
        let receiptObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: receiptData) as? [String: Any]
        )
        XCTAssertNil(receiptObject["implementationObservations"])
        XCTAssertNil(receiptObject["deliverableObservations"])
        let receipt = try JSONDecoder().decode(
            VerificationReceipt.self,
            from: receiptData
        )
        XCTAssertNil(receipt.implementationObservations)
        XCTAssertNil(receipt.deliverableObservations)
    }

    func testExternalDependencyContractRequiresKnownRequirementsAndObserverAuthority() {
        var contract = makeContract()
        contract.externalDependencies = [ExternalDependencyContract(
            id: externalDependencyID,
            kind: .authority,
            requirementIDs: [RequirementID("unknown")],
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID(""),
            authorizedObserverLineageDigests: []
        )]

        XCTAssertTrue(contract.validationIssues().contains(
            "external dependencies require known requirements, evidence recipes, and authorized observer lineages"
        ))
    }

    func testLegacyCallerSelectedExecutionIsRetiredAndStateIsUnchanged() throws {
        let state = try startAttempt(in: authorizedState())
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .recordExecution(attemptID: attemptID, disposition: .completed),
                context: context("legacy-direct-execution", sequence: state.sequence, actor: worker)
            ),
            .rejected(.legacyExecutionAuthorityRetired)
        )
        XCTAssertNil(state.attempts[attemptID]?.disposition)
        XCTAssertEqual(state.activeAttemptID, attemptID)
    }

    func testReceiptProvenStopInterruptsActiveAttemptAndReplaysToStopped() throws {
        var state = try startAttempt(in: authorizedState())
        state = try accepted(RunReducer.handle(
            state: state,
            command: .requestStop,
            context: context("active-stop", sequence: state.sequence, actor: worker)
        ))
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordRuntimeDrain(RuntimeDrainReceipt(
                id: ReceiptID("active-stop-drain"),
                runID: runID,
                snapshot: RuntimeDrainSnapshot(
                    intent: .stop,
                    liveResourceIDs: [],
                    cancelledQueuedLeaseIDs: []
                ),
                observedAt: Date(timeIntervalSince1970: 901),
                observedAtMonotonicNanoseconds: 901
            )),
            context: context(
                "active-stop-drain",
                sequence: state.sequence,
                actor: worker
            )
        ))
        let beforeQuiescence = state
        let decision = RunReducer.handle(
            state: state,
            command: .testOnlyRecordQuiescence(QuiescenceReceipt(
                id: ReceiptID("active-stop-quiescence"),
                runID: runID,
                intent: .stop,
                observedAt: Date(timeIntervalSince1970: 902),
                observedAtMonotonicNanoseconds: 902,
                liveResources: [],
                failedReleases: [],
                queuedLeaseIDs: []
            )),
            context: context(
                "active-stop-quiescence",
                sequence: state.sequence,
                actor: worker
            )
        )
        guard case .accepted(let events, let stopped) = decision else {
            return XCTFail("physical quiescence must close the active attempt")
        }
        XCTAssertEqual(stopped.phase, .stopped)
        XCTAssertNil(stopped.activeAttemptID)
        XCTAssertEqual(
            stopped.attempts[attemptID]?.disposition,
            .interrupted
        )
        XCTAssertEqual(stopped.nodes[nodeID]?.status, .authorized)
        let decoded = try JSONDecoder().decode(
            [OrchestrationEvent].self,
            from: JSONEncoder().encode(events)
        )
        XCTAssertEqual(
            decoded.reduce(beforeQuiescence) {
                RunReducer.reduce(state: $0, event: $1)
            },
            stopped
        )
    }

    func testUnboundQuiescenceEventCannotInterruptActiveAttemptOnReplay() throws {
        let state = try startAttempt(in: authorizedState())
        let event = OrchestrationEvent(
            id: OrchestrationEventID("unbound-quiescence-event"),
            runID: runID,
            sequence: state.sequence + 1,
            commandID: RunCommandID("unbound-quiescence-command"),
            occurredAt: Date(timeIntervalSince1970: 903),
            payload: .quiescenceRecorded(QuiescenceReceipt(
                id: ReceiptID("unbound-quiescence"),
                runID: runID,
                intent: .stop,
                observedAt: Date(timeIntervalSince1970: 903),
                observedAtMonotonicNanoseconds: 903,
                liveResources: [],
                failedReleases: [],
                queuedLeaseIDs: []
            ))
        )

        XCTAssertEqual(RunReducer.reduce(state: state, event: event), state)
    }

    func testWorkerDispositionIsDerivedExactlyFromJournaledParseReceipt() throws {
        let cases: [(KernelWorkerProposedDisposition, KernelExecutionDisposition)] = [
            (.completed, .completed),
            (.continuationNeeded, .continuationNeeded),
            (.blocked, .blocked(reasonDigest: ContentDigest("result"))),
            (.failed, .failed(reasonDigest: ContentDigest("result"))),
            (.interrupted, .interrupted),
            (.malformed, .malformed(reasonDigest: ContentDigest("result")))
        ]
        for (index, entry) in cases.enumerated() {
            var state = try startAttempt(in: authorizedState())
            let parseID = ReceiptID("parse-\(index)")
            var parses = state.workerResultParseReceipts ?? [:]
            parses[parseID] = workerParseReceipt(
                id: parseID,
                disposition: entry.0
            )
            state.workerResultParseReceipts = parses
            let derivationID = ReceiptID("derivation-\(index)")
            let decision = RunReducer.handle(
                state: state,
                command: .deriveExecution(
                    receiptID: derivationID,
                    source: .workerResultParse(parseID)
                ),
                context: context("derive-\(index)", sequence: state.sequence, actor: reviewer)
            )
            guard case .accepted(let events, let derived) = decision else {
                return XCTFail("Expected parser-bound derivation for case \(index)")
            }
            XCTAssertEqual(derived.attempts[attemptID]?.disposition, entry.1)
            XCTAssertEqual(
                derived.executionDerivationReceipts?[derivationID]?.source,
                .workerResultParse(parseID)
            )
            let decoded = try JSONDecoder().decode(
                [OrchestrationEvent].self,
                from: JSONEncoder().encode(events)
            )
            XCTAssertEqual(
                decoded.reduce(state) { RunReducer.reduce(state: $0, event: $1) },
                derived
            )
        }
    }

    func testMissingParserReceiptCannotDeriveExecution() throws {
        let state = try startAttempt(in: authorizedState())
        let derivationID = ReceiptID("missing-parser-derivation")
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .deriveExecution(
                    receiptID: derivationID,
                    source: .workerResultParse(ReceiptID("missing-parser"))
                ),
                context: context("derive-missing", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.executionDerivationRejected(derivationID))
        )
    }

    func testTamperedDerivedExecutionEventCannotAdvanceReplay() throws {
        var state = try startAttempt(in: authorizedState())
        let parseID = ReceiptID("tampered-replay-parse")
        var parses = state.workerResultParseReceipts ?? [:]
        parses[parseID] = workerParseReceipt(id: parseID, disposition: .completed)
        state.workerResultParseReceipts = parses
        let occurredAt = Date(timeIntervalSince1970: 900)
        let event = OrchestrationEvent(
            id: OrchestrationEventID("tampered-derived-event"),
            runID: runID,
            sequence: state.sequence + 1,
            commandID: RunCommandID("tampered-derived-command"),
            occurredAt: occurredAt,
            payload: .executionDerived(KernelExecutionDerivationReceipt(
                id: ReceiptID("tampered-derived-receipt"),
                runID: runID,
                attemptID: attemptID,
                source: .workerResultParse(parseID),
                sourceEvidenceDigest: ContentDigest("result"),
                disposition: .failed(reasonDigest: ContentDigest("attacker-selected")),
                derivedAt: occurredAt
            ))
        )
        XCTAssertEqual(RunReducer.reduce(state: state, event: event), state)
    }

    func testInventedExternalDependencyCannotCreateAcceptedBlockerReceipt() throws {
        let state = try startAttempt(in: authorizedState())
        let receipt = externalDependencyReceipt(observer: reviewer)

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordExternalDependencyObservation(receipt),
                context: context("invented-dependency", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.externalDependencyObservationRejected(
                .unknownDependency(externalDependencyID)
            ))
        )
        XCTAssertTrue((state.externalDependencyReceipts ?? [:]).isEmpty)

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .deriveExecution(
                    receiptID: ReceiptID("invented-derivation"),
                    source: .externalDependencyObservation(receipt.id)
                ),
                context: context("invented-blocker", sequence: state.sequence, actor: worker)
            ),
            .rejected(.executionDerivationRejected(ReceiptID("invented-derivation")))
        )
    }

    func testExternalDependencyObservationRequiresIndependentAuthorizedLineageAndRecipe() throws {
        let state = try startAttempt(in: authorizedState(
            contract: contractWithExternalDependency()
        ))

        let selfObserved = externalDependencyReceipt(observer: worker)
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordExternalDependencyObservation(selfObserved),
                context: context("self-observed", sequence: state.sequence, actor: worker)
            ),
            .rejected(.externalDependencyObservationRejected(
                .unauthorizedObserver(externalDependencyID)
            ))
        )

        var invalidDigest = externalDependencyReceipt(observer: reviewer)
        invalidDigest.evidenceDigest = ContentDigest("not-a-sha256")
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordExternalDependencyObservation(
                    invalidDigest
                ),
                context: context(
                    "invalid-dependency-digest",
                    sequence: state.sequence,
                    actor: reviewer
                )
            ),
            .rejected(.externalDependencyObservationRejected(
                .invalidEvidence(externalDependencyID)
            ))
        )

        var wrongRecipe = externalDependencyReceipt(observer: reviewer)
        wrongRecipe.id = ReceiptID("wrong-recipe")
        wrongRecipe.evidenceRecipeID = ExternalDependencyEvidenceRecipeID("substitute-probe")
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordExternalDependencyObservation(wrongRecipe),
                context: context("wrong-recipe", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.externalDependencyObservationRejected(
                .mismatchedEvidenceRecipe(externalDependencyID)
            ))
        )
    }

    func testTypedUnavailableDependencyReceiptIsJournaledBeforeBlockingExecution() throws {
        var state = try startAttempt(in: authorizedState(
            contract: contractWithExternalDependency()
        ))
        var receipt = externalDependencyReceipt(observer: reviewer)
        let observedAt = Date(timeIntervalSince1970: TimeInterval(state.sequence + 1))
        receipt.observedAt = observedAt

        let observationDecision = RunReducer.handle(
            state: state,
            command: .testOnlyRecordExternalDependencyObservation(receipt),
            context: context("observe-dependency", sequence: state.sequence, actor: reviewer)
        )
        guard case .accepted(let events, let observed) = observationDecision else {
            return XCTFail("Expected dependency observation acceptance")
        }
        let encoded = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([OrchestrationEvent].self, from: encoded)
        var replayed = state
        for event in decoded {
            replayed = RunReducer.reduce(state: replayed, event: event)
        }
        XCTAssertEqual(replayed, observed)
        XCTAssertEqual(replayed.externalDependencyReceipts?[receipt.id], receipt)
        state = replayed

        state = try accepted(RunReducer.handle(
            state: state,
            command: .deriveExecution(
                receiptID: ReceiptID("external-block-derivation"),
                source: .externalDependencyObservation(receipt.id)
            ),
            context: context("record-external-block", sequence: state.sequence, actor: worker)
        ))
        XCTAssertEqual(state.phase, .blocked)
        XCTAssertEqual(state.nodes[nodeID]?.status, .blocked)
        XCTAssertEqual(
            state.attempts[attemptID]?.disposition,
            .externalDependencyUnavailable(
                receiptID: receipt.id,
                reasonDigest: receipt.evidenceDigest
            )
        )
        XCTAssertEqual(
            state.executionDerivationReceipts?[ReceiptID("external-block-derivation")]?.source,
            .externalDependencyObservation(receipt.id)
        )
    }

    func testAvailableDependencyReceiptCannotBackUnavailableDisposition() throws {
        var state = try startAttempt(in: authorizedState(
            contract: contractWithExternalDependency()
        ))
        var receipt = externalDependencyReceipt(observer: reviewer)
        receipt.availability = .available
        receipt.observedAt = Date(timeIntervalSince1970: TimeInterval(state.sequence + 1))
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordExternalDependencyObservation(receipt),
            context: context("observe-available", sequence: state.sequence, actor: reviewer)
        ))

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .deriveExecution(
                    receiptID: ReceiptID("available-derivation"),
                    source: .externalDependencyObservation(receipt.id)
                ),
                context: context("misuse-available", sequence: state.sequence, actor: worker)
            ),
            .rejected(.executionDerivationRejected(ReceiptID("available-derivation")))
        )
    }

    func testTamperedExternalDependencyObservationCannotAdvanceReplay() throws {
        let state = try startAttempt(in: authorizedState(
            contract: contractWithExternalDependency()
        ))
        var tampered = externalDependencyReceipt(observer: worker)
        tampered.observedAt = Date(
            timeIntervalSince1970: TimeInterval(state.sequence + 1)
        )
        let event = OrchestrationEvent(
            id: OrchestrationEventID("tampered-dependency-event"),
            runID: runID,
            sequence: state.sequence + 1,
            commandID: RunCommandID("tampered-dependency-command"),
            occurredAt: tampered.observedAt,
            payload: .externalDependencyObservationRecorded(tampered)
        )

        XCTAssertEqual(RunReducer.reduce(state: state, event: event), state)
    }

    func testDuplicateExternalDependencyReceiptCannotOverwriteReplay() throws {
        var state = try startAttempt(in: authorizedState(
            contract: contractWithExternalDependency()
        ))
        var acceptedReceipt = externalDependencyReceipt(observer: reviewer)
        acceptedReceipt.observedAt = Date(
            timeIntervalSince1970: TimeInterval(state.sequence + 1)
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordExternalDependencyObservation(
                acceptedReceipt
            ),
            context: context(
                "accepted-dependency",
                sequence: state.sequence,
                actor: reviewer
            )
        ))
        var overwrite = acceptedReceipt
        overwrite.availability = .available
        overwrite.observedAt = Date(
            timeIntervalSince1970: TimeInterval(state.sequence + 1)
        )
        let event = OrchestrationEvent(
            id: OrchestrationEventID("overwrite-dependency-event"),
            runID: runID,
            sequence: state.sequence + 1,
            commandID: RunCommandID("overwrite-dependency-command"),
            occurredAt: overwrite.observedAt,
            payload: .externalDependencyObservationRecorded(overwrite)
        )

        XCTAssertEqual(RunReducer.reduce(state: state, event: event), state)
    }

    func testDeliverableCardinalityContractRejectsMalformedDeclaration() {
        var contract = makeContract()
        contract.requirements[0].deliverableCardinality = DeliverableCardinalityConstraint(
            collectionID: " set-with-whitespace ",
            exactCount: 0
        )

        XCTAssertTrue(contract.validationIssues().contains(
            "deliverable cardinality requires an exact collection ID and positive count"
        ))
    }

    func testAcceptedVerificationRequiresExactDomainNeutralDeliverableSet() throws {
        var contract = makeContract()
        contract.requirements[0].deliverableCardinality = DeliverableCardinalityConstraint(
            collectionID: "opaque-collection-17",
            exactCount: 10
        )
        var state = try completedAttemptState(contract: contract)

        var missing = verificationReceipt()
        missing.id = ReceiptID("cardinality-missing")
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(missing),
                context: context("cardinality-missing", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.deliverableCardinalityViolated(.missingObservation(requirementID)))
        )

        var tooFew = verificationReceipt()
        tooFew.id = ReceiptID("cardinality-too-few")
        tooFew.deliverableObservations = [DeliverableCardinalityObservation(
            requirementID: requirementID,
            collectionID: "opaque-collection-17",
            members: deliverableMembers(count: 9),
            evidenceDigest: ContentDigest("membership-evidence")
        )]
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(tooFew),
                context: context("cardinality-too-few", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.deliverableCardinalityViolated(.countMismatch(
                requirementID: requirementID,
                expected: 10,
                actual: 9
            )))
        )

        var tooMany = tooFew
        tooMany.id = ReceiptID("cardinality-too-many")
        tooMany.deliverableObservations = [DeliverableCardinalityObservation(
            requirementID: requirementID,
            collectionID: "opaque-collection-17",
            members: deliverableMembers(count: 11),
            evidenceDigest: ContentDigest("membership-evidence")
        )]
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(tooMany),
                context: context("cardinality-too-many", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.deliverableCardinalityViolated(.countMismatch(
                requirementID: requirementID,
                expected: 10,
                actual: 11
            )))
        )

        var wrongCollection = tooFew
        wrongCollection.id = ReceiptID("cardinality-wrong-collection")
        wrongCollection.deliverableObservations = [DeliverableCardinalityObservation(
            requirementID: requirementID,
            collectionID: "substitute-collection",
            members: [],
            evidenceDigest: ContentDigest("membership-evidence")
        )]
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(wrongCollection),
                context: context(
                    "cardinality-wrong-collection",
                    sequence: state.sequence,
                    actor: reviewer
                )
            ),
            .rejected(.deliverableCardinalityViolated(.collectionMismatch(
                requirementID: requirementID,
                expected: "opaque-collection-17",
                actual: "substitute-collection"
            )))
        )

        var duplicateIdentity = tooFew
        duplicateIdentity.id = ReceiptID("cardinality-duplicate-identity")
        duplicateIdentity.deliverableObservations = [DeliverableCardinalityObservation(
            requirementID: requirementID,
            collectionID: "opaque-collection-17",
            members: [
                DeliverableMemberObservation(
                    stableID: "member-a",
                    contentDigest: ContentDigest("version-a")
                ),
                DeliverableMemberObservation(
                    stableID: "member-a",
                    contentDigest: ContentDigest("version-b")
                )
            ],
            evidenceDigest: ContentDigest("membership-evidence")
        )]
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(duplicateIdentity),
                context: context(
                    "cardinality-duplicate-identity",
                    sequence: state.sequence,
                    actor: reviewer
                )
            ),
            .rejected(.deliverableCardinalityViolated(.duplicateMemberIdentity(
                requirementID: requirementID,
                stableID: "member-a"
            )))
        )

        var exact = verificationReceipt()
        exact.id = ReceiptID("cardinality-exact")
        exact.deliverableObservations = [DeliverableCardinalityObservation(
            requirementID: requirementID,
            collectionID: "opaque-collection-17",
            members: deliverableMembers(count: 10, contentDigest: "same-content"),
            evidenceDigest: ContentDigest("membership-evidence")
        )]
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(exact),
            context: context("cardinality-exact", sequence: state.sequence, actor: reviewer)
        ))
        XCTAssertEqual(state.verificationReceipts[exact.id], exact)
    }

    func testAcceptedVerificationRejectsForbiddenSubstitutionIndependentOfNames() throws {
        let fixtures = [
            ("surface-alpha", "adapter-alpha", "adapter-beta"),
            ("channel-17", "implementation-42", "implementation-91")
        ]
        for (constraintID, permitted, substituted) in fixtures {
            var contract = makeContract()
            contract.constraints = [ConstraintContract(
                id: constraintID,
                kind: .prohibitSubstitution,
                statement: "Preserve the exact contracted implementation.",
                substitutionRule: ExactImplementationConstraint(
                    requirementIDs: [requirementID],
                    permittedImplementationIDs: [permitted]
                )
            )]
            let state = try completedAttemptState(contract: contract)
            var receipt = verificationReceipt()
            receipt.id = ReceiptID("substituted-\(constraintID)")
            receipt.implementationObservations = [ExactImplementationObservation(
                constraintID: constraintID,
                implementationID: substituted,
                evidenceDigest: ContentDigest("binding-evidence")
            )]

            let result = RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(receipt),
                context: context("reject-\(constraintID)", sequence: state.sequence, actor: reviewer)
            )
            XCTAssertEqual(
                result,
                .rejected(.substitutionConstraintViolated(
                    "constraint \(constraintID) rejected implementation identity \(substituted)"
                ))
            )
            XCTAssertTrue(state.verificationReceipts.isEmpty)
        }
    }

    func testAcceptedVerificationRequiresAndAcceptsExactImplementationObservation() throws {
        var contract = makeContract()
        contract.constraints = [ConstraintContract(
            id: "surface-binding",
            kind: .prohibitSubstitution,
            statement: "Preserve the exact contracted implementation.",
            substitutionRule: ExactImplementationConstraint(
                requirementIDs: [requirementID],
                permittedImplementationIDs: ["opaque-implementation"]
            )
        )]
        var state = try completedAttemptState(contract: contract)
        var missing = verificationReceipt()
        missing.id = ReceiptID("missing-binding")
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordVerification(missing),
                context: context("missing-binding", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.substitutionConstraintViolated(
                "implementation observations do not exactly match bound constraints; missing=[\"surface-binding\"]; unexpected=[]"
            ))
        )

        var exact = verificationReceipt()
        exact.id = ReceiptID("exact-binding")
        exact.implementationObservations = [ExactImplementationObservation(
            constraintID: "surface-binding",
            implementationID: "opaque-implementation",
            evidenceDigest: ContentDigest("binding-evidence")
        )]
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(exact),
            context: context("exact-binding", sequence: state.sequence, actor: reviewer)
        ))
        XCTAssertEqual(state.verificationReceipts[exact.id], exact)
    }

    func testRetiredStrategyCannotStartUnderNewAttemptID() throws {
        var state = try authorizedState()
        state = try accepted(RunReducer.handle(
            state: state,
            command: .retireStrategy(
                causalStrategy().fingerprint,
                lessonDigest: ContentDigest("lesson")
            ),
            context: context("retire", sequence: state.sequence, actor: reviewer)
        ))

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .startAttempt(
                    attemptID: AttemptID("renamed-attempt"),
                    nodeID: nodeID,
                    requirementIDs: [requirementID],
                    strategyFingerprint: causalStrategy().fingerprint
                ),
                context: context("restart", sequence: state.sequence, actor: worker)
            ),
            .rejected(.strategyRetired(causalStrategy().fingerprint))
        )
    }

    func testAttemptCannotStartWithoutExactCausalAdmission() throws {
        let state = try authorizedState()

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .startAttempt(
                    attemptID: attemptID,
                    nodeID: nodeID,
                    requirementIDs: [requirementID],
                    strategyFingerprint: causalStrategy().fingerprint
                ),
                context: context("bypass-causal-admission", sequence: state.sequence, actor: worker)
            ),
            .rejected(.invalidConvergenceTransition(
                "attempt start requires an exact accepted causal admission"
            ))
        )
    }

    func testStopIsNotTerminalUntilQuiescenceIsProven() throws {
        var state = try createdState()
        state = try accepted(RunReducer.handle(
            state: state,
            command: .requestStop,
            context: context("stop", sequence: state.sequence, actor: worker)
        ))
        XCTAssertEqual(state.phase, .stopRequested)
        state = try recordedDrain(state, intent: .stop, id: "stop-drain")

        let nonquiescent = QuiescenceReceipt(
            id: ReceiptID("not-quiet"),
            runID: runID,
            intent: .stop,
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2,
            liveResources: [OwnedResourceID("process")],
            failedReleases: [],
            queuedLeaseIDs: []
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordQuiescence(nonquiescent),
                context: context("not-quiet", sequence: state.sequence, actor: worker)
            ),
            .rejected(.quiescenceNotProven)
        )
        XCTAssertEqual(state.phase, .stopRequested)

        let quiet = QuiescenceReceipt(
            id: ReceiptID("quiet"),
            runID: runID,
            intent: .stop,
            observedAt: Date(timeIntervalSince1970: 3),
            observedAtMonotonicNanoseconds: 3,
            liveResources: [],
            failedReleases: [],
            queuedLeaseIDs: []
        )
        let decision = RunReducer.handle(
            state: state,
            command: .testOnlyRecordQuiescence(quiet),
            context: context("quiet", sequence: state.sequence, actor: worker)
        )
        guard case .accepted(let events, let stopped) = decision else {
            return XCTFail("Expected accepted quiescence")
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(stopped.phase, .stopped)
        XCTAssertTrue(KernelRunProjection(state: stopped).quiescent)
    }

    func testQuiescenceCannotBeRecordedWhileAttemptIsStillActive() throws {
        var state = try startAttempt(in: authorizedState())
        state = try accepted(RunReducer.handle(
            state: state,
            command: .requestStop,
            context: context("stop-active", sequence: state.sequence, actor: worker)
        ))
        state = try recordedDrain(state, intent: .stop, id: "active-drain")
        let apparentlyQuiet = QuiescenceReceipt(
            id: ReceiptID("quiet-but-active"),
            runID: runID,
            intent: .stop,
            observedAt: Date(timeIntervalSince1970: 5),
            observedAtMonotonicNanoseconds: 5,
            liveResources: [],
            failedReleases: [],
            queuedLeaseIDs: []
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordQuiescence(apparentlyQuiet),
                context: context("quiet-active", sequence: state.sequence, actor: worker)
            ),
            .rejected(.quiescenceNotProven)
        )
        XCTAssertEqual(state.phase, .stopRequested)
        XCTAssertEqual(state.activeAttemptID, attemptID)
    }

    func testCompletionRequiresRequirementClosureAndQuiescence() throws {
        var state = try reviewedState()
        state = try accepted(RunReducer.handle(
            state: state,
            command: .requestCompletion,
            context: context("request-completion", sequence: state.sequence, actor: reviewer)
        ))
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyAuthorizeCompletion(
                    runID: runID,
                    sourceSequence: state.sequence,
                    authorizer: reviewer
                ),
                context: context("complete-too-soon", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.quiescenceNotProven)
        )
        state = try recordedDrain(state, intent: .complete, id: "completion-drain")

        let quiet = QuiescenceReceipt(
            id: ReceiptID("completion-quiet"),
            runID: runID,
            intent: .complete,
            observedAt: Date(timeIntervalSince1970: TimeInterval(state.sequence + 1)),
            observedAtMonotonicNanoseconds: state.sequence + 1,
            liveResources: [],
            failedReleases: [],
            queuedLeaseIDs: []
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordQuiescence(quiet),
            context: context("record-quiet", sequence: state.sequence, actor: reviewer)
        ))
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyAuthorizeCompletion(
                runID: runID,
                sourceSequence: state.sequence,
                authorizer: reviewer
            ),
            context: context("complete", sequence: state.sequence, actor: reviewer)
        ))

        XCTAssertEqual(state.phase, .completed)
        let projection = KernelRunProjection(state: state)
        XCTAssertEqual(projection.acceptedRequirementCount, 1)
        XCTAssertEqual(projection.mandatoryRequirementCount, 1)
    }

    func testCompletionDurationUsesOnlyJournalBoundAcceptedProgress() throws {
        var contract = makeContract()
        contract.acceptancePolicy.duration = DurationAcceptancePolicy(
            requiredSeconds: 5,
            eligibleClass: .acceptedExecution
        )
        var state = try reviewedState(contract: contract)

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .requestCompletion,
                context: context("duration-too-soon", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.durationIncomplete(requiredSeconds: 5, acceptedSeconds: 0))
        )

        var forged = OccurrenceReceipt(
            id: ReceiptID("forged-occurrence-receipt"),
            occurrenceID: OccurrenceID("forged-occurrence"),
            invocation: .manual(ownerCommandID: RunCommandID("owner")),
            clock: ClockReceipt(
                bootSessionID: BootSessionID("boot"),
                monotonicStartNanoseconds: 0,
                monotonicEndNanoseconds: 5_000_000_000,
                wallStart: Date(timeIntervalSince1970: 0),
                wallEnd: Date(timeIntervalSince1970: 5),
                discontinuities: []
            ),
            outcome: .succeeded,
            intervalDisposition: .acceptedInteractive,
            evidenceReceiptIDs: [ReceiptID("verification")],
            progressReceiptID: ReceiptID("not-a-journal-transaction")
        )
        state.processedCommandIDs.insert(RunCommandID("not-a-journal-transaction"))
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordOccurrence(forged),
                context: context("record-forged-occurrence", sequence: state.sequence, actor: worker)
            ),
            .rejected(.invalidOccurrenceReceipt(
                "progress binding must reference a causal progress journal transaction"
            ))
        )

        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordOccurrence(OccurrenceReceipt(
                id: ReceiptID("stagnant-occurrence-receipt"),
                occurrenceID: OccurrenceID("stagnant-occurrence"),
                invocation: .manual(ownerCommandID: RunCommandID("owner")),
                clock: ClockReceipt(
                    bootSessionID: BootSessionID("boot"),
                    monotonicStartNanoseconds: 0,
                    monotonicEndNanoseconds: 5_000_000_000,
                    wallStart: Date(timeIntervalSince1970: 0),
                    wallEnd: Date(timeIntervalSince1970: 5),
                    discontinuities: []
                ),
                outcome: .succeeded,
                intervalDisposition: .acceptedInteractive,
                evidenceReceiptIDs: [ReceiptID("verification")],
                progressReceiptID: nil
            )),
            context: context("record-stagnant-occurrence", sequence: state.sequence, actor: worker)
        ))
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .requestCompletion,
                context: context("duration-still-stagnant", sequence: state.sequence, actor: reviewer)
            ),
            .rejected(.durationIncomplete(requiredSeconds: 5, acceptedSeconds: 0))
        )

        state.processedCommandIDs.insert(RunCommandID("accepted-progress"))
        state.acceptedProgressCommandIDs = [RunCommandID("accepted-progress")]
        state.causalProgressCommandIDs = [RunCommandID("accepted-progress")]
        forged.id = ReceiptID("accepted-occurrence-receipt")
        forged.occurrenceID = OccurrenceID("accepted-occurrence")
        forged.clock.monotonicStartNanoseconds = 5_000_000_000
        forged.clock.monotonicEndNanoseconds = 10_000_000_000
        forged.clock.wallStart = Date(timeIntervalSince1970: 5)
        forged.clock.wallEnd = Date(timeIntervalSince1970: 10)
        forged.progressReceiptID = ReceiptID("accepted-progress")
        forged.evidenceReceiptIDs = [ReceiptID("invented-evidence")]
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordOccurrence(forged),
                context: context(
                    "record-invented-evidence",
                    sequence: state.sequence,
                    actor: worker
                )
            ),
            .rejected(.invalidOccurrenceReceipt(
                "evidence bindings must reference typed journal evidence receipts"
            ))
        )
        forged.evidenceReceiptIDs = [ReceiptID("verification")]
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordOccurrence(forged),
            context: context("record-accepted-occurrence", sequence: state.sequence, actor: worker)
        ))

        let projection = KernelRunProjection(state: state)
        XCTAssertEqual(projection.durationRequiredSeconds, 5)
        XCTAssertEqual(projection.durationAcceptedSeconds, 5)
        XCTAssertEqual(projection.durationExcludedSeconds, 5)
        XCTAssertEqual(projection.durationCoverageViolations, [.acceptedWithoutProgress])
        guard case .accepted = RunReducer.handle(
            state: state,
            command: .requestCompletion,
            context: context("duration-satisfied", sequence: state.sequence, actor: reviewer)
        ) else {
            return XCTFail("Only journal-bound accepted progress should satisfy duration")
        }
    }

    func testLifecycleRequestsCannotDowngradeStopOrHijackCompletionDrain() throws {
        var stopping = try createdState()
        stopping = try accepted(RunReducer.handle(
            state: stopping,
            command: .requestStop,
            context: context("stop-first", sequence: stopping.sequence, actor: worker)
        ))
        XCTAssertEqual(
            RunReducer.handle(
                state: stopping,
                command: .requestPause,
                context: context("late-pause", sequence: stopping.sequence, actor: worker)
            ),
            .rejected(.invalidTransition(phase: .stopRequested, command: "requestPause"))
        )

        var completing = try reviewedState()
        completing = try accepted(RunReducer.handle(
            state: completing,
            command: .requestCompletion,
            context: context("complete-first", sequence: completing.sequence, actor: reviewer)
        ))
        XCTAssertEqual(
            RunReducer.handle(
                state: completing,
                command: .requestPause,
                context: context("pause-completion", sequence: completing.sequence, actor: worker)
            ),
            .rejected(.invalidTransition(
                phase: .completionRequested,
                command: "requestPause"
            ))
        )
    }

    func testReplayProducesIdenticalStateAndEventEncoding() throws {
        let initial = KernelRunState.empty(runID: runID)
        let decision = RunReducer.handle(
            state: initial,
            command: .createRun(makeContract()),
            context: context("create", sequence: 0, actor: worker)
        )
        guard case .accepted(let events, let expected) = decision else {
            return XCTFail("Expected accepted create")
        }

        let replayed = events.reduce(initial) { RunReducer.reduce(state: $0, event: $1) }
        XCTAssertEqual(replayed, expected)

        let encoded = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([OrchestrationEvent].self, from: encoded)
        XCTAssertEqual(decoded, events)
    }

    func testExternalDependencyActivationRequiresExactAuthorizedReceipt()
        throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: runDirectory)
        }
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: false
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: runDirectory.path
        )
        let canonicalWorkspace = workspace.standardizedFileURL
            .resolvingSymlinksInPath()
        let observer = ActorIdentity(
            id: ActorID("dependency-observer"),
            role: "external-observer",
            lineageDigest: ContentDigest(String(repeating: "d", count: 64))
        )
        var contract = makeContract()
        contract.workspaceBinding = TaskContractWorkspaceBinding(
            workspaceID: WorkspaceID("workspace"),
            canonicalRootDigest: WorkspaceRepositoryIndexer
                .canonicalRootDigest(canonicalWorkspace)
        )
        contract.externalDependencies = [ExternalDependencyContract(
            id: externalDependencyID,
            kind: .authority,
            requirementIDs: [requirementID],
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe-17"),
            authorizedObserverLineageDigests: [observer.lineageDigest],
            executableProbe: externalDependencyObservationProbeFixture()
        )]
        let state = try startAttempt(in: authorizedState(contract: contract))
        let probe = try XCTUnwrap(contract.externalDependencies?.first?
            .executableProbe)
        let receiptID = ReceiptID("dependency-activation")
        let sourceFrameDigest = ContentDigest(
            String(repeating: "f", count: 64)
        )
        let nonce = ExternalDependencyObservationActivationCompiler
            .requestNonce(
                runID: runID,
                attemptID: attemptID,
                dependencyID: externalDependencyID,
                evidenceRecipeID: ExternalDependencyEvidenceRecipeID(
                    "probe-17"
                ),
                observerLineageDigest: observer.lineageDigest,
                receiptID: receiptID,
                sourceJournalSequence: state.sequence,
                sourceJournalFrameDigest: sourceFrameDigest
            )
        let envelope = ExternalDependencyObservationRequestEnvelope(
            attemptID: attemptID,
            dependencyID: externalDependencyID,
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe-17"),
            observerLineageDigest: observer.lineageDigest,
            requestNonce: nonce,
            runID: runID,
            schemaVersion: 1,
            sourceJournalFrameDigest: sourceFrameDigest,
            sourceJournalSequence: state.sequence
        )
        let artifact = try
            ExternalDependencyObservationRequestArtifactIssuer().materialize(
                envelope: envelope,
                receiptID: receiptID,
                journalRunDirectory: runDirectory
            )
        let resolvedArguments = probe.fixedArguments.map {
            $0 == ExternalDependencyObservationExecutableProbe
                .requestArgumentToken
                ? ExternalDependencyObservationActivationCompiler
                    .requestDescriptorPath
                : $0
        }
        let activatedAt = Date(
            timeIntervalSince1970: TimeInterval(state.sequence + 1)
        )
        let receipt = ExternalDependencyObservationActivationReceipt(
            schemaVersion: 1,
            id: receiptID,
            runID: runID,
            attemptID: attemptID,
            dependencyID: externalDependencyID,
            requirementIDs: [requirementID],
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe-17"),
            observer: observer,
            workerLineageDigest: worker.lineageDigest,
            workspaceRootPath: canonicalWorkspace.path,
            workspaceRootPathDigest: WorkspaceRepositoryIndexer
                .canonicalRootDigest(canonicalWorkspace),
            executableStaging: KernelExecutableStagingReceipt(
                sourceExecutablePath: "/test/source",
                stagedExecutablePath: "/test/staged",
                contentDigest: probe.executableContentDigest,
                byteCount: 1,
                deviceID: 1,
                inode: 2,
                materialization: .streamCopy,
                reusedExistingArtifact: false
            ),
            probeDigest: try XCTUnwrap(
                ExternalDependencyObservationActivationCompiler
                    .probeDigest(probe)
            ),
            requestArtifact: artifact.receipt,
            resolvedArguments: resolvedArguments,
            argumentVectorDigest: KernelProviderInvocationCompiler
                .argumentVectorDigest(resolvedArguments),
            environmentIdentityDigest: probe.environmentIdentityDigest,
            captureIdentityDigest: probe.captureIdentityDigest,
            parser: probe.parser,
            resultMappings: probe.resultMappings,
            networkPolicy: probe.networkPolicy,
            resourceLimits: probe.resourceLimits,
            sourceJournalSequence: state.sequence,
            sourceJournalFrameDigest: sourceFrameDigest,
            activatedAt: activatedAt
        )
        let decision = RunReducer.handle(
            state: state,
            command: .activateExternalDependencyObservation(
                .testOnly(receipt)
            ),
            context: context(
                "dependency-activation",
                sequence: state.sequence,
                actor: observer
            )
        )
        let activated = try accepted(decision)
        XCTAssertEqual(
            activated.externalDependencyObservationActivationReceipts?[
                receiptID
            ],
            receipt
        )

        var tampered = receipt
        tampered.probeDigest = ContentDigest(String(repeating: "0", count: 64))
        let replayed = RunReducer.reduce(
            state: state,
            event: OrchestrationEvent(
                id: OrchestrationEventID("tampered-activation"),
                runID: runID,
                sequence: state.sequence + 1,
                commandID: RunCommandID("tampered-activation"),
                occurredAt: activatedAt,
                payload: .externalDependencyObservationActivated(tampered)
            )
        )
        XCTAssertEqual(replayed, state)

        let vetoedAt = activatedAt.addingTimeInterval(1)
        let veto = ExternalDependencyObservationLaunchVetoReceipt(
            schemaVersion: 1,
            id: ReceiptID("dependency-launch-veto"),
            runID: runID,
            activationReceiptID: receipt.id,
            activationSourceJournalFrameDigest:
                receipt.sourceJournalFrameDigest,
            attemptID: attemptID,
            dependencyID: externalDependencyID,
            observer: observer,
            requiredMaximumResidentBytes:
                receipt.resourceLimits.maximumResidentBytes,
            reason:
                .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
            sourceJournalSequence: activated.sequence,
            observedAt: vetoedAt
        )
        let vetoed = try accepted(RunReducer.handle(
            state: activated,
            command: .testOnlyRecordExternalDependencyObservationLaunchVeto(
                veto
            ),
            context: context(
                "dependency-launch-veto",
                sequence: activated.sequence,
                actor: observer
            )
        ))
        XCTAssertEqual(
            vetoed.externalDependencyObservationLaunchVetoReceipts?[veto.id],
            veto
        )
        XCTAssertTrue(vetoed.runtimeAdmissionReceipts.isEmpty)
        XCTAssertTrue(vetoed.runtimeLiveLeases.isEmpty)
        XCTAssertTrue((vetoed.externalDependencyReceipts ?? [:]).isEmpty)

        var tamperedVeto = veto
        tamperedVeto.requiredMaximumResidentBytes += 1
        let replayedTamperedVeto = RunReducer.reduce(
            state: activated,
            event: OrchestrationEvent(
                id: OrchestrationEventID("tampered-launch-veto"),
                runID: runID,
                sequence: activated.sequence + 1,
                commandID: RunCommandID("tampered-launch-veto"),
                occurredAt: vetoedAt,
                payload: .externalDependencyObservationLaunchVetoed(
                    tamperedVeto
                )
            )
        )
        XCTAssertEqual(replayedTamperedVeto, activated)
    }

    // MARK: - Fixtures

    private func makeContract() -> TaskContract {
        TaskContract(
            id: TaskContractID("contract"),
            schemaVersion: 1,
            verbatimObjective: "Satisfy the declared requirement without changing protected evidence.",
            objectiveDigest: ContentDigest("objective"),
            requirements: [RequirementContract(
                id: requirementID,
                statement: "Produce independently verifiable evidence.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("recipe")]
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeNode() -> KernelNodeContract {
        KernelNodeContract(
            id: nodeID,
            requirementIDs: [requirementID],
            objective: "Produce evidence",
            dependencies: [],
            mutationScope: .readOnly,
            capabilityIDs: [],
            strategyFingerprint: causalStrategy().fingerprint
        )
    }

    private func causalStrategy() -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [requirementID],
            hypothesisClass: "evidence-hypothesis",
            actionClass: "produce-evidence",
            workspaceTopology: "read-only-workspace",
            capabilityRoute: ["kernel-test"],
            evidenceSources: ["typed-receipt"],
            measurementBoundary: "requirement",
            verificationOracles: ["independent-review"],
            mutationSurfaceDigest: ContentDigest("no-mutation"),
            baselineRevision: ContentDigest("test-baseline"),
            expectedObservationIDs: ["evidence-produced"],
            falsificationPredicateIDs: ["evidence-missing"],
            inheritedLessonDigests: []
        )
    }

    private func contractWithExternalDependency() -> TaskContract {
        var contract = makeContract()
        contract.externalDependencies = [ExternalDependencyContract(
            id: externalDependencyID,
            kind: .authority,
            requirementIDs: [requirementID],
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe-17"),
            authorizedObserverLineageDigests: [reviewer.lineageDigest],
            executableProbe: externalDependencyObservationProbeFixture()
        )]
        return contract
    }

    private func externalDependencyReceipt(
        observer: ActorIdentity
    ) -> ExternalDependencyObservationReceipt {
        ExternalDependencyObservationReceipt(
            id: ReceiptID("external-dependency-observation"),
            attemptID: attemptID,
            dependencyID: externalDependencyID,
            requirementIDs: [requirementID],
            observer: observer,
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe-17"),
            evidenceDigest: ContentDigest(String(repeating: "e", count: 64)),
            availability: .unavailable,
            observedAt: Date(timeIntervalSince1970: 5)
        )
    }

    private func workerParseReceipt(
        id: ReceiptID,
        disposition: KernelWorkerProposedDisposition
    ) -> KernelWorkerResultParseReceipt {
        let identity = RuntimeExternalIdentity(
            stableDigest: ContentDigest("identity"),
            processID: 1,
            processStartMonotonicNanoseconds: 1
        )
        return KernelWorkerResultParseReceipt(
            id: id,
            parserIdentityDigest: KernelWorkerResultParser.parserIdentityDigest,
            runID: runID,
            attemptID: attemptID,
            resourceID: OwnedResourceID("resource"),
            leaseID: ResourceLeaseID("lease"),
            bindingReceiptID: ReceiptID("binding"),
            releaseReceiptID: ReceiptID("release"),
            invocationDigest: ContentDigest("invocation"),
            requestNonce: ContentDigest("nonce"),
            threadID: "thread",
            eventCount: 1,
            stdoutContentDigest: ContentDigest("stdout"),
            stderrContentDigest: ContentDigest("stderr"),
            terminalEnvelopeDigest: ContentDigest("terminal"),
            proposedDisposition: disposition,
            proposedResultDigest: ContentDigest("result"),
            nativeExit: ManagedProcessExitReceipt(
                handle: ManagedProcessHandle(
                    runID: runID,
                    resourceID: OwnedResourceID("resource"),
                    leaseID: ResourceLeaseID("lease"),
                    processID: 1,
                    processGroupID: 1,
                    externalIdentity: identity
                ),
                observedAtMonotonicNanoseconds: 2,
                exitCode: 0,
                terminationSignal: nil
            )
        )
    }

    private func context(
        _ id: String,
        sequence: UInt64,
        actor: ActorIdentity
    ) -> KernelCommandContext {
        KernelCommandContext(
            commandID: RunCommandID(id),
            expectedSequence: sequence,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(sequence + 1)),
            actor: actor
        )
    }

    private func accepted(_ decision: ReducerDecision) throws -> KernelRunState {
        guard case .accepted(_, let state) = decision else {
            throw NSError(domain: "KernelRunReducerTests", code: 1)
        }
        return state
    }

    private func recordedDrain(
        _ input: KernelRunState,
        intent: RuntimeDrainIntent,
        id: String
    ) throws -> KernelRunState {
        let receipt = RuntimeDrainReceipt(
            id: ReceiptID(id),
            runID: runID,
            snapshot: RuntimeDrainSnapshot(
                intent: intent,
                liveResourceIDs: Set(input.runtimeLiveLeases.keys),
                cancelledQueuedLeaseIDs: []
            ),
            observedAt: Date(timeIntervalSince1970: TimeInterval(input.sequence + 1)),
            observedAtMonotonicNanoseconds: input.sequence + 1
        )
        return try accepted(RunReducer.handle(
            state: input,
            command: .testOnlyRecordRuntimeDrain(receipt),
            context: context(id, sequence: input.sequence, actor: worker)
        ))
    }

    private func createdState(contract: TaskContract? = nil) throws -> KernelRunState {
        try accepted(RunReducer.handle(
            state: .empty(runID: runID),
            command: .createRun(contract ?? makeContract()),
            context: context("create", sequence: 0, actor: worker)
        ))
    }

    private func plannedState(contract: TaskContract? = nil) throws -> KernelRunState {
        var state = try createdState(contract: contract)
        state = try accepted(RunReducer.handle(
            state: state,
            command: .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("objective"),
                nodes: [makeNode()]
            )),
            context: context("plan", sequence: state.sequence, actor: worker)
        ))
        return state
    }

    private func authorizedState(contract: TaskContract? = nil) throws -> KernelRunState {
        var state = try plannedState(contract: contract)
        state = try accepted(RunReducer.handle(
            state: state,
            command: .authorizeNode(nodeID),
            context: context("authorize", sequence: state.sequence, actor: reviewer)
        ))
        return state
    }

    private func startAttempt(in input: KernelRunState) throws -> KernelRunState {
        var state = input
        if state.convergenceGovernor == nil {
            state = try accepted(RunReducer.handle(
                state: state,
                command: .initializeConvergence(
                    epochID: "test-epoch",
                    budget: ConvergenceBudget(
                        maximumAttempts: 4,
                        maximumEquivalentFailures: 2,
                        maximumStrategies: 4,
                        maximumPlanExpansions: 2,
                        maximumMutationCost: 100,
                        maximumVerificationCost: 100,
                        maximumDamageEvents: 1,
                        maximumExternalEffects: 4
                    )
                ),
                context: context("initialize-convergence", sequence: state.sequence, actor: reviewer)
            ))
        }
        state = try accepted(RunReducer.handle(
            state: state,
            command: .admitCausalAttempt(AttemptAdmissionRequest(
                attemptID: attemptID,
                strategy: causalStrategy(),
                predictedObservationIDs: ["evidence-produced"],
                falsificationPredicateIDs: ["evidence-missing"],
                rollbackPoint: ContentDigest("test-rollback"),
                mutationCost: 0,
                verificationCost: 1,
                externalEffects: 0
            )),
            context: context("admit-attempt", sequence: state.sequence, actor: reviewer)
        ))
        return try accepted(RunReducer.handle(
            state: state,
            command: .startAttempt(
                attemptID: attemptID,
                nodeID: nodeID,
                requirementIDs: [requirementID],
                strategyFingerprint: causalStrategy().fingerprint
            ),
            context: context("start", sequence: state.sequence, actor: worker)
        ))
    }

    private func completedAttemptState(contract: TaskContract? = nil) throws -> KernelRunState {
        legacyDispositionState(
            try startAttempt(in: authorizedState(contract: contract)),
            .completed,
            id: "legacy-completed"
        )
    }

    /// Downstream evidence tests retain explicit replay coverage for journals
    /// written before direct execution authority was retired. New commands can
    /// no longer create this payload.
    private func legacyDispositionState(
        _ state: KernelRunState,
        _ disposition: KernelExecutionDisposition,
        id: String
    ) -> KernelRunState {
        RunReducer.reduce(
            state: state,
            event: OrchestrationEvent(
                id: OrchestrationEventID("\(id).\(state.sequence + 1)"),
                runID: state.runID,
                sequence: state.sequence + 1,
                commandID: RunCommandID(id),
                occurredAt: Date(timeIntervalSince1970: TimeInterval(state.sequence + 1)),
                payload: .executionRecorded(attemptID: attemptID, disposition: disposition)
            )
        )
    }

    private func reviewedState(contract: TaskContract? = nil) throws -> KernelRunState {
        var state = try completedAttemptState(contract: contract)
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordVerification(verificationReceipt()),
            context: context("verify", sequence: state.sequence, actor: reviewer)
        ))
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordReview(reviewReceipt(reviewer: reviewer)),
            context: context("review", sequence: state.sequence, actor: reviewer)
        ))
        return state
    }

    private func verificationReceipt() -> VerificationReceipt {
        VerificationReceipt(
            id: ReceiptID("verification"),
            attemptID: attemptID,
            requirementIDs: [requirementID],
            sourceRevision: ContentDigest("revision"),
            environmentDigest: ContentDigest("environment"),
            oracleDigest: ContentDigest("oracle"),
            result: .accepted
        )
    }

    private func postimageVerificationReceipt(
        suffix: Character,
        releaseSequence: UInt64,
        result: VerificationResult,
        oracleDigest: ContentDigest = ContentDigest(
            String(repeating: "c", count: 64)
        )
    ) -> VerificationReceipt {
        let resultDigest = ContentDigest(String(repeating: suffix, count: 64))
        let provisional = VerificationReceipt(
            id: ReceiptID("verification:provisional"),
            attemptID: attemptID,
            requirementIDs: [requirementID],
            sourceRevision: ContentDigest(String(repeating: "a", count: 64)),
            environmentDigest: ContentDigest(String(repeating: "b", count: 64)),
            oracleDigest: oracleDigest,
            result: result,
            postimageEvidenceBatch: KernelVerificationEvidenceBatch(
                schemaVersion: 1,
                postimageResultID: ReceiptID(
                    "postimage-result:\(resultDigest.rawValue)"
                ),
                postimageResultEvidenceSetDigest: resultDigest,
                postimageReleaseReceiptID: ReceiptID(
                    "postimage-release-\(suffix)"
                ),
                postimageReleaseCommandID: RunCommandID(
                    "postimage-release-command-\(suffix)"
                ),
                postimageReleaseEndingSequence: releaseSequence,
                postimageReleaseFrameDigest: ContentDigest(
                    String(repeating: "f", count: 64)
                ),
                evidenceSetDigest: ContentDigest(String(repeating: "0", count: 64))
            )
        )
        var canonical = provisional
        let evidenceSetDigest = KernelPostimageVerificationAuthority
            .expectedEvidenceSetDigest(provisional)!
        canonical.postimageEvidenceBatch?.evidenceSetDigest =
            evidenceSetDigest
        canonical.id = ReceiptID(
            "verification:\(evidenceSetDigest.rawValue)"
        )
        return canonical
    }

    private func deliverableMembers(
        count: Int,
        contentDigest: String? = nil
    ) -> Set<DeliverableMemberObservation> {
        Set((0..<count).map { index in
            DeliverableMemberObservation(
                stableID: "opaque-member-\(index)",
                contentDigest: ContentDigest(contentDigest ?? "digest-\(index)")
            )
        })
    }

    private func reviewReceipt(reviewer: ActorIdentity) -> IndependentReviewReceipt {
        IndependentReviewReceipt(
            id: ReceiptID("review-\(reviewer.id.rawValue)"),
            attemptID: attemptID,
            requirementIDs: [requirementID],
            reviewer: reviewer,
            evidenceDigest: ContentDigest("evidence"),
            sourceRevision: ContentDigest("revision"),
            decision: .approveCandidate
        )
    }
}
