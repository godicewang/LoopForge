# Journal-Issued Repository Generation Authority

Status: **implemented and source/package verified; current unlocked native walkthrough and production run-creator cutover remain pending**

## Authority defect

The first repository-index implementation required a typed
`WorkspaceTreeGenerationReceipt`, but its internal factory accepted any
well-shaped `JournalTransactionReceipt`. Shape validation proved that a frame
identity looked complete; it did not prove that the recovered frame actually
contained the reducer-accepted apply or rollback that established the claimed
tree generation.

The original sequence check also disagreed with `RunJournal` semantics.
`startingSequence` is the first event sequence, so an N-event transaction must
satisfy `endingSequence - startingSequence == N - 1`. The old check expected N,
which rejected a real one-event frame and encouraged synthetic off-by-one test
receipts.

## Journal-only issuer

`WorkspaceTreeGenerationReceipt` is now opaque and non-decodable. Release
builds contain no caller-mintable initializer. `RunJournal` retains the exact
events for each recovered transaction and is the sole issuer. It matches the
latest workspace-changing event to the reducer projection and grants:

- `journaledMutationCommit` only for an `applyRecorded` event whose outcome is
  `exactPostimage` and whose observed postimage equals the projected receipt;
- `journaledRecoveryReconciliation` only for a `rollbackRecorded` event whose
  outcome is `restored` and whose observed preimage equals the projected
  receipt.

The issuer withholds authority when the latest transition is apply/rollback
started but not recorded, failed, in doubt, failed-quarantined, mismatched, or
uses a non-SHA legacy generation identity. An older green generation cannot be
selected after a newer ambiguous effect.

The repository cache key is now recipe version 2 and includes canonical-root,
workspace-identity, tree-generation, and journal-frame digests. This closes a
root-collision gap even when two registrations otherwise reuse the same typed
identities.

## Production recovery and native telemetry

Journaled apply/rollback results and the bounded outbox dispatcher carry opaque
generation receipts in memory. Startup recovery admits repository reuse only
after the outbox has no remaining executable effects, dispatch has no failure
or quarantine, and the supervisor has no live or failed-release ownership.

The recovery report records one of five typed states: `notApplicable`,
`resolved`, `withheldAmbiguousGeneration`, `withheldPendingEffects`, or
`resolutionFailed`. A withheld or failed state requires attention and blocks
Agent and legacy Graph admission. A resolved state exposes authority,
generation, journal frame/sequence, cache disposition, cache key, observed
metadata digest, and indexed-file count. The existing read-only kernel
diagnostics sheet now renders this telemetry without granting mutation or
completion authority.

## Adversarial verification

The integration path now proves all of the following with a real hash journal:

- an in-flight apply without a recorded result withholds generation authority;
- exact apply issues a mutation generation bound to the real record frame;
- the index computes once and hits memory for the same opaque generation;
- journal replay reconstructs the identical receipt and retains the hit;
- startup recovery projects the same generation and cache telemetry;
- a later failed rollback invalidates the older generation, produces no cache
  telemetry, and makes startup recovery require attention;
- legacy non-SHA mutation receipts remain recoverable but cannot gain cache
  authority.

Successful verification:

- 23 focused integration, recovery, repository-index, and lifecycle tests;
- complete source suite: **547 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **547 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, source/test manifest, checksum validation, direct
  executable startup, cleanup, and zero residual packaged processes.

Package receipts:

- source snapshot: `8e498043e1e087aa635ba20bdc52e9ad06402ad6eb60a8b16a7fe3ff3046d47d`
- executable: `00bd3257e09bb835757a8247704bc66c7b3c7aa30c91a8ebed2b2d104480dd74`
- ZIP: `318ec54203dbdf3b636fae080c4f36bba2a00f73bec8345bd87dd972cc1bec20`
- DMG: `08583fbdd1354b7f69cd07281d8984ef55ba2da1b9928e897e4b82cbff67b635`
- package test log: `35582b32391c7e8babeac6faf683284e5d817345d0fa6077a5bc492bad0c04a7`
- source full-test log: `f126d103e8a5e2b23cea121fda8d6e36ddd3e5e75277f723a86858925a5e8091`
- final focused log: `086f41bfc6313eedb06dae9dc98e1e12ea50d291bcdd59f86558621bd0aac6b6`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- CDHash: `f51babfdc5a83fec7b862323e9ac8070ea868a5e`

One compile failure and two focused behavioral failures exposed the private
factory visibility, real sequence arithmetic, legacy short-digest compatibility,
and local fixture binding issues. They were corrected and rerun; all failed
runs and their time are excluded from verification and the strict ledger.

## Boundary

This closes receipt issuance and startup recovery/cache telemetry at the
new-kernel boundary. The currently locked macOS session prevents a current
native accessibility/screenshot walkthrough of the telemetry sheet. No
production run creator yet enrolls ordinary Loop/Graph execution into this
kernel, so full controller cutover, native proof, clean commit, and push remain
mandatory. EasyBusiness remained permanently stopped and read-only.
