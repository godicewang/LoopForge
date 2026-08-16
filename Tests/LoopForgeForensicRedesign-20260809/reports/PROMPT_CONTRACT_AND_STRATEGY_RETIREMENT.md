# Prompt Contract and Strategy-Retirement Forensic Audit

Status: historical failure confirmed; current dirty repair is directionally useful but not convergent. EasyBusiness remained read-only.

## Verdict

The stopped Graph did not fail because the agents were too weak or because seven turns were intrinsically insufficient. It failed because LoopForge represented work as prose objectives plus self-authored verification, then treated each new continuation instruction as another attempt rather than asking whether the causal strategy had already failed. The protocol had no immutable design baseline, risk class, mutation budget, hypothesis identifier, failed-predicate fingerprint, or typed requirement ownership.

The current uncommitted LoopForge repair adds a sixth-rejection retirement trigger and fresh replacement nodes. That prevents one exact historical replay, but its anti-repeat predicate is only normalized string equality. A semantic paraphrase, a different verification sentence, or a new node title is considered materially different even when it uses the same tools, evidence source, mutation surface, and acceptance predicate. It is not yet a convergence mechanism.

## Historical task evidence

The stopped task contains 51 durable iteration records:

- 37 worker summaries explicitly contain `LOOPFORGE_STATUS: BLOCKED`;
- all 37 blocked summaries have process exit code 0;
- Main marked 7 of those blocked turns `approved`, 28 `continueWork`, and only 2 `superseded`;
- `implement-bailian-json-contract` ran 11 iterations, all 11 reported BLOCKED, and the node ended `completed`;
- `retain-ios-baseline-screenshots` ran 7 iterations before retirement;
- `inventory-prior-us-evidence` ran 6 iterations, five BLOCKED, before approval.

This is not merely misleading accounting. It changes planning behavior: exit-code-zero blocked turns remain eligible for the same thread, the reviewer can translate a boundary narrative into approval, and additional prose becomes evidence that the loop is progressing.

## What the historical prompt contract omitted

### Plan proposals were not executable safety contracts

`GraphPlanNodeProposal` contained only ID, title, objective, dependencies, write scopes, verification text, read-only status, and join group. It had no fields for:

- original requirement IDs owned by the node;
- immutable source/design baseline receipt;
- risk class or reversibility;
- maximum files, lines, semantic surfaces, or visual regions allowed to change;
- explicit non-goals and must-preserve invariants;
- pre-mutation hypothesis and predicted observable delta;
- strategy ID or causal failure fingerprint;
- independent acceptance authority;
- rollback point or publication prohibition.

For the U.S. adaptation, the original goal legitimately asked for broad localization. LoopForge therefore had an even stronger duty to freeze the accepted Chinese product hierarchy before authorizing UI mutation. Instead, the planner passed a broad product goal into a node contract that could preserve every English glyph while discarding the product's initial-screen hierarchy.

### The worker was instructed to close its own contract

The node prompt says to inspect, implement, run verification, and “repair failures,” then return an evidence summary. The same worker can change product code, add tests, generate screenshots, write audit documents, and frame its completion claim. No prompt section provides a commit-bound before image, baseline digest, allowed visual delta, or a reviewer-owned test that the worker cannot rewrite.

That structure rewards a self-sealing local optimum: redefine the implementation until the node's own verification is green. `f82ff2d` is the concrete result—272 lines of geometry-focused UI tests passed while the initial dashboard hierarchy became worse.

### Review began with the implementer's narrative

The node review input orders `NODE RESULT` before deterministic findings and the retained evidence block. The reviewer therefore receives the worker's causal framing and self-selected successes before independently observing the product. There is no blind first pass, no prompt/input receipt, and no rule that self-authored tests are lower-authority than an immutable baseline.

### Rejection meant “continue this node”

The historical review envelope had only `approved`, summary, next instruction, verification, and an always-empty `addedNodes`. A rejection could not return `retire`, `abandon`, `split`, `replace`, or a typed external boundary. The engine's natural transition was therefore another instruction on the same node and thread. Free-form wording changed while cwd, tools, evidence source, and failed assumptions remained the same.

## The current dirty retirement repair is still bypassable

The uncommitted source introduces `GraphNodeStrategyEscalationPolicy.maximumUnapprovedDecisions = 6` and intercepts a pending seventh turn. This correctly addresses the user's observed seven-turn loop at the state-transition level. Four design weaknesses remain:

1. `isMateriallyDifferent` lowercases text, removes non-alphanumeric characters, and rejects only exact signature matches. “Recover two missing historical PNGs” and “Reconstruct both unavailable original screenshot files” are different according to this policy.
2. The comparison does not include tool route, evidence provenance, workspace/cwd, mutation surface, acceptance predicate, failure class, or strategy lesson.
3. The six-turn budget is global. A high-risk UI mutation may cause product damage on its first accepted turn, while a safe read-only investigation may rationally need more than six distinct hypotheses.
4. A final audit can still fall back to a write node with `writeScopes: ["."]`. That whole-workspace escape hatch defeats bounded mutation and can reintroduce the same broad redesign under a generic “close gaps” objective.

The repair also stores `coverageResolution` as one enum plus free-form text. Because no node owns typed original requirement IDs, abandoning a strategy as `satisfiedElsewhere` or `externalBoundary` cannot be mechanically checked against the full user goal.

## Required convergence architecture

### Typed plan contract

Every material node must persist:

- `requirementIDs` and explicit conjunctive acceptance clauses;
- `baselineReceiptIDs` for code, native screenshots, design tokens, locale, device, and content-size category;
- `riskClass`: read-only, reversible-local, product-behavior, visual-identity, data/destructive, or external-publication;
- `strategyID`, hypothesis, predicted observations, and falsification conditions;
- `mutationBudget`: maximum files, changed lines, declared semantic surfaces, visual regions, and prohibited paths;
- reviewer-owned gates and worker-authored evidence kept as separate authorities;
- rollback commit/ref and a publication policy.

### Causal attempt fingerprint

Each attempt must hash a structured fingerprint over:

- active requirement and failed predicate;
- baseline and candidate tree hashes;
- workspace/cwd identity;
- tool and evidence routes;
- mutation surface;
- verification authority and commands;
- failure outcome class;
- retained strategy lesson.

Similarity must be semantic and structural, not exact prose equality. A paraphrase with the same cwd, tool route, evidence source, and failed predicate is the same strategy.

### Risk-weighted retirement

- A new visual-identity or information-hierarchy regression causes an immediate veto and rollback; it does not consume five more retries.
- Three causally equivalent blocked/rejected attempts retire a safe strategy.
- Distinct read-only hypotheses may continue within an explicit evidence budget.
- Replacement nodes must change at least one causal axis and state why the new evidence can falsify the old lesson.
- No fallback repair receives `writeScopes: ["."]`; Main must enumerate exact paths or stop for a structural replan.

### Quarantined publication

Implementation commits stay on a task-owned candidate ref. Node approval, join review, baseline diff, and independent product/design review all occur before any canonical merge or remote push. A later veto must be able to discard the candidate without repairing public history.

## New defects recorded

- **F-047 — Node plans are prose, not baseline-bound safety contracts.** Requirement ownership, immutable baselines, risk, mutation budget, rollback, and publication policy are absent.
- **F-048 — UI risk is not elevated before mutation.** A product-hierarchy change can be accepted by the same generic node review used for a read-only audit.
- **F-049 — Historical iterations have no causal strategy identity.** New wording is treated as new progress even when the failed environment and route are unchanged.
- **F-050 — Worker-authored verification closes the worker's own objective.** Tests, screenshots, audit prose, and implementation can form a self-sealing acceptance bundle.
- **F-051 — The dirty anti-repeat comparator is lexical equality.** Semantic paraphrases bypass `isMateriallyDifferent`.
- **F-052 — Retirement budget is not risk- or damage-weighted.** Six universal unapproved decisions are unsafe for visual mutations and arbitrary for read-only investigation.
- **F-053 — Retirement coverage is not bound to typed original requirements.** `satisfiedElsewhere` and `externalBoundary` cannot be mechanically reconciled with the user goal.
- **F-054 — Whole-workspace fallback repair survives the convergence patch.** `writeScopes: ["."]` can recreate an unbounded redesign after a failed final audit.

## Redesign acceptance tests derived from this audit

1. A seventh pending historical cycle is never launched.
2. A paraphrased replacement with the same causal fingerprint is rejected.
3. A replacement that changes only title/objective wording but not tool/evidence/mutation route is rejected.
4. A red immutable visual-baseline gate rolls back and retires the current visual strategy after its first damaging result.
5. No generated repair node may own `.` or an unenumerated whole repository.
6. Abandonment cannot succeed until every owned requirement has a typed resolution and evidence receipt.
7. A rejected candidate cannot have changed the canonical branch or remote.

