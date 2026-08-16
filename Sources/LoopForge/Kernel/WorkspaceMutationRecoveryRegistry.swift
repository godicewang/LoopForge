import CryptoKit
import Darwin
import Foundation

enum KernelRunEnrollmentAuthority: String, Codable, Hashable, Sendable {
    case ratifiedUserContract
    case debugFixture
}

struct KernelRunEnrollmentEvidence: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var authority: KernelRunEnrollmentAuthority
    var runID: KernelRunID
    var contractID: TaskContractID
    var contractRevision: UInt64
    var candidateDigest: ContentDigest
    var ratificationReceiptID: ReceiptID
    var userActorID: ActorID
    var userActorLineageDigest: ContentDigest
    var createCommandID: RunCommandID
    var journalFrameDigest: ContentDigest
    var journalEndingSequence: UInt64
}

struct WorkspaceMutationRecoveryRegistration: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var actorIdentity: ActorIdentity
    var workspaceID: WorkspaceID
    var workspaceRoot: URL
    var journalRoot: URL
    var outboxRoot: URL
    var hostBudget: HostResourceBudget
    var maximumDispatchBatch: Int
    var registeredAt: Date
    /// Optional only for decoding registries produced before the production
    /// enrollment boundary. New release registrations always carry exact
    /// ratification and journal-frame provenance.
    var enrollmentEvidence: KernelRunEnrollmentEvidence? = nil
}

struct WorkspaceMutationRecoveryRegistryLimits: Codable, Hashable, Sendable {
    var maximumRuns: Int
    var maximumBytes: UInt64
    var maximumDispatchBatch: Int

    static let conservative = WorkspaceMutationRecoveryRegistryLimits(
        maximumRuns: 256,
        maximumBytes: 8 * 1_024 * 1_024,
        maximumDispatchBatch: 64
    )
}

enum WorkspaceMutationRecoveryRegistryError: Error, Equatable {
    case invalidRoot
    case invalidRegistration
    case workspaceOverlapsRegistry
    case duplicateRunConflict
    case ratificationReceiptAlreadyConsumed
    case capacityExceeded
    case lockFailed
    case corruptSnapshot
    case persistenceFailed
}

private struct WorkspaceMutationRecoveryRegistrySnapshot: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var registrations: [WorkspaceMutationRecoveryRegistration]
    var snapshotDigest: ContentDigest
}

/// Durable allow-list for new-kernel workspace recovery.
///
/// Registration is intentionally independent of legacy task and Graph state.
/// A caller supplies typed identities, while the registry itself derives the
/// only permitted journal/outbox paths beneath its owned root. Merely creating
/// a registration grants no mutation authority; the journal must separately
/// contain the exact admitted lease and effect intent.
actor WorkspaceMutationRecoveryRegistry {
    let rootDirectory: URL
    let runsDirectory: URL
    let snapshotURL: URL

    private let lockURL: URL
    private let limits: WorkspaceMutationRecoveryRegistryLimits
    private var snapshot: WorkspaceMutationRecoveryRegistrySnapshot

    init(
        rootDirectory: URL,
        limits: WorkspaceMutationRecoveryRegistryLimits = .conservative
    ) throws {
        guard rootDirectory.isFileURL,
              rootDirectory.path.hasPrefix("/"),
              limits.maximumRuns > 0,
              limits.maximumBytes > 0,
              limits.maximumDispatchBatch > 0 else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRoot
        }
        let resolved = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.rootDirectory = resolved
        runsDirectory = resolved.appendingPathComponent("runs", isDirectory: true)
        snapshotURL = resolved.appendingPathComponent("registry.json")
        lockURL = resolved.appendingPathComponent("registry.lock")
        self.limits = limits
        do {
            try FileManager.default.createDirectory(
                at: runsDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.invalidRoot
        }
        guard chmod(resolved.path, 0o700) == 0,
              chmod(runsDirectory.path, 0o700) == 0 else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRoot
        }
        snapshot = try Self.load(
            from: snapshotURL,
            rootDirectory: resolved,
            runsDirectory: runsDirectory,
            limits: limits
        )
    }

    static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("LoopForge", isDirectory: true)
            .appendingPathComponent("KernelRecovery", isDirectory: true)
    }

    #if DEBUG
    /// Test fixture escape hatch. Release builds can publish a recovery
    /// registration only with a sealed, journal-verified enrollment proof.
    @discardableResult
    func register(
        runID: KernelRunID,
        actorIdentity: ActorIdentity,
        workspaceID: WorkspaceID,
        workspaceRoot: URL,
        hostBudget: HostResourceBudget,
        maximumDispatchBatch: Int,
        registeredAt: Date
    ) throws -> WorkspaceMutationRecoveryRegistration {
        let registration = try registrationCandidate(
            runID: runID,
            actorIdentity: actorIdentity,
            workspaceID: workspaceID,
            workspaceRoot: workspaceRoot,
            hostBudget: hostBudget,
            maximumDispatchBatch: maximumDispatchBatch,
            registeredAt: registeredAt
        )
        var fixtureRegistration = registration
        fixtureRegistration.enrollmentEvidence = KernelRunEnrollmentEvidence(
            schemaVersion: 1,
            authority: .debugFixture,
            runID: runID,
            contractID: TaskContractID("debug-fixture"),
            contractRevision: 0,
            candidateDigest: ContentDigest("debug-fixture"),
            ratificationReceiptID: ReceiptID("debug-fixture"),
            userActorID: actorIdentity.id,
            userActorLineageDigest: actorIdentity.lineageDigest,
            createCommandID: RunCommandID("debug-fixture"),
            journalFrameDigest: ContentDigest("debug-fixture"),
            journalEndingSequence: 0
        )
        return try commitRegistration(fixtureRegistration)
    }
    #endif

    /// Produces the exact owned journal/outbox paths and validates conflicts
    /// without persisting recovery enrollment. The production enrollment
    /// coordinator uses this to durably create and verify the run journal
    /// before making the run eligible for automatic recovery.
    func registrationCandidate(
        runID: KernelRunID,
        actorIdentity: ActorIdentity,
        workspaceID: WorkspaceID,
        workspaceRoot: URL,
        hostBudget: HostResourceBudget,
        maximumDispatchBatch: Int,
        registeredAt: Date
    ) throws -> WorkspaceMutationRecoveryRegistration {
        guard Self.validPathComponent(runID.rawValue),
              !actorIdentity.id.rawValue.isEmpty,
              !actorIdentity.role.isEmpty,
              !actorIdentity.lineageDigest.rawValue.isEmpty,
              !workspaceID.rawValue.isEmpty,
              workspaceRoot.isFileURL,
              workspaceRoot.path.hasPrefix("/"),
              maximumDispatchBatch > 0,
              maximumDispatchBatch <= limits.maximumDispatchBatch else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        let suppliedWorkspaceValues: URLResourceValues
        do {
            suppliedWorkspaceValues = try workspaceRoot.standardizedFileURL
                .resourceValues(forKeys: [.isSymbolicLinkKey])
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        guard suppliedWorkspaceValues.isSymbolicLink != true else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        let workspace = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard try Self.isExistingDirectory(workspace) else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        try Self.rejectOverlap(workspace: workspace, registry: rootDirectory)

        let runRoot = runsDirectory.appendingPathComponent(
            runID.rawValue,
            isDirectory: true
        )
        // The snapshot codec persists dates in whole milliseconds. Canonicalize
        // before the value becomes part of registration identity so the receipt
        // returned by commit is exactly equal to a subsequent durable reload.
        // Keeping sub-millisecond memory precision here made valid production
        // enrollment receipts intermittently fail exact-registration checks.
        let durableRegisteredAt = Date(
            timeIntervalSince1970: floor(
                registeredAt.timeIntervalSince1970 * 1_000
            ) / 1_000
        )
        let registration = WorkspaceMutationRecoveryRegistration(
            schemaVersion: 1,
            runID: runID,
            actorIdentity: actorIdentity,
            workspaceID: workspaceID,
            workspaceRoot: workspace,
            journalRoot: runRoot.appendingPathComponent("journal", isDirectory: true),
            outboxRoot: runRoot.appendingPathComponent("outbox", isDirectory: true),
            hostBudget: hostBudget,
            maximumDispatchBatch: maximumDispatchBatch,
            registeredAt: durableRegisteredAt,
            enrollmentEvidence: nil
        )
        try Self.validate(
            registration,
            rootDirectory: rootDirectory,
            runsDirectory: runsDirectory,
            limits: limits
        )
        snapshot = try withLock {
            try Self.load(
                from: snapshotURL,
                rootDirectory: rootDirectory,
                runsDirectory: runsDirectory,
                limits: limits
            )
        }
        if let existing = snapshot.registrations.first(where: {
            $0.runID == runID
        }) {
            guard Self.sameRegistrationIdentity(existing, registration) else {
                throw WorkspaceMutationRecoveryRegistryError.duplicateRunConflict
            }
            return existing
        }
        guard snapshot.registrations.count < limits.maximumRuns else {
            throw WorkspaceMutationRecoveryRegistryError.capacityExceeded
        }
        return registration
    }

    /// Fast fail-closed check used before creating a run journal. The commit
    /// path repeats this check while holding the registry file lock, so this
    /// is only an early side-effect guard and never the authority boundary.
    func requireUnconsumedRatificationReceipt(
        _ receiptID: ReceiptID
    ) throws {
        guard !receiptID.rawValue.isEmpty else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        snapshot = try withLock {
            try Self.load(
                from: snapshotURL,
                rootDirectory: rootDirectory,
                runsDirectory: runsDirectory,
                limits: limits
            )
        }
        guard !snapshot.registrations.contains(where: {
            $0.enrollmentEvidence?.authority == .ratifiedUserContract
                && $0.enrollmentEvidence?.ratificationReceiptID == receiptID
        }) else {
            throw WorkspaceMutationRecoveryRegistryError
                .ratificationReceiptAlreadyConsumed
        }
    }

    /// Publishes recovery only after the enrollment coordinator sealed proof
    /// of an accepted `runCreated` journal transaction and exact projection.
    @discardableResult
    func commit(
        _ proof: JournaledKernelRunEnrollmentProof
    ) throws -> WorkspaceMutationRecoveryRegistration {
        let registration = proof.registration
        guard proof.runID == registration.runID,
              registration.enrollmentEvidence == proof.enrollmentEvidence,
              proof.enrollmentEvidence.authority == .ratifiedUserContract,
              proof.enrollmentEvidence.runID == registration.runID,
              proof.journalTransaction.endingSequence >=
                proof.journalTransaction.startingSequence,
              proof.enrollmentEvidence.createCommandID ==
                proof.journalTransaction.commandID,
              proof.enrollmentEvidence.journalFrameDigest ==
                proof.journalTransaction.frameDigest,
              proof.enrollmentEvidence.journalEndingSequence ==
                proof.journalTransaction.endingSequence,
              !proof.journalTransaction.eventIDs.isEmpty,
              !proof.journalTransaction.frameDigest.rawValue.isEmpty else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        return try commitRegistration(registration)
    }

    private func commitRegistration(
        _ registration: WorkspaceMutationRecoveryRegistration
    ) throws -> WorkspaceMutationRecoveryRegistration {
        try Self.validate(
            registration,
            rootDirectory: rootDirectory,
            runsDirectory: runsDirectory,
            limits: limits
        )
        return try mutate { current in
            if let existing = current.registrations.first(where: {
                $0.runID == registration.runID
            }) {
                guard existing == registration else {
                    throw WorkspaceMutationRecoveryRegistryError.duplicateRunConflict
                }
                return existing
            }
            if let evidence = registration.enrollmentEvidence,
               evidence.authority == .ratifiedUserContract,
               current.registrations.contains(where: {
                   $0.enrollmentEvidence?.authority == .ratifiedUserContract
                       && $0.enrollmentEvidence?.ratificationReceiptID ==
                           evidence.ratificationReceiptID
               }) {
                throw WorkspaceMutationRecoveryRegistryError
                    .ratificationReceiptAlreadyConsumed
            }
            guard current.registrations.count < limits.maximumRuns else {
                throw WorkspaceMutationRecoveryRegistryError.capacityExceeded
            }
            current.registrations.append(registration)
            current.registrations.sort { $0.runID.rawValue < $1.runID.rawValue }
            return registration
        }
    }

    func registrations(limit: Int) throws -> [WorkspaceMutationRecoveryRegistration] {
        guard limit > 0, limit <= limits.maximumRuns else {
            throw WorkspaceMutationRecoveryRegistryError.capacityExceeded
        }
        snapshot = try withLock {
            try Self.load(
                from: snapshotURL,
                rootDirectory: rootDirectory,
                runsDirectory: runsDirectory,
                limits: limits
            )
        }
        return Array(snapshot.registrations.prefix(limit))
    }

    func registration(
        runID: KernelRunID
    ) throws -> WorkspaceMutationRecoveryRegistration? {
        snapshot = try withLock {
            try Self.load(
                from: snapshotURL,
                rootDirectory: rootDirectory,
                runsDirectory: runsDirectory,
                limits: limits
            )
        }
        return snapshot.registrations.first { $0.runID == runID }
    }

    private func mutate<T>(
        _ body: (inout WorkspaceMutationRecoveryRegistrySnapshot) throws -> T
    ) throws -> T {
        try withLock {
            var current = try Self.load(
                from: snapshotURL,
                rootDirectory: rootDirectory,
                runsDirectory: runsDirectory,
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
                at: runsDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.persistenceFailed
        }
        guard chmod(rootDirectory.path, 0o700) == 0,
              chmod(runsDirectory.path, 0o700) == 0 else {
            throw WorkspaceMutationRecoveryRegistryError.persistenceFailed
        }
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            guard FileManager.default.createFile(atPath: lockURL.path, contents: nil) else {
                throw WorkspaceMutationRecoveryRegistryError.lockFailed
            }
            _ = chmod(lockURL.path, 0o600)
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: lockURL)
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.lockFailed
        }
        guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
            try? handle.close()
            throw WorkspaceMutationRecoveryRegistryError.lockFailed
        }
        defer {
            flock(handle.fileDescriptor, LOCK_UN)
            try? handle.close()
        }
        return try body()
    }

    private static func load(
        from url: URL,
        rootDirectory: URL,
        runsDirectory: URL,
        limits: WorkspaceMutationRecoveryRegistryLimits
    ) throws -> WorkspaceMutationRecoveryRegistrySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            var empty = WorkspaceMutationRecoveryRegistrySnapshot(
                schemaVersion: 1,
                registrations: [],
                snapshotDigest: ContentDigest("")
            )
            empty.snapshotDigest = snapshotDigest(empty)
            return empty
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value <= limits.maximumBytes else {
            throw WorkspaceMutationRecoveryRegistryError.capacityExceeded
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(
                WorkspaceMutationRecoveryRegistrySnapshot.self,
                from: Data(contentsOf: url)
            )
            let ratificationReceiptIDs = decoded.registrations.compactMap {
                registration -> ReceiptID? in
                guard registration.enrollmentEvidence?.authority ==
                    .ratifiedUserContract else { return nil }
                return registration.enrollmentEvidence?.ratificationReceiptID
            }
            guard decoded.schemaVersion == 1,
                  decoded.registrations.count <= limits.maximumRuns,
                  Set(decoded.registrations.map(\.runID)).count ==
                    decoded.registrations.count,
                  decoded.registrations == decoded.registrations.sorted(by: {
                      $0.runID.rawValue < $1.runID.rawValue
                  }),
                  Set(ratificationReceiptIDs).count ==
                    ratificationReceiptIDs.count,
                  decoded.registrations.allSatisfy({ registration in
                      (try? validate(
                        registration,
                        rootDirectory: rootDirectory,
                        runsDirectory: runsDirectory,
                        limits: limits
                      )) != nil
                  }),
                  decoded.snapshotDigest == snapshotDigest(decoded) else {
                throw WorkspaceMutationRecoveryRegistryError.corruptSnapshot
            }
            return decoded
        } catch let error as WorkspaceMutationRecoveryRegistryError {
            throw error
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.corruptSnapshot
        }
    }

    private static func validate(
        _ registration: WorkspaceMutationRecoveryRegistration,
        rootDirectory: URL,
        runsDirectory: URL,
        limits: WorkspaceMutationRecoveryRegistryLimits
    ) throws {
        guard registration.schemaVersion == 1,
              validPathComponent(registration.runID.rawValue),
              !registration.actorIdentity.id.rawValue.isEmpty,
              !registration.actorIdentity.role.isEmpty,
              !registration.actorIdentity.lineageDigest.rawValue.isEmpty,
              !registration.workspaceID.rawValue.isEmpty,
              registration.maximumDispatchBatch > 0,
              registration.maximumDispatchBatch <= limits.maximumDispatchBatch else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
        if let evidence = registration.enrollmentEvidence {
            guard evidence.schemaVersion == 1,
                  evidence.runID == registration.runID,
                  !evidence.contractID.rawValue.isEmpty,
                  !evidence.candidateDigest.rawValue.isEmpty,
                  !evidence.ratificationReceiptID.rawValue.isEmpty,
                  !evidence.userActorID.rawValue.isEmpty,
                  !evidence.userActorLineageDigest.rawValue.isEmpty,
                  !evidence.createCommandID.rawValue.isEmpty,
                  !evidence.journalFrameDigest.rawValue.isEmpty else {
                throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
            }
        }
        let workspace = registration.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        try rejectOverlap(workspace: workspace, registry: rootDirectory)
        let expectedRunRoot = runsDirectory.appendingPathComponent(
            registration.runID.rawValue,
            isDirectory: true
        )
        let expectedJournal = expectedRunRoot.appendingPathComponent(
            "journal",
            isDirectory: true
        ).standardizedFileURL
        let expectedOutbox = expectedRunRoot.appendingPathComponent(
            "outbox",
            isDirectory: true
        ).standardizedFileURL
        guard registration.workspaceRoot == workspace,
              registration.journalRoot.standardizedFileURL == expectedJournal,
              registration.outboxRoot.standardizedFileURL == expectedOutbox,
              expectedJournal != expectedOutbox else {
            throw WorkspaceMutationRecoveryRegistryError.invalidRegistration
        }
    }

    private static func rejectOverlap(workspace: URL, registry: URL) throws {
        let workspacePath = workspace.path
        let registryPath = registry.path
        guard workspacePath != registryPath,
              !registryPath.hasPrefix(workspacePath + "/"),
              !workspacePath.hasPrefix(registryPath + "/") else {
            throw WorkspaceMutationRecoveryRegistryError.workspaceOverlapsRegistry
        }
    }

    private static func validPathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func sameRegistrationIdentity(
        _ lhs: WorkspaceMutationRecoveryRegistration,
        _ rhs: WorkspaceMutationRecoveryRegistration
    ) -> Bool {
        var left = lhs
        var right = rhs
        left.enrollmentEvidence = nil
        right.enrollmentEvidence = nil
        return left == right
    }

    private static func isExistingDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func persist(
        _ snapshot: WorkspaceMutationRecoveryRegistrySnapshot,
        to url: URL,
        limits: WorkspaceMutationRecoveryRegistryLimits
    ) throws {
        let data = encode(snapshot)
        guard UInt64(data.count) <= limits.maximumBytes else {
            throw WorkspaceMutationRecoveryRegistryError.capacityExceeded
        }
        do {
            try data.write(to: url, options: .atomic)
            _ = chmod(url.path, 0o600)
            let handle = try FileHandle(forUpdating: url)
            try handle.synchronize()
            try handle.close()
        } catch {
            throw WorkspaceMutationRecoveryRegistryError.persistenceFailed
        }
    }

    private static func snapshotDigest(
        _ snapshot: WorkspaceMutationRecoveryRegistrySnapshot
    ) -> ContentDigest {
        digest(encode(WorkspaceMutationRecoveryRegistrySnapshot(
            schemaVersion: snapshot.schemaVersion,
            registrations: snapshot.registrations,
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
        return (try? encoder.encode(value)) ?? Data()
    }
}
