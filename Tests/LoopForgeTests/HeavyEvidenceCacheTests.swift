import Foundation
import XCTest
@testable import LoopForge

final class HeavyEvidenceCacheTests: XCTestCase {
    private struct Projection: Codable, Equatable, Sendable {
        var value: String
        var count: Int
    }

    private actor Counter {
        private(set) var value = 0

        func increment() -> Int {
            value += 1
            return value
        }

        func current() -> Int { value }
    }

    func testKeyIdentityIsContentAddressedAndInputOrderIndependent() throws {
        let first = key(
            operation: .visualPairMeasurement,
            version: 3,
            inputs: [
                HeavyEvidenceInput(role: "candidate", digest: digest("candidate")),
                HeavyEvidenceInput(role: "baseline", digest: digest("baseline"))
            ]
        )
        let reordered = key(
            operation: .visualPairMeasurement,
            version: 3,
            inputs: first.inputs.reversed()
        )

        XCTAssertEqual(try first.digest(), try reordered.digest())
        XCTAssertNotEqual(
            try first.digest(),
            try key(operation: .visualPairMeasurement, version: 4, inputs: first.inputs).digest()
        )
        XCTAssertNotEqual(
            try first.digest(),
            try key(
                operation: .visualPairMeasurement,
                version: 3,
                inputs: [
                    HeavyEvidenceInput(role: "candidate", digest: digest("changed")),
                    HeavyEvidenceInput(role: "baseline", digest: digest("baseline"))
                ]
            ).digest()
        )
    }

    func testInvalidOrAmbiguousIdentityFailsClosed() throws {
        var invalid = key(operation: .repositoryIndex)
        invalid.inputs[0].digest = ContentDigest("filename-only")
        XCTAssertThrowsError(try invalid.digest())

        var duplicateRoles = key(operation: .visualPairMeasurement)
        duplicateRoles.inputs.append(duplicateRoles.inputs[0])
        XCTAssertThrowsError(try duplicateRoles.digest())
    }

    func testUnchangedHeavyWorkComputesOnceThenUsesMemory() async throws {
        let counter = Counter()
        let cache = HeavyEvidenceCache(rootDirectory: nil)
        let cacheKey = key(operation: .repositoryIndex)

        let first: HeavyEvidenceCacheResolution<Projection> = try await cache.resolve(key: cacheKey) {
            let count = await counter.increment()
            return Projection(value: "indexed-tree", count: count)
        }
        let second: HeavyEvidenceCacheResolution<Projection> = try await cache.resolve(key: cacheKey) {
            let count = await counter.increment()
            return Projection(value: "must-not-run", count: count)
        }

        XCTAssertEqual(first.value, Projection(value: "indexed-tree", count: 1))
        XCTAssertEqual(second.value, first.value)
        XCTAssertEqual(first.receipt.disposition, .computed)
        XCTAssertEqual(second.receipt.disposition, .memoryHit)
        let computationCount = await counter.current()
        XCTAssertEqual(computationCount, 1)
        let metrics = await cache.snapshotMetrics()
        XCTAssertEqual(metrics.computationCount, 1)
        XCTAssertEqual(metrics.memoryHitCount, 1)
    }

    func testPersistentHitSurvivesFreshCacheInstanceWithoutRecomputation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = Counter()
        let cacheKey = key(operation: .imageInspection)
        let first = HeavyEvidenceCache(rootDirectory: directory)

        let miss: HeavyEvidenceCacheResolution<Projection> = try await first.resolve(key: cacheKey) {
            let count = await counter.increment()
            return Projection(value: "decoded-and-ocrd", count: count)
        }
        let reopened = HeavyEvidenceCache(rootDirectory: directory)
        let hit: HeavyEvidenceCacheResolution<Projection> = try await reopened.resolve(key: cacheKey) {
            let count = await counter.increment()
            return Projection(value: "must-not-run", count: count)
        }

        XCTAssertEqual(miss.value, hit.value)
        XCTAssertEqual(hit.receipt.disposition, .diskHit)
        let computationCount = await counter.current()
        let reopenedMetrics = await reopened.snapshotMetrics()
        XCTAssertEqual(computationCount, 1)
        XCTAssertEqual(reopenedMetrics.persistentWriteCount, 0)
    }

    func testConcurrentIdenticalMissesCoalesceOneHeavyComputation() async throws {
        let cache = HeavyEvidenceCache(rootDirectory: nil)
        let counter = Counter()
        let cacheKey = key(operation: .imageInspection)

        async let first: HeavyEvidenceCacheResolution<Projection> = cache.resolve(key: cacheKey) {
            let count = await counter.increment()
            await Task.yield()
            return Projection(value: "image-result", count: count)
        }
        async let second: HeavyEvidenceCacheResolution<Projection> = cache.resolve(key: cacheKey) {
            let count = await counter.increment()
            return Projection(value: "duplicate", count: count)
        }
        let results = try await [first, second]

        XCTAssertEqual(results[0].value, results[1].value)
        let computationCount = await counter.current()
        let metrics = await cache.snapshotMetrics()
        XCTAssertEqual(computationCount, 1)
        XCTAssertEqual(metrics.computationCount, 1)
    }

    func testCollectorVersionAndContentDigestInvalidateExactlyTheirEntry() async throws {
        let cache = HeavyEvidenceCache(rootDirectory: nil)
        let counter = Counter()
        let original = key(operation: .imageInspection, version: 1)
        let changedVersion = key(operation: .imageInspection, version: 2)
        let changedContent = key(
            operation: .imageInspection,
            version: 1,
            inputs: [HeavyEvidenceInput(role: "image", digest: digest("different-image"))]
        )

        for cacheKey in [original, original, changedVersion, changedContent] {
            let _: HeavyEvidenceCacheResolution<Projection> = try await cache.resolve(key: cacheKey) {
                Projection(value: "result", count: await counter.increment())
            }
        }

        let computationCount = await counter.current()
        XCTAssertEqual(computationCount, 3)
        let metrics = await cache.snapshotMetrics()
        XCTAssertEqual(metrics.computationCount, 3)
        XCTAssertEqual(metrics.memoryHitCount, 1)
    }

    func testPersistentTamperingIsRejectedInsteadOfSilentlyRecomputed() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheKey = key(operation: .sourceProjection)
        let original = HeavyEvidenceCache(rootDirectory: directory)
        let _: HeavyEvidenceCacheResolution<Projection> = try await original.resolve(key: cacheKey) {
            Projection(value: "trusted", count: 1)
        }
        let file = try XCTUnwrap(cacheFiles(in: directory).first)
        var bytes = try Data(contentsOf: file)
        bytes[bytes.startIndex] ^= 0xff
        try bytes.write(to: file, options: .atomic)

        let reopened = HeavyEvidenceCache(rootDirectory: directory)
        let counter = Counter()
        do {
            let _: HeavyEvidenceCacheResolution<Projection> = try await reopened.resolve(key: cacheKey) {
                Projection(value: "untrusted-replacement", count: await counter.increment())
            }
            XCTFail("tampered cache entry must fail closed")
        } catch {
            let computationCount = await counter.current()
            let metrics = await reopened.snapshotMetrics()
            XCTAssertEqual(computationCount, 0)
            XCTAssertEqual(metrics.corruptionCount, 1)
        }
    }

    func testPersistentRetentionEvictsOldestEntryWithinBound() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = HeavyEvidenceCachePolicy(
            maximumEntries: 2,
            maximumPayloadBytes: 1_024,
            maximumTotalPayloadBytes: 2_048
        )
        let cache = HeavyEvidenceCache(rootDirectory: directory, policy: policy)

        for index in 0..<3 {
            let cacheKey = key(
                operation: .reportProjection,
                inputs: [HeavyEvidenceInput(role: "projection", digest: digest("input-\(index)"))]
            )
            let _: HeavyEvidenceCacheResolution<Projection> = try await cache.resolve(key: cacheKey) {
                Projection(value: "projection-\(index)", count: index)
            }
        }

        let metrics = await cache.snapshotMetrics()
        XCTAssertEqual(cacheFiles(in: directory).count, 2)
        XCTAssertEqual(metrics.evictionCount, 1)
    }

    func testOversizedProjectionIsNotCached() async throws {
        let cache = HeavyEvidenceCache(
            rootDirectory: nil,
            policy: HeavyEvidenceCachePolicy(
                maximumEntries: 2,
                maximumPayloadBytes: 16,
                maximumTotalPayloadBytes: 32
            )
        )

        do {
            let _: HeavyEvidenceCacheResolution<Projection> = try await cache.resolve(
                key: key(operation: .sourceProjection)
            ) {
                Projection(value: String(repeating: "x", count: 100), count: 1)
            }
            XCTFail("oversized payload must be rejected")
        } catch let error as HeavyEvidenceCacheError {
            guard case .payloadTooLarge = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func key(
        operation: HeavyEvidenceOperation,
        version: UInt32 = 1,
        inputs: [HeavyEvidenceInput]? = nil
    ) -> HeavyEvidenceCacheKey {
        HeavyEvidenceCacheKey(
            operation: operation,
            collectorID: "test-collector",
            collectorVersion: version,
            inputs: inputs ?? [HeavyEvidenceInput(role: "target", digest: digest("unchanged-target"))],
            parametersDigest: digest("fixed-parameters")
        )
    }

    private func digest(_ value: String) -> ContentDigest {
        HeavyEvidenceCache.sha256(value)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopForgeHeavyEvidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cacheFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "cache" }
    }
}
