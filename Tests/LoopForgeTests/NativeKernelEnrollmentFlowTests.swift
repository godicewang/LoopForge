import Foundation
import XCTest
@testable import LoopForge

@MainActor
final class NativeKernelEnrollmentFlowTests: XCTestCase {
    func testAutoGraphNativeConfirmationEnrollsReadyRunWithoutLegacyStart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(model, objective: "Preserve the exact design baseline.")

        model.startWithOriginalPrompt()

        let draft = try XCTUnwrap(model.pendingNativeContractConfirmation)
        XCTAssertEqual(draft.displayObjective, "Preserve the exact design baseline.")
        XCTAssertEqual(draft.displayWorkspacePath, fixture.workspace.path)
        XCTAssertEqual(draft.displayReadableScopes, ["."])
        XCTAssertEqual(draft.displayWritableScopes, ["."])
        XCTAssertEqual(draft.displayExecutionProfile.worker.sandbox, .workspaceOnly)
        XCTAssertEqual(draft.displayExecutionProfile.worker.networkPolicy, .disabled)
        XCTAssertEqual(
            draft.displayExecutionProfile.independentReviewer.sandbox,
            .readOnly
        )
        XCTAssertTrue(draft.displayExecutionProfile.requiresDistinctActorLineage)
        XCTAssertEqual(
            draft.displayExecutionBudgets.mutation.maximumChangedFiles,
            32
        )
        XCTAssertEqual(
            draft.displayExecutionBudgets.convergence.maximumAttempts,
            3
        )
        XCTAssertTrue(draft.displaySourceRevision.validationIssues().isEmpty)
        XCTAssertEqual(draft.displaySourceRevision.entries.count, 0)
        XCTAssertTrue(draft.compiled.candidate.contract.hasValidInitialExecutionAuthority)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertNil(model.controller.runningTaskID)

        await model.confirmAndEnrollNativeAutoGraphContract()

        let receipt = try XCTUnwrap(
            model.latestKernelEnrollmentReceipt,
            model.alertMessage ?? "missing enrollment receipt without an alert"
        )
        XCTAssertEqual(receipt.kernelProjection.phase, .ready)
        let journal = try RunJournal(
            rootDirectory: receipt.registration.journalRoot,
            runID: receipt.runID
        )
        let journaledContract = await journal.currentContract()
        XCTAssertEqual(
            journaledContract?.executionProfile,
            draft.displayExecutionProfile
        )
        XCTAssertEqual(
            journaledContract?.requirementEvidenceRecipes,
            draft.compiled.candidate.evidenceRecipes
        )
        XCTAssertEqual(
            journaledContract?.executionBudgets,
            draft.displayExecutionBudgets
        )
        XCTAssertEqual(
            journaledContract?.sourceRevision,
            draft.displaySourceRevision
        )
        XCTAssertEqual(
            journaledContract?.initialCausalStrategyAuthority,
            draft.displayCausalStrategyAuthority
        )
        XCTAssertEqual(
            journaledContract?.initialExecutionPlan,
            draft.displayExecutionPlan
        )
        XCTAssertEqual(journaledContract?.hasValidInitialExecutionAuthority, true)
        XCTAssertEqual(
            journaledContract?.hasCompleteRequirementEvidenceRecipeProvenance,
            true
        )
        XCTAssertEqual(model.kernelRunProjections, [receipt.kernelProjection])
        XCTAssertNil(model.pendingNativeContractConfirmation)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertNil(model.controller.runningTaskID)
        let registrations = try await fixture.registry.registrations(limit: 8)
        XCTAssertEqual(registrations.map(\.runID), [receipt.runID])
        XCTAssertEqual(registrations.first?.workspaceRoot, fixture.workspace)
        XCTAssertEqual(registrations.first, receipt.registration)
        let readiness = try XCTUnwrap(
            model.latestKernelExecutionReadiness,
            model.alertMessage ?? "missing readiness without an alert"
        )
        XCTAssertEqual(readiness.runID, receipt.runID)
        XCTAssertEqual(readiness.contractID, receipt.contractID)
        XCTAssertEqual(
            readiness.sourceJournalSequence,
            receipt.journalTransaction.endingSequence
        )
        XCTAssertEqual(
            readiness.sourceJournalFrameDigest,
            receipt.journalTransaction.frameDigest
        )
        XCTAssertEqual(readiness.phase, .ready)
        XCTAssertFalse(readiness.canPrepareAndActivate)
        XCTAssertEqual(
            Set(readiness.blockers),
            [
                .preApplyCandidateIsolationAuthorityMissing,
                .journaledMutationPreparationAuthorityMissing
            ]
        )
        let unchangedJournal = try RunJournal(
            rootDirectory: receipt.registration.journalRoot,
            runID: receipt.runID
        )
        let unchangedProjection = await unchangedJournal.currentProjection()
        XCTAssertEqual(unchangedProjection, receipt.kernelProjection)

        await model.activateLatestEnrolledKernelRun()

        XCTAssertNil(model.latestKernelExecutionSessionReceipt)
        XCTAssertNil(model.controller.runningTaskID)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertTrue(
            model.alertMessage?.contains("blocked by 2 missing authority receipts")
                == true
        )
        let stillUnchangedProjection = await unchangedJournal.currentProjection()
        XCTAssertEqual(stillUnchangedProjection, receipt.kernelProjection)
    }

    func testExplicitReadOnlyActivationUsesEnrolledAuthorityWithoutLegacyStart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Observe the exact accepted revision without mutation."
        )
        model.draftAccessMode = .readOnly

        model.startWithOriginalPrompt()

        let draft = try XCTUnwrap(model.pendingNativeContractConfirmation)
        XCTAssertEqual(draft.displayReadableScopes, ["."])
        XCTAssertEqual(draft.displayWritableScopes, [])
        XCTAssertEqual(draft.displayExecutionProfile.worker.sandbox, .readOnly)
        XCTAssertEqual(
            draft.displayExecutionBudgets.mutation,
            KernelMutationBudget(
                maximumChangedFiles: 0,
                maximumChangedBytes: 0
            )
        )
        XCTAssertEqual(
            draft.displayExecutionBudgets.convergence.maximumMutationCost,
            0
        )

        await model.confirmAndEnrollNativeAutoGraphContract()

        let enrollment = try XCTUnwrap(model.latestKernelEnrollmentReceipt)
        let readiness = try XCTUnwrap(model.latestKernelExecutionReadiness)
        XCTAssertTrue(readiness.canPrepareAndActivate)
        XCTAssertTrue(readiness.blockers.isEmpty)
        XCTAssertFalse(
            readiness.providerInvocationProfileReadiness
                .canCompileProviderInvocation
        )
        XCTAssertEqual(
            readiness.providerInvocationProfileReadiness.blockers,
            [
                .providerHarnessProtocolUnavailable,
                .remoteProviderNetworkAuthorityMissing,
            ]
        )
        XCTAssertEqual(enrollment.kernelProjection.phase, .ready)

        await model.activateLatestEnrolledKernelRun()

        let activation = try XCTUnwrap(
            model.latestKernelExecutionSessionReceipt,
            model.alertMessage ?? "missing native activation receipt"
        )
        XCTAssertEqual(activation.kernelProjection.phase, .executing)
        XCTAssertEqual(activation.preparation.runID, enrollment.runID)
        XCTAssertEqual(activation.preparation.contractID, enrollment.contractID)
        XCTAssertEqual(activation.preparation.plan, draft.displayExecutionPlan)
        XCTAssertEqual(
            activation.preparation.admission.strategy,
            draft.displayCausalStrategyAuthority.descriptor
        )
        XCTAssertEqual(activation.preparation.admission.mutationCost, 0)
        XCTAssertEqual(activation.preparation.admission.verificationCost, 1)
        XCTAssertEqual(activation.preparation.admission.externalEffects, 0)
        XCTAssertNil(activation.preApplyCandidateIsolation)
        XCTAssertEqual(
            activation.providerInvocationProfileReadiness,
            readiness.providerInvocationProfileReadiness
        )
        XCTAssertNil(model.latestKernelExecutionReadiness)
        XCTAssertEqual(
            model.kernelProviderInvocationReadinessByRunID[enrollment.runID],
            readiness.providerInvocationProfileReadiness
        )
        XCTAssertNil(model.controller.runningTaskID)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertEqual(
            model.kernelRunProjections,
            [activation.kernelProjection]
        )

        let journal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let state = await journal.state
        XCTAssertEqual(state.phase, .executing)
        XCTAssertEqual(state.sequence, activation.kernelProjection.sequence)
        XCTAssertEqual(
            state.convergenceGovernor?.admittedRequest(
                for: activation.preparation.admission.attemptID
            ),
            activation.preparation.admission
        )
        XCTAssertEqual(
            state.nodes[activation.preparation.nodeID]?.status,
            .executing
        )
        XCTAssertTrue(
            model.alertMessage?.contains(
                "provider invocation is blocked by 2 exact profile constraints"
            ) == true
        )
    }

    func testRelaunchRecoversNewestReadyReadOnlyEnrollmentAndCanActivateIt()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalModel = fixture.model()
        fixture.configureAutoGraph(
            originalModel,
            objective: "Resume only the exact durable read-only enrollment."
        )
        originalModel.draftAccessMode = .readOnly
        originalModel.startWithOriginalPrompt()
        await originalModel.confirmAndEnrollNativeAutoGraphContract()
        let original = try XCTUnwrap(
            originalModel.latestKernelEnrollmentReceipt
        )

        let recoveryReport = try await WorkspaceMutationRecoveryCoordinator(
            registry: fixture.registry
        ).recoverRegisteredRuns()
        let directlyRecovered = try await fixture.executionCoordinator
            .recoverReadyEnrollment(runID: original.runID)
        XCTAssertEqual(directlyRecovered, original)
        let recoveredModel = fixture.model(
            recoveryTask: Task { recoveryReport }
        )
        for _ in 0..<200 {
            if recoveredModel.latestKernelEnrollmentReceipt != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let recovered = try XCTUnwrap(
            recoveredModel.latestKernelEnrollmentReceipt
        )
        XCTAssertEqual(recovered, original)
        XCTAssertEqual(
            recoveredModel.latestKernelExecutionReadiness?.canPrepareAndActivate,
            true
        )
        XCTAssertTrue(recoveredModel.store.tasks.isEmpty)
        XCTAssertNil(recoveredModel.controller.runningTaskID)

        await recoveredModel.activateLatestEnrolledKernelRun()

        XCTAssertEqual(
            recoveredModel.latestKernelExecutionSessionReceipt?
                .kernelProjection.phase,
            .executing
        )
        XCTAssertTrue(recoveredModel.store.tasks.isEmpty)
        XCTAssertNil(recoveredModel.controller.runningTaskID)
    }

    func testExecutingRunCannotReconstructAReadyEnrollmentCapability()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Do not recreate live execution authority after launch."
        )
        model.draftAccessMode = .readOnly
        model.startWithOriginalPrompt()
        await model.confirmAndEnrollNativeAutoGraphContract()
        let enrollment = try XCTUnwrap(model.latestKernelEnrollmentReceipt)
        await model.activateLatestEnrolledKernelRun()
        XCTAssertNotNil(model.latestKernelExecutionSessionReceipt)

        do {
            _ = try await fixture.executionCoordinator
                .recoverReadyEnrollment(runID: enrollment.runID)
            XCTFail("an executing run must not recover a ready capability")
        } catch let error as KernelNativeExecutionReadinessError {
            XCTAssertEqual(error, .recoveredEnrollmentUnavailable)
        }
    }

    func testRelaunchAutomaticallyInterruptsExactEmptyCleanupExecution()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalModel = fixture.model()
        fixture.configureAutoGraph(
            originalModel,
            objective: "Recover cleanup ownership without productive authority."
        )
        originalModel.draftAccessMode = .readOnly
        originalModel.startWithOriginalPrompt()
        await originalModel.confirmAndEnrollNativeAutoGraphContract()
        let enrollment = try XCTUnwrap(
            originalModel.latestKernelEnrollmentReceipt
        )
        await originalModel.activateLatestEnrolledKernelRun()
        XCTAssertEqual(
            originalModel.latestKernelExecutionSessionReceipt?
                .kernelProjection.phase,
            .executing
        )

        let recoveryReport = try await WorkspaceMutationRecoveryCoordinator(
            registry: fixture.registry
        ).recoverRegisteredRuns()
        XCTAssertEqual(
            recoveryReport.runReports.first(where: {
                $0.runID == enrollment.runID
            })?.kernelProjection?.phase,
            .executing
        )
        let recoveredModel = fixture.model(
            recoveryTask: Task { recoveryReport }
        )
        for _ in 0..<200 {
            if recoveredModel.kernelRunProjections.first(where: {
                $0.runID == enrollment.runID
            })?.phase == .stopped {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertFalse(recoveredModel.hasActiveKernelExecutionSessions)
        XCTAssertNil(recoveredModel.latestKernelExecutionSessionReceipt)
        XCTAssertNil(recoveredModel.latestKernelEnrollmentReceipt)

        let recoveredJournal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let state = await recoveredJournal.state
        let projection = await recoveredJournal.currentProjection()
        XCTAssertEqual(state.phase, .stopped)
        XCTAssertEqual(
            state.attempts.values.first?.disposition,
            .interrupted
        )
        XCTAssertEqual(projection.phase, .stopped)
        XCTAssertTrue(projection.quiescent)
        XCTAssertTrue(
            state.runtimeDrainReceipts.values.contains(where: {
                $0.id.rawValue.hasPrefix("native-crash-recovery-")
            })
        )
        XCTAssertTrue(
            state.quiescenceReceipt?.id.rawValue.hasPrefix(
                "native-crash-recovery-"
            ) == true
        )

        do {
            _ = try await fixture.executionCoordinator
                .recoverApplicationTerminationSession(runID: enrollment.runID)
            XCTFail("a stopped run must not recover cleanup ownership")
        } catch let error as KernelRecoveredApplicationTerminationError {
            XCTAssertEqual(error, .recoveryUnavailable)
        }
    }

    func testRelaunchVetoesQuitWhenCleanupOwnershipCannotMatchJournal()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalModel = fixture.model()
        fixture.configureAutoGraph(
            originalModel,
            objective: "Fail closed when startup cleanup evidence is stale."
        )
        originalModel.draftAccessMode = .readOnly
        originalModel.startWithOriginalPrompt()
        await originalModel.confirmAndEnrollNativeAutoGraphContract()
        let enrollment = try XCTUnwrap(
            originalModel.latestKernelEnrollmentReceipt
        )
        await originalModel.activateLatestEnrolledKernelRun()

        let staleExecutingReport = try await WorkspaceMutationRecoveryCoordinator(
            registry: fixture.registry
        ).recoverRegisteredRuns()
        XCTAssertEqual(
            staleExecutingReport.runReports.first?.kernelProjection?.phase,
            .executing
        )
        let originalTerminationReady = await originalModel
            .prepareKernelSessionsForApplicationTermination()
        XCTAssertTrue(originalTerminationReady)
        let stoppedJournal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let stoppedSequence = await stoppedJournal.state.sequence
        let stoppedFrame = await stoppedJournal.recoveryReport.lastFrameDigest

        let recoveredModel = fixture.model(
            recoveryTask: Task { staleExecutingReport }
        )
        for _ in 0..<200 {
            if recoveredModel.hasActiveKernelExecutionSessions { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(recoveredModel.hasActiveKernelExecutionSessions)
        let terminationReady = await recoveredModel
            .prepareKernelSessionsForApplicationTermination()
        XCTAssertFalse(terminationReady)
        XCTAssertTrue(
            recoveredModel.alertMessage?.contains(
                "exact receipt-bound cleanup ownership could not be reconstructed"
            ) == true
        )
        let unchangedJournal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let unchangedSequence = await unchangedJournal.state.sequence
        let unchangedFrame = await unchangedJournal.recoveryReport.lastFrameDigest
        XCTAssertEqual(unchangedSequence, stoppedSequence)
        XCTAssertEqual(unchangedFrame, stoppedFrame)
    }

    func testApplicationTerminationStopsQuiescentNativeAttemptWithoutRecreatingAuthority()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Stop an activated native attempt before application exit."
        )
        model.draftAccessMode = .readOnly
        model.startWithOriginalPrompt()
        await model.confirmAndEnrollNativeAutoGraphContract()
        let enrollment = try XCTUnwrap(model.latestKernelEnrollmentReceipt)
        await model.activateLatestEnrolledKernelRun()

        XCTAssertTrue(model.hasActiveKernelExecutionSessions)
        XCTAssertEqual(
            model.latestKernelExecutionSessionReceipt?.kernelProjection.phase,
            .executing
        )
        let terminationReady = await model
            .prepareKernelSessionsForApplicationTermination()
        XCTAssertTrue(terminationReady)
        XCTAssertFalse(model.hasActiveKernelExecutionSessions)
        XCTAssertNil(model.latestKernelExecutionSessionReceipt)

        let journal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let state = await journal.state
        let projection = await journal.currentProjection()
        XCTAssertEqual(state.phase, .stopped)
        XCTAssertNil(state.activeAttemptID)
        XCTAssertEqual(
            state.attempts.values.first?.disposition,
            .interrupted
        )
        XCTAssertEqual(projection.phase, .stopped)
        XCTAssertTrue(projection.quiescent)

        do {
            _ = try await fixture.executionCoordinator
                .recoverReadyEnrollment(runID: enrollment.runID)
            XCTFail("a stopped run must not recreate ready execution authority")
        } catch let error as KernelNativeExecutionReadinessError {
            XCTAssertEqual(error, .recoveredEnrollmentUnavailable)
        }
    }

    func testApplicationTerminationResumesPreviouslyJournaledStopRequest()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Resume termination after a retained stop boundary."
        )
        model.draftAccessMode = .readOnly
        model.startWithOriginalPrompt()
        await model.confirmAndEnrollNativeAutoGraphContract()
        let enrollment = try XCTUnwrap(model.latestKernelEnrollmentReceipt)
        let activationNonce = UUID().uuidString.lowercased()
        let session = try await fixture.executionCoordinator
            .activateNativeEnrolledRun(
                KernelNativeExecutionStartRequest(
                    enrollment: enrollment,
                    designBaseline: nil,
                    requestNonce: activationNonce,
                    initiatedAt: Date()
                )
            )
        try await session.testOnlyRequestStopWithoutRuntimeDrain(
            commandID: RunCommandID("interrupted-quit-stop-request"),
            issuedAt: Date()
        )
        let retained = await session.kernelProjection()
        XCTAssertEqual(retained.phase, .stopRequested)
        XCTAssertNotNil(retained.activeAttemptID)
        XCTAssertNil(retained.runtimeDrainIntent)

        let recoveryReport = try await WorkspaceMutationRecoveryCoordinator(
            registry: fixture.registry
        ).recoverRegisteredRuns()
        XCTAssertEqual(
            recoveryReport.runReports.first(where: {
                $0.runID == enrollment.runID
            })?.kernelProjection?.phase,
            .stopRequested
        )
        let recoveredModel = fixture.model(
            recoveryTask: Task { recoveryReport }
        )
        for _ in 0..<200 {
            if recoveredModel.kernelRunProjections.first(where: {
                $0.runID == enrollment.runID
            })?.phase == .stopped { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(recoveredModel.hasActiveKernelExecutionSessions)
        let projection = try XCTUnwrap(
            recoveredModel.kernelRunProjections.first(where: {
                $0.runID == enrollment.runID
            })
        )
        XCTAssertEqual(projection.phase, .stopped)
        XCTAssertTrue(projection.quiescent)
        XCTAssertNil(projection.activeAttemptID)

        let journal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let state = await journal.state
        XCTAssertEqual(state.phase, .stopped)
        XCTAssertEqual(
            state.attempts.values.first?.disposition,
            .interrupted
        )
        XCTAssertTrue(
            state.quiescenceReceipt?.id.rawValue.hasPrefix(
                "native-crash-recovery-"
            ) == true
        )
    }

    func testNativeActivationRejectsUnboundRequestIdentityWithoutJournalAdvance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Observe only after an exact native start action."
        )
        model.draftAccessMode = .readOnly
        model.startWithOriginalPrompt()
        await model.confirmAndEnrollNativeAutoGraphContract()

        let enrollment = try XCTUnwrap(model.latestKernelEnrollmentReceipt)
        let journal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let before = await journal.currentProjection()

        do {
            _ = try await fixture.executionCoordinator
                .activateNativeEnrolledRun(
                    KernelNativeExecutionStartRequest(
                        enrollment: enrollment,
                        designBaseline: nil,
                        requestNonce: "caller-chosen-plan",
                        initiatedAt: Date()
                    )
                )
            XCTFail("An invalid native action identity must not activate")
        } catch let error as KernelNativeExecutionStartError {
            XCTAssertEqual(error, .invalidRequestIdentity)
        }

        let after = await journal.currentProjection()
        XCTAssertEqual(after, before)
        XCTAssertNil(model.latestKernelExecutionSessionReceipt)
        XCTAssertNil(model.controller.runningTaskID)
        XCTAssertTrue(model.store.tasks.isEmpty)
    }

    func testAutoGraphAuthoringWithoutExecutableProbeFailsBeforeConfirmation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Do not invent verification authority."
        )
        model.setNativeVerificationProbe(nil)

        model.startWithOriginalPrompt()

        XCTAssertNil(model.pendingNativeContractConfirmation)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertNil(model.controller.runningTaskID)
        XCTAssertTrue(
            model.alertMessage?.contains("Executable verification is not yet configured")
                == true
        )
    }

    func testOptimizedAutoGraphTextIsRecordedAsAcceptedAmendment() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(model, objective: "Original user objective.")
        let optimized = PromptOptimizationCandidate(
            id: "candidate",
            title: "Evidence focused",
            prompt: "Accepted model-authored revision.",
            emphasis: "Exact evidence"
        )

        model.startWithOptimizedPrompt(optimized)

        let draft = try XCTUnwrap(model.pendingNativeContractConfirmation)
        let source = try XCTUnwrap(draft.compiled.candidate.sources.first {
            $0.id == draft.compiled.candidate.initialObjectiveSourceID
        })
        XCTAssertEqual(source.authority, .acceptedUserAmendment)
        XCTAssertEqual(draft.displayObjective, optimized.prompt)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertNil(model.controller.runningTaskID)
        model.cancelNativeContractConfirmation()
        XCTAssertNil(model.pendingNativeContractConfirmation)
    }

    func testCancellingNativeConfirmationCreatesNoJournalOrRegistration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let model = fixture.model()
        fixture.configureAutoGraph(model, objective: "Review without enrolling.")

        model.startWithOriginalPrompt()
        XCTAssertNotNil(model.pendingNativeContractConfirmation)
        model.cancelNativeContractConfirmation()

        XCTAssertNil(model.pendingNativeContractConfirmation)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertNil(model.controller.runningTaskID)
        let registrations = try await fixture.registry.registrations(limit: 8)
        XCTAssertTrue(registrations.isEmpty)
        let runsRoot = fixture.registryRoot.appendingPathComponent(
            "runs",
            isDirectory: true
        )
        let children = try FileManager.default.contentsOfDirectory(
            at: runsRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(children.isEmpty)
    }

    @MainActor
    func testConfirmedVerifierIsImportedAtEnrollmentAndSourceLosesAuthority()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let verifier = fixture.container.appendingPathComponent("verifier")
        let manifestURL = fixture.container.appendingPathComponent(
            "verifier-manifest.json"
        )
        try Data("exact-verifier-v1".utf8).write(to: verifier)
        XCTAssertEqual(chmod(verifier.path, 0o755), 0)
        let manifest = NativeVerificationProbeManifest(
            schemaVersion: 1,
            executablePath: verifier.path,
            fixedArguments: [
                "@loopforge-input:candidate-postimage"
            ],
            resultMappings: [
                RequirementVerificationResultMapping(
                    exitCode: 0,
                    parserResultCode: "accepted",
                    outcome: .accepted
                ),
                RequirementVerificationResultMapping(
                    exitCode: 1,
                    parserResultCode: "rejected",
                    outcome: .rejected
                )
            ],
            maximumWallClockSeconds: 30,
            maximumCapturedOutputBytes: 1_048_576,
            maximumResidentBytes: 134_217_728
        )
        try JSONEncoder.loopForge.encode(manifest).write(
            to: manifestURL,
            options: .atomic
        )
        let selection = try NativeVerificationProbeSelectionLoader.load(
            manifestURL: manifestURL
        )

        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Retain the exact confirmed verifier bytes."
        )
        model.setNativeVerificationProbeSelection(selection)
        model.calculateEstimate()
        model.startWithOriginalPrompt()
        await model.confirmAndEnrollNativeAutoGraphContract()

        let enrollment = try XCTUnwrap(
            model.latestKernelEnrollmentReceipt,
            model.alertMessage ?? "missing enrollment receipt"
        )
        let imported = try XCTUnwrap(
            enrollment.verificationExecutableStaging
        )
        XCTAssertEqual(imported.count, 1)
        let staging = try XCTUnwrap(imported.first)
        XCTAssertEqual(staging.sourceExecutablePath, verifier.path)
        XCTAssertEqual(
            staging.contentDigest,
            selection.probe.executableContentDigest
        )
        XCTAssertTrue(staging.stagedExecutablePath.hasPrefix(
            enrollment.registration.journalRoot.path + "/"
        ))

        try Data("substituted-verifier-v2".utf8).write(
            to: verifier,
            options: .atomic
        )
        XCTAssertEqual(chmod(verifier.path, 0o755), 0)
        XCTAssertNotEqual(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: verifier.path
            ),
            selection.probe.executableContentDigest
        )

        let journal = try RunJournal(
            rootDirectory: enrollment.registration.journalRoot,
            runID: enrollment.runID
        )
        let resolved = try KernelExecutableStager().resolveStaged(
            expectedDigest: selection.probe.executableContentDigest,
            runDirectory: await journal.runDirectory
        )
        XCTAssertEqual(resolved.stagedExecutablePath, staging.stagedExecutablePath)
        XCTAssertEqual(resolved.deviceID, staging.deviceID)
        XCTAssertEqual(resolved.inode, staging.inode)
        XCTAssertEqual(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: resolved.stagedExecutablePath
            ),
            selection.probe.executableContentDigest
        )
    }

    @MainActor
    func testSelectedVerifierDriftBeforeConfirmationEnrollsNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let verifier = fixture.container.appendingPathComponent("verifier")
        let manifestURL = fixture.container.appendingPathComponent(
            "verifier-manifest.json"
        )
        try Data("exact-verifier-v1".utf8).write(to: verifier)
        XCTAssertEqual(chmod(verifier.path, 0o755), 0)
        let manifest = NativeVerificationProbeManifest(
            schemaVersion: 1,
            executablePath: verifier.path,
            fixedArguments: [
                "@loopforge-input:candidate-postimage"
            ],
            resultMappings: [
                RequirementVerificationResultMapping(
                    exitCode: 0,
                    parserResultCode: "accepted",
                    outcome: .accepted
                ),
                RequirementVerificationResultMapping(
                    exitCode: 1,
                    parserResultCode: "rejected",
                    outcome: .rejected
                )
            ],
            maximumWallClockSeconds: 30,
            maximumCapturedOutputBytes: 1_048_576,
            maximumResidentBytes: 134_217_728
        )
        try JSONEncoder.loopForge.encode(manifest).write(
            to: manifestURL,
            options: .atomic
        )
        let selection = try NativeVerificationProbeSelectionLoader.load(
            manifestURL: manifestURL
        )

        let model = fixture.model()
        fixture.configureAutoGraph(
            model,
            objective: "Confirm only unchanged verifier evidence."
        )
        model.setNativeVerificationProbeSelection(selection)
        model.calculateEstimate()
        model.startWithOriginalPrompt()
        XCTAssertNotNil(model.pendingNativeContractConfirmation)

        try Data("substituted-verifier-v2".utf8).write(
            to: verifier,
            options: .atomic
        )
        XCTAssertEqual(chmod(verifier.path, 0o755), 0)
        await model.confirmAndEnrollNativeAutoGraphContract()

        XCTAssertNotNil(model.pendingNativeContractConfirmation)
        XCTAssertNil(model.latestKernelEnrollmentReceipt)
        XCTAssertTrue(model.store.tasks.isEmpty)
        XCTAssertTrue(
            model.alertMessage?.contains("changed after contract review") == true
        )
        let registrations = try await fixture.registry.registrations(limit: 8)
        XCTAssertTrue(registrations.isEmpty)
    }

    private struct Fixture {
        let container: URL
        let workspace: URL
        let registryRoot: URL
        let registry: WorkspaceMutationRecoveryRegistry
        let coordinator: KernelRunEnrollmentCoordinator
        let executionCoordinator: KernelProductionExecutionCoordinator

        init() throws {
            container = FileManager.default.temporaryDirectory.appendingPathComponent(
                "LoopForgeNativeAppFlow-\(UUID().uuidString)",
                isDirectory: true
            )
            workspace = container.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workspace,
                withIntermediateDirectories: true
            )
            registryRoot = container.appendingPathComponent("registry", isDirectory: true)
            registry = try WorkspaceMutationRecoveryRegistry(rootDirectory: registryRoot)
            coordinator = KernelRunEnrollmentCoordinator(registry: registry)
            executionCoordinator = KernelProductionExecutionCoordinator(
                registry: registry
            )
        }

        @MainActor
        func model(
            recoveryTask: Task<
                WorkspaceMutationRecoveryStartupReport,
                Never
            >? = nil
        ) -> AppModel {
            AppModel(
                store: TaskStore(
                    storageURL: container.appendingPathComponent("tasks.json")
                ),
                workspaceMutationRecoveryTask: recoveryTask,
                kernelRunEnrollmentCoordinator: coordinator,
                kernelExecutionCoordinator: executionCoordinator
            )
        }

        @MainActor
        func configureAutoGraph(_ model: AppModel, objective: String) {
            model.draftProjectMode = .existing
            model.draftWorkspacePath = workspace.path
            model.draftRequest = objective
            model.selectAutoGraphLoop()
            model.setNativeVerificationProbe(verificationProbe)
            model.calculateEstimate()
            XCTAssertNotNil(model.estimate)
        }

        private var verificationProbe: RequirementVerificationExecutableProbe {
            RequirementVerificationExecutableProbe(
                schemaVersion: 2,
                transport: .localDirectProcess,
                executableContentDigest: ContentDigest(
                    String(repeating: "c", count: 64)
                ),
                fixedArguments: [
                    "--input", "@loopforge-input:candidate-postimage", "--jsonl"
                ],
                inputBindings: [RequirementVerificationInputBinding(
                    id: "candidate-postimage",
                    kind: .candidatePostimage,
                    artifactID: "candidate-postimage",
                    argumentToken: "@loopforge-input:candidate-postimage"
                )],
                environmentPolicy: .minimalKernelAllowlist,
                environmentIdentityDigest: ContentDigest(
                    String(repeating: "d", count: 64)
                ),
                captureIdentityDigest: ContentDigest(
                    String(repeating: "e", count: 64)
                ),
                parser: RequirementVerificationParserContract(
                    id: "synthetic-jsonl-verifier",
                    schemaVersion: 1,
                    contentDigest: RequirementVerificationParserFormat
                        .canonicalJSONResultV1.implementationIdentityDigest,
                    format: .canonicalJSONResultV1
                ),
                resultMappings: [
                    RequirementVerificationResultMapping(
                        exitCode: 0,
                        parserResultCode: "accepted",
                        outcome: .accepted
                    ),
                    RequirementVerificationResultMapping(
                        exitCode: 1,
                        parserResultCode: "rejected",
                        outcome: .rejected
                    )
                ],
                unmatchedOutcome: .rejected,
                networkPolicy: .disabled,
                resourceLimits: RequirementVerificationResourceLimits(
                    maximumWallClockSeconds: 60,
                    maximumCapturedOutputBytes: 1_048_576,
                    maximumResidentBytes: 268_435_456,
                    maximumChildProcesses: 0
                )
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: container)
        }
    }
}
