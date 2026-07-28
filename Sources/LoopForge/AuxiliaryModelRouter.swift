import Foundation

struct AuxiliaryModelReply: Equatable {
    let text: String
    let provider: AgentProviderKind
    let providerLabel: String
}

/// Fixed-priority routing for LoopForge-owned reasoning. These calls never
/// edit the project and never contribute to the hard Sub Agent runtime.
struct AuxiliaryModelRouter {
    private let supervisor: LocalSupervisor

    init(supervisor: LocalSupervisor = LocalSupervisor()) {
        self.supervisor = supervisor
    }

    func complete(
        task: LoopTask,
        codex: AgentSelection?,
        apiConnections: [APIModelConnection],
        localProfiles: [ModelProfile],
        system: String,
        user: String,
        imagePaths: [String] = [],
        maxTokens: Int = 4_096,
        outputSchema: String? = nil,
        preferred: AgentSelection? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> AuxiliaryModelReply {
        let candidates = Self.orderedSelections(
            codex: codex,
            apiConnections: apiConnections,
            localProfiles: localProfiles,
            preferred: preferred
        )

        var errors: [String] = []
        for selection in candidates {
            do {
                let text = try await supervisor.auxiliaryResponse(
                    task: task,
                    selection: selection,
                    system: system,
                    user: user,
                    imagePaths: imagePaths,
                    maxTokens: maxTokens,
                    outputSchema: outputSchema,
                    timeout: timeout
                )
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LoopForgeError.runtimeUnavailable("The model returned an empty response.")
                }
                return AuxiliaryModelReply(
                    text: text,
                    provider: selection.provider,
                    providerLabel: selection.summary
                )
            } catch {
                errors.append("\(selection.summary): \(String(sanitizedLogText(error.localizedDescription).prefix(180)))")
            }
        }
        throw LoopForgeError.runtimeUnavailable(
            "No LoopForge reasoning provider completed the request. \(errors.joined(separator: " · "))"
        )
    }

    static func orderedSelections(
        codex: AgentSelection?,
        apiConnections: [APIModelConnection],
        localProfiles: [ModelProfile],
        preferred: AgentSelection? = nil
    ) -> [AgentSelection] {
        var candidates: [AgentSelection] = []
        if let preferred {
            candidates.append(readOnly(preferred))
        }
        if let codex {
            candidates.append(readOnly(codex))
        }
        candidates.append(contentsOf: apiConnections.compactMap { connection in
            guard APIKeyVault.get(for: connection.id) != nil else { return nil }
            return .api(
                connection: connection,
                reasoning: connection.reasoningOptions.last,
                access: .readOnly
            )
        })
        candidates.append(contentsOf: localProfiles.map {
            .local(profile: $0, access: .readOnly)
        })
        var seen = Set<String>()
        return candidates.filter {
            let key = "\($0.provider.rawValue)|\($0.modelID)"
            return seen.insert(key).inserted
        }
    }

    private static func readOnly(_ selection: AgentSelection) -> AgentSelection {
        AgentSelection(
            provider: selection.provider,
            modelID: selection.modelID,
            displayName: selection.displayName,
            reasoningEffort: selection.reasoningEffort,
            accessMode: .readOnly,
            localProfile: selection.localProfile,
            apiConnection: selection.apiConnection
        )
    }
}

struct PromptOptimizationCandidate: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let emphasis: String
}

struct PromptOptimizationEnvelope: Codable, Equatable {
    let candidates: [PromptOptimizationCandidate]
}

struct PromptOptimizationResult: Equatable {
    let candidates: [PromptOptimizationCandidate]
    let providerLabel: String
}

enum PromptOptimizationPhase: Equatable {
    case idle
    case generating(provider: String)
    case ready
    case failed(String)

    var isWorking: Bool {
        if case .generating = self { return true }
        return false
    }
}

struct PromptOptimizer {
    private let router: AuxiliaryModelRouter

    init(router: AuxiliaryModelRouter = AuxiliaryModelRouter()) {
        self.router = router
    }

    func optimize(
        task: LoopTask,
        codex: AgentSelection?,
        apiConnections: [APIModelConnection],
        localProfiles: [ModelProfile]
    ) async throws -> PromptOptimizationResult {
        let system = """
        You improve user requests for an autonomous software-engineering loop.
        Return only valid JSON:
        {"candidates":[
          {"id":"A","title":"short focus label","prompt":"complete improved request","emphasis":"what this version clarifies"},
          {"id":"B","title":"short focus label","prompt":"complete improved request","emphasis":"what this version clarifies"},
          {"id":"C","title":"short focus label","prompt":"complete improved request","emphasis":"what this version clarifies"}
        ]}

        Produce exactly three materially useful but semantically equivalent
        versions. Preserve every named product, platform, path, number,
        constraint, comparison, authorization boundary, and required output.
        Do not invent features, credentials, deadlines, technologies, or scope.
        Make acceptance evidence explicit where the original implies it. The
        original request remains an available fourth choice for the user.
        """
        let user = """
        PROJECT: \(task.workspacePath)
        TASK CATEGORY: \(task.category.title)
        TASK QUALITY: \(task.quality.title)

        VERBATIM USER REQUEST
        \(LocalSupervisor.boundedReviewText(task.request, limit: 24_000))
        """
        let reply = try await router.complete(
            task: task,
            codex: codex,
            apiConnections: apiConnections,
            localProfiles: localProfiles,
            system: system,
            user: user,
            maxTokens: 6_000
        )
        guard let envelope = Self.decodeEnvelope(reply.text),
              envelope.candidates.count == 3 else {
            throw LoopForgeError.runtimeUnavailable("The prompt optimizer did not return exactly three valid choices.")
        }
        let ids = Set(envelope.candidates.map { $0.id.uppercased() })
        guard ids.count == 3 else {
            throw LoopForgeError.runtimeUnavailable("The prompt optimizer returned duplicate choices.")
        }
        let requiredTokens = Self.contractTokens(in: task.request)
        let validated = envelope.candidates.filter { candidate in
            let prompt = candidate.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard prompt.count >= max(24, min(task.request.count / 3, 500)) else { return false }
            let normalized = prompt.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return requiredTokens.allSatisfy { normalized.localizedCaseInsensitiveContains($0) }
        }
        guard validated.count == 3 else {
            throw LoopForgeError.runtimeUnavailable(
                "One or more optimized prompts failed LoopForge's deterministic constraint-preservation audit."
            )
        }
        return PromptOptimizationResult(candidates: validated, providerLabel: reply.providerLabel)
    }

    static func decodeEnvelope(_ raw: String) -> PromptOptimizationEnvelope? {
        let stripped = stripFence(raw)
        if let data = stripped.data(using: .utf8),
           let direct = try? JSONDecoder().decode(PromptOptimizationEnvelope.self, from: data) {
            return direct
        }
        guard let object = firstJSONObject(in: stripped),
              let data = object.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PromptOptimizationEnvelope.self, from: data)
    }

    /// Exact values are a conservative anti-drift gate. Natural-language
    /// similarity remains the model's responsibility; paths, versions, quoted
    /// labels, URLs, and numbers are never allowed to disappear silently.
    static func contractTokens(in text: String) -> [String] {
        var tokens = Set<String>()
        let patterns = [
            #"https?://[^\s）)\]}>]+"#,
            #"(?:/|~\/)[A-Za-z0-9._~\-/ ]+"#,
            #"\b\d+(?:[.:]\d+)*(?:\s?(?:h|m|s|gb|mb|kb|%|小时|分钟))?\b"#,
            #""([^"\n]{2,80})""#,
            #"“([^”\n]{2,80})”"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in expression.matches(in: text, range: range) {
                let capture = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                guard let swiftRange = Range(capture, in: text) else { continue }
                tokens.insert(String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return tokens.filter { !$0.isEmpty }.sorted()
    }

    private static func stripFence(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"), let newline = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: newline)...])
            if value.hasSuffix("```") { value = String(value.dropLast(3)) }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var quoted = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
