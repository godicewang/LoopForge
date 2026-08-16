import Foundation
import XCTest
@testable import LoopForge

final class DesignBaselineGateTests: XCTestCase {
    private let firstCell = VisualCellID("dashboard.standard.en-US.light")
    private let secondCell = VisualCellID("dashboard.compact.de-DE.dark")
    private let frozenAt = Date(timeIntervalSince1970: 100)
    private let mutationAt = Date(timeIntervalSince1970: 200)

    func testValidCandidatePassesEveryHardGate() {
        let result = DesignBaselineGate.evaluate(
            baseline: baseline(),
            candidate: candidate()
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.requiredCellIDs, [firstCell])
        XCTAssertEqual(result.baselineCaptureCount, 1)
        XCTAssertEqual(result.candidateCaptureCount, 1)
        XCTAssertEqual(result.selectedCaptureCount, 1)
        XCTAssertEqual(result.attachedCaptureCount, 1)
        XCTAssertEqual(result.inspectedCaptureCount, 1)
        XCTAssertTrue(result.results.allSatisfy { $0.status == .pass })
    }

    func testBaselineFrozenAfterMutationIsRejected() {
        var candidate = candidate()
        candidate.mutationStartedAt = frozenAt.addingTimeInterval(-1)

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testTraitMismatchIsRejected() {
        var candidate = candidate()
        candidate.captures[0].traits.locale = "fr-FR"

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testMissingCandidateCaptureBlocksAcceptance() {
        var candidate = candidate()
        candidate.captures = []

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testPrimaryTaskOutsideBoundaryFails() {
        var candidate = candidate()
        candidate.measurements[0].primaryTaskWithinBoundary = false

        assertFails(candidate, dimension: .initialTaskHierarchy)
    }

    func testOnePixelOfNewOcclusionFails() {
        var candidate = candidate()
        candidate.measurements[0].newOcclusionPixels = 1

        assertFails(candidate, dimension: .collisionOcclusionAndSafeArea)
    }

    func testSymmetricTitleLineCountMismatchFails() {
        var candidate = candidate()
        candidate.measurements[0].symmetricTitleLineCountDelta = 1

        assertFails(candidate, dimension: .symmetryAndAlignment)
    }

    func testTypographyHierarchyInversionFails() {
        var candidate = candidate()
        candidate.measurements[0].typographyHierarchyInverted = true

        assertFails(candidate, dimension: .typographyHierarchy)
    }

    func testTypographyRatioOutsideToleranceFails() {
        var candidate = candidate()
        candidate.measurements[0].maximumTypographyRatioDelta = 0.100_001

        assertFails(candidate, dimension: .typographyHierarchy)
    }

    func testUnchangedShapeRatioCannotHideOverfilledContent() {
        var candidate = candidate()
        candidate.measurements[0].maximumShapeRatioDelta = 0
        candidate.measurements[0].shapeContentFitPasses = false

        assertFails(candidate, dimension: .shapeLanguage)
    }

    func testUndeclaredSemanticTokenFailsShapeAndSpacing() {
        var candidate = candidate()
        candidate.measurements[0].undeclaredSemanticTokenCount = 1
        let result = DesignBaselineGate.evaluate(baseline: baseline(), candidate: candidate)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(status(.shapeLanguage, in: result), .fail)
        XCTAssertEqual(status(.spacingRhythmAndDensity, in: result), .fail)
    }

    func testLocalizedCopyOverflowFails() {
        var candidate = candidate()
        candidate.measurements[0].localizedCopyFitsSlot = false

        assertFails(candidate, dimension: .localizationQualityAndSlotFit)
    }

    func testAccessibilityPassCannotHideCompositionFailure() {
        var candidate = candidate()
        candidate.measurements[0].accessibilitySemanticsPasses = true
        candidate.measurements[0].responsiveCompositionPasses = false

        assertFails(candidate, dimension: .responsiveComposition)
    }

    func testCompositionPassCannotHideAccessibilityFailure() {
        var candidate = candidate()
        candidate.measurements[0].responsiveCompositionPasses = true
        candidate.measurements[0].accessibilitySemanticsPasses = false

        assertFails(candidate, dimension: .accessibilitySemanticsAndOperation)
    }

    func testKnownDebtImprovementPassesDespiteLargePerceptualDifference() {
        var baseline = baseline()
        let debt = DesignDebt(
            id: DesignDebtID("legacy-density"),
            dimension: .spacingRhythmAndDensity,
            cellIDs: [firstCell],
            baselineSeverity: 0.8,
            maximumInterimSeverity: 0.79,
            direction: .improveOnly,
            closureRequired: false,
            evidenceDigest: ContentDigest("historical-density-evidence")
        )
        baseline.knownDebt = [debt]
        var candidate = candidate()
        candidate.debtSeverityByID[debt.id] = 0.5
        candidate.measurements[0].perceptualDifference = 0.95
        refreshReview(in: &candidate, baseline: baseline)

        XCTAssertTrue(DesignBaselineGate.evaluate(baseline: baseline, candidate: candidate).accepted)
    }

    func testKnownDebtCannotRemainFlatWhenMarkedImproveOnly() {
        var baseline = baseline()
        let debt = DesignDebt(
            id: DesignDebtID("legacy-density"),
            dimension: .spacingRhythmAndDensity,
            cellIDs: [firstCell],
            baselineSeverity: 0.8,
            maximumInterimSeverity: 0.8,
            direction: .improveOnly,
            closureRequired: false,
            evidenceDigest: ContentDigest("historical-density-evidence")
        )
        baseline.knownDebt = [debt]
        var candidate = candidate()
        candidate.debtSeverityByID[debt.id] = 0.8

        assertFails(candidate, against: baseline, dimension: .spacingRhythmAndDensity)
    }

    func testKnownDebtWorseningFails() {
        var baseline = baseline()
        let debt = DesignDebt(
            id: DesignDebtID("legacy-shape"),
            dimension: .shapeLanguage,
            cellIDs: [firstCell],
            baselineSeverity: 0.2,
            maximumInterimSeverity: 0.2,
            direction: .notWorse,
            closureRequired: false,
            evidenceDigest: ContentDigest("historical-shape-evidence")
        )
        baseline.knownDebt = [debt]
        var candidate = candidate()
        candidate.debtSeverityByID[debt.id] = 0.21

        assertFails(candidate, against: baseline, dimension: .shapeLanguage)
    }

    func testIncompleteExtraReviewBatchFailsExactCountGate() {
        var candidate = candidate()
        candidate.reviewBatches.append(VisualReviewBatchReceipt(
            id: ReceiptID("incomplete-batch"),
            candidateCaptureIDs: [NativeCaptureID("unattached-capture")],
            verdictRecordedCaptureIDs: []
        ))

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testDuplicateCaptureAcrossReviewBatchesFails() {
        var candidate = candidate()
        candidate.reviewBatches.append(VisualReviewBatchReceipt(
            id: ReceiptID("duplicate-batch"),
            candidateCaptureIDs: [candidate.captures[0].id],
            verdictRecordedCaptureIDs: [candidate.captures[0].id]
        ))

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testBlindIndependentReviewerVetoIsPreserved() {
        var candidate = candidate()
        candidate.independentReview?.decision = .fail

        assertFails(candidate, dimension: .independentProductDesignVerdict)
    }

    func testReviewerFromWorkerLineageFailsIndependence() {
        var candidate = candidate()
        candidate.independentReview?.reviewer.lineageDigest = ContentDigest("worker-lineage")

        assertFails(candidate, dimension: .independentProductDesignVerdict)
    }

    func testReviewExpiresWhenCandidateImageChanges() {
        var candidate = candidate()
        candidate.captures[0].imageDigest = ContentDigest("replacement-image")

        assertFails(candidate, dimension: .independentProductDesignVerdict)
    }

    func testReviewExpiresWhenDeterministicMeasurementChanges() {
        var candidate = candidate()
        candidate.measurements[0].contentOccupancyIncrease = 0.02

        assertFails(candidate, dimension: .independentProductDesignVerdict)
    }

    func testMissingPerImageVerdictFailsReview() {
        var candidate = candidate()
        candidate.independentReview?.perImageDecisions.removeValue(
            forKey: NativeCaptureID("baseline-\(firstCell.rawValue)")
        )

        assertFails(candidate, dimension: .independentProductDesignVerdict)
    }

    func testAttachedImageOrderIsPartOfReviewReceipt() {
        var candidate = candidate()
        candidate.independentReview?.attachedImageDigests.reverse()

        assertFails(candidate, dimension: .independentProductDesignVerdict)
    }

    func testGlobalTokenMutationExpandsToEveryContractedCell() {
        let candidate = candidate(globalTokenMutation: true)
        let result = DesignBaselineGate.evaluate(baseline: baseline(), candidate: candidate)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.requiredCellIDs, [firstCell, secondCell])
        XCTAssertEqual(result.selectedCaptureCount, 2)
    }

    func testGlobalTokenMutationCannotForgeSmallerBaselineMatrix() {
        var candidate = candidate(globalTokenMutation: true)
        candidate.mutationManifest.allBaselineCellIDs = [firstCell]
        candidate.captures = [candidate.captures[0]]
        candidate.measurements = [candidate.measurements[0]]
        candidate.reviewBatches = batches(for: candidate.captures)

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testStaleCandidateRevisionFails() {
        var candidate = candidate()
        candidate.captures[0].sourceTree = ContentDigest("stale-source")

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testUnauthorizedAmendmentFails() {
        var candidate = candidate()
        candidate.amendments = [DesignBaselineAmendment(
            id: ReceiptID("amendment"),
            baselineID: DesignBaselineID("design-baseline"),
            candidateSourceTree: ContentDigest("candidate-source"),
            dimensions: [.typographyHierarchy],
            authority: actor("worker", lineage: "worker-lineage"),
            authorityRole: "worker",
            reasonDigest: ContentDigest("change-the-test"),
            issuedAt: mutationAt.addingTimeInterval(1)
        )]

        assertFails(candidate, dimension: .provenanceAndComparability)
    }

    func testMissingMeasurementProducesUnknownVeto() {
        var candidate = candidate()
        candidate.measurements[0].maximumShapeRatioDelta = nil
        let result = DesignBaselineGate.evaluate(baseline: baseline(), candidate: candidate)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(status(.shapeLanguage, in: result), .unknown)
    }

    func testSingleHardVetoCannotBeAveragedAwayByElevenPasses() {
        var candidate = candidate()
        candidate.measurements[0].maximumTypographyRatioDelta = 0.5
        refreshReview(in: &candidate, baseline: baseline())
        let result = DesignBaselineGate.evaluate(baseline: baseline(), candidate: candidate)

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.results.filter { $0.status == .fail }.count, 1)
        XCTAssertEqual(status(.typographyHierarchy, in: result), .fail)
    }

    func testInvalidThresholdsFailClosed() {
        var thresholds = VisualGateThresholds.platformDefault
        thresholds.shapeRatioTolerance = .nan

        let result = DesignBaselineGate.evaluate(
            baseline: baseline(),
            candidate: candidate(),
            thresholds: thresholds
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(status(.provenanceAndComparability, in: result), .fail)
    }

    func testReviewBatchPlannerIsDeterministicAndComplete() {
        let captures: Set<NativeCaptureID> = [
            NativeCaptureID("capture-c"),
            NativeCaptureID("capture-a"),
            NativeCaptureID("capture-b"),
            NativeCaptureID("capture-d")
        ]
        let planned = VisualReviewBatchPlanner.plan(
            candidateCaptureIDs: captures,
            maximumImagesPerBatch: 3
        )

        XCTAssertEqual(planned, [
            [NativeCaptureID("capture-a"), NativeCaptureID("capture-b"), NativeCaptureID("capture-c")],
            [NativeCaptureID("capture-d")]
        ])
        XCTAssertEqual(Set(planned.flatMap { $0 }), captures)
    }

    func testDeterministicEvidenceDigestIgnoresCollectionOrdering() {
        let firstBaseline = baseline()
        var secondBaseline = firstBaseline
        secondBaseline.captures.reverse()
        secondBaseline.protectedInvariants.reverse()

        var firstCandidate = candidate(globalTokenMutation: true)
        firstCandidate.measurements[0].evidenceReceiptIDs.append(ReceiptID("geometry-secondary"))
        var secondCandidate = firstCandidate
        secondCandidate.captures.reverse()
        secondCandidate.measurements.reverse()
        secondCandidate.measurements[1].evidenceReceiptIDs.reverse()

        XCTAssertEqual(
            DesignBaselineGate.deterministicEvidenceDigest(
                baseline: firstBaseline,
                candidate: firstCandidate
            ),
            DesignBaselineGate.deterministicEvidenceDigest(
                baseline: secondBaseline,
                candidate: secondCandidate
            )
        )
    }

    func testHistoricalDegradationSampleFailsTypographySymmetryDensityAndOcclusion() {
        // Numeric values are retained only as a regression specimen from the
        // forensic corpus. Product policy remains domain- and app-neutral.
        var candidate = candidate()
        candidate.measurements[0].typographyHierarchyInverted = true
        candidate.measurements[0].maximumTypographyRatioDelta = 0.42
        candidate.measurements[0].symmetricTitleLineCountDelta = 2
        candidate.measurements[0].maximumAlignmentOffsetLineHeights = 1.4
        candidate.measurements[0].maximumSpacingDeltaPoints = 9
        candidate.measurements[0].maximumSpacingRelativeDelta = 0.37
        candidate.measurements[0].contentOccupancyIncrease = 0.31
        candidate.measurements[0].newOcclusionPixels = 18

        let result = DesignBaselineGate.evaluate(baseline: baseline(), candidate: candidate)
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(status(.typographyHierarchy, in: result), .fail)
        XCTAssertEqual(status(.symmetryAndAlignment, in: result), .fail)
        XCTAssertEqual(status(.spacingRhythmAndDensity, in: result), .fail)
        XCTAssertEqual(status(.collisionOcclusionAndSafeArea, in: result), .fail)
    }

    private func baseline() -> DesignBaselineBundle {
        let cells: Set<VisualCellID> = [firstCell, secondCell]
        let measuredDimensions = VisualGateDimension.allCases.filter {
            $0 != .provenanceAndComparability
                && $0 != .independentProductDesignVerdict
        }
        let authorityActor = actor("design-authority", lineage: "design-lineage")
        return DesignBaselineBundle(
            id: DesignBaselineID("design-baseline"),
            contractID: TaskContractID("contract"),
            protectedBaselineID: BaselineID("protected-design"),
            requirementIDs: [RequirementID("visual-quality")],
            sourceTree: ContentDigest("baseline-source"),
            builtArtifact: ContentDigest("baseline-artifact"),
            captureProtocol: ContentDigest("native-capture-v1"),
            designTokenSnapshot: ContentDigest("tokens-v1"),
            semanticSurfaceManifest: ContentDigest("surfaces-v1"),
            captures: cells.sorted(by: { $0.rawValue < $1.rawValue }).map {
                capture(cell: $0, baseline: true)
            },
            protectedInvariants: measuredDimensions.map {
                DesignInvariant(id: "invariant-\($0.rawValue)", dimension: $0, cellIDs: cells)
            },
            knownDebt: [],
            authority: DesignAuthorityReceipt(
                id: ReceiptID("authority-receipt"),
                baselineID: DesignBaselineID("design-baseline"),
                authority: authorityActor,
                authorityRole: "productDesignAuthority",
                issuedAt: frozenAt.addingTimeInterval(-20)
            ),
            frozenAt: frozenAt
        )
    }

    private func candidate(globalTokenMutation: Bool = false) -> VisualCandidateBundle {
        let required: Set<VisualCellID> = globalTokenMutation
            ? [firstCell, secondCell]
            : [firstCell]
        let captures = required.sorted(by: { $0.rawValue < $1.rawValue }).map {
            capture(cell: $0, baseline: false)
        }
        let batches = batches(for: captures)
        var value = VisualCandidateBundle(
            sourceTree: ContentDigest("candidate-source"),
            builtArtifact: ContentDigest("candidate-artifact"),
            mutationStartedAt: mutationAt,
            captures: captures,
            measurements: required.sorted(by: { $0.rawValue < $1.rawValue }).map(measurement),
            mutationManifest: VisualMutationManifest(
                directlyAffectedCellIDs: [firstCell],
                allBaselineCellIDs: [firstCell, secondCell],
                globalSemanticTokenMutation: globalTokenMutation,
                touchedTokenFamilies: globalTokenMutation ? ["typography"] : []
            ),
            debtSeverityByID: [:],
            reviewBatches: batches,
            independentReview: nil,
            amendments: []
        )
        let digest = DesignBaselineGate.deterministicEvidenceDigest(
            baseline: baseline(),
            candidate: value
        )
        value.independentReview = review(
            required: required,
            batchIDs: Set(batches.map(\.id)),
            deterministicDigest: digest
        )
        return value
    }

    private func capture(cell: VisualCellID, baseline: Bool) -> NativeCaptureReceipt {
        NativeCaptureReceipt(
            id: NativeCaptureID("\(baseline ? "baseline" : "candidate")-\(cell.rawValue)"),
            cellID: cell,
            sourceTree: ContentDigest(baseline ? "baseline-source" : "candidate-source"),
            builtArtifact: ContentDigest(baseline ? "baseline-artifact" : "candidate-artifact"),
            captureProtocol: ContentDigest("native-capture-v1"),
            traits: traits(for: cell),
            imageDigest: ContentDigest("image-\(baseline ? "before" : "after")-\(cell.rawValue)"),
            accessibilityTreeDigest: ContentDigest("ax-\(baseline ? "before" : "after")-\(cell.rawValue)"),
            navigationRecipeDigest: ContentDigest("navigation-recipe-v1"),
            componentBoundaryDigest: ContentDigest("component-boundaries-\(cell.rawValue)"),
            designTokenTraceDigest: ContentDigest("token-trace-\(cell.rawValue)"),
            imageWidthPixels: traits(for: cell).viewportWidthPixels,
            imageHeightPixels: traits(for: cell).viewportHeightPixels,
            fullViewport: true,
            cleanInstall: true,
            harnessIdentity: "native-ui-harness",
            processExitCode: 0,
            capturedAt: baseline
                ? frozenAt.addingTimeInterval(-10)
                : mutationAt.addingTimeInterval(10)
        )
    }

    private func traits(for cell: VisualCellID) -> VisualTraitSignature {
        let compact = cell == secondCell
        return VisualTraitSignature(
            deviceClass: compact ? "compact" : "standard",
            viewportWidthPixels: compact ? 900 : 1440,
            viewportHeightPixels: compact ? 700 : 1000,
            scale: 2,
            operatingSystem: "macOS-fixture",
            orientation: "landscape",
            locale: compact ? "de-DE" : "en-US",
            calendar: "gregorian",
            layoutDirection: "leftToRight",
            appearance: compact ? "dark" : "light",
            contrast: "normal",
            reducedMotion: false,
            boldText: false,
            contentSizeCategory: "large",
            fixtureDigest: ContentDigest("fixture-v1")
        )
    }

    private func measurement(_ cell: VisualCellID) -> VisualPairMeasurements {
        VisualPairMeasurements(
            cellID: cell,
            evidenceReceiptIDs: [ReceiptID("geometry-\(cell.rawValue)")],
            productIdentityContinuous: true,
            primaryTaskWithinBoundary: true,
            typographyHierarchyInverted: false,
            maximumTypographyRatioDelta: 0.02,
            symmetricTitleLineCountDelta: 0,
            maximumAlignmentOffsetLineHeights: 0.1,
            maximumSpacingDeltaPoints: 0.5,
            maximumSpacingRelativeDelta: 0.02,
            contentOccupancyIncrease: 0.01,
            maximumShapeRatioDelta: 0.02,
            shapeContentFitPasses: true,
            undeclaredSemanticTokenCount: 0,
            newOcclusionPixels: 0,
            responsiveCompositionPasses: true,
            accessibilitySemanticsPasses: true,
            localizationQualityPasses: true,
            localizedCopyFitsSlot: true,
            perceptualDifference: 0.01
        )
    }

    private func batches(for captures: [NativeCaptureReceipt]) -> [VisualReviewBatchReceipt] {
        VisualReviewBatchPlanner.plan(
            candidateCaptureIDs: Set(captures.map(\.id)),
            maximumImagesPerBatch: 3
        ).enumerated().map { index, captureIDs in
            VisualReviewBatchReceipt(
                id: ReceiptID("batch-\(index)"),
                candidateCaptureIDs: captureIDs,
                verdictRecordedCaptureIDs: Set(captureIDs)
            )
        }
    }

    private func review(
        required: Set<VisualCellID>,
        batchIDs: Set<ReceiptID>,
        deterministicDigest: ContentDigest
    ) -> IndependentVisualReviewReceipt {
        let orderedCells = required.sorted { $0.rawValue < $1.rawValue }
        let baselineCaptureIDs = Set(orderedCells.map {
            NativeCaptureID("baseline-\($0.rawValue)")
        })
        let candidateCaptureIDs = Set(orderedCells.map {
            NativeCaptureID("candidate-\($0.rawValue)")
        })
        let allCaptureIDs = baselineCaptureIDs.union(candidateCaptureIDs)
        return IndependentVisualReviewReceipt(
            id: ReceiptID("independent-review"),
            reviewer: actor("reviewer", lineage: "reviewer-lineage"),
            workerLineageDigest: ContentDigest("worker-lineage"),
            provider: "fixture-provider",
            model: "fixture-model",
            contextDigest: ContentDigest("review-context"),
            systemPromptDigest: ContentDigest("review-system-prompt"),
            userPromptDigest: ContentDigest("review-user-prompt"),
            evidenceBundleDigest: ContentDigest("evidence-bundle"),
            deterministicResultsDigest: deterministicDigest,
            baselineID: DesignBaselineID("design-baseline"),
            candidateSourceTree: ContentDigest("candidate-source"),
            baselineCaptureIDs: baselineCaptureIDs,
            candidateCaptureIDs: candidateCaptureIDs,
            attachedImageDigests: orderedCells.flatMap {
                [
                    ContentDigest("image-before-\($0.rawValue)"),
                    ContentDigest("image-after-\($0.rawValue)")
                ]
            },
            perImageDecisions: Dictionary(uniqueKeysWithValues:
                allCaptureIDs.map { ($0, VisualReviewDecision.pass) }
            ),
            pairDecisions: Dictionary(uniqueKeysWithValues:
                required.map { ($0, VisualReviewDecision.pass) }
            ),
            inspectedCellIDs: required,
            batchReceiptIDs: batchIDs,
            blindToWorkerNarrative: true,
            decision: .pass,
            rawResponseDigest: ContentDigest("raw-review-response")
        )
    }

    private func actor(_ id: String, lineage: String) -> ActorIdentity {
        ActorIdentity(
            id: ActorID(id),
            role: "test",
            lineageDigest: ContentDigest(lineage)
        )
    }

    private func refreshReview(
        in candidate: inout VisualCandidateBundle,
        baseline: DesignBaselineBundle
    ) {
        candidate.independentReview = review(
            required: candidate.mutationManifest.requiredCellIDs,
            batchIDs: Set(candidate.reviewBatches.map(\.id)),
            deterministicDigest: DesignBaselineGate.deterministicEvidenceDigest(
                baseline: baseline,
                candidate: candidate
            )
        )
    }

    private func status(
        _ dimension: VisualGateDimension,
        in result: VisualGateResult
    ) -> VisualGateStatus? {
        result.results.first { $0.dimension == dimension }?.status
    }

    private func assertFails(
        _ candidate: VisualCandidateBundle,
        against baseline: DesignBaselineBundle? = nil,
        dimension: VisualGateDimension,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = DesignBaselineGate.evaluate(
            baseline: baseline ?? self.baseline(),
            candidate: candidate
        )
        XCTAssertFalse(result.accepted, file: file, line: line)
        XCTAssertTrue(result.failingDimensions.contains(dimension), file: file, line: line)
    }
}
