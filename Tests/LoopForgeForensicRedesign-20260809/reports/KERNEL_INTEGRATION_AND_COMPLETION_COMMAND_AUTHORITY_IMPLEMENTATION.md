# Kernel Integration and Completion Command Authority

Status: **direct integration/completion injection closed; production proposal, verification, acceptance, and final issuers remain vetoed**

Recorded: `2026-08-11T19:26:20Z`

## Finding

`IntegrationTransactionReducer` has strong ordering and identity checks, but
the outer `RunCommand.advanceIntegration` accepted the entire `Codable`
`IntegrationTransitionCommand` directly. A caller could therefore construct
both command actors and the proposal, preflight, apply, postimage-verification,
independent-acceptance, or rollback receipts whose values were compared. The
state machine proved consistent structure, not necessarily the provenance of
the filesystem executor, verifier, or reviewer.

`authorizeCompletion` was an unparameterized command. Once requirement,
duration, and quiescence projections appeared satisfied, any caller at the
current sequence could emit `completionAuthorized`; there was no distinct final
authorizer capability or binding to the exact source frame.

## Implemented integration boundary

`RunCommand.advanceIntegration` now requires the non-`Codable`
`AuthorizedKernelIntegrationTransition`. Its initializer and production
factory are file-private to `JournaledWorkspaceMutationRuntime.swift`.

The existing real workspace effect path remains functional:

- `startApply` and `requestRollback` are minted only after the runtime validates
  the exact live journal/supervisor lease and request identity;
- `recordApply` and `recordRollback` are minted only from the bounded filesystem
  executor result inside the same actor;
- external source files cannot construct the wrapper;
- DEBUG tests retain a test-only factory for the complete transition matrix.

There is intentionally no Release issuer yet for proposal, preflight,
postimage verification, or independent acceptance. Those stages fail closed
until their dedicated provenance-bearing coordinators exist. Durable command
payload and transition-event schemas remain replayable and unchanged.

## Implemented completion boundary

`authorizeCompletion` now requires `AuthorizedKernelCompletion`, a
non-serializable capability bound to the exact run ID, source sequence, and
authorizer actor. The reducer validates all three before rechecking mandatory
requirements, accepted duration, quiescence, and absence of an active attempt.
Only a DEBUG test factory exists. No Release final-authorizer issuer exists, so
a forged or decoded collection of passing receipts cannot mark a run completed.

## Verification

- integration/reducer/filesystem focused suite: **58 passed, 0 failed**;
- complete source suite: **684 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  executable count: **0**;
- EasyBusiness remained stopped and was observed read-only.

Source identities:

- `RunReducer.swift`: `1163c200b7b6b24953723109d6ba0e2b85ef216d7ddeb64767b340ca454c8ae8`;
- `JournaledWorkspaceMutationRuntime.swift`: `2a11dc8fcf6a031d60359ef9faf3604a94cfa63e6f2c313ffb8dcf71ae2c21d2`;
- `IntegrationTransactionStateMachine.swift`: `53dff2b0c35bf3079ea8de1f5c38adbccf97b1d4c5115426555f57a55242157f`;
- reducer tests: `c232c60606063a8f805cfa929f00b42e9b9f7fabe7547b8309559570ba236140`;
- integration tests: `03937116dc2432d5a23ceb43f7e2e9d3a6c65bf372cc00e224a78abc40303692`;
- filesystem tests: `c398d92e06d7b155c70dc6a43a92b5f7de0f953e544b484804ef0d7aaba9e2de`.

## Remaining vetoes

Production integration proposal/preflight, postimage verifier, independent
acceptance, and final-completion issuers remain absent. Native start,
verification/reviewer/visual composition, external-dependency/drain/quiescence authority,
legacy Single/Parallel retirement, current-source package, unlocked native
proof, clean commit, and push also remain pending. Final acceptance is false.
