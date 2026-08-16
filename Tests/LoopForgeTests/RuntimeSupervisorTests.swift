import Foundation
import XCTest
@testable import LoopForge

final class RuntimeSupervisorTests: XCTestCase {
    private let runID = KernelRunID("runtime-run")

    func testLegacyExternalIdentityDecodesWithoutExplicitContentDigests() throws {
        let legacyJSON = Data(
            #"{"stableDigest":"legacy-stable","processID":42,"processStartMonotonicNanoseconds":7,"parentResourceID":"legacy-parent"}"#.utf8
        )

        let identity = try JSONDecoder().decode(RuntimeExternalIdentity.self, from: legacyJSON)

        XCTAssertEqual(identity.stableDigest, ContentDigest("legacy-stable"))
        XCTAssertEqual(identity.processID, 42)
        XCTAssertEqual(identity.processStartMonotonicNanoseconds, 7)
        XCTAssertEqual(identity.parentResourceID, OwnedResourceID("legacy-parent"))
        XCTAssertNil(identity.executableContentDigest)
        XCTAssertNil(identity.environmentContentDigest)
    }

    func testAdmissionReservesAllDimensionsAndRejectsOverflow() async {
        let supervisor = makeSupervisor(cpu: 100, memory: 1_000)
        let first = request("first", cpu: 60, memory: 600)
        let second = request("second", cpu: 50, memory: 100)

        XCTAssertAccepted(await supervisor.acquire(first), duplicate: false)
        let secondDecision = await supervisor.acquire(second)
        XCTAssertEqual(secondDecision, .rejected(.budgetExceeded))
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.usage.cpuWeight, 60)
        XCTAssertEqual(projection.usage.memoryBytes, 600)
        XCTAssertEqual(projection.liveLeases.count, 1)
    }

    func testIdempotentAcquireReturnsOriginalLease() async {
        let supervisor = makeSupervisor()
        let value = request("same", cpu: 5)
        XCTAssertAccepted(await supervisor.acquire(value), duplicate: false)
        XCTAssertAccepted(await supervisor.acquire(value), duplicate: true)
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.liveLeases.count, 1)
    }

    func testSameResourceWithDifferentLeaseIsRejected() async {
        let supervisor = makeSupervisor()
        let first = request("resource", cpu: 5)
        var second = first
        second.leaseID = ResourceLeaseID("new-lease")
        XCTAssertAccepted(await supervisor.acquire(first), duplicate: false)
        let secondDecision = await supervisor.acquire(second)
        XCTAssertEqual(
            secondDecision,
            .rejected(.duplicateResource(existingLeaseID: first.leaseID))
        )
    }

    func testFairAndLowPowerModesReduceHeavyCapacity() async {
        let supervisor = makeSupervisor(cpu: 100)
        await supervisor.updatePressure(HostPressure(
            thermalState: .fair,
            lowPowerMode: false,
            memoryPressureCritical: false
        ))
        let fairDecision = await supervisor.acquire(request("fair-heavy", cpu: 60))
        XCTAssertEqual(fairDecision, .rejected(.budgetExceeded))
        await supervisor.updatePressure(HostPressure(
            thermalState: .nominal,
            lowPowerMode: true,
            memoryPressureCritical: false
        ))
        let lowPowerDecision = await supervisor.acquire(request("low-power-heavy", cpu: 60))
        XCTAssertEqual(lowPowerDecision, .rejected(.budgetExceeded))
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.capacity.cpuWeight, 50)
    }

    func testSeriousPressureDefersProductiveWorkButAllowsBoundedCleanup() async {
        let supervisor = makeSupervisor(cpu: 100)
        XCTAssertAccepted(
            await supervisor.acquire(request("existing", cpu: 60)),
            duplicate: false
        )
        await supervisor.updatePressure(HostPressure(
            thermalState: .serious,
            lowPowerMode: false,
            memoryPressureCritical: false
        ))
        let productiveDecision = await supervisor.acquire(request("productive", cpu: 1))
        XCTAssertEqual(productiveDecision, .rejected(.thermalDeferred(.serious)))
        XCTAssertAccepted(
            await supervisor.acquire(request("cleanup", cpu: 5, purpose: .cleanup)),
            duplicate: false
        )
    }

    func testReducedBudgetNeverExpandsAZeroDimension() async {
        let supervisor = RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 10,
                memoryBytes: 100,
                diskIOWeight: 0,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 1
            )),
            pressure: HostPressure(
                thermalState: .fair,
                lowPowerMode: false,
                memoryPressureCritical: false
            )
        )
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.capacity.diskIOWeight, 0)
        XCTAssertEqual(projection.capacity.gpuWeight, 0)
        XCTAssertEqual(projection.capacity.networkWeight, 0)
    }

    func testMemoryPressureCriticalUsesCleanupOnlyPolicy() async {
        let supervisor = makeSupervisor(cpu: 100)
        await supervisor.updatePressure(HostPressure(
            thermalState: .nominal,
            lowPowerMode: false,
            memoryPressureCritical: true
        ))
        let decision = await supervisor.acquire(request("productive", cpu: 1))
        XCTAssertEqual(decision, .rejected(.thermalDeferred(.critical)))
    }

    func testDrainRejectsNewProductiveLeaseAndRetainsOwnership() async {
        let supervisor = makeSupervisor()
        let lease = request("owned", cpu: 5)
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        let drain = await supervisor.beginDrain(.stop)
        XCTAssertEqual(drain.liveResourceIDs, [lease.resourceID])
        let lateDecision = await supervisor.acquire(request("late", cpu: 1))
        XCTAssertEqual(lateDecision, .rejected(.draining))
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.liveLeases.count, 1)
    }

    func testDrainIntentCanEscalateButCannotDowngrade() async {
        let supervisor = makeSupervisor()
        _ = await supervisor.beginDrain(.stop)
        _ = await supervisor.beginDrain(.pause)
        let afterDowngrade = await supervisor.projection()
        XCTAssertEqual(afterDowngrade.phase, .draining(.stop))
        _ = await supervisor.beginDrain(.quit)
        let afterEscalation = await supervisor.projection()
        XCTAssertEqual(afterEscalation.phase, .draining(.quit))
    }

    func testRestoreRehydratesJournalBoundOwnershipAndIsHeadIdempotent() async {
        let supervisor = makeSupervisor()
        let liveRequest = request("restored-live", cpu: 5)
        let lease = RuntimeResourceLease(
            request: liveRequest,
            admittedAtMonotonicNanoseconds: 2,
            lastProgressReceiptID: nil
        )
        let released = RuntimeReleaseReceipt(
            id: ReceiptID("restored-release"),
            runID: runID,
            leaseID: ResourceLeaseID("lease-restored-old"),
            resourceID: OwnedResourceID("resource-restored-old"),
            releasedAtMonotonicNanoseconds: 3,
            duplicate: false
        )
        let snapshot = RuntimeSupervisorRecoverySnapshot(
            runID: runID,
            sourceSequence: 42,
            sourceFrameDigest: ContentDigest("journal-head-42"),
            phase: .draining(.stop),
            liveLeases: [lease],
            releasedReceipts: [released],
            failedReleases: [liveRequest.resourceID]
        )

        guard case .restored(let receipt) = await supervisor.restore(from: snapshot) else {
            return XCTFail("Expected supervisor recovery")
        }
        XCTAssertFalse(receipt.duplicate)
        XCTAssertEqual(receipt.sourceSequence, 42)
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.phase, .draining(.stop))
        XCTAssertEqual(projection.liveLeases, [lease])
        XCTAssertEqual(projection.failedReleases, [liveRequest.resourceID])
        XCTAssertEqual(projection.usage, liveRequest.reservation)
        let lateDecision = await supervisor.acquire(request("late-after-restore", cpu: 1))
        XCTAssertEqual(lateDecision, .rejected(.draining))

        guard case .restored(let duplicate) = await supervisor.restore(from: snapshot) else {
            return XCTFail("Expected idempotent recovery receipt")
        }
        XCTAssertTrue(duplicate.duplicate)
        var differentHead = snapshot
        differentHead.sourceSequence = 43
        let differentHeadDecision = await supervisor.restore(from: differentHead)
        XCTAssertEqual(differentHeadDecision, .rejected(.supervisorAlreadyMutated))
    }

    func testRestoreAllowsResourceReacquisitionAfterDistinctLeaseRelease()
        async {
        let supervisor = makeSupervisor()
        var liveRequest = request("reacquired-resource", cpu: 5)
        liveRequest.leaseID = ResourceLeaseID("lease-reacquired-new")
        let liveLease = RuntimeResourceLease(
            request: liveRequest,
            admittedAtMonotonicNanoseconds: 4,
            lastProgressReceiptID: nil
        )
        let earlierRelease = RuntimeReleaseReceipt(
            id: ReceiptID("release-reacquired-old"),
            runID: runID,
            leaseID: ResourceLeaseID("lease-reacquired-old"),
            resourceID: liveRequest.resourceID,
            releasedAtMonotonicNanoseconds: 3,
            duplicate: false
        )
        let decision = await supervisor.restore(from:
            RuntimeSupervisorRecoverySnapshot(
                runID: runID,
                sourceSequence: 43,
                sourceFrameDigest: ContentDigest("journal-head-43"),
                phase: .accepting,
                liveLeases: [liveLease],
                releasedReceipts: [earlierRelease],
                failedReleases: []
            )
        )

        guard case .restored(let receipt) = decision else {
            return XCTFail(
                "a fresh lease may reacquire a durably released resource"
            )
        }
        XCTAssertEqual(receipt.liveResourceIDs, [liveRequest.resourceID])
        let projection = await supervisor.projection()
        XCTAssertEqual(
            projection.liveLeases,
            [liveLease]
        )
    }

    func testRestoreRejectsRunMismatchInvalidSnapshotAndLiveOverwrite() async {
        let fresh = makeSupervisor()
        var wrongRun = RuntimeSupervisorRecoverySnapshot(
            runID: KernelRunID("wrong-run"),
            sourceSequence: 1,
            sourceFrameDigest: nil,
            phase: .accepting,
            liveLeases: [],
            releasedReceipts: [],
            failedReleases: []
        )
        let wrongRunDecision = await fresh.restore(from: wrongRun)
        XCTAssertEqual(wrongRunDecision, .rejected(.runMismatch))

        let value = request("invalid-restore", cpu: 1)
        let lease = RuntimeResourceLease(
            request: value,
            admittedAtMonotonicNanoseconds: 2,
            lastProgressReceiptID: nil
        )
        wrongRun.runID = runID
        wrongRun.liveLeases = [lease, lease]
        let invalidDecision = await fresh.restore(from: wrongRun)
        XCTAssertEqual(invalidDecision, .rejected(.invalidSnapshot))

        let mutated = makeSupervisor()
        XCTAssertAccepted(await mutated.acquire(value), duplicate: false)
        wrongRun.liveLeases = []
        let mutatedDecision = await mutated.restore(from: wrongRun)
        XCTAssertEqual(mutatedDecision, .rejected(.supervisorAlreadyMutated))
    }

    func testStaleReleaseTokenCannotEraseOwnership() async {
        let supervisor = makeSupervisor()
        let lease = request("owned", cpu: 5)
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        let result = await supervisor.release(
            resourceID: lease.resourceID,
            leaseID: ResourceLeaseID("stale"),
            receiptID: ReceiptID("release"),
            atMonotonicNanoseconds: 2
        )
        XCTAssertEqual(
            result,
            .rejected(.staleLease(expected: lease.leaseID, supplied: ResourceLeaseID("stale")))
        )
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.liveLeases.count, 1)
    }

    func testReleaseIsIdempotentAndFreesBudgetOnce() async {
        let supervisor = makeSupervisor()
        let lease = request("owned", cpu: 5)
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        let first = await supervisor.release(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            receiptID: ReceiptID("release"),
            atMonotonicNanoseconds: 2
        )
        let duplicate = await supervisor.release(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            receiptID: ReceiptID("different"),
            atMonotonicNanoseconds: 3
        )
        guard case .released(let firstReceipt) = first,
              case .released(let duplicateReceipt) = duplicate else {
            return XCTFail("Both release commands must return receipts")
        }
        XCTAssertFalse(firstReceipt.duplicate)
        XCTAssertTrue(duplicateReceipt.duplicate)
        XCTAssertEqual(firstReceipt.id, duplicateReceipt.id)
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.usage, .zero)
    }

    func testReleaseOutcomeReplayRetainsTheOriginalReceiptIdentity() async {
        let supervisor = makeSupervisor()
        let lease = request("release-outcome", cpu: 1)
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        let first = await supervisor.releaseOutcomeReceipt(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            receiptID: ReceiptID("original-release"),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )
        let duplicate = await supervisor.releaseOutcomeReceipt(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            receiptID: ReceiptID("replacement-release"),
            observedAt: Date(timeIntervalSince1970: 3),
            observedAtMonotonicNanoseconds: 3
        )
        XCTAssertEqual(first.id, ReceiptID("original-release"))
        XCTAssertEqual(duplicate.id, first.id)
        guard case .released(let duplicateRelease) = duplicate.outcome else {
            return XCTFail("The duplicate must return the original release receipt")
        }
        XCTAssertTrue(duplicateRelease.duplicate)
        XCTAssertEqual(duplicateRelease.id, first.id)
    }

    func testQuiescenceRequiresDrainAndEmptyOwnership() async {
        let supervisor = makeSupervisor()
        let lease = request("owned", cpu: 5)
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        let beforeDrain = await supervisor.quiescenceReceipt(
            id: ReceiptID("quiet"),
            observedAt: Date(timeIntervalSince1970: 1),
            monotonicNanoseconds: 1
        )
        XCTAssertEqual(beforeDrain, .notDraining)
        _ = await supervisor.beginDrain(.pause)
        let beforeRelease = await supervisor.quiescenceReceipt(
            id: ReceiptID("quiet"),
            observedAt: Date(timeIntervalSince1970: 1),
            monotonicNanoseconds: 1
        )
        XCTAssertEqual(beforeRelease, .resourcesRemain([lease.resourceID]))
        _ = await supervisor.release(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            receiptID: ReceiptID("release"),
            atMonotonicNanoseconds: 2
        )
        guard case .issued(let receipt) = await supervisor.quiescenceReceipt(
            id: ReceiptID("quiet"),
            observedAt: Date(timeIntervalSince1970: 2),
            monotonicNanoseconds: 2
        ) else {
            return XCTFail("An empty drained supervisor must issue quiescence")
        }
        XCTAssertTrue(receipt.provesQuiescence)
        XCTAssertEqual(receipt.liveResources, [])
        XCTAssertEqual(receipt.intent, .pause)
    }

    func testFailedReleaseRemainsVisibleAndBlocksQuiescence() async {
        let supervisor = makeSupervisor()
        let lease = request("failed-release", cpu: 5)
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        _ = await supervisor.beginDrain(.quit)
        await supervisor.markReleaseFailed(resourceID: lease.resourceID)
        let decision = await supervisor.quiescenceReceipt(
            id: ReceiptID("quiet"),
            observedAt: Date(timeIntervalSince1970: 2),
            monotonicNanoseconds: 2
        )
        XCTAssertEqual(decision, .failedReleasesRemain([lease.resourceID]))
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.failedReleases, [lease.resourceID])
    }

    func testPowerLeaseRequiresNovelReceiptBackedRenewal() async {
        let supervisor = makeSupervisor()
        let initialProgress = ReceiptID("progress-1")
        var power = request("power", cpu: 1, kind: .powerAssertion)
        let missingProgress = await supervisor.acquire(power)
        XCTAssertEqual(missingProgress, .rejected(.powerLeaseMissingProgress))
        power.progressReceiptID = initialProgress
        let missingDeadline = await supervisor.acquire(power)
        XCTAssertEqual(missingDeadline, .rejected(.invalidPowerLease))
        power.renewalDeadlineMonotonicNanoseconds = 100
        XCTAssertAccepted(await supervisor.acquire(power), duplicate: false)
        let duplicateProgress = await supervisor.renewPowerLease(
            resourceID: power.resourceID,
            leaseID: power.leaseID,
            progressReceiptID: initialProgress,
            nowMonotonicNanoseconds: 50,
            renewalDeadlineMonotonicNanoseconds: 110
        )
        XCTAssertFalse(duplicateProgress)
        let renewed = await supervisor.renewPowerLease(
            resourceID: power.resourceID,
            leaseID: power.leaseID,
            progressReceiptID: ReceiptID("progress-2"),
            nowMonotonicNanoseconds: 50,
            renewalDeadlineMonotonicNanoseconds: 110
        )
        XCTAssertTrue(renewed)
        let expired = await supervisor.renewPowerLease(
            resourceID: power.resourceID,
            leaseID: power.leaseID,
            progressReceiptID: ReceiptID("progress-3"),
            nowMonotonicNanoseconds: 111,
            renewalDeadlineMonotonicNanoseconds: 120
        )
        XCTAssertFalse(expired)
    }

    func testBorrowedResourceRequiresIdentityAndDetachOnlyPolicy() async {
        let supervisor = makeSupervisor()
        var borrowed = request("borrowed", cpu: 1)
        borrowed.ownership = .borrowed
        let missingIdentity = await supervisor.acquire(borrowed)
        XCTAssertEqual(missingIdentity, .rejected(.invalidOwnership))

        borrowed.externalIdentity = externalIdentity("borrowed")
        let destructive = await supervisor.acquire(borrowed)
        XCTAssertEqual(destructive, .rejected(.invalidOwnership))

        borrowed.releasePolicy = .detachOnly
        XCTAssertAccepted(await supervisor.acquire(borrowed), duplicate: false)
        let plan = await supervisor.cleanupPlan()
        XCTAssertEqual(
            plan,
            [.detachBorrowed(resourceID: borrowed.resourceID, leaseID: borrowed.leaseID)]
        )
    }

    func testBorrowedResourceRejectsEmptyStableIdentity() async {
        let supervisor = makeSupervisor()
        var borrowed = request("empty-identity", cpu: 1)
        borrowed.ownership = .borrowed
        borrowed.releasePolicy = .detachOnly
        borrowed.externalIdentity = externalIdentity("")
        let result = await supervisor.acquire(borrowed)
        XCTAssertEqual(result, .rejected(.invalidOwnership))
    }

    func testCleanupCannotAcquireANewPowerAssertion() async {
        let supervisor = makeSupervisor()
        var power = request(
            "cleanup-power",
            cpu: 1,
            kind: .powerAssertion,
            purpose: .cleanup
        )
        power.progressReceiptID = ReceiptID("progress")
        power.renewalDeadlineMonotonicNanoseconds = 100
        let result = await supervisor.acquire(power)
        XCTAssertEqual(result, .rejected(.invalidPowerLease))
    }

    func testOwnedResourceCannotUseDetachOnlyPolicy() async {
        let supervisor = makeSupervisor()
        var owned = request("owned-detach", cpu: 1)
        owned.releasePolicy = .detachOnly
        let result = await supervisor.acquire(owned)
        XCTAssertEqual(result, .rejected(.invalidOwnership))
    }

    func testProcessTreeCannotEnterJoinOnlyCleanupPlan() async {
        let supervisor = makeSupervisor()
        let process = request("process-join", cpu: 1, kind: .processTree)

        let result = await supervisor.acquire(process)
        let cleanupPlan = await supervisor.cleanupPlan()

        XCTAssertEqual(result, .rejected(.invalidReleasePolicy))
        XCTAssertTrue(cleanupPlan.isEmpty)
    }

    func testRecoveryRejectsHistoricalProcessJoinLease() async {
        let supervisor = makeSupervisor()
        let process = request("recovered-process-join", cpu: 1, kind: .processTree)
        let lease = RuntimeResourceLease(
            request: process,
            admittedAtMonotonicNanoseconds: 2,
            lastProgressReceiptID: nil
        )
        let snapshot = RuntimeSupervisorRecoverySnapshot(
            runID: runID,
            sourceSequence: 1,
            sourceFrameDigest: ContentDigest("frame"),
            phase: .draining(.stop),
            liveLeases: [lease],
            releasedReceipts: [],
            failedReleases: []
        )

        let result = await supervisor.restore(from: snapshot)
        let projection = await supervisor.projection()

        XCTAssertEqual(result, .rejected(.invalidSnapshot))
        XCTAssertTrue(projection.liveLeases.isEmpty)
    }

    func testNonProcessCannotMasqueradeAsGracefullyTerminable() async {
        let supervisor = makeSupervisor()
        var task = request("task-terminate", cpu: 1, kind: .asyncTask)
        task.releasePolicy = .gracefulThenTerminate

        let result = await supervisor.acquire(task)
        let cleanupPlan = await supervisor.cleanupPlan()

        XCTAssertEqual(result, .rejected(.invalidReleasePolicy))
        XCTAssertTrue(cleanupPlan.isEmpty)
    }

    func testExternalIdentityBindsOnceAndRejectsPIDReuse() async {
        let supervisor = makeSupervisor()
        var lease = request("process", cpu: 1, kind: .processTree)
        lease.releasePolicy = .gracefulThenTerminate
        XCTAssertAccepted(await supervisor.acquire(lease), duplicate: false)
        let original = externalIdentity("process", pid: 42, start: 100)
        let reusedPID = externalIdentity("process-new", pid: 42, start: 200)
        let firstBinding = await supervisor.bindExternalIdentity(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            identity: original
        )
        XCTAssertTrue(firstBinding)
        let duplicateBinding = await supervisor.bindExternalIdentity(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            identity: original
        )
        XCTAssertTrue(duplicateBinding)
        let reusedBinding = await supervisor.bindExternalIdentity(
            resourceID: lease.resourceID,
            leaseID: lease.leaseID,
            identity: reusedPID
        )
        XCTAssertFalse(reusedBinding)
    }

    func testCleanupPlanDistinguishesJoinTerminateAndBorrowedDetach() async {
        let supervisor = makeSupervisor()
        let join = request("join", cpu: 1)
        var terminate = request("terminate", cpu: 1, kind: .processTree)
        terminate.releasePolicy = .gracefulThenTerminate
        var borrowed = request("borrowed-plan", cpu: 1)
        borrowed.ownership = .borrowed
        borrowed.releasePolicy = .detachOnly
        borrowed.externalIdentity = externalIdentity("borrowed-plan")
        XCTAssertAccepted(await supervisor.acquire(join), duplicate: false)
        XCTAssertAccepted(await supervisor.acquire(terminate), duplicate: false)
        XCTAssertAccepted(await supervisor.acquire(borrowed), duplicate: false)
        let plan = await supervisor.cleanupPlan()
        XCTAssertEqual(plan, [
            .detachBorrowed(resourceID: borrowed.resourceID, leaseID: borrowed.leaseID),
            .awaitJoin(resourceID: join.resourceID, leaseID: join.leaseID),
            .requestGracefulTermination(
                resourceID: terminate.resourceID,
                leaseID: terminate.leaseID
            )
        ])
    }

    func testPowerLeaseReleaseBecomesRequiredOnExpiryPressureOrDrain() async {
        let supervisor = makeSupervisor()
        var power = request("power-release", cpu: 1, kind: .powerAssertion)
        power.progressReceiptID = ReceiptID("progress")
        power.renewalDeadlineMonotonicNanoseconds = 100
        XCTAssertAccepted(await supervisor.acquire(power), duplicate: false)
        let active = await supervisor.powerLeasesRequiringRelease(
            atMonotonicNanoseconds: 100
        )
        XCTAssertEqual(active, [])
        let expired = await supervisor.powerLeasesRequiringRelease(
            atMonotonicNanoseconds: 101
        )
        XCTAssertEqual(expired, [power.resourceID])

        await supervisor.updatePressure(HostPressure(
            thermalState: .serious,
            lowPowerMode: false,
            memoryPressureCritical: false
        ))
        let pressured = await supervisor.powerLeasesRequiringRelease(
            atMonotonicNanoseconds: 50
        )
        XCTAssertEqual(pressured, [power.resourceID])
        await supervisor.updatePressure(.nominal)
        _ = await supervisor.beginDrain(.stop)
        let draining = await supervisor.powerLeasesRequiringRelease(
            atMonotonicNanoseconds: 50
        )
        XCTAssertEqual(draining, [power.resourceID])
    }

    func testZeroReservationAndWrongRunFailClosed() async {
        let supervisor = makeSupervisor()
        var zero = request("zero", cpu: 0)
        zero.reservation = .zero
        let zeroDecision = await supervisor.acquire(zero)
        XCTAssertEqual(zeroDecision, .rejected(.invalidReservation))
        var wrongRun = request("wrong-run", cpu: 1)
        wrongRun.runID = KernelRunID("other")
        let wrongRunDecision = await supervisor.acquire(wrongRun)
        XCTAssertEqual(wrongRunDecision, .rejected(.invalidReservation))
    }

    func testQueueIsIdempotentAndVisibleInProjection() async {
        let supervisor = makeSupervisor()
        let queued = request("queued", cpu: 5)
        let first = await supervisor.enqueue(queued, priority: 2, expiresAtMonotonicNanoseconds: 10)
        let duplicate = await supervisor.enqueue(queued, priority: 2, expiresAtMonotonicNanoseconds: 10)
        guard case .queued(_, duplicate: false) = first,
              case .queued(_, duplicate: true) = duplicate else {
            return XCTFail("The same queue command must be idempotent")
        }
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.queuedLeases.map(\.request.leaseID), [queued.leaseID])
    }

    func testQueueRejectsConflictingLeaseAndResourceIdentity() async {
        let supervisor = makeSupervisor()
        let first = request("first-queue", cpu: 5)
        _ = await supervisor.enqueue(first, priority: 1, expiresAtMonotonicNanoseconds: 10)
        var leaseConflict = first
        leaseConflict.resourceID = OwnedResourceID("different")
        let conflictingLease = await supervisor.enqueue(
            leaseConflict,
            priority: 1,
            expiresAtMonotonicNanoseconds: 10
        )
        XCTAssertEqual(conflictingLease, .rejected(.duplicateLeaseConflict))

        var resourceConflict = request("other-queue", cpu: 5)
        resourceConflict.resourceID = first.resourceID
        let conflictingResource = await supervisor.enqueue(
            resourceConflict,
            priority: 1,
            expiresAtMonotonicNanoseconds: 10
        )
        XCTAssertEqual(
            conflictingResource,
            .rejected(.duplicateResource(existingLeaseID: first.leaseID))
        )
    }

    func testQueueRejectsExpiredDeadlineAtAdmission() async {
        let supervisor = makeSupervisor()
        let value = request("bad-deadline", cpu: 1)
        let result = await supervisor.enqueue(
            value,
            priority: 1,
            expiresAtMonotonicNanoseconds: value.requestedAtMonotonicNanoseconds
        )
        XCTAssertEqual(result, .rejected(.invalidDeadline))
    }

    func testQueueExpiresWithoutCreatingALease() async {
        let supervisor = makeSupervisor()
        let value = request("expires", cpu: 1)
        _ = await supervisor.enqueue(value, priority: 1, expiresAtMonotonicNanoseconds: 5)
        let advance = await supervisor.advanceQueue(atMonotonicNanoseconds: 6)
        XCTAssertEqual(advance.expiredLeaseIDs, [value.leaseID])
        XCTAssertNil(advance.admitted)
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.liveLeases, [])
    }

    func testQueueUsesCleanupThenPriorityThenStableFIFOOrdering() async {
        let supervisor = makeSupervisor()
        var low = request("low", cpu: 1)
        low.requestedAtMonotonicNanoseconds = 2
        var high = request("high", cpu: 1)
        high.requestedAtMonotonicNanoseconds = 3
        var cleanup = request("cleanup-priority", cpu: 1, purpose: .cleanup)
        cleanup.requestedAtMonotonicNanoseconds = 4
        _ = await supervisor.enqueue(low, priority: 1, expiresAtMonotonicNanoseconds: 20)
        _ = await supervisor.enqueue(high, priority: 9, expiresAtMonotonicNanoseconds: 20)
        _ = await supervisor.enqueue(cleanup, priority: 0, expiresAtMonotonicNanoseconds: 20)
        let first = await supervisor.advanceQueue(atMonotonicNanoseconds: 5)
        XCTAssertEqual(first.admitted?.request.leaseID, cleanup.leaseID)
        let second = await supervisor.advanceQueue(atMonotonicNanoseconds: 6)
        XCTAssertEqual(second.admitted?.request.leaseID, high.leaseID)
        let third = await supervisor.advanceQueue(atMonotonicNanoseconds: 7)
        XCTAssertEqual(third.admitted?.request.leaseID, low.leaseID)
    }

    func testQueueCanBypassOversizedHeadWithAnAdmissibleSmallRequest() async {
        let supervisor = makeSupervisor(cpu: 100)
        XCTAssertAccepted(await supervisor.acquire(request("existing-90", cpu: 90)), duplicate: false)
        let tooLarge = request("too-large", cpu: 20)
        let small = request("small", cpu: 5)
        _ = await supervisor.enqueue(tooLarge, priority: 9, expiresAtMonotonicNanoseconds: 20)
        _ = await supervisor.enqueue(small, priority: 1, expiresAtMonotonicNanoseconds: 20)
        let advance = await supervisor.advanceQueue(atMonotonicNanoseconds: 2)
        XCTAssertEqual(advance.admitted?.request.leaseID, small.leaseID)
        XCTAssertEqual(advance.remainingLeaseIDs, [tooLarge.leaseID])
    }

    func testQueuedRequestWaitsThroughThermalPressureThenAdmits() async {
        let supervisor = makeSupervisor(cpu: 100)
        let value = request("thermal-wait", cpu: 5)
        _ = await supervisor.enqueue(value, priority: 1, expiresAtMonotonicNanoseconds: 20)
        await supervisor.updatePressure(HostPressure(
            thermalState: .serious,
            lowPowerMode: false,
            memoryPressureCritical: false
        ))
        let deferred = await supervisor.advanceQueue(atMonotonicNanoseconds: 2)
        XCTAssertNil(deferred.admitted)
        XCTAssertEqual(deferred.remainingLeaseIDs, [value.leaseID])
        await supervisor.updatePressure(.nominal)
        let admitted = await supervisor.advanceQueue(atMonotonicNanoseconds: 3)
        XCTAssertEqual(admitted.admitted?.request.leaseID, value.leaseID)
    }

    func testQueuedCancellationIsExplicitAndIdempotent() async {
        let supervisor = makeSupervisor()
        let value = request("cancel-queue", cpu: 5)
        _ = await supervisor.enqueue(value, priority: 1, expiresAtMonotonicNanoseconds: 20)
        let cancelled = await supervisor.cancelQueued(leaseID: value.leaseID)
        let duplicate = await supervisor.cancelQueued(leaseID: value.leaseID)
        XCTAssertTrue(cancelled)
        XCTAssertFalse(duplicate)
        let advance = await supervisor.advanceQueue(atMonotonicNanoseconds: 2)
        XCTAssertNil(advance.admitted)
    }

    func testDrainDropsProductiveQueueButRetainsCleanupQueue() async {
        let supervisor = makeSupervisor()
        let productive = request("queued-productive", cpu: 1)
        let cleanup = request("queued-cleanup", cpu: 1, purpose: .cleanup)
        _ = await supervisor.enqueue(productive, priority: 9, expiresAtMonotonicNanoseconds: 20)
        _ = await supervisor.enqueue(cleanup, priority: 1, expiresAtMonotonicNanoseconds: 20)
        let drain = await supervisor.beginDrain(.stop)
        XCTAssertEqual(drain.cancelledQueuedLeaseIDs, [productive.leaseID])
        let projection = await supervisor.projection()
        XCTAssertEqual(projection.queuedLeases.map(\.request.leaseID), [cleanup.leaseID])
        let beforeCleanup = await supervisor.quiescenceReceipt(
            id: ReceiptID("premature-quiet"),
            observedAt: Date(timeIntervalSince1970: 2),
            monotonicNanoseconds: 2
        )
        XCTAssertEqual(beforeCleanup, .queuedCleanupRemains([cleanup.leaseID]))
        let advance = await supervisor.advanceQueue(atMonotonicNanoseconds: 2)
        XCTAssertEqual(advance.admitted?.request.leaseID, cleanup.leaseID)
    }

    private func makeSupervisor(
        cpu: UInt16 = 100,
        memory: UInt64 = 10_000
    ) -> RuntimeSupervisor {
        RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: cpu,
                memoryBytes: memory,
                diskIOWeight: 100,
                gpuWeight: 100,
                networkWeight: 100,
                guiSessionCount: 2,
                processCount: 20
            ))
        )
    }

    private func request(
        _ id: String,
        cpu: UInt16,
        memory: UInt64 = 1,
        kind: RuntimeResourceKind = .asyncTask,
        purpose: ResourcePurpose = .productive
    ) -> RuntimeLeaseRequest {
        RuntimeLeaseRequest(
            leaseID: ResourceLeaseID("lease-\(id)"),
            resourceID: OwnedResourceID("resource-\(id)"),
            runID: runID,
            occurrenceID: OccurrenceID("occurrence-\(id)"),
            attemptID: AttemptID("attempt-\(id)"),
            kind: kind,
            purpose: purpose,
            ownership: .owned,
            releasePolicy: .join,
            externalIdentity: nil,
            reservation: ResourceVector(
                cpuWeight: cpu,
                memoryBytes: memory,
                diskIOWeight: 1,
                gpuWeight: 0,
                networkWeight: 1,
                guiSessionCount: 0,
                processCount: 1
            ),
            requestedAtMonotonicNanoseconds: 1,
            renewalDeadlineMonotonicNanoseconds: nil,
            progressReceiptID: nil
        )
    }

    private func externalIdentity(
        _ digest: String,
        pid: Int32? = nil,
        start: UInt64? = nil
    ) -> RuntimeExternalIdentity {
        RuntimeExternalIdentity(
            stableDigest: ContentDigest(digest),
            processID: pid,
            processStartMonotonicNanoseconds: start,
            parentResourceID: nil
        )
    }

    private func XCTAssertAccepted(
        _ decision: RuntimeAdmissionDecision,
        duplicate: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .accepted(_, let actualDuplicate) = decision else {
            return XCTFail("Expected an accepted lease, got \(decision)", file: file, line: line)
        }
        XCTAssertEqual(actualDuplicate, duplicate, file: file, line: line)
    }
}
