# Vertical Special-Case Inventory and Removal Boundary

Status: complete source/test inventory; production refactor remains gated.

## Principle

Generality does **not** mean pretending providers and host tools are identical. A typed ChatGPT authentication adapter, a Chrome UI-control adapter, a Photos permission adapter, or an iOS Simulator lease provider may exist. The defect is allowing those adapters’ names, workflows, and failure remedies to become the scheduler’s task taxonomy, planning vocabulary, privilege policy, evidence model, or completion rubric.

The safe boundary is:

```text
core scheduler contract
  -> typed capability request
  -> adapter selected from runtime registry
  -> scoped authority/resource lease
  -> capability receipt and evidence
```

The current implementation often runs the relationship in reverse: prose keywords select a domain branch, the branch grants a tool/privilege, and the same branch later decides whether work is complete.

## Mechanical inventory

The reviewed production tree contains 87 grouped line matches across the six incident vocabularies below. Counts are line matches and may overlap; they are not defect counts.

| Vocabulary cluster | Production line matches | Active-test line matches | Dominant locations |
|---|---:|---:|---|
| EasyBusiness / Community / Friends / US_R1 | 2 | 31 | `GraphLoopEngine.swift`, `GraphLoopTests.swift` |
| Chrome / GPT-3.5 / Selenium / WebDriver | 43 | 38 | `DesktopAutomationPreflight.swift`, prompt/supervisor/estimator paths |
| Unity / NPC / settlement / world exploration / recruit / wuxia | 15 | 35 | `Models.swift`, `AuditEvidence.swift`, supervisor/tests |
| Photos / photo library | 15 | 3 | permission inference/automation and package entitlements |
| App Store | 4 | 6 | blocker heuristics, supervisor guidance, reports |
| iOS Simulator / `simctl` | 8 | 3 | host-resource implementation and Graph operational prompt |

## Production removal/migration map

### Core policy violations — remove from the core

1. `GraphLoopEngine.swift:6158` uses `EasyBusiness/Features/Community/**` and `EasyBusinessUITests/**` as the canonical example in an exhausted-node control prompt. Replace with schema-generated examples from the node’s actual repository-relative scope grammar.
2. `Models.swift:867-876` contains Unity/NPC-specific title rewrites; `Models.swift:920` contains a task-name vocabulary. Replace with provider-neutral summarization constrained by immutable source spans and a deterministic generic fallback.
3. `AuditEvidence.swift:278,379-383` hardcodes settlement, hero recruitment, building, and world-exploration screen classes. Replace with requirement IDs and screen-state declarations captured from the product baseline or user objective.
4. `Estimator.swift:201-202` classifies work from Chrome/ChatGPT phrases. Remove keyword task taxonomy; derive capabilities from an explicit preflight plan.
5. `PromptCompiler.swift:185,218,246`, `AppModel.swift:975`, and `LocalSupervisor.swift:280` embed one browser incident’s exact forbidden substitutions. Preserve the general invariant—do not substitute the named interaction surface—but express it once as a typed immutable interaction-surface contract.
6. `LocalSupervisor.swift:282` encodes pre-release game/App-Store evaluation rules. Replace with a generic lifecycle/evidence-availability model.
7. `WorkspaceAuditor.swift:233-248` extracts image counts and special-cases “ten photos.” Replace with typed deliverable cardinality parsed and confirmed before execution.
8. `PermissionCenter.swift:34-47` and `SystemPermissionAutomator.swift:19,47` infer Photos authority from prose. Authority must come from a capability request reviewed before the turn, not keyword occurrence.
9. `GraphLoopEngine.swift:1792-1799` inserts iOS Simulator commands in the universal long-running resource prompt. Replace with provider-generated instructions attached only when that lease type is requested.

### Valid adapters in the wrong architectural layer — isolate behind registries

1. `DesktopAutomationPreflight.swift` is a concrete Google Chrome adapter. Keep its capability only if moved behind a general `InteractiveSurfaceAdapter` registry. The core should see availability, authority requirements, session identity, operations, and receipts—not Chrome menu instructions.
2. `HostResourceLeases.swift` and `Resources/bin/loopforge-host-resource-broker` are an iOS Simulator provider. Keep the adapter but make the lease registry provider-neutral and move `simctl` guidance out of Graph core prompts.
3. `PermissionCenter.swift` may retain a Photos permission adapter, while requirement selection moves to typed capability declaration.
4. `CodexCapabilities.swift`, `AppModel.swift`, and `Views.swift` may name ChatGPT where they are specifically presenting/authenticating the Codex provider. Provider UI is not a task-domain special case; it must not leak into generic scheduling or evidence policy.
5. `Scripts/package_app.sh` may retain Photos usage descriptions only if the packaged binary genuinely contains the optional Photos adapter and the UI explains why authority is requested.

### Generic ideas currently expressed through vertical examples — retain the idea, delete the example

- Exact interaction-surface preservation.
- External publisher-controlled dependencies.
- Artifact cardinality requirements.
- Disposable writable verification environments.
- Host-resource ownership and cleanup.
- Product-screen requirement coverage.
- Stopping a repeated strategy and replacing it with materially different work.

Each must become a typed contract with synthetic neutral fixtures.

## Test migration map

The active suite contains direct historical residue rather than isolated forensic fixtures:

- `GraphLoopTests.swift` contains 29 EasyBusiness/Community/US_R1 line matches and 15 game/Community matches, including exact failed node objectives and paths.
- `DesktopAutomationPreflightTests.swift` contains 19 Chrome/GPT-3.5/Selenium line matches.
- `LocalSupervisorTests.swift` contains 13 browser-incident matches and six game/wuxia requirement matches.
- `TaskStoreTests.swift`, `PromptCompilerTests.swift`, `PermissionCenterTests.swift`, `AuditorTests.swift`, and `EstimatorTests.swift` directly ratify the corresponding keyword branches.

Migration rule:

1. Move historical strings to the isolated forensic archive if they are still needed to reproduce this incident.
2. Replace active core tests with neutral identifiers such as `ProjectA`, `SurfaceAdapterA`, `ResourceProviderA`, `Requirement-17`, and `artifact.count`.
3. Add separate adapter contract suites for Chrome, Photos, iOS Simulator, and Codex provider authentication.
4. Run the historical incident corpus only as a compatibility/adversarial pack; it must not define core behavior.

## Required replacement abstractions

### `TaskContract`

- verbatim objective hash;
- immutable requirements and deliverables;
- product/design baseline references;
- allowed mutations;
- forbidden substitutions;
- external dependencies;
- acceptance authorities.

### `CapabilityRequest`

- typed capability identifier;
- required operations;
- requested scope;
- authority ceiling;
- resource semantics;
- expiry and cleanup obligations.

### `CapabilityAdapter`

- probe without mutation;
- explain missing prerequisites;
- acquire a scoped lease;
- execute or expose operations;
- return machine-verifiable receipts;
- release and prove quiescence.

### `EvidenceContract`

- requirement ID;
- revision/workspace/environment identity;
- collection method;
- artifact hashes;
- independent reviewer identity;
- supersession relationship;
- acceptance/veto result.

## Acceptance condition for the eventual refactor

The production tree must have no repository-, customer-, product-, screen-, industry-, content-, or incident-name branches in core scheduling, prompts, scoring, recovery, evidence, or reporting. Provider/tool names may exist only inside their typed adapter implementation or explicit provider UI. A mechanical scan is necessary, but final acceptance also requires proving that equivalent keyword heuristics were not merely renamed.
