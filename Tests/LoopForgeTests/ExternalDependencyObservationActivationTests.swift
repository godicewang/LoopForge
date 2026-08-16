import Foundation
import XCTest
@testable import LoopForge

final class ExternalDependencyObservationActivationTests: XCTestCase {
    func testCoordinatorStagesAndJournalsInertInvocationWithoutLaunching()
        async throws {
        let root = try privateTemporaryDirectory()
        let workspace = try privateTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: workspace)
        }
        let runID = KernelRunID("activation-run")
        let attemptID = AttemptID("activation-attempt")
        let nodeID = KernelNodeID("activation-node")
        let requirementID = RequirementID("activation-requirement")
        let dependencyID = ExternalDependencyID("activation-dependency")
        let recipeID = ExternalDependencyEvidenceRecipeID(
            "activation-recipe"
        )
        let worker = ActorIdentity(
            id: ActorID("activation-worker"),
            role: "executor",
            lineageDigest: ContentDigest(String(repeating: "1", count: 64))
        )
        let observer = ActorIdentity(
            id: ActorID("activation-observer"),
            role: "external-observer",
            lineageDigest: ContentDigest(String(repeating: "2", count: 64))
        )
        let executablePath = "/bin/echo"
        var probe = externalDependencyObservationProbeFixture()
        probe.executableContentDigest = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: executablePath
            )
        )
        let canonicalWorkspace = workspace.standardizedFileURL
            .resolvingSymlinksInPath()
        let strategy = CausalStrategyDescriptor(
            requirementIDs: [requirementID],
            hypothesisClass: "dependency-observation",
            actionClass: "observe-dependency",
            workspaceTopology: "read-only-workspace",
            capabilityRoute: ["local-direct-process"],
            evidenceSources: ["external-dependency"],
            measurementBoundary: "dependency",
            verificationOracles: ["independent-observer"],
            mutationSurfaceDigest: ContentDigest("no-mutation"),
            baselineRevision: ContentDigest("activation-baseline"),
            expectedObservationIDs: ["dependency-observed"],
            falsificationPredicateIDs: ["dependency-unobserved"],
            inheritedLessonDigests: []
        )
        let contract = TaskContract(
            id: TaskContractID("activation-contract"),
            schemaVersion: 1,
            verbatimObjective: "Observe one declared external dependency.",
            objectiveDigest: ContentDigest("activation-objective"),
            requirements: [RequirementContract(
                id: requirementID,
                statement: "Observe the declared dependency.",
                mandatory: true,
                evidenceRecipeIDs: []
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            workspaceBinding: TaskContractWorkspaceBinding(
                workspaceID: WorkspaceID("activation-workspace"),
                canonicalRootDigest: WorkspaceRepositoryIndexer
                    .canonicalRootDigest(canonicalWorkspace)
            ),
            externalDependencies: [ExternalDependencyContract(
                id: dependencyID,
                kind: .authority,
                requirementIDs: [requirementID],
                evidenceRecipeID: recipeID,
                authorizedObserverLineageDigests: [
                    observer.lineageDigest
                ],
                executableProbe: probe
            )],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        var commandIndex = 0
        func transact(_ command: RunCommand, actor: ActorIdentity) async throws {
            commandIndex += 1
            _ = try await journal.transactAtCurrentSequence(
                command,
                commandID: RunCommandID("setup-\(commandIndex)"),
                issuedAt: Date(
                    timeIntervalSince1970: TimeInterval(commandIndex)
                ),
                actor: actor
            )
        }
        try await transact(.createRun(contract), actor: worker)
        try await transact(.proposePlan(KernelPlanProposal(
            contractDigest: contract.objectiveDigest,
            nodes: [KernelNodeContract(
                id: nodeID,
                requirementIDs: [requirementID],
                objective: "Observe dependency",
                dependencies: [],
                mutationScope: .readOnly,
                capabilityIDs: [],
                strategyFingerprint: strategy.fingerprint
            )]
        )), actor: worker)
        try await transact(.authorizeNode(nodeID), actor: observer)
        try await transact(.initializeConvergence(
            epochID: "activation-epoch",
            budget: ConvergenceBudget(
                maximumAttempts: 1,
                maximumEquivalentFailures: 1,
                maximumStrategies: 1,
                maximumPlanExpansions: 1,
                maximumMutationCost: 0,
                maximumVerificationCost: 1,
                maximumDamageEvents: 0,
                maximumExternalEffects: 1
            )
        ), actor: observer)
        try await transact(.admitCausalAttempt(AttemptAdmissionRequest(
            attemptID: attemptID,
            strategy: strategy,
            predictedObservationIDs: ["dependency-observed"],
            falsificationPredicateIDs: ["dependency-unobserved"],
            rollbackPoint: ContentDigest("activation-rollback"),
            mutationCost: 0,
            verificationCost: 1,
            externalEffects: 1
        )), actor: observer)
        try await transact(.startAttempt(
            attemptID: attemptID,
            nodeID: nodeID,
            requirementIDs: [requirementID],
            strategyFingerprint: strategy.fingerprint
        ), actor: worker)

        let request = ExternalDependencyObservationActivationRequest(
            receiptID: ReceiptID("activation-receipt"),
            commandID: RunCommandID("activate-observer"),
            dependencyID: dependencyID,
            observer: observer,
            executablePath: executablePath,
            workspaceRoot: canonicalWorkspace,
            activatedAt: Date(timeIntervalSince1970: 20)
        )
        let coordinator = ExternalDependencyObservationActivationCoordinator(
            journal: journal
        )
        let invocation = try await coordinator.activate(request)
        XCTAssertFalse(invocation.activationTransaction.duplicate)
        XCTAssertEqual(
            invocation.receipt.resolvedArguments,
            ["--request", "/dev/stdin"]
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: invocation.receipt.executableStaging.stagedExecutablePath
        ))
        let artifactPath = await journal.runDirectory.appendingPathComponent(
            invocation.receipt.requestArtifact.fileName
        ).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath))
        let activatedState = await journal.state
        XCTAssertTrue(activatedState.runtimeLiveLeases.isEmpty)
        XCTAssertTrue(
            (activatedState.externalDependencyReceipts ?? [:])
                .isEmpty
        )
        XCTAssertEqual(
            activatedState.externalDependencyObservationActivationReceipts?[
                invocation.receipt.id
            ],
            invocation.receipt
        )

        let readinessRequest =
            ExternalDependencyObservationLaunchReadinessRequest(
                vetoReceiptID: ReceiptID("activation-launch-veto"),
                vetoCommandID: RunCommandID("activation-launch-veto-command"),
                observedAt: Date(timeIntervalSince1970: 21)
            )
        let readinessCoordinator =
            ExternalDependencyObservationLaunchReadinessCoordinator(
                journal: journal
            )
        let readiness = try await readinessCoordinator.evaluate(
            invocation: invocation,
            request: readinessRequest,
            residentMemoryEnforcement:
                .testOnly(externalDependencyActivation: invocation.receipt)
        )
        guard case .ready(let authority) = readiness else {
            return XCTFail("expected exact test-only containment readiness")
        }
        XCTAssertEqual(authority.invocation.receipt, invocation.receipt)
        XCTAssertTrue(authority.residentMemoryEnforcement.authorizes(
            externalDependencyActivation: invocation.receipt
        ))
        var crosswiredActivation = invocation.receipt
        crosswiredActivation.id = ReceiptID("other-activation")
        let crosswiredContainment = AuthorizedKernelResidentMemoryEnforcement
            .testOnly(externalDependencyActivation: crosswiredActivation)
        do {
            _ = try await readinessCoordinator.evaluate(
                invocation: invocation,
                request: readinessRequest,
                residentMemoryEnforcement: crosswiredContainment
            )
            XCTFail("expected crosswired containment rejection")
        } catch let error as
                    ExternalDependencyObservationLaunchReadinessError {
            XCTAssertEqual(error, .containmentAuthorityMismatch)
        }

        let vetoDecision = try await readinessCoordinator.evaluate(
            invocation: invocation,
            request: readinessRequest
        )
        guard case .vetoed(let veto, let vetoTransaction) = vetoDecision else {
            return XCTFail("expected missing-containment veto")
        }
        XCTAssertFalse(vetoTransaction.duplicate)
        XCTAssertEqual(veto.activationReceiptID, invocation.receipt.id)
        XCTAssertEqual(
            veto.reason,
            .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
        )
        XCTAssertEqual(
            veto.requiredMaximumResidentBytes,
            invocation.receipt.resourceLimits.maximumResidentBytes
        )
        let vetoedState = await journal.state
        XCTAssertEqual(
            vetoedState.externalDependencyObservationLaunchVetoReceipts?[
                veto.id
            ],
            veto
        )
        XCTAssertTrue(vetoedState.runtimeAdmissionReceipts.isEmpty)
        XCTAssertTrue(vetoedState.runtimeLiveLeases.isEmpty)
        XCTAssertTrue(
            (vetoedState.externalDependencyReceipts ?? [:]).isEmpty
        )
        let retriedVetoDecision = try await readinessCoordinator.evaluate(
            invocation: invocation,
            request: readinessRequest
        )
        guard case .vetoed(
            let retriedVeto,
            let retriedVetoTransaction
        ) = retriedVetoDecision else {
            return XCTFail("expected exact veto retry")
        }
        XCTAssertEqual(retriedVeto, veto)
        XCTAssertEqual(retriedVetoTransaction, vetoTransaction)

        let replayed = try await coordinator.activate(request)
        XCTAssertEqual(
            replayed.activationTransaction,
            invocation.activationTransaction
        )
        XCTAssertEqual(replayed.receipt, invocation.receipt)
        XCTAssertEqual(
            replayed.requestArtifact.receipt,
            invocation.requestArtifact.receipt
        )
        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let recoveredState = await recovered.state
        XCTAssertEqual(
            recoveredState.externalDependencyObservationActivationReceipts?[
                invocation.receipt.id
            ],
            invocation.receipt
        )
        XCTAssertEqual(
            recoveredState.externalDependencyObservationLaunchVetoReceipts?[
                veto.id
            ],
            veto
        )
    }

    func testRequestArtifactIsCanonicalImmutableAndCrashReplayable() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let envelope = requestEnvelope()
        let receiptID = ReceiptID("activation-receipt")
        let issuer = ExternalDependencyObservationRequestArtifactIssuer()

        let issued = try issuer.materialize(
            envelope: envelope,
            receiptID: receiptID,
            journalRunDirectory: directory
        )
        let artifactURL = directory.appendingPathComponent(
            issued.receipt.fileName,
            isDirectory: false
        )
        let data = try Data(contentsOf: artifactURL)
        XCTAssertEqual(data.last, 0x0a)
        XCTAssertEqual(
            data,
            try ExternalDependencyObservationRequestArtifactIssuer
                .canonicalData(envelope)
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: artifactURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            0o400
        )

        let replayed = try issuer.materialize(
            envelope: envelope,
            receiptID: receiptID,
            journalRunDirectory: directory
        )
        XCTAssertEqual(replayed.receipt, issued.receipt)
        XCTAssertEqual(
            try issuer.revalidate(
                expectedEnvelope: envelope,
                receiptID: receiptID,
                journalRunDirectory: directory,
                matching: issued.receipt
            ).receipt,
            issued.receipt
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o750],
            ofItemAtPath: directory.path
        )
        XCTAssertThrowsError(try issuer.revalidate(
            expectedEnvelope: envelope,
            receiptID: receiptID,
            journalRunDirectory: directory,
            matching: issued.receipt
        )) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationRequestArtifactError,
                .invalidRunDirectory
            )
        }
    }

    func testRequestArtifactRejectsTamperingAndSymlinkPreseed() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let envelope = requestEnvelope()
        let receiptID = ReceiptID("tamper-receipt")
        let issuer = ExternalDependencyObservationRequestArtifactIssuer()
        let issued = try issuer.materialize(
            envelope: envelope,
            receiptID: receiptID,
            journalRunDirectory: directory
        )
        let artifactURL = directory.appendingPathComponent(
            issued.receipt.fileName,
            isDirectory: false
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: artifactURL.path
        )
        try Data("tampered\n".utf8).write(to: artifactURL)

        XCTAssertThrowsError(try issuer.revalidate(
            expectedEnvelope: envelope,
            receiptID: receiptID,
            journalRunDirectory: directory,
            matching: issued.receipt
        )) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationRequestArtifactError,
                .existingArtifactMismatch
            )
        }

        let symlinkDirectory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: symlinkDirectory) }
        let symlinkReceiptID = ReceiptID("symlink-receipt")
        let target = symlinkDirectory.appendingPathComponent("target")
        try Data("target".utf8).write(to: target)
        let link = symlinkDirectory.appendingPathComponent(
            ExternalDependencyObservationRequestArtifactIssuer.fileName(
                receiptID: symlinkReceiptID
            )
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )
        XCTAssertThrowsError(try issuer.materialize(
            envelope: envelope,
            receiptID: symlinkReceiptID,
            journalRunDirectory: symlinkDirectory
        )) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationRequestArtifactError,
                .existingArtifactMismatch
            )
        }
    }

    func testRequestArtifactRejectsGroupAccessibleRunDirectory() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o750],
            ofItemAtPath: directory.path
        )

        XCTAssertThrowsError(
            try ExternalDependencyObservationRequestArtifactIssuer()
                .materialize(
                    envelope: requestEnvelope(),
                    receiptID: ReceiptID("unsafe-directory"),
                    journalRunDirectory: directory
                )
        ) { error in
            XCTAssertEqual(
                error as? ExternalDependencyObservationRequestArtifactError,
                .invalidRunDirectory
            )
        }
    }

    func testOrdinaryMacOSMemoryVetoIsExplicitAndSchemaCompatible()
        throws {
        let reason =
            KernelResidentMemoryEnforcementUnavailabilityReason
            .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
        XCTAssertEqual(
            reason.rawValue,
            "residentMemoryEnforcementUnavailable"
        )
        XCTAssertEqual(
            KernelProductionMutationApplyVetoReason
                .ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit
                .rawValue,
            "containmentReadinessUnavailable"
        )
        XCTAssertEqual(
            try JSONDecoder.loopForge.decode(
                KernelResidentMemoryEnforcementUnavailabilityReason.self,
                from: JSONEncoder.loopForge.encode(reason)
            ),
            reason
        )

        switch KernelResidentMemoryEnforcementResolution
            .ordinaryMacOSUnavailable {
        case .unavailable(let retainedReason):
            XCTAssertEqual(retainedReason, reason)
        case .authorized:
            XCTFail("ordinary macOS must not mint memory authority")
        }
        switch KernelPostimageContainmentReadinessResolution
            .ordinaryMacOSUnavailable {
        case .unavailable(let retainedReason):
            XCTAssertEqual(retainedReason, reason)
        case .authorized:
            XCTFail("ordinary macOS must not mint contract readiness")
        }
    }

    private func requestEnvelope()
        -> ExternalDependencyObservationRequestEnvelope {
        ExternalDependencyObservationRequestEnvelope(
            attemptID: AttemptID("attempt"),
            dependencyID: ExternalDependencyID("dependency"),
            evidenceRecipeID: ExternalDependencyEvidenceRecipeID("recipe"),
            observerLineageDigest: ContentDigest(
                String(repeating: "a", count: 64)
            ),
            requestNonce: ContentDigest(String(repeating: "b", count: 64)),
            runID: KernelRunID("run"),
            schemaVersion: 1,
            sourceJournalFrameDigest: ContentDigest(
                String(repeating: "c", count: 64)
            ),
            sourceJournalSequence: 7
        )
    }

    private func privateTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        return directory
    }
}
