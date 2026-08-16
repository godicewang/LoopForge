import CryptoKit
import Darwin
import Foundation

/// Durable, inert evidence that an owner-private writable candidate began as
/// an exact byte copy of the user-ratified source revision. This receipt is not
/// activation or mutation authority. In particular, it is deliberately
/// distinct from post-apply attestation and apply receipts.
struct WorkspacePreApplyCandidateIsolationReceipt:
    Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var strategyFingerprint: StrategyFingerprint
    var isolationActor: ActorIdentity
    var sourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var enrollmentJournalFrameDigest: ContentDigest
    var candidateRootPath: String
    var candidateCanonicalRootDigest: ContentDigest
    var candidateEntryManifestDigest: ContentDigest
    var fileCount: Int
    var totalBytes: UInt64
    var deviceID: UInt64
    var inode: UInt64
    var isolatedAt: Date
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported pre-apply isolation schema")
        }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || attemptID.rawValue.isEmpty || nodeID.rawValue.isEmpty
            || strategyFingerprint.rawValue.isEmpty
            || isolationActor.id.rawValue.isEmpty
            || isolationActor.role.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            || isolationActor.lineageDigest.rawValue.isEmpty {
            issues.append("pre-apply isolation identity is incomplete")
        }
        if !Self.validDigest(sourceRevision)
            || !Self.validDigest(capturePolicyDigest)
            || !Self.validDigest(enrollmentJournalFrameDigest)
            || !Self.validDigest(candidateCanonicalRootDigest)
            || !Self.validDigest(candidateEntryManifestDigest)
            || !Self.validDigest(receiptDigest) {
            issues.append("pre-apply isolation digest is invalid")
        }
        if !candidateRootPath.hasPrefix("/")
            || fileCount < 0 {
            issues.append("pre-apply isolation artifact is invalid")
        }
        if Self.digest(digestMaterial) != receiptDigest {
            issues.append("pre-apply isolation receipt digest mismatch")
        }
        return issues
    }

    fileprivate struct DigestMaterial: Codable {
        var schemaVersion: Int
        var runID: KernelRunID
        var contractID: TaskContractID
        var attemptID: AttemptID
        var nodeID: KernelNodeID
        var strategyFingerprint: StrategyFingerprint
        var isolationActor: ActorIdentity
        var sourceRevision: ContentDigest
        var capturePolicyDigest: ContentDigest
        var enrollmentJournalFrameDigest: ContentDigest
        var candidateRootPath: String
        var candidateCanonicalRootDigest: ContentDigest
        var candidateEntryManifestDigest: ContentDigest
        var fileCount: Int
        var totalBytes: UInt64
        var deviceID: UInt64
        var inode: UInt64
        var isolatedAt: Date
    }

    fileprivate var digestMaterial: DigestMaterial {
        DigestMaterial(
            schemaVersion: schemaVersion,
            runID: runID,
            contractID: contractID,
            attemptID: attemptID,
            nodeID: nodeID,
            strategyFingerprint: strategyFingerprint,
            isolationActor: isolationActor,
            sourceRevision: sourceRevision,
            capturePolicyDigest: capturePolicyDigest,
            enrollmentJournalFrameDigest: enrollmentJournalFrameDigest,
            candidateRootPath: candidateRootPath,
            candidateCanonicalRootDigest: candidateCanonicalRootDigest,
            candidateEntryManifestDigest: candidateEntryManifestDigest,
            fileCount: fileCount,
            totalBytes: totalBytes,
            deviceID: deviceID,
            inode: inode,
            isolatedAt: isolatedAt
        )
    }

    fileprivate static func digest(
        _ material: DigestMaterial
    ) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(material) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func validDigest(_ value: ContentDigest) -> Bool {
        value.rawValue.count == 64 && value.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

/// Single-process capability for one pristine, writable candidate root. Its
/// initializer is file-private and the value is not Codable, so replaying a
/// receipt cannot recreate live authority.
final class AuthorizedWorkspacePreApplyCandidateIsolation: @unchecked Sendable {
    let receipt: WorkspacePreApplyCandidateIsolationReceipt
    let sourceRevision: WorkspaceSourceRevisionArtifact

    private let lock = NSLock()
    private var rootDescriptor: Int32

    fileprivate init(
        receipt: WorkspacePreApplyCandidateIsolationReceipt,
        sourceRevision: WorkspaceSourceRevisionArtifact,
        rootDescriptor: Int32
    ) {
        self.receipt = receipt
        self.sourceRevision = sourceRevision
        self.rootDescriptor = rootDescriptor
    }

    fileprivate func descriptorForAcceptance() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard rootDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        var status = stat()
        guard fstat(rootDescriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              UInt64(status.st_dev) == receipt.deviceID,
              UInt64(status.st_ino) == receipt.inode else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return rootDescriptor
    }

    /// Transfers this capability exactly once into a longer-lived execution
    /// session. The returned descriptor has independent ownership while this
    /// issuer is permanently consumed, so neither a decoded receipt nor a
    /// duplicate activation call can recreate candidate-root authority.
    fileprivate func consumeDescriptorForActivation() throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard rootDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        var status = stat()
        guard fstat(rootDescriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              UInt64(status.st_dev) == receipt.deviceID,
              UInt64(status.st_ino) == receipt.inode else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        let transferred = Darwin.fcntl(rootDescriptor, F_DUPFD_CLOEXEC, 220)
        guard transferred >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .systemCallFailed(
                    operation: "fcntl(preapply-activation-root)",
                    errno: errno
                )
        }
        _ = Darwin.close(rootDescriptor)
        rootDescriptor = -1
        return transferred
    }

    /// Pure command-side checks available to the reducer. Descriptor identity
    /// and bytes are checked separately by the journal immediately before it
    /// asks the reducer to accept this capability.
    func journalValidationIssues() -> [String] {
        var issues = receipt.validationIssues()
        if sourceRevision.validationIssues().isEmpty == false
            || receipt.sourceRevision != sourceRevision.sourceRevision
            || receipt.capturePolicyDigest != sourceRevision.capturePolicyDigest
            || receipt.fileCount != sourceRevision.entries.count
            || receipt.totalBytes != sourceRevision.totalBytes
            || receipt.candidateEntryManifestDigest !=
                WorkspaceCandidatePostimageMaterializer
                    .preApplyCandidateEntryManifestDigest(sourceRevision) {
            issues.append(
                "pre-apply isolation capability does not match its source revision"
            )
        }
        return issues
    }

    func close() {
        lock.lock()
        let descriptor = rootDescriptor
        rootDescriptor = -1
        lock.unlock()
        if descriptor >= 0 { _ = Darwin.close(descriptor) }
    }

    deinit { close() }
}

/// Session-owned execution root produced only by consuming the original live
/// isolation capability. It retains an independently owned no-follow
/// descriptor across preparation and provider launch; the path in its receipt
/// remains evidence, never the authority used for `fchdir`.
final class AuthorizedWorkspacePreApplyCandidateExecutionRoot:
    @unchecked Sendable {
    let receipt: WorkspacePreApplyCandidateIsolationReceipt
    let sourceRevision: WorkspaceSourceRevisionArtifact

    private let lock = NSLock()
    private var rootDescriptor: Int32

    fileprivate init(
        receipt: WorkspacePreApplyCandidateIsolationReceipt,
        sourceRevision: WorkspaceSourceRevisionArtifact,
        rootDescriptor: Int32
    ) {
        self.receipt = receipt
        self.sourceRevision = sourceRevision
        self.rootDescriptor = rootDescriptor
    }

    func descriptorForLaunch(
        matching expected: WorkspacePreApplyCandidateIsolationReceipt
    ) throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard expected == receipt, rootDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        var status = stat()
        guard fstat(rootDescriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              UInt64(status.st_dev) == receipt.deviceID,
              UInt64(status.st_ino) == receipt.inode else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return rootDescriptor
    }

    fileprivate func descriptorForRevalidation() throws -> Int32 {
        try descriptorForLaunch(matching: receipt)
    }

    func close() {
        lock.lock()
        let descriptor = rootDescriptor
        rootDescriptor = -1
        lock.unlock()
        if descriptor >= 0 { _ = Darwin.close(descriptor) }
    }

    deinit { close() }
}

/// Durable evidence for one stable, content-complete read of the isolated
/// candidate after the exact provider lifecycle reached a reducer-derived
/// completed disposition. The logical workspace identity remains the
/// user-ratified workspace; physical candidate identity is bound separately.
struct WorkspaceCompletedCandidateCaptureReceipt:
    Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var strategyFingerprint: StrategyFingerprint
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var baseSourceRevision: ContentDigest
    var candidateSourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var candidateRevision: WorkspaceSourceRevisionArtifact
    var isolationReceiptDigest: ContentDigest
    var candidateRootPath: String
    var candidateCanonicalRootDigest: ContentDigest
    var candidateEntryManifestDigest: ContentDigest
    var candidateDeviceID: UInt64
    var candidateInode: UInt64
    var releaseReceiptID: ReceiptID
    var releaseJournalFrameDigest: ContentDigest
    var parseReceiptID: ReceiptID
    var parseJournalFrameDigest: ContentDigest
    var executionReceiptID: ReceiptID
    var executionJournalFrameDigest: ContentDigest
    var executionSourceEvidenceDigest: ContentDigest
    var captureActor: ActorIdentity
    var capturedAt: Date
    var contentObjects: [WorkspaceMutationContentReference]
    var objectSetDigest: ContentDigest
    var fileCount: Int
    var totalFileBytes: UInt64
    var objectCount: Int
    var uniqueObjectBytes: UInt64
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported completed-candidate capture schema")
        }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || attemptID.rawValue.isEmpty || nodeID.rawValue.isEmpty
            || strategyFingerprint.rawValue.isEmpty || workspaceID.rawValue.isEmpty
            || releaseReceiptID.rawValue.isEmpty || parseReceiptID.rawValue.isEmpty
            || executionReceiptID.rawValue.isEmpty || captureActor.id.rawValue.isEmpty
            || captureActor.role.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || captureActor.lineageDigest.rawValue.isEmpty {
            issues.append("completed-candidate capture identity is incomplete")
        }
        for digest in [
            canonicalRootDigest,
            baseSourceRevision,
            candidateSourceRevision,
            capturePolicyDigest,
            isolationReceiptDigest,
            candidateCanonicalRootDigest,
            candidateEntryManifestDigest,
            releaseJournalFrameDigest,
            parseJournalFrameDigest,
            executionJournalFrameDigest,
            executionSourceEvidenceDigest,
            objectSetDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("completed-candidate capture digest is invalid")
        }
        if !candidateRootPath.hasPrefix("/")
            || candidateDeviceID == 0 || candidateInode == 0
            || fileCount < 0 || objectCount < 0 {
            issues.append("completed-candidate physical identity is invalid")
        }
        if contentObjects != contentObjects.sorted(by: {
            $0.contentDigest.rawValue < $1.contentDigest.rawValue
        }) || Set(contentObjects.map(\.contentDigest)).count != contentObjects.count {
            issues.append("completed-candidate objects must be uniquely digest-sorted")
        }
        let observedUniqueBytes = contentObjects.reduce(UInt64(0)) { partial, object in
            let (next, overflow) = partial.addingReportingOverflow(object.size)
            return overflow ? .max : next
        }
        if objectCount != contentObjects.count
            || observedUniqueBytes != uniqueObjectBytes
            || totalFileBytes < uniqueObjectBytes {
            issues.append("completed-candidate content cardinality is inconsistent")
        }
        if !candidateRevision.validationIssues().isEmpty
            || candidateRevision.workspaceID != workspaceID
            || candidateRevision.canonicalRootDigest != canonicalRootDigest
            || candidateRevision.sourceRevision != candidateSourceRevision
            || candidateRevision.capturePolicyDigest != capturePolicyDigest
            || candidateRevision.entries.count != fileCount
            || candidateRevision.totalBytes != totalFileBytes {
            issues.append("completed-candidate logical revision is inconsistent")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("completed-candidate receipt digest mismatch")
        }
        return issues
    }

    fileprivate static func digest(
        for receipt: WorkspaceCompletedCandidateCaptureReceipt
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

    private static func isSHA256(_ value: ContentDigest) -> Bool {
        value.rawValue.count == 64 && value.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

/// Non-serializable byte authority for the exact completed-candidate capture.
/// Future content-store composition consumes these immutable bytes; reopening
/// the mutable candidate path from a decoded receipt is never equivalent.
struct AuthorizedWorkspaceCompletedCandidateCapture: Sendable {
    let receipt: WorkspaceCompletedCandidateCaptureReceipt
    let candidateRevision: WorkspaceSourceRevisionArtifact
    let objects: [WorkspaceMutationContentObject]
    let isolationReceipt: WorkspacePreApplyCandidateIsolationReceipt

    fileprivate init(
        receipt: WorkspaceCompletedCandidateCaptureReceipt,
        candidateRevision: WorkspaceSourceRevisionArtifact,
        objects: [WorkspaceMutationContentObject],
        isolationReceipt: WorkspacePreApplyCandidateIsolationReceipt
    ) {
        self.receipt = receipt
        self.candidateRevision = candidateRevision
        self.objects = objects
        self.isolationReceipt = isolationReceipt
    }

    func validationIssues() -> [String] {
        var issues = receipt.validationIssues()
        if !candidateRevision.validationIssues().isEmpty
            || !isolationReceipt.validationIssues().isEmpty
            || receipt.runID != isolationReceipt.runID
            || receipt.contractID != isolationReceipt.contractID
            || receipt.attemptID != isolationReceipt.attemptID
            || receipt.nodeID != isolationReceipt.nodeID
            || receipt.strategyFingerprint != isolationReceipt.strategyFingerprint
            || receipt.baseSourceRevision != isolationReceipt.sourceRevision
            || receipt.isolationReceiptDigest != isolationReceipt.receiptDigest
            || receipt.candidateRootPath != isolationReceipt.candidateRootPath
            || receipt.candidateCanonicalRootDigest !=
                isolationReceipt.candidateCanonicalRootDigest
            || receipt.candidateDeviceID != isolationReceipt.deviceID
            || receipt.candidateInode != isolationReceipt.inode
            || receipt.workspaceID != candidateRevision.workspaceID
            || receipt.canonicalRootDigest != candidateRevision.canonicalRootDigest
            || receipt.candidateSourceRevision != candidateRevision.sourceRevision
            || receipt.capturePolicyDigest != candidateRevision.capturePolicyDigest
            || receipt.fileCount != candidateRevision.entries.count
            || receipt.totalFileBytes != candidateRevision.totalBytes {
            issues.append("completed-candidate capability authority mismatch")
        }
        let sortedObjects = objects.sorted { $0.digest.rawValue < $1.digest.rawValue }
        let references = sortedObjects.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        let revisionReferences = Dictionary(
            grouping: candidateRevision.entries,
            by: \.contentDigest
        ).map { digest, entries in
            WorkspaceMutationContentReference(
                contentDigest: digest,
                size: entries[0].size
            )
        }.sorted { $0.contentDigest.rawValue < $1.contentDigest.rawValue }
        if references != receipt.contentObjects
            || references != revisionReferences
            || receipt.objectCount != objects.count
            || receipt.objectSetDigest !=
                WorkspaceMutationFilesystemExecutor.objectSetDigest(objects)
            || objects.contains(where: {
                WorkspaceMutationFilesystemExecutor.contentDigest($0.data) !=
                    $0.digest
            }) {
            issues.append("completed-candidate capability bytes mismatch")
        }
        return issues
    }
}

enum WorkspaceCompletedCandidateCaptureError: Error, Equatable, Sendable {
    case invalidAuthority
    case invalidCompletion
    case unstableCandidate
    case limitExceeded
    case encodingFailed
    case systemCallFailed(operation: String, errno: Int32)
}

enum WorkspaceCandidatePostimageMaterialization: String, Codable, Hashable, Sendable {
    case streamCopy
    case existingArtifact
}

/// Durable evidence describing a revalidated content-addressed snapshot. This
/// value is not authority by itself; only the non-Codable input capability
/// returned by the materializer may enter a future verifier composition.
struct WorkspaceCandidatePostimageMaterializationReceipt:
    Codable, Hashable, Sendable {
    var workspaceID: WorkspaceID
    var applyReceiptID: ReceiptID
    var sourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var attestationJournalFrameDigest: ContentDigest
    var snapshotRootPath: String
    var snapshotCanonicalRootDigest: ContentDigest
    var snapshotEntryManifestDigest: ContentDigest
    var fileCount: Int
    var totalBytes: UInt64
    var deviceID: UInt64
    var inode: UInt64
    var materialization: WorkspaceCandidatePostimageMaterialization
    var reusedExistingArtifact: Bool
}

/// Single-process capability proving that one exact candidate snapshot was
/// materialized from journal-owned attestation authority and byte-revalidated.
/// It intentionally has no Codable conformance and no public initializer.
struct AuthorizedWorkspaceCandidatePostimageInput: Sendable {
    let receipt: WorkspaceCandidatePostimageMaterializationReceipt
    let attestation: WorkspaceCandidatePostimageAttestationReceipt

    private init(
        receipt: WorkspaceCandidatePostimageMaterializationReceipt,
        attestation: WorkspaceCandidatePostimageAttestationReceipt
    ) {
        self.receipt = receipt
        self.attestation = attestation
    }

    fileprivate static func materialized(
        _ receipt: WorkspaceCandidatePostimageMaterializationReceipt,
        attestation: WorkspaceCandidatePostimageAttestationReceipt
    ) -> AuthorizedWorkspaceCandidatePostimageInput {
        AuthorizedWorkspaceCandidatePostimageInput(
            receipt: receipt,
            attestation: attestation
        )
    }
}

/// Ephemeral authority over the exact no-follow candidate root consumed by a
/// verifier. The descriptor is intentionally non-Codable, owner-private, and
/// closed independently of durable materialization evidence.
final class AuthorizedWorkspaceCandidatePostimageDescriptor: @unchecked Sendable {
    let receipt: WorkspaceCandidatePostimageMaterializationReceipt

    private let lock = NSLock()
    private var descriptor: Int32

    fileprivate init(
        receipt: WorkspaceCandidatePostimageMaterializationReceipt,
        descriptor: Int32
    ) {
        self.receipt = receipt
        self.descriptor = descriptor
    }

    func descriptorForLaunch(
        matching expected: WorkspaceCandidatePostimageMaterializationReceipt
    ) throws -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard receipt == expected, descriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              UInt64(status.st_dev) == receipt.deviceID,
              UInt64(status.st_ino) == receipt.inode else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return descriptor
    }

    func close() {
        lock.lock()
        let current = descriptor
        descriptor = -1
        lock.unlock()
        if current >= 0 { _ = Darwin.close(current) }
    }

    deinit { close() }
}

enum WorkspaceCandidatePostimageMaterializationError: Error, Equatable {
    case invalidAttestation
    case invalidRunDirectory
    case storageOverlapsWorkspace
    case unsafeStagingDirectory
    case sourceRevisionMismatch
    case sourceChangedDuringMaterialization(String)
    case unsafeExistingArtifact
    case existingArtifactMismatch
    case systemCallFailed(operation: String, errno: Int32)
}

/// Copies the exact attested source bytes into an owner-private,
/// content-addressed, read-only tree outside the workspace.
///
/// The live workspace is captured before and after descriptor-relative copy,
/// every source file is opened with `O_NOFOLLOW`, and the installed snapshot is
/// independently rehashed before a non-serializable input capability is
/// returned. No verifier or process is started here.
struct WorkspaceCandidatePostimageMaterializer: Sendable {
    static let directoryName = "candidate-postimages"
    private static let lockName = ".materializer.lock"
    private static let preApplyDirectoryName = "preapply-candidates"
    private static let preApplyLockName = ".isolation.lock"

    /// Candidate work belongs to an owner-private execution sibling of the
    /// journal tree. A workspace-only sandbox can therefore grant mutation of
    /// the candidate without also granting mutation of hash-chained evidence.
    static func preApplyExecutionRoot(
        forJournalRunDirectory journalRunDirectory: URL
    ) -> URL {
        journalRunDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("execution", isDirectory: true)
    }

    static func preApplyCandidateParent(
        forJournalRunDirectory journalRunDirectory: URL
    ) -> URL {
        preApplyExecutionRoot(forJournalRunDirectory: journalRunDirectory)
            .appendingPathComponent(preApplyDirectoryName, isDirectory: true)
    }

    /// Reissues only the live, non-Codable capability for an activation that
    /// was already journaled before launch. A fresh materialization can report
    /// `existingArtifact`, but it must resolve to the exact same immutable
    /// snapshot object and attestation as the retained activation receipt.
    /// This cannot create new durable evidence or select a different tree.
    func replay(
        _ input: AuthorizedWorkspaceCandidatePostimageInput,
        matching expected: WorkspaceCandidatePostimageMaterializationReceipt
    ) throws -> AuthorizedWorkspaceCandidatePostimageInput {
        _ = try revalidate(input)
        let observed = input.receipt
        guard observed.workspaceID == expected.workspaceID,
              observed.applyReceiptID == expected.applyReceiptID,
              observed.sourceRevision == expected.sourceRevision,
              observed.capturePolicyDigest == expected.capturePolicyDigest,
              observed.attestationJournalFrameDigest ==
                expected.attestationJournalFrameDigest,
              observed.snapshotRootPath == expected.snapshotRootPath,
              observed.snapshotCanonicalRootDigest ==
                expected.snapshotCanonicalRootDigest,
              observed.snapshotEntryManifestDigest ==
                expected.snapshotEntryManifestDigest,
              observed.fileCount == expected.fileCount,
              observed.totalBytes == expected.totalBytes,
              observed.deviceID == expected.deviceID,
              observed.inode == expected.inode,
              input.attestation.applyReceiptID == expected.applyReceiptID,
              input.attestation.candidatePostimage.sourceRevision ==
                expected.sourceRevision,
              input.attestation.candidatePostimage.capturePolicyDigest ==
                expected.capturePolicyDigest,
              input.attestation.journalTransaction.frameDigest ==
                expected.attestationJournalFrameDigest else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return .materialized(expected, attestation: input.attestation)
    }

    func materialize(
        attestation: WorkspaceCandidatePostimageAttestationReceipt,
        workspaceRoot: URL,
        runDirectory: URL
    ) throws -> AuthorizedWorkspaceCandidatePostimageInput {
        let workspace = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? attestation.validated(for: workspace)) != nil else {
            throw WorkspaceCandidatePostimageMaterializationError.invalidAttestation
        }
        let run = runDirectory.standardizedFileURL
        guard run.isFileURL else {
            throw WorkspaceCandidatePostimageMaterializationError.invalidRunDirectory
        }
        let workspacePath = workspace.path
        let runPath = run.path
        let resolvedRunPath = run.resolvingSymlinksInPath().path
        guard runPath != workspacePath,
              resolvedRunPath != workspacePath,
              !resolvedRunPath.hasPrefix(workspacePath + "/"),
              !workspacePath.hasPrefix(resolvedRunPath + "/") else {
            throw WorkspaceCandidatePostimageMaterializationError
                .storageOverlapsWorkspace
        }

        let expected = attestation.candidatePostimage
        guard try capture(root: workspace, expected: expected) == expected else {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceRevisionMismatch
        }

        let runDescriptor = Darwin.open(
            runPath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard runDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError.invalidRunDirectory
        }
        defer { Darwin.close(runDescriptor) }
        try validatePrivateDirectory(
            descriptor: runDescriptor,
            error: .invalidRunDirectory
        )

        if mkdirat(runDescriptor, Self.directoryName, 0o700) != 0,
           errno != EEXIST {
            throw Self.systemCallFailure("mkdirat(candidate-postimages)")
        }
        let stagingDescriptor = Darwin.openat(
            runDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard stagingDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeStagingDirectory
        }
        defer { Darwin.close(stagingDescriptor) }
        try validatePrivateDirectory(
            descriptor: stagingDescriptor,
            error: .unsafeStagingDirectory
        )

        let lockDescriptor = Darwin.openat(
            stagingDescriptor,
            Self.lockName,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard lockDescriptor >= 0 else {
            throw Self.systemCallFailure("openat(candidate-materializer-lock)")
        }
        defer { Darwin.close(lockDescriptor) }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw Self.systemCallFailure("flock(candidate-materializer-lock)")
        }
        defer { flock(lockDescriptor, LOCK_UN) }

        let artifactName = expected.sourceRevision.rawValue
        let stagingRoot = run.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
        let finalRoot = stagingRoot.appendingPathComponent(
            artifactName,
            isDirectory: true
        )
        if directoryExists(
            named: artifactName,
            parentDescriptor: stagingDescriptor
        ) {
            let receipt = try validateInstalledSnapshot(
                root: finalRoot,
                expected: expected,
                attestation: attestation,
                materialization: .existingArtifact,
                reused: true
            )
            return .materialized(receipt, attestation: attestation)
        }

        let temporaryName = ".\(artifactName).\(UUID().uuidString).tmp"
        guard mkdirat(stagingDescriptor, temporaryName, 0o700) == 0 else {
            throw Self.systemCallFailure("mkdirat(candidate-temporary)")
        }
        let temporaryRoot = stagingRoot.appendingPathComponent(
            temporaryName,
            isDirectory: true
        )
        var installed = false
        defer {
            if !installed {
                try? FileManager.default.removeItem(at: temporaryRoot)
            }
        }
        let temporaryDescriptor = Darwin.openat(
            stagingDescriptor,
            temporaryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard temporaryDescriptor >= 0 else {
            throw Self.systemCallFailure("openat(candidate-temporary)")
        }
        defer { Darwin.close(temporaryDescriptor) }

        let workspaceDescriptor = Darwin.open(
            workspacePath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard workspaceDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceRevisionMismatch
        }
        defer { Darwin.close(workspaceDescriptor) }

        var createdDirectories: Set<String> = []
        for entry in expected.entries {
            try copy(
                entry: entry,
                workspaceDescriptor: workspaceDescriptor,
                snapshotDescriptor: temporaryDescriptor,
                createdDirectories: &createdDirectories,
                writable: false
            )
        }
        guard try capture(root: workspace, expected: expected) == expected else {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceRevisionMismatch
        }
        try validateSnapshot(root: temporaryRoot, expected: expected)
        try makeReadOnly(
            rootDescriptor: temporaryDescriptor,
            directories: createdDirectories
        )
        guard fsync(temporaryDescriptor) == 0 else {
            throw Self.systemCallFailure("fsync(candidate-temporary)")
        }
        guard renameat(
            stagingDescriptor,
            temporaryName,
            stagingDescriptor,
            artifactName
        ) == 0 else {
            throw Self.systemCallFailure("renameat(candidate-postimage)")
        }
        installed = true
        guard fsync(stagingDescriptor) == 0 else {
            throw Self.systemCallFailure("fsync(candidate-postimages)")
        }

        let receipt = try validateInstalledSnapshot(
            root: finalRoot,
            expected: expected,
            attestation: attestation,
            materialization: .streamCopy,
            reused: false
        )
        return .materialized(receipt, attestation: attestation)
    }

    /// Creates an owner-private writable candidate whose complete initial tree
    /// equals the ratified source revision. This deliberately returns a
    /// pre-apply capability, not post-apply verification or activation
    /// authority, and starts no process.
    func materializePreApplyIsolation(
        runID: KernelRunID,
        contractID: TaskContractID,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        strategyFingerprint: StrategyFingerprint,
        isolationActor: ActorIdentity,
        sourceRevision: WorkspaceSourceRevisionArtifact,
        enrollmentJournalFrameDigest: ContentDigest,
        workspaceRoot: URL,
        runDirectory: URL,
        isolatedAt: Date
    ) throws -> AuthorizedWorkspacePreApplyCandidateIsolation {
        let workspace = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard sourceRevision.validationIssues().isEmpty,
              sourceRevision.workspaceID.rawValue.isEmpty == false,
              try capture(root: workspace, expected: sourceRevision) ==
                sourceRevision else {
            throw WorkspacePreApplyCandidateIsolationError.sourceRevisionMismatch
        }
        let journalRun = runDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        let run = Self.preApplyExecutionRoot(
            forJournalRunDirectory: journalRun
        )
        let workspacePath = workspace.path
        let journalRunPath = journalRun.path
        let executionPath = run.path
        guard run.isFileURL,
              executionPath != workspacePath,
              !executionPath.hasPrefix(workspacePath + "/"),
              !workspacePath.hasPrefix(executionPath + "/"),
              executionPath != journalRunPath,
              !executionPath.hasPrefix(journalRunPath + "/"),
              !journalRunPath.hasPrefix(executionPath + "/") else {
            throw WorkspaceCandidatePostimageMaterializationError
                .storageOverlapsWorkspace
        }

        do {
            try FileManager.default.createDirectory(
                at: run,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch CocoaError.fileWriteFileExists {
            // Existing storage is validated by descriptor below.
        } catch {
            throw WorkspaceCandidatePostimageMaterializationError
                .invalidRunDirectory
        }
        guard chmod(run.path, 0o700) == 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .invalidRunDirectory
        }

        let runDescriptor = Darwin.open(
            run.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard runDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .invalidRunDirectory
        }
        defer { Darwin.close(runDescriptor) }
        try validatePrivateDirectory(
            descriptor: runDescriptor,
            error: .invalidRunDirectory
        )

        if mkdirat(runDescriptor, Self.preApplyDirectoryName, 0o700) != 0,
           errno != EEXIST {
            throw Self.systemCallFailure("mkdirat(preapply-candidates)")
        }
        let stagingDescriptor = Darwin.openat(
            runDescriptor,
            Self.preApplyDirectoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard stagingDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeStagingDirectory
        }
        defer { Darwin.close(stagingDescriptor) }
        try validatePrivateDirectory(
            descriptor: stagingDescriptor,
            error: .unsafeStagingDirectory
        )

        let lockDescriptor = Darwin.openat(
            stagingDescriptor,
            Self.preApplyLockName,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard lockDescriptor >= 0 else {
            throw Self.systemCallFailure("openat(preapply-isolation-lock)")
        }
        defer { Darwin.close(lockDescriptor) }
        guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw Self.systemCallFailure("flock(preapply-isolation-lock)")
        }
        defer { flock(lockDescriptor, LOCK_UN) }

        let artifactName = preApplyArtifactName(
            runID: runID,
            contractID: contractID,
            attemptID: attemptID,
            nodeID: nodeID,
            strategyFingerprint: strategyFingerprint,
            sourceRevision: sourceRevision.sourceRevision,
            enrollmentJournalFrameDigest: enrollmentJournalFrameDigest
        )
        let stagingRoot = run.appendingPathComponent(
            Self.preApplyDirectoryName,
            isDirectory: true
        )
        let finalRoot = stagingRoot.appendingPathComponent(
            artifactName,
            isDirectory: true
        )
        if !directoryExists(
            named: artifactName,
            parentDescriptor: stagingDescriptor
        ) {
            let temporaryName = ".\(artifactName).\(UUID().uuidString).tmp"
            guard mkdirat(stagingDescriptor, temporaryName, 0o700) == 0 else {
                throw Self.systemCallFailure("mkdirat(preapply-temporary)")
            }
            let temporaryRoot = stagingRoot.appendingPathComponent(
                temporaryName,
                isDirectory: true
            )
            var installed = false
            defer {
                if !installed {
                    try? FileManager.default.removeItem(at: temporaryRoot)
                }
            }
            let temporaryDescriptor = Darwin.openat(
                stagingDescriptor,
                temporaryName,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard temporaryDescriptor >= 0 else {
                throw Self.systemCallFailure("openat(preapply-temporary)")
            }
            defer { Darwin.close(temporaryDescriptor) }
            let workspaceDescriptor = Darwin.open(
                workspace.path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard workspaceDescriptor >= 0 else {
                throw WorkspacePreApplyCandidateIsolationError
                    .sourceRevisionMismatch
            }
            defer { Darwin.close(workspaceDescriptor) }

            var createdDirectories: Set<String> = []
            for entry in sourceRevision.entries {
                try copy(
                    entry: entry,
                    workspaceDescriptor: workspaceDescriptor,
                    snapshotDescriptor: temporaryDescriptor,
                    createdDirectories: &createdDirectories,
                    writable: true
                )
            }
            guard try capture(root: workspace, expected: sourceRevision) ==
                    sourceRevision else {
                throw WorkspacePreApplyCandidateIsolationError
                    .sourceRevisionMismatch
            }
            try validateSnapshot(
                rootDescriptor: temporaryDescriptor,
                expected: sourceRevision,
                writable: true
            )
            guard fsync(temporaryDescriptor) == 0,
                  renameat(
                    stagingDescriptor,
                    temporaryName,
                    stagingDescriptor,
                    artifactName
                  ) == 0 else {
                throw Self.systemCallFailure("install(preapply-candidate)")
            }
            installed = true
            guard fsync(stagingDescriptor) == 0 else {
                throw Self.systemCallFailure("fsync(preapply-candidates)")
            }
        }

        let opened = try openValidatedPreApplyIsolation(
            root: finalRoot,
            runID: runID,
            contractID: contractID,
            attemptID: attemptID,
            nodeID: nodeID,
            strategyFingerprint: strategyFingerprint,
            isolationActor: isolationActor,
            sourceRevision: sourceRevision,
            enrollmentJournalFrameDigest: enrollmentJournalFrameDigest,
            isolatedAt: isolatedAt
        )
        return AuthorizedWorkspacePreApplyCandidateIsolation(
            receipt: opened.receipt,
            sourceRevision: sourceRevision,
            rootDescriptor: opened.descriptor
        )
    }

    func revalidatePreApplyIsolation(
        _ authority: AuthorizedWorkspacePreApplyCandidateIsolation
    ) throws -> WorkspacePreApplyCandidateIsolationReceipt {
        let original = authority.receipt
        let descriptor = try authority.descriptorForAcceptance()
        let observed = try validatePreApplyIsolation(
            rootDescriptor: descriptor,
            rootPath: original.candidateRootPath,
            runID: original.runID,
            contractID: original.contractID,
            attemptID: original.attemptID,
            nodeID: original.nodeID,
            strategyFingerprint: original.strategyFingerprint,
            isolationActor: original.isolationActor,
            sourceRevision: authority.sourceRevision,
            enrollmentJournalFrameDigest:
                original.enrollmentJournalFrameDigest,
            isolatedAt: original.isolatedAt
        )
        guard observed == original else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return observed
    }

    func activatePreApplyIsolation(
        _ authority: AuthorizedWorkspacePreApplyCandidateIsolation
    ) throws -> AuthorizedWorkspacePreApplyCandidateExecutionRoot {
        let observed = try revalidatePreApplyIsolation(authority)
        guard observed == authority.receipt else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        let descriptor = try authority.consumeDescriptorForActivation()
        return AuthorizedWorkspacePreApplyCandidateExecutionRoot(
            receipt: observed,
            sourceRevision: authority.sourceRevision,
            rootDescriptor: descriptor
        )
    }

    func revalidatePreApplyExecutionRoot(
        _ authority: AuthorizedWorkspacePreApplyCandidateExecutionRoot
    ) throws -> WorkspacePreApplyCandidateIsolationReceipt {
        let original = authority.receipt
        let descriptor = try authority.descriptorForRevalidation()
        let observed = try validatePreApplyIsolation(
            rootDescriptor: descriptor,
            rootPath: original.candidateRootPath,
            runID: original.runID,
            contractID: original.contractID,
            attemptID: original.attemptID,
            nodeID: original.nodeID,
            strategyFingerprint: original.strategyFingerprint,
            isolationActor: original.isolationActor,
            sourceRevision: authority.sourceRevision,
            enrollmentJournalFrameDigest:
                original.enrollmentJournalFrameDigest,
            isolatedAt: original.isolatedAt
        )
        guard observed == original else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return observed
    }

    /// Captures the exact post-worker tree through the descriptor retained by
    /// the production session. The returned revision deliberately projects the
    /// ratified workspace ID/root digest, while the receipt independently binds
    /// the physical candidate root and completed process provenance.
    func captureCompletedCandidate(
        _ authority: AuthorizedWorkspacePreApplyCandidateExecutionRoot,
        completion: KernelProductionProviderCompletionReceipt,
        captureActor: ActorIdentity,
        capturedAt: Date
    ) throws -> AuthorizedWorkspaceCompletedCandidateCapture {
        let isolation = authority.receipt
        let base = authority.sourceRevision
        let release = completion.release
        let parse = completion.parse
        let execution = completion.execution
        guard isolation.validationIssues().isEmpty,
              base.validationIssues().isEmpty,
              isolation.sourceRevision == base.sourceRevision,
              isolation.capturePolicyDigest == base.capturePolicyDigest,
              release.exit.handle.runID == isolation.runID,
              release.exit.handle.leaseID == release.release.leaseID,
              release.exit.handle.resourceID == release.release.resourceID,
              release.release.runID == isolation.runID,
              release.release.managedProcessExit == release.exit,
              release.release.managedProcessTermination == nil,
              release.exit.exitCode == 0,
              release.exit.terminationSignal == nil,
              parse.parse.runID == isolation.runID,
              parse.parse.attemptID == isolation.attemptID,
              parse.parse.nativeExit == release.exit,
              parse.parse.releaseReceiptID == release.release.id,
              execution.execution.runID == isolation.runID,
              execution.execution.attemptID == isolation.attemptID,
              execution.execution.source == .workerResultParse(parse.parse.id),
              execution.execution.sourceEvidenceDigest ==
                parse.parse.proposedResultDigest,
              execution.execution.disposition == .completed,
              !captureActor.id.rawValue.isEmpty,
              !captureActor.role.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              !captureActor.lineageDigest.rawValue.isEmpty else {
            throw WorkspaceCompletedCandidateCaptureError.invalidCompletion
        }
        guard case .released = release.release.outcome else {
            throw WorkspaceCompletedCandidateCaptureError.invalidCompletion
        }
        let rootDescriptor: Int32
        do {
            rootDescriptor = try authority.descriptorForRevalidation()
        } catch {
            throw WorkspaceCompletedCandidateCaptureError.invalidAuthority
        }
        var rootBefore = stat()
        guard fstat(rootDescriptor, &rootBefore) == 0,
              rootBefore.st_mode & S_IFMT == S_IFDIR,
              UInt64(rootBefore.st_dev) == isolation.deviceID,
              UInt64(rootBefore.st_ino) == isolation.inode else {
            throw WorkspaceCompletedCandidateCaptureError.invalidAuthority
        }

        let paths: [String]
        do {
            paths = try discoverSnapshotEntries(
                rootDescriptor: rootDescriptor,
                maximumFiles: base.limits.maximumFiles,
                excludedDirectoryNames: Set(base.excludedDirectoryNames)
            )
        } catch {
            throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
        }
        let baseByPath = Dictionary(uniqueKeysWithValues: base.entries.map {
            ($0.relativePath, $0)
        })
        var logicalEntries: [WorkspaceSourceRevisionEntry] = []
        var physicalEntries: [WorkspaceSourceRevisionEntry] = []
        var objectByDigest: [ContentDigest: WorkspaceMutationContentObject] = [:]
        var totalBytes: UInt64 = 0
        for path in paths {
            let captured = try readCompletedCandidateFile(
                path,
                rootDescriptor: rootDescriptor,
                maximumBytes: base.limits.maximumFileBytes
            )
            let logicalMode: UInt32
            if let original = baseByPath[path] {
                let normalized = candidateMode(original.mode, writable: true)
                logicalMode = captured.entry.mode == normalized
                    ? original.mode
                    : captured.entry.mode
            } else {
                logicalMode = captured.entry.mode
            }
            let (next, overflow) = totalBytes.addingReportingOverflow(
                captured.entry.size
            )
            guard !overflow, next <= base.limits.maximumTotalBytes else {
                throw WorkspaceCompletedCandidateCaptureError.limitExceeded
            }
            totalBytes = next
            physicalEntries.append(captured.entry)
            logicalEntries.append(WorkspaceSourceRevisionEntry(
                relativePath: path,
                mode: logicalMode,
                size: captured.entry.size,
                contentDigest: captured.entry.contentDigest
            ))
            if let existing = objectByDigest[captured.entry.contentDigest] {
                guard existing.data == captured.data else {
                    throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
                }
            } else {
                objectByDigest[captured.entry.contentDigest] =
                    WorkspaceMutationContentObject(
                        digest: captured.entry.contentDigest,
                        data: captured.data
                    )
            }
        }
        let pathsAfter: [String]
        do {
            pathsAfter = try discoverSnapshotEntries(
                rootDescriptor: rootDescriptor,
                maximumFiles: base.limits.maximumFiles,
                excludedDirectoryNames: Set(base.excludedDirectoryNames)
            )
        } catch {
            throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
        }
        var rootAfter = stat()
        guard pathsAfter == paths,
              fstat(rootDescriptor, &rootAfter) == 0,
              rootBefore.st_dev == rootAfter.st_dev,
              rootBefore.st_ino == rootAfter.st_ino,
              rootBefore.st_mode == rootAfter.st_mode,
              rootBefore.st_mtimespec.tv_sec == rootAfter.st_mtimespec.tv_sec,
              rootBefore.st_mtimespec.tv_nsec == rootAfter.st_mtimespec.tv_nsec else {
            throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
        }
        do {
            let rehashed = try paths.map {
                try WorkspaceSourceRevisionCollector.hashEntry(
                    relativePath: $0,
                    rootDescriptor: rootDescriptor,
                    maximumBytes: base.limits.maximumFileBytes
                )
            }
            guard rehashed == physicalEntries else {
                throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
            }
        } catch let error as WorkspaceCompletedCandidateCaptureError {
            throw error
        } catch {
            throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
        }

        let excludedNames = base.excludedDirectoryNames
        guard let sourceRevision = WorkspaceSourceRevisionArtifact.revisionDigest(
            schemaVersion: 1,
            workspaceID: base.workspaceID,
            canonicalRootDigest: base.canonicalRootDigest,
            excludedDirectoryNames: excludedNames,
            limits: base.limits,
            capturePolicyDigest: base.capturePolicyDigest,
            entries: logicalEntries,
            totalBytes: totalBytes
        ) else {
            throw WorkspaceCompletedCandidateCaptureError.encodingFailed
        }
        let candidateRevision = WorkspaceSourceRevisionArtifact(
            schemaVersion: 1,
            workspaceID: base.workspaceID,
            canonicalRootDigest: base.canonicalRootDigest,
            excludedDirectoryNames: excludedNames,
            limits: base.limits,
            capturePolicyDigest: base.capturePolicyDigest,
            entries: logicalEntries,
            totalBytes: totalBytes,
            sourceRevision: sourceRevision
        )
        guard candidateRevision.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateCaptureError.encodingFailed
        }
        let objects = objectByDigest.values.sorted {
            $0.digest.rawValue < $1.digest.rawValue
        }
        let references = objects.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        let uniqueBytes = references.reduce(UInt64(0)) { $0 + $1.size }
        var receipt = WorkspaceCompletedCandidateCaptureReceipt(
            schemaVersion: 1,
            runID: isolation.runID,
            contractID: isolation.contractID,
            attemptID: isolation.attemptID,
            nodeID: isolation.nodeID,
            strategyFingerprint: isolation.strategyFingerprint,
            workspaceID: base.workspaceID,
            canonicalRootDigest: base.canonicalRootDigest,
            baseSourceRevision: base.sourceRevision,
            candidateSourceRevision: candidateRevision.sourceRevision,
            capturePolicyDigest: base.capturePolicyDigest,
            candidateRevision: candidateRevision,
            isolationReceiptDigest: isolation.receiptDigest,
            candidateRootPath: isolation.candidateRootPath,
            candidateCanonicalRootDigest: isolation.candidateCanonicalRootDigest,
            candidateEntryManifestDigest: manifestDigest(physicalEntries),
            candidateDeviceID: isolation.deviceID,
            candidateInode: isolation.inode,
            releaseReceiptID: release.release.id,
            releaseJournalFrameDigest: release.journalTransaction.frameDigest,
            parseReceiptID: parse.parse.id,
            parseJournalFrameDigest: parse.journalTransaction.frameDigest,
            executionReceiptID: execution.execution.id,
            executionJournalFrameDigest: execution.journalTransaction.frameDigest,
            executionSourceEvidenceDigest:
                execution.execution.sourceEvidenceDigest,
            captureActor: captureActor,
            capturedAt: capturedAt,
            contentObjects: references,
            objectSetDigest:
                WorkspaceMutationFilesystemExecutor.objectSetDigest(objects),
            fileCount: logicalEntries.count,
            totalFileBytes: totalBytes,
            objectCount: objects.count,
            uniqueObjectBytes: uniqueBytes,
            receiptDigest: ContentDigest("")
        )
        guard let receiptDigest = WorkspaceCompletedCandidateCaptureReceipt
            .digest(for: receipt) else {
            throw WorkspaceCompletedCandidateCaptureError.encodingFailed
        }
        receipt.receiptDigest = receiptDigest
        let capability = AuthorizedWorkspaceCompletedCandidateCapture(
            receipt: receipt,
            candidateRevision: candidateRevision,
            objects: objects,
            isolationReceipt: isolation
        )
        guard capability.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateCaptureError.encodingFailed
        }
        return capability
    }

    /// Rehashes the sealed tree and rechecks its root identity immediately
    /// before a future verifier consumes the path. The future process runtime
    /// must compose this check with admission; materialization alone starts no
    /// process and grants no verification result authority.
    func revalidate(
        _ input: AuthorizedWorkspaceCandidatePostimageInput
    ) throws -> WorkspaceCandidatePostimageMaterializationReceipt {
        let original = input.receipt
        let observed = try validateInstalledSnapshot(
            root: URL(
                fileURLWithPath: original.snapshotRootPath,
                isDirectory: true
            ),
            expected: input.attestation.candidatePostimage,
            attestation: input.attestation,
            materialization: original.materialization,
            reused: original.reusedExistingArtifact
        )
        guard observed == original else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return observed
    }

    /// Opens the receipt-bound root without following links and validates the
    /// complete tree through that same descriptor. The returned capability
    /// keeps the root object alive across journal admission and native spawn.
    func openRevalidatedDescriptor(
        _ input: AuthorizedWorkspaceCandidatePostimageInput
    ) throws -> AuthorizedWorkspaceCandidatePostimageDescriptor {
        let original = input.receipt
        let opened = Darwin.open(
            original.snapshotRootPath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard opened >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeExistingArtifact
        }
        let descriptor = Darwin.fcntl(opened, F_DUPFD_CLOEXEC, 210)
        let duplicateErrno = errno
        _ = Darwin.close(opened)
        guard descriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .systemCallFailed(
                    operation: "fcntl(candidate-root)",
                    errno: duplicateErrno
                )
        }
        do {
            var before = stat()
            guard fstat(descriptor, &before) == 0,
                  before.st_mode & S_IFMT == S_IFDIR,
                  before.st_uid == geteuid(),
                  before.st_mode & 0o222 == 0,
                  UInt64(before.st_dev) == original.deviceID,
                  UInt64(before.st_ino) == original.inode else {
                throw WorkspaceCandidatePostimageMaterializationError
                    .unsafeExistingArtifact
            }
            try validateSnapshot(
                rootDescriptor: descriptor,
                expected: input.attestation.candidatePostimage
            )
            var after = stat()
            guard fstat(descriptor, &after) == 0,
                  before.st_dev == after.st_dev,
                  before.st_ino == after.st_ino,
                  before.st_mode == after.st_mode else {
                throw WorkspaceCandidatePostimageMaterializationError
                    .existingArtifactMismatch
            }
            return AuthorizedWorkspaceCandidatePostimageDescriptor(
                receipt: original,
                descriptor: descriptor
            )
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    /// Revalidates the complete sealed tree through the same held descriptor
    /// after a consumer has read it. This avoids falling back to the mutable
    /// pathname between candidate-byte extraction and journal admission.
    func revalidateHeldDescriptor(
        _ authority: AuthorizedWorkspaceCandidatePostimageDescriptor,
        input: AuthorizedWorkspaceCandidatePostimageInput
    ) throws -> WorkspaceCandidatePostimageMaterializationReceipt {
        guard authority.receipt == input.receipt else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        let descriptor = try authority.descriptorForLaunch(
            matching: input.receipt
        )
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        try validateSnapshot(
            rootDescriptor: descriptor,
            expected: input.attestation.candidatePostimage
        )
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              UInt64(after.st_dev) == input.receipt.deviceID,
              UInt64(after.st_ino) == input.receipt.inode else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        return input.receipt
    }

    private func capture(
        root: URL,
        expected: WorkspaceSourceRevisionArtifact
    ) throws -> WorkspaceSourceRevisionArtifact {
        do {
            return try WorkspaceSourceRevisionCollector().capture(
                workspaceID: expected.workspaceID,
                root: root,
                excludedDirectoryNames: Set(expected.excludedDirectoryNames),
                limits: expected.limits
            )
        } catch {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceRevisionMismatch
        }
    }

    private func copy(
        entry: WorkspaceSourceRevisionEntry,
        workspaceDescriptor: Int32,
        snapshotDescriptor: Int32,
        createdDirectories: inout Set<String>,
        writable: Bool
    ) throws {
        let components = entry.relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(WorkspaceSourceRevisionCollector.validPathComponent) else {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceRevisionMismatch
        }
        let parentComponents = Array(components.dropLast())
        let parent = try openDirectory(
            components: parentComponents,
            rootDescriptor: snapshotDescriptor,
            create: true,
            createdDirectories: &createdDirectories
        )
        defer { Darwin.close(parent) }
        let source: Int32
        do {
            source = try WorkspaceSourceRevisionCollector.openRegularFile(
                entry.relativePath,
                rootDescriptor: workspaceDescriptor
            )
        } catch {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceChangedDuringMaterialization(entry.relativePath)
        }
        defer { Darwin.close(source) }
        var before = stat()
        guard fstat(source, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0,
              UInt32(before.st_mode & 0o7777) == entry.mode,
              UInt64(before.st_size) == entry.size else {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceChangedDuringMaterialization(entry.relativePath)
        }

        let destination = components.last!.withCString {
            Darwin.openat(
                parent,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o400)
            )
        }
        guard destination >= 0 else {
            throw Self.systemCallFailure("openat(candidate-file)")
        }
        defer { Darwin.close(destination) }

        var hasher = SHA256()
        var copied: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(source, bytes.baseAddress, bytes.count)
            }
            if readCount == 0 { break }
            guard readCount > 0 else {
                if errno == EINTR { continue }
                throw Self.systemCallFailure("read(candidate-source)")
            }
            let count = Int(readCount)
            copied += UInt64(count)
            guard copied <= entry.size else {
                throw WorkspaceCandidatePostimageMaterializationError
                    .sourceChangedDuringMaterialization(entry.relativePath)
            }
            hasher.update(data: Data(buffer[0..<count]))
            var written = 0
            while written < count {
                let writeCount = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        destination,
                        bytes.baseAddress!.advanced(by: written),
                        count - written
                    )
                }
                guard writeCount > 0 else {
                    if writeCount < 0, errno == EINTR { continue }
                    throw Self.systemCallFailure("write(candidate-snapshot)")
                }
                written += Int(writeCount)
            }
        }
        var after = stat()
        guard fstat(source, &after) == 0,
              copied == entry.size,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              ContentDigest(hasher.finalize().map {
                  String(format: "%02x", $0)
              }.joined()) == entry.contentDigest else {
            throw WorkspaceCandidatePostimageMaterializationError
                .sourceChangedDuringMaterialization(entry.relativePath)
        }
        guard fchmod(
            destination,
            mode_t(candidateMode(entry.mode, writable: writable))
        ) == 0,
              fsync(destination) == 0 else {
            throw Self.systemCallFailure("seal(candidate-file)")
        }
    }

    private func openDirectory(
        components: [String],
        rootDescriptor: Int32,
        create: Bool,
        createdDirectories: inout Set<String>
    ) throws -> Int32 {
        var current = Darwin.dup(rootDescriptor)
        guard current >= 0 else {
            throw Self.systemCallFailure("dup(candidate-root)")
        }
        var pathComponents: [String] = []
        for component in components {
            pathComponents.append(component)
            if create,
               mkdirat(current, component, 0o700) == 0 {
                createdDirectories.insert(pathComponents.joined(separator: "/"))
            } else if create, errno != EEXIST {
                Darwin.close(current)
                throw Self.systemCallFailure("mkdirat(candidate-directory)")
            }
            let next = component.withCString {
                Darwin.openat(
                    current,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            Darwin.close(current)
            guard next >= 0 else {
                throw Self.systemCallFailure("openat(candidate-directory)")
            }
            current = next
        }
        return current
    }

    private func validateSnapshot(
        root: URL,
        expected: WorkspaceSourceRevisionArtifact,
        writable: Bool = false
    ) throws {
        let observed: WorkspaceSourceRevisionArtifact
        do {
            observed = try WorkspaceSourceRevisionCollector().capture(
                workspaceID: expected.workspaceID,
                root: root,
                excludedDirectoryNames: [],
                limits: expected.limits
            )
        } catch {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        let expectedEntries = expected.entries.map {
            WorkspaceSourceRevisionEntry(
                relativePath: $0.relativePath,
                mode: candidateMode($0.mode, writable: writable),
                size: $0.size,
                contentDigest: $0.contentDigest
            )
        }
        guard observed.entries == expectedEntries,
              observed.totalBytes == expected.totalBytes else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
    }

    private func validateSnapshot(
        rootDescriptor: Int32,
        expected: WorkspaceSourceRevisionArtifact,
        writable: Bool = false
    ) throws {
        do {
            let before = try discoverSnapshotEntries(
                rootDescriptor: rootDescriptor,
                maximumFiles: expected.limits.maximumFiles
            )
            var observed: [WorkspaceSourceRevisionEntry] = []
            observed.reserveCapacity(before.count)
            var totalBytes: UInt64 = 0
            for relativePath in before {
                let entry = try WorkspaceSourceRevisionCollector.hashEntry(
                    relativePath: relativePath,
                    rootDescriptor: rootDescriptor,
                    maximumBytes: expected.limits.maximumFileBytes
                )
                let (next, overflow) = totalBytes.addingReportingOverflow(
                    entry.size
                )
                guard !overflow,
                      next <= expected.limits.maximumTotalBytes else {
                    throw WorkspaceCandidatePostimageMaterializationError
                        .existingArtifactMismatch
                }
                totalBytes = next
                observed.append(entry)
            }
            let after = try discoverSnapshotEntries(
                rootDescriptor: rootDescriptor,
                maximumFiles: expected.limits.maximumFiles
            )
            let expectedEntries = expected.entries.map {
                WorkspaceSourceRevisionEntry(
                    relativePath: $0.relativePath,
                    mode: candidateMode($0.mode, writable: writable),
                    size: $0.size,
                    contentDigest: $0.contentDigest
                )
            }
            guard before == after,
                  observed == expectedEntries,
                  totalBytes == expected.totalBytes else {
                throw WorkspaceCandidatePostimageMaterializationError
                    .existingArtifactMismatch
            }
        } catch let error as WorkspaceCandidatePostimageMaterializationError {
            throw error
        } catch {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
    }

    private func discoverSnapshotEntries(
        rootDescriptor: Int32,
        maximumFiles: Int,
        excludedDirectoryNames: Set<String> = []
    ) throws -> [String] {
        var paths: [String] = []
        try discoverSnapshotEntries(
            directoryDescriptor: rootDescriptor,
            prefix: "",
            maximumFiles: maximumFiles,
            excludedDirectoryNames: excludedDirectoryNames,
            paths: &paths
        )
        return paths.sorted()
    }

    private func readCompletedCandidateFile(
        _ relativePath: String,
        rootDescriptor: Int32,
        maximumBytes: UInt64
    ) throws -> (entry: WorkspaceSourceRevisionEntry, data: Data) {
        let descriptor: Int32
        do {
            descriptor = try WorkspaceSourceRevisionCollector.openRegularFile(
                relativePath,
                rootDescriptor: rootDescriptor
            )
        } catch {
            throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0 else {
            throw WorkspaceCompletedCandidateCaptureError
                .systemCallFailed(operation: "fstat(candidate-file)", errno: errno)
        }
        let expectedSize = UInt64(before.st_size)
        guard expectedSize <= maximumBytes,
              expectedSize <= UInt64(Int.max) else {
            throw WorkspaceCompletedCandidateCaptureError.limitExceeded
        }
        var data = Data()
        data.reserveCapacity(Int(expectedSize))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw WorkspaceCompletedCandidateCaptureError
                    .systemCallFailed(operation: "read(candidate-file)", errno: errno)
            }
            data.append(contentsOf: buffer[0..<Int(count)])
            guard UInt64(data.count) <= expectedSize else {
                throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
            }
        }
        var after = stat()
        guard UInt64(data.count) == expectedSize,
              fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw WorkspaceCompletedCandidateCaptureError.unstableCandidate
        }
        let digest = WorkspaceMutationFilesystemExecutor.contentDigest(data)
        return (
            WorkspaceSourceRevisionEntry(
                relativePath: relativePath,
                mode: UInt32(before.st_mode & 0o7777),
                size: expectedSize,
                contentDigest: digest
            ),
            data
        )
    }

    private func discoverSnapshotEntries(
        directoryDescriptor: Int32,
        prefix: String,
        maximumFiles: Int,
        excludedDirectoryNames: Set<String>,
        paths: inout [String]
    ) throws {
        // `dup` would share a directory stream offset with the held authority
        // and make the second listing observe EOF. `openat(".")` creates an
        // independent open-file description rooted at the same directory.
        let duplicate = Darwin.openat(
            directoryDescriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard duplicate >= 0, let directory = fdopendir(duplicate) else {
            if duplicate >= 0 { _ = Darwin.close(duplicate) }
            throw Self.systemCallFailure("fdopendir(candidate-root)")
        }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
                String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            if name == "." || name == ".." { continue }
            guard WorkspaceSourceRevisionCollector.validPathComponent(name) else {
                throw WorkspaceCandidatePostimageMaterializationError
                    .existingArtifactMismatch
            }
            names.append(name)
        }
        guard errno == 0 else {
            throw Self.systemCallFailure("readdir(candidate-root)")
        }
        for name in names.sorted() {
            var status = stat()
            guard fstatat(
                directoryDescriptor,
                name,
                &status,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                throw Self.systemCallFailure("fstatat(candidate-entry)")
            }
            let relativePath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            switch status.st_mode & S_IFMT {
            case S_IFDIR:
                if excludedDirectoryNames.contains(name) { continue }
                let child = name.withCString {
                    Darwin.openat(
                        directoryDescriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                    )
                }
                guard child >= 0 else {
                    throw Self.systemCallFailure("openat(candidate-entry)")
                }
                defer { _ = Darwin.close(child) }
                try discoverSnapshotEntries(
                    directoryDescriptor: child,
                    prefix: relativePath,
                    maximumFiles: maximumFiles,
                    excludedDirectoryNames: excludedDirectoryNames,
                    paths: &paths
                )
            case S_IFREG:
                paths.append(relativePath)
                guard paths.count <= maximumFiles else {
                    throw WorkspaceCandidatePostimageMaterializationError
                        .existingArtifactMismatch
                }
            default:
                throw WorkspaceCandidatePostimageMaterializationError
                    .existingArtifactMismatch
            }
        }
    }

    private func validateInstalledSnapshot(
        root: URL,
        expected: WorkspaceSourceRevisionArtifact,
        attestation: WorkspaceCandidatePostimageAttestationReceipt,
        materialization: WorkspaceCandidatePostimageMaterialization,
        reused: Bool
    ) throws -> WorkspaceCandidatePostimageMaterializationReceipt {
        let descriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeExistingArtifact
        }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o222 == 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeExistingArtifact
        }
        try validateSnapshot(root: root, expected: expected)
        let expectedEntries = expected.entries.map {
            WorkspaceSourceRevisionEntry(
                relativePath: $0.relativePath,
                mode: snapshotMode($0.mode),
                size: $0.size,
                contentDigest: $0.contentDigest
            )
        }
        return WorkspaceCandidatePostimageMaterializationReceipt(
            workspaceID: expected.workspaceID,
            applyReceiptID: attestation.applyReceiptID,
            sourceRevision: expected.sourceRevision,
            capturePolicyDigest: expected.capturePolicyDigest,
            attestationJournalFrameDigest: attestation.journalTransaction.frameDigest,
            snapshotRootPath: root.path,
            snapshotCanonicalRootDigest:
                WorkspaceRepositoryIndexer.canonicalRootDigest(root),
            snapshotEntryManifestDigest: manifestDigest(expectedEntries),
            fileCount: expectedEntries.count,
            totalBytes: expected.totalBytes,
            deviceID: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            materialization: materialization,
            reusedExistingArtifact: reused
        )
    }

    private func validatePreApplyIsolation(
        rootDescriptor descriptor: Int32,
        rootPath: String,
        runID: KernelRunID,
        contractID: TaskContractID,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        strategyFingerprint: StrategyFingerprint,
        isolationActor: ActorIdentity,
        sourceRevision: WorkspaceSourceRevisionArtifact,
        enrollmentJournalFrameDigest: ContentDigest,
        isolatedAt: Date
    ) throws -> WorkspacePreApplyCandidateIsolationReceipt {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0,
              status.st_mode & 0o700 == 0o700 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeExistingArtifact
        }
        let pathDescriptor = Darwin.open(
            rootPath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard pathDescriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeExistingArtifact
        }
        defer { Darwin.close(pathDescriptor) }
        var pathStatus = stat()
        guard fstat(pathDescriptor, &pathStatus) == 0,
              pathStatus.st_dev == status.st_dev,
              pathStatus.st_ino == status.st_ino else {
            throw WorkspaceCandidatePostimageMaterializationError
                .existingArtifactMismatch
        }
        try validateSnapshot(
            rootDescriptor: descriptor,
            expected: sourceRevision,
            writable: true
        )
        let durableIsolatedAt = Date(
            timeIntervalSince1970: floor(
                isolatedAt.timeIntervalSince1970 * 1_000
            ) / 1_000
        )
        let expectedEntries = sourceRevision.entries.map {
            WorkspaceSourceRevisionEntry(
                relativePath: $0.relativePath,
                mode: candidateMode($0.mode, writable: true),
                size: $0.size,
                contentDigest: $0.contentDigest
            )
        }
        var receipt = WorkspacePreApplyCandidateIsolationReceipt(
            schemaVersion: 1,
            runID: runID,
            contractID: contractID,
            attemptID: attemptID,
            nodeID: nodeID,
            strategyFingerprint: strategyFingerprint,
            isolationActor: isolationActor,
            sourceRevision: sourceRevision.sourceRevision,
            capturePolicyDigest: sourceRevision.capturePolicyDigest,
            enrollmentJournalFrameDigest: enrollmentJournalFrameDigest,
            candidateRootPath: rootPath,
            candidateCanonicalRootDigest:
                WorkspaceRepositoryIndexer.canonicalRootDigest(URL(
                    fileURLWithPath: rootPath,
                    isDirectory: true
                )),
            candidateEntryManifestDigest:
                Self.preApplyCandidateEntryManifestDigest(sourceRevision),
            fileCount: expectedEntries.count,
            totalBytes: sourceRevision.totalBytes,
            deviceID: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            isolatedAt: durableIsolatedAt,
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspacePreApplyCandidateIsolationReceipt.digest(
            receipt.digestMaterial
        ) else {
            throw WorkspacePreApplyCandidateIsolationError.receiptEncodingFailed
        }
        receipt.receiptDigest = digest
        guard receipt.validationIssues().isEmpty else {
            throw WorkspacePreApplyCandidateIsolationError.receiptEncodingFailed
        }
        return receipt
    }

    private func openValidatedPreApplyIsolation(
        root: URL,
        runID: KernelRunID,
        contractID: TaskContractID,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        strategyFingerprint: StrategyFingerprint,
        isolationActor: ActorIdentity,
        sourceRevision: WorkspaceSourceRevisionArtifact,
        enrollmentJournalFrameDigest: ContentDigest,
        isolatedAt: Date
    ) throws -> (
        receipt: WorkspacePreApplyCandidateIsolationReceipt,
        descriptor: Int32
    ) {
        let opened = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard opened >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .unsafeExistingArtifact
        }
        let descriptor = Darwin.fcntl(opened, F_DUPFD_CLOEXEC, 210)
        let duplicateErrno = errno
        _ = Darwin.close(opened)
        guard descriptor >= 0 else {
            throw WorkspaceCandidatePostimageMaterializationError
                .systemCallFailed(
                    operation: "fcntl(preapply-candidate-root)",
                    errno: duplicateErrno
                )
        }
        do {
            let receipt = try validatePreApplyIsolation(
                rootDescriptor: descriptor,
                rootPath: root.path,
                runID: runID,
                contractID: contractID,
                attemptID: attemptID,
                nodeID: nodeID,
                strategyFingerprint: strategyFingerprint,
                isolationActor: isolationActor,
                sourceRevision: sourceRevision,
                enrollmentJournalFrameDigest:
                    enrollmentJournalFrameDigest,
                isolatedAt: isolatedAt
            )
            return (receipt, descriptor)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private func preApplyArtifactName(
        runID: KernelRunID,
        contractID: TaskContractID,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        strategyFingerprint: StrategyFingerprint,
        sourceRevision: ContentDigest,
        enrollmentJournalFrameDigest: ContentDigest
    ) -> String {
        struct Material: Codable {
            var runID: KernelRunID
            var contractID: TaskContractID
            var attemptID: AttemptID
            var nodeID: KernelNodeID
            var strategyFingerprint: StrategyFingerprint
            var sourceRevision: ContentDigest
            var enrollmentJournalFrameDigest: ContentDigest
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let material = Material(
            runID: runID,
            contractID: contractID,
            attemptID: attemptID,
            nodeID: nodeID,
            strategyFingerprint: strategyFingerprint,
            sourceRevision: sourceRevision,
            enrollmentJournalFrameDigest: enrollmentJournalFrameDigest
        )
        let data = (try? encoder.encode(material)) ?? Data()
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func makeReadOnly(
        rootDescriptor: Int32,
        directories: Set<String>
    ) throws {
        for relativePath in directories.sorted(by: {
            $0.split(separator: "/").count > $1.split(separator: "/").count
        }) {
            var ignored: Set<String> = []
            let descriptor = try openDirectory(
                components: relativePath.split(separator: "/").map(String.init),
                rootDescriptor: rootDescriptor,
                create: false,
                createdDirectories: &ignored
            )
            guard fchmod(descriptor, mode_t(0o500)) == 0,
                  fsync(descriptor) == 0 else {
                Darwin.close(descriptor)
                throw Self.systemCallFailure("seal(candidate-directory)")
            }
            Darwin.close(descriptor)
        }
        guard fchmod(rootDescriptor, mode_t(0o500)) == 0 else {
            throw Self.systemCallFailure("seal(candidate-root)")
        }
    }

    private func validatePrivateDirectory(
        descriptor: Int32,
        error: WorkspaceCandidatePostimageMaterializationError
    ) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_mode & 0o077 == 0,
              status.st_mode & 0o500 == 0o500 else {
            throw error
        }
    }

    private func directoryExists(
        named name: String,
        parentDescriptor: Int32
    ) -> Bool {
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { return false }
        Darwin.close(descriptor)
        return true
    }

    private func snapshotMode(_ sourceMode: UInt32) -> UInt32 {
        candidateMode(sourceMode, writable: false)
    }

    private func candidateMode(
        _ sourceMode: UInt32,
        writable: Bool
    ) -> UInt32 {
        (writable ? 0o600 : 0o400) | (sourceMode & 0o111)
    }

    private func manifestDigest(
        _ entries: [WorkspaceSourceRevisionEntry]
    ) -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(entries)) ?? Data()
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    static func preApplyCandidateEntryManifestDigest(
        _ sourceRevision: WorkspaceSourceRevisionArtifact
    ) -> ContentDigest {
        let entries = sourceRevision.entries.map {
            WorkspaceSourceRevisionEntry(
                relativePath: $0.relativePath,
                mode: 0o600 | ($0.mode & 0o111),
                size: $0.size,
                contentDigest: $0.contentDigest
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(entries)) ?? Data()
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func systemCallFailure(
        _ operation: String
    ) -> WorkspaceCandidatePostimageMaterializationError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
