# Kernel Command, Event, and Receipt Specification

Status: pre-implementation normative design. This specification makes the command/event atomic boundary concrete enough to implement and model-check after the forensic gate.

## 1. Identity primitives

All IDs are opaque, strongly typed UUID wrappers. Digests are SHA-256 over canonical JSON or raw artifact bytes.

```swift
RunID, TaskContractID, RequirementID, NodeID, AttemptID,
StrategyID, CapabilityLeaseID, MutationTransactionID,
ArtifactID, ReceiptID, ReviewID, CommandID, EventID
```

Every command envelope contains:

```swift
struct RunCommandEnvelope<Payload: Codable & Sendable> {
    let schemaVersion: Int
    let commandID: CommandID
    let runID: RunID
    let expectedSequence: UInt64
    let actor: ActorIdentity
    let authorityLeaseIDs: Set<CapabilityLeaseID>
    let idempotencyKey: Digest
    let submittedAt: Instant
    let payload: Payload
}
```

Every event frame contains:

```swift
struct OrchestrationEventFrame<Payload: Codable & Sendable> {
    let schemaVersion: Int
    let eventID: EventID
    let runID: RunID
    let sequence: UInt64
    let commandID: CommandID
    let priorFrameDigest: Digest
    let contractDigest: Digest
    let actor: ActorIdentity
    let occurredAt: Instant
    let payload: Payload
    let frameDigest: Digest
}
```

Snapshots cache `{lastSequence,lastFrameDigest,stateDigest,state}` and are never authoritative.

## 2. Command transaction protocol

For each command, `RunJournal.transact`:

1. loads/reduces through the authoritative sequence;
2. verifies run, expected sequence, actor, authority leases, idempotency key, schema, and contract digest;
3. asks the pure reducer to return either typed rejection or a non-empty ordered event batch;
4. canonical-encodes and hash-chains every frame;
5. atomically appends/fsyncs the batch;
6. returns a `TransactionReceipt` with first/last sequence and final state digest;
7. asynchronously updates cache/projection after the transaction is durable.

If the client loses the response, the same idempotency key returns the original receipt. A new key against a stale expected sequence returns `staleSequence`; it never silently re-evaluates against newer authority.

Side effects use an outbox event. An adapter claims one effect ID, performs it, and submits a result command. Crash recovery redelivers unacknowledged effects idempotently.

## 3. Derived run phases

`RunPhase` is a projection, not independently mutable:

```text
draft
planning
ready
executing
reviewing
integrating
pauseRequested
stopRequested
draining
cleanupBlocked
paused
stopped
completionCandidate
completed
failed
```

Projection precedence:

1. valid completion receipt → `completed`;
2. unresolved cleanup failure → `cleanupBlocked`;
3. stop request without quiescence → `stopRequested`/`draining`;
4. pause request without quiescence → `pauseRequested`/`draining`;
5. accepted quiescence plus stop/pause → `stopped`/`paused`;
6. live integration/review/execution/ready/planning state;
7. explicit unrecoverable kernel failure → `failed`.

A late Agent result cannot outrank a pause/stop request. It remains historical evidence and is ineligible for mutation, review, or time credit.

## 4. Command and event matrix

| Command | Mandatory preconditions | Emitted event(s) | Never allowed |
|---|---|---|---|
| `createRun(contract)` | new run; owner authority; valid immutable contract | `runCreated`, `contractFrozen` | model refinement silently replacing verbatim goal |
| `amendContract(amendment)` | explicit owner authority; rationale; no retroactive receipt reuse | `contractAmended`, `receiptsInvalidated` | reviewer/worker amendment |
| `proposePlan(proposal)` | frozen contract; planner read-only; nodes map requirement IDs | `planProposed` | implicit capability/scope grant |
| `acceptPlan(planID)` | deterministic DAG/scope/budget checks green | `planAccepted`, node declarations | accepting prose-only/invalid nodes |
| `authorizeNode(auth)` | dependencies have accepted integration/external receipts; budget available | `nodeAuthorized` | missing scope/capability/evidence plan |
| `startAttempt(start)` | authorized node; valid workspace/capability leases; no terminal request | `attemptStarted`, active-time eligibility event | primary-workspace fallback after isolation failure |
| `recordExecutionOutcome(outcome)` | exact active attempt/actor/session | `executionOutcomeRecorded`, time disposition | blocked/failed/interrupted as completed |
| `requestVerification(req)` | candidate revision/artifacts frozen | `verificationRequested`, outbox effect | verification of moving workspace |
| `recordVerification(receipt)` | exact request/executor/revision/oracle | `verificationRecorded` or typed rejection | log text as receipt |
| `requestReview(req)` | complete required evidence; independence class satisfiable | `reviewRequested`, outbox effect | silent attachment truncation |
| `recordReview(receipt)` | one strict envelope; exact request digests and independent actor | `reviewRecorded` or rejection | blocked+ordinary approval; deterministic veto waiver |
| `retireStrategy(retirement)` | causal budget exhausted or structural blocker proven | `strategyRetired`, `attemptsCancelled` | reactivation of retired fingerprint |
| `declareReplacement(replacement)` | typed causal dimension changes; inherited lesson/budget | `replacementDeclared` | paraphrase-only replacement |
| `proposeMutation(tx)` | baseline/current candidate known; scope/budget satisfied | `mutationProposed` | unspecified changed paths |
| `authorizeIntegration(txID)` | fresh verification/review/visual receipts for exact patch | `integrationAuthorized`, outbox effect | exit-code-only authorization |
| `recordIntegration(receipt)` | atomic postimage matches expected digest | `integrationRecorded` | partial apply or stale baseline |
| `recordRollback(receipt)` | failed/cancelled transaction and expected preimage | `rollbackRecorded` | hiding rollback failure |
| `requestCapability(req)` | task authority ceiling permits exact operation | `capabilityRequested`, outbox effect | keyword/prose inference |
| `recordCapabilityLease(lease)` | adapter receipt matches request/owner/expiry | `capabilityAcquired` | unowned durable resource |
| `releaseCapability(leaseID)` | owner or supervisor cleanup authority | `capabilityReleaseRequested`, outbox effect | terminal state before result |
| `recordCapabilityRelease(receipt)` | exact lease; observed final state | `capabilityReleased` or `capabilityReleaseFailed` | clearing failed ownership |
| `requestPause(control)` | owner/control authority; nonterminal run | `pauseRequested`, cancellation outbox | immediate `paused` projection |
| `requestStop(control)` | owner/control authority; nonterminal run | `stopRequested`, cancellation outbox | immediate `stopped` projection |
| `recordDrainProgress(receipt)` | supervisor-owned task/resource inventory | `drainProgressRecorded` | deleting handles before acknowledgement |
| `recordQuiescence(receipt)` | inventory complete; journal flushed; assertions released | `quiescenceVerified` | elapsed grace as proof |
| `authorizeCompletion(auth)` | all mandatory requirements/receipts/current revision/quiescence green | `completionAuthorized`, `completionReceiptIssued` | score/time/prose override |

## 5. Typed worker outcome

```swift
enum ExecutionDisposition: Codable, Sendable {
    case completed
    case continuationNeeded
    case blocked(BlockerReceipt)
    case failed(FailureReceipt)
    case interrupted(InterruptionReceipt)
    case malformed(TransportReceipt)
}
```

`completed` means the worker claims its node output is ready for verification; it does not mean verified, reviewed, integrated, or accepted.

`BlockerReceipt` includes blocker kind, affected requirement/operation, immutable constraint, observed evidence digests, exact retry condition, authority needed, and whether the blocker is external. The reducer assigns no accepted time to blocked intervals.

Valid review resolutions:

| Execution | Valid review decision |
|---|---|
| completed | approveCandidate, rejectCandidate, needsDifferentEvidence |
| continuationNeeded | authorizeContinuation, retireStrategy, rejectCandidate |
| blocked | acceptExternalBoundary, requireTopologyChange, requireAuthorityChange, retireStrategy |
| failed | retireStrategy, authorizeDifferentStrategy |
| interrupted | none; resume requires a new attempt command |
| malformed | none; retry transport/reviewer as applicable, not mutation by default |

## 6. Time ledger

Time is derived from eligibility events using a monotonic clock receipt:

```text
attemptEligibleStarted
attemptEligibilityPaused(reason)
attemptEligibilityResumed
attemptEnded(disposition)
timeDispositionRecorded(accepted | excludedBlocked | excludedRejected |
                        excludedFailure | excludedInterrupted | excludedIdle)
```

An attempt's raw eligible duration is immutable. Accepted duration becomes non-zero only after the node output is accepted by the applicable policy. Historical/excluded time stays visible but cannot satisfy user duration requirements. Current live time exists only between an unmatched eligible-start/resume and pause/end.

## 7. Receipt common header

```swift
struct ReceiptHeader: Codable, Sendable {
    let schemaVersion: Int
    let receiptID: ReceiptID
    let runID: RunID
    let taskContractDigest: Digest
    let requirementIDs: Set<RequirementID>
    let actor: ActorIdentity
    let actorLineage: ActorLineage
    let sourceRevision: RevisionIdentity?
    let workspaceIdentity: WorkspaceIdentity?
    let environmentDigest: Digest?
    let requestDigest: Digest
    let artifactDigests: Set<Digest>
    let issuedAt: Instant
    let expiresOn: ReceiptExpiryPolicy
}
```

All receipt-specific facts live after this header. Receipt validation is deterministic and never delegated to a model.

## 8. Invalid combination invariants

The reducer must reject:

- ordinary approval of blocked/failed/interrupted/malformed execution;
- integration without exact current patch, verification, review, and required visual receipt;
- completed dependency when its mutation is not integrated or external boundary not accepted;
- retired fingerprint authorization;
- active attempt without workspace and capability leases;
- authority outside the immutable task ceiling;
- pause/stop terminal projection without quiescence;
- completion with live tasks, PIDs, timers, leases, sleep assertions, or failed cleanup;
- reuse of any receipt after contract/revision/environment/evidence expiry;
- later success superseding a nonmatching failure;
- visual comparison across mismatched capture environments;
- worker/reviewer lineage violating required independence;
- output envelope with multiple or mismatched decision objects;
- mutation path outside scope or budget;
- any fallback that widens authority.

## 9. Rejection taxonomy

```text
staleSequence
duplicateCommand
invalidContract
authorityDenied
leaseMissingOrExpired
invalidTransition
invalidOutcomeReviewCombination
scopeViolation
mutationBudgetExceeded
staleBaseline
staleReceipt
evidenceIncomplete
reviewNotIndependent
ambiguousEnvelope
strategyRetired
noCausalProgress
cleanupIncomplete
quiescenceNotProven
deterministicVeto
```

Rejections are journaled as audit frames only when useful for diagnostics; they never mutate domain state or consume retry/active budgets unless a policy explicitly classifies the attempt cost.

## 10. Legacy import

Legacy tasks are imported through `LegacyTaskImporter`, never decoded directly into authoritative new state.

- raw bytes and original fields become immutable historical artifacts;
- known command exits become observations, not verification receipts;
- blocked+approved and other contradictions become `legacyContradictionDetected` events;
- free-text approvals/completion markers remain claims;
- old duration becomes raw/excluded legacy time unless direct interval proof supports a typed disposition;
- no legacy task auto-resumes until an owner explicitly creates a new contract/plan from the imported evidence.

## 11. Projection obligations

UI and reports receive only `RunProjection`:

- immutable objective and requirement coverage;
- current derived phase and reason;
- accepted total, current live eligible, and excluded time by reason;
- node strategy fingerprint, attempt budget, progress vector, and retirement lesson;
- mutation candidate/integration/rollback state;
- verification/review provenance and expiry;
- resource inventory and quiescence status;
- claims clearly separated from receipt-backed facts.

No view/controller may call a store mutation closure. UI actions submit typed commands and render the resulting transaction/rejection receipt.

This specification is the contract the first kernel implementation and reducer model tests must satisfy.
