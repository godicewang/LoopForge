# Native Design-Baseline Capture Source and UI

Status: **native capture-source import, exact artifact binding, and post-enrollment confirmation implemented; complete visual evaluation issuer and native screenshot walkthrough remain pending**

Recorded: `2026-08-14T14:57:22Z`

## Implemented boundary

The real Auto Graph authoring surface can now select a user-owned JSON design-baseline manifest through a native `NSOpenPanel`. The manifest is proposal data only. It cannot itself issue product-design authority, freeze a baseline, start a worker, mutate a workspace, or advance a journal.

`NativeDesignBaselineCaptureSourceLoader` validates a strict known-key schema, requires canonical absolute paths, rejects symbolic links and special files, and binds every protected source/build artifact to one descriptor with `lstat`, `open(O_NOFOLLOW | O_CLOEXEC)`, and post-open device/inode/size comparison. Protected artifacts are streamed and hashed through the held descriptor under a 512 MiB ceiling. Capture, token, semantic, fixture, raster, accessibility, navigation, and optional trace evidence are bounded and rehashed; token evidence must be a JSON object and semantic evidence a JSON array.

The capture protocol digest is derived from the complete sorted typed request. Raw capture evidence enters the allow-listed one-shot `NativeVisualCaptureAdapter`, which attests the fixed native harness identity, full-viewport lifecycle, clean-install state, zero process exit, exact traits, and the selected evidence digests. The loader retains the live adapter receipts in memory; decoding the manifest cannot recreate them.

## Contract and two-stage native confirmation

The imported manifest digest enters the native task identity. Contract authoring derives one exact `NativeDesignBaselineSelection` from the compiler-generated contract and mandatory requirement IDs, adds an explicit preservation constraint, and creates one preservation-required `BaselineReference` bound to the rehashed built artifact and environment. The replayable source bytes remain visible as user-selected evidence, not authority.

After the first native contract confirmation enrolls the run, LoopForge starts zero workers when a baseline is present. It prepares a second exact confirmation sheet from the retained ratified contract and enrollment frame. That sheet exposes protected artifact IDs and SHA-256 values, the complete selected native capture matrix and traits, raster/accessibility evidence, invariants, accepted debt, and canonical selection digest. Only the explicit **Confirm & Freeze Baseline** action invokes `NativeDesignBaselineConfirmationIssuer` and retains the resulting single-use `AuthorizedKernelDesignBaseline`. Cancelling leaves the enrolled run unfrozen and starts no worker.

Accessibility identifiers are stable for native verification:

- `select-native-design-baseline-button`;
- `native-design-baseline-confirmation-sheet`;
- `native-design-baseline-selection-digest`; and
- `confirm-native-design-baseline-button`.

## Verification

- capture-source focused tests: **4 passed, 0 failed**;
- exact final-source suite: **773 tests, 8 intentional environment skips, 0 failures** in **65.887 test seconds**;
- non-DEBUG Release build: **passed** in **102.58 seconds**;
- `git diff --check`: **passed**;
- residual exact `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture` process count: **0**;
- EasyBusiness remained read-only at `2ae40452e6d8661c46db466c43ea40bba3bfab04` with status digest `a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.

The first full suite after implementation executed all 773 tests but exposed a pre-existing startup-probe PID reuse race and counts zero. The probe now uses a zsh-owned `TRAPCHLD` plus child-free `zselect` delay, eliminating helper-child PID reuse between spawn and cleanup. Three focused probe runs passed before the accepted full suite. Compilation diagnostics and the lost-output test run also count zero.

Current source identities:

- capture-source loader: `62d836a1bdb5d06433084c9d5ac0ba8ba94414519170bd9d15655a7a03eda0d9`;
- native contract authoring: `668ab811f0e3099f3a4dd74a4d62852e8e83a7af5c185f95a7f47e35b3e92312`;
- app model: `b36597ec0efae7456bf117449566153defa96665b7559760ed4a1770ec6b6cae`;
- native views: `5902a9fa2a08bd39bd0bb23de4ee1460bcdc2d62c928676723333c8639dda442`;
- capture-source tests: `a10e7da80f9c8804f45b1dffd5f6f3dcbf64470934d5b809f6bb329a39b74730`;
- startup probe: `0d35dff1903dea503d0052148417f7eede99446f9298f88cd7bb4a83630ba37c`;
- exact current dirty source snapshot: `050c7f0e3882247ed8ddc14386ec0367fbe4852e3ec49b449eca81aedac7b5c4`.

## Remaining vetoes

Live deterministic typography/shape/spacing measurement authority is now
present as a follow-on. The complete visual-candidate matrix assembler,
independently activated visual reviewer issuer, trusted Release containment
issuer (or retained pre-apply veto), executable external-dependency observer,
final authorization, legacy controller cutover, current unlocked native
screenshot walkthrough, current-source signed package, clean commit, and push
remain required. The previously signed 769-test package predates this source
snapshot and is historical rather than current. Final acceptance remains false.
