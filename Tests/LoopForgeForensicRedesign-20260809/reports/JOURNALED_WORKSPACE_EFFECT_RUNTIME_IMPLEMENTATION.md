# Journaled Workspace Effect Runtime Implementation

Status: journal-first apply/rollback coordination and bounded crash replay implemented; legacy Graph cutover, automatic recovery enumeration, authority issuance, completion, and publication remain blocked.

## Result

The filesystem boundary now distinguishes a new request from a replay of the same content-addressed integration intent. It no longer recaptures an already-mutated workspace as a fresh rollback baseline. A matching recovery checkpoint may resume only from its exact persisted operation prefix and exact inode-bearing owned state; an unowned replacement or unverifiable crash point becomes a failed/quarantined receipt without another workspace mutation.

Successful rollback no longer rewrites the apply recovery evidence whose digest is already bound by the journal. It persists a separate rollback completion artifact containing the exact restored inode state. A retry after restoration can therefore prove that rollback already completed and return the same receipt identity without overwriting the workspace. The recovery artifact date decoder now matches the canonical millisecond encoder; the previous decoder interpreted persisted timestamps with the wrong epoch scale.

`JournaledWorkspaceMutationRuntime` coordinates the reducer journal and concrete executor. It durably records `startApply` or `requestRollback` before entering the filesystem adapter, records the resulting receipt afterward, and re-reads the journal projection after both boundaries. If an apply or rollback receipt is already journaled, recovery returns it without calling the filesystem executor. If only the intent is journaled, the runtime may replay only through the executor's exact recovery checkpoint. Divergent actor, intent, phase, or journal projection fails closed.

## Crash boundaries

- Before intent journal: no workspace executor call is authorized.
- After intent journal but before first workspace effect: retry begins from the durable prepared checkpoint.
- After a persisted operation checkpoint: retry requires the exact operation prefix, affected inode state, and unchanged unrelated-tree digest.
- After a filesystem operation but before its checkpoint: the state is not assumed owned; retry fails/quarantines rather than recapturing it.
- After exact apply but before its journal receipt: the immutable apply checkpoint reconstructs the receipt.
- After exact rollback plus completion checkpoint but before its journal receipt: the separate rollback checkpoint reconstructs the receipt.
- After either receipt is journaled: runtime recovery returns the journal fact and never re-enters the executor.

## Verification

Ten real temporary-workspace executor tests now include repeat apply, foreign same-content inode quarantine, stable repeated failure, and repeat rollback from its separate completion checkpoint. One journal integration test proves that a recorded apply returns without reading the deliberately invalid workspace or creating a recovery directory.

- Executor focus: 10 tests, 0 failures; log SHA-256 `ce44b6d1791a4566ca3124d1bcaee9c8d61174fca2bb595a07c9f975cb389b75`
- Journal recovery focus: 1 test, 0 failures; log SHA-256 `21bb92577fb0bd841b65c0d231742b4a99ca23769460e7a9220b83e4e1047a44`
- Complete: 502 tests, 8 environment-gated skips, 0 failures, 29.395 XCTest seconds; log SHA-256 `f8a2c0a1558e39bd83031d43166a7a8e6d473d23efa65da083c40ffdcb526d23`

## Remaining stop-the-line gaps

This coordinator is not reachable from legacy `GraphLoopEngine`. It does not mint write authority or exclusive leases, retain candidate object sets, automatically enumerate unfinished integration transactions at process startup, issue accepted integration/dependency receipts, commit Git state, publish remotely, or authorize completion. A pre-effect executor rejection after an intent is journaled remains visibly `applying` and requires an explicit reconciliation/quarantine transition; it is never treated as success. Package and native UI proof still predate this slice.

No EasyBusiness file, Git state, process, or application was changed.
