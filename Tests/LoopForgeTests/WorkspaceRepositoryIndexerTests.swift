import Foundation
import XCTest
@testable import LoopForge

final class WorkspaceRepositoryIndexerTests: XCTestCase {
    func testJournalBoundGenerationComputesOnceAndChangedGenerationInvalidates() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Sources/Feature.swift")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("let value = 1\n".utf8).write(to: source)
        let cache = HeavyEvidenceCache(rootDirectory: nil)
        let indexer = WorkspaceRepositoryIndexer(heavyEvidenceCache: cache)
        let firstReceipt = try generationReceipt(
            root: root,
            generation: "tree-generation-1",
            startingSequence: 4
        )

        let first = try await indexer.resolve(root: root, generationReceipt: firstReceipt)
        let unchanged = try await indexer.resolve(root: root, generationReceipt: firstReceipt)
        try Data("let value = 200\n".utf8).write(to: source, options: .atomic)
        let secondReceipt = try generationReceipt(
            root: root,
            generation: "tree-generation-2",
            startingSequence: 5
        )
        let changed = try await indexer.resolve(root: root, generationReceipt: secondReceipt)

        XCTAssertEqual(first.disposition, .computed)
        XCTAssertEqual(unchanged.disposition, .memoryHit)
        XCTAssertEqual(unchanged.index, first.index)
        XCTAssertEqual(changed.disposition, .computed)
        XCTAssertNotEqual(changed.index.observedMetadataDigest, first.index.observedMetadataDigest)
        XCTAssertEqual(changed.index.entries.first?.size, Int64("let value = 200\n".utf8.count))
        let metrics = await cache.snapshotMetrics()
        XCTAssertEqual(metrics.computationCount, 2)
        XCTAssertEqual(metrics.memoryHitCount, 1)
    }

    func testMissingGenerationReceiptAlwaysPerformsUncachedObservation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("main.swift")
        try Data("a".utf8).write(to: source)
        let cache = HeavyEvidenceCache(rootDirectory: nil)
        let indexer = WorkspaceRepositoryIndexer(heavyEvidenceCache: cache)

        let first = try await indexer.resolve(root: root, generationReceipt: nil)
        try Data("expanded".utf8).write(to: source, options: .atomic)
        let second = try await indexer.resolve(root: root, generationReceipt: nil)

        XCTAssertEqual(first.disposition, .uncachedObservation)
        XCTAssertEqual(second.disposition, .uncachedObservation)
        XCTAssertNil(first.cacheReceipt)
        XCTAssertNil(second.cacheReceipt)
        XCTAssertNotEqual(first.index.observedMetadataDigest, second.index.observedMetadataDigest)
        XCTAssertTrue(second.evidenceSummary.contains("no authoritative tree-generation receipt"))
        let metrics = await cache.snapshotMetrics()
        XCTAssertEqual(metrics.lookupCount, 0)
        XCTAssertEqual(metrics.computationCount, 0)
    }

    func testGenerationReceiptCannotBeReusedForDifferentCanonicalRoot() async throws {
        let firstRoot = try temporaryDirectory()
        let secondRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let receipt = try generationReceipt(
            root: firstRoot,
            generation: "root-bound-generation",
            startingSequence: 0
        )
        let indexer = WorkspaceRepositoryIndexer(heavyEvidenceCache: HeavyEvidenceCache(rootDirectory: nil))

        do {
            _ = try await indexer.resolve(root: secondRoot, generationReceipt: receipt)
            XCTFail("a generation receipt must remain bound to its canonical workspace root")
        } catch let error as WorkspaceRepositoryIndexError {
            XCTAssertEqual(error, .workspaceRootMismatch)
        }
    }

    func testIncompleteJournalProvenanceCannotMintGenerationAuthority() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invalid = JournalTransactionReceipt(
            commandID: RunCommandID("command-without-events"),
            startingSequence: 2,
            endingSequence: 2,
            eventIDs: [],
            frameDigest: HeavyEvidenceCache.sha256("frame"),
            duplicate: false
        )

        XCTAssertThrowsError(
            try WorkspaceTreeGenerationReceipt.testOnlyAccepted(
                workspaceID: WorkspaceID("workspace"),
                root: root,
                generationDigest: HeavyEvidenceCache.sha256("tree"),
                authority: .journaledMutationCommit,
                journalTransaction: invalid
            )
        )
    }

    func testRepositoryIndexIgnoresGeneratedTreesAndSymbolicLinks() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data("source".utf8).write(to: root.appendingPathComponent("source.swift"))
        let generated = root.appendingPathComponent("node_modules/package/index.js")
        try FileManager.default.createDirectory(
            at: generated.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("generated".utf8).write(to: generated)
        let outsideFile = outside.appendingPathComponent("secret.txt")
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.txt"),
            withDestinationURL: outsideFile
        )

        let index = try WorkspaceRepositoryIndexer.scan(root: root)

        XCTAssertEqual(index.entries.map(\.relativePath), ["source.swift"])
    }

    private func generationReceipt(
        root: URL,
        generation: String,
        startingSequence: UInt64
    ) throws -> WorkspaceTreeGenerationReceipt {
        let endingSequence = startingSequence
        let transaction = JournalTransactionReceipt(
            commandID: RunCommandID("command-\(endingSequence)"),
            startingSequence: startingSequence,
            endingSequence: endingSequence,
            eventIDs: [OrchestrationEventID("event-\(endingSequence)")],
            frameDigest: HeavyEvidenceCache.sha256("frame-\(endingSequence)"),
            duplicate: false
        )
        return try WorkspaceTreeGenerationReceipt.testOnlyAccepted(
            workspaceID: WorkspaceID("synthetic-workspace"),
            root: root,
            generationDigest: HeavyEvidenceCache.sha256(generation),
            authority: .journaledMutationCommit,
            journalTransaction: transaction
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeRepositoryIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
