import Foundation
import XCTest
@testable import LoopForge

final class NativeProviderHarnessSelectionTests: XCTestCase {
    func testExactTransportVetoManifestSelectsPackagedHarnessIdentity() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let selection = try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )

        XCTAssertEqual(selection.executableURL, harnessURL.standardizedFileURL)
        XCTAssertEqual(selection.manifest.protocolVersion, 2)
        XCTAssertEqual(selection.manifest.operationalMode, .transportVetoOnly)
        XCTAssertTrue(selection.manifest.productiveProviderBackends.isEmpty)
        XCTAssertEqual(
            selection.manifest.releaseCapabilityClassification,
            .nonProductiveTransportVeto
        )
        XCTAssertFalse(selection.manifest.productiveExecutionAvailable)
        XCTAssertEqual(
            selection.manifest.releaseMutationCapabilityClassification,
            .nonMutatingContainmentVeto
        )
        XCTAssertFalse(selection.manifest.workspaceMutationAvailable)
        XCTAssertEqual(
            selection.manifest.selfTestSHA256,
            NativeProviderHarnessSelectionLoader.expectedSelfTestSHA256
        )
    }

    func testInternallyConsistentProductiveManifestCannotMintNativeAuthority() throws {
        var fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.manifest.operationalMode = .productive
        fixture.manifest.productiveProviderBackends = [.codex]
        fixture.manifest.selfTestSHA256 = selfTestDigest(
            mode: .productive,
            productiveProviderBackends: [.codex]
        )
        try write(fixture.manifest, to: fixture.manifestURL)

        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .manifestInvalid
            )
        }
    }

    func testDigestAndSelfTestIdentityTamperingFailClosed() throws {
        var fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.manifest.executableSHA256 = digest(Data("wrong".utf8))
        try write(fixture.manifest, to: fixture.manifestURL)
        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .executableIdentityMismatch
            )
        }

        fixture.manifest.executableSHA256 = try XCTUnwrap(
            ProcessGroupRuntimeAdapter.executableContentDigest(
                atPath: harnessURL.path
            )
        )
        fixture.manifest.selfTestSHA256 = digest(Data("wrong-self-test".utf8))
        try write(fixture.manifest, to: fixture.manifestURL)
        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .selfTestIdentityMismatch
            )
        }
    }

    func testProductiveAvailabilityClaimCannotMintNativeAuthority() throws {
        var fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.manifest.productiveExecutionAvailable = true
        try write(fixture.manifest, to: fixture.manifestURL)

        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .manifestInvalid
            )
        }
    }

    func testWorkspaceMutationAvailabilityClaimCannotMintNativeAuthority() throws {
        var fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.manifest.workspaceMutationAvailable = true
        try write(fixture.manifest, to: fixture.manifestURL)

        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .manifestInvalid
            )
        }
    }

    func testUnavailableMutationClassificationCannotRelabelPackagedHarness() throws {
        var fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.manifest.releaseMutationCapabilityClassification =
            .unavailableFailClosed
        try write(fixture.manifest, to: fixture.manifestURL)

        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: fixture.manifestURL,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .manifestInvalid
            )
        }
    }

    func testMissingHarnessClassificationFailsClosed() {
        XCTAssertFalse(
            LoopForgeReleaseCapabilityClassification.unavailableFailClosed
                .productiveExecutionAvailable
        )
        XCTAssertEqual(
            LoopForgeReleaseCapabilityClassification.unavailableFailClosed.title,
            "Execution unavailable"
        )
        XCTAssertFalse(
            LoopForgeReleaseMutationCapabilityClassification
                .unavailableFailClosed.workspaceMutationAvailable
        )
    }

    func testSymlinkedManifestIsNeverTrusted() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let link = fixture.root.appendingPathComponent("linked-manifest.json")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.manifestURL
        )

        XCTAssertThrowsError(try NativeProviderHarnessSelectionLoader.load(
            manifestURL: link,
            executableURL: harnessURL
        )) { error in
            XCTAssertEqual(
                error as? NativeProviderHarnessSelectionError,
                .manifestUnsafe
            )
        }
    }

    private func makeFixture() throws -> (
        root: URL,
        manifestURL: URL,
        manifest: NativeProviderHarnessManifest
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ProviderHarnessSelection-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: harnessURL.path
        )
        let manifest = NativeProviderHarnessManifest(
            schemaVersion: 1,
            protocolVersion: 2,
            executableFileName: "LoopForgeProviderHarness",
            executableSHA256: try XCTUnwrap(
                ProcessGroupRuntimeAdapter.executableContentDigest(
                    atPath: harnessURL.path
                )
            ),
            executableByteCount: try XCTUnwrap(
                attributes[.size] as? NSNumber
            ).uint64Value,
            operationalMode: .transportVetoOnly,
            productiveProviderBackends: [],
            releaseCapabilityClassification: .nonProductiveTransportVeto,
            productiveExecutionAvailable: false,
            releaseMutationCapabilityClassification:
                .nonMutatingContainmentVeto,
            workspaceMutationAvailable: false,
            selfTestSHA256:
                NativeProviderHarnessSelectionLoader.expectedSelfTestSHA256
        )
        let manifestURL = root.appendingPathComponent(
            NativeProviderHarnessSelectionLoader.manifestFileName
        )
        try write(manifest, to: manifestURL)
        return (root, manifestURL, manifest)
    }

    private func write(
        _ manifest: NativeProviderHarnessManifest,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
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

    private func digest(_ data: Data) -> ContentDigest {
        KernelWorkerResultParser.contentDigest(data)
    }

    private func selfTestDigest(
        mode: KernelProviderHarnessMode,
        productiveProviderBackends: [KernelExecutionProvider]
    ) -> ContentDigest {
        let object: [String: Any] = [
            "credentialTransport": "length-prefixed-fd-197",
            "invocationContextTransport": "canonical-json-fd-196",
            "operationalMode": mode.rawValue.replacingOccurrences(
                of: "Only",
                with: "-only"
            ).replacingOccurrences(of: "transportVeto", with: "transport-veto"),
            "productiveProviderBackends": productiveProviderBackends.map(\.rawValue),
            "promptTransport": "exact-stdin",
            "protocolVersion": 2,
            "schemaVersion": 1,
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return KernelWorkerResultParser.contentDigest(data + [0x0a])
    }
}
