import CryptoKit
import Darwin
import Foundation

enum JournalDurability: String, Codable, Sendable {
  case buffered
  case boundary
}

enum RunJournalError: Error, Equatable {
  case writerPoisoned
  case writerLockFailed
  case writerStale(expectedSequence: UInt64, actualSequence: UInt64)
  case unresolvedTrailingFragment(bytes: Int)
  case runIdentityMismatch
  case invalidFrameEncoding(line: Int)
  case duplicateCommand(line: Int)
  case duplicateEvent(line: Int)
  case batchCommandConflict(commandID: RunCommandID)
  case gitPreimageCaptureCommandConflict(commandID: RunCommandID)
  case canonicalPreimageCommandConflict(commandID: RunCommandID)
  case preApplyCandidateIsolationCommandConflict(commandID: RunCommandID)
  case completedCandidateCaptureCommandConflict(commandID: RunCommandID)
  case completedCandidateCaptureAuthorityStale
  case completedCandidateMutationContentStoreCommandConflict(
    commandID: RunCommandID
  )
  case completedCandidateMutationContentStoreAuthorityStale
  case completedCandidateMutationManifestProposalCommandConflict(
    commandID: RunCommandID
  )
  case completedCandidateMutationManifestProposalAuthorityStale
  case completedCandidateMutationPreparationFactsCommandConflict(
    commandID: RunCommandID
  )
  case completedCandidateMutationPreparationFactsAuthorityStale
  case completedCandidateMutationRollbackRehearsalCommandConflict(
    commandID: RunCommandID
  )
  case completedCandidateMutationRollbackRehearsalAuthorityStale
  case preApplyCandidateIsolationAuthorityStale
  case preApplyCandidateIsolationEnrollmentFrameMismatch
  case baselineContentCaptureCommandConflict(commandID: RunCommandID)
  case candidateContentCaptureCommandConflict(commandID: RunCommandID)
  case candidateContentCaptureAuthorityStale
  case mutationContentStoreCommandConflict(commandID: RunCommandID)
  case mutationContentStoreAuthorityStale
  case nativeVisualEvaluationCommandConflict(commandID: RunCommandID)
  case completionAuthorizationCommandConflict(commandID: RunCommandID)
  case completionAuthorizationAuthorityStale
  case brokenHashChain(line: Int)
  case invalidEventSequence(line: Int)
  case reducerRejected(KernelRejection)
}

struct JournalRecoveryReport: Codable, Equatable, Sendable {
  var recoveredTransactions: Int
  var recoveredEvents: Int
  var ignoredTrailingBytes: Int
  var lastFrameDigest: ContentDigest?
}

struct JournalTransactionReceipt: Codable, Equatable, Sendable {
  var commandID: RunCommandID
  var startingSequence: UInt64
  var endingSequence: UInt64
  var eventIDs: [OrchestrationEventID]
  var frameDigest: ContentDigest
  var duplicate: Bool
}

struct JournalHeadSnapshot: Equatable, Sendable {
  var sequence: UInt64
  var frameDigest: ContentDigest?
}

struct JournalCommandEnvelope: Sendable {
  var command: RunCommand
  var context: KernelCommandContext
  var durability: JournalDurability = .boundary
}

private struct JournalTransactionFrame: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var runID: KernelRunID
  var commandID: RunCommandID
  var previousFrameDigest: ContentDigest?
  var events: [OrchestrationEvent]?
  var encodedEvents: Data?
  var frameDigest: ContentDigest
}

/// A single-writer, hash-chained journal. One command and all events emitted by
/// that command occupy one newline-delimited frame, so recovery either accepts
/// the complete transaction or ignores an uncommitted trailing fragment.
actor RunJournal {
  let runID: KernelRunID
  let runDirectory: URL
  let journalURL: URL

  private(set) var state: KernelRunState
  private(set) var recoveryReport: JournalRecoveryReport
  private var receipts: [RunCommandID: JournalTransactionReceipt]
  private var transactionEvents: [RunCommandID: [OrchestrationEvent]]
  private var lastFrameDigest: ContentDigest?
  private var writerPoisoned = false

  init(rootDirectory: URL, runID: KernelRunID) throws {
    self.runID = runID
    runDirectory = rootDirectory.appendingPathComponent(runID.rawValue, isDirectory: true)
    journalURL = runDirectory.appendingPathComponent("journal.ndjson")

    try FileManager.default.createDirectory(
      at: runDirectory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: runDirectory.path
    )
    let recovered = try Self.recover(journalURL: journalURL, runID: runID)
    state = recovered.state
    receipts = recovered.receipts
    transactionEvents = recovered.transactionEvents
    lastFrameDigest = recovered.report.lastFrameDigest
    recoveryReport = recovered.report
  }

  func transact(
    _ command: RunCommand,
    context: KernelCommandContext,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    guard !writerPoisoned else { throw RunJournalError.writerPoisoned }
    if var receipt = receipts[context.commandID] {
      receipt.duplicate = true
      return receipt
    }

    let decision = RunReducer.handle(state: state, command: command, context: context)
    guard case .accepted(let events, let nextState) = decision else {
      if case .rejected(let rejection) = decision {
        throw RunJournalError.reducerRejected(rejection)
      }
      preconditionFailure("ReducerDecision is exhaustive")
    }

    let encodedEvents = try Self.encodeEvents(events)
    let digest = try Self.frameDigestV2(
      runID: runID,
      commandID: context.commandID,
      previous: lastFrameDigest,
      encodedEvents: encodedEvents
    )
    let frame = JournalTransactionFrame(
      schemaVersion: 2,
      runID: runID,
      commandID: context.commandID,
      previousFrameDigest: lastFrameDigest,
      events: nil,
      encodedEvents: encodedEvents,
      frameDigest: digest
    )

    do {
      try append(frame: frame, durability: durability)
    } catch {
      writerPoisoned = true
      throw error
    }

    let receipt = JournalTransactionReceipt(
      commandID: context.commandID,
      startingSequence: events.first?.sequence ?? state.sequence,
      endingSequence: events.last?.sequence ?? state.sequence,
      eventIDs: events.map(\.id),
      frameDigest: digest,
      duplicate: false
    )
    state = nextState
    lastFrameDigest = digest
    receipts[context.commandID] = receipt
    transactionEvents[context.commandID] = events
    return receipt
  }

  /// Preflights an authority-preparation batch against one reducer snapshot,
  /// then appends it without actor reentrancy. A rejected later command can
  /// therefore never leave an earlier preparation frame behind. The batch
  /// contains no external effect; each accepted command remains its own
  /// hash-chained recovery frame.
  func transactBatch(
    _ envelopes: [JournalCommandEnvelope]
  ) throws -> [JournalTransactionReceipt] {
    guard !writerPoisoned else { throw RunJournalError.writerPoisoned }
    var commandIDs = Set<RunCommandID>()
    for envelope in envelopes {
      guard receipts[envelope.context.commandID] == nil,
        commandIDs.insert(envelope.context.commandID).inserted
      else {
        throw RunJournalError.batchCommandConflict(
          commandID: envelope.context.commandID
        )
      }
    }
    var preview = state
    for envelope in envelopes {
      let decision = RunReducer.handle(
        state: preview,
        command: envelope.command,
        context: envelope.context
      )
      guard case .accepted(_, let next) = decision else {
        if case .rejected(let rejection) = decision {
          throw RunJournalError.reducerRejected(rejection)
        }
        preconditionFailure("ReducerDecision is exhaustive")
      }
      preview = next
    }

    return try envelopes.map {
      try transact(
        $0.command,
        context: $0.context,
        durability: $0.durability
      )
    }
  }

  func currentProjection() -> KernelRunProjection {
    KernelRunProjection(state: state)
  }

  /// Exact reducer-owned contract for trusted composition boundaries. UI and
  /// legacy task state receive only `KernelRunProjection`; enrollment uses
  /// this narrower accessor to verify that an idempotent journal transaction
  /// did not resolve to a different pre-existing run contract.
  func currentContract() -> TaskContract? {
    state.contract
  }

  func currentConvergenceGovernor() -> ConvergenceGovernor? {
    state.convergenceGovernor
  }

  /// Accepts only the non-Codable authority composed from live native
  /// capture, deterministic measurement, and independent-review evidence.
  /// Exact duplicate delivery returns the retained transaction only when
  /// every bound authority field and candidate byte identity are unchanged.
  func recordNativeVisualEvaluation(
    _ authority: AuthorizedKernelVisualEvaluation,
    commandID: RunCommandID,
    evaluatedAt: Date,
    evaluator: ActorIdentity,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .visualCandidateEvaluated(
          let candidate,
          let receipt
        ) = event.payload,
        candidate == authority.candidate,
        receipt.id == authority.receiptID,
        receipt.attemptID == authority.attemptID,
        receipt.requirementIDs == authority.requirementIDs,
        receipt.evaluator == evaluator,
        receipt.nativeReviewRequestDigest == authority.nativeReviewRequestDigest,
        receipt.nativeCaptureAttestationDigests == authority.nativeCaptureAttestationDigests,
        receipt.nativeMeasurementAttestationDigests
          == authority.nativeMeasurementAttestationDigests,
        receipt.nativeReviewCompletedAt == authority.nativeReviewCompletedAt
      else {
        throw RunJournalError.nativeVisualEvaluationCommandConflict(
          commandID: commandID
        )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .evaluateVisualCandidate(authority),
      commandID: commandID,
      issuedAt: evaluatedAt,
      actor: evaluator,
      durability: durability
    )
  }

  func nativeVisualEvaluationReceipt(
    commandID: RunCommandID
  ) -> VisualGateEvaluationReceipt? {
    guard let transaction = receipts[commandID],
      let event = exactSingleEvent(transaction: transaction),
      case .visualCandidateEvaluated(_, let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func nativeVisualEvaluationReceipt(
    transaction: JournalTransactionReceipt
  ) -> VisualGateEvaluationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .visualCandidateEvaluated(_, let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  /// Accepts only the non-Codable authority composed against the exact
  /// completion-requested hash-journal head. Duplicate delivery is valid
  /// only when both retained completion events and every receipt field are
  /// identical.
  func recordCompletionAuthorization(
    _ authority: AuthorizedKernelCompletion,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let receipt = authority.receipt
    if var retained = receipts[receipt.commandID] {
      guard let events = exactEvents(transaction: retained),
        events.count == 2,
        case .completionAuthorizationRecorded(let recorded) =
          events[0].payload,
        case .completionAuthorized = events[1].payload,
        recorded == receipt
      else {
        throw
          RunJournalError
          .completionAuthorizationCommandConflict(
            commandID: receipt.commandID
          )
      }
      retained.duplicate = true
      return retained
    }
    guard state.phase == .completionRequested,
      state.sequence == receipt.sourceSequence,
      lastFrameDigest == receipt.sourceFrameDigest,
      latestEventOccurredAt() == receipt.sourceOccurredAt
    else {
      throw RunJournalError.completionAuthorizationAuthorityStale
    }
    return try transactAtCurrentSequence(
      .authorizeCompletion(authority),
      commandID: receipt.commandID,
      issuedAt: receipt.authorizedAt,
      actor: receipt.authorizer,
      durability: durability
    )
  }

  func completionAuthorizationReceipt()
    -> KernelCompletionAuthorizationReceipt?
  {
    state.completionAuthorizationReceipt
  }

  func completionAuthorizationTransaction(
    commandID: RunCommandID
  ) -> JournalTransactionReceipt? {
    guard let retained = receipts[commandID],
      let events = exactEvents(transaction: retained),
      events.count == 2,
      case .completionAuthorizationRecorded(let receipt) =
        events[0].payload,
      case .completionAuthorized = events[1].payload,
      receipt == state.completionAuthorizationReceipt
    else {
      return nil
    }
    return retained
  }

  /// Accepts only the non-Codable capability minted after one stable,
  /// read-only three-plane observation. Exact replay compares the retained
  /// receipt and never reruns Git or infers empty planes.
  func recordJournaledGitPreimageCapture(
    _ authority: AuthorizedWorkspaceJournaledGitPreimageCapture,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .journaledGitPreimageCaptured(let receipt) =
          event.payload,
        receipt == authority.receipt
      else {
        throw RunJournalError.gitPreimageCaptureCommandConflict(
          commandID: commandID
        )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .recordJournaledGitPreimageCapture(authority),
      commandID: commandID,
      issuedAt: authority.receipt.capturedAt,
      actor: authority.receipt.captureActor,
      durability: durability
    )
  }

  func journaledGitPreimageCaptureReceipt()
    -> WorkspaceJournaledGitPreimageCaptureReceipt?
  {
    state.journaledGitPreimageCaptureReceipt
  }

  func journaledGitPreimageCaptureReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceJournaledGitPreimageCaptureReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .journaledGitPreimageCaptured(let receipt) = event.payload
    else { return nil }
    return receipt
  }

  /// Persists only the inert receipt assembled by the live, stable
  /// repository observer. Recovery never reconstructs its capability and
  /// therefore cannot mint preflight or write authority.
  func recordJournaledCanonicalPreimage(
    _ authority: AuthorizedWorkspaceJournaledCanonicalPreimage,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .journaledCanonicalPreimageCaptured(let receipt) =
          event.payload,
        receipt == authority.receipt
      else {
        throw RunJournalError.canonicalPreimageCommandConflict(
          commandID: commandID
        )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .recordJournaledCanonicalPreimage(authority),
      commandID: commandID,
      issuedAt: authority.receipt.capturedAt,
      actor: authority.receipt.captureActor,
      durability: durability
    )
  }

  func journaledCanonicalPreimageReceipt()
    -> WorkspaceJournaledCanonicalPreimageReceipt?
  {
    state.journaledCanonicalPreimageReceipt
  }

  func journaledCanonicalPreimageReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceJournaledCanonicalPreimageReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .journaledCanonicalPreimageCaptured(let receipt) =
        event.payload
    else { return nil }
    return receipt
  }

  /// Accepts only the live, non-Codable capability minted by the ratified
  /// baseline capture issuer. The journal derives actor and time from that
  /// capability, preventing callers from rebinding an otherwise valid
  /// capture receipt to a different command context.
  func recordRatifiedBaselineContentCapture(
    _ authority: AuthorizedWorkspaceRatifiedBaselineContent,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let transaction = try transactAtCurrentSequence(
      .recordRatifiedBaselineContentCapture(authority),
      commandID: commandID,
      issuedAt: authority.receipt.capturedAt,
      actor: authority.receipt.captureActor,
      durability: durability
    )
    if transaction.duplicate {
      guard let retained = receipts[commandID],
        let event = exactSingleEvent(transaction: retained),
        case .ratifiedBaselineContentCaptured(let receipt) = event.payload,
        receipt == authority.receipt
      else {
        throw RunJournalError.baselineContentCaptureCommandConflict(
          commandID: commandID
        )
      }
    }
    return transaction
  }

  func ratifiedBaselineContentCaptureReceipt(
    derivationDigest: ContentDigest
  ) -> WorkspaceRatifiedBaselineContentCaptureReceipt? {
    state.ratifiedBaselineContentCaptureReceipts?[derivationDigest]
  }

  func ratifiedBaselineContentCaptureReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceRatifiedBaselineContentCaptureReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .ratifiedBaselineContentCaptured(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  /// Revalidates the held no-follow root descriptor and complete pristine
  /// tree before even resolving a duplicate command. First acceptance is
  /// additionally pinned to the current enrollment frame. Only the inert
  /// self-digested receipt enters the journal; replay cannot recreate the
  /// live descriptor or process authority.
  func recordPreApplyCandidateIsolation(
    _ authority: AuthorizedWorkspacePreApplyCandidateIsolation,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let observed: WorkspacePreApplyCandidateIsolationReceipt
    do {
      observed = try WorkspaceCandidatePostimageMaterializer()
        .revalidatePreApplyIsolation(authority)
    } catch {
      throw RunJournalError.preApplyCandidateIsolationAuthorityStale
    }
    guard observed == authority.receipt else {
      throw RunJournalError.preApplyCandidateIsolationAuthorityStale
    }
    let expectedParent =
      WorkspaceCandidatePostimageMaterializer
      .preApplyCandidateParent(forJournalRunDirectory: runDirectory)
      .standardizedFileURL.path + "/"
    guard observed.candidateRootPath.hasPrefix(expectedParent) else {
      throw RunJournalError.preApplyCandidateIsolationAuthorityStale
    }
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .preApplyCandidateIsolationRecorded(let receipt) =
          event.payload,
        receipt == observed
      else {
        throw
          RunJournalError
          .preApplyCandidateIsolationCommandConflict(
            commandID: commandID
          )
      }
      retained.duplicate = true
      return retained
    }
    guard observed.enrollmentJournalFrameDigest == lastFrameDigest else {
      throw RunJournalError
        .preApplyCandidateIsolationEnrollmentFrameMismatch
    }
    return try transactAtCurrentSequence(
      .recordPreApplyCandidateIsolation(authority),
      commandID: commandID,
      issuedAt: observed.isolatedAt,
      actor: observed.isolationActor,
      durability: durability
    )
  }

  func preApplyCandidateIsolationReceipt(
    attemptID: AttemptID
  ) -> WorkspacePreApplyCandidateIsolationReceipt? {
    state.preApplyCandidateIsolationReceipts?[attemptID]
  }

  func preApplyCandidateIsolationReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspacePreApplyCandidateIsolationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .preApplyCandidateIsolationRecorded(let receipt) =
        event.payload
    else { return nil }
    return receipt
  }

  /// Accepts only the non-serializable bytes capability whose release,
  /// parse, and execution frame digests resolve to exact recovered events.
  /// Bytes do not enter the journal; the content-complete logical revision
  /// and physical candidate identity do.
  func recordCompletedCandidateCapture(
    _ authority: AuthorizedWorkspaceCompletedCandidateCapture,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let receipt = authority.receipt
    guard authority.validationIssues().isEmpty,
      runtimeReleaseReceipt(receiptID: receipt.releaseReceiptID) != nil,
      workerResultParseReceipt(receiptID: receipt.parseReceiptID) != nil,
      executionDerivationReceipt(
        receiptID: receipt.executionReceiptID
      ) != nil,
      exactFrameDigest(for: receipt.releaseReceiptID) == receipt.releaseJournalFrameDigest,
      exactFrameDigest(for: receipt.parseReceiptID) == receipt.parseJournalFrameDigest,
      exactFrameDigest(for: receipt.executionReceiptID) == receipt.executionJournalFrameDigest
    else {
      throw RunJournalError.completedCandidateCaptureAuthorityStale
    }
    let transaction = try transactAtCurrentSequence(
      .recordCompletedCandidateCapture(authority),
      commandID: commandID,
      issuedAt: receipt.capturedAt,
      actor: receipt.captureActor,
      durability: durability
    )
    if transaction.duplicate {
      guard let retained = receipts[commandID],
        let event = exactSingleEvent(transaction: retained),
        case .completedCandidateCaptured(let recorded) = event.payload,
        recorded == receipt
      else {
        throw RunJournalError.completedCandidateCaptureCommandConflict(
          commandID: commandID
        )
      }
    }
    return transaction
  }

  func completedCandidateCaptureReceipt(
    attemptID: AttemptID
  ) -> WorkspaceCompletedCandidateCaptureReceipt? {
    state.completedCandidateCaptureReceipts?[attemptID]
  }

  func completedCandidateCaptureReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceCompletedCandidateCaptureReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .completedCandidateCaptured(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  /// Revalidates the external artifact and both live byte origins before one
  /// inert preflight-side store receipt enters the hash journal. Exact replay
  /// cannot reconstruct either byte capability.
  func recordCompletedCandidateMutationContentStore(
    _ authority:
      AuthorizedWorkspaceCompletedCandidateMutationContentStore,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    guard authority.journalValidationIssues().isEmpty,
      authority.externalArtifactValidationIssues().isEmpty,
      completedCandidateCaptureReceipt(
        attemptID: authority.receipt.attemptID
      ) == authority.completedCandidate.receipt,
      exactCompletedCandidateCaptureFrameDigest(
        attemptID: authority.receipt.attemptID
      )
        == authority.receipt
        .completedCandidateCaptureJournalFrameDigest,
      ratifiedBaselineContentCaptureReceipt(
        derivationDigest: authority.receipt.derivationDigest
      ) == authority.baseline.receipt
    else {
      throw RunJournalError
        .completedCandidateMutationContentStoreAuthorityStale
    }
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .completedCandidateMutationContentStored(let receipt) =
          event.payload,
        receipt == authority.receipt
      else {
        throw
          RunJournalError
          .completedCandidateMutationContentStoreCommandConflict(
            commandID: commandID
          )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .recordCompletedCandidateMutationContentStore(authority),
      commandID: commandID,
      issuedAt: authority.receipt.storedAt,
      actor: authority.receipt.storedBy,
      durability: durability
    )
  }

  func completedCandidateMutationContentStoreReceipt(
    derivationDigest: ContentDigest
  ) -> WorkspaceCompletedCandidateMutationContentStoreReceipt? {
    state.completedCandidateMutationContentStoreReceipts?[derivationDigest]
  }

  func completedCandidateMutationContentStoreReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceCompletedCandidateMutationContentStoreReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .completedCandidateMutationContentStored(let receipt) =
        event.payload
    else { return nil }
    return receipt
  }

  /// Revalidates both live origins and requires their exact recovered journal
  /// frames before accepting an inert manifest proposal. No preparation or
  /// mutation authority is minted by this journal transaction.
  func recordCompletedCandidateMutationManifestProposal(
    _ authority:
      AuthorizedWorkspaceCompletedCandidateMutationManifestProposal,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let receipt = authority.receipt
    guard authority.journalValidationIssues().isEmpty,
      authority.externalArtifactValidationIssues().isEmpty,
      completedCandidateMutationContentStoreReceipt(
        derivationDigest:
          authority.contentStore.receipt.derivationDigest
      ) == authority.contentStore.receipt,
      exactCompletedCandidateMutationContentStoreFrameDigest(
        derivationDigest:
          authority.contentStore.receipt.derivationDigest
      )
        == receipt
        .completedCandidateContentStoreJournalFrameDigest,
      journaledCanonicalPreimageReceipt() == authority.canonicalPreimage.receipt,
      exactCanonicalPreimageFrameDigest() == receipt.canonicalPreimageJournalFrameDigest
    else {
      throw RunJournalError
        .completedCandidateMutationManifestProposalAuthorityStale
    }
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .completedCandidateMutationManifestProposed(
          let recorded
        ) = event.payload,
        recorded == receipt
      else {
        throw
          RunJournalError
          .completedCandidateMutationManifestProposalCommandConflict(
            commandID: commandID
          )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .recordCompletedCandidateMutationManifestProposal(authority),
      commandID: commandID,
      issuedAt: receipt.proposedAt,
      actor: receipt.proposedBy,
      durability: durability
    )
  }

  func completedCandidateMutationManifestProposalReceipt(
    derivationDigest: ContentDigest
  ) -> WorkspaceCompletedCandidateMutationManifestProposalReceipt? {
    state.completedCandidateMutationManifestProposalReceipts?[
      derivationDigest
    ]
  }

  func completedCandidateMutationManifestProposalReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceCompletedCandidateMutationManifestProposalReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .completedCandidateMutationManifestProposed(let receipt) =
        event.payload
    else { return nil }
    return receipt
  }

  /// Journals only the inert preparation facts after revalidating the exact
  /// proposal and candidate-release frames. No rollback or mutation
  /// authority is reconstructed here.
  func recordCompletedCandidateMutationPreparationFacts(
    _ authority:
      AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let receipt = authority.receipt
    guard authority.journalValidationIssues().isEmpty,
      authority.externalArtifactValidationIssues().isEmpty,
      completedCandidateMutationManifestProposalReceipt(
        derivationDigest: authority.proposal.contentStore.receipt
          .derivationDigest
      ) == authority.proposal.receipt,
      exactCompletedCandidateMutationManifestProposalFrameDigest(
        receiptDigest: authority.proposal.receipt.receiptDigest
      ) == receipt.proposalJournalFrameDigest,
      runtimeReleaseReceipt(
        receiptID: receipt.candidateReleaseReceiptID
      ) != nil,
      exactFrameDigest(for: receipt.candidateReleaseReceiptID)
        == receipt.candidateReleaseJournalFrameDigest
    else {
      throw RunJournalError
        .completedCandidateMutationPreparationFactsAuthorityStale
    }
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .completedCandidateMutationPreparationFactsRecorded(
          let recorded
        ) = event.payload,
        recorded == receipt
      else {
        throw
          RunJournalError
          .completedCandidateMutationPreparationFactsCommandConflict(
            commandID: commandID
          )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .recordCompletedCandidateMutationPreparationFacts(authority),
      commandID: commandID,
      issuedAt: receipt.preparedAt,
      actor: receipt.preparedBy,
      durability: durability
    )
  }

  func completedCandidateMutationPreparationFactsReceipt(
    proposalReceiptDigest: ContentDigest
  ) -> WorkspaceCompletedCandidateMutationPreparationFactsReceipt? {
    state.completedCandidateMutationPreparationFactsReceipts?[
      proposalReceiptDigest
    ]
  }

  func completedCandidateMutationPreparationFactsReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceCompletedCandidateMutationPreparationFactsReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .completedCandidateMutationPreparationFactsRecorded(
        let receipt
      ) = event.payload
    else { return nil }
    return receipt
  }

  /// Accepts only an exact live, externally revalidated owner-private
  /// rehearsal whose canonical affected paths remain byte/mode identical.
  func recordCompletedCandidateMutationRollbackRehearsal(
    _ authority:
      AuthorizedWorkspaceCompletedCandidateMutationRollbackRehearsal,
    canonicalWorkspaceRoot: URL,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    let receipt = authority.receipt
    do {
      try WorkspaceCompletedCandidateMutationPreparationFactsCoordinator
        .revalidateCanonicalWorkspace(
          preparation: authority.preparation.receipt,
          proposal: authority.preparation.proposal.receipt,
          canonicalWorkspaceRoot: canonicalWorkspaceRoot
        )
    } catch {
      throw RunJournalError
        .completedCandidateMutationRollbackRehearsalAuthorityStale
    }
    guard authority.journalValidationIssues().isEmpty,
      authority.externalArtifactValidationIssues().isEmpty,
      completedCandidateMutationPreparationFactsReceipt(
        proposalReceiptDigest: receipt.proposalReceiptDigest
      ) == authority.preparation.receipt,
      exactCompletedCandidateMutationPreparationFactsFrameDigest(
        proposalReceiptDigest: receipt.proposalReceiptDigest
      ) == receipt.preparationFactsJournalFrameDigest
    else {
      throw RunJournalError
        .completedCandidateMutationRollbackRehearsalAuthorityStale
    }
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .completedCandidateMutationRollbackRehearsed(
          let recorded
        ) = event.payload,
        recorded == receipt
      else {
        throw
          RunJournalError
          .completedCandidateMutationRollbackRehearsalCommandConflict(
            commandID: commandID
          )
      }
      retained.duplicate = true
      return retained
    }
    return try transactAtCurrentSequence(
      .recordCompletedCandidateMutationRollbackRehearsal(
        WorkspaceCompletedCandidateMutationRollbackRehearsalAuthorityBox(
          authority
        )
      ),
      commandID: commandID,
      issuedAt: receipt.rehearsedAt,
      actor: receipt.rehearsedBy,
      durability: durability
    )
  }

  func completedCandidateMutationRollbackRehearsalReceipt(
    proposalReceiptDigest: ContentDigest
  ) -> WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt? {
    state.completedCandidateMutationRollbackRehearsalReceipts?[
      proposalReceiptDigest
    ]
  }

  func completedCandidateMutationRollbackRehearsalReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceCompletedCandidateMutationRollbackRehearsalReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .completedCandidateMutationRollbackRehearsed(let receipt) =
        event.payload
    else { return nil }
    return receipt
  }

  private func exactCompletedCandidateCaptureFrameDigest(
    attemptID: AttemptID
  ) -> ContentDigest? {
    let matches = transactionEvents.compactMap {
      commandID,
      events -> ContentDigest? in
      guard events.count == 1,
        let event = events.first,
        case .completedCandidateCaptured(let receipt) = event.payload,
        receipt.attemptID == attemptID,
        let transaction = receipts[commandID],
        transaction.eventIDs == [event.id],
        transaction.startingSequence == event.sequence,
        transaction.endingSequence == event.sequence
      else {
        return nil
      }
      return transaction.frameDigest
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func exactCompletedCandidateMutationContentStoreFrameDigest(
    derivationDigest: ContentDigest
  ) -> ContentDigest? {
    let matches = transactionEvents.compactMap {
      commandID,
      events -> ContentDigest? in
      guard events.count == 1,
        let event = events.first,
        case .completedCandidateMutationContentStored(let receipt) =
          event.payload,
        receipt.derivationDigest == derivationDigest,
        let transaction = receipts[commandID],
        transaction.eventIDs == [event.id],
        transaction.startingSequence == event.sequence,
        transaction.endingSequence == event.sequence
      else {
        return nil
      }
      return transaction.frameDigest
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func exactCompletedCandidateMutationManifestProposalFrameDigest(
    receiptDigest: ContentDigest
  ) -> ContentDigest? {
    let matches = transactionEvents.compactMap {
      commandID,
      events -> ContentDigest? in
      guard events.count == 1,
        let event = events.first,
        case .completedCandidateMutationManifestProposed(
          let receipt
        ) = event.payload,
        receipt.receiptDigest == receiptDigest,
        let transaction = receipts[commandID],
        transaction.eventIDs == [event.id],
        transaction.startingSequence == event.sequence,
        transaction.endingSequence == event.sequence
      else {
        return nil
      }
      return transaction.frameDigest
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func exactCompletedCandidateMutationPreparationFactsFrameDigest(
    proposalReceiptDigest: ContentDigest
  ) -> ContentDigest? {
    let matches = transactionEvents.compactMap {
      commandID,
      events -> ContentDigest? in
      guard events.count == 1,
        let event = events.first,
        case .completedCandidateMutationPreparationFactsRecorded(
          let receipt
        ) = event.payload,
        receipt.proposalReceiptDigest == proposalReceiptDigest,
        let transaction = receipts[commandID],
        transaction.eventIDs == [event.id],
        transaction.startingSequence == event.sequence,
        transaction.endingSequence == event.sequence
      else {
        return nil
      }
      return transaction.frameDigest
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func exactCanonicalPreimageFrameDigest() -> ContentDigest? {
    let matches = transactionEvents.compactMap {
      commandID,
      events -> ContentDigest? in
      guard events.count == 1,
        let event = events.first,
        case .journaledCanonicalPreimageCaptured = event.payload,
        let transaction = receipts[commandID],
        transaction.eventIDs == [event.id],
        transaction.startingSequence == event.sequence,
        transaction.endingSequence == event.sequence
      else {
        return nil
      }
      return transaction.frameDigest
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  /// Rechecks latest-transition authority immediately before append. Exact
  /// command replay is receipt-only; candidate bytes and descriptors are
  /// deliberately absent from the journal and recovered state.
  func recordJournaledCandidateContentCapture(
    _ authority: AuthorizedWorkspaceJournaledCandidateContent,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    guard
      isLatestAcceptedCandidatePostimageAttestation(
        authority.attestation
      )
    else {
      throw RunJournalError.candidateContentCaptureAuthorityStale
    }
    let transaction = try transactAtCurrentSequence(
      .recordJournaledCandidateContentCapture(authority),
      commandID: commandID,
      issuedAt: authority.receipt.capturedAt,
      actor: authority.receipt.captureActor,
      durability: durability
    )
    if transaction.duplicate {
      guard let retained = receipts[commandID],
        let event = exactSingleEvent(transaction: retained),
        case .journaledCandidateContentCaptured(let receipt) =
          event.payload,
        receipt == authority.receipt
      else {
        throw RunJournalError.candidateContentCaptureCommandConflict(
          commandID: commandID
        )
      }
    }
    return transaction
  }

  func journaledCandidateContentCaptureReceipt(
    derivationDigest: ContentDigest
  ) -> WorkspaceJournaledCandidateContentCaptureReceipt? {
    state.journaledCandidateContentCaptureReceipts?[derivationDigest]
  }

  func journaledCandidateContentCaptureReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceJournaledCandidateContentCaptureReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .journaledCandidateContentCaptured(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  /// Revalidates the external immutable artifact and latest candidate
  /// transition immediately before append. Exact command replay compares the
  /// inert receipt only; neither bytes nor opaque transition authority enter
  /// the journal.
  func recordJournaledMutationContentStore(
    _ authority: AuthorizedWorkspaceJournaledMutationContentStore,
    commandID: RunCommandID,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    if var retained = receipts[commandID] {
      guard let event = exactSingleEvent(transaction: retained),
        case .journaledMutationContentStored(let receipt) =
          event.payload,
        receipt == authority.receipt
      else {
        throw RunJournalError.mutationContentStoreCommandConflict(
          commandID: commandID
        )
      }
      retained.duplicate = true
      return retained
    }
    guard authority.externalArtifactValidationIssues().isEmpty else {
      throw RunJournalError.reducerRejected(
        .invalidMutationContentStore(
          "the external mutation-content store failed immediate revalidation"
        ))
    }
    guard
      isLatestAcceptedCandidatePostimageAttestation(
        authority.composition.candidateAttestation
      )
    else {
      throw RunJournalError.mutationContentStoreAuthorityStale
    }
    let transaction = try transactAtCurrentSequence(
      .recordJournaledMutationContentStore(authority),
      commandID: commandID,
      issuedAt: authority.receipt.storedAt,
      actor: authority.receipt.storedBy,
      durability: durability
    )
    return transaction
  }

  func journaledMutationContentStoreReceipt(
    derivationDigest: ContentDigest
  ) -> WorkspaceJournaledMutationContentStoreReceipt? {
    state.journaledMutationContentStoreReceipts?[derivationDigest]
  }

  func journaledMutationContentStoreReceipt(
    transaction: JournalTransactionReceipt
  ) -> WorkspaceJournaledMutationContentStoreReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .journaledMutationContentStored(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  /// Projects only transaction IDs whose hash-chained event records an
  /// accepted causal progress evaluation. An occurrence cannot turn Agent
  /// success prose, an arbitrary evidence ID, or a rejected evaluation into
  /// accepted-active duration.
  func acceptedCausalProgressReceiptIDs() -> Set<ReceiptID> {
    state.acceptedProgressReceiptIDs
  }

  /// Projects every typed causal-progress transaction, including stagnant
  /// evaluations. Occurrence provenance may bind only to this set, while
  /// accepted duration remains restricted to the accepted subset above.
  func causalProgressReceiptIDs() -> Set<ReceiptID> {
    state.causalProgressReceiptIDs
  }

  /// Projects closed accepted duration from the same hash-journal state used
  /// for convergence and completion. Mutable legacy counters never enter
  /// this calculation.
  func currentDurationCoverage() -> CoverageProjection? {
    state.durationCoverage
  }

  func runtimeLease(resourceID: OwnedResourceID) -> RuntimeResourceLease? {
    state.runtimeLiveLeases[resourceID]
  }

  func runtimeAdmissionReceipt(receiptID: ReceiptID) -> RuntimeAdmissionReceipt? {
    state.runtimeAdmissionReceipts[receiptID]
  }

  /// Resolves a runtime receipt only when the supplied transaction is the
  /// exact hash-journal frame that published that typed event.
  func runtimeAdmissionReceipt(
    transaction: JournalTransactionReceipt
  ) -> RuntimeAdmissionReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .runtimeAdmissionRecorded(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func runtimeBindingReceipt(
    receiptID: ReceiptID
  ) -> RuntimeExternalBindingReceipt? {
    state.runtimeBindingReceipts[receiptID]
  }

  func runtimeBindingReceipt(
    transaction: JournalTransactionReceipt
  ) -> RuntimeExternalBindingReceipt? {
    let matches =
      exactEvents(transaction: transaction)?.compactMap {
        event -> RuntimeExternalBindingReceipt? in
        guard case .runtimeBindingRecorded(let receipt) = event.payload else {
          return nil
        }
        return receipt
      } ?? []
    guard matches.count == 1 else {
      return nil
    }
    return matches[0]
  }

  func providerLaunchReceipt(
    receiptID: ReceiptID
  ) -> KernelProviderLaunchReceipt? {
    state.providerLaunchReceipts?[receiptID]
  }

  func providerLaunchReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelProviderLaunchReceipt? {
    let matches =
      exactEvents(transaction: transaction)?.compactMap {
        event -> KernelProviderLaunchReceipt? in
        guard case .providerLaunchRecorded(let receipt) = event.payload else {
          return nil
        }
        return receipt
      } ?? []
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  func runtimeReleaseReceipt(
    receiptID: ReceiptID
  ) -> RuntimeReleaseOutcomeReceipt? {
    state.runtimeReleaseReceipts[receiptID]
  }

  /// Exposes only the recovered hash-chain frame for a typed release. The
  /// journal keeps the general frame resolver private so callers cannot use
  /// arbitrary receipt-shaped identifiers as provenance.
  func runtimeReleaseFrameDigest(
    receiptID: ReceiptID
  ) -> ContentDigest? {
    guard state.runtimeReleaseReceipts[receiptID] != nil else { return nil }
    return exactFrameDigest(for: receiptID)
  }

  func runtimeReleaseReceipt(
    transaction: JournalTransactionReceipt
  ) -> RuntimeReleaseOutcomeReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .runtimeReleaseRecorded(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func verificationReceipt(
    transaction: JournalTransactionReceipt
  ) -> VerificationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .verificationRecorded(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func independentReviewReceipt(
    transaction: JournalTransactionReceipt
  ) -> IndependentReviewReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .reviewRecorded(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func integrationTransitionEvent(
    transaction: JournalTransactionReceipt
  ) -> IntegrationTransitionEvent? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .integrationAdvanced(let transition) = event.payload
    else {
      return nil
    }
    return transition
  }

  func workerResultParseReceipt(
    receiptID: ReceiptID
  ) -> KernelWorkerResultParseReceipt? {
    state.workerResultParseReceipts?[receiptID]
  }

  func workerResultParseReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelWorkerResultParseReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .workerResultParsed(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func executionDerivationReceipt(
    receiptID: ReceiptID
  ) -> KernelExecutionDerivationReceipt? {
    state.executionDerivationReceipts?[receiptID]
  }

  func executionDerivationReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelExecutionDerivationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .executionDerived(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func externalDependencyObservationActivationReceipt(
    transaction: JournalTransactionReceipt
  ) -> ExternalDependencyObservationActivationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .externalDependencyObservationActivated(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  func externalDependencyObservationLaunchVetoReceipt(
    transaction: JournalTransactionReceipt
  ) -> ExternalDependencyObservationLaunchVetoReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .externalDependencyObservationLaunchVetoed(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  func externalDependencyObservationRuntimeLaunchReceipt(
    receiptID: ReceiptID
  ) -> ExternalDependencyObservationRuntimeLaunchReceipt? {
    state.externalDependencyObservationRuntimeLaunchReceipts?[receiptID]
  }

  func externalDependencyObservationRuntimeLaunchReceipt(
    transaction: JournalTransactionReceipt
  ) -> ExternalDependencyObservationRuntimeLaunchReceipt? {
    let matches =
      exactEvents(transaction: transaction)?.compactMap {
        event -> ExternalDependencyObservationRuntimeLaunchReceipt? in
        guard
          case .externalDependencyObservationRuntimeLaunched(
            let receipt
          ) = event.payload
        else {
          return nil
        }
        return receipt
      } ?? []
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  func externalDependencyObservationReceipt(
    transaction: JournalTransactionReceipt
  ) -> ExternalDependencyObservationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .externalDependencyObservationRecorded(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  func postimageVerifierActivationReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelPostimageVerifierActivationReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .postimageVerifierActivated(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func postimageVerifierLaunchReceipt(
    receiptID: ReceiptID
  ) -> KernelPostimageVerifierLaunchReceipt? {
    state.postimageVerifierLaunchReceipts?[receiptID]
  }

  func postimageVerifierLaunchReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelPostimageVerifierLaunchReceipt? {
    let matches =
      exactEvents(transaction: transaction)?.compactMap {
        event -> KernelPostimageVerifierLaunchReceipt? in
        guard case .postimageVerifierLaunched(let receipt) = event.payload else {
          return nil
        }
        return receipt
      } ?? []
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  func postimageVerifierLaunchVetoReceipt(
    receiptID: ReceiptID
  ) -> KernelPostimageVerifierLaunchVetoReceipt? {
    state.postimageVerifierLaunchVetoReceipts?[receiptID]
  }

  func postimageVerifierLaunchVetoReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelPostimageVerifierLaunchVetoReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .postimageVerifierLaunchVetoed(let receipt) =
        event.payload
    else {
      return nil
    }
    return receipt
  }

  func productionMutationApplyVetoReceipt(
    receiptID: ReceiptID
  ) -> KernelProductionMutationApplyVetoReceipt? {
    state.productionMutationApplyVetoReceipts?[receiptID]
  }

  func productionMutationApplyVetoReceipt(
    transaction: JournalTransactionReceipt
  ) -> KernelProductionMutationApplyVetoReceipt? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .productionMutationApplyVetoed(let receipt) = event.payload
    else {
      return nil
    }
    return receipt
  }

  func headSnapshot() -> JournalHeadSnapshot {
    JournalHeadSnapshot(
      sequence: state.sequence,
      frameDigest: lastFrameDigest
    )
  }

  func latestEventOccurredAt() -> Date? {
    transactionEvents.values
      .flatMap { $0 }
      .max { $0.sequence < $1.sequence }?
      .occurredAt
  }

  func transactionReceipt(commandID: RunCommandID) -> JournalTransactionReceipt? {
    receipts[commandID]
  }

  func attemptStart(
    transaction: JournalTransactionReceipt
  ) -> KernelAttemptState? {
    guard let event = exactSingleEvent(transaction: transaction),
      case .attemptStarted(let attempt) = event.payload
    else {
      return nil
    }
    return attempt
  }

  private func exactSingleEvent(
    transaction: JournalTransactionReceipt
  ) -> OrchestrationEvent? {
    guard let events = exactEvents(transaction: transaction),
      events.count == 1
    else { return nil }
    return events[0]
  }

  private func exactFrameDigest(
    for receiptID: ReceiptID
  ) -> ContentDigest? {
    let matches = transactionEvents.compactMap {
      commandID,
      events -> ContentDigest? in
      guard events.count == 1,
        let event = events.first,
        eventCarriesReceiptID(event.payload, receiptID: receiptID),
        let transaction = receipts[commandID],
        transaction.eventIDs == events.map(\.id),
        transaction.startingSequence == event.sequence,
        transaction.endingSequence == event.sequence
      else {
        return nil
      }
      return transaction.frameDigest
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func eventCarriesReceiptID(
    _ payload: OrchestrationEventPayload,
    receiptID: ReceiptID
  ) -> Bool {
    switch payload {
    case .runtimeReleaseRecorded(let receipt):
      return receipt.id == receiptID
    case .workerResultParsed(let receipt):
      return receipt.id == receiptID
    case .executionDerived(let receipt):
      return receipt.id == receiptID
    default:
      return false
    }
  }

  private func exactEvents(
    transaction: JournalTransactionReceipt
  ) -> [OrchestrationEvent]? {
    guard !transaction.duplicate,
      receipts[transaction.commandID] == transaction,
      let events = transactionEvents[transaction.commandID],
      transaction.eventIDs == events.map(\.id),
      transaction.startingSequence == events.first?.sequence,
      transaction.endingSequence == events.last?.sequence,
      !events.isEmpty
    else { return nil }
    return events
  }

  /// Returns only reducer-accepted workspace generations whose exact event
  /// payload and transaction frame survived journal recovery. This is the
  /// authority boundary used by the repository index; callers cannot turn a
  /// well-shaped but unrelated JournalTransactionReceipt into a generation.
  func acceptedWorkspaceTreeGenerationEvent(
    transactionID: IntegrationTransactionID,
    authority: WorkspaceTreeGenerationAuthority
  ) -> AcceptedWorkspaceTreeGenerationEvent? {
    guard let projected = state.integrationTransactions[transactionID] else {
      return nil
    }
    let candidates = transactionEvents.compactMap {
      commandID,
      events -> AcceptedWorkspaceTreeGenerationEvent? in
      guard let transaction = receipts[commandID],
        transaction.eventIDs == events.map(\.id),
        transaction.endingSequence >= transaction.startingSequence,
        events.count == 1,
        let event = events.first
      else {
        return nil
      }
      let generationDigest: ContentDigest
      let candidatePostimage: WorkspaceSourceRevisionArtifact?
      let applyReceiptID: ReceiptID?
      switch (authority, event.payload) {
      case (
        .journaledMutationCommit,
        .integrationAdvanced(.applyRecorded(let receipt))
      ):
        guard receipt.transactionID == transactionID,
          projected.applyReceipt == receipt,
          case .exactPostimage = receipt.outcome,
          let observed = receipt.observedPostimageDigest
        else {
          return nil
        }
        generationDigest = observed
        candidatePostimage = receipt.candidatePostimage
        applyReceiptID = receipt.id
      case (
        .journaledRecoveryReconciliation,
        .integrationAdvanced(.rollbackRecorded(let receipt))
      ):
        guard receipt.transactionID == transactionID,
          projected.rollbackReceipt == receipt,
          case .restored = receipt.outcome,
          let observed = receipt.observedPreimageDigest
        else {
          return nil
        }
        generationDigest = observed
        candidatePostimage = nil
        applyReceiptID = nil
      default:
        return nil
      }
      return AcceptedWorkspaceTreeGenerationEvent(
        transactionID: transactionID,
        generationDigest: generationDigest,
        authority: authority,
        journalTransaction: transaction,
        candidatePostimage: candidatePostimage,
        applyReceiptID: applyReceiptID
      )
    }
    return candidates.max {
      $0.journalTransaction.endingSequence < $1.journalTransaction.endingSequence
    }
  }

  /// Confirms that an opaque candidate attestation still names the newest
  /// unambiguous accepted apply event. A later in-flight, failed, or rollback
  /// transition invalidates capture authority before any bytes can be read.
  func isLatestAcceptedCandidatePostimageAttestation(
    _ attestation: WorkspaceCandidatePostimageAttestationReceipt
  ) -> Bool {
    guard case .accepted(let event) = latestWorkspaceTreeGenerationEvent(),
      event.authority == .journaledMutationCommit,
      event.transactionID == attestation.integrationTransactionID,
      event.applyReceiptID == attestation.applyReceiptID,
      event.candidatePostimage == attestation.candidatePostimage,
      event.journalTransaction == attestation.journalTransaction
    else {
      return false
    }
    return true
  }

  /// Projects the last journaled filesystem transition. An older successful
  /// generation cannot authorize reuse after a newer failed or in-doubt
  /// effect because the tree may have been partially changed.
  func latestWorkspaceTreeGenerationEvent() -> WorkspaceTreeGenerationJournalProjection {
    let latest = transactionEvents.values
      .flatMap { $0 }
      .filter { event in
        guard case .integrationAdvanced(let transition) = event.payload else {
          return false
        }
        switch transition {
        case .applyStarted, .applyRecorded, .rollbackStarted, .rollbackRecorded:
          return true
        default: return false
        }
      }
      .max { $0.sequence < $1.sequence }
    guard let latest else { return .noWorkspaceTransition }
    switch latest.payload {
    case .integrationAdvanced(.applyRecorded(let receipt)):
      guard case .exactPostimage = receipt.outcome,
        let accepted = acceptedWorkspaceTreeGenerationEvent(
          transactionID: receipt.transactionID,
          authority: .journaledMutationCommit
        )
      else {
        return .ambiguousLatestTransition
      }
      return .accepted(accepted)
    case .integrationAdvanced(.rollbackRecorded(let receipt)):
      guard case .restored = receipt.outcome,
        let accepted = acceptedWorkspaceTreeGenerationEvent(
          transactionID: receipt.transactionID,
          authority: .journaledRecoveryReconciliation
        )
      else {
        return .ambiguousLatestTransition
      }
      return .accepted(accepted)
    default:
      return .ambiguousLatestTransition
    }
  }

  func runtimeReleaseFailed(resourceID: OwnedResourceID) -> Bool {
    state.runtimeFailedReleases.contains(resourceID)
  }

  func integrationTransaction(
    transactionID: IntegrationTransactionID
  ) -> IntegrationTransactionState? {
    state.integrationTransactions[transactionID]
  }

  func runtimeSupervisorRecoverySnapshot() -> RuntimeSupervisorRecoverySnapshot {
    var latestReleasedByLease: [ResourceLeaseID: RuntimeReleaseReceipt] = [:]
    let released = state.runtimeReleaseReceipts.values.compactMap {
      outcome -> RuntimeReleaseReceipt? in
      guard case .released(let receipt) = outcome.outcome else { return nil }
      return receipt
    }.sorted {
      if $0.releasedAtMonotonicNanoseconds != $1.releasedAtMonotonicNanoseconds {
        return $0.releasedAtMonotonicNanoseconds < $1.releasedAtMonotonicNanoseconds
      }
      return $0.leaseID.rawValue < $1.leaseID.rawValue
    }
    for receipt in released {
      latestReleasedByLease[receipt.leaseID] = receipt
    }
    let drainIntent = state.lastRuntimeDrainReceiptID.flatMap {
      state.runtimeDrainReceipts[$0]?.snapshot.intent
    }
    return RuntimeSupervisorRecoverySnapshot(
      runID: runID,
      sourceSequence: state.sequence,
      sourceFrameDigest: lastFrameDigest,
      phase: drainIntent.map(RuntimeSupervisorPhase.draining) ?? .accepting,
      liveLeases: state.runtimeLiveLeases.values.sorted {
        $0.request.resourceID.rawValue < $1.request.resourceID.rawValue
      },
      releasedReceipts: latestReleasedByLease.values.sorted {
        $0.leaseID.rawValue < $1.leaseID.rawValue
      },
      failedReleases: state.runtimeFailedReleases
    )
  }

  /// Creates the command context inside the journal actor so concurrent
  /// clients cannot race while independently reading the current sequence.
  func transactAtCurrentSequence(
    _ command: RunCommand,
    commandID: RunCommandID,
    issuedAt: Date,
    actor: ActorIdentity,
    durability: JournalDurability = .boundary
  ) throws -> JournalTransactionReceipt {
    try transact(
      command,
      context: KernelCommandContext(
        commandID: commandID,
        expectedSequence: state.sequence,
        issuedAt: issuedAt,
        actor: actor
      ),
      durability: durability
    )
  }

  private func append(
    frame: JournalTransactionFrame,
    durability: JournalDurability
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var bytes = try encoder.encode(frame)
    bytes.append(0x0A)

    if !FileManager.default.fileExists(atPath: journalURL.path) {
      FileManager.default.createFile(atPath: journalURL.path, contents: nil)
    }
    let handle = try FileHandle(forUpdating: journalURL)
    guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
      try? handle.close()
      throw RunJournalError.writerLockFailed
    }
    defer {
      flock(handle.fileDescriptor, LOCK_UN)
      try? handle.close()
    }

    let onDisk = try Self.recover(journalURL: journalURL, runID: runID)
    guard onDisk.report.ignoredTrailingBytes == 0 else {
      throw RunJournalError.unresolvedTrailingFragment(
        bytes: onDisk.report.ignoredTrailingBytes
      )
    }
    guard onDisk.state.sequence == state.sequence,
      onDisk.report.lastFrameDigest == lastFrameDigest
    else {
      throw RunJournalError.writerStale(
        expectedSequence: state.sequence,
        actualSequence: onDisk.state.sequence
      )
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: bytes)
    if durability == .boundary { try handle.synchronize() }
  }

  private static func recover(
    journalURL: URL,
    runID: KernelRunID
  ) throws -> (
    state: KernelRunState,
    receipts: [RunCommandID: JournalTransactionReceipt],
    transactionEvents: [RunCommandID: [OrchestrationEvent]],
    report: JournalRecoveryReport
  ) {
    guard let data = try? Data(contentsOf: journalURL), !data.isEmpty else {
      return (
        .empty(runID: runID),
        [:],
        [:],
        JournalRecoveryReport(
          recoveredTransactions: 0,
          recoveredEvents: 0,
          ignoredTrailingBytes: 0,
          lastFrameDigest: nil
        )
      )
    }

    let hasTerminalNewline = data.last == 0x0A
    var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
    if hasTerminalNewline, lines.last?.isEmpty == true { lines.removeLast() }
    var ignoredTrailingBytes = 0
    if !hasTerminalNewline, let trailing = lines.popLast() {
      ignoredTrailingBytes = trailing.count
    }

    let decoder = JSONDecoder()
    var state = KernelRunState.empty(runID: runID)
    var receipts: [RunCommandID: JournalTransactionReceipt] = [:]
    var transactionEvents: [RunCommandID: [OrchestrationEvent]] = [:]
    var previousDigest: ContentDigest?
    var recoveredEvents = 0
    var recoveredEventIDs: Set<OrchestrationEventID> = []

    for (offset, rawLine) in lines.enumerated() {
      let lineNumber = offset + 1
      guard
        let frame = try? decoder.decode(
          JournalTransactionFrame.self,
          from: Data(rawLine)
        )
      else {
        throw RunJournalError.invalidFrameEncoding(line: lineNumber)
      }
      guard frame.schemaVersion == 1 || frame.schemaVersion == 2,
        frame.runID == runID
      else {
        throw RunJournalError.runIdentityMismatch
      }
      guard receipts[frame.commandID] == nil else {
        throw RunJournalError.duplicateCommand(line: lineNumber)
      }
      let frameEvents: [OrchestrationEvent]
      let expected: ContentDigest
      switch frame.schemaVersion {
      case 1:
        guard let events = frame.events, frame.encodedEvents == nil else {
          throw RunJournalError.invalidFrameEncoding(line: lineNumber)
        }
        frameEvents = events
        expected = try legacyFrameDigest(
          runID: runID,
          commandID: frame.commandID,
          previous: previousDigest,
          events: events
        )
      case 2:
        guard frame.events == nil, let encodedEvents = frame.encodedEvents,
          let events = try? decoder.decode(
            [OrchestrationEvent].self,
            from: encodedEvents
          )
        else {
          throw RunJournalError.invalidFrameEncoding(line: lineNumber)
        }
        frameEvents = events
        expected = try frameDigestV2(
          runID: runID,
          commandID: frame.commandID,
          previous: previousDigest,
          encodedEvents: encodedEvents
        )
      default:
        throw RunJournalError.runIdentityMismatch
      }
      guard frame.previousFrameDigest == previousDigest,
        frame.frameDigest == expected
      else {
        throw RunJournalError.brokenHashChain(line: lineNumber)
      }
      guard !frameEvents.isEmpty else {
        throw RunJournalError.invalidEventSequence(line: lineNumber)
      }

      let startingSequence = state.sequence + 1
      for event in frameEvents {
        guard recoveredEventIDs.insert(event.id).inserted else {
          throw RunJournalError.duplicateEvent(line: lineNumber)
        }
        guard event.runID == runID,
          event.commandID == frame.commandID,
          event.sequence == state.sequence + 1
        else {
          throw RunJournalError.invalidEventSequence(line: lineNumber)
        }
        let next = RunReducer.reduce(state: state, event: event)
        guard next.sequence == event.sequence else {
          throw RunJournalError.invalidEventSequence(line: lineNumber)
        }
        state = next
        recoveredEvents += 1
      }
      receipts[frame.commandID] = JournalTransactionReceipt(
        commandID: frame.commandID,
        startingSequence: startingSequence,
        endingSequence: state.sequence,
        eventIDs: frameEvents.map(\.id),
        frameDigest: frame.frameDigest,
        duplicate: false
      )
      transactionEvents[frame.commandID] = frameEvents
      previousDigest = frame.frameDigest
    }

    return (
      state,
      receipts,
      transactionEvents,
      JournalRecoveryReport(
        recoveredTransactions: receipts.count,
        recoveredEvents: recoveredEvents,
        ignoredTrailingBytes: ignoredTrailingBytes,
        lastFrameDigest: previousDigest
      )
    )
  }

  private static func encodeEvents(_ events: [OrchestrationEvent]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(events)
  }

  private static func frameDigestV2(
    runID: KernelRunID,
    commandID: RunCommandID,
    previous: ContentDigest?,
    encodedEvents: Data
  ) throws -> ContentDigest {
    struct DigestInput: Encodable {
      var schemaVersion = 2
      var runID: KernelRunID
      var commandID: RunCommandID
      var previousFrameDigest: ContentDigest?
      var encodedEvents: Data
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(
      DigestInput(
        runID: runID,
        commandID: commandID,
        previousFrameDigest: previous,
        encodedEvents: encodedEvents
      ))
    return ContentDigest(
      SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined())
  }

  private static func legacyFrameDigest(
    runID: KernelRunID,
    commandID: RunCommandID,
    previous: ContentDigest?,
    events: [OrchestrationEvent]
  ) throws -> ContentDigest {
    struct DigestInput: Encodable {
      var schemaVersion = 1
      var runID: KernelRunID
      var commandID: RunCommandID
      var previousFrameDigest: ContentDigest?
      var events: [OrchestrationEvent]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(
      DigestInput(
        runID: runID,
        commandID: commandID,
        previousFrameDigest: previous,
        events: events
      ))
    return ContentDigest(
      SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined())
  }
}
