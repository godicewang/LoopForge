# Journaled Kernel Final Completion Authority

Status: **source implementation, exact-journal regression, and current dirty-source package receipts present; production-controller invocation, external-observer execution, containment decision, cutover, unlocked native proof, clean-commit rebuild, commit, and push remain pending**

Recorded: `2026-08-14T16:46:06Z`

## Result

Final completion is no longer a caller-shaped `runID + sequence + actor` capability in production. `JournaledKernelCompletionCoordinator` now resolves the exact reducer state, hash-journal frame digest, and latest accepted event time; deterministically compiles the complete evidence set; and is the only production owner of the file-private issuer marker needed to construct `AuthorizedKernelCompletion`.

The coordinator executes no model and trusts no completion prose. Its deterministic authorizer has a code-derived lineage distinct from worker, independent-reviewer, external-observer, visual-evaluator, design-authority, integration-executor, and integration-reviewer lineages. The reducer independently recomputes the same evidence digest before accepting the receipt.

## Mandatory vetoes

Authorization fails without advancing the journal when any of these conditions is true:

- the run is not already in reducer-owned `completionRequested` state;
- the exact source sequence, SHA-256 frame digest, or latest journal event time is stale;
- an attempt, live runtime resource, or failed release remains;
- a mandatory requirement or ratified duration floor is incomplete;
- a ratified quiescence receipt is absent, or any executed runtime lacks terminal quiescence;
- a declared external dependency lacks exclusively available evidence from an authorized observer for the exact attempt and recipe;
- a protected visual requirement lacks the latest native green capture, measurement, and independent-review authority;
- an integration is unfinished or quarantined;
- a mutation-backed requirement lacks independently accepted integration; or
- the final-authorizer lineage is not the deterministic independent kernel issuer.

This changes the old aggregate-completion shape into a conjunction of exact typed evidence. A green test count, elapsed time, reviewer prose, or stale receipt cannot compensate for one red gate.

## Durable transaction and replay

One accepted command atomically records two ordered events in one hash-chained journal frame:

1. `completionAuthorizationRecorded(receipt)` retains the exact source head, accepted requirements, complete pre-authorization receipt-ID set, evidence digest, authorizer, and authorization time.
2. `completionAuthorized` changes the phase to `completed`.

Replay validates the first event against the exact preceding reducer state before the terminal transition. Tampered evidence leaves the state unchanged. A retry after recovery returns the exact retained two-event transaction; a reused command ID with different authority fields fails closed. Legacy completed states without the new receipt are not promoted by the production coordinator.

`KernelRunProjection` exposes the durable completion-authorization receipt ID, so native/controller/report layers can distinguish authorized completion from legacy terminal prose.

## Verification

- `JournaledKernelCompletionCoordinatorTests`: 5/5 passed. Coverage includes exact authorization, recovery, exact retry idempotency, executed-runtime terminal-quiescence veto, missing external-dependency evidence veto, missing preservation-required frozen-baseline veto, and tampered replay rejection.
- Exact current full source suite: **794 executed, 8 intentional environment skips, 0 failures**, 56.074 seconds.
- Package-owned full suite: **794 executed, 8 intentional environment skips, 0 failures**, 60.582 seconds.
- Non-DEBUG arm64 Release build: **passed**, 102.12 seconds.
- Exact current source snapshot: `ad26dc732c706074efa5ef1f17eec65431a5d4a448e6fce2d30b741b1bb162db`.
- Packaged `LoopForge` SHA-256: `19575d089f3c62435e1281cd576279c1db75d2d6423910cc630bf08857365a98`.
- Packaged `KernelSandboxGate` SHA-256: `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`.

## Boundary

This closes the source-level final-authorization issuer and replay gap. It does not claim final release. The production controller does not yet invoke this coordinator, and the typed external-dependency contract still has no executable production observer. Mutation-backed execution still requires a trusted Release containment issuer or the retained pre-apply veto. Legacy Single/Parallel execution remains unretired. Current dirty-source package/sign/hash/smoke passed; unlocked native screenshots, clean-commit rebuild, commit, and push remain required.

EasyBusiness was not used as an execution target and was not modified by this work.
