# LoopForge Test-Contract Ratification Audit

Status: forensic analysis only; production refactor remains unauthorized until the 36,000-second analysis gate is met.

Scope: every line of all 19 active test files in `Tests/LoopForgeTests` (9,840 lines), reconciled against the 26,604 reviewed production-source lines and the retained EasyBusiness failure corpus. EasyBusiness remained read-only.

## Outcome

The suite is useful as a characterization harness, but it is not an acceptance system for a general-purpose autonomous scheduler. It contains solid unit coverage for graph dependency barriers, path traversal, worktree scope checks, stale telemetry, atomic persistence recovery, bounded process output, and some descendant termination. At the same time, it repeatedly turns incident-specific behavior into permanent product contracts and treats self-authored evidence as independent proof.

The key distinction is:

- **Characterization value:** the suite can tell us when current behavior changes.
- **Acceptance value:** the suite cannot tell us whether the behavior is convergent, domain-neutral, aesthetically safe, independently verified, or thermally bounded.

Passing all 281 tests therefore characterizes the current system; it does not certify the system the user asked for.

## Findings

### F-134 — Domain fixtures have become product contracts

`EstimatorTests`, `PromptCompilerTests`, `DesktopAutomationPreflightTests`, `PermissionCenterTests`, `TaskStoreTests`, `LocalSupervisorTests`, and `GraphLoopTests` explicitly preserve Chrome, ChatGPT, GPT-3.5, Selenium, game mechanics, App Store, Photos, Community, Friends, EasyBusiness, US_R1 handoff variables, and bilingual keyword-routing behavior. This is not neutral coverage of a capability registry; it is regression protection for vertical special cases.

Required replacement: contract-driven fixtures generated from declared capabilities, with domain examples living outside core policy tests.

### F-135 — The suite normalizes maximum privilege as the default

`CodexCapabilitiesTests` accepts `danger-full-access` plus `approval_policy="never"`; `TaskStoreTests` requires both new-task agents to default to Full Access; Graph writer tests require Full Access across objectives; Watcher fixtures persist and advertise Full Access. Tests do not require a least-privilege derivation, capability receipt, or an explicit reason for escalation.

Required replacement: deny-by-default authority, per-node capability leases, and assertions that privilege expansion is explicit, scoped, time-bounded, and auditable.

### F-136 — Visual acceptance is reduced to file integrity

`AuditorTests` and release round two promote `passedBasicIntegrity` for an arbitrary generated PNG directly into `visualAuditPassed`; once that Boolean is true, the workspace audit passes. The image can be a flat rectangle. No test compares typography, icon geometry, shape vocabulary, spacing rhythm, hierarchy, density, localization expansion, accessibility sizes, or a protected product baseline.

Required replacement: immutable baseline manifests, semantic screen coverage, perceptual and geometry diffs, typography/shape/spacing gates, and independent visual vetoes.

### F-137 — Self-authored review is repeatedly treated as independent evidence

Tests accept `lastReview = "Approved"`, `visualAuditPassed = true`, Agent-authored `review.json`, and report narratives without provenance separation. `LocalSupervisorTests` call review “independent semantic fidelity,” but do not prove distinct model identity, context isolation, evidence isolation, or absence of the implementer’s conclusions.

Required replacement: signed review provenance recording actor, model, context lineage, evidence hashes, independence class, and veto authority.

### F-138 — Verification history can be laundered by a later generic success

`AuditorTests.testLaterSuccessfulVerificationResolvesEarlierFailedAttempt` explicitly requires a later green command to clear a prior failure. It does not require command identity, affected scope, revision identity, environment identity, or proof that the failing assertion was rerun.

Required replacement: verification receipts keyed by command, revision, workspace, environment, requirement, and artifact hashes; only a matching superseding receipt may close a failure.

### F-139 — Reports can convert unproven fields into verified delivery claims

`CompletionReportTests`, `DocumentationReportFixtureTests`, and Graph report tests validate presentation strings and copied images, but do not verify that narrative claims were derived from receipts. Static phrases such as “independent review,” “real scenarios,” and “verified” are accepted because they were inserted into the fixture.

Required replacement: report generation from an immutable evidence graph; unsupported prose must be rejected or visibly labeled as an Agent claim.

### F-140 — Process/resource cleanup coverage is fragmented rather than end-to-end

`RuntimeHealthTests` usefully prove one spawned descendant is reaped, and lease tests prove an iOS-simulator provider can release an exact UDID. They do not replay Graph cancellation, reviewer timeout, app quit, crash recovery, broker failure, launchd ownership, multiple descendant groups, and final process-table quiescence as one lifecycle. `LoopControllerLifecycleTests` mainly assert controller flags and stage strings.

Required replacement: process-group receipts and end-to-end lifecycle scenarios that finish only after descendants, brokers, leases, worktrees, timers, and stores are quiescent.

### F-141 — Host-resource coverage is vertically bound to iOS Simulator

The only first-class host resource exercised is `iosSimulatorBoot`; the broker command, environment, provider, operational prompt, and packaging assertions all encode `xcrun simctl`. There is no provider-neutral contract suite for arbitrary exclusive/shared resources.

Required replacement: a generic resource-provider protocol test kit with the simulator as one adapter, not the scheduler’s ontology.

### F-142 — Convergence is defined by fixed retry counts, not measured progress

Graph tests canonize “three consecutive blocked turns” and structural review on the seventh unapproved cycle. These are useful emergency ceilings but not convergence semantics. The tests do not measure novelty, evidence delta, objective distance, repeated mutations, strategy identity beyond text similarity, or expected value of another turn.

Required replacement: progress vectors, strategy fingerprints, diminishing-return detection, mutation budgets, retirement receipts, and a hard rule that a retired strategy cannot be resurrected by renaming.

### F-143 — Decoder tests ratify extracting authoritative JSON from arbitrary prose

`LocalSupervisorTests` and `GraphLoopTests` require acceptance of a decodable balanced JSON object embedded among examples, prose, code fences, and misleading braces. This makes the first syntactically acceptable object authoritative even when transport/schema boundaries are ambiguous.

Required replacement: structured transport output only, exactly one envelope, schema/version binding, message-role binding, and rejection of trailing or competing semantic payloads.

### F-144 — Capability discovery is based on command and naming lexicons

Graph tests require uppercase runtime-variable discovery such as `US_R1_HANDOFF`, English word-boundary heuristics for GUI/browser tooling, and `_handoff`-style disposable runtime detection. This verifies token recognition, not declared capability negotiation.

Required replacement: typed node requirements and adapter-declared capabilities; prose must never grant host authority.

### F-145 — Tests approve implicit Git initialization in a user workspace

`testCandidateCapabilityInitializesOnlyAnEmptyProject` explicitly expects capability discovery to create `.git` in an empty directory. Discovery is therefore state-changing and cannot be safely repeated as a read-only probe.

Required replacement: pure discovery, followed by a separately authorized and recoverable initialization transaction in LoopForge-owned isolation.

### F-146 — Integration tests preserve risky remote and stash semantics

Published-node tests approve pushing from an isolated node, fast-forwarding the canonical branch, and stashing “exact upstream dirty content.” Although unrelated dirt is protected, the system still relies on patch identity and path classification instead of a transaction journal with a user-owned baseline, rollback receipt, and explicit remote side-effect authority.

Required replacement: no remote mutation by default; staged integration transaction, immutable preimage, explicit mutation set, rollback proof, and post-integration verification before commit publication.

### F-147 — Prompt-substring assertions stand in for runtime guarantees

Watcher and Graph tests repeatedly assert that guidance contains phrases such as “bounded deadline,” “terminate and reap,” “independently rerun,” and “Do not call collaboration.” Those checks prove prompt wording, not enforcement.

Required replacement: runtime policy tests that attempt violations and prove the executor, sandbox, broker, scheduler, and state machine reject them.

### F-148 — Watcher review can create a thermal feedback loop

`testHealthyAgentReviewSchedulesAnImmediateFreshPipelinePass` requires a healthy review to schedule a new pass at `now`. Combined with scheduled reviews, warning events, and unconditional assessment refresh, this can collapse cadence into review → immediate pass → review activity.

Required replacement: a single cadence governor with coalescing, minimum quiet periods, power/thermal budgets, backoff, and proof that review cannot bypass the next eligible pass.

### F-149 — Persistence pressure is treated as success without write-amplification limits

`testR2SingleLoopRapidCheckpointUpdatesReloadLatestAtomicState` executes 150 synchronous state updates and checks only the last value. `TaskStoreTests` also canonizes a 30-second graph-log publication interval. Neither suite measures bytes written, fsync rate, encode cost, UI publication churn, or coalescing efficacy.

Required replacement: write-amplification budgets, dirty-field journaling, adaptive debounce, flush-on-boundary, and thermal/power regression tests.

### F-150 — The release scenarios do not exercise the actual autonomous control loop

The two “release rounds” mostly call pure policies, `ProcessRunner`, `WorkspaceAuditor`, `TaskStore`, and `GraphWorkspaceCoordinator`. `GraphLoopTests` call decoder/schema helpers but never replay a complete `GraphLoopEngine` run with a deterministic fake Main Agent and Node Agent through plan, execute, reject, retire, replace, integrate, final audit, cleanup, and report.

Required replacement: deterministic engine replay fixtures with recorded decisions, injected failures, model-independent clocks, and exact terminal-state assertions.

### F-151 — The suite contains no protected product-design baseline

No active test encodes the recoverable Chinese EasyBusiness baseline or any other immutable product-design baseline. There is no assertion that a localization/adaptation task must preserve information architecture, control geometry, type hierarchy, icon language, or screen topology unless an authorized design-change objective says otherwise.

Required replacement: product baseline contracts that are immutable to worker nodes and changeable only through an explicit owner-approved design migration.

### F-152 — Typography, shape, and spacing have no first-class acceptance tests

Despite production UI containing 32 literal point-font uses and 73 literal corner-radius calls, the test suite contains no system-level typography scale, semantic text style, corner vocabulary, hit-target, density, localization overflow, or accessibility geometry assertions.

Required replacement: design-token invariants plus rendered native geometry tests at standard and accessibility sizes.

### F-153 — Hidden-fanout tests only inspect argument tokens

Watcher and parallel-candidate tests assert that launch arguments contain the strings `multi_agent`, `multi_agent_v2`, and `enable_fanout`; they do not parse the effective configuration or attempt a nested delegation. A malformed or inverted flag can satisfy the test.

Required replacement: parse the effective launch configuration and run an adversarial child turn that must fail to create hidden work.

### F-154 — Model catalogs are tested as fixed identities rather than capability contracts

`AgentModelTests`, `EstimatorTests`, and routing tests freeze provider names, local model versions, memory estimates, and priority order. This becomes stale and encourages the scheduler to infer competence from a model slug.

Required replacement: runtime capability negotiation, benchmark receipts, context/vision/tool constraints, and versioned catalog adapters outside core scheduling policy.

### F-155 — Mission preservation is asymmetrical by provider

`LocalSupervisorTests` explicitly require Codex and API control agents to bypass mission rewriting while local agents receive candidate/audit selection. This means objective-preservation defenses depend on provider identity, not task risk, and can leave the most powerful Full Access path without the same semantic checkpoint.

Required replacement: provider-neutral mission contract capture and immutable objective hashes before any mutating turn.

### F-156 — Domain-shaped evidence requirements contaminate generic approval

Tests use `World exploration`, onboarding, recruit heroes, settlement, App Store submission, signed-in Chrome, and ten-image counts as generic requirement-coverage examples. These strings participate in approval and prompt behavior rather than living in isolated adapter fixtures.

Required replacement: abstract requirement IDs in core tests; domain fixture packages exercise adapters without changing core acceptance semantics.

## What the current suite does protect well

The redesign should retain and strengthen these behaviors:

1. path traversal and symlink escape rejection;
2. dependency and join barriers before successor materialization;
3. exact write-scope checks for isolated worktrees;
4. refusal to stash unrelated canonical dirt;
5. stale/oversized Watcher telemetry rejection;
6. bounded subprocess output and basic timeout recovery;
7. exclusion of offline time from active-time accounting;
8. atomic-store backup recovery;
9. exact resource ownership distinction between borrowed and owned leases;
10. preserving superseded graph history without scheduling it again.

These are components of a safe scheduler, not evidence that the scheduler as a whole is safe or convergent.

## Required test architecture

The replacement suite needs six layers:

1. **Pure policy properties:** graph acyclicity, authority lattice, resource ownership, state-machine invariants.
2. **Typed adapter contracts:** models, tools, resources, UI automation, and domain packs isolated from the core.
3. **Deterministic engine replay:** full Graph runs with injected decisions, failures, stalls, relaunches, and time.
4. **Mutation transactions:** preimage, declared mutation set, integration, rollback, remote-boundary, and postimage receipts.
5. **Independent acceptance:** reviewer provenance, immutable evidence, visual baselines, adversarial veto, and requirement closure.
6. **Operational budgets:** CPU, thermal, process count, timers, checkpoint bytes, write amplification, cadence, and quiescence.

Until these layers exist, a green suite must be labeled **characterization passed**, never **autonomous delivery verified**.
