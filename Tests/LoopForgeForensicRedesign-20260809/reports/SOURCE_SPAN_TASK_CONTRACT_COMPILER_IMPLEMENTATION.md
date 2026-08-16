# Source-Span Task Contract Compiler

Status: **pure compiler and opaque ratification boundary implemented and package verified; native confirmation issuer and execution cutover remain closed**

## Why direct enrollment stayed closed

The production recovery registry can safely recover explicitly registered
new-kernel runs, but ordinary Loop/Graph tasks still have no user-ratified
`TaskContract`. Registering them directly would convert mutable legacy fields
and model-authored plans into apparent kernel facts. This slice therefore does
not register legacy tasks and does not grant execution, mutation, integration,
completion, or publication authority.

## Immutable compiler input

The new pure compiler retains every source as exact UTF-8 bytes with a digest,
typed source authority, author lineage, and timestamp. Requirements,
constraints, and ambiguities cite byte offsets plus the exact source digest.
Spans that split a multibyte scalar, exceed their source, bind stale bytes, or
contain no text are rejected.

Only user or accepted-user-amendment sources may support an `explicit` claim.
A model proposal, workspace observation, project convention, filename,
category, provider choice, or polished rewrite cannot become explicit user
authority. The contract's verbatim objective must equal the complete initial
source bytes and retain the exact SHA-256 objective digest.

## Requirement and authority closure

Compilation fails unless:

- every declared requirement and constraint has exactly one typed source
  binding;
- every mandatory requirement has the exact independently declared evidence
  recipe set;
- recipe ownership and expected observation are nonempty and exact;
- write, capability, or publication expansion has an explicit user-bound
  `requireAuthority` constraint;
- source, requirement, constraint, recipe, and ambiguity identities are
  unique; and
- the existing `TaskContract` structural validation passes without lossy
  normalization.

Duplicate requirement input is rejected without entering a duplicate-key
trap. Candidate encoding uses sorted-key, millisecond-stable JSON and produces
a content-addressed compilation digest. A source or contract change invalidates
an earlier confirmation.

## Ambiguity matrix

The compiler enforces the impact/reversibility table rather than allowing a
model confidence score to decide. Only reversible local assumptions and
rollback-bounded implementation experiments may proceed automatically.
Protected identity/design ambiguity must request authority or preserve the
baseline. Authority expansion, destructive/costly/external effects, mandatory
outcome changes, and missing evidence become typed blockers.

A blocker may remain visible in a ratified contract, but execution eligibility
is strictly `readOnlyDiscovery`. It cannot be relabeled as mutation-eligible.

## Opaque ratification

Release code contains no public initializer for
`TaskContractUserConfirmationReceipt`, and the type is deliberately not
decodable from untrusted bytes. Ratification requires the exact candidate
digest, a nonempty confirmation nonce, a confirmation time after compilation,
and a nonempty user actor/lineage identity. The resulting receipt binds the
contract ID, revision, candidate digest, nonce digest, user lineage, execution
eligibility, and every blocking ambiguity ID.

The debug-only factory exists solely for isolated adversarial tests. A future
native confirmation issuer must live at the explicit user-action boundary;
until then production cannot mint a ratification receipt.

## Verification

- focused compiler suite: **13 tests, 0 failures**;
- complete source suite: **560 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **560 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  direct executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `8ce8d9a2d874896d8b194f6074ec13cdc34d3f896d17e490cda16417fb3acaf0`
- focused log: `f4b4ecc6ee7bc2eb1bd00e77230753dc8906a926678c97a5090fba6c3a370f86`
- full source log: `f83ebeb4a581907dcd32e6521e9cfece40e373abd66a0214ad2ea6876da8cc90`
- package test log: `e189578be5b6bdf63a7bd85d53d834bbf57aeef5c87526139a4f17e56bebc86a`
- package command log: `7c4124d351ce859ee50b75f680ead48df01a55cbaa9327f0a3482b6c271689ac`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- executable: `24d5872ff7dbd80fea46f5951f7779d99859139e243f33f782c13bd8ee8155eb`
- ZIP: `f81116032982c0436594250d8b91f818477e4614e061514c46a67a4893e80574`
- DMG: `32ffca2e32b2e9e47254db9e0060ef3f353d499d8939998077462e44160a69c3`
- CDHash: `a39066054ef4fd3a4a2e76a073dfad54aa28df04`

The first focused build failed on a test return-type mistake and an unsafe
retroactive standard-library conformance. Both were corrected; that failed
run and its time are excluded from verification and the strict ledger.

## Boundary

This advances source-level acceptance rows B-01 and B-07. It does not yet
prove a native user confirmation, source-span authoring UI, baseline capture,
plan requirement ownership, journal enrollment, runtime controller migration,
or clean revision receipt. EasyBusiness remained permanently stopped and
read-only.
