# Plan Requirement Ownership Gate

Status: **pure reducer enforcement and package receipts present; native planning and production controller cutover remain closed**

## Closed failure mode

The previous reducer proved only that each proposed node named at least one
known requirement. It did not prove that every mandatory requirement survived
planning, nor that exactly one node was accountable for it. A replan could
therefore omit a mandatory obligation, or assign it to multiple peers whose
individual completion could not establish singular responsibility.

The reducer now rejects the complete plan before emitting `planAccepted` when:

- a node owns no requirement;
- a node names any requirement outside the immutable task contract;
- a mandatory requirement has no owner; or
- a mandatory requirement has more than one owner.

Node failures return the exact node identity and the full unknown-requirement
set. Mandatory-coverage failures return the exact requirement identity and its
complete owner-node set. Empty and duplicate ownership are therefore distinct,
machine-readable failures rather than prose that a planner can reinterpret.

## Determinism and authority

Mandatory requirement validation is ordered by stable raw requirement ID, so
two processes replaying the same contract and proposal reject the same first
invalid obligation despite randomized `Set` iteration. Optional requirements
may remain unowned; making them mandatory is a task-contract authority change,
not a planner decision. Join ownership is not accepted because the current
kernel contract has no typed join-owner declaration. A future join contract
must add explicit reducer semantics instead of weakening the exact-one rule.

This gate is domain neutral. It contains no application, repository, platform,
screen, provider, or artifact vocabulary. It does not invoke a model, normalize
a plan, repair missing IDs, enroll a legacy task, or grant mutation authority.

## Adversarial verification

The focused reducer suite proves empty ownership, unknown identity, omitted
mandatory ownership, duplicate mandatory ownership, deterministic rejection
ordering, and valid orthogonal cycle/scope behavior. The complete source and
packaging-owned suites both passed with the same source snapshot.

- focused reducer suite: **20 tests, 0 failures**;
- complete source suite: **564 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **564 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  direct executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `a7227612b6ece755b33a587fcf2e81e8891c0271fb3a59a075b1ca949b95fbe3`
- focused log: `0d3992ce94a98b2151096366721aacd815412dcd2e9b3668017ac90c562ff480`
- full source log: `6fa5fb749f5a784ecfcc00d75a7b137281863d3f8fe4e873f81a81024a3418c2`
- package test log: `0592b0fc3565cacdc00d1477dbc31834b368f18b72a599eabe5054816c3b1b29`
- package command log: `7e00725895c54338b43f7f804f74c34837b68613a1b5e6ff75f25b4ce04d69ed`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- executable: `e6f23f32329064b5d58bc321362523c2afd074283e9a6a6014c5dd39dc515f64`
- ZIP: `cd030e9e76c75cc6ffdc5e96c9f6f87d702bac175dd46b4ecab550ea3c56e867`
- DMG: `2646cb7891040970d86223e43c88860c67684c117894b734dc21530b22bf7e31`
- CDHash: `afe9ef322cccf07791088ecd335aef75e5ca5495`

The first focused run exposed a historical cycle fixture that also duplicated
mandatory ownership. The fixture was made orthogonal and the suite rerun; that
failed verification interval is excluded from the strict ledger.

## Boundary

This advances source-level acceptance row B-02. It does not prove native plan
authoring, source-span confirmation, baseline binding, production enrollment,
controller cutover, a clean revision, or push. EasyBusiness remained
permanently stopped and read-only.
