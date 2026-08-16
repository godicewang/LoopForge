# Kernel mutation-preflight authority-gap hardening

Recorded at: `2026-08-12T05:02:31Z`

## Outcome

The deterministic mutation preflight remains available as a pure calculation, but Release code can no longer authorize it by decoding or constructing a `MutationManifest` and a `MutationPreflightContext` containing caller-selected sets of “accepted” receipt IDs.

`TransactionalMutationKernel.preflight` now consumes `AuthorizedMutationPreflight`, a non-`Codable` capability with a file-private initializer. The direct manifest/context overload and a test-only capability constructor exist only under `DEBUG`. Release deliberately has no issuer, so the current proposal/preflight gap fails closed instead of converting identifier equality into authority.

## Stop-the-line finding

The old context modeled eight authority classes as freely supplied ID sets. Current `KernelRunState` owns durable ordinary-verification, independent-review, visual-gate, and global quiescence facts, but it does not own the complete preparation facts required to mint this capability:

- no journal-derived mutation manifest and candidate/preimage construction path;
- no write-authority receipt for the exact proposed paths;
- a ratified mutation ceiling exists, but the manifest's separate mutation-budget receipt identity is not a journal fact;
- no per-operation path-resolution receipts;
- no rollback-rehearsal receipt;
- no candidate-scoped quiescence receipt with semantics suitable for pre-apply admission.

The worker result parser retains a proposed-result digest, not authoritative mutation operations or a complete preimage. Existing global runtime quiescence is not silently relabeled candidate quiescence. A production issuer would therefore need new journal-owned, typed preparation facts and exact replay rules; composing one from the current structures would recreate caller-selected authority.

## Proof

- A new regression passes one exact non-serializable test capability and verifies exact manifest and rollback digests while publication stays false.
- All 17 transactional-mutation tests pass.
- Exact current-source split coverage passes: **719 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **720 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass. The Release source contains only the capability-consuming overload; the direct overload is excluded by conditional compilation.
- Release `LoopForge` SHA-256: `688aa593413218e600df27922baa233b3b16dcd7f4c3cc531f158aa54aa66bf7`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `70f95d0edc81a7112d03d6bff1835ae3e28b21e0efcca70460f4dbeff0638486`.
- Diff whitespace and process cleanup pass. The read-only EasyBusiness fingerprint is unchanged.

## Boundary retained

This hardening closes one authority-injection surface; it does not implement integration proposal/preflight production issuance. Publication, final authorization, native start, package/sign, commit, and push remain unavailable. Production verifier/reviewer launch also retains the resident-memory veto. Historical Auto Graph remains permanently stopped, and legacy Single Loop and Parallel Candidates remain uncut-over.

Final acceptance remains false.
