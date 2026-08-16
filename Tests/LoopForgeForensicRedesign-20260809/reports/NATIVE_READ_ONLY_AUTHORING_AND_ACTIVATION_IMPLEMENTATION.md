# Native Read-Only Authoring and Activation

Status: **implemented, source/package verified, and proven through the exact packaged native UI; final release remains false**

Recorded: `2026-08-15T21:47:00Z`

## Defect

The production kernel already supported a zero-mutation `readOnly` worker profile, and the independent reviewer was always forced to that profile at execution time. The real task composer nevertheless exposed only Workspace Only and Full Access to the worker while misleadingly showing those same choices for the reviewer. The safest production path could not be selected, and the visible reviewer authority did not match the kernel's enforced authority.

## Repair

Role-specific access policy now has one source of truth:

- the Main Graph independent reviewer exposes only Read Only;
- the Node Loop worker exposes Read Only, Workspace Only, and Full Access;
- new drafts default the reviewer to Read Only and the worker to Workspace Only;
- role-aware mutation rejects any attempted reviewer escalation;
- reset restores the same explicit defaults;
- legacy decoded authority remains historical data and is not silently rewritten.

This does not broaden any execution authority. Read Only still compiles to a zero-file, zero-byte mutation ceiling with disabled network and plugins. Workspace Only remains the default worker choice, so inspection-only operation is an explicit user decision rather than hidden inference.

## Tests

Focused `TaskStoreTests` passed 20/0 in 10.305 seconds. The exact read-only activation test passed 1/0 in 1.084 seconds, and the corrected read-only sandbox test passed 1/0 in 0.001 seconds. The first graph test filter named a nonexistent test and ran zero tests; it counts zero and was replaced by the exact test name.

The clean full source suite passed **837 tests, 8 explicit skips, 0 failures** in 59.796 test seconds (59.845 wall), including the real Codex bridge in 6.767 seconds. The package-owned suite passed **837/8/0** in 66.951 test seconds (67.000 wall), including the real Codex bridge in 13.973 seconds.

## Exact package

The signed package binds dirty-source snapshot `8ecc27fc6116e5d120f4a77ad847e5ef3800c4e952785dc1d74bc7ea3cdb2f70` and package log `1c0848e672072846a985a414c945cb8f69b257dc13602095869bceeb616c9db1`. Deep strict signature, ZIP, DMG, checksum manifest, exact packaged-Mach-O startup, smoke, and Release test-hook absence passed. The app executable is `9c6bc2ae9daedcf89933eb35d3d6e3e37597a43e8572430d8dc589b925b9d12c`; the sandbox gate remains `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`.

## Native proof

Computer Use operated `/Users/godice/Coding/LoopForge/dist/LoopForge.app` directly. The composer showed exactly one reviewer option, Read Only, and all three worker choices. It selected Read Only for the worker, the exact LoopForge workspace, the explicit source exclusions `.build, .git, .loopforge, .swiftpm, .vendor, DerivedData, Tests, dist`, and the packaged verifier.

The confirmation sheet bound:

- source revision `7f435175a998de9100814aa7303256306f8ab6745ba74f0bcf2c1a40fd03f72c`, 164 files, 6,472,476 bytes;
- no writable paths;
- mutation ceiling 0 files / 0 bytes and mutation cost 0;
- worker and independent reviewer sandboxes both Read Only;
- disabled network and plugins for both roles;
- candidate digest `bde2f9f997cdf2f159c9bbcd093811e4ed7cd76a778db459772118778b00da9a`.

Enrollment created `native-run-48b4997c-4d31-4c02-909f-f3d30dd71b70` at journal sequence 1, phase `ready`, with no blocker and an enabled `Activate Native Attempt`. Explicit activation advanced only that run to epoch `native-dea35366-1b45-4d0c-9ccd-53f18a3cd3ae-epoch`, sequence 6, phase `executing`, with `Mutation Δ 0`, `verification Δ 1`, external effects 0, and failures 0. The native alert stated that no legacy task or Graph worker was created and provider launch remained separately receipt-gated.

After quit and exact-package relaunch, the new run remained executing and no activation control was reconstructed for it. The older Workspace Only run remained inert. No provider, verifier, worker, legacy execution, or product mutation was launched. After the receipt was acknowledged, the app quit and zero exact packaged processes remained.

That retained `executing` state was later confirmed as a lifecycle defect rather
than an acceptable terminal projection. The current package closes it by making
receipt-proven stop quiescence interrupt the unfinished attempt and by routing
normal quit through retained native sessions. See [Native Termination and
Quiescence Hardening](NATIVE_TERMINATION_QUIESCENCE_HARDENING.md). The screenshots
below remain accurate evidence of the older package and are not relabeled as
current behavior.

Screenshots:

- [Read-only contract](../screenshots/packaged-loopforge-read-only-contract-20260815T212900Z.png)
- [Ready and activatable](../screenshots/packaged-loopforge-read-only-ready-and-activatable-20260815T212900Z.png)
- [Activated and executing](../screenshots/packaged-loopforge-read-only-activated-executing-20260815T212900Z.png)
- [Executing after relaunch, not recovered as ready](../screenshots/packaged-loopforge-executing-run-not-recovered-as-ready-20260815T212900Z.png)

## Boundary

This closes the native read-only authoring and explicit activation gap. It does not claim a provider launch, verifier execution, full trait/window/baseline/candidate matrix, trusted Release containment, mutation-backed production execution, clean-commit rebuild, commit, or push. Final release remains false. EasyBusiness remained read-only evidence.
