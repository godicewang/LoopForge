# Unified Scheduler, Watcher Cadence, and Interval Accounting Specification

Status: **pre-implementation normative design; production refactor gate remains closed**  
Scope: the common scheduling, occurrence, timing, recovery, cancellation, persistence, and projection semantics required by Auto Graph, Single Loop, Continuum Watcher, and future workload adapters.

## 1. Governing conclusion

Continuum Watcher is currently a second orchestration kernel, not a workload adapter. Its 4,987 production lines own a separate lifecycle enum, mutable runtime record, timer registry, operation registry, Agent queue, persistence file, event vocabulary, recovery policy, completion mechanism, and reporting path. Auto Graph and Single Loop implement parallel versions of those same responsibilities. The three systems therefore disagree about what “running,” “stopped,” “successful,” “active time,” “manual work,” “recovered,” and “complete” mean.

This semantic split explains multiple observed failures with one cause:

- cancellation removes Swift task handles before the child operation proves exit;
- a failed pass may synchronously wake an Agent and the review schedules another pass at `now`;
- startup turns a missing `nextRunAt` into an immediate pass;
- telemetry freshness is inferred from wall-clock timestamps and file modification time;
- a checkpoint is accepted by existence and size, without occurrence identity or digest lineage;
- manual, scheduled, recovery, verification, and Agent activity have no common typed interval ledger;
- an Agent-authored status marker can complete work without deterministic acceptance receipts;
- the UI and report present recent prose events, not the authoritative occurrence journal.

The remedy is not another Watcher-specific guard. One event-sourced scheduler and runtime supervisor must own every durable workload. Watcher becomes a declarative workload adapter that contributes a deterministic action, telemetry decoder, evaluation rules, and evidence recipe; it must not own lifecycle truth.

## 2. Measured current surface

| Item | Observation |
|---|---:|
| Watcher production surface | 4,987 lines across eight files |
| Watcher test functions discovered | 60 |
| scheduling/time/cancellation references in core Watcher files | 63 |
| in-memory scheduler registries | 4 dictionaries/sets plus one FIFO Agent gate |
| durable pass interval receipts | 0 |
| monotonic clock / boot-session identities | 0 |
| checkpoint content/lineage receipts | 0 |
| report event retention | last 40 prose events |
| review prompt event retention | last 20 prose events |
| native detail event retention | last 16 prose events |

Tests exercise many local functions, but the production contract remains unprovable because the state needed to assert ownership, quiescence, interval eligibility, causal retry identity, and crash recovery is not represented.

## 3. Additional defects

### F-213 — Critical — Watcher duplicates the orchestration kernel

`WatcherController`, `WatcherStore`, `WatcherStatus`, and `WatcherRuntimeState` independently implement lifecycle, scheduling, persistence, retry, Agent serialization, and reports. The same concepts exist separately in Graph and Single Loop. A fix in one path cannot establish a system invariant.

Required redesign: a common command/event/reducer kernel owns lifecycle and resources. Workload adapters may provide domain-free executable declarations and decoders but cannot mutate lifecycle state.

### F-214 — Critical — Cancellation is handle deletion, not quiescence

`cancelWork` and `shutdown` cancel tasks, immediately remove all task/token ownership, and project the watcher as no longer running (`WatcherController.swift:292-338`). No awaited join, process-group inventory, TERM/KILL escalation, or final-state receipt exists.

Required redesign: stop and pause enter `draining`; the supervisor retains ownership until every async task, process descendant, timer, capability, power assertion, and pending journal write has a terminal receipt. Failure becomes `cleanupFailed`, never `stopped`.

### F-215 — Critical — Scheduling has no durable occurrence identity

Scheduling is a `Task.sleep` plus a UUID token stored in memory (`WatcherController.swift:1126-1145`). The intended occurrence, lease, deadline, invocation reason, retry lineage, and result are not journaled atomically. Relaunch reconstructs intent from mutable `nextRunAt` fields.

Required redesign: persist an `OccurrencePlanned` event with a deterministic occurrence ID before arming an in-memory timer. Execution requires a compare-and-swap lease for that exact occurrence.

### F-216 — High — Wall clock is used as elapsed-time authority

The controller computes delays with `Date.timeIntervalSinceNow`, freshness with `Date`, and cadence with mutable wall-clock fields. Clock changes, sleep, wake, and reboot cannot be distinguished from productive elapsed time.

Required redesign: wall clock is used only for calendar eligibility and display. Elapsed execution uses a monotonic clock receipt bound to a boot/session ID. A reboot or sleep boundary closes the live segment; it never fabricates coverage.

### F-217 — Critical — Scheduled, manual, recovery, verification, and Agent work are not typed

`runNow` and `reviewNow` cancel a scheduled timer and enter the same operation paths used by automatic work. Runtime stores counts and last dates but no invocation-class interval receipt.

Required redesign: every attempt carries an immutable `InvocationKind` (`scheduled`, `manual`, `recovery`, `verification`, `adaptiveReview`, `ownerAmendment`) and a policy-derived time disposition. Manual work can never accidentally satisfy a scheduled-coverage requirement.

### F-218 — Critical — A successful pass has no causal interval receipt

The runtime stores `lastSuccessfulRunAt` and `totalRuns`, but not start/end monotonic instants, expected cadence, source revision, process receipt, output digest, or exclusion reason. Valid coverage cannot be reconstructed after a crash.

Required redesign: `OccurrenceReceipt` is the sole pass truth. Coverage is derived from accepted adjacent successful scheduled occurrences under the task contract; raw time is never inferred from status dates.

### F-219 — High — Missed-run behavior is implicit and unbounded

Startup uses `nextRunAt ?? Date()`, recovery sets `nextRunAt = now`, and post-review schedules at `now`. The scheduler has no explicit skip, coalesce, or bounded catch-up policy. A long sleep or outage can create immediate work and burst load without recording what was missed.

Required redesign: every schedule declares one missed-run policy. The safe default is `coalesceOne`: record all missed occurrences as excluded and authorize at most one recovery occurrence subject to resource and novelty gates.

### F-220 — Critical — Checkpoint existence is confused with recoverability

Checkpoint validation proves only that a path exists and is below a size limit. It does not bind checkpoint bytes to a pass, source revision, telemetry, predecessor, schema, atomic write, or replay test.

Required redesign: checkpoint writes use atomic replace and produce a digest-linked `CheckpointReceipt` containing occurrence ID, schema, producer revision, prior digest, content digest, and recovery-probe result.

### F-221 — Critical — Telemetry freshness is wall-clock/file metadata, not provenance

The loader accepts Agent/pipeline-authored `capturedAt` within a small time window and relies on file freshness. An old or unrelated file can be timestamped into the current run, and clock skew can reject valid output.

Required redesign: the supervisor creates a nonce/output directory for each occurrence. Telemetry must embed the nonce and source revision, and its digest must be emitted by the owned process receipt. Modification time is diagnostic only.

### F-222 — Critical — Prose and self-authored booleans control lifecycle

`telemetry.completed` and a status marker found anywhere in an Agent response can lead to completion. The same Agent may author the pipeline, repair it, verify commands, create assessment data, and declare completion.

Required redesign: model output is a claim. Completion requires the task contract’s deterministic evidence receipts, independent review, accepted integration state where applicable, and quiescence. No string marker or workload boolean changes lifecycle directly.

### F-223 — High — Agent turn serialization leaks cancelled waiters

`WatcherAgentTurnGate` queues checked continuations without cancellation removal, priority, lease timeout, or fairness receipt. A stopped watcher may remain queued and later acquire the gate.

Required redesign: Agent execution is a ResourceGovernor lease with cancellation-aware waiters, bounded queue age, task authority checks at grant time, and an explicit release receipt.

### F-224 — High — Manifest normalization silently changes executable intent

Unknown enum values are mapped to fallbacks, strings and collections are truncated, and only the normalized projection remains visible. The Agent and user can believe a larger contract is active.

Required redesign: parsing preserves raw bytes; validation either accepts the exact declared contract or returns structured diagnostics. Any reduction requires an owner-visible amendment with before/after digests.

### F-225 — High — Recent prose is mistaken for operational history

Watcher storage truncates its event array, reports show 40 events, review prompts 20, and detail views 16. These events lack causal IDs and cannot prove omissions, attempts, or resources.

Required redesign: append-only typed journal is authoritative. Views request bounded projections with an omission cursor and aggregate counts; reports cite exact event/receipt IDs.

### F-226 — Critical — Recovery can project healthy scheduling without proving prior cleanup

On load, `runningPipeline`, `reviewing`, and `preparing` become `active` or `needsAttention`; no prior process inventory, incomplete effect, or checkpoint transaction is reconciled first.

Required redesign: recovery begins in `reconciling`, scans owned process/resource records, completes or rolls back interrupted effects, validates the last snapshot, and only then admits a new occurrence.

## 4. Unified runtime model

```swift
enum WorkloadKind: Codable, Sendable {
    case graph
    case iterative
    case scheduled
    case externalWait
}

enum InvocationKind: Codable, Sendable {
    case scheduled(scheduleID: ScheduleID, ordinal: UInt64)
    case manual(ownerCommandID: CommandID)
    case recovery(predecessor: OccurrenceID?)
    case verification(requirementIDs: Set<RequirementID>)
    case adaptiveReview(trigger: TriggerID)
}

struct WorkIntent: Codable, Sendable {
    let runID: RunID
    let contractDigest: Digest
    let workload: WorkloadKind
    let invocation: InvocationKind
    let strategyFingerprint: StrategyFingerprint
    let sourceRevision: RevisionIdentity
    let capabilityRequest: CapabilityRequest
    let evidenceRecipeIDs: Set<EvidenceRecipeID>
}
```

`WorkIntent` is immutable. The reducer, not a controller or model, decides whether it is eligible. One admitted intent creates one `OccurrenceID`; retries create new attempts under that occurrence and retain the same causal failure lineage.

## 5. Schedule contract

```swift
struct ScheduleSpec: Codable, Sendable {
    let scheduleID: ScheduleID
    let cadence: Duration
    let phaseAnchor: WallInstant
    let tolerance: Duration
    let missedRunPolicy: MissedRunPolicy
    let maximumCatchUp: Int
    let overlapPolicy: OverlapPolicy
    let resourceClass: ResourceClass
    let coveragePolicy: CoveragePolicy?
}

enum MissedRunPolicy: Codable, Sendable {
    case skip
    case coalesceOne
    case boundedCatchUp
}

enum OverlapPolicy: Codable, Sendable {
    case rejectNew
    case coalesceIntoRunning
    case queueOne
}
```

Invariants:

1. One schedule has at most one live occurrence lease.
2. The next ordinal derives from the journal, never from an array count or date.
3. Arming a timer is a disposable optimization; persisted schedule truth survives its loss.
4. Catch-up cannot exceed both `maximumCatchUp` and the current ResourceGovernor budget.
5. An Agent review cannot move a due time earlier unless a typed contract amendment authorizes it.
6. Failure backoff covers the entire pass → review → repair cycle, not only the deterministic command.
7. Equivalent failures require evidence novelty or a different strategy before any expensive wake.

## 6. Monotonic time and coverage

```swift
struct ClockReceipt: Codable, Sendable {
    let bootSessionID: BootSessionID
    let monotonicStart: UInt64
    let monotonicEnd: UInt64
    let wallStart: WallInstant
    let wallEnd: WallInstant
    let discontinuities: [ClockDiscontinuity]
}

enum IntervalDisposition: Codable, Sendable {
    case acceptedScheduled
    case acceptedInteractive
    case excludedManual
    case excludedSleep
    case excludedDowntime
    case excludedGap
    case excludedEmpty
    case excludedFailure
    case excludedCancelled
    case excludedBlocked
    case excludedUnverified
}
```

The coverage engine is a deterministic fold over typed receipts. It never reads UI status dates. A contract may require scheduled continuity; for that policy:

- only adjacent, successful, accepted scheduled occurrences contribute;
- manual/recovery/review/verification occurrences never contribute;
- sleep, reboot, app downtime, failed/cancelled/blocked/unverified work, and intervals with no owned execution are excluded;
- a gap larger than the contract’s explicit continuity tolerance splits coverage rather than filling it;
- every included interval names both bounding occurrence receipts and its exact formula;
- cumulative accepted time, current live attempt time, raw time, and excluded time by reason are shown separately.

The engine is generic: another contract may accept interactive intervals, but the disposition remains explicit and cannot be reclassified by a view or Agent.

## 7. Occurrence and output receipts

```swift
struct OccurrenceReceipt: Codable, Sendable {
    let header: ReceiptHeader
    let occurrenceID: OccurrenceID
    let invocation: InvocationKind
    let scheduleOrdinal: UInt64?
    let clock: ClockReceipt
    let processReceiptID: ReceiptID
    let telemetryReceiptID: ReceiptID?
    let checkpointReceiptID: ReceiptID?
    let evaluationReceiptID: ReceiptID
    let outcome: ExecutionDisposition
    let intervalDisposition: IntervalDisposition
}

struct CheckpointReceipt: Codable, Sendable {
    let header: ReceiptHeader
    let occurrenceID: OccurrenceID
    let schemaID: String
    let priorDigest: Digest?
    let contentDigest: Digest
    let atomicReplaceReceiptID: ReceiptID
    let recoveryProbeReceiptID: ReceiptID
}

struct TelemetryReceipt: Codable, Sendable {
    let header: ReceiptHeader
    let occurrenceID: OccurrenceID
    let nonce: Nonce
    let producerProcessReceiptID: ReceiptID
    let payloadDigest: Digest
    let schemaID: String
}
```

Receipt validation is deterministic. File paths, timestamps, exit codes, and Agent prose are observations; none alone is acceptance.

## 8. Lifecycle and cancellation

Common derived phases:

```text
draft → ready → scheduled → admitted → executing → evaluating
      → awaitingReview → accepted | rejected | blocked
pauseRequested/stopRequested → draining → paused/stopped
draining → cleanupFailed
startup → reconciling → ready/scheduled/cleanupFailed
```

Required stop protocol:

1. journal owner stop command and freeze new admissions;
2. revoke pending scheduler and resource leases;
3. cancel queue waiters and obtain cancellation acknowledgements;
4. signal owned process groups, await bounded TERM grace, then KILL if required;
5. verify exact PID/start-time descendants are gone;
6. close clock intervals with excluded disposition;
7. flush event journal and reconcile incomplete effects;
8. release workspace, capability, Agent, thermal, and power leases;
9. issue a quiescence receipt containing an empty ownership inventory;
10. only then project `paused` or `stopped`.

Closing the window and quitting the process are distinct commands. A user-selected background policy may retain admitted productive work, but screen lock never implies permission to disable sleep indefinitely. Renewable power leases require recent verified progress and release on thermal pressure, inactivity, pause, stop, or app shutdown.

## 9. Recovery protocol

Recovery never calls the workload first. It performs:

1. validate journal frames and last compact snapshot;
2. enter `reconciling` and inventory incomplete commands/effects;
3. reconcile process groups using persisted PID/start-time ownership;
4. validate or roll back incomplete checkpoint and integration transactions;
5. close unmatched clock segments as interrupted/downtime;
6. derive missed schedule ordinals and record their exclusion receipts;
7. apply the declared missed-run policy under resource limits;
8. validate contract, source revision, capabilities, and evidence expiry;
9. resume only through a new admitted occurrence.

No recovery path may silently set `active`, assume prior cleanup, or count offline time.

## 10. Watcher adapter boundary

The replacement `ScheduledWorkloadAdapter` may define only:

- exact executable/action request;
- input/output schema IDs;
- telemetry decoder;
- deterministic evaluation rules bound to requirement IDs;
- checkpoint codec and recovery probe;
- evidence recipes and resource-cost estimate.

It may not:

- own tasks, timers, process handles, or power assertions;
- directly update run status or accepted time;
- schedule an Agent turn;
- declare completion;
- silently normalize its contract;
- select reviewer identity;
- mutate files outside a transaction/capability lease.

This boundary preserves LoopForge’s generality. No product, industry, file-name, UI genre, programming language, or historical scenario vocabulary belongs in scheduler policy.

## 11. Projection and UI contract

Every run and node projection shows:

- cumulative accepted duration across all accepted attempts/rounds;
- current live attempt duration, updated from the current monotonic segment;
- raw duration and excluded duration grouped by reason;
- invocation kind and current schedule ordinal;
- next eligible wall time plus missed-run policy;
- current strategy fingerprint, attempt number, remaining budgets, and retirement state;
- owned processes/tasks/timers/capabilities and drain status;
- last accepted occurrence/evidence/checkpoint receipts;
- journal cursor and explicit omitted-event count.

The UI must never collapse cumulative and current-round time into one number. It must never animate a live timer when no eligible monotonic segment exists.

## 12. Low-thermal admission policy

The unified scheduler delegates admission to the ResourceGovernor:

- no fixed-frequency polling while a durable timer/event source can be used;
- one shared heavy Agent lane by default, with cost-weighted fairness;
- coalesce duplicate wake causes by causal fingerprint;
- defer nonurgent evidence/OCR/package work under serious thermal pressure;
- cap catch-up and retry bursts;
- write append-only small journal frames and compact off the main actor;
- renew power leases only during receipt-backed productive intervals;
- surface thermal deferral as an excluded interval, never a failure or active time.

## 13. Migration

1. Decode legacy watcher JSON into read-only `LegacyWatcherObservation` records.
2. Preserve raw bytes and all prose events as claims.
3. Treat `lastSuccessfulRunAt`, `totalRuns`, and old durations as unverified observations.
4. Do not synthesize occurrence, checkpoint, or coverage receipts from dates alone.
5. Require explicit owner adoption into a new task contract and schedule.
6. Start in `reconciling`; never auto-run a legacy watcher from `status.shouldSchedule`.

## 14. Required tests

At least 52 tests are required before replacing the existing path:

1. reducer transition and invalid-combination model tests (8);
2. occurrence idempotency, ordinal, overlap, and lease tests (6);
3. sleep/reboot/clock-shift/monotonic interval tests (6);
4. manual/recovery/scheduled time-disposition tests (5);
5. gap/tolerance/empty/failure coverage property tests (5);
6. missed-run skip/coalesce/bounded-catch-up tests (4);
7. cancellation-aware queue and awaited quiescence tests (5);
8. process descendant and power-lease cleanup native tests (4);
9. telemetry nonce/source/process binding tests (3);
10. checkpoint atomicity/digest lineage/recovery tests (3);
11. crash-point replay tests across every journaled effect (5);
12. Agent claim cannot complete or schedule tests (3);
13. migration never invents accepted time tests (2);
14. cumulative plus live node-time projection tests (2).

The suite must include injected cancellation at every `await`, randomized clock discontinuities, repeated equivalent failures, corrupted/truncated journals, stale telemetry, PID reuse, and thermal deferral. Exit zero is never the sole oracle.

## 15. Ratification gates

Implementation is accepted only when:

- Graph, Single Loop, and Watcher submit commands to the same reducer and supervisor;
- no controller maintains independent lifecycle truth or child ownership;
- every pass and Agent turn has an occurrence/attempt receipt;
- pause/stop/quit cannot project terminal state without quiescence;
- scheduled coverage is exactly reproducible from the journal;
- cumulative and live attempt time are simultaneously visible and correct;
- equivalent failures cannot generate an unbounded Agent/pass cycle;
- legacy recovery cannot auto-run or invent time;
- thermal/resource budgets are enforced by admission, not advisory copy;
- all required deterministic, property, crash, and native tests pass.

This specification is evidence for the target architecture. It does not authorize production-source modification before the 36,000-second forensic-analysis gate.
