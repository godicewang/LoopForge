import CryptoKit
import Darwin
import Foundation

enum WorkspaceMutationEffectPayload: Codable, Hashable, Sendable {
    case apply(WorkspaceMutationExecutionRequest)
    case rollback(WorkspaceMutationRollbackRequest)

    var intentID: IntegrationEffectIntentID {
        switch self {
        case .apply(let request): return request.intent.id
        case .rollback(let request): return request.intent.id
        }
    }

    var transactionID: IntegrationTransactionID {
        switch self {
        case .apply(let request): return request.intent.transactionID
        case .rollback(let request): return request.intent.transactionID
        }
    }

    var workspaceRoot: URL {
        switch self {
        case .apply(let request): return request.workspaceRoot
        case .rollback(let request): return request.workspaceRoot
        }
    }
}

enum WorkspaceMutationEffectOutboxState: Codable, Hashable, Sendable {
    case pending
    case retryScheduled(
        failureDigest: ContentDigest,
        attemptCount: Int,
        lastAttemptAt: Date
    )
    case completed(receiptDigest: ContentDigest, completedAt: Date)
    case quarantined(failureDigest: ContentDigest, quarantinedAt: Date)
}

struct WorkspaceMutationEffectEnvelope: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var intentID: IntegrationEffectIntentID
    var transactionID: IntegrationTransactionID
    var payload: WorkspaceMutationEffectPayload
    var payloadDigest: ContentDigest
    var startCommandID: RunCommandID
    var recordCommandID: RunCommandID
    var releaseReceiptID: ReceiptID
    var releaseCommandID: RunCommandID
    var failureReceiptID: ReceiptID
    var failureCommandID: RunCommandID
    var enqueuedAt: Date
    var state: WorkspaceMutationEffectOutboxState
}

struct WorkspaceMutationEffectOutboxLimits: Codable, Hashable, Sendable {
    var maximumEntries: Int
    var maximumBytes: UInt64
    var maximumDispatchAttempts: Int

    static let conservative = WorkspaceMutationEffectOutboxLimits(
        maximumEntries: 10_000,
        maximumBytes: 1_024 * 1_024 * 1_024,
        maximumDispatchAttempts: 3
    )
}

enum WorkspaceMutationEffectOutboxError: Error, Equatable {
    case invalidRoot
    case rootInsideWorkspace
    case invalidEnvelope
    case duplicateIntentConflict
    case entryMissing
    case alreadyCompleted
    case quarantineConflict
    case capacityExceeded
    case lockFailed
    case corruptSnapshot
    case persistenceFailed
}

private struct WorkspaceMutationEffectOutboxSnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var entries: [WorkspaceMutationEffectEnvelope]
    var snapshotDigest: ContentDigest
}

/// Durable content-bearing queue for journal-first workspace effects.
///
/// Entries remain pending while an effect is dispatched. A crash therefore
/// causes bounded replay of the same intent and command identities, never a
/// newly minted mutation. Completion is persisted only after the journaled
/// runtime returns a receipt accepted by the reducer projection.
actor WorkspaceMutationEffectOutbox {
    let runID: KernelRunID
    let rootDirectory: URL
    let snapshotURL: URL

    private let lockURL: URL
    private let limits: WorkspaceMutationEffectOutboxLimits
    private var snapshot: WorkspaceMutationEffectOutboxSnapshot

    init(
        rootDirectory: URL,
        runID: KernelRunID,
        limits: WorkspaceMutationEffectOutboxLimits = .conservative
    ) throws {
        guard rootDirectory.isFileURL,
              !runID.rawValue.isEmpty,
              limits.maximumEntries > 0,
              limits.maximumBytes > 0,
              limits.maximumDispatchAttempts > 0 else {
            throw WorkspaceMutationEffectOutboxError.invalidRoot
        }
        let resolved = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.runID = runID
        self.rootDirectory = resolved
        snapshotURL = resolved.appendingPathComponent("effects.json")
        lockURL = resolved.appendingPathComponent("effects.lock")
        self.limits = limits
        snapshot = try Self.load(
            from: snapshotURL,
            runID: runID,
            limits: limits
        )
    }

    @discardableResult
    func enqueue(
        payload: WorkspaceMutationEffectPayload,
        startCommandID: RunCommandID,
        recordCommandID: RunCommandID,
        releaseReceiptID: ReceiptID,
        releaseCommandID: RunCommandID,
        failureReceiptID: ReceiptID,
        failureCommandID: RunCommandID,
        enqueuedAt: Date
    ) throws -> WorkspaceMutationEffectEnvelope {
        try validateRootIsOutsideWorkspace(payload.workspaceRoot)
        let digest = Self.payloadDigest(payload)
        let envelope = WorkspaceMutationEffectEnvelope(
            schemaVersion: 5,
            runID: runID,
            intentID: payload.intentID,
            transactionID: payload.transactionID,
            payload: payload,
            payloadDigest: digest,
            startCommandID: startCommandID,
            recordCommandID: recordCommandID,
            releaseReceiptID: releaseReceiptID,
            releaseCommandID: releaseCommandID,
            failureReceiptID: failureReceiptID,
            failureCommandID: failureCommandID,
            enqueuedAt: enqueuedAt,
            state: .pending
        )
        try Self.validate(envelope, runID: runID)
        return try mutate { current in
            if let existing = current.entries.first(where: {
                $0.intentID == envelope.intentID
            }) {
                // Decoding canonical JSON can normalize representation-only
                // details (notably URL base metadata) without changing the
                // sealed payload. Idempotency therefore compares the exact
                // durable enqueue identity and its canonical payload digest,
                // never incidental in-memory representation or mutable queue
                // state.
                guard Self.sameEnqueueIdentity(existing, envelope) else {
                    throw WorkspaceMutationEffectOutboxError.duplicateIntentConflict
                }
                return existing
            }
            guard current.entries.count < limits.maximumEntries else {
                throw WorkspaceMutationEffectOutboxError.capacityExceeded
            }
            current.entries.append(envelope)
            current.entries.sort { $0.intentID.rawValue < $1.intentID.rawValue }
            return envelope
        }
    }

    func pending(limit: Int) throws -> [WorkspaceMutationEffectEnvelope] {
        guard limit > 0, limit <= limits.maximumEntries else {
            throw WorkspaceMutationEffectOutboxError.capacityExceeded
        }
        snapshot = try withLock {
            try Self.load(from: snapshotURL, runID: runID, limits: limits)
        }
        return snapshot.entries.compactMap { envelope in
            switch envelope.state {
            case .pending:
                return envelope
            case .retryScheduled(_, let attemptCount, _):
                return attemptCount < limits.maximumDispatchAttempts
                    ? envelope
                    : nil
            case .completed, .quarantined:
                return nil
            }
        }.prefix(limit).map { $0 }
    }

    @discardableResult
    func markCompleted(
        intentID: IntegrationEffectIntentID,
        receiptDigest: ContentDigest,
        completedAt: Date
    ) throws -> WorkspaceMutationEffectEnvelope {
        guard !receiptDigest.rawValue.isEmpty else {
            throw WorkspaceMutationEffectOutboxError.invalidEnvelope
        }
        return try mutate { current in
            guard let index = current.entries.firstIndex(where: {
                $0.intentID == intentID
            }) else {
                throw WorkspaceMutationEffectOutboxError.entryMissing
            }
            if case .completed(let existingDigest, let existingDate) =
                current.entries[index].state {
                guard existingDigest == receiptDigest,
                      existingDate == completedAt else {
                    throw WorkspaceMutationEffectOutboxError.alreadyCompleted
                }
                return current.entries[index]
            }
            if case .quarantined = current.entries[index].state {
                throw WorkspaceMutationEffectOutboxError.alreadyCompleted
            }
            current.entries[index].state = .completed(
                receiptDigest: receiptDigest,
                completedAt: completedAt
            )
            return current.entries[index]
        }
    }

    /// Removes an in-doubt ownership failure from ordinary recovery. The
    /// envelope remains durable for an explicit repair workflow; it is never
    /// acknowledged as completed and never scanned as an executable effect.
    @discardableResult
    func markQuarantined(
        intentID: IntegrationEffectIntentID,
        failureDigest: ContentDigest,
        quarantinedAt: Date
    ) throws -> WorkspaceMutationEffectEnvelope {
        guard !failureDigest.rawValue.isEmpty else {
            throw WorkspaceMutationEffectOutboxError.invalidEnvelope
        }
        return try mutate { current in
            guard let index = current.entries.firstIndex(where: {
                $0.intentID == intentID
            }) else {
                throw WorkspaceMutationEffectOutboxError.entryMissing
            }
            switch current.entries[index].state {
            case .pending, .retryScheduled:
                current.entries[index].state = .quarantined(
                    failureDigest: failureDigest,
                    quarantinedAt: quarantinedAt
                )
            case .quarantined(let existingDigest, let existingDate):
                guard existingDigest == failureDigest,
                      existingDate == quarantinedAt else {
                    throw WorkspaceMutationEffectOutboxError.quarantineConflict
                }
            case .completed:
                throw WorkspaceMutationEffectOutboxError.alreadyCompleted
            }
            return current.entries[index]
        }
    }

    /// Persists one bounded retryable failure. Once the configured attempt
    /// budget is exhausted, the entry becomes quarantined and ordinary
    /// recovery can no longer rediscover it.
    @discardableResult
    func recordRetryableFailure(
        intentID: IntegrationEffectIntentID,
        failureDigest: ContentDigest,
        attemptedAt: Date
    ) throws -> WorkspaceMutationEffectEnvelope {
        guard !failureDigest.rawValue.isEmpty else {
            throw WorkspaceMutationEffectOutboxError.invalidEnvelope
        }
        return try mutate { current in
            guard let index = current.entries.firstIndex(where: {
                $0.intentID == intentID
            }) else {
                throw WorkspaceMutationEffectOutboxError.entryMissing
            }
            let nextAttemptCount: Int
            switch current.entries[index].state {
            case .pending:
                nextAttemptCount = 1
            case .retryScheduled(_, let attemptCount, _):
                nextAttemptCount = attemptCount + 1
            case .quarantined:
                throw WorkspaceMutationEffectOutboxError.quarantineConflict
            case .completed:
                throw WorkspaceMutationEffectOutboxError.alreadyCompleted
            }
            if nextAttemptCount >= limits.maximumDispatchAttempts {
                current.entries[index].state = .quarantined(
                    failureDigest: failureDigest,
                    quarantinedAt: attemptedAt
                )
            } else {
                current.entries[index].state = .retryScheduled(
                    failureDigest: failureDigest,
                    attemptCount: nextAttemptCount,
                    lastAttemptAt: attemptedAt
                )
            }
            return current.entries[index]
        }
    }

    func allEntries() throws -> [WorkspaceMutationEffectEnvelope] {
        snapshot = try withLock {
            try Self.load(from: snapshotURL, runID: runID, limits: limits)
        }
        return snapshot.entries
    }

    /// Canonical digest used when a reducer-accepted effect receipt retires an
    /// envelope. Receipt payloads may contain sets; hashing a plain encoder
    /// makes their iteration order part of the receipt identity.
    nonisolated static func durableReceiptDigest<T: Encodable>(
        _ receipt: T
    ) -> ContentDigest {
        digest(encode(receipt))
    }

    private func mutate<T>(
        _ body: (inout WorkspaceMutationEffectOutboxSnapshot) throws -> T
    ) throws -> T {
        try withLock {
            var current = try Self.load(
                from: snapshotURL,
                runID: runID,
                limits: limits
            )
            let result = try body(&current)
            current.snapshotDigest = Self.snapshotDigest(current)
            try Self.persist(current, to: snapshotURL, limits: limits)
            snapshot = current
            return result
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        do {
            try FileManager.default.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw WorkspaceMutationEffectOutboxError.persistenceFailed
        }
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            guard FileManager.default.createFile(atPath: lockURL.path, contents: nil) else {
                throw WorkspaceMutationEffectOutboxError.lockFailed
            }
            _ = chmod(lockURL.path, 0o600)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: lockURL)
        } catch {
            throw WorkspaceMutationEffectOutboxError.lockFailed
        }
        guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
            try? handle.close()
            throw WorkspaceMutationEffectOutboxError.lockFailed
        }
        defer {
            flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
        }
        return try body()
    }

    private func validateRootIsOutsideWorkspace(_ workspaceRoot: URL) throws {
        guard workspaceRoot.isFileURL else {
            throw WorkspaceMutationEffectOutboxError.invalidRoot
        }
        let workspace = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let outbox = rootDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard outbox != workspace,
              !outbox.hasPrefix(workspace + "/") else {
            throw WorkspaceMutationEffectOutboxError.rootInsideWorkspace
        }
    }

    private static func load(
        from url: URL,
        runID: KernelRunID,
        limits: WorkspaceMutationEffectOutboxLimits
    ) throws -> WorkspaceMutationEffectOutboxSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            var empty = WorkspaceMutationEffectOutboxSnapshot(
                schemaVersion: 5,
                runID: runID,
                entries: [],
                snapshotDigest: ContentDigest("")
            )
            empty.snapshotDigest = snapshotDigest(empty)
            return empty
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value <= limits.maximumBytes else {
            throw WorkspaceMutationEffectOutboxError.capacityExceeded
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(
                WorkspaceMutationEffectOutboxSnapshot.self,
                from: Data(contentsOf: url)
            )
            guard [3, 4, 5].contains(decoded.schemaVersion),
                  decoded.runID == runID,
                  decoded.entries.count <= limits.maximumEntries,
                  decoded.entries.map(\.intentID).count ==
                    Set(decoded.entries.map(\.intentID)).count,
                  decoded.entries.allSatisfy({ envelope in
                      envelope.schemaVersion == decoded.schemaVersion &&
                        (try? validate(
                            envelope,
                            runID: runID,
                            schemaVersion: decoded.schemaVersion
                        )) != nil
                  }),
                  decoded.snapshotDigest == snapshotDigest(decoded) else {
                throw WorkspaceMutationEffectOutboxError.corruptSnapshot
            }
            guard decoded.schemaVersion < 5 else { return decoded }
            var upgraded = decoded
            upgraded.schemaVersion = 5
            for index in upgraded.entries.indices {
                upgraded.entries[index].schemaVersion = 5
            }
            upgraded.snapshotDigest = snapshotDigest(upgraded)
            return upgraded
        } catch let error as WorkspaceMutationEffectOutboxError {
            throw error
        } catch {
            throw WorkspaceMutationEffectOutboxError.corruptSnapshot
        }
    }

    private static func validate(
        _ envelope: WorkspaceMutationEffectEnvelope,
        runID: KernelRunID,
        schemaVersion: Int = 5
    ) throws {
        guard envelope.schemaVersion == schemaVersion,
              [3, 4, 5].contains(schemaVersion),
              envelope.runID == runID,
              envelope.intentID == envelope.payload.intentID,
              envelope.transactionID == envelope.payload.transactionID,
              envelope.payloadDigest == payloadDigest(envelope.payload),
              !envelope.intentID.rawValue.isEmpty,
              !envelope.transactionID.rawValue.isEmpty,
              !envelope.startCommandID.rawValue.isEmpty,
              !envelope.recordCommandID.rawValue.isEmpty,
              !envelope.releaseReceiptID.rawValue.isEmpty,
              !envelope.releaseCommandID.rawValue.isEmpty,
              !envelope.failureReceiptID.rawValue.isEmpty,
              !envelope.failureCommandID.rawValue.isEmpty,
              Set([
                envelope.startCommandID,
                envelope.recordCommandID,
                envelope.releaseCommandID,
                envelope.failureCommandID
              ]).count == 4,
              envelope.releaseReceiptID != envelope.failureReceiptID else {
            throw WorkspaceMutationEffectOutboxError.invalidEnvelope
        }
        if case .retryScheduled(_, let attemptCount, _) = envelope.state {
            guard schemaVersion >= 5,
                  attemptCount > 0 else {
                throw WorkspaceMutationEffectOutboxError.invalidEnvelope
            }
        }
    }

    private static func sameEnqueueIdentity(
        _ lhs: WorkspaceMutationEffectEnvelope,
        _ rhs: WorkspaceMutationEffectEnvelope
    ) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.runID == rhs.runID
            && lhs.intentID == rhs.intentID
            && lhs.transactionID == rhs.transactionID
            && lhs.payloadDigest == rhs.payloadDigest
            && lhs.startCommandID == rhs.startCommandID
            && lhs.recordCommandID == rhs.recordCommandID
            && lhs.releaseReceiptID == rhs.releaseReceiptID
            && lhs.releaseCommandID == rhs.releaseCommandID
            && lhs.failureReceiptID == rhs.failureReceiptID
            && lhs.failureCommandID == rhs.failureCommandID
            && lhs.enqueuedAt == rhs.enqueuedAt
    }

    private static func persist(
        _ snapshot: WorkspaceMutationEffectOutboxSnapshot,
        to url: URL,
        limits: WorkspaceMutationEffectOutboxLimits
    ) throws {
        let data = encode(snapshot)
        guard UInt64(data.count) <= limits.maximumBytes else {
            throw WorkspaceMutationEffectOutboxError.capacityExceeded
        }
        do {
            try data.write(to: url, options: .atomic)
            _ = chmod(url.path, 0o600)
            let handle = try FileHandle(forUpdating: url)
            try handle.synchronize()
            try handle.close()
        } catch {
            throw WorkspaceMutationEffectOutboxError.persistenceFailed
        }
    }

    private static func payloadDigest(
        _ payload: WorkspaceMutationEffectPayload
    ) -> ContentDigest {
        digest(Data("workspace-effect-payload-v1\n".utf8) + encode(payload))
    }

    private static func snapshotDigest(
        _ snapshot: WorkspaceMutationEffectOutboxSnapshot
    ) -> ContentDigest {
        digest(encode(WorkspaceMutationEffectOutboxSnapshot(
            schemaVersion: snapshot.schemaVersion,
            runID: snapshot.runID,
            entries: snapshot.entries,
            snapshotDigest: ContentDigest("")
        )))
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let encoded = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(
                with: encoded,
                options: [.fragmentsAllowed]
              ),
              let canonical = try? canonicalized(object, fieldName: nil),
              let data = try? JSONSerialization.data(
                withJSONObject: canonical,
                options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
              ) else {
            return Data()
        }
        return data
    }

    private static let unorderedArrayFieldNames: Set<String> = [
        "candidateVerificationReceiptIDs",
        "capturedPlanes",
        "requirementIDs",
        "requiredPlanes",
        "touchedRequirementIDs"
    ]

    private static func canonicalized(
        _ value: Any,
        fieldName: String?
    ) throws -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary {
                result[key] = try canonicalized(child, fieldName: key)
            }
            return result
        }
        if let array = value as? [Any] {
            let result = try array.map { try canonicalized($0, fieldName: nil) }
            guard fieldName.map(unorderedArrayFieldNames.contains) == true else {
                return result
            }
            return try result.sorted {
                try canonicalSortKey($0).lexicographicallyPrecedes(
                    canonicalSortKey($1)
                )
            }
        }
        return value
    }

    private static func canonicalSortKey(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
    }
}
