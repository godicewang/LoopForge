# Kernel Slice One Implementation

Status: **implemented side-by-side; full Swift suite green; no legacy execution path cut over yet**

## Outcome

The first ratified production slice introduces a pure, domain-neutral orchestration vocabulary and reducer without touching EasyBusiness or changing existing Loop/Graph/Watcher runtime behavior.

New production components:

- phantom-typed stable IDs, content digests, actor lineage, and command context;
- immutable task/requirement/constraint/baseline/authority/acceptance contracts;
- node contracts with exact requirement mapping, dependency graph, mutation scope, capability set, and strategy fingerprint;
- typed execution, verification, review, quiescence, command, event, state, rejection, and projection models;
- a pure command validator and event reducer with expected-sequence and idempotency fences;
- deterministic replay and Codable event envelopes.

## Enforced invariants

1. Invalid contracts do not advance state.
2. Stale sequence fails closed; an idempotent duplicate returns the original
   receipt and cannot create a second logical effect.
3. Every planned node maps to known requirement IDs.
4. Dependency graphs are acyclic and scopes cannot exceed the contract ceiling.
5. Blocked/failed/malformed execution cannot enter verification.
6. Review approval requires matching accepted verification and a reviewer lineage distinct from the worker.
7. Retired strategies cannot restart under a renamed attempt.
8. Pause/stop are requests; terminal projection requires a quiescence receipt.
9. An apparently empty resource receipt cannot close a still-active attempt.
10. Completion requires mandatory requirement closure, applicable independent review, no active attempt, and quiescence.
11. UI-facing projection derives from reducer state and exposes requirement closure and quiescence.

## Verification

- targeted kernel suite: 11 tests, 0 failures;
- latest complete Swift suite: 354 tests, 6 intentionally skipped integration tests, 0 failures;
- whitespace validation: clean for the new source/test paths;
- vertical-policy scan: no product, repository, industry, UI genre, provider, or concrete tool vocabulary in the new kernel;
- production source and tests total 1,286 lines in this slice.

The first compile attempt found one Swift exclusivity violation and is excluded from successful verification time. The access was made explicit through a local derived set, after which the targeted and full suites passed.

## Boundary

This slice is not yet the source of truth for existing tasks. The hash-chained
journal, conservative importer, and typed interval ledger now exist beside it;
the next dependency is the runtime supervisor. No existing mutable snapshot is
silently upgraded to a receipt.
