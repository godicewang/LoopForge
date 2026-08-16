import Foundation
@testable import LoopForge

struct JournaledTestWorkerDispositionReceipt {
    var release: JournaledProcessNaturalReleaseReceipt
    var parse: JournaledWorkerResultParseReceipt
    var execution: JournaledExecutionDerivationReceipt
}

func externalDependencyObservationProbeFixture(
    networkPolicy: KernelNetworkPolicy = .disabled
) -> ExternalDependencyObservationExecutableProbe {
    ExternalDependencyObservationExecutableProbe(
        schemaVersion: 1,
        transport: .localDirectProcess,
        executableContentDigest: ContentDigest(String(repeating: "a", count: 64)),
        fixedArguments: [
            "--request",
            ExternalDependencyObservationExecutableProbe.requestArgumentToken
        ],
        environmentPolicy: .minimalKernelAllowlist,
        environmentIdentityDigest: KernelProcessEnvironmentAuthorizer
            .environmentDigest(
                KernelProcessEnvironmentAuthorizer.minimalEnvironment
            ),
        captureIdentityDigest:
            ExternalDependencyObservationCapturePolicy.identityDigest,
        parser: ExternalDependencyObservationParserContract(
            id: "external-dependency-canonical-parser",
            schemaVersion: 1,
            contentDigest: ExternalDependencyObservationParserFormat
                .canonicalJSONAvailabilityV1.implementationIdentityDigest,
            format: .canonicalJSONAvailabilityV1
        ),
        resultMappings: [
            ExternalDependencyObservationResultMapping(
                exitCode: 0,
                parserResultCode: "available",
                availability: .available
            ),
            ExternalDependencyObservationResultMapping(
                exitCode: 3,
                parserResultCode: "unavailable",
                availability: .unavailable
            )
        ],
        networkPolicy: networkPolicy,
        resourceLimits: RequirementVerificationResourceLimits(
            maximumWallClockSeconds: 30,
            maximumCapturedOutputBytes: 65_536,
            maximumResidentBytes: 134_217_728,
            maximumChildProcesses: 0
        )
    )
}

/// Journals a fully typed synthetic process provenance chain for tests whose
/// subject lies after execution. This deliberately exercises the same reducer
/// boundary as production; it does not expose a source-side execution bypass.
@discardableResult
func journalTestWorkerDisposition(
    _ journal: RunJournal,
    runID: KernelRunID,
    attemptID: AttemptID,
    actor: ActorIdentity,
    prefix: String,
    proposedDisposition: KernelWorkerProposedDisposition = .completed,
    startingAt: TimeInterval = 1_000
) async throws -> JournaledTestWorkerDispositionReceipt {
    let resourceID = OwnedResourceID("\(prefix)-resource")
    let leaseID = ResourceLeaseID("\(prefix)-lease")
    let admissionID = ReceiptID("\(prefix)-admission")
    let bindingID = ReceiptID("\(prefix)-binding")
    let releaseID = ReceiptID("\(prefix)-release")
    let parseID = ReceiptID("\(prefix)-parse")
    let derivationID = ReceiptID("\(prefix)-derivation")
    let monotonic: UInt64 = 10_000
    let request = RuntimeLeaseRequest(
        leaseID: leaseID,
        resourceID: resourceID,
        runID: runID,
        occurrenceID: nil,
        attemptID: attemptID,
        kind: .processTree,
        purpose: .productive,
        ownership: .owned,
        releasePolicy: .join,
        externalIdentity: nil,
        reservation: .zero,
        requestedAtMonotonicNanoseconds: monotonic,
        renewalDeadlineMonotonicNanoseconds: nil,
        progressReceiptID: nil
    )
    let lease = RuntimeResourceLease(
        request: request,
        admittedAtMonotonicNanoseconds: monotonic + 1,
        lastProgressReceiptID: nil
    )
    let admission = RuntimeAdmissionReceipt(
        id: admissionID,
        runID: runID,
        request: request,
        outcome: .accepted(lease, duplicate: false),
        observedAt: Date(timeIntervalSince1970: startingAt),
        observedAtMonotonicNanoseconds: monotonic + 1
    )
    _ = try await journal.transactAtCurrentSequence(
        .testOnlyRecordRuntimeAdmission(admission),
        commandID: RunCommandID("\(prefix)-admission-command"),
        issuedAt: admission.observedAt,
        actor: actor
    )

    let identity = RuntimeExternalIdentity(
        stableDigest: KernelWorkerResultParser.contentDigest(Data("\(prefix)-identity".utf8)),
        processID: 42,
        processStartMonotonicNanoseconds: monotonic + 2
    )
    let binding = RuntimeExternalBindingReceipt(
        id: bindingID,
        runID: runID,
        resourceID: resourceID,
        leaseID: leaseID,
        identity: identity,
        accepted: true,
        observedAt: Date(timeIntervalSince1970: startingAt + 1),
        observedAtMonotonicNanoseconds: monotonic + 2
    )
    _ = try await journal.transactAtCurrentSequence(
        .testOnlyRecordRuntimeBinding(binding),
        commandID: RunCommandID("\(prefix)-binding-command"),
        issuedAt: binding.observedAt,
        actor: actor
    )

    let handle = ManagedProcessHandle(
        runID: runID,
        resourceID: resourceID,
        leaseID: leaseID,
        processID: 42,
        processGroupID: 42,
        externalIdentity: identity
    )
    let exit = ManagedProcessExitReceipt(
        handle: handle,
        observedAtMonotonicNanoseconds: monotonic + 3,
        exitCode: 0,
        terminationSignal: nil
    )
    let release = RuntimeReleaseOutcomeReceipt(
        id: releaseID,
        runID: runID,
        resourceID: resourceID,
        leaseID: leaseID,
        observedAt: Date(timeIntervalSince1970: startingAt + 2),
        observedAtMonotonicNanoseconds: monotonic + 3,
        outcome: .released(RuntimeReleaseReceipt(
            id: releaseID,
            runID: runID,
            leaseID: leaseID,
            resourceID: resourceID,
            releasedAtMonotonicNanoseconds: monotonic + 3,
            duplicate: false
        )),
        managedProcessTermination: nil,
        managedProcessExit: exit
    )
    let releaseTransaction = try await journal.transactAtCurrentSequence(
        .testOnlyRecordRuntimeRelease(release),
        commandID: RunCommandID("\(prefix)-release-command"),
        issuedAt: release.observedAt,
        actor: actor
    )

    let invocationDigest = KernelWorkerResultParser.contentDigest(
        Data("\(prefix)-invocation".utf8)
    )
    let nonce = KernelWorkerResultParser.contentDigest(Data("\(prefix)-nonce".utf8))
    let resultDigest = KernelWorkerResultParser.contentDigest(Data("\(prefix)-result".utf8))
    let terminal = KernelWorkerStreamEnvelope(
        invocationDigest: invocationDigest,
        payloadDigest: nil,
        proposedDisposition: proposedDisposition,
        requestNonce: nonce,
        resultDigest: resultDigest,
        schemaVersion: 1,
        sequence: 0,
        threadID: "\(prefix)-thread",
        type: .terminal
    )
    var stdout = try KernelWorkerResultParser.canonicalLine(terminal)
    stdout.append(0x0a)
    let authorized = try KernelWorkerResultParser().parseAuthorized(
        stdout: stdout,
        stderr: Data(),
        expectation: KernelWorkerResultParseExpectation(
            runID: runID,
            attemptID: attemptID,
            resourceID: resourceID,
            leaseID: leaseID,
            bindingReceiptID: bindingID,
            releaseReceiptID: releaseID,
            invocationDigest: invocationDigest,
            requestNonce: nonce,
            nativeExit: exit
        ),
        receiptID: parseID
    )
    let parseTransaction = try await journal.transactAtCurrentSequence(
        .recordWorkerResultParse(authorized),
        commandID: RunCommandID("\(prefix)-parse-command"),
        issuedAt: Date(timeIntervalSince1970: startingAt + 3),
        actor: actor
    )
    let executionTransaction = try await journal.transactAtCurrentSequence(
        .deriveExecution(
            receiptID: derivationID,
            source: .workerResultParse(parseID)
        ),
        commandID: RunCommandID("\(prefix)-derive-command"),
        issuedAt: Date(timeIntervalSince1970: startingAt + 4),
        actor: actor
    )
    guard let execution = await journal.executionDerivationReceipt(
        transaction: executionTransaction
    ) else {
        throw RunJournalError.runIdentityMismatch
    }
    return JournaledTestWorkerDispositionReceipt(
        release: JournaledProcessNaturalReleaseReceipt(
            exit: exit,
            release: release,
            journalTransaction: releaseTransaction
        ),
        parse: JournaledWorkerResultParseReceipt(
            parse: authorized.receipt,
            journalTransaction: parseTransaction
        ),
        execution: JournaledExecutionDerivationReceipt(
            execution: execution,
            journalTransaction: executionTransaction
        )
    )
}
