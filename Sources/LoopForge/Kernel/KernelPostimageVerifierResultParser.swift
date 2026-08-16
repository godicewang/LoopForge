import CryptoKit
import Foundation

struct KernelPostimageVerifierResultEnvelope: Codable, Hashable, Sendable {
    var evidenceDigest: ContentDigest
    var resultCode: String
    var schemaVersion: Int
}

struct KernelPostimageVerifierResultParseExpectation: Hashable, Sendable {
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var launchReceiptID: ReceiptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var parser: RequirementVerificationParserContract
    var standardOutput: KernelPostimageVerifierOutputFileReceipt
    var standardError: KernelPostimageVerifierOutputFileReceipt
}

/// Durable parse evidence remains a proposal until the journal-owned oracle
/// binds it to native exit and the exact recipe mapping. Decoding this receipt
/// cannot recreate the in-memory capability required by that future boundary.
struct KernelPostimageVerifierResultParseReceipt: Codable, Hashable, Sendable {
    var parserImplementationDigest: ContentDigest
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var launchReceiptID: ReceiptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var standardOutputContentDigest: ContentDigest
    var standardErrorContentDigest: ContentDigest
    var terminalEnvelopeDigest: ContentDigest
    var resultCode: String
    var evidenceDigest: ContentDigest
}

struct AuthorizedKernelPostimageVerifierResultParse: Sendable {
    let receipt: KernelPostimageVerifierResultParseReceipt

    fileprivate init(receipt: KernelPostimageVerifierResultParseReceipt) {
        self.receipt = receipt
    }
}

enum KernelPostimageVerifierResultParserError: Error, Equatable {
    case invalidExpectation
    case outputIdentityMismatch
    case standardErrorNotEmpty
    case emptyOutput
    case outputTooLarge
    case missingFinalNewline
    case multipleLines
    case invalidUTF8
    case invalidJSON
    case unexpectedKeys
    case nonCanonicalJSON
    case unsupportedSchema
    case invalidResultCode
    case invalidEvidenceDigest
}

struct KernelPostimageVerifierResultParser: Sendable {
    static let maximumEnvelopeBytes = 64 * 1_024

    func parse(
        standardOutput: Data,
        standardError: Data,
        expectation: KernelPostimageVerifierResultParseExpectation
    ) throws -> AuthorizedKernelPostimageVerifierResultParse {
        guard !expectation.runID.rawValue.isEmpty,
              !expectation.activationReceiptID.rawValue.isEmpty,
              !expectation.launchReceiptID.rawValue.isEmpty,
              !expectation.resourceID.rawValue.isEmpty,
              !expectation.leaseID.rawValue.isEmpty,
              expectation.parser.schemaVersion == 1,
              expectation.parser.format == .canonicalJSONResultV1,
              expectation.parser.contentDigest ==
                RequirementVerificationParserFormat.canonicalJSONResultV1
                    .implementationIdentityDigest else {
            throw KernelPostimageVerifierResultParserError.invalidExpectation
        }
        guard standardOutput.count == expectation.standardOutput.byteCount,
              standardError.count == expectation.standardError.byteCount,
              Self.digest(standardOutput) ==
                expectation.standardOutput.contentDigest,
              Self.digest(standardError) ==
                expectation.standardError.contentDigest else {
            throw KernelPostimageVerifierResultParserError.outputIdentityMismatch
        }
        guard standardError.isEmpty else {
            throw KernelPostimageVerifierResultParserError.standardErrorNotEmpty
        }
        guard !standardOutput.isEmpty else {
            throw KernelPostimageVerifierResultParserError.emptyOutput
        }
        guard standardOutput.count <= Self.maximumEnvelopeBytes else {
            throw KernelPostimageVerifierResultParserError.outputTooLarge
        }
        guard standardOutput.last == 0x0a else {
            throw KernelPostimageVerifierResultParserError.missingFinalNewline
        }
        let envelopeBytes = standardOutput.dropLast()
        guard !envelopeBytes.isEmpty,
              !envelopeBytes.contains(0x0a),
              !envelopeBytes.contains(0x0d) else {
            throw KernelPostimageVerifierResultParserError.multipleLines
        }
        let line = Data(envelopeBytes)
        guard String(data: line, encoding: .utf8) != nil else {
            throw KernelPostimageVerifierResultParserError.invalidUTF8
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: line)
        } catch {
            throw KernelPostimageVerifierResultParserError.invalidJSON
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == [
                "evidenceDigest", "resultCode", "schemaVersion"
              ] else {
            throw KernelPostimageVerifierResultParserError.unexpectedKeys
        }
        let envelope: KernelPostimageVerifierResultEnvelope
        do {
            envelope = try JSONDecoder().decode(
                KernelPostimageVerifierResultEnvelope.self,
                from: line
            )
        } catch {
            throw KernelPostimageVerifierResultParserError.invalidJSON
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard try encoder.encode(envelope) == line else {
            throw KernelPostimageVerifierResultParserError.nonCanonicalJSON
        }
        guard envelope.schemaVersion == 1 else {
            throw KernelPostimageVerifierResultParserError.unsupportedSchema
        }
        guard Self.validResultCode(envelope.resultCode) else {
            throw KernelPostimageVerifierResultParserError.invalidResultCode
        }
        guard Self.validSHA256(envelope.evidenceDigest) else {
            throw KernelPostimageVerifierResultParserError.invalidEvidenceDigest
        }
        return AuthorizedKernelPostimageVerifierResultParse(
            receipt: KernelPostimageVerifierResultParseReceipt(
                parserImplementationDigest: expectation.parser.contentDigest,
                runID: expectation.runID,
                activationReceiptID: expectation.activationReceiptID,
                launchReceiptID: expectation.launchReceiptID,
                resourceID: expectation.resourceID,
                leaseID: expectation.leaseID,
                standardOutputContentDigest:
                    expectation.standardOutput.contentDigest,
                standardErrorContentDigest:
                    expectation.standardError.contentDigest,
                terminalEnvelopeDigest: Self.digest(line),
                resultCode: envelope.resultCode,
                evidenceDigest: envelope.evidenceDigest
            )
        )
    }

    static func receipt(
        _ receipt: KernelPostimageVerifierResultParseReceipt,
        matches expectation: KernelPostimageVerifierResultParseExpectation
    ) -> Bool {
        expectation.parser.schemaVersion == 1
            && expectation.parser.format == .canonicalJSONResultV1
            && receipt.parserImplementationDigest == expectation.parser.contentDigest
            && receipt.parserImplementationDigest ==
                expectation.parser.format?.implementationIdentityDigest
            && receipt.runID == expectation.runID
            && receipt.activationReceiptID == expectation.activationReceiptID
            && receipt.launchReceiptID == expectation.launchReceiptID
            && receipt.resourceID == expectation.resourceID
            && receipt.leaseID == expectation.leaseID
            && receipt.standardOutputContentDigest ==
                expectation.standardOutput.contentDigest
            && receipt.standardErrorContentDigest ==
                expectation.standardError.contentDigest
            && validResultCode(receipt.resultCode)
            && validSHA256(receipt.evidenceDigest)
            && receipt.terminalEnvelopeDigest == canonicalEnvelopeDigest(
                resultCode: receipt.resultCode,
                evidenceDigest: receipt.evidenceDigest
            )
    }

    static func canonicalEnvelopeDigest(
        resultCode: String,
        evidenceDigest: ContentDigest
    ) -> ContentDigest? {
        let envelope = KernelPostimageVerifierResultEnvelope(
            evidenceDigest: evidenceDigest,
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

    static func validResultCode(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
