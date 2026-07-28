import Foundation
import Network

private final class BridgeContinuationGate {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

/// Current Codex builds only accept the Responses wire protocol for custom
/// providers. This loopback bridge preserves the Codex tool harness while
/// adapting providers that expose only OpenAI-compatible Chat Completions.
final class ResponsesChatBridge {
    let authorizationToken = UUID().uuidString

    private let connection: APIModelConnection
    private let apiKey: String
    private let queue = DispatchQueue(label: "com.loopforge.responses-chat-bridge")
    private var listener: NWListener?

    init(connection: APIModelConnection, apiKey: String) {
        self.connection = connection
        self.apiKey = apiKey
    }

    func start() async throws -> URL {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = BridgeContinuationGate()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: LoopForgeError.runtimeUnavailable(
                            "The local API compatibility bridge did not receive a port."
                        ))
                        return
                    }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: LoopForgeError.runtimeUnavailable(
                        "The local API compatibility bridge could not start: \(error.localizedDescription)"
                    ))
                case .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: LoopForgeError.runtimeUnavailable(
                        "The local API compatibility bridge was cancelled before startup."
                    ))
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
        receive(from: client, buffer: Data())
    }

    private func receive(from client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else {
                client.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if next.count > 64_000_000 {
                self.send(status: 413, contentType: "text/plain", body: Data("Request too large".utf8), to: client)
                return
            }
            if let request = HTTPBridgeRequest.parseIfComplete(next) {
                Task {
                    let response = await self.response(for: request)
                    self.send(status: response.status, contentType: response.contentType, body: response.body, to: client)
                }
            } else if complete || error != nil {
                self.send(status: 400, contentType: "text/plain", body: Data("Incomplete request".utf8), to: client)
            } else {
                self.receive(from: client, buffer: next)
            }
        }
    }

    private func response(for request: HTTPBridgeRequest) async -> HTTPBridgeResponse {
        guard request.authorization == "Bearer \(authorizationToken)" else {
            return .json(status: 401, object: ["error": ["message": "Unauthorized loopback request"]])
        }
        if request.method == "GET", request.path.hasSuffix("/models") {
            return .json(status: 200, object: [
                "object": "list",
                "data": [["id": connection.model, "object": "model", "owned_by": "loopforge"]]
            ])
        }
        guard request.method == "POST", request.path.hasSuffix("/responses") else {
            return .json(status: 404, object: ["error": ["message": "Route not found"]])
        }
        do {
            guard let responsesPayload = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
                throw LoopForgeError.runtimeUnavailable("Codex sent malformed Responses JSON.")
            }
            var chatPayload = try ResponsesChatTranslator.chatRequest(
                from: responsesPayload,
                model: connection.model
            )
            if let reasoning = responsesPayload["reasoning"] as? [String: Any],
               let effort = reasoning["effort"] as? String {
                OpenAICompatibleClient.applyProviderReasoning(
                    to: &chatPayload,
                    provider: connection.resolvedProviderKind,
                    effort: effort
                )
            }
            let upstream = try await sendUpstream(chatPayload)
            let stream = try ResponsesChatTranslator.responsesEventStream(
                from: upstream,
                model: connection.model
            )
            return HTTPBridgeResponse(status: 200, contentType: "text/event-stream", body: Data(stream.utf8))
        } catch {
            return .json(status: 502, object: [
                "error": [
                    "message": sanitizedLogText(error.localizedDescription),
                    "type": "loopforge_chat_bridge_error"
                ]
            ])
        }
    }

    private func sendUpstream(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: connection.normalizedBaseURL + "/chat/completions") else {
            throw LoopForgeError.runtimeUnavailable("The API base URL is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if connection.resolvedProviderKind == .claude {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LoopForgeError.runtimeUnavailable("The Chat Completions provider returned no HTTP status.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = sanitizedLogText(String(data: data, encoding: .utf8) ?? "")
            throw LoopForgeError.runtimeUnavailable("Upstream HTTP \(http.statusCode): \(body.prefix(600))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoopForgeError.runtimeUnavailable("The Chat Completions provider returned malformed JSON.")
        }
        return json
    }

    private func send(status: Int, contentType: String, body: Data, to client: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        default: reason = "Bad Gateway"
        }
        let head = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var packet = Data(head.utf8)
        packet.append(body)
        client.send(content: packet, completion: .contentProcessed { _ in client.cancel() })
    }
}

struct HTTPBridgeResponse {
    let status: Int
    let contentType: String
    let body: Data

    static func json(status: Int, object: [String: Any]) -> HTTPBridgeResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPBridgeResponse(status: status, contentType: "application/json", body: data)
    }
}

struct HTTPBridgeRequest {
    let method: String
    let path: String
    let authorization: String?
    let body: Data

    static func parseIfComplete(_ data: Data) -> HTTPBridgeRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let bodyStart = headerRange.upperBound
        let available = Data(data[bodyStart...])
        let body: Data
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decoded = decodeChunked(available) else { return nil }
            body = decoded
        } else {
            let length = Int(headers["content-length"] ?? "0") ?? 0
            guard available.count >= length else { return nil }
            body = Data(available.prefix(length))
        }
        return HTTPBridgeRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            authorization: headers["authorization"],
            body: body
        )
    }

    private static func decodeChunked(_ data: Data) -> Data? {
        var cursor = data.startIndex
        var result = Data()
        let crlf = Data("\r\n".utf8)
        while cursor < data.endIndex {
            guard let lineRange = data[cursor...].range(of: crlf),
                  let line = String(data: data[cursor..<lineRange.lowerBound], encoding: .utf8),
                  let count = Int(line.split(separator: ";")[0], radix: 16) else { return nil }
            cursor = lineRange.upperBound
            if count == 0 {
                guard data.distance(from: cursor, to: data.endIndex) >= 2 else { return nil }
                return result
            }
            guard data.distance(from: cursor, to: data.endIndex) >= count + 2 else { return nil }
            let end = data.index(cursor, offsetBy: count)
            result.append(data[cursor..<end])
            cursor = data.index(end, offsetBy: 2)
        }
        return nil
    }
}

enum ResponsesChatTranslator {
    static func chatRequest(from payload: [String: Any], model: String) throws -> [String: Any] {
        var messages: [[String: Any]] = []
        if let instructions = payload["instructions"] as? String, !instructions.isEmpty {
            messages.append(["role": "system", "content": instructions])
        }
        if let input = payload["input"] as? String {
            messages.append(["role": "user", "content": input])
        } else if let items = payload["input"] as? [[String: Any]] {
            var pendingToolCalls: [[String: Any]] = []
            for item in items {
                let type = item["type"] as? String
                if type == "function_call" {
                    let call = [
                        "id": (item["call_id"] as? String) ?? UUID().uuidString,
                        "type": "function",
                        "function": [
                            "name": (item["name"] as? String) ?? "tool",
                            "arguments": (item["arguments"] as? String) ?? "{}"
                        ]
                    ] as [String: Any]
                    pendingToolCalls.append(call)
                } else if type == "function_call_output" {
                    if !pendingToolCalls.isEmpty {
                        messages.append([
                            "role": "assistant",
                            "content": NSNull(),
                            "tool_calls": pendingToolCalls
                        ])
                        pendingToolCalls.removeAll()
                    }
                    messages.append([
                        "role": "tool",
                        "tool_call_id": (item["call_id"] as? String) ?? "",
                        "content": stringValue(item["output"]) ?? ""
                    ])
                } else {
                    if !pendingToolCalls.isEmpty {
                        messages.append([
                            "role": "assistant",
                            "content": NSNull(),
                            "tool_calls": pendingToolCalls
                        ])
                        pendingToolCalls.removeAll()
                    }
                    let rawRole = (item["role"] as? String) ?? "user"
                    let role = rawRole == "developer" ? "system" : rawRole
                    let content = chatContent(item["content"])
                    messages.append(["role": role, "content": content])
                }
            }
            if !pendingToolCalls.isEmpty {
                messages.append([
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": pendingToolCalls
                ])
            }
        }
        if messages.isEmpty {
            throw LoopForgeError.runtimeUnavailable("Codex sent no input messages to the compatibility bridge.")
        }

        var result: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "max_tokens": max(256, (payload["max_output_tokens"] as? Int) ?? 16_384)
        ]
        if let parallel = payload["parallel_tool_calls"] as? Bool {
            result["parallel_tool_calls"] = parallel
        }
        if let toolChoice = payload["tool_choice"], !(toolChoice is NSNull) {
            result["tool_choice"] = toolChoice
        }
        if let tools = payload["tools"] as? [[String: Any]] {
            let chatTools = tools.compactMap(chatTool)
            if !chatTools.isEmpty { result["tools"] = chatTools }
        }
        return result
    }

    static func responsesEventStream(from chat: [String: Any], model: String) throws -> String {
        guard let choices = chat["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw LoopForgeError.runtimeUnavailable("The Chat Completions response contained no assistant message.")
        }
        let responseID = "resp_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let createdAt = Int(Date().timeIntervalSince1970)
        var output: [[String: Any]] = []
        var events: [[String: Any]] = []
        events.append([
            "type": "response.created",
            "sequence_number": 0,
            "response": responseObject(
                id: responseID, createdAt: createdAt, model: model, status: "in_progress", output: []
            )
        ])
        var sequence = 1

        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            for (index, call) in toolCalls.enumerated() {
                guard let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String else { continue }
                let arguments = (function["arguments"] as? String) ?? "{}"
                let callID = (call["id"] as? String) ?? "call_\(UUID().uuidString)"
                let itemID = "fc_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                let item: [String: Any] = [
                    "id": itemID, "type": "function_call", "status": "completed",
                    "name": name, "call_id": callID, "arguments": arguments
                ]
                var added = item
                added["status"] = "in_progress"
                added["arguments"] = ""
                events.append([
                    "type": "response.output_item.added", "sequence_number": sequence,
                    "output_index": index, "item": added
                ])
                sequence += 1
                if !arguments.isEmpty {
                    events.append([
                        "type": "response.function_call_arguments.delta", "sequence_number": sequence,
                        "item_id": itemID, "output_index": index, "delta": arguments
                    ])
                    sequence += 1
                }
                events.append([
                    "type": "response.function_call_arguments.done", "sequence_number": sequence,
                    "item_id": itemID, "output_index": index, "arguments": arguments
                ])
                sequence += 1
                events.append([
                    "type": "response.output_item.done", "sequence_number": sequence,
                    "output_index": index, "item": item
                ])
                sequence += 1
                output.append(item)
            }
        } else {
            let text = textContent(message["content"])
            guard !text.isEmpty else {
                throw LoopForgeError.runtimeUnavailable("The Chat Completions response contained neither text nor tool calls.")
            }
            let itemID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let part: [String: Any] = [
                "type": "output_text", "text": text, "annotations": [], "logprobs": []
            ]
            let item: [String: Any] = [
                "id": itemID, "type": "message", "status": "completed",
                "role": "assistant", "content": [part]
            ]
            events.append([
                "type": "response.output_item.added", "sequence_number": sequence,
                "output_index": 0,
                "item": [
                    "id": itemID, "type": "message", "status": "in_progress",
                    "role": "assistant", "content": []
                ]
            ])
            sequence += 1
            events.append([
                "type": "response.content_part.added", "sequence_number": sequence,
                "item_id": itemID, "output_index": 0, "content_index": 0,
                "part": ["type": "output_text", "text": "", "annotations": [], "logprobs": []]
            ])
            sequence += 1
            events.append([
                "type": "response.output_text.delta", "sequence_number": sequence,
                "item_id": itemID, "output_index": 0, "content_index": 0, "delta": text, "logprobs": []
            ])
            sequence += 1
            events.append([
                "type": "response.output_text.done", "sequence_number": sequence,
                "item_id": itemID, "output_index": 0, "content_index": 0, "text": text, "logprobs": []
            ])
            sequence += 1
            events.append([
                "type": "response.content_part.done", "sequence_number": sequence,
                "item_id": itemID, "output_index": 0, "content_index": 0, "part": part
            ])
            sequence += 1
            events.append([
                "type": "response.output_item.done", "sequence_number": sequence,
                "output_index": 0, "item": item
            ])
            sequence += 1
            output.append(item)
        }
        events.append([
            "type": "response.completed", "sequence_number": sequence,
            "response": responseObject(
                id: responseID, createdAt: createdAt, model: model, status: "completed", output: output
            )
        ])
        return try events.map { event in
            let data = try JSONSerialization.data(withJSONObject: event)
            return "event: \(event["type"] as? String ?? "message")\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
        }.joined()
    }

    private static func chatContent(_ raw: Any?) -> Any {
        guard let parts = raw as? [[String: Any]] else {
            return stringValue(raw) ?? ""
        }
        let mapped = parts.compactMap { part -> [String: Any]? in
            let type = part["type"] as? String
            if type == "input_image", let url = part["image_url"] as? String {
                return ["type": "image_url", "image_url": ["url": url]]
            }
            if let text = part["text"] as? String {
                return ["type": "text", "text": text]
            }
            return nil
        }
        if mapped.count == 1, mapped[0]["type"] as? String == "text" {
            return mapped[0]["text"] as? String ?? ""
        }
        return mapped
    }

    private static func chatTool(_ tool: [String: Any]) -> [String: Any]? {
        let type = tool["type"] as? String
        guard type == "function" || type == "custom",
              let name = tool["name"] as? String, !name.isEmpty else { return nil }
        let parameters: [String: Any]
        if type == "custom" {
            parameters = [
                "type": "object",
                "properties": ["input": ["type": "string"]],
                "required": ["input"],
                "additionalProperties": false
            ]
        } else {
            parameters = (tool["parameters"] as? [String: Any]) ?? [
                "type": "object", "properties": [:]
            ]
        }
        var function: [String: Any] = ["name": name, "parameters": parameters]
        if let description = tool["description"] as? String { function["description"] = description }
        return ["type": "function", "function": function]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        guard let value, JSONSerialization.isValidJSONObject(["value": value]),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func textContent(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let parts = value as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private static func responseObject(
        id: String,
        createdAt: Int,
        model: String,
        status: String,
        output: [[String: Any]]
    ) -> [String: Any] {
        [
            "id": id,
            "object": "response",
            "created_at": createdAt,
            "status": status,
            "model": model,
            "output": output,
            "parallel_tool_calls": true,
            "error": NSNull(),
            "incomplete_details": NSNull(),
            "usage": [
                "input_tokens": 0,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens": 0,
                "output_tokens_details": ["reasoning_tokens": 0],
                "total_tokens": 0
            ]
        ]
    }
}
