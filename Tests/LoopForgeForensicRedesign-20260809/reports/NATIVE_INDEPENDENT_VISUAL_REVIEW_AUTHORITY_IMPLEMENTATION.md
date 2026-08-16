# Native Independent Visual Review Authority

Status: **distinct ratified reviewer authority implemented; journal-bound kernel visual-evaluation composition remains pending**

Recorded: `2026-08-14T15:41:02Z`

## Closed authority gap

`NativeIndependentVisualReviewAdapter` now owns the production boundary between a complete native visual evidence matrix and an independent product-design verdict. Its output is a non-Codable `AuthorizedNativeIndependentVisualReview` with a file-private initializer, so decoded review JSON cannot recreate the live value needed by a future kernel evaluation issuer.

The request binds the exact frozen baseline, baseline PNG bytes, candidate source and build identities, candidate mutation time, one live authorized candidate capture per required cell, every applicable live authorized measurement, the exact mutation manifest, the ratified reviewer execution profile, the reviewer actor, and bounded batch/time limits. Before invoking the review harness, the adapter re-decodes and rehashes every baseline and candidate image against its original pixel receipt, revalidates candidate traits/protocol/time, requires the exact contracted matrix, rejects duplicate or missing cells and measurements, and requires exact known-debt severity coverage.

The reviewer must use the ratified read-only, offline, plugin-free, minimal-environment profile and a distinct lineage. The allow-listed harness identity must exactly match its provider, model, and executable SHA-256. LoopForge builds evidence-only prompts and deterministic gate context itself; worker narrative is not accepted by this API. Harness output is limited to per-image and per-pair decisions, inspected cell IDs, raw response, and exit status. LoopForge validates complete decision coverage and derives the aggregate pass/fail result, prompt/context/evidence/response digests, review ID, and batch receipts. A red review is retained as valid durable red evidence rather than being discarded or promoted.

`NativeVisualCaptureAdapter` now retains the exact raw image, accessibility tree, clean-install evidence, and optional trace bytes behind its live capture authority. It can revalidate later image bytes against the original raster dimensions and pixel digest. `NativeVisualMeasurementAdapter` now binds the baseline's accepted known debt and adapter-validated debt severities into the live measurement authority, allowing the reviewer to require complete and conflict-free debt evidence.

## Verification

- focused independent-review tests: **5 passed, 0 failed**;
- exact final-source suite: **783 tests, 8 intentional environment skips, 0 failures** in **60.731 test seconds**;
- non-DEBUG Release build: **passed** in **100.80 seconds**;
- `git diff --check`: **passed**;
- residual exact LoopForge/gate/fixture process count: **0**;
- EasyBusiness remained read-only at `2ae40452e6d8661c46db466c43ea40bba3bfab04` with unchanged status digest `a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.

Source identities:

- `NativeVisualCaptureAdapter.swift`: `c4d20bdd31f3aaeeaa3bc1edff280a7521f2a67fba45b19be55b84d279fbc7cd`;
- `NativeVisualMeasurementAdapter.swift`: `dd86c1c0f9e10429f5b9ddf73e26e4528bec066993551f374ce67f6a39a2f7ec`;
- `NativeIndependentVisualReviewAdapter.swift`: `bac1c040825d0e45f2bf5f6314a1ddf2954850da2f33c4e6167244d54be3b44e`;
- `NativeIndependentVisualReviewAdapterTests.swift`: `1902aff70cdb0f42c09b5a553bd4d44ecdcc03ea7ee5366b698549ae5c4e1c96`;
- current exact dirty-source snapshot: `1a73df35424b1ae1be186ff49a8d7c75373c44d2e090aa9cbff32d7493d790cd`.

One focused compile attempt failed because a test invoked a stored measurement as a function; it was corrected and counts zero. A complete-suite run whose final summary could not be recovered after output truncation also counts zero. Only the independently observed 783-test successful run above is accepted.

## Remaining vetoes

The reviewer authority is intentionally inert: it appends no journal event, mutates no workspace, and cannot create `AuthorizedKernelVisualEvaluation`. A journal-bound compositor/issuer must still consume the exact live capture, measurement, and independent-review authorities; bind the active run, frozen baseline, candidate mutation, complete matrix, and latest review; and mint the sole reducer-consumable kernel visual evaluation. Trusted Release containment (or retained pre-apply veto), executable external-dependency observation, final authorization, controller cutover, current native screenshots, current-source packaging, clean commit, and push remain pending. Final acceptance remains false.
