import Foundation

enum NativeSourceRevisionCapturePolicyParser {
    /// Parses only exact directory-name components. Commas and newlines are
    /// separators for the native text field; ordering is canonicalized, while
    /// duplicates remain present so policy validation can reject ambiguity.
    static func parseExcludedDirectoryNames(_ text: String) -> [String] {
        text.split(
            maxSplits: .max,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == "," || $0.isNewline }
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .sorted()
    }
}

enum NativeExactImplementationIdentityParser {
    /// Produces canonical opaque identities without interpreting product,
    /// framework, provider, filename, or brand vocabulary. Duplicates remain
    /// present so authoring validation can reject ambiguous user authority.
    static func parse(_ text: String) -> [String] {
        text.split(
            maxSplits: .max,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == "," || $0.isNewline }
        )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .sorted()
    }
}

enum NativeDeliverableCardinalityParser {
    /// Parses one optional, vocabulary-neutral exact-set declaration. Empty
    /// fields mean no cardinality claim. Partial, whitespace-normalized,
    /// signed, zero, leading-zero, and overflowing counts fail closed instead
    /// of being silently repaired into user authority.
    static func parse(
        collectionID: String,
        exactCountText: String
    ) -> (
        constraint: DeliverableCardinalityConstraint?,
        issues: [String]
    ) {
        if collectionID.isEmpty && exactCountText.isEmpty {
            return (nil, [])
        }
        var issues: [String] = []
        if collectionID.isEmpty || exactCountText.isEmpty {
            issues.append(
                "Exact deliverable cardinality requires both an opaque collection ID and a positive count."
            )
        }
        if collectionID != collectionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) {
            issues.append(
                "The opaque collection ID must already be trimmed."
            )
        }
        let decimalDigitsOnly = !exactCountText.isEmpty
            && exactCountText.unicodeScalars.allSatisfy {
                (48...57).contains($0.value)
            }
        let exactCount = decimalDigitsOnly ? UInt64(exactCountText) : nil
        if !decimalDigitsOnly
            || exactCount == nil
            || exactCount == 0
            || exactCount.map(String.init) != exactCountText {
            issues.append(
                "The exact deliverable count must be a canonical positive UInt64 without signs, spaces, or leading zeroes."
            )
        }
        guard issues.isEmpty, let exactCount else {
            return (nil, issues.sorted())
        }
        return (
            DeliverableCardinalityConstraint(
                collectionID: collectionID,
                exactCount: exactCount
            ),
            []
        )
    }
}

struct NativeTaskContractAuthoringRequest: Sendable {
    static let defaultSourceRevisionCapturePolicy =
        WorkspaceCandidatePostimageCapturePolicy(
            excludedDirectoryNames: [
                ".build", ".git", ".loopforge", ".swiftpm", "DerivedData"
            ],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 20_000,
                maximumTotalBytes: 268_435_456,
                maximumFileBytes: 33_554_432
            )
        )

    var exactObjective: String
    /// Text entered directly by the user is `.user`; a model-authored option
    /// becomes authority only after the user selects it for the native review,
    /// in which case it is recorded as an accepted user amendment.
    var objectiveSourceAuthority: TaskContractSourceAuthority = .user
    var workspaceID: WorkspaceID
    var workspaceRoot: URL
    var readableScopes: Set<String>
    var writableScopes: Set<String>
    /// Exact runtime capabilities explicitly selected in the native composer.
    /// New authoring currently supports only worker network access; unknown or
    /// dormant grants fail before source capture becomes contract authority.
    var authorityCapabilityIDs: Set<String> = []
    var acceptedDuration: DurationAcceptancePolicy?
    var executionProfile: KernelExecutionProfile
    /// Must be selected and displayed as exact user-confirmed verifier
    /// authority. Native authoring never invents a command from objective text.
    var verificationProbe: RequirementVerificationExecutableProbe? = nil
    var executionBudgets: KernelExecutionBudgetPolicy? = nil
    /// Optional exact native capture source explicitly selected by the user.
    /// It is already adapter-attested and non-Codable; contract authoring
    /// retains its replayable selection bytes but cannot recreate its live
    /// import provenance from a decoded manifest.
    var designBaselineSource: NativeDesignBaselineCaptureSource? = nil
    /// Exact user-visible source capture policy. The native composer may
    /// amend directory-name exclusions, but it may not infer them from the
    /// repository layout or error path. The complete policy is digest-bound,
    /// displayed, and re-used unchanged for confirmation-time recapture.
    var sourceRevisionCapturePolicy = defaultSourceRevisionCapturePolicy
    /// Optional exact implementation identities explicitly entered by the
    /// user. Empty means no substitution claim. The native path never derives
    /// these values from objective prose or repository vocabulary.
    var permittedImplementationIDs: [String] = []
    /// Optional user-authored exact-set semantics for the mandatory outcome.
    /// Raw text is retained until this boundary validates canonical authority;
    /// neither objective prose nor repository vocabulary may populate it.
    var deliverableCollectionID: String = ""
    var deliverableExactCountText: String = ""
    var userActor: ActorIdentity
    var recordedAt: Date
    var authoringNonce: ContentDigest
}

enum NativeTaskContractAuthoringError: Error, Equatable {
    case malformedUserAuthority
    case invalidObjective
    case invalidWorkspace
    case invalidScope
    case invalidAuthorityCapabilities([String])
    case invalidDuration
    case invalidExecutionProfile([String])
    case invalidVerificationProbe([String])
    case invalidExecutionBudgets([String])
    case invalidDesignBaselineSource([String])
    case invalidSourceRevisionCapturePolicy([String])
    case invalidExactImplementationIDs([String])
    case invalidDeliverableCardinality([String])
    case sourceRevisionCaptureFailed(String)
    case unsupportedExecutionAuthority(String)
    case compilationFailed([TaskContractCompilationIssue])
}

struct NativeTaskContractConfirmationDraft: Sendable {
    let compiled: CompiledTaskContractCandidate
    let workspaceID: WorkspaceID
    let canonicalWorkspaceRoot: URL
    let displayObjective: String
    let displayWorkspacePath: String
    let displayReadableScopes: [String]
    let displayWritableScopes: [String]
    let displayAuthorityCapabilityIDs: [String]
    let displayDuration: DurationAcceptancePolicy?
    let displayExecutionProfile: KernelExecutionProfile
    let displayExecutionBudgets: KernelExecutionBudgetPolicy
    let displaySourceRevision: WorkspaceSourceRevisionArtifact
    let displayCausalStrategyAuthority: KernelCausalStrategyAuthority
    let displayExecutionPlan: KernelPlanProposal
    let displayDesignBaselineSelection: NativeDesignBaselineSelection?
    let displayPermittedImplementationIDs: [String]
    let displayDeliverableCardinality: DeliverableCardinalityConstraint?

    fileprivate init(
        compiled: CompiledTaskContractCandidate,
        workspaceID: WorkspaceID,
        canonicalWorkspaceRoot: URL,
        displayObjective: String,
        displayWorkspacePath: String,
        displayReadableScopes: [String],
        displayWritableScopes: [String],
        displayAuthorityCapabilityIDs: [String],
        displayDuration: DurationAcceptancePolicy?,
        displayExecutionProfile: KernelExecutionProfile,
        displayExecutionBudgets: KernelExecutionBudgetPolicy,
        displaySourceRevision: WorkspaceSourceRevisionArtifact,
        displayCausalStrategyAuthority: KernelCausalStrategyAuthority,
        displayExecutionPlan: KernelPlanProposal,
        displayDesignBaselineSelection: NativeDesignBaselineSelection?,
        displayPermittedImplementationIDs: [String],
        displayDeliverableCardinality: DeliverableCardinalityConstraint?
    ) {
        self.compiled = compiled
        self.workspaceID = workspaceID
        self.canonicalWorkspaceRoot = canonicalWorkspaceRoot
        self.displayObjective = displayObjective
        self.displayWorkspacePath = displayWorkspacePath
        self.displayReadableScopes = displayReadableScopes
        self.displayWritableScopes = displayWritableScopes
        self.displayAuthorityCapabilityIDs = displayAuthorityCapabilityIDs
        self.displayDuration = displayDuration
        self.displayExecutionProfile = displayExecutionProfile
        self.displayExecutionBudgets = displayExecutionBudgets
        self.displaySourceRevision = displaySourceRevision
        self.displayCausalStrategyAuthority = displayCausalStrategyAuthority
        self.displayExecutionPlan = displayExecutionPlan
        self.displayDesignBaselineSelection = displayDesignBaselineSelection
        self.displayPermittedImplementationIDs = displayPermittedImplementationIDs
        self.displayDeliverableCardinality = displayDeliverableCardinality
    }
}

/// Pure native authoring boundary. It records exact user-entered bytes and
/// exact native selections as separate source artifacts. A bounded strategy
/// and plan are explicit proposals shown in full; neither gains authority from
/// model prose or application defaults before whole-candidate confirmation.
enum NativeTaskContractAuthor {
    static func prepare(
        _ request: NativeTaskContractAuthoringRequest
    ) -> Result<NativeTaskContractConfirmationDraft, NativeTaskContractAuthoringError> {
        guard !request.userActor.id.rawValue.isEmpty,
              !request.userActor.role.isEmpty,
              !request.userActor.lineageDigest.rawValue.isEmpty,
              !request.authoringNonce.rawValue.isEmpty,
              request.recordedAt.timeIntervalSince1970.isFinite else {
            return .failure(.malformedUserAuthority)
        }
        guard !request.exactObjective.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
              request.objectiveSourceAuthority.mayCreateExplicitAuthority else {
            return .failure(.invalidObjective)
        }
        guard request.workspaceRoot.isFileURL,
              request.workspaceRoot.path.hasPrefix("/"),
              !request.workspaceID.rawValue.isEmpty else {
            return .failure(.invalidWorkspace)
        }
        let suppliedValues: URLResourceValues
        do {
            suppliedValues = try request.workspaceRoot.standardizedFileURL
                .resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            return .failure(.invalidWorkspace)
        }
        guard suppliedValues.isDirectory == true,
              suppliedValues.isSymbolicLink != true else {
            return .failure(.invalidWorkspace)
        }
        let workspace = request.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        let cardinality = NativeDeliverableCardinalityParser.parse(
            collectionID: request.deliverableCollectionID,
            exactCountText: request.deliverableExactCountText
        )
        guard cardinality.issues.isEmpty else {
            return .failure(.invalidDeliverableCardinality(
                cardinality.issues
            ))
        }
        let sourceRevisionPolicyIssues =
            request.sourceRevisionCapturePolicy.validationIssues()
        guard sourceRevisionPolicyIssues.isEmpty else {
            return .failure(.invalidSourceRevisionCapturePolicy(
                sourceRevisionPolicyIssues
            ))
        }
        let sourceRevision: WorkspaceSourceRevisionArtifact
        do {
            sourceRevision = try WorkspaceSourceRevisionCollector().capture(
                workspaceID: request.workspaceID,
                root: workspace,
                excludedDirectoryNames: Set(
                    request.sourceRevisionCapturePolicy.excludedDirectoryNames
                ),
                limits: request.sourceRevisionCapturePolicy.limits
            )
        } catch {
            return .failure(.sourceRevisionCaptureFailed(String(describing: error)))
        }
        let readable = request.readableScopes.sorted()
        let writable = request.writableScopes.sorted()
        guard request.writableScopes.isSubset(of: request.readableScopes),
              (readable + writable).allSatisfy({
                  WorkspacePathPolicy.canonical($0) == $0
              }) else {
            return .failure(.invalidScope)
        }
        let capabilities = request.authorityCapabilityIDs.sorted()
        let implementationIDs = request.permittedImplementationIDs.sorted()
        var implementationIdentityIssues: [String] = []
        if Set(implementationIDs).count != implementationIDs.count {
            implementationIdentityIssues.append(
                "Exact implementation identities must be unique."
            )
        }
        if implementationIDs.contains(where: {
            $0.isEmpty
                || $0 != $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }) {
            implementationIdentityIssues.append(
                "Exact implementation identities must be nonempty and already trimmed."
            )
        }
        guard implementationIdentityIssues.isEmpty else {
            return .failure(.invalidExactImplementationIDs(
                implementationIdentityIssues.sorted()
            ))
        }
        let authorityCeiling = KernelAuthorityCeiling(
            readableScopes: request.readableScopes,
            writableScopes: request.writableScopes,
            capabilityIDs: request.authorityCapabilityIDs,
            permitsExternalPublication: false
        )
        let supportedCapabilities: Set<String> = [
            KernelExecutionProfile.networkCapabilityID
        ]
        let unknownCapabilities = request.authorityCapabilityIDs
            .subtracting(supportedCapabilities)
            .sorted()
        let workerRequestsNetwork =
            request.executionProfile.worker.networkPolicy == .enabled
        let grantsNetwork = request.authorityCapabilityIDs.contains(
            KernelExecutionProfile.networkCapabilityID
        )
        var capabilityIssues = unknownCapabilities.map {
            "unsupported native authority capability: \($0)"
        }
        if workerRequestsNetwork != grantsNetwork {
            capabilityIssues.append(
                workerRequestsNetwork
                    ? "worker network access requires the exact kernel.network-access capability"
                    : "kernel.network-access cannot remain as dormant authority when worker networking is disabled"
            )
        }
        guard capabilityIssues.isEmpty else {
            return .failure(.invalidAuthorityCapabilities(
                capabilityIssues.sorted()
            ))
        }
        if let duration = request.acceptedDuration,
           duration.requiredSeconds == 0 {
            return .failure(.invalidDuration)
        }
        let executionIssues = request.executionProfile.validationIssues(
            authorityCeiling: authorityCeiling
        )
        guard executionIssues.isEmpty else {
            if request.executionProfile.worker.sandbox == .fullAccess
                || request.executionProfile.independentReviewer.sandbox == .fullAccess {
                return .failure(.unsupportedExecutionAuthority(
                    "Full Access requires a trusted native capability grant issuer."
                ))
            }
            return .failure(.invalidExecutionProfile(executionIssues))
        }
        guard let executionData = TaskContractCompiler.executionProfileData(
            request.executionProfile
        ) else {
            return .failure(.invalidExecutionProfile([
                "Execution profile cannot be canonically encoded."
            ]))
        }
        guard let verificationProbe = request.verificationProbe else {
            return .failure(.invalidVerificationProbe([
                "An exact executable verification probe must be selected before confirmation."
            ]))
        }
        var verificationProbeIssues = verificationProbe.validationIssues()
        if verificationProbe.schemaVersion != 2 {
            verificationProbeIssues.append(
                "New native authoring requires verification probe schemaVersion 2."
            )
        }
        guard verificationProbeIssues.isEmpty else {
            return .failure(.invalidVerificationProbe(verificationProbeIssues))
        }
        guard let executionBudgets = request.executionBudgets else {
            return .failure(.invalidExecutionBudgets([
                "Mutation and convergence budgets must be selected before confirmation."
            ]))
        }
        let budgetIssues = executionBudgets.validationIssues(
            writableScopes: request.writableScopes
        )
        guard budgetIssues.isEmpty,
              let executionBudgetData = TaskContractCompiler.executionBudgetData(
                executionBudgets
              ) else {
            return .failure(.invalidExecutionBudgets(
                budgetIssues.isEmpty
                    ? ["Execution budgets cannot be canonically encoded."]
                    : budgetIssues
            ))
        }
        guard sourceRevision.validationIssues().isEmpty,
              let sourceRevisionData = TaskContractCompiler.sourceRevisionData(
                sourceRevision
              ) else {
            return .failure(.sourceRevisionCaptureFailed(
                "The captured source revision cannot be canonically retained."
            ))
        }
        if let designSource = request.designBaselineSource {
            var issues = designSource.validationIssues()
            if designSource.importedAt > request.recordedAt {
                issues.append("design baseline import cannot postdate contract authoring")
            }
            guard issues.isEmpty else {
                return .failure(.invalidDesignBaselineSource(issues.sorted()))
            }
        }

        let objectiveData = Data(request.exactObjective.utf8)
        let workspaceSelection = [
            request.workspaceID.rawValue,
            workspace.path.precomposedStringWithCanonicalMapping,
            "read:\(readable.joined(separator: ","))",
            "write:\(writable.joined(separator: ","))"
        ].joined(separator: "\u{1f}")
        let workspaceData = Data(workspaceSelection.utf8)
        let capabilityData = Data(
            (capabilities.isEmpty ? "none" : capabilities.joined(separator: "\u{1f}"))
                .utf8
        )
        let implementationIdentityData = Data(
            (implementationIDs.isEmpty
                ? "none"
                : implementationIDs.joined(separator: "\u{1f}"))
                .utf8
        )
        let deliverableCardinalityData = Data(
            cardinality.constraint.map {
                "\($0.collectionID)\u{1f}\($0.exactCount)"
            }?.utf8 ?? "none".utf8
        )
        let durationSelection = request.acceptedDuration.map {
            "\($0.requiredSeconds)\u{1f}\($0.eligibleClass.rawValue)"
        }
        let executionDigest = TaskContractCompiler.digest(executionData)
        let identityMaterial = Data([
            request.authoringNonce.rawValue,
            TaskContractCompiler.digest(objectiveData).rawValue,
            TaskContractCompiler.digest(workspaceData).rawValue,
            TaskContractCompiler.digest(capabilityData).rawValue,
            TaskContractCompiler.digest(implementationIdentityData).rawValue,
            TaskContractCompiler.digest(deliverableCardinalityData).rawValue,
            durationSelection ?? "no-duration",
            executionDigest.rawValue,
            TaskContractCompiler.digest(executionBudgetData).rawValue,
            sourceRevision.sourceRevision.rawValue,
            request.designBaselineSource?.manifestDigest.rawValue
                ?? "no-design-baseline"
        ].joined(separator: "\u{1e}").utf8)
        let identityDigest = TaskContractCompiler.digest(identityMaterial).rawValue
        let shortIdentity = String(identityDigest.prefix(24))
        let requirementID = RequirementID("native-outcome-\(shortIdentity)")
        let contractID = TaskContractID("native-contract-\(shortIdentity)")
        let recipeID = EvidenceRecipeID("native-evidence-\(shortIdentity)")
        let evidenceRecipe = RequirementEvidenceRecipe(
            id: recipeID,
            requirementID: requirementID,
            verifierKind: .deterministic,
            expectedObservation:
                "Independent evidence closes the exact user-authored outcome at the accepted revision.",
            requiresIndependentLineage: true,
            executableProbe: verificationProbe
        )
        let designBaselineSelection = request.designBaselineSource.map { source in
            NativeDesignBaselineSelection(
                id: source.designBaselineID,
                contractID: contractID,
                protectedBaselineID: source.protectedBaselineID,
                requirementIDs: [requirementID],
                sourceTree: source.sourceTree,
                builtArtifact: source.builtArtifact,
                captureProtocol: source.captureProtocol,
                designTokenSnapshot: source.designTokenSnapshot,
                semanticSurfaceManifest: source.semanticSurfaceManifest,
                captures: source.captures,
                protectedInvariants: source.protectedInvariants,
                knownDebt: source.knownDebt
            )
        }
        guard executionBudgets.mutation.maximumChangedBytes <= UInt64(Int.max) else {
            return .failure(.invalidExecutionBudgets([
                "maximumChangedBytes cannot be represented by the execution plan"
            ]))
        }
        let expectedObservationID = "required-evidence-accepted-\(shortIdentity)"
        let falsificationPredicateID = "required-evidence-missing-\(shortIdentity)"
        let provisionalNode = KernelNodeContract(
            id: KernelNodeID("native-node-\(shortIdentity)"),
            requirementIDs: [requirementID],
            objective: request.exactObjective,
            dependencies: [],
            mutationScope: KernelMutationScope(
                writablePaths: request.writableScopes,
                maximumChangedFiles:
                    executionBudgets.mutation.maximumChangedFiles,
                maximumChangedBytes: Int(
                    executionBudgets.mutation.maximumChangedBytes
                )
            ),
            capabilityIDs: request.authorityCapabilityIDs,
            strategyFingerprint: StrategyFingerprint("pending-user-confirmation")
        )
        let provisionalPlan = KernelPlanProposal(
            contractDigest: TaskContractCompiler.digest(objectiveData),
            nodes: [provisionalNode]
        )
        guard let mutationSurfaceDigest = TaskContractCompiler
            .planMutationSurfaceDigest(provisionalPlan) else {
            return .failure(.compilationFailed([.encodingFailed]))
        }
        let strategyDescriptor = CausalStrategyDescriptor(
            requirementIDs: [requirementID],
            hypothesisClass: "confirmed-requirement-unsatisfied-at-bound-revision",
            actionClass: request.writableScopes.isEmpty
                ? "bounded-read-only-observation"
                : "bounded-workspace-change",
            workspaceTopology: "single-user-selected-canonical-workspace",
            capabilityRoute: request.authorityCapabilityIDs,
            evidenceSources: [recipeID.rawValue],
            measurementBoundary:
                "accepted-recipe-evidence-at-confirmed-source-revision",
            verificationOracles: [evidenceRecipe.verifierKind.rawValue],
            mutationSurfaceDigest: mutationSurfaceDigest,
            baselineRevision: sourceRevision.sourceRevision,
            expectedObservationIDs: [expectedObservationID],
            falsificationPredicateIDs: [falsificationPredicateID],
            inheritedLessonDigests: []
        )
        let strategyAuthority = KernelCausalStrategyAuthority(
            descriptor: strategyDescriptor,
            expectedObservations: [KernelExpectedObservationContract(
                id: expectedObservationID,
                requirementID: requirementID,
                evidenceRecipeID: recipeID,
                expectedObservationDigest: TaskContractCompiler.digest(
                    Data(evidenceRecipe.expectedObservation.utf8)
                )
            )],
            falsificationPredicates: [KernelFalsificationPredicateContract(
                id: falsificationPredicateID,
                requirementID: requirementID,
                evidenceRecipeID: recipeID,
                kind: .requiredEvidenceMissing,
                boundSourceRevision: sourceRevision.sourceRevision
            )]
        )
        var node = provisionalNode
        node.strategyFingerprint = strategyDescriptor.fingerprint
        let executionPlan = KernelPlanProposal(
            contractDigest: provisionalPlan.contractDigest,
            nodes: [node]
        )
        guard let strategyAuthorityData = TaskContractCompiler
            .causalStrategyAuthorityData(strategyAuthority),
              let executionPlanData = TaskContractCompiler.executionPlanData(
                executionPlan
              ) else {
            return .failure(.compilationFailed([.encodingFailed]))
        }

        let objectiveSource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-objective-\(shortIdentity)"),
            exactUTF8: objectiveData,
            authority: request.objectiveSourceAuthority,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let workspaceSource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-workspace-\(shortIdentity)"),
            exactUTF8: workspaceData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let objectiveSpan = fullSpan(objectiveSource)
        let workspaceSpan = fullSpan(workspaceSource)
        let capabilitySource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-capabilities-\(shortIdentity)"),
            exactUTF8: capabilityData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let capabilitySpan = fullSpan(capabilitySource)
        let implementationIdentitySource = TaskContractSourceArtifact(
            id: TaskContractSourceID(
                "native-implementation-identities-\(shortIdentity)"
            ),
            exactUTF8: implementationIdentityData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let implementationIdentitySpan = fullSpan(
            implementationIdentitySource
        )
        let deliverableCardinalitySource = TaskContractSourceArtifact(
            id: TaskContractSourceID(
                "native-deliverable-cardinality-\(shortIdentity)"
            ),
            exactUTF8: deliverableCardinalityData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let deliverableCardinalitySpan = fullSpan(
            deliverableCardinalitySource
        )
        let executionSource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-execution-\(shortIdentity)"),
            exactUTF8: executionData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let executionSpan = fullSpan(executionSource)
        let executionBudgetSource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-execution-budgets-\(shortIdentity)"),
            exactUTF8: executionBudgetData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let executionBudgetSpan = fullSpan(executionBudgetSource)
        let sourceRevisionSource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-source-revision-\(shortIdentity)"),
            exactUTF8: sourceRevisionData,
            authority: .workspaceObservation,
            author: ActorIdentity(
                id: ActorID("loopforge-workspace-source-revision-collector"),
                role: "workspace-source-revision-collector",
                lineageDigest: TaskContractCompiler.digest(
                    Data("loopforge-workspace-source-revision-collector-v1".utf8)
                )
            ),
            recordedAt: request.recordedAt
        )
        let sourceRevisionSpan = fullSpan(sourceRevisionSource)
        let strategyAuthoritySource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-causal-strategy-\(shortIdentity)"),
            exactUTF8: strategyAuthorityData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let strategyAuthoritySpan = fullSpan(strategyAuthoritySource)
        let executionPlanSource = TaskContractSourceArtifact(
            id: TaskContractSourceID("native-execution-plan-\(shortIdentity)"),
            exactUTF8: executionPlanData,
            authority: .user,
            author: request.userActor,
            recordedAt: request.recordedAt
        )
        let executionPlanSpan = fullSpan(executionPlanSource)
        var sources = [
            objectiveSource,
            workspaceSource,
            capabilitySource,
            executionSource,
            executionBudgetSource,
            sourceRevisionSource,
            strategyAuthoritySource,
            executionPlanSource
        ]
        var constraints = [ConstraintContract(
            id: "native-workspace-authority-\(shortIdentity)",
            kind: .requireAuthority,
            statement: "Use only the exact workspace and relative scopes selected in the native confirmation."
        )]
        var constraintBindings = [ConstraintSourceBinding(
            constraintID: constraints[0].id,
            sourceSpans: [workspaceSpan],
            epistemicState: .explicit
        )]
        let capabilityConstraint = ConstraintContract(
            id: "native-capability-authority-\(shortIdentity)",
            kind: .bound,
            statement: "Use only the exact runtime capability IDs selected in the native confirmation."
        )
        constraints.append(capabilityConstraint)
        constraintBindings.append(ConstraintSourceBinding(
            constraintID: capabilityConstraint.id,
            sourceSpans: [capabilitySpan],
            epistemicState: .explicit
        ))
        if !implementationIDs.isEmpty {
            sources.append(implementationIdentitySource)
            let substitutionConstraint = ConstraintContract(
                id: "native-exact-implementation-\(shortIdentity)",
                kind: .prohibitSubstitution,
                statement: "Accept only the exact opaque implementation identities explicitly confirmed by the user.",
                substitutionRule: ExactImplementationConstraint(
                    requirementIDs: [requirementID],
                    permittedImplementationIDs: Set(implementationIDs)
                )
            )
            constraints.append(substitutionConstraint)
            constraintBindings.append(ConstraintSourceBinding(
                constraintID: substitutionConstraint.id,
                sourceSpans: [implementationIdentitySpan],
                epistemicState: .explicit
            ))
        }
        if cardinality.constraint != nil {
            sources.append(deliverableCardinalitySource)
        }
        if let selection = designBaselineSelection {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            guard let selectionData = try? encoder.encode(selection) else {
                return .failure(.invalidDesignBaselineSource([
                    "design baseline selection cannot be canonically retained"
                ]))
            }
            let baselineSource = TaskContractSourceArtifact(
                id: TaskContractSourceID(
                    "native-design-baseline-\(shortIdentity)"
                ),
                exactUTF8: selectionData,
                authority: .user,
                author: request.userActor,
                recordedAt: request.recordedAt
            )
            let baselineSpan = fullSpan(baselineSource)
            sources.append(baselineSource)
            let baselineConstraint = ConstraintContract(
                id: "native-design-baseline-preservation-\(shortIdentity)",
                kind: .preserve,
                statement: "Preserve the exact user-selected native product/design baseline and protected artifact."
            )
            constraints.append(baselineConstraint)
            constraintBindings.append(ConstraintSourceBinding(
                constraintID: baselineConstraint.id,
                sourceSpans: [baselineSpan],
                epistemicState: .explicit
            ))
        }
        var durationBinding: DurationAcceptanceSourceBinding?
        if let durationSelection {
            let durationSource = TaskContractSourceArtifact(
                id: TaskContractSourceID("native-duration-\(shortIdentity)"),
                exactUTF8: Data(durationSelection.utf8),
                authority: .user,
                author: request.userActor,
                recordedAt: request.recordedAt
            )
            let durationSpan = fullSpan(durationSource)
            sources.append(durationSource)
            let durationConstraint = ConstraintContract(
                id: "native-duration-acceptance-\(shortIdentity)",
                kind: .bound,
                statement: "Count only the exact accepted execution class and duration selected in the native confirmation."
            )
            constraints.append(durationConstraint)
            constraintBindings.append(ConstraintSourceBinding(
                constraintID: durationConstraint.id,
                sourceSpans: [durationSpan],
                epistemicState: .explicit
            ))
            durationBinding = DurationAcceptanceSourceBinding(
                sourceSpans: [durationSpan],
                epistemicState: .explicit
            )
        }

        let candidate = TaskContractCompilationCandidate(
            schemaVersion: 1,
            revision: 1,
            initialObjectiveSourceID: objectiveSource.id,
            sources: sources,
            contract: TaskContract(
                id: contractID,
                schemaVersion: 1,
                verbatimObjective: request.exactObjective,
                objectiveDigest: objectiveSource.digest,
                requirements: [RequirementContract(
                    id: requirementID,
                    statement: request.exactObjective,
                    mandatory: true,
                    evidenceRecipeIDs: [recipeID],
                    deliverableCardinality: cardinality.constraint
                )],
                constraints: constraints,
                nonGoals: [],
                protectedBaselines: request.designBaselineSource.map { source in
                    [BaselineReference(
                        id: source.protectedBaselineID,
                        artifactDigest: source.builtArtifact,
                        environmentDigest: source.environmentDigest,
                        preservationRequired: true
                    )]
                } ?? [],
                workspaceBinding: TaskContractWorkspaceBinding(
                    workspaceID: request.workspaceID,
                    canonicalRootDigest: sourceRevision.canonicalRootDigest
                ),
                requirementEvidenceRecipes: [evidenceRecipe],
                executionBudgets: executionBudgets,
                sourceRevision: sourceRevision,
                initialCausalStrategyAuthority: strategyAuthority,
                initialExecutionPlan: executionPlan,
                executionProfile: request.executionProfile,
                authorityCeiling: authorityCeiling,
                acceptancePolicy: TaskAcceptancePolicy(
                    duration: request.acceptedDuration,
                    requiresIndependentReview: true,
                    requiresQuiescence: true
                ),
                createdAt: request.recordedAt
            ),
            requirementBindings: [RequirementSourceBinding(
                requirementID: requirementID,
                sourceSpans: [objectiveSpan]
                    + (cardinality.constraint == nil
                        ? []
                        : [deliverableCardinalitySpan]),
                epistemicState: .explicit
            )],
            constraintBindings: constraintBindings,
            evidenceRecipes: [evidenceRecipe],
            ambiguities: [],
            workspaceSourceBinding: WorkspaceSourceBinding(
                sourceSpans: [workspaceSpan],
                epistemicState: .explicit
            ),
            durationAcceptanceSourceBinding: durationBinding,
            executionProfileSourceBinding: ExecutionProfileSourceBinding(
                sourceSpans: [executionSpan],
                epistemicState: .explicit
            ),
            executionBudgetSourceBinding: ExecutionBudgetSourceBinding(
                sourceSpans: [executionBudgetSpan],
                epistemicState: .explicit
            ),
            sourceRevisionSourceBinding: SourceRevisionSourceBinding(
                sourceSpans: [sourceRevisionSpan],
                epistemicState: .workspaceObserved
            ),
            causalStrategyAuthoritySourceBinding:
                CausalStrategyAuthoritySourceBinding(
                    sourceSpans: [strategyAuthoritySpan],
                    epistemicState: .explicit
                ),
            executionPlanSourceBinding: ExecutionPlanSourceBinding(
                sourceSpans: [executionPlanSpan],
                epistemicState: .explicit
            ),
            compilerActor: ActorIdentity(
                id: ActorID("loopforge-native-contract-author"),
                role: "native-contract-author",
                lineageDigest: TaskContractCompiler.digest(
                    Data("loopforge-native-contract-author-v1".utf8)
                )
            ),
            compiledAt: request.recordedAt
        )
        guard let authorityCeilingDigest =
                TaskContractCompiler.authorityCeilingDigest(authorityCeiling) else {
            return .failure(.compilationFailed([.encodingFailed]))
        }
        let capabilityGrantReceipts = capabilities.map { capabilityID in
            let nonceMaterial = Data([
                "loopforge.native-capability-grant.v1",
                request.authoringNonce.rawValue,
                contractID.rawValue,
                String(candidate.revision),
                authorityCeilingDigest.rawValue,
                capabilityID,
                request.userActor.id.rawValue,
                request.userActor.lineageDigest.rawValue
            ].joined(separator: "\u{1f}").utf8)
            return TaskContractCapabilityGrantReceipt.nativeUserSelectedGrant(
                contractID: contractID,
                candidateRevision: candidate.revision,
                authorityCeilingDigest: authorityCeilingDigest,
                capabilityID: capabilityID,
                grantNonceDigest: TaskContractCompiler.digest(nonceMaterial),
                grantedAt: request.recordedAt,
                userActor: request.userActor
            )
        }
        switch TaskContractCompiler.compile(
            candidate,
            capabilityGrantReceipts: capabilityGrantReceipts
        ) {
        case .success(let compiled):
            return .success(NativeTaskContractConfirmationDraft(
                compiled: compiled,
                workspaceID: request.workspaceID,
                canonicalWorkspaceRoot: workspace,
                displayObjective: request.exactObjective,
                displayWorkspacePath: workspace.path,
                displayReadableScopes: readable,
                displayWritableScopes: writable,
                displayAuthorityCapabilityIDs: capabilities,
                displayDuration: request.acceptedDuration,
                displayExecutionProfile: request.executionProfile,
                displayExecutionBudgets: executionBudgets,
                displaySourceRevision: sourceRevision,
                displayCausalStrategyAuthority: strategyAuthority,
                displayExecutionPlan: executionPlan,
                displayDesignBaselineSelection: designBaselineSelection,
                displayPermittedImplementationIDs: implementationIDs,
                displayDeliverableCardinality: cardinality.constraint
            ))
        case .failure(let failure):
            return .failure(.compilationFailed(failure.issues))
        }
    }

    private static func fullSpan(
        _ source: TaskContractSourceArtifact
    ) -> TaskContractSourceSpan {
        TaskContractSourceSpan(
            sourceID: source.id,
            sourceDigest: source.digest,
            lowerUTF8Offset: 0,
            upperUTF8Offset: source.exactUTF8.count
        )
    }
}
