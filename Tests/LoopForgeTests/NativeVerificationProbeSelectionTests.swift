import Darwin
import Foundation
import XCTest
@testable import LoopForge

final class NativeVerificationProbeSelectionTests: XCTestCase {
    func testSelectedExecutableIsRehashedIntoFixedKernelProbe() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let selection = try NativeVerificationProbeSelectionLoader.load(
            manifestURL: fixture.manifestURL
        )

        XCTAssertEqual(
            selection.probe.executableContentDigest,
            TaskContractCompiler.digest(fixture.executableBytes)
        )
        XCTAssertEqual(
            selection.probe.environmentIdentityDigest,
            KernelProcessEnvironmentAuthorizer.environmentDigest(
                KernelProcessEnvironmentAuthorizer.minimalEnvironment
            )
        )
        XCTAssertEqual(
            selection.probe.captureIdentityDigest,
            KernelPostimageVerifierCapturePolicy.identityDigest
        )
        XCTAssertEqual(selection.probe.schemaVersion, 2)
        XCTAssertEqual(selection.probe.transport, .localDirectProcess)
        XCTAssertEqual(selection.probe.networkPolicy, .disabled)
        XCTAssertEqual(
            selection.probe.resourceLimits.maximumChildProcesses,
            0
        )
        XCTAssertEqual(
            selection.probe.inputBindings,
            [RequirementVerificationInputBinding(
                id: "candidate-postimage",
                kind: .candidatePostimage,
                artifactID: "journal-owned-candidate-postimage",
                argumentToken: "@loopforge-input:candidate-postimage"
            )]
        )
        XCTAssertTrue(selection.probe.validationIssues().isEmpty)
        XCTAssertNotNil(
            KernelPostimageVerifierActivationCompiler.probeDigest(
                selection.probe
            )
        )
    }

    func testUnknownManifestAuthorityAndUnboundInputFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.loopForge.encode(fixture.manifest)
            ) as? [String: Any]
        )
        object["networkPolicy"] = "enabled"
        try JSONSerialization.data(withJSONObject: object).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        XCTAssertThrowsError(
            try NativeVerificationProbeSelectionLoader.load(
                manifestURL: fixture.manifestURL
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeVerificationProbeSelectionError,
                .malformedManifest
            )
        }

        var manifest = fixture.manifest
        manifest.fixedArguments.append("@loopforge-input:undeclared")
        try JSONEncoder.loopForge.encode(manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        XCTAssertThrowsError(
            try NativeVerificationProbeSelectionLoader.load(
                manifestURL: fixture.manifestURL
            )
        ) { error in
            guard case .invalidManifest(let issues) =
                    error as? NativeVerificationProbeSelectionError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(issues.contains("undeclared verifier input tokens are forbidden"))
        }
    }

    func testSymlinkedOrNonExecutableVerifierFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let link = fixture.root.appendingPathComponent("verifier-link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.executableURL
        )
        var manifest = fixture.manifest
        manifest.executablePath = link.path
        try JSONEncoder.loopForge.encode(manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        XCTAssertThrowsError(
            try NativeVerificationProbeSelectionLoader.load(
                manifestURL: fixture.manifestURL
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeVerificationProbeSelectionError,
                .invalidExecutable(link.path)
            )
        }

        XCTAssertEqual(chmod(fixture.executableURL.path, 0o644), 0)
        try JSONEncoder.loopForge.encode(fixture.manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        XCTAssertThrowsError(
            try NativeVerificationProbeSelectionLoader.load(
                manifestURL: fixture.manifestURL
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeVerificationProbeSelectionError,
                .invalidExecutable(fixture.executableURL.path)
            )
        }
    }

    func testResourceAndResultBudgetsCannotBeWidened() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        manifest.maximumWallClockSeconds = 3_601
        manifest.maximumCapturedOutputBytes = 67_108_865
        manifest.maximumResidentBytes = 8_589_934_593
        manifest.resultMappings = [RequirementVerificationResultMapping(
            exitCode: 1,
            parserResultCode: "rejected",
            outcome: .rejected
        )]
        try JSONEncoder.loopForge.encode(manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )

        XCTAssertThrowsError(
            try NativeVerificationProbeSelectionLoader.load(
                manifestURL: fixture.manifestURL
            )
        ) { error in
            guard case .invalidManifest(let issues) =
                    error as? NativeVerificationProbeSelectionError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(issues.count, 4)
            XCTAssertTrue(issues.contains {
                $0.contains("include an accepted result")
            })
        }
    }

    func testConfirmationRevalidationRejectsExecutableDrift() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let selection = try NativeVerificationProbeSelectionLoader.load(
            manifestURL: fixture.manifestURL
        )
        XCTAssertEqual(
            try NativeVerificationProbeSelectionLoader.revalidate(selection),
            selection
        )

        try Data("changed-verifier-bytes".utf8).write(
            to: fixture.executableURL,
            options: .atomic
        )
        XCTAssertEqual(chmod(fixture.executableURL.path, 0o755), 0)
        XCTAssertThrowsError(
            try NativeVerificationProbeSelectionLoader.revalidate(selection)
        ) { error in
            XCTAssertEqual(
                error as? NativeVerificationProbeSelectionError,
                .selectionChanged
            )
        }
    }
}

private final class Fixture {
    let root: URL
    let manifestURL: URL
    let executableURL: URL
    let executableBytes = Data("synthetic-deterministic-verifier".utf8)
    var manifest: NativeVerificationProbeManifest

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeNativeVerifier-\(UUID().uuidString)",
            isDirectory: true
        ).standardizedFileURL
        manifestURL = root.appendingPathComponent("verifier.json")
        executableURL = root.appendingPathComponent("verifier")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try executableBytes.write(to: executableURL)
        guard chmod(executableURL.path, 0o755) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        manifest = NativeVerificationProbeManifest(
            schemaVersion: 1,
            executablePath: executableURL.path,
            fixedArguments: [
                "--candidate",
                "@loopforge-input:candidate-postimage",
                "--canonical-json"
            ],
            resultMappings: [
                RequirementVerificationResultMapping(
                    exitCode: 0,
                    parserResultCode: "accepted",
                    outcome: .accepted
                ),
                RequirementVerificationResultMapping(
                    exitCode: 1,
                    parserResultCode: "rejected",
                    outcome: .rejected
                )
            ],
            maximumWallClockSeconds: 60,
            maximumCapturedOutputBytes: 1_048_576,
            maximumResidentBytes: 268_435_456
        )
        try JSONEncoder.loopForge.encode(manifest).write(
            to: manifestURL,
            options: .atomic
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
