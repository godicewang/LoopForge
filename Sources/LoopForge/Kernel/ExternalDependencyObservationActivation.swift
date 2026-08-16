import CryptoKit
import Darwin
import Foundation

/// Canonical request bytes delivered on the observer's standard-input
/// descriptor. The nonce is replay-stable for one exact journal activation,
/// but changes with any run, attempt, dependency, actor, receipt, or source
/// frame identity.
struct ExternalDependencyObservationRequestEnvelope:
  Codable, Hashable, Sendable
{
  var attemptID: AttemptID
  var dependencyID: ExternalDependencyID
  var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
  var observerLineageDigest: ContentDigest
  var requestNonce: ContentDigest
  var runID: KernelRunID
  var schemaVersion: Int
  var sourceJournalFrameDigest: ContentDigest
  var sourceJournalSequence: UInt64
}

struct ExternalDependencyObservationRequestArtifactReceipt:
  Codable, Hashable, Sendable
{
  var runID: KernelRunID
  var attemptID: AttemptID
  var dependencyID: ExternalDependencyID
  var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
  var observerLineageDigest: ContentDigest
  var requestNonce: ContentDigest
  var sourceJournalSequence: UInt64
  var sourceJournalFrameDigest: ContentDigest
  var fileName: String
  var contentDigest: ContentDigest
  var byteCount: UInt64
  var deviceID: UInt64
  var inode: UInt64
}

/// A decoded request receipt is evidence only. The live wrapper can be issued
/// solely by descriptor-relative materialization or exact revalidation inside
/// the owner-private journal run directory.
struct AuthorizedExternalDependencyObservationRequestArtifact: Sendable {
  let receipt: ExternalDependencyObservationRequestArtifactReceipt

  fileprivate init(
    receipt: ExternalDependencyObservationRequestArtifactReceipt
  ) {
    self.receipt = receipt
  }
}

enum ExternalDependencyObservationRequestArtifactError:
  Error, Equatable
{
  case invalidEnvelope
  case invalidRunDirectory
  case createFailed(errno: Int32)
  case writeFailed(errno: Int32)
  case durabilityFailed(errno: Int32)
  case existingArtifactMismatch
  case metadataMismatch
}

/// Creates or crash-recovers exactly one immutable, canonical request file.
/// Existing bytes are accepted only when their digest, inode metadata, and
/// complete expected envelope match the current activation.
struct ExternalDependencyObservationRequestArtifactIssuer: Sendable {
  static let maximumRequestBytes = 64 * 1_024

  func materialize(
    envelope: ExternalDependencyObservationRequestEnvelope,
    receiptID: ReceiptID,
    journalRunDirectory: URL
  ) throws -> AuthorizedExternalDependencyObservationRequestArtifact {
    guard Self.envelopeIsValid(envelope),
      !receiptID.rawValue.isEmpty
    else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidEnvelope
    }
    let data = try Self.canonicalData(envelope)
    guard !data.isEmpty, data.count <= Self.maximumRequestBytes else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidEnvelope
    }
    let fileName = Self.fileName(receiptID: receiptID)
    let directoryDescriptor = Darwin.open(
      journalRunDirectory.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard directoryDescriptor >= 0 else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidRunDirectory
    }
    defer { _ = Darwin.close(directoryDescriptor) }
    try Self.validateRunDirectory(descriptor: directoryDescriptor)

    let descriptor = fileName.withCString {
      Darwin.openat(
        directoryDescriptor,
        $0,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        0o600
      )
    }
    if descriptor < 0 {
      guard errno == EEXIST else {
        throw
          ExternalDependencyObservationRequestArtifactError
          .createFailed(errno: errno)
      }
      return try revalidate(
        expectedEnvelope: envelope,
        receiptID: receiptID,
        journalRunDirectory: journalRunDirectory
      )
    }
    var committed = false
    defer {
      _ = Darwin.close(descriptor)
      if !committed {
        _ = fileName.withCString {
          Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
      }
    }
    do {
      try data.withUnsafeBytes { try Self.writeAll($0, to: descriptor) }
    } catch {
      throw error
    }
    guard Darwin.fchmod(descriptor, 0o400) == 0,
      Darwin.fsync(descriptor) == 0
    else {
      throw
        ExternalDependencyObservationRequestArtifactError
        .durabilityFailed(errno: errno)
    }
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      status.st_size == data.count,
      status.st_mode & 0o222 == 0
    else {
      throw ExternalDependencyObservationRequestArtifactError
        .metadataMismatch
    }
    guard Darwin.fsync(directoryDescriptor) == 0 else {
      throw
        ExternalDependencyObservationRequestArtifactError
        .durabilityFailed(errno: errno)
    }
    committed = true
    return AuthorizedExternalDependencyObservationRequestArtifact(
      receipt: Self.receipt(
        envelope: envelope,
        fileName: fileName,
        data: data,
        status: status
      )
    )
  }

  func revalidate(
    expectedEnvelope: ExternalDependencyObservationRequestEnvelope,
    receiptID: ReceiptID,
    journalRunDirectory: URL,
    matching expectedReceipt:
      ExternalDependencyObservationRequestArtifactReceipt? = nil
  ) throws -> AuthorizedExternalDependencyObservationRequestArtifact {
    guard Self.envelopeIsValid(expectedEnvelope),
      !receiptID.rawValue.isEmpty
    else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidEnvelope
    }
    let data = try Self.canonicalData(expectedEnvelope)
    guard !data.isEmpty, data.count <= Self.maximumRequestBytes else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidEnvelope
    }
    let fileName = Self.fileName(receiptID: receiptID)
    let directoryDescriptor = Darwin.open(
      journalRunDirectory.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard directoryDescriptor >= 0 else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidRunDirectory
    }
    defer { _ = Darwin.close(directoryDescriptor) }
    try Self.validateRunDirectory(descriptor: directoryDescriptor)
    let descriptor = fileName.withCString {
      Darwin.openat(
        directoryDescriptor,
        $0,
        O_RDONLY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    guard descriptor >= 0 else {
      throw ExternalDependencyObservationRequestArtifactError
        .existingArtifactMismatch
    }
    defer { _ = Darwin.close(descriptor) }
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFREG,
      status.st_uid == geteuid(),
      status.st_nlink == 1,
      status.st_size == data.count,
      status.st_mode & 0o222 == 0,
      Darwin.lseek(descriptor, 0, SEEK_SET) == 0,
      let observed = try? Self.readAll(
        descriptor: descriptor,
        maximumBytes: Self.maximumRequestBytes
      ),
      observed == data
    else {
      throw ExternalDependencyObservationRequestArtifactError
        .existingArtifactMismatch
    }
    let receipt = Self.receipt(
      envelope: expectedEnvelope,
      fileName: fileName,
      data: data,
      status: status
    )
    guard expectedReceipt == nil || expectedReceipt == receipt else {
      throw ExternalDependencyObservationRequestArtifactError
        .existingArtifactMismatch
    }
    return AuthorizedExternalDependencyObservationRequestArtifact(
      receipt: receipt
    )
  }

  static func expectedReceiptIsValid(
    _ receipt: ExternalDependencyObservationRequestArtifactReceipt,
    envelope: ExternalDependencyObservationRequestEnvelope,
    receiptID: ReceiptID
  ) -> Bool {
    guard envelopeIsValid(envelope),
      !receiptID.rawValue.isEmpty,
      let data = try? canonicalData(envelope),
      !data.isEmpty,
      data.count <= maximumRequestBytes
    else {
      return false
    }
    return receipt.runID == envelope.runID
      && receipt.attemptID == envelope.attemptID
      && receipt.dependencyID == envelope.dependencyID
      && receipt.evidenceRecipeID == envelope.evidenceRecipeID
      && receipt.observerLineageDigest == envelope.observerLineageDigest
      && receipt.requestNonce == envelope.requestNonce
      && receipt.sourceJournalSequence == envelope.sourceJournalSequence
      && receipt.sourceJournalFrameDigest == envelope.sourceJournalFrameDigest
      && receipt.fileName == fileName(receiptID: receiptID)
      && receipt.contentDigest == digest(data)
      && receipt.byteCount == UInt64(data.count)
      && receipt.deviceID > 0
      && receipt.inode > 0
  }

  static func fileName(receiptID: ReceiptID) -> String {
    let identity = digest(Data(receiptID.rawValue.utf8)).rawValue
    return "external-dependency-request-\(identity).json"
  }

  static func canonicalData(
    _ envelope: ExternalDependencyObservationRequestEnvelope
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(envelope)
    data.append(0x0a)
    return data
  }

  private static func receipt(
    envelope: ExternalDependencyObservationRequestEnvelope,
    fileName: String,
    data: Data,
    status: stat
  ) -> ExternalDependencyObservationRequestArtifactReceipt {
    ExternalDependencyObservationRequestArtifactReceipt(
      runID: envelope.runID,
      attemptID: envelope.attemptID,
      dependencyID: envelope.dependencyID,
      evidenceRecipeID: envelope.evidenceRecipeID,
      observerLineageDigest: envelope.observerLineageDigest,
      requestNonce: envelope.requestNonce,
      sourceJournalSequence: envelope.sourceJournalSequence,
      sourceJournalFrameDigest: envelope.sourceJournalFrameDigest,
      fileName: fileName,
      contentDigest: digest(data),
      byteCount: UInt64(data.count),
      deviceID: UInt64(bitPattern: Int64(status.st_dev)),
      inode: UInt64(status.st_ino)
    )
  }

  private static func writeAll(
    _ buffer: UnsafeRawBufferPointer,
    to descriptor: Int32
  ) throws {
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
        throw
          ExternalDependencyObservationRequestArtifactError
          .writeFailed(errno: errno)
      }
    }
  }

  private static func readAll(
    descriptor: Int32,
    maximumBytes: Int
  ) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
    while true {
      let count = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if count > 0 {
        result.append(buffer, count: count)
        guard result.count <= maximumBytes else {
          throw ExternalDependencyObservationRequestArtifactError
            .existingArtifactMismatch
        }
      } else if count == 0 {
        return result
      } else if errno != EINTR {
        throw ExternalDependencyObservationRequestArtifactError
          .existingArtifactMismatch
      }
    }
  }

  private static func digest(_ data: Data) -> ContentDigest {
    ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
  }

  private static func envelopeIsValid(
    _ envelope: ExternalDependencyObservationRequestEnvelope
  ) -> Bool {
    envelope.schemaVersion == 1
      && !envelope.runID.rawValue.isEmpty
      && !envelope.attemptID.rawValue.isEmpty
      && !envelope.dependencyID.rawValue.isEmpty
      && !envelope.evidenceRecipeID.rawValue.isEmpty
      && ExternalDependencyObservationProbe.validSHA256(
        envelope.observerLineageDigest
      )
      && ExternalDependencyObservationProbe.validSHA256(
        envelope.requestNonce
      )
      && ExternalDependencyObservationProbe.validSHA256(
        envelope.sourceJournalFrameDigest
      )
  }

  private static func validateRunDirectory(descriptor: Int32) throws {
    var status = stat()
    guard Darwin.fstat(descriptor, &status) == 0,
      status.st_mode & S_IFMT == S_IFDIR,
      status.st_uid == geteuid(),
      status.st_mode & 0o077 == 0
    else {
      throw ExternalDependencyObservationRequestArtifactError
        .invalidRunDirectory
    }
  }
}

struct ExternalDependencyObservationActivationReceipt:
  Codable, Hashable, Sendable
{
  var schemaVersion: Int
  var id: ReceiptID
  var runID: KernelRunID
  var attemptID: AttemptID
  var dependencyID: ExternalDependencyID
  var requirementIDs: Set<RequirementID>
  var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
  var observer: ActorIdentity
  var workerLineageDigest: ContentDigest
  var workspaceRootPath: String
  var workspaceRootPathDigest: ContentDigest
  var executableStaging: KernelExecutableStagingReceipt
  var probeDigest: ContentDigest
  var requestArtifact: ExternalDependencyObservationRequestArtifactReceipt
  var resolvedArguments: [String]
  var argumentVectorDigest: ContentDigest
  var environmentIdentityDigest: ContentDigest
  var captureIdentityDigest: ContentDigest
  var parser: ExternalDependencyObservationParserContract
  var resultMappings: [ExternalDependencyObservationResultMapping]
  var networkPolicy: KernelNetworkPolicy
  var resourceLimits: RequirementVerificationResourceLimits
  var sourceJournalSequence: UInt64
  var sourceJournalFrameDigest: ContentDigest
  var activatedAt: Date
}

struct AuthorizedExternalDependencyObservationActivation: Sendable {
  let receipt: ExternalDependencyObservationActivationReceipt

  private init(receipt: ExternalDependencyObservationActivationReceipt) {
    self.receipt = receipt
  }

  fileprivate static func issued(
    _ receipt: ExternalDependencyObservationActivationReceipt
  ) -> AuthorizedExternalDependencyObservationActivation {
    AuthorizedExternalDependencyObservationActivation(receipt: receipt)
  }

  #if DEBUG
    static func testOnly(
      _ receipt: ExternalDependencyObservationActivationReceipt
    ) -> AuthorizedExternalDependencyObservationActivation {
      AuthorizedExternalDependencyObservationActivation(receipt: receipt)
    }
  #endif
}

struct AuthorizedExternalDependencyObservationInvocation: Sendable {
  let receipt: ExternalDependencyObservationActivationReceipt
  let activationTransaction: JournalTransactionReceipt
  let requestArtifact: AuthorizedExternalDependencyObservationRequestArtifact

  fileprivate init(
    receipt: ExternalDependencyObservationActivationReceipt,
    activationTransaction: JournalTransactionReceipt,
    requestArtifact:
      AuthorizedExternalDependencyObservationRequestArtifact
  ) {
    self.receipt = receipt
    self.activationTransaction = activationTransaction
    self.requestArtifact = requestArtifact
  }
}

struct ExternalDependencyObservationActivationRequest: Sendable {
  var receiptID: ReceiptID
  var commandID: RunCommandID
  var dependencyID: ExternalDependencyID
  var observer: ActorIdentity
  var executablePath: String
  var workspaceRoot: URL
  var activatedAt: Date
}

enum ExternalDependencyObservationActivationError: Error, Equatable {
  case invalidActor
  case invalidRunState
  case dependencyNotAuthorized
  case observerNotAuthorized
  case workspaceMismatch
  case executableStagingFailed
  case requestMaterializationFailed
  case journalRejected(KernelRejection)
  case journalWriteFailed
  case journalReceiptMismatch
}

enum ExternalDependencyObservationActivationCompiler {
  static let requestDescriptorPath = "/dev/stdin"

  static func probeDigest(
    _ probe: ExternalDependencyObservationExecutableProbe
  ) -> ContentDigest? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(probe) else { return nil }
    return ExternalDependencyObservationProbe.digest(data)
  }

  static func requestNonce(
    runID: KernelRunID,
    attemptID: AttemptID,
    dependencyID: ExternalDependencyID,
    evidenceRecipeID: ExternalDependencyEvidenceRecipeID,
    observerLineageDigest: ContentDigest,
    receiptID: ReceiptID,
    sourceJournalSequence: UInt64,
    sourceJournalFrameDigest: ContentDigest
  ) -> ContentDigest {
    let material = [
      "loopforge.external-dependency-request-nonce.v1",
      runID.rawValue,
      attemptID.rawValue,
      dependencyID.rawValue,
      evidenceRecipeID.rawValue,
      observerLineageDigest.rawValue,
      receiptID.rawValue,
      String(sourceJournalSequence),
      sourceJournalFrameDigest.rawValue,
    ].joined(separator: "\u{1f}")
    return ExternalDependencyObservationProbe.digest(Data(material.utf8))
  }

  static func envelope(
    receipt: ExternalDependencyObservationActivationReceipt
  ) -> ExternalDependencyObservationRequestEnvelope {
    ExternalDependencyObservationRequestEnvelope(
      attemptID: receipt.attemptID,
      dependencyID: receipt.dependencyID,
      evidenceRecipeID: receipt.evidenceRecipeID,
      observerLineageDigest: receipt.observer.lineageDigest,
      requestNonce: receipt.requestArtifact.requestNonce,
      runID: receipt.runID,
      schemaVersion: 1,
      sourceJournalFrameDigest: receipt.sourceJournalFrameDigest,
      sourceJournalSequence: receipt.sourceJournalSequence
    )
  }

  static func receipt(
    _ receipt: ExternalDependencyObservationActivationReceipt,
    matches probe: ExternalDependencyObservationExecutableProbe
  ) -> Bool {
    let expectedArguments = probe.fixedArguments.map {
      $0
        == ExternalDependencyObservationExecutableProbe
        .requestArgumentToken ? requestDescriptorPath : $0
    }
    let envelope = envelope(receipt: receipt)
    return receipt.schemaVersion == 1
      && receipt.executableStaging.contentDigest == probe.executableContentDigest
      && receipt.probeDigest == probeDigest(probe)
      && receipt.resolvedArguments == expectedArguments
      && receipt.argumentVectorDigest
        == KernelProviderInvocationCompiler.argumentVectorDigest(
          expectedArguments
        )
      && receipt.environmentIdentityDigest == probe.environmentIdentityDigest
      && receipt.captureIdentityDigest == probe.captureIdentityDigest
      && receipt.parser == probe.parser
      && receipt.resultMappings == probe.resultMappings
      && receipt.networkPolicy == probe.networkPolicy
      && receipt.resourceLimits == probe.resourceLimits
      && receipt.requestArtifact.requestNonce
        == requestNonce(
          runID: receipt.runID,
          attemptID: receipt.attemptID,
          dependencyID: receipt.dependencyID,
          evidenceRecipeID: receipt.evidenceRecipeID,
          observerLineageDigest: receipt.observer.lineageDigest,
          receiptID: receipt.id,
          sourceJournalSequence: receipt.sourceJournalSequence,
          sourceJournalFrameDigest: receipt.sourceJournalFrameDigest
        )
      && ExternalDependencyObservationRequestArtifactIssuer
        .expectedReceiptIsValid(
          receipt.requestArtifact,
          envelope: envelope,
          receiptID: receipt.id
        )
  }

  static func validationIssue(
    _ receipt: ExternalDependencyObservationActivationReceipt,
    state: KernelRunState,
    actor: ActorIdentity,
    occurredAt: Date
  ) -> String? {
    guard receipt.schemaVersion == 1,
      receipt.runID == state.runID,
      receipt.observer == actor,
      receipt.activatedAt == occurredAt,
      receipt.sourceJournalSequence == state.sequence,
      ExternalDependencyObservationProbe.validSHA256(
        receipt.sourceJournalFrameDigest
      ),
      state.phase == .executing,
      state.activeAttemptID == receipt.attemptID,
      let attempt = state.attempts[receipt.attemptID],
      attempt.disposition == nil,
      receipt.workerLineageDigest == attempt.worker.lineageDigest,
      receipt.observer.lineageDigest != attempt.worker.lineageDigest,
      let contract = state.contract,
      let dependency = (contract.externalDependencies ?? [])
        .first(where: { $0.id == receipt.dependencyID }),
      (contract.externalDependencies ?? []).filter({
        $0.id == receipt.dependencyID
      }).count == 1,
      dependency.evidenceRecipeID == receipt.evidenceRecipeID,
      dependency.authorizedObserverLineageDigests.contains(
        receipt.observer.lineageDigest
      ),
      receipt.requirementIDs
        == dependency.requirementIDs
        .intersection(attempt.requirementIDs),
      !receipt.requirementIDs.isEmpty,
      let probe = dependency.executableProbe,
      probe.validationIssues().isEmpty,
      let workspace = contract.workspaceBinding,
      receipt.workspaceRootPath.hasPrefix("/"),
      receipt.workspaceRootPathDigest == workspace.canonicalRootDigest,
      receipt.workspaceRootPathDigest
        == WorkspaceRepositoryIndexer.canonicalRootDigest(
          URL(
            fileURLWithPath: receipt.workspaceRootPath,
            isDirectory: true
          )),
      self.receipt(receipt, matches: probe),
      !(state.externalDependencyObservationActivationReceipts ?? [:])
        .values.contains(where: {
          $0.attemptID == receipt.attemptID
            && $0.dependencyID == receipt.dependencyID
        })
    else {
      return "external dependency observation activation provenance mismatch"
    }
    return nil
  }
}

/// Stages one exact observer and journals one inert, nonce-bound invocation.
/// It starts no process and cannot mint availability evidence.
actor ExternalDependencyObservationActivationCoordinator {
  private let journal: RunJournal

  init(journal: RunJournal) {
    self.journal = journal
  }

  func activate(
    _ request: ExternalDependencyObservationActivationRequest
  ) async throws -> AuthorizedExternalDependencyObservationInvocation {
    guard !request.receiptID.rawValue.isEmpty,
      !request.commandID.rawValue.isEmpty,
      !request.observer.id.rawValue.isEmpty,
      !request.observer.role.isEmpty,
      ExternalDependencyObservationProbe.validSHA256(
        request.observer.lineageDigest
      )
    else {
      throw ExternalDependencyObservationActivationError.invalidActor
    }
    let state = await journal.state
    guard state.phase == .executing,
      state.activeAttemptID != nil,
      let attemptID = state.activeAttemptID,
      let attempt = state.attempts[attemptID],
      attempt.disposition == nil,
      let contract = state.contract,
      let dependency = (contract.externalDependencies ?? [])
        .first(where: { $0.id == request.dependencyID }),
      (contract.externalDependencies ?? []).filter({
        $0.id == request.dependencyID
      }).count == 1,
      let probe = dependency.executableProbe,
      probe.validationIssues().isEmpty
    else {
      throw ExternalDependencyObservationActivationError.invalidRunState
    }
    guard request.observer.lineageDigest != attempt.worker.lineageDigest,
      dependency.authorizedObserverLineageDigests.contains(
        request.observer.lineageDigest
      )
    else {
      throw ExternalDependencyObservationActivationError
        .observerNotAuthorized
    }
    let requirementIDs = dependency.requirementIDs.intersection(
      attempt.requirementIDs
    )
    guard !requirementIDs.isEmpty else {
      throw ExternalDependencyObservationActivationError
        .dependencyNotAuthorized
    }
    let workspace: URL
    do {
      workspace =
        try KernelNativeSandboxAuthorizer
        .physicalDirectoryURL(request.workspaceRoot)
    } catch {
      throw ExternalDependencyObservationActivationError
        .workspaceMismatch
    }
    guard let workspaceBinding = contract.workspaceBinding,
      WorkspaceRepositoryIndexer.canonicalRootDigest(workspace)
        == workspaceBinding.canonicalRootDigest
    else {
      throw ExternalDependencyObservationActivationError
        .workspaceMismatch
    }
    let staging: KernelExecutableStagingReceipt
    do {
      staging = try KernelExecutableStager().stage(
        executablePath: request.executablePath,
        expectedDigest: probe.executableContentDigest,
        runDirectory: journal.runDirectory
      )
    } catch {
      throw ExternalDependencyObservationActivationError
        .executableStagingFailed
    }
    guard
      let exactProbeDigest =
        ExternalDependencyObservationActivationCompiler
        .probeDigest(probe)
    else {
      throw ExternalDependencyObservationActivationError
        .dependencyNotAuthorized
    }
    let head = await journal.headSnapshot()
    guard head.sequence == state.sequence,
      let sourceFrameDigest = head.frameDigest
    else {
      throw ExternalDependencyObservationActivationError.invalidRunState
    }
    let nonce =
      ExternalDependencyObservationActivationCompiler
      .requestNonce(
        runID: state.runID,
        attemptID: attemptID,
        dependencyID: dependency.id,
        evidenceRecipeID: dependency.evidenceRecipeID,
        observerLineageDigest: request.observer.lineageDigest,
        receiptID: request.receiptID,
        sourceJournalSequence: head.sequence,
        sourceJournalFrameDigest: sourceFrameDigest
      )
    let envelope = ExternalDependencyObservationRequestEnvelope(
      attemptID: attemptID,
      dependencyID: dependency.id,
      evidenceRecipeID: dependency.evidenceRecipeID,
      observerLineageDigest: request.observer.lineageDigest,
      requestNonce: nonce,
      runID: state.runID,
      schemaVersion: 1,
      sourceJournalFrameDigest: sourceFrameDigest,
      sourceJournalSequence: head.sequence
    )
    let prior =
      (state
      .externalDependencyObservationActivationReceipts ?? [:])
      .values.filter {
        $0.attemptID == attemptID
          && $0.dependencyID == dependency.id
      }
    if let retained = prior.first {
      let artifact: AuthorizedExternalDependencyObservationRequestArtifact
      do {
        artifact = try ExternalDependencyObservationRequestArtifactIssuer()
          .revalidate(
            expectedEnvelope:
              ExternalDependencyObservationActivationCompiler
              .envelope(receipt: retained),
            receiptID: retained.id,
            journalRunDirectory: journal.runDirectory,
            matching: retained.requestArtifact
          )
      } catch {
        throw ExternalDependencyObservationActivationError
          .requestMaterializationFailed
      }
      let replayHead = await journal.headSnapshot()
      guard replayHead.sequence == state.sequence,
        prior.count == 1,
        retained.id == request.receiptID,
        retained.observer == request.observer,
        retained.activatedAt == request.activatedAt,
        retained.workspaceRootPath == workspace.path,
        retained.executableStaging.stagedExecutablePath == staging.stagedExecutablePath,
        retained.executableStaging.contentDigest == staging.contentDigest,
        retained.executableStaging.byteCount == staging.byteCount,
        retained.executableStaging.deviceID == staging.deviceID,
        retained.executableStaging.inode == staging.inode,
        ExternalDependencyObservationActivationCompiler.receipt(
          retained,
          matches: probe
        ),
        let transaction = await journal.transactionReceipt(
          commandID: request.commandID
        ),
        await journal
          .externalDependencyObservationActivationReceipt(
            transaction: transaction
          ) == retained
      else {
        throw ExternalDependencyObservationActivationError
          .invalidRunState
      }
      return AuthorizedExternalDependencyObservationInvocation(
        receipt: retained,
        activationTransaction: transaction,
        requestArtifact: artifact
      )
    }
    let artifact: AuthorizedExternalDependencyObservationRequestArtifact
    do {
      artifact = try ExternalDependencyObservationRequestArtifactIssuer()
        .materialize(
          envelope: envelope,
          receiptID: request.receiptID,
          journalRunDirectory: journal.runDirectory
        )
    } catch {
      throw ExternalDependencyObservationActivationError
        .requestMaterializationFailed
    }
    let resolvedArguments = probe.fixedArguments.map {
      $0
        == ExternalDependencyObservationExecutableProbe
        .requestArgumentToken
        ? ExternalDependencyObservationActivationCompiler
          .requestDescriptorPath
        : $0
    }
    let receipt = ExternalDependencyObservationActivationReceipt(
      schemaVersion: 1,
      id: request.receiptID,
      runID: state.runID,
      attemptID: attemptID,
      dependencyID: dependency.id,
      requirementIDs: requirementIDs,
      evidenceRecipeID: dependency.evidenceRecipeID,
      observer: request.observer,
      workerLineageDigest: attempt.worker.lineageDigest,
      workspaceRootPath: workspace.path,
      workspaceRootPathDigest: workspaceBinding.canonicalRootDigest,
      executableStaging: staging,
      probeDigest: exactProbeDigest,
      requestArtifact: artifact.receipt,
      resolvedArguments: resolvedArguments,
      argumentVectorDigest:
        KernelProviderInvocationCompiler
        .argumentVectorDigest(resolvedArguments),
      environmentIdentityDigest: probe.environmentIdentityDigest,
      captureIdentityDigest: probe.captureIdentityDigest,
      parser: probe.parser,
      resultMappings: probe.resultMappings,
      networkPolicy: probe.networkPolicy,
      resourceLimits: probe.resourceLimits,
      sourceJournalSequence: head.sequence,
      sourceJournalFrameDigest: sourceFrameDigest,
      activatedAt: request.activatedAt
    )
    let transaction: JournalTransactionReceipt
    do {
      transaction = try await journal.transactAtCurrentSequence(
        .activateExternalDependencyObservation(.issued(receipt)),
        commandID: request.commandID,
        issuedAt: request.activatedAt,
        actor: request.observer
      )
    } catch RunJournalError.reducerRejected(let rejection) {
      throw
        ExternalDependencyObservationActivationError
        .journalRejected(rejection)
    } catch {
      throw ExternalDependencyObservationActivationError
        .journalWriteFailed
    }
    guard !transaction.duplicate,
      await journal.externalDependencyObservationActivationReceipt(
        transaction: transaction
      ) == receipt
    else {
      throw ExternalDependencyObservationActivationError
        .journalReceiptMismatch
    }
    return AuthorizedExternalDependencyObservationInvocation(
      receipt: receipt,
      activationTransaction: transaction,
      requestArtifact: artifact
    )
  }
}
