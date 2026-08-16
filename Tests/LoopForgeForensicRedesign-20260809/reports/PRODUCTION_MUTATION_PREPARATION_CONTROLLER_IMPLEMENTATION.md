# Production Mutation-Preparation Controller and Durable Pre-Effect Veto

Status: **production mutation preparation is now controller-composed; ordinary-macOS Release retains one exact durable containment veto before every effect**

Recorded: `2026-08-16T05:18:00Z`

## Outcome

`KernelProductionExecutionCoordinator.prepareCompletedCandidateMutation` is
now the production boundary between a live, journal-accepted rollback-prepared
candidate and canonical workspace mutation. It accepts no caller-supplied
containment capability inside the apply request. Instead, it resolves one
non-Codable contract/transaction-exact readiness capability immediately before
lease admission.

Ordinary macOS still cannot truthfully issue the required hard physical
resident-memory boundary for this process class. `RLIMIT_RSS` is advisory or
aliased, the physical-footprint task API is privilege-gated, and ordinary
spawn jetsam flags do not provide the required pre-exec termination guarantee.
LoopForge therefore does not invent a Release issuer. A missing issuer creates
one `KernelProductionMutationApplyVetoReceipt` while the integration remains
`rollbackPrepared`.

The veto is journaled before:

- workspace lease admission;
- integration apply intent;
- mutation outbox persistence;
- canonical workspace writes;
- apply, verification, acceptance, or publication authority.

## Exact authority and replay

The durable receipt binds schema, run, integration transaction, accepted
preflight receipt, exact contract identity and digest, the sorted full set of
ratified verifier/reviewer containment requirements, reason, actor, source
journal sequence, and observation time. The requirements retain each evidence
recipe, requirement, verifier kind, full probe digest, executable digest,
resident-memory ceiling, and zero-child ceiling.

Reducer admission requires the exact journal to be evaluating, release-clean,
and still `rollbackPrepared`. The proposal, accepted preflight, rollback
manifest, contract, and both original transition transactions must match.
Reopening the journal reconstructs the same receipt; an unchanged retry returns
the exact original receipt and transaction without appending a second frame.
A substituted receipt identity fails closed.

A genuinely changed external boundary may later return a live non-Codable
readiness capability. The production controller revalidates that capability
against the same run, transaction, contract, and complete requirement set
before invoking the existing lease/intent/outbox coordinator. A decoded
receipt, inner-request field, or cross-wired test capability cannot satisfy
this boundary.

## Adversarial proof

The strategy-level completed-candidate test now proves all of these paths:

1. a receipt-ID collision rejects before any veto or mutation state;
2. nil Release readiness journals one exact veto;
3. journal reopen recovers the exact receipt;
4. unchanged retry returns the exact receipt and transaction;
5. substituted retained-veto identity rejects;
6. integration remains `rollbackPrepared`;
7. workspace lease is absent;
8. mutation outbox is empty and canonical bytes are unchanged;
9. cross-wired containment rejects without a lease;
10. a caller cannot smuggle readiness through the inner apply request;
11. an exact DEBUG capability passed through the production resolver prepares
    the bounded apply;
12. exact prepared replay returns duplicate lease/intent transactions and the
    same outbox envelope.

The focused proof passed in 1.289 seconds. The enrollment/reducer surface
passed 89 tests with zero failures in 8.376 seconds. The exact package-owned
suite passed 861 tests with 8 intentional environment skips and zero failures
in 76.002 test seconds; the real Codex bridge passed in 12.900 seconds.

## Exact package

The package is bound to dirty-source snapshot
`15e1eef4ddd0bbdd473d337c338845573d8b8be8290e7165822ded0b22ceb9eb`
and embedded test-log digest
`4bab4a94d01eec75093c80089f053c44204f5fd3d425ea4f6d932d6160dae37f`.
Release build, deep strict signing, checksum validation, direct startup, DMG
verification, mounted-DMG byte identity for all three Mach-O files, mounted
startup, force detach, smoke, and zero residual package processes or mounts
passed. The app executable is 26,201,040 bytes with SHA-256
`13e10ad5d193fa63732bf867f979f5cce87839ce7963fd4a59149931b3f7e1df`
and CDHash `fd8fa5fcbd4cd4b41bafa5b0a99159dcde7eb939`.

This is a code-only authority/journal change, so the preceding exact-package
native screenshot remains historical evidence and was not relabeled as
current.

## Boundary retained

No production resident-memory issuer was created. No productive provider
backend was ratified. Productive native provider cutover, the complete current
native trait/window/baseline/candidate matrix, clean-commit rebuild, commit,
and push remain pending. Publication remains structurally impossible and
final release is false.

EasyBusiness was not mutated. Its observed state remained branch
`codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, and NUL-delimited status
fingerprint
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
