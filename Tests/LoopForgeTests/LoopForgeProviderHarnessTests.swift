import Foundation
import XCTest
@testable import LoopForge

final class LoopForgeProviderHarnessTests: XCTestCase {
    func testSelfTestIsOneExactCanonicalLine() throws {
        let result = try runProcess(
            executableURL: harnessURL,
            arguments: ["--loopforge-provider-self-test"]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertEqual(
            KernelWorkerResultParser.contentDigest(result.stdout),
            NativeProviderHarnessSelectionLoader.expectedSelfTestSHA256
        )
        XCTAssertEqual(result.stdout.last, 0x0a)
        XCTAssertEqual(result.stdout.filter { $0 == 0x0a }.count, 1)
    }

    func testValidV2DescriptorTransportCanOnlyProposeBlocked() throws {
        let invocationDigest = digest("invocation")
        let nonce = digest("nonce")
        let prompt = Data("{\"task\":\"transport-boundary-test\"}\n".utf8)
        let result = try invokeHarness(
            invocationDigest: invocationDigest,
            nonce: nonce,
            prompt: prompt,
            advertisedPromptDigest: KernelWorkerResultParser.contentDigest(prompt)
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.last, 0x0a)
        XCTAssertEqual(result.stdout.filter { $0 == 0x0a }.count, 1)
        XCTAssertEqual(
            String(data: result.stderr, encoding: .utf8),
            "loopforge-provider-harness:productive-provider-backend-unavailable\n"
        )
        let line = Data(result.stdout.dropLast())
        let envelope = try JSONDecoder().decode(
            KernelWorkerStreamEnvelope.self,
            from: line
        )
        XCTAssertEqual(envelope.type, .terminal)
        XCTAssertEqual(envelope.sequence, 0)
        XCTAssertEqual(envelope.invocationDigest, invocationDigest)
        XCTAssertEqual(envelope.requestNonce, nonce)
        XCTAssertEqual(envelope.proposedDisposition, .blocked)
        XCTAssertNil(envelope.payloadDigest)
        XCTAssertNotNil(envelope.resultDigest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(try encoder.encode(envelope), line)
    }

    func testPromptDigestMismatchEmitsNoProposal() throws {
        let result = try invokeHarness(
            invocationDigest: digest("invocation"),
            nonce: digest("nonce"),
            prompt: Data("real prompt".utf8),
            advertisedPromptDigest: digest("different prompt")
        )

        XCTAssertEqual(result.status, 66)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertEqual(
            String(data: result.stderr, encoding: .utf8),
            "loopforge-provider-harness:prompt-digest\n"
        )
    }

    private func invokeHarness(
        invocationDigest: ContentDigest,
        nonce: ContentDigest,
        prompt: Data,
        advertisedPromptDigest: ContentDigest
    ) throws -> ProcessResult {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ProviderHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let contextURL = root.appendingPathComponent("context.json")
        let promptURL = root.appendingPathComponent("prompt.json")
        let context: [String: Any] = [
            "attemptID": "attempt-1",
            "invocationDigest": invocationDigest.rawValue,
            "requestNonce": nonce.rawValue,
            "runID": "run-1",
            "schemaVersion": 1,
        ]
        var contextBytes = try JSONSerialization.data(
            withJSONObject: context,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        contextBytes.append(0x0a)
        try contextBytes.write(to: contextURL, options: .atomic)
        try prompt.write(to: promptURL, options: .atomic)

        let arguments = [
            "--loopforge-provider-protocol", "2",
            "--provider", "local",
            "--provider-reference", "local-fixture",
            "--model", "fixture-model",
            "--reasoning-effort", "high",
            "--sandbox", "readOnly",
            "--network", "disabled",
            "--plugins", "disabled",
            "--hidden-fan-out", "disabled",
            "--invocation-context-fd", "196",
            "--prompt-fd", "0",
            "--prompt-digest", advertisedPromptDigest.rawValue,
            "--prompt-bytes", String(prompt.count),
            "--request-nonce", nonce.rawValue,
            "--credential-mode", "none",
            "--credential-fd", "none",
        ]
        let input = try FileHandle(forReadingFrom: promptURL)
        defer { try? input.close() }
        return try runProcess(
            executableURL: processFixtureURL,
            arguments: [
                "--exec-with-context-fd", contextURL.path, harnessURL.path,
            ] + arguments,
            standardInput: input
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        standardInput: Any? = nil
    ) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = [:]
        process.standardInput = standardInput
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private var harnessURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/LoopForgeProviderHarness")
            .standardizedFileURL
    }

    private var processFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/KernelProcessFixture")
            .standardizedFileURL
    }

    private func digest(_ value: String) -> ContentDigest {
        KernelWorkerResultParser.contentDigest(Data(value.utf8))
    }

    private struct ProcessResult {
        var status: Int32
        var stdout: Data
        var stderr: Data
    }
}
