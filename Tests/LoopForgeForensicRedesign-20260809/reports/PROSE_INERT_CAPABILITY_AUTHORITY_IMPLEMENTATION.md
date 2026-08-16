# Prose-Inert Capability Authority

Status: **source-level compiler authority and package receipts present; trusted native issuer and production enrollment remain closed**

## Root cause closed

The task-contract compiler previously treated capability expansion like every
other authority expansion. If any `requireAuthority` constraint had an explicit
user-bound source span, a model candidate could place arbitrary capability IDs
in the authority ceiling. The compiler did not match names in prose, but it also
did not require a separate user selection for each capability. A model could
therefore reinterpret an objective that merely mentioned a tool or explicitly
forbade one as an authority grant.

LoopForge now treats objective prose and capability authority as different
channels. Capability IDs remain opaque and domain-neutral, but every non-empty
capability set must have an exact set of out-of-band
`TaskContractCapabilityGrantReceipt` values. That receipt type is intentionally
not `Codable` and is absent from `TaskContractCompilationCandidate`; adding a
lookalike field to model-authored JSON has no effect.

## Exact binding

Each grant binds:

- the task contract identity and exact candidate revision;
- one exact, non-empty capability identity;
- the canonical digest of the complete authority ceiling, including readable
  scopes, writable scopes, every capability, and publication authority;
- a non-empty grant nonce digest;
- the grant timestamp, which must not follow compilation; and
- the exact user actor and lineage that authored the initial objective source.

The compiler requires one and only one receipt for every declared capability.
Missing, extra, duplicate, stale-revision, wrong-contract, wrong-user,
future-dated, malformed, or authority-ceiling-stale receipts fail with typed
issues. Changing a scope or adding another capability invalidates all receipts
because the complete ceiling digest changes. An explicit prose constraint alone
can no longer satisfy capability authority.

Every valid grant is canonicalized to its own digest. The ordered digest map is
then included in the compiled candidate digest and copied into the ratification
receipt. Changing even the grant nonce changes both the retained receipt digest
and the candidate digest that the user confirmation must bind; replay does not
have to trust an in-memory compiler decision that discarded its authority.

The release build has no production receipt issuer. Only a DEBUG test factory
exists in this slice, so an unintegrated production caller that supplies a
non-empty capability set fails closed. A separate trusted native selection
issuer and production run enrollment are still required before cutover.

## Adversarial verification

- objective text containing `browser`, `PHOTO`, `simulator`, and `HANDOFF`
  leaves the capability set empty;
- an explicit authority constraint plus a model-proposed capability is rejected
  without the out-of-band receipt;
- a fake JSON `capabilityGrantReceipts` payload is ignored and cannot grant
  authority;
- exact one- and two-capability receipt sets compile independent of input order;
- malformed IDs, duplicate receipts, stale revisions, changed ceilings, and a
  different user lineage reject;
- core policy contains no tool, product, provider, repository, or industry
  keyword matching.

## Verification

- focused compiler suite: **21 tests, 0 failures**;
- complete source suite: **586 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **586 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  direct executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `e952ae53273310614072443f591fc8d9a24910d5fa6dc6ef9aab36291414d757`
- focused log: `a4320a12fe856ddc8f9ce207ebb6df54bbc686d3827c2dbc19622cb8a244f4db`
- full source log: `68365573cc21b2fa7967be5ff1fbf6a1a1ef75eff38ecbd7e72c268ec909b5f1`
- package test log: `247793c24a656c1866d99839bc5e95d9b2daaa813473a42b83253e282ff65225`
- package command log: `be0194a0a19b2707ba7e4750aded8b1f232afb5d95d9de792154ad2c62fdd262`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `8cbc749796b27e5e8782b878a92701d9e10bd7efbea4de6c07271f44f928efea`
- executable: `2be3595aa66b4513b9e73a63389c7c1b0eb047bcb2ccc438190c652d8d7b2444`
- ZIP: `c7eb4e477b5d04ae7dad09fafeea00579dfd55a043ec22f8e1dc82d4c44ac022`
- DMG: `2f1571f545d15ecd2862b7a9dfbb88282aa2fbe0cf776867c4b4d181c2cc3242`
- CDHash: `f59e14791e78d4dd501b0fce88d510d138f0f5c0`

## Boundary

This advances source-level acceptance row C-02. It does not authorize any
capability in the legacy Graph and does not enroll the stopped task. Native
capability selection, the trusted production issuer, journal enrollment and
controller cutover, current native UI verification, a clean commit, and push
remain mandatory. EasyBusiness remained permanently stopped and read-only.
