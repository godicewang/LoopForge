import CryptoKit
import Darwin
import Foundation

struct KernelNativeSandboxReceipt: Codable, Hashable, Sendable {
  var schemaVersion: Int
  var sandbox: KernelExecutionSandbox
  var networkPolicy: KernelNetworkPolicy
  var launcherPath: String
  var launcherContentDigest: ContentDigest
  var gateExecutablePath: String
  var gateExecutableContentDigest: ContentDigest
  var profileDigest: ContentDigest
  var parameterDigest: ContentDigest
  var workspaceRootPathDigest: ContentDigest
  var journalRunDirectoryPathDigest: ContentDigest
  var standardOutputPathDigest: ContentDigest?
  var standardErrorPathDigest: ContentDigest?
  var journalWritesDefaultDenied: Bool
  var nativeAttestationRequired: Bool
}

struct ManagedProcessNativeSandbox: Codable, Hashable, Sendable {
  var receipt: KernelNativeSandboxReceipt
  var profile: String
  var parameters: [String: String]
}

enum KernelCandidateWorkingDirectoryBinding:
  String, Codable, Hashable, Sendable
{
  case posixSpawnFileActionsFchdir
}

struct KernelCandidateWorkingDirectoryAttestationReceipt:
  Codable, Hashable, Sendable
{
  var binding: KernelCandidateWorkingDirectoryBinding
  var deviceID: UInt64
  var inode: UInt64
}

struct KernelNativeSandboxAttestationReceipt: Codable, Hashable, Sendable {
  var authorization: KernelNativeSandboxReceipt
  var processID: Int32
  var observedAtMonotonicNanoseconds: UInt64
  var nativeSandboxCheckResult: Int32
  var gateObservedStopped: Bool
  var targetExecHandshakeSucceeded: Bool
  var candidateWorkingDirectory: KernelCandidateWorkingDirectoryAttestationReceipt? = nil
}

enum KernelNativeSandboxError: Error, Equatable {
  case invalidWorkspace
  case invalidJournalDirectory
  case workspaceOverlapsJournal
  case ioDirectoryMismatch
  case unsupportedFullAccess
  case launcherUnavailable
  case invalidConfiguration
}

struct AuthorizedKernelNativeSandbox: Sendable {
  var configuration: ManagedProcessNativeSandbox

  fileprivate init(configuration: ManagedProcessNativeSandbox) {
    self.configuration = configuration
  }
}

/// Builds the only native sandbox configuration accepted by the journaled
/// process boundary. The profile begins with deny-default. Read-only grants no
/// pathname writes; workspace-only grants writes solely beneath the exact
/// canonical workspace. Full-access cannot be represented while also
/// protecting same-user journal evidence under Seatbelt's allow composition,
/// so it fails closed instead of publishing a misleading receipt.
struct KernelNativeSandboxAuthorizer: Sendable {
  static let launcherPath = "/usr/bin/sandbox-exec"
  static let handshakeDescriptor: Int32 = 198

  private let gateExecutablePath: String

  init(gateExecutablePath: String? = nil) {
    self.gateExecutablePath =
      gateExecutablePath
      ?? Self.defaultGateExecutablePath()
      ?? ""
  }

  /// Returns the descriptor-resolved physical directory name used by the
  /// native sandbox boundary. Foundation's symlink resolution can retain the
  /// `/var` compatibility alias on macOS while `F_GETPATH` reports
  /// `/private/var`; sharing this primitive keeps durable launch evidence and
  /// native Seatbelt parameters in one path-identity domain.
  static func physicalDirectoryURL(_ url: URL) throws -> URL {
    try canonicalDirectory(url, invalid: .invalidWorkspace)
  }

  func authorize(
    executionProfile: KernelAgentExecutionProfile,
    workspaceRoot: URL,
    journalRunDirectory: URL,
    ioFiles: ManagedProcessIOFiles?
  ) throws -> AuthorizedKernelNativeSandbox {
    let workspace = try Self.canonicalDirectory(
      workspaceRoot,
      invalid: .invalidWorkspace
    )
    let journal = try Self.canonicalDirectory(
      journalRunDirectory,
      invalid: .invalidJournalDirectory
    )
    guard !Self.pathsOverlap(workspace.path, journal.path) else {
      throw KernelNativeSandboxError.workspaceOverlapsJournal
    }
    if let ioFiles {
      let supplied = try Self.canonicalDirectory(
        URL(
          fileURLWithPath: ioFiles.directoryPath,
          isDirectory: true
        ),
        invalid: .ioDirectoryMismatch
      )
      guard supplied.path == journal.path else {
        throw KernelNativeSandboxError.ioDirectoryMismatch
      }
    }
    guard executionProfile.sandbox != .fullAccess else {
      throw KernelNativeSandboxError.unsupportedFullAccess
    }
    guard
      let launcherDigest =
        ProcessGroupRuntimeAdapter
        .executableContentDigest(atPath: Self.launcherPath)
    else {
      throw KernelNativeSandboxError.launcherUnavailable
    }
    guard
      let gateDigest = ProcessGroupRuntimeAdapter.executableContentDigest(
        atPath: gateExecutablePath
      )
    else {
      throw KernelNativeSandboxError.launcherUnavailable
    }

    let outputPath = try Self.outputPath(
      ioFiles?.standardOutputFileName,
      beneath: journal
    )
    let errorPath = try Self.outputPath(
      ioFiles?.standardErrorFileName,
      beneath: journal
    )
    // JOURNAL is digest-bound evidence only. The profile deliberately has
    // no allow rule for it, so child writes remain default-denied.
    var parameters = [
      "JOURNAL": journal.path,
      "WORKSPACE": workspace.path,
    ]
    if let outputPath { parameters["STDOUT"] = outputPath }
    if let errorPath { parameters["STDERR"] = errorPath }
    let profile = Self.profile(
      sandbox: executionProfile.sandbox,
      networkPolicy: executionProfile.networkPolicy,
      hasStandardOutput: outputPath != nil,
      hasStandardError: errorPath != nil
    )
    let receipt = KernelNativeSandboxReceipt(
      schemaVersion: 1,
      sandbox: executionProfile.sandbox,
      networkPolicy: executionProfile.networkPolicy,
      launcherPath: Self.launcherPath,
      launcherContentDigest: launcherDigest,
      gateExecutablePath: gateExecutablePath,
      gateExecutableContentDigest: gateDigest,
      profileDigest: Self.digest("kernel-native-sandbox-profile-v1", profile),
      parameterDigest: Self.parameterDigest(parameters),
      workspaceRootPathDigest: Self.workspacePathDigest(workspace.path),
      journalRunDirectoryPathDigest:
        Self.journalRunDirectoryPathDigest(journal.path),
      standardOutputPathDigest: outputPath.map {
        Self.digest("kernel-native-sandbox-output-v1", $0)
      },
      standardErrorPathDigest: errorPath.map {
        Self.digest("kernel-native-sandbox-error-v1", $0)
      },
      journalWritesDefaultDenied: true,
      nativeAttestationRequired: true
    )
    let configuration = ManagedProcessNativeSandbox(
      receipt: receipt,
      profile: profile,
      parameters: parameters
    )
    guard Self.configurationIsValid(configuration) else {
      throw KernelNativeSandboxError.invalidConfiguration
    }
    return AuthorizedKernelNativeSandbox(configuration: configuration)
  }

  static func configurationIsValid(_ value: ManagedProcessNativeSandbox) -> Bool {
    let receipt = value.receipt
    guard receipt.schemaVersion == 1,
      receipt.sandbox != .fullAccess,
      receipt.launcherPath == launcherPath,
      receipt.gateExecutablePath.hasPrefix("/"),
      receipt.gateExecutableContentDigest.rawValue.count == 64,
      receipt.journalWritesDefaultDenied,
      receipt.nativeAttestationRequired,
      receipt.profileDigest
        == digest(
          "kernel-native-sandbox-profile-v1",
          value.profile
        ),
      receipt.parameterDigest == parameterDigest(value.parameters),
      value.parameters["JOURNAL"]?.hasPrefix("/") == true,
      value.parameters["WORKSPACE"]?.hasPrefix("/") == true,
      Set(value.parameters.keys).isSubset(of: [
        "JOURNAL", "WORKSPACE", "STDOUT", "STDERR",
      ]),
      value.parameters.allSatisfy({ key, path in
        !key.isEmpty && !key.contains("=") && !key.contains("\0")
          && path.hasPrefix("/") && !path.contains("\0")
      })
    else {
      return false
    }
    let expected = profile(
      sandbox: receipt.sandbox,
      networkPolicy: receipt.networkPolicy,
      hasStandardOutput: value.parameters["STDOUT"] != nil,
      hasStandardError: value.parameters["STDERR"] != nil
    )
    guard value.profile == expected else { return false }
    return receipt.journalRunDirectoryPathDigest
      == journalRunDirectoryPathDigest(
        value.parameters["JOURNAL"] ?? ""
      )
      && receipt.workspaceRootPathDigest
        == workspacePathDigest(
          value.parameters["WORKSPACE"] ?? ""
        )
      && receipt.standardOutputPathDigest
        == value.parameters["STDOUT"].map {
          digest("kernel-native-sandbox-output-v1", $0)
        }
      && receipt.standardErrorPathDigest
        == value.parameters["STDERR"].map {
          digest("kernel-native-sandbox-error-v1", $0)
        }
  }

  static func workspacePathDigest(_ path: String) -> ContentDigest {
    digest("kernel-native-sandbox-workspace-v1", path)
  }

  static func journalRunDirectoryPathDigest(
    _ path: String
  ) -> ContentDigest {
    digest("kernel-native-sandbox-journal-v1", path)
  }

  static func outputPathDigest(
    directoryPath: String,
    fileName: String?
  ) -> ContentDigest? {
    guard let fileName else { return nil }
    return digest(
      "kernel-native-sandbox-output-v1",
      URL(
        fileURLWithPath: directoryPath,
        isDirectory: true
      ).appendingPathComponent(fileName, isDirectory: false).path
    )
  }

  static func errorPathDigest(
    directoryPath: String,
    fileName: String?
  ) -> ContentDigest? {
    guard let fileName else { return nil }
    return digest(
      "kernel-native-sandbox-error-v1",
      URL(
        fileURLWithPath: directoryPath,
        isDirectory: true
      ).appendingPathComponent(fileName, isDirectory: false).path
    )
  }

  private static func profile(
    sandbox: KernelExecutionSandbox,
    networkPolicy: KernelNetworkPolicy,
    hasStandardOutput: Bool,
    hasStandardError: Bool
  ) -> String {
    var rules = [
      "(version 1)",
      "(deny default)",
      "(allow file-read*)",
      "(allow process*)",
      "(allow sysctl-read)",
      "(allow mach-lookup)",
      "(allow file-write-data (literal \"/dev/null\"))",
    ]
    if sandbox == .workspaceOnly {
      rules.append("(allow file-write* (subpath (param \"WORKSPACE\")))")
    }
    if hasStandardOutput {
      rules.append("(allow file-write-data (literal (param \"STDOUT\")))")
    }
    if hasStandardError {
      rules.append("(allow file-write-data (literal (param \"STDERR\")))")
    }
    if networkPolicy == .enabled {
      rules.append("(allow network*)")
    }
    return rules.joined(separator: "\n") + "\n"
  }

  private static func defaultGateExecutablePath() -> String? {
    let fileManager = FileManager.default
    let bundleCandidate = Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/KernelSandboxGate")
    if fileManager.isExecutableFile(atPath: bundleCandidate.path) {
      return bundleCandidate.path
    }
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    for candidate in [
      projectRoot.appendingPathComponent(".build/debug/KernelSandboxGate"),
      projectRoot.appendingPathComponent(
        ".build/arm64-apple-macosx/debug/KernelSandboxGate"
      ),
    ] where fileManager.isExecutableFile(atPath: candidate.path) {
      return candidate.standardizedFileURL.path
    }
    return nil
  }

  private static func canonicalDirectory(
    _ url: URL,
    invalid: KernelNativeSandboxError
  ) throws -> URL {
    guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0") else {
      throw invalid
    }
    let descriptor = Darwin.open(
      url.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard descriptor >= 0 else {
      throw invalid
    }
    defer { _ = Darwin.close(descriptor) }
    var physical = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard Darwin.fcntl(descriptor, F_GETPATH, &physical) == 0 else {
      throw invalid
    }
    let resolved = URL(
      fileURLWithPath: String(cString: physical),
      isDirectory: true
    )
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: resolved.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue
    else {
      throw invalid
    }
    return resolved
  }

  private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
    lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
  }

  private static func outputPath(_ name: String?, beneath directory: URL) throws -> String? {
    guard let name else { return nil }
    guard !name.isEmpty,
      name != ".",
      name != "..",
      !name.contains("/"),
      !name.contains("\0"),
      name.precomposedStringWithCanonicalMapping == name
    else {
      throw KernelNativeSandboxError.invalidConfiguration
    }
    return directory.appendingPathComponent(name, isDirectory: false).path
  }

  private static func parameterDigest(_ parameters: [String: String]) -> ContentDigest {
    let material = parameters.keys.sorted().map { key in
      let value = parameters[key] ?? ""
      return "\(key.utf8.count):\(key)\(value.utf8.count):\(value)"
    }.joined(separator: "|")
    return digest("kernel-native-sandbox-parameters-v1", material)
  }

  private static func digest(_ domain: String, _ value: String) -> ContentDigest {
    let hash = SHA256.hash(data: Data("\(domain)\0\(value)".utf8))
    return ContentDigest(hash.map { String(format: "%02x", $0) }.joined())
  }
}
