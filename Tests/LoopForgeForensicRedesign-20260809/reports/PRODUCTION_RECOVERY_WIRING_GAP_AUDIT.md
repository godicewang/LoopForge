# Production Recovery Wiring Gap Audit

Status: **registry, startup guard, and journal-first production enrollment implemented; native authoring and legacy cutover veto remain**

## Enrollment update — 2026-08-11T08:15:30Z

`KernelProductionRuntime` now gives the native application one registry shared
by startup recovery and an explicit `KernelRunEnrollmentCoordinator` retained
by `AppModel`. Enrollment accepts only an immutable compiler-sealed
`RatifiedTaskContract`, rejects read-only ambiguities before filesystem work,
creates and validates the hash-journal run before registry publication, and
persists exact ratification plus journal-frame evidence. A file-private,
non-serializable proof is required to commit a release registration; the raw
registration helper is compiled only for debug fixtures.

The production creator is deliberately not invoked by legacy task creation,
Graph resume, Watcher, or timers. Native source-span authoring and explicit user
confirmation still need to call the coordinator, and execution/controller
cutover remains vetoed. The current implementation and package receipts are in
`PRODUCTION_KERNEL_RUN_ENROLLMENT_IMPLEMENTATION.md`.

## Implementation update — 2026-08-10T22:32:23Z

The isolated registry and coordinator specified by this audit now exist and the
native application explicitly starts them. Single-loop work, parallel-candidate
integration, and legacy host-resource recovery wait behind the typed result;
any ownership, persistence, binding, quarantine, live-resource, or release
attention blocks agent/legacy-Graph work and automatic resume. Termination waits
for the bounded owner. An empty registry creates its private roots and is a
verified no-op. The full implementation and
remaining limits are recorded in
`WORKSPACE_MUTATION_RECOVERY_REGISTRY_AND_STARTUP_IMPLEMENTATION.md`.

The legacy Graph still has zero registration/call sites. Therefore startup and
production enrollment composition are closed without claiming controller,
dependency, completion, mutation, native-authoring, or UI cutover.

## Finding

The journaled workspace authority, runtime, outbox, and dispatcher are complete
source components but have zero production call sites. A source-wide call-graph
search finds their names only inside the four kernel implementation files; all
construction and dispatch calls are test-only. The production application still
starts only legacy host-resource recovery from `LoopController.init`, and task
resume continues through mutable `LoopTask`/`GraphLoopEngine` state.

The same audit finds zero production call sites for
`LegacyGraphKernelShadowAdapter` and `LegacyGraphShadowContractMapper`. The
shadow code correctly grants no authority, but it is not yet a persisted
production observation path either. Consequently, none of the new kernel facts
currently gates legacy scheduling, mutation, integration, completion, automatic
resume, or UI status.

This means the current package proves implementation integrity, not production
control. Connecting only `recoverPending()` at app launch would be unsafe: the
app has no trusted catalog telling it which run journals and outboxes exist,
which actor owns them, which host budget reconstructs their supervisor, which
workspace roots are authorized, or which task should be blocked when recovery
quarantines an effect.

## Required recovery boundary

Before production invocation, LoopForge needs a dedicated kernel-run recovery
registry with all of these properties:

1. registration is journal-first and exists before the first outbox enqueue;
2. every run binds exact run ID, actor identity, journal root, outbox root,
   workspace identity, host budget, schema, and registration digest;
3. journal/outbox roots are canonical descendants of one LoopForge-owned
   Application Support root, mode-restricted, non-symlinked, and distinct;
4. legacy tasks and Graph checkpoints cannot register themselves or infer a
   kernel actor/contract from prose;
5. startup has one recovery owner, a cross-process lock, a run-count ceiling,
   a per-run dispatch ceiling, and no timer polling;
6. the supervisor is restored from the exact journal head before dispatcher
   construction;
7. corrupt, missing, conflicting, or newer-schema registrations fail closed
   without opening a workspace;
8. every completion, quarantine, retry-budget exhaustion, and registry failure
   becomes a typed startup receipt and visible blocker;
9. automatic legacy task resume is vetoed while any registered kernel run is
   unresolved; and
10. application termination waits for the bounded recovery owner and cannot
    race another dispatch.

Only an explicitly registered new-kernel run may enter this path. Empty registry
startup must be a no-op. The old Graph must remain disconnected until the
separate contract compiler, receipt mapping, dependency/completion authority,
and UI cutover gates pass.

## Evidence

The production workspace-recovery call-graph log is
`/tmp/loopforge-production-workspace-recovery-callgraph.log`, SHA-256
`6f4424d36a4c901dee949f4bc1b62fcc978a06ffe0fc4c545791b71f7e655df1`.
It contains definitions only. The production shadow-call-graph log is empty,
SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

This was a read-only source audit. No EasyBusiness file, task state, lease, Git
state, or process was changed. No native UI retry was attempted while macOS
remained locked.

## Next implementation slice

Implement and fault-test the registry and a recovery coordinator in isolation,
including empty-registry production startup. Do not expose registration to
legacy Graph. Only after atomic registry/recovery receipts and termination
coordination pass should the app construct the coordinator at launch.
