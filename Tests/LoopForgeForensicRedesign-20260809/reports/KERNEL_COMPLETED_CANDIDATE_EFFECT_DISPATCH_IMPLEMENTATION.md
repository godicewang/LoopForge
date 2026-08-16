# Completed candidate production effect dispatch

Recorded: `2026-08-14T09:35:03Z`

## Result

LoopForge's real startup recovery composition now takes the exact durable
completed-candidate apply request through the journaled mutation runtime and
filesystem executor. On a synthetic registered workspace, the production
coordinator dispatches the pending effect, writes the reviewed candidate bytes,
captures a content-complete postimage under the sealed policy, journals an exact
apply receipt, releases the exclusive workspace lease, and retires the outbox
entry. Restart recovery scans zero effects and does not re-enter the executor.

The resulting integration remains `appliedUnverified`. Startup telemetry now
reports that unresolved phase as requiring attention even though the effect
itself and its lease are clean. No verification, independent acceptance,
publication, or final-completion authority is inferred from a successful write.

## Systemic defects closed

1. Completed-candidate manifests bind the reviewed content-complete source
   revision, while the older executor recognized only an affected-path digest.
   The executor now independently recomputes both observations. The manifest's
   expected digest selects the matching observation; callers cannot downgrade a
   full-tree requirement to affected paths.
2. Source-revision operations carry permission bits such as `0644`, while
   legacy executor fixtures and recovery entries can retain full `st_mode`
   values such as `0100644`. File kind remains an independent CAS predicate and
   the executor compares only the permission portion, preserving both durable
   formats without weakening kind checks.
3. Prepared requests previously carried a completion timestamp from enqueue
   time. The journaled runtime now overwrites it with its live wall-clock
   observation immediately before executor entry. A crash-recovered artifact
   retains its original actual completion time, so replay remains byte-stable.
4. Successful dispatch with an `appliedUnverified` transaction previously could
   look clean. Recovery now counts every integration phase other than
   `independentlyAccepted` or `rolledBack` and keeps attention asserted.

## Verification

- The enrolled completed-candidate chain uses a temporary synthetic Git
  workspace. It proves exact dispatch, candidate bytes, candidate postimage
  attestation, runtime-owned completion time, `appliedUnverified`, lease release,
  completed outbox state, unresolved recovery telemetry, and zero-reentry
  restart replay.
- All 14 filesystem-executor/outbox tests pass.
- All 5 recovery-registry/startup tests pass.
- All 8 integration-state/runtime tests pass.
- The complete exact-source Swift suite passes 766 tests with eight intentional
  environment skips and zero failures in 1,960.324 test seconds (1,960.371
  wall).
- The production Release build passes in 112.08 seconds.
- Diff whitespace, owned-process cleanup, and the unchanged read-only
  EasyBusiness fingerprint pass.

## Still blocked

The applied candidate has not been postimage-verified by a newly activated
independent verifier and has not been independently accepted by the distinct
reviewer. The production rollback/failure composition for that next boundary,
resident-memory authority, native immutable design/visual/final authority,
legacy Single/Parallel retirement, current native walkthrough,
package/sign/hash, clean commit, and push remain pending. Final acceptance is
false.
