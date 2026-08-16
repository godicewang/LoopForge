import CryptoKit
import Foundation

/// Durable evidence that the exact before/after bytes for a completed
/// pre-apply candidate were installed in the immutable external object store.
/// This is deliberately a distinct preflight-side chain: it does not depend on
/// an integration apply event and cannot itself authorize a manifest or effect.
struct WorkspaceCompletedCandidateMutationContentStoreReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var derivation: WorkspaceMutationOperationDerivationReceipt
    var completedCandidateCaptureReceiptDigest: ContentDigest
    var completedCandidateCaptureJournalFrameDigest: ContentDigest
    var baselineCaptureReceiptDigest: ContentDigest
    var verificationReceipt: WorkspaceMutationContentObjectSetReceipt
    var objectStoreReceipt: WorkspaceMutationContentObjectStoreReceipt
    var storedBy: ActorIdentity
    var storedAt: Date
    var receiptDigest: ContentDigest

    var derivationDigest: ContentDigest { derivation.derivationDigest }

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported completed-candidate content-store schema")
        }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || attemptID.rawValue.isEmpty || nodeID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty || storedBy.id.rawValue.isEmpty
            || storedBy.role.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || storedBy.lineageDigest.rawValue.isEmpty {
            issues.append("completed-candidate content-store identity is incomplete")
        }
        for digest in [
            canonicalRootDigest,
            completedCandidateCaptureReceiptDigest,
            completedCandidateCaptureJournalFrameDigest,
            baselineCaptureReceiptDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("completed-candidate content-store digest is invalid")
        }
        issues.append(contentsOf: derivation.validationIssues())
        issues.append(contentsOf: verificationReceipt.validationIssues())
        issues.append(contentsOf: objectStoreReceipt.validationIssues())
        if derivation.workspaceID != workspaceID
            || derivation.canonicalRootDigest != canonicalRootDigest
            || verificationReceipt.derivationDigest != derivation.derivationDigest
            || verificationReceipt.baseSourceRevision !=
                derivation.baseSourceRevision
            || verificationReceipt.candidateSourceRevision !=
                derivation.candidateSourceRevision
            || verificationReceipt.contentObjects != derivation.contentObjects
            || objectStoreReceipt.verificationReceiptDigest !=
                verificationReceipt.receiptDigest
            || objectStoreReceipt.derivationDigest != derivation.derivationDigest
            || objectStoreReceipt.objectSetDigest !=
                verificationReceipt.objectSetDigest
            || objectStoreReceipt.objectCount != verificationReceipt.objectCount
            || objectStoreReceipt.totalBytes != verificationReceipt.totalBytes {
            issues.append(
                "completed-candidate content-store composition is inconsistent"
            )
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("completed-candidate content-store receipt digest mismatch")
        }
        return issues
    }

    static func digest(
        for receipt: WorkspaceCompletedCandidateMutationContentStoreReceipt
    ) -> ContentDigest? {
        var material = receipt
        material.receiptDigest = ContentDigest("")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(material) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

/// Live proof that the stored artifact descends from the exact captured
/// candidate bytes and exact ratified baseline bytes. Recovered receipt data
/// cannot manufacture this capability.
struct AuthorizedWorkspaceCompletedCandidateMutationContentStore: Sendable {
    let receipt: WorkspaceCompletedCandidateMutationContentStoreReceipt
    let completedCandidate: AuthorizedWorkspaceCompletedCandidateCapture
    let baseline: AuthorizedWorkspaceRatifiedBaselineContent
    let objects: [WorkspaceMutationContentObject]

    fileprivate init(
        receipt: WorkspaceCompletedCandidateMutationContentStoreReceipt,
        completedCandidate: AuthorizedWorkspaceCompletedCandidateCapture,
        baseline: AuthorizedWorkspaceRatifiedBaselineContent,
        objects: [WorkspaceMutationContentObject]
    ) {
        self.receipt = receipt
        self.completedCandidate = completedCandidate
        self.baseline = baseline
        self.objects = objects
    }

    func journalValidationIssues() -> [String] {
        var issues = receipt.validationIssues()
        issues.append(contentsOf: completedCandidate.validationIssues())
        issues.append(contentsOf: baseline.validationIssues())
        let references = objects.sorted {
            $0.digest.rawValue < $1.digest.rawValue
        }.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        if receipt.runID != completedCandidate.receipt.runID
            || receipt.contractID != completedCandidate.receipt.contractID
            || receipt.attemptID != completedCandidate.receipt.attemptID
            || receipt.nodeID != completedCandidate.receipt.nodeID
            || receipt.workspaceID != completedCandidate.receipt.workspaceID
            || receipt.canonicalRootDigest !=
                completedCandidate.receipt.canonicalRootDigest
            || receipt.completedCandidateCaptureReceiptDigest !=
                completedCandidate.receipt.receiptDigest
            || receipt.baselineCaptureReceiptDigest != baseline.receipt.receiptDigest
            || receipt.runID != baseline.receipt.runID
            || receipt.contractID != baseline.receipt.contractID
            || receipt.workspaceID != baseline.receipt.workspaceID
            || receipt.canonicalRootDigest != baseline.receipt.canonicalRootDigest
            || receipt.derivation.baseSourceRevision !=
                baseline.receipt.baseSourceRevision
            || receipt.derivation.candidateSourceRevision !=
                completedCandidate.receipt.candidateSourceRevision
            || receipt.derivation.capturePolicyDigest !=
                completedCandidate.receipt.capturePolicyDigest
            || references != receipt.verificationReceipt.contentObjects
            || WorkspaceMutationFilesystemExecutor.objectSetDigest(objects) !=
                receipt.verificationReceipt.objectSetDigest
            || objects.contains(where: {
                WorkspaceMutationFilesystemExecutor.contentDigest($0.data) !=
                    $0.digest
            }) {
            issues.append(
                "completed-candidate content-store live authority is inconsistent"
            )
        }
        return issues
    }

    func externalArtifactValidationIssues() -> [String] {
        do {
            let observed = try WorkspaceMutationContentObjectStore().revalidate(
                receipt.objectStoreReceipt,
                verification: receipt.verificationReceipt
            )
            return observed == receipt.objectStoreReceipt
                ? [] : ["completed-candidate object store changed"]
        } catch {
            return ["completed-candidate object store cannot be revalidated"]
        }
    }

    func validationIssues() -> [String] {
        journalValidationIssues() + externalArtifactValidationIssues()
    }
}

struct WorkspaceCompletedCandidateMutationContentStoreInstallation: Sendable {
    let authority: AuthorizedWorkspaceCompletedCandidateMutationContentStore
    let journalTransaction: JournalTransactionReceipt
}

enum WorkspaceCompletedCandidateMutationContentStoreError:
    Error,
    Equatable,
    Sendable
{
    case invalidProposal
    case invalidBaselineAuthority
    case originNotAccepted
    case candidatePartitionMismatch
    case baselinePartitionMismatch
    case sharedObjectConflict(ContentDigest)
    case contentSetVerification(WorkspaceMutationContentObjectSetVerificationError)
    case objectStore(WorkspaceMutationContentObjectStoreError)
    case encodingFailed
}

/// Composes and stores the exact preflight-side before/after byte set. It
/// intentionally issues no manifest, rollback, preflight, staging, apply, or
/// canonical-workspace mutation authority.
actor WorkspaceCompletedCandidateMutationContentStoreCoordinator {
    private let journal: RunJournal
    private let store = WorkspaceMutationContentObjectStore()
    private let verifier = WorkspaceMutationContentObjectSetVerifier()
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func install(
        proposal: KernelProductionCompletedCandidateProposal,
        baseline: AuthorizedWorkspaceRatifiedBaselineContent,
        workspaceRoot: URL,
        storageRoot: URL,
        commandID: RunCommandID,
        limits: WorkspaceMutationContentObjectSetLimits = .conservative,
        durability: JournalDurability = .boundary
    ) async throws
        -> WorkspaceCompletedCandidateMutationContentStoreInstallation {
        guard proposal.capture.validationIssues().isEmpty,
              proposal.derivation.validationIssues().isEmpty,
              proposal.capture.receipt.workspaceID ==
                proposal.derivation.workspaceID,
              proposal.capture.receipt.canonicalRootDigest ==
                proposal.derivation.canonicalRootDigest,
              proposal.capture.receipt.baseSourceRevision ==
                proposal.derivation.baseSourceRevision,
              proposal.capture.receipt.candidateSourceRevision ==
                proposal.derivation.candidateSourceRevision,
              proposal.capture.receipt.capturePolicyDigest ==
                proposal.derivation.capturePolicyDigest,
              await journal.completedCandidateCaptureReceipt(
                transaction: proposal.journalTransaction
              ) == proposal.capture.receipt else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .invalidProposal
        }
        guard baseline.validationIssues().isEmpty,
              baseline.receipt.runID == proposal.capture.receipt.runID,
              baseline.receipt.contractID == proposal.capture.receipt.contractID,
              baseline.receipt.workspaceID == proposal.derivation.workspaceID,
              baseline.receipt.canonicalRootDigest ==
                proposal.derivation.canonicalRootDigest,
              baseline.receipt.derivationDigest ==
                proposal.derivation.derivationDigest,
              baseline.receipt.baseSourceRevision ==
                proposal.derivation.baseSourceRevision,
              baseline.receipt.capturePolicyDigest ==
                proposal.derivation.capturePolicyDigest else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .invalidBaselineAuthority
        }
        try await validateAcceptedOrigins(proposal: proposal, baseline: baseline)

        let references = Dictionary(uniqueKeysWithValues:
            proposal.derivation.contentObjects.map {
                ($0.contentDigest, $0)
            }
        )
        let baselineDigests = Set(
            proposal.derivation.operations.compactMap(\.expectedPreimage)
        )
        let candidateDigests = Set(
            proposal.derivation.operations.compactMap(\.desiredPostimage)
        )
        let expectedBaseline = baselineDigests.compactMap { references[$0] }
            .sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        let expectedCandidate = candidateDigests.compactMap { references[$0] }
            .sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        guard expectedBaseline.count == baselineDigests.count,
              baseline.receipt.contentObjects == expectedBaseline else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .baselinePartitionMismatch
        }
        let candidateByDigest = Dictionary(uniqueKeysWithValues:
            proposal.capture.objects.map { ($0.digest, $0) }
        )
        guard expectedCandidate.count == candidateDigests.count,
              expectedCandidate.allSatisfy({ reference in
                  candidateByDigest[reference.contentDigest].map {
                      UInt64($0.data.count) == reference.size
                  } ?? false
              }) else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .candidatePartitionMismatch
        }

        var objectByDigest: [ContentDigest: WorkspaceMutationContentObject] = [:]
        for object in baseline.objects
            + candidateDigests.compactMap({ candidateByDigest[$0] }) {
            if let retained = objectByDigest[object.digest], retained != object {
                throw WorkspaceCompletedCandidateMutationContentStoreError
                    .sharedObjectConflict(object.digest)
            }
            objectByDigest[object.digest] = object
        }
        let objects = objectByDigest.values.sorted {
            $0.digest.rawValue < $1.digest.rawValue
        }
        let verification: WorkspaceMutationContentObjectSetReceipt
        do {
            verification = try verifier.verify(
                derivation: proposal.derivation,
                objects: objects,
                limits: limits
            )
        } catch let error as WorkspaceMutationContentObjectSetVerificationError {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .contentSetVerification(error)
        }
        if let retained = await journal
            .completedCandidateMutationContentStoreReceipt(
                derivationDigest: proposal.derivation.derivationDigest
            ) {
            let authority =
                AuthorizedWorkspaceCompletedCandidateMutationContentStore(
                    receipt: retained,
                    completedCandidate: proposal.capture,
                    baseline: baseline,
                    objects: objects
                )
            guard authority.validationIssues().isEmpty else {
                throw WorkspaceCompletedCandidateMutationContentStoreError
                    .originNotAccepted
            }
            let transaction = try await journal
                .recordCompletedCandidateMutationContentStore(
                    authority,
                    commandID: commandID,
                    durability: durability
                )
            return WorkspaceCompletedCandidateMutationContentStoreInstallation(
                authority: authority,
                journalTransaction: transaction
            )
        }
        let objectStoreReceipt: WorkspaceMutationContentObjectStoreReceipt
        do {
            objectStoreReceipt = try store.materialize(
                verification: verification,
                objects: objects,
                workspaceRoot: workspaceRoot,
                storageRoot: storageRoot
            )
            _ = try store.revalidate(
                objectStoreReceipt,
                verification: verification
            )
        } catch let error as WorkspaceMutationContentObjectStoreError {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .objectStore(error)
        }

        try await validateAcceptedOrigins(proposal: proposal, baseline: baseline)
        var receipt = WorkspaceCompletedCandidateMutationContentStoreReceipt(
            schemaVersion: 1,
            runID: proposal.capture.receipt.runID,
            contractID: proposal.capture.receipt.contractID,
            attemptID: proposal.capture.receipt.attemptID,
            nodeID: proposal.capture.receipt.nodeID,
            workspaceID: proposal.derivation.workspaceID,
            canonicalRootDigest: proposal.derivation.canonicalRootDigest,
            derivation: proposal.derivation,
            completedCandidateCaptureReceiptDigest:
                proposal.capture.receipt.receiptDigest,
            completedCandidateCaptureJournalFrameDigest:
                proposal.journalTransaction.frameDigest,
            baselineCaptureReceiptDigest: baseline.receipt.receiptDigest,
            verificationReceipt: verification,
            objectStoreReceipt: objectStoreReceipt,
            storedBy: proposal.capture.receipt.captureActor,
            storedAt: wallClock(),
            receiptDigest: ContentDigest("")
        )
        guard let digest =
                WorkspaceCompletedCandidateMutationContentStoreReceipt.digest(
                    for: receipt
                ) else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .encodingFailed
        }
        receipt.receiptDigest = digest
        let authority =
            AuthorizedWorkspaceCompletedCandidateMutationContentStore(
                receipt: receipt,
                completedCandidate: proposal.capture,
                baseline: baseline,
                objects: objects
            )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .encodingFailed
        }
        let transaction = try await journal
            .recordCompletedCandidateMutationContentStore(
                authority,
                commandID: commandID,
                durability: durability
            )
        return WorkspaceCompletedCandidateMutationContentStoreInstallation(
            authority: authority,
            journalTransaction: transaction
        )
    }

    private func validateAcceptedOrigins(
        proposal: KernelProductionCompletedCandidateProposal,
        baseline: AuthorizedWorkspaceRatifiedBaselineContent
    ) async throws {
        guard await journal.completedCandidateCaptureReceipt(
            attemptID: proposal.capture.receipt.attemptID
        ) == proposal.capture.receipt,
        await journal.ratifiedBaselineContentCaptureReceipt(
            derivationDigest: proposal.derivation.derivationDigest
        ) == baseline.receipt else {
            throw WorkspaceCompletedCandidateMutationContentStoreError
                .originNotAccepted
        }
    }
}
