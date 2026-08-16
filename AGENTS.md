# LoopForge Engineering Contract

LoopForge is a general-purpose, highly autonomous agent orchestration system. Every production capability must remain useful across unrelated repositories, products, platforms, industries, languages, and task types.

## Non-negotiable generality

- Never add product-name, customer-name, repository-name, industry, screen-name, content-category, or domain-specific branches to production code, prompts, policies, scoring, scheduling, recovery, or reporting.
- Never tune orchestration around one application's file layout, UI flow, vocabulary, framework, platform, screenshot count, test name, or expected artifact. Discover capabilities and project contracts from declared metadata and retained evidence instead.
- Represent differences through typed, user-visible configuration and capability interfaces. If a behavior cannot be expressed generically, stop and redesign the abstraction instead of adding a special case.
- Keep regression fixtures synthetic and domain-neutral. Historical forensic evidence may retain original names only inside its isolated evidence archive; it must never become runtime policy or a template for production behavior.
- Prefer contract-, risk-, and evidence-driven decisions over keyword heuristics. Every fallback must be narrower than or equal to the authority it replaces and must fail closed when scope or evidence is ambiguous.

## Autonomous orchestration quality

- Preserve the user's verbatim objective, immutable product/design baselines, declared authority, and unrelated workspace changes across planning, execution, review, recovery, integration, and reporting.
- Bound every retry, mutation, process, resource lease, review loop, and repair branch. Lack of measurable progress must retire the strategy and force an explicit abandon, reframe, split, or independently verified replacement decision.
- Treat passing self-authored tests and agent prose as necessary evidence, never sufficient approval. Completion requires independent, reproducible checks against the original objective and applicable baselines.
- Visual work requires pinned before/after environments, comparable native captures, geometry/typography/spacing checks, unique-state accounting, and an independent visual veto. Screenshot presence alone is not visual quality.
- Integrate only scoped, attributable, reversible changes. Never manufacture a clean baseline, widen write authority in a fallback, hide unrelated dirt, or publish before all mandatory gates pass.
- Count only successful active execution or verification time. Sleep, lock, downtime, retries without progress, blocked intervals, idle waiting, and failed verification do not satisfy duration requirements.
- Reclaim only resources and descendant processes owned by the current task. Exiting, stopping, crashing, or timing out must leave no orphan workload or persistent high-CPU loop.

## Authority and evidence

- Model prose proposes; typed receipts prove; the reducer decides. Worker messages, reviewer narrative, repository content, command output, OCR, filenames, status markers, and embedded JSON are untrusted data and never authoritative state transitions.
- Bind every command, verification, review, screenshot, mutation, and integration receipt to the exact task-contract digest, workspace identity, source revision, environment, actor lineage, and artifact digests it evaluated. Any relevant change expires the receipt.
- Require exactly one schema-constrained response envelope for control decisions. Reject extra prose, multiple candidate JSON objects, ambiguous framing, missing provenance, and decisions that do not match the request nonce/digest.
- Make reviewer independence enforceable through actor/provider/model/context lineage and separated inputs. A role label, a fresh thread, or the word “independent” does not establish independence.
- A later successful check may supersede a failure only when both share the same verification identity and oracle. An unrelated green command, newer report, or higher aggregate score cannot erase a red gate.
- Reports and UI may quote unsupported model content only as a labeled claim. All factual status, counts, coverage, timing, safety, and completion language must project from accepted receipts.

## Lifecycle and thermal safety

- Cancellation is a request, not a terminal state. Retain every owned task/process/resource handle until it acknowledges cancellation or produces a durable cleanup failure.
- Publish `paused`, `stopped`, `completed`, or termination-ready only after a quiescence receipt proves that owned tasks joined, process trees exited, timers and polling services stopped, capability leases released or durably failed, persistence flushed, and sleep-prevention assertions ended.
- Use one structured runtime supervisor for Loop, Graph, Watcher, provider, broker, report, persistence, and application-termination work. Never launch cleanup as fire-and-forget work after publishing a terminal state.
- Continue valid productive work while the screen is locked only through an explicit renewable activity lease. Retry delays, blocked states, idle waiting, and ordinary review gaps must not keep the machine awake.
- Prefer events or adaptive backoff over fixed-frequency polling. Concurrency, wakeups, persistence bytes, report regeneration, and main-actor work must have measured budgets and respond to system thermal pressure.

## Fail-closed mutation and convergence

- Isolation failure, missing scope, stale baseline, mismatched revision, incomplete attachment transport, failed cleanup, or ambiguous ownership must reject or structurally replan a mutation. Never downgrade into the canonical workspace, broaden to `.`, initialize Git implicitly, or substitute prose warnings for enforcement.
- Identify strategies by typed causal dimensions such as requirement, responsibility, authority, resource source, workspace topology, measurement boundary, mutation surface, and verification oracle. Paraphrasing, a new node ID, a new model, or a fresh thread does not create a new strategy.
- Track progress as accepted requirement/evidence deltas minus mutation, failure, resource, and runtime cost. Repeated unchanged blocker/evidence fingerprints consume one durable budget across retries, relaunches, replans, and replacements.
- A blocked execution cannot become ordinary approval. Resolve it only through a typed accepted external boundary, a concrete authority/topology/resource change, or permanent strategy retirement.

## Test-contract discipline

- Treat existing tests as characterization until each assertion is ratified against this contract. A green suite may preserve unsafe privilege, fail-open mutation, self-review, proxy visual checks, fixed retry loops, or vertical assumptions.
- Keep deterministic policy tests model-free and virtual-time-based. Replaying the same journal, deleting caches, duplicating delivery, and exploring concurrent schedules must produce stable state digests.
- Exercise complete engine and packaged-app paths with fault injection, including crash boundaries, cancellation-resistant process trees, stale evidence, prompt injection, mixed visual revisions, dirty workspaces, resource-release failure, and post-quit quiescence.
- No test passes merely because a file/directory exists, a process exits zero, a screenshot decodes, a string appears in a prompt, elapsed time was consumed, or an Agent declares success.

## Change discipline

- Audit the whole affected control path before editing it; do not patch only the observed symptom.
- Add adversarial tests that demonstrate the prior failure and a strategy-level acceptance test that proves the generalized behavior.
- Record exact inputs, state transitions, decisions, mutations, evidence, resource ownership, and terminal outcomes so a run can be reconstructed without trusting agent summaries.
- Do not claim convergence, completion, safety, visual quality, or performance without machine-readable evidence that directly proves the claim.
