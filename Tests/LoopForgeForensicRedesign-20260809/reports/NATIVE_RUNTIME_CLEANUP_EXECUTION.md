# Native Runtime Cleanup Execution

Status: **exact live-process cleanup, cleanup-only relaunch ownership, live-provider quit, and live-verifier fail-red quit passed; ambiguous ownership remains retained; clean commit and push remain pending**

Recorded: `2026-08-16T04:05:14Z`

## Defect closed

The prior normal-quit boundary correctly refused to publish quiescence while a
native session retained resources, but it could only veto a nonempty cleanup
plan. It had no receipt-owned path to execute the supervisor's exact
`join`/`gracefulThenTerminate`/`detachOnly` actions. A healthy, fully identified
owned process could therefore keep the application open indefinitely even
though the journal retained enough PID/start identity to recover and terminate
it safely.

This was a convergence defect: the supervisor could describe the required
closure, but no component was responsible for completing it and presenting
durable release receipts back to the reducer.

## Runtime repair

`JournaledProcessRuntime` now performs a read-only termination preflight that
requires exact equality between supervisor live leases and journal live
leases, no queued leases, no failed releases, and no in-doubt resources. Every
cleanup action must match the lease's resource, lease, ownership, release
policy, and resource kind. Graceful process cleanup additionally requires an
exact positive PID plus process-start identity; join cleanup requires the
exact retained in-memory handle; borrowed detach requires a stable external
identity.

After all retained sessions pass preflight, each session journals stop/drain,
freezing new productive admissions, and executes only the unchanged captured
plan. Owned process trees are reconciled by exact PID/start identity and
terminated as process groups; an exactly absent process receives a durable
absence release. Join-only resources use a bounded exact-handle join, and
borrowed resources receive a logical detach release. Any plan change,
identity ambiguity, failed release, missing handle, or remaining action aborts
termination and preserves ownership.

The executor returns a typed receipt containing the run, request nonce, exact
planned actions, durable release-receipt identities, and remaining actions.
Only an empty remaining plan may advance the session to journaled quiescence
and stopped state. Multi-session application quit preflights every session
before mutating any session, preventing partial shutdown when a later session
has incomplete ownership.

Postimage-verifier cleanup has a dedicated fail-red path. It retains exact
activation/launch/lease containment, terminates the exact process group,
captures output within the existing ceilings, and records a
`runtimeCleanupTermination` containment disposition. A cleanup termination
cannot be mistaken for a successful verification result.

## Full-application relaunch ownership

Startup now reconstructs a cleanup-only actor for exact ratified journals in
`executing` or `stopRequested`. The actor receives a supervisor restored from
the journal and a process runtime with no productive execution proof or
candidate root. It exposes only cleanup preflight, projection, and the same
shared termination implementation used by a continuously retained production
session. It cannot prepare or launch a provider, mutate, review, retry, or
authorize completion.

Attention-bearing runs are included. If any registry, journal, active-attempt,
node, actor, contract, phase, or supervisor identity cannot be matched,
`AppModel` retains a recovery-failure sentinel and vetoes normal quit rather
than dropping the run. Executing-state, interrupted stop-request, stopped-state
rejection, and stale-evidence quit-veto paths passed. Details are in
[Application Relaunch Cleanup Ownership](APPLICATION_RELAUNCH_CLEANUP_OWNERSHIP_IMPLEMENTATION.md).

## Adversarial boundaries

- An exact live `/bin/sleep` process is recovered, group-terminated, durably
  released, and removed from the adapter, supervisor, and journal.
- A new runtime/supervisor reconstructed from the journal recovers the same
  process by exact PID/start identity, terminates it, and closes ownership.
- An admission that never received a process binding fails preflight. Its
  lease remains in both supervisor and journal; the runtime does not scan for
  or guess a process.
- An unchanged cleanup plan is required at execution time. Preflight does not
  itself consume, detach, or release anything.

## Verification

- A dedicated end-to-end test launches a ratified productive V2 provider,
  proves its PID live, gives the session to the real AppModel termination
  coordinator, and proves exact termination, durable release, interrupted
  attempt, empty leases, and stopped quiescence. It passed in 1.127 seconds
  focused and 1.108 seconds inside the package-owned suite.
- A second end-to-end test launches a real postimage verifier through the same
  retained production session, proves its PID live, and exercises the real
  application quit path. The release carries exact managed termination plus
  `runtimeCleanupTermination`, no natural exit, no postimage result authority,
  a failure digest, empty leases, and stopped quiescence. It passed in 2.634
  seconds focused and 1.306 seconds inside the package-owned suite.
- Exact package-owned complete suite: 861 executed, 8 intentionally gated
  skips, 0 failures in 80.610 test seconds (80.660 wall). The real Codex child
  bridge passed in 16.308 seconds.
- Exact dirty-source snapshot:
  `3686f6594a418ac4743cb14d8faddaa62b9ea24c15297a748984bf23d074f3f9`.
- Signed executable:
  `3541c91dea36e7805cc4a1f06eed96932ec1dffe5ee5723d5ff673d1e48e10dc`,
  CDHash `cc045adbca8e8a6027303bea621d43b75dc8ce62`.
- Deep-strict signing, source/test manifest binding, ZIP/DMG checksums,
  mounted-DMG byte identity for all three Mach-O files, direct and mounted
  exact startup, detach, and zero residual packaged/provider processes passed.

The current change has no visible UI effect. The preceding exact package was
inspected with Computer Use while unlocked and retains its hash-bound
[historical screenshot](../screenshots/packaged-loopforge-current-live-production-quit-package-20260816T031933Z.jpeg).
That image is not relabeled as the current package. Direct and mounted startup
of the new signed package passed and left zero exact packaged processes or
mounts.

EasyBusiness remained permanently stopped and read-only at branch
`codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status digest
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Remaining boundary

The exact runtime and `AppModel` now recover cleanup ownership after a full
application relaunch, but they deliberately do not reconstruct productive
execution authority. Join-only resources remain recoverable only while their
exact handle is retained, and an admission lost before binding intentionally
remains in doubt.
The dedicated live-provider and live-postimage-verifier retained-session quit
tests are now closed. Productive backend ratification, trusted Release
containment or retained vetoes,
the complete native matrix, clean-commit
rebuild, commit, and push remain pending. Final release is false.
