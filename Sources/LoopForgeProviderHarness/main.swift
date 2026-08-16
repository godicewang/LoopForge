import CryptoKit
import Darwin
import Foundation

private enum HarnessContract {
    static let schemaVersion = 1
    static let protocolVersion = 2
    static let contextDescriptor: Int32 = 196
    static let credentialDescriptor: Int32 = 197
    static let maximumContextBytes = 4 * 1_024
    static let maximumPromptBytes = 16 * 1_024 * 1_024
    static let maximumCredentialBytes = 8 * 1_024
    static let orderedFlags = [
        "--loopforge-provider-protocol",
        "--provider",
        "--provider-reference",
        "--model",
        "--reasoning-effort",
        "--sandbox",
        "--network",
        "--plugins",
        "--hidden-fan-out",
        "--invocation-context-fd",
        "--prompt-fd",
        "--prompt-digest",
        "--prompt-bytes",
        "--request-nonce",
        "--credential-mode",
        "--credential-fd",
    ]
}

private enum HarnessExit: Int32 {
    case invalidArguments = 64
    case invalidContext = 65
    case invalidPrompt = 66
    case invalidCredential = 67
    case outputFailure = 68
}

private func fail(_ code: HarnessExit, _ message: String) -> Never {
    let bounded = "loopforge-provider-harness:\(message.prefix(240))\n"
    _ = bounded.withCString {
        Darwin.write(STDERR_FILENO, $0, strlen($0))
    }
    Darwin.exit(code.rawValue)
}

private func writeAll(_ bytes: Data, to descriptor: Int32) throws {
    try bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let result = Darwin.write(
                descriptor,
                buffer.baseAddress?.advanced(by: offset),
                buffer.count - offset
            )
            if result > 0 {
                offset += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }
}

private func readExactly(
    _ byteCount: Int,
    from descriptor: Int32
) throws -> Data {
    guard byteCount >= 0 else { throw CocoaError(.fileReadCorruptFile) }
    var result = Data(count: byteCount)
    var offset = 0
    try result.withUnsafeMutableBytes { buffer in
        while offset < byteCount {
            let count = Darwin.read(
                descriptor,
                buffer.baseAddress?.advanced(by: offset),
                byteCount - offset
            )
            if count > 0 {
                offset += count
            } else if count < 0, errno == EINTR {
                continue
            } else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
    return result
}

private func requireEOF(_ descriptor: Int32) throws {
    var byte: UInt8 = 0
    while true {
        let count = Darwin.read(descriptor, &byte, 1)
        if count == 0 { return }
        if count < 0, errno == EINTR { continue }
        throw CocoaError(.fileReadCorruptFile)
    }
}

private func readBoundedToEOF(
    from descriptor: Int32,
    maximumBytes: Int
) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        if count == 0 { return result }
        if count < 0, errno == EINTR { continue }
        guard count > 0, result.count + count <= maximumBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        result.append(contentsOf: buffer.prefix(count))
    }
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
    }
}

private func exactIdentity(_ value: String) -> Bool {
    !value.isEmpty
        && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
        && !value.contains("\0")
}

private func canonicalJSON(_ object: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
}

private func writeJSONObject(_ object: Any) -> Never {
    do {
        var bytes = try canonicalJSON(object)
        bytes.append(0x0a)
        try writeAll(bytes, to: STDOUT_FILENO)
        Darwin.exit(EXIT_SUCCESS)
    } catch {
        fail(.outputFailure, "canonical-output-failed")
    }
}

private let rawArguments = Array(CommandLine.arguments.dropFirst())
if rawArguments == ["--loopforge-provider-self-test"] {
    writeJSONObject([
        "credentialTransport": "length-prefixed-fd-197",
        "invocationContextTransport": "canonical-json-fd-196",
        "operationalMode": "transport-veto-only",
        "productiveProviderBackends": [],
        "promptTransport": "exact-stdin",
        "protocolVersion": HarnessContract.protocolVersion,
        "schemaVersion": HarnessContract.schemaVersion,
    ] as [String: Any])
}

guard rawArguments.count == HarnessContract.orderedFlags.count * 2 else {
    fail(.invalidArguments, "argument-cardinality")
}
var values: [String: String] = [:]
for index in HarnessContract.orderedFlags.indices {
    let flag = rawArguments[index * 2]
    let value = rawArguments[index * 2 + 1]
    guard flag == HarnessContract.orderedFlags[index],
          values.updateValue(value, forKey: flag) == nil,
          !value.contains("\0") else {
        fail(.invalidArguments, "argument-order-or-duplication")
    }
}

guard values["--loopforge-provider-protocol"]
        == String(HarnessContract.protocolVersion),
      ["codex", "local", "api"].contains(values["--provider"] ?? ""),
      exactIdentity(values["--provider-reference"] ?? ""),
      exactIdentity(values["--model"] ?? ""),
      exactIdentity(values["--reasoning-effort"] ?? ""),
      ["readOnly", "workspaceOnly", "fullAccess"].contains(
        values["--sandbox"] ?? ""
      ),
      ["disabled", "enabled"].contains(values["--network"] ?? ""),
      values["--plugins"] == "disabled",
      values["--hidden-fan-out"] == "disabled",
      values["--invocation-context-fd"]
        == String(HarnessContract.contextDescriptor),
      values["--prompt-fd"] == String(STDIN_FILENO),
      let promptDigest = values["--prompt-digest"],
      isDigest(promptDigest),
      let promptByteText = values["--prompt-bytes"],
      let promptByteCount = Int(promptByteText),
      promptByteCount > 0,
      promptByteCount <= HarnessContract.maximumPromptBytes,
      let requestNonce = values["--request-nonce"],
      isDigest(requestNonce),
      let credentialMode = values["--credential-mode"],
      ["none", "opaqueProviderSecret"].contains(credentialMode),
      (credentialMode == "none"
        ? values["--credential-fd"] == "none"
        : values["--credential-fd"]
          == String(HarnessContract.credentialDescriptor)) else {
    fail(.invalidArguments, "argument-authority")
}

let contextBytes: Data
do {
    contextBytes = try readBoundedToEOF(
        from: HarnessContract.contextDescriptor,
        maximumBytes: HarnessContract.maximumContextBytes
    )
} catch {
    fail(.invalidContext, "context-read")
}
guard contextBytes.last == 0x0a else {
    fail(.invalidContext, "context-final-newline")
}
let contextBody = Data(contextBytes.dropLast())
guard !contextBody.isEmpty,
      let context = try? JSONSerialization.jsonObject(with: contextBody)
        as? [String: Any],
      (try? canonicalJSON(context)) == contextBody,
      Set(context.keys) == [
        "attemptID", "invocationDigest", "requestNonce", "runID",
        "schemaVersion",
      ],
      context["schemaVersion"] as? Int == HarnessContract.schemaVersion,
      let runID = context["runID"] as? String,
      exactIdentity(runID),
      let attemptID = context["attemptID"] as? String,
      exactIdentity(attemptID),
      let invocationDigest = context["invocationDigest"] as? String,
      isDigest(invocationDigest),
      context["requestNonce"] as? String == requestNonce else {
    fail(.invalidContext, "context-canonicality-or-binding")
}

let prompt: Data
do {
    prompt = try readExactly(promptByteCount, from: STDIN_FILENO)
    try requireEOF(STDIN_FILENO)
} catch {
    fail(.invalidPrompt, "prompt-read-or-length")
}
guard digest(prompt) == promptDigest else {
    fail(.invalidPrompt, "prompt-digest")
}

if credentialMode == "opaqueProviderSecret" {
    do {
        let lengthBytes = try readExactly(
            MemoryLayout<UInt64>.size,
            from: HarnessContract.credentialDescriptor
        )
        let count = lengthBytes.withUnsafeBytes {
            UInt64(bigEndian: $0.load(as: UInt64.self))
        }
        guard count > 0,
              count <= UInt64(HarnessContract.maximumCredentialBytes),
              count <= UInt64(Int.max) else {
            throw CocoaError(.fileReadTooLarge)
        }
        var secret = try readExactly(
            Int(count),
            from: HarnessContract.credentialDescriptor
        )
        try requireEOF(HarnessContract.credentialDescriptor)
        secret.resetBytes(in: 0..<secret.count)
    } catch {
        fail(.invalidCredential, "credential-transport")
    }
}

let resultMaterial = Data([
    "loopforge.provider-harness.v2.transport-veto",
    runID,
    attemptID,
    invocationDigest,
    requestNonce,
    promptDigest,
].joined(separator: "\u{1f}").utf8)
let threadMaterial = Data(
    "\(runID)\u{1f}\(attemptID)\u{1f}\(invocationDigest)".utf8
)
let terminal: [String: Any] = [
    "invocationDigest": invocationDigest,
    "proposedDisposition": "blocked",
    "requestNonce": requestNonce,
    "resultDigest": digest(resultMaterial),
    "schemaVersion": 1,
    "sequence": 0,
    "threadID": "loopforge-v2-\(digest(threadMaterial).prefix(24))",
    "type": "terminal",
]
let diagnostic = "loopforge-provider-harness:productive-provider-backend-unavailable\n"
_ = diagnostic.withCString {
    Darwin.write(STDERR_FILENO, $0, strlen($0))
}
writeJSONObject(terminal)
