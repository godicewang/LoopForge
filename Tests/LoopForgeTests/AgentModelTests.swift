import Foundation
import Network
import XCTest
@testable import LoopForge

private final class AgentModelURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw NSError(domain: "AgentModelURLProtocol", code: 1)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func capturedRequestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else {
        throw NSError(domain: "AgentModelURLProtocol", code: 2)
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? NSError(domain: "AgentModelURLProtocol", code: 3) }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

private final class TestContinuationGate {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

private final class MockChatCompletionServer {
    private let queue = DispatchQueue(label: "com.loopforge.tests.mock-chat")
    private var listener: NWListener?

    func start() async throws -> URL {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] client in
            self?.accept(client)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = TestContinuationGate()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    guard let port = listener.port else { return }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ client: NWConnection) {
        client.start(queue: queue)
        receive(client, buffer: Data())
    }

    private func receive(_ client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, _ in
            guard let self else { return }
            var next = buffer
            if let data { next.append(data) }
            if let request = HTTPBridgeRequest.parseIfComplete(next) {
                self.reply(to: request, client: client)
            } else if !complete {
                self.receive(client, buffer: next)
            } else {
                client.cancel()
            }
        }
    }

    private func reply(to request: HTTPBridgeRequest, client: NWConnection) {
        let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
        let messages = payload?["messages"] as? [[String: Any]] ?? []
        let hasToolResult = messages.contains { ($0["role"] as? String) == "tool" }
        let tools = payload?["tools"] as? [[String: Any]] ?? []
        let execTool = tools.first {
            (($0["function"] as? [String: Any])?["name"] as? String) == "exec_command"
        }
        let object: [String: Any]
        if hasToolResult {
            object = [
                "id": "chatcmpl_done",
                "choices": [[
                    "index": 0,
                    "finish_reason": "stop",
                    "message": ["role": "assistant", "content": "LOOPFORGE_BRIDGE_TOOL_OK"]
                ]]
            ]
        } else if let function = execTool?["function"] as? [String: Any],
                  let name = function["name"] as? String {
            object = [
                "id": "chatcmpl_tool",
                "choices": [[
                    "index": 0,
                    "finish_reason": "tool_calls",
                    "message": [
                        "role": "assistant",
                        "content": NSNull(),
                        "tool_calls": [[
                            "id": "call_bridge_test",
                            "type": "function",
                            "function": [
                                "name": name,
                                "arguments": #"{"cmd":"printf bridge_tool_ok > bridge-marker.txt"}"#
                            ]
                        ]]
                    ]
                ]]
            ]
        } else {
            object = [
                "id": "chatcmpl_text",
                "choices": [[
                    "index": 0,
                    "finish_reason": "stop",
                    "message": ["role": "assistant", "content": "LOOPFORGE_BRIDGE_TEXT_OK"]
                ]]
            ]
        }
        let body = try! JSONSerialization.data(withJSONObject: object)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var packet = Data(header.utf8)
        packet.append(body)
        client.send(content: packet, completion: .contentProcessed { _ in client.cancel() })
    }
}

final class AgentModelTests: XCTestCase {
    override func tearDown() {
        AgentModelURLProtocol.handler = nil
        super.tearDown()
    }

    func testProviderTemplatesExposeOnlyCurrentAgentModels() {
        XCTAssertEqual(APIProviderKind.qwen.fallbackModels.first, "qwen3.7-max")
        XCTAssertTrue(APIProviderKind.zhipu.acceptsRecentModel("glm-5.2"))
        XCTAssertFalse(APIProviderKind.zhipu.acceptsRecentModel("glm-4.7"))
        XCTAssertTrue(APIProviderKind.deepSeek.acceptsRecentModel("deepseek-v4-pro"))
        XCTAssertFalse(APIProviderKind.deepSeek.acceptsRecentModel("deepseek-chat"))
        XCTAssertEqual(APIProviderKind.kimi.fallbackModels.first, "kimi-k3")
        XCTAssertTrue(APIProviderKind.kimi.acceptsRecentModel("kimi-k2.7-code-highspeed"))
        XCTAssertFalse(APIProviderKind.kimi.acceptsRecentModel("kimi-k2.5"))
        XCTAssertTrue(APIProviderKind.claude.acceptsRecentModel("claude-opus-5"))
        XCTAssertFalse(APIProviderKind.claude.acceptsRecentModel("claude-3-5-sonnet"))
    }

    func testLocalCatalogContainsFiveToolCapableUnbundledRecommendations() {
        XCTAssertEqual(ModelProfile.all.map(\.ollamaName), [
            "qwen3.6:35b",
            "devstral-small-2:24b",
            "qwen3-coder:30b",
            "glm-4.7-flash:q4_K_M",
            "gpt-oss:20b"
        ])
        XCTAssertTrue(ModelProfile.all.allSatisfy {
            $0.requiredOllamaCapabilities.contains("completion")
                && $0.requiredOllamaCapabilities.contains("tools")
                && $0.downloadSizeGB > 10
        })
        XCTAssertEqual(ModelProfile.all.filter(\.supportsVision).count, 2)
    }

    func testOllamaRegistryPreflightUsesOfficialManifestAndExactLayerSizes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentModelURLProtocol.self]
        let session = URLSession(configuration: configuration)
        AgentModelURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "registry.ollama.ai")
            XCTAssertEqual(request.url?.path, "/v2/library/qwen3.6/manifests/35b")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Accept"),
                "application/vnd.docker.distribution.manifest.v2+json"
            )
            let body = """
            {
              "layers": [
                {"mediaType":"application/vnd.ollama.image.model","digest":"sha256:model","size":24000000000},
                {"mediaType":"application/vnd.ollama.image.template","digest":"sha256:template","size":5000}
              ]
            }
            """
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(body.utf8)
            )
        }

        let plan = try await OllamaRegistryClient(session: session)
            .downloadPlan(for: .advancedVisualAuditor)
        XCTAssertEqual(plan.profile, .advancedVisualAuditor)
        XCTAssertEqual(plan.downloadBytes, 24_000_005_000)
        XCTAssertEqual(plan.modelLayerDigest, "sha256:model")
    }

    func testLegacyAPIConnectionDecodesWithoutNewProviderCatalogFields() throws {
        let id = UUID()
        let json = """
        {
          "id":"\(id.uuidString)",
          "name":"Legacy DeepSeek",
          "baseURL":"https://api.deepseek.com",
          "model":"deepseek-v4-pro",
          "wireProtocol":"chatCompletions",
          "reasoningOptions":["high"],
          "contextWindow":128000,
          "supportsVision":false
        }
        """
        let connection = try JSONDecoder().decode(APIModelConnection.self, from: Data(json.utf8))
        XCTAssertEqual(connection.id, id)
        XCTAssertNil(connection.providerKind)
        XCTAssertEqual(connection.resolvedProviderKind, .deepSeek)
        XCTAssertEqual(connection.selectableModels, ["deepseek-v4-pro"])
    }

    func testOfficialModelCatalogParsingUsesProviderAuthenticationAndNewestFirst() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentModelURLProtocol.self]
        let session = URLSession(configuration: configuration)
        AgentModelURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "local-test-key")
            let body = """
            {"data":[
              {"id":"claude-sonnet-4-6","created_at":100},
              {"id":"claude-opus-5","created_at":200}
            ]}
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }
        let connection = APIProviderKind.claude.template()
        let models = try await OpenAICompatibleClient(session: session).listModels(
            connection: connection,
            apiKey: "local-test-key"
        )
        XCTAssertEqual(models, ["claude-opus-5", "claude-sonnet-4-6"])
    }

    func testChatCompletionAdapterUsesProviderSpecificThinkingInsteadOfOpenAIReasoningField() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentModelURLProtocol.self]
        let session = URLSession(configuration: configuration)
        AgentModelURLProtocol.handler = { request in
            let body = try capturedRequestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertNotNil(json["thinking"])
            XCTAssertNil(json["reasoning_effort"])
            let response = #"{"choices":[{"message":{"role":"assistant","content":"LOOPFORGE_OK"}}]}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }
        let connection = APIProviderKind.zhipu.template()
        let text = try await OpenAICompatibleClient(session: session).complete(
            system: "Return the token.",
            user: "LOOPFORGE_OK",
            connection: connection,
            apiKey: "test-key",
            reasoningEffort: "high"
        )
        XCTAssertEqual(text, "LOOPFORGE_OK")
    }

    func testResponsesChatTranslatorPreservesToolsAndReturnsCodexFunctionEvents() throws {
        let request: [String: Any] = [
            "instructions": "Use tools and verify the result.",
            "input": [
                ["role": "user", "content": [["type": "input_text", "text": "Create marker.txt"]]]
            ],
            "tools": [[
                "type": "function",
                "name": "exec_command",
                "description": "Run a command",
                "parameters": [
                    "type": "object",
                    "properties": ["cmd": ["type": "string"]],
                    "required": ["cmd"]
                ]
            ]],
            "max_output_tokens": 2_048
        ]
        let chat = try ResponsesChatTranslator.chatRequest(from: request, model: "glm-5.2")
        XCTAssertEqual(chat["model"] as? String, "glm-5.2")
        let tools = try XCTUnwrap(chat["tools"] as? [[String: Any]])
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "exec_command")

        let upstream: [String: Any] = [
            "choices": [[
                "message": [
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": [[
                        "id": "call_test",
                        "type": "function",
                        "function": [
                            "name": "exec_command",
                            "arguments": #"{"cmd":"touch marker.txt"}"#
                        ]
                    ]]
                ]
            ]]
        ]
        let stream = try ResponsesChatTranslator.responsesEventStream(from: upstream, model: "glm-5.2")
        XCTAssertTrue(stream.contains("response.function_call_arguments.done"))
        XCTAssertTrue(stream.contains("call_test"))
        XCTAssertTrue(stream.contains("touch marker.txt"))
        XCTAssertTrue(stream.contains("response.completed"))
    }

    func testRealCodexChildRunsAToolThroughResponsesChatBridge() async throws {
        guard let codex = CodexRuntime.executable else {
            throw XCTSkip("No official or bundled Codex executable is available.")
        }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopforge-chat-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let upstream = MockChatCompletionServer()
        let upstreamURL = try await upstream.start()
        defer { upstream.stop() }
        var connection = APIProviderKind.zhipu.template()
        connection.baseURL = upstreamURL.absoluteString
        connection.model = "glm-5.2"
        let bridge = ResponsesChatBridge(connection: connection, apiKey: "local-fixture-key")
        let bridgeURL = try await bridge.start()
        defer { bridge.stop() }

        var environment = CodexRuntime.environment()
        environment["LOOPFORGE_AGENT_API_KEY"] = bridge.authorizationToken
        let arguments = [
            "exec", "--json", "--color", "never", "--skip-git-repo-check",
            "--disable", "plugins", "--ignore-user-config",
            "--model", connection.model,
            "--sandbox", "danger-full-access", "--cd", workspace.path,
            "--config", "approval_policy=\"never\"",
            "--config", "model_provider=\"loopforge_test_api\"",
            "--config", "model_providers.loopforge_test_api.name=\"LoopForge bridge test\"",
            "--config", "model_providers.loopforge_test_api.base_url=\"\(bridgeURL.absoluteString)\"",
            "--config", "model_providers.loopforge_test_api.env_key=\"LOOPFORGE_AGENT_API_KEY\"",
            "--config", "model_providers.loopforge_test_api.wire_api=\"responses\"",
            "--config", "model_providers.loopforge_test_api.requires_openai_auth=false",
            "-"
        ]
        let result = try await ProcessRunner().run(
            executable: codex,
            arguments: arguments,
            environment: environment,
            currentDirectory: workspace,
            stdin: Data("Create bridge-marker.txt using the shell tool, verify it, then finish.".utf8),
            timeout: 45
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("LOOPFORGE_BRIDGE_TOOL_OK"), result.stdout)
        XCTAssertEqual(
            try String(contentsOf: workspace.appendingPathComponent("bridge-marker.txt"), encoding: .utf8),
            "bridge_tool_ok"
        )
    }

    func testProcessRunnerTerminatesAChildAtItsDeadline() async throws {
        let startedAt = Date()
        do {
            _ = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"],
                timeout: 0.1
            )
            XCTFail("Expected the process deadline to fail closed.")
        } catch {
            XCTAssertTrue(error is ProcessRunnerError)
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        }
    }

    func testMissingCodexThreadIsRecognizedForImmediateFreshSessionRecovery() {
        XCTAssertTrue(CodexRunner.reportsMissingThread(
            "ERROR codex_core::session: failed to record rollout items: thread 019f-test not found"
        ))
        XCTAssertFalse(CodexRunner.reportsMissingThread(
            "ERROR codex_models_manager: timeout waiting for child process to exit"
        ))
    }

    func testLocalSubAgentUsesCodexOSSHarness() {
        var task = makeTask()
        task.subAgent = .local(profile: .deepCoder, access: .fullAccess)

        let arguments = CodexRunner().initialArguments(task: task)

        XCTAssertTrue(arguments.contains("--oss"))
        XCTAssertTrue(arguments.contains("ollama"))
        XCTAssertTrue(arguments.contains("apply_patch_freeform"))
        XCTAssertTrue(arguments.contains("qwen3-coder:30b"))
        XCTAssertFalse(arguments.joined(separator: " ").contains("LOOPFORGE_AGENT_API_KEY="))
    }

    func testResponsesAPISubAgentUsesProviderWithoutEmbeddingSecret() {
        var task = makeTask()
        let connection = APIModelConnection(
            id: UUID(),
            name: "Private Responses",
            baseURL: "https://example.com/v1/",
            model: "reasoning-model",
            wireProtocol: .responses,
            reasoningOptions: ["high"],
            contextWindow: 64_000,
            supportsVision: false
        )
        task.subAgent = .api(connection: connection, reasoning: "high", access: .workspaceOnly)

        let arguments = CodexRunner().initialArguments(task: task)
        let command = arguments.joined(separator: " ")

        XCTAssertTrue(command.contains("model_provider=\"loopforge_api\""))
        XCTAssertTrue(command.contains("wire_api=\"responses\""))
        XCTAssertTrue(command.contains("https://example.com/v1"))
        XCTAssertTrue(command.contains("model_reasoning_effort=\"high\""))
        XCTAssertFalse(command.lowercased().contains("bearer"))
        XCTAssertFalse(command.contains("sk-"))
    }

    func testAgentSelectionRoundTripsWithTaskCheckpoint() throws {
        var task = makeTask()
        task.controlAgent = .local(profile: .advancedVisualAuditor, access: .workspaceOnly)
        task.subAgent = .codex(model: "gpt-5.6-sol", displayName: "GPT-5.6-Sol", reasoning: "ultra", access: .fullAccess)
        let data = try JSONEncoder.loopForge.encode(task)
        let restored = try JSONDecoder.loopForge.decode(LoopTask.self, from: data)

        XCTAssertEqual(restored.resolvedControlAgent.provider, .local)
        XCTAssertEqual(restored.resolvedSubAgent.modelID, "gpt-5.6-sol")
        XCTAssertEqual(restored.resolvedSubAgent.reasoningEffort, "ultra")
    }

    func testRealDeepSeekChatAndAutomaticFallbackWhenEnabled() async throws {
        guard let key = ProcessInfo.processInfo.environment["LOOPFORGE_DEEPSEEK_TEST_KEY"], !key.isEmpty else {
            throw XCTSkip("Set LOOPFORGE_DEEPSEEK_TEST_KEY to run the real DeepSeek product-path test.")
        }
        let connection = APIModelConnection(
            id: UUID(),
            name: "DeepSeek V4 Flash",
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash",
            wireProtocol: .chatCompletions,
            reasoningOptions: ["high", "max"],
            contextWindow: 128_000,
            supportsVision: false
        )
        let client = OpenAICompatibleClient()
        let direct = try await client.complete(
            system: "Return only the requested token.",
            user: "Return LOOPFORGE_DEEPSEEK_OK",
            connection: connection,
            apiKey: key,
            protocolOverride: .chatCompletions,
            maxTokens: 64
        )
        XCTAssertTrue(direct.contains("LOOPFORGE_DEEPSEEK_OK"))

        var automatic = connection
        automatic.wireProtocol = .automatic
        let fallback = try await client.complete(
            system: "Return only the requested token.",
            user: "Return LOOPFORGE_AUTO_OK",
            connection: automatic,
            apiKey: key,
            maxTokens: 64
        )
        XCTAssertTrue(fallback.contains("LOOPFORGE_AUTO_OK"))

        var responsesOnly = connection
        responsesOnly.wireProtocol = .responses
        do {
            _ = try await client.complete(
                system: "Connection test", user: "Reply OK",
                connection: responsesOnly, apiKey: key, maxTokens: 32
            )
            XCTFail("DeepSeek currently documents Chat Completions, so an explicit Responses-only configuration must not silently fall back.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testRealLocalSubAgentsCompleteTwoDifferentWorkspaceTasksWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["LOOPFORGE_RUN_LOCAL_SUBAGENT_TESTS"] == "1" else {
            throw XCTSkip("Set LOOPFORGE_RUN_LOCAL_SUBAGENT_TESTS=1 to run real Codex OSS harness tasks.")
        }
        let manager = OllamaManager()
        try await manager.ensureReady(contextWindow: 32_768) { _ in }
        let requestedProfile = ProcessInfo.processInfo.environment["LOOPFORGE_LOCAL_SUBAGENT_PROFILE"]
        let profiles = [ModelProfile.deepCoder, ModelProfile.efficientAgent].filter {
            requestedProfile == nil || $0.id == requestedProfile
        }
        for profile in profiles {
            let plan = try await manager.prepareDownload(profile)
            _ = try await manager.downloadVerifiedModel(plan) { _ in }
        }

        let repairRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopforge-local-repair-\(UUID().uuidString)", isDirectory: true)
        let buildRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopforge-local-build-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repairRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: repairRoot)
            try? FileManager.default.removeItem(at: buildRoot)
        }
        try """
        def stable_unique(values):
            return list(set(values))
        """.write(to: repairRoot.appendingPathComponent("stable_unique.py"), atomically: true, encoding: .utf8)

        let scenarios: [(ModelProfile, URL, String, String)] = [
            (
                .deepCoder,
                repairRoot,
                "Repair stable_unique.py so it preserves first-seen order for hashable values. Add unittest coverage in test_stable_unique.py, run it, and finish only after it passes.",
                "test_stable_unique.py"
            ),
            (
                .efficientAgent,
                buildRoot,
                "Create a dependency-free Python CLI named slugify.py. It must convert Unicode text to a lowercase ASCII hyphen slug, reject an empty result with a concise nonzero error, include unittest coverage in test_slugify.py, and run the tests.",
                "test_slugify.py"
            )
        ]

        for (profile, root, prompt, expectedTest) in scenarios where profiles.contains(profile) {
            var task = makeTask()
            task = LoopTask(
                id: task.id, title: profile.displayName, request: prompt, quality: .lightweight,
                category: .maintenance, workspacePath: root.path, targetSeconds: 3_600,
                accumulatedCodexSeconds: 0, model: .advancedVisualAuditor, status: .preparing,
                stage: "Ready", iteration: 0, threadID: nil, auditScore: 0, auditSummary: "",
                lastAgentMessage: "", consecutiveFailures: 0, createdAt: task.createdAt,
                updatedAt: task.updatedAt, completedAt: nil, logs: [],
                subAgent: .local(profile: profile, access: .fullAccess)
            )
            let result = try await CodexRunner().runTurn(
                task: task,
                prompt: prompt,
                onThreadStarted: { _ in },
                onEvent: { _, _ in }
            )
            XCTAssertEqual(result.exitCode, 0, "\(profile.displayName): \(result.stderr)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(expectedTest).path))
            let verification = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: ["-m", "unittest", "discover", "-v"],
                currentDirectory: root
            )
            XCTAssertEqual(verification.exitCode, 0, "\(profile.displayName): \(verification.stderr)")
        }
    }

    private func makeTask() -> LoopTask {
        let now = Date()
        return LoopTask(
            id: UUID(), title: "Agent Test", request: "Build a tested CLI", quality: .lightweight,
            category: .library, workspacePath: FileManager.default.temporaryDirectory.path,
            targetSeconds: 3_600, accumulatedCodexSeconds: 0, model: .advancedVisualAuditor,
            status: .preparing, stage: "Ready", iteration: 0, threadID: nil, auditScore: 0,
            auditSummary: "", lastAgentMessage: "", consecutiveFailures: 0,
            createdAt: now, updatedAt: now, completedAt: nil, logs: []
        )
    }
}
