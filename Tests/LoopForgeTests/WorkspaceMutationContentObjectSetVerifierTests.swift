import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceMutationContentObjectSetVerifierTests: XCTestCase {
    func testVerifiesExactCompleteBeforeAndAfterContentSet() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeDerivation()
        let objects = material.objects.reversed()

        let receipt = try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: Array(objects)
        )

        XCTAssertTrue(receipt.validationIssues().isEmpty)
        XCTAssertEqual(
            receipt.derivationDigest,
            material.derivation.derivationDigest
        )
        XCTAssertEqual(
            receipt.contentObjects,
            material.derivation.contentObjects
        )
        XCTAssertEqual(receipt.objectCount, material.objects.count)
        XCTAssertEqual(
            receipt.totalBytes,
            UInt64(material.objects.reduce(0) { $0 + $1.data.count })
        )
        XCTAssertFalse(receipt.objectSetDigest.rawValue.isEmpty)
        XCTAssertFalse(receipt.receiptDigest.rawValue.isEmpty)
    }

    func testRejectsMissingAndUnexpectedObjects() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeDerivation()
        let removed = material.objects.last!

        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: Array(material.objects.dropLast())
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .missingObject(removed.digest)
            )
        }

        let extraData = Data("extra".utf8)
        let extra = WorkspaceMutationContentObject(
            digest: WorkspaceMutationFilesystemExecutor.contentDigest(extraData),
            data: extraData
        )
        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: material.objects + [extra]
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .unexpectedObject(extra.digest)
            )
        }
    }

    func testRejectsDuplicateCorruptAndWrongSizedObjects() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeDerivation()
        let first = material.objects[0]

        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: material.objects + [first]
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .duplicateObject(first.digest)
            )
        }

        var corrupt = material.objects
        corrupt[0].data = Data(repeating: 0x78, count: corrupt[0].data.count)
        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: corrupt
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .corruptObject(first.digest)
            )
        }

        var wrongSize = material.objects
        wrongSize[0].data.append(0)
        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: wrongSize
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .objectSizeMismatch(
                    digest: first.digest,
                    actual: UInt64(wrongSize[0].data.count),
                    expected: UInt64(first.data.count)
                )
            )
        }
    }

    func testEnforcesCountPerObjectAndTotalByteLimits() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeDerivation()

        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: material.objects,
            limits: WorkspaceMutationContentObjectSetLimits(
                maximumObjectCount: material.objects.count - 1,
                maximumObjectBytes: 100,
                maximumTotalBytes: 100
            )
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .objectCountLimitExceeded(
                    actual: material.objects.count,
                    maximum: material.objects.count - 1
                )
            )
        }

        let largest = material.objects.max { $0.data.count < $1.data.count }!
        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: material.objects,
            limits: WorkspaceMutationContentObjectSetLimits(
                maximumObjectCount: 100,
                maximumObjectBytes: UInt64(largest.data.count - 1),
                maximumTotalBytes: 100
            )
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectSetVerificationError,
                .objectSizeLimitExceeded(
                    digest: largest.digest,
                    actual: UInt64(largest.data.count),
                    maximum: UInt64(largest.data.count - 1)
                )
            )
        }

        let total = material.objects.reduce(0) { $0 + $1.data.count }
        XCTAssertThrowsError(try WorkspaceMutationContentObjectSetVerifier().verify(
            derivation: material.derivation,
            objects: material.objects,
            limits: WorkspaceMutationContentObjectSetLimits(
                maximumObjectCount: 100,
                maximumObjectBytes: UInt64(total - 1),
                maximumTotalBytes: UInt64(total - 1)
            )
        )) { error in
            guard case let .totalByteLimitExceeded(actual, maximum) =
                    error as? WorkspaceMutationContentObjectSetVerificationError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, maximum)
            XCTAssertEqual(maximum, UInt64(total - 1))
        }
    }

    private struct Fixture {
        struct Material {
            var derivation: WorkspaceMutationOperationDerivationReceipt
            var objects: [WorkspaceMutationContentObject]
        }

        let container: URL
        let root: URL
        let limits = WorkspaceSourceRevisionLimits(
            maximumFiles: 32,
            maximumTotalBytes: 1_048_576,
            maximumFileBytes: 262_144
        )

        init() throws {
            container = FileManager.default.temporaryDirectory.appendingPathComponent(
                "LoopForgeContentSet-\(UUID().uuidString)",
                isDirectory: true
            )
            root = container.appendingPathComponent("workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func makeDerivation() throws -> Material {
            let old = Data("old-a".utf8)
            let removed = Data("removed".utf8)
            let new = Data("new-a-value".utf8)
            let created = Data("created".utf8)
            try write(old, to: "Sources/a.txt")
            try write(removed, to: "Sources/deleted.txt")
            let base = try capture()
            try write(new, to: "Sources/a.txt")
            try FileManager.default.removeItem(
                at: root.appendingPathComponent("Sources/deleted.txt")
            )
            try write(created, to: "Sources/new.txt")
            let candidate = try capture()
            let derivation = try WorkspaceMutationOperationDeriver().derive(
                base: base,
                candidate: candidate,
                requirementIDs: [RequirementID("requirement-a")],
                authorizedPaths: [
                    "Sources/a.txt", "Sources/deleted.txt", "Sources/new.txt"
                ]
            )
            let data = [old, removed, new, created]
            return Material(
                derivation: derivation,
                objects: data.map {
                    WorkspaceMutationContentObject(
                        digest: WorkspaceMutationFilesystemExecutor.contentDigest($0),
                        data: $0
                    )
                }.sorted { $0.digest.rawValue < $1.digest.rawValue }
            )
        }

        func write(_ data: Data, to relativePath: String) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
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
