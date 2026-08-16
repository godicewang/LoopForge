import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceMutationContentObjectStoreTests: XCTestCase {
    func testMaterializesReadOnlyContentAddressedObjectsAndReusesExactArtifact() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeMaterial()
        let store = WorkspaceMutationContentObjectStore()

        let first = try store.materialize(
            verification: material.verification,
            objects: Array(material.objects.reversed()),
            workspaceRoot: fixture.workspace,
            storageRoot: fixture.storage
        )
        let second = try store.materialize(
            verification: material.verification,
            objects: material.objects,
            workspaceRoot: fixture.workspace,
            storageRoot: fixture.storage
        )

        XCTAssertTrue(first.validationIssues().isEmpty)
        XCTAssertEqual(first.materialization, .streamWrite)
        XCTAssertFalse(first.reusedExistingArtifact)
        XCTAssertEqual(second.materialization, .existingArtifact)
        XCTAssertTrue(second.reusedExistingArtifact)
        XCTAssertEqual(first.artifactPath, second.artifactPath)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(first.inode, second.inode)
        XCTAssertEqual(first.objectCount, material.objects.count)
        XCTAssertEqual(first.totalBytes, material.verification.totalBytes)
        XCTAssertEqual(try store.revalidate(first, verification: material.verification), first)

        let artifact = URL(fileURLWithPath: first.artifactPath, isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: artifact.path)
            .sorted()
        XCTAssertEqual(names, material.objects.map(\.digest.rawValue).sorted())
        for object in material.objects {
            let url = artifact.appendingPathComponent(object.digest.rawValue)
            XCTAssertEqual(try Data(contentsOf: url), object.data)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            XCTAssertEqual(
                (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0,
                0o400
            )
        }
    }

    func testTamperedOrExtraArtifactBytesFailRevalidationAndReuse() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeMaterial()
        let store = WorkspaceMutationContentObjectStore()
        let receipt = try store.materialize(
            verification: material.verification,
            objects: material.objects,
            workspaceRoot: fixture.workspace,
            storageRoot: fixture.storage
        )
        let artifact = URL(fileURLWithPath: receipt.artifactPath, isDirectory: true)
        let target = artifact.appendingPathComponent(
            material.objects[0].digest.rawValue
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: artifact.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: target.path
        )
        try Data(repeating: 0x78, count: material.objects[0].data.count).write(
            to: target,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: target.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: artifact.path
        )

        XCTAssertThrowsError(try store.revalidate(
            receipt,
            verification: material.verification
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .existingArtifactMismatch
            )
        }
        XCTAssertThrowsError(try store.materialize(
            verification: material.verification,
            objects: material.objects,
            workspaceRoot: fixture.workspace,
            storageRoot: fixture.storage
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .existingArtifactMismatch
            )
        }

        let extraFixture = try Fixture()
        defer { extraFixture.removeAll() }
        let extraMaterial = try extraFixture.makeMaterial()
        let extraReceipt = try store.materialize(
            verification: extraMaterial.verification,
            objects: extraMaterial.objects,
            workspaceRoot: extraFixture.workspace,
            storageRoot: extraFixture.storage
        )
        let extraArtifact = URL(
            fileURLWithPath: extraReceipt.artifactPath,
            isDirectory: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: extraArtifact.path
        )
        let unexpected = extraArtifact.appendingPathComponent("unexpected")
        try Data("unexpected".utf8).write(to: unexpected)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: unexpected.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: extraArtifact.path
        )
        XCTAssertThrowsError(try store.revalidate(
            extraReceipt,
            verification: extraMaterial.verification
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .existingArtifactMismatch
            )
        }
    }

    func testRejectsOverlappingStorageAndSymlinkedStoreDirectory() throws {
        let overlap = try Fixture()
        defer { overlap.removeAll() }
        let overlapMaterial = try overlap.makeMaterial()
        XCTAssertThrowsError(try WorkspaceMutationContentObjectStore().materialize(
            verification: overlapMaterial.verification,
            objects: overlapMaterial.objects,
            workspaceRoot: overlap.workspace,
            storageRoot: overlap.workspace
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .storageOverlapsWorkspace
            )
        }

        let symlink = try Fixture()
        defer { symlink.removeAll() }
        let symlinkMaterial = try symlink.makeMaterial()
        let outside = symlink.container.appendingPathComponent(
            "outside-store",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createSymbolicLink(
            at: symlink.storage.appendingPathComponent(
                WorkspaceMutationContentObjectStore.directoryName
            ),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try WorkspaceMutationContentObjectStore().materialize(
            verification: symlinkMaterial.verification,
            objects: symlinkMaterial.objects,
            workspaceRoot: symlink.workspace,
            storageRoot: symlink.storage
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .unsafeStoreDirectory
            )
        }

        let artifactSymlink = try Fixture()
        defer { artifactSymlink.removeAll() }
        let artifactMaterial = try artifactSymlink.makeMaterial()
        let storeRoot = artifactSymlink.storage.appendingPathComponent(
            WorkspaceMutationContentObjectStore.directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: storeRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let outsideArtifact = artifactSymlink.container.appendingPathComponent(
            "outside-artifact",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outsideArtifact,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o500]
        )
        try FileManager.default.createSymbolicLink(
            at: storeRoot.appendingPathComponent(
                artifactMaterial.verification.receiptDigest.rawValue
            ),
            withDestinationURL: outsideArtifact
        )
        XCTAssertThrowsError(try WorkspaceMutationContentObjectStore().materialize(
            verification: artifactMaterial.verification,
            objects: artifactMaterial.objects,
            workspaceRoot: artifactSymlink.workspace,
            storageRoot: artifactSymlink.storage
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .unsafeExistingArtifact
            )
        }
    }

    func testRejectsChangedInputBytesAndUnsafeStorageRoot() throws {
        let fixture = try Fixture()
        defer { fixture.removeAll() }
        let material = try fixture.makeMaterial()
        var changed = material.objects
        changed[0].data = Data(repeating: 0x78, count: changed[0].data.count)
        XCTAssertThrowsError(try WorkspaceMutationContentObjectStore().materialize(
            verification: material.verification,
            objects: changed,
            workspaceRoot: fixture.workspace,
            storageRoot: fixture.storage
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .inputObjectSetMismatch
            )
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.storage.path
        )
        XCTAssertThrowsError(try WorkspaceMutationContentObjectStore().materialize(
            verification: material.verification,
            objects: material.objects,
            workspaceRoot: fixture.workspace,
            storageRoot: fixture.storage
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationContentObjectStoreError,
                .invalidStorageRoot
            )
        }
    }

    private final class Fixture {
        struct Material {
            var verification: WorkspaceMutationContentObjectSetReceipt
            var objects: [WorkspaceMutationContentObject]
        }

        let container: URL
        let workspace: URL
        let storage: URL
        let limits = WorkspaceSourceRevisionLimits(
            maximumFiles: 32,
            maximumTotalBytes: 1_048_576,
            maximumFileBytes: 262_144
        )

        init() throws {
            container = FileManager.default.temporaryDirectory.appendingPathComponent(
                "LoopForgeContentStore-\(UUID().uuidString)",
                isDirectory: true
            )
            workspace = container.appendingPathComponent("workspace", isDirectory: true)
            storage = container.appendingPathComponent("storage", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workspace,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: storage,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        func makeMaterial() throws -> Material {
            let old = Data("old-value".utf8)
            let new = Data("new-value-longer".utf8)
            try write(old, to: "Sources/value.txt")
            let base = try capture()
            try write(new, to: "Sources/value.txt")
            let candidate = try capture()
            let derivation = try WorkspaceMutationOperationDeriver().derive(
                base: base,
                candidate: candidate,
                requirementIDs: [RequirementID("requirement-a")],
                authorizedPaths: ["Sources/value.txt"]
            )
            let objects = [old, new].map {
                WorkspaceMutationContentObject(
                    digest: WorkspaceMutationFilesystemExecutor.contentDigest($0),
                    data: $0
                )
            }
            let verification = try WorkspaceMutationContentObjectSetVerifier()
                .verify(derivation: derivation, objects: objects)
            return Material(verification: verification, objects: objects)
        }

        private func write(_ data: Data, to relativePath: String) throws {
            let url = workspace.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }

        private func capture() throws -> WorkspaceSourceRevisionArtifact {
            try WorkspaceSourceRevisionCollector().capture(
                workspaceID: WorkspaceID("workspace"),
                root: workspace,
                excludedDirectoryNames: [],
                limits: limits
            )
        }

        func removeAll() {
            try? makeWritable(container)
            try? FileManager.default.removeItem(at: container)
        }

        private func makeWritable(_ url: URL) throws {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) {
                var paths: [URL] = []
                for case let child as URL in enumerator { paths.append(child) }
                for child in paths.reversed() {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: 0o700],
                        ofItemAtPath: child.path
                    )
                }
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        }
    }
}
