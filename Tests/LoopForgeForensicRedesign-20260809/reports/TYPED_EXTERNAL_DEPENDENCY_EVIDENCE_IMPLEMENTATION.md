# Typed External Dependency Evidence

Status: **contract, source authority, journal receipt, blocker linkage, and package receipts present; native authoring and production enrollment remain closed**

## Root cause closed

The stopped Graph could turn an agent-written sentence such as “an external
credential is unavailable” into a terminal blocker. Its blocked state retained
only a reason digest. Nothing proved that the dependency was declared by the
user, that it applied to the current requirement and attempt, that an authorized
independent observer ran the required probe, or that the observation actually
reported unavailability. The same worker that wanted to stop could therefore
invent both the dependency and the conclusion.

LoopForge now separates ordinary internal blocking from external-dependency
blocking. A task contract may declare an opaque dependency identity, a typed
kind, the exact requirement set it constrains, an evidence-recipe identity, and
the authorized observer lineage set. These are structural identities rather
than credential, provider, product, or industry keyword rules. Duplicate,
empty, unknown-requirement, recipe-free, and observer-free declarations fail
contract validation.

## Authority and observation

The pure task-contract compiler requires exactly one source binding for every
declared external dependency. The binding must be explicit; proposed, inferred,
observed, unknown, and conflicting states cannot mint dependency authority.
Existing source-span validation separately proves that an explicit binding
originates in the user source or an accepted user amendment, and ratification
binds the exact candidate digest.

An external-dependency observation is a first-class journal event. The reducer
accepts it only when all of the following agree:

- the dependency is present in the ratified contract;
- the receipt targets the current active attempt before disposition;
- its requirement set is the exact dependency/attempt intersection;
- the command actor is the observer, is outside the worker lineage, and is in
  the contract-authorized observer lineage set;
- its evidence recipe exactly matches the contract;
- the evidence digest is non-empty; and
- the observation timestamp equals the journaled command timestamp.

The observation records either `available` or `unavailable`. Only a stored
`unavailable` receipt for the same attempt can authorize the typed
`externalDependencyUnavailable` disposition. A missing, rejected, available,
or cross-attempt receipt cannot block the node or run. Ordinary
`blocked(reasonDigest:)` remains available for genuine internal failures, so
the new rule does not misclassify every blocker as external.

## Domain-neutral adversarial scenario

The acceptance fixture uses only opaque identities. An undeclared dependency
cannot create a receipt; the worker cannot self-observe; a substitute recipe is
rejected; an `available` observation cannot support unavailability; and a valid
independent `unavailable` receipt encodes, decodes, and replays byte-stably
before it can block the exact attempt. Legacy contracts, compiler candidates,
and run states without the new optional fields still decode.

## Verification

- focused reducer/compiler suite: **45 tests, 0 failures**;
- complete source suite: **580 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **580 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  direct executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `8cbfcdba71e73cfd0102e18e6d8db28c4de23b879c734ce2da6e217efd4665ad`
- focused log: `e03905f6b58a923edcfedac7afc41473b73a45adbd7ae94c7246e3b72a82a8ff`
- full source log: `c036330f12e97a7015d97c536dc974091d3c0e01ef10b2ccd348a2c126860941`
- package test log: `a111d7716e6d8c4ea917a7de8c8e45f7858b20c7985e77a4887eee871d315004`
- package command log: `1c1f1d6fd32571c2fb70f530ba6919331b79055b3eab2cd0ac0cc794f6795797`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `eb6db72f1eedaf5bef49e546d4766549c93adab10f858dd81c1c28bda2a8058a`
- executable: `c4476cbe7a4b1204f98ecffd0285cc57be078a7d171c24126cffd305aa74d78d`
- ZIP: `cb54f2ce4d8ad55a10cc65fc40fbf17d58c16ee938317ec821e8fcbe582fa789`
- DMG: `71c0b9d454347c09ab64c5b7dda9e1fcc927816295675a51925653573871580e`
- CDHash: `2cf331654ee38696debb7229e149fd04c5dac715`

## Boundary

This advances source-level acceptance row B-06. It does not make the legacy
Graph authoritative and does not enroll the stopped task. Native dependency
authoring and user confirmation, production run enrollment/controller cutover,
current native UI verification, a clean commit, and push remain mandatory.
EasyBusiness remained permanently stopped and read-only.
