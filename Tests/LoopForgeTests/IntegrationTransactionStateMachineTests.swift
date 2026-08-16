import Foundation
import XCTest
@testable import LoopForge

final class IntegrationTransactionStateMachineTests: XCTestCase {
    private let runID = KernelRunID("run")
    private let transactionID = IntegrationTransactionID("transaction")
    private let candidateID = MutationCandidateID("candidate")
    private let attemptID = AttemptID("attempt")
    private let nodeID = KernelNodeID("node")
    private let executor = ActorIdentity(
        id: ActorID("executor"),
        role: "transaction-executor",
        lineageDigest: ContentDigest("executor-lineage")
    )
    private let verifier = ActorIdentity(
        id: ActorID("verifier"),
        role: "postimage-verifier",
        lineageDigest: ContentDigest("verifier-lineage")
    )
    private let reviewer = ActorIdentity(
        id: ActorID("reviewer"),
        role: "independent-reviewer",
        lineageDigest: ContentDigest("reviewer-lineage")
    )

    func testExactProgressionSeparatesApplyVerificationAndAcceptance() throws {
        var state = try advance(nil, .propose(proposal()), actor: executor)
        let prepared = preflightAndRollback()
        state = try advance(
            state,
            .acceptPreflight(receipt: prepared.0, rollback: prepared.1),
            actor: executor
        )
        XCTAssertEqual(state.phase, .rollbackPrepared)
        XCTAssertFalse(state.permitsPublication)

        state = try advance(state, .startApply(applyIntent()), actor: executor)
        state = try advance(state, .recordApply(applyReceipt()), actor: executor)
        XCTAssertEqual(state.phase, .appliedUnverified)
        XCTAssertFalse(state.permitsPublication)

        state = try advance(
            state,
            .recordPostimageVerification(verificationReceipt()),
            actor: verifier
        )
        XCTAssertEqual(state.phase, .postimageVerified)
        state = try advance(
            state,
            .recordIndependentAcceptance(acceptanceReceipt()),
            actor: reviewer
        )
        XCTAssertEqual(state.phase, .independentlyAccepted)
        XCTAssertFalse(state.permitsPublication)
        XCTAssertEqual(state.receiptIDs.count, 4)
        XCTAssertEqual(state.intentIDs, [IntegrationEffectIntentID("apply-intent")])
    }

    func testFailedApplyCannotVerifyAndRequiresExactRollback() throws {
        var state = try preparedState()
        state = try advance(state, .startApply(applyIntent()), actor: executor)
        var failed = applyReceipt()
        failed.observedPostimageDigest = nil
        failed.unchangedPathProofDigest = nil
        failed.appliedOperationCount = 0
        failed.outcome = .inDoubt(reasonDigest: ContentDigest("apply-failure"))
        state = try advance(state, .recordApply(failed), actor: executor)
        XCTAssertEqual(state.phase, .rollbackRequired)

        XCTAssertEqual(
            rejection(
                state,
                .recordPostimageVerification(verificationReceipt()),
                actor: verifier
            ),
            .invalidPhase(expected: [.appliedUnverified], actual: .rollbackRequired)
        )

        var rollback = rollbackIntent()
        rollback.expectedCurrentWorkspaceDigest = nil
        state = try advance(state, .requestRollback(rollback), actor: executor)
        state = try advance(state, .recordRollback(rollbackReceipt()), actor: executor)
        XCTAssertEqual(state.phase, .rolledBack)
        XCTAssertEqual(state.rollbackReceipt?.observedPreimageDigest, ContentDigest("preimage"))
    }

    func testRejectedVerificationAndFailedRollbackRemainQuarantined() throws {
        var state = try appliedState()
        var rejected = verificationReceipt()
        rejected.result = .rejected(reasonDigest: ContentDigest("test-failure"))
        state = try advance(
            state,
            .recordPostimageVerification(rejected),
            actor: verifier
        )
        XCTAssertEqual(state.phase, .rollbackRequired)
        state = try advance(state, .requestRollback(rollbackIntent()), actor: executor)

        var failed = rollbackReceipt()
        failed.observedPreimageDigest = nil
        failed.unchangedPathProofDigest = nil
        failed.outcome = .failedQuarantined(
            reasonDigest: ContentDigest("rollback-failure"),
            recoveryArtifactDigest: ContentDigest("recovery-artifact")
        )
        state = try advance(state, .recordRollback(failed), actor: executor)
        XCTAssertEqual(state.phase, .rollbackFailedQuarantined)
        XCTAssertFalse(state.permitsPublication)
    }

    func testRemoteAccessIdentityAndLineageBypassesFailClosed() throws {
        var state = try preparedState()
        var unsafeIntent = applyIntent()
        unsafeIntent.remoteAccessDisabled = false
        XCTAssertEqual(
            rejection(state, .startApply(unsafeIntent), actor: executor),
            .remoteAccessNotDisabled
        )

        state = try advance(state, .startApply(applyIntent()), actor: executor)
        var wrongExecutor = applyReceipt()
        wrongExecutor.executor = reviewer
        XCTAssertEqual(
            rejection(state, .recordApply(wrongExecutor), actor: executor),
            .invalidApplyReceipt
        )

        state = try advance(state, .recordApply(applyReceipt()), actor: executor)
        var selfVerified = verificationReceipt()
        selfVerified.verifier = executor
        XCTAssertEqual(
            rejection(state, .recordPostimageVerification(selfVerified), actor: executor),
            .invalidVerificationReceipt
        )

        state = try advance(
            state,
            .recordPostimageVerification(verificationReceipt()),
            actor: verifier
        )
        var selfReviewed = acceptanceReceipt()
        selfReviewed.reviewer = verifier
        XCTAssertEqual(
            rejection(state, .recordIndependentAcceptance(selfReviewed), actor: verifier),
            .reviewerNotIndependent
        )
    }

    func testTamperedRollbackAndPartialSuccessReceiptsAreRejected() throws {
        var state = try advance(nil, .propose(proposal()), actor: executor)
        var prepared = preflightAndRollback()
        prepared.1.restoresPreimageDigest = ContentDigest("other-preimage")
        XCTAssertEqual(
            rejection(
                state,
                .acceptPreflight(receipt: prepared.0, rollback: prepared.1),
                actor: executor
            ),
            .identityMismatch
        )

        prepared = preflightAndRollback()
        state = try advance(
            state,
            .acceptPreflight(receipt: prepared.0, rollback: prepared.1),
            actor: executor
        )
        state = try advance(state, .startApply(applyIntent()), actor: executor)
        var partial = applyReceipt()
        partial.appliedOperationCount = 0
        XCTAssertEqual(
            rejection(state, .recordApply(partial), actor: executor),
            .invalidApplyReceipt
        )
    }

    func testRunJournalReplaysIntegrationFramesAndRejectsScopeWidening() async throws {
        let registryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeIntegrationRegistry-\(UUID().uuidString)",
            isDirectory: true
        )
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeIntegrationWorkspace-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let registry = try WorkspaceMutationRecoveryRegistry(rootDirectory: registryRoot)
        let registration = try await registry.register(
            runID: runID,
            actorIdentity: executor,
            workspaceID: WorkspaceID("journal-workspace"),
            workspaceRoot: workspace,
            hostBudget: HostResourceBudget(nominal: .zero),
            maximumDispatchBatch: 4,
            registeredAt: Date(timeIntervalSince1970: 1)
        )
        let root = registration.journalRoot
        defer {
            let contentStoreRoot = registryRoot.appendingPathComponent(
                WorkspaceMutationContentObjectStore.directoryName,
                isDirectory: true
            )
            Self.makeTreeWritable(contentStoreRoot)
            try? FileManager.default.removeItem(at: registryRoot)
            try? FileManager.default.removeItem(at: workspace)
        }
        let verifierEvidence = String(repeating: "a", count: 64)
        let baselineBytes = Data("journal-owned baseline bytes".utf8)
        try baselineBytes.write(
            to: workspace.appendingPathComponent("file.txt")
        )
        var baselineRootIdentity = stat()
        XCTAssertEqual(lstat(workspace.path, &baselineRootIdentity), 0)
        let ratifiedBase = try WorkspaceSourceRevisionCollector().capture(
            workspaceID: WorkspaceID("journal-workspace"),
            root: workspace,
            excludedDirectoryNames: [],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 100,
                maximumTotalBytes: 1_024 * 1_024,
                maximumFileBytes: 1_024 * 1_024
            )
        )
        let candidateBytes = Data("journal-owned candidate bytes".utf8)
        try candidateBytes.write(
            to: workspace.appendingPathComponent("file.txt")
        )
        let candidatePostimage = try WorkspaceSourceRevisionCollector().capture(
            workspaceID: WorkspaceID("journal-workspace"),
            root: workspace,
            excludedDirectoryNames: [],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 100,
                maximumTotalBytes: 1_024 * 1_024,
                maximumFileBytes: 1_024 * 1_024
            )
        )
        let candidateDerivation = try WorkspaceMutationOperationDeriver().derive(
            base: ratifiedBase,
            candidate: candidatePostimage,
            requirementIDs: [RequirementID("requirement")],
            authorizedPaths: ["file.txt"]
        )
        let acceptedGeneration = candidatePostimage.sourceRevision
        var journalContract = contract()
        journalContract.workspaceBinding = TaskContractWorkspaceBinding(
            workspaceID: candidatePostimage.workspaceID,
            canonicalRootDigest: candidatePostimage.canonicalRootDigest
        )
        journalContract.sourceRevision = ratifiedBase
        let verifierExecutable = kernelProcessFixturePath
        let verifierExecutableDigest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: verifierExecutable
            )
        )
        let verificationProbe = RequirementVerificationExecutableProbe(
            schemaVersion: 2,
            transport: .localDirectProcess,
            executableContentDigest: verifierExecutableDigest,
            fixedArguments: [
                "--emit-verifier-result-and-sleep",
                "accepted",
                verifierEvidence,
                "3",
                "@loopforge-input:candidate"
            ],
            inputBindings: [RequirementVerificationInputBinding(
                id: "candidate",
                kind: .candidatePostimage,
                artifactID: "journal-owned-postimage",
                argumentToken: "@loopforge-input:candidate"
            )],
            environmentPolicy: .minimalKernelAllowlist,
            environmentIdentityDigest: KernelProcessEnvironmentAuthorizer
                .environmentDigest(
                    KernelProcessEnvironmentAuthorizer.minimalEnvironment
                ),
            captureIdentityDigest:
                KernelPostimageVerifierCapturePolicy.identityDigest,
            parser: RequirementVerificationParserContract(
                id: "integration-postimage-parser",
                schemaVersion: 1,
                contentDigest: RequirementVerificationParserFormat
                    .canonicalJSONResultV1.implementationIdentityDigest,
                format: .canonicalJSONResultV1
            ),
            resultMappings: [RequirementVerificationResultMapping(
                exitCode: 0,
                parserResultCode: "accepted",
                outcome: .accepted
            )],
            unmatchedOutcome: .rejected,
            networkPolicy: .disabled,
            resourceLimits: RequirementVerificationResourceLimits(
                maximumWallClockSeconds: 2,
                maximumCapturedOutputBytes: 64 * 1_024,
                maximumResidentBytes: 64 * 1_024 * 1_024,
                maximumChildProcesses: 0
            )
        )
        var successfulVerificationProbe = verificationProbe
        successfulVerificationProbe.fixedArguments = [
            "--emit-verifier-result-and-sleep",
            "accepted",
            verifierEvidence,
            "0",
            "@loopforge-input:candidate"
        ]
        var independentReviewProbe = successfulVerificationProbe
        independentReviewProbe.fixedArguments.append(
            "@loopforge-input:reviewed-evidence"
        )
        independentReviewProbe.inputBindings.append(
            RequirementVerificationInputBinding(
                id: "reviewed-evidence",
                kind: .verificationEvidenceDigest,
                artifactID: "journaled-v2-verification",
                argumentToken: "@loopforge-input:reviewed-evidence"
            )
        )
        journalContract.requirements[0].evidenceRecipeIDs.insert(
            EvidenceRecipeID("recipe-natural-exit")
        )
        journalContract.requirements[0].evidenceRecipeIDs.insert(
            EvidenceRecipeID("recipe-independent-review")
        )
        journalContract.requirements[0].evidenceRecipeIDs.insert(
            EvidenceRecipeID("recipe-containment-veto")
        )
        journalContract.requirements[0].evidenceRecipeIDs.insert(
            EvidenceRecipeID("recipe-cross-wired-memory")
        )
        journalContract.requirementEvidenceRecipes = [RequirementEvidenceRecipe(
            id: EvidenceRecipeID("recipe"),
            requirementID: RequirementID("requirement"),
            verifierKind: .deterministic,
            expectedObservation: "The exact applied postimage passes.",
            requiresIndependentLineage: true,
            executableProbe: verificationProbe
        ), RequirementEvidenceRecipe(
            id: EvidenceRecipeID("recipe-natural-exit"),
            requirementID: RequirementID("requirement"),
            verifierKind: .deterministic,
            expectedObservation:
                "The exact applied postimage exits naturally and passes.",
            requiresIndependentLineage: true,
            executableProbe: successfulVerificationProbe
        ), RequirementEvidenceRecipe(
            id: EvidenceRecipeID("recipe-containment-veto"),
            requirementID: RequirementID("requirement"),
            verifierKind: .deterministic,
            expectedObservation:
                "The exact applied postimage remains inside its memory ceiling.",
            requiresIndependentLineage: true,
            executableProbe: successfulVerificationProbe
        ), RequirementEvidenceRecipe(
            id: EvidenceRecipeID("recipe-cross-wired-memory"),
            requirementID: RequirementID("requirement"),
            verifierKind: .deterministic,
            expectedObservation:
                "Resident-memory authority binds one exact activation.",
            requiresIndependentLineage: true,
            executableProbe: successfulVerificationProbe
        ), RequirementEvidenceRecipe(
            id: EvidenceRecipeID("recipe-independent-review"),
            requirementID: RequirementID("requirement"),
            verifierKind: .adversarial,
            expectedObservation:
                "A distinct reviewer approves the exact v2 evidence batch.",
            requiresIndependentLineage: true,
            executableProbe: independentReviewProbe
        )]
        var commandIndex = 0
        let journal = try RunJournal(rootDirectory: root, runID: runID)

        let baselineObject = WorkspaceMutationContentObject(
            digest: WorkspaceMutationFilesystemExecutor.contentDigest(baselineBytes),
            data: baselineBytes
        )
        let baselineReferences = [WorkspaceMutationContentReference(
            contentDigest: baselineObject.digest,
            size: UInt64(baselineBytes.count)
        )]
        var baselineCaptureReceipt = WorkspaceRatifiedBaselineContentCaptureReceipt(
            schemaVersion: 1,
            runID: runID,
            contractID: journalContract.id,
            ratificationReceiptID: ReceiptID("journal-ratification"),
            enrollmentJournalFrameDigest:
                HeavyEvidenceCache.sha256("journal-enrollment-frame"),
            workspaceID: ratifiedBase.workspaceID,
            canonicalRootDigest: ratifiedBase.canonicalRootDigest,
            captureActor: executor,
            capturedAt: Date(timeIntervalSince1970: 1.5),
            derivationDigest: candidateDerivation.derivationDigest,
            baseSourceRevision: ratifiedBase.sourceRevision,
            capturePolicyDigest: ratifiedBase.capturePolicyDigest,
            contentObjects: baselineReferences,
            objectSetDigest: WorkspaceMutationFilesystemExecutor.objectSetDigest([
                baselineObject
            ]),
            objectCount: 1,
            totalBytes: UInt64(baselineBytes.count),
            rootDeviceID: UInt64(baselineRootIdentity.st_dev),
            rootInode: UInt64(baselineRootIdentity.st_ino),
            receiptDigest: ContentDigest("")
        )
        baselineCaptureReceipt.receiptDigest = try XCTUnwrap(
            WorkspaceRatifiedBaselineContentCaptureReceipt.digest(
                for: baselineCaptureReceipt
            )
        )
        let baselineContent = AuthorizedWorkspaceRatifiedBaselineContent.testOnly(
            receipt: baselineCaptureReceipt,
            objects: [baselineObject]
        )

        func transact(_ command: RunCommand, actor: ActorIdentity) async throws {
            commandIndex += 1
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: RunCommandID("command-\(commandIndex)"),
                issuedAt: Date(timeIntervalSince1970: TimeInterval(commandIndex)),
                actor: actor
            )
        }

        try await transact(.createRun(journalContract), actor: reviewer)
        let baselineCaptureTransaction = try await journal
            .recordRatifiedBaselineContentCapture(
                baselineContent,
                commandID: RunCommandID("baseline-content-capture")
            )
        XCTAssertFalse(baselineCaptureTransaction.duplicate)
        try await transact(.proposePlan(KernelPlanProposal(
            contractDigest: ContentDigest("contract"),
            nodes: [node()]
        )), actor: reviewer)
        try await transact(.authorizeNode(nodeID), actor: reviewer)
        try await transact(.initializeConvergence(
            epochID: "integration-epoch",
            budget: convergenceBudget()
        ), actor: reviewer)
        try await transact(.admitCausalAttempt(causalAdmission()), actor: reviewer)
        try await transact(.startAttempt(
            attemptID: attemptID,
            nodeID: nodeID,
            requirementIDs: [RequirementID("requirement")],
            strategyFingerprint: causalStrategy().fingerprint
        ), actor: executor)
        try await journalTestWorkerDisposition(
            journal,
            runID: runID,
            attemptID: attemptID,
            actor: executor,
            prefix: "integration-generation"
        )
        try await transact(.testOnlyRecordVerification(VerificationReceipt(
            id: ReceiptID("candidate-verification"),
            attemptID: attemptID,
            requirementIDs: [RequirementID("requirement")],
            sourceRevision: acceptedGeneration,
            environmentDigest: ContentDigest("environment"),
            oracleDigest: ContentDigest("oracle"),
            result: .accepted
        )), actor: verifier)
        try await transact(.testOnlyRecordReview(IndependentReviewReceipt(
            id: ReceiptID("candidate-review"),
            attemptID: attemptID,
            requirementIDs: [RequirementID("requirement")],
            reviewer: reviewer,
            evidenceDigest: ContentDigest("review-evidence"),
            sourceRevision: acceptedGeneration,
            decision: .approveCandidate
        )), actor: reviewer)
        var journalProposal = proposal()
        journalProposal.expectedPostimageDigest = acceptedGeneration
        try await transact(.testOnlyAdvanceIntegration(.propose(journalProposal)), actor: executor)

        var widened = preflightAndRollback().0
        widened.affectedPaths = ["other.txt"]
        do {
            try await transact(.testOnlyAdvanceIntegration(.acceptPreflight(
                receipt: widened,
                rollback: preflightAndRollback().1
            )), actor: executor)
            XCTFail("Expected scope widening rejection")
        } catch RunJournalError.reducerRejected(
            .invalidIntegrationTransition(.identityMismatch)
        ) {}

        var prepared = preflightAndRollback()
        prepared.1.expectedAppliedPostimageDigest = acceptedGeneration
        prepared.0.rollbackManifestDigest = TransactionalMutationKernel.rollbackDigest(prepared.1)
        try await transact(.testOnlyAdvanceIntegration(.acceptPreflight(
            receipt: prepared.0,
            rollback: prepared.1
        )), actor: executor)
        var journalApplyIntent = applyIntent()
        journalApplyIntent.rollbackManifestDigest = prepared.0.rollbackManifestDigest
        journalApplyIntent.candidatePostimageCapturePolicyDigest =
            candidatePostimage.capturePolicyDigest
        try await transact(
            .testOnlyAdvanceIntegration(.startApply(journalApplyIntent)),
            actor: executor
        )
        let inFlight = try await journal.latestAcceptedWorkspaceTreeGenerationReceipt(
            workspaceID: WorkspaceID("journal-workspace"),
            root: workspace
        )
        guard case .ambiguousLatestTransition = inFlight else {
            return XCTFail("an in-flight effect without a recorded outcome must withhold authority")
        }
        let inFlightAttestation = try await journal
            .latestAcceptedWorkspaceCandidatePostimageAttestation(
                workspaceID: WorkspaceID("journal-workspace"),
                root: workspace
            )
        guard case .ambiguousLatestTransition = inFlightAttestation else {
            return XCTFail("an in-flight effect must withhold candidate attestation")
        }
        var exactApply = applyReceipt()
        exactApply.intentID = journalApplyIntent.id
        exactApply.observedPostimageDigest = acceptedGeneration
        exactApply.candidatePostimage = candidatePostimage
        try await transact(.testOnlyAdvanceIntegration(.recordApply(exactApply)), actor: executor)

        let generation = try await journal.latestAcceptedWorkspaceTreeGenerationReceipt(
            workspaceID: WorkspaceID("journal-workspace"),
            root: workspace
        )
        guard case .accepted(let generationReceipt) = generation else {
            return XCTFail("the exact reducer-accepted postimage must issue tree authority")
        }
        XCTAssertEqual(generationReceipt.generationDigest, acceptedGeneration)
        XCTAssertEqual(generationReceipt.authority, .journaledMutationCommit)
        XCTAssertEqual(generationReceipt.journalTransaction.commandID, RunCommandID("command-13"))
        let attestation = try await journal
            .latestAcceptedWorkspaceCandidatePostimageAttestation(
                workspaceID: WorkspaceID("journal-workspace"),
                root: workspace
            )
        guard case .accepted(let attestationReceipt) = attestation else {
            return XCTFail("the exact reducer-accepted candidate tree must be attested")
        }
        XCTAssertEqual(attestationReceipt.applyReceiptID, exactApply.id)
        XCTAssertEqual(attestationReceipt.candidatePostimage, candidatePostimage)
        XCTAssertEqual(
            attestationReceipt.journalTransaction,
            generationReceipt.journalTransaction
        )
        let runDirectory = await journal.runDirectory
        let candidateInput = try WorkspaceCandidatePostimageMaterializer()
            .materialize(
                attestation: attestationReceipt,
                workspaceRoot: workspace,
                runDirectory: runDirectory
            )
        defer {
            _ = Darwin.chmod(
                URL(fileURLWithPath: candidateInput.receipt.snapshotRootPath)
                    .appendingPathComponent("file.txt").path,
                0o600
            )
            _ = Darwin.chmod(candidateInput.receipt.snapshotRootPath, 0o700)
        }
        let captureTime = Date(timeIntervalSince1970: 13.5)
        let candidateCaptureIssuer =
            WorkspaceJournaledCandidateContentCaptureIssuer(
                journal: journal,
                wallClock: { captureTime }
            )
        let candidateContent = try await candidateCaptureIssuer.capture(
            derivation: candidateDerivation,
            input: candidateInput
        )
        XCTAssertEqual(candidateContent.objects.map(\.data), [candidateBytes])
        XCTAssertEqual(candidateContent.receipt.captureActor, executor)
        XCTAssertEqual(
            candidateContent.receipt.applyJournalFrameDigest,
            attestationReceipt.journalTransaction.frameDigest
        )
        let beforeMalformedCapture = await journal.headSnapshot()
        let malformedCandidateContent =
            AuthorizedWorkspaceJournaledCandidateContent.testOnly(
                receipt: candidateContent.receipt,
                objects: [],
                attestation: attestationReceipt
            )
        do {
            _ = try await journal.recordJournaledCandidateContentCapture(
                malformedCandidateContent,
                commandID: RunCommandID("candidate-content-malformed")
            )
            XCTFail("candidate bytes that do not match the receipt must be rejected")
        } catch RunJournalError.reducerRejected(
            .invalidCandidateContentCapture(
                "the live candidate-content capability does not match its receipt"
            )
        ) {}
        let afterMalformedCapture = await journal.headSnapshot()
        XCTAssertEqual(afterMalformedCapture, beforeMalformedCapture)
        let substitutedAttestation = try
            WorkspaceCandidatePostimageAttestationReceipt.testOnlyAccepted(
                integrationTransactionID:
                    IntegrationTransactionID("substituted-integration"),
                workspaceID: candidatePostimage.workspaceID,
                root: workspace,
                candidatePostimage: candidatePostimage,
                applyReceiptID: exactApply.id,
                journalTransaction: attestationReceipt.journalTransaction
            )
        let crossWiredCandidateContent =
            AuthorizedWorkspaceJournaledCandidateContent.testOnly(
                receipt: candidateContent.receipt,
                objects: candidateContent.objects,
                attestation: substitutedAttestation
            )
        XCTAssertEqual(
            crossWiredCandidateContent.validationIssues(),
            ["candidate-content capability does not match its attestation"]
        )
        do {
            _ = try await journal.recordJournaledCandidateContentCapture(
                crossWiredCandidateContent,
                commandID: RunCommandID("candidate-content-cross-wire")
            )
            XCTFail("a receipt and attestation from different transactions must reject")
        } catch RunJournalError.candidateContentCaptureAuthorityStale {}
        let afterCrossWiredCapture = await journal.headSnapshot()
        XCTAssertEqual(afterCrossWiredCapture, beforeMalformedCapture)
        let candidateCaptureTransaction = try await journal
            .recordJournaledCandidateContentCapture(
                candidateContent,
                commandID: RunCommandID("candidate-content-capture")
            )
        XCTAssertFalse(candidateCaptureTransaction.duplicate)
        let duplicateCandidateCapture = try await journal
            .recordJournaledCandidateContentCapture(
                candidateContent,
                commandID: RunCommandID("candidate-content-capture")
            )
        XCTAssertTrue(duplicateCandidateCapture.duplicate)
        let journaledCandidateContent = await journal
            .journaledCandidateContentCaptureReceipt(
                transaction: candidateCaptureTransaction
            )
        XCTAssertEqual(journaledCandidateContent, candidateContent.receipt)
        let compositionIssuer =
            WorkspaceJournaledMutationContentCompositionIssuer(journal: journal)
        let composedContent = try await compositionIssuer.compose(
            derivation: candidateDerivation,
            baseline: baselineContent,
            candidate: candidateContent
        )
        XCTAssertTrue(composedContent.validationIssues().isEmpty)
        XCTAssertEqual(
            Set(composedContent.objects.map(\.data)),
            Set([baselineBytes, candidateBytes])
        )
        XCTAssertEqual(
            composedContent.receipt.baselineCaptureReceiptDigest,
            baselineContent.receipt.receiptDigest
        )
        XCTAssertEqual(
            composedContent.receipt.candidateCaptureReceiptDigest,
            candidateContent.receipt.receiptDigest
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                WorkspaceJournaledMutationContentCompositionReceipt.self,
                from: JSONEncoder().encode(composedContent.receipt)
            ),
            composedContent.receipt
        )
        let contentStoreTime = Date(timeIntervalSince1970: 13.75)
        let contentStoreCoordinator =
            WorkspaceJournaledMutationContentStoreCoordinator(
                journal: journal,
                wallClock: { contentStoreTime }
            )
        let contentStoreInstallation = try await contentStoreCoordinator.install(
            composition: composedContent,
            workspaceRoot: workspace,
            storageRoot: registryRoot,
            commandID: RunCommandID("journaled-mutation-content-store")
        )
        XCTAssertFalse(contentStoreInstallation.journalTransaction.duplicate)
        XCTAssertTrue(
            contentStoreInstallation.authority.validationIssues().isEmpty
        )
        XCTAssertEqual(
            contentStoreInstallation.authority.receipt.compositionReceipt,
            composedContent.receipt
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                WorkspaceJournaledMutationContentStoreReceipt.self,
                from: JSONEncoder().encode(
                    contentStoreInstallation.authority.receipt
                )
            ),
            contentStoreInstallation.authority.receipt
        )
        let retainedContentStore = await journal
            .journaledMutationContentStoreReceipt(
                transaction: contentStoreInstallation.journalTransaction
            )
        XCTAssertEqual(
            retainedContentStore,
            contentStoreInstallation.authority.receipt
        )
        let duplicateContentStore = try await contentStoreCoordinator.install(
            composition: composedContent,
            workspaceRoot: workspace,
            storageRoot: registryRoot,
            commandID: RunCommandID("journaled-mutation-content-store")
        )
        XCTAssertTrue(duplicateContentStore.journalTransaction.duplicate)
        XCTAssertEqual(
            duplicateContentStore.authority.receipt,
            contentStoreInstallation.authority.receipt
        )
        let beforeSubstitutedStore = await journal.headSnapshot()
        var substitutedStoreReceipt = contentStoreInstallation.authority.receipt
        substitutedStoreReceipt.compositionReceipt.candidateCaptureReceiptDigest =
            HeavyEvidenceCache.sha256("substituted-candidate-capture")
        substitutedStoreReceipt.compositionReceipt.compositionDigest = try XCTUnwrap(
            WorkspaceJournaledMutationContentCompositionReceipt.digest(
                for: substitutedStoreReceipt.compositionReceipt
            )
        )
        substitutedStoreReceipt.receiptDigest = try XCTUnwrap(
            WorkspaceJournaledMutationContentStoreReceipt.digest(
                for: substitutedStoreReceipt
            )
        )
        let substitutedStore =
            AuthorizedWorkspaceJournaledMutationContentStore.testOnly(
                receipt: substitutedStoreReceipt,
                composition: composedContent
            )
        do {
            _ = try await journal.recordJournaledMutationContentStore(
                substitutedStore,
                commandID: RunCommandID("substituted-mutation-content-store")
            )
            XCTFail("a store receipt substituted onto another composition must reject")
        } catch RunJournalError.reducerRejected(
            .invalidMutationContentStore(
                "the live mutation-content-store capability does not match its receipt"
            )
        ) {}
        let afterSubstitutedStore = await journal.headSnapshot()
        XCTAssertEqual(afterSubstitutedStore, beforeSubstitutedStore)
        var unacceptedBaselineReceipt = baselineContent.receipt
        unacceptedBaselineReceipt.rootInode += 1
        unacceptedBaselineReceipt.receiptDigest = try XCTUnwrap(
            WorkspaceRatifiedBaselineContentCaptureReceipt.digest(
                for: unacceptedBaselineReceipt
            )
        )
        let unacceptedBaseline =
            AuthorizedWorkspaceRatifiedBaselineContent.testOnly(
                receipt: unacceptedBaselineReceipt,
                objects: baselineContent.objects
            )
        do {
            _ = try await compositionIssuer.compose(
                derivation: candidateDerivation,
                baseline: unacceptedBaseline,
                candidate: candidateContent
            )
            XCTFail("a substituted baseline receipt must not compose")
        } catch WorkspaceJournaledMutationContentCompositionError
            .baselineReceiptNotAccepted {}
        let conflictingContent = try await
            WorkspaceJournaledCandidateContentCaptureIssuer(
                journal: journal,
                wallClock: { captureTime.addingTimeInterval(1) }
            ).capture(
                derivation: candidateDerivation,
                input: candidateInput
            )
        do {
            _ = try await journal.recordJournaledCandidateContentCapture(
                conflictingContent,
                commandID: RunCommandID("candidate-content-capture")
            )
            XCTFail("the same command must not resolve to different capture content")
        } catch RunJournalError.candidateContentCaptureCommandConflict(
            commandID: RunCommandID("candidate-content-capture")
        ) {}
        let activationCoordinator = KernelPostimageVerifierActivationCoordinator(
            journal: journal
        )
        let baseActivation = KernelPostimageVerifierActivationRequest(
            workspaceRoot: workspace,
            integrationTransactionID: transactionID,
            evidenceRecipeID: EvidenceRecipeID("recipe"),
            verifier: verifier,
            candidateInput: candidateInput,
            receiptID: ReceiptID("postimage-verifier-activation"),
            commandID: RunCommandID("postimage-verifier-activation-command"),
            activatedAt: Date(timeIntervalSince1970: 14)
        )
        do {
            _ = try await activationCoordinator.activate(baseActivation)
            XCTFail("activation must not import a caller-path executable")
        } catch KernelPostimageVerifierActivationError
            .stagedExecutableResolutionFailed {}
        _ = try KernelExecutableStager().stage(
            executablePath: verifierExecutable,
            expectedDigest: verifierExecutableDigest,
            runDirectory: runDirectory
        )
        var selfActivation = baseActivation
        selfActivation.verifier = executor
        do {
            _ = try await activationCoordinator.activate(selfActivation)
            XCTFail("the apply executor must not activate as postimage verifier")
        } catch KernelPostimageVerifierActivationError.verifierNotIndependent {}

        let activated = try await activationCoordinator.activate(baseActivation)
        XCTAssertEqual(activated.receipt.verifier, verifier)
        XCTAssertEqual(activated.receipt.applyReceiptID, exactApply.id)
        XCTAssertEqual(
            activated.receipt.sourceRevision,
            candidatePostimage.sourceRevision
        )
        XCTAssertEqual(
            activated.receipt.resolvedArguments,
            [
                "--emit-verifier-result-and-sleep",
                "accepted",
                verifierEvidence,
                "3",
                KernelPostimageVerifierActivationCompiler
                    .candidateInputDescriptorPath
            ]
        )
        XCTAssertEqual(
            activated.receipt.executableStaging.contentDigest,
            verifierExecutableDigest
        )
        let journaledActivation = await journal
            .postimageVerifierActivationReceipt(
                transaction: activated.activationTransaction
            )
        XCTAssertEqual(journaledActivation, activated.receipt)
        let activatedState = await journal.state
        XCTAssertNil(activatedState.verificationReceipts[activated.receipt.id])
        XCTAssertEqual(
            activatedState.integrationTransactions[transactionID]?.phase,
            .appliedUnverified
        )
        do {
            var duplicate = baseActivation
            duplicate.receiptID = ReceiptID("duplicate-postimage-activation")
            duplicate.commandID = RunCommandID("duplicate-postimage-activation-command")
            _ = try await activationCoordinator.activate(duplicate)
            XCTFail("one recipe must not activate twice for the same apply")
        } catch KernelPostimageVerifierActivationError.invalidRunState {}

        var vetoActivationRequest = baseActivation
        vetoActivationRequest.evidenceRecipeID = EvidenceRecipeID(
            "recipe-containment-veto"
        )
        vetoActivationRequest.receiptID = ReceiptID(
            "vetoed-postimage-verifier-activation"
        )
        vetoActivationRequest.commandID = RunCommandID(
            "vetoed-postimage-verifier-activation"
        )
        let vetoedActivation = try await activationCoordinator.activate(
            vetoActivationRequest
        )

        let verifierSupervisor = RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 4,
                memoryBytes: 128 * 1_024 * 1_024,
                diskIOWeight: 4,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 4
            )),
            pressure: .nominal
        )
        let unavailableVerifierRuntime = JournaledProcessRuntime(
            supervisor: verifierSupervisor,
            journal: journal,
            actorIdentity: verifier
        )
        let verifierRuntimeRequest = KernelPostimageVerifierRuntimeRequest(
                    leaseID: ResourceLeaseID("postimage-verifier-lease"),
                    resourceID: OwnedResourceID("postimage-verifier-process"),
                    standardOutputFileName: "postimage-verifier.stdout",
                    standardErrorFileName: "postimage-verifier.stderr",
                    admissionReceiptID: ReceiptID("postimage-verifier-admission"),
                    admissionCommandID: RunCommandID("postimage-verifier-admit"),
                    bindingReceiptID: ReceiptID("postimage-verifier-binding"),
                    launchReceiptID: ReceiptID("postimage-verifier-launch"),
                    bindingCommandID: RunCommandID("postimage-verifier-bind"),
                    launchFailureReleaseReceiptID:
                        ReceiptID("postimage-verifier-launch-failure-release"),
                    launchFailureReleaseCommandID:
                        RunCommandID("postimage-verifier-launch-failure-release"),
                    launchVetoReceiptID:
                        ReceiptID("postimage-verifier-launch-veto"),
                    launchVetoCommandID:
                        RunCommandID("postimage-verifier-launch-veto")
                )
        do {
            _ = try await unavailableVerifierRuntime
                .admitAndLaunchPostimageVerifier(
                    invocation: vetoedActivation,
                    request: verifierRuntimeRequest
                )
            XCTFail("production launch must require resident-memory authority")
        } catch JournaledProcessRuntimeError
                    .residentMemoryEnforcementUnavailable {}
        let unavailableLease = await journal.runtimeLease(
            resourceID: verifierRuntimeRequest.resourceID
        )
        XCTAssertNil(unavailableLease)
        let recordedLaunchVeto = await journal
            .postimageVerifierLaunchVetoReceipt(
                receiptID: verifierRuntimeRequest.launchVetoReceiptID
            )
        let launchVeto = try XCTUnwrap(
            recordedLaunchVeto
        )
        XCTAssertEqual(
            launchVeto.activationReceiptID,
            vetoedActivation.receipt.id
        )
        XCTAssertEqual(
            launchVeto.requiredMaximumResidentBytes,
            vetoedActivation.receipt.resourceLimits.maximumResidentBytes
        )
        XCTAssertEqual(
            launchVeto.reason,
            .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
        )
        XCTAssertNotEqual(
            vetoedActivation.receipt.id,
            activated.receipt.id
        )
        let stateAfterLaunchVeto = await journal.state
        XCTAssertEqual(
            stateAfterLaunchVeto.postimageVerifierActivationReceipts?[
                activated.receipt.id
            ],
            activated.receipt
        )
        XCTAssertFalse(
            (stateAfterLaunchVeto.postimageVerifierLaunchVetoReceipts ?? [:])
                .values.contains(where: {
                    $0.activationReceiptID == activated.receipt.id
                })
        )
        let vetoedVerifierRuntime = JournaledProcessRuntime(
            supervisor: verifierSupervisor,
            journal: journal,
            actorIdentity: verifier,
            residentMemoryEnforcement: .testOnly(
                activation: vetoedActivation.receipt
            )
        )
        do {
            _ = try await vetoedVerifierRuntime
                .admitAndLaunchPostimageVerifier(
                    invocation: vetoedActivation,
                    request: verifierRuntimeRequest
                )
            XCTFail("a durable containment veto must retire its activation")
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}
        let leaseAfterRetiredVeto = await journal.runtimeLease(
            resourceID: verifierRuntimeRequest.resourceID
        )
        XCTAssertNil(leaseAfterRetiredVeto)
        let verifierRuntime = JournaledProcessRuntime(
            supervisor: verifierSupervisor,
            journal: journal,
            actorIdentity: verifier,
            residentMemoryEnforcement: .testOnly(
                activation: activated.receipt
            )
        )
        let wrongVerifierRuntime = JournaledProcessRuntime(
            supervisor: verifierSupervisor,
            journal: journal,
            actorIdentity: executor
        )
        do {
            _ = try await wrongVerifierRuntime.admitAndLaunchPostimageVerifier(
                invocation: activated,
                request: verifierRuntimeRequest
            )
            XCTFail("a different actor must not consume verifier authority")
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}
        let verifierStart = try await verifierRuntime
            .admitAndLaunchPostimageVerifier(
                invocation: activated,
                request: verifierRuntimeRequest
            )
        XCTAssertEqual(
            verifierStart.verifierLaunch.activationReceiptID,
            activated.receipt.id
        )
        XCTAssertEqual(
            verifierStart.launch.handle.externalIdentity
                .executableContentDigest,
            verifierExecutableDigest
        )
        XCTAssertEqual(
            verifierStart.launch.handle.externalIdentity
                .argumentVectorContentDigest,
            activated.receipt.argumentVectorDigest
        )
        XCTAssertEqual(
            verifierStart.launch.nativeSandbox.authorization.sandbox,
            .readOnly
        )
        XCTAssertEqual(
            verifierStart.launch.nativeSandbox.authorization.networkPolicy,
            .disabled
        )
        XCTAssertNil(
            verifierStart.launch.processIOFiles?.standardInputFileName
        )
        let journaledVerifierLaunch = await journal
            .postimageVerifierLaunchReceipt(
                transaction: verifierStart.launch.journalTransaction
            )
        XCTAssertEqual(journaledVerifierLaunch, verifierStart.verifierLaunch)
        let launchedState = await journal.state
        XCTAssertNil(
            launchedState.verificationReceipts[
                verifierStart.verifierLaunch.id
            ]
        )
        XCTAssertEqual(
            launchedState.integrationTransactions[transactionID]?.phase,
            .appliedUnverified
        )
        let preCompletionJournalSnapshot = FileManager.default
            .temporaryDirectory.appendingPathComponent(
                "LoopForgeVerifierCrashSnapshot-\(UUID().uuidString)",
                isDirectory: true
        )
        defer {
            if let subpaths = try? FileManager.default.subpathsOfDirectory(
                atPath: preCompletionJournalSnapshot.path
            ) {
                for relativePath in subpaths {
                    _ = Darwin.chmod(
                        preCompletionJournalSnapshot.appendingPathComponent(
                            relativePath
                        ).path,
                        0o700
                    )
                }
            }
            _ = Darwin.chmod(preCompletionJournalSnapshot.path, 0o700)
            try? FileManager.default.removeItem(
                at: preCompletionJournalSnapshot
            )
        }
        try FileManager.default.copyItem(
            at: root,
            to: preCompletionJournalSnapshot
        )
        let verifierCompletion = try await verifierRuntime
            .completePostimageVerifier(
                launchReceiptID: verifierStart.verifierLaunch.id,
                request: KernelPostimageVerifierCompletionRequest(
                    releaseReceiptID: ReceiptID("postimage-verifier-release"),
                    releaseCommandID: RunCommandID("postimage-verifier-release")
                )
            )
        XCTAssertEqual(
            verifierCompletion.containment.disposition,
            .wallClockExceeded
        )
        XCTAssertNil(verifierCompletion.naturalExit)
        let verifierTermination = try XCTUnwrap(verifierCompletion.termination)
        XCTAssertTrue(
            verifierTermination.exit.exitCode != nil
                || verifierTermination.exit.terminationSignal != nil
        )
        XCTAssertEqual(
            verifierCompletion.containment.maximumOutputFileBytes,
            verificationProbe.resourceLimits.maximumCapturedOutputBytes / 2
        )
        XCTAssertEqual(verifierCompletion.containment.schemaVersion, 4)
        let liveParse = try XCTUnwrap(
            verifierCompletion.containment.resultParse
        )
        XCTAssertEqual(liveParse.resultCode, "accepted")
        XCTAssertEqual(
            liveParse.evidenceDigest,
            ContentDigest(verifierEvidence)
        )
        XCTAssertEqual(
            verifierCompletion.containment.standardOutput?.contentDigest,
            liveParse.standardOutputContentDigest
        )
        XCTAssertGreaterThan(
            verifierCompletion.containment.standardOutput?.byteCount ?? 0,
            0
        )
        XCTAssertEqual(
            verifierCompletion.containment.standardError?.byteCount,
            0
        )
        XCTAssertNil(verifierCompletion.containment.failureReasonDigest)
        XCTAssertNil(
            verifierCompletion.containment.resultParseFailureDigest
        )
        XCTAssertNil(verifierCompletion.containment.resultMapping)
        XCTAssertEqual(
            verifierCompletion.containment
                .resultMappingFailureDigest?.rawValue.utf8.count,
            64
        )
        XCTAssertNil(verifierCompletion.containment.postimageResult)
        XCTAssertEqual(
            verifierCompletion.containment
                .postimageResultFailureDigest?.rawValue.utf8.count,
            64
        )
        XCTAssertNil(verifierCompletion.authorizedResult)
        XCTAssertEqual(
            verifierCompletion.release.postimageVerifierContainment,
            verifierCompletion.containment
        )
        var missingContainment = verifierCompletion.release
        missingContainment.postimageVerifierContainment = nil
        XCTAssertEqual(
            RunReducer.handle(
                state: launchedState,
                command: .testOnlyRecordRuntimeRelease(missingContainment),
                context: KernelCommandContext(
                    commandID: RunCommandID("missing-verifier-containment"),
                    expectedSequence: launchedState.sequence,
                    issuedAt: missingContainment.observedAt,
                    actor: verifier
                )
            ),
            .rejected(.invalidRuntimeReceipt(
                "postimage verifier release lacks exact containment"
            ))
        )
        var tamperedResult = verifierCompletion.release
        tamperedResult.postimageVerifierContainment?
            .resultParse?.resultCode = "rejected"
        XCTAssertEqual(
            RunReducer.handle(
                state: launchedState,
                command: .testOnlyRecordRuntimeRelease(tamperedResult),
                context: KernelCommandContext(
                    commandID: RunCommandID("tampered-verifier-result"),
                    expectedSequence: launchedState.sequence,
                    issuedAt: tamperedResult.observedAt,
                    actor: verifier
                )
            ),
            .rejected(.invalidRuntimeReceipt(
                "postimage verifier release lacks exact containment"
            ))
        )
        var timeoutMapping = verifierCompletion.release
        timeoutMapping.postimageVerifierContainment?.resultMapping =
            KernelPostimageVerifierResultMapper.expectedReceipt(
                probe: verificationProbe,
                nativeExitCode: 0,
                parse: liveParse
            )
        timeoutMapping.postimageVerifierContainment?
            .resultMappingFailureDigest = nil
        XCTAssertEqual(
            RunReducer.handle(
                state: launchedState,
                command: .testOnlyRecordRuntimeRelease(timeoutMapping),
                context: KernelCommandContext(
                    commandID: RunCommandID("timeout-mapping-smuggle"),
                    expectedSequence: launchedState.sequence,
                    issuedAt: timeoutMapping.observedAt,
                    actor: verifier
                )
            ),
            .rejected(.invalidRuntimeReceipt(
                "postimage verifier release lacks exact containment"
            ))
        )
        var timeoutResult = verifierCompletion.release
        timeoutResult.postimageVerifierContainment?.postimageResult =
            KernelPostimageVerifierResultAuthority.expectedReceipt(
                activation: activated.receipt,
                launch: verifierStart.verifierLaunch,
                releaseReceiptID: verifierCompletion.release.id,
                standardOutput: try XCTUnwrap(
                    verifierCompletion.containment.standardOutput
                ),
                standardError: try XCTUnwrap(
                    verifierCompletion.containment.standardError
                ),
                parse: liveParse,
                mapping: try XCTUnwrap(
                    KernelPostimageVerifierResultMapper.expectedReceipt(
                        probe: verificationProbe,
                        nativeExitCode: 0,
                        parse: liveParse
                    )
                ),
                completedAt: verifierCompletion.containment.observedAt
            )
        timeoutResult.postimageVerifierContainment?
            .postimageResultFailureDigest = nil
        XCTAssertEqual(
            RunReducer.handle(
                state: launchedState,
                command: .testOnlyRecordRuntimeRelease(timeoutResult),
                context: KernelCommandContext(
                    commandID: RunCommandID("timeout-result-smuggle"),
                    expectedSequence: launchedState.sequence,
                    issuedAt: timeoutResult.observedAt,
                    actor: verifier
                )
            ),
            .rejected(.invalidRuntimeReceipt(
                "postimage verifier release lacks exact containment"
            ))
        )
        var tamperedContainment = verifierCompletion.release
            .postimageVerifierContainment
        tamperedContainment?.maximumOutputFileBytes += 1
        var tamperedRelease = verifierCompletion.release
        tamperedRelease.postimageVerifierContainment = tamperedContainment
        XCTAssertEqual(
            RunReducer.handle(
                state: launchedState,
                command: .testOnlyRecordRuntimeRelease(tamperedRelease),
                context: KernelCommandContext(
                    commandID: RunCommandID("tampered-verifier-containment"),
                    expectedSequence: launchedState.sequence,
                    issuedAt: tamperedRelease.observedAt,
                    actor: verifier
                )
            ),
            .rejected(.invalidRuntimeReceipt(
                "postimage verifier release lacks exact containment"
            ))
        )
        let verifierProjection = await verifierRuntime.projection()
        XCTAssertTrue(verifierProjection.adapter.liveHandles.isEmpty)
        XCTAssertTrue(verifierProjection.inDoubtResourceIDs.isEmpty)
        do {
            var duplicateLaunchRequest = verifierRuntimeRequest
            duplicateLaunchRequest.leaseID =
                ResourceLeaseID("duplicate-postimage-verifier-lease")
            duplicateLaunchRequest.resourceID =
                OwnedResourceID("duplicate-postimage-verifier-process")
            duplicateLaunchRequest.admissionReceiptID =
                ReceiptID("duplicate-postimage-verifier-admission")
            duplicateLaunchRequest.admissionCommandID =
                RunCommandID("duplicate-postimage-verifier-admit")
            duplicateLaunchRequest.bindingReceiptID =
                ReceiptID("duplicate-postimage-verifier-binding")
            duplicateLaunchRequest.launchReceiptID =
                ReceiptID("duplicate-postimage-verifier-launch")
            duplicateLaunchRequest.bindingCommandID =
                RunCommandID("duplicate-postimage-verifier-bind")
            _ = try await verifierRuntime.admitAndLaunchPostimageVerifier(
                invocation: activated,
                request: duplicateLaunchRequest
            )
            XCTFail("one activation must not launch twice")
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}

        let naturalActivation = try await activationCoordinator.activate(
            KernelPostimageVerifierActivationRequest(
                workspaceRoot: workspace,
                integrationTransactionID: transactionID,
                evidenceRecipeID: EvidenceRecipeID("recipe-natural-exit"),
                verifier: verifier,
                candidateInput: candidateInput,
                receiptID: ReceiptID("natural-postimage-verifier-activation"),
                commandID:
                    RunCommandID("natural-postimage-verifier-activation"),
                activatedAt: Date()
            )
        )
        XCTAssertEqual(
            naturalActivation.receipt.resolvedArguments,
            [
                "--emit-verifier-result-and-sleep",
                "accepted",
                verifierEvidence,
                "0",
                KernelPostimageVerifierActivationCompiler
                    .candidateInputDescriptorPath
            ]
        )
        let crossWiredActivation = try await activationCoordinator.activate(
            KernelPostimageVerifierActivationRequest(
                workspaceRoot: workspace,
                integrationTransactionID: transactionID,
                evidenceRecipeID:
                    EvidenceRecipeID("recipe-cross-wired-memory"),
                verifier: verifier,
                candidateInput: candidateInput,
                receiptID: ReceiptID(
                    "cross-wired-memory-postimage-verifier-activation"
                ),
                commandID: RunCommandID(
                    "cross-wired-memory-postimage-verifier-activation"
                ),
                activatedAt: Date()
            )
        )
        do {
            _ = try await verifierRuntime.admitAndLaunchPostimageVerifier(
                invocation: crossWiredActivation,
                request: KernelPostimageVerifierRuntimeRequest(
                    leaseID: ResourceLeaseID("cross-wired-memory-lease"),
                    resourceID: OwnedResourceID("cross-wired-memory-process"),
                    standardOutputFileName: "cross-wired-memory.stdout",
                    standardErrorFileName: "cross-wired-memory.stderr",
                    admissionReceiptID: ReceiptID("cross-wired-memory-admission"),
                    admissionCommandID: RunCommandID("cross-wired-memory-admit"),
                    bindingReceiptID: ReceiptID("cross-wired-memory-binding"),
                    launchReceiptID: ReceiptID("cross-wired-memory-launch"),
                    bindingCommandID: RunCommandID("cross-wired-memory-bind"),
                    launchFailureReleaseReceiptID:
                        ReceiptID("cross-wired-memory-failure"),
                    launchFailureReleaseCommandID:
                        RunCommandID("cross-wired-memory-failure"),
                    launchVetoReceiptID:
                        ReceiptID("cross-wired-memory-veto"),
                    launchVetoCommandID:
                        RunCommandID("cross-wired-memory-veto")
                )
            )
            XCTFail("memory authority must bind one exact activation")
        } catch JournaledProcessRuntimeError
                    .residentMemoryEnforcementUnavailable {}
        let naturalRuntime = JournaledProcessRuntime(
            supervisor: verifierSupervisor,
            journal: journal,
            actorIdentity: verifier,
            residentMemoryEnforcement: .testOnly(
                activation: naturalActivation.receipt
            )
        )
        let naturalStart = try await naturalRuntime
            .admitAndLaunchPostimageVerifier(
                invocation: naturalActivation,
                request: KernelPostimageVerifierRuntimeRequest(
                    leaseID:
                        ResourceLeaseID("natural-postimage-verifier-lease"),
                    resourceID:
                        OwnedResourceID("natural-postimage-verifier-process"),
                    standardOutputFileName:
                        "natural-postimage-verifier.stdout",
                    standardErrorFileName:
                        "natural-postimage-verifier.stderr",
                    admissionReceiptID:
                        ReceiptID("natural-postimage-verifier-admission"),
                    admissionCommandID:
                        RunCommandID("natural-postimage-verifier-admit"),
                    bindingReceiptID:
                        ReceiptID("natural-postimage-verifier-binding"),
                    launchReceiptID:
                        ReceiptID("natural-postimage-verifier-launch"),
                    bindingCommandID:
                        RunCommandID("natural-postimage-verifier-bind"),
                    launchFailureReleaseReceiptID:
                        ReceiptID("natural-postimage-verifier-launch-failure"),
                    launchFailureReleaseCommandID:
                        RunCommandID("natural-postimage-verifier-launch-failure"),
                    launchVetoReceiptID:
                        ReceiptID("natural-postimage-verifier-launch-veto"),
                    launchVetoCommandID:
                        RunCommandID("natural-postimage-verifier-launch-veto")
                )
            )
        let naturalCompletion = try await naturalRuntime
            .completePostimageVerifier(
                launchReceiptID: naturalStart.verifierLaunch.id,
                request: KernelPostimageVerifierCompletionRequest(
                    releaseReceiptID:
                        ReceiptID("natural-postimage-verifier-release"),
                    releaseCommandID:
                        RunCommandID("natural-postimage-verifier-release")
                )
            )
        XCTAssertEqual(
            naturalCompletion.containment.disposition,
            .naturalExit
        )
        XCTAssertEqual(naturalCompletion.naturalExit?.exitCode, 0)
        XCTAssertNil(naturalCompletion.termination)
        XCTAssertEqual(naturalCompletion.containment.schemaVersion, 4)
        XCTAssertEqual(
            naturalCompletion.containment.resultParse?.resultCode,
            "accepted"
        )
        XCTAssertEqual(
            naturalCompletion.containment.resultMapping?.outcome,
            .accepted
        )
        XCTAssertNil(
            naturalCompletion.containment.resultMappingFailureDigest
        )
        let naturalResult = try XCTUnwrap(
            naturalCompletion.containment.postimageResult
        )
        XCTAssertEqual(naturalResult.outcome, .accepted)
        XCTAssertNil(
            naturalCompletion.containment.postimageResultFailureDigest
        )
        let naturalAuthorizedResult = try XCTUnwrap(
            naturalCompletion.authorizedResult
        )
        XCTAssertEqual(naturalAuthorizedResult.receipt, naturalResult)
        XCTAssertEqual(
            naturalAuthorizedResult.releaseTransaction,
            naturalCompletion.journalTransaction
        )
        let journaledNaturalRelease = await journal.runtimeReleaseReceipt(
            transaction: naturalAuthorizedResult.releaseTransaction
        )
        XCTAssertEqual(journaledNaturalRelease, naturalCompletion.release)
        let naturalState = await journal.state
        XCTAssertNil(naturalState.verificationReceipts[naturalResult.id])
        XCTAssertEqual(
            naturalState.integrationTransactions[transactionID]?.phase,
            .appliedUnverified
        )
        let journaledVerification = try await verifierRuntime
            .recordPostimageVerification(
                result: naturalAuthorizedResult,
                commandID: RunCommandID(
                    "natural-postimage-verification-record"
                )
            )
        XCTAssertEqual(
            journaledVerification.verification.result,
            .accepted
        )
        XCTAssertEqual(
            journaledVerification.verification.attemptID,
            naturalResult.attemptID
        )
        XCTAssertEqual(
            journaledVerification.verification.requirementIDs,
            naturalResult.requirementIDs
        )
        XCTAssertEqual(
            journaledVerification.verification.sourceRevision,
            naturalResult.sourceRevision
        )
        XCTAssertEqual(
            journaledVerification.verification.postimageEvidenceBatch?
                .postimageResultID,
            naturalResult.id
        )
        XCTAssertEqual(
            journaledVerification.verification.postimageEvidenceBatch?
                .postimageReleaseEndingSequence,
            naturalCompletion.journalTransaction.endingSequence
        )
        let exactJournaledVerification = await journal.verificationReceipt(
            transaction: journaledVerification.journalTransaction
        )
        XCTAssertEqual(
            exactJournaledVerification,
            journaledVerification.verification
        )
        let replayedVerification = try await verifierRuntime
            .recordPostimageVerification(
                result: naturalAuthorizedResult,
                commandID: RunCommandID(
                    "natural-postimage-verification-record"
                )
            )
        XCTAssertEqual(
            replayedVerification.verification,
            journaledVerification.verification
        )
        XCTAssertEqual(
            replayedVerification.journalTransaction,
            journaledVerification.journalTransaction
        )
        let verifiedNaturalState = await journal.state
        XCTAssertEqual(
            verifiedNaturalState.verificationReceipts[
                journaledVerification.verification.id
            ],
            journaledVerification.verification
        )
        XCTAssertEqual(
            verifiedNaturalState.integrationTransactions[transactionID]?.phase,
            .appliedUnverified
        )

        let independentReviewActivation = try await activationCoordinator
            .activate(KernelPostimageVerifierActivationRequest(
                workspaceRoot: workspace,
                integrationTransactionID: transactionID,
                evidenceRecipeID:
                    EvidenceRecipeID("recipe-independent-review"),
                verifier: reviewer,
                candidateInput: candidateInput,
                receiptID: ReceiptID("independent-review-activation"),
                commandID: RunCommandID("independent-review-activation"),
                activatedAt: Date(),
                reviewedVerificationReceiptID:
                    journaledVerification.verification.id
            ))
        let reviewedEvidenceDigest = try XCTUnwrap(
            journaledVerification.verification.postimageEvidenceBatch?
                .evidenceSetDigest
        )
        XCTAssertEqual(
            independentReviewActivation.receipt
                .reviewedVerificationEvidenceSetDigest,
            reviewedEvidenceDigest
        )
        XCTAssertEqual(
            independentReviewActivation.receipt.resolvedArguments,
            [
                "--emit-verifier-result-and-sleep",
                "accepted",
                verifierEvidence,
                "0",
                KernelPostimageVerifierActivationCompiler
                    .candidateInputDescriptorPath,
                reviewedEvidenceDigest.rawValue
            ]
        )
        let reviewRuntime = JournaledProcessRuntime(
            supervisor: verifierSupervisor,
            journal: journal,
            actorIdentity: reviewer,
            residentMemoryEnforcement: .testOnly(
                activation: independentReviewActivation.receipt
            )
        )
        let reviewStart = try await reviewRuntime
            .admitAndLaunchPostimageVerifier(
                invocation: independentReviewActivation,
                request: KernelPostimageVerifierRuntimeRequest(
                    leaseID: ResourceLeaseID("independent-review-lease"),
                    resourceID: OwnedResourceID("independent-review-process"),
                    standardOutputFileName: "independent-review.stdout",
                    standardErrorFileName: "independent-review.stderr",
                    admissionReceiptID:
                        ReceiptID("independent-review-admission"),
                    admissionCommandID:
                        RunCommandID("independent-review-admission"),
                    bindingReceiptID:
                        ReceiptID("independent-review-binding"),
                    launchReceiptID: ReceiptID("independent-review-launch"),
                    bindingCommandID:
                        RunCommandID("independent-review-binding"),
                    launchFailureReleaseReceiptID:
                        ReceiptID("independent-review-launch-failure"),
                    launchFailureReleaseCommandID:
                        RunCommandID("independent-review-launch-failure"),
                    launchVetoReceiptID:
                        ReceiptID("independent-review-launch-veto"),
                    launchVetoCommandID:
                        RunCommandID("independent-review-launch-veto")
                )
            )
        let reviewCompletion = try await reviewRuntime
            .completePostimageVerifier(
                launchReceiptID: reviewStart.verifierLaunch.id,
                request: KernelPostimageVerifierCompletionRequest(
                    releaseReceiptID:
                        ReceiptID("independent-review-release"),
                    releaseCommandID:
                        RunCommandID("independent-review-release")
                )
            )
        let reviewResult = try XCTUnwrap(
            reviewCompletion.authorizedResult
        )
        do {
            _ = try await reviewRuntime.recordPostimageVerification(
                result: reviewResult,
                commandID: RunCommandID("review-as-verification")
            )
            XCTFail("a review-designated result must not mint verification")
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}
        let journaledReview = try await reviewRuntime
            .recordIndependentReview(
                result: reviewResult,
                commandID: RunCommandID("independent-review-record")
            )
        XCTAssertEqual(journaledReview.review.decision, .approveCandidate)
        XCTAssertEqual(journaledReview.review.reviewer, reviewer)
        XCTAssertEqual(
            journaledReview.review.verificationEvidenceSetDigest,
            reviewedEvidenceDigest
        )
        let exactJournaledReview = await journal.independentReviewReceipt(
            transaction: journaledReview.journalTransaction
        )
        XCTAssertEqual(exactJournaledReview, journaledReview.review)
        let independentlyReviewedState = await journal.state
        XCTAssertEqual(
            independentlyReviewedState.integrationTransactions[
                transactionID
            ]?.phase,
            .appliedUnverified
        )
        do {
            _ = try await naturalRuntime
                .recordIntegrationPostimageVerification(
                    result: reviewResult,
                    integrationTransactionID: transactionID,
                    sourceVerificationReceiptID:
                        journaledVerification.verification.id,
                    commandID: RunCommandID(
                        "integration-review-capability-substitution"
                    )
                )
            XCTFail(
                "a review-designated live capability must not verify integration"
            )
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}
        let integrationVerification = try await naturalRuntime
            .recordIntegrationPostimageVerification(
                result: naturalAuthorizedResult,
                integrationTransactionID: transactionID,
                sourceVerificationReceiptID:
                    journaledVerification.verification.id,
                commandID: RunCommandID(
                    "integration-postimage-verification-record"
                )
            )
        guard case .postimageVerificationRecorded(
            let integrationVerificationReceipt
        ) = integrationVerification.event else {
            return XCTFail("expected integration postimage verification event")
        }
        XCTAssertEqual(
            integrationVerificationReceipt.sourceVerificationReceiptID,
            journaledVerification.verification.id
        )
        XCTAssertEqual(
            integrationVerificationReceipt.processQuiescenceReceiptID,
            naturalCompletion.release.id
        )
        let integrationVerifiedState = await journal.state
        XCTAssertEqual(
            integrationVerifiedState.integrationTransactions[
                transactionID
            ]?.phase,
            .postimageVerified
        )
        do {
            _ = try await reviewRuntime
                .recordIntegrationIndependentAcceptance(
                    result: naturalAuthorizedResult,
                    integrationTransactionID: transactionID,
                    sourceIndependentReviewReceiptID:
                        journaledReview.review.id,
                    commandID: RunCommandID(
                        "integration-verifier-capability-substitution"
                    )
                )
            XCTFail(
                "a verifier-designated live capability must not accept integration"
            )
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}
        let integrationAcceptance = try await reviewRuntime
            .recordIntegrationIndependentAcceptance(
                result: reviewResult,
                integrationTransactionID: transactionID,
                sourceIndependentReviewReceiptID: journaledReview.review.id,
                commandID: RunCommandID(
                    "integration-independent-acceptance-record"
                )
            )
        guard case .independentAcceptanceRecorded(
            let integrationAcceptanceReceipt
        ) = integrationAcceptance.event else {
            return XCTFail("expected integration acceptance event")
        }
        XCTAssertEqual(
            integrationAcceptanceReceipt
                .sourceIndependentReviewReceiptID,
            journaledReview.review.id
        )
        XCTAssertEqual(
            integrationAcceptanceReceipt
                .sourceVerificationEvidenceSetDigest,
            reviewedEvidenceDigest
        )
        let integrationAcceptedState = await journal.state
        XCTAssertEqual(
            integrationAcceptedState.integrationTransactions[
                transactionID
            ]?.phase,
            .independentlyAccepted
        )
        XCTAssertFalse(
            integrationAcceptedState.integrationTransactions[
                transactionID
            ]?.permitsPublication ?? true
        )

        try Data("accepted bytes\n".utf8).write(
            to: workspace.appendingPathComponent("accepted.txt")
        )
        let cache = HeavyEvidenceCache(rootDirectory: nil)
        let indexer = WorkspaceRepositoryIndexer(heavyEvidenceCache: cache)
        let firstIndex = try await indexer.resolve(
            root: workspace,
            generationReceipt: generationReceipt
        )
        let sameGeneration = try await indexer.resolve(
            root: workspace,
            generationReceipt: generationReceipt
        )
        XCTAssertEqual(firstIndex.disposition, .computed)
        XCTAssertEqual(sameGeneration.disposition, .memoryHit)

        let before = await journal.state
        XCTAssertEqual(
            before.integrationTransactions[transactionID]?.phase,
            .independentlyAccepted
        )
        XCTAssertEqual(KernelRunProjection(state: before).integrationTransactionCount, 1)

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let after = await recovered.state
        XCTAssertEqual(after, before)
        XCTAssertEqual(
            after.integrationTransactions[transactionID]?.phase,
            .independentlyAccepted
        )
        let recoveredVerifierLaunch = await recovered
            .postimageVerifierLaunchReceipt(
                receiptID: verifierStart.verifierLaunch.id
            )
        XCTAssertEqual(recoveredVerifierLaunch, verifierStart.verifierLaunch)
        let recoveredGeneration = try await recovered
            .latestAcceptedWorkspaceTreeGenerationReceipt(
                workspaceID: WorkspaceID("journal-workspace"),
                root: workspace
            )
        guard case .accepted(let recoveredReceipt) = recoveredGeneration else {
            return XCTFail("journal replay must reconstruct identical tree authority")
        }
        XCTAssertEqual(recoveredReceipt, generationReceipt)
        let recoveredAttestation = try await recovered
            .latestAcceptedWorkspaceCandidatePostimageAttestation(
                workspaceID: WorkspaceID("journal-workspace"),
                root: workspace
            )
        guard case .accepted(let recoveredAttestationReceipt) = recoveredAttestation else {
            return XCTFail("journal replay must reconstruct candidate attestation")
        }
        XCTAssertEqual(recoveredAttestationReceipt, attestationReceipt)
        let recoveredCandidateContent = await recovered
            .journaledCandidateContentCaptureReceipt(
                derivationDigest: candidateDerivation.derivationDigest
            )
        XCTAssertEqual(recoveredCandidateContent, candidateContent.receipt)
        let recoveredContentStore = await recovered
            .journaledMutationContentStoreReceipt(
                derivationDigest: candidateDerivation.derivationDigest
            )
        XCTAssertEqual(
            recoveredContentStore,
            contentStoreInstallation.authority.receipt
        )
        let replayedIndex = try await indexer.resolve(
            root: workspace,
            generationReceipt: recoveredReceipt
        )
        XCTAssertEqual(replayedIndex.disposition, .memoryHit)
        XCTAssertEqual(replayedIndex.index, firstIndex.index)
        let coordinator = try WorkspaceMutationRecoveryCoordinator(
            registry: registry,
            repositoryIndexer: indexer
        )
        let recovery = try await coordinator.recoverRegisteredRuns()
        let recoveryRun = try XCTUnwrap(recovery.runReports.first)
        XCTAssertFalse(recovery.requiresAttention)
        XCTAssertEqual(recoveryRun.repositoryIndexStatus, .resolved)
        XCTAssertEqual(
            recoveryRun.repositoryIndexTelemetry?.generationDigest,
            acceptedGeneration
        )
        XCTAssertEqual(recoveryRun.repositoryIndexTelemetry?.disposition, .memoryHit)

        var rollback = rollbackIntent()
        rollback.rollbackManifestDigest = prepared.0.rollbackManifestDigest
        rollback.expectedCurrentWorkspaceDigest = acceptedGeneration
        _ = try await recovered.transactAtCurrentSequence(
            .testOnlyAdvanceIntegration(.requestRollback(rollback)),
            commandID: RunCommandID("ambiguous-rollback-start"),
            issuedAt: rollback.requestedAt,
            actor: executor
        )
        var failedRollback = rollbackReceipt()
        failedRollback.intentID = rollback.id
        failedRollback.rollbackManifestDigest = prepared.0.rollbackManifestDigest
        failedRollback.observedPreimageDigest = nil
        failedRollback.unchangedPathProofDigest = nil
        failedRollback.outcome = .failedQuarantined(
            reasonDigest: HeavyEvidenceCache.sha256("rollback-failed"),
            recoveryArtifactDigest: failedRollback.recoveryArtifactDigest
        )
        _ = try await recovered.transactAtCurrentSequence(
            .testOnlyAdvanceIntegration(.recordRollback(failedRollback)),
            commandID: RunCommandID("ambiguous-rollback-record"),
            issuedAt: failedRollback.completedAt,
            actor: executor
        )
        let withheld = try await recovered.latestAcceptedWorkspaceTreeGenerationReceipt(
            workspaceID: WorkspaceID("journal-workspace"),
            root: workspace
        )
        guard case .ambiguousLatestTransition = withheld else {
            return XCTFail("a newer failed rollback must invalidate the older generation")
        }
        let withheldAttestation = try await recovered
            .latestAcceptedWorkspaceCandidatePostimageAttestation(
                workspaceID: WorkspaceID("journal-workspace"),
                root: workspace
            )
        guard case .ambiguousLatestTransition = withheldAttestation else {
            return XCTFail("a newer failed rollback must invalidate candidate attestation")
        }
        do {
            _ = try await WorkspaceJournaledCandidateContentCaptureIssuer(
                journal: recovered
            ).capture(
                derivation: candidateDerivation,
                input: candidateInput
            )
            XCTFail("a stale accepted apply must not authorize candidate-byte reuse")
        } catch WorkspaceJournaledCandidateContentCaptureError.authorityMismatch {}
        do {
            _ = try await WorkspaceJournaledMutationContentCompositionIssuer(
                journal: recovered
            ).compose(
                derivation: candidateDerivation,
                baseline: baselineContent,
                candidate: candidateContent
            )
            XCTFail("a newer failed rollback must invalidate content composition")
        } catch WorkspaceJournaledMutationContentCompositionError
            .candidateAuthorityStale {}
        do {
            _ = try await WorkspaceJournaledMutationContentStoreCoordinator(
                journal: recovered,
                wallClock: { Date(timeIntervalSince1970: 20) }
            ).install(
                composition: composedContent,
                workspaceRoot: workspace,
                storageRoot: registryRoot,
                commandID: RunCommandID("stale-journaled-content-store")
            )
            XCTFail("a newer failed rollback must invalidate store acceptance")
        } catch WorkspaceJournaledMutationContentStoreError
            .candidateAuthorityStale {}
        let ambiguousRecovery = try await coordinator.recoverRegisteredRuns()
        XCTAssertTrue(ambiguousRecovery.requiresAttention)
        XCTAssertEqual(
            ambiguousRecovery.runReports.first?.repositoryIndexStatus,
            .withheldAmbiguousGeneration
        )
        XCTAssertNil(ambiguousRecovery.runReports.first?.repositoryIndexTelemetry)

        // Replay the exact pre-completion launch after the first branch has
        // terminated and reaped its native PID. A fresh runtime cannot invent
        // the lost exit status; it must prove exact absence, retain bounded
        // output evidence, and release fail-red through the typed completion
        // path. Generic reconciliation is intentionally denied.
        XCTAssertEqual(
            Darwin.chmod(
                candidateInput.receipt.snapshotRootPath,
                0o700
            ),
            0
        )
        XCTAssertEqual(
            Darwin.chmod(
                URL(fileURLWithPath: candidateInput.receipt.snapshotRootPath)
                    .appendingPathComponent("file.txt").path,
                0o600
            ),
            0
        )
        try FileManager.default.removeItem(at: root)
        try FileManager.default.copyItem(
            at: preCompletionJournalSnapshot,
            to: root
        )
        let absentJournal = try RunJournal(rootDirectory: root, runID: runID)
        let absentSupervisor = RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 4,
                memoryBytes: 128 * 1_024 * 1_024,
                diskIOWeight: 4,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 4
            )),
            pressure: .nominal
        )
        let absentSnapshot = await absentJournal
            .runtimeSupervisorRecoverySnapshot()
        guard case .restored = await absentSupervisor.restore(
            from: absentSnapshot
        ) else {
            return XCTFail("expected verifier lease recovery hydration")
        }
        let absentRuntime = JournaledProcessRuntime(
            supervisor: absentSupervisor,
            journal: absentJournal,
            actorIdentity: verifier
        )
        do {
            _ = try await absentRuntime.reconcile(
                resourceID: verifierStart.verifierLaunch.resourceID,
                absentReleaseReceiptID:
                    ReceiptID("generic-verifier-absence-release"),
                absentReleaseCommandID:
                    RunCommandID("generic-verifier-absence-release")
            )
            XCTFail("generic reconciliation must not release a verifier lease")
        } catch JournaledProcessRuntimeError.postimageVerifierUnauthorized {}

        let absentCompletion = try await absentRuntime
            .completePostimageVerifier(
                launchReceiptID: verifierStart.verifierLaunch.id,
                request: KernelPostimageVerifierCompletionRequest(
                    releaseReceiptID:
                        ReceiptID("postimage-verifier-absent-release"),
                    releaseCommandID:
                        RunCommandID("postimage-verifier-absent-release")
                )
            )
        XCTAssertEqual(
            absentCompletion.containment.disposition,
            .recoveryProcessAbsent
        )
        XCTAssertNil(absentCompletion.naturalExit)
        XCTAssertNil(absentCompletion.termination)
        XCTAssertNil(absentCompletion.release.managedProcessExit)
        XCTAssertNil(absentCompletion.release.managedProcessTermination)
        XCTAssertEqual(absentCompletion.containment.schemaVersion, 4)
        XCTAssertNil(absentCompletion.containment.resultMapping)
        XCTAssertEqual(
            absentCompletion.containment
                .resultMappingFailureDigest?.rawValue.utf8.count,
            64
        )
        XCTAssertNil(absentCompletion.containment.postimageResult)
        XCTAssertEqual(
            absentCompletion.containment
                .postimageResultFailureDigest?.rawValue.utf8.count,
            64
        )
        XCTAssertNil(absentCompletion.authorizedResult)
        if let absentParse = absentCompletion.containment.resultParse {
            XCTAssertEqual(absentParse.resultCode, "accepted")
            XCTAssertEqual(
                absentParse.evidenceDigest,
                ContentDigest(verifierEvidence)
            )
            XCTAssertEqual(
                absentCompletion.containment.standardOutput?.contentDigest,
                absentParse.standardOutputContentDigest
            )
            XCTAssertGreaterThan(
                absentCompletion.containment.standardOutput?.byteCount ?? 0,
                0
            )
            XCTAssertNil(
                absentCompletion.containment.resultParseFailureDigest
            )
        } else {
            let parseFailure = try XCTUnwrap(
                absentCompletion.containment.resultParseFailureDigest
            )
            XCTAssertEqual(parseFailure.rawValue.utf8.count, 64)
        }
        XCTAssertEqual(
            absentCompletion.containment.standardError?.byteCount,
            0
        )
        XCTAssertEqual(
            absentCompletion.release.postimageVerifierContainment,
            absentCompletion.containment
        )
        let absentState = await absentJournal.state
        XCTAssertEqual(
            absentState.integrationTransactions[transactionID]?.phase,
            .appliedUnverified
        )
        let absentProjection = await absentSupervisor.projection()
        XCTAssertTrue(absentProjection.liveLeases.isEmpty)
        let replayedAbsent = try RunJournal(rootDirectory: root, runID: runID)
        let replayedAbsentState = await replayedAbsent.state
        XCTAssertEqual(replayedAbsentState, absentState)
    }

    func testJournaledWorkspaceRuntimeDoesNotReenterExecutorForRecordedApply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeJournaledWorkspaceRuntime-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        var commandIndex = 0
        func transact(_ command: RunCommand, actor: ActorIdentity) async throws {
            commandIndex += 1
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: RunCommandID("runtime-setup-\(commandIndex)"),
                issuedAt: Date(timeIntervalSince1970: TimeInterval(commandIndex)),
                actor: actor
            )
        }
        try await transact(.createRun(contract()), actor: reviewer)
        try await transact(.proposePlan(KernelPlanProposal(
            contractDigest: ContentDigest("contract"),
            nodes: [node()]
        )), actor: reviewer)
        try await transact(.authorizeNode(nodeID), actor: reviewer)
        try await transact(.initializeConvergence(
            epochID: "integration-epoch",
            budget: convergenceBudget()
        ), actor: reviewer)
        try await transact(.admitCausalAttempt(causalAdmission()), actor: reviewer)
        try await transact(.startAttempt(
            attemptID: attemptID,
            nodeID: nodeID,
            requirementIDs: [RequirementID("requirement")],
            strategyFingerprint: causalStrategy().fingerprint
        ), actor: executor)
        try await journalTestWorkerDisposition(
            journal,
            runID: runID,
            attemptID: attemptID,
            actor: executor,
            prefix: "integration-runtime"
        )
        try await transact(.testOnlyRecordVerification(VerificationReceipt(
            id: ReceiptID("candidate-verification"),
            attemptID: attemptID,
            requirementIDs: [RequirementID("requirement")],
            sourceRevision: ContentDigest("postimage"),
            environmentDigest: ContentDigest("environment"),
            oracleDigest: ContentDigest("oracle"),
            result: .accepted
        )), actor: verifier)
        try await transact(.testOnlyRecordReview(IndependentReviewReceipt(
            id: ReceiptID("candidate-review"),
            attemptID: attemptID,
            requirementIDs: [RequirementID("requirement")],
            reviewer: reviewer,
            evidenceDigest: ContentDigest("review-evidence"),
            sourceRevision: ContentDigest("postimage"),
            decision: .approveCandidate
        )), actor: reviewer)
        try await transact(.testOnlyAdvanceIntegration(.propose(proposal())), actor: executor)
        let prepared = preflightAndRollback()
        try await transact(.testOnlyAdvanceIntegration(.acceptPreflight(
            receipt: prepared.0,
            rollback: prepared.1
        )), actor: executor)
        let supervisor = RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 1,
                memoryBytes: 1,
                diskIOWeight: 2,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 0
            ))
        )
        let authority = JournaledWorkspaceMutationLeaseAuthority(
            supervisor: supervisor,
            journal: journal,
            actorIdentity: executor
        )
        let issuedAt = Date(timeIntervalSince1970: 11)
        let leaseAdmission = try await authority.admit(
            transactionID: transactionID,
            workspaceID: WorkspaceID("unused"),
            rootIdentity: ContentDigest("unused-root"),
            operation: .apply,
            leaseID: ResourceLeaseID("workspace-runtime-lease"),
            admissionReceiptID: ReceiptID("exclusive-lease"),
            admissionCommandID: RunCommandID("workspace-runtime-admission"),
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(60),
            requestedAtMonotonicNanoseconds: 1_000,
            expiresAtMonotonicNanoseconds: 60_000_001_000
        )
        try await transact(.testOnlyAdvanceIntegration(.startApply(applyIntent())), actor: executor)
        try await transact(.testOnlyAdvanceIntegration(.recordApply(applyReceipt())), actor: executor)

        let dummyPreimage = WorkspacePreimage(
            workspaceID: WorkspaceID("unused"),
            rootIdentity: ContentDigest("unused-root"),
            contractDigest: ContentDigest("contract"),
            sourceRevision: ContentDigest("revision"),
            requiredPlanes: [.worktree],
            capturedPlanes: [.worktree],
            entries: [],
            repositoryMetadataDigest: ContentDigest("metadata"),
            ignoredPathPolicyDigest: ContentDigest("ignored"),
            capturedAt: Date(timeIntervalSince1970: 1)
        )
        let dummyManifest = MutationManifest(
            transactionID: transactionID,
            candidateID: candidateID,
            contractDigest: ContentDigest("contract"),
            planNodeDigest: ContentDigest("plan-node"),
            basePreimageDigest: ContentDigest("preimage"),
            operations: [],
            touchedRequirementIDs: [],
            writeAuthorityReceiptID: ReceiptID("write"),
            mutationBudgetReceiptID: ReceiptID("budget"),
            candidateVerificationReceiptIDs: [],
            independentReviewReceiptID: ReceiptID("review"),
            rollbackRehearsalReceiptID: ReceiptID("rehearsal"),
            candidateQuiescenceReceiptID: ReceiptID("quiescence"),
            visualGateReceiptID: nil,
            expectedPostimageDigest: ContentDigest("postimage")
        )
        let request = WorkspaceMutationExecutionRequest(
            workspaceRoot: root.appendingPathComponent("must-not-be-read"),
            recoveryRoot: root.appendingPathComponent("must-not-be-written"),
            workspaceID: WorkspaceID("unused"),
            preimage: dummyPreimage,
            manifest: dummyManifest,
            rollbackManifest: prepared.1,
            preflightReceipt: prepared.0,
            intent: applyIntent(),
            lease: leaseAdmission.executionLease,
            contentObjects: [],
            executor: executor,
            completedAt: Date(timeIntervalSince1970: 20),
            limits: .conservative
        )
        let runtime = JournaledWorkspaceMutationRuntime(
            journal: journal,
            actorIdentity: executor,
            authority: authority,
            wallClock: { Date(timeIntervalSince1970: 20) },
            monotonicClock: { 9_000_001_000 }
        )
        let recovered = try await runtime.apply(
            request,
            startCommandID: RunCommandID("unused-start"),
            recordCommandID: RunCommandID("unused-record"),
            releaseReceiptID: ReceiptID("workspace-runtime-release"),
            releaseCommandID: RunCommandID("workspace-runtime-release-command"),
            failureReceiptID: ReceiptID("workspace-runtime-failure"),
            failureCommandID: RunCommandID("workspace-runtime-failure-command")
        )
        XCTAssertTrue(recovered.recoveredFromJournal)
        XCTAssertNil(recovered.startTransaction)
        XCTAssertNil(recovered.recordTransaction)
        XCTAssertEqual(recovered.applyReceipt, applyReceipt())
        XCTAssertNil(recovered.treeGenerationReceipt)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: request.recoveryRoot.path
        ))

        let outbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: root.appendingPathComponent("effect-outbox"),
            runID: runID
        )
        _ = try await outbox.enqueue(
            payload: .apply(request),
            startCommandID: RunCommandID("dispatcher-start"),
            recordCommandID: RunCommandID("dispatcher-record"),
            releaseReceiptID: ReceiptID("workspace-runtime-release"),
            releaseCommandID: RunCommandID("workspace-runtime-release-command"),
            failureReceiptID: ReceiptID("workspace-runtime-failure"),
            failureCommandID: RunCommandID("workspace-runtime-failure-command"),
            enqueuedAt: Date(timeIntervalSince1970: 19)
        )
        let dispatcher = JournaledWorkspaceMutationDispatcher(
            outbox: outbox,
            runtime: runtime
        )
        let report = try await dispatcher.recoverPending(limit: 1)
        XCTAssertEqual(report.scannedCount, 1)
        XCTAssertEqual(report.completedIntentIDs, [applyIntent().id])
        XCTAssertTrue(report.failures.isEmpty)
        let afterDispatch = try await outbox.pending(limit: 1)
        XCTAssertTrue(afterDispatch.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: request.recoveryRoot.path
        ))

        var unauthorizedRequest = request
        unauthorizedRequest.executor = reviewer
        unauthorizedRequest.intent.id = IntegrationEffectIntentID("unauthorized-intent")
        let failedOutbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: root.appendingPathComponent("failed-effect-outbox"),
            runID: runID
        )
        _ = try await failedOutbox.enqueue(
            payload: .apply(unauthorizedRequest),
            startCommandID: RunCommandID("failed-start"),
            recordCommandID: RunCommandID("failed-record"),
            releaseReceiptID: ReceiptID("failed-release"),
            releaseCommandID: RunCommandID("failed-release-command"),
            failureReceiptID: ReceiptID("failed-cleanup"),
            failureCommandID: RunCommandID("failed-cleanup-command"),
            enqueuedAt: Date(timeIntervalSince1970: 20)
        )
        let failedDispatcher = JournaledWorkspaceMutationDispatcher(
            outbox: failedOutbox,
            runtime: runtime
        )
        let failedReport = try await failedDispatcher.recoverPending(limit: 1)
        XCTAssertEqual(failedReport.scannedCount, 1)
        XCTAssertTrue(failedReport.completedIntentIDs.isEmpty)
        XCTAssertEqual(
            failedReport.failures,
            [WorkspaceMutationEffectDispatchFailure(
                intentID: unauthorizedRequest.intent.id,
                error: .actorMismatch
            )]
        )
        XCTAssertEqual(
            failedReport.quarantinedIntentIDs,
            [unauthorizedRequest.intent.id]
        )
        let retiredInvalidRequest = try await failedOutbox.pending(limit: 1)
        XCTAssertTrue(retiredInvalidRequest.isEmpty)
        let secondInvalidDispatch = try await failedDispatcher.recoverPending(limit: 1)
        XCTAssertEqual(secondInvalidDispatch.scannedCount, 0)
    }

    func testJournaledWorkspaceLeaseAuthorityBindsJournalSupervisorAndRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeWorkspaceLeaseAuthority-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        var commandIndex = 0
        func transact(_ command: RunCommand, actor: ActorIdentity) async throws {
            commandIndex += 1
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: RunCommandID("lease-setup-\(commandIndex)"),
                issuedAt: Date(timeIntervalSince1970: TimeInterval(commandIndex)),
                actor: actor
            )
        }
        try await transact(.createRun(contract()), actor: reviewer)
        try await transact(.proposePlan(KernelPlanProposal(
            contractDigest: ContentDigest("contract"),
            nodes: [node()]
        )), actor: reviewer)
        try await transact(.authorizeNode(nodeID), actor: reviewer)
        try await transact(.initializeConvergence(
            epochID: "integration-epoch",
            budget: convergenceBudget()
        ), actor: reviewer)
        try await transact(.admitCausalAttempt(causalAdmission()), actor: reviewer)
        try await transact(.startAttempt(
            attemptID: attemptID,
            nodeID: nodeID,
            requirementIDs: [RequirementID("requirement")],
            strategyFingerprint: causalStrategy().fingerprint
        ), actor: executor)
        try await journalTestWorkerDisposition(
            journal,
            runID: runID,
            attemptID: attemptID,
            actor: executor,
            prefix: "integration-lease"
        )
        try await transact(.testOnlyRecordVerification(VerificationReceipt(
            id: ReceiptID("candidate-verification"),
            attemptID: attemptID,
            requirementIDs: [RequirementID("requirement")],
            sourceRevision: ContentDigest("postimage"),
            environmentDigest: ContentDigest("environment"),
            oracleDigest: ContentDigest("oracle"),
            result: .accepted
        )), actor: verifier)
        try await transact(.testOnlyRecordReview(IndependentReviewReceipt(
            id: ReceiptID("candidate-review"),
            attemptID: attemptID,
            requirementIDs: [RequirementID("requirement")],
            reviewer: reviewer,
            evidenceDigest: ContentDigest("review-evidence"),
            sourceRevision: ContentDigest("postimage"),
            decision: .approveCandidate
        )), actor: reviewer)
        try await transact(.testOnlyAdvanceIntegration(.propose(proposal())), actor: executor)
        let prepared = preflightAndRollback()
        try await transact(.testOnlyAdvanceIntegration(.acceptPreflight(
            receipt: prepared.0,
            rollback: prepared.1
        )), actor: executor)

        let supervisor = RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 1,
                memoryBytes: 1,
                diskIOWeight: 2,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 0
            ))
        )
        let authority = JournaledWorkspaceMutationLeaseAuthority(
            supervisor: supervisor,
            journal: journal,
            actorIdentity: executor
        )
        let issuedAt = Date(timeIntervalSince1970: 100)
        let admitted = try await authority.admit(
            transactionID: transactionID,
            workspaceID: WorkspaceID("workspace"),
            rootIdentity: ContentDigest("canonical-root"),
            operation: .apply,
            leaseID: ResourceLeaseID("workspace-lease"),
            admissionReceiptID: ReceiptID("workspace-admission"),
            admissionCommandID: RunCommandID("workspace-admission-command"),
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(60),
            requestedAtMonotonicNanoseconds: 1_000,
            expiresAtMonotonicNanoseconds: 60_000_001_000
        )
        XCTAssertEqual(admitted.runtimeAdmission.request.kind, .workspaceMutation)
        XCTAssertEqual(
            admitted.runtimeAdmission.request.resourceID,
            JournaledWorkspaceMutationLeaseAuthority.resourceID(
                workspaceID: WorkspaceID("workspace"),
                rootIdentity: ContentDigest("canonical-root")
            )
        )
        try await authority.validate(
            admitted.executionLease,
            operation: .apply,
            at: issuedAt.addingTimeInterval(1),
            atMonotonicNanoseconds: 1_000_001_000
        )

        var forged = admitted.executionLease
        forged.rootIdentity = ContentDigest("forged-root")
        do {
            try await authority.validate(
                forged,
                operation: .apply,
                at: issuedAt.addingTimeInterval(1),
                atMonotonicNanoseconds: 1_000_001_000
            )
            XCTFail("Expected forged lease rejection")
        } catch JournaledWorkspaceMutationLeaseAuthorityError.authorityNotLive {}

        do {
            _ = try await authority.admit(
                transactionID: transactionID,
                workspaceID: WorkspaceID("workspace"),
                rootIdentity: ContentDigest("canonical-root"),
                operation: .apply,
                leaseID: ResourceLeaseID("conflicting-workspace-lease"),
                admissionReceiptID: ReceiptID("conflicting-workspace-admission"),
                admissionCommandID: RunCommandID("conflicting-workspace-command"),
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(60),
                requestedAtMonotonicNanoseconds: 1_000,
                expiresAtMonotonicNanoseconds: 60_000_001_000
            )
            XCTFail("Expected canonical-root exclusivity rejection")
        } catch JournaledWorkspaceMutationLeaseAuthorityError.admissionRejected(
            .duplicateResource(existingLeaseID: ResourceLeaseID("workspace-lease"))
        ) {}

        let recoveredSupervisor = RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 1,
                memoryBytes: 1,
                diskIOWeight: 2,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 0
            ))
        )
        let recoveredAuthority = JournaledWorkspaceMutationLeaseAuthority(
            supervisor: recoveredSupervisor,
            journal: journal,
            actorIdentity: executor
        )
        try await recoveredAuthority.validate(
            admitted.executionLease,
            operation: .apply,
            at: issuedAt.addingTimeInterval(1),
            atMonotonicNanoseconds: 1_000_001_000
        )
        let replayedAdmission = try await recoveredAuthority.admit(
            transactionID: transactionID,
            workspaceID: WorkspaceID("workspace"),
            rootIdentity: ContentDigest("canonical-root"),
            operation: .apply,
            leaseID: ResourceLeaseID("workspace-lease"),
            admissionReceiptID: ReceiptID("workspace-admission"),
            admissionCommandID: RunCommandID("workspace-admission-command"),
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(60),
            requestedAtMonotonicNanoseconds: 1_000,
            expiresAtMonotonicNanoseconds: 60_000_001_000
        )
        XCTAssertTrue(replayedAdmission.journalTransaction.duplicate)
        XCTAssertEqual(replayedAdmission.runtimeAdmission, admitted.runtimeAdmission)
        XCTAssertEqual(replayedAdmission.executionLease, admitted.executionLease)
        let failureReason = ContentDigest("executor-failure")
        let stagedFailure = await recoveredSupervisor.previewReleaseFailureReceipt(
            resourceID: admitted.runtimeAdmission.request.resourceID,
            leaseID: admitted.runtimeAdmission.request.leaseID,
            receiptID: ReceiptID("workspace-release-failed"),
            reasonDigest: failureReason,
            observedAt: issuedAt.addingTimeInterval(1.5),
            observedAtMonotonicNanoseconds: 1_500_001_000
        )
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordRuntimeRelease(stagedFailure),
            commandID: RunCommandID("workspace-release-failed-command"),
            issuedAt: issuedAt.addingTimeInterval(1.5),
            actor: executor
        )
        let failedRelease = try await recoveredAuthority.recordReleaseFailure(
            admitted.executionLease,
            receiptID: ReceiptID("workspace-release-failed"),
            commandID: RunCommandID("workspace-release-failed-command"),
            reasonDigest: failureReason,
            observedAt: issuedAt.addingTimeInterval(1.5),
            observedAtMonotonicNanoseconds: 1_500_001_000
        )
        XCTAssertEqual(
            failedRelease.runtimeFailure.outcome,
            .cleanupFailed(reasonDigest: failureReason)
        )
        let failedResourceID = admitted.runtimeAdmission.request.resourceID
        let journalFailed = await journal.runtimeReleaseFailed(resourceID: failedResourceID)
        let failedProjection = await recoveredSupervisor.projection()
        XCTAssertTrue(journalFailed)
        XCTAssertTrue(failedProjection.failedReleases.contains(failedResourceID))

        let failedOwnershipRequest = WorkspaceMutationExecutionRequest(
            workspaceRoot: root.appendingPathComponent("must-not-be-entered"),
            recoveryRoot: root.appendingPathComponent("must-not-be-written"),
            workspaceID: admitted.executionLease.workspaceID,
            preimage: WorkspacePreimage(
                workspaceID: admitted.executionLease.workspaceID,
                rootIdentity: admitted.executionLease.rootIdentity,
                contractDigest: ContentDigest("contract"),
                sourceRevision: ContentDigest("revision"),
                requiredPlanes: [.worktree],
                capturedPlanes: [.worktree],
                entries: [],
                repositoryMetadataDigest: ContentDigest("metadata"),
                ignoredPathPolicyDigest: ContentDigest("ignored"),
                capturedAt: issuedAt
            ),
            manifest: MutationManifest(
                transactionID: transactionID,
                candidateID: candidateID,
                contractDigest: ContentDigest("contract"),
                planNodeDigest: ContentDigest("plan-node"),
                basePreimageDigest: ContentDigest("preimage"),
                operations: [],
                touchedRequirementIDs: [],
                writeAuthorityReceiptID: ReceiptID("write"),
                mutationBudgetReceiptID: ReceiptID("budget"),
                candidateVerificationReceiptIDs: [],
                independentReviewReceiptID: ReceiptID("review"),
                rollbackRehearsalReceiptID: ReceiptID("rehearsal"),
                candidateQuiescenceReceiptID: ReceiptID("quiescence"),
                visualGateReceiptID: nil,
                expectedPostimageDigest: ContentDigest("postimage")
            ),
            rollbackManifest: prepared.1,
            preflightReceipt: prepared.0,
            intent: applyIntent(),
            lease: admitted.executionLease,
            contentObjects: [],
            executor: executor,
            completedAt: issuedAt.addingTimeInterval(2),
            limits: .conservative
        )
        let failedOwnershipRuntime = JournaledWorkspaceMutationRuntime(
            journal: journal,
            actorIdentity: executor,
            authority: recoveredAuthority,
            wallClock: { issuedAt.addingTimeInterval(2) },
            monotonicClock: { 2_000_001_000 }
        )
        do {
            _ = try await failedOwnershipRuntime.apply(
                failedOwnershipRequest,
                startCommandID: RunCommandID("must-not-start"),
                recordCommandID: RunCommandID("must-not-record"),
                releaseReceiptID: ReceiptID("must-not-release"),
                releaseCommandID: RunCommandID("must-not-release-command"),
                failureReceiptID: ReceiptID("must-not-fail-again"),
                failureCommandID: RunCommandID("must-not-fail-again-command")
            )
            XCTFail("Expected failed ownership to prohibit executor re-entry")
        } catch JournaledWorkspaceMutationRuntimeError
            .failedOwnershipRequiresRepair(let resourceID) {
            XCTAssertEqual(resourceID, failedResourceID)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: failedOwnershipRequest.recoveryRoot.path
        ))

        let failedOwnershipOutbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: root.appendingPathComponent("failed-ownership-outbox"),
            runID: runID
        )
        _ = try await failedOwnershipOutbox.enqueue(
            payload: .apply(failedOwnershipRequest),
            startCommandID: RunCommandID("blocked-start"),
            recordCommandID: RunCommandID("blocked-record"),
            releaseReceiptID: ReceiptID("blocked-release"),
            releaseCommandID: RunCommandID("blocked-release-command"),
            failureReceiptID: ReceiptID("blocked-failure"),
            failureCommandID: RunCommandID("blocked-failure-command"),
            enqueuedAt: issuedAt.addingTimeInterval(2)
        )
        let failedOwnershipDispatcher = JournaledWorkspaceMutationDispatcher(
            outbox: failedOwnershipOutbox,
            runtime: failedOwnershipRuntime,
            wallClock: { issuedAt.addingTimeInterval(3) }
        )
        let firstBlockedDispatch = try await failedOwnershipDispatcher
            .recoverPending(limit: 1)
        XCTAssertEqual(firstBlockedDispatch.scannedCount, 1)
        XCTAssertEqual(
            firstBlockedDispatch.quarantinedIntentIDs,
            [failedOwnershipRequest.intent.id]
        )
        XCTAssertEqual(
            firstBlockedDispatch.failures.first?.error,
            .failedOwnershipRequiresRepair(failedResourceID)
        )
        let secondBlockedDispatch = try await failedOwnershipDispatcher
            .recoverPending(limit: 1)
        XCTAssertEqual(secondBlockedDispatch.scannedCount, 0)
        XCTAssertTrue(secondBlockedDispatch.completedIntentIDs.isEmpty)
        XCTAssertTrue(secondBlockedDispatch.quarantinedIntentIDs.isEmpty)
        let failedOwnershipEntries = try await failedOwnershipOutbox.allEntries()
        guard case .quarantined(_, let quarantinedAt) =
                failedOwnershipEntries.first?.state else {
            return XCTFail("failed ownership must retire from ordinary dispatch")
        }
        XCTAssertEqual(quarantinedAt, issuedAt.addingTimeInterval(3))

        let stagedRelease = await recoveredSupervisor.previewReleaseOutcomeReceipt(
            resourceID: admitted.runtimeAdmission.request.resourceID,
            leaseID: admitted.runtimeAdmission.request.leaseID,
            receiptID: ReceiptID("workspace-release"),
            observedAt: issuedAt.addingTimeInterval(2),
            observedAtMonotonicNanoseconds: 2_000_001_000
        )
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordRuntimeRelease(stagedRelease),
            commandID: RunCommandID("workspace-release-command"),
            issuedAt: issuedAt.addingTimeInterval(2),
            actor: executor
        )
        let stagedProjection = await recoveredSupervisor.projection()
        XCTAssertTrue(stagedProjection.liveLeases.contains {
            $0.request.resourceID == admitted.runtimeAdmission.request.resourceID
        })
        let released = try await recoveredAuthority.release(
            admitted.executionLease,
            receiptID: ReceiptID("workspace-release"),
            commandID: RunCommandID("workspace-release-command"),
            observedAt: issuedAt.addingTimeInterval(2),
            observedAtMonotonicNanoseconds: 2_000_001_000
        )
        guard case .released = released.runtimeRelease.outcome else {
            return XCTFail("Expected journaled release")
        }
        let resourceID = admitted.runtimeAdmission.request.resourceID
        let journalLease = await journal.runtimeLease(resourceID: resourceID)
        let supervisorProjection = await recoveredSupervisor.projection()
        XCTAssertNil(journalLease)
        XCTAssertFalse(supervisorProjection.liveLeases.contains {
            $0.request.resourceID == resourceID
        })

        let expiredIssuedAt = issuedAt.addingTimeInterval(3)
        let expiredAdmission = try await recoveredAuthority.admit(
            transactionID: transactionID,
            workspaceID: WorkspaceID("workspace"),
            rootIdentity: ContentDigest("canonical-root"),
            operation: .apply,
            leaseID: ResourceLeaseID("expired-workspace-lease"),
            admissionReceiptID: ReceiptID("expired-workspace-admission"),
            admissionCommandID: RunCommandID("expired-workspace-admission-command"),
            issuedAt: expiredIssuedAt,
            expiresAt: expiredIssuedAt.addingTimeInterval(1),
            requestedAtMonotonicNanoseconds: 3_000_001_000,
            expiresAtMonotonicNanoseconds: 4_000_001_000
        )
        var expiredRequest = failedOwnershipRequest
        expiredRequest.lease = expiredAdmission.executionLease
        expiredRequest.intent.exclusiveLeaseReceiptID =
            expiredAdmission.executionLease.receiptID
        expiredRequest.completedAt = expiredIssuedAt
        let expiredRuntime = JournaledWorkspaceMutationRuntime(
            journal: journal,
            actorIdentity: executor,
            authority: recoveredAuthority,
            wallClock: { expiredIssuedAt.addingTimeInterval(2) },
            monotonicClock: { 5_000_001_000 }
        )
        let expiredOutbox = try WorkspaceMutationEffectOutbox(
            rootDirectory: root.appendingPathComponent("expired-effect-outbox"),
            runID: runID
        )
        _ = try await expiredOutbox.enqueue(
            payload: .apply(expiredRequest),
            startCommandID: RunCommandID("expired-start"),
            recordCommandID: RunCommandID("expired-record"),
            releaseReceiptID: ReceiptID("expired-release"),
            releaseCommandID: RunCommandID("expired-release-command"),
            failureReceiptID: ReceiptID("expired-failure"),
            failureCommandID: RunCommandID("expired-failure-command"),
            enqueuedAt: expiredIssuedAt.addingTimeInterval(2)
        )
        let expiredDispatcher = JournaledWorkspaceMutationDispatcher(
            outbox: expiredOutbox,
            runtime: expiredRuntime,
            wallClock: { expiredIssuedAt.addingTimeInterval(2) }
        )
        let expiredFirstDispatch = try await expiredDispatcher.recoverPending(limit: 1)
        XCTAssertEqual(expiredFirstDispatch.scannedCount, 1)
        XCTAssertEqual(
            expiredFirstDispatch.quarantinedIntentIDs,
            [expiredRequest.intent.id]
        )
        XCTAssertEqual(
            expiredFirstDispatch.failures.first?.error,
            .preEffectRejectedAndReleased(.leaseExpired)
        )
        let expiredJournalLease = await journal.runtimeLease(resourceID: resourceID)
        XCTAssertNil(expiredJournalLease)
        let expiredSupervisorProjection = await recoveredSupervisor.projection()
        XCTAssertFalse(expiredSupervisorProjection.liveLeases.contains {
            $0.request.resourceID == resourceID
        })
        XCTAssertFalse(expiredSupervisorProjection.failedReleases.contains(resourceID))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: expiredRequest.recoveryRoot.path
        ))
        let expiredSecondDispatch = try await expiredDispatcher.recoverPending(limit: 1)
        XCTAssertEqual(expiredSecondDispatch.scannedCount, 0)
    }

    private func proposal() -> IntegrationProposal {
        IntegrationProposal(
            runID: runID,
            transactionID: transactionID,
            candidateID: candidateID,
            attemptID: attemptID,
            nodeID: nodeID,
            contractDigest: ContentDigest("contract"),
            planNodeDigest: ContentDigest("plan-node"),
            manifestDigest: ContentDigest("manifest"),
            canonicalPreimageDigest: ContentDigest("preimage"),
            expectedPostimageDigest: ContentDigest("postimage"),
            proposedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func preflightAndRollback() -> (MutationPreflightReceipt, RollbackManifest) {
        let rollback = RollbackManifest(
            transactionID: transactionID,
            forwardManifestDigest: ContentDigest("manifest"),
            expectedAppliedPostimageDigest: ContentDigest("postimage"),
            restoresPreimageDigest: ContentDigest("preimage"),
            operations: [MutationOperation(
                sequence: 1,
                kind: .modify,
                sourcePath: nil,
                destinationPath: "file.txt",
                expectedPreimage: ContentDigest("new"),
                desiredPostimage: ContentDigest("old"),
                entryKindBefore: .regularFile,
                entryKindAfter: .regularFile,
                modeBefore: 0o100644,
                modeAfter: 0o100644,
                requirementIDs: [RequirementID("requirement")],
                pathResolutionReceiptID: ReceiptID("path")
            )]
        )
        let receipt = MutationPreflightReceipt(
            id: ReceiptID("preflight"),
            transactionID: transactionID,
            candidateID: candidateID,
            manifestDigest: ContentDigest("manifest"),
            canonicalPreimageDigest: ContentDigest("preimage"),
            rollbackManifestDigest: TransactionalMutationKernel.rollbackDigest(rollback),
            affectedPaths: ["file.txt"],
            operationCount: 1,
            changedFileCount: 1,
            changedByteCount: 1,
            writeAuthorityReceiptID: ReceiptID("write"),
            mutationBudgetReceiptID: ReceiptID("budget"),
            candidateVerificationReceiptIDs: [ReceiptID("candidate-verification")],
            independentReviewReceiptID: ReceiptID("candidate-review"),
            rollbackRehearsalReceiptID: ReceiptID("rollback-rehearsal"),
            candidateQuiescenceReceiptID: ReceiptID("candidate-quiescence"),
            visualGateReceiptID: nil,
            observedAt: Date(timeIntervalSince1970: 11),
            eligibleForDeterministicApply: true,
            permitsPublication: false
        )
        return (receipt, rollback)
    }

    private func applyIntent() -> IntegrationApplyIntent {
        IntegrationApplyIntent(
            id: IntegrationEffectIntentID("apply-intent"),
            transactionID: transactionID,
            preflightReceiptID: ReceiptID("preflight"),
            manifestDigest: ContentDigest("manifest"),
            canonicalPreimageDigest: ContentDigest("preimage"),
            rollbackManifestDigest: preflightAndRollback().0.rollbackManifestDigest,
            stagedObjectSetDigest: ContentDigest("staged-objects"),
            exclusiveLeaseReceiptID: ReceiptID("exclusive-lease"),
            remoteAccessDisabled: true,
            requestedAt: Date(timeIntervalSince1970: 12)
        )
    }

    private func applyReceipt() -> IntegrationApplyReceipt {
        IntegrationApplyReceipt(
            id: ReceiptID("apply"),
            intentID: IntegrationEffectIntentID("apply-intent"),
            transactionID: transactionID,
            manifestDigest: ContentDigest("manifest"),
            canonicalPreimageDigest: ContentDigest("preimage"),
            observedPostimageDigest: ContentDigest("postimage"),
            unchangedPathProofDigest: ContentDigest("unchanged"),
            recoveryArtifactDigest: ContentDigest("recovery-artifact"),
            appliedOperationCount: 1,
            executor: executor,
            completedAt: Date(timeIntervalSince1970: 13),
            outcome: .exactPostimage
        )
    }

    private func verificationReceipt() -> IntegrationPostimageVerificationReceipt {
        IntegrationPostimageVerificationReceipt(
            id: ReceiptID("postimage-verification"),
            transactionID: transactionID,
            applyReceiptID: ReceiptID("apply"),
            canonicalPostimageDigest: ContentDigest("postimage"),
            evidenceSetDigest: ContentDigest("postimage-evidence"),
            processQuiescenceReceiptID: ReceiptID("postimage-quiescence"),
            verifier: verifier,
            verifiedAt: Date(timeIntervalSince1970: 14),
            result: .accepted
        )
    }

    private func acceptanceReceipt() -> IntegrationAcceptanceReceipt {
        IntegrationAcceptanceReceipt(
            id: ReceiptID("acceptance"),
            transactionID: transactionID,
            verificationReceiptID: ReceiptID("postimage-verification"),
            canonicalPostimageDigest: ContentDigest("postimage"),
            evidenceDigest: ContentDigest("acceptance-evidence"),
            reviewer: reviewer,
            reviewedAt: Date(timeIntervalSince1970: 15),
            decision: .accepted
        )
    }

    private func rollbackIntent() -> IntegrationRollbackIntent {
        IntegrationRollbackIntent(
            id: IntegrationEffectIntentID("rollback-intent"),
            transactionID: transactionID,
            rollbackManifestDigest: preflightAndRollback().0.rollbackManifestDigest,
            expectedCurrentWorkspaceDigest: ContentDigest("postimage"),
            recoveryArtifactDigest: ContentDigest("recovery-artifact"),
            exclusiveLeaseReceiptID: ReceiptID("rollback-lease"),
            remoteAccessDisabled: true,
            requestedAt: Date(timeIntervalSince1970: 16)
        )
    }

    private func rollbackReceipt() -> IntegrationRollbackReceipt {
        IntegrationRollbackReceipt(
            id: ReceiptID("rollback"),
            intentID: IntegrationEffectIntentID("rollback-intent"),
            transactionID: transactionID,
            rollbackManifestDigest: preflightAndRollback().0.rollbackManifestDigest,
            recoveryArtifactDigest: ContentDigest("recovery-artifact"),
            observedPreimageDigest: ContentDigest("preimage"),
            unchangedPathProofDigest: ContentDigest("rollback-unchanged"),
            executor: executor,
            completedAt: Date(timeIntervalSince1970: 17),
            outcome: .restored
        )
    }

    private func preparedState() throws -> IntegrationTransactionState {
        var state = try advance(nil, .propose(proposal()), actor: executor)
        let prepared = preflightAndRollback()
        state = try advance(
            state,
            .acceptPreflight(receipt: prepared.0, rollback: prepared.1),
            actor: executor
        )
        return state
    }

    private func appliedState() throws -> IntegrationTransactionState {
        var state = try preparedState()
        state = try advance(state, .startApply(applyIntent()), actor: executor)
        return try advance(state, .recordApply(applyReceipt()), actor: executor)
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
              let next = IntegrationTransactionReducer.reduce(
                current: current,
                event: event
              ) else {
            throw NSError(domain: "IntegrationTransactionStateMachineTests", code: 1)
        }
        return next
    }

    private func rejection(
        _ current: IntegrationTransactionState?,
        _ command: IntegrationTransitionCommand,
        actor: ActorIdentity
    ) -> IntegrationTransitionRejection? {
        let decision = IntegrationTransactionReducer.decide(
            current: current,
            command: command,
            actor: actor,
            knownReceiptIDs: current?.receiptIDs ?? [],
            knownIntentIDs: current?.intentIDs ?? []
        )
        guard case .failure(let rejection) = decision else { return nil }
        return rejection
    }

    private func contract() -> TaskContract {
        TaskContract(
            id: TaskContractID("contract-id"),
            schemaVersion: 1,
            verbatimObjective: "Apply one independently verified exact mutation.",
            objectiveDigest: ContentDigest("contract"),
            requirements: [RequirementContract(
                id: RequirementID("requirement"),
                statement: "Produce the accepted postimage.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("recipe")]
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: KernelAuthorityCeiling(
                readableScopes: ["file.txt"],
                writableScopes: ["file.txt"],
                capabilityIDs: [],
                permitsExternalPublication: false
            ),
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private var kernelProcessFixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/KernelProcessFixture")
            .standardizedFileURL.path
    }

    private func node() -> KernelNodeContract {
        KernelNodeContract(
            id: nodeID,
            requirementIDs: [RequirementID("requirement")],
            objective: "Construct one candidate",
            dependencies: [],
            mutationScope: KernelMutationScope(
                writablePaths: ["file.txt"],
                maximumChangedFiles: 1,
                maximumChangedBytes: 1
            ),
            capabilityIDs: [],
            strategyFingerprint: causalStrategy().fingerprint
        )
    }

    private func causalStrategy() -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [RequirementID("requirement")],
            hypothesisClass: "exact-mutation",
            actionClass: "construct-candidate",
            workspaceTopology: "single-file-workspace",
            capabilityRoute: [],
            evidenceSources: ["typed-verification"],
            measurementBoundary: "exact-postimage",
            verificationOracles: ["independent-review"],
            mutationSurfaceDigest: ContentDigest("file.txt"),
            baselineRevision: ContentDigest("preimage"),
            expectedObservationIDs: ["postimage-produced"],
            falsificationPredicateIDs: ["postimage-mismatch"],
            inheritedLessonDigests: []
        )
    }

    private func convergenceBudget() -> ConvergenceBudget {
        ConvergenceBudget(
            maximumAttempts: 2,
            maximumEquivalentFailures: 2,
            maximumStrategies: 2,
            maximumPlanExpansions: 1,
            maximumMutationCost: 2,
            maximumVerificationCost: 2,
            maximumDamageEvents: 1,
            maximumExternalEffects: 1
        )
    }

    private func causalAdmission() -> AttemptAdmissionRequest {
        AttemptAdmissionRequest(
            attemptID: attemptID,
            strategy: causalStrategy(),
            predictedObservationIDs: ["postimage-produced"],
            falsificationPredicateIDs: ["postimage-mismatch"],
            rollbackPoint: ContentDigest("preimage"),
            mutationCost: 1,
            verificationCost: 1,
            externalEffects: 0
        )
    }

    private static func makeTreeWritable(_ root: URL) {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            var paths: [URL] = []
            for case let child as URL in enumerator { paths.append(child) }
            for child in paths.reversed() {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: child.path
                )
            }
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
    }
}
