# Runtime Release-Policy Compatibility Hardening

Status: **shared admission, queue, and recovery policy compatibility passed; exact workspace-mutation join composition and final release remain pending**

Recorded: `2026-08-16T06:49:06Z`

## Defect found

`RuntimeSupervisor` previously treated an owned resource's release policy as a
mostly caller-selected value. It prohibited owned detach, but it could still
admit a process tree with `join` or a non-process resource with
`gracefulThenTerminate`. Those pairings were not executable by the cleanup
adapters represented by the plan:

- a process-tree `join` depends on an exact in-memory handle and cannot be
  reconstructed from PID/start identity after a complete application crash;
- graceful termination is a native process operation and cannot truthfully
  release an async task, workspace mutation, or other non-process lease.

The process runtime rejected join-only launch later, after the rejected
admission had been journaled and compensated. Queue and supervisor recovery
also lacked a common semantic compatibility rule. This created unnecessary
state transitions and allowed historical incompatible leases to look
structurally valid during restore.

## Repair

Release policy is now validated as part of resource identity at the first
shared supervisor boundary:

- borrowed resources require `detachOnly` plus their stable external identity;
- owned process trees require `gracefulThenTerminate`;
- every other owned resource requires `join` by its exact typed owner.

An incompatible direct acquisition returns
`invalidReleasePolicy` before budget admission or live-lease creation. The
same predicate governs queue validation and recovery snapshots, so incompatible
queued requests fail closed and a historical process-tree join lease makes the
entire snapshot invalid rather than entering a cleanup projection.

This closes the generic policy/adapter mismatch. It does not manufacture a
recoverable join handle for non-process resources. The only production
non-process join issuer found by the full call-path audit is the typed
`JournaledWorkspaceMutationLeaseAuthority`; its startup registry remains the
durable recovery path. Its exact live-handle-aware normal-quit composition,
after Release containment permits admission, remains pending and is stated as
such rather than hidden behind the generic supervisor repair.

## Verification

- Combined focused policy/runtime run: 39 tests, 0 failures in 0.024 test
  seconds after correcting one stale process fixture.
- `RuntimeSupervisorTests`: 39 tests, 0 failures in 0.008 test seconds,
  including direct process-join rejection, non-process graceful-termination
  rejection, and historical process-join recovery rejection.
- Broader lifecycle/recovery run: 90 tests, 0 failures in 12.716 test seconds
  across `JournaledProcessRuntimeTests`,
  `KernelRunEnrollmentCoordinatorTests`, `RuntimeJournalIntegrationTests`, and
  `WorkspaceMutationRecoveryRegistryTests`.
- Package-owned complete suite: 867 executed, 8 explicitly gated skips,
  0 failures in 80.552 test seconds (80.605 wall).

The exact dirty-source snapshot
`610338f003c251ef943a8b32c084776437d95ab91064a5403031bbb5d8a33178`
was Release-built, signed, packaged, checksummed, and verified through direct
and mounted-DMG bounded startup. The application executable is 26,214,928
bytes with SHA-256
`3f85d0393e566a6050e8dc291c7a8caa7627dd1ef589ea80262279fccce8102a`
and CDHash `1c08d57f8927bc8c6212d5d63c991d7aa02d8873`. ZIP, DMG, and
package-log hashes are recorded in the companion scorecard. Deep strict
signature verification, checksum verification, detach, and zero residual
packaged processes or verification mounts passed.

This source-only policy change has no visible UI effect. The two most recent
native screenshots remain exact evidence for the preceding package snapshot
`0e42de36…21da7`; they are not relabeled as evidence for this package.

The first combined focused run failed only because an existing process-tree
fixture still used the old default `join` policy. The fixture was corrected to
the production process policy, the rerun passed, and the failed run counts zero.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Remaining boundary

The shared runtime can no longer admit or restore a resource/release-policy
pair that its cleanup semantics cannot represent. Still pending are exact
workspace-mutation live-handle-aware normal-quit composition after Release
containment permits admission, a trusted Release resident-memory containment
issuer, productive provider backend ratification and native cutover, the full
native trait/window/baseline/candidate matrix, a clean-commit rebuild, commit,
and push. Final release is false.
