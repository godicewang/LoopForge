# Graph Engine Full-Source Audit

Status: every line of `Sources/LoopForge/GraphLoopEngine.swift` (6,539 lines) reviewed. Evidence only; no production source was changed. EasyBusiness remained read-only.

## Verdict

The engine contains thoughtful local safeguards, including durable iteration history, post-review integration, dependency barriers, explicit strategy retirement, binary patches, and some fail-closed branches. They do not form one enforceable autonomy architecture. The 6,539-line `@MainActor` object still combines plan parsing, authority, execution, review, retry, Git mutation, recovery, integration, final approval, and reporting. Safety depends on prose and mutable booleans, while several fallback paths deliberately broaden authority or silently change isolation.

This read corroborates earlier defects F-022–F-030, F-038–F-054, F-063, F-067, F-069–F-073, and F-078–F-080. The findings below record additional source-specific defects exposed by the full read.

## New findings

### F-125 — Critical — Core strategy-retirement prompt contains EasyBusiness paths

The production `exhaustedNodeReviewSystemPrompt` teaches write-scope syntax with `EasyBusiness/Features/Community/**` and `EasyBusinessUITests/**` (`GraphLoopEngine.swift:6156-6159`). A historical product is therefore embedded in the reasoning context of every unrelated Graph strategy retirement.

Required redesign: no product, platform, repository, language, locale, tool, or prior task name may occur in core prompts. Examples must be schema-generated from the active repository capability manifest or use neutral placeholders validated by tests.

### F-126 — High — Generic execution capability is inferred from a fixed command/scenario lexicon

`requiresDisposableRuntime` searches task prose for a fixed list of Python, Node, Swift, Xcode, Cargo, Go, .NET, browser, screenshot, simulator, and historical `_handoff`/status filenames (`GraphLoopEngine.swift:1832-1872`). The process-lifecycle prompt separately embeds one iOS Simulator broker protocol (`GraphLoopEngine.swift:1781-1804`). Unknown build systems or writable inspection tools are missed; unrelated prose can trigger a costly copy.

Required redesign: typed capability discovery declares filesystem, process, GUI, network, cache, and host-resource requirements. Tool adapters register capabilities outside the scheduler core.

### F-127 — Critical — Worktree preparation failure silently downgrades an isolated writer to the canonical workspace

When `workspaces.prepare` throws, the engine changes the node to `.exclusiveWorkspace`, points it at the primary project, and immediately launches the same worker (`GraphLoopEngine.swift:2914-2948`). The task began under an isolated-write contract, but a local preparation failure silently expands blast radius instead of asking for a replan or stopping.

Required redesign: isolation level is an immutable authority floor. A failure may reduce capability or pause; it can never grant direct canonical writes. Replanning must create a new transaction with explicit authority and rollback.

### F-128 — Critical — Declared write scope is a post-hoc patch filter, not an execution boundary

`GraphNodeAccessPolicy.selection` returns the parent Agent unchanged, including Full Access (`GraphLoopEngine.swift:1753-1773`). The worker prompt tells the Agent to respect scopes, but enforcement occurs only when Git changed paths are compared before patch integration (`GraphLoopEngine.swift:2261-2287,2665-2685`). A Full Access worker can mutate paths or systems outside the isolated Git tree that no patch check observes.

Required redesign: execute inside a capability sandbox whose filesystem mounts, environment, network, host resources, Git refs, and process namespace mechanically implement the node contract. Post-hoc diff validation remains defense in depth only.

### F-129 — Critical — Conflict repair equates process exit zero with successful integration

On patch conflict, a fresh Agent is launched directly in the primary workspace with the isolated and canonical paths in prose. `repairIntegration` returns `result.exitCode == 0` (`GraphLoopEngine.swift:5581-5627`); callers then mark the original node completed (`GraphLoopEngine.swift:4442-4500`). There is no changed-path budget, intended-result manifest, unrelated-file invariant, independent review, or rollback receipt.

Required redesign: conflict resolution runs in a coordinator-owned merge workspace, produces a typed merge candidate, proves intended and untouched paths, reruns independent gates, then atomically updates the canonical tree with a rollback receipt.

### F-130 — High — Structured output decoder accepts any earlier decodable JSON object

`decode` first tries the whole response, then scans every balanced object and returns the first object that decodes (`GraphLoopEngine.swift:5937-5984`). A model can emit an example, quoted prior object, or superseded draft before its actual decision, and lifecycle control will accept the earlier object. This contradicts the promise that only the final structured verdict controls state.

Required redesign: use one transport-level schema response with exact framing, reject extra objects/text, persist raw bytes and schema version, and bind the decoded decision hash to the review receipt.

### F-131 — Critical — Parallel-worktree capability is made sticky without ownership provenance

After a Graph has once recorded worktree support, later runs set `clean=true` whenever that old flag is true, even if the current capability scan reports a dirty repository (`GraphLoopEngine.swift:2748-2760`). The coordinator then mirrors the entire current primary workspace into a new worktree and commits that mirror as an integration baseline (`GraphLoopEngine.swift:2045-2072`). It cannot distinguish LoopForge-integrated dirt from unrelated user edits made after pause.

Required redesign: persist a canonical tree/diff receipt and an ownership manifest. On resume, classify every delta as coordinator-owned, user-owned, or unknown; unknown changes invalidate isolation preparation until reconciled.

### F-132 — High — Parallel mode may initialize and commit an external project implicitly

For an empty non-Git project, `candidateCapability` runs `git init` and creates an empty commit with LoopForge identity (`GraphLoopEngine.swift:1945-1981`). Although limited to directories with no visible entries, this is a durable version-control mutation performed while determining capability, before an explicit integration transaction exists.

Required redesign: discovery is read-only. Repository initialization is a separately authorized, reversible setup transaction with before/after receipt and clear ownership.

### F-133 — High — Cleanup and orchestration completion are fire-and-forget

The child registry cancels Swift tasks but never awaits their termination (`GraphLoopEngine.swift:1683-1725`). Workspace cleanup ignores `git worktree remove` errors and uses best-effort filesystem deletion (`GraphLoopEngine.swift:2490-2499`). Per-event callbacks also create unconstrained MainActor tasks (`GraphLoopEngine.swift:3659-3734,5608-5618`), and the signal semaphore keeps an unbounded pending array (`GraphLoopEngine.swift:1661-1681`). A stopped or superseded node can therefore retain processes, worktrees, queued UI/persistence work, and heat after the visible state advances.

Required redesign: structured task groups, bounded event channels with backpressure/coalescing, task-scoped process groups, awaited cancellation, and durable cleanup receipts. A node cannot reach a terminal state until resource cleanup is proven or represented as a visible failure.

## Corroborated systemic defects

- **No reducer/replay model (F-022–F-024):** 82 mutation closures and captured/reloaded snapshots remain the state machine.
- **Retry budgets reset or measure counts rather than causes (F-025, F-052, F-080):** batch/final counters are process memory, provider failures retry after ten seconds, and final repair allows eight rounds/32 nodes without mutation or damage budgets (`GraphLoopEngine.swift:5170-5190,5240-5299`).
- **Strategy identity remains lexical (F-026, F-049, F-051, F-078):** punctuation-stripped text equality decides whether a replacement is materially different (`GraphLoopEngine.swift:1114-1224`).
- **Legacy approval inference remains unsafe (F-027):** any review containing “approved,” including “not approved,” is reconstructed as approval (`GraphLoopEngine.swift:1620-1649`).
- **Approval reuse is not revision-bound (F-028):** `supervisorCompletionApproved`, a generic audit, and non-empty review text are treated as unchanged proof; pending repair branches may then be deleted (`GraphLoopEngine.swift:5211-5230,5480-5511`).
- **Completion lacks an integration receipt (F-029):** completed time plus non-empty review text unlock successors (`GraphLoopEngine.swift:1268-1287`).
- **Whole-workspace repair survives (F-030, F-054, F-079):** missing scopes default to `.`, and conservative final repair explicitly writes `.` (`GraphLoopEngine.swift:289-299,445-475,1248-1261`).
- **Reviewer independence is asserted, not proven (F-043, F-050, F-062, F-070):** node review, candidate selection, final audit, strategy retirement, and report narrative all prefer the same configured control Agent.
- **Visual truth is model-authored (F-039–F-046, F-071):** final completion consumes `visualPassed` from the control model while the final prompt omits the complete evidence text.

## Required replacement boundary

The engine should not be incrementally patched into another larger coordinator. Replace it behind compatibility adapters with:

1. a pure versioned reducer and append-only event journal;
2. immutable goal, authority, baseline, mutation-budget, and publication contracts;
3. capability-discovered worker sandboxes;
4. typed worker, evidence, review, integration, cleanup, and completion receipts;
5. causal strategy fingerprints and persistent budgets;
6. a single Git authority with isolated merge/rollback transactions;
7. independent adversarial review that cannot share author context or authority;
8. bounded event streams and a process/thermal governor;
9. deterministic replay/property tests for every crash boundary and interleaving;
10. a truthful UI derived only from reducer state and receipts.

The remaining test corpus must now be read in full to identify which unsafe behaviors are currently ratified and which compatibility surfaces the replacement must deliberately break.
