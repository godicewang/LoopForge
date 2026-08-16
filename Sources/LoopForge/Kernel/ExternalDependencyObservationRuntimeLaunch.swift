import Foundation

/// Durable evidence that one exact activated dependency observer was bound to
/// one exact native process. The receipt is evidence only: decoding it cannot
/// recreate the live request-file, memory-enforcement, sandbox, or process
/// capabilities required to issue the command.
struct ExternalDependencyObservationRuntimeLaunchReceipt:
  Codable, Hashable, Sendable
{
  var schemaVersion: Int
  var id: ReceiptID
  var runID: KernelRunID
  var activationReceiptID: ReceiptID
  var activationJournalFrameDigest: ContentDigest
  var attemptID: AttemptID
  var dependencyID: ExternalDependencyID
  var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
  var observer: ActorIdentity
  var resourceID: OwnedResourceID
  var leaseID: ResourceLeaseID
  var bindingReceiptID: ReceiptID
  var executableStaging: KernelExecutableStagingReceipt
  var requestArtifact: ExternalDependencyObservationRequestArtifactReceipt
  var resolvedArguments: [String]
  var argumentVectorDigest: ContentDigest
  var processEnvironment: KernelProcessEnvironmentReceipt
  var processIOFiles: ManagedProcessIOFiles
  var nativeSandbox: KernelNativeSandboxAttestationReceipt
  var parser: ExternalDependencyObservationParserContract
  var resultMappings: [ExternalDependencyObservationResultMapping]
  var networkPolicy: KernelNetworkPolicy
  var resourceLimits: RequirementVerificationResourceLimits
  var residentMemoryCeilingBytes: UInt64
  var launchedAt: Date
}

/// The process runtime may issue this capability only while retaining the
/// activation-specific readiness capability. A serialized launch receipt can
/// never be promoted back into reducer command authority.
struct AuthorizedExternalDependencyObservationRuntimeLaunch: Sendable {
  let binding: RuntimeExternalBindingReceipt
  let receipt: ExternalDependencyObservationRuntimeLaunchReceipt

  private init(
    binding: RuntimeExternalBindingReceipt,
    receipt: ExternalDependencyObservationRuntimeLaunchReceipt
  ) {
    self.binding = binding
    self.receipt = receipt
  }

  static func issuedByProcessRuntime(
    binding: RuntimeExternalBindingReceipt,
    receipt: ExternalDependencyObservationRuntimeLaunchReceipt,
    readiness: AuthorizedExternalDependencyObservationLaunchReadiness,
    issuer: JournaledProcessRuntimeCommandIssuer
  ) -> Self? {
    let activation = readiness.invocation.receipt
    guard
      readiness.residentMemoryEnforcement.authorizes(
        externalDependencyActivation: activation
      ),
      receipt.residentMemoryCeilingBytes
        == readiness
        .residentMemoryEnforcement.maximumResidentBytes,
      receipt.activationJournalFrameDigest
        == readiness.invocation
        .activationTransaction.frameDigest,
      ExternalDependencyObservationRuntimeLaunchCompiler.launch(
        receipt,
        matches: activation,
        binding: binding
      )
    else {
      return nil
    }
    return Self(binding: binding, receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      binding: RuntimeExternalBindingReceipt,
      receipt: ExternalDependencyObservationRuntimeLaunchReceipt
    ) -> Self {
      Self(binding: binding, receipt: receipt)
    }
  #endif
}

enum ExternalDependencyObservationRuntimeLaunchCompiler {
  static func specification(
    _ specification: ManagedProcessSpecification,
    matches activation: ExternalDependencyObservationActivationReceipt
  ) -> Bool {
    let expectedLimits = ManagedProcessKernelResourceLimits(
      maximumOutputFileBytes:
        activation.resourceLimits.maximumCapturedOutputBytes / 2,
      maximumProcessCount: 1
    )
    guard
      ProcessGroupRuntimeAdapter.specificationIsValid(specification),
      specification.executablePath
        == activation.executableStaging.stagedExecutablePath,
      specification.executableArgumentZero
        == activation.executableStaging.stagedExecutablePath,
      specification.arguments == activation.resolvedArguments,
      specification.environment
        == KernelProcessEnvironmentAuthorizer.minimalEnvironment,
      specification.ioFiles?.standardInputFileName
        == activation.requestArtifact.fileName,
      specification.expectedExecutableContentDigest
        == activation.executableStaging.contentDigest,
      specification.expectedEnvironmentContentDigest
        == activation.environmentIdentityDigest,
      specification.expectedArgumentVectorContentDigest
        == activation.argumentVectorDigest,
      specification.expectedProviderPromptArtifact == nil,
      specification.expectedExternalDependencyRequestArtifact
        == activation.requestArtifact,
      specification.nativeSandbox?.receipt.sandbox == .readOnly,
      specification.nativeSandbox?.receipt.networkPolicy
        == activation.networkPolicy,
      specification.kernelResourceLimits == expectedLimits
    else {
      return false
    }
    return true
  }

  static func launch(
    _ launch: ExternalDependencyObservationRuntimeLaunchReceipt,
    matches activation: ExternalDependencyObservationActivationReceipt,
    binding: RuntimeExternalBindingReceipt
  ) -> Bool {
    let sandbox = launch.nativeSandbox.authorization
    let identity = binding.identity
    let io = launch.processIOFiles
    let limits = ManagedProcessKernelResourceLimits(
      maximumOutputFileBytes:
        activation.resourceLimits.maximumCapturedOutputBytes / 2,
      maximumProcessCount: 1
    )
    guard launch.schemaVersion == 1,
      !launch.id.rawValue.isEmpty,
      binding.runID == launch.runID,
      binding.accepted,
      binding.observedAt == launch.launchedAt,
      let processID = identity.processID,
      processID > 0,
      identity.processStartMonotonicNanoseconds != nil,
      launch.runID == activation.runID,
      launch.activationReceiptID == activation.id,
      validSHA256(launch.activationJournalFrameDigest),
      launch.attemptID == activation.attemptID,
      launch.dependencyID == activation.dependencyID,
      launch.evidenceRecipeID == activation.evidenceRecipeID,
      launch.observer == activation.observer,
      launch.resourceID == binding.resourceID,
      launch.leaseID == binding.leaseID,
      launch.bindingReceiptID == binding.id,
      launch.executableStaging == activation.executableStaging,
      launch.requestArtifact == activation.requestArtifact,
      launch.resolvedArguments == activation.resolvedArguments,
      launch.argumentVectorDigest == activation.argumentVectorDigest,
      launch.processEnvironment.policy == .minimalKernelAllowlist,
      launch.processEnvironment.variableNames
        == KernelProcessEnvironmentAuthorizer.minimalEnvironment.keys
        .sorted(),
      launch.processEnvironment.environmentDigest == activation.environmentIdentityDigest,
      io.directoryPath.hasPrefix("/"),
      io.standardInputFileName == activation.requestArtifact.fileName,
      validBasename(io.standardInputFileName),
      validBasename(io.standardOutputFileName),
      validBasename(io.standardErrorFileName),
      io.standardOutputFileName != io.standardErrorFileName,
      io.standardInputFileName != io.standardOutputFileName,
      io.standardInputFileName != io.standardErrorFileName,
      sandbox.schemaVersion == 1,
      sandbox.sandbox == .readOnly,
      sandbox.networkPolicy == activation.networkPolicy,
      sandbox.workspaceRootPathDigest
        == KernelNativeSandboxAuthorizer.workspacePathDigest(
          activation.workspaceRootPath
        ),
      sandbox.journalRunDirectoryPathDigest
        == KernelNativeSandboxAuthorizer.journalRunDirectoryPathDigest(
          io.directoryPath
        ),
      sandbox.standardOutputPathDigest
        == KernelNativeSandboxAuthorizer.outputPathDigest(
          directoryPath: io.directoryPath,
          fileName: io.standardOutputFileName
        ),
      sandbox.standardErrorPathDigest
        == KernelNativeSandboxAuthorizer.errorPathDigest(
          directoryPath: io.directoryPath,
          fileName: io.standardErrorFileName
        ),
      sandbox.nativeAttestationRequired,
      sandbox.journalWritesDefaultDenied,
      validSHA256(sandbox.launcherContentDigest),
      validSHA256(sandbox.gateExecutableContentDigest),
      validSHA256(sandbox.profileDigest),
      validSHA256(sandbox.parameterDigest),
      launch.nativeSandbox.processID == identity.processID,
      launch.nativeSandbox.nativeSandboxCheckResult == 1,
      launch.nativeSandbox.gateObservedStopped,
      launch.nativeSandbox.targetExecHandshakeSucceeded,
      launch.nativeSandbox.candidateWorkingDirectory == nil,
      identity.executableContentDigest == activation.executableStaging.contentDigest,
      identity.environmentContentDigest == activation.environmentIdentityDigest,
      identity.argumentVectorContentDigest == activation.argumentVectorDigest,
      identity.nativeSandboxAttestation == launch.nativeSandbox,
      identity.kernelResourceLimits == limits,
      launch.parser == activation.parser,
      launch.resultMappings == activation.resultMappings,
      launch.networkPolicy == activation.networkPolicy,
      launch.resourceLimits == activation.resourceLimits,
      launch.residentMemoryCeilingBytes == activation.resourceLimits.maximumResidentBytes,
      launch.residentMemoryCeilingBytes > 0
    else {
      return false
    }
    return true
  }

  private static func validBasename(_ name: String?) -> Bool {
    guard let name else { return false }
    return !name.isEmpty
      && name != "."
      && name != ".."
      && !name.contains("/")
      && !name.contains("\0")
      && name.precomposedStringWithCanonicalMapping == name
  }

  private static func validSHA256(_ digest: ContentDigest) -> Bool {
    ExternalDependencyObservationProbe.validSHA256(digest)
  }
}
