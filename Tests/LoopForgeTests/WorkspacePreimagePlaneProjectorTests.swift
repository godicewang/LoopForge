import Foundation
import XCTest
@testable import LoopForge

final class WorkspacePreimagePlaneProjectorTests: XCTestCase {
    func testProjectsExactInitialWorktreePlaneFromConfirmedSourceRevision() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("shared", to: "Sources/a.txt")
        try fixture.write("shared", to: "Sources/b.txt")
        try fixture.write("unique", to: "root.txt")
        let source = try fixture.capture()

        let artifact = try WorkspacePreimagePlaneProjector()
            .projectInitialWorktree(from: source)

        XCTAssertTrue(artifact.validationIssues().isEmpty)
        XCTAssertEqual(artifact.provenance, .confirmedWorkspaceSourceRevision)
        XCTAssertEqual(artifact.plane, .worktree)
        XCTAssertEqual(artifact.workspaceID, source.workspaceID)
        XCTAssertEqual(artifact.rootIdentity, source.canonicalRootDigest)
        XCTAssertEqual(artifact.sourceRevision, source.sourceRevision)
        XCTAssertEqual(artifact.entries.map(\.path), [
            "Sources/a.txt", "Sources/b.txt", "root.txt"
        ])
        XCTAssertTrue(artifact.entries.allSatisfy {
            $0.plane == .worktree
                && $0.kind == .regularFile
                && $0.ownership == .userExisting
        })
        XCTAssertEqual(artifact.contentObjects.count, 2)
        XCTAssertFalse(artifact.artifactDigest.rawValue.isEmpty)
    }

    func testCoverageAssessmentReportsEveryUnobservedPlane() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("value", to: "file.txt")
        let artifact = try WorkspacePreimagePlaneProjector()
            .projectInitialWorktree(from: fixture.capture())

        let assessment = try WorkspacePreimagePlaneProjector().assessCoverage(
            requiredPlanes: [.head, .index, .worktree, .untracked],
            artifacts: [artifact]
        )

        XCTAssertFalse(assessment.isComplete)
        XCTAssertEqual(assessment.acceptedPlanes, [.worktree])
        XCTAssertEqual(assessment.missingPlanes, [.head, .index, .untracked])
    }

    func testTamperedPlaneArtifactIsRejectedBeforeCoverage() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("value", to: "file.txt")
        var artifact = try WorkspacePreimagePlaneProjector()
            .projectInitialWorktree(from: fixture.capture())
        artifact.entries[0].mode ^= 0o100

        XCTAssertFalse(artifact.validationIssues().isEmpty)
        XCTAssertThrowsError(try WorkspacePreimagePlaneProjector().assessCoverage(
            requiredPlanes: [.worktree],
            artifacts: [artifact]
        )) { error in
            XCTAssertEqual(
                error as? WorkspacePreimagePlaneProjectionError,
                .invalidPlaneArtifact(0)
            )
        }
    }

    func testDuplicatePlaneCannotManufactureAdditionalCoverage() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        try fixture.write("value", to: "file.txt")
        let artifact = try WorkspacePreimagePlaneProjector()
            .projectInitialWorktree(from: fixture.capture())

        XCTAssertThrowsError(try WorkspacePreimagePlaneProjector().assessCoverage(
            requiredPlanes: [.worktree],
            artifacts: [artifact, artifact]
        )) { error in
            XCTAssertEqual(
                error as? WorkspacePreimagePlaneProjectionError,
                .duplicatePlane(.worktree)
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
                "LoopForgePreimagePlane-\(UUID().uuidString)",
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
