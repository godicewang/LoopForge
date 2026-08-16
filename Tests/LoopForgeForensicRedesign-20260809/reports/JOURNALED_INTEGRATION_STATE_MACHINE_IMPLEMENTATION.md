# Journaled Integration State Machine Implementation

Status: implemented reducer/journal slice and extended with recovery-artifact binding; filesystem executor exists side-by-side; no publication authority; legacy Graph not cut over.

## Result

The transaction preflight boundary is now followed by a typed integration state machine carried inside the authoritative `RunReducer` and hash-chained `RunJournal`. A candidate can no longer move directly from “reviewed” prose or process exit zero to an integration-success projection in this side-by-side kernel. Each transition binds the same run, attempt, node, candidate, transaction, contract, plan-node, manifest, preimage, expected postimage, and effect identity.

The implemented phases are `proposed`, `rollbackPrepared`, `applying`, `appliedUnverified`, `postimageVerified`, `independentlyAccepted`, `rollbackRequired`, `rollingBack`, `rolledBack`, and `rollbackFailedQuarantined`. Every accepted command becomes one hash-chained journal event and is deterministically reconstructed on recovery.

## Enforced boundaries

- A proposal must belong to the current run, current contract digest, a known completed attempt, and that attempt's exact node.
- Candidate IDs cannot be reused across transactions.
- A preflight receipt must bind the proposal and an exact canonical rollback digest; apply eligibility cannot carry publication authority.
- Kernel-owned candidate verification and independent-review receipts must belong to the same attempt and exact expected postimage.
- A visual receipt is mandatory when the node intersects a frozen visual baseline; a supplied visual receipt must be accepted and revision-exact.
- Preflight paths and recomputed byte/file counts must fit the node's exact mutation scope and budget.
- Apply and rollback require unique durable effect-intent identities, a nonempty exclusive-lease receipt, and `remoteAccessDisabled == true`.
- Exact apply success requires every declared operation, the expected postimage digest, an unchanged-path proof, and a durable recovery-artifact digest. Partial success cannot enter verification.
- Apply failure or an in-doubt outcome enters `rollbackRequired`, not success, and rollback must bind the actual observed state when known plus the exact recovery artifact.
- Postimage verification must be performed by a different lineage than the transaction executor and must bind the apply receipt, exact postimage, evidence set, and quiescence receipt.
- Independent acceptance must use a third lineage, different from both executor and verifier, and must bind the exact verification receipt and postimage.
- Verification or acceptance rejection requires rollback. Rollback success must restore the exact preimage and unchanged-path proof; failure becomes a durable quarantine state.
- Every state, including `independentlyAccepted`, exposes `permitsPublication == false`.

## Tests

Six focused scenarios cover the exact happy path, failed apply and rollback, rejected verification plus quarantined rollback failure, remote-access and actor-lineage bypasses, tampered rollback/partial-success receipts, and real `RunJournal` replay with node-scope widening rejection.

- Focused: 6 tests, 0 failures; log SHA-256 `e212fa9ce85f77f47e8b6dfb628a392adf9ba6f1c8740e2b80145adb98cfdfda`
- Complete: 499 tests, 8 environment-gated skips, 0 failures, 27.038 XCTest seconds; log SHA-256 `af68722fc558a878ba7e2fe424ed6c6bc8adede58089ef180c77174d4ad33b33`

## Source identity

- `IntegrationTransactionStateMachine.swift`: 538 lines, SHA-256 `53dff2b0c35bf3079ea8de1f5c38adbccf97b1d4c5115426555f57a55242157f`
- `TransactionalMutationKernel.swift`: 851 lines, SHA-256 `22b83d09f05f3d28707ac330b315c4a07e77bf43f08a7fe0bcea84873be7b58a`
- `RunReducer.swift`: 1,518 lines, SHA-256 `b8dff39907535ae2dba0e5f09edb7f42522a4bd1f18018cd465c2a53c5250fcc`
- `IntegrationTransactionStateMachineTests.swift`: 515 lines, SHA-256 `2f87c128f64e18f83621b55cf14e5d9d246e298e0e0fdb6ef992728f5ce8b01c`

## Remaining stop-the-line gaps

The adjacent filesystem executor now captures real workspaces, validates content objects and lease bindings, synchronizes a recovery artifact before effect, applies bounded file/symlink operations, verifies postimage and unrelated-tree state, and executes guarded rollback. The journaled effect outbox, crash-time dispatcher and post-restore receipt recovery, concrete lease issuer, directory/submodule semantics, accepted `IntegrationReceipt`, dependency/completion predicates, commit, and publication still do not exist. Candidate-quiescence, write-authority, mutation-budget, rollback-rehearsal, and exclusive-lease IDs still require concrete provenance-bound adapters rather than caller-provided accepted-ID sets.

The legacy `GraphLoopEngine` remains active and bypasses these transaction states. Therefore the new projection is not cutover evidence and the current application package predates this slice. No EasyBusiness file or process was changed.
