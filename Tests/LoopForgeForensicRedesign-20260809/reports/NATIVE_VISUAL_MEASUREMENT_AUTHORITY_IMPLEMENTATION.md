# Native Visual Measurement Authority

Status: **live candidate-capture and deterministic measurement authority implemented; complete matrix composition and independent adversarial-review issuer remain pending**

Recorded: `2026-08-14T15:20:14Z`

## Closed authority gap

`NativeVisualCaptureAdapter` now has a production `captureAuthorized` boundary. It retains the existing durable `AttestedNativeCapture` evidence but wraps it in a non-Codable `AuthorizedNativeCapture` whose initializer is file-private. A decoded capture receipt or attestation cannot recreate the live value required by downstream deterministic measurement.

`NativeVisualMeasurementAdapter` accepts one frozen baseline receipt and one live candidate-capture authority for the same visual cell. Before invoking a measurement harness it requires complete receipts, exact traits and capture protocol, ordered capture time, a non-empty protected-dimension set, and an exact measurement-protocol identity. Only an allow-listed harness identity may run.

The harness can report structured measurements and raw evidence, but it cannot select the cell, capture pair, traits, protocol, protected dimensions, authority time, or evidence receipt ID. The adapter rejects a harness-supplied receipt ID, nonzero process exit, malformed/non-container JSON evidence, oversized evidence, pre-boundary time, cell mismatch, missing required measurements, nonfinite values, and negative maximums. It hashes the sorted request, raw evidence, normalized measurements, harness identity, and adapter-owned time; then it assigns the sole evidence receipt ID and returns a non-Codable `AuthorizedNativeVisualMeasurement`.

Dimension completeness is explicit for product identity, initial task hierarchy, typography hierarchy, symmetry/alignment, spacing/density, shape language, occlusion/safe area, responsive composition, accessibility, and localization/slot fit. Provenance/comparability remains the matrix compositor's responsibility, while the independent product-design verdict remains a separately activated reviewer responsibility.

## Verification

- focused authority tests: **5 passed, 0 failed**;
- exact final-source suite: **778 tests, 8 intentional environment skips, 0 failures** in **60.577 test seconds**;
- non-DEBUG Release build: **passed** in **92.60 seconds**;
- `git diff --check`: **passed**;
- residual exact LoopForge/gate/fixture process count: **0**;
- EasyBusiness remained read-only at `2ae40452e6d8661c46db466c43ea40bba3bfab04` with unchanged status digest `a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.

Source identities:

- `NativeVisualCaptureAdapter.swift`: `55a7096484be92bff73e7cdf16e45056c72ad47d6a500e9c6c667faa2cb5197f`;
- `NativeVisualMeasurementAdapter.swift`: `2728f2bc9a603e1681e0d554e359775fe8ef1d491b8015c8fc80e5865bee80d5`;
- `NativeVisualMeasurementAdapterTests.swift`: `051bc6fc8cb9a45a9e1054d6816d1b6cbe716ec8cc3df32ffd581b92ddd56ce5`;
- current exact dirty-source snapshot: `b1554e9e428970dcad2566a617c4119a0ba3f80ff51d8cd6ede4968704a9c19e`.

## Remaining vetoes

The live measurement authority is intentionally inert: it appends no journal event, starts no process, mutates no workspace, and supplies no reviewer verdict. A complete visual matrix compositor must still require one live candidate capture and one live measurement for every required cell, assemble exact review batches, invoke a distinct ratified reviewer runtime, validate complete per-image and per-pair decisions, and only then mint `AuthorizedKernelVisualEvaluation`. Trusted Release containment (or retained pre-apply veto), external-dependency observation, final authorization, controller cutover, current native screenshots, current-source packaging, clean commit, and push remain pending. Final acceptance remains false.
