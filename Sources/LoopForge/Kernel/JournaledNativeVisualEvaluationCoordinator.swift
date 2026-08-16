import CryptoKit
import Foundation

enum JournaledNativeVisualEvaluationError: Error, Equatable {
  case invalidEvaluator
  case runMismatch
  case invalidExecutionProof
  case invalidReducerState(String)
  case invalidReviewAuthority(String)
  case digestConstructionFailed
  case journalRejected(KernelRejection)
  case journalReceiptMismatch
}

struct JournaledNativeVisualEvaluationRequest: Sendable {
  var execution: JournaledKernelExecutionProof
  var review: AuthorizedNativeIndependentVisualReview
}

struct JournaledNativeVisualEvaluationReceipt: Sendable {
  var runID: KernelRunID
  var contractID: TaskContractID
  var attemptID: AttemptID
  var baselineID: DesignBaselineID
  var nativeReviewRequestDigest: ContentDigest
  var visualGateReceipt: VisualGateEvaluationReceipt
  var journalTransaction: JournalTransactionReceipt
  var kernelProjection: KernelRunProjection
}

/// Unforgeable issuer marker. Only this file can construct it; the reducer's
/// production visual command factory requires it.
struct NativeVisualEvaluationCommandIssuer: Sendable {
  fileprivate init() {}
}

/// File-owned production evaluator identity. A production controller does not
/// accept a caller-selected actor for the deterministic visual gate.
enum KernelNativeVisualEvaluationIdentity {
  static let deterministicEvaluator = ActorIdentity(
    id: ActorID("loopforge-kernel-native-visual-evaluator-v1"),
    role: "deterministicVisualGate",
    lineageDigest: ContentDigest(
      "a4e3ee3f9a4ef2ae565b82d3dad4c69ffb260d45ccf28f8a8122322dcd4c092b"
    )
  )
}

/// Consumes the exact live native review authority and appends one reducer-
/// evaluated, hash-journaled visual result. It does not invoke a harness,
/// capture UI, mutate the workspace, or trust caller-selected receipt IDs,
/// requirements, actor time, or aggregate verdicts.
actor JournaledNativeVisualEvaluationCoordinator {
  private struct IssuanceEnvelope: Encodable {
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var baselineID: DesignBaselineID
    var attemptID: AttemptID
    var requirementIDs: [RequirementID]
    var candidateSourceTree: ContentDigest
    var candidateBuiltArtifact: ContentDigest
    var deterministicEvidenceDigest: ContentDigest
    var nativeReviewRequestDigest: ContentDigest
    var nativeCaptureAttestationDigests: [ContentDigest]
    var nativeMeasurementAttestationDigests: [ContentDigest]
    var independentReviewReceiptID: ReceiptID
    var reviewer: ActorIdentity
    var worker: ActorIdentity
    var evaluator: ActorIdentity
  }

  private let journal: RunJournal
  private let evaluator: ActorIdentity
  private let clock: @Sendable () -> Date

  init(
    journal: RunJournal,
    evaluator: ActorIdentity,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.journal = journal
    self.evaluator = evaluator
    self.clock = clock
  }

  /// Production composition fixes the evaluator identity in code. Tests
  /// that exercise explicit lineage substitution retain the designated
  /// initializer above.
  init(journal: RunJournal) {
    self.init(
      journal: journal,
      evaluator: KernelNativeVisualEvaluationIdentity
        .deterministicEvaluator
    )
  }

  func evaluate(
    _ request: JournaledNativeVisualEvaluationRequest
  ) async throws -> JournaledNativeVisualEvaluationReceipt {
    let reviewAuthority = request.review
    let candidate = reviewAuthority.candidate
    guard !evaluator.id.rawValue.isEmpty,
      evaluator.role == "deterministicVisualGate",
      !evaluator.lineageDigest.rawValue.isEmpty
    else {
      throw JournaledNativeVisualEvaluationError.invalidEvaluator
    }
    guard request.execution.runID == journal.runID else {
      throw JournaledNativeVisualEvaluationError.runMismatch
    }

    let state = await journal.state
    guard state.phase == .evaluating,
      let contract = state.contract,
      let baseline = state.designBaseline,
      let attempt = state.attempts[request.execution.attemptID],
      attempt.disposition?.canEnterVerification == true
    else {
      throw JournaledNativeVisualEvaluationError.invalidReducerState(
        "visual issuance requires one completed exact attempt and frozen baseline"
      )
    }
    guard contract.id == baseline.contractID,
      request.execution.nodeID == attempt.nodeID,
      request.execution.strategyFingerprint == attempt.strategyFingerprint,
      request.execution.activationActor == attempt.worker,
      let started = await journal.attemptStart(
        transaction: request.execution.activationTransaction
      ),
      started.id == attempt.id,
      started.nodeID == attempt.nodeID,
      started.requirementIDs == attempt.requirementIDs,
      started.strategyFingerprint == attempt.strategyFingerprint,
      started.worker == attempt.worker,
      started.startedAt == attempt.startedAt
    else {
      throw JournaledNativeVisualEvaluationError.invalidExecutionProof
    }

    guard let profile = contract.executionProfile,
      profile.requiresDistinctActorLineage,
      profile.worker == request.execution.workerExecutionProfile,
      profile.independentReviewer == reviewAuthority.reviewerExecutionProfile,
      reviewAuthority.worker == attempt.worker,
      let review = candidate.independentReview,
      review.workerLineageDigest == attempt.worker.lineageDigest,
      review.reviewer.lineageDigest != attempt.worker.lineageDigest,
      review.reviewer.lineageDigest != evaluator.lineageDigest,
      review.reviewer.lineageDigest
        != baseline.authority.authority
        .lineageDigest,
      evaluator.lineageDigest != attempt.worker.lineageDigest,
      evaluator.lineageDigest
        != baseline.authority.authority
        .lineageDigest,
      review.provider == profile.independentReviewer.providerReference,
      review.model == profile.independentReviewer.modelID
    else {
      throw JournaledNativeVisualEvaluationError.invalidReviewAuthority(
        "ratified reviewer, worker, evaluator, and design-authority lineages must remain exact and distinct"
      )
    }
    guard baseline.requirementIDs.isSubset(of: attempt.requirementIDs),
      review.baselineID == baseline.id,
      review.candidateSourceTree == candidate.sourceTree,
      review.decision == candidate.independentReview?.decision,
      candidate.captures.allSatisfy({
        $0.sourceTree == candidate.sourceTree
          && $0.builtArtifact == candidate.builtArtifact
          && $0.captureProtocol == baseline.captureProtocol
      }),
      Self.validSHA256(reviewAuthority.requestDigest),
      reviewAuthority.captureAttestationDigests.count == candidate.captures.count,
      reviewAuthority.measurementAttestationDigests.count == candidate.measurements.count,
      reviewAuthority.captureAttestationDigests.allSatisfy(
        Self.validSHA256
      ),
      reviewAuthority.measurementAttestationDigests.allSatisfy(
        Self.validSHA256
      )
    else {
      throw JournaledNativeVisualEvaluationError.invalidReviewAuthority(
        "live review must bind the exact baseline, candidate matrix, and complete attestation sets"
      )
    }

    let evaluatedAt = clock()
    let latestCapture =
      candidate.captures.map(\.capturedAt).max()
      ?? candidate.mutationStartedAt
    guard reviewAuthority.reviewedAt >= candidate.mutationStartedAt,
      reviewAuthority.reviewedAt >= latestCapture,
      evaluatedAt >= reviewAuthority.reviewedAt
    else {
      throw JournaledNativeVisualEvaluationError.invalidReviewAuthority(
        "review and evaluation time must follow the exact candidate evidence"
      )
    }
    let deterministicDigest = DesignBaselineGate.deterministicEvidenceDigest(
      baseline: baseline,
      candidate: candidate
    )
    guard !deterministicDigest.rawValue.isEmpty else {
      throw JournaledNativeVisualEvaluationError.digestConstructionFailed
    }

    let issuanceDigest = try Self.digest(
      IssuanceEnvelope(
        schemaVersion: 1,
        runID: journal.runID,
        contractID: contract.id,
        baselineID: baseline.id,
        attemptID: attempt.id,
        requirementIDs: baseline.requirementIDs.sorted {
          $0.rawValue < $1.rawValue
        },
        candidateSourceTree: candidate.sourceTree,
        candidateBuiltArtifact: candidate.builtArtifact,
        deterministicEvidenceDigest: deterministicDigest,
        nativeReviewRequestDigest: reviewAuthority.requestDigest,
        nativeCaptureAttestationDigests:
          reviewAuthority.captureAttestationDigests.sorted {
            $0.rawValue < $1.rawValue
          },
        nativeMeasurementAttestationDigests:
          reviewAuthority.measurementAttestationDigests.sorted {
            $0.rawValue < $1.rawValue
          },
        independentReviewReceiptID: review.id,
        reviewer: review.reviewer,
        worker: attempt.worker,
        evaluator: evaluator
      ))
    let authority =
      AuthorizedKernelVisualEvaluation
      .issuedByNativeVisualEvaluationCoordinator(
        receiptID: ReceiptID(
          "kernel-native-visual-evaluation-\(issuanceDigest.rawValue)"
        ),
        attemptID: attempt.id,
        requirementIDs: baseline.requirementIDs,
        review: reviewAuthority,
        issuer: NativeVisualEvaluationCommandIssuer()
      )
    let commandID = RunCommandID(
      "kernel-native-visual-evaluation-\(issuanceDigest.rawValue)"
    )
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.recordNativeVisualEvaluation(
        authority,
        commandID: commandID,
        evaluatedAt: evaluatedAt,
        evaluator: evaluator
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw JournaledNativeVisualEvaluationError.journalRejected(rejection)
    }
    guard
      let visualReceipt = await journal.nativeVisualEvaluationReceipt(
        commandID: commandID
      ),
      visualReceipt.id == authority.receiptID,
      visualReceipt.attemptID == attempt.id,
      visualReceipt.requirementIDs == baseline.requirementIDs,
      visualReceipt.baselineID == baseline.id,
      visualReceipt.candidateSourceTree == candidate.sourceTree,
      visualReceipt.candidateBuiltArtifact == candidate.builtArtifact,
      visualReceipt.deterministicEvidenceDigest == deterministicDigest,
      visualReceipt.independentReviewReceiptID == review.id,
      visualReceipt.nativeReviewRequestDigest == reviewAuthority.requestDigest,
      visualReceipt.nativeCaptureAttestationDigests == reviewAuthority.captureAttestationDigests,
      visualReceipt.nativeMeasurementAttestationDigests
        == reviewAuthority.measurementAttestationDigests,
      visualReceipt.nativeReviewCompletedAt == reviewAuthority.reviewedAt
    else {
      throw JournaledNativeVisualEvaluationError.journalReceiptMismatch
    }
    return JournaledNativeVisualEvaluationReceipt(
      runID: journal.runID,
      contractID: contract.id,
      attemptID: attempt.id,
      baselineID: baseline.id,
      nativeReviewRequestDigest: reviewAuthority.requestDigest,
      visualGateReceipt: visualReceipt,
      journalTransaction: transaction,
      kernelProjection: await journal.currentProjection()
    )
  }

  private nonisolated static func validSHA256(
    _ digest: ContentDigest
  ) -> Bool {
    digest.rawValue.count == 64
      && digest.rawValue == digest.rawValue.lowercased()
      && digest.rawValue.allSatisfy(\.isHexDigit)
  }

  private nonisolated static func digest<T: Encodable>(
    _ value: T
  ) throws -> ContentDigest {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    guard let data = try? encoder.encode(value) else {
      throw JournaledNativeVisualEvaluationError
        .digestConstructionFailed
    }
    return ContentDigest(
      SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined())
  }
}
