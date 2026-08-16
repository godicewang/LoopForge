# Typed Progress Provenance Enforcement

Status: **F-02 causal/evidence provenance gate implemented and package-verified; production issuance cutover pending**

Recorded: `2026-08-11T06:55:35Z`

## Defect confirmed

The initial journal-duration gate checked that `progressReceiptID` named a
processed journal command, but did not prove that command was a causal progress
evaluation. `evidenceReceiptIDs` were checked only for non-empty strings. A
create-run, plan, or unrelated lifecycle command could therefore be named as
progress provenance, while invented evidence identities could be attached to
an occurrence. Accepted duration still required an accepted-progress ID, but
the occurrence provenance boundary itself was structurally forgeable and
misleading diagnostics could enter replay.

## Repair

- reducer state now retains every typed causal-progress command separately
  from the accepted-progress subset;
- both sets are rebuilt exclusively by replaying
  `progressEvaluated` events;
- occurrence progress bindings must name a typed causal-progress transaction,
  not merely any processed command;
- occurrence evidence must name a typed reducer receipt or a typed causal
  progress transaction;
- prior occurrence receipts are excluded from the evidence authority set, so
  counted time cannot recursively certify later time;
- stagnant causal progress remains recordable for diagnosis, but only the
  accepted subset contributes duration;
- `RunJournal` exposes both projections explicitly for recovery and tests.

## Adversarial verification

The reducer test inserts a forged progress ID into `processedCommandIDs` and
proves it is still rejected because it did not arise from a causal-progress
event. A second fixture uses a valid accepted progress binding with an invented
evidence ID and proves the occurrence is rejected. Journal replay preserves
both accepted and stagnant causal-progress IDs while the accepted projection
contains only the improving transaction.

## Verification

- reducer suite: **31 tests, 0 failures**;
- journal suite: **16 tests, 0 failures**;
- complete source suite: **601 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **601 tests, 8 environment-gated skips, 0 failures**;
- exact-source release, ad-hoc signature, ZIP, DMG, checksum manifest,
  executable startup, cleanup, and zero residual packaged processes passed.

Receipts:

- source snapshot: `14b4610930e88b11007d660ad98704ee5461e2ef5d8a0fdcda70582a1b007607`
- reducer source: `c22cb62d84910bf2db080368c4e3a1bdd9844ded6ca6df26fc201fb17561c688`
- journal source: `f18039546095126c138f90a9616634781f735a312995814425f269a009a5dbab`
- reducer tests: `8b33ff43ef4a3c02982ae70adacb5b6827efa4ce51047fc28a8bc61536d06253`
- journal tests: `7fce422ee091260925b2a96485d02bcb8cc8e1082b95003fbfa27bca3d493004`
- complete test log: `3c09646c7f7a0e019b4d2a1fec5c00cf3a7ffd6d1615c7fb8ff118879d25ca70`
- package test log: `c2b765e2ea0f956bda1c982c73eef962322f5ee1bfa652fa5cbc3c7f7d5955bf`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `4bef0ced44ed67380097967680d381ed0f7e02987c3fcdb17c0d4dc8f3897bd3`
- executable: `6f99b8ab85b1026d1f27c1a8f2e4f6a0ad738dec6d1952f7700b7309a5ccc9c9`
- ZIP: `821330a27cc04727338d7c60c385d36228b8bd2b029477724556257f2ca59b40`
- DMG: `735355d374c872120fd496779c70d99f4389f1e66dc547d77509aef9fed7ea49`
- CDHash: `68676f5de2cc3ef2ff13ea43f1f6d5bf444abf71`

## Boundary

This prevents arbitrary journal commands and invented IDs from entering the
occurrence provenance chain. Production task enrollment, trusted occurrence
issuance from owned execution, legacy controller removal, current unlocked
native proof, a clean commit, and push remain pending.

EasyBusiness remained permanently stopped and read-only.
