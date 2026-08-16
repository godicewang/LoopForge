import CryptoKit
import Foundation

/// Durable evidence that the journal-accepted baseline and candidate capture
/// receipts were composed into the exact complete content set for one
/// derivation. This receipt is inert and intentionally carries no bytes.
struct WorkspaceJournaledMutationContentCompositionReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var integrationTransactionID: IntegrationTransactionID
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var derivationDigest: ContentDigest
    var baseSourceRevision: ContentDigest
    var candidateSourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var baselineCaptureReceiptDigest: ContentDigest
    var candidateCaptureReceiptDigest: ContentDigest
    var baselineContentObjects: [WorkspaceMutationContentReference]
    var candidateContentObjects: [WorkspaceMutationContentReference]
    var verificationReceipt: WorkspaceMutationContentObjectSetReceipt
    var compositionDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported journaled content-composition schema")
        }
        if runID.rawValue.isEmpty || integrationTransactionID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty {
            issues.append("journaled content-composition identity must not be empty")
        }
        for digest in [
            canonicalRootDigest,
            derivationDigest,
            baseSourceRevision,
            candidateSourceRevision,
            capturePolicyDigest,
            baselineCaptureReceiptDigest,
            candidateCaptureReceiptDigest,
            compositionDigest
        ] where !Self.isSHA256(digest) {
            issues.append("journaled content-composition digests must be SHA-256")
        }
        issues.append(contentsOf: verificationReceipt.validationIssues())
        if verificationReceipt.derivationDigest != derivationDigest
            || verificationReceipt.baseSourceRevision != baseSourceRevision
            || verificationReceipt.candidateSourceRevision != candidateSourceRevision {
            issues.append("content verification does not match composition revisions")
        }
        for partition in [baselineContentObjects, candidateContentObjects] {
            if partition != partition.sorted(by: {
                $0.contentDigest.rawValue < $1.contentDigest.rawValue
            }) || Set(partition.map(\.contentDigest)).count != partition.count {
                issues.append("composition partitions must be uniquely digest-sorted")
            }
        }
        var baselineByDigest: [ContentDigest: UInt64] = [:]
        for reference in baselineContentObjects {
            baselineByDigest[reference.contentDigest] = reference.size
        }
        var candidateByDigest: [ContentDigest: UInt64] = [:]
        for reference in candidateContentObjects {
            candidateByDigest[reference.contentDigest] = reference.size
        }
        if baselineByDigest.keys.contains(where: { digest in
            candidateByDigest[digest].map {
                $0 != baselineByDigest[digest]
            } ?? false
        }) {
            issues.append("shared composition references disagree on byte size")
        }
        var unionByDigest: [ContentDigest: UInt64] = [:]
        for reference in baselineContentObjects + candidateContentObjects {
            unionByDigest[reference.contentDigest] = reference.size
        }
        let union = unionByDigest.map {
            WorkspaceMutationContentReference(contentDigest: $0.key, size: $0.value)
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        if union != verificationReceipt.contentObjects {
            issues.append("composition partitions do not cover the verified content set")
        }
        if Self.digest(for: self) != compositionDigest {
            issues.append("journaled content-composition digest mismatch")
        }
        return issues
    }

    static func digest(
        for receipt: WorkspaceJournaledMutationContentCompositionReceipt
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            runID: receipt.runID,
            integrationTransactionID: receipt.integrationTransactionID,
            workspaceID: receipt.workspaceID,
            canonicalRootDigest: receipt.canonicalRootDigest,
            derivationDigest: receipt.derivationDigest,
            baseSourceRevision: receipt.baseSourceRevision,
            candidateSourceRevision: receipt.candidateSourceRevision,
            capturePolicyDigest: receipt.capturePolicyDigest,
            baselineCaptureReceiptDigest: receipt.baselineCaptureReceiptDigest,
            candidateCaptureReceiptDigest: receipt.candidateCaptureReceiptDigest,
            baselineContentObjects: receipt.baselineContentObjects,
            candidateContentObjects: receipt.candidateContentObjects,
            verificationReceipt: receipt.verificationReceipt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func isSHA256(_ value: ContentDigest) -> Bool {
        value.rawValue.count == 64 && value.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var runID: KernelRunID
        var integrationTransactionID: IntegrationTransactionID
        var workspaceID: WorkspaceID
        var canonicalRootDigest: ContentDigest
        var derivationDigest: ContentDigest
        var baseSourceRevision: ContentDigest
        var candidateSourceRevision: ContentDigest
        var capturePolicyDigest: ContentDigest
        var baselineCaptureReceiptDigest: ContentDigest
        var candidateCaptureReceiptDigest: ContentDigest
        var baselineContentObjects: [WorkspaceMutationContentReference]
        var candidateContentObjects: [WorkspaceMutationContentReference]
        var verificationReceipt: WorkspaceMutationContentObjectSetReceipt
    }
}

/// Non-Codable possession of the exact rehashed before/after bytes. The
/// journaled composition receipt cannot recreate this live capability.
struct AuthorizedWorkspaceJournaledMutationContentSet: Sendable {
    let receipt: WorkspaceJournaledMutationContentCompositionReceipt
    let objects: [WorkspaceMutationContentObject]
    /// Retained only in live memory so a later authority boundary can prove
    /// that this composition still descends from the exact accepted candidate
    /// transition. Neither value is Codable or embedded in the durable
    /// composition receipt.
    let candidateCaptureReceipt: WorkspaceJournaledCandidateContentCaptureReceipt
    let candidateAttestation: WorkspaceCandidatePostimageAttestationReceipt

    fileprivate init(
        receipt: WorkspaceJournaledMutationContentCompositionReceipt,
        objects: [WorkspaceMutationContentObject],
        candidateCaptureReceipt: WorkspaceJournaledCandidateContentCaptureReceipt,
        candidateAttestation: WorkspaceCandidatePostimageAttestationReceipt
    ) {
        self.receipt = receipt
        self.objects = objects
        self.candidateCaptureReceipt = candidateCaptureReceipt
        self.candidateAttestation = candidateAttestation
    }

    func validationIssues() -> [String] {
        var issues = receipt.validationIssues()
        let sorted = objects.sorted { $0.digest.rawValue < $1.digest.rawValue }
        let references = sorted.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        if references != receipt.verificationReceipt.contentObjects
            || objects.count != receipt.verificationReceipt.objectCount
            || WorkspaceMutationFilesystemExecutor.objectSetDigest(objects) !=
                receipt.verificationReceipt.objectSetDigest
            || objects.contains(where: {
                WorkspaceMutationFilesystemExecutor.contentDigest($0.data) !=
                    $0.digest
            }) {
            issues.append("journaled composition bytes do not match its receipt")
        }
        if candidateCaptureReceipt.validationIssues().isEmpty == false
            || candidateCaptureReceipt.receiptDigest !=
                receipt.candidateCaptureReceiptDigest
            || candidateCaptureReceipt.runID != receipt.runID
            || candidateCaptureReceipt.integrationTransactionID !=
                receipt.integrationTransactionID
            || candidateCaptureReceipt.workspaceID != receipt.workspaceID
            || candidateCaptureReceipt.canonicalRootDigest !=
                receipt.canonicalRootDigest
            || candidateCaptureReceipt.derivationDigest !=
                receipt.derivationDigest
            || candidateCaptureReceipt.candidateSourceRevision !=
                receipt.candidateSourceRevision
            || candidateCaptureReceipt.capturePolicyDigest !=
                receipt.capturePolicyDigest
            || candidateCaptureReceipt.integrationTransactionID !=
                candidateAttestation.integrationTransactionID
            || candidateCaptureReceipt.applyReceiptID !=
                candidateAttestation.applyReceiptID
            || candidateCaptureReceipt.applyJournalFrameDigest !=
                candidateAttestation.journalTransaction.frameDigest
            || candidateCaptureReceipt.workspaceID !=
                candidateAttestation.workspaceID
            || candidateCaptureReceipt.canonicalRootDigest !=
                candidateAttestation.canonicalRootDigest
            || candidateCaptureReceipt.candidateSourceRevision !=
                candidateAttestation.candidatePostimage.sourceRevision
            || candidateCaptureReceipt.capturePolicyDigest !=
                candidateAttestation.candidatePostimage.capturePolicyDigest {
            issues.append(
                "journaled composition does not match its live candidate transition"
            )
        }
        return issues
    }
}

enum WorkspaceJournaledMutationContentCompositionError:
    Error,
    Equatable,
    Sendable
{
    case invalidDerivation
    case invalidBaselineAuthority
    case invalidCandidateAuthority
    case authorityIdentityMismatch
    case baselineReceiptNotAccepted
    case candidateReceiptNotAccepted
    case candidateAuthorityStale
    case baselinePartitionMismatch
    case candidatePartitionMismatch
    case sharedObjectConflict(ContentDigest)
    case contentSetVerification(WorkspaceMutationContentObjectSetVerificationError)
    case encodingFailed
}

/// Resolves both origin receipts from the current journal, rechecks candidate
/// transition freshness on both sides of byte verification, and issues only an
/// inert complete-set capability. It cannot write a content store or authorize
/// preflight, staging, or filesystem mutation.
actor WorkspaceJournaledMutationContentCompositionIssuer {
    private let journal: RunJournal
    private let verifier = WorkspaceMutationContentObjectSetVerifier()

    init(journal: RunJournal) {
        self.journal = journal
    }

    func compose(
        derivation: WorkspaceMutationOperationDerivationReceipt,
        baseline: AuthorizedWorkspaceRatifiedBaselineContent,
        candidate: AuthorizedWorkspaceJournaledCandidateContent,
        limits: WorkspaceMutationContentObjectSetLimits = .conservative
    ) async throws -> AuthorizedWorkspaceJournaledMutationContentSet {
        guard derivation.validationIssues().isEmpty else {
            throw WorkspaceJournaledMutationContentCompositionError.invalidDerivation
        }
        guard baseline.validationIssues().isEmpty else {
            throw WorkspaceJournaledMutationContentCompositionError
                .invalidBaselineAuthority
        }
        guard candidate.validationIssues().isEmpty else {
            throw WorkspaceJournaledMutationContentCompositionError
                .invalidCandidateAuthority
        }
        guard baseline.receipt.runID == journal.runID,
              candidate.receipt.runID == journal.runID,
              baseline.receipt.runID == candidate.receipt.runID,
              candidate.receipt.integrationTransactionID ==
                candidate.attestation.integrationTransactionID,
              baseline.receipt.workspaceID == derivation.workspaceID,
              candidate.receipt.workspaceID == derivation.workspaceID,
              baseline.receipt.canonicalRootDigest == derivation.canonicalRootDigest,
              candidate.receipt.canonicalRootDigest == derivation.canonicalRootDigest,
              baseline.receipt.capturePolicyDigest == derivation.capturePolicyDigest,
              candidate.receipt.capturePolicyDigest == derivation.capturePolicyDigest,
              baseline.receipt.derivationDigest == derivation.derivationDigest,
              candidate.receipt.derivationDigest == derivation.derivationDigest,
              baseline.receipt.baseSourceRevision == derivation.baseSourceRevision,
              candidate.receipt.candidateSourceRevision ==
                derivation.candidateSourceRevision,
              baseline.receipt.capturedAt <= candidate.receipt.capturedAt else {
            throw WorkspaceJournaledMutationContentCompositionError
                .authorityIdentityMismatch
        }
        guard await journal.ratifiedBaselineContentCaptureReceipt(
            derivationDigest: derivation.derivationDigest
        ) == baseline.receipt else {
            throw WorkspaceJournaledMutationContentCompositionError
                .baselineReceiptNotAccepted
        }
        guard await journal.journaledCandidateContentCaptureReceipt(
            derivationDigest: derivation.derivationDigest
        ) == candidate.receipt else {
            throw WorkspaceJournaledMutationContentCompositionError
                .candidateReceiptNotAccepted
        }
        guard await journal.isLatestAcceptedCandidatePostimageAttestation(
            candidate.attestation
        ) else {
            throw WorkspaceJournaledMutationContentCompositionError
                .candidateAuthorityStale
        }

        let referenceByDigest = Dictionary(
            uniqueKeysWithValues: derivation.contentObjects.map {
                ($0.contentDigest, $0)
            }
        )
        let baselineDigests = Set(
            derivation.operations.compactMap(\.expectedPreimage)
        )
        let candidateDigests = Set(
            derivation.operations.compactMap(\.desiredPostimage)
        )
        let expectedBaseline = baselineDigests.compactMap {
            referenceByDigest[$0]
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        let expectedCandidate = candidateDigests.compactMap {
            referenceByDigest[$0]
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        guard expectedBaseline.count == baselineDigests.count,
              expectedCandidate.count == candidateDigests.count else {
            throw WorkspaceJournaledMutationContentCompositionError.invalidDerivation
        }
        guard baseline.receipt.contentObjects == expectedBaseline else {
            throw WorkspaceJournaledMutationContentCompositionError
                .baselinePartitionMismatch
        }
        guard candidate.receipt.contentObjects == expectedCandidate else {
            throw WorkspaceJournaledMutationContentCompositionError
                .candidatePartitionMismatch
        }

        var objectByDigest: [ContentDigest: WorkspaceMutationContentObject] = [:]
        for object in baseline.objects + candidate.objects {
            if let retained = objectByDigest[object.digest], retained != object {
                throw WorkspaceJournaledMutationContentCompositionError
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
                derivation: derivation,
                objects: objects,
                limits: limits
            )
        } catch let error as WorkspaceMutationContentObjectSetVerificationError {
            throw WorkspaceJournaledMutationContentCompositionError
                .contentSetVerification(error)
        }

        guard await journal.ratifiedBaselineContentCaptureReceipt(
            derivationDigest: derivation.derivationDigest
        ) == baseline.receipt else {
            throw WorkspaceJournaledMutationContentCompositionError
                .baselineReceiptNotAccepted
        }
        guard await journal.journaledCandidateContentCaptureReceipt(
            derivationDigest: derivation.derivationDigest
        ) == candidate.receipt else {
            throw WorkspaceJournaledMutationContentCompositionError
                .candidateReceiptNotAccepted
        }
        guard await journal.isLatestAcceptedCandidatePostimageAttestation(
            candidate.attestation
        ) else {
            throw WorkspaceJournaledMutationContentCompositionError
                .candidateAuthorityStale
        }

        var receipt = WorkspaceJournaledMutationContentCompositionReceipt(
            schemaVersion: 1,
            runID: candidate.receipt.runID,
            integrationTransactionID: candidate.receipt.integrationTransactionID,
            workspaceID: derivation.workspaceID,
            canonicalRootDigest: derivation.canonicalRootDigest,
            derivationDigest: derivation.derivationDigest,
            baseSourceRevision: derivation.baseSourceRevision,
            candidateSourceRevision: derivation.candidateSourceRevision,
            capturePolicyDigest: derivation.capturePolicyDigest,
            baselineCaptureReceiptDigest: baseline.receipt.receiptDigest,
            candidateCaptureReceiptDigest: candidate.receipt.receiptDigest,
            baselineContentObjects: expectedBaseline,
            candidateContentObjects: expectedCandidate,
            verificationReceipt: verification,
            compositionDigest: ContentDigest("")
        )
        guard let digest = WorkspaceJournaledMutationContentCompositionReceipt
            .digest(for: receipt) else {
            throw WorkspaceJournaledMutationContentCompositionError.encodingFailed
        }
        receipt.compositionDigest = digest
        let authority = AuthorizedWorkspaceJournaledMutationContentSet(
            receipt: receipt,
            objects: objects,
            candidateCaptureReceipt: candidate.receipt,
            candidateAttestation: candidate.attestation
        )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceJournaledMutationContentCompositionError.encodingFailed
        }
        return authority
    }
}
