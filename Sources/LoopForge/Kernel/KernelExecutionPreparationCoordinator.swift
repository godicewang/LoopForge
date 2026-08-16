import Foundation

enum KernelExecutionPreparationError: Error, Equatable {
    case invalidEnrollment
    case registrationMismatch
    case invalidPreparation(String)
    case preApplyCandidateIsolationAuthorityMissing
    case stalePreparation(expectedSequence: UInt64, actualSequence: UInt64)
    case journalRejected(KernelRejection)
}

struct KernelExecutionPreparationRequest: Sendable {
    var enrollment: KernelRunEnrollmentReceipt
    var plan: KernelPlanProposal
    /// Only the live capability minted by an explicit native baseline
    /// confirmation can enter production preparation. A decoded durable
    /// baseline bundle is evidence, not command authority.
    var designBaseline: AuthorizedKernelDesignBaseline?
    var convergenceEpochID: String
    var convergenceBudget: ConvergenceBudget
    var nodeID: KernelNodeID
    var admission: AttemptAdmissionRequest
    var actorIdentity: ActorIdentity
    var issuedAt: Date
    var planCommandID: RunCommandID
    var baselineCommandID: RunCommandID?
    var convergenceCommandID: RunCommandID
    var authorizationCommandID: RunCommandID
    var admissionCommandID: RunCommandID
}

struct KernelExecutionPreparationReceipt: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var contractID: TaskContractID
    var plan: KernelPlanProposal
    var designBaselineID: DesignBaselineID?
    var convergenceEpochID: String
    var nodeID: KernelNodeID
    var admission: AttemptAdmissionRequest
    var transactions: [JournalTransactionReceipt]
    var endingSequence: UInt64
    var kernelProjection: KernelRunProjection
}

struct KernelExecutionActivationRequest: Sendable {
    var enrollment: KernelRunEnrollmentReceipt
    var preparation: KernelExecutionPreparationReceipt
    var actorIdentity: ActorIdentity
    var startCommandID: RunCommandID
    var issuedAt: Date
}

/// Non-serializable proof that the exact prepared journal state was activated.
/// Runtime materialization may consume this capability in addition to its own
/// reducer-state checks; persistence can retain the typed receipt but cannot
/// manufacture this value.
struct JournaledKernelExecutionProof: Sendable {
    let runID: KernelRunID
    let attemptID: AttemptID
    let nodeID: KernelNodeID
    let strategyFingerprint: StrategyFingerprint
    let workerExecutionProfile: KernelAgentExecutionProfile
    let workspaceRoot: URL
    let preApplyCandidateIsolation:
        WorkspacePreApplyCandidateIsolationReceipt?
    let activationActor: ActorIdentity
    let activationTransaction: JournalTransactionReceipt

    fileprivate init(
        runID: KernelRunID,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        strategyFingerprint: StrategyFingerprint,
        workerExecutionProfile: KernelAgentExecutionProfile,
        workspaceRoot: URL,
        preApplyCandidateIsolation:
            WorkspacePreApplyCandidateIsolationReceipt? = nil,
        activationActor: ActorIdentity,
        activationTransaction: JournalTransactionReceipt
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.nodeID = nodeID
        self.strategyFingerprint = strategyFingerprint
        self.workerExecutionProfile = workerExecutionProfile
        self.workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.preApplyCandidateIsolation = preApplyCandidateIsolation
        self.activationActor = activationActor
        self.activationTransaction = activationTransaction
    }

#if DEBUG
    static func testOnly(
        runID: KernelRunID,
        attemptID: AttemptID,
        nodeID: KernelNodeID,
        strategyFingerprint: StrategyFingerprint,
        workerExecutionProfile: KernelAgentExecutionProfile,
        workspaceRoot: URL,
        preApplyCandidateIsolation:
            WorkspacePreApplyCandidateIsolationReceipt? = nil,
        activationActor: ActorIdentity,
        activationTransaction: JournalTransactionReceipt
    ) -> JournaledKernelExecutionProof {
        JournaledKernelExecutionProof(
            runID: runID,
            attemptID: attemptID,
            nodeID: nodeID,
            strategyFingerprint: strategyFingerprint,
            workerExecutionProfile: workerExecutionProfile,
            workspaceRoot: workspaceRoot,
            preApplyCandidateIsolation: preApplyCandidateIsolation,
            activationActor: activationActor,
            activationTransaction: activationTransaction
        )
    }
#endif
}

struct KernelExecutionActivationReceipt: Sendable {
    var journalTransaction: JournalTransactionReceipt
    var kernelProjection: KernelRunProjection
    var proof: JournaledKernelExecutionProof
}

/// Composes ratified enrollment into an inert, fully reducer-checked execution
/// preparation. Planning, baseline freezing, convergence initialization, node
/// authorization, and causal admission are preflighted as one journal batch.
/// No process, agent, timer, workspace lease, or external effect is created.
actor KernelExecutionPreparationCoordinator {
    private let registry: WorkspaceMutationRecoveryRegistry

    init(registry: WorkspaceMutationRecoveryRegistry) {
        self.registry = registry
    }

    func prepare(
        _ request: KernelExecutionPreparationRequest,
        acceptedPreApplyIsolation:
            WorkspacePreApplyCandidateIsolationReceipt? = nil
    ) async throws -> KernelExecutionPreparationReceipt {
        let registration = try await exactRegistration(for: request.enrollment)
        let evidence = registration.enrollmentEvidence
        guard request.enrollment.runID == registration.runID,
              request.enrollment.registration == registration,
              request.enrollment.contractID == evidence?.contractID,
              request.enrollment.journalTransaction.frameDigest ==
                evidence?.journalFrameDigest,
              request.enrollment.journalTransaction.endingSequence ==
                evidence?.journalEndingSequence else {
            throw KernelExecutionPreparationError.invalidEnrollment
        }

        guard let node = request.plan.nodes.first(where: { $0.id == request.nodeID }),
              request.plan.nodes.filter({ $0.id == request.nodeID }).count == 1,
              request.admission.strategy.fingerprint == node.strategyFingerprint,
              request.admission.strategy.requirementIDs == node.requirementIDs,
              request.admission.attemptID.rawValue.isEmpty == false,
              request.designBaseline == nil || request.baselineCommandID != nil,
              request.designBaseline != nil || request.baselineCommandID == nil else {
            throw KernelExecutionPreparationError.invalidPreparation(
                "plan node, causal admission, and optional baseline command must match exactly"
            )
        }

        let journal = try RunJournal(
            rootDirectory: registration.journalRoot,
            runID: registration.runID
        )
        let initial = await journal.state
        let expectedInitialSequence: UInt64
        if let acceptedPreApplyIsolation {
            guard request.plan.requiresWorkspaceMutation,
                  initial.preApplyCandidateIsolationReceipts?[
                    request.admission.attemptID
                  ] == acceptedPreApplyIsolation,
                  acceptedPreApplyIsolation.nodeID == request.nodeID,
                  acceptedPreApplyIsolation.strategyFingerprint ==
                    request.admission.strategy.fingerprint else {
                throw KernelExecutionPreparationError
                    .preApplyCandidateIsolationAuthorityMissing
            }
            expectedInitialSequence =
                request.enrollment.journalTransaction.endingSequence + 1
        } else {
            expectedInitialSequence =
                request.enrollment.journalTransaction.endingSequence
        }
        guard initial.phase == .ready,
              initial.sequence == expectedInitialSequence,
              initial.nodes.isEmpty,
              initial.attempts.isEmpty,
              initial.convergenceGovernor == nil,
              initial.designBaseline == nil else {
            throw KernelExecutionPreparationError.stalePreparation(
                expectedSequence: expectedInitialSequence,
                actualSequence: initial.sequence
            )
        }
        guard let contract = initial.contract,
              contract.hasValidInitialExecutionAuthority,
              let authority = contract.initialCausalStrategyAuthority,
              let retainedPlan = contract.initialExecutionPlan,
              let retainedBudgets = contract.executionBudgets,
              request.plan == retainedPlan,
              request.admission.strategy == authority.descriptor,
              request.admission.predictedObservationIDs ==
                authority.descriptor.expectedObservationIDs,
              request.admission.falsificationPredicateIDs ==
                authority.descriptor.falsificationPredicateIDs,
              request.admission.rollbackPoint == authority.descriptor.baselineRevision,
              request.convergenceBudget == retainedBudgets.convergence else {
            throw KernelExecutionPreparationError.invalidPreparation(
                "preparation must equal the user-confirmed strategy, plan, predictions, falsifiers, rollback revision, and convergence budget"
            )
        }

        if let authorized = request.designBaseline {
            guard authorized.runID == request.enrollment.runID,
                  authorized.contractRatificationReceiptID ==
                    request.enrollment.ratificationReceiptID,
                  authorized.enrollmentJournalFrameDigest ==
                    request.enrollment.journalTransaction.frameDigest,
                  authorized.baseline.contractID == request.enrollment.contractID,
                  authorized.baseline.authority.authority ==
                    authorized.confirmingUser else {
                throw KernelExecutionPreparationError.invalidPreparation(
                    "design baseline authority must bind the exact enrollment, ratification, contract, and confirming user"
                )
            }
        }

        var commands: [(RunCommand, RunCommandID, ActorIdentity)] = [
            (.proposePlan(request.plan), request.planCommandID, request.actorIdentity)
        ]
        if let authorized = request.designBaseline,
           let commandID = request.baselineCommandID {
            commands.append((
                .freezeDesignBaseline(authorized),
                commandID,
                authorized.confirmingUser
            ))
        }
        commands.append(contentsOf: [
            (
                .initializeConvergence(
                    epochID: request.convergenceEpochID,
                    budget: request.convergenceBudget
                ),
                request.convergenceCommandID,
                request.actorIdentity
            ),
            (
                .authorizeNode(request.nodeID),
                request.authorizationCommandID,
                request.actorIdentity
            ),
            (
                .admitCausalAttempt(request.admission),
                request.admissionCommandID,
                request.actorIdentity
            )
        ])

        var preview = initial
        var envelopes: [JournalCommandEnvelope] = []
        for (command, commandID, actor) in commands {
            let context = KernelCommandContext(
                commandID: commandID,
                expectedSequence: preview.sequence,
                issuedAt: request.issuedAt,
                actor: actor
            )
            let decision = RunReducer.handle(
                state: preview,
                command: command,
                context: context
            )
            guard case .accepted(_, let next) = decision else {
                if case .rejected(let rejection) = decision {
                    throw KernelExecutionPreparationError.journalRejected(rejection)
                }
                preconditionFailure("ReducerDecision is exhaustive")
            }
            envelopes.append(JournalCommandEnvelope(
                command: command,
                context: context
            ))
            preview = next
        }

        let transactions: [JournalTransactionReceipt]
        do {
            transactions = try await journal.transactBatch(envelopes)
        } catch RunJournalError.reducerRejected(let rejection) {
            throw KernelExecutionPreparationError.journalRejected(rejection)
        }
        let final = await journal.state
        guard final.phase == .ready,
              final.nodes[request.nodeID]?.status == .authorized,
              final.convergenceGovernor?.admittedRequest(
                for: request.admission.attemptID
              ) == request.admission,
              final.activeAttemptID == nil else {
            throw KernelExecutionPreparationError.invalidPreparation(
                "journal did not project the exact inert prepared attempt"
            )
        }
        return KernelExecutionPreparationReceipt(
            schemaVersion: 1,
            runID: registration.runID,
            contractID: request.enrollment.contractID,
            plan: request.plan,
            designBaselineID: request.designBaseline?.baseline.id,
            convergenceEpochID: request.convergenceEpochID,
            nodeID: request.nodeID,
            admission: request.admission,
            transactions: transactions,
            endingSequence: final.sequence,
            kernelProjection: KernelRunProjection(state: final)
        )
    }

    func activate(
        _ request: KernelExecutionActivationRequest,
        acceptedPreApplyIsolation:
            WorkspacePreApplyCandidateIsolationReceipt? = nil
    ) async throws -> KernelExecutionActivationReceipt {
        let registration = try await exactRegistration(for: request.enrollment)
        guard request.preparation.runID == registration.runID,
              request.preparation.contractID == request.enrollment.contractID else {
            throw KernelExecutionPreparationError.invalidEnrollment
        }
        let journal = try RunJournal(
            rootDirectory: registration.journalRoot,
            runID: registration.runID
        )
        let state = await journal.state
        let attempt = request.preparation.admission
        guard state.sequence == request.preparation.endingSequence else {
            throw KernelExecutionPreparationError.stalePreparation(
                expectedSequence: request.preparation.endingSequence,
                actualSequence: state.sequence
            )
        }
        guard state.phase == .ready,
              state.nodes[request.preparation.nodeID]?.status == .authorized,
              state.nodes[request.preparation.nodeID]?.contract ==
                request.preparation.plan.nodes.first(where: {
                    $0.id == request.preparation.nodeID
                }),
              state.convergenceGovernor?.admittedRequest(for: attempt.attemptID) == attempt,
              state.designBaseline?.id == request.preparation.designBaselineID else {
            throw KernelExecutionPreparationError.invalidPreparation(
                "activation requires the unchanged exact prepared reducer projection"
            )
        }
        if request.preparation.plan.requiresWorkspaceMutation {
            guard let acceptedPreApplyIsolation,
                  state.contract?.requiresWorkspaceMutationAuthority == true,
                  state.preApplyCandidateIsolationReceipts?[
                    attempt.attemptID
                  ] == acceptedPreApplyIsolation,
                  acceptedPreApplyIsolation.nodeID ==
                    request.preparation.nodeID,
                  acceptedPreApplyIsolation.strategyFingerprint ==
                    attempt.strategy.fingerprint else {
                throw KernelExecutionPreparationError
                    .preApplyCandidateIsolationAuthorityMissing
            }
        } else {
            guard acceptedPreApplyIsolation == nil,
                  state.contract?.requiresWorkspaceMutationAuthority == false else {
                throw KernelExecutionPreparationError
                    .preApplyCandidateIsolationAuthorityMissing
            }
        }

        let transaction: JournalTransactionReceipt
        do {
            transaction = try await journal.transactAtCurrentSequence(
                .startAttempt(
                    attemptID: attempt.attemptID,
                    nodeID: request.preparation.nodeID,
                    requirementIDs: attempt.strategy.requirementIDs,
                    strategyFingerprint: attempt.strategy.fingerprint
                ),
                commandID: request.startCommandID,
                issuedAt: request.issuedAt,
                actor: request.actorIdentity
            )
        } catch RunJournalError.reducerRejected(let rejection) {
            throw KernelExecutionPreparationError.journalRejected(rejection)
        }
        let projection = await journal.currentProjection()
        guard projection.phase == .executing else {
            throw KernelExecutionPreparationError.invalidPreparation(
                "activation transaction did not enter executing"
            )
        }
        guard let workerExecutionProfile = state.contract?.executionProfile?.worker else {
            throw KernelExecutionPreparationError.invalidPreparation(
                "activation requires a ratified worker execution profile"
            )
        }
        let proof = JournaledKernelExecutionProof(
            runID: registration.runID,
            attemptID: attempt.attemptID,
            nodeID: request.preparation.nodeID,
            strategyFingerprint: attempt.strategy.fingerprint,
            workerExecutionProfile: workerExecutionProfile,
            workspaceRoot: acceptedPreApplyIsolation.map {
                URL(
                    fileURLWithPath: $0.candidateRootPath,
                    isDirectory: true
                )
            } ?? registration.workspaceRoot,
            preApplyCandidateIsolation: acceptedPreApplyIsolation,
            activationActor: request.actorIdentity,
            activationTransaction: transaction
        )
        return KernelExecutionActivationReceipt(
            journalTransaction: transaction,
            kernelProjection: projection,
            proof: proof
        )
    }

    private func exactRegistration(
        for enrollment: KernelRunEnrollmentReceipt
    ) async throws -> WorkspaceMutationRecoveryRegistration {
        guard let registration = try await registry.registration(
            runID: enrollment.runID
        ),
        registration.enrollmentEvidence?.authority == .ratifiedUserContract else {
            throw KernelExecutionPreparationError.registrationMismatch
        }
        return registration
    }
}
