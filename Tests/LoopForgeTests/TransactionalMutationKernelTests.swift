import XCTest
@testable import LoopForge

final class TransactionalMutationKernelTests: XCTestCase {
    private let requirementID = RequirementID("requirement")
    private let oldA = ContentDigest("old-a")
    private let newA = ContentDigest("new-a")
    private let oldDelete = ContentDigest("old-delete")
    private let newB = ContentDigest("new-b")

    func testValidManifestProducesApplyEligibilityAndExactReverseRollback() throws {
        let context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        let (receipt, rollback) = try admitted(manifest, context)

        XCTAssertTrue(receipt.eligibleForDeterministicApply)
        XCTAssertFalse(receipt.permitsPublication)
        XCTAssertEqual(
            receipt.affectedPaths,
            ["Sources/a.txt", "Sources/b.txt", "Sources/delete.txt"]
        )
        XCTAssertEqual(receipt.changedFileCount, 3)
        XCTAssertEqual(receipt.operationCount, 3)
        XCTAssertEqual(receipt.changedByteCount, 19)
        XCTAssertEqual(rollback.forwardManifestDigest, receipt.manifestDigest)
        XCTAssertEqual(rollback.restoresPreimageDigest, context.preimage.canonicalDigest)
        XCTAssertEqual(rollback.operations.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(rollback.operations.map(\.kind), [.create, .delete, .modify])
        XCTAssertEqual(rollback.operations[0].destinationPath, "Sources/delete.txt")
        XCTAssertEqual(rollback.operations[0].desiredPostimage, oldDelete)
        XCTAssertEqual(rollback.operations[0].entryKindAfter, .regularFile)
        XCTAssertEqual(rollback.operations[1].sourcePath, "Sources/b.txt")
        XCTAssertEqual(rollback.operations[1].expectedPreimage, newB)
        XCTAssertEqual(rollback.operations[1].entryKindBefore, .regularFile)
        XCTAssertEqual(rollback.operations[2].destinationPath, "Sources/a.txt")
        XCTAssertEqual(rollback.operations[2].expectedPreimage, newA)
        XCTAssertEqual(rollback.operations[2].desiredPostimage, oldA)
    }

    func testPreflightConsumesNonSerializableAuthorityCapability() throws {
        let context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        let authority = AuthorizedMutationPreflight.testOnly(
            manifest: manifest,
            context: context
        )
        guard case .admitted(let receipt, let rollback) =
                TransactionalMutationKernel.preflight(authority) else {
            return XCTFail("expected capability-authorized preflight")
        }
        XCTAssertEqual(
            receipt.manifestDigest,
            TransactionalMutationKernel.manifestDigest(manifest)
        )
        XCTAssertEqual(
            receipt.rollbackManifestDigest,
            TransactionalMutationKernel.rollbackDigest(rollback)
        )
        XCTAssertFalse(receipt.permitsPublication)
    }

    func testStaleContractPlanAndPreimageRejectBeforeEligibility() {
        var context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        context.currentContractDigest = ContentDigest("new-contract")
        XCTAssertEqual(
            TransactionalMutationKernel.preflight(manifest: manifest, context: context),
            .rejected(.staleContract)
        )

        context = makeContext()
        context.currentPlanNodeDigest = ContentDigest("new-plan")
        XCTAssertEqual(
            TransactionalMutationKernel.preflight(manifest: manifest, context: context),
            .rejected(.stalePlanNode)
        )

        context = makeContext()
        var staleBase = manifest
        staleBase.basePreimageDigest = ContentDigest("stale-base")
        XCTAssertEqual(
            TransactionalMutationKernel.preflight(manifest: staleBase, context: context),
            .rejected(.preimageDigestMismatch)
        )
    }

    func testIncompleteOrDuplicatePreimageCaptureFailsClosed() {
        var context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        context.preimage.capturedPlanes.remove(.index)
        XCTAssertEqual(
            TransactionalMutationKernel.preflight(manifest: manifest, context: context),
            .rejected(.incompletePreimageCapture)
        )

        context = makeContext()
        context.preimage.entries.append(context.preimage.entries[0])
        var rebound = manifest
        rebound.basePreimageDigest = context.preimage.canonicalDigest
        XCTAssertEqual(
            TransactionalMutationKernel.preflight(manifest: rebound, context: context),
            .rejected(.incompletePreimageCapture)
        )
    }

    func testEveryAuthorityAndCandidateGateIsMandatory() {
        let manifest: MutationManifest
        var context = makeContext()
        manifest = makeManifest(preimage: context.preimage)

        context.preparationFacts.writeAuthority.id = ReceiptID("wrong-write")
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingWriteAuthority))
        context = makeContext()
        context.preparationFacts.mutationBudget.id = ReceiptID("wrong-budget")
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingMutationBudgetAuthority))
        context = makeContext()
        context.acceptedCandidateVerificationReceiptIDs = []
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingCandidateVerification([ReceiptID("verify")]))
        )
        context = makeContext()
        var missingVerificationManifest = manifest
        missingVerificationManifest.candidateVerificationReceiptIDs = []
        XCTAssertEqual(
            preflight(missingVerificationManifest, context),
            .rejected(.malformedManifest("all mandatory receipt IDs must be present"))
        )
        context = makeContext()
        context.acceptedIndependentReviewReceiptIDs = []
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingIndependentReview))
        context = makeContext()
        context.preparationFacts.rollbackRehearsal.id = ReceiptID("wrong-rollback")
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingRollbackRehearsal))
        context = makeContext()
        context.preparationFacts.candidateQuiescence.candidateScoped = false
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingCandidateQuiescence))
        context = makeContext()
        context.preparationFacts.pathResolution.operations = []
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingPathResolutionReceipt("Sources/a.txt"))
        )
    }

    func testPreparationFactsAreExactTransactionCandidateAndTopologyBound() {
        let manifest: MutationManifest
        var context = makeContext()
        manifest = makeManifest(preimage: context.preimage)

        context.preparationFacts.writeAuthority.binding.candidateID =
            MutationCandidateID("different-candidate")
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingWriteAuthority))

        context = makeContext()
        context.preparationFacts.mutationBudget.binding.transactionID =
            IntegrationTransactionID("different-transaction")
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingMutationBudgetAuthority)
        )

        context = makeContext()
        context.preparationFacts.candidateQuiescence.activeOwnedResourceCount = 1
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingCandidateQuiescence)
        )

        context = makeContext()
        context.preparationFacts.pathResolution.rootIdentity = ContentDigest("other-root")
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingPathResolutionReceipt("Sources/a.txt"))
        )

        context = makeContext()
        context.preparationFacts.rollbackRehearsal.forwardManifestDigest =
            ContentDigest("unrehearsed-manifest")
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingRollbackRehearsal)
        )
    }

    func testVisualGateAndExternalEffectsCannotBeBypassed() {
        var context = makeContext()
        var manifest = makeManifest(preimage: context.preimage)
        context.visualGateRequired = true
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingVisualGate))

        manifest.visualGateReceiptID = ReceiptID("visual")
        context.acceptedVisualGateReceiptIDs = [ReceiptID("visual")]
        XCTAssertNotNil(try? admitted(manifest, context))

        context = makeContext()
        XCTAssertEqual(preflight(manifest, context), .rejected(.missingVisualGate))

        context.preparationFacts.candidateQuiescence.externalEffectCount = 1
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.candidateExternalEffectsForbidden)
        )
    }

    func testProtectedBaselineEntryCannotBeModifiedEvenWithWriteAuthority() {
        var context = makeContext()
        let baselineID = BaselineID("baseline")
        context.protectedWorkspaceEntries = [ProtectedWorkspaceEntryBinding(
            baselineID: baselineID,
            entry: ProtectedWorkspaceEntry(
                path: "Sources/a.txt",
                contentDigest: oldA,
                scope: .exactEntry
            )
        )]
        let manifest = makeManifest(preimage: context.preimage)

        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.protectedBaselineMutation(
                path: "Sources/a.txt",
                baselineID: baselineID
            ))
        )
    }

    func testProtectedBaselineSubtreeRejectsDescendantCreation() {
        var context = makeContext()
        let baselineID = BaselineID("baseline-tree")
        context.protectedWorkspaceEntries = [ProtectedWorkspaceEntryBinding(
            baselineID: baselineID,
            entry: ProtectedWorkspaceEntry(
                path: "Sources",
                contentDigest: ContentDigest("baseline-tree-digest"),
                scope: .subtree
            )
        )]
        let manifest = makeManifest(preimage: context.preimage)

        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.protectedBaselineMutation(
                path: "Sources/a.txt",
                baselineID: baselineID
            ))
        )
    }

    func testProtectedBaselineDriftFailsAsBaselineMismatchBeforeMutation() {
        var context = makeContext()
        context.protectedWorkspaceEntries = [ProtectedWorkspaceEntryBinding(
            baselineID: BaselineID("baseline"),
            entry: ProtectedWorkspaceEntry(
                path: "Sources/a.txt",
                contentDigest: ContentDigest("different-baseline-bytes"),
                scope: .exactEntry
            )
        )]
        let manifest = makeManifest(preimage: context.preimage)

        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.compareAndSwapConflict(
                path: "Sources/a.txt",
                conflict: .baselineMismatch
            ))
        )
    }

    func testLegacyPreflightContextRoundTripsWithoutWorkspaceBindings() throws {
        let context = makeContext()

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(MutationPreflightContext.self, from: data)

        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(
            "protectedWorkspaceEntries"
        ))
        XCTAssertNil(decoded.protectedWorkspaceEntries)
        XCTAssertEqual(decoded, context)
    }

    func testTraversalAbsoluteGlobAndUnicodeAliasPathsAreRejected() {
        let invalidPaths = ["../escape", "/absolute", "Sources/*", "Sources//a"]
        for path in invalidPaths {
            var context = makeContext()
            var manifest = makeManifest(preimage: context.preimage)
            manifest.operations[0].destinationPath = path
        context.preparationFacts.writeAuthority.authorizedPaths.insert(path)
            XCTAssertEqual(
                preflight(manifest, context),
                .rejected(.invalidPath(path)),
                path
            )
        }

        let decomposed = "Sources/cafe\u{301}.txt"
        var context = makeContext()
        var manifest = makeManifest(preimage: context.preimage)
        manifest.operations[0].destinationPath = decomposed
        context.preparationFacts.writeAuthority.authorizedPaths.insert(decomposed)
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.invalidPath(decomposed))
        )
    }

    func testPathAuthorityCaseCollisionAndRepeatedMutationReject() {
        var context = makeContext()
        var manifest = makeManifest(preimage: context.preimage)
        context.preparationFacts.writeAuthority.authorizedPaths.remove("Sources/b.txt")
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.pathOutsideAuthority("Sources/b.txt"))
        )

        context = makeContext()
        manifest = makeManifest(preimage: context.preimage)
        manifest.operations[1].destinationPath = "sources/A.txt"
        context.preparationFacts.writeAuthority.authorizedPaths.insert("sources/A.txt")
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.pathCollision("sources/A.txt"))
        )

        context = makeContext()
        manifest = makeManifest(preimage: context.preimage)
        manifest.operations[1].destinationPath = "Sources/a.txt"
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.pathCollision("Sources/a.txt"))
        )

        context = makeContext()
        context.actualWorktreeEntries.append(entry("Sources/Existing.txt", digest: oldA))
        context.preparationFacts.writeAuthority.authorizedPaths.insert("sources/existing.txt")
        manifest = singleOperationManifest(
            preimage: context.preimage,
            operation: MutationOperation(
                sequence: 1,
                kind: .create,
                sourcePath: nil,
                destinationPath: "sources/existing.txt",
                expectedPreimage: nil,
                desiredPostimage: newB,
                entryKindBefore: nil,
                entryKindAfter: .regularFile,
                modeBefore: nil,
                modeAfter: 0o100644,
                requirementIDs: [requirementID],
                pathResolutionReceiptID: ReceiptID("path")
            )
        )
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.pathCollision("sources/existing.txt"))
        )
    }

    func testCompareAndSwapRejectsNewerUserBytesAndRenameTopology() {
        var context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        context.actualWorktreeEntries[0].contentDigest = ContentDigest("user-newer")
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.compareAndSwapConflict(
                path: "Sources/a.txt",
                conflict: .newerUserChange
            ))
        )

        context = makeContext()
        context.actualWorktreeEntries.append(entry("Sources/b.txt", digest: newB))
        var rename = singleOperationManifest(
            preimage: context.preimage,
            operation: MutationOperation(
                sequence: 1,
                kind: .rename,
                sourcePath: "Sources/a.txt",
                destinationPath: "Sources/b.txt",
                expectedPreimage: oldA,
                desiredPostimage: newA,
                entryKindBefore: .regularFile,
                entryKindAfter: .regularFile,
                modeBefore: 0o100644,
                modeAfter: 0o100644,
                requirementIDs: [requirementID],
                pathResolutionReceiptID: ReceiptID("path")
            )
        )
        context.contentObjectSizes[newA] = 10
        rebindPreparationFacts(&context, to: rename)
        XCTAssertEqual(
            preflight(rename, context),
            .rejected(.compareAndSwapConflict(
                path: "Sources/b.txt",
                conflict: .pathTopologyChange
            ))
        )
        rename.operations[0].destinationPath = "Sources/renamed.txt"
        context.preparationFacts.writeAuthority.authorizedPaths.insert("Sources/renamed.txt")
        XCTAssertNotNil(try? admitted(rename, context))

        context = makeContext()
        context.actualWorktreeEntries[0].contentDigest = ContentDigest("accepted-sibling")
        context.actualWorktreeEntries[0].ownership = .taskPriorAccepted
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.compareAndSwapConflict(
                path: "Sources/a.txt",
                conflict: .acceptedSiblingChange
            ))
        )

        context = makeContext()
        context.actualWorktreeEntries[0].kind = .symbolicLink
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.compareAndSwapConflict(
                path: "Sources/a.txt",
                conflict: .modeOrSymlinkConflict
            ))
        )
    }

    func testFileAndByteBudgetsAreRecomputedFromSealedObjects() {
        var context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        context.preparationFacts.mutationBudget.maximumChangedFiles = 2
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.fileBudgetExceeded(actual: 3, maximum: 2))
        )

        context = makeContext()
        context.preparationFacts.mutationBudget.maximumChangedBytes = 18
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.byteBudgetExceeded(actual: 19, maximum: 18))
        )

        context = makeContext()
        context.contentObjectSizes[newB] = nil
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingContentObject(newB))
        )

        context = makeContext()
        context.contentObjectSizes[oldDelete] = nil
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.missingContentObject(oldDelete))
        )

        context = makeContext()
        context.contentObjectSizes[oldA] = 999
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.contentObjectSizeMismatch(
                digest: oldA,
                expected: 4,
                actual: 999
            ))
        )
    }

    func testOperationSequenceShapeAndRequirementOwnershipAreExact() {
        let context = makeContext()
        var manifest = makeManifest(preimage: context.preimage)
        manifest.operations[1].sequence = 4
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.malformedManifest(
                "operation sequences must be contiguous and start at one"
            ))
        )

        manifest = makeManifest(preimage: context.preimage)
        manifest.operations[0].expectedPreimage = nil
        XCTAssertEqual(
            preflight(manifest, context),
            .rejected(.invalidOperation(
                sequence: 1,
                reason: "operation fields do not match its declared kind"
            ))
        )

        manifest = makeManifest(preimage: context.preimage)
        manifest.touchedRequirementIDs = [RequirementID("other")]
        XCTAssertEqual(preflight(manifest, context), .rejected(.requirementOwnershipMismatch))

        manifest = makeManifest(preimage: context.preimage)
        manifest.operations[0].requirementIDs = [RequirementID("unauthorized")]
        XCTAssertEqual(preflight(manifest, context), .rejected(.requirementOwnershipMismatch))
    }

    func testPreimageAndManifestDigestsIgnoreSetAndInputEnumerationOrder() throws {
        let context = makeContext()
        let manifest = makeManifest(preimage: context.preimage)
        let first = try admitted(manifest, context).0

        var reorderedContext = context
        reorderedContext.preimage.entries.reverse()
        reorderedContext.actualWorktreeEntries.reverse()
        reorderedContext.preimage.requiredPlanes = Set(
            reorderedContext.preimage.requiredPlanes.sorted { $0.rawValue > $1.rawValue }
        )
        var reorderedManifest = manifest
        reorderedManifest.operations.reverse()
        reorderedManifest.touchedRequirementIDs = Set(
            reorderedManifest.touchedRequirementIDs.sorted { $0.rawValue > $1.rawValue }
        )
        reorderedManifest.basePreimageDigest = reorderedContext.preimage.canonicalDigest
        let second = try admitted(reorderedManifest, reorderedContext).0

        XCTAssertEqual(first.canonicalPreimageDigest, second.canonicalPreimageDigest)
        XCTAssertEqual(first.manifestDigest, second.manifestDigest)
        XCTAssertEqual(first.rollbackManifestDigest, second.rollbackManifestDigest)
    }

    func testCreatedSymbolicObjectRollsBackAsDeletion() throws {
        var context = makeContext()
        let desired = ContentDigest("link-target")
        context.preparationFacts.writeAuthority.authorizedPaths.insert("Sources/link")
        context.contentObjectSizes[desired] = 12
        let manifest = singleOperationManifest(
            preimage: context.preimage,
            operation: MutationOperation(
                sequence: 1,
                kind: .symbolicLink,
                sourcePath: nil,
                destinationPath: "Sources/link",
                expectedPreimage: nil,
                desiredPostimage: desired,
                entryKindBefore: nil,
                entryKindAfter: .symbolicLink,
                modeBefore: nil,
                modeAfter: 0o120000,
                requirementIDs: [requirementID],
                pathResolutionReceiptID: ReceiptID("path")
            )
        )
        let (_, rollback) = try admitted(manifest, context)
        XCTAssertEqual(rollback.operations.count, 1)
        XCTAssertEqual(rollback.operations[0].kind, .delete)
        XCTAssertEqual(rollback.operations[0].sourcePath, "Sources/link")
        XCTAssertEqual(rollback.operations[0].expectedPreimage, desired)
        XCTAssertNil(rollback.operations[0].desiredPostimage)
    }

    private func preflight(
        _ manifest: MutationManifest,
        _ context: MutationPreflightContext
    ) -> MutationPreflightDecision {
        TransactionalMutationKernel.preflight(manifest: manifest, context: context)
    }

    private func admitted(
        _ manifest: MutationManifest,
        _ originalContext: MutationPreflightContext
    ) throws -> (MutationPreflightReceipt, RollbackManifest) {
        var context = originalContext
        rebindPreparationFacts(&context, to: manifest)
        guard case .admitted(let receipt, let rollback) = preflight(manifest, context) else {
            throw NSError(domain: "TransactionalMutationKernelTests", code: 1)
        }
        return (receipt, rollback)
    }

    private func rebindPreparationFacts(
        _ context: inout MutationPreflightContext,
        to manifest: MutationManifest
    ) {
        let binding = MutationPreparationBinding(
            transactionID: manifest.transactionID,
            candidateID: manifest.candidateID,
            contractDigest: manifest.contractDigest,
            planNodeDigest: manifest.planNodeDigest,
            canonicalPreimageDigest: manifest.basePreimageDigest,
            expectedPostimageDigest: manifest.expectedPostimageDigest
        )
        context.preparationFacts.writeAuthority.binding = binding
        context.preparationFacts.mutationBudget.binding = binding
        context.preparationFacts.rollbackRehearsal.binding = binding
        context.preparationFacts.rollbackRehearsal.forwardManifestDigest =
            TransactionalMutationKernel.manifestDigest(manifest)
        context.preparationFacts.rollbackRehearsal.rehearsedOperationCount =
            manifest.operations.count
        context.preparationFacts.candidateQuiescence.binding = binding
        context.preparationFacts.pathResolution.binding = binding
        context.preparationFacts.pathResolution.operations = Set(
            manifest.operations.map {
                MutationPathResolutionBinding(
                    sequence: $0.sequence,
                    sourcePath: $0.sourcePath,
                    destinationPath: $0.destinationPath
                )
            }
        )
    }

    private func makeContext() -> MutationPreflightContext {
        let preimage = WorkspacePreimage(
            workspaceID: WorkspaceID("workspace"),
            rootIdentity: ContentDigest("root"),
            contractDigest: ContentDigest("contract"),
            sourceRevision: ContentDigest("revision"),
            requiredPlanes: [.head, .index, .worktree, .untracked],
            capturedPlanes: [.head, .index, .worktree, .untracked],
            entries: [
                entry("Sources/a.txt", digest: oldA),
                entry("Sources/delete.txt", digest: oldDelete)
            ],
            repositoryMetadataDigest: ContentDigest("metadata"),
            ignoredPathPolicyDigest: ContentDigest("ignored-policy"),
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let binding = MutationPreparationBinding(
            transactionID: IntegrationTransactionID("transaction"),
            candidateID: MutationCandidateID("candidate"),
            contractDigest: ContentDigest("contract"),
            planNodeDigest: ContentDigest("plan"),
            canonicalPreimageDigest: preimage.canonicalDigest,
            expectedPostimageDigest: ContentDigest("expected-postimage")
        )
        return MutationPreflightContext(
            currentContractDigest: ContentDigest("contract"),
            currentPlanNodeDigest: ContentDigest("plan"),
            preimage: preimage,
            actualWorktreeEntries: preimage.entries,
            contentObjectSizes: [oldA: 4, newA: 10, oldDelete: 4, newB: 5],
            acceptedCandidateVerificationReceiptIDs: [ReceiptID("verify")],
            acceptedIndependentReviewReceiptIDs: [ReceiptID("review")],
            acceptedVisualGateReceiptIDs: [],
            preparationFacts: MutationPreflightPreparationFacts(
                writeAuthority: MutationWriteAuthorityPreparationReceipt(
                    id: ReceiptID("write"),
                    binding: binding,
                    authorizedPaths: [
                        "Sources/a.txt", "Sources/b.txt", "Sources/delete.txt"
                    ],
                    authorizedRequirementIDs: [requirementID]
                ),
                mutationBudget: MutationBudgetPreparationReceipt(
                    id: ReceiptID("budget"),
                    binding: binding,
                    maximumChangedFiles: 3,
                    maximumChangedBytes: 19
                ),
                rollbackRehearsal: MutationRollbackRehearsalPreparationReceipt(
                    id: ReceiptID("rollback"),
                    binding: binding,
                    forwardManifestDigest: TransactionalMutationKernel.manifestDigest(
                        makeManifest(preimage: preimage)
                    ),
                    rehearsedOperationCount: 3
                ),
                candidateQuiescence: MutationCandidateQuiescencePreparationReceipt(
                    id: ReceiptID("quiescence"),
                    binding: binding,
                    candidateScoped: true,
                    activeOwnedResourceCount: 0,
                    unreleasedLeaseCount: 0,
                    externalEffectCount: 0
                ),
                pathResolution: MutationPathResolutionPreparationReceipt(
                    id: ReceiptID("path"),
                    binding: binding,
                    rootIdentity: preimage.rootIdentity,
                    operations: [
                        MutationPathResolutionBinding(
                            sequence: 1,
                            sourcePath: nil,
                            destinationPath: "Sources/a.txt"
                        ),
                        MutationPathResolutionBinding(
                            sequence: 2,
                            sourcePath: nil,
                            destinationPath: "Sources/b.txt"
                        ),
                        MutationPathResolutionBinding(
                            sequence: 3,
                            sourcePath: "Sources/delete.txt",
                            destinationPath: nil
                        )
                    ],
                    noSymbolicLinkTraversal: true
                )
            ),
            visualGateRequired: false,
            observedAt: Date(timeIntervalSince1970: 200)
        )
    }

    private func makeManifest(preimage: WorkspacePreimage) -> MutationManifest {
        MutationManifest(
            transactionID: IntegrationTransactionID("transaction"),
            candidateID: MutationCandidateID("candidate"),
            contractDigest: ContentDigest("contract"),
            planNodeDigest: ContentDigest("plan"),
            basePreimageDigest: preimage.canonicalDigest,
            operations: [
                MutationOperation(
                    sequence: 1,
                    kind: .modify,
                    sourcePath: nil,
                    destinationPath: "Sources/a.txt",
                    expectedPreimage: oldA,
                    desiredPostimage: newA,
                    entryKindBefore: .regularFile,
                    entryKindAfter: .regularFile,
                    modeBefore: 0o100644,
                    modeAfter: 0o100644,
                    requirementIDs: [requirementID],
                    pathResolutionReceiptID: ReceiptID("path")
                ),
                MutationOperation(
                    sequence: 2,
                    kind: .create,
                    sourcePath: nil,
                    destinationPath: "Sources/b.txt",
                    expectedPreimage: nil,
                    desiredPostimage: newB,
                    entryKindBefore: nil,
                    entryKindAfter: .regularFile,
                    modeBefore: nil,
                    modeAfter: 0o100644,
                    requirementIDs: [requirementID],
                    pathResolutionReceiptID: ReceiptID("path")
                ),
                MutationOperation(
                    sequence: 3,
                    kind: .delete,
                    sourcePath: "Sources/delete.txt",
                    destinationPath: nil,
                    expectedPreimage: oldDelete,
                    desiredPostimage: nil,
                    entryKindBefore: .regularFile,
                    entryKindAfter: nil,
                    modeBefore: 0o100644,
                    modeAfter: nil,
                    requirementIDs: [requirementID],
                    pathResolutionReceiptID: ReceiptID("path")
                )
            ],
            touchedRequirementIDs: [requirementID],
            writeAuthorityReceiptID: ReceiptID("write"),
            mutationBudgetReceiptID: ReceiptID("budget"),
            candidateVerificationReceiptIDs: [ReceiptID("verify")],
            independentReviewReceiptID: ReceiptID("review"),
            rollbackRehearsalReceiptID: ReceiptID("rollback"),
            candidateQuiescenceReceiptID: ReceiptID("quiescence"),
            visualGateReceiptID: nil,
            expectedPostimageDigest: ContentDigest("expected-postimage")
        )
    }

    private func singleOperationManifest(
        preimage: WorkspacePreimage,
        operation: MutationOperation
    ) -> MutationManifest {
        var manifest = makeManifest(preimage: preimage)
        manifest.operations = [operation]
        manifest.touchedRequirementIDs = operation.requirementIDs
        return manifest
    }

    private func entry(
        _ path: String,
        digest: ContentDigest
    ) -> WorkspaceEntrySnapshot {
        WorkspaceEntrySnapshot(
            plane: .worktree,
            path: path,
            kind: .regularFile,
            mode: 0o100644,
            contentDigest: digest,
            size: 4,
            ownership: .userExisting
        )
    }
}
