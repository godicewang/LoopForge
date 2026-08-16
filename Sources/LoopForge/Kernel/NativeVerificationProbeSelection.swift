import CryptoKit
import Darwin
import Foundation

/// User-selected description of one deterministic postimage verifier. The
/// manifest cannot select transport, environment, capture, parser, network, or
/// child-process policy: those authorities are fixed below by the kernel.
struct NativeVerificationProbeManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var executablePath: String
    var fixedArguments: [String]
    var resultMappings: [RequirementVerificationResultMapping]
    var maximumWallClockSeconds: UInt64
    var maximumCapturedOutputBytes: UInt64
    var maximumResidentBytes: UInt64
}

/// Exact in-memory result of one native file-panel selection. Paths are
/// non-authoritative display and enrollment-import hints; the probe retains
/// only the executable content digest and fixed invocation contract.
struct NativeVerificationProbeSelection: Hashable, Sendable {
    let manifestDigest: ContentDigest
    let manifestPath: String
    let executablePath: String
    let probe: RequirementVerificationExecutableProbe

    fileprivate init(
        manifestDigest: ContentDigest,
        manifestPath: String,
        executablePath: String,
        probe: RequirementVerificationExecutableProbe
    ) {
        self.manifestDigest = manifestDigest
        self.manifestPath = manifestPath
        self.executablePath = executablePath
        self.probe = probe
    }

    var manifestFileName: String {
        URL(fileURLWithPath: manifestPath).lastPathComponent
    }

    var executableFileName: String {
        URL(fileURLWithPath: executablePath).lastPathComponent
    }
}

enum NativeVerificationProbeSelectionError: Error, Equatable {
    case invalidManifestFile
    case malformedManifest
    case unsupportedSchema
    case invalidManifest([String])
    case invalidExecutable(String)
    case executableTooLarge(String)
    case executableChanged(String)
    case selectionChanged
    case digestConstructionFailed
}

extension NativeVerificationProbeSelectionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidManifestFile:
            return "The selected verifier manifest is not a stable regular JSON file."
        case .malformedManifest:
            return "The selected verifier manifest is not valid schema-constrained JSON."
        case .unsupportedSchema:
            return "The selected verifier manifest schema is unsupported."
        case .invalidManifest(let issues):
            return "The selected verifier manifest failed closed: \(issues.joined(separator: "; "))"
        case .invalidExecutable(let file):
            return "The selected verifier executable is missing, non-regular, symlinked, non-executable, or unsafe: \(file)"
        case .executableTooLarge(let file):
            return "The selected verifier executable exceeds the bounded import limit: \(file)"
        case .executableChanged(let file):
            return "The selected verifier executable changed while it was being hashed: \(file)"
        case .selectionChanged:
            return "The selected verifier manifest or executable changed after contract review. Select it again before confirming."
        case .digestConstructionFailed:
            return "The verifier manifest identity could not be constructed."
        }
    }
}

enum NativeVerificationProbeSelectionLoader {
    static let candidateInputID = "candidate-postimage"
    static let candidateInputToken = "@loopforge-input:candidate-postimage"
    static let maximumManifestBytes = 1_048_576
    static let maximumExecutableBytes = 536_870_912
    static let maximumWallClockSeconds: UInt64 = 3_600
    static let maximumCapturedOutputBytes: UInt64 = 67_108_864
    static let maximumResidentBytes: UInt64 = 8_589_934_592

    static func load(
        manifestURL: URL
    ) throws -> NativeVerificationProbeSelection {
        let manifestBytes = try readManifest(manifestURL.path)
        guard hasExactJSONShape(manifestBytes) else {
            throw NativeVerificationProbeSelectionError.malformedManifest
        }
        let manifest: NativeVerificationProbeManifest
        do {
            manifest = try JSONDecoder.loopForge.decode(
                NativeVerificationProbeManifest.self,
                from: manifestBytes
            )
        } catch {
            throw NativeVerificationProbeSelectionError.malformedManifest
        }
        guard manifest.schemaVersion == 1 else {
            throw NativeVerificationProbeSelectionError.unsupportedSchema
        }
        let issues = validationIssues(manifest)
        guard issues.isEmpty else {
            throw NativeVerificationProbeSelectionError.invalidManifest(
                issues.sorted()
            )
        }

        let executableDigest = try digestExecutable(manifest.executablePath)
        let parserFormat = RequirementVerificationParserFormat
            .canonicalJSONResultV1
        let probe = RequirementVerificationExecutableProbe(
            schemaVersion: 2,
            transport: .localDirectProcess,
            executableContentDigest: executableDigest,
            fixedArguments: manifest.fixedArguments,
            inputBindings: [RequirementVerificationInputBinding(
                id: candidateInputID,
                kind: .candidatePostimage,
                artifactID: "journal-owned-candidate-postimage",
                argumentToken: candidateInputToken
            )],
            environmentPolicy: .minimalKernelAllowlist,
            environmentIdentityDigest: KernelProcessEnvironmentAuthorizer
                .environmentDigest(
                    KernelProcessEnvironmentAuthorizer.minimalEnvironment
                ),
            captureIdentityDigest:
                KernelPostimageVerifierCapturePolicy.identityDigest,
            parser: RequirementVerificationParserContract(
                id: "loopforge-canonical-json-result-v1",
                schemaVersion: 1,
                contentDigest: parserFormat.implementationIdentityDigest,
                format: parserFormat
            ),
            resultMappings: manifest.resultMappings,
            unmatchedOutcome: .rejected,
            networkPolicy: .disabled,
            resourceLimits: RequirementVerificationResourceLimits(
                maximumWallClockSeconds:
                    manifest.maximumWallClockSeconds,
                maximumCapturedOutputBytes:
                    manifest.maximumCapturedOutputBytes,
                maximumResidentBytes: manifest.maximumResidentBytes,
                maximumChildProcesses: 0
            )
        )
        let probeIssues = probe.validationIssues()
        guard probeIssues.isEmpty else {
            throw NativeVerificationProbeSelectionError.invalidManifest(
                probeIssues.sorted()
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let canonicalManifest = try? encoder.encode(manifest) else {
            throw NativeVerificationProbeSelectionError
                .digestConstructionFailed
        }
        return NativeVerificationProbeSelection(
            manifestDigest: TaskContractCompiler.digest(canonicalManifest),
            manifestPath: manifestURL.path,
            executablePath: manifest.executablePath,
            probe: probe
        )
    }

    /// Re-opens both selected files at the user-confirmation boundary and
    /// requires the complete digest-bound selection to remain unchanged.
    /// This does not turn either path into authority: enrollment imports and
    /// rehashes the executable against the confirmed probe digest, after which
    /// activation resolves only the journal-owned content-addressed artifact.
    static func revalidate(
        _ selection: NativeVerificationProbeSelection
    ) throws -> NativeVerificationProbeSelection {
        let refreshed = try load(
            manifestURL: URL(fileURLWithPath: selection.manifestPath)
        )
        guard refreshed == selection else {
            throw NativeVerificationProbeSelectionError.selectionChanged
        }
        return refreshed
    }

    private static func validationIssues(
        _ manifest: NativeVerificationProbeManifest
    ) -> [String] {
        var issues: [String] = []
        if !validAbsolutePath(manifest.executablePath) {
            issues.append("executablePath must be one exact absolute standardized path")
        }
        if manifest.fixedArguments.isEmpty
            || manifest.fixedArguments.count > 64
            || manifest.fixedArguments.contains(where: {
                $0.utf8.count > 4_096 || $0.contains("\0")
            }) {
            issues.append("fixedArguments must be a non-empty bounded exact argv")
        }
        if manifest.fixedArguments.filter({
            $0 == candidateInputToken
        }).count != 1 {
            issues.append("fixedArguments must contain the exact candidate postimage token once")
        }
        if manifest.fixedArguments.contains(where: {
            $0.hasPrefix("@loopforge-input:") && $0 != candidateInputToken
        }) {
            issues.append("undeclared verifier input tokens are forbidden")
        }
        let mappingKeys = manifest.resultMappings.map {
            "\($0.exitCode)\u{1f}\($0.parserResultCode)"
        }
        if manifest.resultMappings.isEmpty
            || manifest.resultMappings.count > 64
            || Set(mappingKeys).count != mappingKeys.count
            || manifest.resultMappings.contains(where: {
                !validIdentity($0.parserResultCode)
            })
            || !manifest.resultMappings.contains(where: {
                $0.outcome == .accepted
            }) {
            issues.append("resultMappings must be unique, exact, and include an accepted result")
        }
        if manifest.maximumWallClockSeconds == 0
            || manifest.maximumWallClockSeconds > maximumWallClockSeconds {
            issues.append("maximumWallClockSeconds must be between 1 and 3600")
        }
        if manifest.maximumCapturedOutputBytes == 0
            || manifest.maximumCapturedOutputBytes > maximumCapturedOutputBytes {
            issues.append("maximumCapturedOutputBytes must be between 1 and 67108864")
        }
        if manifest.maximumResidentBytes == 0
            || manifest.maximumResidentBytes > maximumResidentBytes {
            issues.append("maximumResidentBytes must be between 1 and 8589934592")
        }
        return issues
    }

    private static func hasExactJSONShape(_ bytes: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: bytes),
              let object = root as? [String: Any],
              Set(object.keys) == [
                "schemaVersion",
                "executablePath",
                "fixedArguments",
                "resultMappings",
                "maximumWallClockSeconds",
                "maximumCapturedOutputBytes",
                "maximumResidentBytes"
              ],
              let mappings = object["resultMappings"] as? [[String: Any]],
              mappings.allSatisfy({
                  Set($0.keys) == ["exitCode", "parserResultCode", "outcome"]
              }) else {
            return false
        }
        return true
    }

    private static func readManifest(_ file: String) throws -> Data {
        let descriptor: Int32
        do {
            descriptor = try openRegularFile(
                file,
                maximumBytes: maximumManifestBytes,
                requireExecutable: false
            )
        } catch {
            throw NativeVerificationProbeSelectionError.invalidManifestFile
        }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else {
            throw NativeVerificationProbeSelectionError.invalidManifestFile
        }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw NativeVerificationProbeSelectionError.invalidManifestFile
            }
            bytes.append(contentsOf: buffer[0..<count])
        }
        guard stableAfterRead(
            descriptor,
            expectedBytes: bytes.count,
            originalPath: file,
            initial: initial
        ) else {
            throw NativeVerificationProbeSelectionError.invalidManifestFile
        }
        return bytes
    }

    private static func digestExecutable(
        _ file: String
    ) throws -> ContentDigest {
        let descriptor: Int32
        do {
            descriptor = try openRegularFile(
                file,
                maximumBytes: maximumExecutableBytes,
                requireExecutable: true
            )
        } catch let error as NativeVerificationProbeSelectionError {
            throw error
        } catch {
            throw NativeVerificationProbeSelectionError.invalidExecutable(file)
        }
        defer { _ = Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0 else {
            throw NativeVerificationProbeSelectionError
                .executableChanged(file)
        }
        var hasher = SHA256()
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw NativeVerificationProbeSelectionError
                    .executableChanged(file)
            }
            total += count
            hasher.update(data: Data(buffer[0..<count]))
        }
        guard stableAfterRead(
            descriptor,
            expectedBytes: total,
            originalPath: file,
            initial: initial
        ) else {
            throw NativeVerificationProbeSelectionError.executableChanged(file)
        }
        return ContentDigest(
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func openRegularFile(
        _ file: String,
        maximumBytes: Int,
        requireExecutable: Bool
    ) throws -> Int32 {
        guard validAbsolutePath(file), maximumBytes > 0 else {
            throw NativeVerificationProbeSelectionError.invalidExecutable(file)
        }
        var before = stat()
        guard lstat(file, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0 else {
            throw NativeVerificationProbeSelectionError.invalidExecutable(file)
        }
        guard before.st_size <= off_t(maximumBytes) else {
            throw NativeVerificationProbeSelectionError.executableTooLarge(file)
        }
        if requireExecutable,
           before.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH) == 0 {
            throw NativeVerificationProbeSelectionError.invalidExecutable(file)
        }
        let descriptor = Darwin.open(file, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw NativeVerificationProbeSelectionError.invalidExecutable(file)
        }
        var held = stat()
        guard fstat(descriptor, &held) == 0,
              held.st_mode & S_IFMT == S_IFREG,
              held.st_dev == before.st_dev,
              held.st_ino == before.st_ino,
              held.st_size == before.st_size,
              held.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              held.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else {
            _ = Darwin.close(descriptor)
            throw NativeVerificationProbeSelectionError.invalidExecutable(file)
        }
        return descriptor
    }

    private static func stableAfterRead(
        _ descriptor: Int32,
        expectedBytes: Int,
        originalPath: String,
        initial: stat
    ) -> Bool {
        var held = stat()
        var current = stat()
        return fstat(descriptor, &held) == 0
            && held.st_size == off_t(expectedBytes)
            && held.st_dev == initial.st_dev
            && held.st_ino == initial.st_ino
            && held.st_size == initial.st_size
            && held.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec
            && held.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec
            && lstat(originalPath, &current) == 0
            && current.st_mode & S_IFMT == S_IFREG
            && current.st_dev == held.st_dev
            && current.st_ino == held.st_ino
            && current.st_size == held.st_size
            && current.st_mtimespec.tv_sec == held.st_mtimespec.tv_sec
            && current.st_mtimespec.tv_nsec == held.st_mtimespec.tv_nsec
    }

    private static func validAbsolutePath(_ file: String) -> Bool {
        !file.isEmpty
            && file.hasPrefix("/")
            && !file.contains("\0")
            && URL(fileURLWithPath: file).standardizedFileURL.path == file
    }

    private static func validIdentity(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 512
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
