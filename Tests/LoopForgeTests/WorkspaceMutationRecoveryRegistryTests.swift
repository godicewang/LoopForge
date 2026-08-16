import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceMutationRecoveryRegistryTests: XCTestCase {
    func testStartupReportCarriesOnlyJournalDerivedConvergenceDiagnosis() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeConvergenceDiagnosisRecovery-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: container) }
        let workspace = container.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        let registry = try WorkspaceMutationRecoveryRegistry(
            rootDirectory: container.appendingPathComponent("recovery", isDirectory: true)
        )
        let runID = KernelRunID("diagnostic-run")
        let actor = ActorIdentity(
            id: ActorID("diagnostic-actor"),
            role: "kernel-controller",
            lineageDigest: ContentDigest("diagnostic-lineage")
        )
        let registration = try await registry.register(
            runID: runID,
            actorIdentity: actor,
            workspaceID: WorkspaceID("diagnostic-workspace"),
            workspaceRoot: workspace,
            hostBudget: HostResourceBudget(nominal: ResourceVector.zero),
            maximumDispatchBatch: 4,
            registeredAt: Date(timeIntervalSince1970: 10)
        )
        let journal = try RunJournal(
            rootDirectory: registration.journalRoot,
            runID: runID
        )
        let requirementID = RequirementID("diagnostic-requirement")
        let contract = TaskContract(
            id: TaskContractID("diagnostic-contract"),
            schemaVersion: 1,
            verbatimObjective: "Project accepted receipt state without mutation.",
            objectiveDigest: ContentDigest("diagnostic-objective"),
            requirements: [RequirementContract(
                id: requirementID,
                statement: "Expose the accepted convergence diagnosis.",
                mandatory: true,
                evidenceRecipeIDs: [EvidenceRecipeID("diagnostic-recipe")]
            )],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        _ = try await journal.transactAtCurrentSequence(
            .createRun(contract),
            commandID: RunCommandID("diagnostic-create"),
            issuedAt: Date(timeIntervalSince1970: 11),
            actor: actor
        )
        let convergenceBudget = ConvergenceBudget(
            maximumAttempts: 4,
            maximumEquivalentFailures: 2,
            maximumStrategies: 3,
            maximumPlanExpansions: 1,
            maximumMutationCost: 20,
            maximumVerificationCost: 20,
            maximumDamageEvents: 1,
            maximumExternalEffects: 1
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(
                epochID: "diagnostic-epoch",
                budget: convergenceBudget
            ),
            commandID: RunCommandID("diagnostic-initialize"),
            issuedAt: Date(timeIntervalSince1970: 12),
            actor: actor
        )
        let descriptor = CausalStrategyDescriptor(
            requirementIDs: [requirementID],
            hypothesisClass: "typed-projection",
            actionClass: "read-journal",
            workspaceTopology: "read-only-registry",
            capabilityRoute: ["filesystem-read"],
            evidenceSources: ["hash-journal"],
            measurementBoundary: "accepted-reducer-state",
            verificationOracles: ["projection-digest"],
            mutationSurfaceDigest: ContentDigest("no-mutation"),
            baselineRevision: ContentDigest("journal-head"),
            expectedObservationIDs: ["diagnosis-visible"],
            falsificationPredicateIDs: ["diagnosis-missing"],
            inheritedLessonDigests: []
        )
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(AttemptAdmissionRequest(
                attemptID: AttemptID("diagnostic-attempt"),
                strategy: descriptor,
                predictedObservationIDs: ["diagnosis-visible"],
                falsificationPredicateIDs: ["diagnosis-missing"],
                rollbackPoint: ContentDigest("read-only-rollback"),
                mutationCost: 0,
                verificationCost: 2,
                externalEffects: 0
            )),
            commandID: RunCommandID("diagnostic-admit"),
            issuedAt: Date(timeIntervalSince1970: 13),
            actor: actor
        )

        let coordinator = try WorkspaceMutationRecoveryCoordinator(registry: registry)
        let report = try await coordinator.recoverRegisteredRuns()
        let projection = try XCTUnwrap(report.runReports.first?.kernelProjection)
        let diagnosis = try XCTUnwrap(projection.convergenceDiagnosis)

        XCTAssertEqual(diagnosis.authority, ConvergenceDiagnosticProjection.authority)
        XCTAssertEqual(diagnosis.epochID, "diagnostic-epoch")
        XCTAssertEqual(diagnosis.sourceSequence, 3)
        XCTAssertEqual(diagnosis.budget.consumed.attempts, 1)
        XCTAssertEqual(diagnosis.budget.consumed.verificationCost, 2)
        XCTAssertEqual(diagnosis.strategies.first?.fingerprint, descriptor.fingerprint)
        XCTAssertFalse(diagnosis.projectionDigest.rawValue.isEmpty)
        XCTAssertFalse(report.requiresAttention)

        let decoded = try JSONDecoder().decode(
            WorkspaceMutationRecoveryStartupReport.self,
            from: JSONEncoder().encode(report)
        )
        XCTAssertEqual(decoded, report)
    }

    func testEmptyRegistryCreatesPrivateRootsAndRecoversAsNoOp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeEmptyWorkspaceRecovery-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let registry = try WorkspaceMutationRecoveryRegistry(rootDirectory: root)
        let coordinator = try WorkspaceMutationRecoveryCoordinator(registry: registry)
        let report = try await coordinator.recoverRegisteredRuns()

        XCTAssertTrue(report.ownershipAcquired)
        XCTAssertEqual(report.registeredRunCount, 0)
        XCTAssertTrue(report.runReports.isEmpty)
        XCTAssertFalse(report.requiresAttention)
        let rootMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: root.path)[
                .posixPermissions
            ] as? NSNumber
        )
        let runsMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: root.appendingPathComponent("runs").path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(rootMode.intValue & 0o777, 0o700)
        XCTAssertEqual(runsMode.intValue & 0o777, 0o700)
    }

    func testRegistryPersistsOnlyCanonicalTypedRunsAndRejectsTampering() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeWorkspaceRecoveryRegistry-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: container) }
        let workspace = container.appendingPathComponent("workspace", isDirectory: true)
        let otherWorkspace = container.appendingPathComponent(
            "other-workspace",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: otherWorkspace,
            withIntermediateDirectories: true
        )
        let registryRoot = container.appendingPathComponent(
            "kernel-recovery",
            isDirectory: true
        )
        let registry = try WorkspaceMutationRecoveryRegistry(
            rootDirectory: registryRoot
        )
        let runID = KernelRunID("registry-run")
        let actor = ActorIdentity(
            id: ActorID("registry-executor"),
            role: "executor",
            lineageDigest: ContentDigest("registry-lineage")
        )
        let budget = HostResourceBudget(nominal: ResourceVector(
            cpuWeight: 1,
            memoryBytes: 1_024,
            diskIOWeight: 1,
            gpuWeight: 0,
            networkWeight: 0,
            guiSessionCount: 0,
            processCount: 0
        ))
        let registeredAt = Date(timeIntervalSince1970: 100)
        let registered = try await registry.register(
            runID: runID,
            actorIdentity: actor,
            workspaceID: WorkspaceID("workspace-id"),
            workspaceRoot: workspace,
            hostBudget: budget,
            maximumDispatchBatch: 8,
            registeredAt: registeredAt
        )
        XCTAssertEqual(registered.schemaVersion, 1)
        XCTAssertEqual(registered.runID, runID)
        XCTAssertEqual(registered.actorIdentity, actor)
        XCTAssertEqual(registered.hostBudget, budget)
        XCTAssertEqual(registered.maximumDispatchBatch, 8)
        XCTAssertEqual(
            registered.journalRoot,
            registryRoot
                .appendingPathComponent("runs/registry-run/journal", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(
            registered.outboxRoot,
            registryRoot
                .appendingPathComponent("runs/registry-run/outbox", isDirectory: true)
                .standardizedFileURL
        )

        let duplicate = try await registry.register(
            runID: runID,
            actorIdentity: actor,
            workspaceID: WorkspaceID("workspace-id"),
            workspaceRoot: workspace,
            hostBudget: budget,
            maximumDispatchBatch: 8,
            registeredAt: registeredAt
        )
        XCTAssertEqual(duplicate, registered)
        do {
            _ = try await registry.register(
                runID: runID,
                actorIdentity: actor,
                workspaceID: WorkspaceID("workspace-id"),
                workspaceRoot: otherWorkspace,
                hostBudget: budget,
                maximumDispatchBatch: 8,
                registeredAt: registeredAt
            )
            XCTFail("same run identity cannot change workspace")
        } catch WorkspaceMutationRecoveryRegistryError.duplicateRunConflict {}
        do {
            _ = try await registry.register(
                runID: KernelRunID("../escape"),
                actorIdentity: actor,
                workspaceID: WorkspaceID("workspace-id"),
                workspaceRoot: workspace,
                hostBudget: budget,
                maximumDispatchBatch: 8,
                registeredAt: registeredAt
            )
            XCTFail("run identity cannot escape the registry root")
        } catch WorkspaceMutationRecoveryRegistryError.invalidRegistration {}
        let workspaceLink = container.appendingPathComponent(
            "workspace-link",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: workspaceLink,
            withDestinationURL: workspace
        )
        do {
            _ = try await registry.register(
                runID: KernelRunID("symlink-workspace"),
                actorIdentity: actor,
                workspaceID: WorkspaceID("workspace-id"),
                workspaceRoot: workspaceLink,
                hostBudget: budget,
                maximumDispatchBatch: 8,
                registeredAt: registeredAt
            )
            XCTFail("workspace registration cannot enter through a symlink")
        } catch WorkspaceMutationRecoveryRegistryError.invalidRegistration {}
        do {
            _ = try await registry.register(
                runID: KernelRunID("overlap"),
                actorIdentity: actor,
                workspaceID: WorkspaceID("workspace-id"),
                workspaceRoot: container,
                hostBudget: budget,
                maximumDispatchBatch: 8,
                registeredAt: registeredAt
            )
            XCTFail("registry storage cannot live inside the workspace")
        } catch WorkspaceMutationRecoveryRegistryError.workspaceOverlapsRegistry {}
        do {
            _ = try await registry.register(
                runID: KernelRunID("oversized-batch"),
                actorIdentity: actor,
                workspaceID: WorkspaceID("workspace-id"),
                workspaceRoot: workspace,
                hostBudget: budget,
                maximumDispatchBatch: 65,
                registeredAt: registeredAt
            )
            XCTFail("dispatch batch cannot exceed registry policy")
        } catch WorkspaceMutationRecoveryRegistryError.invalidRegistration {}

        let restarted = try WorkspaceMutationRecoveryRegistry(
            rootDirectory: registryRoot
        )
        let persisted = try await restarted.registrations(limit: 10)
        XCTAssertEqual(persisted, [registered])
        let coordinator = try WorkspaceMutationRecoveryCoordinator(
            registry: restarted,
            maximumRunsPerLaunch: 4,
            wallClock: { Date(timeIntervalSince1970: 200) },
            monotonicClock: { 200_000_000_000 }
        )
        let recovery = try await coordinator.recoverRegisteredRuns()
        XCTAssertTrue(recovery.ownershipAcquired)
        XCTAssertEqual(recovery.registeredRunCount, 1)
        XCTAssertEqual(recovery.runReports.count, 1)
        XCTAssertEqual(recovery.runReports.first?.runID, runID)
        XCTAssertNil(recovery.runReports.first?.failure)
        XCTAssertEqual(recovery.runReports.first?.scannedCount, 0)
        XCTAssertFalse(recovery.requiresAttention)
        let snapshotURL = registryRoot.appendingPathComponent("registry.json")
        let snapshotPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: snapshotURL.path)[
                .posixPermissions
            ] as? NSNumber
        )
        XCTAssertEqual(snapshotPermissions.intValue & 0o777, 0o600)
        let rootPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: registryRoot.path)[
                .posixPermissions
            ] as? NSNumber
        )
        XCTAssertEqual(rootPermissions.intValue & 0o777, 0o700)
        let runsPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: registryRoot.appendingPathComponent("runs").path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(runsPermissions.intValue & 0o777, 0o700)

        var bytes = try Data(contentsOf: snapshotURL)
        bytes[bytes.startIndex] ^= 0x01
        try bytes.write(to: snapshotURL, options: .atomic)
        XCTAssertThrowsError(try WorkspaceMutationRecoveryRegistry(
            rootDirectory: registryRoot
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationRecoveryRegistryError,
                .corruptSnapshot
            )
        }
    }

    func testCoordinatorFailsClosedWhenRegisteredWorkspaceDisappears() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeWorkspaceRecoveryMissingWorkspace-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: container) }
        let workspace = container.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        let registry = try WorkspaceMutationRecoveryRegistry(
            rootDirectory: container.appendingPathComponent("recovery", isDirectory: true)
        )
        _ = try await registry.register(
            runID: KernelRunID("missing-workspace-run"),
            actorIdentity: ActorIdentity(
                id: ActorID("missing-workspace-executor"),
                role: "executor",
                lineageDigest: ContentDigest("missing-workspace-lineage")
            ),
            workspaceID: WorkspaceID("missing-workspace-id"),
            workspaceRoot: workspace,
            hostBudget: HostResourceBudget(nominal: ResourceVector.zero),
            maximumDispatchBatch: 4,
            registeredAt: Date(timeIntervalSince1970: 100)
        )
        try FileManager.default.removeItem(at: workspace)

        let coordinator = try WorkspaceMutationRecoveryCoordinator(registry: registry)
        let report = try await coordinator.recoverRegisteredRuns()

        XCTAssertTrue(report.ownershipAcquired)
        XCTAssertEqual(report.runReports.first?.failure, .workspaceUnavailable)
        XCTAssertTrue(report.requiresAttention)
    }

    func testStartupReportSeparatesPersistedAttentionFromUnsafeTerminationCleanup() {
        let persistedIncompleteIntegration = WorkspaceMutationRecoveryStartupReport(
            ownershipAcquired: true,
            registeredRunCount: 1,
            runReports: [WorkspaceMutationRecoveryRunReport(
                runID: KernelRunID("persisted-incomplete-run"),
                failure: nil,
                scannedCount: 0,
                completedIntentIDs: [],
                quarantinedIntentIDs: [],
                dispatchFailures: [],
                liveResourceCount: 0,
                failedReleaseCount: 0,
                unresolvedIntegrationTransactionCount: 1
            )]
        )
        let liveResourceReport = WorkspaceMutationRecoveryStartupReport(
            ownershipAcquired: true,
            registeredRunCount: 1,
            runReports: [WorkspaceMutationRecoveryRunReport(
                runID: KernelRunID("live-resource-run"),
                failure: nil,
                scannedCount: 0,
                completedIntentIDs: [],
                quarantinedIntentIDs: [],
                dispatchFailures: [],
                liveResourceCount: 1,
                failedReleaseCount: 0
            )]
        )
        let quarantinedEffectReport = WorkspaceMutationRecoveryStartupReport(
            ownershipAcquired: true,
            registeredRunCount: 1,
            runReports: [WorkspaceMutationRecoveryRunReport(
                runID: KernelRunID("quarantined-effect-run"),
                failure: nil,
                scannedCount: 1,
                completedIntentIDs: [],
                quarantinedIntentIDs: [IntegrationEffectIntentID("quarantined-intent")],
                dispatchFailures: [],
                liveResourceCount: 0,
                failedReleaseCount: 0
            )]
        )
        let pendingEffectReport = WorkspaceMutationRecoveryStartupReport(
            ownershipAcquired: true,
            registeredRunCount: 1,
            runReports: [WorkspaceMutationRecoveryRunReport(
                runID: KernelRunID("pending-effect-run"),
                failure: nil,
                scannedCount: 0,
                completedIntentIDs: [],
                quarantinedIntentIDs: [],
                dispatchFailures: [],
                liveResourceCount: 0,
                failedReleaseCount: 0,
                remainingExecutableEffects: true
            )]
        )
        let startupFailure = WorkspaceMutationRecoveryStartupReport(
            ownershipAcquired: false,
            registeredRunCount: 0,
            runReports: [],
            startupFailure: .registryUnavailable
        )

        XCTAssertTrue(persistedIncompleteIntegration.requiresAttention)
        XCTAssertTrue(
            persistedIncompleteIntegration.applicationTerminationCleanupIsSafe
        )
        XCTAssertTrue(liveResourceReport.requiresAttention)
        XCTAssertFalse(liveResourceReport.applicationTerminationCleanupIsSafe)
        XCTAssertTrue(quarantinedEffectReport.requiresAttention)
        XCTAssertFalse(quarantinedEffectReport.applicationTerminationCleanupIsSafe)
        XCTAssertTrue(pendingEffectReport.requiresAttention)
        XCTAssertFalse(pendingEffectReport.applicationTerminationCleanupIsSafe)
        XCTAssertTrue(startupFailure.requiresAttention)
        XCTAssertFalse(startupFailure.applicationTerminationCleanupIsSafe)
    }
}
