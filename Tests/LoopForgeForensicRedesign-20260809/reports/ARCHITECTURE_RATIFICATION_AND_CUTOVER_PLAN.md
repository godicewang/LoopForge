# Architecture Ratification and Cutover Plan

Status: **forensic architecture ratified for implementation after the 36,000-second gate**

## Ratification basis

The audit now contains 227 unique finding identifiers, 81 pre-existing mandatory acceptance rows, a complete 64-file/37,444-line source inventory, a 5,758-event stopped-task corpus, native Chinese/current-English visual baselines, process and thermal evidence, and normative specifications for contracts, authority, events, persistence, scheduling, convergence, mutation, evidence, review, visual gates, and quiescence.

The final cross-specification review found no requirement that justifies resuming the stopped EasyBusiness run or mutating EasyBusiness. It also found no legitimate vertical special case in the target kernel. Concrete tools remain adapters; all scheduling and acceptance policy is expressed through provider-neutral contracts, capabilities, receipts, risk, and evidence.

## Conflicts resolved

1. **Seven rollout slices versus eleven blueprint slices.** They are one dependency graph, not two plans. The cutover sequence below is authoritative.
2. **Watcher as trigger source versus workload adapter.** It is a scheduled workload adapter that emits typed observations; it owns neither lifecycle nor completion.
3. **Wall-clock dates versus monotonic time.** Wall time is presentation/calendar eligibility only. Elapsed time uses a boot-bound monotonic clock receipt.
4. **Shadow state versus dual authority.** Shadow mode compares projections only. It may never write back into legacy state or authorize effects.
5. **Backward compatibility versus fail-closed recovery.** Legacy bytes remain readable evidence, but legacy status/duration/prose never becomes new authority and never auto-resumes.
6. **Reviewer independence versus limited model availability.** Independence is enforced by actor lineage, isolated context, read-only capability, blind evidence order, and no worker-produced hidden context; different model/provider is desirable but not the sole proof.
7. **Atomic per-event files versus write amplification.** The journal uses small hash-chained frames in bounded segments, explicit flush classes, and off-main snapshots; atomicity is at committed frame boundaries.
8. **Immediate anomaly response versus convergence/thermal safety.** Critical observations may shorten eligibility only through a typed policy, but never bypass causal deduplication, resource admission, or the global attempt budget.
9. **Current dirty fixes versus clean-room rewrite.** The recorded dirty patch is migration input. New components are introduced side-by-side and call sites move deliberately; no reset, stash, or wholesale overwrite is allowed.

## Authoritative cutover order

### Gate 0 — Preserve and characterize

- verify the recorded dirty-diff hash before each overlapping edit;
- keep legacy tests as characterization, not proof of new semantics;
- add new tests before changing ownership paths;
- prohibit target-repository effects from shadow mode.

### Gate 1 — Pure kernel types and reducer

Introduce domain-neutral IDs, `TaskContract`, commands, events, receipts, `RunState`, `RunReducer`, and `RunProjection`. The reducer is pure and total. No existing controller is migrated until replay, rejection, and idempotency tests pass.

### Gate 2 — Journal and conservative import

Implement the single-writer hash-chained journal, bounded segments, snapshots, receipt store, recovery, and legacy importer. Legacy import produces observations/claims only. Fault injection covers torn frames, stale writers, corrupt snapshots, and crash replay.

### Gate 3 — Runtime supervisor and resource governor

Move process groups, async tasks, timers, capabilities, Agent turns, power leases, thermal admission, and quiescence into one owner. Stop/pause/quit become draining protocols and cannot report terminal state without an empty ownership receipt.

### Gate 4 — Task contract and requirement compiler

Freeze verbatim objectives, requirements, constraints, non-goals, baselines, authority ceilings, ambiguity decisions, and evidence recipes before mutation. Remove category/keyword inference from authority and acceptance.

### Gate 5 — Scheduler, occurrence, and time ledger

Add durable occurrence IDs, invocation kinds, missed-run policy, monotonic intervals, explicit exclusions, scheduled coverage, cumulative accepted time, and current live attempt time. Migrate Watcher timers only after clock, sleep, manual-run, and recovery property tests pass.

### Gate 6 — Transactional mutation and integration

Introduce content-addressed preimages/candidates, mutation manifests, compare-and-swap apply, rollback rehearsal, conflict re-entry, and separate publication authorization. User dirty/index state is a protected baseline.

### Gate 7 — Evidence, review, visual gates, and convergence

Introduce the evidence graph, omission manifests, strict envelopes, independent review receipts, visual baseline manifests, typography/shape/spacing gates, progress vectors, strategy fingerprints, durable budgets, and retirement lessons. Prose and aggregate scores lose lifecycle authority.

### Gate 8 — Incremental execution-path migration

Migrate Single Loop, then Graph attempt admission/integration, then Watcher scheduling. Each path reads `RunProjection` and submits commands; legacy mutable snapshots become compatibility views. A path is cut over only after old/new projection comparison and native lifecycle tests are green.

### Gate 9 — Truthful native UI and reports

Centralize design tokens and render contract, requirement, evidence, convergence, resource, cumulative/current/excluded time, and cleanup truth. Regress standard, accessibility, narrow-window, light/dark, and baseline-preservation states. Reports render receipts and claims separately.

### Gate 10 — Compatibility retirement and release

Disable legacy authority, run the full deterministic/property/fault/native suite, package/sign/hash the tested revision, verify real executable startup/use/quit/quiescence, migrate LoopForge-owned data with backup/rollback proof, then commit and push LoopForge only.

## First implementation slice

The first production slice is deliberately pure and side-by-side:

```text
Sources/LoopForge/Kernel/
  KernelIdentity.swift
  TaskContract.swift
  RunCommand.swift
  OrchestrationEvent.swift
  RunState.swift
  RunReducer.swift
  RunProjection.swift

Tests/LoopForgeTests/Kernel/
  RunReducerTests.swift
  RunProjectionTests.swift
```

It must not import AppKit/SwiftUI, spawn processes, inspect provider names, infer task categories, read target workspaces, or mutate existing stores. It establishes the invariant vocabulary before runtime integration.

## Stop-the-line conditions

Implementation pauses immediately if:

- an edit changes unrecorded user work or the EasyBusiness repository;
- a core type contains product/domain/provider vocabulary;
- a legacy field is silently upgraded into a receipt;
- a controller/view regains direct authoritative mutation;
- a retry path bypasses fingerprint/budget admission;
- pause/stop reports success before quiescence;
- a visual mutation lacks a pinned baseline and independent veto;
- a test asserts only status/prose/exit zero where a receipt is required;
- thermal/CPU work remains after quit without an owned visible failure.

## Acceptance rule

The architecture is ratified for implementation, not declared complete. Each cutover gate must produce revision-bound receipts, and all mandatory acceptance rows remain red until exercised by the corrected packaged app. The 72,000-second total-work requirement remains independent and mandatory.
