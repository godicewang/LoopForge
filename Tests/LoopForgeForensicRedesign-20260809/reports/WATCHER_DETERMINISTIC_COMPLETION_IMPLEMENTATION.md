# Watcher Deterministic Completion Implementation

Status: **implemented, current clean-package UI contract verified; operation-free live completion fixture remains pending**

## Forensic finding

Acceptance row I-06 was reachable in the production Watcher path. A writable
Agent could emit `COMPLETE` after the pipeline verification commands ran, and
the controller would immediately persist `status = completed`. That promotion
did not require the latest telemetry to say both `completed: true` and
`status: ok`; it did not bind the physical checkpoint bytes, require zero live
deterministic issues, cover every declared goal anchor, or retain a completion
receipt. A legacy or tampered persisted `completed` value could therefore look
authoritative after relaunch.

## Production retirement

Completion is now a four-stage, fail-closed protocol:

1. A successful bounded pipeline pass must emit fresh normalized telemetry with
   `completed: true`, `status: ok`, a capture time, and a non-empty checkpoint
   label. The runtime must have a successful exit, no consecutive failures, at
   least one recorded pass, and zero active issues.
2. LoopForge parses the durable checkpoint as a bounded non-empty JSON object
   and records its SHA-256 together with the exact telemetry SHA-256, pipeline
   revision, and run number in a typed completion observation.
3. After all declared verification commands pass, the adaptive assessment must
   contain no confirmed issue and must attach non-empty evidence to every
   explicit dashboard goal anchor. A typed receipt binds that assessment,
   verification plan, observation, and sorted goal coverage.
4. The fresh read-only adversarial reviewer receives the exact completion
   receipt and its digest. Its persisted independent-review receipt must bind
   the same completion receipt before native status, schedule, report, or
   notification can become completed.

Any non-complete review invalidates the prior completion receipt. A new pipeline
pass replaces the pending observation. Pipeline errors clear it. At startup,
LoopForge validates the full receipt chain and re-hashes the current checkpoint;
legacy, missing, stale, altered, or self-approved completion state is demoted to
`needsAttention` without resuming or mutating the external workspace. The
Watcher report now labels invalid completion as such and exposes the bound run,
telemetry, checkpoint, verification-plan, and goal-anchor evidence.

## Adversarial verification

Seven new tests cover the completion protocol and extend the Watcher suite to 42
tests. They prove rejection of empty/scalar/malformed checkpoints, incomplete or
degraded telemetry, blank checkpoint labels, unresolved issues, stale run
numbers, confirmed assessment issues, missing goal coverage, absent or tampered
completion bindings, missing independent approval, and legacy completed state.
Stable JSON-object checkpoint hashing and the fully bound positive path also
pass.

The complete source suite passed **529 tests, 8 environment-gated skips, and 0
failures**. Packaging reran the same 529-test suite, built the exact-source arm64
app, ZIP, and DMG, and passed deep signature, source/test-manifest, checksum,
bundled-tool, direct executable startup, and zero-process cleanup checks.

Package receipts:

- source snapshot: `e3c8cbfd323ffece35f55bda06693b91fb6bf3edf484c4105d8c906185dbe2dc`
- executable: `ae8fb93dfba3a32a5941e367d01e6ba0f5f1cd125cd4620295edfa22d2e4e5de`
- ZIP: `fcc8edb1e024e78e27368e914a4bc7929af040e29e19a26a1c4756eeeb764d44`
- DMG: `55dd772854cf9e5ccb7480e840d0a0d84d1a16072db62673dea1e2468a0b5ed6`
- package test log: `8f6f773daa4a031672829dcd8eab1378fc04dc7422f95907646e03c7b7ed29dd`
- CDHash: `b3d8b73b6aa7d29cb58b2c44e81a09da895d72e7`

The initial targeted compile exposed a missing explicit Swift getter return. It
was corrected, and that failed run and its time are excluded from the strict
ledger.

## Boundary

This advances I-06 at source/package level and removes marker-only completion.
It is not final acceptance: current unlocked native Watcher screenshots, legacy
kernel cutover, G-08, J-04, clean commit, and push remain pending. EasyBusiness
remained stopped and read-only.

## Current native contract

Clean commit `0a40f5d` makes the deterministic receipt chain and marker-only veto
explicit in the Watcher composer and guide. Source and package-owned suites
passed 878/8/0, and the signed package displayed those rules with Build Watcher
disabled. The launch resumed a persisted unrelated Watcher, so the operational
walkthrough is not claimed as read-only; see
`WATCHER_AUTHORITY_NATIVE_CONTRACT.md`. A future live completion-chain exercise
must use an explicitly disposable fixture after all persisted Watchers are
paused. Final acceptance remains false.
