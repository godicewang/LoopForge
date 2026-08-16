# Workspace Mutation Release and Crash Reconciliation Implementation

Status: successful and journal-recovered effects require exact release before acknowledgement; executor throws now retain durable failed ownership. Explicit repair/renewal and production startup wiring remain cutover vetoes.

## Durable release identity

Workspace-effect outbox schema v2 seals a release receipt ID and release command ID alongside the apply/rollback start and record command identities. All three journal command IDs must be non-empty and distinct. Exact enqueue replay retains the same release authority; a caller cannot acknowledge an effect under a newly invented cleanup identity.

`JournaledWorkspaceMutationRuntime` now returns a successful apply or rollback result only after `JournaledWorkspaceMutationLeaseAuthority.release` succeeds. This applies to both fresh effects and the important crash-recovery path where the integration receipt was already journaled: the executor is not re-entered, but the runtime still reconciles and releases ownership before the dispatcher can mark the envelope completed.

## Admission crash reconciliation

Before effect validation, the authority compares the journal recovery snapshot with the unified supervisor projection. If they differ, only a pristine supervisor may restore the exact journal head. A partially mutated or conflicting supervisor is rejected rather than overwritten. This closes the journal-admission-before-supervisor-commit restart window without scanning processes or trusting a caller lease.

## Release crash reconciliation

Release remains journal-first. If the journal already records the exact stable release but the supervisor still projects the same live lease, retry applies that recorded release to the supervisor and verifies that the canonical-root resource disappears. A different live lease for the resource is a hard ownership divergence. If both journal and supervisor already show no live ownership, the exact command/receipt replay is returned idempotently.

The integration test now exercises both crash windows: a fresh supervisor is hydrated from the journaled admission, then a release is journaled without supervisor commit, and retry clears the retained supervisor lease before completion. The dispatcher recovery test proves that a previously recorded apply is never executed again and is not acknowledged until its exact release is present.

## Verification

- Focused integration-state suite: 8 tests, 0 failures.
- Real filesystem/outbox suite: 13 tests, 0 failures.
- Complete suite: 506 tests, 8 environment-gated skips, 0 failures, 28.341 XCTest seconds.
- Complete log SHA-256: `ff806ab768340c59f4df79ffdfb1582d805d080427ef4535c6caf1dca214942d`.

## Remaining stop-the-line work

- Define explicit repair/renewal or permanent-quarantine commands for failed live ownership; ambiguous failure is intentionally not auto-released.
- Provide an explicit, evidence-preserving migration for any schema-v1 outbox rather than decoding it permissively.
- Invoke reconciliation and bounded dispatch from the production run lifecycle; legacy Graph remains disconnected.
- Complete accepted integration/dependency cutover, packaged native verification, receipt-native UI, commit, and push proof.

No EasyBusiness file, Git state, process, or application was changed.
