import Foundation
import XCTest
@testable import LoopForge

final class ConvergenceGovernorTests: XCTestCase {
    func testReceiptNativeDiagnosisExposesBudgetCostEvidenceRetirementAndReplacement() throws {
        var governor = makeGovernor()
        let first = strategy()
        var firstRequest = request("diagnostic-attempt-1", first)
        firstRequest.mutationCost = 7
        firstRequest.verificationCost = 5
        firstRequest.externalEffects = 1
        XCTAssertEqual(governor.admit(firstRequest), .admitted(first.fingerprint))

        let previous = ConvergenceProgressVector(
            acceptedRequirements: [],
            unresolvedRequirements: [RequirementID("r")],
            blockerDigests: [digest("blocker")],
            acceptedEvidence: [],
            unresolvedVerifierFailures: ["oracle-red"],
            acceptedQualityDimensions: [],
            unresolvedClaims: ["claim"],
            protectedInvariantRegressions: []
        )
        let current = ConvergenceProgressVector(
            acceptedRequirements: [RequirementID("r")],
            unresolvedRequirements: [],
            blockerDigests: [],
            acceptedEvidence: [ReceiptID("evidence-receipt")],
            unresolvedVerifierFailures: [],
            acceptedQualityDimensions: ["typography"],
            unresolvedClaims: [],
            protectedInvariantRegressions: []
        )
        XCTAssertEqual(
            governor.recordProgress(
                strategy: first.fingerprint,
                previous: previous,
                current: current
            ),
            true
        )

        XCTAssertEqual(
            governor.admit(request("diagnostic-attempt-2", first)),
            .admitted(first.fingerprint)
        )
        let blocker = failure(.deterministicImplementationFailure)
        XCTAssertEqual(
            governor.recordFailure(
                strategy: first.fingerprint,
                failure: blocker,
                lessonDigest: digest("diagnostic-lesson")
            ),
            .retireAndRequireCausallyDistinctRepair(
                remainingEquivalentFailures: 2,
                failureDigest: blocker.digest
            )
        )

        let replacement = strategy(
            action: "repair-layout-with-new-boundary",
            observations: ["replacement-observation"],
            lessons: [digest("diagnostic-lesson")]
        )
        XCTAssertTrue(governor.authorizeReplacement(
            receiptID: ReceiptID("diagnostic-replacement"),
            predecessor: first.fingerprint,
            replacement: replacement,
            failures: [blocker],
            delta: delta(
                axis: .action,
                failure: blocker,
                observation: "replacement-observation",
                lesson: "diagnostic-lesson"
            )
        ))

        let projection = governor.diagnosticProjection(sourceSequence: 42)
        XCTAssertEqual(
            projection.authority,
            ConvergenceDiagnosticProjection.authority
        )
        XCTAssertEqual(projection.sourceSequence, 42)
        XCTAssertFalse(projection.projectionDigest.rawValue.isEmpty)
        XCTAssertEqual(projection.budget.consumed.attempts, 2)
        XCTAssertEqual(projection.budget.consumed.mutationCost, 8)
        XCTAssertEqual(projection.budget.remaining.attempts, 6)

        let strategyDiagnosis = try XCTUnwrap(projection.strategies.first)
        XCTAssertEqual(strategyDiagnosis.fingerprint, first.fingerprint)
        XCTAssertEqual(strategyDiagnosis.lifecycle, .retired)
        XCTAssertEqual(strategyDiagnosis.mutationCostConsumed, 8)
        XCTAssertEqual(strategyDiagnosis.verificationCostConsumed, 6)
        XCTAssertEqual(strategyDiagnosis.externalEffectsConsumed, 1)
        XCTAssertEqual(strategyDiagnosis.lessonDigest, digest("diagnostic-lesson"))
        XCTAssertEqual(
            strategyDiagnosis.retirementActionCode,
            "retire-and-require-causally-distinct-repair"
        )
        XCTAssertEqual(strategyDiagnosis.lastProgressAccepted, true)
        XCTAssertEqual(
            strategyDiagnosis.lastProgressDelta?.acceptedEvidenceReceiptIDsAdded,
            [ReceiptID("evidence-receipt")]
        )
        XCTAssertEqual(
            strategyDiagnosis.lastProgressDelta?.acceptedRequirementIDsAdded,
            [RequirementID("r")]
        )
        XCTAssertEqual(
            strategyDiagnosis.lastProgressDelta?.blockerDigestsResolved,
            [digest("blocker")]
        )

        let replacementDiagnosis = try XCTUnwrap(
            projection.replacementAuthorizations.first
        )
        XCTAssertEqual(replacementDiagnosis.changedAxes, [.action])
        XCTAssertEqual(replacementDiagnosis.consumed, false)
        XCTAssertEqual(replacementDiagnosis.failureDigests, [blocker.digest])

        let restored = try JSONDecoder().decode(
            ConvergenceGovernor.self,
            from: JSONEncoder().encode(governor)
        )
        XCTAssertEqual(
            restored.diagnosticProjection(sourceSequence: 42),
            projection
        )
        XCTAssertNotEqual(
            restored.diagnosticProjection(sourceSequence: 43).projectionDigest,
            projection.projectionDigest
        )
    }

    func testFingerprintIsStableAcrossSetOrderingAndExcludesAttemptIdentity() {
        let first = strategy(capabilities: ["shell", "camera"], evidence: ["baseline", "native"])
        let second = strategy(capabilities: ["camera", "shell"], evidence: ["native", "baseline"])

        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first, second)
    }

    func testFingerprintExcludesRenamableAttemptAndReplacementMetadata() {
        let first = strategy(
            observations: ["initial-observation"],
            lessons: []
        )
        var renamed = strategy(
            observations: ["same-outcome-under-new-label"],
            lessons: [digest("newly-attached-lesson")]
        )
        renamed.falsificationPredicateIDs = ["same-failure-under-new-label"]

        XCTAssertNotEqual(first, renamed)
        XCTAssertEqual(
            first.fingerprint,
            renamed.fingerprint,
            "Prediction, falsification, and lesson receipt labels constrain attempts but cannot mint causal strategy identity."
        )

        var governor = makeGovernor()
        XCTAssertEqual(
            governor.admit(request("original-attempt", first)),
            .admitted(first.fingerprint)
        )
        XCTAssertEqual(
            governor.admit(request("renamed-metadata-attempt", renamed)),
            .rejected(.equivalentStrategyAlreadyActive(first.fingerprint))
        )
        XCTAssertEqual(governor.consumption.attempts, 1)
        XCTAssertEqual(governor.consumption.strategies, 1)
    }

    func testEquivalentAttemptCannotRunConcurrently() {
        var governor = makeGovernor()
        let descriptor = strategy()
        XCTAssertEqual(governor.admit(request("attempt-1", descriptor)), .admitted(descriptor.fingerprint))
        XCTAssertEqual(
            governor.admit(request("renamed-attempt", descriptor)),
            .rejected(.equivalentStrategyAlreadyActive(descriptor.fingerprint))
        )
        XCTAssertEqual(governor.consumption.attempts, 1)
    }

    func testThreeEquivalentDeterministicFailuresRetireAcrossRenamedAttempts() {
        var governor = makeGovernor()
        let first = strategy()
        let blocker = failure(.deterministicImplementationFailure)
        XCTAssertEqual(governor.admit(request("attempt-1", first)), .admitted(first.fingerprint))
        XCTAssertEqual(
            governor.recordFailure(strategy: first.fingerprint, failure: blocker, lessonDigest: digest("lesson-1")),
            .retireAndRequireCausallyDistinctRepair(
                remainingEquivalentFailures: 2,
                failureDigest: blocker.digest
            )
        )
        XCTAssertEqual(
            governor.admit(request("renamed-attempt", first)),
            .rejected(.strategyRetired(first.fingerprint))
        )

        let second = strategy(
            action: "repair-layout-b",
            observations: ["oracle-passes-b"],
            lessons: [digest("lesson-1")]
        )
        XCTAssertEqual(
            governor.admit(request("attempt-2", second)),
            .rejected(.replacementDeltaRequired([RequirementID("r")]))
        )
        XCTAssertTrue(governor.authorizeReplacement(
            receiptID: ReceiptID("replace-1-with-2"),
            predecessor: first.fingerprint,
            replacement: second,
            failures: [blocker],
            delta: delta(
                axis: .action,
                failure: blocker,
                observation: "oracle-passes-b",
                lesson: "lesson-1"
            )
        ))
        XCTAssertEqual(
            governor.admit(request("attempt-2", second)),
            .admitted(second.fingerprint)
        )
        XCTAssertEqual(
            governor.recordFailure(strategy: second.fingerprint, failure: blocker, lessonDigest: digest("lesson-2")),
            .retireAndRequireCausallyDistinctRepair(
                remainingEquivalentFailures: 1,
                failureDigest: blocker.digest
            )
        )

        let third = strategy(
            action: "repair-layout-c",
            observations: ["oracle-passes-c"],
            lessons: [digest("lesson-2")]
        )
        XCTAssertTrue(governor.authorizeReplacement(
            receiptID: ReceiptID("replace-2-with-3"),
            predecessor: second.fingerprint,
            replacement: third,
            failures: [blocker],
            delta: delta(
                axis: .action,
                failure: blocker,
                observation: "oracle-passes-c",
                lesson: "lesson-2"
            )
        ))
        XCTAssertEqual(
            governor.admit(request("attempt-3", third)),
            .admitted(third.fingerprint)
        )
        XCTAssertEqual(
            governor.recordFailure(strategy: third.fingerprint, failure: blocker, lessonDigest: digest("lesson-3")),
            .retireEquivalentFailureLimit(blocker.digest)
        )
        XCTAssertNotNil(governor.retiredStrategies[third.fingerprint])

        let fourth = strategy(
            action: "repair-layout-d",
            observations: ["oracle-passes-d"],
            lessons: [digest("lesson-3")]
        )
        XCTAssertFalse(governor.authorizeReplacement(
            receiptID: ReceiptID("replace-3-with-4"),
            predecessor: third.fingerprint,
            replacement: fourth,
            failures: [blocker],
            delta: delta(
                axis: .action,
                failure: blocker,
                observation: "oracle-passes-d",
                lesson: "lesson-3"
            )
        ))
    }

    func testUnreviewedReplacementCannotManufactureNovelty() {
        var governor = makeGovernor()
        let predecessor = strategy()
        let blocker = failure(.deterministicImplementationFailure)
        _ = governor.admit(request("attempt-1", predecessor))
        _ = governor.recordFailure(
            strategy: predecessor.fingerprint,
            failure: blocker,
            lessonDigest: digest("lesson")
        )
        let replacement = strategy(action: "newly-worded-repair")

        XCTAssertEqual(
            governor.admit(request("new-thread", replacement)),
            .rejected(.replacementDeltaRequired([RequirementID("r")]))
        )
    }

    func testConfirmedTopologyMismatchRetiresOnFirstOccurrence() {
        var governor = makeGovernor()
        let descriptor = strategy()
        let blocker = failure(.authorityScopeOrTopologyMismatch)
        _ = governor.admit(request("attempt", descriptor))

        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("scope-lesson")),
            .retireAndRequireTopologyChange(blocker.digest)
        )
        XCTAssertNil(governor.activeStrategies[descriptor.fingerprint])
        XCTAssertNotNil(governor.retiredStrategies[descriptor.fingerprint])
    }

    func testUnavailableEvidenceRetiresInsteadOfPollingAgain() {
        var governor = makeGovernor()
        let descriptor = strategy()
        let blocker = failure(.evidenceUnavailable)
        _ = governor.admit(request("attempt", descriptor))

        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("absence-proof")),
            .retireAndWaitForNewEvidence(blocker.digest)
        )
        XCTAssertEqual(
            governor.admit(request("ask-again-with-new-words", descriptor)),
            .rejected(.strategyRetired(descriptor.fingerprint))
        )
    }

    func testVisualRegressionRollsBackRetiresAndFreezesDamageBudget() {
        var governor = makeGovernor(maximumDamageEvents: 1)
        let descriptor = strategy()
        let blocker = failure(.invariantOrBaselineRegression)
        _ = governor.admit(request("damaging-attempt", descriptor))

        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("visual-lesson")),
            .rollbackAndRetire(blocker.digest)
        )
        let replacement = strategy(action: "different-renderer")
        XCTAssertEqual(
            governor.admit(request("replacement", replacement)),
            .rejected(.damageBudgetExhausted)
        )
    }

    func testExternalAndHostWaitRequireChangedConditionWithoutConsumingAttempt() {
        var governor = makeGovernor()
        let descriptor = strategy()
        let blocker = failure(.transientExternalService)
        _ = governor.admit(request("attempt-1", descriptor))
        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("wait-lesson")),
            .waitForExternalCondition(blocker.digest)
        )
        XCTAssertEqual(
            governor.admit(request("attempt-2", descriptor)),
            .rejected(.conditionUnchanged(blocker.digest))
        )
        XCTAssertEqual(governor.consumption.attempts, 1)
        XCTAssertFalse(governor.observeChangedCondition(
            for: descriptor.fingerprint,
            previousFailureDigest: blocker.digest,
            observationDigest: blocker.digest
        ))
        XCTAssertTrue(governor.observeChangedCondition(
            for: descriptor.fingerprint,
            previousFailureDigest: blocker.digest,
            observationDigest: digest("service-version-2")
        ))
        XCTAssertEqual(governor.admit(request("attempt-2", descriptor)), .admitted(descriptor.fingerprint))
    }

    func testReviewerFailureRetriesReviewerAndNeverRelaunchesWorker() {
        var governor = makeGovernor()
        let descriptor = strategy()
        let blocker = failure(.reviewerProtocolOrTransportFailure)
        _ = governor.admit(request("worker-attempt", descriptor))

        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("review-lesson")),
            .retryReviewerOnly(blocker.digest)
        )
        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("review-lesson-2")),
            .retryReviewerOnly(blocker.digest)
        )
        XCTAssertEqual(
            governor.recordFailure(strategy: descriptor.fingerprint, failure: blocker, lessonDigest: digest("review-lesson-3")),
            .pauseForProtocolRepair(blocker.digest)
        )
        XCTAssertEqual(
            governor.admit(request("worker-relaunch", descriptor)),
            .rejected(.equivalentStrategyAlreadyActive(descriptor.fingerprint))
        )
        XCTAssertEqual(governor.consumption.attempts, 1)
    }

    func testMaterialTopologyDeltaAddressesTopologyFailure() {
        var governor = makeGovernor(maximumDamageEvents: 2)
        let predecessor = strategy(topology: "isolated-worktree")
        let blocker = failure(.authorityScopeOrTopologyMismatch)
        _ = governor.admit(request("attempt", predecessor))
        _ = governor.recordFailure(
            strategy: predecessor.fingerprint,
            failure: blocker,
            lessonDigest: digest("topology-lesson")
        )
        let replacement = strategy(
            topology: "coordinator-owned-worktree",
            observations: ["canonical-cwd-observed"],
            lessons: [digest("topology-lesson")]
        )
        let delta = CausalStrategyDelta(
            changedAxes: [.workspaceTopology],
            addressedFailureDigests: [blocker.digest],
            newPredictedObservationIDs: ["canonical-cwd-observed"],
            inheritedLessonDigests: [digest("topology-lesson")],
            whyOldFailureNoLongerApplies: [digest("coordinator-topology-receipt")]
        )

        XCTAssertTrue(governor.validateReplacement(
            predecessor: predecessor.fingerprint,
            replacement: replacement,
            failures: [blocker],
            delta: delta
        ))
    }

    func testIrrelevantAxisChangeDoesNotAddressUnavailableEvidence() {
        var governor = makeGovernor()
        let predecessor = strategy(hypothesis: "artifact-exists")
        let blocker = failure(.evidenceUnavailable)
        _ = governor.admit(request("attempt", predecessor))
        _ = governor.recordFailure(
            strategy: predecessor.fingerprint,
            failure: blocker,
            lessonDigest: digest("evidence-lesson")
        )
        let replacement = strategy(
            hypothesis: "artifact-probably-exists",
            observations: ["new-observation"]
        )
        let delta = CausalStrategyDelta(
            changedAxes: [.hypothesis],
            addressedFailureDigests: [blocker.digest],
            newPredictedObservationIDs: ["new-observation"],
            inheritedLessonDigests: [],
            whyOldFailureNoLongerApplies: [digest("prose-only")]
        )

        XCTAssertFalse(governor.validateReplacement(
            predecessor: predecessor.fingerprint,
            replacement: replacement,
            failures: [blocker],
            delta: delta
        ))
    }

    func testProgressVectorUsesHardVetoForProtectedRegression() {
        let requirement = RequirementID("r")
        let before = progress(unresolved: [requirement])
        let accepted = progress(accepted: [requirement])
        var regressed = accepted
        regressed.protectedInvariantRegressions = ["typography-scale"]

        XCTAssertTrue(accepted.isAcceptedProgress(over: before))
        XCTAssertFalse(regressed.isAcceptedProgress(over: before))
        XCTAssertFalse(before.isAcceptedProgress(over: before))
    }

    func testMalformedPredictionAndExcessCostFailBeforeBudgetConsumption() {
        var governor = makeGovernor()
        let descriptor = strategy()
        var malformed = request("malformed", descriptor)
        malformed.predictedObservationIDs = []
        XCTAssertEqual(
            governor.admit(malformed),
            .rejected(.malformedAttempt("prediction, falsification boundary, and rollback point are required"))
        )
        var expensive = request("expensive", descriptor)
        expensive.mutationCost = 101
        XCTAssertEqual(governor.admit(expensive), .rejected(.mutationBudgetExceeded))
        XCTAssertEqual(governor.consumption.attempts, 0)
    }

    func testPlanExpansionAndRoundTripCannotMintBudgetOrForgetRetirement() throws {
        var governor = makeGovernor(maximumPlanExpansions: 1)
        let descriptor = strategy()
        let blocker = failure(.evidenceUnavailable)
        _ = governor.admit(request("attempt", descriptor))
        _ = governor.recordFailure(
            strategy: descriptor.fingerprint,
            failure: blocker,
            lessonDigest: digest("lesson")
        )
        XCTAssertTrue(governor.consumePlanExpansion())
        XCTAssertFalse(governor.consumePlanExpansion())

        let restored = try JSONDecoder().decode(
            ConvergenceGovernor.self,
            from: JSONEncoder().encode(governor)
        )
        XCTAssertEqual(restored, governor)
        XCTAssertEqual(restored.consumption.attempts, 1)
        XCTAssertNotNil(restored.retiredStrategies[descriptor.fingerprint])
    }

    private func makeGovernor(
        maximumDamageEvents: UInt16 = 2,
        maximumPlanExpansions: UInt16 = 2
    ) -> ConvergenceGovernor {
        ConvergenceGovernor(
            epochID: "epoch-1",
            budget: ConvergenceBudget(
                maximumAttempts: 8,
                maximumEquivalentFailures: 3,
                maximumStrategies: 8,
                maximumPlanExpansions: maximumPlanExpansions,
                maximumMutationCost: 100,
                maximumVerificationCost: 100,
                maximumDamageEvents: maximumDamageEvents,
                maximumExternalEffects: 2
            )
        )
    }

    private func strategy(
        hypothesis: String = "repair-layout",
        action: String = "patch-swiftui",
        topology: String = "isolated-worktree",
        capabilities: Set<String> = ["shell"],
        evidence: Set<String> = ["native-screenshot"],
        observations: Set<String> = ["oracle-passes"],
        lessons: Set<ContentDigest> = []
    ) -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [RequirementID("r")],
            hypothesisClass: hypothesis,
            actionClass: action,
            workspaceTopology: topology,
            capabilityRoute: capabilities,
            evidenceSources: evidence,
            measurementBoundary: "before-input-through-render",
            verificationOracles: ["native-visual-oracle"],
            mutationSurfaceDigest: digest("swiftui-files"),
            baselineRevision: digest("baseline-revision"),
            expectedObservationIDs: observations,
            falsificationPredicateIDs: ["oracle-fails"],
            inheritedLessonDigests: lessons
        )
    }

    private func request(
        _ id: String,
        _ descriptor: CausalStrategyDescriptor
    ) -> AttemptAdmissionRequest {
        AttemptAdmissionRequest(
            attemptID: AttemptID(id),
            strategy: descriptor,
            predictedObservationIDs: descriptor.expectedObservationIDs,
            falsificationPredicateIDs: descriptor.falsificationPredicateIDs,
            rollbackPoint: digest("rollback"),
            mutationCost: 1,
            verificationCost: 1,
            externalEffects: 0
        )
    }

    private func failure(_ failureClass: CausalFailureClass) -> CausalFailureFingerprint {
        CausalFailureFingerprint(
            predicateID: "oracle-fails",
            outcomeClass: failureClass,
            structuredErrorCode: "E1",
            workspaceRevision: digest("workspace-revision"),
            capabilityOrResource: "resource",
            verifierOrMeasurement: "native-visual-oracle",
            immutableConstraint: failureClass == .authorityScopeOrTopologyMismatch ? "cwd" : nil,
            evidenceDigest: digest("same-evidence"),
            externalConditionVersion: "v1"
        )
    }

    private func progress(
        accepted: Set<RequirementID> = [],
        unresolved: Set<RequirementID> = []
    ) -> ConvergenceProgressVector {
        ConvergenceProgressVector(
            acceptedRequirements: accepted,
            unresolvedRequirements: unresolved,
            blockerDigests: [],
            acceptedEvidence: [],
            unresolvedVerifierFailures: [],
            acceptedQualityDimensions: [],
            unresolvedClaims: [],
            protectedInvariantRegressions: []
        )
    }

    private func delta(
        axis: CausalStrategyAxis,
        failure: CausalFailureFingerprint,
        observation: String,
        lesson: String
    ) -> CausalStrategyDelta {
        CausalStrategyDelta(
            changedAxes: [axis],
            addressedFailureDigests: [failure.digest],
            newPredictedObservationIDs: [observation],
            inheritedLessonDigests: [digest(lesson)],
            whyOldFailureNoLongerApplies: [digest("proof-\(observation)")]
        )
    }

    private func digest(_ value: String) -> ContentDigest { ContentDigest(value) }
}
