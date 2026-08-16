import Darwin

@_silgen_name("_NSGetEnviron")
private func kernelProcessEnvironmentPointer()
  -> UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?>

signal(SIGTERM) { _ in Darwin.exit(0) }

private func canonicalRequestValue(
  _ key: String,
  in bytes: [UInt8]
) -> String? {
  let prefix = Array("\"\(key)\":\"".utf8)
  guard
    let prefixStart = bytes.indices.first(where: {
      bytes[$0...].starts(with: prefix)
    })
  else {
    return nil
  }
  let valueStart = prefixStart + prefix.count
  guard valueStart <= bytes.endIndex,
    let valueEnd = bytes[valueStart...].firstIndex(of: 0x22)
  else {
    return nil
  }
  return String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)
}

/// Returns true only when the native process ceiling rejects even one direct
/// child. Provider-mode tests call this after consuming every fixed transport
/// so a green launch proves that hidden fan-out is mechanically impossible.
private func childProcessCreationIsDenied() -> Bool {
  let path = "/usr/bin/true"
  guard let duplicated = strdup(path) else { return false }
  defer { Darwin.free(duplicated) }
  var child: pid_t = 0
  var vector: [UnsafeMutablePointer<CChar>?] = [duplicated, nil]
  let result = vector.withUnsafeMutableBufferPointer { arguments in
    path.withCString { executable in
      Darwin.posix_spawn(
        &child,
        executable,
        nil,
        nil,
        arguments.baseAddress!,
        kernelProcessEnvironmentPointer().pointee
      )
    }
  }
  if result == EAGAIN { return true }
  if result == 0, child > 0 {
    var status: Int32 = 0
    _ = Darwin.waitpid(child, &status, 0)
  }
  return false
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--exit":
  let code = arguments.dropFirst().first.flatMap(Int32.init) ?? 0
  Darwin.exit(code)
case "--sleep-seconds":
  let seconds = arguments.dropFirst().first.flatMap(Double.init) ?? 0
  if seconds > 0 {
    let totalNanoseconds = UInt64(seconds * 1_000_000_000)
    var request = timespec(
      tv_sec: Int(totalNanoseconds / 1_000_000_000),
      tv_nsec: Int(totalNanoseconds % 1_000_000_000)
    )
    while true {
      var remaining = timespec()
      if nanosleep(&request, &remaining) == 0 { break }
      if errno != EINTR { break }
      request = remaining
    }
  }
  Darwin.exit(0)
case "--emit-verifier-result-and-sleep":
  guard arguments.count == 5 || arguments.count == 6 else {
    Darwin.exit(66)
  }
  let resultCode = arguments[1]
  let evidenceDigest = arguments[2]
  let seconds = Double(arguments[3]) ?? 0
  guard !resultCode.isEmpty,
    evidenceDigest.utf8.count == 64,
    evidenceDigest.utf8.allSatisfy({
      (48...57).contains($0) || (97...102).contains($0)
    }),
    seconds >= 0,
    !arguments[4].isEmpty,
    arguments.count == 5
      || (arguments[5].utf8.count == 64
        && arguments[5].utf8.allSatisfy({
          (48...57).contains($0) || (97...102).contains($0)
        }))
  else {
    Darwin.exit(67)
  }
  let candidateRoot = Darwin.open(
    arguments[4],
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  )
  guard candidateRoot >= 0 else { Darwin.exit(69) }
  var candidateStatus = stat()
  guard fstat(candidateRoot, &candidateStatus) == 0,
    candidateStatus.st_mode & S_IFMT == S_IFDIR
  else {
    _ = Darwin.close(candidateRoot)
    Darwin.exit(70)
  }
  _ = Darwin.close(candidateRoot)
  let envelopeText =
    "{\"evidenceDigest\":\""
    + evidenceDigest
    + "\",\"resultCode\":\""
    + resultCode
    + "\",\"schemaVersion\":1}\n"
  let envelope = Array(envelopeText.utf8)
  var written = 0
  while written < envelope.count {
    let count = envelope.withUnsafeBytes {
      Darwin.write(
        STDOUT_FILENO,
        $0.baseAddress?.advanced(by: written),
        envelope.count - written
      )
    }
    if count > 0 {
      written += count
    } else if count < 0, errno == EINTR {
      continue
    } else {
      Darwin.exit(68)
    }
  }
  if seconds > 0 {
    let totalNanoseconds = UInt64(seconds * 1_000_000_000)
    var request = timespec(
      tv_sec: Int(totalNanoseconds / 1_000_000_000),
      tv_nsec: Int(totalNanoseconds % 1_000_000_000)
    )
    while true {
      var remaining = timespec()
      if nanosleep(&request, &remaining) == 0 { break }
      if errno != EINTR { break }
      request = remaining
    }
  }
  Darwin.exit(0)
case "--dump-environment":
  var entries: [String] = []
  if var cursor = kernelProcessEnvironmentPointer().pointee {
    while let entry = cursor.pointee {
      entries.append(String(cString: entry))
      cursor = cursor.advanced(by: 1)
    }
  }
  for entry in entries.sorted() {
    print(entry)
  }
  Darwin.exit(0)
case "--consume-external-dependency-request":
  guard arguments.count == 3,
    arguments[1] == "--request",
    arguments[2] == "/dev/stdin"
  else {
    Darwin.exit(82)
  }
  var requestBytes = 0
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while true {
    let count = buffer.withUnsafeMutableBytes {
      Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
    }
    if count > 0 {
      requestBytes += count
    } else if count == 0 {
      break
    } else if errno != EINTR {
      Darwin.exit(83)
    }
  }
  guard requestBytes > 0 else { Darwin.exit(84) }
  let response = Array("external-dependency-request-read\n".utf8)
  let responseResult = response.withUnsafeBytes {
    Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count)
  }
  guard responseResult == response.count else { Darwin.exit(85) }
  Darwin.exit(0)
case "--observe-external-dependency":
  guard arguments.count == 3,
    arguments[1] == "--request",
    arguments[2] == "/dev/stdin"
  else {
    Darwin.exit(86)
  }
  var requestData: [UInt8] = []
  var buffer = [UInt8](repeating: 0, count: 4_096)
  while true {
    let count = buffer.withUnsafeMutableBytes {
      Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
    }
    if count > 0 {
      requestData.append(contentsOf: buffer.prefix(count))
    } else if count == 0 {
      break
    } else if errno != EINTR {
      Darwin.exit(87)
    }
  }
  guard
    let dependencyID = canonicalRequestValue(
      "dependencyID",
      in: requestData
    ),
    let evidenceRecipeID = canonicalRequestValue(
      "evidenceRecipeID",
      in: requestData
    ),
    let requestNonce = canonicalRequestValue(
      "requestNonce",
      in: requestData
    ),
    !dependencyID.isEmpty,
    !evidenceRecipeID.isEmpty,
    requestNonce.utf8.count == 64,
    requestNonce.utf8.allSatisfy({
      (48...57).contains($0) || (97...102).contains($0)
    })
  else {
    Darwin.exit(88)
  }
  let response = Array(
    ("{\"dependencyID\":\"" + dependencyID
      + "\",\"evidenceDigest\":\"" + String(repeating: "e", count: 64)
      + "\",\"evidenceRecipeID\":\"" + evidenceRecipeID
      + "\",\"requestNonce\":\"" + requestNonce
      + "\",\"resultCode\":\"available\",\"schemaVersion\":1}\n").utf8
  )
  var written = 0
  while written < response.count {
    let count = response.withUnsafeBytes {
      Darwin.write(
        STDOUT_FILENO,
        $0.baseAddress?.advanced(by: written),
        response.count - written
      )
    }
    if count > 0 {
      written += count
    } else if count < 0, errno == EINTR {
      continue
    } else {
      Darwin.exit(90)
    }
  }
  Darwin.exit(0)
case "--emit-bytes":
  let count = arguments.dropFirst().first.flatMap(Int.init) ?? 0
  guard count >= 0, count <= 16 * 1_024 * 1_024 else { Darwin.exit(78) }
  let bytes = [UInt8](repeating: 0x58, count: min(count, 64 * 1_024))
  var remaining = count
  while remaining > 0 {
    let amount = min(remaining, bytes.count)
    let written = bytes.withUnsafeBytes {
      Darwin.write(STDOUT_FILENO, $0.baseAddress, amount)
    }
    if written > 0 {
      remaining -= written
    } else if written < 0, errno == EINTR {
      continue
    } else {
      Darwin.exit(79)
    }
  }
  Darwin.exit(0)
case "--expect-child-process-denied":
  Darwin.exit(childProcessCreationIsDenied() ? 0 : 80)
case "--exec-with-context-fd":
  guard arguments.count >= 4 else { Darwin.exit(92) }
  let context = Darwin.open(arguments[1], O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
  guard context >= 0 else { Darwin.exit(93) }
  guard Darwin.dup2(context, 196) == 196 else {
    _ = Darwin.close(context)
    Darwin.exit(94)
  }
  _ = Darwin.close(context)
  let executable = arguments[2]
  var vector: [UnsafeMutablePointer<CChar>?] = arguments.dropFirst(2).map {
    strdup($0)
  }
  guard vector.allSatisfy({ $0 != nil }) else { Darwin.exit(95) }
  vector.append(nil)
  let execResult = vector.withUnsafeMutableBufferPointer { values in
    executable.withCString {
      Darwin.execv($0, values.baseAddress!)
    }
  }
  for value in vector where value != nil { Darwin.free(value) }
  Darwin.exit(execResult == -1 ? 96 : 97)
case "--emit-worker-result":
  guard arguments.count == 6 else { Darwin.exit(65) }
  let invocationDigest = arguments[1]
  let requestNonce = arguments[2]
  let threadID = arguments[3]
  let proposedDisposition = arguments[4]
  let resultDigest = arguments[5]
  let validDigest: (String) -> Bool = { value in
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (97...102).contains(byte)
      }
  }
  let validThread =
    !threadID.isEmpty
    && threadID.utf8.allSatisfy { byte in
      (48...57).contains(byte) || (65...90).contains(byte)
        || (97...122).contains(byte) || byte == 45 || byte == 95
    }
  let validDisposition = [
    "completed", "continuationNeeded", "blocked", "failed",
    "interrupted", "malformed",
  ].contains(proposedDisposition)
  guard validDigest(invocationDigest),
    validDigest(requestNonce),
    validDigest(resultDigest),
    validThread,
    validDisposition
  else { Darwin.exit(66) }
  print(
    "{\"invocationDigest\":\"\(invocationDigest)\","
      + "\"proposedDisposition\":\"\(proposedDisposition)\","
      + "\"requestNonce\":\"\(requestNonce)\"," + "\"resultDigest\":\"\(resultDigest)\","
      + "\"schemaVersion\":1,\"sequence\":0,"
      + "\"threadID\":\"\(threadID)\",\"type\":\"terminal\"}"
  )
  Darwin.exit(0)
case "--loopforge-provider-protocol":
  guard arguments.count >= 4, arguments[1] == "2" else { Darwin.exit(70) }
  var options: [String: String] = [:]
  var index = 2
  while index + 1 < arguments.count {
    let key = arguments[index]
    guard key.hasPrefix("--"), options[key] == nil else { Darwin.exit(71) }
    options[key] = arguments[index + 1]
    index += 2
  }
  guard index == arguments.count,
    options["--invocation-context-fd"] == "196",
    options["--prompt-fd"] == "0",
    let expectedPromptBytes = options["--prompt-bytes"].flatMap(Int.init),
    expectedPromptBytes > 0
  else { Darwin.exit(72) }

  func readExactly(_ descriptor: Int32, count: Int) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: count)
    var consumed = 0
    while consumed < bytes.count {
      let result = bytes.withUnsafeMutableBytes { buffer in
        Darwin.read(
          descriptor,
          buffer.baseAddress?.advanced(by: consumed),
          buffer.count - consumed
        )
      }
      if result > 0 {
        consumed += result
      } else if result < 0, errno == EINTR {
        continue
      } else {
        return nil
      }
    }
    return bytes
  }
  guard readExactly(STDIN_FILENO, count: expectedPromptBytes) != nil else {
    Darwin.exit(73)
  }

  func readToEnd(_ descriptor: Int32, maximumBytes: Int) -> [UInt8]? {
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 512)
    while true {
      let result = buffer.withUnsafeMutableBytes {
        Darwin.read(descriptor, $0.baseAddress, $0.count)
      }
      if result > 0 {
        guard bytes.count + result <= maximumBytes else { return nil }
        bytes.append(contentsOf: buffer.prefix(result))
      } else if result == 0 {
        return bytes
      } else if errno != EINTR {
        return nil
      }
    }
  }
  guard let invocationContext = readToEnd(196, maximumBytes: 4 * 1_024),
    invocationContext.last == 0x0a,
    let invocationDigest = canonicalRequestValue(
      "invocationDigest",
      in: invocationContext
    ),
    let contextRequestNonce = canonicalRequestValue(
      "requestNonce",
      in: invocationContext
    ),
    contextRequestNonce == options["--request-nonce"],
    invocationDigest.utf8.count == 64,
    invocationDigest.utf8.allSatisfy({
      (48...57).contains($0) || (97...102).contains($0)
    }),
    contextRequestNonce.utf8.count == 64,
    contextRequestNonce.utf8.allSatisfy({
      (48...57).contains($0) || (97...102).contains($0)
    })
  else {
    Darwin.exit(78)
  }

  let credentialReceived: Bool
  switch options["--credential-mode"] {
  case "none":
    guard options["--credential-fd"] == "none" else { Darwin.exit(74) }
    credentialReceived = false
  case "opaqueProviderSecret":
    guard options["--credential-fd"] == "197",
      let lengthBytes = readExactly(197, count: 8)
    else {
      Darwin.exit(75)
    }
    let length = lengthBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    guard length > 0, length <= 8 * 1_024,
      var credential = readExactly(197, count: Int(length))
    else {
      Darwin.exit(76)
    }
    credential.withUnsafeMutableBytes { buffer in
      if let base = buffer.baseAddress {
        _ = Darwin.memset(base, 0, buffer.count)
      }
    }
    credentialReceived = true
  default:
    Darwin.exit(77)
  }
  guard childProcessCreationIsDenied() else { Darwin.exit(91) }
  if options["--model"] == "fixture-live-termination-model" {
    Darwin.sleep(30)
  }
  let resultDigest = String(repeating: credentialReceived ? "d" : "c", count: 64)
  print(
    "{\"invocationDigest\":\"\(invocationDigest)\","
      + "\"proposedDisposition\":\"completed\","
      + "\"requestNonce\":\"\(contextRequestNonce)\","
      + "\"resultDigest\":\"\(resultDigest)\","
      + "\"schemaVersion\":1,\"sequence\":0,"
      + "\"threadID\":\"fixture-provider\",\"type\":\"terminal\"}"
  )
  Darwin.exit(0)
default:
  Darwin.exit(64)
}
