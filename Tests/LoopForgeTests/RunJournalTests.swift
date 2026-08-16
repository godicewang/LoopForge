import Foundation
import CryptoKit
import XCTest
@testable import LoopForge

final class RunJournalTests: XCTestCase {
    private let runID = KernelRunID("journal-run")
    private let actor = ActorIdentity(
        id: ActorID("owner"),
        role: "owner",
        lineageDigest: ContentDigest("owner-lineage")
    )

    func testJournalReplaysCompleteTransactionsAndReturnsOriginalDuplicateReceipt() async throws {
        let root = temporaryDirectory("replay")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        let context = commandContext("create", sequence: 0)

        let first = try await journal.transact(.createRun(contract()), context: context)
        let duplicate = try await journal.transact(.createRun(contract()), context: context)

        XCTAssertFalse(first.duplicate)
        XCTAssertTrue(duplicate.duplicate)
        XCTAssertEqual(first.commandID, duplicate.commandID)
        XCTAssertEqual(first.frameDigest, duplicate.frameDigest)
        XCTAssertEqual(first.eventIDs, duplicate.eventIDs)

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let projection = await recovered.currentProjection()
        let report = await recovered.recoveryReport
        XCTAssertEqual(projection.phase, .ready)
        XCTAssertEqual(projection.sequence, 1)
        XCTAssertEqual(report.recoveredTransactions, 1)
        XCTAssertEqual(report.recoveredEvents, 1)
        XCTAssertEqual(report.ignoredTrailingBytes, 0)
    }

    func testOneCommandWithTwoEventsRecoversAtomically() async throws {
        let root = temporaryDirectory("atomic")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transact(
            .createRun(contract()),
            context: commandContext("create", sequence: 0)
        )
        _ = try await journal.transact(
            .requestStop,
            context: commandContext("stop", sequence: 1)
        )
        _ = try await journal.transact(
            .testOnlyRecordRuntimeDrain(RuntimeDrainReceipt(
                id: ReceiptID("drain"),
                runID: runID,
                snapshot: RuntimeDrainSnapshot(
                    intent: .stop,
                    liveResourceIDs: [],
                    cancelledQueuedLeaseIDs: []
                ),
                observedAt: Date(timeIntervalSince1970: 3),
                observedAtMonotonicNanoseconds: 3
            )),
            context: commandContext("drain", sequence: 2)
        )
        let receipt = try await journal.transact(
            .testOnlyRecordQuiescence(QuiescenceReceipt(
                id: ReceiptID("quiet"),
                runID: runID,
                intent: .stop,
                observedAt: Date(timeIntervalSince1970: 4),
                observedAtMonotonicNanoseconds: 4,
                liveResources: [],
                failedReleases: [],
                queuedLeaseIDs: []
            )),
            context: commandContext("quiet", sequence: 3)
        )
        XCTAssertEqual(receipt.eventIDs.count, 2)

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let projection = await recovered.currentProjection()
        let report = await recovered.recoveryReport
        XCTAssertEqual(projection.phase, .stopped)
        XCTAssertEqual(projection.sequence, 5)
        XCTAssertTrue(projection.quiescent)
        XCTAssertEqual(report.recoveredTransactions, 4)
        XCTAssertEqual(report.recoveredEvents, 5)
    }

    func testRecoveryIgnoresOnlyUnterminatedTrailingFragment() async throws {
        let root = temporaryDirectory("partial")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transact(
            .createRun(contract()),
            context: commandContext("create", sequence: 0)
        )
        let journalURL = await journal.journalURL
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"truncated\":".utf8))
        try handle.close()

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let report = await recovered.recoveryReport
        let projection = await recovered.currentProjection()
        XCTAssertEqual(projection.phase, .ready)
        XCTAssertEqual(report.recoveredTransactions, 1)
        XCTAssertGreaterThan(report.ignoredTrailingBytes, 0)
    }

    func testRecoveryRejectsACompleteCorruptFrame() async throws {
        let root = temporaryDirectory("corrupt")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(runID.rawValue),
            withIntermediateDirectories: true
        )
        let url = root
            .appendingPathComponent(runID.rawValue)
            .appendingPathComponent("journal.ndjson")
        try Data("{\"complete\":\"but invalid\"}\n".utf8).write(to: url)

        XCTAssertThrowsError(try RunJournal(rootDirectory: root, runID: runID)) { error in
            XCTAssertEqual(error as? RunJournalError, .invalidFrameEncoding(line: 1))
        }
    }

    func testRecoveryRemainsBackwardCompatibleWithVersionOneFrame() async throws {
        struct LegacyDigestInput: Encodable {
            var schemaVersion = 1
            var runID: KernelRunID
            var commandID: RunCommandID
            var previousFrameDigest: ContentDigest?
            var events: [OrchestrationEvent]
        }
        struct LegacyFrame: Encodable {
            var schemaVersion = 1
            var runID: KernelRunID
            var commandID: RunCommandID
            var previousFrameDigest: ContentDigest?
            var events: [OrchestrationEvent]
            var frameDigest: ContentDigest
        }
        let root = temporaryDirectory("version-one")
        defer { try? FileManager.default.removeItem(at: root) }
        let commandID = RunCommandID("legacy-create")
        let event = OrchestrationEvent(
            id: OrchestrationEventID("legacy-create.1"),
            runID: runID,
            sequence: 1,
            commandID: commandID,
            occurredAt: Date(timeIntervalSince1970: 1),
            payload: .runCreated(contract())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digestBytes = try encoder.encode(LegacyDigestInput(
            runID: runID,
            commandID: commandID,
            previousFrameDigest: nil,
            events: [event]
        ))
        let digest = ContentDigest(SHA256.hash(data: digestBytes).map {
            String(format: "%02x", $0)
        }.joined())
        var bytes = try encoder.encode(LegacyFrame(
            runID: runID,
            commandID: commandID,
            previousFrameDigest: nil,
            events: [event],
            frameDigest: digest
        ))
        bytes.append(0x0A)
        let runDirectory = root.appendingPathComponent(runID.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        try bytes.write(to: runDirectory.appendingPathComponent("journal.ndjson"))

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let projection = await recovered.currentProjection()
        XCTAssertEqual(projection.phase, .ready)
        XCTAssertEqual(projection.sequence, 1)
    }

    func testRecoveryRejectsARepeatedCommandFrame() async throws {
        let root = temporaryDirectory("duplicate-command")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transact(
            .createRun(contract()),
            context: commandContext("create", sequence: 0)
        )
        let journalURL = await journal.journalURL
        let frame = try Data(contentsOf: journalURL)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: frame)
        try handle.close()

        XCTAssertThrowsError(try RunJournal(rootDirectory: root, runID: runID)) { error in
            XCTAssertEqual(error as? RunJournalError, .duplicateCommand(line: 2))
        }
    }

    func testConcurrentStaleWriterCannotCreateASecondLogicalEffect() async throws {
        let root = temporaryDirectory("stale")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transact(
            .createRun(contract()),
            context: commandContext("create", sequence: 0)
        )

        do {
            _ = try await journal.transact(
                .requestStop,
                context: commandContext("stale-stop", sequence: 0)
            )
            XCTFail("A stale expected sequence must be rejected")
        } catch {
            XCTAssertEqual(
                error as? RunJournalError,
                .reducerRejected(.staleSequence(expected: 0, actual: 1))
            )
        }
        let projection = await journal.currentProjection()
        XCTAssertEqual(projection.phase, .ready)
        XCTAssertEqual(projection.sequence, 1)
    }

    func testTwoJournalActorsCannotForkTheSameOnDiskSequence() async throws {
        let root = temporaryDirectory("split-brain")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try RunJournal(rootDirectory: root, runID: runID)
        let stale = try RunJournal(rootDirectory: root, runID: runID)

        _ = try await first.transact(
            .createRun(contract()),
            context: commandContext("first-create", sequence: 0)
        )
        do {
            _ = try await stale.transact(
                .createRun(contract()),
                context: commandContext("stale-create", sequence: 0)
            )
            XCTFail("A second writer must not append from an obsolete journal head")
        } catch {
            XCTAssertEqual(
                error as? RunJournalError,
                .writerStale(expectedSequence: 0, actualSequence: 1)
            )
        }

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let projection = await recovered.currentProjection()
        XCTAssertEqual(projection.sequence, 1)
        XCTAssertEqual(projection.phase, .ready)
    }

    func testWriterRefusesToAppendAcrossAnUnresolvedTrailingFragment() async throws {
        let root = temporaryDirectory("fragment-fence")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transact(
            .createRun(contract()),
            context: commandContext("create", sequence: 0)
        )
        let journalURL = await journal.journalURL
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("broken".utf8))
        try handle.close()

        do {
            _ = try await journal.transact(
                .requestStop,
                context: commandContext("stop", sequence: 1)
            )
            XCTFail("Appending behind a partial transaction would make corruption durable")
        } catch {
            XCTAssertEqual(
                error as? RunJournalError,
                .unresolvedTrailingFragment(bytes: 6)
            )
        }
    }

    func testCausalAttemptBudgetIsJournaledBeforeWorkerAndDuplicateCannotCountTwice() async throws {
        let root = temporaryDirectory("causal-admission")
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transactAtCurrentSequence(
            .createRun(contract()),
            commandID: RunCommandID("create"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(epochID: "epoch", budget: convergenceBudget()),
            commandID: RunCommandID("initialize-convergence"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        let request = causalRequest("attempt-1", strategy: causalStrategy())
        let first = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(request),
            commandID: RunCommandID("admit-attempt-1"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )
        let duplicate = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(request),
            commandID: RunCommandID("admit-attempt-1"),
            issuedAt: Date(timeIntervalSince1970: 4),
            actor: actor
        )

        XCTAssertFalse(first.duplicate)
        XCTAssertTrue(duplicate.duplicate)
        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let projection = await recovered.currentProjection()
        let recoveredGovernor = await recovered.currentConvergenceGovernor()
        let governor = try XCTUnwrap(recoveredGovernor)
        XCTAssertEqual(projection.causalAttemptsConsumed, 1)
        XCTAssertEqual(projection.causalStrategiesConsumed, 1)
        XCTAssertEqual(governor.consumption.attempts, 1)
        XCTAssertEqual(governor.activeStrategies.count, 1)
        let journalURL = await recovered.journalURL
        let journalText = try String(contentsOf: journalURL, encoding: .utf8)
        let decodedEventText = try journalText
            .split(separator: "\n")
            .map { line -> String in
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
                let frame = try XCTUnwrap(object as? [String: Any])
                let base64 = try XCTUnwrap(frame["encodedEvents"] as? String)
                let data = try XCTUnwrap(Data(base64Encoded: base64))
                return try XCTUnwrap(String(data: data, encoding: .utf8))
            }
            .joined(separator: "\n")
        XCTAssertTrue(decodedEventText.contains("attemptAdmitted"))
        XCTAssertFalse(decodedEventText.contains("activeStrategies"))
        XCTAssertFalse(decodedEventText.contains("retiredStrategies"))
        XCTAssertFalse(decodedEventText.contains("replacementAuthorizationReceipts"))
    }

    func testRenamedStrategyMetadataSharesBudgetAcrossJournalReplay() async throws {
        let root = temporaryDirectory("causal-equivalent-replay")
        defer { try? FileManager.default.removeItem(at: root) }
        var journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transactAtCurrentSequence(
            .createRun(contract()),
            commandID: RunCommandID("create"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(epochID: "epoch", budget: convergenceBudget()),
            commandID: RunCommandID("initialize"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        let first = causalStrategy(observation: "first-observation")
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("attempt-1", strategy: first)),
            commandID: RunCommandID("admit-first"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .recordCausalProgress(
                strategy: first.fingerprint,
                previous: convergenceProgress(unresolved: [RequirementID("requirement")]),
                current: convergenceProgress(accepted: [RequirementID("requirement")])
            ),
            commandID: RunCommandID("close-first"),
            issuedAt: Date(timeIntervalSince1970: 4),
            actor: actor
        )

        journal = try RunJournal(rootDirectory: root, runID: runID)
        var renamed = causalStrategy(
            observation: "renamed-observation",
            lessons: [ContentDigest("new-lesson-receipt")]
        )
        renamed.falsificationPredicateIDs = ["renamed-falsification-predicate"]
        XCTAssertEqual(first.fingerprint, renamed.fingerprint)
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("attempt-2", strategy: renamed)),
            commandID: RunCommandID("admit-renamed"),
            issuedAt: Date(timeIntervalSince1970: 5),
            actor: actor
        )
        let stagnant = convergenceProgress(
            unresolved: [RequirementID("requirement")]
        )
        _ = try await journal.transactAtCurrentSequence(
            .recordCausalProgress(
                strategy: renamed.fingerprint,
                previous: stagnant,
                current: stagnant
            ),
            commandID: RunCommandID("close-without-progress"),
            issuedAt: Date(timeIntervalSince1970: 6),
            actor: actor
        )

        journal = try RunJournal(rootDirectory: root, runID: runID)
        let recoveredSnapshot = await journal.currentConvergenceGovernor()
        let recovered = try XCTUnwrap(recoveredSnapshot)
        let acceptedProgressReceiptIDs = await journal.acceptedCausalProgressReceiptIDs()
        XCTAssertEqual(recovered.consumption.attempts, 2)
        XCTAssertEqual(
            recovered.consumption.strategies,
            1,
            "Journal replay must retain one shared strategy budget for causally identical metadata renames."
        )
        XCTAssertEqual(recovered.activeStrategies.count, 1)
        XCTAssertEqual(
            acceptedProgressReceiptIDs,
            [ReceiptID("close-first")],
            "A journaled accepted=false progress event cannot authorize accepted-active duration."
        )
    }

    func testJournaledOccurrenceCoverageSurvivesReplayAndRejectsStagnantTime() async throws {
        let root = temporaryDirectory("journaled-occurrence-coverage")
        defer { try? FileManager.default.removeItem(at: root) }
        var journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transactAtCurrentSequence(
            .createRun(durationContract()),
            commandID: RunCommandID("create-duration"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(epochID: "duration-epoch", budget: convergenceBudget()),
            commandID: RunCommandID("initialize-duration"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        let strategy = causalStrategy(observation: "duration-progress")
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("duration-attempt-1", strategy: strategy)),
            commandID: RunCommandID("admit-duration-1"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .recordCausalProgress(
                strategy: strategy.fingerprint,
                previous: convergenceProgress(unresolved: [RequirementID("requirement")]),
                current: convergenceProgress(accepted: [RequirementID("requirement")])
            ),
            commandID: RunCommandID("accepted-duration-progress"),
            issuedAt: Date(timeIntervalSince1970: 4),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordOccurrence(occurrence(
                id: "accepted-duration",
                ordinal: 1,
                start: 0,
                end: 5_000_000_000,
                progress: ReceiptID("accepted-duration-progress")
            )),
            commandID: RunCommandID("record-accepted-duration"),
            issuedAt: Date(timeIntervalSince1970: 5),
            actor: actor
        )

        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("duration-attempt-2", strategy: strategy)),
            commandID: RunCommandID("admit-duration-2"),
            issuedAt: Date(timeIntervalSince1970: 6),
            actor: actor
        )
        let stagnant = convergenceProgress(unresolved: [RequirementID("requirement")])
        _ = try await journal.transactAtCurrentSequence(
            .recordCausalProgress(
                strategy: strategy.fingerprint,
                previous: stagnant,
                current: stagnant
            ),
            commandID: RunCommandID("stagnant-duration-progress"),
            issuedAt: Date(timeIntervalSince1970: 7),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .testOnlyRecordOccurrence(occurrence(
                id: "stagnant-duration",
                ordinal: 2,
                start: 5_000_000_000,
                end: 10_000_000_000,
                progress: ReceiptID("stagnant-duration-progress")
            )),
            commandID: RunCommandID("record-stagnant-duration"),
            issuedAt: Date(timeIntervalSince1970: 8),
            actor: actor
        )

        let liveCoverage = await journal.currentDurationCoverage()
        let liveProjection = try XCTUnwrap(liveCoverage)
        XCTAssertEqual(liveProjection.cumulativeAcceptedSeconds, 5)
        XCTAssertEqual(liveProjection.excludedSecondsByReason[.excludedNoProgress], 5)
        XCTAssertEqual(liveProjection.violations, [.acceptedWithoutProgress])

        journal = try RunJournal(rootDirectory: root, runID: runID)
        let replayedCoverage = await journal.currentDurationCoverage()
        let replayed = try XCTUnwrap(replayedCoverage)
        XCTAssertEqual(replayed, liveProjection)
        let acceptedProgressReceiptIDs = await journal.acceptedCausalProgressReceiptIDs()
        let causalProgressReceiptIDs = await journal.causalProgressReceiptIDs()
        XCTAssertEqual(
            acceptedProgressReceiptIDs,
            [ReceiptID("accepted-duration-progress")]
        )
        XCTAssertEqual(
            causalProgressReceiptIDs,
            [
                ReceiptID("accepted-duration-progress"),
                ReceiptID("stagnant-duration-progress")
            ]
        )
    }

    func testRetirementAndReplacementAuthorizationSurviveCrashReplay() async throws {
        let root = temporaryDirectory("causal-retirement")
        defer { try? FileManager.default.removeItem(at: root) }
        var journal = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await journal.transactAtCurrentSequence(
            .createRun(contract()),
            commandID: RunCommandID("create"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .initializeConvergence(epochID: "epoch", budget: convergenceBudget()),
            commandID: RunCommandID("initialize"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        let first = causalStrategy(action: "first", observation: "first-passes")
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("attempt-1", strategy: first)),
            commandID: RunCommandID("admit-first"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )
        let blocker = causalFailure()
        _ = try await journal.transactAtCurrentSequence(
            .recordCausalFailure(
                strategy: first.fingerprint,
                failure: blocker,
                lessonDigest: ContentDigest("lesson-1")
            ),
            commandID: RunCommandID("fail-first"),
            issuedAt: Date(timeIntervalSince1970: 4),
            actor: actor
        )

        journal = try RunJournal(rootDirectory: root, runID: runID)
        var recoveredSnapshot = await journal.currentConvergenceGovernor()
        var recoveredGovernor = try XCTUnwrap(recoveredSnapshot)
        XCTAssertNotNil(recoveredGovernor.retiredStrategies[first.fingerprint])
        XCTAssertEqual(recoveredGovernor.equivalentFailureCounts[blocker.digest], 1)

        let second = causalStrategy(
            action: "second",
            observation: "second-passes",
            lessons: [ContentDigest("lesson-1")]
        )
        let delta = CausalStrategyDelta(
            changedAxes: [.action],
            addressedFailureDigests: [blocker.digest],
            newPredictedObservationIDs: ["second-passes"],
            inheritedLessonDigests: [ContentDigest("lesson-1")],
            whyOldFailureNoLongerApplies: [ContentDigest("proof")]
        )
        _ = try await journal.transactAtCurrentSequence(
            .authorizeCausalReplacement(
                receiptID: ReceiptID("replacement-receipt"),
                predecessor: first.fingerprint,
                replacement: second,
                failures: [blocker],
                delta: delta
            ),
            commandID: RunCommandID("authorize-second"),
            issuedAt: Date(timeIntervalSince1970: 5),
            actor: actor
        )
        _ = try await journal.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("attempt-2", strategy: second)),
            commandID: RunCommandID("admit-second"),
            issuedAt: Date(timeIntervalSince1970: 6),
            actor: actor
        )

        journal = try RunJournal(rootDirectory: root, runID: runID)
        recoveredSnapshot = await journal.currentConvergenceGovernor()
        recoveredGovernor = try XCTUnwrap(recoveredSnapshot)
        XCTAssertEqual(recoveredGovernor.consumption.attempts, 2)
        XCTAssertEqual(recoveredGovernor.consumption.strategies, 2)
        XCTAssertNotNil(recoveredGovernor.replacementAuthorizationReceipts[second.fingerprint])
        XCTAssertNotNil(recoveredGovernor.activeStrategies[second.fingerprint])
    }

    func testStaleConvergenceWriterCannotForkOrMintAttemptBudget() async throws {
        let root = temporaryDirectory("causal-split-brain")
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await owner.transactAtCurrentSequence(
            .createRun(contract()),
            commandID: RunCommandID("create"),
            issuedAt: Date(timeIntervalSince1970: 1),
            actor: actor
        )
        _ = try await owner.transactAtCurrentSequence(
            .initializeConvergence(epochID: "epoch", budget: convergenceBudget()),
            commandID: RunCommandID("initialize"),
            issuedAt: Date(timeIntervalSince1970: 2),
            actor: actor
        )
        let stale = try RunJournal(rootDirectory: root, runID: runID)
        _ = try await owner.transactAtCurrentSequence(
            .admitCausalAttempt(causalRequest("owner-attempt", strategy: causalStrategy())),
            commandID: RunCommandID("owner-admission"),
            issuedAt: Date(timeIntervalSince1970: 3),
            actor: actor
        )

        do {
            _ = try await stale.transactAtCurrentSequence(
                .admitCausalAttempt(causalRequest(
                    "stale-attempt",
                    strategy: causalStrategy(action: "stale", observation: "stale-passes")
                )),
                commandID: RunCommandID("stale-admission"),
                issuedAt: Date(timeIntervalSince1970: 3),
                actor: actor
            )
            XCTFail("A stale convergence writer must not append from an obsolete budget state")
        } catch {
            XCTAssertEqual(
                error as? RunJournalError,
                .writerStale(expectedSequence: 2, actualSequence: 3)
            )
        }

        let recovered = try RunJournal(rootDirectory: root, runID: runID)
        let recoveredGovernor = await recovered.currentConvergenceGovernor()
        let governor = try XCTUnwrap(recoveredGovernor)
        XCTAssertEqual(governor.consumption.attempts, 1)
        XCTAssertEqual(governor.consumption.strategies, 1)
    }

    func testLegacyImporterNeverMintsReceiptsAcceptedTimeOrAutoResume() throws {
        let data = Data(#"""
        {
          "id": "legacy",
          "request": "Preserve this objective",
          "status": "completed",
          "lastAgentMessage": "verified and complete",
          "auditSummary": "100/100",
          "accumulatedCodexSeconds": 72000,
          "coveredSeconds": 36000
        }
        """#.utf8)

        let observations = try LegacyTaskImporter.importRaw(data)
        XCTAssertEqual(observations.count, 1)
        let observation = try XCTUnwrap(observations.first)
        XCTAssertEqual(observation.historicalID, "legacy")
        XCTAssertEqual(observation.objectiveClaim, "Preserve this objective")
        XCTAssertFalse(observation.mayAutoResume)
        XCTAssertEqual(observation.acceptedReceiptIDs, [])
        XCTAssertEqual(observation.durationObservations.count, 2)
        XCTAssertTrue(observation.durationObservations.allSatisfy {
            $0.acceptedSeconds == 0 && $0.disposition == "unverifiedLegacyObservation"
        })
        XCTAssertTrue(observation.claims.contains {
            $0.field == "status" && $0.value == "completed"
        })
    }

    func testLegacyImporterRejectsScalarTopLevel() {
        XCTAssertThrowsError(try LegacyTaskImporter.importRaw(Data("42".utf8))) { error in
            XCTAssertEqual(error as? LegacyTaskImporterError, .invalidTopLevel)
        }
    }

    private func commandContext(_ id: String, sequence: UInt64) -> KernelCommandContext {
        KernelCommandContext(
            commandID: RunCommandID(id),
            expectedSequence: sequence,
            issuedAt: Date(timeIntervalSince1970: TimeInterval(sequence + 1)),
            actor: actor
        )
    }

    private func contract() -> TaskContract {
        TaskContract(
            id: TaskContractID("journal-contract"),
            schemaVersion: 1,
            verbatimObjective: "Retain the exact objective as an immutable contract.",
            objectiveDigest: ContentDigest("journal-objective"),
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

    private func durationContract() -> TaskContract {
        var value = contract()
        value.acceptancePolicy.duration = DurationAcceptancePolicy(
            requiredSeconds: 5,
            eligibleClass: .acceptedExecution
        )
        return value
    }

    private func occurrence(
        id: String,
        ordinal: UInt64,
        start: UInt64,
        end: UInt64,
        progress: ReceiptID?
    ) -> OccurrenceReceipt {
        OccurrenceReceipt(
            id: ReceiptID("receipt-\(id)"),
            occurrenceID: OccurrenceID(id),
            invocation: .scheduled(scheduleID: ScheduleID("schedule"), ordinal: ordinal),
            clock: ClockReceipt(
                bootSessionID: BootSessionID("boot"),
                monotonicStartNanoseconds: start,
                monotonicEndNanoseconds: end,
                wallStart: Date(timeIntervalSince1970: TimeInterval(start) / 1_000_000_000),
                wallEnd: Date(timeIntervalSince1970: TimeInterval(end) / 1_000_000_000),
                discontinuities: []
            ),
            outcome: .succeeded,
            intervalDisposition: .acceptedScheduled,
            evidenceReceiptIDs: Set(progress.map { [$0] } ?? []),
            progressReceiptID: progress
        )
    }

    private func convergenceBudget() -> ConvergenceBudget {
        ConvergenceBudget(
            maximumAttempts: 6,
            maximumEquivalentFailures: 3,
            maximumStrategies: 6,
            maximumPlanExpansions: 2,
            maximumMutationCost: 100,
            maximumVerificationCost: 100,
            maximumDamageEvents: 1,
            maximumExternalEffects: 1
        )
    }

    private func causalStrategy(
        action: String = "first",
        observation: String = "first-passes",
        lessons: Set<ContentDigest> = []
    ) -> CausalStrategyDescriptor {
        CausalStrategyDescriptor(
            requirementIDs: [RequirementID("requirement")],
            hypothesisClass: "repair",
            actionClass: action,
            workspaceTopology: "isolated",
            capabilityRoute: ["shell"],
            evidenceSources: ["baseline"],
            measurementBoundary: "before-through-after",
            verificationOracles: ["oracle"],
            mutationSurfaceDigest: ContentDigest("surface"),
            baselineRevision: ContentDigest("baseline-revision"),
            expectedObservationIDs: [observation],
            falsificationPredicateIDs: ["oracle-fails"],
            inheritedLessonDigests: lessons
        )
    }

    private func causalRequest(
        _ id: String,
        strategy: CausalStrategyDescriptor
    ) -> AttemptAdmissionRequest {
        AttemptAdmissionRequest(
            attemptID: AttemptID(id),
            strategy: strategy,
            predictedObservationIDs: strategy.expectedObservationIDs,
            falsificationPredicateIDs: strategy.falsificationPredicateIDs,
            rollbackPoint: ContentDigest("rollback"),
            mutationCost: 1,
            verificationCost: 1,
            externalEffects: 0
        )
    }

    private func causalFailure() -> CausalFailureFingerprint {
        CausalFailureFingerprint(
            predicateID: "oracle-fails",
            outcomeClass: .deterministicImplementationFailure,
            structuredErrorCode: "E1",
            workspaceRevision: ContentDigest("workspace"),
            capabilityOrResource: nil,
            verifierOrMeasurement: "oracle",
            immutableConstraint: nil,
            evidenceDigest: ContentDigest("same-evidence"),
            externalConditionVersion: nil
        )
    }

    private func convergenceProgress(
        accepted: Set<RequirementID> = [],
        unresolved: Set<RequirementID> = []
    ) -> ConvergenceProgressVector {
        ConvergenceProgressVector(
            acceptedRequirements: accepted,
            unresolvedRequirements: unresolved,
            blockerDigests: [],
            acceptedEvidence: [],
            unresolvedVerifierFailures: [],
            acceptedQualityDimensions: [],
            unresolvedClaims: [],
            protectedInvariantRegressions: []
        )
    }

    private func temporaryDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-RunJournal-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
