import CryptoKit
import Darwin
import Dispatch
import Foundation

@_silgen_name("sandbox_check")
private func loopForgeSandboxCheck(
  _ processID: Int32,
  _ operation: UnsafePointer<CChar>?,
  _ flags: UInt32
) -> Int32

struct ManagedProcessSpecification: Codable, Hashable, Sendable {
  var executablePath: String
  var arguments: [String]
  var environment: [String: String]
  var ioFiles: ManagedProcessIOFiles? = nil
  /// Preserves the intended invocation identity when the executable bytes
  /// are launched from a kernel-owned content-addressed staging path.
  var executableArgumentZero: String? = nil
  /// Optional for the generic adapter, mandatory when launched through the
  /// journaled execution-authority boundary.
  var expectedExecutableContentDigest: ContentDigest? = nil
  /// Optional for generic transport callers. The journaled boundary always
  /// injects the digest of its kernel-constructed minimal environment.
  var expectedEnvironmentContentDigest: ContentDigest? = nil
  /// Optional for generic transport callers. Provider launches bind this to
  /// the deterministic kernel-compiled argv and recheck it before spawn.
  var expectedArgumentVectorContentDigest: ContentDigest? = nil
  /// Provider-only immutable stdin identity. The adapter re-hashes the exact
  /// already-open descriptor immediately before spawn and rewinds it to zero.
  var expectedProviderPromptArtifact: KernelProviderPromptArtifactReceipt? = nil
  /// External-observer-only immutable stdin identity. This remains a
  /// separate type so a provider prompt can never be substituted for the
  /// activation-bound dependency request merely because its bytes match.
  var expectedExternalDependencyRequestArtifact:
    ExternalDependencyObservationRequestArtifactReceipt? = nil
  /// Optional for the generic transport. The journaled runtime requires a
  /// kernel-issued deny-default configuration for every productive launch.
  var nativeSandbox: ManagedProcessNativeSandbox? = nil
  /// Optional kernel-enforced ceilings installed by KernelSandboxGate before
  /// the target executable replaces it. The deterministic postimage
  /// verifier requires this field; ordinary provider transports omit it.
  var kernelResourceLimits: ManagedProcessKernelResourceLimits? = nil
}

/// Limits that can be truthfully installed in the verifier process itself on
/// macOS. Wall time remains journal-runtime authority, while resident-memory
/// enforcement requires a separate task-observation boundary and is therefore
/// deliberately absent here.
struct ManagedProcessKernelResourceLimits: Codable, Hashable, Sendable {
  /// RLIMIT_FSIZE applied to each private retained output descriptor. The
  /// verifier compiler conservatively allocates half of the declared total
  /// capture budget to each stream, so their combined bytes cannot exceed it.
  var maximumOutputFileBytes: UInt64
  /// RLIMIT_NPROC includes the verifier itself. A value of one forbids it
  /// from creating a child while still permitting direct exec replacement.
  var maximumProcessCount: UInt64
}

/// File-backed process transport rooted in one already-owned directory.
/// Individual names are basenames rather than paths so the adapter can open
/// them relative to one no-follow directory descriptor without shell
/// redirection or ambient current-directory authority.
struct ManagedProcessIOFiles: Codable, Hashable, Sendable {
  var directoryPath: String
  var standardInputFileName: String?
  var standardOutputFileName: String?
  var standardErrorFileName: String?
}

struct ManagedProcessHandle: Codable, Hashable, Sendable {
  var runID: KernelRunID
  var resourceID: OwnedResourceID
  var leaseID: ResourceLeaseID
  var processID: Int32
  var processGroupID: Int32
  var externalIdentity: RuntimeExternalIdentity
}

struct ManagedProviderProcessLaunchReceipt: Sendable {
  var handle: ManagedProcessHandle
  var invocation: KernelProviderInvocationReceipt
  var invocationContextTransport:
    KernelProviderInvocationContextTransportReceipt
  var secretDelivery: KernelProviderSecretDeliveryReceipt?
}

struct ManagedProcessExitReceipt: Codable, Hashable, Sendable {
  var handle: ManagedProcessHandle
  var observedAtMonotonicNanoseconds: UInt64
  var exitCode: Int32?
  var terminationSignal: Int32?
}

struct ManagedProcessTerminationReceipt: Codable, Hashable, Sendable {
  var handle: ManagedProcessHandle
  var gracefulSignal: Int32
  var forced: Bool
  var exit: ManagedProcessExitReceipt
}

struct ProcessGroupAdapterProjection: Equatable, Sendable {
  var liveHandles: [ManagedProcessHandle]
}

enum ProcessGroupAdapterError: Error, Equatable {
  case invalidSpecification
  case invalidLease
  case duplicateResource(existingLeaseID: ResourceLeaseID)
  case launchFailed(errno: Int32)
  case executableContentMismatch
  case environmentContentMismatch
  case argumentVectorContentMismatch
  case providerInvocationUnauthorized
  case postimageVerifierInvocationUnauthorized
  case providerCredentialUnauthorized
  case providerPromptArtifactMismatch
  case externalDependencyObservationUnauthorized
  case externalDependencyRequestArtifactMismatch
  case nativeSandboxConfigurationMismatch
  case nativeSandboxAttestationFailed
  case unknownResource
  case staleLease(expected: ResourceLeaseID, supplied: ResourceLeaseID)
  case recoveryIdentityMissing
  case recoveryProcessAbsent
  case recoveryIdentityMismatch
  case terminationTimedOut
}

/// Owns only process groups launched for exact runtime leases. It never scans
/// by executable name and never signals a borrowed or unrelated process. A
/// process-group leader and its descendants share one kill boundary, while an
/// event source observes exit without a fixed-frequency poll loop.
actor ProcessGroupRuntimeAdapter {
  private struct SystemProcessIdentity: Equatable, Sendable {
    var processID: Int32
    var processGroupID: Int32
    var startSystemNanoseconds: UInt64
  }

  private struct Record: Sendable {
    var handle: ManagedProcessHandle
    var exitLatch: ProcessExitLatch
  }

  private struct ProviderCredentialTransport: @unchecked Sendable {
    var capability: KernelProviderSecretCapability
    var binding: KernelProviderSecretBinding
    var targetDescriptor: Int32
  }

  private struct ProviderInvocationContextTransport: Sendable {
    var invocation: KernelProviderInvocationReceipt
    var targetDescriptor: Int32
  }

  private var records: [OwnedResourceID: Record] = [:]

  #if DEBUG
    func launch(
      lease: RuntimeResourceLease,
      specification: ManagedProcessSpecification
    ) throws -> ManagedProcessHandle {
      try launchValidated(
        lease: lease,
        specification: specification,
        providerCredential: nil,
        providerInvocationContext: nil
      ).handle
    }
  #endif

  /// Launches only an exact kernel-compiled provider invocation. Credential
  /// transport is a dedicated inherited pipe descriptor, never argv,
  /// environment, filesystem, or ambient inherited state.
  func launchProvider(
    lease: RuntimeResourceLease,
    specification: ManagedProcessSpecification,
    authorization: AuthorizedKernelProviderInvocation,
    secretCapability: KernelProviderSecretCapability?,
    candidateExecutionRoot:
      AuthorizedWorkspacePreApplyCandidateExecutionRoot? = nil
  ) throws -> ManagedProviderProcessLaunchReceipt {
    do {
      try KernelProviderInvocationCompiler().validateTransport(
        specification: specification,
        against: authorization
      )
    } catch {
      throw ProcessGroupAdapterError.providerInvocationUnauthorized
    }
    let invocation = authorization.receipt
    let credential: ProviderCredentialTransport?
    switch invocation.credentialMode {
    case .none:
      guard secretCapability == nil,
        invocation.credentialDescriptor == nil
      else {
        throw ProcessGroupAdapterError.providerCredentialUnauthorized
      }
      credential = nil
    case .opaqueProviderSecret:
      guard let secretCapability,
        invocation.credentialDescriptor == KernelProviderInvocationCompiler.credentialDescriptor,
        secretCapability.metadata.binding
          == KernelProviderSecretBinding(
            runID: invocation.runID,
            attemptID: invocation.attemptID,
            providerReference: invocation.executionProfile.providerReference,
            invocationDigest: invocation.invocationDigest
          )
      else {
        throw ProcessGroupAdapterError.providerCredentialUnauthorized
      }
      credential = ProviderCredentialTransport(
        capability: secretCapability,
        binding: secretCapability.metadata.binding,
        targetDescriptor: KernelProviderInvocationCompiler.credentialDescriptor
      )
    }
    // A provider launch is never treated as an idempotent replay because
    // its single-use credential cannot be truthfully delivered twice.
    guard records[lease.request.resourceID] == nil else {
      throw ProcessGroupAdapterError.duplicateResource(
        existingLeaseID: records[lease.request.resourceID]!.handle.leaseID
      )
    }
    let candidateDescriptor: Int32?
    if let expected = invocation.preApplyCandidateIsolation {
      guard let candidateExecutionRoot else {
        throw ProcessGroupAdapterError
          .providerInvocationUnauthorized
      }
      do {
        guard
          try WorkspaceCandidatePostimageMaterializer()
            .revalidatePreApplyExecutionRoot(candidateExecutionRoot) == expected
        else {
          throw WorkspaceCandidatePostimageMaterializationError
            .existingArtifactMismatch
        }
        candidateDescriptor =
          try candidateExecutionRoot
          .descriptorForLaunch(matching: expected)
      } catch {
        throw ProcessGroupAdapterError
          .providerInvocationUnauthorized
      }
    } else {
      guard candidateExecutionRoot == nil else {
        throw ProcessGroupAdapterError
          .providerInvocationUnauthorized
      }
      candidateDescriptor = nil
    }
    let launched = try launchValidated(
      lease: lease,
      specification: specification,
      providerCredential: credential,
      providerInvocationContext: ProviderInvocationContextTransport(
        invocation: invocation,
        targetDescriptor:
          KernelProviderInvocationCompiler.invocationContextDescriptor
      ),
      candidateDescriptor: candidateDescriptor
    )
    guard let invocationContextTransport = launched.invocationContextTransport
    else {
      throw ProcessGroupAdapterError.providerInvocationUnauthorized
    }
    return ManagedProviderProcessLaunchReceipt(
      handle: launched.handle,
      invocation: invocation,
      invocationContextTransport: invocationContextTransport,
      secretDelivery: launched.secretDelivery
    )
  }

  /// Launches only an exact kernel-activated deterministic postimage
  /// verifier. This path carries no provider credential and cannot issue a
  /// verification verdict.
  func launchPostimageVerifier(
    lease: RuntimeResourceLease,
    specification: ManagedProcessSpecification,
    authorization: AuthorizedKernelPostimageVerifierInvocation,
    candidateDescriptor:
      AuthorizedWorkspaceCandidatePostimageDescriptor
  ) throws -> ManagedProcessHandle {
    guard
      KernelPostimageVerifierActivationCompiler.specification(
        specification,
        matches: authorization
      )
    else {
      throw ProcessGroupAdapterError
        .postimageVerifierInvocationUnauthorized
    }
    guard records[lease.request.resourceID] == nil else {
      throw ProcessGroupAdapterError.duplicateResource(
        existingLeaseID: records[lease.request.resourceID]!.handle.leaseID
      )
    }
    let inheritedDescriptor: Int32
    do {
      inheritedDescriptor = try candidateDescriptor.descriptorForLaunch(
        matching: authorization.receipt.candidateMaterialization
      )
    } catch {
      throw ProcessGroupAdapterError
        .postimageVerifierInvocationUnauthorized
    }
    return try launchValidated(
      lease: lease,
      specification: specification,
      providerCredential: nil,
      providerInvocationContext: nil,
      candidateDescriptor: inheritedDescriptor
    ).handle
  }

  /// Launches only an activation-bound external-dependency observer. The
  /// readiness capability is non-Codable and can exist in Release only when
  /// a trusted boundary supplied the exact resident-memory enforcement.
  func launchExternalDependencyObserver(
    lease: RuntimeResourceLease,
    specification: ManagedProcessSpecification,
    authorization: AuthorizedExternalDependencyObservationLaunchReadiness
  ) throws -> ManagedProcessHandle {
    guard
      ExternalDependencyObservationRuntimeLaunchCompiler
        .specification(
          specification,
          matches: authorization.invocation.receipt
        ),
      authorization.residentMemoryEnforcement.authorizes(
        externalDependencyActivation:
          authorization.invocation.receipt
      )
    else {
      throw ProcessGroupAdapterError
        .externalDependencyObservationUnauthorized
    }
    guard records[lease.request.resourceID] == nil else {
      throw ProcessGroupAdapterError.duplicateResource(
        existingLeaseID: records[lease.request.resourceID]!.handle.leaseID
      )
    }
    return try launchValidated(
      lease: lease,
      specification: specification,
      providerCredential: nil,
      providerInvocationContext: nil,
      candidateDescriptor: nil
    ).handle
  }

  private func launchValidated(
    lease: RuntimeResourceLease,
    specification: ManagedProcessSpecification,
    providerCredential: ProviderCredentialTransport?,
    providerInvocationContext: ProviderInvocationContextTransport?,
    candidateDescriptor: Int32? = nil
  ) throws -> (
    handle: ManagedProcessHandle,
    invocationContextTransport:
      KernelProviderInvocationContextTransportReceipt?,
    secretDelivery: KernelProviderSecretDeliveryReceipt?
  ) {
    let request = lease.request
    guard request.kind == .processTree,
      request.ownership == .owned,
      request.releasePolicy == .gracefulThenTerminate,
      request.externalIdentity == nil
    else {
      throw ProcessGroupAdapterError.invalidLease
    }
    guard Self.specificationIsValid(specification) else {
      throw ProcessGroupAdapterError.invalidSpecification
    }
    if let existing = records[request.resourceID] {
      if existing.handle.leaseID == request.leaseID {
        return (existing.handle, nil, nil)
      }
      throw ProcessGroupAdapterError.duplicateResource(
        existingLeaseID: existing.handle.leaseID
      )
    }

    let spawned = try Self.spawnProcessGroup(
      specification,
      providerCredential: providerCredential,
      providerInvocationContext: providerInvocationContext,
      candidateDescriptor: candidateDescriptor
    )
    let pid = spawned.processID
    let started = DispatchTime.now().uptimeNanoseconds
    guard
      let systemIdentity = spawned.systemIdentity
        ?? Self.systemProcessIdentity(processID: pid)
    else {
      Self.signalProcessGroup(pid, signal: SIGKILL)
      var status: Int32 = 0
      _ = waitpid(pid, &status, 0)
      throw ProcessGroupAdapterError.launchFailed(errno: ESRCH)
    }
    let identity = RuntimeExternalIdentity(
      stableDigest: Self.identityDigest(
        specification: specification,
        processID: pid,
        startedAtSystemNanoseconds: systemIdentity.startSystemNanoseconds
      ),
      processID: pid,
      processStartMonotonicNanoseconds: started,
      processStartSystemNanoseconds: systemIdentity.startSystemNanoseconds,
      parentResourceID: nil,
      executableContentDigest: specification.expectedExecutableContentDigest,
      environmentContentDigest: specification.expectedEnvironmentContentDigest,
      argumentVectorContentDigest:
        specification.expectedArgumentVectorContentDigest,
      nativeSandboxAttestation: spawned.nativeSandboxAttestation,
      kernelResourceLimits: specification.kernelResourceLimits
    )
    let handle = ManagedProcessHandle(
      runID: request.runID,
      resourceID: request.resourceID,
      leaseID: request.leaseID,
      processID: pid,
      processGroupID: pid,
      externalIdentity: identity
    )
    records[request.resourceID] = Record(
      handle: handle,
      exitLatch: ProcessExitLatch(
        processID: pid,
        handle: handle,
        ownsChild: true
      )
    )
    return (
      handle,
      spawned.invocationContextTransport,
      spawned.secretDelivery
    )
  }

  /// Reattaches only to the exact journaled PID/start-time/process-group
  /// identity. A missing PID is distinguishable from PID reuse or a process
  /// that is no longer its own group leader; neither case is signalled.
  func recover(lease: RuntimeResourceLease) throws -> ManagedProcessHandle {
    let request = lease.request
    guard request.kind == .processTree,
      request.ownership == .owned,
      request.releasePolicy == .gracefulThenTerminate,
      let externalIdentity = request.externalIdentity,
      let processID = externalIdentity.processID,
      let expectedStart = externalIdentity.processStartSystemNanoseconds,
      processID > 0
    else {
      throw ProcessGroupAdapterError.recoveryIdentityMissing
    }
    if let existing = records[request.resourceID] {
      if existing.handle.leaseID == request.leaseID,
        existing.handle.externalIdentity == externalIdentity
      {
        return existing.handle
      }
      throw ProcessGroupAdapterError.duplicateResource(
        existingLeaseID: existing.handle.leaseID
      )
    }
    guard let observed = Self.systemProcessIdentity(processID: processID) else {
      throw ProcessGroupAdapterError.recoveryProcessAbsent
    }
    guard observed.startSystemNanoseconds == expectedStart,
      observed.processGroupID == processID
    else {
      throw ProcessGroupAdapterError.recoveryIdentityMismatch
    }

    let handle = ManagedProcessHandle(
      runID: request.runID,
      resourceID: request.resourceID,
      leaseID: request.leaseID,
      processID: processID,
      processGroupID: processID,
      externalIdentity: externalIdentity
    )
    let latch = ProcessExitLatch(
      processID: processID,
      handle: handle,
      ownsChild: false
    )
    guard Self.systemProcessIdentity(processID: processID) == observed,
      Self.processGroupExists(processID)
    else {
      latch.invalidate()
      throw ProcessGroupAdapterError.recoveryProcessAbsent
    }
    records[request.resourceID] = Record(handle: handle, exitLatch: latch)
    return handle
  }

  func join(
    resourceID: OwnedResourceID,
    leaseID: ResourceLeaseID,
    timeoutNanoseconds: UInt64
  ) async throws -> ManagedProcessExitReceipt {
    let record = try exactRecord(resourceID: resourceID, leaseID: leaseID)
    let deadline = Self.deadline(after: timeoutNanoseconds)
    guard let exit = await record.exitLatch.wait(timeoutNanoseconds: timeoutNanoseconds) else {
      throw ProcessGroupAdapterError.terminationTimedOut
    }
    guard
      await Self.waitForProcessGroupToDisappear(
        record.handle.processGroupID,
        deadline: deadline
      )
    else {
      // A leader may exit while a descendant keeps the group alive. Keep
      // the record so the caller cannot mistake leader exit for drain.
      throw ProcessGroupAdapterError.terminationTimedOut
    }
    records[resourceID] = nil
    return exit
  }

  func terminate(
    resourceID: OwnedResourceID,
    leaseID: ResourceLeaseID,
    gracefulSignal: Int32 = SIGTERM,
    graceNanoseconds: UInt64
  ) async throws -> ManagedProcessTerminationReceipt {
    let record = try exactRecord(resourceID: resourceID, leaseID: leaseID)
    let gracefulDeadline = Self.deadline(after: graceNanoseconds)
    Self.signalProcessGroup(record.handle.processGroupID, signal: gracefulSignal)
    let gracefulExit = await record.exitLatch.wait(timeoutNanoseconds: graceNanoseconds)
    if let gracefulExit,
      await Self.waitForProcessGroupToDisappear(
        record.handle.processGroupID,
        deadline: gracefulDeadline
      )
    {
      records[resourceID] = nil
      return ManagedProcessTerminationReceipt(
        handle: record.handle,
        gracefulSignal: gracefulSignal,
        forced: false,
        exit: gracefulExit
      )
    }

    Self.signalProcessGroup(record.handle.processGroupID, signal: SIGKILL)
    let forceTimeout = max(graceNanoseconds, 1_000_000_000)
    let forceDeadline = Self.deadline(after: forceTimeout)
    let exit: ManagedProcessExitReceipt?
    if let gracefulExit {
      exit = gracefulExit
    } else {
      exit = await record.exitLatch.wait(timeoutNanoseconds: forceTimeout)
    }
    guard let exit,
      await Self.waitForProcessGroupToDisappear(
        record.handle.processGroupID,
        deadline: forceDeadline
      )
    else {
      // Retain ownership so quiescence cannot be manufactured.
      throw ProcessGroupAdapterError.terminationTimedOut
    }
    records[resourceID] = nil
    return ManagedProcessTerminationReceipt(
      handle: record.handle,
      gracefulSignal: gracefulSignal,
      forced: true,
      exit: exit
    )
  }

  func projection() -> ProcessGroupAdapterProjection {
    ProcessGroupAdapterProjection(
      liveHandles: records.values.map(\.handle).sorted {
        $0.resourceID.rawValue < $1.resourceID.rawValue
      })
  }

  private func exactRecord(
    resourceID: OwnedResourceID,
    leaseID: ResourceLeaseID
  ) throws -> Record {
    guard let record = records[resourceID] else {
      throw ProcessGroupAdapterError.unknownResource
    }
    guard record.handle.leaseID == leaseID else {
      throw ProcessGroupAdapterError.staleLease(
        expected: record.handle.leaseID,
        supplied: leaseID
      )
    }
    return record
  }

  nonisolated static func specificationIsValid(
    _ specification: ManagedProcessSpecification
  ) -> Bool {
    guard specification.executablePath.hasPrefix("/"),
      FileManager.default.isExecutableFile(
        atPath: specification.executablePath
      ),
      !specification.executablePath.contains("\0"),
      specification.executableArgumentZero.map({ !$0.contains("\0") }) ?? true,
      specification.arguments.allSatisfy({ !$0.contains("\0") })
    else {
      return false
    }
    guard
      specification.environment.allSatisfy({ key, value in
        !key.isEmpty && !key.contains("=") && !key.contains("\0") && !value.contains("\0")
      })
    else { return false }
    if let expected = specification.expectedExecutableContentDigest?.rawValue,
      !validContentDigest(expected)
    {
      return false
    }
    if let expected = specification.expectedEnvironmentContentDigest?.rawValue,
      !validContentDigest(expected)
    {
      return false
    }
    if let expected = specification.expectedArgumentVectorContentDigest?.rawValue,
      !validContentDigest(expected)
    {
      return false
    }
    if let nativeSandbox = specification.nativeSandbox,
      !KernelNativeSandboxAuthorizer.configurationIsValid(nativeSandbox)
    {
      return false
    }
    if let limits = specification.kernelResourceLimits {
      guard specification.nativeSandbox != nil,
        limits.maximumProcessCount == 1
      else {
        return false
      }
    }
    if let artifact = specification.expectedProviderPromptArtifact {
      guard KernelProviderInvocationCompiler.validFileName(artifact.fileName),
        validContentDigest(artifact.contentDigest.rawValue),
        artifact.byteCount > 0,
        artifact.byteCount
          <= UInt64(
            KernelProviderPromptArtifactIssuer.maximumPromptBytes
          ),
        artifact.inode > 0,
        specification.ioFiles?.standardInputFileName == artifact.fileName
      else {
        return false
      }
    }
    if let artifact =
      specification.expectedExternalDependencyRequestArtifact
    {
      guard specification.expectedProviderPromptArtifact == nil,
        KernelProviderInvocationCompiler.validFileName(
          artifact.fileName
        ),
        validContentDigest(artifact.contentDigest.rawValue),
        artifact.byteCount > 0,
        artifact.byteCount
          <= UInt64(
            ExternalDependencyObservationRequestArtifactIssuer
              .maximumRequestBytes
          ),
        artifact.deviceID > 0,
        artifact.inode > 0,
        specification.ioFiles?.standardInputFileName == artifact.fileName
      else {
        return false
      }
    }
    guard let io = specification.ioFiles else { return true }
    guard io.directoryPath.hasPrefix("/"),
      !io.directoryPath.contains("\0")
    else { return false }
    let names = [
      io.standardInputFileName,
      io.standardOutputFileName,
      io.standardErrorFileName,
    ].compactMap { $0 }
    return Set(names).count == names.count && names.allSatisfy(validIOFileName)
  }

  private nonisolated static func validContentDigest(_ value: String) -> Bool {
    let bytes = value.utf8
    return bytes.count == 64
      && bytes.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }

  private struct SpawnedProcess {
    var processID: pid_t
    var systemIdentity: SystemProcessIdentity?
    var nativeSandboxAttestation: KernelNativeSandboxAttestationReceipt?
    var invocationContextTransport:
      KernelProviderInvocationContextTransportReceipt?
    var secretDelivery: KernelProviderSecretDeliveryReceipt?
  }

  private static func spawnProcessGroup(
    _ specification: ManagedProcessSpecification,
    providerCredential: ProviderCredentialTransport?,
    providerInvocationContext: ProviderInvocationContextTransport?,
    candidateDescriptor: Int32?
  ) throws -> SpawnedProcess {
    if let expected = specification.expectedExecutableContentDigest,
      executableContentDigest(atPath: specification.executablePath) != expected
    {
      throw ProcessGroupAdapterError.executableContentMismatch
    }
    if let expected = specification.expectedEnvironmentContentDigest,
      KernelProcessEnvironmentAuthorizer.environmentDigest(
        specification.environment
      ) != expected
    {
      throw ProcessGroupAdapterError.environmentContentMismatch
    }
    if let expected = specification.expectedArgumentVectorContentDigest,
      KernelProviderInvocationCompiler.argumentVectorDigest(
        specification.arguments
      ) != expected
    {
      throw ProcessGroupAdapterError.argumentVectorContentMismatch
    }
    if let nativeSandbox = specification.nativeSandbox {
      guard KernelNativeSandboxAuthorizer.configurationIsValid(nativeSandbox),
        executableContentDigest(
          atPath: nativeSandbox.receipt.launcherPath
        ) == nativeSandbox.receipt.launcherContentDigest,
        executableContentDigest(
          atPath: nativeSandbox.receipt.gateExecutablePath
        ) == nativeSandbox.receipt.gateExecutableContentDigest
      else {
        throw ProcessGroupAdapterError.nativeSandboxConfigurationMismatch
      }
    }
    var attributes: posix_spawnattr_t?
    var actions: posix_spawn_file_actions_t?
    let attributeResult = posix_spawnattr_init(&attributes)
    guard attributeResult == 0 else {
      throw ProcessGroupAdapterError.launchFailed(errno: attributeResult)
    }
    let actionsResult = posix_spawn_file_actions_init(&actions)
    guard actionsResult == 0 else {
      posix_spawnattr_destroy(&attributes)
      throw ProcessGroupAdapterError.launchFailed(errno: actionsResult)
    }
    defer {
      posix_spawn_file_actions_destroy(&actions)
      posix_spawnattr_destroy(&attributes)
    }

    let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)
    let flagsResult = posix_spawnattr_setflags(&attributes, flags)
    guard flagsResult == 0 else {
      throw ProcessGroupAdapterError.launchFailed(errno: flagsResult)
    }
    let groupResult = posix_spawnattr_setpgroup(&attributes, 0)
    guard groupResult == 0 else {
      throw ProcessGroupAdapterError.launchFailed(errno: groupResult)
    }

    let openedIO = try configureStandardIO(
      specification.ioFiles,
      expectedInputArtifact: specification.expectedProviderPromptArtifact,
      expectedExternalDependencyInputArtifact:
        specification.expectedExternalDependencyRequestArtifact,
      actions: &actions
    )
    defer { openedIO.descriptors.forEach { _ = Darwin.close($0) } }

    if let candidateDescriptor {
      guard candidateDescriptor >= 0 else {
        throw ProcessGroupAdapterError
          .postimageVerifierInvocationUnauthorized
      }
      let changeDirectoryResult = posix_spawn_file_actions_addfchdir_np(
        &actions,
        candidateDescriptor
      )
      guard changeDirectoryResult == 0 else {
        throw ProcessGroupAdapterError.launchFailed(
          errno: changeDirectoryResult
        )
      }
      // CLOEXEC_DEFAULT closes the source descriptor after its ordered
      // fchdir action. An explicit close action here is rejected on
      // some Darwin versions because the descriptor is not inherited.
    }

    var handshakeReadDescriptor: Int32 = -1
    var handshakeWriteDescriptor: Int32 = -1
    if specification.nativeSandbox != nil {
      var descriptors: [Int32] = [0, 0]
      guard Darwin.pipe(&descriptors) == 0 else {
        throw ProcessGroupAdapterError.launchFailed(errno: errno)
      }
      handshakeReadDescriptor = descriptors[0]
      handshakeWriteDescriptor = descriptors[1]
      guard Darwin.fcntl(handshakeReadDescriptor, F_SETFD, FD_CLOEXEC) == 0,
        Darwin.fcntl(handshakeWriteDescriptor, F_SETFD, FD_CLOEXEC) == 0
      else {
        let failure = errno
        _ = Darwin.close(handshakeReadDescriptor)
        _ = Darwin.close(handshakeWriteDescriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: failure)
      }
      let duplicateResult = posix_spawn_file_actions_adddup2(
        &actions,
        handshakeWriteDescriptor,
        KernelNativeSandboxAuthorizer.handshakeDescriptor
      )
      guard duplicateResult == 0 else {
        _ = Darwin.close(handshakeReadDescriptor)
        _ = Darwin.close(handshakeWriteDescriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: duplicateResult)
      }
    }
    defer {
      if handshakeReadDescriptor >= 0 { _ = Darwin.close(handshakeReadDescriptor) }
      if handshakeWriteDescriptor >= 0 { _ = Darwin.close(handshakeWriteDescriptor) }
    }

    var invocationContextReadDescriptor: Int32 = -1
    var invocationContextWriteDescriptor: Int32 = -1
    var invocationContextTransportReceipt:
      KernelProviderInvocationContextTransportReceipt?
    if let providerInvocationContext {
      guard providerInvocationContext.targetDescriptor ==
          KernelProviderInvocationCompiler.invocationContextDescriptor,
        providerInvocationContext.invocation.invocationContextDescriptor ==
          providerInvocationContext.targetDescriptor,
        let payload = KernelProviderInvocationContextTransportReceipt
          .payloadBytes(for: providerInvocationContext.invocation),
        let receipt = KernelProviderInvocationContextTransportReceipt.issue(
          invocation: providerInvocationContext.invocation,
          stagedAtMonotonicNanoseconds:
            DispatchTime.now().uptimeNanoseconds
        ),
        receipt.byteCount == UInt64(payload.count)
      else {
        throw ProcessGroupAdapterError.providerInvocationUnauthorized
      }
      let descriptors = try makeCloexecPipe(minimumDescriptor: 200)
      invocationContextReadDescriptor = descriptors.read
      invocationContextWriteDescriptor = descriptors.write
      let duplicateResult = posix_spawn_file_actions_adddup2(
        &actions,
        invocationContextReadDescriptor,
        providerInvocationContext.targetDescriptor
      )
      guard duplicateResult == 0 else {
        _ = Darwin.close(invocationContextReadDescriptor)
        _ = Darwin.close(invocationContextWriteDescriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: duplicateResult)
      }
      let closeWriteResult = posix_spawn_file_actions_addclose(
        &actions,
        invocationContextWriteDescriptor
      )
      guard closeWriteResult == 0 else {
        _ = Darwin.close(invocationContextReadDescriptor)
        _ = Darwin.close(invocationContextWriteDescriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: closeWriteResult)
      }
      do {
        try writeAll(payload, to: invocationContextWriteDescriptor)
      } catch {
        _ = Darwin.close(invocationContextReadDescriptor)
        _ = Darwin.close(invocationContextWriteDescriptor)
        throw error
      }
      invocationContextTransportReceipt = receipt
    } else if specification.expectedProviderPromptArtifact != nil {
      throw ProcessGroupAdapterError.providerInvocationUnauthorized
    }
    defer {
      if invocationContextReadDescriptor >= 0 {
        _ = Darwin.close(invocationContextReadDescriptor)
      }
      if invocationContextWriteDescriptor >= 0 {
        _ = Darwin.close(invocationContextWriteDescriptor)
      }
    }

    var credentialReadDescriptor: Int32 = -1
    var credentialWriteDescriptor: Int32 = -1
    if let providerCredential {
      let descriptors = try makeCloexecPipe(minimumDescriptor: 200)
      credentialReadDescriptor = descriptors.read
      credentialWriteDescriptor = descriptors.write
      let duplicateResult = posix_spawn_file_actions_adddup2(
        &actions,
        credentialReadDescriptor,
        providerCredential.targetDescriptor
      )
      guard duplicateResult == 0 else {
        _ = Darwin.close(credentialReadDescriptor)
        _ = Darwin.close(credentialWriteDescriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: duplicateResult)
      }
      let closeWriteResult = posix_spawn_file_actions_addclose(
        &actions,
        credentialWriteDescriptor
      )
      guard closeWriteResult == 0 else {
        _ = Darwin.close(credentialReadDescriptor)
        _ = Darwin.close(credentialWriteDescriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: closeWriteResult)
      }
    }
    defer {
      if credentialReadDescriptor >= 0 { _ = Darwin.close(credentialReadDescriptor) }
      if credentialWriteDescriptor >= 0 { _ = Darwin.close(credentialWriteDescriptor) }
    }

    let executablePath: String
    let arguments: [String]
    if let nativeSandbox = specification.nativeSandbox {
      executablePath = nativeSandbox.receipt.launcherPath
      let parameterArguments = nativeSandbox.parameters.keys.sorted().map { key in
        "-D\(key)=\(nativeSandbox.parameters[key] ?? "")"
      }
      let resourceArguments: [String]
      if let limits = specification.kernelResourceLimits {
        resourceArguments = [
          "--kernel-resource-limits-v1",
          String(limits.maximumOutputFileBytes),
          String(limits.maximumProcessCount),
        ]
      } else {
        resourceArguments = []
      }
      arguments =
        [executablePath]
        + parameterArguments
        + [
          "-p",
          nativeSandbox.profile,
          nativeSandbox.receipt.gateExecutablePath,
          String(KernelNativeSandboxAuthorizer.handshakeDescriptor),
        ]
        + resourceArguments
        + [specification.executablePath]
        + specification.arguments
    } else {
      executablePath = specification.executablePath
      arguments =
        [
          specification.executableArgumentZero ?? specification.executablePath
        ] + specification.arguments
    }
    let environment = specification.environment
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value)" }
    var processID: pid_t = 0
    let result = try withMutableCStringArray(arguments) { argumentVector in
      try withMutableCStringArray(environment) { environmentVector in
        executablePath.withCString { executable in
          posix_spawn(
            &processID,
            executable,
            &actions,
            &attributes,
            argumentVector,
            environmentVector
          )
        }
      }
    }
    guard result == 0 else {
      if let directoryDescriptor = openedIO.directoryDescriptor {
        Self.removeCreatedFiles(
          directoryDescriptor: directoryDescriptor,
          fileNames: openedIO.createdFileNames
        )
      }
      throw ProcessGroupAdapterError.launchFailed(errno: result)
    }
    if credentialReadDescriptor >= 0 {
      _ = Darwin.close(credentialReadDescriptor)
      credentialReadDescriptor = -1
    }
    if invocationContextReadDescriptor >= 0 {
      _ = Darwin.close(invocationContextReadDescriptor)
      invocationContextReadDescriptor = -1
    }
    if invocationContextWriteDescriptor >= 0 {
      _ = Darwin.close(invocationContextWriteDescriptor)
      invocationContextWriteDescriptor = -1
    }
    if handshakeWriteDescriptor >= 0 {
      _ = Darwin.close(handshakeWriteDescriptor)
      handshakeWriteDescriptor = -1
    }
    var nativeSandboxAttestation: KernelNativeSandboxAttestationReceipt?
    var attestedSystemIdentity: SystemProcessIdentity?
    if let nativeSandbox = specification.nativeSandbox {
      var attested = false
      for _ in 0..<200 {
        if Self.processStatus(processID: processID) == UInt32(SSTOP),
          loopForgeSandboxCheck(processID, nil, 0) == 1
        {
          attested = true
          break
        }
        usleep(500)
      }
      guard attested else {
        var gateFailure: Int32 = 0
        var descriptorEvent = pollfd(
          fd: handshakeReadDescriptor,
          events: Int16(POLLIN | POLLHUP),
          revents: 0
        )
        let gatePoll = Darwin.poll(&descriptorEvent, 1, 0)
        let gateRead =
          gatePoll > 0
          ? withUnsafeMutableBytes(of: &gateFailure) { bytes in
            Darwin.read(
              handshakeReadDescriptor,
              bytes.baseAddress,
              bytes.count
            )
          }
          : -1
        Self.signalProcessGroup(processID, signal: SIGKILL)
        var status: Int32 = 0
        _ = waitpid(processID, &status, 0)
        if let directoryDescriptor = openedIO.directoryDescriptor {
          Self.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: openedIO.createdFileNames
          )
        }
        if gateRead == MemoryLayout<Int32>.size, gateFailure > 0 {
          throw ProcessGroupAdapterError.launchFailed(errno: gateFailure)
        }
        throw ProcessGroupAdapterError.nativeSandboxAttestationFailed
      }
      guard let stoppedIdentity = Self.systemProcessIdentity(processID: processID),
        stoppedIdentity.processGroupID == processID
      else {
        Self.signalProcessGroup(processID, signal: SIGKILL)
        var status: Int32 = 0
        _ = waitpid(processID, &status, 0)
        if let directoryDescriptor = openedIO.directoryDescriptor {
          Self.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: openedIO.createdFileNames
          )
        }
        throw ProcessGroupAdapterError.nativeSandboxAttestationFailed
      }
      let candidateWorkingDirectory: KernelCandidateWorkingDirectoryAttestationReceipt?
      if let candidateDescriptor {
        var expectedCandidate = stat()
        guard fstat(candidateDescriptor, &expectedCandidate) == 0,
          let observedCandidate =
            Self
            .processWorkingDirectoryIdentity(processID: processID),
          observedCandidate.deviceID == UInt64(expectedCandidate.st_dev),
          observedCandidate.inode == UInt64(expectedCandidate.st_ino)
        else {
          Self.signalProcessGroup(processID, signal: SIGKILL)
          var status: Int32 = 0
          _ = waitpid(processID, &status, 0)
          throw ProcessGroupAdapterError
            .nativeSandboxAttestationFailed
        }
        candidateWorkingDirectory =
          KernelCandidateWorkingDirectoryAttestationReceipt(
            binding: .posixSpawnFileActionsFchdir,
            deviceID: observedCandidate.deviceID,
            inode: observedCandidate.inode
          )
      } else {
        candidateWorkingDirectory = nil
      }
      attestedSystemIdentity = stoppedIdentity
      let observedAt = DispatchTime.now().uptimeNanoseconds
      nativeSandboxAttestation = KernelNativeSandboxAttestationReceipt(
        authorization: nativeSandbox.receipt,
        processID: processID,
        observedAtMonotonicNanoseconds: observedAt,
        nativeSandboxCheckResult: 1,
        gateObservedStopped: true,
        targetExecHandshakeSucceeded: false,
        candidateWorkingDirectory: candidateWorkingDirectory
      )
      guard Darwin.kill(processID, SIGCONT) == 0 else {
        Self.signalProcessGroup(processID, signal: SIGKILL)
        var status: Int32 = 0
        _ = waitpid(processID, &status, 0)
        if let directoryDescriptor = openedIO.directoryDescriptor {
          Self.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: openedIO.createdFileNames
          )
        }
        throw ProcessGroupAdapterError.nativeSandboxAttestationFailed
      }
      var descriptorEvent = pollfd(
        fd: handshakeReadDescriptor,
        events: Int16(POLLIN | POLLHUP),
        revents: 0
      )
      let pollResult = Darwin.poll(&descriptorEvent, 1, 500)
      guard pollResult > 0 else {
        Self.signalProcessGroup(processID, signal: SIGKILL)
        var status: Int32 = 0
        _ = waitpid(processID, &status, 0)
        if let directoryDescriptor = openedIO.directoryDescriptor {
          Self.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: openedIO.createdFileNames
          )
        }
        throw ProcessGroupAdapterError.nativeSandboxAttestationFailed
      }
      var launchErrno: Int32 = 0
      let readCount = withUnsafeMutableBytes(of: &launchErrno) { bytes in
        Darwin.read(
          handshakeReadDescriptor,
          bytes.baseAddress,
          bytes.count
        )
      }
      guard readCount == 0 else {
        Self.signalProcessGroup(processID, signal: SIGKILL)
        var status: Int32 = 0
        _ = waitpid(processID, &status, 0)
        if let directoryDescriptor = openedIO.directoryDescriptor {
          Self.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: openedIO.createdFileNames
          )
        }
        if readCount == MemoryLayout<Int32>.size, launchErrno > 0 {
          throw ProcessGroupAdapterError.launchFailed(errno: launchErrno)
        }
        throw ProcessGroupAdapterError.nativeSandboxAttestationFailed
      }
      nativeSandboxAttestation?.targetExecHandshakeSucceeded = true
    }
    var secretDelivery: KernelProviderSecretDeliveryReceipt?
    if let providerCredential {
      do {
        secretDelivery = try providerCredential.capability.deliver(
          to: credentialWriteDescriptor,
          targetDescriptor: providerCredential.targetDescriptor,
          for: providerCredential.binding
        )
        _ = Darwin.close(credentialWriteDescriptor)
        credentialWriteDescriptor = -1
      } catch {
        Self.signalProcessGroup(processID, signal: SIGKILL)
        var status: Int32 = 0
        _ = waitpid(processID, &status, 0)
        if let directoryDescriptor = openedIO.directoryDescriptor {
          Self.removeCreatedFiles(
            directoryDescriptor: directoryDescriptor,
            fileNames: openedIO.createdFileNames
          )
        }
        throw ProcessGroupAdapterError.providerCredentialUnauthorized
      }
    }
    return SpawnedProcess(
      processID: processID,
      systemIdentity: attestedSystemIdentity,
      nativeSandboxAttestation: nativeSandboxAttestation,
      invocationContextTransport: invocationContextTransportReceipt,
      secretDelivery: secretDelivery
    )
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { buffer in
      var written = 0
      while written < buffer.count {
        let result = Darwin.write(
          descriptor,
          buffer.baseAddress?.advanced(by: written),
          buffer.count - written
        )
        if result > 0 {
          written += result
        } else if result < 0, errno == EINTR {
          continue
        } else {
          throw ProcessGroupAdapterError.launchFailed(errno: errno)
        }
      }
    }
  }

  /// Allocates pipe ends away from fixed child protocol descriptors so file
  /// action ordering cannot accidentally close a just-duplicated endpoint.
  private static func makeCloexecPipe(
    minimumDescriptor: Int32
  ) throws -> (read: Int32, write: Int32) {
    var original: [Int32] = [0, 0]
    guard Darwin.pipe(&original) == 0 else {
      throw ProcessGroupAdapterError.launchFailed(errno: errno)
    }
    defer {
      _ = Darwin.close(original[0])
      _ = Darwin.close(original[1])
    }
    let read = Darwin.fcntl(original[0], F_DUPFD_CLOEXEC, minimumDescriptor)
    guard read >= 0 else {
      throw ProcessGroupAdapterError.launchFailed(errno: errno)
    }
    let write = Darwin.fcntl(original[1], F_DUPFD_CLOEXEC, minimumDescriptor)
    guard write >= 0 else {
      let failure = errno
      _ = Darwin.close(read)
      throw ProcessGroupAdapterError.launchFailed(errno: failure)
    }
    return (read, write)
  }

  /// Hashes one regular executable through a single descriptor. Resolving
  /// symlinks before opening prevents the symlink itself from becoming the
  /// identity, and a second adapter-side check immediately before spawn
  /// narrows the pathname replacement window.
  nonisolated static func executableContentDigest(atPath path: String) -> ContentDigest? {
    guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
    let resolved = URL(fileURLWithPath: path).standardizedFileURL
      .resolvingSymlinksInPath()
    var metadata = stat()
    guard lstat(resolved.path, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFREG,
      FileManager.default.isExecutableFile(atPath: resolved.path),
      let handle = try? FileHandle(forReadingFrom: resolved)
    else {
      return nil
    }
    defer { try? handle.close() }
    var hasher = SHA256()
    do {
      while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
        hasher.update(data: chunk)
      }
    } catch {
      return nil
    }
    let digest = hasher.finalize()
    return ContentDigest(digest.map { String(format: "%02x", $0) }.joined())
  }

  private struct OpenedProcessIO {
    var descriptors: [Int32]
    var directoryDescriptor: Int32?
    var createdFileNames: [String]
  }

  private static func configureStandardIO(
    _ io: ManagedProcessIOFiles?,
    expectedInputArtifact: KernelProviderPromptArtifactReceipt?,
    expectedExternalDependencyInputArtifact:
      ExternalDependencyObservationRequestArtifactReceipt?,
    actions: inout posix_spawn_file_actions_t?
  ) throws -> OpenedProcessIO {
    guard let io else {
      guard expectedInputArtifact == nil,
        expectedExternalDependencyInputArtifact == nil
      else {
        throw ProcessGroupAdapterError.providerPromptArtifactMismatch
      }
      let result = "/dev/null".withCString { path in
        for (target, flags) in [
          (STDIN_FILENO, O_RDONLY),
          (STDOUT_FILENO, O_WRONLY),
          (STDERR_FILENO, O_WRONLY),
        ] {
          let added = posix_spawn_file_actions_addopen(
            &actions,
            target,
            path,
            flags,
            0
          )
          guard added == 0 else { return added }
        }
        return 0
      }
      guard result == 0 else {
        throw ProcessGroupAdapterError.launchFailed(errno: result)
      }
      return OpenedProcessIO(
        descriptors: [],
        directoryDescriptor: nil,
        createdFileNames: []
      )
    }

    let directoryFD = Darwin.open(
      io.directoryPath,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard directoryFD >= 0 else {
      throw ProcessGroupAdapterError.launchFailed(errno: errno)
    }
    var descriptors = [directoryFD]
    var createdFileNames: [String] = []
    var succeeded = false
    defer {
      if !succeeded {
        Self.removeCreatedFiles(
          directoryDescriptor: directoryFD,
          fileNames: createdFileNames
        )
        descriptors.forEach { _ = Darwin.close($0) }
      }
    }

    func addNull(target: Int32, flags: Int32) throws {
      let result = "/dev/null".withCString {
        posix_spawn_file_actions_addopen(
          &actions,
          target,
          $0,
          flags,
          0
        )
      }
      guard result == 0 else {
        throw ProcessGroupAdapterError.launchFailed(errno: result)
      }
    }

    func openRelative(
      name: String,
      flags: Int32,
      mode: mode_t = 0
    ) throws -> Int32 {
      let descriptor = name.withCString {
        Darwin.openat(directoryFD, $0, flags | O_NOFOLLOW | O_CLOEXEC, mode)
      }
      guard descriptor >= 0 else {
        throw ProcessGroupAdapterError.launchFailed(errno: errno)
      }
      var status = stat()
      guard Darwin.fstat(descriptor, &status) == 0,
        (status.st_mode & S_IFMT) == S_IFREG
      else {
        let failure = errno == 0 ? EINVAL : errno
        _ = Darwin.close(descriptor)
        throw ProcessGroupAdapterError.launchFailed(errno: failure)
      }
      descriptors.append(descriptor)
      return descriptor
    }

    func bind(descriptor: Int32, target: Int32) throws {
      let result = posix_spawn_file_actions_adddup2(
        &actions,
        descriptor,
        target
      )
      guard result == 0 else {
        throw ProcessGroupAdapterError.launchFailed(errno: result)
      }
    }

    if let name = io.standardInputFileName {
      let descriptor = try openRelative(name: name, flags: O_RDONLY)
      if let expectedInputArtifact {
        guard name == expectedInputArtifact.fileName,
          inputArtifactMatches(
            descriptor: descriptor,
            expected: expectedInputArtifact
          )
        else {
          throw ProcessGroupAdapterError.providerPromptArtifactMismatch
        }
      } else if let expectedExternalDependencyInputArtifact {
        guard name == expectedExternalDependencyInputArtifact.fileName,
          inputArtifactMatches(
            descriptor: descriptor,
            expected: expectedExternalDependencyInputArtifact
          )
        else {
          throw ProcessGroupAdapterError
            .externalDependencyRequestArtifactMismatch
        }
      }
      try bind(descriptor: descriptor, target: STDIN_FILENO)
    } else {
      guard expectedInputArtifact == nil,
        expectedExternalDependencyInputArtifact == nil
      else {
        throw ProcessGroupAdapterError.providerPromptArtifactMismatch
      }
      try addNull(target: STDIN_FILENO, flags: O_RDONLY)
    }
    for (name, target) in [
      (io.standardOutputFileName, STDOUT_FILENO),
      (io.standardErrorFileName, STDERR_FILENO),
    ] {
      if let name {
        let descriptor = try openRelative(
          name: name,
          flags: O_WRONLY | O_CREAT | O_EXCL,
          mode: 0o600
        )
        guard Darwin.fchmod(descriptor, 0o400) == 0 else {
          throw ProcessGroupAdapterError.launchFailed(errno: errno)
        }
        createdFileNames.append(name)
        try bind(descriptor: descriptor, target: target)
      } else {
        try addNull(target: target, flags: O_WRONLY)
      }
    }
    succeeded = true
    return OpenedProcessIO(
      descriptors: descriptors,
      directoryDescriptor: directoryFD,
      createdFileNames: createdFileNames
    )
  }

  private static func inputArtifactMatches(
    descriptor: Int32,
    expected: KernelProviderPromptArtifactReceipt
  ) -> Bool {
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_nlink == 1,
      UInt64(bitPattern: Int64(status.st_dev)) == expected.deviceID,
      UInt64(status.st_ino) == expected.inode,
      UInt64(status.st_size) == expected.byteCount,
      Darwin.lseek(descriptor, 0, SEEK_SET) == 0
    else {
      return false
    }
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if count > 0 {
        hasher.update(data: Data(buffer.prefix(count)))
      } else if count == 0 {
        break
      } else if errno == EINTR {
        continue
      } else {
        return false
      }
    }
    guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { return false }
    let observed = ContentDigest(
      hasher.finalize().map { String(format: "%02x", $0) }.joined()
    )
    return observed == expected.contentDigest
  }

  private static func inputArtifactMatches(
    descriptor: Int32,
    expected: ExternalDependencyObservationRequestArtifactReceipt
  ) -> Bool {
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      status.st_mode & 0o222 == 0,
      UInt64(bitPattern: Int64(status.st_dev)) == expected.deviceID,
      UInt64(status.st_ino) == expected.inode,
      UInt64(status.st_size) == expected.byteCount,
      Darwin.lseek(descriptor, 0, SEEK_SET) == 0
    else {
      return false
    }
    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if count > 0 {
        hasher.update(data: Data(buffer.prefix(count)))
      } else if count == 0 {
        break
      } else if errno == EINTR {
        continue
      } else {
        return false
      }
    }
    guard Darwin.lseek(descriptor, 0, SEEK_SET) == 0 else { return false }
    let observed = ContentDigest(
      hasher.finalize().map { String(format: "%02x", $0) }.joined()
    )
    return observed == expected.contentDigest
  }

  /// Deletes only entries created relative to the still-open directory
  /// descriptor. Re-resolving the supplied directory path here would permit
  /// a rename/replacement race to redirect cleanup into an unrelated tree.
  nonisolated static func removeCreatedFiles(
    directoryDescriptor: Int32,
    fileNames: [String]
  ) {
    guard directoryDescriptor >= 0 else { return }
    for name in fileNames where validIOFileName(name) {
      _ = name.withCString {
        Darwin.unlinkat(directoryDescriptor, $0, 0)
      }
    }
  }

  nonisolated private static func validIOFileName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
      && name.precomposedStringWithCanonicalMapping == name
  }

  private static func signalProcessGroup(_ groupID: pid_t, signal: Int32) {
    guard groupID > 0 else { return }
    _ = Darwin.kill(-groupID, signal)
  }

  private static func deadline(after nanoseconds: UInt64) -> UInt64 {
    let now = DispatchTime.now().uptimeNanoseconds
    let (deadline, overflow) = now.addingReportingOverflow(nanoseconds)
    return overflow ? UInt64.max : deadline
  }

  private static func waitForProcessGroupToDisappear(
    _ groupID: pid_t,
    deadline: UInt64
  ) async -> Bool {
    var backoff: UInt64 = 5_000_000
    while processGroupExists(groupID) {
      let now = DispatchTime.now().uptimeNanoseconds
      guard now < deadline else { return false }
      let remaining = deadline - now
      try? await Task.sleep(nanoseconds: min(backoff, remaining))
      backoff = min(backoff * 2, 100_000_000)
    }
    return true
  }

  private static func processGroupExists(_ groupID: pid_t) -> Bool {
    guard groupID > 0 else { return false }
    if Darwin.kill(-groupID, 0) == 0 { return true }
    return errno == EPERM
  }

  private static func systemProcessIdentity(
    processID: pid_t
  ) -> SystemProcessIdentity? {
    guard processID > 0 else { return nil }
    var info = proc_bsdinfo()
    let expectedSize = MemoryLayout<proc_bsdinfo>.size
    let readSize = withUnsafeMutablePointer(to: &info) { pointer in
      proc_pidinfo(
        processID,
        PROC_PIDTBSDINFO,
        0,
        UnsafeMutableRawPointer(pointer),
        Int32(expectedSize)
      )
    }
    guard readSize == Int32(expectedSize),
      info.pbi_pid == UInt32(processID),
      info.pbi_pgid <= UInt32(Int32.max)
    else {
      return nil
    }
    let (seconds, secondsOverflow) = info.pbi_start_tvsec
      .multipliedReportingOverflow(by: 1_000_000_000)
    let (microseconds, microsecondsOverflow) = info.pbi_start_tvusec
      .multipliedReportingOverflow(by: 1_000)
    let (start, additionOverflow) = seconds.addingReportingOverflow(microseconds)
    guard !secondsOverflow, !microsecondsOverflow, !additionOverflow else {
      return nil
    }
    return SystemProcessIdentity(
      processID: processID,
      processGroupID: Int32(info.pbi_pgid),
      startSystemNanoseconds: start
    )
  }

  private static func processStatus(processID: pid_t) -> UInt32? {
    guard processID > 0 else { return nil }
    var info = proc_bsdinfo()
    let expectedSize = MemoryLayout<proc_bsdinfo>.size
    let readSize = withUnsafeMutablePointer(to: &info) { pointer in
      proc_pidinfo(
        processID,
        PROC_PIDTBSDINFO,
        0,
        UnsafeMutableRawPointer(pointer),
        Int32(expectedSize)
      )
    }
    guard readSize == Int32(expectedSize),
      info.pbi_pid == UInt32(processID)
    else {
      return nil
    }
    return info.pbi_status
  }

  private static func processWorkingDirectoryIdentity(
    processID: pid_t
  ) -> (deviceID: UInt64, inode: UInt64)? {
    guard processID > 0 else { return nil }
    var info = proc_vnodepathinfo()
    let expectedSize = MemoryLayout<proc_vnodepathinfo>.size
    let readSize = withUnsafeMutablePointer(to: &info) { pointer in
      proc_pidinfo(
        processID,
        PROC_PIDVNODEPATHINFO,
        0,
        UnsafeMutableRawPointer(pointer),
        Int32(expectedSize)
      )
    }
    guard readSize == Int32(expectedSize) else { return nil }
    let status = info.pvi_cdir.vip_vi.vi_stat
    return (UInt64(status.vst_dev), UInt64(status.vst_ino))
  }

  private static func identityDigest(
    specification: ManagedProcessSpecification,
    processID: pid_t,
    startedAtSystemNanoseconds: UInt64
  ) -> ContentDigest {
    let executableDigest = specification.expectedExecutableContentDigest?.rawValue ?? ""
    let environmentDigest = specification.expectedEnvironmentContentDigest?.rawValue ?? ""
    let argumentVectorDigest = specification.expectedArgumentVectorContentDigest?.rawValue ?? ""
    let argumentZero = specification.executableArgumentZero ?? ""
    let sandboxMaterial =
      specification.nativeSandbox.map {
        "\($0.receipt.launcherContentDigest.rawValue)\u{0}\($0.receipt.gateExecutableContentDigest.rawValue)\u{0}\($0.receipt.profileDigest.rawValue)\u{0}\($0.receipt.parameterDigest.rawValue)"
      } ?? ""
    let resourceMaterial =
      specification.kernelResourceLimits.map {
        "\($0.maximumOutputFileBytes)\u{0}\($0.maximumProcessCount)"
      } ?? ""
    let material =
      "\(specification.executablePath)\u{0}\(argumentZero)\u{0}\(executableDigest)\u{0}\(environmentDigest)\u{0}\(argumentVectorDigest)\u{0}\(sandboxMaterial)\u{0}\(resourceMaterial)\u{0}\(processID)\u{0}\(startedAtSystemNanoseconds)"
    let hash = SHA256.hash(data: Data(material.utf8))
    return ContentDigest(hash.map { String(format: "%02x", $0) }.joined())
  }

}

private final class ProcessExitLatch: @unchecked Sendable {
  private struct Waiter {
    var continuation: CheckedContinuation<ManagedProcessExitReceipt?, Never>
    var timeout: DispatchWorkItem?
  }

  private let lock = NSLock()
  private let processID: pid_t
  private let handle: ManagedProcessHandle
  private let ownsChild: Bool
  private let source: DispatchSourceProcess
  private var exitReceipt: ManagedProcessExitReceipt?
  private var waiters: [UUID: Waiter] = [:]

  init(processID: pid_t, handle: ManagedProcessHandle, ownsChild: Bool) {
    self.processID = processID
    self.handle = handle
    self.ownsChild = ownsChild
    source = DispatchSource.makeProcessSource(
      identifier: processID,
      eventMask: .exit,
      queue: DispatchQueue.global(qos: .utility)
    )
    source.setEventHandler { [weak self] in self?.reap() }
    source.resume()
  }

  func invalidate() {
    source.cancel()
  }

  func wait(timeoutNanoseconds: UInt64) async -> ManagedProcessExitReceipt? {
    await withCheckedContinuation { continuation in
      lock.lock()
      if let exitReceipt {
        lock.unlock()
        continuation.resume(returning: exitReceipt)
        return
      }
      let id = UUID()
      let timeout = DispatchWorkItem { [weak self] in self?.expire(id: id) }
      waiters[id] = Waiter(continuation: continuation, timeout: timeout)
      lock.unlock()
      DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + .nanoseconds(Int(clamping: timeoutNanoseconds)),
        execute: timeout
      )
    }
  }

  private func reap() {
    var status: Int32 = 0
    let waited = ownsChild ? waitpid(processID, &status, 0) : 0
    guard !ownsChild || waited == processID else { return }
    let low = status & 0x7f
    let receipt = ManagedProcessExitReceipt(
      handle: handle,
      observedAtMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
      exitCode: ownsChild && low == 0 ? (status >> 8) & 0xff : nil,
      terminationSignal: ownsChild && low != 0 ? low : nil
    )

    lock.lock()
    guard exitReceipt == nil else {
      lock.unlock()
      return
    }
    exitReceipt = receipt
    let pending = waiters.values
    waiters.removeAll()
    lock.unlock()
    for waiter in pending {
      waiter.timeout?.cancel()
      waiter.continuation.resume(returning: receipt)
    }
    source.cancel()
  }

  private func expire(id: UUID) {
    lock.lock()
    guard let waiter = waiters.removeValue(forKey: id) else {
      lock.unlock()
      return
    }
    lock.unlock()
    waiter.continuation.resume(returning: nil)
  }
}

private func withMutableCStringArray<Result>(
  _ strings: [String],
  _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
) throws -> Result {
  let allocated: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
  defer { allocated.forEach { free($0) } }
  guard allocated.allSatisfy({ $0 != nil }) else {
    throw ProcessGroupAdapterError.launchFailed(errno: ENOMEM)
  }
  var pointers = allocated + [nil]
  return try pointers.withUnsafeMutableBufferPointer { buffer in
    try body(buffer.baseAddress!)
  }
}
