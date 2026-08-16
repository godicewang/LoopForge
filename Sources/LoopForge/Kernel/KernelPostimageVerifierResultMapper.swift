import Foundation

/// Replayable deterministic evidence that one exact native exit/result pair
/// matched one exact recipe row. This is data, not verification authority.
struct KernelPostimageVerifierResultMappingReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var probeDigest: ContentDigest
    var nativeExitCode: Int32
    var parserResultCode: String
    var parsedEvidenceDigest: ContentDigest
    var terminalEnvelopeDigest: ContentDigest
    var mappingOrdinal: UInt64
    var outcome: RequirementVerificationOutcome
}

struct KernelPostimageVerifierResultMapper: Sendable {
    static func expectedReceipt(
        probe: RequirementVerificationExecutableProbe,
        nativeExitCode: Int32,
        parse: KernelPostimageVerifierResultParseReceipt
    ) -> KernelPostimageVerifierResultMappingReceipt? {
        guard probe.validationIssues().isEmpty,
              KernelPostimageVerifierResultParser.validResultCode(
                parse.resultCode
              ),
              KernelPostimageVerifierResultParser.validSHA256(
                parse.evidenceDigest
              ),
              KernelPostimageVerifierResultParser.validSHA256(
                parse.terminalEnvelopeDigest
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
                KernelPostimageVerifierActivationCompiler.probeDigest(probe)
        else {
            return nil
        }
        return KernelPostimageVerifierResultMappingReceipt(
            schemaVersion: 1,
            probeDigest: probeDigest,
            nativeExitCode: nativeExitCode,
            parserResultCode: parse.resultCode,
            parsedEvidenceDigest: parse.evidenceDigest,
            terminalEnvelopeDigest: parse.terminalEnvelopeDigest,
            mappingOrdinal: UInt64(match.offset),
            outcome: match.element.outcome
        )
    }
}
