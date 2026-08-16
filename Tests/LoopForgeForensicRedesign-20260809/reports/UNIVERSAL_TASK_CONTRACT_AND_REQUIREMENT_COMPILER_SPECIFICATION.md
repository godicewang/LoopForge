# Universal Task Contract and Requirement Compiler Specification

Status: pre-implementation normative design; production refactor remains unauthorized until the 36,000-second forensic gate.

## Executive conclusion

LoopForge currently sends a preserved user request to agents, but it does not preserve the request as an executable contract. The controlling structure is still inferred from keyword-driven categories and model-written prose. This is the mechanism that allowed a localization task to become a broad visual redesign, allowed successful tests to outweigh a damaged interface, and allowed later plans to silently weaken earlier constraints.

The replacement is a domain-neutral compiler. It converts the immutable user utterance and explicitly accepted amendments into typed requirements, constraints, non-goals, baselines, risks, authority boundaries, evidence recipes, and unresolved ambiguities. Every planned node must own requirement IDs. Every mutation must cite an owned requirement and a baseline-relative budget. Every review must attach source-revision-bound receipts to those IDs. Completion is a conjunction over mandatory requirements at one accepted revision, never a category score, elapsed time, output marker, or reviewer impression.

This design does not encode special rules for commerce, health, games, localization, or any other vertical. It reasons from observable capabilities, artifact kinds, mutation risk, evidence modality, and explicit authority.

## Measured current topology

The inspected dirty source has the following objective-compilation surface:

- `TaskEstimator` contains approximately 302 string literals in its first 212 lines, including multilingual keywords for task type, complexity, authorization, and visual work.
- Source contains 98 category-dependent branches or cases.
- Category-dependent behavior appears in at least fourteen production files: `Estimator`, `PromptCompiler`, `WorkspaceAuditor`, `GraphLoopEngine`, `AppModel`, `AuditEvidence`, `PermissionCenter`, `CodexRunner`, `LoopController`, `DesktopAutomationPreflight`, and presentation/model code.
- There is no production `Requirement`, `Constraint`, `NonGoal`, `AcceptanceContract`, or equivalent typed source-of-truth declaration.
- `GraphPlanNodeProposal` has nine data fields, but none carries requirement ownership, baseline identity, risk, mutation budget, rollback policy, evidence recipe, or strategy identity.
- `PromptOptimizer.contractTokens` preserves URLs, paths, numbers, and quoted spans only. Ordinary negative constraints, comparative language, design intent, ordering, and semantic relationships can disappear while the rewrite passes.
- `PromptCompiler.acceptanceRequirements` synthesizes generic prose from quality and category. The resulting bullets are not stable IDs and are not checked individually.
- `WorkspaceAuditor.audit` derives completion from proxy file counts, log patterns, category branches, `LOOPFORGE_STATUS: COMPLETE`, screenshot presence, and a scalar score.
- `GraphPlanPolicy.normalizedNodes` silently drops invalid proposals, removes unresolved dependencies, defaults an empty writer scope to `.` and accepts arbitrary objective/verification prose.
- initial, node, batch, exhausted-node, incremental and final reviewers each consume different narrative projections of the task. None is required to prove semantic equivalence to a canonical requirement set.

The system therefore preserves the words but not their operational meaning.

## Defects added by this analysis

### F-179 — Category inference is acting as latent authority

A substring classifier changes model choice, permissions, visual-review requirements, worker prompts and acceptance behavior. A non-authoritative heuristic can therefore broaden access or redefine success.

### F-180 — The original request has no typed requirement identity

Requirements cannot be durably owned, superseded, satisfied, waived, blocked or compared across plans because they have no stable IDs or source spans.

### F-181 — Prompt rewrite preservation is lexically narrow

URLs, paths, numbers and quoted strings survive, but semantic negation, comparisons, priorities, preservation clauses, non-goals and aesthetic intent can be lost.

### F-182 — Graph plans can silently discard requirements

Node proposals name bounded objectives but do not declare the requirement IDs they cover. A replan or replacement can appear valid while leaving original obligations ownerless.

### F-183 — Acceptance recipes are invented by the same planning path

Generic prompt bullets and node-authored verification can become the evidence used to approve the node, creating a self-sealing contract.

### F-184 — Ambiguity policy defaults to execution even when impact is irreversible

The prompt says to ask no questions for ordinary ambiguity but has no deterministic distinction between safe reversible assumptions and product-defining choices.

### F-185 — Proxy artifact counts substitute for semantic outcomes

A source file, documentation file, test command or screenshot can satisfy points without proving any specific user requirement, and unrelated evidence can mask a failed primary outcome.

### F-186 — Re-estimation mutates governance after persistence

Task loading can recompute visual-audit requirements from current keyword logic. An unchanged historical request can acquire different governance after an application update.

### F-187 — Invalid plan normalization is lossy rather than fail-closed

Unknown dependencies can disappear and malformed proposals can be dropped. The remaining graph no longer proves that the accepted plan is equivalent to the proposed plan or complete for the task.

### F-188 — Whole-workspace fallback repairs erase least-authority planning

The conservative final repair currently emits `writeScopes: ["."]`. A failed completion review can authorize a new unbounded rewrite precisely when prior strategy safety is least trustworthy.

## Immutable source model

The root object is `TaskContract`, not `LoopTask.request` plus derived category fields.

```text
TaskContract
  contractID
  revision
  sourceDigest
  utterances[]
  requirements[]
  constraints[]
  nonGoals[]
  baselines[]
  authority
  assumptions[]
  ambiguities[]
  evidenceRecipes[]
  riskProfile
  amendmentHistory[]
  compilerReceipt
```

`utterances` retain exact UTF-8 bytes, author, timestamp and precedence. The initial user message is revision zero. Later user instructions become amendments; they do not overwrite history. Model output, file contents and inferred workspace conventions can propose interpretations but cannot create user authority.

The contract is content-addressed. Every plan, attempt, mutation, review and publication receipt includes `contractID`, `revision` and `sourceDigest`. Evidence from a different revision is visible but cannot close the current contract without an explicit compatibility receipt.

## Requirement representation

Each requirement is typed:

```text
Requirement
  id                       stable content-derived identifier
  sourceSpans[]            exact utterance byte ranges
  statement                lossless normalized proposition
  modality                 must | mustNot | should | may
  kind                     outcome | preservation | process | evidence | duration | delivery
  priority                 mandatory | preferred | optional
  subject                  artifact/surface/process reference
  predicate                observable expected relation
  scope                    included resources and states
  exclusions[]             explicit boundaries
  dependencies[]           other requirement IDs
  conflicts[]              candidate conflict IDs
  acceptanceRecipeIDs[]
  riskTags[]
  baselineIDs[]
  status                   open | accepted | rejected | waived | infeasible | superseded
```

IDs are derived from source revision, source spans, modality, subject and predicate; wording cleanup cannot mint a new obligation. A requirement may be decomposed into children only through a `RequirementRefinement` that preserves the parent and proves logical coverage. Removing a mandatory child requires a user amendment or a typed infeasibility decision within the existing authority boundary.

## Constraints, non-goals and preservation obligations

Constraints are first-class and independently veto-capable:

- workspace and path boundary;
- read-only versus mutation authority;
- allowed external effects;
- protected files, data and branches;
- exact product, platform, account or surface;
- time-accounting rules;
- model or tool constraints explicitly chosen by the user;
- privacy, credential, payment, legal and destructive-action boundaries;
- baseline preservation constraints;
- concurrency and resource constraints.

Negative language is never reduced to a positive objective. `Do not redesign`, `preserve unrelated changes`, `never resume`, and `read only` compile into hard deny predicates. They must be checked before scheduling and before every effect, not merely repeated in prompts.

Non-goals capture requested exclusions and safe inferred exclusions. Inferred non-goals have `proposed` status and may restrict autonomous work only when they reduce risk without preventing a mandatory requirement. They can never be used to waive an outcome.

## Baseline bindings

A requirement that says adapt, repair, translate, improve, preserve, compare, regress or redesign is relational. The compiler must bind it to a baseline rather than treating the current workspace as a blank slate.

```text
BaselineBinding
  baselineID
  artifactSelector
  sourceRevision
  captureDigest
  acceptedGoodProperties[]
  knownDebt[]
  allowedChangeDimensions[]
  forbiddenRegressionDimensions[]
```

If no baseline can be resolved, the requirement remains `ambiguityRequiresEvidence` or `blockedOnBaseline`; the scheduler may perform read-only discovery but cannot start a broad mutation. Known baseline debt is explicit: new work need not preserve an existing defect, but it may not worsen it or use it as license for unrelated change.

## Epistemic states and claim provenance

Every compiler output distinguishes:

- `explicit`: directly entailed by a cited user span;
- `workspaceObserved`: derived from immutable workspace evidence;
- `conventionObserved`: derived from project instructions or established patterns;
- `inferredSafe`: conservative, reversible interpretation;
- `proposed`: model suggestion awaiting authority or evidence;
- `unknown`: unresolved;
- `conflicted`: incompatible evidence or instructions.

A high-confidence probability is not authority. A model cannot convert `proposed` to `explicit`. Reviews cannot close an `unknown` requirement by omitting it. Reports display provenance rather than flattening everything into polished prose.

## Ambiguity and authority decision table

The compiler evaluates ambiguity by impact and reversibility:

| Impact | Reversible | Action |
|---|---:|---|
| local, no external effect | yes | record one bounded assumption and proceed |
| changes implementation detail but preserves all baselines | yes | allow experiment behind rollback boundary |
| affects product identity, information architecture or protected design | any | request authority or preserve baseline |
| broadens write, network, app, account or data scope | any | deny until explicitly authorized |
| changes a mandatory outcome or non-goal | any | require user amendment |
| depends on unavailable evidence | yes | schedule bounded read-only discovery |
| destructive, costly, legal, credentialed or public | any | block for authority |

The phrase “do not ask for ordinary ambiguity” applies only to the first two rows. It is not a blanket authorization to decide product strategy.

## Domain-neutral capability and risk features

`TaskCategory` may remain temporarily as a display label during migration, but it must not control authority, acceptance or scheduler policy. Replace category branches with independent features inferred from contract and workspace evidence:

```text
CapabilityNeeds
  readsWorkspace
  writesWorkspace
  executesCommands
  controlsInteractiveSurface
  accessesNetwork
  capturesRenderedState
  accessesSensitiveData
  publishesExternally
  usesCredential
  requiresSpecialHardware

ArtifactKinds
  executable | library | document | dataset | media | configuration |
  interactiveUI | externalAction | analysisResult | package

RiskDimensions
  mutationBreadth
  reversibility
  visualHierarchyImpact
  dataLossPotential
  externalEffect
  privacySensitivity
  securityBoundary
  financialOrLegalCommitment
  resourceCost
  uncertainty
```

Two causally equivalent tasks in unrelated domains must compile to the same scheduler policy. Product nouns and vertical keywords may improve a UI label but do not grant permission, choose acceptance, or mint retries.

## Requirement compiler pipeline

The compiler is deterministic around model assistance:

1. **Ingest** exact utterance bytes, workspace identity, project instructions and selected execution settings.
2. **Lex** explicit paths, names, versions, numbers, negations, quantifiers, comparisons, preservation clauses, time rules and external-effect verbs.
3. **Propose semantics** using an optional model that returns source-span-linked typed candidates; raw prose is rejected.
4. **Normalize** equivalent predicates without deleting their source spans.
5. **Validate entailment** using deterministic rules plus an independent semantic review that sees the source and candidate contract, not a prior agent rationale.
6. **Resolve conflicts** by authority and temporal precedence; never by model confidence alone.
7. **Bind baselines** from Git revisions, immutable files, screenshots, schemas, APIs, tests or user-selected references.
8. **Derive capability and risk features** from effects and artifacts, not domain category.
9. **Compile acceptance recipes** independently of worker plans.
10. **Check ownership feasibility**: every mandatory requirement must be ownable, externally blocked or explicitly unresolved.
11. **Ratify** a versioned contract receipt. Mutation remains disabled until ratification passes.

If the model fails, the compiler emits a conservative partial contract and permits only read-only evidence collection. It never falls back to a broad build/modify category.

## Evidence recipe model

Acceptance is defined before worker execution:

```text
EvidenceRecipe
  id
  requirementID
  verifierKind             deterministic | nativeVisual | adversarial | userAuthority
  preconditions[]
  commandOrCaptureSpec
  expectedObservation
  revisionBinding
  freshnessPolicy
  independencePolicy
  failureClass
```

Recipes must describe observations, not filenames or exit-code proxies alone. Examples of general observations include a state transition, schema invariant, retained identity, absence of overlap, successful round-trip, rendered hierarchy relation, resource quiescence, or immutable byte equality.

A worker may add candidate evidence, but cannot change a mandatory recipe or mark it accepted. An independent verifier generates a signed `RequirementReceipt` containing exact command/capture identity, source and artifact digests, environment, start/end times, outcome and exclusions.

## Planner contract

Replace the current nine-field proposal with:

```text
PlanNodeContract
  nodeID
  contractRevision
  ownedRequirementIDs[]
  observedConstraintIDs[]
  objective
  dependencies[]
  readSet[]
  writeSet[]
  externalEffectSet[]
  baselineBindings[]
  evidenceRecipeIDs[]
  mutationBudget
  resourceBudget
  strategyFingerprint
  rollbackPolicy
  publicationPolicy
  joinBarrier
```

Admission is fail-closed:

- every mandatory requirement has exactly one current owner or a declared join-owner set;
- every node owns at least one open requirement or a necessary dependency proof;
- no objective introduces a proposition absent from the contract;
- no node weakens a hard constraint;
- dependencies resolve exactly; unknown IDs reject the entire proposal;
- write and external-effect sets are precise and within authority;
- risk has a matching baseline, budget, verifier and rollback policy;
- parallel nodes do not share a source of truth or acceptance receipt;
- replacement nodes preserve requirement ownership and cite retired strategy lessons;
- plan cardinality and budgets cannot grow through rephrasing or splitting.

No normalizer may silently delete nodes, dependencies, requirements or invalid scopes. It returns a typed rejection with the exact field path.

## Review and completion semantics

Requirement state is reduced only from receipts:

```text
accepted(R, revision) =
  all required recipes for R have valid receipts
  AND receipts bind to revision
  AND no newer contradictory receipt exists
  AND all constraints attached to R pass
  AND all baseline regression vetoes pass
```

Task completion is:

```text
complete(revision) =
  every mandatory requirement accepted at revision
  AND no mandatory requirement is unknown, conflicted or ownerless
  AND no hard constraint failed
  AND no protected baseline regressed
  AND all external effects have reconciled receipts
  AND publication/quiescence receipts are present when required
```

Elapsed time, file counts, model markers, generic documentation, one successful command and scalar audit scores are diagnostics only. None participates in the truth function above.

## Amendments, precedence and supersession

Only a user-authority event may amend mandatory requirements, deny rules or baselines. Amendments contain source spans and explicitly list:

- requirements added;
- requirements refined;
- requirements superseded;
- constraints strengthened or weakened;
- baseline changes;
- effects on active plans and evidence.

A new amendment opens a convergence epoch but preserves all prior attempts and retired strategies. Compatible receipts may be adopted with an explicit compatibility proof. Incompatible nodes are safely stopped before a new plan is admitted. A replan is never an amendment.

## Legacy import

Historical tasks import into `LegacyTaskClaim`:

- original and effective requests remain separate claims;
- category becomes a non-authoritative display hint;
- generated acceptance bullets become proposed recipes, not accepted requirements;
- audit scores and `COMPLETE` markers remain historical claims;
- file/log/screenshot observations become untrusted evidence candidates;
- contradictory states are preserved and surfaced;
- no old task is automatically resumed during import;
- no legacy graph acquires mutation authority until a new contract is ratified.

This prevents a software update from retroactively legitimizing a historical mutation or silently changing its governance.

## User interface requirements

The native task view must show:

- immutable original request and current contract revision;
- mandatory/preferred requirement counts and current states;
- explicit constraints and non-goals;
- requirement owner nodes;
- baseline and risk badges;
- accepted, rejected, missing and stale receipts;
- current assumption and its reversibility;
- exact reason a plan or mutation is denied;
- cumulative task active time and current-iteration real-time duration separately;
- excluded idle/blocked/waiting time;
- amendments and superseded decisions without hiding history.

The UI must not present a category label, percentage score or model-written summary as proof of completion.

## Deterministic and property tests

1. Exact original UTF-8 bytes survive compile, persist, reload and report.
2. Every requirement cites at least one valid source span.
3. “Do not modify” compiles to a hard deny predicate.
4. “Preserve X while adapting Y” creates separate preservation and outcome requirements.
5. Comparatives retain both baseline and target relation.
6. Negative constraints survive prompt optimization.
7. A rewrite that drops ordinary unquoted intent is rejected.
8. A rewrite that changes modality from should to must is rejected.
9. A rewrite that adds a platform, feature or public effect is rejected.
10. Category vocabulary cannot change authority.
11. Domain noun substitution leaves equivalent capability/risk policy unchanged.
12. Full Access cannot weaken task or effect authority.
13. Missing baseline permits discovery but denies broad mutation.
14. Known baseline debt may be repaired but not worsened.
15. Product-defining ambiguity cannot be auto-assumed.
16. Safe reversible ambiguity creates a bounded recorded assumption.
17. Every mandatory requirement has an owner before launch.
18. An ownerless mandatory requirement rejects the entire plan.
19. Unknown dependency rejects the proposal rather than disappearing.
20. Empty writer scope does not default to whole workspace.
21. Whole-workspace final repair is rejected without explicit contract authority.
22. A node cannot own requirements outside its effect boundary.
23. A replacement preserves all predecessor requirement IDs.
24. Split nodes cannot mint budget or drop requirements.
25. Worker-authored verification cannot ratify a mandatory recipe.
26. Exit zero without expected observation does not accept a requirement.
27. Screenshot presence without baseline-bound inspection does not accept visual quality.
28. Evidence from an older revision is stale unless compatibility is proven.
29. Evidence from an isolated worktree cannot close the integrated revision.
30. Contradictory receipts keep a requirement open.
31. A scalar score cannot override one failed mandatory requirement.
32. Elapsed-time satisfaction cannot accept any requirement.
33. User amendment supersedes exactly the cited obligations and no others.
34. Crash/replay preserves contract revision, ownership and receipt states.
35. Legacy completion imports as a claim, not a fact.
36. Legacy tasks never auto-resume merely because import succeeds.
37. Property test: every mutating command cites an open owned requirement and valid authority receipt.
38. Property test: every accepted task has a proof path from each mandatory requirement to fresh evidence.
39. Property test: no plan transition reduces mandatory coverage without a user amendment.
40. Vocabulary-invariance test: causally identical tasks across unrelated domains compile to identical control policy.

## Implementation boundary after the forensic gate

1. Introduce a pure `TaskContractKernel` module containing value types, compiler validation, reducers and receipt checks.
2. Add a journaled `TaskContractRepository`; never recompute durable governance on task load.
3. Run the compiler in report-only shadow mode against historical and synthetic tasks.
4. Replace category-controlled authority and acceptance with capability/risk features.
5. Upgrade Graph proposal schemas and reject lossy normalization.
6. Bind evidence collection to requirement IDs, source revisions and immutable artifact digests.
7. Replace scalar `WorkspaceAuditor` completion with receipt conjunction while retaining metrics as diagnostics.
8. Add native contract/requirement/evidence views and explicit amendment flow.
9. Migrate legacy state conservatively with resume disabled.
10. Remove category governance only after shadow equivalence and adversarial tests pass.

The essential invariant is simple: agents may propose how to satisfy the contract, but they may not rewrite what the contract means, grant themselves authority, choose their own proof standard, or erase failed obligations.
