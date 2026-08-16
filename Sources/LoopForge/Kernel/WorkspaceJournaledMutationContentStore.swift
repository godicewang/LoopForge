import CryptoKit
import Foundation

/// Durable evidence that one exact journal-derived before/after byte
/// composition was installed in the external immutable object store. The
/// receipt carries no bytes, descriptors, or mutation capability.
struct WorkspaceJournaledMutationContentStoreReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var compositionReceipt: WorkspaceJournaledMutationContentCompositionReceipt
    var objectStoreReceipt: WorkspaceMutationContentObjectStoreReceipt
    var storedBy: ActorIdentity
    var storedAt: Date
    var receiptDigest: ContentDigest

    var runID: KernelRunID { compositionReceipt.runID }
    var derivationDigest: ContentDigest { compositionReceipt.derivationDigest }

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported journaled mutation-content-store schema")
        }
        issues.append(contentsOf: compositionReceipt.validationIssues())
        issues.append(contentsOf: objectStoreReceipt.validationIssues())
        if storedBy.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || storedBy.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || storedBy.lineageDigest.rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
            issues.append("journaled mutation-content-store actor must not be empty")
        }
        if objectStoreReceipt.verificationReceiptDigest !=
            compositionReceipt.verificationReceipt.receiptDigest
            || objectStoreReceipt.derivationDigest !=
                compositionReceipt.derivationDigest
            || objectStoreReceipt.objectSetDigest !=
                compositionReceipt.verificationReceipt.objectSetDigest
            || objectStoreReceipt.objectCount !=
                compositionReceipt.verificationReceipt.objectCount
            || objectStoreReceipt.totalBytes !=
                compositionReceipt.verificationReceipt.totalBytes {
            issues.append(
                "external object-store receipt does not match the exact composition"
            )
        }
        if !Self.isSHA256(receiptDigest) {
            issues.append("journaled mutation-content-store digest must be SHA-256")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("journaled mutation-content-store receipt digest mismatch")
        }
        return issues
    }

    static func digest(
        for receipt: WorkspaceJournaledMutationContentStoreReceipt
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            compositionReceipt: receipt.compositionReceipt,
            objectStoreReceipt: receipt.objectStoreReceipt,
            storedBy: receipt.storedBy,
            storedAt: receipt.storedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var compositionReceipt: WorkspaceJournaledMutationContentCompositionReceipt
        var objectStoreReceipt: WorkspaceMutationContentObjectStoreReceipt
        var storedBy: ActorIdentity
        var storedAt: Date
    }
}

/// Live, non-Codable proof that the durable store receipt was revalidated
/// against the exact bytes and candidate-transition authority used to compose
/// it. Replay cannot recreate this capability from the receipt.
struct AuthorizedWorkspaceJournaledMutationContentStore: Sendable {
    let receipt: WorkspaceJournaledMutationContentStoreReceipt
    let composition: AuthorizedWorkspaceJournaledMutationContentSet

    fileprivate init(
        receipt: WorkspaceJournaledMutationContentStoreReceipt,
        composition: AuthorizedWorkspaceJournaledMutationContentSet
    ) {
        self.receipt = receipt
        self.composition = composition
    }

#if DEBUG
    static func testOnly(
        receipt: WorkspaceJournaledMutationContentStoreReceipt,
        composition: AuthorizedWorkspaceJournaledMutationContentSet
    ) -> AuthorizedWorkspaceJournaledMutationContentStore {
        AuthorizedWorkspaceJournaledMutationContentStore(
            receipt: receipt,
            composition: composition
        )
    }
#endif

    func validationIssues() -> [String] {
        var issues = journalValidationIssues()
        issues.append(contentsOf: externalArtifactValidationIssues())
        return issues
    }

    func externalArtifactValidationIssues() -> [String] {
        var issues: [String] = []
        do {
            let observed = try WorkspaceMutationContentObjectStore().revalidate(
                receipt.objectStoreReceipt,
                verification: composition.receipt.verificationReceipt
            )
            if observed != receipt.objectStoreReceipt {
                issues.append("external object-store artifact changed")
            }
        } catch {
            issues.append("external object-store artifact cannot be revalidated")
        }
        return issues
    }

    /// Pure in-memory validation used by the reducer. External artifact I/O is
    /// deliberately performed by RunJournal immediately before reduction so
    /// replay remains deterministic from durable events alone.
    func journalValidationIssues() -> [String] {
        var issues = receipt.validationIssues()
        issues.append(contentsOf: composition.validationIssues())
        if receipt.compositionReceipt != composition.receipt {
            issues.append(
                "journaled store capability does not match its live composition"
            )
        }
        return issues
    }
}

struct WorkspaceJournaledMutationContentStoreInstallation: Sendable {
    let authority: AuthorizedWorkspaceJournaledMutationContentStore
    let journalTransaction: JournalTransactionReceipt
}

enum WorkspaceJournaledMutationContentStoreError: Error, Equatable, Sendable {
    case invalidCompositionAuthority
    case baselineReceiptNotAccepted
    case candidateReceiptNotAccepted
    case candidateAuthorityStale
    case objectStore(WorkspaceMutationContentObjectStoreError)
    case encodingFailed
}

/// Installs a complete composition in the external immutable store, rechecks
/// its accepted origins and candidate freshness after materialization, then
/// asks the journal reducer to accept only the inert receipt. It cannot issue
/// preflight, staging, integration, or workspace-mutation authority.
actor WorkspaceJournaledMutationContentStoreCoordinator {
    private let journal: RunJournal
    private let store = WorkspaceMutationContentObjectStore()
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func install(
        composition: AuthorizedWorkspaceJournaledMutationContentSet,
        workspaceRoot: URL,
        storageRoot: URL,
        commandID: RunCommandID,
        durability: JournalDurability = .boundary
    ) async throws -> WorkspaceJournaledMutationContentStoreInstallation {
        guard composition.validationIssues().isEmpty else {
            throw WorkspaceJournaledMutationContentStoreError
                .invalidCompositionAuthority
        }
        try await validateAcceptedOrigins(composition)

        if let retained = await journal.journaledMutationContentStoreReceipt(
            derivationDigest: composition.receipt.derivationDigest
        ) {
            let authority = AuthorizedWorkspaceJournaledMutationContentStore(
                receipt: retained,
                composition: composition
            )
            guard authority.validationIssues().isEmpty else {
                throw WorkspaceJournaledMutationContentStoreError
                    .invalidCompositionAuthority
            }
            let transaction = try await journal
                .recordJournaledMutationContentStore(
                    authority,
                    commandID: commandID,
                    durability: durability
                )
            return WorkspaceJournaledMutationContentStoreInstallation(
                authority: authority,
                journalTransaction: transaction
            )
        }

        let objectStoreReceipt: WorkspaceMutationContentObjectStoreReceipt
        do {
            objectStoreReceipt = try store.materialize(
                verification: composition.receipt.verificationReceipt,
                objects: composition.objects,
                workspaceRoot: workspaceRoot,
                storageRoot: storageRoot
            )
            _ = try store.revalidate(
                objectStoreReceipt,
                verification: composition.receipt.verificationReceipt
            )
        } catch let error as WorkspaceMutationContentObjectStoreError {
            throw WorkspaceJournaledMutationContentStoreError.objectStore(error)
        }

        // Materialization can be arbitrarily slow. Re-resolve both origin
        // receipts and the latest candidate transition after the filesystem
        // work, immediately before asking the reducer to append acceptance.
        try await validateAcceptedOrigins(composition)

        var receipt = WorkspaceJournaledMutationContentStoreReceipt(
            schemaVersion: 1,
            compositionReceipt: composition.receipt,
            objectStoreReceipt: objectStoreReceipt,
            storedBy: composition.candidateCaptureReceipt.captureActor,
            storedAt: wallClock(),
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspaceJournaledMutationContentStoreReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceJournaledMutationContentStoreError.encodingFailed
        }
        receipt.receiptDigest = digest
        let authority = AuthorizedWorkspaceJournaledMutationContentStore(
            receipt: receipt,
            composition: composition
        )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceJournaledMutationContentStoreError.encodingFailed
        }
        let transaction = try await journal
            .recordJournaledMutationContentStore(
                authority,
                commandID: commandID,
                durability: durability
            )
        return WorkspaceJournaledMutationContentStoreInstallation(
            authority: authority,
            journalTransaction: transaction
        )
    }

    private func validateAcceptedOrigins(
        _ composition: AuthorizedWorkspaceJournaledMutationContentSet
    ) async throws {
        guard await journal.ratifiedBaselineContentCaptureReceipt(
            derivationDigest: composition.receipt.derivationDigest
        )?.receiptDigest == composition.receipt.baselineCaptureReceiptDigest else {
            throw WorkspaceJournaledMutationContentStoreError
                .baselineReceiptNotAccepted
        }
        guard await journal.journaledCandidateContentCaptureReceipt(
            derivationDigest: composition.receipt.derivationDigest
        ) == composition.candidateCaptureReceipt else {
            throw WorkspaceJournaledMutationContentStoreError
                .candidateReceiptNotAccepted
        }
        guard await journal.isLatestAcceptedCandidatePostimageAttestation(
            composition.candidateAttestation
        ) else {
            throw WorkspaceJournaledMutationContentStoreError
                .candidateAuthorityStale
        }
    }
}
