import Foundation
import XCTest
@testable import LoopForge

final class KernelWorkerResultParserTests: XCTestCase {
    func testCanonicalStreamProducesDigestBoundProposalReceipt() throws {
        let observation = envelope(
            type: .event,
            sequence: 0,
            payloadDigest: digest("c")
        )
        let terminal = envelope(
            type: .terminal,
            sequence: 1,
            proposedDisposition: .completed,
            resultDigest: digest("d")
        )
        let stdout = try stream([observation, terminal])
        let stderr = Data("bounded diagnostic".utf8)

        let receipt = try KernelWorkerResultParser().parse(
            stdout: stdout,
            stderr: stderr,
            expectation: expectation(),
            receiptID: ReceiptID("parse-receipt")
        )

        XCTAssertEqual(receipt.parserIdentityDigest, KernelWorkerResultParser.parserIdentityDigest)
        XCTAssertEqual(receipt.threadID, "thread-1")
        XCTAssertEqual(receipt.eventCount, 2)
        XCTAssertEqual(receipt.proposedDisposition, .completed)
        XCTAssertEqual(receipt.proposedResultDigest, digest("d"))
        XCTAssertEqual(
            receipt.stdoutContentDigest,
            KernelWorkerResultParser.contentDigest(stdout)
        )
        XCTAssertEqual(
            receipt.stderrContentDigest,
            KernelWorkerResultParser.contentDigest(stderr)
        )
        XCTAssertEqual(
            receipt.terminalEnvelopeDigest,
            KernelWorkerResultParser.contentDigest(
                try KernelWorkerResultParser.canonicalLine(terminal)
            )
        )
        XCTAssertEqual(receipt.nativeExit, expectation().nativeExit)
    }

    func testNonCanonicalUnknownAndNarrativeLinesFailClosed() throws {
        let terminalLine = try KernelWorkerResultParser.canonicalLine(
            envelope(
                type: .terminal,
                sequence: 0,
                proposedDisposition: .completed,
                resultDigest: digest("d")
            )
        )
        let nonCanonical = Data(" \(String(decoding: terminalLine, as: UTF8.self))\n".utf8)
        XCTAssertParserError(.nonCanonicalJSON) {
            try self.parse(nonCanonical)
        }

        var unknownObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: terminalLine) as? [String: Any]
        )
        unknownObject["narrative"] = "trust me"
        let unknown = try JSONSerialization.data(
            withJSONObject: unknownObject,
            options: [.sortedKeys]
        ) + Data([0x0a])
        XCTAssertParserError(.invalidJSON) {
            try self.parse(unknown)
        }

        XCTAssertParserError(.invalidJSON) {
            try self.parse(Data("worker says complete\n".utf8))
        }
    }

    func testTruncationSequenceThreadNonceAndTerminalRulesFailClosed() throws {
        let terminal = envelope(
            type: .terminal,
            sequence: 0,
            proposedDisposition: .completed,
            resultDigest: digest("d")
        )
        let terminalLine = try KernelWorkerResultParser.canonicalLine(terminal)
        XCTAssertParserError(.missingFinalNewline) {
            try self.parse(terminalLine)
        }

        let sequenceGap = envelope(
            type: .terminal,
            sequence: 1,
            proposedDisposition: .completed,
            resultDigest: digest("d")
        )
        XCTAssertParserError(.sequenceMismatch) {
            try self.parse(try self.stream([sequenceGap]))
        }

        let differentThread = envelope(
            type: .terminal,
            sequence: 1,
            threadID: "thread-2",
            proposedDisposition: .completed,
            resultDigest: digest("d")
        )
        XCTAssertParserError(.threadIdentityMismatch) {
            try self.parse(try self.stream([
                self.envelope(type: .event, sequence: 0, payloadDigest: self.digest("c")),
                differentThread
            ]))
        }

        let wrongNonce = envelope(
            type: .terminal,
            sequence: 0,
            nonce: digest("e"),
            proposedDisposition: .completed,
            resultDigest: digest("d")
        )
        XCTAssertParserError(.nonceMismatch) {
            try self.parse(try self.stream([wrongNonce]))
        }

        XCTAssertParserError(.duplicateTerminal) {
            try self.parse(try self.stream([
                terminal,
                self.envelope(
                    type: .terminal,
                    sequence: 1,
                    proposedDisposition: .failed,
                    resultDigest: self.digest("e")
                )
            ]))
        }

        XCTAssertParserError(.semanticDataAfterTerminal) {
            try self.parse(try self.stream([
                terminal,
                self.envelope(type: .event, sequence: 1, payloadDigest: self.digest("e"))
            ]))
        }

        XCTAssertParserError(.missingTerminal) {
            try self.parse(try self.stream([
                self.envelope(type: .event, sequence: 0, payloadDigest: self.digest("c"))
            ]))
        }
    }

    func testUnsuccessfulNativeExitAndBoundedInputCannotProduceProposal() throws {
        var unsuccessful = expectation()
        unsuccessful.nativeExit.exitCode = 7
        XCTAssertParserError(.nativeExitUnsuccessful) {
            try KernelWorkerResultParser().parse(
                stdout: try self.stream([
                    self.envelope(
                        type: .terminal,
                        sequence: 0,
                        proposedDisposition: .completed,
                        resultDigest: self.digest("d")
                    )
                ]),
                stderr: Data(),
                expectation: unsuccessful,
                receiptID: ReceiptID("parse-receipt")
            )
        }

        let limits = KernelWorkerResultParserLimits(
            maximumStdoutBytes: 8,
            maximumStderrBytes: 8,
            maximumLineBytes: 8,
            maximumEvents: 1
        )
        XCTAssertParserError(.outputTooLarge) {
            try KernelWorkerResultParser().parse(
                stdout: Data(repeating: 0x61, count: 9),
                stderr: Data(),
                expectation: self.expectation(),
                receiptID: ReceiptID("parse-receipt"),
                limits: limits
            )
        }

        let invalidLimits = KernelWorkerResultParserLimits(
            maximumStdoutBytes: -1,
            maximumStderrBytes: 0,
            maximumLineBytes: 1,
            maximumEvents: 1
        )
        XCTAssertParserError(.invalidLimits) {
            try KernelWorkerResultParser().parse(
                stdout: try self.stream([
                    self.envelope(
                        type: .terminal,
                        sequence: 0,
                        proposedDisposition: .completed,
                        resultDigest: self.digest("d")
                    )
                ]),
                stderr: Data(),
                expectation: self.expectation(),
                receiptID: ReceiptID("parse-receipt"),
                limits: invalidLimits
            )
        }
    }

    func testRetainedFileReaderRejectsTraversalAndSymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KernelWorkerResultParserTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        let outside = root.deletingLastPathComponent().appendingPathComponent(
            "outside-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data().write(to: outside)
        let symlink = root.appendingPathComponent("stderr.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        let stdout = root.appendingPathComponent("stdout.jsonl")
        try stream([
            envelope(
                type: .terminal,
                sequence: 0,
                proposedDisposition: .completed,
                resultDigest: digest("d")
            )
        ]).write(to: stdout)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stdout.path
        )

        XCTAssertParserError(.invalidFileName) {
            try KernelWorkerResultParser().parseRetainedFiles(
                directoryPath: root.path,
                standardOutputFileName: "../outside",
                standardErrorFileName: "stderr.txt",
                expectation: self.expectation(),
                receiptID: ReceiptID("parse-receipt")
            )
        }
        XCTAssertParserError(.unsafeFile) {
            try KernelWorkerResultParser().parseRetainedFiles(
                directoryPath: root.path,
                standardOutputFileName: "stdout.jsonl",
                standardErrorFileName: "stderr.txt",
                expectation: self.expectation(),
                receiptID: ReceiptID("parse-receipt")
            )
        }
    }

    private func parse(_ stdout: Data) throws -> KernelWorkerResultParseReceipt {
        try KernelWorkerResultParser().parse(
            stdout: stdout,
            stderr: Data(),
            expectation: expectation(),
            receiptID: ReceiptID("parse-receipt")
        )
    }

    private func stream(_ envelopes: [KernelWorkerStreamEnvelope]) throws -> Data {
        var result = Data()
        for envelope in envelopes {
            result.append(try KernelWorkerResultParser.canonicalLine(envelope))
            result.append(0x0a)
        }
        return result
    }

    private func envelope(
        type: KernelWorkerStreamEnvelopeKind,
        sequence: UInt64,
        threadID: String = "thread-1",
        nonce: ContentDigest? = nil,
        payloadDigest: ContentDigest? = nil,
        proposedDisposition: KernelWorkerProposedDisposition? = nil,
        resultDigest: ContentDigest? = nil
    ) -> KernelWorkerStreamEnvelope {
        KernelWorkerStreamEnvelope(
            invocationDigest: digest("a"),
            payloadDigest: payloadDigest,
            proposedDisposition: proposedDisposition,
            requestNonce: nonce ?? digest("b"),
            resultDigest: resultDigest,
            schemaVersion: 1,
            sequence: sequence,
            threadID: threadID,
            type: type
        )
    }

    private func expectation() -> KernelWorkerResultParseExpectation {
        let identity = RuntimeExternalIdentity(
            stableDigest: digest("f"),
            processID: 101,
            processStartMonotonicNanoseconds: 10,
            parentResourceID: nil
        )
        let handle = ManagedProcessHandle(
            runID: KernelRunID("run"),
            resourceID: OwnedResourceID("resource"),
            leaseID: ResourceLeaseID("lease"),
            processID: 101,
            processGroupID: 101,
            externalIdentity: identity
        )
        return KernelWorkerResultParseExpectation(
            runID: handle.runID,
            attemptID: AttemptID("attempt"),
            resourceID: handle.resourceID,
            leaseID: handle.leaseID,
            bindingReceiptID: ReceiptID("binding"),
            releaseReceiptID: ReceiptID("release"),
            invocationDigest: digest("a"),
            requestNonce: digest("b"),
            nativeExit: ManagedProcessExitReceipt(
                handle: handle,
                observedAtMonotonicNanoseconds: 20,
                exitCode: 0,
                terminationSignal: nil
            )
        )
    }

    private func digest(_ character: Character) -> ContentDigest {
        ContentDigest(String(repeating: String(character), count: 64))
    }

    private func XCTAssertParserError<T>(
        _ expected: KernelWorkerResultParserError,
        operation: () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try operation()
            XCTFail("Expected parser error \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? KernelWorkerResultParserError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
