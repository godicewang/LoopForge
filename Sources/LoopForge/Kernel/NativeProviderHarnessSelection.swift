import CryptoKit
import Darwin
import Foundation

struct NativeProviderHarnessManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var protocolVersion: Int
    var executableFileName: String
    var executableSHA256: ContentDigest
    var executableByteCount: UInt64
    var operationalMode: KernelProviderHarnessMode
    var productiveProviderBackends: [KernelExecutionProvider]
    var selfTestSHA256: ContentDigest
}

struct NativeProviderHarnessSelection: Equatable, Sendable {
    var executableURL: URL
    var manifest: NativeProviderHarnessManifest
}

enum NativeProviderHarnessSelectionError: Error, Equatable {
    case manifestUnavailable
    case manifestUnsafe
    case manifestInvalid
    case executableUnsafe
    case executableIdentityMismatch
    case selfTestIdentityMismatch
}

/// Loads only one package-owned, signed-resource identity. Provider labels,
/// PATH, ambient executables, and model prose cannot select or ratify a
/// harness. This ordinary-app loader intentionally accepts only the packaged
/// transport-veto identity. Productive mode belongs to a separately scoped
/// privileged or virtualized isolation product and cannot be enabled by
/// editing a local manifest, even when its executable digest is otherwise
/// exact.
enum NativeProviderHarnessSelectionLoader {
    static let manifestFileName = "LoopForgeProviderHarnessManifest.json"
    static let executableFileName = "LoopForgeProviderHarness"

    static func bundled() -> NativeProviderHarnessSelection? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let manifest = resources.appendingPathComponent(manifestFileName)
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableFileName)
        return try? load(manifestURL: manifest, executableURL: executable)
    }

    static func load(
        manifestURL: URL,
        executableURL: URL
    ) throws -> NativeProviderHarnessSelection {
        let manifest = manifestURL.standardizedFileURL
        let executable = executableURL.standardizedFileURL
        guard manifest.isFileURL, executable.isFileURL else {
            throw NativeProviderHarnessSelectionError.manifestUnavailable
        }
        let manifestStatus = try safeRegularFile(manifest)
        guard manifestStatus.st_size > 0, manifestStatus.st_size <= 65_536 else {
            throw NativeProviderHarnessSelectionError.manifestUnsafe
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifest, options: [.mappedIfSafe])
        } catch {
            throw NativeProviderHarnessSelectionError.manifestUnavailable
        }
        guard let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              Set(object.keys) == [
                "executableByteCount", "executableFileName",
                "executableSHA256", "operationalMode",
                "productiveProviderBackends", "protocolVersion",
                "schemaVersion", "selfTestSHA256",
              ],
              let decoded = try? JSONDecoder().decode(
                NativeProviderHarnessManifest.self,
                from: data
              ),
              decoded.schemaVersion == 1,
              decoded.protocolVersion ==
                KernelProviderInvocationCompiler.protocolVersion,
              decoded.executableFileName == executableFileName,
              decoded.operationalMode == .transportVetoOnly,
              decoded.productiveProviderBackends.isEmpty else {
            throw NativeProviderHarnessSelectionError.manifestInvalid
        }

        let executableStatus: stat
        do {
            executableStatus = try safeRegularFile(executable)
        } catch {
            throw NativeProviderHarnessSelectionError.executableUnsafe
        }
        guard executable.lastPathComponent == decoded.executableFileName,
              executableStatus.st_size > 0,
              UInt64(executableStatus.st_size) == decoded.executableByteCount,
              executableStatus.st_mode & 0o111 != 0,
              let digest = ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: executable.path
              ),
              digest == decoded.executableSHA256 else {
            throw NativeProviderHarnessSelectionError
                .executableIdentityMismatch
        }
        guard decoded.selfTestSHA256 == expectedSelfTestSHA256 else {
            throw NativeProviderHarnessSelectionError.selfTestIdentityMismatch
        }
        return NativeProviderHarnessSelection(
            executableURL: executable,
            manifest: decoded
        )
    }

    static var expectedSelfTestSHA256: ContentDigest {
        let object: [String: Any] = [
            "credentialTransport": "length-prefixed-fd-197",
            "invocationContextTransport": "canonical-json-fd-196",
            "operationalMode": "transport-veto-only",
            "productiveProviderBackends": [],
            "promptTransport": "exact-stdin",
            "protocolVersion": 2,
            "schemaVersion": 1,
        ]
        let bytes = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        return ContentDigest(KernelHex.encode(SHA256.hash(data: bytes + [0x0a])))
    }

    private static func safeRegularFile(_ url: URL) throws -> stat {
        var status = stat()
        guard url.path.hasPrefix("/"), !url.path.contains("\0"),
              Darwin.lstat(url.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1,
              status.st_uid == geteuid(),
              status.st_mode & 0o022 == 0 else {
            throw NativeProviderHarnessSelectionError.manifestUnsafe
        }
        return status
    }
}
