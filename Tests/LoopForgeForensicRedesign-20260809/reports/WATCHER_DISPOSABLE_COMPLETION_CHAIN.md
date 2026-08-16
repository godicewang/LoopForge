# Disposable Watcher Completion Chain

Status: **source, package, and isolated native proof pass; final release remains false**

Recorded: `2026-08-16T14:36:57Z`

## Closed gap

Commit `39ebb2ab6c9222afef79a3721982277560983ba3` closes the
operation-free live Watcher completion-chain fixture gap. “Operation-free”
here means that the proof does not load or mutate the user's persisted
Watchers, does not contact a live Agent provider, and does not touch a product
workspace. The controller still executes a real bounded subprocess pipeline
and its real verification command, but both operate only inside an XCTest
temporary directory that is removed by test teardown.

## Controller boundary

`WatcherController` now accepts a `WatcherAgentTurnRunning` dependency. The
ordinary application constructs `LiveWatcherAgentTurnRunner`, which preserves
the prior Codex/API/local readiness checks and calls `CodexRunner.runTurn`
with the Continuum Watcher watchdog. No production caller bypasses provider
readiness by default.

The seam exists so the controller—not merely its individual policies—can be
tested deterministically. The fixture supplies a scripted Agent boundary while
retaining the real controller state machine, `ProcessRunner`, manifest and
telemetry loaders, checkpoint hashing, verification subprocess, completion
policy, independent-review policy, report generator, and `WatcherStore` JSON
persistence.

## Executed chain

The new integration test performs one complete controller run:

1. A real Python pipeline writes fresh telemetry with `completed=true`, a
   current capture time, status `ok`, a declared progress signal, and a
   non-empty checkpoint label.
2. The same pass writes a non-empty JSON checkpoint. LoopForge hashes its
   exact bytes and creates a deterministic completion observation for pipeline
   revision 1, run 1.
3. A separate real Python verification command reopens telemetry and checkpoint
   and checks completion, status, checkpoint label, and completed-item count.
4. The scripted adaptive author writes a fresh assessment covering the exact
   `fixture-goal` anchor and returns the one allowed `COMPLETE` marker with
   lineage `scripted-author-thread`.
5. The controller forces the next selection to read-only access and starts a
   fresh reviewer lineage, `scripted-independent-reviewer-thread`. The fixture
   snapshots every regular file, including hidden `.loopforge` artifacts,
   before and after that turn and proves byte-for-byte equality.
6. The controller validates distinct author/reviewer lineage digests, exact
   pipeline and assessment digests, the completion-receipt digest, current
   checkpoint bytes, verification-plan digest, and goal coverage before it
   persists `completed`.
7. The generated clickable HTML report exposes independent assessment
   authority and the covered goal. A new `WatcherStore` instance reloads the
   JSON checkpoint; deterministic completion and current-checkpoint validation
   still pass after the persistence boundary.

## Verification

- Focused disposable-chain test: 1 executed, 0 failures, 0.131 seconds.
- Complete Watcher suite: 45 executed, 0 failures, 0.205 seconds.
- Complete source suite: 884 executed, 8 environment-gated skips, 0 failures,
  84.077 seconds.
- `git diff --check`: passed before the implementation commit.
- Commit patch SHA-256:
  `22a7fedc9e3cd3d1f005d3a0a45a0a3e778251764eb813c6a6c76422a34fa2d3`.

## Current package and native verification

The exact signed package was rebuilt from clean source revision
`253e1c0028312fbc7df4bc6aa6b6b1053b5ee741`; that revision includes the
implementation commit and its first evidence commit. Its source snapshot is
`76068cdad1486a5eb4ad038d058b0db0d8c7a5e818911c5d5af2d38680b7c6b4`.
The package-owned complete suite passed 884/8/0 in 81.975 seconds. Release
compilation, deep-strict ad-hoc signing, canonical provider self-test,
ZIP/DMG/checksum verification, exact source and package-test binding, and the
isolated executable startup probe passed.

The app executable SHA-256 is
`eb7b39651445e8444fc78911b79da8dd46cf9e802e74a9499fea46d1f2daf91e`
and its CDHash is `626f380880e45fd2d91443a622294ae774dba16f`. The ZIP SHA-256 is
`f687fe7122b558685465483c7d56e53fc15edf5d6402168e8159656502a8b86a`;
the DMG SHA-256 is
`28e6904adea2c48a5dbea02e69892cd0f9871cbfd391bc400d6eb1bec11a6f11`.

Computer Use inspected that exact app under `--isolated-inspection-profile`.
The accessibility tree exposed both the explicit non-productive release
classification and isolated-profile banner, an empty Watcher list, the
Authority & completion contract, and a disabled Build Watcher control. The
[1060×752 native screenshot](../screenshots/packaged-loopforge-disposable-watcher-chain-current-20260816T1435Z.png)
has SHA-256
`b4822488c205aebe491a531b02f9f44811705acac31102d428989a8c71214380`.

The persisted user Watcher store retained SHA-256
`a59ca5375c6ee3c78de63773df68b20e80106ef15ad1fd7b85776ba78a584d71`,
891807 bytes, and mtime epoch 1786885277 before and after inspection. Cmd-Q
left zero LoopForge, provider-harness, or sandbox-gate processes and zero
verification mounts. EasyBusiness retained branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, and NUL-delimited status
digest `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Boundary

This is a source-level integration fixture, not a claim that a live external
reviewer exercised semantic judgment and not a productive-provider
authorization. The current signed package remains explicitly non-productive;
packaging and native inspection do not manufacture the two missing Release
authorities below.

Two global gates remain:

1. resolved repository-generation telemetry after separately ratified
   mutation/isolation authority; and
2. Release containment and mutation-isolation authority.
