# Workspace Mutation Recovery Registry and Startup Guard

Status: **implemented, production-started, and regression-tested; legacy cutover remains vetoed**

## Closed production gap

The native application now explicitly starts one bounded new-kernel recovery
task before agent work. The durable registry lives under LoopForge-owned
Application Support storage and binds each admitted run to its exact run ID,
actor identity and lineage, workspace identity and canonical root, registry-
derived journal/outbox roots, host budget, dispatch ceiling, schema, and
registration time. The snapshot is digest-sealed, atomically replaced,
cross-process locked, permission restricted, capacity bounded, and rejects
symlink entry, path traversal, storage overlap, duplicate conflicts, malformed
identity, oversized batches, and tampering.

The recovery coordinator acquires a separate nonblocking cross-process owner,
restores a pristine supervisor from the exact run journal, verifies every
outbox workspace/preimage/root binding before runtime construction, and runs
one sequential pass with a 32-run launch ceiling and a per-registration batch
ceiling no greater than 64. It has no timer and accepts no legacy task or Graph
input. Missing workspaces, corrupt persistence, restore rejection, binding
conflicts, quarantines, dispatch failures, failed releases, and surviving live
resources all produce typed attention state rather than apparent success.

## Native startup enforcement

`LoopForgeApp` is now the only production construction site for the default
recovery task. `AppModel` and `LoopController` accept it explicitly, leaving
ordinary test construction free of real Application Support effects. Both
normal task start and parallel-candidate integration await the same result
before any Codex or legacy Graph work. Legacy host-resource recovery is chained
after the new-kernel result and is skipped when that result requires attention.
The controller then blocks visibly, disables automatic resume, and records a
fail-closed log. Application termination waits for the bounded owner instead of
cancelling it in the middle of an effect.

An empty registry remains a no-op. No existing legacy Graph source calls the
registry, coordinator, authority, runtime, outbox, or dispatcher, and this
slice does not register a run on behalf of legacy state. Consequently it adds
startup ownership without granting new mutation, completion, or publication
authority to the old Graph.

## Verification

Focused tests passed: four registry/coordinator tests plus one lifecycle gate
test, 0 failures. They cover canonical persistence, exact duplicate replay,
conflicting registration, traversal, root overlap, batch bounds, symlink
rejection, permissions, restart, tampering, missing-workspace fail closure,
live-resource attention, construction failure, and blocking before the first
agent/legacy-Graph log.

The complete Swift suite passed: **511 tests, 8 environment-gated skips,
0 failures**. The full log is
`/tmp/loopforge-full-test-workspace-recovery-startup.log`, SHA-256
`7699852211721f2023b74ff7112fdbb362a8b108a192884245ae95c05226b84e`.

The arm64 release app was rebuilt and ad-hoc signed. Deep strict signature,
plist, ZIP, DMG, checksum-manifest, architecture, bundled-weight exclusion, and
post-package process checks passed. The current executable SHA-256 is
`eb07a465de795466578db76f38f1def56c4d088535908d81bb58e9f616c23676`.
No current native screenshot is claimed: the latest known macOS state is locked
and this pass did not repeat an unlock/poll attempt.

## Remaining cutover vetoes

Production still has no source-span task compiler or accepted new-kernel run
creation path, so journal-first registration-before-enqueue is not yet exercised
by a real product run. Registry issuance is isolated by call graph, not yet by a
separate Swift module/capability boundary. Explicit quarantine repair, remaining
runtime adapters and authorities, dependency/completion migration, receipt-native
UI, current native matrices, and revision-bound commit/push remain required.
The legacy Graph stays disconnected.
