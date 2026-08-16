import CryptoKit
import Foundation

enum ExternalDependencyObservationTransport: String, Codable, Hashable, Sendable {
    case localDirectProcess
}

enum ExternalDependencyObservationParserFormat: String, Codable, Hashable, Sendable {
    case canonicalJSONAvailabilityV1

    var implementationIdentityDigest: ContentDigest {
        switch self {
        case .canonicalJSONAvailabilityV1:
            return ExternalDependencyObservationProbe.digest(Data(
                "loopforge.kernel.external-dependency-result.v1.canonical-sorted-json-single-line"
                    .utf8
            ))
        }
    }
}

/// Exact retained-output contract for external observers. This identity is
/// user-ratified with the executable probe and prevents a future runtime from
/// substituting pipes, merged streams, shell redirection, or unbounded output
/// for the private journal-owned stdin/stdout/stderr files.
struct ExternalDependencyObservationCapturePolicy: Sendable {
    static let identityDigest = ExternalDependencyObservationProbe.digest(
        Data(
            "external-dependency-capture-v1|private-request-stdin|private-bounded-stdout-stderr|no-shell"
                .utf8
        )
    )
}

struct ExternalDependencyObservationParserContract:
    Codable, Hashable, Sendable {
    var id: String
    var schemaVersion: Int
    var contentDigest: ContentDigest
    var format: ExternalDependencyObservationParserFormat
}

struct ExternalDependencyObservationResultMapping:
    Codable, Hashable, Sendable {
    var exitCode: Int32
    var parserResultCode: String
    var availability: ExternalDependencyAvailability
}

/// User-ratified executable material for observing one external boundary.
/// It carries no executable path, shell string, credential, or ambient
/// environment authority. A later journal-owned runtime must stage the exact
/// digest, replace the single request token with a private descriptor-backed
/// request, enforce these ceilings, and map only the declared terminal pair.
struct ExternalDependencyObservationExecutableProbe:
    Codable, Hashable, Sendable {
    static let requestArgumentToken =
        "@loopforge-input:external-dependency-request"

    var schemaVersion: Int
    var transport: ExternalDependencyObservationTransport
    var executableContentDigest: ContentDigest
    var fixedArguments: [String]
    var environmentPolicy: KernelEnvironmentPolicy
    var environmentIdentityDigest: ContentDigest
    var captureIdentityDigest: ContentDigest
    var parser: ExternalDependencyObservationParserContract
    var resultMappings: [ExternalDependencyObservationResultMapping]
    var networkPolicy: KernelNetworkPolicy
    var resourceLimits: RequirementVerificationResourceLimits

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append(
                "external dependency probe schemaVersion must be supported"
            )
        }
        if transport != .localDirectProcess {
            issues.append(
                "external dependency probe must use direct local executable transport"
            )
        }
        if !ExternalDependencyObservationProbe.validSHA256(
            executableContentDigest
        ) {
            issues.append(
                "external dependency executable content digest must be exact lowercase SHA-256"
            )
        }
        if fixedArguments.count > 64
            || fixedArguments.contains(where: {
                $0.utf8.count > 4_096 || $0.contains("\0")
            })
            || fixedArguments.filter({
                $0 == Self.requestArgumentToken
            }).count != 1 {
            issues.append(
                "external dependency arguments must contain one bounded exact request token"
            )
        }
        if environmentPolicy != .minimalKernelAllowlist {
            issues.append(
                "external dependency probe must use the minimal kernel environment"
            )
        }
        if !ExternalDependencyObservationProbe.validSHA256(
            environmentIdentityDigest
        ) || !ExternalDependencyObservationProbe.validSHA256(
            captureIdentityDigest
        ) {
            issues.append(
                "external dependency environment and capture identities must be exact lowercase SHA-256"
            )
        }
        let exactEnvironmentIdentity = KernelProcessEnvironmentAuthorizer
            .environmentDigest(
                KernelProcessEnvironmentAuthorizer.minimalEnvironment
            )
        if environmentIdentityDigest != exactEnvironmentIdentity {
            issues.append(
                "external dependency environment identity must bind the exact kernel minimal environment"
            )
        }
        if captureIdentityDigest !=
            ExternalDependencyObservationCapturePolicy.identityDigest {
            issues.append(
                "external dependency capture identity must bind private bounded request and output files"
            )
        }
        if !ExternalDependencyObservationProbe.validIdentity(parser.id)
            || parser.schemaVersion != 1
            || parser.format != .canonicalJSONAvailabilityV1
            || parser.contentDigest != parser.format.implementationIdentityDigest {
            issues.append(
                "external dependency parser must identify the supported canonical result grammar"
            )
        }
        let mappingKeys = resultMappings.map {
            "\($0.exitCode)\u{1f}\($0.parserResultCode)"
        }
        if resultMappings.isEmpty
            || resultMappings.count > 64
            || Set(mappingKeys).count != mappingKeys.count
            || resultMappings.contains(where: {
                !ExternalDependencyObservationProbe.validIdentity(
                    $0.parserResultCode
                )
            })
            || Set(resultMappings.map(\.availability)) != [
                .available, .unavailable
            ] {
            issues.append(
                "external dependency result mapping must be unique, exact, and cover both availability outcomes"
            )
        }
        if resourceLimits.maximumWallClockSeconds == 0
            || resourceLimits.maximumCapturedOutputBytes == 0
            || resourceLimits.maximumResidentBytes == 0
            || resourceLimits.maximumChildProcesses != 0 {
            issues.append(
                "external dependency resource limits must be positive and forbid child processes"
            )
        }
        return issues
    }
}

struct ExternalDependencyObservationResultEnvelope:
    Codable, Hashable, Sendable {
    var dependencyID: ExternalDependencyID
    var evidenceDigest: ContentDigest
    var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
    var requestNonce: ContentDigest
    var resultCode: String
    var schemaVersion: Int
}

struct ExternalDependencyObservationParseExpectation: Hashable, Sendable {
    var dependencyID: ExternalDependencyID
    var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
    var requestNonce: ContentDigest
    var parser: ExternalDependencyObservationParserContract
}

struct ExternalDependencyObservationParseReceipt:
    Codable, Hashable, Sendable {
    var parserImplementationDigest: ContentDigest
    var dependencyID: ExternalDependencyID
    var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
    var requestNonce: ContentDigest
    var standardOutputContentDigest: ContentDigest
    var standardOutputByteCount: UInt64
    var terminalEnvelopeDigest: ContentDigest
    var resultCode: String
    var evidenceDigest: ContentDigest
}

/// Strictly parsed bytes are still only a proposal. This non-Codable wrapper
/// must later be combined with exact native exit and launch receipts before a
/// journal observation can be issued.
struct AuthorizedExternalDependencyObservationParse: Sendable {
    let receipt: ExternalDependencyObservationParseReceipt

    fileprivate init(receipt: ExternalDependencyObservationParseReceipt) {
        self.receipt = receipt
    }
}

enum ExternalDependencyObservationProbeError: Error, Equatable {
    case invalidExpectation
    case emptyOutput
    case outputTooLarge
    case missingFinalNewline
    case multipleLines
    case invalidUTF8
    case invalidJSON
    case unexpectedKeys
    case nonCanonicalJSON
    case unsupportedSchema
    case mismatchedRequest
    case invalidResultCode
    case invalidEvidenceDigest
}

struct ExternalDependencyObservationProbe: Sendable {
    static let maximumEnvelopeBytes = 64 * 1_024

    func parse(
        standardOutput: Data,
        expectation: ExternalDependencyObservationParseExpectation
    ) throws -> AuthorizedExternalDependencyObservationParse {
        guard !expectation.dependencyID.rawValue.isEmpty,
              !expectation.evidenceRecipeID.rawValue.isEmpty,
              Self.validSHA256(expectation.requestNonce),
              expectation.parser.schemaVersion == 1,
              expectation.parser.format == .canonicalJSONAvailabilityV1,
              expectation.parser.contentDigest ==
                expectation.parser.format.implementationIdentityDigest else {
            throw ExternalDependencyObservationProbeError.invalidExpectation
        }
        guard !standardOutput.isEmpty else {
            throw ExternalDependencyObservationProbeError.emptyOutput
        }
        guard standardOutput.count <= Self.maximumEnvelopeBytes else {
            throw ExternalDependencyObservationProbeError.outputTooLarge
        }
        guard standardOutput.last == 0x0a else {
            throw ExternalDependencyObservationProbeError.missingFinalNewline
        }
        let envelopeBytes = standardOutput.dropLast()
        guard !envelopeBytes.isEmpty,
              !envelopeBytes.contains(0x0a),
              !envelopeBytes.contains(0x0d) else {
            throw ExternalDependencyObservationProbeError.multipleLines
        }
        let line = Data(envelopeBytes)
        guard String(data: line, encoding: .utf8) != nil else {
            throw ExternalDependencyObservationProbeError.invalidUTF8
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: line)
        } catch {
            throw ExternalDependencyObservationProbeError.invalidJSON
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == [
                "dependencyID",
                "evidenceDigest",
                "evidenceRecipeID",
                "requestNonce",
                "resultCode",
                "schemaVersion"
              ] else {
            throw ExternalDependencyObservationProbeError.unexpectedKeys
        }
        let envelope: ExternalDependencyObservationResultEnvelope
        do {
            envelope = try JSONDecoder().decode(
                ExternalDependencyObservationResultEnvelope.self,
                from: line
            )
        } catch {
            throw ExternalDependencyObservationProbeError.invalidJSON
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == line else {
            throw ExternalDependencyObservationProbeError.nonCanonicalJSON
        }
        guard envelope.schemaVersion == 1 else {
            throw ExternalDependencyObservationProbeError.unsupportedSchema
        }
        guard envelope.dependencyID == expectation.dependencyID,
              envelope.evidenceRecipeID == expectation.evidenceRecipeID,
              envelope.requestNonce == expectation.requestNonce else {
            throw ExternalDependencyObservationProbeError.mismatchedRequest
        }
        guard Self.validIdentity(envelope.resultCode) else {
            throw ExternalDependencyObservationProbeError.invalidResultCode
        }
        guard Self.validSHA256(envelope.evidenceDigest) else {
            throw ExternalDependencyObservationProbeError.invalidEvidenceDigest
        }
        return AuthorizedExternalDependencyObservationParse(
            receipt: ExternalDependencyObservationParseReceipt(
                parserImplementationDigest:
                    expectation.parser.contentDigest,
                dependencyID: envelope.dependencyID,
                evidenceRecipeID: envelope.evidenceRecipeID,
                requestNonce: envelope.requestNonce,
                standardOutputContentDigest: Self.digest(standardOutput),
                standardOutputByteCount: UInt64(standardOutput.count),
                terminalEnvelopeDigest: Self.digest(line),
                resultCode: envelope.resultCode,
                evidenceDigest: envelope.evidenceDigest
            )
        )
    }

    static func receipt(
        _ receipt: ExternalDependencyObservationParseReceipt,
        matches expectation: ExternalDependencyObservationParseExpectation
    ) -> Bool {
        expectation.parser.schemaVersion == 1
            && expectation.parser.format == .canonicalJSONAvailabilityV1
            && receipt.parserImplementationDigest ==
                expectation.parser.contentDigest
            && receipt.parserImplementationDigest ==
                expectation.parser.format.implementationIdentityDigest
            && receipt.dependencyID == expectation.dependencyID
            && receipt.evidenceRecipeID == expectation.evidenceRecipeID
            && receipt.requestNonce == expectation.requestNonce
            && receipt.standardOutputByteCount > 0
            && receipt.standardOutputByteCount <= UInt64(maximumEnvelopeBytes)
            && validSHA256(receipt.standardOutputContentDigest)
            && validIdentity(receipt.resultCode)
            && validSHA256(receipt.evidenceDigest)
            && receipt.terminalEnvelopeDigest == canonicalEnvelopeDigest(
                dependencyID: receipt.dependencyID,
                evidenceRecipeID: receipt.evidenceRecipeID,
                requestNonce: receipt.requestNonce,
                resultCode: receipt.resultCode,
                evidenceDigest: receipt.evidenceDigest
            )
    }

    static func canonicalEnvelopeDigest(
        dependencyID: ExternalDependencyID,
        evidenceRecipeID: ExternalDependencyEvidenceRecipeID,
        requestNonce: ContentDigest,
        resultCode: String,
        evidenceDigest: ContentDigest
    ) -> ContentDigest? {
        let envelope = ExternalDependencyObservationResultEnvelope(
            dependencyID: dependencyID,
            evidenceDigest: evidenceDigest,
            evidenceRecipeID: evidenceRecipeID,
            requestNonce: requestNonce,
            resultCode: resultCode,
            schemaVersion: 1
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope) else { return nil }
        return digest(data)
    }

    static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }

    static func validSHA256(_ digest: ContentDigest) -> Bool {
        let value = digest.rawValue
        return value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func validIdentity(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
