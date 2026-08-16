# Strategy Churn and Review Causal Model

Status: confirmed forensic finding and audit of the current dirty repair. This is not a completion claim.  
Evidence source: stopped task snapshot and the flattened 5,758-event corpus.  
EasyBusiness handling: read-only.

## Quantified control history

The stopped Graph contains 51 durable node iterations:

| Decision/outcome | Count |
|---|---:|
| Main `approved` decisions | 12 |
| Main `continueWork` decisions | 32 |
| Main `superseded` decisions | 5 |
| Still `pending` at stop | 2 |
| Worker summaries explicitly marked `LOOPFORGE_STATUS: BLOCKED` | 37 |
| `BLOCKED` worker summaries nevertheless assigned `continueWork` | 28 |
| `BLOCKED` worker summaries approved in the same iteration | 7 |
| Exact adjacent instruction repeats | 2 |

Thus 72.5% of all worker turns explicitly declared that the requested outcome was blocked. Only two adjacent instruction pairs were byte-identical. The dominant failure is therefore **causal repetition hidden by rewritten prose**, not literal prompt replay.

Eight completed nodes contain at least one blocked iteration. Seven were approved on a final iteration that was itself marked blocked. `inventory-prior-us-evidence` is the eighth: its approved turn was not blocked, but five earlier blocked turns were continued.

## Four distinct non-convergence mechanisms

### C-1 — Immutable write scope was treated as mutable prose

`implement-bailian-json-contract` ran 11 iterations. Iteration 1 completed the core implementation but exposed a real `/readyz` gap. Iterations 2–9 all returned blocked because `backend/app/main.py` and `backend/tests/test_api_health.py` were outside the node's declared write scope.

The Main reviewer repeatedly wrote variants of “add these files in the next frontier,” but the control plane did not change the node's actual scope. The worker correctly refused to cross the boundary each time. Iteration 8 additionally suffered a reviewer-format/provider fallback and was told to rerun verification, despite the blocker already being proven. Only iteration 10 finally carried a real `MAIN GRAPH SCOPE RECOVERY` control change.

This was not a worker reasoning failure. It was a topology mutation requested through a channel that could only change text. Eight repeated blocked cycles were caused by the coordinator failing to distinguish instruction state from execution-boundary state.

### C-2 — Missing historical bytes were pursued as if persistence could be persuaded

`retain-ios-baseline-screenshots` ran seven iterations. The missing tenth and eleventh historical PNG objects had no readable retained source. Main continued asking for byte-identical recovery while changing the proposed search path and wording. Iterations 5 and 6 used the exact same instruction. The node was retired only in iteration 7, after repeatedly scanning or probing sessions, mounts, and artifact paths.

The node accumulated 12,297.89 stored blocked seconds, but that value includes long wall-clock gaps and is not accepted active work. The important convergence evidence is structural: five blocked summaries, six `continueWork` decisions, 529 command events, 24 errors, and no change in the authoritative availability of the two bytestrings.

### C-3 — An isolated worktree was told to become a different cwd

`repair-1` ran four iterations. The later instructions told the same worker to operate on the canonical `/Users/godice/Coding/EasyBusiness` worktree, but the node remained materialized inside its immutable isolated Graph worktree. Three turns explicitly reported the same cwd/boundary failure. Updating prose could not change process cwd or workspace ownership.

The node was eventually abandoned as an external execution boundary. The correct control action should have happened after the first proof that the requested topology was impossible, before another worker turn.

### C-4 — A green test measured after the failure interval

The XCUITest evidence path reported success although the synchronous `tap()` itself blocked for about 980.887 seconds. The assertion timer began only after `tap()` returned, so the test could pass while hiding the entire user-visible delay. Main and later evidence artifacts reused the green exit status as responsiveness proof.

This is a measurement-boundary defect. More repetitions of the same test cannot improve confidence. The eventual replacement—an external process watchdog—was materially different because it started timing before the input action and could capture the blocked interval independently of XCTest quiescence.

## Why the Main review reinforced the worker

The current/historical review chain lacks typed separation between:

1. transport completion;
2. worker execution outcome;
3. reviewer evidence judgment;
4. graph topology action;
5. product-quality acceptance.

A zero Codex process exit delivered a parseable narrative. The narrative could say `BLOCKED`, yet still be reviewed as ordinary work and receive another prose instruction. A later `approved` Boolean then erased the contradiction. For visual work, the evidence collector's deterministic inspection only checks that an image decodes, is at least 400×300, is non-blank by luminance variance, and yields OCR. It does not compare against a before-state or measure typography, density, hierarchy, shape, spacing, or occlusion.

The same control model therefore produces both observed failures:

- operational dead loops continue because the causal blocker is untyped;
- visually bad work passes because image integrity is mistaken for design quality.

## Audit of the current dirty LoopForge repair

The uncommitted source already contains several valuable changes:

- `requiredWriteScopes` in the node review envelope;
- exact-path scope recovery in the control plane;
- a three-consecutive-blocked-turn freeze;
- a six-unapproved-decision strategy budget;
- first-occurrence interception of requests that require a canonical-workspace transition;
- fresh-thread replacement plans;
- durable `supersededAt`, strategy decision, and strategy lesson fields;
- structural abandon/reframe/split/replace review.

These changes address real historical failures, but the current implementation still cannot be accepted:

1. `LOOPFORGE_STATUS: BLOCKED` remains a free-form substring rather than a typed worker outcome.
2. `GraphWorkerRuntimePolicy.reviewAdjustment` adds blocked runtime back when Main approves it. The current unit test explicitly expects `BLOCKED + approved = +117 seconds`.
3. Per-iteration `activeSeconds` stores the full eligible runtime before review, even when the turn is rejected or blocked.
4. `GraphLoopNode.liveActiveSeconds` deliberately sums approved, rejected, blocked, superseded, and pending iteration durations into the displayed total.
5. Strategy equivalence uses punctuation-stripped exact strings. Semantically identical objectives with different wording pass `isMateriallyDifferent`.
6. The total strategy budget counts decisions, not repeated causal fingerprints, elapsed cost, command churn, or unchanged authoritative evidence.
7. Reviewer/provider failure falls back to “run verification,” which can relaunch a worker even though the worker result was not the failure.
8. Scope recovery checks every non-superseded writer as a peer, including completed writers whose isolated work is already integrated and cleaned. This can reject legitimate sequential ownership transfer.
9. Visual inspection remains decode/dimensions/variance/OCR integrity only. There is no immutable UI baseline, visual delta, typography scale contract, density budget, or adversarial design verdict.
10. Node review and whole-graph review consume worker-authored tests, screenshots, documentation, and conclusions without a genuinely separate baseline owner.

## Required convergence state machine

The redesign must make these states explicit and durable.

### Worker result

```text
executionOutcome:
  completed | continuationNeeded | blocked | failed | interrupted | malformed

blocker:
  kind | affectedOperation | immutableConstraint | exactResources |
  evidenceDigest | retryCondition | externallyRecoverable
```

### Independent review

```text
reviewOutcome:
  approved | rejected | externalBoundaryAccepted | topologyChangeRequired |
  strategyRetirementRequired | evidenceUnavailable
```

`blocked + approved` must be invalid. The only valid resolution for a blocked worker is an accepted external boundary, a concrete topology/resource change, or strategy retirement.

### Causal retry budgets

- Immutable workspace/cwd mismatch: structural replan after the first confirmed occurrence.
- Missing write scope: apply one safe coordinator scope change; if it is rejected or conflicts, retire/replan without relaunching the worker.
- Same blocker fingerprint: at most three total occurrences, including the first; the third forces retirement.
- Same authoritative evidence digest: a differently worded prompt does not reset the budget.
- Reviewer transport/format failure: retry the reviewer, never the worker.
- Six total unapproved decisions remains an absolute ceiling, not the primary detector.
- High-cost turns and high command/error churn lower the remaining budget rather than receiving six equally expensive attempts.

### Materially different replacement

A replacement must change at least one typed contract dimension—responsibility, resource source, measurement boundary, workspace topology, or verification oracle—and must explicitly retire the failed assumption. A new ID, fresh thread, or paraphrased objective alone is not different.

## Acceptance consequences

LoopForge must not report convergence until all are true:

- no active or pending node retains an exhausted causal fingerprint;
- no invalid `blocked + approved` record exists without a visible migration warning;
- accepted active time excludes blocked, rejected, failed, interrupted, and idle intervals;
- replacements prove a contract-level difference from retired strategies;
- visual work includes immutable before/after evidence and independent design gates;
- the UI displays accepted total, current eligible live time, and excluded time separately.

The machine-readable companion is `STRATEGY_CHURN_SCORECARD.json`.
