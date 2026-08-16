# Kernel Native Strategy and Plan Authority

Status: **typed causal strategy, mechanical falsifiers, and requirement-owned plan are displayed, explicitly confirmed, retained, and enforced; no native start capability exists**

Recorded: `2026-08-11T21:50:33Z`

## Authority result

Native Auto Graph authoring now proposes one complete causal strategy and one
bounded execution plan against the exact content-complete source revision. The
proposal has no authority by itself. The confirmation sheet displays every
prediction, falsifier, requirement owner, dependency, write scope, capability,
and file/byte ceiling. Authority exists only after the user confirms the whole
candidate whose canonical digest includes those exact artifacts.

The retained strategy binds:

- every mandatory requirement and accepted evidence recipe;
- one expected observation per recipe;
- one mechanical `requiredEvidenceMissing` falsification predicate per recipe;
- the exact confirmed source revision and causal axes;
- the confirmed plan's effective mutation-surface digest; and
- the finite convergence policy already retained in the contract.

The retained plan binds every mandatory requirement to exactly one node,
retains the dependency graph, restricts scopes and capabilities to the
confirmed ceiling, rejects protected-baseline overlap, rejects cycles, and
keeps aggregate file and byte limits inside the confirmed mutation budget.

## Compiler and confirmation boundary

`TaskContractCompiler` requires separate full-span explicit-user source
bindings whose canonical bytes exactly equal the retained strategy and plan.
Model proposal bytes, objective prose, repository content, or a source scan
cannot satisfy those bindings. Confirmation rechecks that the displayed
strategy and plan still equal the candidate before issuing its single-use
whole-candidate receipt.

The strategy fingerprint deliberately identifies causal dimensions rather
than display text or prediction IDs. Separate canonical authority bindings
retain the complete prediction, falsifier, and plan payloads, so stable
convergence identity does not discard user-confirmed detail.

## Preparation enforcement

`KernelExecutionPreparationCoordinator` now reopens the journaled contract and
requires the preparation request to equal its retained:

- execution plan;
- causal strategy descriptor;
- prediction and falsifier identifier sets;
- rollback/source revision; and
- convergence budget.

A caller cannot keep the same registration while substituting a broader plan,
different causal strategy, stale rollback point, or expanded convergence
budget. Rejection occurs before any journal append.

The read-only readiness assessment consequently reports zero missing authority
blockers for a newly confirmed native enrollment. This means the retained
contract is sufficient for the existing separate production preparation
boundary; it does **not** launch a worker. The native application still exposes
no start action and creates no process, attempt, integration, publication, or
legacy controller effect.

## Verification

- strategy/plan authoring, enrollment, and exact-preparation suite: **27
  passed, 0 failed**;
- compiler, reducer, and convergence regression suite: **75 passed, 0
  failed**;
- complete source suite: **695 tests, 8 skipped, 0 failures**;
- non-DEBUG arm64 Release build: **passed**;
- `git diff --check`: **passed**;
- release-source snapshot SHA-256:
  `4bf83237fce3658fece4df0687781f85f62e8222c43cc316c018879dade8bc47`;
- read-only EasyBusiness status: **unchanged**.

The first focused run exposed only an obsolete fixture expectation (six source
artifacts before the two new explicit bindings); it is excluded from the
strict active-work ledger. Test/build execution, polling, and waits are also
excluded.

## Remaining vetoes

The next boundary is not more planning authority. It is trusted execution
composition: deterministic verification-oracle issuance, separately activated
independent review, native immutable design-baseline selection, complete visual
evidence, transactional integration acceptance, final authorization, and
executable external-dependency observation. Native start must remain absent
until those required issuers and cleanup paths are composed. Legacy Single Loop
and Parallel Candidates are not cut over. Current package/sign/hash, unlocked
native screenshots, clean commit, and push remain incomplete. EasyBusiness
remains permanently stopped and read-only.
