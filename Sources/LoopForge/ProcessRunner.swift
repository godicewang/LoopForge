import Foundation
import Darwin

struct ProcessResult {
    let exitCode: Int32
    let elapsed: TimeInterval
    let stdout: String
    let stderr: String
}

enum ProcessRunnerError: LocalizedError {
    case timedOut(TimeInterval)
    case stalled(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "The child process exceeded its \(seconds.compactDuration) time limit."
        case .stalled(let reason):
            return reason
        }
    }
}

private final class LineBuffer {
    private let lock = NSLock()
    private var data = Data()
    private var retained: [String] = []
    private var retainedBytes = 0
    private var pendingWasTruncated = false
    private let limit: Int
    private let maximumLineBytes: Int
    private let maximumRetainedBytes: Int

    init(
        limit: Int = 4_000,
        maximumLineBytes: Int = 4 * 1_024 * 1_024,
        maximumRetainedBytes: Int = 8 * 1_024 * 1_024
    ) {
        self.limit = limit
        self.maximumLineBytes = maximumLineBytes
        self.maximumRetainedBytes = maximumRetainedBytes
    }

    func append(_ chunk: Data, callback: (String) -> Void) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        var lines: [String] = []
        var segmentStart = chunk.startIndex
        for index in chunk.indices where chunk[index] == 10 || chunk[index] == 13 {
            appendPending(chunk[segmentStart..<index])
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                let safeLine = boundedLine(line)
                lines.append(safeLine)
                retain(safeLine)
            }
            data.removeAll(keepingCapacity: true)
            pendingWasTruncated = false
            segmentStart = chunk.index(after: index)
        }
        appendPending(chunk[segmentStart..<chunk.endIndex])
        lock.unlock()
        lines.forEach(callback)
    }

    func flush(callback: (String) -> Void) {
        lock.lock()
        let decoded = String(data: data, encoding: .utf8)
        let line = decoded.map(boundedLine)
        data.removeAll()
        pendingWasTruncated = false
        if let line, !line.isEmpty { retain(line) }
        let output = retained.joined(separator: "\n")
        _cachedOutput = output
        lock.unlock()
        if let line, !line.isEmpty { callback(line) }
    }

    private var _cachedOutput = ""
    var output: String {
        lock.lock(); defer { lock.unlock() }
        return _cachedOutput.isEmpty ? retained.joined(separator: "\n") : _cachedOutput
    }

    private func boundedLine(_ line: String) -> String {
        let marker = "…[output truncated]…"
        let source = pendingWasTruncated ? marker + line : line
        guard source.utf8.count > maximumLineBytes else { return source }
        return marker + String(source.suffix(maximumLineBytes / 2))
    }

    private func retain(_ line: String) {
        retained.append(line)
        retainedBytes += line.utf8.count + 1
        while retained.count > limit || retainedBytes > maximumRetainedBytes {
            guard !retained.isEmpty else { break }
            retainedBytes -= retained.removeFirst().utf8.count + 1
        }
    }

    private func appendPending(_ fragment: Data.SubSequence) {
        guard !fragment.isEmpty else { return }

        // Stay allocation-free for ordinary output. Once a single line
        // crosses the limit, retain a rolling tail and compact only after the
        // buffer has grown back to the full limit. The previous implementation
        // copied a multi-megabyte Data value for every small pipe chunk, which
        // made a 25 MB no-newline child output disproportionately expensive on
        // slower/shared machines.
        if data.count + fragment.count <= maximumLineBytes {
            data.append(contentsOf: fragment)
            return
        }

        let tailTarget = max(1, maximumLineBytes / 2)
        if fragment.count >= tailTarget {
            data = Data(fragment.suffix(tailTarget))
        } else {
            let retainedTailCount = max(0, tailTarget - fragment.count)
            data = Data(data.suffix(retainedTailCount))
            data.append(contentsOf: fragment)
        }
        pendingWasTruncated = true
    }
}

final class ProcessRunner {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        stdin: Data? = nil,
        timeout: TimeInterval? = nil,
        watchdog: ProcessWatchdog? = nil,
        onStdout: @escaping (String) -> Void = { _ in },
        onStderr: @escaping (String) -> Void = { _ in }
    ) async throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let stdoutBuffer = LineBuffer()
        let stderrBuffer = LineBuffer()
        let startedAt = Date()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if stdin != nil { process.standardInput = stdinPipe }
        process.currentDirectoryURL = currentDirectory
        if let environment { process.environment = environment }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let completion = ProcessCompletionGate()
                let timeoutWorkItem = timeout.flatMap { seconds -> DispatchWorkItem? in
                    guard seconds > 0 else { return nil }
                    return DispatchWorkItem {
                        guard completion.claim() else { return }
                        watchdog?.disarm()
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        stdoutBuffer.flush(callback: onStdout)
                        stderrBuffer.flush(callback: onStderr)
                        stopProcessWithEscalation(process)
                        continuation.resume(throwing: ProcessRunnerError.timedOut(seconds))
                    }
                }
                watchdog?.arm { reason in
                    guard completion.claim() else { return }
                    timeoutWorkItem?.cancel()
                    watchdog?.disarm()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stdoutBuffer.flush(callback: onStdout)
                    stderrBuffer.flush(callback: onStderr)
                    stopProcessWithEscalation(process)
                    continuation.resume(throwing: ProcessRunnerError.stalled(reason))
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    stdoutBuffer.append(handle.availableData, callback: onStdout)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    stderrBuffer.append(handle.availableData, callback: onStderr)
                }
                process.terminationHandler = { process in
                    guard completion.claim() else { return }
                    timeoutWorkItem?.cancel()
                    watchdog?.disarm()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if let remaining = try? stdoutPipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                        stdoutBuffer.append(remaining, callback: onStdout)
                    }
                    if let remaining = try? stderrPipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                        stderrBuffer.append(remaining, callback: onStderr)
                    }
                    stdoutBuffer.flush(callback: onStdout)
                    stderrBuffer.flush(callback: onStderr)
                    let result = ProcessResult(
                        exitCode: process.terminationStatus,
                        elapsed: Date().timeIntervalSince(startedAt),
                        stdout: stdoutBuffer.output,
                        stderr: stderrBuffer.output
                    )
                    continuation.resume(returning: result)
                }

                do {
                    try process.run()
                    // The child owns duplicated write descriptors after launch. Closing the
                    // parent's copies is essential: otherwise readToEnd() can wait forever
                    // after a short-lived command such as `codex --version` exits.
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    if stdin != nil { try? stdinPipe.fileHandleForReading.close() }
                    if let stdin {
                        stdinPipe.fileHandleForWriting.write(stdin)
                        try? stdinPipe.fileHandleForWriting.close()
                    }
                    if let timeoutWorkItem, let timeout {
                        DispatchQueue.global().asyncAfter(
                            deadline: .now() + timeout,
                            execute: timeoutWorkItem
                        )
                    }
                } catch {
                    guard completion.claim() else { return }
                    timeoutWorkItem?.cancel()
                    watchdog?.disarm()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stdoutBuffer.flush(callback: onStdout)
                    stderrBuffer.flush(callback: onStderr)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            watchdog?.disarm()
            stopProcessWithEscalation(process)
        }
    }
}

private func stopProcessWithEscalation(_ process: Process) {
    let processIdentifier = process.processIdentifier
    guard processIdentifier > 0 else { return }
    let tree = ProcessTreeStopper(rootPID: processIdentifier)
    tree.signal(SIGINT)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
        tree.signal(SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            tree.signal(SIGKILL)
        }
    }
}

/// Foundation's `Process.interrupt()` targets only the immediate shell or
/// Codex CLI. Agents routinely start compilers, test runners, Node hosts, and
/// simulator helpers beneath that process; killing just the root reparents
/// those descendants to launchd, so they can keep consuming CPU after the
/// task or app has exited. Capture the owned tree before signalling the root,
/// then keep that snapshot through the full escalation window.
private final class ProcessTreeStopper: @unchecked Sendable {
    private let rootPID: pid_t
    private let lock = NSLock()
    private var knownPIDs = Set<pid_t>()

    init(rootPID: pid_t) {
        self.rootPID = rootPID
    }

    func signal(_ value: Int32) {
        let targets = snapshotTargets()
        for pid in targets where pid != getpid() {
            _ = Darwin.kill(pid, value)
        }
    }

    private func snapshotTargets() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }

        var visited = Set<pid_t>()
        var descendants: [pid_t] = []
        collectDescendants(
            of: rootPID,
            visited: &visited,
            deepestFirst: &descendants
        )
        knownPIDs.formUnion(visited)

        // A descendant may have been reparented after an earlier signal. Keep
        // signalling the previously captured PID until it exits.
        for pid in knownPIDs where pid != rootPID
            && !descendants.contains(pid)
            && processExists(pid) {
            descendants.append(pid)
        }
        if processExists(rootPID) {
            descendants.append(rootPID)
            knownPIDs.insert(rootPID)
        }
        return descendants
    }

    private func collectDescendants(
        of parent: pid_t,
        visited: inout Set<pid_t>,
        deepestFirst: inout [pid_t]
    ) {
        for child in childPIDs(of: parent)
            where child > 0 && visited.insert(child).inserted {
            collectDescendants(
                of: child,
                visited: &visited,
                deepestFirst: &deepestFirst
            )
            deepestFirst.append(child)
        }
    }

    private func childPIDs(of parent: pid_t) -> [pid_t] {
        var capacity = 32
        while capacity <= 4_096 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let count = Int(proc_listchildpids(
                parent,
                &buffer,
                Int32(capacity * MemoryLayout<pid_t>.stride)
            ))
            guard count > 0 else { return [] }
            if count < capacity {
                return Array(buffer.prefix(count))
            }
            capacity *= 2
        }
        return []
    }

    private func processExists(_ pid: pid_t) -> Bool {
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

private final class ProcessCompletionGate {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}
