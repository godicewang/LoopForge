import Foundation

struct ExternalDependencyObservationLaunchVetoReceipt:
  Codable, Hashable, Sendable
{
  var schemaVersion: Int
  var id: ReceiptID
  var runID: KernelRunID
  var activationReceiptID: ReceiptID
  var activationSourceJournalFrameDigest: ContentDigest
  var attemptID: AttemptID
  var dependencyID: ExternalDependencyID
  var observer: ActorIdentity
  var requiredMaximumResidentBytes: UInt64
  var reason: KernelResidentMemoryEnforcementUnavailabilityReason
  var sourceJournalSequence: UInt64
  var observedAt: Date
}

/// Only the readiness coordinator can turn a live activation and a missing
/// hard memory-enforcement capability into reducer command authority.
struct AuthorizedExternalDependencyObservationLaunchVeto: Sendable {
  let receipt: ExternalDependencyObservationLaunchVetoReceipt

  private init(receipt: ExternalDependencyObservationLaunchVetoReceipt) {
    self.receipt = receipt
  }

  fileprivate static func issued(
    _ receipt: ExternalDependencyObservationLaunchVetoReceipt
  ) -> Self {
    Self(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: ExternalDependencyObservationLaunchVetoReceipt
    ) -> Self {
      Self(receipt: receipt)
    }
  #endif
}

/// Non-serializable authority proving the exact activation remains live and
/// a separate boundary can enforce its declared resident-memory ceiling.
/// This is readiness only: it owns no lease, process, sandbox, or result.
struct AuthorizedExternalDependencyObservationLaunchReadiness: Sendable {
  let invocation: AuthorizedExternalDependencyObservationInvocation
  let residentMemoryEnforcement: AuthorizedKernelResidentMemoryEnforcement

  fileprivate init(
    invocation: AuthorizedExternalDependencyObservationInvocation,
    residentMemoryEnforcement: AuthorizedKernelResidentMemoryEnforcement
  ) {
    self.invocation = invocation
    self.residentMemoryEnforcement = residentMemoryEnforcement
  }
}

struct ExternalDependencyObservationLaunchReadinessRequest: Sendable {
  var vetoReceiptID: ReceiptID
  var vetoCommandID: RunCommandID
  var observedAt: Date
}

enum ExternalDependencyObservationLaunchReadinessDecision: Sendable {
  case ready(AuthorizedExternalDependencyObservationLaunchReadiness)
  case vetoed(
    receipt: ExternalDependencyObservationLaunchVetoReceipt,
    transaction: JournalTransactionReceipt
  )
}

enum ExternalDependencyObservationLaunchReadinessError: Error, Equatable {
  case invalidRequest
  case activationNotActive
  case artifactRevalidationFailed
  case executableRevalidationFailed
  case containmentAuthorityMismatch
  case journalRejected(KernelRejection)
  case journalWriteFailed
  case journalReceiptMismatch
}

enum ExternalDependencyObservationLaunchVetoCompiler {
  static func validationIssue(
    _ receipt: ExternalDependencyObservationLaunchVetoReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.schemaVersion == 1,
      !receipt.id.rawValue.isEmpty,
      receipt.runID == state.runID,
      receipt.observer == actor,
      receipt.observedAt == occurredAt,
      receipt.sourceJournalSequence == state.sequence,
      receipt.requiredMaximumResidentBytes > 0,
      receipt.reason
        == .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
      state.phase == .executing,
      state.activeAttemptID == receipt.attemptID,
      state.attempts[receipt.attemptID]?.disposition == nil,
      let activation =
        (state
        .externalDependencyObservationActivationReceipts ?? [:])[
          receipt.activationReceiptID
        ],
      activation.runID == receipt.runID,
      activation.attemptID == receipt.attemptID,
      activation.dependencyID == receipt.dependencyID,
      activation.observer == receipt.observer,
      activation.sourceJournalFrameDigest == receipt.activationSourceJournalFrameDigest,
      activation.resourceLimits.maximumResidentBytes == receipt.requiredMaximumResidentBytes,
      (state.externalDependencyReceipts ?? [:]).values.contains(
        where: {
          $0.attemptID == receipt.attemptID
            && $0.dependencyID == receipt.dependencyID
        }
      ) == false,
      (state.externalDependencyObservationRuntimeLaunchReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == receipt.activationReceiptID
        }) == false,
      (state.externalDependencyObservationLaunchVetoReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == receipt.activationReceiptID
        }) == false
    else {
      return "external dependency launch veto provenance mismatch"
    }
    return nil
  }
}

/// Resolves the safety boundary immediately before resource admission. A
/// missing hard resident-memory enforcer is journaled as a deterministic veto
/// while creating no lease, process, output, or availability evidence.
actor ExternalDependencyObservationLaunchReadinessCoordinator {
  private let journal: RunJournal

  init(journal: RunJournal) {
    self.journal = journal
  }

  func evaluate(
    invocation: AuthorizedExternalDependencyObservationInvocation,
    request: ExternalDependencyObservationLaunchReadinessRequest,
    residentMemoryEnforcement:
      AuthorizedKernelResidentMemoryEnforcement? = nil
  ) async throws -> ExternalDependencyObservationLaunchReadinessDecision {
    guard !request.vetoReceiptID.rawValue.isEmpty,
      !request.vetoCommandID.rawValue.isEmpty
    else {
      throw ExternalDependencyObservationLaunchReadinessError
        .invalidRequest
    }
    let activation = invocation.receipt
    let state = await journal.state
    guard state.phase == .executing,
      state.activeAttemptID == activation.attemptID,
      state.attempts[activation.attemptID]?.disposition == nil,
      (state.externalDependencyObservationActivationReceipts ?? [:])[
        activation.id
      ] == activation,
      await journal.externalDependencyObservationActivationReceipt(
        transaction: invocation.activationTransaction
      ) == activation,
      (state.externalDependencyReceipts ?? [:]).values.contains(
        where: {
          $0.attemptID == activation.attemptID
            && $0.dependencyID == activation.dependencyID
        }
      ) == false,
      (state.externalDependencyObservationRuntimeLaunchReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == activation.id
        }) == false
    else {
      throw ExternalDependencyObservationLaunchReadinessError
        .activationNotActive
    }
    do {
      _ = try ExternalDependencyObservationRequestArtifactIssuer()
        .revalidate(
          expectedEnvelope:
            ExternalDependencyObservationActivationCompiler
            .envelope(receipt: activation),
          receiptID: activation.id,
          journalRunDirectory: journal.runDirectory,
          matching: activation.requestArtifact
        )
    } catch {
      throw ExternalDependencyObservationLaunchReadinessError
        .artifactRevalidationFailed
    }
    do {
      let staging = try KernelExecutableStager().stage(
        executablePath: activation.executableStaging
          .sourceExecutablePath,
        expectedDigest: activation.executableStaging.contentDigest,
        runDirectory: journal.runDirectory
      )
      guard staging.stagedExecutablePath == activation.executableStaging.stagedExecutablePath,
        staging.contentDigest == activation.executableStaging.contentDigest,
        staging.byteCount == activation.executableStaging.byteCount,
        staging.deviceID == activation.executableStaging.deviceID,
        staging.inode == activation.executableStaging.inode
      else {
        throw ExternalDependencyObservationLaunchReadinessError
          .executableRevalidationFailed
      }
    } catch let error as ExternalDependencyObservationLaunchReadinessError {
      throw error
    } catch {
      throw ExternalDependencyObservationLaunchReadinessError
        .executableRevalidationFailed
    }

    if let prior = await journal.transactionReceipt(
      commandID: request.vetoCommandID
    ) {
      guard residentMemoryEnforcement == nil,
        let retained =
          await journal
          .externalDependencyObservationLaunchVetoReceipt(
            transaction: prior
          ),
        retained.id == request.vetoReceiptID,
        retained.runID == activation.runID,
        retained.activationReceiptID == activation.id,
        retained.activationSourceJournalFrameDigest == activation.sourceJournalFrameDigest,
        retained.attemptID == activation.attemptID,
        retained.dependencyID == activation.dependencyID,
        retained.observer == activation.observer,
        retained.requiredMaximumResidentBytes == activation.resourceLimits.maximumResidentBytes,
        retained.reason
          == .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
        retained.observedAt == request.observedAt
      else {
        throw ExternalDependencyObservationLaunchReadinessError
          .journalReceiptMismatch
      }
      return .vetoed(receipt: retained, transaction: prior)
    }
    guard
      (state.externalDependencyObservationLaunchVetoReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == activation.id
        }) == false
    else {
      throw ExternalDependencyObservationLaunchReadinessError
        .activationNotActive
    }

    if let residentMemoryEnforcement {
      guard
        residentMemoryEnforcement.authorizes(
          externalDependencyActivation: activation
        )
      else {
        throw ExternalDependencyObservationLaunchReadinessError
          .containmentAuthorityMismatch
      }
      return .ready(
        AuthorizedExternalDependencyObservationLaunchReadiness(
          invocation: invocation,
          residentMemoryEnforcement: residentMemoryEnforcement
        )
      )
    }

    let receipt = ExternalDependencyObservationLaunchVetoReceipt(
      schemaVersion: 1,
      id: request.vetoReceiptID,
      runID: activation.runID,
      activationReceiptID: activation.id,
      activationSourceJournalFrameDigest:
        activation.sourceJournalFrameDigest,
      attemptID: activation.attemptID,
      dependencyID: activation.dependencyID,
      observer: activation.observer,
      requiredMaximumResidentBytes:
        activation.resourceLimits.maximumResidentBytes,
      reason: .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit,
      sourceJournalSequence: state.sequence,
      observedAt: request.observedAt
    )
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordExternalDependencyObservationLaunchVeto(
          .issued(receipt)
        ),
        commandID: request.vetoCommandID,
        issuedAt: request.observedAt,
        actor: activation.observer
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw
        ExternalDependencyObservationLaunchReadinessError
        .journalRejected(rejection)
    } catch {
      throw ExternalDependencyObservationLaunchReadinessError
        .journalWriteFailed
    }
    guard !transaction.duplicate,
      await journal.externalDependencyObservationLaunchVetoReceipt(
        transaction: transaction
      ) == receipt
    else {
      throw ExternalDependencyObservationLaunchReadinessError
        .journalReceiptMismatch
    }
    return .vetoed(receipt: receipt, transaction: transaction)
  }
}
