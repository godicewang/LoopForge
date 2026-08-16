import Foundation
import XCTest
@testable import LoopForge

final class JournaledProcessRuntimeTests: XCTestCase {
    private let runID = KernelRunID("journaled-process-run")
    private let actor = ActorIdentity(
        id: ActorID("journaled-process-owner"),
        role: "runtime-owner",
        lineageDigest: ContentDigest("journaled-process-lineage")
    )

    func testJournaledProviderAPIOwnsPromptInvocationSandboxLaunchAndReceipt() async throws {
        let name = "provider-api"
        let fixture = try await makeEmptyFixture(name, provider: .local)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let invocation = try await runtime.prepareProviderInvocation(
            prompt: Data("journaled runtime provider prompt".utf8),
            promptFileName: "provider-prompt.json",
            requestNonce: KernelWorkerResultParser.contentDigest(
                Data("provider-runtime-nonce".utf8)
            )
        )

        let start = try await runtime.admitAndLaunchProvider(
            request: leaseRequest(name),
            executablePath: kernelProcessFixturePath,
            invocation: invocation,
            secretCapability: nil,
            standardOutputFileName: "provider-stdout.jsonl",
            standardErrorFileName: "provider-stderr.txt",
            admissionReceiptID: ReceiptID("provider-admission"),
            admissionCommandID: RunCommandID("provider-admit"),
            bindingReceiptID: ReceiptID("provider-binding"),
            providerLaunchReceiptID: ReceiptID("provider-launch"),
            bindingCommandID: RunCommandID("provider-bind"),
            launchFailureReleaseReceiptID: ReceiptID("provider-launch-failure-release"),
            launchFailureReleaseCommandID:
                RunCommandID("provider-launch-failure-release")
        )

        XCTAssertEqual(start.launch.providerInvocation, invocation.receipt)
        let contextTransport = try XCTUnwrap(
            start.launch.providerInvocationContextTransport
        )
        XCTAssertEqual(
            contextTransport,
            start.launch.providerLaunch?.invocationContextTransport
        )
        XCTAssertTrue(contextTransport.isValid(for: invocation.receipt))
        XCTAssertEqual(contextTransport.targetDescriptor, 196)
        XCTAssertNil(start.launch.providerSecretDelivery)
        let providerLaunch = try XCTUnwrap(start.launch.providerLaunch)
        XCTAssertEqual(providerLaunch.invocation, invocation.receipt)
        XCTAssertNil(providerLaunch.secretDelivery)
        XCTAssertEqual(providerLaunch.schemaVersion, 2)
        XCTAssertEqual(
            providerLaunch.resourceLimits,
            KernelProviderInvocationCompiler.requiredResourceLimits
        )
        XCTAssertEqual(
            start.launch.handle.externalIdentity.kernelResourceLimits,
            KernelProviderInvocationCompiler.requiredResourceLimits
        )
        XCTAssertTrue(providerLaunch.isValid(binding: start.launch.binding))
        XCTAssertEqual(start.launch.journalTransaction.eventIDs.count, 2)
        let journaledProviderLaunch = await fixture.journal.providerLaunchReceipt(
            transaction: start.launch.journalTransaction
        )
        XCTAssertEqual(journaledProviderLaunch, providerLaunch)
        let stateBeforeRelease = await fixture.journal.state
        XCTAssertEqual(
            start.launch.handle.externalIdentity.argumentVectorContentDigest,
            invocation.receipt.argumentVectorDigest
        )
        XCTAssertEqual(
            start.launch.handle.externalIdentity.nativeSandboxAttestation?
                .targetExecHandshakeSucceeded,
            true
        )
        guard case .accepted = start.admission.outcome else {
            return XCTFail("Expected provider process admission")
        }
        let projectedLease = await fixture.journal.runtimeLease(
            resourceID: OwnedResourceID("resource-\(name)")
        )
        let lease = try XCTUnwrap(projectedLease)
        let release = try await runtime.joinAndRelease(
            lease: lease,
            releaseReceiptID: ReceiptID("provider-release"),
            commandID: RunCommandID("provider-release"),
            timeoutNanoseconds: 2_000_000_000
        )
        XCTAssertEqual(release.exit.exitCode, 0)
        let runDirectory = fixture.journalRoot.appendingPathComponent(
            runID.rawValue,
            isDirectory: true
        )
        let expectedResultDigest = ContentDigest(String(repeating: "c", count: 64))
        XCTAssertEqual(
            try String(
                contentsOf: runDirectory.appendingPathComponent(
                    "provider-stdout.jsonl"
                ),
                encoding: .utf8
            ),
            "{\"invocationDigest\":\"\(invocation.receipt.invocationDigest.rawValue)\","
                + "\"proposedDisposition\":\"completed\","
                + "\"requestNonce\":\"\(invocation.receipt.requestNonce.rawValue)\","
                + "\"resultDigest\":\"\(expectedResultDigest.rawValue)\","
                + "\"schemaVersion\":1,\"sequence\":0,"
                + "\"threadID\":\"fixture-provider\",\"type\":\"terminal\"}\n"
        )
        XCTAssertTrue(
            try Data(
                contentsOf: runDirectory.appendingPathComponent(
                    "provider-stderr.txt"
                )
            ).isEmpty
        )
        let projection = await runtime.projection()
        XCTAssertTrue(projection.adapter.liveHandles.isEmpty)
        XCTAssertTrue(projection.inDoubtResourceIDs.isEmpty)

        let parsed = try await runtime.parseReleasedWorkerResult(
            start: start,
            release: release,
            invocationDigest: invocation.receipt.invocationDigest,
            requestNonce: invocation.receipt.requestNonce,
            receiptID: ReceiptID("provider-result-parse"),
            commandID: RunCommandID("provider-result-parse")
        )
        XCTAssertEqual(parsed.parse.proposedDisposition, .completed)
        XCTAssertEqual(parsed.parse.proposedResultDigest, expectedResultDigest)
        XCTAssertEqual(parsed.parse.threadID, "fixture-provider")
        let derived = try await runtime.deriveReleasedWorkerExecution(
            parse: parsed,
            receiptID: ReceiptID("provider-result-derive"),
            commandID: RunCommandID("provider-result-derive")
        )
        XCTAssertEqual(derived.execution.disposition, .completed)

        let recovered = try RunJournal(
            rootDirectory: fixture.journalRoot,
            runID: runID
        )
        let recoveredProviderLaunch = await recovered.providerLaunchReceipt(
            receiptID: providerLaunch.id
        )
        XCTAssertEqual(recoveredProviderLaunch, providerLaunch)
        let recoveredProjection = await recovered.currentProjection()
        XCTAssertEqual(recoveredProjection.providerLaunchCount, 1)
        let recoveredBinding = await recovered.runtimeBindingReceipt(
            transaction: start.launch.journalTransaction
        )
        XCTAssertEqual(recoveredBinding, start.launch.binding)

        var preBindingState = stateBeforeRelease
        preBindingState.sequence -= 2
        preBindingState.processedCommandIDs.remove(
            start.launch.journalTransaction.commandID
        )
        preBindingState.runtimeBindingReceipts[start.launch.binding.id] = nil
        preBindingState.providerLaunchReceipts?[providerLaunch.id] = nil
        preBindingState.runtimeLiveLeases[
            start.launch.binding.resourceID
        ]?.request.externalIdentity = nil
        var tampered = providerLaunch
        tampered.receiptDigest = ContentDigest(
            String(repeating: "0", count: 64)
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: preBindingState,
                command: .recordProviderRuntimeBinding(
                    .testOnly(
                        binding: start.launch.binding,
                        receipt: tampered
                    )
                ),
                context: KernelCommandContext(
                    commandID: RunCommandID("tampered-provider-bind"),
                    expectedSequence: preBindingState.sequence,
                    issuedAt: Date(),
                    actor: actor
                )
            ),
            .rejected(.invalidRuntimeReceipt(
                "provider launch provenance mismatch"
            ))
        )
    }

    func testInvalidSpecificationRejectsBeforeAdmission() async throws {
        let fixture = try await makeEmptyFixture("invalid-specification")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor
        )

        await XCTAssertThrowsRuntimeError(.invalidSpecification) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("invalid-specification"),
                specification: self.specification("bin/true"),
                id: "invalid-specification"
            )
        }
        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testProductiveProcessCannotLaunchWithoutActiveCausalAttempt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-JournaledProcess-unauthorized-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        let supervisor = makeSupervisor()
        _ = try await journal.transactAtCurrentSequence(
            .createRun(contract()),
            commandID: RunCommandID("create-unauthorized"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        let runtime = JournaledProcessRuntime(
            supervisor: supervisor,
            journal: journal,
            actorIdentity: actor
        )

        await XCTAssertThrowsRuntimeError(.executionNotAuthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("unauthorized"),
                specification: self.specification("/usr/bin/true"),
                id: "unauthorized"
            )
        }

        let journalProjection = await journal.currentProjection()
        let supervisorProjection = await supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 1)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testProductiveProcessRejectsProofFromUnrelatedJournalTransaction() async throws {
        let fixture = try await makeEmptyFixture("cross-wired-proof")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        guard let unrelatedTransaction = await fixture.journal.transactionReceipt(
            commandID: RunCommandID("create-cross-wired-proof")
        ) else {
            return XCTFail("Expected the unrelated create transaction")
        }
        let forgedProof = JournaledKernelExecutionProof.testOnly(
            runID: runID,
            attemptID: AttemptID("attempt-cross-wired-proof"),
            nodeID: KernelNodeID("process-node"),
            strategyFingerprint: causalStrategy().fingerprint,
            workerExecutionProfile: workerExecutionProfile(),
            workspaceRoot: fixture.proof.workspaceRoot,
            activationActor: actor,
            activationTransaction: unrelatedTransaction
        )
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: forgedProof
        )

        await XCTAssertThrowsRuntimeError(.executionNotAuthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("cross-wired-proof"),
                specification: self.specification("/usr/bin/true"),
                id: "cross-wired-proof"
            )
        }

        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testProductiveProcessRejectsCrossWiredWorkerProfileAndActor() async throws {
        let fixture = try await makeEmptyFixture("cross-wired-worker-profile")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let crossWiredProfile = KernelAgentExecutionProfile(
            provider: .codex,
            providerReference: "other-worker-harness",
            executableContentDigest: executableDigest("/usr/bin/true"),
            modelID: "other-worker-model",
            reasoningEffort: "low",
            sandbox: .readOnly,
            networkPolicy: .disabled,
            pluginPolicy: .disabled,
            environmentPolicy: .minimalKernelAllowlist
        )
        let crossWiredProof = JournaledKernelExecutionProof.testOnly(
            runID: fixture.proof.runID,
            attemptID: fixture.proof.attemptID,
            nodeID: fixture.proof.nodeID,
            strategyFingerprint: fixture.proof.strategyFingerprint,
            workerExecutionProfile: crossWiredProfile,
            workspaceRoot: fixture.proof.workspaceRoot,
            activationActor: actor,
            activationTransaction: fixture.proof.activationTransaction
        )
        let crossWiredRuntime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: crossWiredProof
        )
        await XCTAssertThrowsRuntimeError(.executionNotAuthorized) {
            _ = try await self.admitAndLaunch(
                crossWiredRuntime,
                request: self.leaseRequest("cross-wired-worker-profile"),
                specification: self.specification("/usr/bin/true"),
                id: "cross-wired-worker-profile"
            )
        }

        let otherActor = ActorIdentity(
            id: ActorID("other-runtime-owner"),
            role: actor.role,
            lineageDigest: ContentDigest("other-runtime-lineage")
        )
        let crossWiredActorRuntime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: otherActor,
            executionProof: fixture.proof
        )
        await XCTAssertThrowsRuntimeError(.executionNotAuthorized) {
            _ = try await self.admitAndLaunch(
                crossWiredActorRuntime,
                request: self.leaseRequest("cross-wired-actor"),
                specification: self.specification("/usr/bin/true"),
                id: "cross-wired-actor"
            )
        }
        let crossWiredSupervisorProjection = await fixture.supervisor.projection()
        XCTAssertTrue(crossWiredSupervisorProjection.liveLeases.isEmpty)
    }

    func testExecutableContentMismatchRejectsBeforeAdmission() async throws {
        let fixture = try await makeEmptyFixture("executable-content-mismatch")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let mismatched = ManagedProcessSpecification(
            executablePath: "/usr/bin/true",
            arguments: [],
            environment: [:]
        )
        await XCTAssertThrowsRuntimeError(.executableIdentityMismatch) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("executable-content-mismatch"),
                specification: mismatched,
                id: "executable-content-mismatch"
            )
        }
        let mismatchJournalProjection = await fixture.journal.currentProjection()
        let mismatchSupervisorProjection = await fixture.supervisor.projection()
        let mismatchRuntimeProjection = await runtime.projection()
        XCTAssertEqual(mismatchJournalProjection.sequence, 6)
        XCTAssertTrue(mismatchSupervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(mismatchRuntimeProjection.adapter.liveHandles.isEmpty)
    }

    func testCallerSuppliedEnvironmentRejectsBeforeAdmission() async throws {
        let fixture = try await makeEmptyFixture("caller-environment")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        var injected = specification("/usr/bin/true")
        injected.environment = [
            "PATH": "/attacker/bin",
            "PRIVATE_API_KEY": "must-not-reach-worker"
        ]

        await XCTAssertThrowsRuntimeError(.executionEnvironmentUnauthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("caller-environment"),
                specification: injected,
                id: "caller-environment"
            )
        }

        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testDeclaredEnvironmentPolicyRejectsWithoutTypedVariableGrant() async throws {
        let fixture = try await makeEmptyFixture(
            "declared-environment",
            environmentPolicy: .declaredAllowlist
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let rejectedPromptName = "declared-environment-provider-prompt.json"
        await XCTAssertThrowsRuntimeError(.providerInvocationUnauthorized) {
            _ = try await runtime.prepareProviderInvocation(
                prompt: Data("must not be materialized".utf8),
                promptFileName: rejectedPromptName,
                requestNonce: KernelWorkerResultParser.contentDigest(
                    Data("declared-environment-provider-nonce".utf8)
                )
            )
        }
        let runDirectory = await fixture.journal.runDirectory
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: runDirectory.appendingPathComponent(
                    rejectedPromptName
                ).path
            )
        )

        await XCTAssertThrowsRuntimeError(.executionEnvironmentUnauthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("declared-environment"),
                specification: self.specification("/usr/bin/true"),
                id: "declared-environment"
            )
        }

        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testCallerSuppliedEnvironmentDigestCannotOverrideKernelEnvironment() async throws {
        let fixture = try await makeEmptyFixture("caller-environment-digest")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        var injected = specification("/usr/bin/true")
        injected.expectedEnvironmentContentDigest = ContentDigest(
            String(repeating: "0", count: 64)
        )

        await XCTAssertThrowsRuntimeError(.executionEnvironmentUnauthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("caller-environment-digest"),
                specification: injected,
                id: "caller-environment-digest"
            )
        }

        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testNativeChildObservesOnlyExactKernelMinimalEnvironment() async throws {
        let fixture = try await makeEmptyFixture("native-minimal-environment")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let journalRunDirectory = await fixture.journal.runDirectory
        let outputName = "minimal-environment.txt"
        let worker = ManagedProcessSpecification(
            executablePath: kernelProcessFixturePath,
            arguments: ["--dump-environment"],
            environment: [:],
            ioFiles: ManagedProcessIOFiles(
                directoryPath: journalRunDirectory.path,
                standardInputFileName: nil,
                standardOutputFileName: outputName,
                standardErrorFileName: "minimal-environment-stderr.txt"
            )
        )

        let start = try await admitAndLaunch(
            runtime,
            request: leaseRequest("native-minimal-environment"),
            specification: worker,
            id: "native-minimal-environment"
        )
        guard case .accepted(_, duplicate: false) = start.admission.outcome else {
            return XCTFail("Expected a new journaled admission")
        }
        let projectedLease = await fixture.journal.runtimeLease(
            resourceID: OwnedResourceID("resource-native-minimal-environment")
        )
        let lease = try XCTUnwrap(projectedLease)
        let release = try await runtime.joinAndRelease(
            lease: lease,
            releaseReceiptID: ReceiptID("release-native-minimal-environment"),
            commandID: RunCommandID("release-native-minimal-environment"),
            timeoutNanoseconds: 2_000_000_000
        )
        XCTAssertEqual(release.exit.exitCode, 0)
        XCTAssertEqual(
            try String(
                contentsOf: journalRunDirectory.appendingPathComponent(outputName),
                encoding: .utf8
            ),
            "LANG=C\nLC_ALL=C\nNO_COLOR=1\nPATH=/usr/bin:/bin:/usr/sbin:/sbin\n"
        )
        XCTAssertEqual(
            try Data(
                contentsOf: journalRunDirectory.appendingPathComponent(
                    "minimal-environment-stderr.txt"
                )
            ),
            Data()
        )
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testNativeRetainedResultIsStrictlyParsedAndJournaledAsProposal() async throws {
        let fixture = try await makeEmptyFixture("native-worker-result")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let invocationDigest = ContentDigest(String(repeating: "a", count: 64))
        let nonce = ContentDigest(String(repeating: "b", count: 64))
        let resultDigest = ContentDigest(String(repeating: "c", count: 64))
        let journalRunDirectory = await fixture.journal.runDirectory
        let worker = ManagedProcessSpecification(
            executablePath: kernelProcessFixturePath,
            arguments: [
                "--emit-worker-result",
                invocationDigest.rawValue,
                nonce.rawValue,
                "thread-native",
                "completed",
                resultDigest.rawValue
            ],
            environment: [:],
            ioFiles: ManagedProcessIOFiles(
                directoryPath: journalRunDirectory.path,
                standardInputFileName: nil,
                standardOutputFileName: "worker-result.jsonl",
                standardErrorFileName: "worker-result.stderr"
            )
        )

        let start = try await admitAndLaunch(
            runtime,
            request: leaseRequest("native-worker-result"),
            specification: worker,
            id: "native-worker-result"
        )
        let projectedLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        )
        let lease = try XCTUnwrap(projectedLease)
        let release = try await runtime.joinAndRelease(
            lease: lease,
            releaseReceiptID: ReceiptID("release-native-worker-result"),
            commandID: RunCommandID("release-native-worker-result"),
            timeoutNanoseconds: 2_000_000_000
        )
        let parsed = try await runtime.parseReleasedWorkerResult(
            start: start,
            release: release,
            invocationDigest: invocationDigest,
            requestNonce: nonce,
            receiptID: ReceiptID("parse-native-worker-result"),
            commandID: RunCommandID("parse-native-worker-result")
        )

        XCTAssertEqual(parsed.parse.proposedDisposition, .completed)
        XCTAssertEqual(parsed.parse.proposedResultDigest, resultDigest)
        XCTAssertEqual(parsed.parse.threadID, "thread-native")
        XCTAssertEqual(parsed.parse.eventCount, 1)
        XCTAssertEqual(parsed.parse.nativeExit, release.exit)
        let journaledParse = await fixture.journal.workerResultParseReceipt(
            transaction: parsed.journalTransaction
        )
        XCTAssertEqual(journaledParse, parsed.parse)
        let state = await fixture.journal.state
        XCTAssertNil(state.attempts[AttemptID("attempt-native-worker-result")]?.disposition)
        XCTAssertEqual(state.workerResultParseReceipts?[parsed.parse.id], parsed.parse)

        let duplicate = try await runtime.parseReleasedWorkerResult(
            start: start,
            release: release,
            invocationDigest: invocationDigest,
            requestNonce: nonce,
            receiptID: ReceiptID("parse-native-worker-result"),
            commandID: RunCommandID("parse-native-worker-result")
        )
        XCTAssertEqual(duplicate.parse, parsed.parse)
        XCTAssertEqual(duplicate.journalTransaction, parsed.journalTransaction)

        let derived = try await runtime.deriveReleasedWorkerExecution(
            parse: parsed,
            receiptID: ReceiptID("derive-native-worker-result"),
            commandID: RunCommandID("derive-native-worker-result")
        )
        XCTAssertEqual(derived.execution.disposition, .completed)
        XCTAssertEqual(
            derived.execution.source,
            .workerResultParse(parsed.parse.id)
        )
        let derivedState = await fixture.journal.state
        XCTAssertEqual(
            derivedState.attempts[AttemptID("attempt-native-worker-result")]?.disposition,
            .completed
        )
        let journaledDerivation = await fixture.journal.executionDerivationReceipt(
            transaction: derived.journalTransaction
        )
        XCTAssertEqual(journaledDerivation, derived.execution)
        let duplicateDerivation = try await runtime.deriveReleasedWorkerExecution(
            parse: parsed,
            receiptID: ReceiptID("derive-native-worker-result"),
            commandID: RunCommandID("derive-native-worker-result")
        )
        XCTAssertEqual(duplicateDerivation.execution, derived.execution)
        XCTAssertEqual(duplicateDerivation.journalTransaction, derived.journalTransaction)

        let sequenceBeforeForgery = await fixture.journal.currentProjection().sequence
        let forgedAuthorized = try KernelWorkerResultParser().parseAuthorizedRetainedFiles(
            directoryPath: try XCTUnwrap(start.launch.processIOFiles).directoryPath,
            standardOutputFileName: "worker-result.jsonl",
            standardErrorFileName: "worker-result.stderr",
            expectation: KernelWorkerResultParseExpectation(
                runID: runID,
                attemptID: AttemptID("attempt-native-worker-result"),
                resourceID: start.launch.handle.resourceID,
                leaseID: start.launch.handle.leaseID,
                bindingReceiptID: start.launch.binding.id,
                releaseReceiptID: ReceiptID("release-from-unrelated-process"),
                invocationDigest: invocationDigest,
                requestNonce: nonce,
                nativeExit: release.exit
            ),
            receiptID: ReceiptID("parse-native-worker-result-forged")
        )
        let forged = forgedAuthorized.receipt
        do {
            _ = try await fixture.journal.transactAtCurrentSequence(
                .recordWorkerResultParse(forgedAuthorized),
                commandID: RunCommandID("parse-native-worker-result-forged"),
                issuedAt: Date(timeIntervalSince1970: 11),
                actor: actor
            )
            XCTFail("A cross-wired release receipt must not authorize worker output")
        } catch {
            XCTAssertEqual(
                error as? RunJournalError,
                .reducerRejected(.invalidRuntimeReceipt(
                    "worker result parse does not match journaled process provenance"
                ))
            )
        }
        let sequenceAfterForgery = await fixture.journal.currentProjection().sequence
        XCTAssertEqual(sequenceAfterForgery, sequenceBeforeForgery)
        let forgedReceipt = await fixture.journal.workerResultParseReceipt(
            receiptID: forged.id
        )
        XCTAssertNil(forgedReceipt)

        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredParse = await recovered.workerResultParseReceipt(
            receiptID: parsed.parse.id
        )
        XCTAssertEqual(recoveredParse, parsed.parse)
    }

    func testLegacyContractWithoutExecutionProfileCannotMaterialize() async throws {
        let fixture = try await makeEmptyFixture(
            "legacy-contract-profile",
            includeExecutionProfile: false
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        await XCTAssertThrowsRuntimeError(.executionNotAuthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("legacy-contract-profile"),
                specification: self.specification("/usr/bin/true"),
                id: "legacy-contract-profile"
            )
        }
        let legacySupervisorProjection = await fixture.supervisor.projection()
        XCTAssertTrue(legacySupervisorProjection.liveLeases.isEmpty)
    }

    func testProductiveProcessRejectsIOOutsideJournalDirectory() async throws {
        let fixture = try await makeEmptyFixture("outside-journal-io")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var escaped = specification("/usr/bin/true")
        escaped.ioFiles = ManagedProcessIOFiles(
            directoryPath: fixture.root.path,
            standardInputFileName: nil,
            standardOutputFileName: "escaped-output.txt",
            standardErrorFileName: nil
        )
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )

        await XCTAssertThrowsRuntimeError(.executionIOUnauthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("outside-journal-io"),
                specification: escaped,
                id: "outside-journal-io"
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.root.appendingPathComponent("escaped-output.txt").path
            )
        )
        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testFullAccessProfileRejectsBeforeAdmissionStagingOrNativeSpawn() async throws {
        let fixture = try await makeEmptyFixture(
            "full-access-native-sandbox",
            sandbox: .fullAccess
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )

        await XCTAssertThrowsRuntimeError(.nativeSandboxUnauthorized) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("full-access-native-sandbox"),
                specification: self.specification("/usr/bin/true"),
                id: "full-access-native-sandbox"
            )
        }

        let projection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        let stagingDirectory = await fixture.journal.runDirectory.appendingPathComponent(
            KernelExecutableStager.directoryName,
            isDirectory: true
        )
        XCTAssertEqual(projection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
    }

    func testAdmissionLaunchBindingAndReleaseAreJournaledEndToEnd() async throws {
        let fixture = try await makeEmptyFixture("end-to-end")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let request = leaseRequest("end-to-end")

        let start = try await admitAndLaunch(
            runtime,
            request: request,
            specification: specification("/bin/sleep", arguments: ["30"]),
            id: "end-to-end"
        )
        guard case .accepted(let lease, duplicate: false) = start.admission.outcome else {
            return XCTFail("Expected a new journaled admission")
        }
        XCTAssertEqual(start.launch.handle.leaseID, lease.request.leaseID)
        XCTAssertEqual(
            start.launch.executableStaging.sourceExecutablePath,
            kernelProcessFixturePath
        )
        XCTAssertEqual(
            start.launch.executableStaging.contentDigest,
            fixture.proof.workerExecutionProfile.executableContentDigest
        )
        XCTAssertFalse(start.launch.executableStaging.reusedExistingArtifact)
        let journalRunDirectory = await fixture.journal.runDirectory
        XCTAssertTrue(
            start.launch.executableStaging.stagedExecutablePath.hasPrefix(
                journalRunDirectory.path + "/runtime-executables/"
            )
        )
        XCTAssertNotEqual(
            start.launch.executableStaging.stagedExecutablePath,
            start.launch.executableStaging.sourceExecutablePath
        )
        XCTAssertEqual(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: start.launch.executableStaging.stagedExecutablePath
            ),
            start.launch.executableStaging.contentDigest
        )
        XCTAssertEqual(
            start.launch.processEnvironment.policy,
            .minimalKernelAllowlist
        )
        XCTAssertEqual(
            start.launch.processEnvironment.variableNames,
            ["LANG", "LC_ALL", "NO_COLOR", "PATH"]
        )
        XCTAssertEqual(
            start.launch.processEnvironment.environmentDigest,
            KernelProcessEnvironmentAuthorizer.environmentDigest(
                KernelProcessEnvironmentAuthorizer.minimalEnvironment
            )
        )
        let boundLease = await fixture.journal.runtimeLease(resourceID: request.resourceID)
        XCTAssertNotNil(boundLease?.request.externalIdentity)
        XCTAssertEqual(
            boundLease?.request.externalIdentity?.executableContentDigest,
            start.launch.executableStaging.contentDigest
        )
        XCTAssertEqual(
            boundLease?.request.externalIdentity?.environmentContentDigest,
            start.launch.processEnvironment.environmentDigest
        )
        XCTAssertEqual(
            start.launch.handle.externalIdentity.nativeSandboxAttestation,
            start.launch.nativeSandbox
        )
        XCTAssertEqual(
            boundLease?.request.externalIdentity?.nativeSandboxAttestation,
            start.launch.nativeSandbox
        )
        XCTAssertTrue(start.launch.nativeSandbox.gateObservedStopped)
        XCTAssertTrue(start.launch.nativeSandbox.targetExecHandshakeSucceeded)
        let recoveredBound = try RunJournal(
            rootDirectory: fixture.journalRoot,
            runID: runID
        )
        let recoveredBoundLease = await recoveredBound.runtimeLease(
            resourceID: request.resourceID
        )
        XCTAssertEqual(
            recoveredBoundLease?.request.externalIdentity?.nativeSandboxAttestation,
            start.launch.nativeSandbox
        )

        _ = try await runtime.terminate(
            lease: boundLease!,
            releaseReceiptID: ReceiptID("release-end-to-end"),
            commandID: RunCommandID("release-end-to-end"),
            graceNanoseconds: 100_000_000
        )
        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredProjection = await recovered.currentProjection()
        XCTAssertEqual(recoveredProjection.sequence, 9)
        XCTAssertEqual(recoveredProjection.runtimeLiveResourceCount, 0)
        let supervisorProjection = await fixture.supervisor.projection()
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
    }

    func testSymlinkedExecutableStagingDirectoryRejectsBeforeAdmission() async throws {
        let fixture = try await makeEmptyFixture("symlinked-staging")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let journalRunDirectory = await fixture.journal.runDirectory
        let staging = journalRunDirectory.appendingPathComponent(
            KernelExecutableStager.directoryName,
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: outside)
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )

        await XCTAssertThrowsRuntimeError(.executableIdentityMismatch) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("symlinked-staging"),
                specification: self.specification("/usr/bin/true"),
                id: "symlinked-staging"
            )
        }
        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 6)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        XCTAssertTrue(
            (try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty
        )
    }

    func testOwnedProcessBridgeRequiresExactJournaledExitAndRelease() async throws {
        let fixture = try await makeEmptyFixture("owned-occurrence")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let recorder = JournaledOccurrenceRecorder(
            journal: fixture.journal,
            actorIdentity: actor
        )
        let bridge = JournaledOwnedProcessOccurrenceBridge(
            journal: fixture.journal,
            supervisor: fixture.supervisor,
            recorder: recorder
        )
        let start = try await admitAndLaunch(
            runtime,
            request: leaseRequest("owned-occurrence"),
            specification: specification("/bin/sleep", arguments: ["0.05"]),
            id: "owned-occurrence"
        )
        var crossWiredStart = start
        crossWiredStart.admissionTransaction = start.launch.journalTransaction
        do {
            _ = try await bridge.begin(
                start: crossWiredStart,
                invocation: .scheduled(scheduleID: ScheduleID("schedule"), ordinal: 0)
            )
            XCTFail("An unrelated journal frame must not authorize the start")
        } catch {
            XCTAssertEqual(
                error as? JournaledOwnedProcessOccurrenceBridgeError,
                .unjournaledStart
            )
        }
        let token = try await bridge.begin(
            start: start,
            invocation: .scheduled(scheduleID: ScheduleID("schedule"), ordinal: 1)
        )
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let projectedBoundLease = await fixture.journal.runtimeLease(
            resourceID: OwnedResourceID("resource-owned-occurrence")
        )
        let boundLease = try XCTUnwrap(projectedBoundLease)
        let release = try await runtime.terminate(
            lease: boundLease,
            releaseReceiptID: ReceiptID("release-owned-occurrence"),
            commandID: RunCommandID("release-owned-occurrence"),
            graceNanoseconds: 100_000_000
        )

        var mismatched = release
        mismatched.termination.handle.leaseID = ResourceLeaseID("forged-lease")
        do {
            _ = try await bridge.close(
                token,
                release: mismatched,
                evidenceReceiptIDs: [],
                progressReceiptID: nil,
                occurrenceReceiptID: ReceiptID("forged-occurrence"),
                occurrenceCommandID: RunCommandID("forged-occurrence")
            )
            XCTFail("A mismatched native handle must not close owned execution")
        } catch {
            XCTAssertEqual(
                error as? JournaledOwnedProcessOccurrenceBridgeError,
                .releaseMismatch
            )
        }
        let retainedOpenCount = await bridge.openExecutionCount()
        XCTAssertEqual(retainedOpenCount, 1)

        var crossWiredRelease = release
        crossWiredRelease.journalTransaction = start.launch.journalTransaction
        do {
            _ = try await bridge.close(
                token,
                release: crossWiredRelease,
                evidenceReceiptIDs: [],
                progressReceiptID: nil,
                occurrenceReceiptID: ReceiptID("cross-wired-occurrence"),
                occurrenceCommandID: RunCommandID("cross-wired-occurrence")
            )
            XCTFail("An unrelated journal frame must not authorize the close")
        } catch {
            XCTAssertEqual(
                error as? JournaledOwnedProcessOccurrenceBridgeError,
                .unjournaledRelease
            )
        }
        let crossWiredOpenCount = await bridge.openExecutionCount()
        XCTAssertEqual(crossWiredOpenCount, 1)

        let occurrence = try await bridge.close(
            token,
            release: release,
            evidenceReceiptIDs: [],
            progressReceiptID: nil,
            occurrenceReceiptID: ReceiptID("occurrence-owned-occurrence"),
            occurrenceCommandID: RunCommandID("occurrence-owned-occurrence")
        )
        XCTAssertEqual(occurrence.occurrence.outcome, .succeeded)
        XCTAssertEqual(occurrence.occurrence.intervalDisposition, .acceptedScheduled)
        XCTAssertEqual(
            occurrence.occurrence.clock.monotonicEndNanoseconds,
            release.termination.exit.observedAtMonotonicNanoseconds
        )
        XCTAssertGreaterThan(occurrence.occurrence.clock.elapsedNanoseconds ?? 0, 0)
        let finalOpenCount = await bridge.openExecutionCount()
        XCTAssertEqual(finalOpenCount, 0)
        let releasedLease = await fixture.journal.runtimeLease(
            resourceID: OwnedResourceID("resource-owned-occurrence")
        )
        XCTAssertNil(releasedLease)
        let projectedBinding = await fixture.journal.runtimeBindingReceipt(
            receiptID: ReceiptID("binding-owned-occurrence")
        )
        XCTAssertEqual(projectedBinding, start.launch.binding)
    }

    func testNaturalExitJournalsReleaseAndClosesOwnedOccurrence() async throws {
        let fixture = try await makeEmptyFixture("natural-occurrence")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let recorder = JournaledOccurrenceRecorder(
            journal: fixture.journal,
            actorIdentity: actor
        )
        let bridge = JournaledOwnedProcessOccurrenceBridge(
            journal: fixture.journal,
            supervisor: fixture.supervisor,
            recorder: recorder
        )
        let start = try await admitAndLaunch(
            runtime,
            request: leaseRequest("natural-occurrence"),
            specification: specification("/bin/sleep", arguments: ["0.05"]),
            id: "natural-occurrence"
        )
        let token = try await bridge.begin(
            start: start,
            invocation: .scheduled(scheduleID: ScheduleID("natural"), ordinal: 0)
        )
        let projectedLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        )
        let lease = try XCTUnwrap(projectedLease)
        let release = try await runtime.joinAndRelease(
            lease: lease,
            releaseReceiptID: ReceiptID("release-natural-occurrence"),
            commandID: RunCommandID("release-natural-occurrence"),
            timeoutNanoseconds: 5_000_000_000
        )

        XCTAssertEqual(release.exit.exitCode, 0)
        XCTAssertNil(release.exit.terminationSignal)
        XCTAssertEqual(release.release.managedProcessExit, release.exit)
        XCTAssertNil(release.release.managedProcessTermination)
        let occurrence = try await bridge.closeNaturally(
            token,
            release: release,
            evidenceReceiptIDs: [],
            progressReceiptID: nil,
            occurrenceReceiptID: ReceiptID("occurrence-natural-occurrence"),
            occurrenceCommandID: RunCommandID("occurrence-natural-occurrence")
        )
        XCTAssertEqual(occurrence.occurrence.outcome, .succeeded)
        XCTAssertEqual(occurrence.occurrence.intervalDisposition, .acceptedScheduled)
        XCTAssertEqual(
            occurrence.occurrence.clock.monotonicEndNanoseconds,
            release.exit.observedAtMonotonicNanoseconds
        )
        let releasedLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        )
        let supervisorProjection = await fixture.supervisor.projection()
        let openExecutionCount = await bridge.openExecutionCount()
        XCTAssertNil(releasedLease)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertEqual(openExecutionCount, 0)
    }

    func testStaleJournalDuringAdmissionDoesNotMutateSupervisorOrLaunch() async throws {
        let fixture = try await makeEmptyFixture("stale-admission")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let concurrent = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        _ = try await concurrent.transactAtCurrentSequence(
            .testOnlyRecordRuntimeAdmission(concurrentRejectedAdmission("admission")),
            commandID: RunCommandID("concurrent-admission"),
            issuedAt: Date(),
            actor: actor
        )

        await XCTAssertThrowsRuntimeError(.journalWriteFailed) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("stale-admission"),
                specification: self.specification("/usr/bin/true"),
                id: "stale-admission"
            )
        }
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredLease = await recovered.runtimeLease(
            resourceID: OwnedResourceID("resource-stale-admission")
        )
        XCTAssertNil(recoveredLease)
    }

    func testNativeSpawnFailureJournalsReleaseAndFreesAdmission() async throws {
        let invalidExecutable = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForge-invalid-executable-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: invalidExecutable) }
        try Data("not a native executable\n".utf8).write(to: invalidExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: invalidExecutable.path
        )
        let fixture = try await makeEmptyFixture(
            "spawn-failure",
            executablePath: invalidExecutable.path
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )

        await XCTAssertThrowsRuntimeError(.nativeLaunchFailed(.launchFailed(errno: ENOEXEC))) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: self.leaseRequest("spawn-failure"),
                specification: self.specification(invalidExecutable.path),
                id: "spawn-failure"
            )
        }
        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredProjection = await recovered.currentProjection()
        let recoveredReport = await recovered.recoveryReport
        let supervisorProjection = await fixture.supervisor.projection()
        XCTAssertEqual(recoveredProjection.runtimeLiveResourceCount, 0)
        XCTAssertEqual(recoveredReport.recoveredTransactions, 8)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        XCTAssertTrue(runtimeProjection.inDoubtResourceIDs.isEmpty)
    }

    func testRejectedAdmissionIsDurableAndNeverLaunches() async throws {
        let fixture = try await makeEmptyFixture("rejected-admission")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        var request = leaseRequest("rejected-admission")
        request.reservation.cpuWeight = 100

        await XCTAssertThrowsRuntimeError(.admissionRejected(.budgetExceeded)) {
            _ = try await self.admitAndLaunch(
                runtime,
                request: request,
                specification: self.specification("/usr/bin/true"),
                id: "rejected-admission"
            )
        }
        let journalProjection = await fixture.journal.currentProjection()
        let supervisorProjection = await fixture.supervisor.projection()
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(journalProjection.sequence, 7)
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testLaunchAndTerminatePublishBindingAndReleaseBeforeSupervisorCommit() async throws {
        let fixture = try await makeFixture("happy")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )

        let launch = try await runtime.launch(
            lease: fixture.lease,
            specification: specification("/bin/sleep", arguments: ["30"]),
            bindingReceiptID: ReceiptID("binding-happy"),
            commandID: RunCommandID("bind-happy")
        )
        let journalBound = await fixture.journal.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        let supervisorBound = (await fixture.supervisor.projection()).liveLeases.first
        XCTAssertEqual(journalBound?.request.externalIdentity, launch.handle.externalIdentity)
        XCTAssertEqual(supervisorBound?.request.externalIdentity, launch.handle.externalIdentity)

        let release = try await runtime.terminate(
            lease: journalBound!,
            releaseReceiptID: ReceiptID("release-happy"),
            commandID: RunCommandID("release-happy"),
            graceNanoseconds: 100_000_000
        )
        guard case .released(let nativeRelease) = release.release.outcome else {
            return XCTFail("Expected a journaled native release")
        }
        XCTAssertEqual(nativeRelease.resourceID, fixture.lease.request.resourceID)
        let releasedJournalLease = await fixture.journal.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        XCTAssertNil(releasedJournalLease)
        let releasedSupervisorProjection = await fixture.supervisor.projection()
        XCTAssertTrue(releasedSupervisorProjection.liveLeases.isEmpty)
        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        XCTAssertTrue(runtimeProjection.inDoubtResourceIDs.isEmpty)

        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredProjection = await recovered.currentProjection()
        XCTAssertEqual(recoveredProjection.runtimeLiveResourceCount, 0)
    }

    func testApplicationTerminationCleanupTerminatesExactLiveProcessAndJournalsRelease()
        async throws
    {
        let fixture = try await makeEmptyFixture("app-termination-cleanup")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let start = try await admitAndLaunch(
            runtime,
            request: leaseRequest("app-termination-cleanup"),
            specification: specification("/bin/sleep", arguments: ["30"]),
            id: "app-termination-cleanup"
        )
        let cleanupIsExecutable = await runtime
            .applicationTerminationCleanupIsExecutable()
        XCTAssertTrue(cleanupIsExecutable)
        _ = await fixture.supervisor.beginDrain(.stop)
        let plan = await fixture.supervisor.cleanupPlan()
        XCTAssertEqual(plan, [
            .requestGracefulTermination(
                resourceID: start.launch.handle.resourceID,
                leaseID: start.launch.handle.leaseID
            )
        ])

        let nonce = UUID().uuidString.lowercased()
        let cleanup = try await runtime.executeApplicationTerminationCleanup(
            expectedPlan: plan,
            requestNonce: nonce,
            origin: .nativeQuit
        )
        XCTAssertEqual(cleanup.runID, runID)
        XCTAssertEqual(cleanup.requestNonce, nonce)
        XCTAssertEqual(cleanup.origin, .nativeQuit)
        XCTAssertEqual(cleanup.plannedActions, plan)
        XCTAssertEqual(cleanup.releaseReceiptIDs.count, 1)
        XCTAssertTrue(cleanup.remainingActions.isEmpty)
        let state = await fixture.journal.state
        let release = try XCTUnwrap(
            state.runtimeReleaseReceipts[cleanup.releaseReceiptIDs[0]]
        )
        XCTAssertNotNil(release.managedProcessTermination)
        XCTAssertNil(release.managedProcessExit)
        let retainedJournalLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        )
        XCTAssertNil(retainedJournalLease)
        let remainingPlan = await fixture.supervisor.cleanupPlan()
        XCTAssertTrue(remainingPlan.isEmpty)
        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
    }

    func testApplicationTerminationCleanupRecoversExactProcessAfterRuntimeRestart()
        async throws
    {
        let fixture = try await makeEmptyFixture(
            "app-termination-cleanup-recovery"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalAdapter = ProcessGroupRuntimeAdapter()
        let originalRuntime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: originalAdapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let start = try await admitAndLaunch(
            originalRuntime,
            request: leaseRequest("app-termination-cleanup-recovery"),
            specification: specification("/bin/sleep", arguments: ["30"]),
            id: "app-termination-cleanup-recovery"
        )

        let recoveredSupervisor = makeSupervisor()
        let snapshot = await fixture.journal.runtimeSupervisorRecoverySnapshot()
        guard case .restored = await recoveredSupervisor.restore(from: snapshot) else {
            return XCTFail("Expected exact supervisor recovery")
        }
        let recoveredRuntime = JournaledProcessRuntime(
            supervisor: recoveredSupervisor,
            journal: fixture.journal,
            actorIdentity: actor
        )
        let cleanupIsExecutable = await recoveredRuntime
            .applicationTerminationCleanupIsExecutable()
        XCTAssertTrue(cleanupIsExecutable)
        _ = await recoveredSupervisor.beginDrain(.stop)
        let plan = await recoveredSupervisor.cleanupPlan()
        let cleanup = try await recoveredRuntime
            .executeApplicationTerminationCleanup(
                expectedPlan: plan,
                requestNonce: UUID().uuidString.lowercased(),
                origin: .applicationCrashRecovery
            )
        XCTAssertEqual(cleanup.origin, .applicationCrashRecovery)
        XCTAssertEqual(cleanup.releaseReceiptIDs.count, 1)
        XCTAssertTrue(cleanup.remainingActions.isEmpty)
        _ = try await originalAdapter.join(
            resourceID: start.launch.handle.resourceID,
            leaseID: start.launch.handle.leaseID,
            timeoutNanoseconds: 1_000_000_000
        )
        let remainingPlan = await recoveredSupervisor.cleanupPlan()
        XCTAssertTrue(remainingPlan.isEmpty)
        let recoveredProjection = await recoveredRuntime.projection()
        XCTAssertTrue(recoveredProjection.adapter.liveHandles.isEmpty)
        let retainedJournalLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        )
        XCTAssertNil(retainedJournalLease)
    }

    func testNativeProcessAdmissionRejectsJoinOnlyUnrecoverableReleasePolicy()
        async throws
    {
        let fixture = try await makeEmptyFixture(
            "reject-join-only-process"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        var request = leaseRequest("reject-join-only-process")
        request.releasePolicy = .join

        do {
            _ = try await admitAndLaunch(
                runtime,
                request: request,
                specification: specification("/bin/sleep", arguments: ["30"]),
                id: "reject-join-only-process"
            )
            XCTFail("a native process must not launch with join-only cleanup")
        } catch let error as JournaledProcessRuntimeError {
            XCTAssertEqual(
                error,
                .admissionRejected(.invalidReleasePolicy)
            )
        }
        let state = await fixture.journal.state
        XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
        XCTAssertTrue(state.runtimeReleaseReceipts.isEmpty)
        XCTAssertEqual(state.runtimeAdmissionReceipts.count, 1)
        guard let admission = state.runtimeAdmissionReceipts.values.first else {
            return XCTFail("join-only process rejection must remain journaled")
        }
        XCTAssertEqual(
            admission.outcome,
            .rejected(.invalidReleasePolicy)
        )
        let adapterProjection = await adapter.projection()
        let cleanupPlan = await fixture.supervisor.cleanupPlan()
        XCTAssertTrue(adapterProjection.liveHandles.isEmpty)
        XCTAssertTrue(cleanupPlan.isEmpty)
    }

    func testOwnershipDivergenceRejectsBeforeNativeLaunch() async throws {
        let fixture = try await makeFixture("mismatch")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        var substituted = fixture.lease
        substituted.request.leaseID = ResourceLeaseID("substituted")

        await XCTAssertThrowsRuntimeError(.ownershipDiverged) {
            _ = try await runtime.launch(
                lease: substituted,
                specification: self.specification("/bin/sleep", arguments: ["30"]),
                bindingReceiptID: ReceiptID("binding-mismatch"),
                commandID: RunCommandID("bind-mismatch")
            )
        }
        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        let supervisorProjection = await fixture.supervisor.projection()
        XCTAssertEqual(supervisorProjection.liveLeases, [fixture.lease])
    }

    func testStaleJournalDuringBindingCompensatesNativeLaunchAndRetainsOwnership() async throws {
        let fixture = try await makeFixture("stale-binding")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let concurrent = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        _ = try await concurrent.transactAtCurrentSequence(
            .testOnlyRecordRuntimeAdmission(concurrentRejectedAdmission("binding")),
            commandID: RunCommandID("concurrent-binding"),
            issuedAt: Date(),
            actor: actor
        )

        await XCTAssertThrowsRuntimeError(.journalWriteFailed) {
            _ = try await runtime.launch(
                lease: fixture.lease,
                specification: self.specification("/bin/sleep", arguments: ["30"]),
                bindingReceiptID: ReceiptID("binding-stale"),
                commandID: RunCommandID("bind-stale")
            )
        }

        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        XCTAssertEqual(runtimeProjection.inDoubtResourceIDs, [fixture.lease.request.resourceID])
        let supervisorProjection = await fixture.supervisor.projection()
        XCTAssertEqual(supervisorProjection.liveLeases.count, 1)
        XCTAssertEqual(supervisorProjection.failedReleases, [fixture.lease.request.resourceID])
        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredLease = await recovered.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        XCTAssertNotNil(recoveredLease)
        XCTAssertNil(recoveredLease?.request.externalIdentity)
    }

    func testStaleJournalDuringReleaseRetainsLogicalOwnershipAfterNativeDrain() async throws {
        let fixture = try await makeFixture("stale-release")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let adapter = ProcessGroupRuntimeAdapter()
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: adapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        _ = try await runtime.launch(
            lease: fixture.lease,
            specification: specification("/bin/sleep", arguments: ["30"]),
            bindingReceiptID: ReceiptID("binding-release-stale"),
            commandID: RunCommandID("bind-release-stale")
        )
        let boundLease = await fixture.journal.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        let concurrent = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        _ = try await concurrent.transactAtCurrentSequence(
            .testOnlyRecordRuntimeAdmission(concurrentRejectedAdmission("release")),
            commandID: RunCommandID("concurrent-release"),
            issuedAt: Date(),
            actor: actor
        )

        await XCTAssertThrowsRuntimeError(.journalWriteFailed) {
            _ = try await runtime.terminate(
                lease: boundLease!,
                releaseReceiptID: ReceiptID("release-stale"),
                commandID: RunCommandID("release-stale"),
                graceNanoseconds: 100_000_000
            )
        }

        let runtimeProjection = await runtime.projection()
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        XCTAssertEqual(runtimeProjection.inDoubtResourceIDs, [fixture.lease.request.resourceID])
        let supervisorProjection = await fixture.supervisor.projection()
        XCTAssertEqual(supervisorProjection.liveLeases.count, 1)
        XCTAssertEqual(supervisorProjection.failedReleases, [fixture.lease.request.resourceID])
        let recovered = try RunJournal(rootDirectory: fixture.journalRoot, runID: runID)
        let recoveredLease = await recovered.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        XCTAssertNotNil(recoveredLease)
    }

    func testReconcileKeepsUnboundAdmissionInDoubtWithoutScanning() async throws {
        let fixture = try await makeFixture("reconcile-unbound")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let recoveredSupervisor = makeSupervisor()
        let recoverySnapshot = await fixture.journal.runtimeSupervisorRecoverySnapshot()
        guard case .restored = await recoveredSupervisor.restore(from: recoverySnapshot) else {
            return XCTFail("Expected journal supervisor hydration")
        }
        let runtime = JournaledProcessRuntime(
            supervisor: recoveredSupervisor,
            journal: fixture.journal,
            actorIdentity: actor
        )

        let outcome = try await runtime.reconcile(
            resourceID: fixture.lease.request.resourceID,
            absentReleaseReceiptID: ReceiptID("reconcile-unbound-release"),
            absentReleaseCommandID: RunCommandID("reconcile-unbound-release")
        )
        guard case .unboundAdmission(let retained) = outcome else {
            return XCTFail("Expected an in-doubt unbound admission")
        }
        XCTAssertEqual(retained, fixture.lease)
        let runtimeProjection = await runtime.projection()
        XCTAssertEqual(runtimeProjection.inDoubtResourceIDs, [fixture.lease.request.resourceID])
        XCTAssertTrue(runtimeProjection.adapter.liveHandles.isEmpty)
        let supervisorProjection = await recoveredSupervisor.projection()
        XCTAssertEqual(supervisorProjection.liveLeases, [fixture.lease])
        XCTAssertEqual(supervisorProjection.failedReleases, [fixture.lease.request.resourceID])
        let journalLease = await fixture.journal.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        XCTAssertNotNil(journalLease)
    }

    func testApplicationTerminationCleanupPreflightRetainsUnboundAdmission()
        async throws
    {
        let fixture = try await makeFixture("app-termination-cleanup-unbound")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runtime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            actorIdentity: actor
        )

        let cleanupIsExecutable = await runtime
            .applicationTerminationCleanupIsExecutable()
        XCTAssertFalse(cleanupIsExecutable)
        let plan = await fixture.supervisor.cleanupPlan()
        XCTAssertEqual(plan, [
            .requestGracefulTermination(
                resourceID: fixture.lease.request.resourceID,
                leaseID: fixture.lease.request.leaseID
            )
        ])
        let supervisorProjection = await fixture.supervisor.projection()
        XCTAssertEqual(supervisorProjection.liveLeases, [fixture.lease])
        let journalLease = await fixture.journal.runtimeLease(
            resourceID: fixture.lease.request.resourceID
        )
        XCTAssertEqual(journalLease, fixture.lease)
    }

    func testReconcileReattachesExactBoundProcessAndCanTerminateIt() async throws {
        let fixture = try await makeEmptyFixture("reconcile-bound")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalAdapter = ProcessGroupRuntimeAdapter()
        let originalRuntime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: originalAdapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let start = try await admitAndLaunch(
            originalRuntime,
            request: leaseRequest("reconcile-bound"),
            specification: specification("/bin/sleep", arguments: ["30"]),
            id: "reconcile-bound"
        )
        guard let boundLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        ) else {
            return XCTFail("Expected bound journal lease")
        }

        let recoveredSupervisor = makeSupervisor()
        let recoverySnapshot = await fixture.journal.runtimeSupervisorRecoverySnapshot()
        guard case .restored = await recoveredSupervisor.restore(from: recoverySnapshot) else {
            return XCTFail("Expected journal supervisor hydration")
        }
        let recoveredAdapter = ProcessGroupRuntimeAdapter()
        let recoveredRuntime = JournaledProcessRuntime(
            supervisor: recoveredSupervisor,
            journal: fixture.journal,
            adapter: recoveredAdapter,
            actorIdentity: actor
        )
        let outcome = try await recoveredRuntime.reconcile(
            resourceID: boundLease.request.resourceID,
            absentReleaseReceiptID: ReceiptID("reconcile-bound-absent"),
            absentReleaseCommandID: RunCommandID("reconcile-bound-absent")
        )
        guard case .recovered(let recoveredHandle) = outcome else {
            return XCTFail("Expected exact process recovery")
        }
        XCTAssertEqual(recoveredHandle, start.launch.handle)

        _ = try await recoveredRuntime.terminate(
            lease: boundLease,
            releaseReceiptID: ReceiptID("reconcile-bound-release"),
            commandID: RunCommandID("reconcile-bound-release"),
            graceNanoseconds: 100_000_000
        )
        _ = try await originalAdapter.join(
            resourceID: boundLease.request.resourceID,
            leaseID: boundLease.request.leaseID,
            timeoutNanoseconds: 1_000_000_000
        )
        let releasedJournalLease = await fixture.journal.runtimeLease(
            resourceID: boundLease.request.resourceID
        )
        XCTAssertNil(releasedJournalLease)
    }

    func testReconcileJournalsReleaseWhenExactBoundProcessIsAbsent() async throws {
        let fixture = try await makeEmptyFixture("reconcile-absent")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let originalAdapter = ProcessGroupRuntimeAdapter()
        let originalRuntime = JournaledProcessRuntime(
            supervisor: fixture.supervisor,
            journal: fixture.journal,
            adapter: originalAdapter,
            actorIdentity: actor,
            executionProof: fixture.proof
        )
        let start = try await admitAndLaunch(
            originalRuntime,
            request: leaseRequest("reconcile-absent"),
            specification: specification("/bin/sleep", arguments: ["30"]),
            id: "reconcile-absent"
        )
        guard let boundLease = await fixture.journal.runtimeLease(
            resourceID: start.launch.handle.resourceID
        ) else {
            return XCTFail("Expected bound journal lease")
        }
        _ = try await originalAdapter.terminate(
            resourceID: boundLease.request.resourceID,
            leaseID: boundLease.request.leaseID,
            graceNanoseconds: 100_000_000
        )

        let recoveredSupervisor = makeSupervisor()
        let recoverySnapshot = await fixture.journal.runtimeSupervisorRecoverySnapshot()
        guard case .restored = await recoveredSupervisor.restore(from: recoverySnapshot) else {
            return XCTFail("Expected journal supervisor hydration")
        }
        let recoveredRuntime = JournaledProcessRuntime(
            supervisor: recoveredSupervisor,
            journal: fixture.journal,
            actorIdentity: actor
        )
        let outcome = try await recoveredRuntime.reconcile(
            resourceID: boundLease.request.resourceID,
            absentReleaseReceiptID: ReceiptID("reconcile-absent-release"),
            absentReleaseCommandID: RunCommandID("reconcile-absent-release")
        )
        guard case .absentReleased(let receipt) = outcome else {
            return XCTFail("Expected exact absence release")
        }
        guard case .released = receipt.release.outcome else {
            return XCTFail("Expected journaled release")
        }
        let supervisorProjection = await recoveredSupervisor.projection()
        XCTAssertTrue(supervisorProjection.liveLeases.isEmpty)
        let releasedJournalLease = await fixture.journal.runtimeLease(
            resourceID: boundLease.request.resourceID
        )
        XCTAssertNil(releasedJournalLease)
    }

    private struct Fixture {
        var root: URL
        var journalRoot: URL
        var journal: RunJournal
        var supervisor: RuntimeSupervisor
        var lease: RuntimeResourceLease
        var proof: JournaledKernelExecutionProof
    }

    private struct EmptyFixture {
        var root: URL
        var workspaceRoot: URL
        var journalRoot: URL
        var journal: RunJournal
        var supervisor: RuntimeSupervisor
        var proof: JournaledKernelExecutionProof
    }

    private func makeFixture(_ name: String) async throws -> Fixture {
        let empty = try await makeEmptyFixture(name)
        let root = empty.root
        let journal = empty.journal
        let supervisor = empty.supervisor
        let request = leaseRequest(name)
        let admission = await supervisor.acquireReceipt(
            request,
            receiptID: ReceiptID("admission-\(name)"),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordRuntimeAdmission(admission),
            commandID: RunCommandID("admit-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        guard case .accepted(let lease, duplicate: false) = admission.outcome else {
            throw NSError(domain: "JournaledProcessRuntimeTests", code: 1)
        }
        return Fixture(
            root: root,
            journalRoot: empty.journalRoot,
            journal: journal,
            supervisor: supervisor,
            lease: lease,
            proof: empty.proof
        )
    }

    private func makeEmptyFixture(
        _ name: String,
        executablePath: String? = nil,
        includeExecutionProfile: Bool = true,
        environmentPolicy: KernelEnvironmentPolicy = .minimalKernelAllowlist,
        sandbox: KernelExecutionSandbox = .readOnly,
        provider: KernelExecutionProvider = .codex
    ) async throws -> EmptyFixture {
        let executablePath = executablePath ?? kernelProcessFixturePath
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-JournaledProcess-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspaceRoot = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let journalRoot = root.appendingPathComponent("journal", isDirectory: true)
        let journal = try RunJournal(
            rootDirectory: journalRoot,
            runID: runID
        )
        let supervisor = makeSupervisor()
        _ = try await journal.transactAtCurrentSequence(
            .createRun(contract(
                executablePath: executablePath,
                includeExecutionProfile: includeExecutionProfile,
                environmentPolicy: environmentPolicy,
                sandbox: sandbox,
                provider: provider
            )),
            commandID: RunCommandID("create-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        let strategy = causalStrategy()
        _ = try await journal.transactAtCurrentSequence(
            .proposePlan(KernelPlanProposal(
                contractDigest: ContentDigest("journaled-process-objective"),
                nodes: [KernelNodeContract(
                    id: KernelNodeID("process-node"),
                    requirementIDs: [RequirementID("process-execution")],
                    objective: "Execute one exact journal-authorized process.",
                    dependencies: [],
                    mutationScope: .readOnly,
                    capabilityIDs: [],
                    strategyFingerprint: strategy.fingerprint
                )]
            )),
            commandID: RunCommandID("plan-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .authorizeNode(KernelNodeID("process-node")),
            commandID: RunCommandID("authorize-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(
                epochID: "process-epoch-\(name)",
                budget: convergenceBudget()
            ),
            commandID: RunCommandID("initialize-convergence-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 4),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(AttemptAdmissionRequest(
                attemptID: AttemptID("attempt-\(name)"),
                strategy: strategy,
                predictedObservationIDs: ["process-exited"],
                falsificationPredicateIDs: ["process-identity-mismatch"],
                rollbackPoint: ContentDigest("no-process"),
                mutationCost: 0,
                verificationCost: 1,
                externalEffects: 1
            )),
            commandID: RunCommandID("admit-causal-attempt-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 5),
            actor: actor
        )
        let activation = try await journal.transactAtCurrentSequence(
            .startAttempt(
                attemptID: AttemptID("attempt-\(name)"),
                nodeID: KernelNodeID("process-node"),
                requirementIDs: [RequirementID("process-execution")],
                strategyFingerprint: strategy.fingerprint
            ),
            commandID: RunCommandID("start-attempt-\(name)"),
            issuedAt: Date(timeIntervalSince1970: 6),
            actor: actor
        )
        let proof = JournaledKernelExecutionProof.testOnly(
            runID: runID,
            attemptID: AttemptID("attempt-\(name)"),
            nodeID: KernelNodeID("process-node"),
            strategyFingerprint: strategy.fingerprint,
            workerExecutionProfile: workerExecutionProfile(
                executablePath: executablePath,
                environmentPolicy: environmentPolicy,
                sandbox: sandbox,
                provider: provider
            ),
            workspaceRoot: workspaceRoot,
            activationActor: actor,
            activationTransaction: activation
        )
        return EmptyFixture(
            root: root,
            workspaceRoot: workspaceRoot,
            journalRoot: journalRoot,
            journal: journal,
            supervisor: supervisor,
            proof: proof
        )
    }

    private func causalStrategy() -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [RequirementID("process-execution")],
            hypothesisClass: "managed-process",
            actionClass: "launch-exact-executable",
            workspaceTopology: "read-only-runtime",
            capabilityRoute: ["journaled-process-runtime"],
            evidenceSources: ["exact-process-identity", "exit-receipt"],
            measurementBoundary: "owned-process-group",
            verificationOracles: ["pid-start-time-process-group"],
            mutationSurfaceDigest: ContentDigest("no-workspace-mutation"),
            baselineRevision: ContentDigest("no-process"),
            expectedObservationIDs: ["process-exited"],
            falsificationPredicateIDs: ["process-identity-mismatch"],
            inheritedLessonDigests: []
        )
    }

    private func convergenceBudget() -> ConvergenceBudget {
        ConvergenceBudget(
            maximumAttempts: 1,
            maximumEquivalentFailures: 1,
            maximumStrategies: 1,
            maximumPlanExpansions: 1,
            maximumMutationCost: 0,
            maximumVerificationCost: 1,
            maximumDamageEvents: 1,
            maximumExternalEffects: 1
        )
    }

    private func concurrentRejectedAdmission(_ id: String) -> RuntimeAdmissionReceipt {
        let request = RuntimeLeaseRequest(
            leaseID: ResourceLeaseID("concurrent-lease-\(id)"),
            resourceID: OwnedResourceID("concurrent-resource-\(id)"),
            runID: runID,
            occurrenceID: nil,
            attemptID: nil,
            kind: .capability,
            purpose: .cleanup,
            ownership: .owned,
            releasePolicy: .join,
            externalIdentity: nil,
            reservation: .zero,
            requestedAtMonotonicNanoseconds: 1,
            renewalDeadlineMonotonicNanoseconds: nil,
            progressReceiptID: nil
        )
        return RuntimeAdmissionReceipt(
            id: ReceiptID("concurrent-rejection-\(id)"),
            runID: runID,
            request: request,
            outcome: .rejected(.draining),
            observedAt: Date(),
            observedAtMonotonicNanoseconds: 2
        )
    }

    private func makeSupervisor() -> RuntimeSupervisor {
        RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 10,
                memoryBytes: 1_024,
                diskIOWeight: 10,
                gpuWeight: 0,
                networkWeight: 10,
                guiSessionCount: 0,
                processCount: 4
            ))
        )
    }

    private func admitAndLaunch(
        _ runtime: JournaledProcessRuntime,
        request: RuntimeLeaseRequest,
        specification: ManagedProcessSpecification,
        id: String
    ) async throws -> JournaledProcessStartReceipt {
        try await runtime.admitAndLaunch(
            request: request,
            specification: specification,
            admissionReceiptID: ReceiptID("admission-\(id)"),
            admissionCommandID: RunCommandID("admit-\(id)"),
            bindingReceiptID: ReceiptID("binding-\(id)"),
            bindingCommandID: RunCommandID("bind-\(id)"),
            launchFailureReleaseReceiptID: ReceiptID("launch-failure-release-\(id)"),
            launchFailureReleaseCommandID: RunCommandID("launch-failure-release-\(id)")
        )
    }

    private func leaseRequest(_ id: String) -> RuntimeLeaseRequest {
        RuntimeLeaseRequest(
            leaseID: ResourceLeaseID("lease-\(id)"),
            resourceID: OwnedResourceID("resource-\(id)"),
            runID: runID,
            occurrenceID: OccurrenceID("occurrence-\(id)"),
            attemptID: AttemptID("attempt-\(id)"),
            kind: .processTree,
            purpose: .productive,
            ownership: .owned,
            releasePolicy: .gracefulThenTerminate,
            externalIdentity: nil,
            reservation: ResourceVector(
                cpuWeight: 1,
                memoryBytes: 1,
                diskIOWeight: 0,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 1
            ),
            requestedAtMonotonicNanoseconds: 1,
            renewalDeadlineMonotonicNanoseconds: nil,
            progressReceiptID: nil
        )
    }

    private func contract(
        executablePath: String? = nil,
        includeExecutionProfile: Bool = true,
        environmentPolicy: KernelEnvironmentPolicy = .minimalKernelAllowlist,
        sandbox: KernelExecutionSandbox = .readOnly,
        provider: KernelExecutionProvider = .codex
    ) -> TaskContract {
        let executablePath = executablePath ?? kernelProcessFixturePath
        let authorityCeiling: KernelAuthorityCeiling
        if sandbox == .fullAccess {
            authorityCeiling = KernelAuthorityCeiling(
                readableScopes: [],
                writableScopes: [],
                capabilityIDs: [KernelExecutionProfile.fullAccessCapabilityID],
                permitsExternalPublication: false
            )
        } else if environmentPolicy == .declaredAllowlist {
            authorityCeiling = KernelAuthorityCeiling(
                readableScopes: [],
                writableScopes: [],
                capabilityIDs: [KernelExecutionProfile.declaredEnvironmentCapabilityID],
                permitsExternalPublication: false
            )
        } else {
            authorityCeiling = .readOnly
        }
        return TaskContract(
            id: TaskContractID("journaled-process-contract"),
            schemaVersion: 1,
            verbatimObjective: "Execute declared work and retain exact ownership.",
            objectiveDigest: ContentDigest("journaled-process-objective"),
            requirements: [RequirementContract(
                id: RequirementID("process-execution"),
                statement: "Execute one exact journal-authorized process.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("exact-process-exit")]
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            executionProfile: includeExecutionProfile ? KernelExecutionProfile(
                schemaVersion: 1,
                worker: workerExecutionProfile(
                    executablePath: executablePath,
                    environmentPolicy: environmentPolicy,
                    sandbox: sandbox,
                    provider: provider
                ),
                independentReviewer: KernelAgentExecutionProfile(
                    provider: .codex,
                    providerReference: "review-harness",
                    executableContentDigest: executableDigest(executablePath),
                    modelID: "review-model",
                    reasoningEffort: "high",
                    sandbox: .readOnly,
                    networkPolicy: .disabled,
                    pluginPolicy: .disabled,
                    environmentPolicy: .minimalKernelAllowlist
                ),
                requiresDistinctActorLineage: true
            ) : nil,
            authorityCeiling: authorityCeiling,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: DurationAcceptancePolicy(
                    requiredSeconds: 1,
                    eligibleClass: .acceptedScheduledExecution
                ),
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func workerExecutionProfile(
        executablePath: String? = nil,
        environmentPolicy: KernelEnvironmentPolicy = .minimalKernelAllowlist,
        sandbox: KernelExecutionSandbox = .readOnly,
        provider: KernelExecutionProvider = .codex
    ) -> KernelAgentExecutionProfile {
        let executablePath = executablePath ?? kernelProcessFixturePath
        return KernelAgentExecutionProfile(
            provider: provider,
            providerReference: provider == .local
                ? "local-worker-harness"
                : "worker-harness",
            executableContentDigest: executableDigest(executablePath),
            modelID: "worker-model",
            reasoningEffort: "high",
            sandbox: sandbox,
            networkPolicy: .disabled,
            pluginPolicy: .disabled,
            environmentPolicy: environmentPolicy,
            providerProtocol: .loopForgeProviderHarnessV2,
            providerHarnessMode: .productive,
            credentialMode: provider == .local
                ? .none
                : .opaqueProviderSecret,
            credentialReference: provider == .local
                ? nil
                : KernelProviderCredentialReference(
                    source: .macOSKeychainGenericPassword,
                    service: "test.loopforge.provider",
                    account: "journaled-runtime-provider"
                )
        )
    }

    private func executableDigest(_ path: String) -> ContentDigest {
        ProcessGroupRuntimeAdapter.executableContentDigest(atPath: path)
            ?? ContentDigest("")
    }

    private func specification(
        _ path: String,
        arguments: [String] = []
    ) -> ManagedProcessSpecification {
        if path == "/usr/bin/true" {
            return ManagedProcessSpecification(
                executablePath: kernelProcessFixturePath,
                arguments: ["--exit", "0"],
                environment: [:]
            )
        }
        if path == "/bin/sleep", let duration = arguments.first {
            return ManagedProcessSpecification(
                executablePath: kernelProcessFixturePath,
                arguments: ["--sleep-seconds", duration],
                environment: [:]
            )
        }
        return ManagedProcessSpecification(
            executablePath: path,
            arguments: arguments,
            environment: [:]
        )
    }

    private var kernelProcessFixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/KernelProcessFixture")
            .standardizedFileURL.path
    }

    private func XCTAssertThrowsRuntimeError<T>(
        _ expected: JournaledProcessRuntimeError,
        operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as JournaledProcessRuntimeError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
