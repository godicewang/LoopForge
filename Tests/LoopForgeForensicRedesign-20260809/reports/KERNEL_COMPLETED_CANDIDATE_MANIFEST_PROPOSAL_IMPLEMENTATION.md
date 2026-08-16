# Completed candidate manifest proposal — inert, exact, replayable

Recorded: `2026-08-12T16:52:43Z`

## Result

LoopForge now converts the exact accepted completed-candidate before/after
content store into one durable mutation-manifest **proposal**. The proposal is
bound to the separately journaled canonical `WorkspacePreimage`, the active
contract and plan node, the completed attempt and strategy, exact requirement
ownership, canonical regular-file operation topology, file and byte ceilings,
and one common `MutationPreparationBinding`.

This boundary is intentionally inert. Its operation type has no path-resolution
receipt, and the proposal carries no write, mutation-budget, candidate-
verification, independent-review, rollback-rehearsal, candidate-quiescence, or
visual-gate receipt. It cannot be decoded or replayed into a `MutationManifest`
and cannot open an integration transaction or invoke a filesystem executor.

## Independent reducer and journal authority

The coordinator requires the exact accepted content-store transaction and the
exact accepted canonical-preimage transaction. Transaction and candidate IDs
are derived from accepted content digests rather than caller labels. The pure
reducer independently rechecks evaluating/completed/awaiting-verification
state, contract/source/workspace/root identity, node and strategy identity,
canonical preimage, both source journal-frame digests, exact operations,
requirement ownership, write-scope containment, plan and contract budgets,
actor, time, common binding, and the proposal's self digest.

`RunJournal` revalidates both live non-Codable origins and the external content
artifact before first append and exact duplicate replay. Close/reopen replay
recovers only inert proposal evidence; it cannot reconstruct either live
origin or executable authority.

## Native crash forensic and low-overhead repair

Nine failed diagnostic XCTest processes produced native `.ips` reports. Their
triggered cooperative-thread frames advanced through SHA byte-format closures
in verifier activation, provider invocation, heavy-evidence cache, task-
contract compiler/parser, confirming one systemic Foundation validated-format
stack-overflow pattern rather than unrelated test failures. Those affected
paths and the new proposal digest now use a bounded locale-free `KernelHex`
encoder. The diagnostic failures count zero in the strict ledger. The final
full suite completed without a crash.

## Verification

- A substituted canonical-preimage transaction was rejected before proposal
  acceptance.
- Exact proposal append was idempotent and still revalidated live origins.
- Journal close/reopen recovered the same proposal receipt.
- Serialized proposal evidence contains none of the eight executable receipt
  authority keys enumerated above.
- No integration transaction was created.
- The canonical fixture remained byte-identical.
- The complete Swift suite passed 764 tests with 8 intentional environment
  skips and zero failures in 58.701 test seconds (66.25 seconds wall).
- Diff whitespace, owned-process cleanup, thermal checks, and the unchanged
  read-only EasyBusiness fingerprint passed.

Failed crash diagnostics, failed runs, tests/builds, waits, polling, cleanup
checks, and report generation count zero in the strict ledger.

## Still blocked

The proposal must next acquire exact preparation facts and a rollback rehearsal
before an executable manifest can be assembled and proposed for preflight.
Preflight/integration authority, resident-memory authority, native design/
visual/final authority, native UI verification, package/sign/hash, clean
commit, and push remain pending.
