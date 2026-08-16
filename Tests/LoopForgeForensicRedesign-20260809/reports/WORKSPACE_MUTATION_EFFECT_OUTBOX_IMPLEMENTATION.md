# Workspace Mutation Effect Outbox Implementation

Status: durable content-bearing effect outbox and bounded recovery dispatcher implemented; startup wiring, authority issuance, legacy cutover, completion, and publication remain blocked.

## Result

LoopForge can now retain the complete sealed request needed to recover a journaled workspace effect after process restart. Each outbox envelope binds one run, transaction, effect intent, payload digest, stable start/record command identities, enqueue time, and pending/completed state. Apply envelopes include the preimage, manifest, rollback plan, preflight receipt, staged content objects, workspace/recovery roots, executor identity, exact lease, timestamps, and limits; rollback envelopes bind the corresponding apply receipt and rollback authority.

The queue is stored outside the target workspace with mode-0600 files, an explicit entry/byte ceiling, cross-process `flock`, atomic synchronized snapshots, a snapshot digest, and per-envelope canonical payload digests. Fields represented by Swift sets are recursively sorted before hashing, while ordered mutation operations remain ordered. A duplicate intent is idempotent only when every sealed field and command identity is identical; conflicting reuse fails closed. Corrupt or oversized snapshots do not fall back to an empty queue.

`JournaledWorkspaceMutationDispatcher` enumerates a bounded number of pending envelopes and calls the journal-first runtime serially. It acknowledges an envelope only after the reducer journal contains the exact apply or rollback receipt. A crash after journal acceptance but before outbox completion is safe: the entry remains pending, the runtime returns the recorded journal fact without re-entering the filesystem executor, and the dispatcher then completes the queue entry. Runtime or authority failures remain pending and are reported; the dispatcher cannot renew a lease, mint authority, or reinterpret failure as progress.

## Verification

Three new outbox tests prove restart persistence, exact duplicate enqueue, durable completion, conflicting-intent rejection, target-workspace storage rejection before directory creation, and tamper rejection. The journal recovery test now also proves bounded dispatcher completion without executor re-entry and proves actor mismatch remains pending.

- Outbox/executor focus: 13 tests, 0 failures; log SHA-256 `ffa3be186d6b717776a13c9cad14f089de7bcd2e83d50bf38d42532103b43b77`
- Dispatcher/journal focus: 1 test, 0 failures; log SHA-256 `3266a5efaedb32c4589044e8d68cb8bece334d52d8ad10ddbd649192c630767b`
- Complete: 505 tests, 8 environment-gated skips, 0 failures, 32.492 XCTest seconds; log SHA-256 `fc45fe2c3b1c96ef0f13723936f67979ad4b92ad79641dfaf38c4a8393a1da64`

## Remaining stop-the-line gaps

The application does not yet construct and invoke this dispatcher during authoritative startup recovery, and legacy `GraphLoopEngine` cannot enqueue these envelopes. The outbox is not a write-authority or lease issuer. Expired authority and pre-effect executor rejection remain pending for explicit reconciliation. Accepted integration/dependency receipts, completion predicates, Git commit/publication transactions, package proof, and receipt-native UI are still absent.

No EasyBusiness file, Git state, process, or application was changed.
