# Kernel mutation-preparation facts implementation

Recorded at: `2026-08-12T05:20:50Z`

## Outcome

Mutation preflight no longer models missing preparation authority as five caller-supplied sets of accepted receipt IDs. Each previously anonymous class is now an exact typed fact bound to one transaction, candidate, contract, plan node, canonical preimage, and expected postimage:

- write authority binds the exact authorized paths and requirement IDs;
- mutation budget binds exact changed-file and changed-byte ceilings;
- rollback rehearsal binds the exact forward-manifest digest and operation count;
- candidate quiescence is explicitly candidate-scoped and records active-resource, unreleased-lease, and external-effect counts;
- path resolution binds the exact root identity and source/destination tuple for every operation, plus a no-symbolic-link-traversal assertion.

The deterministic preflight validates every binding before computing apply eligibility. Wrong candidate, transaction, root, manifest, operation topology, live-resource count, lease count, or external-effect count rejects with the existing typed fail-closed outcome. Ordinary verification, independent review, and visual acceptance remain journal-owned receipt identities rather than being duplicated into these preparation facts.

## Data-origin finding

The retained worker-result protocol carries canonical event and terminal envelopes plus a proposed result digest. It does not carry authoritative mutation operations, a canonical workspace preimage, content objects, path-resolution observations, or rollback evidence. `IntegrationProposal` nevertheless presumes manifest/preimage/postimage digests. Therefore no safe production proposal/preflight issuer can be composed from current worker output alone.

The new preparation structures are durable evidence schemas, not authority. Release preflight still requires `AuthorizedMutationPreflight`, whose initializer is file-private and whose production issuer remains absent. The reducer likewise continues to reject proposal and preflight transitions from every non-test issuer.

## Proof

- 18 transactional-mutation tests pass, including cross-candidate, cross-transaction, wrong-root, active-resource, and unrehearsed-manifest substitution cases.
- 14 real-filesystem mutation executor tests pass against the typed preparation schema.
- Exact current-source split coverage passes: **720 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **721 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass.
- Release `LoopForge` SHA-256: `8268f995ce31b963e05634892cdf2f07a49adcc37756d31440c7e2d584ce1043`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `ece66579c27aebc3a2613aca3771a376c88bb3ec6fdf377c1be72ce3da8b32c6`.
- Diff whitespace and process cleanup pass. The read-only EasyBusiness fingerprint is unchanged.

## Boundary retained

This slice defines the exact missing facts and enforces them in the pure calculation. It does not capture a production manifest/preimage, create journal events or replay rules for these facts, issue the non-serializable capability, or advance integration proposal/preflight state. Resident-memory, publication, final authorization, native start, package/sign, commit, and push vetoes remain unchanged.

Final acceptance remains false.
