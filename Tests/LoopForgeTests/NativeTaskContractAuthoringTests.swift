import Foundation
import XCTest
@testable import LoopForge

final class NativeTaskContractAuthoringTests: XCTestCase {
    func testNativeDraftBindsExactObjectiveWorkspaceScopesAndDuration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let duration = DurationAcceptancePolicy(
            requiredSeconds: 72_000,
            eligibleClass: .acceptedExecution
        )
        let draft = try prepared(fixture.request(duration: duration))

        XCTAssertEqual(draft.displayObjective, fixture.objective)
        XCTAssertEqual(draft.displayWorkspacePath, fixture.workspace.path)
        XCTAssertEqual(draft.displayReadableScopes, ["."])
        XCTAssertEqual(draft.displayWritableScopes, ["."])
        XCTAssertEqual(draft.displayDuration, duration)
        XCTAssertEqual(draft.compiled.executionEligibility, .contractAuthorityCeiling)
        XCTAssertTrue(draft.compiled.blockingAmbiguityIDs.isEmpty)
        XCTAssertEqual(draft.compiled.candidate.sources.count, 9)
        XCTAssertEqual(
            draft.compiled.candidate.sources[0].exactUTF8,
            Data(fixture.objective.utf8)
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.workspaceBinding?.workspaceID,
            fixture.workspaceID
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.authorityCeiling.writableScopes,
            ["."]
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.acceptancePolicy.duration,
            duration
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.executionProfile,
            fixture.executionProfile
        )
        XCTAssertEqual(draft.displayExecutionProfile, fixture.executionProfile)
        XCTAssertTrue(draft.displayAuthorityCapabilityIDs.isEmpty)
        XCTAssertTrue(draft.displayPermittedImplementationIDs.isEmpty)
        XCTAssertEqual(draft.displayExecutionBudgets, fixture.executionBudgets)
        XCTAssertEqual(
            draft.compiled.candidate.contract.executionBudgets,
            fixture.executionBudgets
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.sourceRevision,
            draft.displaySourceRevision
        )
        XCTAssertEqual(draft.displaySourceRevision.entries.count, 0)
        XCTAssertTrue(draft.displaySourceRevision.validationIssues().isEmpty)
        XCTAssertEqual(
            draft.compiled.candidate.contract.initialCausalStrategyAuthority,
            draft.displayCausalStrategyAuthority
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.initialExecutionPlan,
            draft.displayExecutionPlan
        )
        XCTAssertTrue(
            draft.compiled.candidate.contract.hasValidInitialExecutionAuthority
        )
        XCTAssertEqual(
            draft.displayCausalStrategyAuthority.descriptor.baselineRevision,
            draft.displaySourceRevision.sourceRevision
        )
        XCTAssertEqual(
            draft.displayExecutionPlan.nodes.first?.strategyFingerprint,
            draft.displayCausalStrategyAuthority.descriptor.fingerprint
        )
        XCTAssertEqual(
            draft.displayExecutionPlan.nodes.first?.mutationScope.maximumChangedFiles,
            fixture.executionBudgets.mutation.maximumChangedFiles
        )
        XCTAssertNotNil(draft.compiled.candidate.workspaceSourceBinding)
        XCTAssertNotNil(draft.compiled.candidate.durationAcceptanceSourceBinding)
        XCTAssertNotNil(draft.compiled.candidate.executionProfileSourceBinding)
        XCTAssertNotNil(draft.compiled.candidate.executionBudgetSourceBinding)
        XCTAssertNotNil(draft.compiled.candidate.sourceRevisionSourceBinding)
        XCTAssertNotNil(
            draft.compiled.candidate.causalStrategyAuthoritySourceBinding
        )
        XCTAssertNotNil(draft.compiled.candidate.executionPlanSourceBinding)
        XCTAssertEqual(
            draft.compiled.candidate.evidenceRecipes.first?.verifierKind,
            .deterministic
        )
        XCTAssertEqual(
            draft.compiled.candidate.evidenceRecipes.first?.executableProbe,
            fixture.verificationProbe
        )

        let encoded = try JSONEncoder.loopForge.encode(draft.compiled.candidate)
        let decoded = try JSONDecoder.loopForge.decode(
            TaskContractCompilationCandidate.self,
            from: encoded
        )
        switch TaskContractCompiler.compile(decoded) {
        case .success(let replayed):
            XCTAssertEqual(replayed.candidateDigest, draft.compiled.candidateDigest)
        case .failure(let failure):
            XCTFail("native candidate must replay exactly: \(failure.issues)")
        }
    }

    func testDurationAndWorkspaceAuthorityCannotLoseExplicitBindings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let duration = DurationAcceptancePolicy(
            requiredSeconds: 3_600,
            eligibleClass: .acceptedExecution
        )
        let draft = try prepared(fixture.request(duration: duration))
        var candidate = draft.compiled.candidate
        candidate.durationAcceptanceSourceBinding = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .durationAcceptanceBindingMismatch
        )

        candidate = draft.compiled.candidate
        if let workspaceSourceID = candidate.workspaceSourceBinding?
            .sourceSpans.first?.sourceID,
           let index = candidate.sources.firstIndex(where: {
               $0.id == workspaceSourceID
           }) {
            candidate.sources[index].authority = .modelProposal
        }
        let issues = compileIssues(candidate)
        XCTAssertContainsIssue(
            issues,
            .explicitClaimLacksUserAuthority("workspace-binding")
        )
    }

    @MainActor
    func testConfirmationUsesDisplayedDigestExactUserAndIsSingleUseInProcess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let draft = try prepared(fixture.request(duration: nil))
        let issuer = NativeTaskContractConfirmationIssuer()

        XCTAssertEqual(
            failure(issuer.confirmFromNativeUserAction(
                draft,
                displayedCandidateDigest: ContentDigest("stale-display"),
                userActor: fixture.user,
                confirmedAt: Date(timeIntervalSince1970: 3)
            )),
            .displayedCandidateChanged
        )
        var wrongUser = fixture.user
        wrongUser.lineageDigest = ContentDigest("wrong-lineage")
        XCTAssertEqual(
            failure(issuer.confirmFromNativeUserAction(
                draft,
                displayedCandidateDigest: draft.compiled.candidateDigest,
                userActor: wrongUser,
                confirmedAt: Date(timeIntervalSince1970: 3)
            )),
            .userIdentityMismatch
        )

        let ratified: RatifiedTaskContract
        switch issuer.confirmFromNativeUserAction(
            draft,
            displayedCandidateDigest: draft.compiled.candidateDigest,
            userActor: fixture.user,
            confirmedAt: Date(timeIntervalSince1970: 3)
        ) {
        case .success(let value): ratified = value
        case .failure(let error):
            XCTFail("confirmation failed: \(error)")
            return
        }
        var expectedDurableContract = draft.compiled.candidate.contract
        expectedDurableContract.requirementEvidenceRecipes =
            draft.compiled.candidate.evidenceRecipes
        XCTAssertEqual(ratified.contract, expectedDurableContract)
        XCTAssertEqual(
            ratified.receipt.candidateDigest,
            draft.compiled.candidateDigest
        )
        XCTAssertEqual(
            failure(issuer.confirmFromNativeUserAction(
                draft,
                displayedCandidateDigest: draft.compiled.candidateDigest,
                userActor: fixture.user,
                confirmedAt: Date(timeIntervalSince1970: 4)
            )),
            .alreadyConfirmed
        )
    }

    @MainActor
    func testConfirmationRejectsWorkspaceChangeAfterDisplayedCapture() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("before".utf8).write(
            to: fixture.workspace.appendingPathComponent("source.txt")
        )
        let draft = try prepared(fixture.request(duration: nil))
        try Data("after".utf8).write(
            to: fixture.workspace.appendingPathComponent("source.txt")
        )

        XCTAssertEqual(
            failure(NativeTaskContractConfirmationIssuer()
                .confirmFromNativeUserAction(
                    draft,
                    displayedCandidateDigest: draft.compiled.candidateDigest,
                    userActor: fixture.user,
                    confirmedAt: Date(timeIntervalSince1970: 3)
                )),
            .displayedSourceRevisionChanged
        )
    }

    func testNativeAuthoringRejectsNoncanonicalOrUnselectedAuthority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var request = fixture.request(duration: nil)
        request.writableScopes = ["../escape"]
        XCTAssertEqual(authoringFailure(request), .invalidScope)

        request = fixture.request(duration: nil)
        request.readableScopes = []
        XCTAssertEqual(authoringFailure(request), .invalidScope)
    }

    func testAcceptedUserAmendmentIsExplicitButModelProposalIsNot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var request = fixture.request(duration: nil)
        request.objectiveSourceAuthority = .acceptedUserAmendment
        let accepted = try prepared(request)
        let objectiveSource = try XCTUnwrap(
            accepted.compiled.candidate.sources.first {
                $0.id == accepted.compiled.candidate.initialObjectiveSourceID
            }
        )
        XCTAssertEqual(objectiveSource.authority, .acceptedUserAmendment)

        request.objectiveSourceAuthority = .modelProposal
        XCTAssertEqual(authoringFailure(request), .invalidObjective)
    }

    func testExecutionProfileCannotLoseExplicitBindingOrGainAuthority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let draft = try prepared(fixture.request(duration: nil))

        var candidate = draft.compiled.candidate
        candidate.executionProfileSourceBinding = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .executionProfileBindingMismatch
        )

        candidate = draft.compiled.candidate
        candidate.contract.executionProfile?.worker.modelID = "tampered-model"
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .executionProfileSourceMismatch
        )

        candidate = draft.compiled.candidate
        candidate.contract.executionProfile?.worker.executableContentDigest =
            ContentDigest(String(repeating: "c", count: 64))
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .executionProfileSourceMismatch
        )

        var request = fixture.request(duration: nil)
        request.executionProfile.worker.executableContentDigest = ContentDigest("not-sha256")
        guard case .invalidExecutionProfile(let digestIssues) = authoringFailure(request) else {
            return XCTFail("a malformed executable digest must fail native authoring")
        }
        XCTAssertTrue(digestIssues.contains { $0.contains("executable content digest") })

        request = fixture.request(duration: nil)
        request.executionProfile.worker.sandbox = .fullAccess
        XCTAssertEqual(
            authoringFailure(request),
            .unsupportedExecutionAuthority(
                "Full Access requires a trusted native capability grant issuer."
            )
        )
    }

    func testExecutionBudgetsCannotLoseExplicitBindingOrBeExpandedAfterDisplay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let draft = try prepared(fixture.request(duration: nil))

        var candidate = draft.compiled.candidate
        candidate.executionBudgetSourceBinding = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .executionBudgetBindingMismatch
        )

        candidate = draft.compiled.candidate
        candidate.contract.executionBudgets?.mutation.maximumChangedFiles += 1
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .executionBudgetSourceMismatch
        )

        var request = fixture.request(duration: nil)
        request.executionBudgets = nil
        guard case .invalidExecutionBudgets = authoringFailure(request) else {
            return XCTFail("missing budgets must fail before confirmation")
        }

        request = fixture.request(duration: nil)
        request.executionBudgets?.convergence.maximumEquivalentFailures = 4
        guard case .invalidExecutionBudgets(let issues) = authoringFailure(request) else {
            return XCTFail("expanded equivalent-failure budget must fail")
        }
        XCTAssertTrue(issues.contains {
            $0.contains("maximumEquivalentFailures")
        })
    }

    func testSourceRevisionCannotLoseObservedBindingOrChangeAfterDisplay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("source".utf8).write(
            to: fixture.workspace.appendingPathComponent("source.txt")
        )
        let draft = try prepared(fixture.request(duration: nil))
        XCTAssertEqual(
            draft.displaySourceRevision.entries.map(\.relativePath),
            ["source.txt"]
        )

        var candidate = draft.compiled.candidate
        candidate.sourceRevisionSourceBinding = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .sourceRevisionBindingMismatch
        )

        candidate = draft.compiled.candidate
        candidate.contract.sourceRevision?.entries[0].contentDigest =
            ContentDigest(String(repeating: "0", count: 64))
        let issues = compileIssues(candidate)
        XCTAssertTrue(issues.contains {
            if case .invalidContract(let message) = $0 {
                return message.contains("source-revision digest mismatch")
            }
            return false
        })
        XCTAssertContainsIssue(issues, .sourceRevisionSourceMismatch)

        candidate = draft.compiled.candidate
        if let sourceID = candidate.sourceRevisionSourceBinding?
            .sourceSpans.first?.sourceID,
           let index = candidate.sources.firstIndex(where: { $0.id == sourceID }) {
            candidate.sources[index].authority = .user
        }
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .sourceRevisionSourceMismatch
        )
    }

    func testNativeSourceRevisionPolicyParserIsCanonicalAndAmbiguityFailsClosed() throws {
        XCTAssertEqual(
            NativeSourceRevisionCapturePolicyParser
                .parseExcludedDirectoryNames("dist, Generated\n.cache"),
            [".cache", "Generated", "dist"]
        )

        let fixture = try Fixture()
        defer { fixture.remove() }
        var request = fixture.request(duration: nil)
        request.sourceRevisionCapturePolicy =
            WorkspaceCandidatePostimageCapturePolicy(
                excludedDirectoryNames:
                    NativeSourceRevisionCapturePolicyParser
                        .parseExcludedDirectoryNames("dist, dist"),
                limits: NativeTaskContractAuthoringRequest
                    .defaultSourceRevisionCapturePolicy.limits
            )
        guard case .invalidSourceRevisionCapturePolicy(let duplicateIssues) =
                authoringFailure(request) else {
            return XCTFail("duplicate source exclusions must fail before capture")
        }
        XCTAssertTrue(duplicateIssues.contains {
            $0.contains("unique canonical components")
        })

        request = fixture.request(duration: nil)
        request.sourceRevisionCapturePolicy =
            WorkspaceCandidatePostimageCapturePolicy(
                excludedDirectoryNames: ["dist/generated"],
                limits: NativeTaskContractAuthoringRequest
                    .defaultSourceRevisionCapturePolicy.limits
            )
        guard case .invalidSourceRevisionCapturePolicy(let pathIssues) =
                authoringFailure(request) else {
            return XCTFail("path-shaped exclusions must fail before capture")
        }
        XCTAssertTrue(pathIssues.contains {
            $0.contains("unique canonical components")
        })
    }

    func testNativeExactImplementationAuthorityIsUserBoundAndFailsClosed()
        throws
    {
        XCTAssertEqual(
            NativeExactImplementationIdentityParser.parse(
                "opaque-implementation-b, opaque-implementation-a\nopaque-implementation-b"
            ),
            [
                "opaque-implementation-a",
                "opaque-implementation-b",
                "opaque-implementation-b"
            ]
        )

        let fixture = try Fixture()
        defer { fixture.remove() }
        var request = fixture.request(duration: nil)
        request.permittedImplementationIDs =
            NativeExactImplementationIdentityParser.parse(
                "opaque-implementation-b, opaque-implementation-a"
            )
        let draft = try prepared(request)
        XCTAssertEqual(
            draft.displayPermittedImplementationIDs,
            ["opaque-implementation-a", "opaque-implementation-b"]
        )
        let constraint = try XCTUnwrap(
            draft.compiled.candidate.contract.constraints.first(where: {
                $0.kind == .prohibitSubstitution
            })
        )
        XCTAssertEqual(
            constraint.substitutionRule,
            ExactImplementationConstraint(
                requirementIDs: Set(
                    draft.compiled.candidate.contract.requirements.map(\.id)
                ),
                permittedImplementationIDs: [
                    "opaque-implementation-a",
                    "opaque-implementation-b"
                ]
            )
        )
        let binding = try XCTUnwrap(
            draft.compiled.candidate.constraintBindings.first(where: {
                $0.constraintID == constraint.id
            })
        )
        XCTAssertEqual(binding.epistemicState, .explicit)
        let sourceID = try XCTUnwrap(binding.sourceSpans.first?.sourceID)
        let source = try XCTUnwrap(
            draft.compiled.candidate.sources.first(where: {
                $0.id == sourceID
            })
        )
        XCTAssertEqual(source.authority, .user)
        XCTAssertEqual(
            source.exactUTF8,
            Data("opaque-implementation-a\u{1f}opaque-implementation-b".utf8)
        )

        var changed = fixture.request(duration: nil)
        changed.permittedImplementationIDs = ["opaque-implementation-c"]
        XCTAssertNotEqual(
            try prepared(changed).compiled.candidateDigest,
            draft.compiled.candidateDigest
        )

        var duplicate = fixture.request(duration: nil)
        duplicate.permittedImplementationIDs = ["opaque-a", "opaque-a"]
        guard case .invalidExactImplementationIDs(let duplicateIssues) =
                authoringFailure(duplicate) else {
            return XCTFail("duplicate exact identities must fail before capture")
        }
        XCTAssertTrue(duplicateIssues.contains {
            $0.contains("must be unique")
        })

        var ambiguous = fixture.request(duration: nil)
        ambiguous.permittedImplementationIDs = [" opaque-a"]
        guard case .invalidExactImplementationIDs(let whitespaceIssues) =
                authoringFailure(ambiguous) else {
            return XCTFail("whitespace-shaped identity must fail before capture")
        }
        XCTAssertTrue(whitespaceIssues.contains {
            $0.contains("already trimmed")
        })
    }

    @MainActor
    func testExplicitSourceRevisionPolicyExcludesGeneratedTreeAndIsConfirmed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("source".utf8).write(
            to: fixture.workspace.appendingPathComponent("source.txt")
        )
        let generated = fixture.workspace.appendingPathComponent(
            "dist/runtime",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: generated,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: generated.appendingPathComponent("runtime.dylib").path,
            withDestinationPath: "../../source.txt"
        )

        var request = fixture.request(duration: nil)
        var excluded = NativeTaskContractAuthoringRequest
            .defaultSourceRevisionCapturePolicy.excludedDirectoryNames
        excluded.append("dist")
        request.sourceRevisionCapturePolicy =
            WorkspaceCandidatePostimageCapturePolicy(
                excludedDirectoryNames: excluded.sorted(),
                limits: NativeTaskContractAuthoringRequest
                    .defaultSourceRevisionCapturePolicy.limits
            )
        let draft = try prepared(request)
        XCTAssertEqual(
            draft.displaySourceRevision.entries.map(\.relativePath),
            ["source.txt"]
        )
        XCTAssertTrue(
            draft.displaySourceRevision.excludedDirectoryNames.contains("dist")
        )
        XCTAssertEqual(
            draft.displaySourceRevision.capturePolicyDigest,
            request.sourceRevisionCapturePolicy.capturePolicyDigest
        )

        switch NativeTaskContractConfirmationIssuer()
            .confirmFromNativeUserAction(
                draft,
                displayedCandidateDigest: draft.compiled.candidateDigest,
                userActor: fixture.user,
                confirmedAt: Date(timeIntervalSince1970: 3)
            ) {
        case .success(let ratified):
            XCTAssertEqual(
                ratified.contract.sourceRevision,
                draft.displaySourceRevision
            )
        case .failure(let error):
            XCTFail("explicit source policy should recapture exactly: \(error)")
        }
    }

    func testStrategyAndPlanCannotLoseExplicitBindingOrDriftFromRevision() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let draft = try prepared(fixture.request(duration: nil))

        var candidate = draft.compiled.candidate
        candidate.causalStrategyAuthoritySourceBinding = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .causalStrategyAuthorityBindingMismatch
        )

        candidate = draft.compiled.candidate
        candidate.executionPlanSourceBinding = nil
        XCTAssertContainsIssue(
            compileIssues(candidate),
            .executionPlanBindingMismatch
        )

        candidate = draft.compiled.candidate
        candidate.contract.initialCausalStrategyAuthority?.descriptor
            .falsificationPredicateIDs = ["renamed-unbound-falsifier"]
        let strategyIssues = compileIssues(candidate)
        XCTAssertContainsIssue(
            strategyIssues,
            .causalStrategyAuthoritySourceMismatch
        )
        XCTAssertTrue(strategyIssues.contains {
            if case .invalidContract(let message) = $0 {
                return message.contains("falsification predicates")
            }
            return false
        })

        candidate = draft.compiled.candidate
        candidate.contract.initialExecutionPlan?.nodes[0]
            .mutationScope.maximumChangedFiles += 1
        let planIssues = compileIssues(candidate)
        XCTAssertContainsIssue(planIssues, .executionPlanSourceMismatch)
        XCTAssertTrue(planIssues.contains {
            if case .invalidContract(let message) = $0 {
                return message.contains("mutation scope")
                    || message.contains("mutation surface")
            }
            return false
        })

        candidate = draft.compiled.candidate
        if let sourceID = candidate.causalStrategyAuthoritySourceBinding?
            .sourceSpans.first?.sourceID,
           let index = candidate.sources.firstIndex(where: { $0.id == sourceID }) {
            candidate.sources[index].authority = .modelProposal
        }
        let authorityIssues = compileIssues(candidate)
        XCTAssertContainsIssue(
            authorityIssues,
            .explicitClaimLacksUserAuthority("causal-strategy-authority")
        )
        XCTAssertContainsIssue(
            authorityIssues,
            .causalStrategyAuthoritySourceMismatch
        )

        candidate = draft.compiled.candidate
        var duplicatePrediction = try XCTUnwrap(
            candidate.contract.initialCausalStrategyAuthority?
                .expectedObservations.first
        )
        duplicatePrediction.id = "duplicate-prediction"
        candidate.contract.initialCausalStrategyAuthority?
            .expectedObservations.append(duplicatePrediction)
        candidate.contract.initialCausalStrategyAuthority?.descriptor
            .expectedObservationIDs.insert(duplicatePrediction.id)
        XCTAssertTrue(compileIssues(candidate).contains {
            if case .invalidContract(let message) = $0 {
                return message.contains("exactly one prediction")
            }
            return false
        })

        candidate = draft.compiled.candidate
        var duplicateFalsifier = try XCTUnwrap(
            candidate.contract.initialCausalStrategyAuthority?
                .falsificationPredicates.first
        )
        duplicateFalsifier.id = "duplicate-falsifier"
        candidate.contract.initialCausalStrategyAuthority?
            .falsificationPredicates.append(duplicateFalsifier)
        candidate.contract.initialCausalStrategyAuthority?.descriptor
            .falsificationPredicateIDs.insert(duplicateFalsifier.id)
        XCTAssertTrue(compileIssues(candidate).contains {
            if case .invalidContract(let message) = $0 {
                return message.contains("exactly one falsifier")
            }
            return false
        })

        candidate = draft.compiled.candidate
        let optionalRequirementID = RequirementID("optional-unconfirmed")
        candidate.contract.requirements.append(RequirementContract(
            id: optionalRequirementID,
            statement: "Optional unconfirmed work",
            mandatory: false,
            evidenceRecipeIDs: []
        ))
        candidate.contract.initialExecutionPlan?.nodes.append(
            KernelNodeContract(
                id: KernelNodeID("optional-node"),
                requirementIDs: [optionalRequirementID],
                objective: "Optional work",
                dependencies: [],
                mutationScope: KernelMutationScope(
                    writablePaths: [],
                    maximumChangedFiles: 0,
                    maximumChangedBytes: 0
                ),
                capabilityIDs: [],
                strategyFingerprint: draft.displayCausalStrategyAuthority
                    .descriptor.fingerprint
            )
        )
        XCTAssertTrue(compileIssues(candidate).contains {
            if case .invalidContract(let message) = $0 {
                return message.contains("confirmed strategy requirements")
            }
            return false
        })
    }

    func testReviewerMustRemainIndependentReadOnlyAndOffline() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var request = fixture.request(duration: nil)
        request.executionProfile.independentReviewer.networkPolicy = .enabled
        let failure = try XCTUnwrap(authoringFailure(request))
        guard case .invalidExecutionProfile(let issues) = failure else {
            return XCTFail("unexpected failure: \(failure)")
        }
        XCTAssertTrue(issues.contains {
            $0.contains("independent reviewer") || $0.contains("network access")
        })
    }

    func testWorkerNetworkAuthorityIsExplicitExactAndNonDormant() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let offlineDraft = try prepared(fixture.request(duration: nil))
        XCTAssertTrue(
            offlineDraft.compiled.candidate.contract.authorityCeiling
                .capabilityIDs.isEmpty
        )

        var authorized = fixture.request(duration: nil)
        authorized.executionProfile.worker.networkPolicy = .enabled
        authorized.authorityCapabilityIDs = [
            KernelExecutionProfile.networkCapabilityID
        ]
        let networkDraft = try prepared(authorized)
        XCTAssertEqual(
            networkDraft.displayAuthorityCapabilityIDs,
            [KernelExecutionProfile.networkCapabilityID]
        )
        XCTAssertEqual(
            networkDraft.compiled.candidate.contract.authorityCeiling
                .capabilityIDs,
            [KernelExecutionProfile.networkCapabilityID]
        )
        XCTAssertEqual(
            Set(networkDraft.compiled.capabilityGrantReceiptDigests.keys),
            [KernelExecutionProfile.networkCapabilityID]
        )
        XCTAssertFalse(
            networkDraft.compiled.capabilityGrantReceiptDigests[
                KernelExecutionProfile.networkCapabilityID
            ]?.rawValue.isEmpty ?? true
        )
        XCTAssertEqual(
            networkDraft.displayExecutionPlan.nodes.first?.capabilityIDs,
            [KernelExecutionProfile.networkCapabilityID]
        )
        XCTAssertEqual(
            networkDraft.displayCausalStrategyAuthority.descriptor
                .capabilityRoute,
            [KernelExecutionProfile.networkCapabilityID]
        )
        XCTAssertNotEqual(
            networkDraft.compiled.candidateDigest,
            offlineDraft.compiled.candidateDigest
        )
        let capabilitySource = try XCTUnwrap(
            networkDraft.compiled.candidate.sources.first(where: {
                $0.id.rawValue.hasPrefix("native-capabilities-")
            })
        )
        XCTAssertEqual(capabilitySource.authority, .user)
        XCTAssertEqual(
            capabilitySource.exactUTF8,
            Data(KernelExecutionProfile.networkCapabilityID.utf8)
        )

        var missingGrant = fixture.request(duration: nil)
        missingGrant.executionProfile.worker.networkPolicy = .enabled
        guard case .invalidAuthorityCapabilities(let missingIssues) =
            authoringFailure(missingGrant) else {
            return XCTFail("expected missing network authority to reject")
        }
        XCTAssertTrue(missingIssues.contains {
            $0.contains(KernelExecutionProfile.networkCapabilityID)
        })

        var dormantGrant = fixture.request(duration: nil)
        dormantGrant.authorityCapabilityIDs = [
            KernelExecutionProfile.networkCapabilityID
        ]
        guard case .invalidAuthorityCapabilities(let dormantIssues) =
            authoringFailure(dormantGrant) else {
            return XCTFail("expected dormant network authority to reject")
        }
        XCTAssertTrue(dormantIssues.contains { $0.contains("dormant") })

        var unknownGrant = fixture.request(duration: nil)
        unknownGrant.authorityCapabilityIDs = ["kernel.unratified"]
        guard case .invalidAuthorityCapabilities(let unknownIssues) =
            authoringFailure(unknownGrant) else {
            return XCTFail("expected unknown capability to reject")
        }
        XCTAssertEqual(
            unknownIssues,
            ["unsupported native authority capability: kernel.unratified"]
        )
    }

    func testExecutableVerificationProbeIsMandatoryAndFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var request = fixture.request(duration: nil)
        request.verificationProbe = nil
        XCTAssertEqual(
            authoringFailure(request),
            .invalidVerificationProbe([
                "An exact executable verification probe must be selected before confirmation."
            ])
        )

        request = fixture.request(duration: nil)
        request.verificationProbe?.resultMappings[0].outcome = .rejected
        guard case .invalidVerificationProbe(let issues) = authoringFailure(request) else {
            return XCTFail("expected fail-closed probe validation")
        }
        XCTAssertTrue(issues.contains { $0.contains("accepted result") })

        request = fixture.request(duration: nil)
        request.verificationProbe?.parser.format = nil
        request.verificationProbe?.parser.contentDigest = ContentDigest(
            String(repeating: "f", count: 64)
        )
        guard case .invalidVerificationProbe(let parserIssues) =
                authoringFailure(request) else {
            return XCTFail("expected descriptive parser rejection")
        }
        XCTAssertTrue(parserIssues.contains {
            $0.contains("supported canonical result grammar")
        })

        request = fixture.request(duration: nil)
        request.verificationProbe?.schemaVersion = 1
        request.verificationProbe?.parser.format = nil
        request.verificationProbe?.parser.contentDigest = ContentDigest(
            String(repeating: "f", count: 64)
        )
        XCTAssertEqual(
            authoringFailure(request),
            .invalidVerificationProbe([
                "New native authoring requires verification probe schemaVersion 2."
            ])
        )
    }

    func testLegacyProfileWithoutExecutableDigestDecodesButCannotValidate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let encoded = try JSONEncoder().encode(fixture.executionProfile.worker)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "executableContentDigest")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            KernelAgentExecutionProfile.self,
            from: legacyData
        )
        XCTAssertEqual(decoded.executableContentDigest, ContentDigest(""))

        var profile = fixture.executionProfile
        profile.worker = decoded
        XCTAssertTrue(
            profile.validationIssues(authorityCeiling: .readOnly).contains {
                $0.contains("executable content digest")
            }
        )
    }

    private struct Fixture {
        let container: URL
        let workspace: URL
        let objective = "Preserve the exact visual baseline and close the declared outcome."
        let workspaceID = WorkspaceID("native-workspace")
        let user = ActorIdentity(
            id: ActorID("native-user"),
            role: "user",
            lineageDigest: ContentDigest("native-user-lineage")
        )
        let executionProfile = KernelExecutionProfile(
            schemaVersion: 1,
            worker: KernelAgentExecutionProfile(
                provider: .codex,
                providerReference: "official-codex-session",
                executableContentDigest: ContentDigest(String(repeating: "a", count: 64)),
                modelID: "gpt-worker",
                reasoningEffort: "high",
                sandbox: .workspaceOnly,
                networkPolicy: .disabled,
                pluginPolicy: .disabled,
                environmentPolicy: .minimalKernelAllowlist
            ),
            independentReviewer: KernelAgentExecutionProfile(
                provider: .local,
                providerReference: "review-profile",
                executableContentDigest: ContentDigest(String(repeating: "b", count: 64)),
                modelID: "review-model",
                reasoningEffort: nil,
                sandbox: .readOnly,
                networkPolicy: .disabled,
                pluginPolicy: .disabled,
                environmentPolicy: .minimalKernelAllowlist
            ),
            requiresDistinctActorLineage: true
        )
        let executionBudgets = KernelExecutionBudgetPolicy(
            mutation: KernelMutationBudget(
                maximumChangedFiles: 12,
                maximumChangedBytes: 262_144
            ),
            convergence: ConvergenceBudget(
                maximumAttempts: 3,
                maximumEquivalentFailures: 3,
                maximumStrategies: 2,
                maximumPlanExpansions: 1,
                maximumMutationCost: 262_144,
                maximumVerificationCost: 12,
                maximumDamageEvents: 0,
                maximumExternalEffects: 0
            )
        )

        init() throws {
            container = FileManager.default.temporaryDirectory.appendingPathComponent(
                "LoopForgeNativeContract-\(UUID().uuidString)",
                isDirectory: true
            )
            workspace = container.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workspace,
                withIntermediateDirectories: true
            )
        }

        func request(
            duration: DurationAcceptancePolicy?
        ) -> NativeTaskContractAuthoringRequest {
            NativeTaskContractAuthoringRequest(
                exactObjective: objective,
                workspaceID: workspaceID,
                workspaceRoot: workspace,
                readableScopes: ["."],
                writableScopes: ["."],
                acceptedDuration: duration,
                executionProfile: executionProfile,
                verificationProbe: verificationProbe,
                executionBudgets: executionBudgets,
                userActor: user,
                recordedAt: Date(timeIntervalSince1970: 2),
                authoringNonce: ContentDigest("native-authoring-nonce")
            )
        }

        var verificationProbe: RequirementVerificationExecutableProbe {
            RequirementVerificationExecutableProbe(
                schemaVersion: 2,
                transport: .localDirectProcess,
                executableContentDigest: ContentDigest(
                    String(repeating: "c", count: 64)
                ),
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
                environmentIdentityDigest: ContentDigest(
                    String(repeating: "d", count: 64)
                ),
                captureIdentityDigest: ContentDigest(
                    String(repeating: "e", count: 64)
                ),
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
        }

        func remove() {
            try? FileManager.default.removeItem(at: container)
        }
    }

    private func prepared(
        _ request: NativeTaskContractAuthoringRequest
    ) throws -> NativeTaskContractConfirmationDraft {
        switch NativeTaskContractAuthor.prepare(request) {
        case .success(let draft): return draft
        case .failure(let error):
            XCTFail("unexpected authoring failure: \(error)")
            throw error
        }
    }

    private func compileIssues(
        _ candidate: TaskContractCompilationCandidate
    ) -> [TaskContractCompilationIssue] {
        switch TaskContractCompiler.compile(candidate) {
        case .success:
            XCTFail("expected compilation failure")
            return []
        case .failure(let failure): return failure.issues
        }
    }

    private func authoringFailure(
        _ request: NativeTaskContractAuthoringRequest
    ) -> NativeTaskContractAuthoringError? {
        switch NativeTaskContractAuthor.prepare(request) {
        case .success:
            XCTFail("expected authoring failure")
            return nil
        case .failure(let error): return error
        }
    }

    @MainActor
    private func failure(
        _ result: Result<RatifiedTaskContract, NativeTaskContractConfirmationError>
    ) -> NativeTaskContractConfirmationError? {
        switch result {
        case .success:
            XCTFail("expected confirmation failure")
            return nil
        case .failure(let error): return error
        }
    }

    private func XCTAssertContainsIssue(
        _ issues: [TaskContractCompilationIssue],
        _ expected: TaskContractCompilationIssue,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(issues.contains(expected), "missing \(expected) in \(issues)", file: file, line: line)
    }
}
