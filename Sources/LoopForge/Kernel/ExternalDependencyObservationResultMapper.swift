import Foundation

/// Replayable deterministic evidence that one exact native exit/parser pair
/// selected one exact ratified external-dependency mapping row. This remains
/// inert data: only a future journal/process runtime that owns the launch,
/// exit, retained output, and release may issue an observation capability.
struct ExternalDependencyObservationResultMappingReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var probeDigest: ContentDigest
    var activationReceiptID: ReceiptID
    var requestNonce: ContentDigest
    var nativeExitCode: Int32
    var parserResultCode: String
    var parsedEvidenceDigest: ContentDigest
    var terminalEnvelopeDigest: ContentDigest
    var mappingOrdinal: UInt64
    var availability: ExternalDependencyAvailability
}

struct ExternalDependencyObservationResultMapper: Sendable {
    static func expectedReceipt(
        activation: ExternalDependencyObservationActivationReceipt,
        probe: ExternalDependencyObservationExecutableProbe,
        nativeExitCode: Int32,
        parse: ExternalDependencyObservationParseReceipt
    ) -> ExternalDependencyObservationResultMappingReceipt? {
        guard probe.validationIssues().isEmpty,
              ExternalDependencyObservationActivationCompiler.receipt(
                activation,
                matches: probe
              ),
              ExternalDependencyObservationProbe.receipt(
                parse,
                matches: ExternalDependencyObservationParseExpectation(
                    dependencyID: activation.dependencyID,
                    evidenceRecipeID: activation.evidenceRecipeID,
                    requestNonce:
                        activation.requestArtifact.requestNonce,
                    parser: activation.parser
                )
              ) else {
            return nil
        }
        let matches = probe.resultMappings.enumerated().filter {
            $0.element.exitCode == nativeExitCode
                && $0.element.parserResultCode == parse.resultCode
        }
        guard matches.count == 1,
              let match = matches.first,
              let probeDigest =
                ExternalDependencyObservationActivationCompiler.probeDigest(
                    probe
                ) else {
            return nil
        }
        return ExternalDependencyObservationResultMappingReceipt(
            schemaVersion: 1,
            probeDigest: probeDigest,
            activationReceiptID: activation.id,
            requestNonce: activation.requestArtifact.requestNonce,
            nativeExitCode: nativeExitCode,
            parserResultCode: parse.resultCode,
            parsedEvidenceDigest: parse.evidenceDigest,
            terminalEnvelopeDigest: parse.terminalEnvelopeDigest,
            mappingOrdinal: UInt64(match.offset),
            availability: match.element.availability
        )
    }
}
