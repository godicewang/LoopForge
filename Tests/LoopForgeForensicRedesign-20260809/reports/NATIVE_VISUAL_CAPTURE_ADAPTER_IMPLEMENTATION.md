# Native Visual Capture Attestation Boundary

Status: adapter implemented and verified; concrete production harness and legacy Graph connection remain open.

## Root cause closed by this slice

The immutable visual gate previously consumed `NativeCaptureReceipt`, but there was no trusted component that created one. A controller or worker could construct the public fields itself, choose an image digest, repeat expected dimensions, claim a clean install, and assign a convenient timestamp. The gate correctly validated relationships among receipts, but it could not prove that receipt facts originated from decoded native evidence.

`NativeVisualCaptureAdapter` is now the only implemented generation boundary for attested native captures. The orchestrator fixes the visual cell, source tree, built artifact, capture protocol, expected trait matrix, navigation recipe, authority time boundary, and required traces. An allow-listed harness returns only observed bytes and primitive lifecycle outcomes. The adapter—not the harness—sets capture time, decodes the image, measures dimensions, computes every digest, and constructs the receipt identity.

## Fail-closed trust model

The adapter rejects a capture before it can become gate evidence when any of these conditions holds:

- capture limits or request provenance are incomplete;
- the harness identity is not explicitly allow-listed;
- the harness throws or exits non-zero;
- capture time precedes the authority boundary;
- full-viewport or clean-install lifecycle proof is absent;
- observed locale, viewport, scale, OS, accessibility, appearance, or fixture traits differ from the requested matrix;
- image or semantic evidence exceeds bounded memory limits;
- the image is empty, multi-frame, non-PNG, undecodable, oversized, or reports dimensions different from decoded pixels;
- accessibility, lifecycle, component-boundary, or token evidence is malformed;
- a required component or design-token trace is missing.

The API accepts artifact bytes rather than paths. A worker therefore cannot pass validation and later replace a symlink or rewrite the evidence file. The encoded PNG digest is retained for artifact identity, while the normative image digest is computed from decoded width, height, and canonical RGBA raster bytes so PNG metadata cannot masquerade as a visual change. Accessibility and lifecycle evidence keep exact byte digests after structural JSON validation.

The final attestation digest length-frames the request digest, decoded pixel digest, encoded image digest, accessibility digest, lifecycle proof, optional trace digests, and adapter clock. That digest becomes the capture identifier. Changing a trusted request input or observed artifact necessarily changes the receipt.

## Adversarial verification

Nine focused tests pass with zero warnings and zero failures. They prove:

1. only an allow-listed harness can be invoked;
2. source, artifact, protocol, trait, time, dimensions, and all digests are adapter-computed;
3. harness failure and non-zero exit fail closed;
4. claimed traits cannot override decoded viewport dimensions;
5. invalid and oversized rasters are rejected;
6. malformed accessibility or lifecycle evidence is rejected;
7. missing or malformed component/token traces are rejected;
8. a clean-install boolean without evidence and a pre-authority clock are rejected;
9. trusted navigation input changes expire both request and attestation identity.

The complete Swift suite executes 453 tests, skips 6 environment-gated tests, and reports 0 failures. The production source contains no application-, customer-, industry-, screen-, or device-specific policy. `git diff --check` passes.

One earlier focused invocation passed its assertions but emitted concurrency warnings in the initial test double and default clock. That invocation is excluded from the strict ledger. The clock is now an explicit Sendable closure, the harness double is an actor, and the warning-free focused and complete suites are the retained evidence.

## Exact artifacts

- `Sources/LoopForge/Kernel/NativeVisualCaptureAdapter.swift`: 371 lines, SHA-256 `64a967513cec2b3d63079fb4660fb215683cd6b3439b34a12857677d019a307e`.
- `Tests/LoopForgeTests/NativeVisualCaptureAdapterTests.swift`: 326 lines, SHA-256 `ba00a152a921fb0b69cabd024ae692cbdbcc3f61dfe25f8c63cc9f5b871f22e8`.
- Warning-free focused log: `/tmp/loopforge-native-capture-tests-clean.log`.
- Warning-free complete-suite log: `/tmp/loopforge-full-tests-native-capture.log`.

## Open boundary

This slice does not claim that current Auto Graph produces trusted native receipts. A concrete production harness still must be independently identified, resource-supervised, packaged, and connected through a Graph-to-kernel adapter. Attestations must then be journaled with the candidate and consumed by the existing visual authority transaction. Transactional integration/publication, historical shadow replay, controller migration, receipt-native UI, latest package/sign/hash, native app verification, commit, and push remain mandatory.

EasyBusiness remained read-only.
