# Kernel Native Execution Readiness Gate

Status: **compiler-validated evidence, budgets, source revision, causal strategy, falsifiers, and plan retained; read-only gate reports zero missing-authority blockers and no native start action exists**

Recorded: `2026-08-11T21:50:33Z`

## Reachability result

The enrolled native Auto Graph contract now retains enough exact authority for
the separate production preparation boundary: evidence recipes, finite
mutation and convergence ceilings, a content-complete source revision, a typed
causal strategy, mechanical falsification predicates, and a requirement-owned
execution plan. The read-only assessment therefore returns an empty blocker
set and `canPrepareAndActivate == true` for the exact confirmed enrollment.

Nothing is inferred from objective prose or the source scan. Strategy and plan
are LoopForge proposals until the confirmation sheet displays their complete
canonical payloads and the user confirms the whole candidate. The compiler
then retains separate exact explicit-user source bindings for both artifacts.

## Implemented boundary

`KernelProductionExecutionCoordinator.nativeExecutionReadiness(for:)` is a
read-only preflight over one exact retained enrollment. It requires:

- ratified-user-contract enrollment authority;
- exact equality with the durable registry registration;
- exact contract ID, journal ending sequence, and journal frame digest; and
- successful hash-journal recovery.

It returns a Codable `KernelNativeExecutionReadinessAssessment` whose empty
typed blocker set reflects only validated retained authority. It accepts no
plan, strategy, budget, recipe, timestamp, command ID, or verdict from the
caller and appends no journal frame. The native AppModel records the assessment
after enrollment, and the diagnostics sheet displays the exact result.

No start button was added. Confirmation creates no attempt or process. The
existing production execution coordinator can activate only a preparation that
exactly equals the retained plan, strategy, predictions, falsifiers, rollback
revision, and convergence budget.

## Ratified evidence-recipe retention

`TaskContractCompiler.ratify` now seals the exact compiler-validated
`RequirementEvidenceRecipe` array into the durable contract before enrollment.
The optional field preserves decoding for old journals, while newly ratified
contracts must exactly cover every declared recipe ID, bind each recipe to the
owning requirement, preserve verifier kind and independent-lineage policy, and
retain a nonempty expected observation.

Ratification now recomputes the complete candidate digest and recomputes the
blocking ambiguity/eligibility projection before issuing a receipt. A mutable
in-process caller can no longer compile one candidate, replace its recipe or
eligibility fields, and reuse the old displayed confirmation digest. The
native enrollment test proves the exact recipes survive journal replay, and
the readiness assessment mechanically removes only the recipe blocker.

## Ratified budget retention

The native candidate now includes canonical user-bound source bytes for exact
mutation and convergence ceilings. The confirmation sheet displays every
limit. Compiler replay rejects a missing binding or any expanded value whose
bytes no longer match the displayed source. The journal replay test proves the
policy survives enrollment, and readiness removes the two budget blockers only
when that durable policy validates. This does not create causal strategy, plan,
attempt, or start authority. Native authoring now captures the bounded
content-complete revision, displays its exact policy and digest, re-captures it
at confirmation, binds it through the user's whole-candidate receipt, and
retains it in the ratified contract and hash journal. The separately displayed
and confirmed strategy and plan now bind their causal and mutation decisions to
that exact revision.

## Strategy and plan retention

The strategy owns every mandatory requirement and evidence recipe, retains an
expected observation plus a `requiredEvidenceMissing` falsifier at the exact
source revision, and binds the confirmed plan's mutation surface. The plan has
exact mandatory-requirement ownership, a cycle-free dependency graph, bounded
scopes/capabilities, protected-baseline exclusion, and aggregate file/byte
ceilings. Preparation rejects any substituted plan, strategy, identifier set,
rollback revision, or convergence budget before journal mutation. The detailed
receipt is `KERNEL_NATIVE_STRATEGY_AND_PLAN_AUTHORITY_SCORECARD.json`.

## Durable identity defect found and repaired

The readiness gate exposed an intermittent production defect. Registry
snapshots encode `registeredAt` in whole milliseconds, while
`registrationCandidate` previously returned a nanosecond-precision in-memory
Date. A receipt could therefore differ from the immediately reloaded durable
registration even though every security-relevant field was unchanged.
`KernelProductionExecutionCoordinator.activate` correctly requires exact
registration equality, so valid native activation could fail nondeterministically.

`WorkspaceMutationRecoveryRegistry` now canonicalizes `registeredAt` to the
snapshot codec's millisecond boundary before it becomes registration identity.
The native enrollment test asserts exact equality after durable reload. This
fix narrows representation; it does not relax any registration comparison.

## External-dependency observer audit

No production observer was added. `ExternalDependencyContract` currently
freezes dependency kind, requirement ownership, one opaque
`evidenceRecipeID`, and allowed observer lineage digests. It does not define an
executable probe, probe inputs, output parser, or deterministic mapping from
observations to `available`/`unavailable`. Treating a provider exit status or
model prose as the verdict would recreate self-issued evidence. The reducer's
non-Codable command boundary therefore remains the correct fail-closed state.

## Verification

- strategy/plan authoring, enrollment, and preparation suite: **27 passed, 0 failed**;
- durable reload equals the returned registration: **passed**;
- read-only preflight leaves journal sequence and projection unchanged:
  **passed**;
- compiler/reducer/convergence regression suite: **75 passed, 0 failed**;
- complete source suite: **695 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**.

The earlier identity-defect failures, the obsolete pre-retention assertion, and
the first strategy-binding fixture count mismatch are excluded from the strict
ledger.

## Remaining vetoes

A native start action remains vetoed until deterministic verification,
independent review, native design-baseline selection, complete visual evidence,
transactional integration acceptance, final authorization, and complete
cleanup are composed. External dependency observation likewise needs a
ratified executable probe and independent result interpreter. Legacy
Single/Parallel retirement, current package/native proof, commit, and push
remain incomplete.

EasyBusiness remained stopped and read-only.
