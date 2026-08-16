import Foundation

enum KernelRunPhase: String, Codable, Sendable {
  case uninitialized
  case ready
  case executing
  case evaluating
  case blocked
  case pauseRequested
  case completionRequested
  case stopRequested
  case paused
  case stopped
  case completed
  case cleanupFailed

  var isTerminal: Bool {
    self == .stopped || self == .completed
  }
}

enum KernelNodeStatus: String, Codable, Sendable {
  case proposed
  case authorized
  case executing
  case awaitingVerification
  case blocked
  case failed
  case rejected
  case accepted
}

enum KernelExecutionDisposition: Codable, Hashable, Sendable {
  case completed
  case continuationNeeded
  case blocked(reasonDigest: ContentDigest)
  case externalDependencyUnavailable(
    receiptID: ReceiptID,
    reasonDigest: ContentDigest
  )
  case failed(reasonDigest: ContentDigest)
  case interrupted
  case malformed(reasonDigest: ContentDigest)

  var canEnterVerification: Bool {
    if case .completed = self { return true }
    return false
  }
}

enum ExternalDependencyAvailability: String, Codable, Hashable, Sendable {
  case available
  case unavailable
}

struct ExternalDependencyObservationReceipt: Codable, Hashable, Sendable {
  var id: ReceiptID
  var attemptID: AttemptID
  var dependencyID: ExternalDependencyID
  var requirementIDs: Set<RequirementID>
  var observer: ActorIdentity
  var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
  var evidenceDigest: ContentDigest
  var availability: ExternalDependencyAvailability
  var observedAt: Date
  /// Present for the production executable-observer path. Optional values
  /// preserve forensic replay of pre-authority journals.
  var sourceResultID: ReceiptID? = nil
  var sourceResultEvidenceSetDigest: ContentDigest? = nil
  var sourceReleaseReceiptID: ReceiptID? = nil
  var sourceReleaseFrameDigest: ContentDigest? = nil
}

/// Non-serializable authority for an external-dependency observation. A future
/// observer runtime must mint this from the configured evidence recipe and an
/// independently identified observer; decoded receipt data is not authority.
struct AuthorizedKernelExternalDependencyObservation: Sendable {
  let receipt: ExternalDependencyObservationReceipt

  fileprivate init(receipt: ExternalDependencyObservationReceipt) {
    self.receipt = receipt
  }

  static func issuedByExternalDependencyJournal(
    _ receipt: ExternalDependencyObservationReceipt,
    issuer: ExternalDependencyObservationJournalCommandIssuer
  ) -> Self {
    Self(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: ExternalDependencyObservationReceipt
    ) -> AuthorizedKernelExternalDependencyObservation {
      AuthorizedKernelExternalDependencyObservation(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority for a runtime-drain snapshot. Release issuance
/// requires the file-private token owned by the journaled lifecycle runtime;
/// decoded supervisor-shaped data alone is never command authority.
struct AuthorizedKernelRuntimeDrain: Sendable {
  let receipt: RuntimeDrainReceipt

  private init(receipt: RuntimeDrainReceipt) {
    self.receipt = receipt
  }

  static func issuedByLifecycleRuntime(
    _ receipt: RuntimeDrainReceipt,
    issuer: JournaledRuntimeLifecycleCommandIssuer
  ) -> AuthorizedKernelRuntimeDrain {
    AuthorizedKernelRuntimeDrain(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: RuntimeDrainReceipt
    ) -> AuthorizedKernelRuntimeDrain {
      AuthorizedKernelRuntimeDrain(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority for a proven-quiescence snapshot. Release
/// issuance requires the lifecycle runtime that owns the journal and the live
/// supervisor observations for processes, leases, failures, and cleanup.
struct AuthorizedKernelQuiescence: Sendable {
  let receipt: QuiescenceReceipt

  private init(receipt: QuiescenceReceipt) {
    self.receipt = receipt
  }

  static func issuedByLifecycleRuntime(
    _ receipt: QuiescenceReceipt,
    issuer: JournaledRuntimeLifecycleCommandIssuer
  ) -> AuthorizedKernelQuiescence {
    AuthorizedKernelQuiescence(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: QuiescenceReceipt
    ) -> AuthorizedKernelQuiescence {
      AuthorizedKernelQuiescence(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority for a runtime admission fact. Exactly two
/// production coordinators may mint one, and each factory requires its
/// source-file-owned issuer token.
struct AuthorizedKernelRuntimeAdmission: Sendable {
  let receipt: RuntimeAdmissionReceipt

  private init(receipt: RuntimeAdmissionReceipt) {
    self.receipt = receipt
  }

  static func issuedByProcessRuntime(
    _ receipt: RuntimeAdmissionReceipt,
    issuer: JournaledProcessRuntimeCommandIssuer
  ) -> AuthorizedKernelRuntimeAdmission {
    AuthorizedKernelRuntimeAdmission(receipt: receipt)
  }

  static func issuedByWorkspaceMutationRuntime(
    _ receipt: RuntimeAdmissionReceipt,
    issuer: JournaledWorkspaceMutationRuntimeCommandIssuer
  ) -> AuthorizedKernelRuntimeAdmission {
    AuthorizedKernelRuntimeAdmission(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: RuntimeAdmissionReceipt
    ) -> AuthorizedKernelRuntimeAdmission {
      AuthorizedKernelRuntimeAdmission(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority for binding a real external process identity.
/// Only the journaled process runtime owns the required issuer token.
struct AuthorizedKernelRuntimeBinding: Sendable {
  let receipt: RuntimeExternalBindingReceipt

  private init(receipt: RuntimeExternalBindingReceipt) {
    self.receipt = receipt
  }

  static func issuedByProcessRuntime(
    _ receipt: RuntimeExternalBindingReceipt,
    issuer: JournaledProcessRuntimeCommandIssuer
  ) -> AuthorizedKernelRuntimeBinding {
    AuthorizedKernelRuntimeBinding(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: RuntimeExternalBindingReceipt
    ) -> AuthorizedKernelRuntimeBinding {
      AuthorizedKernelRuntimeBinding(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority for a runtime release or cleanup-failure fact.
/// Both legitimate cleanup coordinators retain their existing ability to mint
/// one through distinct file-owned issuer tokens.
struct AuthorizedKernelRuntimeRelease: Sendable {
  let receipt: RuntimeReleaseOutcomeReceipt

  private init(receipt: RuntimeReleaseOutcomeReceipt) {
    self.receipt = receipt
  }

  static func issuedByProcessRuntime(
    _ receipt: RuntimeReleaseOutcomeReceipt,
    issuer: JournaledProcessRuntimeCommandIssuer
  ) -> AuthorizedKernelRuntimeRelease {
    AuthorizedKernelRuntimeRelease(receipt: receipt)
  }

  static func issuedByWorkspaceMutationRuntime(
    _ receipt: RuntimeReleaseOutcomeReceipt,
    issuer: JournaledWorkspaceMutationRuntimeCommandIssuer
  ) -> AuthorizedKernelRuntimeRelease {
    AuthorizedKernelRuntimeRelease(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: RuntimeReleaseOutcomeReceipt
    ) -> AuthorizedKernelRuntimeRelease {
      AuthorizedKernelRuntimeRelease(receipt: receipt)
    }
  #endif
}

enum ExternalDependencyObservationViolation: Codable, Hashable, Sendable {
  case unknownDependency(ExternalDependencyID)
  case mismatchedAttempt(AttemptID)
  case mismatchedRequirements(ExternalDependencyID)
  case unauthorizedObserver(ExternalDependencyID)
  case mismatchedEvidenceRecipe(ExternalDependencyID)
  case invalidEvidence(ExternalDependencyID)
}

enum VerificationResult: String, Codable, Sendable {
  case accepted
  case rejected
}

struct KernelVerificationEvidenceBatch: Codable, Hashable, Sendable {
  var schemaVersion: Int
  var postimageResultID: ReceiptID
  var postimageResultEvidenceSetDigest: ContentDigest
  var postimageReleaseReceiptID: ReceiptID
  var postimageReleaseCommandID: RunCommandID
  var postimageReleaseEndingSequence: UInt64
  var postimageReleaseFrameDigest: ContentDigest
  var evidenceSetDigest: ContentDigest
}

struct VerificationReceipt: Codable, Hashable, Sendable {
  var id: ReceiptID
  var attemptID: AttemptID
  var requirementIDs: Set<RequirementID>
  var sourceRevision: ContentDigest
  var environmentDigest: ContentDigest
  var oracleDigest: ContentDigest
  var result: VerificationResult
  /// Exact implementation bindings observed by the verifier. Optionality is
  /// retained only for decoding pre-v2 journal receipts; a newly accepted
  /// receipt for a bound requirement must provide the full typed set.
  var implementationObservations: Set<ExactImplementationObservation>? = nil
  /// Exact member observations for cardinality-bound requirements. Optional
  /// only so pre-cardinality journal receipts remain decodable.
  var deliverableObservations: Set<DeliverableCardinalityObservation>? = nil
  /// Present for production postimage verification. Legacy receipts remain
  /// readable, but cannot participate in result-ordered red revocation.
  var postimageEvidenceBatch: KernelVerificationEvidenceBatch? = nil
}

enum DeliverableCardinalityViolation: Codable, Hashable, Sendable {
  case missingObservation(RequirementID)
  case unexpectedObservation(RequirementID)
  case duplicateObservation(RequirementID)
  case collectionMismatch(requirementID: RequirementID, expected: String, actual: String)
  case invalidEvidence(RequirementID)
  case duplicateMemberIdentity(requirementID: RequirementID, stableID: String)
  case countMismatch(requirementID: RequirementID, expected: UInt64, actual: UInt64)
}

/// Non-serializable production authority for verification evidence. Durable
/// receipts remain replayable, but decoded data cannot recreate the command
/// capability required to add a new accepted or rejected verification fact.
struct AuthorizedKernelVerification: Sendable {
  let receipt: VerificationReceipt

  fileprivate init(receipt: VerificationReceipt) {
    self.receipt = receipt
  }

  static func issuedByProcessRuntime(
    receipt: VerificationReceipt,
    issuer: JournaledProcessRuntimeCommandIssuer
  ) -> AuthorizedKernelVerification {
    AuthorizedKernelVerification(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      receipt: VerificationReceipt
    ) -> AuthorizedKernelVerification {
      AuthorizedKernelVerification(receipt: receipt)
    }
  #endif
}

enum IndependentReviewDecision: String, Codable, Sendable {
  case approveCandidate
  case rejectCandidate
  case needsDifferentEvidence
}

struct IndependentReviewReceipt: Codable, Hashable, Sendable {
  var id: ReceiptID
  var attemptID: AttemptID
  var requirementIDs: Set<RequirementID>
  var reviewer: ActorIdentity
  var evidenceDigest: ContentDigest
  var sourceRevision: ContentDigest?
  var decision: IndependentReviewDecision
  /// Exact v2 verification batch reviewed. Optional only for legacy replay;
  /// it does not replace the reviewer's own evidence digest above.
  var verificationEvidenceSetDigest: ContentDigest? = nil
  /// Exact schema-v4 reviewer result that authorized this fact. Optional
  /// only for legacy replay and DEBUG fixtures.
  var sourcePostimageResultID: ReceiptID? = nil
}

/// Non-serializable production authority for independent review. The future
/// reviewer runtime issuer must create this value from exact journaled process
/// and retained-result provenance; model JSON or a decoded receipt cannot.
struct AuthorizedKernelIndependentReview: Sendable {
  let receipt: IndependentReviewReceipt

  fileprivate init(receipt: IndependentReviewReceipt) {
    self.receipt = receipt
  }

  static func issuedByProcessRuntime(
    receipt: IndependentReviewReceipt,
    issuer: JournaledProcessRuntimeCommandIssuer
  ) -> AuthorizedKernelIndependentReview {
    AuthorizedKernelIndependentReview(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      receipt: IndependentReviewReceipt
    ) -> AuthorizedKernelIndependentReview {
      AuthorizedKernelIndependentReview(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority for evaluating one exact visual candidate. The
/// future issuer must bind native capture attestations, deterministic
/// measurements, and a separately activated reviewer result before this
/// command can be created in production.
struct AuthorizedKernelVisualEvaluation: Sendable {
  let receiptID: ReceiptID
  let attemptID: AttemptID
  let requirementIDs: Set<RequirementID>
  let candidate: VisualCandidateBundle
  let nativeReviewRequestDigest: ContentDigest?
  let nativeCaptureAttestationDigests: Set<ContentDigest>?
  let nativeMeasurementAttestationDigests: Set<ContentDigest>?
  let nativeReviewCompletedAt: Date?

  fileprivate init(
    receiptID: ReceiptID,
    attemptID: AttemptID,
    requirementIDs: Set<RequirementID>,
    candidate: VisualCandidateBundle,
    nativeReviewRequestDigest: ContentDigest? = nil,
    nativeCaptureAttestationDigests: Set<ContentDigest>? = nil,
    nativeMeasurementAttestationDigests: Set<ContentDigest>? = nil,
    nativeReviewCompletedAt: Date? = nil
  ) {
    self.receiptID = receiptID
    self.attemptID = attemptID
    self.requirementIDs = requirementIDs
    self.candidate = candidate
    self.nativeReviewRequestDigest = nativeReviewRequestDigest
    self.nativeCaptureAttestationDigests = nativeCaptureAttestationDigests
    self.nativeMeasurementAttestationDigests =
      nativeMeasurementAttestationDigests
    self.nativeReviewCompletedAt = nativeReviewCompletedAt
  }

  static func issuedByNativeVisualEvaluationCoordinator(
    receiptID: ReceiptID,
    attemptID: AttemptID,
    requirementIDs: Set<RequirementID>,
    review: AuthorizedNativeIndependentVisualReview,
    issuer: NativeVisualEvaluationCommandIssuer
  ) -> AuthorizedKernelVisualEvaluation {
    AuthorizedKernelVisualEvaluation(
      receiptID: receiptID,
      attemptID: attemptID,
      requirementIDs: requirementIDs,
      candidate: review.candidate,
      nativeReviewRequestDigest: review.requestDigest,
      nativeCaptureAttestationDigests:
        review.captureAttestationDigests,
      nativeMeasurementAttestationDigests:
        review.measurementAttestationDigests,
      nativeReviewCompletedAt: review.reviewedAt
    )
  }

  #if DEBUG
    static func testOnly(
      receiptID: ReceiptID,
      attemptID: AttemptID,
      requirementIDs: Set<RequirementID>,
      candidate: VisualCandidateBundle
    ) -> AuthorizedKernelVisualEvaluation {
      AuthorizedKernelVisualEvaluation(
        receiptID: receiptID,
        attemptID: attemptID,
        requirementIDs: requirementIDs,
        candidate: candidate
      )
    }
  #endif
}

/// Non-serializable final authorization bound to one exact reducer and
/// hash-journal head. Completion evidence remains replayable, but decoded data
/// cannot recreate the production capability.
struct AuthorizedKernelCompletion: Sendable {
  let receipt: KernelCompletionAuthorizationReceipt
  let isTestOnly: Bool

  var runID: KernelRunID { receipt.runID }
  var sourceSequence: UInt64 { receipt.sourceSequence }
  var authorizer: ActorIdentity { receipt.authorizer }

  fileprivate init(
    receipt: KernelCompletionAuthorizationReceipt,
    isTestOnly: Bool = false
  ) {
    self.receipt = receipt
    self.isTestOnly = isTestOnly
  }

  static func issuedByJournaledCompletionCoordinator(
    receipt: KernelCompletionAuthorizationReceipt,
    issuer: KernelCompletionCommandIssuer
  ) -> AuthorizedKernelCompletion {
    AuthorizedKernelCompletion(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      runID: KernelRunID,
      sourceSequence: UInt64,
      authorizer: ActorIdentity
    ) -> AuthorizedKernelCompletion {
      let syntheticFrame = ContentDigest(String(repeating: "0", count: 64))
      return AuthorizedKernelCompletion(
        receipt:
          KernelCompletionAuthorizationReceipt(
            id: ReceiptID("test-completion-\(sourceSequence)"),
            commandID: RunCommandID("test-completion-\(sourceSequence)"),
            runID: runID,
            contractID: TaskContractID("test-contract"),
            sourceSequence: sourceSequence,
            sourceFrameDigest: syntheticFrame,
            sourceOccurredAt: Date(timeIntervalSince1970: 0),
            sourceEvidenceDigest: syntheticFrame,
            acceptedRequirementIDs: [],
            evidenceReceiptIDs: [],
            authorizer: authorizer,
            authorizedAt: Date(timeIntervalSince1970: 0)
          ), isTestOnly: true)
    }
  #endif
}

struct QuiescenceReceipt: Codable, Hashable, Sendable {
  var id: ReceiptID
  var runID: KernelRunID
  var intent: RuntimeDrainIntent
  var observedAt: Date
  var observedAtMonotonicNanoseconds: UInt64
  var liveResources: Set<OwnedResourceID>
  var failedReleases: Set<OwnedResourceID>
  var queuedLeaseIDs: Set<ResourceLeaseID>

  var provesQuiescence: Bool {
    liveResources.isEmpty && failedReleases.isEmpty && queuedLeaseIDs.isEmpty
  }
}

struct KernelAttemptState: Codable, Hashable, Sendable {
  var id: AttemptID
  var nodeID: KernelNodeID
  var requirementIDs: Set<RequirementID>
  var strategyFingerprint: StrategyFingerprint
  var worker: ActorIdentity
  var startedAt: Date
  var disposition: KernelExecutionDisposition?
  var verificationReceiptIDs: Set<ReceiptID>
  var reviewReceiptIDs: Set<ReceiptID>
}

enum KernelExecutionDerivationSource: Codable, Hashable, Sendable {
  case workerResultParse(ReceiptID)
  case externalDependencyObservation(ReceiptID)
}

struct KernelExecutionDerivationReceipt: Codable, Hashable, Sendable {
  var id: ReceiptID
  var runID: KernelRunID
  var attemptID: AttemptID
  var source: KernelExecutionDerivationSource
  var sourceEvidenceDigest: ContentDigest
  var disposition: KernelExecutionDisposition
  var derivedAt: Date
}

struct KernelNodeState: Codable, Hashable, Sendable {
  var contract: KernelNodeContract
  var status: KernelNodeStatus
  var attemptIDs: [AttemptID]
}

struct KernelRunState: Codable, Hashable, Sendable {
  var runID: KernelRunID
  var sequence: UInt64
  var processedCommandIDs: Set<RunCommandID>
  var contract: TaskContract?
  var phase: KernelRunPhase
  var nodes: [KernelNodeID: KernelNodeState]
  var attempts: [AttemptID: KernelAttemptState]
  var activeAttemptID: AttemptID?
  var verificationReceipts: [ReceiptID: VerificationReceipt]
  var reviewReceipts: [ReceiptID: IndependentReviewReceipt]
  /// Optional solely for decoding pre-dependency state snapshots.
  var externalDependencyReceipts: [ReceiptID: ExternalDependencyObservationReceipt]? = nil
  /// Optional solely for replaying journals written before an exact
  /// executable dependency observer could retain inert activation evidence.
  /// The live request-file authority and process-launch authority are absent
  /// from recovered reducer state.
  var externalDependencyObservationActivationReceipts:
    [ReceiptID: ExternalDependencyObservationActivationReceipt]? = nil
  /// Optional solely for replaying journals written before an activated
  /// dependency observer could bind one exact native process identity.
  var externalDependencyObservationRuntimeLaunchReceipts:
    [ReceiptID:
      ExternalDependencyObservationRuntimeLaunchReceipt]? = nil
  /// Optional solely for replaying journals written before missing hard
  /// external-observer containment became explicit durable causal evidence.
  /// A veto owns no lease, process, or observation authority.
  var externalDependencyObservationLaunchVetoReceipts:
    [ReceiptID: ExternalDependencyObservationLaunchVetoReceipt]? = nil
  var designBaseline: DesignBaselineBundle?
  var visualGateReceipts: [ReceiptID: VisualGateEvaluationReceipt]
  var retiredStrategies: Set<StrategyFingerprint>
  var convergenceGovernor: ConvergenceGovernor?
  /// Optional only for compatibility with reducer snapshots encoded before
  /// accepted-duration authority became journal state. Replay rebuilds this
  /// set exclusively from accepted causal progress events.
  var acceptedProgressCommandIDs: Set<RunCommandID>? = nil
  /// Every causal progress evaluation, including stagnant evaluations. This
  /// keeps occurrence provenance typed: an arbitrary processed command can
  /// never masquerade as progress merely because its identifier exists in
  /// the journal.
  var causalProgressCommandIDs: Set<RunCommandID>? = nil
  /// Closed execution intervals in journal order. Legacy mutable task timing
  /// fields are deliberately not imported into this authority boundary.
  var occurrenceReceipts: [OccurrenceReceipt]? = nil
  /// Optional solely for replaying journals written before an atomic Git
  /// HEAD/index/untracked observation became durable run evidence.
  var journaledGitPreimageCaptureReceipt: WorkspaceJournaledGitPreimageCaptureReceipt? = nil
  /// Optional solely for replaying journals written before repository
  /// metadata, effective ignore classification, and four-plane assembly
  /// became one durable inert receipt.
  var journaledCanonicalPreimageReceipt: WorkspaceJournaledCanonicalPreimageReceipt? = nil
  /// Optional solely for replaying journals written before an isolated
  /// pre-apply candidate could be accepted as inert evidence. The live root
  /// descriptor is deliberately absent from recovered reducer state.
  var preApplyCandidateIsolationReceipts: [AttemptID: WorkspacePreApplyCandidateIsolationReceipt]? =
    nil
  /// Optional solely for replaying journals written before a completed
  /// provider candidate could become durable logical revision evidence.
  /// Exact bytes and held descriptor authority remain out of recovered state.
  var completedCandidateCaptureReceipts: [AttemptID: WorkspaceCompletedCandidateCaptureReceipt]? =
    nil
  /// Optional solely for replaying journals written before completed
  /// candidate bytes could be composed with ratified baseline bytes and
  /// installed in the external immutable store. Bytes remain out of state.
  var completedCandidateMutationContentStoreReceipts:
    [ContentDigest:
      WorkspaceCompletedCandidateMutationContentStoreReceipt]? = nil
  /// Optional solely for replaying journals written before exact accepted
  /// before/after content and canonical preimage evidence could be composed
  /// into an inert manifest proposal. No executable receipt IDs or mutation
  /// authority are present in this recovered projection.
  var completedCandidateMutationManifestProposalReceipts:
    [ContentDigest:
      WorkspaceCompletedCandidateMutationManifestProposalReceipt]? = nil
  /// Optional solely for replaying journals written before descriptor-based
  /// path, exact budget, write-scope, and candidate-quiescence facts became
  /// durable. Rollback and executable authority remain absent.
  var completedCandidateMutationPreparationFactsReceipts:
    [ContentDigest:
      WorkspaceCompletedCandidateMutationPreparationFactsReceipt]? = nil
  /// Optional solely for replaying journals written before an exact
  /// owner-private forward/inverse mutation cycle became durable evidence.
  /// The replica, bytes, and executable preflight authority are absent.
  var completedCandidateMutationRollbackRehearsalReceipts:
    [ContentDigest:
      WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt]? = nil
  /// Optional solely for replaying journals written before ratified baseline
  /// content observation became a distinct durable receipt. The map is keyed
  /// by derivation digest so one mutation derivation cannot silently replace
  /// the baseline bytes that were accepted for it.
  var ratifiedBaselineContentCaptureReceipts:
    [ContentDigest: WorkspaceRatifiedBaselineContentCaptureReceipt]? = nil
  /// Optional solely for replaying journals written before candidate bytes
  /// captured from an exact accepted apply snapshot became durable state.
  /// Bytes and live descriptor authority never enter the journal.
  var journaledCandidateContentCaptureReceipts:
    [ContentDigest: WorkspaceJournaledCandidateContentCaptureReceipt]? = nil
  /// Optional solely for replaying journals written before exact composed
  /// bytes could be accepted into the external immutable object store.
  /// Stored bytes and live composition authority never enter recovered state.
  var journaledMutationContentStoreReceipts:
    [ContentDigest: WorkspaceJournaledMutationContentStoreReceipt]? = nil
  var runtimeAdmissionReceipts: [ReceiptID: RuntimeAdmissionReceipt]
  var runtimeBindingReceipts: [ReceiptID: RuntimeExternalBindingReceipt]
  /// Optional solely for decoding snapshots written before provider launch
  /// became a distinct replayed journal event.
  var providerLaunchReceipts: [ReceiptID: KernelProviderLaunchReceipt]? = nil
  var runtimeReleaseReceipts: [ReceiptID: RuntimeReleaseOutcomeReceipt]
  /// Optional solely for decoding state snapshots written before strict
  /// retained worker-result parsing became journal authority.
  var workerResultParseReceipts: [ReceiptID: KernelWorkerResultParseReceipt]? = nil
  /// Optional solely for decoding snapshots written before execution
  /// disposition became a reducer-derived, source-bound receipt.
  var executionDerivationReceipts: [ReceiptID: KernelExecutionDerivationReceipt]? = nil
  /// Optional solely for replaying journals written before postimage
  /// verifier activation became a distinct, non-verdict authority boundary.
  var postimageVerifierActivationReceipts: [ReceiptID: KernelPostimageVerifierActivationReceipt]? =
    nil
  /// Optional solely for replaying journals written before an activated
  /// postimage verifier could bind one exact native process identity.
  var postimageVerifierLaunchReceipts: [ReceiptID: KernelPostimageVerifierLaunchReceipt]? = nil
  /// Optional solely for replaying journals written before a pre-admission
  /// verifier containment veto became durable causal evidence.
  var postimageVerifierLaunchVetoReceipts: [ReceiptID: KernelPostimageVerifierLaunchVetoReceipt]? =
    nil
  /// Optional solely for replaying journals written before a pre-effect
  /// canonical-mutation containment veto became durable causal evidence.
  var productionMutationApplyVetoReceipts: [ReceiptID: KernelProductionMutationApplyVetoReceipt]? =
    nil
  var runtimeDrainReceipts: [ReceiptID: RuntimeDrainReceipt]
  var runtimeLiveLeases: [OwnedResourceID: RuntimeResourceLease]
  var runtimeFailedReleases: Set<OwnedResourceID>
  var lastRuntimeDrainReceiptID: ReceiptID?
  var quiescenceReceipt: QuiescenceReceipt?
  var integrationTransactions: [IntegrationTransactionID: IntegrationTransactionState]
  /// Optional only for replaying journals completed before exact final
  /// authorization became a distinct durable evidence event.
  var completionAuthorizationReceipt: KernelCompletionAuthorizationReceipt? = nil

  static func empty(runID: KernelRunID) -> KernelRunState {
    KernelRunState(
      runID: runID,
      sequence: 0,
      processedCommandIDs: [],
      contract: nil,
      phase: .uninitialized,
      nodes: [:],
      attempts: [:],
      activeAttemptID: nil,
      verificationReceipts: [:],
      reviewReceipts: [:],
      externalDependencyReceipts: [:],
      externalDependencyObservationActivationReceipts: [:],
      externalDependencyObservationRuntimeLaunchReceipts: [:],
      externalDependencyObservationLaunchVetoReceipts: [:],
      designBaseline: nil,
      visualGateReceipts: [:],
      retiredStrategies: [],
      convergenceGovernor: nil,
      acceptedProgressCommandIDs: [],
      causalProgressCommandIDs: [],
      occurrenceReceipts: [],
      journaledGitPreimageCaptureReceipt: nil,
      journaledCanonicalPreimageReceipt: nil,
      preApplyCandidateIsolationReceipts: [:],
      completedCandidateCaptureReceipts: [:],
      completedCandidateMutationContentStoreReceipts: [:],
      completedCandidateMutationManifestProposalReceipts: [:],
      completedCandidateMutationPreparationFactsReceipts: [:],
      completedCandidateMutationRollbackRehearsalReceipts: [:],
      ratifiedBaselineContentCaptureReceipts: [:],
      journaledCandidateContentCaptureReceipts: [:],
      journaledMutationContentStoreReceipts: [:],
      runtimeAdmissionReceipts: [:],
      runtimeBindingReceipts: [:],
      providerLaunchReceipts: [:],
      runtimeReleaseReceipts: [:],
      workerResultParseReceipts: [:],
      executionDerivationReceipts: [:],
      postimageVerifierActivationReceipts: [:],
      postimageVerifierLaunchReceipts: [:],
      postimageVerifierLaunchVetoReceipts: [:],
      productionMutationApplyVetoReceipts: [:],
      runtimeDrainReceipts: [:],
      runtimeLiveLeases: [:],
      runtimeFailedReleases: [],
      lastRuntimeDrainReceiptID: nil,
      quiescenceReceipt: nil,
      integrationTransactions: [:]
    )
  }

  var acceptedRequirementIDs: Set<RequirementID> {
    guard let contract else { return [] }
    let evidenceAccepted: Set<RequirementID> = Set(
      contract.requirements.compactMap { requirement in
        let verifications = verificationReceipts.values.filter {
          $0.result == .accepted
            && $0.requirementIDs.contains(requirement.id)
            && verificationIsEffective($0, requirementID: requirement.id)
        }
        guard !verifications.isEmpty else { return nil }
        if !contract.acceptancePolicy.requiresIndependentReview { return requirement.id }
        let hasSameAttemptApproval = reviewReceipts.values.contains { review in
          review.decision == .approveCandidate
            && review.requirementIDs.contains(requirement.id)
            && verifications.contains {
              $0.attemptID == review.attemptID
                && review.sourceRevision == $0.sourceRevision
                && reviewMatchesVerification(
                  review,
                  verification: $0
                )
            }
        }
        return hasSameAttemptApproval ? requirement.id : nil
      })
    guard let baseline = designBaseline else { return evidenceAccepted }
    var latestVisualByRequirement: [RequirementID: VisualGateEvaluationReceipt] = [:]
    for receipt in visualGateReceipts.values {
      for requirementID in receipt.requirementIDs {
        if let existing = latestVisualByRequirement[requirementID],
          existing.journalSequence >= receipt.journalSequence
        {
          continue
        }
        latestVisualByRequirement[requirementID] = receipt
      }
    }
    let visuallyAccepted: Set<RequirementID> = Set(
      latestVisualByRequirement.compactMap { entry -> RequirementID? in
        let (requirementID, visual) = entry
        guard visual.result.accepted else { return nil }
        let matchingVerification = verificationReceipts.values.contains {
          $0.attemptID == visual.attemptID
            && $0.result == .accepted
            && $0.requirementIDs.contains(requirementID)
            && $0.sourceRevision == visual.candidateSourceTree
            && verificationIsEffective($0, requirementID: requirementID)
        }
        guard matchingVerification else { return nil }
        if contract.acceptancePolicy.requiresIndependentReview {
          let matchingReview = reviewReceipts.values.contains { review in
            review.attemptID == visual.attemptID
              && review.decision == .approveCandidate
              && review.requirementIDs.contains(requirementID)
              && review.sourceRevision == visual.candidateSourceTree
              && verificationReceipts.values.contains {
                verification in
                verification.attemptID == review.attemptID
                  && verification.requirementIDs.contains(
                    requirementID
                  )
                  && verification.sourceRevision == review.sourceRevision
                  && verificationIsEffective(
                    verification,
                    requirementID: requirementID
                  )
                  && reviewMatchesVerification(
                    review,
                    verification: verification
                  )
              }
          }
          guard matchingReview else { return nil }
        }
        return requirementID
      })
    let unguarded = evidenceAccepted.subtracting(baseline.requirementIDs)
    let guarded =
      evidenceAccepted
      .intersection(baseline.requirementIDs)
      .intersection(visuallyAccepted)
    return unguarded.union(guarded)
  }

  func verificationIsEffective(
    _ receipt: VerificationReceipt,
    requirementID: RequirementID
  ) -> Bool {
    guard receipt.result == .accepted else { return false }
    guard let batch = receipt.postimageEvidenceBatch else {
      return !verificationReceipts.values.contains { candidate in
        candidate.result == .rejected
          && candidate.attemptID == receipt.attemptID
          && candidate.requirementIDs.contains(requirementID)
          && candidate.sourceRevision == receipt.sourceRevision
          && candidate.environmentDigest == receipt.environmentDigest
          && candidate.oracleDigest == receipt.oracleDigest
          && candidate.postimageEvidenceBatch != nil
      }
    }
    return !verificationReceipts.values.contains { candidate in
      guard candidate.result == .rejected,
        candidate.attemptID == receipt.attemptID,
        candidate.requirementIDs.contains(requirementID),
        candidate.sourceRevision == receipt.sourceRevision,
        candidate.environmentDigest == receipt.environmentDigest,
        candidate.oracleDigest == receipt.oracleDigest,
        let candidateBatch = candidate.postimageEvidenceBatch
      else {
        return false
      }
      return candidateBatch.postimageReleaseEndingSequence > batch.postimageReleaseEndingSequence
    }
  }

  func reviewMatchesVerification(
    _ review: IndependentReviewReceipt,
    verification: VerificationReceipt
  ) -> Bool {
    guard let batch = verification.postimageEvidenceBatch else {
      return true
    }
    return review.verificationEvidenceSetDigest == batch.evidenceSetDigest
  }

  var allReceiptIDs: Set<ReceiptID> {
    Set(verificationReceipts.keys)
      .union(reviewReceipts.keys)
      .union((externalDependencyReceipts ?? [:]).keys)
      .union((externalDependencyObservationActivationReceipts ?? [:]).keys)
      .union((externalDependencyObservationRuntimeLaunchReceipts ?? [:]).keys)
      .union((externalDependencyObservationLaunchVetoReceipts ?? [:]).keys)
      .union(visualGateReceipts.keys)
      .union(designBaseline.map { [$0.authority.id] } ?? [])
      .union(runtimeAdmissionReceipts.keys)
      .union(runtimeBindingReceipts.keys)
      .union((providerLaunchReceipts ?? [:]).keys)
      .union(runtimeReleaseReceipts.keys)
      .union((workerResultParseReceipts ?? [:]).keys)
      .union((executionDerivationReceipts ?? [:]).keys)
      .union((postimageVerifierActivationReceipts ?? [:]).keys)
      .union((postimageVerifierLaunchReceipts ?? [:]).keys)
      .union((postimageVerifierLaunchVetoReceipts ?? [:]).keys)
      .union((productionMutationApplyVetoReceipts ?? [:]).keys)
      .union(runtimeDrainReceipts.keys)
      .union(quiescenceReceipt.map { [$0.id] } ?? [])
      .union(completionAuthorizationReceipt.map { [$0.id] } ?? [])
      .union(integrationTransactions.values.flatMap(\.receiptIDs))
      .union((occurrenceReceipts ?? []).map(\.id))
      .union(
        (completedCandidateMutationPreparationFactsReceipts ?? [:])
          .values.flatMap {
            [
              $0.writeAuthority.id,
              $0.mutationBudget.id,
              $0.candidateQuiescence.id,
              $0.pathResolution.id,
            ]
          }
      )
      .union(
        (completedCandidateMutationRollbackRehearsalReceipts ?? [:])
          .values.map(\.rollbackRehearsal.id))
  }

  var acceptedProgressReceiptIDs: Set<ReceiptID> {
    Set((acceptedProgressCommandIDs ?? []).map { ReceiptID($0.rawValue) })
  }

  var causalProgressReceiptIDs: Set<ReceiptID> {
    Set((causalProgressCommandIDs ?? []).map { ReceiptID($0.rawValue) })
  }

  /// Journal-issued evidence identities that a closed occurrence may cite.
  /// Prior occurrence receipts are intentionally excluded so counted time
  /// cannot recursively certify later time.
  var occurrenceEvidenceReceiptIDs: Set<ReceiptID> {
    Set(verificationReceipts.keys)
      .union(reviewReceipts.keys)
      .union((externalDependencyReceipts ?? [:]).keys)
      .union((externalDependencyObservationActivationReceipts ?? [:]).keys)
      .union((externalDependencyObservationRuntimeLaunchReceipts ?? [:]).keys)
      .union((externalDependencyObservationLaunchVetoReceipts ?? [:]).keys)
      .union(visualGateReceipts.keys)
      .union(designBaseline.map { [$0.authority.id] } ?? [])
      .union(runtimeAdmissionReceipts.keys)
      .union(runtimeBindingReceipts.keys)
      .union((providerLaunchReceipts ?? [:]).keys)
      .union(runtimeReleaseReceipts.keys)
      .union((workerResultParseReceipts ?? [:]).keys)
      .union((executionDerivationReceipts ?? [:]).keys)
      .union((postimageVerifierActivationReceipts ?? [:]).keys)
      .union((postimageVerifierLaunchReceipts ?? [:]).keys)
      .union((postimageVerifierLaunchVetoReceipts ?? [:]).keys)
      .union((productionMutationApplyVetoReceipts ?? [:]).keys)
      .union(runtimeDrainReceipts.keys)
      .union(quiescenceReceipt.map { [$0.id] } ?? [])
      .union(integrationTransactions.values.flatMap(\.receiptIDs))
      .union(causalProgressReceiptIDs)
  }

  var durationCoverage: CoverageProjection? {
    guard let duration = contract?.acceptancePolicy.duration else { return nil }
    return IntervalLedger.project(
      receipts: occurrenceReceipts ?? [],
      policy: CoveragePolicy(
        eligibleClass: duration.eligibleClass,
        continuityToleranceNanoseconds: 0
      ),
      acceptedProgressReceiptIDs: acceptedProgressReceiptIDs
    )
  }

  var allIntegrationIntentIDs: Set<IntegrationEffectIntentID> {
    Set(integrationTransactions.values.flatMap(\.intentIDs))
  }
}

enum RunCommand: Sendable {
  case createRun(TaskContract)
  case proposePlan(KernelPlanProposal)
  case authorizeNode(KernelNodeID)
  case startAttempt(
    attemptID: AttemptID,
    nodeID: KernelNodeID,
    requirementIDs: Set<RequirementID>,
    strategyFingerprint: StrategyFingerprint
  )
  case recordExecution(attemptID: AttemptID, disposition: KernelExecutionDisposition)
  case deriveExecution(
    receiptID: ReceiptID,
    source: KernelExecutionDerivationSource
  )
  case activateExternalDependencyObservation(
    AuthorizedExternalDependencyObservationActivation
  )
  case recordExternalDependencyObservationRuntimeBinding(
    AuthorizedExternalDependencyObservationRuntimeLaunch
  )
  case recordExternalDependencyObservationLaunchVeto(
    AuthorizedExternalDependencyObservationLaunchVeto
  )
  case recordExternalDependencyObservation(AuthorizedKernelExternalDependencyObservation)
  case recordVerification(AuthorizedKernelVerification)
  case recordReview(AuthorizedKernelIndependentReview)
  case freezeDesignBaseline(AuthorizedKernelDesignBaseline)
  case evaluateVisualCandidate(AuthorizedKernelVisualEvaluation)
  case retireStrategy(StrategyFingerprint, lessonDigest: ContentDigest)
  case initializeConvergence(epochID: String, budget: ConvergenceBudget)
  case admitCausalAttempt(AttemptAdmissionRequest)
  case recordCausalFailure(
    strategy: StrategyFingerprint,
    failure: CausalFailureFingerprint,
    lessonDigest: ContentDigest
  )
  case authorizeCausalReplacement(
    receiptID: ReceiptID,
    predecessor: StrategyFingerprint,
    replacement: CausalStrategyDescriptor,
    failures: Set<CausalFailureFingerprint>,
    delta: CausalStrategyDelta
  )
  case recordCausalConditionChange(
    strategy: StrategyFingerprint,
    previousFailureDigest: ContentDigest,
    observationDigest: ContentDigest
  )
  case recordCausalProgress(
    strategy: StrategyFingerprint,
    previous: ConvergenceProgressVector,
    current: ConvergenceProgressVector
  )
  case recordOccurrence(AuthorizedKernelOccurrence)
  case recordJournaledGitPreimageCapture(
    AuthorizedWorkspaceJournaledGitPreimageCapture
  )
  case recordJournaledCanonicalPreimage(
    AuthorizedWorkspaceJournaledCanonicalPreimage
  )
  case recordPreApplyCandidateIsolation(
    AuthorizedWorkspacePreApplyCandidateIsolation
  )
  case recordCompletedCandidateCapture(
    AuthorizedWorkspaceCompletedCandidateCapture
  )
  case recordCompletedCandidateMutationContentStore(
    AuthorizedWorkspaceCompletedCandidateMutationContentStore
  )
  case recordCompletedCandidateMutationManifestProposal(
    AuthorizedWorkspaceCompletedCandidateMutationManifestProposal
  )
  case recordCompletedCandidateMutationPreparationFacts(
    AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts
  )
  case recordCompletedCandidateMutationRollbackRehearsal(
    WorkspaceCompletedCandidateMutationRollbackRehearsalAuthorityBox
  )
  case recordRatifiedBaselineContentCapture(
    AuthorizedWorkspaceRatifiedBaselineContent
  )
  case recordJournaledCandidateContentCapture(
    AuthorizedWorkspaceJournaledCandidateContent
  )
  case recordJournaledMutationContentStore(
    AuthorizedWorkspaceJournaledMutationContentStore
  )
  case consumeCausalPlanExpansion
  case recordRuntimeAdmission(AuthorizedKernelRuntimeAdmission)
  case recordRuntimeBinding(AuthorizedKernelRuntimeBinding)
  case recordProviderRuntimeBinding(AuthorizedKernelProviderLaunch)
  case recordRuntimeRelease(AuthorizedKernelRuntimeRelease)
  case recordWorkerResultParse(KernelAuthorizedWorkerResultParse)
  case activatePostimageVerifier(AuthorizedKernelPostimageVerifierActivation)
  case recordPostimageVerifierRuntimeBinding(
    AuthorizedKernelPostimageVerifierLaunch
  )
  case recordPostimageVerifierLaunchVeto(
    AuthorizedKernelPostimageVerifierLaunchVeto
  )
  case recordProductionMutationApplyVeto(
    AuthorizedKernelProductionMutationApplyVeto
  )
  case recordRuntimeDrain(AuthorizedKernelRuntimeDrain)
  case advanceIntegration(AuthorizedKernelIntegrationTransition)
  case requestPause
  case requestCompletion
  case requestStop
  case recordQuiescence(AuthorizedKernelQuiescence)
  case authorizeCompletion(AuthorizedKernelCompletion)
}

#if DEBUG
  extension RunCommand {
    static func testOnlyRecordExternalDependencyObservation(
      _ receipt: ExternalDependencyObservationReceipt
    ) -> RunCommand {
      .recordExternalDependencyObservation(.testOnly(receipt))
    }

    static func testOnlyRecordExternalDependencyObservationLaunchVeto(
      _ receipt: ExternalDependencyObservationLaunchVetoReceipt
    ) -> RunCommand {
      .recordExternalDependencyObservationLaunchVeto(.testOnly(receipt))
    }

    static func testOnlyRecordExternalDependencyObservationRuntimeBinding(
      binding: RuntimeExternalBindingReceipt,
      launch: ExternalDependencyObservationRuntimeLaunchReceipt
    ) -> RunCommand {
      .recordExternalDependencyObservationRuntimeBinding(
        .testOnly(
          binding: binding,
          receipt: launch
        ))
    }

    static func testOnlyRecordVerification(
      _ receipt: VerificationReceipt
    ) -> RunCommand {
      .recordVerification(.testOnly(receipt: receipt))
    }

    static func testOnlyRecordReview(
      _ receipt: IndependentReviewReceipt
    ) -> RunCommand {
      .recordReview(.testOnly(receipt: receipt))
    }

    static func testOnlyFreezeDesignBaseline(
      _ baseline: DesignBaselineBundle
    ) -> RunCommand {
      .freezeDesignBaseline(.testOnly(baseline: baseline))
    }

    static func testOnlyEvaluateVisualCandidate(
      receiptID: ReceiptID,
      attemptID: AttemptID,
      requirementIDs: Set<RequirementID>,
      candidate: VisualCandidateBundle
    ) -> RunCommand {
      .evaluateVisualCandidate(
        .testOnly(
          receiptID: receiptID,
          attemptID: attemptID,
          requirementIDs: requirementIDs,
          candidate: candidate
        ))
    }

    static func testOnlyRecordOccurrence(
      _ receipt: OccurrenceReceipt
    ) -> RunCommand {
      .recordOccurrence(.testOnly(receipt))
    }

    static func testOnlyRecordJournaledGitPreimageCapture(
      _ authority: AuthorizedWorkspaceJournaledGitPreimageCapture
    ) -> RunCommand {
      .recordJournaledGitPreimageCapture(authority)
    }

    static func testOnlyRecordJournaledCanonicalPreimage(
      _ authority: AuthorizedWorkspaceJournaledCanonicalPreimage
    ) -> RunCommand {
      .recordJournaledCanonicalPreimage(authority)
    }

    static func testOnlyRecordRatifiedBaselineContentCapture(
      _ authority: AuthorizedWorkspaceRatifiedBaselineContent
    ) -> RunCommand {
      .recordRatifiedBaselineContentCapture(authority)
    }

    static func testOnlyRecordPreApplyCandidateIsolation(
      _ authority: AuthorizedWorkspacePreApplyCandidateIsolation
    ) -> RunCommand {
      .recordPreApplyCandidateIsolation(authority)
    }

    static func testOnlyRecordCompletedCandidateCapture(
      _ authority: AuthorizedWorkspaceCompletedCandidateCapture
    ) -> RunCommand {
      .recordCompletedCandidateCapture(authority)
    }

    static func testOnlyRecordCompletedCandidateMutationContentStore(
      _ authority: AuthorizedWorkspaceCompletedCandidateMutationContentStore
    ) -> RunCommand {
      .recordCompletedCandidateMutationContentStore(authority)
    }

    static func testOnlyRecordCompletedCandidateMutationManifestProposal(
      _ authority:
        AuthorizedWorkspaceCompletedCandidateMutationManifestProposal
    ) -> RunCommand {
      .recordCompletedCandidateMutationManifestProposal(authority)
    }

    static func testOnlyRecordCompletedCandidateMutationPreparationFacts(
      _ authority:
        AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts
    ) -> RunCommand {
      .recordCompletedCandidateMutationPreparationFacts(authority)
    }

    static func testOnlyRecordCompletedCandidateMutationRollbackRehearsal(
      _ authority:
        AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal
    ) -> RunCommand {
      .recordCompletedCandidateMutationRollbackRehearsal(
        WorkspaceCompletedCandidateMutationRollbackRehearsalAuthorityBox(
          authority
        )
      )
    }

    static func testOnlyRecordJournaledCandidateContentCapture(
      _ authority: AuthorizedWorkspaceJournaledCandidateContent
    ) -> RunCommand {
      .recordJournaledCandidateContentCapture(authority)
    }

    static func testOnlyRecordJournaledMutationContentStore(
      _ authority: AuthorizedWorkspaceJournaledMutationContentStore
    ) -> RunCommand {
      .recordJournaledMutationContentStore(authority)
    }

    static func testOnlyRecordRuntimeDrain(
      _ receipt: RuntimeDrainReceipt
    ) -> RunCommand {
      .recordRuntimeDrain(.testOnly(receipt))
    }

    static func testOnlyRecordQuiescence(
      _ receipt: QuiescenceReceipt
    ) -> RunCommand {
      .recordQuiescence(.testOnly(receipt))
    }

    static func testOnlyRecordRuntimeAdmission(
      _ receipt: RuntimeAdmissionReceipt
    ) -> RunCommand {
      .recordRuntimeAdmission(.testOnly(receipt))
    }

    static func testOnlyRecordRuntimeBinding(
      _ receipt: RuntimeExternalBindingReceipt
    ) -> RunCommand {
      .recordRuntimeBinding(.testOnly(receipt))
    }

    static func testOnlyRecordRuntimeRelease(
      _ receipt: RuntimeReleaseOutcomeReceipt
    ) -> RunCommand {
      .recordRuntimeRelease(.testOnly(receipt))
    }

    static func testOnlyActivatePostimageVerifier(
      _ receipt: KernelPostimageVerifierActivationReceipt
    ) -> RunCommand {
      .activatePostimageVerifier(.testOnly(receipt))
    }

    static func testOnlyRecordPostimageVerifierRuntimeBinding(
      binding: RuntimeExternalBindingReceipt,
      launch: KernelPostimageVerifierLaunchReceipt
    ) -> RunCommand {
      .recordPostimageVerifierRuntimeBinding(
        .testOnly(
          binding: binding,
          receipt: launch
        ))
    }

    static func testOnlyAdvanceIntegration(
      _ transition: IntegrationTransitionCommand
    ) -> RunCommand {
      .advanceIntegration(.testOnly(transition))
    }

    static func testOnlyAuthorizeCompletion(
      runID: KernelRunID,
      sourceSequence: UInt64,
      authorizer: ActorIdentity
    ) -> RunCommand {
      .authorizeCompletion(
        .testOnly(
          runID: runID,
          sourceSequence: sourceSequence,
          authorizer: authorizer
        ))
    }
  }
#endif

enum OrchestrationEventPayload: Codable, Hashable, Sendable {
  case runCreated(TaskContract)
  case planAccepted(KernelPlanProposal)
  case nodeAuthorized(KernelNodeID)
  case attemptStarted(KernelAttemptState)
  case executionRecorded(attemptID: AttemptID, disposition: KernelExecutionDisposition)
  case executionDerived(KernelExecutionDerivationReceipt)
  case externalDependencyObservationActivated(
    ExternalDependencyObservationActivationReceipt
  )
  case externalDependencyObservationLaunchVetoed(
    ExternalDependencyObservationLaunchVetoReceipt
  )
  case externalDependencyObservationRecorded(ExternalDependencyObservationReceipt)
  case verificationRecorded(VerificationReceipt)
  case reviewRecorded(IndependentReviewReceipt)
  case designBaselineFrozen(DesignBaselineBundle)
  case visualCandidateEvaluated(
    candidate: VisualCandidateBundle,
    receipt: VisualGateEvaluationReceipt
  )
  case strategyRetired(StrategyFingerprint, lessonDigest: ContentDigest)
  case causalConvergenceAdvanced(CausalConvergenceTransition)
  case occurrenceRecorded(OccurrenceReceipt)
  case journaledGitPreimageCaptured(
    WorkspaceJournaledGitPreimageCaptureReceipt
  )
  case journaledCanonicalPreimageCaptured(
    WorkspaceJournaledCanonicalPreimageReceipt
  )
  case preApplyCandidateIsolationRecorded(
    WorkspacePreApplyCandidateIsolationReceipt
  )
  case completedCandidateCaptured(
    WorkspaceCompletedCandidateCaptureReceipt
  )
  case completedCandidateMutationContentStored(
    WorkspaceCompletedCandidateMutationContentStoreReceipt
  )
  case completedCandidateMutationManifestProposed(
    WorkspaceCompletedCandidateMutationManifestProposalReceipt
  )
  case completedCandidateMutationPreparationFactsRecorded(
    WorkspaceCompletedCandidateMutationPreparationFactsReceipt
  )
  indirect case completedCandidateMutationRollbackRehearsed(
    WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt
  )
  case ratifiedBaselineContentCaptured(
    WorkspaceRatifiedBaselineContentCaptureReceipt
  )
  case journaledCandidateContentCaptured(
    WorkspaceJournaledCandidateContentCaptureReceipt
  )
  case journaledMutationContentStored(
    WorkspaceJournaledMutationContentStoreReceipt
  )
  case runtimeAdmissionRecorded(RuntimeAdmissionReceipt)
  case runtimeBindingRecorded(RuntimeExternalBindingReceipt)
  case providerLaunchRecorded(KernelProviderLaunchReceipt)
  case runtimeReleaseRecorded(RuntimeReleaseOutcomeReceipt)
  case workerResultParsed(KernelWorkerResultParseReceipt)
  case postimageVerifierActivated(KernelPostimageVerifierActivationReceipt)
  case externalDependencyObservationRuntimeLaunched(
    ExternalDependencyObservationRuntimeLaunchReceipt
  )
  case postimageVerifierLaunched(KernelPostimageVerifierLaunchReceipt)
  case postimageVerifierLaunchVetoed(
    KernelPostimageVerifierLaunchVetoReceipt
  )
  case productionMutationApplyVetoed(
    KernelProductionMutationApplyVetoReceipt
  )
  case runtimeDrainRecorded(RuntimeDrainReceipt)
  case integrationAdvanced(IntegrationTransitionEvent)
  case pauseRequested
  case completionRequested
  case stopRequested
  case quiescenceRecorded(QuiescenceReceipt)
  case completionAuthorizationRecorded(
    KernelCompletionAuthorizationReceipt
  )
  case runPaused
  case runStopped
  case completionAuthorized
}

struct OrchestrationEvent: Codable, Hashable, Sendable {
  var id: OrchestrationEventID
  var runID: KernelRunID
  var sequence: UInt64
  var commandID: RunCommandID
  var occurredAt: Date
  var payload: OrchestrationEventPayload
}

enum KernelRejection: Codable, Hashable, Sendable, Error {
  case staleSequence(expected: UInt64, actual: UInt64)
  case duplicateCommand(RunCommandID)
  case invalidContract([String])
  case invalidTransition(phase: KernelRunPhase, command: String)
  case invalidPlan(String)
  case invalidNodeRequirementOwnership(
    nodeID: KernelNodeID,
    unknownRequirementIDs: Set<RequirementID>
  )
  case invalidMandatoryRequirementOwnership(
    requirementID: RequirementID,
    ownerNodeIDs: Set<KernelNodeID>
  )
  case protectedBaselineScopeViolation(
    nodeID: KernelNodeID,
    baselineID: BaselineID,
    protectedPath: String,
    writableScope: String
  )
  case unknownNode(KernelNodeID)
  case unknownAttempt(AttemptID)
  case dependencyIncomplete(KernelNodeID)
  case strategyRetired(StrategyFingerprint)
  case mismatchedRequirements
  case executionNotVerifiable
  case legacyExecutionAuthorityRetired
  case executionDerivationRejected(ReceiptID)
  case externalDependencyObservationRejected(ExternalDependencyObservationViolation)
  case externalDependencyBlockerRejected(ReceiptID)
  case substitutionConstraintViolated(String)
  case deliverableCardinalityViolated(DeliverableCardinalityViolation)
  case verificationMissing
  case reviewNotIndependent
  case invalidDesignBaseline(String)
  case invalidVisualEvaluation(String)
  case invalidRuntimeReceipt(String)
  case invalidOccurrenceReceipt(String)
  case invalidGitPreimageCapture(String)
  case invalidCanonicalPreimage(String)
  case invalidPreApplyCandidateIsolation(String)
  case invalidBaselineContentCapture(String)
  case invalidCandidateContentCapture(String)
  case invalidCompletedCandidateMutationContentStore(String)
  case invalidCompletedCandidateMutationManifestProposal(String)
  case invalidCompletedCandidateMutationPreparationFacts(String)
  case invalidCompletedCandidateMutationRollbackRehearsal(String)
  case invalidMutationContentStore(String)
  case durationIncomplete(requiredSeconds: UInt64, acceptedSeconds: UInt64)
  case invalidConvergenceTransition(String)
  case invalidIntegrationTransition(IntegrationTransitionRejection)
  case convergenceAdmissionRejected(ConvergenceAdmissionRejection)
  case duplicateReceipt(ReceiptID)
  case quiescenceNotProven
  case evidenceIncomplete(Set<RequirementID>)
}

enum ReducerDecision: Equatable, Sendable {
  case accepted(events: [OrchestrationEvent], state: KernelRunState)
  case rejected(KernelRejection)
}

enum RunReducer {
  static func handle(
    state: KernelRunState,
    command: RunCommand,
    context: KernelCommandContext
  ) -> ReducerDecision {
    guard !state.processedCommandIDs.contains(context.commandID) else {
      return .rejected(.duplicateCommand(context.commandID))
    }
    guard context.expectedSequence == state.sequence else {
      return .rejected(
        .staleSequence(
          expected: context.expectedSequence,
          actual: state.sequence
        ))
    }

    let payloadDecision:
      Result<
        [OrchestrationEventPayload],
        KernelRejection
      >
    if case .recordRuntimeRelease(let authorized) = command {
      payloadDecision = decideRuntimeRelease(authorized, state: state)
    } else {
      payloadDecision = decide(
        state: state,
        command: command,
        context: context
      )
    }
    switch payloadDecision {
    case .failure(let rejection):
      return .rejected(rejection)
    case .success(let payloads):
      var next = state
      var events: [OrchestrationEvent] = []
      for (offset, payload) in payloads.enumerated() {
        let sequence = state.sequence + UInt64(offset) + 1
        let event = OrchestrationEvent(
          id: OrchestrationEventID("\(context.commandID.rawValue).\(sequence)"),
          runID: state.runID,
          sequence: sequence,
          commandID: context.commandID,
          occurredAt: context.issuedAt,
          payload: payload
        )
        next = reduce(state: next, event: event)
        events.append(event)
      }
      return .accepted(events: events, state: next)
    }
  }

  static func reduce(state: KernelRunState, event: OrchestrationEvent) -> KernelRunState {
    var next = state
    guard event.runID == state.runID, event.sequence == state.sequence + 1 else {
      return state
    }
    next.sequence = event.sequence
    next.processedCommandIDs.insert(event.commandID)
    switch event.payload {
    case .runCreated(let contract):
      next.contract = contract
      next.phase = .ready
    case .planAccepted(let plan):
      for node in plan.nodes {
        next.nodes[node.id] = KernelNodeState(
          contract: node,
          status: .proposed,
          attemptIDs: []
        )
      }
    case .nodeAuthorized(let nodeID):
      next.nodes[nodeID]?.status = .authorized
      next.phase = .ready
    case .attemptStarted(let attempt):
      next.attempts[attempt.id] = attempt
      next.nodes[attempt.nodeID]?.status = .executing
      next.nodes[attempt.nodeID]?.attemptIDs.append(attempt.id)
      next.activeAttemptID = attempt.id
      next.quiescenceReceipt = nil
      next.phase = .executing
    case .executionRecorded(let attemptID, let disposition):
      applyExecutionDisposition(
        attemptID: attemptID,
        disposition: disposition,
        to: &next
      )
    case .executionDerived(let receipt):
      guard !next.allReceiptIDs.contains(receipt.id),
        receipt.runID == next.runID,
        receipt.derivedAt == event.occurredAt,
        next.activeAttemptID == receipt.attemptID,
        next.attempts[receipt.attemptID]?.disposition == nil,
        let material = executionDerivationMaterial(
          state: next,
          source: receipt.source
        ),
        material.attemptID == receipt.attemptID,
        material.evidenceDigest == receipt.sourceEvidenceDigest,
        material.disposition == receipt.disposition
      else {
        return state
      }
      var receipts = next.executionDerivationReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.executionDerivationReceipts = receipts
      applyExecutionDisposition(
        attemptID: receipt.attemptID,
        disposition: receipt.disposition,
        to: &next
      )
    case .externalDependencyObservationActivated(let receipt):
      guard !state.allReceiptIDs.contains(receipt.id),
        ExternalDependencyObservationActivationCompiler
          .validationIssue(
            receipt,
            state: state,
            actor: receipt.observer,
            occurredAt: event.occurredAt
          ) == nil
      else {
        return state
      }
      var receipts =
        state
        .externalDependencyObservationActivationReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.externalDependencyObservationActivationReceipts = receipts
    case .externalDependencyObservationRuntimeLaunched(let receipt):
      guard !state.allReceiptIDs.contains(receipt.id),
        receipt.launchedAt == event.occurredAt,
        let activation =
          (state
          .externalDependencyObservationActivationReceipts ?? [:])[
            receipt.activationReceiptID
          ],
        let binding = state.runtimeBindingReceipts[
          receipt.bindingReceiptID
        ],
        ExternalDependencyObservationRuntimeLaunchCompiler.launch(
          receipt,
          matches: activation,
          binding: binding
        ),
        !(state
          .externalDependencyObservationRuntimeLaunchReceipts ?? [:])
          .values.contains(where: {
            $0.activationReceiptID == receipt.activationReceiptID
          }),
        !(state.externalDependencyObservationLaunchVetoReceipts ?? [:])
          .values.contains(where: {
            $0.activationReceiptID == receipt.activationReceiptID
          }),
        !(state.externalDependencyReceipts ?? [:]).values.contains(
          where: {
            $0.attemptID == receipt.attemptID
              && $0.dependencyID == receipt.dependencyID
          }
        )
      else {
        return state
      }
      var receipts =
        state
        .externalDependencyObservationRuntimeLaunchReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.externalDependencyObservationRuntimeLaunchReceipts = receipts
    case .externalDependencyObservationLaunchVetoed(let receipt):
      guard !state.allReceiptIDs.contains(receipt.id),
        ExternalDependencyObservationLaunchVetoCompiler
          .validationIssue(
            receipt,
            state: state,
            actor: receipt.observer,
            occurredAt: event.occurredAt
          ) == nil
      else {
        return state
      }
      var receipts =
        state
        .externalDependencyObservationLaunchVetoReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.externalDependencyObservationLaunchVetoReceipts = receipts
    case .postimageVerifierActivated(let receipt):
      var receipts = next.postimageVerifierActivationReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.postimageVerifierActivationReceipts = receipts
    case .postimageVerifierLaunched(let receipt):
      var receipts = next.postimageVerifierLaunchReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.postimageVerifierLaunchReceipts = receipts
    case .postimageVerifierLaunchVetoed(let receipt):
      var receipts = next.postimageVerifierLaunchVetoReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.postimageVerifierLaunchVetoReceipts = receipts
    case .productionMutationApplyVetoed(let receipt):
      guard !state.allReceiptIDs.contains(receipt.id),
        KernelProductionMutationApplyVetoCompiler.validationIssue(
          receipt,
          state: state,
          actor: receipt.actor,
          occurredAt: event.occurredAt
        ) == nil
      else {
        return state
      }
      var receipts = next.productionMutationApplyVetoReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.productionMutationApplyVetoReceipts = receipts
    case .externalDependencyObservationRecorded(let receipt):
      guard !state.allReceiptIDs.contains(receipt.id),
        externalDependencyObservationValidationIssue(
          receipt,
          state: state,
          actor: receipt.observer,
          occurredAt: event.occurredAt
        ) == nil
      else {
        return state
      }
      var receipts = next.externalDependencyReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.externalDependencyReceipts = receipts
    case .verificationRecorded(let receipt):
      next.verificationReceipts[receipt.id] = receipt
      next.attempts[receipt.attemptID]?.verificationReceiptIDs.insert(receipt.id)
      if receipt.result == .rejected {
        for (transactionID, integration) in next.integrationTransactions {
          guard
            let sourceID = integration
              .postimageVerificationReceipt?
              .sourceVerificationReceiptID,
            let source = next.verificationReceipts[sourceID],
            source.requirementIDs.contains(where: {
              !next.verificationIsEffective(
                source,
                requirementID: $0
              )
            })
          else {
            continue
          }
          switch integration.phase {
          case .postimageVerified, .independentlyAccepted:
            var revoked = integration
            revoked.phase = .rollbackRequired
            next.integrationTransactions[transactionID] = revoked
          default:
            break
          }
        }
      }
      if let nodeID = next.attempts[receipt.attemptID]?.nodeID,
        next.nodes[nodeID]?.status == .accepted
      {
        let required = next.nodes[nodeID]?.contract.requirementIDs ?? []
        if !required.isSubset(of: next.acceptedRequirementIDs) {
          next.nodes[nodeID]?.status = .awaitingVerification
        }
      }
    case .reviewRecorded(let receipt):
      next.reviewReceipts[receipt.id] = receipt
      next.attempts[receipt.attemptID]?.reviewReceiptIDs.insert(receipt.id)
      if let nodeID = next.attempts[receipt.attemptID]?.nodeID {
        switch receipt.decision {
        case .approveCandidate:
          let required = next.nodes[nodeID]?.contract.requirementIDs ?? []
          let accepted = next.acceptedRequirementIDs
          next.nodes[nodeID]?.status =
            required.isSubset(of: accepted)
            ? .accepted
            : .awaitingVerification
        case .rejectCandidate:
          next.nodes[nodeID]?.status = .rejected
        case .needsDifferentEvidence:
          next.nodes[nodeID]?.status = .awaitingVerification
        }
      }
    case .designBaselineFrozen(let baseline):
      guard
        designBaselineValidationIssues(
          state: next,
          baseline: baseline,
          recordedAt: event.occurredAt
        ).isEmpty
      else { return state }
      next.designBaseline = baseline
    case .visualCandidateEvaluated(let candidate, let receipt):
      guard let baseline = next.designBaseline,
        let attempt = next.attempts[receipt.attemptID],
        attempt.disposition?.canEnterVerification == true,
        !receipt.requirementIDs.isEmpty,
        receipt.requirementIDs.isSubset(of: attempt.requirementIDs),
        receipt.requirementIDs.isSubset(of: baseline.requirementIDs),
        receipt.baselineID == baseline.id,
        receipt.candidateSourceTree == candidate.sourceTree,
        receipt.candidateBuiltArtifact == candidate.builtArtifact,
        receipt.deterministicEvidenceDigest
          == DesignBaselineGate.deterministicEvidenceDigest(
            baseline: baseline,
            candidate: candidate
          ),
        receipt.evaluatedAt == event.occurredAt,
        receipt.journalSequence == event.sequence,
        receipt.independentReviewReceiptID == candidate.independentReview?.id
      else {
        return state
      }
      guard
        nativeVisualAuthorityValidationIssues(
          receipt: receipt,
          candidate: candidate
        ).isEmpty
      else { return state }
      if let review = candidate.independentReview,
        review.workerLineageDigest != attempt.worker.lineageDigest
          || review.reviewer.lineageDigest == attempt.worker.lineageDigest
      {
        return state
      }
      let recomputed = DesignBaselineGate.evaluate(
        baseline: baseline,
        candidate: candidate
      )
      guard receipt.result == recomputed else { return state }
      next.visualGateReceipts[receipt.id] = receipt
      if let nodeID = next.attempts[receipt.attemptID]?.nodeID {
        if !receipt.result.accepted {
          next.nodes[nodeID]?.status = .rejected
        } else {
          let required = next.nodes[nodeID]?.contract.requirementIDs ?? []
          let accepted = next.acceptedRequirementIDs
          next.nodes[nodeID]?.status =
            required.isSubset(of: accepted)
            ? .accepted
            : .awaitingVerification
        }
      }
    case .strategyRetired(let fingerprint, _):
      next.retiredStrategies.insert(fingerprint)
    case .causalConvergenceAdvanced(let transition):
      switch transition {
      case .initialized(let epochID, let budget):
        next.convergenceGovernor = ConvergenceGovernor(
          epochID: epochID,
          budget: budget
        )
      case .attemptAdmitted(let request, let expectedFingerprint):
        guard var governor = next.convergenceGovernor,
          governor.admit(request) == .admitted(expectedFingerprint)
        else {
          return state
        }
        next.convergenceGovernor = governor
      case .failureRecorded(
        let
          fingerprint,
        let
          failure,
        let
          expectedAction,
        let
          lessonDigest
      ):
        guard var governor = next.convergenceGovernor,
          governor.recordFailure(
            strategy: fingerprint,
            failure: failure,
            lessonDigest: lessonDigest
          ) == expectedAction
        else { return state }
        next.convergenceGovernor = governor
      case .replacementAuthorized(let receipt, let replacement, let failures):
        guard var governor = next.convergenceGovernor,
          governor.authorizeReplacement(
            receiptID: receipt.id,
            predecessor: receipt.predecessorFingerprint,
            replacement: replacement,
            failures: failures,
            delta: receipt.delta
          ),
          governor.replacementAuthorizationReceipts[
            replacement.fingerprint
          ] == receipt
        else { return state }
        next.convergenceGovernor = governor
      case .conditionChanged(
        let
          fingerprint,
        let
          previousFailureDigest,
        let
          observationDigest
      ):
        guard var governor = next.convergenceGovernor,
          governor.observeChangedCondition(
            for: fingerprint,
            previousFailureDigest: previousFailureDigest,
            observationDigest: observationDigest
          )
        else { return state }
        next.convergenceGovernor = governor
      case .progressEvaluated(let fingerprint, let expected, let previous, let current):
        guard var governor = next.convergenceGovernor,
          governor.recordProgress(
            strategy: fingerprint,
            previous: previous,
            current: current
          ) == expected
        else { return state }
        next.convergenceGovernor = governor
        var causal = next.causalProgressCommandIDs ?? []
        causal.insert(event.commandID)
        next.causalProgressCommandIDs = causal
        if expected {
          var accepted = next.acceptedProgressCommandIDs ?? []
          accepted.insert(event.commandID)
          next.acceptedProgressCommandIDs = accepted
        }
      case .planExpansionConsumed:
        guard var governor = next.convergenceGovernor,
          governor.consumePlanExpansion()
        else { return state }
        next.convergenceGovernor = governor
      }
    case .occurrenceRecorded(let receipt):
      var receipts = next.occurrenceReceipts ?? []
      receipts.append(receipt)
      next.occurrenceReceipts = receipts
    case .journaledGitPreimageCaptured(let receipt):
      guard
        gitPreimageCaptureValidationIssue(
          receipt,
          state: next,
          actor: receipt.captureActor,
          occurredAt: event.occurredAt
        ) == nil, next.journaledGitPreimageCaptureReceipt == nil
      else {
        return state
      }
      next.journaledGitPreimageCaptureReceipt = receipt
    case .journaledCanonicalPreimageCaptured(let receipt):
      guard
        canonicalPreimageValidationIssue(
          receipt,
          state: next,
          actor: receipt.captureActor,
          occurredAt: event.occurredAt
        ) == nil, next.journaledCanonicalPreimageReceipt == nil
      else {
        return state
      }
      next.journaledCanonicalPreimageReceipt = receipt
    case .preApplyCandidateIsolationRecorded(let receipt):
      guard
        preApplyCandidateIsolationValidationIssue(
          receipt,
          state: next,
          actor: receipt.isolationActor,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts = next.preApplyCandidateIsolationReceipts ?? [:]
      guard receipts[receipt.attemptID] == nil else { return state }
      receipts[receipt.attemptID] = receipt
      next.preApplyCandidateIsolationReceipts = receipts
    case .completedCandidateCaptured(let receipt):
      guard
        completedCandidateCaptureValidationIssue(
          receipt,
          state: next,
          actor: receipt.captureActor,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts = next.completedCandidateCaptureReceipts ?? [:]
      guard receipts[receipt.attemptID] == nil else { return state }
      receipts[receipt.attemptID] = receipt
      next.completedCandidateCaptureReceipts = receipts
    case .completedCandidateMutationContentStored(let receipt):
      guard
        completedCandidateMutationContentStoreValidationIssue(
          receipt,
          state: next,
          actor: receipt.storedBy,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts =
        next.completedCandidateMutationContentStoreReceipts ?? [:]
      guard receipts[receipt.derivationDigest] == nil else { return state }
      receipts[receipt.derivationDigest] = receipt
      next.completedCandidateMutationContentStoreReceipts = receipts
    case .completedCandidateMutationManifestProposed(let receipt):
      guard
        completedCandidateMutationManifestProposalValidationIssue(
          receipt,
          state: next,
          actor: receipt.proposedBy,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      guard
        let store =
          (next
          .completedCandidateMutationContentStoreReceipts ?? [:])
          .values.first(where: {
            $0.receiptDigest
              == receipt
              .completedCandidateContentStoreReceiptDigest
          })
      else { return state }
      var receipts =
        next
        .completedCandidateMutationManifestProposalReceipts ?? [:]
      guard receipts[store.derivationDigest] == nil else { return state }
      receipts[store.derivationDigest] = receipt
      next.completedCandidateMutationManifestProposalReceipts = receipts
    case .completedCandidateMutationPreparationFactsRecorded(let receipt):
      guard
        completedCandidateMutationPreparationFactsValidationIssue(
          receipt,
          state: next,
          actor: receipt.preparedBy,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts =
        next
        .completedCandidateMutationPreparationFactsReceipts ?? [:]
      guard receipts[receipt.proposalReceiptDigest] == nil else {
        return state
      }
      receipts[receipt.proposalReceiptDigest] = receipt
      next.completedCandidateMutationPreparationFactsReceipts = receipts
    case .completedCandidateMutationRollbackRehearsed(let receipt):
      guard
        completedCandidateMutationRollbackRehearsalValidationIssue(
          receipt,
          state: next,
          actor: receipt.rehearsedBy,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts =
        next
        .completedCandidateMutationRollbackRehearsalReceipts ?? [:]
      guard receipts[receipt.proposalReceiptDigest] == nil else {
        return state
      }
      receipts[receipt.proposalReceiptDigest] = receipt
      next.completedCandidateMutationRollbackRehearsalReceipts = receipts
    case .ratifiedBaselineContentCaptured(let receipt):
      guard
        baselineContentCaptureValidationIssue(
          receipt,
          state: next,
          actor: receipt.captureActor,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts = next.ratifiedBaselineContentCaptureReceipts ?? [:]
      guard receipts[receipt.derivationDigest] == nil else { return state }
      receipts[receipt.derivationDigest] = receipt
      next.ratifiedBaselineContentCaptureReceipts = receipts
    case .journaledCandidateContentCaptured(let receipt):
      guard
        candidateContentCaptureValidationIssue(
          receipt,
          state: next,
          actor: receipt.captureActor,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts = next.journaledCandidateContentCaptureReceipts ?? [:]
      guard receipts[receipt.derivationDigest] == nil else { return state }
      receipts[receipt.derivationDigest] = receipt
      next.journaledCandidateContentCaptureReceipts = receipts
    case .journaledMutationContentStored(let receipt):
      guard
        mutationContentStoreValidationIssue(
          receipt,
          state: next,
          actor: receipt.storedBy,
          occurredAt: event.occurredAt
        ) == nil
      else { return state }
      var receipts = next.journaledMutationContentStoreReceipts ?? [:]
      guard receipts[receipt.derivationDigest] == nil else { return state }
      receipts[receipt.derivationDigest] = receipt
      next.journaledMutationContentStoreReceipts = receipts
    case .runtimeAdmissionRecorded(let receipt):
      next.runtimeAdmissionReceipts[receipt.id] = receipt
      if case .accepted(let lease, _) = receipt.outcome {
        next.runtimeLiveLeases[lease.request.resourceID] = lease
        next.runtimeFailedReleases.remove(lease.request.resourceID)
      }
    case .runtimeBindingRecorded(let receipt):
      next.runtimeBindingReceipts[receipt.id] = receipt
      if receipt.accepted,
        var lease = next.runtimeLiveLeases[receipt.resourceID]
      {
        lease.request.externalIdentity = receipt.identity
        next.runtimeLiveLeases[receipt.resourceID] = lease
      }
    case .providerLaunchRecorded(let receipt):
      guard !next.allReceiptIDs.contains(receipt.id),
        let binding =
          next.runtimeBindingReceipts[receipt.bindingReceiptID],
        receipt.isValid(binding: binding)
      else {
        return state
      }
      var receipts = next.providerLaunchReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.providerLaunchReceipts = receipts
    case .runtimeReleaseRecorded(let receipt):
      next.runtimeReleaseReceipts[receipt.id] = receipt
      switch receipt.outcome {
      case .released:
        next.runtimeLiveLeases[receipt.resourceID] = nil
        next.runtimeFailedReleases.remove(receipt.resourceID)
      case .cleanupFailed:
        next.runtimeFailedReleases.insert(receipt.resourceID)
      case .rejected:
        break
      }
    case .workerResultParsed(let receipt):
      var receipts = next.workerResultParseReceipts ?? [:]
      receipts[receipt.id] = receipt
      next.workerResultParseReceipts = receipts
    case .runtimeDrainRecorded(let receipt):
      next.runtimeDrainReceipts[receipt.id] = receipt
      next.lastRuntimeDrainReceiptID = receipt.id
    case .integrationAdvanced(let transition):
      let transactionID = transition.transactionID
      let current = next.integrationTransactions[transactionID]
      if let updated = IntegrationTransactionReducer.reduce(
        current: current,
        event: transition
      ) {
        next.integrationTransactions[transactionID] = updated
      }
    case .pauseRequested:
      next.phase = .pauseRequested
    case .completionRequested:
      next.phase = .completionRequested
    case .stopRequested:
      next.phase = .stopRequested
    case .quiescenceRecorded(let receipt):
      let retainedDrain = next.lastRuntimeDrainReceiptID.flatMap {
        next.runtimeDrainReceipts[$0]
      }
      let phaseMatchesIntent: Bool
      switch (next.phase, receipt.intent) {
      case (.pauseRequested, .pause),
        (.stopRequested, .stop),
        (.stopRequested, .quit),
        (.completionRequested, .complete):
        phaseMatchesIntent = true
      default:
        phaseMatchesIntent = false
      }
      guard receipt.runID == next.runID,
        receipt.provesQuiescence,
        receipt.liveResources == Set(next.runtimeLiveLeases.keys),
        receipt.failedReleases == next.runtimeFailedReleases,
        let retainedDrain,
        retainedDrain.snapshot.intent == receipt.intent,
        receipt.observedAtMonotonicNanoseconds
          >= retainedDrain.observedAtMonotonicNanoseconds,
        phaseMatchesIntent
      else {
        return state
      }
      next.quiescenceReceipt = receipt
      // A physically quiescent pause/stop is itself the runtime-owned proof
      // that an unfinished active attempt can no longer execute. Closing it as
      // interrupted here avoids the circular requirement that an attempt must
      // already be closed before the receipt capable of closing it is accepted.
      if receipt.intent != .complete, let attemptID = next.activeAttemptID {
        applyExecutionDisposition(
          attemptID: attemptID,
          disposition: .interrupted,
          to: &next
        )
      }
    case .completionAuthorizationRecorded(let receipt):
      let issues = KernelCompletionEvidenceCompiler.validationIssues(
        state: state,
        sourceFrameDigest: receipt.sourceFrameDigest,
        sourceOccurredAt: receipt.sourceOccurredAt,
        authorizedAt: receipt.authorizedAt,
        authorizer: receipt.authorizer
      )
      guard issues.isEmpty,
        receipt.runID == state.runID,
        receipt.contractID == state.contract?.id,
        receipt.sourceSequence == state.sequence,
        receipt.sourceEvidenceDigest
          == KernelCompletionEvidenceCompiler.evidenceDigest(
            state: state,
            sourceFrameDigest: receipt.sourceFrameDigest,
            sourceOccurredAt: receipt.sourceOccurredAt,
            authorizer: receipt.authorizer
          ),
        receipt.acceptedRequirementIDs == state.acceptedRequirementIDs,
        receipt.evidenceReceiptIDs == state.allReceiptIDs,
        receipt.authorizedAt == event.occurredAt,
        state.completionAuthorizationReceipt == nil
      else {
        return state
      }
      next.completionAuthorizationReceipt = receipt
    case .runPaused:
      next.phase = .paused
    case .runStopped:
      next.phase = .stopped
    case .completionAuthorized:
      next.phase = .completed
    }
    return next
  }

  private static func decide(
    state: KernelRunState,
    command: RunCommand,
    context: KernelCommandContext
  ) -> Result<[OrchestrationEventPayload], KernelRejection> {
    switch command {
    case .createRun(let contract):
      guard state.phase == .uninitialized else {
        return .failure(.invalidTransition(phase: state.phase, command: "createRun"))
      }
      let issues = contract.validationIssues()
      return issues.isEmpty ? .success([.runCreated(contract)]) : .failure(.invalidContract(issues))

    case .proposePlan(let plan):
      guard state.phase == .ready, let contract = state.contract else {
        return .failure(.invalidTransition(phase: state.phase, command: "proposePlan"))
      }
      guard plan.contractDigest == contract.objectiveDigest else {
        return .failure(.invalidPlan("plan is not bound to the current contract digest"))
      }
      let ids = plan.nodes.map(\.id)
      guard !ids.isEmpty, Set(ids).count == ids.count else {
        return .failure(.invalidPlan("plan nodes must be non-empty and uniquely identified"))
      }
      let knownRequirements = Set(contract.requirements.map(\.id))
      let knownNodes = Set(ids)
      var requirementOwners: [RequirementID: Set<KernelNodeID>] = [:]
      for node in plan.nodes {
        let unknownRequirementIDs = node.requirementIDs.subtracting(knownRequirements)
        guard !node.requirementIDs.isEmpty, unknownRequirementIDs.isEmpty else {
          return .failure(
            .invalidNodeRequirementOwnership(
              nodeID: node.id,
              unknownRequirementIDs: unknownRequirementIDs
            ))
        }
        for requirementID in node.requirementIDs {
          requirementOwners[requirementID, default: []].insert(node.id)
        }
        guard node.dependencies.isSubset(of: knownNodes),
          !node.dependencies.contains(node.id)
        else {
          return .failure(.invalidPlan("dependencies must reference other nodes in the plan"))
        }
        guard node.mutationScope.maximumChangedFiles >= 0,
          node.mutationScope.maximumChangedBytes >= 0
        else {
          return .failure(.invalidPlan("mutation budgets must not be negative"))
        }
        guard !node.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !node.strategyFingerprint.rawValue.isEmpty
        else {
          return .failure(.invalidPlan("node objective and strategy fingerprint are required"))
        }
        guard
          node.mutationScope.writablePaths.allSatisfy({
            WorkspacePathPolicy.canonical($0) == $0
          })
        else {
          return .failure(.invalidPlan("node mutation scopes must be canonical workspace paths"))
        }
        guard
          node.mutationScope.writablePaths.allSatisfy({ path in
            contract.authorityCeiling.writableScopes.contains(where: {
              WorkspacePathPolicy.contains(scope: $0, path: path)
            })
          })
        else {
          return .failure(
            .invalidPlan("node mutation scope exceeds the contract authority ceiling"))
        }
        let protectedBindings = contract.protectedWorkspaceEntryBindings.sorted {
          ($0.baselineID.rawValue, $0.entry.path)
            < ($1.baselineID.rawValue, $1.entry.path)
        }
        for binding in protectedBindings {
          for writableScope in node.mutationScope.writablePaths.sorted()
          where WorkspacePathPolicy.overlaps(writableScope, binding.entry.path) {
            return .failure(
              .protectedBaselineScopeViolation(
                nodeID: node.id,
                baselineID: binding.baselineID,
                protectedPath: binding.entry.path,
                writableScope: writableScope
              ))
          }
        }
        guard
          node.capabilityIDs.isSubset(
            of: contract.authorityCeiling.capabilityIDs
          )
        else {
          return .failure(.invalidPlan("node capabilities exceed the contract authority ceiling"))
        }
      }
      for requirementID in contract.mandatoryRequirementIDs.sorted(by: {
        $0.rawValue < $1.rawValue
      }) {
        let ownerNodeIDs = requirementOwners[requirementID, default: []]
        guard ownerNodeIDs.count == 1 else {
          return .failure(
            .invalidMandatoryRequirementOwnership(
              requirementID: requirementID,
              ownerNodeIDs: ownerNodeIDs
            ))
        }
      }
      if hasDependencyCycle(plan.nodes) {
        return .failure(.invalidPlan("plan dependencies must be acyclic"))
      }
      return .success([.planAccepted(plan)])

    case .authorizeNode(let nodeID):
      guard state.phase == .ready || state.phase == .blocked else {
        return .failure(.invalidTransition(phase: state.phase, command: "authorizeNode"))
      }
      guard let node = state.nodes[nodeID] else { return .failure(.unknownNode(nodeID)) }
      guard !state.retiredStrategies.contains(node.contract.strategyFingerprint) else {
        return .failure(.strategyRetired(node.contract.strategyFingerprint))
      }
      for dependency in node.contract.dependencies {
        guard state.nodes[dependency]?.status == .accepted else {
          return .failure(.dependencyIncomplete(dependency))
        }
      }
      return .success([.nodeAuthorized(nodeID)])

    case .startAttempt(let attemptID, let nodeID, let requirements, let fingerprint):
      guard state.phase == .ready, state.activeAttemptID == nil else {
        return .failure(.invalidTransition(phase: state.phase, command: "startAttempt"))
      }
      guard let node = state.nodes[nodeID], node.status == .authorized else {
        return .failure(.unknownNode(nodeID))
      }
      guard requirements == node.contract.requirementIDs else {
        return .failure(.mismatchedRequirements)
      }
      guard fingerprint == node.contract.strategyFingerprint,
        !state.retiredStrategies.contains(fingerprint)
      else {
        return .failure(.strategyRetired(fingerprint))
      }
      guard
        let admittedRequest = state.convergenceGovernor?
          .admittedRequest(for: attemptID),
        admittedRequest.strategy.fingerprint == fingerprint,
        admittedRequest.strategy.requirementIDs == requirements
      else {
        return .failure(
          .invalidConvergenceTransition(
            "attempt start requires an exact accepted causal admission"
          ))
      }
      let attempt = KernelAttemptState(
        id: attemptID,
        nodeID: nodeID,
        requirementIDs: requirements,
        strategyFingerprint: fingerprint,
        worker: context.actor,
        startedAt: context.issuedAt,
        disposition: nil,
        verificationReceiptIDs: [],
        reviewReceiptIDs: []
      )
      return .success([.attemptStarted(attempt)])

    case .recordExecution:
      return .failure(.legacyExecutionAuthorityRetired)

    case .deriveExecution(let receiptID, let source):
      guard !state.allReceiptIDs.contains(receiptID) else {
        return .failure(.duplicateReceipt(receiptID))
      }
      guard
        let material = executionDerivationMaterial(
          state: state,
          source: source
        ), state.activeAttemptID == material.attemptID,
        state.attempts[material.attemptID]?.disposition == nil
      else {
        return .failure(.executionDerivationRejected(receiptID))
      }
      let receipt = KernelExecutionDerivationReceipt(
        id: receiptID,
        runID: state.runID,
        attemptID: material.attemptID,
        source: source,
        sourceEvidenceDigest: material.evidenceDigest,
        disposition: material.disposition,
        derivedAt: context.issuedAt
      )
      return .success([.executionDerived(receipt)])

    case .activateExternalDependencyObservation(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      if let issue =
        ExternalDependencyObservationActivationCompiler
        .validationIssue(
          receipt,
          state: state,
          actor: context.actor,
          occurredAt: context.issuedAt
        )
      {
        return .failure(.invalidRuntimeReceipt(issue))
      }
      return .success([
        .externalDependencyObservationActivated(receipt)
      ])

    case .recordExternalDependencyObservationRuntimeBinding(
      let authorization
    ):
      let binding = authorization.binding
      let launch = authorization.receipt
      guard binding.id != launch.id,
        !state.allReceiptIDs.contains(binding.id),
        !state.allReceiptIDs.contains(launch.id)
      else {
        return .failure(
          .duplicateReceipt(
            state.allReceiptIDs.contains(binding.id)
              ? binding.id
              : launch.id
          ))
      }
      guard state.phase == .executing,
        binding.runID == state.runID,
        binding.accepted,
        !binding.identity.stableDigest.rawValue.isEmpty,
        let lease = state.runtimeLiveLeases[binding.resourceID],
        lease.request.leaseID == binding.leaseID,
        lease.request.kind == .processTree,
        lease.request.purpose == .productive,
        lease.request.ownership == .owned,
        lease.request.releasePolicy == .gracefulThenTerminate,
        lease.request.externalIdentity == nil || lease.request.externalIdentity == binding.identity,
        binding.observedAtMonotonicNanoseconds >= lease.admittedAtMonotonicNanoseconds,
        lease.request.attemptID == launch.attemptID,
        state.activeAttemptID == launch.attemptID,
        state.attempts[launch.attemptID]?.disposition == nil,
        launch.observer == context.actor,
        launch.launchedAt == context.issuedAt,
        let activation =
          (state
          .externalDependencyObservationActivationReceipts ?? [:])[
            launch.activationReceiptID
          ],
        ExternalDependencyObservationRuntimeLaunchCompiler.launch(
          launch,
          matches: activation,
          binding: binding
        ),
        !(state
          .externalDependencyObservationRuntimeLaunchReceipts ?? [:])
          .values.contains(where: {
            $0.activationReceiptID == launch.activationReceiptID
          }),
        !(state.externalDependencyObservationLaunchVetoReceipts ?? [:])
          .values.contains(where: {
            $0.activationReceiptID == launch.activationReceiptID
          }),
        !(state.externalDependencyReceipts ?? [:]).values.contains(
          where: {
            $0.attemptID == launch.attemptID
              && $0.dependencyID == launch.dependencyID
          }
        )
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "external dependency observer launch provenance mismatch"
          ))
      }
      return .success([
        .runtimeBindingRecorded(binding),
        .externalDependencyObservationRuntimeLaunched(launch),
      ])

    case .recordExternalDependencyObservationLaunchVeto(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      if let issue =
        ExternalDependencyObservationLaunchVetoCompiler
        .validationIssue(
          receipt,
          state: state,
          actor: context.actor,
          occurredAt: context.issuedAt
        )
      {
        return .failure(.invalidRuntimeReceipt(issue))
      }
      return .success([
        .externalDependencyObservationLaunchVetoed(receipt)
      ])

    case .recordExternalDependencyObservation(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      if let violation = externalDependencyObservationValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(
          .externalDependencyObservationRejected(violation)
        )
      }
      return .success([.externalDependencyObservationRecorded(receipt)])

    case .recordVerification(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard let attempt = state.attempts[receipt.attemptID] else {
        return .failure(.unknownAttempt(receipt.attemptID))
      }
      guard attempt.disposition?.canEnterVerification == true else {
        return .failure(.executionNotVerifiable)
      }
      guard receipt.requirementIDs.isSubset(of: attempt.requirementIDs) else {
        return .failure(.mismatchedRequirements)
      }
      if receipt.postimageEvidenceBatch != nil {
        guard
          KernelPostimageVerificationAuthority
            .batchMatchesVerification(receipt)
        else {
          return .failure(
            .invalidRuntimeReceipt(
              "postimage verification batch is malformed"
            ))
        }
      }
      if receipt.result == .accepted,
        let contract = state.contract,
        let violation = substitutionViolation(
          contract: contract,
          receipt: receipt
        )
      {
        return .failure(.substitutionConstraintViolated(violation))
      }
      if receipt.result == .accepted,
        let contract = state.contract,
        let violation = deliverableCardinalityViolation(
          contract: contract,
          receipt: receipt
        )
      {
        return .failure(.deliverableCardinalityViolated(violation))
      }
      return .success([.verificationRecorded(receipt)])

    case .recordReview(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard let attempt = state.attempts[receipt.attemptID] else {
        return .failure(.unknownAttempt(receipt.attemptID))
      }
      guard receipt.reviewer == context.actor,
        receipt.reviewer.lineageDigest != attempt.worker.lineageDigest
      else {
        return .failure(.reviewNotIndependent)
      }
      let verified = state.verificationReceipts.values.reduce(into: Set<RequirementID>()) {
        if $1.attemptID == receipt.attemptID,
          $1.result == .accepted,
          receipt.sourceRevision == $1.sourceRevision,
          state.reviewMatchesVerification(
            receipt,
            verification: $1
          )
        {
          for requirementID in $1.requirementIDs
          where
            state.verificationIsEffective(
              $1,
              requirementID: requirementID
            )
          {
            $0.insert(requirementID)
          }
        }
      }
      guard receipt.requirementIDs.isSubset(of: verified),
        receipt.requirementIDs.isSubset(of: attempt.requirementIDs)
      else {
        return .failure(.verificationMissing)
      }
      return .success([.reviewRecorded(receipt)])

    case .freezeDesignBaseline(let authorized):
      let baseline = authorized.baseline
      guard state.phase == .ready,
        state.designBaseline == nil,
        state.attempts.isEmpty,
        context.actor == baseline.authority.authority
      else {
        return .failure(
          .invalidDesignBaseline(
            "baseline must be authority-recorded exactly once before execution"
          ))
      }
      let issues = designBaselineValidationIssues(
        state: state,
        baseline: baseline,
        recordedAt: context.issuedAt
      )
      guard issues.isEmpty else {
        return .failure(.invalidDesignBaseline(issues.sorted().joined(separator: "; ")))
      }
      guard !state.allReceiptIDs.contains(baseline.authority.id) else {
        return .failure(.duplicateReceipt(baseline.authority.id))
      }
      return .success([.designBaselineFrozen(baseline)])

    case .evaluateVisualCandidate(let authorized):
      let receiptID = authorized.receiptID
      let attemptID = authorized.attemptID
      let requirementIDs = authorized.requirementIDs
      let candidate = authorized.candidate
      guard state.phase == .evaluating,
        let baseline = state.designBaseline,
        let attempt = state.attempts[attemptID],
        attempt.disposition?.canEnterVerification == true
      else {
        return .failure(
          .invalidVisualEvaluation(
            "visual evaluation requires a frozen baseline and completed attempt"
          ))
      }
      guard !state.allReceiptIDs.contains(receiptID) else {
        return .failure(.duplicateReceipt(receiptID))
      }
      guard !requirementIDs.isEmpty,
        requirementIDs.isSubset(of: attempt.requirementIDs),
        requirementIDs.isSubset(of: baseline.requirementIDs)
      else {
        return .failure(.mismatchedRequirements)
      }
      if let independentID = candidate.independentReview?.id,
        state.visualGateReceipts.values.contains(where: {
          $0.independentReviewReceiptID == independentID
        })
      {
        return .failure(
          .invalidVisualEvaluation(
            "independent review receipt cannot authorize multiple candidates"
          ))
      }
      if let review = candidate.independentReview,
        review.workerLineageDigest != attempt.worker.lineageDigest
          || review.reviewer.lineageDigest == attempt.worker.lineageDigest
      {
        return .failure(
          .invalidVisualEvaluation(
            "independent visual review lineage does not match the actual worker"
          ))
      }
      let deterministicDigest = DesignBaselineGate.deterministicEvidenceDigest(
        baseline: baseline,
        candidate: candidate
      )
      guard !deterministicDigest.rawValue.isEmpty,
        !candidate.sourceTree.rawValue.isEmpty,
        !candidate.builtArtifact.rawValue.isEmpty
      else {
        return .failure(
          .invalidVisualEvaluation(
            "candidate evidence could not be content-addressed"
          ))
      }
      let nativeAuthorityProbe = VisualGateEvaluationReceipt(
        id: receiptID,
        attemptID: attemptID,
        requirementIDs: requirementIDs,
        baselineID: baseline.id,
        candidateSourceTree: candidate.sourceTree,
        candidateBuiltArtifact: candidate.builtArtifact,
        deterministicEvidenceDigest: deterministicDigest,
        evaluator: context.actor,
        evaluatedAt: context.issuedAt,
        journalSequence: state.sequence + 1,
        independentReviewReceiptID: candidate.independentReview?.id,
        result: DesignBaselineGate.evaluate(
          baseline: baseline,
          candidate: candidate
        ),
        nativeReviewRequestDigest:
          authorized.nativeReviewRequestDigest,
        nativeCaptureAttestationDigests:
          authorized.nativeCaptureAttestationDigests,
        nativeMeasurementAttestationDigests:
          authorized.nativeMeasurementAttestationDigests,
        nativeReviewCompletedAt: authorized.nativeReviewCompletedAt
      )
      let nativeIssues = nativeVisualAuthorityValidationIssues(
        receipt: nativeAuthorityProbe,
        candidate: candidate
      )
      guard nativeIssues.isEmpty else {
        return .failure(
          .invalidVisualEvaluation(
            nativeIssues.sorted().joined(separator: "; ")
          ))
      }
      let result = nativeAuthorityProbe.result
      let receipt = VisualGateEvaluationReceipt(
        id: receiptID,
        attemptID: attemptID,
        requirementIDs: requirementIDs,
        baselineID: baseline.id,
        candidateSourceTree: candidate.sourceTree,
        candidateBuiltArtifact: candidate.builtArtifact,
        deterministicEvidenceDigest: deterministicDigest,
        evaluator: context.actor,
        evaluatedAt: context.issuedAt,
        journalSequence: state.sequence + 1,
        independentReviewReceiptID: candidate.independentReview?.id,
        result: result,
        nativeReviewRequestDigest:
          authorized.nativeReviewRequestDigest,
        nativeCaptureAttestationDigests:
          authorized.nativeCaptureAttestationDigests,
        nativeMeasurementAttestationDigests:
          authorized.nativeMeasurementAttestationDigests,
        nativeReviewCompletedAt: authorized.nativeReviewCompletedAt
      )
      return .success([
        .visualCandidateEvaluated(
          candidate: candidate,
          receipt: receipt
        )
      ])

    case .retireStrategy(let fingerprint, let lessonDigest):
      guard state.phase == .ready || state.phase == .evaluating || state.phase == .blocked else {
        return .failure(.invalidTransition(phase: state.phase, command: "retireStrategy"))
      }
      guard !lessonDigest.rawValue.isEmpty else {
        return .failure(.invalidPlan("strategy retirement requires a durable lesson"))
      }
      return .success([.strategyRetired(fingerprint, lessonDigest: lessonDigest)])

    case .initializeConvergence(let epochID, let budget):
      guard state.contract != nil,
        state.convergenceGovernor == nil,
        !state.phase.isTerminal,
        !epochID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        budget.validationIssues().isEmpty
      else {
        return .failure(
          .invalidConvergenceTransition(
            "convergence initialization requires a live run, unique epoch, and valid budget"
          ))
      }
      return .success([
        .causalConvergenceAdvanced(
          .initialized(epochID: epochID, budget: budget)
        )
      ])

    case .admitCausalAttempt(let request):
      guard var governor = state.convergenceGovernor else {
        return .failure(.invalidConvergenceTransition("convergence is not initialized"))
      }
      let decision = governor.admit(request)
      guard case .admitted(let fingerprint) = decision else {
        if case .rejected(let rejection) = decision {
          return .failure(.convergenceAdmissionRejected(rejection))
        }
        preconditionFailure("ConvergenceAdmissionDecision is exhaustive")
      }
      return .success([
        .causalConvergenceAdvanced(
          .attemptAdmitted(request, fingerprint)
        )
      ])

    case .recordCausalFailure(let fingerprint, let failure, let lessonDigest):
      guard var governor = state.convergenceGovernor,
        let action = governor.recordFailure(
          strategy: fingerprint,
          failure: failure,
          lessonDigest: lessonDigest
        )
      else {
        return .failure(
          .invalidConvergenceTransition(
            "failure requires an open admitted attempt and durable lesson"
          ))
      }
      return .success([
        .causalConvergenceAdvanced(
          .failureRecorded(
            strategy: fingerprint,
            failure: failure,
            action: action,
            lessonDigest: lessonDigest
          )
        )
      ])

    case .authorizeCausalReplacement(
      let
        receiptID,
      let
        predecessor,
      let
        replacement,
      let
        failures,
      let
        delta
    ):
      guard var governor = state.convergenceGovernor,
        governor.authorizeReplacement(
          receiptID: receiptID,
          predecessor: predecessor,
          replacement: replacement,
          failures: failures,
          delta: delta
        ),
        let receipt = governor.replacementAuthorizationReceipts[
          replacement.fingerprint
        ]
      else {
        return .failure(
          .invalidConvergenceTransition(
            "replacement requires a unique receipt and failure-relevant causal delta"
          ))
      }
      return .success([
        .causalConvergenceAdvanced(
          .replacementAuthorized(
            receipt,
            replacement: replacement,
            failures: failures
          )
        )
      ])

    case .recordCausalConditionChange(
      let
        fingerprint,
      let
        previousFailureDigest,
      let
        observationDigest
    ):
      guard var governor = state.convergenceGovernor,
        governor.observeChangedCondition(
          for: fingerprint,
          previousFailureDigest: previousFailureDigest,
          observationDigest: observationDigest
        )
      else {
        return .failure(
          .invalidConvergenceTransition(
            "condition observation must differ from the durable wait fingerprint"
          ))
      }
      return .success([
        .causalConvergenceAdvanced(
          .conditionChanged(
            strategy: fingerprint,
            previousFailureDigest: previousFailureDigest,
            observationDigest: observationDigest
          )
        )
      ])

    case .recordCausalProgress(let fingerprint, let previous, let current):
      guard var governor = state.convergenceGovernor,
        let accepted = governor.recordProgress(
          strategy: fingerprint,
          previous: previous,
          current: current
        )
      else {
        return .failure(
          .invalidConvergenceTransition(
            "progress requires an open admitted attempt"
          ))
      }
      return .success([
        .causalConvergenceAdvanced(
          .progressEvaluated(
            strategy: fingerprint,
            accepted: accepted,
            previous: previous,
            current: current
          )
        )
      ])

    case .recordOccurrence(let authorized):
      let receipt = authorized.receipt
      guard state.contract?.acceptancePolicy.duration != nil else {
        return .failure(
          .invalidOccurrenceReceipt(
            "the ratified contract does not declare duration acceptance"
          ))
      }
      guard !state.allReceiptIDs.contains(receipt.id),
        !(state.occurrenceReceipts ?? []).contains(where: {
          $0.occurrenceID == receipt.occurrenceID
        })
      else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      if let issue = occurrenceValidationIssue(receipt, state: state) {
        return .failure(.invalidOccurrenceReceipt(issue))
      }
      return .success([.occurrenceRecorded(receipt)])

    case .recordRatifiedBaselineContentCapture(let authorized):
      let receipt = authorized.receipt
      guard authorized.validationIssues().isEmpty else {
        return .failure(
          .invalidBaselineContentCapture(
            "the live baseline-content capability does not match its receipt"
          ))
      }
      guard
        (state.ratifiedBaselineContentCaptureReceipts ?? [:])[
          receipt.derivationDigest
        ] == nil
      else {
        return .failure(
          .invalidBaselineContentCapture(
            "a baseline capture is already accepted for this derivation"
          ))
      }
      if let issue = baselineContentCaptureValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidBaselineContentCapture(issue))
      }
      return .success([.ratifiedBaselineContentCaptured(receipt)])

    case .recordJournaledGitPreimageCapture(let authorized):
      let receipt = authorized.receipt
      guard authorized.validationIssues().isEmpty else {
        return .failure(
          .invalidGitPreimageCapture(
            "the live Git preimage capability does not match its receipt"
          ))
      }
      guard state.journaledGitPreimageCaptureReceipt == nil else {
        return .failure(
          .invalidGitPreimageCapture(
            "a Git preimage capture is already accepted for this run"
          ))
      }
      if let issue = gitPreimageCaptureValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidGitPreimageCapture(issue))
      }
      return .success([.journaledGitPreimageCaptured(receipt)])

    case .recordJournaledCanonicalPreimage(let authorized):
      let receipt = authorized.receipt
      guard authorized.validationIssues().isEmpty else {
        return .failure(
          .invalidCanonicalPreimage(
            "the live canonical-preimage capability does not match its receipt"
          ))
      }
      guard state.journaledCanonicalPreimageReceipt == nil else {
        return .failure(
          .invalidCanonicalPreimage(
            "a canonical preimage is already accepted for this run"
          ))
      }
      if let issue = canonicalPreimageValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidCanonicalPreimage(issue))
      }
      return .success([.journaledCanonicalPreimageCaptured(receipt)])

    case .recordPreApplyCandidateIsolation(let authorized):
      let receipt = authorized.receipt
      guard authorized.journalValidationIssues().isEmpty else {
        return .failure(
          .invalidPreApplyCandidateIsolation(
            "the live pre-apply isolation capability does not match its receipt"
          ))
      }
      guard
        (state.preApplyCandidateIsolationReceipts ?? [:])[
          receipt.attemptID
        ] == nil
      else {
        return .failure(
          .invalidPreApplyCandidateIsolation(
            "pre-apply isolation is already accepted for this attempt"
          ))
      }
      if let issue = preApplyCandidateIsolationValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidPreApplyCandidateIsolation(issue))
      }
      return .success([.preApplyCandidateIsolationRecorded(receipt)])

    case .recordCompletedCandidateCapture(let authorized):
      let receipt = authorized.receipt
      guard authorized.validationIssues().isEmpty else {
        return .failure(
          .invalidCandidateContentCapture(
            "the live completed-candidate capability does not match its receipt"
          ))
      }
      guard
        (state.completedCandidateCaptureReceipts ?? [:])[
          receipt.attemptID
        ] == nil
      else {
        return .failure(
          .invalidCandidateContentCapture(
            "a completed candidate is already accepted for this attempt"
          ))
      }
      if let issue = completedCandidateCaptureValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidCandidateContentCapture(issue))
      }
      return .success([.completedCandidateCaptured(receipt)])

    case .recordCompletedCandidateMutationContentStore(let authorized):
      let receipt = authorized.receipt
      guard authorized.journalValidationIssues().isEmpty else {
        return .failure(
          .invalidCompletedCandidateMutationContentStore(
            "the live completed-candidate store authority does not match its receipt"
          ))
      }
      guard
        (state.completedCandidateMutationContentStoreReceipts ?? [:])[
          receipt.derivationDigest
        ] == nil
      else {
        return .failure(
          .invalidCompletedCandidateMutationContentStore(
            "completed-candidate content is already stored for this derivation"
          ))
      }
      if let issue = completedCandidateMutationContentStoreValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(
          .invalidCompletedCandidateMutationContentStore(
            issue
          ))
      }
      return .success([.completedCandidateMutationContentStored(receipt)])

    case .recordCompletedCandidateMutationManifestProposal(
      let authorized
    ):
      let receipt = authorized.receipt
      guard authorized.journalValidationIssues().isEmpty else {
        return .failure(
          .invalidCompletedCandidateMutationManifestProposal(
            "the live manifest-proposal authority does not match its receipt"
          )
        )
      }
      guard
        (state.completedCandidateMutationManifestProposalReceipts
          ?? [:])[authorized.contentStore.receipt.derivationDigest]
          == nil
      else {
        return .failure(
          .invalidCompletedCandidateMutationManifestProposal(
            "a manifest proposal is already accepted for this content store"
          )
        )
      }
      if let issue =
        completedCandidateMutationManifestProposalValidationIssue(
          receipt,
          state: state,
          actor: context.actor,
          occurredAt: context.issuedAt
        )
      {
        return .failure(
          .invalidCompletedCandidateMutationManifestProposal(issue)
        )
      }
      return .success([
        .completedCandidateMutationManifestProposed(receipt)
      ])

    case .recordCompletedCandidateMutationPreparationFacts(
      let authorized
    ):
      let receipt = authorized.receipt
      guard authorized.journalValidationIssues().isEmpty else {
        return .failure(
          .invalidCompletedCandidateMutationPreparationFacts(
            "the live preparation-facts authority does not match its receipt"
          )
        )
      }
      guard
        (state.completedCandidateMutationPreparationFactsReceipts
          ?? [:])[receipt.proposalReceiptDigest] == nil
      else {
        return .failure(
          .invalidCompletedCandidateMutationPreparationFacts(
            "preparation facts are already accepted for this proposal"
          )
        )
      }
      let factReceiptIDs: Set<ReceiptID> = [
        receipt.writeAuthority.id,
        receipt.mutationBudget.id,
        receipt.candidateQuiescence.id,
        receipt.pathResolution.id,
      ]
      guard factReceiptIDs.count == 4,
        factReceiptIDs.isDisjoint(with: state.allReceiptIDs)
      else {
        return .failure(
          .invalidCompletedCandidateMutationPreparationFacts(
            "a preparation fact receipt identity is already accepted"
          )
        )
      }
      if let issue =
        completedCandidateMutationPreparationFactsValidationIssue(
          receipt,
          state: state,
          actor: context.actor,
          occurredAt: context.issuedAt
        )
      {
        return .failure(
          .invalidCompletedCandidateMutationPreparationFacts(issue)
        )
      }
      return .success([
        .completedCandidateMutationPreparationFactsRecorded(receipt)
      ])

    case .recordCompletedCandidateMutationRollbackRehearsal(
      let authorityBox
    ):
      return decideCompletedCandidateMutationRollbackRehearsal(
        authorityBox,
        state: state,
        context: context
      )

    case .recordJournaledCandidateContentCapture(let authorized):
      let receipt = authorized.receipt
      guard authorized.validationIssues().isEmpty else {
        return .failure(
          .invalidCandidateContentCapture(
            "the live candidate-content capability does not match its receipt"
          ))
      }
      guard
        (state.journaledCandidateContentCaptureReceipts ?? [:])[
          receipt.derivationDigest
        ] == nil
      else {
        return .failure(
          .invalidCandidateContentCapture(
            "a candidate capture is already accepted for this derivation"
          ))
      }
      let attestation = authorized.attestation
      guard receipt.integrationTransactionID == attestation.integrationTransactionID,
        receipt.applyReceiptID == attestation.applyReceiptID,
        receipt.applyJournalFrameDigest == attestation.journalTransaction.frameDigest,
        receipt.workspaceID == attestation.candidatePostimage.workspaceID,
        receipt.canonicalRootDigest == attestation.candidatePostimage.canonicalRootDigest,
        receipt.candidateSourceRevision == attestation.candidatePostimage.sourceRevision,
        receipt.capturePolicyDigest == attestation.candidatePostimage.capturePolicyDigest
      else {
        return .failure(
          .invalidCandidateContentCapture(
            "the live candidate-content capability does not match its accepted apply attestation"
          ))
      }
      if let issue = candidateContentCaptureValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidCandidateContentCapture(issue))
      }
      return .success([.journaledCandidateContentCaptured(receipt)])

    case .recordJournaledMutationContentStore(let authorized):
      let receipt = authorized.receipt
      guard authorized.journalValidationIssues().isEmpty else {
        return .failure(
          .invalidMutationContentStore(
            "the live mutation-content-store capability does not match its receipt"
          ))
      }
      guard
        (state.journaledMutationContentStoreReceipts ?? [:])[
          receipt.derivationDigest
        ] == nil
      else {
        return .failure(
          .invalidMutationContentStore(
            "content is already stored for this derivation"
          ))
      }
      if let issue = mutationContentStoreValidationIssue(
        receipt,
        state: state,
        actor: context.actor,
        occurredAt: context.issuedAt
      ) {
        return .failure(.invalidMutationContentStore(issue))
      }
      return .success([.journaledMutationContentStored(receipt)])

    case .consumeCausalPlanExpansion:
      guard var governor = state.convergenceGovernor,
        governor.consumePlanExpansion()
      else {
        return .failure(
          .invalidConvergenceTransition(
            "causal plan-expansion budget is exhausted or unavailable"
          ))
      }
      return .success([.causalConvergenceAdvanced(.planExpansionConsumed)])

    case .recordRuntimeAdmission(let authorized):
      let receipt = authorized.receipt
      guard state.contract != nil, !state.phase.isTerminal else {
        return .failure(
          .invalidTransition(
            phase: state.phase,
            command: "recordRuntimeAdmission"
          ))
      }
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard receipt.runID == state.runID,
        receipt.request.runID == state.runID,
        receipt.observedAtMonotonicNanoseconds >= receipt.request.requestedAtMonotonicNanoseconds
      else {
        return .failure(.invalidRuntimeReceipt("admission provenance mismatch"))
      }
      switch receipt.outcome {
      case .accepted(let lease, let duplicate):
        guard lease.request == receipt.request,
          lease.admittedAtMonotonicNanoseconds >= receipt.request.requestedAtMonotonicNanoseconds
        else {
          return .failure(.invalidRuntimeReceipt("accepted lease differs from request"))
        }
        let existing = state.runtimeLiveLeases[receipt.request.resourceID]
        if duplicate {
          guard existing == lease else {
            return .failure(
              .invalidRuntimeReceipt(
                "duplicate admission has no identical live lease"
              ))
          }
        } else {
          guard existing == nil,
            !state.runtimeLiveLeases.values.contains(where: {
              $0.request.leaseID == receipt.request.leaseID
            })
          else {
            return .failure(
              .invalidRuntimeReceipt(
                "new admission conflicts with live ownership"
              ))
          }
        }
      case .rejected:
        break
      }
      return .success([.runtimeAdmissionRecorded(receipt)])

    case .recordRuntimeBinding(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard receipt.runID == state.runID,
        !receipt.identity.stableDigest.rawValue.isEmpty
      else {
        return .failure(.invalidRuntimeReceipt("binding provenance mismatch"))
      }
      if receipt.accepted {
        guard let lease = state.runtimeLiveLeases[receipt.resourceID],
          lease.request.leaseID == receipt.leaseID,
          receipt.observedAtMonotonicNanoseconds >= lease.admittedAtMonotonicNanoseconds,
          lease.request.externalIdentity == nil
            || lease.request.externalIdentity == receipt.identity
        else {
          return .failure(
            .invalidRuntimeReceipt(
              "binding does not match live ownership"
            ))
        }
      }
      return .success([.runtimeBindingRecorded(receipt)])

    case .recordProviderRuntimeBinding(let authorization):
      let binding = authorization.binding
      let launch = authorization.receipt
      guard binding.id != launch.id,
        !state.allReceiptIDs.contains(binding.id),
        !state.allReceiptIDs.contains(launch.id)
      else {
        return .failure(
          .duplicateReceipt(
            state.allReceiptIDs.contains(binding.id)
              ? binding.id
              : launch.id
          ))
      }
      guard binding.runID == state.runID,
        binding.accepted,
        !binding.identity.stableDigest.rawValue.isEmpty,
        let lease = state.runtimeLiveLeases[binding.resourceID],
        lease.request.leaseID == binding.leaseID,
        lease.request.kind == .processTree,
        lease.request.purpose == .productive,
        lease.request.ownership == .owned,
        lease.request.externalIdentity == nil || lease.request.externalIdentity == binding.identity,
        binding.observedAtMonotonicNanoseconds >= lease.admittedAtMonotonicNanoseconds
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "provider binding does not match live productive ownership"
          ))
      }
      guard launch.isValid(binding: binding),
        lease.request.attemptID == launch.attemptID,
        let attempt = state.attempts[launch.attemptID],
        state.activeAttemptID == attempt.id,
        attempt.nodeID == launch.invocation.nodeID,
        attempt.strategyFingerprint == launch.invocation.strategyFingerprint,
        attempt.worker == launch.invocation.activationActor,
        state.contract?.executionProfile?.worker == launch.invocation.executionProfile
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "provider launch provenance mismatch"
          ))
      }
      return .success([
        .runtimeBindingRecorded(binding),
        .providerLaunchRecorded(launch),
      ])

    case .recordRuntimeRelease(let authorized):
      // `handle` routes this command around the monolithic switch so its
      // deeply nested containment validation does not inherit this
      // function's large stack frame.
      return decideRuntimeRelease(authorized, state: state)

    case .recordWorkerResultParse(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard receipt.parserIdentityDigest == KernelWorkerResultParser.parserIdentityDigest,
        receipt.runID == state.runID,
        state.activeAttemptID == receipt.attemptID,
        state.attempts[receipt.attemptID]?.disposition == nil,
        receipt.eventCount > 0,
        receipt.eventCount <= 4_096,
        !receipt.threadID.isEmpty,
        receipt.threadID.utf8.count <= 256,
        KernelWorkerResultParser.validDigest(receipt.invocationDigest),
        KernelWorkerResultParser.validDigest(receipt.requestNonce),
        KernelWorkerResultParser.validDigest(receipt.stdoutContentDigest),
        KernelWorkerResultParser.validDigest(receipt.stderrContentDigest),
        KernelWorkerResultParser.validDigest(receipt.terminalEnvelopeDigest),
        KernelWorkerResultParser.validDigest(receipt.proposedResultDigest),
        let binding = state.runtimeBindingReceipts[receipt.bindingReceiptID],
        binding.accepted,
        binding.runID == receipt.runID,
        binding.resourceID == receipt.resourceID,
        binding.leaseID == receipt.leaseID,
        binding.identity == receipt.nativeExit.handle.externalIdentity,
        let release = state.runtimeReleaseReceipts[receipt.releaseReceiptID],
        release.runID == receipt.runID,
        release.resourceID == receipt.resourceID,
        release.leaseID == receipt.leaseID,
        release.managedProcessExit == receipt.nativeExit,
        release.managedProcessTermination == nil,
        receipt.nativeExit.exitCode == 0,
        receipt.nativeExit.terminationSignal == nil,
        state.runtimeLiveLeases[receipt.resourceID] == nil
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "worker result parse does not match journaled process provenance"
          ))
      }
      return .success([.workerResultParsed(receipt)])

    case .recordRuntimeDrain(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      let expectedIntent: RuntimeDrainIntent?
      switch state.phase {
      case .pauseRequested: expectedIntent = .pause
      case .completionRequested: expectedIntent = .complete
      case .stopRequested: expectedIntent = .stop
      default: expectedIntent = nil
      }
      guard let expectedIntent,
        receipt.runID == state.runID,
        receipt.snapshot.intent == expectedIntent,
        receipt.snapshot.liveResourceIDs == Set(state.runtimeLiveLeases.keys)
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "drain snapshot does not match requested lifecycle or live ownership"
          ))
      }
      return .success([.runtimeDrainRecorded(receipt)])

    case .activatePostimageVerifier(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard state.phase == .evaluating,
        receipt.runID == state.runID,
        receipt.verifier == context.actor,
        receipt.activatedAt == context.issuedAt,
        receipt.sourceJournalSequence == state.sequence,
        let attempt = state.attempts[receipt.attemptID],
        attempt.disposition?.canEnterVerification == true,
        receipt.requirementIDs == [receipt.requirementID],
        receipt.requirementIDs.isSubset(of: attempt.requirementIDs),
        receipt.workerLineageDigest == attempt.worker.lineageDigest,
        receipt.verifier.lineageDigest != attempt.worker.lineageDigest,
        let integration = state.integrationTransactions[
          receipt.integrationTransactionID
        ],
        integration.phase == .appliedUnverified,
        integration.proposal.attemptID == receipt.attemptID,
        integration.proposal.nodeID == attempt.nodeID,
        integration.applyReceipt?.id == receipt.applyReceiptID,
        integration.applyReceipt?.executor.lineageDigest != receipt.verifier.lineageDigest,
        let contract = state.contract,
        let recipes = contract.requirementEvidenceRecipes,
        let recipe = recipes.first(where: {
          $0.id == receipt.evidenceRecipeID
        }),
        recipes.filter({ $0.id == receipt.evidenceRecipeID }).count == 1,
        recipe.requirementID == receipt.requirementID,
        recipe.requiresIndependentLineage,
        let probe = recipe.executableProbe,
        probe.validationIssues().isEmpty,
        KernelPostimageVerifierActivationCompiler.receipt(
          receipt,
          matches: probe
        ),
        !(state.postimageVerifierActivationReceipts ?? [:]).values
          .contains(where: {
            $0.integrationTransactionID == receipt.integrationTransactionID
              && $0.evidenceRecipeID == receipt.evidenceRecipeID
          })
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "postimage verifier activation provenance mismatch"
          ))
      }
      return .success([.postimageVerifierActivated(receipt)])

    case .recordPostimageVerifierRuntimeBinding(let authorization):
      let binding = authorization.binding
      let launch = authorization.receipt
      guard binding.id != launch.id,
        !state.allReceiptIDs.contains(binding.id),
        !state.allReceiptIDs.contains(launch.id)
      else {
        return .failure(
          .duplicateReceipt(
            state.allReceiptIDs.contains(binding.id)
              ? binding.id
              : launch.id
          ))
      }
      guard state.phase == .evaluating,
        binding.runID == state.runID,
        binding.accepted,
        !binding.identity.stableDigest.rawValue.isEmpty,
        let lease = state.runtimeLiveLeases[binding.resourceID],
        lease.request.leaseID == binding.leaseID,
        lease.request.kind == .processTree,
        lease.request.purpose == .productive,
        lease.request.ownership == .owned,
        lease.request.releasePolicy == .gracefulThenTerminate,
        lease.request.externalIdentity == nil || lease.request.externalIdentity == binding.identity,
        binding.observedAtMonotonicNanoseconds >= lease.admittedAtMonotonicNanoseconds,
        lease.request.attemptID == launch.attemptID,
        launch.verifier == context.actor,
        launch.launchedAt == context.issuedAt,
        let activation =
          (state
          .postimageVerifierActivationReceipts ?? [:])[
            launch.activationReceiptID
          ],
        let integration = state.integrationTransactions[
          launch.integrationTransactionID
        ],
        integration.phase == .appliedUnverified,
        integration.applyReceipt?.id == launch.applyReceiptID,
        KernelPostimageVerifierActivationCompiler.launch(
          launch,
          matches: activation,
          binding: binding
        ),
        !(state.postimageVerifierLaunchReceipts ?? [:]).values
          .contains(where: {
            $0.activationReceiptID == launch.activationReceiptID
          }),
        !(state.postimageVerifierLaunchVetoReceipts ?? [:]).values
          .contains(where: {
            $0.activationReceiptID == launch.activationReceiptID
          })
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "postimage verifier launch provenance mismatch"
          ))
      }
      return .success([
        .runtimeBindingRecorded(binding),
        .postimageVerifierLaunched(launch),
      ])

    case .recordPostimageVerifierLaunchVeto(let authorization):
      let receipt = authorization.receipt
      guard !state.allReceiptIDs.contains(receipt.id),
        receipt.schemaVersion == 1,
        receipt.runID == state.runID,
        receipt.verifier == context.actor,
        receipt.observedAt == context.issuedAt,
        receipt.sourceJournalSequence == state.sequence,
        KernelPostimageVerifierActivationCompiler.validSHA256(
          receipt.activationJournalFrameDigest
        ),
        let activation =
          (state
          .postimageVerifierActivationReceipts ?? [:])[
            receipt.activationReceiptID
          ],
        receipt.integrationTransactionID == activation.integrationTransactionID,
        receipt.applyReceiptID == activation.applyReceiptID,
        receipt.attemptID == activation.attemptID,
        receipt.evidenceRecipeID == activation.evidenceRecipeID,
        receipt.verifier == activation.verifier,
        receipt.requiredMaximumResidentBytes == activation.resourceLimits.maximumResidentBytes,
        receipt.requiredMaximumResidentBytes > 0,
        receipt.reason
          == .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
        let integration = state.integrationTransactions[
          receipt.integrationTransactionID
        ],
        integration.phase == .appliedUnverified,
        integration.applyReceipt?.id == receipt.applyReceiptID,
        !(state.postimageVerifierLaunchReceipts ?? [:]).values
          .contains(where: {
            $0.activationReceiptID == receipt.activationReceiptID
          }),
        !(state.postimageVerifierLaunchVetoReceipts ?? [:]).values
          .contains(where: {
            $0.activationReceiptID == receipt.activationReceiptID
          })
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "postimage verifier launch veto provenance mismatch"
          ))
      }
      return .success([.postimageVerifierLaunchVetoed(receipt)])

    case .recordProductionMutationApplyVeto(let authorization):
      let receipt = authorization.receipt
      guard !state.allReceiptIDs.contains(receipt.id),
        KernelProductionMutationApplyVetoCompiler.validationIssue(
          receipt,
          state: state,
          actor: context.actor,
          occurredAt: context.issuedAt
        ) == nil
      else {
        return .failure(
          .invalidRuntimeReceipt(
            "production mutation apply veto provenance mismatch"
          )
        )
      }
      return .success([.productionMutationApplyVetoed(receipt)])

    case .advanceIntegration(let authorized):
      let transition = authorized.transition
      switch transition {
      case .startApply:
        guard
          authorized.issuer == .workspaceMutationRuntime
            || authorized.issuer == .completedCandidateApplyPreparationRuntime
            || authorized.issuer == .testOnly
        else {
          return .failure(
            .invalidIntegrationTransition(
              .identityMismatch
            ))
        }
      case .recordApply, .requestRollback, .recordRollback:
        guard
          authorized.issuer == .workspaceMutationRuntime
            || authorized.issuer == .testOnly
        else {
          return .failure(
            .invalidIntegrationTransition(
              .identityMismatch
            ))
        }
      case .recordPostimageVerification,
        .recordIndependentAcceptance:
        guard
          authorized.issuer == .processRuntime
            || authorized.issuer == .testOnly
        else {
          return .failure(
            .invalidIntegrationTransition(
              .identityMismatch
            ))
        }
      case .propose, .acceptPreflight:
        guard
          authorized.issuer == .completedCandidatePreflightRuntime
            || authorized.issuer == .testOnly
        else {
          return .failure(
            .invalidIntegrationTransition(
              .identityMismatch
            ))
        }
      }
      let transactionID: IntegrationTransactionID
      switch transition {
      case .propose(let proposal): transactionID = proposal.transactionID
      case .acceptPreflight(let receipt, _): transactionID = receipt.transactionID
      case .startApply(let intent): transactionID = intent.transactionID
      case .recordApply(let receipt): transactionID = receipt.transactionID
      case .recordPostimageVerification(let receipt):
        transactionID = receipt.transactionID
      case .recordIndependentAcceptance(let receipt):
        transactionID = receipt.transactionID
      case .requestRollback(let intent): transactionID = intent.transactionID
      case .recordRollback(let receipt): transactionID = receipt.transactionID
      }
      if case .propose(let proposal) = transition {
        guard let contract = state.contract,
          proposal.runID == state.runID,
          proposal.contractDigest == contract.objectiveDigest,
          let attempt = state.attempts[proposal.attemptID],
          attempt.nodeID == proposal.nodeID,
          attempt.disposition?.canEnterVerification == true,
          state.integrationTransactions.values.allSatisfy({
            $0.proposal.candidateID != proposal.candidateID
          })
        else {
          return .failure(.invalidIntegrationTransition(.malformedProposal))
        }
      }
      if case .acceptPreflight(let receipt, _) = transition,
        let transaction = state.integrationTransactions[transactionID]
      {
        let proposal = transaction.proposal
        guard let node = state.nodes[proposal.nodeID]?.contract,
          receipt.affectedPaths.allSatisfy({ path in
            node.mutationScope.writablePaths.contains { scope in
              WorkspacePathPolicy.contains(
                scope: scope,
                path: path
              )
            }
          }),
          receipt.changedFileCount <= node.mutationScope.maximumChangedFiles,
          receipt.changedByteCount <= UInt64(node.mutationScope.maximumChangedBytes),
          !receipt.candidateVerificationReceiptIDs.isEmpty,
          receipt.candidateVerificationReceiptIDs.allSatisfy({ id in
            guard let verification = state.verificationReceipts[id] else {
              return false
            }
            return verification.attemptID == proposal.attemptID
              && verification.result == .accepted
              && verification.sourceRevision == proposal.expectedPostimageDigest
              && verification.requirementIDs.allSatisfy {
                state.verificationIsEffective(
                  verification,
                  requirementID: $0
                )
              }
          }),
          state.reviewReceipts[receipt.independentReviewReceiptID].map({ review in
            review.attemptID == proposal.attemptID
              && review.decision == .approveCandidate
              && review.sourceRevision == proposal.expectedPostimageDigest
              && receipt.candidateVerificationReceiptIDs
                .contains { verificationID in
                  state.verificationReceipts[
                    verificationID
                  ].map {
                    state.reviewMatchesVerification(
                      review,
                      verification: $0
                    )
                  } == true
                }
          }) == true
        else {
          return .failure(.invalidIntegrationTransition(.identityMismatch))
        }
        if let visualID = receipt.visualGateReceiptID {
          guard
            state.visualGateReceipts[visualID].map({ visual in
              visual.attemptID == proposal.attemptID
                && visual.candidateSourceTree == proposal.expectedPostimageDigest
                && visual.result.accepted
            }) == true
          else {
            return .failure(.invalidIntegrationTransition(.identityMismatch))
          }
        } else if state.designBaseline?.requirementIDs
          .isDisjoint(with: node.requirementIDs) == false
        {
          return .failure(.invalidIntegrationTransition(.identityMismatch))
        }
      }
      if case .startApply(let intent) = transition,
        let sourceRevision = state.contract?.sourceRevision,
        intent.candidatePostimageCapturePolicyDigest != sourceRevision.capturePolicyDigest
      {
        return .failure(.invalidIntegrationTransition(.identityMismatch))
      }
      if case .recordApply(let receipt) = transition,
        case .exactPostimage = receipt.outcome,
        let contract = state.contract,
        let sourceRevision = contract.sourceRevision
      {
        guard let workspaceBinding = contract.workspaceBinding,
          let transaction = state.integrationTransactions[transactionID],
          transaction.applyIntent?
            .candidatePostimageCapturePolicyDigest == sourceRevision.capturePolicyDigest,
          let candidatePostimage = receipt.candidatePostimage,
          candidatePostimage.validationIssues().isEmpty,
          candidatePostimage.workspaceID == workspaceBinding.workspaceID,
          candidatePostimage.canonicalRootDigest == workspaceBinding.canonicalRootDigest,
          candidatePostimage.capturePolicyDigest == sourceRevision.capturePolicyDigest
        else {
          return .failure(.invalidIntegrationTransition(.identityMismatch))
        }
      }
      if case .recordPostimageVerification(let receipt) = transition {
        guard let sourceID = receipt.sourceVerificationReceiptID,
          let source = state.verificationReceipts[sourceID],
          source.attemptID
            == state.integrationTransactions[
              transactionID
            ]?.proposal.attemptID,
          source.requirementIDs
            == state.attempts[
              source.attemptID
            ]?.requirementIDs,
          source.sourceRevision == receipt.canonicalPostimageDigest,
          source.result == .accepted,
          source.requirementIDs.allSatisfy({
            state.verificationIsEffective(
              source,
              requirementID: $0
            )
          }),
          let batch = source.postimageEvidenceBatch,
          batch.evidenceSetDigest == receipt.evidenceSetDigest,
          batch.postimageReleaseReceiptID == receipt.processQuiescenceReceiptID,
          let release = state.runtimeReleaseReceipts[
            batch.postimageReleaseReceiptID
          ],
          release.postimageVerifierContainment?.postimageResult?.id
            == batch.postimageResultID,
          release.postimageVerifierContainment?.postimageResult?
            .evidenceSetDigest == batch.postimageResultEvidenceSetDigest,
          release.postimageVerifierContainment?.postimageResult?
            .integrationTransactionID == transactionID,
          release.postimageVerifierContainment?.postimageResult?
            .applyReceiptID == receipt.applyReceiptID,
          release.postimageVerifierContainment?.postimageResult?
            .sourceRevision == receipt.canonicalPostimageDigest,
          release.postimageVerifierContainment?.postimageResult?
            .verifier == receipt.verifier
        else {
          return .failure(
            .invalidIntegrationTransition(
              .invalidVerificationReceipt
            ))
        }
      }
      if case .recordIndependentAcceptance(let receipt) = transition {
        guard
          let reviewID =
            receipt.sourceIndependentReviewReceiptID,
          let evidenceSetDigest =
            receipt.sourceVerificationEvidenceSetDigest,
          let review = state.reviewReceipts[reviewID],
          review.attemptID
            == state.integrationTransactions[
              transactionID
            ]?.proposal.attemptID,
          review.requirementIDs
            == state.attempts[
              review.attemptID
            ]?.requirementIDs,
          review.sourceRevision == receipt.canonicalPostimageDigest,
          review.reviewer == receipt.reviewer,
          review.evidenceDigest == receipt.evidenceDigest,
          let reviewResultID = review.sourcePostimageResultID,
          let reviewResult = state.runtimeReleaseReceipts.values
            .compactMap({
              $0.postimageVerifierContainment?.postimageResult
            })
            .first(where: { $0.id == reviewResultID }),
          reviewResult.integrationTransactionID == transactionID,
          reviewResult.applyReceiptID
            == state
            .integrationTransactions[transactionID]?
            .applyReceipt?.id,
          reviewResult.sourceRevision == receipt.canonicalPostimageDigest,
          reviewResult.verifier == receipt.reviewer,
          reviewResult.evidenceSetDigest == receipt.evidenceDigest,
          receipt.decision
            == KernelIntegrationReceiptAuthority
            .acceptanceDecision(review: review),
          review.verificationEvidenceSetDigest == evidenceSetDigest,
          let integrationVerification =
            state
            .integrationTransactions[transactionID]?
            .postimageVerificationReceipt,
          integrationVerification.evidenceSetDigest == evidenceSetDigest,
          integrationVerification.sourceVerificationReceiptID
            .flatMap({ state.verificationReceipts[$0] })
            .map({ source in
              source.postimageEvidenceBatch?.evidenceSetDigest == evidenceSetDigest
                && state.reviewMatchesVerification(
                  review,
                  verification: source
                )
            }) == true
        else {
          return .failure(
            .invalidIntegrationTransition(
              .invalidAcceptanceReceipt
            ))
        }
      }
      let decision = IntegrationTransactionReducer.decide(
        current: state.integrationTransactions[transactionID],
        command: transition,
        actor: context.actor,
        knownReceiptIDs: state.allReceiptIDs,
        knownIntentIDs: state.allIntegrationIntentIDs
      )
      switch decision {
      case .success(let event): return .success([.integrationAdvanced(event)])
      case .failure(let rejection):
        return .failure(.invalidIntegrationTransition(rejection))
      }

    case .requestPause:
      guard
        state.phase == .ready || state.phase == .executing || state.phase == .evaluating
          || state.phase == .blocked
      else {
        return .failure(.invalidTransition(phase: state.phase, command: "requestPause"))
      }
      return .success([.pauseRequested])

    case .requestCompletion:
      guard state.phase == .ready || state.phase == .evaluating || state.phase == .blocked,
        state.activeAttemptID == nil,
        let contract = state.contract
      else {
        return .failure(
          .invalidTransition(
            phase: state.phase,
            command: "requestCompletion"
          ))
      }
      let missing = contract.mandatoryRequirementIDs.subtracting(
        state.acceptedRequirementIDs
      )
      guard missing.isEmpty else { return .failure(.evidenceIncomplete(missing)) }
      if let rejection = durationRejection(state: state, contract: contract) {
        return .failure(rejection)
      }
      return .success([.completionRequested])

    case .requestStop:
      guard !state.phase.isTerminal, state.phase != .stopRequested else {
        return .failure(.invalidTransition(phase: state.phase, command: "requestStop"))
      }
      return .success([.stopRequested])

    case .recordQuiescence(let authorized):
      let receipt = authorized.receipt
      guard !state.allReceiptIDs.contains(receipt.id) else {
        return .failure(.duplicateReceipt(receipt.id))
      }
      guard receipt.runID == state.runID,
        receipt.provesQuiescence,
        receipt.liveResources == Set(state.runtimeLiveLeases.keys),
        receipt.failedReleases == state.runtimeFailedReleases,
        let drainID = state.lastRuntimeDrainReceiptID,
        let drain = state.runtimeDrainReceipts[drainID],
        drain.snapshot.intent == receipt.intent,
        receipt.observedAtMonotonicNanoseconds >= drain.observedAtMonotonicNanoseconds
      else {
        return .failure(.quiescenceNotProven)
      }
      switch state.phase {
      case .pauseRequested:
        guard receipt.intent == .pause else {
          return .failure(.quiescenceNotProven)
        }
        return .success([.quiescenceRecorded(receipt), .runPaused])
      case .stopRequested:
        guard receipt.intent == .stop || receipt.intent == .quit else {
          return .failure(.quiescenceNotProven)
        }
        return .success([.quiescenceRecorded(receipt), .runStopped])
      case .completionRequested:
        guard receipt.intent == .complete, state.activeAttemptID == nil else {
          return .failure(.quiescenceNotProven)
        }
        return .success([.quiescenceRecorded(receipt)])
      default:
        return .failure(.invalidTransition(phase: state.phase, command: "recordQuiescence"))
      }

    case .authorizeCompletion(let authorization):
      let receipt = authorization.receipt
      guard state.phase == .completionRequested, let contract = state.contract else {
        return .failure(.invalidTransition(phase: state.phase, command: "authorizeCompletion"))
      }
      #if DEBUG
        if authorization.isTestOnly {
          guard authorization.runID == state.runID,
            authorization.sourceSequence == state.sequence,
            authorization.authorizer == context.actor
          else {
            return .failure(
              .invalidTransition(
                phase: state.phase,
                command: "authorizeCompletionAuthority"
              ))
          }
          let missing = contract.mandatoryRequirementIDs.subtracting(
            state.acceptedRequirementIDs
          )
          guard missing.isEmpty else {
            return .failure(.evidenceIncomplete(missing))
          }
          if let rejection = durationRejection(
            state: state,
            contract: contract
          ) {
            return .failure(rejection)
          }
          if contract.acceptancePolicy.requiresQuiescence,
            state.quiescenceReceipt?.provesQuiescence != true
          {
            return .failure(.quiescenceNotProven)
          }
          guard state.activeAttemptID == nil else {
            return .failure(.quiescenceNotProven)
          }
          return .success([.completionAuthorized])
        }
      #endif
      let issues = KernelCompletionEvidenceCompiler.validationIssues(
        state: state,
        sourceFrameDigest: receipt.sourceFrameDigest,
        sourceOccurredAt: receipt.sourceOccurredAt,
        authorizedAt: receipt.authorizedAt,
        authorizer: receipt.authorizer
      )
      guard issues.isEmpty,
        receipt.runID == state.runID,
        receipt.contractID == contract.id,
        receipt.sourceSequence == state.sequence,
        receipt.authorizer == context.actor,
        receipt.authorizedAt == context.issuedAt,
        receipt.sourceEvidenceDigest
          == KernelCompletionEvidenceCompiler.evidenceDigest(
            state: state,
            sourceFrameDigest: receipt.sourceFrameDigest,
            sourceOccurredAt: receipt.sourceOccurredAt,
            authorizer: receipt.authorizer
          ),
        receipt.acceptedRequirementIDs == state.acceptedRequirementIDs,
        receipt.evidenceReceiptIDs == state.allReceiptIDs,
        !state.allReceiptIDs.contains(receipt.id)
      else {
        return .failure(
          .invalidTransition(
            phase: state.phase,
            command: "authorizeCompletionAuthority"
          ))
      }
      let missing = contract.mandatoryRequirementIDs.subtracting(state.acceptedRequirementIDs)
      guard missing.isEmpty else { return .failure(.evidenceIncomplete(missing)) }
      if let rejection = durationRejection(state: state, contract: contract) {
        return .failure(rejection)
      }
      if contract.acceptancePolicy.requiresQuiescence,
        state.quiescenceReceipt?.provesQuiescence != true
      {
        return .failure(.quiescenceNotProven)
      }
      guard state.activeAttemptID == nil else { return .failure(.quiescenceNotProven) }
      return .success([
        .completionAuthorizationRecorded(receipt),
        .completionAuthorized,
      ])
    }
  }

  private static func applyExecutionDisposition(
    attemptID: AttemptID,
    disposition: KernelExecutionDisposition,
    to state: inout KernelRunState
  ) {
    state.attempts[attemptID]?.disposition = disposition
    if state.activeAttemptID == attemptID { state.activeAttemptID = nil }
    guard let nodeID = state.attempts[attemptID]?.nodeID else { return }
    switch disposition {
    case .completed:
      state.nodes[nodeID]?.status = .awaitingVerification
      state.phase = .evaluating
    case .blocked, .externalDependencyUnavailable:
      state.nodes[nodeID]?.status = .blocked
      state.phase = .blocked
    case .failed, .malformed:
      state.nodes[nodeID]?.status = .failed
      state.phase = .ready
    case .continuationNeeded, .interrupted:
      state.nodes[nodeID]?.status = .authorized
      state.phase = .ready
    }
  }

  private static func executionDerivationMaterial(
    state: KernelRunState,
    source: KernelExecutionDerivationSource
  ) -> (
    attemptID: AttemptID,
    evidenceDigest: ContentDigest,
    disposition: KernelExecutionDisposition
  )? {
    switch source {
    case .workerResultParse(let parseReceiptID):
      guard let parse = state.workerResultParseReceipts?[parseReceiptID] else {
        return nil
      }
      let disposition: KernelExecutionDisposition
      switch parse.proposedDisposition {
      case .completed:
        disposition = .completed
      case .continuationNeeded:
        disposition = .continuationNeeded
      case .blocked:
        disposition = .blocked(reasonDigest: parse.proposedResultDigest)
      case .failed:
        disposition = .failed(reasonDigest: parse.proposedResultDigest)
      case .interrupted:
        disposition = .interrupted
      case .malformed:
        disposition = .malformed(reasonDigest: parse.proposedResultDigest)
      }
      return (parse.attemptID, parse.proposedResultDigest, disposition)
    case .externalDependencyObservation(let observationReceiptID):
      guard let observation = state.externalDependencyReceipts?[observationReceiptID],
        observation.availability == .unavailable,
        !observation.requirementIDs.isEmpty,
        let attempt = state.attempts[observation.attemptID],
        observation.requirementIDs.isSubset(of: attempt.requirementIDs)
      else {
        return nil
      }
      return (
        observation.attemptID,
        observation.evidenceDigest,
        .externalDependencyUnavailable(
          receiptID: observation.id,
          reasonDigest: observation.evidenceDigest
        )
      )
    }
  }

  private static func occurrenceValidationIssue(
    _ receipt: OccurrenceReceipt,
    state: KernelRunState
  ) -> String? {
    guard !receipt.id.rawValue.isEmpty,
      !receipt.occurrenceID.rawValue.isEmpty,
      !receipt.clock.bootSessionID.rawValue.isEmpty,
      receipt.clock.elapsedNanoseconds != nil,
      receipt.evidenceReceiptIDs.allSatisfy({ !$0.rawValue.isEmpty })
    else {
      return
        "occurrence identity, boot identity, monotonic bounds, and evidence identities must be valid"
    }
    if let progressReceiptID = receipt.progressReceiptID {
      guard !progressReceiptID.rawValue.isEmpty,
        state.causalProgressReceiptIDs.contains(progressReceiptID)
      else {
        return "progress binding must reference a causal progress journal transaction"
      }
    }
    let unknownEvidence = receipt.evidenceReceiptIDs.subtracting(
      state.occurrenceEvidenceReceiptIDs
    )
    guard unknownEvidence.isEmpty else {
      return "evidence bindings must reference typed journal evidence receipts"
    }
    switch receipt.invocation {
    case .scheduled(let scheduleID, _):
      guard !scheduleID.rawValue.isEmpty else {
        return "scheduled invocation requires an exact schedule identity"
      }
    case .manual(let ownerCommandID), .ownerAmendment(let ownerCommandID):
      guard !ownerCommandID.rawValue.isEmpty else {
        return "interactive invocation requires an exact owner command identity"
      }
    case .verification(let requirementIDs):
      guard !requirementIDs.isEmpty else {
        return "verification invocation requires bound requirement identities"
      }
    case .adaptiveReview(let triggerID):
      guard !triggerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return "adaptive review requires an exact trigger identity"
      }
    case .recovery:
      break
    }
    return nil
  }

  private static func gitPreimageCaptureValidationIssue(
    _ receipt: WorkspaceJournaledGitPreimageCaptureReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the Git preimage receipt is malformed"
    }
    guard !state.phase.isTerminal,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let baseline = contract.sourceRevision,
      let workspace = contract.workspaceBinding
    else {
      return "the Git preimage receipt does not match an active run contract"
    }
    guard receipt.workspaceID == workspace.workspaceID,
      receipt.workspaceID == baseline.workspaceID,
      receipt.canonicalRootDigest == workspace.canonicalRootDigest,
      receipt.canonicalRootDigest == baseline.canonicalRootDigest,
      receipt.baseSourceRevision == baseline.sourceRevision,
      receipt.capturePolicyDigest == baseline.capturePolicyDigest
    else {
      return "the Git preimage receipt does not match the ratified source revision"
    }
    guard receipt.captureActor == actor,
      receipt.capturedAt == occurredAt
    else {
      return "the Git preimage receipt actor or time does not match the command"
    }
    return nil
  }

  private static func canonicalPreimageValidationIssue(
    _ receipt: WorkspaceJournaledCanonicalPreimageReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the canonical preimage receipt is malformed"
    }
    guard !state.phase.isTerminal,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let source = contract.sourceRevision,
      let workspace = contract.workspaceBinding,
      let git = state.journaledGitPreimageCaptureReceipt
    else {
      return "the canonical preimage does not match an active captured run"
    }
    guard receipt.gitPreimageCaptureReceiptDigest == git.receiptDigest,
      receipt.preimage.workspaceID == workspace.workspaceID,
      receipt.preimage.workspaceID == source.workspaceID,
      receipt.preimage.rootIdentity == workspace.canonicalRootDigest,
      receipt.preimage.rootIdentity == source.canonicalRootDigest,
      receipt.preimage.sourceRevision == source.sourceRevision,
      receipt.preimage.contractDigest == contract.objectiveDigest,
      receipt.worktree.workspaceID == source.workspaceID,
      receipt.worktree.rootIdentity == source.canonicalRootDigest,
      receipt.worktree.sourceRevision == source.sourceRevision,
      receipt.worktree.capturePolicyDigest == source.capturePolicyDigest,
      receipt.worktree.entries
        == source.entries.map({
          WorkspaceEntrySnapshot(
            plane: .worktree,
            path: $0.relativePath,
            kind: .regularFile,
            mode: $0.mode,
            contentDigest: $0.contentDigest,
            size: $0.size,
            ownership: .userExisting
          )
        })
    else {
      return "the canonical preimage does not match ratified workspace authority"
    }
    let exactEntries = [
      git.head, git.index, receipt.worktree,
      git.untracked,
    ].flatMap(\.entries).sorted {
      ($0.plane.rawValue, $0.path) < ($1.plane.rawValue, $1.path)
    }
    guard receipt.preimage.entries == exactEntries,
      receipt.ignoredPathClassifications.map(\.path) == git.untracked.entries.map(\.path)
    else {
      return "the canonical preimage does not exactly compose accepted planes"
    }
    guard receipt.captureActor == actor,
      receipt.capturedAt == occurredAt
    else {
      return "the canonical preimage actor or time does not match the command"
    }
    return nil
  }

  private static func baselineContentCaptureValidationIssue(
    _ receipt: WorkspaceRatifiedBaselineContentCaptureReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the baseline-content receipt is malformed"
    }
    guard !state.phase.isTerminal,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let baseline = contract.sourceRevision,
      let workspace = contract.workspaceBinding
    else {
      return "the baseline-content receipt does not match an active run contract"
    }
    guard receipt.workspaceID == workspace.workspaceID,
      receipt.workspaceID == baseline.workspaceID,
      receipt.canonicalRootDigest == workspace.canonicalRootDigest,
      receipt.canonicalRootDigest == baseline.canonicalRootDigest,
      receipt.baseSourceRevision == baseline.sourceRevision,
      receipt.capturePolicyDigest == baseline.capturePolicyDigest
    else {
      return "the baseline-content receipt does not match the ratified source revision"
    }
    guard receipt.captureActor == actor,
      receipt.capturedAt == occurredAt
    else {
      return "the baseline-content receipt actor or time does not match the command"
    }
    let baselineReferences = Set(
      baseline.entries.map {
        WorkspaceMutationContentReference(
          contentDigest: $0.contentDigest,
          size: $0.size
        )
      })
    guard
      receipt.contentObjects.allSatisfy({
        baselineReferences.contains($0)
      })
    else {
      return "the baseline-content receipt contains bytes outside the ratified revision"
    }
    return nil
  }

  private static func preApplyCandidateIsolationValidationIssue(
    _ receipt: WorkspacePreApplyCandidateIsolationReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the pre-apply isolation receipt is malformed"
    }
    guard state.phase == .ready,
      state.nodes.isEmpty,
      state.attempts.isEmpty,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      contract.requiresWorkspaceMutationAuthority,
      let source = contract.sourceRevision,
      let workspace = contract.workspaceBinding,
      let plan = contract.initialExecutionPlan,
      plan.requiresWorkspaceMutation,
      let node = plan.nodes.first(where: {
        $0.id == receipt.nodeID
      }),
      !node.mutationScope.writablePaths.isEmpty
        || node.mutationScope.maximumChangedFiles > 0
        || node.mutationScope.maximumChangedBytes > 0
    else {
      return "the pre-apply isolation receipt does not match an active mutation attempt"
    }
    guard receipt.strategyFingerprint == node.strategyFingerprint,
      receipt.sourceRevision == source.sourceRevision,
      receipt.capturePolicyDigest == source.capturePolicyDigest,
      receipt.fileCount == source.entries.count,
      receipt.totalBytes == source.totalBytes,
      receipt.candidateEntryManifestDigest
        == WorkspaceCandidatePostimageMaterializer
        .preApplyCandidateEntryManifestDigest(source),
      receipt.candidateCanonicalRootDigest != workspace.canonicalRootDigest
    else {
      return "the pre-apply isolation receipt does not match the ratified source and plan"
    }
    guard receipt.isolationActor == actor,
      receipt.isolatedAt == occurredAt
    else {
      return "the pre-apply isolation actor or time does not match the command"
    }
    return nil
  }

  private static func candidateContentCaptureValidationIssue(
    _ receipt: WorkspaceJournaledCandidateContentCaptureReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the candidate-content receipt is malformed"
    }
    guard !state.phase.isTerminal,
      receipt.runID == state.runID,
      let contract = state.contract,
      let workspace = contract.workspaceBinding,
      let integration = state.integrationTransactions[
        receipt.integrationTransactionID
      ], let apply = integration.applyReceipt,
      case .exactPostimage = apply.outcome,
      let candidate = apply.candidatePostimage
    else {
      return "the candidate-content receipt does not match an active exact apply"
    }
    guard receipt.workspaceID == workspace.workspaceID,
      receipt.canonicalRootDigest == workspace.canonicalRootDigest,
      receipt.applyReceiptID == apply.id,
      receipt.captureActor == apply.executor,
      receipt.capturedAt >= apply.completedAt,
      receipt.candidateSourceRevision == candidate.sourceRevision,
      receipt.workspaceID == candidate.workspaceID,
      receipt.canonicalRootDigest == candidate.canonicalRootDigest,
      receipt.capturePolicyDigest == candidate.capturePolicyDigest
    else {
      return "the candidate-content receipt does not match the journaled candidate postimage"
    }
    guard receipt.captureActor == actor,
      receipt.capturedAt == occurredAt
    else {
      return "the candidate-content receipt actor or time does not match the command"
    }
    let candidateReferences = Set(
      candidate.entries.map {
        WorkspaceMutationContentReference(
          contentDigest: $0.contentDigest,
          size: $0.size
        )
      })
    guard
      receipt.contentObjects.allSatisfy({
        candidateReferences.contains($0)
      })
    else {
      return "the candidate-content receipt contains bytes outside the accepted candidate revision"
    }
    return nil
  }

  private static func completedCandidateCaptureValidationIssue(
    _ receipt: WorkspaceCompletedCandidateCaptureReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the completed-candidate receipt is malformed"
    }
    guard state.phase == .evaluating,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let workspace = contract.workspaceBinding,
      let source = contract.sourceRevision,
      let attempt = state.attempts[receipt.attemptID],
      attempt.disposition == .completed,
      attempt.nodeID == receipt.nodeID,
      attempt.strategyFingerprint == receipt.strategyFingerprint,
      let node = state.nodes[receipt.nodeID]?.contract,
      state.nodes[receipt.nodeID]?.status == .awaitingVerification,
      let isolation = (state.preApplyCandidateIsolationReceipts ?? [:])[
        receipt.attemptID
      ],
      let execution = (state.executionDerivationReceipts ?? [:])[
        receipt.executionReceiptID
      ],
      execution.disposition == .completed
    else {
      return "the completed-candidate receipt does not match a completed mutation attempt"
    }
    guard receipt.workspaceID == workspace.workspaceID,
      receipt.canonicalRootDigest == workspace.canonicalRootDigest,
      receipt.baseSourceRevision == source.sourceRevision,
      receipt.capturePolicyDigest == source.capturePolicyDigest,
      receipt.isolationReceiptDigest == isolation.receiptDigest,
      receipt.candidateRootPath == isolation.candidateRootPath,
      receipt.candidateCanonicalRootDigest == isolation.candidateCanonicalRootDigest,
      receipt.candidateDeviceID == isolation.deviceID,
      receipt.candidateInode == isolation.inode,
      receipt.executionSourceEvidenceDigest == execution.sourceEvidenceDigest,
      node.requirementIDs == attempt.requirementIDs,
      receipt.captureActor == actor,
      receipt.capturedAt == occurredAt,
      receipt.capturedAt >= execution.derivedAt
    else {
      return "the completed-candidate receipt does not match journaled execution authority"
    }
    let candidateReferences = Set(
      receipt.candidateRevision.entries.map {
        WorkspaceMutationContentReference(
          contentDigest: $0.contentDigest,
          size: $0.size
        )
      })
    guard
      receipt.contentObjects.allSatisfy({
        candidateReferences.contains($0)
      })
    else {
      return "the completed-candidate receipt contains bytes outside its logical revision"
    }
    return nil
  }

  private static func mutationContentStoreValidationIssue(
    _ receipt: WorkspaceJournaledMutationContentStoreReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the journaled mutation-content-store receipt is malformed"
    }
    let composition = receipt.compositionReceipt
    guard !state.phase.isTerminal,
      composition.runID == state.runID,
      let contract = state.contract,
      let workspace = contract.workspaceBinding,
      composition.workspaceID == workspace.workspaceID,
      composition.canonicalRootDigest == workspace.canonicalRootDigest,
      let baseline = (state.ratifiedBaselineContentCaptureReceipts ?? [:])[
        composition.derivationDigest
      ],
      let candidate = (state.journaledCandidateContentCaptureReceipts ?? [:])[
        composition.derivationDigest
      ]
    else {
      return "the stored composition does not match active accepted origins"
    }
    guard composition.baselineCaptureReceiptDigest == baseline.receiptDigest,
      composition.candidateCaptureReceiptDigest == candidate.receiptDigest,
      composition.integrationTransactionID == candidate.integrationTransactionID,
      composition.baseSourceRevision == baseline.baseSourceRevision,
      composition.candidateSourceRevision == candidate.candidateSourceRevision,
      composition.capturePolicyDigest == baseline.capturePolicyDigest,
      composition.capturePolicyDigest == candidate.capturePolicyDigest,
      composition.baselineContentObjects == baseline.contentObjects,
      composition.candidateContentObjects == candidate.contentObjects
    else {
      return "the stored composition is not the exact accepted before/after byte set"
    }
    guard receipt.storedBy == candidate.captureActor,
      receipt.storedBy == actor,
      receipt.storedAt == occurredAt,
      receipt.storedAt >= baseline.capturedAt,
      receipt.storedAt >= candidate.capturedAt
    else {
      return "the stored composition actor or time does not match the command"
    }
    return nil
  }

  private static func completedCandidateMutationContentStoreValidationIssue(
    _ receipt: WorkspaceCompletedCandidateMutationContentStoreReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the completed-candidate content-store receipt is malformed"
    }
    let derivation = receipt.derivation
    guard state.phase == .evaluating,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let workspace = contract.workspaceBinding,
      let source = contract.sourceRevision,
      let attempt = state.attempts[receipt.attemptID],
      attempt.disposition == .completed,
      attempt.nodeID == receipt.nodeID,
      let node = state.nodes[receipt.nodeID]?.contract,
      state.nodes[receipt.nodeID]?.status == .awaitingVerification,
      let candidate = (state.completedCandidateCaptureReceipts ?? [:])[
        receipt.attemptID
      ],
      let baseline =
        (state.ratifiedBaselineContentCaptureReceipts ?? [:])[
          derivation.derivationDigest
        ]
    else {
      return "the completed-candidate store does not match active completed origins"
    }
    guard receipt.workspaceID == workspace.workspaceID,
      receipt.canonicalRootDigest == workspace.canonicalRootDigest,
      derivation.workspaceID == workspace.workspaceID,
      derivation.canonicalRootDigest == workspace.canonicalRootDigest,
      derivation.capturePolicyDigest == source.capturePolicyDigest,
      derivation.baseSourceRevision == source.sourceRevision,
      derivation.baseSourceRevision == candidate.baseSourceRevision,
      derivation.candidateSourceRevision == candidate.candidateSourceRevision,
      receipt.completedCandidateCaptureReceiptDigest == candidate.receiptDigest,
      receipt.baselineCaptureReceiptDigest == baseline.receiptDigest,
      baseline.derivationDigest == derivation.derivationDigest,
      baseline.baseSourceRevision == derivation.baseSourceRevision,
      baseline.workspaceID == derivation.workspaceID,
      baseline.canonicalRootDigest == derivation.canonicalRootDigest,
      baseline.capturePolicyDigest == derivation.capturePolicyDigest,
      derivation.touchedRequirementIDs == attempt.requirementIDs,
      derivation.touchedRequirementIDs == node.requirementIDs,
      derivation.operations.allSatisfy({ operation in
        operation.requirementIDs == node.requirementIDs
          && node.mutationScope.writablePaths.contains(where: {
            WorkspacePathPolicy.contains(
              scope: $0,
              path: operation.path
            )
          })
      })
    else {
      return "the completed-candidate store is not the exact accepted before/after set"
    }
    let referenceByDigest = Dictionary(
      uniqueKeysWithValues:
        derivation.contentObjects.map { ($0.contentDigest, $0) }
    )
    let expectedBaseline = Set(
      derivation.operations.compactMap(\.expectedPreimage)
    ).compactMap { referenceByDigest[$0] }.sorted {
      $0.contentDigest.rawValue < $1.contentDigest.rawValue
    }
    let expectedCandidate = Set(
      derivation.operations.compactMap(\.desiredPostimage)
    ).compactMap { referenceByDigest[$0] }
    guard expectedBaseline == baseline.contentObjects,
      Set(expectedCandidate).isSubset(of: Set(candidate.contentObjects))
    else {
      return "the completed-candidate store content partitions are not exact"
    }
    guard receipt.storedBy == candidate.captureActor,
      receipt.storedBy == actor,
      receipt.storedAt == occurredAt,
      receipt.storedAt >= candidate.capturedAt,
      receipt.storedAt >= baseline.capturedAt
    else {
      return "the completed-candidate store actor or time does not match the command"
    }
    return nil
  }

  private static func completedCandidateMutationManifestProposalValidationIssue(
    _ receipt:
      WorkspaceCompletedCandidateMutationManifestProposalReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the completed-candidate manifest-proposal receipt is malformed"
    }
    guard state.phase == .evaluating,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let workspace = contract.workspaceBinding,
      let source = contract.sourceRevision,
      let attempt = state.attempts[receipt.attemptID],
      attempt.disposition == .completed,
      attempt.nodeID == receipt.nodeID,
      attempt.strategyFingerprint == receipt.strategyFingerprint,
      let nodeState = state.nodes[receipt.nodeID],
      nodeState.status == .awaitingVerification,
      let contractMutationBudget = contract.executionBudgets?.mutation,
      let canonical = state.journaledCanonicalPreimageReceipt,
      let store =
        (state
        .completedCandidateMutationContentStoreReceipts ?? [:])
        .values.first(where: {
          $0.receiptDigest
            == receipt
            .completedCandidateContentStoreReceiptDigest
        }),
      let nodeDigest =
        WorkspaceCompletedCandidateMutationManifestProposalReceipt
        .planNodeDigest(nodeState.contract),
      nodeState.contract.mutationScope.maximumChangedFiles >= 0,
      nodeState.contract.mutationScope.maximumChangedBytes >= 0,
      contractMutationBudget.maximumChangedFiles >= 0,
      let changedBytes =
        WorkspaceCompletedCandidateMutationManifestProposalReceipt
        .changedByteCount(derivation: store.derivation)
    else {
      return "the manifest proposal does not match active accepted origins"
    }
    guard receipt.workspaceID == workspace.workspaceID,
      receipt.workspaceID == store.workspaceID,
      receipt.workspaceID == canonical.preimage.workspaceID,
      receipt.canonicalRootDigest == workspace.canonicalRootDigest,
      receipt.canonicalRootDigest == store.canonicalRootDigest,
      receipt.canonicalRootDigest == canonical.preimage.rootIdentity,
      receipt.completedCandidateContentStoreReceiptDigest == store.receiptDigest,
      receipt.canonicalPreimageReceiptDigest == canonical.receiptDigest,
      receipt.contractDigest == contract.objectiveDigest,
      receipt.contractDigest == canonical.preimage.contractDigest,
      receipt.planNodeDigest == nodeDigest,
      receipt.basePreimageDigest == canonical.preimage.canonicalDigest,
      store.derivation.baseSourceRevision == source.sourceRevision,
      store.derivation.baseSourceRevision == canonical.preimage.sourceRevision,
      receipt.expectedPostimageDigest == store.derivation.candidateSourceRevision,
      receipt.operations
        == WorkspaceCompletedCandidateMutationManifestProposalReceipt
        .operations(for: store.derivation),
      receipt.touchedRequirementIDs == attempt.requirementIDs,
      receipt.touchedRequirementIDs == nodeState.contract.requirementIDs,
      receipt.touchedRequirementIDs == store.derivation.touchedRequirementIDs,
      receipt.changedFileCount == store.derivation.operations.count,
      receipt.changedByteCount == changedBytes,
      receipt.changedFileCount <= nodeState.contract.mutationScope.maximumChangedFiles,
      receipt.changedByteCount
        <= UInt64(
          nodeState.contract.mutationScope.maximumChangedBytes
        ),
      receipt.changedFileCount <= contractMutationBudget.maximumChangedFiles,
      receipt.changedByteCount <= contractMutationBudget.maximumChangedBytes,
      receipt.operations.allSatisfy({ operation in
        operation.requirementIDs == nodeState.contract.requirementIDs
          && [operation.sourcePath, operation.destinationPath]
            .compactMap { $0 }.allSatisfy { path in
              nodeState.contract.mutationScope.writablePaths
                .contains(where: {
                  WorkspacePathPolicy.contains(
                    scope: $0,
                    path: path
                  )
                })
            }
      })
    else {
      return "the manifest proposal is not the exact bounded mutation projection"
    }
    guard receipt.proposedBy == store.storedBy,
      receipt.proposedBy == canonical.captureActor,
      receipt.proposedBy == actor,
      receipt.proposedAt == occurredAt,
      receipt.proposedAt >= store.storedAt,
      receipt.proposedAt >= canonical.capturedAt
    else {
      return "the manifest-proposal actor or time does not match the command"
    }
    return nil
  }

  private static func completedCandidateMutationPreparationFactsValidationIssue(
    _ receipt:
      WorkspaceCompletedCandidateMutationPreparationFactsReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the completed-candidate preparation-facts receipt is malformed"
    }
    guard state.phase == .evaluating,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let attempt = state.attempts[receipt.attemptID],
      attempt.disposition == .completed,
      attempt.nodeID == receipt.nodeID,
      attempt.strategyFingerprint == receipt.strategyFingerprint,
      let nodeState = state.nodes[receipt.nodeID],
      nodeState.status == .awaitingVerification,
      let proposal =
        (state
        .completedCandidateMutationManifestProposalReceipts ?? [:])
        .values.first(where: {
          $0.receiptDigest == receipt.proposalReceiptDigest
        }),
      let store =
        (state
        .completedCandidateMutationContentStoreReceipts ?? [:])
        .values.first(where: {
          $0.receiptDigest
            == proposal
            .completedCandidateContentStoreReceiptDigest
        }),
      let capture = (state.completedCandidateCaptureReceipts ?? [:])[
        receipt.attemptID
      ],
      capture.receiptDigest == store.completedCandidateCaptureReceiptDigest,
      let release = state.runtimeReleaseReceipts[
        receipt.candidateReleaseReceiptID
      ], case .released = release.outcome,
      state.runtimeLiveLeases.isEmpty,
      state.runtimeFailedReleases.isEmpty,
      state.integrationTransactions.isEmpty
    else {
      return "preparation facts do not match active accepted origins"
    }
    let paths = Set(
      proposal.operations.compactMap {
        $0.sourcePath ?? $0.destinationPath
      })
    let pathBindings = Set(
      proposal.operations.map {
        MutationPathResolutionBinding(
          sequence: $0.sequence,
          sourcePath: $0.sourcePath,
          destinationPath: $0.destinationPath
        )
      })
    guard receipt.workspaceID == proposal.workspaceID,
      receipt.canonicalRootDigest == proposal.canonicalRootDigest,
      receipt.proposalJournalFrameDigest.rawValue.isEmpty == false,
      receipt.completedCandidateCaptureReceiptDigest == capture.receiptDigest,
      receipt.candidateReleaseReceiptID == capture.releaseReceiptID,
      receipt.candidateReleaseJournalFrameDigest == capture.releaseJournalFrameDigest,
      release.runID == receipt.runID,
      receipt.preparationBinding == proposal.preparationBinding,
      receipt.writeAuthority.authorizedPaths == paths,
      receipt.writeAuthority.authorizedRequirementIDs == proposal.touchedRequirementIDs,
      receipt.mutationBudget.maximumChangedFiles == proposal.changedFileCount,
      receipt.mutationBudget.maximumChangedBytes == proposal.changedByteCount,
      receipt.pathResolution.operations == pathBindings,
      receipt.pathObservations.count == proposal.operations.count,
      zip(receipt.pathObservations, proposal.operations).allSatisfy({
        observation, operation in
        observation.sequence == operation.sequence
          && observation.path == (operation.sourcePath ?? operation.destinationPath)
          && observation.exists == (operation.kind != .create)
          && (observation.exists == false
            || (observation.contentDigest == operation.expectedPreimage
              && observation.mode == operation.modeBefore))
      }),
      receipt.preparedBy == proposal.proposedBy,
      receipt.preparedBy == actor,
      receipt.preparedAt == occurredAt,
      receipt.preparedAt >= proposal.proposedAt
    else {
      return "preparation facts are not the exact inert proposal projection"
    }
    return nil
  }

  private static func completedCandidateMutationRollbackRehearsalValidationIssue(
    _ receipt:
      WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.validationIssues().isEmpty else {
      return "the completed-candidate rollback-rehearsal receipt is malformed"
    }
    guard state.phase == .evaluating,
      receipt.runID == state.runID,
      let contract = state.contract,
      contract.id == receipt.contractID,
      let attempt = state.attempts[receipt.attemptID],
      attempt.disposition == .completed,
      attempt.nodeID == receipt.nodeID,
      let node = state.nodes[receipt.nodeID],
      node.status == .accepted,
      let prepared =
        (state
        .completedCandidateMutationPreparationFactsReceipts ?? [:])[
          receipt.proposalReceiptDigest
        ],
      prepared.receiptDigest == receipt.preparationFactsReceiptDigest,
      let proposal =
        (state
        .completedCandidateMutationManifestProposalReceipts ?? [:])
        .values.first(where: {
          $0.receiptDigest == receipt.proposalReceiptDigest
        }),
      let store =
        (state
        .completedCandidateMutationContentStoreReceipts ?? [:])
        .values.first(where: {
          $0.receiptDigest
            == proposal
            .completedCandidateContentStoreReceiptDigest
        }),
      state.runtimeLiveLeases.isEmpty,
      state.runtimeFailedReleases.isEmpty,
      state.integrationTransactions.isEmpty
    else {
      return "rollback rehearsal does not match active accepted origins"
    }
    let manifest = receipt.rehearsalManifest
    guard receipt.workspaceID == prepared.workspaceID,
      receipt.canonicalRootDigest == prepared.canonicalRootDigest,
      receipt.preparationFactsJournalFrameDigest.rawValue.isEmpty == false,
      receipt.contentObjectSetDigest == store.verificationReceipt.objectSetDigest,
      manifest.candidateVerificationReceiptIDs.count == 1,
      let verificationID = manifest
        .candidateVerificationReceiptIDs.first,
      let verification = state.verificationReceipts[verificationID],
      verification.attemptID == receipt.attemptID,
      verification.result == .accepted,
      verification.requirementIDs == proposal.touchedRequirementIDs,
      verification.sourceRevision == proposal.expectedPostimageDigest,
      proposal.touchedRequirementIDs.allSatisfy({
        state.verificationIsEffective(
          verification,
          requirementID: $0
        )
      }),
      let review = state.reviewReceipts[
        manifest.independentReviewReceiptID
      ],
      review.attemptID == receipt.attemptID,
      review.requirementIDs == proposal.touchedRequirementIDs,
      review.sourceRevision == proposal.expectedPostimageDigest,
      review.decision == .approveCandidate,
      state.reviewMatchesVerification(
        review,
        verification: verification
      )
    else {
      return "rollback rehearsal lacks exact effective verification or review"
    }
    let visualRequirements =
      state.designBaseline.map {
        $0.requirementIDs.intersection(proposal.touchedRequirementIDs)
      } ?? []
    if visualRequirements.isEmpty {
      guard manifest.visualGateReceiptID == nil else {
        return "rollback rehearsal carries an unrequired visual receipt"
      }
    } else {
      guard let visualID = manifest.visualGateReceiptID,
        let visual = state.visualGateReceipts[visualID],
        visual.attemptID == receipt.attemptID,
        visual.requirementIDs.isSuperset(of: visualRequirements),
        visual.candidateSourceTree == proposal.expectedPostimageDigest,
        visual.result.accepted
      else {
        return "rollback rehearsal lacks the required exact visual gate"
      }
    }
    guard receipt.rehearsedBy == prepared.preparedBy,
      receipt.rehearsedBy == actor,
      receipt.rehearsedAt == occurredAt,
      receipt.rehearsedAt >= prepared.preparedAt
    else {
      return "rollback-rehearsal actor or time does not match the command"
    }
    return nil
  }

  private static func decideCompletedCandidateMutationRollbackRehearsal(
    _ authorityBox:
      WorkspaceCompletedCandidateMutationRollbackRehearsalAuthorityBox,
    state: KernelRunState,
    context: KernelCommandContext
  ) -> Result<[OrchestrationEventPayload], KernelRejection> {
    let authorized = authorityBox.authority
    let receipt = authorized.receipt
    guard authorized.journalValidationIssues().isEmpty else {
      return .failure(
        .invalidCompletedCandidateMutationRollbackRehearsal(
          "the live rollback-rehearsal authority does not match its receipt"
        )
      )
    }
    guard
      (state.completedCandidateMutationRollbackRehearsalReceipts
        ?? [:])[receipt.proposalReceiptDigest] == nil
    else {
      return .failure(
        .invalidCompletedCandidateMutationRollbackRehearsal(
          "a rollback rehearsal is already accepted for this proposal"
        )
      )
    }
    guard !state.allReceiptIDs.contains(receipt.rollbackRehearsal.id) else {
      return .failure(
        .invalidCompletedCandidateMutationRollbackRehearsal(
          "the rollback-rehearsal identity is already accepted"
        )
      )
    }
    if let issue = completedCandidateMutationRollbackRehearsalValidationIssue(
      receipt,
      state: state,
      actor: context.actor,
      occurredAt: context.issuedAt
    ) {
      return .failure(
        .invalidCompletedCandidateMutationRollbackRehearsal(issue)
      )
    }
    return .success([
      .completedCandidateMutationRollbackRehearsed(receipt)
    ])
  }

  private static func decideRuntimeRelease(
    _ authorized: AuthorizedKernelRuntimeRelease,
    state: KernelRunState
  ) -> Result<[OrchestrationEventPayload], KernelRejection> {
    let receipt = authorized.receipt
    guard !state.allReceiptIDs.contains(receipt.id) else {
      return .failure(.duplicateReceipt(receipt.id))
    }
    if let issue = runtimeReleaseValidationIssue(receipt, state: state) {
      return .failure(.invalidRuntimeReceipt(issue))
    }
    return .success([.runtimeReleaseRecorded(receipt)])
  }

  /// Runtime-release validation is intentionally isolated from the reducer's
  /// already-large command switch. This keeps the postimage containment path
  /// below Swift's async-test stack-guard limit without weakening any gate.
  private static func runtimeReleaseValidationIssue(
    _ receipt: RuntimeReleaseOutcomeReceipt,
    state: KernelRunState
  ) -> String? {
    guard receipt.runID == state.runID else {
      return "release run mismatch"
    }
    guard receipt.managedProcessTermination == nil || receipt.managedProcessExit == nil else {
      return "release cannot assert both natural exit and termination"
    }
    if let termination = receipt.managedProcessTermination {
      guard termination.handle == termination.exit.handle,
        termination.handle.runID == state.runID,
        termination.handle.resourceID == receipt.resourceID,
        termination.handle.leaseID == receipt.leaseID,
        termination.handle.processID > 0,
        termination.handle.processGroupID == termination.handle.processID,
        termination.exit.observedAtMonotonicNanoseconds <= receipt.observedAtMonotonicNanoseconds,
        !(termination.exit.exitCode != nil && termination.exit.terminationSignal != nil)
      else {
        return "managed process termination provenance mismatch"
      }
    }
    if let exit = receipt.managedProcessExit {
      guard exit.handle.runID == state.runID,
        exit.handle.resourceID == receipt.resourceID,
        exit.handle.leaseID == receipt.leaseID,
        exit.handle.processID > 0,
        exit.handle.processGroupID == exit.handle.processID,
        exit.observedAtMonotonicNanoseconds <= receipt.observedAtMonotonicNanoseconds,
        !(exit.exitCode != nil && exit.terminationSignal != nil)
      else {
        return "managed process natural-exit provenance mismatch"
      }
    }

    let postimageLaunch = (state.postimageVerifierLaunchReceipts ?? [:])
      .values.first(where: {
        $0.resourceID == receipt.resourceID
          && $0.leaseID == receipt.leaseID
      })
    if case .released = receipt.outcome, let postimageLaunch {
      guard
        let activation = state
          .postimageVerifierActivationReceipts?[
            postimageLaunch.activationReceiptID
          ],
        let recipes = state.contract?
          .requirementEvidenceRecipes,
        let recipe = recipes.first(where: {
          $0.id == postimageLaunch.evidenceRecipeID
        }),
        recipes.filter({
          $0.id == postimageLaunch.evidenceRecipeID
        }).count == 1,
        let probe = recipe.executableProbe,
        let containment = receipt.postimageVerifierContainment,
        let binding = state.runtimeBindingReceipts[
          postimageLaunch.bindingReceiptID
        ],
        KernelPostimageVerifierActivationCompiler.containment(
          containment,
          activation: activation,
          probe: probe,
          matches: postimageLaunch,
          binding: binding,
          release: receipt
        )
      else {
        return "postimage verifier release lacks exact containment"
      }
    } else if receipt.postimageVerifierContainment != nil {
      return "postimage containment has no exact verifier launch"
    }

    switch receipt.outcome {
    case .released(let release):
      guard let lease = state.runtimeLiveLeases[receipt.resourceID],
        lease.request.leaseID == receipt.leaseID,
        receipt.observedAtMonotonicNanoseconds >= lease.admittedAtMonotonicNanoseconds,
        release.id == receipt.id,
        release.runID == state.runID,
        release.resourceID == receipt.resourceID,
        release.leaseID == receipt.leaseID,
        release.releasedAtMonotonicNanoseconds == receipt.observedAtMonotonicNanoseconds
      else {
        return "release does not match live ownership"
      }
    case .cleanupFailed(let reasonDigest):
      guard receipt.postimageVerifierContainment == nil,
        receipt.managedProcessTermination == nil,
        receipt.managedProcessExit == nil,
        let lease = state.runtimeLiveLeases[receipt.resourceID],
        lease.request.leaseID == receipt.leaseID,
        receipt.observedAtMonotonicNanoseconds >= lease.admittedAtMonotonicNanoseconds,
        !reasonDigest.rawValue.isEmpty
      else {
        return "cleanup failure does not match live ownership"
      }
    case .rejected:
      guard receipt.postimageVerifierContainment == nil,
        receipt.managedProcessTermination == nil,
        receipt.managedProcessExit == nil
      else {
        return "rejected release cannot assert native termination"
      }
    }
    return nil
  }

  private static func durationRejection(
    state: KernelRunState,
    contract: TaskContract
  ) -> KernelRejection? {
    guard let duration = contract.acceptancePolicy.duration,
      let coverage = state.durationCoverage
    else { return nil }
    guard coverage.cumulativeAcceptedSeconds < Double(duration.requiredSeconds) else {
      return nil
    }
    return .durationIncomplete(
      requiredSeconds: duration.requiredSeconds,
      acceptedSeconds: UInt64(
        max(
          0,
          coverage.cumulativeAcceptedSeconds.rounded(.down)
        ))
    )
  }

  private static func substitutionViolation(
    contract: TaskContract,
    receipt: VerificationReceipt
  ) -> String? {
    let relevant = contract.constraints.filter { constraint in
      guard constraint.kind == .prohibitSubstitution,
        let rule = constraint.substitutionRule
      else { return false }
      return !rule.requirementIDs.isDisjoint(with: receipt.requirementIDs)
    }
    let observations = receipt.implementationObservations ?? []
    let relevantIDs = Set(relevant.map(\.id))
    let observedIDs = Set(observations.map(\.constraintID))
    guard observedIDs == relevantIDs else {
      let missing = relevantIDs.subtracting(observedIDs).sorted()
      let unexpected = observedIDs.subtracting(relevantIDs).sorted()
      return
        "implementation observations do not exactly match bound constraints; missing=\(missing); unexpected=\(unexpected)"
    }
    for constraint in relevant.sorted(by: { $0.id < $1.id }) {
      guard let rule = constraint.substitutionRule else { continue }
      let matches = observations.filter { $0.constraintID == constraint.id }
      guard matches.count == 1, let observation = matches.first else {
        return "constraint \(constraint.id) requires exactly one implementation observation"
      }
      guard !observation.evidenceDigest.rawValue.isEmpty,
        observation.implementationID
          == observation.implementationID.trimmingCharacters(
            in: .whitespacesAndNewlines
          ),
        rule.permittedImplementationIDs.contains(observation.implementationID)
      else {
        return
          "constraint \(constraint.id) rejected implementation identity \(observation.implementationID)"
      }
    }
    return nil
  }

  private static func deliverableCardinalityViolation(
    contract: TaskContract,
    receipt: VerificationReceipt
  ) -> DeliverableCardinalityViolation? {
    let relevant = contract.requirements.filter {
      receipt.requirementIDs.contains($0.id) && $0.deliverableCardinality != nil
    }
    let observations = receipt.deliverableObservations ?? []
    let relevantIDs = Set(relevant.map(\.id))
    let observedIDs = Set(observations.map(\.requirementID))

    if let missing = relevantIDs.subtracting(observedIDs).sorted(
      by: { $0.rawValue < $1.rawValue }
    ).first {
      return .missingObservation(missing)
    }
    if let unexpected = observedIDs.subtracting(relevantIDs).sorted(
      by: { $0.rawValue < $1.rawValue }
    ).first {
      return .unexpectedObservation(unexpected)
    }

    for requirement in relevant.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
      guard let constraint = requirement.deliverableCardinality else { continue }
      let matches = observations.filter { $0.requirementID == requirement.id }
      guard matches.count == 1, let observation = matches.first else {
        return .duplicateObservation(requirement.id)
      }
      guard observation.collectionID == constraint.collectionID else {
        return .collectionMismatch(
          requirementID: requirement.id,
          expected: constraint.collectionID,
          actual: observation.collectionID
        )
      }
      guard !observation.evidenceDigest.rawValue.isEmpty,
        !observation.members.contains(where: {
          $0.stableID.isEmpty
            || $0.stableID
              != $0.stableID.trimmingCharacters(
                in: .whitespacesAndNewlines
              )
            || $0.contentDigest.rawValue.isEmpty
        })
      else {
        return .invalidEvidence(requirement.id)
      }

      let stableIDGroups = Dictionary(grouping: observation.members, by: \.stableID)
      if let duplicateID = stableIDGroups.keys.sorted().first(where: {
        (stableIDGroups[$0]?.count ?? 0) != 1
      }) {
        return .duplicateMemberIdentity(
          requirementID: requirement.id,
          stableID: duplicateID
        )
      }
      let actual = UInt64(observation.members.count)
      guard actual == constraint.exactCount else {
        return .countMismatch(
          requirementID: requirement.id,
          expected: constraint.exactCount,
          actual: actual
        )
      }
    }
    return nil
  }

  private static func hasDependencyCycle(_ nodes: [KernelNodeContract]) -> Bool {
    let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.dependencies) })
    var visiting = Set<KernelNodeID>()
    var visited = Set<KernelNodeID>()

    func visit(_ id: KernelNodeID) -> Bool {
      if visiting.contains(id) { return true }
      if visited.contains(id) { return false }
      visiting.insert(id)
      for dependency in byID[id] ?? [] where visit(dependency) {
        return true
      }
      visiting.remove(id)
      visited.insert(id)
      return false
    }

    return nodes.contains { visit($0.id) }
  }

  private static func externalDependencyObservationValidationIssue(
    _ receipt: ExternalDependencyObservationReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> ExternalDependencyObservationViolation? {
    guard let attempt = state.attempts[receipt.attemptID],
      state.activeAttemptID == receipt.attemptID,
      attempt.disposition == nil
    else {
      return .mismatchedAttempt(receipt.attemptID)
    }
    guard let contract = state.contract,
      let dependency = (contract.externalDependencies ?? [])
        .first(where: { $0.id == receipt.dependencyID })
    else {
      return .unknownDependency(receipt.dependencyID)
    }
    let boundRequirements = dependency.requirementIDs.intersection(
      attempt.requirementIDs
    )
    guard !boundRequirements.isEmpty,
      receipt.requirementIDs == boundRequirements
    else {
      return .mismatchedRequirements(dependency.id)
    }
    guard receipt.observer == actor,
      receipt.observer.lineageDigest != attempt.worker.lineageDigest,
      dependency.authorizedObserverLineageDigests.contains(
        receipt.observer.lineageDigest
      )
    else {
      return .unauthorizedObserver(dependency.id)
    }
    guard receipt.evidenceRecipeID == dependency.evidenceRecipeID else {
      return .mismatchedEvidenceRecipe(dependency.id)
    }
    guard
      KernelPostimageVerifierActivationCompiler.validSHA256(
        receipt.evidenceDigest
      ),
      receipt.observedAt == occurredAt
    else {
      return .invalidEvidence(dependency.id)
    }
    let provenance = [
      receipt.sourceResultID != nil,
      receipt.sourceResultEvidenceSetDigest != nil,
      receipt.sourceReleaseReceiptID != nil,
      receipt.sourceReleaseFrameDigest != nil,
    ]
    if provenance.contains(true) {
      guard provenance.allSatisfy({ $0 }),
        let resultID = receipt.sourceResultID,
        !resultID.rawValue.isEmpty,
        let resultDigest =
          receipt.sourceResultEvidenceSetDigest,
        KernelPostimageVerifierActivationCompiler.validSHA256(
          resultDigest
        ),
        let releaseID = receipt.sourceReleaseReceiptID,
        state.runtimeReleaseReceipts[releaseID] != nil,
        let releaseFrameDigest =
          receipt.sourceReleaseFrameDigest,
        KernelPostimageVerifierActivationCompiler.validSHA256(
          releaseFrameDigest
        )
      else {
        return .invalidEvidence(dependency.id)
      }
    }
    return nil
  }

  private static func nativeVisualAuthorityValidationIssues(
    receipt: VisualGateEvaluationReceipt,
    candidate: VisualCandidateBundle
  ) -> [String] {
    let requestDigest = receipt.nativeReviewRequestDigest
    let captureDigests = receipt.nativeCaptureAttestationDigests
    let measurementDigests = receipt.nativeMeasurementAttestationDigests
    let reviewedAt = receipt.nativeReviewCompletedAt
    let presentCount = [
      requestDigest != nil,
      captureDigests != nil,
      measurementDigests != nil,
      reviewedAt != nil,
    ].filter { $0 }.count
    if presentCount == 0 { return [] }
    guard presentCount == 4,
      let requestDigest,
      let captureDigests,
      let measurementDigests,
      let reviewedAt
    else {
      return ["native visual authority provenance must be all-or-none"]
    }
    var issues: [String] = []
    if !KernelPostimageVerifierActivationCompiler.validSHA256(
      requestDigest
    ) {
      issues.append("native review request digest must be exact SHA-256")
    }
    if captureDigests.count != candidate.captures.count
      || captureDigests.contains(where: {
        !KernelPostimageVerifierActivationCompiler.validSHA256($0)
      })
    {
      issues.append("native capture attestations must cover every candidate capture")
    }
    if measurementDigests.count != candidate.measurements.count
      || measurementDigests.contains(where: {
        !KernelPostimageVerifierActivationCompiler.validSHA256($0)
      })
    {
      issues.append("native measurement attestations must cover every measurement")
    }
    let latestCapture =
      candidate.captures.map(\.capturedAt).max()
      ?? candidate.mutationStartedAt
    if reviewedAt < candidate.mutationStartedAt
      || reviewedAt < latestCapture
      || reviewedAt > receipt.evaluatedAt
    {
      issues.append("native review time must follow candidate evidence and precede evaluation")
    }
    return issues
  }

  private static func designBaselineValidationIssues(
    state: KernelRunState,
    baseline: DesignBaselineBundle,
    recordedAt: Date
  ) -> [String] {
    guard let contract = state.contract else { return ["task contract is absent"] }
    var issues: [String] = []
    if baseline.id.rawValue.isEmpty
      || baseline.contractID != contract.id
      || baseline.sourceTree.rawValue.isEmpty
      || baseline.builtArtifact.rawValue.isEmpty
      || baseline.captureProtocol.rawValue.isEmpty
      || baseline.designTokenSnapshot.rawValue.isEmpty
      || baseline.semanticSurfaceManifest.rawValue.isEmpty
    {
      issues.append("baseline identity and content digests must be complete")
    }
    let knownRequirements = Set(contract.requirements.map(\.id))
    if baseline.requirementIDs.isEmpty
      || !baseline.requirementIDs.isSubset(of: knownRequirements)
    {
      issues.append("visual requirements must be declared by the task contract")
    }
    let protectedReference = contract.protectedBaselines.first {
      $0.id == baseline.protectedBaselineID
    }
    if protectedReference?.preservationRequired != true
      || protectedReference?.artifactDigest != baseline.builtArtifact
    {
      issues.append("built baseline must match a preservation-required contract baseline")
    }
    if baseline.authority.baselineID != baseline.id
      || !baseline.authority.isProductDesignAuthority
      || baseline.authority.issuedAt > baseline.frozenAt
      || baseline.frozenAt > recordedAt
    {
      issues.append("baseline freeze requires prior product-design authority")
    }
    guard let captures = baseline.captureByCell, !captures.isEmpty else {
      issues.append("baseline captures must be non-empty and unique by visual cell")
      return issues
    }
    let captureCells = Set(captures.keys)
    let contractedCells = Set(baseline.protectedInvariants.flatMap(\.cellIDs))
    if contractedCells.isEmpty || !contractedCells.isSubset(of: captureCells) {
      issues.append("protected invariant cells must have native captures")
    }
    let invariantIDs = baseline.protectedInvariants.map(\.id)
    if invariantIDs.contains(where: { $0.isEmpty })
      || Set(invariantIDs).count != invariantIDs.count
    {
      issues.append("protected invariants require unique non-empty IDs")
    }
    if captures.values.contains(where: {
      !$0.isComplete
        || $0.sourceTree != baseline.sourceTree
        || $0.builtArtifact != baseline.builtArtifact
        || $0.captureProtocol != baseline.captureProtocol
        || $0.capturedAt > baseline.frozenAt
    }) {
      issues.append("baseline capture provenance does not match the frozen bundle")
    }
    let debtIDs = baseline.knownDebt.map(\.id)
    if Set(debtIDs).count != debtIDs.count
      || baseline.knownDebt.contains(where: {
        $0.id.rawValue.isEmpty
          || $0.cellIDs.isEmpty
          || !$0.cellIDs.isSubset(of: contractedCells)
          || !$0.baselineSeverity.isFinite
          || $0.baselineSeverity < 0
          || !$0.maximumInterimSeverity.isFinite
          || $0.maximumInterimSeverity < 0
          || $0.evidenceDigest.rawValue.isEmpty
      })
    {
      issues.append("known design debt is malformed or outside the capture contract")
    }
    return issues
  }
}

struct KernelNodeProjection: Codable, Equatable, Sendable {
  var nodeID: KernelNodeID
  var requirementIDs: Set<RequirementID>
  var acceptedRequirementIDs: Set<RequirementID>
  var dependencyNodeIDs: Set<KernelNodeID>
  var writablePaths: Set<String>
  var maximumChangedFiles: Int
  var maximumChangedBytes: Int
  var capabilityIDs: Set<String>
  var status: KernelNodeStatus
  var attemptIDs: [AttemptID]
  var activeAttemptID: AttemptID?
  var strategyFingerprint: StrategyFingerprint
  var strategyRetired: Bool
  var verificationReceiptCount: Int
  var reviewReceiptCount: Int
  var visualReceiptCount: Int
  var latestVisualAccepted: Bool?

  var allRequirementsAccepted: Bool {
    !requirementIDs.isEmpty && requirementIDs.isSubset(of: acceptedRequirementIDs)
  }
}

struct KernelRunProjection: Codable, Equatable, Sendable {
  var runID: KernelRunID
  var sequence: UInt64
  var phase: KernelRunPhase
  var mandatoryRequirementCount: Int
  var acceptedRequirementCount: Int
  var activeAttemptID: AttemptID?
  var retiredStrategyCount: Int
  var runtimeLiveResourceCount: Int
  var runtimeFailedReleaseCount: Int
  /// Optional for decoding projections produced before provider launch was
  /// promoted to an independently replayed event.
  var providerLaunchCount: Int? = nil
  var runtimeDrainIntent: RuntimeDrainIntent?
  var quiescent: Bool
  var convergenceEpochID: String?
  var causalAttemptsConsumed: UInt32
  var causalStrategiesConsumed: UInt16
  var causalRetiredStrategyCount: Int
  var causalDamageEvents: UInt16
  var convergenceDiagnosis: ConvergenceDiagnosticProjection?
  var durationRequiredSeconds: UInt64?
  var durationAcceptedSeconds: Double
  var durationExcludedSeconds: Double
  var durationCoverageViolations: [CoverageViolation]
  var designBaselineFrozen: Bool
  var visualEvaluationCount: Int
  var latestVisualAccepted: Bool?
  var latestVisualFailingDimensionCount: Int
  var integrationTransactionCount: Int
  var independentlyAcceptedIntegrationCount: Int
  var quarantinedIntegrationCount: Int
  var completionAuthorizationReceiptID: ReceiptID? = nil
  var nodes: [KernelNodeProjection]

  init(state: KernelRunState) {
    runID = state.runID
    sequence = state.sequence
    phase = state.phase
    mandatoryRequirementCount = state.contract?.mandatoryRequirementIDs.count ?? 0
    acceptedRequirementCount =
      state.contract?.mandatoryRequirementIDs
      .intersection(state.acceptedRequirementIDs).count ?? 0
    activeAttemptID = state.activeAttemptID
    retiredStrategyCount = state.retiredStrategies.count
    runtimeLiveResourceCount = state.runtimeLiveLeases.count
    runtimeFailedReleaseCount = state.runtimeFailedReleases.count
    providerLaunchCount = state.providerLaunchReceipts?.count ?? 0
    runtimeDrainIntent = state.lastRuntimeDrainReceiptID.flatMap {
      state.runtimeDrainReceipts[$0]?.snapshot.intent
    }
    quiescent = state.quiescenceReceipt?.provesQuiescence == true
    convergenceEpochID = state.convergenceGovernor?.epochID
    causalAttemptsConsumed = state.convergenceGovernor?.consumption.attempts ?? 0
    causalStrategiesConsumed = state.convergenceGovernor?.consumption.strategies ?? 0
    causalRetiredStrategyCount = state.convergenceGovernor?.retiredStrategies.count ?? 0
    causalDamageEvents = state.convergenceGovernor?.consumption.damageEvents ?? 0
    convergenceDiagnosis = state.convergenceGovernor?.diagnosticProjection(
      sourceSequence: state.sequence
    )
    let durationCoverage = state.durationCoverage
    durationRequiredSeconds = state.contract?.acceptancePolicy.duration?.requiredSeconds
    durationAcceptedSeconds = durationCoverage?.cumulativeAcceptedSeconds ?? 0
    durationExcludedSeconds = durationCoverage?.excludedClosedSeconds ?? 0
    durationCoverageViolations = durationCoverage?.violations ?? []
    designBaselineFrozen = state.designBaseline != nil
    visualEvaluationCount = state.visualGateReceipts.count
    let latestVisual = state.visualGateReceipts.values.max {
      $0.journalSequence < $1.journalSequence
    }
    latestVisualAccepted = latestVisual?.result.accepted
    latestVisualFailingDimensionCount = latestVisual?.result.failingDimensions.count ?? 0
    integrationTransactionCount = state.integrationTransactions.count
    independentlyAcceptedIntegrationCount =
      state.integrationTransactions.values.filter {
        $0.phase == .independentlyAccepted
      }.count
    quarantinedIntegrationCount =
      state.integrationTransactions.values.filter {
        $0.phase == .rollbackFailedQuarantined
      }.count
    completionAuthorizationReceiptID =
      state.completionAuthorizationReceipt?.id
    let acceptedRequirements = state.acceptedRequirementIDs
    nodes = state.nodes.values.map { node in
      let attemptIDs = node.attemptIDs
      let attemptIDSet = Set(attemptIDs)
      let verificationCount = state.verificationReceipts.values.filter {
        attemptIDSet.contains($0.attemptID)
      }.count
      let reviewCount = state.reviewReceipts.values.filter {
        attemptIDSet.contains($0.attemptID)
      }.count
      let visualReceipts = state.visualGateReceipts.values.filter {
        attemptIDSet.contains($0.attemptID)
      }
      let latestNodeVisual = visualReceipts.max {
        $0.journalSequence < $1.journalSequence
      }
      return KernelNodeProjection(
        nodeID: node.contract.id,
        requirementIDs: node.contract.requirementIDs,
        acceptedRequirementIDs: node.contract.requirementIDs
          .intersection(acceptedRequirements),
        dependencyNodeIDs: node.contract.dependencies,
        writablePaths: node.contract.mutationScope.writablePaths,
        maximumChangedFiles: node.contract.mutationScope.maximumChangedFiles,
        maximumChangedBytes: node.contract.mutationScope.maximumChangedBytes,
        capabilityIDs: node.contract.capabilityIDs,
        status: node.status,
        attemptIDs: attemptIDs,
        activeAttemptID: state.activeAttemptID.flatMap {
          attemptIDSet.contains($0) ? $0 : nil
        },
        strategyFingerprint: node.contract.strategyFingerprint,
        strategyRetired: state.retiredStrategies.contains(
          node.contract.strategyFingerprint
        ),
        verificationReceiptCount: verificationCount,
        reviewReceiptCount: reviewCount,
        visualReceiptCount: visualReceipts.count,
        latestVisualAccepted: latestNodeVisual?.result.accepted
      )
    }.sorted { $0.nodeID.rawValue < $1.nodeID.rawValue }
  }
}
