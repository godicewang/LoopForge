import AppKit
import Combine
import Foundation

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
    @Published var draftExecutionMode: LoopExecutionMode = .singleLoop {
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
    @Published var draftAccessMode: CodexAccessMode = .fullAccess
    @Published var draftLocalModelID = ModelProfile.advancedVisualAuditor.id
    @Published var draftControlProvider: AgentProviderKind = .codex
    @Published var draftControlModelReference = AppConstants.officialWorkerModel
    @Published var draftControlReasoningEffort = "ultra"
    @Published var draftControlAccessMode: CodexAccessMode = .fullAccess
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

    let store: TaskStore
    let controller: LoopController
    let watcherStore: WatcherStore
    let watcherController: WatcherController
    let codexConnection: CodexConnectionManager
    let permissionCenter: PermissionCenter
    let agentCatalog: AgentCatalog
    private let estimator = TaskEstimator()
    private let promptOptimizer = PromptOptimizer()
    private var cancellables = Set<AnyCancellable>()
    private var pendingOriginalPromptForTask: String?
    private var pendingPromptOptimizationSource: String?
    private var watcherAgentWasCustomized = false

    init(
        store: TaskStore? = nil,
        codexConnection: CodexConnectionManager? = nil,
        permissionCenter: PermissionCenter? = nil,
        agentCatalog: AgentCatalog? = nil
    ) {
        let actualStore = store ?? TaskStore()
        let actualPermissionCenter = permissionCenter ?? PermissionCenter()
        let actualAgentCatalog = agentCatalog ?? AgentCatalog()
        let actualCodexConnection = codexConnection ?? CodexConnectionManager()
        let actualWatcherStore = WatcherStore()
        self.selectedModule = LoopForgeModule(
            rawValue: UserDefaults.standard.string(forKey: "LoopForge.SelectedModule") ?? ""
        ) ?? .autoLoop
        self.store = actualStore
        self.controller = LoopController(
            store: actualStore,
            permissionCenter: actualPermissionCenter,
            agentCatalog: actualAgentCatalog
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
        refreshIncompleteGraphReportsIfNeeded()
    }

    private func refreshIncompleteGraphReportsIfNeeded() {
        let auditor = WorkspaceAuditor()
        let generator = CompletionReportGenerator()
        for task in store.tasks where task.status == .completed
            && task.resolvedExecutionMode == .autoGraph {
            guard let path = task.completionReportPath,
                  let document = try? String(contentsOfFile: path, encoding: .utf8),
                  !document.contains("data-loopforge-report-schema=\"2\""),
                  !document.contains("data-loopforge-report-schema=\"3\""),
                  document.contains(
                    "<h2>Verification runs</h2><ul><li>No verified item is available yet.</li>"
                  ) else { continue }
            let graphLogs = task.graphState?.nodes.flatMap(\.logs) ?? []
            guard graphLogs.contains(where: { $0.kind == .command }) else { continue }

            var reportTask = task
            reportTask.reportGenerationProvider =
                "Deterministic evidence fallback · refreshed from retained graph evidence"
            let reportLogs = (task.logs + graphLogs).sorted { $0.timestamp < $1.timestamp }
            let audit = auditor.audit(task: reportTask)
            let snapshot = auditor.snapshot(
                workspacePath: reportTask.workspacePath,
                logs: reportLogs
            )
            guard let refreshedPath = try? generator.generate(
                task: reportTask,
                audit: audit,
                snapshot: snapshot,
                narrative: nil,
                isFinal: true
            ) else { continue }
            store.update(id: task.id) {
                $0.completionReportPath = refreshedPath
                $0.reportGeneratedAt = Date()
                $0.reportGenerationProvider = reportTask.reportGenerationProvider
            }
            store.appendLog(
                id: task.id,
                kind: .audit,
                "Refreshed the graph delivery report so node-level commands and verification evidence are visible."
            )
        }
    }

    var selectedLocalModel: ModelProfile {
        ModelProfile.profile(id: draftLocalModelID) ?? estimate?.model ?? .advancedVisualAuditor
    }

    func beginStartup() {
        permissionCenter.beginOnboarding()
        watcherController.beginStartup()
        if permissionCenter.isReady {
            codexConnection.start()
            resumeInterruptedTaskIfNeeded()
        }
    }

    func permissionStateChanged() {
        permissionCenter.refresh()
        if permissionCenter.isReady {
            codexConnection.start()
            resumeInterruptedTaskIfNeeded()
        }
    }

    func connectionStateChanged() {
        guard codexConnection.phase == .ready else { return }
        if draftProjectMode == nil { adoptRecommendedCodexDefaults() }
        if !watcherAgentWasCustomized { adoptRecommendedWatcherCodexDefault() }
        resumeInterruptedTaskIfNeeded()
    }

    func resumeInterruptedTaskIfNeeded() {
        guard permissionCenter.isReady, controller.runningTaskID == nil,
              let recovered = store.tasks.first(where: {
                  $0.resumeOnNextLaunch == true
                      && $0.canResume
                      && ($0.externalBlockerKind != .automationPermission || permissionCenter.requirementsSatisfied(for: $0))
              }) else { return }
        let needsCodex = recovered.resolvedControlAgent.provider == .codex
            || recovered.resolvedSubAgent.provider == .codex
        guard !needsCodex || codexConnection.isConnected else { return }
        store.selectedTaskID = recovered.id
        showingNewTask = false
        store.appendLog(id: recovered.id, kind: .system, "Permissions and official Codex are ready. LoopForge is automatically continuing from the last durable checkpoint.")
        controller.start(taskID: recovered.id)
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
        draftControlAccessMode = .fullAccess
        draftSubProvider = .codex
        draftSubModelReference = recommended.slug
        draftReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
        draftAccessMode = .fullAccess
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
                access: .fullAccess
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
                access: .fullAccess
            )
        case .local:
            guard let profile = agentCatalog.localProfile(
                idOrName: watcherDraftModelReference
            ), agentCatalog.isLocalModelReady(profile) else { return nil }
            return .local(
                profile: profile,
                reasoning: reasoning.isEmpty ? nil : reasoning,
                access: .fullAccess
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
        present(panel) { [weak self] url in
            self?.draftWorkspacePath = url.path
            self?.draftProjectMode = .existing
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
            draftControlAccessMode = .fullAccess
            draftSubProvider = .codex
            draftSubModelReference = recommended.slug
            draftOfficialModel = recommended.slug
            draftReasoningEffort = CodexCatalog.strongestReasoning(for: recommended)
            draftAccessMode = .fullAccess
        }
    }

    func qualityChanged() {
        if draftExecutionMode == .autoGraph {
            draftExecutionMode = .singleLoop
        }
        if estimate != nil { calculateEstimate() }
        else { draftTargetMinutes = max(draftTargetMinutes, draftQuality.defaultRuntimeMinutes) }
    }

    func selectAutoGraphLoop() {
        draftExecutionMode = .autoGraph
        if estimate != nil { calculateEstimate() }
    }

    func selectSingleLoop() {
        draftExecutionMode = .singleLoop
        if estimate != nil { calculateEstimate() }
    }

    func setParallelCandidatesEnabled(_ enabled: Bool) {
        draftExecutionMode = enabled ? .parallelCandidates : .singleLoop
        if estimate != nil { calculateEstimate() }
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
        pendingOriginalPromptForTask = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingPromptOptimizationSource = "Original prompt selected by user"
        createAndStart()
    }

    func beginPromptOptimization() {
        showingPromptOptimizationOffer = false
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
        let original = pendingOriginalPromptForTask
            ?? draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingOriginalPromptForTask = original
        pendingPromptOptimizationSource = "\(promptOptimizationProvider) · \(candidate.title)"
        showingPromptOptimization = false
        let confirmedMinutes = draftTargetMinutes
        draftRequest = candidate.prompt
        calculateEstimate()
        draftTargetMinutes = confirmedMinutes
        createAndStart()
    }

    func cancelPromptOptimization() {
        showingPromptOptimization = false
        promptOptimizationPhase = .idle
        promptOptimizationCandidates = []
        promptOptimizationProvider = ""
    }

    private func promptOptimizationTask() -> LoopTask? {
        guard let estimate,
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

    func createAndStart() {
        let needsCodex = selectedAgent(for: .control)?.provider == .codex
            || selectedAgent(for: .subAgent)?.provider == .codex
        guard !needsCodex || codexConnection.isConnected else {
            codexConnection.presentStatus()
            alertMessage = "Reconnect Codex before starting this loop."
            return
        }
        guard controller.runningTaskID == nil else {
            alertMessage = "Pause the active task before starting another so local model memory does not stack."
            return
        }
        if estimate == nil { calculateEstimate() }
        guard let estimate else { return }
        guard let controlAgent = selectedAgent(for: .control),
              let subAgent = selectedAgent(for: .subAgent) else {
            alertMessage = "Choose a configured model for both agents."
            return
        }
        for (role, agent) in [(AgentRole.control, controlAgent), (.subAgent, subAgent)]
        where agent.provider == .local {
            guard let profile = agent.localProfile, agentCatalog.isLocalModelReady(profile) else {
                modelManagerRequestedRole = role
                showingModelManager = true
                return
            }
        }
        guard !estimate.visualAuditRequired || controlAgent.supportsVision else {
            draftControlProvider = .local
            draftControlModelReference = ModelProfile.advancedVisualAuditor.id
            draftLocalModelID = ModelProfile.advancedVisualAuditor.id
            modelManagerRequestedRole = .control
            showingModelManager = true
            return
        }
        if draftExecutionMode == .parallelCandidates,
           estimate.category == .desktopAutomation {
            alertMessage = "Parallel Candidates cannot safely share one signed-in browser or desktop-app session. Use Auto Graph Loop or Single Loop for this interactive task."
            return
        }
        guard draftExecutionMode == .autoGraph
            || draftTargetMinutes >= AppConstants.minimumCustomRuntimeMinutes else {
            draftTargetMinutes = AppConstants.minimumCustomRuntimeMinutes
            alertMessage = "Choose at least \(TimeInterval(AppConstants.minimumCustomRuntimeMinutes * 60).compactDuration) of active Sub Agent work."
            return
        }
        let request = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let workspace = try preparedWorkspace()
            let now = Date()
            let task = LoopTask(
                id: UUID(), title: safeProjectName(from: request), request: request,
                quality: draftQuality, category: estimate.category, workspacePath: workspace.path,
                targetSeconds: draftExecutionMode == .autoGraph ? 0 : TimeInterval(draftTargetMinutes * 60),
                accumulatedCodexSeconds: 0,
                model: selectedLocalModel, status: .preparing, stage: "Waiting to start", iteration: 0,
                threadID: nil, auditScore: 0, auditSummary: "Not audited yet", lastAgentMessage: "",
                consecutiveFailures: 0, createdAt: now, updatedAt: now, completedAt: nil,
                logs: [
                    TaskLogEntry(kind: .system, message: "Confirmed: \(estimate.explanation)"),
                    TaskLogEntry(kind: .system, message: "Project mode: \(draftProjectMode?.title ?? "Unknown"). Workspace: \(workspace.path)"),
                    TaskLogEntry(kind: .system, message: {
                        switch draftExecutionMode {
                        case .autoGraph:
                            return "Execution mode: Auto Graph Loop. Node loops have no artificial minimum runtime; completion requires node-level and whole-graph evidence audits."
                        case .parallelCandidates:
                            return "Execution mode: \(draftParallelCandidateCount) isolated parallel candidates. Each candidate must complete \(TimeInterval(draftTargetMinutes * 60).compactDuration) of successful active work and pass an independent review; \(draftParallelSelectionMode.title.lowercased()) the one result retained."
                        case .singleLoop:
                            return "User-confirmed hard active Sub Agent runtime: \(TimeInterval(draftTargetMinutes * 60).compactDuration)."
                        }
                    }()),
                    TaskLogEntry(
                        kind: .system,
                        message: estimate.category == .desktopAutomation
                            ? "Interactive-surface contract: use the user's named, already signed-in browser or desktop app directly. Never replace it with an API, Selenium/WebDriver, a different model, or a generated automation project unless the user explicitly requests that substitution."
                            : "Execution contract confirmed for the selected project category."
                    )
                ],
                visualAuditRequired: estimate.visualAuditRequired,
                officialModel: draftOfficialModel,
                officialReasoningEffort: draftReasoningEffort,
                codexAccessMode: draftAccessMode,
                resumeOnNextLaunch: true,
                checkpointedAt: now,
                controlInteractionCount: 0
            )
            var configuredTask = task
            configuredTask.executionMode = draftExecutionMode
            if draftExecutionMode == .parallelCandidates {
                configuredTask.parallelCandidateCount = ParallelCandidatePolicy.normalizedCount(
                    draftParallelCandidateCount
                )
                configuredTask.parallelSelectionMode = draftParallelSelectionMode
            }
            configuredTask.controlAgent = controlAgent
            configuredTask.subAgent = subAgent
            configuredTask.originalRequest = pendingOriginalPromptForTask ?? request
            configuredTask.promptOptimizationSource = pendingPromptOptimizationSource
            configuredTask.shortTitle = TaskNamePolicy.descriptiveSummary(
                request: configuredTask.originalRequest ?? request,
                fallback: configuredTask.title
            )
            configuredTask.taskNamingVersion = TaskNamePolicy.currentVersion
            configuredTask.taskNamingCompleted = false
            let baselineSnapshot = WorkspaceAuditor().snapshot(
                workspacePath: configuredTask.workspacePath,
                logs: []
            )
            configuredTask.reportBaseline = TaskNamePolicy.baseline(from: baselineSnapshot, at: now)
            if let local = controlAgent.localProfile { configuredTask.model = local }
            store.add(configuredTask)
            showingNewTask = false
            controller.start(taskID: configuredTask.id)
            resetDraft()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func resume(_ task: LoopTask) { controller.start(taskID: task.id) }
    func chooseParallelCandidate(_ task: LoopTask, candidateID: String) {
        guard controller.runningTaskID == nil else {
            alertMessage = "Pause the active task before applying a parallel candidate."
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
        draftExecutionMode = .singleLoop
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
        draftControlAccessMode = .fullAccess
        modelManagerRequestedRole = nil
        showingPromptOptimizationOffer = false
        showingPromptOptimization = false
        promptOptimizationPhase = .idle
        promptOptimizationCandidates = []
        promptOptimizationProvider = ""
        pendingOriginalPromptForTask = nil
        pendingPromptOptimizationSource = nil
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
