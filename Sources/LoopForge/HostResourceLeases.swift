import Foundation

enum GraphHostResourceKind: String, Codable, CaseIterable, Sendable {
    case iosSimulatorBoot
}

enum GraphHostResourceObservedState: String, Codable, Sendable {
    case active
    case inactive
    case missing
}

enum GraphHostResourceOwnership: String, Codable, Sendable {
    /// LoopForge observed the resource as inactive before the first holder and
    /// therefore owns only the temporary state transition, not the resource.
    case ownedTransition
    /// The user or another process already had the resource active. LoopForge
    /// may use it, but must never restore or terminate it.
    case borrowed
}

enum GraphHostResourceLeaseState: String, Codable, Sendable {
    case acquiring
    case active
    case releasing
    case released
    case releaseFailed
}

struct GraphHostResourceScope: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let nodeID: String
    let iteration: Int
    let createdAt: Date
    var releasedAt: Date?
    let registryPath: String
    /// Per-scope inbox owned by the LoopForge process. Workers may submit
    /// allowlisted requests here but never write the lease registry itself.
    let brokerDirectory: String?
    let brokerToken: String?
}

struct GraphHostResourceLease: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: GraphHostResourceKind
    /// A provider-validated, exact identifier. For v1 this is one Simulator
    /// device UUID; arbitrary commands and broad selectors are never stored.
    let identifier: String
    let taskID: UUID
    let initialState: GraphHostResourceObservedState
    let ownership: GraphHostResourceOwnership
    var holderScopeIDs: [UUID]
    var state: GraphHostResourceLeaseState
    let acquiredAt: Date
    var releasedAt: Date?
    var lastError: String?
}

struct GraphHostResourceRecoveryReport: Equatable, Sendable {
    var releasedLeaseIDs: [UUID] = []
    var failedTaskIDs: Set<UUID> = []

    static let empty = GraphHostResourceRecoveryReport()
}

enum GraphHostResourceBrokerOperation: String, Codable, Sendable {
    case declareIOSSimulatorBoot
    case markAcquired
}

struct GraphHostResourceBrokerRequest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: UUID
    let scopeID: UUID
    let token: String
    let operation: GraphHostResourceBrokerOperation
    let identifier: String?
    let leaseID: UUID?
}

struct GraphHostResourceBrokerResponse: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let requestID: UUID
    let success: Bool
    let leaseID: UUID?
    let performAcquisition: Bool
    let error: String?
}

enum GraphHostResourceLeaseError: LocalizedError {
    case unsupportedKind(GraphHostResourceKind)
    case invalidScope
    case invalidIdentifier(String)
    case persistence(String)
    case provider(String)
    case releaseFailed(UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedKind(let kind):
            return "No host-resource provider is available for \(kind.rawValue)."
        case .invalidScope:
            return "The host-resource scope is missing or already closed."
        case .invalidIdentifier(let identifier):
            return "The host-resource identifier is invalid: \(identifier)."
        case .persistence(let detail):
            return "The host-resource lease checkpoint could not be saved. \(detail)"
        case .provider(let detail):
            return detail
        case .releaseFailed(let taskID):
            return "LoopForge could not restore a host resource owned by Graph task \(taskID.uuidString). The task was stopped to avoid compounding the leak."
        }
    }
}

protocol GraphHostResourceProvider: Sendable {
    var kind: GraphHostResourceKind { get }
    func observedState(identifier: String) async throws -> GraphHostResourceObservedState
    func release(identifier: String) async throws
}

protocol GraphHostResourceLeaseManaging: Sendable {
    var registryPath: String { get }

    func beginNodeScope(
        taskID: UUID,
        nodeID: String,
        iteration: Int
    ) async throws -> GraphHostResourceScope

    /// Records intent before a broker changes host state. The broker must call
    /// `markAcquired` after the typed acquisition succeeds. Persisting intent
    /// first closes the crash window between `simctl boot` and bookkeeping.
    func declareAcquisition(
        scopeID: UUID,
        kind: GraphHostResourceKind,
        identifier: String
    ) async throws -> GraphHostResourceLease

    func markAcquired(leaseID: UUID) async throws
    func releaseScope(id: UUID, reason: String) async -> GraphHostResourceRecoveryReport
    func releaseTask(taskID: UUID, reason: String) async -> GraphHostResourceRecoveryReport
    func releaseAll(reason: String) async -> GraphHostResourceRecoveryReport
    func reconcileDanglingLeases() async -> GraphHostResourceRecoveryReport
    func serviceBrokerRequests(scopeID: UUID) async
    func processBrokerRequests(scopeID: UUID) async
}

private struct GraphHostResourceRegistrySnapshot: Codable {
    var schemaVersion = 1
    var scopes: [GraphHostResourceScope] = []
    var leases: [GraphHostResourceLease] = []
}

enum GraphHostResourceBrokerRuntime {
    static var executableURL: URL? {
        if let bundled = PathResolver.bundledExecutable(
            named: "loopforge-host-resource-broker"
        ) {
            return bundled
        }
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let developmentBroker = projectRoot
            .appendingPathComponent("Resources/bin/loopforge-host-resource-broker")
        return FileManager.default.isExecutableFile(atPath: developmentBroker.path)
            ? developmentBroker
            : nil
    }
}

actor GraphHostResourceLeaseRegistry: GraphHostResourceLeaseManaging {
    nonisolated let registryPath: String

    private let storageURL: URL
    private let brokerRootURL: URL
    private var snapshot: GraphHostResourceRegistrySnapshot
    private let providers: [GraphHostResourceKind: any GraphHostResourceProvider]

    init(
        storageURL: URL = GraphHostResourceLeaseRegistry.defaultStorageURL(),
        providers: [any GraphHostResourceProvider] = [IOSSimulatorHostResourceProvider()]
    ) {
        self.storageURL = storageURL
        self.brokerRootURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("BrokerRequests", isDirectory: true)
        self.registryPath = storageURL.path
        self.providers = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.kind, $0) }
        )
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder.loopForgeLeaseDecoder.decode(
               GraphHostResourceRegistrySnapshot.self,
               from: data
           ) {
            self.snapshot = decoded
        } else {
            self.snapshot = GraphHostResourceRegistrySnapshot()
        }
    }

    static func defaultStorageURL() -> URL {
        TaskStore.applicationSupportDirectory()
            .appendingPathComponent("HostResourceLeases", isDirectory: true)
            .appendingPathComponent("leases.json")
    }

    func beginNodeScope(
        taskID: UUID,
        nodeID: String,
        iteration: Int
    ) throws -> GraphHostResourceScope {
        let scopeID = UUID()
        let brokerDirectory = brokerRootURL
            .appendingPathComponent(scopeID.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: brokerDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw GraphHostResourceLeaseError.persistence(error.localizedDescription)
        }
        let scope = GraphHostResourceScope(
            id: scopeID,
            taskID: taskID,
            nodeID: nodeID,
            iteration: iteration,
            createdAt: Date(),
            releasedAt: nil,
            registryPath: storageURL.path,
            brokerDirectory: brokerDirectory.path,
            brokerToken: UUID().uuidString
        )
        snapshot.scopes.append(scope)
        try persist()
        return scope
    }

    func declareAcquisition(
        scopeID: UUID,
        kind: GraphHostResourceKind,
        identifier: String
    ) async throws -> GraphHostResourceLease {
        guard let scopeIndex = snapshot.scopes.firstIndex(where: {
            $0.id == scopeID && $0.releasedAt == nil
        }) else {
            throw GraphHostResourceLeaseError.invalidScope
        }
        _ = scopeIndex
        guard let provider = providers[kind] else {
            throw GraphHostResourceLeaseError.unsupportedKind(kind)
        }
        let normalizedIdentifier: String
        switch kind {
        case .iosSimulatorBoot:
            guard let uuid = UUID(uuidString: identifier) else {
                throw GraphHostResourceLeaseError.invalidIdentifier(identifier)
            }
            normalizedIdentifier = uuid.uuidString
        }

        if let index = snapshot.leases.firstIndex(where: {
            $0.kind == kind
                && $0.identifier == normalizedIdentifier
                && $0.state != .released
        }) {
            if !snapshot.leases[index].holderScopeIDs.contains(scopeID) {
                snapshot.leases[index].holderScopeIDs.append(scopeID)
                try persist()
            }
            return snapshot.leases[index]
        }

        let observed: GraphHostResourceObservedState
        do {
            observed = try await provider.observedState(identifier: normalizedIdentifier)
        } catch {
            throw GraphHostResourceLeaseError.provider(error.localizedDescription)
        }
        let ownership: GraphHostResourceOwnership = observed == .active
            ? .borrowed
            : .ownedTransition
        let lease = GraphHostResourceLease(
            id: UUID(),
            kind: kind,
            identifier: normalizedIdentifier,
            taskID: snapshot.scopes[scopeIndex].taskID,
            initialState: observed,
            ownership: ownership,
            holderScopeIDs: [scopeID],
            state: ownership == .borrowed ? .active : .acquiring,
            acquiredAt: Date(),
            releasedAt: nil,
            lastError: nil
        )
        snapshot.leases.append(lease)
        try persist()
        return lease
    }

    func markAcquired(leaseID: UUID) throws {
        guard let index = snapshot.leases.firstIndex(where: { $0.id == leaseID }),
              snapshot.leases[index].state != .released else {
            return
        }
        snapshot.leases[index].state = .active
        snapshot.leases[index].lastError = nil
        try persist()
    }

    func releaseScope(
        id: UUID,
        reason: String
    ) async -> GraphHostResourceRecoveryReport {
        guard let index = snapshot.scopes.firstIndex(where: { $0.id == id }) else {
            return .empty
        }
        if snapshot.scopes[index].releasedAt == nil {
            snapshot.scopes[index].releasedAt = Date()
        }
        for leaseIndex in snapshot.leases.indices
            where snapshot.leases[leaseIndex].holderScopeIDs.contains(id) {
            snapshot.leases[leaseIndex].holderScopeIDs.removeAll { $0 == id }
        }
        try? persist()
        return await releaseUnheldLeases(
            where: { _ in true },
            reason: reason
        )
    }

    func releaseTask(
        taskID: UUID,
        reason: String
    ) async -> GraphHostResourceRecoveryReport {
        let scopeIDs = snapshot.scopes
            .filter { $0.taskID == taskID && $0.releasedAt == nil }
            .map(\.id)
        for scopeID in scopeIDs {
            if let index = snapshot.scopes.firstIndex(where: { $0.id == scopeID }) {
                snapshot.scopes[index].releasedAt = Date()
            }
            for leaseIndex in snapshot.leases.indices
                where snapshot.leases[leaseIndex].holderScopeIDs.contains(scopeID) {
                snapshot.leases[leaseIndex].holderScopeIDs.removeAll { $0 == scopeID }
            }
        }
        try? persist()
        // A resource can be shared by scopes from more than one task. Once this
        // task's holders are removed, release every now-unheld lease; leases
        // still referenced by another task remain protected by the holder check.
        return await releaseUnheldLeases(where: { _ in true }, reason: reason)
    }

    func releaseAll(reason: String) async -> GraphHostResourceRecoveryReport {
        for index in snapshot.scopes.indices where snapshot.scopes[index].releasedAt == nil {
            snapshot.scopes[index].releasedAt = Date()
        }
        for index in snapshot.leases.indices {
            snapshot.leases[index].holderScopeIDs.removeAll()
        }
        try? persist()
        return await releaseUnheldLeases(where: { _ in true }, reason: reason)
    }

    func reconcileDanglingLeases() async -> GraphHostResourceRecoveryReport {
        await releaseAll(reason: "Recovered an interrupted LoopForge host-resource scope")
    }

    func serviceBrokerRequests(scopeID: UUID) async {
        while !Task.isCancelled {
            await processBrokerRequests(scopeID: scopeID)
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }
    }

    func processBrokerRequests(scopeID: UUID) async {
        guard let scope = snapshot.scopes.first(where: {
            $0.id == scopeID && $0.releasedAt == nil
        }),
        let directoryPath = scope.brokerDirectory,
        let token = scope.brokerToken else {
            return
        }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        guard directory.standardizedFileURL.deletingLastPathComponent() == brokerRootURL.standardizedFileURL else {
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted().prefix(64) where name.hasSuffix(".request.json") {
            let rawID = String(name.dropLast(".request.json".count))
            guard let requestID = UUID(uuidString: rawID) else { continue }
            let requestURL = directory.appendingPathComponent(name)
            let responseURL = directory.appendingPathComponent("\(rawID).response.json")
            guard !FileManager.default.fileExists(atPath: responseURL.path),
                  let values = try? requestURL.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= 16_384,
                  let data = try? Data(contentsOf: requestURL),
                  let request = try? JSONDecoder.loopForgeLeaseDecoder.decode(
                    GraphHostResourceBrokerRequest.self,
                    from: data
                  ) else {
                continue
            }
            let response: GraphHostResourceBrokerResponse
            do {
                guard request.schemaVersion == 1,
                      request.requestID == requestID,
                      request.scopeID == scopeID,
                      request.token == token else {
                    throw GraphHostResourceLeaseError.invalidScope
                }
                response = try await handleBrokerRequest(request, scope: scope)
            } catch {
                response = GraphHostResourceBrokerResponse(
                    schemaVersion: 1,
                    requestID: requestID,
                    success: false,
                    leaseID: nil,
                    performAcquisition: false,
                    error: sanitizedLogText(error.localizedDescription)
                )
            }
            if let responseData = try? JSONEncoder.loopForgeLeaseEncoder.encode(response) {
                try? responseData.write(to: responseURL, options: .atomic)
            }
        }
    }

    func lease(id: UUID) -> GraphHostResourceLease? {
        snapshot.leases.first { $0.id == id }
    }

    func activeLeases() -> [GraphHostResourceLease] {
        snapshot.leases.filter { $0.state != .released }
    }

    private func handleBrokerRequest(
        _ request: GraphHostResourceBrokerRequest,
        scope: GraphHostResourceScope
    ) async throws -> GraphHostResourceBrokerResponse {
        switch request.operation {
        case .declareIOSSimulatorBoot:
            guard let identifier = request.identifier,
                  UUID(uuidString: identifier) != nil,
                  request.leaseID == nil else {
                throw GraphHostResourceLeaseError.invalidIdentifier(
                    request.identifier ?? "missing"
                )
            }
            let lease = try await declareAcquisition(
                scopeID: scope.id,
                kind: .iosSimulatorBoot,
                identifier: identifier
            )
            let isAcquisitionOwner = lease.ownership == .ownedTransition
                && lease.state == .acquiring
                && lease.holderScopeIDs.first == scope.id
            return GraphHostResourceBrokerResponse(
                schemaVersion: 1,
                requestID: request.requestID,
                success: true,
                leaseID: lease.id,
                performAcquisition: isAcquisitionOwner,
                error: nil
            )
        case .markAcquired:
            guard request.identifier == nil,
                  let leaseID = request.leaseID,
                  let lease = snapshot.leases.first(where: { $0.id == leaseID }),
                  lease.kind == .iosSimulatorBoot,
                  lease.holderScopeIDs.contains(scope.id) else {
                throw GraphHostResourceLeaseError.invalidScope
            }
            try markAcquired(leaseID: leaseID)
            return GraphHostResourceBrokerResponse(
                schemaVersion: 1,
                requestID: request.requestID,
                success: true,
                leaseID: leaseID,
                performAcquisition: false,
                error: nil
            )
        }
    }

    private func releaseUnheldLeases(
        where predicate: (GraphHostResourceLease) -> Bool,
        reason: String
    ) async -> GraphHostResourceRecoveryReport {
        var report = GraphHostResourceRecoveryReport()
        let candidates = snapshot.leases.indices.filter {
            predicate(snapshot.leases[$0])
                && snapshot.leases[$0].holderScopeIDs.isEmpty
                && snapshot.leases[$0].state != .released
        }
        for index in candidates {
            let lease = snapshot.leases[index]
            guard let provider = providers[lease.kind] else {
                snapshot.leases[index].state = .releaseFailed
                snapshot.leases[index].lastError =
                    "No provider is available to release \(lease.kind.rawValue)."
                report.failedTaskIDs.insert(lease.taskID)
                continue
            }
            if lease.ownership == .borrowed || lease.initialState == .active {
                snapshot.leases[index].state = .released
                snapshot.leases[index].releasedAt = Date()
                snapshot.leases[index].lastError = nil
                report.releasedLeaseIDs.append(lease.id)
                continue
            }

            snapshot.leases[index].state = .releasing
            snapshot.leases[index].lastError = nil
            try? persist()
            do {
                let state = try await provider.observedState(identifier: lease.identifier)
                if state == .active {
                    try await provider.release(identifier: lease.identifier)
                }
                snapshot.leases[index].state = .released
                snapshot.leases[index].releasedAt = Date()
                snapshot.leases[index].lastError = nil
                report.releasedLeaseIDs.append(lease.id)
            } catch {
                snapshot.leases[index].state = .releaseFailed
                snapshot.leases[index].lastError =
                    "\(reason): \(error.localizedDescription)"
                report.failedTaskIDs.insert(lease.taskID)
            }
        }
        // Node turns that never acquire a hosted resource are the common case.
        // Keep only live scopes so the durable registry does not grow once per
        // Graph turn during long-running tasks.
        let heldScopeIDs = Set(snapshot.leases.flatMap(\.holderScopeIDs))
        let finishedScopes = snapshot.scopes.filter {
            $0.releasedAt != nil && !heldScopeIDs.contains($0.id)
        }
        for scope in finishedScopes {
            guard let path = scope.brokerDirectory else { continue }
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            guard directory.standardizedFileURL.deletingLastPathComponent()
                == brokerRootURL.standardizedFileURL else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
        let finishedScopeIDs = Set(finishedScopes.map(\.id))
        snapshot.scopes.removeAll { finishedScopeIDs.contains($0.id) }
        try? persist()
        return report
    }

    private func persist() throws {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.loopForgeLeaseEncoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            throw GraphHostResourceLeaseError.persistence(error.localizedDescription)
        }
    }
}

/// Owns the lifetime boundary around one Graph node turn. Cleanup is performed
/// after success, failure, or cancellation before the result is returned to the
/// scheduler. The registry executes release work independently of node status,
/// because `.blocked` is also used for transient transport degradation.
struct GraphHostResourceExecutionScope: Sendable {
    let registry: any GraphHostResourceLeaseManaging

    func run<T: Sendable>(
        taskID: UUID,
        nodeID: String,
        iteration: Int,
        operation: @escaping @Sendable (GraphHostResourceScope) async throws -> T
    ) async throws -> T {
        let scope = try await registry.beginNodeScope(
            taskID: taskID,
            nodeID: nodeID,
            iteration: iteration
        )
        let brokerService = Task {
            await registry.serviceBrokerRequests(scopeID: scope.id)
        }
        do {
            let value = try await operation(scope)
            brokerService.cancel()
            await brokerService.value
            await registry.processBrokerRequests(scopeID: scope.id)
            let report = await registry.releaseScope(
                id: scope.id,
                reason: "Graph node turn completed"
            )
            if report.failedTaskIDs.contains(taskID) {
                throw GraphHostResourceLeaseError.releaseFailed(taskID)
            }
            return value
        } catch {
            brokerService.cancel()
            await brokerService.value
            await registry.processBrokerRequests(scopeID: scope.id)
            _ = await registry.releaseScope(
                id: scope.id,
                reason: error is CancellationError
                    ? "Graph node turn was cancelled"
                    : "Graph node turn failed"
            )
            throw error
        }
    }
}

final class IOSSimulatorHostResourceProvider: GraphHostResourceProvider, @unchecked Sendable {
    let kind = GraphHostResourceKind.iosSimulatorBoot
    private let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    func observedState(identifier: String) async throws -> GraphHostResourceObservedState {
        guard let uuid = UUID(uuidString: identifier) else {
            throw GraphHostResourceLeaseError.invalidIdentifier(identifier)
        }
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list", "devices", "--json"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 30
        )
        guard result.exitCode == 0 else {
            throw GraphHostResourceLeaseError.provider(
                "Simulator state inspection failed: \(sanitizedLogText(result.stderr).prefix(320))"
            )
        }
        return Self.observedState(identifier: uuid.uuidString, json: result.stdout)
    }

    func release(identifier: String) async throws {
        guard let uuid = UUID(uuidString: identifier) else {
            throw GraphHostResourceLeaseError.invalidIdentifier(identifier)
        }
        let canonicalIdentifier = uuid.uuidString
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "shutdown", canonicalIdentifier],
            environment: ProcessInfo.processInfo.environment,
            timeout: 30
        )
        guard result.exitCode == 0 else {
            if let state = try? await observedState(identifier: canonicalIdentifier),
               state != .active {
                return
            }
            throw GraphHostResourceLeaseError.provider(
                "Simulator \(canonicalIdentifier) could not be shut down: \(sanitizedLogText(result.stderr).prefix(320))"
            )
        }
    }

    static func observedState(
        identifier: String,
        json: String
    ) -> GraphHostResourceObservedState {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = root["devices"] as? [String: Any] else {
            return .missing
        }
        for value in runtimes.values {
            guard let devices = value as? [[String: Any]] else { continue }
            for device in devices where (device["udid"] as? String)?
                .caseInsensitiveCompare(identifier) == .orderedSame {
                // Booting and other transitional states still represent a
                // state change that can finish after the short-lived simctl
                // process exits. Only the stable Shutdown state is inactive.
                return (device["state"] as? String) == "Shutdown" ? .inactive : .active
            }
        }
        return .missing
    }
}

private extension JSONEncoder {
    static var loopForgeLeaseEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var loopForgeLeaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
