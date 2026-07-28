import Foundation

struct LocalModelDownloadPlan: Equatable, Identifiable {
    let profile: ModelProfile
    let downloadBytes: Int64
    let modelLayerDigest: String
    let verifiedAt: Date

    var id: String { profile.id }
    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: downloadBytes, countStyle: .file)
    }
}

struct OllamaRegistryClient {
    private struct Manifest: Decodable {
        struct Layer: Decodable {
            let mediaType: String
            let digest: String
            let size: Int64
        }
        let layers: [Layer]
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func downloadPlan(for profile: ModelProfile) async throws -> LocalModelDownloadPlan {
        let reference = try registryReference(for: profile.ollamaName)
        var url = URL(string: "https://registry.ollama.ai/v2")!
        for component in reference.repository.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        url.appendPathComponent("manifests")
        url.appendPathComponent(reference.tag)

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "application/vnd.docker.distribution.manifest.v2+json",
            forHTTPHeaderField: "Accept"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw LoopForgeError.runtimeUnavailable(
                "Ollama Registry could not verify \(profile.ollamaName) (HTTP \(code)). No download was started."
            )
        }

        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        let total = manifest.layers.reduce(Int64(0)) { partial, layer in
            partial.addingReportingOverflow(layer.size).overflow ? Int64.max : partial + layer.size
        }
        guard total > 100_000_000,
              let modelLayer = manifest.layers.first(where: {
                  $0.mediaType.contains("model") && !$0.digest.isEmpty
              }) else {
            throw LoopForgeError.runtimeUnavailable(
                "Ollama Registry returned an incomplete manifest for \(profile.ollamaName). No download was started."
            )
        }
        return LocalModelDownloadPlan(
            profile: profile,
            downloadBytes: total,
            modelLayerDigest: modelLayer.digest,
            verifiedAt: Date()
        )
    }

    private func registryReference(for model: String) throws -> (repository: String, tag: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*(?::[A-Za-z0-9][A-Za-z0-9._-]*)?$"#, options: .regularExpression) != nil
        else {
            throw LoopForgeError.runtimeUnavailable("The Ollama model name is invalid.")
        }

        let lastSlash = trimmed.lastIndex(of: "/")
        let lastColon = trimmed.lastIndex(of: ":")
        let hasTag = lastColon.map { colon in
            lastSlash.map { colon > $0 } ?? true
        } ?? false
        let repositoryName: String
        let tag: String
        if hasTag, let lastColon {
            repositoryName = String(trimmed[..<lastColon])
            tag = String(trimmed[trimmed.index(after: lastColon)...])
        } else {
            repositoryName = trimmed
            tag = "latest"
        }
        let repository = repositoryName.contains("/") ? repositoryName : "library/\(repositoryName)"
        return (repository, tag)
    }
}

final class OllamaManager {
    private let runner = ProcessRunner()
    private let registry: OllamaRegistryClient
    private var serverProcess: Process?
    private var serverOwnedByApp = false

    init(registry: OllamaRegistryClient = OllamaRegistryClient()) {
        self.registry = registry
    }

    deinit { stopOwnedServer() }

    func ensureReady(contextWindow: Int, onLog: @escaping (String) -> Void) async throws {
        if await healthCheck() {
            onLog("Connected to the local Ollama service")
            return
        }
        guard let executable = ollamaExecutable else { throw LoopForgeError.executableMissing("Ollama") }
        let models = TaskStore.applicationSupportDirectory().appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.environment = runtimeEnvironment(contextWindow: contextWindow)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            let clean = sanitizedLogText(text)
            if !clean.isEmpty && (clean.contains("error") || clean.contains("listening")) { onLog(clean) }
        }
        process.terminationHandler = { _ in pipe.fileHandleForReading.readabilityHandler = nil }
        try process.run()
        serverProcess = process
        serverOwnedByApp = true

        for _ in 0..<50 {
            if await healthCheck() {
                onLog("Bundled Ollama started with one loaded model and one parallel request to protect unified memory")
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        stopOwnedServer()
        throw LoopForgeError.runtimeUnavailable("The local Ollama inference service timed out while starting.")
    }

    func requireInstalledModel(_ profile: ModelProfile, onProgress: @escaping (String) -> Void = { _ in }) async throws {
        if await hasModel(profile.ollamaName) {
            try await validateInstalledMetadata(profile)
            onProgress("Model ready: \(profile.displayName)")
            return
        }
        throw LoopForgeError.runtimeUnavailable(
            "\(profile.displayName) is not downloaded. Choose Local Deployment, review its size, and confirm the download before starting."
        )
    }

    func prepareDownload(_ profile: ModelProfile) async throws -> LocalModelDownloadPlan {
        let plan = try await registry.downloadPlan(for: profile)
        let available = availableDiskSpaceGB()
        let required = Double(plan.downloadBytes) / 1_073_741_824 + 6
        guard available >= required else {
            throw LoopForgeError.insufficientDiskSpace(requiredGB: required, availableGB: available)
        }
        return plan
    }

    func downloadVerifiedModel(
        _ plan: LocalModelDownloadPlan,
        onProgress: @escaping (String) -> Void
    ) async throws -> String {
        let refreshed = try await prepareDownload(plan.profile)
        guard refreshed.modelLayerDigest == plan.modelLayerDigest else {
            throw LoopForgeError.runtimeUnavailable(
                "\(plan.profile.displayName) changed in the registry after confirmation. Review the new size and confirm again."
            )
        }
        guard let executable = ollamaExecutable else { throw LoopForgeError.executableMissing("Ollama") }
        if !(await hasModel(plan.profile.ollamaName)) {
            onProgress("Downloading \(plan.profile.displayName) · \(refreshed.sizeLabel)")
            let result = try await runner.run(
                executable: executable,
                arguments: ["pull", plan.profile.ollamaName],
                environment: runtimeEnvironment(contextWindow: plan.profile.contextWindow),
                currentDirectory: executable.deletingLastPathComponent(),
                onStdout: onProgress,
                onStderr: onProgress
            )
            guard result.exitCode == 0 else {
                throw LoopForgeError.processFailed("ollama pull", result.exitCode, result.stderr.suffixText(800))
            }
        }
        guard await hasModel(plan.profile.ollamaName) else {
            throw LoopForgeError.runtimeUnavailable(
                "The download finished, but \(plan.profile.ollamaName) was not reported by the local service."
            )
        }
        onProgress("Validating tools and running a local response check…")
        try await validateInstalledMetadata(plan.profile)
        try await smokeTestInstalledModel(plan.profile)
        guard let digest = await installedDigest(for: plan.profile.ollamaName), !digest.isEmpty else {
            throw LoopForgeError.runtimeUnavailable(
                "\(plan.profile.displayName) responded, but its installed digest could not be verified."
            )
        }
        return digest
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "http://\(AppConstants.ollamaHost)/api/version") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    func hasModel(_ name: String) async -> Bool {
        guard let url = URL(string: "http://\(AppConstants.ollamaHost)/api/tags") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = object["models"] as? [[String: Any]] else { return false }
            let requested = normalizedModelName(name)
            return models.contains { model in
                guard let modelName = (model["name"] ?? model["model"]) as? String else { return false }
                return normalizedModelName(modelName) == requested
            }
        } catch { return false }
    }

    func installedDigest(for name: String) async -> String? {
        guard let url = URL(string: "http://\(AppConstants.ollamaHost)/api/tags") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = object["models"] as? [[String: Any]] else { return nil }
            let requested = normalizedModelName(name)
            return models.first { model in
                guard let modelName = (model["name"] ?? model["model"]) as? String else { return false }
                return normalizedModelName(modelName) == requested
            }?["digest"] as? String
        } catch {
            return nil
        }
    }

    func validateInstalledMetadata(_ profile: ModelProfile) async throws {
        guard let url = URL(string: "http://\(AppConstants.ollamaHost)/api/show") else {
            throw LoopForgeError.runtimeUnavailable("The local model service URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": profile.ollamaName,
            "verbose": false
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LoopForgeError.runtimeUnavailable(
                "\(profile.displayName) is installed but Ollama could not inspect it."
            )
        }
        let capabilities = Set((object["capabilities"] as? [String] ?? []).map { $0.lowercased() })
        let missing = profile.requiredOllamaCapabilities.subtracting(capabilities).sorted()
        guard missing.isEmpty else {
            throw LoopForgeError.runtimeUnavailable(
                "\(profile.displayName) is missing required Ollama capabilities: \(missing.joined(separator: ", "))."
            )
        }
    }

    func smokeTestInstalledModel(_ profile: ModelProfile) async throws {
        guard let url = URL(string: "http://\(AppConstants.ollamaHost)/api/chat") else {
            throw LoopForgeError.runtimeUnavailable("The local model service URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": profile.ollamaName,
            "messages": [[
                "role": "user",
                "content": "Reply with the single word READY."
            ]],
            "stream": false,
            "think": false,
            "keep_alive": 0,
            "options": [
                "num_ctx": min(profile.contextWindow, 4_096),
                "num_predict": 24,
                "temperature": 0
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["done"] as? Bool == true,
              let message = object["message"] as? [String: Any]
        else {
            let detail = sanitizedLogText(String(data: data, encoding: .utf8) ?? "")
            throw LoopForgeError.runtimeUnavailable(
                "\(profile.displayName) downloaded but failed its local response check. \(detail.prefix(240))"
            )
        }
        let content = (message["content"] as? String ?? "")
            + (message["thinking"] as? String ?? "")
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LoopForgeError.runtimeUnavailable(
                "\(profile.displayName) downloaded but returned an empty local response."
            )
        }
    }

    func stopOwnedServer() {
        guard serverOwnedByApp, let process = serverProcess, process.isRunning else { return }
        process.terminate()
        serverProcess = nil
        serverOwnedByApp = false
    }

    private var ollamaExecutable: URL? {
        PathResolver.executable(named: "ollama", fallbacks: [
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama"
        ])
    }

    private func runtimeEnvironment(contextWindow: Int) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = AppConstants.ollamaHost
        environment["OLLAMA_MODELS"] = TaskStore.applicationSupportDirectory().appendingPathComponent("Models").path
        environment["OLLAMA_KEEP_ALIVE"] = "5m"
        environment["OLLAMA_MAX_LOADED_MODELS"] = "1"
        environment["OLLAMA_NUM_PARALLEL"] = "1"
        environment["OLLAMA_CONTEXT_LENGTH"] = String(min(contextWindow, 65_536))
        environment["OLLAMA_NOHISTORY"] = "1"
        environment["OLLAMA_NO_CLOUD"] = "1"
        if let executable = ollamaExecutable {
            environment["OLLAMA_RUNNERS_DIR"] = executable.deletingLastPathComponent().path
            let currentPath = environment["PATH"] ?? ""
            environment["PATH"] = executable.deletingLastPathComponent().path + ":" + currentPath
        }
        return environment
    }

    private func normalizedModelName(_ name: String) -> String {
        name.hasSuffix(":latest") ? String(name.dropLast(7)) : name
    }

    func availableDiskSpaceGB() -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824
    }
}

private extension String {
    func suffixText(_ count: Int) -> String { String(suffix(count)) }
}
