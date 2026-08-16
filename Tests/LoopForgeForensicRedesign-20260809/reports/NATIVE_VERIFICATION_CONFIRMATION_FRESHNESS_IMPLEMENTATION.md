# Native Verification Confirmation Freshness

Status: **confirmation-time manifest and executable revalidation implemented, tested, packaged, and selector-inspected; activation and production execution remain separate gates**

Recorded: `2026-08-15T19:28:28Z`

## Closed confirmation gap

The native selector already opened and hashed a stable manifest and executable before contract review, and activation already required later restaging and rehash. A time-of-check/time-of-use gap remained between those boundaries: confirmation ratified the displayed draft without reopening the selected files. A user could therefore confirm after the manifest or executable had been substituted, even though later activation would reject the stale executable.

`NativeVerificationProbeSelectionLoader.revalidate(_:)` now reloads the selected manifest and executable through the same no-follow, stable-regular-file boundary used by selection and requires the complete refreshed selection to equal the reviewed selection. A mismatch produces the typed `selectionChanged` error.

Immediately before ratification, `AppModel.confirmAndEnrollNativeAutoGraphContract()` now:

- requires a real native selection in non-DEBUG builds, so test-only probe injection cannot enter production confirmation;
- reopens and revalidates that selection on a detached task;
- rejects a selection changed while the asynchronous revalidation was running;
- requires every compiled evidence recipe to carry the exact refreshed executable probe;
- returns before contract ratification, enrollment identity creation, journal creation, or registry registration on any mismatch.

Display paths remain non-authoritative staging hints. Confirmation freshness does not replace activation-time staging and rehash.

## Adversarial verification

- Selection loader suite: 5 tests, 0 failures, 0.017 test seconds. It proves unchanged revalidation and executable-byte substitution rejection.
- Native enrollment substitution test: 1 test, 0 failures, 1.077 test seconds. It selects and reviews an exact verifier, replaces the executable before confirmation, and proves that the contract remains pending, no enrollment receipt exists, the task store and run registry remain empty, and the native alert reports drift.
- Pre-package full suite: 829 tests, 8 intentional environment skips, 0 failures, 59.565 test seconds.
- Package-owned full suite: 829 tests, 8 intentional environment skips, 0 failures, 55.642 test seconds; the real Codex bridge passed in 9.866 seconds.

Two intermediate focused invocations failed during compilation (conditional syntax/member access, then an async XCTest autoclosure). Both were corrected without weakening the boundary and count zero.

## Package and native receipt

The rebuilt ad-hoc-signed package is bound to dirty-source snapshot `cd020030c179bc2dc5580c6f5f3bfa03a53c810d2a768242ca9c6e3b20034c3a`, executable SHA-256 `ebb1e8a96a93ecf6565607b06ae00ad591340e3727964755f17a2e27dc9ff8b7`, and application CDHash `1f51eb4af0d3728c100b9cd42210de8b5a29287f`. Deep signing, source/test manifest binding, ZIP, DMG, checksums, exact packaged-Mach-O startup, cleanup, and zero residual packaged processes passed.

Computer Use opened that exact package, selected the retained workspace manifest through the native file panel, and observed packaged `KernelSandboxGate`, SHA-256 `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`, one fixed argument, and two result mappings. The 1160×768 screenshot is retained at `../screenshots/packaged-loopforge-verifier-confirmation-freshness-20260815T192548Z.png` with SHA-256 `8f6d73d8c183760f1bc30df70fc5819aa5be2c135a1b77ce5e64c169481b8591`.

The native walkthrough stopped before estimation, contract review, confirmation, or enrollment. `KernelSandboxGate` is selector evidence, not a claimed production verifier execution.

## Remaining boundary

Activation-time executable staging/rehash, trusted Release containment or the retained veto, a real production verifier run and result issuance, the separately packaged provider harness and exact network authority, mutation preparation or retained vetoes, legacy Single/Parallel retirement, the complete native visual matrix, a clean-commit rebuild, commit, and push remain required. Final release is false.

EasyBusiness remained read-only at HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04`; its established `git status --porcelain=v1 -z -uall` fingerprint remained `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
