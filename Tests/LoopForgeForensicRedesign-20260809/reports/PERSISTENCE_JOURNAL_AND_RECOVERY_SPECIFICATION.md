# Persistence Journal and Recovery Specification

Status: pre-implementation normative design. Production refactoring remains forbidden until the 36,000-second forensic-analysis gate is reached.

## Executive conclusion

LoopForge currently persists a mutable UI-shaped object graph, not an authoritative causal history. Task state, retained prose, runtime counters, Graph topology, review conclusions, report metadata, and recovery flags live in one `[LoopTask]` snapshot. Controllers mutate that graph directly; `TaskStore` republishes it and rewrites the complete store. On relaunch, current-version heuristics mutate decoded history in place.

This design has four coupled failure classes:

1. **truth loss:** the last 30 seconds of streamed Graph evidence and any silently failed save can disappear;
2. **truth invention:** load-time heuristics can convert interrupted or failed states into new projections without receipt-backed facts;
3. **split brain:** task, Watcher, resource, report, and target-workspace state advance in separate files and side effects without one sequence boundary;
4. **load amplification:** UI publication and full-store persistence are the same operation, so historical evidence makes every new mutation more expensive.

The replacement is not merely “more backups.” It is a domain-neutral, single-writer, append-only transaction journal whose pure reducer owns state. Snapshots, indexes, HTML, and SwiftUI models are disposable projections.

## Measured current surface

Read-only inspection at this stage measured:

| Item | Value |
|---|---:|
| `tasks.json` | 10,734,766 bytes |
| `tasks.json.backup` | 10,734,531 bytes |
| task count | 2 |
| top-level task logs | 2,272 |
| Graph nodes | 19 |
| Graph-node logs | 5,486 |
| `watchers.json` | 902,184 bytes |
| `watchers.json.backup` | 902,192 bytes |
| resource registry | 16,604 bytes |
| LoopController mutation/log call sites | 106 |
| GraphLoopEngine mutation/log call sites | 151 |
| WatcherController mutation/event call sites | 20 |

The call-site counts are mutation surface, not an assertion that every path executes per turn. A successful `TaskStore.save()` nevertheless reads and decodes the full prior task store, writes the full prior bytes to a backup, encodes the full current array, and writes the full current bytes. With the measured store, one logical field change causes at least about 21.47 MB of full-payload backup/current writes, excluding temporary-file, metadata, allocation, and filesystem overhead.

## Existing defect bindings

This specification resolves already recorded defects rather than inventing duplicate IDs:

- F-018 / F-107 / F-163: full-store main-actor write amplification;
- F-094: silent task-store failure and unreadable storage presented as no tasks;
- F-095: 30-second non-durable Graph-log window;
- F-084: silent Watcher persistence failure;
- F-098: semantically unvalidated Watcher checkpoints;
- F-158 through F-166: cancellation, cleanup, and resource state not joined into a terminal receipt;
- F-170 through F-177: prose and truncated evidence used as lifecycle authority.

## Exact current hazards

### P-01 — Snapshot identity conflates authority and presentation

`TaskStore` is `@MainActor` and `@Published`. `update` mutates the in-memory `LoopTask`, refreshes `updatedAt`, and immediately calls `save` (`TaskStore.swift:4-6,65-70`). The same value is therefore:

- the mutable scheduler database;
- the SwiftUI projection;
- the recovery checkpoint;
- the report input;
- the log archive;
- the source for derived timing and completion fields.

A UI-friendly field update can incur durable I/O, while a persistence failure leaves the optimistic UI value visible.

### P-02 — Failed writes are swallowed after the UI already advanced

`TaskStore.save()` catches every error and returns no failure (`TaskStore.swift:341-352`). `WatcherStore.save()` does the same (`WatcherStore.swift:58-71`). There is no durable-generation receipt, dirty-state indicator, retry owner, terminal barrier, or scheduler veto. The comment that a later mutation will surface the error is not implemented.

### P-03 — Unreadable authority fails open

If both task snapshots fail, `TaskStore.load()` catches and sets `tasks = []` (`TaskStore.swift:197-339`). If the resource registry cannot be read or decoded, it initializes an empty scope/lease snapshot (`HostResourceLeases.swift:183-202`). The Watcher store also resolves unreadable primary and backup data to `[]` (`WatcherStore.swift:76-86`).

“Unknown ownership/history” is thereby displayed and scheduled as “nothing exists.” For host resources this can orphan an owned Simulator or allow a second acquisition without reconciling the first.

### P-04 — Recovery runs unversioned policy over historical facts

Loading tasks converts `pausing` to `paused`, `stopping` to `stopped`, any active state to resumable `paused`, reclassifies failures from the suffix of prose logs, rewrites titles, changes retired-model routing, and recomputes visual-audit requirements (`TaskStore.swift:208-335`). These changes are neither versioned migration events nor reversible transformations. A newer binary can reinterpret old history merely by opening the app.

### P-05 — Stream batching trades heat for causal data loss

Agent, command, and system Graph logs remain in `pendingGraphLogs` for up to 30 seconds (`TaskStore.swift:9-21,101-168`). They are visible through an in-memory merge but are not durable. An abrupt process exit can remove the exact output explaining a mutation or failure. The delayed task itself is also outside the run-wide quiescence inventory.

### P-06 — Bounded arrays erase evidence without a tombstone

Task, node, and Watcher histories discard their oldest entries after `maxStoredLogs == 2,000`. Persisted completion/status fields survive while the causal attempts, failures, or warnings that produced them can vanish. No digest, archived range, or compaction receipt proves what was removed.

### P-07 — Cross-file and external side effects have no transaction boundary

`tasks.json`, `watchers.json`, `HostResourceLeases/leases.json`, model settings, reports, worktrees, canonical Git changes, remote pushes, processes, and Simulator state advance independently. A crash between any two writes leaves no sequence number that says which combination is valid. “Atomic file write” protects one replacement, not the orchestration transaction.

### P-08 — No single-writer fence exists

Main-actor and actor isolation serialize one process, but there is no interprocess lock or generation fence. A second LoopForge instance or differently packaged build can read the same generation and later replace it. Last writer wins even when its state was derived from stale evidence.

### P-09 — Side-effect retry cannot be made idempotent from snapshots

After a crash, a status field cannot distinguish “effect not started,” “effect succeeded but acknowledgement was not saved,” and “effect partially applied.” Blind retry can duplicate an integration, remote push, resource acquisition, notification, or Agent turn; refusing to retry can strand legitimate work.

### P-10 — Backup validity has no causal meaning

The single backup is only the most recently decodable whole array. It has no generation, previous hash, reducer version, command identity, workspace revision, or resource sequence. It can recover bytes, but cannot establish which external effects correspond to those bytes.

## Authoritative storage topology

All authoritative orchestration data lives under LoopForge Application Support, never in the target repository:

```text
runs/<run-id>/
  contract/00000001.json
  transactions/
    000000000001-<transaction-id>.json
    000000000002-<transaction-id>.json
  artifacts/<sha256>
  snapshots/<last-sequence>-<state-hash>.json
  projections/current.json
  indexes/evidence.json
  quarantine/
global/
  capability-transactions/
  run-index.json
legacy-imports/<import-id>/
  tasks.json
  tasks.json.backup
  watchers.json
  watchers.json.backup
  leases.json
  manifest.json
```

`transactions/` is authoritative. `snapshots`, `projections`, `indexes`, reports, and UI models may be deleted and rebuilt. Artifact files are content-addressed and immutable. The run index is discoverability data, not lifecycle authority.

## Atomic transaction envelope

Each committed file contains exactly one command decision and its event batch:

```json
{
  "schemaVersion": 1,
  "runID": "...",
  "transactionID": "...",
  "commandID": "...",
  "expectedPreviousSequence": 41,
  "firstSequence": 42,
  "lastSequence": 45,
  "previousTransactionHash": "sha256:...",
  "reducerVersion": 1,
  "recordedAt": "...",
  "events": [],
  "outboxEffects": [],
  "payloadHash": "sha256:..."
}
```

Normative commit path:

1. acquire the run's single-writer fence;
2. validate `commandID` idempotency and expected sequence;
3. reduce the command against the current immutable state;
4. produce a complete event batch and outbox effects without performing them;
5. encode canonical sorted-key JSON to a same-directory temporary file;
6. flush the file and request full filesystem synchronization for authority-changing commands;
7. atomically rename to the final sequence/transaction filename;
8. synchronize the containing directory;
9. apply the already-committed batch to the in-memory reducer;
10. acknowledge the transaction and dispatch idempotent outbox effects.

No UI field, controller callback, timer, Agent response, or adapter result bypasses this path.

## Durability classes

| Class | Examples | Maximum unflushed interval | Rule |
|---|---|---:|---|
| `critical` | contract/authority change, mutation authorization, integration, remote publication, resource acquisition/release, pause/stop/completion | 0 | full file and directory synchronization before acknowledgement |
| `standard` | attempt lifecycle, verification/review result, strategy/progress decision, timer eligibility | 1 s | coalesce only within one causally independent run; preserve event order |
| `stream` | bounded Agent/process output chunks | 1 s or 64 KiB | append immutable chunks; final output receipt binds ordered chunk hashes |
| `projection` | SwiftUI refresh, HTML, indexes, thumbnails | no authority guarantee | debounce/adapt freely; always carry source sequence |

There is no 30-second loss window for causal Agent output. Very large raw streams may be immutable artifacts, while journal events record chunk order, byte counts, hashes, redaction policy, and truncation boundaries.

## Single-writer and stale-writer fencing

- One process-wide `RunJournalCoordinator` owns an advisory file lock and an instance UUID.
- Every transaction includes the writer instance, expected prior sequence, and prior hash.
- A process that loses the lock or observes a different generation becomes read-only and must rehydrate before submitting another command.
- Multiple UI windows and read-only report tools consume projections; they never become writers.
- Shared capabilities use a separate global coordinator journal so two runs cannot both claim exclusive ownership.
- PID alone is never a writer identity; include process start time, executable identity, and instance UUID.

## Pure recovery algorithm

On launch:

1. acquire read authority and enumerate run directories without mutating them;
2. validate transaction filenames, contiguous sequences, hashes, transaction payload hashes, and schema/reducer compatibility;
3. choose the newest valid snapshot whose state hash and journal prefix hash verify;
4. replay later transactions through the pure reducer;
5. rebuild and compare the projection; never trust a stale projection as input;
6. inspect unacknowledged outbox effects through typed adapters;
7. reconcile owned processes/resources using recorded immutable identities;
8. emit explicit recovery transactions for observed facts;
9. allow mutation only after contradictions and failed cleanup are resolved or explicitly authorized;
10. expose corruption/recovery state in the UI instead of presenting an empty store.

Opening the app never runs current-version business heuristics over historical facts. Schema migration is a pure, versioned transform from old event type to new event type, with input/output hashes and a reversible backup.

## Crash and fault matrix

| Fault point | Required recovery |
|---|---|
| crash before temporary transaction is complete | ignore/quarantine temp; prior sequence remains authoritative |
| crash after temp flush but before rename | ignore/quarantine temp; do not dispatch effect |
| crash after rename but before directory sync/ack | validate committed file; acknowledge only after recovery confirms it |
| crash after transaction commit but before effect starts | outbox dispatcher performs effect once using `effectID` |
| crash during an effect | adapter probes exact external identity; it never blindly repeats a non-idempotent effect |
| effect succeeded but receipt was not committed | reconcile postcondition, then commit recovered result bound to original `effectID` |
| gap, duplicate sequence, or previous-hash mismatch | stop at last verified prefix, quarantine tail, block mutation |
| corrupt snapshot | delete/rebuild projection snapshot from journal; authority is unaffected |
| unsupported journal schema | open read-only with exact upgrade requirement; do not coerce state |
| primary legacy snapshot corrupt, backup valid | import backup as an untrusted legacy claim and preserve both byte images |
| both legacy snapshots corrupt | show recovery-blocked state; never show an ordinary empty task list |
| resource ledger corrupt | block new managed-resource work; enumerate provider state and require reconciliation |
| writer lock lost | reject all writes from stale instance and rehydrate |
| disk full or permission denied | keep UI projection marked non-durable; stop new side effects and completion |

## Side-effect protocol

Every external effect has a typed lifecycle:

```text
effectPlanned
  -> effectStarted
  -> effectObservedSucceeded | effectObservedFailed | effectOutcomeUnknown
  -> receiptAccepted
```

The adapter contract requires:

- stable `effectID` and run/attempt/requirement identity;
- declared idempotency mode;
- exact precondition and expected postcondition;
- immutable target revision or resource identity;
- start/end monotonic and wall-clock timestamps;
- process/PID-start-time or remote request identity;
- output/artifact digests;
- reconciliation probe;
- rollback capability and receipt when applicable.

`effectOutcomeUnknown` blocks dependent mutation and completion. A model may propose recovery, but prose cannot choose between repeat, accept, or rollback.

## Legacy import without historical laundering

Migration is read-only with respect to the legacy files:

1. copy the exact primary, backup, Watcher, and lease bytes into `legacy-imports/<id>/`;
2. hash every byte image and record original path, metadata, app build, and import time;
3. decode primary and backup independently and retain all diagnostics;
4. import each legacy field as a `LegacyClaim`, not a modern receipt;
5. map prose logs to immutable archive artifacts plus indexed entries, preserving order and omissions;
6. mark completed/approved legacy nodes `legacyReportedCompleted` when modern verification, review, integration, or quiescence receipts are absent;
7. preserve contradictions such as `BLOCKED` plus approved as contradictions, not a chosen truth;
8. reconcile resource claims against current provider observations before scheduling;
9. replay the imported claims deterministically and compare the resulting compatibility projection to the old UI;
10. retain a rollback manifest until the user-owned data migration is verified.

Rollout may shadow-mirror legacy controller mutations into new commands and compare projections while the legacy path is still authoritative. It must never let two stores independently authorize side effects. After parity acceptance, the journal becomes authority and legacy JSON becomes read-only evidence.

## Snapshot and compaction policy

- Create a snapshot at a terminal lifecycle boundary, or after 1,000 transactions / 64 MiB of new journal data, whichever comes first.
- Build snapshots off the main actor from an immutable reducer value.
- Record source sequence, journal-prefix hash, reducer version, state hash, build duration, and byte count.
- Before accepting a snapshot, replay the same prefix independently and compare state hashes.
- Keep journal transactions authoritative after snapshot creation.
- Archive old raw stream artifacts only under an explicit retention policy that records digest ranges and tombstone receipts.
- Never delete failure, authority, mutation, verification, review, integration, resource, or quiescence receipts solely to meet a count limit.
- Defer compaction under serious thermal pressure, cleanup, integration, or active native verification.

## Projection contract

Each native UI and report model carries:

- `sourceSequence` and `sourceStateHash`;
- `projectionGeneratedAt`;
- `durabilityHealth` (`current`, `pending`, `degraded`, `recoveryBlocked`);
- any omitted range with digest/index reference;
- current run phase derived only by the reducer.

Projection refresh can be coalesced at 250 ms while visible and much more slowly when backgrounded. Persistence never calls `objectWillChange`, and a SwiftUI selection change never writes the run journal unless it is a user-intent command with product meaning.

## Quantitative acceptance budgets

Initial conservative budgets, to be validated on representative long histories before final ratification:

1. Critical transaction acknowledgement p95 ≤ 100 ms on the supported local filesystem, with no main-actor file I/O.
2. Standard event loss window ≤ 1 second; authority/lifecycle/resource event loss window = 0 acknowledged events.
3. Logical-to-physical authoritative payload write amplification ≤ 4× over a 30-minute active run, excluding explicit artifact bytes and filesystem implementation overhead measured separately.
4. Idle/stopped journal writes = 0 except explicit user actions, recovery, or bounded housekeeping.
5. A one-field runtime update is O(new event size), not O(total historical evidence).
6. Projection generation p95 ≤ 16 ms of main-actor publication work; encoding/scanning stays off actor.
7. Recovery of 100,000 transactions produces the same state hash on 100 replays.
8. Compaction never changes the authoritative hash chain and can be interrupted at every write boundary.
9. Disk-full, permission, corruption, stale-writer, and unsupported-schema faults visibly fail closed.
10. Terminal UI requires matching journal, projection, side-effect, resource, and quiescence sequences.

## Required deterministic tests

1. transaction append/idempotent command replay;
2. stale expected-sequence rejection;
3. two-process writer lock and fencing;
4. crash at each commit step;
5. partial/corrupt/gapped/duplicated/hash-mismatched journal tail;
6. corrupted and stale snapshots rebuilt from journal;
7. effect success before receipt and effect failure after start;
8. non-idempotent integration/push/resource reconciliation;
9. disk full and permission denial before and after UI projection;
10. primary/backup legacy decode matrix;
11. contradictory legacy approval/blocker preservation;
12. resource-registry corruption with live provider resource;
13. pending output stream crash at every chunk boundary;
14. 100,000-event deterministic replay and bounded memory;
15. snapshot interruption and compaction interruption;
16. cross-run exclusive-capability contention;
17. terminal-state rejection with pending/unknown effect;
18. main-actor and physical-write budget instrumentation;
19. UI projection staleness and source-sequence labeling;
20. read-only report/index rebuild from authoritative data.

## Implementation boundary after the forensic gate

The first production slice must add a journal package and characterization adapters without changing target-repository behavior:

1. pure IDs, commands, events, receipts, reducer, and canonical encoder;
2. transaction writer/reader with crash injection and writer fence;
3. legacy importer preserving byte-identical inputs;
4. shadow command mirror and projection-difference diagnostics;
5. one low-risk internal task path cut over after deterministic parity;
6. resource and process effects moved behind outbox/reconciliation;
7. Graph, Single Loop, and Watcher migrated incrementally;
8. UI and reports switched to source-sequenced projections;
9. legacy direct mutation APIs removed only after all ratified scenarios pass.

No prompt patch, backup rotation, debounce interval, or additional status flag is an acceptable substitute for this authority boundary.

