# Fail-Closed Control-Plane Retirements

Status: **implemented and regression-verified; final clean commit/native matrix pending**

## Defects retired

Three remaining acceptance contradictions were reachable in production code:

1. a healthy Continuum Watcher review scheduled its next pipeline at the same
   instant, allowing an immediate self-reinforcing review loop;
2. legacy Graph decision decoding searched arbitrary prose for a balanced JSON
   object, so examples, markdown fences, multiple objects, or trailing semantic
   text could be treated as the authoritative decision;
3. the package startup check had only a positive receipt and no automated proof
   that a startup crash is rejected or that a surviving child is reaped.

## Implementation

`WatcherPostReviewSchedule` now schedules an unfinished review no earlier than
the validated Watcher cadence, clamps malformed zero cadence to the policy's
60-second minimum, preserves a later failure backoff, and returns no next run
for a completed Watcher. An agent review can no longer enqueue a fresh pipeline
at `now`.

`GraphLoopEngine` now accepts exactly one trimmed top-level JSON object as the
entire transport envelope. It rejects prose containing JSON, markdown fences,
two valid objects, and any trailing semantic payload. Missing legacy optional
repair fields remain a separately documented compatibility behavior; transport
strictness no longer attempts to guess which embedded object the agent meant.

The package smoke path now calls a reusable executable-startup probe. A real
negative fixture executes a program that exits with status 7 and proves the
probe rejects it. A real positive fixture stays alive beyond the bounded probe,
writes its PID, and proves the trap terminates and reaps it before returning.

## Verification

- Watcher focused suite: 30 passed, 0 failed;
- strict Graph envelope focused tests: 2 passed, 0 failed;
- startup crash/reap fixture: 1 passed, 0 failed;
- complete source suite: 517 executed, 8 environment-gated skips, 0 failures;
- packaging-owned suite: 517 executed, 8 skips, 0 failures;
- exact signed packaged Mach-O startup: passed;
- residual packaged process count: 0.

The current package source snapshot is
`7146c8abddaa1a8ddfc36bd4aea46acda699a9f58bc06c239c113e7e949d8750`.
EasyBusiness remained stopped and read-only.

## Boundary

These receipts advance E-01, I-04, and J-07 at source/package level. They do
not create final acceptance: the worktree remains dirty, current native visual
proof is blocked by the latest known lock-screen state, legacy cutover remains
incomplete, and no clean commit or push receipt exists.
