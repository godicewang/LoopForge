import CryptoKit
import XCTest
@testable import LoopForge

final class TaskContractCompilerTests: XCTestCase {
    func testExactUTF8SourceSurvivesEncodeDecodeAndProducesStableDigest() throws {
        let candidate = makeCandidate(objective: "Preserve café ☕ while adapting the interface.")
        let compiled = try accepted(candidate)
        let data = try JSONEncoder.loopForge.encode(candidate)
        let decoded = try JSONDecoder.loopForge.decode(
            TaskContractCompilationCandidate.self,
            from: data
        )
        let replayed = try accepted(decoded)

        XCTAssertEqual(decoded.sources[0].exactUTF8, candidate.sources[0].exactUTF8)
        XCTAssertNil(decoded.externalDependencyBindings)
        XCTAssertEqual(replayed.candidateDigest, compiled.candidateDigest)
    }

    func testObjectiveMustBeExactVerbatimSourceAndDigestBound() {
        var rewritten = makeCandidate()
        rewritten.contract.verbatimObjective = "A polished rewrite"
        XCTAssertContainsIssue(compileIssues(rewritten), .objectiveNotVerbatim)
        XCTAssertContainsIssue(compileIssues(rewritten), .objectiveDigestMismatch)

        var digestMismatch = makeCandidate()
        digestMismatch.contract.objectiveDigest = ContentDigest("other")
        XCTAssertContainsIssue(compileIssues(digestMismatch), .objectiveDigestMismatch)
    }

    func testSpanMustBindExactSourceDigestAndUTF8Boundaries() {
        var candidate = makeCandidate(objective: "Keep ☕ stable")
        candidate.requirementBindings[0].sourceSpans[0].lowerUTF8Offset = 6
        candidate.requirementBindings[0].sourceSpans[0].upperUTF8Offset = 7
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .invalidSourceSpan("requirement:outcome")
        )

        candidate = makeCandidate()
        candidate.constraintBindings[0].sourceSpans[0].sourceDigest = ContentDigest("stale")
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .invalidSourceSpan("constraint:authority")
        )
    }

    func testModelProposalCannotBecomeExplicitUserAuthority() {
        var candidate = makeCandidate()
        candidate.sources[0].authority = .modelProposal
        XCTAssertContainsIssue(compileIssues(candidate), .objectiveSourceLacksUserAuthority)
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .explicitClaimLacksUserAuthority("requirement:outcome")
        )
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .explicitClaimLacksUserAuthority("constraint:authority")
        )
    }

    func testMandatoryRequirementNeedsExactIndependentlyDeclaredRecipe() {
        var candidate = makeCandidate()
        candidate.evidenceRecipes = []
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .missingMandatoryEvidenceRecipe("outcome")
        )

        candidate = makeCandidate()
        candidate.evidenceRecipes[0].requirementID = RequirementID("unknown")
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .evidenceRecipeMismatch("recipe")
        )

        candidate = makeCandidate()
        candidate.evidenceRecipes[0].executableProbe = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .evidenceRecipeMismatch("recipe")
        )

        candidate = makeCandidate()
        candidate.evidenceRecipes[0].executableProbe?.networkPolicy = .enabled
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .evidenceRecipeMismatch("recipe")
        )

        candidate = makeCandidate()
        candidate.evidenceRecipes[0].executableProbe?.executableContentDigest =
            ContentDigest(String(repeating: "ａ", count: 64))
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .evidenceRecipeMismatch("recipe")
        )
    }

    func testDuplicateContractRequirementRejectsWithoutCrashingCompiler() {
        var candidate = makeCandidate()
        candidate.contract.requirements.append(candidate.contract.requirements[0])
        let issues = compileIssues(candidate)
        XCTAssertTrue(issues.contains {
            if case .invalidContract(let message) = $0 {
                return message == "requirement identifiers must be unique"
            }
            return false
        })
    }

    func testAuthorityExpansionRequiresExplicitUserBoundConstraint() {
        var candidate = makeCandidate()
        candidate.constraintBindings[0].epistemicState = .workspaceObserved
        XCTAssertContainsIssue(compileIssues(candidate), .unboundAuthorityExpansion)

        candidate = makeCandidate()
        candidate.contract.constraints[0].kind = .preserve
        XCTAssertContainsIssue(compileIssues(candidate), .unboundAuthorityExpansion)
    }

    func testObjectiveCapabilityWordsDoNotCreateCapabilityAuthority() throws {
        let candidate = makeCandidate(
            objective: "Mention browser PHOTO simulator and HANDOFF without granting access"
        )
        let compiled = try accepted(candidate)

        XCTAssertTrue(compiled.candidate.contract.authorityCeiling.capabilityIDs.isEmpty)
    }

    func testExplicitConstraintCannotGrantCapabilityWithoutOutOfBandReceipt() {
        var candidate = makeCandidate()
        candidate.contract.authorityCeiling.capabilityIDs = ["opaque-capability-17"]

        XCTAssertContainsIssue(
            compileIssues(candidate),
            .capabilityGrantSetMismatch
        )
    }

    func testModelCandidateJSONCannotSmuggleCapabilityGrantReceipt() throws {
        var candidate = makeCandidate()
        candidate.contract.authorityCeiling.capabilityIDs = ["opaque-capability-17"]
        let encoded = try JSONEncoder.loopForge.encode(candidate)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["capabilityGrantReceipts"] = [[
            "capabilityID": "opaque-capability-17",
            "grantNonceDigest": "model-authored"
        ]]
        let injected = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.loopForge.decode(
            TaskContractCompilationCandidate.self,
            from: injected
        )

        XCTAssertContainsIssue(
            compileIssues(decoded),
            .capabilityGrantSetMismatch
        )
    }

    func testExactOutOfBandCapabilityGrantBindsWholeAuthorityCeiling() throws {
        var candidate = makeCandidate()
        candidate.contract.authorityCeiling.capabilityIDs = ["opaque-capability-17"]
        let ceilingDigest = try XCTUnwrap(TaskContractCompiler.authorityCeilingDigest(
            candidate.contract.authorityCeiling
        ))
        let receipt = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-17"
        )

        let compiled = try accepted(candidate, capabilityGrantReceipts: [receipt])
        XCTAssertEqual(
            compiled.candidate.contract.authorityCeiling.capabilityIDs,
            ["opaque-capability-17"]
        )
        XCTAssertEqual(
            compiled.capabilityGrantReceiptDigests["opaque-capability-17"],
            TaskContractCompiler.capabilityGrantDigest(receipt)
        )
        let ratification = try ratified(compiled)
        XCTAssertEqual(
            ratification.capabilityGrantReceiptDigests,
            compiled.capabilityGrantReceiptDigests
        )

        let differentReceipt = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-17",
            grantNonceDigest: ContentDigest("different-grant")
        )
        let differentlyGranted = try accepted(
            candidate,
            capabilityGrantReceipts: [differentReceipt]
        )
        XCTAssertNotEqual(differentlyGranted.candidateDigest, compiled.candidateDigest)
        XCTAssertNotEqual(
            differentlyGranted.capabilityGrantReceiptDigests,
            compiled.capabilityGrantReceiptDigests
        )

        candidate.contract.authorityCeiling.writableScopes.insert("additional-scope")
        let changedIssues = compileIssues(candidate, capabilityGrantReceipts: [receipt])
        XCTAssertContainsIssue(
            changedIssues,
            .capabilityGrantReceiptMismatch("opaque-capability-17")
        )
    }

    func testCapabilityGrantRejectsDuplicateStaleAndWrongUserReceipts() throws {
        var candidate = makeCandidate()
        candidate.contract.authorityCeiling.capabilityIDs = ["opaque-capability-17"]
        let ceilingDigest = try XCTUnwrap(TaskContractCompiler.authorityCeilingDigest(
            candidate.contract.authorityCeiling
        ))
        let valid = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-17"
        )
        XCTAssertContainsIssue(
            compileIssues(candidate, capabilityGrantReceipts: [valid, valid]),
            .duplicateCapabilityGrantReceipt("opaque-capability-17")
        )

        let stale = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision + 1,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-17"
        )
        XCTAssertContainsIssue(
            compileIssues(candidate, capabilityGrantReceipts: [stale]),
            .capabilityGrantReceiptMismatch("opaque-capability-17")
        )

        let wrongUser = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-17",
            userActorID: ActorID("other-user"),
            userActorLineageDigest: ContentDigest("other-lineage")
        )
        XCTAssertContainsIssue(
            compileIssues(candidate, capabilityGrantReceipts: [wrongUser]),
            .capabilityGrantReceiptMismatch("opaque-capability-17")
        )
    }

    func testCapabilityGrantRequiresValidIDsAndTheExactDeclaredSet() throws {
        var malformed = makeCandidate()
        malformed.contract.authorityCeiling.capabilityIDs = [" padded-capability "]
        XCTAssertContainsIssue(
            compileIssues(malformed),
            .invalidContract("authority capability IDs must be exact and nonempty")
        )

        var candidate = makeCandidate()
        candidate.contract.authorityCeiling.capabilityIDs = [
            "opaque-capability-17",
            "opaque-capability-29"
        ]
        let ceilingDigest = try XCTUnwrap(TaskContractCompiler.authorityCeilingDigest(
            candidate.contract.authorityCeiling
        ))
        let first = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-17"
        )
        XCTAssertContainsIssue(
            compileIssues(candidate, capabilityGrantReceipts: [first]),
            .capabilityGrantSetMismatch
        )

        let second = TaskContractCapabilityGrantReceipt.testOnlyExactGrant(
            contractID: candidate.contract.id,
            candidateRevision: candidate.revision,
            authorityCeilingDigest: ceilingDigest,
            capabilityID: "opaque-capability-29"
        )
        switch TaskContractCompiler.compile(
            candidate,
            capabilityGrantReceipts: [second, first]
        ) {
        case .success(let compiled):
            XCTAssertEqual(
                compiled.candidate.contract.authorityCeiling.capabilityIDs,
                ["opaque-capability-17", "opaque-capability-29"]
            )
        case .failure(let failure):
            XCTFail("Unexpected compiler issues: \(failure.issues)")
        }
    }

    func testExactDeliverableCardinalityRequiresExplicitUserBoundRequirement() throws {
        var candidate = makeCandidate()
        candidate.contract.requirements[0].deliverableCardinality =
            DeliverableCardinalityConstraint(
                collectionID: "deliverable-set-7",
                exactCount: 10
            )
        candidate.requirementBindings[0].epistemicState = .inferredSafe
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .cardinalityLacksExplicitAuthority("outcome")
        )

        candidate.requirementBindings[0].epistemicState = .explicit
        let compiled = try accepted(candidate)
        XCTAssertEqual(
            compiled.candidate.contract.requirements[0].deliverableCardinality?.exactCount,
            10
        )
    }

    func testExternalDependencyRequiresExactExplicitSourceBinding() throws {
        var candidate = makeCandidate()
        let dependencyID = ExternalDependencyID("dependency-17")
        candidate.contract.externalDependencies = [ExternalDependencyContract(
            id: dependencyID,
            kind: .externalCondition,
            requirementIDs: [RequirementID("outcome")],
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("probe-17"),
            authorizedObserverLineageDigests: [ContentDigest("observer-lineage")],
            executableProbe: externalDependencyObservationProbeFixture()
        )]
        candidate.externalDependencyBindings = [ExternalDependencySourceBinding(
            dependencyID: dependencyID,
            sourceSpans: candidate.requirementBindings[0].sourceSpans,
            epistemicState: .proposed
        )]
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .externalDependencyLacksExplicitAuthority("dependency-17")
        )

        candidate.externalDependencyBindings?[0].epistemicState = .explicit
        let compiled = try accepted(candidate)
        XCTAssertEqual(
            compiled.candidate.contract.externalDependencies?.first?.id,
            dependencyID
        )

        candidate.externalDependencyBindings = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .externalDependencyBindingMismatch
        )
    }

    func testAmbiguityMatrixRejectsUnsafeDowngrade() {
        var candidate = makeCandidate()
        candidate.ambiguities = [ambiguity(
            impact: .protectedIdentityOrDesign,
            reversible: true,
            resolution: .boundedAssumption
        )]
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .invalidAmbiguityResolution("ambiguity")
        )

        candidate.ambiguities = [ambiguity(
            impact: .authorityScope,
            reversible: true,
            resolution: .rollbackExperiment
        )]
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .invalidAmbiguityResolution("ambiguity")
        )
    }

    func testBlockingAmbiguityRatifiesReadOnlyWithoutMutationEligibility() throws {
        var candidate = makeCandidate()
        candidate.ambiguities = [ambiguity(
            impact: .unavailableEvidence,
            reversible: true,
            resolution: .readOnlyDiscovery
        )]
        let compiled = try accepted(candidate)
        XCTAssertEqual(compiled.executionEligibility, .readOnlyDiscovery)
        XCTAssertEqual(compiled.blockingAmbiguityIDs.map(\.rawValue), ["ambiguity"])

        let ratified = try ratified(compiled)
        XCTAssertEqual(ratified.executionEligibility, .readOnlyDiscovery)
        XCTAssertEqual(ratified.blockingAmbiguityIDs.map(\.rawValue), ["ambiguity"])
    }

    func testSafeLocalAmbiguityRetainsContractCeiling() throws {
        var candidate = makeCandidate()
        candidate.ambiguities = [ambiguity(
            impact: .local,
            reversible: true,
            resolution: .boundedAssumption
        )]
        let compiled = try accepted(candidate)
        XCTAssertEqual(compiled.executionEligibility, .contractAuthorityCeiling)
        XCTAssertTrue(compiled.blockingAmbiguityIDs.isEmpty)
    }

    func testStaleConfirmationCannotRatifyChangedCandidate() throws {
        let first = try accepted(makeCandidate())
        var changed = makeCandidate()
        changed.contract.nonGoals = ["Do not alter unrelated artifacts"]
        let second = try accepted(changed)
        let stale = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
            candidateDigest: first.candidateDigest,
            confirmedAt: Date(timeIntervalSince1970: 3)
        )
        XCTAssertEqual(
            TaskContractCompiler.ratify(second, confirmation: stale),
            .failure(.candidateDigestMismatch)
        )
    }

    func testRatificationRetainsExactRecipeAndRejectsPostCompileMutation() throws {
        let candidate = makeCandidate()
        let compiled = try accepted(candidate)
        let confirmation = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
            candidateDigest: compiled.candidateDigest,
            confirmedAt: Date(timeIntervalSince1970: 3)
        )
        guard case .success(let ratified) = TaskContractCompiler.ratify(
            compiled,
            confirmation: confirmation
        ) else {
            return XCTFail("Expected exact compiled candidate to ratify")
        }
        XCTAssertEqual(
            ratified.contract.requirementEvidenceRecipes,
            candidate.evidenceRecipes
        )
        XCTAssertTrue(
            ratified.contract.hasCompleteRequirementEvidenceRecipeProvenance
        )

        var mutated = compiled
        mutated.candidate.evidenceRecipes[0].expectedObservation =
            "Post-compile replacement observation"
        XCTAssertEqual(
            TaskContractCompiler.ratify(mutated, confirmation: confirmation),
            .failure(.candidateDigestMismatch)
        )
    }

    func testLegacyDescriptiveRecipeDecodesOnlyForForensicRecovery() throws {
        let candidate = makeCandidate()
        let encoded = try JSONEncoder.loopForge.encode(candidate.evidenceRecipes[0])
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "executableProbe")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder.loopForge.decode(
            RequirementEvidenceRecipe.self,
            from: legacyData
        )
        XCTAssertNil(decoded.executableProbe)

        var legacyCandidate = candidate
        legacyCandidate.evidenceRecipes = [decoded]
        XCTAssertContainsIssue(
            compileIssues(legacyCandidate),
            .evidenceRecipeMismatch(decoded.id.rawValue)
        )
        var legacyContract = candidate.contract
        legacyContract.requirementEvidenceRecipes = [decoded]
        XCTAssertFalse(legacyContract.hasCompleteRequirementEvidenceRecipeProvenance)
        XCTAssertTrue(legacyContract.validationIssues().contains {
            $0.contains("retained requirement evidence recipes")
        })
    }

    func testLegacyParserIdentityDecodesButCannotAuthorizeV2Probe() throws {
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "id": "legacy-descriptive-parser",
            "schemaVersion": 1,
            "contentDigest": String(repeating: "f", count: 64)
        ])
        let decoded = try JSONDecoder.loopForge.decode(
            RequirementVerificationParserContract.self,
            from: legacyData
        )
        XCTAssertNil(decoded.format)

        var probe = Self.verificationProbe
        probe.parser = decoded
        XCTAssertTrue(probe.validationIssues().contains {
            $0.contains("supported canonical result grammar")
        })
    }

    func testConfirmationMustFollowCompilationAndCarryNonce() throws {
        let compiled = try accepted(makeCandidate())
        let early = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
            candidateDigest: compiled.candidateDigest,
            confirmedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(
            TaskContractCompiler.ratify(compiled, confirmation: early),
            .failure(.malformedConfirmation)
        )
        let empty = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
            candidateDigest: compiled.candidateDigest,
            confirmationNonce: ContentDigest(""),
            confirmedAt: Date(timeIntervalSince1970: 3)
        )
        XCTAssertEqual(
            TaskContractCompiler.ratify(compiled, confirmation: empty),
            .failure(.malformedConfirmation)
        )
        let missingActor = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
            candidateDigest: compiled.candidateDigest,
            confirmedAt: Date(timeIntervalSince1970: 3),
            userActor: ActorIdentity(
                id: ActorID(""),
                role: "user",
                lineageDigest: ContentDigest("")
            )
        )
        XCTAssertEqual(
            TaskContractCompiler.ratify(compiled, confirmation: missingActor),
            .failure(.malformedConfirmation)
        )
    }

    func testEquivalentDomainNeutralContractsReceiveSamePolicy() throws {
        let first = try accepted(makeCandidate(objective: "Transform artifact alpha safely"))
        let second = try accepted(makeCandidate(objective: "Transform artifact beta safely"))
        XCTAssertEqual(first.executionEligibility, second.executionEligibility)
        XCTAssertEqual(first.blockingAmbiguityIDs.count, second.blockingAmbiguityIDs.count)
    }

    private func makeCandidate(
        objective: String = "Adapt the selected artifact and preserve unrelated work"
    ) -> TaskContractCompilationCandidate {
        let createdAt = Date(timeIntervalSince1970: 2)
        let actor = ActorIdentity(
            id: ActorID("user"),
            role: "user",
            lineageDigest: ContentDigest("user-lineage")
        )
        let source = TaskContractSourceArtifact(
            id: TaskContractSourceID("initial"),
            exactUTF8: Data(objective.utf8),
            authority: .user,
            author: actor,
            recordedAt: Date(timeIntervalSince1970: 1)
        )
        let span = TaskContractSourceSpan(
            sourceID: source.id,
            sourceDigest: source.digest,
            lowerUTF8Offset: 0,
            upperUTF8Offset: source.exactUTF8.count
        )
        let recipeID = EvidenceRecipeID("recipe")
        let requirementID = RequirementID("outcome")
        let contract = TaskContract(
            id: TaskContractID("contract"),
            schemaVersion: 1,
            verbatimObjective: objective,
            objectiveDigest: TaskContractCompiler.digest(Data(objective.utf8)),
            requirements: [RequirementContract(
                id: requirementID,
                statement: objective,
                mandatory: true,
                evidenceRecipeIDs: [recipeID]
            )],
            constraints: [ConstraintContract(
                id: "authority",
                kind: .requireAuthority,
                statement: "Mutation remains within the explicitly selected scope"
            )],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: KernelAuthorityCeiling(
                readableScopes: ["workspace"],
                writableScopes: ["workspace"],
                capabilityIDs: [],
                permitsExternalPublication: false
            ),
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: createdAt
        )
        return TaskContractCompilationCandidate(
            schemaVersion: 1,
            revision: 0,
            initialObjectiveSourceID: source.id,
            sources: [source],
            contract: contract,
            requirementBindings: [RequirementSourceBinding(
                requirementID: requirementID,
                sourceSpans: [span],
                epistemicState: .explicit
            )],
            constraintBindings: [ConstraintSourceBinding(
                constraintID: "authority",
                sourceSpans: [span],
                epistemicState: .explicit
            )],
            evidenceRecipes: [RequirementEvidenceRecipe(
                id: recipeID,
                requirementID: requirementID,
                verifierKind: .deterministic,
                expectedObservation: "The declared relation holds at the accepted revision",
                requiresIndependentLineage: true,
                executableProbe: Self.verificationProbe
            )],
            ambiguities: [],
            compilerActor: ActorIdentity(
                id: ActorID("compiler"),
                role: "contract-compiler",
                lineageDigest: ContentDigest("compiler-lineage")
            ),
            compiledAt: createdAt
        )
    }

    private static let verificationProbe = RequirementVerificationExecutableProbe(
        schemaVersion: 2,
        transport: .localDirectProcess,
        executableContentDigest: ContentDigest(String(repeating: "c", count: 64)),
        fixedArguments: [
            "--input", "@loopforge-input:candidate-postimage", "--jsonl"
        ],
        inputBindings: [RequirementVerificationInputBinding(
            id: "candidate-postimage",
            kind: .candidatePostimage,
            artifactID: "candidate-postimage",
            argumentToken: "@loopforge-input:candidate-postimage"
        )],
        environmentPolicy: .minimalKernelAllowlist,
        environmentIdentityDigest: ContentDigest(String(repeating: "d", count: 64)),
        captureIdentityDigest: ContentDigest(String(repeating: "e", count: 64)),
        parser: RequirementVerificationParserContract(
            id: "synthetic-jsonl-verifier",
            schemaVersion: 1,
            contentDigest: RequirementVerificationParserFormat
                .canonicalJSONResultV1.implementationIdentityDigest,
            format: .canonicalJSONResultV1
        ),
        resultMappings: [
            RequirementVerificationResultMapping(
                exitCode: 0,
                parserResultCode: "accepted",
                outcome: .accepted
            ),
            RequirementVerificationResultMapping(
                exitCode: 1,
                parserResultCode: "rejected",
                outcome: .rejected
            )
        ],
        unmatchedOutcome: .rejected,
        networkPolicy: .disabled,
        resourceLimits: RequirementVerificationResourceLimits(
            maximumWallClockSeconds: 60,
            maximumCapturedOutputBytes: 1_048_576,
            maximumResidentBytes: 268_435_456,
            maximumChildProcesses: 0
        )
    )

    private func ambiguity(
        impact: TaskContractAmbiguityImpact,
        reversible: Bool,
        resolution: TaskContractAmbiguityResolution
    ) -> TaskContractAmbiguity {
        let source = makeCandidate().sources[0]
        return TaskContractAmbiguity(
            id: TaskContractAmbiguityID("ambiguity"),
            sourceSpans: [TaskContractSourceSpan(
                sourceID: source.id,
                sourceDigest: source.digest,
                lowerUTF8Offset: 0,
                upperUTF8Offset: source.exactUTF8.count
            )],
            impact: impact,
            reversible: reversible,
            resolution: resolution
        )
    }

    private func accepted(
        _ candidate: TaskContractCompilationCandidate,
        capabilityGrantReceipts: [TaskContractCapabilityGrantReceipt] = []
    ) throws -> CompiledTaskContractCandidate {
        switch TaskContractCompiler.compile(
            candidate,
            capabilityGrantReceipts: capabilityGrantReceipts
        ) {
        case .success(let compiled): return compiled
        case .failure(let failure):
            XCTFail("Unexpected compiler issues: \(failure.issues)")
            throw NSError(domain: "TaskContractCompilerTests", code: 1)
        }
    }

    private func ratified(
        _ compiled: CompiledTaskContractCandidate
    ) throws -> TaskContractRatificationReceipt {
        let confirmation = TaskContractUserConfirmationReceipt.testOnlyExactConfirmation(
            candidateDigest: compiled.candidateDigest,
            confirmedAt: Date(timeIntervalSince1970: 3)
        )
        switch TaskContractCompiler.ratify(compiled, confirmation: confirmation) {
        case .success(let ratified): return ratified.receipt
        case .failure(let error):
            XCTFail("Unexpected ratification failure: \(error)")
            throw NSError(domain: "TaskContractCompilerTests", code: 2)
        }
    }

    private func compileIssues(
        _ candidate: TaskContractCompilationCandidate,
        capabilityGrantReceipts: [TaskContractCapabilityGrantReceipt] = []
    ) -> [TaskContractCompilationIssue] {
        switch TaskContractCompiler.compile(
            candidate,
            capabilityGrantReceipts: capabilityGrantReceipts
        ) {
        case .success:
            XCTFail("Expected compilation rejection")
            return []
        case .failure(let failure): return failure.issues
        }
    }

    private func XCTAssertContainsIssue(
        _ issues: [TaskContractCompilationIssue],
        _ expected: TaskContractCompilationIssue,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(issues.contains(expected), "Missing \(expected) in \(issues)", file: file, line: line)
    }
}
