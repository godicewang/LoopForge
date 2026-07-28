import Foundation

struct APIProbeResult: Equatable {
    let protocolUsed: APIWireProtocol
    let message: String
}

struct OpenAICompatibleClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func listModels(connection: APIModelConnection, apiKey: String) async throws -> [String] {
        guard let url = URL(string: connection.normalizedBaseURL + "/models") else {
            throw LoopForgeError.runtimeUnavailable("The API base URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        applyAuthentication(to: &request, connection: connection, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LoopForgeError.runtimeUnavailable("The model catalog returned no HTTP status.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = sanitizedLogText(String(data: data, encoding: .utf8) ?? "")
            throw LoopForgeError.runtimeUnavailable("Model catalog HTTP \(http.statusCode): \(body.prefix(320))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoopForgeError.runtimeUnavailable("The model catalog returned malformed JSON.")
        }
        let entries = (json["data"] as? [[String: Any]])
            ?? (json["models"] as? [[String: Any]])
            ?? []
        var seen = Set<String>()
        let models = entries.compactMap { item -> (String, TimeInterval)? in
            guard let id = (item["id"] as? String) ?? (item["model"] as? String),
                  !id.isEmpty, seen.insert(id).inserted else { return nil }
            let created = (item["created_at"] as? TimeInterval)
                ?? (item["created"] as? TimeInterval)
                ?? 0
            return (id, created)
        }
        guard !models.isEmpty else {
            throw LoopForgeError.runtimeUnavailable("The provider returned an empty model catalog.")
        }
        return models.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.localizedStandardCompare($1.0) == .orderedDescending
        }.map { $0.0 }
    }

    func probe(connection: APIModelConnection, apiKey: String) async throws -> APIProbeResult {
        let protocols: [APIWireProtocol]
        switch connection.wireProtocol {
        case .automatic: protocols = [.responses, .chatCompletions]
        case .responses: protocols = [.responses]
        case .chatCompletions: protocols = [.chatCompletions]
        }
        var errors: [String] = []
        for item in protocols {
            do {
                let reply = try await complete(
                    system: "Reply with exactly LOOPFORGE_OK.",
                    user: "Connection test.",
                    connection: connection,
                    apiKey: apiKey,
                    protocolOverride: item,
                    maxTokens: 24
                )
                guard reply.uppercased().contains("LOOPFORGE_OK") else {
                    throw LoopForgeError.runtimeUnavailable("The endpoint responded, but the model did not complete the test contract.")
                }
                return APIProbeResult(protocolUsed: item, message: "Authenticated model response received.")
            } catch {
                errors.append("\(item.title): \(sanitizedLogText(error.localizedDescription).prefix(240))")
            }
        }
        throw LoopForgeError.runtimeUnavailable(errors.joined(separator: " · "))
    }

    func complete(
        system: String,
        user: String,
        connection: APIModelConnection,
        apiKey: String,
        protocolOverride: APIWireProtocol? = nil,
        reasoningEffort: String? = nil,
        imagePaths: [String] = [],
        maxTokens: Int = 4_096,
        timeout: TimeInterval = 120
    ) async throws -> String {
        let selected = protocolOverride ?? connection.wireProtocol
        if selected == .automatic {
            do {
                return try await complete(
                    system: system, user: user, connection: connection, apiKey: apiKey,
                    protocolOverride: .responses, reasoningEffort: reasoningEffort,
                    imagePaths: imagePaths, maxTokens: maxTokens, timeout: timeout
                )
            } catch {
                return try await complete(
                    system: system, user: user, connection: connection, apiKey: apiKey,
                    protocolOverride: .chatCompletions, reasoningEffort: reasoningEffort,
                    imagePaths: imagePaths, maxTokens: maxTokens, timeout: timeout
                )
            }
        }
        let suffix = selected == .responses ? "responses" : "chat/completions"
        guard let url = URL(string: connection.normalizedBaseURL + "/" + suffix) else {
            throw LoopForgeError.runtimeUnavailable("The API base URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        applyAuthentication(to: &request, connection: connection, apiKey: apiKey)

        var payload: [String: Any]
        let images = encodedImages(imagePaths)
        if selected == .responses {
            payload = [
                "model": connection.model,
                "instructions": system,
                "input": images.isEmpty ? user : [[
                    "role": "user",
                    "content": [["type": "input_text", "text": user]]
                        + images.map { ["type": "input_image", "image_url": $0] }
                ]],
                "max_output_tokens": maxTokens
            ]
        } else {
            let userContent: Any = images.isEmpty
                ? user
                : ([["type": "text", "text": user]]
                    + images.map { ["type": "image_url", "image_url": ["url": $0]] }) as [[String: Any]]
            payload = [
                "model": connection.model,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userContent]
                ],
                "max_tokens": maxTokens,
                "stream": false
            ]
        }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            if selected == .responses {
                payload["reasoning"] = ["effort": reasoningEffort]
            } else {
                Self.applyProviderReasoning(
                    to: &payload,
                    provider: connection.resolvedProviderKind,
                    effort: reasoningEffort
                )
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LoopForgeError.runtimeUnavailable("The API returned no HTTP status.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = sanitizedLogText(String(data: data, encoding: .utf8) ?? "")
            throw LoopForgeError.runtimeUnavailable("HTTP \(http.statusCode): \(body.prefix(420))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoopForgeError.runtimeUnavailable("The API returned malformed JSON.")
        }
        if selected == .responses {
            if let text = json["output_text"] as? String, !text.isEmpty { return text }
            if let output = json["output"] as? [[String: Any]] {
                let text = output.flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                if !text.isEmpty { return text }
            }
        } else if let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] {
            if let content = message["content"] as? String, !content.isEmpty { return content }
            if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty { return reasoning }
        }
        throw LoopForgeError.runtimeUnavailable("The API response contained no model text.")
    }

    private func applyAuthentication(
        to request: inout URLRequest,
        connection: APIModelConnection,
        apiKey: String
    ) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if connection.resolvedProviderKind == .claude {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    static func applyProviderReasoning(
        to payload: inout [String: Any],
        provider: APIProviderKind,
        effort: String
    ) {
        guard !effort.isEmpty, effort != "none" else { return }
        switch provider {
        case .qwen:
            payload["enable_thinking"] = true
        case .zhipu, .deepSeek:
            payload["thinking"] = ["type": "enabled"]
        case .claude:
            payload["thinking"] = ["type": "adaptive"]
        case .kimi:
            payload["reasoning_effort"] = effort
        case .custom:
            break
        }
    }

    private func encodedImages(_ paths: [String]) -> [String] {
        paths.prefix(4).compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url), data.count <= 12_000_000 else { return nil }
            let mime: String
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg": mime = "image/jpeg"
            case "webp": mime = "image/webp"
            default: mime = "image/png"
            }
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }
    }
}
