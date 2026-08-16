import CryptoKit
import Darwin
import Foundation

/// Durable evidence describing bytes observed from the exact baseline that a
/// ratified, journal-enrolled contract bound. This value is intentionally inert;
/// only `AuthorizedWorkspaceRatifiedBaselineContent` carries the observed bytes.
struct WorkspaceRatifiedBaselineContentCaptureReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var ratificationReceiptID: ReceiptID
    var enrollmentJournalFrameDigest: ContentDigest
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var captureActor: ActorIdentity
    var capturedAt: Date
    var derivationDigest: ContentDigest
    var baseSourceRevision: ContentDigest
    var capturePolicyDigest: ContentDigest
    var contentObjects: [WorkspaceMutationContentReference]
    var objectSetDigest: ContentDigest
    var objectCount: Int
    var totalBytes: UInt64
    var rootDeviceID: UInt64
    var rootInode: UInt64
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported baseline-content schema") }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || ratificationReceiptID.rawValue.isEmpty
            || workspaceID.rawValue.isEmpty
            || captureActor.id.rawValue.isEmpty
            || captureActor.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || captureActor.lineageDigest.rawValue.isEmpty {
            issues.append("baseline-content authority identity must not be empty")
        }
        for digest in [
            enrollmentJournalFrameDigest,
            canonicalRootDigest,
            derivationDigest,
            baseSourceRevision,
            capturePolicyDigest,
            objectSetDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("baseline-content authority digests must be SHA-256")
        }
        if contentObjects != contentObjects.sorted(by: {
            $0.contentDigest.rawValue < $1.contentDigest.rawValue
        }) || Set(contentObjects.map(\.contentDigest)).count != contentObjects.count {
            issues.append("baseline content references must be uniquely digest-sorted")
        }
        var observedTotal: UInt64 = 0
        for object in contentObjects {
            if !Self.isSHA256(object.contentDigest) {
                issues.append("baseline content digest must be SHA-256")
            }
            let (next, overflow) = observedTotal.addingReportingOverflow(object.size)
            if overflow {
                issues.append("baseline content byte count overflowed")
                observedTotal = .max
            } else {
                observedTotal = next
            }
        }
        if objectCount != contentObjects.count || totalBytes != observedTotal {
            issues.append("baseline content cardinality is inconsistent")
        }
        if rootDeviceID == 0 || rootInode == 0 {
            issues.append("baseline root identity must not be empty")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("baseline-content receipt digest mismatch")
        }
        return issues
    }

    static func digest(
        for receipt: WorkspaceRatifiedBaselineContentCaptureReceipt
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            runID: receipt.runID,
            contractID: receipt.contractID,
            ratificationReceiptID: receipt.ratificationReceiptID,
            enrollmentJournalFrameDigest: receipt.enrollmentJournalFrameDigest,
            workspaceID: receipt.workspaceID,
            canonicalRootDigest: receipt.canonicalRootDigest,
            captureActor: receipt.captureActor,
            capturedAt: receipt.capturedAt,
            derivationDigest: receipt.derivationDigest,
            baseSourceRevision: receipt.baseSourceRevision,
            capturePolicyDigest: receipt.capturePolicyDigest,
            contentObjects: receipt.contentObjects,
            objectSetDigest: receipt.objectSetDigest,
            objectCount: receipt.objectCount,
            totalBytes: receipt.totalBytes,
            rootDeviceID: receipt.rootDeviceID,
            rootInode: receipt.rootInode
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
        var contractID: TaskContractID
        var ratificationReceiptID: ReceiptID
        var enrollmentJournalFrameDigest: ContentDigest
        var workspaceID: WorkspaceID
        var canonicalRootDigest: ContentDigest
        var captureActor: ActorIdentity
        var capturedAt: Date
        var derivationDigest: ContentDigest
        var baseSourceRevision: ContentDigest
        var capturePolicyDigest: ContentDigest
        var contentObjects: [WorkspaceMutationContentReference]
        var objectSetDigest: ContentDigest
        var objectCount: Int
        var totalBytes: UInt64
        var rootDeviceID: UInt64
        var rootInode: UInt64
    }
}

/// Non-serializable capability carrying the exact bytes observed by the
/// registry/journal-backed issuer. A decoded receipt cannot manufacture it.
struct AuthorizedWorkspaceRatifiedBaselineContent: Sendable {
    let receipt: WorkspaceRatifiedBaselineContentCaptureReceipt
    let objects: [WorkspaceMutationContentObject]

    fileprivate init(
        receipt: WorkspaceRatifiedBaselineContentCaptureReceipt,
        objects: [WorkspaceMutationContentObject]
    ) {
        self.receipt = receipt
        self.objects = objects
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
        if references != receipt.contentObjects
            || objects.count != receipt.objectCount
            || WorkspaceMutationFilesystemExecutor.objectSetDigest(objects) !=
                receipt.objectSetDigest
            || objects.contains(where: {
                WorkspaceMutationFilesystemExecutor.contentDigest($0.data) !=
                    $0.digest
            }) {
            issues.append("baseline-content capability bytes do not match its receipt")
        }
        return issues
    }

#if DEBUG
    static func testOnly(
        receipt: WorkspaceRatifiedBaselineContentCaptureReceipt,
        objects: [WorkspaceMutationContentObject]
    ) -> AuthorizedWorkspaceRatifiedBaselineContent {
        AuthorizedWorkspaceRatifiedBaselineContent(
            receipt: receipt,
            objects: objects
        )
    }
#endif
}

enum WorkspaceRatifiedBaselineContentCaptureError:
    Error,
    Equatable,
    Sendable
{
    case invalidEnrollment
    case registrationMismatch
    case journalMismatch
    case invalidDerivation
    case baselineAuthorityMismatch
    case baselineChanged
    case missingContent(ContentDigest)
    case corruptContent(ContentDigest)
    case systemCallFailed(operation: String, errno: Int32)
    case encodingFailed
}

/// Reads only the baseline plane of a derived mutation from the exact
/// production-enrolled workspace. Registry lookup, journal replay, contract
/// equality, a complete before/after source recapture, and descriptor-stable
/// byte reads all have to agree before an ephemeral capability is returned.
///
/// Candidate bytes remain deliberately out of scope: this issuer cannot mint
/// a complete content set, a journal acceptance, or preflight authority.
actor WorkspaceRatifiedBaselineContentCaptureIssuer {
    private let registry: WorkspaceMutationRecoveryRegistry

    init(registry: WorkspaceMutationRecoveryRegistry) {
        self.registry = registry
    }

    func capture(
        enrollment: KernelRunEnrollmentReceipt,
        derivation: WorkspaceMutationOperationDerivationReceipt
    ) async throws -> AuthorizedWorkspaceRatifiedBaselineContent {
        guard enrollment.schemaVersion == 1,
              enrollment.runID == enrollment.registration.runID,
              enrollment.contractID.rawValue.isEmpty == false,
              enrollment.ratificationReceiptID.rawValue.isEmpty == false,
              enrollment.journalTransaction.frameDigest.rawValue.isEmpty == false else {
            throw WorkspaceRatifiedBaselineContentCaptureError.invalidEnrollment
        }
        guard let registration = try await registry.registration(
            runID: enrollment.runID
        ), registration == enrollment.registration,
              registration.enrollmentEvidence?.authority == .ratifiedUserContract,
              registration.enrollmentEvidence?.contractID == enrollment.contractID,
              registration.enrollmentEvidence?.ratificationReceiptID ==
                enrollment.ratificationReceiptID,
              registration.enrollmentEvidence?.journalFrameDigest ==
                enrollment.journalTransaction.frameDigest,
              registration.enrollmentEvidence?.journalEndingSequence ==
                enrollment.journalTransaction.endingSequence else {
            throw WorkspaceRatifiedBaselineContentCaptureError.registrationMismatch
        }
        let journal: RunJournal
        do {
            journal = try RunJournal(
                rootDirectory: registration.journalRoot,
                runID: registration.runID
            )
        } catch {
            throw WorkspaceRatifiedBaselineContentCaptureError.journalMismatch
        }
        guard await journal.transactionReceipt(
            commandID: enrollment.journalTransaction.commandID
        ) == enrollment.journalTransaction,
              let contract = await journal.currentContract(),
              contract.id == enrollment.contractID,
              let baseline = contract.sourceRevision,
              let workspaceBinding = contract.workspaceBinding else {
            throw WorkspaceRatifiedBaselineContentCaptureError.journalMismatch
        }
        guard derivation.validationIssues().isEmpty else {
            throw WorkspaceRatifiedBaselineContentCaptureError.invalidDerivation
        }
        guard baseline.validationIssues().isEmpty,
              baseline.workspaceID == registration.workspaceID,
              baseline.workspaceID == derivation.workspaceID,
              baseline.canonicalRootDigest == workspaceBinding.canonicalRootDigest,
              baseline.canonicalRootDigest == derivation.canonicalRootDigest,
              baseline.capturePolicyDigest == derivation.capturePolicyDigest,
              baseline.sourceRevision == derivation.baseSourceRevision else {
            throw WorkspaceRatifiedBaselineContentCaptureError
                .baselineAuthorityMismatch
        }

        let workspace = registration.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        guard WorkspaceRepositoryIndexer.canonicalRootDigest(workspace) ==
                baseline.canonicalRootDigest else {
            throw WorkspaceRatifiedBaselineContentCaptureError
                .baselineAuthorityMismatch
        }
        guard try recapture(workspace, expected: baseline) == baseline else {
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
        }
        let rootDescriptor = try openAbsoluteDirectory(workspace)
        defer { _ = Darwin.close(rootDescriptor) }
        var rootBefore = stat()
        guard fstat(rootDescriptor, &rootBefore) == 0,
              rootBefore.st_mode & S_IFMT == S_IFDIR else {
            throw Self.systemCallFailure("fstat(baseline-root)")
        }

        let expectedDigests = Set(derivation.operations.compactMap(\.expectedPreimage))
        let referenceByDigest = Dictionary(
            uniqueKeysWithValues: derivation.contentObjects.map {
                ($0.contentDigest, $0)
            }
        )
        let entryByDigest = Dictionary(
            grouping: baseline.entries,
            by: \.contentDigest
        ).mapValues { entries in
            entries.sorted { $0.relativePath < $1.relativePath }[0]
        }
        var objects: [WorkspaceMutationContentObject] = []
        objects.reserveCapacity(expectedDigests.count)
        for digest in expectedDigests.sorted(by: {
            $0.rawValue < $1.rawValue
        }) {
            guard let entry = entryByDigest[digest],
                  referenceByDigest[digest]?.size == entry.size else {
                throw WorkspaceRatifiedBaselineContentCaptureError
                    .missingContent(digest)
            }
            let data = try readStable(
                entry,
                rootDescriptor: rootDescriptor
            )
            guard WorkspaceMutationFilesystemExecutor.contentDigest(data) == digest else {
                throw WorkspaceRatifiedBaselineContentCaptureError
                    .corruptContent(digest)
            }
            objects.append(WorkspaceMutationContentObject(
                digest: digest,
                data: data
            ))
        }
        objects.sort { $0.digest.rawValue < $1.digest.rawValue }

        guard try recapture(workspace, expected: baseline) == baseline else {
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
        }
        var rootAfter = stat()
        guard fstat(rootDescriptor, &rootAfter) == 0,
              rootBefore.st_dev == rootAfter.st_dev,
              rootBefore.st_ino == rootAfter.st_ino,
              rootBefore.st_mode == rootAfter.st_mode,
              rootBefore.st_mtimespec.tv_sec == rootAfter.st_mtimespec.tv_sec,
              rootBefore.st_mtimespec.tv_nsec == rootAfter.st_mtimespec.tv_nsec else {
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
        }

        let references = objects.map {
            WorkspaceMutationContentReference(
                contentDigest: $0.digest,
                size: UInt64($0.data.count)
            )
        }
        let total = references.reduce(UInt64(0)) { $0 + $1.size }
        var receipt = WorkspaceRatifiedBaselineContentCaptureReceipt(
            schemaVersion: 1,
            runID: enrollment.runID,
            contractID: enrollment.contractID,
            ratificationReceiptID: enrollment.ratificationReceiptID,
            enrollmentJournalFrameDigest:
                enrollment.journalTransaction.frameDigest,
            workspaceID: baseline.workspaceID,
            canonicalRootDigest: baseline.canonicalRootDigest,
            captureActor: registration.actorIdentity,
            capturedAt: Date(),
            derivationDigest: derivation.derivationDigest,
            baseSourceRevision: baseline.sourceRevision,
            capturePolicyDigest: baseline.capturePolicyDigest,
            contentObjects: references,
            objectSetDigest: WorkspaceMutationFilesystemExecutor.objectSetDigest(
                objects
            ),
            objectCount: objects.count,
            totalBytes: total,
            rootDeviceID: UInt64(rootBefore.st_dev),
            rootInode: UInt64(rootBefore.st_ino),
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspaceRatifiedBaselineContentCaptureReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceRatifiedBaselineContentCaptureError.encodingFailed
        }
        receipt.receiptDigest = digest
        guard receipt.validationIssues().isEmpty else {
            throw WorkspaceRatifiedBaselineContentCaptureError.encodingFailed
        }
        return AuthorizedWorkspaceRatifiedBaselineContent(
            receipt: receipt,
            objects: objects
        )
    }

    func revalidate(
        _ authority: AuthorizedWorkspaceRatifiedBaselineContent
    ) throws -> WorkspaceRatifiedBaselineContentCaptureReceipt {
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceRatifiedBaselineContentCaptureError.encodingFailed
        }
        return authority.receipt
    }

    private func recapture(
        _ root: URL,
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
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
        }
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
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0,
              UInt64(before.st_size) == entry.size,
              UInt32(before.st_mode & 0o7777) == entry.mode else {
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
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
                throw Self.systemCallFailure("read(baseline-content)")
            }
            data.append(contentsOf: buffer[0..<Int(count)])
            guard UInt64(data.count) <= entry.size else {
                throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
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
            throw WorkspaceRatifiedBaselineContentCaptureError.baselineChanged
        }
        return data
    }

    private func openAbsoluteDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else {
            throw WorkspaceRatifiedBaselineContentCaptureError
                .baselineAuthorityMismatch
        }
        guard let resolvedPointer = realpath(url.path, nil) else {
            throw Self.systemCallFailure("realpath(baseline-root)")
        }
        defer { free(resolvedPointer) }
        let resolvedPath = String(cString: resolvedPointer)
        var descriptor = Darwin.open(
            "/",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw Self.systemCallFailure("open(baseline-root-prefix)")
        }
        for component in resolvedPath.split(separator: "/").map(String.init) {
            guard !component.isEmpty, component != ".", component != ".." else {
                _ = Darwin.close(descriptor)
                throw WorkspaceRatifiedBaselineContentCaptureError
                    .baselineAuthorityMismatch
            }
            let next = component.withCString {
                Darwin.openat(
                    descriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            let failure = errno
            _ = Darwin.close(descriptor)
            guard next >= 0 else {
                throw WorkspaceRatifiedBaselineContentCaptureError
                    .systemCallFailed(
                        operation: "openat(baseline-root-component)",
                        errno: failure
                    )
            }
            descriptor = next
        }
        return descriptor
    }

    private static func systemCallFailure(
        _ operation: String
    ) -> WorkspaceRatifiedBaselineContentCaptureError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
