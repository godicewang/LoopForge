import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct NativeCaptureLimits: Codable, Hashable, Sendable {
    var maximumEncodedImageBytes: Int
    var maximumRasterPixels: Int
    var maximumEvidenceBytes: Int
    var maximumDimensionPixels: Int

    static let platformDefault = NativeCaptureLimits(
        maximumEncodedImageBytes: 40 * 1_024 * 1_024,
        maximumRasterPixels: 40_000_000,
        maximumEvidenceBytes: 16 * 1_024 * 1_024,
        maximumDimensionPixels: 16_384
    )

    var isValid: Bool {
        maximumEncodedImageBytes > 0
            && maximumRasterPixels > 0
            && maximumEvidenceBytes > 0
            && maximumDimensionPixels > 0
    }
}

/// The orchestrator supplies provenance and the exact environment it expects.
/// The harness supplies only observations; it cannot choose receipt digests,
/// source revisions, capture time, or the visual cell receiving the evidence.
struct NativeCaptureRequest: Codable, Hashable, Sendable {
    var cellID: VisualCellID
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var captureProtocol: ContentDigest
    var expectedTraits: VisualTraitSignature
    var navigationRecipe: Data
    var notBefore: Date
    var requiresComponentBoundaryTrace: Bool
    var requiresDesignTokenTrace: Bool

    var isValid: Bool {
        !cellID.rawValue.isEmpty
            && !sourceTree.rawValue.isEmpty
            && !builtArtifact.rawValue.isEmpty
            && !captureProtocol.rawValue.isEmpty
            && expectedTraits.hasValidViewport
            && !navigationRecipe.isEmpty
            && notBefore.timeIntervalSince1970.isFinite
    }
}

struct NativeCaptureHarnessOutput: Hashable, Sendable {
    var encodedImage: Data
    var accessibilityTree: Data
    var observedTraits: VisualTraitSignature
    var cleanInstallEvidence: Data
    var componentBoundaryTrace: Data?
    var designTokenTrace: Data?
    var fullViewport: Bool
    var cleanInstall: Bool
    var processExitCode: Int32
}

protocol NativeCaptureHarness: Sendable {
    var identity: String { get }
    func capture(_ request: NativeCaptureRequest) async throws -> NativeCaptureHarnessOutput
}

struct AttestedNativeCapture: Codable, Hashable, Sendable {
    var receipt: NativeCaptureReceipt
    var requestDigest: ContentDigest
    var encodedImageDigest: ContentDigest
    var cleanInstallEvidenceDigest: ContentDigest
    var componentBoundaryArtifactDigest: ContentDigest?
    var designTokenArtifactDigest: ContentDigest?
    var attestationDigest: ContentDigest
}

/// Live, non-serializable authority proving that one exact capture was issued
/// by `NativeVisualCaptureAdapter` in this process. Durable attestation bytes
/// remain replayable evidence, but decoding them cannot recreate this value.
struct AuthorizedNativeCapture: Sendable {
    let attestation: AttestedNativeCapture
    let encodedImage: Data
    let accessibilityTree: Data
    let cleanInstallEvidence: Data
    let componentBoundaryTrace: Data?
    let designTokenTrace: Data?

    fileprivate init(
        attestation: AttestedNativeCapture,
        encodedImage: Data,
        accessibilityTree: Data,
        cleanInstallEvidence: Data,
        componentBoundaryTrace: Data?,
        designTokenTrace: Data?
    ) {
        self.attestation = attestation
        self.encodedImage = encodedImage
        self.accessibilityTree = accessibilityTree
        self.cleanInstallEvidence = cleanInstallEvidence
        self.componentBoundaryTrace = componentBoundaryTrace
        self.designTokenTrace = designTokenTrace
    }
}

enum NativeVisualCaptureError: Error, Equatable {
    case invalidLimits
    case invalidRequest
    case untrustedHarness
    case harnessFailed
    case capturePredatesAuthorityBoundary
    case processFailed(Int32)
    case incompleteLifecycleEvidence
    case traitMismatch
    case imageTooLarge
    case evidenceTooLarge
    case invalidRaster
    case rasterDimensionsMismatch
    case invalidAccessibilityTree
    case invalidCleanInstallEvidence
    case invalidComponentBoundaryTrace
    case invalidDesignTokenTrace
    case missingComponentBoundaryTrace
    case missingDesignTokenTrace
    case digestConstructionFailed
}

/// Converts one allow-listed native harness observation into a receipt. This
/// type deliberately accepts bytes rather than artifact paths, preventing a
/// worker from swapping a symlink or rewriting evidence after validation.
actor NativeVisualCaptureAdapter {
    private struct RequestDigestEnvelope: Encodable {
        var cellID: VisualCellID
        var sourceTree: ContentDigest
        var builtArtifact: ContentDigest
        var captureProtocol: ContentDigest
        var expectedTraits: VisualTraitSignature
        var navigationRecipeDigest: ContentDigest
        var notBefore: Date
        var requiresComponentBoundaryTrace: Bool
        var requiresDesignTokenTrace: Bool
        var harnessIdentity: String
    }

    private struct RasterEvidence: Sendable {
        var width: Int
        var height: Int
        var pixelDigest: ContentDigest
    }

    private let harness: any NativeCaptureHarness
    private let allowedHarnessIdentities: Set<String>
    private let limits: NativeCaptureLimits
    private let clock: @Sendable () -> Date

    init(
        harness: any NativeCaptureHarness,
        allowedHarnessIdentities: Set<String>,
        limits: NativeCaptureLimits = .platformDefault,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.harness = harness
        self.allowedHarnessIdentities = allowedHarnessIdentities
        self.limits = limits
        self.clock = clock
    }

    func capture(_ request: NativeCaptureRequest) async throws -> AttestedNativeCapture {
        try await performCapture(request).attestation
    }

    private func performCapture(
        _ request: NativeCaptureRequest
    ) async throws -> (
        attestation: AttestedNativeCapture,
        output: NativeCaptureHarnessOutput
    ) {
        guard limits.isValid else { throw NativeVisualCaptureError.invalidLimits }
        guard request.isValid else { throw NativeVisualCaptureError.invalidRequest }
        let harnessIdentity = harness.identity
        guard !harnessIdentity.isEmpty,
              allowedHarnessIdentities.contains(harnessIdentity) else {
            throw NativeVisualCaptureError.untrustedHarness
        }

        let output: NativeCaptureHarnessOutput
        do {
            output = try await harness.capture(request)
        } catch {
            throw NativeVisualCaptureError.harnessFailed
        }
        let capturedAt = clock()
        guard capturedAt >= request.notBefore else {
            throw NativeVisualCaptureError.capturePredatesAuthorityBoundary
        }
        guard output.processExitCode == 0 else {
            throw NativeVisualCaptureError.processFailed(output.processExitCode)
        }
        guard output.fullViewport,
              output.cleanInstall,
              !output.cleanInstallEvidence.isEmpty else {
            throw NativeVisualCaptureError.incompleteLifecycleEvidence
        }
        guard output.observedTraits == request.expectedTraits else {
            throw NativeVisualCaptureError.traitMismatch
        }
        guard output.encodedImage.count <= limits.maximumEncodedImageBytes else {
            throw NativeVisualCaptureError.imageTooLarge
        }

        let allEvidence = [
            output.accessibilityTree,
            output.cleanInstallEvidence,
            output.componentBoundaryTrace ?? Data(),
            output.designTokenTrace ?? Data()
        ]
        guard allEvidence.allSatisfy({ $0.count <= limits.maximumEvidenceBytes }) else {
            throw NativeVisualCaptureError.evidenceTooLarge
        }
        guard Self.isJSONObjectOrArray(output.accessibilityTree) else {
            throw NativeVisualCaptureError.invalidAccessibilityTree
        }
        guard Self.isJSONObjectOrArray(output.cleanInstallEvidence) else {
            throw NativeVisualCaptureError.invalidCleanInstallEvidence
        }
        if let trace = output.componentBoundaryTrace,
           !Self.isJSONObjectOrArray(trace) {
            throw NativeVisualCaptureError.invalidComponentBoundaryTrace
        }
        if let trace = output.designTokenTrace,
           !Self.isJSONObjectOrArray(trace) {
            throw NativeVisualCaptureError.invalidDesignTokenTrace
        }
        if request.requiresComponentBoundaryTrace,
           output.componentBoundaryTrace == nil {
            throw NativeVisualCaptureError.missingComponentBoundaryTrace
        }
        if request.requiresDesignTokenTrace,
           output.designTokenTrace == nil {
            throw NativeVisualCaptureError.missingDesignTokenTrace
        }

        let raster = try Self.rasterEvidence(
            output.encodedImage,
            limits: limits
        )
        guard raster.width == request.expectedTraits.viewportWidthPixels,
              raster.height == request.expectedTraits.viewportHeightPixels else {
            throw NativeVisualCaptureError.rasterDimensionsMismatch
        }

        let navigationRecipeDigest = Self.digest(request.navigationRecipe)
        let accessibilityDigest = Self.digest(output.accessibilityTree)
        let encodedImageDigest = Self.digest(output.encodedImage)
        let lifecycleDigest = Self.digest(output.cleanInstallEvidence)
        let componentDigest = output.componentBoundaryTrace.map(Self.digest)
        let tokenDigest = output.designTokenTrace.map(Self.digest)
        let requestEnvelope = RequestDigestEnvelope(
            cellID: request.cellID,
            sourceTree: request.sourceTree,
            builtArtifact: request.builtArtifact,
            captureProtocol: request.captureProtocol,
            expectedTraits: request.expectedTraits,
            navigationRecipeDigest: navigationRecipeDigest,
            notBefore: request.notBefore,
            requiresComponentBoundaryTrace: request.requiresComponentBoundaryTrace,
            requiresDesignTokenTrace: request.requiresDesignTokenTrace,
            harnessIdentity: harnessIdentity
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let requestData = try? encoder.encode(requestEnvelope) else {
            throw NativeVisualCaptureError.digestConstructionFailed
        }
        let requestDigest = Self.digest(requestData)
        let attestationDigest = Self.framedDigest([
            Data(requestDigest.rawValue.utf8),
            Data(raster.pixelDigest.rawValue.utf8),
            Data(encodedImageDigest.rawValue.utf8),
            Data(accessibilityDigest.rawValue.utf8),
            Data(lifecycleDigest.rawValue.utf8),
            Data((componentDigest?.rawValue ?? "").utf8),
            Data((tokenDigest?.rawValue ?? "").utf8),
            Data(String(capturedAt.timeIntervalSince1970).utf8)
        ])
        let captureID = NativeCaptureID("native-capture-\(attestationDigest.rawValue)")
        let receipt = NativeCaptureReceipt(
            id: captureID,
            cellID: request.cellID,
            sourceTree: request.sourceTree,
            builtArtifact: request.builtArtifact,
            captureProtocol: request.captureProtocol,
            traits: output.observedTraits,
            imageDigest: raster.pixelDigest,
            accessibilityTreeDigest: accessibilityDigest,
            navigationRecipeDigest: navigationRecipeDigest,
            componentBoundaryDigest: componentDigest,
            designTokenTraceDigest: tokenDigest,
            imageWidthPixels: raster.width,
            imageHeightPixels: raster.height,
            fullViewport: output.fullViewport,
            cleanInstall: output.cleanInstall,
            harnessIdentity: harnessIdentity,
            processExitCode: output.processExitCode,
            capturedAt: capturedAt
        )
        guard receipt.isComplete else {
            throw NativeVisualCaptureError.digestConstructionFailed
        }
        let attestation = AttestedNativeCapture(
            receipt: receipt,
            requestDigest: requestDigest,
            encodedImageDigest: encodedImageDigest,
            cleanInstallEvidenceDigest: lifecycleDigest,
            componentBoundaryArtifactDigest: componentDigest,
            designTokenArtifactDigest: tokenDigest,
            attestationDigest: attestationDigest
        )
        return (attestation, output)
    }

    /// Production visual evaluation consumes this live wrapper rather than a
    /// decoded `AttestedNativeCapture` value.
    func captureAuthorized(
        _ request: NativeCaptureRequest
    ) async throws -> AuthorizedNativeCapture {
        let result = try await performCapture(request)
        return AuthorizedNativeCapture(
            attestation: result.attestation,
            encodedImage: result.output.encodedImage,
            accessibilityTree: result.output.accessibilityTree,
            cleanInstallEvidence: result.output.cleanInstallEvidence,
            componentBoundaryTrace: result.output.componentBoundaryTrace,
            designTokenTrace: result.output.designTokenTrace
        )
    }

    nonisolated static func isJSONObjectOrArray(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let value = try? JSONSerialization.jsonObject(with: data),
              value is [String: Any] || value is [Any] else {
            return false
        }
        return true
    }

    /// Revalidates bytes supplied later for baseline/candidate pair review
    /// against the exact raster identity retained in a capture receipt.
    nonisolated static func encodedImage(
        _ data: Data,
        matches receipt: NativeCaptureReceipt,
        limits: NativeCaptureLimits = .platformDefault
    ) -> Bool {
        guard let raster = try? rasterEvidence(data, limits: limits) else {
            return false
        }
        return raster.width == receipt.imageWidthPixels
            && raster.height == receipt.imageHeightPixels
            && raster.pixelDigest == receipt.imageDigest
    }

    private nonisolated static func rasterEvidence(
        _ data: Data,
        limits: NativeCaptureLimits
    ) throws -> RasterEvidence {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            throw NativeVisualCaptureError.invalidRaster
        }
        let width = image.width
        let height = image.height
        guard width > 0,
              height > 0,
              width <= limits.maximumDimensionPixels,
              height <= limits.maximumDimensionPixels else {
            throw NativeVisualCaptureError.invalidRaster
        }
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelOverflow,
              !byteOverflow,
              pixelCount <= limits.maximumRasterPixels,
              byteCount > 0 else {
            throw NativeVisualCaptureError.invalidRaster
        }
        var pixels = Data(count: byteCount)
        let rendered = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw NativeVisualCaptureError.invalidRaster }
        var dimensionData = Data()
        var bigWidth = UInt64(width).bigEndian
        var bigHeight = UInt64(height).bigEndian
        withUnsafeBytes(of: &bigWidth) { dimensionData.append(contentsOf: $0) }
        withUnsafeBytes(of: &bigHeight) { dimensionData.append(contentsOf: $0) }
        return RasterEvidence(
            width: width,
            height: height,
            pixelDigest: framedDigest([dimensionData, pixels])
        )
    }

    private nonisolated static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private nonisolated static func framedDigest(_ fields: [Data]) -> ContentDigest {
        var material = Data()
        for field in fields {
            var length = UInt64(field.count).bigEndian
            withUnsafeBytes(of: &length) { material.append(contentsOf: $0) }
            material.append(field)
        }
        return digest(material)
    }
}
