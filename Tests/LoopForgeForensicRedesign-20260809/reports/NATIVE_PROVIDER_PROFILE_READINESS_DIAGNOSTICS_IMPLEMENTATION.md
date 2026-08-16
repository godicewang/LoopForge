# Native Provider-Profile Readiness Diagnostics

Status: **implemented, package verified, and proven through the exact packaged native UI; provider launch remains vetoed and final release remains false**

Recorded: `2026-08-15T22:11:00Z`

## Defect

The provider compiler already failed closed when the worker executable was not a ratified LoopForge Provider Harness V2 or when a remote provider lacked network authority. Native diagnostics did not project those reasons. A run could enter the intentionally separate `executing` journal phase while the UI said only that provider launch was separately gated, leaving the next boundary opaque. The ready-run card also used the same “no strategy or worker has been admitted” sentence for every phase, which was false for an active native attempt.

## Repair

Provider-profile readiness is now a typed, deterministic assessment over the exact worker execution profile and authority ceiling. It records ordered blockers for:

- invalid provider/model/executable identity;
- unavailable or retired provider-harness protocol;
- missing remote-provider network policy or `kernel.network-access` grant;
- unsupported user-installed plugin authority;
- invalid exact credential authority.

The assessment is deliberately narrower than launch readiness. It does not claim that a prompt, nonce, invocation-context transport, secret capability, sandbox, lease, process binding, or launch receipt exists. Journal activation remains a separate action and is not silently blocked or promoted by these diagnostics.

The read-only enrollment preflight now binds the assessment to the exact journal source frame. Production activation copies the same assessment into the non-Codable session receipt from the retained contract. `AppModel` projects the ready assessment before activation and the session-owned assessment afterward. Native diagnostics distinguish `ready` from `executing`, and show the exact blocker list rather than a generic provider-gated sentence.

## Tests

The focused provider and native-enrollment suites passed **26 tests with zero failures** in 11.326 test seconds. New adversarial coverage proves that unavailable protocol, absent network grant, unsupported plugins, and invalid credential authority remain distinct blockers, while an exact local V2 profile is accepted only at the profile-compilation layer.

The exact package-owned suite passed **839 tests, 8 explicit skips, and 0 failures** in 61.998 test seconds (62.047 wall). The real Codex child/Responses bridge passed in 8.783 seconds. The 2-test increase is the new provider-readiness coverage.

## Exact package

The corrected package binds Git revision `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`, dirty-source snapshot `6903695bfce7743d2cc582420ff28f2e64b56a28731150e06ad037ceb80c4306`, and package test-log digest `a69bbea9314604399692d23f69f959c4d516b2c020899738439afa416fc9c14c`. Both non-DEBUG arm64 products built; deep strict signing, ZIP, DMG, checksum manifest, source/test binding, exact packaged-Mach-O startup, smoke, and cleanup passed.

The app executable is `e43d0f3c0ab57092ea0f5e0097487782e8b4091c95963f3230bd9c02fb7702b6`, application CDHash `d0a4f39f98a10fa71e16c686eb28ca43bff125bb`, and sandbox gate `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`.

## Native proof

Computer Use opened `/Users/godice/Coding/LoopForge/dist/LoopForge.app` and the real Kernel diagnostics sheet. For retained ready run `native-run-c2070190-a24a-42bf-a9f5-fee696aea42c`, the exact package displayed:

- `Requirements 0 / 1 · no native attempt admitted`;
- the two separate mutation-preparation blockers and a disabled activation control;
- `Provider invocation blocked · 2 exact profile constraints`;
- the exact missing V2 harness and remote-network-authority explanations.

The prior read-only run remained journal-derived `executing` at sequence 6 with one active attempt, mutation delta zero, one verification activation, zero external effects, and zero failures. The walkthrough performed no activation, provider preparation, provider launch, verifier launch, worker launch, mutation, legacy execution, or EasyBusiness action. The app quit and zero exact packaged processes remained.

Screenshot: [Packaged provider-profile blockers](../screenshots/packaged-loopforge-provider-profile-blockers-20260815T220900Z.png), 860×760, SHA-256 `583f37760e1c9e46c7b1d44c3a30ac872c969b820a8af85826c4a48d6dfefa2e`.

## Boundary

This closes the misleading provider-readiness diagnostics gap. It does not supply or ratify a V2 provider harness, issue network authority, prepare a provider prompt, launch a process, execute a verifier, complete the full native matrix, rebuild from a clean commit, commit, or push. Final release remains false. EasyBusiness remained read-only at HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04` with unchanged NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
