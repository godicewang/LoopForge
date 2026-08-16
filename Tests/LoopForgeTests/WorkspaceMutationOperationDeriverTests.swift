import Darwin
import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceMutationOperationDeriverTests: XCTestCase {
    func testDerivesCanonicalRegularFileDeltaWithoutEffectAuthority() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("old", to: "Sources/a.txt")
        try fixture.write("remove", to: "Sources/deleted.txt")
        try fixture.write("mode", to: "Sources/mode.txt")
        try fixture.setMode(0o600, for: "Sources/mode.txt")
        let base = try fixture.capture()

        try fixture.write("new-value", to: "Sources/a.txt")
        try fixture.write("created", to: "Sources/created.txt")
        try fixture.remove("Sources/deleted.txt")
        try fixture.setMode(0o700, for: "Sources/mode.txt")
        let candidate = try fixture.capture()
        let requirements: Set<RequirementID> = [RequirementID("requirement-a")]

        let receipt = try WorkspaceMutationOperationDeriver().derive(
            base: base,
            candidate: candidate,
            requirementIDs: requirements,
            authorizedPaths: [
                "Sources/a.txt",
                "Sources/created.txt",
                "Sources/deleted.txt",
                "Sources/mode.txt"
            ]
        )

        XCTAssertTrue(receipt.validationIssues().isEmpty)
        XCTAssertEqual(receipt.baseSourceRevision, base.sourceRevision)
        XCTAssertEqual(receipt.candidateSourceRevision, candidate.sourceRevision)
        XCTAssertEqual(receipt.touchedRequirementIDs, requirements)
        XCTAssertEqual(receipt.operations.map(\.sequence), [1, 2, 3, 4])
        XCTAssertEqual(receipt.operations.map(\.path), [
            "Sources/a.txt",
            "Sources/created.txt",
            "Sources/deleted.txt",
            "Sources/mode.txt"
        ])
        XCTAssertEqual(receipt.operations.map(\.kind), [
            .modify, .create, .delete, .chmod
        ])
        XCTAssertTrue(receipt.operations.allSatisfy {
            $0.requirementIDs == requirements
        })
        XCTAssertFalse(receipt.derivationDigest.rawValue.isEmpty)
    }

    func testMatchingContentAtDifferentPathsDoesNotInferRenameIntent() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("anchor", to: "Sources/anchor.txt")
        try fixture.write("same-content", to: "Sources/old.txt")
        let base = try fixture.capture()

        try fixture.remove("Sources/old.txt")
        try fixture.write("same-content", to: "Sources/new.txt")
        let candidate = try fixture.capture()
        let receipt = try WorkspaceMutationOperationDeriver().derive(
            base: base,
            candidate: candidate,
            requirementIDs: [RequirementID("requirement-a")],
            authorizedPaths: ["Sources/new.txt", "Sources/old.txt"]
        )

        XCTAssertEqual(receipt.operations.map(\.kind), [.create, .delete])
        XCTAssertFalse(receipt.operations.contains { $0.kind == .rename })
    }

    func testRejectsCombinedContentAndModeChange() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("before", to: "file.txt")
        try fixture.setMode(0o600, for: "file.txt")
        let base = try fixture.capture()
        try fixture.write("after", to: "file.txt")
        try fixture.setMode(0o700, for: "file.txt")
        let candidate = try fixture.capture()

        XCTAssertThrowsError(try WorkspaceMutationOperationDeriver().derive(
            base: base,
            candidate: candidate,
            requirementIDs: [RequirementID("requirement-a")],
            authorizedPaths: ["file.txt"]
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationOperationDerivationError,
                .simultaneousContentAndModeChange("file.txt")
            )
        }
    }

    func testRejectsNewParentTopology() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("anchor", to: "anchor.txt")
        let base = try fixture.capture()
        try fixture.write("new", to: "NewDirectory/file.txt")
        let candidate = try fixture.capture()

        XCTAssertThrowsError(try WorkspaceMutationOperationDeriver().derive(
            base: base,
            candidate: candidate,
            requirementIDs: [RequirementID("requirement-a")],
            authorizedPaths: ["NewDirectory/file.txt"]
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationOperationDerivationError,
                .unsupportedParentTopology("NewDirectory/file.txt")
            )
        }
    }

    func testRejectsPathAuthorityAndArtifactIdentityMismatch() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("before", to: "file.txt")
        let base = try fixture.capture()
        try fixture.write("after", to: "file.txt")
        let candidate = try fixture.capture()

        XCTAssertThrowsError(try WorkspaceMutationOperationDeriver().derive(
            base: base,
            candidate: candidate,
            requirementIDs: [RequirementID("requirement-a")],
            authorizedPaths: []
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationOperationDerivationError,
                .pathOutsideAuthority("file.txt")
            )
        }

        let otherFixture = try Fixture()
        defer { otherFixture.removeAll() }
        try otherFixture.write("after", to: "file.txt")
        let otherRoot = try otherFixture.capture()
        XCTAssertThrowsError(try WorkspaceMutationOperationDeriver().derive(
            base: base,
            candidate: otherRoot,
            requirementIDs: [RequirementID("requirement-a")],
            authorizedPaths: ["file.txt"]
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationOperationDerivationError,
                .canonicalRootMismatch
            )
        }
    }

    private struct Fixture {
        let container: URL
        let root: URL
        let limits = WorkspaceSourceRevisionLimits(
            maximumFiles: 32,
            maximumTotalBytes: 1_048_576,
            maximumFileBytes: 262_144
        )

        init() throws {
            container = FileManager.default.temporaryDirectory.appendingPathComponent(
                "LoopForgeMutationDerivation-\(UUID().uuidString)",
                isDirectory: true
            )
            root = container.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func write(_ value: String, to relativePath: String) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(value.utf8).write(to: url)
        }

        func remove(_ relativePath: String) throws {
            try FileManager.default.removeItem(
                at: root.appendingPathComponent(relativePath)
            )
        }

        func setMode(_ mode: mode_t, for relativePath: String) throws {
            XCTAssertEqual(
                Darwin.chmod(root.appendingPathComponent(relativePath).path, mode),
                0
            )
        }

        func capture() throws -> WorkspaceSourceRevisionArtifact {
            try WorkspaceSourceRevisionCollector().capture(
                workspaceID: WorkspaceID("workspace"),
                root: root,
                excludedDirectoryNames: [],
                limits: limits
            )
        }

        func removeAll() {
            try? FileManager.default.removeItem(at: container)
        }
    }
}
