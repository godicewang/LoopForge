import CryptoKit
import Darwin
import Foundation

/// User-selected file manifest for one immutable native design baseline.
/// Paths are observations only: the loader below opens every file itself with
/// `O_NOFOLLOW`, hashes the two protected artifacts through held descriptors,
/// and sends capture bytes through `NativeVisualCaptureAdapter` before any
/// value can enter contract authoring.
struct NativeDesignBaselineCaptureSourceManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var designBaselineID: DesignBaselineID
    var protectedBaselineID: BaselineID
    var sourceArtifactPath: String
    var builtArtifactPath: String
    var environmentDigest: ContentDigest?
    var designTokenSnapshotPath: String
    var semanticSurfaceManifestPath: String
    var captures: [NativeDesignBaselineCaptureFileSource]
    var protectedInvariants: [DesignInvariant]
    var knownDebt: [DesignDebt]
}

struct NativeDesignBaselineCaptureFileSource: Codable, Hashable, Sendable {
    var cellID: VisualCellID
    var expectedTraits: VisualTraitSignature
    var encodedImagePath: String
    var accessibilityTreePath: String
    var cleanInstallEvidencePath: String
    var navigationRecipePath: String
    var componentBoundaryTracePath: String?
    var designTokenTracePath: String?
    var fullViewport: Bool
    var cleanInstall: Bool
    var processExitCode: Int32
}

/// Exact in-memory result of a successful native import. It is intentionally
/// non-Codable: reopening a JSON manifest cannot recreate the adapter-issued
/// capture attestations or substitute bytes after the native user selection.
struct NativeDesignBaselineCaptureSource: Hashable, Sendable {
    var manifestDigest: ContentDigest
    var designBaselineID: DesignBaselineID
    var protectedBaselineID: BaselineID
    var sourceTree: ContentDigest
    var builtArtifact: ContentDigest
    var environmentDigest: ContentDigest?
    var captureProtocol: ContentDigest
    var designTokenSnapshot: ContentDigest
    var semanticSurfaceManifest: ContentDigest
    var captures: [NativeCaptureReceipt]
    var protectedInvariants: [DesignInvariant]
    var knownDebt: [DesignDebt]
    var importedAt: Date

    func validationIssues() -> [String] {
        var issues: [String] = []
        let digests = [
            manifestDigest,
            sourceTree,
            builtArtifact,
            captureProtocol,
            designTokenSnapshot,
            semanticSurfaceManifest
        ] + (environmentDigest.map { [$0] } ?? [])
        if designBaselineID.rawValue.isEmpty
            || protectedBaselineID.rawValue.isEmpty {
            issues.append("baseline identities must not be empty")
        }
        if digests.contains(where: { !Self.validSHA256($0) }) {
            issues.append("baseline source digests must be exact lowercase SHA-256")
        }
        if !importedAt.timeIntervalSince1970.isFinite {
            issues.append("baseline import time must be finite")
        }
        let captureIDs = captures.map(\.id)
        let cells = captures.map(\.cellID)
        if captures.isEmpty
            || Set(captureIDs).count != captureIDs.count
            || Set(cells).count != cells.count
            || captures.contains(where: {
                !$0.isComplete
                    || $0.sourceTree != sourceTree
                    || $0.builtArtifact != builtArtifact
                    || $0.captureProtocol != captureProtocol
                    || $0.capturedAt != importedAt
            }) {
            issues.append("native captures must be complete, unique, and source-bound")
        }
        let captureCells = Set(cells)
        let invariantIDs = protectedInvariants.map(\.id)
        if protectedInvariants.isEmpty
            || invariantIDs.contains(where: { $0.isEmpty })
            || Set(invariantIDs).count != invariantIDs.count
            || protectedInvariants.contains(where: {
                $0.cellIDs.isEmpty || !$0.cellIDs.isSubset(of: captureCells)
            }) {
            issues.append("protected invariants must uniquely cover captured cells")
        }
        let invariantCells = Set(protectedInvariants.flatMap(\.cellIDs))
        let debtIDs = knownDebt.map(\.id)
        if Set(debtIDs).count != debtIDs.count
            || knownDebt.contains(where: {
                $0.id.rawValue.isEmpty
                    || $0.cellIDs.isEmpty
                    || !$0.cellIDs.isSubset(of: invariantCells)
                    || !$0.baselineSeverity.isFinite
                    || $0.baselineSeverity < 0
                    || !$0.maximumInterimSeverity.isFinite
                    || $0.maximumInterimSeverity < 0
                    || !Self.validSHA256($0.evidenceDigest)
            }) {
            issues.append("known design debt must be unique, finite, and evidence-bound")
        }
        return issues
    }

    fileprivate static func validSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }
}

enum NativeDesignBaselineCaptureSourceError: Error, Equatable {
    case invalidManifestFile
    case malformedManifest
    case unsupportedSchema
    case invalidManifest([String])
    case invalidEvidenceFile(String)
    case evidenceTooLarge(String)
    case captureFailed(NativeVisualCaptureError)
    case digestConstructionFailed
}

extension NativeDesignBaselineCaptureSourceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidManifestFile:
            return "The selected baseline manifest is not a stable regular JSON file."
        case .malformedManifest:
            return "The selected baseline manifest is not valid schema-constrained JSON."
        case .unsupportedSchema:
            return "The selected baseline manifest schema is unsupported."
        case .invalidManifest(let issues):
            return "The selected baseline manifest failed closed: \(issues.joined(separator: "; "))"
        case .invalidEvidenceFile(let path):
            return "A baseline evidence file is missing, non-regular, symlinked, or changed: \(path)"
        case .evidenceTooLarge(let path):
            return "A baseline evidence file exceeds its bounded import limit: \(path)"
        case .captureFailed(let error):
            return "Native baseline capture attestation failed: \(error)"
        case .digestConstructionFailed:
            return "The baseline capture-source identity could not be constructed."
        }
    }
}

enum NativeDesignBaselineCaptureSourceLoader {
    static let harnessIdentity = "loopforge-native-selected-capture-source-v1"
    private static let maximumManifestBytes = 1_048_576
    private static let maximumProtectedArtifactBytes = 536_870_912

    static func load(
        manifestURL: URL,
        importedAt: Date = Date()
    ) async throws -> NativeDesignBaselineCaptureSource {
        guard importedAt.timeIntervalSince1970.isFinite else {
            throw NativeDesignBaselineCaptureSourceError.invalidManifest([
                "import time must be finite"
            ])
        }
        let manifestBytes = try readRegularFile(
            manifestURL.path,
            maximumBytes: maximumManifestBytes,
            manifest: true
        )
        let decoder = JSONDecoder.loopForge
        let manifest: NativeDesignBaselineCaptureSourceManifest
        guard hasExactJSONShape(manifestBytes) else {
            throw NativeDesignBaselineCaptureSourceError.malformedManifest
        }
        do {
            manifest = try decoder.decode(
                NativeDesignBaselineCaptureSourceManifest.self,
                from: manifestBytes
            )
        } catch {
            throw NativeDesignBaselineCaptureSourceError.malformedManifest
        }
        guard manifest.schemaVersion == 1 else {
            throw NativeDesignBaselineCaptureSourceError.unsupportedSchema
        }
        let manifestIssues = validationIssues(manifest)
        guard manifestIssues.isEmpty else {
            throw NativeDesignBaselineCaptureSourceError.invalidManifest(
                manifestIssues.sorted()
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let canonicalManifest = try? encoder.encode(manifest) else {
            throw NativeDesignBaselineCaptureSourceError.digestConstructionFailed
        }
        let manifestDigest = TaskContractCompiler.digest(canonicalManifest)
        let sourceTree = try digestRegularFile(
            manifest.sourceArtifactPath,
            maximumBytes: maximumProtectedArtifactBytes
        )
        let builtArtifact = try digestRegularFile(
            manifest.builtArtifactPath,
            maximumBytes: maximumProtectedArtifactBytes
        )
        let tokenBytes = try readRegularFile(
            manifest.designTokenSnapshotPath,
            maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
        )
        let semanticBytes = try readRegularFile(
            manifest.semanticSurfaceManifestPath,
            maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
        )
        guard NativeVisualCaptureAdapter.isJSONObjectOrArray(tokenBytes),
              NativeVisualCaptureAdapter.isJSONObjectOrArray(semanticBytes) else {
            throw NativeDesignBaselineCaptureSourceError.invalidManifest([
                "design-token and semantic-surface evidence must be JSON objects or arrays"
            ])
        }

        let captureProtocol = try captureProtocolDigest(manifest.captures)
        var receipts: [NativeCaptureReceipt] = []
        for source in manifest.captures.sorted(by: {
            $0.cellID.rawValue < $1.cellID.rawValue
        }) {
            let navigation = try readRegularFile(
                source.navigationRecipePath,
                maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
            )
            let output = NativeCaptureHarnessOutput(
                encodedImage: try readRegularFile(
                    source.encodedImagePath,
                    maximumBytes: NativeCaptureLimits.platformDefault
                        .maximumEncodedImageBytes
                ),
                accessibilityTree: try readRegularFile(
                    source.accessibilityTreePath,
                    maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
                ),
                observedTraits: source.expectedTraits,
                cleanInstallEvidence: try readRegularFile(
                    source.cleanInstallEvidencePath,
                    maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
                ),
                componentBoundaryTrace: try source.componentBoundaryTracePath.map {
                    try readRegularFile(
                        $0,
                        maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
                    )
                },
                designTokenTrace: try source.designTokenTracePath.map {
                    try readRegularFile(
                        $0,
                        maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
                    )
                },
                fullViewport: source.fullViewport,
                cleanInstall: source.cleanInstall,
                processExitCode: source.processExitCode
            )
            let harness = SelectedCaptureSourceHarness(output: output)
            let adapter = NativeVisualCaptureAdapter(
                harness: harness,
                allowedHarnessIdentities: [harnessIdentity],
                clock: { importedAt }
            )
            do {
                let capture = try await adapter.capture(NativeCaptureRequest(
                    cellID: source.cellID,
                    sourceTree: sourceTree,
                    builtArtifact: builtArtifact,
                    captureProtocol: captureProtocol,
                    expectedTraits: source.expectedTraits,
                    navigationRecipe: navigation,
                    notBefore: importedAt,
                    requiresComponentBoundaryTrace:
                        source.componentBoundaryTracePath != nil,
                    requiresDesignTokenTrace: source.designTokenTracePath != nil
                ))
                receipts.append(capture.receipt)
            } catch let error as NativeVisualCaptureError {
                throw NativeDesignBaselineCaptureSourceError.captureFailed(error)
            }
        }
        let source = NativeDesignBaselineCaptureSource(
            manifestDigest: manifestDigest,
            designBaselineID: manifest.designBaselineID,
            protectedBaselineID: manifest.protectedBaselineID,
            sourceTree: sourceTree,
            builtArtifact: builtArtifact,
            environmentDigest: manifest.environmentDigest,
            captureProtocol: captureProtocol,
            designTokenSnapshot: TaskContractCompiler.digest(tokenBytes),
            semanticSurfaceManifest: TaskContractCompiler.digest(semanticBytes),
            captures: receipts,
            protectedInvariants: manifest.protectedInvariants,
            knownDebt: manifest.knownDebt,
            importedAt: importedAt
        )
        let issues = source.validationIssues()
        guard issues.isEmpty else {
            throw NativeDesignBaselineCaptureSourceError.invalidManifest(
                issues.sorted()
            )
        }
        return source
    }

    private static func validationIssues(
        _ manifest: NativeDesignBaselineCaptureSourceManifest
    ) -> [String] {
        var issues: [String] = []
        if manifest.designBaselineID.rawValue.isEmpty
            || manifest.protectedBaselineID.rawValue.isEmpty {
            issues.append("baseline identities must not be empty")
        }
        let paths = [
            manifest.sourceArtifactPath,
            manifest.builtArtifactPath,
            manifest.designTokenSnapshotPath,
            manifest.semanticSurfaceManifestPath
        ] + manifest.captures.flatMap {
            [
                $0.encodedImagePath,
                $0.accessibilityTreePath,
                $0.cleanInstallEvidencePath,
                $0.navigationRecipePath
            ] + [$0.componentBoundaryTracePath, $0.designTokenTracePath]
                .compactMap { $0 }
        }
        if paths.contains(where: { !validAbsolutePath($0) }) {
            issues.append("every capture-source path must be absolute and canonical")
        }
        let cells = manifest.captures.map(\.cellID)
        if cells.isEmpty || Set(cells).count != cells.count
            || cells.contains(where: { $0.rawValue.isEmpty }) {
            issues.append("capture cells must be non-empty and unique")
        }
        if let environment = manifest.environmentDigest,
           !NativeDesignBaselineCaptureSource.validSHA256(environment) {
            issues.append("environment digest must be exact lowercase SHA-256")
        }
        return issues
    }

    private static func hasExactJSONShape(_ bytes: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: bytes),
              let object = root as? [String: Any],
              Set(object.keys).isSuperset(of: [
                "schemaVersion",
                "designBaselineID",
                "protectedBaselineID",
                "sourceArtifactPath",
                "builtArtifactPath",
                "designTokenSnapshotPath",
                "semanticSurfaceManifestPath",
                "captures",
                "protectedInvariants",
                "knownDebt"
              ]),
              Set(object.keys).isSubset(of: [
                "schemaVersion",
                "designBaselineID",
                "protectedBaselineID",
                "sourceArtifactPath",
                "builtArtifactPath",
                "environmentDigest",
                "designTokenSnapshotPath",
                "semanticSurfaceManifestPath",
                "captures",
                "protectedInvariants",
                "knownDebt"
              ]),
              let captures = object["captures"] as? [[String: Any]],
              captures.allSatisfy({ capture in
                  Set(capture.keys).isSuperset(of: [
                    "cellID",
                    "expectedTraits",
                    "encodedImagePath",
                    "accessibilityTreePath",
                    "cleanInstallEvidencePath",
                    "navigationRecipePath",
                    "fullViewport",
                    "cleanInstall",
                    "processExitCode"
                  ]) && Set(capture.keys).isSubset(of: [
                    "cellID",
                    "expectedTraits",
                    "encodedImagePath",
                    "accessibilityTreePath",
                    "cleanInstallEvidencePath",
                    "navigationRecipePath",
                    "componentBoundaryTracePath",
                    "designTokenTracePath",
                    "fullViewport",
                    "cleanInstall",
                    "processExitCode"
                  ]) && ((capture["expectedTraits"] as? [String: Any]).map {
                      Set($0.keys) == [
                        "deviceClass",
                        "viewportWidthPixels",
                        "viewportHeightPixels",
                        "scale",
                        "operatingSystem",
                        "orientation",
                        "locale",
                        "calendar",
                        "layoutDirection",
                        "appearance",
                        "contrast",
                        "reducedMotion",
                        "boldText",
                        "contentSizeCategory",
                        "fixtureDigest"
                      ]
                  } ?? false)
              }),
              let invariants = object["protectedInvariants"] as? [[String: Any]],
              invariants.allSatisfy({
                  Set($0.keys) == ["id", "dimension", "cellIDs"]
              }),
              let debt = object["knownDebt"] as? [[String: Any]],
              debt.allSatisfy({
                  Set($0.keys) == [
                    "id",
                    "dimension",
                    "cellIDs",
                    "baselineSeverity",
                    "maximumInterimSeverity",
                    "direction",
                    "closureRequired",
                    "evidenceDigest"
                  ]
              }) else {
            return false
        }
        return true
    }

    private static func captureProtocolDigest(
        _ captures: [NativeDesignBaselineCaptureFileSource]
    ) throws -> ContentDigest {
        struct Material: Codable {
            var harnessIdentity: String
            var cells: [Cell]
        }
        struct Cell: Codable {
            var cellID: VisualCellID
            var expectedTraits: VisualTraitSignature
            var navigationRecipeDigest: ContentDigest
            var requiresComponentBoundaryTrace: Bool
            var requiresDesignTokenTrace: Bool
        }
        var cells: [Cell] = []
        for capture in captures.sorted(by: {
            $0.cellID.rawValue < $1.cellID.rawValue
        }) {
            let navigation = try readRegularFile(
                capture.navigationRecipePath,
                maximumBytes: NativeCaptureLimits.platformDefault.maximumEvidenceBytes
            )
            cells.append(Cell(
                cellID: capture.cellID,
                expectedTraits: capture.expectedTraits,
                navigationRecipeDigest: TaskContractCompiler.digest(navigation),
                requiresComponentBoundaryTrace:
                    capture.componentBoundaryTracePath != nil,
                requiresDesignTokenTrace: capture.designTokenTracePath != nil
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(Material(
            harnessIdentity: harnessIdentity,
            cells: cells
        )) else {
            throw NativeDesignBaselineCaptureSourceError.digestConstructionFailed
        }
        return TaskContractCompiler.digest(bytes)
    }

    private static func validAbsolutePath(_ path: String) -> Bool {
        !path.isEmpty
            && path.hasPrefix("/")
            && !path.contains("\0")
            && URL(fileURLWithPath: path).standardizedFileURL.path == path
    }

    private static func digestRegularFile(
        _ path: String,
        maximumBytes: Int
    ) throws -> ContentDigest {
        let descriptor = try openRegularFile(path, maximumBytes: maximumBytes)
        defer { _ = Darwin.close(descriptor) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw NativeDesignBaselineCaptureSourceError.invalidEvidenceFile(path)
            }
            hasher.update(data: Data(buffer[0..<count]))
        }
        return ContentDigest(hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func readRegularFile(
        _ path: String,
        maximumBytes: Int,
        manifest: Bool = false
    ) throws -> Data {
        let descriptor: Int32
        do {
            descriptor = try openRegularFile(path, maximumBytes: maximumBytes)
        } catch {
            if manifest {
                throw NativeDesignBaselineCaptureSourceError.invalidManifestFile
            }
            throw error
        }
        defer { _ = Darwin.close(descriptor) }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: min(1_048_576, maximumBytes))
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                throw NativeDesignBaselineCaptureSourceError.invalidEvidenceFile(path)
            }
            bytes.append(contentsOf: buffer[0..<count])
        }
        return bytes
    }

    private static func openRegularFile(
        _ path: String,
        maximumBytes: Int
    ) throws -> Int32 {
        guard validAbsolutePath(path), maximumBytes > 0 else {
            throw NativeDesignBaselineCaptureSourceError.invalidEvidenceFile(path)
        }
        var before = stat()
        guard lstat(path, &before) == 0,
              before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 0 else {
            throw NativeDesignBaselineCaptureSourceError.invalidEvidenceFile(path)
        }
        guard before.st_size <= off_t(maximumBytes) else {
            throw NativeDesignBaselineCaptureSourceError.evidenceTooLarge(path)
        }
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw NativeDesignBaselineCaptureSourceError.invalidEvidenceFile(path)
        }
        var held = stat()
        guard fstat(descriptor, &held) == 0,
              held.st_mode & S_IFMT == S_IFREG,
              held.st_dev == before.st_dev,
              held.st_ino == before.st_ino,
              held.st_size == before.st_size else {
            _ = Darwin.close(descriptor)
            throw NativeDesignBaselineCaptureSourceError.invalidEvidenceFile(path)
        }
        return descriptor
    }
}

private actor SelectedCaptureSourceHarness: NativeCaptureHarness {
    nonisolated let identity =
        NativeDesignBaselineCaptureSourceLoader.harnessIdentity
    private let output: NativeCaptureHarnessOutput
    private var consumed = false

    init(output: NativeCaptureHarnessOutput) {
        self.output = output
    }

    func capture(
        _ request: NativeCaptureRequest
    ) async throws -> NativeCaptureHarnessOutput {
        guard !consumed else {
            throw NativeDesignBaselineCaptureSourceError.invalidManifest([
                "one selected capture source cannot be replayed"
            ])
        }
        consumed = true
        return output
    }
}
