import CryptoKit
import Foundation

enum TaskContractSourceAuthority: String, Codable, Hashable, Sendable {
    case user
    case acceptedUserAmendment
    case workspaceObservation
    case projectInstruction
    case modelProposal

    var mayCreateExplicitAuthority: Bool {
        self == .user || self == .acceptedUserAmendment
    }
}

struct TaskContractSourceArtifact: Codable, Hashable, Sendable {
    var id: TaskContractSourceID
    var exactUTF8: Data
    var digest: ContentDigest
    var authority: TaskContractSourceAuthority
    var author: ActorIdentity
    var recordedAt: Date

    init(
        id: TaskContractSourceID,
        exactUTF8: Data,
        authority: TaskContractSourceAuthority,
        author: ActorIdentity,
        recordedAt: Date
    ) {
        self.id = id
        self.exactUTF8 = exactUTF8
        digest = TaskContractCompiler.digest(exactUTF8)
        self.authority = authority
        self.author = author
        self.recordedAt = recordedAt
    }
}

struct TaskContractSourceSpan: Codable, Hashable, Sendable {
    var sourceID: TaskContractSourceID
    var sourceDigest: ContentDigest
    var lowerUTF8Offset: Int
    var upperUTF8Offset: Int
}

enum TaskContractEpistemicState: String, Codable, Hashable, Sendable {
    case explicit
    case workspaceObserved
    case conventionObserved
    case inferredSafe
    case proposed
    case unknown
    case conflicted
}

struct RequirementSourceBinding: Codable, Hashable, Sendable {
    var requirementID: RequirementID
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct ConstraintSourceBinding: Codable, Hashable, Sendable {
    var constraintID: String
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct ExternalDependencySourceBinding: Codable, Hashable, Sendable {
    var dependencyID: ExternalDependencyID
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct WorkspaceSourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct DurationAcceptanceSourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct ExecutionProfileSourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct ExecutionBudgetSourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct SourceRevisionSourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct CausalStrategyAuthoritySourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

struct ExecutionPlanSourceBinding: Codable, Hashable, Sendable {
    var sourceSpans: [TaskContractSourceSpan]
    var epistemicState: TaskContractEpistemicState
}

enum RequirementVerifierKind: String, Codable, Hashable, Sendable {
    case deterministic
    case nativeVisual
    case adversarial
    case userAuthority
}

enum RequirementVerificationInputKind: String, Codable, Hashable, Sendable {
    case candidatePostimage
    /// Exact evidence-set identity of an already journaled v2 verification.
    /// This binding is permitted only for a separately activated independent
    /// review probe; it is resolved by the journal coordinator, never by its
    /// caller.
    case verificationEvidenceDigest
    case ratifiedContract
    case confirmedSourceRevision
    case immutableBaseline
    case declaredArtifact
}

struct RequirementVerificationInputBinding: Codable, Hashable, Sendable {
    var id: String
    var kind: RequirementVerificationInputKind
    /// Opaque contract-owned identity. The verifier runtime must later bind
    /// this identity to one exact journal-retained content digest.
    var artifactID: String
    /// Exact argv token replaced descriptor-relatively by the future verifier
    /// runtime. It is never interpolated by a shell.
    var argumentToken: String
}

enum RequirementVerificationOutcome: String, Codable, Hashable, Sendable {
    case accepted
    case rejected
}

struct RequirementVerificationResultMapping: Codable, Hashable, Sendable {
    var exitCode: Int32
    var parserResultCode: String
    var outcome: RequirementVerificationOutcome
}

enum RequirementVerificationParserFormat: String, Codable, Hashable, Sendable {
    /// Exactly one UTF-8, canonical sorted-key JSON object followed by one LF.
    /// The future parser implementation must reject every other byte shape.
    case canonicalJSONResultV1

    var implementationIdentityDigest: ContentDigest {
        switch self {
        case .canonicalJSONResultV1:
            return ContentDigest(KernelHex.encode(SHA256.hash(data: Data(
                "loopforge.kernel.postimage-verifier-result.v1.canonical-sorted-json-single-line"
                    .utf8
            ))))
        }
    }
}

struct RequirementVerificationParserContract: Codable, Hashable, Sendable {
    var id: String
    var schemaVersion: Int
    var contentDigest: ContentDigest
    /// Optional only so schema-v1 journals remain decodable for read-only
    /// recovery. New authoring and activation require the exact v2 format and
    /// its built-in implementation identity.
    var format: RequirementVerificationParserFormat? = nil
}

struct RequirementVerificationResourceLimits: Codable, Hashable, Sendable {
    var maximumWallClockSeconds: UInt64
    var maximumCapturedOutputBytes: UInt64
    var maximumResidentBytes: UInt64
    var maximumChildProcesses: UInt64
}

enum RequirementVerificationTransport: String, Codable, Hashable, Sendable {
    /// Direct executable launch only. Shells, command strings, remote
    /// transports, and provider/model invocations are deliberately absent.
    case localDirectProcess
}

struct RequirementVerificationExecutableProbe: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var transport: RequirementVerificationTransport
    var executableContentDigest: ContentDigest
    /// Exact argv elements after argv[0]. They are data, never a shell string.
    var fixedArguments: [String]
    var inputBindings: [RequirementVerificationInputBinding]
    var environmentPolicy: KernelEnvironmentPolicy
    var environmentIdentityDigest: ContentDigest
    var captureIdentityDigest: ContentDigest
    var parser: RequirementVerificationParserContract
    /// Exact recognized parser result codes. Any unmatched exit/result pair
    /// must map to `unmatchedOutcome`, which validation requires to be red.
    var resultMappings: [RequirementVerificationResultMapping]
    var unmatchedOutcome: RequirementVerificationOutcome
    var networkPolicy: KernelNetworkPolicy
    var resourceLimits: RequirementVerificationResourceLimits

    func validationIssues() -> [String] {
        var issues: [String] = []
        func isExactSHA256(_ digest: ContentDigest) -> Bool {
            let value = digest.rawValue
            return value.utf8.count == 64
                && value.utf8.allSatisfy {
                    (48...57).contains($0) || (97...102).contains($0)
                }
        }
        func isExactIdentity(_ value: String, maximumUTF8Bytes: Int = 512) -> Bool {
            !value.isEmpty
                && value.utf8.count <= maximumUTF8Bytes
                && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && value.unicodeScalars.allSatisfy {
                    !CharacterSet.controlCharacters.contains($0)
                }
        }

        if schemaVersion <= 0 || schemaVersion > 2 {
            issues.append("verification probe schemaVersion must be supported")
        }
        if transport != .localDirectProcess {
            issues.append("verification probe must use direct local executable transport")
        }
        if !isExactSHA256(executableContentDigest) {
            issues.append("verification executable content digest must be exact lowercase SHA-256")
        }
        if fixedArguments.count > 64 || fixedArguments.contains(where: {
            $0.utf8.count > 4_096 || $0.contains("\0")
        }) {
            issues.append("verification arguments exceed the bounded exact argv policy")
        }
        let inputIDs = inputBindings.map(\.id)
        if inputBindings.isEmpty
            || inputBindings.count > 64
            || Set(inputIDs).count != inputIDs.count
            || inputBindings.contains(where: { binding in
                !isExactIdentity(binding.id)
                    || !isExactIdentity(binding.artifactID)
                    || binding.argumentToken != "@loopforge-input:\(binding.id)"
                    || fixedArguments.filter({
                        $0 == binding.argumentToken
                    }).count != 1
            }) {
            issues.append("verification input bindings must have unique exact identities and one exact argv token")
        }
        if inputBindings.filter({ $0.kind == .candidatePostimage }).count != 1 {
            issues.append("verification probe must bind exactly one candidate postimage input")
        }
        if environmentPolicy != .minimalKernelAllowlist {
            issues.append("verification probe must use the minimal kernel environment")
        }
        if networkPolicy != .disabled {
            issues.append("verification probe network access must be disabled")
        }
        if !isExactSHA256(environmentIdentityDigest)
            || !isExactSHA256(captureIdentityDigest) {
            issues.append("verification environment and capture identities must be exact lowercase SHA-256")
        }
        if !isExactIdentity(parser.id)
            || parser.schemaVersion <= 0
            || !isExactSHA256(parser.contentDigest) {
            issues.append("verification parser identity, schema, and content digest must be exact")
        }
        if schemaVersion >= 2,
           (parser.schemaVersion != 1
            || parser.format != .canonicalJSONResultV1
            || parser.contentDigest != parser.format?.implementationIdentityDigest) {
            issues.append("verification parser format and implementation digest must identify the supported canonical result grammar")
        }
        let mappingKeys = resultMappings.map {
            "\($0.exitCode)\u{1f}\($0.parserResultCode)"
        }
        if resultMappings.isEmpty
            || resultMappings.count > 64
            || Set(mappingKeys).count != mappingKeys.count
            || resultMappings.contains(where: {
                !isExactIdentity($0.parserResultCode)
            })
            || !resultMappings.contains(where: { $0.outcome == .accepted }) {
            issues.append("verification result mapping must be unique, exact, and include an accepted result")
        }
        if unmatchedOutcome != .rejected {
            issues.append("unmatched verification results must be rejected")
        }
        if resourceLimits.maximumWallClockSeconds == 0
            || resourceLimits.maximumCapturedOutputBytes == 0
            || resourceLimits.maximumResidentBytes == 0
            || resourceLimits.maximumChildProcesses != 0 {
            issues.append("verification resource limits must be positive and forbid child processes")
        }
        return issues
    }
}

struct RequirementEvidenceRecipe: Codable, Hashable, Sendable {
    var id: EvidenceRecipeID
    var requirementID: RequirementID
    var verifierKind: RequirementVerifierKind
    var expectedObservation: String
    var requiresIndependentLineage: Bool
    /// Optional solely so pre-executable-recipe journals remain decodable for
    /// forensic recovery. New compilation and enrollment require a valid probe.
    var executableProbe: RequirementVerificationExecutableProbe? = nil
}

enum TaskContractAmbiguityImpact: String, Codable, Hashable, Sendable {
    case local
    case implementationDetail
    case protectedIdentityOrDesign
    case authorityScope
    case mandatoryOutcome
    case unavailableEvidence
    case destructiveCostlyOrExternal
}

enum TaskContractAmbiguityResolution: String, Codable, Hashable, Sendable {
    case boundedAssumption
    case rollbackExperiment
    case requestAuthority
    case preserveBaseline
    case denyPendingAuthority
    case userAmendmentRequired
    case readOnlyDiscovery
}

struct TaskContractAmbiguity: Codable, Hashable, Sendable {
    var id: TaskContractAmbiguityID
    var sourceSpans: [TaskContractSourceSpan]
    var impact: TaskContractAmbiguityImpact
    var reversible: Bool
    var resolution: TaskContractAmbiguityResolution
}

struct TaskContractCompilationCandidate: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var revision: UInt64
    var initialObjectiveSourceID: TaskContractSourceID
    var sources: [TaskContractSourceArtifact]
    var contract: TaskContract
    var requirementBindings: [RequirementSourceBinding]
    var constraintBindings: [ConstraintSourceBinding]
    var evidenceRecipes: [RequirementEvidenceRecipe]
    var ambiguities: [TaskContractAmbiguity]
    /// Optional only for decoding candidates authored before native workspace
    /// selection was bound to the contract.
    var workspaceSourceBinding: WorkspaceSourceBinding? = nil
    /// Required when the contract declares a duration acceptance obligation.
    var durationAcceptanceSourceBinding: DurationAcceptanceSourceBinding? = nil
    /// Required whenever an execution profile is declared.
    var executionProfileSourceBinding: ExecutionProfileSourceBinding? = nil
    /// Required whenever bounded execution budgets are declared.
    var executionBudgetSourceBinding: ExecutionBudgetSourceBinding? = nil
    /// Required whenever the candidate carries a captured workspace revision.
    /// The source must remain a workspace observation; the later native user
    /// confirmation binds the complete candidate digest.
    var sourceRevisionSourceBinding: SourceRevisionSourceBinding? = nil
    /// Required whenever a user-confirmable causal strategy is proposed.
    var causalStrategyAuthoritySourceBinding:
        CausalStrategyAuthoritySourceBinding? = nil
    /// Required whenever a user-confirmable execution plan is proposed.
    var executionPlanSourceBinding: ExecutionPlanSourceBinding? = nil
    /// Optional solely for decoding pre-dependency compiler candidates.
    var externalDependencyBindings: [ExternalDependencySourceBinding]? = nil
    var compilerActor: ActorIdentity
    var compiledAt: Date
}

enum TaskContractCompilationIssue: Equatable, Sendable {
    case invalidSchemaVersion
    case invalidRevision
    case duplicateSourceID
    case malformedSource(String)
    case objectiveSourceMissing
    case objectiveSourceLacksUserAuthority
    case objectiveNotVerbatim
    case objectiveDigestMismatch
    case invalidContract(String)
    case duplicateRequirementBinding(String)
    case requirementBindingMismatch
    case duplicateConstraintBinding(String)
    case constraintBindingMismatch
    case missingSourceSpan(String)
    case invalidSourceSpan(String)
    case explicitClaimLacksUserAuthority(String)
    case cardinalityLacksExplicitAuthority(String)
    case duplicateExternalDependencyBinding(String)
    case externalDependencyBindingMismatch
    case externalDependencyLacksExplicitAuthority(String)
    case workspaceBindingMismatch
    case durationAcceptanceBindingMismatch
    case executionProfileBindingMismatch
    case executionProfileSourceMismatch
    case executionBudgetBindingMismatch
    case executionBudgetSourceMismatch
    case sourceRevisionBindingMismatch
    case sourceRevisionSourceMismatch
    case causalStrategyAuthorityBindingMismatch
    case causalStrategyAuthoritySourceMismatch
    case executionPlanBindingMismatch
    case executionPlanSourceMismatch
    case duplicateCapabilityGrantReceipt(String)
    case capabilityGrantSetMismatch
    case capabilityGrantReceiptMismatch(String)
    case duplicateEvidenceRecipe(String)
    case evidenceRecipeMismatch(String)
    case missingMandatoryEvidenceRecipe(String)
    case duplicateAmbiguity(String)
    case invalidAmbiguityResolution(String)
    case unboundAuthorityExpansion
    case encodingFailed
}

struct TaskContractCompilationFailure: Error, Equatable, Sendable {
    var issues: [TaskContractCompilationIssue]
}

enum TaskContractExecutionEligibility: String, Equatable, Sendable {
    case readOnlyDiscovery
    case contractAuthorityCeiling
}

struct CompiledTaskContractCandidate: Equatable, Sendable {
    var candidate: TaskContractCompilationCandidate
    var candidateDigest: ContentDigest
    var capabilityGrantReceiptDigests: [String: ContentDigest]
    var executionEligibility: TaskContractExecutionEligibility
    var blockingAmbiguityIDs: [TaskContractAmbiguityID]
}

struct TaskContractUserConfirmationReceipt: Equatable, Sendable {
    fileprivate var candidateDigest: ContentDigest
    fileprivate var confirmationNonce: ContentDigest
    fileprivate var confirmedAt: Date
    fileprivate var userActor: ActorIdentity

#if DEBUG
    static func testOnlyExactConfirmation(
        candidateDigest: ContentDigest,
        confirmationNonce: ContentDigest = ContentDigest("test-confirmation"),
        confirmedAt: Date = Date(timeIntervalSince1970: 1),
        userActor: ActorIdentity = ActorIdentity(
            id: ActorID("test-user"),
            role: "user",
            lineageDigest: ContentDigest("test-user-lineage")
        )
    ) -> Self {
        Self(
            candidateDigest: candidateDigest,
            confirmationNonce: confirmationNonce,
            confirmedAt: confirmedAt,
            userActor: userActor
        )
    }
#endif
}

/// Out-of-band authority for one exact capability selection. This deliberately
/// does not conform to `Codable`: a model-authored compilation candidate can
/// propose a capability, but cannot serialize the authority needed to grant it.
/// The native issuer remains a separate trusted boundary.
struct TaskContractCapabilityGrantReceipt: Equatable, Sendable {
    fileprivate var contractID: TaskContractID
    fileprivate var candidateRevision: UInt64
    fileprivate var authorityCeilingDigest: ContentDigest
    fileprivate var capabilityID: String
    fileprivate var grantNonceDigest: ContentDigest
    fileprivate var grantedAt: Date
    fileprivate var userActorID: ActorID
    fileprivate var userActorLineageDigest: ContentDigest

    /// Trusted native authoring boundary for one capability that the user
    /// explicitly selected in the app. Keeping the receipt non-Codable means
    /// a decoded/model-authored candidate still cannot manufacture this
    /// authority. The compiler independently revalidates every field against
    /// the exact candidate before including its digest in candidate identity.
    static func nativeUserSelectedGrant(
        contractID: TaskContractID,
        candidateRevision: UInt64,
        authorityCeilingDigest: ContentDigest,
        capabilityID: String,
        grantNonceDigest: ContentDigest,
        grantedAt: Date,
        userActor: ActorIdentity
    ) -> Self {
        Self(
            contractID: contractID,
            candidateRevision: candidateRevision,
            authorityCeilingDigest: authorityCeilingDigest,
            capabilityID: capabilityID,
            grantNonceDigest: grantNonceDigest,
            grantedAt: grantedAt,
            userActorID: userActor.id,
            userActorLineageDigest: userActor.lineageDigest
        )
    }

#if DEBUG
    static func testOnlyExactGrant(
        contractID: TaskContractID,
        candidateRevision: UInt64,
        authorityCeilingDigest: ContentDigest,
        capabilityID: String,
        grantNonceDigest: ContentDigest = ContentDigest("test-capability-grant"),
        grantedAt: Date = Date(timeIntervalSince1970: 1),
        userActorID: ActorID = ActorID("user"),
        userActorLineageDigest: ContentDigest = ContentDigest("user-lineage")
    ) -> Self {
        Self(
            contractID: contractID,
            candidateRevision: candidateRevision,
            authorityCeilingDigest: authorityCeilingDigest,
            capabilityID: capabilityID,
            grantNonceDigest: grantNonceDigest,
            grantedAt: grantedAt,
            userActorID: userActorID,
            userActorLineageDigest: userActorLineageDigest
        )
    }
#endif
}

private struct CapabilityGrantDigestMaterial: Encodable {
    var contractID: TaskContractID
    var candidateRevision: UInt64
    var authorityCeilingDigest: ContentDigest
    var capabilityID: String
    var grantNonceDigest: ContentDigest
    var grantedAtBitPattern: UInt64
    var userActorID: ActorID
    var userActorLineageDigest: ContentDigest
}

private struct CapabilityBoundCandidateDigestMaterial: Encodable {
    var unboundCandidateDigest: ContentDigest
    var capabilityGrantReceiptDigests: [String: ContentDigest]
}

struct TaskContractRatificationReceipt: Equatable, Sendable {
    var receiptID: ReceiptID
    var contractID: TaskContractID
    var revision: UInt64
    var candidateDigest: ContentDigest
    var capabilityGrantReceiptDigests: [String: ContentDigest]
    var confirmationNonceDigest: ContentDigest
    var confirmedAt: Date
    var userActorID: ActorID
    var userActorLineageDigest: ContentDigest
    var executionEligibility: TaskContractExecutionEligibility
    var blockingAmbiguityIDs: [TaskContractAmbiguityID]
}

struct RatifiedTaskContract: Equatable, Sendable {
    let contract: TaskContract
    let receipt: TaskContractRatificationReceipt

    /// Only the compiler that validates an out-of-band user confirmation may
    /// manufacture this capability-bearing value. Production enrollment takes
    /// this sealed value rather than accepting a bare, model-constructible
    /// `TaskContract` as authority.
    fileprivate init(
        contract: TaskContract,
        receipt: TaskContractRatificationReceipt
    ) {
        self.contract = contract
        self.receipt = receipt
    }
}

enum TaskContractRatificationError: Error, Equatable {
    case candidateDigestMismatch
    case malformedConfirmation
}

enum NativeTaskContractConfirmationError: Error, Equatable {
    case displayedCandidateChanged
    case displayedSourceRevisionChanged
    case sourceRevisionRecaptureFailed(String)
    case userIdentityMismatch
    case alreadyConfirmed
    case ratificationFailed(TaskContractRatificationError)
}

/// Native UI authority issuer. Preparation may be automated, but only an
/// explicit confirmation control calls this main-actor method with the digest
/// that was actually displayed. Durable single-use enforcement is repeated by
/// the recovery registry when the ratified contract is enrolled.
@MainActor
final class NativeTaskContractConfirmationIssuer {
    private var confirmedCandidateDigests: Set<ContentDigest> = []

    func confirmFromNativeUserAction(
        _ draft: NativeTaskContractConfirmationDraft,
        displayedCandidateDigest: ContentDigest,
        userActor: ActorIdentity,
        confirmedAt: Date
    ) -> Result<RatifiedTaskContract, NativeTaskContractConfirmationError> {
        guard displayedCandidateDigest == draft.compiled.candidateDigest else {
            return .failure(.displayedCandidateChanged)
        }
        guard draft.compiled.candidate.contract.sourceRevision ==
                draft.displaySourceRevision else {
            return .failure(.displayedCandidateChanged)
        }
        guard draft.compiled.candidate.contract.initialCausalStrategyAuthority ==
                draft.displayCausalStrategyAuthority,
              draft.compiled.candidate.contract.initialExecutionPlan ==
                draft.displayExecutionPlan else {
            return .failure(.displayedCandidateChanged)
        }
        let currentSourceRevision: WorkspaceSourceRevisionArtifact
        do {
            currentSourceRevision = try WorkspaceSourceRevisionCollector().capture(
                workspaceID: draft.workspaceID,
                root: draft.canonicalWorkspaceRoot,
                excludedDirectoryNames:
                    Set(draft.displaySourceRevision.excludedDirectoryNames),
                limits: draft.displaySourceRevision.limits
            )
        } catch {
            return .failure(.sourceRevisionRecaptureFailed(
                String(describing: error)
            ))
        }
        guard currentSourceRevision == draft.displaySourceRevision else {
            return .failure(.displayedSourceRevisionChanged)
        }
        guard let objectiveSource = draft.compiled.candidate.sources.first(where: {
            $0.id == draft.compiled.candidate.initialObjectiveSourceID
        }), objectiveSource.author == userActor else {
            return .failure(.userIdentityMismatch)
        }
        guard !confirmedCandidateDigests.contains(displayedCandidateDigest) else {
            return .failure(.alreadyConfirmed)
        }
        let nonceMaterial = Data([
            UUID().uuidString,
            displayedCandidateDigest.rawValue,
            userActor.id.rawValue,
            userActor.lineageDigest.rawValue,
            String(confirmedAt.timeIntervalSinceReferenceDate.bitPattern)
        ].joined(separator: "\u{1f}").utf8)
        let confirmation = TaskContractUserConfirmationReceipt(
            candidateDigest: displayedCandidateDigest,
            confirmationNonce: TaskContractCompiler.digest(nonceMaterial),
            confirmedAt: confirmedAt,
            userActor: userActor
        )
        switch TaskContractCompiler.ratify(
            draft.compiled,
            confirmation: confirmation
        ) {
        case .success(let ratified):
            confirmedCandidateDigests.insert(displayedCandidateDigest)
            return .success(ratified)
        case .failure(let error):
            return .failure(.ratificationFailed(error))
        }
    }
}

/// Pure, domain-neutral validation around optional semantic proposal work.
/// It never infers authority from task categories, provider names, filenames,
/// or model prose. A candidate with unresolved high-impact ambiguity can be
/// ratified for visibility, but its execution eligibility remains read-only.
enum TaskContractCompiler {
    static func compile(
        _ candidate: TaskContractCompilationCandidate,
        capabilityGrantReceipts: [TaskContractCapabilityGrantReceipt] = []
    ) -> Result<CompiledTaskContractCandidate, TaskContractCompilationFailure> {
        var issues: [TaskContractCompilationIssue] = []
        guard candidate.schemaVersion > 0 else {
            return .failure(TaskContractCompilationFailure(issues: [.invalidSchemaVersion]))
        }
        let sourceGroups = Dictionary(grouping: candidate.sources, by: \.id)
        if sourceGroups.values.contains(where: { $0.count != 1 }) {
            issues.append(.duplicateSourceID)
        }
        let sources = sourceGroups.compactMapValues(\.first)
        for source in candidate.sources {
            if source.exactUTF8.isEmpty || String(data: source.exactUTF8, encoding: .utf8) == nil ||
                source.digest != digest(source.exactUTF8) ||
                source.author.id.rawValue.isEmpty || source.author.lineageDigest.rawValue.isEmpty {
                issues.append(.malformedSource(source.id.rawValue))
            }
        }

        if let objective = sources[candidate.initialObjectiveSourceID] {
            if !objective.authority.mayCreateExplicitAuthority {
                issues.append(.objectiveSourceLacksUserAuthority)
            }
            if String(data: objective.exactUTF8, encoding: .utf8) !=
                candidate.contract.verbatimObjective {
                issues.append(.objectiveNotVerbatim)
            }
        } else {
            issues.append(.objectiveSourceMissing)
        }
        if candidate.contract.objectiveDigest != digest(
            Data(candidate.contract.verbatimObjective.utf8)
        ) {
            issues.append(.objectiveDigestMismatch)
        }
        issues.append(contentsOf: candidate.contract.validationIssues().map {
            .invalidContract($0)
        })

        let requirementGroups = Dictionary(
            grouping: candidate.requirementBindings,
            by: \.requirementID
        )
        for id in requirementGroups.keys.sorted(by: { $0.rawValue < $1.rawValue })
        where requirementGroups[id]?.count != 1 {
            issues.append(.duplicateRequirementBinding(id.rawValue))
        }
        if Set(requirementGroups.keys) != Set(candidate.contract.requirements.map(\.id)) {
            issues.append(.requirementBindingMismatch)
        }
        for binding in candidate.requirementBindings {
            validate(
                spans: binding.sourceSpans,
                bindingName: "requirement:\(binding.requirementID.rawValue)",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
        }
        for requirement in candidate.contract.requirements
        where requirement.deliverableCardinality != nil {
            guard requirementGroups[requirement.id]?.count == 1,
                  requirementGroups[requirement.id]?.first?.epistemicState == .explicit else {
                issues.append(.cardinalityLacksExplicitAuthority(requirement.id.rawValue))
                continue
            }
        }

        let constraintGroups = Dictionary(
            grouping: candidate.constraintBindings,
            by: \.constraintID
        )
        for id in constraintGroups.keys.sorted()
        where constraintGroups[id]?.count != 1 {
            issues.append(.duplicateConstraintBinding(id))
        }
        if Set(constraintGroups.keys) != Set(candidate.contract.constraints.map(\.id)) {
            issues.append(.constraintBindingMismatch)
        }
        for binding in candidate.constraintBindings {
            validate(
                spans: binding.sourceSpans,
                bindingName: "constraint:\(binding.constraintID)",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
        }

        let dependencyBindings = candidate.externalDependencyBindings ?? []
        let dependencyBindingGroups = Dictionary(
            grouping: dependencyBindings,
            by: \.dependencyID
        )
        for id in dependencyBindingGroups.keys.sorted(by: {
            $0.rawValue < $1.rawValue
        }) where dependencyBindingGroups[id]?.count != 1 {
            issues.append(.duplicateExternalDependencyBinding(id.rawValue))
        }
        let dependencyIDs = Set((candidate.contract.externalDependencies ?? []).map(\.id))
        if Set(dependencyBindingGroups.keys) != dependencyIDs {
            issues.append(.externalDependencyBindingMismatch)
        }
        for binding in dependencyBindings {
            validate(
                spans: binding.sourceSpans,
                bindingName: "external-dependency:\(binding.dependencyID.rawValue)",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.externalDependencyLacksExplicitAuthority(
                    binding.dependencyID.rawValue
                ))
            }
        }

        switch (candidate.contract.workspaceBinding, candidate.workspaceSourceBinding) {
        case (.none, .none):
            break
        case (.some, .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "workspace-binding",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.workspaceBindingMismatch)
            }
        case (.none, .some), (.some, .none):
            issues.append(.workspaceBindingMismatch)
        }

        switch (
            candidate.contract.acceptancePolicy.duration,
            candidate.durationAcceptanceSourceBinding
        ) {
        case (.none, .none):
            break
        case (.some, .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "duration-acceptance",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.durationAcceptanceBindingMismatch)
            }
        case (.none, .some), (.some, .none):
            issues.append(.durationAcceptanceBindingMismatch)
        }

        switch (
            candidate.contract.executionProfile,
            candidate.executionProfileSourceBinding
        ) {
        case (.none, .none):
            break
        case (.some(let profile), .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "execution-profile",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.executionProfileBindingMismatch)
            }
            let span = binding.sourceSpans.count == 1
                ? binding.sourceSpans.first
                : nil
            guard let span,
                  let source = sources[span.sourceID],
                  span.lowerUTF8Offset == 0,
                  span.upperUTF8Offset == source.exactUTF8.count,
                  source.exactUTF8 == executionProfileData(profile) else {
                issues.append(.executionProfileSourceMismatch)
                break
            }
        case (.none, .some), (.some, .none):
            issues.append(.executionProfileBindingMismatch)
        }

        switch (
            candidate.contract.executionBudgets,
            candidate.executionBudgetSourceBinding
        ) {
        case (.none, .none):
            break
        case (.some(let budgets), .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "execution-budgets",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.executionBudgetBindingMismatch)
            }
            let span = binding.sourceSpans.count == 1
                ? binding.sourceSpans.first
                : nil
            guard let span,
                  let source = sources[span.sourceID],
                  span.lowerUTF8Offset == 0,
                  span.upperUTF8Offset == source.exactUTF8.count,
                  source.exactUTF8 == executionBudgetData(budgets) else {
                issues.append(.executionBudgetSourceMismatch)
                break
            }
        case (.none, .some), (.some, .none):
            issues.append(.executionBudgetBindingMismatch)
        }

        switch (
            candidate.contract.sourceRevision,
            candidate.sourceRevisionSourceBinding
        ) {
        case (.none, .none):
            break
        case (.some(let revision), .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "source-revision",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .workspaceObserved {
                issues.append(.sourceRevisionBindingMismatch)
            }
            let span = binding.sourceSpans.count == 1
                ? binding.sourceSpans.first
                : nil
            guard let span,
                  let source = sources[span.sourceID],
                  source.authority == .workspaceObservation,
                  span.lowerUTF8Offset == 0,
                  span.upperUTF8Offset == source.exactUTF8.count,
                  source.exactUTF8 == sourceRevisionData(revision) else {
                issues.append(.sourceRevisionSourceMismatch)
                break
            }
        case (.none, .some), (.some, .none):
            issues.append(.sourceRevisionBindingMismatch)
        }

        switch (
            candidate.contract.initialCausalStrategyAuthority,
            candidate.causalStrategyAuthoritySourceBinding
        ) {
        case (.none, .none):
            break
        case (.some(let authority), .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "causal-strategy-authority",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.causalStrategyAuthorityBindingMismatch)
            }
            let span = binding.sourceSpans.count == 1
                ? binding.sourceSpans.first
                : nil
            guard let span,
                  let source = sources[span.sourceID],
                  source.authority.mayCreateExplicitAuthority,
                  span.lowerUTF8Offset == 0,
                  span.upperUTF8Offset == source.exactUTF8.count,
                  source.exactUTF8 == causalStrategyAuthorityData(authority) else {
                issues.append(.causalStrategyAuthoritySourceMismatch)
                break
            }
        case (.none, .some), (.some, .none):
            issues.append(.causalStrategyAuthorityBindingMismatch)
        }

        switch (
            candidate.contract.initialExecutionPlan,
            candidate.executionPlanSourceBinding
        ) {
        case (.none, .none):
            break
        case (.some(let plan), .some(let binding)):
            validate(
                spans: binding.sourceSpans,
                bindingName: "execution-plan",
                epistemicState: binding.epistemicState,
                sources: sources,
                issues: &issues
            )
            if binding.epistemicState != .explicit {
                issues.append(.executionPlanBindingMismatch)
            }
            let span = binding.sourceSpans.count == 1
                ? binding.sourceSpans.first
                : nil
            guard let span,
                  let source = sources[span.sourceID],
                  source.authority.mayCreateExplicitAuthority,
                  span.lowerUTF8Offset == 0,
                  span.upperUTF8Offset == source.exactUTF8.count,
                  source.exactUTF8 == executionPlanData(plan) else {
                issues.append(.executionPlanSourceMismatch)
                break
            }
        case (.none, .some), (.some, .none):
            issues.append(.executionPlanBindingMismatch)
        }

        let capabilityGrantGroups = Dictionary(
            grouping: capabilityGrantReceipts,
            by: \.capabilityID
        )
        for capabilityID in capabilityGrantGroups.keys.sorted()
        where capabilityGrantGroups[capabilityID]?.count != 1 {
            issues.append(.duplicateCapabilityGrantReceipt(capabilityID))
        }
        let capabilityIDs = candidate.contract.authorityCeiling.capabilityIDs
        if Set(capabilityGrantGroups.keys) != capabilityIDs {
            issues.append(.capabilityGrantSetMismatch)
        }
        guard let authorityCeilingDigest = authorityCeilingDigest(
            candidate.contract.authorityCeiling
        ) else {
            return .failure(TaskContractCompilationFailure(issues: [.encodingFailed]))
        }
        let objectiveAuthor = sources[candidate.initialObjectiveSourceID]?.author
        for receipt in capabilityGrantReceipts {
            let normalizedCapabilityID = receipt.capabilityID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if receipt.contractID != candidate.contract.id
                || receipt.candidateRevision != candidate.revision
                || receipt.authorityCeilingDigest != authorityCeilingDigest
                || !capabilityIDs.contains(receipt.capabilityID)
                || normalizedCapabilityID.isEmpty
                || normalizedCapabilityID != receipt.capabilityID
                || receipt.grantNonceDigest.rawValue.isEmpty
                || !receipt.grantedAt.timeIntervalSince1970.isFinite
                || receipt.grantedAt.timeIntervalSince1970 < 0
                || receipt.grantedAt > candidate.compiledAt
                || receipt.userActorID.rawValue.isEmpty
                || receipt.userActorLineageDigest.rawValue.isEmpty
                || receipt.userActorID != objectiveAuthor?.id
                || receipt.userActorLineageDigest != objectiveAuthor?.lineageDigest {
                issues.append(.capabilityGrantReceiptMismatch(receipt.capabilityID))
            }
        }

        let recipeGroups = Dictionary(grouping: candidate.evidenceRecipes, by: \.id)
        for id in recipeGroups.keys.sorted(by: { $0.rawValue < $1.rawValue })
        where recipeGroups[id]?.count != 1 {
            issues.append(.duplicateEvidenceRecipe(id.rawValue))
        }
        let requirementsByID = Dictionary(
            grouping: candidate.contract.requirements,
            by: \.id
        ).compactMapValues { $0.count == 1 ? $0.first : nil }
        for recipe in candidate.evidenceRecipes {
            guard requirementsByID[recipe.requirementID] != nil,
                  !recipe.expectedObservation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty,
                  recipe.requiresIndependentLineage,
                  let executableProbe = recipe.executableProbe,
                  executableProbe.validationIssues().isEmpty else {
                issues.append(.evidenceRecipeMismatch(recipe.id.rawValue))
                continue
            }
            guard requirementsByID[recipe.requirementID]?.evidenceRecipeIDs.contains(
                recipe.id
            ) == true else {
                issues.append(.evidenceRecipeMismatch(recipe.id.rawValue))
                continue
            }
        }
        for requirement in candidate.contract.requirements {
            let declared = Set(candidate.evidenceRecipes.lazy.filter {
                $0.requirementID == requirement.id
            }.map(\.id))
            if requirement.mandatory
                && (declared.isEmpty || declared != requirement.evidenceRecipeIDs) {
                issues.append(.missingMandatoryEvidenceRecipe(requirement.id.rawValue))
            } else if declared != requirement.evidenceRecipeIDs {
                issues.append(.evidenceRecipeMismatch(
                    "requirement:\(requirement.id.rawValue)"
                ))
            }
        }

        let ambiguityGroups = Dictionary(grouping: candidate.ambiguities, by: \.id)
        for id in ambiguityGroups.keys.sorted(by: { $0.rawValue < $1.rawValue })
        where ambiguityGroups[id]?.count != 1 {
            issues.append(.duplicateAmbiguity(id.rawValue))
        }
        for ambiguity in candidate.ambiguities {
            validate(
                spans: ambiguity.sourceSpans,
                bindingName: "ambiguity:\(ambiguity.id.rawValue)",
                epistemicState: .unknown,
                sources: sources,
                issues: &issues
            )
            if !validResolution(for: ambiguity) {
                issues.append(.invalidAmbiguityResolution(ambiguity.id.rawValue))
            }
        }

        let expandsAuthority = !candidate.contract.authorityCeiling.writableScopes.isEmpty ||
            !candidate.contract.authorityCeiling.capabilityIDs.isEmpty ||
            candidate.contract.authorityCeiling.permitsExternalPublication
        let explicitAuthority = candidate.contract.constraints.contains {
            $0.kind == .requireAuthority &&
                constraintGroups[$0.id]?.first?.epistemicState == .explicit
        }
        if expandsAuthority && !explicitAuthority {
            issues.append(.unboundAuthorityExpansion)
        }

        guard issues.isEmpty else {
            return .failure(TaskContractCompilationFailure(issues: issues))
        }
        var capabilityGrantReceiptDigests: [String: ContentDigest] = [:]
        for receipt in capabilityGrantReceipts {
            guard let receiptDigest = capabilityGrantDigest(receipt) else {
                return .failure(TaskContractCompilationFailure(issues: [.encodingFailed]))
            }
            capabilityGrantReceiptDigests[receipt.capabilityID] = receiptDigest
        }
        guard let candidateDigest = sealedCandidateDigest(
            candidate,
            capabilityGrantReceiptDigests: capabilityGrantReceiptDigests
        ) else {
            return .failure(TaskContractCompilationFailure(issues: [.encodingFailed]))
        }
        let blockers = candidate.ambiguities.filter(isBlocking).map(\.id).sorted {
            $0.rawValue < $1.rawValue
        }
        return .success(CompiledTaskContractCandidate(
            candidate: candidate,
            candidateDigest: candidateDigest,
            capabilityGrantReceiptDigests: capabilityGrantReceiptDigests,
            executionEligibility: blockers.isEmpty
                ? .contractAuthorityCeiling
                : .readOnlyDiscovery,
            blockingAmbiguityIDs: blockers
        ))
    }

    static func ratify(
        _ compiled: CompiledTaskContractCandidate,
        confirmation: TaskContractUserConfirmationReceipt
    ) -> Result<RatifiedTaskContract, TaskContractRatificationError> {
        let currentBlockers = compiled.candidate.ambiguities.filter(isBlocking)
            .map(\.id).sorted { $0.rawValue < $1.rawValue }
        let currentEligibility: TaskContractExecutionEligibility =
            currentBlockers.isEmpty ? .contractAuthorityCeiling : .readOnlyDiscovery
        guard confirmation.candidateDigest == compiled.candidateDigest,
              sealedCandidateDigest(
                compiled.candidate,
                capabilityGrantReceiptDigests:
                    compiled.capabilityGrantReceiptDigests
              ) == compiled.candidateDigest,
              currentBlockers == compiled.blockingAmbiguityIDs,
              currentEligibility == compiled.executionEligibility else {
            return .failure(.candidateDigestMismatch)
        }
        guard !confirmation.confirmationNonce.rawValue.isEmpty,
              !confirmation.userActor.id.rawValue.isEmpty,
              !confirmation.userActor.lineageDigest.rawValue.isEmpty,
              confirmation.confirmedAt >= compiled.candidate.compiledAt else {
            return .failure(.malformedConfirmation)
        }
        let material = Data(
            [
                compiled.candidate.contract.id.rawValue,
                String(compiled.candidate.revision),
                compiled.candidateDigest.rawValue,
                confirmation.confirmationNonce.rawValue,
                confirmation.userActor.id.rawValue,
                confirmation.userActor.lineageDigest.rawValue,
                String(confirmation.confirmedAt.timeIntervalSince1970)
            ].joined(separator: "\u{1f}").utf8
        )
        let nonceDigest = digest(Data(confirmation.confirmationNonce.rawValue.utf8))
        var durableContract = compiled.candidate.contract
        durableContract.requirementEvidenceRecipes =
            compiled.candidate.evidenceRecipes
        guard durableContract.hasCompleteRequirementEvidenceRecipeProvenance,
              durableContract.validationIssues().isEmpty else {
            return .failure(.candidateDigestMismatch)
        }
        return .success(RatifiedTaskContract(
            contract: durableContract,
            receipt: TaskContractRatificationReceipt(
                receiptID: ReceiptID("contract-ratification-\(digest(material).rawValue)"),
                contractID: compiled.candidate.contract.id,
                revision: compiled.candidate.revision,
                candidateDigest: compiled.candidateDigest,
                capabilityGrantReceiptDigests: compiled.capabilityGrantReceiptDigests,
                confirmationNonceDigest: nonceDigest,
                confirmedAt: confirmation.confirmedAt,
                userActorID: confirmation.userActor.id,
                userActorLineageDigest: confirmation.userActor.lineageDigest,
                executionEligibility: compiled.executionEligibility,
                blockingAmbiguityIDs: compiled.blockingAmbiguityIDs
            )
        ))
    }

    static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }

    private static func sealedCandidateDigest(
        _ candidate: TaskContractCompilationCandidate,
        capabilityGrantReceiptDigests: [String: ContentDigest]
    ) -> ContentDigest? {
        guard let encoded = try? canonicalData(candidate) else { return nil }
        let unboundCandidateDigest = digest(encoded)
        guard !capabilityGrantReceiptDigests.isEmpty else {
            return unboundCandidateDigest
        }
        guard let authorityBoundEncoding = try? canonicalData(
            CapabilityBoundCandidateDigestMaterial(
                unboundCandidateDigest: unboundCandidateDigest,
                capabilityGrantReceiptDigests: capabilityGrantReceiptDigests
            )
        ) else {
            return nil
        }
        return digest(authorityBoundEncoding)
    }

    static func authorityCeilingDigest(
        _ authorityCeiling: KernelAuthorityCeiling
    ) -> ContentDigest? {
        guard let encoded = try? canonicalData(authorityCeiling) else { return nil }
        return digest(encoded)
    }

    static func executionProfileData(
        _ executionProfile: KernelExecutionProfile
    ) -> Data? {
        try? canonicalData(executionProfile)
    }

    static func executionBudgetData(
        _ executionBudgets: KernelExecutionBudgetPolicy
    ) -> Data? {
        try? canonicalData(executionBudgets)
    }

    static func sourceRevisionData(
        _ sourceRevision: WorkspaceSourceRevisionArtifact
    ) -> Data? {
        try? canonicalData(sourceRevision)
    }

    static func causalStrategyAuthorityData(
        _ authority: KernelCausalStrategyAuthority
    ) -> Data? {
        try? canonicalData(authority)
    }

    static func executionPlanData(_ plan: KernelPlanProposal) -> Data? {
        try? canonicalData(plan)
    }

    /// Causal strategy identity binds only the effective mutation surface, not
    /// display labels or node IDs. Canonical entry bytes define stable ordering.
    static func planMutationSurfaceDigest(
        _ plan: KernelPlanProposal
    ) -> ContentDigest? {
        let materials = plan.nodes.map { node in
            PlanMutationSurfaceMaterial(
                requirementIDs: node.requirementIDs.map(\.rawValue).sorted(),
                writablePaths: node.mutationScope.writablePaths.sorted(),
                maximumChangedFiles: node.mutationScope.maximumChangedFiles,
                maximumChangedBytes: node.mutationScope.maximumChangedBytes,
                capabilityIDs: node.capabilityIDs.sorted()
            )
        }
        let encoded = materials.compactMap { material in
            (try? canonicalData(material)).map { ($0, material) }
        }
        guard encoded.count == materials.count else { return nil }
        let ordered = encoded.sorted {
            $0.0.lexicographicallyPrecedes($1.0)
        }.map(\.1)
        guard let data = try? canonicalData(ordered) else { return nil }
        return digest(data)
    }

    static func capabilityGrantDigest(
        _ receipt: TaskContractCapabilityGrantReceipt
    ) -> ContentDigest? {
        guard receipt.grantedAt.timeIntervalSince1970.isFinite,
              let encoded = try? canonicalData(CapabilityGrantDigestMaterial(
                contractID: receipt.contractID,
                candidateRevision: receipt.candidateRevision,
                authorityCeilingDigest: receipt.authorityCeilingDigest,
                capabilityID: receipt.capabilityID,
                grantNonceDigest: receipt.grantNonceDigest,
                grantedAtBitPattern: receipt.grantedAt
                    .timeIntervalSinceReferenceDate.bitPattern,
                userActorID: receipt.userActorID,
                userActorLineageDigest: receipt.userActorLineageDigest
              )) else {
            return nil
        }
        return digest(encoded)
    }

    private static func validate(
        spans: [TaskContractSourceSpan],
        bindingName: String,
        epistemicState: TaskContractEpistemicState,
        sources: [TaskContractSourceID: TaskContractSourceArtifact],
        issues: inout [TaskContractCompilationIssue]
    ) {
        guard !spans.isEmpty else {
            issues.append(.missingSourceSpan(bindingName))
            return
        }
        var hasUserAuthority = false
        for span in spans {
            guard let source = sources[span.sourceID],
                  source.digest == span.sourceDigest,
                  span.lowerUTF8Offset >= 0,
                  span.upperUTF8Offset > span.lowerUTF8Offset,
                  span.upperUTF8Offset <= source.exactUTF8.count,
                  String(
                    data: source.exactUTF8.subdata(
                        in: span.lowerUTF8Offset..<span.upperUTF8Offset
                    ),
                    encoding: .utf8
                  ) != nil else {
                issues.append(.invalidSourceSpan(bindingName))
                continue
            }
            hasUserAuthority = hasUserAuthority || source.authority.mayCreateExplicitAuthority
        }
        if epistemicState == .explicit && !hasUserAuthority {
            issues.append(.explicitClaimLacksUserAuthority(bindingName))
        }
    }

    private static func validResolution(for ambiguity: TaskContractAmbiguity) -> Bool {
        switch ambiguity.impact {
        case .local:
            return ambiguity.reversible && ambiguity.resolution == .boundedAssumption
        case .implementationDetail:
            return ambiguity.reversible && ambiguity.resolution == .rollbackExperiment
        case .protectedIdentityOrDesign:
            return ambiguity.resolution == .requestAuthority ||
                ambiguity.resolution == .preserveBaseline
        case .authorityScope, .destructiveCostlyOrExternal:
            return ambiguity.resolution == .denyPendingAuthority
        case .mandatoryOutcome:
            return ambiguity.resolution == .userAmendmentRequired
        case .unavailableEvidence:
            return ambiguity.resolution == .readOnlyDiscovery
        }
    }

    private static func isBlocking(_ ambiguity: TaskContractAmbiguity) -> Bool {
        switch ambiguity.resolution {
        case .boundedAssumption, .rollbackExperiment, .preserveBaseline:
            return false
        case .requestAuthority, .denyPendingAuthority, .userAmendmentRequired,
             .readOnlyDiscovery:
            return true
        }
    }

    private static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
}

private struct PlanMutationSurfaceMaterial: Codable {
    var requirementIDs: [String]
    var writablePaths: [String]
    var maximumChangedFiles: Int
    var maximumChangedBytes: Int
    var capabilityIDs: [String]
}
