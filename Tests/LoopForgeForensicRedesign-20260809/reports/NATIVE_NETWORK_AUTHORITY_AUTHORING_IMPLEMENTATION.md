# Native Worker-Network Authority Authoring

Status: **implemented, package verified, and proven default-off through the exact packaged native UI; production provider harness and launch remain vetoed**

Recorded: `2026-08-15T23:12:00Z`

## Defect

The provider compiler correctly required both an enabled worker network policy and an exact `kernel.network-access` capability, but native authoring hard-coded both values off. A user therefore had no way to make that authority decision. Provider diagnostics could name the missing grant, but the composer could not create it. This was a systemic authority-path gap, not a missing display label.

## Repair

The Journaled Auto Graph composer now exposes one explicit `Allow worker network access` toggle. It is off by default and changes only the worker profile. The independent reviewer remains read-only, offline, plugin-free, and minimally isolated.

Native authoring now enforces exact equivalence:

- enabled worker networking requires exactly `kernel.network-access`;
- the grant is rejected as dormant when worker networking is disabled;
- unknown capability IDs reject before compilation;
- the capability is retained in the authority ceiling, execution-plan node, and causal strategy route;
- a separate user-authored source artifact and explicit constraint bind the exact selected capability bytes;
- capability bytes contribute to the native identity digest;
- the compiler receives one non-Codable grant receipt per selected capability, bound to contract ID, candidate revision, the complete authority-ceiling digest, authoring nonce, capability ID, timestamp, and exact user identity/lineage;
- the receipt digest contributes to the compiled candidate digest and survives into ratification.

The existing compiler boundary is retained: a model-authored/decoded candidate cannot serialize a grant receipt, an explicit source constraint alone grants nothing, and missing, duplicate, stale, wrong-user, or ceiling-mismatched receipts fail closed.

The confirmation sheet displays the exact capability ceiling alongside provider protocol, credential mode, worker network policy, and the invariant that the independent reviewer remains offline. Enabling the toggle does not select, ratify, package, or launch a provider harness.

## Tests

The focused native-authoring test passed **16 tests with zero failures**. The broader compiler, enrollment, provider, and persistence selection passed **86 tests with zero failures** in 21.712 test seconds. New coverage proves default-off authoring, exact user source binding, nonempty compiler grant-receipt identity, plan/strategy/ceiling equality, candidate-digest change, missing-grant rejection, dormant-grant rejection, and unknown-capability rejection.

An independent full source suite passed **840 tests, 8 explicit skips, and 0 failures** in 63.246 test seconds (63.295 wall).

## Exact package

The corrected package binds Git revision `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`, dirty-source snapshot `4dad397e664536c5a79c980edeb93487091168e8f3bf6d78c73804875328d6f4`, and package test-log digest `c3d4be9e4d9d58be6fafcf4fa90a3dd6b9d1c65d3d78744dc6f98c0c4d861de3`. The package-owned suite passed **840/8/0** in 62.826 test seconds (62.874 wall); its real Codex bridge passed in 10.495 seconds.

Both non-DEBUG arm64 products built. Deep strict ad-hoc signing, source/test-manifest binding, ZIP, DMG, checksum manifest, exact packaged-Mach-O bounded startup, Release test-hook absence, smoke, cleanup, and zero residual packaged processes passed.

- app executable: 25,405,536 bytes, SHA-256 `f51412e2da983bc3d9cdc0531e45bd29325c409ffd6c4692ef70037676a7e970`, CDHash `deee495588e8b5ef2d54f29e6db84abe32d27a00`;
- sandbox gate: 78,512 bytes, SHA-256 `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`, CDHash `138982f66022e1d20d76823282ff6a9fc507d3b6`;
- ZIP: 253,152,293 bytes, SHA-256 `b11959be659089feb119d1fcc219a6b6390f1bab9b3a2e6ac7ecc2b5815aff9e`;
- DMG: 285,448,183 bytes, SHA-256 `93147011e33ab1230dd2f33e35ff6c22341e051bef3285fd829d0f8188a56877`.

## Native proof

Computer Use opened `/Users/godice/Coding/LoopForge/dist/LoopForge.app`, created a new draft for the LoopForge workspace, and observed:

- `Allow worker network access` was off by default;
- the exact copy stated that enabling it adds only `kernel.network-access` to the user-confirmed contract;
- worker-only networking and the offline independent-reviewer boundary were explicit;
- the UI stated that the toggle does not select, ratify, or launch a provider harness.

No toggle escalation, contract confirmation, enrollment, activation, prompt preparation, provider/verifier/worker launch, mutation, legacy execution, or EasyBusiness action occurred. The app quit and zero exact packaged processes remained.

Screenshot: [Packaged default-off network authority](../screenshots/packaged-loopforge-network-authority-default-off-20260815T230946Z.jpeg), 1160×768, SHA-256 `6ab38b1acbd7bb8752ef05e42a1a4e926ebd214b5ab3e85f83dc94cdf0a3790b`.

## Boundary

This closes the absent native network-authority decision seam. It does not package or independently ratify a production LoopForge Provider Harness V2. The current default execution profile still uses the unavailable harness protocol, so provider compilation and launch remain vetoed even if a future user explicitly confirms network authority. Trusted Release verifier containment or its retained veto, mutation preparation or its retained veto, the complete native trait/window/baseline/candidate matrix, a rebuild from an exact clean commit, commit, and push remain pending. Final release remains false.

EasyBusiness remained read-only on `codex/USA_Version` at HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04` with unchanged NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
