import CryptoKit
import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceMutationFilesystemExecutorTests: XCTestCase {
    func testEffectOutboxPersistsPendingRequestAndExactCompletion() async throws {
        let fixture = try makeFixture()
        let outboxRoot = fixture.container.appendingPathComponent("effect-outbox")
        let runID = KernelRunID("outbox-run")
        let outbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: outboxRoot,
            runID: runID
        )
        let first = try await outbox.enqueue(
            payload: .apply(fixture.applyRequest),
            startCommandID: RunCommandID("apply-start"),
            recordCommandID: RunCommandID("apply-record"),
            releaseReceiptID: ReceiptID("apply-release"),
            releaseCommandID: RunCommandID("apply-release-command"),
            failureReceiptID: ReceiptID("apply-failure"),
            failureCommandID: RunCommandID("apply-failure-command"),
            enqueuedAt: date(220)
        )
        let duplicate = try await outbox.enqueue(
            payload: .apply(fixture.applyRequest),
            startCommandID: RunCommandID("apply-start"),
            recordCommandID: RunCommandID("apply-record"),
            releaseReceiptID: ReceiptID("apply-release"),
            releaseCommandID: RunCommandID("apply-release-command"),
            failureReceiptID: ReceiptID("apply-failure"),
            failureCommandID: RunCommandID("apply-failure-command"),
            enqueuedAt: date(220)
        )
        XCTAssertEqual(first.schemaVersion, 5)
        XCTAssertEqual(duplicate, first)
        let decodedURLDuplicate = try WorkspaceMutationEffectOutbox(
            rootDirectory: outboxRoot,
            runID: runID
        )
        let replayedAfterDecode = try await decodedURLDuplicate.enqueue(
            payload: .apply(fixture.applyRequest),
            startCommandID: RunCommandID("apply-start"),
            recordCommandID: RunCommandID("apply-record"),
            releaseReceiptID: ReceiptID("apply-release"),
            releaseCommandID: RunCommandID("apply-release-command"),
            failureReceiptID: ReceiptID("apply-failure"),
            failureCommandID: RunCommandID("apply-failure-command"),
            enqueuedAt: date(220)
        )
        XCTAssertEqual(replayedAfterDecode.payloadDigest, first.payloadDigest)
        try rewriteOutboxSnapshotAsVersionThree(
            outboxRoot.appendingPathComponent("effects.json")
        )

        let restarted = try WorkspaceMutationEffectOutbox(
            rootDirectory: outboxRoot,
            runID: runID
        )
        let pending = try await restarted.pending(limit: 10)
        XCTAssertEqual(pending, [first])

        let receiptDigest = ContentDigest("journaled-apply-receipt")
        let completed = try await restarted.markCompleted(
            intentID: first.intentID,
            receiptDigest: receiptDigest,
            completedAt: date(300)
        )
        guard case .completed(let observed, let completedAt) = completed.state else {
            return XCTFail("effect must be durably completed")
        }
        XCTAssertEqual(observed, receiptDigest)
        XCTAssertEqual(completedAt, date(300))

        let recovered = try WorkspaceMutationEffectOutbox(
            rootDirectory: outboxRoot,
            runID: runID
        )
        let recoveredPending = try await recovered.pending(limit: 10)
        let recoveredEntries = try await recovered.allEntries()
        XCTAssertTrue(recoveredPending.isEmpty)
        XCTAssertEqual(recoveredEntries, [completed])
        let persistedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: outboxRoot.appendingPathComponent("effects.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual(persistedObject["schemaVersion"] as? Int, 5)
    }

    func testEffectOutboxRejectsConflictingIntentAndWorkspaceLocalStorage() async throws {
        var fixture = try makeFixture()
        let externalRoot = fixture.container.appendingPathComponent("effect-outbox")
        let outbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: externalRoot,
            runID: KernelRunID("outbox-run")
        )
        _ = try await outbox.enqueue(
            payload: .apply(fixture.applyRequest),
            startCommandID: RunCommandID("apply-start"),
            recordCommandID: RunCommandID("apply-record"),
            releaseReceiptID: ReceiptID("apply-release"),
            releaseCommandID: RunCommandID("apply-release-command"),
            failureReceiptID: ReceiptID("apply-failure"),
            failureCommandID: RunCommandID("apply-failure-command"),
            enqueuedAt: date(220)
        )
        fixture.applyRequest.completedAt = date(251)
        do {
            _ = try await outbox.enqueue(
                payload: .apply(fixture.applyRequest),
                startCommandID: RunCommandID("apply-start"),
                recordCommandID: RunCommandID("apply-record"),
                releaseReceiptID: ReceiptID("apply-release"),
                releaseCommandID: RunCommandID("apply-release-command"),
                failureReceiptID: ReceiptID("apply-failure"),
                failureCommandID: RunCommandID("apply-failure-command"),
                enqueuedAt: date(220)
            )
            XCTFail("same intent with different sealed payload must conflict")
        } catch WorkspaceMutationEffectOutboxError.duplicateIntentConflict {}

        let firstRetry = try await outbox.recordRetryableFailure(
            intentID: fixture.applyRequest.intent.id,
            failureDigest: ContentDigest("retry-one"),
            attemptedAt: date(230)
        )
        guard case .retryScheduled(_, let firstAttemptCount, _) = firstRetry.state else {
            return XCTFail("first retryable failure must remain bounded-pending")
        }
        XCTAssertEqual(firstAttemptCount, 1)
        let pendingAfterFirstRetry = try await outbox.pending(limit: 10)
        XCTAssertEqual(pendingAfterFirstRetry.count, 1)

        let secondRetry = try await outbox.recordRetryableFailure(
            intentID: fixture.applyRequest.intent.id,
            failureDigest: ContentDigest("retry-two"),
            attemptedAt: date(240)
        )
        guard case .retryScheduled(_, let secondAttemptCount, _) = secondRetry.state else {
            return XCTFail("second retryable failure must remain bounded-pending")
        }
        XCTAssertEqual(secondAttemptCount, 2)

        let exhausted = try await outbox.recordRetryableFailure(
            intentID: fixture.applyRequest.intent.id,
            failureDigest: ContentDigest("retry-three"),
            attemptedAt: date(250)
        )
        guard case .quarantined(let exhaustedDigest, let exhaustedAt) = exhausted.state else {
            return XCTFail("dispatch retry budget must retire on the third failure")
        }
        XCTAssertEqual(exhaustedDigest, ContentDigest("retry-three"))
        XCTAssertEqual(exhaustedAt, date(250))
        let pendingAfterExhaustion = try await outbox.pending(limit: 10)
        XCTAssertTrue(pendingAfterExhaustion.isEmpty)

        let restartedExhausted = try WorkspaceMutationEffectOutbox(
            rootDirectory: externalRoot,
            runID: KernelRunID("outbox-run")
        )
        let pendingAfterRestart = try await restartedExhausted.pending(limit: 10)
        XCTAssertTrue(pendingAfterRestart.isEmpty)

        let localRoot = fixture.root.appendingPathComponent(".effect-outbox")
        let local = try WorkspaceMutationEffectOutbox(
            rootDirectory: localRoot,
            runID: KernelRunID("local-outbox-run")
        )
        do {
            _ = try await local.enqueue(
                payload: .apply(fixture.applyRequest),
                startCommandID: RunCommandID("local-start"),
                recordCommandID: RunCommandID("local-record"),
                releaseReceiptID: ReceiptID("local-release"),
                releaseCommandID: RunCommandID("local-release-command"),
                failureReceiptID: ReceiptID("local-failure"),
                failureCommandID: RunCommandID("local-failure-command"),
                enqueuedAt: date(220)
            )
            XCTFail("outbox storage inside the target workspace must fail")
        } catch WorkspaceMutationEffectOutboxError.rootInsideWorkspace {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: localRoot.path))
    }

    func testEffectOutboxRejectsTamperedSnapshotOnRestart() async throws {
        let fixture = try makeFixture()
        let outboxRoot = fixture.container.appendingPathComponent("effect-outbox")
        let runID = KernelRunID("outbox-run")
        let outbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: outboxRoot,
            runID: runID
        )
        _ = try await outbox.enqueue(
            payload: .apply(fixture.applyRequest),
            startCommandID: RunCommandID("apply-start"),
            recordCommandID: RunCommandID("apply-record"),
            releaseReceiptID: ReceiptID("apply-release"),
            releaseCommandID: RunCommandID("apply-release-command"),
            failureReceiptID: ReceiptID("apply-failure"),
            failureCommandID: RunCommandID("apply-failure-command"),
            enqueuedAt: date(220)
        )
        let snapshotURL = outboxRoot.appendingPathComponent("effects.json")
        var bytes = try Data(contentsOf: snapshotURL)
        bytes[bytes.startIndex] ^= 0x01
        try bytes.write(to: snapshotURL, options: .atomic)

        XCTAssertThrowsError(try WorkspaceMutationEffectOutbox(
            rootDirectory: outboxRoot,
            runID: runID
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationEffectOutboxError,
                .corruptSnapshot
            )
        }
    }

    func testRepeatedApplyRecoversExistingArtifactWithoutRecapturingBaseline() throws {
        var fixture = try makeFixture()
        let executor = WorkspaceMutationFilesystemExecutor()

        let first = try executor.apply(fixture.applyRequest)
        fixture.applyRequest.completedAt = date(400)
        let recovered = try executor.apply(fixture.applyRequest)

        XCTAssertEqual(recovered, first)
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "new-a")
        XCTAssertEqual(try text(fixture.root, "Sources/b.txt"), "b")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("Sources/delete.txt").path
        ))
    }

    func testExactApplyCapturesPolicyBoundContentCompleteCandidatePostimage() throws {
        var fixture = try makeFixture()
        let policy = WorkspaceCandidatePostimageCapturePolicy(
            excludedDirectoryNames: [],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 100,
                maximumTotalBytes: 1_024 * 1_024,
                maximumFileBytes: 1_024 * 1_024
            )
        )
        fixture.applyRequest.intent.candidatePostimageCapturePolicyDigest =
            try XCTUnwrap(policy.capturePolicyDigest)
        fixture.applyRequest.candidatePostimageCapturePolicy = policy

        let executor = WorkspaceMutationFilesystemExecutor()
        let apply = try executor.apply(fixture.applyRequest)
        let candidatePostimage = try XCTUnwrap(apply.candidatePostimage)

        XCTAssertTrue(candidatePostimage.validationIssues().isEmpty)
        XCTAssertEqual(candidatePostimage.workspaceID, fixture.workspaceID)
        XCTAssertEqual(
            candidatePostimage.capturePolicyDigest,
            fixture.applyRequest.intent.candidatePostimageCapturePolicyDigest
        )
        XCTAssertEqual(
            candidatePostimage.entries.map(\.relativePath),
            ["Sources/a.txt", "Sources/b.txt", "untouched.txt"]
        )
        XCTAssertEqual(
            candidatePostimage.entries.first(where: {
                $0.relativePath == "Sources/a.txt"
            })?.contentDigest,
            WorkspaceMutationFilesystemExecutor.contentDigest(Data("new-a".utf8))
        )

        fixture.applyRequest.completedAt = date(400)
        let recovered = try executor.apply(fixture.applyRequest)
        XCTAssertEqual(recovered.candidatePostimage, candidatePostimage)

        var mismatched = try makeFixture()
        mismatched.applyRequest.intent.candidatePostimageCapturePolicyDigest =
            try XCTUnwrap(policy.capturePolicyDigest)
        mismatched.applyRequest.candidatePostimageCapturePolicy =
            WorkspaceCandidatePostimageCapturePolicy(
                excludedDirectoryNames: ["Sources"],
                limits: policy.limits
            )
        XCTAssertThrowsError(try executor.apply(mismatched.applyRequest)) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationExecutionError,
                .invalidBinding("apply")
            )
        }
        XCTAssertEqual(try text(mismatched.root, "Sources/a.txt"), "old-a")
    }

    func testRepeatedApplyQuarantinesUnownedSameContentReplacement() throws {
        var fixture = try makeFixture()
        let executor = WorkspaceMutationFilesystemExecutor()
        _ = try executor.apply(fixture.applyRequest)

        try Data("new-a".utf8).write(
            to: fixture.root.appendingPathComponent("Sources/a.txt"),
            options: .atomic
        )
        fixture.applyRequest.completedAt = date(400)
        let recovered = try executor.apply(fixture.applyRequest)

        guard case .failed = recovered.outcome else {
            return XCTFail("unowned replacement must fail recovery")
        }
        XCTAssertEqual(recovered.appliedOperationCount, 3)
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "new-a")

        fixture.applyRequest.completedAt = date(450)
        let repeated = try executor.apply(fixture.applyRequest)
        XCTAssertEqual(repeated, recovered)
    }

    func testExactApplyAndRollbackPreserveUnrelatedWorkspaceState() throws {
        let fixture = try makeFixture()
        let executor = WorkspaceMutationFilesystemExecutor()

        let apply = try executor.apply(fixture.applyRequest)
        guard case .exactPostimage = apply.outcome else {
            return XCTFail("expected exact postimage, got \(apply.outcome)")
        }
        XCTAssertEqual(apply.appliedOperationCount, 3)
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "new-a")
        XCTAssertEqual(try text(fixture.root, "Sources/b.txt"), "b")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("Sources/delete.txt").path
        ))
        XCTAssertEqual(try text(fixture.root, "untouched.txt"), "keep")

        var transactionState = try advance(
            nil,
            .propose(IntegrationProposal(
                runID: KernelRunID("run"),
                transactionID: fixture.manifest.transactionID,
                candidateID: fixture.manifest.candidateID,
                attemptID: AttemptID("attempt"),
                nodeID: KernelNodeID("node"),
                contractDigest: fixture.manifest.contractDigest,
                planNodeDigest: fixture.manifest.planNodeDigest,
                manifestDigest: fixture.preflight.manifestDigest,
                canonicalPreimageDigest: fixture.preflight.canonicalPreimageDigest,
                expectedPostimageDigest: fixture.manifest.expectedPostimageDigest,
                proposedAt: date(190)
            )),
            actor: fixture.actor
        )
        transactionState = try advance(
            transactionState,
            .acceptPreflight(receipt: fixture.preflight, rollback: fixture.rollback),
            actor: fixture.actor
        )
        transactionState = try advance(
            transactionState,
            .startApply(fixture.applyRequest.intent),
            actor: fixture.actor
        )
        transactionState = try advance(
            transactionState,
            .recordApply(apply),
            actor: fixture.actor
        )
        XCTAssertEqual(transactionState.phase, .appliedUnverified)

        let rollbackIntent = IntegrationRollbackIntent(
            id: IntegrationEffectIntentID("rollback-intent"),
            transactionID: fixture.manifest.transactionID,
            rollbackManifestDigest: fixture.preflight.rollbackManifestDigest,
            expectedCurrentWorkspaceDigest: apply.observedPostimageDigest,
            recoveryArtifactDigest: apply.recoveryArtifactDigest,
            exclusiveLeaseReceiptID: ReceiptID("rollback-lease"),
            remoteAccessDisabled: true,
            requestedAt: date(260)
        )
        var rollbackRequest = WorkspaceMutationRollbackRequest(
            workspaceRoot: fixture.root,
            recoveryRoot: fixture.recoveryRoot,
            workspaceID: fixture.workspaceID,
            preimage: fixture.preimage,
            manifest: fixture.manifest,
            rollbackManifest: fixture.rollback,
            preflightReceipt: fixture.preflight,
            applyReceipt: apply,
            intent: rollbackIntent,
            lease: lease(
                fixture: fixture,
                receiptID: rollbackIntent.exclusiveLeaseReceiptID,
                issuedAt: date(251),
                expiresAt: date(500)
            ),
            executor: fixture.actor,
            completedAt: date(270),
            limits: .conservative
        )
        let rollback = try executor.rollback(rollbackRequest)
        guard case .restored = rollback.outcome else {
            return XCTFail("expected exact restoration")
        }
        transactionState = try advance(
            transactionState,
            .requestRollback(rollbackIntent),
            actor: fixture.actor
        )
        transactionState = try advance(
            transactionState,
            .recordRollback(rollback),
            actor: fixture.actor
        )
        XCTAssertEqual(transactionState.phase, .rolledBack)
        XCTAssertEqual(rollback.observedPreimageDigest, fixture.preimage.canonicalDigest)
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "old-a")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("Sources/b.txt").path
        ))
        XCTAssertEqual(try text(fixture.root, "Sources/delete.txt"), "old-delete")
        XCTAssertEqual(try text(fixture.root, "untouched.txt"), "keep")

        rollbackRequest.completedAt = date(400)
        let recoveredRollback = try executor.rollback(rollbackRequest)
        guard case .restored = recoveredRollback.outcome else {
            return XCTFail("repeated rollback must confirm the restored baseline")
        }
        XCTAssertEqual(recoveredRollback.id, rollback.id)
        XCTAssertEqual(recoveredRollback.recoveryArtifactDigest, apply.recoveryArtifactDigest)
    }

    func testStaleCASRejectsBeforeAnyExecutorMutation() throws {
        let fixture = try makeFixture()
        try Data("newer-user-edit".utf8).write(
            to: fixture.root.appendingPathComponent("Sources/a.txt"),
            options: .atomic
        )
        XCTAssertThrowsError(
            try WorkspaceMutationFilesystemExecutor().apply(fixture.applyRequest)
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationExecutionError,
                .compareAndSwapConflict(path: "Sources/a.txt")
            )
        }
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "newer-user-edit")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("Sources/b.txt").path
        ))
        XCTAssertEqual(try text(fixture.root, "Sources/delete.txt"), "old-delete")
    }

    func testExpiredOrMismatchedLeaseFailsClosed() throws {
        var fixture = try makeFixture()
        fixture.applyRequest.lease.expiresAt = date(220)
        XCTAssertThrowsError(
            try WorkspaceMutationFilesystemExecutor().apply(fixture.applyRequest)
        ) { error in
            guard case .invalidLease = error as? WorkspaceMutationExecutionError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "old-a")

        fixture.applyRequest.lease.expiresAt = date(500)
        fixture.applyRequest.lease.workspaceID = WorkspaceID("other-workspace")
        XCTAssertThrowsError(
            try WorkspaceMutationFilesystemExecutor().apply(fixture.applyRequest)
        ) { error in
            guard case .invalidLease = error as? WorkspaceMutationExecutionError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRecoveryArtifactsCannotBeWrittenInsideWorkspace() throws {
        var fixture = try makeFixture()
        fixture.applyRequest.recoveryRoot = fixture.root.appendingPathComponent(".recovery")
        XCTAssertThrowsError(
            try WorkspaceMutationFilesystemExecutor().apply(fixture.applyRequest)
        ) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationExecutionError,
                .recoveryRootInsideWorkspace
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent(".recovery").path
        ))
    }

    func testRollbackQuarantinesWhenUnrelatedUserStateChanges() throws {
        let fixture = try makeFixture()
        let executor = WorkspaceMutationFilesystemExecutor()
        let apply = try executor.apply(fixture.applyRequest)
        try Data("user-kept-edit".utf8).write(
            to: fixture.root.appendingPathComponent("untouched.txt"),
            options: .atomic
        )
        let intent = IntegrationRollbackIntent(
            id: IntegrationEffectIntentID("rollback-intent-drift"),
            transactionID: fixture.manifest.transactionID,
            rollbackManifestDigest: fixture.preflight.rollbackManifestDigest,
            expectedCurrentWorkspaceDigest: apply.observedPostimageDigest,
            recoveryArtifactDigest: apply.recoveryArtifactDigest,
            exclusiveLeaseReceiptID: ReceiptID("rollback-lease-drift"),
            remoteAccessDisabled: true,
            requestedAt: date(260)
        )
        let receipt = try executor.rollback(WorkspaceMutationRollbackRequest(
            workspaceRoot: fixture.root,
            recoveryRoot: fixture.recoveryRoot,
            workspaceID: fixture.workspaceID,
            preimage: fixture.preimage,
            manifest: fixture.manifest,
            rollbackManifest: fixture.rollback,
            preflightReceipt: fixture.preflight,
            applyReceipt: apply,
            intent: intent,
            lease: lease(
                fixture: fixture,
                receiptID: intent.exclusiveLeaseReceiptID,
                issuedAt: date(251),
                expiresAt: date(500)
            ),
            executor: fixture.actor,
            completedAt: date(270),
            limits: .conservative
        ))
        guard case .failedQuarantined = receipt.outcome else {
            return XCTFail("unrelated drift must quarantine rollback")
        }
        XCTAssertEqual(try text(fixture.root, "untouched.txt"), "user-kept-edit")
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "new-a")
    }

    func testRollbackDoesNotOverwriteSameContentWithDifferentInodeIdentity() throws {
        let fixture = try makeFixture()
        let executor = WorkspaceMutationFilesystemExecutor()
        let apply = try executor.apply(fixture.applyRequest)
        try Data("new-a".utf8).write(
            to: fixture.root.appendingPathComponent("Sources/a.txt"),
            options: .atomic
        )
        let intent = IntegrationRollbackIntent(
            id: IntegrationEffectIntentID("rollback-intent-recreated"),
            transactionID: fixture.manifest.transactionID,
            rollbackManifestDigest: fixture.preflight.rollbackManifestDigest,
            expectedCurrentWorkspaceDigest: apply.observedPostimageDigest,
            recoveryArtifactDigest: apply.recoveryArtifactDigest,
            exclusiveLeaseReceiptID: ReceiptID("rollback-lease-recreated"),
            remoteAccessDisabled: true,
            requestedAt: date(260)
        )
        let receipt = try executor.rollback(WorkspaceMutationRollbackRequest(
            workspaceRoot: fixture.root,
            recoveryRoot: fixture.recoveryRoot,
            workspaceID: fixture.workspaceID,
            preimage: fixture.preimage,
            manifest: fixture.manifest,
            rollbackManifest: fixture.rollback,
            preflightReceipt: fixture.preflight,
            applyReceipt: apply,
            intent: intent,
            lease: lease(
                fixture: fixture,
                receiptID: intent.exclusiveLeaseReceiptID,
                issuedAt: date(251),
                expiresAt: date(500)
            ),
            executor: fixture.actor,
            completedAt: date(270),
            limits: .conservative
        ))
        guard case .failedQuarantined = receipt.outcome else {
            return XCTFail("same bytes from another inode must not be treated as owned")
        }
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "new-a")
    }

    func testSymlinkedParentCannotRedirectMutationOutsideWorkspace() throws {
        let fixture = try makeFixture()
        let sourceDirectory = fixture.root.appendingPathComponent("Sources")
        let externalDirectory = fixture.container.appendingPathComponent("external-sources")
        try FileManager.default.moveItem(at: sourceDirectory, to: externalDirectory)
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory,
            withDestinationURL: externalDirectory
        )
        XCTAssertThrowsError(
            try WorkspaceMutationFilesystemExecutor().apply(fixture.applyRequest)
        ) { error in
            guard case .symbolicLinkInParent = error as? WorkspaceMutationExecutionError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(
            try String(
                contentsOf: externalDirectory.appendingPathComponent("a.txt"),
                encoding: .utf8
            ),
            "old-a"
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: externalDirectory.appendingPathComponent("b.txt").path
        ))
    }

    func testCorruptStagedObjectIsRejectedBeforeWorkspaceEffect() throws {
        var fixture = try makeFixture()
        fixture.applyRequest.contentObjects[0].data = Data("xxxxx".utf8)
        XCTAssertThrowsError(
            try WorkspaceMutationFilesystemExecutor().apply(fixture.applyRequest)
        ) { error in
            guard case .corruptContentObject = error as? WorkspaceMutationExecutionError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try text(fixture.root, "Sources/a.txt"), "old-a")
    }

    private struct Fixture {
        var container: URL
        var root: URL
        var recoveryRoot: URL
        var workspaceID: WorkspaceID
        var preimage: WorkspacePreimage
        var manifest: MutationManifest
        var rollback: RollbackManifest
        var preflight: MutationPreflightReceipt
        var actor: ActorIdentity
        var applyRequest: WorkspaceMutationExecutionRequest
    }

    private func rewriteOutboxSnapshotAsVersionThree(_ url: URL) throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        object["schemaVersion"] = 3
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        for index in entries.indices {
            entries[index]["schemaVersion"] = 3
        }
        object["entries"] = entries
        object["snapshotDigest"] = ""
        let digestInput = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        object["snapshotDigest"] = SHA256.hash(data: digestInput).map {
            String(format: "%02x", $0)
        }.joined()
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ).write(to: url, options: .atomic)
    }

    private func makeFixture() throws -> Fixture {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopforge-workspace-executor-\(UUID().uuidString)")
        let root = container.appendingPathComponent("workspace", isDirectory: true)
        let recoveryRoot = container.appendingPathComponent("recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: container) }
        try write("old-a", to: root, path: "Sources/a.txt")
        try write("old-delete", to: root, path: "Sources/delete.txt")
        try write("keep", to: root, path: "untouched.txt")

        let workspaceID = WorkspaceID("workspace-\(UUID().uuidString)")
        let rootIdentity = try WorkspaceMutationFilesystemExecutor.rootIdentity(root)
        let oldA = WorkspaceMutationFilesystemExecutor.contentDigest(Data("old-a".utf8))
        let newA = WorkspaceMutationFilesystemExecutor.contentDigest(Data("new-a".utf8))
        let oldDelete = WorkspaceMutationFilesystemExecutor.contentDigest(
            Data("old-delete".utf8)
        )
        let newB = WorkspaceMutationFilesystemExecutor.contentDigest(Data("b".utf8))
        let entries = [
            entry("Sources/a.txt", digest: oldA, size: 5),
            entry("Sources/delete.txt", digest: oldDelete, size: 10)
        ]
        let preimage = WorkspacePreimage(
            workspaceID: workspaceID,
            rootIdentity: rootIdentity,
            contractDigest: ContentDigest("contract"),
            sourceRevision: ContentDigest("revision"),
            requiredPlanes: [.head, .index, .worktree, .untracked],
            capturedPlanes: [.head, .index, .worktree, .untracked],
            entries: entries,
            repositoryMetadataDigest: ContentDigest("repository-metadata"),
            ignoredPathPolicyDigest: ContentDigest("ignored-policy"),
            capturedAt: date(100)
        )

        let candidate = container.appendingPathComponent("candidate", isDirectory: true)
        try FileManager.default.createDirectory(
            at: candidate.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try write("new-a", to: candidate, path: "Sources/a.txt")
        try write("b", to: candidate, path: "Sources/b.txt")
        let affected = ["Sources/a.txt", "Sources/b.txt", "Sources/delete.txt"]
        let expectedPostimage = try WorkspaceMutationFilesystemExecutor.affectedStateDigest(
            workspaceRoot: candidate,
            paths: affected
        )
        let requirement = RequirementID("requirement")
        let manifest = MutationManifest(
            transactionID: IntegrationTransactionID("transaction-\(UUID().uuidString)"),
            candidateID: MutationCandidateID("candidate"),
            contractDigest: ContentDigest("contract"),
            planNodeDigest: ContentDigest("plan-node"),
            basePreimageDigest: preimage.canonicalDigest,
            operations: [
                operation(
                    sequence: 1,
                    kind: .modify,
                    source: nil,
                    destination: "Sources/a.txt",
                    before: oldA,
                    after: newA,
                    kindBefore: .regularFile,
                    kindAfter: .regularFile,
                    modeBefore: 0o100644,
                    modeAfter: 0o100644,
                    requirement: requirement
                ),
                operation(
                    sequence: 2,
                    kind: .create,
                    source: nil,
                    destination: "Sources/b.txt",
                    before: nil,
                    after: newB,
                    kindBefore: nil,
                    kindAfter: .regularFile,
                    modeBefore: nil,
                    modeAfter: 0o100644,
                    requirement: requirement
                ),
                operation(
                    sequence: 3,
                    kind: .delete,
                    source: "Sources/delete.txt",
                    destination: nil,
                    before: oldDelete,
                    after: nil,
                    kindBefore: .regularFile,
                    kindAfter: nil,
                    modeBefore: 0o100644,
                    modeAfter: nil,
                    requirement: requirement
                )
            ],
            touchedRequirementIDs: [requirement],
            writeAuthorityReceiptID: ReceiptID("write-authority"),
            mutationBudgetReceiptID: ReceiptID("mutation-budget"),
            candidateVerificationReceiptIDs: [ReceiptID("candidate-verification")],
            independentReviewReceiptID: ReceiptID("independent-review"),
            rollbackRehearsalReceiptID: ReceiptID("rollback-rehearsal"),
            candidateQuiescenceReceiptID: ReceiptID("candidate-quiescence"),
            visualGateReceiptID: nil,
            expectedPostimageDigest: expectedPostimage
        )
        let context = MutationPreflightContext(
            currentContractDigest: ContentDigest("contract"),
            currentPlanNodeDigest: ContentDigest("plan-node"),
            preimage: preimage,
            actualWorktreeEntries: entries,
            contentObjectSizes: [oldA: 5, newA: 5, oldDelete: 10, newB: 1],
            acceptedCandidateVerificationReceiptIDs: [ReceiptID("candidate-verification")],
            acceptedIndependentReviewReceiptIDs: [ReceiptID("independent-review")],
            acceptedVisualGateReceiptIDs: [],
            preparationFacts: MutationPreflightPreparationFacts(
                writeAuthority: MutationWriteAuthorityPreparationReceipt(
                    id: ReceiptID("write-authority"),
                    binding: preparationBinding(manifest),
                    authorizedPaths: Set(affected),
                    authorizedRequirementIDs: [requirement]
                ),
                mutationBudget: MutationBudgetPreparationReceipt(
                    id: ReceiptID("mutation-budget"),
                    binding: preparationBinding(manifest),
                    maximumChangedFiles: 3,
                    maximumChangedBytes: 32
                ),
                rollbackRehearsal: MutationRollbackRehearsalPreparationReceipt(
                    id: ReceiptID("rollback-rehearsal"),
                    binding: preparationBinding(manifest),
                    forwardManifestDigest: TransactionalMutationKernel.manifestDigest(
                        manifest
                    ),
                    rehearsedOperationCount: manifest.operations.count
                ),
                candidateQuiescence: MutationCandidateQuiescencePreparationReceipt(
                    id: ReceiptID("candidate-quiescence"),
                    binding: preparationBinding(manifest),
                    candidateScoped: true,
                    activeOwnedResourceCount: 0,
                    unreleasedLeaseCount: 0,
                    externalEffectCount: 0
                ),
                pathResolution: MutationPathResolutionPreparationReceipt(
                    id: ReceiptID("path-resolution"),
                    binding: preparationBinding(manifest),
                    rootIdentity: preimage.rootIdentity,
                    operations: Set(manifest.operations.map {
                        MutationPathResolutionBinding(
                            sequence: $0.sequence,
                            sourcePath: $0.sourcePath,
                            destinationPath: $0.destinationPath
                        )
                    }),
                    noSymbolicLinkTraversal: true
                )
            ),
            visualGateRequired: false,
            observedAt: date(200)
        )
        guard case .admitted(let preflight, let rollback) =
            TransactionalMutationKernel.preflight(manifest: manifest, context: context) else {
            throw NSError(domain: "WorkspaceMutationFilesystemExecutorTests", code: 1)
        }
        let objects = [
            WorkspaceMutationContentObject(digest: newA, data: Data("new-a".utf8)),
            WorkspaceMutationContentObject(digest: newB, data: Data("b".utf8))
        ]
        let intent = IntegrationApplyIntent(
            id: IntegrationEffectIntentID("apply-intent"),
            transactionID: manifest.transactionID,
            preflightReceiptID: preflight.id,
            manifestDigest: preflight.manifestDigest,
            canonicalPreimageDigest: preflight.canonicalPreimageDigest,
            rollbackManifestDigest: preflight.rollbackManifestDigest,
            stagedObjectSetDigest:
                WorkspaceMutationFilesystemExecutor.objectSetDigest(objects),
            exclusiveLeaseReceiptID: ReceiptID("apply-lease"),
            remoteAccessDisabled: true,
            requestedAt: date(210)
        )
        let actor = ActorIdentity(
            id: ActorID("filesystem-executor"),
            role: "workspace-mutation-executor",
            lineageDigest: ContentDigest("filesystem-executor-lineage")
        )
        let provisional = Fixture(
            container: container,
            root: root,
            recoveryRoot: recoveryRoot,
            workspaceID: workspaceID,
            preimage: preimage,
            manifest: manifest,
            rollback: rollback,
            preflight: preflight,
            actor: actor,
            applyRequest: WorkspaceMutationExecutionRequest(
                workspaceRoot: root,
                recoveryRoot: recoveryRoot,
                workspaceID: workspaceID,
                preimage: preimage,
                manifest: manifest,
                rollbackManifest: rollback,
                preflightReceipt: preflight,
                intent: intent,
                lease: WorkspaceMutationExecutionLease(
                    receiptID: intent.exclusiveLeaseReceiptID,
                    transactionID: manifest.transactionID,
                    workspaceID: workspaceID,
                    rootIdentity: rootIdentity,
                    exclusive: true,
                    remoteAccessDisabled: true,
                    issuedAt: date(205),
                    expiresAt: date(500)
                ),
                contentObjects: objects,
                executor: actor,
                completedAt: date(250),
                limits: .conservative
            )
        )
        return provisional
    }

    private func lease(
        fixture: Fixture,
        receiptID: ReceiptID,
        issuedAt: Date,
        expiresAt: Date
    ) -> WorkspaceMutationExecutionLease {
        WorkspaceMutationExecutionLease(
            receiptID: receiptID,
            transactionID: fixture.manifest.transactionID,
            workspaceID: fixture.workspaceID,
            rootIdentity: fixture.preimage.rootIdentity,
            exclusive: true,
            remoteAccessDisabled: true,
            issuedAt: issuedAt,
            expiresAt: expiresAt
        )
    }

    private func preparationBinding(
        _ manifest: MutationManifest
    ) -> MutationPreparationBinding {
        MutationPreparationBinding(
            transactionID: manifest.transactionID,
            candidateID: manifest.candidateID,
            contractDigest: manifest.contractDigest,
            planNodeDigest: manifest.planNodeDigest,
            canonicalPreimageDigest: manifest.basePreimageDigest,
            expectedPostimageDigest: manifest.expectedPostimageDigest
        )
    }

    private func advance(
        _ current: IntegrationTransactionState?,
        _ command: IntegrationTransitionCommand,
        actor: ActorIdentity
    ) throws -> IntegrationTransactionState {
        let decision = IntegrationTransactionReducer.decide(
            current: current,
            command: command,
            actor: actor,
            knownReceiptIDs: current?.receiptIDs ?? [],
            knownIntentIDs: current?.intentIDs ?? []
        )
        guard case .success(let event) = decision,
              let next = IntegrationTransactionReducer.reduce(current: current, event: event) else {
            throw NSError(domain: "WorkspaceMutationFilesystemExecutorTests", code: 2)
        }
        return next
    }

    private func operation(
        sequence: Int,
        kind: MutationOperationKind,
        source: String?,
        destination: String?,
        before: ContentDigest?,
        after: ContentDigest?,
        kindBefore: WorkspaceEntryKind?,
        kindAfter: WorkspaceEntryKind?,
        modeBefore: UInt32?,
        modeAfter: UInt32?,
        requirement: RequirementID
    ) -> MutationOperation {
        MutationOperation(
            sequence: sequence,
            kind: kind,
            sourcePath: source,
            destinationPath: destination,
            expectedPreimage: before,
            desiredPostimage: after,
            entryKindBefore: kindBefore,
            entryKindAfter: kindAfter,
            modeBefore: modeBefore,
            modeAfter: modeAfter,
            requirementIDs: [requirement],
            pathResolutionReceiptID: ReceiptID("path-resolution")
        )
    }

    private func entry(
        _ path: String,
        digest: ContentDigest,
        size: UInt64
    ) -> WorkspaceEntrySnapshot {
        WorkspaceEntrySnapshot(
            plane: .worktree,
            path: path,
            kind: .regularFile,
            mode: 0o100644,
            contentDigest: digest,
            size: size,
            ownership: .userExisting
        )
    }

    private func write(_ value: String, to root: URL, path: String) throws {
        let url = root.appendingPathComponent(path)
        try Data(value.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: url.path
        )
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
