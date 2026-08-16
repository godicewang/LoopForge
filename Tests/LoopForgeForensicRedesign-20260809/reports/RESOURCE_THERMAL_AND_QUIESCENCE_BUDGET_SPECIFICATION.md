# Resource, Thermal, and Quiescence Budget Specification

Status: pre-implementation normative design. Production refactoring is still forbidden before the 36,000-second forensic-analysis gate.

## Executive conclusion

LoopForge currently has local optimizations but no host-wide resource authority. A non-local Graph can run three nodes; each can independently build, test, launch Simulator, scan a repository, decode/OCR images, perform Agent work, and integrate. Per-node resource brokers poll at 20 Hz. A Full Access permission scanner traverses other applications every four seconds. State mutations rewrite multi-megabyte checkpoints. A whole-task process activity disables idle sleep, while terminal UI can precede task joining and resource release.

This makes heat an emergent property rather than a governed budget. Closing a window, pressing stop, or seeing `stopped` cannot prove the host is quiet.

The redesign introduces one `RuntimeSupervisor` and one host-relative `ResourceGovernor`. Every task, process tree, timer, filesystem observer, local model, native runtime, GUI session, port/server, persistence job, report/OCR job, and power assertion is a typed lease. Scheduling requires both task authority and available host budget. Terminal state requires a replayable `QuiescenceReceipt`.

## Current measured and source-backed mechanisms

| Mechanism | Current value/behavior | Consequence |
|---|---|---|
| Graph worker concurrency | non-local Auto Graph up to 3; local provider 1; parallel candidates up to 8 | independence of objectives does not imply independence of host load |
| broker polling | one 50 ms loop per active node (20 Hz) | idle directory scans scale with node count |
| permission scan | every 4 s, main actor; regular/active apps, up to 2 windows × 64 nodes × depth 4 | broad repeated cross-app AX traversal |
| Loop timer | 5 s; full checkpoint after 15 s active segment | timer-driven 10.7 MB store rewrite |
| sleep assertion | `.idleSystemSleepDisabled` for whole outer task | blocked/retry/idle intervals can keep Mac awake |
| app quit | fixed 3.25–4 s grace, 50 ms polling | elapsed time substitutes for observed cleanup |
| Ollama | 5-minute keep-alive, one model/parallel request | local model may remain resident after useful work |
| Ollama stop | terminate immediate process, clear ownership immediately | no exit/descendant/unload proof |
| evidence | repeated fingerprint/recent scan plus decode/luminance/OCR | repeated heavy work with no content cache |
| stopped observation | LoopForge 0.0% CPU, zero direct children, all 37 task leases released | task was quiet at one instant, but architecture cannot issue durable proof |

No production source observes `ProcessInfo.thermalState`, low-power mode, power source, memory pressure, owned-process aggregate CPU/RSS, heavy-lane occupancy, or persistence byte rate as a scheduling input.

## Resource model

```swift
struct ResourceVector: Codable, Sendable {
    let cpuWeight: UInt16
    let memoryBytes: UInt64
    let diskIOWeight: UInt16
    let gpuWeight: UInt16
    let networkWeight: UInt16
    let guiSessionCount: UInt16
    let processCount: UInt16
    let timerClass: TimerClass?
    let powerClass: PowerClass?
}

struct ResourceLease: Codable, Sendable {
    let id: ResourceLeaseID
    let runID: RunID
    let attemptID: AttemptID?
    let capability: CapabilityDescriptor
    let reservation: ResourceVector
    let ownership: OwnershipMode
    let externalIdentity: ExternalResourceIdentity?
    let acquiredAt: MonotonicInstant
    let renewalDeadline: MonotonicInstant?
    let releasePolicy: ReleasePolicy
}
```

Resource/capability families are open and adapter-defined, not vertical product categories:

- process tree / command;
- local inference server and loaded model;
- native runtime/device and GUI application session;
- local server/port/socket;
- filesystem observer and timer;
- repository scan, hash, image decode, OCR, and report projection;
- persistence append/snapshot/compaction;
- network/API concurrency;
- credential/session access;
- power assertion;
- shared or exclusive external capability.

An adapter declares a conservative cost vector before execution and reports measured usage afterward. Unknown cost uses a high-risk default and cannot participate in speculative parallelism.

## Host-relative capacity

At startup and after material host changes, the governor records:

- logical/active processor count;
- physical memory and current pressure/available-memory sample;
- thermal state;
- low-power mode and power source where available;
- display/lock/sleep state;
- owned-process CPU, RSS, process count, and open resource leases;
- active heavy phases and recent p50/p95 cost by adapter signature;
- persistence/report bytes and main-actor time.

Default CPU-heavy concurrency capacity is host-relative:

```text
usableHeavyCores = max(1, min(activeCores - 2, floor(activeCores * 0.50)))
```

This is a planning ceiling, not permission to keep all usable cores saturated indefinitely. Adapter profiles reserve weights against a 100-point heavy lane:

| Generic phase | Initial CPU weight | Initial memory reservation | Exclusivity default |
|---|---:|---:|---|
| local large-model inference | 70 | model profile + context headroom | no build/OCR overlap |
| compiler/build/test | 60 | learned p95, conservative first run | one build family at a time |
| native runtime + GUI capture | 25 | learned p95 | one mutable session per identity |
| image decode/OCR batch | 25 | image-bound estimate | cache by artifact hash |
| repository scan/hash | 15 | bounded index estimate | one scan per tree generation |
| integration/rollback | 20 | bounded | exclusive target revision |
| journal snapshot/report | 10 | immutable snapshot size | defer under thermal/cleanup pressure |
| remote Agent/network wait | 5 | process baseline | bounded by provider/session limits |

Weights are calibration seeds. Measured overruns update future reservations through a deterministic bounded policy; they do not silently expand total capacity.

Owned resident memory is capped at the smaller of:

- 70% of physical memory; and
- currently available memory minus an 8 GiB host reserve.

If that result is below a requested reservation, the phase waits or selects an explicitly compatible lower-cost adapter. The system never starts a large local model because a keyword/category chose it.

## Adaptive thermal states

| State | New work | In-flight action | Power/model action |
|---|---|---|---|
| nominal | normal budget; no unmeasured speculative heavy overlap | sample and learn | eligible activity lease allowed |
| fair | heavy capacity reduced 50%; no speculative candidates/heavy compaction | finish bounded safe segment, shorten batch | unload idle model; tighten renewals |
| serious | no new heavy work; max one low-cost reconciliation lane | checkpoint, cancel/drain interruptible heavy phases | release sleep assertion unless cleanup needs it; unload owned model |
| critical | only safety cleanup/reconciliation | interrupt, reap, persist critical receipts, pause | release all non-cleanup resources and assertions |
| unavailable/unknown | conservative fair policy until calibrated | no speculative heavy overlap | visible diagnostic |

Low-power mode applies at least the `fair` concurrency policy. Memory-pressure warning blocks new memory-heavy work; critical pressure follows the serious/critical drain path. The governor uses hysteresis and a minimum cool-down window to prevent rapid oscillation.

Thermal throttling, cool-down, resource queueing, and idle wait never count as eligible Agent work time.

## Heavy-phase scheduler

1. Planner declares capabilities and conservative costs per node/attempt.
2. Kernel proves dependencies and task authority.
3. Governor atomically reserves all required dimensions or queues the attempt.
4. RuntimeSupervisor launches the adapter in a process group/session and records identities.
5. Usage sampling updates the lease and can trigger deterministic downgrade/cancel.
6. Completion/cancellation starts awaited cleanup while retaining ownership.
7. Governor releases capacity only after adapter/resource receipts prove release.

Node independence controls data/requirement scheduling; the governor independently controls host concurrency. Three ready nodes can therefore execute one at a time when they all need the same heavy lane, without changing their Graph semantics.

## Polling and timer policy

- Replace per-node 50 ms broker scans with one task/run IPC service or filesystem event source.
- If an event source is unavailable, fallback starts at 250 ms and exponentially backs off to 30 s while idle; a request wakes it immediately.
- Permission automation exists only while an exact expected-prompt lease is active, expires within a bounded window, and responds to app/window events rather than scanning the desktop for the whole task.
- One scheduler owns deadlines and wakes only at the earliest eligible time; Watchers do not each own independent always-live timers.
- UI refresh, persistence, report generation, and telemetry sampling use separate coalesced projections.
- Idle/stopped LoopForge has no repeating timer faster than 30 s and no polling service.
- Every timer/observer has an owner, lease ID, cadence, last-fired time, cancellation acknowledgement, and quiescence membership.

## Evidence and report load

Evidence work is content-addressed by target tree/artifact hash plus collector version:

- one repository index/fingerprint per tree generation;
- source excerpts and changed-path manifests derived from that index;
- image decode, luminance, OCR, geometry, and thumbnail results cached by image hash;
- baseline/candidate visual pairs reused across reviewers;
- report/HTML generation reads immutable projections and is debounced;
- cache misses reserve heavy-lane resources; cache hits consume only bounded projection budget;
- evidence invalidation follows revision/content hashes, never filenames or blanket rescan.

## Power and lock-screen contract

The user may authorize productive work while the screen is locked. This does not authorize indefinite forced wakefulness.

`ProductiveActivityLease` rules:

- acquired only for an executing eligible Agent/verification/integration segment or bounded cleanup;
- includes run/attempt identity, reason, resource reservation, and renewal deadline;
- renewed at most every 60 seconds from receipt-backed liveness and budget health;
- released during retry sleep, external blocker, user-input wait, thermal cool-down, empty queue, and idle report projection;
- narrowing/stop/pause revokes new work immediately and retains only bounded cleanup power;
- UI shows whether lock-screen continuation is active and why;
- the time ledger counts actual eligible intervals, not assertion duration.

## Process and external-resource ownership

RuntimeSupervisor retains every ownership handle until joined/reconciled:

- PID plus process start time, executable hash/path, process group/session, parent and known descendants;
- pipes/readers and inherited-descriptor state;
- ports/sockets and server health identity;
- native runtime/device ID and whether borrowed or LoopForge-created;
- GUI application/session identity;
- model/server ownership and loaded-model identity;
- launch agent/service identity when explicitly authorized;
- exact signals/actions and observed exit/release state.

Cancellation sequence is adapter-specific but normally requests graceful interrupt, then TERM, then KILL under bounded deadlines. A task handle is not removed until its value/termination acknowledgement is observed. Reparenting, PID reuse, or missing process handles produce `outcomeUnknown`/`cleanupBlocked`, not success.

Borrowed resources are never destroyed. The release receipt proves that LoopForge's own session/model/device transition was undone without terminating unrelated user work.

## `QuiescenceReceipt`

Terminal `paused`, `stopped`, application-exit readiness, and completed package handoff require:

```swift
struct QuiescenceReceipt: Codable, Sendable {
    let runID: RunID
    let requestedAction: TerminalIntent
    let journalSequence: UInt64
    let unjoinedTaskCount: UInt32
    let ownedLiveProcesses: [ProcessIdentity]
    let activeResourceLeases: [ResourceLeaseID]
    let activeTimersAndObservers: [RuntimeHandleID]
    let activeOutboxEffects: [EffectID]
    let activePowerAssertions: [PowerLeaseID]
    let persistenceFlushedThrough: UInt64
    let projectionSequence: UInt64
    let cleanupActions: [CleanupReceipt]
    let startedAt: MonotonicInstant
    let finishedAt: MonotonicInstant
    let result: QuiescenceResult
}
```

Success requires zero unjoined tasks, live owned processes, active leases, timers/observers, outbox effects, and power assertions; persistence and projection sequences must agree. A failed release remains visible with exact identity and blocks the terminal projection. Fixed elapsed grace is never proof.

## Quantitative budgets

Initial acceptance budgets, subject to measurement-based tightening but never silent relaxation:

1. Idle/stopped app sampled CPU p95 ≤ 0.5% over 10 minutes on the release machine.
2. Idle/stopped app owns zero children, managed external resources, broker services, permission scanners, and power assertions.
3. Idle/stopped repeating-timer cadence ≥ 30 seconds; expected steady-state disk writes = 0.
4. Coordinator overhead while Agents are network-waiting p95 ≤ 2% CPU and ≤ 0.25 core-second per wall-second over five minutes.
5. No more than one 50+-weight heavy phase runs under the default budget.
6. Owned resident memory stays within the host-relative cap; model context/reservation is included before launch.
7. Serious thermal response begins within one sampling interval and launches no new heavy work.
8. Critical thermal response reaches cleanup-only mode within five seconds, subject to safe interrupt boundaries.
9. Stop/pause blocks new effects at the next journal sequence and begins drain within 250 ms.
10. A cooperative run reaches quiescence within five seconds; a forced process-tree case within the declared escalation SLA, otherwise terminal remains blocked.
11. No idle filesystem poll faster than 250 ms; fallback reaches 30 seconds after sustained idleness.
12. Permission scanning has a maximum expected-prompt lease of 30 seconds and no whole-task background scan.
13. Evidence scan/OCR is not repeated for an unchanged tree/image/collector hash.
14. Lock-screen power lease renews only from eligible activity at intervals ≤ 60 seconds.
15. Persistence/report work satisfies the separate journal write-amplification and main-actor budgets.

## User-facing resource projection

Every active node/card displays:

- cumulative eligible runtime across all iterations;
- live eligible runtime for the current iteration;
- current phase and wait/throttle reason;
- reserved and measured resource class;
- active capability/process count;
- thermal/power policy action when throttled;
- cleanup/drain state and exact unresolved identity;
- source journal sequence.

Waiting for a heavy lane is not shown as Agent work. Strategy retirement/replacement preserves historical runtime while resetting only the live current-iteration clock.

## Required deterministic and native tests

1. three ready nodes request overlapping heavy build lanes; only budget-compatible work starts;
2. independent light node runs while unrelated exclusive target integration waits;
3. unknown-cost adapter receives conservative reservation;
4. measured cost overrun reduces later concurrency deterministically;
5. nominal → fair → serious → critical thermal trace;
6. hysteresis prevents thermal oscillation/restart storm;
7. low-power mode applies reduced capacity;
8. memory warning/critical pressure blocks and drains correctly;
9. local inference never overlaps prohibited heavy build/OCR combination;
10. owned model unload and server descendant reaping;
11. borrowed local model/server release leaves user service alive;
12. broker event wake plus exponential idle fallback;
13. no per-node polling multiplication;
14. expected permission prompt lease expires and scanner stops;
15. one scheduler manages 1,000 Watcher deadlines without 1,000 timers;
16. evidence cache hit avoids scan/decode/OCR;
17. tree/image hash change invalidates only affected evidence;
18. report projection is coalesced and cannot delay cleanup;
19. retry sleep and external blocker release power assertion;
20. lock-screen productive work renews lease and counts only eligible intervals;
21. pause races process completion without late running overwrite;
22. stop cancels, joins, escalates, and records every process identity;
23. resistant descendant exceeds SLA and terminal stays cleanup-blocked;
24. PID reuse and reparented child cannot be mistaken for a receipt;
25. borrowed Simulator remains booted; owned transition is restored;
26. port/server/GUI session cleanup joins quiescence inventory;
27. app quit waits on receipt rather than elapsed fixed grace;
28. crash recovery reconciles every durable live lease before new work;
29. 10-minute native idle/stopped CPU/process/timer/disk acceptance run;
30. packaged app lock/unlock, close-window, quit, relaunch, and stopped-state native verification.

## Implementation boundary after the forensic gate

1. Add generic resource vectors, lease identities, governor state, sampling interface, and pure scheduling policy.
2. Add RuntimeSupervisor ownership/join/reconciliation behind characterization adapters.
3. Replace broker and permission fixed polling with leased event-driven services.
4. Move process, model, native runtime, server, timer, persistence, and report work behind leases incrementally.
5. Add thermal/low-power/memory signals and deterministic simulated traces before live enforcement.
6. Change terminal projections to require quiescence receipts.
7. Add content-addressed evidence cache and heavy-lane reservations.
8. Verify native idle, active, stop, quit, and lock-screen behavior in the packaged app.

The governor remains general-purpose: it schedules declared capability costs and measured host state, never task vocabulary, product type, file name, or customer-specific exceptions.

