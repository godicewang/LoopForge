import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceCompletedCandidateCaptureTests: XCTestCase {
    func testCompletedCaptureProjectsLogicalWorkspaceAndRetainsExactBytes()
        throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let materializer = WorkspaceCandidatePostimageMaterializer()
        let isolation = try fixture.isolation(materializer: materializer)
        defer { isolation.close() }
        let executionRoot = try materializer.activatePreApplyIsolation(isolation)
        defer { executionRoot.close() }
        let candidateRoot = URL(
            fileURLWithPath: isolation.receipt.candidateRootPath,
            isDirectory: true
        )
        let modified = Data("let value = 2\n".utf8)
        let created = Data("let added = true\n".utf8)
        try modified.write(
            to: candidateRoot.appendingPathComponent("Sources/a.swift")
        )
        try created.write(
            to: candidateRoot.appendingPathComponent("Sources/b.swift")
        )
        try FileManager.default.createDirectory(
            at: candidateRoot.appendingPathComponent(".build"),
            withIntermediateDirectories: false
        )
        try Data("excluded".utf8).write(
            to: candidateRoot.appendingPathComponent(".build/worker.bin")
        )

        let capture = try materializer.captureCompletedCandidate(
            executionRoot,
            completion: fixture.completion(disposition: .completed),
            captureActor: fixture.actor,
            capturedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertTrue(capture.validationIssues().isEmpty)
        XCTAssertEqual(capture.candidateRevision.workspaceID, fixture.base.workspaceID)
        XCTAssertEqual(
            capture.candidateRevision.canonicalRootDigest,
            fixture.base.canonicalRootDigest
        )
        XCTAssertNotEqual(
            capture.receipt.candidateCanonicalRootDigest,
            fixture.base.canonicalRootDigest
        )
        XCTAssertNotEqual(
            capture.candidateRevision.sourceRevision,
            fixture.base.sourceRevision
        )
        XCTAssertEqual(
            Set(capture.candidateRevision.entries.map(\.relativePath)),
            ["README.md", "Sources/a.swift", "Sources/b.swift"]
        )
        XCTAssertFalse(capture.candidateRevision.entries.contains {
            $0.relativePath.hasPrefix(".build/")
        })
        XCTAssertEqual(
            Set(capture.objects.map(\.data)),
            [Data("baseline\n".utf8), modified, created]
        )
        XCTAssertEqual(capture.receipt.fileCount, 3)
        XCTAssertEqual(capture.receipt.objectCount, 3)

        let derivation = try WorkspaceMutationOperationDeriver().derive(
            base: fixture.base,
            candidate: capture.candidateRevision,
            requirementIDs: [RequirementID("requirement")],
            authorizedPaths: ["Sources/a.swift", "Sources/b.swift"]
        )
        XCTAssertEqual(derivation.operations.map(\.kind), [.modify, .create])
        XCTAssertEqual(
            derivation.operations.map(\.path),
            ["Sources/a.swift", "Sources/b.swift"]
        )
        XCTAssertTrue(
            Set(derivation.operations.compactMap(\.desiredPostimage)).isSubset(
                of: Set(capture.objects.map(\.digest))
            )
        )
    }

    func testCaptureRejectsNonCompletedOrMismatchedCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let materializer = WorkspaceCandidatePostimageMaterializer()
        let isolation = try fixture.isolation(materializer: materializer)
        defer { isolation.close() }
        let executionRoot = try materializer.activatePreApplyIsolation(isolation)
        defer { executionRoot.close() }

        XCTAssertThrowsError(try materializer.captureCompletedCandidate(
            executionRoot,
            completion: fixture.completion(disposition: .continuationNeeded),
            captureActor: fixture.actor,
            capturedAt: Date(timeIntervalSince1970: 20)
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceCompletedCandidateCaptureError,
                .invalidCompletion
            )
        }
        var mismatched = fixture.completion(disposition: .completed)
        mismatched.parse.parse.attemptID = AttemptID("other-attempt")
        XCTAssertThrowsError(try materializer.captureCompletedCandidate(
            executionRoot,
            completion: mismatched,
            captureActor: fixture.actor,
            capturedAt: Date(timeIntervalSince1970: 20)
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceCompletedCandidateCaptureError,
                .invalidCompletion
            )
        }
    }

    private struct Fixture {
        let container: URL
        let workspace: URL
        let runDirectory: URL
        let base: WorkspaceSourceRevisionArtifact
        let actor = ActorIdentity(
            id: ActorID("capture-actor"),
            role: "kernel-worker",
            lineageDigest: ContentDigest("capture-lineage")
        )
        let runID = KernelRunID("capture-run")
        let contractID = TaskContractID("capture-contract")
        let attemptID = AttemptID("capture-attempt")
        let nodeID = KernelNodeID("capture-node")
        let strategy = StrategyFingerprint("capture-strategy")

        init() throws {
            container = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "LoopForge-CompletedCandidateCapture-\(UUID().uuidString)",
                    isDirectory: true
                )
            workspace = container.appendingPathComponent(
                "workspace",
                isDirectory: true
            )
            runDirectory = container.appendingPathComponent(
                "journal/runs/capture-run",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: workspace.appendingPathComponent("Sources"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: workspace.appendingPathComponent(".build"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: runDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try Data("let value = 1\n".utf8).write(
                to: workspace.appendingPathComponent("Sources/a.swift")
            )
            try Data("baseline\n".utf8).write(
                to: workspace.appendingPathComponent("README.md")
            )
            try Data("excluded".utf8).write(
                to: workspace.appendingPathComponent(".build/cache.bin")
            )
            base = try WorkspaceSourceRevisionCollector().capture(
                workspaceID: WorkspaceID("logical-workspace"),
                root: workspace,
                excludedDirectoryNames: [".build", ".git"],
                limits: WorkspaceSourceRevisionLimits(
                    maximumFiles: 16,
                    maximumTotalBytes: 1_048_576,
                    maximumFileBytes: 1_048_576
                )
            )
        }

        func isolation(
            materializer: WorkspaceCandidatePostimageMaterializer
        ) throws -> AuthorizedWorkspacePreApplyCandidateIsolation {
            try materializer.materializePreApplyIsolation(
                runID: runID,
                contractID: contractID,
                attemptID: attemptID,
                nodeID: nodeID,
                strategyFingerprint: strategy,
                isolationActor: actor,
                sourceRevision: base,
                enrollmentJournalFrameDigest: digest("enrollment"),
                workspaceRoot: workspace,
                runDirectory: runDirectory,
                isolatedAt: Date(timeIntervalSince1970: 10)
            )
        }

        func completion(
            disposition: KernelExecutionDisposition
        ) -> KernelProductionProviderCompletionReceipt {
            let resourceID = OwnedResourceID("capture-resource")
            let leaseID = ResourceLeaseID("capture-lease")
            let identity = RuntimeExternalIdentity(
                stableDigest: digest("process"),
                processID: 123,
                processStartMonotonicNanoseconds: 10
            )
            let handle = ManagedProcessHandle(
                runID: runID,
                resourceID: resourceID,
                leaseID: leaseID,
                processID: 123,
                processGroupID: 123,
                externalIdentity: identity
            )
            let exit = ManagedProcessExitReceipt(
                handle: handle,
                observedAtMonotonicNanoseconds: 11,
                exitCode: 0,
                terminationSignal: nil
            )
            let releaseID = ReceiptID("capture-release")
            let release = RuntimeReleaseOutcomeReceipt(
                id: releaseID,
                runID: runID,
                resourceID: resourceID,
                leaseID: leaseID,
                observedAt: Date(timeIntervalSince1970: 11),
                observedAtMonotonicNanoseconds: 11,
                outcome: .released(RuntimeReleaseReceipt(
                    id: releaseID,
                    runID: runID,
                    leaseID: leaseID,
                    resourceID: resourceID,
                    releasedAtMonotonicNanoseconds: 11,
                    duplicate: false
                )),
                managedProcessTermination: nil,
                managedProcessExit: exit
            )
            let resultDigest = digest("result")
            let parseID = ReceiptID("capture-parse")
            let parse = KernelWorkerResultParseReceipt(
                id: parseID,
                parserIdentityDigest: KernelWorkerResultParser.parserIdentityDigest,
                runID: runID,
                attemptID: attemptID,
                resourceID: resourceID,
                leaseID: leaseID,
                bindingReceiptID: ReceiptID("capture-binding"),
                releaseReceiptID: releaseID,
                invocationDigest: digest("invocation"),
                requestNonce: digest("nonce"),
                threadID: "capture-thread",
                eventCount: 1,
                stdoutContentDigest: digest("stdout"),
                stderrContentDigest: digest("stderr"),
                terminalEnvelopeDigest: digest("terminal"),
                proposedDisposition: .completed,
                proposedResultDigest: resultDigest,
                nativeExit: exit
            )
            let execution = KernelExecutionDerivationReceipt(
                id: ReceiptID("capture-execution"),
                runID: runID,
                attemptID: attemptID,
                source: .workerResultParse(parseID),
                sourceEvidenceDigest: resultDigest,
                disposition: disposition,
                derivedAt: Date(timeIntervalSince1970: 13)
            )
            return KernelProductionProviderCompletionReceipt(
                release: JournaledProcessNaturalReleaseReceipt(
                    exit: exit,
                    release: release,
                    journalTransaction: transaction("release", sequence: 1)
                ),
                parse: JournaledWorkerResultParseReceipt(
                    parse: parse,
                    journalTransaction: transaction("parse", sequence: 2)
                ),
                execution: JournaledExecutionDerivationReceipt(
                    execution: execution,
                    journalTransaction: transaction("execution", sequence: 3)
                )
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: container)
        }

        private func transaction(
            _ name: String,
            sequence: UInt64
        ) -> JournalTransactionReceipt {
            JournalTransactionReceipt(
                commandID: RunCommandID("\(name)-command"),
                startingSequence: sequence,
                endingSequence: sequence,
                eventIDs: [OrchestrationEventID("\(name)-event")],
                frameDigest: digest("\(name)-frame"),
                duplicate: false
            )
        }

        private func digest(_ value: String) -> ContentDigest {
            KernelWorkerResultParser.contentDigest(Data(value.utf8))
        }
    }
}
