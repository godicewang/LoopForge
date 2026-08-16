# Workspace Mutation Normal-Quit Join Implementation

Status: **exact live-handle join, fail-closed preflight, startup synchronization, and package verification passed; final release remains pending**

Recorded: `2026-08-16T07:27:30Z`

## Defect found

The completed-candidate apply preparation correctly admitted one owned
`workspaceMutation` lease, journaled one exact apply intent, and durably
enqueued one bounded effect. The production composition then returned only
inert installation data. Its exact non-Codable supervisor, lease authority,
dispatcher, and join handle were discarded.

Crash recovery could replay that durable effect on a later launch, but normal
application quit had no live owner for the current-session join-only lease.
Quit could therefore race startup recovery or leave an authorized pending
effect outside the process-session cleanup composition.

## Repair

`WorkspaceMutationApplicationTerminationJoin` now retains the exact journal,
runtime supervisor, outbox, dispatcher, accepted lease, and effect envelope
created by preparation. Its preflight proves all of the following before an
effect can run:

- the envelope, transaction, intent, run, and lease identities are exact;
- the lease is owned `workspaceMutation` authority with `join` policy;
- the journal and supervisor contain that one live lease and no queued or
  failed release state;
- the cleanup plan is exactly one `awaitJoin` action;
- the outbox contains exactly the retained pending envelope; and
- the integration transaction is still applying the exact intent and has no
  apply receipt.

The production coordinator retains this non-Codable handle by run. Normal quit
first obtains the complete sorted plan set, preflights every retained process
session, rechecks the complete mutation plan set before the first effect, and
then dispatches only the already-authorized envelope. Success requires the
exact release receipt and command frame, an empty outbox and supervisor, no
journal live lease, and an `appliedUnverified` transaction bound to the same
intent. The handle is removed only after those durable facts are proven.

Application startup and quit now share the same retained recovery task. Quit
cannot observe an empty in-memory table while startup owns durable recovery.
The startup report separately exposes `applicationTerminationCleanupIsSafe`:
persisted incomplete verification may remain visible attention without
blocking a safe exit, while startup failure, live ownership, pending effects,
quarantine, dispatch failure, or failed release vetoes quit.

## Adversarial evidence

The end-to-end production-composition test prepares the exact mutation twice,
proving idempotent retained installation, then substitutes the preflighted
payload digest at the termination boundary. The coordinator rejects the
changed plan before dispatch; the canonical file and pending envelope remain
unchanged. The exact plan then joins once, journals the specified release,
applies the candidate, removes the live handle, and leaves startup recovery
with zero effects to replay.

The first focused compile failed because the release outcome carries an
associated managed-release receipt. A second compile failed because XCTest
autoclosures cannot directly await. Both runs count zero. One combined class
run later observed a single transient `dispatchFailed`; five consecutive
focused reruns, a complete class rerun, and the package-owned complete suite
all passed. The transient run counts zero and is not hidden as credited work.

## Verification and package

- Focused exact normal-quit mutation proof: 1 test, 0 failures in 1.378 test
  seconds after the adversarial substitution check was added.
- `WorkspaceMutationRecoveryRegistryTests`: 5 tests, 0 failures in 0.026 test
  seconds.
- `KernelRunEnrollmentCoordinatorTests`: 44 tests, 0 failures in 7.163 test
  seconds on the complete rerun.
- `NativeKernelEnrollmentFlowTests`: 14 tests, 0 failures in 17.917 test
  seconds.
- `LoopControllerLifecycleTests`: 7 tests, 0 failures in 0.272 test seconds.
- Package-owned complete suite: 867 tests, 8 intentional environment-gated
  skips, 0 failures in 87.345 test seconds (87.397 wall).

Dirty-source snapshot
`348535debd90099b4b7ad9d4bcdec24dc06dfef4d4299c1e1058b605c5a11d3b`
was Release-built, ad-hoc signed, archived, checksummed, and verified through
direct and mounted-DMG startup. The executable is 26,301,888 bytes with
SHA-256
`f09bcf83206f9a82a50e04ebaf3b3e1811c2e1c1bfb7547ed6a12d966c4f5fdf`
and CDHash `0ba16766a1b3e10519ac28d0ae77ede4bff0dc39`.
All three packaged Mach-O files matched their mounted-DMG bytes. Strict deep
signature verification, checksum verification, detach, and zero residual
package processes or verification mounts passed.

This is a lifecycle/backend change with no visible UI delta. Prior screenshots
were not relabeled as evidence for this package.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Remaining boundary

The exact workspace-mutation normal-quit composition gap is closed. Still
pending are a trusted Release resident-memory containment issuer, productive
provider backend ratification and native launch cutover, the complete current
native trait/window/baseline/candidate matrix, a clean committed-revision
rebuild, commit, and push. Final release is false.
