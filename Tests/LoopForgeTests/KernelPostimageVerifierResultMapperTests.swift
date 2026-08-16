import Foundation
import XCTest
@testable import LoopForge

final class KernelPostimageVerifierResultMapperTests: XCTestCase {
    func testExactExitAndParserResultSelectOneRecipeRow() throws {
        let accepted = try XCTUnwrap(
            KernelPostimageVerifierResultMapper.expectedReceipt(
                probe: probe(),
                nativeExitCode: 0,
                parse: parse(resultCode: "accepted")
            )
        )
        XCTAssertEqual(accepted.mappingOrdinal, 0)
        XCTAssertEqual(accepted.outcome, .accepted)
        XCTAssertEqual(accepted.nativeExitCode, 0)
        XCTAssertEqual(accepted.parserResultCode, "accepted")

        let rejected = try XCTUnwrap(
            KernelPostimageVerifierResultMapper.expectedReceipt(
                probe: probe(),
                nativeExitCode: 7,
                parse: parse(resultCode: "rejected")
            )
        )
        XCTAssertEqual(rejected.mappingOrdinal, 1)
        XCTAssertEqual(rejected.outcome, .rejected)
    }

    func testUnmatchedExitOrResultAndTamperedRecipeFailClosed() {
        XCTAssertNil(KernelPostimageVerifierResultMapper.expectedReceipt(
            probe: probe(),
            nativeExitCode: 7,
            parse: parse(resultCode: "accepted")
        ))
        XCTAssertNil(KernelPostimageVerifierResultMapper.expectedReceipt(
            probe: probe(),
            nativeExitCode: 0,
            parse: parse(resultCode: "unknown")
        ))
        var invalid = probe()
        invalid.unmatchedOutcome = .accepted
        XCTAssertNil(KernelPostimageVerifierResultMapper.expectedReceipt(
            probe: invalid,
            nativeExitCode: 0,
            parse: parse(resultCode: "accepted")
        ))
    }

    private func probe() -> RequirementVerificationExecutableProbe {
        RequirementVerificationExecutableProbe(
            schemaVersion: 2,
            transport: .localDirectProcess,
            executableContentDigest:
                ContentDigest(String(repeating: "b", count: 64)),
            fixedArguments: ["@loopforge-input:candidate"],
            inputBindings: [RequirementVerificationInputBinding(
                id: "candidate",
                kind: .candidatePostimage,
                artifactID: "artifact",
                argumentToken: "@loopforge-input:candidate"
            )],
            environmentPolicy: .minimalKernelAllowlist,
            environmentIdentityDigest:
                KernelProcessEnvironmentAuthorizer.environmentDigest(
                    KernelProcessEnvironmentAuthorizer.minimalEnvironment
                ),
            captureIdentityDigest:
                KernelPostimageVerifierCapturePolicy.identityDigest,
            parser: RequirementVerificationParserContract(
                id: "parser",
                schemaVersion: 1,
                contentDigest: RequirementVerificationParserFormat
                    .canonicalJSONResultV1.implementationIdentityDigest,
                format: .canonicalJSONResultV1
            ),
            resultMappings: [
                RequirementVerificationResultMapping(
                    exitCode: 0,
                    parserResultCode: "accepted",
                    outcome: .accepted
                ),
                RequirementVerificationResultMapping(
                    exitCode: 7,
                    parserResultCode: "rejected",
                    outcome: .rejected
                )
            ],
            unmatchedOutcome: .rejected,
            networkPolicy: .disabled,
            resourceLimits: RequirementVerificationResourceLimits(
                maximumWallClockSeconds: 1,
                maximumCapturedOutputBytes: 64 * 1_024,
                maximumResidentBytes: 64 * 1_024 * 1_024,
                maximumChildProcesses: 0
            )
        )
    }

    private func parse(
        resultCode: String
    ) -> KernelPostimageVerifierResultParseReceipt {
        let evidence = ContentDigest(String(repeating: "a", count: 64))
        return KernelPostimageVerifierResultParseReceipt(
            parserImplementationDigest: RequirementVerificationParserFormat
                .canonicalJSONResultV1.implementationIdentityDigest,
            runID: KernelRunID("run"),
            activationReceiptID: ReceiptID("activation"),
            launchReceiptID: ReceiptID("launch"),
            resourceID: OwnedResourceID("resource"),
            leaseID: ResourceLeaseID("lease"),
            standardOutputContentDigest:
                ContentDigest(String(repeating: "c", count: 64)),
            standardErrorContentDigest:
                ContentDigest(String(repeating: "d", count: 64)),
            terminalEnvelopeDigest:
                KernelPostimageVerifierResultParser.canonicalEnvelopeDigest(
                    resultCode: resultCode,
                    evidenceDigest: evidence
                )!,
            resultCode: resultCode,
            evidenceDigest: evidence
        )
    }
}
