import Foundation
import CryptoKit

enum VisualGateDimension: String, Codable, CaseIterable, Hashable, Sendable {
    case provenanceAndComparability
    case productIdentityContinuity
    case initialTaskHierarchy
    case typographyHierarchy
    case symmetryAndAlignment
    case spacingRhythmAndDensity
    case shapeLanguage
    case collisionOcclusionAndSafeArea
    case responsiveComposition
    case accessibilitySemanticsAndOperation
    case localizationQualityAndSlotFit
    case independentProductDesignVerdict
}

enum VisualGateStatus: String, Codable, Hashable, Sendable {
    case pass
    case fail
    case unknown
    case notApplicable

    var vetoes: Bool { self == .fail || self == .unknown }
}

struct VisualTraitSignature: Codable, Hashable, Sendable {
    var deviceClass: String
    var viewportWidthPixels: Int
    var viewportHeightPixels: Int
    var scale: Double
    var operatingSystem: String
    var orientation: String
    var locale: String
    var calendar: String
    var layoutDirection: String
    var appearance: String
    var contrast: String
    var reducedMotion: Bool
    var boldText: Bool
    var contentSizeCategory: String
    var fixtureDigest: ContentDigest

    var hasValidViewport: Bool {
        viewportWidthPixels > 0 && viewportHeightPixels > 0 && scale > 0
    }
}

struct NativeCaptureReceipt: Codable, Hashable, Sendable {
    var id: NativeCaptureID
    var cellID: VisualCellID
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var captureProtocol: ContentDigest
    var traits: VisualTraitSignature
    var imageDigest: ContentDigest
    var accessibilityTreeDigest: ContentDigest
    var navigationRecipeDigest: ContentDigest
    var componentBoundaryDigest: ContentDigest?
    var designTokenTraceDigest: ContentDigest?
    var imageWidthPixels: Int
    var imageHeightPixels: Int
    var fullViewport: Bool
    var cleanInstall: Bool
    var harnessIdentity: String
    var processExitCode: Int32
    var capturedAt: Date

    var isComplete: Bool {
        !id.rawValue.isEmpty
            && !cellID.rawValue.isEmpty
            && !sourceTree.rawValue.isEmpty
            && !builtArtifact.rawValue.isEmpty
            && !captureProtocol.rawValue.isEmpty
            && !imageDigest.rawValue.isEmpty
            && !accessibilityTreeDigest.rawValue.isEmpty
            && !navigationRecipeDigest.rawValue.isEmpty
            && imageWidthPixels == traits.viewportWidthPixels
            && imageHeightPixels == traits.viewportHeightPixels
            && !harnessIdentity.isEmpty
            && traits.hasValidViewport
            && fullViewport
            && cleanInstall
            && processExitCode == 0
    }
}

struct DesignAuthorityReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var baselineID: DesignBaselineID
    var authority: ActorIdentity
    var authorityRole: String
    var issuedAt: Date

    var isProductDesignAuthority: Bool {
        authorityRole == "productDesignAuthority" && !id.rawValue.isEmpty
    }
}

struct DesignInvariant: Codable, Hashable, Sendable {
    var id: String
    var dimension: VisualGateDimension
    var cellIDs: Set<VisualCellID>
}

enum DesignDebtDirection: String, Codable, Hashable, Sendable {
    case improveOnly
    case notWorse
}

struct DesignDebt: Codable, Hashable, Sendable {
    var id: DesignDebtID
    var dimension: VisualGateDimension
    var cellIDs: Set<VisualCellID>
    var baselineSeverity: Double
    var maximumInterimSeverity: Double
    var direction: DesignDebtDirection
    var closureRequired: Bool
    var evidenceDigest: ContentDigest
}

struct DesignBaselineBundle: Codable, Hashable, Sendable {
    var id: DesignBaselineID
    var contractID: TaskContractID
    var protectedBaselineID: BaselineID
    var requirementIDs: Set<RequirementID>
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var captureProtocol: ContentDigest
    var designTokenSnapshot: ContentDigest
    var semanticSurfaceManifest: ContentDigest
    var captures: [NativeCaptureReceipt]
    var protectedInvariants: [DesignInvariant]
    var knownDebt: [DesignDebt]
    var authority: DesignAuthorityReceipt
    var frozenAt: Date

    var captureByCell: [VisualCellID: NativeCaptureReceipt]? {
        let pairs = captures.map { ($0.cellID, $0) }
        guard Set(pairs.map(\.0)).count == pairs.count else { return nil }
        return Dictionary(uniqueKeysWithValues: pairs)
    }
}

struct VisualGateThresholds: Codable, Hashable, Sendable {
    var typographyRatioTolerance: Double
    var alignmentToleranceLineHeights: Double
    var spacingPointTolerance: Double
    var spacingRelativeTolerance: Double
    var maximumOccupancyIncrease: Double
    var shapeRatioTolerance: Double
    var maximumNewOcclusionPixels: Int

    static let platformDefault = VisualGateThresholds(
        typographyRatioTolerance: 0.10,
        alignmentToleranceLineHeights: 0.5,
        spacingPointTolerance: 1,
        spacingRelativeTolerance: 0.10,
        maximumOccupancyIncrease: 0.15,
        shapeRatioTolerance: 0.10,
        maximumNewOcclusionPixels: 0
    )
}

struct VisualPairMeasurements: Codable, Hashable, Sendable {
    var cellID: VisualCellID
    var evidenceReceiptIDs: [ReceiptID]
    var productIdentityContinuous: Bool?
    var primaryTaskWithinBoundary: Bool?
    var typographyHierarchyInverted: Bool?
    var maximumTypographyRatioDelta: Double?
    var symmetricTitleLineCountDelta: Int?
    var maximumAlignmentOffsetLineHeights: Double?
    var maximumSpacingDeltaPoints: Double?
    var maximumSpacingRelativeDelta: Double?
    var contentOccupancyIncrease: Double?
    var maximumShapeRatioDelta: Double?
    var shapeContentFitPasses: Bool?
    var undeclaredSemanticTokenCount: Int?
    var newOcclusionPixels: Int?
    var responsiveCompositionPasses: Bool?
    var accessibilitySemanticsPasses: Bool?
    var localizationQualityPasses: Bool?
    var localizedCopyFitsSlot: Bool?
    var perceptualDifference: Double?
}

struct VisualMutationManifest: Codable, Hashable, Sendable {
    var directlyAffectedCellIDs: Set<VisualCellID>
    var allBaselineCellIDs: Set<VisualCellID>
    var globalSemanticTokenMutation: Bool
    var touchedTokenFamilies: Set<String>

    var requiredCellIDs: Set<VisualCellID> {
        globalSemanticTokenMutation ? allBaselineCellIDs : directlyAffectedCellIDs
    }
}

enum VisualReviewDecision: String, Codable, Hashable, Sendable {
    case pass
    case fail
}

struct VisualReviewBatchReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var candidateCaptureIDs: [NativeCaptureID]
    var verdictRecordedCaptureIDs: Set<NativeCaptureID>

    var isComplete: Bool {
        !candidateCaptureIDs.isEmpty
            && Set(candidateCaptureIDs).count == candidateCaptureIDs.count
            && verdictRecordedCaptureIDs == Set(candidateCaptureIDs)
    }
}

struct IndependentVisualReviewReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var reviewer: ActorIdentity
    var workerLineageDigest: ContentDigest
    var provider: String
    var model: String
    var contextDigest: ContentDigest
    var systemPromptDigest: ContentDigest
    var userPromptDigest: ContentDigest
    var evidenceBundleDigest: ContentDigest
    var deterministicResultsDigest: ContentDigest
    var baselineID: DesignBaselineID
    var candidateSourceTree: ContentDigest
    var baselineCaptureIDs: Set<NativeCaptureID>
    var candidateCaptureIDs: Set<NativeCaptureID>
    var attachedImageDigests: [ContentDigest]
    var perImageDecisions: [NativeCaptureID: VisualReviewDecision]
    var pairDecisions: [VisualCellID: VisualReviewDecision]
    var inspectedCellIDs: Set<VisualCellID>
    var batchReceiptIDs: Set<ReceiptID>
    var blindToWorkerNarrative: Bool
    var decision: VisualReviewDecision
    var rawResponseDigest: ContentDigest
}

struct DesignBaselineAmendment: Codable, Hashable, Sendable {
    var id: ReceiptID
    var baselineID: DesignBaselineID
    var candidateSourceTree: ContentDigest
    var dimensions: Set<VisualGateDimension>
    var authority: ActorIdentity
    var authorityRole: String
    var reasonDigest: ContentDigest
    var issuedAt: Date

    var isAuthorized: Bool {
        authorityRole == "productDesignAuthority"
            && !id.rawValue.isEmpty
            && !reasonDigest.rawValue.isEmpty
            && !dimensions.isEmpty
    }
}

struct VisualCandidateBundle: Codable, Hashable, Sendable {
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var mutationStartedAt: Date
    var captures: [NativeCaptureReceipt]
    var measurements: [VisualPairMeasurements]
    var mutationManifest: VisualMutationManifest
    var debtSeverityByID: [DesignDebtID: Double]
    var reviewBatches: [VisualReviewBatchReceipt]
    var independentReview: IndependentVisualReviewReceipt?
    var amendments: [DesignBaselineAmendment]

    var captureByCell: [VisualCellID: NativeCaptureReceipt]? {
        let pairs = captures.map { ($0.cellID, $0) }
        guard Set(pairs.map(\.0)).count == pairs.count else { return nil }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    var measurementsByCell: [VisualCellID: VisualPairMeasurements]? {
        let pairs = measurements.map { ($0.cellID, $0) }
        guard Set(pairs.map(\.0)).count == pairs.count else { return nil }
        return Dictionary(uniqueKeysWithValues: pairs)
    }
}

struct VisualGateDimensionResult: Codable, Hashable, Sendable {
    var dimension: VisualGateDimension
    var status: VisualGateStatus
    var failedCellIDs: Set<VisualCellID>
    var evidenceReceiptIDs: Set<ReceiptID>
    var reasonCodes: Set<String>
}

struct VisualGateResult: Codable, Hashable, Sendable {
    var accepted: Bool
    var requiredCellIDs: Set<VisualCellID>
    var baselineCaptureCount: Int
    var candidateCaptureCount: Int
    var selectedCaptureCount: Int
    var attachedCaptureCount: Int
    var inspectedCaptureCount: Int
    var results: [VisualGateDimensionResult]

    var failingDimensions: Set<VisualGateDimension> {
        Set(results.lazy.filter { $0.status.vetoes }.map(\.dimension))
    }
}

struct VisualGateEvaluationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var attemptID: AttemptID
    var requirementIDs: Set<RequirementID>
    var baselineID: DesignBaselineID
    var candidateSourceTree: ContentDigest
    var candidateBuiltArtifact: ContentDigest
    var deterministicEvidenceDigest: ContentDigest
    var evaluator: ActorIdentity
    var evaluatedAt: Date
    var journalSequence: UInt64
    var independentReviewReceiptID: ReceiptID?
    var result: VisualGateResult
    /// Present for production-native evaluations issued from one live review
    /// authority. Optional only for replaying older journals and DEBUG
    /// characterization fixtures.
    var nativeReviewRequestDigest: ContentDigest? = nil
    var nativeCaptureAttestationDigests: Set<ContentDigest>? = nil
    var nativeMeasurementAttestationDigests: Set<ContentDigest>? = nil
    var nativeReviewCompletedAt: Date? = nil
}

enum VisualReviewBatchPlanner {
    static func plan(
        candidateCaptureIDs: Set<NativeCaptureID>,
        maximumImagesPerBatch: Int
    ) -> [[NativeCaptureID]] {
        guard maximumImagesPerBatch > 0 else { return [] }
        let ordered = candidateCaptureIDs.sorted { $0.rawValue < $1.rawValue }
        return stride(from: 0, to: ordered.count, by: maximumImagesPerBatch).map {
            Array(ordered[$0..<min($0 + maximumImagesPerBatch, ordered.count)])
        }
    }
}

enum DesignBaselineGate {
    static func deterministicEvidenceDigest(
        baseline: DesignBaselineBundle,
        candidate: VisualCandidateBundle,
        thresholds: VisualGateThresholds = .platformDefault
    ) -> ContentDigest {
        struct Envelope: Encodable {
            var baselineID: DesignBaselineID
            var contractID: TaskContractID
            var protectedBaselineID: BaselineID
            var requirementIDs: [RequirementID]
            var baselineSourceTree: ContentDigest
            var candidateSourceTree: ContentDigest
            var captureProtocol: ContentDigest
            var designTokenSnapshot: ContentDigest
            var semanticSurfaceManifest: ContentDigest
            var protectedInvariantMaterial: [String]
            var knownDebtMaterial: [String]
            var requiredCellIDs: [VisualCellID]
            var directlyAffectedCellIDs: [VisualCellID]
            var allBaselineCellIDs: [VisualCellID]
            var globalSemanticTokenMutation: Bool
            var touchedTokenFamilies: [String]
            var baselineCaptures: [NativeCaptureReceipt]
            var candidateCaptures: [NativeCaptureReceipt]
            var measurements: [VisualPairMeasurements]
            var debtSeverityByID: [String: Double]
            var amendmentMaterial: [String]
            var thresholds: VisualGateThresholds
        }

        let required = candidate.mutationManifest.requiredCellIDs
        let baselineCaptures = baseline.captures
            .filter { required.contains($0.cellID) }
            .sorted { $0.cellID.rawValue < $1.cellID.rawValue }
        let candidateCaptures = candidate.captures
            .filter { required.contains($0.cellID) }
            .sorted { $0.cellID.rawValue < $1.cellID.rawValue }
        let measurements = candidate.measurements
            .filter { required.contains($0.cellID) }
            .map { value -> VisualPairMeasurements in
                var normalized = value
                normalized.evidenceReceiptIDs.sort { $0.rawValue < $1.rawValue }
                return normalized
            }
            .sorted { $0.cellID.rawValue < $1.cellID.rawValue }
        let invariantMaterial = baseline.protectedInvariants.map { invariant in
            [
                invariant.id,
                invariant.dimension.rawValue,
                invariant.cellIDs.map(\.rawValue).sorted().joined(separator: ",")
            ].joined(separator: "|")
        }.sorted()
        let debtMaterial = baseline.knownDebt.map { debt in
            [
                debt.id.rawValue,
                debt.dimension.rawValue,
                debt.cellIDs.map(\.rawValue).sorted().joined(separator: ","),
                String(debt.baselineSeverity),
                String(debt.maximumInterimSeverity),
                debt.direction.rawValue,
                String(debt.closureRequired),
                debt.evidenceDigest.rawValue
            ].joined(separator: "|")
        }.sorted()
        let amendmentMaterial = candidate.amendments.map { amendment in
            [
                amendment.id.rawValue,
                amendment.baselineID.rawValue,
                amendment.candidateSourceTree.rawValue,
                amendment.dimensions.map(\.rawValue).sorted().joined(separator: ","),
                amendment.authority.id.rawValue,
                amendment.authority.lineageDigest.rawValue,
                amendment.authorityRole,
                amendment.reasonDigest.rawValue,
                String(amendment.issuedAt.timeIntervalSince1970)
            ].joined(separator: "|")
        }.sorted()
        let envelope = Envelope(
            baselineID: baseline.id,
            contractID: baseline.contractID,
            protectedBaselineID: baseline.protectedBaselineID,
            requirementIDs: baseline.requirementIDs.sorted { $0.rawValue < $1.rawValue },
            baselineSourceTree: baseline.sourceTree,
            candidateSourceTree: candidate.sourceTree,
            captureProtocol: baseline.captureProtocol,
            designTokenSnapshot: baseline.designTokenSnapshot,
            semanticSurfaceManifest: baseline.semanticSurfaceManifest,
            protectedInvariantMaterial: invariantMaterial,
            knownDebtMaterial: debtMaterial,
            requiredCellIDs: required.sorted { $0.rawValue < $1.rawValue },
            directlyAffectedCellIDs: candidate.mutationManifest.directlyAffectedCellIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            allBaselineCellIDs: candidate.mutationManifest.allBaselineCellIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            globalSemanticTokenMutation: candidate.mutationManifest.globalSemanticTokenMutation,
            touchedTokenFamilies: candidate.mutationManifest.touchedTokenFamilies.sorted(),
            baselineCaptures: baselineCaptures,
            candidateCaptures: candidateCaptures,
            measurements: measurements,
            debtSeverityByID: Dictionary(uniqueKeysWithValues:
                candidate.debtSeverityByID.map { ($0.key.rawValue, $0.value) }
            ),
            amendmentMaterial: amendmentMaterial,
            thresholds: thresholds
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return ContentDigest("") }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    static func evaluate(
        baseline: DesignBaselineBundle,
        candidate: VisualCandidateBundle,
        thresholds: VisualGateThresholds = .platformDefault
    ) -> VisualGateResult {
        let required = candidate.mutationManifest.requiredCellIDs
        let contractedCells = Set(baseline.protectedInvariants.flatMap(\.cellIDs))
        let baselineByCell = baseline.captureByCell
        let candidateByCell = candidate.captureByCell
        let measurements = candidate.measurementsByCell
        let applicable = contractedCells.intersection(required)
        let dimensions = Set(baseline.protectedInvariants.filter {
            !$0.cellIDs.isDisjoint(with: required)
        }.map(\.dimension))

        var results: [VisualGateDimensionResult] = []
        func append(
            _ dimension: VisualGateDimension,
            _ status: VisualGateStatus,
            failed: Set<VisualCellID> = [],
            evidence: Set<ReceiptID> = [],
            reasons: Set<String> = []
        ) {
            results.append(VisualGateDimensionResult(
                dimension: dimension,
                status: status,
                failedCellIDs: failed,
                evidenceReceiptIDs: evidence,
                reasonCodes: reasons
            ))
        }

        let invalidAmendment = candidate.amendments.contains {
            $0.baselineID != baseline.id
                || $0.candidateSourceTree != candidate.sourceTree
                || !$0.isAuthorized
        }
        var provenanceFailures: Set<VisualCellID> = []
        var provenanceReasons: Set<String> = []
        if baseline.authority.baselineID != baseline.id
            || !baseline.authority.isProductDesignAuthority
            || baseline.authority.issuedAt > baseline.frozenAt
            || candidate.mutationStartedAt < baseline.frozenAt {
            provenanceReasons.insert("baseline-not-frozen-before-mutation")
        }
        if invalidAmendment { provenanceReasons.insert("unauthorized-baseline-amendment") }
        let thresholdsAreValid = thresholds.typographyRatioTolerance.isFinite
            && thresholds.typographyRatioTolerance >= 0
            && thresholds.alignmentToleranceLineHeights.isFinite
            && thresholds.alignmentToleranceLineHeights >= 0
            && thresholds.spacingPointTolerance.isFinite
            && thresholds.spacingPointTolerance >= 0
            && thresholds.spacingRelativeTolerance.isFinite
            && thresholds.spacingRelativeTolerance >= 0
            && thresholds.maximumOccupancyIncrease.isFinite
            && thresholds.maximumOccupancyIncrease >= 0
            && thresholds.shapeRatioTolerance.isFinite
            && thresholds.shapeRatioTolerance >= 0
            && thresholds.maximumNewOcclusionPixels >= 0
        if !thresholdsAreValid {
            provenanceReasons.insert("invalid-visual-gate-thresholds")
        }
        if candidate.mutationManifest.allBaselineCellIDs != contractedCells
            || candidate.mutationManifest.directlyAffectedCellIDs.isEmpty
            || !candidate.mutationManifest.directlyAffectedCellIDs.isSubset(of: contractedCells)
            || required.isEmpty
            || !required.isSubset(of: applicable) {
            provenanceReasons.insert("required-capture-matrix-not-covered-by-contract")
        }
        if baselineByCell == nil || candidateByCell == nil || measurements == nil {
            provenanceReasons.insert("duplicate-cell-receipt")
        }
        for cell in required {
            guard let base = baselineByCell?[cell], let cand = candidateByCell?[cell] else {
                provenanceFailures.insert(cell)
                provenanceReasons.insert("missing-baseline-or-candidate-capture")
                continue
            }
            if !base.isComplete || !cand.isComplete
                || base.sourceTree != baseline.sourceTree
                || base.builtArtifact != baseline.builtArtifact
                || base.captureProtocol != baseline.captureProtocol
                || cand.sourceTree != candidate.sourceTree
                || cand.builtArtifact != candidate.builtArtifact
                || cand.captureProtocol != baseline.captureProtocol
                || base.traits != cand.traits
                || base.capturedAt > baseline.frozenAt
                || cand.capturedAt < candidate.mutationStartedAt {
                provenanceFailures.insert(cell)
                provenanceReasons.insert("capture-provenance-or-traits-mismatch")
            }
        }
        let requiredCandidateIDs = Set(required.compactMap { candidateByCell?[$0]?.id })
        let completeBatches = candidate.reviewBatches.filter(\.isComplete)
        let batchedIDList = completeBatches.flatMap(\.candidateCaptureIDs)
        let batchedIDs = Set(batchedIDList)
        let batchReceiptIDs = candidate.reviewBatches.map(\.id)
        if completeBatches.count != candidate.reviewBatches.count
            || Set(batchReceiptIDs).count != batchReceiptIDs.count
            || batchReceiptIDs.contains(where: { $0.rawValue.isEmpty })
            || batchedIDList.count != batchedIDs.count
            || batchedIDs != requiredCandidateIDs {
            provenanceReasons.insert("selected-attached-inspected-count-mismatch")
            provenanceFailures.formUnion(required)
        }
        append(
            .provenanceAndComparability,
            provenanceReasons.isEmpty ? .pass : .fail,
            failed: provenanceFailures,
            reasons: provenanceReasons
        )

        func measuredResult(
            _ dimension: VisualGateDimension,
            predicate: (VisualPairMeasurements) -> Bool?
        ) {
            guard dimensions.contains(dimension) else {
                append(dimension, .notApplicable)
                return
            }
            var failed: Set<VisualCellID> = []
            var evidence: Set<ReceiptID> = []
            var unknown = false
            for cell in required {
                guard let value = measurements?[cell],
                      !value.evidenceReceiptIDs.isEmpty,
                      Set(value.evidenceReceiptIDs).count == value.evidenceReceiptIDs.count else {
                    unknown = true
                    continue
                }
                evidence.formUnion(value.evidenceReceiptIDs)
                guard let passes = predicate(value) else {
                    unknown = true
                    continue
                }
                if !passes { failed.insert(cell) }
            }
            append(
                dimension,
                !failed.isEmpty ? .fail : (unknown ? .unknown : .pass),
                failed: failed,
                evidence: evidence,
                reasons: !failed.isEmpty ? ["threshold-or-invariant-failed"]
                    : (unknown ? ["required-measurement-missing"] : [])
            )
        }

        measuredResult(.productIdentityContinuity) { $0.productIdentityContinuous }
        measuredResult(.initialTaskHierarchy) { $0.primaryTaskWithinBoundary }
        measuredResult(.typographyHierarchy) {
            guard let inverted = $0.typographyHierarchyInverted,
                  let delta = $0.maximumTypographyRatioDelta else { return nil }
            return !inverted && delta <= thresholds.typographyRatioTolerance
        }
        measuredResult(.symmetryAndAlignment) {
            guard let lines = $0.symmetricTitleLineCountDelta,
                  let alignment = $0.maximumAlignmentOffsetLineHeights else { return nil }
            return lines == 0 && alignment <= thresholds.alignmentToleranceLineHeights
        }
        measuredResult(.spacingRhythmAndDensity) {
            guard let points = $0.maximumSpacingDeltaPoints,
                  let relative = $0.maximumSpacingRelativeDelta,
                  let occupancy = $0.contentOccupancyIncrease,
                  let undeclared = $0.undeclaredSemanticTokenCount else { return nil }
            let spacingPasses = points <= thresholds.spacingPointTolerance
                || relative <= thresholds.spacingRelativeTolerance
            return spacingPasses
                && occupancy <= thresholds.maximumOccupancyIncrease
                && undeclared == 0
        }
        measuredResult(.shapeLanguage) {
            guard let ratio = $0.maximumShapeRatioDelta,
                  let fit = $0.shapeContentFitPasses,
                  let undeclared = $0.undeclaredSemanticTokenCount else { return nil }
            return ratio <= thresholds.shapeRatioTolerance && fit && undeclared == 0
        }
        measuredResult(.collisionOcclusionAndSafeArea) {
            $0.newOcclusionPixels.map { $0 <= thresholds.maximumNewOcclusionPixels }
        }
        measuredResult(.responsiveComposition) { $0.responsiveCompositionPasses }
        measuredResult(.accessibilitySemanticsAndOperation) {
            $0.accessibilitySemanticsPasses
        }
        measuredResult(.localizationQualityAndSlotFit) {
            guard let quality = $0.localizationQualityPasses,
                  let fits = $0.localizedCopyFitsSlot else { return nil }
            return quality && fits
        }

        for debt in baseline.knownDebt where !debt.cellIDs.isDisjoint(with: required) {
            let candidateSeverity = candidate.debtSeverityByID[debt.id]
            let debtPasses = candidateSeverity.map {
                let directionPasses: Bool
                switch debt.direction {
                case .improveOnly:
                    directionPasses = $0 < debt.baselineSeverity
                case .notWorse:
                    directionPasses = $0 <= debt.baselineSeverity
                }
                return $0.isFinite
                    && $0 >= 0
                    && $0 <= debt.maximumInterimSeverity
                    && directionPasses
                    && (!debt.closureRequired || $0 == 0)
            } ?? false
            if !debtPasses,
               let index = results.firstIndex(where: { $0.dimension == debt.dimension }) {
                results[index].status = candidateSeverity == nil ? .unknown : .fail
                results[index].failedCellIDs.formUnion(debt.cellIDs.intersection(required))
                results[index].reasonCodes.insert(
                    candidateSeverity == nil ? "known-debt-unmeasured" : "known-debt-worsened"
                )
            }
        }

        let review = candidate.independentReview
        let batchIDs = Set(completeBatches.map(\.id))
        let orderedCells = required.sorted { $0.rawValue < $1.rawValue }
        let requiredBaselineCaptureIDs = Set(orderedCells.compactMap { baselineByCell?[$0]?.id })
        let requiredAttachedDigests = orderedCells.flatMap { cell -> [ContentDigest] in
            guard let baselineCapture = baselineByCell?[cell],
                  let candidateCapture = candidateByCell?[cell] else { return [] }
            return [baselineCapture.imageDigest, candidateCapture.imageDigest]
        }
        let expectedImageDecisions = requiredBaselineCaptureIDs.union(requiredCandidateIDs)
        let deterministicDigest = deterministicEvidenceDigest(
            baseline: baseline,
            candidate: candidate,
            thresholds: thresholds
        )
        let reviewPasses = review.map {
            $0.baselineID == baseline.id
                && $0.candidateSourceTree == candidate.sourceTree
                && $0.reviewer.lineageDigest != $0.workerLineageDigest
                && !$0.provider.isEmpty
                && !$0.model.isEmpty
                && !$0.contextDigest.rawValue.isEmpty
                && !$0.systemPromptDigest.rawValue.isEmpty
                && !$0.userPromptDigest.rawValue.isEmpty
                && !$0.evidenceBundleDigest.rawValue.isEmpty
                && $0.deterministicResultsDigest == deterministicDigest
                && $0.baselineCaptureIDs == requiredBaselineCaptureIDs
                && $0.candidateCaptureIDs == requiredCandidateIDs
                && $0.attachedImageDigests == requiredAttachedDigests
                && Set($0.perImageDecisions.keys) == expectedImageDecisions
                && $0.perImageDecisions.values.allSatisfy { $0 == .pass }
                && Set($0.pairDecisions.keys) == required
                && $0.pairDecisions.values.allSatisfy { $0 == .pass }
                && $0.blindToWorkerNarrative
                && $0.inspectedCellIDs == required
                && $0.batchReceiptIDs == batchIDs
                && !$0.rawResponseDigest.rawValue.isEmpty
                && $0.decision == .pass
        } ?? false
        append(
            .independentProductDesignVerdict,
            review == nil ? .unknown : (reviewPasses ? .pass : .fail),
            failed: reviewPasses ? [] : required,
            reasons: reviewPasses ? [] : ["independent-review-missing-incomplete-or-vetoed"]
        )

        let selected = requiredCandidateIDs.count
        let attached = Set(candidate.reviewBatches.flatMap(\.candidateCaptureIDs)).count
        let inspected = Set(completeBatches.flatMap(\.verdictRecordedCaptureIDs)).count
        return VisualGateResult(
            accepted: results.allSatisfy { !$0.status.vetoes },
            requiredCellIDs: required,
            baselineCaptureCount: required.compactMap { baselineByCell?[$0] }.count,
            candidateCaptureCount: required.compactMap { candidateByCell?[$0] }.count,
            selectedCaptureCount: selected,
            attachedCaptureCount: attached,
            inspectedCaptureCount: inspected,
            results: VisualGateDimension.allCases.map { dimension in
                results.first { $0.dimension == dimension }
                    ?? VisualGateDimensionResult(
                        dimension: dimension,
                        status: .notApplicable,
                        failedCellIDs: [],
                        evidenceReceiptIDs: [],
                        reasonCodes: []
                    )
            }
        )
    }
}
