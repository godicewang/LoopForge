# Kernel Production Execution Composition Implementation

Status: **typed worker composition seam plus exact confirmed-preparation enforcement, clock, runtime-fact, drain, and quiescence issuers implemented; native start and observer-to-completion cutover remain vetoed**

Recorded: `2026-08-11T21:50:33Z`

## Reachability finding

The production call graph contained two incompatible systems:

| Entry | Execution authority before this slice | Current disposition |
|---|---|---|
| Historical Auto Graph start/resume | Legacy `LoopController` / `GraphLoopEngine` | Permanently blocked before timers, agents, integration, or retries |
| New native Auto Graph enrollment | Compiler-sealed contract and hash journal | Enrolled only to `ready`; no worker start API |
| Single Loop | Mutable `LoopController` / direct `CodexRunner` | Still legacy; not represented as kernel cutover |
| Parallel Candidates | Mutable `LoopController` / `GraphLoopEngine` | Still legacy; not represented as kernel cutover |

The missing boundary was not another boolean in `LoopController`. New runs
needed a separate composition root that cannot see legacy task snapshots or
construct provider argv, environment, timing, or completion claims.

The native plan audit now closes that preparation prerequisite without adding
a start action. Ratification recomputes the sealed candidate digest, rejects
post-compile mutation, and retains every compiler-validated evidence recipe,
exact user-confirmed mutation/convergence ceilings, content-complete revision,
typed causal strategy, mechanical falsifiers, and requirement-owned plan in
the durable ready journal. A read-only typed readiness assessment reports zero
missing authority blockers from the exact durable registration, journal
sequence, and frame digest without appending a frame. The native diagnostics
sheet exposes readiness, but confirmation still creates no attempt or worker.

## Implemented boundary

`KernelProductionExecutionCoordinator` now accepts only a retained enrollment
and a typed `KernelExecutionPreparationRequest`. It requires the exact durable
ratified registration, the enrollment actor lineage, monotonic prepare/activate
ordering, and then performs:

1. reducer-preflighted plan, optional baseline, convergence budget, node
   authorization, and causal admission;
2. exact attempt activation and issuance of the non-serializable execution
   proof;
3. fresh journal open and supervisor restoration from the exact current frame;
4. construction of a private `JournaledProcessRuntime`;
5. return of a non-Codable `KernelProductionExecutionSession`.

Before step one, preparation must equal the retained plan, causal strategy,
prediction/falsifier sets, rollback revision, and convergence budget. A caller
cannot replace the confirmed mutation surface under an unchanged enrollment.

The coordinator has no type dependency on or call into `LoopController`,
`CodexRunner`, `GraphLoopEngine`, legacy task state, or mutable runtime ledgers.
The public session receipt exposes only the preparation receipt, activation
transaction, and reducer projection; it does not expose the non-serializable
activation proof. `KernelProductionRuntime.startDefault()` constructs the
coordinator from the same private
registry used by enrollment and recovery, and the native `AppModel` retains
that independent service.

## Session authority

The session owns the activation proof and raw runtime. It provides bounded
operations to:

- issue a journal-owned deterministic provider invocation;
- issue an invocation-bound, memory-only provider secret when the ratified
  profile requires one;
- construct the productive owned process lease internally and launch only via
  the typed provider path;
- join the exact admitted lease, parse the exact retained result using digest
  and nonce from the replayed provider-launch event, and derive disposition in
  the reducer.

The completion method accepts no lease, invocation digest, nonce, or proposed
disposition from its caller. These values are carried forward from accepted
journal receipts.

The session also privately owns a `JournaledRuntimeLifecycleAuthority` built
from the same journal, supervisor, and actor identity. It accepts lifecycle
intent plus fresh command/receipt identities, journals pause/complete/stop
before entering supervisor drain, derives the drain snapshot and cleanup plan
from live supervisor state, and can journal quiescence only after the
supervisor proves no live resources, failed releases, or queued cleanup. The
caller cannot supply clocks, resource sets, or a verdict. A failed second
journal write leaves productive admission closed rather than reopening work;
a duplicate journal receipt is rejected rather than misread as proof that the
new drain payload was persisted.

## Verification

- production enrollment/composition suite: **11 passed, 0 failed**;
- native enrollment/readiness flow: **3 passed, 0 failed**;
- compiler, authoring, and native-enrollment authority suites:
  **34 passed, 0 failed**;
- actor-substitution adversary: rejected before plan or attempt writes;
- lifecycle-focused suite: **92 passed, 0 failed**;
- exact strategy/plan preparation suite: **27 passed, 0 failed**;
- complete source suite: **695 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  processes: **0**.

Source identities:

- task contract: `53d451bd42dda4b24dae4efcc0d26b5293d306ff96f4527f044aba9e0b481f86`;
- task contract compiler: `f5efdaf1a66145be928b6d459201599b18ab66dead9288d57d9ec95054e3500f`;
- production execution coordinator: `0eb023c5803e39c426ff549ac3f06b539ad652ebe55b6b5a254fd6d983400c94`;
- execution preparation coordinator: `625d30cc1e89b0b00e4c46da23829a686a7b6180800a0bcff114acb10a2084d0`;
- journaled runtime lifecycle authority: `c897aa93569a64b10191c4d54c40cc9eff0435c4216eeb8fc056e2ef41ea8ea8`;
- production runtime composition: `3ef3f086e908e7f9c991bba67b1883ff777d50b7fd97bc592fc37dd0c305647e`;
- durable registration registry: `ec03de070a3b14370fa6af57a876c6808320a3969540616705a62c7877ffffe1`;
- native AppModel connection: `662900025156fcef7aa6e480c2e491c0029cb6c9286ffd28f0d7a511eef30013`;
- native app composition root: `def426e032d37f911980ce686015e1484a39d0518feb9a0e010d222b4578a0d2`;
- composition tests: `83eedf61504bff4eece3891b6060756f4498433f845468db77018c25d8991590`;
- unchanged legacy controller audit identity: `fa2293333a87df913df7e63548e174274b11eaa0a27f360dd59a3c2675e4c06b`.

## Remaining vetoes

This is a production-oriented worker composition seam, not end-to-end
controller cutover. Native plan authoring is retained, but no start action
invokes it yet.
The read-only readiness gate makes this an explicit typed product state rather
than a vague future-cutover label. It also exposed and repaired an intermittent
durable-identity mismatch: registry timestamps are now canonicalized to the
millisecond precision used by the snapshot codec before becoming registration
identity, so an immediate reload remains exactly equal without weakening the
comparison.
Verification, review, baseline, and visual-evaluation commands now require
non-Codable authority, so Release fails closed instead of accepting
caller-constructed durable receipt shapes; their real runtime issuers are not
implemented. A non-nil baseline in production preparation is explicitly
rejected until native design authority exists. Independent reviewer execution,
deterministic verification issuance, immutable visual candidate assembly/evaluation,
the missing integration issuers, final completion authorization, external
dependency observation, and cleanup execution across every resource type are
not composed into one recovered state machine. Single Loop and Parallel
Candidates still use the legacy controller. Current-source packaging, unlocked
native screenshots, commit, and push remain pending. EasyBusiness remained
permanently stopped and read-only.

Direct integration and completion injection is now closed: only the journaled
workspace runtime can mint apply/rollback transitions after live-lease
validation, and final completion requires a non-Codable run/sequence/authorizer
capability. Proposal, preflight, postimage-verification, independent-acceptance,
and final-authorizer production issuers remain absent.

Occurrence closure crosses a non-Codable command boundary whose only Release
factory is file-private to the clock-owning `JournaledOccurrenceRecorder`.
Runtime drain and quiescence now have a separate production authority composed
from the same journal and supervisor as the session; it owns clocks and live
sets, journals lifecycle intent first, and derives quiescence only from empty
supervisor state. External-dependency observation still has no Release issuer.
Durable journal replay schemas are unchanged.

Generic runtime facts are now equally provenance-bound. Admission, external
process binding, release, and cleanup-failure commands require non-Codable
authority. Their production factories require a token constructible only in
the journaled process runtime or journaled workspace-mutation lease authority;
binding accepts only the process token. This preserves journal-first crash
cleanup while preventing decoded supervisor receipts from creating live or
released ownership facts.
