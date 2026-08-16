import Foundation
@testable import LoopForge
import XCTest

final class WorkspaceCompletedCandidateMutationRollbackRehearsalTests:
    XCTestCase
{
    func testRichRollbackAuthorityDoesNotInflateCentralReducerEnvelopes() {
        XCTAssertLessThanOrEqual(MemoryLayout<RunCommand>.size, 4_096)
        XCTAssertLessThanOrEqual(
            MemoryLayout<OrchestrationEventPayload>.size,
            4_096
        )
    }

    func testOwnerPrivateReplicaExecutesEveryRegularFileInverseAndCleansUp()
        throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sentinel = fixture.canonical.appendingPathComponent("sentinel.txt")
        try Data("canonical must remain unchanged\n".utf8).write(to: sentinel)

        let beforeA = Data("before-a\n".utf8)
        let afterA = Data("after-a\n".utf8)
        let beforeB = Data("before-b\n".utf8)
        let created = Data("created\n".utf8)
        let chmodBytes = Data("#!/bin/sh\nexit 0\n".utf8)
        let objects = [beforeA, afterA, beforeB, created, chmodBytes].reduce(
            into: [ContentDigest: Data]()) { result, data in
                result[WorkspaceMutationFilesystemExecutor.contentDigest(data)] = data
            }
        let receipt = ReceiptID("path-resolution")
        let requirement = RequirementID("requirement")
        let operations = [
            MutationOperation(
                sequence: 1,
                kind: .modify,
                sourcePath: nil,
                destinationPath: "a.txt",
                expectedPreimage:
                    WorkspaceMutationFilesystemExecutor.contentDigest(beforeA),
                desiredPostimage:
                    WorkspaceMutationFilesystemExecutor.contentDigest(afterA),
                entryKindBefore: .regularFile,
                entryKindAfter: .regularFile,
                modeBefore: 0o644,
                modeAfter: 0o644,
                requirementIDs: [requirement],
                pathResolutionReceiptID: receipt
            ),
            MutationOperation(
                sequence: 2,
                kind: .delete,
                sourcePath: "b.txt",
                destinationPath: nil,
                expectedPreimage:
                    WorkspaceMutationFilesystemExecutor.contentDigest(beforeB),
                desiredPostimage: nil,
                entryKindBefore: .regularFile,
                entryKindAfter: nil,
                modeBefore: 0o600,
                modeAfter: nil,
                requirementIDs: [requirement],
                pathResolutionReceiptID: receipt
            ),
            MutationOperation(
                sequence: 3,
                kind: .create,
                sourcePath: nil,
                destinationPath: "sub/new.txt",
                expectedPreimage: nil,
                desiredPostimage:
                    WorkspaceMutationFilesystemExecutor.contentDigest(created),
                entryKindBefore: nil,
                entryKindAfter: .regularFile,
                modeBefore: nil,
                modeAfter: 0o640,
                requirementIDs: [requirement],
                pathResolutionReceiptID: receipt
            ),
            MutationOperation(
                sequence: 4,
                kind: .chmod,
                sourcePath: nil,
                destinationPath: "tool.sh",
                expectedPreimage:
                    WorkspaceMutationFilesystemExecutor.contentDigest(chmodBytes),
                desiredPostimage:
                    WorkspaceMutationFilesystemExecutor.contentDigest(chmodBytes),
                entryKindBefore: .regularFile,
                entryKindAfter: .regularFile,
                modeBefore: 0o644,
                modeAfter: 0o755,
                requirementIDs: [requirement],
                pathResolutionReceiptID: receipt
            ),
        ]
        let manifest = MutationManifest(
            transactionID: IntegrationTransactionID("transaction"),
            candidateID: MutationCandidateID("candidate"),
            contractDigest: digest("contract"),
            planNodeDigest: digest("plan"),
            basePreimageDigest: digest("preimage"),
            operations: operations,
            touchedRequirementIDs: [requirement],
            writeAuthorityReceiptID: ReceiptID("write"),
            mutationBudgetReceiptID: ReceiptID("budget"),
            candidateVerificationReceiptIDs: [ReceiptID("verification")],
            independentReviewReceiptID: ReceiptID("review"),
            rollbackRehearsalReceiptID: ReceiptID("rollback"),
            candidateQuiescenceReceiptID: ReceiptID("quiescence"),
            visualGateReceiptID: nil,
            expectedPostimageDigest: digest("postimage")
        )
        let rollback = TransactionalMutationKernel.rollbackPlan(
            forward: manifest,
            preimageDigest: manifest.basePreimageDigest
        )
        let replica = try WorkspaceMutationOwnerPrivateRollbackReplica(
            canonicalWorkspaceRoot: fixture.canonical,
            storageRoot: fixture.storage
        )
        let evidence: WorkspaceMutationRollbackReplicaEvidence
        do {
            evidence = try replica.executeCycle(
                forward: operations,
                inverse: rollback.operations,
                objects: objects
            )
            try replica.cleanup()
        } catch {
            try? replica.cleanup()
            throw error
        }

        XCTAssertEqual(evidence.initialDigest, evidence.restoredDigest)
        XCTAssertNotEqual(evidence.initialDigest, evidence.appliedDigest)
        XCTAssertEqual(
            evidence.paths,
            ["a.txt", "b.txt", "sub/new.txt", "tool.sh"]
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.storage.path
            ),
            []
        )
        XCTAssertEqual(
            try String(contentsOf: sentinel, encoding: .utf8),
            "canonical must remain unchanged\n"
        )
    }

    private func digest(_ value: String) -> ContentDigest {
        WorkspaceMutationFilesystemExecutor.contentDigest(Data(value.utf8))
    }

    private final class Fixture {
        let root: URL
        let canonical: URL
        let storage: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "loopforge-rollback-rehearsal-tests-\(UUID().uuidString)",
                isDirectory: true
            )
            canonical = root.appendingPathComponent("canonical", isDirectory: true)
            storage = root.appendingPathComponent("storage", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            for directory in [canonical, storage] {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
                )
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
