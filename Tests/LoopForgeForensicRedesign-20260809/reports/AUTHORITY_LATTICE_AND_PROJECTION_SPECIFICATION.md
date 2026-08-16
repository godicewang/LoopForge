# Authority Lattice and Projection Specification

Status: pre-implementation normative design. The forensic gate remains closed; this document does not authorize production-source changes.

## Executive conclusion

LoopForge currently treats one large mutable model as contract, scheduler state, Agent memory, evidence, verdict, recovery checkpoint, and UI. `LoopTask` has 63 stored properties and `GraphLoopNode` has 39. Controllers, load-time migration, model-output parsers, audit code, integration code, and UI-facing orchestration all write overlapping subsets. The code can therefore express contradictory combinations that no authoritative transition ever accepted.

The redesign separates three concepts that the current `Full Access` label collapses:

1. **host reach:** what an adapter process can technically read, write, execute, or access on the Mac;
2. **task authority:** which declared targets and effects the immutable user contract permits;
3. **decision authority:** which kernel transition can accept a proposal or receipt.

Full host reach never grants task scope, contract amendment, evidence validity, independent approval, integration, remote publication, or completion authority. Model prose is always a proposal or observation. Only the journal reducer changes authoritative state.

## Current authority collisions

### One enum value carries several dimensions

`LoopTaskStatus` combines preparation, execution, audit, selection, pause/stop intent, blockers, failure, and terminal state. `WatcherStatus` similarly combines operational scheduling and user attention. Graph node status combines execution, review, integration, blocker, replacement, and terminal meaning. A write intended to preserve one dimension can erase another.

### Domain categories grant policy

`TaskCategory` contains vertical labels such as web, native app, mini program, game, desktop automation, experiment, data, optimization, and research. Those values currently select visual requirements, preferred control provider, parallel-mode rejection, evidence collection, workspace acceptance, and report behavior. This violates LoopForge's general-purpose contract: category names may be a non-authoritative display tag, but they cannot grant privilege or determine acceptance.

### A model selection doubles as an authority grant

`CodexAccessMode.fullAccess` is presented as unrestricted local tools/network and is used as the default in task setup. Yet plan nodes also carry free-form write scopes, read-only flags, workspace strategies, and prompts that attempt to constrain behavior. The OS sandbox ceiling and the orchestration authorization are not the same mechanism, so a Full Access worker can technically exceed the intended node contract.

### Derived fields are directly mutable

`status`, `stage`, accumulated time, audit score/summary, last messages, failure counts, visual flags, approval flags, completion time, resume flags, Graph phase, node status, strategy decisions, candidate selection, report metadata, and integration booleans are persisted as writable fields. A code path can set a conclusion without the receipts that would justify it.

## Authority principals

| Principal | May produce | May never directly do |
|---|---|---|
| user/operator | initial contract, explicit amendment, control command, external authorization | forge receipts or bypass safety/quiescence |
| contract compiler | typed proposal from user input, ambiguity diagnostics | silently change user intent or privileges |
| planning Agent | plan/replan/strategy proposals with rationale | authorize a node, grant capability, mutate workspace, approve itself |
| kernel/reducer | accept/reject commands, derive lifecycle state | execute processes or infer facts from prose |
| executor adapter | process, file, artifact, and effect receipts within a lease | expand scope, mark verification/review/completion |
| deterministic verifier | verifier receipt for exact requirement/revision/environment | mutate candidate, resolve a different failure identity |
| independent reviewer | read-only review receipt or veto over supplied evidence | share mutable workspace/session with author; integrate or publish |
| integration coordinator | atomic integration/rollback receipts for authorized candidate | invent acceptance or widen mutation manifest |
| resource supervisor | capability/process/power/quiescence receipts | treat elapsed time or cancellation request as cleanup success |
| recovery reconciler | observations bound to prior effect/resource identities | choose a favorable historical interpretation or resume mutation autonomously under ambiguity |
| projection builder | source-sequenced UI/report/index models | write authoritative lifecycle or contract state |

Agents may fill more than one *proposal* role in low-risk tasks, but conflicting authority roles remain process-enforced. In particular, an author/executor cannot become the independent reviewer for the same candidate revision.

## Authority grant model

Every accepted run has an immutable `AuthorityManifest`:

```swift
struct AuthorityManifest: Codable, Sendable {
    let contractID: ContractID
    let targetRoots: [PathGrant]
    let mutationGrants: [MutationGrant]
    let commandGrants: [CommandGrant]
    let networkGrants: [NetworkGrant]
    let externalResourceGrants: [CapabilityGrant]
    let remoteSideEffectGrants: [RemoteEffectGrant]
    let credentialGrants: [CredentialGrant]
    let expiresAt: Date?
}
```

Rules:

- default is no mutation, no credential, no remote side effect, and no external resource;
- paths are canonical, symlink-resolved, inode/device-bound where needed, and revision-bound;
- grants include operation, identity, quantity/concurrency budget, duration, and revocation behavior;
- undeclared and ambiguous access is rejected, never mapped to the current directory or broad home directory;
- prompts receive a human-readable projection of the manifest, while the executor enforces the machine form;
- user authority can narrow at any time; widening requires an explicit amendment transaction;
- no task category, filename, keyword, model choice, quality tier, or Agent recommendation grants authority.

## Command admissibility matrix

| Command family | Proposer | Required authority/receipt | Reducer acceptance condition |
|---|---|---|---|
| create contract | user via compiler | exact user confirmation | schema valid; ambiguities resolved or explicitly retained as blockers |
| amend contract | user or predelegated bounded policy | amendment grant and diff | no retroactive laundering; version increments |
| propose plan | planner | read-only context lease | every node maps to requirement and declared budget |
| accept plan | kernel policy | deterministic plan validation | DAG, scopes, capabilities, independence, and budgets valid |
| authorize attempt | scheduler | accepted node plus leases | dependencies and environment revision current |
| record output | executor adapter | process/stream receipt | identity, sequence, revision, and truncation metadata valid |
| record progress | evaluator | progress receipt | causal novelty and requirement mapping valid |
| retire/replace strategy | planner proposes; kernel accepts | exhausted/stagnant signature and lesson | replacement is typed non-equivalent and within budget |
| record verification | verifier | exact command/environment/artifact receipt | verifier identity and rerun equivalence valid |
| record review | independent reviewer | read-only evidence lease | independence and evidence completeness valid |
| propose mutation | executor/planner | candidate tree and manifest | changes confined to authorized candidate scope |
| integrate mutation | coordinator | verification, review, baseline, rollback authorization | all gates current and exact postimage provable |
| acquire/release capability | resource supervisor | manifest grant | ownership, quantity, lifecycle, and reconciliation defined |
| publish remote effect | coordinator | explicit remote grant | local final gates pass; idempotency and rollback policy known |
| pause/stop | user or controlling automation | run-control authority | intent accepted immediately; terminal state waits for quiescence |
| complete run | kernel only | complete receipt set | every required conjunction passes at same revision/sequence |

## Non-waivable deny rules

1. Worker prose cannot set lifecycle, progress, blocker, review, verification, integration, or completion state.
2. A parser failure never falls back to “approve,” “continue,” current directory, full access, or empty scope.
3. Missing/expired/stale evidence never contributes partial aggregate credit.
4. A later unrelated green command cannot resolve an earlier verifier failure.
5. Read-only review cannot share a mutable worktree, thread, credentials, or unreviewed artifact cache with the author.
6. Isolation preparation failure rejects the attempt; it cannot downgrade to the canonical workspace.
7. Cancellation is an intent/interrupt request, not a terminal fact.
8. `blocked`, `failed`, `outcomeUnknown`, and `cleanupFailed` cannot be converted to ordinary approval by a score or prose marker.
9. A strategy replacement must differ in typed hypothesis, method, scope, or dependency—not wording alone.
10. Any contract, baseline, authority, revision, environment, or evidence mismatch invalidates dependent receipts.
11. No vertical product/task category appears in core scheduling, evidence, scoring, recovery, or acceptance policy.
12. Side effects outside the target workspace require explicit typed grants even when the process sandbox is Full Access.

## Field-level migration: `LoopTask`

The 63 legacy stored properties move into the following owners.

### Immutable contract/import claims

| Legacy fields | Target representation |
|---|---|
| `id`, `createdAt` | `RunIdentity` from `runCreated` |
| `request`, `originalRequest` | verbatim requirement source artifact plus immutable `TaskContract` |
| `workspacePath` | canonical `TargetRoot` with baseline identity |
| `targetSeconds` | explicit eligible-work constraint; never a completion score |
| `quality` | optional user preference translated into declared budgets/gates, not implicit policy |
| `executionMode` | scheduler topology preference, subject to contract validation |
| `controlAgent`, `subAgent`, `officialModel`, `officialReasoningEffort`, `model` | immutable/explicitly amended role assignments and provider capabilities |
| `codexAccessMode` | legacy host-reach ceiling; replaced by authority manifest plus executor sandbox profile |
| `parallelCandidateCount`, `parallelSelectionMode` | accepted scheduler/candidate policy |
| `category` | deprecated as authority; optional display-only legacy tag |
| `promptOptimizationSource`, `refinedRequest`, `missionRewriteAuditSummary`, `missionRewriteAttempts` | proposal lineage; cannot replace verbatim intent without contract amendment |

### Reducer-derived lifecycle and time projection

| Legacy fields | Target derivation |
|---|---|
| `status`, `stage` | `RunPhase` and diagnostics from journal state |
| `iteration`, `controlInteractionCount` | accepted attempt/review event counts |
| `accumulatedCodexSeconds` | eligible time-ledger interval union |
| `resumeOnNextLaunch`, `checkpointedAt` | recovery eligibility and last durable sequence projection |
| `updatedAt`, `completedAt` | last accepted transaction / completion authorization timestamps |
| `consecutiveFailures` | causal failure-signature counters, not a mutable integer |
| `agentWaitState`, `lastSubAgentHeartbeatAt`, `lastLoopInterventionAt` | process/session/timer receipts and derived liveness |
| `externalBlockerKind`, `externalBlockerMessage`, `externalBlockerRetryAfter` | typed blocker receipt and eligibility policy |

### Evidence, verification, review, and completion

| Legacy fields | Target representation |
|---|---|
| `logs`, `lastAgentMessage` | immutable output artifacts/events; never facts by themselves |
| `auditScore` | remove as completion authority; optional diagnostic projection only |
| `auditSummary`, `lastSupervisorReview` | review/evaluation text attached to typed receipts |
| `supervisorCompletionApproved` | remove; completion is a reducer conjunction |
| `visualAuditRequired` | explicit acceptance requirement, not category inference |
| `visualAuditPassed`, `visualAuditSummary`, `visualEvidencePaths` | revision/environment/baseline-bound visual receipts |
| `lastEvidenceCoverage`, `lastControlGapKeys` | derived requirement/evidence index with exact missing IDs |

### Integration, selection, and reporting projection

| Legacy fields | Target representation |
|---|---|
| `graphState` | projection of accepted plan/node/attempt/strategy/integration events |
| `selectedCandidateID`, `parallelSelectionSummary`, `parallelWinnerIntegrated` | candidate decision and integration receipts |
| `completionReportPath`, `reportBaseline`, `reportGeneratedAt`, `reportGenerationProvider` | disposable report projection bound to journal sequence and artifact hash |
| `title`, `shortTitle`, `taskNamingCompleted`, `taskNamingVersion` | display projection; never execution policy |
| `completionViewedAt` | local UI preference outside authoritative run state |

## Field-level migration: `GraphLoopNode`

The 39 legacy node properties become:

| Ownership | Legacy fields |
|---|---|
| accepted node contract | `id`, `title`, `objective`, `dependencies`, `writeScopes`, `verification`, `readOnly`, `joinGroupID`, `createdAt` |
| workspace/capability authorization | `workspacePath`, `isolationRootPath`, `workspaceStrategy`, `integrationBaseCommit` |
| attempt/session receipts | `iteration`, `threadID`, `currentInstruction`, `lastAgentMessage`, `logs`, `iterationHistory` |
| time ledger | `accumulatedActiveSeconds`, `accumulatedBlockedSeconds`, `activeStartedAt`, `blockedAt` |
| reducer projection | `status`, `consecutiveFailures`, `completedAt`, `incrementalReviewFailures`, `automaticRetryDisabled`, `strategyEscalationRequired` |
| review/strategy events | `lastReview`, `strategyLesson`, `strategyDecision`, `replacementPlanStartedFreshThread`, `replacementPlanContractVersion` |
| replan lineage | `supersededAt`, `supersededReason`, `supersededByNodeIDs`, `replacesNodeIDs`, `planAdjustment` |

No field in the last five rows remains directly writable by a controller. The reducer derives projections from receipts and decisions.

## Orthogonal run projection

Replace the overloaded task/node status enums with orthogonal dimensions:

```swift
struct RunProjection {
    let phase: RunPhase
    let execution: ExecutionProjection
    let userAttention: AttentionProjection
    let durability: DurabilityProjection
    let resources: ResourceProjection
    let authority: AuthorityProjection
    let progress: ProgressProjection
    let currentIteration: IterationTimeProjection
    let cumulativeRuntime: RuntimeProjection
    let sourceSequence: UInt64
    let sourceStateHash: Digest
}
```

`RunPhase` follows the kernel lifecycle (`draft`, `ready`, `planning`, `executing`, `verifying`, `reviewing`, `integrating`, `pauseRequested`, `stopRequested`, `draining`, `cleanupBlocked`, `paused`, `stopped`, `completionPending`, `completed`). User attention can be present while deterministic Watcher scheduling remains active. Durability can be degraded while execution is forced to stop accepting new side effects. Resource cleanup can be draining while the run is no longer executing Agents.

Node cards show both cumulative eligible runtime over all iterations and the live current-iteration runtime, sourced from the time ledger—not mutually overwriting counters. This preserves the user's requested observability without making time sufficient for approval.

## Manual control and preemption

Priority is deterministic:

```text
emergency safety revoke
  > stop request
  > pause request
  > contract authority narrowing
  > recovery reconciliation
  > scheduled execution/review
```

Acceptance of a higher-priority command fences new lower-priority effects at the next journal sequence. In-flight effects enter cancel/drain/reconcile; they cannot write a late `running`, `approved`, or `completed` projection over the intent. Stop and pause become terminal only after the resource supervisor emits a valid quiescence receipt.

## Completion authority

Completion is one reducer command whose preconditions are all exact and current:

- every mandatory contract requirement has accepted evidence;
- every required verifier has a successful, unresolved receipt for the same artifact/revision/environment;
- required visual baselines and captures pass independent gates;
- independent review is valid and unexpired;
- no causal blocker, unknown effect, pending mutation, or cleanup failure remains;
- integrated target postimage matches the accepted candidate and immutable baseline transaction;
- remote publication, if required and authorized, has its receipt;
- active-time minimums are met, but time alone grants no quality credit;
- all tasks/processes/resources/assertions are quiescent;
- journal and UI/report projection sequences match.

The reducer records either `completionAuthorized` or a typed rejection listing exact missing receipt IDs. No score threshold or final text marker participates.

## Required deterministic authority tests

1. Full Access worker tries an undeclared target path.
2. Display category changes while authority and acceptance remain identical.
3. Planner attempts to self-authorize a node.
4. Author and reviewer share a session/worktree and independence validation rejects it.
5. UI writes a terminal-looking projection without a journal event.
6. Recovery code attempts to convert unknown cleanup into stopped.
7. Pause races a late worker completion.
8. Stop races review and integration.
9. Contract narrowing revokes an in-flight capability.
10. Contract widening without explicit amendment is rejected.
11. Isolation failure attempts canonical fallback.
12. Stale evidence from a prior revision attempts approval.
13. Unrelated green verification tries to clear a failure.
14. Blocked prose plus approval marker cannot complete.
15. Strategy paraphrase fails non-equivalence validation.
16. Reviewer tries to mutate candidate.
17. Resource supervisor reports elapsed grace without identities.
18. Legacy `completed` imports without receipts as untrusted history.
19. Watcher attention changes without changing scheduler eligibility.
20. Node cumulative and current-iteration clocks update independently.
21. Projection with stale source sequence is visibly stale and cannot issue mutation-dependent commands.
22. Remote push without explicit remote grant is rejected.
23. Every deprecated direct field setter is unavailable across the production module boundary.
24. Equivalent domain-neutral tasks receive identical authority behavior regardless of vocabulary or file names.

## Implementation boundary after the forensic gate

1. Introduce authority identities, manifests, commands, and pure validation in a new kernel package.
2. Wrap current controller entry points in typed commands while preserving behavior for characterization.
3. Generate a read-only legacy projection from journal state and compare every field transition.
4. Move one lifecycle dimension at a time behind reducer-only writes.
5. Enforce executor manifests and reviewer read-only isolation before allowing new Graph mutations.
6. Replace category/keyword policy with explicit contract requirements and adapter capabilities.
7. Remove writable legacy verdict/status fields after parity and fault tests pass.
8. Switch SwiftUI and HTML to source-sequenced projections.

This authority boundary is necessary for autonomy: a highly autonomous scheduler must be free to propose and execute many strategies while being mechanically unable to expand its own authority or certify its own result.

