import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum ProjectEntryMode: String, Equatable {
    case existing
    case new

    var title: String { self == .existing ? "Existing project" : "New project" }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedModule: LoopForgeModule {
        didSet {
            UserDefaults.standard.set(selectedModule.rawValue, forKey: "LoopForge.SelectedModule")
        }
    }
    @Published var draftRequest = "" {
        didSet { if draftRequest != oldValue, estimate != nil { estimate = nil } }
    }
    @Published var draftExecutionMode: LoopExecutionMode = .autoGraph {
        didSet { if draftExecutionMode != oldValue, estimate != nil { estimate = nil } }
    }
    @Published var draftParallelCandidateCount = 3
    @Published var draftParallelSelectionMode: ParallelCandidateSelectionMode = .agent
    @Published var draftQuality: QualityTier = .medium
    @Published var draftTargetMinutes = QualityTier.medium.defaultRuntimeMinutes
    @Published var draftWorkspacePath: String? {
        didSet { if draftWorkspacePath != oldValue, estimate != nil { estimate = nil } }
    }
    @Published var draftProjectMode: ProjectEntryMode?
    @Published var estimate: TaskEstimate?
    @Published var showingNewTask = true
    @Published var alertMessage: String?
    @Published var draftOfficialModel = AppConstants.officialWorkerModel
    @Published var draftReasoningEffort = "ultra"
    @Published var draftAccessMode: CodexAccessMode = .workspaceOnly
    @Published var draftLocalModelID = ModelProfile.advancedVisualAuditor.id
    @Published var draftControlProvider: AgentProviderKind = .codex
    @Published var draftControlModelReference = AppConstants.officialWorkerModel
    @Published var draftControlReasoningEffort = "ultra"
    @Published var draftControlAccessMode: CodexAccessMode = .readOnly
    @Published var draftSubProvider: AgentProviderKind = .codex
    @Published var draftSubModelReference = AppConstants.officialWorkerModel
    @Published var showingModelManager = false
    @Published var modelManagerPreferredProvider: AgentProviderKind = .local
    @Published var modelManagerRequestedRole: AgentRole?
    @Published var pendingTaskDeletion: LoopTask?
    @Published var showingPromptOptimizationOffer = false
    @Published var showingPromptOptimization = false
    @Published var promptOptimizationPhase: PromptOptimizationPhase = .idle
    @Published var promptOptimizationCandidates: [PromptOptimizationCandidate] = []
    @Published var promptOptimizationProvider = ""
    @Published private(set) var pendingNativeContractConfirmation:
        NativeTaskContractConfirmationDraft?
    @Published private(set) var kernelEnrollmentInProgress = false
    @Published private(set) var latestKernelEnrollmentReceipt:
        KernelRunEnrollmentReceipt?
    @Published private(set) var latestKernelExecutionReadiness:
        KernelNativeExecutionReadinessAssessment?
    @Published private(set) var kernelExecutionStartInProgress = false
    @Published private(set) var latestKernelExecutionSessionReceipt:
        KernelProductionExecutionSessionReceipt?
    @Published private(set) var draftNativeVerificationProbe:
        RequirementVerificationExecutableProbe?
    @Published private(set) var draftNativeVerificationProbeSelection:
        NativeVerificationProbeSelection?
    @Published private(set) var nativeVerificationProbeImportInProgress = false
    @Published private(set) var draftNativeDesignBaselineSource:
        NativeDesignBaselineCaptureSource?
    @Published var draftSourceRevisionExcludedDirectoryNames =
        NativeTaskContractAuthoringRequest.defaultSourceRevisionCapturePolicy
            .excludedDirectoryNames.joined(separator: ", ")
    @Published var draftPermittedImplementationIDs = ""
    @Published var draftDeliverableCollectionID = ""
    @Published var draftDeliverableExactCount = ""
    /// Explicit native-contract authority. Off by default and reset for every
    /// new draft; it never inherits from provider selection or stored keys.
    @Published var draftWorkerNetworkAccess = false
    @Published private(set) var nativeDesignBaselineImportInProgress = false
    @Published private(set) var pendingNativeDesignBaselineConfirmation:
        NativeDesignBaselineConfirmationDraft?
    @Published private(set) var latestAuthorizedKernelDesignBaseline:
        AuthorizedKernelDesignBaseline?
    @Published var watcherDraftRequest = ""
    @Published var watcherDraftWorkspacePath: String?
    @Published var watcherDraftProjectMode: ProjectEntryMode?
    @Published var watcherDraftPollSeconds: TimeInterval = 15 * 60
    @Published var watcherDraftReviewSeconds: TimeInterval = 4 * 60 * 60
    @Published var watcherDraftNotifications = true
    @Published var watcherDraftLaunchAtLogin = true
    @Published var watcherDraftProvider: AgentProviderKind = .codex
    @Published var watcherDraftModelReference = AppConstants.officialWorkerModel
    @Published var watcherDraftReasoningEffort = "ultra"
    @Published var showingWatcherGuide = false
    @Published var watcherGuideStartIndex = 0
    @Published var showingNewWatcher = true
    @Published private(set) var kernelRecoveryReport:
        WorkspaceMutationRecoveryStartupReport?

    let store: TaskStore
    let controller: LoopController
    let watcherStore: WatcherStore
    let watcherController: WatcherController
    let codexConnection: CodexConnectionManager
    let permissionCenter: PermissionCenter
    let agentCatalog: AgentCatalog
    let launchProfile: LoopForgeLaunchProfile
    /// Explicit new-kernel enrollment capability. No legacy task or Graph
    /// path calls this service; a future native confirmation flow must supply
    /// a sealed `RatifiedTaskContract` before enrollment is possible.
    let kernelRunEnrollmentCoordinator: KernelRunEnrollmentCoordinator?
    /// Separate new-kernel execution composition. It accepts only a retained
    /// enrollment plus reducer-checked plan/admission authority and never
    /// routes through the legacy LoopController, CodexRunner, or Graph engine.
    let kernelExecutionCoordinator: KernelProductionExecutionCoordinator?
    private let nativeContractConfirmationIssuer =
        NativeTaskContractConfirmationIssuer()
    private let nativeDesignBaselineConfirmationIssuer =
        NativeDesignBaselineConfirmationIssuer()
    private let estimator = TaskEstimator()
    private let promptOptimizer = PromptOptimizer()
    private var cancellables = Set<AnyCancellable>()
    private var pendingOriginalPromptForTask: String?
    private var pendingPromptOptimizationSource: String?
    private var pendingNativeContractUserActor: ActorIdentity?
    private var pendingRatifiedNativeContract: RatifiedTaskContract?
    private var pendingNativeEnrollmentRequestIdentity: (
        runID: KernelRunID,
        commandID: RunCommandID,
        enrolledAt: Date
    )?
    /// Live, non-Codable execution authority. Only the explicit native
    /// activation action can populate productive authority. Relaunch may add
    /// only the narrow cleanup capability for an exact executing journal.
    private var kernelExecutionSessions:
        [KernelRunID: any KernelApplicationTerminationSession]
    /// Normal quit must not race the one startup pass that owns durable
    /// workspace-mutation recovery. Retaining the task lets termination await
    /// the same bounded pass instead of observing an empty in-memory handle
    /// table while a registered live lease still exists on disk.
    private let workspaceMutationRecoveryTask: Task<
        WorkspaceMutationRecoveryStartupReport,
        Never
    >?
    private var kernelRecoveryReportConsumed = false
    /// A journal proven to require cleanup must never disappear merely because
    /// exact cleanup ownership could not be reconstructed. Such runs veto
    /// normal termination until a later launch can recover them.
    private var kernelApplicationTerminationRecoveryFailures: Set<KernelRunID>
    private var newlyEnrolledKernelRunProjections: [KernelRunProjection] = []
    private var watcherAgentWasCustomized = false

    init(
        store: TaskStore? = nil,
        watcherStore: WatcherStore? = nil,
        codexConnection: CodexConnectionManager? = nil,
        permissionCenter: PermissionCenter? = nil,
        agentCatalog: AgentCatalog? = nil,
        launchProfile: LoopForgeLaunchProfile = .current,
        workspaceMutationRecoveryTask: Task<
            WorkspaceMutationRecoveryStartupReport,
            Never
        >? = nil,
        kernelRunEnrollmentCoordinator: KernelRunEnrollmentCoordinator? = nil,
        kernelExecutionCoordinator: KernelProductionExecutionCoordinator? = nil
    ) {
        let actualStore = store ?? TaskStore()
        let actualPermissionCenter = permissionCenter ?? PermissionCenter()
        let actualAgentCatalog = agentCatalog ?? AgentCatalog()
        let actualCodexConnection = codexConnection ?? CodexConnectionManager()
        let actualWatcherStore = watcherStore ?? WatcherStore()
        self.selectedModule = LoopForgeModule(
            rawValue: UserDefaults.standard.string(forKey: "LoopForge.SelectedModule") ?? ""
        ) ?? .autoLoop
        self.store = actualStore
        self.controller = LoopController(
            store: actualStore,
            permissionCenter: actualPermissionCenter,
            agentCatalog: actualAgentCatalog,
            workspaceMutationRecoveryTask: workspaceMutationRecoveryTask
        )
        self.watcherStore = actualWatcherStore
        self.watcherController = WatcherController(
            store: actualWatcherStore,
            codexConnection: actualCodexConnection,
            agentCatalog: actualAgentCatalog
        )
        self.codexConnection = actualCodexConnection
        self.permissionCenter = actualPermissionCenter
        self.agentCatalog = actualAgentCatalog
        self.launchProfile = launchProfile
        self.kernelRunEnrollmentCoordinator = kernelRunEnrollmentCoordinator
        self.kernelExecutionCoordinator = kernelExecutionCoordinator
        self.workspaceMutationRecoveryTask = workspaceMutationRecoveryTask
        self.kernelRecoveryReport = nil
        self.pendingNativeContractConfirmation = nil
        self.latestKernelEnrollmentReceipt = nil
        self.latestKernelExecutionReadiness = nil
        self.latestKernelExecutionSessionReceipt = nil
        self.kernelExecutionSessions = [:]
        self.kernelApplicationTerminationRecoveryFailures = []
        self.draftNativeVerificationProbe = nil
        self.draftNativeVerificationProbeSelection = nil
        self.draftNativeDesignBaselineSource = nil
        self.pendingNativeDesignBaselineConfirmation = nil
        self.latestAuthorizedKernelDesignBaseline = nil
        if !actualStore.tasks.isEmpty { showingNewTask = false }
        if !actualWatcherStore.watchers.isEmpty { showingNewWatcher = false }
        self.codexConnection.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.permissionCenter.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.agentCatalog.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.watcherStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        self.watcherController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        if let workspaceMutationRecoveryTask {
            Task { [weak self] in
                let report = await workspaceMutationRecoveryTask.value
                guard let self else { return }
                await self.consumeKernelRecoveryReport(report)
            }
        }
        blockRetiredTaskRecoveryCandidates()
    }

    var kernelRunProjections: [KernelRunProjection] {
        let recovered = (kernelRecoveryReport?.runReports ?? [])
            .compactMap(\.kernelProjection)
        return Dictionary(
            (recovered + newlyEnrolledKernelRunProjections).map {
                ($0.runID, $0)
            },
            uniquingKeysWith: { _, newest in newest }
        ).values.sorted { $0.runID.rawValue < $1.runID.rawValue }
    }

    var kernelRecoveryRunReports: [WorkspaceMutationRecoveryRunReport] {
        (kernelRecoveryReport?.runReports ?? [])
            .sorted { $0.runID.rawValue < $1.runID.rawValue }
    }

    var kernelExecutionReadinessByRunID:
        [KernelRunID: KernelNativeExecutionReadinessAssessment] {
        guard let readiness = latestKernelExecutionReadiness else { return [:] }
        return [readiness.runID: readiness]
    }

    var kernelProviderInvocationReadinessByRunID:
        [KernelRunID: KernelProviderInvocationProfileReadinessAssessment] {
        if let session = latestKernelExecutionSessionReceipt {
            return [
                session.kernelProjection.runID:
                    session.providerInvocationProfileReadiness
            ]
        }
        guard let readiness = latestKernelExecutionReadiness else { return [:] }
        return [
            readiness.runID: readiness.providerInvocationProfileReadiness
        ]
    }

    var hasActiveKernelExecutionSessions: Bool {
        !kernelExecutionSessions.isEmpty ||
            !kernelApplicationTerminationRecoveryFailures.isEmpty
    }

    #if DEBUG
    /// Installs one already activated production session so the application
    /// termination boundary can be exercised against a genuinely live native
    /// provider or verifier process without exposing mutable session storage
    /// in release builds.
    func testOnlyRetainKernelExecutionSession(
        _ session: KernelProductionExecutionSession
    ) async {
        let projection = await session.kernelProjection()
        kernelExecutionSessions[projection.runID] = session
    }
    #endif

    /// Normal app termination consumes every retained native session through
    /// the same journal/supervisor lifecycle boundary as an explicit stop.
    /// A nonempty cleanup plan may proceed only when every action has exact,
    /// receipt-backed runtime ownership. Otherwise termination is cancelled
    /// before any retained session crosses its lifecycle boundary.
    func prepareKernelSessionsForApplicationTermination() async -> Bool {
        if let workspaceMutationRecoveryTask {
            await consumeKernelRecoveryReport(
                workspaceMutationRecoveryTask.value
            )
        }
        if let report = kernelRecoveryReport,
           !report.applicationTerminationCleanupIsSafe {
            alertMessage = "LoopForge cannot quit yet: startup workspace recovery retains unresolved runtime ownership or a failed effect."
            return false
        }
        if let runID = kernelApplicationTerminationRecoveryFailures.sorted(
            by: { $0.rawValue < $1.rawValue }
        ).first {
            alertMessage = "LoopForge cannot quit yet: native run \(runID.rawValue) requires lifecycle cleanup, but exact receipt-bound cleanup ownership could not be reconstructed."
            return false
        }
        let ordered = kernelExecutionSessions.sorted {
            $0.key.rawValue < $1.key.rawValue
        }
        let workspaceMutationPlans:
            [WorkspaceMutationApplicationTerminationPlan]
        do {
            workspaceMutationPlans = try await kernelExecutionCoordinator?
                .workspaceMutationApplicationTerminationPlans() ?? []
        } catch {
            alertMessage = "LoopForge cannot quit yet: an exact workspace-mutation join handle no longer matches its journaled lease and outbox."
            return false
        }
        for (runID, session) in ordered {
            let preflight = await session.runtimeCleanupPlan()
            guard await session.applicationTerminationCleanupIsExecutable() else {
                alertMessage = "LoopForge cannot quit yet: native run \(runID.rawValue) has \(preflight.count) retained cleanup actions without complete receipt-backed runtime ownership."
                return false
            }
        }

        do {
            let receipts = try await kernelExecutionCoordinator?
                .joinWorkspaceMutationsForApplicationTermination(
                    expectedPlans: workspaceMutationPlans
                ) ?? []
            guard receipts.map(\.plan) == workspaceMutationPlans else {
                alertMessage = "LoopForge cannot quit: workspace-mutation join receipts did not cover the exact preflight plan."
                return false
            }
        } catch {
            alertMessage = "LoopForge cannot quit because an authorized pending workspace mutation failed closed while joining: \(error)."
            return false
        }

        for (runID, session) in ordered {
            let nonce = UUID().uuidString.lowercased()
            do {
                let projection = try await session
                    .prepareForApplicationTermination(
                        requestNonce: nonce
                    )
                guard projection.phase.isTerminal, projection.quiescent else {
                    alertMessage = "LoopForge cannot quit: native run \(runID.rawValue) did not reach receipt-proven stopped quiescence."
                    return false
                }
                newlyEnrolledKernelRunProjections.removeAll {
                    $0.runID == runID
                }
                newlyEnrolledKernelRunProjections.append(projection)
                kernelExecutionSessions[runID] = nil
                if latestKernelExecutionSessionReceipt?
                    .kernelProjection.runID == runID
                {
                    latestKernelExecutionSessionReceipt = nil
                }
            } catch {
                alertMessage = "LoopForge cannot quit because native run \(runID.rawValue) failed closed during lifecycle cleanup: \(error)."
                return false
            }
        }
        return true
    }

    private func consumeKernelRecoveryReport(
        _ report: WorkspaceMutationRecoveryStartupReport
    ) async {
        kernelRecoveryReport = report
        guard !kernelRecoveryReportConsumed else { return }
        kernelRecoveryReportConsumed = true
        await recoverKernelExecutionState(from: report)
    }

    private func blockRetiredTaskRecoveryCandidates() {
        for task in store.tasks where task.resumeOnNextLaunch == true {
            controller.blockRetiredTaskExecution(
                taskID: task.id,
                source: "startup recovery"
            )
        }
    }

    var selectedLocalModel: ModelProfile {
        ModelProfile.profile(id: draftLocalModelID) ?? estimate?.model ?? .advancedVisualAuditor
    }

    func beginStartup() {
        guard !launchProfile.isIsolatedInspection else { return }
        permissionCenter.beginOnboarding()
        watcherController.beginStartup()
        if permissionCenter.isReady {
            codexConnection.start()
            resumeInterruptedTaskIfNeeded()
        }
    }

    func permissionStateChanged() {
        guard !launchProfile.isIsolatedInspection else { return }
        permissionCenter.refresh()
        if permissionCenter.isReady {
            codexConnection.start()
            resumeInterruptedTaskIfNeeded()
        }
    }

    func connectionStateChanged() {
        guard !launchProfile.isIsolatedInspection else { return }
        guard codexConnection.phase == .ready else { return }
        if draftProjectMode == nil { adoptRecommendedCodexDefaults() }
        if !watcherAgentWasCustomized { adoptRecommendedWatcherCodexDefault() }
        resumeInterruptedTaskIfNeeded()
    }

    func resumeInterruptedTaskIfNeeded() {
        blockRetiredTaskRecoveryCandidates()
    }

    /// Restores only a durable, journal-proven enrollment receipt for the
    /// newest ready kernel run. Live baseline, process, provider, mutation,
    /// and retry capabilities are deliberately not reconstructed on launch.
    private func recoverLatestReadyKernelEnrollment(
        from report: WorkspaceMutationRecoveryStartupReport
    ) async {
        guard latestKernelEnrollmentReceipt == nil,
              let coordinator = kernelExecutionCoordinator,
              report.ownershipAcquired,
              report.startupFailure == nil else { return }

        var recovered: [KernelRunEnrollmentReceipt] = []
        for run in report.runReports where
            run.failure == nil &&
            run.requiresAttention == false &&
            run.kernelProjection?.phase == .ready {
            if let receipt = try? await coordinator.recoverReadyEnrollment(
                runID: run.runID
            ) {
                recovered.append(receipt)
            }
        }
        guard let latest = recovered.max(by: {
            if $0.registration.registeredAt == $1.registration.registeredAt {
                return $0.runID.rawValue < $1.runID.rawValue
            }
            return $0.registration.registeredAt < $1.registration.registeredAt
        }) else { return }

        latestKernelEnrollmentReceipt = latest
        latestKernelExecutionSessionReceipt = nil
        do {
            latestKernelExecutionReadiness = try await coordinator
                .nativeExecutionReadiness(
                    for: latest,
                    designBaseline: nil
                )
        } catch {
            latestKernelExecutionReadiness = nil
        }
    }

    /// Startup recovery keeps productive authority non-recoverable. Exact
    /// durable workspace effects finish through the retained recovery task;
    /// an abandoned process is interrupted only when its complete cleanup
    /// plan has receipt-backed ownership. Ambiguous ownership remains a
    /// visible quit blocker without crossing the lifecycle boundary.
    private func recoverKernelExecutionState(
        from report: WorkspaceMutationRecoveryStartupReport
    ) async {
        guard let coordinator = kernelExecutionCoordinator,
              report.ownershipAcquired,
              report.startupFailure == nil else {
            await recoverLatestReadyKernelEnrollment(from: report)
            return
        }

        for run in report.runReports {
            guard let phase = run.kernelProjection?.phase,
                  phase == .executing || phase == .stopRequested else {
                continue
            }
            let session: KernelRecoveredApplicationTerminationSession
            do {
                session = try await coordinator
                    .recoverApplicationTerminationSession(runID: run.runID)
            } catch {
                kernelExecutionSessions[run.runID] = nil
                kernelApplicationTerminationRecoveryFailures.insert(run.runID)
                continue
            }
            kernelExecutionSessions[run.runID] = session
            guard await session
                .applicationTerminationCleanupIsExecutable() else {
                kernelApplicationTerminationRecoveryFailures.insert(
                    run.runID
                )
                continue
            }
            do {
                let projection = try await session
                    .reconcileAfterApplicationCrash(
                        requestNonce: UUID().uuidString.lowercased()
                    )
                let remainingPlan = await session.runtimeCleanupPlan()
                guard projection.phase == .stopped,
                      projection.quiescent,
                      projection.activeAttemptID == nil,
                      remainingPlan.isEmpty else {
                    kernelExecutionSessions[run.runID] = session
                    kernelApplicationTerminationRecoveryFailures.insert(
                        run.runID
                    )
                    continue
                }
                newlyEnrolledKernelRunProjections.removeAll {
                    $0.runID == run.runID
                }
                newlyEnrolledKernelRunProjections.append(projection)
                kernelExecutionSessions[run.runID] = nil
                kernelApplicationTerminationRecoveryFailures.remove(run.runID)
            } catch {
                // Retain the exact recovered runtime and every native handle it
                // may have reacquired. The failure blocks normal quit and may
                // be retried through the same cleanup-only capability; it must
                // never disappear merely because reconciliation failed.
                kernelApplicationTerminationRecoveryFailures.insert(run.runID)
            }
        }
        await recoverLatestReadyKernelEnrollment(from: report)
    }

    private func refreshLatestKernelExecutionReadiness() async {
        guard let enrollment = latestKernelEnrollmentReceipt,
              let coordinator = kernelExecutionCoordinator else { return }
        do {
            latestKernelExecutionReadiness = try await coordinator
                .nativeExecutionReadiness(
                    for: enrollment,
                    designBaseline: latestAuthorizedKernelDesignBaseline
                )
        } catch {
            latestKernelExecutionReadiness = nil
        }
    }

    var selectedCodexModel: CodexModelOption {
        codexConnection.models.first(where: { $0.slug == draftOfficialModel }) ?? codexConnection.recommendedModel
    }

    var availableReasoningLevels: [CodexReasoningOption] { selectedCodexModel.supportedReasoningLevels }

    func modelChoices(provider: AgentProviderKind, role: AgentRole) -> [AgentModelChoice] {
        switch provider {
        case .codex:
            return codexConnection.models.map {
                AgentModelChoice(
                    id: $0.slug,
                    displayName: $0.displayName,
                    detail: "Codex · authenticated with ChatGPT",
                    reasoningOptions: $0.supportedReasoningLevels.map(\.effort),
                    supportsVision: true,
                    supportsSubAgent: true
                )
            }
        case .local:
            return agentCatalog.localModels.map {
                AgentModelChoice(
                    id: $0.id,
                    displayName: $0.displayName,
                    detail: $0.resourceLabel,
                    reasoningOptions: [],
                    supportsVision: $0.supportsVision,
                    supportsSubAgent: true
                )
            }
        case .api:
            return agentCatalog.apiConnections.map {
                AgentModelChoice(
                    id: $0.id.uuidString,
                    displayName: $0.displayName,
                    detail: $0.resourceLabel,
                    reasoningOptions: $0.reasoningOptions,
                    supportsVision: $0.supportsVision,
                    supportsSubAgent: true
                )
            }
        }
    }

    func provider(for role: AgentRole) -> AgentProviderKind {
        role == .control ? draftControlProvider : draftSubProvider
    }

    func modelReference(for role: AgentRole) -> String {
        role == .control ? draftControlModelReference : draftSubModelReference
    }

    func reasoningEffort(for role: AgentRole) -> String {
        role == .control ? draftControlReasoningEffort : draftReasoningEffort
    }

    func accessMode(for role: AgentRole) -> CodexAccessMode {
        role == .control ? draftControlAccessMode : draftAccessMode
    }

    /// Native Journaled Auto Graph authoring exposes the mutation-free worker
    /// path directly. The independent reviewer has one truthful authority:
    /// read-only. This prevents the picker from advertising access that the
    /// ratified execution profile would discard or silently narrow later.
    func accessModes(for role: AgentRole) -> [CodexAccessMode] {
        switch role {
        case .control:
            return CodexAccessMode.independentReviewerSelectableCases
        case .subAgent:
            return CodexAccessMode.nativeWorkerSelectableCases
        }
    }

    func setProvider(_ provider: AgentProviderKind, role: AgentRole) {
        if role == .control { draftControlProvider = provider }
        else { draftSubProvider = provider }
        let choices = modelChoices(provider: provider, role: role)
        if let first = choices.first { setModelReference(first.id, role: role) }
    }

    func openLocalModelPicker(for role: AgentRole) {
        setProvider(.local, role: role)
        modelManagerRequestedRole = role
        modelManagerPreferredProvider = .local
        showingModelManager = true
    }

    func openModelManager(preferredProvider: AgentProviderKind? = nil) {
        modelManagerRequestedRole = nil
        if let preferredProvider, preferredProvider != .codex {
            modelManagerPreferredProvider = preferredProvider
        }
        showingModelManager = true
    }

    func setModelReference(_ reference: String, role: AgentRole) {
        if role == .control { draftControlModelReference = reference }
        else {
            draftSubModelReference = reference
            if draftSubProvider == .codex { draftOfficialModel = reference }
        }
        let options = reasoningOptions(for: role)
        let current = reasoningEffort(for: role)
        let next = options.contains(current) ? current : (options.last ?? "")
        if role == .control { draftControlReasoningEffort = next }
        else { draftReasoningEffort = next }
    }

    func setReasoningEffort(_ effort: String, role: AgentRole) {
        if role == .control { draftControlReasoningEffort = effort }
        else { draftReasoningEffort = effort }
    }

    func setAccessMode(_ access: CodexAccessMode, role: AgentRole) {
        guard accessModes(for: role).contains(access) else { return }
        if role == .control { draftControlAccessMode = access }
        else { draftAccessMode = access }
    }

    func reasoningOptions(for role: AgentRole) -> [String] {
        let provider = provider(for: role)
        let reference = modelReference(for: role)
        return modelChoices(provider: provider, role: role).first { $0.id == reference }?.reasoningOptions ?? []
    }

    func selectedAgent(for role: AgentRole) -> AgentSelection? {
        let provider = provider(for: role)
        let reference = modelReference(for: role)
        let reasoning = reasoningEffort(for: role).trimmingCharacters(in: .whitespacesAndNewlines)
        let access = accessMode(for: role)
        switch provider {
        case .codex:
            guard let choice = modelChoices(provider: .codex, role: role).first(where: { $0.id == reference }) else { return nil }
            return .codex(
                model: reference,
                displayName: choice.displayName,
                reasoning: reasoning.isEmpty ? nil : reasoning,
                access: access
            )
        case .local:
            guard let profile = agentCatalog.localProfile(idOrName: reference) else { return nil }
            return .local(profile: profile, reasoning: reasoning.isEmpty ? nil : reasoning, access: access)
        case .api:
            guard let id = UUID(uuidString: reference),
                  let connection = agentCatalog.apiConnection(id: id) else { return nil }
            return .api(connection: connection, reasoning: reasoning.isEmpty ? nil : reasoning, access: access)
        }
    }

    func adoptRecommendedCodexDefaults() {
        let recommended = codexConnection.recommendedModel
        draftOfficialModel = recommended.slug
        draftControlProvider = .codex
        draftControlModelReference = recommended.slug
        draftControlReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
        draftSubProvider = .codex
        draftSubModelReference = recommended.slug
        draftReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
    }

    func codexModelChanged() {
        let available = selectedCodexModel.supportedReasoningLevels.map(\.effort)
        if !available.contains(draftReasoningEffort) {
            draftReasoningEffort = CodexCatalog.strongestReasoning(for: selectedCodexModel)
        }
    }

    func startNewTaskFlow() {
        if selectedModule == .continuumWatcher {
            startNewWatcherFlow()
            return
        }
        resetDraft()
        showingNewTask = true
    }

    /// Test/internal typed draft boundary. Production selection must enter
    /// through the native manifest picker below; AppModel never infers a
    /// command from objective prose or reuses a worker/reviewer executable.
    func setNativeVerificationProbe(
        _ probe: RequirementVerificationExecutableProbe?
    ) {
        draftNativeVerificationProbeSelection = nil
        draftNativeVerificationProbe = probe
    }

    /// Test/internal equivalent of one successful native file-panel import.
    /// Production still enters through `chooseNativeVerificationProbeManifest`.
    func setNativeVerificationProbeSelection(
        _ selection: NativeVerificationProbeSelection?
    ) {
        draftNativeVerificationProbeSelection = selection
        draftNativeVerificationProbe = selection?.probe
    }

    /// Selects one schema-constrained deterministic verifier manifest. The
    /// loader opens both manifest and executable no-follow, hashes exact bytes,
    /// and fixes environment, parser, capture, network, and child-process
    /// policy rather than accepting those authorities from JSON.
    func chooseNativeVerificationProbeManifest() {
        guard !nativeVerificationProbeImportInProgress else { return }
        let panel = NSOpenPanel()
        panel.title = "Select an exact verification manifest"
        panel.message = "Choose JSON that names one direct-process verifier executable, exact argv, result mappings, and bounded resources. LoopForge will open and hash the executable before contract review."
        panel.prompt = "Select Verifier"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        present(panel) { [weak self] url in
            guard let self else { return }
            self.nativeVerificationProbeImportInProgress = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await Task.detached {
                    try NativeVerificationProbeSelectionLoader.load(
                        manifestURL: url
                    )
                }.result
                self.nativeVerificationProbeImportInProgress = false
                switch result {
                case .success(let selection):
                    self.draftNativeVerificationProbeSelection = selection
                    self.draftNativeVerificationProbe = selection.probe
                    self.estimate = nil
                case .failure(let error):
                    self.draftNativeVerificationProbeSelection = nil
                    self.draftNativeVerificationProbe = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func clearNativeVerificationProbeSelection() {
        guard !nativeVerificationProbeImportInProgress else { return }
        draftNativeVerificationProbeSelection = nil
        draftNativeVerificationProbe = nil
        estimate = nil
    }

    /// Selects one schema-constrained capture-source manifest through the
    /// native file panel. File paths from JSON are never accepted as digests:
    /// the loader opens them no-follow, hashes protected artifacts, and routes
    /// raw capture bytes through the allow-listed native adapter first.
    func chooseNativeDesignBaselineCaptureSource() {
        guard !nativeDesignBaselineImportInProgress else { return }
        let panel = NSOpenPanel()
        panel.title = "Select a native design-baseline capture manifest"
        panel.message = "Choose the JSON manifest that names the protected source/artifact archives and native capture evidence. LoopForge will rehash every selected file before contract review."
        panel.prompt = "Import Baseline"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        present(panel) { [weak self] url in
            guard let self else { return }
            self.nativeDesignBaselineImportInProgress = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await Task.detached {
                    try await NativeDesignBaselineCaptureSourceLoader.load(
                        manifestURL: url,
                        importedAt: Date()
                    )
                }.result
                self.nativeDesignBaselineImportInProgress = false
                switch result {
                case .success(let source):
                    self.draftNativeDesignBaselineSource = source
                    self.estimate = nil
                case .failure(let error):
                    self.draftNativeDesignBaselineSource = nil
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func clearNativeDesignBaselineCaptureSource() {
        guard !nativeDesignBaselineImportInProgress else { return }
        draftNativeDesignBaselineSource = nil
        estimate = nil
    }

    func selectModule(_ module: LoopForgeModule) {
        guard selectedModule != module else { return }
        selectedModule = module
        if module == .autoLoop {
            showingNewTask = store.tasks.isEmpty
        } else {
            showingNewWatcher = watcherStore.watchers.isEmpty
            presentWatcherGuideIfNeeded()
        }
    }

    func startNewWatcherFlow() {
        watcherDraftRequest = ""
        watcherDraftWorkspacePath = nil
        watcherDraftProjectMode = nil
        watcherDraftPollSeconds = 15 * 60
        watcherDraftReviewSeconds = 4 * 60 * 60
        watcherDraftNotifications = true
        watcherDraftLaunchAtLogin = true
        watcherAgentWasCustomized = false
        adoptRecommendedWatcherCodexDefault()
        showingNewWatcher = true
    }

    func presentWatcherGuideIfNeeded() {
        guard selectedModule == .continuumWatcher,
              !UserDefaults.standard.bool(forKey: AppConstants.watcherGuideCompletedKey),
              !showingWatcherGuide else { return }
        watcherGuideStartIndex = 0
        showingWatcherGuide = true
    }

    func showWatcherGuide(startingAtCadence: Bool = false) {
        watcherGuideStartIndex = startingAtCadence ? WatcherGuideStep.cadence.rawValue : 0
        showingWatcherGuide = true
    }

    func finishWatcherGuide() {
        showingWatcherGuide = false
        UserDefaults.standard.set(true, forKey: AppConstants.watcherGuideCompletedKey)
    }

    var watcherModelChoices: [AgentModelChoice] {
        switch watcherDraftProvider {
        case .codex:
            return modelChoices(provider: .codex, role: .control)
        case .api:
            return modelChoices(provider: .api, role: .control)
        case .local:
            return modelChoices(provider: .local, role: .control).filter { choice in
                guard let profile = agentCatalog.localProfile(idOrName: choice.id) else {
                    return false
                }
                return agentCatalog.isLocalModelReady(profile)
            }
        }
    }

    var watcherReasoningOptions: [String] {
        watcherModelChoices.first {
            $0.id == watcherDraftModelReference
        }?.reasoningOptions ?? []
    }

    var watcherSelectedModelChoice: AgentModelChoice? {
        watcherModelChoices.first { $0.id == watcherDraftModelReference }
    }

    func setWatcherProvider(_ provider: AgentProviderKind) {
        watcherAgentWasCustomized = true
        watcherDraftProvider = provider
        if provider == .codex, codexConnection.isConnected {
            let recommended = codexConnection.recommendedModel
            watcherDraftModelReference = recommended.slug
            watcherDraftReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
            return
        }
        if let first = watcherModelChoices.first {
            setWatcherModelReference(first.id)
        } else {
            watcherDraftModelReference = ""
            watcherDraftReasoningEffort = ""
        }
    }

    func setWatcherModelReference(_ reference: String) {
        watcherAgentWasCustomized = true
        watcherDraftModelReference = reference
        let options = watcherReasoningOptions
        if !options.contains(watcherDraftReasoningEffort) {
            watcherDraftReasoningEffort = options.last ?? ""
        }
    }

    func setWatcherReasoningEffort(_ effort: String) {
        watcherAgentWasCustomized = true
        watcherDraftReasoningEffort = effort
    }

    func adoptRecommendedWatcherCodexDefault() {
        watcherDraftProvider = .codex
        let recommended = codexConnection.recommendedModel
        watcherDraftModelReference = recommended.slug
        watcherDraftReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
    }

    func selectedWatcherAgent() -> AgentSelection? {
        let reasoning = watcherDraftReasoningEffort
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch watcherDraftProvider {
        case .codex:
            guard codexConnection.isConnected,
                  let choice = watcherSelectedModelChoice else { return nil }
            return .codex(
                model: choice.id,
                displayName: choice.displayName,
                reasoning: reasoning.isEmpty ? nil : reasoning,
                access: .workspaceOnly
            )
        case .api:
            guard let id = UUID(uuidString: watcherDraftModelReference),
                  let connection = agentCatalog.apiConnection(id: id),
                  APIKeyVault.get(for: connection.id)?.isEmpty == false else {
                return nil
            }
            return .api(
                connection: connection,
                reasoning: reasoning.isEmpty ? nil : reasoning,
                access: .workspaceOnly
            )
        case .local:
            guard let profile = agentCatalog.localProfile(
                idOrName: watcherDraftModelReference
            ), agentCatalog.isLocalModelReady(profile) else { return nil }
            return .local(
                profile: profile,
                reasoning: reasoning.isEmpty ? nil : reasoning,
                access: .workspaceOnly
            )
        }
    }

    var watcherAgentSetupMessage: String {
        switch watcherDraftProvider {
        case .codex:
            return codexConnection.isConnected
                ? (watcherSelectedModelChoice?.detail ?? "Choose a Codex model.")
                : "Connect with ChatGPT before building, or choose API or Local Deployment."
        case .api:
            return watcherModelChoices.isEmpty
                ? "Add and test an API connection in Manage Models."
                : (watcherSelectedModelChoice?.detail ?? "Choose a configured API model.")
        case .local:
            return watcherModelChoices.isEmpty
                ? "Download and verify a local model in Manage Models."
                : (watcherSelectedModelChoice?.detail ?? "Choose a downloaded local model.")
        }
    }

    func chooseExistingWatcherProject() {
        let panel = NSOpenPanel()
        panel.title = "Open a project for Continuum Watcher"
        panel.message = "Choose the folder where the durable pipeline and checkpoints will live."
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        present(panel) { [weak self] url in
            self?.watcherDraftWorkspacePath = url.standardizedFileURL.path
            self?.watcherDraftProjectMode = .existing
        }
    }

    func createNewWatcherProjectFolder() {
        let panel = NSSavePanel()
        panel.title = "Create a project for Continuum Watcher"
        panel.message = "The generated pipeline, telemetry, and durable checkpoint stay in this folder."
        panel.prompt = "Create Project"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "New Watcher"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LoopForge Projects", isDirectory: true)
        present(panel) { [weak self] url in
            self?.finishCreatingWatcherProjectFolder(at: url)
        }
    }

    private func finishCreatingWatcherProjectFolder(at url: URL) {
        do {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw LoopForgeError.invalidWorkspace }
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            watcherDraftWorkspacePath = url.standardizedFileURL.path
            watcherDraftProjectMode = .new
        } catch {
            alertMessage = "The project folder could not be created: \(error.localizedDescription)"
        }
    }

    func changeWatcherProjectSelection() {
        watcherDraftWorkspacePath = nil
        watcherDraftProjectMode = nil
    }

    func buildWatcher() {
        guard !launchProfile.isIsolatedInspection else {
            alertMessage = "Isolated inspection mode cannot build or resume work. Relaunch LoopForge normally to create a Watcher."
            return
        }
        let request = watcherDraftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            alertMessage = "Describe the target Continuum Watcher should monitor or process."
            return
        }
        guard let workspace = watcherDraftWorkspacePath,
              watcherDraftProjectMode != nil else {
            alertMessage = "Choose an existing project or create a project folder first."
            return
        }
        guard let agentSelection = selectedWatcherAgent() else {
            alertMessage = watcherAgentSetupMessage
            return
        }
        showingNewWatcher = false
        watcherController.buildAndStart(
            request: request,
            workspacePath: workspace,
            pollIntervalSeconds: watcherDraftPollSeconds,
            reviewIntervalSeconds: max(
                WatcherPolicy.minimumReviewInterval,
                watcherDraftReviewSeconds
            ),
            notificationsEnabled: watcherDraftNotifications,
            launchAtLogin: watcherDraftLaunchAtLogin,
            agentSelection: agentSelection
        )
    }

    func chooseExistingProject() {
        let panel = NSOpenPanel()
        panel.title = "Open an existing project"
        panel.message = "Choose the project folder that official Codex may inspect and modify."
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        // Keep the workspace chooser independent from the SwiftUI scene. On
        // current macOS releases, replacing ProjectEntryChooser with
        // TaskComposer while a sheet is being dismissed can tear down the
        // only app window even though the process remains alive. An app-modal
        // open panel avoids that scene/sheet lifetime race and returns focus
        // to the existing LoopForge window after selection.
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.draftWorkspacePath = url.path
                self?.draftProjectMode = .existing
                // The panel completion may run before AppKit has restored the
                // ordering of the owning scene. Defer one main-actor turn, then
                // explicitly return the existing workspace window to the front
                // so the process cannot remain alive with no visible window.
                await Task.yield()
                NSApp.activate(ignoringOtherApps: true)
                (NSApp.keyWindow
                    ?? NSApp.mainWindow
                    ?? NSApp.windows.first(where: { $0.canBecomeMain }))?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    func createNewProjectFolder() {
        let panel = NSSavePanel()
        panel.title = "Create a new project folder"
        panel.message = "Name the workspace that LoopForge and official Codex will build in."
        panel.prompt = "Create Project"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "New Project"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LoopForge Projects", isDirectory: true)
        present(panel) { [weak self] url in
            self?.finishCreatingProjectFolder(at: url)
        }
    }

    private func present(_ panel: NSSavePanel, onSelection: @escaping @MainActor (URL) -> Void) {
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in onSelection(url) }
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func finishCreatingProjectFolder(at url: URL) {
        do {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw LoopForgeError.invalidWorkspace }
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            draftWorkspacePath = url.path
            draftProjectMode = .new
        } catch {
            alertMessage = "The project folder could not be created: \(error.localizedDescription)"
        }
    }

    func changeProjectSelection() {
        draftProjectMode = nil
        draftWorkspacePath = nil
        estimate = nil
    }

    func calculateEstimate() {
        let trimmed = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draftProjectMode != nil, draftWorkspacePath != nil else {
            alertMessage = "Choose an existing project or create a new project folder first."
            return
        }
        guard !trimmed.isEmpty else {
            estimate = nil
            alertMessage = "Describe the outcome you want in one sentence first."
            return
        }
        let result = estimator.estimate(
            request: trimmed,
            quality: draftQuality,
            workspacePath: draftWorkspacePath
        )
        estimate = result
        draftLocalModelID = result.model.id
        draftTargetMinutes = max(draftQuality.defaultRuntimeMinutes, Int(result.recommendedSeconds / 60))
        if result.category.prefersOfficialControlAgent {
            let recommended = codexConnection.recommendedModel
            draftControlProvider = .codex
            draftControlModelReference = recommended.slug
            draftControlReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
            draftSubProvider = .codex
            draftSubModelReference = recommended.slug
            draftOfficialModel = recommended.slug
            draftReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
        }
    }

    func qualityChanged() {
        draftExecutionMode = .autoGraph
        if estimate != nil { calculateEstimate() }
        else { draftTargetMinutes = max(draftTargetMinutes, draftQuality.defaultRuntimeMinutes) }
    }

    func selectAutoGraphLoop() {
        draftExecutionMode = .autoGraph
        if estimate != nil { calculateEstimate() }
    }

    func selectSingleLoop() {
        rejectRetiredLegacyAuthoring(.singleLoop)
    }

    func setParallelCandidatesEnabled(_ enabled: Bool) {
        if enabled {
            rejectRetiredLegacyAuthoring(.parallelCandidates)
        } else {
            draftExecutionMode = .autoGraph
        }
    }

    func setParallelCandidateCount(_ count: Int) {
        draftParallelCandidateCount = ParallelCandidatePolicy.normalizedCount(count)
    }

    func setDraftTargetHours(_ hours: Double) {
        let finiteHours = hours.isFinite ? hours : Double(draftQuality.defaultRuntimeMinutes) / 60.0
        let roundedMinutes = Int((finiteHours * 4).rounded()) * 15
        draftTargetMinutes = min(30 * 24 * 60, max(AppConstants.minimumCustomRuntimeMinutes, roundedMinutes))
    }

    func adjustDraftTargetMinutes(by delta: Int) {
        draftTargetMinutes = min(30 * 24 * 60, max(AppConstants.minimumCustomRuntimeMinutes, draftTargetMinutes + delta))
    }

    func restoreRecommendedRuntime() {
        guard let estimate else { return }
        draftTargetMinutes = max(draftQuality.defaultRuntimeMinutes, Int(estimate.recommendedSeconds / 60))
    }

    func requestStartLoop() {
        guard !launchProfile.isIsolatedInspection else {
            alertMessage = "Isolated inspection mode cannot enroll or start work. Relaunch LoopForge normally to create a task."
            return
        }
        guard draftExecutionMode == .autoGraph else {
            rejectRetiredLegacyAuthoring(draftExecutionMode)
            return
        }
        let trimmed = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alertMessage = "Describe the outcome you want first."
            return
        }
        if estimate == nil { calculateEstimate() }
        guard estimate != nil else { return }
        pendingOriginalPromptForTask = trimmed
        pendingPromptOptimizationSource = nil
        showingPromptOptimizationOffer = true
    }

    func startWithOriginalPrompt() {
        showingPromptOptimizationOffer = false
        guard draftExecutionMode == .autoGraph else {
            rejectRetiredLegacyAuthoring(draftExecutionMode)
            return
        }
        pendingOriginalPromptForTask = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPromptOptimizationSource = "Original prompt selected by user"
        prepareNativeAutoGraphContract(
            objective: pendingOriginalPromptForTask ?? draftRequest,
            sourceAuthority: .user
        )
    }

    func beginPromptOptimization() {
        showingPromptOptimizationOffer = false
        guard draftExecutionMode == .autoGraph else {
            rejectRetiredLegacyAuthoring(draftExecutionMode)
            return
        }
        guard let task = promptOptimizationTask() else { return }
        showingPromptOptimization = true
        promptOptimizationCandidates = []
        promptOptimizationProvider = ""
        promptOptimizationPhase = .generating(provider: "Codex → API → Local")

        let recommended = codexConnection.recommendedModel
        let codexSelection: AgentSelection? = codexConnection.isConnected
            ? .codex(
                model: recommended.slug,
                displayName: recommended.displayName,
                reasoning: CodexCatalog.strongestReasoning(for: recommended),
                access: .workspaceOnly
            )
            : nil
        let apis = agentCatalog.apiConnections
        let installed = agentCatalog.localModels.filter {
            agentCatalog.isLocalModelReady($0)
        }
        let preferredLocal = selectedAgent(for: .control)?.localProfile
        var localProfiles = installed
        if let preferredLocal,
           !localProfiles.contains(where: { $0.ollamaName == preferredLocal.ollamaName }) {
            localProfiles.append(preferredLocal)
        }

        Task {
            do {
                let result = try await promptOptimizer.optimize(
                    task: task,
                    codex: codexSelection,
                    apiConnections: apis,
                    localProfiles: localProfiles
                )
                promptOptimizationCandidates = result.candidates
                promptOptimizationProvider = result.providerLabel
                promptOptimizationPhase = .ready
            } catch {
                promptOptimizationPhase = .failed(sanitizedLogText(error.localizedDescription))
            }
        }
    }

    func startWithOptimizedPrompt(_ candidate: PromptOptimizationCandidate) {
        guard draftExecutionMode == .autoGraph else {
            rejectRetiredLegacyAuthoring(draftExecutionMode)
            return
        }
        let original = pendingOriginalPromptForTask
            ?? draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingOriginalPromptForTask = original
        pendingPromptOptimizationSource = "\(promptOptimizationProvider) · \(candidate.title)"
        showingPromptOptimization = false
        let confirmedMinutes = draftTargetMinutes
        draftRequest = candidate.prompt
        calculateEstimate()
        draftTargetMinutes = confirmedMinutes
        prepareNativeAutoGraphContract(
            objective: candidate.prompt,
            sourceAuthority: .acceptedUserAmendment
        )
    }

    func cancelPromptOptimization() {
        showingPromptOptimization = false
        promptOptimizationPhase = .idle
        promptOptimizationCandidates = []
        promptOptimizationProvider = ""
    }

    private func promptOptimizationTask() -> LoopTask? {
        guard draftExecutionMode == .autoGraph,
              let estimate,
              let workspace = try? preparedWorkspace() else {
            alertMessage = "Estimate the task and choose a valid project before optimizing its prompt."
            return nil
        }
        let request = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        return LoopTask(
            id: UUID(),
            title: safeProjectName(from: request),
            request: request,
            quality: draftQuality,
            category: estimate.category,
            workspacePath: workspace.path,
            targetSeconds: TimeInterval(draftTargetMinutes * 60),
            accumulatedCodexSeconds: 0,
            model: selectedLocalModel,
            status: .preparing,
            stage: "Optimizing prompt",
            iteration: 0,
            threadID: nil,
            auditScore: 0,
            auditSummary: "",
            lastAgentMessage: "",
            consecutiveFailures: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            logs: [],
            originalRequest: request,
            executionMode: draftExecutionMode
        )
    }

    private func rejectRetiredLegacyAuthoring(_ mode: LoopExecutionMode) {
        draftExecutionMode = .autoGraph
        estimate = nil
        showingPromptOptimizationOffer = false
        showingPromptOptimization = false
        alertMessage = LegacyTaskExecutionRetirementPolicy.authoringMessage(
            for: mode
        )
    }

    private func prepareNativeAutoGraphContract(
        objective: String,
        sourceAuthority: TaskContractSourceAuthority
    ) {
        guard draftExecutionMode == .autoGraph else {
            alertMessage = "Native contract enrollment is currently limited to Auto Graph."
            return
        }
        guard kernelRunEnrollmentCoordinator != nil else {
            alertMessage = "The journaled kernel registry is unavailable. No task was created."
            return
        }
        do {
            let workspace = try preparedWorkspace().standardizedFileURL
                .resolvingSymlinksInPath()
            guard let worker = selectedAgent(for: .subAgent),
                  let reviewer = selectedAgent(for: .control) else {
                alertMessage = "Choose a configured model for both the worker and independent reviewer."
                return
            }
            let now = Date()
            let userActor = nativeContractUserActor()
            let workspaceDigest = TaskContractCompiler.digest(
                Data(workspace.path.precomposedStringWithCanonicalMapping.utf8)
            )
            let mutationAuthorized = worker.accessMode != .readOnly
            let sourceRevisionCapturePolicy =
                WorkspaceCandidatePostimageCapturePolicy(
                    excludedDirectoryNames:
                        NativeSourceRevisionCapturePolicyParser
                            .parseExcludedDirectoryNames(
                                draftSourceRevisionExcludedDirectoryNames
                            ),
                    limits: NativeTaskContractAuthoringRequest
                        .defaultSourceRevisionCapturePolicy.limits
                )
            let request = NativeTaskContractAuthoringRequest(
                exactObjective: objective,
                objectiveSourceAuthority: sourceAuthority,
                workspaceID: WorkspaceID(
                    "native-workspace-\(workspaceDigest.rawValue)"
                ),
                workspaceRoot: workspace,
                readableScopes: ["."],
                writableScopes: mutationAuthorized ? ["."] : [],
                authorityCapabilityIDs: draftWorkerNetworkAccess
                    ? [KernelExecutionProfile.networkCapabilityID]
                    : [],
                acceptedDuration: nil,
                executionProfile: try nativeKernelExecutionProfile(
                    worker: worker,
                    reviewer: reviewer
                ),
                verificationProbe: draftNativeVerificationProbe,
                executionBudgets: nativeKernelExecutionBudgets(
                    mutationAuthorized: mutationAuthorized
                ),
                designBaselineSource: draftNativeDesignBaselineSource,
                sourceRevisionCapturePolicy: sourceRevisionCapturePolicy,
                permittedImplementationIDs:
                    NativeExactImplementationIdentityParser.parse(
                        draftPermittedImplementationIDs
                    ),
                deliverableCollectionID: draftDeliverableCollectionID,
                deliverableExactCountText: draftDeliverableExactCount,
                userActor: userActor,
                recordedAt: now,
                authoringNonce: TaskContractCompiler.digest(
                    Data(UUID().uuidString.utf8)
                )
            )
            switch NativeTaskContractAuthor.prepare(request) {
            case .success(let draft):
                pendingNativeContractUserActor = userActor
                pendingNativeContractConfirmation = draft
                pendingRatifiedNativeContract = nil
                pendingNativeEnrollmentRequestIdentity = nil
            case .failure(let error):
                alertMessage = nativeContractErrorMessage(error)
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func nativeKernelExecutionProfile(
        worker: AgentSelection,
        reviewer: AgentSelection
    ) throws -> KernelExecutionProfile {
        let executableDigest: ContentDigest
        let providerProtocol: KernelProviderProtocol
        let providerHarnessMode: KernelProviderHarnessMode
        if let harness = NativeProviderHarnessSelectionLoader.bundled() {
            executableDigest = harness.manifest.executableSHA256
            providerProtocol = .loopForgeProviderHarnessV2
            providerHarnessMode = harness.manifest.operationalMode
        } else if let executable = CodexRuntime.executable?
            .standardizedFileURL.resolvingSymlinksInPath(),
            let digest = ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: executable.path
            ) {
            // Development and recovered installations retain the direct
            // executable identity as evidence, but never relabel it as a
            // LoopForge provider protocol implementation.
            executableDigest = digest
            providerProtocol = .unavailable
            providerHarnessMode = .unavailable
        } else {
            throw LoopForgeError.executableMissing("ratifiable provider executable")
        }
        let workerSandbox: KernelExecutionSandbox
        switch worker.accessMode {
        case .readOnly: workerSandbox = .readOnly
        case .workspaceOnly: workerSandbox = .workspaceOnly
        case .fullAccess: workerSandbox = .fullAccess
        }
        let workerNetworkPolicy: KernelNetworkPolicy =
            draftWorkerNetworkAccess ? .enabled : .disabled
        return KernelExecutionProfile(
            schemaVersion: 1,
            worker: nativeKernelAgentProfile(
                worker,
                sandbox: workerSandbox,
                networkPolicy: workerNetworkPolicy,
                executableContentDigest: executableDigest,
                providerProtocol: providerProtocol,
                providerHarnessMode: providerHarnessMode
            ),
            independentReviewer: nativeKernelAgentProfile(
                reviewer,
                sandbox: .readOnly,
                networkPolicy: .disabled,
                executableContentDigest: executableDigest,
                providerProtocol: providerProtocol,
                providerHarnessMode: providerHarnessMode
            ),
            requiresDistinctActorLineage: true
        )
    }

    /// Conservative, domain-neutral authority proposed by the native app and
    /// displayed in full before the user confirms the candidate digest.
    /// These values authorize only ceilings; the separately displayed and
    /// confirmed strategy/plan proposal still creates no attempt or start.
    private func nativeKernelExecutionBudgets(
        mutationAuthorized: Bool
    ) -> KernelExecutionBudgetPolicy {
        KernelExecutionBudgetPolicy(
            mutation: KernelMutationBudget(
                maximumChangedFiles: mutationAuthorized ? 32 : 0,
                maximumChangedBytes: mutationAuthorized ? 1_048_576 : 0
            ),
            convergence: ConvergenceBudget(
                maximumAttempts: 3,
                maximumEquivalentFailures: 3,
                maximumStrategies: 3,
                maximumPlanExpansions: 1,
                maximumMutationCost: mutationAuthorized ? 1_048_576 : 0,
                maximumVerificationCost: 32,
                maximumDamageEvents: 0,
                maximumExternalEffects: 0
            )
        )
    }

    private func nativeKernelAgentProfile(
        _ selection: AgentSelection,
        sandbox: KernelExecutionSandbox,
        networkPolicy: KernelNetworkPolicy,
        executableContentDigest: ContentDigest,
        providerProtocol: KernelProviderProtocol,
        providerHarnessMode: KernelProviderHarnessMode
    ) -> KernelAgentExecutionProfile {
        let provider: KernelExecutionProvider
        let providerReference: String
        switch selection.provider {
        case .codex:
            provider = .codex
            providerReference = "official-codex-session"
        case .local:
            provider = .local
            providerReference = selection.localProfile?.id ?? selection.modelID
        case .api:
            provider = .api
            providerReference = selection.apiConnection?.id.uuidString.lowercased()
                ?? selection.modelID
        }
        let credentialMode: KernelProviderCredentialMode = provider == .api
            ? .opaqueProviderSecret
            : .none
        let credentialReference = selection.apiConnection.map {
            APIKeyVault.kernelCredentialReference(for: $0.id)
        }
        return KernelAgentExecutionProfile(
            provider: provider,
            providerReference: providerReference,
            executableContentDigest: executableContentDigest,
            modelID: selection.modelID,
            reasoningEffort: selection.reasoningEffort,
            sandbox: sandbox,
            networkPolicy: networkPolicy,
            pluginPolicy: .disabled,
            environmentPolicy: .minimalKernelAllowlist,
            // A packaged selection is a descriptor-aware transport identity,
            // not a productive-provider claim. This ordinary-app loader can
            // select only transport-veto mode; productive authority requires
            // a separately isolated and ratified execution product.
            providerProtocol: providerProtocol,
            providerHarnessMode: providerHarnessMode,
            credentialMode: credentialMode,
            credentialReference: credentialReference
        )
    }

    func cancelNativeContractConfirmation() {
        guard !kernelEnrollmentInProgress else { return }
        pendingNativeContractConfirmation = nil
        draftNativeVerificationProbeSelection = nil
        draftNativeVerificationProbe = nil
        pendingNativeContractUserActor = nil
        pendingRatifiedNativeContract = nil
        pendingNativeEnrollmentRequestIdentity = nil
    }

    func cancelPendingNativeAuthorityConfirmation() {
        if pendingNativeDesignBaselineConfirmation != nil {
            cancelNativeDesignBaselineConfirmation()
        } else {
            cancelNativeContractConfirmation()
        }
    }

    func cancelNativeDesignBaselineConfirmation() {
        guard !kernelEnrollmentInProgress else { return }
        pendingNativeDesignBaselineConfirmation = nil
        pendingNativeContractUserActor = nil
        pendingRatifiedNativeContract = nil
        pendingNativeEnrollmentRequestIdentity = nil
        resetDraft()
        showingNewTask = true
        alertMessage = "The run remains enrolled, but its protected design baseline was not frozen. No worker was started."
    }

    func confirmNativeDesignBaseline() {
        guard let draft = pendingNativeDesignBaselineConfirmation,
              let userActor = pendingNativeContractUserActor else { return }
        switch nativeDesignBaselineConfirmationIssuer
            .confirmFromNativeUserAction(
                draft,
                displayedSelectionDigest: draft.selectionDigest,
                userActor: userActor,
                confirmedAt: Date()
            ) {
        case .success(let authority):
            latestAuthorizedKernelDesignBaseline = authority
            pendingNativeDesignBaselineConfirmation = nil
            pendingNativeContractUserActor = nil
            pendingRatifiedNativeContract = nil
            pendingNativeEnrollmentRequestIdentity = nil
            resetDraft()
            showingNewTask = true
            alertMessage = "The enrolled run now holds the explicitly confirmed protected design baseline. No worker was started."
            Task { await refreshLatestKernelExecutionReadiness() }
        case .failure(let error):
            alertMessage = nativeDesignBaselineConfirmationErrorMessage(error)
        }
    }

    func confirmAndEnrollNativeAutoGraphContract() async {
        guard !kernelEnrollmentInProgress,
              let draft = pendingNativeContractConfirmation,
              let userActor = pendingNativeContractUserActor,
              let coordinator = kernelRunEnrollmentCoordinator else { return }
        kernelEnrollmentInProgress = true
        defer { kernelEnrollmentInProgress = false }

#if !DEBUG
        guard draftNativeVerificationProbeSelection != nil else {
            alertMessage = "Select and review an exact verifier manifest before confirming. No run was enrolled."
            return
        }
#endif
        var enrollmentVerificationSelections: [
            NativeVerificationProbeSelection
        ] = []
        if let selected = draftNativeVerificationProbeSelection {
            do {
                let refreshed = try await Task.detached {
                    try NativeVerificationProbeSelectionLoader.revalidate(
                        selected
                    )
                }.value
                guard draftNativeVerificationProbeSelection == selected,
                      draft.compiled.candidate.contract
                        .requirementEvidenceRecipes?
                        .allSatisfy({
                            $0.executableProbe == refreshed.probe
                        }) == true else {
                    alertMessage = NativeVerificationProbeSelectionError
                        .selectionChanged.localizedDescription
                    return
                }
                draftNativeVerificationProbeSelection = refreshed
                draftNativeVerificationProbe = refreshed.probe
                enrollmentVerificationSelections = [refreshed]
            } catch {
                alertMessage = error.localizedDescription
                return
            }
        }

        let ratified: RatifiedTaskContract
        if let existing = pendingRatifiedNativeContract {
            ratified = existing
        } else {
            switch nativeContractConfirmationIssuer.confirmFromNativeUserAction(
                draft,
                displayedCandidateDigest: draft.compiled.candidateDigest,
                userActor: userActor,
                confirmedAt: Date()
            ) {
            case .success(let value):
                ratified = value
                pendingRatifiedNativeContract = value
            case .failure(let error):
                alertMessage = nativeConfirmationErrorMessage(error)
                return
            }
        }

        let identity: (
            runID: KernelRunID,
            commandID: RunCommandID,
            enrolledAt: Date
        )
        if let existing = pendingNativeEnrollmentRequestIdentity {
            identity = existing
        } else {
            let nonce = UUID().uuidString.lowercased()
            let created = (
                runID: KernelRunID("native-run-\(nonce)"),
                commandID: RunCommandID("native-create-\(nonce)"),
                enrolledAt: Date()
            )
            pendingNativeEnrollmentRequestIdentity = created
            identity = created
        }

        do {
            let receipt = try await coordinator.enroll(KernelRunEnrollmentRequest(
                runID: identity.runID,
                ratifiedContract: ratified,
                actorIdentity: ActorIdentity(
                    id: ActorID("loopforge-native-enrollment"),
                    role: "native-enrollment",
                    lineageDigest: TaskContractCompiler.digest(
                        Data("loopforge-native-enrollment-v1".utf8)
                    )
                ),
                workspaceID: draft.workspaceID,
                workspaceRoot: draft.canonicalWorkspaceRoot,
                hostBudget: HostResourceBudget(nominal: ResourceVector(
                    cpuWeight: 1,
                    memoryBytes: 2 * 1_024 * 1_024 * 1_024,
                    diskIOWeight: 1,
                    gpuWeight: 0,
                    networkWeight: 1,
                    guiSessionCount: 1,
                    processCount: 8
                )),
                maximumDispatchBatch: 8,
                createCommandID: identity.commandID,
                enrolledAt: identity.enrolledAt,
                verificationProbeSelections:
                    enrollmentVerificationSelections
            ))
            latestKernelEnrollmentReceipt = receipt
            latestKernelExecutionSessionReceipt = nil
            latestAuthorizedKernelDesignBaseline = nil
            newlyEnrolledKernelRunProjections.removeAll {
                $0.runID == receipt.runID
            }
            newlyEnrolledKernelRunProjections.append(receipt.kernelProjection)
            var readinessFailure: Error?
            if let executionCoordinator = kernelExecutionCoordinator {
                do {
                    latestKernelExecutionReadiness = try await executionCoordinator
                        .nativeExecutionReadiness(
                            for: receipt,
                            designBaseline: latestAuthorizedKernelDesignBaseline
                        )
                } catch {
                    latestKernelExecutionReadiness = nil
                    readinessFailure = error
                }
            } else {
                latestKernelExecutionReadiness = nil
            }
            if let selection = draft.displayDesignBaselineSelection {
                switch NativeDesignBaselineAuthor.prepare(
                    selection: selection,
                    ratifiedContract: ratified,
                    enrollment: receipt,
                    preparedAt: Date()
                ) {
                case .success(let designDraft):
                    pendingNativeContractConfirmation = nil
                    pendingNativeDesignBaselineConfirmation = designDraft
                    pendingNativeEnrollmentRequestIdentity = nil
                    showingNewTask = true
                    alertMessage = "The run is enrolled. Confirm the exact protected artifact and native capture digest to freeze its design baseline. No worker was started."
                    return
                case .failure(let error):
                    pendingNativeContractConfirmation = nil
                    pendingNativeContractUserActor = nil
                    pendingRatifiedNativeContract = nil
                    pendingNativeEnrollmentRequestIdentity = nil
                    resetDraft()
                    showingNewTask = true
                    alertMessage = "The run was enrolled, but design-baseline preparation failed closed: \(error). No worker was started."
                    return
                }
            }
            pendingNativeContractConfirmation = nil
            pendingNativeContractUserActor = nil
            pendingRatifiedNativeContract = nil
            pendingNativeEnrollmentRequestIdentity = nil
            resetDraft()
            showingNewTask = true
            if let readiness = latestKernelExecutionReadiness,
               readiness.blockers.isEmpty {
                alertMessage = "The confirmed Auto Graph contract, source revision, strategy, and requirement-owned plan are enrolled and ready. No start capability or worker was created."
            } else if let readiness = latestKernelExecutionReadiness {
                alertMessage = "The confirmed Auto Graph contract is enrolled and remains ready. Native execution is blocked by \(readiness.blockers.count) missing authority receipts; no legacy worker was started."
            } else if let readinessFailure {
                alertMessage = "The confirmed Auto Graph contract is enrolled and remains ready, but the read-only native execution preflight failed closed: \(readinessFailure). No legacy worker was started."
            } else {
                alertMessage = "The confirmed Auto Graph contract is enrolled in the journaled kernel and remains ready. The native execution readiness service is unavailable; no legacy worker was started."
            }
        } catch {
            alertMessage = "Contract enrollment failed without starting a worker: \(error.localizedDescription)"
        }
    }

    /// Explicit native activation. The AppModel contributes only a fresh
    /// replay-protection nonce and timestamp; the production coordinator
    /// reconstructs every executable field from the exact enrolled journal.
    /// Missing mutation or design authority rejects before legacy execution
    /// can be reached.
    func activateLatestEnrolledKernelRun() async {
        guard !launchProfile.isIsolatedInspection else {
            alertMessage = "Isolated inspection mode cannot activate a native run. Relaunch LoopForge normally to execute work."
            return
        }
        guard !kernelExecutionStartInProgress,
              let enrollment = latestKernelEnrollmentReceipt,
              let coordinator = kernelExecutionCoordinator else { return }
        kernelExecutionStartInProgress = true
        defer { kernelExecutionStartInProgress = false }

        do {
            let readiness = try await coordinator.nativeExecutionReadiness(
                for: enrollment,
                designBaseline: latestAuthorizedKernelDesignBaseline
            )
            latestKernelExecutionReadiness = readiness
            guard readiness.canPrepareAndActivate else {
                alertMessage = "Native activation remains blocked by \(readiness.blockers.count) missing authority receipts. No journal preparation, process, or legacy worker was started."
                return
            }

            let session = try await coordinator.activateNativeEnrolledRun(
                KernelNativeExecutionStartRequest(
                    enrollment: enrollment,
                    designBaseline: latestAuthorizedKernelDesignBaseline,
                    requestNonce: UUID().uuidString.lowercased(),
                    initiatedAt: Date()
                )
            )
            let receipt = session.receipt
            kernelExecutionSessions[receipt.kernelProjection.runID] = session
            latestKernelExecutionSessionReceipt = receipt
            latestKernelExecutionReadiness = nil
            newlyEnrolledKernelRunProjections.removeAll {
                $0.runID == receipt.kernelProjection.runID
            }
            newlyEnrolledKernelRunProjections.append(receipt.kernelProjection)
            let providerBlockers = receipt
                .providerInvocationProfileReadiness.blockers.count
            alertMessage = "The exact enrolled authority is now an active native kernel attempt. No legacy task or Graph worker was created; provider invocation is blocked by \(providerBlockers) exact profile constraints and launch remains a separate receipt-gated step."
        } catch {
            alertMessage = "Native activation failed closed: \(error). No legacy worker was started."
        }
    }

    private func nativeContractUserActor() -> ActorIdentity {
        ActorIdentity(
            id: ActorID("loopforge-native-user"),
            role: "user",
            lineageDigest: TaskContractCompiler.digest(
                Data("loopforge-native-user-v1".utf8)
            )
        )
    }

    private func nativeContractErrorMessage(
        _ error: NativeTaskContractAuthoringError
    ) -> String {
        switch error {
        case .malformedUserAuthority:
            return "The native user authority record is invalid. No task was created."
        case .invalidObjective:
            return "The exact objective is empty or lacks user authority."
        case .invalidWorkspace:
            return "The selected workspace is unavailable or cannot be bound safely."
        case .invalidScope:
            return "The selected workspace scope is not canonical."
        case .invalidAuthorityCapabilities(let issues):
            return "The selected runtime capability authority failed closed: \(issues.joined(separator: "; ")) No task was created."
        case .invalidDuration:
            return "The accepted duration is invalid."
        case .invalidExecutionProfile(let issues):
            return "The selected execution identity failed closed: \(issues.joined(separator: "; "))"
        case .invalidVerificationProbe(let issues):
            return "Executable verification is not yet configured: \(issues.joined(separator: "; ")) No task was created."
        case .invalidExecutionBudgets(let issues):
            return "The selected execution budgets failed closed: \(issues.joined(separator: "; "))"
        case .invalidDesignBaselineSource(let issues):
            return "The selected design baseline failed closed: \(issues.joined(separator: "; ")) No task was created."
        case .invalidSourceRevisionCapturePolicy(let issues):
            return "The source-revision capture policy failed closed: \(issues.joined(separator: "; ")) Use unique directory names only; paths and traversal are not accepted. No task was created."
        case .invalidExactImplementationIDs(let issues):
            return "The exact implementation authority failed closed: \(issues.joined(separator: "; ")) No task was created."
        case .invalidDeliverableCardinality(let issues):
            return "The exact deliverable cardinality failed closed: \(issues.joined(separator: "; ")) No task was created."
        case .sourceRevisionCaptureFailed(let reason):
            return "The selected workspace could not be captured as an exact bounded source revision: \(reason) No task was created."
        case .unsupportedExecutionAuthority(let reason):
            return "The selected execution authority is unavailable: \(reason) No task was created."
        case .compilationFailed(let issues):
            return "The task contract failed closed: \(issues)"
        }
    }

    private func nativeConfirmationErrorMessage(
        _ error: NativeTaskContractConfirmationError
    ) -> String {
        switch error {
        case .displayedCandidateChanged:
            return "The contract changed after it was displayed. Review a fresh contract."
        case .displayedSourceRevisionChanged:
            return "The workspace changed after its source revision was displayed. Review a fresh capture before enrollment."
        case .sourceRevisionRecaptureFailed(let reason):
            return "The workspace source revision could not be rechecked at confirmation: \(reason)"
        case .userIdentityMismatch:
            return "The confirming user does not match the contract author."
        case .alreadyConfirmed:
            return "This exact contract was already confirmed."
        case .ratificationFailed(let failure):
            return "The native confirmation failed closed: \(failure)"
        }
    }

    private func nativeDesignBaselineConfirmationErrorMessage(
        _ error: NativeDesignBaselineConfirmationError
    ) -> String {
        switch error {
        case .displayedSelectionChanged:
            return "The design baseline changed after display. Review a fresh capture source."
        case .userIdentityMismatch:
            return "The confirming user does not match the enrolled contract author."
        case .confirmationPredatesDisplay:
            return "The design baseline confirmation time is invalid."
        case .alreadyConfirmed:
            return "This exact design baseline was already confirmed."
        case .digestConstructionFailed:
            return "The design-baseline authority receipt could not be constructed."
        }
    }

    func resume(_ task: LoopTask) {
        if controller.blockRetiredTaskExecution(
            taskID: task.id,
            source: "user resume request"
        ) {
            alertMessage = LegacyTaskExecutionRetirementPolicy.authoringMessage(
                for: task.resolvedExecutionMode
            )
            return
        }
        controller.start(taskID: task.id)
    }
    func chooseParallelCandidate(_ task: LoopTask, candidateID: String) {
        guard !controller.blockRetiredTaskExecution(
            taskID: task.id,
            source: "user parallel-candidate selection"
        ) else {
            alertMessage = LegacyTaskExecutionRetirementPolicy.authoringMessage(
                for: .parallelCandidates
            )
            return
        }
        controller.chooseParallelCandidate(taskID: task.id, candidateID: candidateID)
    }
    func pause(_ task: LoopTask) { controller.pause(taskID: task.id) }
    func stop(_ task: LoopTask) { controller.stop(taskID: task.id) }
    func openWorkspace(_ task: LoopTask) { NSWorkspace.shared.open(URL(fileURLWithPath: task.workspacePath, isDirectory: true)) }
    func revealWorkspace(_ task: LoopTask) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: task.workspacePath)]) }
    func openCompletionReport(_ task: LoopTask) {
        guard let path = task.completionReportPath else { return }
        store.update(id: task.id) { $0.completionViewedAt = Date() }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func setLocalModel(_ profile: ModelProfile, for task: LoopTask) {
        guard !task.needsVisualAudit || profile.supportsVision else {
            alertMessage = "Visual tasks require a vision-capable local supervisor."
            return
        }
        guard controller.runningTaskID != task.id else {
            alertMessage = "Pause the loop before switching its local supervisor."
            return
        }
        store.update(id: task.id) {
            $0.model = profile
            $0.stage = "Local supervisor changed to \(profile.displayName); ready to resume"
        }
        store.appendLog(id: task.id, kind: .system, "Local supervisor changed to \(profile.displayName) (\(profile.resourceLabel)). The official Codex session and runtime ledger were preserved.")
    }

    func requestDeleteTask(_ task: LoopTask) {
        let current = store.task(id: task.id) ?? task
        if let blocker = taskDeletionBlocker(for: current) {
            alertMessage = blocker
            return
        }
        pendingTaskDeletion = current
    }

    func deleteTaskRecord(_ task: LoopTask) {
        if let blocker = taskDeletionBlocker(for: store.task(id: task.id) ?? task) {
            pendingTaskDeletion = nil
            alertMessage = blocker
            return
        }
        controller.discardParallelCandidateWorkspaces(for: task)
        store.delete(id: task.id)
        pendingTaskDeletion = nil
        if store.tasks.isEmpty { showingNewTask = true }
    }

    func deleteTaskAndMoveWorkspaceToTrash(_ task: LoopTask) {
        if let blocker = taskDeletionBlocker(for: store.task(id: task.id) ?? task) {
            pendingTaskDeletion = nil
            alertMessage = blocker
            return
        }
        let url = URL(fileURLWithPath: task.workspacePath, isDirectory: true).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = url.path
        let protected: [String] = ["/", NSHomeDirectory(), FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path(percentEncoded: false)]
            .compactMap { $0 }
        guard !protected.contains(path), !protected.contains(resolved.path), url.pathComponents.count >= 4 else {
            pendingTaskDeletion = nil
            alertMessage = "LoopForge refused to remove this broad or protected folder. The task record was left unchanged."
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            deleteTaskRecord(task)
            return
        }
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.pendingTaskDeletion = nil
                    self.alertMessage = "The project folder could not be moved to Trash: \(error.localizedDescription)"
                } else {
                    self.deleteTaskRecord(task)
                }
            }
        }
    }

    private func taskDeletionBlocker(for task: LoopTask) -> String? {
        if controller.runningTaskID == task.id {
            if task.status == .pausing || task.status == .paused {
                return "Pause is still finishing. Wait for “Paused · Saved” to appear, then delete the task."
            }
            if task.status == .stopping || task.status == .stopped {
                return "The task is still ending. Delete will be available as soon as “Stopped” appears."
            }
            return "Pause or end this task before deleting it."
        }
        if task.status == .pausing {
            return "Pause is still finishing. Wait for “Paused · Saved” to appear, then delete the task."
        }
        if task.status == .stopping {
            return "The task is still ending. Delete will be available as soon as “Stopped” appears."
        }
        return nil
    }

    func resetDraft(keepRequest: Bool = false) {
        if !keepRequest { draftRequest = "" }
        draftExecutionMode = .autoGraph
        draftParallelCandidateCount = 3
        draftParallelSelectionMode = .agent
        draftQuality = .medium
        draftTargetMinutes = QualityTier.medium.defaultRuntimeMinutes
        draftWorkspacePath = nil
        draftProjectMode = nil
        estimate = nil
        draftLocalModelID = ModelProfile.advancedVisualAuditor.id
        draftControlProvider = .codex
        draftControlModelReference = AppConstants.officialWorkerModel
        draftControlReasoningEffort = "ultra"
        draftControlAccessMode = .readOnly
        draftAccessMode = .workspaceOnly
        modelManagerRequestedRole = nil
        showingPromptOptimizationOffer = false
        showingPromptOptimization = false
        promptOptimizationPhase = .idle
        promptOptimizationCandidates = []
        promptOptimizationProvider = ""
        pendingOriginalPromptForTask = nil
        pendingPromptOptimizationSource = nil
        pendingNativeContractConfirmation = nil
        draftNativeVerificationProbeSelection = nil
        draftNativeVerificationProbe = nil
        draftNativeDesignBaselineSource = nil
        draftSourceRevisionExcludedDirectoryNames =
            NativeTaskContractAuthoringRequest.defaultSourceRevisionCapturePolicy
                .excludedDirectoryNames.joined(separator: ", ")
        draftPermittedImplementationIDs = ""
        draftDeliverableCollectionID = ""
        draftDeliverableExactCount = ""
        draftWorkerNetworkAccess = false
        nativeDesignBaselineImportInProgress = false
        nativeVerificationProbeImportInProgress = false
        pendingNativeDesignBaselineConfirmation = nil
        pendingNativeContractUserActor = nil
        pendingRatifiedNativeContract = nil
        pendingNativeEnrollmentRequestIdentity = nil
        adoptRecommendedCodexDefaults()
    }

    private func preparedWorkspace() throws -> URL {
        guard let path = draftWorkspacePath, !path.isEmpty, draftProjectMode != nil else {
            throw LoopForgeError.invalidWorkspace
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: path) else { throw LoopForgeError.invalidWorkspace }
        return url
    }
}
