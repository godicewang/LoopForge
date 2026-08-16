import Foundation

struct WorkspaceCompletedCandidateMutationApplyPreparationRequest: Sendable {
  var preflight: WorkspaceCompletedCandidateMutationPreflightInstallation
  var registration: WorkspaceMutationRecoveryRegistration
  /// Non-Codable, exact-run proof that every ratified verifier and reviewer
  /// recipe has an installable pre-exec containment route. No Release caller
  /// can manufacture this capability on ordinary macOS.
  var containmentReadiness: AuthorizedKernelPostimageContainmentReadiness?
  var leaseID: ResourceLeaseID
  var admissionReceiptID: ReceiptID
  var admissionCommandID: RunCommandID
  var intentID: IntegrationEffectIntentID
  var intentCommandID: RunCommandID
  var startCommandID: RunCommandID
  var recordCommandID: RunCommandID
  var releaseReceiptID: ReceiptID
  var releaseCommandID: RunCommandID
  var failureReceiptID: ReceiptID
  var failureCommandID: RunCommandID
  var issuedAt: Date
  var expiresAt: Date
  var requestedAtMonotonicNanoseconds: UInt64
  var expiresAtMonotonicNanoseconds: UInt64
  var executorLimits: WorkspaceMutationExecutorLimits = .conservative
}

struct WorkspaceCompletedCandidateMutationApplyPreparationInstallation:
  Sendable
{
  var preflight: AuthorizedWorkspaceCompletedCandidateMutationPreflight
  var leaseAdmission: JournaledWorkspaceMutationLeaseAdmission
  var intent: IntegrationApplyIntent
  var intentJournalTransaction: JournalTransactionReceipt
  var effectEnvelope: WorkspaceMutationEffectEnvelope
  /// Exact, non-Codable join handle retained by the production composition
  /// root. Dropping this actor does not release the durable lease; normal quit
  /// must either consume it or fail closed while startup recovery remains the
  /// crash-only owner.
  var applicationTerminationJoin:
    WorkspaceMutationApplicationTerminationJoin
}

struct WorkspaceMutationApplicationTerminationPlan: Equatable, Sendable {
  let runID: KernelRunID
  let transactionID: IntegrationTransactionID
  let intentID: IntegrationEffectIntentID
  let payloadDigest: ContentDigest
  let action: RuntimeCleanupAction
  let releaseReceiptID: ReceiptID
  let releaseCommandID: RunCommandID
}

struct WorkspaceMutationApplicationTerminationReceipt: Equatable, Sendable {
  let plan: WorkspaceMutationApplicationTerminationPlan
  let releaseReceiptID: ReceiptID
  let releaseFrameDigest: ContentDigest
  let finalIntegrationPhase: IntegrationTransactionPhase
}

enum WorkspaceMutationApplicationTerminationJoinError:
  Error,
  Equatable,
  Sendable
{
  case ownershipChanged
  case outboxChanged
  case integrationChanged
  case expectedPlanChanged
  case dispatchFailed
  case releaseReceiptMissing
  case cleanupIncomplete
}

/// Live join capability for one already-authorized, durably enqueued workspace
/// apply. It can do exactly one thing during normal application termination:
/// finish the exact pending envelope through the existing journaled runtime,
/// then prove the lease release and applied-unverified transaction. It cannot
/// mint a lease, replace an envelope, expand a workspace, or recover a
/// productive capability after a crash.
actor WorkspaceMutationApplicationTerminationJoin {
  private let journal: RunJournal
  private let supervisor: RuntimeSupervisor
  private let outbox: WorkspaceMutationEffectOutbox
  private let dispatcher: JournaledWorkspaceMutationDispatcher
  private let runtimeLease: RuntimeResourceLease
  private let envelope: WorkspaceMutationEffectEnvelope
  private let expectedPlan: WorkspaceMutationApplicationTerminationPlan

  fileprivate init(
    journal: RunJournal,
    supervisor: RuntimeSupervisor,
    outbox: WorkspaceMutationEffectOutbox,
    dispatcher: JournaledWorkspaceMutationDispatcher,
    runtimeLease: RuntimeResourceLease,
    envelope: WorkspaceMutationEffectEnvelope
  ) {
    self.journal = journal
    self.supervisor = supervisor
    self.outbox = outbox
    self.dispatcher = dispatcher
    self.runtimeLease = runtimeLease
    self.envelope = envelope
    expectedPlan = WorkspaceMutationApplicationTerminationPlan(
      runID: runtimeLease.request.runID,
      transactionID: envelope.transactionID,
      intentID: envelope.intentID,
      payloadDigest: envelope.payloadDigest,
      action: .awaitJoin(
        resourceID: runtimeLease.request.resourceID,
        leaseID: runtimeLease.request.leaseID
      ),
      releaseReceiptID: envelope.releaseReceiptID,
      releaseCommandID: envelope.releaseCommandID
    )
  }

  func preflight() async throws
    -> WorkspaceMutationApplicationTerminationPlan
  {
    guard envelope.runID == runtimeLease.request.runID,
      envelope.transactionID.rawValue
        == runtimeLease.request.occurrenceID?.rawValue,
      envelope.payload.intentID == envelope.intentID,
      envelope.payload.transactionID == envelope.transactionID,
      runtimeLease.request.kind == .workspaceMutation,
      runtimeLease.request.ownership == .owned,
      runtimeLease.request.releasePolicy == .join,
      await journal.runtimeLease(
        resourceID: runtimeLease.request.resourceID
      ) == runtimeLease
    else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .ownershipChanged
    }
    let projection = await supervisor.projection()
    guard projection.liveLeases == [runtimeLease],
      projection.failedReleases.isEmpty,
      projection.queuedLeases.isEmpty,
      await supervisor.cleanupPlan() == [expectedPlan.action]
    else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .ownershipChanged
    }
    let pending: [WorkspaceMutationEffectEnvelope]
    do {
      pending = try await outbox.pending(limit: 2)
    } catch {
      throw WorkspaceMutationApplicationTerminationJoinError.outboxChanged
    }
    guard pending == [envelope] else {
      throw WorkspaceMutationApplicationTerminationJoinError.outboxChanged
    }
    guard let transaction = await journal.integrationTransaction(
      transactionID: envelope.transactionID
    ), transaction.phase == .applying,
      transaction.applyIntent?.id == envelope.intentID,
      transaction.applyReceipt == nil
    else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .integrationChanged
    }
    return expectedPlan
  }

  func join(
    expected: WorkspaceMutationApplicationTerminationPlan
  ) async throws -> WorkspaceMutationApplicationTerminationReceipt {
    guard try await preflight() == expected else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .expectedPlanChanged
    }
    let dispatch: WorkspaceMutationEffectDispatchReport
    do {
      dispatch = try await dispatcher.recoverPending(limit: 1)
    } catch {
      throw WorkspaceMutationApplicationTerminationJoinError.dispatchFailed
    }
    guard dispatch.scannedCount == 1,
      dispatch.completedIntentIDs == [expected.intentID],
      dispatch.quarantinedIntentIDs.isEmpty,
      dispatch.failures.isEmpty
    else {
      throw WorkspaceMutationApplicationTerminationJoinError.dispatchFailed
    }
    let release = await journal.runtimeReleaseReceipt(
      receiptID: expected.releaseReceiptID
    )
    guard let release,
      release.runID == expected.runID,
      release.resourceID == runtimeLease.request.resourceID,
      release.leaseID == runtimeLease.request.leaseID,
      case .released(let managedRelease) = release.outcome,
      managedRelease.id == expected.releaseReceiptID,
      managedRelease.runID == expected.runID,
      managedRelease.resourceID == runtimeLease.request.resourceID,
      managedRelease.leaseID == runtimeLease.request.leaseID,
      let releaseTransaction = await journal.transactionReceipt(
        commandID: expected.releaseCommandID
      )
    else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .releaseReceiptMissing
    }
    let remainingPending: [WorkspaceMutationEffectEnvelope]
    do {
      remainingPending = try await outbox.pending(limit: 1)
    } catch {
      throw WorkspaceMutationApplicationTerminationJoinError.outboxChanged
    }
    guard remainingPending.isEmpty,
      await supervisor.cleanupPlan().isEmpty,
      await journal.runtimeLease(
        resourceID: runtimeLease.request.resourceID
      ) == nil,
      let transaction = await journal.integrationTransaction(
        transactionID: expected.transactionID
      ), transaction.phase == .appliedUnverified,
      transaction.applyReceipt?.intentID == expected.intentID
    else {
      throw WorkspaceMutationApplicationTerminationJoinError
        .cleanupIncomplete
    }
    return WorkspaceMutationApplicationTerminationReceipt(
      plan: expected,
      releaseReceiptID: release.id,
      releaseFrameDigest: releaseTransaction.frameDigest,
      finalIntegrationPhase: transaction.phase
    )
  }
}

enum WorkspaceCompletedCandidateMutationApplyPreparationError:
  Error,
  Equatable,
  Sendable
{
  case invalidPreflightAuthority
  case preflightNotAccepted
  case registrationMismatch
  case canonicalWorkspaceChanged
  case objectStoreChanged
  case journalStateMismatch
  case containmentReadinessUnavailable
  case invalidIdentity
  case leaseAdmissionRejected
  case transitionAuthorityUnavailable
  case intentJournalRejected
  case retainedIntentMismatch
  case outboxRejected(WorkspaceMutationEffectOutboxError)
}

/// Converts one exact live completed-candidate preflight into a durable,
/// recoverable apply request without entering the filesystem executor.
///
/// Ordering is fail-closed across crash boundaries: revalidate the canonical
/// workspace and immutable object set; durably admit one bounded exclusive
/// lease; journal the exact apply intent; then persist the content-bearing
/// request in the registered external outbox. A crash after either journal
/// frame is resumed only by exact identity replay. No apply receipt,
/// verification, acceptance, or publication authority is issued here.
actor WorkspaceCompletedCandidateMutationApplyPreparationCoordinator {
  private let registry: WorkspaceMutationRecoveryRegistry
  private let journal: RunJournal
  private let wallClock: @Sendable () -> Date
  private let monotonicClock: @Sendable () -> UInt64

  init(
    registry: WorkspaceMutationRecoveryRegistry,
    journal: RunJournal,
    wallClock: @escaping @Sendable () -> Date = { Date() },
    monotonicClock: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) {
    self.registry = registry
    self.journal = journal
    self.wallClock = wallClock
    self.monotonicClock = monotonicClock
  }

  func prepare(
    _ request: WorkspaceCompletedCandidateMutationApplyPreparationRequest,
    durability: JournalDurability = .boundary
  ) async throws
    -> WorkspaceCompletedCandidateMutationApplyPreparationInstallation
  {
    let preflight = request.preflight.authority
    guard preflight.validationIssues().isEmpty else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .invalidPreflightAuthority
    }
    guard await acceptedPreflight(request.preflight) else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .preflightNotAccepted
    }
    guard
      let retainedRegistration = try? await registry.registration(
        runID: preflight.proposal.runID
      ), retainedRegistration == request.registration,
      request.registration.runID == journal.runID,
      request.registration.workspaceID == preflight.rehearsal.receipt.workspaceID,
      request.registration.actorIdentity == preflight.rehearsal.receipt.rehearsedBy,
      request.registration.workspaceRoot
        == request.registration.workspaceRoot.standardizedFileURL
        .resolvingSymlinksInPath()
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .registrationMismatch
    }
    do {
      try WorkspaceCompletedCandidateMutationPreparationFactsCoordinator
        .revalidateCanonicalWorkspace(
          preparation: preflight.rehearsal.preparation.receipt,
          proposal:
            preflight.rehearsal.preparation.proposal.receipt,
          canonicalWorkspaceRoot: request.registration.workspaceRoot
        )
    } catch {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .canonicalWorkspaceChanged
    }
    guard preflight.rehearsal.externalArtifactValidationIssues().isEmpty
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .objectStoreChanged
    }
    let state = await journal.state
    let transactionID = preflight.proposal.transactionID
    guard state.phase == .evaluating,
      state.runtimeFailedReleases.isEmpty,
      let contract = state.contract,
      let transaction = state.integrationTransactions[transactionID],
      transaction.proposal == preflight.proposal,
      transaction.preflightReceipt == preflight.receipt,
      transaction.rollbackManifest == preflight.rollback,
      transaction.phase == .rollbackPrepared
        || transaction.phase == .applying
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .journalStateMismatch
    }
    guard let containmentReadiness = request.containmentReadiness,
      containmentReadiness.authorizes(
        runID: journal.runID,
        integrationTransactionID: transactionID,
        contract: contract
      )
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .containmentReadinessUnavailable
    }
    guard Self.requestIdentityIsValid(request) else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .invalidIdentity
    }

    let supervisor = RuntimeSupervisor(
      runID: request.registration.runID,
      budget: request.registration.hostBudget
    )
    let leaseAuthority = JournaledWorkspaceMutationLeaseAuthority(
      supervisor: supervisor,
      journal: journal,
      actorIdentity: request.registration.actorIdentity
    )
    do {
      try await leaseAuthority.reconcileSupervisorFromJournal()
    } catch {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .leaseAdmissionRejected
    }
    let admission: JournaledWorkspaceMutationLeaseAdmission
    let liveRootIdentity: ContentDigest
    do {
      liveRootIdentity =
        try WorkspaceMutationFilesystemExecutor
        .rootIdentity(request.registration.workspaceRoot)
    } catch {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .canonicalWorkspaceChanged
    }
    do {
      admission = try await leaseAuthority.admit(
        transactionID: transactionID,
        workspaceID: request.registration.workspaceID,
        rootIdentity: liveRootIdentity,
        operation: .apply,
        leaseID: request.leaseID,
        admissionReceiptID: request.admissionReceiptID,
        admissionCommandID: request.admissionCommandID,
        issuedAt: request.issuedAt,
        expiresAt: request.expiresAt,
        requestedAtMonotonicNanoseconds:
          request.requestedAtMonotonicNanoseconds,
        expiresAtMonotonicNanoseconds:
          request.expiresAtMonotonicNanoseconds
      )
    } catch {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .leaseAdmissionRejected
    }

    let sourceRevision = preflight.rehearsal.preparation.proposal
      .contentStore.completedCandidate.candidateRevision
    let capturePolicy = WorkspaceCandidatePostimageCapturePolicy(
      sourceRevision: sourceRevision
    )
    guard capturePolicy.validationIssues().isEmpty,
      capturePolicy.capturePolicyDigest
        == preflight.rehearsal.preparation.proposal.contentStore.receipt
        .derivation.capturePolicyDigest
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .invalidPreflightAuthority
    }
    let intent = IntegrationApplyIntent(
      id: request.intentID,
      transactionID: transactionID,
      preflightReceiptID: preflight.receipt.id,
      manifestDigest:
        preflight.rehearsal.receipt.forwardManifestDigest,
      canonicalPreimageDigest:
        preflight.proposal.canonicalPreimageDigest,
      rollbackManifestDigest:
        preflight.rehearsal.receipt.rollbackManifestDigest,
      stagedObjectSetDigest:
        preflight.rehearsal.receipt.contentObjectSetDigest,
      exclusiveLeaseReceiptID: admission.executionLease.receiptID,
      remoteAccessDisabled: true,
      requestedAt: request.issuedAt,
      candidatePostimageCapturePolicyDigest:
        capturePolicy.capturePolicyDigest
    )
    guard
      let transition =
        AuthorizedKernelIntegrationTransition
        .issuedByCompletedCandidateApplyPreparationRuntime(
          .startApply(intent),
          preflight: preflight,
          admission: admission
        )
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .transitionAuthorityUnavailable
    }
    let intentTransaction: JournalTransactionReceipt
    if transaction.phase == .applying {
      guard transaction.applyIntent == intent,
        var retained = await journal.transactionReceipt(
          commandID: request.intentCommandID
        ),
        await journal.integrationTransitionEvent(
          transaction: retained
        ) == .applyStarted(intent)
      else {
        throw WorkspaceCompletedCandidateMutationApplyPreparationError
          .retainedIntentMismatch
      }
      retained.duplicate = true
      intentTransaction = retained
    } else {
      do {
        intentTransaction =
          try await journal
          .transactAtCurrentSequence(
            .advanceIntegration(transition),
            commandID: request.intentCommandID,
            issuedAt: request.issuedAt,
            actor: request.registration.actorIdentity,
            durability: durability
          )
      } catch {
        throw WorkspaceCompletedCandidateMutationApplyPreparationError
          .intentJournalRejected
      }
    }
    guard
      let applying = await journal.integrationTransaction(
        transactionID: transactionID
      ), applying.phase == .applying,
      applying.applyIntent == intent
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .retainedIntentMismatch
    }

    let executionRequest = WorkspaceMutationExecutionRequest(
      workspaceRoot: request.registration.workspaceRoot,
      recoveryRoot: request.registration.outboxRoot.appendingPathComponent(
        "workspace-recovery",
        isDirectory: true
      ),
      workspaceID: request.registration.workspaceID,
      preimage: preflight.rehearsal.preparation.proposal
        .canonicalPreimage.receipt.preimage,
      manifest: preflight.rehearsal.manifest,
      rollbackManifest: preflight.rollback,
      preflightReceipt: preflight.receipt,
      intent: intent,
      lease: admission.executionLease,
      contentObjects: preflight.rehearsal.preparation.proposal
        .contentStore.objects,
      executor: request.registration.actorIdentity,
      completedAt: request.issuedAt,
      limits: request.executorLimits,
      candidatePostimageCapturePolicy: capturePolicy
    )
    let outbox: WorkspaceMutationEffectOutbox
    do {
      outbox = try WorkspaceMutationEffectOutbox(
        rootDirectory: request.registration.outboxRoot,
        runID: request.registration.runID
      )
    } catch let error as WorkspaceMutationEffectOutboxError {
      throw
        WorkspaceCompletedCandidateMutationApplyPreparationError
        .outboxRejected(error)
    }
    let envelope: WorkspaceMutationEffectEnvelope
    do {
      envelope = try await outbox.enqueue(
        payload: .apply(executionRequest),
        startCommandID: request.startCommandID,
        recordCommandID: request.recordCommandID,
        releaseReceiptID: request.releaseReceiptID,
        releaseCommandID: request.releaseCommandID,
        failureReceiptID: request.failureReceiptID,
        failureCommandID: request.failureCommandID,
        enqueuedAt: request.issuedAt
      )
    } catch let error as WorkspaceMutationEffectOutboxError {
      throw
        WorkspaceCompletedCandidateMutationApplyPreparationError
        .outboxRejected(error)
    }
    guard case .accepted(let runtimeLease, _) = admission.runtimeAdmission.outcome
    else {
      throw WorkspaceCompletedCandidateMutationApplyPreparationError
        .leaseAdmissionRejected
    }
    let mutationRuntime = JournaledWorkspaceMutationRuntime(
      journal: journal,
      actorIdentity: request.registration.actorIdentity,
      authority: leaseAuthority,
      wallClock: wallClock,
      monotonicClock: monotonicClock
    )
    let applicationTerminationJoin =
      WorkspaceMutationApplicationTerminationJoin(
        journal: journal,
        supervisor: supervisor,
        outbox: outbox,
        dispatcher: JournaledWorkspaceMutationDispatcher(
          outbox: outbox,
          runtime: mutationRuntime,
          wallClock: wallClock
        ),
        runtimeLease: runtimeLease,
        envelope: envelope
      )
    return WorkspaceCompletedCandidateMutationApplyPreparationInstallation(
      preflight: preflight,
      leaseAdmission: admission,
      intent: intent,
      intentJournalTransaction: intentTransaction,
      effectEnvelope: envelope,
      applicationTerminationJoin: applicationTerminationJoin
    )
  }

  private func acceptedPreflight(
    _ installation: WorkspaceCompletedCandidateMutationPreflightInstallation
  ) async -> Bool {
    let authority = installation.authority
    let proposed = await journal.integrationTransitionEvent(
      transaction: installation.proposalJournalTransaction
    )
    let prepared = await journal.integrationTransitionEvent(
      transaction: installation.preflightJournalTransaction
    )
    return proposed == .proposed(authority.proposal)
      && prepared
        == .rollbackPrepared(
          receipt: authority.receipt,
          rollback: authority.rollback
        )
  }

  static func requestIdentityIsValid(
    _ request: WorkspaceCompletedCandidateMutationApplyPreparationRequest
  ) -> Bool {
    !request.leaseID.rawValue.isEmpty
      && !request.admissionReceiptID.rawValue.isEmpty
      && !request.admissionCommandID.rawValue.isEmpty
      && !request.intentID.rawValue.isEmpty
      && !request.intentCommandID.rawValue.isEmpty
      && !request.startCommandID.rawValue.isEmpty
      && !request.recordCommandID.rawValue.isEmpty
      && !request.releaseReceiptID.rawValue.isEmpty
      && !request.releaseCommandID.rawValue.isEmpty
      && !request.failureReceiptID.rawValue.isEmpty
      && !request.failureCommandID.rawValue.isEmpty
      && Set([
        request.admissionCommandID,
        request.intentCommandID,
        request.startCommandID,
        request.recordCommandID,
        request.releaseCommandID,
        request.failureCommandID,
      ]).count == 6
      && request.admissionReceiptID != request.releaseReceiptID
      && request.admissionReceiptID != request.failureReceiptID
      && request.releaseReceiptID != request.failureReceiptID
      && request.issuedAt >= request.preflight.authority.receipt.observedAt
      && request.expiresAt > request.issuedAt
      && request.expiresAtMonotonicNanoseconds > request.requestedAtMonotonicNanoseconds
      && request.executorLimits.maximumSnapshotFiles > 0
      && request.executorLimits.maximumSnapshotBytes > 0
      && request.executorLimits.maximumRecoveryBytes > 0
  }
}
