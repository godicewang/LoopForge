import CryptoKit
import Foundation

struct ExternalDependencyObservationOutputFileReceipt:
    Codable,
    Hashable,
    Sendable
{
    var fileName: String
    var byteCount: UInt64
    var contentDigest: ContentDigest
}

/// Replayable evidence that exact retained output, a natural native exit, and
/// one ratified mapping were committed with one exact runtime release. This is
/// still data; only JournaledProcessRuntime can mint the live capability.
struct ExternalDependencyObservationResultReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var id: ReceiptID
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var attemptID: AttemptID
    var dependencyID: ExternalDependencyID
    var requirementIDs: Set<RequirementID>
    var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
    var observer: ActorIdentity
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var releaseReceiptID: ReceiptID
    var releaseEndingSequence: UInt64
    var releaseFrameDigest: ContentDigest
    var standardOutput: ExternalDependencyObservationOutputFileReceipt
    var standardError: ExternalDependencyObservationOutputFileReceipt
    var parse: ExternalDependencyObservationParseReceipt
    var mapping: ExternalDependencyObservationResultMappingReceipt
    var evidenceSetDigest: ContentDigest
    var completedAt: Date
}

/// Non-serializable proof reserved to the journal-owned process runtime. A
/// decoded result receipt or release transaction cannot recreate it.
struct AuthorizedExternalDependencyObservationResult: Sendable {
    let receipt: ExternalDependencyObservationResultReceipt
    let release: RuntimeReleaseOutcomeReceipt
    let releaseTransaction: JournalTransactionReceipt

    private init(
        receipt: ExternalDependencyObservationResultReceipt,
        release: RuntimeReleaseOutcomeReceipt,
        releaseTransaction: JournalTransactionReceipt
    ) {
        self.receipt = receipt
        self.release = release
        self.releaseTransaction = releaseTransaction
    }

    static func issuedByProcessRuntime(
        receipt: ExternalDependencyObservationResultReceipt,
        release: RuntimeReleaseOutcomeReceipt,
        releaseTransaction: JournalTransactionReceipt,
        issuer: JournaledProcessRuntimeCommandIssuer
    ) -> Self {
        Self(
            receipt: receipt,
            release: release,
            releaseTransaction: releaseTransaction
        )
    }

#if DEBUG
    static func testOnly(
        receipt: ExternalDependencyObservationResultReceipt,
        release: RuntimeReleaseOutcomeReceipt,
        releaseTransaction: JournalTransactionReceipt
    ) -> Self {
        Self(
            receipt: receipt,
            release: release,
            releaseTransaction: releaseTransaction
        )
    }
#endif
}

struct ExternalDependencyObservationResultAuthority: Sendable {
    private struct EvidenceMaterial: Codable {
        var schemaVersion: Int
        var runID: KernelRunID
        var activationReceiptID: ReceiptID
        var attemptID: AttemptID
        var dependencyID: ExternalDependencyID
        var requirementIDs: [RequirementID]
        var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
        var observer: ActorIdentity
        var resourceID: OwnedResourceID
        var leaseID: ResourceLeaseID
        var releaseReceiptID: ReceiptID
        var releaseEndingSequence: UInt64
        var releaseFrameDigest: ContentDigest
        var standardOutput: ExternalDependencyObservationOutputFileReceipt
        var standardError: ExternalDependencyObservationOutputFileReceipt
        var parse: ExternalDependencyObservationParseReceipt
        var mapping: ExternalDependencyObservationResultMappingReceipt
        var completedAt: Date
    }

    static func expectedReceipt(
        activation: ExternalDependencyObservationActivationReceipt,
        probe: ExternalDependencyObservationExecutableProbe,
        release: RuntimeReleaseOutcomeReceipt,
        releaseTransaction: JournalTransactionReceipt,
        standardOutput: ExternalDependencyObservationOutputFileReceipt,
        standardError: ExternalDependencyObservationOutputFileReceipt,
        parse: ExternalDependencyObservationParseReceipt,
        mapping: ExternalDependencyObservationResultMappingReceipt
    ) -> ExternalDependencyObservationResultReceipt? {
        let expectation = ExternalDependencyObservationParseExpectation(
            dependencyID: activation.dependencyID,
            evidenceRecipeID: activation.evidenceRecipeID,
            requestNonce: activation.requestArtifact.requestNonce,
            parser: activation.parser
        )
        guard probe.validationIssues().isEmpty,
              ExternalDependencyObservationActivationCompiler.receipt(
                activation,
                matches: probe
              ),
              ExternalDependencyObservationProbe.receipt(
                parse,
                matches: expectation
              ),
              mapping == ExternalDependencyObservationResultMapper
                .expectedReceipt(
                    activation: activation,
                    probe: probe,
                    nativeExitCode: mapping.nativeExitCode,
                    parse: parse
                ),
              release.runID == activation.runID,
              release.id.rawValue.isEmpty == false,
              release.managedProcessTermination == nil,
              release.postimageVerifierContainment == nil,
              let nativeExit = release.managedProcessExit,
              nativeExit.exitCode == mapping.nativeExitCode,
              nativeExit.terminationSignal == nil,
              nativeExit.handle.runID == activation.runID,
              nativeExit.handle.resourceID == release.resourceID,
              nativeExit.handle.leaseID == release.leaseID,
              nativeExit.handle.processID > 0,
              nativeExit.handle.processGroupID ==
                nativeExit.handle.processID,
              nativeExit.observedAtMonotonicNanoseconds <=
                release.observedAtMonotonicNanoseconds,
              case .released(let released) = release.outcome,
              released.id == release.id,
              released.runID == release.runID,
              released.resourceID == release.resourceID,
              released.leaseID == release.leaseID,
              released.releasedAtMonotonicNanoseconds ==
                release.observedAtMonotonicNanoseconds,
              releaseTransaction.duplicate == false,
              releaseTransaction.startingSequence ==
                releaseTransaction.endingSequence,
              releaseTransaction.eventIDs.count == 1,
              releaseTransaction.commandID.rawValue.isEmpty == false,
              releaseTransaction.eventIDs[0].rawValue.isEmpty == false,
              ExternalDependencyObservationProbe.validSHA256(
                releaseTransaction.frameDigest
              ),
              validOutputName(standardOutput.fileName),
              validOutputName(standardError.fileName),
              standardOutput.byteCount == parse.standardOutputByteCount,
              standardOutput.contentDigest ==
                parse.standardOutputContentDigest,
              standardError.byteCount == 0,
              standardError.contentDigest ==
                ExternalDependencyObservationProbe.digest(Data()),
              standardOutput.byteCount <=
                probe.resourceLimits.maximumCapturedOutputBytes,
              standardError.byteCount <=
                probe.resourceLimits.maximumCapturedOutputBytes -
                    standardOutput.byteCount,
              release.observedAt >= activation.activatedAt else {
            return nil
        }
        let material = EvidenceMaterial(
            schemaVersion: 1,
            runID: activation.runID,
            activationReceiptID: activation.id,
            attemptID: activation.attemptID,
            dependencyID: activation.dependencyID,
            requirementIDs: activation.requirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            evidenceRecipeID: activation.evidenceRecipeID,
            observer: activation.observer,
            resourceID: release.resourceID,
            leaseID: release.leaseID,
            releaseReceiptID: release.id,
            releaseEndingSequence: releaseTransaction.endingSequence,
            releaseFrameDigest: releaseTransaction.frameDigest,
            standardOutput: standardOutput,
            standardError: standardError,
            parse: parse,
            mapping: mapping,
            completedAt: release.observedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(material) else { return nil }
        let evidenceSetDigest = ContentDigest(
            KernelHex.encode(SHA256.hash(data: bytes))
        )
        return ExternalDependencyObservationResultReceipt(
            schemaVersion: material.schemaVersion,
            id: ReceiptID(
                "external-dependency-result:\(evidenceSetDigest.rawValue)"
            ),
            runID: material.runID,
            activationReceiptID: material.activationReceiptID,
            attemptID: material.attemptID,
            dependencyID: material.dependencyID,
            requirementIDs: Set(material.requirementIDs),
            evidenceRecipeID: material.evidenceRecipeID,
            observer: material.observer,
            resourceID: material.resourceID,
            leaseID: material.leaseID,
            releaseReceiptID: material.releaseReceiptID,
            releaseEndingSequence: material.releaseEndingSequence,
            releaseFrameDigest: material.releaseFrameDigest,
            standardOutput: material.standardOutput,
            standardError: material.standardError,
            parse: material.parse,
            mapping: material.mapping,
            evidenceSetDigest: evidenceSetDigest,
            completedAt: material.completedAt
        )
    }

    static func receipt(
        _ receipt: ExternalDependencyObservationResultReceipt,
        matchesActivation activation:
            ExternalDependencyObservationActivationReceipt,
        probe: ExternalDependencyObservationExecutableProbe,
        release: RuntimeReleaseOutcomeReceipt,
        releaseTransaction: JournalTransactionReceipt
    ) -> Bool {
        receipt == expectedReceipt(
            activation: activation,
            probe: probe,
            release: release,
            releaseTransaction: releaseTransaction,
            standardOutput: receipt.standardOutput,
            standardError: receipt.standardError,
            parse: receipt.parse,
            mapping: receipt.mapping
        )
    }

    private static func validOutputName(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\0")
            && value.precomposedStringWithCanonicalMapping == value
    }
}
