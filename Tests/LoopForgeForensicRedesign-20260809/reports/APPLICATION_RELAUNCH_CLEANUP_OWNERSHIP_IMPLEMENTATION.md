# Application Relaunch Cleanup Ownership

Status: **cleanup-only ownership recovery for executing and interrupted-stop native runs passed; productive execution authority remains non-recoverable**

Recorded: `2026-08-16T03:20:51Z`

Companion verifier proof updated: `2026-08-16T04:05:14Z`

## Defect closed

LoopForge previously recovered only unchanged `ready` enrollments after a full
application relaunch. An `executing` or `stopRequested` journal could retain an
active attempt and exact process/resource evidence, yet the new `AppModel`
would hold no session responsible for normal-quit cleanup. The lower runtime
could reconcile an exact PID/start identity, but application composition had
lost the owner that was allowed to invoke it.

## Authority-preserving repair

`KernelApplicationTerminationSession` is now the only capability retained by
the application-wide termination registry. A live
`KernelProductionExecutionSession` conforms to it, but relaunch recovery
creates a separate `KernelRecoveredApplicationTerminationSession` with only:

- read-only cleanup-plan and kernel projections;
- exact receipt-bound cleanup preflight; and
- the shared stop, drain, cleanup, quiescence, and stopped transition.

The recovered actor has no non-Codable execution proof, candidate root,
provider preparation or launch method, mutation method, evidence/review method,
retry method, or completion-authorization method. Its
`JournaledProcessRuntime` is constructed without productive execution proof,
so decoded receipts cannot regain productive authority.

Recovery requires an exact ratified registry entry, nonempty retained actor
identity, matching run and contract identities, a hash-journal head, an
`executing` or `stopRequested` phase, one exact live attempt, and an executing
node that owns that attempt. The runtime supervisor is restored from the
journal-derived snapshot. Any mismatch rejects before a session is returned.

`AppModel` now examines every startup recovery report in those two phases,
including attention-bearing reports with live or failed resources. Successful
recovery retains the cleanup-only actor. Failed recovery records the run in a
separate fail-closed set: the run still counts as active and normal quit is
vetoed with an explicit ownership error instead of silently forgetting it.

Both continuously retained and relaunch-recovered sessions use one shared
termination implementation. This prevents later lifecycle changes from
creating a weaker recovery fork.

## Adversarial verification

- An executing read-only run was activated, observed through the real startup
  recovery coordinator, loaded into a new `AppModel`, and terminated to exact
  `stopped`/quiescent state. Its active attempt became `interrupted`.
- The relaunched model exposed no enrollment receipt or productive execution
  session receipt, proving cleanup recovery did not recreate ready or live
  productive authority.
- A retained `stopRequested` crash window with no runtime-drain frame was
  relaunched and resumed through the cleanup-only actor without replaying the
  stop command.
- A stopped journal rejected cleanup-session reconstruction.
- A deliberately stale executing startup report whose journal had already
  advanced to stopped could not reconstruct ownership; the new model retained
  a blocking recovery-failure sentinel and vetoed quit.

`NativeKernelEnrollmentFlowTests` passed 14 tests with 0 failures in 18.364
seconds. The exact package-owned complete suite passed 860 tests with 8
intentionally gated skips and 0 failures in 74.652 test seconds (74.703 wall).
The real Codex child bridge passed in 12.037 seconds.

## Package binding

The corrected signed package is bound to dirty-source snapshot
`7ca002e7a5fedee480c52b26b77f6c6a84d0b25cd7169538f165cada4cb3f19d`,
built at `2026-08-16T03:15:05Z`. Its executable is 26,092,176 bytes with
SHA-256 `d5c69f39b31d62e6053ef02b591f728fdfe26a91380432236b28ba61835f8593`
and CDHash `17f174f2d962cb77111c33d5697c998f3afa3b02`. Deep-strict signing,
exact source/test-manifest binding, ZIP integrity, DMG verification,
mounted-DMG byte identity for all three Mach-O files, bounded exact packaged
startup, and zero residual package processes or mounts passed.

Computer Use inspected the exact rebuilt package while unlocked, retained a
current-package screenshot, and performed a real UI quit. The historical
EasyBusiness task remained visibly stopped and untouched; zero exact packaged
or live provider-fixture processes remained.

EasyBusiness remained permanently stopped and read-only at branch
`codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status digest
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Remaining boundary

This closes application-level recovery of cleanup ownership, not productive
session reconstruction. Join-only resources still require their retained exact
in-memory handle, and an unbound admission intentionally remains in doubt. The
dedicated live production-session app-quit test is now closed; a dedicated
The companion live postimage-verifier app-quit test now passes; see
[Live Postimage Verifier Application Quit](LIVE_POSTIMAGE_VERIFIER_APPLICATION_QUIT_IMPLEMENTATION.md).
Productive provider
ratification, trusted Release containment or retained vetoes, the complete native
matrix, a clean-commit rebuild, commit, and push also remain pending. Final
release is false.
