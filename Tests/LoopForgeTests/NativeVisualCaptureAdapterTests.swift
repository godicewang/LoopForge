import Foundation
import XCTest
@testable import LoopForge

final class NativeVisualCaptureAdapterTests: XCTestCase {
    func testTrustedHarnessProducesAdapterComputedReceiptAndAttestation() async throws {
        let capturedAt = Date(timeIntervalSince1970: 2_000)
        let harness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: output()
        )
        let adapter = NativeVisualCaptureAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { capturedAt }
        )

        let result = try await adapter.capture(request())

        XCTAssertTrue(result.receipt.isComplete)
        XCTAssertEqual(result.receipt.cellID, VisualCellID("cell-primary"))
        XCTAssertEqual(result.receipt.sourceTree, ContentDigest("source-revision"))
        XCTAssertEqual(result.receipt.builtArtifact, ContentDigest("artifact-revision"))
        XCTAssertEqual(result.receipt.capturedAt, capturedAt)
        XCTAssertEqual(result.receipt.imageWidthPixels, 1)
        XCTAssertEqual(result.receipt.imageHeightPixels, 1)
        XCTAssertEqual(result.receipt.harnessIdentity, harness.identity)
        XCTAssertEqual(result.receipt.processExitCode, 0)
        XCTAssertEqual(result.receipt.imageDigest.rawValue.count, 64)
        XCTAssertEqual(result.encodedImageDigest.rawValue.count, 64)
        XCTAssertNotEqual(result.receipt.imageDigest, result.encodedImageDigest)
        XCTAssertEqual(result.cleanInstallEvidenceDigest.rawValue.count, 64)
        XCTAssertEqual(result.componentBoundaryArtifactDigest?.rawValue.count, 64)
        XCTAssertEqual(result.designTokenArtifactDigest?.rawValue.count, 64)
        XCTAssertTrue(result.receipt.id.rawValue.hasPrefix("native-capture-"))
        XCTAssertTrue(result.receipt.id.rawValue.hasSuffix(result.attestationDigest.rawValue))
    }

    func testUntrustedHarnessIsRejectedBeforeInvocation() async {
        let harness = StubNativeCaptureHarness(identity: "worker-selected", output: output())
        let adapter = NativeVisualCaptureAdapter(
            harness: harness,
            allowedHarnessIdentities: ["signed-native-harness-v1"]
        )

        await assertCaptureError(.untrustedHarness) {
            _ = try await adapter.capture(self.request())
        }
        let invocationCount = await harness.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func testHarnessFailureAndNonzeroExitFailClosed() async {
        let failedHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: output(),
            throwsOnCapture: true
        )
        let failedAdapter = adapter(failedHarness)
        await assertCaptureError(.harnessFailed) {
            _ = try await failedAdapter.capture(self.request())
        }

        var nonzero = output()
        nonzero.processExitCode = 7
        let nonzeroHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: nonzero
        )
        await assertCaptureError(.processFailed(7)) {
            _ = try await self.adapter(nonzeroHarness).capture(self.request())
        }
    }

    func testTraitAndDecodedViewportMismatchFailClosed() async {
        var wrongTraits = output()
        wrongTraits.observedTraits.locale = "fr-FR"
        let traitHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: wrongTraits
        )
        await assertCaptureError(.traitMismatch) {
            _ = try await self.adapter(traitHarness).capture(self.request())
        }

        var twoPixelRequest = request()
        twoPixelRequest.expectedTraits.viewportWidthPixels = 2
        var reportsTwoPixels = output()
        reportsTwoPixels.observedTraits.viewportWidthPixels = 2
        let dimensionHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: reportsTwoPixels
        )
        await assertCaptureError(.rasterDimensionsMismatch) {
            _ = try await self.adapter(dimensionHarness).capture(twoPixelRequest)
        }
    }

    func testInvalidOrOversizedRasterCannotBecomeEvidence() async {
        var invalid = output()
        invalid.encodedImage = Data("not-an-image".utf8)
        let invalidHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: invalid
        )
        await assertCaptureError(.invalidRaster) {
            _ = try await self.adapter(invalidHarness).capture(self.request())
        }

        let tinyLimits = NativeCaptureLimits(
            maximumEncodedImageBytes: 1,
            maximumRasterPixels: 1,
            maximumEvidenceBytes: 1_024,
            maximumDimensionPixels: 1
        )
        let validHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: output()
        )
        let limited = NativeVisualCaptureAdapter(
            harness: validHarness,
            allowedHarnessIdentities: [validHarness.identity],
            limits: tinyLimits
        )
        await assertCaptureError(.imageTooLarge) {
            _ = try await limited.capture(self.request())
        }
    }

    func testMalformedSemanticAndLifecycleEvidenceFailClosed() async {
        var malformedTree = output()
        malformedTree.accessibilityTree = Data("not-json".utf8)
        let treeHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: malformedTree
        )
        await assertCaptureError(.invalidAccessibilityTree) {
            _ = try await self.adapter(treeHarness).capture(self.request())
        }

        var scalarLifecycle = output()
        scalarLifecycle.cleanInstallEvidence = Data("true".utf8)
        let lifecycleHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: scalarLifecycle
        )
        await assertCaptureError(.invalidCleanInstallEvidence) {
            _ = try await self.adapter(lifecycleHarness).capture(self.request())
        }
    }

    func testTraceRequirementsCannotBeSatisfiedByMissingOrMalformedClaims() async {
        var missing = output()
        missing.componentBoundaryTrace = nil
        let missingHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: missing
        )
        await assertCaptureError(.missingComponentBoundaryTrace) {
            _ = try await self.adapter(missingHarness).capture(self.request())
        }

        var malformed = output()
        malformed.designTokenTrace = Data("[] trailing".utf8)
        let malformedHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: malformed
        )
        await assertCaptureError(.invalidDesignTokenTrace) {
            _ = try await self.adapter(malformedHarness).capture(self.request())
        }
    }

    func testCleanInstallBooleanWithoutEvidenceAndPreBoundaryClockAreRejected() async {
        var emptyLifecycle = output()
        emptyLifecycle.cleanInstallEvidence = Data()
        let lifecycleHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: emptyLifecycle
        )
        await assertCaptureError(.incompleteLifecycleEvidence) {
            _ = try await self.adapter(lifecycleHarness).capture(self.request())
        }

        let earlyHarness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: output()
        )
        let earlyAdapter = NativeVisualCaptureAdapter(
            harness: earlyHarness,
            allowedHarnessIdentities: [earlyHarness.identity],
            clock: { Date(timeIntervalSince1970: 999) }
        )
        await assertCaptureError(.capturePredatesAuthorityBoundary) {
            _ = try await earlyAdapter.capture(self.request())
        }
    }

    func testRequestAndAttestationDigestsChangeWithTrustedInputs() async throws {
        let harness = StubNativeCaptureHarness(
            identity: "signed-native-harness-v1",
            output: output()
        )
        let firstAdapter = NativeVisualCaptureAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
        let first = try await firstAdapter.capture(request())

        var changed = request()
        changed.navigationRecipe = Data(#"{"steps":["launch","alternate-route"]}"#.utf8)
        let secondAdapter = NativeVisualCaptureAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
        let second = try await secondAdapter.capture(changed)

        XCTAssertNotEqual(first.requestDigest, second.requestDigest)
        XCTAssertNotEqual(first.receipt.navigationRecipeDigest, second.receipt.navigationRecipeDigest)
        XCTAssertNotEqual(first.attestationDigest, second.attestationDigest)
        XCTAssertNotEqual(first.receipt.id, second.receipt.id)
    }

    private func adapter(_ harness: StubNativeCaptureHarness) -> NativeVisualCaptureAdapter {
        NativeVisualCaptureAdapter(
            harness: harness,
            allowedHarnessIdentities: [harness.identity],
            clock: { Date(timeIntervalSince1970: 2_000) }
        )
    }

    private func request() -> NativeCaptureRequest {
        NativeCaptureRequest(
            cellID: VisualCellID("cell-primary"),
            sourceTree: ContentDigest("source-revision"),
            builtArtifact: ContentDigest("artifact-revision"),
            captureProtocol: ContentDigest("native-capture-protocol-v1"),
            expectedTraits: traits(),
            navigationRecipe: Data(#"{"steps":["clean-install","launch"]}"#.utf8),
            notBefore: Date(timeIntervalSince1970: 1_000),
            requiresComponentBoundaryTrace: true,
            requiresDesignTokenTrace: true
        )
    }

    private func output() -> NativeCaptureHarnessOutput {
        NativeCaptureHarnessOutput(
            encodedImage: Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            )!,
            accessibilityTree: Data(#"{"role":"window","children":[]}"#.utf8),
            observedTraits: traits(),
            cleanInstallEvidence: Data(#"{"dataReset":true,"restartCount":1}"#.utf8),
            componentBoundaryTrace: Data(#"{"components":["root"]}"#.utf8),
            designTokenTrace: Data(#"{"tokens":["semantic.primary"]}"#.utf8),
            fullViewport: true,
            cleanInstall: true,
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

    private func assertCaptureError(
        _ expected: NativeVisualCaptureError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as NativeVisualCaptureError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum StubCaptureError: Error {
    case failed
}

private actor StubNativeCaptureHarness: NativeCaptureHarness {
    nonisolated let identity: String
    let output: NativeCaptureHarnessOutput
    let throwsOnCapture: Bool
    private(set) var invocationCount = 0

    init(
        identity: String,
        output: NativeCaptureHarnessOutput,
        throwsOnCapture: Bool = false
    ) {
        self.identity = identity
        self.output = output
        self.throwsOnCapture = throwsOnCapture
    }

    func capture(_ request: NativeCaptureRequest) async throws -> NativeCaptureHarnessOutput {
        invocationCount += 1
        if throwsOnCapture { throw StubCaptureError.failed }
        return output
    }
}
