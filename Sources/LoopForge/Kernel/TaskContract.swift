import Foundation

struct RequirementContract: Codable, Hashable, Sendable {
    var id: RequirementID
    var statement: String
    var mandatory: Bool
    var evidenceRecipeIDs: Set<EvidenceRecipeID>
    /// Optional exact-set semantics for requirements whose user-authorized
    /// outcome declares a concrete number of independently identifiable
    /// deliverables. The opaque collection identity keeps the kernel neutral
    /// to artifact type, filename, framework, and product vocabulary.
    var deliverableCardinality: DeliverableCardinalityConstraint? = nil
}

struct DeliverableCardinalityConstraint: Codable, Hashable, Sendable {
    var collectionID: String
    var exactCount: UInt64
}

struct DeliverableMemberObservation: Codable, Hashable, Sendable {
    var stableID: String
    var contentDigest: ContentDigest
}

struct DeliverableCardinalityObservation: Codable, Hashable, Sendable {
    var requirementID: RequirementID
    var collectionID: String
    var members: Set<DeliverableMemberObservation>
    var evidenceDigest: ContentDigest
}

struct ConstraintContract: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case preserve
        case prohibit
        case prohibitSubstitution
        case bound
        case requireAuthority
    }

    var id: String
    var kind: Kind
    var statement: String
    /// Opaque implementation identities make exact-surface enforcement
    /// independent of provider, product, framework, or brand vocabulary.
    /// The contract compiler, not the verifier, decides which identities are
    /// equivalent. Verification may only attest one of those exact values.
    var substitutionRule: ExactImplementationConstraint? = nil
}

struct ExactImplementationConstraint: Codable, Hashable, Sendable {
    var requirementIDs: Set<RequirementID>
    var permittedImplementationIDs: Set<String>
}

struct ExactImplementationObservation: Codable, Hashable, Sendable {
    var constraintID: String
    var implementationID: String
    var evidenceDigest: ContentDigest
}

enum ProtectedWorkspaceEntryScope: String, Codable, Hashable, Sendable {
    case exactEntry
    case subtree
}

struct ProtectedWorkspaceEntry: Codable, Hashable, Sendable {
    var path: String
    var contentDigest: ContentDigest
    var scope: ProtectedWorkspaceEntryScope
}

struct BaselineReference: Codable, Hashable, Sendable {
    var id: BaselineID
    var artifactDigest: ContentDigest
    var environmentDigest: ContentDigest?
    var preservationRequired: Bool
    /// Optional for decoding pre-v2 contracts and for immutable baseline
    /// artifacts that live outside the mutable workspace.
    var protectedWorkspaceEntries: Set<ProtectedWorkspaceEntry>? = nil
}

enum ExternalDependencyKind: String, Codable, Hashable, Sendable {
    case authority
    case capability
    case resource
    case externalCondition
}

struct ExternalDependencyContract: Codable, Hashable, Sendable {
    var id: ExternalDependencyID
    var kind: ExternalDependencyKind
    var requirementIDs: Set<RequirementID>
    var evidenceRecipeID: ExternalDependencyEvidenceRecipeID
    /// Exact observer lineages are frozen by the ratified contract. A runtime
    /// reviewer role string cannot grant itself availability authority.
    var authorizedObserverLineageDigests: Set<ContentDigest>
    /// Optional only so pre-executable dependency contracts remain decodable
    /// for read-only forensic recovery. New contract validation and enrollment
    /// require an exact bounded executable probe.
    var executableProbe: ExternalDependencyObservationExecutableProbe? = nil
}

struct ProtectedWorkspaceEntryBinding: Codable, Hashable, Sendable {
    var baselineID: BaselineID
    var entry: ProtectedWorkspaceEntry
}

struct KernelAuthorityCeiling: Codable, Hashable, Sendable {
    var readableScopes: Set<String>
    var writableScopes: Set<String>
    var capabilityIDs: Set<String>
    var permitsExternalPublication: Bool

    static let readOnly = KernelAuthorityCeiling(
        readableScopes: [],
        writableScopes: [],
        capabilityIDs: [],
        permitsExternalPublication: false
    )
}

struct DurationAcceptancePolicy: Codable, Hashable, Sendable {
    enum EligibleClass: String, Codable, Sendable {
        case acceptedExecution
        case acceptedScheduledExecution
        case acceptedInteractiveExecution
    }

    var requiredSeconds: UInt64
    var eligibleClass: EligibleClass
}

struct TaskAcceptancePolicy: Codable, Hashable, Sendable {
    var duration: DurationAcceptancePolicy?
    var requiresIndependentReview: Bool
    var requiresQuiescence: Bool
}

/// Binds a ratified contract to the exact workspace selected by the user.
/// Only a digest of the canonical absolute root is persisted.
struct TaskContractWorkspaceBinding: Codable, Hashable, Sendable {
    var workspaceID: WorkspaceID
    var canonicalRootDigest: ContentDigest
}

enum KernelExecutionProvider: String, Codable, Hashable, Sendable {
    case codex
    case local
    case api
}

enum KernelExecutionSandbox: String, Codable, Hashable, Sendable {
    case readOnly
    case workspaceOnly
    case fullAccess
}

enum KernelNetworkPolicy: String, Codable, Hashable, Sendable {
    case disabled
    case enabled
}

enum KernelPluginPolicy: String, Codable, Hashable, Sendable {
    case disabled
    case userInstalled
}

enum KernelEnvironmentPolicy: String, Codable, Hashable, Sendable {
    /// Only the kernel-owned, deterministic allowlist may reach the child.
    case minimalKernelAllowlist
    /// Additional names must be ratified by a future typed capability grant.
    case declaredAllowlist
}

enum KernelProviderProtocol: String, Codable, Hashable, Sendable {
    /// The exact executable is retained as evidence, but no production
    /// provider protocol has been ratified for it. It cannot be launched by
    /// the kernel's provider invocation compiler.
    case unavailable
    /// Historical prompt/credential transport without a post-compilation
    /// invocation-context channel. Retained only for forensic decoding and
    /// never accepted by the current compiler.
    case loopForgeProviderHarnessV1
    /// Canonical prompt plus fixed-FD invocation context and optional
    /// credential transport, with canonical JSONL result output.
    case loopForgeProviderHarnessV2
}

enum KernelProviderHarnessMode: String, Codable, Hashable, Sendable {
    /// Historical or unratified executable. It cannot satisfy V2 readiness.
    case unavailable
    /// The descriptor, prompt, credential, and canonical-result protocol is
    /// independently packaged and validated, but no productive provider
    /// backend is installed. Launch may only produce a fail-closed blocked
    /// proposal; it can never claim productive completion.
    case transportVetoOnly
    /// Reserved for a separately ratified harness whose productive provider
    /// backend, privileged or virtualized isolation product, and complete
    /// resource boundary are all present. An ordinary package manifest can
    /// never mint this authority by relabeling an executable.
    case productive
}

enum KernelProviderCredentialMode: String, Codable, Hashable, Sendable {
    /// The ratified harness authenticates without a LoopForge-delivered
    /// secret, for example a local runtime or an independently signed-in
    /// provider session.
    case none
    /// One exact stored credential must cross only the fixed descriptor.
    case opaqueProviderSecret
}

enum KernelProviderCredentialSource: String, Codable, Hashable, Sendable {
    case macOSKeychainGenericPassword
}

/// Safe, user-visible identity for a stored credential. It never contains the
/// credential value, a value digest, or a recovery token. The exact reference
/// is contract authority; provider kind alone must never select ambient keys.
struct KernelProviderCredentialReference: Codable, Hashable, Sendable {
    var source: KernelProviderCredentialSource
    var service: String
    var account: String

    var isValid: Bool {
        !service.isEmpty
            && service == service.trimmingCharacters(in: .whitespacesAndNewlines)
            && !service.contains("\0")
            && !account.isEmpty
            && account == account.trimmingCharacters(in: .whitespacesAndNewlines)
            && !account.contains("\0")
    }
}

struct KernelAgentExecutionProfile: Codable, Hashable, Sendable {
    var provider: KernelExecutionProvider
    /// Stable provider/profile identity. It must never contain credentials.
    var providerReference: String
    /// SHA-256 of the exact executable harness authorized by the user. A
    /// provider/model label alone cannot authorize a different local binary.
    var executableContentDigest: ContentDigest
    var modelID: String
    var reasoningEffort: String?
    var sandbox: KernelExecutionSandbox
    var networkPolicy: KernelNetworkPolicy
    var pluginPolicy: KernelPluginPolicy
    var environmentPolicy: KernelEnvironmentPolicy
    /// Separates an installed provider executable (for example the Codex CLI)
    /// from a binary that actually implements LoopForge's descriptor,
    /// credential, and canonical-result protocol. Defaulting recovered and
    /// direct executable profiles to unavailable prevents argv substitution.
    var providerProtocol: KernelProviderProtocol = .unavailable
    /// Missing mode authority is never productive. Native authoring and test
    /// fixtures must each supply their exact independently established mode.
    var providerHarnessMode: KernelProviderHarnessMode = .unavailable
    /// Authentication is explicit contract data rather than inferred from a
    /// provider label. Historical profiles decode to no credential authority.
    var credentialMode: KernelProviderCredentialMode = .none
    var credentialReference: KernelProviderCredentialReference? = nil
}

extension KernelAgentExecutionProfile {
    private enum CodingKeys: String, CodingKey {
        case provider
        case providerReference
        case executableContentDigest
        case modelID
        case reasoningEffort
        case sandbox
        case networkPolicy
        case pluginPolicy
        case environmentPolicy
        case providerProtocol
        case providerHarnessMode
        case credentialMode
        case credentialReference
    }

    /// Profiles persisted before executable identity became mandatory remain
    /// decodable for forensic recovery, but receive an empty digest and cannot
    /// pass validation or materialize a process.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(KernelExecutionProvider.self, forKey: .provider)
        providerReference = try container.decode(String.self, forKey: .providerReference)
        executableContentDigest = try container.decodeIfPresent(
            ContentDigest.self,
            forKey: .executableContentDigest
        ) ?? ContentDigest("")
        modelID = try container.decode(String.self, forKey: .modelID)
        reasoningEffort = try container.decodeIfPresent(
            String.self,
            forKey: .reasoningEffort
        )
        sandbox = try container.decode(KernelExecutionSandbox.self, forKey: .sandbox)
        networkPolicy = try container.decode(KernelNetworkPolicy.self, forKey: .networkPolicy)
        pluginPolicy = try container.decode(KernelPluginPolicy.self, forKey: .pluginPolicy)
        environmentPolicy = try container.decode(
            KernelEnvironmentPolicy.self,
            forKey: .environmentPolicy
        )
        providerProtocol = try container.decodeIfPresent(
            KernelProviderProtocol.self,
            forKey: .providerProtocol
        ) ?? .unavailable
        providerHarnessMode = try container.decodeIfPresent(
            KernelProviderHarnessMode.self,
            forKey: .providerHarnessMode
        ) ?? .unavailable
        credentialMode = try container.decodeIfPresent(
            KernelProviderCredentialMode.self,
            forKey: .credentialMode
        ) ?? .none
        credentialReference = try container.decodeIfPresent(
            KernelProviderCredentialReference.self,
            forKey: .credentialReference
        )
    }
}

struct KernelExecutionProfile: Codable, Hashable, Sendable {
    static let fullAccessCapabilityID = "kernel.full-access"
    static let networkCapabilityID = "kernel.network-access"
    static let userInstalledPluginCapabilityID = "kernel.user-installed-plugins"
    static let declaredEnvironmentCapabilityID = "kernel.declared-environment"

    var schemaVersion: Int
    var worker: KernelAgentExecutionProfile
    var independentReviewer: KernelAgentExecutionProfile
    /// A role label or a second invocation of the worker is not independent.
    /// Runtime activation must prove distinct actor lineage.
    var requiresDistinctActorLineage: Bool

    func validationIssues(authorityCeiling: KernelAuthorityCeiling) -> [String] {
        var issues: [String] = []
        if schemaVersion <= 0 {
            issues.append("execution profile schemaVersion must be positive")
        }
        for (role, profile) in [
            ("worker", worker),
            ("independent reviewer", independentReviewer)
        ] {
            let provider = profile.providerReference.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let model = profile.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if provider.isEmpty || provider != profile.providerReference
                || model.isEmpty || model != profile.modelID {
                issues.append("\(role) execution identity must use exact nonempty values")
            }
            let executableDigest = profile.executableContentDigest.rawValue
            if executableDigest.count != 64
                || executableDigest != executableDigest.lowercased()
                || !executableDigest.allSatisfy({ $0.isHexDigit }) {
                issues.append("\(role) executable content digest must be exact lowercase SHA-256")
            }
            if let reasoning = profile.reasoningEffort {
                let exact = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                if exact.isEmpty || exact != reasoning {
                    issues.append("\(role) reasoning effort must be exact and nonempty")
                }
            }
            switch profile.credentialMode {
            case .none:
                if profile.credentialReference != nil {
                    issues.append("\(role) credential-free profile must not retain a credential reference")
                }
            case .opaqueProviderSecret:
                if profile.credentialReference?.isValid != true {
                    issues.append("\(role) stored credential mode requires one exact valid reference")
                }
            }
            if profile.sandbox == .fullAccess,
               !authorityCeiling.capabilityIDs.contains(Self.fullAccessCapabilityID) {
                issues.append("\(role) full access lacks a ratified capability grant")
            }
            if profile.networkPolicy == .enabled,
               !authorityCeiling.capabilityIDs.contains(Self.networkCapabilityID) {
                issues.append("\(role) network access lacks a ratified capability grant")
            }
            if profile.pluginPolicy == .userInstalled,
               !authorityCeiling.capabilityIDs.contains(
                   Self.userInstalledPluginCapabilityID
               ) {
                issues.append("\(role) plugin access lacks a ratified capability grant")
            }
            if profile.environmentPolicy == .declaredAllowlist,
               !authorityCeiling.capabilityIDs.contains(
                   Self.declaredEnvironmentCapabilityID
               ) {
                issues.append("\(role) environment access lacks a ratified capability grant")
            }
        }
        if independentReviewer.sandbox != .readOnly
            || independentReviewer.networkPolicy != .disabled
            || independentReviewer.pluginPolicy != .disabled
            || independentReviewer.environmentPolicy != .minimalKernelAllowlist {
            issues.append("independent reviewer must be read-only, offline, plugin-free, and minimally isolated")
        }
        if !requiresDistinctActorLineage {
            issues.append("independent reviewer must require distinct actor lineage")
        }
        return issues
    }
}

struct KernelMutationBudget: Codable, Hashable, Sendable {
    var maximumChangedFiles: Int
    var maximumChangedBytes: UInt64

    func validationIssues(writableScopes: Set<String>) -> [String] {
        var issues: [String] = []
        if maximumChangedFiles < 0 {
            issues.append("maximumChangedFiles must not be negative")
        }
        if writableScopes.isEmpty {
            if maximumChangedFiles != 0 || maximumChangedBytes != 0 {
                issues.append("read-only authority must have a zero mutation budget")
            }
        } else if maximumChangedFiles == 0 || maximumChangedBytes == 0 {
            issues.append("writable authority requires positive file and byte budgets")
        }
        return issues
    }
}

/// User-visible limits sealed into the ratified contract before enrollment.
/// They bound authority but do not create a plan, strategy, source revision,
/// attempt identity, or permission to start a worker.
struct KernelExecutionBudgetPolicy: Codable, Hashable, Sendable {
    var mutation: KernelMutationBudget
    var convergence: ConvergenceBudget

    func validationIssues(writableScopes: Set<String>) -> [String] {
        var issues = mutation.validationIssues(writableScopes: writableScopes)
        issues.append(contentsOf: convergence.validationIssues())
        if convergence.maximumEquivalentFailures > convergence.maximumAttempts {
            issues.append("maximumEquivalentFailures must not exceed maximumAttempts")
        }
        if convergence.maximumStrategies > convergence.maximumAttempts {
            issues.append("maximumStrategies must not exceed maximumAttempts")
        }
        if writableScopes.isEmpty {
            if convergence.maximumMutationCost != 0 {
                issues.append("read-only authority must have zero convergence mutation cost")
            }
        } else if convergence.maximumMutationCost == 0 {
            issues.append("writable authority requires a positive convergence mutation cost")
        }
        if convergence.maximumVerificationCost == 0 {
            issues.append("maximumVerificationCost must be positive")
        }
        return issues
    }
}

struct TaskContract: Codable, Hashable, Sendable {
    var id: TaskContractID
    var schemaVersion: Int
    var verbatimObjective: String
    var objectiveDigest: ContentDigest
    var requirements: [RequirementContract]
    var constraints: [ConstraintContract]
    var nonGoals: [String]
    var protectedBaselines: [BaselineReference]
    /// Optional only for decoding contracts produced before native workspace
    /// selection became part of ratified authority. Production enrollment
    /// requires this binding.
    var workspaceBinding: TaskContractWorkspaceBinding? = nil
    /// Optional solely for decoding contracts written before dependency
    /// evidence became a kernel concept.
    var externalDependencies: [ExternalDependencyContract]? = nil
    /// Optional solely for decoding contracts ratified before complete
    /// requirement evidence recipes were retained in the run journal. New
    /// ratification seals the compiler-validated recipes into the contract.
    var requirementEvidenceRecipes: [RequirementEvidenceRecipe]? = nil
    /// Optional solely for decoding contracts ratified before the native
    /// confirmation exposed bounded mutation and convergence authority.
    var executionBudgets: KernelExecutionBudgetPolicy? = nil
    /// Optional solely for decoding contracts ratified before native
    /// confirmation captured and displayed a content-complete source revision.
    /// The artifact is evidence until the enclosing candidate is confirmed by
    /// the user; it never creates a strategy or plan by itself.
    var sourceRevision: WorkspaceSourceRevisionArtifact? = nil
    /// Optional solely for decoding contracts ratified before native strategy
    /// authority existed. The descriptor remains an inert proposal until the
    /// enclosing candidate is displayed and confirmed by the user.
    var initialCausalStrategyAuthority: KernelCausalStrategyAuthority? = nil
    /// Optional solely for decoding contracts ratified before native plan
    /// authority existed. It authorizes no command or process by itself.
    var initialExecutionPlan: KernelPlanProposal? = nil
    /// Optional solely for decoding contracts created before execution
    /// identity became ratified authority. Native authoring always supplies it.
    var executionProfile: KernelExecutionProfile? = nil
    var authorityCeiling: KernelAuthorityCeiling
    var acceptancePolicy: TaskAcceptancePolicy
    var createdAt: Date

    var mandatoryRequirementIDs: Set<RequirementID> {
        Set(requirements.lazy.filter(\.mandatory).map(\.id))
    }

    var protectedWorkspaceEntryBindings: Set<ProtectedWorkspaceEntryBinding> {
        Set(protectedBaselines.flatMap { baseline in
            (baseline.protectedWorkspaceEntries ?? []).map {
                ProtectedWorkspaceEntryBinding(baselineID: baseline.id, entry: $0)
            }
        })
    }

    var hasCompleteRequirementEvidenceRecipeProvenance: Bool {
        guard let recipes = requirementEvidenceRecipes else { return false }
        let recipeGroups = Dictionary(grouping: recipes, by: \.id)
        guard recipeGroups.values.allSatisfy({ $0.count == 1 }) else {
            return false
        }
        let requirementGroups = Dictionary(grouping: requirements, by: \.id)
        guard requirementGroups.values.allSatisfy({ $0.count == 1 }) else {
            return false
        }
        let requirementsByID = requirementGroups.compactMapValues(\.first)
        let declaredIDs = Set(requirements.flatMap(\.evidenceRecipeIDs))
        guard Set(recipes.map(\.id)) == declaredIDs else { return false }
        return recipes.allSatisfy { recipe in
            requirementsByID[recipe.requirementID]?.evidenceRecipeIDs.contains(
                recipe.id
            ) == true
                && !recipe.expectedObservation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                && recipe.requiresIndependentLineage
                && recipe.executableProbe?.validationIssues().isEmpty == true
        }
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion <= 0 { issues.append("schemaVersion must be positive") }
        if verbatimObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("verbatimObjective must not be empty")
        }
        if objectiveDigest.rawValue.isEmpty { issues.append("objectiveDigest must not be empty") }
        if requirementEvidenceRecipes != nil,
           !hasCompleteRequirementEvidenceRecipeProvenance {
            issues.append("retained requirement evidence recipes must exactly cover every declared recipe")
        }
        if let executionBudgets {
            issues.append(contentsOf: executionBudgets.validationIssues(
                writableScopes: authorityCeiling.writableScopes
            ))
        }
        if let sourceRevision {
            issues.append(contentsOf: sourceRevision.validationIssues())
            if let workspaceBinding,
               sourceRevision.workspaceID != workspaceBinding.workspaceID
                || sourceRevision.canonicalRootDigest !=
                    workspaceBinding.canonicalRootDigest {
                issues.append("source revision must match the exact workspace binding")
            }
        }
        issues.append(contentsOf: initialExecutionAuthorityValidationIssues())
        if let workspaceBinding,
           workspaceBinding.workspaceID.rawValue.isEmpty
            || workspaceBinding.canonicalRootDigest.rawValue.isEmpty {
            issues.append("workspace binding requires exact identity and root digest")
        }
        let requirementIDs = requirements.map(\.id)
        if Set(requirementIDs).count != requirementIDs.count {
            issues.append("requirement identifiers must be unique")
        }
        if requirements.contains(where: {
            $0.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            issues.append("requirement statements must not be empty")
        }
        if requirements.contains(where: { requirement in
            guard let cardinality = requirement.deliverableCardinality else { return false }
            let trimmed = cardinality.collectionID.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return cardinality.exactCount == 0
                || trimmed.isEmpty
                || trimmed != cardinality.collectionID
        }) {
            issues.append("deliverable cardinality requires an exact collection ID and positive count")
        }
        let constraintIDs = constraints.map(\.id)
        if Set(constraintIDs).count != constraintIDs.count {
            issues.append("constraint identifiers must be unique")
        }
        if constraints.contains(where: {
            $0.id.isEmpty || $0.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            issues.append("constraint identifiers and statements must not be empty")
        }
        let knownRequirementIDs = Set(requirements.map(\.id))
        for constraint in constraints {
            switch (constraint.kind, constraint.substitutionRule) {
            case (.prohibitSubstitution, .none):
                issues.append(
                    "prohibitSubstitution constraint \(constraint.id) requires a typed rule"
                )
            case (.prohibitSubstitution, .some(let rule)):
                if rule.requirementIDs.isEmpty
                    || !rule.requirementIDs.isSubset(of: knownRequirementIDs) {
                    issues.append(
                        "substitution constraint \(constraint.id) must bind known requirement IDs"
                    )
                }
                if rule.permittedImplementationIDs.isEmpty
                    || rule.permittedImplementationIDs.contains(where: {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || $0 != $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }) {
                    issues.append(
                        "substitution constraint \(constraint.id) requires exact implementation IDs"
                    )
                }
            case (_, .some):
                issues.append(
                    "typed substitution rule on \(constraint.id) requires prohibitSubstitution kind"
                )
            case (_, .none):
                break
            }
        }
        let baselineIDs = protectedBaselines.map(\.id)
        if Set(baselineIDs).count != baselineIDs.count {
            issues.append("baseline identifiers must be unique")
        }
        if protectedBaselines.contains(where: { $0.artifactDigest.rawValue.isEmpty }) {
            issues.append("baseline digests must not be empty")
        }
        let externalDependencies = externalDependencies ?? []
        let externalDependencyIDs = externalDependencies.map(\.id)
        if Set(externalDependencyIDs).count != externalDependencyIDs.count {
            issues.append("external dependency identifiers must be unique")
        }
        for dependency in externalDependencies {
            if dependency.id.rawValue.isEmpty
                || dependency.evidenceRecipeID.rawValue.isEmpty
                || dependency.requirementIDs.isEmpty
                || !dependency.requirementIDs.isSubset(of: knownRequirementIDs)
                || dependency.authorizedObserverLineageDigests.isEmpty
                || dependency.authorizedObserverLineageDigests.contains(where: {
                    $0.rawValue.isEmpty
                }) {
                issues.append(
                    "external dependencies require known requirements, evidence recipes, and authorized observer lineages"
                )
            }
            if dependency.executableProbe?.validationIssues().isEmpty != true {
                issues.append(
                    "external dependency \(dependency.id.rawValue) requires one valid executable observation probe"
                )
            }
        }
        if let executionProfile {
            issues.append(contentsOf: executionProfile.validationIssues(
                authorityCeiling: authorityCeiling
            ))
        }
        if authorityCeiling.capabilityIDs.contains(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed != $0
        }) {
            issues.append("authority capability IDs must be exact and nonempty")
        }
        if (authorityCeiling.readableScopes.union(authorityCeiling.writableScopes))
            .contains(where: { WorkspacePathPolicy.canonical($0) != $0 }) {
            issues.append("authority scopes must be canonical workspace paths")
        }
        var protectedWorkspacePathOwners: [String: BaselineID] = [:]
        for baseline in protectedBaselines {
            guard let entries = baseline.protectedWorkspaceEntries else { continue }
            if entries.isEmpty {
                issues.append("declared protected workspace entry sets must not be empty")
            }
            if !baseline.preservationRequired {
                issues.append("protected workspace entries require baseline preservation")
            }
            for entry in entries.sorted(by: { $0.path < $1.path }) {
                if WorkspacePathPolicy.canonical(entry.path) != entry.path
                    || entry.contentDigest.rawValue.isEmpty {
                    issues.append("protected workspace entries require canonical paths and digests")
                }
                if protectedWorkspacePathOwners[entry.path] != nil {
                    issues.append("protected workspace paths must have one baseline owner")
                } else {
                    protectedWorkspacePathOwners[entry.path] = baseline.id
                }
            }
        }
        if let duration = acceptancePolicy.duration,
           duration.requiredSeconds == 0 {
            issues.append("a declared duration requirement must be positive")
        }
        return issues
    }
}

struct KernelMutationScope: Codable, Hashable, Sendable {
    var writablePaths: Set<String>
    var maximumChangedFiles: Int
    var maximumChangedBytes: Int

    static let readOnly = KernelMutationScope(
        writablePaths: [],
        maximumChangedFiles: 0,
        maximumChangedBytes: 0
    )
}

struct KernelNodeContract: Codable, Hashable, Sendable {
    var id: KernelNodeID
    var requirementIDs: Set<RequirementID>
    var objective: String
    var dependencies: Set<KernelNodeID>
    var mutationScope: KernelMutationScope
    var capabilityIDs: Set<String>
    var strategyFingerprint: StrategyFingerprint
}

struct KernelPlanProposal: Codable, Hashable, Sendable {
    var contractDigest: ContentDigest
    var nodes: [KernelNodeContract]

    /// A plan is mutation-capable when any node can name a writable path or
    /// consume a non-zero filesystem mutation budget. This is deliberately
    /// structural: objective prose and action labels cannot downgrade a plan
    /// to read-only execution.
    var requiresWorkspaceMutation: Bool {
        nodes.contains { node in
            !node.mutationScope.writablePaths.isEmpty
                || node.mutationScope.maximumChangedFiles > 0
                || node.mutationScope.maximumChangedBytes > 0
        }
    }
}

extension TaskContract {
    /// Conservative contract-level projection used before an attempt exists.
    /// Any retained write ceiling or budget keeps the mutation authority gates
    /// closed even if the plan is missing or internally inconsistent.
    var requiresWorkspaceMutationAuthority: Bool {
        !authorityCeiling.writableScopes.isEmpty
            || executionBudgets.map {
                $0.mutation.maximumChangedFiles > 0
                    || $0.mutation.maximumChangedBytes > 0
            } == true
            || initialExecutionPlan?.requiresWorkspaceMutation == true
    }
}

enum KernelFalsificationPredicateKind: String, Codable, Hashable, Sendable {
    /// The exact user-confirmed evidence recipe did not produce accepted
    /// evidence for its owning requirement at the bound source revision.
    case requiredEvidenceMissing
}

struct KernelExpectedObservationContract: Codable, Hashable, Sendable {
    var id: String
    var requirementID: RequirementID
    var evidenceRecipeID: EvidenceRecipeID
    var expectedObservationDigest: ContentDigest
}

struct KernelFalsificationPredicateContract: Codable, Hashable, Sendable {
    var id: String
    var requirementID: RequirementID
    var evidenceRecipeID: EvidenceRecipeID
    var kind: KernelFalsificationPredicateKind
    var boundSourceRevision: ContentDigest
}

/// Exact strategy material proposed by the native app and made authoritative
/// only by whole-candidate user confirmation. Display prose and model output
/// cannot manufacture this retained envelope.
struct KernelCausalStrategyAuthority: Codable, Hashable, Sendable {
    var descriptor: CausalStrategyDescriptor
    var expectedObservations: [KernelExpectedObservationContract]
    var falsificationPredicates: [KernelFalsificationPredicateContract]
}

extension TaskContract {
    var hasValidInitialExecutionAuthority: Bool {
        initialCausalStrategyAuthority != nil
            && initialExecutionPlan != nil
            && initialExecutionAuthorityValidationIssues().isEmpty
    }

    fileprivate func initialExecutionAuthorityValidationIssues() -> [String] {
        switch (initialCausalStrategyAuthority, initialExecutionPlan) {
        case (.none, .none):
            return []
        case (.none, .some), (.some, .none):
            return ["initial causal strategy and execution plan must be retained together"]
        case (.some(let authority), .some(let plan)):
            var issues: [String] = []
            guard let sourceRevision,
                  let executionBudgets,
                  let recipes = requirementEvidenceRecipes else {
                return ["initial execution authority requires source revision, budgets, and evidence recipes"]
            }
            let descriptor = authority.descriptor
            let knownRequirements = Set(requirements.map(\.id))
            let expectedIDs = authority.expectedObservations.map(\.id)
            let falsificationIDs = authority.falsificationPredicates.map(\.id)
            if descriptor.requirementIDs.isEmpty
                || !descriptor.requirementIDs.isSubset(of: knownRequirements)
                || descriptor.requirementIDs != mandatoryRequirementIDs {
                issues.append("initial strategy must own every mandatory requirement exactly")
            }
            if descriptor.hypothesisClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || descriptor.actionClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || descriptor.workspaceTopology.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || descriptor.measurementBoundary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || descriptor.evidenceSources.isEmpty
                || descriptor.verificationOracles.isEmpty {
                issues.append("initial strategy causal axes must be explicit and nonempty")
            }
            if Set(expectedIDs).count != expectedIDs.count
                || expectedIDs.contains(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
                || Set(expectedIDs) != descriptor.expectedObservationIDs {
                issues.append("initial strategy expected observations must be unique and exact")
            }
            if Set(falsificationIDs).count != falsificationIDs.count
                || falsificationIDs.contains(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
                || Set(falsificationIDs) != descriptor.falsificationPredicateIDs {
                issues.append("initial strategy falsification predicates must be unique and exact")
            }
            let recipesByID = Dictionary(grouping: recipes, by: \.id)
                .compactMapValues { $0.count == 1 ? $0.first : nil }
            let retainedRecipeIDs = Set(recipes.map(\.id))
            let expectedByRecipe = Dictionary(
                grouping: authority.expectedObservations,
                by: \.evidenceRecipeID
            )
            if Set(expectedByRecipe.keys) != retainedRecipeIDs
                || expectedByRecipe.values.contains(where: { $0.count != 1 }) {
                issues.append("initial strategy must retain exactly one prediction per evidence recipe")
            }
            let falsifiersByRecipe = Dictionary(
                grouping: authority.falsificationPredicates,
                by: \.evidenceRecipeID
            )
            if Set(falsifiersByRecipe.keys) != retainedRecipeIDs
                || falsifiersByRecipe.values.contains(where: { $0.count != 1 }) {
                issues.append("initial strategy must retain exactly one falsifier per evidence recipe")
            }
            for expected in authority.expectedObservations {
                guard let recipe = recipesByID[expected.evidenceRecipeID],
                      recipe.requirementID == expected.requirementID,
                      descriptor.requirementIDs.contains(expected.requirementID),
                      expected.expectedObservationDigest == TaskContractCompiler.digest(
                        Data(recipe.expectedObservation.utf8)
                      ) else {
                    issues.append("initial expected observation must bind its exact requirement and evidence recipe")
                    continue
                }
            }
            for predicate in authority.falsificationPredicates {
                guard let recipe = recipesByID[predicate.evidenceRecipeID],
                      recipe.requirementID == predicate.requirementID,
                      descriptor.requirementIDs.contains(predicate.requirementID),
                      predicate.kind == .requiredEvidenceMissing,
                      predicate.boundSourceRevision == sourceRevision.sourceRevision else {
                    issues.append("initial falsification predicate must bind missing required evidence at the exact source revision")
                    continue
                }
            }
            if Set(authority.expectedObservations.map(\.evidenceRecipeID)) !=
                retainedRecipeIDs
                || Set(authority.falsificationPredicates.map(\.evidenceRecipeID)) !=
                    retainedRecipeIDs {
                issues.append("initial strategy predictions and falsifiers must cover every retained evidence recipe")
            }
            for requirementID in descriptor.requirementIDs {
                if !authority.expectedObservations.contains(where: {
                    $0.requirementID == requirementID
                }) || !authority.falsificationPredicates.contains(where: {
                    $0.requirementID == requirementID
                }) {
                    issues.append("each initial strategy requirement needs a prediction and falsification predicate")
                }
            }
            if descriptor.baselineRevision != sourceRevision.sourceRevision {
                issues.append("initial strategy baseline revision must equal the confirmed source revision")
            }
            if descriptor.evidenceSources != Set(recipes.map { $0.id.rawValue }) {
                issues.append("initial strategy evidence sources must equal retained recipe identities")
            }
            if descriptor.verificationOracles != Set(recipes.map {
                $0.verifierKind.rawValue
            }) {
                issues.append("initial strategy verification oracles must equal retained verifier kinds")
            }
            if plan.contractDigest != objectiveDigest {
                issues.append("initial plan must bind the exact objective digest")
            }
            let nodeIDs = plan.nodes.map(\.id)
            if plan.nodes.isEmpty || Set(nodeIDs).count != nodeIDs.count {
                issues.append("initial plan nodes must be nonempty and unique")
            }
            let knownNodeIDs = Set(nodeIDs)
            var requirementOwners: [RequirementID: Int] = [:]
            var totalFiles = 0
            var totalBytes = 0
            var totalOverflow = false
            var planCapabilityRoute = Set<String>()
            for node in plan.nodes {
                if node.requirementIDs.isEmpty
                    || !node.requirementIDs.isSubset(of: knownRequirements) {
                    issues.append("initial plan nodes must own known requirements")
                }
                if !node.requirementIDs.isSubset(
                    of: descriptor.requirementIDs
                ) {
                    issues.append("initial plan nodes must own confirmed strategy requirements")
                }
                for requirementID in node.requirementIDs {
                    requirementOwners[requirementID, default: 0] += 1
                }
                if !node.dependencies.isSubset(of: knownNodeIDs)
                    || node.dependencies.contains(node.id) {
                    issues.append("initial plan dependencies must reference other nodes")
                }
                if node.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || node.strategyFingerprint != descriptor.fingerprint {
                    issues.append("initial plan nodes must bind the confirmed causal strategy")
                }
                if node.mutationScope.maximumChangedFiles < 0
                    || node.mutationScope.maximumChangedBytes < 0
                    || node.mutationScope.writablePaths.contains(where: {
                        WorkspacePathPolicy.canonical($0) != $0
                    })
                    || node.mutationScope.writablePaths.contains(where: { path in
                        !authorityCeiling.writableScopes.contains(where: {
                            WorkspacePathPolicy.contains(scope: $0, path: path)
                        })
                    }) {
                    issues.append("initial plan mutation scope exceeds canonical contract authority")
                }
                if !node.capabilityIDs.isSubset(of: authorityCeiling.capabilityIDs) {
                    issues.append("initial plan capabilities exceed contract authority")
                }
                planCapabilityRoute.formUnion(node.capabilityIDs)
                for binding in protectedWorkspaceEntryBindings {
                    for writableScope in node.mutationScope.writablePaths where
                        WorkspacePathPolicy.overlaps(
                            writableScope,
                            binding.entry.path
                        ) {
                        issues.append("initial plan mutation scope overlaps a protected baseline")
                    }
                }
                let (nextFiles, fileOverflow) = totalFiles.addingReportingOverflow(
                    node.mutationScope.maximumChangedFiles
                )
                let (nextBytes, byteOverflow) = totalBytes.addingReportingOverflow(
                    node.mutationScope.maximumChangedBytes
                )
                totalOverflow = totalOverflow || fileOverflow || byteOverflow
                totalFiles = fileOverflow ? .max : nextFiles
                totalBytes = byteOverflow ? .max : nextBytes
            }
            for requirementID in mandatoryRequirementIDs where
                requirementOwners[requirementID] != 1 {
                issues.append("each mandatory requirement must have exactly one initial plan owner")
            }
            if Self.initialPlanHasDependencyCycle(plan.nodes) {
                issues.append("initial plan dependencies must be acyclic")
            }
            if descriptor.capabilityRoute != planCapabilityRoute {
                issues.append("initial strategy capability route must equal the confirmed plan")
            }
            if totalOverflow || totalFiles < 0 || totalBytes < 0
                || totalFiles > executionBudgets.mutation.maximumChangedFiles
                || (totalBytes >= 0
                    && UInt64(totalBytes) > executionBudgets.mutation.maximumChangedBytes) {
                issues.append("initial plan aggregate mutation scope exceeds confirmed budgets")
            }
            if TaskContractCompiler.planMutationSurfaceDigest(plan) !=
                descriptor.mutationSurfaceDigest {
                issues.append("initial strategy mutation surface must equal the confirmed plan")
            }
            return issues
        }
    }

    private static func initialPlanHasDependencyCycle(
        _ nodes: [KernelNodeContract]
    ) -> Bool {
        var dependencies: [KernelNodeID: Set<KernelNodeID>] = [:]
        for node in nodes where dependencies[node.id] == nil {
            dependencies[node.id] = node.dependencies
        }
        var visiting = Set<KernelNodeID>()
        var visited = Set<KernelNodeID>()
        func visit(_ nodeID: KernelNodeID) -> Bool {
            if visiting.contains(nodeID) { return true }
            if visited.contains(nodeID) { return false }
            visiting.insert(nodeID)
            for dependency in dependencies[nodeID] ?? [] where visit(dependency) {
                return true
            }
            visiting.remove(nodeID)
            visited.insert(nodeID)
            return false
        }
        return nodes.contains { visit($0.id) }
    }
}
