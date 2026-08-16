import CryptoKit
import Foundation

struct NativeIndependentVisualReviewRequest: Sendable {
  var baseline: DesignBaselineBundle
  var baselineEncodedImages: [VisualCellID: Data]
  var candidateSourceTree: ContentDigest
  var candidateBuiltArtifact: ContentDigest
  var mutationStartedAt: Date
  var candidateCaptures: [AuthorizedNativeCapture]
  var measurements: [AuthorizedNativeVisualMeasurement]
  var mutationManifest: VisualMutationManifest
  var executionProfile: KernelExecutionProfile
  var worker: ActorIdentity
  var maximumImagesPerBatch: Int
  var notBefore: Date
}

struct NativeVisualReviewImagePair: Sendable {
  var cellID: VisualCellID
  var baselineReceipt: NativeCaptureReceipt
  var candidateReceipt: NativeCaptureReceipt
  var baselineEncodedImage: Data
  var candidateEncodedImage: Data
}

struct NativeIndependentVisualReviewHarnessRequest: Sendable {
  var baselineID: DesignBaselineID
  var candidateSourceTree: ContentDigest
  var deterministicResultsDigest: ContentDigest
  var systemPrompt: Data
  var userPrompt: Data
  var evidenceContext: Data
  var imagePairs: [NativeVisualReviewImagePair]
  var candidateBatches: [[NativeCaptureID]]
}

struct NativeIndependentVisualReviewHarnessOutput: Hashable, Sendable {
  var perImageDecisions: [NativeCaptureID: VisualReviewDecision]
  var pairDecisions: [VisualCellID: VisualReviewDecision]
  var inspectedCellIDs: Set<VisualCellID>
  var rawResponse: Data
  var processExitCode: Int32
}

protocol NativeIndependentVisualReviewHarness: Sendable {
  var identity: String { get }
  var providerReference: String { get }
  var modelID: String { get }
  var executableContentDigest: ContentDigest { get }
  var reviewer: ActorIdentity { get }
  func review(
    _ request: NativeIndependentVisualReviewHarnessRequest
  ) async throws -> NativeIndependentVisualReviewHarnessOutput
}

struct AuthorizedNativeIndependentVisualReview: Sendable {
  let candidate: VisualCandidateBundle
  let requestDigest: ContentDigest
  let captureAttestationDigests: Set<ContentDigest>
  let measurementAttestationDigests: Set<ContentDigest>
  let reviewerExecutionProfile: KernelAgentExecutionProfile
  let worker: ActorIdentity
  let reviewedAt: Date

  fileprivate init(
    candidate: VisualCandidateBundle,
    requestDigest: ContentDigest,
    captureAttestationDigests: Set<ContentDigest>,
    measurementAttestationDigests: Set<ContentDigest>,
    reviewerExecutionProfile: KernelAgentExecutionProfile,
    worker: ActorIdentity,
    reviewedAt: Date
  ) {
    self.candidate = candidate
    self.requestDigest = requestDigest
    self.captureAttestationDigests = captureAttestationDigests
    self.measurementAttestationDigests = measurementAttestationDigests
    self.reviewerExecutionProfile = reviewerExecutionProfile
    self.worker = worker
    self.reviewedAt = reviewedAt
  }

  #if DEBUG
    /// Intentionally invalid live-shaped authority for testing that a higher
    /// production boundary rejects on its own retained reducer state before
    /// reading review evidence. It is unavailable in non-DEBUG builds.
    static func testOnlyInvalid() -> AuthorizedNativeIndependentVisualReview {
      AuthorizedNativeIndependentVisualReview(
        candidate: VisualCandidateBundle(
          sourceTree: ContentDigest("test-only-invalid-source"),
          builtArtifact: ContentDigest("test-only-invalid-artifact"),
          mutationStartedAt: .distantPast,
          captures: [],
          measurements: [],
          mutationManifest: VisualMutationManifest(
            directlyAffectedCellIDs: [],
            allBaselineCellIDs: [],
            globalSemanticTokenMutation: false,
            touchedTokenFamilies: []
          ),
          debtSeverityByID: [:],
          reviewBatches: [],
          independentReview: nil,
          amendments: []
        ),
        requestDigest: ContentDigest("test-only-invalid-request"),
        captureAttestationDigests: [],
        measurementAttestationDigests: [],
        reviewerExecutionProfile: KernelAgentExecutionProfile(
          provider: .local,
          providerReference: "test-only-invalid-reviewer",
          executableContentDigest: ContentDigest(
            "test-only-invalid-executable"
          ),
          modelID: "test-only-invalid-model",
          reasoningEffort: nil,
          sandbox: .readOnly,
          networkPolicy: .disabled,
          pluginPolicy: .disabled,
          environmentPolicy: .minimalKernelAllowlist
        ),
        worker: ActorIdentity(
          id: ActorID("test-only-invalid-worker"),
          role: "worker",
          lineageDigest: ContentDigest("test-only-invalid-lineage")
        ),
        reviewedAt: .distantPast
      )
    }
  #endif
}

enum NativeIndependentVisualReviewError: Error, Equatable {
  case invalidRequest(String)
  case incompleteCaptureMatrix
  case invalidBaselineImage(VisualCellID)
  case invalidCandidateCapture(VisualCellID)
  case incompleteMeasurementMatrix
  case invalidMeasurementAuthority(VisualCellID)
  case invalidReviewerProfile
  case untrustedHarness
  case reviewerLineageNotIndependent
  case harnessFailed
  case reviewPredatesAuthorityBoundary
  case processFailed(Int32)
  case responseTooLarge
  case emptyResponse
  case incompleteDecisionMatrix
  case digestConstructionFailed
}

/// Activates one evidence-only, read-only, offline product-design review over
/// an exact native before/after matrix. The adapter constructs every prompt,
/// context digest, batch receipt, aggregate verdict, and review receipt. No
/// worker narrative is accepted by this API.
actor NativeIndependentVisualReviewAdapter {
  private struct EvidenceEnvelope: Encodable {
    var baselineID: DesignBaselineID
    var contractID: TaskContractID
    var candidateSourceTree: ContentDigest
    var candidateBuiltArtifact: ContentDigest
    var requiredCellIDs: [VisualCellID]
    var baselineCaptures: [NativeCaptureReceipt]
    var candidateCaptures: [NativeCaptureReceipt]
    var measurements: [VisualPairMeasurements]
    var debtSeverityByID: [String: Double]
    var mutationManifest: VisualMutationManifest
    var reviewerExecutionProfile: KernelAgentExecutionProfile
    var workerLineageDigest: ContentDigest
    var captureAttestationDigests: [ContentDigest]
    var measurementAttestationDigests: [ContentDigest]
    var baselineEncodedImageDigests: [String: ContentDigest]
    var candidateEncodedImageDigests: [String: ContentDigest]
  }

  private struct ReceiptEnvelope: Encodable {
    var evidenceBundleDigest: ContentDigest
    var deterministicResultsDigest: ContentDigest
    var systemPromptDigest: ContentDigest
    var userPromptDigest: ContentDigest
    var contextDigest: ContentDigest
    var harnessIdentity: String
    var reviewer: ActorIdentity
    var perImageDecisions: [String: VisualReviewDecision]
    var pairDecisions: [String: VisualReviewDecision]
    var inspectedCellIDs: [VisualCellID]
    var rawResponseDigest: ContentDigest
    var reviewedAt: Date
  }

  private let harness: any NativeIndependentVisualReviewHarness
  private let allowedHarnessIdentities: Set<String>
  private let maximumResponseBytes: Int
  private let clock: @Sendable () -> Date

  init(
    harness: any NativeIndependentVisualReviewHarness,
    allowedHarnessIdentities: Set<String>,
    maximumResponseBytes: Int = 4 * 1_024 * 1_024,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.harness = harness
    self.allowedHarnessIdentities = allowedHarnessIdentities
    self.maximumResponseBytes = maximumResponseBytes
    self.clock = clock
  }

  func review(
    _ request: NativeIndependentVisualReviewRequest
  ) async throws -> AuthorizedNativeIndependentVisualReview {
    guard maximumResponseBytes > 0,
      request.maximumImagesPerBatch > 0,
      request.maximumImagesPerBatch <= 8,
      request.mutationStartedAt >= request.baseline.frozenAt,
      request.notBefore >= request.mutationStartedAt,
      !request.candidateSourceTree.rawValue.isEmpty,
      !request.candidateBuiltArtifact.rawValue.isEmpty
    else {
      throw NativeIndependentVisualReviewError.invalidRequest(
        "review bounds and candidate identity must be valid"
      )
    }
    let reviewerProfile = request.executionProfile.independentReviewer
    guard request.executionProfile.requiresDistinctActorLineage,
      reviewerProfile.sandbox == .readOnly,
      reviewerProfile.networkPolicy == .disabled,
      reviewerProfile.pluginPolicy == .disabled,
      reviewerProfile.environmentPolicy == .minimalKernelAllowlist,
      reviewerProfile.providerReference == harness.providerReference,
      reviewerProfile.modelID == harness.modelID,
      reviewerProfile.executableContentDigest == harness.executableContentDigest,
      Self.validSHA256(reviewerProfile.executableContentDigest)
    else {
      throw NativeIndependentVisualReviewError.invalidReviewerProfile
    }
    guard !harness.identity.isEmpty,
      allowedHarnessIdentities.contains(harness.identity)
    else {
      throw NativeIndependentVisualReviewError.untrustedHarness
    }
    let reviewer = harness.reviewer
    guard !reviewer.id.rawValue.isEmpty,
      reviewer.role == "independentProductDesignReviewer",
      !reviewer.lineageDigest.rawValue.isEmpty,
      reviewer.lineageDigest != request.worker.lineageDigest
    else {
      throw NativeIndependentVisualReviewError.reviewerLineageNotIndependent
    }

    let contractedCells = Set(request.baseline.protectedInvariants.flatMap(\.cellIDs))
    let required = request.mutationManifest.requiredCellIDs
    guard request.mutationManifest.allBaselineCellIDs == contractedCells,
      !request.mutationManifest.directlyAffectedCellIDs.isEmpty,
      request.mutationManifest.directlyAffectedCellIDs.isSubset(of: contractedCells),
      !required.isEmpty,
      required.isSubset(of: contractedCells),
      let baselineByCell = request.baseline.captureByCell
    else {
      throw NativeIndependentVisualReviewError.invalidRequest(
        "mutation manifest must select a complete contracted matrix"
      )
    }

    let candidatePairs = request.candidateCaptures.map {
      ($0.attestation.receipt.cellID, $0)
    }
    guard Set(candidatePairs.map(\.0)).count == candidatePairs.count,
      Set(candidatePairs.map(\.0)) == required
    else {
      throw NativeIndependentVisualReviewError.incompleteCaptureMatrix
    }
    let candidateByCell = Dictionary(uniqueKeysWithValues: candidatePairs)

    var imagePairs: [NativeVisualReviewImagePair] = []
    for cell in required.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let baselineCapture = baselineByCell[cell],
        let baselineImage = request.baselineEncodedImages[cell],
        NativeVisualCaptureAdapter.encodedImage(
          baselineImage,
          matches: baselineCapture
        )
      else {
        throw NativeIndependentVisualReviewError.invalidBaselineImage(cell)
      }
      guard let candidateAuthority = candidateByCell[cell] else {
        throw NativeIndependentVisualReviewError.incompleteCaptureMatrix
      }
      let candidateCapture = candidateAuthority.attestation.receipt
      guard candidateCapture.isComplete,
        candidateCapture.sourceTree == request.candidateSourceTree,
        candidateCapture.builtArtifact == request.candidateBuiltArtifact,
        candidateCapture.captureProtocol == request.baseline.captureProtocol,
        candidateCapture.traits == baselineCapture.traits,
        candidateCapture.capturedAt >= request.mutationStartedAt,
        NativeVisualCaptureAdapter.encodedImage(
          candidateAuthority.encodedImage,
          matches: candidateCapture
        )
      else {
        throw NativeIndependentVisualReviewError.invalidCandidateCapture(cell)
      }
      imagePairs.append(
        NativeVisualReviewImagePair(
          cellID: cell,
          baselineReceipt: baselineCapture,
          candidateReceipt: candidateCapture,
          baselineEncodedImage: baselineImage,
          candidateEncodedImage: candidateAuthority.encodedImage
        ))
    }

    let measurableByCell = Dictionary(
      uniqueKeysWithValues: required.map { cell in
        let dimensions = Set(
          request.baseline.protectedInvariants.filter {
            $0.cellIDs.contains(cell)
              && $0.dimension != .provenanceAndComparability
              && $0.dimension != .independentProductDesignVerdict
          }.map(\.dimension))
        return (cell, dimensions)
      })
    let measurementPairs = request.measurements.map { ($0.measurement.cellID, $0) }
    guard Set(measurementPairs.map(\.0)).count == measurementPairs.count,
      Set(measurementPairs.map(\.0))
        == Set(
          measurableByCell.filter {
            !$0.value.isEmpty
          }.map(\.key))
    else {
      throw NativeIndependentVisualReviewError.incompleteMeasurementMatrix
    }
    let measurementByCell = Dictionary(uniqueKeysWithValues: measurementPairs)
    var debtSeverityByID: [DesignDebtID: Double] = [:]
    for pair in imagePairs {
      let expectedDimensions = measurableByCell[pair.cellID] ?? []
      if !expectedDimensions.isEmpty {
        guard let authority = measurementByCell[pair.cellID],
          authority.baselineCaptureID == pair.baselineReceipt.id,
          authority.candidateCaptureID == pair.candidateReceipt.id,
          authority.protectedDimensions == expectedDimensions,
          authority.measuredAt >= pair.candidateReceipt.capturedAt
        else {
          throw NativeIndependentVisualReviewError.invalidMeasurementAuthority(
            pair.cellID
          )
        }
        for (debtID, severity) in authority.debtSeverityByID {
          if let existing = debtSeverityByID[debtID], existing != severity {
            throw NativeIndependentVisualReviewError.invalidMeasurementAuthority(
              pair.cellID
            )
          }
          debtSeverityByID[debtID] = severity
        }
      }
    }
    let requiredDebtIDs = Set(
      request.baseline.knownDebt.filter {
        !$0.cellIDs.isDisjoint(with: required)
      }.map(\.id))
    guard Set(debtSeverityByID.keys) == requiredDebtIDs else {
      throw NativeIndependentVisualReviewError.incompleteMeasurementMatrix
    }

    let candidateCaptures = imagePairs.map(\.candidateReceipt)
    let measurements = imagePairs.compactMap {
      measurementByCell[$0.cellID]?.measurement
    }
    var candidate = VisualCandidateBundle(
      sourceTree: request.candidateSourceTree,
      builtArtifact: request.candidateBuiltArtifact,
      mutationStartedAt: request.mutationStartedAt,
      captures: candidateCaptures,
      measurements: measurements,
      mutationManifest: request.mutationManifest,
      debtSeverityByID: debtSeverityByID,
      reviewBatches: [],
      independentReview: nil,
      amendments: []
    )
    let deterministicDigest = DesignBaselineGate.deterministicEvidenceDigest(
      baseline: request.baseline,
      candidate: candidate
    )
    guard !deterministicDigest.rawValue.isEmpty else {
      throw NativeIndependentVisualReviewError.digestConstructionFailed
    }

    let captureDigests = Set(
      request.candidateCaptures.map {
        $0.attestation.attestationDigest
      })
    let measurementDigests = Set(request.measurements.map(\.attestationDigest))
    let baselineEncodedDigests = Dictionary(
      uniqueKeysWithValues: imagePairs.map {
        ($0.cellID.rawValue, Self.digest($0.baselineEncodedImage))
      })
    let candidateEncodedDigests = Dictionary(
      uniqueKeysWithValues: imagePairs.map {
        ($0.cellID.rawValue, Self.digest($0.candidateEncodedImage))
      })
    let evidenceContext = try Self.encoded(
      EvidenceEnvelope(
        baselineID: request.baseline.id,
        contractID: request.baseline.contractID,
        candidateSourceTree: request.candidateSourceTree,
        candidateBuiltArtifact: request.candidateBuiltArtifact,
        requiredCellIDs: required.sorted { $0.rawValue < $1.rawValue },
        baselineCaptures: imagePairs.map(\.baselineReceipt),
        candidateCaptures: candidateCaptures,
        measurements: measurements,
        debtSeverityByID: Dictionary(
          uniqueKeysWithValues:
            debtSeverityByID.map { ($0.key.rawValue, $0.value) }
        ),
        mutationManifest: request.mutationManifest,
        reviewerExecutionProfile: reviewerProfile,
        workerLineageDigest: request.worker.lineageDigest,
        captureAttestationDigests: captureDigests.sorted {
          $0.rawValue < $1.rawValue
        },
        measurementAttestationDigests: measurementDigests.sorted {
          $0.rawValue < $1.rawValue
        },
        baselineEncodedImageDigests: baselineEncodedDigests,
        candidateEncodedImageDigests: candidateEncodedDigests
      ))
    let evidenceBundleDigest = Self.digest(evidenceContext)
    let systemPrompt = Data(
      "Independently review every attached native before/after pair. Use only the exact evidence context; worker narrative is unavailable. Return one decision for every image and pair."
        .utf8
    )
    let userPrompt = Data(
      "Baseline \(request.baseline.id.rawValue); candidate \(request.candidateSourceTree.rawValue); deterministic evidence \(deterministicDigest.rawValue)."
        .utf8
    )
    let systemPromptDigest = Self.digest(systemPrompt)
    let userPromptDigest = Self.digest(userPrompt)
    let contextDigest = Self.digest(evidenceContext)
    let candidateIDs = Set(candidateCaptures.map(\.id))
    let plannedBatches = VisualReviewBatchPlanner.plan(
      candidateCaptureIDs: candidateIDs,
      maximumImagesPerBatch: request.maximumImagesPerBatch
    )
    let harnessRequest = NativeIndependentVisualReviewHarnessRequest(
      baselineID: request.baseline.id,
      candidateSourceTree: request.candidateSourceTree,
      deterministicResultsDigest: deterministicDigest,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      evidenceContext: evidenceContext,
      imagePairs: imagePairs,
      candidateBatches: plannedBatches
    )

    let output: NativeIndependentVisualReviewHarnessOutput
    do {
      output = try await harness.review(harnessRequest)
    } catch {
      throw NativeIndependentVisualReviewError.harnessFailed
    }
    let reviewedAt = clock()
    let latestMeasurement =
      request.measurements.map(\.measuredAt).max()
      ?? request.mutationStartedAt
    guard reviewedAt >= request.notBefore,
      reviewedAt >= latestMeasurement
    else {
      throw NativeIndependentVisualReviewError.reviewPredatesAuthorityBoundary
    }
    guard output.processExitCode == 0 else {
      throw NativeIndependentVisualReviewError.processFailed(output.processExitCode)
    }
    guard !output.rawResponse.isEmpty else {
      throw NativeIndependentVisualReviewError.emptyResponse
    }
    guard output.rawResponse.count <= maximumResponseBytes else {
      throw NativeIndependentVisualReviewError.responseTooLarge
    }
    let baselineIDs = Set(imagePairs.map(\.baselineReceipt.id))
    let expectedImageIDs = baselineIDs.union(candidateIDs)
    guard Set(output.perImageDecisions.keys) == expectedImageIDs,
      Set(output.pairDecisions.keys) == required,
      output.inspectedCellIDs == required
    else {
      throw NativeIndependentVisualReviewError.incompleteDecisionMatrix
    }

    let rawResponseDigest = Self.digest(output.rawResponse)
    let receiptMaterial = ReceiptEnvelope(
      evidenceBundleDigest: evidenceBundleDigest,
      deterministicResultsDigest: deterministicDigest,
      systemPromptDigest: systemPromptDigest,
      userPromptDigest: userPromptDigest,
      contextDigest: contextDigest,
      harnessIdentity: harness.identity,
      reviewer: reviewer,
      perImageDecisions: Dictionary(
        uniqueKeysWithValues:
          output.perImageDecisions.map { ($0.key.rawValue, $0.value) }
      ),
      pairDecisions: Dictionary(
        uniqueKeysWithValues:
          output.pairDecisions.map { ($0.key.rawValue, $0.value) }
      ),
      inspectedCellIDs: output.inspectedCellIDs.sorted {
        $0.rawValue < $1.rawValue
      },
      rawResponseDigest: rawResponseDigest,
      reviewedAt: reviewedAt
    )
    let requestDigest = try Self.digest(receiptMaterial)
    let batches = try plannedBatches.enumerated().map { index, ids in
      let batchDigest = try Self.digest([
        requestDigest.rawValue,
        String(index),
        ids.map(\.rawValue).joined(separator: ","),
      ])
      return VisualReviewBatchReceipt(
        id: ReceiptID("native-visual-review-batch-\(batchDigest.rawValue)"),
        candidateCaptureIDs: ids,
        verdictRecordedCaptureIDs: Set(ids)
      )
    }
    let decision: VisualReviewDecision =
      output.perImageDecisions.values.allSatisfy { $0 == .pass }
        && output.pairDecisions.values.allSatisfy { $0 == .pass }
      ? .pass : .fail
    let review = IndependentVisualReviewReceipt(
      id: ReceiptID("native-independent-visual-review-\(requestDigest.rawValue)"),
      reviewer: reviewer,
      workerLineageDigest: request.worker.lineageDigest,
      provider: reviewerProfile.providerReference,
      model: reviewerProfile.modelID,
      contextDigest: contextDigest,
      systemPromptDigest: systemPromptDigest,
      userPromptDigest: userPromptDigest,
      evidenceBundleDigest: evidenceBundleDigest,
      deterministicResultsDigest: deterministicDigest,
      baselineID: request.baseline.id,
      candidateSourceTree: request.candidateSourceTree,
      baselineCaptureIDs: baselineIDs,
      candidateCaptureIDs: candidateIDs,
      attachedImageDigests: imagePairs.flatMap {
        [$0.baselineReceipt.imageDigest, $0.candidateReceipt.imageDigest]
      },
      perImageDecisions: output.perImageDecisions,
      pairDecisions: output.pairDecisions,
      inspectedCellIDs: output.inspectedCellIDs,
      batchReceiptIDs: Set(batches.map(\.id)),
      blindToWorkerNarrative: true,
      decision: decision,
      rawResponseDigest: rawResponseDigest
    )
    candidate.reviewBatches = batches
    candidate.independentReview = review
    return AuthorizedNativeIndependentVisualReview(
      candidate: candidate,
      requestDigest: requestDigest,
      captureAttestationDigests: captureDigests,
      measurementAttestationDigests: measurementDigests,
      reviewerExecutionProfile: reviewerProfile,
      worker: request.worker,
      reviewedAt: reviewedAt
    )
  }

  private nonisolated static func validSHA256(_ digest: ContentDigest) -> Bool {
    digest.rawValue.count == 64
      && digest.rawValue == digest.rawValue.lowercased()
      && digest.rawValue.allSatisfy(\.isHexDigit)
  }

  private nonisolated static func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    guard let data = try? encoder.encode(value) else {
      throw NativeIndependentVisualReviewError.digestConstructionFailed
    }
    return data
  }

  private nonisolated static func digest<T: Encodable>(
    _ value: T
  ) throws -> ContentDigest {
    digest(try encoded(value))
  }

  private nonisolated static func digest(_ data: Data) -> ContentDigest {
    ContentDigest(
      SHA256.hash(data: data).map {
        String(format: "%02x", $0)
      }.joined())
  }
}
