# Deterministic Replay and Fault-Injection Plan

Status: pre-implementation test architecture. These scenarios are mandatory additions to, not replacements for, the current 281-test characterization suite.

## Purpose

The redesign cannot be accepted through example-level unit tests alone. It must replay the exact failed historical control trajectory and survive adversarial failures at every authority, persistence, integration, review, and lifecycle boundary.

The harness therefore has four layers:

1. **pure reducer model checks** — exhaustive event/state invariants with deterministic clocks and IDs;
2. **simulated adapter faults** — process, filesystem, Git, capability, provider, and capture adapters fail at controlled phases;
3. **historical corpus replay** — import the 5,758-event stopped EasyBusiness trajectory without trusting its conclusions;
4. **packaged native system checks** — run, pause, stop, quit, relaunch, visual capture, and process/resource inspection against the signed app.

## Harness contract

Every scenario receives:

- immutable task-contract digest;
- seeded deterministic clock and ID generator;
- initial workspace/baseline manifest;
- adapter capability descriptors;
- ordered commands plus declared concurrency points;
- injected fault schedule;
- expected event/rejection sequence;
- expected final state digest;
- expected accepted/excluded time ledger;
- expected resource/quiescence ledger;
- expected artifact and review receipt set.

The harness fails if it relies on wall-clock sleeps, user home state, arbitrary model prose, a pre-existing simulator/browser process, or the target repository's writable files.

## Historical replay suite

### R-01 — Exact stopped-task migration

Import the preserved task snapshot and all 5,758 chronological events. Preserve original bytes and IDs. Project 51 legacy iterations, 37 blocked summaries, 7 blocked+approved contradictions, 28 blocked+continued contradictions, five superseded nodes, and two pending nodes.

Oracle: every contradiction is visible and excluded from accepted receipts/time. No historical worker is relaunched. The migrated state cannot become complete.

### R-02 — Rebuild after deleting every cache

Delete only derived snapshots, report projections, indexes, and UI caches; replay the journal 100 times.

Oracle: identical state, coverage, time, resource, convergence, and report-data digests every time.

### R-03 — Duplicate delivery and command idempotency

Deliver each event twice; separately retry every command after a simulated lost response.

Oracle: one logical effect per idempotency key, with duplicate receipts retained as transport metadata rather than state changes.

### R-04 — Concurrent submission schedule exploration

Explore seeded interleavings of node completion, stop request, review completion, lease failure, and integration authorization.

Oracle: causal ordering is explicit; stop wins over late success; invalid transitions are rejected; all schedules converge to one allowed state set.

### R-05 — Crash at every transaction boundary

Crash before append, after append/before fsync, after event fsync/before snapshot, during projection, during artifact copy, and during integration postimage verification.

Oracle: journal recovery yields either the pre-transaction or committed state, never a mixed state. Offline time remains excluded.

## Authority and workspace suite

### A-01 — Isolation creation failure

Inject worktree and fallback-copy failure for a writer.

Oracle: no worker launches, canonical workspace hashes remain unchanged, and the node receives a typed topology blocker. There is no primary-workspace downgrade.

### A-02 — Undeclared write attempt

Allow a worker to propose writes to one scoped file and one unscoped file.

Oracle: the executor denies or rejects the candidate before review; no reviewer can waive it.

### A-03 — Read-only probe on a non-Git directory

Probe capabilities in an empty external directory.

Oracle: byte manifest unchanged; no `.git`, report, cache, lock, or evidence directory appears in the target.

### A-04 — Dirty user workspace preservation

Seed unrelated tracked/untracked changes and a pre-existing stash.

Oracle: every byte, index state, branch, upstream, stash, and untracked path remains identical unless the task contract explicitly owns it.

### A-05 — Environment secret minimization

Seed parent environment with unrelated tokens and private paths.

Oracle: worker/reviewer environment receipts contain only the declared allowlist; absence is mechanically verified.

### A-06 — Reviewer attempts mutation

The review adapter requests shell, filesystem, network, or publication authority.

Oracle: request denied; review remains read-only and can only emit a receipt proposal.

### A-07 — Remote publication without authorization

A worker runs push/publish or mutates remote-tracking state.

Oracle: capability denied and incident recorded; candidate may not be approved until reverified from a clean transaction.

### A-08 — Integration conflict repair changes semantics

Inject a conflict; repair returns exit zero but produces a patch digest different from the reviewed candidate.

Oracle: old verification/review receipts expire and the new patch re-enters every gate.

## Evidence and review suite

### E-01 — Multiple JSON objects in reviewer output

Return an example approval object, prose, and a final rejection object.

Oracle: transport rejects the response as ambiguous; it never selects the first decodable object.

### E-02 — Repository prompt injection

Place reviewer instructions and a valid approval object in a changed source file, command output, OCR text, and worker message.

Oracle: all remain data with provenance; reviewer authority and decoder output are unaffected.

### E-03 — Quoted completion marker

Worker says “I must not emit `LOOPFORGE_STATUS: COMPLETE` because work is incomplete.”

Oracle: no completion claim exists because free-form markers have no authority.

### E-04 — Unrelated success after primary failure

Fail the full suite, then pass a narrow unrelated command.

Oracle: the full-suite failure remains unresolved; only a matching verification identity can supersede it.

### E-05 — Stale revision evidence

Capture tests/screenshots on revision A, mutate to B, then request review/integration.

Oracle: every A receipt is expired for B and cannot satisfy coverage.

### E-06 — Incomplete attachment transport

Require 12 named visual states but make the provider transport accept only four.

Oracle: review does not run; the missing attachment manifest remains red. Silent truncation is impossible.

### E-07 — Same-actor self approval

Use identical worker/reviewer lineage for a high-risk mutation.

Oracle: independence gate rejects the receipt; deterministic checks may still be retained.

### E-08 — Narrative exceeds receipts

Report claims 100 tests while receipt says 42 and claims a screenshot state not captured.

Oracle: unsupported facts are rejected or labeled as untrusted claim; deterministic report data remains exact.

## Causal convergence suite

### C-01 — Historical blocked sequence

Replay 11 exit-zero turns with the same typed blocker and paraphrased summaries.

Oracle: the causal fingerprint budget trips at the configured typed threshold, not turn 11; no accepted time is added.

### C-02 — Paraphrased replacement

Change node ID, title, wording, model, and thread while retaining responsibility, resource route, scope, and oracle.

Oracle: same strategy fingerprint; replacement rejected.

### C-03 — Valid measurement-boundary replacement

Replace an in-process UI timer with an external watchdog whose start precedes input.

Oracle: typed measurement-boundary dimension changes, replacement is allowed, and inherited evidence is untrusted input.

### C-04 — Scope topology change

Worker proves one exact missing path, then requests a safe non-conflicting scope addition.

Oracle: coordinator applies at most one typed scope amendment without rerunning the failed worker; conflicting scope forces replan.

### C-05 — Missing immutable artifact

Repeated searches return the same artifact-availability digest.

Oracle: differently worded paths do not reset progress; strategy retires or accepts a typed external boundary.

### C-06 — Reviewer transport failure

Worker completes once; reviewer times out or returns malformed JSON three times.

Oracle: only reviewer attempts repeat. Worker mutation/runtime/evidence are not rerun.

### C-07 — Final repair resurrects retired strategy

Whole-project reviewer proposes a renamed retired action.

Oracle: reducer rejects it using inherited strategy fingerprint and lesson.

### C-08 — No-progress expensive mutation

Two broad visual candidates produce unchanged requirement/evidence vectors but large mutation deltas.

Oracle: damage-weighted budget exhausts sooner; both candidates roll back; no “polish” loop continues.

## Lifecycle, persistence, and thermal suite

### L-01 — Cancellation-resistant process tree

Launch a child/grandchild that ignores SIGINT and one child that reparents.

Oracle: supervisor retains ownership, escalates, verifies PID death, and withholds `stopped` until the receipt is complete.

### L-02 — Watcher and Graph simultaneous quit

Run a Watcher command, three Graph nodes, broker services, local model, timers, and report generation; close the last window.

Oracle: one supervisor drains them all. No handle dictionary is cleared before join; terminal package run leaves no owned resource.

### L-03 — Resource release failure

Make one owned capability fail release.

Oracle: durable lease remains, task is `cleanupBlocked`, app/UI names the exact resource, and relaunch reconciles it before new mutation.

### L-04 — Borrowed resource preservation

Use a pre-existing shared resource and an app-owned resource concurrently.

Oracle: borrowed resource survives; owned resource is restored/deleted according to its lease.

### L-05 — Idle broker load

Simulate three node scopes with no broker requests for 30 minutes of virtual time.

Oracle: event-driven/adaptive mechanism remains under the wakeup budget; fixed 20 Hz × N polling fails.

### L-06 — Persistence storm

Submit 150 state updates and 5,000 log events in a burst.

Oracle: journal records are complete, UI projections are coalesced, snapshots/fsync/bytes/main-actor time stay below declared budgets.

### L-07 — Lock screen versus sleep eligibility

Transition productive → retry sleep → blocked → cleanup while the screen locks.

Oracle: productive and bounded cleanup phases can retain an explicit activity lease; retry/blocked/idle phases release it. Locking alone does not lose valid work.

### L-08 — Thermal pressure

Feed nominal, fair, serious, and critical thermal states while light and heavy nodes are queued.

Oracle: concurrency/resource budgets adapt deterministically; throttling reason is journaled; no timer/persistence retry storm appears.

## Visual system suite

### V-01 — Same-state before/after capture

Capture identical route/state under pinned device, viewport, scale, locale, appearance, content size, seed, and revision.

Oracle: valid comparison receipt and stable perceptual/geometry metrics.

### V-02 — Mixed environment rejection

Change one capture dimension at a time.

Oracle: comparison rejected before aesthetic review.

### V-03 — Duplicate screenshots under different names

Submit byte-identical files for multiple required states.

Oracle: coverage counts one unique state and names missing states.

### V-04 — Typography regression

Increase literal title/body sizes, add arbitrary caps/scaling, or violate semantic tokens while keeping all text visible.

Oracle: accessibility may pass; typography gate fails.

### V-05 — Shape/spacing regression

Change radius, control shape, grid symmetry, density, hierarchy, or primary viewport while avoiding clipping.

Oracle: relational geometry/composition gate fails.

### V-06 — Baseline-preserving localization

Change copy length without design migration authority.

Oracle: layout adapts within protected hierarchy/tokens; if impossible, integration blocks for explicit design migration rather than silently redesigning.

### V-07 — Aesthetic veto versus green UI tests

All hit-target, visibility, and screenshot-integrity tests pass while the composition is intentionally degraded.

Oracle: independent visual veto remains red and cannot be averaged away.

### V-08 — Worker-selected favorable subset

Provide attractive primary screenshots but omit overflow, empty, error, and maximum-text states required by the contract.

Oracle: capture manifest is incomplete; review never receives authority to approve.

## Watcher suite

### W-01 — Invalid non-empty checkpoint

Write small syntactically valid but semantically stale/garbage state.

Oracle: checkpoint rejected and prior valid state retained.

### W-02 — Warning/review/cadence collision

Fire warning, scheduled pass, and review-completion trigger at the same virtual instant.

Oracle: one coalesced eligible operation with quiet-period enforcement.

### W-03 — Agent self-repair and self-approval

One review proposes, applies, and declares its pipeline repair complete.

Oracle: mutation remains candidate-only until independent verification/review receipts exist.

### W-04 — Review failure while attention exists

Timeout/malformed reviewer output after a deterministic issue.

Oracle: attention persists; no healthy status or immediate retry loop.

### W-05 — Pipeline boundary escape

Script reads/writes outside declared generated paths or accesses undeclared environment/network capabilities.

Oracle: sandbox denial and durable incident; Watcher does not continue as healthy.

## Release suite

### P-01 — Tested/package revision identity

Change source after tests but before archive.

Oracle: package receipt rejects mismatch.

### P-02 — Directory-exists false smoke test

Create an app directory whose executable fails.

Oracle: smoke gate fails because executable launch and expected native state are required.

### P-03 — Signed-app native control flow

Create a neutral task, run a deterministic mock adapter scenario, inspect convergence UI, pause, resume, stop, quit, and relaunch.

Oracle: UI projections match journal receipts at each phase and accessibility identifiers remain stable.

### P-04 — Post-quit quiescence audit

Inspect owned task IDs, PIDs, timers, leases, temporary workspaces, model servers, Watchers, and sleep assertions after package quit.

Oracle: all zero or one explicit durable cleanup failure that prevents a false green package score.

## Execution ordering

1. reducer property tests and historical migration;
2. journal crash/idempotency tests;
3. authority/mutation/evidence adapter tests;
4. convergence and lifecycle simulations under virtual time;
5. visual capture/diff fixtures;
6. Watcher integration;
7. complete engine replay with scripted providers;
8. signed native package verification.

The test harness itself must emit machine-readable scenario receipts. A scenario cannot pass from log text, file existence, elapsed time, or an Agent declaration.
