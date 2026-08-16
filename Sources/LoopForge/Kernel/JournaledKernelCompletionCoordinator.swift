import CryptoKit
import Foundation

enum JournaledKernelCompletionError: Error, Equatable {
    case invalidState([String])
    case journalHeadMismatch
    case journalRejected(KernelRejection)
    case journalReceiptMismatch
    case legacyCompletionWithoutAuthorization
}

struct KernelCompletionAuthorizationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var commandID: RunCommandID
    var runID: KernelRunID
    var contractID: TaskContractID
    var sourceSequence: UInt64
    var sourceFrameDigest: ContentDigest
    var sourceOccurredAt: Date
    var sourceEvidenceDigest: ContentDigest
    var acceptedRequirementIDs: Set<RequirementID>
    var evidenceReceiptIDs: Set<ReceiptID>
    var authorizer: ActorIdentity
    var authorizedAt: Date
}

struct JournaledKernelCompletionReceipt: Sendable {
    var authorization: KernelCompletionAuthorizationReceipt
    var journalTransaction: JournalTransactionReceipt
    var kernelProjection: KernelRunProjection
}

/// File-owned production issuer marker. Model output, decoded journal data,
/// and controller prose cannot construct it.
struct KernelCompletionCommandIssuer: Sendable {
    fileprivate init() {}
}

enum KernelCompletionEvidenceCompiler {
    static let deterministicAuthorizer = ActorIdentity(
        id: ActorID("loopforge-kernel-final-authorizer-v1"),
        role: "deterministicFinalAuthorizer",
        lineageDigest: digest(
            Data("loopforge.kernel.final-authorizer.v1".utf8)
        )
    )

    static func validationIssues(
        state: KernelRunState,
        sourceFrameDigest: ContentDigest,
        sourceOccurredAt: Date,
        authorizedAt: Date,
        authorizer: ActorIdentity
    ) -> [String] {
        var issues: [String] = []
        guard let contract = state.contract else {
            return ["task contract is absent"]
        }
        if state.phase != .completionRequested {
            issues.append("completion must already be reducer-requested")
        }
        if state.activeAttemptID != nil {
            issues.append("active attempt remains")
        }
        if !state.runtimeLiveLeases.isEmpty {
            issues.append("live runtime resources remain")
        }
        if !state.runtimeFailedReleases.isEmpty {
            issues.append("failed runtime releases remain")
        }
        if !validSHA256(sourceFrameDigest) {
            issues.append("journal head digest must be exact SHA-256")
        }
        if authorizedAt < sourceOccurredAt {
            issues.append("authorization predates the journal head")
        }
        let missing = contract.mandatoryRequirementIDs.subtracting(
            state.acceptedRequirementIDs
        )
        if !missing.isEmpty {
            issues.append("mandatory requirements remain unaccepted")
        }
        if let duration = contract.acceptancePolicy.duration {
            let accepted = state.durationCoverage?.cumulativeAcceptedSeconds ?? 0
            if accepted < Double(duration.requiredSeconds) {
                issues.append("accepted duration remains below the ratified floor")
            }
        }
        if contract.acceptancePolicy.requiresQuiescence,
           state.quiescenceReceipt?.provesQuiescence != true {
            issues.append("ratified quiescence is absent")
        }
        if !(state.runtimeAdmissionReceipts.isEmpty),
           state.quiescenceReceipt?.provesQuiescence != true {
            issues.append("executed runtime lacks a terminal quiescence receipt")
        }
        if contract.protectedBaselines.contains(where: {
            $0.preservationRequired
        }), state.designBaseline == nil {
            issues.append(
                "preservation-required product baseline lacks frozen design authority"
            )
        }

        for dependency in contract.externalDependencies ?? [] {
            let observations = (state.externalDependencyReceipts ?? [:])
                .values.filter { $0.dependencyID == dependency.id }
            if observations.isEmpty
                || observations.contains(where: { observation in
                    observation.availability != .available
                        || observation.evidenceRecipeID !=
                            dependency.evidenceRecipeID
                        || observation.requirementIDs !=
                            dependency.requirementIDs.intersection(
                                state.attempts[observation.attemptID]?
                                    .requirementIDs ?? []
                            )
                        || !dependency.authorizedObserverLineageDigests
                            .contains(observation.observer.lineageDigest)
                }) {
                issues.append(
                    "external dependency \(dependency.id.rawValue) lacks exclusively available authorized evidence"
                )
            }
        }

        if let baseline = state.designBaseline {
            for requirementID in baseline.requirementIDs {
                let latest = state.visualGateReceipts.values
                    .filter { $0.requirementIDs.contains(requirementID) }
                    .max { $0.journalSequence < $1.journalSequence }
                if latest?.result.accepted != true
                    || latest?.nativeReviewRequestDigest == nil
                    || latest?.nativeCaptureAttestationDigests == nil
                    || latest?.nativeMeasurementAttestationDigests == nil
                    || latest?.nativeReviewCompletedAt == nil {
                    issues.append(
                        "protected visual requirement \(requirementID.rawValue) lacks latest native green authority"
                    )
                }
            }
        }

        let unsafeIntegrations = state.integrationTransactions.values.filter {
            $0.phase != .independentlyAccepted && $0.phase != .rolledBack
        }
        if !unsafeIntegrations.isEmpty {
            issues.append("integration transaction remains unfinished or quarantined")
        }
        if contract.requiresWorkspaceMutationAuthority {
            for requirementID in contract.mandatoryRequirementIDs {
                let acceptedAttempts = Set(state.verificationReceipts.values
                    .filter {
                        $0.requirementIDs.contains(requirementID)
                            && state.verificationIsEffective(
                                $0,
                                requirementID: requirementID
                            )
                    }
                    .map(\.attemptID))
                let integrated = state.integrationTransactions.values.contains {
                    $0.phase == .independentlyAccepted
                        && acceptedAttempts.contains($0.proposal.attemptID)
                }
                if !integrated {
                    issues.append(
                        "mutation-backed requirement \(requirementID.rawValue) lacks independent integration acceptance"
                    )
                }
            }
        }

        if authorizer != deterministicAuthorizer {
            issues.append("final authorizer is not the deterministic kernel issuer")
        }
        let occupiedLineages = actorLineages(state: state)
        if occupiedLineages.contains(authorizer.lineageDigest) {
            issues.append("final authorizer lineage is not independent")
        }
        return issues.sorted()
    }

    static func evidenceDigest(
        state: KernelRunState,
        sourceFrameDigest: ContentDigest,
        sourceOccurredAt: Date,
        authorizer: ActorIdentity
    ) -> ContentDigest {
        let contract = state.contract
        var fields = [
            "loopforge.kernel.final-completion-evidence.v1",
            state.runID.rawValue,
            contract?.id.rawValue ?? "",
            String(state.sequence),
            sourceFrameDigest.rawValue,
            String(Int64(sourceOccurredAt.timeIntervalSince1970 * 1_000)),
            authorizer.id.rawValue,
            authorizer.role,
            authorizer.lineageDigest.rawValue,
            joined(contract?.mandatoryRequirementIDs.map(\.rawValue) ?? []),
            joined(state.acceptedRequirementIDs.map(\.rawValue)),
            joined(state.allReceiptIDs.map(\.rawValue)),
            state.activeAttemptID?.rawValue ?? "",
            joined(state.runtimeLiveLeases.keys.map(\.rawValue)),
            joined(state.runtimeFailedReleases.map(\.rawValue)),
            state.quiescenceReceipt?.id.rawValue ?? ""
        ]
        fields.append(contentsOf: (state.externalDependencyReceipts ?? [:])
            .values.sorted { $0.id.rawValue < $1.id.rawValue }
            .map {
                "dependency:\($0.id.rawValue):\($0.dependencyID.rawValue):\($0.availability.rawValue):\($0.evidenceDigest.rawValue)"
            })
        fields.append(contentsOf: state.visualGateReceipts.values
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map {
                "visual:\($0.id.rawValue):\($0.deterministicEvidenceDigest.rawValue):\($0.result.accepted):\($0.journalSequence)"
            })
        fields.append(contentsOf: state.integrationTransactions
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map {
                "integration:\($0.key.rawValue):\($0.value.phase.rawValue):\(joined($0.value.receiptIDs.map(\.rawValue)))"
            })
        fields.append(contentsOf: state.nodes.values
            .sorted { $0.contract.id.rawValue < $1.contract.id.rawValue }
            .map {
                "node:\($0.contract.id.rawValue):\($0.status.rawValue):\(joined($0.attemptIDs.map(\.rawValue)))"
            })
        return digest(Data(fields.joined(separator: "\0").utf8))
    }

    private static func actorLineages(
        state: KernelRunState
    ) -> Set<ContentDigest> {
        var values = Set(state.attempts.values.map { $0.worker.lineageDigest })
        values.formUnion(state.reviewReceipts.values.map {
            $0.reviewer.lineageDigest
        })
        values.formUnion((state.externalDependencyReceipts ?? [:]).values.map {
            $0.observer.lineageDigest
        })
        values.formUnion(state.visualGateReceipts.values.map {
            $0.evaluator.lineageDigest
        })
        if let authority = state.designBaseline?.authority.authority {
            values.insert(authority.lineageDigest)
        }
        for integration in state.integrationTransactions.values {
            if let executor = integration.applyReceipt?.executor {
                values.insert(executor.lineageDigest)
            }
            if let reviewer = integration.acceptanceReceipt?.reviewer {
                values.insert(reviewer.lineageDigest)
            }
        }
        return values
    }

    private static func joined<S: Sequence>(_ values: S) -> String
    where S.Element == String {
        values.sorted().joined(separator: "\u{1f}")
    }

    private static func validSHA256(_ value: ContentDigest) -> Bool {
        value.rawValue.utf8.count == 64
            && value.rawValue == value.rawValue.lowercased()
            && value.rawValue.allSatisfy(\.isHexDigit)
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }
}

/// Deterministic final-completion issuer. It executes no model and trusts no
/// completion prose. Independent verifier/reviewer/visual/integration facts
/// must already be accepted in the exact hash-journal head.
actor JournaledKernelCompletionCoordinator {
    private let journal: RunJournal
    private let clock: @Sendable () -> Date

    init(
        journal: RunJournal,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.clock = clock
    }

    func authorize() async throws -> JournaledKernelCompletionReceipt {
        let state = await journal.state
        if state.phase == .completed {
            guard let retained = state.completionAuthorizationReceipt,
                  let transaction = await journal
                    .completionAuthorizationTransaction(
                        commandID: retained.commandID
                    ) else {
                throw JournaledKernelCompletionError
                    .legacyCompletionWithoutAuthorization
            }
            var duplicate = transaction
            duplicate.duplicate = true
            return JournaledKernelCompletionReceipt(
                authorization: retained,
                journalTransaction: duplicate,
                kernelProjection: await journal.currentProjection()
            )
        }
        guard let contract = state.contract else {
            throw JournaledKernelCompletionError.invalidState([
                "task contract is absent"
            ])
        }
        let head = await journal.headSnapshot()
        guard head.sequence == state.sequence,
              let frameDigest = head.frameDigest,
              let sourceOccurredAt = await journal.latestEventOccurredAt()
        else {
            throw JournaledKernelCompletionError.journalHeadMismatch
        }
        let authorizer = KernelCompletionEvidenceCompiler
            .deterministicAuthorizer
        let authorizedAt = clock()
        let issues = KernelCompletionEvidenceCompiler.validationIssues(
            state: state,
            sourceFrameDigest: frameDigest,
            sourceOccurredAt: sourceOccurredAt,
            authorizedAt: authorizedAt,
            authorizer: authorizer
        )
        guard issues.isEmpty else {
            throw JournaledKernelCompletionError.invalidState(issues)
        }
        let evidenceDigest = KernelCompletionEvidenceCompiler.evidenceDigest(
            state: state,
            sourceFrameDigest: frameDigest,
            sourceOccurredAt: sourceOccurredAt,
            authorizer: authorizer
        )
        let commandID = RunCommandID(
            "kernel-final-completion-\(evidenceDigest.rawValue)"
        )
        let receipt = KernelCompletionAuthorizationReceipt(
            id: ReceiptID(commandID.rawValue),
            commandID: commandID,
            runID: state.runID,
            contractID: contract.id,
            sourceSequence: state.sequence,
            sourceFrameDigest: frameDigest,
            sourceOccurredAt: sourceOccurredAt,
            sourceEvidenceDigest: evidenceDigest,
            acceptedRequirementIDs: state.acceptedRequirementIDs,
            evidenceReceiptIDs: state.allReceiptIDs,
            authorizer: authorizer,
            authorizedAt: authorizedAt
        )
        let authority = AuthorizedKernelCompletion
            .issuedByJournaledCompletionCoordinator(
                receipt: receipt,
                issuer: KernelCompletionCommandIssuer()
            )
        let transaction: JournalTransactionReceipt
        do {
            transaction = try await journal.recordCompletionAuthorization(
                authority
            )
        } catch RunJournalError.reducerRejected(let rejection) {
            throw JournaledKernelCompletionError.journalRejected(rejection)
        }
        guard let recorded = await journal.completionAuthorizationReceipt(),
              recorded == receipt,
              transaction.eventIDs.count == 2 else {
            throw JournaledKernelCompletionError.journalReceiptMismatch
        }
        return JournaledKernelCompletionReceipt(
            authorization: receipt,
            journalTransaction: transaction,
            kernelProjection: await journal.currentProjection()
        )
    }
}
