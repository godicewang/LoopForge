import Foundation

enum RuntimeResourceKind: String, Codable, Hashable, Sendable {
    case asyncTask
    case processTree
    case timer
    case fileObserver
    case capability
    case agentTurn
    case nativeSession
    case localService
    case persistence
    case evidenceWork
    case powerAssertion
    case workspaceMutation
}

enum ResourcePurpose: String, Codable, Hashable, Sendable {
    case productive
    case cleanup
}

enum RuntimeOwnershipMode: String, Codable, Hashable, Sendable {
    case owned
    case borrowed
}

enum RuntimeReleasePolicy: String, Codable, Hashable, Sendable {
    case join
    case gracefulThenTerminate
    case detachOnly
}

struct RuntimeExternalIdentity: Codable, Hashable, Sendable {
    var stableDigest: ContentDigest
    var processID: Int32?
    var processStartMonotonicNanoseconds: UInt64?
    var processStartSystemNanoseconds: UInt64? = nil
    var parentResourceID: OwnedResourceID?
    /// Optional for pre-kernel and non-process identities. Journaled process
    /// launches persist both digests explicitly in addition to the composite
    /// stable identity so recovery and reports need not reverse a hash.
    var executableContentDigest: ContentDigest? = nil
    var environmentContentDigest: ContentDigest? = nil
    /// Exact kernel-compiled argv identity for provider processes. Optional
    /// only for historical and non-provider runtime identities.
    var argumentVectorContentDigest: ContentDigest? = nil
    /// Present only when the process was held behind the native sandbox gate,
    /// observed stopped, confirmed sandboxed by the host, and then resumed.
    var nativeSandboxAttestation: KernelNativeSandboxAttestationReceipt? = nil
    /// Exact in-process kernel ceilings installed by KernelSandboxGate before
    /// exec. Optional preserves historical and non-verifier identities.
    var kernelResourceLimits: ManagedProcessKernelResourceLimits? = nil
}

struct ResourceVector: Codable, Hashable, Sendable {
    var cpuWeight: UInt16
    var memoryBytes: UInt64
    var diskIOWeight: UInt16
    var gpuWeight: UInt16
    var networkWeight: UInt16
    var guiSessionCount: UInt16
    var processCount: UInt16

    static let zero = ResourceVector(
        cpuWeight: 0,
        memoryBytes: 0,
        diskIOWeight: 0,
        gpuWeight: 0,
        networkWeight: 0,
        guiSessionCount: 0,
        processCount: 0
    )

    func adding(_ other: ResourceVector) -> ResourceVector? {
        guard let cpu = exactAdd(cpuWeight, other.cpuWeight),
              let memory = exactAdd(memoryBytes, other.memoryBytes),
              let disk = exactAdd(diskIOWeight, other.diskIOWeight),
              let gpu = exactAdd(gpuWeight, other.gpuWeight),
              let network = exactAdd(networkWeight, other.networkWeight),
              let gui = exactAdd(guiSessionCount, other.guiSessionCount),
              let processes = exactAdd(processCount, other.processCount) else {
            return nil
        }
        return ResourceVector(
            cpuWeight: cpu,
            memoryBytes: memory,
            diskIOWeight: disk,
            gpuWeight: gpu,
            networkWeight: network,
            guiSessionCount: gui,
            processCount: processes
        )
    }

    func fits(within capacity: ResourceVector) -> Bool {
        cpuWeight <= capacity.cpuWeight &&
            memoryBytes <= capacity.memoryBytes &&
            diskIOWeight <= capacity.diskIOWeight &&
            gpuWeight <= capacity.gpuWeight &&
            networkWeight <= capacity.networkWeight &&
            guiSessionCount <= capacity.guiSessionCount &&
            processCount <= capacity.processCount
    }

    private func exactAdd<T: FixedWidthInteger>(_ lhs: T, _ rhs: T) -> T? {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : sum
    }
}

struct HostResourceBudget: Codable, Hashable, Sendable {
    var nominal: ResourceVector

    func effective(for pressure: HostPressure) -> ResourceVector {
        switch pressure.effectiveThermalState {
        case .nominal:
            return nominal
        case .fair, .unknown:
            return ResourceVector(
                cpuWeight: reduced(nominal.cpuWeight, divisor: 2),
                memoryBytes: nominal.memoryBytes,
                diskIOWeight: reduced(nominal.diskIOWeight, divisor: 2),
                gpuWeight: reduced(nominal.gpuWeight, divisor: 2),
                networkWeight: nominal.networkWeight,
                guiSessionCount: nominal.guiSessionCount,
                processCount: nominal.processCount
            )
        case .serious, .critical:
            return ResourceVector(
                cpuWeight: reduced(nominal.cpuWeight, divisor: 10),
                memoryBytes: nominal.memoryBytes,
                diskIOWeight: reduced(nominal.diskIOWeight, divisor: 10),
                gpuWeight: 0,
                networkWeight: reduced(nominal.networkWeight, divisor: 4),
                guiSessionCount: 0,
                processCount: reduced(nominal.processCount, divisor: 4)
            )
        }
    }

    private func reduced(_ value: UInt16, divisor: UInt16) -> UInt16 {
        guard value > 0 else { return 0 }
        return max(1, value / divisor)
    }
}

enum ThermalState: String, Codable, Hashable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

struct HostPressure: Codable, Hashable, Sendable {
    var thermalState: ThermalState
    var lowPowerMode: Bool
    var memoryPressureCritical: Bool

    var effectiveThermalState: ThermalState {
        if memoryPressureCritical { return .critical }
        if thermalState == .critical || thermalState == .serious { return thermalState }
        if lowPowerMode || thermalState == .fair || thermalState == .unknown { return .fair }
        return .nominal
    }

    static let nominal = HostPressure(
        thermalState: .nominal,
        lowPowerMode: false,
        memoryPressureCritical: false
    )
}

struct RuntimeLeaseRequest: Codable, Hashable, Sendable {
    var leaseID: ResourceLeaseID
    var resourceID: OwnedResourceID
    var runID: KernelRunID
    var occurrenceID: OccurrenceID?
    var attemptID: AttemptID?
    var kind: RuntimeResourceKind
    var purpose: ResourcePurpose
    var ownership: RuntimeOwnershipMode
    var releasePolicy: RuntimeReleasePolicy
    var externalIdentity: RuntimeExternalIdentity?
    var reservation: ResourceVector
    var requestedAtMonotonicNanoseconds: UInt64
    var renewalDeadlineMonotonicNanoseconds: UInt64?
    var progressReceiptID: ReceiptID?
}

struct RuntimeResourceLease: Codable, Hashable, Sendable {
    var request: RuntimeLeaseRequest
    var admittedAtMonotonicNanoseconds: UInt64
    var lastProgressReceiptID: ReceiptID?
}

enum RuntimeAdmissionRejection: Codable, Hashable, Sendable {
    case draining
    case thermalDeferred(ThermalState)
    case duplicateResource(existingLeaseID: ResourceLeaseID)
    case budgetExceeded
    case invalidReservation
    case powerLeaseMissingProgress
    case invalidPowerLease
    case invalidOwnership
    case invalidReleasePolicy
}

enum RuntimeAdmissionDecision: Equatable, Sendable {
    case accepted(RuntimeResourceLease, duplicate: Bool)
    case rejected(RuntimeAdmissionRejection)
}

enum RuntimeAdmissionOutcome: Codable, Hashable, Sendable {
    case accepted(RuntimeResourceLease, duplicate: Bool)
    case rejected(RuntimeAdmissionRejection)
}

struct RuntimeAdmissionReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var request: RuntimeLeaseRequest
    var outcome: RuntimeAdmissionOutcome
    var observedAt: Date
    var observedAtMonotonicNanoseconds: UInt64
}

struct QueuedRuntimeLease: Codable, Hashable, Sendable {
    var request: RuntimeLeaseRequest
    var priority: UInt8
    var enqueuedAtMonotonicNanoseconds: UInt64
    var expiresAtMonotonicNanoseconds: UInt64
}

enum RuntimeQueueRejection: Equatable, Sendable {
    case invalidRequest
    case invalidDeadline
    case draining
    case duplicateLeaseConflict
    case duplicateResource(existingLeaseID: ResourceLeaseID)
}

enum RuntimeQueueDecision: Equatable, Sendable {
    case queued(QueuedRuntimeLease, duplicate: Bool)
    case rejected(RuntimeQueueRejection)
}

struct RuntimeQueueAdvance: Equatable, Sendable {
    var expiredLeaseIDs: Set<ResourceLeaseID>
    var admitted: RuntimeResourceLease?
    var remainingLeaseIDs: [ResourceLeaseID]
}

enum RuntimeReleaseRejection: Codable, Hashable, Sendable {
    case unknownResource
    case staleLease(expected: ResourceLeaseID, supplied: ResourceLeaseID)
}

struct RuntimeReleaseReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var leaseID: ResourceLeaseID
    var resourceID: OwnedResourceID
    var releasedAtMonotonicNanoseconds: UInt64
    var duplicate: Bool
}

enum RuntimeReleaseOutcome: Codable, Hashable, Sendable {
    case released(RuntimeReleaseReceipt)
    case cleanupFailed(reasonDigest: ContentDigest)
    case rejected(RuntimeReleaseRejection)
}

struct RuntimeReleaseOutcomeReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var observedAt: Date
    var observedAtMonotonicNanoseconds: UInt64
    var outcome: RuntimeReleaseOutcome
    /// Present only when an owned native process release was preceded by an
    /// exact adapter-observed termination. Optional preserves replay of older
    /// and non-process release events.
    var managedProcessTermination: ManagedProcessTerminationReceipt? = nil
    /// Present when an owned native process exited naturally and the adapter
    /// joined the complete process group before journaled release. It is
    /// distinct from forced or requested termination provenance.
    var managedProcessExit: ManagedProcessExitReceipt? = nil
    /// Present only for an activated deterministic postimage verifier. The
    /// process runtime publishes this in the same release event so wall/output
    /// containment cannot be asserted independently of native exit ownership.
    var postimageVerifierContainment:
        KernelPostimageVerifierContainmentReceipt? = nil
}

enum RuntimeReleaseDecision: Equatable, Sendable {
    case released(RuntimeReleaseReceipt)
    case rejected(RuntimeReleaseRejection)
}

enum RuntimeDrainIntent: String, Codable, Hashable, Sendable {
    case pause
    case complete
    case stop
    case quit

    var priority: Int {
        switch self {
        case .pause: return 0
        case .complete: return 1
        case .stop: return 2
        case .quit: return 3
        }
    }
}

enum RuntimeSupervisorPhase: Codable, Hashable, Sendable {
    case accepting
    case draining(RuntimeDrainIntent)
}

struct RuntimeDrainSnapshot: Codable, Hashable, Sendable {
    var intent: RuntimeDrainIntent
    var liveResourceIDs: Set<OwnedResourceID>
    var cancelledQueuedLeaseIDs: Set<ResourceLeaseID>
}

struct RuntimeDrainReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var snapshot: RuntimeDrainSnapshot
    var observedAt: Date
    var observedAtMonotonicNanoseconds: UInt64
}

struct RuntimeExternalBindingReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var identity: RuntimeExternalIdentity
    var accepted: Bool
    var observedAt: Date
    var observedAtMonotonicNanoseconds: UInt64
}

struct RuntimeSupervisorProjection: Codable, Equatable, Sendable {
    var phase: RuntimeSupervisorPhase
    var pressure: HostPressure
    var capacity: ResourceVector
    var usage: ResourceVector
    var liveLeases: [RuntimeResourceLease]
    var queuedLeases: [QueuedRuntimeLease]
    var failedReleases: Set<OwnedResourceID>
}

struct RuntimeSupervisorRecoverySnapshot: Codable, Equatable, Sendable {
    var runID: KernelRunID
    var sourceSequence: UInt64
    var sourceFrameDigest: ContentDigest?
    var phase: RuntimeSupervisorPhase
    var liveLeases: [RuntimeResourceLease]
    var releasedReceipts: [RuntimeReleaseReceipt]
    var failedReleases: Set<OwnedResourceID>
}

struct RuntimeSupervisorRecoveryReceipt: Codable, Equatable, Sendable {
    var runID: KernelRunID
    var sourceSequence: UInt64
    var sourceFrameDigest: ContentDigest?
    var phase: RuntimeSupervisorPhase
    var liveResourceIDs: Set<OwnedResourceID>
    var failedReleases: Set<OwnedResourceID>
    var duplicate: Bool
}

enum RuntimeSupervisorRecoveryRejection: Equatable, Sendable {
    case runMismatch
    case supervisorAlreadyMutated
    case invalidSnapshot
}

enum RuntimeSupervisorRecoveryDecision: Equatable, Sendable {
    case restored(RuntimeSupervisorRecoveryReceipt)
    case rejected(RuntimeSupervisorRecoveryRejection)
}

enum RuntimeCleanupAction: Codable, Hashable, Sendable {
    case awaitJoin(resourceID: OwnedResourceID, leaseID: ResourceLeaseID)
    case requestGracefulTermination(resourceID: OwnedResourceID, leaseID: ResourceLeaseID)
    case detachBorrowed(resourceID: OwnedResourceID, leaseID: ResourceLeaseID)
}

enum SupervisorQuiescenceDecision: Equatable, Sendable {
    case issued(QuiescenceReceipt)
    case notDraining
    case resourcesRemain(Set<OwnedResourceID>)
    case failedReleasesRemain(Set<OwnedResourceID>)
    case queuedCleanupRemains(Set<ResourceLeaseID>)
}

/// The sole in-process owner registry for runtime handles. It is deliberately
/// adapter-neutral: controllers request typed leases and cannot erase ownership
/// by dropping a Task, PID, timer, capability, or power-assertion handle.
actor RuntimeSupervisor {
    let runID: KernelRunID

    private var phase: RuntimeSupervisorPhase = .accepting
    private var pressure: HostPressure
    private var budget: HostResourceBudget
    private var leasesByResource: [OwnedResourceID: RuntimeResourceLease] = [:]
    private var queuedByLeaseID: [ResourceLeaseID: QueuedRuntimeLease] = [:]
    private var releasedReceipts: [ResourceLeaseID: RuntimeReleaseReceipt] = [:]
    private var failedReleases: Set<OwnedResourceID> = []
    private var recoveryReceipt: RuntimeSupervisorRecoveryReceipt?

    init(
        runID: KernelRunID,
        budget: HostResourceBudget,
        pressure: HostPressure = .nominal
    ) {
        self.runID = runID
        self.budget = budget
        self.pressure = pressure
    }

    func updatePressure(_ pressure: HostPressure) {
        self.pressure = pressure
    }

    func updateBudget(_ budget: HostResourceBudget) {
        self.budget = budget
    }

    /// Rehydrates an otherwise pristine supervisor from a hash-chain-bound
    /// journal projection. Recovery retains every live or failed lease even if
    /// the current host budget is lower; admission policy may not erase debt.
    func restore(
        from snapshot: RuntimeSupervisorRecoverySnapshot
    ) -> RuntimeSupervisorRecoveryDecision {
        guard snapshot.runID == runID else {
            return .rejected(.runMismatch)
        }
        if let recoveryReceipt {
            let sameHead = recoveryReceipt.sourceSequence == snapshot.sourceSequence &&
                recoveryReceipt.sourceFrameDigest == snapshot.sourceFrameDigest
            return sameHead
                ? .restored(RuntimeSupervisorRecoveryReceipt(
                    runID: recoveryReceipt.runID,
                    sourceSequence: recoveryReceipt.sourceSequence,
                    sourceFrameDigest: recoveryReceipt.sourceFrameDigest,
                    phase: recoveryReceipt.phase,
                    liveResourceIDs: recoveryReceipt.liveResourceIDs,
                    failedReleases: recoveryReceipt.failedReleases,
                    duplicate: true
                ))
                : .rejected(.supervisorAlreadyMutated)
        }
        guard phase == .accepting,
              leasesByResource.isEmpty,
              queuedByLeaseID.isEmpty,
              releasedReceipts.isEmpty,
              failedReleases.isEmpty else {
            return .rejected(.supervisorAlreadyMutated)
        }

        let liveResourceIDs = Set(snapshot.liveLeases.map(\.request.resourceID))
        let liveLeaseIDs = Set(snapshot.liveLeases.map(\.request.leaseID))
        let releasedLeaseIDs = Set(snapshot.releasedReceipts.map(\.leaseID))
        guard liveResourceIDs.count == snapshot.liveLeases.count,
              liveLeaseIDs.count == snapshot.liveLeases.count,
              releasedLeaseIDs.count == snapshot.releasedReceipts.count,
              liveLeaseIDs.isDisjoint(with: releasedLeaseIDs),
              snapshot.failedReleases.isSubset(of: liveResourceIDs),
              snapshot.liveLeases.allSatisfy({ staticRequestIsValid($0.request) }),
              snapshot.releasedReceipts.allSatisfy({ receipt in
                  // A resource may be reacquired under a fresh lease after an
                  // earlier lease was durably released. Lease identity, not
                  // resource identity, distinguishes that valid history from
                  // a live/released contradiction.
                  receipt.runID == runID &&
                    !liveLeaseIDs.contains(receipt.leaseID)
              }) else {
            return .rejected(.invalidSnapshot)
        }

        phase = snapshot.phase
        leasesByResource = Dictionary(uniqueKeysWithValues: snapshot.liveLeases.map {
            ($0.request.resourceID, $0)
        })
        releasedReceipts = Dictionary(uniqueKeysWithValues: snapshot.releasedReceipts.map {
            ($0.leaseID, $0)
        })
        failedReleases = snapshot.failedReleases
        let receipt = RuntimeSupervisorRecoveryReceipt(
            runID: runID,
            sourceSequence: snapshot.sourceSequence,
            sourceFrameDigest: snapshot.sourceFrameDigest,
            phase: snapshot.phase,
            liveResourceIDs: liveResourceIDs,
            failedReleases: snapshot.failedReleases,
            duplicate: false
        )
        recoveryReceipt = receipt
        return .restored(receipt)
    }

    func acquire(_ request: RuntimeLeaseRequest) -> RuntimeAdmissionDecision {
        let decision = previewAdmissionDecision(request)
        if case .accepted(let lease, duplicate: false) = decision {
            leasesByResource[request.resourceID] = lease
            failedReleases.remove(request.resourceID)
        }
        return decision
    }

    func previewAdmissionReceipt(
        _ request: RuntimeLeaseRequest,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeAdmissionReceipt {
        let outcome: RuntimeAdmissionOutcome
        switch previewAdmissionDecision(request) {
        case .accepted(let lease, let duplicate):
            outcome = .accepted(lease, duplicate: duplicate)
        case .rejected(let rejection):
            outcome = .rejected(rejection)
        }
        return RuntimeAdmissionReceipt(
            id: receiptID,
            runID: runID,
            request: request,
            outcome: outcome,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
    }

    func applyAdmissionReceipt(_ receipt: RuntimeAdmissionReceipt) -> Bool {
        guard receipt.runID == runID, receipt.request.runID == runID else {
            return false
        }
        switch receipt.outcome {
        case .rejected:
            return true
        case .accepted(let lease, duplicate: true):
            return leasesByResource[receipt.request.resourceID] == lease
        case .accepted(let lease, duplicate: false):
            guard case .accepted(let previewed, duplicate: false) =
                    previewAdmissionDecision(receipt.request),
                  previewed == lease else {
                return false
            }
            leasesByResource[receipt.request.resourceID] = lease
            failedReleases.remove(receipt.request.resourceID)
            return true
        }
    }

    private func previewAdmissionDecision(
        _ request: RuntimeLeaseRequest
    ) -> RuntimeAdmissionDecision {
        guard request.runID == runID,
              request.reservation != .zero else {
            return .rejected(.invalidReservation)
        }
        if let existing = leasesByResource[request.resourceID] {
            if existing.request.leaseID == request.leaseID,
               existing.request == request {
                return .accepted(existing, duplicate: true)
            }
            return .rejected(.duplicateResource(existingLeaseID: existing.request.leaseID))
        }
        if case .draining = phase, request.purpose != .cleanup {
            return .rejected(.draining)
        }
        let effectivePressure = pressure.effectiveThermalState
        if request.purpose == .productive,
           effectivePressure == .serious || effectivePressure == .critical {
            return .rejected(.thermalDeferred(effectivePressure))
        }
        if request.kind == .powerAssertion {
            guard request.progressReceiptID != nil else {
                return .rejected(.powerLeaseMissingProgress)
            }
            guard request.purpose == .productive,
                  let deadline = request.renewalDeadlineMonotonicNanoseconds,
                  deadline > request.requestedAtMonotonicNanoseconds else {
                return .rejected(.invalidPowerLease)
            }
        }
        if request.ownership == .borrowed,
           request.externalIdentity?.stableDigest.rawValue.isEmpty != false ||
            request.releasePolicy != .detachOnly {
            return .rejected(.invalidOwnership)
        }
        if request.ownership == .owned,
           request.releasePolicy == .detachOnly {
            return .rejected(.invalidOwnership)
        }
        guard staticReleasePolicyIsValid(request) else {
            return .rejected(.invalidReleasePolicy)
        }
        let usage = currentUsage()
        let capacity = request.purpose == .cleanup
            ? budget.nominal
            : budget.effective(for: pressure)
        guard let projected = usage.adding(request.reservation),
              projected.fits(within: capacity) else {
            return .rejected(.budgetExceeded)
        }
        let lease = RuntimeResourceLease(
            request: request,
            admittedAtMonotonicNanoseconds: request.requestedAtMonotonicNanoseconds,
            lastProgressReceiptID: request.progressReceiptID
        )
        return .accepted(lease, duplicate: false)
    }

    func acquireReceipt(
        _ request: RuntimeLeaseRequest,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeAdmissionReceipt {
        let outcome: RuntimeAdmissionOutcome
        switch acquire(request) {
        case .accepted(let lease, let duplicate):
            outcome = .accepted(lease, duplicate: duplicate)
        case .rejected(let rejection):
            outcome = .rejected(rejection)
        }
        return RuntimeAdmissionReceipt(
            id: receiptID,
            runID: runID,
            request: request,
            outcome: outcome,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
    }

    func enqueue(
        _ request: RuntimeLeaseRequest,
        priority: UInt8,
        expiresAtMonotonicNanoseconds: UInt64
    ) -> RuntimeQueueDecision {
        guard staticRequestIsValid(request) else {
            return .rejected(.invalidRequest)
        }
        guard expiresAtMonotonicNanoseconds > request.requestedAtMonotonicNanoseconds else {
            return .rejected(.invalidDeadline)
        }
        if case .draining = phase, request.purpose != .cleanup {
            return .rejected(.draining)
        }
        if let live = leasesByResource[request.resourceID] {
            return .rejected(.duplicateResource(existingLeaseID: live.request.leaseID))
        }
        if let existing = queuedByLeaseID[request.leaseID] {
            let candidate = QueuedRuntimeLease(
                request: request,
                priority: priority,
                enqueuedAtMonotonicNanoseconds: request.requestedAtMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds: expiresAtMonotonicNanoseconds
            )
            return existing == candidate
                ? .queued(existing, duplicate: true)
                : .rejected(.duplicateLeaseConflict)
        }
        if let existing = queuedByLeaseID.values.first(where: {
            $0.request.resourceID == request.resourceID
        }) {
            return .rejected(.duplicateResource(existingLeaseID: existing.request.leaseID))
        }
        let queued = QueuedRuntimeLease(
            request: request,
            priority: priority,
            enqueuedAtMonotonicNanoseconds: request.requestedAtMonotonicNanoseconds,
            expiresAtMonotonicNanoseconds: expiresAtMonotonicNanoseconds
        )
        queuedByLeaseID[request.leaseID] = queued
        return .queued(queued, duplicate: false)
    }

    func cancelQueued(leaseID: ResourceLeaseID) -> Bool {
        queuedByLeaseID.removeValue(forKey: leaseID) != nil
    }

    func advanceQueue(atMonotonicNanoseconds now: UInt64) -> RuntimeQueueAdvance {
        let expired = Set(queuedByLeaseID.values.compactMap { queued in
            now > queued.expiresAtMonotonicNanoseconds ? queued.request.leaseID : nil
        })
        for leaseID in expired { queuedByLeaseID[leaseID] = nil }

        var admitted: RuntimeResourceLease?
        for queued in sortedQueue() {
            let decision = acquire(queued.request)
            switch decision {
            case .accepted(let lease, _):
                queuedByLeaseID[queued.request.leaseID] = nil
                admitted = lease
            case .rejected(.budgetExceeded), .rejected(.thermalDeferred):
                continue
            case .rejected:
                queuedByLeaseID[queued.request.leaseID] = nil
            }
            if admitted != nil { break }
        }
        return RuntimeQueueAdvance(
            expiredLeaseIDs: expired,
            admitted: admitted,
            remainingLeaseIDs: sortedQueue().map(\.request.leaseID)
        )
    }

    func bindExternalIdentity(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        identity: RuntimeExternalIdentity
    ) -> Bool {
        guard var lease = leasesByResource[resourceID],
              lease.request.leaseID == leaseID,
              !identity.stableDigest.rawValue.isEmpty else { return false }
        if let existing = lease.request.externalIdentity {
            return existing == identity
        }
        lease.request.externalIdentity = identity
        leasesByResource[resourceID] = lease
        return true
    }

    func bindExternalIdentityReceipt(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        identity: RuntimeExternalIdentity,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeExternalBindingReceipt {
        RuntimeExternalBindingReceipt(
            id: receiptID,
            runID: runID,
            resourceID: resourceID,
            leaseID: leaseID,
            identity: identity,
            accepted: bindExternalIdentity(
                resourceID: resourceID,
                leaseID: leaseID,
                identity: identity
            ),
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
    }

    func previewExternalIdentityReceipt(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        identity: RuntimeExternalIdentity,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeExternalBindingReceipt {
        let accepted: Bool
        if let lease = leasesByResource[resourceID],
           lease.request.leaseID == leaseID,
           !identity.stableDigest.rawValue.isEmpty {
            accepted = lease.request.externalIdentity == nil ||
                lease.request.externalIdentity == identity
        } else {
            accepted = false
        }
        return RuntimeExternalBindingReceipt(
            id: receiptID,
            runID: runID,
            resourceID: resourceID,
            leaseID: leaseID,
            identity: identity,
            accepted: accepted,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
    }

    func applyExternalIdentityReceipt(
        _ receipt: RuntimeExternalBindingReceipt
    ) -> Bool {
        guard receipt.runID == runID else { return false }
        if !receipt.accepted { return true }
        return bindExternalIdentity(
            resourceID: receipt.resourceID,
            leaseID: receipt.leaseID,
            identity: receipt.identity
        )
    }

    func renewPowerLease(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        progressReceiptID: ReceiptID,
        nowMonotonicNanoseconds: UInt64,
        renewalDeadlineMonotonicNanoseconds: UInt64
    ) -> Bool {
        guard var lease = leasesByResource[resourceID],
              lease.request.leaseID == leaseID,
              lease.request.kind == .powerAssertion,
              lease.lastProgressReceiptID != progressReceiptID,
              let priorDeadline = lease.request.renewalDeadlineMonotonicNanoseconds,
              nowMonotonicNanoseconds <= priorDeadline,
              renewalDeadlineMonotonicNanoseconds > nowMonotonicNanoseconds,
              pressure.effectiveThermalState != .serious,
              pressure.effectiveThermalState != .critical,
              case .accepting = phase else {
            return false
        }
        lease.lastProgressReceiptID = progressReceiptID
        lease.request.progressReceiptID = progressReceiptID
        lease.request.renewalDeadlineMonotonicNanoseconds = renewalDeadlineMonotonicNanoseconds
        leasesByResource[resourceID] = lease
        return true
    }

    func release(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        receiptID: ReceiptID,
        atMonotonicNanoseconds: UInt64
    ) -> RuntimeReleaseDecision {
        if var receipt = releasedReceipts[leaseID] {
            receipt.duplicate = true
            return .released(receipt)
        }
        guard let lease = leasesByResource[resourceID] else {
            return .rejected(.unknownResource)
        }
        guard lease.request.leaseID == leaseID else {
            return .rejected(.staleLease(
                expected: lease.request.leaseID,
                supplied: leaseID
            ))
        }
        leasesByResource[resourceID] = nil
        failedReleases.remove(resourceID)
        let receipt = RuntimeReleaseReceipt(
            id: receiptID,
            runID: runID,
            leaseID: leaseID,
            resourceID: resourceID,
            releasedAtMonotonicNanoseconds: atMonotonicNanoseconds,
            duplicate: false
        )
        releasedReceipts[leaseID] = receipt
        return .released(receipt)
    }

    func releaseOutcomeReceipt(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeReleaseOutcomeReceipt {
        let outcome: RuntimeReleaseOutcome
        let effectiveReceiptID: ReceiptID
        switch release(
            resourceID: resourceID,
            leaseID: leaseID,
            receiptID: receiptID,
            atMonotonicNanoseconds: observedAtMonotonicNanoseconds
        ) {
        case .released(let receipt):
            outcome = .released(receipt)
            effectiveReceiptID = receipt.id
        case .rejected(let rejection):
            outcome = .rejected(rejection)
            effectiveReceiptID = receiptID
        }
        return RuntimeReleaseOutcomeReceipt(
            id: effectiveReceiptID,
            runID: runID,
            resourceID: resourceID,
            leaseID: leaseID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds,
            outcome: outcome
        )
    }

    func previewReleaseOutcomeReceipt(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeReleaseOutcomeReceipt {
        let outcome: RuntimeReleaseOutcome
        let effectiveReceiptID: ReceiptID
        if var existing = releasedReceipts[leaseID] {
            existing.duplicate = true
            outcome = .released(existing)
            effectiveReceiptID = existing.id
        } else if let lease = leasesByResource[resourceID] {
            if lease.request.leaseID == leaseID {
                outcome = .released(RuntimeReleaseReceipt(
                    id: receiptID,
                    runID: runID,
                    leaseID: leaseID,
                    resourceID: resourceID,
                    releasedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds,
                    duplicate: false
                ))
                effectiveReceiptID = receiptID
            } else {
                outcome = .rejected(.staleLease(
                    expected: lease.request.leaseID,
                    supplied: leaseID
                ))
                effectiveReceiptID = receiptID
            }
        } else {
            outcome = .rejected(.unknownResource)
            effectiveReceiptID = receiptID
        }
        return RuntimeReleaseOutcomeReceipt(
            id: effectiveReceiptID,
            runID: runID,
            resourceID: resourceID,
            leaseID: leaseID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds,
            outcome: outcome
        )
    }

    func previewReleaseFailureReceipt(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        receiptID: ReceiptID,
        reasonDigest: ContentDigest,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeReleaseOutcomeReceipt {
        let outcome: RuntimeReleaseOutcome
        if let lease = leasesByResource[resourceID],
           lease.request.leaseID == leaseID,
           !reasonDigest.rawValue.isEmpty {
            outcome = .cleanupFailed(reasonDigest: reasonDigest)
        } else if let lease = leasesByResource[resourceID] {
            outcome = .rejected(.staleLease(
                expected: lease.request.leaseID,
                supplied: leaseID
            ))
        } else {
            outcome = .rejected(.unknownResource)
        }
        return RuntimeReleaseOutcomeReceipt(
            id: receiptID,
            runID: runID,
            resourceID: resourceID,
            leaseID: leaseID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds,
            outcome: outcome
        )
    }

    func applyReleaseOutcomeReceipt(
        _ receipt: RuntimeReleaseOutcomeReceipt
    ) -> Bool {
        guard receipt.runID == runID else { return false }
        switch receipt.outcome {
        case .released(let release):
            if let existing = releasedReceipts[receipt.leaseID] {
                return existing.id == release.id &&
                    existing.runID == release.runID &&
                    existing.resourceID == release.resourceID
            }
            guard let lease = leasesByResource[receipt.resourceID],
                  lease.request.leaseID == receipt.leaseID,
                  release.id == receipt.id,
                  release.runID == runID,
                  release.resourceID == receipt.resourceID,
                  release.leaseID == receipt.leaseID,
                  release.releasedAtMonotonicNanoseconds ==
                    receipt.observedAtMonotonicNanoseconds else {
                return false
            }
            leasesByResource[receipt.resourceID] = nil
            failedReleases.remove(receipt.resourceID)
            releasedReceipts[receipt.leaseID] = release
            return true
        case .cleanupFailed(let reasonDigest):
            guard let lease = leasesByResource[receipt.resourceID],
                  lease.request.leaseID == receipt.leaseID,
                  !reasonDigest.rawValue.isEmpty else {
                return false
            }
            failedReleases.insert(receipt.resourceID)
            return true
        case .rejected:
            return true
        }
    }

    func markReleaseFailed(resourceID: OwnedResourceID) {
        guard leasesByResource[resourceID] != nil else { return }
        failedReleases.insert(resourceID)
    }

    func markReleaseFailedReceipt(
        resourceID: OwnedResourceID,
        leaseID: ResourceLeaseID,
        receiptID: ReceiptID,
        reasonDigest: ContentDigest,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeReleaseOutcomeReceipt {
        let outcome: RuntimeReleaseOutcome
        if let lease = leasesByResource[resourceID],
           lease.request.leaseID == leaseID,
           !reasonDigest.rawValue.isEmpty {
            failedReleases.insert(resourceID)
            outcome = .cleanupFailed(reasonDigest: reasonDigest)
        } else if let lease = leasesByResource[resourceID] {
            outcome = .rejected(.staleLease(
                expected: lease.request.leaseID,
                supplied: leaseID
            ))
        } else {
            outcome = .rejected(.unknownResource)
        }
        return RuntimeReleaseOutcomeReceipt(
            id: receiptID,
            runID: runID,
            resourceID: resourceID,
            leaseID: leaseID,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds,
            outcome: outcome
        )
    }

    func beginDrain(_ intent: RuntimeDrainIntent) -> RuntimeDrainSnapshot {
        if case .draining(let existing) = phase, existing.priority > intent.priority {
            phase = .draining(existing)
        } else {
            phase = .draining(intent)
        }
        let cancelledQueuedLeaseIDs = Set(queuedByLeaseID.values.compactMap { queued in
            queued.request.purpose == .productive ? queued.request.leaseID : nil
        })
        queuedByLeaseID = queuedByLeaseID.filter { _, queued in
            queued.request.purpose == .cleanup
        }
        let effectiveIntent: RuntimeDrainIntent
        if case .draining(let retained) = phase {
            effectiveIntent = retained
        } else {
            preconditionFailure("beginDrain always enters a draining phase")
        }
        return RuntimeDrainSnapshot(
            intent: effectiveIntent,
            liveResourceIDs: Set(leasesByResource.keys),
            cancelledQueuedLeaseIDs: cancelledQueuedLeaseIDs
        )
    }

    func beginDrainReceipt(
        _ intent: RuntimeDrainIntent,
        receiptID: ReceiptID,
        observedAt: Date,
        observedAtMonotonicNanoseconds: UInt64
    ) -> RuntimeDrainReceipt {
        RuntimeDrainReceipt(
            id: receiptID,
            runID: runID,
            snapshot: beginDrain(intent),
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: observedAtMonotonicNanoseconds
        )
    }

    func cleanupPlan() -> [RuntimeCleanupAction] {
        leasesByResource.values.sorted {
            $0.request.resourceID.rawValue < $1.request.resourceID.rawValue
        }.map { lease in
            switch (lease.request.ownership, lease.request.releasePolicy) {
            case (.borrowed, _):
                return .detachBorrowed(
                    resourceID: lease.request.resourceID,
                    leaseID: lease.request.leaseID
                )
            case (.owned, .gracefulThenTerminate):
                return .requestGracefulTermination(
                    resourceID: lease.request.resourceID,
                    leaseID: lease.request.leaseID
                )
            case (.owned, .join):
                return .awaitJoin(
                    resourceID: lease.request.resourceID,
                    leaseID: lease.request.leaseID
                )
            case (.owned, .detachOnly):
                preconditionFailure("Owned detach-only requests are rejected at admission")
            }
        }
    }

    func powerLeasesRequiringRelease(
        atMonotonicNanoseconds now: UInt64
    ) -> Set<OwnedResourceID> {
        Set(leasesByResource.values.compactMap { lease in
            guard lease.request.kind == .powerAssertion else { return nil }
            let expired = lease.request.renewalDeadlineMonotonicNanoseconds.map {
                now > $0
            } ?? true
            let pressured = pressure.effectiveThermalState == .serious ||
                pressure.effectiveThermalState == .critical
            let draining: Bool
            if case .draining = phase { draining = true } else { draining = false }
            return expired || pressured || draining ? lease.request.resourceID : nil
        })
    }

    func quiescenceReceipt(
        id: ReceiptID,
        observedAt: Date,
        monotonicNanoseconds: UInt64
    ) -> SupervisorQuiescenceDecision {
        guard case .draining(let intent) = phase else { return .notDraining }
        guard failedReleases.isEmpty else {
            return .failedReleasesRemain(failedReleases)
        }
        let queued = Set(queuedByLeaseID.keys)
        guard queued.isEmpty else { return .queuedCleanupRemains(queued) }
        let live = Set(leasesByResource.keys)
        guard live.isEmpty else { return .resourcesRemain(live) }
        return .issued(QuiescenceReceipt(
            id: id,
            runID: runID,
            intent: intent,
            observedAt: observedAt,
            observedAtMonotonicNanoseconds: monotonicNanoseconds,
            liveResources: [],
            failedReleases: [],
            queuedLeaseIDs: []
        ))
    }

    func projection() -> RuntimeSupervisorProjection {
        RuntimeSupervisorProjection(
            phase: phase,
            pressure: pressure,
            capacity: budget.effective(for: pressure),
            usage: currentUsage(),
            liveLeases: leasesByResource.values.sorted {
                $0.request.resourceID.rawValue < $1.request.resourceID.rawValue
            },
            queuedLeases: sortedQueue(),
            failedReleases: failedReleases
        )
    }

    private func staticRequestIsValid(_ request: RuntimeLeaseRequest) -> Bool {
        guard request.runID == runID, request.reservation != .zero else { return false }
        if request.kind == .powerAssertion {
            guard request.progressReceiptID != nil,
                  request.purpose == .productive,
                  let deadline = request.renewalDeadlineMonotonicNanoseconds,
                  deadline > request.requestedAtMonotonicNanoseconds else {
                return false
            }
        }
        if request.ownership == .borrowed {
            return request.externalIdentity?.stableDigest.rawValue.isEmpty == false &&
                request.releasePolicy == .detachOnly
        }
        return request.releasePolicy != .detachOnly &&
            staticReleasePolicyIsValid(request)
    }

    /// Release policy is part of resource identity, not a caller preference.
    /// Process trees are the only resources for which the native adapter can
    /// prove graceful termination. Every non-process owned resource must be
    /// joined by its exact typed owner; treating it as a process would create
    /// a cleanup plan that no adapter can execute after a crash.
    private func staticReleasePolicyIsValid(
        _ request: RuntimeLeaseRequest
    ) -> Bool {
        switch request.ownership {
        case .borrowed:
            return request.releasePolicy == .detachOnly
        case .owned:
            if request.kind == .processTree {
                return request.releasePolicy == .gracefulThenTerminate
            }
            return request.releasePolicy == .join
        }
    }

    private func sortedQueue() -> [QueuedRuntimeLease] {
        queuedByLeaseID.values.sorted { lhs, rhs in
            if lhs.request.purpose != rhs.request.purpose {
                return lhs.request.purpose == .cleanup
            }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.enqueuedAtMonotonicNanoseconds != rhs.enqueuedAtMonotonicNanoseconds {
                return lhs.enqueuedAtMonotonicNanoseconds < rhs.enqueuedAtMonotonicNanoseconds
            }
            return lhs.request.leaseID.rawValue < rhs.request.leaseID.rawValue
        }
    }

    private func currentUsage() -> ResourceVector {
        leasesByResource.values.reduce(.zero) { partial, lease in
            partial.adding(lease.request.reservation) ?? ResourceVector(
                cpuWeight: UInt16.max,
                memoryBytes: UInt64.max,
                diskIOWeight: UInt16.max,
                gpuWeight: UInt16.max,
                networkWeight: UInt16.max,
                guiSessionCount: UInt16.max,
                processCount: UInt16.max
            )
        }
    }
}
