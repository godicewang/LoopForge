import Foundation
import XCTest
@testable import LoopForge

final class KernelNativeSandboxTests: XCTestCase {
    func testProviderSecretCapabilityCrossesSpawnAndSandboxGateOnlyOnFixedFD() async throws {
        let root = try makeRoot("provider-secret")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try makeDirectories([workspace, journal])
        let io = ManagedProcessIOFiles(
            directoryPath: journal.path,
            standardInputFileName: "provider-prompt.json",
            standardOutputFileName: "provider-stdout.jsonl",
            standardErrorFileName: "provider-stderr.txt"
        )
        let proof = providerExecutionProof(workspace: workspace)
        let prompt = try KernelProviderPromptArtifactIssuer().issue(
            prompt: Data("exact provider prompt".utf8),
            fileName: "provider-prompt.json",
            journalRunDirectory: journal,
            executionProof: proof
        )
        let invocation = try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: prompt,
            requestNonce: contentDigest("provider-request-nonce")
        )
        let secret = try KernelProviderSecretIssuer().issue(
            secret: Data("ephemeral-provider-secret".utf8),
            for: invocation,
            executionProof: proof,
            lifetimeNanoseconds: 5_000_000_000
        )
        let nativeSandbox = try KernelNativeSandboxAuthorizer().authorize(
            executionProfile: proof.workerExecutionProfile,
            workspaceRoot: workspace,
            journalRunDirectory: journal,
            ioFiles: io
        )
        let specification = ManagedProcessSpecification(
            executablePath: kernelProcessFixturePath,
            arguments: invocation.receipt.arguments,
            environment: [:],
            ioFiles: io,
            expectedExecutableContentDigest:
                proof.workerExecutionProfile.executableContentDigest,
            expectedArgumentVectorContentDigest:
                invocation.receipt.argumentVectorDigest,
            expectedProviderPromptArtifact: invocation.receipt.promptArtifact,
            nativeSandbox: nativeSandbox.configuration,
            kernelResourceLimits:
                KernelProviderInvocationCompiler.requiredResourceLimits
        )
        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("provider-secret")

        var unbounded = specification
        unbounded.kernelResourceLimits = nil
        do {
            _ = try await adapter.launchProvider(
                lease: value,
                specification: unbounded,
                authorization: invocation,
                secretCapability: secret
            )
            XCTFail("Expected the provider transport to reject absent native ceilings")
        } catch let error as ProcessGroupAdapterError {
            XCTAssertEqual(error, .providerInvocationUnauthorized)
        }

        let launch = try await adapter.launchProvider(
            lease: value,
            specification: specification,
            authorization: invocation,
            secretCapability: secret
        )

        XCTAssertEqual(launch.invocation, invocation.receipt)
        XCTAssertTrue(
            launch.invocationContextTransport.isValid(
                for: invocation.receipt
            )
        )
        XCTAssertEqual(
            launch.invocationContextTransport.targetDescriptor,
            KernelProviderInvocationCompiler.invocationContextDescriptor
        )
        XCTAssertEqual(
            launch.secretDelivery?.capabilityID,
            secret.metadata.capabilityID
        )
        XCTAssertEqual(
            launch.secretDelivery?.targetDescriptor,
            KernelProviderInvocationCompiler.credentialDescriptor
        )
        XCTAssertEqual(
            launch.handle.externalIdentity.nativeSandboxAttestation?.targetExecHandshakeSucceeded,
            true
        )
        XCTAssertEqual(
            launch.handle.externalIdentity.kernelResourceLimits,
            KernelProviderInvocationCompiler.requiredResourceLimits
        )
        let exit = try await adapter.join(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )
        XCTAssertEqual(exit.exitCode, 0)
        XCTAssertEqual(
            try String(
                contentsOf: journal.appendingPathComponent("provider-stdout.jsonl"),
                encoding: .utf8
            ),
            "{\"invocationDigest\":\"\(invocation.receipt.invocationDigest.rawValue)\","
                + "\"proposedDisposition\":\"completed\","
                + "\"requestNonce\":\"\(invocation.receipt.requestNonce.rawValue)\","
                + "\"resultDigest\":\"\(String(repeating: "d", count: 64))\","
                + "\"schemaVersion\":1,\"sequence\":0,"
                + "\"threadID\":\"fixture-provider\",\"type\":\"terminal\"}\n"
        )
        let stderr = try Data(
            contentsOf: journal.appendingPathComponent("provider-stderr.txt")
        )
        XCTAssertTrue(stderr.isEmpty)
        XCTAssertFalse(
            try String(
                contentsOf: journal.appendingPathComponent("provider-stdout.jsonl"),
                encoding: .utf8
            ).contains("ephemeral-provider-secret")
        )
    }

    func testProviderLaunchRejectsPromptDigestChangeOnSameInodeBeforeSpawn() async throws {
        let root = try makeRoot("provider-prompt-tamper")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try makeDirectories([workspace, journal])
        let proof = providerExecutionProof(workspace: workspace)
        let prompt = try KernelProviderPromptArtifactIssuer().issue(
            prompt: Data("exact provider prompt".utf8),
            fileName: "provider-prompt.json",
            journalRunDirectory: journal,
            executionProof: proof
        )
        let invocation = try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: prompt,
            requestNonce: contentDigest("tamper-nonce")
        )
        let secret = try KernelProviderSecretIssuer().issue(
            secret: Data("still-unconsumed".utf8),
            for: invocation,
            executionProof: proof,
            lifetimeNanoseconds: 5_000_000_000
        )
        let promptPath = journal.appendingPathComponent("provider-prompt.json").path
        XCTAssertEqual(Darwin.chmod(promptPath, 0o600), 0)
        let descriptor = Darwin.open(promptPath, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        var replacement: UInt8 = 0x58
        XCTAssertEqual(Darwin.pwrite(descriptor, &replacement, 1, 0), 1)
        XCTAssertEqual(Darwin.fsync(descriptor), 0)
        _ = Darwin.close(descriptor)
        XCTAssertEqual(Darwin.chmod(promptPath, 0o400), 0)

        let io = ManagedProcessIOFiles(
            directoryPath: journal.path,
            standardInputFileName: prompt.receipt.fileName,
            standardOutputFileName: "tamper-stdout.jsonl",
            standardErrorFileName: "tamper-stderr.txt"
        )
        let sandbox = try KernelNativeSandboxAuthorizer().authorize(
            executionProfile: proof.workerExecutionProfile,
            workspaceRoot: workspace,
            journalRunDirectory: journal,
            ioFiles: io
        )
        let specification = ManagedProcessSpecification(
            executablePath: kernelProcessFixturePath,
            arguments: invocation.receipt.arguments,
            environment: [:],
            ioFiles: io,
            expectedExecutableContentDigest:
                proof.workerExecutionProfile.executableContentDigest,
            expectedArgumentVectorContentDigest:
                invocation.receipt.argumentVectorDigest,
            expectedProviderPromptArtifact: invocation.receipt.promptArtifact,
            nativeSandbox: sandbox.configuration,
            kernelResourceLimits:
                KernelProviderInvocationCompiler.requiredResourceLimits
        )
        let adapter = ProcessGroupRuntimeAdapter()
        do {
            _ = try await adapter.launchProvider(
                lease: lease("provider-prompt-tamper"),
                specification: specification,
                authorization: invocation,
                secretCapability: secret
            )
            XCTFail("Expected prompt digest mismatch")
        } catch let error as ProcessGroupAdapterError {
            XCTAssertEqual(error, .providerPromptArtifactMismatch)
        }
        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: journal.appendingPathComponent("tamper-stdout.jsonl").path
            )
        )
    }

    func testWorkspaceSandboxAttestsBeforeResumeAndProtectsJournalEvidence() async throws {
        let root = try makeRoot("workspace")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try makeDirectories([workspace, journal])
        let io = ManagedProcessIOFiles(
            directoryPath: journal.path,
            standardInputFileName: nil,
            standardOutputFileName: "stdout.txt",
            standardErrorFileName: "stderr.txt"
        )
        let authorized = try KernelNativeSandboxAuthorizer().authorize(
            executionProfile: profile(sandbox: .workspaceOnly),
            workspaceRoot: workspace,
            journalRunDirectory: journal,
            ioFiles: io
        )
        let specification = ManagedProcessSpecification(
            executablePath: "/bin/sh",
            arguments: [
                "-c",
                "echo exact-output; touch \"$1/allowed\"; first=$?; "
                    + "touch \"$2/forbidden\"; second=$?; "
                    + "echo status:$first:$second; test $first -eq 0 -a $second -ne 0",
                "worker",
                authorized.configuration.parameters["WORKSPACE"] ?? "",
                URL(fileURLWithPath: authorized.configuration.parameters["STDOUT"] ?? "")
                    .deletingLastPathComponent().path
            ],
            environment: ["PATH": "/usr/bin:/bin"],
            ioFiles: io,
            expectedExecutableContentDigest: executableDigest("/bin/sh"),
            nativeSandbox: authorized.configuration
        )
        let adapter = ProcessGroupRuntimeAdapter()
        let lease = lease("workspace")
        let handle = try await adapter.launch(lease: lease, specification: specification)
        let attestation = try XCTUnwrap(handle.externalIdentity.nativeSandboxAttestation)
        XCTAssertEqual(attestation.authorization, authorized.configuration.receipt)
        XCTAssertEqual(attestation.processID, handle.processID)
        XCTAssertEqual(attestation.nativeSandboxCheckResult, 1)
        XCTAssertTrue(attestation.gateObservedStopped)
        XCTAssertTrue(attestation.targetExecHandshakeSucceeded)

        let exit = try await adapter.join(
            resourceID: lease.request.resourceID,
            leaseID: lease.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )
        XCTAssertEqual(exit.exitCode, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: workspace.appendingPathComponent("allowed").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: journal.appendingPathComponent("forbidden").path
            )
        )
        XCTAssertEqual(
            try String(
                contentsOf: journal.appendingPathComponent("stdout.txt"),
                encoding: .utf8
            ),
            "exact-output\nstatus:0:1\n"
        )
        for name in ["stdout.txt", "stderr.txt"] {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: journal.appendingPathComponent(name).path
            )
            XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o400)
        }
    }

    func testFullAccessAndOverlappingWorkspaceFailClosed() throws {
        let root = try makeRoot("fail-closed")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try makeDirectories([workspace, journal])

        XCTAssertThrowsError(
            try KernelNativeSandboxAuthorizer().authorize(
                executionProfile: profile(sandbox: .fullAccess),
                workspaceRoot: workspace,
                journalRunDirectory: journal,
                ioFiles: nil
            )
        ) { error in
            XCTAssertEqual(error as? KernelNativeSandboxError, .unsupportedFullAccess)
        }
        XCTAssertThrowsError(
            try KernelNativeSandboxAuthorizer().authorize(
                executionProfile: profile(sandbox: .readOnly),
                workspaceRoot: journal,
                journalRunDirectory: journal,
                ioFiles: nil
            )
        ) { error in
            XCTAssertEqual(error as? KernelNativeSandboxError, .workspaceOverlapsJournal)
        }
    }

    func testTamperedProfileCannotReachSpawn() async throws {
        let root = try makeRoot("tamper")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try makeDirectories([workspace, journal])
        var authorized = try KernelNativeSandboxAuthorizer().authorize(
            executionProfile: profile(sandbox: .readOnly),
            workspaceRoot: workspace,
            journalRunDirectory: journal,
            ioFiles: nil
        ).configuration
        authorized.profile += "(allow file-write*)\n"
        let specification = ManagedProcessSpecification(
            executablePath: "/bin/sleep",
            arguments: ["1"],
            environment: ["PATH": "/usr/bin:/bin"],
            expectedExecutableContentDigest: executableDigest("/bin/sleep"),
            nativeSandbox: authorized
        )
        let adapter = ProcessGroupRuntimeAdapter()
        do {
            _ = try await adapter.launch(lease: lease("tamper"), specification: specification)
            XCTFail("Expected tampered sandbox profile to reject")
        } catch let error as ProcessGroupAdapterError {
            XCTAssertEqual(error, .invalidSpecification)
        }
        let projection = await adapter.projection()
        XCTAssertTrue(projection.liveHandles.isEmpty)
    }

    func testSandboxGateInstallsVerifierFileAndChildProcessCeilings() async throws {
        let root = try makeRoot("verifier-kernel-limits")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let journal = root.appendingPathComponent("journal", isDirectory: true)
        try makeDirectories([workspace, journal])
        let io = ManagedProcessIOFiles(
            directoryPath: journal.path,
            standardInputFileName: nil,
            standardOutputFileName: "verifier.stdout",
            standardErrorFileName: "verifier.stderr"
        )
        let authorized = try KernelNativeSandboxAuthorizer().authorize(
            executionProfile: profile(sandbox: .readOnly),
            workspaceRoot: workspace,
            journalRunDirectory: journal,
            ioFiles: io
        )
        let stagedExecutable = journal.appendingPathComponent("staged-fixture")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: kernelProcessFixturePath),
            to: stagedExecutable
        )
        XCTAssertEqual(Darwin.chmod(stagedExecutable.path, 0o500), 0)
        let specification = ManagedProcessSpecification(
            executablePath: stagedExecutable.path,
            arguments: ["--emit-bytes", "4096"],
            environment: [:],
            ioFiles: io,
            expectedExecutableContentDigest: executableDigest(stagedExecutable.path),
            nativeSandbox: authorized.configuration,
            kernelResourceLimits: ManagedProcessKernelResourceLimits(
                maximumOutputFileBytes: 32,
                maximumProcessCount: 1
            )
        )
        let adapter = ProcessGroupRuntimeAdapter()
        let value = lease("verifier-kernel-limits")
        _ = try await adapter.launch(lease: value, specification: specification)
        let exit = try await adapter.join(
            resourceID: value.request.resourceID,
            leaseID: value.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )
        XCTAssertTrue(
            exit.terminationSignal == SIGXFSZ || exit.exitCode == 79,
            "the target must either receive SIGXFSZ or observe the hard EFBIG write failure"
        )
        XCTAssertEqual(
            try Data(
                contentsOf: journal.appendingPathComponent("verifier.stdout")
            ).count,
            32
        )

        let childIO = ManagedProcessIOFiles(
            directoryPath: journal.path,
            standardInputFileName: nil,
            standardOutputFileName: "child.stdout",
            standardErrorFileName: "child.stderr"
        )
        let childSandbox = try KernelNativeSandboxAuthorizer().authorize(
            executionProfile: profile(sandbox: .readOnly),
            workspaceRoot: workspace,
            journalRunDirectory: journal,
            ioFiles: childIO
        )
        let childSpecification = ManagedProcessSpecification(
            executablePath: stagedExecutable.path,
            arguments: ["--expect-child-process-denied"],
            environment: [:],
            ioFiles: childIO,
            expectedExecutableContentDigest: executableDigest(stagedExecutable.path),
            nativeSandbox: childSandbox.configuration,
            kernelResourceLimits: ManagedProcessKernelResourceLimits(
                maximumOutputFileBytes: 32,
                maximumProcessCount: 1
            )
        )
        let childLease = lease("verifier-child-limit")
        _ = try await adapter.launch(
            lease: childLease,
            specification: childSpecification
        )
        let childExit = try await adapter.join(
            resourceID: childLease.request.resourceID,
            leaseID: childLease.request.leaseID,
            timeoutNanoseconds: 2_000_000_000
        )
        XCTAssertEqual(childExit.exitCode, 0)
    }

    private func profile(sandbox: KernelExecutionSandbox) -> KernelAgentExecutionProfile {
        KernelAgentExecutionProfile(
            provider: .local,
            providerReference: "sandbox-test-worker",
            executableContentDigest: executableDigest("/bin/sh"),
            modelID: "sandbox-test-model",
            reasoningEffort: nil,
            sandbox: sandbox,
            networkPolicy: .disabled,
            pluginPolicy: .disabled,
            environmentPolicy: .minimalKernelAllowlist
        )
    }

    private func providerExecutionProof(
        workspace: URL
    ) -> JournaledKernelExecutionProof {
        JournaledKernelExecutionProof.testOnly(
            runID: KernelRunID("sandbox-test-run"),
            attemptID: AttemptID("attempt-provider-secret"),
            nodeID: KernelNodeID("provider-node"),
            strategyFingerprint: StrategyFingerprint("provider-strategy"),
            workerExecutionProfile: KernelAgentExecutionProfile(
                provider: .api,
                providerReference: "remote-provider-harness",
                executableContentDigest: executableDigest(kernelProcessFixturePath),
                modelID: "provider-model",
                reasoningEffort: "high",
                sandbox: .readOnly,
                networkPolicy: .enabled,
                pluginPolicy: .disabled,
                environmentPolicy: .minimalKernelAllowlist,
                providerProtocol: .loopForgeProviderHarnessV2,
                providerHarnessMode: .productive,
                credentialMode: .opaqueProviderSecret,
                credentialReference: KernelProviderCredentialReference(
                    source: .macOSKeychainGenericPassword,
                    service: "test.loopforge.provider",
                    account: "native-sandbox-provider"
                )
            ),
            workspaceRoot: workspace,
            activationActor: ActorIdentity(
                id: ActorID("provider-actor"),
                role: "worker",
                lineageDigest: contentDigest("provider-actor")
            ),
            activationTransaction: JournalTransactionReceipt(
                commandID: RunCommandID("provider-activation"),
                startingSequence: 1,
                endingSequence: 1,
                eventIDs: [OrchestrationEventID("provider-activation-event")],
                frameDigest: contentDigest("provider-frame"),
                duplicate: false
            )
        )
    }

    private func contentDigest(_ value: String) -> ContentDigest {
        KernelWorkerResultParser.contentDigest(Data(value.utf8))
    }

    private var kernelProcessFixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/KernelProcessFixture")
            .standardizedFileURL.path
    }

    private func executableDigest(_ path: String) -> ContentDigest {
        ProcessGroupRuntimeAdapter.executableContentDigest(atPath: path)
            ?? ContentDigest("")
    }

    private func makeRoot(_ name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-NativeSandbox-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func makeDirectories(_ values: [URL]) throws {
        for value in values {
            try FileManager.default.createDirectory(
                at: value,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private func lease(_ id: String) -> RuntimeResourceLease {
        RuntimeResourceLease(
            request: RuntimeLeaseRequest(
                leaseID: ResourceLeaseID("lease-\(id)"),
                resourceID: OwnedResourceID("resource-\(id)"),
                runID: KernelRunID("sandbox-test-run"),
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
            ),
            admittedAtMonotonicNanoseconds: 1,
            lastProgressReceiptID: nil
        )
    }
}
