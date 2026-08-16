import Foundation
import XCTest
@testable import LoopForge

final class RuntimeJournalIntegrationTests: XCTestCase {
    private let runID = KernelRunID("runtime-journal-run")
    private let actor = ActorIdentity(
        id: ActorID("runtime-owner"),
        role: "runtime-owner",
        lineageDigest: ContentDigest("runtime-owner-lineage")
    )

    func testJournaledLifecycleAuthorityOwnsDrainAndQuiescenceFacts() async throws {
        let root = temporaryDirectory("lifecycle-authority")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        let supervisor = makeSupervisor()
        _ = try await journal.transact(
            .createRun(contract()),
            context: context("create-authority", sequence: 0)
        )
        let authority = JournaledRuntimeLifecycleAuthority(
            supervisor: supervisor,
            journal: journal,
            actorIdentity: actor
        )

        let drain = try await authority.requestDrain(
            JournaledRuntimeDrainRequest(
                intent: .stop,
                lifecycleCommandID: RunCommandID("request-stop-authority"),
                drainReceiptID: ReceiptID("drain-authority"),
                drainCommandID: RunCommandID("record-drain-authority")
            )
        )
        XCTAssertEqual(drain.drain.snapshot.intent, .stop)
        XCTAssertTrue(drain.drain.snapshot.liveResourceIDs.isEmpty)
        XCTAssertTrue(drain.cleanupPlan.isEmpty)

        let quiet = try await authority.recordQuiescence(
            JournaledRuntimeQuiescenceRequest(
                receiptID: ReceiptID("quiescence-authority"),
                commandID: RunCommandID("record-quiescence-authority")
            )
        )
        XCTAssertTrue(quiet.quiescence.provesQuiescence)

        let projection = await journal.currentProjection()
        XCTAssertEqual(projection.phase, .stopped)
        XCTAssertEqual(projection.runtimeDrainIntent, .stop)
        XCTAssertTrue(projection.quiescent)
        XCTAssertEqual(projection.sequence, 5)
    }

    func testDrainJournalFailureLeavesSupervisorFailClosed() async throws {
        let root = temporaryDirectory("lifecycle-drain-journal-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        let supervisor = makeSupervisor()
        _ = try await journal.transact(
            .createRun(contract()),
            context: context("create-drain-failure", sequence: 0)
        )
        let authority = JournaledRuntimeLifecycleAuthority(
            supervisor: supervisor,
            journal: journal,
            actorIdentity: actor
        )
        let reusedCommandID = RunCommandID("reused-lifecycle-command")

        do {
            _ = try await authority.requestDrain(
                JournaledRuntimeDrainRequest(
                    intent: .stop,
                    lifecycleCommandID: reusedCommandID,
                    drainReceiptID: ReceiptID("drain-journal-failure"),
                    drainCommandID: reusedCommandID
                )
            )
            XCTFail("A conflicting second journal command must fail")
        } catch {
            XCTAssertEqual(
                error as? JournaledRuntimeLifecycleAuthorityError,
                .journalWriteFailed
            )
        }

        let runtimeProjection = await supervisor.projection()
        XCTAssertEqual(runtimeProjection.phase, .draining(.stop))
        let journalProjection = await journal.currentProjection()
        XCTAssertEqual(journalProjection.phase, .stopRequested)
        XCTAssertNil(journalProjection.runtimeDrainIntent)
    }

    func testSupervisorReceiptsReplayThroughTheSingleJournalToStoppedQuiescence() async throws {
        let root = temporaryDirectory("lifecycle")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        let supervisor = makeSupervisor()
        let request = leaseRequest("process")

        _ = try await journal.transact(
            .createRun(contract()),
            context: context("create", sequence: 0)
        )
        let admission = await supervisor.acquireReceipt(
            request,
            receiptID: ReceiptID("admission"),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )
        _ = try await journal.transact(
            .testOnlyRecordRuntimeAdmission(admission),
            context: context("admission", sequence: 1)
        )

        let identity = RuntimeExternalIdentity(
            stableDigest: ContentDigest("process-start-identity"),
            processID: 42,
            processStartMonotonicNanoseconds: 3,
            parentResourceID: nil
        )
        let binding = await supervisor.bindExternalIdentityReceipt(
            resourceID: request.resourceID,
            leaseID: request.leaseID,
            identity: identity,
            receiptID: ReceiptID("binding"),
            observedAt: Date(timeIntervalSince1970: 3),
            observedAtMonotonicNanoseconds: 3
        )
        _ = try await journal.transact(
            .testOnlyRecordRuntimeBinding(binding),
            context: context("binding", sequence: 2)
        )
        _ = try await journal.transact(
            .requestStop,
            context: context("stop", sequence: 3)
        )
        let drain = await supervisor.beginDrainReceipt(
            .stop,
            receiptID: ReceiptID("drain"),
            observedAt: Date(timeIntervalSince1970: 4),
            observedAtMonotonicNanoseconds: 4
        )
        _ = try await journal.transact(
            .testOnlyRecordRuntimeDrain(drain),
            context: context("drain", sequence: 4)
        )
        let release = await supervisor.releaseOutcomeReceipt(
            resourceID: request.resourceID,
            leaseID: request.leaseID,
            receiptID: ReceiptID("release"),
            observedAt: Date(timeIntervalSince1970: 5),
            observedAtMonotonicNanoseconds: 5
        )
        _ = try await journal.transact(
            .testOnlyRecordRuntimeRelease(release),
            context: context("release", sequence: 5)
        )
        guard case .issued(let quiet) = await supervisor.quiescenceReceipt(
            id: ReceiptID("quiet"),
            observedAt: Date(timeIntervalSince1970: 6),
            monotonicNanoseconds: 6
        ) else {
            return XCTFail("The drained empty supervisor must issue quiescence")
        }
        _ = try await journal.transact(
            .testOnlyRecordQuiescence(quiet),
            context: context("quiet", sequence: 6)
        )

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let projection = await recovered.currentProjection()
        let report = await recovered.recoveryReport
        XCTAssertEqual(projection.phase, .stopped)
        XCTAssertEqual(projection.sequence, 8)
        XCTAssertEqual(projection.runtimeLiveResourceCount, 0)
        XCTAssertEqual(projection.runtimeFailedReleaseCount, 0)
        XCTAssertEqual(projection.runtimeDrainIntent, .stop)
        XCTAssertTrue(projection.quiescent)
        XCTAssertEqual(report.recoveredTransactions, 7)
        XCTAssertEqual(report.recoveredEvents, 8)
    }

    func testAcceptedAdmissionCannotSubstituteADifferentRequest() throws {
        let state = try createdState()
        let request = leaseRequest("declared")
        var substituted = request
        substituted.resourceID = OwnedResourceID("resource-substituted")
        let receipt = RuntimeAdmissionReceipt(
            id: ReceiptID("forged-admission"),
            runID: runID,
            request: request,
            outcome: .accepted(RuntimeResourceLease(
                request: substituted,
                admittedAtMonotonicNanoseconds: 2,
                lastProgressReceiptID: nil
            ), duplicate: false),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordRuntimeAdmission(receipt),
                context: context("forged-admission", sequence: state.sequence)
            ),
            .rejected(.invalidRuntimeReceipt("accepted lease differs from request"))
        )
    }

    func testDuplicateReceiptIDCannotCreateASecondRuntimeFact() throws {
        var state = try createdState()
        let request = leaseRequest("rejected")
        let receipt = RuntimeAdmissionReceipt(
            id: ReceiptID("one-receipt"),
            runID: runID,
            request: request,
            outcome: .rejected(.budgetExceeded),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordRuntimeAdmission(receipt),
            context: context("first-receipt", sequence: state.sequence)
        ))

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordRuntimeAdmission(receipt),
                context: context("second-receipt", sequence: state.sequence)
            ),
            .rejected(.duplicateReceipt(receipt.id))
        )
        XCTAssertTrue(state.runtimeLiveLeases.isEmpty)
    }

    func testCleanupFailureRemainsLiveAndBlocksForgedQuiescence() throws {
        var state = try stateWithLiveLease("failed-cleanup")
        state = try accepted(RunReducer.handle(
            state: state,
            command: .requestStop,
            context: context("request-stop", sequence: state.sequence)
        ))
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordRuntimeDrain(RuntimeDrainReceipt(
                id: ReceiptID("failed-drain"),
                runID: runID,
                snapshot: RuntimeDrainSnapshot(
                    intent: .stop,
                    liveResourceIDs: Set(state.runtimeLiveLeases.keys),
                    cancelledQueuedLeaseIDs: []
                ),
                observedAt: Date(timeIntervalSince1970: 3),
                observedAtMonotonicNanoseconds: 3
            )),
            context: context("failed-drain", sequence: state.sequence)
        ))
        let lease = try XCTUnwrap(state.runtimeLiveLeases.values.first)
        let failure = RuntimeReleaseOutcomeReceipt(
            id: ReceiptID("cleanup-failed"),
            runID: runID,
            resourceID: lease.request.resourceID,
            leaseID: lease.request.leaseID,
            observedAt: Date(timeIntervalSince1970: 4),
            observedAtMonotonicNanoseconds: 4,
            outcome: .cleanupFailed(reasonDigest: ContentDigest("durable-failure"))
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordRuntimeRelease(failure),
            context: context("cleanup-failed", sequence: state.sequence)
        ))
        XCTAssertEqual(state.runtimeFailedReleases, [lease.request.resourceID])
        XCTAssertNotNil(state.runtimeLiveLeases[lease.request.resourceID])

        let forgedQuiet = QuiescenceReceipt(
            id: ReceiptID("forged-quiet"),
            runID: runID,
            intent: .stop,
            observedAt: Date(timeIntervalSince1970: 5),
            observedAtMonotonicNanoseconds: 5,
            liveResources: [],
            failedReleases: [],
            queuedLeaseIDs: []
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordQuiescence(forgedQuiet),
                context: context("forged-quiet", sequence: state.sequence)
            ),
            .rejected(.quiescenceNotProven)
        )
    }

    func testManagedProcessReleaseRejectsForgedNativeTerminationProvenance() throws {
        let state = try stateWithLiveLease("forged-termination")
        let lease = try XCTUnwrap(state.runtimeLiveLeases.values.first)
        let identity = RuntimeExternalIdentity(
            stableDigest: ContentDigest("native-process-identity"),
            processID: 42,
            processStartMonotonicNanoseconds: 2,
            processStartSystemNanoseconds: 2,
            parentResourceID: nil
        )
        let handle = ManagedProcessHandle(
            runID: runID,
            resourceID: lease.request.resourceID,
            leaseID: lease.request.leaseID,
            processID: 42,
            processGroupID: 42,
            externalIdentity: identity
        )
        var forgedExitHandle = handle
        forgedExitHandle.leaseID = ResourceLeaseID("substituted-native-lease")
        let releaseID = ReceiptID("forged-native-release")
        let receipt = RuntimeReleaseOutcomeReceipt(
            id: releaseID,
            runID: runID,
            resourceID: lease.request.resourceID,
            leaseID: lease.request.leaseID,
            observedAt: Date(timeIntervalSince1970: 5),
            observedAtMonotonicNanoseconds: 5,
            outcome: .released(RuntimeReleaseReceipt(
                id: releaseID,
                runID: runID,
                leaseID: lease.request.leaseID,
                resourceID: lease.request.resourceID,
                releasedAtMonotonicNanoseconds: 5,
                duplicate: false
            )),
            managedProcessTermination: ManagedProcessTerminationReceipt(
                handle: handle,
                gracefulSignal: 15,
                forced: false,
                exit: ManagedProcessExitReceipt(
                    handle: forgedExitHandle,
                    observedAtMonotonicNanoseconds: 4,
                    exitCode: 0,
                    terminationSignal: nil
                )
            )
        )

        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordRuntimeRelease(receipt),
                context: context("forged-native-release", sequence: state.sequence)
            ),
            .rejected(.invalidRuntimeReceipt(
                "managed process termination provenance mismatch"
            ))
        )
    }

    func testManagedProcessReleaseRejectsForgedOrDualNaturalExitProvenance() throws {
        let state = try stateWithLiveLease("forged-natural-exit")
        let lease = try XCTUnwrap(state.runtimeLiveLeases.values.first)
        let identity = RuntimeExternalIdentity(
            stableDigest: ContentDigest("natural-process-identity"),
            processID: 43,
            processStartMonotonicNanoseconds: 2,
            processStartSystemNanoseconds: 2,
            parentResourceID: nil
        )
        let handle = ManagedProcessHandle(
            runID: runID,
            resourceID: lease.request.resourceID,
            leaseID: lease.request.leaseID,
            processID: 43,
            processGroupID: 43,
            externalIdentity: identity
        )
        let releaseID = ReceiptID("forged-natural-release")
        var receipt = RuntimeReleaseOutcomeReceipt(
            id: releaseID,
            runID: runID,
            resourceID: lease.request.resourceID,
            leaseID: lease.request.leaseID,
            observedAt: Date(timeIntervalSince1970: 5),
            observedAtMonotonicNanoseconds: 5,
            outcome: .released(RuntimeReleaseReceipt(
                id: releaseID,
                runID: runID,
                leaseID: lease.request.leaseID,
                resourceID: lease.request.resourceID,
                releasedAtMonotonicNanoseconds: 5,
                duplicate: false
            ))
        )
        var crossWired = handle
        crossWired.resourceID = OwnedResourceID("other-resource")
        receipt.managedProcessExit = ManagedProcessExitReceipt(
            handle: crossWired,
            observedAtMonotonicNanoseconds: 4,
            exitCode: 0,
            terminationSignal: nil
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordRuntimeRelease(receipt),
                context: context("forged-natural-release", sequence: state.sequence)
            ),
            .rejected(.invalidRuntimeReceipt(
                "managed process natural-exit provenance mismatch"
            ))
        )

        let exactExit = ManagedProcessExitReceipt(
            handle: handle,
            observedAtMonotonicNanoseconds: 4,
            exitCode: 0,
            terminationSignal: nil
        )
        receipt.managedProcessExit = exactExit
        receipt.managedProcessTermination = ManagedProcessTerminationReceipt(
            handle: handle,
            gracefulSignal: 15,
            forced: false,
            exit: exactExit
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordRuntimeRelease(receipt),
                context: context("dual-native-release", sequence: state.sequence)
            ),
            .rejected(.invalidRuntimeReceipt(
                "release cannot assert both natural exit and termination"
            ))
        )
    }

    func testWrongDrainIntentCannotCloseACompletionRequest() throws {
        var state = try createdState()
        state = try accepted(RunReducer.handle(
            state: state,
            command: .requestCompletion,
            context: context("request-completion", sequence: state.sequence)
        ))
        let wrong = RuntimeDrainReceipt(
            id: ReceiptID("wrong-drain"),
            runID: runID,
            snapshot: RuntimeDrainSnapshot(
                intent: .stop,
                liveResourceIDs: [],
                cancelledQueuedLeaseIDs: []
            ),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )
        XCTAssertEqual(
            RunReducer.handle(
                state: state,
                command: .testOnlyRecordRuntimeDrain(wrong),
                context: context("wrong-drain", sequence: state.sequence)
            ),
            .rejected(.invalidRuntimeReceipt(
                "drain snapshot does not match requested lifecycle or live ownership"
            ))
        )
    }

    private func stateWithLiveLease(_ id: String) throws -> KernelRunState {
        var state = try createdState()
        let request = leaseRequest(id)
        let receipt = RuntimeAdmissionReceipt(
            id: ReceiptID("admission-\(id)"),
            runID: runID,
            request: request,
            outcome: .accepted(RuntimeResourceLease(
                request: request,
                admittedAtMonotonicNanoseconds: 2,
                lastProgressReceiptID: nil
            ), duplicate: false),
            observedAt: Date(timeIntervalSince1970: 2),
            observedAtMonotonicNanoseconds: 2
        )
        state = try accepted(RunReducer.handle(
            state: state,
            command: .testOnlyRecordRuntimeAdmission(receipt),
            context: context("admission-\(id)", sequence: state.sequence)
        ))
        return state
    }

    private func makeSupervisor() -> RuntimeSupervisor {
        RuntimeSupervisor(
            runID: runID,
            budget: HostResourceBudget(nominal: ResourceVector(
                cpuWeight: 100,
                memoryBytes: 1_000_000,
                diskIOWeight: 100,
                gpuWeight: 100,
                networkWeight: 100,
                guiSessionCount: 2,
                processCount: 20
            ))
        )
    }

    private func leaseRequest(_ id: String) -> RuntimeLeaseRequest {
        RuntimeLeaseRequest(
            leaseID: ResourceLeaseID("lease-\(id)"),
            resourceID: OwnedResourceID("resource-\(id)"),
            runID: runID,
            occurrenceID: OccurrenceID("occurrence-\(id)"),
            attemptID: nil,
            kind: .processTree,
            purpose: .productive,
            ownership: .owned,
            releasePolicy: .gracefulThenTerminate,
            externalIdentity: nil,
            reservation: ResourceVector(
                cpuWeight: 1,
                memoryBytes: 1,
                diskIOWeight: 1,
                gpuWeight: 0,
                networkWeight: 0,
                guiSessionCount: 0,
                processCount: 1
            ),
            requestedAtMonotonicNanoseconds: 1,
            renewalDeadlineMonotonicNanoseconds: nil,
            progressReceiptID: nil
        )
    }

    private func contract() -> TaskContract {
        TaskContract(
            id: TaskContractID("runtime-contract"),
            schemaVersion: 1,
            verbatimObjective: "Execute declared work and prove resource cleanup.",
            objectiveDigest: ContentDigest("runtime-objective"),
            requirements: [],
            constraints: [],
            nonGoals: [],
            protectedBaselines: [],
            authorityCeiling: .readOnly,
            acceptancePolicy: TaskAcceptancePolicy(
                duration: nil,
                requiresIndependentReview: true,
                requiresQuiescence: true
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func context(_ id: String, sequence: UInt64) -> KernelCommandContext {
        KernelCommandContext(
            commandID: RunCommandID(id),
            expectedSequence: sequence,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(sequence + 1)),
            actor: actor
        )
    }

    private func createdState() throws -> KernelRunState {
        try accepted(RunReducer.handle(
            state: .empty(runID: runID),
            command: .createRun(contract()),
            context: context("create", sequence: 0)
        ))
    }

    private func accepted(_ decision: ReducerDecision) throws -> KernelRunState {
        guard case .accepted(_, let state) = decision else {
            throw NSError(domain: "RuntimeJournalIntegrationTests", code: 1)
        }
        return state
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-RuntimeJournal-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
