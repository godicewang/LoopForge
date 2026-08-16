import CryptoKit
import Foundation

enum KernelProductionExecutionCompositionError: Error, Equatable {
  case invalidEnrollment
  case actorBoundaryMismatch
  case registrationMismatch
  case preApplyCandidateIsolationAuthorityMissing
  case supervisorRestoreRejected
  case providerLaunchMissing
  case leaseAdmissionMissing
  case completedCandidateCaptureUnauthorized
  case completedCandidateCaptureAlreadyIssued
  case completedCandidateDerivationRejected(
    WorkspaceMutationOperationDerivationError
  )
  case externalDependencyObservationRequestInvalid
  case postimageVerifierLaunchRequestInvalid
  case postimageVerifierContainmentAuthorityMismatch
  case postimageVerifierLaunchVetoReceiptMismatch
  case mutationApplyPreparationRequestInvalid
  case mutationApplyContainmentAuthorityMismatch
  case mutationApplyVetoReceiptMismatch
}

enum KernelNativeExecutionReadinessError: Error, Equatable {
  case invalidEnrollment
  case registrationMismatch
  case journalIdentityMismatch
  case recoveredEnrollmentUnavailable
}

enum KernelNativeExecutionStartError: Error, Equatable {
  case authorityBlocked([KernelNativeExecutionAuthorityBlocker])
  case invalidRequestIdentity
  case invalidRetainedAuthority
  case ambiguousInitialNode
  case designBaselineAuthorityMismatch
}

enum KernelNativeProviderInvocationPreparationError: Error, Equatable {
  case invalidRequestIdentity
  case invocationAlreadyPrepared
  case retainedExecutionMismatch
  case canonicalPromptEncodingFailed
}

/// Code-owned protocol instructions wrapped around the unchanged ratified
/// contract. These constraints narrow execution and describe the parser's
/// exact accepted output; they cannot add a requirement, capability, writable
/// path, strategy, or budget.
struct KernelNativeWorkerOutputProtocol: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var encoding: String
  var invocationDigestSource: String
  var requestNonceSource: String
  var eventShape: String
  var terminalShape: String
  var terminalRequired: Bool
  var standardOutputMayContainOtherBytes: Bool
}

/// Canonical, journal-derived productive input for one native attempt. The
/// application never accepts arbitrary provider prompt text at this boundary.
/// Every authoritative field is copied from the active journal or its exact
/// non-Codable execution proof.
struct KernelNativeProviderPromptEnvelope: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var instructions: [String]
  var sourceJournalSequence: UInt64
  var sourceJournalFrameDigest: ContentDigest
  var activationJournalFrameDigest: ContentDigest
  var runID: KernelRunID
  var attemptID: AttemptID
  var nodeID: KernelNodeID
  var strategyFingerprint: StrategyFingerprint
  var workspaceRootPath: String
  var contract: TaskContract
  var plan: KernelPlanProposal
  var admission: AttemptAdmissionRequest
  var workerExecutionProfile: KernelAgentExecutionProfile
  var requestNonce: ContentDigest
  var outputProtocol: KernelNativeWorkerOutputProtocol
}

/// Opaque identities minted only by one explicit native start action. The
/// identifiers provide replay protection; all executable strategy, plan,
/// budget, evidence, profile, and workspace authority remains sourced from
/// the exact enrolled journal.
struct KernelNativeExecutionStartRequest: Sendable {
  var enrollment: KernelRunEnrollmentReceipt
  var designBaseline: AuthorizedKernelDesignBaseline?
  var requestNonce: String
  var initiatedAt: Date
}

/// Authority that is intentionally absent from a bare enrollment receipt.
/// These are not inferred from the objective, workspace scope, or model
/// profile because doing so would let the application manufacture executable
/// strategy and mutation authority after the user's confirmation.
enum KernelNativeExecutionAuthorityBlocker: String, Codable, CaseIterable,
  Hashable, Sendable
{
  case evidenceRecipeProvenanceMissing
  case causalStrategyAuthorityMissing
  case mutationBudgetAuthorityMissing
  case convergenceBudgetAuthorityMissing
  case executionPlanAuthorityMissing
  case designBaselineAuthorityMissing
  case preApplyCandidateIsolationAuthorityMissing
  case journaledMutationPreparationAuthorityMissing

  var displaySummary: String {
    switch self {
    case .evidenceRecipeProvenanceMissing:
      return "The enrolled journal does not retain the confirmed evidence recipe."
    case .causalStrategyAuthorityMissing:
      return "No causal strategy and falsification predicates are authorized."
    case .mutationBudgetAuthorityMissing:
      return "No changed-file or changed-byte mutation budget is authorized."
    case .convergenceBudgetAuthorityMissing:
      return "No attempt, strategy, verification, or damage budget is authorized."
    case .executionPlanAuthorityMissing:
      return "No requirement-owned execution plan has been issued."
    case .designBaselineAuthorityMissing:
      return
        "The protected design baseline requires a fresh native confirmation capability."
    case .preApplyCandidateIsolationAuthorityMissing:
      return
        "No pre-apply isolated candidate workspace is authorized; the canonical workspace remains read-only."
    case .journaledMutationPreparationAuthorityMissing:
      return
        "No acyclic journal-owned manifest, preparation-fact, rollback-rehearsal, and preflight authority path is available."
    }
  }
}

struct KernelNativeExecutionReadinessAssessment: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var runID: KernelRunID
  var contractID: TaskContractID
  var sourceJournalSequence: UInt64
  var sourceJournalFrameDigest: ContentDigest
  var phase: KernelRunPhase
  var blockers: [KernelNativeExecutionAuthorityBlocker]
  /// This does not block journal activation. It makes the next provider
  /// boundary explicit without claiming prompt, transport, lease, or process
  /// launch authority.
  var providerInvocationProfileReadiness: KernelProviderInvocationProfileReadinessAssessment

  var canPrepareAndActivate: Bool { blockers.isEmpty }
}

/// The only production request that may cross from a ratified, enrolled run
/// into executable kernel state. It carries typed plan/admission authority but
/// no legacy task, Graph checkpoint, mutable timer, argv, environment, or
/// completion claim.
struct KernelProductionExecutionCompositionRequest: Sendable {
  var preparation: KernelExecutionPreparationRequest
  var startCommandID: RunCommandID
  var activatedAt: Date
  var preApplyCandidateIsolation: AuthorizedWorkspacePreApplyCandidateIsolation? = nil
}

struct KernelProductionProviderLaunchRequest: Sendable {
  var leaseID: ResourceLeaseID
  var resourceID: OwnedResourceID
  var occurrenceID: OccurrenceID?
  var reservation: ResourceVector
  var requestedAtMonotonicNanoseconds: UInt64
  var renewalDeadlineMonotonicNanoseconds: UInt64?
  var executablePath: String
  var standardOutputFileName: String
  var standardErrorFileName: String
  var admissionReceiptID: ReceiptID
  var admissionCommandID: RunCommandID
  var bindingReceiptID: ReceiptID
  var providerLaunchReceiptID: ReceiptID
  var bindingCommandID: RunCommandID
  var launchFailureReleaseReceiptID: ReceiptID
  var launchFailureReleaseCommandID: RunCommandID
}

struct KernelProductionProviderCompletionRequest: Sendable {
  var naturalExitTimeoutNanoseconds: UInt64
  var releaseReceiptID: ReceiptID
  var releaseCommandID: RunCommandID
  var parseReceiptID: ReceiptID
  var parseCommandID: RunCommandID
  var derivationReceiptID: ReceiptID
  var derivationCommandID: RunCommandID
}

struct KernelProductionProviderCompletionReceipt: Sendable {
  var release: JournaledProcessNaturalReleaseReceipt
  var parse: JournaledWorkerResultParseReceipt
  var execution: JournaledExecutionDerivationReceipt
}

/// One complete controller request for a ratified external dependency. The
/// caller chooses only opaque journal identities, the explicitly authorized
/// observer and executable path, and private output basenames. Process
/// parameters, timeouts, retained bytes, parsing, result mapping, release,
/// and observation content remain runtime-derived.
struct KernelProductionExternalDependencyObservationRequest: Sendable {
  var activation: ExternalDependencyObservationActivationRequest
  var readiness: ExternalDependencyObservationLaunchReadinessRequest
  var runtime: ExternalDependencyObservationRuntimeRequest
  var completion: ExternalDependencyObservationCompletionRequest
}

enum KernelProductionExternalDependencyObservationOutcome: Sendable {
  case vetoed(
    receipt: ExternalDependencyObservationLaunchVetoReceipt,
    transaction: JournalTransactionReceipt
  )
  case observed(JournaledExternalDependencyObservationCompletionReceipt)
}

/// A future privileged helper may resolve one live, activation-exact physical
/// resident-memory capability here. Ordinary-macOS production returns the
/// explicit terminal platform resolution and deterministically journals the
/// pre-admission veto. A decoded receipt cannot satisfy this closure's return
/// type.
typealias KernelExternalDependencyResidentMemoryEnforcementResolver =
  @Sendable (ExternalDependencyObservationActivationReceipt) async throws ->
  KernelResidentMemoryEnforcementResolution

/// One complete production-controller request for an exact applied-postimage
/// verifier. Activation remains journal-derived and the runtime request may
/// choose only opaque receipt/resource identities and private output names.
struct KernelProductionPostimageVerifierLaunchRequest: Sendable {
  var activation: KernelPostimageVerifierActivationRequest
  var runtime: KernelPostimageVerifierRuntimeRequest
}

/// A missing non-serializable containment capability is a durable terminal
/// outcome for this activation, not an exceptional hole a controller may
/// ignore and retry around. A launch returns only the journal/runtime-owned
/// start receipt needed by later completion or application cleanup.
enum KernelProductionPostimageVerifierLaunchOutcome: Sendable {
  case vetoed(
    activation: KernelPostimageVerifierActivationReceipt,
    activationTransaction: JournalTransactionReceipt,
    receipt: KernelPostimageVerifierLaunchVetoReceipt,
    transaction: JournalTransactionReceipt
  )
  case launched(JournaledPostimageVerifierStartReceipt)
}

/// A future privileged helper may resolve one activation-exact physical
/// resident-memory capability here. Ordinary-macOS production returns the
/// typed terminal platform resolution and the process runtime journals a
/// pre-admission veto. Decoded receipts cannot satisfy this closure's return
/// type.
typealias KernelPostimageVerifierResidentMemoryEnforcementResolver =
  @Sendable (KernelPostimageVerifierActivationReceipt) async throws ->
  KernelResidentMemoryEnforcementResolution

/// One exact production-controller request for the last pre-effect boundary.
/// The live preflight remains non-Codable and journal-bound. The caller may
/// choose only opaque identities for the durable containment veto and the
/// already bounded apply-preparation request.
struct KernelProductionMutationApplyPreparationRequest: Sendable {
  var preparation: WorkspaceCompletedCandidateMutationApplyPreparationRequest
  var containmentVetoReceiptID: ReceiptID
  var containmentVetoCommandID: RunCommandID
}

enum KernelProductionMutationApplyPreparationOutcome: Sendable {
  case vetoed(
    receipt: KernelProductionMutationApplyVetoReceipt,
    transaction: JournalTransactionReceipt
  )
  case prepared(WorkspaceCompletedCandidateMutationApplyPreparationInstallation)
}

/// A future privileged helper or container may prove that every exact
/// contract recipe has an installable pre-exec physical-memory boundary.
/// Ordinary-macOS production returns the typed terminal platform resolution
/// and journals a pre-effect veto.
typealias KernelPostimageContainmentReadinessResolver =
  @Sendable (
    KernelRunID,
    IntegrationTransactionID,
    TaskContract
  ) async throws -> KernelPostimageContainmentReadinessResolution

private let kernelOrdinaryMacOSExternalDependencyResolution:
  KernelExternalDependencyResidentMemoryEnforcementResolver = { _ in
    .ordinaryMacOSUnavailable
  }

private let kernelOrdinaryMacOSPostimageVerifierResolution:
  KernelPostimageVerifierResidentMemoryEnforcementResolver = { _ in
    .ordinaryMacOSUnavailable
  }

private let kernelOrdinaryMacOSContractReadinessResolution:
  KernelPostimageContainmentReadinessResolver = { _, _, _ in
    .ordinaryMacOSUnavailable
  }

enum KernelProductionMutationApplyVetoReason: String, Codable, Hashable,
  Sendable
{
  case ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit =
    "containmentReadinessUnavailable"
}

/// Durable causal evidence that canonical mutation was stopped before lease
/// admission, apply intent, outbox persistence, or filesystem effects. It is
/// not an apply failure or a verification result and grants no transition.
struct KernelProductionMutationApplyVetoReceipt: Codable, Hashable, Sendable {
  var schemaVersion: Int
  var id: ReceiptID
  var runID: KernelRunID
  var integrationTransactionID: IntegrationTransactionID
  var preflightReceiptID: ReceiptID
  var contractID: TaskContractID
  var contractDigest: ContentDigest
  var requirements: [KernelPostimageContainmentRequirement]
  var reason: KernelProductionMutationApplyVetoReason
  var actor: ActorIdentity
  var sourceJournalSequence: UInt64
  var observedAt: Date
}

/// File-owned proof that only the production coordinator can ask the reducer
/// to retain a mutation-preparation veto.
private struct KernelProductionMutationApplyVetoCommandIssuer: Sendable {
  init() {}
}

struct AuthorizedKernelProductionMutationApplyVeto: Sendable {
  let receipt: KernelProductionMutationApplyVetoReceipt

  private init(receipt: KernelProductionMutationApplyVetoReceipt) {
    self.receipt = receipt
  }

  fileprivate static func issuedByProductionCoordinator(
    receipt: KernelProductionMutationApplyVetoReceipt,
    issuer: KernelProductionMutationApplyVetoCommandIssuer
  ) -> Self {
    Self(receipt: receipt)
  }
}

enum KernelProductionMutationApplyVetoCompiler {
  static func validationIssue(
    _ receipt: KernelProductionMutationApplyVetoReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.schemaVersion == 1,
      receipt.runID == state.runID,
      receipt.actor == actor,
      receipt.observedAt == occurredAt,
      receipt.sourceJournalSequence == state.sequence,
      receipt.reason
        == .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
      !receipt.id.rawValue.isEmpty,
      state.phase == .evaluating,
      state.runtimeFailedReleases.isEmpty,
      let contract = state.contract,
      receipt.contractID == contract.id,
      receipt.contractDigest == contract.objectiveDigest,
      let expectedRequirements =
        AuthorizedKernelPostimageContainmentReadiness
        .requiredRequirements(contract),
      !expectedRequirements.isEmpty,
      receipt.requirements == expectedRequirements,
      let integration = state.integrationTransactions[
        receipt.integrationTransactionID
      ],
      integration.phase == .rollbackPrepared,
      integration.preflightReceipt?.id == receipt.preflightReceiptID,
      !(state.productionMutationApplyVetoReceipts ?? [:]).values.contains(
        where: {
          $0.integrationTransactionID == receipt.integrationTransactionID
        }
      )
    else {
      return "production mutation apply veto provenance mismatch"
    }
    return nil
  }
}

/// Inert, content-complete proposal evidence produced only from the session's
/// retained descriptor after successful natural release and reducer-derived
/// completion. It does not authorize a manifest, preflight, or apply.
struct KernelProductionCompletedCandidateProposal: Sendable {
  var capture: AuthorizedWorkspaceCompletedCandidateCapture
  var derivation: WorkspaceMutationOperationDerivationReceipt
  var journalTransaction: JournalTransactionReceipt
}

struct KernelProductionExecutionSessionReceipt: Sendable {
  var preparation: KernelExecutionPreparationReceipt
  var activationTransaction: JournalTransactionReceipt
  var kernelProjection: KernelRunProjection
  var preApplyCandidateIsolation: WorkspacePreApplyCandidateIsolationReceipt?
  var providerInvocationProfileReadiness: KernelProviderInvocationProfileReadinessAssessment
}

enum KernelProductionExecutionTerminationError: Error, Equatable, Sendable {
  case invalidRequestIdentity
  case cleanupRequired(Int)
  case terminalRunNotQuiescent(KernelRunPhase)
  case finalProjectionInvalid(KernelRunPhase)
}

enum KernelRecoveredApplicationTerminationError: Error, Equatable, Sendable {
  case recoveryUnavailable
  case supervisorRestoreRejected
}

/// The deliberately narrow capability retained by the application solely to
/// prove and perform native cleanup before process exit. Productive sessions
/// conform, while relaunch recovery can reconstruct a separate implementation
/// that has no provider, mutation, review, retry, or completion methods.
protocol KernelApplicationTerminationSession: Actor {
  func runtimeCleanupPlan() async -> [RuntimeCleanupAction]
  func applicationTerminationCleanupIsExecutable() async -> Bool
  func kernelProjection() async -> KernelRunProjection
  func prepareForApplicationTermination(
    requestNonce: String
  ) async throws -> KernelRunProjection
}

/// One implementation for both continuously retained and relaunch-recovered
/// cleanup capabilities. Keeping the journal transition sequence shared
/// prevents the recovery path from becoming a weaker lifecycle fork.
private func prepareKernelApplicationTermination(
  runtime: JournaledProcessRuntime,
  lifecycle: JournaledRuntimeLifecycleAuthority,
  supervisor: RuntimeSupervisor,
  journal: RunJournal,
  requestNonce: String,
  origin: JournaledApplicationTerminationCleanupOrigin
) async throws -> KernelRunProjection {
  guard requestNonce == requestNonce.lowercased(),
    UUID(uuidString: requestNonce) != nil
  else {
    throw KernelProductionExecutionTerminationError.invalidRequestIdentity
  }
  var projection = await journal.currentProjection()
  if projection.phase.isTerminal {
    guard projection.quiescent else {
      throw
        KernelProductionExecutionTerminationError
        .terminalRunNotQuiescent(projection.phase)
    }
    return projection
  }

  let drainRequest = JournaledRuntimeDrainRequest(
    intent: .stop,
    lifecycleCommandID: RunCommandID(
      "\(origin.commandPrefix)-\(requestNonce)-request"
    ),
    drainReceiptID: ReceiptID(
      "\(origin.commandPrefix)-\(requestNonce)-drain"
    ),
    drainCommandID: RunCommandID(
      "\(origin.commandPrefix)-\(requestNonce)-record-drain"
    )
  )
  let cleanupPlan: [RuntimeCleanupAction]
  if projection.phase == .stopRequested {
    if projection.runtimeDrainIntent == nil {
      let drain = try await lifecycle.resumeRetainedStopDrain(drainRequest)
      cleanupPlan = drain.cleanupPlan
    } else if projection.runtimeDrainIntent != .stop {
      throw
        KernelProductionExecutionTerminationError
        .finalProjectionInvalid(projection.phase)
    } else {
      cleanupPlan = await supervisor.cleanupPlan()
    }
  } else {
    let drain = try await lifecycle.requestDrain(drainRequest)
    cleanupPlan = drain.cleanupPlan
  }
  if !cleanupPlan.isEmpty {
    let cleanup = try await runtime.executeApplicationTerminationCleanup(
      expectedPlan: cleanupPlan,
      requestNonce: requestNonce,
      origin: origin
    )
    guard cleanup.remainingActions.isEmpty,
      cleanup.plannedActions == cleanupPlan,
      cleanup.releaseReceiptIDs.count == cleanupPlan.count
    else {
      throw KernelProductionExecutionTerminationError.cleanupRequired(
        cleanup.remainingActions.count
      )
    }
  }

  _ = try await lifecycle.recordQuiescence(
    JournaledRuntimeQuiescenceRequest(
      receiptID: ReceiptID(
        "\(origin.commandPrefix)-\(requestNonce)-quiescence"
      ),
      commandID: RunCommandID(
        "\(origin.commandPrefix)-\(requestNonce)-record-quiescence"
      )
    )
  )
  projection = await journal.currentProjection()
  guard projection.phase == .stopped, projection.quiescent else {
    throw
      KernelProductionExecutionTerminationError
      .finalProjectionInvalid(projection.phase)
  }
  return projection
}

/// Non-Codable live composition capability. The raw runtime and activation
/// proof never escape, so production controllers cannot swap leases, result
/// digests, nonces, or execution dispositions between lifecycle stages.
actor KernelProductionExecutionSession: KernelApplicationTerminationSession {
  let receipt: KernelProductionExecutionSessionReceipt

  private let runtime: JournaledProcessRuntime
  private let lifecycle: JournaledRuntimeLifecycleAuthority
  private let supervisor: RuntimeSupervisor
  private let journal: RunJournal
  private let completionCoordinator: JournaledKernelCompletionCoordinator
  private let visualEvaluationCoordinator: JournaledNativeVisualEvaluationCoordinator
  private let executionProof: JournaledKernelExecutionProof
  private let candidateExecutionRoot: AuthorizedWorkspacePreApplyCandidateExecutionRoot?
  private var completedCandidateCaptureIssued = false
  private var nativeProviderInvocationPrepared = false

  fileprivate init(
    preparation: KernelExecutionPreparationReceipt,
    activation: KernelExecutionActivationReceipt,
    runtime: JournaledProcessRuntime,
    lifecycle: JournaledRuntimeLifecycleAuthority,
    supervisor: RuntimeSupervisor,
    journal: RunJournal,
    candidateExecutionRoot:
      AuthorizedWorkspacePreApplyCandidateExecutionRoot?,
    providerInvocationProfileReadiness:
      KernelProviderInvocationProfileReadinessAssessment
  ) {
    receipt = KernelProductionExecutionSessionReceipt(
      preparation: preparation,
      activationTransaction: activation.journalTransaction,
      kernelProjection: activation.kernelProjection,
      preApplyCandidateIsolation:
        candidateExecutionRoot?.receipt,
      providerInvocationProfileReadiness:
        providerInvocationProfileReadiness
    )
    self.runtime = runtime
    self.lifecycle = lifecycle
    self.supervisor = supervisor
    self.journal = journal
    completionCoordinator = JournaledKernelCompletionCoordinator(
      journal: journal
    )
    visualEvaluationCoordinator = JournaledNativeVisualEvaluationCoordinator(
      journal: journal
    )
    executionProof = activation.proof
    self.candidateExecutionRoot = candidateExecutionRoot
  }

  /// Creates the sole provider prompt from the active journal. The caller may
  /// choose only a fresh UUID used for replay protection and file identity;
  /// objective text, plan, strategy, profile, workspace, output protocol, and
  /// authority all remain exact session-owned values.
  func prepareNativeProviderInvocation(
    requestNonce: String
  ) async throws -> AuthorizedKernelProviderInvocation {
    guard requestNonce == requestNonce.lowercased(),
      UUID(uuidString: requestNonce) != nil
    else {
      throw KernelNativeProviderInvocationPreparationError.invalidRequestIdentity
    }
    guard !nativeProviderInvocationPrepared else {
      throw KernelNativeProviderInvocationPreparationError.invocationAlreadyPrepared
    }

    let invocationNonce = Self.providerRequestDigest(
      requestNonce: requestNonce,
      executionProof: executionProof
    )
    // Reject known transport/profile mismatches before creating an immutable
    // prompt artifact. Authorization is repeated by the runtime after the
    // artifact exists, so this is defense in depth rather than a substitute.
    try KernelProviderInvocationCompiler().validateExecution(
      executionProof: executionProof,
      requestNonce: invocationNonce
    )

    let state = await journal.state
    let recovery = await journal.recoveryReport
    guard state.phase == .executing,
      state.sequence == receipt.kernelProjection.sequence,
      recovery.lastFrameDigest == receipt.activationTransaction.frameDigest,
      let sourceFrameDigest = recovery.lastFrameDigest,
      let contract = state.contract,
      contract.id == receipt.preparation.contractID,
      contract.executionProfile?.worker == executionProof.workerExecutionProfile,
      state.activeAttemptID == executionProof.attemptID,
      let attempt = state.attempts[executionProof.attemptID],
      attempt.id == executionProof.attemptID,
      attempt.nodeID == executionProof.nodeID,
      attempt.strategyFingerprint == executionProof.strategyFingerprint,
      attempt.disposition == nil,
      let node = receipt.preparation.plan.nodes.first(where: {
        $0.id == executionProof.nodeID
      }),
      state.nodes[executionProof.nodeID]?.contract == node,
      state.nodes[executionProof.nodeID]?.status == .executing,
      receipt.preparation.admission.attemptID == executionProof.attemptID,
      receipt.preparation.admission.strategy.fingerprint
        == executionProof.strategyFingerprint,
      (state.providerLaunchReceipts ?? [:]).isEmpty,
      state.runtimeLiveLeases.isEmpty
    else {
      throw KernelNativeProviderInvocationPreparationError.retainedExecutionMismatch
    }

    let prompt = KernelNativeProviderPromptEnvelope(
      schemaVersion: 1,
      instructions: [
        "Treat only the enclosed ratified contract, plan, admission, workspace, and execution profile as authority.",
        "Do not expand writable paths, capabilities, strategy, budgets, network, plugins, or external effects.",
        "Do not delegate or create hidden fan-out.",
        "Write only canonical JSON Lines accepted by the enclosed output protocol to standard output; send diagnostics only to standard error.",
      ],
      sourceJournalSequence: state.sequence,
      sourceJournalFrameDigest: sourceFrameDigest,
      activationJournalFrameDigest: receipt.activationTransaction.frameDigest,
      runID: executionProof.runID,
      attemptID: executionProof.attemptID,
      nodeID: executionProof.nodeID,
      strategyFingerprint: executionProof.strategyFingerprint,
      workspaceRootPath: executionProof.workspaceRoot.path,
      contract: contract,
      plan: receipt.preparation.plan,
      admission: receipt.preparation.admission,
      workerExecutionProfile: executionProof.workerExecutionProfile,
      requestNonce: invocationNonce,
      outputProtocol: KernelNativeWorkerOutputProtocol(
        schemaVersion: 1,
        encoding: "utf-8-canonical-sorted-key-jsonl-with-final-lf",
        invocationDigestSource:
          "kernel-owned-canonical-json-context-fd:196",
        requestNonceSource:
          "kernel-owned-canonical-json-context-fd:196",
        eventShape:
          "schemaVersion,type=event,sequence,threadID,invocationDigest,requestNonce,payloadDigest",
        terminalShape:
          "schemaVersion,type=terminal,sequence,threadID,invocationDigest,requestNonce,proposedDisposition,resultDigest",
        terminalRequired: true,
        standardOutputMayContainOtherBytes: false
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard var promptData = try? encoder.encode(prompt) else {
      throw KernelNativeProviderInvocationPreparationError
        .canonicalPromptEncodingFailed
    }
    promptData.append(0x0a)
    let authorization = try await runtime.prepareProviderInvocation(
      prompt: promptData,
      promptFileName: "native-provider-\(requestNonce).json",
      requestNonce: invocationNonce
    )
    nativeProviderInvocationPrepared = true
    return authorization
  }

  private static func providerRequestDigest(
    requestNonce: String,
    executionProof: JournaledKernelExecutionProof
  ) -> ContentDigest {
    let material = [
      "loopforge.kernel.native-provider-request.v1",
      requestNonce,
      executionProof.runID.rawValue,
      executionProof.attemptID.rawValue,
      executionProof.nodeID.rawValue,
      executionProof.strategyFingerprint.rawValue,
      executionProof.activationTransaction.frameDigest.rawValue,
    ].joined(separator: "\u{1f}")
    return ContentDigest(
      SHA256.hash(data: Data(material.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
    )
  }

  func issueProviderSecret(
    for invocation: AuthorizedKernelProviderInvocation,
    lifetimeNanoseconds: UInt64
  ) throws -> KernelProviderSecretCapability {
    try KernelProviderSecretIssuer().issueStoredCredential(
      for: invocation,
      executionProof: executionProof,
      lifetimeNanoseconds: lifetimeNanoseconds
    )
  }

  func launchProvider(
    _ request: KernelProductionProviderLaunchRequest,
    invocation: AuthorizedKernelProviderInvocation,
    secretCapability: KernelProviderSecretCapability?
  ) async throws -> JournaledProcessStartReceipt {
    let leaseRequest = RuntimeLeaseRequest(
      leaseID: request.leaseID,
      resourceID: request.resourceID,
      runID: executionProof.runID,
      occurrenceID: request.occurrenceID,
      attemptID: executionProof.attemptID,
      kind: .processTree,
      purpose: .productive,
      ownership: .owned,
      releasePolicy: .gracefulThenTerminate,
      externalIdentity: nil,
      reservation: request.reservation,
      requestedAtMonotonicNanoseconds:
        request.requestedAtMonotonicNanoseconds,
      renewalDeadlineMonotonicNanoseconds:
        request.renewalDeadlineMonotonicNanoseconds,
      progressReceiptID: nil
    )
    return try await runtime.admitAndLaunchProvider(
      request: leaseRequest,
      executablePath: request.executablePath,
      invocation: invocation,
      secretCapability: secretCapability,
      standardOutputFileName: request.standardOutputFileName,
      standardErrorFileName: request.standardErrorFileName,
      admissionReceiptID: request.admissionReceiptID,
      admissionCommandID: request.admissionCommandID,
      bindingReceiptID: request.bindingReceiptID,
      providerLaunchReceiptID: request.providerLaunchReceiptID,
      bindingCommandID: request.bindingCommandID,
      launchFailureReleaseReceiptID:
        request.launchFailureReleaseReceiptID,
      launchFailureReleaseCommandID:
        request.launchFailureReleaseCommandID
    )
  }

  /// Joins and derives the execution disposition exclusively from the
  /// journaled launch event and retained worker result. No caller-supplied
  /// lease, invocation digest, nonce, or disposition enters this boundary.
  func completeProviderExecution(
    start: JournaledProcessStartReceipt,
    request: KernelProductionProviderCompletionRequest
  ) async throws -> KernelProductionProviderCompletionReceipt {
    guard let launch = start.launch.providerLaunch else {
      throw KernelProductionExecutionCompositionError.providerLaunchMissing
    }
    guard case .accepted = start.admission.outcome else {
      throw KernelProductionExecutionCompositionError.leaseAdmissionMissing
    }
    let release = try await runtime.joinAndReleaseProvider(
      start: start,
      releaseReceiptID: request.releaseReceiptID,
      commandID: request.releaseCommandID,
      timeoutNanoseconds: request.naturalExitTimeoutNanoseconds
    )
    let parse = try await runtime.parseReleasedWorkerResult(
      start: start,
      release: release,
      invocationDigest: launch.invocation.invocationDigest,
      requestNonce: launch.invocation.requestNonce,
      receiptID: request.parseReceiptID,
      commandID: request.parseCommandID
    )
    let execution = try await runtime.deriveReleasedWorkerExecution(
      parse: parse,
      receiptID: request.derivationReceiptID,
      commandID: request.derivationCommandID
    )
    return KernelProductionProviderCompletionReceipt(
      release: release,
      parse: parse,
      execution: execution
    )
  }

  /// Production-controller composition for one external dependency. It
  /// activates the exact contract probe, resolves containment immediately
  /// before admission, and either returns the durable veto or performs the
  /// complete native launch-to-observation chain. No partial ready state or
  /// live process authority escapes this method.
  func observeExternalDependency(
    _ request: KernelProductionExternalDependencyObservationRequest,
    residentMemoryEnforcementResolver:
      KernelExternalDependencyResidentMemoryEnforcementResolver =
        kernelOrdinaryMacOSExternalDependencyResolution
  ) async throws -> KernelProductionExternalDependencyObservationOutcome {
    guard !request.activation.dependencyID.rawValue.isEmpty,
      request.readiness.observedAt >= request.activation.activatedAt
    else {
      throw KernelProductionExecutionCompositionError
        .externalDependencyObservationRequestInvalid
    }
    let invocation = try await ExternalDependencyObservationActivationCoordinator(journal: journal)
      .activate(request.activation)
    let observerRuntime = JournaledProcessRuntime(
      supervisor: supervisor,
      journal: journal,
      actorIdentity: request.activation.observer
    )
    let state = await journal.state
    let retainedLaunches =
      (state.externalDependencyObservationRuntimeLaunchReceipts ?? [:])
      .values.filter {
        $0.activationReceiptID == invocation.receipt.id
      }
    if let retainedLaunch = retainedLaunches.first {
      guard retainedLaunches.count == 1,
        retainedLaunch.id == request.runtime.launchReceiptID,
        retainedLaunch.resourceID == request.runtime.resourceID,
        retainedLaunch.leaseID == request.runtime.leaseID,
        retainedLaunch.bindingReceiptID == request.runtime.bindingReceiptID,
        retainedLaunch.processIOFiles.standardOutputFileName
          == request.runtime.standardOutputFileName,
        retainedLaunch.processIOFiles.standardErrorFileName == request.runtime.standardErrorFileName
      else {
        throw KernelProductionExecutionCompositionError
          .externalDependencyObservationRequestInvalid
      }
      let completion =
        try await observerRuntime
        .completeExternalDependencyObservation(
          launchReceiptID: retainedLaunch.id,
          request: request.completion
        )
      return .observed(completion)
    }
    let enforcement: AuthorizedKernelResidentMemoryEnforcement?
    switch try await residentMemoryEnforcementResolver(invocation.receipt) {
    case .unavailable(
      .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
    ):
      enforcement = nil
    case .authorized(let authority):
      enforcement = authority
    }
    let decision = try await ExternalDependencyObservationLaunchReadinessCoordinator(
      journal: journal
    ).evaluate(
      invocation: invocation,
      request: request.readiness,
      residentMemoryEnforcement: enforcement
    )
    switch decision {
    case .vetoed(let receipt, let transaction):
      return .vetoed(receipt: receipt, transaction: transaction)
    case .ready(let readiness):
      let start =
        try await observerRuntime
        .admitAndLaunchExternalDependencyObserver(
          readiness: readiness,
          request: request.runtime
        )
      let completion =
        try await observerRuntime
        .completeExternalDependencyObservation(
          launchReceiptID: start.observerLaunch.id,
          request: request.completion
        )
      return .observed(completion)
    }
  }

  /// Production-controller composition for one deterministic verifier. It
  /// activates the exact evidence recipe, resolves physical resident-memory
  /// containment immediately before admission, and returns either the exact
  /// durable veto or the native start receipt. The verifier uses its own
  /// journal actor while the session's exact runtime adapter retains the live
  /// process handle required for deterministic application cleanup.
  func launchPostimageVerifier(
    _ request: KernelProductionPostimageVerifierLaunchRequest,
    residentMemoryEnforcementResolver:
      KernelPostimageVerifierResidentMemoryEnforcementResolver =
        kernelOrdinaryMacOSPostimageVerifierResolution
  ) async throws -> KernelProductionPostimageVerifierLaunchOutcome {
    guard Self.postimageVerifierLaunchRequestIsValid(request) else {
      throw KernelProductionExecutionCompositionError
        .postimageVerifierLaunchRequestInvalid
    }
    let invocation = try await KernelPostimageVerifierActivationCoordinator(
      journal: journal
    ).activate(request.activation)

    if let retained = try await retainedPostimageVerifierLaunchVeto(
      invocation: invocation,
      request: request.runtime
    ) {
      return .vetoed(
        activation: invocation.receipt,
        activationTransaction: invocation.activationTransaction,
        receipt: retained.receipt,
        transaction: retained.transaction
      )
    }

    let enforcement: AuthorizedKernelResidentMemoryEnforcement?
    switch try await residentMemoryEnforcementResolver(invocation.receipt) {
    case .unavailable(
      .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
    ):
      enforcement = nil
    case .authorized(let authority):
      enforcement = authority
    }
    if let enforcement,
      !enforcement.authorizes(activation: invocation.receipt)
    {
      throw KernelProductionExecutionCompositionError
        .postimageVerifierContainmentAuthorityMismatch
    }
    do {
      let start = try await runtime.admitAndLaunchPostimageVerifier(
        invocation: invocation,
        request: request.runtime,
        residentMemoryEnforcementAuthority: enforcement,
        verifierExecutionActor: invocation.receipt.verifier
      )
      return .launched(start)
    } catch JournaledProcessRuntimeError
      .residentMemoryEnforcementUnavailable
    {
      guard
        let retained = try await retainedPostimageVerifierLaunchVeto(
          invocation: invocation,
          request: request.runtime
        )
      else {
        throw KernelProductionExecutionCompositionError
          .postimageVerifierLaunchVetoReceiptMismatch
      }
      return .vetoed(
        activation: invocation.receipt,
        activationTransaction: invocation.activationTransaction,
        receipt: retained.receipt,
        transaction: retained.transaction
      )
    }
  }

  private func retainedPostimageVerifierLaunchVeto(
    invocation: AuthorizedKernelPostimageVerifierInvocation,
    request: KernelPostimageVerifierRuntimeRequest
  ) async throws -> (
    receipt: KernelPostimageVerifierLaunchVetoReceipt,
    transaction: JournalTransactionReceipt
  )? {
    let state = await journal.state
    let matches = (state.postimageVerifierLaunchVetoReceipts ?? [:])
      .values.filter {
        $0.activationReceiptID == invocation.receipt.id
      }
    guard !matches.isEmpty else { return nil }
    guard matches.count == 1,
      let veto = matches.first,
      veto.id == request.launchVetoReceiptID,
      veto.runID == invocation.receipt.runID,
      veto.activationJournalFrameDigest
        == invocation.activationTransaction.frameDigest,
      veto.integrationTransactionID
        == invocation.receipt.integrationTransactionID,
      veto.applyReceiptID == invocation.receipt.applyReceiptID,
      veto.attemptID == invocation.receipt.attemptID,
      veto.evidenceRecipeID == invocation.receipt.evidenceRecipeID,
      veto.verifier == invocation.receipt.verifier,
      veto.requiredMaximumResidentBytes
        == invocation.receipt.resourceLimits.maximumResidentBytes,
      veto.reason
        == .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
      let transaction = await journal.transactionReceipt(
        commandID: request.launchVetoCommandID
      ),
      await journal.postimageVerifierLaunchVetoReceipt(
        transaction: transaction
      ) == veto
    else {
      throw KernelProductionExecutionCompositionError
        .postimageVerifierLaunchVetoReceiptMismatch
    }
    return (veto, transaction)
  }

  private static func postimageVerifierLaunchRequestIsValid(
    _ request: KernelProductionPostimageVerifierLaunchRequest
  ) -> Bool {
    let receiptIDs = [
      request.activation.receiptID,
      request.runtime.admissionReceiptID,
      request.runtime.bindingReceiptID,
      request.runtime.launchReceiptID,
      request.runtime.launchFailureReleaseReceiptID,
      request.runtime.launchVetoReceiptID,
    ]
    let commandIDs = [
      request.activation.commandID,
      request.runtime.admissionCommandID,
      request.runtime.bindingCommandID,
      request.runtime.launchFailureReleaseCommandID,
      request.runtime.launchVetoCommandID,
    ]
    return !request.activation.verifier.id.rawValue.isEmpty
      && !request.runtime.leaseID.rawValue.isEmpty
      && !request.runtime.resourceID.rawValue.isEmpty
      && !request.runtime.standardOutputFileName.isEmpty
      && !request.runtime.standardErrorFileName.isEmpty
      && request.runtime.standardOutputFileName
        != request.runtime.standardErrorFileName
      && receiptIDs.allSatisfy { !$0.rawValue.isEmpty }
      && Set(receiptIDs).count == receiptIDs.count
      && commandIDs.allSatisfy { !$0.rawValue.isEmpty }
      && Set(commandIDs).count == commandIDs.count
  }

  /// Converts completed worker output into exact logical delta evidence while
  /// retaining captured bytes in a non-Codable capability. Only the prepared
  /// node's requirement ownership and canonical writable paths may appear.
  func captureCompletedCandidateProposal(
    completion: KernelProductionProviderCompletionReceipt,
    captureCommandID: RunCommandID,
    capturedAt: Date
  ) async throws -> KernelProductionCompletedCandidateProposal {
    guard !completedCandidateCaptureIssued else {
      throw KernelProductionExecutionCompositionError
        .completedCandidateCaptureAlreadyIssued
    }
    guard let candidateExecutionRoot,
      completion.execution.execution.attemptID == executionProof.attemptID,
      completion.execution.execution.runID == executionProof.runID,
      capturedAt >= completion.execution.execution.derivedAt,
      await runtime.authorizesCompletedCandidateCapture(completion),
      let node = receipt.preparation.plan.nodes.first(where: {
        $0.id == executionProof.nodeID
      }),
      node.strategyFingerprint == executionProof.strategyFingerprint,
      node.requirementIDs
        == receipt.preparation.admission
        .strategy.requirementIDs
    else {
      throw KernelProductionExecutionCompositionError
        .completedCandidateCaptureUnauthorized
    }
    // One completed worker gets one immutable capture attempt. A rejected
    // delta must not become permission to mutate the same writable tree
    // out of band and retry under unchanged completion provenance.
    completedCandidateCaptureIssued = true
    let capture: AuthorizedWorkspaceCompletedCandidateCapture
    do {
      capture = try WorkspaceCandidatePostimageMaterializer()
        .captureCompletedCandidate(
          candidateExecutionRoot,
          completion: completion,
          captureActor: executionProof.activationActor,
          capturedAt: capturedAt
        )
    } catch {
      throw KernelProductionExecutionCompositionError
        .completedCandidateCaptureUnauthorized
    }
    let derivation: WorkspaceMutationOperationDerivationReceipt
    do {
      derivation = try WorkspaceMutationOperationDeriver().derive(
        base: candidateExecutionRoot.sourceRevision,
        candidate: capture.candidateRevision,
        requirementIDs: node.requirementIDs,
        authorizedPaths: node.mutationScope.writablePaths
      )
    } catch let error as WorkspaceMutationOperationDerivationError {
      throw
        KernelProductionExecutionCompositionError
        .completedCandidateDerivationRejected(error)
    }
    guard derivation.workspaceID == capture.receipt.workspaceID,
      derivation.canonicalRootDigest == capture.receipt.canonicalRootDigest,
      derivation.baseSourceRevision == capture.receipt.baseSourceRevision,
      derivation.candidateSourceRevision == capture.receipt.candidateSourceRevision,
      derivation.capturePolicyDigest == capture.receipt.capturePolicyDigest,
      Set(derivation.operations.compactMap(\.desiredPostimage))
        .isSubset(
          of: Set(
            capture.receipt.contentObjects.map(
              \.contentDigest
            )))
    else {
      throw KernelProductionExecutionCompositionError
        .completedCandidateCaptureUnauthorized
    }
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await runtime.recordCompletedCandidateCapture(
        capture,
        commandID: captureCommandID
      )
    } catch {
      throw KernelProductionExecutionCompositionError
        .completedCandidateCaptureUnauthorized
    }
    return KernelProductionCompletedCandidateProposal(
      capture: capture,
      derivation: derivation,
      journalTransaction: transaction
    )
  }

  func runtimeProjection() async -> JournaledProcessRuntimeProjection {
    await runtime.projection()
  }

  /// Read-only termination projection. A nonempty plan is not terminal; it is
  /// executable only when the process runtime still owns every exact handle or
  /// recoverable PID/start identity needed to mint durable release receipts.
  func runtimeCleanupPlan() async -> [RuntimeCleanupAction] {
    await supervisor.cleanupPlan()
  }

  func applicationTerminationCleanupIsExecutable() async -> Bool {
    await runtime.applicationTerminationCleanupIsExecutable()
  }

  func kernelProjection() async -> KernelRunProjection {
    await journal.currentProjection()
  }

  #if DEBUG
    /// Keeps test-only post-execution state transitions on the exact journal
    /// actor retained by this session. This prevents a second writer from
    /// manufacturing a stale in-memory fork while lifecycle tests assemble
    /// an applied-but-unverified verifier fixture.
    func testOnlyTransact(
      _ command: RunCommand,
      commandID: RunCommandID,
      issuedAt: Date,
      actor: ActorIdentity
    ) async throws -> JournalTransactionReceipt {
      try await journal.transactAtCurrentSequence(
        command,
        commandID: commandID,
        issuedAt: issuedAt,
        actor: actor
      )
    }

    /// Fault-injection seam for the exact crash window after the lifecycle
    /// request commits but before the runtime-drain frame is appended.
    func testOnlyRequestStopWithoutRuntimeDrain(
      commandID: RunCommandID,
      issuedAt: Date
    ) async throws {
      _ = try await journal.transactAtCurrentSequence(
        .requestStop,
        commandID: commandID,
        issuedAt: issuedAt,
        actor: executionProof.activationActor
      )
    }
  #endif

  /// Idempotent normal-quit boundary for one retained native session. A
  /// previously journaled stop request is resumed at quiescence instead of
  /// attempting an invalid second stop command after an interrupted quit.
  func prepareForApplicationTermination(
    requestNonce: String
  ) async throws -> KernelRunProjection {
    try await prepareKernelApplicationTermination(
      runtime: runtime,
      lifecycle: lifecycle,
      supervisor: supervisor,
      journal: journal,
      requestNonce: requestNonce,
      origin: .nativeQuit
    )
  }

  func requestRuntimeDrain(
    _ request: JournaledRuntimeDrainRequest
  ) async throws -> JournaledRuntimeDrainTransitionReceipt {
    try await lifecycle.requestDrain(request)
  }

  func recordRuntimeQuiescence(
    _ request: JournaledRuntimeQuiescenceRequest
  ) async throws -> JournaledRuntimeQuiescenceTransitionReceipt {
    try await lifecycle.recordQuiescence(request)
  }

  /// Consumes one live independent native-review authority and evaluates it
  /// against this session's exact non-Codable execution proof and retained
  /// journal. The caller cannot substitute the evaluator, attempt, start
  /// frame, command identity, requirement set, verdict, or evaluation time.
  func evaluateNativeVisualReview(
    _ review: AuthorizedNativeIndependentVisualReview
  ) async throws -> JournaledNativeVisualEvaluationReceipt {
    try await visualEvaluationCoordinator.evaluate(
      JournaledNativeVisualEvaluationRequest(
        execution: executionProof,
        review: review
      )
    )
  }

  /// Requests final completion only from the exact journal retained by this
  /// production execution session. The deterministic completion coordinator
  /// revalidates the current hash-journal head and all mandatory evidence,
  /// integration, visual, external-dependency, duration, and quiescence
  /// authority before it can append the authorization and completion frames.
  /// Missing or cross-wired authority therefore rejects without journal
  /// advance; no caller-provided completion claim enters this boundary.
  func authorizeFinalCompletion() async throws
    -> JournaledKernelCompletionReceipt
  {
    try await completionCoordinator.authorize()
  }
}

/// Relaunch-only cleanup ownership for an exact registered journal. This actor
/// intentionally cannot perform productive work: its process runtime has no
/// execution proof or candidate root, and the actor exposes only projection,
/// cleanup preflight, and termination. A failed exact-process reconciliation
/// therefore vetoes normal quit instead of silently abandoning ownership.
actor KernelRecoveredApplicationTerminationSession:
  KernelApplicationTerminationSession
{
  private let runtime: JournaledProcessRuntime
  private let lifecycle: JournaledRuntimeLifecycleAuthority
  private let supervisor: RuntimeSupervisor
  private let journal: RunJournal

  fileprivate init(
    runtime: JournaledProcessRuntime,
    lifecycle: JournaledRuntimeLifecycleAuthority,
    supervisor: RuntimeSupervisor,
    journal: RunJournal
  ) {
    self.runtime = runtime
    self.lifecycle = lifecycle
    self.supervisor = supervisor
    self.journal = journal
  }

  func runtimeCleanupPlan() async -> [RuntimeCleanupAction] {
    await supervisor.cleanupPlan()
  }

  func applicationTerminationCleanupIsExecutable() async -> Bool {
    await runtime.applicationTerminationCleanupIsExecutable()
  }

  func kernelProjection() async -> KernelRunProjection {
    await journal.currentProjection()
  }

  func prepareForApplicationTermination(
    requestNonce: String
  ) async throws -> KernelRunProjection {
    try await prepareKernelApplicationTermination(
      runtime: runtime,
      lifecycle: lifecycle,
      supervisor: supervisor,
      journal: journal,
      requestNonce: requestNonce,
      origin: .nativeQuit
    )
  }

  /// Startup-only fail-closed reconciliation. A complete application crash
  /// destroys every non-Codable productive capability, so an exact recovered
  /// cleanup session may only drain, release, interrupt, and become quiescent.
  /// The distinct durable command namespace makes crash recovery auditable and
  /// prevents a retry from masquerading as an ordinary user-initiated quit.
  func reconcileAfterApplicationCrash(
    requestNonce: String
  ) async throws -> KernelRunProjection {
    try await prepareKernelApplicationTermination(
      runtime: runtime,
      lifecycle: lifecycle,
      supervisor: supervisor,
      journal: journal,
      requestNonce: requestNonce,
      origin: .applicationCrashRecovery
    )
  }
}

/// Separate composition root for new-kernel execution. It cannot see or call
/// `LoopController`, `CodexRunner`, `GraphLoopEngine`, or legacy task state.
actor KernelProductionExecutionCoordinator {
  private let registry: WorkspaceMutationRecoveryRegistry
  private let preparationCoordinator: KernelExecutionPreparationCoordinator
  private let wallClock: @Sendable () -> Date
  private let monotonicClock: @Sendable () -> UInt64
  private var workspaceMutationApplicationTerminationJoins:
    [KernelRunID: WorkspaceMutationApplicationTerminationJoin] = [:]

  init(
    registry: WorkspaceMutationRecoveryRegistry,
    wallClock: @escaping @Sendable () -> Date = { Date() },
    monotonicClock: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) {
    self.registry = registry
    self.wallClock = wallClock
    self.monotonicClock = monotonicClock
    preparationCoordinator = KernelExecutionPreparationCoordinator(
      registry: registry
    )
  }

  /// Preflights every live, non-Codable workspace join before normal quit.
  /// Returning the exact plans lets AppModel prove this set is unchanged after
  /// all process-session preflights and before the first pending effect runs.
  func workspaceMutationApplicationTerminationPlans() async throws
    -> [WorkspaceMutationApplicationTerminationPlan]
  {
    var plans: [WorkspaceMutationApplicationTerminationPlan] = []
    for (runID, join) in workspaceMutationApplicationTerminationJoins.sorted(
      by: { $0.key.rawValue < $1.key.rawValue }
    ) {
      let plan = try await join.preflight()
      guard plan.runID == runID else {
        throw WorkspaceMutationApplicationTerminationJoinError
          .ownershipChanged
      }
      plans.append(plan)
    }
    return plans
  }

  /// Joins only the exact set returned by the preceding full preflight. A
  /// changed count, identity, envelope, lease, or cleanup plan rejects before
  /// the first filesystem effect. Each successful join removes only its live
  /// in-memory handle after the journal and outbox prove durable completion.
  func joinWorkspaceMutationsForApplicationTermination(
    expectedPlans: [WorkspaceMutationApplicationTerminationPlan]
  ) async throws -> [WorkspaceMutationApplicationTerminationReceipt] {
    let current = try await workspaceMutationApplicationTerminationPlans()
    guard current == expectedPlans else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .expectedPlanChanged
    }
    var receipts: [WorkspaceMutationApplicationTerminationReceipt] = []
    for plan in expectedPlans {
      guard let join = workspaceMutationApplicationTerminationJoins[
        plan.runID
      ] else {
        throw WorkspaceMutationApplicationTerminationJoinError
          .expectedPlanChanged
      }
      let receipt = try await join.join(expected: plan)
      guard receipt.plan == plan else {
        throw WorkspaceMutationApplicationTerminationJoinError
          .cleanupIncomplete
      }
      receipts.append(receipt)
      workspaceMutationApplicationTerminationJoins[plan.runID] = nil
    }
    return receipts
  }

  /// Production composition for the final pre-effect mutation boundary. It
  /// consumes an exact journal-accepted preflight, resolves non-serializable
  /// containment immediately before lease admission, and returns either one
  /// durable pre-effect veto or the bounded apply installation. A caller
  /// cannot smuggle containment through the inner request.
  func prepareCompletedCandidateMutation(
    _ request: KernelProductionMutationApplyPreparationRequest,
    containmentReadinessResolver:
      KernelPostimageContainmentReadinessResolver =
        kernelOrdinaryMacOSContractReadinessResolution
  ) async throws -> KernelProductionMutationApplyPreparationOutcome {
    let preparation = request.preparation
    let authority = preparation.preflight.authority
    guard case nil = preparation.containmentReadiness,
      WorkspaceCompletedCandidateMutationApplyPreparationCoordinator
        .requestIdentityIsValid(preparation),
      !request.containmentVetoReceiptID.rawValue.isEmpty,
      !request.containmentVetoCommandID.rawValue.isEmpty,
      request.containmentVetoReceiptID
        != authority.receipt.id,
      ![
        preparation.admissionReceiptID,
        preparation.releaseReceiptID,
        preparation.failureReceiptID,
      ].contains(request.containmentVetoReceiptID),
      ![
        preparation.admissionCommandID,
        preparation.intentCommandID,
        preparation.startCommandID,
        preparation.recordCommandID,
        preparation.releaseCommandID,
        preparation.failureCommandID,
      ].contains(request.containmentVetoCommandID),
      preparation.registration.runID == authority.proposal.runID,
      preparation.registration.workspaceID
        == authority.rehearsal.receipt.workspaceID,
      preparation.issuedAt >= authority.receipt.observedAt
    else {
      throw KernelProductionExecutionCompositionError
        .mutationApplyPreparationRequestInvalid
    }
    guard
      let retainedRegistration = try await registry.registration(
        runID: preparation.registration.runID
      ), retainedRegistration == preparation.registration
    else {
      throw KernelProductionExecutionCompositionError.registrationMismatch
    }

    let journal = try RunJournal(
      rootDirectory: preparation.registration.journalRoot,
      runID: preparation.registration.runID
    )
    let state = await journal.state
    let transactionID = authority.proposal.transactionID
    let proposed = await journal.integrationTransitionEvent(
      transaction: preparation.preflight.proposalJournalTransaction
    )
    let prepared = await journal.integrationTransitionEvent(
      transaction: preparation.preflight.preflightJournalTransaction
    )
    guard state.phase == .evaluating,
      state.runtimeFailedReleases.isEmpty,
      let contract = state.contract,
      authority.proposal.contractDigest == contract.objectiveDigest,
      let requirements =
        AuthorizedKernelPostimageContainmentReadiness
        .requiredRequirements(contract),
      !requirements.isEmpty,
      let retainedIntegration = state.integrationTransactions[transactionID],
      retainedIntegration.phase == .rollbackPrepared
        || retainedIntegration.phase == .applying,
      retainedIntegration.proposal == authority.proposal,
      retainedIntegration.preflightReceipt == authority.receipt,
      retainedIntegration.rollbackManifest == authority.rollback,
      proposed == .proposed(authority.proposal),
      prepared
        == .rollbackPrepared(
          receipt: authority.receipt,
          rollback: authority.rollback
        )
    else {
      throw KernelProductionExecutionCompositionError
        .mutationApplyPreparationRequestInvalid
    }

    let readinessResolution = try await containmentReadinessResolver(
      preparation.registration.runID,
      transactionID,
      contract
    )
    if case .authorized(let readiness) = readinessResolution {
      guard
        readiness.authorizes(
          runID: preparation.registration.runID,
          integrationTransactionID: transactionID,
          contract: contract
        )
      else {
        throw KernelProductionExecutionCompositionError
          .mutationApplyContainmentAuthorityMismatch
      }
      var authorizedPreparation = preparation
      authorizedPreparation.containmentReadiness = readiness
      let installation = try await WorkspaceCompletedCandidateMutationApplyPreparationCoordinator(
        registry: registry,
        journal: journal,
        wallClock: wallClock,
        monotonicClock: monotonicClock
      ).prepare(authorizedPreparation)
      workspaceMutationApplicationTerminationJoins[
        preparation.registration.runID
      ] = installation.applicationTerminationJoin
      return .prepared(installation)
    }

    guard retainedIntegration.phase == .rollbackPrepared else {
      throw KernelProductionExecutionCompositionError
        .mutationApplyPreparationRequestInvalid
    }

    if let retained = try await retainedMutationApplyVeto(
      request: request,
      journal: journal,
      state: state,
      contract: contract,
      requirements: requirements
    ) {
      return .vetoed(
        receipt: retained.receipt,
        transaction: retained.transaction
      )
    }

    let receipt = KernelProductionMutationApplyVetoReceipt(
      schemaVersion: 1,
      id: request.containmentVetoReceiptID,
      runID: preparation.registration.runID,
      integrationTransactionID: transactionID,
      preflightReceiptID: authority.receipt.id,
      contractID: contract.id,
      contractDigest: contract.objectiveDigest,
      requirements: requirements,
      reason: .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
      actor: preparation.registration.actorIdentity,
      sourceJournalSequence: state.sequence,
      observedAt: preparation.issuedAt
    )
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordProductionMutationApplyVeto(
          .issuedByProductionCoordinator(
            receipt: receipt,
            issuer: .init()
          )
        ),
        commandID: request.containmentVetoCommandID,
        issuedAt: preparation.issuedAt,
        actor: preparation.registration.actorIdentity
      )
    } catch {
      throw KernelProductionExecutionCompositionError
        .mutationApplyVetoReceiptMismatch
    }
    guard
      await journal.productionMutationApplyVetoReceipt(
        transaction: transaction
      ) == receipt
    else {
      throw KernelProductionExecutionCompositionError
        .mutationApplyVetoReceiptMismatch
    }
    return .vetoed(receipt: receipt, transaction: transaction)
  }

  private func retainedMutationApplyVeto(
    request: KernelProductionMutationApplyPreparationRequest,
    journal: RunJournal,
    state: KernelRunState,
    contract: TaskContract,
    requirements: [KernelPostimageContainmentRequirement]
  ) async throws -> (
    receipt: KernelProductionMutationApplyVetoReceipt,
    transaction: JournalTransactionReceipt
  )? {
    let authority = request.preparation.preflight.authority
    let matches = (state.productionMutationApplyVetoReceipts ?? [:])
      .values.filter {
        $0.integrationTransactionID == authority.proposal.transactionID
      }
    guard !matches.isEmpty else { return nil }
    guard matches.count == 1,
      let receipt = matches.first,
      receipt.id == request.containmentVetoReceiptID,
      receipt.runID == request.preparation.registration.runID,
      receipt.preflightReceiptID == authority.receipt.id,
      receipt.contractID == contract.id,
      receipt.contractDigest == contract.objectiveDigest,
      receipt.requirements == requirements,
      receipt.reason
        == .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
      receipt.actor == request.preparation.registration.actorIdentity,
      let transaction = await journal.transactionReceipt(
        commandID: request.containmentVetoCommandID
      ),
      await journal.productionMutationApplyVetoReceipt(
        transaction: transaction
      ) == receipt
    else {
      throw KernelProductionExecutionCompositionError
        .mutationApplyVetoReceiptMismatch
    }
    return (receipt, transaction)
  }

  /// Read-only native cutover preflight. It proves what the enrolled journal
  /// contains and reports the authority that is still absent. It never
  /// invents a plan, strategy, budget, evidence recipe, command ID, or
  /// timestamp, and it never appends a journal frame.
  func nativeExecutionReadiness(
    for enrollment: KernelRunEnrollmentReceipt,
    designBaseline: AuthorizedKernelDesignBaseline? = nil
  ) async throws -> KernelNativeExecutionReadinessAssessment {
    guard enrollment.runID == enrollment.registration.runID,
      enrollment.contractID
        == enrollment.registration
        .enrollmentEvidence?.contractID,
      enrollment.journalTransaction.frameDigest
        == enrollment.registration
        .enrollmentEvidence?.journalFrameDigest,
      enrollment.journalTransaction.endingSequence
        == enrollment.registration
        .enrollmentEvidence?.journalEndingSequence,
      enrollment.registration.enrollmentEvidence?.authority == .ratifiedUserContract
    else {
      throw KernelNativeExecutionReadinessError.invalidEnrollment
    }
    guard
      let registration = try await registry.registration(
        runID: enrollment.runID
      ), registration == enrollment.registration
    else {
      throw KernelNativeExecutionReadinessError.registrationMismatch
    }

    let journal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: registration.runID
    )
    let state = await journal.state
    let recovery = await journal.recoveryReport
    guard state.contract?.id == enrollment.contractID,
      state.phase == .ready,
      state.nodes.isEmpty,
      state.attempts.isEmpty
    else {
      throw KernelNativeExecutionReadinessError.journalIdentityMismatch
    }
    let isolationReceipts = state.preApplyCandidateIsolationReceipts ?? [:]
    if isolationReceipts.isEmpty {
      guard state.sequence == enrollment.journalTransaction.endingSequence,
        recovery.lastFrameDigest == enrollment.journalTransaction.frameDigest
      else {
        throw KernelNativeExecutionReadinessError.journalIdentityMismatch
      }
    } else {
      guard isolationReceipts.count == 1,
        state.sequence == enrollment.journalTransaction.endingSequence + 1,
        recovery.lastFrameDigest != nil
      else {
        throw KernelNativeExecutionReadinessError.journalIdentityMismatch
      }
    }

    var blockers = KernelNativeExecutionAuthorityBlocker.allCases
    if state.contract?.hasCompleteRequirementEvidenceRecipeProvenance == true {
      blockers.removeAll { $0 == .evidenceRecipeProvenanceMissing }
    }
    if let contract = state.contract,
      let budgets = contract.executionBudgets,
      budgets.validationIssues(
        writableScopes: contract.authorityCeiling.writableScopes
      ).isEmpty
    {
      blockers.removeAll {
        $0 == .mutationBudgetAuthorityMissing
          || $0 == .convergenceBudgetAuthorityMissing
      }
    }
    if state.contract?.hasValidInitialExecutionAuthority == true {
      blockers.removeAll {
        $0 == .causalStrategyAuthorityMissing
          || $0 == .executionPlanAuthorityMissing
      }
    }
    if let contract = state.contract {
      if contract.protectedBaselines.isEmpty {
        blockers.removeAll { $0 == .designBaselineAuthorityMissing }
      } else if let baseline = designBaseline,
        baseline.runID == enrollment.runID,
        baseline.contractRatificationReceiptID
          == enrollment.ratificationReceiptID,
        baseline.enrollmentJournalFrameDigest
          == enrollment.journalTransaction.frameDigest,
        baseline.baseline.contractID == enrollment.contractID
      {
        blockers.removeAll { $0 == .designBaselineAuthorityMissing }
      }
    }
    if state.contract?.requiresWorkspaceMutationAuthority == false {
      blockers.removeAll {
        $0 == .preApplyCandidateIsolationAuthorityMissing
          || $0 == .journaledMutationPreparationAuthorityMissing
      }
    }
    guard let contract = state.contract,
      let workerProfile = contract.executionProfile?.worker
    else {
      throw KernelNativeExecutionReadinessError.journalIdentityMismatch
    }
    let providerReadiness = KernelProviderInvocationCompiler.profileReadiness(
      workerProfile,
      authorityCeiling: contract.authorityCeiling
    )
    return KernelNativeExecutionReadinessAssessment(
      schemaVersion: 2,
      runID: enrollment.runID,
      contractID: enrollment.contractID,
      sourceJournalSequence: state.sequence,
      sourceJournalFrameDigest: recovery.lastFrameDigest
        ?? enrollment.journalTransaction.frameDigest,
      phase: state.phase,
      blockers: blockers,
      providerInvocationProfileReadiness: providerReadiness
    )
  }

  /// Reconstructs only the inert enrollment receipt already proven by the
  /// durable registry and exact run-created journal frame. It creates no live
  /// design, process, mutation, provider, or retry authority. A ready run can
  /// therefore reappear after relaunch, while every non-Codable capability
  /// still has to be reissued by its native authority boundary.
  func recoverReadyEnrollment(
    runID: KernelRunID
  ) async throws -> KernelRunEnrollmentReceipt {
    guard let registration = try await registry.registration(runID: runID),
      registration.runID == runID,
      let evidence = registration.enrollmentEvidence,
      evidence.authority == .ratifiedUserContract,
      evidence.runID == runID,
      !evidence.userActorID.rawValue.isEmpty,
      !evidence.userActorLineageDigest.rawValue.isEmpty,
      !registration.actorIdentity.id.rawValue.isEmpty,
      !registration.actorIdentity.lineageDigest.rawValue.isEmpty
    else {
      throw KernelNativeExecutionReadinessError
        .recoveredEnrollmentUnavailable
    }

    let journal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: registration.runID
    )
    guard
      let transaction = await journal.transactionReceipt(
        commandID: evidence.createCommandID
      )
    else {
      throw KernelNativeExecutionReadinessError
        .recoveredEnrollmentUnavailable
    }
    let state = await journal.state
    let recovery = await journal.recoveryReport
    let projection = await journal.currentProjection()
    guard !transaction.duplicate,
      transaction.startingSequence == 1,
      transaction.endingSequence == evidence.journalEndingSequence,
      transaction.eventIDs.count == 1,
      transaction.frameDigest == evidence.journalFrameDigest,
      recovery.lastFrameDigest == transaction.frameDigest,
      state.sequence == transaction.endingSequence,
      state.phase == .ready,
      state.nodes.isEmpty,
      state.attempts.isEmpty,
      state.contract?.id == evidence.contractID,
      projection.runID == runID,
      projection.phase == .ready
    else {
      throw KernelNativeExecutionReadinessError
        .recoveredEnrollmentUnavailable
    }
    return KernelRunEnrollmentReceipt(
      schemaVersion: 1,
      runID: runID,
      contractID: evidence.contractID,
      contractRevision: evidence.contractRevision,
      candidateDigest: evidence.candidateDigest,
      ratificationReceiptID: evidence.ratificationReceiptID,
      userActorID: evidence.userActorID,
      journalTransaction: transaction,
      registration: registration,
      kernelProjection: projection,
      verificationExecutableStaging: nil
    )
  }

  /// Reconstructs only the authority needed to drain an exact durable native
  /// execution after application relaunch. The recovered process runtime has
  /// no execution proof or candidate root, so this path cannot prepare or
  /// launch providers, mutate a workspace, evaluate evidence, retry work, or
  /// authorize completion. Executable process cleanup remains receipt-bound.
  func recoverApplicationTerminationSession(
    runID: KernelRunID
  ) async throws -> KernelRecoveredApplicationTerminationSession {
    guard let registration = try await registry.registration(runID: runID),
      registration.runID == runID,
      let evidence = registration.enrollmentEvidence,
      evidence.authority == .ratifiedUserContract,
      evidence.runID == runID,
      !evidence.userActorID.rawValue.isEmpty,
      !evidence.userActorLineageDigest.rawValue.isEmpty,
      !registration.actorIdentity.id.rawValue.isEmpty,
      !registration.actorIdentity.role.isEmpty,
      !registration.actorIdentity.lineageDigest.rawValue.isEmpty
    else {
      throw KernelRecoveredApplicationTerminationError.recoveryUnavailable
    }

    let journal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: registration.runID
    )
    let state = await journal.state
    let recovery = await journal.recoveryReport
    let projection = await journal.currentProjection()
    guard state.runID == runID,
      state.contract?.id == evidence.contractID,
      state.phase == .executing || state.phase == .stopRequested,
      let activeAttemptID = state.activeAttemptID,
      let attempt = state.attempts[activeAttemptID],
      attempt.id == activeAttemptID,
      attempt.disposition == nil,
      let node = state.nodes[attempt.nodeID],
      node.attemptIDs.contains(activeAttemptID),
      node.status == .executing,
      recovery.lastFrameDigest != nil,
      projection.runID == runID,
      projection.sequence == state.sequence,
      projection.phase == state.phase,
      projection.activeAttemptID == activeAttemptID,
      projection.quiescent == false
    else {
      throw KernelRecoveredApplicationTerminationError.recoveryUnavailable
    }

    let supervisor = RuntimeSupervisor(
      runID: registration.runID,
      budget: registration.hostBudget
    )
    let snapshot = await journal.runtimeSupervisorRecoverySnapshot()
    guard case .restored = await supervisor.restore(from: snapshot) else {
      throw KernelRecoveredApplicationTerminationError
        .supervisorRestoreRejected
    }
    let runtime = JournaledProcessRuntime(
      supervisor: supervisor,
      journal: journal,
      actorIdentity: registration.actorIdentity
    )
    let lifecycle = JournaledRuntimeLifecycleAuthority(
      supervisor: supervisor,
      journal: journal,
      actorIdentity: registration.actorIdentity
    )
    return KernelRecoveredApplicationTerminationSession(
      runtime: runtime,
      lifecycle: lifecycle,
      supervisor: supervisor,
      journal: journal
    )
  }

  /// Native cutover boundary for an explicitly selected enrolled run. The
  /// caller supplies no plan, strategy, budget, costs, node, actor, or command
  /// graph. Those values are reconstructed from the unchanged ratified
  /// journal, while an ambiguous multi-root plan or missing live design
  /// authority fails closed before any preparation frame is appended.
  func activateNativeEnrolledRun(
    _ request: KernelNativeExecutionStartRequest
  ) async throws -> KernelProductionExecutionSession {
    let nonce = request.requestNonce
    guard !nonce.isEmpty,
      nonce == nonce.lowercased(),
      UUID(uuidString: nonce) != nil,
      request.initiatedAt.timeIntervalSince1970.isFinite
    else {
      throw KernelNativeExecutionStartError.invalidRequestIdentity
    }

    let readiness = try await nativeExecutionReadiness(
      for: request.enrollment,
      designBaseline: request.designBaseline
    )
    guard readiness.canPrepareAndActivate else {
      throw KernelNativeExecutionStartError.authorityBlocked(
        readiness.blockers
      )
    }

    let registration = request.enrollment.registration
    let journal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: registration.runID
    )
    let state = await journal.state
    let recovery = await journal.recoveryReport
    guard state.sequence == readiness.sourceJournalSequence,
      recovery.lastFrameDigest == readiness.sourceJournalFrameDigest,
      state.phase == .ready,
      state.nodes.isEmpty,
      state.attempts.isEmpty,
      let contract = state.contract,
      contract.id == request.enrollment.contractID,
      contract.hasCompleteRequirementEvidenceRecipeProvenance,
      contract.hasValidInitialExecutionAuthority,
      let authority = contract.initialCausalStrategyAuthority,
      let plan = contract.initialExecutionPlan,
      let budgets = contract.executionBudgets
    else {
      throw KernelNativeExecutionStartError.invalidRetainedAuthority
    }

    let initialNodes = plan.nodes.filter(\.dependencies.isEmpty)
    guard initialNodes.count == 1, let node = initialNodes.first else {
      throw KernelNativeExecutionStartError.ambiguousInitialNode
    }
    guard node.strategyFingerprint == authority.descriptor.fingerprint,
      node.requirementIDs == authority.descriptor.requirementIDs
    else {
      throw KernelNativeExecutionStartError.invalidRetainedAuthority
    }

    if contract.protectedBaselines.isEmpty {
      guard request.designBaseline == nil else {
        throw KernelNativeExecutionStartError.designBaselineAuthorityMismatch
      }
    } else {
      guard let baseline = request.designBaseline,
        baseline.runID == request.enrollment.runID,
        baseline.contractRatificationReceiptID
          == request.enrollment.ratificationReceiptID,
        baseline.enrollmentJournalFrameDigest
          == request.enrollment.journalTransaction.frameDigest,
        baseline.baseline.contractID == request.enrollment.contractID
      else {
        throw KernelNativeExecutionStartError.designBaselineAuthorityMismatch
      }
    }

    let recipes = contract.requirementEvidenceRecipes ?? []
    let verificationRecipeCount = recipes.filter {
      node.requirementIDs.contains($0.requirementID)
    }.count
    guard verificationRecipeCount > 0,
      let verificationCost = UInt64(exactly: verificationRecipeCount),
      let externalEffects = UInt16(
        exactly: (contract.externalDependencies ?? []).count
      )
    else {
      throw KernelNativeExecutionStartError.invalidRetainedAuthority
    }
    let mutationCost: UInt64
    if plan.requiresWorkspaceMutation {
      guard node.mutationScope.maximumChangedBytes >= 0,
        let exactMutationCost = UInt64(
          exactly: node.mutationScope.maximumChangedBytes
        )
      else {
        throw KernelNativeExecutionStartError.invalidRetainedAuthority
      }
      mutationCost = exactMutationCost
    } else {
      mutationCost = 0
    }

    let prefix = "native-\(nonce)"
    return try await activate(
      KernelProductionExecutionCompositionRequest(
        preparation: KernelExecutionPreparationRequest(
          enrollment: request.enrollment,
          plan: plan,
          designBaseline: request.designBaseline,
          convergenceEpochID: "\(prefix)-epoch",
          convergenceBudget: budgets.convergence,
          nodeID: node.id,
          admission: AttemptAdmissionRequest(
            attemptID: AttemptID("\(prefix)-attempt"),
            strategy: authority.descriptor,
            predictedObservationIDs:
              authority.descriptor.expectedObservationIDs,
            falsificationPredicateIDs:
              authority.descriptor.falsificationPredicateIDs,
            rollbackPoint: authority.descriptor.baselineRevision,
            mutationCost: mutationCost,
            verificationCost: verificationCost,
            externalEffects: externalEffects
          ),
          actorIdentity: registration.actorIdentity,
          issuedAt: request.initiatedAt,
          planCommandID: RunCommandID("\(prefix)-plan"),
          baselineCommandID: request.designBaseline == nil
            ? nil
            : RunCommandID("\(prefix)-baseline"),
          convergenceCommandID: RunCommandID("\(prefix)-convergence"),
          authorizationCommandID: RunCommandID("\(prefix)-authorize"),
          admissionCommandID: RunCommandID("\(prefix)-admit")
        ),
        startCommandID: RunCommandID("\(prefix)-start"),
        activatedAt: request.initiatedAt,
        preApplyCandidateIsolation: nil
      )
    )
  }

  func activate(
    _ request: KernelProductionExecutionCompositionRequest
  ) async throws -> KernelProductionExecutionSession {
    let enrollment = request.preparation.enrollment
    guard request.preparation.actorIdentity == enrollment.registration.actorIdentity,
      request.activatedAt >= request.preparation.issuedAt
    else {
      throw KernelProductionExecutionCompositionError.actorBoundaryMismatch
    }
    guard enrollment.registration.enrollmentEvidence?.authority == .ratifiedUserContract else {
      throw KernelProductionExecutionCompositionError.invalidEnrollment
    }
    guard
      let registration = try await registry.registration(
        runID: enrollment.runID
      ), registration == enrollment.registration
    else {
      throw KernelProductionExecutionCompositionError.registrationMismatch
    }
    let readinessJournal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: registration.runID
    )
    let retainedContract = await readinessJournal.currentContract()
    guard let retainedContract,
      let workerProfile = retainedContract.executionProfile?.worker
    else {
      throw KernelProductionExecutionCompositionError.invalidEnrollment
    }
    let providerReadiness = KernelProviderInvocationCompiler.profileReadiness(
      workerProfile,
      authorityCeiling: retainedContract.authorityCeiling
    )
    let mutationExecution = request.preparation.plan
      .requiresWorkspaceMutation
    let acceptedIsolation: WorkspacePreApplyCandidateIsolationReceipt?
    let consumedCandidateExecutionRoot: AuthorizedWorkspacePreApplyCandidateExecutionRoot?
    if mutationExecution {
      guard retainedContract.requiresWorkspaceMutationAuthority == true,
        let authority = request.preApplyCandidateIsolation,
        authority.receipt.attemptID == request.preparation.admission.attemptID,
        authority.receipt.nodeID == request.preparation.nodeID,
        authority.receipt.strategyFingerprint == request.preparation.admission.strategy.fingerprint,
        authority.receipt.isolationActor == request.preparation.actorIdentity,
        await readinessJournal.preApplyCandidateIsolationReceipt(
          attemptID: authority.receipt.attemptID
        ) == authority.receipt
      else {
        throw KernelProductionExecutionCompositionError
          .preApplyCandidateIsolationAuthorityMissing
      }
      do {
        consumedCandidateExecutionRoot = try WorkspaceCandidatePostimageMaterializer()
          .activatePreApplyIsolation(authority)
        acceptedIsolation = consumedCandidateExecutionRoot?.receipt
      } catch {
        throw KernelProductionExecutionCompositionError
          .preApplyCandidateIsolationAuthorityMissing
      }
    } else {
      guard retainedContract.requiresWorkspaceMutationAuthority == false,
        request.preApplyCandidateIsolation == nil
      else {
        throw KernelProductionExecutionCompositionError
          .preApplyCandidateIsolationAuthorityMissing
      }
      acceptedIsolation = nil
      consumedCandidateExecutionRoot = nil
    }

    let preparation = try await preparationCoordinator.prepare(
      request.preparation,
      acceptedPreApplyIsolation: acceptedIsolation
    )
    let activation = try await preparationCoordinator.activate(
      KernelExecutionActivationRequest(
        enrollment: enrollment,
        preparation: preparation,
        actorIdentity: request.preparation.actorIdentity,
        startCommandID: request.startCommandID,
        issuedAt: request.activatedAt
      ),
      acceptedPreApplyIsolation: acceptedIsolation
    )
    let journal = try RunJournal(
      rootDirectory: registration.journalRoot,
      runID: registration.runID
    )
    let supervisor = RuntimeSupervisor(
      runID: registration.runID,
      budget: registration.hostBudget
    )
    let snapshot = await journal.runtimeSupervisorRecoverySnapshot()
    guard case .restored = await supervisor.restore(from: snapshot) else {
      throw KernelProductionExecutionCompositionError
        .supervisorRestoreRejected
    }
    let runtime = JournaledProcessRuntime(
      supervisor: supervisor,
      journal: journal,
      actorIdentity: request.preparation.actorIdentity,
      executionProof: activation.proof,
      candidateExecutionRoot: consumedCandidateExecutionRoot
    )
    let lifecycle = JournaledRuntimeLifecycleAuthority(
      supervisor: supervisor,
      journal: journal,
      actorIdentity: request.preparation.actorIdentity
    )
    return KernelProductionExecutionSession(
      preparation: preparation,
      activation: activation,
      runtime: runtime,
      lifecycle: lifecycle,
      supervisor: supervisor,
      journal: journal,
      candidateExecutionRoot: consumedCandidateExecutionRoot,
      providerInvocationProfileReadiness: providerReadiness
    )
  }
}
