# Typed Deliverable Cardinality Enforcement

Status: **contract, compilation-authority, verification, and package receipts present; native authoring and production enrollment remain closed**

> Historical boundary note (2026-08-16): this report preserves the original
> source-level receipt. Native authoring, immutable confirmation, enrollment and
> activation retention, the clean 876/8/0 package, and real packaged UI proof
> are now closed by [Native Deliverable Cardinality Authoring](NATIVE_DELIVERABLE_CARDINALITY_AUTHORING_IMPLEMENTATION.md)
> and its [machine-readable scorecard](NATIVE_DELIVERABLE_CARDINALITY_AUTHORING_SCORECARD.json).

## Root cause closed

The stopped Graph could count whatever artifacts happened to be visible, or
substitute a collection of plausible outputs for a user-declared exact set.
Neither the immutable task contract nor an accepted verification receipt could
represent “exactly N independently identifiable members.” A prose plan, file
count, test name, or aggregate audit score could therefore stand in for the
missing obligation.

LoopForge now models exact set size directly on a requirement. The constraint
contains only an opaque collection identity and a positive unsigned count. It
does not classify image, document, screen, repository, provider, product, or
industry vocabulary. Malformed, whitespace-normalized, empty, and zero-count
declarations fail contract validation.

## Authority and verification

The pure task-contract compiler accepts cardinality only when the requirement's
single source binding is explicitly authorized. Workspace observations,
conventions, safe inference, proposals, unknown state, and conflict cannot mint
the count. Existing source-span validation independently proves that explicit
authority comes from the user or an accepted user amendment, and the eventual
ratification digest binds the exact candidate.

An accepted verification receipt must now supply exactly one observation for
every cardinality-bound requirement it claims. Each observation binds:

- the exact requirement and opaque collection identity;
- a set of stable member identities and content digests; and
- an independent evidence digest for the membership observation.

The reducer rejects missing, unexpected, duplicate, substituted-collection,
invalid-evidence, duplicate-member-identity, under-count, and over-count
observations with typed reasons. A `Set` prevents byte-identical duplicate
records from inflating the result, while a separate stable identity permits two
legitimate members with identical content bytes. Rejected receipts cannot
advance reducer state. Legacy contracts and receipts with no cardinality field
still decode and preserve `nil`.

## Domain-neutral adversarial scenario

The acceptance fixture uses only opaque identities. Its contract requires ten
members in `opaque-collection-17`; nine and eleven are rejected, a substituted
collection is rejected, two records sharing one stable identity are rejected,
and ten distinct stable identities are accepted even when every member has the
same content digest. No image or other vertical keyword selects this policy.

## Verification

- focused reducer/compiler suite: **39 tests, 0 failures**;
- complete source suite: **574 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **574 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  direct executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `2aadc782217dfd601cac725b111d71feea98f7b9e92ddaa11c003449e6992c9c`
- focused log: `fda07439f3d87e6de265cbe32a23f1e99493838288be2758b6c9116c109422fd`
- full source log: `2d1239d107a418266a8f9b98e405b0fa60211d9330840a383ee64ac032cfecfb`
- package test log: `6f70e419004cebf4424b9607139a50607298dd3694e021c453c4902818ff5136`
- package command log: `136cfa454faf0269cd431c493665538b9d5618bc99263e79d19136ab0e081e57`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- executable: `924afdfeecd273e931b4c061a069996542bacfaac5eebc59be21f786c005b677`
- ZIP: `73a400466a7ab74d24174d55740066cf1973d640a17480b2c7c59ecee8848077`
- DMG: `ecccdf54614976aab96f64175d9e988f8a526b177bf04085da1c38e959e23baa`
- CDHash: `0109b70ca4e1c44faf89b8fe47bf12a9f41cea34`

## Boundary

This advances source-level acceptance row B-04. It does not make the legacy
Graph authoritative and does not enroll the stopped task. Native contract
authoring and user confirmation, production run enrollment/controller cutover,
current native UI verification, a clean commit, and push remain mandatory.
EasyBusiness remained permanently stopped and read-only.
