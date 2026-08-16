import CryptoKit
import Foundation

enum HeavyEvidenceOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case repositoryIndex
    case sourceProjection
    case imageInspection
    case visualPairMeasurement
    case reportProjection
}

struct HeavyEvidenceInput: Codable, Hashable, Sendable {
    var role: String
    var digest: ContentDigest
}

struct HeavyEvidenceCacheKey: Codable, Hashable, Sendable {
    var operation: HeavyEvidenceOperation
    var collectorID: String
    var collectorVersion: UInt32
    var inputs: [HeavyEvidenceInput]
    var parametersDigest: ContentDigest

    func validated() throws -> HeavyEvidenceCacheKey {
        let collector = collectorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collector.isEmpty, collectorVersion > 0 else {
            throw HeavyEvidenceCacheError.invalidKey("collector identity and version are required")
        }
        guard !inputs.isEmpty else {
            throw HeavyEvidenceCacheError.invalidKey("at least one content input is required")
        }
        guard Self.isSHA256(parametersDigest) else {
            throw HeavyEvidenceCacheError.invalidKey("parameters digest is not SHA-256")
        }

        let normalizedInputs = try inputs.map { input -> HeavyEvidenceInput in
            let role = input.role.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !role.isEmpty, Self.isSHA256(input.digest) else {
                throw HeavyEvidenceCacheError.invalidKey("input role and SHA-256 digest are required")
            }
            return HeavyEvidenceInput(
                role: role,
                digest: ContentDigest(input.digest.rawValue.lowercased())
            )
        }.sorted {
            ($0.role, $0.digest.rawValue) < ($1.role, $1.digest.rawValue)
        }
        guard Set(normalizedInputs.map(\.role)).count == normalizedInputs.count else {
            throw HeavyEvidenceCacheError.invalidKey("input roles must be unique")
        }

        return HeavyEvidenceCacheKey(
            operation: operation,
            collectorID: collector,
            collectorVersion: collectorVersion,
            inputs: normalizedInputs,
            parametersDigest: ContentDigest(parametersDigest.rawValue.lowercased())
        )
    }

    func digest() throws -> ContentDigest {
        let key = try validated()
        var material = Data()
        Self.append(key.operation.rawValue, to: &material)
        Self.append(key.collectorID, to: &material)
        Self.append(String(key.collectorVersion), to: &material)
        for input in key.inputs {
            Self.append(input.role, to: &material)
            Self.append(input.digest.rawValue, to: &material)
        }
        Self.append(key.parametersDigest.rawValue, to: &material)
        return HeavyEvidenceCache.sha256(material)
    }

    private static func append(_ field: String, to data: inout Data) {
        let bytes = Data(field.utf8)
        var count = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(bytes)
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64
            && digest.rawValue.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
            }
    }
}

struct HeavyEvidenceCachePolicy: Codable, Hashable, Sendable {
    var maximumEntries: Int
    var maximumPayloadBytes: Int
    var maximumTotalPayloadBytes: Int

    static let runtimeDefault = HeavyEvidenceCachePolicy(
        maximumEntries: 2_048,
        maximumPayloadBytes: 8 * 1_024 * 1_024,
        maximumTotalPayloadBytes: 256 * 1_024 * 1_024
    )

    func validate() throws {
        guard maximumEntries > 0,
              maximumPayloadBytes > 0,
              maximumTotalPayloadBytes >= maximumPayloadBytes else {
            throw HeavyEvidenceCacheError.invalidPolicy
        }
    }
}

enum HeavyEvidenceCacheDisposition: String, Codable, Hashable, Sendable {
    case computed
    case memoryHit
    case diskHit
    case coalescedHit
}

struct HeavyEvidenceCacheReceipt: Codable, Hashable, Sendable {
    var keyDigest: ContentDigest
    var payloadDigest: ContentDigest
    var payloadBytes: Int
    var disposition: HeavyEvidenceCacheDisposition
}

struct HeavyEvidenceCacheResolution<Value: Sendable>: Sendable {
    var value: Value
    var receipt: HeavyEvidenceCacheReceipt
}

struct HeavyEvidenceCacheMetrics: Codable, Equatable, Sendable {
    var lookupCount: UInt64 = 0
    var memoryHitCount: UInt64 = 0
    var diskHitCount: UInt64 = 0
    var coalescedHitCount: UInt64 = 0
    var computationCount: UInt64 = 0
    var persistentWriteCount: UInt64 = 0
    var evictionCount: UInt64 = 0
    var corruptionCount: UInt64 = 0
}

enum HeavyEvidenceCacheError: Error, Equatable, LocalizedError {
    case invalidPolicy
    case invalidKey(String)
    case payloadTooLarge(actual: Int, maximum: Int)
    case corruptEntry(String)
    case unsafeCachePath(String)
    case valueEncodingFailed
    case valueDecodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPolicy:
            return "The heavy-evidence cache policy is invalid."
        case let .invalidKey(reason):
            return "The heavy-evidence cache key is invalid: \(reason)."
        case let .payloadTooLarge(actual, maximum):
            return "The evidence projection is \(actual) bytes; the cache limit is \(maximum)."
        case let .corruptEntry(reason):
            return "A content-addressed evidence cache entry failed verification: \(reason)."
        case let .unsafeCachePath(path):
            return "The evidence cache path is not a regular private file: \(path)."
        case .valueEncodingFailed:
            return "The evidence projection could not be encoded."
        case .valueDecodingFailed:
            return "The evidence projection could not be decoded."
        }
    }
}

private struct HeavyEvidenceCacheEnvelope: Codable, Sendable {
    var schemaVersion: UInt32
    var key: HeavyEvidenceCacheKey
    var keyDigest: ContentDigest
    var payloadDigest: ContentDigest
    var payload: Data
    var createdAt: Date
}

/// A fail-closed cache for expensive deterministic evidence projections.
///
/// Callers provide immutable content digests and a collector version. Paths,
/// mtimes, task names, and model prose never participate in cache identity.
/// Payloads are small derived projections (indexes, OCR, geometry, visual-pair
/// measurements), not the original workspace or image bytes. Persistent files
/// are immutable, digest-verified on every disk load, and written only on a
/// cache miss. Concurrent identical misses share exactly one computation.
actor HeavyEvidenceCache {
    static let shared = HeavyEvidenceCache(
        rootDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("LoopForge/HeavyEvidence-v1", isDirectory: true),
        policy: .runtimeDefault
    )

    private let rootDirectory: URL?
    private let policy: HeavyEvidenceCachePolicy
    private var memory: [ContentDigest: Data] = [:]
    private var memoryCreatedAt: [ContentDigest: Date] = [:]
    private var inFlight: [ContentDigest: Task<Data, Error>] = [:]
    private var metrics = HeavyEvidenceCacheMetrics()

    init(rootDirectory: URL?, policy: HeavyEvidenceCachePolicy = .runtimeDefault) {
        self.rootDirectory = rootDirectory
        self.policy = policy
    }

    func resolve<Value: Codable & Sendable>(
        key unvalidatedKey: HeavyEvidenceCacheKey,
        compute: @escaping @Sendable () async throws -> Value
    ) async throws -> HeavyEvidenceCacheResolution<Value> {
        try policy.validate()
        let key = try unvalidatedKey.validated()
        let keyDigest = try key.digest()
        metrics.lookupCount &+= 1

        if let payload = memory[keyDigest] {
            metrics.memoryHitCount &+= 1
            return try resolution(
                payload: payload,
                keyDigest: keyDigest,
                disposition: .memoryHit
            )
        }

        if let payload = try loadPersistent(key: key, keyDigest: keyDigest) {
            memory[keyDigest] = payload
            memoryCreatedAt[keyDigest] = Date()
            metrics.diskHitCount &+= 1
            trimMemoryIfNeeded()
            return try resolution(
                payload: payload,
                keyDigest: keyDigest,
                disposition: .diskHit
            )
        }

        if let active = inFlight[keyDigest] {
            metrics.coalescedHitCount &+= 1
            let payload = try await active.value
            return try resolution(
                payload: payload,
                keyDigest: keyDigest,
                disposition: .coalescedHit
            )
        }

        let maximum = policy.maximumPayloadBytes
        let task = Task<Data, Error> {
            let value = try await compute()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let payload = try? encoder.encode(value) else {
                throw HeavyEvidenceCacheError.valueEncodingFailed
            }
            guard !payload.isEmpty, payload.count <= maximum else {
                throw HeavyEvidenceCacheError.payloadTooLarge(
                    actual: payload.count,
                    maximum: maximum
                )
            }
            return payload
        }
        inFlight[keyDigest] = task
        metrics.computationCount &+= 1

        do {
            let payload = try await task.value
            inFlight[keyDigest] = nil
            try persist(payload: payload, key: key, keyDigest: keyDigest)
            memory[keyDigest] = payload
            memoryCreatedAt[keyDigest] = Date()
            trimMemoryIfNeeded()
            return try resolution(
                payload: payload,
                keyDigest: keyDigest,
                disposition: .computed
            )
        } catch {
            inFlight[keyDigest] = nil
            throw error
        }
    }

    func snapshotMetrics() -> HeavyEvidenceCacheMetrics { metrics }

    func resetMemory() {
        memory.removeAll()
        memoryCreatedAt.removeAll()
    }

    static func sha256(_ data: Data) -> ContentDigest {
        ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }

    static func sha256(_ text: String) -> ContentDigest {
        sha256(Data(text.utf8))
    }

    static func digest(fileAt url: URL) throws -> ContentDigest {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw HeavyEvidenceCacheError.unsafeCachePath(url.path)
        }
        return sha256(try Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    private func resolution<Value: Codable & Sendable>(
        payload: Data,
        keyDigest: ContentDigest,
        disposition: HeavyEvidenceCacheDisposition
    ) throws -> HeavyEvidenceCacheResolution<Value> {
        guard let value = try? JSONDecoder().decode(Value.self, from: payload) else {
            throw HeavyEvidenceCacheError.valueDecodingFailed
        }
        return HeavyEvidenceCacheResolution(
            value: value,
            receipt: HeavyEvidenceCacheReceipt(
                keyDigest: keyDigest,
                payloadDigest: Self.sha256(payload),
                payloadBytes: payload.count,
                disposition: disposition
            )
        )
    }

    private func persistentURL(for keyDigest: ContentDigest) throws -> URL? {
        guard let rootDirectory else { return nil }
        let digest = keyDigest.rawValue
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) else {
            throw HeavyEvidenceCacheError.invalidKey("derived cache digest is invalid")
        }
        let shard = rootDirectory.appendingPathComponent(String(digest.prefix(2)), isDirectory: true)
        return shard.appendingPathComponent(digest + ".cache", isDirectory: false)
    }

    private func loadPersistent(
        key: HeavyEvidenceCacheKey,
        keyDigest: ContentDigest
    ) throws -> Data? {
        guard let url = try persistentURL(for: keyDigest),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw HeavyEvidenceCacheError.unsafeCachePath(url.path)
            }
            let bytes = try Data(contentsOf: url, options: [.mappedIfSafe])
            let envelope = try JSONDecoder().decode(HeavyEvidenceCacheEnvelope.self, from: bytes)
            guard envelope.schemaVersion == 1,
                  envelope.key == key,
                  envelope.keyDigest == keyDigest,
                  try envelope.key.digest() == keyDigest,
                  envelope.payloadDigest == Self.sha256(envelope.payload),
                  !envelope.payload.isEmpty,
                  envelope.payload.count <= policy.maximumPayloadBytes else {
                throw HeavyEvidenceCacheError.corruptEntry(keyDigest.rawValue)
            }
            return envelope.payload
        } catch let error as HeavyEvidenceCacheError {
            metrics.corruptionCount &+= 1
            throw error
        } catch {
            metrics.corruptionCount &+= 1
            throw HeavyEvidenceCacheError.corruptEntry(keyDigest.rawValue)
        }
    }

    private func persist(
        payload: Data,
        key: HeavyEvidenceCacheKey,
        keyDigest: ContentDigest
    ) throws {
        guard let url = try persistentURL(for: keyDigest) else { return }
        let manager = FileManager.default
        try manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if manager.fileExists(atPath: url.path) {
            _ = try loadPersistent(key: key, keyDigest: keyDigest)
            return
        }
        let envelope = HeavyEvidenceCacheEnvelope(
            schemaVersion: 1,
            key: key,
            keyDigest: keyDigest,
            payloadDigest: Self.sha256(payload),
            payload: payload,
            createdAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(envelope)
        try bytes.write(to: url, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        metrics.persistentWriteCount &+= 1
        try trimPersistentIfNeeded(protecting: keyDigest)
    }

    private func trimMemoryIfNeeded() {
        var total = memory.values.reduce(0) { $0 + $1.count }
        while memory.count > policy.maximumEntries || total > policy.maximumTotalPayloadBytes {
            guard let victim = memory.keys.min(by: {
                let lhs = memoryCreatedAt[$0] ?? .distantPast
                let rhs = memoryCreatedAt[$1] ?? .distantPast
                return lhs == rhs ? $0.rawValue < $1.rawValue : lhs < rhs
            }), let removed = memory.removeValue(forKey: victim) else { break }
            memoryCreatedAt[victim] = nil
            total -= removed.count
        }
    }

    private func trimPersistentIfNeeded(protecting protected: ContentDigest) throws {
        guard let rootDirectory else { return }
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return }

        var entries: [(url: URL, envelope: HeavyEvidenceCacheEnvelope)] = []
        for case let url as URL in enumerator where url.pathExtension == "cache" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard let bytes = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  let envelope = try? JSONDecoder().decode(HeavyEvidenceCacheEnvelope.self, from: bytes),
                  envelope.schemaVersion == 1,
                  envelope.payloadDigest == Self.sha256(envelope.payload) else { continue }
            entries.append((url, envelope))
        }
        entries.sort {
            if $0.envelope.createdAt != $1.envelope.createdAt {
                return $0.envelope.createdAt < $1.envelope.createdAt
            }
            return $0.envelope.keyDigest.rawValue < $1.envelope.keyDigest.rawValue
        }
        var total = entries.reduce(0) { $0 + $1.envelope.payload.count }
        var count = entries.count
        for entry in entries where count > policy.maximumEntries || total > policy.maximumTotalPayloadBytes {
            guard entry.envelope.keyDigest != protected else { continue }
            try manager.removeItem(at: entry.url)
            total -= entry.envelope.payload.count
            count -= 1
            metrics.evictionCount &+= 1
        }
    }
}
