import CryptoKit
import Darwin
import Foundation

/// Durable receipt for bytes read from the exact descriptor-atomic candidate
/// snapshot projected by an accepted integration apply event. The receipt is
/// inert; only `AuthorizedWorkspaceJournaledCandidateContent` carries bytes.
struct WorkspaceJournaledCandidateContentCaptureReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var integrationTransactionID: IntegrationTransactionID
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var applyReceiptID: ReceiptID
    var applyJournalFrameDigest: ContentDigest
    var candidateSourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var materializationBindingDigest: ContentDigest
    var snapshotEntryManifestDigest: ContentDigest
    var snapshotDeviceID: UInt64
    var snapshotInode: UInt64
    var captureActor: ActorIdentity
    var capturedAt: Date
    var derivationDigest: ContentDigest
    var contentObjects: [WorkspaceMutationContentReference]
    var objectSetDigest: ContentDigest
    var objectCount: Int
    var totalBytes: UInt64
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported candidate-content schema") }
        if runID.rawValue.isEmpty || integrationTransactionID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty || applyReceiptID.rawValue.isEmpty
            || captureActor.id.rawValue.isEmpty
            || captureActor.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || captureActor.lineageDigest.rawValue.isEmpty {
            issues.append("candidate-content authority identity must not be empty")
        }
        for digest in [
            canonicalRootDigest,
            applyJournalFrameDigest,
            candidateSourceRevision,
            capturePolicyDigest,
            materializationBindingDigest,
            snapshotEntryManifestDigest,
            derivationDigest,
            objectSetDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("candidate-content authority digests must be SHA-256")
        }
        if snapshotDeviceID == 0 || snapshotInode == 0 {
            issues.append("candidate snapshot identity must not be empty")
        }
        if contentObjects != contentObjects.sorted(by: {
            $0.contentDigest.rawValue < $1.contentDigest.rawValue
        }) || Set(contentObjects.map(\.contentDigest)).count != contentObjects.count {
            issues.append("candidate content references must be uniquely digest-sorted")
        }
        var observedTotal: UInt64 = 0
        for object in contentObjects {
            if !Self.isSHA256(object.contentDigest) {
                issues.append("candidate content digest must be SHA-256")
            }
            let (next, overflow) = observedTotal.addingReportingOverflow(object.size)
            if overflow {
                issues.append("candidate content byte count overflowed")
                observedTotal = .max
            } else {
                observedTotal = next
            }
        }
        if objectCount != contentObjects.count || totalBytes != observedTotal {
            issues.append("candidate content cardinality is inconsistent")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("candidate-content receipt digest mismatch")
        }
        return issues
    }

    static func materializationBindingDigest(
        _ receipt: WorkspaceCandidatePostimageMaterializationReceipt
    ) -> ContentDigest? {
        canonicalDigest(receipt)
    }

    fileprivate static func digest(
        for receipt: WorkspaceJournaledCandidateContentCaptureReceipt
    ) -> ContentDigest? {
        canonicalDigest(DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            runID: receipt.runID,
            integrationTransactionID: receipt.integrationTransactionID,
            workspaceID: receipt.workspaceID,
            canonicalRootDigest: receipt.canonicalRootDigest,
            applyReceiptID: receipt.applyReceiptID,
            applyJournalFrameDigest: receipt.applyJournalFrameDigest,
            candidateSourceRevision: receipt.candidateSourceRevision,
            capturePolicyDigest: receipt.capturePolicyDigest,
            materializationBindingDigest: receipt.materializationBindingDigest,
            snapshotEntryManifestDigest: receipt.snapshotEntryManifestDigest,
            snapshotDeviceID: receipt.snapshotDeviceID,
            snapshotInode: receipt.snapshotInode,
            captureActor: receipt.captureActor,
            capturedAt: receipt.capturedAt,
            derivationDigest: receipt.derivationDigest,
            contentObjects: receipt.contentObjects,
            objectSetDigest: receipt.objectSetDigest,
            objectCount: receipt.objectCount,
            totalBytes: receipt.totalBytes
        ))
    }

    private static func canonicalDigest<T: Encodable>(_ value: T) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
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
        var applyReceiptID: ReceiptID
        var applyJournalFrameDigest: ContentDigest
        var candidateSourceRevision: ContentDigest
        var capturePolicyDigest: ContentDigest
        var materializationBindingDigest: ContentDigest
        var snapshotEntryManifestDigest: ContentDigest
        var snapshotDeviceID: UInt64
        var snapshotInode: UInt64
        var captureActor: ActorIdentity
        var capturedAt: Date
        var derivationDigest: ContentDigest
        var contentObjects: [WorkspaceMutationContentReference]
        var objectSetDigest: ContentDigest
        var objectCount: Int
        var totalBytes: UInt64
    }
}

struct AuthorizedWorkspaceJournaledCandidateContent: Sendable {
    let receipt: WorkspaceJournaledCandidateContentCaptureReceipt
    let objects: [WorkspaceMutationContentObject]
    let attestation: WorkspaceCandidatePostimageAttestationReceipt

    fileprivate init(
        receipt: WorkspaceJournaledCandidateContentCaptureReceipt,
        objects: [WorkspaceMutationContentObject],
        attestation: WorkspaceCandidatePostimageAttestationReceipt
    ) {
        self.receipt = receipt
        self.objects = objects
        self.attestation = attestation
    }

    func validationIssues() -> [String] {
        var issues = receipt.validationIssues()
        if receipt.integrationTransactionID != attestation.integrationTransactionID
            || receipt.workspaceID != attestation.workspaceID
            || receipt.canonicalRootDigest != attestation.canonicalRootDigest
            || receipt.applyReceiptID != attestation.applyReceiptID
            || receipt.applyJournalFrameDigest !=
                attestation.journalTransaction.frameDigest
            || receipt.candidateSourceRevision !=
                attestation.candidatePostimage.sourceRevision
            || receipt.capturePolicyDigest !=
                attestation.candidatePostimage.capturePolicyDigest {
            issues.append("candidate-content capability does not match its attestation")
        }
        let sorted = objects.sorted { $0.digest.rawValue < $1.digest.rawValue }
        let references = sorted.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        if references != receipt.contentObjects
            || objects.count != receipt.objectCount
            || WorkspaceMutationFilesystemExecutor.objectSetDigest(objects) !=
                receipt.objectSetDigest
            || objects.contains(where: {
                WorkspaceMutationFilesystemExecutor.contentDigest($0.data) !=
                    $0.digest
            }) {
            issues.append("candidate-content capability bytes do not match its receipt")
        }
        return issues
    }

#if DEBUG
    static func testOnly(
        receipt: WorkspaceJournaledCandidateContentCaptureReceipt,
        objects: [WorkspaceMutationContentObject],
        attestation: WorkspaceCandidatePostimageAttestationReceipt
    ) -> AuthorizedWorkspaceJournaledCandidateContent {
        AuthorizedWorkspaceJournaledCandidateContent(
            receipt: receipt,
            objects: objects,
            attestation: attestation
        )
    }
#endif
}

enum WorkspaceJournaledCandidateContentCaptureError: Error, Equatable, Sendable {
    case invalidDerivation
    case authorityMismatch
    case missingContent(ContentDigest)
    case corruptContent(ContentDigest)
    case unstableSnapshot
    case systemCallFailed(operation: String, errno: Int32)
    case encodingFailed
}

/// Reads only desired-postimage bytes from the exact held, read-only snapshot
/// materialized from a reducer-accepted apply event. It cannot read the mutable
/// workspace, compose baseline bytes, write the store, or authorize an effect.
actor WorkspaceJournaledCandidateContentCaptureIssuer {
    private let journal: RunJournal
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func capture(
        derivation: WorkspaceMutationOperationDerivationReceipt,
        input: AuthorizedWorkspaceCandidatePostimageInput
    ) async throws -> AuthorizedWorkspaceJournaledCandidateContent {
        guard derivation.validationIssues().isEmpty else {
            throw WorkspaceJournaledCandidateContentCaptureError.invalidDerivation
        }
        guard await journal.isLatestAcceptedCandidatePostimageAttestation(
            input.attestation
        ) else {
            throw WorkspaceJournaledCandidateContentCaptureError.authorityMismatch
        }
        guard let integration = await journal.integrationTransaction(
            transactionID: input.attestation.integrationTransactionID
        ), let acceptedApply = integration.applyReceipt,
           acceptedApply.id == input.attestation.applyReceiptID,
           acceptedApply.candidatePostimage == input.attestation.candidatePostimage,
           case .exactPostimage = acceptedApply.outcome else {
            throw WorkspaceJournaledCandidateContentCaptureError.authorityMismatch
        }
        let materializer = WorkspaceCandidatePostimageMaterializer()
        let materialization = try materializer.revalidate(input)
        let candidate = input.attestation.candidatePostimage
        guard candidate.validationIssues().isEmpty,
              candidate.workspaceID == derivation.workspaceID,
              candidate.canonicalRootDigest == derivation.canonicalRootDigest,
              candidate.capturePolicyDigest == derivation.capturePolicyDigest,
              candidate.sourceRevision == derivation.candidateSourceRevision,
              materialization.workspaceID == candidate.workspaceID,
              materialization.sourceRevision == candidate.sourceRevision,
              materialization.capturePolicyDigest == candidate.capturePolicyDigest,
              materialization.applyReceiptID == input.attestation.applyReceiptID,
              materialization.attestationJournalFrameDigest ==
                input.attestation.journalTransaction.frameDigest else {
            throw WorkspaceJournaledCandidateContentCaptureError.authorityMismatch
        }
        let desiredDigests = Set(derivation.operations.compactMap(\.desiredPostimage))
        let referenceByDigest = Dictionary(
            uniqueKeysWithValues: derivation.contentObjects.map {
                ($0.contentDigest, $0)
            }
        )
        let entryByDigest = Dictionary(
            grouping: candidate.entries,
            by: \.contentDigest
        ).mapValues { entries in
            entries.sorted { $0.relativePath < $1.relativePath }[0]
        }
        let descriptorAuthority = try materializer.openRevalidatedDescriptor(input)
        defer { descriptorAuthority.close() }
        let rootDescriptor = try descriptorAuthority.descriptorForLaunch(
            matching: materialization
        )
        var rootBefore = stat()
        guard fstat(rootDescriptor, &rootBefore) == 0 else {
            throw systemCallFailure("fstat(candidate-content-root)")
        }
        var objects: [WorkspaceMutationContentObject] = []
        for digest in desiredDigests.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let entry = entryByDigest[digest],
                  referenceByDigest[digest]?.size == entry.size else {
                throw WorkspaceJournaledCandidateContentCaptureError
                    .missingContent(digest)
            }
            let data = try readStable(entry, rootDescriptor: rootDescriptor)
            guard WorkspaceMutationFilesystemExecutor.contentDigest(data) == digest else {
                throw WorkspaceJournaledCandidateContentCaptureError
                    .corruptContent(digest)
            }
            objects.append(WorkspaceMutationContentObject(digest: digest, data: data))
        }
        objects.sort { $0.digest.rawValue < $1.digest.rawValue }
        _ = try materializer.revalidateHeldDescriptor(
            descriptorAuthority,
            input: input
        )
        guard await journal.isLatestAcceptedCandidatePostimageAttestation(
            input.attestation
        ) else {
            throw WorkspaceJournaledCandidateContentCaptureError.authorityMismatch
        }
        var rootAfter = stat()
        guard fstat(rootDescriptor, &rootAfter) == 0,
              rootBefore.st_dev == rootAfter.st_dev,
              rootBefore.st_ino == rootAfter.st_ino,
              rootBefore.st_mode == rootAfter.st_mode,
              rootBefore.st_mtimespec.tv_sec == rootAfter.st_mtimespec.tv_sec,
              rootBefore.st_mtimespec.tv_nsec == rootAfter.st_mtimespec.tv_nsec else {
            throw WorkspaceJournaledCandidateContentCaptureError.unstableSnapshot
        }
        guard let materializationDigest =
                WorkspaceJournaledCandidateContentCaptureReceipt
                    .materializationBindingDigest(materialization) else {
            throw WorkspaceJournaledCandidateContentCaptureError.encodingFailed
        }
        let references = objects.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        let total = references.reduce(UInt64(0)) { $0 + $1.size }
        var receipt = WorkspaceJournaledCandidateContentCaptureReceipt(
            schemaVersion: 1,
            runID: journal.runID,
            integrationTransactionID: input.attestation.integrationTransactionID,
            workspaceID: candidate.workspaceID,
            canonicalRootDigest: candidate.canonicalRootDigest,
            applyReceiptID: input.attestation.applyReceiptID,
            applyJournalFrameDigest: input.attestation.journalTransaction.frameDigest,
            candidateSourceRevision: candidate.sourceRevision,
            capturePolicyDigest: candidate.capturePolicyDigest,
            materializationBindingDigest: materializationDigest,
            snapshotEntryManifestDigest: materialization.snapshotEntryManifestDigest,
            snapshotDeviceID: materialization.deviceID,
            snapshotInode: materialization.inode,
            captureActor: acceptedApply.executor,
            capturedAt: wallClock(),
            derivationDigest: derivation.derivationDigest,
            contentObjects: references,
            objectSetDigest: WorkspaceMutationFilesystemExecutor.objectSetDigest(objects),
            objectCount: objects.count,
            totalBytes: total,
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspaceJournaledCandidateContentCaptureReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceJournaledCandidateContentCaptureError.encodingFailed
        }
        receipt.receiptDigest = digest
        let authority = AuthorizedWorkspaceJournaledCandidateContent(
            receipt: receipt,
            objects: objects,
            attestation: input.attestation
        )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceJournaledCandidateContentCaptureError.encodingFailed
        }
        return authority
    }

    private func readStable(
        _ entry: WorkspaceSourceRevisionEntry,
        rootDescriptor: Int32
    ) throws -> Data {
        let descriptor: Int32
        do {
            descriptor = try WorkspaceSourceRevisionCollector.openRegularFile(
                entry.relativePath,
                rootDescriptor: rootDescriptor
            )
        } catch {
            throw WorkspaceJournaledCandidateContentCaptureError.unstableSnapshot
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0,
              UInt64(before.st_size) == entry.size else {
            throw WorkspaceJournaledCandidateContentCaptureError.unstableSnapshot
        }
        var data = Data()
        data.reserveCapacity(Int(entry.size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw systemCallFailure("read(candidate-content)")
            }
            data.append(contentsOf: buffer[0..<Int(count)])
            guard UInt64(data.count) <= entry.size else {
                throw WorkspaceJournaledCandidateContentCaptureError.unstableSnapshot
            }
        }
        var after = stat()
        guard UInt64(data.count) == entry.size,
              fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw WorkspaceJournaledCandidateContentCaptureError.unstableSnapshot
        }
        return data
    }

    private func systemCallFailure(
        _ operation: String
    ) -> WorkspaceJournaledCandidateContentCaptureError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
