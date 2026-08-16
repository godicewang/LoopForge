# Source-to-Kernel Migration Map

Status: pre-implementation architecture. It covers every production source, script, resource helper, and package file in the 64-file audited manifest. It does not authorize production edits before the forensic gate.

## Migration rules

1. Preserve the existing dirty patch byte-for-byte as migration input; do not reset, stash, or wholesale overwrite it.
2. Build the new kernel side-by-side behind compatibility projections.
3. Move policy out of controllers, views, prompts, and provider adapters before deleting legacy paths.
4. Provider/tool names may exist only inside adapters and UI catalog metadata; core scheduling sees typed capabilities.
5. Every legacy state field must be classified as authoritative event, derived projection, untrusted claim, or deprecated compatibility data.
6. Old tests remain characterization until explicitly ratified against the new invariant matrix.

## Target source topology

```text
Sources/LoopForge/
  Kernel/
    TaskContract.swift
    OrchestrationEvent.swift
    RunCommand.swift
    RunReducer.swift
    RunJournal.swift
    RunState.swift
    ReceiptStore.swift
    RunProjection.swift
  Execution/
    RuntimeSupervisor.swift
    ProcessLease.swift
    CapabilityRegistry.swift
    MutationCoordinator.swift
    WorkspaceIsolation.swift
    QuiescenceVerifier.swift
    ThermalGovernor.swift
  Evidence/
    EvidenceGraph.swift
    VerificationReceipt.swift
    ReviewReceipt.swift
    VisualBaseline.swift
    VisualCaptureAdapter.swift
  Convergence/
    StrategyFingerprint.swift
    ProgressVector.swift
    ConvergenceGovernor.swift
  Adapters/
    Codex/
    LocalModel/
    API/
    DesktopAutomation/
    IOSSimulator/
  Watcher/
    WatcherTriggerEngine.swift
    WatcherPipelineAdapter.swift
  Compatibility/
    LegacyTaskImporter.swift
    LegacyProjectionBridge.swift
  UI/
    DesignTokens.swift
    RunViews.swift
    WatcherViews.swift
```

Folders describe ownership boundaries, not extra products or targets. The kernel stays domain-neutral.

## File-level disposition

| Current file | Disposition | Migration responsibility |
|---|---|---|
| `Package.swift` | modify late | register new files/resources without changing product identity; preserve build compatibility |
| `Resources/bin/loopforge-host-resource-broker` | replace protocol | convert fixed Simulator-shaped operations into versioned capability-adapter IPC; retain strict request validation |
| `Scripts/bootstrap_vendor.sh` | retain/harden | deterministic dependency bootstrap receipt; no hidden mutation |
| `Scripts/generate_report_example.sh` | move to fixture | remove from release authority; output is documentation-only |
| `Scripts/make_icon.swift` | retain | deterministic asset generation; hash output |
| `Scripts/make_social_preview.swift` | retain | presentation asset only; never evidence |
| `Scripts/make_visual_audit_fixture.swift` | replace fixture system | generate explicit pass/fail typography, shape, spacing, density, hierarchy fixtures |
| `Scripts/package_app.sh` | harden | bind package to tested revision, sign identity, executable smoke receipt, SHA-256 |
| `Scripts/smoke_test.sh` | replace oracle | launch actual executable, verify native state and post-quit quiescence; directory existence is insufficient |
| `Scripts/validate_discovery.sh` | adapter contract test | test capability discovery without keyword/brand policy |
| `AgentModels.swift` | split | provider catalog/adapter descriptors remain; model names and defaults leave core policy |
| `AppModel.swift` | reduce to composition root | construct kernel/adapters/projections; remove state mutation and policy inference |
| `AuditEvidence.swift` | replace | typed `EvidenceGraph`, independent collectors, full attachment manifests, digest/provenance receipts |
| `AuxiliaryModelRouter.swift` | adapter boundary | route typed requests; strict one-envelope response; no authority or completion decisions |
| `CodexCapabilities.swift` | adapter boundary | capability probes and connection status only; no scheduler policy |
| `CodexRunner.swift` | retain executor, add receipts | preserve event/process transport; emit typed outcomes and command receipts; remove free-text status authority |
| `CompletionReportGenerator.swift` | projection only | render receipt-backed facts and labeled claims; never infer completion |
| `DesktopAutomationPreflight.swift` | capability adapter | typed probe/lease with explicit app/session identity and read/write authority |
| `Estimator.swift` | advisory only | estimates cannot grant category, runtime, privilege, or acceptance; contract builder owns authority |
| `GraphLoopEngine.swift` | replace incrementally | decompose monolith into reducer commands, runtime supervisor, mutation coordinator, evidence/review pipeline, convergence governor |
| `HostResourceLeases.swift` | generalize | durable capability/resource ledger; adapters implement concrete lifecycle; event-driven broker and quiescence receipts |
| `LocalSupervisor.swift` | split | provider client remains adapter; review becomes provenance-bound receipt request; mission rewriting cannot amend contract |
| `LoopController.swift` | replace with command facade | submit start/pause/stop commands and observe projections; no timers, direct mutation, process ownership, or cleanup tasks |
| `LoopForgeApp.swift` | await supervisor shutdown | application termination consumes one drain/quiescence result; no fixed grace as proof |
| `Models.swift` | compatibility bridge | freeze legacy Codable schema, add importer; new authoritative types live in Kernel/Evidence/Execution |
| `OllamaManager.swift` | local-model process adapter | durable process-tree lease, awaited shutdown/escalation, resource/thermal budget |
| `OpenAICompatibleClient.swift` | provider adapter | strict typed transport, bounded data, provider identity; no scheduler semantics |
| `PermissionCenter.swift` | authority UI/adapter | permissions are explicit capability receipts; no task-category privilege inference |
| `ProcessRunner.swift` | retain and wrap | keep process-tree escalation; add process lease identity, join result, output digests, and quiescence integration |
| `PromptCompiler.swift` | demote | compile typed contracts/claims into provider input; prompts cannot enforce scope, authority, state, or acceptance |
| `ResponsesChatBridge.swift` | provider adapter | preserve protocol bridge; emit typed transport events and actor lineage |
| `RuntimeHealth.swift` | merge into supervisor | health signals inform typed eligibility/resource state; cannot rewrite task state directly |
| `SystemPermissionAutomator.swift` | replace polling | event-triggered, expected-prompt capability adapter with short lease and quiescence ownership |
| `TaskStore.swift` | legacy importer/projection | new journal is authoritative; snapshots are rebuildable; UI publication and persistence are separated |
| `Utilities.swift` | audit and retain pure helpers | remove policy hidden in string/path helpers; keep deterministic utilities |
| `Views.swift` | replace state consumption | read `RunProjection`; shared design tokens; truthful status, time, privilege, evidence, convergence, and cleanup states |
| `WatcherController.swift` | replace with trigger engine + facade | no operation task ownership or self-review; submit typed commands to shared supervisor/kernel |
| `WatcherFocusProjector.swift` | retain as projection | pure derivation only; no authority or acceptance |
| `WatcherModels.swift` | compatibility + typed contract | migrate markers and mutable pipeline state to trigger/requirement/receipt types |
| `WatcherPolicy.swift` | split | deterministic domain-neutral pipeline validation remains; product/tool-specific logic moves to adapters |
| `WatcherPromptCompiler.swift` | demote | serialize typed pipeline contract; remove brand/vertical evidence policy and self-approval semantics |
| `WatcherReportGenerator.swift` | projection only | receipt-backed cadence, pass, anomaly, attention, and cleanup facts |
| `WatcherStore.swift` | replace with journal projection | semantic checkpoints, hash/version validation, replayable triggers |
| `WatcherViews.swift` | redesign projection | shared tokens and truthful cadence/total/current/excluded time; no hidden mode or optimistic completion |
| `WorkspaceAuditor.swift` | replace scoring authority | keep neutral inventory diagnostics only; requirement closure moves to evidence graph and typed verification |

## Legacy-state classification

### Import as historical facts

- task/node IDs and timestamps;
- verbatim request and persisted prompts;
- raw log/event bytes;
- command/process exit observations when source bytes exist;
- Git/workspace paths and hashes as untrusted historical observations;
- iteration durations as observed/excluded legacy time;
- resource lease records.

### Import as untrusted claims

- `lastAgentMessage`, `lastReview`, plan summaries;
- audit/visual summaries;
- completion narrative;
- test counts extracted from prose;
- “safe,” “verified,” “integrated,” and external-blocker descriptions without receipts.

### Recompute as projections

- task/node status;
- accepted/current/excluded time;
- requirement coverage;
- convergence budget and strategy fingerprints;
- terminal/quiescence state;
- report facts and UI labels.

### Never migrate as authority

- aggregate audit score;
- `LOOPFORGE_STATUS` and Watcher status substrings;
- free-form write scopes or capability keywords;
- visual approval based on file integrity;
- exit-code-only integration success;
- optimistic `resumeOnNextLaunch`, pause, stop, or completion flags.

## Compatibility rollout

### Slice 1 — Kernel shadow state

Introduce journal/reducer/contract/receipts and replay neutral scripted scenarios. Legacy UI remains primary, but every legacy mutation is mirrored as a typed command and divergences are logged. No target-repository behavior changes.

### Slice 2 — Runtime and quiescence ownership

Move Loop, Graph, Watcher, process, timer, model, broker, and capability ownership into `RuntimeSupervisor`. Terminal UI begins using receipt-backed lifecycle state.

### Slice 3 — Transactional workspaces

Route writer nodes through `MutationCoordinator`; eliminate isolation fallback, implicit Git init, conflict exit-code approval, and unscoped publication.

### Slice 4 — Evidence/review/convergence

Replace free-text outcomes, log scoring, permissive JSON, self-review, and count-based churn with typed receipts and progress fingerprints.

### Slice 5 — Visual baselines and UI projection

Add immutable capture manifests and visual vetoes; migrate Loop/Watcher UI to shared tokens and truthful projections.

### Slice 6 — Watcher and legacy importer

Move Watcher scheduling onto shared kernel, import old tasks/checkpoints as contradiction-aware history, remove duplicate controller/store state machines.

### Slice 7 — Delete compatibility authority

After full replay, fault injection, package, and native acceptance, prevent legacy fields from changing authoritative state. Retain read-only import support.

## Anti-big-bang safeguards

- each slice compiles and has reducer/adaptor tests before call-site migration;
- no mass rewrite of `GraphLoopEngine.swift` without side-by-side behavior receipts;
- every removed path is preceded by an exact usage inventory;
- the current dirty patch remains recoverable and its useful fixes are migrated intentionally;
- package/native verification runs after each lifecycle/UI-affecting slice;
- user-owned LoopForge task data receives backup, schema migration dry-run, and rollback proof.

This map is the implementation boundary: core becomes general-purpose policy; concrete tools remain replaceable adapters; views become projections; prose loses authority.
