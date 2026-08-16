import Darwin
import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceSourceRevisionCollectorTests: XCTestCase {
    func testRevisionIsContentModePathAndPolicyBoundButTimestampIndependent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("alpha", to: "Sources/a.txt")
        try fixture.write("beta", to: "Sources/b.txt")
        try fixture.write("ignored", to: ".build/cache.bin")

        let first = try fixture.capture(excluding: [".build"])
        XCTAssertTrue(first.validationIssues().isEmpty)
        XCTAssertEqual(first.excludedDirectoryNames, [".build"])
        XCTAssertEqual(first.limits, fixture.limits)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 99)],
            ofItemAtPath: fixture.root.appendingPathComponent("Sources/a.txt").path
        )
        let timestampOnly = try fixture.capture(excluding: [".build"])
        XCTAssertEqual(timestampOnly.sourceRevision, first.sourceRevision)
        XCTAssertEqual(first.entries.map(\.relativePath), ["Sources/a.txt", "Sources/b.txt"])
        XCTAssertEqual(first.totalBytes, 9)

        try fixture.write("ALPHA", to: "Sources/a.txt")
        let contentChanged = try fixture.capture(excluding: [".build"])
        XCTAssertNotEqual(contentChanged.sourceRevision, first.sourceRevision)

        XCTAssertEqual(
            Darwin.chmod(
                fixture.root.appendingPathComponent("Sources/a.txt").path,
                0o700
            ),
            0
        )
        let modeChanged = try fixture.capture(excluding: [".build"])
        XCTAssertNotEqual(modeChanged.sourceRevision, contentChanged.sourceRevision)

        let policyChanged = try fixture.capture(excluding: [])
        XCTAssertNotEqual(policyChanged.sourceRevision, modeChanged.sourceRevision)
        XCTAssertEqual(policyChanged.entries.count, 3)
    }

    func testSymlinkAndBoundsFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("12345", to: "one.txt")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.root.appendingPathComponent("link.txt").path,
            withDestinationPath: "one.txt"
        )
        XCTAssertThrowsError(try fixture.capture(excluding: [])) { error in
            XCTAssertEqual(error as? WorkspaceSourceRevisionError, .symbolicLink("link.txt"))
        }

        try FileManager.default.removeItem(
            at: fixture.root.appendingPathComponent("link.txt")
        )
        try FileManager.default.createSymbolicLink(
            atPath: fixture.root.appendingPathComponent(".build").path,
            withDestinationPath: "one.txt"
        )
        XCTAssertThrowsError(try fixture.capture(excluding: [".build"])) { error in
            XCTAssertEqual(error as? WorkspaceSourceRevisionError, .symbolicLink(".build"))
        }
        try FileManager.default.removeItem(
            at: fixture.root.appendingPathComponent(".build")
        )

        XCTAssertThrowsError(try fixture.capture(
            excluding: [],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 4,
                maximumTotalBytes: 4,
                maximumFileBytes: 4
            )
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceSourceRevisionError,
                .fileByteLimitExceeded(path: "one.txt", actual: 5, maximum: 4)
            )
        }

        try fixture.write("x", to: "two.txt")
        XCTAssertThrowsError(try fixture.capture(
            excluding: [],
            limits: WorkspaceSourceRevisionLimits(
                maximumFiles: 1,
                maximumTotalBytes: 100,
                maximumFileBytes: 100
            )
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceSourceRevisionError,
                .fileLimitExceeded(actual: 2, maximum: 1)
            )
        }
    }

    func testWorkspaceIdentityAndExcludedDirectoryPolicyAreRevisionAuthority() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("same", to: "file.txt")
        let first = try fixture.capture(excluding: [])
        let otherWorkspace = try WorkspaceSourceRevisionCollector().capture(
            workspaceID: WorkspaceID("other-workspace"),
            root: fixture.root,
            excludedDirectoryNames: [],
            limits: fixture.limits
        )
        XCTAssertNotEqual(first.sourceRevision, otherWorkspace.sourceRevision)
        XCTAssertNotEqual(first.canonicalRootDigest.rawValue, "")
        XCTAssertNotEqual(first.capturePolicyDigest.rawValue, "")

        var tampered = first
        tampered.totalBytes += 1
        XCTAssertTrue(tampered.validationIssues().contains {
            $0.contains("total bytes")
        })
        XCTAssertTrue(tampered.validationIssues().contains {
            $0.contains("revision digest mismatch")
        })
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
                "LoopForgeSourceRevision-\(UUID().uuidString)",
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

        func capture(
            excluding: Set<String>,
            limits: WorkspaceSourceRevisionLimits? = nil
        ) throws -> WorkspaceSourceRevisionArtifact {
            try WorkspaceSourceRevisionCollector().capture(
                workspaceID: WorkspaceID("workspace"),
                root: root,
                excludedDirectoryNames: excluding,
                limits: limits ?? self.limits
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: container)
        }
    }
}
