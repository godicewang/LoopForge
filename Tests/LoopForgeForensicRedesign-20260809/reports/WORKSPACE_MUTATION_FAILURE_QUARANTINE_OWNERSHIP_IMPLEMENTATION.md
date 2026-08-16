# Workspace Mutation Failure and Quarantine Ownership Implementation

Status: executor throws now create durable failed ownership and block quiescence; returned mutation/rollback failure receipts still follow the transaction state machine and release normally. Explicit repair/renewal and production lifecycle wiring remain pending.

## Failure is not silent release

A filesystem adapter can fail before it returns an `IntegrationApplyReceipt` or `IntegrationRollbackReceipt`: invalid root/binding, unavailable lock, corrupt recovery evidence, snapshot budget, or an unexpected filesystem exception. Previously the outbox stayed pending and the live lease remained only implicitly visible. A restart could restore the lease, but there was no journal fact explaining why cleanup had not completed.

Outbox schema v3 now seals separate failure receipt and failure command identities in addition to start, record, and successful-release identities. On an executor throw, `JournaledWorkspaceMutationRuntime` hashes the structured failure and calls `recordReleaseFailure` before returning the execution error. The authority journals an exact `cleanupFailed` runtime outcome, applies it to the unified supervisor, and verifies that both projections retain the live canonical-root lease in their failed-release sets. Quiescence therefore remains impossible until explicit repair and release.

This deliberately does not guess that an exception was pre-effect. Ambiguous recovery corruption or filesystem failure may follow partial mutation; automatic release would erase ownership evidence. In contrast, an executor-returned failed apply receipt includes its durable recovery artifact and observed state, advances integration to `rollbackRequired`, and releases the completed apply lease so a separately admitted rollback can proceed. A returned quarantined rollback receipt advances to `rollbackFailedQuarantined` and releases the finished rollback attempt while the integration quarantine remains authoritative.

## Crash reconciliation

Failure recording is journal-first. If the failure receipt exists but the supervisor did not commit it before a crash, retry applies the exact recorded failure to the retained lease. A fresh pristine supervisor may restore the journal snapshot including the failed-release set. Conflicting ownership is never overwritten. Successful repair can later journal a distinct stable release receipt, which removes both live ownership and failed-release debt.

The authority integration test now stages a cleanup-failure journal frame without supervisor commit, proves retry restores the failed-release projection, then stages and reconciles final release. This covers admission, failure, and release crash windows on one canonical-root lease.

## Verification

- Integration-state/authority suite: 8 tests, 0 failures.
- Real filesystem/outbox suite: 13 tests, 0 failures.
- Complete suite: 506 tests, 8 environment-gated skips, 0 failures, 28.341 XCTest seconds.
- Complete log SHA-256: `ff806ab768340c59f4df79ffdfb1582d805d080427ef4535c6caf1dca214942d`.

## Remaining stop-the-line work

- Define an explicit operator/kernel repair command that either renews a still-pending intent under new bounded authority or quarantines it permanently; the dispatcher cannot mint renewal.
- Migrate outbox schemas only through an evidence-preserving, explicit tool. Older schema snapshots currently fail closed.
- Invoke reconciliation and bounded dispatch from the production run lifecycle.
- Prove a fresh effect from admission through real filesystem execution, integration receipt, release, outbox acknowledgement, restart, and quiescence.
- Complete legacy cutover, receipt-native UI, package/sign/native verification, commit, and push evidence.

No EasyBusiness file, Git state, process, or application was changed.
