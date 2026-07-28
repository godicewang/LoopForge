import Foundation

struct CodexTurnResult {
    let exitCode: Int32
    let elapsed: TimeInterval
    let eligibleElapsed: TimeInterval
    let threadID: String?
    let lastAgentMessage: String
    let commandSuccesses: Int
    let commandFailures: Int
    let stderr: String
    let eventErrors: [String]
    let recoveryReason: String?
}

private final class CodexEventCollector {
    private let lock = NSLock()
    private(set) var threadID: String?
    private(set) var lastAgentMessage = ""
    private(set) var commandSuccesses = 0
    private(set) var commandFailures = 0
    private(set) var eventErrors: [String] = []
    private(set) var turnCompleted = false

    func consume(
        _ line: String,
        onThreadStarted: (String) -> Void,
        onEvent: (LogKind, String) -> Void,
        onRuntimeSignal: (CodexRuntimeSignal) -> Void
    ) {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            onRuntimeSignal(CodexRuntimeSignal.classify(message: line))
            onEvent(.system, line)
            return
        }

        lock.lock(); defer { lock.unlock() }
        if type == "turn.completed" {
            turnCompleted = true
            onRuntimeSignal(.terminalCompletion)
            return
        }
        if type == "thread.started", let id = event["thread_id"] as? String {
            onRuntimeSignal(.productive)
            threadID = id
            onThreadStarted(id)
            onEvent(.system, "Codex session: \(id)")
            return
        }
        if type == "item.completed" || type == "item.started" {
            guard let item = event["item"] as? [String: Any], let itemType = item["type"] as? String else { return }
            if itemType == "agent_message", let text = item["text"] as? String {
                onRuntimeSignal(.productive)
                lastAgentMessage = text
                onEvent(.agent, text)
            } else if itemType.contains("command") {
                onRuntimeSignal(.productive)
                let command = (item["command"] as? String) ?? (item["text"] as? String) ?? "Command execution"
                let exitCode = item["exit_code"] as? Int
                var message = command
                if let output = item["aggregated_output"] as? String, !output.isEmpty {
                    message += "\n" + Self.boundedCommandOutput(output)
                }
                if let exitCode {
                    message += "\nexit code \(exitCode)"
                    if exitCode == 0 { commandSuccesses += 1 } else { commandFailures += 1 }
                }
                onEvent(.command, message)
            } else if itemType == "error", let message = item["message"] as? String {
                onRuntimeSignal(CodexRuntimeSignal.classify(message: message))
                eventErrors.append(message)
                onEvent(codexPresentationKind(for: message, fallback: .error), message)
            }
            return
        }
        if type == "turn.failed" || type == "error" {
            let message = (event["message"] as? String) ?? line
            onRuntimeSignal(CodexRuntimeSignal.classify(message: message))
            eventErrors.append(message)
            onEvent(codexPresentationKind(for: message, fallback: .error), message)
        }
    }

    func snapshot() -> (String?, String, Int, Int, [String]) {
        lock.lock(); defer { lock.unlock() }
        return (threadID, lastAgentMessage, commandSuccesses, commandFailures, eventErrors)
    }

    func hasCompletedTurn() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return turnCompleted
    }

    private static func boundedCommandOutput(_ output: String) -> String {
        let limit = 3_600
        guard output.count > limit else { return output }
        let head = String(output.prefix(1_400))
        let tail = String(output.suffix(2_000))
        return """
        \(head)
        … \(output.count - 3_400) command-output characters omitted; head and tail retained …
        \(tail)
        """
    }
}

final class CodexRunner {
    private let runner = ProcessRunner()

    func verifyWorker(task: LoopTask) async throws -> String {
        switch task.resolvedSubAgent.provider {
        case .codex:
            return try await verifyOfficialWorker(workspacePath: task.workspacePath)
        case .local:
            guard task.resolvedSubAgent.localProfile != nil else {
                throw LoopForgeError.runtimeUnavailable("The selected local Sub Agent is no longer configured.")
            }
            return "Local Sub Agent ready through the Codex OSS harness: \(task.resolvedSubAgent.displayName)."
        case .api:
            guard let connection = task.resolvedSubAgent.apiConnection else {
                throw LoopForgeError.runtimeUnavailable("The selected API Sub Agent connection is missing.")
            }
            guard let key = APIKeyVault.get(for: connection.id), !key.isEmpty else {
                throw LoopForgeError.runtimeUnavailable("The API key for \(connection.displayName) is missing from macOS Keychain.")
            }
            let probe = try await OpenAICompatibleClient().probe(connection: connection, apiKey: key)
            return probe.protocolUsed == .responses
                ? "API Sub Agent ready through the Codex Responses harness: \(connection.displayName)."
                : "API Sub Agent ready through LoopForge's local Responses-to-Chat bridge: \(connection.displayName)."
        }
    }

    func verifyOfficialWorker(workspacePath: String) async throws -> String {
        guard let executable = CodexRuntime.executable else { throw LoopForgeError.executableMissing("official Codex") }
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let result = try await runner.run(
            executable: executable,
            arguments: ["login", "status"],
            environment: CodexRuntime.environment(),
            currentDirectory: workspace
        )
        let status = sanitizedLogText([result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
        guard result.exitCode == 0 else {
            throw LoopForgeError.runtimeUnavailable(
                "The official Codex worker is not authenticated. Open Codex or run `codex login`, then resume this task. \(status.prefix(300))"
            )
        }
        return "Official Codex worker ready at \(executable.path). \(status)"
    }

    func runTurn(
        task: LoopTask,
        prompt: String,
        imagePaths: [String] = [],
        watchdogPolicy: CodexTurnWatchdogPolicy? = nil,
        onThreadStarted: @escaping (String) -> Void,
        onEvent: @escaping (LogKind, String) -> Void,
        onAgentSignal: @escaping (CodexRuntimeSignal) -> Void = { _ in },
        onRuntimeEligibilityChanged: @escaping (Bool, String) -> Void = { _, _ in }
    ) async throws -> CodexTurnResult {
        guard let executable = CodexRuntime.executable else { throw LoopForgeError.executableMissing("Codex") }
        var executionTask = task
        if var selection = executionTask.subAgent,
           var connection = selection.apiConnection,
           connection.wireProtocol == .automatic {
            guard let key = APIKeyVault.get(for: connection.id), !key.isEmpty else {
                throw LoopForgeError.runtimeUnavailable(
                    "The API key for \(connection.displayName) is missing from macOS Keychain."
                )
            }
            let probe = try await OpenAICompatibleClient().probe(connection: connection, apiKey: key)
            connection.wireProtocol = probe.protocolUsed
            selection.apiConnection = connection
            executionTask.subAgent = selection
        }

        let workspace = URL(fileURLWithPath: executionTask.workspacePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LoopForgeError.invalidWorkspace
        }

        var bridge: ResponsesChatBridge?
        var providerBaseURLOverride: String?
        var bridgeAuthorizationToken: String?
        if let connection = executionTask.resolvedSubAgent.apiConnection,
           connection.wireProtocol != .responses {
            guard let key = APIKeyVault.get(for: connection.id), !key.isEmpty else {
                throw LoopForgeError.runtimeUnavailable(
                    "The API key for \(connection.displayName) is missing from macOS Keychain."
                )
            }
            let compatibilityBridge = ResponsesChatBridge(connection: connection, apiKey: key)
            providerBaseURLOverride = try await compatibilityBridge.start().absoluteString
            bridgeAuthorizationToken = compatibilityBridge.authorizationToken
            bridge = compatibilityBridge
        }
        defer { bridge?.stop() }

        let collector = CodexEventCollector()
        let activeWork = ActiveWorkDurationTracker()
        let watchdog = CodexTurnWatchdog(
            policy: watchdogPolicy ?? .policy(for: task),
            onEligibilityChanged: { eligible, reason in
                activeWork.setEligible(eligible)
                onRuntimeEligibilityChanged(eligible, reason)
            }
        )
        let runtimeSignal: (CodexRuntimeSignal) -> Void = { signal in
            onAgentSignal(signal)
            switch signal {
            case .productive:
                watchdog.noteProductiveActivity()
            case .transportDegraded(let detail):
                watchdog.noteTransportDegraded(detail)
            case .terminalCompletion:
                watchdog.noteTerminalCompletion()
            case .diagnostic:
                break
            }
        }
        let arguments = executionTask.threadID == nil
            ? initialArguments(
                task: executionTask,
                imagePaths: imagePaths,
                providerBaseURLOverride: providerBaseURLOverride
            )
            : resumeArguments(
                task: executionTask,
                imagePaths: imagePaths,
                providerBaseURLOverride: providerBaseURLOverride
            )
        let effectivePrompt = workerPrompt(prompt, selection: executionTask.resolvedSubAgent)
        let wallStartedAt = Date()
        let result: ProcessResult
        do {
            result = try await runner.run(
                executable: executable,
                arguments: arguments,
                environment: environment(for: executionTask, bridgeAuthorizationToken: bridgeAuthorizationToken),
                currentDirectory: workspace,
                stdin: Data(effectivePrompt.utf8),
                watchdog: watchdog,
                onStdout: { line in
                    collector.consume(
                        line,
                        onThreadStarted: onThreadStarted,
                        onEvent: onEvent,
                        onRuntimeSignal: runtimeSignal
                    )
                },
                onStderr: { line in
                    let clean = sanitizedLogText(line)
                    if !clean.isEmpty {
                        runtimeSignal(CodexRuntimeSignal.classify(message: clean))
                        let lower = clean.lowercased()
                        if shouldIgnoreCodexStderr(lower) { return }
                        let fallback: LogKind = lower.contains("error") && !lower.contains("model metadata")
                            ? .error
                            : (lower.contains("warn") || lower.contains("model metadata") ? .warning : .system)
                        let kind = codexPresentationKind(for: clean, fallback: fallback)
                        onEvent(kind, clean)
                    }
                }
            )
        } catch ProcessRunnerError.stalled(let reason) {
            let values = collector.snapshot()
            if collector.hasCompletedTurn(), !values.1.isEmpty {
                onEvent(
                    .warning,
                    "Official Codex completed the turn, but its CLI cleanup process did not exit. LoopForge safely reclaimed the terminal process and continued from the confirmed result."
                )
                return CodexTurnResult(
                    exitCode: 0,
                    elapsed: Date().timeIntervalSince(wallStartedAt),
                    eligibleElapsed: activeWork.elapsed(),
                    threadID: values.0 ?? executionTask.threadID,
                    lastAgentMessage: values.1,
                    commandSuccesses: values.2,
                    commandFailures: values.3,
                    stderr: reason,
                    eventErrors: values.4,
                    recoveryReason: "Recovered after a confirmed terminal Codex event outlived its CLI cleanup process."
                )
            }
            return CodexTurnResult(
                exitCode: 124,
                elapsed: Date().timeIntervalSince(wallStartedAt),
                eligibleElapsed: activeWork.elapsed(),
                threadID: values.0 ?? executionTask.threadID,
                lastAgentMessage: values.1,
                commandSuccesses: values.2,
                commandFailures: values.3,
                stderr: reason,
                eventErrors: values.4 + [reason],
                recoveryReason: reason
            )
        } catch {
            watchdog.disarm()
            throw error
        }
        let values = collector.snapshot()
        return CodexTurnResult(
            exitCode: result.exitCode,
            elapsed: result.elapsed,
            eligibleElapsed: activeWork.elapsed(),
            threadID: values.0 ?? executionTask.threadID,
            lastAgentMessage: values.1,
            commandSuccesses: values.2,
            commandFailures: values.3,
            stderr: result.stderr,
            eventErrors: values.4,
            recoveryReason: nil
        )
    }

    static func reportsMissingThread(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("thread")
            && lower.contains("not found")
            && (lower.contains("failed to record rollout items")
                || lower.contains("failed to load")
                || lower.contains("resume"))
    }

    func initialArguments(
        task: LoopTask,
        imagePaths: [String] = [],
        providerBaseURLOverride: String? = nil
    ) -> [String] {
        var arguments = [
            "exec", "--json", "--color", "never", "--skip-git-repo-check"
        ]
        appendHostToolingPolicy(for: task, to: &arguments)
        appendGraphConcurrencyPolicy(for: task, to: &arguments)
        arguments += [
            "--model", task.workerModel,
            "--sandbox", task.workerAccessMode.sandboxMode, "--cd", task.workspacePath,
            "--config", "approval_policy=\"never\"",
            "--config", "sandbox_workspace_write.network_access=true",
            "--config", "project_root_markers=[]"
        ]
        appendProviderConfiguration(
            task.resolvedSubAgent,
            baseURLOverride: providerBaseURLOverride,
            to: &arguments
        )
        appendReasoning(task.resolvedSubAgent.reasoningEffort, to: &arguments)
        appendImages(imagePaths, to: &arguments)
        arguments.append("-")
        return arguments
    }

    func resumeArguments(
        task: LoopTask,
        imagePaths: [String] = [],
        providerBaseURLOverride: String? = nil
    ) -> [String] {
        var arguments = [
            "exec", "resume", "--json", "--skip-git-repo-check"
        ]
        appendHostToolingPolicy(for: task, to: &arguments)
        appendGraphConcurrencyPolicy(for: task, to: &arguments)
        arguments += [
            "--model", task.workerModel,
            "--config", "approval_policy=\"never\"",
            "--config", "sandbox_mode=\"\(task.workerAccessMode.sandboxMode)\"",
            "--config", "sandbox_workspace_write.network_access=true"
        ]
        appendProviderConfiguration(
            task.resolvedSubAgent,
            baseURLOverride: providerBaseURLOverride,
            to: &arguments
        )
        appendReasoning(task.resolvedSubAgent.reasoningEffort, to: &arguments)
        appendImages(imagePaths, to: &arguments)
        arguments.append(contentsOf: [task.threadID!, "-"])
        return arguments
    }

    private func appendHostToolingPolicy(for task: LoopTask, to arguments: inout [String]) {
        if CodexHostToolingPolicy.shouldLoadInstalledTools(for: task) {
            // Full Access plus an explicitly visual/GUI objective means the
            // user expects the same already-installed Browser/Computer Use
            // environment as Codex itself. Model, sandbox, and approval
            // settings below remain explicit LoopForge overrides.
            arguments.append(contentsOf: ["--enable", "plugins"])
        } else {
            // Keep ordinary code-only turns deterministic and free of unrelated
            // user plugins, MCP servers, notifications, or hooks.
            arguments.append(contentsOf: ["--disable", "plugins", "--ignore-user-config"])
        }
    }

    private func appendGraphConcurrencyPolicy(for task: LoopTask, to arguments: inout [String]) {
        if task.resolvedExecutionMode != .singleLoop {
            // LoopForge's persisted graph/candidate scheduler is the sole
            // concurrency controller.
            // Hidden Codex fan-out would bypass node scopes, max concurrency,
            // signal-based wakeups, timers, and the user-visible graph.
            arguments.append(contentsOf: [
                "--disable", "multi_agent",
                "--disable", "multi_agent_v2",
                "--disable", "enable_fanout"
            ])
        }
    }

    private func appendImages(_ paths: [String], to arguments: inout [String]) {
        for path in paths.prefix(4) where FileManager.default.fileExists(atPath: path) {
            arguments.append(contentsOf: ["--image", path])
        }
    }

    private func appendProviderConfiguration(
        _ selection: AgentSelection,
        baseURLOverride: String?,
        to arguments: inout [String]
    ) {
        switch selection.provider {
        case .codex:
            break
        case .local:
            arguments.append(contentsOf: [
                "--oss", "--local-provider", "ollama",
                "--enable", "apply_patch_freeform"
            ])
        case .api:
            guard let connection = selection.apiConnection else { return }
            let baseURL = baseURLOverride ?? connection.normalizedBaseURL
            arguments.append(contentsOf: [
                "--config", "model_provider=\"loopforge_api\"",
                "--config", "model_providers.loopforge_api.name=\(tomlString(connection.displayName))",
                "--config", "model_providers.loopforge_api.base_url=\(tomlString(baseURL))",
                "--config", "model_providers.loopforge_api.env_key=\"LOOPFORGE_AGENT_API_KEY\"",
                "--config", "model_providers.loopforge_api.wire_api=\"responses\"",
                "--config", "model_providers.loopforge_api.requires_openai_auth=false"
            ])
        }
    }

    private func appendReasoning(_ reasoning: String?, to arguments: inout [String]) {
        guard let reasoning, !reasoning.isEmpty else { return }
        arguments.append(contentsOf: ["--config", "model_reasoning_effort=\(tomlString(reasoning))"])
    }

    private func environment(
        for task: LoopTask,
        bridgeAuthorizationToken: String?
    ) -> [String: String] {
        var result = CodexRuntime.environment()
        if let bridgeAuthorizationToken {
            result["LOOPFORGE_AGENT_API_KEY"] = bridgeAuthorizationToken
        } else if let connection = task.resolvedSubAgent.apiConnection,
                  let key = APIKeyVault.get(for: connection.id) {
            result["LOOPFORGE_AGENT_API_KEY"] = key
        }
        return result
    }

    private func tomlString(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func workerPrompt(_ prompt: String, selection: AgentSelection) -> String {
        guard selection.provider == .local, selection.modelID.lowercased().hasPrefix("gpt-oss") else {
            return prompt
        }
        return """
        <loopforge_local_tool_compatibility>
        This gpt-oss runtime can execute Codex shell tools, but its structured `apply_patch` calls are not accepted by the current OSS bridge. Do not call or retry `apply_patch` or alternate spellings. Use `exec_command` for workspace file creation and edits, then re-open the result and run the requested verification. Preserve the same access and task boundaries.
        </loopforge_local_tool_compatibility>

        \(prompt)
        """
    }
}

enum CodexHostToolingPolicy {
    static func shouldLoadInstalledTools(for task: LoopTask) -> Bool {
        guard task.workerAccessMode == .fullAccess else { return false }
        return objectiveRequiresInstalledTools(task.request, category: task.category)
    }

    static func objectiveRequiresInstalledTools(
        _ request: String,
        category: TaskCategory
    ) -> Bool {
        if category == .desktopAutomation { return true }
        let objective = request.lowercased()
        let englishSignals = [
            "browser", "screenshot", "screen shot", "gui", "ui qa",
            "visual qa", "visual inspection", "playtest", "play test",
            "desktop app", "simulator", "real app", "real ui"
        ]
        let normalizedEnglish = objective
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")
        let boundedEnglish = " \(normalizedEnglish) "
        if englishSignals.contains(where: { boundedEnglish.contains(" \($0) ") }) {
            return true
        }

        let naturalLanguageSignals = [
            "浏览器", "截图", "界面验收", "视觉验收", "试玩", "模拟器"
        ]
        return naturalLanguageSignals.contains { objective.contains($0) }
    }
}

func shouldIgnoreCodexStderr(_ lowercasedText: String) -> Bool {
    lowercasedText.contains("codex_otel::events::session_telemetry")
        || lowercasedText.contains("model personality requested but model_messages is missing")
        || lowercasedText.contains("model_verbosity is set but ignored")
}

/// Codex emits some retryable transport diagnostics as error events even while
/// the same turn remains alive and continues producing successful tool output.
/// Keep those diagnostics in the durable log, but do not present them as user
/// action blockers. A real non-zero turn exit is still handled separately by
/// LoopController's infrastructure-failure policy.
func codexPresentationKind(for message: String, fallback: LogKind) -> LogKind {
    guard fallback == .error else { return fallback }
    let lower = message.lowercased()
    if isRetryableCodexTransportMessage(lower)
        || lower.contains("codex_models_manager::manager: failed to refresh available models: timeout waiting for child process to exit") {
        return .system
    }
    return fallback
}
