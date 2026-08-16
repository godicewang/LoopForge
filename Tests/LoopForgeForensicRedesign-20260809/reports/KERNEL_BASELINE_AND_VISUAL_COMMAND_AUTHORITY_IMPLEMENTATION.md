# Kernel Baseline and Visual Command Authority

Status: **baseline and visual receipt injection closed; native design issuer now composed; complete visual issuer remains vetoed**

Recorded: `2026-08-11T19:04:27Z`

Updated: `2026-08-14T14:14:57Z`

## Native design-authority update

The native design half described as missing below is now implemented. A
non-Codable confirmation draft binds one exact user-ratified contract,
enrollment frame, preservation-required protected artifact, canonical capture
selection digest, and user lineage. An explicit main-actor user action mints a
single-use `AuthorizedKernelDesignBaseline`, and Release preparation consumes
that capability using the product-design actor. Raw durable baseline data and
DEBUG-shaped unbound evidence reject before journal advance. See
`NATIVE_DESIGN_BASELINE_CONFIRMATION_AUTHORITY_IMPLEMENTATION.md` and its
machine-readable scorecard for the current proof. Native capture-source
selection/population UI and complete visual-candidate authority remain absent.

## Finding

Two supposedly immutable visual gates still admitted caller-constructed durable
data:

1. `freezeDesignBaseline` accepted a `Codable` `DesignBaselineBundle` and only
   compared its embedded authority actor with the caller-supplied command actor.
2. `evaluateVisualCandidate` accepted a `Codable` `VisualCandidateBundle`
   containing capture receipts, measurements, batches, amendments, and an
   independent visual-review receipt. The reducer checked internal consistency,
   but not whether one trusted runtime had actually assembled those facts.

`NativeVisualCaptureAdapter` independently validates one allow-listed capture,
but returns a serializable `AttestedNativeCapture`. No production composition
currently binds a complete capture matrix, exact deterministic measurements,
and a separately activated reviewer result into an unforgeable visual command.
Consequently, both baseline and green visual verdicts could previously be
self-consistent shapes rather than provenance-backed authority.

## Implemented fail-closed boundary

- `freezeDesignBaseline` now requires `AuthorizedKernelDesignBaseline`.
- `evaluateVisualCandidate` now requires
  `AuthorizedKernelVisualEvaluation`, which seals the receipt ID, attempt,
  requirement set, and candidate together.
- Both wrappers are non-`Codable`, have file-private initializers, and expose
  only DEBUG test factories.
- Durable baseline, candidate, evaluation-receipt, and journal-event schemas
  remain unchanged for exact replay.
- The preparation coordinator now accepts a non-nil baseline in Release only
  through the native confirmation issuer's exact run/ratification/enrollment-
  frame capability. Baseline-free preparation remains available.
- Release has no visual-evaluation issuer, so a decoded/model candidate cannot
  create a new visual verdict.

This closes command authority and now implements the protected-artifact-bound
baseline issuer. The next production boundary must bind native capture attestations,
deterministic measurement receipts, independent reviewer activation/output,
and the exact journal attempt to visual-evaluation authority.

## Verification

- baseline/capture/visual-journal/composition focused suite: **34 passed, 0 failed**;
- complete source suite: **684 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  executable count: **0**;
- EasyBusiness remained stopped and was observed read-only.

Source identities:

- `RunReducer.swift`: `de04268f5fb0676908296193546d6bac9605c3900babda90c9c55a77672e76e1`;
- `KernelExecutionPreparationCoordinator.swift`: `7342f9f33d8da0aa7e8ef97c60d95c2dd5ebe1869b8f86daa40be217ac97626c`;
- `NativeVisualCaptureAdapter.swift`: `64a967513cec2b3d63079fb4660fb215683cd6b3439b34a12857677d019a307e`;
- `DesignBaselineGate.swift`: `34cc44ce9401b383dc45d1fb7b2eae53f15cc85106d1c9e59240dfbd2531cb87`;
- visual journal tests: `56968a1c5642ae45ec3bb13d5e4c0b2798ef1c9c9377f93ec1173f77f35f8228`;
- native capture tests: `ba00a152a921fb0b69cabd024ae692cbdbcc3f61dfe25f8c63cc9f5b871f22e8`.

## Remaining vetoes

Native capture-source selection/population, native visual matrix assembly,
deterministic measurement issuance, independently activated visual reviewer issuance,
integration acceptance authority, completion authority, native start, legacy
Single/Parallel retirement, current package, unlocked native proof, clean
commit, and push remain absent. Final acceptance remains false.
