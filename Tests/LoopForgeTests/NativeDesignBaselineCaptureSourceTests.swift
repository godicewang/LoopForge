import Foundation
import XCTest
@testable import LoopForge

final class NativeDesignBaselineCaptureSourceTests: XCTestCase {
    func testSelectedFilesAreRehashedAttestedAndBoundIntoContract() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let importedAt = Date(timeIntervalSince1970: 2_000)

        let source = try await NativeDesignBaselineCaptureSourceLoader.load(
            manifestURL: fixture.manifestURL,
            importedAt: importedAt
        )

        XCTAssertEqual(
            source.sourceTree,
            TaskContractCompiler.digest(fixture.sourceArchive)
        )
        XCTAssertEqual(
            source.builtArtifact,
            TaskContractCompiler.digest(fixture.builtArchive)
        )
        XCTAssertEqual(source.captures.count, 1)
        XCTAssertEqual(source.captures[0].capturedAt, importedAt)
        XCTAssertEqual(
            source.captures[0].harnessIdentity,
            NativeDesignBaselineCaptureSourceLoader.harnessIdentity
        )
        XCTAssertTrue(source.validationIssues().isEmpty)

        var request = fixture.contractRequest
        request.designBaselineSource = source
        request.recordedAt = Date(timeIntervalSince1970: 2_001)
        let draft: NativeTaskContractConfirmationDraft
        switch NativeTaskContractAuthor.prepare(request) {
        case .success(let value): draft = value
        case .failure(let error):
            return XCTFail("contract authoring failed: \(error)")
        }
        let selection = try XCTUnwrap(draft.displayDesignBaselineSelection)
        XCTAssertEqual(selection.builtArtifact, source.builtArtifact)
        XCTAssertEqual(selection.sourceTree, source.sourceTree)
        XCTAssertEqual(selection.captures, source.captures)
        XCTAssertEqual(
            selection.requirementIDs,
            draft.compiled.candidate.contract.mandatoryRequirementIDs
        )
        XCTAssertEqual(
            draft.compiled.candidate.contract.protectedBaselines,
            [BaselineReference(
                id: source.protectedBaselineID,
                artifactDigest: source.builtArtifact,
                environmentDigest: source.environmentDigest,
                preservationRequired: true
            )]
        )
        XCTAssertTrue(draft.compiled.candidate.contract.constraints.contains {
            $0.kind == .preserve
        })
        XCTAssertTrue(
            draft.compiled.candidate.sources.contains {
                $0.id.rawValue.hasPrefix("native-design-baseline-")
                    && $0.authority == .user
            }
        )

        let encoded = try JSONEncoder.loopForge.encode(
            draft.compiled.candidate
        )
        let decoded = try JSONDecoder.loopForge.decode(
            TaskContractCompilationCandidate.self,
            from: encoded
        )
        switch TaskContractCompiler.compile(decoded) {
        case .success(let replayed):
            XCTAssertEqual(
                replayed.candidateDigest,
                draft.compiled.candidateDigest
            )
        case .failure(let failure):
            XCTFail("baseline-bound candidate did not replay: \(failure.issues)")
        }
    }

    func testSymlinkedEvidenceAndDuplicateCellsFailClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let link = fixture.root.appendingPathComponent("built-link.zip")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.builtURL
        )
        var manifest = fixture.manifest
        manifest.builtArtifactPath = link.path
        try JSONEncoder.loopForge.encode(manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        do {
            _ = try await NativeDesignBaselineCaptureSourceLoader.load(
                manifestURL: fixture.manifestURL
            )
            XCTFail("symlinked artifact unexpectedly imported")
        } catch let error as NativeDesignBaselineCaptureSourceError {
            XCTAssertEqual(error, .invalidEvidenceFile(link.path))
        }

        manifest = fixture.manifest
        manifest.captures.append(manifest.captures[0])
        try JSONEncoder.loopForge.encode(manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        do {
            _ = try await NativeDesignBaselineCaptureSourceLoader.load(
                manifestURL: fixture.manifestURL
            )
            XCTFail("duplicate visual cell unexpectedly imported")
        } catch let error as NativeDesignBaselineCaptureSourceError {
            guard case .invalidManifest(let issues) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(issues.contains {
                $0.contains("capture cells must be non-empty and unique")
            })
        }
    }

    func testContractRejectsImportedSourceThatPostdatesAuthoring() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try await NativeDesignBaselineCaptureSourceLoader.load(
            manifestURL: fixture.manifestURL,
            importedAt: Date(timeIntervalSince1970: 4_000)
        )
        var request = fixture.contractRequest
        request.recordedAt = Date(timeIntervalSince1970: 3_999)
        request.designBaselineSource = source

        guard case .failure(.invalidDesignBaselineSource(let issues)) =
            NativeTaskContractAuthor.prepare(request) else {
            return XCTFail("postdated import unexpectedly became authority")
        }
        XCTAssertTrue(issues.contains {
            $0.contains("cannot postdate contract authoring")
        })
    }

    func testUnknownSchemaKeysAndLifecycleClaimsFailClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.loopForge.encode(fixture.manifest)
            ) as? [String: Any]
        )
        object["workerNarrative"] = "trust this capture"
        try JSONSerialization.data(withJSONObject: object).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        do {
            _ = try await NativeDesignBaselineCaptureSourceLoader.load(
                manifestURL: fixture.manifestURL
            )
            XCTFail("unknown manifest key unexpectedly accepted")
        } catch let error as NativeDesignBaselineCaptureSourceError {
            XCTAssertEqual(error, .malformedManifest)
        }

        var manifest = fixture.manifest
        manifest.captures[0].fullViewport = false
        try JSONEncoder.loopForge.encode(manifest).write(
            to: fixture.manifestURL,
            options: .atomic
        )
        do {
            _ = try await NativeDesignBaselineCaptureSourceLoader.load(
                manifestURL: fixture.manifestURL
            )
            XCTFail("incomplete viewport unexpectedly accepted")
        } catch let error as NativeDesignBaselineCaptureSourceError {
            XCTAssertEqual(error, .captureFailed(.incompleteLifecycleEvidence))
        }
    }
}

private final class Fixture {
    let root: URL
    let workspace: URL
    let manifestURL: URL
    let sourceURL: URL
    let builtURL: URL
    let sourceArchive = Data("exact-source-archive".utf8)
    let builtArchive = Data("exact-built-artifact".utf8)
    let user = ActorIdentity(
        id: ActorID("native-design-user"),
        role: "user",
        lineageDigest: ContentDigest(String(repeating: "a", count: 64))
    )

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForgeNativeDesignSource-\(UUID().uuidString)",
            isDirectory: true
        ).standardizedFileURL
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        manifestURL = root.appendingPathComponent("baseline.json")
        sourceURL = root.appendingPathComponent("source.zip")
        builtURL = root.appendingPathComponent("artifact.zip")
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        try sourceArchive.write(to: sourceURL)
        try builtArchive.write(to: builtURL)
        try Data(#"{"tokens":["semantic.primary"]}"#.utf8).write(
            to: root.appendingPathComponent("tokens.json")
        )
        try Data(#"{"surfaces":["root"]}"#.utf8).write(
            to: root.appendingPathComponent("semantic.json")
        )
        try png.write(to: root.appendingPathComponent("capture.png"))
        try Data(#"{"role":"window","children":[]}"#.utf8).write(
            to: root.appendingPathComponent("accessibility.json")
        )
        try Data(#"{"dataReset":true,"restartCount":1}"#.utf8).write(
            to: root.appendingPathComponent("clean-install.json")
        )
        try Data(#"{"steps":["clean-install","launch"]}"#.utf8).write(
            to: root.appendingPathComponent("navigation.json")
        )
        try Data(#"{"components":["root"]}"#.utf8).write(
            to: root.appendingPathComponent("components.json")
        )
        try Data(#"{"tokens":["semantic.primary"]}"#.utf8).write(
            to: root.appendingPathComponent("trace.json")
        )
        try JSONEncoder.loopForge.encode(manifest).write(
            to: manifestURL,
            options: .atomic
        )
    }

    var manifest: NativeDesignBaselineCaptureSourceManifest {
        NativeDesignBaselineCaptureSourceManifest(
            schemaVersion: 1,
            designBaselineID: DesignBaselineID("native-design-baseline"),
            protectedBaselineID: BaselineID("protected-product-artifact"),
            sourceArtifactPath: sourceURL.path,
            builtArtifactPath: builtURL.path,
            environmentDigest: ContentDigest(String(repeating: "b", count: 64)),
            designTokenSnapshotPath: root.appendingPathComponent("tokens.json").path,
            semanticSurfaceManifestPath: root.appendingPathComponent("semantic.json").path,
            captures: [NativeDesignBaselineCaptureFileSource(
                cellID: VisualCellID("primary.standard.en.light"),
                expectedTraits: traits,
                encodedImagePath: root.appendingPathComponent("capture.png").path,
                accessibilityTreePath: root.appendingPathComponent("accessibility.json").path,
                cleanInstallEvidencePath: root.appendingPathComponent("clean-install.json").path,
                navigationRecipePath: root.appendingPathComponent("navigation.json").path,
                componentBoundaryTracePath: root.appendingPathComponent("components.json").path,
                designTokenTracePath: root.appendingPathComponent("trace.json").path,
                fullViewport: true,
                cleanInstall: true,
                processExitCode: 0
            )],
            protectedInvariants: [DesignInvariant(
                id: "typography-hierarchy",
                dimension: .typographyHierarchy,
                cellIDs: [VisualCellID("primary.standard.en.light")]
            )],
            knownDebt: []
        )
    }

    var contractRequest: NativeTaskContractAuthoringRequest {
        NativeTaskContractAuthoringRequest(
            exactObjective: "Improve the selected product while preserving its protected design identity.",
            workspaceID: WorkspaceID("native-design-workspace"),
            workspaceRoot: workspace,
            readableScopes: ["."],
            writableScopes: ["."],
            acceptedDuration: nil,
            executionProfile: KernelExecutionProfile(
                schemaVersion: 1,
                worker: profile(
                    id: "worker",
                    sandbox: .workspaceOnly,
                    digest: String(repeating: "c", count: 64)
                ),
                independentReviewer: profile(
                    id: "reviewer",
                    sandbox: .readOnly,
                    digest: String(repeating: "d", count: 64)
                ),
                requiresDistinctActorLineage: true
            ),
            verificationProbe: verificationProbe,
            executionBudgets: KernelExecutionBudgetPolicy(
                mutation: KernelMutationBudget(
                    maximumChangedFiles: 8,
                    maximumChangedBytes: 65_536
                ),
                convergence: ConvergenceBudget(
                    maximumAttempts: 3,
                    maximumEquivalentFailures: 3,
                    maximumStrategies: 2,
                    maximumPlanExpansions: 1,
                    maximumMutationCost: 65_536,
                    maximumVerificationCost: 8,
                    maximumDamageEvents: 0,
                    maximumExternalEffects: 0
                )
            ),
            userActor: user,
            recordedAt: Date(timeIntervalSince1970: 2_001),
            authoringNonce: ContentDigest(String(repeating: "e", count: 64))
        )
    }

    private func profile(
        id: String,
        sandbox: KernelExecutionSandbox,
        digest: String
    ) -> KernelAgentExecutionProfile {
        KernelAgentExecutionProfile(
            provider: .codex,
            providerReference: "provider-\(id)",
            executableContentDigest: ContentDigest(digest),
            modelID: "model-\(id)",
            reasoningEffort: "high",
            sandbox: sandbox,
            networkPolicy: .disabled,
            pluginPolicy: .disabled,
            environmentPolicy: .minimalKernelAllowlist
        )
    }

    private var verificationProbe: RequirementVerificationExecutableProbe {
        RequirementVerificationExecutableProbe(
            schemaVersion: 2,
            transport: .localDirectProcess,
            executableContentDigest: ContentDigest(String(repeating: "f", count: 64)),
            fixedArguments: ["--input", "@loopforge-input:candidate-postimage"],
            inputBindings: [RequirementVerificationInputBinding(
                id: "candidate-postimage",
                kind: .candidatePostimage,
                artifactID: "candidate-postimage",
                argumentToken: "@loopforge-input:candidate-postimage"
            )],
            environmentPolicy: .minimalKernelAllowlist,
            environmentIdentityDigest: ContentDigest(String(repeating: "1", count: 64)),
            captureIdentityDigest: ContentDigest(String(repeating: "2", count: 64)),
            parser: RequirementVerificationParserContract(
                id: "canonical-json-result",
                schemaVersion: 1,
                contentDigest: RequirementVerificationParserFormat
                    .canonicalJSONResultV1.implementationIdentityDigest,
                format: .canonicalJSONResultV1
            ),
            resultMappings: [RequirementVerificationResultMapping(
                exitCode: 0,
                parserResultCode: "accepted",
                outcome: .accepted
            )],
            unmatchedOutcome: .rejected,
            networkPolicy: .disabled,
            resourceLimits: RequirementVerificationResourceLimits(
                maximumWallClockSeconds: 60,
                maximumCapturedOutputBytes: 1_048_576,
                maximumResidentBytes: 268_435_456,
                maximumChildProcesses: 0
            )
        )
    }

    private var traits: VisualTraitSignature {
        VisualTraitSignature(
            deviceClass: "synthetic-desktop",
            viewportWidthPixels: 1,
            viewportHeightPixels: 1,
            scale: 1,
            operatingSystem: "synthetic-os-1",
            orientation: "landscape",
            locale: "en-US",
            calendar: "gregorian",
            layoutDirection: "left-to-right",
            appearance: "light",
            contrast: "standard",
            reducedMotion: false,
            boldText: false,
            contentSizeCategory: "large",
            fixtureDigest: ContentDigest(String(repeating: "3", count: 64))
        )
    }

    private var png: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
