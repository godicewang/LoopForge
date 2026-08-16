# Domain Generality and Autonomous-Orchestration Audit

Status: **forensic analysis in progress; not a final acceptance report**  
Pinned code inventory: `CODE_AUDIT_MANIFEST.json`  
Active inventory: 64 files / 37,444 lines  
Reviewed in this pass: 30 files / 8,663 lines  
Production refactor gate: **closed until 36,000 eligible forensic-analysis seconds**

## Governing conclusion

The current failure is systemic. LoopForge frequently models a general task by first assigning it to a hard-coded domain bucket and then injecting domain-specific policy. This makes orchestration behavior depend on incidental words such as `game`, `Chrome`, `Photos`, `iOS`, `Unity`, or `NPC`, rather than on a typed declaration of authority, capabilities, risks, invariants, evidence, and completion gates. The result is brittle routing, non-transferable fixes, objective drift, and tests that can prove the implementation is internally consistent while the actual product outcome degrades.

The repository-level constraint is now explicit in `/Users/godice/Coding/LoopForge/AGENTS.md`: production orchestration must be domain-neutral, capability-driven, bounded, independently verified, and reversible.

## Defects

### F-063 — Critical — Task-domain taxonomy is embedded in the control plane

`TaskCategory` enumerates script, web, native app, mini program, game, desktop automation, experiment, data, library, maintenance, optimization, and research (`Models.swift:114-115`). `TaskEstimator` then assigns different fixed runtimes, complexity scores, models, and visual requirements to those buckets (`Estimator.swift:31-53`, `Estimator.swift:104-181`). `PromptCompiler` injects different behavioral playbooks, including a bespoke game-design process (`PromptCompiler.swift:199-225`).

This is not a capability abstraction. It is a collection of vertical product assumptions. A request can change scheduler behavior merely by using a keyword, while an unfamiliar task with the same real risks receives no equivalent policy.

Required redesign: infer a typed task contract from declared outcomes—mutation authority, artifact types, interactive surfaces, external resources, risk, reversibility, evidence classes, and acceptance invariants. Domain labels may be presentation metadata only and must never select control logic.

### F-064 — High — Task naming contains prior-project special cases

`TaskNamePolicy.descriptiveSummary` has direct branches for an iOS game, Unity package errors, NPC game systems, and Chrome/browser automation (`Models.swift:828-900`). These examples are not isolated fixtures; they are production behavior.

Required redesign: locale-safe generic summarization with a deterministic first-clause fallback. No product, framework, genre, or prior-customer branch is permitted.

### F-065 — Critical — Desktop preflight is a Chrome product adapter in the generic scheduler

`DesktopAutomationPreflight` searches request text for Chrome aliases, checks bundle identifier `com.google.Chrome`, emits Google-Chrome-specific recovery copy, and executes Chrome AppleScript (`DesktopAutomationPreflight.swift:42-48`, `59-103`, `131-154`). Other applications receive only a broad Accessibility check.

Required redesign: interactive surfaces must declare a capability descriptor and a provider implementation outside the scheduler. The scheduler asks whether the exact declared surface is available; it never contains an application name or script.

### F-066 — High — Permission requirements are inferred from product words

`TaskPermissionRequirements` detects Photos via English/Chinese product phrases and grants Accessibility/Screen Recording based on the `.desktopAutomation` category (`PermissionCenter.swift:29-48`). This can miss new languages and unfamiliar tools, request unnecessary access, or fail to request a capability that a task actually declared.

Required redesign: the plan declares typed host capabilities. Permission readiness is computed from those declarations, not request substring matching.

### F-067 — Critical — The core host-resource protocol supports only iOS Simulator boot

`GraphHostResourceKind` has one case, `iosSimulatorBoot`; the broker operation, identifier validation, request handler, bundled executable, and default provider all encode the same iOS-specific action (`HostResourceLeases.swift:3-5`, `68`, `260-265`, `456-489`, `630`; `Resources/bin/loopforge-host-resource-broker:8-11,60`).

The ownership/lease concept is useful, but the current implementation is a vertical patch embedded in the core.

Required redesign: a generic, capability-registered lease protocol with typed schemas, provider discovery, exact ownership semantics, and an allowlisted operation manifest. Platform adapters live behind that protocol and are never mentioned by graph policy.

### F-068 — High — Idle resource polling can itself create thermal load

Every active Graph node starts `serviceBrokerRequests`, which lists a directory every 50ms until cancellation (`HostResourceLeases.swift:375-381`, `398-399`). This is 20 filesystem polls per second per active node even when no resource is requested. It multiplies with graph concurrency and runs for the entire worker turn.

Required redesign: event-driven filesystem notification or a blocking local IPC channel, with coalescing and a measured idle-CPU budget. No per-node busy polling.

### F-069 — Critical — A supposedly non-mutating control reviewer can inherit Full Access

`LocalSupervisor.review` selects `task.resolvedControlAgent` (`LocalSupervisor.swift:261-299`). Its Codex path passes `selection.accessMode.sandboxMode` directly to `codex exec` (`LocalSupervisor.swift:816-832`) even though the type-level documentation says the control model never edits. A Full Access control selection therefore has technical write authority during review.

Required redesign: reviewers receive a hard read-only execution capability independent of UI selection. Product mutation must be impossible at the process sandbox and workspace-view layers, not merely prohibited in prose.

### F-070 — Critical — “Independent” generation and review reuse the same model

Local mission refinement launches three concurrent prompts through the same `selection`, then asks the same selection to audit those candidates (`LocalSupervisor.swift:376-418`, `518-566`). The ordinary node/final reviews similarly reuse the configured control agent. Different prompt labels do not create epistemic independence.

Required redesign: independent review requires a distinct role boundary plus either a different provider/model family or deterministic/adversarial gates that the author cannot satisfy by assertion. Same-model review must be labeled self-review and cannot carry a completion veto alone.

### F-071 — Critical — Visual approval is a model-authored Boolean, not a visual contract

The review schema accepts `visualPassed`; screenshot attachments are omitted when the selected model lacks vision (`LocalSupervisor.swift:287-288`, `594-635`). A non-vision reviewer can still return the required Boolean. Citations and geometry are not machine-validated. The exact EasyBusiness evidence already proves a clipped label and duplicate captures passed this gate.

Required redesign: pin a baseline and environment receipt; require unique-state captures, comparable before/after geometry, typography, spacing, clipping, contrast/accessibility signals, and an independent native visual veto. Model judgment supplements these gates and cannot replace them.

### F-072 — Critical — Worker and control processes inherit the app's entire environment

`CodexRuntime.environment()` starts from `ProcessInfo.processInfo.environment` (`CodexCapabilities.swift:130-136`), and both worker and control Codex processes receive it. This can expose unrelated credentials and host configuration to task code or model tools. Adding one intended provider key does not remove the unrelated variables.

Required redesign: construct an allowlisted environment from zero, explicitly adding only locale, safe executable paths, task-scoped runtime paths, and the one credential needed by the selected provider.

### F-073 — High — Prior-scenario handoff suffixes are production runtime policy

`CodexRunner` scans arbitrary user text for uppercase variables ending in `_HANDOFF`, `_BEFORE_STATUS`, or `_AFTER_STATUS`, creates a hidden runtime directory, and synthesizes values for them (`CodexRunner.swift:497-536`, `564-577`). This is a previous scenario contract promoted into general production code.

Required redesign: runtime artifacts must be declared in a typed task contract. The runner never mines prose for magic environment-variable suffixes.

### F-074 — High — Compatibility bridge is not demonstrably loopback-only and permits large per-connection buffers

`ResponsesChatBridge` starts `NWListener(using:.tcp,on:.any)` while merely returning a `127.0.0.1` URL (`ResponsesChatBridge.swift:34-50`). It accumulates up to 64 MB per accepted connection and does not bound concurrent clients (`ResponsesChatBridge.swift:75-99`). Authorization helps, but it is not a substitute for a loopback binding and resource admission policy.

Required redesign: bind an explicit loopback endpoint, cap headers/body/connections, track accepted connections, cancel them on stop, and make backpressure observable.

### F-075 — High — Declared Claude support is not backed by its wire contract

The Claude template uses `https://api.anthropic.com/v1`, but both direct and bridge paths append `/chat/completions` and send OpenAI Chat Completions JSON while only adding Anthropic headers (`OpenAICompatibleClient.swift:111,194-197`; `ResponsesChatBridge.swift:151-164`). No active real-provider test proves this path.

Required redesign: provider adapters advertise and implement a verified wire capability. Unsupported combinations fail at configuration time instead of masquerading as compatible.

### F-076 — High — Local-model lifetime can outlive the task and retain heat

`OllamaManager` starts a long-lived `Process` directly, configures `OLLAMA_KEEP_ALIVE=5m`, and stops only the immediate server with `process.terminate()` (`OllamaManager.swift:111-151`, `327-349`). This bypasses `ProcessRunner` descendant reclamation. If an external Ollama is already active, LoopForge borrows it without a task-scoped model-unload contract.

Required redesign: acquire local inference as a typed lease, set per-request keep-alive based on task lifetime, unload task-owned models at terminal state, and stop the exact owned process tree with a verified terminal receipt.

### F-077 — High — Broker inbox can starve new requests after 64 retained files

The broker sorts all request names and processes only the first 64, but completed request/response files remain until the whole scope closes (`HostResourceLeases.swift:398-430`). Once the oldest 64 pairs remain present, later requests can fall outside the prefix indefinitely.

Required redesign: atomically consume/remove or archive each request, maintain a bounded ordered queue, and test more than one batch.

### F-078 — Critical — Strategy retirement tests lexical spelling, not strategy identity

`isMateriallyDifferent` lowercases and strips non-alphanumerics, then checks exact string inequality (`GraphLoopEngine.swift:1122-1147`, `1180-1186`). A paraphrase of the same objective, evidence source, action, or verification route therefore passes as a new strategy.

Required redesign: persist a structured strategy contract—hypothesis, action class, evidence source, mutation scope, verification oracle, failure signature, and assumptions—and compare those fields plus deterministic resource/effect fingerprints. A model may propose the structure but cannot self-certify novelty.

### F-079 — Critical — Final-repair fallback broadens authority to the entire workspace

`conservativeFinalRepairProposal` discards the rejected proposal's dependencies and returns `writeScopes:["."]` (`GraphLoopEngine.swift:430-468`). This violates the rule that a fallback must be narrower than or equal to the authority it replaces and permits final-audit prose to trigger an unrestricted mutation node.

Required redesign: no automatic writer fallback. Invalid repair proposals remain rejected; Main must return a precise scope proven against the unmet requirement and immutable baseline, or retain a truthful gap.

### F-080 — High — Retry and replacement budgets are fixed counts with no progress/risk model

Every node receives six unapproved decisions and at most two replacements regardless of mutation size, cost, risk, evidence novelty, repeated failure signature, or whether the task is read-only (`GraphLoopEngine.swift:1011-1014`, `1046-1058`, `1088-1114`). A high-risk visual rewrite can mutate six times; a low-risk investigation can be retired despite new evidence.

Required redesign: budget attempts by measured strategy progress, risk, mutation surface, evidence novelty, and cost. Identical failure signatures retire immediately; demonstrably new evidence can justify a bounded extension.

### F-081 — High — The passing test suite ratifies unsafe behavior

The full suite passed 281 tests with 6 skipped and 0 failures, yet `testConservativeFinalRepairFallbackUsesFreshIDAndDropsUnsafeDependencies` explicitly asserts `writeScopes == ["."]` (`GraphLoopTests.swift:1169-1219`). The suite therefore demonstrates internal consistency, not correctness against the new generality and safety contract.

Required redesign: replace implementation-affirming tests with adversarial invariants: no authority widening, no semantic strategy replay, no mutation by reviewers, no domain tokens in control logic, and no completion without independent baseline gates.

### F-082 — High — External blockers are accepted through loose keyword correlation

`ExternalBlockerPolicy` contains platform/product phrases such as Apple distribution and App Store Connect; it accepts a claim when any recent command failure contains any external signal (`Models.swift:1017-1044`). The command is not causally tied to the claimed requirement and a non-empty dependency list can broadly support `externally_blocked` coverage.

Required redesign: blockers are typed records bound to one requirement, one exact operation, one retained command/API receipt, an authority boundary, and a retry/switch condition.

### F-083 — High — Model capabilities are inferred from names and frozen versions

Vision support is inferred from `qwen3.6:` and `devstral-small-2:` prefixes (`Models.swift:241-244`); API provider catalogs filter hard-coded future version patterns and fallback model IDs (`AgentModels.swift:29-137`). This will reject capable unfamiliar models and accept renamed models without verified tool/schema behavior.

Required redesign: capability probes and persisted signed receipts for tools, vision, context, schema, streaming, reasoning controls, and provider wire protocol. Names are display metadata only.

### F-084 — Medium — Watcher persistence failure is silent

`WatcherStore.save()` swallows all persistence errors (`WatcherStore.swift:52-69`). The UI can continue showing a mutation that was never durably checkpointed, undermining restart/recovery truthfulness.

Required redesign: surface checkpoint health, retain the last durable generation, and stop scheduling state-changing passes when required persistence fails.

### F-085 — Medium — Package smoke test masks an executable failure

`smoke_test.sh` runs the packaged Ollama executable with `|| true` (`Scripts/smoke_test.sh:22`), so a broken bundled runtime can still produce “Bundle smoke test passed.”

Required redesign: every required packaged executable must exit successfully; optional checks must be explicitly labeled and excluded from acceptance.

### F-086 — High — Active time starts before semantic work is observed

`ActiveWorkDurationTracker` initializes `eligible=true` and starts its segment immediately. `CodexRunner` constructs it before process launch and only pauses it after a recognized transport-degradation event (`RuntimeHealth.swift:177-204`; `CodexRunner.swift:261-281`). Startup silence, blocked pipe setup, and unrecognized idle states can therefore enter the hard runtime ledger.

Required redesign: start ineligible; open a segment only on a semantically productive event or a verified long-running owned command, and close it on terminal, wait, transport degradation, approval wait, or lack of measurable progress.

### F-087 — High — Evidence citations are checked for non-emptiness, not truth

`enforcingCoverageForApproval` accepts any non-empty citation string and does not resolve the path, command receipt, screenshot identity, timestamp, hash, or requirement binding (`LocalSupervisor.swift:641-682`).

Required redesign: citations must be typed IDs into an immutable evidence store and machine-resolve to the exact artifact or execution receipt.

### F-088 — High — Same-model approval can waive requirements as externally blocked

Completion coverage accepts `externally_blocked` when the decision contains any external dependency, without checking that dependency against the specific requirement or a blocker receipt (`LocalSupervisor.swift:641-661`). Combined with same-model review, this lets narrative structure substitute for causal evidence.

Required redesign: one blocker record per requirement, deterministic binding, and independent verification of the authority boundary. Unverified blocked requirements prevent completion.

## Positive mechanisms worth preserving behind new abstractions

- `ProcessRunner` bounds retained output and attempts descendant reclamation; the ownership concept is correct even though process-group/PID-lifetime guarantees still need later audit.
- Host leases distinguish borrowed resources from LoopForge-owned state transitions and persist intent before acquisition.
- Graph history now preserves superseded nodes and per-iteration decisions instead of erasing failed strategies.
- Package creation is explicit, checksum-producing, and verifies the code signature.
- The current suite provides a useful characterization baseline even where its asserted contract is wrong.

## Required architectural direction

1. Replace domain categories and keyword routing with a typed `TaskContract` and capability registry.
2. Split author, executor, deterministic evaluator, and independent reviewer into enforceable authority domains.
3. Make strategy identity structured and persist failure signatures, novelty evidence, mutation cost, and retirement lessons.
4. Make baselines immutable and acceptance gates artifact-specific but domain-neutral through registered evaluators.
5. Remove all automatic authority widening and require scoped, reversible integration with rollback receipts.
6. Replace polling and unmanaged long-lived runtimes with leased, event-driven, task-owned resources.
7. Build an allowlisted environment and typed evidence/blocker stores.

These are design requirements, not authorization to begin the production refactor before the forensic-analysis time gate is satisfied.

The next control-plane tranche is recorded in
`CONTROL_PLANE_AND_WATCHER_AUDIT.md` (F-089 through F-111). It proves that
vertical assumptions also exist in workspace scoring, evidence selection,
Watcher UI projection, cadence/retry behavior, persistence, process authority,
and completion state—not only in the original Graph planner.
