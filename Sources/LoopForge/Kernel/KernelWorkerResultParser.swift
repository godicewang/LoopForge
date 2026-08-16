import CryptoKit
import Darwin
import Foundation

enum KernelWorkerProposedDisposition: String, Codable, Hashable, Sendable {
    case completed
    case continuationNeeded
    case blocked
    case failed
    case interrupted
    case malformed
}

enum KernelWorkerStreamEnvelopeKind: String, Codable, Hashable, Sendable {
    case event
    case terminal
}

/// The only JSON object accepted on retained worker stdout. Every line must be
/// the canonical sorted-key encoding of this structure. Optional fields are
/// made mutually exclusive by the parser according to `type`.
struct KernelWorkerStreamEnvelope: Codable, Hashable, Sendable {
    var invocationDigest: ContentDigest
    var payloadDigest: ContentDigest?
    var proposedDisposition: KernelWorkerProposedDisposition?
    var requestNonce: ContentDigest
    var resultDigest: ContentDigest?
    var schemaVersion: Int
    var sequence: UInt64
    var threadID: String
    var type: KernelWorkerStreamEnvelopeKind
}

struct KernelWorkerResultParseExpectation: Hashable, Sendable {
    var runID: KernelRunID
    var attemptID: AttemptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var bindingReceiptID: ReceiptID
    var releaseReceiptID: ReceiptID
    var invocationDigest: ContentDigest
    var requestNonce: ContentDigest
    var nativeExit: ManagedProcessExitReceipt
}

/// Safe journal evidence. The worker's disposition and result digest remain
/// proposals; a later reducer command must bind independent evidence before
/// either may alter orchestration state.
struct KernelWorkerResultParseReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var parserIdentityDigest: ContentDigest
    var runID: KernelRunID
    var attemptID: AttemptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var bindingReceiptID: ReceiptID
    var releaseReceiptID: ReceiptID
    var invocationDigest: ContentDigest
    var requestNonce: ContentDigest
    var threadID: String
    var eventCount: UInt64
    var stdoutContentDigest: ContentDigest
    var stderrContentDigest: ContentDigest
    var terminalEnvelopeDigest: ContentDigest
    var proposedDisposition: KernelWorkerProposedDisposition
    var proposedResultDigest: ContentDigest
    var nativeExit: ManagedProcessExitReceipt
}

/// An in-memory capability issued only by the strict parser. Journal commands
/// consume this wrapper rather than a freely constructible Codable receipt, so
/// decoded or caller-authored receipt values can never cross the write boundary.
struct KernelAuthorizedWorkerResultParse: Sendable {
    let receipt: KernelWorkerResultParseReceipt

    fileprivate init(receipt: KernelWorkerResultParseReceipt) {
        self.receipt = receipt
    }
}

enum KernelWorkerResultParserError: Error, Equatable {
    case invalidLimits
    case invalidExpectation
    case nativeExitUnsuccessful
    case outputFileMissing
    case invalidFileName
    case unsafeDirectory
    case unsafeFile
    case outputTooLarge
    case emptyOutput
    case missingFinalNewline
    case invalidUTF8
    case emptyLine
    case lineTooLarge
    case invalidJSON
    case nonCanonicalJSON
    case unsupportedSchema
    case invalidDigest
    case invocationMismatch
    case nonceMismatch
    case sequenceMismatch
    case invalidThreadIdentity
    case threadIdentityMismatch
    case invalidEventShape
    case invalidTerminalShape
    case duplicateTerminal
    case semanticDataAfterTerminal
    case missingTerminal
    case tooManyEvents
}

struct KernelWorkerResultParserLimits: Hashable, Sendable {
    var maximumStdoutBytes: Int
    var maximumStderrBytes: Int
    var maximumLineBytes: Int
    var maximumEvents: Int

    static let production = KernelWorkerResultParserLimits(
        maximumStdoutBytes: 16 * 1_024 * 1_024,
        maximumStderrBytes: 4 * 1_024 * 1_024,
        maximumLineBytes: 1 * 1_024 * 1_024,
        maximumEvents: 4_096
    )
}

struct KernelWorkerResultParser: Sendable {
    static let parserIdentityDigest = contentDigest(
        Data("loopforge.kernel.worker-result-parser.v1.canonical-jsonl".utf8)
    )

    func parseRetainedFiles(
        directoryPath: String,
        standardOutputFileName: String,
        standardErrorFileName: String,
        expectation: KernelWorkerResultParseExpectation,
        receiptID: ReceiptID,
        limits: KernelWorkerResultParserLimits = .production
    ) throws -> KernelWorkerResultParseReceipt {
        guard Self.validLimits(limits) else {
            throw KernelWorkerResultParserError.invalidLimits
        }
        guard Self.validFileName(standardOutputFileName),
              Self.validFileName(standardErrorFileName),
              standardOutputFileName != standardErrorFileName else {
            throw KernelWorkerResultParserError.invalidFileName
        }
        let directory = open(
            directoryPath,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directory >= 0 else {
            throw KernelWorkerResultParserError.unsafeDirectory
        }
        defer { close(directory) }
        var directoryStatus = stat()
        guard fstat(directory, &directoryStatus) == 0,
              (directoryStatus.st_mode & S_IFMT) == S_IFDIR,
              directoryStatus.st_uid == geteuid(),
              directoryStatus.st_mode & 0o022 == 0 else {
            throw KernelWorkerResultParserError.unsafeDirectory
        }
        let stdout = try Self.readBoundedFile(
            directoryDescriptor: directory,
            name: standardOutputFileName,
            maximumBytes: limits.maximumStdoutBytes
        )
        let stderr = try Self.readBoundedFile(
            directoryDescriptor: directory,
            name: standardErrorFileName,
            maximumBytes: limits.maximumStderrBytes
        )
        return try parse(
            stdout: stdout,
            stderr: stderr,
            expectation: expectation,
            receiptID: receiptID,
            limits: limits
        )
    }

    func parseAuthorizedRetainedFiles(
        directoryPath: String,
        standardOutputFileName: String,
        standardErrorFileName: String,
        expectation: KernelWorkerResultParseExpectation,
        receiptID: ReceiptID,
        limits: KernelWorkerResultParserLimits = .production
    ) throws -> KernelAuthorizedWorkerResultParse {
        KernelAuthorizedWorkerResultParse(receipt: try parseRetainedFiles(
            directoryPath: directoryPath,
            standardOutputFileName: standardOutputFileName,
            standardErrorFileName: standardErrorFileName,
            expectation: expectation,
            receiptID: receiptID,
            limits: limits
        ))
    }

    func parse(
        stdout: Data,
        stderr: Data,
        expectation: KernelWorkerResultParseExpectation,
        receiptID: ReceiptID,
        limits: KernelWorkerResultParserLimits = .production
    ) throws -> KernelWorkerResultParseReceipt {
        guard Self.validLimits(limits) else {
            throw KernelWorkerResultParserError.invalidLimits
        }
        guard Self.validDigest(expectation.invocationDigest),
              Self.validDigest(expectation.requestNonce),
              !receiptID.rawValue.isEmpty,
              expectation.nativeExit.handle.runID == expectation.runID,
              expectation.nativeExit.handle.resourceID == expectation.resourceID,
              expectation.nativeExit.handle.leaseID == expectation.leaseID else {
            throw KernelWorkerResultParserError.invalidExpectation
        }
        guard expectation.nativeExit.exitCode == 0,
              expectation.nativeExit.terminationSignal == nil else {
            throw KernelWorkerResultParserError.nativeExitUnsuccessful
        }
        guard stdout.count <= limits.maximumStdoutBytes,
              stderr.count <= limits.maximumStderrBytes else {
            throw KernelWorkerResultParserError.outputTooLarge
        }
        guard !stdout.isEmpty else {
            throw KernelWorkerResultParserError.emptyOutput
        }
        guard stdout.last == 0x0a else {
            throw KernelWorkerResultParserError.missingFinalNewline
        }
        guard String(data: stdout, encoding: .utf8) != nil else {
            throw KernelWorkerResultParserError.invalidUTF8
        }

        let lineSlices = stdout.split(separator: 0x0a, omittingEmptySubsequences: false)
        // A mandatory final newline creates exactly one trailing empty slice.
        let retainedLines = lineSlices.dropLast()
        guard retainedLines.count <= limits.maximumEvents else {
            throw KernelWorkerResultParserError.tooManyEvents
        }

        var threadID: String?
        var terminal: KernelWorkerStreamEnvelope?
        var terminalDigest: ContentDigest?
        for (index, slice) in retainedLines.enumerated() {
            guard !slice.isEmpty else {
                throw KernelWorkerResultParserError.emptyLine
            }
            guard slice.count <= limits.maximumLineBytes else {
                throw KernelWorkerResultParserError.lineTooLarge
            }
            let line = Data(slice)
            let envelope = try Self.decodeCanonicalEnvelope(line)
            guard envelope.schemaVersion == 1 else {
                throw KernelWorkerResultParserError.unsupportedSchema
            }
            guard Self.validDigest(envelope.invocationDigest),
                  Self.validDigest(envelope.requestNonce),
                  envelope.payloadDigest.map(Self.validDigest) ?? true,
                  envelope.resultDigest.map(Self.validDigest) ?? true else {
                throw KernelWorkerResultParserError.invalidDigest
            }
            guard envelope.invocationDigest == expectation.invocationDigest else {
                throw KernelWorkerResultParserError.invocationMismatch
            }
            guard envelope.requestNonce == expectation.requestNonce else {
                throw KernelWorkerResultParserError.nonceMismatch
            }
            guard envelope.sequence == UInt64(index) else {
                throw KernelWorkerResultParserError.sequenceMismatch
            }
            guard Self.validThreadID(envelope.threadID) else {
                throw KernelWorkerResultParserError.invalidThreadIdentity
            }
            if let threadID, threadID != envelope.threadID {
                throw KernelWorkerResultParserError.threadIdentityMismatch
            }
            threadID = envelope.threadID

            if terminal != nil {
                if envelope.type == .terminal {
                    throw KernelWorkerResultParserError.duplicateTerminal
                }
                throw KernelWorkerResultParserError.semanticDataAfterTerminal
            }
            switch envelope.type {
            case .event:
                guard envelope.payloadDigest != nil,
                      envelope.proposedDisposition == nil,
                      envelope.resultDigest == nil else {
                    throw KernelWorkerResultParserError.invalidEventShape
                }
            case .terminal:
                guard envelope.payloadDigest == nil,
                      envelope.proposedDisposition != nil,
                      envelope.resultDigest != nil else {
                    throw KernelWorkerResultParserError.invalidTerminalShape
                }
                guard terminal == nil else {
                    throw KernelWorkerResultParserError.duplicateTerminal
                }
                terminal = envelope
                terminalDigest = Self.contentDigest(line)
            }
        }
        guard let terminal,
              let terminalDigest,
              let threadID,
              let disposition = terminal.proposedDisposition,
              let resultDigest = terminal.resultDigest else {
            throw KernelWorkerResultParserError.missingTerminal
        }
        return KernelWorkerResultParseReceipt(
            id: receiptID,
            parserIdentityDigest: Self.parserIdentityDigest,
            runID: expectation.runID,
            attemptID: expectation.attemptID,
            resourceID: expectation.resourceID,
            leaseID: expectation.leaseID,
            bindingReceiptID: expectation.bindingReceiptID,
            releaseReceiptID: expectation.releaseReceiptID,
            invocationDigest: expectation.invocationDigest,
            requestNonce: expectation.requestNonce,
            threadID: threadID,
            eventCount: UInt64(retainedLines.count),
            stdoutContentDigest: Self.contentDigest(stdout),
            stderrContentDigest: Self.contentDigest(stderr),
            terminalEnvelopeDigest: terminalDigest,
            proposedDisposition: disposition,
            proposedResultDigest: resultDigest,
            nativeExit: expectation.nativeExit
        )
    }

    func parseAuthorized(
        stdout: Data,
        stderr: Data,
        expectation: KernelWorkerResultParseExpectation,
        receiptID: ReceiptID,
        limits: KernelWorkerResultParserLimits = .production
    ) throws -> KernelAuthorizedWorkerResultParse {
        KernelAuthorizedWorkerResultParse(receipt: try parse(
            stdout: stdout,
            stderr: stderr,
            expectation: expectation,
            receiptID: receiptID,
            limits: limits
        ))
    }

    static func canonicalLine(_ envelope: KernelWorkerStreamEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    static func contentDigest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    static func validDigest(_ digest: ContentDigest) -> Bool {
        let bytes = digest.rawValue.utf8
        return bytes.count == 64 && bytes.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
        }
    }

    private static func decodeCanonicalEnvelope(
        _ line: Data
    ) throws -> KernelWorkerStreamEnvelope {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let dictionary = object as? [String: Any] else {
            throw KernelWorkerResultParserError.invalidJSON
        }
        let common: Set<String> = [
            "invocationDigest", "requestNonce", "schemaVersion", "sequence",
            "threadID", "type"
        ]
        let type = dictionary["type"] as? String
        let expectedKeys: Set<String>
        switch type {
        case KernelWorkerStreamEnvelopeKind.event.rawValue:
            expectedKeys = common.union(["payloadDigest"])
        case KernelWorkerStreamEnvelopeKind.terminal.rawValue:
            expectedKeys = common.union(["proposedDisposition", "resultDigest"])
        default:
            throw KernelWorkerResultParserError.invalidJSON
        }
        guard Set(dictionary.keys) == expectedKeys,
              let envelope = try? JSONDecoder().decode(
                  KernelWorkerStreamEnvelope.self,
                  from: line
              ) else {
            throw KernelWorkerResultParserError.invalidJSON
        }
        guard try canonicalLine(envelope) == line else {
            throw KernelWorkerResultParserError.nonCanonicalJSON
        }
        return envelope
    }

    private static func validThreadID(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 256
            && !value.unicodeScalars.contains(where: {
                $0.value < 0x20 || $0.value == 0x7f
            })
    }

    private static func validFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    private static func validLimits(_ limits: KernelWorkerResultParserLimits) -> Bool {
        limits.maximumStdoutBytes > 0
            && limits.maximumStderrBytes >= 0
            && limits.maximumLineBytes > 0
            && limits.maximumLineBytes <= limits.maximumStdoutBytes
            && limits.maximumEvents > 0
    }

    private static func readBoundedFile(
        directoryDescriptor: Int32,
        name: String,
        maximumBytes: Int
    ) throws -> Data {
        let descriptor = openat(
            directoryDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw KernelWorkerResultParserError.outputFileMissing
            }
            throw KernelWorkerResultParserError.unsafeFile
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              status.st_mode & 0o077 == 0,
              status.st_size >= 0,
              UInt64(status.st_size) <= UInt64(maximumBytes) else {
            throw KernelWorkerResultParserError.unsafeFile
        }
        var result = Data()
        result.reserveCapacity(Int(status.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw KernelWorkerResultParserError.unsafeFile
            }
            guard result.count <= maximumBytes - count else {
                throw KernelWorkerResultParserError.outputTooLarge
            }
            result.append(buffer, count: count)
        }
        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0,
              finalStatus.st_dev == status.st_dev,
              finalStatus.st_ino == status.st_ino,
              finalStatus.st_size == status.st_size,
              result.count == Int(status.st_size) else {
            throw KernelWorkerResultParserError.unsafeFile
        }
        return result
    }
}
