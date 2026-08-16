# State-Machine, Replay, and Convergence Architecture Audit

Status: confirmed architectural root cause; refactor required  
Scope: current LoopForge source, dirty repair, test topology, and stopped task replay  
EasyBusiness handling: read-only evidence only

## Executive finding

LoopForge does not have one authoritative Graph state machine. It has a 6,539-line `@MainActor` orchestration file in which task state, graph phase, node status, iteration decision, retry state, integration state, time accounting, approval, and UI stage text are mutated through dozens of independent closures. The recent fixes improve individual incidents, but they add more flags and branches to the same non-replayable model. This is why one defect can be patched while another loop or contradiction appears elsewhere.

The stopped EasyBusiness run is the concrete result: 19 nodes, 51 iterations, 77 Main Graph interactions, three whole-project repair rounds, five superseded strategies, two pending nodes, audit score 100, visual failure, and no approval. The engine retained a large amount of work yet never had a durable predicate that could prove it was moving closer to the immutable product goal.

## 1. Transition logic is distributed rather than reduced

`GraphLoopEngine.swift` currently contains:

- 6,539 lines;
- 39 task-level `store.update` call sites;
- 43 node-level `store.updateGraphNode` call sites;
- 69 direct `.status = ...` assignments;
- 23 direct `.phase = ...` assignments;
- 10 direct iteration `.decision = ...` assignments.

Those 82 mutation call sites do not pass typed domain events through a reducer. Each closure can set a subset of fields and rely on surrounding control flow to remember the rest. A pause, review result, runtime callback, integration result, recovery, incremental plan change, or final audit may therefore leave a combination that no single transition table has validated.

The engine itself is `@MainActor`. Awaiting a model or process correctly yields the actor, but callbacks and sibling execution can mutate the same store before the suspended orchestration resumes. The code frequently mitigates this by reloading a task manually; other paths keep a captured `task`, `graph`, or `node`. Correctness depends on local discipline rather than an optimistic revision check or reducer precondition.

## 2. The persistence schema makes invalid combinations representable

Four independently encoded enums already allow 3,888 raw tuples per node:

- 12 task statuses;
- 6 graph phases;
- 9 node statuses;
- 6 iteration decisions.

The effective state space is much larger because a node also persists optional and partially overlapping flags such as:

- `automaticRetryDisabled`;
- `strategyEscalationRequired`;
- `replacementPlanStartedFreshThread`;
- `replacementPlanContractVersion`;
- `supersededAt`, `supersededReason`, and `supersededByNodeIDs`;
- `planAdjustment`;
- `strategyLesson` and `strategyDecision`;
- `threadID`, `activeStartedAt`, and `blockedAt`.

Examples of contradictions are representable without a decoding error: waiting plus automatic retry disabled, completed plus strategy escalation required, superseded provenance with a non-superseded status, an approved iteration with a blocked worker summary, or a task in `running` while its graph is in `planning` and no node is runnable. Recovery code contains ad hoc migrations for several of these exact combinations, proving they are not hypothetical.

## 3. Current tests do not replay the real engine

`GraphLoopTests.swift` has 84 tests and 3,167 lines. They provide useful unit coverage for normalization, scheduling, scope checks, timing helpers, worktree integration, and the new strategy-retirement policies.

No test in `Tests/LoopForgeTests` instantiates `GraphLoopEngine`. There is therefore no deterministic end-to-end replay of:

- multiple node completions arriving around a review;
- pause or stop during node review, integration, and final audit;
- crash after approval but before integration/reporting;
- restart with queued node signals;
- repeated provider parse failures across relaunches;
- strategy retirement while another node finishes;
- approval reuse after repository or evidence changes;
- all possible terminal resource cleanup results.

Policy tests can all pass while the orchestration assembled from those policies remains non-convergent.

## 4. Some retry budgets reset when the app or engine restarts

`consecutiveBatchTransitionFailures` and `consecutiveFinalReviewFailures` are in-memory properties reset to zero at every `run`. The engine blocks after three failures *within one run*, but pause/resume or relaunch grants three new attempts. A persistent malformed or unavailable reviewer can therefore repeat forever across restarts while the UI reports bounded retries.

Incremental-review failures were later made durable on each node. Node strategy decisions and final repair count are also partly durable. The inconsistent persistence of budgets is itself the problem: “three retries” means different things depending on which review phase failed.

## 5. Strategy identity is lexical, not causal

The dirty repair correctly recognizes that a node must be retired after a bounded unapproved budget. Its `isMateriallyDifferent` gate does not measure strategy, evidence source, failed assumption, or verification method. It removes non-alphanumeric characters and rejects only exact normalized equality with historical text.

Trivial paraphrases therefore count as materially different:

- “recover two missing historical PNG byte objects”;
- “search for the unavailable screenshot bytes”;
- “reconstruct absent original image artifacts.”

All can express the same failed causal strategy yet produce different signatures. The model can escape retirement simply by rewording its objective. This is precisely the behavior the user objected to after seven attempts.

The stopped task proves the need for causal identity: the retired screenshot strategy repeatedly changed search wording and evidence probes while preserving the same invalid assumption that missing historical bytes could be recovered.

## 6. Legacy replay uses unsafe keyword inference

For old checkpoints without structured iteration history, `GraphIterationHistoryPolicy` reconstructs decisions from free-form log text. Its approval test is:

```text
normalized.contains("approved")
```

That classifies “not approved,” “unapproved,” or “cannot be approved” as `approved`. Similar keyword inference is used for blocked and recovery states. Persisted modern records override reconstructed records of the same number, but legacy history and partially migrated tasks can still be falsely green.

A forensic ledger must preserve uncertainty. It must never upgrade ambiguous prose into a terminal approval.

## 7. Approval is not bound to a revision or evidence set

Whole-graph approval may be reused when:

- `supervisorCompletionApproved == true`;
- the generic deterministic audit passes;
- `mainLastReview` is non-empty.

There is no stored approval receipt containing workspace tree hash, dirty diff hash, requirement-contract version, visual-baseline IDs, evidence hashes, reviewer identity, or review input hash. The comment says approval is reused because “the graph and every objective evidence gate are unchanged,” but the code does not prove unchanged state.

`discardRedundantPendingRepairIfAlreadyApproved` can then delete unfinished repair nodes and decrement the final-repair count on the strength of the same unbound approval flag plus the generic audit.

## 8. “Audited and integrated” has no integration receipt

The scheduling gate considers a node audited and integrated when:

- status is `completed`;
- `completedAt` is non-null;
- `lastReview` is non-empty.

It does not require an integration receipt, canonical tree hash, applied patch hash, commit identity, changed-path manifest, verification receipt, or reviewer input/output ID. Those three mutable presentation fields unlock dependencies and final audit.

Worktree-specific recovery contains stronger patch/marker checks, but that evidence is not part of the universal completion predicate. The graph core therefore cannot independently prove that “completed” means the approved bytes are in the canonical workspace.

## 9. Whole-project repair still permits bounded-looking churn

If final review rejects the product, the engine permits up to eight final-repair rounds and 32 total nodes. When a reviewer emits no safe plan, the conservative fallback creates a writer with `writeScopes: ["."]`. There is no budget for:

- changed files;
- added/deleted lines;
- UI surfaces touched;
- baseline design tokens altered;
- test/evidence churn;
- cumulative rollback distance;
- semantic overlap with prior repair strategies.

The current lexical anti-repeat gate can be bypassed by paraphrase, so eight “different” whole-workspace repair rounds can keep restyling a product that was already visually degraded. A cap prevents infinite in-process growth; it does not establish convergence.

## 10. Completion is a mutable collection of booleans, not a proof object

The final state is spread across task fields (`auditScore`, `visualAuditPassed`, `supervisorCompletionApproved`, report path), graph phase/completion time, node statuses, join-group review lists, and mutable evidence paths. This permits the stopped task's visible contradiction: audit 100 while visual is false and supervisor approval is false.

The architecture needs one immutable `CompletionReceipt` that can be created only when all typed gates refer to the same revision and requirement contract. Until then, summary values are observations, not completion.

## Required refactor

### A. Event-sourced core

Define versioned domain events such as:

- `nodeTurnStarted`;
- `workerOutcomeRecorded`;
- `reviewVerdictRecorded`;
- `strategyRetired`;
- `integrationReceiptRecorded`;
- `resourceCleanupRecorded`;
- `baselineDiffRecorded`;
- `completionReceiptIssued`.

Apply every event through a pure reducer that validates a revision number and all invariants. Persist the event before side effects advance. Derive task status, graph phase, node display state, and time totals rather than mutating all of them independently.

### B. Separate execution from judgment

Split the monolith into explicit actors/services:

1. scheduler/reducer;
2. worker executor;
3. evidence collector;
4. independent reviewer;
5. integrator/rollback manager;
6. resource and thermal governor;
7. report issuer.

Each returns a typed receipt. No service can directly set a node to completed.

### C. Causal strategy fingerprints

Persist a structured fingerprint containing hypothesis, evidence source, mutation class, verification method, blocker class, and failure signature. A replacement must change at least one causal dimension and explain why. Paraphrasing cannot reset the budget.

### D. Immutable acceptance and design baselines

At task creation, freeze the verbatim goal, requirement IDs, protected files/surfaces, product-design baseline hashes, typography/shape/spacing tolerances, allowed mutation budget, and explicit exceptions. A planner may refine execution but cannot silently delete or weaken acceptance requirements.

### E. Revision-bound receipts

Review, integration, visual comparison, test verification, and completion receipts must all include the same canonical tree/diff hash and evidence-set hash. Any later mutation invalidates downstream receipts automatically.

### F. Replay and model checking

Build deterministic engine tests from event sequences, including crash boundaries after every event. Add property tests asserting impossible combinations cannot be reduced, retries do not reset across restart, superseded strategies never run, approval cannot survive a revision change, and completion always has integration/resource/visual receipts when required.

## Defect classification

| ID | Severity | Defect | Consequence |
|---|---:|---|---|
| F-022 | Critical | No authoritative reducer; 82 distributed mutation sites | Local fixes create cross-field contradictions and new loops |
| F-023 | Critical | Invalid state combinations are representable | Recovery relies on ad hoc flag precedence and migrations |
| F-024 | High | No end-to-end GraphLoopEngine replay tests | Policy tests cannot expose orchestration interleavings |
| F-025 | High | Retry budgets reset across engine runs | “Three attempts” can repeat indefinitely after resume/relaunch |
| F-026 | Critical | Strategy difference uses normalized text equality | Paraphrasing bypasses retirement and repeats the same failed idea |
| F-027 | Critical | Legacy `contains("approved")` inference ignores negation | “Not approved” can become durable approval |
| F-028 | Critical | Approval reuse has no revision/evidence digest | Stale approval can authorize changed work or delete needed repair nodes |
| F-029 | Critical | Completion gate lacks an integration receipt | Three mutable presentation fields can unlock successors |
| F-030 | Critical | Final repair has node/round caps but no mutation/design budget | Bounded churn can still destroy product coherence |

## Evidence

- `Sources/LoopForge/GraphLoopEngine.swift`
- `Sources/LoopForge/Models.swift`
- `Sources/LoopForge/TaskStore.swift`
- `Tests/LoopForgeTests/GraphLoopTests.swift`
- `evidence/task-snapshot-20260809T131753Z.json`
- `evidence/node-iteration-metrics.json`
- `reports/STATUS_ACCOUNTING_AND_CONVERGENCE.md`
- `reports/STRATEGY_CHURN_AND_REVIEW_CAUSAL_MODEL.md`
- `reports/COMPLETION_SCORE_AND_REQUIREMENT_COVERAGE.md`

