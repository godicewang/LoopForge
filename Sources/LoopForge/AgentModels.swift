import Combine
import Foundation
import Security

enum AgentProviderKind: String, Codable, CaseIterable, Identifiable {
    case codex
    case local
    case api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .local: return "Local Deployment"
        case .api: return "API Connection"
        }
    }

    var symbol: String {
        switch self {
        case .codex: return "sparkles"
        case .local: return "desktopcomputer"
        case .api: return "network"
        }
    }
}

enum APIWireProtocol: String, Codable, CaseIterable, Identifiable {
    case automatic
    case responses
    case chatCompletions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Auto Detect"
        case .responses: return "Responses API"
        case .chatCompletions: return "Chat Completions"
        }
    }
}

enum APIProviderKind: String, Codable, CaseIterable, Identifiable {
    case qwen
    case zhipu
    case deepSeek
    case kimi
    case claude
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qwen: return "Qwen"
        case .zhipu: return "Zhipu · GLM"
        case .deepSeek: return "DeepSeek"
        case .kimi: return "Kimi"
        case .claude: return "Claude"
        case .custom: return "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .deepSeek: return "https://api.deepseek.com"
        case .kimi: return "https://api.moonshot.ai/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .custom: return ""
        }
    }

    var defaultProtocol: APIWireProtocol {
        switch self {
        case .qwen: return .automatic
        case .zhipu, .deepSeek, .kimi, .claude: return .chatCompletions
        case .custom: return .automatic
        }
    }

    var fallbackModels: [String] {
        switch self {
        case .qwen: return ["qwen3.7-max", "qwen3.7-plus", "qwen3.7-flash"]
        case .zhipu: return ["glm-5.2", "glm-5.1", "glm-5"]
        case .deepSeek: return ["deepseek-v4-pro", "deepseek-v4-flash"]
        case .kimi: return ["kimi-k3", "kimi-k2.7-code-highspeed", "kimi-k2.7-code", "kimi-k2.6"]
        case .claude: return ["claude-opus-5", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .custom: return []
        }
    }

    var defaultContextWindow: Int {
        switch self {
        case .qwen: return 1_000_000
        case .zhipu: return 204_800
        case .deepSeek: return 1_000_000
        case .kimi: return 1_000_000
        case .claude: return 1_000_000
        case .custom: return 128_000
        }
    }

    var supportsVisionByDefault: Bool {
        switch self {
        case .qwen, .kimi, .claude: return true
        case .zhipu, .deepSeek, .custom: return false
        }
    }

    var reasoningOptions: [String] {
        switch self {
        case .qwen, .zhipu, .deepSeek, .claude: return ["high"]
        case .kimi: return ["low", "high", "max"]
        case .custom: return []
        }
    }

    func acceptsRecentModel(_ modelID: String) -> Bool {
        let id = modelID.lowercased()
        guard !id.contains("embedding"), !id.contains("rerank"), !id.contains("audio"),
              !id.contains("image"), !id.contains("tts"), !id.contains("moderation") else {
            return false
        }
        switch self {
        case .qwen:
            return id.hasPrefix("qwen3.6") || id.hasPrefix("qwen3.7")
                || (4...9).contains(where: { id.hasPrefix("qwen\($0)") })
        case .zhipu:
            return (5...9).contains(where: { id.hasPrefix("glm-\($0)") })
        case .deepSeek:
            return (4...9).contains(where: { id.hasPrefix("deepseek-v\($0)") })
        case .kimi:
            return id.hasPrefix("kimi-k2.6") || id.hasPrefix("kimi-k2.7")
                || (3...9).contains(where: { id.hasPrefix("kimi-k\($0)") })
        case .claude:
            return id.hasPrefix("claude-") && (
                id.contains("-4-5") || id.contains("-4-6") || id.contains("-4-7")
                    || id.contains("-4-8") || id.contains("-4-9")
                    || id.hasPrefix("claude-opus-5")
                    || id.hasPrefix("claude-sonnet-5")
                    || id.hasPrefix("claude-haiku-5")
            )
        case .custom:
            return true
        }
    }

    func template() -> APIModelConnection {
        APIModelConnection(
            id: UUID(),
            name: title,
            baseURL: defaultBaseURL,
            model: fallbackModels.first ?? "",
            wireProtocol: defaultProtocol,
            reasoningOptions: reasoningOptions,
            contextWindow: defaultContextWindow,
            supportsVision: supportsVisionByDefault,
            providerKind: self,
            discoveredModels: fallbackModels,
            lastModelRefreshAt: nil
        )
    }
}

struct APIModelConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var model: String
    var wireProtocol: APIWireProtocol
    var reasoningOptions: [String]
    var contextWindow: Int
    var supportsVision: Bool
    var providerKind: APIProviderKind?
    var discoveredModels: [String]?
    var lastModelRefreshAt: Date?

    init(
        id: UUID,
        name: String,
        baseURL: String,
        model: String,
        wireProtocol: APIWireProtocol,
        reasoningOptions: [String],
        contextWindow: Int,
        supportsVision: Bool,
        providerKind: APIProviderKind? = nil,
        discoveredModels: [String]? = nil,
        lastModelRefreshAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.wireProtocol = wireProtocol
        self.reasoningOptions = reasoningOptions
        self.contextWindow = contextWindow
        self.supportsVision = supportsVision
        self.providerKind = providerKind
        self.discoveredModels = discoveredModels
        self.lastModelRefreshAt = lastModelRefreshAt
    }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n\t"))
    }

    var displayName: String { name.isEmpty ? model : name }

    var resourceLabel: String {
        let context: String
        if contextWindow >= 1_000_000 {
            let millions = Double(contextWindow) / 1_000_000
            context = millions == millions.rounded()
                ? "\(Int(millions))M"
                : String(format: "%.1fM", millions)
        } else {
            context = "\(max(1, contextWindow) / 1_024)K"
        }
        let bridge = wireProtocol == .chatCompletions ? " · Codex bridge" : ""
        return "\(wireProtocol.title)\(bridge) · \(context) context"
    }

    var resolvedProviderKind: APIProviderKind {
        if let providerKind { return providerKind }
        let lower = "\(name) \(baseURL)".lowercased()
        if lower.contains("dashscope") || lower.contains("qwen") { return .qwen }
        if lower.contains("bigmodel") || lower.contains("zhipu") || lower.contains("glm") { return .zhipu }
        if lower.contains("deepseek") { return .deepSeek }
        if lower.contains("moonshot") || lower.contains("kimi") { return .kimi }
        if lower.contains("anthropic") || lower.contains("claude") { return .claude }
        return .custom
    }

    var selectableModels: [String] {
        let candidates = (discoveredModels ?? []) + [model]
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static var deepSeekTemplate: APIModelConnection { APIProviderKind.deepSeek.template() }
    static var qwenTemplate: APIModelConnection { APIProviderKind.qwen.template() }
}

struct AgentSelection: Codable, Equatable {
    var provider: AgentProviderKind
    var modelID: String
    var displayName: String
    var reasoningEffort: String?
    var accessMode: CodexAccessMode
    var localProfile: ModelProfile?
    var apiConnection: APIModelConnection?

    var supportsVision: Bool {
        switch provider {
        case .codex: return true
        case .local: return localProfile?.supportsVision ?? false
        case .api: return apiConnection?.supportsVision ?? false
        }
    }

    var contextWindow: Int {
        switch provider {
        case .codex: return 0
        case .local: return localProfile?.contextWindow ?? 32_768
        case .api: return apiConnection?.contextWindow ?? 32_768
        }
    }

    var summary: String {
        "\(provider.title) · \(displayName)"
    }

    static func codex(model: String, displayName: String, reasoning: String?, access: CodexAccessMode) -> AgentSelection {
        AgentSelection(
            provider: .codex,
            modelID: model,
            displayName: displayName,
            reasoningEffort: reasoning,
            accessMode: access,
            localProfile: nil,
            apiConnection: nil
        )
    }

    static func local(profile: ModelProfile, reasoning: String? = nil, access: CodexAccessMode) -> AgentSelection {
        AgentSelection(
            provider: .local,
            modelID: profile.ollamaName,
            displayName: profile.displayName,
            reasoningEffort: reasoning,
            accessMode: access,
            localProfile: profile,
            apiConnection: nil
        )
    }

    static func api(connection: APIModelConnection, reasoning: String?, access: CodexAccessMode) -> AgentSelection {
        AgentSelection(
            provider: .api,
            modelID: connection.model,
            displayName: connection.displayName,
            reasoningEffort: reasoning,
            accessMode: access,
            localProfile: nil,
            apiConnection: connection
        )
    }
}

enum AgentRole: String {
    case control
    case subAgent

    var title: String { self == .control ? "Loop Control Agent" : "Sub Agent" }
}

struct AgentModelChoice: Identifiable, Equatable {
    let id: String
    let displayName: String
    let detail: String
    let reasoningOptions: [String]
    let supportsVision: Bool
    let supportsSubAgent: Bool
}

enum APIConnectionTestStatus: Equatable {
    case idle
    case testing
    case passed(protocolUsed: APIWireProtocol, message: String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Not tested"
        case .testing: return "Testing…"
        case .passed(let protocolUsed, _): return "Connected · \(protocolUsed.title)"
        case .failed: return "Connection failed"
        }
    }
}

enum APIModelDiscoveryStatus: Equatable {
    case idle
    case loading
    case loaded(count: Int, usedFallback: Bool)
    case failed(String)

    var title: String {
        switch self {
        case .idle: return ""
        case .loading: return "Loading the provider model catalog…"
        case .loaded(let count, let usedFallback):
            return usedFallback ? "\(count) current recommended models" : "\(count) models loaded from the provider"
        case .failed(let message): return message
        }
    }
}

struct APIModelDiscoveryResult: Equatable {
    let models: [String]
    let usedFallback: Bool
}

enum APIKeyVault {
    static let service = "com.loopforge.api-connections"

    static func kernelCredentialReference(
        for id: UUID
    ) -> KernelProviderCredentialReference {
        KernelProviderCredentialReference(
            source: .macOSKeychainGenericPassword,
            service: service,
            account: id.uuidString
        )
    }

    static func set(_ key: String, for id: UUID) throws {
        let account = id.uuidString
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LoopForgeError.runtimeUnavailable("The API key could not be stored securely (Keychain status \(status)).")
        }
    }

    static func get(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AgentCatalog: ObservableObject {
    @Published private(set) var apiConnections: [APIModelConnection] = []
    @Published private(set) var customLocalModels: [ModelProfile] = []
    @Published private(set) var installedLocalNames: Set<String> = []
    @Published private(set) var verifiedLocalNames: Set<String> = []
    @Published private(set) var localValidationErrors: [String: String] = [:]
    @Published private(set) var checkingLocalModelID: String?
    @Published private(set) var downloadingLocalModelID: String?
    @Published var localStatus = ""
    @Published var downloadProgress = ""
    @Published var apiTestStatus: APIConnectionTestStatus = .idle
    @Published var apiDiscoveryStatus: APIModelDiscoveryStatus = .idle

    private struct PersistedCatalog: Codable {
        var apiConnections: [APIModelConnection]
        var customLocalModels: [ModelProfile]
        var verifiedLocalDigests: [String: String]?
    }

    private let storageURL: URL
    private let ollama = OllamaManager()
    private var verifiedLocalDigests: [String: String] = [:]

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? TaskStore.applicationSupportDirectory().appendingPathComponent("agent-models.json")
        load()
    }

    var localModels: [ModelProfile] {
        var seen = Set<String>()
        return (ModelProfile.all + customLocalModels).filter { seen.insert($0.ollamaName).inserted }
    }

    func localProfile(idOrName: String) -> ModelProfile? {
        localModels.first { $0.id == idOrName || $0.ollamaName == idOrName }
    }

    func isLocalModelInstalled(_ profile: ModelProfile) -> Bool {
        let requested = normalizedLocalModelName(profile.ollamaName)
        return installedLocalNames.contains {
            normalizedLocalModelName($0) == requested
        }
    }

    func isLocalModelReady(_ profile: ModelProfile) -> Bool {
        verifiedLocalNames.contains(profile.ollamaName)
    }

    func apiConnection(id: UUID?) -> APIModelConnection? {
        guard let id else { return nil }
        return apiConnections.first { $0.id == id }
    }

    func saveAPIConnection(_ connection: APIModelConnection, apiKey: String?) throws {
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedKey.isEmpty { try APIKeyVault.set(trimmedKey, for: connection.id) }
        if let index = apiConnections.firstIndex(where: { $0.id == connection.id }) {
            apiConnections[index] = connection
        } else {
            apiConnections.append(connection)
        }
        persist()
    }

    func deleteAPIConnection(_ connection: APIModelConnection) {
        APIKeyVault.delete(for: connection.id)
        apiConnections.removeAll { $0.id == connection.id }
        persist()
    }

    func addCustomLocalModel(
        displayName: String,
        ollamaName: String,
        estimatedMemoryGB: Double,
        contextWindow: Int,
        supportsVision: Bool
    ) {
        let normalized = ollamaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let profile = ModelProfile(
            id: "custom-\(normalized.lowercased().replacingOccurrences(of: "/", with: "-"))",
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalized : displayName,
            ollamaName: normalized,
            downloadSizeGB: max(1, estimatedMemoryGB * 0.72),
            activeParameters: "User-configured local model",
            contextWindow: max(2_048, contextWindow),
            reason: "A user-added Ollama model available to either LoopForge agent.",
            estimatedMemoryGBOverride: max(1, estimatedMemoryGB),
            supportsVisionOverride: supportsVision
        )
        customLocalModels.removeAll { $0.ollamaName == profile.ollamaName }
        customLocalModels.append(profile)
        persist()
    }

    func refreshInstalledModels() async {
        if !(await ollama.healthCheck()) {
            do {
                try await ollama.ensureReady(contextWindow: 32_768) { message in
                    Task { @MainActor in self.localStatus = sanitizedLogText(message) }
                }
            } catch {
                localStatus = "Ollama could not start: \(sanitizedLogText(error.localizedDescription).prefix(180))"
                return
            }
        }
        guard let url = URL(string: "http://\(AppConstants.ollamaHost)/api/tags") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                localStatus = "Ollama is not reachable."
                return
            }
            struct Tags: Decodable {
                struct Item: Decodable {
                    let name: String
                    let digest: String?
                }
                let models: [Item]
            }
            let tags = try JSONDecoder().decode(Tags.self, from: data)
            installedLocalNames = Set(tags.models.map(\.name))
            verifiedLocalNames = []
            localValidationErrors = [:]
            let installedDigests = tags.models.reduce(into: [String: String]()) { result, item in
                if let digest = item.digest {
                    result[normalizedLocalModelName(item.name)] = digest
                }
            }
            for profile in localModels where isLocalModelInstalled(profile) {
                do {
                    try await ollama.validateInstalledMetadata(profile)
                    let expected = verifiedLocalDigests[profile.ollamaName]
                    let installed = installedDigests[normalizedLocalModelName(profile.ollamaName)]
                    if expected != nil, expected == installed {
                        verifiedLocalNames.insert(profile.ollamaName)
                    } else {
                        localValidationErrors[profile.ollamaName] = "Installed · response check required"
                    }
                } catch {
                    localValidationErrors[profile.ollamaName] = sanitizedLogText(error.localizedDescription)
                }
            }
            let ready = verifiedLocalNames.count
            let pending = localModels.filter {
                isLocalModelInstalled($0) && !isLocalModelReady($0)
            }.count
            localStatus = pending == 0
                ? "\(ready) verified local model\(ready == 1 ? "" : "s")"
                : "\(ready) verified · \(pending) needs a response check"
        } catch {
            localStatus = "Ollama discovery failed: \(sanitizedLogText(error.localizedDescription).prefix(180))"
        }
    }

    func prepareLocalModelDownload(_ profile: ModelProfile) async throws -> LocalModelDownloadPlan {
        checkingLocalModelID = profile.id
        downloadProgress = "Checking \(profile.displayName) with Ollama Registry…"
        defer { checkingLocalModelID = nil }
        do {
            let plan = try await ollama.prepareDownload(profile)
            downloadProgress = "\(profile.displayName) verified in Ollama Registry · \(plan.sizeLabel)"
            return plan
        } catch {
            downloadProgress = sanitizedLogText(error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    func downloadLocalModel(_ plan: LocalModelDownloadPlan) async -> Bool {
        let profile = plan.profile
        downloadingLocalModelID = profile.id
        downloadProgress = "Preparing \(profile.displayName)…"
        defer { downloadingLocalModelID = nil }
        do {
            try await ollama.ensureReady(contextWindow: profile.contextWindow) { message in
                Task { @MainActor in self.downloadProgress = sanitizedLogText(message) }
            }
            let digest = try await ollama.downloadVerifiedModel(plan) { message in
                Task { @MainActor in self.downloadProgress = sanitizedLogText(message) }
            }
            verifiedLocalDigests[profile.ollamaName] = digest
            persist()
            await refreshInstalledModels()
            downloadProgress = "\(profile.displayName) passed its local response check and is ready."
            return true
        } catch {
            downloadProgress = sanitizedLogText(error.localizedDescription)
            localValidationErrors[profile.ollamaName] = downloadProgress
            verifiedLocalNames.remove(profile.ollamaName)
            return false
        }
    }

    @discardableResult
    func verifyInstalledLocalModel(_ profile: ModelProfile) async -> Bool {
        checkingLocalModelID = profile.id
        downloadProgress = "Running a local response check for \(profile.displayName)…"
        defer { checkingLocalModelID = nil }
        do {
            try await ollama.ensureReady(contextWindow: profile.contextWindow) { message in
                Task { @MainActor in self.downloadProgress = sanitizedLogText(message) }
            }
            try await ollama.validateInstalledMetadata(profile)
            try await ollama.smokeTestInstalledModel(profile)
            guard let digest = await ollama.installedDigest(for: profile.ollamaName) else {
                throw LoopForgeError.runtimeUnavailable("The installed model digest could not be read.")
            }
            verifiedLocalDigests[profile.ollamaName] = digest
            verifiedLocalNames.insert(profile.ollamaName)
            localValidationErrors.removeValue(forKey: profile.ollamaName)
            persist()
            downloadProgress = "\(profile.displayName) passed its local response check and is ready."
            return true
        } catch {
            downloadProgress = sanitizedLogText(error.localizedDescription)
            localValidationErrors[profile.ollamaName] = downloadProgress
            verifiedLocalNames.remove(profile.ollamaName)
            return false
        }
    }

    func testAPIConnection(_ connection: APIModelConnection, apiKey: String?) async -> APIConnectionTestStatus {
        let supplied = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = supplied.isEmpty ? APIKeyVault.get(for: connection.id) : supplied
        guard let key, !key.isEmpty else {
            let result = APIConnectionTestStatus.failed("Enter an API key. It will be stored in macOS Keychain.")
            apiTestStatus = result
            return result
        }
        apiTestStatus = .testing
        do {
            let result = try await OpenAICompatibleClient().probe(connection: connection, apiKey: key)
            apiTestStatus = .passed(protocolUsed: result.protocolUsed, message: result.message)
        } catch {
            apiTestStatus = .failed(sanitizedLogText(error.localizedDescription))
        }
        return apiTestStatus
    }

    func discoverAPIModels(
        provider: APIProviderKind,
        baseURL: String,
        apiKey: String?
    ) async -> APIModelDiscoveryResult {
        apiDiscoveryStatus = .loading
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let probe = APIModelConnection(
            id: UUID(),
            name: provider.title,
            baseURL: baseURL,
            model: provider.fallbackModels.first ?? "",
            wireProtocol: provider.defaultProtocol,
            reasoningOptions: provider.reasoningOptions,
            contextWindow: provider.defaultContextWindow,
            supportsVision: provider.supportsVisionByDefault,
            providerKind: provider
        )
        if !key.isEmpty {
            do {
                let models = try await OpenAICompatibleClient().listModels(connection: probe, apiKey: key)
                let recent = models.filter(provider.acceptsRecentModel)
                if !recent.isEmpty {
                    apiDiscoveryStatus = .loaded(count: recent.count, usedFallback: false)
                    return APIModelDiscoveryResult(models: recent, usedFallback: false)
                }
            } catch {
                if provider == .custom {
                    apiDiscoveryStatus = .failed(sanitizedLogText(error.localizedDescription))
                    return APIModelDiscoveryResult(models: [], usedFallback: false)
                }
            }
        }
        let fallback = provider.fallbackModels
        apiDiscoveryStatus = .loaded(count: fallback.count, usedFallback: true)
        return APIModelDiscoveryResult(models: fallback, usedFallback: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let persisted = try? JSONDecoder.loopForge.decode(PersistedCatalog.self, from: data) else { return }
        apiConnections = persisted.apiConnections
        customLocalModels = persisted.customLocalModels
        verifiedLocalDigests = persisted.verifiedLocalDigests ?? [:]
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.loopForge.encode(PersistedCatalog(
                apiConnections: apiConnections,
                customLocalModels: customLocalModels,
                verifiedLocalDigests: verifiedLocalDigests
            ))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            localStatus = "Model settings could not be saved."
        }
    }

    private func normalizedLocalModelName(_ name: String) -> String {
        name.hasSuffix(":latest") ? String(name.dropLast(7)) : name
    }
}
