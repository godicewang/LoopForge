# Journaled mutation-content store acceptance

Recorded 2026-08-12T09:18:28Z. Final acceptance remains false.

## Implemented boundary

`WorkspaceJournaledMutationContentStoreCoordinator` now accepts only the live,
non-Codable complete byte composition, resolves both exact origin receipts from
the current journal, and proves that its opaque candidate attestation is still
the newest accepted workspace transition. It then delegates byte installation
to the existing owner-private, descriptor-relative, content-addressed store,
revalidates the sealed artifact, repeats both origin and transition checks after
filesystem work, and presents a second non-Codable capability to `RunJournal`.

The reducer validates only pure typed data. The journal revalidates the external
artifact immediately before first append and rechecks transition freshness;
replay is deterministic from the inert event and never performs filesystem I/O.
An exact duplicate command returns the retained receipt without consulting
mutable external state, while the same command bound to different evidence is a
conflict. Recovered state retains one receipt per derivation and no bytes,
descriptors, or mutation capability.

The durable receipt binds the complete composition receipt, exact existing
object-store receipt, derived accepted-apply actor, time, and canonical digest.
It cannot issue proposal, preflight, staging, integration, publication, or
workspace-effect authority.

## Adversarial verification

The real integration state-machine fixture exercises a distinct before/after
modify delta, exact store materialization and revalidation, receipt Codable
roundtrip, hash-journal acceptance, exact duplicate replay, substituted
composition rejection without journal advance, recovery equality, and stale
denial after a newer failed rollback. The final split gate passed 744 tests with
8 intentional environment skips plus the independently run process-group
resistance case: 745 covered, zero failures.

Fresh Release hashes:

- LoopForge: `ebd97aa3a1f76d4ffd41f019fd62e416ebdf8ca617d979e70e131632850f4065`
- KernelSandboxGate: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`
- exact source snapshot before report-only changes: `de07fadfbc1307a2dcaf284093304846dab2d7174b76464f7154b49f659d2a4e`

All builds, tests, waits, failed diagnostic runs, and report generation are
excluded from the strict ledger. EasyBusiness remained read-only and its
fingerprint was unchanged.

## Still blocked

Journal-owned content-complete HEAD, index, and untracked planes;
repository-metadata and ignored-path-policy authority; canonical
`WorkspacePreimage` and manifest assembly; proposal/preflight issuance;
resident-memory authority; publication; native design/visual authority; final
authorization; native start/UI; package/sign; clean commit; and push remain
blocked.
