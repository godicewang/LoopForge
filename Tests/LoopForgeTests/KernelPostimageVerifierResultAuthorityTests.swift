import Foundation
import XCTest
@testable import LoopForge

final class KernelPostimageVerifierResultAuthorityTests: XCTestCase {
    func testCompleteMappedEvidenceProducesDeterministicResultReceipt() throws {
        let fixture = try Fixture()
        let result = try XCTUnwrap(
            KernelPostimageVerifierResultAuthority.expectedReceipt(
                activation: fixture.activation,
                launch: fixture.launch,
                releaseReceiptID: ReceiptID("release"),
                standardOutput: fixture.stdout,
                standardError: fixture.stderr,
                parse: fixture.parse,
                mapping: fixture.mapping,
                completedAt: fixture.completedAt
            )
        )
        XCTAssertEqual(result.outcome, .accepted)
        XCTAssertEqual(result.sourceRevision, fixture.activation.sourceRevision)
        XCTAssertEqual(result.parsedEvidenceDigest, fixture.parse.evidenceDigest)
        XCTAssertTrue(result.id.rawValue.hasPrefix("postimage-result:"))
        XCTAssertEqual(result.evidenceSetDigest.rawValue.utf8.count, 64)
        XCTAssertEqual(
            result,
            KernelPostimageVerifierResultAuthority.expectedReceipt(
                activation: fixture.activation,
                launch: fixture.launch,
                releaseReceiptID: ReceiptID("release"),
                standardOutput: fixture.stdout,
                standardError: fixture.stderr,
                parse: fixture.parse,
                mapping: fixture.mapping,
                completedAt: fixture.completedAt
            )
        )
    }

    func testCrossWiredParseMappingAndReleaseFailClosed() throws {
        let fixture = try Fixture()
        var crossWired = fixture.mapping
        crossWired.parsedEvidenceDigest =
            ContentDigest(String(repeating: "f", count: 64))
        XCTAssertNil(KernelPostimageVerifierResultAuthority.expectedReceipt(
            activation: fixture.activation,
            launch: fixture.launch,
            releaseReceiptID: ReceiptID("release"),
            standardOutput: fixture.stdout,
            standardError: fixture.stderr,
            parse: fixture.parse,
            mapping: crossWired,
            completedAt: fixture.completedAt
        ))
        var wrongLaunch = fixture.launch
        wrongLaunch.applyReceiptID = ReceiptID("other-apply")
        XCTAssertNil(KernelPostimageVerifierResultAuthority.expectedReceipt(
            activation: fixture.activation,
            launch: wrongLaunch,
            releaseReceiptID: ReceiptID("release"),
            standardOutput: fixture.stdout,
            standardError: fixture.stderr,
            parse: fixture.parse,
            mapping: fixture.mapping,
            completedAt: fixture.completedAt
        ))
        XCTAssertNil(KernelPostimageVerifierResultAuthority.expectedReceipt(
            activation: fixture.activation,
            launch: fixture.launch,
            releaseReceiptID: ReceiptID(""),
            standardOutput: fixture.stdout,
            standardError: fixture.stderr,
            parse: fixture.parse,
            mapping: fixture.mapping,
            completedAt: fixture.completedAt
        ))
    }

    func testPostimageVerificationBatchIsDeterministicAndReleaseOrdered() throws {
        let fixture = try Fixture()
        let result = try XCTUnwrap(fixture.result())
        let release = JournalTransactionReceipt(
            commandID: RunCommandID("release-command"),
            startingSequence: 12,
            endingSequence: 12,
            eventIDs: [OrchestrationEventID("release-event")],
            frameDigest: ContentDigest(String(repeating: "f", count: 64)),
            duplicate: false
        )
        let verification = try XCTUnwrap(
            KernelPostimageVerificationAuthority.expectedReceipt(
                result: result,
                releaseTransaction: release,
                environmentDigest:
                    fixture.launch.processEnvironment.environmentDigest,
                oracleDigest: fixture.activation.probeDigest
            )
        )
        XCTAssertEqual(verification.result, .accepted)
        XCTAssertEqual(verification.attemptID, result.attemptID)
        XCTAssertEqual(verification.requirementIDs, result.requirementIDs)
        XCTAssertEqual(
            verification.postimageEvidenceBatch?.postimageResultID,
            result.id
        )
        XCTAssertEqual(
            verification.postimageEvidenceBatch?
                .postimageReleaseEndingSequence,
            12
        )
        XCTAssertEqual(
            verification,
            KernelPostimageVerificationAuthority.expectedReceipt(
                result: result,
                releaseTransaction: release,
                environmentDigest:
                    fixture.launch.processEnvironment.environmentDigest,
                oracleDigest: fixture.activation.probeDigest
            )
        )
        XCTAssertTrue(
            KernelPostimageVerificationAuthority
                .batchMatchesVerification(verification)
        )
        var tamperedSequence = verification
        tamperedSequence.postimageEvidenceBatch?
            .postimageReleaseEndingSequence += 1
        XCTAssertFalse(
            KernelPostimageVerificationAuthority
                .batchMatchesVerification(tamperedSequence)
        )

        var duplicateRelease = release
        duplicateRelease.duplicate = true
        XCTAssertNil(KernelPostimageVerificationAuthority.expectedReceipt(
            result: result,
            releaseTransaction: duplicateRelease,
            environmentDigest:
                fixture.launch.processEnvironment.environmentDigest,
            oracleDigest: fixture.activation.probeDigest
        ))
        var crossWiredResult = result
        crossWiredResult.id = ReceiptID("postimage-result:wrong")
        XCTAssertNil(KernelPostimageVerificationAuthority.expectedReceipt(
            result: crossWiredResult,
            releaseTransaction: release,
            environmentDigest:
                fixture.launch.processEnvironment.environmentDigest,
            oracleDigest: fixture.activation.probeDigest
        ))
    }

    func testIndependentReviewActivationBindsExactVerificationEvidenceDigest()
        throws {
        let fixture = try Fixture()
        let candidate = RequirementVerificationInputBinding(
            id: "candidate",
            kind: .candidatePostimage,
            artifactID: "candidate-artifact",
            argumentToken: "@loopforge-input:candidate"
        )
        let reviewed = RequirementVerificationInputBinding(
            id: "reviewed-evidence",
            kind: .verificationEvidenceDigest,
            artifactID: "journaled-v2-verification",
            argumentToken: "@loopforge-input:reviewed-evidence"
        )
        let evidenceDigest = ContentDigest(String(repeating: "e", count: 64))
        let probe = RequirementVerificationExecutableProbe(
            schemaVersion: 2,
            transport: .localDirectProcess,
            executableContentDigest:
                fixture.activation.executableStaging.contentDigest,
            fixedArguments: [
                candidate.argumentToken,
                reviewed.argumentToken
            ],
            inputBindings: [candidate, reviewed],
            environmentPolicy: .minimalKernelAllowlist,
            environmentIdentityDigest:
                fixture.activation.environmentIdentityDigest,
            captureIdentityDigest:
                fixture.activation.captureIdentityDigest,
            parser: fixture.activation.parser,
            resultMappings: [RequirementVerificationResultMapping(
                exitCode: 0,
                parserResultCode: "accepted",
                outcome: .accepted
            )],
            unmatchedOutcome: .rejected,
            networkPolicy: .disabled,
            resourceLimits: fixture.activation.resourceLimits
        )
        var activation = fixture.activation
        activation.workspaceRootPathDigest = WorkspaceRepositoryIndexer
            .canonicalRootDigest(URL(
                fileURLWithPath: activation.workspaceRootPath,
                isDirectory: true
            ))
        activation.candidateInputBindingID = candidate.id
        activation.candidateArtifactID = candidate.artifactID
        activation.reviewedVerificationReceiptID = ReceiptID("verification")
        activation.reviewedVerificationEvidenceSetDigest = evidenceDigest
        activation.reviewEvidenceInputBindingID = reviewed.id
        activation.reviewEvidenceArtifactID = reviewed.artifactID
        activation.probeDigest = try XCTUnwrap(
            KernelPostimageVerifierActivationCompiler.probeDigest(probe)
        )
        activation.resolvedArguments = [".", evidenceDigest.rawValue]
        activation.argumentVectorDigest = KernelProviderInvocationCompiler
            .argumentVectorDigest(activation.resolvedArguments)

        XCTAssertTrue(KernelPostimageVerifierActivationCompiler.receipt(
            activation,
            matches: probe
        ))

        activation.resolvedArguments[1] = String(repeating: "f", count: 64)
        activation.argumentVectorDigest = KernelProviderInvocationCompiler
            .argumentVectorDigest(activation.resolvedArguments)
        XCTAssertFalse(KernelPostimageVerifierActivationCompiler.receipt(
            activation,
            matches: probe
        ))
    }

    func testOrdinaryActivationRejectsReviewBindingWithoutReviewIdentity()
        throws {
        let fixture = try Fixture()
        let candidate = RequirementVerificationInputBinding(
            id: "candidate",
            kind: .candidatePostimage,
            artifactID: "candidate-artifact",
            argumentToken: "@loopforge-input:candidate"
        )
        let reviewed = RequirementVerificationInputBinding(
            id: "reviewed-evidence",
            kind: .verificationEvidenceDigest,
            artifactID: "journaled-v2-verification",
            argumentToken: "@loopforge-input:reviewed-evidence"
        )
        let probe = RequirementVerificationExecutableProbe(
            schemaVersion: 2,
            transport: .localDirectProcess,
            executableContentDigest:
                fixture.activation.executableStaging.contentDigest,
            fixedArguments: [
                candidate.argumentToken,
                reviewed.argumentToken
            ],
            inputBindings: [candidate, reviewed],
            environmentPolicy: .minimalKernelAllowlist,
            environmentIdentityDigest:
                fixture.activation.environmentIdentityDigest,
            captureIdentityDigest:
                fixture.activation.captureIdentityDigest,
            parser: fixture.activation.parser,
            resultMappings: [RequirementVerificationResultMapping(
                exitCode: 0,
                parserResultCode: "accepted",
                outcome: .accepted
            )],
            unmatchedOutcome: .rejected,
            networkPolicy: .disabled,
            resourceLimits: fixture.activation.resourceLimits
        )
        var activation = fixture.activation
        activation.workspaceRootPathDigest = WorkspaceRepositoryIndexer
            .canonicalRootDigest(URL(
                fileURLWithPath: activation.workspaceRootPath,
                isDirectory: true
            ))
        activation.candidateInputBindingID = candidate.id
        activation.candidateArtifactID = candidate.artifactID
        activation.probeDigest = try XCTUnwrap(
            KernelPostimageVerifierActivationCompiler.probeDigest(probe)
        )
        activation.resolvedArguments = [".", String(repeating: "e", count: 64)]
        activation.argumentVectorDigest = KernelProviderInvocationCompiler
            .argumentVectorDigest(activation.resolvedArguments)

        XCTAssertFalse(KernelPostimageVerifierActivationCompiler.receipt(
            activation,
            matches: probe
        ))
    }

    private struct Fixture {
        let completedAt = Date(timeIntervalSince1970: 20)
        let activation: KernelPostimageVerifierActivationReceipt
        let launch: KernelPostimageVerifierLaunchReceipt
        let stdout: KernelPostimageVerifierOutputFileReceipt
        let stderr: KernelPostimageVerifierOutputFileReceipt
        let parse: KernelPostimageVerifierResultParseReceipt
        let mapping: KernelPostimageVerifierResultMappingReceipt

        init() throws {
            let evidence = ContentDigest(String(repeating: "a", count: 64))
            let parserDigest = RequirementVerificationParserFormat
                .canonicalJSONResultV1.implementationIdentityDigest
            let parser = RequirementVerificationParserContract(
                id: "parser",
                schemaVersion: 1,
                contentDigest: parserDigest,
                format: .canonicalJSONResultV1
            )
            stdout = KernelPostimageVerifierOutputFileReceipt(
                fileName: "stdout",
                byteCount: 1,
                contentDigest: ContentDigest(String(repeating: "b", count: 64))
            )
            stderr = KernelPostimageVerifierOutputFileReceipt(
                fileName: "stderr",
                byteCount: 0,
                contentDigest: ContentDigest(String(repeating: "c", count: 64))
            )
            parse = KernelPostimageVerifierResultParseReceipt(
                parserImplementationDigest: parserDigest,
                runID: KernelRunID("run"),
                activationReceiptID: ReceiptID("activation"),
                launchReceiptID: ReceiptID("launch"),
                resourceID: OwnedResourceID("resource"),
                leaseID: ResourceLeaseID("lease"),
                standardOutputContentDigest: stdout.contentDigest,
                standardErrorContentDigest: stderr.contentDigest,
                terminalEnvelopeDigest:
                    KernelPostimageVerifierResultParser
                        .canonicalEnvelopeDigest(
                            resultCode: "accepted",
                            evidenceDigest: evidence
                        )!,
                resultCode: "accepted",
                evidenceDigest: evidence
            )
            mapping = KernelPostimageVerifierResultMappingReceipt(
                schemaVersion: 1,
                probeDigest: ContentDigest(String(repeating: "d", count: 64)),
                nativeExitCode: 0,
                parserResultCode: "accepted",
                parsedEvidenceDigest: evidence,
                terminalEnvelopeDigest: parse.terminalEnvelopeDigest,
                mappingOrdinal: 0,
                outcome: .accepted
            )
            let materialization =
                WorkspaceCandidatePostimageMaterializationReceipt(
                    workspaceID: WorkspaceID("workspace"),
                    applyReceiptID: ReceiptID("apply"),
                    sourceRevision:
                        ContentDigest(String(repeating: "e", count: 64)),
                    capturePolicyDigest:
                        ContentDigest(String(repeating: "1", count: 64)),
                    attestationJournalFrameDigest:
                        ContentDigest(String(repeating: "2", count: 64)),
                    snapshotRootPath: "/tmp/candidate",
                    snapshotCanonicalRootDigest:
                        ContentDigest(String(repeating: "3", count: 64)),
                    snapshotEntryManifestDigest:
                        ContentDigest(String(repeating: "4", count: 64)),
                    fileCount: 1,
                    totalBytes: 1,
                    deviceID: 1,
                    inode: 1,
                    materialization: .streamCopy,
                    reusedExistingArtifact: false
                )
            let staging = KernelExecutableStagingReceipt(
                sourceExecutablePath: "/tmp/source",
                stagedExecutablePath: "/tmp/staged",
                contentDigest: ContentDigest(String(repeating: "5", count: 64)),
                byteCount: 1,
                deviceID: 1,
                inode: 1,
                materialization: .streamCopy,
                reusedExistingArtifact: false
            )
            activation = KernelPostimageVerifierActivationReceipt(
                id: ReceiptID("activation"),
                runID: KernelRunID("run"),
                integrationTransactionID: IntegrationTransactionID("tx"),
                applyReceiptID: ReceiptID("apply"),
                attemptID: AttemptID("attempt"),
                requirementID: RequirementID("requirement"),
                requirementIDs: [RequirementID("requirement")],
                evidenceRecipeID: EvidenceRecipeID("recipe"),
                candidateInputBindingID: "candidate",
                candidateArtifactID: "artifact",
                verifier: ActorIdentity(
                    id: ActorID("verifier"),
                    role: "verifier",
                    lineageDigest:
                        ContentDigest(String(repeating: "6", count: 64))
                ),
                workerLineageDigest:
                    ContentDigest(String(repeating: "7", count: 64)),
                workspaceRootPath: "/tmp/workspace",
                workspaceRootPathDigest:
                    ContentDigest(String(repeating: "8", count: 64)),
                sourceRevision: materialization.sourceRevision,
                candidateMaterialization: materialization,
                executableStaging: staging,
                probeDigest: mapping.probeDigest,
                resolvedArguments: ["/tmp/candidate"],
                argumentVectorDigest:
                    ContentDigest(String(repeating: "9", count: 64)),
                environmentIdentityDigest:
                    ContentDigest(String(repeating: "a", count: 64)),
                captureIdentityDigest:
                    ContentDigest(String(repeating: "b", count: 64)),
                parser: parser,
                resourceLimits: RequirementVerificationResourceLimits(
                    maximumWallClockSeconds: 1,
                    maximumCapturedOutputBytes: 1024,
                    maximumResidentBytes: 1024,
                    maximumChildProcesses: 0
                ),
                sourceJournalSequence: 1,
                sourceJournalFrameDigest:
                    ContentDigest(String(repeating: "c", count: 64)),
                activatedAt: Date(timeIntervalSince1970: 10)
            )
            launch = KernelPostimageVerifierLaunchReceipt(
                id: ReceiptID("launch"),
                runID: activation.runID,
                activationReceiptID: activation.id,
                activationJournalFrameDigest:
                    ContentDigest(String(repeating: "d", count: 64)),
                integrationTransactionID:
                    activation.integrationTransactionID,
                applyReceiptID: activation.applyReceiptID,
                attemptID: activation.attemptID,
                evidenceRecipeID: activation.evidenceRecipeID,
                verifier: activation.verifier,
                resourceID: OwnedResourceID("resource"),
                leaseID: ResourceLeaseID("lease"),
                bindingReceiptID: ReceiptID("binding"),
                executableStaging: staging,
                candidateMaterialization: materialization,
                resolvedArguments: activation.resolvedArguments,
                argumentVectorDigest: activation.argumentVectorDigest,
                processEnvironment: KernelProcessEnvironmentReceipt(
                    policy: .minimalKernelAllowlist,
                    variableNames: [],
                    environmentDigest:
                        activation.environmentIdentityDigest
                ),
                processIOFiles: ManagedProcessIOFiles(
                    directoryPath: "/tmp",
                    standardInputFileName: nil,
                    standardOutputFileName: "stdout",
                    standardErrorFileName: "stderr"
                ),
                nativeSandbox: KernelNativeSandboxAttestationReceipt(
                    authorization: KernelNativeSandboxReceipt(
                        schemaVersion: 1,
                        sandbox: .readOnly,
                        networkPolicy: .disabled,
                        launcherPath: "/usr/bin/sandbox-exec",
                        launcherContentDigest:
                            ContentDigest(String(repeating: "a", count: 64)),
                        gateExecutablePath: "/tmp/gate",
                        gateExecutableContentDigest:
                            ContentDigest(String(repeating: "b", count: 64)),
                        profileDigest:
                            ContentDigest(String(repeating: "c", count: 64)),
                        parameterDigest:
                            ContentDigest(String(repeating: "d", count: 64)),
                        workspaceRootPathDigest:
                            activation.workspaceRootPathDigest,
                        journalRunDirectoryPathDigest:
                            ContentDigest(String(repeating: "e", count: 64)),
                        standardOutputPathDigest:
                            ContentDigest(String(repeating: "f", count: 64)),
                        standardErrorPathDigest:
                            ContentDigest(String(repeating: "1", count: 64)),
                        journalWritesDefaultDenied: true,
                        nativeAttestationRequired: true
                    ),
                    processID: 42,
                    observedAtMonotonicNanoseconds: 1,
                        nativeSandboxCheckResult: 1,
                        gateObservedStopped: true,
                        targetExecHandshakeSucceeded: true,
                        candidateWorkingDirectory:
                            KernelCandidateWorkingDirectoryAttestationReceipt(
                                binding: .posixSpawnFileActionsFchdir,
                                deviceID: materialization.deviceID,
                                inode: materialization.inode
                            )
                ),
                parser: parser,
                resourceLimits: activation.resourceLimits,
                launchedAt: Date(timeIntervalSince1970: 11)
            )
        }

        func result() -> KernelPostimageVerifierResultReceipt? {
            KernelPostimageVerifierResultAuthority.expectedReceipt(
                activation: activation,
                launch: launch,
                releaseReceiptID: ReceiptID("release"),
                standardOutput: stdout,
                standardError: stderr,
                parse: parse,
                mapping: mapping,
                completedAt: completedAt
            )
        }
    }
}
