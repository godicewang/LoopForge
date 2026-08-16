# Journaled Native Visual Evaluation Authority

Status: **live native capture, measurement, and independent-review authority now composes into one exact hash-journaled kernel visual evaluation**

Recorded: `2026-08-14T16:08:22Z`

## Closed authority gap

`JournaledNativeVisualEvaluationCoordinator` is now the production compositor between the live native visual-review capability and `RunReducer`. It accepts no image paths, harness, receipt ID, requirement set, aggregate verdict, actor time, workspace mutation request, or publication authority from its caller. Its only evidence inputs are one exact non-serializable `JournaledKernelExecutionProof` and one exact non-Codable `AuthorizedNativeIndependentVisualReview`.

Before issuance it resolves the exact active run and completed attempt from the journal, verifies the retained attempt-start frame, frozen baseline, contract, node, strategy, worker, worker execution profile, ratified reviewer profile, candidate source/build/capture protocol, complete capture and measurement attestation sets, review receipt, and evidence ordering. Worker, independent reviewer, deterministic evaluator, and product-design authority must have four distinct lineages. The evaluator role is exactly `deterministicVisualGate`; model prose cannot grant it.

The coordinator recomputes the deterministic visual-evidence digest, hashes a canonical issuance envelope, derives both the command ID and visual receipt ID, and uses a file-private issuer marker to mint the only production `AuthorizedKernelVisualEvaluation` factory input. `RunJournal.recordNativeVisualEvaluation` accepts that non-Codable capability, appends the reducer result atomically, verifies exact duplicate delivery field-for-field, and rejects a conflicting reuse. The coordinator then re-reads the exact durable journal event before returning its projection. A red independent verdict is therefore a successful durable red journal fact that rejects the candidate; it is never discarded or converted into approval.

`VisualGateEvaluationReceipt` now retains the native review-request digest, complete native capture and measurement attestation digests, and native review completion time. These fields are optional only so older journals and DEBUG fixtures remain replayable. Production authority supplies all four fields together; the reducer rejects missing, partial, malformed, wrong-cardinality, or temporally cross-wired native provenance.

## Adversarial proof

The new coordinator tests exercise the real live native capture → measurement → independent-review adapters and then a hash-journaled reducer run:

- a green live review produces one exact durable visual receipt, survives journal reopen, and resolves exact retry as a duplicate without a second evaluation;
- a cross-wired attempt-start frame changes no journal head and produces no visual evaluation;
- a substituted worker execution profile produces no visual evaluation;
- a complete independent veto is accepted as evidence but journals a red gate result with `independentProductDesignVerdict` failing.

The focused class passed **9 tests with 0 failures**. The exact source suite passed **787 tests, 8 intentional environment skips, and 0 failures** in **63.291 test seconds**. The non-DEBUG Release build passed in **101.82 build seconds** (`102.73` wall seconds). The first focused compilation with `await` inside XCTest autoclosures failed and counts zero. The earlier focused invocation whose output was lost during continuation recovery also counts zero.

`git diff --check` passed and the residual exact LoopForge, sandbox-gate, fixture, Swift build, and XCTest process count was zero. EasyBusiness remained read-only at `2ae40452e6d8661c46db466c43ea40bba3bfab04` with unchanged status digest `a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.

## Exact source identity

- current exact dirty-source snapshot: `62d41213bbc5530aaeee6825ef2a2d49aed9f0103c9cc2d69993a16824bed8fd`;
- `JournaledNativeVisualEvaluationCoordinator.swift`: `8a02782ae7e068e0ab1962c4f3840cfc13f812bfc2684aa9a51516b19476ec75`;
- `RunJournal.swift`: `3aa34af91db1f44bf4dc5e716552c01431b63cdace7c0594a73a5ac9122098bd`;
- `RunReducer.swift`: `6ea11bd1b5cb1dabca91786c7fd33168077ff793351218aab7acf76080af91a3`;
- `DesignBaselineGate.swift`: `e5c9ca44b996944fc9c695ba86ab70e180be34f9490ba05683b29f7c54e24891`;
- `NativeIndependentVisualReviewAdapter.swift`: `54449a9597179842b037e0ce46845581ff9631e6b1e0a0ca286bd653224a893d`;
- `NativeIndependentVisualReviewAdapterTests.swift`: `0bbccd1db8f6a7b0562e73219252dc91993fa0f20625bf3779bf37ff320f20f9`.

## Boundary and remaining vetoes

This closes the source-level visual compositor/issuer gap. It does not invoke the coordinator from the native production controller, create trusted resident-memory containment on ordinary macOS, observe external dependencies, authorize final completion, retire legacy Single/Parallel execution, package/sign/hash the current snapshot, capture current-source native screenshots, or create a clean commit/push receipt. Publication remains structurally unavailable and final acceptance remains false. EasyBusiness remained permanently stopped and read-only.
