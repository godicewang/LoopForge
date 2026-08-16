# Application Crash Reconciliation

Status: **exact executing and stop-requested sessions now auto-interrupt after a full application crash; productive authority is not reconstructed**

Recorded: `2026-08-16T05:56:00Z`

## Defect closed

The preceding relaunch repair could reconstruct a deliberately narrow cleanup-only
owner, but startup still left that owner waiting for a later quit request. A full
application crash could therefore relaunch into a stale `executing` or
`stopRequested` projection even when the complete cleanup plan was exact and
receipt-backed.

## Fail-closed repair

Startup now reconstructs only the cleanup capability and immediately asks it to
reconcile after a full application crash. Normal quit and crash recovery share one
termination implementation, but use typed origins and disjoint durable command
namespaces: `native-quit-*` and `native-crash-recovery-*`. The crash path can only
append stop/drain frames, terminate or detach exact resources, journal their
releases, interrupt the live attempt, and establish stopped quiescence. It exposes
no provider, mutation, review, retry, result, or completion API.

Reconciliation begins only when the complete captured cleanup plan is executable.
An exact empty plan and an exact PID/start-bound process plan reach `stopped`, mark
the active attempt `interrupted`, and leave no live lease or handle. Ambiguous,
unbound, failed, or join-only ownership remains retained as a visible quit blocker;
the journal does not advance. If a later step fails after an exact process is
reattached, AppModel retains that exact cleanup-only session and native handle
instead of replacing it with a weaker abstract flag.

Native process admission itself rejects `.join` release policy. The adversarial
test proves that a native live process cannot be created in the unrecoverable
join-only state: admission is released and the runtime retains zero process, lease,
handle, or cleanup action. Generic non-process join-only ownership remains
fail-closed and requires its exact retained handle.

## Adversarial verification

- An exact empty-plan executing journal auto-interrupted on relaunch.
- A retained `stopRequested` journal without its drain frame resumed in the crash
  namespace and reached stopped quiescence.
- A stale startup report against an already-stopped journal produced no journal
  advance.
- A real productive provider was launched and its PID observed live. A new
  AppModel, without any productive-session handoff, consumed only the recovery
  report, reattached the exact PID/start identity, terminated it, journaled its
  release under `native-crash-recovery-*`, interrupted the attempt, and reached
  stopped quiescence.
- Native join-only process launch rejected before a child or retained lease could
  exist.

Focused results were 14/0 for `NativeKernelEnrollmentFlowTests`, 32/0 for
`JournaledProcessRuntimeTests`, and 44/0 for
`KernelRunEnrollmentCoordinatorTests`. The authoritative package-owned suite
passed **862 tests with 8 intentional environment skips and 0 failures** in
81.987 test seconds (82.040 wall).

## Package and forensic boundary

The signed package is bound to dirty-source snapshot
`fef6b857691e2353c744b11b43d6af3ab8c00cf8ba2f1f686049a923f73ec74a`,
built at `2026-08-16T05:51:43Z`. Its executable is 26,200,544 bytes with
SHA-256 `e2626e7828d1a4dfe5c07bc6729487838588d2f4aca1da2e979f3fb7e1cf0d10`
and CDHash `6584ac604aec29e5f43ba843e2289d21baefd503`. Deep-strict signing,
source/test-manifest binding, ZIP and DMG integrity, direct and mounted startup,
all-three-Mach-O mounted identity, detach, smoke, and zero retained packaged
processes or mounts passed.

EasyBusiness remained permanently stopped and read-only at branch
`codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

This closes safe crash auto-interruption; it intentionally does not reconstruct
productive authority. A trusted Release resident-memory containment issuer, a
productive provider backend and launch cutover, the complete current native
matrix, a clean-revision rebuild, commit, and push remain pending. Final release
is false.
