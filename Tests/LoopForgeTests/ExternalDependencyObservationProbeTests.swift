import Foundation
import XCTest
@testable import LoopForge

final class ExternalDependencyObservationProbeTests: XCTestCase {
    private let dependencyID = ExternalDependencyID("dependency")
    private let recipeID = ExternalDependencyEvidenceRecipeID("probe")
    private let requestNonce = ContentDigest(String(repeating: "d", count: 64))

    func testExecutableProbeRequiresExactBoundedDirectRecipe() {
        XCTAssertTrue(
            externalDependencyObservationProbeFixture()
                .validationIssues().isEmpty
        )
        XCTAssertTrue(
            externalDependencyObservationProbeFixture(networkPolicy: .enabled)
                .validationIssues().isEmpty
        )

        var missingToken = externalDependencyObservationProbeFixture()
        missingToken.fixedArguments = ["--request"]
        XCTAssertTrue(missingToken.validationIssues().contains {
            $0.contains("one bounded exact request token")
        })

        var permissiveEnvironment = externalDependencyObservationProbeFixture()
        permissiveEnvironment.environmentPolicy = .declaredAllowlist
        XCTAssertTrue(permissiveEnvironment.validationIssues().contains {
            $0.contains("minimal kernel environment")
        })

        var substitutedEnvironment =
            externalDependencyObservationProbeFixture()
        substitutedEnvironment.environmentIdentityDigest = ContentDigest(
            String(repeating: "0", count: 64)
        )
        XCTAssertTrue(substitutedEnvironment.validationIssues().contains {
            $0.contains("exact kernel minimal environment")
        })

        var substitutedCapture = externalDependencyObservationProbeFixture()
        substitutedCapture.captureIdentityDigest = ContentDigest(
            String(repeating: "1", count: 64)
        )
        XCTAssertTrue(substitutedCapture.validationIssues().contains {
            $0.contains("private bounded request and output files")
        })

        var incompleteMapping = externalDependencyObservationProbeFixture()
        incompleteMapping.resultMappings.removeLast()
        XCTAssertTrue(incompleteMapping.validationIssues().contains {
            $0.contains("cover both availability outcomes")
        })

        var childProcess = externalDependencyObservationProbeFixture()
        childProcess.resourceLimits.maximumChildProcesses = 1
        XCTAssertTrue(childProcess.validationIssues().contains {
            $0.contains("forbid child processes")
        })
    }

    func testLegacyDependencyDecodesButCannotAuthorizeNewContract() throws {
        let contract = ExternalDependencyContract(
            id: dependencyID,
            kind: .externalCondition,
            requirementIDs: [RequirementID("requirement")],
            evidenceRecipeID: recipeID,
            authorizedObserverLineageDigests: [ContentDigest("observer")],
            executableProbe: externalDependencyObservationProbeFixture()
        )
        let encoded = try JSONEncoder().encode(contract)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "executableProbe")
        let legacy = try JSONDecoder().decode(
            ExternalDependencyContract.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(legacy.executableProbe)

        var task = taskContract(dependency: legacy)
        XCTAssertTrue(task.validationIssues().contains(
            "external dependency dependency requires one valid executable observation probe"
        ))
        task.externalDependencies?[0].executableProbe =
            externalDependencyObservationProbeFixture()
        XCTAssertTrue(task.validationIssues().isEmpty)
    }

    func testStrictParserBindsRequestAndProducesInertParseAuthority() throws {
        let expectation = parseExpectation()
        let line = try canonicalLine(ExternalDependencyObservationResultEnvelope(
            dependencyID: dependencyID,
            evidenceDigest: ContentDigest(String(repeating: "e", count: 64)),
            evidenceRecipeID: recipeID,
            requestNonce: requestNonce,
            resultCode: "available",
            schemaVersion: 1
        ))
        let parsed = try ExternalDependencyObservationProbe().parse(
            standardOutput: line,
            expectation: expectation
        )

        XCTAssertEqual(parsed.receipt.dependencyID, dependencyID)
        XCTAssertEqual(parsed.receipt.evidenceRecipeID, recipeID)
        XCTAssertEqual(parsed.receipt.requestNonce, requestNonce)
        XCTAssertEqual(parsed.receipt.resultCode, "available")
        XCTAssertEqual(
            parsed.receipt.parserImplementationDigest,
            expectation.parser.contentDigest
        )
    }

    func testStrictParserRejectsStaleNoncanonicalAndExtraOutput() throws {
        let expectation = parseExpectation()
        var stale = ExternalDependencyObservationResultEnvelope(
            dependencyID: dependencyID,
            evidenceDigest: ContentDigest(String(repeating: "e", count: 64)),
            evidenceRecipeID: recipeID,
            requestNonce: ContentDigest(String(repeating: "f", count: 64)),
            resultCode: "unavailable",
            schemaVersion: 1
        )
        XCTAssertThrowsError(try ExternalDependencyObservationProbe().parse(
            standardOutput: canonicalLine(stale),
            expectation: expectation
        )) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationProbeError,
                .mismatchedRequest
            )
        }

        stale.requestNonce = requestNonce
        let noncanonical = Data(
            "{\"schemaVersion\":1,\"resultCode\":\"unavailable\",\"requestNonce\":\"\(requestNonce.rawValue)\",\"evidenceRecipeID\":\"probe\",\"evidenceDigest\":\"\(String(repeating: "e", count: 64))\",\"dependencyID\":\"dependency\"}\n"
                .utf8
        )
        XCTAssertThrowsError(try ExternalDependencyObservationProbe().parse(
            standardOutput: noncanonical,
            expectation: expectation
        )) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationProbeError,
                .nonCanonicalJSON
            )
        }

        var extra = try canonicalLine(stale)
        extra.append(contentsOf: Data("{}\n".utf8))
        XCTAssertThrowsError(try ExternalDependencyObservationProbe().parse(
            standardOutput: extra,
            expectation: expectation
        )) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationProbeError,
                .multipleLines
            )
        }
    }

    func testResultMapperSelectsOnlyExactRatifiedExitAndParserPair()
        throws {
        let probe = externalDependencyObservationProbeFixture()
        let activation = try activationReceipt(probe: probe)
        let available = try ExternalDependencyObservationProbe().parse(
            standardOutput: canonicalLine(
                ExternalDependencyObservationResultEnvelope(
                    dependencyID: dependencyID,
                    evidenceDigest: ContentDigest(
                        String(repeating: "e", count: 64)
                    ),
                    evidenceRecipeID: recipeID,
                    requestNonce: activation.requestArtifact.requestNonce,
                    resultCode: "available",
                    schemaVersion: 1
                )
            ),
            expectation: ExternalDependencyObservationParseExpectation(
                dependencyID: dependencyID,
                evidenceRecipeID: recipeID,
                requestNonce: activation.requestArtifact.requestNonce,
                parser: probe.parser
            )
        )
        let mapped = try XCTUnwrap(
            ExternalDependencyObservationResultMapper.expectedReceipt(
                activation: activation,
                probe: probe,
                nativeExitCode: 0,
                parse: available.receipt
            )
        )
        XCTAssertEqual(mapped.activationReceiptID, activation.id)
        XCTAssertEqual(mapped.mappingOrdinal, 0)
        XCTAssertEqual(mapped.availability, .available)
        XCTAssertEqual(mapped.parsedEvidenceDigest, available.receipt.evidenceDigest)

        XCTAssertNil(ExternalDependencyObservationResultMapper.expectedReceipt(
            activation: activation,
            probe: probe,
            nativeExitCode: 3,
            parse: available.receipt
        ))
        var crosswired = available.receipt
        crosswired.requestNonce = ContentDigest(String(repeating: "0", count: 64))
        XCTAssertNil(ExternalDependencyObservationResultMapper.expectedReceipt(
            activation: activation,
            probe: probe,
            nativeExitCode: 0,
            parse: crosswired
        ))
        var forgedEnvelope = available.receipt
        forgedEnvelope.terminalEnvelopeDigest = ContentDigest(
            String(repeating: "a", count: 64)
        )
        XCTAssertNil(ExternalDependencyObservationResultMapper.expectedReceipt(
            activation: activation,
            probe: probe,
            nativeExitCode: 0,
            parse: forgedEnvelope
        ))
        var substitutedProbe = probe
        substitutedProbe.resultMappings[0].availability = .unavailable
        XCTAssertNil(ExternalDependencyObservationResultMapper.expectedReceipt(
            activation: activation,
            probe: substitutedProbe,
            nativeExitCode: 0,
            parse: available.receipt
        ))
    }

    func testReleaseBoundResultAuthorityRejectsCrossWiredNativeEvidence()
        throws {
        let probe = externalDependencyObservationProbeFixture()
        let activation = try activationReceipt(probe: probe)
        let line = try canonicalLine(
            ExternalDependencyObservationResultEnvelope(
                dependencyID: dependencyID,
                evidenceDigest: ContentDigest(
                    String(repeating: "e", count: 64)
                ),
                evidenceRecipeID: recipeID,
                requestNonce: activation.requestArtifact.requestNonce,
                resultCode: "available",
                schemaVersion: 1
            )
        )
        let parse = try ExternalDependencyObservationProbe().parse(
            standardOutput: line,
            expectation: ExternalDependencyObservationParseExpectation(
                dependencyID: dependencyID,
                evidenceRecipeID: recipeID,
                requestNonce: activation.requestArtifact.requestNonce,
                parser: probe.parser
            )
        ).receipt
        let mapping = try XCTUnwrap(
            ExternalDependencyObservationResultMapper.expectedReceipt(
                activation: activation,
                probe: probe,
                nativeExitCode: 0,
                parse: parse
            )
        )
        let output = ExternalDependencyObservationOutputFileReceipt(
            fileName: "dependency.stdout",
            byteCount: UInt64(line.count),
            contentDigest: ExternalDependencyObservationProbe.digest(line)
        )
        let errorOutput = ExternalDependencyObservationOutputFileReceipt(
            fileName: "dependency.stderr",
            byteCount: 0,
            contentDigest: ExternalDependencyObservationProbe.digest(Data())
        )
        let release = nativeRelease(activation: activation, exitCode: 0)
        let transaction = releaseTransaction()
        let receipt = try XCTUnwrap(
            ExternalDependencyObservationResultAuthority.expectedReceipt(
                activation: activation,
                probe: probe,
                release: release,
                releaseTransaction: transaction,
                standardOutput: output,
                standardError: errorOutput,
                parse: parse,
                mapping: mapping
            )
        )
        XCTAssertTrue(
            ExternalDependencyObservationResultAuthority.receipt(
                receipt,
                matchesActivation: activation,
                probe: probe,
                release: release,
                releaseTransaction: transaction
            )
        )

        var crossWiredRelease = release
        crossWiredRelease.managedProcessExit?.handle.leaseID =
            ResourceLeaseID("other-lease")
        XCTAssertNil(
            ExternalDependencyObservationResultAuthority.expectedReceipt(
                activation: activation,
                probe: probe,
                release: crossWiredRelease,
                releaseTransaction: transaction,
                standardOutput: output,
                standardError: errorOutput,
                parse: parse,
                mapping: mapping
            )
        )
        var duplicate = transaction
        duplicate.duplicate = true
        XCTAssertNil(
            ExternalDependencyObservationResultAuthority.expectedReceipt(
                activation: activation,
                probe: probe,
                release: release,
                releaseTransaction: duplicate,
                standardOutput: output,
                standardError: errorOutput,
                parse: parse,
                mapping: mapping
            )
        )
        var forgedOutput = output
        forgedOutput.contentDigest = ContentDigest(
            String(repeating: "0", count: 64)
        )
        XCTAssertNil(
            ExternalDependencyObservationResultAuthority.expectedReceipt(
                activation: activation,
                probe: probe,
                release: release,
                releaseTransaction: transaction,
                standardOutput: forgedOutput,
                standardError: errorOutput,
                parse: parse,
                mapping: mapping
            )
        )
    }

    private func nativeRelease(
        activation: ExternalDependencyObservationActivationReceipt,
        exitCode: Int32
    ) -> RuntimeReleaseOutcomeReceipt {
        let resourceID = OwnedResourceID("dependency-resource")
        let leaseID = ResourceLeaseID("dependency-lease")
        let releasedAt: UInt64 = 30
        let handle = ManagedProcessHandle(
            runID: activation.runID,
            resourceID: resourceID,
            leaseID: leaseID,
            processID: 42,
            processGroupID: 42,
            externalIdentity: RuntimeExternalIdentity(
                stableDigest: ContentDigest(String(repeating: "9", count: 64)),
                processID: 42,
                processStartMonotonicNanoseconds: 20
            )
        )
        let releaseID = ReceiptID("dependency-release")
        return RuntimeReleaseOutcomeReceipt(
            id: releaseID,
            runID: activation.runID,
            resourceID: resourceID,
            leaseID: leaseID,
            observedAt: Date(timeIntervalSince1970: 30),
            observedAtMonotonicNanoseconds: releasedAt,
            outcome: .released(RuntimeReleaseReceipt(
                id: releaseID,
                runID: activation.runID,
                leaseID: leaseID,
                resourceID: resourceID,
                releasedAtMonotonicNanoseconds: releasedAt,
                duplicate: false
            )),
            managedProcessExit: ManagedProcessExitReceipt(
                handle: handle,
                observedAtMonotonicNanoseconds: releasedAt,
                exitCode: exitCode,
                terminationSignal: nil
            )
        )
    }

    private func releaseTransaction() -> JournalTransactionReceipt {
        JournalTransactionReceipt(
            commandID: RunCommandID("dependency-release-command"),
            startingSequence: 9,
            endingSequence: 9,
            eventIDs: [OrchestrationEventID("dependency-release-event")],
            frameDigest: ContentDigest(String(repeating: "8", count: 64)),
            duplicate: false
        )
    }

    private func parseExpectation()
        -> ExternalDependencyObservationParseExpectation {
        ExternalDependencyObservationParseExpectation(
            dependencyID: dependencyID,
            evidenceRecipeID: recipeID,
            requestNonce: requestNonce,
            parser: externalDependencyObservationProbeFixture().parser
        )
    }

    private func canonicalLine(
        _ envelope: ExternalDependencyObservationResultEnvelope
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(envelope)
        data.append(0x0a)
        return data
    }

    private func activationReceipt(
        probe: ExternalDependencyObservationExecutableProbe
    ) throws -> ExternalDependencyObservationActivationReceipt {
        let runID = KernelRunID("mapping-run")
        let attemptID = AttemptID("mapping-attempt")
        let receiptID = ReceiptID("mapping-activation")
        let observer = ActorIdentity(
            id: ActorID("mapping-observer"),
            role: "external-observer",
            lineageDigest: ContentDigest(String(repeating: "1", count: 64))
        )
        let sourceFrame = ContentDigest(String(repeating: "f", count: 64))
        let nonce = ExternalDependencyObservationActivationCompiler
            .requestNonce(
                runID: runID,
                attemptID: attemptID,
                dependencyID: dependencyID,
                evidenceRecipeID: recipeID,
                observerLineageDigest: observer.lineageDigest,
                receiptID: receiptID,
                sourceJournalSequence: 7,
                sourceJournalFrameDigest: sourceFrame
            )
        let envelope = ExternalDependencyObservationRequestEnvelope(
            attemptID: attemptID,
            dependencyID: dependencyID,
            evidenceRecipeID: recipeID,
            observerLineageDigest: observer.lineageDigest,
            requestNonce: nonce,
            runID: runID,
            schemaVersion: 1,
            sourceJournalFrameDigest: sourceFrame,
            sourceJournalSequence: 7
        )
        let data = try ExternalDependencyObservationRequestArtifactIssuer
            .canonicalData(envelope)
        let requestArtifact =
            ExternalDependencyObservationRequestArtifactReceipt(
                runID: runID,
                attemptID: attemptID,
                dependencyID: dependencyID,
                evidenceRecipeID: recipeID,
                observerLineageDigest: observer.lineageDigest,
                requestNonce: nonce,
                sourceJournalSequence: 7,
                sourceJournalFrameDigest: sourceFrame,
                fileName: ExternalDependencyObservationRequestArtifactIssuer
                    .fileName(receiptID: receiptID),
                contentDigest: ExternalDependencyObservationProbe.digest(data),
                byteCount: UInt64(data.count),
                deviceID: 1,
                inode: 2
            )
        let arguments = probe.fixedArguments.map {
            $0 == ExternalDependencyObservationExecutableProbe
                .requestArgumentToken
                ? ExternalDependencyObservationActivationCompiler
                    .requestDescriptorPath
                : $0
        }
        return ExternalDependencyObservationActivationReceipt(
            schemaVersion: 1,
            id: receiptID,
            runID: runID,
            attemptID: attemptID,
            dependencyID: dependencyID,
            requirementIDs: [RequirementID("requirement")],
            evidenceRecipeID: recipeID,
            observer: observer,
            workerLineageDigest: ContentDigest(
                String(repeating: "2", count: 64)
            ),
            workspaceRootPath: "/tmp/mapping-workspace",
            workspaceRootPathDigest: ContentDigest("mapping-workspace"),
            executableStaging: KernelExecutableStagingReceipt(
                sourceExecutablePath: "/test/source",
                stagedExecutablePath: "/test/staged",
                contentDigest: probe.executableContentDigest,
                byteCount: 1,
                deviceID: 3,
                inode: 4,
                materialization: .streamCopy,
                reusedExistingArtifact: false
            ),
            probeDigest: try XCTUnwrap(
                ExternalDependencyObservationActivationCompiler.probeDigest(
                    probe
                )
            ),
            requestArtifact: requestArtifact,
            resolvedArguments: arguments,
            argumentVectorDigest: KernelProviderInvocationCompiler
                .argumentVectorDigest(arguments),
            environmentIdentityDigest: probe.environmentIdentityDigest,
            captureIdentityDigest: probe.captureIdentityDigest,
            parser: probe.parser,
            resultMappings: probe.resultMappings,
            networkPolicy: probe.networkPolicy,
            resourceLimits: probe.resourceLimits,
            sourceJournalSequence: 7,
            sourceJournalFrameDigest: sourceFrame,
            activatedAt: Date(timeIntervalSince1970: 7)
        )
    }

    private func taskContract(
        dependency: ExternalDependencyContract
    ) -> TaskContract {
        TaskContract(
            id: TaskContractID("contract"),
            schemaVersion: 1,
            verbatimObjective: "Observe one external dependency.",
            objectiveDigest: ContentDigest("objective"),
            requirements: [RequirementContract(
                id: RequirementID("requirement"),
                statement: "Observe one external dependency.",
                mandatory: true,
                evidenceRecipeIDs: []
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            externalDependencies: [dependency],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: false
            ),
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
