import Foundation
import XCTest
@testable import LoopForge

final class KernelPostimageVerifierResultParserTests: XCTestCase {
    private let evidence = ContentDigest(String(repeating: "a", count: 64))

    func testCanonicalSingleEnvelopeIssuesBoundParseCapability() throws {
        let output = canonicalOutput(resultCode: "accepted")
        let parsed = try KernelPostimageVerifierResultParser().parse(
            standardOutput: output,
            standardError: Data(),
            expectation: expectation(output: output)
        )
        XCTAssertEqual(parsed.receipt.resultCode, "accepted")
        XCTAssertEqual(parsed.receipt.evidenceDigest, evidence)
        XCTAssertEqual(
            parsed.receipt.parserImplementationDigest,
            RequirementVerificationParserFormat.canonicalJSONResultV1
                .implementationIdentityDigest
        )
        XCTAssertEqual(
            parsed.receipt.standardOutputContentDigest,
            KernelPostimageVerifierResultParser.digest(output)
        )
        XCTAssertTrue(KernelPostimageVerifierResultParser.receipt(
            parsed.receipt,
            matches: expectation(output: output)
        ))
        var alteredResult = parsed.receipt
        alteredResult.resultCode = "rejected"
        XCTAssertFalse(KernelPostimageVerifierResultParser.receipt(
            alteredResult,
            matches: expectation(output: output)
        ))
        var alteredEvidence = parsed.receipt
        alteredEvidence.evidenceDigest =
            ContentDigest(String(repeating: "b", count: 64))
        XCTAssertFalse(KernelPostimageVerifierResultParser.receipt(
            alteredEvidence,
            matches: expectation(output: output)
        ))
    }

    func testUnknownKeyWhitespaceAndSemanticTailAreRejected() throws {
        let unknown = Data(
            "{\"evidenceDigest\":\"\(evidence.rawValue)\",\"extra\":true,\"resultCode\":\"accepted\",\"schemaVersion\":1}\n"
                .utf8
        )
        XCTAssertThrowsError(try parse(unknown)) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .unexpectedKeys
            )
        }
        let whitespace = Data(
            "{\"evidenceDigest\": \"\(evidence.rawValue)\",\"resultCode\":\"accepted\",\"schemaVersion\":1}\n"
                .utf8
        )
        XCTAssertThrowsError(try parse(whitespace)) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .nonCanonicalJSON
            )
        }
        let tail = canonicalOutput(resultCode: "accepted")
            + Data("prose\n".utf8)
        XCTAssertThrowsError(try parse(tail)) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .multipleLines
            )
        }
    }

    func testOutputDigestStderrAndParserIdentityAreExact() throws {
        let output = canonicalOutput(resultCode: "accepted")
        var wrongOutput = expectation(output: output)
        wrongOutput.standardOutput.contentDigest =
            ContentDigest(String(repeating: "b", count: 64))
        XCTAssertThrowsError(try KernelPostimageVerifierResultParser().parse(
            standardOutput: output,
            standardError: Data(),
            expectation: wrongOutput
        )) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .outputIdentityMismatch
            )
        }

        let stderr = Data("warning\n".utf8)
        var withStderr = expectation(output: output)
        withStderr.standardError = outputReceipt("stderr", data: stderr)
        XCTAssertThrowsError(try KernelPostimageVerifierResultParser().parse(
            standardOutput: output,
            standardError: stderr,
            expectation: withStderr
        )) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .standardErrorNotEmpty
            )
        }

        var wrongParser = expectation(output: output)
        wrongParser.parser.contentDigest =
            ContentDigest(String(repeating: "c", count: 64))
        XCTAssertThrowsError(try KernelPostimageVerifierResultParser().parse(
            standardOutput: output,
            standardError: Data(),
            expectation: wrongParser
        )) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .invalidExpectation
            )
        }
    }

    func testUnsupportedSchemaAndInvalidEvidenceDigestFailClosed() throws {
        let unsupported = canonicalOutput(resultCode: "accepted", schemaVersion: 2)
        XCTAssertThrowsError(try parse(unsupported)) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .unsupportedSchema
            )
        }
        let invalid = Data(
            "{\"evidenceDigest\":\"not-a-digest\",\"resultCode\":\"accepted\",\"schemaVersion\":1}\n"
                .utf8
        )
        XCTAssertThrowsError(try parse(invalid)) {
            XCTAssertEqual(
                $0 as? KernelPostimageVerifierResultParserError,
                .invalidEvidenceDigest
            )
        }
    }

    private func parse(_ output: Data) throws
        -> AuthorizedKernelPostimageVerifierResultParse {
        try KernelPostimageVerifierResultParser().parse(
            standardOutput: output,
            standardError: Data(),
            expectation: expectation(output: output)
        )
    }

    private func expectation(
        output: Data
    ) -> KernelPostimageVerifierResultParseExpectation {
        KernelPostimageVerifierResultParseExpectation(
            runID: KernelRunID("run"),
            activationReceiptID: ReceiptID("activation"),
            launchReceiptID: ReceiptID("launch"),
            resourceID: OwnedResourceID("resource"),
            leaseID: ResourceLeaseID("lease"),
            parser: RequirementVerificationParserContract(
                id: "canonical-result-parser",
                schemaVersion: 1,
                contentDigest: RequirementVerificationParserFormat
                    .canonicalJSONResultV1.implementationIdentityDigest,
                format: .canonicalJSONResultV1
            ),
            standardOutput: outputReceipt("stdout", data: output),
            standardError: outputReceipt("stderr", data: Data())
        )
    }

    private func outputReceipt(
        _ name: String,
        data: Data
    ) -> KernelPostimageVerifierOutputFileReceipt {
        KernelPostimageVerifierOutputFileReceipt(
            fileName: name,
            byteCount: UInt64(data.count),
            contentDigest: KernelPostimageVerifierResultParser.digest(data)
        )
    }

    private func canonicalOutput(
        resultCode: String,
        schemaVersion: Int = 1
    ) -> Data {
        Data(
            "{\"evidenceDigest\":\"\(evidence.rawValue)\",\"resultCode\":\"\(resultCode)\",\"schemaVersion\":\(schemaVersion)}\n"
                .utf8
        )
    }
}
