import Foundation

enum KernelRunEnrollmentError: Error, Equatable {
    case invalidRatification
    case executionAuthorityWithheld([TaskContractAmbiguityID])
    case executionProfileMissing
    case workspaceBindingMismatch
    case verificationSelectionMismatch
    case verificationSelectionChanged
    case verificationExecutableStagingFailed
    case journalProjectionMismatch
}

struct KernelRunEnrollmentRequest: Sendable {
    var runID: KernelRunID
    var ratifiedContract: RatifiedTaskContract
    var actorIdentity: ActorIdentity
    var workspaceID: WorkspaceID
    var workspaceRoot: URL
    var hostBudget: HostResourceBudget
    var maximumDispatchBatch: Int
    var createCommandID: RunCommandID
    var enrolledAt: Date
    /// Native confirmation capabilities whose exact bytes must be imported
    /// before the contract becomes a journaled run. Empty remains available
    /// for internal/non-native construction, but can never activate a verifier.
    var verificationProbeSelections: [NativeVerificationProbeSelection] = []
}

struct KernelRunEnrollmentReceipt: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var contractRevision: UInt64
    var candidateDigest: ContentDigest
    var ratificationReceiptID: ReceiptID
    var userActorID: ActorID
    var journalTransaction: JournalTransactionReceipt
    var registration: WorkspaceMutationRecoveryRegistration
    var kernelProjection: KernelRunProjection
    /// Optional preserves decoding of schema-v1 receipts created before
    /// enrollment-owned verifier import was added.
    var verificationExecutableStaging: [KernelExecutableStagingReceipt]? = nil
}

/// Non-serializable capability proving the enrollment coordinator observed the
/// exact reducer-owned contract after the journal transaction. Its initializer
/// is file-private so registry callers cannot manufacture recovery authority
/// from a registration-shaped value.
struct JournaledKernelRunEnrollmentProof: Sendable {
    let runID: KernelRunID
    let registration: WorkspaceMutationRecoveryRegistration
    let journalTransaction: JournalTransactionReceipt
    let enrollmentEvidence: KernelRunEnrollmentEvidence

    fileprivate init(
        runID: KernelRunID,
        registration: WorkspaceMutationRecoveryRegistration,
        journalTransaction: JournalTransactionReceipt,
        enrollmentEvidence: KernelRunEnrollmentEvidence
    ) {
        self.runID = runID
        self.registration = registration
        self.journalTransaction = journalTransaction
        self.enrollmentEvidence = enrollmentEvidence
    }
}

/// The sole production-oriented boundary from confirmed contract authority to
/// a recoverable new-kernel run. It deliberately has no legacy task, Graph,
/// timer, provider, or Agent-prose input.
///
/// Ordering is fail-closed: derive owned paths, append `runCreated` to the
/// hash journal, verify the reducer projection, then publish the recovery
/// registration. A crash before the last step can leave an inert, unregistered
/// journal, but can never make an unjournaled run recoverable.
actor KernelRunEnrollmentCoordinator {
    private let registry: WorkspaceMutationRecoveryRegistry

    init(registry: WorkspaceMutationRecoveryRegistry) {
        self.registry = registry
    }

    func enroll(
        _ request: KernelRunEnrollmentRequest
    ) async throws -> KernelRunEnrollmentReceipt {
        let ratification = request.ratifiedContract.receipt
        let contract = request.ratifiedContract.contract
        guard ratification.contractID == contract.id,
              !ratification.candidateDigest.rawValue.isEmpty,
              !ratification.receiptID.rawValue.isEmpty,
              !ratification.userActorID.rawValue.isEmpty,
              !ratification.userActorLineageDigest.rawValue.isEmpty,
              ratification.confirmedAt <= request.enrolledAt else {
            throw KernelRunEnrollmentError.invalidRatification
        }
        guard ratification.executionEligibility == .contractAuthorityCeiling,
              ratification.blockingAmbiguityIDs.isEmpty else {
            throw KernelRunEnrollmentError.executionAuthorityWithheld(
                ratification.blockingAmbiguityIDs
            )
        }
        guard contract.executionProfile != nil else {
            throw KernelRunEnrollmentError.executionProfileMissing
        }
        guard contract.hasCompleteRequirementEvidenceRecipeProvenance,
              contract.validationIssues().isEmpty else {
            throw KernelRunEnrollmentError.invalidRatification
        }

        let resolvedWorkspace = request.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        let rootDigest = WorkspaceRepositoryIndexer.canonicalRootDigest(
            resolvedWorkspace
        )
        guard let workspaceBinding = contract.workspaceBinding,
              workspaceBinding.workspaceID == request.workspaceID,
              workspaceBinding.canonicalRootDigest == rootDigest else {
            throw KernelRunEnrollmentError.workspaceBindingMismatch
        }

        try await registry.requireUnconsumedRatificationReceipt(
            ratification.receiptID
        )

        var registration = try await registry.registrationCandidate(
            runID: request.runID,
            actorIdentity: request.actorIdentity,
            workspaceID: request.workspaceID,
            workspaceRoot: request.workspaceRoot,
            hostBudget: request.hostBudget,
            maximumDispatchBatch: request.maximumDispatchBatch,
            registeredAt: request.enrolledAt
        )
        let journal = try RunJournal(
            rootDirectory: registration.journalRoot,
            runID: request.runID
        )
        let verifierStaging = try stageConfirmedVerificationExecutables(
            request.verificationProbeSelections,
            contract: contract,
            runDirectory: journal.runDirectory
        )
        let transaction = try await journal.transactAtCurrentSequence(
            .createRun(contract),
            commandID: request.createCommandID,
            issuedAt: request.enrolledAt,
            actor: request.actorIdentity
        )
        let projection = await journal.currentProjection()
        let journalContract = await journal.currentContract()
        guard journalContract == contract,
              projection.phase == .ready else {
            throw KernelRunEnrollmentError.journalProjectionMismatch
        }
        let enrollmentEvidence = KernelRunEnrollmentEvidence(
            schemaVersion: 1,
            authority: .ratifiedUserContract,
            runID: request.runID,
            contractID: contract.id,
            contractRevision: ratification.revision,
            candidateDigest: ratification.candidateDigest,
            ratificationReceiptID: ratification.receiptID,
            userActorID: ratification.userActorID,
            userActorLineageDigest: ratification.userActorLineageDigest,
            createCommandID: transaction.commandID,
            journalFrameDigest: transaction.frameDigest,
            journalEndingSequence: transaction.endingSequence
        )
        registration.enrollmentEvidence = enrollmentEvidence
        let committed = try await registry.commit(
            JournaledKernelRunEnrollmentProof(
                runID: request.runID,
                registration: registration,
                journalTransaction: transaction,
                enrollmentEvidence: enrollmentEvidence
            )
        )
        return KernelRunEnrollmentReceipt(
            schemaVersion: 1,
            runID: request.runID,
            contractID: contract.id,
            contractRevision: ratification.revision,
            candidateDigest: ratification.candidateDigest,
            ratificationReceiptID: ratification.receiptID,
            userActorID: ratification.userActorID,
            journalTransaction: transaction,
            registration: committed,
            kernelProjection: projection,
            verificationExecutableStaging:
                verifierStaging.isEmpty ? nil : verifierStaging
        )
    }

    private func stageConfirmedVerificationExecutables(
        _ selections: [NativeVerificationProbeSelection],
        contract: TaskContract,
        runDirectory: URL
    ) throws -> [KernelExecutableStagingReceipt] {
        guard !selections.isEmpty else { return [] }
        let contractProbes = contract.requirementEvidenceRecipes?
            .compactMap(\.executableProbe) ?? []
        let uniqueContractProbes = Set(contractProbes)
        let selectedProbes = selections.map(\.probe)
        guard Set(selectedProbes) == uniqueContractProbes,
              Set(selectedProbes).count == selections.count else {
            throw KernelRunEnrollmentError.verificationSelectionMismatch
        }

        var refreshed: [NativeVerificationProbeSelection] = []
        for selection in selections {
            do {
                refreshed.append(
                    try NativeVerificationProbeSelectionLoader.revalidate(
                        selection
                    )
                )
            } catch {
                throw KernelRunEnrollmentError.verificationSelectionChanged
            }
        }

        do {
            return try refreshed.sorted {
                $0.probe.executableContentDigest.rawValue <
                    $1.probe.executableContentDigest.rawValue
            }.map {
                try KernelExecutableStager().stage(
                    executablePath: $0.executablePath,
                    expectedDigest: $0.probe.executableContentDigest,
                    runDirectory: runDirectory
                )
            }
        } catch {
            throw KernelRunEnrollmentError
                .verificationExecutableStagingFailed
        }
    }
}

/// One native-app composition root shares the same durable registry between
/// startup recovery and future explicit run enrollment. Constructing it does
/// not enroll, resume, or import any legacy task.
struct KernelProductionRuntime {
    var recoveryTask: Task<WorkspaceMutationRecoveryStartupReport, Never>
    var enrollmentCoordinator: KernelRunEnrollmentCoordinator?
    var executionCoordinator: KernelProductionExecutionCoordinator?

    static func startDefault() -> KernelProductionRuntime {
        do {
            let root = try WorkspaceMutationRecoveryRegistry.defaultRoot()
            let registry = try WorkspaceMutationRecoveryRegistry(rootDirectory: root)
            return KernelProductionRuntime(
                recoveryTask: WorkspaceMutationProductionRecovery.start(
                    registry: registry
                ),
                enrollmentCoordinator: KernelRunEnrollmentCoordinator(
                    registry: registry
                ),
                executionCoordinator: KernelProductionExecutionCoordinator(
                    registry: registry
                )
            )
        } catch {
            return KernelProductionRuntime(
                recoveryTask: WorkspaceMutationProductionRecovery.failed(
                    .registryUnavailable
                ),
                enrollmentCoordinator: nil,
                executionCoordinator: nil
            )
        }
    }
}
