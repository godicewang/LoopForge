# Causal Convergence and Strategy Portfolio Specification

Status: pre-implementation normative design. This document does not authorize production refactoring before the 36,000-second forensic gate.

## Executive conclusion

The seven-turn failure was not “insufficient persistence.” It was persistence applied to an unchanged causal strategy. In the stopped run, 37 of 51 worker iterations explicitly reported `BLOCKED`; 28 were continued and 7 were approved. The controller changed wording, thread, or local instruction while the failed predicate, workspace topology, unavailable evidence source, or measurement boundary stayed the same.

The current dirty repair improves safety by freezing after three blocked turns and requiring a strategy review after six unapproved decisions. It still defines “materially different” by punctuation-stripped string inequality. A paraphrase resets practical novelty. Single Loop similarly resets its stagnation counter after changing models/threads, while the scalar audit objective can remain causally unchanged.

The replacement convergence mechanism is typed and finite:

- every attempt belongs to a structured strategy fingerprint;
- every failed predicate produces a causal failure fingerprint;
- progress is a requirement/receipt/risk vector, not a scalar score or new prose;
- retry budgets depend on failure class, damage, cost, and evidence novelty;
- exhausted strategies are retired permanently and leave structured negative knowledge;
- replacements must change a causally relevant axis;
- the total run budget cannot be recreated by replan, rename, new thread, or restart;
- no valid alternative yields an explicit safe terminal result rather than another worker turn.

## Typed worker and review outcomes

```swift
enum ExecutionOutcome {
    case completed(OutputReceipt)
    case continuationNeeded(ProgressReceipt)
    case blocked(BlockerReceipt)
    case failed(FailureReceipt)
    case interrupted(InterruptionReceipt)
    case malformed(ProtocolFailureReceipt)
}

enum ReviewOutcome {
    case accepted(ReviewReceipt)
    case rejected(ReviewReceipt)
    case topologyChangeRequired(TopologyChangeProposal)
    case strategyRetirementRequired(RetirementProposal)
    case externalBoundaryAccepted(BoundaryReceipt)
    case evidenceUnavailable(UnavailabilityReceipt)
}
```

Invalid combinations are reducer rejections:

- `blocked + accepted`;
- `failed + accepted`;
- `malformed + continue worker` before repairing/retrying the reviewer/protocol;
- `interrupted + completed`;
- `evidenceUnavailable + ordinary retry` without a new evidence source receipt;
- `topologyChangeRequired + same immutable workspace attempt`.

Process exit code zero means transport completion only. Text markers and substring parsing cannot select these enums.

## `StrategyFingerprint`

```swift
struct StrategyFingerprint: Codable, Hashable, Sendable {
    let requirementIDs: SortedSet<RequirementID>
    let hypothesisClass: TypedDescriptor
    let actionClass: TypedDescriptor
    let workspaceTopology: WorkspaceTopologyIdentity
    let capabilityRoute: SortedSet<CapabilityDescriptor>
    let evidenceSources: SortedSet<EvidenceSourceIdentity>
    let measurementBoundary: MeasurementBoundary
    let verificationOracles: SortedSet<VerifierIdentity>
    let mutationSurface: MutationManifest
    let baselineRevision: RevisionIdentity
    let expectedObservations: [ExpectedObservation]
    let falsificationPredicates: [PredicateID]
    let inheritedLessons: SortedSet<LessonID>
}
```

The canonical fingerprint hash excludes title, natural-language objective wording, node ID, thread ID, and model prose. Those are lineage/display data, not strategy identity.

Two strategies are equivalent when all causally relevant axes are equal after typed normalization. An optional semantic model may flag likely equivalence for review, but it cannot certify difference. Difference requires a machine-checkable `StrategyDelta` on at least one axis relevant to the prior failure.

## `FailureFingerprint`

```swift
struct FailureFingerprint: Codable, Hashable, Sendable {
    let predicateID: PredicateID
    let outcomeClass: FailureClass
    let structuredErrorCode: String?
    let workspaceAndRevision: WorkspaceRevisionIdentity
    let capabilityOrResource: ExternalResourceIdentity?
    let verifierOrMeasurement: VerifierIdentity?
    let immutableConstraint: ConstraintIdentity?
    let evidenceDigest: Digest
    let externalConditionVersion: String?
}
```

Failure classes are general-purpose:

- structural authority/scope/topology mismatch;
- deterministic implementation failure;
- invariant or baseline regression;
- evidence unavailable/nonexistent;
- external/transient service or rate limit;
- reviewer/protocol/transport failure;
- resource/thermal/capacity failure;
- integration conflict/stale revision;
- unknown outcome requiring reconciliation.

Changing punctuation, explanation, model, node title, or fresh thread does not change the failure fingerprint. A mutable external condition changes only when a trusted observation records a new version/value.

## Progress vector

LoopForge must not reduce convergence to `auditScore` or “number of files/tests.” The reducer maintains:

```swift
struct ProgressVector {
    let mandatoryRequirementsAccepted: Set<RequirementID>
    let mandatoryRequirementsUnresolved: Set<RequirementID>
    let blockers: Set<FailureFingerprint>
    let acceptedEvidence: Set<EvidenceReceiptID>
    let unresolvedVerifierFailures: Set<VerifierFailureID>
    let acceptedQualityDimensions: Set<QualityDimensionID>
    let integrationState: IntegrationProgress
    let uncertaintyClaims: Set<UnresolvedClaimID>
    let mutationCost: MutationCost
    let damageRegressions: Set<InvariantID>
}
```

An attempt makes accepted progress only when at least one of these occurs at the same or newer valid revision:

- a mandatory requirement receives a new accepted receipt;
- an existing causal blocker is resolved by a typed condition change;
- a verifier failure is resolved by a causally equivalent successful rerun;
- a required quality dimension passes without regressing another protected invariant;
- uncertainty is reduced by new authoritative evidence;
- an accepted candidate moves through verified integration/rollback-safe state.

And none of these regress:

- protected invariant or accepted mandatory requirement;
- unresolved critical failure/damage count;
- authority/baseline/revision validity;
- integration/rollback safety.

New prose, another command, a new test file, time spent, fresh thread, higher aggregate score, or repeated evidence at the same digest is not progress.

The comparator is a partial order with hard veto dimensions. It does not allow ten low-value positives to compensate for one product hierarchy regression.

## Attempt admission

Before a worker starts, the scheduler requires an `AttemptAdmissionReceipt` proving:

1. accepted node/requirement contract;
2. current strategy and failure fingerprints;
3. predicted observation and falsification boundary;
4. material novelty versus every retired/active strategy in scope;
5. remaining requirement, strategy, mutation, verification, time, cost, and damage budgets;
6. workspace/resource/authority leases;
7. rollback point for mutations;
8. evidence and verifier identities;
9. no higher-priority pause/stop/narrowing command;
10. host budget availability.

An attempt without a falsifiable prediction is a planning defect and cannot consume a worker turn.

## Failure-class retry policy

| Failure class | Automatic worker retry | Required next action |
|---|---:|---|
| immutable authority/scope/cwd/topology mismatch | 0 after first confirmed fingerprint | graph-level authority/topology change or retire |
| evidence proven unavailable/nonexistent | 0 until new source/version receipt | accept boundary, request data, or propose genuinely new source |
| visual/product invariant regression | 0 on damaging candidate | rollback/quarantine, retire strategy, independent replan |
| deterministic verifier failure | at most 2 causally distinct repairs | each changes hypothesis/mutation and reruns same oracle |
| transient external service/rate limit | no mutation retry; bounded scheduled retry | exponential backoff, new external-condition observation |
| reviewer/decoder/transport failure | retry reviewer/protocol only | never relaunch worker for reviewer failure |
| resource/thermal capacity | no strategy retry | wait/throttle without eligible-time credit; resume on new host-state event |
| integration conflict/stale revision | one coordinator reconciliation | new baseline/manifest; otherwise retire/replan |
| outcome unknown | 0 blind retries | reconcile exact external identity before decision |

The generic ceiling of three equivalent blocked/rejected observations remains a final safety bound for classes not more strictly handled. The third includes the first occurrence. High-cost or damaging attempts can exhaust a strategy sooner.

## Durable multidimensional budgets

Each contract allocates finite budgets:

```swift
struct ConvergenceBudget {
    let maximumAttempts: UInt32
    let maximumEquivalentFailures: UInt16
    let maximumStrategies: UInt16
    let maximumPlanExpansions: UInt16
    let maximumMutationCost: MutationCost
    let maximumVerificationCost: CostVector
    let maximumDamageEvents: UInt16
    let maximumEligibleRuntime: Duration?
    let maximumExternalEffects: UInt16
}
```

Budget rules:

- every admitted attempt consumes a durable attempt token at start;
- a plan expansion transfers remaining budget; it cannot mint new budget;
- replace/split/reframe share the predecessor requirement budget unless an explicit contract amendment adds resources;
- pause, quit, crash, relaunch, model change, provider change, thread reset, and node rename never reset budgets;
- blocked/failed/idle/thermal wait time is recorded but excluded from accepted active-work time;
- a destructive or protected-invariant regression consumes the damage budget immediately and can force task-wide mutation freeze;
- explicit user amendment can add budget with reason, risk, and new acceptance terms.

## Strategy retirement

`StrategyRetired` is immutable and contains:

- strategy fingerprint/hash and owned requirement IDs;
- all causal failure fingerprints;
- final progress vector and cost/mutation/damage totals;
- structured `StrategyLesson`;
- retained candidate/artifact/workspace identities;
- rollback/quarantine result;
- coverage disposition per owned requirement;
- retirement reason and authority receipt.

The structured lesson records:

```swift
struct StrategyLesson {
    let falsifiedAssumptions: [AssumptionID]
    let invalidRoutes: [CausalAxisValue]
    let evidenceThatWouldPermitReconsideration: [ConditionPredicate]
    let reusableArtifacts: [ArtifactReceiptID]
    let prohibitedInheritance: [ArtifactOrStateIdentity]
}
```

Retired strategies never become runnable again. A future strategy may reuse explicitly accepted immutable artifacts, but it cannot inherit the stale mutable thread/worktree/reviewer framing by default.

## Replacement actions

The coordinator chooses one typed terminal/replacement action:

- `abandon`: requirement is proven irrelevant only through explicit contract amendment;
- `acceptExternalBoundary`: requirement remains unsatisfied but a user/external-authority boundary is recorded;
- `requestAuthorityOrData`: pause until a named condition changes;
- `reframe`: same requirement, different hypothesis/action/measurement route;
- `split`: separable requirements/uncertainties become independently falsifiable nodes;
- `substituteDependency`: replace an unavailable source/capability with an authorized alternative;
- `replace`: a new end-to-end strategy with a material causal delta;
- `declareInfeasible`: preserve evidence and safely stop when no authorized viable strategy exists.

No action is forced to create a replacement. “No genuinely different safe strategy exists” is a successful convergence outcome into a visible blocked/infeasible terminal state, not a failure that restarts the loop.

## `StrategyDelta` validation

```swift
struct StrategyDelta {
    let changedAxes: [CausalAxisChange]
    let addressedFailureFingerprints: Set<FailureFingerprint>
    let newPredictedObservations: [ExpectedObservation]
    let inheritedLessonIDs: Set<LessonID>
    let whyOldFailureNoLongerApplies: [PredicateProof]
}
```

A delta is material only when:

1. at least one changed axis is causally connected to a recorded failure;
2. the new expected observation can distinguish success from the old failure;
3. no retired anti-repeat constraint is violated;
4. requirement coverage is complete or explicitly split;
5. authority and mutation/resource budgets remain valid.

Examples:

- changing cwd topology after a proven isolated-worktree mismatch is material;
- adding a new authoritative artifact source after bytes were proven absent is material;
- starting the watchdog before the input action after XCTest measured only afterward is material;
- changing only objective wording, model, thread, or verifier description is not material.

## Strategy portfolio planning

For uncertain or high-risk requirements, the planner proposes a bounded portfolio before mutation:

```swift
struct StrategyCandidate {
    let fingerprint: StrategyFingerprint
    let predictedInformationGain: EvidenceValue
    let expectedRequirementGain: Set<RequirementID>
    let estimatedCost: CostVector
    let mutationRisk: RiskVector
    let reversibility: Reversibility
    let dependencies: Set<StrategyFingerprint>
}
```

The kernel validates causal diversity and selects by expected requirement/evidence gain per cost under risk and resource budgets. Safe read-only strategies with genuinely distinct evidence routes may run in parallel. Mutating strategies remain isolated; broad/high-risk candidates require stronger baseline and rollback gates.

The portfolio is not a demand to run multiple Agents. It prevents the first familiar idea from monopolizing all budget and makes alternative routes explicit before repeated failure.

## External waiting without busy loops

An external blocker transition records a predicate and optional next eligible time/event source. The run then has no runnable worker:

- timers use the central scheduler;
- no power lease remains unless bounded cleanup is active;
- no retry/active time accrues;
- a wake requires a new external-condition receipt or explicit user command;
- unchanged observations do not generate new Agent attempts.

This preserves long-lived autonomous recovery without polling an impossible condition through expensive model turns.

## Formal termination argument

Let `B` be the finite sum of remaining durable attempt, strategy, plan-expansion, mutation, damage, and external-effect tokens across the accepted contract.

1. Every admitted attempt commits token consumption before execution.
2. Every replacement retires at least one strategy and consumes/transfers, but never creates, budget.
3. Equivalent fingerprints cannot be re-admitted after their class-specific or global limit.
4. Pause/restart/thread/model changes do not modify `B`.
5. External waits have no runnable transition until a new condition event; they perform no busy work.
6. Therefore the number of automatic work transitions is finite.
7. The reducer must eventually reach completed, explicitly externally blocked, infeasible/exhausted, paused/stopped, or cleanup-blocked state.

An explicit user contract amendment may add budget and begins a new auditable convergence epoch. It cannot rewrite the history of the prior epoch.

## Runtime accounting and node UI

Each node exposes three receipt-derived quantities:

- cumulative eligible runtime across every attempt/strategy round;
- live eligible runtime in the current attempt;
- excluded time by reason (blocked, failed, interrupted, thermal/resource wait, idle, reviewer failure).

Cumulative history never resets on replacement, while the current live clock starts at zero for the new attempt. Time satisfies an explicit effort constraint only; it never proves quality or progress.

## Required historical and property tests

1. Replay all 51 stopped-run iterations and preserve every contradiction as legacy evidence.
2. The 11 blocked write-scope turns trigger topology review after the first confirmed scope mismatch.
3. The seven unavailable-screenshot iterations stop after first authoritative unavailability proof.
4. The isolated-worktree/canonical-cwd sequence never relaunches the unchanged worker.
5. The XCTest delayed-measurement strategy is retired; pre-action watchdog delta is accepted.
6. `blocked + accepted` is unrepresentable.
7. exit code zero plus blocked receipt remains blocked.
8. reviewer parse failure retries reviewer, not worker.
9. paraphrased objective with identical causal axes is rejected.
10. fresh thread/model/node ID cannot reset equivalence or budget.
11. material cwd/topology change passes `StrategyDelta` validation.
12. genuinely new evidence source passes only with source identity receipt.
13. same verifier failure resolves only through equivalent successful rerun.
14. unrelated green command cannot improve progress vector.
15. new files/tests/prose at unchanged evidence digest are zero progress.
16. protected visual regression forces immediate rollback and retirement.
17. safe read-only distinct hypotheses can use a larger evidence budget.
18. high-cost attempts consume more cost budget without minting retries.
19. split transfers predecessor budget and typed requirement ownership.
20. replacement cannot drop an owned requirement silently.
21. no viable replacement yields `declareInfeasible`, not loop restart.
22. external blocker waits without worker, poll storm, power lease, or active time.
23. pause/relaunch preserves all budgets and retired fingerprints.
24. plan expansion cannot increase total budget.
25. user amendment creates a new convergence epoch and preserves old history.
26. concurrent portfolio strategies have distinct fingerprints and isolated mutations.
27. property test: every automatic transition monotonically reduces finite budget or enters a non-runnable wait/terminal state.
28. property test: no retired/equivalent strategy becomes runnable across arbitrary crash/replay points.
29. property test: completion implies every mandatory requirement accepted at the same revision and no hard regression.
30. vocabulary-invariance test: causally equivalent scenarios with unrelated domains produce identical scheduler decisions.

## Implementation boundary after the forensic gate

1. Add typed outcomes, fingerprints, progress vectors, budgets, lessons, deltas, and portfolio values to the pure kernel.
2. Import legacy histories as contradictory claims without converting blocked prose to approval.
3. Shadow-classify current turns and compare the new reducer decision with legacy behavior.
4. Enforce structural failure classes before generic retry counts.
5. Persist budget consumption and retirement before worker/replacement launch.
6. Replace lexical `isMateriallyDifferent`, scalar stagnation, and thread-reset recovery.
7. Route all external waits through predicate/event eligibility and the resource governor.
8. Expose cumulative/current/excluded time and causal strategy history in the native UI.

This makes autonomy stronger, not weaker: the scheduler can explore a diverse portfolio, learn durable negative knowledge, and act without supervision, while finite budgets and causal novelty prevent it from grinding indefinitely on an unchanged idea.

