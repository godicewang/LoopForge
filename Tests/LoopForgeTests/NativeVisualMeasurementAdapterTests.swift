import Foundation
import XCTest
@testable import LoopForge

final class NativeVisualMeasurementAdapterTests: XCTestCase {
    func testLiveCandidateCaptureProducesAdapterOwnedMeasurementReceipt() async throws {
        let request = try await measurementRequest()
        let harness = StubNativeVisualMeasurementHarness(
            identity: "signed-visual-measurer-v1",
            output: measurementOutput()
        )
        let adapter = NativeVisualMeasurementAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 200) }
        )

        let authority = try await adapter.measure(request)

        XCTAssertEqual(authority.baselineCaptureID, request.baselineCapture.id)
        XCTAssertEqual(authority.candidateCaptureID, request.candidateCapture.id)
        XCTAssertEqual(authority.protectedDimensions, request.protectedDimensions)
        XCTAssertEqual(authority.debtSeverityByID, [:])
        XCTAssertEqual(authority.measurement.cellID, VisualCellID("cell-primary"))
        XCTAssertEqual(authority.measurement.evidenceReceiptIDs.count, 1)
        XCTAssertTrue(
            authority.measurement.evidenceReceiptIDs[0].rawValue
                .hasPrefix("native-visual-measurement-")
        )
        XCTAssertEqual(authority.requestDigest.rawValue.count, 64)
        XCTAssertEqual(authority.rawEvidenceDigest.rawValue.count, 64)
        XCTAssertEqual(authority.attestationDigest.rawValue.count, 64)
        XCTAssertEqual(authority.measuredAt, Date(timeIntervalSince1970: 200))
        XCTAssertFalse(AuthorizedNativeCapture.self is any Codable.Type)
        XCTAssertFalse(AuthorizedNativeVisualMeasurement.self is any Codable.Type)
    }

    func testHarnessCannotMintEvidenceReceiptOrOmitProtectedMeasurement() async throws {
        let request = try await measurementRequest(dimensions: [.typographyHierarchy])
        var attemptedReceipt = measurementOutput()
        attemptedReceipt.measurement.evidenceReceiptIDs = [ReceiptID("harness-chosen")]
        await assertError(.harnessAttemptedToMintEvidenceReceipt) {
            _ = try await self.adapter(output: attemptedReceipt).measure(request)
        }

        var missing = measurementOutput()
        missing.measurement.maximumTypographyRatioDelta = nil
        await assertError(.invalidMeasurement("typography ratio delta invalid")) {
            _ = try await self.adapter(output: missing).measure(request)
        }
    }

    func testUntrustedHarnessAndMalformedEvidenceFailClosed() async throws {
        let request = try await measurementRequest()
        let untrusted = StubNativeVisualMeasurementHarness(
            identity: "worker-selected-measurer",
            output: measurementOutput()
        )
        let untrustedAdapter = NativeVisualMeasurementAdapter(
            harness: untrusted,
            allowedHarnessIdentities: ["signed-visual-measurer-v1"]
        )
        await assertError(.untrustedHarness) {
            _ = try await untrustedAdapter.measure(request)
        }
        let untrustedInvocationCount = await untrusted.invocationCount
        XCTAssertEqual(untrustedInvocationCount, 0)

        var malformed = measurementOutput()
        malformed.rawEvidence = Data("true".utf8)
        await assertError(.invalidRawEvidence) {
            _ = try await self.adapter(output: malformed).measure(request)
        }
    }

    func testTraitMismatchAndPreBoundaryMeasurementRejectBeforeAuthority() async throws {
        var request = try await measurementRequest()
        request.baselineCapture.traits.locale = "fr-FR"
        let harness = StubNativeVisualMeasurementHarness(
            identity: "signed-visual-measurer-v1",
            output: measurementOutput()
        )
        let invalidRequestAdapter = NativeVisualMeasurementAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity]
        )
        await assertError(.invalidRequest) {
            _ = try await invalidRequestAdapter.measure(request)
        }
        let invalidRequestInvocationCount = await harness.invocationCount
        XCTAssertEqual(invalidRequestInvocationCount, 0)

        let valid = try await measurementRequest()
        let earlyAdapter = NativeVisualMeasurementAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 149) }
        )
        await assertError(.measurementPredatesAuthorityBoundary) {
            _ = try await earlyAdapter.measure(valid)
        }
    }

    func testNonfiniteAndNegativeMaximumsCannotBecomeEvidence() async throws {
        let request = try await measurementRequest()
        var invalid = measurementOutput()
        invalid.measurement.maximumShapeRatioDelta = .infinity
        invalid.measurement.maximumSpacingDeltaPoints = -1
        await assertError(.invalidMeasurement(
            "shape ratio delta invalid; spacing point delta invalid"
        )) {
            _ = try await self.adapter(output: invalid).measure(request)
        }
    }

    private func adapter(
        output: NativeVisualMeasurementHarnessOutput
    ) -> NativeVisualMeasurementAdapter {
        let harness = StubNativeVisualMeasurementHarness(
            identity: "signed-visual-measurer-v1",
            output: output
        )
        return NativeVisualMeasurementAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 200) }
        )
    }

    private func measurementRequest(
        dimensions: Set<VisualGateDimension>? = nil
    ) async throws -> NativeVisualMeasurementRequest {
        let candidate = try await candidateCaptureAuthority()
        return NativeVisualMeasurementRequest(
            baselineCapture: baselineCapture(),
            candidateCaptureAuthority: candidate,
            protectedDimensions: dimensions ?? measurableDimensions,
            knownDebt: [],
            measurementProtocol: ContentDigest("deterministic-visual-measurement-v1"),
            notBefore: Date(timeIntervalSince1970: 100)
        )
    }

    private var measurableDimensions: Set<VisualGateDimension> {
        Set(VisualGateDimension.allCases.filter {
            $0 != .provenanceAndComparability
                && $0 != .independentProductDesignVerdict
        })
    }

    private func candidateCaptureAuthority() async throws -> AuthorizedNativeCapture {
        let harness = StubMeasurementCaptureHarness(
            identity: "signed-native-capture-v1",
            output: NativeCaptureHarnessOutput(
                encodedImage: onePixelPNG,
                accessibilityTree: Data(#"{"role":"window","children":[]}"#.utf8),
                observedTraits: traits(),
                cleanInstallEvidence: Data(#"{"reset":true}"#.utf8),
                componentBoundaryTrace: Data(#"{"components":["root"]}"#.utf8),
                designTokenTrace: Data(#"{"tokens":["semantic.primary"]}"#.utf8),
                fullViewport: true,
                cleanInstall: true,
                processExitCode: 0
            )
        )
        let adapter = NativeVisualCaptureAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 150) }
        )
        return try await adapter.captureAuthorized(NativeCaptureRequest(
            cellID: VisualCellID("cell-primary"),
            sourceTree: ContentDigest("candidate-source"),
            builtArtifact: ContentDigest("candidate-artifact"),
            captureProtocol: ContentDigest("native-capture-v1"),
            expectedTraits: traits(),
            navigationRecipe: Data(#"{"steps":["launch"]}"#.utf8),
            notBefore: Date(timeIntervalSince1970: 100),
            requiresComponentBoundaryTrace: true,
            requiresDesignTokenTrace: true
        ))
    }

    private func baselineCapture() -> NativeCaptureReceipt {
        NativeCaptureReceipt(
            id: NativeCaptureID("baseline-cell-primary"),
            cellID: VisualCellID("cell-primary"),
            sourceTree: ContentDigest("baseline-source"),
            builtArtifact: ContentDigest("baseline-artifact"),
            captureProtocol: ContentDigest("native-capture-v1"),
            traits: traits(),
            imageDigest: ContentDigest(String(repeating: "a", count: 64)),
            accessibilityTreeDigest: ContentDigest(String(repeating: "b", count: 64)),
            navigationRecipeDigest: ContentDigest(String(repeating: "c", count: 64)),
            componentBoundaryDigest: ContentDigest(String(repeating: "d", count: 64)),
            designTokenTraceDigest: ContentDigest(String(repeating: "e", count: 64)),
            imageWidthPixels: 1,
            imageHeightPixels: 1,
            fullViewport: true,
            cleanInstall: true,
            harnessIdentity: "signed-native-capture-v1",
            processExitCode: 0,
            capturedAt: Date(timeIntervalSince1970: 90)
        )
    }

    private func measurementOutput() -> NativeVisualMeasurementHarnessOutput {
        NativeVisualMeasurementHarnessOutput(
            measurement: VisualPairMeasurements(
                cellID: VisualCellID("cell-primary"),
                evidenceReceiptIDs: [],
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
            ),
            debtSeverityByID: [:],
            rawEvidence: Data(#"{"engine":"deterministic","version":1}"#.utf8),
            processExitCode: 0
        )
    }

    private func traits() -> VisualTraitSignature {
        VisualTraitSignature(
            deviceClass: "synthetic-desktop",
            viewportWidthPixels: 1,
            viewportHeightPixels: 1,
            scale: 1,
            operatingSystem: "synthetic-os-1",
            orientation: "landscape",
            locale: "en-US",
            calendar: "gregorian",
            layoutDirection: "left-to-right",
            appearance: "light",
            contrast: "standard",
            reducedMotion: false,
            boldText: false,
            contentSizeCategory: "large",
            fixtureDigest: ContentDigest("fixture")
        )
    }

    private var onePixelPNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }

    private func assertError(
        _ expected: NativeVisualMeasurementError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as NativeVisualMeasurementError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private actor StubNativeVisualMeasurementHarness: NativeVisualMeasurementHarness {
    nonisolated let identity: String
    let output: NativeVisualMeasurementHarnessOutput
    private(set) var invocationCount = 0

    init(identity: String, output: NativeVisualMeasurementHarnessOutput) {
        self.identity = identity
        self.output = output
    }

    func measure(
        _ request: NativeVisualMeasurementRequest
    ) async throws -> NativeVisualMeasurementHarnessOutput {
        invocationCount += 1
        return output
    }
}

private actor StubMeasurementCaptureHarness: NativeCaptureHarness {
    nonisolated let identity: String
    let output: NativeCaptureHarnessOutput

    init(identity: String, output: NativeCaptureHarnessOutput) {
        self.identity = identity
        self.output = output
    }

    func capture(_ request: NativeCaptureRequest) async throws -> NativeCaptureHarnessOutput {
        output
    }
}
