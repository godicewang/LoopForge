import Foundation

/// File-owned proof that only this coordinator can convert a live
/// process-runtime result into reducer command authority.
struct ExternalDependencyObservationJournalCommandIssuer: Sendable {
  fileprivate init() {}
}

struct ExternalDependencyObservationJournalRequest: Sendable {
  var commandID: RunCommandID
}

struct JournaledExternalDependencyObservationReceipt: Sendable {
  var observation: ExternalDependencyObservationReceipt
  var transaction: JournalTransactionReceipt
}

enum ExternalDependencyObservationJournalError: Error, Equatable {
  case invalidRequest
  case resultNotCurrent
  case releaseNotJournaled
  case observationAlreadyResolved
  case journalRejected(KernelRejection)
  case journalWriteFailed
  case journalReceiptMismatch
}

/// The sole production ingress from a process-runtime result capability to an
/// external-dependency observation event. It executes no process and parses no
/// bytes; it only re-resolves and journals exact authority already established
/// by the activation and release paths.
actor ExternalDependencyObservationJournalCoordinator {
  private let journal: RunJournal

  init(journal: RunJournal) {
    self.journal = journal
  }

  func record(
    _ result: AuthorizedExternalDependencyObservationResult,
    request: ExternalDependencyObservationJournalRequest
  ) async throws -> JournaledExternalDependencyObservationReceipt {
    guard !request.commandID.rawValue.isEmpty else {
      throw ExternalDependencyObservationJournalError.invalidRequest
    }
    let resultReceipt = result.receipt
    let state = await journal.state
    guard state.phase == .executing,
      state.activeAttemptID == resultReceipt.attemptID,
      state.attempts[resultReceipt.attemptID]?.disposition == nil,
      let activation =
        (state
        .externalDependencyObservationActivationReceipts ?? [:])[
          resultReceipt.activationReceiptID
        ],
      activation.runID == resultReceipt.runID,
      activation.attemptID == resultReceipt.attemptID,
      activation.dependencyID == resultReceipt.dependencyID,
      activation.requirementIDs == resultReceipt.requirementIDs,
      activation.evidenceRecipeID == resultReceipt.evidenceRecipeID,
      activation.observer == resultReceipt.observer,
      let launch =
        (state
        .externalDependencyObservationRuntimeLaunchReceipts ?? [:])
        .values.first(where: {
          $0.activationReceiptID == activation.id
        }),
      (state.externalDependencyObservationRuntimeLaunchReceipts ?? [:])
        .values.filter({
          $0.activationReceiptID == activation.id
        }).count == 1,
      launch.resourceID == resultReceipt.resourceID,
      launch.leaseID == resultReceipt.leaseID,
      let binding = state.runtimeBindingReceipts[
        launch.bindingReceiptID
      ],
      ExternalDependencyObservationRuntimeLaunchCompiler.launch(
        launch,
        matches: activation,
        binding: binding
      ),
      result.release.managedProcessExit?.handle.externalIdentity == binding.identity,
      result.release.observedAt >= launch.launchedAt,
      let dependency = state.contract?.externalDependencies?
        .first(where: { $0.id == activation.dependencyID }),
      state.contract?.externalDependencies?.filter({
        $0.id == activation.dependencyID
      }).count == 1,
      let probe = dependency.executableProbe,
      ExternalDependencyObservationResultAuthority.receipt(
        resultReceipt,
        matchesActivation: activation,
        probe: probe,
        release: result.release,
        releaseTransaction: result.releaseTransaction
      )
    else {
      throw ExternalDependencyObservationJournalError.resultNotCurrent
    }
    guard
      await journal.runtimeReleaseReceipt(
        transaction: result.releaseTransaction
      ) == result.release,
      await journal.runtimeReleaseFrameDigest(
        receiptID: result.release.id
      ) == result.releaseTransaction.frameDigest
    else {
      throw ExternalDependencyObservationJournalError.releaseNotJournaled
    }
    let observation = ExternalDependencyObservationReceipt(
      id: ReceiptID(
        "external-dependency-observation:\(resultReceipt.evidenceSetDigest.rawValue)"
      ),
      attemptID: resultReceipt.attemptID,
      dependencyID: resultReceipt.dependencyID,
      requirementIDs: resultReceipt.requirementIDs,
      observer: resultReceipt.observer,
      evidenceRecipeID: resultReceipt.evidenceRecipeID,
      evidenceDigest: resultReceipt.parse.evidenceDigest,
      availability: resultReceipt.mapping.availability,
      observedAt: resultReceipt.completedAt,
      sourceResultID: resultReceipt.id,
      sourceResultEvidenceSetDigest: resultReceipt.evidenceSetDigest,
      sourceReleaseReceiptID: resultReceipt.releaseReceiptID,
      sourceReleaseFrameDigest: resultReceipt.releaseFrameDigest
    )

    if let prior = await journal.transactionReceipt(
      commandID: request.commandID
    ) {
      guard
        await journal.externalDependencyObservationReceipt(
          transaction: prior
        ) == observation
      else {
        throw ExternalDependencyObservationJournalError
          .journalReceiptMismatch
      }
      return JournaledExternalDependencyObservationReceipt(
        observation: observation,
        transaction: prior
      )
    }
    guard
      (state.externalDependencyReceipts ?? [:]).values.contains(
        where: {
          $0.attemptID == observation.attemptID
            && $0.dependencyID == observation.dependencyID
        }
      ) == false,
      (state.externalDependencyObservationLaunchVetoReceipts ?? [:])
        .values.contains(where: {
          $0.activationReceiptID == activation.id
        }) == false
    else {
      throw ExternalDependencyObservationJournalError
        .observationAlreadyResolved
    }
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .recordExternalDependencyObservation(
          .issuedByExternalDependencyJournal(
            observation,
            issuer: .init()
          )
        ),
        commandID: request.commandID,
        issuedAt: observation.observedAt,
        actor: observation.observer
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw
        ExternalDependencyObservationJournalError
        .journalRejected(rejection)
    } catch {
      throw ExternalDependencyObservationJournalError.journalWriteFailed
    }
    guard !transaction.duplicate,
      await journal.externalDependencyObservationReceipt(
        transaction: transaction
      ) == observation
    else {
      throw ExternalDependencyObservationJournalError
        .journalReceiptMismatch
    }
    return JournaledExternalDependencyObservationReceipt(
      observation: observation,
      transaction: transaction
    )
  }
}
