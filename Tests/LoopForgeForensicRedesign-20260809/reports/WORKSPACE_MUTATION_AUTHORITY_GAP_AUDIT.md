# Workspace Mutation Authority Gap Audit

Status: historical critical authority-origin gap confirmed; stale replay-time authority fixed; trusted issuer, dual-live validation, canonical-root exclusivity, and explicit journaled release are now implemented. Automatic release dispatch and crash reconciliation remain stop-the-line work.

## Confirmed defect

`WorkspaceMutationExecutionLease` is currently a caller-constructible value. The executor verifies that its receipt ID, transaction, workspace, root identity, exclusivity, remote-disabled flag, and wall-clock bounds agree with the adjacent intent, but it does not prove that a trusted journal/supervisor issued either value. A malicious or defective caller can therefore construct matching lease and intent fields. Strong root/CAS/recovery checks limit the damage, but matching strings are not authority provenance.

The new durable outbox exposed a second time-of-check defect: executor lease validation used `request.completedAt`, a sealed request timestamp. Replaying the same envelope after the actual lease expired would still pass because the historical timestamp remained inside the old lease interval. `JournaledWorkspaceMutationRuntime` now checks the live wall clock against the lease before journaling a new apply or rollback intent and before any executor entry. A dispatcher cannot silently renew or backdate authority. An already-recorded journal receipt remains recoverable after expiry because recovery returns the journal fact without executing the workspace adapter.

## Required authority design

- Add a typed workspace-mutation resource kind to the unified runtime supervisor.
- Issue the exclusive lease through journal-first runtime admission, bound to run, transaction, attempt, workspace ID, canonical root device/inode identity, and remote-disabled capability.
- Carry the runtime resource/lease identities in `WorkspaceMutationExecutionLease`; receipt ID alone is insufficient.
- Before executor entry, require exact equality among the outbox envelope, integration intent, journal live lease, and supervisor live lease.
- Use actual wall and monotonic time at dispatch. Replays may not reuse an expired productive lease.
- Journal release after apply/rollback receipt recording; recovery must release a still-live lease without erasing a pending or quarantined effect.
- Workspace mutation admission must be exclusive per canonical root, not merely per transaction label.
- No Graph worker, node agent, or persisted legacy snapshot may mint, renew, release, or substitute this authority.

## Implementation follow-up

The first six controls above are now implemented by `JournaledWorkspaceMutationLeaseAuthority`; see `JOURNALED_WORKSPACE_MUTATION_LEASE_AUTHORITY_IMPLEMENTATION.md`. The remaining gap is lifecycle orchestration: the durable dispatcher does not yet carry release identities or guarantee release/reconciliation across every terminal and crash branch, so this audit remains a cutover veto rather than a closed acceptance claim.

## Verification

- Warning-free focused runtime recovery test: 1 test, 0 failures; SHA-256 `4c46d3ad7c2c0dc1e4270094dbe5eaa59fb486e3110b22a3cd95ce929ebc8339`
- Complete current suite: 505 tests, 8 environment-gated skips, 0 failures, 32.235 XCTest seconds; SHA-256 `a5872b5020d7683fad20288a2f59f3f456c8d1771486ff4c841bebc5a88cdba2`

No EasyBusiness file, Git state, process, or application was changed.
