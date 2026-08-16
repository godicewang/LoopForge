# Native Design-Baseline Confirmation Authority

Status: **production protected-artifact-bound issuer, native capture-source selection, and post-enrollment confirmation implemented; complete visual-evaluation issuer remains pending**

Recorded: `2026-08-14T14:57:22Z`

## Closed authority gap

Release preparation no longer accepts a caller-constructed
`DesignBaselineBundle`, and it no longer contains a compile-time branch that
rejects every visual baseline because no production issuer exists.

The new boundary separates three facts:

1. `NativeDesignBaselineSelection` is replayable proposal/display data and has
   no authority receipt or freeze time.
2. `NativeDesignBaselineConfirmationDraft` is non-Codable and can be created
   only after exact ratification, enrollment-frame, protected-artifact, capture,
   invariant, debt, and SHA-256 validation.
3. `AuthorizedKernelDesignBaseline` is a live non-Codable capability minted
   only by an explicit main-actor native user confirmation over the exact
   canonical selection digest.

The capability binds the run, ratification receipt, enrollment journal frame,
contract, protected artifact, selected native capture matrix, and confirming
user identity/lineage. The confirmation issuer—not decoded evidence—creates the
`productDesignAuthority` receipt and freeze time. It is single-use for one
run/baseline/digest tuple.

`KernelExecutionPreparationCoordinator` now consumes this exact capability in
Release. The baseline command uses the confirming product-design actor while
plan, convergence, node, and attempt commands retain the enrolled kernel actor.
Cross-wired enrollment, ratification, frame, contract, artifact, displayed
digest, or user lineage rejects before the journal batch. A DEBUG-shaped raw
baseline wrapper is also rejected by production preparation and leaves the
journal sequence unchanged.

## Deterministic selection identity

The selection digest canonicalizes requirement IDs, capture ordering,
invariant cell sets, invariant ordering, debt cell sets, and debt ordering
before sorted-key, millisecond-date JSON encoding. Native selection validation
requires:

- one preservation-required contract baseline whose artifact SHA-256 exactly
  matches the selected built artifact;
- a non-empty contract requirement subset;
- exact lowercase SHA-256 source, build, protocol, token, semantic, fixture,
  raster, accessibility, navigation, optional trace, and debt identities;
- complete captures unique by receipt and visual cell, captured before the
  confirmation display boundary with matching source/build/protocol;
- unique non-empty protected invariants whose cells are fully captured; and
- finite, unique, evidenced, invariant-bound known debt.

No process, lease, external effect, workspace mutation, verification verdict,
integration acceptance, publication, or completion fact is created by baseline
selection or confirmation.

## Process-probe defect found during packaging

The first package-owned full suite exposed a pre-existing race in the executable
startup probe: a state-only PID observation could mistake rapid PID reuse for
the original direct child and accept an exit-7 fixture. That package attempt
failed and counts zero. The probe now requires both a non-zombie state and the
original shell parent identity; cleanup repeats the same ownership check before
TERM or KILL, so it cannot signal a reused unrelated PID. The focused test
passed three consecutive runs, and the next package-owned complete suite
passed.

## Verification

- focused native baseline authority/preparation tests: **2 passed, 0 failed**;
- focused process-probe regression: **3 consecutive passes**;
- exact final-source suite: **769 tests, 8 intentional environment skips,
  0 failures** in **69.209 test seconds**;
- package-owned suite: **769 tests, 8 intentional environment skips,
  0 failures** in **73.563 test seconds**;
- non-DEBUG Release build: **passed** in **98.16 seconds** before the final
  package build;
- ad-hoc deep strict signature, ZIP, DMG, checksums, manifest binding, bundled
  tool probes, exact packaged Mach-O startup, and cleanup: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  executable count: **0**;
- EasyBusiness HEAD remained read-only at
  `2ae40452e6d8661c46db466c43ea40bba3bfab04`.

Source identities:

- `NativeDesignBaselineConfirmation.swift`:
  `d25fbcc92df3b90ac530823a5383c1a468779718570e70547730a7d9abb0488c`;
- `KernelExecutionPreparationCoordinator.swift`:
  `115d9900219c214cab9acb09139cf6b1acaecf671b6850e74303c9f8e1b95485`;
- `RunReducer.swift`:
  `e93273a58834e62ead9c5a2dbf6a58fe831644e4ab538fb410f4b48e50eb844c`;
- `KernelRunEnrollmentCoordinatorTests.swift`:
  `51f47917a9feec0d445903ba62a80526df547df8d3fcde85dcc8aa1152f8cc3b`;
- `probe_executable_startup.sh`:
  `39e2ba3ccccb87d1a7b818b38eb4430ea6e9e5e52fc8283a025747de28b05dc8`.

Historical package identities (superseded by the capture-source source snapshot):

- signed app Mach-O:
  `58ff65022d2f4b4d84e13ddcf4b6bf484059fb47cfc7b72ff6dc54407c5bfe2c`;
- signed sandbox gate:
  `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`;
- ZIP:
  `4c33b06d8ca5acd369fb2060f210a4722a0ec502ce8052da7179e3a016ab9138`;
- DMG:
  `8cbf33a3dd3515d130c6ff436dca2d604651ab835b113898c4bf57e3e6919bcd`;
- package test log:
  `8fe0ee98f4703fd5c38f9b4322e7cbc553f720177764b8872c4fb2da707dad55`;
- exact source snapshot:
  `5b9790bf61c117596afcdc0549f24d5aa3d9e00c874a2c2e5785669a3a2760aa`.

## Remaining vetoes

The real native UI now imports a schema-constrained capture source, rehashes
protected artifacts with descriptor-bound no-follow reads, routes raw evidence
through the native adapter, binds the result into the contract, and displays a
second exact post-enrollment confirmation. Live deterministic per-cell
measurement authority is now present; complete native visual-candidate matrix
assembly and independently activated visual reviewer authority,
final authorization, external-dependency runtime observation, trusted Release
resident-memory containment (or the retained pre-apply veto), legacy
Single/Parallel retirement, unlocked current native screenshots, clean commit,
and push remain required. Final acceptance remains false.

The follow-on implementation and its accepted 773-test/Release evidence are in
`NATIVE_DESIGN_BASELINE_CAPTURE_SOURCE_UI_IMPLEMENTATION.md` and the matching
machine-readable scorecard. The signed 769-test package identities above are
historical: the capture-source implementation changed the exact source
snapshot, so a current-source signed package remains pending.

The measurement follow-on is documented in
`NATIVE_VISUAL_MEASUREMENT_AUTHORITY_IMPLEMENTATION.md` and its scorecard.
