# Native App Execution-Session Cutover

Status: **explicit native read-only activation now reaches the production execution session; mutation activation and provider launch remain receipt-gated**

Recorded: `2026-08-15T16:00:57Z`

## Result

The real `AppModel` now retains live non-Codable
`KernelProductionExecutionSession` capabilities by run identity and exposes
only their proof-free receipts. The native diagnostics sheet presents an
explicit **Activate Native Attempt** action only for the exact latest enrolled
run and enables it only when the journal-owned readiness assessment contains
no blockers.

`KernelProductionExecutionCoordinator.activateNativeEnrolledRun` accepts only
the enrollment receipt, an optional live design-baseline authority, a fresh
canonical UUID nonce, and the user-action time. It reconstructs the exact
plan, unique dependency-free node, causal strategy, predictions, falsifiers,
rollback revision, convergence budget, evidence-derived verification cost,
external-effect count, actor, and command graph from the unchanged ratified
journal. A changed head, malformed action identity, ambiguous initial node,
missing design authority, or missing readiness authority rejects before
preparation.

Native authoring now also respects an explicitly selected Read Only worker:
the displayed and ratified contract has no writable scopes, zero changed-file
and changed-byte authority, and zero convergence mutation cost. This provides
one honest production activation route without weakening mutation safety.
Workspace-authorized contracts remain blocked by the pre-apply isolation and
journaled mutation-preparation gates; an explicit activation attempt leaves
the journal unchanged and creates no legacy task or worker.

## Verification

- the six native enrollment/cutover tests passed **6/0** in **6.195 seconds**;
- the positive native path enrolled a read-only contract, reported zero
  readiness blockers, activated the production session, and projected the
  exact journal as `executing`;
- the mutation-capable path retained both authority blockers and did not
  append a preparation or start frame;
- a caller-selected non-UUID action identity rejected with
  `invalidRequestIdentity` and preserved the exact journal projection;
- no legacy `LoopTask`, `LoopController` worker, or Graph worker was created;
- the exact source suite passed **816 tests**, with **8 intentional skips** and
  **0 failures**, in **60.187 test seconds**;
- the package-owned suite passed **816/8/0** in **61.069 test seconds**;
- the real Codex child/Responses bridge passed in **13.822 seconds**;
- non-DEBUG arm64 Release built in **104.58 seconds**;
- source snapshot:
  `02722bd6c8f2c02aacd4477572ff2cfd1c274249f17f3349dfadfa2a972af85a`;
- packaged LoopForge SHA-256:
  `d03464f19d7e6de8b0fe9a9b7bf112ea895fd9549f3f3a32be007c45709c2b23`;
- deep-strict signing, ZIP, DMG, checksums, embedded source/test binding,
  exact packaged-Mach-O startup, and zero residual packaged processes passed.

## Boundary

Activation starts the exact reducer attempt and constructs the production
session, but it deliberately does not launch a provider. Provider launch still
requires the session-owned executable, lease, process-binding, sandbox, and
runtime request chain. Mutation-backed execution still lacks the complete
native isolation/preparation issuer and remains vetoed. Current unlocked native
screenshots, legacy Single/Parallel retirement, a clean-commit rebuild, commit,
and push remain pending.

EasyBusiness remained stopped and read only at
`2ae40452e6d8661c46db466c43ea40bba3bfab04` with unchanged newline-delimited
status fingerprint
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false.
