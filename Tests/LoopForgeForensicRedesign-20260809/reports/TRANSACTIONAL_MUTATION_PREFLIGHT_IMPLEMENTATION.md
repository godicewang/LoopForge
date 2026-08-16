# Transactional Mutation Preflight and Rollback Planner

Status: implemented pure-kernel slice, subsequently extended by `JOURNALED_INTEGRATION_STATE_MACHINE_IMPLEMENTATION.md` and `WORKSPACE_MUTATION_FILESYSTEM_EXECUTOR_IMPLEMENTATION.md`; not connected to the legacy Graph executor; not a commit or publication implementation.

## Outcome

LoopForge now has a domain-neutral, effect-free mutation preflight boundary in `TransactionalMutationKernel.swift`. It accepts a content-addressed workspace preimage, an exact mutation manifest, and accepted authority/evidence identifiers. The function returns either one typed rejection or an apply-eligibility receipt plus an exact reverse rollback manifest. It never reads or writes a filesystem, launches a process, changes Git state, or contacts a remote.

The receipt deliberately sets `permitsPublication` to `false`. An admitted preflight therefore does not mean that canonical bytes were changed, postimage checks passed, a commit was created, or any remote effect is authorized.

## Implemented invariants

- Transaction, candidate, contract, plan, base-preimage, and expected-postimage identities must be present and current.
- HEAD, index, worktree, and untracked plane capture is explicit; incomplete, duplicate, noncanonical, or identity-incomplete preimages fail closed.
- Manifest paths are exact canonical relative paths. Absolute paths, traversal, globs, empty components, decomposed Unicode aliases, repeated paths, and case-fold collisions are rejected.
- Case-fold checks cover both manifest paths and paths that already exist in the observed worktree, preventing a candidate from creating a differently cased alias of user content.
- Every path must be explicitly authorized and carry an accepted path-resolution receipt ID.
- Every operation must carry an authorized requirement set, and the manifest's touched-requirement set must equal the operation union.
- Write authority, mutation budget, candidate verification, independent review, rollback rehearsal, candidate quiescence, and applicable visual evidence are mandatory. An optional but unaccepted visual receipt also fails closed.
- Candidate-side external effects are forbidden.
- Operation sequence and field shape are exact for create, modify, delete, rename, chmod, symbolic-link, and submodule mutations.
- Entry kind and mode are part of compare-and-swap. Byte drift, topology drift, accepted-sibling drift, cache/baseline drift, and kind/mode drift produce typed conflicts before apply eligibility.
- Both desired postimage objects and the preimage objects required for rollback must exist in the sealed object inventory. Observed/stored size disagreement rejects.
- File count and byte footprint are recomputed by the kernel. Deletions and rollback material are counted; the manifest cannot self-report a smaller budget.
- Manifest, preimage, and rollback digests use field-aware canonical encoding. Sets are sorted while declared operation order is preserved by sequence.
- Rollback reverses operation order and swaps content, entry-kind, mode, and path pre/postconditions. A newly created symlink or submodule rolls back as deletion rather than as an invalid replacement.

## Adversarial coverage

`TransactionalMutationKernelTests` contains 12 scenario tests with multiple fail-closed assertions. It covers valid admission, exact reverse rollback, stale bindings, incomplete capture, every authority gate, visual/effect bypass attempts, traversal/glob/Unicode paths, case collisions against candidate and existing paths, repeated mutation, newer user bytes, accepted sibling drift, kind drift, rename topology, recomputed file/byte budgets, missing rollback objects, object-size mismatch, malformed operation sequences and shapes, requirement ownership, cross-order digest stability, and new symbolic-object rollback.

Focused result:

- 12 tests executed
- 0 failures
- log SHA-256: `c40830a5b085a8b61acf6900221c9d8660dbff2e3d9715358ed8cfc34bb681fb`

Complete Swift result:

- 499 tests executed
- 8 environment-gated tests skipped
- 0 failures
- 27.038 seconds XCTest execution
- log SHA-256: `af68722fc558a878ba7e2fe424ed6c6bc8adede58089ef180c77174d4ad33b33`

## Source identity

- `Sources/LoopForge/Kernel/TransactionalMutationKernel.swift`: current 851 lines, SHA-256 `22b83d09f05f3d28707ac330b315c4a07e77bf43f08a7fe0bcea84873be7b58a`
- `Sources/LoopForge/Kernel/KernelIdentity.swift`: current SHA-256 `3d14f06124afa4901c870bec28fe92b5c64fb214af74f943322cfb57c9e1f805`
- `Tests/LoopForgeTests/TransactionalMutationKernelTests.swift`: current 556 lines, SHA-256 `77ec955b4b38fbb1ea587fbe885ded1669138f7961c0ba3d0547c8407eb42c14`

## Explicitly unresolved

This slice is intentionally insufficient for cutover. The accepted IDs in the preflight context still need to be replaced by journal-reduced, provenance-bound receipt objects at the production boundary. A durable integration state machine and bounded filesystem executor now exist side-by-side, including recovery, affected-postimage, unchanged-tree, inode-ownership, and rollback/quarantine checks. LoopForge still lacks the production content-object retention adapter, concrete exclusive-lease issuer, journaled effect outbox and crash dispatcher, post-restore receipt recovery, post-integration recipe execution, independent postimage acceptance adapter, accepted integration receipt, canonical commit transaction, and separate remote publication transaction.

The legacy Graph integration paths remain live and do not call this kernel. They still contain the unsafe stash, patch, direct conflict-repair, and remote-alignment behavior documented in the normative specification. No real workspace should rely on this pure planner until shadow replay, fault injection, and controlled cutover prove the entire effect path. No EasyBusiness file or process was mutated during this implementation interval.
