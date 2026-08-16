# Disposable Watcher Completion Chain

Status: **source integration proof passes; final release remains false**

Recorded: `2026-08-16T14:27:18Z`

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

## Boundary

This is a source-level integration fixture, not a claim that a live external
reviewer exercised semantic judgment and not a productive-provider
authorization. It also does not update the previously packaged application;
the exact current source must still be packaged, signed, hashed, and inspected
after the remaining Release authority work.

Two global gates remain:

1. resolved repository-generation telemetry after separately ratified
   mutation/isolation authority; and
2. Release containment and mutation-isolation authority.

