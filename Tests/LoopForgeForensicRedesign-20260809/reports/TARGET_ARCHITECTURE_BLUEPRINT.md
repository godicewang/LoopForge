# LoopForge Target Architecture Blueprint

Status: design specification only; no production implementation is authorized before the forensic gate.

## Design objective

LoopForge should be a general-purpose autonomous orchestration kernel whose state can be replayed, whose authority is explicitly leased, whose mutations are transactional, whose evidence is independently attributable, whose strategies provably converge or retire, and whose terminal state includes resource quiescence.

The current `LoopTask` + `GraphLoopState` + mutable-node snapshots should become a compatibility view over a smaller set of authoritative primitives.

## 1. Identity and immutable task contract

Every run begins by freezing a contract before any mutating Agent turn.

```swift
struct TaskContract: Codable, Sendable {
    let id: TaskContractID
    let schemaVersion: Int
    let verbatimObjective: String
    let objectiveDigest: Digest
    let requirements: [RequirementContract]
    let deliverables: [DeliverableContract]
    let protectedBaselines: [BaselineReference]
    let forbiddenSubstitutions: [SubstitutionConstraint]
    let authorityCeiling: AuthoritySet
    let externalDependencies: [ExternalDependencyContract]
    let acceptancePolicy: AcceptancePolicy
    let createdAt: Date
}
```

Properties:

- requirement IDs are stable and provider-neutral;
- every node declares which requirement IDs it advances;
- product/design baselines are immutable artifact hashes;
- a contract amendment is a new event requiring explicit authority and a rationale;
- model-generated refinement can propose a contract, but cannot silently replace verbatim intent;
- no task category or keyword classifier may grant tools, privilege, or acceptance.

## 2. Append-only orchestration journal and pure reducer

### Authoritative write path

Only `RunJournal` appends state-changing events. Views, controllers, Agents, adapters, and timers submit commands; they never mutate snapshots directly.

```swift
actor RunJournal {
    func transact(_ command: RunCommand) async throws -> TransactionReceipt
    func events(after sequence: EventSequence) async throws -> [OrchestrationEvent]
    func snapshot() async throws -> RunState
}

enum RunCommand: Sendable {
    case createRun(TaskContract)
    case proposePlan(PlanProposal)
    case authorizeNode(NodeAuthorization)
    case startAttempt(AttemptStart)
    case recordAgentOutput(AgentOutputReceipt)
    case recordVerification(VerificationReceipt)
    case recordReview(ReviewReceipt)
    case retireStrategy(StrategyRetirement)
    case proposeMutation(MutationProposal)
    case integrateMutation(IntegrationAuthorization)
    case acquireCapability(CapabilityRequest)
    case releaseCapability(CapabilityLeaseID)
    case requestPause(ControlRequest)
    case requestStop(ControlRequest)
    case completeRun(CompletionAuthorization)
}
```

`RunReducer.reduce(state:event:)` is pure and total. Every command is validated against the current state and emits either a typed event batch or a typed rejection. Invalid combinations are not repairable by flag precedence because they cannot be appended.

### Minimum event families

- contract created/amended;
- plan proposed/accepted/rejected;
- node declared/authorized/started/interrupted;
- attempt output classified;
- verification requested/completed/invalidated;
- review requested/completed/vetoed;
- strategy progress observed/retired/replaced;
- capability requested/acquired/released/release-failed;
- mutation proposed/verified/approved/applied/rolled-back;
- timer eligibility changed;
- pause/stop requested/acknowledged;
- resource quiescence verified;
- run completion authorized.

### Persistence format

Use a LoopForge-owned run directory, not the target repository:

```text
Application Support/LoopForge/runs/<run-id>/
  contract.json
  journal/00000001.event ...
  snapshots/<sequence>.json
  artifacts/<digest>
  receipts/<receipt-id>.json
```

Each event is individually atomic, sequence-numbered, hash-chained, and checksummed. Snapshots are caches and can be deleted/rebuilt. The journal is the source of truth. UI publication is a projection, never persistence itself.

## 3. Typed plan and node contract

```swift
struct NodeContract: Codable, Sendable {
    let id: NodeID
    let requirementIDs: Set<RequirementID>
    let objective: String
    let dependencies: Set<NodeID>
    let mutationScope: MutationScope
    let capabilityRequests: [CapabilityRequest]
    let verificationPlan: [VerificationRequirement]
    let evidencePlan: [EvidenceRequirement]
    let mutationBudget: MutationBudget
    let strategyFingerprint: StrategyFingerprint
    let risk: RiskAssessment
}
```

Rules:

- read-only is an empty mutation scope enforced by the executor;
- missing/invalid scope rejects authorization; it never becomes `.`;
- capability requests are typed; prose cannot discover authority;
- dependency completion requires accepted integration and unexpired evidence receipts;
- plan additions can address newly observed gaps but must map to original requirement IDs or an explicitly authorized amendment;
- UI/design mutations are high-risk and require protected-baseline comparison before integration.

## 4. Capability registry and least-privilege leases

```swift
protocol CapabilityAdapter: Sendable {
    var descriptor: CapabilityDescriptor { get }
    func probe(_ request: CapabilityRequest) async -> CapabilityProbeReceipt
    func acquire(_ request: CapabilityRequest, owner: ResourceOwner) async throws -> CapabilityLease
    func release(_ lease: CapabilityLease) async -> CapabilityReleaseReceipt
}
```

Core-visible descriptor fields:

- stable capability ID and adapter version;
- operations;
- authority requirements;
- exclusive/shared resource semantics;
- supported evidence receipts;
- acquisition, expiry, renewal, and cleanup behavior.

Concrete Chrome, Photos, iOS Simulator, Codex, local-model, API, and browser adapters live behind this interface. Their menu names, commands, and domain vocabulary never appear in core plan/review prompts.

Authority rules:

- planner/reviewer/reporter default to read-only;
- workers receive only declared workspace paths and leased capabilities;
- Full Access is not a default mode; it is an explicit exceptional lease with a reason and expiry;
- environment construction starts empty and adds an allowlist;
- an isolation failure rejects the node; it cannot fall back to the canonical workspace;
- a pure probe cannot create Git metadata, start durable processes, or alter permissions.

## 5. Transactional mutation and integration

```swift
struct MutationTransaction: Codable, Sendable {
    let id: MutationTransactionID
    let baseline: WorkspaceBaselineReceipt
    let proposedPaths: Set<RepositoryPath>
    let actualPatchDigest: Digest
    let mutationBudget: MutationBudget
    let verificationReceiptIDs: Set<ReceiptID>
    let reviewReceiptIDs: Set<ReceiptID>
    let rollbackPlan: RollbackPlan
    let publicationPolicy: PublicationPolicy
}
```

Lifecycle:

1. capture baseline identity, including user-owned dirty paths;
2. create LoopForge-owned isolation without mutating the target;
3. execute within enforced scopes;
4. derive actual mutation manifest and compare against authorization/budget;
5. verify against the exact candidate revision/environment;
6. obtain required independent reviews and visual vetoes;
7. apply atomically to the expected baseline;
8. verify the postimage;
9. retain rollback receipt;
10. publish/commit/push only through a separate explicit authorization.

No generic conflict Agent may turn process exit zero into integration success. It must return a candidate patch plus receipts, which re-enter the same transaction gates.

## 6. Evidence graph and independent review

```swift
struct EvidenceArtifact: Codable, Sendable {
    let id: EvidenceID
    let requirementID: RequirementID
    let sourceRevision: RevisionIdentity
    let workspaceIdentity: WorkspaceIdentity
    let environment: EnvironmentReceipt
    let collector: ActorIdentity
    let artifactDigest: Digest
    let mediaType: String
    let capturedAt: Date
}

struct ReviewReceipt: Codable, Sendable {
    let id: ReviewReceiptID
    let role: ReviewRole
    let reviewer: ActorIdentity
    let independence: IndependenceClass
    let reviewedEvidenceDigests: [Digest]
    let reviewedContractDigest: Digest
    let decision: ReviewDecision
    let findings: [TypedFinding]
    let rawOutputDigest: Digest
    let createdAt: Date
}
```

Independence is a property, not the word “independent”:

- implementer and reviewer identities differ;
- reviewer context excludes worker conclusions unless explicitly presented as untrusted claims;
- reviewer receives complete evidence, attachment manifest, and order;
- provider/model/context lineage is retained;
- deterministic gates cannot be waived by a model;
- external dependencies require typed evidence and cannot be invented by loose keyword matching;
- review receipts expire when contract, revision, baseline, or environment changes.

Reports read only accepted receipts. Agent narrative is displayed as narrative, never as fact.

## 7. Causal convergence governor

```swift
struct StrategyFingerprint: Codable, Hashable, Sendable {
    let requirementIDs: Set<RequirementID>
    let actionClass: ActionClass
    let targetScopeClass: ScopeClass
    let capabilityIDs: Set<CapabilityID>
    let environmentClass: EnvironmentClass
    let expectedEvidenceClasses: Set<EvidenceClass>
    let mutationClass: MutationClass
}

struct ProgressVector: Codable, Sendable {
    let newlyClosedRequirements: Set<RequirementID>
    let newEvidenceDigests: Set<Digest>
    let verificationDelta: VerificationDelta
    let baselineRegressionDelta: RegressionDelta
    let mutationCost: MutationCost
    let operationalCost: OperationalCost
    let remainingGapDigest: Digest
}
```

Policy:

- every attempt emits a progress vector;
- equivalent fingerprints share one durable budget across nodes, prompts, models, restarts, and renames;
- no-progress attempts do not count as productive time;
- repeated equivalent failure retires the strategy before another worker launch;
- high-risk mutation strategies have lower attempt and damage ceilings than read-only investigation;
- replacement requires a materially different fingerprint and explains the inherited lesson;
- valid decisions are `continue`, `split`, `replace`, `reframe`, `satisfyElsewhere`, `acceptExternalDependency`, or `abandonRequirement` (the last requires owner authority);
- final repair is not special: it obeys the same scope, mutation, evidence, and convergence rules.

## 8. Operational lifecycle and thermal governor

### Resource ledger

Every process, app session, device, model residency, listener, worktree, timer, broker, and wake assertion has:

- durable task/node/attempt owner;
- provider identity;
- acquired durable identity (not only launcher PID);
- borrowed/owned semantics;
- lease state and expiry;
- exact cleanup operation;
- release receipt;
- recovery policy.

### Governor inputs

- process count and owned CPU;
- system thermal state;
- active heavy adapters;
- persistence write rate/bytes;
- evidence decoding/OCR work;
- scheduled cadence and pending wake reasons;
- battery/power source where available.

### Hard invariants

- one cadence governor coalesces scheduled, anomaly, failure, and post-review triggers;
- review cannot schedule an immediate pass inside the minimum quiet period unless a typed critical policy allows it;
- polling adapters must expose event-driven or backed-off behavior;
- checkpoints journal dirty fields and flush on state boundaries, not every five seconds;
- stop/quit completes only after owned resources are released or a durable `releaseFailed` state is visible;
- background continuation is explicit and visible; closing the last window cannot make workers invisible;
- terminal completion requires a machine-readable quiescence receipt.

## 9. Visual/design acceptance subsystem

`VisualBaselineManifest` records:

- product version/revision;
- required screen/state IDs;
- device/window, OS, scale, locale, appearance, content-size category;
- image and geometry artifact hashes;
- typography tokens;
- shape tokens;
- spacing/grid tokens;
- initial-viewport requirements;
- approved waivers and owner.

Candidate checks are independent dimensions:

1. capture provenance;
2. state coverage and uniqueness;
3. semantic accessibility;
4. clipping/collision/occlusion/hit targets;
5. typography hierarchy and locale expansion;
6. shape and spacing relationships;
7. initial-viewport task usefulness;
8. baseline preservation or authorized migration;
9. independent aesthetic/product veto.

One green dimension cannot clear another red dimension. A screenshot Boolean cannot represent visual acceptance.

## 10. Watcher as a trigger source, not a second autonomous truth system

Continuum Watcher should emit typed observations into the same journal:

```swift
enum WatcherObservation {
    case scheduledPass(PipelineReceipt)
    case anomaly(AnomalyReceipt)
    case checkpointAdvanced(CheckpointReceipt)
    case pipelineFailure(FailureReceipt)
    case completionCandidate(CompletionEvidence)
}
```

The Watcher Agent may propose instrumentation or a repair transaction, but cannot repair, assess, and approve itself. Its pipeline runs in an enforced sandbox with declared generated paths and a capability allowlist. Completion requires deterministic pipeline state plus requirement closure plus independent review.

## 11. UI projection

The native UI consumes `RunProjection`, derived from journal state:

- accepted active total;
- current eligible live interval;
- excluded blocked/rejected/failed time;
- current strategy fingerprint and attempt budget;
- requirement closure;
- mutation scope/budget and actual delta;
- evidence and review provenance;
- capability/resource leases;
- convergence status and retired lessons;
- cleanup/quiescence status.

The UI cannot display “verified,” “safe,” “independent,” “complete,” or a 100 score unless the corresponding typed receipts exist. Execution mode and privilege are explicit controls, never invisible gestures.

## 12. Legacy migration

Existing `tasks.json` and `watchers.json` are imported read-only into a `LegacyRunImported` event with original bytes hashed. Ambiguous states are labeled `untrustedLegacyState`; they are never silently upgraded to approved receipts. Historical completed Graph nodes with blocked summaries remain contradictory evidence, not valid completion.

The migration must never mutate an external workspace at app launch.

## Implementation slices after authorization

1. Journal/reducer library and replay/property tests.
2. Task contract, authority types, and legacy importer.
3. Process/resource ledger plus synchronous quiescence barrier.
4. Mutation transaction/coordinator with fail-closed isolation.
5. Evidence graph and strict review transport.
6. Convergence governor and permanent strategy retirement.
7. Visual baseline/design gates.
8. Watcher trigger integration and cadence governor.
9. Truthful projections and unified design-token UI.
10. Adapter migration and deletion of core vertical branches.
11. Deterministic end-to-end engine replay, packaging, and native verification.

Each slice must leave the characterization suite runnable while adding adversarial acceptance tests for the new contract. No slice may rely on another prompt warning as its enforcement mechanism.
