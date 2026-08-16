import Darwin
import Foundation

enum WorkspaceMutationRecoveryRunFailure: String, Codable, Equatable, Sendable {
    case workspaceUnavailable
    case journalOpenFailed
    case supervisorRestoreRejected
    case outboxOpenFailed
    case outboxWorkspaceBindingRejected
    case rollbackPreparationFailed
    case dispatchFailed
}

enum WorkspaceRepositoryIndexRecoveryStatus: String, Codable, Equatable, Sendable {
    case notApplicable
    case resolved
    case withheldAmbiguousGeneration
    case withheldPendingEffects
    case resolutionFailed
}

struct WorkspaceRepositoryIndexRecoveryTelemetry: Codable, Equatable, Sendable {
    var authority: WorkspaceTreeGenerationAuthority
    var generationDigest: ContentDigest
    var journalFrameDigest: ContentDigest
    var sourceSequence: UInt64
    var disposition: WorkspaceRepositoryIndexDisposition
    var observedMetadataDigest: ContentDigest
    var entryCount: Int
    var cacheKeyDigest: ContentDigest?
}

struct WorkspaceMutationRecoveryRunReport: Codable, Equatable, Sendable {
    var runID: KernelRunID
    var failure: WorkspaceMutationRecoveryRunFailure?
    var scannedCount: Int
    var completedIntentIDs: [IntegrationEffectIntentID]
    var quarantinedIntentIDs: [IntegrationEffectIntentID]
    var dispatchFailures: [WorkspaceMutationEffectDispatchFailure]
    var liveResourceCount: Int
    var failedReleaseCount: Int
    /// Read-only, reducer-derived state from the hash-chained journal. Legacy
    /// task/Graph fields and Agent prose cannot populate this projection.
    var kernelProjection: KernelRunProjection? = nil
    var remainingExecutableEffects: Bool = false
    /// Optional only for decoding reports emitted before incomplete
    /// integration phases became explicit recovery telemetry.
    var unresolvedIntegrationTransactionCount: Int? = nil
    var repositoryIndexStatus: WorkspaceRepositoryIndexRecoveryStatus = .notApplicable
    var repositoryIndexTelemetry: WorkspaceRepositoryIndexRecoveryTelemetry? = nil
    /// Rollback effects synthesized only from an exact verifier launch veto
    /// and the completed source apply envelope during this recovery pass.
    var preparedRollbackIntentIDs: [IntegrationEffectIntentID]? = nil

    var requiresAttention: Bool {
        failure != nil ||
            !quarantinedIntentIDs.isEmpty ||
            !dispatchFailures.isEmpty ||
            liveResourceCount > 0 ||
            failedReleaseCount > 0 ||
            remainingExecutableEffects ||
            (unresolvedIntegrationTransactionCount ?? 0) > 0 ||
            ![.notApplicable, .resolved].contains(repositoryIndexStatus)
    }
}

enum WorkspaceMutationRecoveryStartupFailure: String, Codable, Equatable, Sendable {
    case registryUnavailable
    case coordinatorUnavailable
    case recoveryFailed
}

struct WorkspaceMutationRecoveryStartupReport: Codable, Equatable, Sendable {
    var ownershipAcquired: Bool
    var registeredRunCount: Int
    var runReports: [WorkspaceMutationRecoveryRunReport]
    var startupFailure: WorkspaceMutationRecoveryStartupFailure? = nil

    var requiresAttention: Bool {
        startupFailure != nil ||
            !ownershipAcquired ||
            runReports.contains(where: \.requiresAttention)
    }

    /// Normal application exit may preserve an incomplete integration for a
    /// later verifier or user decision, but it must never race or conceal a
    /// live lease, pending effect, quarantined effect, failed release, or
    /// startup recovery failure. This is intentionally narrower than the UI's
    /// `requiresAttention`, which also includes safe persisted workflow state.
    var applicationTerminationCleanupIsSafe: Bool {
        startupFailure == nil &&
            ownershipAcquired &&
            runReports.allSatisfy {
                $0.failure == nil &&
                    $0.quarantinedIntentIDs.isEmpty &&
                    $0.dispatchFailures.isEmpty &&
                    $0.liveResourceCount == 0 &&
                    $0.failedReleaseCount == 0 &&
                    !$0.remainingExecutableEffects
            }
    }
}

/// Executes one sequential, bounded startup recovery pass for explicitly
/// registered new-kernel runs. It has no timer and no legacy task/Graph input.
actor WorkspaceMutationRecoveryCoordinator {
    private let registry: WorkspaceMutationRecoveryRegistry
    private let recoveryLockURL: URL
    private let maximumRunsPerLaunch: Int
    private let wallClock: @Sendable () -> Date
    private let monotonicClock: @Sendable () -> UInt64
    private let repositoryIndexer: WorkspaceRepositoryIndexer

    init(
        registry: WorkspaceMutationRecoveryRegistry,
        maximumRunsPerLaunch: Int = 32,
        repositoryIndexer: WorkspaceRepositoryIndexer = WorkspaceRepositoryIndexer(),
        wallClock: @escaping @Sendable () -> Date = { Date() },
        monotonicClock: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) throws {
        guard maximumRunsPerLaunch > 0 else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        self.registry = registry
        recoveryLockURL = registry.rootDirectory.appendingPathComponent(
            "recovery.lock"
        )
        self.maximumRunsPerLaunch = maximumRunsPerLaunch
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
        self.repositoryIndexer = repositoryIndexer
    }

    func recoverRegisteredRuns() async throws -> WorkspaceMutationRecoveryStartupReport {
        guard let ownership = try RecoveryOwnershipLock(url: recoveryLockURL) else {
            return WorkspaceMutationRecoveryStartupReport(
                ownershipAcquired: false,
                registeredRunCount: 0,
                runReports: []
            )
        }
        defer { _ = ownership }
        let registrations = try await registry.registrations(
            limit: maximumRunsPerLaunch
        )
        var reports: [WorkspaceMutationRecoveryRunReport] = []
        reports.reserveCapacity(registrations.count)
        for registration in registrations {
            reports.append(await recover(registration))
        }
        return WorkspaceMutationRecoveryStartupReport(
            ownershipAcquired: true,
            registeredRunCount: registrations.count,
            runReports: reports
        )
    }

    private func recover(
        _ registration: WorkspaceMutationRecoveryRegistration
    ) async -> WorkspaceMutationRecoveryRunReport {
        guard Self.isAvailableWorkspace(registration.workspaceRoot) else {
            return failureReport(registration.runID, .workspaceUnavailable)
        }
        let journal: RunJournal
        do {
            journal = try RunJournal(
                rootDirectory: registration.journalRoot,
                runID: registration.runID
            )
        } catch {
            return failureReport(registration.runID, .journalOpenFailed)
        }

        let supervisor = RuntimeSupervisor(
            runID: registration.runID,
            budget: registration.hostBudget
        )
        let recoveredKernelProjection = await journal.currentProjection()
        let recoverySnapshot = await journal.runtimeSupervisorRecoverySnapshot()
        guard case .restored = await supervisor.restore(from: recoverySnapshot) else {
            return failureReport(
                registration.runID,
                .supervisorRestoreRejected,
                kernelProjection: recoveredKernelProjection
            )
        }

        let outbox: WorkspaceMutationEffectOutbox
        do {
            outbox = try WorkspaceMutationEffectOutbox(
                rootDirectory: registration.outboxRoot,
                runID: registration.runID
            )
        } catch {
            return await failureReport(
                registration.runID,
                .outboxOpenFailed,
                supervisor: supervisor,
                kernelProjection: recoveredKernelProjection
            )
        }
        let entries: [WorkspaceMutationEffectEnvelope]
        do {
            entries = try await outbox.allEntries()
        } catch {
            return await failureReport(
                registration.runID,
                .outboxOpenFailed,
                supervisor: supervisor,
                kernelProjection: recoveredKernelProjection
            )
        }
        guard entries.allSatisfy({ Self.registrationClaims(
            registration,
            payload: $0.payload
        ) }) else {
            return await failureReport(
                registration.runID,
                .outboxWorkspaceBindingRejected,
                supervisor: supervisor,
                kernelProjection: recoveredKernelProjection
            )
        }

        let authority = JournaledWorkspaceMutationLeaseAuthority(
            supervisor: supervisor,
            journal: journal,
            actorIdentity: registration.actorIdentity
        )
        let rollbackPreparations:
            [WorkspacePostimageVerifierVetoRollbackPreparationInstallation]
        do {
            rollbackPreparations = try await
                WorkspacePostimageVerifierVetoRollbackPreparationCoordinator(
                    registry: registry,
                    registration: registration,
                    journal: journal,
                    outbox: outbox,
                    leaseAuthority: authority,
                    wallClock: wallClock,
                    monotonicClock: monotonicClock
                ).prepareEligibleRollbacks(
                    limit: registration.maximumDispatchBatch
                )
        } catch {
            return await failureReport(
                registration.runID,
                .rollbackPreparationFailed,
                supervisor: supervisor,
                kernelProjection: recoveredKernelProjection
            )
        }
        let runtime = JournaledWorkspaceMutationRuntime(
            journal: journal,
            actorIdentity: registration.actorIdentity,
            authority: authority,
            wallClock: wallClock,
            monotonicClock: monotonicClock
        )
        let dispatcher = JournaledWorkspaceMutationDispatcher(
            outbox: outbox,
            runtime: runtime,
            wallClock: wallClock
        )
        do {
            let dispatch = try await dispatcher.recoverPending(
                limit: registration.maximumDispatchBatch
            )
            let projection = await supervisor.projection()
            let currentState = await journal.state
            let currentKernelProjection = KernelRunProjection(
                state: currentState
            )
            let remainingExecutableEffects = try await !outbox.pending(limit: 1).isEmpty
            let unresolvedIntegrationTransactionCount =
                currentState.integrationTransactions.values.filter {
                    ![.independentlyAccepted, .rolledBack].contains($0.phase)
                }.count
            let repositoryIndex: (
                WorkspaceRepositoryIndexRecoveryStatus,
                WorkspaceRepositoryIndexRecoveryTelemetry?
            )
            if dispatch.failures.isEmpty,
               dispatch.quarantinedIntentIDs.isEmpty,
               projection.liveLeases.isEmpty,
               projection.failedReleases.isEmpty,
               !remainingExecutableEffects {
                repositoryIndex = await resolveRepositoryIndex(
                    journal: journal,
                    registration: registration
                )
            } else {
                repositoryIndex = (.withheldPendingEffects, nil)
            }
            return WorkspaceMutationRecoveryRunReport(
                runID: registration.runID,
                failure: nil,
                scannedCount: dispatch.scannedCount,
                completedIntentIDs: dispatch.completedIntentIDs,
                quarantinedIntentIDs: dispatch.quarantinedIntentIDs,
                dispatchFailures: dispatch.failures,
                liveResourceCount: projection.liveLeases.count,
                failedReleaseCount: projection.failedReleases.count,
                kernelProjection: currentKernelProjection,
                remainingExecutableEffects: remainingExecutableEffects,
                unresolvedIntegrationTransactionCount:
                    unresolvedIntegrationTransactionCount,
                repositoryIndexStatus: repositoryIndex.0,
                repositoryIndexTelemetry: repositoryIndex.1,
                preparedRollbackIntentIDs:
                    rollbackPreparations.map(\.intent.id)
            )
        } catch {
            return await failureReport(
                registration.runID,
                .dispatchFailed,
                supervisor: supervisor,
                kernelProjection: recoveredKernelProjection
            )
        }
    }

    private func resolveRepositoryIndex(
        journal: RunJournal,
        registration: WorkspaceMutationRecoveryRegistration
    ) async -> (
        WorkspaceRepositoryIndexRecoveryStatus,
        WorkspaceRepositoryIndexRecoveryTelemetry?
    ) {
        do {
            let generation = try await journal
                .latestAcceptedWorkspaceTreeGenerationReceipt(
                    workspaceID: registration.workspaceID,
                    root: registration.workspaceRoot
                )
            switch generation {
            case .noWorkspaceTransition:
                return (.notApplicable, nil)
            case .ambiguousLatestTransition:
                return (.withheldAmbiguousGeneration, nil)
            case .accepted(let receipt):
                let resolution = try await repositoryIndexer.resolve(
                    root: registration.workspaceRoot,
                    generationReceipt: receipt
                )
                return (.resolved, WorkspaceRepositoryIndexRecoveryTelemetry(
                    authority: receipt.authority,
                    generationDigest: receipt.generationDigest,
                    journalFrameDigest: receipt.journalTransaction.frameDigest,
                    sourceSequence: receipt.journalTransaction.endingSequence,
                    disposition: resolution.disposition,
                    observedMetadataDigest: resolution.index.observedMetadataDigest,
                    entryCount: resolution.index.entries.count,
                    cacheKeyDigest: resolution.cacheReceipt?.keyDigest
                ))
            }
        } catch {
            return (.resolutionFailed, nil)
        }
    }

    private func failureReport(
        _ runID: KernelRunID,
        _ failure: WorkspaceMutationRecoveryRunFailure,
        kernelProjection: KernelRunProjection? = nil
    ) -> WorkspaceMutationRecoveryRunReport {
        WorkspaceMutationRecoveryRunReport(
            runID: runID,
            failure: failure,
            scannedCount: 0,
            completedIntentIDs: [],
            quarantinedIntentIDs: [],
            dispatchFailures: [],
            liveResourceCount: 0,
            failedReleaseCount: 0,
            kernelProjection: kernelProjection
        )
    }

    private func failureReport(
        _ runID: KernelRunID,
        _ failure: WorkspaceMutationRecoveryRunFailure,
        supervisor: RuntimeSupervisor,
        kernelProjection: KernelRunProjection? = nil
    ) async -> WorkspaceMutationRecoveryRunReport {
        let projection = await supervisor.projection()
        return WorkspaceMutationRecoveryRunReport(
            runID: runID,
            failure: failure,
            scannedCount: 0,
            completedIntentIDs: [],
            quarantinedIntentIDs: [],
            dispatchFailures: [],
            liveResourceCount: projection.liveLeases.count,
            failedReleaseCount: projection.failedReleases.count,
            kernelProjection: kernelProjection
        )
    }

    private static func registrationClaims(
        _ registration: WorkspaceMutationRecoveryRegistration,
        payload: WorkspaceMutationEffectPayload
    ) -> Bool {
        let expectedRoot = registration.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        switch payload {
        case .apply(let request):
            return request.workspaceID == registration.workspaceID &&
                request.preimage.workspaceID == registration.workspaceID &&
                request.workspaceRoot.standardizedFileURL.resolvingSymlinksInPath() ==
                    expectedRoot
        case .rollback(let request):
            return request.workspaceID == registration.workspaceID &&
                request.preimage.workspaceID == registration.workspaceID &&
                request.workspaceRoot.standardizedFileURL.resolvingSymlinksInPath() ==
                    expectedRoot
        }
    }

    private static func isAvailableWorkspace(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.standardizedFileURL.resolvingSymlinksInPath() == url else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}

/// Production entry point for the new-kernel recovery contract. The native app
/// starts this explicitly; tests and legacy Graph construction do not touch the
/// user's Application Support registry unless the task is injected.
enum WorkspaceMutationProductionRecovery {
    static func startDefault() -> Task<WorkspaceMutationRecoveryStartupReport, Never> {
        do {
            let root = try WorkspaceMutationRecoveryRegistry.defaultRoot()
            let registry = try WorkspaceMutationRecoveryRegistry(rootDirectory: root)
            return start(registry: registry)
        } catch {
            return failed(.registryUnavailable)
        }
    }

    static func start(
        registry: WorkspaceMutationRecoveryRegistry
    ) -> Task<WorkspaceMutationRecoveryStartupReport, Never> {
        Task.detached(priority: .utility) {
            let coordinator: WorkspaceMutationRecoveryCoordinator
            do {
                coordinator = try WorkspaceMutationRecoveryCoordinator(registry: registry)
            } catch {
                return WorkspaceMutationRecoveryStartupReport(
                    ownershipAcquired: false,
                    registeredRunCount: 0,
                    runReports: [],
                    startupFailure: .coordinatorUnavailable
                )
            }
            do {
                return try await coordinator.recoverRegisteredRuns()
            } catch {
                return WorkspaceMutationRecoveryStartupReport(
                    ownershipAcquired: false,
                    registeredRunCount: 0,
                    runReports: [],
                    startupFailure: .recoveryFailed
                )
            }
        }
    }

    static func failed(
        _ failure: WorkspaceMutationRecoveryStartupFailure
    ) -> Task<WorkspaceMutationRecoveryStartupReport, Never> {
        Task {
            WorkspaceMutationRecoveryStartupReport(
                ownershipAcquired: false,
                registeredRunCount: 0,
                runReports: [],
                startupFailure: failure
            )
        }
    }
}

private final class RecoveryOwnershipLock: @unchecked Sendable {
    private let handle: FileHandle

    init?(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw WorkspaceMutationRecoveryRegistryError.lockFailed
            }
            _ = chmod(url.path, 0o600)
        }
        do {
            handle = try FileHandle(forUpdating: url)
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.lockFailed
        }
        guard flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            try? handle.close()
            return nil
        }
    }

    deinit {
        flock(handle.fileDescriptor, LOCK_UN)
        try? handle.close()
    }
}
