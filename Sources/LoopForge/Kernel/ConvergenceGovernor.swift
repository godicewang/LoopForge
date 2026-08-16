import CryptoKit
import Foundation

enum CausalStrategyAxis: String, Codable, CaseIterable, Hashable, Sendable {
    case hypothesis
    case action
    case workspaceTopology
    case capabilityRoute
    case evidenceSource
    case measurementBoundary
    case verificationOracle
    case mutationSurface
    case baselineRevision
}

enum CausalFailureClass: String, Codable, Hashable, Sendable {
    case authorityScopeOrTopologyMismatch
    case deterministicImplementationFailure
    case invariantOrBaselineRegression
    case evidenceUnavailable
    case transientExternalService
    case reviewerProtocolOrTransportFailure
    case resourceOrThermalCapacity
    case integrationConflictOrStaleRevision
    case unknownOutcome

    var causallyRelevantAxes: Set<CausalStrategyAxis> {
        switch self {
        case .authorityScopeOrTopologyMismatch:
            return [.workspaceTopology, .capabilityRoute, .mutationSurface]
        case .deterministicImplementationFailure:
            return [.hypothesis, .action, .mutationSurface, .verificationOracle]
        case .invariantOrBaselineRegression:
            return [.hypothesis, .action, .mutationSurface, .baselineRevision]
        case .evidenceUnavailable:
            return [.evidenceSource, .capabilityRoute]
        case .transientExternalService:
            return [.capabilityRoute, .evidenceSource]
        case .reviewerProtocolOrTransportFailure:
            return [.verificationOracle]
        case .resourceOrThermalCapacity:
            return [.capabilityRoute]
        case .integrationConflictOrStaleRevision:
            return [.workspaceTopology, .baselineRevision, .mutationSurface]
        case .unknownOutcome:
            return [.measurementBoundary, .verificationOracle]
        }
    }
}

/// Causally relevant strategy identity. Display prose, node/thread/model IDs and
/// attempt IDs are deliberately absent, so renaming cannot manufacture novelty.
struct CausalStrategyDescriptor: Codable, Hashable, Sendable {
    var requirementIDs: Set<RequirementID>
    var hypothesisClass: String
    var actionClass: String
    var workspaceTopology: String
    var capabilityRoute: Set<String>
    var evidenceSources: Set<String>
    var measurementBoundary: String
    var verificationOracles: Set<String>
    var mutationSurfaceDigest: ContentDigest
    var baselineRevision: ContentDigest
    var expectedObservationIDs: Set<String>
    var falsificationPredicateIDs: Set<String>
    var inheritedLessonDigests: Set<ContentDigest>

    var fingerprint: StrategyFingerprint {
        StrategyFingerprint(Self.sha256(canonicalMaterial))
    }

    func changedAxes(comparedWith other: Self) -> Set<CausalStrategyAxis> {
        var axes: Set<CausalStrategyAxis> = []
        if hypothesisClass != other.hypothesisClass { axes.insert(.hypothesis) }
        if actionClass != other.actionClass { axes.insert(.action) }
        if workspaceTopology != other.workspaceTopology { axes.insert(.workspaceTopology) }
        if capabilityRoute != other.capabilityRoute { axes.insert(.capabilityRoute) }
        if evidenceSources != other.evidenceSources { axes.insert(.evidenceSource) }
        if measurementBoundary != other.measurementBoundary { axes.insert(.measurementBoundary) }
        if verificationOracles != other.verificationOracles { axes.insert(.verificationOracle) }
        if mutationSurfaceDigest != other.mutationSurfaceDigest { axes.insert(.mutationSurface) }
        if baselineRevision != other.baselineRevision { axes.insert(.baselineRevision) }
        return axes
    }

    private var canonicalMaterial: String {
        // Strategy identity contains only the declared causal axes (plus the
        // requirements whose outcome the strategy owns). Prediction labels,
        // falsification IDs, and inherited lesson receipts constrain an
        // attempt or replacement authorization, but changing those opaque
        // names does not create a new causal strategy or a fresh budget.
        let fields = [
            canonicalSet(requirementIDs.map(\.rawValue)),
            hypothesisClass,
            actionClass,
            workspaceTopology,
            canonicalSet(capabilityRoute),
            canonicalSet(evidenceSources),
            measurementBoundary,
            canonicalSet(verificationOracles),
            mutationSurfaceDigest.rawValue,
            baselineRevision.rawValue
        ]
        return fields.map(lengthPrefix).joined()
    }

    private func canonicalSet<S: Sequence>(_ values: S) -> String where S.Element == String {
        values.sorted().map(lengthPrefix).joined()
    }

    private func lengthPrefix(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    private static func sha256(_ material: String) -> String {
        SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CausalFailureFingerprint: Codable, Hashable, Sendable {
    var predicateID: String
    var outcomeClass: CausalFailureClass
    var structuredErrorCode: String?
    var workspaceRevision: ContentDigest
    var capabilityOrResource: String?
    var verifierOrMeasurement: String?
    var immutableConstraint: String?
    var evidenceDigest: ContentDigest
    var externalConditionVersion: String?

    var digest: ContentDigest {
        let fields = [
            predicateID,
            outcomeClass.rawValue,
            structuredErrorCode ?? "",
            workspaceRevision.rawValue,
            capabilityOrResource ?? "",
            verifierOrMeasurement ?? "",
            immutableConstraint ?? "",
            evidenceDigest.rawValue,
            externalConditionVersion ?? ""
        ]
        let material = fields.map { "\($0.utf8.count):\($0)" }.joined()
        let hash = SHA256.hash(data: Data(material.utf8))
        return ContentDigest(hash.map { String(format: "%02x", $0) }.joined())
    }
}

struct CausalStrategyDelta: Codable, Hashable, Sendable {
    var changedAxes: Set<CausalStrategyAxis>
    var addressedFailureDigests: Set<ContentDigest>
    var newPredictedObservationIDs: Set<String>
    var inheritedLessonDigests: Set<ContentDigest>
    var whyOldFailureNoLongerApplies: Set<ContentDigest>

    func validates(
        predecessor: CausalStrategyDescriptor,
        replacement: CausalStrategyDescriptor,
        failures: Set<CausalFailureFingerprint>
    ) -> Bool {
        let actualAxes = replacement.changedAxes(comparedWith: predecessor)
        let failureDigests = Set(failures.map(\.digest))
        let relevantAxes = failures.reduce(into: Set<CausalStrategyAxis>()) {
            $0.formUnion($1.outcomeClass.causallyRelevantAxes)
        }
        return !changedAxes.isEmpty
            && changedAxes == actualAxes
            && !changedAxes.isDisjoint(with: relevantAxes)
            && !newPredictedObservationIDs.isEmpty
            && newPredictedObservationIDs.isSubset(of: replacement.expectedObservationIDs)
            && !addressedFailureDigests.isEmpty
            && addressedFailureDigests.isSubset(of: failureDigests)
            && !whyOldFailureNoLongerApplies.isEmpty
            && inheritedLessonDigests.isSubset(of: replacement.inheritedLessonDigests)
            && predecessor.requirementIDs == replacement.requirementIDs
    }
}

struct CausalReplacementAuthorizationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var predecessorFingerprint: StrategyFingerprint
    var replacementFingerprint: StrategyFingerprint
    var failureDigests: Set<ContentDigest>
    var delta: CausalStrategyDelta
}

struct ConvergenceBudget: Codable, Hashable, Sendable {
    var maximumAttempts: UInt32
    var maximumEquivalentFailures: UInt16
    var maximumStrategies: UInt16
    var maximumPlanExpansions: UInt16
    var maximumMutationCost: UInt64
    var maximumVerificationCost: UInt64
    var maximumDamageEvents: UInt16
    var maximumExternalEffects: UInt16

    func validationIssues() -> [String] {
        var issues: [String] = []
        if maximumAttempts == 0 { issues.append("maximumAttempts must be positive") }
        if maximumEquivalentFailures == 0 { issues.append("maximumEquivalentFailures must be positive") }
        if maximumStrategies == 0 { issues.append("maximumStrategies must be positive") }
        return issues
    }
}

struct ConvergenceConsumption: Codable, Hashable, Sendable {
    var attempts: UInt32 = 0
    var strategies: UInt16 = 0
    var planExpansions: UInt16 = 0
    var mutationCost: UInt64 = 0
    var verificationCost: UInt64 = 0
    var damageEvents: UInt16 = 0
    var externalEffects: UInt16 = 0
}

struct ConvergenceProgressVector: Codable, Hashable, Sendable {
    var acceptedRequirements: Set<RequirementID>
    var unresolvedRequirements: Set<RequirementID>
    var blockerDigests: Set<ContentDigest>
    var acceptedEvidence: Set<ReceiptID>
    var unresolvedVerifierFailures: Set<String>
    var acceptedQualityDimensions: Set<String>
    var unresolvedClaims: Set<String>
    var protectedInvariantRegressions: Set<String>

    func isAcceptedProgress(over previous: Self) -> Bool {
        guard protectedInvariantRegressions.isSubset(of: previous.protectedInvariantRegressions),
              acceptedRequirements.isSuperset(of: previous.acceptedRequirements),
              unresolvedRequirements.isSubset(of: previous.unresolvedRequirements),
              blockerDigests.isSubset(of: previous.blockerDigests),
              unresolvedVerifierFailures.isSubset(of: previous.unresolvedVerifierFailures) else {
            return false
        }
        return acceptedRequirements != previous.acceptedRequirements
            || unresolvedRequirements != previous.unresolvedRequirements
            || blockerDigests != previous.blockerDigests
            || acceptedEvidence != previous.acceptedEvidence
            || unresolvedVerifierFailures != previous.unresolvedVerifierFailures
            || acceptedQualityDimensions != previous.acceptedQualityDimensions
            || unresolvedClaims.isStrictSubset(of: previous.unresolvedClaims)
    }
}

struct AttemptAdmissionRequest: Codable, Hashable, Sendable {
    var attemptID: AttemptID
    var strategy: CausalStrategyDescriptor
    var predictedObservationIDs: Set<String>
    var falsificationPredicateIDs: Set<String>
    var rollbackPoint: ContentDigest
    var mutationCost: UInt64
    var verificationCost: UInt64
    var externalEffects: UInt16
}

enum ConvergenceAdmissionRejection: Codable, Hashable, Sendable {
    case invalidBudget([String])
    case malformedAttempt(String)
    case duplicateAttempt(AttemptID)
    case strategyRetired(StrategyFingerprint)
    case equivalentStrategyAlreadyActive(StrategyFingerprint)
    case attemptBudgetExhausted
    case strategyBudgetExhausted
    case damageBudgetExhausted
    case mutationBudgetExceeded
    case verificationBudgetExceeded
    case externalEffectBudgetExceeded
    case replacementDeltaRequired(Set<RequirementID>)
    case conditionUnchanged(ContentDigest)
}

enum ConvergenceAdmissionDecision: Codable, Hashable, Sendable {
    case admitted(StrategyFingerprint)
    case rejected(ConvergenceAdmissionRejection)
}

enum ConvergenceFailureAction: Codable, Hashable, Sendable {
    case retireAndRequireCausallyDistinctRepair(
        remainingEquivalentFailures: UInt16,
        failureDigest: ContentDigest
    )
    case retireAndRequireTopologyChange(ContentDigest)
    case retireAndWaitForNewEvidence(ContentDigest)
    case rollbackAndRetire(ContentDigest)
    case waitForExternalCondition(ContentDigest)
    case retryReviewerOnly(ContentDigest)
    case pauseForProtocolRepair(ContentDigest)
    case waitForHostStateChange(ContentDigest)
    case reconcileIntegrationOnce(ContentDigest)
    case reconcileExactExternalIdentity(ContentDigest)
    case retireEquivalentFailureLimit(ContentDigest)
}

enum CausalConvergenceTransition: Codable, Hashable, Sendable {
    case initialized(epochID: String, budget: ConvergenceBudget)
    case attemptAdmitted(AttemptAdmissionRequest, StrategyFingerprint)
    case failureRecorded(
        strategy: StrategyFingerprint,
        failure: CausalFailureFingerprint,
        action: ConvergenceFailureAction,
        lessonDigest: ContentDigest
    )
    case replacementAuthorized(
        CausalReplacementAuthorizationReceipt,
        replacement: CausalStrategyDescriptor,
        failures: Set<CausalFailureFingerprint>
    )
    case conditionChanged(
        strategy: StrategyFingerprint,
        previousFailureDigest: ContentDigest,
        observationDigest: ContentDigest
    )
    case progressEvaluated(
        strategy: StrategyFingerprint,
        accepted: Bool,
        previous: ConvergenceProgressVector,
        current: ConvergenceProgressVector
    )
    case planExpansionConsumed
}

struct RetiredCausalStrategy: Codable, Hashable, Sendable {
    var fingerprint: StrategyFingerprint
    var descriptor: CausalStrategyDescriptor
    var failureDigests: Set<ContentDigest>
    var lessonDigest: ContentDigest
    var retirementAction: ConvergenceFailureAction
}

enum ConvergenceStrategyLifecycle: String, Codable, Hashable, Sendable {
    case active
    case waitingForCondition
    case retired
}

struct ConvergenceProgressDeltaDiagnostic: Codable, Hashable, Sendable {
    var acceptedRequirementIDsAdded: [RequirementID]
    var unresolvedRequirementIDsResolved: [RequirementID]
    var blockerDigestsResolved: [ContentDigest]
    var acceptedEvidenceReceiptIDsAdded: [ReceiptID]
    var verifierFailureIDsResolved: [String]
    var acceptedQualityDimensionIDsAdded: [String]
    var unresolvedClaimIDsResolved: [String]
    var invariantRegressionIDsAdded: [String]

    init(previous: ConvergenceProgressVector, current: ConvergenceProgressVector) {
        acceptedRequirementIDsAdded = current.acceptedRequirements
            .subtracting(previous.acceptedRequirements)
            .sorted { $0.rawValue < $1.rawValue }
        unresolvedRequirementIDsResolved = previous.unresolvedRequirements
            .subtracting(current.unresolvedRequirements)
            .sorted { $0.rawValue < $1.rawValue }
        blockerDigestsResolved = previous.blockerDigests
            .subtracting(current.blockerDigests)
            .sorted { $0.rawValue < $1.rawValue }
        acceptedEvidenceReceiptIDsAdded = current.acceptedEvidence
            .subtracting(previous.acceptedEvidence)
            .sorted { $0.rawValue < $1.rawValue }
        verifierFailureIDsResolved = previous.unresolvedVerifierFailures
            .subtracting(current.unresolvedVerifierFailures)
            .sorted()
        acceptedQualityDimensionIDsAdded = current.acceptedQualityDimensions
            .subtracting(previous.acceptedQualityDimensions)
            .sorted()
        unresolvedClaimIDsResolved = previous.unresolvedClaims
            .subtracting(current.unresolvedClaims)
            .sorted()
        invariantRegressionIDsAdded = current.protectedInvariantRegressions
            .subtracting(previous.protectedInvariantRegressions)
            .sorted()
    }
}

struct ConvergenceBudgetDiagnostic: Codable, Hashable, Sendable {
    var maximum: ConvergenceBudget
    var consumed: ConvergenceConsumption
    var remaining: ConvergenceConsumption

    init(maximum: ConvergenceBudget, consumed: ConvergenceConsumption) {
        self.maximum = maximum
        self.consumed = consumed
        remaining = ConvergenceConsumption(
            attempts: maximum.maximumAttempts.saturatingSubtract(consumed.attempts),
            strategies: maximum.maximumStrategies.saturatingSubtract(consumed.strategies),
            planExpansions: maximum.maximumPlanExpansions.saturatingSubtract(
                consumed.planExpansions
            ),
            mutationCost: maximum.maximumMutationCost.saturatingSubtract(
                consumed.mutationCost
            ),
            verificationCost: maximum.maximumVerificationCost.saturatingSubtract(
                consumed.verificationCost
            ),
            damageEvents: maximum.maximumDamageEvents.saturatingSubtract(
                consumed.damageEvents
            ),
            externalEffects: maximum.maximumExternalEffects.saturatingSubtract(
                consumed.externalEffects
            )
        )
    }
}

struct ConvergenceStrategyDiagnostic: Codable, Hashable, Sendable, Identifiable {
    var id: String { fingerprint.rawValue }
    var fingerprint: StrategyFingerprint
    var requirementIDs: [RequirementID]
    var lifecycle: ConvergenceStrategyLifecycle
    var attemptIDs: [AttemptID]
    var mutationCostConsumed: UInt64
    var verificationCostConsumed: UInt64
    var externalEffectsConsumed: UInt16
    var waitingConditionDigest: ContentDigest?
    var failureDigests: [ContentDigest]
    var lessonDigest: ContentDigest?
    var retirementActionCode: String?
    var lastProgressAccepted: Bool?
    var lastProgressDelta: ConvergenceProgressDeltaDiagnostic?
}

struct ConvergenceReplacementDiagnostic: Codable, Hashable, Sendable, Identifiable {
    var id: String { receiptID.rawValue }
    var receiptID: ReceiptID
    var predecessorFingerprint: StrategyFingerprint
    var replacementFingerprint: StrategyFingerprint
    var failureDigests: [ContentDigest]
    var changedAxes: [CausalStrategyAxis]
    var newPredictedObservationIDs: [String]
    var inheritedLessonDigests: [ContentDigest]
    var consumed: Bool
}

struct ConvergenceDiagnosticProjection: Codable, Hashable, Sendable {
    static let authority = "accepted-run-journal-reducer-state-v1"

    var authority: String
    var epochID: String
    var sourceSequence: UInt64
    var budget: ConvergenceBudgetDiagnostic
    var strategies: [ConvergenceStrategyDiagnostic]
    var replacementAuthorizations: [ConvergenceReplacementDiagnostic]
    var equivalentFailureCounts: [String: UInt16]
    var projectionDigest: ContentDigest
}

private struct ConvergenceProgressEvaluation: Codable, Hashable, Sendable {
    var accepted: Bool
    var previous: ConvergenceProgressVector
    var current: ConvergenceProgressVector
}

private struct CausalStrategyRecord: Codable, Hashable, Sendable {
    var descriptor: CausalStrategyDescriptor
    var attemptIDs: Set<AttemptID>
    var failureDigests: Set<ContentDigest>
    var waitingConditionDigest: ContentDigest?
}

/// Pure journal-friendly convergence state. Every mutating call returns the
/// decision that must be durably appended before launching more work.
struct ConvergenceGovernor: Codable, Hashable, Sendable {
    let epochID: String
    let budget: ConvergenceBudget
    private(set) var consumption: ConvergenceConsumption
    private(set) var activeStrategies: [StrategyFingerprint: CausalStrategyDescriptor]
    private(set) var retiredStrategies: [StrategyFingerprint: RetiredCausalStrategy]
    private(set) var equivalentFailureCounts: [ContentDigest: UInt16]
    private(set) var replacementAuthorizationReceipts:
        [StrategyFingerprint: CausalReplacementAuthorizationReceipt]
    private var records: [StrategyFingerprint: CausalStrategyRecord]
    private var admittedAttemptIDs: Set<AttemptID>
    private var openAttemptIDs: [StrategyFingerprint: AttemptID]
    private var requirementsRequiringReplacement: Set<RequirementID>
    private var authorizedReplacementFingerprints: Set<StrategyFingerprint>
    private var consumedReplacementAuthorizations: Set<StrategyFingerprint>
    /// Optional for decoding snapshots produced before diagnostic projection
    /// v1. Journal replay repopulates these only from accepted typed events.
    private var admittedRequestsByAttemptID: [AttemptID: AttemptAdmissionRequest]?
    private var latestProgressEvaluations:
        [StrategyFingerprint: ConvergenceProgressEvaluation]?

    init(epochID: String, budget: ConvergenceBudget) {
        self.epochID = epochID
        self.budget = budget
        consumption = ConvergenceConsumption()
        activeStrategies = [:]
        retiredStrategies = [:]
        equivalentFailureCounts = [:]
        replacementAuthorizationReceipts = [:]
        records = [:]
        admittedAttemptIDs = []
        openAttemptIDs = [:]
        requirementsRequiringReplacement = []
        authorizedReplacementFingerprints = []
        consumedReplacementAuthorizations = []
        admittedRequestsByAttemptID = [:]
        latestProgressEvaluations = [:]
    }

    mutating func admit(_ request: AttemptAdmissionRequest) -> ConvergenceAdmissionDecision {
        let budgetIssues = budget.validationIssues()
        guard budgetIssues.isEmpty else { return .rejected(.invalidBudget(budgetIssues)) }
        guard !request.predictedObservationIDs.isEmpty,
              request.predictedObservationIDs.isSubset(of: request.strategy.expectedObservationIDs),
              !request.falsificationPredicateIDs.isEmpty,
              request.falsificationPredicateIDs.isSubset(of: request.strategy.falsificationPredicateIDs),
              !request.rollbackPoint.rawValue.isEmpty else {
            return .rejected(.malformedAttempt("prediction, falsification boundary, and rollback point are required"))
        }
        guard admittedAttemptIDs.insert(request.attemptID).inserted else {
            return .rejected(.duplicateAttempt(request.attemptID))
        }

        let fingerprint = request.strategy.fingerprint
        guard retiredStrategies[fingerprint] == nil else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.strategyRetired(fingerprint))
        }
        guard openAttemptIDs[fingerprint] == nil else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.equivalentStrategyAlreadyActive(fingerprint))
        }
        guard consumption.damageEvents == 0
                || consumption.damageEvents < budget.maximumDamageEvents else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.damageBudgetExhausted)
        }
        if let record = records[fingerprint] {
            if let condition = record.waitingConditionDigest {
                admittedAttemptIDs.remove(request.attemptID)
                return .rejected(.conditionUnchanged(condition))
            }
        } else {
            let replacementRequirements = request.strategy.requirementIDs
                .intersection(requirementsRequiringReplacement)
            guard replacementRequirements.isEmpty
                    || authorizedReplacementFingerprints.contains(fingerprint) else {
                admittedAttemptIDs.remove(request.attemptID)
                return .rejected(.replacementDeltaRequired(replacementRequirements))
            }
        }
        guard consumption.attempts < budget.maximumAttempts else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.attemptBudgetExhausted)
        }
        let isNewStrategy = records[fingerprint] == nil
        guard !isNewStrategy || consumption.strategies < budget.maximumStrategies else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.strategyBudgetExhausted)
        }
        guard consumption.mutationCost <= budget.maximumMutationCost,
              request.mutationCost <= budget.maximumMutationCost - consumption.mutationCost else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.mutationBudgetExceeded)
        }
        guard consumption.verificationCost <= budget.maximumVerificationCost,
              request.verificationCost <= budget.maximumVerificationCost - consumption.verificationCost else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.verificationBudgetExceeded)
        }
        guard consumption.externalEffects <= budget.maximumExternalEffects,
              request.externalEffects <= budget.maximumExternalEffects - consumption.externalEffects else {
            admittedAttemptIDs.remove(request.attemptID)
            return .rejected(.externalEffectBudgetExceeded)
        }

        consumption.attempts += 1
        consumption.mutationCost += request.mutationCost
        consumption.verificationCost += request.verificationCost
        consumption.externalEffects += request.externalEffects
        if isNewStrategy {
            consumption.strategies += 1
            records[fingerprint] = CausalStrategyRecord(
                descriptor: request.strategy,
                attemptIDs: [],
                failureDigests: [],
                waitingConditionDigest: nil
            )
            activeStrategies[fingerprint] = request.strategy
        }
        records[fingerprint]?.attemptIDs.insert(request.attemptID)
        requirementsRequiringReplacement.subtract(request.strategy.requirementIDs)
        authorizedReplacementFingerprints.remove(fingerprint)
        if replacementAuthorizationReceipts[fingerprint] != nil {
            consumedReplacementAuthorizations.insert(fingerprint)
        }
        openAttemptIDs[fingerprint] = request.attemptID
        if admittedRequestsByAttemptID == nil { admittedRequestsByAttemptID = [:] }
        admittedRequestsByAttemptID?[request.attemptID] = request
        return .admitted(fingerprint)
    }

    /// Returns only an attempt admission reconstructed from accepted journal
    /// transitions. Callers must not infer execution authority from a node
    /// authorization or a strategy fingerprint alone.
    func admittedRequest(for attemptID: AttemptID) -> AttemptAdmissionRequest? {
        admittedRequestsByAttemptID?[attemptID]
    }

    mutating func recordFailure(
        strategy fingerprint: StrategyFingerprint,
        failure: CausalFailureFingerprint,
        lessonDigest: ContentDigest
    ) -> ConvergenceFailureAction? {
        guard records[fingerprint] != nil,
              openAttemptIDs[fingerprint] != nil,
              !lessonDigest.rawValue.isEmpty else { return nil }
        let failureDigest = failure.digest
        let nextCount = min(UInt16.max, (equivalentFailureCounts[failureDigest] ?? 0) + 1)
        equivalentFailureCounts[failureDigest] = nextCount
        records[fingerprint]?.failureDigests.insert(failureDigest)

        if failure.outcomeClass == .reviewerProtocolOrTransportFailure {
            let ceiling = min(UInt16(3), budget.maximumEquivalentFailures)
            if nextCount >= ceiling {
                records[fingerprint]?.waitingConditionDigest = failureDigest
                return .pauseForProtocolRepair(failureDigest)
            }
            return .retryReviewerOnly(failureDigest)
        }
        openAttemptIDs[fingerprint] = nil

        let action: ConvergenceFailureAction
        switch failure.outcomeClass {
        case .authorityScopeOrTopologyMismatch:
            action = .retireAndRequireTopologyChange(failureDigest)
        case .invariantOrBaselineRegression:
            consumption.damageEvents = min(UInt16.max, consumption.damageEvents + 1)
            action = .rollbackAndRetire(failureDigest)
        case .evidenceUnavailable:
            action = .retireAndWaitForNewEvidence(failureDigest)
        case .transientExternalService:
            records[fingerprint]?.waitingConditionDigest = failureDigest
            return .waitForExternalCondition(failureDigest)
        case .reviewerProtocolOrTransportFailure:
            preconditionFailure("reviewer failure is handled before worker-attempt closure")
        case .resourceOrThermalCapacity:
            records[fingerprint]?.waitingConditionDigest = failureDigest
            return .waitForHostStateChange(failureDigest)
        case .integrationConflictOrStaleRevision where nextCount == 1:
            records[fingerprint]?.waitingConditionDigest = failureDigest
            return .reconcileIntegrationOnce(failureDigest)
        case .unknownOutcome:
            records[fingerprint]?.waitingConditionDigest = failureDigest
            return .reconcileExactExternalIdentity(failureDigest)
        case .deterministicImplementationFailure, .integrationConflictOrStaleRevision:
            let ceiling = min(UInt16(3), budget.maximumEquivalentFailures)
            if nextCount < ceiling {
                action = .retireAndRequireCausallyDistinctRepair(
                    remainingEquivalentFailures: ceiling - nextCount,
                    failureDigest: failureDigest
                )
                break
            }
            action = .retireEquivalentFailureLimit(failureDigest)
        }
        retire(fingerprint, lessonDigest: lessonDigest, action: action)
        return action
    }

    mutating func observeChangedCondition(
        for fingerprint: StrategyFingerprint,
        previousFailureDigest: ContentDigest,
        observationDigest: ContentDigest
    ) -> Bool {
        guard !observationDigest.rawValue.isEmpty,
              observationDigest != previousFailureDigest,
              records[fingerprint]?.waitingConditionDigest == previousFailureDigest else {
            return false
        }
        records[fingerprint]?.waitingConditionDigest = nil
        return true
    }

    mutating func recordProgress(
        strategy fingerprint: StrategyFingerprint,
        previous: ConvergenceProgressVector,
        current: ConvergenceProgressVector
    ) -> Bool? {
        guard records[fingerprint] != nil, openAttemptIDs[fingerprint] != nil else { return nil }
        openAttemptIDs[fingerprint] = nil
        let accepted = current.isAcceptedProgress(over: previous)
        if latestProgressEvaluations == nil { latestProgressEvaluations = [:] }
        latestProgressEvaluations?[fingerprint] = ConvergenceProgressEvaluation(
            accepted: accepted,
            previous: previous,
            current: current
        )
        return accepted
    }

    func validateReplacement(
        predecessor: StrategyFingerprint,
        replacement: CausalStrategyDescriptor,
        failures: Set<CausalFailureFingerprint>,
        delta: CausalStrategyDelta
    ) -> Bool {
        guard let old = records[predecessor]?.descriptor,
              replacement.fingerprint != predecessor,
              retiredStrategies[replacement.fingerprint] == nil else { return false }
        return delta.validates(predecessor: old, replacement: replacement, failures: failures)
    }

    mutating func authorizeReplacement(
        receiptID: ReceiptID,
        predecessor: StrategyFingerprint,
        replacement: CausalStrategyDescriptor,
        failures: Set<CausalFailureFingerprint>,
        delta: CausalStrategyDelta
    ) -> Bool {
        let ceiling = min(UInt16(3), budget.maximumEquivalentFailures)
        let failureDigests = Set(failures.map(\.digest))
        guard !receiptID.rawValue.isEmpty,
              !replacementAuthorizationReceipts.values.contains(where: { $0.id == receiptID }),
              replacementAuthorizationReceipts[replacement.fingerprint] == nil,
              !consumedReplacementAuthorizations.contains(replacement.fingerprint),
              failures.allSatisfy({ (equivalentFailureCounts[$0.digest] ?? 0) < ceiling }),
              validateReplacement(
                predecessor: predecessor,
                replacement: replacement,
                failures: failures,
                delta: delta
              ) else { return false }
        replacementAuthorizationReceipts[replacement.fingerprint] =
            CausalReplacementAuthorizationReceipt(
                id: receiptID,
                predecessorFingerprint: predecessor,
                replacementFingerprint: replacement.fingerprint,
                failureDigests: failureDigests,
                delta: delta
            )
        authorizedReplacementFingerprints.insert(replacement.fingerprint)
        return true
    }

    mutating func consumePlanExpansion() -> Bool {
        guard consumption.planExpansions < budget.maximumPlanExpansions else { return false }
        consumption.planExpansions += 1
        return true
    }

    func diagnosticProjection(sourceSequence: UInt64) -> ConvergenceDiagnosticProjection {
        let requests = admittedRequestsByAttemptID ?? [:]
        let progress = latestProgressEvaluations ?? [:]
        let strategyDiagnostics = records.map { fingerprint, record in
            let admitted = record.attemptIDs.compactMap { requests[$0] }
            let retired = retiredStrategies[fingerprint]
            let lifecycle: ConvergenceStrategyLifecycle
            if retired != nil {
                lifecycle = .retired
            } else if record.waitingConditionDigest != nil {
                lifecycle = .waitingForCondition
            } else {
                lifecycle = .active
            }
            let evaluation = progress[fingerprint]
            return ConvergenceStrategyDiagnostic(
                fingerprint: fingerprint,
                requirementIDs: record.descriptor.requirementIDs.sorted {
                    $0.rawValue < $1.rawValue
                },
                lifecycle: lifecycle,
                attemptIDs: record.attemptIDs.sorted { $0.rawValue < $1.rawValue },
                mutationCostConsumed: admitted.reduce(0) {
                    $0.saturatingAdd($1.mutationCost)
                },
                verificationCostConsumed: admitted.reduce(0) {
                    $0.saturatingAdd($1.verificationCost)
                },
                externalEffectsConsumed: admitted.reduce(0) {
                    $0.saturatingAdd($1.externalEffects)
                },
                waitingConditionDigest: record.waitingConditionDigest,
                failureDigests: record.failureDigests.sorted {
                    $0.rawValue < $1.rawValue
                },
                lessonDigest: retired?.lessonDigest,
                retirementActionCode: retired?.retirementAction.diagnosticCode,
                lastProgressAccepted: evaluation?.accepted,
                lastProgressDelta: evaluation.map {
                    ConvergenceProgressDeltaDiagnostic(
                        previous: $0.previous,
                        current: $0.current
                    )
                }
            )
        }.sorted { $0.fingerprint.rawValue < $1.fingerprint.rawValue }

        let replacements = replacementAuthorizationReceipts.values.map { receipt in
            ConvergenceReplacementDiagnostic(
                receiptID: receipt.id,
                predecessorFingerprint: receipt.predecessorFingerprint,
                replacementFingerprint: receipt.replacementFingerprint,
                failureDigests: receipt.failureDigests.sorted {
                    $0.rawValue < $1.rawValue
                },
                changedAxes: receipt.delta.changedAxes.sorted {
                    $0.rawValue < $1.rawValue
                },
                newPredictedObservationIDs: receipt.delta
                    .newPredictedObservationIDs.sorted(),
                inheritedLessonDigests: receipt.delta.inheritedLessonDigests.sorted {
                    $0.rawValue < $1.rawValue
                },
                consumed: consumedReplacementAuthorizations.contains(
                    receipt.replacementFingerprint
                )
            )
        }.sorted { $0.receiptID.rawValue < $1.receiptID.rawValue }

        var projection = ConvergenceDiagnosticProjection(
            authority: ConvergenceDiagnosticProjection.authority,
            epochID: epochID,
            sourceSequence: sourceSequence,
            budget: ConvergenceBudgetDiagnostic(maximum: budget, consumed: consumption),
            strategies: strategyDiagnostics,
            replacementAuthorizations: replacements,
            equivalentFailureCounts: Dictionary(uniqueKeysWithValues:
                equivalentFailureCounts.map { ($0.key.rawValue, $0.value) }
            ),
            projectionDigest: ContentDigest("")
        )
        projection.projectionDigest = Self.diagnosticDigest(projection)
        return projection
    }

    private mutating func retire(
        _ fingerprint: StrategyFingerprint,
        lessonDigest: ContentDigest,
        action: ConvergenceFailureAction
    ) {
        guard let record = records[fingerprint] else { return }
        activeStrategies[fingerprint] = nil
        openAttemptIDs[fingerprint] = nil
        requirementsRequiringReplacement.formUnion(record.descriptor.requirementIDs)
        retiredStrategies[fingerprint] = RetiredCausalStrategy(
            fingerprint: fingerprint,
            descriptor: record.descriptor,
            failureDigests: record.failureDigests,
            lessonDigest: lessonDigest,
            retirementAction: action
        )
    }

    private static func diagnosticDigest(
        _ projection: ConvergenceDiagnosticProjection
    ) -> ContentDigest {
        var material = projection
        material.projectionDigest = ContentDigest("")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(material) else {
            return ContentDigest("")
        }
        return ContentDigest(SHA256.hash(data: encoded).map {
            String(format: "%02x", $0)
        }.joined())
    }
}

private extension ConvergenceFailureAction {
    var diagnosticCode: String {
        switch self {
        case .retireAndRequireCausallyDistinctRepair:
            return "retire-and-require-causally-distinct-repair"
        case .retireAndRequireTopologyChange:
            return "retire-and-require-topology-change"
        case .retireAndWaitForNewEvidence:
            return "retire-and-wait-for-new-evidence"
        case .rollbackAndRetire:
            return "rollback-and-retire"
        case .waitForExternalCondition:
            return "wait-for-external-condition"
        case .retryReviewerOnly:
            return "retry-reviewer-only"
        case .pauseForProtocolRepair:
            return "pause-for-protocol-repair"
        case .waitForHostStateChange:
            return "wait-for-host-state-change"
        case .reconcileIntegrationOnce:
            return "reconcile-integration-once"
        case .reconcileExactExternalIdentity:
            return "reconcile-exact-external-identity"
        case .retireEquivalentFailureLimit:
            return "retire-equivalent-failure-limit"
        }
    }
}

private extension FixedWidthInteger {
    func saturatingSubtract(_ other: Self) -> Self {
        other >= self ? 0 : self - other
    }

    func saturatingAdd(_ other: Self) -> Self {
        let (value, overflow) = addingReportingOverflow(other)
        return overflow ? .max : value
    }
}

private extension Set {
    func isStrictSubset(of other: Set<Element>) -> Bool {
        isSubset(of: other) && self != other
    }
}
