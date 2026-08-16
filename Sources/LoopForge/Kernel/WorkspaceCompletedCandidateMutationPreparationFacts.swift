import CryptoKit
import Darwin
import Foundation

/// A descriptor-derived observation of one canonical-workspace path named by
/// an inert completed-candidate proposal. This records historical topology;
/// it does not retain a descriptor and cannot authorize a later write.
struct WorkspaceCompletedCandidateMutationPathObservation:
    Codable,
    Hashable,
    Sendable
{
    var sequence: Int
    var path: String
    var exists: Bool
    var deviceID: UInt64?
    var inode: UInt64?
    var mode: UInt32?
    var size: UInt64?
    var contentDigest: ContentDigest?
}

/// Durable preparation facts derived from one exact accepted inert proposal.
/// Rollback rehearsal, verification, independent review, visual acceptance,
/// `MutationManifest`, and `AuthorizedMutationPreflight` are intentionally not
/// members of this type. Consequently replay recovers facts, never authority.
struct WorkspaceCompletedCandidateMutationPreparationFactsReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var strategyFingerprint: StrategyFingerprint
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
    var proposalReceiptDigest: ContentDigest
    var proposalJournalFrameDigest: ContentDigest
    var completedCandidateCaptureReceiptDigest: ContentDigest
    var candidateReleaseReceiptID: ReceiptID
    var candidateReleaseJournalFrameDigest: ContentDigest
    var preparationBinding: MutationPreparationBinding
    var writeAuthority: MutationWriteAuthorityPreparationReceipt
    var mutationBudget: MutationBudgetPreparationReceipt
    var candidateQuiescence: MutationCandidateQuiescencePreparationReceipt
    var pathResolution: MutationPathResolutionPreparationReceipt
    var canonicalRootDeviceID: UInt64
    var canonicalRootInode: UInt64
    var pathObservations: [WorkspaceCompletedCandidateMutationPathObservation]
    var pathObservationDigest: ContentDigest
    var preparedBy: ActorIdentity
    var preparedAt: Date
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 {
            issues.append("unsupported completed-candidate preparation-facts schema")
        }
        if runID.rawValue.isEmpty || contractID.rawValue.isEmpty
            || attemptID.rawValue.isEmpty || nodeID.rawValue.isEmpty
            || strategyFingerprint.rawValue.isEmpty || workspaceID.rawValue.isEmpty
            || candidateReleaseReceiptID.rawValue.isEmpty
            || canonicalRootDeviceID == 0 || canonicalRootInode == 0
            || preparedBy.id.rawValue.isEmpty
            || preparedBy.role.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty || preparedBy.lineageDigest.rawValue.isEmpty {
            issues.append("completed-candidate preparation-facts identity is incomplete")
        }
        for digest in [
            canonicalRootDigest,
            proposalReceiptDigest,
            proposalJournalFrameDigest,
            completedCandidateCaptureReceiptDigest,
            candidateReleaseJournalFrameDigest,
            pathObservationDigest,
            receiptDigest
        ] where !Self.isSHA256(digest) {
            issues.append("completed-candidate preparation-facts digest is invalid")
        }
        let bindings = [
            writeAuthority.binding,
            mutationBudget.binding,
            candidateQuiescence.binding,
            pathResolution.binding
        ]
        if bindings.contains(where: { $0 != preparationBinding }) {
            issues.append("preparation facts are not bound to one proposal identity")
        }
        if writeAuthority.id != Self.factID(
            role: "write-authority",
            proposalReceiptDigest: proposalReceiptDigest
        ) || mutationBudget.id != Self.factID(
            role: "mutation-budget",
            proposalReceiptDigest: proposalReceiptDigest
        ) || candidateQuiescence.id != Self.factID(
            role: "candidate-quiescence",
            proposalReceiptDigest: proposalReceiptDigest
        ) || pathResolution.id != Self.factID(
            role: "path-resolution",
            proposalReceiptDigest: proposalReceiptDigest
        ) {
            issues.append("preparation-fact identities are not content-derived")
        }
        if writeAuthority.authorizedPaths.isEmpty
            || writeAuthority.authorizedRequirementIDs.isEmpty
            || mutationBudget.maximumChangedFiles <= 0
            || candidateQuiescence.candidateScoped == false
            || candidateQuiescence.activeOwnedResourceCount != 0
            || candidateQuiescence.unreleasedLeaseCount != 0
            || candidateQuiescence.externalEffectCount != 0
            || pathResolution.rootIdentity != canonicalRootDigest
            || pathResolution.noSymbolicLinkTraversal == false {
            issues.append("preparation facts do not express least inert authority")
        }
        if pathObservations.isEmpty
            || pathObservations.map(\.sequence) !=
                Array(1...pathObservations.count)
            || Set(pathObservations.map(\.path)).count != pathObservations.count
            || pathObservations.contains(where: { !Self.validObservation($0) }) {
            issues.append("canonical path observations are malformed")
        }
        if pathResolution.operations.count != pathObservations.count
            || pathObservations.contains(where: { observation in
                !pathResolution.operations.contains(where: { binding in
                    binding.sequence == observation.sequence
                        && (binding.sourcePath ?? binding.destinationPath) ==
                            observation.path
                })
            }) {
            issues.append("path-resolution facts do not match observations")
        }
        if Self.pathObservationDigest(
            rootDeviceID: canonicalRootDeviceID,
            rootInode: canonicalRootInode,
            observations: pathObservations
        ) != pathObservationDigest {
            issues.append("canonical path-observation digest mismatch")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("completed-candidate preparation-facts digest mismatch")
        }
        return issues
    }

    static func factID(
        role: String,
        proposalReceiptDigest: ContentDigest
    ) -> ReceiptID {
        ReceiptID("completed-candidate-\(role)-\(proposalReceiptDigest.rawValue)")
    }

    static func pathObservationDigest(
        rootDeviceID: UInt64,
        rootInode: UInt64,
        observations: [WorkspaceCompletedCandidateMutationPathObservation]
    ) -> ContentDigest? {
        canonicalDigest(PathObservationMaterial(
            rootDeviceID: rootDeviceID,
            rootInode: rootInode,
            observations: observations
        ))
    }

    static func digest(
        for receipt: WorkspaceCompletedCandidateMutationPreparationFactsReceipt
    ) -> ContentDigest? {
        var material = receipt
        material.receiptDigest = ContentDigest("")
        return canonicalDigest(material)
    }

    private static func validObservation(
        _ observation: WorkspaceCompletedCandidateMutationPathObservation
    ) -> Bool {
        guard observation.sequence > 0,
              WorkspaceSourceRevisionCollector.validRelativePath(
                observation.path
              ) else { return false }
        if observation.exists {
            return observation.deviceID.map { $0 > 0 } == true
                && observation.inode.map { $0 > 0 } == true
                && observation.mode != nil
                && observation.size != nil
                && observation.contentDigest.map(isSHA256) == true
        }
        return observation.deviceID == nil && observation.inode == nil
            && observation.mode == nil && observation.size == nil
            && observation.contentDigest == nil
    }

    private static func canonicalDigest<T: Encodable>(
        _ value: T
    ) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else { return nil }
        return ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private struct PathObservationMaterial: Codable {
        var rootDeviceID: UInt64
        var rootInode: UInt64
        var observations: [WorkspaceCompletedCandidateMutationPathObservation]
    }
}

/// Non-serializable composition proof retaining the exact live proposal.
struct AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts:
    Sendable
{
    let receipt: WorkspaceCompletedCandidateMutationPreparationFactsReceipt
    let proposal:
        AuthorizedWorkspaceCompletedCandidateMutationManifestProposal

    fileprivate init(
        receipt: WorkspaceCompletedCandidateMutationPreparationFactsReceipt,
        proposal:
            AuthorizedWorkspaceCompletedCandidateMutationManifestProposal
    ) {
        self.receipt = receipt
        self.proposal = proposal
    }

    func journalValidationIssues() -> [String] {
        var issues = receipt.validationIssues()
        issues.append(contentsOf: proposal.journalValidationIssues())
        let proposed = proposal.receipt
        let capture = proposal.contentStore.completedCandidate.receipt
        if receipt.runID != proposed.runID
            || receipt.contractID != proposed.contractID
            || receipt.attemptID != proposed.attemptID
            || receipt.nodeID != proposed.nodeID
            || receipt.strategyFingerprint != proposed.strategyFingerprint
            || receipt.workspaceID != proposed.workspaceID
            || receipt.canonicalRootDigest != proposed.canonicalRootDigest
            || receipt.proposalReceiptDigest != proposed.receiptDigest
            || receipt.completedCandidateCaptureReceiptDigest !=
                capture.receiptDigest
            || receipt.candidateReleaseReceiptID != capture.releaseReceiptID
            || receipt.candidateReleaseJournalFrameDigest !=
                capture.releaseJournalFrameDigest
            || receipt.preparationBinding != proposed.preparationBinding
            || receipt.preparedBy != proposed.proposedBy
            || receipt.preparedAt < proposed.proposedAt {
            issues.append("completed-candidate preparation-facts composition is inconsistent")
        }
        return issues
    }

    func externalArtifactValidationIssues() -> [String] {
        proposal.externalArtifactValidationIssues()
    }

    func validationIssues() -> [String] {
        journalValidationIssues() + externalArtifactValidationIssues()
    }
}

struct WorkspaceCompletedCandidateMutationPreparationFactsInstallation:
    Sendable
{
    let authority:
        AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts
    let journalTransaction: JournalTransactionReceipt
}

enum WorkspaceCompletedCandidateMutationPreparationFactsError:
    Error,
    Equatable,
    Sendable
{
    case invalidProposalAuthority
    case originNotAccepted
    case candidateNotQuiescent
    case canonicalWorkspaceMismatch
    case unsafePath(String)
    case canonicalPathChanged(String)
    case encodingFailed
    case systemCallFailed(operation: String, errno: Int32)
}

/// Mints and journals only write-scope, exact-budget, candidate-quiescence,
/// and descriptor-observed path facts. It deliberately cannot build rollback
/// facts, an executable manifest, a preflight capability, or an effect.
actor WorkspaceCompletedCandidateMutationPreparationFactsCoordinator {
    private let journal: RunJournal
    private let wallClock: @Sendable () -> Date

    init(
        journal: RunJournal,
        wallClock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.wallClock = wallClock
    }

    func prepare(
        proposal:
            WorkspaceCompletedCandidateMutationManifestProposalInstallation,
        canonicalWorkspaceRoot: URL,
        commandID: RunCommandID,
        durability: JournalDurability = .boundary
    ) async throws
        -> WorkspaceCompletedCandidateMutationPreparationFactsInstallation {
        guard proposal.authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .invalidProposalAuthority
        }
        guard await journal.completedCandidateMutationManifestProposalReceipt(
            transaction: proposal.journalTransaction
        ) == proposal.authority.receipt else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .originNotAccepted
        }
        let state = await journal.state
        let proposed = proposal.authority.receipt
        let capture = proposal.authority.contentStore.completedCandidate.receipt
        guard state.phase == .evaluating,
              state.runtimeLiveLeases.isEmpty,
              state.runtimeFailedReleases.isEmpty,
              state.integrationTransactions.isEmpty,
              let release = state.runtimeReleaseReceipts[
                capture.releaseReceiptID
              ], release.runID == proposed.runID,
              release.resourceID.rawValue.isEmpty == false,
              release.leaseID.rawValue.isEmpty == false,
              case .released = release.outcome,
              await journal.runtimeReleaseFrameDigest(
                receiptID: capture.releaseReceiptID
              ) == capture.releaseJournalFrameDigest else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .candidateNotQuiescent
        }

        let observation = try Self.observe(
            proposal: proposed,
            canonicalWorkspaceRoot: canonicalWorkspaceRoot
        )
        if let retained = await journal
            .completedCandidateMutationPreparationFactsReceipt(
                proposalReceiptDigest: proposed.receiptDigest
            ) {
            guard retained.canonicalRootDeviceID == observation.deviceID,
                  retained.canonicalRootInode == observation.inode,
                  retained.pathObservations == observation.paths,
                  retained.pathObservationDigest == observation.digest else {
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .canonicalWorkspaceMismatch
            }
            let authority =
                AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts(
                    receipt: retained,
                    proposal: proposal.authority
                )
            guard authority.validationIssues().isEmpty else {
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .originNotAccepted
            }
            let transaction = try await journal
                .recordCompletedCandidateMutationPreparationFacts(
                    authority,
                    commandID: commandID,
                    durability: durability
                )
            return WorkspaceCompletedCandidateMutationPreparationFactsInstallation(
                authority: authority,
                journalTransaction: transaction
            )
        }
        let paths = Set(proposed.operations.compactMap {
            $0.sourcePath ?? $0.destinationPath
        })
        let binding = proposed.preparationBinding
        let pathBindings = Set(proposed.operations.map {
            MutationPathResolutionBinding(
                sequence: $0.sequence,
                sourcePath: $0.sourcePath,
                destinationPath: $0.destinationPath
            )
        })
        var receipt =
            WorkspaceCompletedCandidateMutationPreparationFactsReceipt(
                schemaVersion: 1,
                runID: proposed.runID,
                contractID: proposed.contractID,
                attemptID: proposed.attemptID,
                nodeID: proposed.nodeID,
                strategyFingerprint: proposed.strategyFingerprint,
                workspaceID: proposed.workspaceID,
                canonicalRootDigest: proposed.canonicalRootDigest,
                proposalReceiptDigest: proposed.receiptDigest,
                proposalJournalFrameDigest:
                    proposal.journalTransaction.frameDigest,
                completedCandidateCaptureReceiptDigest: capture.receiptDigest,
                candidateReleaseReceiptID: capture.releaseReceiptID,
                candidateReleaseJournalFrameDigest:
                    capture.releaseJournalFrameDigest,
                preparationBinding: binding,
                writeAuthority: MutationWriteAuthorityPreparationReceipt(
                    id: Self.factID(
                        role: "write-authority",
                        proposal: proposed
                    ),
                    binding: binding,
                    authorizedPaths: paths,
                    authorizedRequirementIDs:
                        proposed.touchedRequirementIDs
                ),
                mutationBudget: MutationBudgetPreparationReceipt(
                    id: Self.factID(
                        role: "mutation-budget",
                        proposal: proposed
                    ),
                    binding: binding,
                    maximumChangedFiles: proposed.changedFileCount,
                    maximumChangedBytes: proposed.changedByteCount
                ),
                candidateQuiescence:
                    MutationCandidateQuiescencePreparationReceipt(
                        id: Self.factID(
                            role: "candidate-quiescence",
                            proposal: proposed
                        ),
                        binding: binding,
                        candidateScoped: true,
                        activeOwnedResourceCount: 0,
                        unreleasedLeaseCount: 0,
                        externalEffectCount: 0
                    ),
                pathResolution: MutationPathResolutionPreparationReceipt(
                    id: Self.factID(
                        role: "path-resolution",
                        proposal: proposed
                    ),
                    binding: binding,
                    rootIdentity: proposed.canonicalRootDigest,
                    operations: pathBindings,
                    noSymbolicLinkTraversal: true
                ),
                canonicalRootDeviceID: observation.deviceID,
                canonicalRootInode: observation.inode,
                pathObservations: observation.paths,
                pathObservationDigest: observation.digest,
                preparedBy: proposed.proposedBy,
                preparedAt: wallClock(),
                receiptDigest: ContentDigest("")
            )
        guard let digest =
                WorkspaceCompletedCandidateMutationPreparationFactsReceipt
                    .digest(for: receipt) else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .encodingFailed
        }
        receipt.receiptDigest = digest
        let authority =
            AuthorizedWorkspaceCompletedCandidateMutationPreparationFacts(
                receipt: receipt,
                proposal: proposal.authority
            )
        guard authority.validationIssues().isEmpty else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .encodingFailed
        }
        let transaction = try await journal
            .recordCompletedCandidateMutationPreparationFacts(
                authority,
                commandID: commandID,
                durability: durability
            )
        return WorkspaceCompletedCandidateMutationPreparationFactsInstallation(
            authority: authority,
            journalTransaction: transaction
        )
    }

    private static func factID(
        role: String,
        proposal:
            WorkspaceCompletedCandidateMutationManifestProposalReceipt
    ) -> ReceiptID {
        WorkspaceCompletedCandidateMutationPreparationFactsReceipt.factID(
            role: role,
            proposalReceiptDigest: proposal.receiptDigest
        )
    }

    /// Re-observes the exact canonical root and affected paths without minting
    /// a receipt. Later inert preparation boundaries use this both before and
    /// after owner-private work to prove the canonical preimage stayed fixed.
    nonisolated static func revalidateCanonicalWorkspace(
        preparation:
            WorkspaceCompletedCandidateMutationPreparationFactsReceipt,
        proposal:
            WorkspaceCompletedCandidateMutationManifestProposalReceipt,
        canonicalWorkspaceRoot: URL
    ) throws {
        let observation = try observe(
            proposal: proposal,
            canonicalWorkspaceRoot: canonicalWorkspaceRoot
        )
        guard preparation.canonicalRootDeviceID == observation.deviceID,
              preparation.canonicalRootInode == observation.inode,
              preparation.pathObservations == observation.paths,
              preparation.pathObservationDigest == observation.digest else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalWorkspaceMismatch
        }
    }

    private static func observe(
        proposal:
            WorkspaceCompletedCandidateMutationManifestProposalReceipt,
        canonicalWorkspaceRoot: URL
    ) throws -> (
        deviceID: UInt64,
        inode: UInt64,
        paths: [WorkspaceCompletedCandidateMutationPathObservation],
        digest: ContentDigest
    ) {
        let standardized = canonicalWorkspaceRoot.standardizedFileURL
        guard standardized.isFileURL, standardized.path.hasPrefix("/"),
              let resolvedPointer = standardized.path.withCString({
                Darwin.realpath($0, nil)
              }) else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalWorkspaceMismatch
        }
        defer { Darwin.free(resolvedPointer) }
        let resolved = URL(
            fileURLWithPath: String(cString: resolvedPointer),
            isDirectory: true
        )
        guard
              WorkspaceRepositoryIndexer.canonicalRootDigest(resolved) ==
                proposal.canonicalRootDigest else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalWorkspaceMismatch
        }
        let rootDescriptor = try openAbsoluteDirectory(resolved)
        defer { _ = Darwin.close(rootDescriptor) }
        var before = stat()
        guard Darwin.fstat(rootDescriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFDIR else {
            throw systemCallFailure("fstat(preparation-root)")
        }
        var observations: [WorkspaceCompletedCandidateMutationPathObservation]
            = []
        observations.reserveCapacity(proposal.operations.count)
        for operation in proposal.operations {
            guard let path = operation.sourcePath ?? operation.destinationPath,
                  WorkspaceSourceRevisionCollector.validRelativePath(path)
            else {
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .unsafePath(operation.sourcePath ?? operation.destinationPath ?? "")
            }
            observations.append(try observe(
                operation: operation,
                path: path,
                rootDescriptor: rootDescriptor
            ))
        }
        var after = stat()
        guard Darwin.fstat(rootDescriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalWorkspaceMismatch
        }
        let deviceID = UInt64(bitPattern: Int64(before.st_dev))
        let inode = UInt64(before.st_ino)
        guard let digest =
                WorkspaceCompletedCandidateMutationPreparationFactsReceipt
                    .pathObservationDigest(
                        rootDeviceID: deviceID,
                        rootInode: inode,
                        observations: observations
                    ) else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .encodingFailed
        }
        return (deviceID, inode, observations, digest)
    }

    private static func observe(
        operation: WorkspaceCompletedCandidateMutationOperationProposal,
        path: String,
        rootDescriptor: Int32
    ) throws -> WorkspaceCompletedCandidateMutationPathObservation {
        if operation.kind == .create {
            let parent = try openParent(path, rootDescriptor: rootDescriptor)
            defer { _ = Darwin.close(parent.descriptor) }
            var status = stat()
            let result = parent.name.withCString {
                Darwin.fstatat(
                    parent.descriptor,
                    $0,
                    &status,
                    AT_SYMLINK_NOFOLLOW
                )
            }
            guard result != 0, errno == ENOENT else {
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .canonicalPathChanged(path)
            }
            return WorkspaceCompletedCandidateMutationPathObservation(
                sequence: operation.sequence,
                path: path,
                exists: false,
                deviceID: nil,
                inode: nil,
                mode: nil,
                size: nil,
                contentDigest: nil
            )
        }
        let descriptor: Int32
        do {
            descriptor = try WorkspaceSourceRevisionCollector.openRegularFile(
                path,
                rootDescriptor: rootDescriptor
            )
        } catch {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalPathChanged(path)
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0 else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalPathChanged(path)
        }
        var hasher = SHA256()
        var observed: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw systemCallFailure("read(preparation-path)")
            }
            let (nextObserved, overflow) = observed.addingReportingOverflow(
                UInt64(count)
            )
            guard !overflow else {
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .canonicalPathChanged(path)
            }
            observed = nextObserved
            hasher.update(data: Data(buffer.prefix(count)))
        }
        var after = stat()
        let digest = ContentDigest(KernelHex.encode(hasher.finalize()))
        guard Darwin.fstat(descriptor, &after) == 0,
              observed == UInt64(before.st_size),
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_mode == after.st_mode,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              digest == operation.expectedPreimage,
              UInt32(before.st_mode & 0o7777) == operation.modeBefore else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .canonicalPathChanged(path)
        }
        return WorkspaceCompletedCandidateMutationPathObservation(
            sequence: operation.sequence,
            path: path,
            exists: true,
            deviceID: UInt64(bitPattern: Int64(before.st_dev)),
            inode: UInt64(before.st_ino),
            mode: UInt32(before.st_mode & 0o7777),
            size: observed,
            contentDigest: digest
        )
    }

    private static func openParent(
        _ path: String,
        rootDescriptor: Int32
    ) throws -> (descriptor: Int32, name: String) {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(
                WorkspaceSourceRevisionCollector.validPathComponent
              ) else {
            throw WorkspaceCompletedCandidateMutationPreparationFactsError
                .unsafePath(path)
        }
        var descriptor = Darwin.dup(rootDescriptor)
        guard descriptor >= 0 else {
            throw systemCallFailure("dup(preparation-root)")
        }
        for component in components.dropLast() {
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
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .systemCallFailed(
                        operation: "openat(preparation-parent)",
                        errno: failure
                    )
            }
            descriptor = next
        }
        return (descriptor, components.last!)
    }

    private static func openAbsoluteDirectory(_ url: URL) throws -> Int32 {
        var descriptor = Darwin.open(
            "/",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw systemCallFailure("open(preparation-root-prefix)")
        }
        for component in url.path.split(separator: "/").map(String.init) {
            guard WorkspaceSourceRevisionCollector.validPathComponent(
                component
            ) else {
                _ = Darwin.close(descriptor)
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .canonicalWorkspaceMismatch
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
                throw WorkspaceCompletedCandidateMutationPreparationFactsError
                    .systemCallFailed(
                        operation: "openat(preparation-root-component)",
                        errno: failure
                    )
            }
            descriptor = next
        }
        return descriptor
    }

    private static func systemCallFailure(
        _ operation: String
    ) -> WorkspaceCompletedCandidateMutationPreparationFactsError {
        .systemCallFailed(operation: operation, errno: errno)
    }
}
