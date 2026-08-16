import CryptoKit
import Darwin
import Foundation

struct WorkspaceMutationContentObject: Codable, Hashable, Sendable {
    var digest: ContentDigest
    var data: Data
}

struct WorkspaceMutationExecutionLease: Codable, Hashable, Sendable {
    var receiptID: ReceiptID
    var transactionID: IntegrationTransactionID
    var workspaceID: WorkspaceID
    var rootIdentity: ContentDigest
    var exclusive: Bool
    var remoteAccessDisabled: Bool
    var issuedAt: Date
    var expiresAt: Date
}

struct WorkspaceMutationExecutorLimits: Codable, Hashable, Sendable {
    var maximumSnapshotFiles: Int
    var maximumSnapshotBytes: UInt64
    var maximumRecoveryBytes: UInt64

    static let conservative = WorkspaceMutationExecutorLimits(
        maximumSnapshotFiles: 200_000,
        maximumSnapshotBytes: 4 * 1_024 * 1_024 * 1_024,
        maximumRecoveryBytes: 512 * 1_024 * 1_024
    )
}

struct WorkspaceMutationExecutionRequest: Codable, Hashable, Sendable {
    var workspaceRoot: URL
    var recoveryRoot: URL
    var workspaceID: WorkspaceID
    var preimage: WorkspacePreimage
    var manifest: MutationManifest
    var rollbackManifest: RollbackManifest
    var preflightReceipt: MutationPreflightReceipt
    var intent: IntegrationApplyIntent
    var lease: WorkspaceMutationExecutionLease
    var contentObjects: [WorkspaceMutationContentObject]
    var executor: ActorIdentity
    var completedAt: Date
    var limits: WorkspaceMutationExecutorLimits
    /// Optional only for replaying pre-attestation requests. Contract-backed
    /// requests must carry the exact policy whose digest is sealed in `intent`.
    var candidatePostimageCapturePolicy:
        WorkspaceCandidatePostimageCapturePolicy? = nil
}

struct WorkspaceMutationRollbackRequest: Codable, Hashable, Sendable {
    var workspaceRoot: URL
    var recoveryRoot: URL
    var workspaceID: WorkspaceID
    var preimage: WorkspacePreimage
    var manifest: MutationManifest
    var rollbackManifest: RollbackManifest
    var preflightReceipt: MutationPreflightReceipt
    var applyReceipt: IntegrationApplyReceipt
    var intent: IntegrationRollbackIntent
    var lease: WorkspaceMutationExecutionLease
    var executor: ActorIdentity
    var completedAt: Date
    var limits: WorkspaceMutationExecutorLimits
}

enum WorkspaceMutationExecutionError: Error, Codable, Hashable, Sendable {
    case invalidBinding(String)
    case invalidLease(String)
    case unsafeRoot(String)
    case recoveryRootInsideWorkspace
    case lockUnavailable
    case unsupportedEntryKind(path: String, kind: WorkspaceEntryKind)
    case missingContentObject(ContentDigest)
    case corruptContentObject(ContentDigest)
    case compareAndSwapConflict(path: String)
    case pathEscapesWorkspace(String)
    case symbolicLinkInParent(String)
    case snapshotBudgetExceeded
    case recoveryBudgetExceeded
    case recoveryArtifactMissing
    case recoveryArtifactCorrupt
    case unrelatedWorkspaceDrift
    case filesystemFailure(String)
}

/// Executes an already-admitted mutation against one explicitly bound workspace.
///
/// The executor cannot grant authority. It rechecks the pure-kernel manifest,
/// preflight, lease, content objects, root identity, path topology, and CAS values;
/// writes a durable recovery artifact before the first workspace effect; serializes
/// cooperating writers with a cross-process lock; and produces effect receipts that
/// still require journal acceptance, independent verification, and review.
struct WorkspaceMutationFilesystemExecutor: Sendable {
    func apply(
        _ request: WorkspaceMutationExecutionRequest
    ) throws -> IntegrationApplyReceipt {
        let root = try validatedRoot(
            request.workspaceRoot,
            workspaceID: request.workspaceID,
            expectedIdentity: request.lease.rootIdentity
        )
        let recoveryRoot = try validatedRecoveryRoot(request.recoveryRoot, outside: root)
        try validateApplyBindings(request)
        let objects = try validatedObjects(
            request.contentObjects,
            expectedSetDigest: request.intent.stagedObjectSetDigest
        )

        return try withExclusiveLock(
            recoveryRoot: recoveryRoot,
            workspaceID: request.workspaceID,
            limits: request.limits
        ) {
            try validateLease(
                request.lease,
                receiptID: request.intent.exclusiveLeaseReceiptID,
                transactionID: request.manifest.transactionID,
                workspaceID: request.workspaceID,
                rootIdentity: try Self.rootIdentity(root),
                at: request.completedAt
            )
            let affectedPaths = request.preflightReceipt.affectedPaths
            let artifactURL = recoveryArtifactURL(
                root: recoveryRoot,
                transactionID: request.manifest.transactionID,
                intentID: request.intent.id
            )
            let operations = request.manifest.operations.sorted { $0.sequence < $1.sequence }
            var artifact: RecoveryArtifact
            var appliedCount: Int
            if FileManager.default.fileExists(atPath: artifactURL.path) {
                artifact = try loadArtifact(
                    at: artifactURL,
                    maximumBytes: request.limits.maximumRecoveryBytes
                )
                try validateRecoveryArtifact(
                    artifact,
                    request: request,
                    operations: operations
                )
                if artifact.status == .applyFailed {
                    let recoveryDigest = try Self.fileDigest(artifactURL)
                    return failedApplyReceipt(
                        request: request,
                        observed: artifact.lastObservedAffectedDigest,
                        recoveryDigest: recoveryDigest,
                        appliedCount: artifact.appliedOperationSequences.count,
                        reason: artifact.failureReasonDigest ?? Self.errorDigest(
                            WorkspaceMutationExecutionError.recoveryArtifactCorrupt
                        ),
                        completedAt: artifact.updatedAt
                    )
                }
                if artifact.status == .restored {
                    throw WorkspaceMutationExecutionError.invalidBinding(
                        "apply intent has already been rolled back"
                    )
                }
                let current = try Self.captureAffected(paths: affectedPaths, root: root)
                let unaffectedCurrent = try unaffectedDigest(
                    root: root,
                    excluding: Set(affectedPaths),
                    limits: request.limits
                )
                guard current == artifact.ownedPostimageEntries,
                      Self.affectedStateDigest(current) ==
                        artifact.lastObservedAffectedDigest,
                      unaffectedCurrent == artifact.unaffectedBeforeDigest else {
                    return try recoveredApplyFailureReceipt(
                        request: request,
                        artifact: &artifact,
                        artifactURL: artifactURL,
                        observedEntries: current,
                        reason: WorkspaceMutationExecutionError.compareAndSwapConflict(
                            path: "recovery-checkpoint"
                        )
                    )
                }
                switch artifact.status {
                case .applied:
                    guard artifact.appliedOperationSequences.count == operations.count,
                          let observedAffected =
                            artifact.lastObservedAffectedDigest else {
                        throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
                    }
                    let candidatePostimage = try captureCandidatePostimage(
                        request: request,
                        root: root
                    )
                    let observedPostimage = try resolvedPostimageDigest(
                        affectedStateDigest: observedAffected,
                        candidatePostimage: candidatePostimage,
                        expectedPostimageDigest:
                            request.manifest.expectedPostimageDigest
                    )
                    let recoveryDigest = try Self.fileDigest(artifactURL)
                    return exactApplyReceipt(
                        request: request,
                        observed: observedPostimage,
                        unaffectedBefore: artifact.unaffectedBeforeDigest,
                        unaffectedAfter: unaffectedCurrent,
                        recoveryDigest: recoveryDigest,
                        appliedCount: operations.count,
                        completedAt: artifact.updatedAt,
                        candidatePostimage: candidatePostimage
                    )
                case .applyFailed, .restored:
                    preconditionFailure("terminal recovery states returned above")
                case .prepared, .applying:
                    appliedCount = artifact.appliedOperationSequences.count
                }
            } else {
                try validateOperationsAtExecution(
                    request.manifest.operations,
                    root: root,
                    objects: objects
                )
                let baseline = try Self.captureAffected(paths: affectedPaths, root: root)
                let unaffectedBefore = try unaffectedDigest(
                    root: root,
                    excluding: Set(affectedPaths),
                    limits: request.limits
                )
                artifact = RecoveryArtifact(
                    schemaVersion: 2,
                    workspaceID: request.workspaceID,
                    rootIdentity: request.lease.rootIdentity,
                    transactionID: request.manifest.transactionID,
                    applyIntentID: request.intent.id,
                    manifestDigest: request.preflightReceipt.manifestDigest,
                    rollbackManifestDigest: request.preflightReceipt.rollbackManifestDigest,
                    baselineAffectedDigest: Self.affectedStateDigest(baseline),
                    unaffectedBeforeDigest: unaffectedBefore,
                    baselineEntries: baseline,
                    ownedPostimageEntries: baseline,
                    appliedOperationSequences: [],
                    lastObservedAffectedDigest: Self.affectedStateDigest(baseline),
                    failureReasonDigest: nil,
                    status: .prepared,
                    createdAt: request.intent.requestedAt,
                    updatedAt: request.intent.requestedAt
                )
                try persist(
                    artifact,
                    to: artifactURL,
                    maximumBytes: request.limits.maximumRecoveryBytes
                )
                appliedCount = 0
            }

            do {
                for operation in operations.dropFirst(appliedCount) {
                    try validateOperationAtExecution(operation, root: root, objects: objects)
                    try execute(operation, root: root, objects: objects)
                    try validateOperationPostimage(operation, root: root, objects: objects)
                    appliedCount += 1
                    artifact.appliedOperationSequences.append(operation.sequence)
                    let observedEntries = try Self.captureAffected(
                        paths: affectedPaths,
                        root: root
                    )
                    artifact.ownedPostimageEntries = observedEntries
                    artifact.lastObservedAffectedDigest =
                        Self.affectedStateDigest(observedEntries)
                    artifact.status = .applying
                    artifact.updatedAt = request.completedAt
                    try persist(
                        artifact,
                        to: artifactURL,
                        maximumBytes: request.limits.maximumRecoveryBytes
                    )
                }

                let observedAffected = try Self.affectedStateDigest(
                    Self.captureAffected(paths: affectedPaths, root: root)
                )
                let unaffectedAfter = try unaffectedDigest(
                    root: root,
                    excluding: Set(affectedPaths),
                    limits: request.limits
                )
                guard unaffectedAfter == artifact.unaffectedBeforeDigest else {
                    throw WorkspaceMutationExecutionError.unrelatedWorkspaceDrift
                }
                artifact.lastObservedAffectedDigest = observedAffected
                artifact.ownedPostimageEntries = try Self.captureAffected(
                    paths: affectedPaths,
                    root: root
                )
                artifact.status = .applied
                artifact.updatedAt = request.completedAt
                try persist(
                    artifact,
                    to: artifactURL,
                    maximumBytes: request.limits.maximumRecoveryBytes
                )
                let candidatePostimage = try captureCandidatePostimage(
                    request: request,
                    root: root
                )
                let observedPostimage = try resolvedPostimageDigest(
                    affectedStateDigest: observedAffected,
                    candidatePostimage: candidatePostimage,
                    expectedPostimageDigest:
                        request.manifest.expectedPostimageDigest
                )
                let recoveryDigest = try Self.fileDigest(artifactURL)
                return exactApplyReceipt(
                    request: request,
                    observed: observedPostimage,
                    unaffectedBefore: artifact.unaffectedBeforeDigest,
                    unaffectedAfter: unaffectedAfter,
                    recoveryDigest: recoveryDigest,
                    appliedCount: appliedCount,
                    completedAt: request.completedAt,
                    candidatePostimage: candidatePostimage
                )
            } catch {
                let reason = Self.errorDigest(error)
                let observed = try? Self.affectedStateDigest(
                    Self.captureAffected(paths: affectedPaths, root: root)
                )
                artifact.lastObservedAffectedDigest = observed
                artifact.failureReasonDigest = reason
                artifact.status = .applyFailed
                artifact.updatedAt = request.completedAt
                try persist(
                    artifact,
                    to: artifactURL,
                    maximumBytes: request.limits.maximumRecoveryBytes
                )
                let recoveryDigest = try Self.fileDigest(artifactURL)
                return failedApplyReceipt(
                    request: request,
                    observed: observed,
                    recoveryDigest: recoveryDigest,
                    appliedCount: appliedCount,
                    reason: reason,
                    completedAt: request.completedAt
                )
            }
        }
    }

    func rollback(
        _ request: WorkspaceMutationRollbackRequest
    ) throws -> IntegrationRollbackReceipt {
        let root = try validatedRoot(
            request.workspaceRoot,
            workspaceID: request.workspaceID,
            expectedIdentity: request.lease.rootIdentity
        )
        let recoveryRoot = try validatedRecoveryRoot(request.recoveryRoot, outside: root)
        try validateRollbackBindings(request)

        return try withExclusiveLock(
            recoveryRoot: recoveryRoot,
            workspaceID: request.workspaceID,
            limits: request.limits
        ) {
            try validateLease(
                request.lease,
                receiptID: request.intent.exclusiveLeaseReceiptID,
                transactionID: request.manifest.transactionID,
                workspaceID: request.workspaceID,
                rootIdentity: try Self.rootIdentity(root),
                at: request.completedAt
            )
            let artifactURL = recoveryArtifactURL(
                root: recoveryRoot,
                transactionID: request.manifest.transactionID,
                intentID: request.applyReceipt.intentID
            )
            let artifact = try loadArtifact(
                at: artifactURL,
                maximumBytes: request.limits.maximumRecoveryBytes
            )
            guard try Self.fileDigest(artifactURL) == request.intent.recoveryArtifactDigest,
                  request.intent.recoveryArtifactDigest ==
                    request.applyReceipt.recoveryArtifactDigest,
                  artifact.workspaceID == request.workspaceID,
                  artifact.rootIdentity == request.lease.rootIdentity,
                  artifact.transactionID == request.manifest.transactionID,
                  artifact.applyIntentID == request.applyReceipt.intentID,
                  artifact.manifestDigest == request.preflightReceipt.manifestDigest,
                  artifact.rollbackManifestDigest ==
                    request.preflightReceipt.rollbackManifestDigest else {
                throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
            }

            let affectedPaths = request.preflightReceipt.affectedPaths
            let rollbackArtifactURL = rollbackRecoveryArtifactURL(
                root: recoveryRoot,
                transactionID: request.manifest.transactionID,
                intentID: request.intent.id
            )
            if FileManager.default.fileExists(atPath: rollbackArtifactURL.path) {
                let rollbackArtifact = try loadRollbackArtifact(
                    at: rollbackArtifactURL,
                    maximumBytes: request.limits.maximumRecoveryBytes
                )
                guard rollbackArtifact.workspaceID == request.workspaceID,
                      rollbackArtifact.rootIdentity == request.lease.rootIdentity,
                      rollbackArtifact.transactionID == request.manifest.transactionID,
                      rollbackArtifact.rollbackIntentID == request.intent.id,
                      rollbackArtifact.applyRecoveryArtifactDigest ==
                        request.intent.recoveryArtifactDigest else {
                    throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
                }
                let current = try Self.captureAffected(paths: affectedPaths, root: root)
                let unaffectedCurrent = try unaffectedDigest(
                    root: root,
                    excluding: Set(affectedPaths),
                    limits: request.limits
                )
                guard current == rollbackArtifact.restoredEntries,
                      Self.affectedStateDigest(current) ==
                        artifact.baselineAffectedDigest,
                      unaffectedCurrent == rollbackArtifact.unaffectedDigest else {
                    return quarantinedRollbackReceipt(
                        request: request,
                        reason: WorkspaceMutationExecutionError.compareAndSwapConflict(
                            path: "rollback-recovery-checkpoint"
                        ),
                        recoveryDigest: request.intent.recoveryArtifactDigest
                    )
                }
                return restoredRollbackReceipt(
                    request: request,
                    recoveryDigest: request.intent.recoveryArtifactDigest,
                    receiptIdentityDigest: try Self.fileDigest(rollbackArtifactURL),
                    unaffectedAfter: unaffectedCurrent,
                    completedAt: rollbackArtifact.completedAt
                )
            }
            let current = try Self.captureAffected(paths: affectedPaths, root: root)
            let currentDigest = Self.affectedStateDigest(current)
            let unaffectedCurrent = try unaffectedDigest(
                root: root,
                excluding: Set(affectedPaths),
                limits: request.limits
            )
            if let expected = request.intent.expectedCurrentWorkspaceDigest {
                let observedCurrentDigest: ContentDigest
                if let candidatePostimage = request.applyReceipt.candidatePostimage {
                    let observedSourceRevision = try WorkspaceSourceRevisionCollector()
                        .capture(
                            workspaceID: request.workspaceID,
                            root: root,
                            excludedDirectoryNames:
                                Set(candidatePostimage.excludedDirectoryNames),
                            limits: candidatePostimage.limits
                        )
                    guard observedSourceRevision.validationIssues().isEmpty,
                          observedSourceRevision.capturePolicyDigest ==
                            candidatePostimage.capturePolicyDigest else {
                        throw WorkspaceMutationExecutionError.invalidBinding(
                            "rollback-postimage-policy"
                        )
                    }
                    observedCurrentDigest =
                        observedSourceRevision.sourceRevision
                } else {
                    observedCurrentDigest = currentDigest
                }
                if observedCurrentDigest != expected {
                    return quarantinedRollbackReceipt(
                        request: request,
                        reason: WorkspaceMutationExecutionError
                            .compareAndSwapConflict(
                                path: "affected-workspace"
                            ),
                        recoveryDigest: request.intent.recoveryArtifactDigest
                    )
                }
            }
            guard currentEntriesAreTransactionOwned(
                current,
                baseline: artifact.baselineEntries,
                ownedPostimage: artifact.ownedPostimageEntries
            ) else {
                return quarantinedRollbackReceipt(
                    request: request,
                    reason: WorkspaceMutationExecutionError.compareAndSwapConflict(
                        path: "affected-workspace"
                    ),
                    recoveryDigest: request.intent.recoveryArtifactDigest
                )
            }

            guard unaffectedCurrent == artifact.unaffectedBeforeDigest else {
                return quarantinedRollbackReceipt(
                    request: request,
                    reason: WorkspaceMutationExecutionError.unrelatedWorkspaceDrift,
                    recoveryDigest: request.intent.recoveryArtifactDigest
                )
            }

            do {
                try restore(entries: artifact.baselineEntries, root: root)
                let restored = try Self.captureAffected(paths: affectedPaths, root: root)
                guard Self.affectedStateDigest(restored) == artifact.baselineAffectedDigest else {
                    throw WorkspaceMutationExecutionError.filesystemFailure(
                        "restored workspace does not match recovery baseline"
                    )
                }
                let unaffectedAfter = try unaffectedDigest(
                    root: root,
                    excluding: Set(affectedPaths),
                    limits: request.limits
                )
                guard unaffectedAfter == artifact.unaffectedBeforeDigest else {
                    throw WorkspaceMutationExecutionError.unrelatedWorkspaceDrift
                }
                let rollbackArtifact = RollbackRecoveryArtifact(
                    schemaVersion: 1,
                    workspaceID: request.workspaceID,
                    rootIdentity: request.lease.rootIdentity,
                    transactionID: request.manifest.transactionID,
                    rollbackIntentID: request.intent.id,
                    applyRecoveryArtifactDigest: request.intent.recoveryArtifactDigest,
                    restoredEntries: restored,
                    unaffectedDigest: unaffectedAfter,
                    completedAt: request.completedAt
                )
                try persist(
                    rollbackArtifact,
                    to: rollbackArtifactURL,
                    maximumBytes: request.limits.maximumRecoveryBytes
                )
                return restoredRollbackReceipt(
                    request: request,
                    recoveryDigest: request.intent.recoveryArtifactDigest,
                    receiptIdentityDigest: try Self.fileDigest(rollbackArtifactURL),
                    unaffectedAfter: unaffectedAfter,
                    completedAt: request.completedAt
                )
            } catch {
                return quarantinedRollbackReceipt(
                    request: request,
                    reason: error,
                    recoveryDigest: request.intent.recoveryArtifactDigest
                )
            }
        }
    }

    static func rootIdentity(_ root: URL) throws -> ContentDigest {
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        var info = stat()
        guard lstat(resolved.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw WorkspaceMutationExecutionError.unsafeRoot(root.path)
        }
        return digest(Data(
            "root-v1\u{0}\(resolved.path)\u{0}\(info.st_dev)\u{0}\(info.st_ino)"
                .utf8
        ))
    }

    static func contentDigest(_ data: Data) -> ContentDigest {
        digest(data)
    }

    static func objectSetDigest(
        _ objects: [WorkspaceMutationContentObject]
    ) -> ContentDigest {
        let material = objects.sorted { $0.digest.rawValue < $1.digest.rawValue }
            .map { "\($0.digest.rawValue):\($0.data.count)" }
            .joined(separator: "\n")
        return digest(Data("object-set-v1\n\(material)".utf8))
    }

    static func affectedStateDigest(
        workspaceRoot: URL,
        paths: [String]
    ) throws -> ContentDigest {
        try affectedStateDigest(captureAffected(paths: paths, root: workspaceRoot))
    }

    static func unchangedStateDigest(
        workspaceRoot: URL,
        excludingPaths: Set<String>,
        limits: WorkspaceMutationExecutorLimits = .conservative
    ) throws -> ContentDigest {
        try WorkspaceMutationFilesystemExecutor().unaffectedDigest(
            root: workspaceRoot,
            excluding: excludingPaths,
            limits: limits
        )
    }

    private func validateApplyBindings(
        _ request: WorkspaceMutationExecutionRequest
    ) throws {
        guard request.completedAt >= request.intent.requestedAt,
              request.manifest.transactionID == request.rollbackManifest.transactionID,
              request.manifest.transactionID == request.preflightReceipt.transactionID,
              request.manifest.transactionID == request.intent.transactionID,
              request.preimage.workspaceID == request.workspaceID,
              request.preimage.canonicalDigest ==
                request.preflightReceipt.canonicalPreimageDigest,
              request.preimage.contractDigest == request.manifest.contractDigest,
              request.manifest.candidateID == request.preflightReceipt.candidateID,
              TransactionalMutationKernel.manifestDigest(request.manifest) ==
                request.preflightReceipt.manifestDigest,
              TransactionalMutationKernel.rollbackDigest(request.rollbackManifest) ==
                request.preflightReceipt.rollbackManifestDigest,
              request.intent.manifestDigest == request.preflightReceipt.manifestDigest,
              request.intent.canonicalPreimageDigest ==
                request.preflightReceipt.canonicalPreimageDigest,
              request.intent.rollbackManifestDigest ==
                request.preflightReceipt.rollbackManifestDigest,
              request.intent.preflightReceiptID == request.preflightReceipt.id,
              request.preflightReceipt.eligibleForDeterministicApply,
              !request.preflightReceipt.permitsPublication,
              request.preflightReceipt.operationCount == request.manifest.operations.count,
              request.preflightReceipt.affectedPaths ==
                affectedPaths(request.manifest.operations),
              request.manifest.expectedPostimageDigest ==
                request.rollbackManifest.expectedAppliedPostimageDigest,
              request.rollbackManifest.restoresPreimageDigest ==
                request.preflightReceipt.canonicalPreimageDigest,
              request.intent.remoteAccessDisabled,
              candidatePostimageCapturePolicyIsBound(request) else {
            throw WorkspaceMutationExecutionError.invalidBinding("apply")
        }
    }

    private func candidatePostimageCapturePolicyIsBound(
        _ request: WorkspaceMutationExecutionRequest
    ) -> Bool {
        switch (
            request.intent.candidatePostimageCapturePolicyDigest,
            request.candidatePostimageCapturePolicy
        ) {
        case (nil, nil):
            return true
        case let (expectedDigest?, policy?):
            return policy.validationIssues().isEmpty
                && policy.capturePolicyDigest == expectedDigest
        default:
            return false
        }
    }

    private func captureCandidatePostimage(
        request: WorkspaceMutationExecutionRequest,
        root: URL
    ) throws -> WorkspaceSourceRevisionArtifact? {
        guard let policy = request.candidatePostimageCapturePolicy else {
            return nil
        }
        let artifact = try WorkspaceSourceRevisionCollector().capture(
            workspaceID: request.workspaceID,
            root: root,
            excludedDirectoryNames: Set(policy.excludedDirectoryNames),
            limits: policy.limits
        )
        guard artifact.capturePolicyDigest ==
                request.intent.candidatePostimageCapturePolicyDigest,
              artifact.workspaceID == request.workspaceID,
              artifact.canonicalRootDigest ==
                WorkspaceRepositoryIndexer.canonicalRootDigest(root),
              artifact.validationIssues().isEmpty else {
            throw WorkspaceMutationExecutionError.invalidBinding(
                "candidate-postimage"
            )
        }
        return artifact
    }

    /// Older mutation requests bind the exact affected-path state digest.
    /// Contract-backed completed candidates instead bind the content-complete
    /// source revision that was reviewed before apply. Both are independently
    /// recomputed after the effect; the manifest digest itself selects which
    /// observation is authoritative, so callers cannot downgrade a full-tree
    /// requirement into an affected-path-only check.
    private func resolvedPostimageDigest(
        affectedStateDigest: ContentDigest,
        candidatePostimage: WorkspaceSourceRevisionArtifact?,
        expectedPostimageDigest: ContentDigest
    ) throws -> ContentDigest {
        if affectedStateDigest == expectedPostimageDigest {
            return affectedStateDigest
        }
        guard candidatePostimage?.sourceRevision == expectedPostimageDigest else {
            throw WorkspaceMutationExecutionError.filesystemFailure(
                "observed postimage does not match manifest"
            )
        }
        return expectedPostimageDigest
    }

    private func validateRollbackBindings(
        _ request: WorkspaceMutationRollbackRequest
    ) throws {
        guard request.completedAt >= request.intent.requestedAt,
              request.manifest.transactionID == request.rollbackManifest.transactionID,
              request.manifest.transactionID == request.preflightReceipt.transactionID,
              request.manifest.transactionID == request.applyReceipt.transactionID,
              request.manifest.transactionID == request.intent.transactionID,
              request.preimage.workspaceID == request.workspaceID,
              request.preimage.canonicalDigest ==
                request.preflightReceipt.canonicalPreimageDigest,
              request.preimage.contractDigest == request.manifest.contractDigest,
              request.applyReceipt.intentID != request.intent.id,
              TransactionalMutationKernel.manifestDigest(request.manifest) ==
                request.preflightReceipt.manifestDigest,
              TransactionalMutationKernel.rollbackDigest(request.rollbackManifest) ==
                request.preflightReceipt.rollbackManifestDigest,
              request.intent.rollbackManifestDigest ==
                request.preflightReceipt.rollbackManifestDigest,
              request.intent.recoveryArtifactDigest ==
                request.applyReceipt.recoveryArtifactDigest,
              request.intent.expectedCurrentWorkspaceDigest ==
                request.applyReceipt.observedPostimageDigest,
              request.intent.remoteAccessDisabled else {
            throw WorkspaceMutationExecutionError.invalidBinding("rollback")
        }
    }

    private func validateRecoveryArtifact(
        _ artifact: RecoveryArtifact,
        request: WorkspaceMutationExecutionRequest,
        operations: [MutationOperation]
    ) throws {
        let prefix = Array(operations.prefix(artifact.appliedOperationSequences.count))
            .map(\.sequence)
        guard (artifact.schemaVersion == 1 || artifact.schemaVersion == 2),
              artifact.workspaceID == request.workspaceID,
              artifact.rootIdentity == request.lease.rootIdentity,
              artifact.transactionID == request.manifest.transactionID,
              artifact.applyIntentID == request.intent.id,
              artifact.manifestDigest == request.preflightReceipt.manifestDigest,
              artifact.rollbackManifestDigest ==
                request.preflightReceipt.rollbackManifestDigest,
              artifact.appliedOperationSequences == prefix,
              artifact.baselineEntries.map(\.path) ==
                request.preflightReceipt.affectedPaths,
              artifact.ownedPostimageEntries.map(\.path) ==
                request.preflightReceipt.affectedPaths,
              Self.affectedStateDigest(artifact.baselineEntries) ==
                artifact.baselineAffectedDigest else {
            throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
        }
    }

    private func exactApplyReceipt(
        request: WorkspaceMutationExecutionRequest,
        observed: ContentDigest,
        unaffectedBefore: ContentDigest,
        unaffectedAfter: ContentDigest,
        recoveryDigest: ContentDigest,
        appliedCount: Int,
        completedAt: Date,
        candidatePostimage: WorkspaceSourceRevisionArtifact?
    ) -> IntegrationApplyReceipt {
        IntegrationApplyReceipt(
            id: Self.receiptID(
                prefix: "workspace-apply",
                fields: [request.intent.id.rawValue, recoveryDigest.rawValue]
            ),
            intentID: request.intent.id,
            transactionID: request.manifest.transactionID,
            manifestDigest: request.preflightReceipt.manifestDigest,
            canonicalPreimageDigest: request.preflightReceipt.canonicalPreimageDigest,
            observedPostimageDigest: observed,
            unchangedPathProofDigest: Self.proofDigest(
                before: unaffectedBefore,
                after: unaffectedAfter
            ),
            recoveryArtifactDigest: recoveryDigest,
            appliedOperationCount: appliedCount,
            executor: request.executor,
            completedAt: completedAt,
            outcome: .exactPostimage,
            candidatePostimage: candidatePostimage
        )
    }

    private func failedApplyReceipt(
        request: WorkspaceMutationExecutionRequest,
        observed: ContentDigest?,
        recoveryDigest: ContentDigest,
        appliedCount: Int,
        reason: ContentDigest,
        completedAt: Date
    ) -> IntegrationApplyReceipt {
        IntegrationApplyReceipt(
            id: Self.receiptID(
                prefix: "workspace-apply-failed",
                fields: [request.intent.id.rawValue, recoveryDigest.rawValue]
            ),
            intentID: request.intent.id,
            transactionID: request.manifest.transactionID,
            manifestDigest: request.preflightReceipt.manifestDigest,
            canonicalPreimageDigest: request.preflightReceipt.canonicalPreimageDigest,
            observedPostimageDigest: observed,
            unchangedPathProofDigest: nil,
            recoveryArtifactDigest: recoveryDigest,
            appliedOperationCount: appliedCount,
            executor: request.executor,
            completedAt: completedAt,
            outcome: observed == nil
                ? .inDoubt(reasonDigest: reason)
                : .failed(reasonDigest: reason)
        )
    }

    private func recoveredApplyFailureReceipt(
        request: WorkspaceMutationExecutionRequest,
        artifact: inout RecoveryArtifact,
        artifactURL: URL,
        observedEntries: [RecoveryEntry],
        reason: Error
    ) throws -> IntegrationApplyReceipt {
        let reasonDigest = Self.errorDigest(reason)
        artifact.lastObservedAffectedDigest = Self.affectedStateDigest(observedEntries)
        artifact.failureReasonDigest = reasonDigest
        artifact.status = .applyFailed
        artifact.updatedAt = request.completedAt
        try persist(
            artifact,
            to: artifactURL,
            maximumBytes: request.limits.maximumRecoveryBytes
        )
        return failedApplyReceipt(
            request: request,
            observed: artifact.lastObservedAffectedDigest,
            recoveryDigest: try Self.fileDigest(artifactURL),
            appliedCount: artifact.appliedOperationSequences.count,
            reason: reasonDigest,
            completedAt: request.completedAt
        )
    }

    private func restoredRollbackReceipt(
        request: WorkspaceMutationRollbackRequest,
        recoveryDigest: ContentDigest,
        receiptIdentityDigest: ContentDigest,
        unaffectedAfter: ContentDigest,
        completedAt: Date
    ) -> IntegrationRollbackReceipt {
        IntegrationRollbackReceipt(
            id: Self.receiptID(
                prefix: "workspace-rollback",
                fields: [request.intent.id.rawValue, receiptIdentityDigest.rawValue]
            ),
            intentID: request.intent.id,
            transactionID: request.manifest.transactionID,
            rollbackManifestDigest: request.preflightReceipt.rollbackManifestDigest,
            recoveryArtifactDigest: recoveryDigest,
            observedPreimageDigest: request.preflightReceipt.canonicalPreimageDigest,
            unchangedPathProofDigest: Self.proofDigest(
                before: unaffectedAfter,
                after: unaffectedAfter
            ),
            executor: request.executor,
            completedAt: completedAt,
            outcome: .restored
        )
    }

    private func validateLease(
        _ lease: WorkspaceMutationExecutionLease,
        receiptID: ReceiptID,
        transactionID: IntegrationTransactionID,
        workspaceID: WorkspaceID,
        rootIdentity: ContentDigest,
        at date: Date
    ) throws {
        guard lease.receiptID == receiptID,
              lease.transactionID == transactionID,
              lease.workspaceID == workspaceID,
              lease.rootIdentity == rootIdentity,
              lease.exclusive,
              lease.remoteAccessDisabled,
              date >= lease.issuedAt,
              date <= lease.expiresAt else {
            throw WorkspaceMutationExecutionError.invalidLease("lease binding or lifetime")
        }
    }

    private func validatedObjects(
        _ objects: [WorkspaceMutationContentObject],
        expectedSetDigest: ContentDigest
    ) throws -> [ContentDigest: Data] {
        guard Self.objectSetDigest(objects) == expectedSetDigest else {
            throw WorkspaceMutationExecutionError.invalidBinding("content object set")
        }
        var result: [ContentDigest: Data] = [:]
        for object in objects {
            guard !object.digest.rawValue.isEmpty,
                  result[object.digest] == nil else {
                throw WorkspaceMutationExecutionError.corruptContentObject(object.digest)
            }
            guard Self.contentDigest(object.data) == object.digest else {
                throw WorkspaceMutationExecutionError.corruptContentObject(object.digest)
            }
            result[object.digest] = object.data
        }
        return result
    }

    private func validateOperationsAtExecution(
        _ operations: [MutationOperation],
        root: URL,
        objects: [ContentDigest: Data]
    ) throws {
        for operation in operations.sorted(by: { $0.sequence < $1.sequence }) {
            try validateOperationAtExecution(operation, root: root, objects: objects)
        }
    }

    private func validateOperationAtExecution(
        _ operation: MutationOperation,
        root: URL,
        objects: [ContentDigest: Data]
    ) throws {
        for path in [operation.sourcePath, operation.destinationPath].compactMap({ $0 }) {
            _ = try safeURL(root: root, relativePath: path)
        }
        if operation.entryKindBefore == .directory || operation.entryKindAfter == .directory {
            throw WorkspaceMutationExecutionError.unsupportedEntryKind(
                path: operation.sourcePath ?? operation.destinationPath ?? "unknown",
                kind: .directory
            )
        }
        if operation.entryKindBefore == .submodule || operation.entryKindAfter == .submodule {
            throw WorkspaceMutationExecutionError.unsupportedEntryKind(
                path: operation.sourcePath ?? operation.destinationPath ?? "unknown",
                kind: .submodule
            )
        }
        if let desired = operation.desiredPostimage, objects[desired] == nil {
            throw WorkspaceMutationExecutionError.missingContentObject(desired)
        }
        let path = operation.sourcePath ?? operation.destinationPath
        if let expected = operation.expectedPreimage, let path {
            let entry = try Self.captureEntry(path: path, root: root)
            guard entry.exists,
                  entry.contentDigest == expected,
                  entry.kind == operation.entryKindBefore,
                  Self.modesMatch(
                    observed: entry.mode,
                    expected: operation.modeBefore
                  ) else {
                throw WorkspaceMutationExecutionError.compareAndSwapConflict(path: path)
            }
        } else if let path, operation.kind == .create || operation.expectedPreimage == nil {
            if operation.kind == .create || operation.kind == .symbolicLink {
                guard !(try Self.captureEntry(path: path, root: root)).exists else {
                    throw WorkspaceMutationExecutionError.compareAndSwapConflict(path: path)
                }
            }
        }
        if operation.kind == .rename,
           let destination = operation.destinationPath,
           (try Self.captureEntry(path: destination, root: root)).exists {
            throw WorkspaceMutationExecutionError.compareAndSwapConflict(path: destination)
        }
    }

    private func execute(
        _ operation: MutationOperation,
        root: URL,
        objects: [ContentDigest: Data]
    ) throws {
        switch operation.kind {
        case .create, .modify:
            guard let path = operation.destinationPath,
                  let digest = operation.desiredPostimage,
                  let data = objects[digest],
                  operation.entryKindAfter == .regularFile,
                  let mode = operation.modeAfter else {
                throw WorkspaceMutationExecutionError.invalidBinding("regular file write")
            }
            let url = try safeURL(root: root, relativePath: path)
            try data.write(to: url, options: operation.kind == .create ? .withoutOverwriting : .atomic)
            try setMode(mode, at: url)
            try synchronizeFile(at: url)
        case .delete:
            guard let path = operation.sourcePath else {
                throw WorkspaceMutationExecutionError.invalidBinding("delete")
            }
            try FileManager.default.removeItem(at: safeURL(root: root, relativePath: path))
        case .rename:
            guard let source = operation.sourcePath,
                  let destination = operation.destinationPath else {
                throw WorkspaceMutationExecutionError.invalidBinding("rename")
            }
            try FileManager.default.moveItem(
                at: safeURL(root: root, relativePath: source),
                to: safeURL(root: root, relativePath: destination)
            )
        case .chmod:
            guard let path = operation.destinationPath, let mode = operation.modeAfter else {
                throw WorkspaceMutationExecutionError.invalidBinding("chmod")
            }
            try setMode(mode, at: safeURL(root: root, relativePath: path))
        case .symbolicLink:
            guard let path = operation.destinationPath,
                  let digest = operation.desiredPostimage,
                  let data = objects[digest],
                  let target = String(data: data, encoding: .utf8) else {
                throw WorkspaceMutationExecutionError.invalidBinding("symbolic link")
            }
            let url = try safeURL(root: root, relativePath: path)
            if operation.expectedPreimage != nil { try FileManager.default.removeItem(at: url) }
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        case .submodule:
            throw WorkspaceMutationExecutionError.unsupportedEntryKind(
                path: operation.destinationPath ?? "unknown",
                kind: .submodule
            )
        }
    }

    private func validateOperationPostimage(
        _ operation: MutationOperation,
        root: URL,
        objects: [ContentDigest: Data]
    ) throws {
        switch operation.kind {
        case .delete:
            guard let path = operation.sourcePath,
                  !(try Self.captureEntry(path: path, root: root)).exists else {
                throw WorkspaceMutationExecutionError.filesystemFailure("delete postimage")
            }
        case .rename:
            guard let source = operation.sourcePath,
                  let destination = operation.destinationPath,
                  !(try Self.captureEntry(path: source, root: root)).exists else {
                throw WorkspaceMutationExecutionError.filesystemFailure("rename source")
            }
            try validateExpectedEntry(operation, at: destination, root: root)
        default:
            guard let path = operation.destinationPath else {
                throw WorkspaceMutationExecutionError.invalidBinding("postimage path")
            }
            try validateExpectedEntry(operation, at: path, root: root)
        }
        _ = objects
    }

    private func validateExpectedEntry(
        _ operation: MutationOperation,
        at path: String,
        root: URL
    ) throws {
        let entry = try Self.captureEntry(path: path, root: root)
        guard entry.exists,
              entry.contentDigest == operation.desiredPostimage,
              entry.kind == operation.entryKindAfter,
              Self.modesMatch(
                observed: entry.mode,
                expected: operation.modeAfter
              ) else {
            throw WorkspaceMutationExecutionError.filesystemFailure("postimage mismatch: \(path)")
        }
    }

    private func restore(entries: [RecoveryEntry], root: URL) throws {
        for entry in entries.sorted(by: { $0.path.count > $1.path.count }) {
            let url = try safeURL(root: root, relativePath: entry.path)
            if FileManager.default.fileExists(atPath: url.path)
                || (try? Self.captureEntry(path: entry.path, root: root).exists) == true {
                try FileManager.default.removeItem(at: url)
            }
        }
        for entry in entries.sorted(by: { $0.path < $1.path }) where entry.exists {
            let url = try safeURL(root: root, relativePath: entry.path)
            switch entry.kind {
            case .regularFile:
                guard let data = entry.contentData, let mode = entry.mode else {
                    throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
                }
                try data.write(to: url, options: .withoutOverwriting)
                try setMode(mode, at: url)
                try synchronizeFile(at: url)
            case .symbolicLink:
                guard let target = entry.symbolicLinkTarget else {
                    throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
                }
                try FileManager.default.createSymbolicLink(
                    atPath: url.path,
                    withDestinationPath: target
                )
            case .directory, .submodule, .none:
                throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
            }
        }
    }

    private func currentEntriesAreTransactionOwned(
        _ current: [RecoveryEntry],
        baseline: [RecoveryEntry],
        ownedPostimage: [RecoveryEntry]
    ) -> Bool {
        let baselineByPath = Dictionary(uniqueKeysWithValues: baseline.map { ($0.path, $0) })
        let ownedByPath = Dictionary(
            uniqueKeysWithValues: ownedPostimage.map { ($0.path, $0) }
        )
        for entry in current {
            if entry == baselineByPath[entry.path] { continue }
            if entry != ownedByPath[entry.path] { return false }
        }
        return true
    }

    private func quarantinedRollbackReceipt(
        request: WorkspaceMutationRollbackRequest,
        reason: Error,
        recoveryDigest: ContentDigest
    ) -> IntegrationRollbackReceipt {
        let reasonDigest = Self.errorDigest(reason)
        return IntegrationRollbackReceipt(
            id: Self.receiptID(
                prefix: "workspace-rollback-quarantined",
                fields: [request.intent.id.rawValue, reasonDigest.rawValue]
            ),
            intentID: request.intent.id,
            transactionID: request.manifest.transactionID,
            rollbackManifestDigest: request.preflightReceipt.rollbackManifestDigest,
            recoveryArtifactDigest: recoveryDigest,
            observedPreimageDigest: nil,
            unchangedPathProofDigest: nil,
            executor: request.executor,
            completedAt: request.completedAt,
            outcome: .failedQuarantined(
                reasonDigest: reasonDigest,
                recoveryArtifactDigest: recoveryDigest
            )
        )
    }

    private func validatedRoot(
        _ root: URL,
        workspaceID: WorkspaceID,
        expectedIdentity: ContentDigest
    ) throws -> URL {
        guard root.isFileURL, !workspaceID.rawValue.isEmpty else {
            throw WorkspaceMutationExecutionError.unsafeRoot(root.path)
        }
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        guard try Self.rootIdentity(resolved) == expectedIdentity else {
            throw WorkspaceMutationExecutionError.unsafeRoot(root.path)
        }
        return resolved
    }

    private func validatedRecoveryRoot(_ recovery: URL, outside root: URL) throws -> URL {
        guard recovery.isFileURL else {
            throw WorkspaceMutationExecutionError.unsafeRoot(recovery.path)
        }
        let resolved = recovery.standardizedFileURL.resolvingSymlinksInPath()
        let recoveryPath = resolved.path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard recoveryPath != rootPath,
              !recoveryPath.hasPrefix(rootPath + "/") else {
            throw WorkspaceMutationExecutionError.recoveryRootInsideWorkspace
        }
        return resolved
    }

    private func withExclusiveLock<T>(
        recoveryRoot: URL,
        workspaceID: WorkspaceID,
        limits: WorkspaceMutationExecutorLimits,
        body: () throws -> T
    ) throws -> T {
        guard limits.maximumSnapshotFiles > 0,
              limits.maximumSnapshotBytes > 0,
              limits.maximumRecoveryBytes > 0 else {
            throw WorkspaceMutationExecutionError.snapshotBudgetExceeded
        }
        try FileManager.default.createDirectory(
            at: recoveryRoot,
            withIntermediateDirectories: true
        )
        let lockName = Self.digest(Data(workspaceID.rawValue.utf8)).rawValue + ".lock"
        let lockURL = recoveryRoot.appendingPathComponent(lockName)
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw WorkspaceMutationExecutionError.lockUnavailable }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw WorkspaceMutationExecutionError.lockUnavailable
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func safeURL(root: URL, relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw WorkspaceMutationExecutionError.pathEscapesWorkspace(relativePath)
        }
        var current = root
        for component in components.dropLast() {
            current.appendPathComponent(String(component), isDirectory: true)
            var info = stat()
            guard lstat(current.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR else {
                throw WorkspaceMutationExecutionError.symbolicLinkInParent(relativePath)
            }
        }
        let result = root.appendingPathComponent(relativePath).standardizedFileURL
        guard result.path.hasPrefix(root.path + "/") else {
            throw WorkspaceMutationExecutionError.pathEscapesWorkspace(relativePath)
        }
        return result
    }

    private static func captureAffected(
        paths: [String],
        root: URL
    ) throws -> [RecoveryEntry] {
        try paths.sorted().map { try captureEntry(path: $0, root: root) }
    }

    private static func captureEntry(path: String, root: URL) throws -> RecoveryEntry {
        let executor = WorkspaceMutationFilesystemExecutor()
        let url = try executor.safeURL(root: root, relativePath: path)
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT {
                return RecoveryEntry(
                    path: path,
                    exists: false,
                    kind: nil,
                    mode: nil,
                    contentDigest: nil,
                    size: 0,
                    contentData: nil,
                    symbolicLinkTarget: nil,
                    fileSystemObjectIdentity: nil
                )
            }
            throw WorkspaceMutationExecutionError.filesystemFailure("lstat: \(path)")
        }
        let mode = UInt32(info.st_mode)
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return RecoveryEntry(
                path: path,
                exists: true,
                kind: .regularFile,
                mode: mode,
                contentDigest: contentDigest(data),
                size: UInt64(data.count),
                contentData: data,
                symbolicLinkTarget: nil,
                fileSystemObjectIdentity: objectIdentity(info)
            )
        case S_IFLNK:
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            let data = Data(target.utf8)
            return RecoveryEntry(
                path: path,
                exists: true,
                kind: .symbolicLink,
                mode: mode,
                contentDigest: contentDigest(data),
                size: UInt64(data.count),
                contentData: nil,
                symbolicLinkTarget: target,
                fileSystemObjectIdentity: objectIdentity(info)
            )
        case S_IFDIR:
            throw WorkspaceMutationExecutionError.unsupportedEntryKind(path: path, kind: .directory)
        default:
            throw WorkspaceMutationExecutionError.filesystemFailure("unsupported inode: \(path)")
        }
    }

    private func unaffectedDigest(
        root: URL,
        excluding paths: Set<String>,
        limits: WorkspaceMutationExecutorLimits
    ) throws -> ContentDigest {
        Self.digest(Self.encode(try unaffectedEntries(
            root: root,
            excluding: paths,
            limits: limits
        )))
    }

    private func unaffectedEntries(
        root: URL,
        excluding paths: Set<String>,
        limits: WorkspaceMutationExecutorLimits
    ) throws -> [UnchangedEntry] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw WorkspaceMutationExecutionError.filesystemFailure("enumerate workspace")
        }
        var records: [UnchangedEntry] = []
        var totalBytes: UInt64 = 0
        while let url = enumerator.nextObject() as? URL {
            let relative = try relativePath(of: url, beneath: root)
            if paths.contains(relative) { continue }
            if paths.contains(where: { relative.hasPrefix($0 + "/") }) {
                enumerator.skipDescendants()
                continue
            }
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                throw WorkspaceMutationExecutionError.filesystemFailure("lstat: \(relative)")
            }
            let kind: WorkspaceEntryKind
            let digestValue: ContentDigest
            let size: UInt64
            switch info.st_mode & S_IFMT {
            case S_IFREG:
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                kind = .regularFile
                digestValue = Self.contentDigest(data)
                size = UInt64(data.count)
            case S_IFLNK:
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                let data = Data(target.utf8)
                kind = .symbolicLink
                digestValue = Self.contentDigest(data)
                size = UInt64(data.count)
                enumerator.skipDescendants()
            case S_IFDIR:
                kind = .directory
                digestValue = Self.digest(Data("directory-v1".utf8))
                size = 0
            default:
                throw WorkspaceMutationExecutionError.filesystemFailure(
                    "unsupported inode: \(relative)"
                )
            }
            let (nextBytes, overflow) = totalBytes.addingReportingOverflow(size)
            guard !overflow,
                  records.count + 1 <= limits.maximumSnapshotFiles,
                  nextBytes <= limits.maximumSnapshotBytes else {
                throw WorkspaceMutationExecutionError.snapshotBudgetExceeded
            }
            totalBytes = nextBytes
            records.append(UnchangedEntry(
                path: relative,
                kind: kind,
                mode: UInt32(info.st_mode),
                contentDigest: digestValue,
                size: size
            ))
        }
        if let enumerationError {
            throw WorkspaceMutationExecutionError.filesystemFailure(
                "workspace enumeration: \(String(reflecting: enumerationError))"
            )
        }
        return records.sorted { $0.path < $1.path }
    }

    private func relativePath(of url: URL, beneath root: URL) throws -> String {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalParent = url.deletingLastPathComponent()
            .standardizedFileURL.resolvingSymlinksInPath()
        let canonicalURL = canonicalParent.appendingPathComponent(url.lastPathComponent)
        let prefix = canonicalRoot.path + "/"
        guard canonicalURL.path.hasPrefix(prefix) else {
            throw WorkspaceMutationExecutionError.pathEscapesWorkspace(url.path)
        }
        return String(canonicalURL.path.dropFirst(prefix.count))
    }

    private func persist<T: Encodable>(
        _ artifact: T,
        to url: URL,
        maximumBytes: UInt64
    ) throws {
        let data = Self.encode(artifact)
        guard UInt64(data.count) <= maximumBytes else {
            throw WorkspaceMutationExecutionError.recoveryBudgetExceeded
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
        try synchronizeFile(at: url)
    }

    private func loadArtifact(at url: URL, maximumBytes: UInt64) throws -> RecoveryArtifact {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            throw WorkspaceMutationExecutionError.recoveryArtifactMissing
        }
        guard size.uint64Value <= maximumBytes else {
            throw WorkspaceMutationExecutionError.recoveryBudgetExceeded
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(RecoveryArtifact.self, from: Data(contentsOf: url))
        } catch {
            throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
        }
    }

    private func loadRollbackArtifact(
        at url: URL,
        maximumBytes: UInt64
    ) throws -> RollbackRecoveryArtifact {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            throw WorkspaceMutationExecutionError.recoveryArtifactMissing
        }
        guard size.uint64Value <= maximumBytes else {
            throw WorkspaceMutationExecutionError.recoveryBudgetExceeded
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(
                RollbackRecoveryArtifact.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw WorkspaceMutationExecutionError.recoveryArtifactCorrupt
        }
    }

    private func recoveryArtifactURL(
        root: URL,
        transactionID: IntegrationTransactionID,
        intentID: IntegrationEffectIntentID
    ) -> URL {
        let component = Self.digest(Data(
            "\(transactionID.rawValue)\u{0}\(intentID.rawValue)".utf8
        )).rawValue
        return root.appendingPathComponent(component, isDirectory: true)
            .appendingPathComponent("recovery.json")
    }

    private func rollbackRecoveryArtifactURL(
        root: URL,
        transactionID: IntegrationTransactionID,
        intentID: IntegrationEffectIntentID
    ) -> URL {
        let component = Self.digest(Data(
            "\(transactionID.rawValue)\u{0}\(intentID.rawValue)".utf8
        )).rawValue
        return root.appendingPathComponent(component, isDirectory: true)
            .appendingPathComponent("rollback.json")
    }

    private func setMode(_ mode: UInt32, at url: URL) throws {
        guard chmod(url.path, mode_t(mode & 0o7777)) == 0 else {
            throw WorkspaceMutationExecutionError.filesystemFailure("chmod: \(url.path)")
        }
    }

    /// Mutation manifests describe permission bits, while legacy executor
    /// fixtures and recovery artifacts may retain the POSIX file-type bits
    /// from `st_mode`. File kind is checked independently, so CAS authority
    /// must compare the permission portion without weakening kind checks.
    private static func modesMatch(
        observed: UInt32?,
        expected: UInt32?
    ) -> Bool {
        switch (observed, expected) {
        case (nil, nil):
            return true
        case let (observed?, expected?):
            return observed & 0o7777 == expected & 0o7777
        default:
            return false
        }
    }

    private func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private func affectedPaths(_ operations: [MutationOperation]) -> [String] {
        Set(operations.flatMap { [$0.sourcePath, $0.destinationPath].compactMap { $0 } })
            .sorted()
    }

    private static func affectedStateDigest(_ entries: [RecoveryEntry]) -> ContentDigest {
        let states = entries.sorted { $0.path < $1.path }.map {
            AffectedEntryState(
                path: $0.path,
                exists: $0.exists,
                kind: $0.kind,
                mode: $0.mode,
                contentDigest: $0.contentDigest,
                size: $0.size
            )
        }
        return digest(encode(states))
    }

    private static func objectIdentity(_ info: stat) -> ContentDigest {
        digest(Data("inode-v1\u{0}\(info.st_dev)\u{0}\(info.st_ino)".utf8))
    }

    private static func proofDigest(
        before: ContentDigest,
        after: ContentDigest
    ) -> ContentDigest {
        digest(Data("unchanged-v1\u{0}\(before.rawValue)\u{0}\(after.rawValue)".utf8))
    }

    private static func receiptID(prefix: String, fields: [String]) -> ReceiptID {
        ReceiptID("\(prefix)-\(digest(Data(fields.joined(separator: "\u{0}").utf8)).rawValue)")
    }

    private static func errorDigest(_ error: Error) -> ContentDigest {
        digest(Data(String(reflecting: error).utf8))
    }

    private static func fileDigest(_ url: URL) throws -> ContentDigest {
        digest(try Data(contentsOf: url))
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return (try? encoder.encode(value)) ?? Data()
    }
}

private enum RecoveryStatus: String, Codable, Hashable, Sendable {
    case prepared
    case applying
    case applied
    case applyFailed
    case restored
}

private struct RecoveryArtifact: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workspaceID: WorkspaceID
    var rootIdentity: ContentDigest
    var transactionID: IntegrationTransactionID
    var applyIntentID: IntegrationEffectIntentID
    var manifestDigest: ContentDigest
    var rollbackManifestDigest: ContentDigest
    var baselineAffectedDigest: ContentDigest
    var unaffectedBeforeDigest: ContentDigest
    var baselineEntries: [RecoveryEntry]
    var ownedPostimageEntries: [RecoveryEntry]
    var appliedOperationSequences: [Int]
    var lastObservedAffectedDigest: ContentDigest?
    var failureReasonDigest: ContentDigest?
    var status: RecoveryStatus
    var createdAt: Date
    var updatedAt: Date
}

private struct RecoveryEntry: Codable, Hashable, Sendable {
    var path: String
    var exists: Bool
    var kind: WorkspaceEntryKind?
    var mode: UInt32?
    var contentDigest: ContentDigest?
    var size: UInt64
    var contentData: Data?
    var symbolicLinkTarget: String?
    var fileSystemObjectIdentity: ContentDigest?
}

private struct RollbackRecoveryArtifact: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var workspaceID: WorkspaceID
    var rootIdentity: ContentDigest
    var transactionID: IntegrationTransactionID
    var rollbackIntentID: IntegrationEffectIntentID
    var applyRecoveryArtifactDigest: ContentDigest
    var restoredEntries: [RecoveryEntry]
    var unaffectedDigest: ContentDigest
    var completedAt: Date
}

private struct AffectedEntryState: Codable, Hashable, Sendable {
    var path: String
    var exists: Bool
    var kind: WorkspaceEntryKind?
    var mode: UInt32?
    var contentDigest: ContentDigest?
    var size: UInt64
}

private struct UnchangedEntry: Codable, Hashable, Sendable {
    var path: String
    var kind: WorkspaceEntryKind
    var mode: UInt32
    var contentDigest: ContentDigest
    var size: UInt64
}
