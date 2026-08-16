import CryptoKit
import Foundation

enum IntegrationTransactionPhase: String, Codable, Hashable, Sendable {
    case proposed
    case rollbackPrepared
    case applying
    case appliedUnverified
    case postimageVerified
    case independentlyAccepted
    case rollbackRequired
    case rollingBack
    case rolledBack
    case rollbackFailedQuarantined
}

struct IntegrationProposal: Codable, Hashable, Sendable {
    var runID: KernelRunID
    var transactionID: IntegrationTransactionID
    var candidateID: MutationCandidateID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var contractDigest: ContentDigest
    var planNodeDigest: ContentDigest
    var manifestDigest: ContentDigest
    var canonicalPreimageDigest: ContentDigest
    var expectedPostimageDigest: ContentDigest
    var proposedAt: Date
}

struct IntegrationApplyIntent: Codable, Hashable, Sendable {
    var id: IntegrationEffectIntentID
    var transactionID: IntegrationTransactionID
    var preflightReceiptID: ReceiptID
    var manifestDigest: ContentDigest
    var canonicalPreimageDigest: ContentDigest
    var rollbackManifestDigest: ContentDigest
    var stagedObjectSetDigest: ContentDigest
    var exclusiveLeaseReceiptID: ReceiptID
    var remoteAccessDisabled: Bool
    var requestedAt: Date
    /// Optional only for replaying intents journaled before candidate-tree
    /// attestation existed. Native contract-backed starts must bind the exact
    /// ratified source-revision capture policy.
    var candidatePostimageCapturePolicyDigest: ContentDigest? = nil
}

enum IntegrationApplyOutcome: Codable, Hashable, Sendable {
    case exactPostimage
    case failed(reasonDigest: ContentDigest)
    case inDoubt(reasonDigest: ContentDigest)
}

struct IntegrationApplyReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var intentID: IntegrationEffectIntentID
    var transactionID: IntegrationTransactionID
    var manifestDigest: ContentDigest
    var canonicalPreimageDigest: ContentDigest
    var observedPostimageDigest: ContentDigest?
    var unchangedPathProofDigest: ContentDigest?
    var recoveryArtifactDigest: ContentDigest
    var appliedOperationCount: Int
    var executor: ActorIdentity
    var completedAt: Date
    var outcome: IntegrationApplyOutcome
    /// Present only for an exact postimage captured under the policy sealed in
    /// the apply intent. Journal acceptance is still required before this
    /// evidence can become an attestation authority.
    var candidatePostimage: WorkspaceSourceRevisionArtifact? = nil
}

enum IntegrationVerificationResult: Codable, Hashable, Sendable {
    case accepted
    case rejected(reasonDigest: ContentDigest)
}

struct IntegrationPostimageVerificationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var transactionID: IntegrationTransactionID
    var applyReceiptID: ReceiptID
    var canonicalPostimageDigest: ContentDigest
    var evidenceSetDigest: ContentDigest
    var processQuiescenceReceiptID: ReceiptID
    var verifier: ActorIdentity
    var verifiedAt: Date
    var result: IntegrationVerificationResult
    /// Present for journal/process-issued transitions. Optional only for
    /// decoding legacy and DEBUG reducer fixtures.
    var sourceVerificationReceiptID: ReceiptID? = nil
}

enum IntegrationAcceptanceDecision: Codable, Hashable, Sendable {
    case accepted
    case rejected(reasonDigest: ContentDigest)
}

enum KernelIntegrationReceiptAuthority {
    static func rejectionDigest(
        review: IndependentReviewReceipt
    ) -> ContentDigest {
        let value = [
            "kernel-integration-review-rejection-v1",
            review.id.rawValue,
            review.evidenceDigest.rawValue,
            review.decision.rawValue
        ].joined(separator: "\0")
        return ContentDigest(SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined())
    }

    static func acceptanceDecision(
        review: IndependentReviewReceipt
    ) -> IntegrationAcceptanceDecision {
        switch review.decision {
        case .approveCandidate:
            return .accepted
        case .rejectCandidate, .needsDifferentEvidence:
            return .rejected(reasonDigest: rejectionDigest(review: review))
        }
    }
}

struct IntegrationAcceptanceReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var transactionID: IntegrationTransactionID
    var verificationReceiptID: ReceiptID
    var canonicalPostimageDigest: ContentDigest
    var evidenceDigest: ContentDigest
    var reviewer: ActorIdentity
    var reviewedAt: Date
    var decision: IntegrationAcceptanceDecision
    /// Present for journal/process-issued transitions. Optional only for
    /// decoding legacy and DEBUG reducer fixtures.
    var sourceIndependentReviewReceiptID: ReceiptID? = nil
    var sourceVerificationEvidenceSetDigest: ContentDigest? = nil
}

struct IntegrationRollbackIntent: Codable, Hashable, Sendable {
    var id: IntegrationEffectIntentID
    var transactionID: IntegrationTransactionID
    var rollbackManifestDigest: ContentDigest
    var expectedCurrentWorkspaceDigest: ContentDigest?
    var recoveryArtifactDigest: ContentDigest
    var exclusiveLeaseReceiptID: ReceiptID
    var remoteAccessDisabled: Bool
    var requestedAt: Date
}

enum IntegrationRollbackOutcome: Codable, Hashable, Sendable {
    case restored
    case failedQuarantined(reasonDigest: ContentDigest, recoveryArtifactDigest: ContentDigest)
}

struct IntegrationRollbackReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var intentID: IntegrationEffectIntentID
    var transactionID: IntegrationTransactionID
    var rollbackManifestDigest: ContentDigest
    var recoveryArtifactDigest: ContentDigest
    var observedPreimageDigest: ContentDigest?
    var unchangedPathProofDigest: ContentDigest?
    var executor: ActorIdentity
    var completedAt: Date
    var outcome: IntegrationRollbackOutcome
}

struct IntegrationTransactionState: Codable, Hashable, Sendable {
    var proposal: IntegrationProposal
    var phase: IntegrationTransactionPhase
    var preflightReceipt: MutationPreflightReceipt?
    var rollbackManifest: RollbackManifest?
    var applyIntent: IntegrationApplyIntent?
    var applyReceipt: IntegrationApplyReceipt?
    var postimageVerificationReceipt: IntegrationPostimageVerificationReceipt?
    var acceptanceReceipt: IntegrationAcceptanceReceipt?
    var rollbackIntent: IntegrationRollbackIntent?
    var rollbackReceipt: IntegrationRollbackReceipt?

    var receiptIDs: Set<ReceiptID> {
        Set([
            preflightReceipt?.id,
            applyReceipt?.id,
            postimageVerificationReceipt?.id,
            acceptanceReceipt?.id,
            rollbackReceipt?.id
        ].compactMap { $0 })
    }

    var intentIDs: Set<IntegrationEffectIntentID> {
        Set([applyIntent?.id, rollbackIntent?.id].compactMap { $0 })
    }

    var permitsPublication: Bool { false }
}

enum IntegrationTransitionCommand: Codable, Hashable, Sendable {
    case propose(IntegrationProposal)
    case acceptPreflight(
        receipt: MutationPreflightReceipt,
        rollback: RollbackManifest
    )
    case startApply(IntegrationApplyIntent)
    case recordApply(IntegrationApplyReceipt)
    case recordPostimageVerification(IntegrationPostimageVerificationReceipt)
    case recordIndependentAcceptance(IntegrationAcceptanceReceipt)
    case requestRollback(IntegrationRollbackIntent)
    case recordRollback(IntegrationRollbackReceipt)
}

enum IntegrationTransitionEvent: Codable, Hashable, Sendable {
    case proposed(IntegrationProposal)
    case rollbackPrepared(
        receipt: MutationPreflightReceipt,
        rollback: RollbackManifest
    )
    case applyStarted(IntegrationApplyIntent)
    case applyRecorded(IntegrationApplyReceipt)
    case postimageVerificationRecorded(IntegrationPostimageVerificationReceipt)
    case independentAcceptanceRecorded(IntegrationAcceptanceReceipt)
    case rollbackStarted(IntegrationRollbackIntent)
    case rollbackRecorded(IntegrationRollbackReceipt)

    var transactionID: IntegrationTransactionID {
        switch self {
        case .proposed(let value): return value.transactionID
        case .rollbackPrepared(let value, _): return value.transactionID
        case .applyStarted(let value): return value.transactionID
        case .applyRecorded(let value): return value.transactionID
        case .postimageVerificationRecorded(let value): return value.transactionID
        case .independentAcceptanceRecorded(let value): return value.transactionID
        case .rollbackStarted(let value): return value.transactionID
        case .rollbackRecorded(let value): return value.transactionID
        }
    }
}

enum IntegrationTransitionRejection: Error, Codable, Hashable, Sendable {
    case malformedProposal
    case transactionAlreadyExists
    case transactionMissing
    case invalidPhase(expected: Set<IntegrationTransactionPhase>, actual: IntegrationTransactionPhase)
    case identityMismatch
    case duplicateEffectIdentity
    case preflightNotApplyEligible
    case publicationAuthorityLeak
    case rollbackNotMaterialized
    case remoteAccessNotDisabled
    case invalidApplyReceipt
    case invalidVerificationReceipt
    case reviewerNotIndependent
    case invalidAcceptanceReceipt
    case invalidRollbackIntent
    case invalidRollbackReceipt
}

enum IntegrationTransactionReducer {
    static func decide(
        current: IntegrationTransactionState?,
        command: IntegrationTransitionCommand,
        actor: ActorIdentity,
        knownReceiptIDs: Set<ReceiptID>,
        knownIntentIDs: Set<IntegrationEffectIntentID>
    ) -> Result<IntegrationTransitionEvent, IntegrationTransitionRejection> {
        switch command {
        case .propose(let proposal):
            guard current == nil else { return .failure(.transactionAlreadyExists) }
            guard proposalIsComplete(proposal) else { return .failure(.malformedProposal) }
            return .success(.proposed(proposal))

        case .acceptPreflight(let receipt, let rollback):
            guard let current else { return .failure(.transactionMissing) }
            guard current.phase == .proposed else {
                return invalidPhase([.proposed], current.phase)
            }
            let proposal = current.proposal
            guard receipt.transactionID == proposal.transactionID,
                  receipt.candidateID == proposal.candidateID,
                  receipt.manifestDigest == proposal.manifestDigest,
                  receipt.canonicalPreimageDigest == proposal.canonicalPreimageDigest,
                  rollback.transactionID == proposal.transactionID,
                  rollback.forwardManifestDigest == proposal.manifestDigest,
                  rollback.expectedAppliedPostimageDigest == proposal.expectedPostimageDigest,
                  rollback.restoresPreimageDigest == proposal.canonicalPreimageDigest else {
                return .failure(.identityMismatch)
            }
            guard receipt.eligibleForDeterministicApply else {
                return .failure(.preflightNotApplyEligible)
            }
            guard !receipt.permitsPublication else {
                return .failure(.publicationAuthorityLeak)
            }
            guard !receipt.id.rawValue.isEmpty,
                  receipt.operationCount > 0,
                  !rollback.operations.isEmpty,
                  receipt.operationCount == rollback.operations.count,
                  receipt.changedFileCount == receipt.affectedPaths.count,
                  receipt.affectedPaths == Array(Set(receipt.affectedPaths)).sorted(),
                  rollback.operations.map(\.sequence) ==
                    Array(1...rollback.operations.count),
                  receipt.observedAt >= proposal.proposedAt,
                  receipt.rollbackManifestDigest ==
                    TransactionalMutationKernel.rollbackDigest(rollback) else {
                return .failure(.rollbackNotMaterialized)
            }
            guard !knownReceiptIDs.contains(receipt.id) else {
                return .failure(.duplicateEffectIdentity)
            }
            return .success(.rollbackPrepared(receipt: receipt, rollback: rollback))

        case .startApply(let intent):
            guard let current else { return .failure(.transactionMissing) }
            guard current.phase == .rollbackPrepared else {
                return invalidPhase([.rollbackPrepared], current.phase)
            }
            guard let preflight = current.preflightReceipt,
                  intent.transactionID == current.proposal.transactionID,
                  intent.preflightReceiptID == preflight.id,
                  intent.manifestDigest == current.proposal.manifestDigest,
                  intent.canonicalPreimageDigest == current.proposal.canonicalPreimageDigest,
                  intent.rollbackManifestDigest == preflight.rollbackManifestDigest,
                  !intent.id.rawValue.isEmpty,
                  !intent.stagedObjectSetDigest.rawValue.isEmpty,
                  !intent.exclusiveLeaseReceiptID.rawValue.isEmpty,
                  intent.requestedAt >= preflight.observedAt else {
                return .failure(.identityMismatch)
            }
            guard intent.remoteAccessDisabled else {
                return .failure(.remoteAccessNotDisabled)
            }
            guard !knownIntentIDs.contains(intent.id) else {
                return .failure(.duplicateEffectIdentity)
            }
            return .success(.applyStarted(intent))

        case .recordApply(let receipt):
            guard let current else { return .failure(.transactionMissing) }
            guard current.phase == .applying else {
                return invalidPhase([.applying], current.phase)
            }
            guard let intent = current.applyIntent,
                  let preflight = current.preflightReceipt,
                  receipt.executor == actor,
                  receipt.transactionID == current.proposal.transactionID,
                  receipt.intentID == intent.id,
                  receipt.manifestDigest == current.proposal.manifestDigest,
                  receipt.canonicalPreimageDigest == current.proposal.canonicalPreimageDigest,
                  receipt.appliedOperationCount >= 0,
                  receipt.appliedOperationCount <= preflight.operationCount,
                  !receipt.recoveryArtifactDigest.rawValue.isEmpty,
                  receipt.completedAt >= intent.requestedAt,
                  !receipt.id.rawValue.isEmpty,
                  !knownReceiptIDs.contains(receipt.id) else {
                return .failure(.invalidApplyReceipt)
            }
            switch receipt.outcome {
            case .exactPostimage:
                guard receipt.appliedOperationCount == preflight.operationCount,
                      receipt.observedPostimageDigest == current.proposal.expectedPostimageDigest,
                      receipt.unchangedPathProofDigest?.rawValue.isEmpty == false else {
                    return .failure(.invalidApplyReceipt)
                }
                switch (
                    intent.candidatePostimageCapturePolicyDigest,
                    receipt.candidatePostimage
                ) {
                case (nil, nil):
                    break
                case let (expectedPolicyDigest?, candidatePostimage?):
                    guard candidatePostimage.validationIssues().isEmpty,
                          candidatePostimage.capturePolicyDigest == expectedPolicyDigest else {
                        return .failure(.invalidApplyReceipt)
                    }
                default:
                    return .failure(.invalidApplyReceipt)
                }
            case .failed(let reason):
                guard !reason.rawValue.isEmpty,
                      receipt.observedPostimageDigest?.rawValue.isEmpty == false,
                      receipt.candidatePostimage == nil else {
                    return .failure(.invalidApplyReceipt)
                }
            case .inDoubt(let reason):
                guard !reason.rawValue.isEmpty,
                      receipt.candidatePostimage == nil else {
                    return .failure(.invalidApplyReceipt)
                }
            }
            return .success(.applyRecorded(receipt))

        case .recordPostimageVerification(let receipt):
            guard let current else { return .failure(.transactionMissing) }
            guard current.phase == .appliedUnverified else {
                return invalidPhase([.appliedUnverified], current.phase)
            }
            guard let apply = current.applyReceipt,
                  receipt.verifier == actor,
                  receipt.verifier.lineageDigest != apply.executor.lineageDigest,
                  receipt.transactionID == current.proposal.transactionID,
                  receipt.applyReceiptID == apply.id,
                  receipt.canonicalPostimageDigest == current.proposal.expectedPostimageDigest,
                  !receipt.id.rawValue.isEmpty,
                  !receipt.evidenceSetDigest.rawValue.isEmpty,
                  !receipt.processQuiescenceReceiptID.rawValue.isEmpty,
                  receipt.verifiedAt >= apply.completedAt,
                  !knownReceiptIDs.contains(receipt.id) else {
                return .failure(.invalidVerificationReceipt)
            }
            if case .rejected(let reason) = receipt.result,
               reason.rawValue.isEmpty {
                return .failure(.invalidVerificationReceipt)
            }
            return .success(.postimageVerificationRecorded(receipt))

        case .recordIndependentAcceptance(let receipt):
            guard let current else { return .failure(.transactionMissing) }
            guard current.phase == .postimageVerified else {
                return invalidPhase([.postimageVerified], current.phase)
            }
            guard let apply = current.applyReceipt,
                  let verification = current.postimageVerificationReceipt,
                  receipt.reviewer == actor,
                  receipt.reviewer.lineageDigest != apply.executor.lineageDigest,
                  receipt.reviewer.lineageDigest != verification.verifier.lineageDigest else {
                return .failure(.reviewerNotIndependent)
            }
            guard receipt.transactionID == current.proposal.transactionID,
                  receipt.verificationReceiptID == verification.id,
                  receipt.canonicalPostimageDigest == current.proposal.expectedPostimageDigest,
                  !receipt.id.rawValue.isEmpty,
                  !receipt.evidenceDigest.rawValue.isEmpty,
                  receipt.reviewedAt >= verification.verifiedAt,
                  !knownReceiptIDs.contains(receipt.id) else {
                return .failure(.invalidAcceptanceReceipt)
            }
            if case .rejected(let reason) = receipt.decision,
               reason.rawValue.isEmpty {
                return .failure(.invalidAcceptanceReceipt)
            }
            return .success(.independentAcceptanceRecorded(receipt))

        case .requestRollback(let intent):
            guard let current else { return .failure(.transactionMissing) }
            let allowed: Set<IntegrationTransactionPhase> = [
                .rollbackRequired, .appliedUnverified, .postimageVerified,
                .independentlyAccepted
            ]
            guard allowed.contains(current.phase) else {
                return invalidPhase(allowed, current.phase)
            }
            guard let preflight = current.preflightReceipt,
                  let apply = current.applyReceipt,
                  intent.transactionID == current.proposal.transactionID,
                  intent.rollbackManifestDigest == preflight.rollbackManifestDigest,
                  intent.expectedCurrentWorkspaceDigest ==
                    apply.observedPostimageDigest,
                  intent.recoveryArtifactDigest == apply.recoveryArtifactDigest,
                  !intent.recoveryArtifactDigest.rawValue.isEmpty,
                  !intent.id.rawValue.isEmpty,
                  !intent.exclusiveLeaseReceiptID.rawValue.isEmpty,
                  intent.requestedAt >= (current.applyReceipt?.completedAt
                    ?? current.preflightReceipt?.observedAt
                    ?? current.proposal.proposedAt),
                  !knownIntentIDs.contains(intent.id) else {
                return .failure(.invalidRollbackIntent)
            }
            guard intent.remoteAccessDisabled else {
                return .failure(.remoteAccessNotDisabled)
            }
            return .success(.rollbackStarted(intent))

        case .recordRollback(let receipt):
            guard let current else { return .failure(.transactionMissing) }
            guard current.phase == .rollingBack else {
                return invalidPhase([.rollingBack], current.phase)
            }
            guard let intent = current.rollbackIntent,
                  let preflight = current.preflightReceipt,
                  receipt.executor == actor,
                  receipt.intentID == intent.id,
                  receipt.transactionID == current.proposal.transactionID,
                  receipt.rollbackManifestDigest == preflight.rollbackManifestDigest,
                  receipt.recoveryArtifactDigest == intent.recoveryArtifactDigest,
                  receipt.completedAt >= intent.requestedAt,
                  !receipt.id.rawValue.isEmpty,
                  !knownReceiptIDs.contains(receipt.id) else {
                return .failure(.invalidRollbackReceipt)
            }
            switch receipt.outcome {
            case .restored:
                guard receipt.observedPreimageDigest ==
                        current.proposal.canonicalPreimageDigest,
                      receipt.unchangedPathProofDigest?.rawValue.isEmpty == false else {
                    return .failure(.invalidRollbackReceipt)
                }
            case .failedQuarantined(let reason, let recovery):
                guard !reason.rawValue.isEmpty, !recovery.rawValue.isEmpty else {
                    return .failure(.invalidRollbackReceipt)
                }
            }
            return .success(.rollbackRecorded(receipt))
        }
    }

    static func reduce(
        current: IntegrationTransactionState?,
        event: IntegrationTransitionEvent
    ) -> IntegrationTransactionState? {
        switch event {
        case .proposed(let proposal):
            guard current == nil, proposalIsComplete(proposal) else { return current }
            return IntegrationTransactionState(
                proposal: proposal,
                phase: .proposed,
                preflightReceipt: nil,
                rollbackManifest: nil,
                applyIntent: nil,
                applyReceipt: nil,
                postimageVerificationReceipt: nil,
                acceptanceReceipt: nil,
                rollbackIntent: nil,
                rollbackReceipt: nil
            )
        case .rollbackPrepared(let receipt, let rollback):
            guard var next = current, next.phase == .proposed else { return current }
            next.preflightReceipt = receipt
            next.rollbackManifest = rollback
            next.phase = .rollbackPrepared
            return next
        case .applyStarted(let intent):
            guard var next = current, next.phase == .rollbackPrepared else { return current }
            next.applyIntent = intent
            next.phase = .applying
            return next
        case .applyRecorded(let receipt):
            guard var next = current, next.phase == .applying else { return current }
            next.applyReceipt = receipt
            switch receipt.outcome {
            case .exactPostimage: next.phase = .appliedUnverified
            case .failed, .inDoubt: next.phase = .rollbackRequired
            }
            return next
        case .postimageVerificationRecorded(let receipt):
            guard var next = current, next.phase == .appliedUnverified else { return current }
            next.postimageVerificationReceipt = receipt
            switch receipt.result {
            case .accepted: next.phase = .postimageVerified
            case .rejected: next.phase = .rollbackRequired
            }
            return next
        case .independentAcceptanceRecorded(let receipt):
            guard var next = current, next.phase == .postimageVerified else { return current }
            next.acceptanceReceipt = receipt
            switch receipt.decision {
            case .accepted: next.phase = .independentlyAccepted
            case .rejected: next.phase = .rollbackRequired
            }
            return next
        case .rollbackStarted(let intent):
            guard var next = current,
                  [IntegrationTransactionPhase.rollbackRequired,
                   .appliedUnverified,
                   .postimageVerified,
                   .independentlyAccepted].contains(next.phase) else {
                return current
            }
            next.rollbackIntent = intent
            next.phase = .rollingBack
            return next
        case .rollbackRecorded(let receipt):
            guard var next = current, next.phase == .rollingBack else { return current }
            next.rollbackReceipt = receipt
            switch receipt.outcome {
            case .restored: next.phase = .rolledBack
            case .failedQuarantined: next.phase = .rollbackFailedQuarantined
            }
            return next
        }
    }

    private static func proposalIsComplete(_ value: IntegrationProposal) -> Bool {
        !value.runID.rawValue.isEmpty
            && !value.transactionID.rawValue.isEmpty
            && !value.candidateID.rawValue.isEmpty
            && !value.attemptID.rawValue.isEmpty
            && !value.nodeID.rawValue.isEmpty
            && !value.contractDigest.rawValue.isEmpty
            && !value.planNodeDigest.rawValue.isEmpty
            && !value.manifestDigest.rawValue.isEmpty
            && !value.canonicalPreimageDigest.rawValue.isEmpty
            && !value.expectedPostimageDigest.rawValue.isEmpty
    }

    private static func invalidPhase(
        _ expected: Set<IntegrationTransactionPhase>,
        _ actual: IntegrationTransactionPhase
    ) -> Result<IntegrationTransitionEvent, IntegrationTransitionRejection> {
        .failure(.invalidPhase(expected: expected, actual: actual))
    }
}
