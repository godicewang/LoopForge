# Completion Score Inflation and Missing Requirement Registry

Status: confirmed systemic defect. This report explains why the stopped task could display `100/100` while the visual reviewer rejected it and material product defects remained. It does not declare the redesign complete.

## Impossible persisted state

Task `1ED2180F-FBE1-4BCA-9E79-701F40CC3483` retains all of the following simultaneously:

- `auditScore = 100`;
- `auditSummary = "All required Ultra evidence gates passed."`;
- `visualAuditRequired = true`;
- `visualAuditPassed = false`;
- `supervisorCompletionApproved = false`;
- the visual review explicitly lists report-evidence bypass, false financial terminology, malformed competitor ontology, Dynamic Type caps, stale product naming, and missing visual coverage.

This is not a display-only race. The contradiction is produced by the audit model and finalization order.

## Why 100 is easy to obtain

`WorkspaceAuditor.audit` awards a generic 100-point checklist (`Sources/LoopForge/WorkspaceAuditor.swift:101-222`):

- any substantive source already present: 20;
- any qualifying documentation already present: 15;
- any manifest or entry point already present: 10;
- any test file already present: 15;
- any recent successful command-like log: 20;
- no currently tracked unresolved command failure: 10;
- any graph response containing `LOOPFORGE_STATUS: COMPLETE`: 10.

These sum to 100 before visual quality is considered. Visual evidence and visual approval are Boolean hard gates but contribute no score and subtract no points. Therefore `score == 100 && passed == false` is an expected state, not an exceptional one.

For an established repository, the first four categories mostly measure that the project existed before the task. The scanner reads the whole workspace rather than a requirement-specific baseline delta. A large mature app begins close to a passing score even if the current mutation made the product worse.

## Why the persisted summary says every gate passed

`finalizeOrExpand` deliberately performs two different audits:

1. `preliminary = auditor.audit(... requireVisualApproval: false)`;
2. it stores `preliminary.score` and `preliminary.summary` on the task;
3. only afterward it computes `finalAudit = auditor.audit(task: refreshed)` with visual approval required.

The second result controls the branch, but it is not persisted as `auditScore` or `auditSummary` (`Sources/LoopForge/GraphLoopEngine.swift:5203-5209, 5271-5290`). The user therefore sees the optimistic pre-visual result while the engine acts on a different result. The stopped task is an exact historical reproduction of this code path.

## Verification evidence can mask unrelated failures

The workspace snapshot scans recent command/error logs for broad substrings such as `test`, `build`, `verify`, `python`, or `./`. Any later recognized success resets `unresolvedVerificationFailures` to zero, even when it is a different command, subsystem, node, commit, or workspace (`Sources/LoopForge/WorkspaceAuditor.swift:70-96`).

The accompanying unit test intentionally asserts that a later success resolves an earlier failure, but it only covers the same `pytest` suite. There is no command identity, scenario identity, commit identity, or failure fingerprint in the model. In a 19-node graph, an unrelated successful build can erase a failed product contract from the deterministic signal.

## “Requirement evidence” is not based on user requirements

The persisted `lastEvidenceCoverage` has seven generic rows:

1. workspace implementation;
2. reproducible verification;
3. documentation and handoff;
4. regression or recovery coverage;
5. primary visual state;
6. failure/empty/offline/recovery state;
7. accessibility/layout-pressure state.

Two of those seven were `not observed`, including accessibility/layout pressure, yet the preliminary score remained 100.

The collector never atomizes the user's request. `evidenceCoverage` emits a fixed category template and uses filenames as candidates (`Sources/LoopForge/AuditEvidence.swift:296-389`). It does not contain entries for the actual EasyBusiness obligations: American business English, financial terminology, category ontology, direct versus substitute competitors, report provenance, MapKit attribution, or the named audit documents.

Worse, the evidence bundle labels a section `ORIGINAL USER GOAL` but inserts `task.request`, not `task.originalRequest` (`Sources/LoopForge/AuditEvidence.swift:129-132`). An optimized or rewritten request can therefore silently replace the original inside the reviewer evidence.

## No durable requirement identity exists

The Graph schemas contain free-form strings but no requirement registry:

- `LoopTask` stores `request` and optional `originalRequest`, but no parsed immutable requirements, source spans, priorities, prohibitions, or waiver state.
- `GraphPlanNodeProposal` stores title, objective, dependencies, scopes, and verification, but no requirement IDs.
- `GraphLoopState` stores only a free-form `planSummary`, nodes, and review barriers.
- node reviews return one Boolean and free-form text.
- final review returns `approved`, `summary`, `nextInstruction`, `visualPassed`, and repair nodes; it cannot return a result per original requirement (`Sources/LoopForge/GraphLoopEngine.swift:6396-6440`).

Prompts repeatedly include the verbatim goal, which is useful context but not a proof invariant. After many iterations, reviewers can approve a self-consistent plan that has silently dropped obligations because no typed conjunction is available.

The prompt optimizer's deterministic preservation check is also too narrow. It guarantees only URLs, paths, numbers with some units, and quoted labels (`Sources/LoopForge/AuxiliaryModelRouter.swift:220-242`). Unquoted semantic constraints such as “do not redesign the UI,” “preserve the Chinese hierarchy,” “independent review,” or “never mutate EasyBusiness” can disappear while every deterministic token check still passes.

## How this produced aesthetic degradation

The graph had no immutable product/design baseline requirement and no per-requirement visual verdict. Tests and generic evidence were easy to accumulate, while visual judgment was a late Boolean supplied by the same orchestration context. This rewarded changes that increased test count, screenshots, and documentation even when they changed type scale, shape geometry, hierarchy, and density away from the original product.

Once the mutated English state became the next node's workspace, later reviewers treated it as the product baseline. The 100-point signal reinforced that drift: more artifacts made the graph appear more complete without measuring whether the app still resembled the accepted Chinese design.

## Required redesign contract

1. Parse the immutable original request into durable `Requirement` records before planning. Each record needs a stable ID, exact source span, kind, priority, verification policy, and waiver authority.
2. Store immutable baseline artifacts—commit, screenshots, environment, typography tokens, shape geometry, spacing, and accepted intentional-difference policy—as requirements, not prose hints.
3. Require every node and every repair to declare which requirement IDs it advances and which it is allowed to alter.
4. Record requirement verdicts as `unverified | satisfied | violated | externalBlocked | explicitlyWaived`, with exact evidence and independent reviewer identity.
5. Completion must be a conjunction across every non-waived requirement plus runtime, integration, process cleanup, and visual gates. A scalar score may summarize only after the conjunction is known.
6. Replace the generic 100 with labelled dimensions. “Repository readiness,” “task delta verification,” “requirement coverage,” and “visual fidelity” must never be collapsed into one unlabeled number.
7. Persist the same final result shown to the user. Never store a pre-visual score/summary as if it were the final audit.
8. Match failures and successful reruns by command/scenario/fingerprint and commit. An unrelated success may not clear a prior failure.
9. Treat evidence candidates as unverified until an independent checker links them to a requirement. Filename matches are discovery hints only.
10. Add adversarial tests for semantic constraint deletion, score-100/failed contradictions, unrelated failure masking, and plan changes that omit a requirement ID.

The machine-readable companion is `COMPLETION_SCORE_AND_REQUIREMENT_SCORECARD.json`.
