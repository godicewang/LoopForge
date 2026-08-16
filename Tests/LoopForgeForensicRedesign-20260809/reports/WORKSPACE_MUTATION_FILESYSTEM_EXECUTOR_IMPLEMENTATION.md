# Workspace Mutation Filesystem Executor Implementation

Status: concrete bounded executor implemented and receipt-compatible; legacy Graph and completion/publication paths are not cut over.

## Result

LoopForge now has a real filesystem adapter behind the pure mutation preflight and journaled integration state machine. It writes only an exact preflight-admitted manifest, revalidates the workspace root and every compare-and-swap value immediately before effect, persists a content-bearing recovery artifact outside the workspace before the first mutation, serializes cooperating writers with a cross-process lock, and returns an apply receipt that the integration reducer accepts only as `appliedUnverified`.

Partial or uncertain application no longer pretends that the workspace equals the complete expected postimage. Apply receipts bind the durable recovery artifact and the actually observed affected-state digest; rollback intents must bind those exact values. A rollback restores only when current affected entries retain the inode identities captured by this transaction and the unrelated workspace digest remains unchanged. Same-content external replacement, unrelated drift, stale CAS, expired authority, and any recovery mismatch quarantine the transaction instead of overwriting user state.

## Enforced boundaries

- Root authority binds the resolved canonical path plus device/inode identity, workspace ID, transaction ID, exact lease receipt, exclusivity, remote-disabled state, and lease lifetime.
- Recovery storage must resolve outside the target workspace and is bounded by an explicit byte budget.
- Manifest, rollback manifest, preflight receipt, preimage, staged object set, and integration intent are independently rehashed and cross-bound before the first effect.
- Parent components must be real directories; a symlinked parent cannot redirect a write outside the workspace.
- Content objects are rehashed from bytes. Object-set, file-count, byte, and snapshot budgets cannot be supplied as unchecked prose.
- The complete unrelated tree is hashed before and after application. Enumeration errors and scan-budget exhaustion fail closed.
- Recovery data is durably written and synchronized before mutation; progress and owned inode identities are persisted after every accepted operation.
- Apply success requires the exact manifest postimage and an unchanged-tree proof. It still cannot publish.
- Rollback refuses a same-byte file recreated under a different inode and refuses unrelated workspace drift; both become quarantine receipts.
- Directory and submodule mutation are explicitly unsupported in this executor slice and fail closed. No implicit Git operation or remote access exists.

## Verification

Eight real temporary-workspace tests execute bytes and inspect the resulting files. They cover exact three-operation apply and rollback through the transaction reducer, stale CAS, expired/mismatched leases, in-workspace recovery rejection, corrupt staged bytes, unrelated user drift, same-content/different-inode replacement, and symlink-parent escape.

- Focused: 8 tests, 0 failures; log SHA-256 `288f55743d09f3504009474978f2deecc461ad49c9e19e51287c29b57702f7aa`
- Complete: 499 tests, 8 environment-gated skips, 0 failures, 27.038 XCTest seconds; log SHA-256 `af68722fc558a878ba7e2fe424ed6c6bc8adede58089ef180c77174d4ad33b33`

## Source identity

- `WorkspaceMutationFilesystemExecutor.swift`: 1,205 lines, SHA-256 `e5fa00b1f33ee15ab93283ba395252922e6d3b1fc24c401766bd73ea8775da0a`
- `IntegrationTransactionStateMachine.swift`: 538 lines, SHA-256 `53dff2b0c35bf3079ea8de1f5c38adbccf97b1d4c5115426555f57a55242157f`
- `TransactionalMutationKernel.swift`: 851 lines, SHA-256 `22b83d09f05f3d28707ac330b315c4a07e77bf43f08a7fe0bcea84873be7b58a`
- `WorkspaceMutationFilesystemExecutorTests.swift`: final digest recorded in the adjacent scorecard.

## Remaining stop-the-line gaps

This adapter is deliberately not reachable from `GraphLoopEngine`; installing an implementation is not a cutover. The concrete exclusive-lease issuer, journaled effect outbox, candidate content-object retention, crash-time recovery dispatcher, post-restore receipt recovery, accepted integration receipt, dependency/completion predicates, local commit transaction, remote publication transaction, and receipt-native UI remain absent. Directory/submodule operations need separately specified safe semantics. The old Graph integration path therefore remains a critical veto and the current packaged app predates this executor.

No EasyBusiness file, Git state, process, or application was changed.
