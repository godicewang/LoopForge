import CryptoKit
import Dispatch
import Foundation

/// File-owned, non-serializable proof that a generic runtime fact came from
/// the journal/process coordinator. The initializer is unavailable outside
/// this source file and no token is returned from a public API.
struct JournaledProcessRuntimeCommandIssuer: Sendable {
  fileprivate init() {}
}

struct JournaledProcessLaunchReceipt: Sendable {
  var handle: ManagedProcessHandle
  var binding: RuntimeExternalBindingReceipt
  var journalTransaction: JournalTransactionReceipt
  var executableStaging: KernelExecutableStagingReceipt
  var processEnvironment: KernelProcessEnvironmentReceipt
  var nativeSandbox: KernelNativeSandboxAttestationReceipt
  var processIOFiles: ManagedProcessIOFiles?
  var providerLaunch: KernelProviderLaunchReceipt?
  var providerInvocation: KernelProviderInvocationReceipt?
  var providerInvocationContextTransport:
    KernelProviderInvocationContextTransportReceipt? = nil
  var providerSecretDelivery: KernelProviderSecretDeliveryReceipt?
}

private struct AuthorizedManagedProcessSpecification: Sendable {
  var specification: ManagedProcessSpecification
  var executableStaging: KernelExecutableStagingReceipt
  var processEnvironment: KernelProcessEnvironmentReceipt
  var nativeSandbox: KernelNativeSandboxReceipt
}

struct JournaledProcessStartReceipt: Sendable {
  var admission: RuntimeAdmissionReceipt
  var admissionTransaction: JournalTransactionReceipt
  var launch: JournaledProcessLaunchReceipt
}

struct KernelPostimageVerifierRuntimeRequest: Sendable {
  var leaseID: ResourceLeaseID
  var resourceID: OwnedResourceID
  var standardOutputFileName: String
  var standardErrorFileName: String
  var admissionReceiptID: ReceiptID
  var admissionCommandID: RunCommandID
  var bindingReceiptID: ReceiptID
  var launchReceiptID: ReceiptID
  var bindingCommandID: RunCommandID
  var launchFailureReleaseReceiptID: ReceiptID
  var launchFailureReleaseCommandID: RunCommandID
  var launchVetoReceiptID: ReceiptID
  var launchVetoCommandID: RunCommandID
}

struct JournaledPostimageVerifierStartReceipt: Sendable {
  var activation: KernelPostimageVerifierActivationReceipt
  var admission: RuntimeAdmissionReceipt
  var admissionTransaction: JournalTransactionReceipt
  var launch: JournaledProcessLaunchReceipt
  var verifierLaunch: KernelPostimageVerifierLaunchReceipt

  fileprivate init(
    activation: KernelPostimageVerifierActivationReceipt,
    admission: RuntimeAdmissionReceipt,
    admissionTransaction: JournalTransactionReceipt,
    launch: JournaledProcessLaunchReceipt,
    verifierLaunch: KernelPostimageVerifierLaunchReceipt
  ) {
    self.activation = activation
    self.admission = admission
    self.admissionTransaction = admissionTransaction
    self.launch = launch
    self.verifierLaunch = verifierLaunch
  }
}

struct ExternalDependencyObservationRuntimeRequest: Sendable {
  var leaseID: ResourceLeaseID
  var resourceID: OwnedResourceID
  var standardOutputFileName: String
  var standardErrorFileName: String
  var admissionReceiptID: ReceiptID
  var admissionCommandID: RunCommandID
  var bindingReceiptID: ReceiptID
  var launchReceiptID: ReceiptID
  var bindingCommandID: RunCommandID
  var launchFailureReleaseReceiptID: ReceiptID
  var launchFailureReleaseCommandID: RunCommandID
}

struct JournaledExternalDependencyObservationStartReceipt: Sendable {
  var activation: ExternalDependencyObservationActivationReceipt
  var admission: RuntimeAdmissionReceipt
  var admissionTransaction: JournalTransactionReceipt
  var launch: JournaledProcessLaunchReceipt
  var observerLaunch: ExternalDependencyObservationRuntimeLaunchReceipt

  fileprivate init(
    activation: ExternalDependencyObservationActivationReceipt,
    admission: RuntimeAdmissionReceipt,
    admissionTransaction: JournalTransactionReceipt,
    launch: JournaledProcessLaunchReceipt,
    observerLaunch: ExternalDependencyObservationRuntimeLaunchReceipt
  ) {
    self.activation = activation
    self.admission = admission
    self.admissionTransaction = admissionTransaction
    self.launch = launch
    self.observerLaunch = observerLaunch
  }
}

struct ExternalDependencyObservationCompletionRequest: Sendable {
  var releaseReceiptID: ReceiptID
  var releaseCommandID: RunCommandID
  var observationCommandID: RunCommandID
}

struct JournaledExternalDependencyObservationCompletionReceipt: Sendable {
  var release: JournaledProcessNaturalReleaseReceipt
  var result: ExternalDependencyObservationResultReceipt
  var observation: JournaledExternalDependencyObservationReceipt
}

struct KernelPostimageVerifierCompletionRequest: Sendable {
  var releaseReceiptID: ReceiptID
  var releaseCommandID: RunCommandID
}

struct JournaledPostimageVerifierCompletionReceipt: Sendable {
  var containment: KernelPostimageVerifierContainmentReceipt
  var naturalExit: ManagedProcessExitReceipt?
  var termination: ManagedProcessTerminationReceipt?
  var release: RuntimeReleaseOutcomeReceipt
  var journalTransaction: JournalTransactionReceipt
  var authorizedResult: AuthorizedKernelPostimageVerifierResult?
}

struct JournaledIndependentReviewReceipt: Sendable {
  var review: IndependentReviewReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct JournaledIntegrationTransitionReceipt: Sendable {
  var event: IntegrationTransitionEvent
  var journalTransaction: JournalTransactionReceipt
}

private struct PostimageVerifierCompletionContext: Sendable {
  var activation: KernelPostimageVerifierActivationReceipt
  var probe: RequirementVerificationExecutableProbe
  var launch: KernelPostimageVerifierLaunchReceipt
  var binding: RuntimeExternalBindingReceipt
  var lease: RuntimeResourceLease
  /// Nil only when a fresh adapter proved the exact journaled PID/start
  /// identity absent. The typed completion path must still publish a
  /// fail-red containment receipt before releasing logical ownership.
  var handle: ManagedProcessHandle?
}

private struct RetainedPostimageVerifierOutput: Sendable {
  var receipt: KernelPostimageVerifierOutputFileReceipt
  var data: Data
}

private struct ExternalDependencyObservationCompletionContext: Sendable {
  var activation: ExternalDependencyObservationActivationReceipt
  var probe: ExternalDependencyObservationExecutableProbe
  var launch: ExternalDependencyObservationRuntimeLaunchReceipt
  var binding: RuntimeExternalBindingReceipt
  var liveLease: RuntimeResourceLease?
}

private struct RetainedExternalDependencyObservationOutput: Sendable {
  var receipt: ExternalDependencyObservationOutputFileReceipt
  var data: Data
}

struct JournaledProcessReleaseReceipt: Sendable {
  var termination: ManagedProcessTerminationReceipt
  var release: RuntimeReleaseOutcomeReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct JournaledProcessNaturalReleaseReceipt: Sendable {
  var exit: ManagedProcessExitReceipt
  var release: RuntimeReleaseOutcomeReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct JournaledWorkerResultParseReceipt: Sendable {
  var parse: KernelWorkerResultParseReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct JournaledExecutionDerivationReceipt: Sendable {
  var execution: KernelExecutionDerivationReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct JournaledPostimageVerificationReceipt: Sendable {
  var verification: VerificationReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct JournaledProcessAbsenceReleaseReceipt: Sendable {
  var release: RuntimeReleaseOutcomeReceipt
  var journalTransaction: JournalTransactionReceipt
}

/// Typed provenance for the two lifecycle boundaries allowed to consume a
/// retained runtime-cleanup plan. The value is never supplied as free-form
/// text, so restart recovery cannot collide with normal-quit command IDs.
enum JournaledApplicationTerminationCleanupOrigin: String, Sendable {
  case nativeQuit
  case applicationCrashRecovery

  var commandPrefix: String {
    switch self {
    case .nativeQuit: "native-quit"
    case .applicationCrashRecovery: "native-crash-recovery"
    }
  }
}

/// In-memory proof that application termination consumed the exact cleanup
/// plan projected by the journal-restored supervisor. Every released resource
/// also has its ordinary durable runtime-release event; this receipt is not
/// serialized and cannot independently authorize quiescence.
struct JournaledApplicationTerminationCleanupReceipt: Sendable {
  var runID: KernelRunID
  var requestNonce: String
  var origin: JournaledApplicationTerminationCleanupOrigin
  var plannedActions: [RuntimeCleanupAction]
  var releaseReceiptIDs: [ReceiptID]
  var remainingActions: [RuntimeCleanupAction]
}

enum JournaledProcessRecoveryOutcome: Sendable {
  case recovered(ManagedProcessHandle)
  case unboundAdmission(RuntimeResourceLease)
  case unverifiableIdentity(RuntimeResourceLease)
  case identityMismatch(RuntimeResourceLease)
  case absentReleased(JournaledProcessAbsenceReleaseReceipt)
}

struct JournaledProcessRuntimeProjection: Equatable, Sendable {
  var adapter: ProcessGroupAdapterProjection
  var inDoubtResourceIDs: Set<OwnedResourceID>
}

enum JournaledProcessRuntimeError: Error, Equatable {
  case invalidSpecification
  case executionNotAuthorized
  case executionIOUnauthorized
  case executionEnvironmentUnauthorized
  case nativeSandboxUnauthorized
  case providerPromptUnauthorized
  case providerInvocationUnauthorized
  case providerCredentialUnauthorized
  case executableIdentityMismatch
  case admissionRejected(RuntimeAdmissionRejection)
  case ownershipDiverged
  case bindingRejected
  case journalWriteFailed
  case supervisorCommitFailed
  case nativeLaunchFailed(ProcessGroupAdapterError)
  case naturalExitTimedOut
  case terminationFailed
  case applicationTerminationCleanupUnavailable
  case applicationTerminationCleanupPlanChanged
  case applicationTerminationCleanupIncomplete(Int)
  case workerResultUnauthorized
  case workerResultParseFailed
  case postimageVerifierUnauthorized
  case externalDependencyObservationUnauthorized
  case residentMemoryEnforcementUnavailable
  case postimageVerifierCandidateInvalid
  case postimageVerifierOutputInvalid
  case externalDependencyObservationOutputInvalid
  case externalDependencyObservationResultInvalid
  case postimageVerificationRejected(KernelRejection)
  case independentReviewRejected(KernelRejection)
  case integrationRelianceRejected(KernelRejection)
}

/// Coordinates a real process group with the journal-first runtime protocol.
/// Journal publication precedes supervisor release, so a failed write retains
/// logical ownership and blocks quiescence even if native cleanup succeeded.
actor JournaledProcessRuntime {
  private let supervisor: RuntimeSupervisor
  private let journal: RunJournal
  private let adapter: ProcessGroupRuntimeAdapter
  private let actorIdentity: ActorIdentity
  private let executionProof: JournaledKernelExecutionProof?
  private let candidateExecutionRoot: AuthorizedWorkspacePreApplyCandidateExecutionRoot?
  private let residentMemoryEnforcement: AuthorizedKernelResidentMemoryEnforcement?
  private var inDoubtResourceIDs: Set<OwnedResourceID> = []

  init(
    supervisor: RuntimeSupervisor,
    journal: RunJournal,
    adapter: ProcessGroupRuntimeAdapter = ProcessGroupRuntimeAdapter(),
    actorIdentity: ActorIdentity,
    executionProof: JournaledKernelExecutionProof? = nil,
    candidateExecutionRoot:
      AuthorizedWorkspacePreApplyCandidateExecutionRoot? = nil,
    residentMemoryEnforcement:
      AuthorizedKernelResidentMemoryEnforcement? = nil
  ) {
    self.supervisor = supervisor
    self.journal = journal
    self.adapter = adapter
    self.actorIdentity = actorIdentity
    self.executionProof = executionProof
    self.candidateExecutionRoot = candidateExecutionRoot
    self.residentMemoryEnforcement = residentMemoryEnforcement
  }

  /// Creates the sole productive provider input beneath the exact run
  /// journal and returns non-serializable launch authority. Model prose and
  /// decoded receipts cannot enter this path.
  func prepareProviderInvocation(
    prompt: Data,
    promptFileName: String,
    requestNonce: ContentDigest
  ) async throws -> AuthorizedKernelProviderInvocation {
    guard let executionProof,
      await executionProofIsActive()
    else {
      throw JournaledProcessRuntimeError.executionNotAuthorized
    }
    let compiler = KernelProviderInvocationCompiler()
    do {
      try compiler.validateExecution(
        executionProof: executionProof,
        requestNonce: requestNonce
      )
    } catch {
      throw JournaledProcessRuntimeError.providerInvocationUnauthorized
    }
    let promptArtifact: AuthorizedKernelProviderPromptArtifact
    do {
      promptArtifact = try KernelProviderPromptArtifactIssuer().issue(
        prompt: prompt,
        fileName: promptFileName,
        journalRunDirectory: journal.runDirectory,
        executionProof: executionProof
      )
    } catch {
      throw JournaledProcessRuntimeError.providerPromptUnauthorized
    }
    do {
      return try compiler.authorize(
        executionProof: executionProof,
        promptArtifact: promptArtifact,
        requestNonce: requestNonce
      )
    } catch {
      throw JournaledProcessRuntimeError.providerInvocationUnauthorized
    }
  }

  func admitAndLaunchProvider(
    request: RuntimeLeaseRequest,
    executablePath: String,
    invocation: AuthorizedKernelProviderInvocation,
    secretCapability: KernelProviderSecretCapability?,
    standardOutputFileName: String,
    standardErrorFileName: String,
    admissionReceiptID: ReceiptID,
    admissionCommandID: RunCommandID,
    bindingReceiptID: ReceiptID,
    providerLaunchReceiptID: ReceiptID,
    bindingCommandID: RunCommandID,
    launchFailureReleaseReceiptID: ReceiptID,
    launchFailureReleaseCommandID: RunCommandID
  ) async throws -> JournaledProcessStartReceipt {
    guard await executionAuthorityMatches(request),
      providerInvocationMatchesExecutionProof(invocation)
    else {
      throw JournaledProcessRuntimeError.providerInvocationUnauthorized
    }
    let receipt = invocation.receipt
    switch receipt.credentialMode {
    case .none:
      guard secretCapability == nil else {
        throw JournaledProcessRuntimeError.providerCredentialUnauthorized
      }
    case .opaqueProviderSecret:
      guard let secretCapability,
        secretCapability.metadata.binding
          == KernelProviderSecretBinding(
            runID: receipt.runID,
            attemptID: receipt.attemptID,
            providerReference: receipt.executionProfile.providerReference,
            invocationDigest: receipt.invocationDigest
          )
      else {
        throw JournaledProcessRuntimeError.providerCredentialUnauthorized
      }
    }
    var specification = ManagedProcessSpecification(
      executablePath: executablePath,
      arguments: receipt.arguments,
      environment: [:],
      ioFiles: ManagedProcessIOFiles(
        directoryPath: journal.runDirectory.path,
        standardInputFileName: receipt.promptArtifact.fileName,
        standardOutputFileName: standardOutputFileName,
        standardErrorFileName: standardErrorFileName
      ),
      expectedExecutableContentDigest: receipt.executionProfile.executableContentDigest,
      expectedArgumentVectorContentDigest: receipt.argumentVectorDigest
    )
    do {
      try KernelProviderInvocationCompiler().validate(
        specification: specification,
        against: invocation
      )
    } catch {
      throw JournaledProcessRuntimeError.providerInvocationUnauthorized
    }
    specification.expectedProviderPromptArtifact = receipt.promptArtifact
    guard ProcessGroupRuntimeAdapter.specificationIsValid(specification) else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    var authorization = try await authorizedSpecification(specification)
    authorization.specification.kernelResourceLimits =
      KernelProviderInvocationCompiler.requiredResourceLimits
    guard ProcessGroupRuntimeAdapter.specificationIsValid(
      authorization.specification
    ) else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    do {
      try KernelProviderInvocationCompiler().validateTransport(
        specification: authorization.specification,
        against: invocation
      )
    } catch {
      throw JournaledProcessRuntimeError.providerInvocationUnauthorized
    }

    let observedAt = Date()
    let observedAtMonotonicNanoseconds = max(
      DispatchTime.now().uptimeNanoseconds,
      request.requestedAtMonotonicNanoseconds
    )
    let admission = await supervisor.previewAdmissionReceipt(
      request,
      receiptID: admissionReceiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
    )
    let admissionTransaction: JournalTransactionReceipt
    do {
      admissionTransaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeAdmission(
          .issuedByProcessRuntime(
            admission,
            issuer: .init()
          )),
        commandID: admissionCommandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyAdmissionReceipt(admission) else {
      inDoubtResourceIDs.insert(request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    guard case .accepted(let lease, _) = admission.outcome else {
      if case .rejected(let rejection) = admission.outcome {
        throw JournaledProcessRuntimeError.admissionRejected(rejection)
      }
      preconditionFailure("RuntimeAdmissionOutcome is exhaustive")
    }
    do {
      guard await executionAuthorityMatches(lease.request) else {
        throw JournaledProcessRuntimeError.executionNotAuthorized
      }
      let launch = try await launchAuthorized(
        lease: lease,
        authorization: authorization,
        bindingReceiptID: bindingReceiptID,
        providerLaunchReceiptID: providerLaunchReceiptID,
        commandID: bindingCommandID,
        providerInvocation: invocation,
        secretCapability: secretCapability
      )
      return JournaledProcessStartReceipt(
        admission: admission,
        admissionTransaction: admissionTransaction,
        launch: launch
      )
    } catch let error as ProcessGroupAdapterError {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: launchFailureReleaseReceiptID,
        commandID: launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError.nativeLaunchFailed(error)
    }
  }

  /// Admits and launches one exact activation-bound external dependency
  /// observer. The caller supplies no lease budget, environment, sandbox,
  /// executable staging, argv, or stdin authority; all are derived from the
  /// live readiness capability and journaled activation.
  func admitAndLaunchExternalDependencyObserver(
    readiness: AuthorizedExternalDependencyObservationLaunchReadiness,
    request: ExternalDependencyObservationRuntimeRequest
  ) async throws -> JournaledExternalDependencyObservationStartReceipt {
    guard Self.externalDependencyObservationRuntimeRequestIsValid(request)
    else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    guard await externalDependencyObservationReadinessIsActive(readiness)
    else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationUnauthorized
    }

    let activation = readiness.invocation.receipt
    let authorizedRequestArtifact: AuthorizedExternalDependencyObservationRequestArtifact
    do {
      authorizedRequestArtifact = try ExternalDependencyObservationRequestArtifactIssuer()
        .revalidate(
          expectedEnvelope:
            ExternalDependencyObservationActivationCompiler
            .envelope(receipt: activation),
          receiptID: activation.id,
          journalRunDirectory: journal.runDirectory,
          matching: activation.requestArtifact
        )
    } catch {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationUnauthorized
    }
    let staging = try revalidatedExternalDependencyExecutable(activation)
    let physicalJournalDirectory: URL
    do {
      physicalJournalDirectory =
        try KernelNativeSandboxAuthorizer
        .physicalDirectoryURL(journal.runDirectory)
    } catch {
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let io = ManagedProcessIOFiles(
      directoryPath: physicalJournalDirectory.path,
      standardInputFileName: authorizedRequestArtifact.receipt.fileName,
      standardOutputFileName: request.standardOutputFileName,
      standardErrorFileName: request.standardErrorFileName
    )
    let environmentAuthorization: AuthorizedKernelProcessEnvironment
    do {
      environmentAuthorization = try KernelProcessEnvironmentAuthorizer()
        .authorize(
          callerSuppliedEnvironment: [:],
          policy: .minimalKernelAllowlist
        )
    } catch {
      throw JournaledProcessRuntimeError
        .executionEnvironmentUnauthorized
    }
    guard environmentAuthorization.receipt.environmentDigest == activation.environmentIdentityDigest
    else {
      throw JournaledProcessRuntimeError
        .executionEnvironmentUnauthorized
    }
    let observerProfile = KernelAgentExecutionProfile(
      provider: .local,
      providerReference: "kernel.external-dependency-observer",
      executableContentDigest: staging.contentDigest,
      modelID: activation.evidenceRecipeID.rawValue,
      reasoningEffort: nil,
      sandbox: .readOnly,
      networkPolicy: activation.networkPolicy,
      pluginPolicy: .disabled,
      environmentPolicy: .minimalKernelAllowlist
    )
    let sandboxAuthorization: AuthorizedKernelNativeSandbox
    do {
      sandboxAuthorization = try KernelNativeSandboxAuthorizer().authorize(
        executionProfile: observerProfile,
        workspaceRoot: URL(
          fileURLWithPath: activation.workspaceRootPath,
          isDirectory: true
        ),
        journalRunDirectory: journal.runDirectory,
        ioFiles: io
      )
    } catch {
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let specification = ManagedProcessSpecification(
      executablePath: staging.stagedExecutablePath,
      arguments: activation.resolvedArguments,
      environment: environmentAuthorization.environment,
      ioFiles: io,
      executableArgumentZero: staging.stagedExecutablePath,
      expectedExecutableContentDigest: staging.contentDigest,
      expectedEnvironmentContentDigest:
        environmentAuthorization.receipt.environmentDigest,
      expectedArgumentVectorContentDigest: activation.argumentVectorDigest,
      expectedProviderPromptArtifact: nil,
      expectedExternalDependencyRequestArtifact:
        authorizedRequestArtifact.receipt,
      nativeSandbox: sandboxAuthorization.configuration,
      kernelResourceLimits: ManagedProcessKernelResourceLimits(
        maximumOutputFileBytes:
          activation.resourceLimits.maximumCapturedOutputBytes / 2,
        maximumProcessCount: 1
      )
    )
    guard
      ExternalDependencyObservationRuntimeLaunchCompiler
        .specification(specification, matches: activation)
    else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }

    let requestedAt = DispatchTime.now().uptimeNanoseconds
    let wallNanoseconds = activation.resourceLimits.maximumWallClockSeconds
      .multipliedReportingOverflow(by: 1_000_000_000)
    guard !wallNanoseconds.overflow else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let renewal = requestedAt.addingReportingOverflow(
      wallNanoseconds.partialValue
    )
    guard !renewal.overflow else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let leaseRequest = RuntimeLeaseRequest(
      leaseID: request.leaseID,
      resourceID: request.resourceID,
      runID: activation.runID,
      occurrenceID: nil,
      attemptID: activation.attemptID,
      kind: .processTree,
      purpose: .productive,
      ownership: .owned,
      releasePolicy: .gracefulThenTerminate,
      externalIdentity: nil,
      reservation: ResourceVector(
        cpuWeight: 1,
        memoryBytes: activation.resourceLimits.maximumResidentBytes,
        diskIOWeight: 1,
        gpuWeight: 0,
        networkWeight: activation.networkPolicy == .enabled ? 1 : 0,
        guiSessionCount: 0,
        processCount: 1
      ),
      requestedAtMonotonicNanoseconds: requestedAt,
      renewalDeadlineMonotonicNanoseconds: renewal.partialValue,
      progressReceiptID: nil
    )
    let observedAt = Date()
    let admission = await supervisor.previewAdmissionReceipt(
      leaseRequest,
      receiptID: request.admissionReceiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: requestedAt
    )
    let admissionTransaction: JournalTransactionReceipt
    do {
      admissionTransaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeAdmission(
          .issuedByProcessRuntime(
            admission,
            issuer: .init()
          )),
        commandID: request.admissionCommandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyAdmissionReceipt(admission) else {
      inDoubtResourceIDs.insert(request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    guard case .accepted(let lease, _) = admission.outcome else {
      if case .rejected(let rejection) = admission.outcome {
        throw JournaledProcessRuntimeError.admissionRejected(rejection)
      }
      preconditionFailure("RuntimeAdmissionOutcome is exhaustive")
    }

    guard await externalDependencyObservationReadinessIsActive(readiness)
    else {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError
        .externalDependencyObservationUnauthorized
    }
    do {
      let secondRequest = try ExternalDependencyObservationRequestArtifactIssuer()
        .revalidate(
          expectedEnvelope:
            ExternalDependencyObservationActivationCompiler
            .envelope(receipt: activation),
          receiptID: activation.id,
          journalRunDirectory: journal.runDirectory,
          matching: activation.requestArtifact
        )
      let secondStaging = try revalidatedExternalDependencyExecutable(activation)
      guard secondRequest.receipt == authorizedRequestArtifact.receipt,
        secondStaging == staging
      else {
        throw JournaledProcessRuntimeError
          .externalDependencyObservationUnauthorized
      }
    } catch let error as JournaledProcessRuntimeError {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw error
    } catch {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError
        .externalDependencyObservationUnauthorized
    }

    let handle: ManagedProcessHandle
    do {
      handle = try await adapter.launchExternalDependencyObserver(
        lease: lease,
        specification: specification,
        authorization: readiness
      )
    } catch let error as ProcessGroupAdapterError {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError.nativeLaunchFailed(error)
    }
    guard
      let nativeSandbox =
        handle.externalIdentity.nativeSandboxAttestation,
      nativeSandbox.authorization == sandboxAuthorization.configuration.receipt,
      nativeSandbox.processID == handle.processID,
      nativeSandbox.nativeSandboxCheckResult == 1,
      nativeSandbox.gateObservedStopped,
      nativeSandbox.targetExecHandshakeSucceeded,
      nativeSandbox.candidateWorkingDirectory == nil
    else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let launchedAt = Date()
    let launchedAtMonotonic = max(
      DispatchTime.now().uptimeNanoseconds,
      handle.externalIdentity.processStartMonotonicNanoseconds ?? 0
    )
    let binding = await supervisor.previewExternalIdentityReceipt(
      resourceID: request.resourceID,
      leaseID: request.leaseID,
      identity: handle.externalIdentity,
      receiptID: request.bindingReceiptID,
      observedAt: launchedAt,
      observedAtMonotonicNanoseconds: launchedAtMonotonic
    )
    guard binding.accepted else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.bindingRejected
    }
    let observerLaunch = ExternalDependencyObservationRuntimeLaunchReceipt(
      schemaVersion: 1,
      id: request.launchReceiptID,
      runID: activation.runID,
      activationReceiptID: activation.id,
      activationJournalFrameDigest:
        readiness.invocation.activationTransaction.frameDigest,
      attemptID: activation.attemptID,
      dependencyID: activation.dependencyID,
      evidenceRecipeID: activation.evidenceRecipeID,
      observer: activation.observer,
      resourceID: request.resourceID,
      leaseID: request.leaseID,
      bindingReceiptID: request.bindingReceiptID,
      executableStaging: activation.executableStaging,
      requestArtifact: authorizedRequestArtifact.receipt,
      resolvedArguments: activation.resolvedArguments,
      argumentVectorDigest: activation.argumentVectorDigest,
      processEnvironment: environmentAuthorization.receipt,
      processIOFiles: io,
      nativeSandbox: nativeSandbox,
      parser: activation.parser,
      resultMappings: activation.resultMappings,
      networkPolicy: activation.networkPolicy,
      resourceLimits: activation.resourceLimits,
      residentMemoryCeilingBytes:
        activation.resourceLimits.maximumResidentBytes,
      launchedAt: launchedAt
    )
    guard
      let launchAuthorization =
        AuthorizedExternalDependencyObservationRuntimeLaunch
        .issuedByProcessRuntime(
          binding: binding,
          receipt: observerLaunch,
          readiness: readiness,
          issuer: .init()
        )
    else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError
        .externalDependencyObservationUnauthorized
    }
    let bindingTransaction: JournalTransactionReceipt
    do {
      bindingTransaction = try await journal.transactAtCurrentSequence(
        .recordExternalDependencyObservationRuntimeBinding(
          launchAuthorization
        ),
        commandID: request.bindingCommandID,
        issuedAt: launchedAt,
        actor: actorIdentity
      )
    } catch {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyExternalIdentityReceipt(binding) else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(request.resourceID)
    let launch = JournaledProcessLaunchReceipt(
      handle: handle,
      binding: binding,
      journalTransaction: bindingTransaction,
      executableStaging: activation.executableStaging,
      processEnvironment: environmentAuthorization.receipt,
      nativeSandbox: nativeSandbox,
      processIOFiles: io,
      providerLaunch: nil,
      providerInvocation: nil,
      providerSecretDelivery: nil
    )
    return JournaledExternalDependencyObservationStartReceipt(
      activation: activation,
      admission: admission,
      admissionTransaction: admissionTransaction,
      launch: launch,
      observerLaunch: observerLaunch
    )
  }

  /// Completes one exact journaled external-dependency launch without caller-
  /// supplied process, timeout, output, parse, mapping, or observation data.
  /// The release command is replayable: after the native exit is committed,
  /// crash recovery can re-read the descriptor-constrained retained files and
  /// reproduce the same result and observation transaction without recreating
  /// process authority.
  func completeExternalDependencyObservation(
    launchReceiptID: ReceiptID,
    request: ExternalDependencyObservationCompletionRequest
  ) async throws -> JournaledExternalDependencyObservationCompletionReceipt {
    guard
      Self.externalDependencyObservationCompletionRequestIsValid(request)
    else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let context = try await externalDependencyObservationCompletionContext(
      launchReceiptID: launchReceiptID
    )

    let release: JournaledProcessNaturalReleaseReceipt
    if let prior = await journal.transactionReceipt(
      commandID: request.releaseCommandID
    ) {
      guard
        let retained = await journal.runtimeReleaseReceipt(
          transaction: prior
        ),
        retained.id == request.releaseReceiptID,
        retained.runID == context.launch.runID,
        retained.resourceID == context.launch.resourceID,
        retained.leaseID == context.launch.leaseID,
        retained.managedProcessTermination == nil,
        retained.postimageVerifierContainment == nil,
        let exit = retained.managedProcessExit,
        exit.handle.runID == context.launch.runID,
        exit.handle.resourceID == context.launch.resourceID,
        exit.handle.leaseID == context.launch.leaseID,
        exit.handle.externalIdentity == context.binding.identity,
        exit.terminationSignal == nil
      else {
        throw JournaledProcessRuntimeError
          .externalDependencyObservationResultInvalid
      }
      release = JournaledProcessNaturalReleaseReceipt(
        exit: exit,
        release: retained,
        journalTransaction: prior
      )
    } else {
      guard let lease = context.liveLease,
        let processStart = context.binding.identity
          .processStartMonotonicNanoseconds
      else {
        throw JournaledProcessRuntimeError
          .externalDependencyObservationUnauthorized
      }
      do {
        let recovered = try await adapter.recover(lease: lease)
        guard recovered.externalIdentity == context.binding.identity else {
          throw JournaledProcessRuntimeError
            .externalDependencyObservationUnauthorized
        }
      } catch let error as JournaledProcessRuntimeError {
        throw error
      } catch {
        throw JournaledProcessRuntimeError
          .externalDependencyObservationUnauthorized
      }
      let wallNanoseconds = context.activation.resourceLimits
        .maximumWallClockSeconds.multipliedReportingOverflow(
          by: 1_000_000_000
        )
      let deadline = processStart.addingReportingOverflow(
        wallNanoseconds.partialValue
      )
      guard !wallNanoseconds.overflow, !deadline.overflow else {
        throw JournaledProcessRuntimeError.invalidSpecification
      }
      let now = DispatchTime.now().uptimeNanoseconds
      let remaining =
        now < deadline.partialValue ? deadline.partialValue - now : 0
      release = try await joinAndRelease(
        lease: lease,
        releaseReceiptID: request.releaseReceiptID,
        commandID: request.releaseCommandID,
        timeoutNanoseconds: remaining
      )
    }

    let output = try retainedExternalDependencyObservationOutput(
      context.launch
    )
    guard output.1.receipt.byteCount == 0 else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationResultInvalid
    }
    let expectation = ExternalDependencyObservationParseExpectation(
      dependencyID: context.activation.dependencyID,
      evidenceRecipeID: context.activation.evidenceRecipeID,
      requestNonce: context.activation.requestArtifact.requestNonce,
      parser: context.activation.parser
    )
    let parse: ExternalDependencyObservationParseReceipt
    do {
      parse = try ExternalDependencyObservationProbe().parse(
        standardOutput: output.0.data,
        expectation: expectation
      ).receipt
    } catch {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationResultInvalid
    }
    guard let exitCode = release.exit.exitCode,
      let mapping = ExternalDependencyObservationResultMapper.expectedReceipt(
        activation: context.activation,
        probe: context.probe,
        nativeExitCode: exitCode,
        parse: parse
      ),
      let result = ExternalDependencyObservationResultAuthority.expectedReceipt(
        activation: context.activation,
        probe: context.probe,
        release: release.release,
        releaseTransaction: release.journalTransaction,
        standardOutput: output.0.receipt,
        standardError: output.1.receipt,
        parse: parse,
        mapping: mapping
      )
    else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationResultInvalid
    }
    let authorized =
      AuthorizedExternalDependencyObservationResult
      .issuedByProcessRuntime(
        receipt: result,
        release: release.release,
        releaseTransaction: release.journalTransaction,
        issuer: .init()
      )
    let observation = try await ExternalDependencyObservationJournalCoordinator(
      journal: journal
    ).record(
      authorized,
      request: ExternalDependencyObservationJournalRequest(
        commandID: request.observationCommandID
      )
    )
    return JournaledExternalDependencyObservationCompletionReceipt(
      release: release,
      result: result,
      observation: observation
    )
  }

  /// Admits and launches one exact deterministic postimage verifier. This
  /// path is independent of worker execution authority, carries no provider
  /// credential, reads no retained output, and cannot mint a verdict.
  func admitAndLaunchPostimageVerifier(
    invocation: AuthorizedKernelPostimageVerifierInvocation,
    request: KernelPostimageVerifierRuntimeRequest,
    residentMemoryEnforcementAuthority:
      AuthorizedKernelResidentMemoryEnforcement? = nil,
    verifierExecutionActor: ActorIdentity? = nil
  ) async throws -> JournaledPostimageVerifierStartReceipt {
    let verifierActor = verifierExecutionActor ?? actorIdentity
    guard Self.postimageVerifierRuntimeRequestIsValid(request) else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    guard await postimageVerifierInvocationIsActive(
      invocation,
      executionActor: verifierActor
    ) else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    guard
      (residentMemoryEnforcementAuthority ?? residentMemoryEnforcement)?
        .authorizes(
        activation: invocation.receipt
      ) == true
    else {
      let activation = invocation.receipt
      let state = await journal.state
      let observedAt = Date()
      let veto = KernelPostimageVerifierLaunchVetoReceipt(
        schemaVersion: 1,
        id: request.launchVetoReceiptID,
        runID: activation.runID,
        activationReceiptID: activation.id,
        activationJournalFrameDigest:
          invocation.activationTransaction.frameDigest,
        integrationTransactionID:
          activation.integrationTransactionID,
        applyReceiptID: activation.applyReceiptID,
        attemptID: activation.attemptID,
        evidenceRecipeID: activation.evidenceRecipeID,
        verifier: activation.verifier,
        requiredMaximumResidentBytes:
          activation.resourceLimits.maximumResidentBytes,
        reason: .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
        sourceJournalSequence: state.sequence,
        observedAt: observedAt
      )
      do {
        _ = try await journal.transactAtCurrentSequence(
          .recordPostimageVerifierLaunchVeto(
            .issuedByProcessRuntime(
              receipt: veto,
              issuer: .init()
            )
          ),
          commandID: request.launchVetoCommandID,
          issuedAt: observedAt,
          actor: verifierActor
        )
      } catch {
        throw JournaledProcessRuntimeError.journalWriteFailed
      }
      throw JournaledProcessRuntimeError
        .residentMemoryEnforcementUnavailable
    }
    do {
      _ = try WorkspaceCandidatePostimageMaterializer().revalidate(
        invocation.candidateInput
      )
    } catch {
      throw JournaledProcessRuntimeError.postimageVerifierCandidateInvalid
    }

    let activation = invocation.receipt
    let io = ManagedProcessIOFiles(
      directoryPath: journal.runDirectory.path,
      standardInputFileName: nil,
      standardOutputFileName: request.standardOutputFileName,
      standardErrorFileName: request.standardErrorFileName
    )
    let environmentAuthorization: AuthorizedKernelProcessEnvironment
    do {
      environmentAuthorization = try KernelProcessEnvironmentAuthorizer()
        .authorize(
          callerSuppliedEnvironment: [:],
          policy: .minimalKernelAllowlist
        )
    } catch {
      throw JournaledProcessRuntimeError.executionEnvironmentUnauthorized
    }
    guard environmentAuthorization.receipt.environmentDigest == activation.environmentIdentityDigest
    else {
      throw JournaledProcessRuntimeError.executionEnvironmentUnauthorized
    }
    let verifierProfile = KernelAgentExecutionProfile(
      provider: .local,
      providerReference: "kernel.deterministic-postimage-verifier",
      executableContentDigest: activation.executableStaging.contentDigest,
      modelID: activation.evidenceRecipeID.rawValue,
      reasoningEffort: nil,
      sandbox: .readOnly,
      networkPolicy: .disabled,
      pluginPolicy: .disabled,
      environmentPolicy: .minimalKernelAllowlist
    )
    let sandboxAuthorization: AuthorizedKernelNativeSandbox
    do {
      sandboxAuthorization = try KernelNativeSandboxAuthorizer().authorize(
        executionProfile: verifierProfile,
        workspaceRoot: URL(
          fileURLWithPath: activation.workspaceRootPath,
          isDirectory: true
        ),
        journalRunDirectory: journal.runDirectory,
        ioFiles: io
      )
    } catch {
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let staging = try revalidatedVerifierExecutable(activation)
    var specification = ManagedProcessSpecification(
      executablePath: staging.stagedExecutablePath,
      arguments: activation.resolvedArguments,
      environment: environmentAuthorization.environment,
      ioFiles: io,
      executableArgumentZero: staging.stagedExecutablePath,
      expectedExecutableContentDigest: staging.contentDigest,
      expectedEnvironmentContentDigest:
        environmentAuthorization.receipt.environmentDigest,
      expectedArgumentVectorContentDigest: activation.argumentVectorDigest,
      expectedProviderPromptArtifact: nil,
      nativeSandbox: sandboxAuthorization.configuration,
      kernelResourceLimits: ManagedProcessKernelResourceLimits(
        maximumOutputFileBytes:
          activation.resourceLimits.maximumCapturedOutputBytes / 2,
        maximumProcessCount: 1
      )
    )
    guard ProcessGroupRuntimeAdapter.specificationIsValid(specification),
      KernelPostimageVerifierActivationCompiler.specification(
        specification,
        matches: invocation
      )
    else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }

    let requestedAt = DispatchTime.now().uptimeNanoseconds
    let wallNanoseconds = activation.resourceLimits.maximumWallClockSeconds
      .multipliedReportingOverflow(by: 1_000_000_000)
    guard !wallNanoseconds.overflow else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let renewal = requestedAt.addingReportingOverflow(
      wallNanoseconds.partialValue
    )
    guard !renewal.overflow else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let leaseRequest = RuntimeLeaseRequest(
      leaseID: request.leaseID,
      resourceID: request.resourceID,
      runID: activation.runID,
      occurrenceID: nil,
      attemptID: activation.attemptID,
      kind: .processTree,
      purpose: .productive,
      ownership: .owned,
      releasePolicy: .gracefulThenTerminate,
      externalIdentity: nil,
      reservation: ResourceVector(
        cpuWeight: 1,
        memoryBytes: activation.resourceLimits.maximumResidentBytes,
        diskIOWeight: 1,
        gpuWeight: 0,
        networkWeight: 0,
        guiSessionCount: 0,
        processCount: 1
      ),
      requestedAtMonotonicNanoseconds: requestedAt,
      renewalDeadlineMonotonicNanoseconds: renewal.partialValue,
      progressReceiptID: nil
    )
    let observedAt = Date()
    let admission = await supervisor.previewAdmissionReceipt(
      leaseRequest,
      receiptID: request.admissionReceiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: requestedAt
    )
    let admissionTransaction: JournalTransactionReceipt
    do {
      admissionTransaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeAdmission(
          .issuedByProcessRuntime(
            admission,
            issuer: .init()
          )),
        commandID: request.admissionCommandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyAdmissionReceipt(admission) else {
      inDoubtResourceIDs.insert(request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    guard case .accepted(let lease, _) = admission.outcome else {
      if case .rejected(let rejection) = admission.outcome {
        throw JournaledProcessRuntimeError.admissionRejected(rejection)
      }
      preconditionFailure("RuntimeAdmissionOutcome is exhaustive")
    }

    guard await postimageVerifierInvocationIsActive(
      invocation,
      executionActor: verifierActor
    ) else {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let candidateDescriptor: AuthorizedWorkspaceCandidatePostimageDescriptor
    do {
      candidateDescriptor = try WorkspaceCandidatePostimageMaterializer()
        .openRevalidatedDescriptor(invocation.candidateInput)
      let secondStaging = try revalidatedVerifierExecutable(activation)
      guard secondStaging.stagedExecutablePath == staging.stagedExecutablePath,
        secondStaging.contentDigest == staging.contentDigest,
        secondStaging.byteCount == staging.byteCount,
        secondStaging.deviceID == staging.deviceID,
        secondStaging.inode == staging.inode
      else {
        throw JournaledProcessRuntimeError.executableIdentityMismatch
      }
    } catch {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError.postimageVerifierCandidateInvalid
    }
    defer { candidateDescriptor.close() }
    // Preserve the exact authorization assembled before admission. The
    // adapter independently rehashes executable, environment, and argv at
    // its immediate spawn boundary.
    specification.executablePath = staging.stagedExecutablePath
    let handle: ManagedProcessHandle
    do {
      handle = try await adapter.launchPostimageVerifier(
        lease: lease,
        specification: specification,
        authorization: invocation,
        candidateDescriptor: candidateDescriptor
      )
    } catch let error as ProcessGroupAdapterError {
      _ = try await releaseUnmaterializedLease(
        lease,
        receiptID: request.launchFailureReleaseReceiptID,
        commandID: request.launchFailureReleaseCommandID
      )
      throw JournaledProcessRuntimeError.nativeLaunchFailed(error)
    }
    guard let nativeSandbox = handle.externalIdentity.nativeSandboxAttestation,
      nativeSandbox.authorization == sandboxAuthorization.configuration.receipt,
      nativeSandbox.processID == handle.processID,
      nativeSandbox.nativeSandboxCheckResult == 1,
      nativeSandbox.gateObservedStopped,
      nativeSandbox.targetExecHandshakeSucceeded,
      nativeSandbox.candidateWorkingDirectory
        == KernelCandidateWorkingDirectoryAttestationReceipt(
          binding: .posixSpawnFileActionsFchdir,
          deviceID: activation.candidateMaterialization.deviceID,
          inode: activation.candidateMaterialization.inode
        )
    else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let launchedAt = Date()
    let launchedAtMonotonic = max(
      DispatchTime.now().uptimeNanoseconds,
      handle.externalIdentity.processStartMonotonicNanoseconds ?? 0
    )
    let binding = await supervisor.previewExternalIdentityReceipt(
      resourceID: request.resourceID,
      leaseID: request.leaseID,
      identity: handle.externalIdentity,
      receiptID: request.bindingReceiptID,
      observedAt: launchedAt,
      observedAtMonotonicNanoseconds: launchedAtMonotonic
    )
    guard binding.accepted else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.bindingRejected
    }
    let verifierLaunch = KernelPostimageVerifierLaunchReceipt(
      id: request.launchReceiptID,
      runID: activation.runID,
      activationReceiptID: activation.id,
      activationJournalFrameDigest:
        invocation.activationTransaction.frameDigest,
      integrationTransactionID: activation.integrationTransactionID,
      applyReceiptID: activation.applyReceiptID,
      attemptID: activation.attemptID,
      evidenceRecipeID: activation.evidenceRecipeID,
      verifier: activation.verifier,
      resourceID: request.resourceID,
      leaseID: request.leaseID,
      bindingReceiptID: request.bindingReceiptID,
      executableStaging: staging,
      candidateMaterialization: activation.candidateMaterialization,
      resolvedArguments: activation.resolvedArguments,
      argumentVectorDigest: activation.argumentVectorDigest,
      processEnvironment: environmentAuthorization.receipt,
      processIOFiles: io,
      nativeSandbox: nativeSandbox,
      parser: activation.parser,
      resourceLimits: activation.resourceLimits,
      launchedAt: launchedAt
    )
    let launchAuthorization =
      AuthorizedKernelPostimageVerifierLaunch
      .issuedByProcessRuntime(
        binding: binding,
        receipt: verifierLaunch,
        issuer: .init()
      )
    let bindingTransaction: JournalTransactionReceipt
    do {
      bindingTransaction = try await journal.transactAtCurrentSequence(
        .recordPostimageVerifierRuntimeBinding(launchAuthorization),
        commandID: request.bindingCommandID,
        issuedAt: launchedAt,
        actor: verifierActor
      )
    } catch {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyExternalIdentityReceipt(binding) else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(request.resourceID)
    let launch = JournaledProcessLaunchReceipt(
      handle: handle,
      binding: binding,
      journalTransaction: bindingTransaction,
      executableStaging: staging,
      processEnvironment: environmentAuthorization.receipt,
      nativeSandbox: nativeSandbox,
      processIOFiles: io,
      providerLaunch: nil,
      providerInvocation: nil,
      providerSecretDelivery: nil
    )
    return JournaledPostimageVerifierStartReceipt(
      activation: activation,
      admission: admission,
      admissionTransaction: admissionTransaction,
      launch: launch,
      verifierLaunch: verifierLaunch
    )
  }

  /// Owns the complete activated-verifier lifetime. The caller supplies no
  /// timeout, output budget, process handle, or verdict: all containment is
  /// derived from the exact journaled launch and recipe. Release and the
  /// containment receipt are committed in one journal event.
  func completePostimageVerifier(
    launchReceiptID: ReceiptID,
    request: KernelPostimageVerifierCompletionRequest
  ) async throws -> JournaledPostimageVerifierCompletionReceipt {
    let context = try await postimageVerifierCompletionContext(
      launchReceiptID: launchReceiptID
    )
    guard await postimageVerifierContextIsActive(context),
      let processStart = context.binding.identity
        .processStartMonotonicNanoseconds
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let wallNanoseconds = context.activation.resourceLimits
      .maximumWallClockSeconds.multipliedReportingOverflow(
        by: 1_000_000_000
      )
    let deadline = processStart.addingReportingOverflow(
      wallNanoseconds.partialValue
    )
    guard !wallNanoseconds.overflow, !deadline.overflow else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }

    guard let handle = context.handle else {
      return try await completeAbsentPostimageVerifier(
        context: context,
        processStart: processStart,
        wallDeadline: deadline.partialValue,
        request: request
      )
    }
    let now = DispatchTime.now().uptimeNanoseconds
    let remaining =
      now < deadline.partialValue
      ? deadline.partialValue - now
      : 0
    var naturalExit: ManagedProcessExitReceipt?
    var termination: ManagedProcessTerminationReceipt?
    do {
      naturalExit = try await adapter.join(
        resourceID: handle.resourceID,
        leaseID: handle.leaseID,
        timeoutNanoseconds: remaining
      )
    } catch ProcessGroupAdapterError.terminationTimedOut {
      do {
        termination = try await adapter.terminate(
          resourceID: handle.resourceID,
          leaseID: handle.leaseID,
          graceNanoseconds: 100_000_000
        )
      } catch {
        guard
          let lease = await journal.runtimeLease(
            resourceID: handle.resourceID
          )
        else {
          throw JournaledProcessRuntimeError.ownershipDiverged
        }
        try await recordCleanupFailure(
          lease: lease,
          receiptID: request.releaseReceiptID,
          commandID: request.releaseCommandID,
          error: error
        )
        throw JournaledProcessRuntimeError.terminationFailed
      }
    } catch {
      throw JournaledProcessRuntimeError.terminationFailed
    }
    guard let nativeExit = termination?.exit ?? naturalExit else {
      throw JournaledProcessRuntimeError.terminationFailed
    }

    let output:
      (
        RetainedPostimageVerifierOutput,
        RetainedPostimageVerifierOutput
      )?
    var outputFailureDigest: ContentDigest?
    do {
      output = try retainedPostimageVerifierOutput(
        context.launch
      )
    } catch {
      output = nil
      outputFailureDigest = containmentFailureDigest(error)
    }
    let quota =
      context.activation.resourceLimits
      .maximumCapturedOutputBytes / 2
    let quotaReached =
      quota > 0
      && output.map {
        $0.0.receipt.byteCount == quota || $0.1.receipt.byteCount == quota
      } == true
    let disposition: KernelPostimageVerifierContainmentDisposition
    if output == nil {
      disposition = .outputCaptureInvalid
    } else if nativeExit.terminationSignal == SIGXFSZ || quotaReached {
      disposition = .outputLimitExceeded
    } else if termination != nil
      || nativeExit.observedAtMonotonicNanoseconds > deadline.partialValue
    {
      disposition = .wallClockExceeded
    } else {
      disposition = .naturalExit
    }

    let observedAt = Date()
    let observedAtMonotonic = max(
      DispatchTime.now().uptimeNanoseconds,
      nativeExit.observedAtMonotonicNanoseconds
    )
    let parse = resultParseEvidence(context: context, output: output)
    let mapping = resultMappingEvidence(
      context: context,
      disposition: disposition,
      nativeExit: naturalExit,
      parse: parse.receipt
    )
    let result = postimageResultEvidence(
      context: context,
      releaseReceiptID: request.releaseReceiptID,
      output: output,
      parse: parse.receipt,
      mapping: mapping.receipt,
      completedAt: observedAt
    )
    let containment = KernelPostimageVerifierContainmentReceipt(
      schemaVersion: 4,
      runID: context.activation.runID,
      activationReceiptID: context.activation.id,
      launchReceiptID: context.launch.id,
      bindingReceiptID: context.launch.bindingReceiptID,
      resourceID: handle.resourceID,
      leaseID: handle.leaseID,
      processStartMonotonicNanoseconds: processStart,
      wallDeadlineMonotonicNanoseconds: deadline.partialValue,
      maximumOutputFileBytes: quota,
      resourceLimits: context.activation.resourceLimits,
      disposition: disposition,
      standardOutput: output?.0.receipt,
      standardError: output?.1.receipt,
      failureReasonDigest: outputFailureDigest,
      resultParse: parse.receipt,
      resultParseFailureDigest: parse.failureDigest,
      resultMapping: mapping.receipt,
      resultMappingFailureDigest: mapping.failureDigest,
      postimageResult: result.receipt,
      postimageResultFailureDigest: result.failureDigest,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonic
    )

    return try await publishPostimageVerifierRelease(
      context: context,
      containment: containment,
      naturalExit: naturalExit,
      termination: termination,
      request: request
    )
  }

  /// Application termination owns a distinct fail-red verifier path. It never
  /// waits out the productive wall deadline and never converts cancellation
  /// output into verification authority, but it preserves the same exact
  /// launch/binding/output/termination provenance in the release event.
  private func cleanupPostimageVerifierForApplicationTermination(
    lease: RuntimeResourceLease,
    releaseReceiptID: ReceiptID,
    releaseCommandID: RunCommandID
  ) async throws -> JournaledPostimageVerifierCompletionReceipt {
    let state = await journal.state
    guard let launch = (state.postimageVerifierLaunchReceipts ?? [:])
      .values.first(where: {
        $0.resourceID == lease.request.resourceID
          && $0.leaseID == lease.request.leaseID
      })
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let context = try await postimageVerifierCompletionContext(
      launchReceiptID: launch.id,
      executionActor: launch.verifier
    )
    guard await postimageVerifierContextIsOwnedForCleanup(context),
      let processStart = context.binding.identity
        .processStartMonotonicNanoseconds
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let wallNanoseconds = context.activation.resourceLimits
      .maximumWallClockSeconds.multipliedReportingOverflow(
        by: 1_000_000_000
      )
    let deadline = processStart.addingReportingOverflow(
      wallNanoseconds.partialValue
    )
    guard !wallNanoseconds.overflow, !deadline.overflow else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let request = KernelPostimageVerifierCompletionRequest(
      releaseReceiptID: releaseReceiptID,
      releaseCommandID: releaseCommandID
    )
    guard let handle = context.handle else {
      return try await completeAbsentPostimageVerifier(
        context: context,
        processStart: processStart,
        wallDeadline: deadline.partialValue,
        request: request
      )
    }

    let termination: ManagedProcessTerminationReceipt
    do {
      termination = try await adapter.terminate(
        resourceID: handle.resourceID,
        leaseID: handle.leaseID,
        graceNanoseconds: 100_000_000
      )
    } catch {
      try await recordCleanupFailure(
        lease: lease,
        receiptID: releaseReceiptID,
        commandID: releaseCommandID,
        error: error
      )
      throw JournaledProcessRuntimeError.terminationFailed
    }

    let output:
      (
        RetainedPostimageVerifierOutput,
        RetainedPostimageVerifierOutput
      )?
    var outputFailureDigest: ContentDigest?
    do {
      output = try retainedPostimageVerifierOutput(context.launch)
    } catch {
      output = nil
      outputFailureDigest = containmentFailureDigest(error)
    }
    let quota = context.activation.resourceLimits
      .maximumCapturedOutputBytes / 2
    let quotaReached = quota > 0
      && output.map {
        $0.0.receipt.byteCount == quota || $0.1.receipt.byteCount == quota
      } == true
    let disposition: KernelPostimageVerifierContainmentDisposition
    if output == nil {
      disposition = .outputCaptureInvalid
    } else if termination.exit.terminationSignal == SIGXFSZ || quotaReached {
      disposition = .outputLimitExceeded
    } else {
      disposition = .runtimeCleanupTermination
    }
    let observedAt = Date()
    let observedAtMonotonic = max(
      DispatchTime.now().uptimeNanoseconds,
      termination.exit.observedAtMonotonicNanoseconds
    )
    let parse = resultParseEvidence(context: context, output: output)
    let mapping = resultMappingEvidence(
      context: context,
      disposition: disposition,
      nativeExit: nil,
      parse: parse.receipt
    )
    let result = postimageResultEvidence(
      context: context,
      releaseReceiptID: releaseReceiptID,
      output: output,
      parse: parse.receipt,
      mapping: mapping.receipt,
      completedAt: observedAt
    )
    let containment = KernelPostimageVerifierContainmentReceipt(
      schemaVersion: 4,
      runID: context.activation.runID,
      activationReceiptID: context.activation.id,
      launchReceiptID: context.launch.id,
      bindingReceiptID: context.launch.bindingReceiptID,
      resourceID: handle.resourceID,
      leaseID: handle.leaseID,
      processStartMonotonicNanoseconds: processStart,
      wallDeadlineMonotonicNanoseconds: deadline.partialValue,
      maximumOutputFileBytes: quota,
      resourceLimits: context.activation.resourceLimits,
      disposition: disposition,
      standardOutput: output?.0.receipt,
      standardError: output?.1.receipt,
      failureReasonDigest: outputFailureDigest,
      resultParse: parse.receipt,
      resultParseFailureDigest: parse.failureDigest,
      resultMapping: mapping.receipt,
      resultMappingFailureDigest: mapping.failureDigest,
      postimageResult: result.receipt,
      postimageResultFailureDigest: result.failureDigest,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonic
    )
    return try await publishPostimageVerifierRelease(
      context: context,
      containment: containment,
      naturalExit: nil,
      termination: termination,
      request: request
    )
  }

  /// Records ordinary verification only from a live result capability and
  /// its exact v4 release transaction. All receipt fields are reconstructed
  /// from journal state; result bytes alone cannot invoke this boundary.
  func recordPostimageVerification(
    result authorizedResult: AuthorizedKernelPostimageVerifierResult,
    commandID: RunCommandID
  ) async throws -> JournaledPostimageVerificationReceipt {
    let result = authorizedResult.receipt
    let releaseTransaction = authorizedResult.releaseTransaction
    let state = await journal.state
    guard result.runID == journal.runID,
      let release = await journal.runtimeReleaseReceipt(
        transaction: releaseTransaction
      ),
      release.id == result.releaseReceiptID,
      release.postimageVerifierContainment?.schemaVersion == 4,
      release.postimageVerifierContainment?.postimageResult == result,
      let activation = state.postimageVerifierActivationReceipts?[
        result.activationReceiptID
      ],
      let launch = state.postimageVerifierLaunchReceipts?[
        result.launchReceiptID
      ],
      activation.runID == result.runID,
      activation.integrationTransactionID == result.integrationTransactionID,
      activation.applyReceiptID == result.applyReceiptID,
      activation.attemptID == result.attemptID,
      activation.requirementIDs == result.requirementIDs,
      activation.evidenceRecipeID == result.evidenceRecipeID,
      activation.sourceRevision == result.sourceRevision,
      activation.verifier == result.verifier,
      activation.reviewedVerificationReceiptID == nil,
      activation.reviewedVerificationEvidenceSetDigest == nil,
      activation.reviewEvidenceInputBindingID == nil,
      activation.reviewEvidenceArtifactID == nil,
      launch.activationReceiptID == activation.id,
      launch.verifier == result.verifier,
      launch.processEnvironment.environmentDigest.rawValue.isEmpty == false,
      actorIdentity == result.verifier,
      state.integrationTransactions[
        result.integrationTransactionID
      ]?.phase == .appliedUnverified,
      state.integrationTransactions[
        result.integrationTransactionID
      ]?.applyReceipt?.id == result.applyReceiptID,
      let verification =
        KernelPostimageVerificationAuthority.expectedReceipt(
          result: result,
          releaseTransaction: releaseTransaction,
          environmentDigest:
            launch.processEnvironment.environmentDigest,
          oracleDigest: activation.probeDigest
        )
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }

    if let prior = await journal.transactionReceipt(commandID: commandID),
      let existing = await journal.verificationReceipt(
        transaction: prior
      )
    {
      guard existing == verification else {
        throw JournaledProcessRuntimeError
          .postimageVerifierUnauthorized
      }
      return JournaledPostimageVerificationReceipt(
        verification: existing,
        journalTransaction: prior
      )
    }

    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordVerification(
          .issuedByProcessRuntime(
            receipt: verification,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: Date(),
        actor: actorIdentity
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw
        JournaledProcessRuntimeError
        .postimageVerificationRejected(rejection)
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard
      await journal.verificationReceipt(
        transaction: transaction
      ) == verification
    else {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    return JournaledPostimageVerificationReceipt(
      verification: verification,
      journalTransaction: transaction
    )
  }

  /// Records independent review only from a second live verifier result
  /// whose activation was journal-compiled with the exact accepted v2
  /// verification evidence-set digest. The caller supplies no review fields.
  func recordIndependentReview(
    result authorizedResult: AuthorizedKernelPostimageVerifierResult,
    commandID: RunCommandID
  ) async throws -> JournaledIndependentReviewReceipt {
    let result = authorizedResult.receipt
    let releaseTransaction = authorizedResult.releaseTransaction
    let state = await journal.state
    guard result.runID == journal.runID,
      let release = await journal.runtimeReleaseReceipt(
        transaction: releaseTransaction
      ),
      release.id == result.releaseReceiptID,
      release.postimageVerifierContainment?.schemaVersion == 4,
      release.postimageVerifierContainment?.postimageResult == result,
      let activation = state.postimageVerifierActivationReceipts?[
        result.activationReceiptID
      ],
      let reviewedID = activation.reviewedVerificationReceiptID,
      let reviewedDigest =
        activation.reviewedVerificationEvidenceSetDigest,
      activation.reviewEvidenceInputBindingID != nil,
      activation.reviewEvidenceArtifactID != nil,
      let reviewed = state.verificationReceipts[reviewedID],
      reviewed.result == .accepted,
      reviewed.attemptID == result.attemptID,
      reviewed.requirementIDs == result.requirementIDs,
      reviewed.sourceRevision == result.sourceRevision,
      reviewed.postimageEvidenceBatch?.evidenceSetDigest == reviewedDigest,
      result.verifier == activation.verifier,
      actorIdentity == result.verifier,
      result.verifier.lineageDigest != state.attempts[result.attemptID]?.worker.lineageDigest,
      result.requirementIDs.allSatisfy({
        state.verificationIsEffective(
          reviewed,
          requirementID: $0
        )
      }),
      let reviewedResult = state.runtimeReleaseReceipts.values
        .compactMap({
          $0.postimageVerifierContainment?.postimageResult
        })
        .first(where: {
          $0.id == reviewed.postimageEvidenceBatch?.postimageResultID
        }),
      reviewedResult.evidenceSetDigest
        == reviewed
        .postimageEvidenceBatch?.postimageResultEvidenceSetDigest,
      reviewedResult.integrationTransactionID == result.integrationTransactionID,
      reviewedResult.applyReceiptID == result.applyReceiptID,
      reviewedResult.sourceRevision == result.sourceRevision,
      reviewedResult.verifier.lineageDigest != result.verifier.lineageDigest
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }

    let review = IndependentReviewReceipt(
      id: ReceiptID("independent-review-\(result.id.rawValue)"),
      attemptID: result.attemptID,
      requirementIDs: result.requirementIDs,
      reviewer: result.verifier,
      evidenceDigest: result.evidenceSetDigest,
      sourceRevision: result.sourceRevision,
      decision: result.outcome == .accepted
        ? .approveCandidate
        : .rejectCandidate,
      verificationEvidenceSetDigest: reviewedDigest,
      sourcePostimageResultID: result.id
    )

    if let prior = await journal.transactionReceipt(commandID: commandID),
      let existing = await journal.independentReviewReceipt(
        transaction: prior
      )
    {
      guard existing == review else {
        throw JournaledProcessRuntimeError
          .postimageVerifierUnauthorized
      }
      return JournaledIndependentReviewReceipt(
        review: existing,
        journalTransaction: prior
      )
    }

    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordReview(
          .issuedByProcessRuntime(
            receipt: review,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: Date(),
        actor: actorIdentity
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw
        JournaledProcessRuntimeError
        .independentReviewRejected(rejection)
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard
      await journal.independentReviewReceipt(
        transaction: transaction
      ) == review
    else {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    return JournaledIndependentReviewReceipt(
      review: review,
      journalTransaction: transaction
    )
  }

  /// Advances only the integration verification phase from an already
  /// journaled, accepted, still-effective v2 verification. Selector IDs are
  /// caller input; every receipt field is reconstructed from journal state.
  func recordIntegrationPostimageVerification(
    result authorizedResult: AuthorizedKernelPostimageVerifierResult,
    integrationTransactionID: IntegrationTransactionID,
    sourceVerificationReceiptID: ReceiptID,
    commandID: RunCommandID
  ) async throws -> JournaledIntegrationTransitionReceipt {
    let state = await journal.state
    let authorizedReceipt = authorizedResult.receipt
    guard
      let integration = state.integrationTransactions[
        integrationTransactionID
      ],
      integration.phase == .appliedUnverified,
      let apply = integration.applyReceipt,
      let source = state.verificationReceipts[
        sourceVerificationReceiptID
      ],
      source.result == .accepted,
      source.attemptID == integration.proposal.attemptID,
      source.requirementIDs
        == state.attempts[source.attemptID]?
        .requirementIDs,
      source.sourceRevision
        == integration.proposal
        .expectedPostimageDigest,
      source.requirementIDs.allSatisfy({
        state.verificationIsEffective(
          source,
          requirementID: $0
        )
      }),
      let batch = source.postimageEvidenceBatch,
      authorizedReceipt.id == batch.postimageResultID,
      authorizedReceipt.evidenceSetDigest == batch.postimageResultEvidenceSetDigest,
      authorizedResult.releaseTransaction.commandID == batch.postimageReleaseCommandID,
      authorizedResult.releaseTransaction.endingSequence == batch.postimageReleaseEndingSequence,
      authorizedResult.releaseTransaction.frameDigest == batch.postimageReleaseFrameDigest,
      let release = state.runtimeReleaseReceipts[
        batch.postimageReleaseReceiptID
      ],
      release.id == batch.postimageReleaseReceiptID,
      let result = release.postimageVerifierContainment?
        .postimageResult,
      result.id == batch.postimageResultID,
      result.evidenceSetDigest == batch.postimageResultEvidenceSetDigest,
      result.integrationTransactionID == integrationTransactionID,
      result.applyReceiptID == apply.id,
      result.sourceRevision == source.sourceRevision,
      result.verifier == actorIdentity
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let receipt = IntegrationPostimageVerificationReceipt(
      id: ReceiptID(
        "integration-verification-\(source.id.rawValue)"
      ),
      transactionID: integrationTransactionID,
      applyReceiptID: apply.id,
      canonicalPostimageDigest: source.sourceRevision,
      evidenceSetDigest: batch.evidenceSetDigest,
      processQuiescenceReceiptID: batch.postimageReleaseReceiptID,
      verifier: result.verifier,
      verifiedAt: result.completedAt,
      result: .accepted,
      sourceVerificationReceiptID: source.id
    )
    return try await recordIntegrationTransition(
      .recordPostimageVerification(receipt),
      commandID: commandID
    )
  }

  /// Advances only independent integration acceptance from an exact
  /// journaled review that remains bound to the integration verification's
  /// source batch. No publication or completion authority is produced.
  func recordIntegrationIndependentAcceptance(
    result authorizedResult: AuthorizedKernelPostimageVerifierResult,
    integrationTransactionID: IntegrationTransactionID,
    sourceIndependentReviewReceiptID: ReceiptID,
    commandID: RunCommandID
  ) async throws -> JournaledIntegrationTransitionReceipt {
    let state = await journal.state
    let authorizedReceipt = authorizedResult.receipt
    guard
      let integration = state.integrationTransactions[
        integrationTransactionID
      ],
      integration.phase == .postimageVerified,
      let integrationVerification =
        integration.postimageVerificationReceipt,
      let sourceVerificationID = integrationVerification
        .sourceVerificationReceiptID,
      let sourceVerification = state.verificationReceipts[
        sourceVerificationID
      ],
      let batch = sourceVerification.postimageEvidenceBatch,
      let review = state.reviewReceipts[
        sourceIndependentReviewReceiptID
      ],
      review.attemptID == integration.proposal.attemptID,
      review.requirementIDs == sourceVerification.requirementIDs,
      review.sourceRevision
        == integration.proposal
        .expectedPostimageDigest,
      review.verificationEvidenceSetDigest == batch.evidenceSetDigest,
      state.reviewMatchesVerification(
        review,
        verification: sourceVerification
      ),
      let reviewResultID = review.sourcePostimageResultID,
      authorizedReceipt.id == reviewResultID,
      authorizedReceipt.evidenceSetDigest == review.evidenceDigest,
      let reviewResult = state.runtimeReleaseReceipts.values
        .compactMap({
          $0.postimageVerifierContainment?.postimageResult
        })
        .first(where: { $0.id == reviewResultID }),
      reviewResult.integrationTransactionID == integrationTransactionID,
      reviewResult.applyReceiptID == integration.applyReceipt?.id,
      reviewResult.sourceRevision == review.sourceRevision,
      reviewResult.verifier == review.reviewer,
      reviewResult == authorizedReceipt,
      review.reviewer == actorIdentity
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let receipt = IntegrationAcceptanceReceipt(
      id: ReceiptID(
        "integration-acceptance-\(review.id.rawValue)"
      ),
      transactionID: integrationTransactionID,
      verificationReceiptID: integrationVerification.id,
      canonicalPostimageDigest:
        integration.proposal.expectedPostimageDigest,
      evidenceDigest: review.evidenceDigest,
      reviewer: review.reviewer,
      reviewedAt: reviewResult.completedAt,
      decision:
        KernelIntegrationReceiptAuthority
        .acceptanceDecision(review: review),
      sourceIndependentReviewReceiptID: review.id,
      sourceVerificationEvidenceSetDigest: batch.evidenceSetDigest
    )
    return try await recordIntegrationTransition(
      .recordIndependentAcceptance(receipt),
      commandID: commandID
    )
  }

  private func recordIntegrationTransition(
    _ transition: IntegrationTransitionCommand,
    commandID: RunCommandID
  ) async throws -> JournaledIntegrationTransitionReceipt {
    if let prior = await journal.transactionReceipt(commandID: commandID),
      let event = await journal.integrationTransitionEvent(
        transaction: prior
      )
    {
      guard event == expectedIntegrationEvent(transition) else {
        throw JournaledProcessRuntimeError
          .postimageVerifierUnauthorized
      }
      return JournaledIntegrationTransitionReceipt(
        event: event,
        journalTransaction: prior
      )
    }
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .advanceIntegration(
          .issuedByProcessRuntime(
            transition,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: Date(),
        actor: actorIdentity
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw
        JournaledProcessRuntimeError
        .integrationRelianceRejected(rejection)
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard
      let event = await journal.integrationTransitionEvent(
        transaction: transaction
      ),
      event == expectedIntegrationEvent(transition)
    else {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    return JournaledIntegrationTransitionReceipt(
      event: event,
      journalTransaction: transaction
    )
  }

  private func expectedIntegrationEvent(
    _ transition: IntegrationTransitionCommand
  ) -> IntegrationTransitionEvent? {
    switch transition {
    case .recordPostimageVerification(let receipt):
      return .postimageVerificationRecorded(receipt)
    case .recordIndependentAcceptance(let receipt):
      return .independentAcceptanceRecorded(receipt)
    default:
      return nil
    }
  }

  #if DEBUG
    /// Generic process construction exists only for kernel transport tests.
    /// Product release builds expose provider launch solely through the typed
    /// invocation/capability API above.
    func admitAndLaunch(
      request: RuntimeLeaseRequest,
      specification: ManagedProcessSpecification,
      admissionReceiptID: ReceiptID,
      admissionCommandID: RunCommandID,
      bindingReceiptID: ReceiptID,
      bindingCommandID: RunCommandID,
      launchFailureReleaseReceiptID: ReceiptID,
      launchFailureReleaseCommandID: RunCommandID
    ) async throws -> JournaledProcessStartReceipt {
      guard ProcessGroupRuntimeAdapter.specificationIsValid(specification) else {
        throw JournaledProcessRuntimeError.invalidSpecification
      }
      guard executionIOIsJournalOwned(specification) else {
        throw JournaledProcessRuntimeError.executionIOUnauthorized
      }
      guard await executionAuthorityMatches(request) else {
        throw JournaledProcessRuntimeError.executionNotAuthorized
      }
      let authorization = try await authorizedSpecification(specification)

      let observedAt = Date()
      let observedAtMonotonicNanoseconds = max(
        DispatchTime.now().uptimeNanoseconds,
        request.requestedAtMonotonicNanoseconds
      )
      let admission = await supervisor.previewAdmissionReceipt(
        request,
        receiptID: admissionReceiptID,
        observedAt: observedAt,
        observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
      )
      let admissionTransaction: JournalTransactionReceipt
      do {
        admissionTransaction = try await journal.transactAtCurrentSequence(
          .recordRuntimeAdmission(
            .issuedByProcessRuntime(
              admission,
              issuer: .init()
            )),
          commandID: admissionCommandID,
          issuedAt: observedAt,
          actor: actorIdentity
        )
      } catch {
        throw JournaledProcessRuntimeError.journalWriteFailed
      }
      guard await supervisor.applyAdmissionReceipt(admission) else {
        inDoubtResourceIDs.insert(request.resourceID)
        throw JournaledProcessRuntimeError.supervisorCommitFailed
      }
      guard case .accepted(let lease, _) = admission.outcome else {
        if case .rejected(let rejection) = admission.outcome {
          throw JournaledProcessRuntimeError.admissionRejected(rejection)
        }
        preconditionFailure("RuntimeAdmissionOutcome is exhaustive")
      }

      do {
        guard await executionAuthorityMatches(lease.request) else {
          throw JournaledProcessRuntimeError.executionNotAuthorized
        }
        let launch = try await launchAuthorized(
          lease: lease,
          authorization: authorization,
          bindingReceiptID: bindingReceiptID,
          commandID: bindingCommandID
        )
        return JournaledProcessStartReceipt(
          admission: admission,
          admissionTransaction: admissionTransaction,
          launch: launch
        )
      } catch let error as ProcessGroupAdapterError {
        _ = try await releaseUnmaterializedLease(
          lease,
          receiptID: launchFailureReleaseReceiptID,
          commandID: launchFailureReleaseCommandID
        )
        throw JournaledProcessRuntimeError.nativeLaunchFailed(error)
      }
    }

    func launch(
      lease: RuntimeResourceLease,
      specification: ManagedProcessSpecification,
      bindingReceiptID: ReceiptID,
      commandID: RunCommandID
    ) async throws -> JournaledProcessLaunchReceipt {
      guard executionIOIsJournalOwned(specification) else {
        throw JournaledProcessRuntimeError.executionIOUnauthorized
      }
      guard await executionAuthorityMatches(lease.request) else {
        throw JournaledProcessRuntimeError.executionNotAuthorized
      }
      let authorization = try await authorizedSpecification(specification)
      return try await launchAuthorized(
        lease: lease,
        authorization: authorization,
        bindingReceiptID: bindingReceiptID,
        commandID: commandID
      )
    }
  #endif

  private func launchAuthorized(
    lease: RuntimeResourceLease,
    authorization: AuthorizedManagedProcessSpecification,
    bindingReceiptID: ReceiptID,
    providerLaunchReceiptID: ReceiptID? = nil,
    commandID: RunCommandID,
    providerInvocation: AuthorizedKernelProviderInvocation? = nil,
    secretCapability: KernelProviderSecretCapability? = nil
  ) async throws -> JournaledProcessLaunchReceipt {
    guard await ownershipMatches(lease) else {
      throw JournaledProcessRuntimeError.ownershipDiverged
    }

    let handle: ManagedProcessHandle
    let providerInvocationContextTransport:
      KernelProviderInvocationContextTransportReceipt?
    let providerSecretDelivery: KernelProviderSecretDeliveryReceipt?
    let providerInvocationReceipt: KernelProviderInvocationReceipt?
    let executedProviderInvocation: AuthorizedKernelProviderInvocation?
    #if DEBUG
      if let providerInvocation {
        let adapterLaunch = try await adapter.launchProvider(
          lease: lease,
          specification: authorization.specification,
          authorization: providerInvocation,
          secretCapability: secretCapability,
          candidateExecutionRoot: candidateExecutionRoot
        )
        handle = adapterLaunch.handle
        providerInvocationContextTransport =
          adapterLaunch.invocationContextTransport
        providerSecretDelivery = adapterLaunch.secretDelivery
        providerInvocationReceipt = providerInvocation.receipt
        executedProviderInvocation = providerInvocation
      } else {
        guard secretCapability == nil else {
          throw ProcessGroupAdapterError.providerCredentialUnauthorized
        }
        handle = try await adapter.launch(
          lease: lease,
          specification: authorization.specification
        )
        providerInvocationContextTransport = nil
        providerSecretDelivery = nil
        providerInvocationReceipt = nil
        executedProviderInvocation = nil
      }
    #else
      guard let providerInvocation else {
        throw ProcessGroupAdapterError.providerInvocationUnauthorized
      }
      let adapterLaunch = try await adapter.launchProvider(
        lease: lease,
        specification: authorization.specification,
        authorization: providerInvocation,
        secretCapability: secretCapability,
        candidateExecutionRoot: candidateExecutionRoot
      )
      handle = adapterLaunch.handle
      providerInvocationContextTransport =
        adapterLaunch.invocationContextTransport
      providerSecretDelivery = adapterLaunch.secretDelivery
      providerInvocationReceipt = providerInvocation.receipt
      executedProviderInvocation = providerInvocation
    #endif
    let expectedCandidateWorkingDirectory = executionProof.flatMap {
      proof in
      proof.preApplyCandidateIsolation.map {
        KernelCandidateWorkingDirectoryAttestationReceipt(
          binding: .posixSpawnFileActionsFchdir,
          deviceID: $0.deviceID,
          inode: $0.inode
        )
      }
    }
    guard let nativeSandbox = handle.externalIdentity.nativeSandboxAttestation,
      nativeSandbox.authorization == authorization.nativeSandbox,
      nativeSandbox.processID == handle.processID,
      nativeSandbox.nativeSandboxCheckResult == 1,
      nativeSandbox.gateObservedStopped,
      nativeSandbox.targetExecHandshakeSucceeded,
      nativeSandbox.candidateWorkingDirectory == expectedCandidateWorkingDirectory
    else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let observedAt = Date()
    let observedAtMonotonicNanoseconds = max(
      DispatchTime.now().uptimeNanoseconds,
      handle.externalIdentity.processStartMonotonicNanoseconds ?? 0
    )
    let binding = await supervisor.previewExternalIdentityReceipt(
      resourceID: lease.request.resourceID,
      leaseID: lease.request.leaseID,
      identity: handle.externalIdentity,
      receiptID: bindingReceiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
    )
    guard binding.accepted else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.bindingRejected
    }
    let authorizedProviderLaunch: AuthorizedKernelProviderLaunch?
    if let executedProviderInvocation {
      guard let providerLaunchReceiptID,
        let providerInvocationContextTransport
      else {
        await compensateLaunch(handle: handle)
        throw JournaledProcessRuntimeError.providerInvocationUnauthorized
      }
      do {
        authorizedProviderLaunch = try KernelProviderLaunchEvidenceIssuer()
          .issue(
            id: providerLaunchReceiptID,
            binding: binding,
            invocation: executedProviderInvocation,
            invocationContextTransport:
              providerInvocationContextTransport,
            secretDelivery: providerSecretDelivery
          )
      } catch {
        await compensateLaunch(handle: handle)
        throw JournaledProcessRuntimeError.providerInvocationUnauthorized
      }
    } else {
      guard providerLaunchReceiptID == nil,
        providerInvocationContextTransport == nil,
        providerSecretDelivery == nil
      else {
        await compensateLaunch(handle: handle)
        throw JournaledProcessRuntimeError.providerInvocationUnauthorized
      }
      authorizedProviderLaunch = nil
    }
    let providerLaunch = authorizedProviderLaunch?.receipt

    let transaction: JournalTransactionReceipt
    do {
      let command: RunCommand
      if let authorizedProviderLaunch {
        command = .recordProviderRuntimeBinding(
          authorizedProviderLaunch
        )
      } else {
        command = .recordRuntimeBinding(
          .issuedByProcessRuntime(
            binding,
            issuer: .init()
          ))
      }
      transaction = try await journal.transactAtCurrentSequence(
        command,
        commandID: commandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }

    guard await supervisor.applyExternalIdentityReceipt(binding) else {
      await compensateLaunch(handle: handle)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(lease.request.resourceID)
    return JournaledProcessLaunchReceipt(
      handle: handle,
      binding: binding,
      journalTransaction: transaction,
      executableStaging: authorization.executableStaging,
      processEnvironment: authorization.processEnvironment,
      nativeSandbox: nativeSandbox,
      processIOFiles: authorization.specification.ioFiles,
      providerLaunch: providerLaunch,
      providerInvocation: providerInvocationReceipt,
      providerInvocationContextTransport:
        providerInvocationContextTransport,
      providerSecretDelivery: providerSecretDelivery
    )
  }

  func terminate(
    lease: RuntimeResourceLease,
    releaseReceiptID: ReceiptID,
    commandID: RunCommandID,
    graceNanoseconds: UInt64
  ) async throws -> JournaledProcessReleaseReceipt {
    guard !(await isPostimageVerifierLease(lease)) else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    guard await ownershipMatches(lease) else {
      throw JournaledProcessRuntimeError.ownershipDiverged
    }

    let termination: ManagedProcessTerminationReceipt
    do {
      termination = try await adapter.terminate(
        resourceID: lease.request.resourceID,
        leaseID: lease.request.leaseID,
        graceNanoseconds: graceNanoseconds
      )
    } catch {
      try await recordCleanupFailure(
        lease: lease,
        receiptID: releaseReceiptID,
        commandID: commandID,
        error: error
      )
      throw JournaledProcessRuntimeError.terminationFailed
    }

    let observedAt = Date()
    let observedAtMonotonicNanoseconds = max(
      DispatchTime.now().uptimeNanoseconds,
      termination.exit.observedAtMonotonicNanoseconds
    )
    var release = await supervisor.previewReleaseOutcomeReceipt(
      resourceID: lease.request.resourceID,
      leaseID: lease.request.leaseID,
      receiptID: releaseReceiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
    )
    guard case .released = release.outcome else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    release.managedProcessTermination = termination

    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeRelease(
          .issuedByProcessRuntime(
            release,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }

    guard await supervisor.applyReleaseOutcomeReceipt(release) else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(lease.request.resourceID)
    return JournaledProcessReleaseReceipt(
      termination: termination,
      release: release,
      journalTransaction: transaction
    )
  }

  /// Joins a naturally completed owned process group, then publishes its
  /// exact native exit before releasing supervisor ownership. If the join or
  /// journal write fails, logical ownership remains live and no occurrence
  /// can be credited from the uncommitted exit.
  func joinAndRelease(
    lease: RuntimeResourceLease,
    releaseReceiptID: ReceiptID,
    commandID: RunCommandID,
    timeoutNanoseconds: UInt64
  ) async throws -> JournaledProcessNaturalReleaseReceipt {
    guard !(await isPostimageVerifierLease(lease)) else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    guard await ownershipMatches(lease) else {
      throw JournaledProcessRuntimeError.ownershipDiverged
    }

    let exit: ManagedProcessExitReceipt
    do {
      exit = try await adapter.join(
        resourceID: lease.request.resourceID,
        leaseID: lease.request.leaseID,
        timeoutNanoseconds: timeoutNanoseconds
      )
    } catch {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.naturalExitTimedOut
    }

    let observedAt = Date()
    let observedAtMonotonicNanoseconds = max(
      DispatchTime.now().uptimeNanoseconds,
      exit.observedAtMonotonicNanoseconds
    )
    var release = await supervisor.previewReleaseOutcomeReceipt(
      resourceID: lease.request.resourceID,
      leaseID: lease.request.leaseID,
      receiptID: releaseReceiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
    )
    guard case .released = release.outcome else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    release.managedProcessExit = exit

    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeRelease(
          .issuedByProcessRuntime(
            release,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyReleaseOutcomeReceipt(release) else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(lease.request.resourceID)
    return JournaledProcessNaturalReleaseReceipt(
      exit: exit,
      release: release,
      journalTransaction: transaction
    )
  }

  /// Resolves the post-binding lease exclusively from the exact journaled
  /// provider launch. The admission receipt intentionally predates native
  /// identity binding and therefore must never be replayed as current
  /// ownership during completion.
  func joinAndReleaseProvider(
    start: JournaledProcessStartReceipt,
    releaseReceiptID: ReceiptID,
    commandID: RunCommandID,
    timeoutNanoseconds: UInt64
  ) async throws -> JournaledProcessNaturalReleaseReceipt {
    guard let providerLaunch = start.launch.providerLaunch,
      await journal.providerLaunchReceipt(
        transaction: start.launch.journalTransaction
      ) == providerLaunch,
      providerLaunch.bindingReceiptID == start.launch.binding.id,
      start.launch.binding.accepted,
      start.launch.binding.identity == start.launch.handle.externalIdentity,
      case .accepted(let admittedLease, _) = start.admission.outcome,
      admittedLease.request.resourceID == providerLaunch.resourceID,
      admittedLease.request.leaseID == providerLaunch.leaseID,
      let boundLease = await journal.runtimeLease(
        resourceID: providerLaunch.resourceID
      )
    else {
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    var expectedBoundLease = admittedLease
    expectedBoundLease.request.externalIdentity =
      start.launch.handle.externalIdentity
    guard boundLease == expectedBoundLease else {
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    return try await joinAndRelease(
      lease: boundLease,
      releaseReceiptID: releaseReceiptID,
      commandID: commandID,
      timeoutNanoseconds: timeoutNanoseconds
    )
  }

  /// Parses only retained bytes from the exact journal-owned stdout/stderr
  /// files after a journaled successful natural exit. The resulting event is
  /// evidence of a worker proposal, not authority to record execution.
  func parseReleasedWorkerResult(
    start: JournaledProcessStartReceipt,
    release: JournaledProcessNaturalReleaseReceipt,
    invocationDigest: ContentDigest,
    requestNonce: ContentDigest,
    receiptID: ReceiptID,
    commandID: RunCommandID
  ) async throws -> JournaledWorkerResultParseReceipt {
    if let providerLaunch = start.launch.providerLaunch {
      guard
        await journal.providerLaunchReceipt(
          transaction: start.launch.journalTransaction
        ) == providerLaunch,
        providerLaunch.invocation.invocationDigest == invocationDigest,
        providerLaunch.invocation.requestNonce == requestNonce,
        start.launch.providerInvocation == providerLaunch.invocation,
        start.launch.providerInvocationContextTransport ==
          providerLaunch.invocationContextTransport,
        start.launch.providerSecretDelivery == providerLaunch.secretDelivery
      else {
        throw JournaledProcessRuntimeError.workerResultUnauthorized
      }
    }
    guard let executionProof,
      executionProof.attemptID == start.admission.request.attemptID,
      start.launch.handle == release.exit.handle,
      start.launch.processIOFiles.map({ executionIOIsJournalOwned($0) }) == true,
      let io = start.launch.processIOFiles,
      let stdoutName = io.standardOutputFileName,
      let stderrName = io.standardErrorFileName,
      await journal.runtimeBindingReceipt(
        transaction: start.launch.journalTransaction
      ) == start.launch.binding,
      await journal.runtimeReleaseReceipt(
        transaction: release.journalTransaction
      ) == release.release,
      release.release.managedProcessExit == release.exit,
      release.release.managedProcessTermination == nil
    else {
      throw JournaledProcessRuntimeError.workerResultUnauthorized
    }

    let expectation = KernelWorkerResultParseExpectation(
      runID: start.launch.handle.runID,
      attemptID: executionProof.attemptID,
      resourceID: start.launch.handle.resourceID,
      leaseID: start.launch.handle.leaseID,
      bindingReceiptID: start.launch.binding.id,
      releaseReceiptID: release.release.id,
      invocationDigest: invocationDigest,
      requestNonce: requestNonce,
      nativeExit: release.exit
    )
    if let existingTransaction = await journal.transactionReceipt(
      commandID: commandID
    ),
      let existing = await journal.workerResultParseReceipt(
        transaction: existingTransaction
      )
    {
      guard existing.id == receiptID,
        existing.runID == expectation.runID,
        existing.attemptID == expectation.attemptID,
        existing.resourceID == expectation.resourceID,
        existing.leaseID == expectation.leaseID,
        existing.bindingReceiptID == expectation.bindingReceiptID,
        existing.releaseReceiptID == expectation.releaseReceiptID,
        existing.invocationDigest == invocationDigest,
        existing.requestNonce == requestNonce,
        existing.nativeExit == release.exit
      else {
        throw JournaledProcessRuntimeError.workerResultUnauthorized
      }
      return JournaledWorkerResultParseReceipt(
        parse: existing,
        journalTransaction: existingTransaction
      )
    }

    let authorized: KernelAuthorizedWorkerResultParse
    do {
      authorized = try KernelWorkerResultParser().parseAuthorizedRetainedFiles(
        directoryPath: io.directoryPath,
        standardOutputFileName: stdoutName,
        standardErrorFileName: stderrName,
        expectation: expectation,
        receiptID: receiptID
      )
    } catch {
      throw JournaledProcessRuntimeError.workerResultParseFailed
    }
    let parsed = authorized.receipt
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordWorkerResultParse(authorized),
        commandID: commandID,
        issuedAt: Date(),
        actor: actorIdentity
      )
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard
      await journal.workerResultParseReceipt(
        transaction: transaction
      ) == parsed
    else {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    return JournaledWorkerResultParseReceipt(
      parse: parsed,
      journalTransaction: transaction
    )
  }

  /// Closes the active attempt only by asking the reducer to map the exact
  /// journaled parser receipt. No caller-selected disposition or reason can
  /// cross this boundary.
  func deriveReleasedWorkerExecution(
    parse: JournaledWorkerResultParseReceipt,
    receiptID: ReceiptID,
    commandID: RunCommandID
  ) async throws -> JournaledExecutionDerivationReceipt {
    guard
      await journal.workerResultParseReceipt(
        transaction: parse.journalTransaction
      ) == parse.parse
    else {
      throw JournaledProcessRuntimeError.workerResultUnauthorized
    }
    if let existingTransaction = await journal.transactionReceipt(commandID: commandID),
      let existing = await journal.executionDerivationReceipt(
        transaction: existingTransaction
      )
    {
      guard existing.id == receiptID,
        existing.runID == parse.parse.runID,
        existing.attemptID == parse.parse.attemptID,
        existing.source == .workerResultParse(parse.parse.id)
      else {
        throw JournaledProcessRuntimeError.workerResultUnauthorized
      }
      return JournaledExecutionDerivationReceipt(
        execution: existing,
        journalTransaction: existingTransaction
      )
    }
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .deriveExecution(
          receiptID: receiptID,
          source: .workerResultParse(parse.parse.id)
        ),
        commandID: commandID,
        issuedAt: Date(),
        actor: actorIdentity
      )
    } catch {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard
      let execution = await journal.executionDerivationReceipt(
        transaction: transaction
      ), execution.id == receiptID,
      execution.source == .workerResultParse(parse.parse.id)
    else {
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    return JournaledExecutionDerivationReceipt(
      execution: execution,
      journalTransaction: transaction
    )
  }

  /// Proves the completed worker no longer owns native or logical resources
  /// and that every provenance receipt is the exact journaled event. This is
  /// the fail-closed gate before the session may read candidate bytes.
  func authorizesCompletedCandidateCapture(
    _ completion: KernelProductionProviderCompletionReceipt
  ) async -> Bool {
    guard completion.execution.execution.disposition == .completed,
      completion.execution.execution.runID == journal.runID,
      completion.execution.execution.source == .workerResultParse(completion.parse.parse.id),
      completion.execution.execution.sourceEvidenceDigest
        == completion.parse.parse.proposedResultDigest,
      completion.parse.parse.nativeExit == completion.release.exit,
      completion.parse.parse.releaseReceiptID == completion.release.release.id,
      completion.release.release.managedProcessExit == completion.release.exit,
      completion.release.release.managedProcessTermination == nil,
      await journal.runtimeReleaseReceipt(
        transaction: completion.release.journalTransaction
      ) == completion.release.release,
      await journal.workerResultParseReceipt(
        transaction: completion.parse.journalTransaction
      ) == completion.parse.parse,
      await journal.executionDerivationReceipt(
        transaction: completion.execution.journalTransaction
      ) == completion.execution.execution
    else {
      return false
    }
    let adapterProjection = await adapter.projection()
    let supervisorProjection = await supervisor.projection()
    return adapterProjection.liveHandles.isEmpty
      && inDoubtResourceIDs.isEmpty
      && supervisorProjection.liveLeases.isEmpty
      && supervisorProjection.queuedLeases.isEmpty
      && supervisorProjection.failedReleases.isEmpty
  }

  func recordCompletedCandidateCapture(
    _ authority: AuthorizedWorkspaceCompletedCandidateCapture,
    commandID: RunCommandID
  ) async throws -> JournalTransactionReceipt {
    try await journal.recordCompletedCandidateCapture(
      authority,
      commandID: commandID
    )
  }

  /// Reconciles a journaled process lease without scanning by executable
  /// name. Only an exact OS PID/start-time/process-group match may reattach.
  /// An unbound or unverifiable lease stays live and in doubt. A proven
  /// absent process is released through the journal before supervisor commit.
  func reconcile(
    resourceID: OwnedResourceID,
    absentReleaseReceiptID: ReceiptID,
    absentReleaseCommandID: RunCommandID
  ) async throws -> JournaledProcessRecoveryOutcome {
    guard let journalLease = await journal.runtimeLease(resourceID: resourceID),
      let supervisorLease = await supervisor.projection().liveLeases.first(where: {
        $0.request.resourceID == resourceID
      }),
      supervisorLease == journalLease
    else {
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    guard journalLease.request.externalIdentity != nil else {
      inDoubtResourceIDs.insert(resourceID)
      await supervisor.markReleaseFailed(resourceID: resourceID)
      return .unboundAdmission(journalLease)
    }
    guard !(await isPostimageVerifierLease(journalLease)) else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }

    do {
      let handle = try await adapter.recover(lease: journalLease)
      inDoubtResourceIDs.remove(resourceID)
      return .recovered(handle)
    } catch ProcessGroupAdapterError.recoveryProcessAbsent {
      let release = try await releaseUnmaterializedLease(
        journalLease,
        receiptID: absentReleaseReceiptID,
        commandID: absentReleaseCommandID
      )
      return .absentReleased(release)
    } catch ProcessGroupAdapterError.recoveryIdentityMissing {
      inDoubtResourceIDs.insert(resourceID)
      await supervisor.markReleaseFailed(resourceID: resourceID)
      return .unverifiableIdentity(journalLease)
    } catch ProcessGroupAdapterError.recoveryIdentityMismatch {
      inDoubtResourceIDs.insert(resourceID)
      await supervisor.markReleaseFailed(resourceID: resourceID)
      return .identityMismatch(journalLease)
    } catch {
      throw error
    }
  }

  /// Read-only application-termination preflight. The session invokes this
  /// for every retained run before any run is moved into draining, preventing
  /// partial multi-session shutdown when one plan has no exact runtime owner.
  func applicationTerminationCleanupIsExecutable() async -> Bool {
    let supervisorProjection = await supervisor.projection()
    let journalState = await journal.state
    let plan = await supervisor.cleanupPlan()
    guard inDoubtResourceIDs.isEmpty,
      supervisorProjection.failedReleases.isEmpty,
      supervisorProjection.queuedLeases.isEmpty,
      supervisorProjection.liveLeases.count == plan.count,
      Dictionary(
        uniqueKeysWithValues: supervisorProjection.liveLeases.map {
          ($0.request.resourceID, $0)
        }
      ) == journalState.runtimeLiveLeases
    else {
      return false
    }
    let adapterHandles = await adapter.projection().liveHandles
    return zip(plan, supervisorProjection.liveLeases).allSatisfy {
      action, lease in
      guard Self.cleanupAction(action, matches: lease) else {
        return false
      }
      switch action {
      case .requestGracefulTermination:
        let identity = lease.request.externalIdentity
        return lease.request.kind == .processTree
          && identity?.processID.map({ $0 > 0 }) == true
          && identity?.processStartSystemNanoseconds != nil
      case .awaitJoin:
        return lease.request.kind == .processTree
          && adapterHandles.contains(where: {
            $0.resourceID == lease.request.resourceID
              && $0.leaseID == lease.request.leaseID
              && $0.externalIdentity == lease.request.externalIdentity
          })
      case .detachBorrowed:
        return lease.request.externalIdentity?.stableDigest.rawValue.isEmpty
          == false
      }
    }
  }

  /// Executes only the exact cleanup plan retained by the now-draining
  /// supervisor. Owned process trees are recovered by PID/start identity and
  /// terminated as complete process groups; already-absent identities receive
  /// a durable absence release; borrowed resources are detached logically;
  /// join-only resources must still have their exact in-memory handle. Any
  /// mismatch records or retains failure and prevents quiescence.
  func executeApplicationTerminationCleanup(
    expectedPlan: [RuntimeCleanupAction],
    requestNonce: String,
    origin: JournaledApplicationTerminationCleanupOrigin
  ) async throws -> JournaledApplicationTerminationCleanupReceipt {
    guard requestNonce == requestNonce.lowercased(),
      UUID(uuidString: requestNonce) != nil,
      await applicationTerminationCleanupIsExecutable()
    else {
      throw JournaledProcessRuntimeError
        .applicationTerminationCleanupUnavailable
    }
    guard await supervisor.cleanupPlan() == expectedPlan else {
      throw JournaledProcessRuntimeError
        .applicationTerminationCleanupPlanChanged
    }

    var releaseReceiptIDs: [ReceiptID] = []
    for (index, action) in expectedPlan.enumerated() {
      let projection = await supervisor.projection()
      guard let lease = projection.liveLeases.first(where: {
        Self.cleanupAction(action, matches: $0)
      }) else {
        throw JournaledProcessRuntimeError
          .applicationTerminationCleanupPlanChanged
      }
      let prefix = "\(origin.commandPrefix)-\(requestNonce)-cleanup-\(index)"
      switch action {
      case .detachBorrowed:
        let released = try await releaseUnmaterializedLease(
          lease,
          receiptID: ReceiptID("\(prefix)-detach-release"),
          commandID: RunCommandID("\(prefix)-detach-release")
        )
        releaseReceiptIDs.append(released.release.id)

      case .awaitJoin:
        let released = try await joinAndRelease(
          lease: lease,
          releaseReceiptID: ReceiptID("\(prefix)-join-release"),
          commandID: RunCommandID("\(prefix)-join-release"),
          timeoutNanoseconds: 250_000_000
        )
        releaseReceiptIDs.append(released.release.id)

      case .requestGracefulTermination:
        if await isPostimageVerifierLease(lease) {
          let released = try await cleanupPostimageVerifierForApplicationTermination(
            lease: lease,
            releaseReceiptID: ReceiptID("\(prefix)-verifier-release"),
            releaseCommandID: RunCommandID("\(prefix)-verifier-release")
          )
          releaseReceiptIDs.append(released.release.id)
          continue
        }
        let recovered = try await reconcile(
          resourceID: lease.request.resourceID,
          absentReleaseReceiptID: ReceiptID("\(prefix)-absent-release"),
          absentReleaseCommandID: RunCommandID("\(prefix)-absent-release")
        )
        switch recovered {
        case .recovered:
          let released = try await terminate(
            lease: lease,
            releaseReceiptID: ReceiptID("\(prefix)-terminate-release"),
            commandID: RunCommandID("\(prefix)-terminate-release"),
            graceNanoseconds: 100_000_000
          )
          releaseReceiptIDs.append(released.release.id)
        case .absentReleased(let released):
          releaseReceiptIDs.append(released.release.id)
        case .unboundAdmission, .unverifiableIdentity, .identityMismatch:
          throw JournaledProcessRuntimeError
            .applicationTerminationCleanupUnavailable
        }
      }
    }

    let remaining = await supervisor.cleanupPlan()
    guard remaining.isEmpty else {
      throw JournaledProcessRuntimeError
        .applicationTerminationCleanupIncomplete(remaining.count)
    }
    return JournaledApplicationTerminationCleanupReceipt(
      runID: journal.runID,
      requestNonce: requestNonce,
      origin: origin,
      plannedActions: expectedPlan,
      releaseReceiptIDs: releaseReceiptIDs,
      remainingActions: remaining
    )
  }

  func projection() async -> JournaledProcessRuntimeProjection {
    JournaledProcessRuntimeProjection(
      adapter: await adapter.projection(),
      inDoubtResourceIDs: inDoubtResourceIDs
    )
  }

  private nonisolated static func cleanupAction(
    _ action: RuntimeCleanupAction,
    matches lease: RuntimeResourceLease
  ) -> Bool {
    switch action {
    case .awaitJoin(let resourceID, let leaseID):
      return lease.request.resourceID == resourceID
        && lease.request.leaseID == leaseID
        && lease.request.ownership == .owned
        && lease.request.releasePolicy == .join
    case .requestGracefulTermination(let resourceID, let leaseID):
      return lease.request.resourceID == resourceID
        && lease.request.leaseID == leaseID
        && lease.request.ownership == .owned
        && lease.request.releasePolicy == .gracefulThenTerminate
    case .detachBorrowed(let resourceID, let leaseID):
      return lease.request.resourceID == resourceID
        && lease.request.leaseID == leaseID
        && lease.request.ownership == .borrowed
        && lease.request.releasePolicy == .detachOnly
    }
  }

  private func ownershipMatches(_ lease: RuntimeResourceLease) async -> Bool {
    let journalLease = await journal.runtimeLease(
      resourceID: lease.request.resourceID
    )
    let supervisorProjection = await supervisor.projection()
    let supervisorLease = supervisorProjection.liveLeases.first {
      $0.request.resourceID == lease.request.resourceID
    }
    return journalLease == lease && supervisorLease == lease
  }

  private func isPostimageVerifierLease(
    _ lease: RuntimeResourceLease
  ) async -> Bool {
    let state = await journal.state
    return (state.postimageVerifierLaunchReceipts ?? [:]).values.contains {
      $0.resourceID == lease.request.resourceID
        && $0.leaseID == lease.request.leaseID
    }
  }

  /// A runtime lease is capacity, not execution authority. Productive OS
  /// work may materialize only while the journal's reducer projection names
  /// the exact causal attempt as active and executing.
  private func executionAuthorityMatches(_ request: RuntimeLeaseRequest) async -> Bool {
    guard let executionProof,
      request.runID == journal.runID,
      executionProof.runID == request.runID,
      request.purpose == .productive,
      let attemptID = request.attemptID,
      executionProof.attemptID == attemptID
    else {
      return false
    }
    return await executionProofIsActive()
  }

  private func executionProofIsActive() async -> Bool {
    guard let executionProof,
      executionProof.runID == journal.runID,
      executionProof.activationActor == actorIdentity,
      let journalAttempt = await journal.attemptStart(
        transaction: executionProof.activationTransaction
      ),
      journalAttempt.id == executionProof.attemptID,
      journalAttempt.nodeID == executionProof.nodeID,
      journalAttempt.strategyFingerprint == executionProof.strategyFingerprint
    else {
      return false
    }
    let state = await journal.state
    guard state.phase == .executing,
      state.contract?.executionProfile?.worker == executionProof.workerExecutionProfile,
      state.activeAttemptID == executionProof.attemptID,
      let attempt = state.attempts[executionProof.attemptID],
      attempt == journalAttempt,
      attempt.disposition == nil,
      let admission = state.convergenceGovernor?.admittedRequest(
        for: executionProof.attemptID
      ),
      admission.strategy.fingerprint == attempt.strategyFingerprint,
      admission.strategy.requirementIDs == attempt.requirementIDs
    else {
      return false
    }
    return true
  }

  private func externalDependencyObservationReadinessIsActive(
    _ readiness: AuthorizedExternalDependencyObservationLaunchReadiness
  ) async -> Bool {
    let invocation = readiness.invocation
    let receipt = invocation.receipt
    guard receipt.runID == journal.runID,
      receipt.observer == actorIdentity,
      readiness.residentMemoryEnforcement.authorizes(
        externalDependencyActivation: receipt
      ),
      invocation.requestArtifact.receipt == receipt.requestArtifact,
      invocation.activationTransaction.startingSequence == receipt.sourceJournalSequence + 1,
      invocation.activationTransaction.endingSequence
        == invocation.activationTransaction.startingSequence,
      await journal.externalDependencyObservationActivationReceipt(
        transaction: invocation.activationTransaction
      ) == receipt
    else {
      return false
    }
    let state = await journal.state
    guard state.phase == .executing,
      state.activeAttemptID == receipt.attemptID,
      state.attempts[receipt.attemptID]?.disposition == nil,
      (state.externalDependencyObservationActivationReceipts ?? [:])[
        receipt.id
      ] == receipt,
      !(state.externalDependencyObservationRuntimeLaunchReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == receipt.id
        }),
      !(state.externalDependencyObservationLaunchVetoReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == receipt.id
        }),
      !(state.externalDependencyReceipts ?? [:]).values.contains(
        where: {
          $0.attemptID == receipt.attemptID
            && $0.dependencyID == receipt.dependencyID
        }
      )
    else {
      return false
    }
    return true
  }

  private static func externalDependencyObservationRuntimeRequestIsValid(
    _ request: ExternalDependencyObservationRuntimeRequest
  ) -> Bool {
    let receiptIDs = [
      request.admissionReceiptID,
      request.bindingReceiptID,
      request.launchReceiptID,
      request.launchFailureReleaseReceiptID,
    ]
    let commandIDs = [
      request.admissionCommandID,
      request.bindingCommandID,
      request.launchFailureReleaseCommandID,
    ]
    return !request.leaseID.rawValue.isEmpty
      && !request.resourceID.rawValue.isEmpty
      && !request.standardOutputFileName.isEmpty
      && !request.standardErrorFileName.isEmpty
      && request.standardOutputFileName != request.standardErrorFileName
      && receiptIDs.allSatisfy { !$0.rawValue.isEmpty }
      && Set(receiptIDs).count == receiptIDs.count
      && commandIDs.allSatisfy { !$0.rawValue.isEmpty }
      && Set(commandIDs).count == commandIDs.count
  }

  private static func externalDependencyObservationCompletionRequestIsValid(
    _ request: ExternalDependencyObservationCompletionRequest
  ) -> Bool {
    !request.releaseReceiptID.rawValue.isEmpty
      && !request.releaseCommandID.rawValue.isEmpty
      && !request.observationCommandID.rawValue.isEmpty
      && request.releaseCommandID != request.observationCommandID
  }

  private func externalDependencyObservationCompletionContext(
    launchReceiptID: ReceiptID
  ) async throws -> ExternalDependencyObservationCompletionContext {
    guard !launchReceiptID.rawValue.isEmpty else {
      throw JournaledProcessRuntimeError.invalidSpecification
    }
    let state = await journal.state
    guard state.phase == .executing,
      let launch = state.externalDependencyObservationRuntimeLaunchReceipts?[
        launchReceiptID
      ],
      launch.runID == journal.runID,
      launch.observer == actorIdentity,
      state.activeAttemptID == launch.attemptID,
      state.attempts[launch.attemptID]?.disposition == nil,
      let activation = state.externalDependencyObservationActivationReceipts?[
        launch.activationReceiptID
      ],
      let binding = state.runtimeBindingReceipts[
        launch.bindingReceiptID
      ],
      let dependency = state.contract?.externalDependencies?.first(
        where: { $0.id == launch.dependencyID }
      ),
      state.contract?.externalDependencies?.filter({
        $0.id == launch.dependencyID
      }).count == 1,
      let probe = dependency.executableProbe,
      ExternalDependencyObservationActivationCompiler.receipt(
        activation,
        matches: probe
      ),
      ExternalDependencyObservationRuntimeLaunchCompiler.launch(
        launch,
        matches: activation,
        binding: binding
      ),
      activation.observer == actorIdentity
    else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationUnauthorized
    }
    let liveLease = state.runtimeLiveLeases[launch.resourceID]
    if let liveLease {
      guard liveLease.request.runID == launch.runID,
        liveLease.request.resourceID == launch.resourceID,
        liveLease.request.leaseID == launch.leaseID,
        liveLease.request.attemptID == launch.attemptID,
        liveLease.request.kind == .processTree,
        liveLease.request.purpose == .productive,
        liveLease.request.ownership == .owned,
        liveLease.request.releasePolicy == .gracefulThenTerminate,
        liveLease.request.externalIdentity == binding.identity
      else {
        throw JournaledProcessRuntimeError.ownershipDiverged
      }
    }
    return ExternalDependencyObservationCompletionContext(
      activation: activation,
      probe: probe,
      launch: launch,
      binding: binding,
      liveLease: liveLease
    )
  }

  private func postimageVerifierInvocationIsActive(
    _ invocation: AuthorizedKernelPostimageVerifierInvocation,
    executionActor: ActorIdentity
  ) async -> Bool {
    let receipt = invocation.receipt
    guard receipt.runID == journal.runID,
      receipt.verifier == executionActor,
      invocation.candidateInput.receipt == receipt.candidateMaterialization,
      invocation.activationTransaction.startingSequence == receipt.sourceJournalSequence + 1,
      invocation.activationTransaction.endingSequence
        == invocation.activationTransaction.startingSequence,
      await journal.postimageVerifierActivationReceipt(
        transaction: invocation.activationTransaction
      ) == receipt
    else {
      return false
    }
    let state = await journal.state
    guard state.phase == .evaluating,
      let integration = state.integrationTransactions[
        receipt.integrationTransactionID
      ],
      integration.phase == .appliedUnverified,
      integration.applyReceipt?.id == receipt.applyReceiptID,
      state.attempts[receipt.attemptID]?
        .disposition?.canEnterVerification == true,
      !(state.postimageVerifierLaunchReceipts ?? [:]).values
        .contains(where: {
          $0.activationReceiptID == receipt.id
        }),
      !(state.postimageVerifierLaunchVetoReceipts ?? [:]).values
        .contains(where: {
          $0.activationReceiptID == receipt.id
        })
    else {
      return false
    }
    return true
  }

  private static func postimageVerifierRuntimeRequestIsValid(
    _ request: KernelPostimageVerifierRuntimeRequest
  ) -> Bool {
    let receiptIDs = [
      request.admissionReceiptID,
      request.bindingReceiptID,
      request.launchReceiptID,
      request.launchFailureReleaseReceiptID,
      request.launchVetoReceiptID,
    ]
    let commandIDs = [
      request.admissionCommandID,
      request.bindingCommandID,
      request.launchFailureReleaseCommandID,
      request.launchVetoCommandID,
    ]
    return !request.leaseID.rawValue.isEmpty
      && !request.resourceID.rawValue.isEmpty
      && !request.standardOutputFileName.isEmpty
      && !request.standardErrorFileName.isEmpty
      && request.standardOutputFileName != request.standardErrorFileName
      && receiptIDs.allSatisfy { !$0.rawValue.isEmpty }
      && Set(receiptIDs).count == receiptIDs.count
      && commandIDs.allSatisfy { !$0.rawValue.isEmpty }
      && Set(commandIDs).count == commandIDs.count
  }

  private func postimageVerifierCompletionContext(
    launchReceiptID: ReceiptID,
    executionActor: ActorIdentity? = nil
  ) async throws -> PostimageVerifierCompletionContext {
    let expectedVerifier = executionActor ?? actorIdentity
    let state = await journal.state
    guard let launch = state.postimageVerifierLaunchReceipts?[launchReceiptID],
      let activation = state.postimageVerifierActivationReceipts?[
        launch.activationReceiptID
      ],
      let contract = state.contract,
      let recipes = contract.requirementEvidenceRecipes,
      let recipe = recipes.first(where: {
        $0.id == activation.evidenceRecipeID
      }),
      recipes.filter({
        $0.id == activation.evidenceRecipeID
      }).count == 1,
      let probe = recipe.executableProbe,
      KernelPostimageVerifierActivationCompiler.receipt(
        activation,
        matches: probe
      ),
      let binding = state.runtimeBindingReceipts[
        launch.bindingReceiptID
      ],
      let lease = state.runtimeLiveLeases[launch.resourceID],
      lease.request.leaseID == launch.leaseID,
      lease.request.externalIdentity == binding.identity,
      activation.verifier == expectedVerifier
    else {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    let handle: ManagedProcessHandle?
    do {
      handle = try await adapter.recover(lease: lease)
    } catch ProcessGroupAdapterError.recoveryProcessAbsent {
      handle = nil
    } catch {
      throw JournaledProcessRuntimeError.postimageVerifierUnauthorized
    }
    return PostimageVerifierCompletionContext(
      activation: activation,
      probe: probe,
      launch: launch,
      binding: binding,
      lease: lease,
      handle: handle
    )
  }

  private func postimageVerifierContextIsActive(
    _ context: PostimageVerifierCompletionContext
  ) async -> Bool {
    let launch = context.launch
    guard
      KernelPostimageVerifierActivationCompiler.launch(
        launch,
        matches: context.activation,
        binding: context.binding
      ),
      context.lease.request.runID == journal.runID,
      context.lease.request.resourceID == launch.resourceID,
      context.lease.request.leaseID == launch.leaseID,
      context.lease.request.externalIdentity == context.binding.identity,
      context.binding.id == launch.bindingReceiptID
    else {
      return false
    }
    if let handle = context.handle {
      guard handle.runID == journal.runID,
        handle.resourceID == launch.resourceID,
        handle.leaseID == launch.leaseID,
        context.binding.identity == handle.externalIdentity
      else {
        return false
      }
    }
    let state = await journal.state
    guard state.phase == .evaluating,
      context.activation.verifier == actorIdentity,
      state.postimageVerifierActivationReceipts?[context.activation.id] == context.activation,
      state.postimageVerifierLaunchReceipts?[launch.id] == launch,
      state.runtimeBindingReceipts[launch.bindingReceiptID] == context.binding,
      let lease = state.runtimeLiveLeases[launch.resourceID],
      lease.request.leaseID == launch.leaseID,
      lease.request.attemptID == launch.attemptID,
      lease.request.kind == .processTree,
      lease.request.purpose == .productive,
      lease.request.ownership == .owned,
      !(state.runtimeReleaseReceipts.values.contains(where: {
        $0.resourceID == launch.resourceID
          && $0.leaseID == launch.leaseID
      }))
    else {
      return false
    }
    return true
  }

  private func postimageVerifierContextIsOwnedForCleanup(
    _ context: PostimageVerifierCompletionContext
  ) async -> Bool {
    let launch = context.launch
    guard KernelPostimageVerifierActivationCompiler.launch(
      launch,
      matches: context.activation,
      binding: context.binding
    ),
      context.lease.request.runID == journal.runID,
      context.lease.request.resourceID == launch.resourceID,
      context.lease.request.leaseID == launch.leaseID,
      context.lease.request.kind == .processTree,
      context.lease.request.purpose == .productive,
      context.lease.request.ownership == .owned,
      context.lease.request.releasePolicy == .gracefulThenTerminate,
      context.lease.request.externalIdentity == context.binding.identity,
      context.binding.id == launch.bindingReceiptID
    else {
      return false
    }
    if let handle = context.handle {
      guard handle.runID == journal.runID,
        handle.resourceID == launch.resourceID,
        handle.leaseID == launch.leaseID,
        handle.externalIdentity == context.binding.identity
      else {
        return false
      }
    }
    let state = await journal.state
    guard state.phase == .evaluating || state.phase == .stopRequested,
      state.postimageVerifierActivationReceipts?[context.activation.id]
        == context.activation,
      state.postimageVerifierLaunchReceipts?[launch.id] == launch,
      state.runtimeBindingReceipts[launch.bindingReceiptID]
        == context.binding,
      state.runtimeLiveLeases[launch.resourceID] == context.lease,
      !(state.runtimeReleaseReceipts.values.contains(where: {
        $0.resourceID == launch.resourceID
          && $0.leaseID == launch.leaseID
      }))
    else {
      return false
    }
    return true
  }

  /// Recovery cannot recreate an exit status after the kernel has already
  /// reaped an exact PID. It can, however, prove that the journaled
  /// PID/start identity is absent, validate whatever bounded output remains,
  /// and atomically release ownership with a permanently fail-red receipt.
  private func completeAbsentPostimageVerifier(
    context: PostimageVerifierCompletionContext,
    processStart: UInt64,
    wallDeadline: UInt64,
    request: KernelPostimageVerifierCompletionRequest
  ) async throws -> JournaledPostimageVerifierCompletionReceipt {
    let output:
      (
        RetainedPostimageVerifierOutput,
        RetainedPostimageVerifierOutput
      )?
    var outputFailureDigest: ContentDigest?
    do {
      output = try retainedPostimageVerifierOutput(context.launch)
    } catch {
      output = nil
      outputFailureDigest = containmentFailureDigest(error)
    }
    let observedAt = Date()
    let observedAtMonotonic = max(
      DispatchTime.now().uptimeNanoseconds,
      processStart
    )
    let parse = resultParseEvidence(context: context, output: output)
    let mapping = resultMappingEvidence(
      context: context,
      disposition: .recoveryProcessAbsent,
      nativeExit: nil,
      parse: parse.receipt
    )
    let result = postimageResultEvidence(
      context: context,
      releaseReceiptID: request.releaseReceiptID,
      output: output,
      parse: parse.receipt,
      mapping: mapping.receipt,
      completedAt: observedAt
    )
    let containment = KernelPostimageVerifierContainmentReceipt(
      schemaVersion: 4,
      runID: context.activation.runID,
      activationReceiptID: context.activation.id,
      launchReceiptID: context.launch.id,
      bindingReceiptID: context.launch.bindingReceiptID,
      resourceID: context.launch.resourceID,
      leaseID: context.launch.leaseID,
      processStartMonotonicNanoseconds: processStart,
      wallDeadlineMonotonicNanoseconds: wallDeadline,
      maximumOutputFileBytes: context.activation.resourceLimits
        .maximumCapturedOutputBytes / 2,
      resourceLimits: context.activation.resourceLimits,
      disposition: .recoveryProcessAbsent,
      standardOutput: output?.0.receipt,
      standardError: output?.1.receipt,
      failureReasonDigest: outputFailureDigest,
      resultParse: parse.receipt,
      resultParseFailureDigest: parse.failureDigest,
      resultMapping: mapping.receipt,
      resultMappingFailureDigest: mapping.failureDigest,
      postimageResult: result.receipt,
      postimageResultFailureDigest: result.failureDigest,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonic
    )
    return try await publishPostimageVerifierRelease(
      context: context,
      containment: containment,
      naturalExit: nil,
      termination: nil,
      request: request
    )
  }

  private func publishPostimageVerifierRelease(
    context: PostimageVerifierCompletionContext,
    containment: KernelPostimageVerifierContainmentReceipt,
    naturalExit: ManagedProcessExitReceipt?,
    termination: ManagedProcessTerminationReceipt?,
    request: KernelPostimageVerifierCompletionRequest
  ) async throws -> JournaledPostimageVerifierCompletionReceipt {
    let resourceID = context.launch.resourceID
    let leaseID = context.launch.leaseID
    var release = await supervisor.previewReleaseOutcomeReceipt(
      resourceID: resourceID,
      leaseID: leaseID,
      receiptID: request.releaseReceiptID,
      observedAt: containment.observedAt,
      observedAtMonotonicNanoseconds:
        containment.observedAtMonotonicNanoseconds
    )
    guard case .released = release.outcome else {
      inDoubtResourceIDs.insert(resourceID)
      await supervisor.markReleaseFailed(resourceID: resourceID)
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    release.managedProcessExit = naturalExit
    release.managedProcessTermination = termination
    release.postimageVerifierContainment = containment

    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeRelease(
          .issuedByProcessRuntime(
            release,
            issuer: .init()
          )),
        commandID: request.releaseCommandID,
        issuedAt: containment.observedAt,
        actor: actorIdentity
      )
    } catch {
      inDoubtResourceIDs.insert(resourceID)
      await supervisor.markReleaseFailed(resourceID: resourceID)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyReleaseOutcomeReceipt(release) else {
      inDoubtResourceIDs.insert(resourceID)
      await supervisor.markReleaseFailed(resourceID: resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(resourceID)
    let authorizedResult: AuthorizedKernelPostimageVerifierResult?
    if let result = containment.postimageResult,
      await journal.runtimeReleaseReceipt(transaction: transaction) == release
    {
      authorizedResult = .issuedByProcessRuntime(
        receipt: result,
        releaseTransaction: transaction,
        issuer: .init()
      )
    } else {
      authorizedResult = nil
    }
    return JournaledPostimageVerifierCompletionReceipt(
      containment: containment,
      naturalExit: naturalExit,
      termination: termination,
      release: release,
      journalTransaction: transaction,
      authorizedResult: authorizedResult
    )
  }

  private func retainedExternalDependencyObservationOutput(
    _ launch: ExternalDependencyObservationRuntimeLaunchReceipt
  ) throws -> (
    RetainedExternalDependencyObservationOutput,
    RetainedExternalDependencyObservationOutput
  ) {
    let physicalJournalDirectory: URL
    do {
      physicalJournalDirectory =
        try KernelNativeSandboxAuthorizer
        .physicalDirectoryURL(journal.runDirectory)
    } catch {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    guard launch.processIOFiles.directoryPath == physicalJournalDirectory.path,
      let stdoutName = launch.processIOFiles.standardOutputFileName,
      let stderrName = launch.processIOFiles.standardErrorFileName,
      stdoutName != stderrName
    else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    let limit = launch.resourceLimits.maximumCapturedOutputBytes / 2
    let directory = Darwin.open(
      physicalJournalDirectory.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard directory >= 0 else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    defer { _ = Darwin.close(directory) }
    return (
      try retainedExternalDependencyObservationOutputFile(
        name: stdoutName,
        limit: limit,
        directoryDescriptor: directory
      ),
      try retainedExternalDependencyObservationOutputFile(
        name: stderrName,
        limit: limit,
        directoryDescriptor: directory
      )
    )
  }

  private func retainedExternalDependencyObservationOutputFile(
    name: String,
    limit: UInt64,
    directoryDescriptor: Int32
  ) throws -> RetainedExternalDependencyObservationOutput {
    guard validRetainedOutputFileName(name) else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    let descriptor = name.withCString {
      Darwin.openat(
        directoryDescriptor,
        $0,
        O_RDONLY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    guard descriptor >= 0 else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    defer { _ = Darwin.close(descriptor) }
    var before = stat()
    guard Darwin.fstat(descriptor, &before) == 0,
      before.st_mode & S_IFMT == S_IFREG,
      before.st_nlink == 1,
      before.st_mode & 0o777 == 0o400,
      before.st_size >= 0,
      UInt64(before.st_size) <= limit
    else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    var remaining = UInt64(before.st_size)
    var hasher = SHA256()
    var retained = Data()
    retained.reserveCapacity(Int(before.st_size))
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while remaining > 0 {
      let requested = min(UInt64(buffer.count), remaining)
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, Int(requested))
      }
      if count > 0 {
        let chunk = Data(buffer.prefix(count))
        hasher.update(data: chunk)
        retained.append(chunk)
        remaining -= UInt64(count)
      } else if count < 0, errno == EINTR {
        continue
      } else {
        throw JournaledProcessRuntimeError
          .externalDependencyObservationOutputInvalid
      }
    }
    var probe: UInt8 = 0
    guard Darwin.read(descriptor, &probe, 1) == 0 else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    var after = stat()
    guard Darwin.fstat(descriptor, &after) == 0,
      after.st_dev == before.st_dev,
      after.st_ino == before.st_ino,
      after.st_mode == before.st_mode,
      after.st_nlink == before.st_nlink,
      after.st_size == before.st_size
    else {
      throw JournaledProcessRuntimeError
        .externalDependencyObservationOutputInvalid
    }
    let digest = ContentDigest(
      hasher.finalize().map {
        String(format: "%02x", $0)
      }.joined())
    return RetainedExternalDependencyObservationOutput(
      receipt: ExternalDependencyObservationOutputFileReceipt(
        fileName: name,
        byteCount: UInt64(before.st_size),
        contentDigest: digest
      ),
      data: retained
    )
  }

  private func retainedPostimageVerifierOutput(
    _ launch: KernelPostimageVerifierLaunchReceipt
  ) throws -> (
    RetainedPostimageVerifierOutput,
    RetainedPostimageVerifierOutput
  ) {
    guard launch.processIOFiles.directoryPath == journal.runDirectory.path,
      let stdoutName = launch.processIOFiles.standardOutputFileName,
      let stderrName = launch.processIOFiles.standardErrorFileName
    else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    let limit = launch.resourceLimits.maximumCapturedOutputBytes / 2
    let directory = Darwin.open(
      journal.runDirectory.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard directory >= 0 else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    defer { _ = Darwin.close(directory) }
    return (
      try retainedPostimageVerifierOutputFile(
        name: stdoutName,
        limit: limit,
        directoryDescriptor: directory
      ),
      try retainedPostimageVerifierOutputFile(
        name: stderrName,
        limit: limit,
        directoryDescriptor: directory
      )
    )
  }

  private func retainedPostimageVerifierOutputFile(
    name: String,
    limit: UInt64,
    directoryDescriptor: Int32
  ) throws -> RetainedPostimageVerifierOutput {
    guard validRetainedOutputFileName(name) else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    let descriptor = name.withCString {
      Darwin.openat(
        directoryDescriptor,
        $0,
        O_RDONLY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    guard descriptor >= 0 else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    defer { _ = Darwin.close(descriptor) }
    var before = stat()
    guard Darwin.fstat(descriptor, &before) == 0,
      before.st_mode & S_IFMT == S_IFREG,
      before.st_nlink == 1,
      before.st_mode & 0o777 == 0o400,
      before.st_size >= 0,
      UInt64(before.st_size) <= limit
    else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    var remaining = UInt64(before.st_size)
    var hasher = SHA256()
    var retained = Data()
    retained.reserveCapacity(Int(before.st_size))
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while remaining > 0 {
      let requested = min(UInt64(buffer.count), remaining)
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, Int(requested))
      }
      if count > 0 {
        let chunk = Data(buffer.prefix(count))
        hasher.update(data: chunk)
        retained.append(chunk)
        remaining -= UInt64(count)
      } else if count < 0, errno == EINTR {
        continue
      } else {
        throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
      }
    }
    var probe: UInt8 = 0
    guard Darwin.read(descriptor, &probe, 1) == 0 else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    var after = stat()
    guard Darwin.fstat(descriptor, &after) == 0,
      after.st_dev == before.st_dev,
      after.st_ino == before.st_ino,
      after.st_mode == before.st_mode,
      after.st_nlink == before.st_nlink,
      after.st_size == before.st_size
    else {
      throw JournaledProcessRuntimeError.postimageVerifierOutputInvalid
    }
    let digest = ContentDigest(
      hasher.finalize().map {
        String(format: "%02x", $0)
      }.joined())
    return RetainedPostimageVerifierOutput(
      receipt: KernelPostimageVerifierOutputFileReceipt(
        fileName: name,
        byteCount: UInt64(before.st_size),
        contentDigest: digest
      ),
      data: retained
    )
  }

  private func resultParseEvidence(
    context: PostimageVerifierCompletionContext,
    output: (
      RetainedPostimageVerifierOutput,
      RetainedPostimageVerifierOutput
    )?
  ) -> (
    receipt: KernelPostimageVerifierResultParseReceipt?,
    failureDigest: ContentDigest?
  ) {
    guard let output else {
      return (
        nil,
        resultParseFailureDigest(
          JournaledProcessRuntimeError.postimageVerifierOutputInvalid
        )
      )
    }
    let expectation = KernelPostimageVerifierResultParseExpectation(
      runID: context.activation.runID,
      activationReceiptID: context.activation.id,
      launchReceiptID: context.launch.id,
      resourceID: context.launch.resourceID,
      leaseID: context.launch.leaseID,
      parser: context.launch.parser,
      standardOutput: output.0.receipt,
      standardError: output.1.receipt
    )
    do {
      let parsed = try KernelPostimageVerifierResultParser().parse(
        standardOutput: output.0.data,
        standardError: output.1.data,
        expectation: expectation
      )
      return (parsed.receipt, nil)
    } catch {
      return (nil, resultParseFailureDigest(error))
    }
  }

  private func resultMappingEvidence(
    context: PostimageVerifierCompletionContext,
    disposition: KernelPostimageVerifierContainmentDisposition,
    nativeExit: ManagedProcessExitReceipt?,
    parse: KernelPostimageVerifierResultParseReceipt?
  ) -> (
    receipt: KernelPostimageVerifierResultMappingReceipt?,
    failureDigest: ContentDigest?
  ) {
    guard disposition == .naturalExit,
      let nativeExit,
      nativeExit.terminationSignal == nil,
      let exitCode = nativeExit.exitCode,
      let parse,
      let receipt = KernelPostimageVerifierResultMapper.expectedReceipt(
        probe: context.probe,
        nativeExitCode: exitCode,
        parse: parse
      )
    else {
      return (
        nil,
        resultMappingFailureDigest(
          disposition: disposition,
          nativeExit: nativeExit,
          parse: parse
        )
      )
    }
    return (receipt, nil)
  }

  private func postimageResultEvidence(
    context: PostimageVerifierCompletionContext,
    releaseReceiptID: ReceiptID,
    output: (
      RetainedPostimageVerifierOutput,
      RetainedPostimageVerifierOutput
    )?,
    parse: KernelPostimageVerifierResultParseReceipt?,
    mapping: KernelPostimageVerifierResultMappingReceipt?,
    completedAt: Date
  ) -> (
    receipt: KernelPostimageVerifierResultReceipt?,
    failureDigest: ContentDigest?
  ) {
    guard let output,
      let parse,
      let mapping,
      let receipt =
        KernelPostimageVerifierResultAuthority.expectedReceipt(
          activation: context.activation,
          launch: context.launch,
          releaseReceiptID: releaseReceiptID,
          standardOutput: output.0.receipt,
          standardError: output.1.receipt,
          parse: parse,
          mapping: mapping,
          completedAt: completedAt
        )
    else {
      return (
        nil,
        postimageResultFailureDigest(
          releaseReceiptID: releaseReceiptID,
          parse: parse,
          mapping: mapping
        )
      )
    }
    return (receipt, nil)
  }

  private func validRetainedOutputFileName(_ name: String) -> Bool {
    !name.isEmpty
      && name != "."
      && name != ".."
      && !name.contains("/")
      && !name.contains("\0")
      && name.precomposedStringWithCanonicalMapping == name
  }

  private func containmentFailureDigest(_ error: Error) -> ContentDigest {
    let value =
      "kernel-postimage-verifier-output-capture-v1\0"
      + String(reflecting: error)
    return ContentDigest(
      SHA256.hash(data: Data(value.utf8)).map {
        String(format: "%02x", $0)
      }.joined())
  }

  private func resultParseFailureDigest(_ error: Error) -> ContentDigest {
    let value =
      "kernel-postimage-verifier-result-parse-v1\0"
      + String(reflecting: error)
    return ContentDigest(
      SHA256.hash(data: Data(value.utf8)).map {
        String(format: "%02x", $0)
      }.joined())
  }

  private func resultMappingFailureDigest(
    disposition: KernelPostimageVerifierContainmentDisposition,
    nativeExit: ManagedProcessExitReceipt?,
    parse: KernelPostimageVerifierResultParseReceipt?
  ) -> ContentDigest {
    let exitIdentity: String
    if let nativeExit {
      exitIdentity = [
        nativeExit.exitCode.map(String.init) ?? "nil",
        nativeExit.terminationSignal.map(String.init) ?? "nil",
      ].joined(separator: "|")
    } else {
      exitIdentity = "absent"
    }
    let value = [
      "kernel-postimage-verifier-result-mapping-v1",
      disposition.rawValue,
      exitIdentity,
      parse?.resultCode ?? "no-parse",
      parse?.terminalEnvelopeDigest.rawValue ?? "no-envelope",
    ].joined(separator: "\0")
    return ContentDigest(
      SHA256.hash(data: Data(value.utf8)).map {
        String(format: "%02x", $0)
      }.joined())
  }

  private func postimageResultFailureDigest(
    releaseReceiptID: ReceiptID,
    parse: KernelPostimageVerifierResultParseReceipt?,
    mapping: KernelPostimageVerifierResultMappingReceipt?
  ) -> ContentDigest {
    let value = [
      "kernel-postimage-verifier-result-authority-v1",
      releaseReceiptID.rawValue,
      parse?.terminalEnvelopeDigest.rawValue ?? "no-parse",
      mapping?.probeDigest.rawValue ?? "no-mapping",
      mapping?.outcome.rawValue ?? "no-outcome",
    ].joined(separator: "\0")
    return ContentDigest(
      SHA256.hash(data: Data(value.utf8)).map {
        String(format: "%02x", $0)
      }.joined())
  }

  private func revalidatedVerifierExecutable(
    _ activation: KernelPostimageVerifierActivationReceipt
  ) throws -> KernelExecutableStagingReceipt {
    let observed = try KernelExecutableStager().stage(
      executablePath: activation.executableStaging.stagedExecutablePath,
      expectedDigest: activation.executableStaging.contentDigest,
      runDirectory: journal.runDirectory
    )
    guard observed.stagedExecutablePath == activation.executableStaging.stagedExecutablePath,
      observed.contentDigest == activation.executableStaging.contentDigest,
      observed.byteCount == activation.executableStaging.byteCount,
      observed.deviceID == activation.executableStaging.deviceID,
      observed.inode == activation.executableStaging.inode
    else {
      throw JournaledProcessRuntimeError.executableIdentityMismatch
    }
    return observed
  }

  private func revalidatedExternalDependencyExecutable(
    _ activation: ExternalDependencyObservationActivationReceipt
  ) throws -> KernelExecutableStagingReceipt {
    let observed = try KernelExecutableStager().stage(
      executablePath: activation.executableStaging.stagedExecutablePath,
      expectedDigest: activation.executableStaging.contentDigest,
      runDirectory: journal.runDirectory
    )
    guard observed.stagedExecutablePath == activation.executableStaging.stagedExecutablePath,
      observed.contentDigest == activation.executableStaging.contentDigest,
      observed.byteCount == activation.executableStaging.byteCount,
      observed.deviceID == activation.executableStaging.deviceID,
      observed.inode == activation.executableStaging.inode
    else {
      throw JournaledProcessRuntimeError.executableIdentityMismatch
    }
    return observed
  }

  private func providerInvocationMatchesExecutionProof(
    _ invocation: AuthorizedKernelProviderInvocation
  ) -> Bool {
    guard let executionProof else { return false }
    let receipt = invocation.receipt
    return receipt.runID == executionProof.runID
      && receipt.attemptID == executionProof.attemptID
      && receipt.nodeID == executionProof.nodeID
      && receipt.strategyFingerprint == executionProof.strategyFingerprint
      && receipt.activationActor == executionProof.activationActor
      && receipt.executionProfile == executionProof.workerExecutionProfile
      && receipt.preApplyCandidateIsolation == executionProof.preApplyCandidateIsolation
      && receipt.promptArtifact.runID == executionProof.runID
      && receipt.promptArtifact.attemptID == executionProof.attemptID
  }

  private func authorizedSpecification(
    _ specification: ManagedProcessSpecification
  ) async throws -> AuthorizedManagedProcessSpecification {
    guard let executionProof else {
      throw JournaledProcessRuntimeError.executableIdentityMismatch
    }
    guard (executionProof.preApplyCandidateIsolation != nil) == (candidateExecutionRoot != nil)
    else {
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    let expected = executionProof.workerExecutionProfile.executableContentDigest
    guard
      specification.expectedExecutableContentDigest == nil
        || specification.expectedExecutableContentDigest == expected
    else {
      throw JournaledProcessRuntimeError.executableIdentityMismatch
    }
    let environmentAuthorization: AuthorizedKernelProcessEnvironment
    do {
      environmentAuthorization = try KernelProcessEnvironmentAuthorizer().authorize(
        callerSuppliedEnvironment: specification.environment,
        policy: executionProof.workerExecutionProfile.environmentPolicy
      )
    } catch {
      throw JournaledProcessRuntimeError.executionEnvironmentUnauthorized
    }
    guard
      specification.expectedEnvironmentContentDigest == nil
        || specification.expectedEnvironmentContentDigest
          == environmentAuthorization.receipt.environmentDigest
    else {
      throw JournaledProcessRuntimeError.executionEnvironmentUnauthorized
    }
    let sandboxAuthorization: AuthorizedKernelNativeSandbox
    do {
      sandboxAuthorization = try KernelNativeSandboxAuthorizer().authorize(
        executionProfile: executionProof.workerExecutionProfile,
        workspaceRoot: executionProof.workspaceRoot,
        journalRunDirectory: journal.runDirectory,
        ioFiles: specification.ioFiles
      )
    } catch {
      throw JournaledProcessRuntimeError.nativeSandboxUnauthorized
    }
    guard
      let staging = try? KernelExecutableStager().stage(
        executablePath: specification.executablePath,
        expectedDigest: expected,
        runDirectory: journal.runDirectory
      )
    else {
      throw JournaledProcessRuntimeError.executableIdentityMismatch
    }
    var stagedSpecification = specification
    stagedSpecification.executablePath = staging.stagedExecutablePath
    stagedSpecification.executableArgumentZero =
      specification.executableArgumentZero
      ?? specification.executablePath
    stagedSpecification.expectedExecutableContentDigest = expected
    stagedSpecification.environment = environmentAuthorization.environment
    stagedSpecification.expectedEnvironmentContentDigest =
      environmentAuthorization.receipt.environmentDigest
    stagedSpecification.nativeSandbox = sandboxAuthorization.configuration
    return AuthorizedManagedProcessSpecification(
      specification: stagedSpecification,
      executableStaging: staging,
      processEnvironment: environmentAuthorization.receipt,
      nativeSandbox: sandboxAuthorization.configuration.receipt
    )
  }

  private func executionIOIsJournalOwned(
    _ specification: ManagedProcessSpecification
  ) -> Bool {
    guard let io = specification.ioFiles else { return true }
    return executionIOIsJournalOwned(io)
  }

  private func executionIOIsJournalOwned(
    _ io: ManagedProcessIOFiles
  ) -> Bool {
    let supplied = URL(
      fileURLWithPath: io.directoryPath,
      isDirectory: true
    ).standardizedFileURL.resolvingSymlinksInPath()
    let owned = journal.runDirectory.standardizedFileURL.resolvingSymlinksInPath()
    return supplied.path == owned.path
  }

  private func compensateLaunch(handle: ManagedProcessHandle) async {
    _ = try? await adapter.terminate(
      resourceID: handle.resourceID,
      leaseID: handle.leaseID,
      graceNanoseconds: 50_000_000
    )
    inDoubtResourceIDs.insert(handle.resourceID)
    await supervisor.markReleaseFailed(resourceID: handle.resourceID)
  }

  private func releaseUnmaterializedLease(
    _ lease: RuntimeResourceLease,
    receiptID: ReceiptID,
    commandID: RunCommandID
  ) async throws -> JournaledProcessAbsenceReleaseReceipt {
    let observedAt = Date()
    let observedAtMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
    let release = await supervisor.previewReleaseOutcomeReceipt(
      resourceID: lease.request.resourceID,
      leaseID: lease.request.leaseID,
      receiptID: receiptID,
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
    )
    guard case .released = release.outcome else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.ownershipDiverged
    }
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordRuntimeRelease(
          .issuedByProcessRuntime(
            release,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyReleaseOutcomeReceipt(release) else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.remove(lease.request.resourceID)
    return JournaledProcessAbsenceReleaseReceipt(
      release: release,
      journalTransaction: transaction
    )
  }

  private func recordCleanupFailure(
    lease: RuntimeResourceLease,
    receiptID: ReceiptID,
    commandID: RunCommandID,
    error: Error
  ) async throws {
    let observedAt = Date()
    let observedAtMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
    let failure = await supervisor.previewReleaseFailureReceipt(
      resourceID: lease.request.resourceID,
      leaseID: lease.request.leaseID,
      receiptID: receiptID,
      reasonDigest: Self.failureDigest(error),
      observedAt: observedAt,
      observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
    )
    do {
      _ = try await journal.transactAtCurrentSequence(
        .recordRuntimeRelease(
          .issuedByProcessRuntime(
            failure,
            issuer: .init()
          )),
        commandID: commandID,
        issuedAt: observedAt,
        actor: actorIdentity
      )
    } catch {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.journalWriteFailed
    }
    guard await supervisor.applyReleaseOutcomeReceipt(failure) else {
      inDoubtResourceIDs.insert(lease.request.resourceID)
      await supervisor.markReleaseFailed(resourceID: lease.request.resourceID)
      throw JournaledProcessRuntimeError.supervisorCommitFailed
    }
    inDoubtResourceIDs.insert(lease.request.resourceID)
  }

  private static func failureDigest(_ error: Error) -> ContentDigest {
    let material = String(reflecting: type(of: error))
    let digest = SHA256.hash(data: Data(material.utf8))
    return ContentDigest(digest.map { String(format: "%02x", $0) }.joined())
  }
}
