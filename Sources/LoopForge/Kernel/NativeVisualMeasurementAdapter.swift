import CryptoKit
import Foundation

struct NativeVisualMeasurementRequest: Sendable {
    var baselineCapture: NativeCaptureReceipt
    var candidateCaptureAuthority: AuthorizedNativeCapture
    var protectedDimensions: Set<VisualGateDimension>
    var knownDebt: [DesignDebt]
    var measurementProtocol: ContentDigest
    var notBefore: Date

    var candidateCapture: NativeCaptureReceipt {
        candidateCaptureAuthority.attestation.receipt
    }

    var isValid: Bool {
        baselineCapture.isComplete
            && candidateCapture.isComplete
            && baselineCapture.cellID == candidateCapture.cellID
            && baselineCapture.traits == candidateCapture.traits
            && baselineCapture.captureProtocol == candidateCapture.captureProtocol
            && baselineCapture.capturedAt <= candidateCapture.capturedAt
            && candidateCapture.capturedAt >= notBefore
            && !protectedDimensions.isEmpty
            && Set(knownDebt.map(\.id)).count == knownDebt.count
            && knownDebt.allSatisfy {
                $0.cellIDs.contains(baselineCapture.cellID)
                    && $0.baselineSeverity.isFinite
                    && $0.maximumInterimSeverity.isFinite
            }
            && !measurementProtocol.rawValue.isEmpty
            && notBefore.timeIntervalSince1970.isFinite
    }
}

struct NativeVisualMeasurementHarnessOutput: Hashable, Sendable {
    /// Evidence IDs are deliberately supplied empty. The adapter replaces them
    /// with its own digest-bound receipt after validating the raw evidence.
    var measurement: VisualPairMeasurements
    var debtSeverityByID: [DesignDebtID: Double]
    var rawEvidence: Data
    var processExitCode: Int32
}

protocol NativeVisualMeasurementHarness: Sendable {
    var identity: String { get }
    func measure(
        _ request: NativeVisualMeasurementRequest
    ) async throws -> NativeVisualMeasurementHarnessOutput
}

struct AuthorizedNativeVisualMeasurement: Sendable {
    let measurement: VisualPairMeasurements
    let baselineCaptureID: NativeCaptureID
    let candidateCaptureID: NativeCaptureID
    let protectedDimensions: Set<VisualGateDimension>
    let debtSeverityByID: [DesignDebtID: Double]
    let measurementProtocol: ContentDigest
    let harnessIdentity: String
    let requestDigest: ContentDigest
    let rawEvidenceDigest: ContentDigest
    let attestationDigest: ContentDigest
    let measuredAt: Date

    fileprivate init(
        measurement: VisualPairMeasurements,
        baselineCaptureID: NativeCaptureID,
        candidateCaptureID: NativeCaptureID,
        protectedDimensions: Set<VisualGateDimension>,
        debtSeverityByID: [DesignDebtID: Double],
        measurementProtocol: ContentDigest,
        harnessIdentity: String,
        requestDigest: ContentDigest,
        rawEvidenceDigest: ContentDigest,
        attestationDigest: ContentDigest,
        measuredAt: Date
    ) {
        self.measurement = measurement
        self.baselineCaptureID = baselineCaptureID
        self.candidateCaptureID = candidateCaptureID
        self.protectedDimensions = protectedDimensions
        self.debtSeverityByID = debtSeverityByID
        self.measurementProtocol = measurementProtocol
        self.harnessIdentity = harnessIdentity
        self.requestDigest = requestDigest
        self.rawEvidenceDigest = rawEvidenceDigest
        self.attestationDigest = attestationDigest
        self.measuredAt = measuredAt
    }
}

enum NativeVisualMeasurementError: Error, Equatable {
    case invalidRequest
    case untrustedHarness
    case harnessFailed
    case measurementPredatesAuthorityBoundary
    case processFailed(Int32)
    case invalidRawEvidence
    case evidenceTooLarge
    case harnessAttemptedToMintEvidenceReceipt
    case cellMismatch
    case invalidMeasurement(String)
    case digestConstructionFailed
}

/// Turns one allow-listed deterministic measurement-harness observation into
/// live, non-Codable authority. The harness can report measurements, but it
/// cannot select the cell, capture pair, protocol, evidence receipt identity,
/// or measurement time.
actor NativeVisualMeasurementAdapter {
    private struct RequestDigestEnvelope: Encodable {
        var baselineCaptureID: NativeCaptureID
        var baselineImageDigest: ContentDigest
        var baselineAccessibilityDigest: ContentDigest
        var candidateCaptureID: NativeCaptureID
        var candidateImageDigest: ContentDigest
        var candidateAccessibilityDigest: ContentDigest
        var cellID: VisualCellID
        var traits: VisualTraitSignature
        var captureProtocol: ContentDigest
        var protectedDimensions: [VisualGateDimension]
        var knownDebtMaterial: [String]
        var measurementProtocol: ContentDigest
        var notBefore: Date
        var harnessIdentity: String
    }

    private struct AttestationEnvelope: Encodable {
        var requestDigest: ContentDigest
        var rawEvidenceDigest: ContentDigest
        var measurement: VisualPairMeasurements
        var debtSeverityByID: [String: Double]
        var harnessIdentity: String
        var measuredAt: Date
    }

    private let harness: any NativeVisualMeasurementHarness
    private let allowedHarnessIdentities: Set<String>
    private let maximumEvidenceBytes: Int
    private let clock: @Sendable () -> Date

    init(
        harness: any NativeVisualMeasurementHarness,
        allowedHarnessIdentities: Set<String>,
        maximumEvidenceBytes: Int = 16 * 1_024 * 1_024,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.harness = harness
        self.allowedHarnessIdentities = allowedHarnessIdentities
        self.maximumEvidenceBytes = maximumEvidenceBytes
        self.clock = clock
    }

    func measure(
        _ request: NativeVisualMeasurementRequest
    ) async throws -> AuthorizedNativeVisualMeasurement {
        guard maximumEvidenceBytes > 0, request.isValid else {
            throw NativeVisualMeasurementError.invalidRequest
        }
        let identity = harness.identity
        guard !identity.isEmpty, allowedHarnessIdentities.contains(identity) else {
            throw NativeVisualMeasurementError.untrustedHarness
        }

        let output: NativeVisualMeasurementHarnessOutput
        do {
            output = try await harness.measure(request)
        } catch {
            throw NativeVisualMeasurementError.harnessFailed
        }
        let measuredAt = clock()
        guard measuredAt >= request.notBefore,
              measuredAt >= request.candidateCapture.capturedAt else {
            throw NativeVisualMeasurementError.measurementPredatesAuthorityBoundary
        }
        guard output.processExitCode == 0 else {
            throw NativeVisualMeasurementError.processFailed(output.processExitCode)
        }
        guard output.rawEvidence.count <= maximumEvidenceBytes else {
            throw NativeVisualMeasurementError.evidenceTooLarge
        }
        guard NativeVisualCaptureAdapter.isJSONObjectOrArray(output.rawEvidence) else {
            throw NativeVisualMeasurementError.invalidRawEvidence
        }
        guard output.measurement.evidenceReceiptIDs.isEmpty else {
            throw NativeVisualMeasurementError.harnessAttemptedToMintEvidenceReceipt
        }
        guard output.measurement.cellID == request.baselineCapture.cellID else {
            throw NativeVisualMeasurementError.cellMismatch
        }
        let issues = Self.validationIssues(
            output.measurement,
            protectedDimensions: request.protectedDimensions
        )
        guard issues.isEmpty else {
            throw NativeVisualMeasurementError.invalidMeasurement(
                issues.sorted().joined(separator: "; ")
            )
        }
        let requiredDebtIDs = Set(request.knownDebt.map(\.id))
        guard Set(output.debtSeverityByID.keys) == requiredDebtIDs,
              output.debtSeverityByID.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw NativeVisualMeasurementError.invalidMeasurement(
                "known-debt severity coverage invalid"
            )
        }

        let requestDigest = try Self.digest(RequestDigestEnvelope(
            baselineCaptureID: request.baselineCapture.id,
            baselineImageDigest: request.baselineCapture.imageDigest,
            baselineAccessibilityDigest: request.baselineCapture.accessibilityTreeDigest,
            candidateCaptureID: request.candidateCapture.id,
            candidateImageDigest: request.candidateCapture.imageDigest,
            candidateAccessibilityDigest: request.candidateCapture.accessibilityTreeDigest,
            cellID: request.baselineCapture.cellID,
            traits: request.baselineCapture.traits,
            captureProtocol: request.baselineCapture.captureProtocol,
            protectedDimensions: request.protectedDimensions.sorted {
                $0.rawValue < $1.rawValue
            },
            knownDebtMaterial: request.knownDebt.map {
                [
                    $0.id.rawValue,
                    $0.dimension.rawValue,
                    $0.cellIDs.map(\.rawValue).sorted().joined(separator: ","),
                    String($0.baselineSeverity),
                    String($0.maximumInterimSeverity),
                    $0.direction.rawValue,
                    String($0.closureRequired),
                    $0.evidenceDigest.rawValue
                ].joined(separator: "|")
            }.sorted(),
            measurementProtocol: request.measurementProtocol,
            notBefore: request.notBefore,
            harnessIdentity: identity
        ))
        let evidenceDigest = Self.digest(output.rawEvidence)
        var measurement = output.measurement
        let preReceiptDigest = try Self.digest(AttestationEnvelope(
            requestDigest: requestDigest,
            rawEvidenceDigest: evidenceDigest,
            measurement: measurement,
            debtSeverityByID: Dictionary(uniqueKeysWithValues:
                output.debtSeverityByID.map { ($0.key.rawValue, $0.value) }
            ),
            harnessIdentity: identity,
            measuredAt: measuredAt
        ))
        measurement.evidenceReceiptIDs = [ReceiptID(
            "native-visual-measurement-\(preReceiptDigest.rawValue)"
        )]
        let attestationDigest = try Self.digest(AttestationEnvelope(
            requestDigest: requestDigest,
            rawEvidenceDigest: evidenceDigest,
            measurement: measurement,
            debtSeverityByID: Dictionary(uniqueKeysWithValues:
                output.debtSeverityByID.map { ($0.key.rawValue, $0.value) }
            ),
            harnessIdentity: identity,
            measuredAt: measuredAt
        ))
        return AuthorizedNativeVisualMeasurement(
            measurement: measurement,
            baselineCaptureID: request.baselineCapture.id,
            candidateCaptureID: request.candidateCapture.id,
            protectedDimensions: request.protectedDimensions,
            debtSeverityByID: output.debtSeverityByID,
            measurementProtocol: request.measurementProtocol,
            harnessIdentity: identity,
            requestDigest: requestDigest,
            rawEvidenceDigest: evidenceDigest,
            attestationDigest: attestationDigest,
            measuredAt: measuredAt
        )
    }

    nonisolated static func validationIssues(
        _ value: VisualPairMeasurements,
        protectedDimensions: Set<VisualGateDimension>
    ) -> [String] {
        var issues: [String] = []
        func require(_ condition: Bool, _ issue: String) {
            if !condition { issues.append(issue) }
        }
        func validMaximum(_ number: Double?) -> Bool {
            guard let number else { return false }
            return number.isFinite && number >= 0
        }

        if protectedDimensions.contains(.productIdentityContinuity) {
            require(value.productIdentityContinuous != nil, "product identity result missing")
        }
        if protectedDimensions.contains(.initialTaskHierarchy) {
            require(value.primaryTaskWithinBoundary != nil, "task hierarchy result missing")
        }
        if protectedDimensions.contains(.typographyHierarchy) {
            require(value.typographyHierarchyInverted != nil, "typography inversion result missing")
            require(validMaximum(value.maximumTypographyRatioDelta), "typography ratio delta invalid")
        }
        if protectedDimensions.contains(.symmetryAndAlignment) {
            require(
                value.symmetricTitleLineCountDelta.map { $0 >= 0 } == true,
                "title line-count delta invalid"
            )
            require(validMaximum(value.maximumAlignmentOffsetLineHeights), "alignment delta invalid")
        }
        if protectedDimensions.contains(.spacingRhythmAndDensity) {
            require(validMaximum(value.maximumSpacingDeltaPoints), "spacing point delta invalid")
            require(validMaximum(value.maximumSpacingRelativeDelta), "spacing relative delta invalid")
            require(validMaximum(value.contentOccupancyIncrease), "occupancy increase invalid")
            require(
                value.undeclaredSemanticTokenCount.map { $0 >= 0 } == true,
                "semantic-token count invalid"
            )
        }
        if protectedDimensions.contains(.shapeLanguage) {
            require(validMaximum(value.maximumShapeRatioDelta), "shape ratio delta invalid")
            require(value.shapeContentFitPasses != nil, "shape fit result missing")
            require(
                value.undeclaredSemanticTokenCount.map { $0 >= 0 } == true,
                "semantic-token count invalid"
            )
        }
        if protectedDimensions.contains(.collisionOcclusionAndSafeArea) {
            require(value.newOcclusionPixels.map { $0 >= 0 } == true, "occlusion result invalid")
        }
        if protectedDimensions.contains(.responsiveComposition) {
            require(value.responsiveCompositionPasses != nil, "responsive result missing")
        }
        if protectedDimensions.contains(.accessibilitySemanticsAndOperation) {
            require(value.accessibilitySemanticsPasses != nil, "accessibility result missing")
        }
        if protectedDimensions.contains(.localizationQualityAndSlotFit) {
            require(value.localizationQualityPasses != nil, "localization result missing")
            require(value.localizedCopyFitsSlot != nil, "localized slot-fit result missing")
        }
        if let perceptual = value.perceptualDifference {
            require(perceptual.isFinite && perceptual >= 0, "perceptual difference invalid")
        }
        return issues
    }

    private nonisolated static func digest<T: Encodable>(
        _ value: T
    ) throws -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else {
            throw NativeVisualMeasurementError.digestConstructionFailed
        }
        return digest(data)
    }

    private nonisolated static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}
