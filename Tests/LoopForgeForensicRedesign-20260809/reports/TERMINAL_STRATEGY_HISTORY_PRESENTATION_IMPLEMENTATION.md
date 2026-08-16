# Terminal Strategy-History Presentation

Status: **implemented, focused reducer and presentation tests passed, exact package verified through the native UI**

Recorded: `2026-08-16T06:23:46Z`

## Finding

The historical stopped run did not retain an active execution attempt. Current
`RunReducer` replay consumes its receipt-proven quiescence and `runStopped`
tail, derives interruption, and leaves `KernelRunProjection.activeAttemptID`
nil. The raw `active` word in diagnostics came from
`ConvergenceStrategyLifecycle.active`, whose meaning is only “not retired.”
Once the run is terminal, that strategy is inert history.

This distinction matters because migrating or quarantining a consistent
immutable journal would destroy evidence to repair a UI vocabulary problem.
The journal was therefore left byte-for-byte intact.

## Implementation

`KernelConvergenceDiagnosticPresentation` now contextualizes strategy state
against `KernelRunPhase`:

- a non-retired strategy in a stopped run displays `unretired history · run stopped`;
- a non-retired strategy in a completed run displays `unretired history · run completed`;
- live active and waiting strategies retain `active` and `waiting for condition`;
- retired strategies remain `retired` in every phase.

Terminal non-retired history uses secondary emphasis, the accessibility ID
`kernel-terminal-strategy-history`, and help text stating that a terminal run
cannot execute the strategy. Live lifecycle rows retain a separate
`kernel-live-strategy-lifecycle` identity.

## Verification

- `KernelConvergenceDiagnosticPresentationTests`: 2 tests, 0 failures;
- receipt-proven stop reducer replay: 1 test, 0 failures;
- exact package-owned suite: 864 tests, 8 intentional environment skips, 0 failures in 82.321 test seconds;
- dirty-source snapshot: `0e42de365702528200d97a174537d1b05d0aaf3d1a99b5a6854dce87a5821da7`;
- signed executable: `0f26556b8924a7c0b2e3199506edad13e3379705314af0571ede523383d8c72f`, CDHash `31fc9c387b50cbf149d83bbe7790d64a9c0af031`;
- deep signing, ZIP, DMG, checksum, direct startup, mounted startup, mounted byte identity, detach, smoke, and cleanup passed;
- exact native diagnostics displayed `unretired history · run stopped · 1 attempt` in the [860×760 screenshot](../screenshots/packaged-loopforge-current-strategy-history-diagnostics-20260816T062100Z.png), SHA-256 `37f8a69e33ec6164d1f750aa7aac8dffd5bb97c5c4a794ace8a237116237f50a`;
- real UI quit left zero packaged processes and zero verification mounts.

EasyBusiness remained read-only on branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

This semantic presentation defect is closed. The full native visual matrix,
productive provider cutover, trusted Release containment issuer, clean-revision
rebuild, commit, and push remain pending. Final release is false.
