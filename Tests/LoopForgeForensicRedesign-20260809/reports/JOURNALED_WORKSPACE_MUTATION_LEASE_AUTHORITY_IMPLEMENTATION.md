# Journaled Workspace Mutation Lease Authority Implementation

Status: trusted issuer and dual-live validation implemented; successful/recovered effects now release before acknowledgement. Failure disposition and legacy Graph cutover remain vetoed.

## Closed authority defects

`WorkspaceMutationExecutionLease` is no longer sufficient by construction to enter the journaled workspace runtime. A new effect now fails closed unless a `JournaledWorkspaceMutationLeaseAuthority` can resolve the lease receipt to an accepted runtime admission in the hash journal and prove that the exact same `RuntimeResourceLease` remains live in both the journal projection and the sole in-process `RuntimeSupervisor`.

The issuer adds `workspaceMutation` to the supervisor resource taxonomy and derives one resource identity from the workspace ID plus canonical root identity. Different transactions or caller-selected lease labels therefore cannot concurrently authorize the same canonical root. Admission binds the current run, integration transaction, candidate attempt, workspace, root identity, owned/join release policy, zero-network reservation, and an exact wall/monotonic lifetime. Admission is written to the journal before supervisor commit.

The returned transport lease remains a compact value, but none of its caller-controlled fields establish provenance. Validation resolves its receipt back to the journaled admission and rejects mismatched root, workspace, transaction, attempt, runtime resource, runtime lease, supervisor state, phase, wall time, or monotonic deadline. Already-recorded integration receipts remain recoverable without re-entering an adapter or demanding renewed authority.

Release is also journal-first: the authority previews an exact supervisor release, records it in the journal, applies it to the supervisor, and verifies that the journal no longer projects live ownership. Expired authority may still be released, but may not authorize a new effect.

## Fail-closed runtime boundary

`JournaledWorkspaceMutationRuntime` now requires this authority before any new apply or rollback executor entry. Absence becomes `authorityUnavailable`; any provenance, lifetime, phase, or dual-live mismatch becomes `authorityRejected`. The optional initializer reference exists only so a journal-recovery-only path can decode and return an already-recorded receipt without filesystem access; it cannot execute a new effect.

## Verification

- New authority integration test covers journal-first admission, canonical-root resource derivation, journal/supervisor dual-live validation, forged-root rejection, conflicting lease rejection, and journaled release.
- Complete suite: 506 tests, 8 environment-gated skips, 0 failures, 28.341 XCTest seconds.
- Complete-suite log SHA-256: `ff806ab768340c59f4df79ffdfb1582d805d080427ef4535c6caf1dca214942d`.
- Issuer source SHA-256: `5e4f7feb9411dff29545938bb341cae5c83297783d59ad0cb2716681a386f22b`.

## Release follow-up

Outbox schema v2 now carries stable release identities, and fresh or already-journaled success cannot return to the dispatcher until exact journal/supervisor release reconciliation succeeds. See `WORKSPACE_MUTATION_RELEASE_AND_CRASH_RECONCILIATION_IMPLEMENTATION.md`.

## Remaining stop-the-line work

- Complete failure and quarantine lease disposition without erasing in-doubt ownership.
- Wire bounded reconciliation/dispatch into the production lifecycle and prove a fresh effect through the real executor.
- Keep legacy Graph disconnected until accepted integration/dependency completion, packaged native verification, and explicit cutover evidence exist.

No EasyBusiness file, Git state, process, or application was changed.
