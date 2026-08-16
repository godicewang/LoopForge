# Transactional Integration, Rollback, and Publication Specification

Status: pre-implementation normative design; no production source mutation is authorized before the forensic gate.

## Executive conclusion

LoopForge's isolated worktrees and binary patches are useful mechanisms, but the surrounding protocol is not a closed transaction. Workers can commit and push from an isolated worktree; the coordinator may then stash canonical dirty content and fast-forward to the remote. On a patch conflict, a fresh agent edits the primary workspace directly and exit code zero is treated as integration success. The system lacks an immutable user-owned preimage, typed mutation manifest, postimage receipt, rollback proof, and separately authorized publication transaction.

The replacement separates candidate construction, integration, verification, acceptance, canonical commit, and remote publication. Candidate workers never touch the canonical workspace or remotes. Integration is performed only by a deterministic transaction executor against a content-addressed preimage. A semantic conflict resolver may propose a new candidate, but cannot edit canonical state. Every canonical mutation remains rollbackable until independent postimage gates pass. Push, deployment, upload, submission and other remote effects require their own authority and durable outbox receipt.

## Measured current behavior

The current source implements several partial safeguards:

- clean Git workspaces can produce detached worktrees;
- primary uncommitted state is mirrored into dependent worktrees;
- changed paths are checked against declared write scopes;
- binary patches are written by Git rather than string transport;
- `git apply --check` precedes patch application;
- reverse-apply checks provide limited idempotence after a crash;
- unrelated canonical dirty paths block published fast-forward alignment;
- process calls have bounded timeouts.

Those strengths do not form a transaction:

- `prepare` forcibly removes an existing node worktree path before proving that its evidence or changes are durably retained;
- a clean empty project may be initialized and committed as a capability side effect;
- dependent worktrees mirror the mutable primary workspace and create a private commit, but the canonical preimage has no durable manifest;
- commits created in isolated worktrees can be pushed by workers because network and Git remote authority are not separated from workspace access;
- published-node recovery treats a remote fast-forward as a possible source of truth before final product approval;
- matching dirty canonical content may be stashed with `--include-untracked`, changing user-visible index and worktree state;
- patch files are keyed by task/node ID rather than candidate revision, base digest and patch digest;
- a `verified-no-changes` marker contains no base, revision, path-set or verifier identity;
- reverse-patch presence does not prove which transaction applied the bytes, whether mode/rename/submodule semantics match, or whether post-integration verification passed;
- conflict repair launches an agent in the primary workspace and returns success solely from process exit code zero;
- cleanup uses forced worktree removal without a durable cleanup/quiescence receipt;
- there is no universal integration receipt in the dependency or completion predicate.

## Defects added by this analysis

### F-189 — Remote state can outrun local acceptance

An isolated worker can commit and push. Coordinator code then attempts to align canonical state to the already-published result. Remote publication has become an input to acceptance rather than a separately authorized terminal effect.

### F-190 — Canonical dirty state has no owner-preserving preimage

Path names and object IDs are sampled, but there is no durable record of working-tree bytes, index bytes, modes, symlinks, untracked files, sparse settings and ownership at transaction start.

### F-191 — Safety stash is a hidden canonical mutation

Even byte-identical dirty content can carry user staging intent and recovery expectations. `stash --include-untracked` changes the visible workspace without a user-authorized transaction or a tested restoration receipt.

### F-192 — Integration artifacts are not revision-addressed

Node-ID patch and no-change marker filenames allow stale artifacts to collide with later iterations. Some recovery paths compensate with live worktree checks, but identity is not universal.

### F-193 — Conflict repair bypasses deterministic integration

The repair agent writes directly to the primary workspace, can exceed original scope, and converts exit zero into success without a candidate manifest, rollback proof or independent postimage gates.

### F-194 — Reverse patch is an incomplete integration receipt

It demonstrates applicability of inverse text/binary changes in a current tree, not transaction ownership, requirement coverage, revision identity, post-verification success or absence of unrelated changes.

### F-195 — Capability discovery can mutate the repository

Initializing Git and creating a baseline commit changes project metadata merely to enable an execution mode. Capability detection must be observational.

### F-196 — Forced workspace cleanup can destroy the last candidate copy

An existing node worktree may be removed before its candidate, logs, evidence and manifest have been durably sealed.

### F-197 — No-change markers are unauthenticated assertions

The current marker contains only `verified-no-changes`; it does not identify which base, contract revision, candidate revision, command or verifier established the claim.

### F-198 — Dependency scheduling trusts presentation fields, not integration truth

Status/review fields can unlock successors without an `IntegrationReceipt` binding approved bytes to the canonical postimage.

### F-199 — Rollback is possible in theory but absent as a protocol

Patches, Git history or stashes might permit manual recovery, yet no rollback plan is preflighted, no reversal is exercised, and no receipt proves the exact user preimage can be restored.

### F-200 — Cleanup and publication have no effect outbox

Worktree removal, remote push and related effects can happen between state checkpoints. Replay cannot distinguish intended, started, succeeded, failed and reconciled effects reliably.

## Trust boundaries

The protocol separates five principals:

1. **Candidate worker**: reads an authorized snapshot and writes only its isolated candidate overlay.
2. **Candidate verifier**: runs recipes against the candidate revision; it cannot mutate canonical state or acceptance policy.
3. **Independent reviewer**: accepts or rejects requirement receipts and protected baselines; it cannot integrate or publish.
4. **Transaction executor**: applies a pre-authorized manifest mechanically; it cannot invent edits, relax gates or contact remotes.
5. **Publication executor**: performs explicitly authorized remote effects after canonical acceptance; it cannot edit product content.

The Main Graph Agent may choose among admissible candidates and request a semantic conflict-resolution candidate. It is not any of the executors above.

## Content-addressed objects

All durable identities use cryptographic digests over canonical encodings:

```text
WorkspacePreimage
  workspaceID
  rootIdentity
  contractRevision
  vcsKind and head identity if any
  entries[]
  indexEntries[]
  untrackedEntries[]
  repositoryMetadataDigest
  ignoredPathPolicy
  capturedAt
  digest

WorkspaceEntry
  path
  kind                  file | directory | symlink | submodule
  mode
  contentDigest
  linkTarget
  size
  ownershipClass        userExisting | taskPriorAccepted | generatedCache

MutationCandidate
  candidateID
  parentPreimageDigest
  contractRevision
  planNodeContractDigest
  strategyFingerprint
  mutationManifestDigest
  evidenceSetDigest
  candidatePostimageDigest
  sealedAt
```

Large content is stored once in a local content-addressed object store with retention and privacy policy. The manifest never relies on an ephemeral worktree as the only copy. Secret scanning and path policy run before an object is admitted.

## Typed mutation manifest

```text
MutationManifest
  candidateID
  baseDigest
  operations[]
  touchedRequirementIDs[]
  writeAuthorityReceipt
  mutationBudgetReceipt
  expectedPostimageDigest

MutationOperation
  sequence
  kind                 create | modify | delete | rename | chmod | symlink | submodule
  sourcePath
  destinationPath
  expectedPreimage
  desiredPostimage
  modeBefore
  modeAfter
  requirementIDs[]
```

Each operation has compare-and-swap semantics. If the canonical entry no longer equals `expectedPreimage`, integration stops with a typed conflict before mutating that entry. Path normalization resolves case, Unicode normalization, symlinks and repository-root escapes before admission. Globs and `.` are never executable mutation targets; they must expand into a sealed exact operation list.

## Transaction state machine

```text
proposed
  -> preflighted
  -> rollbackPrepared
  -> applying
  -> appliedUnverified
  -> postimageVerified
  -> independentlyAccepted
  -> canonicalCommitted
  -> publicationEligible
  -> published | retainedLocal

Any nonterminal mutation state
  -> rollingBack
  -> rolledBack | rollbackFailedQuarantined
```

Every transition is a journal event with expected sequence, input digests and an idempotency key. No UI status is authoritative. A crash resumes by reducing the journal and reconciling the current filesystem to the last durable intent.

## Preflight

Before any canonical write, the executor must prove:

- contract revision and plan ownership are current;
- candidate is sealed and its object graph is complete;
- exact operation paths are inside the authorized set;
- actual preimages match expected preimages;
- user-owned dirty/index/untracked state is fully captured;
- no unrelated path will be touched;
- required candidate verification and adversarial review receipts are valid;
- visual/design vetoes pass for visual-risk candidates;
- no worker process still owns the candidate directory;
- disk space can hold preimage, postimage and rollback objects;
- rollback has been materialized and dry-validated;
- resource governor grants a bounded integration lease;
- remote access is disabled for this phase.

Failure leaves canonical bytes unchanged and emits a typed receipt.

## User-owned dirty state

Dirty state is never stashed, reset, cleaned, committed, staged, unstaged or normalized as a hidden implementation detail. It is modeled entry-by-entry.

- A candidate based on user dirt records separate HEAD, index and worktree preimages.
- Integration modifies only exact worktree entries authorized by compare-and-swap.
- Existing staging intent remains unchanged unless the user contract explicitly authorizes index mutation.
- An operation overlapping newer user changes becomes a semantic conflict; it cannot be auto-stashed.
- Untracked files are protected equally with tracked files.
- Ignored files are not copied or removed unless explicitly part of the task contract.
- Repository metadata, hooks, remotes, attributes, sparse-checkout and submodule configuration are protected system surfaces.

## Candidate construction

Capability observation must not initialize Git or create commits. Execution choices are:

- Git repository: isolated detached worktree or content-addressed overlay at an exact preimage.
- Non-Git workspace: read-only snapshot plus writable overlay.
- Read-only verification: disposable clone/overlay with all product writes discarded.
- Canonical exclusive mode: allowed only through the same transaction executor, never direct worker writes.

An existing candidate directory is reused only when its owner lease and manifest match. Otherwise it is quarantined and sealed before any removal. Forced deletion is forbidden until a durable `CleanupReceipt` proves every recoverable object is retained.

Worker Git configuration disables remotes and hooks in the candidate environment. Worker process policy rejects `git push`, remote-mutating commands, deploy/upload/store submission, and other external effects unless they are routed through an explicit broker capability—which is unavailable during candidate work by default.

## Independent candidate gates

Before integration admission:

1. operation manifest matches candidate postimage;
2. write scope and mutation budget pass;
3. no protected metadata changed;
4. deterministic requirement recipes pass on candidate revision;
5. baseline-bound visual/design gates pass when applicable;
6. adversarial reviewer sees original contract, immutable baseline, manifest and raw receipts without worker rationale first;
7. candidate resource/process cleanup passes;
8. candidate contains no unresolved test or effect failure;
9. rollback plan is constructible;
10. reviewer and worker independence policy passes.

Rejected candidates never become a new baseline and never enter canonical history.

## Deterministic apply protocol

The executor performs:

1. journal `IntegrationRequested` with all digests;
2. acquire exclusive canonical mutation lease;
3. re-capture and compare canonical preimage;
4. write rollback objects and journal `RollbackPrepared`;
5. stage desired bytes in a transaction-private sibling directory;
6. validate every staged content digest, mode and link target;
7. journal `ApplyStarted`;
8. apply operations in declared order using same-volume temporary files and atomic rename where possible;
9. fsync files and parent directories according to durability class;
10. capture the full affected postimage and compare to expected digest;
11. prove all non-manifest paths unchanged;
12. journal `AppliedUnverified`;
13. run post-integration recipes on canonical state;
14. run rollback rehearsal against a disposable image of the applied state;
15. request independent acceptance bound to the canonical postimage;
16. on success journal `IntegrationAccepted`; otherwise rollback immediately.

Git patches may be an interchange optimization, but the manifest and object digests are authoritative. Patch application alone never closes the transaction.

## Semantic conflict resolution

A conflict is classified before response:

- `newerUserChange`;
- `acceptedSiblingChange`;
- `baselineMismatch`;
- `pathTopologyChange`;
- `modeOrSymlinkConflict`;
- `requirementConflict`;
- `unknownPreimage`.

The resolver receives immutable base, candidate and canonical snapshots plus typed requirements. It works in a new isolated overlay and returns a new `MutationCandidate`, `StrategyDelta`, and conflict-resolution proof. It has no canonical write access. The new candidate repeats all independent gates and consumes a distinct integration-repair budget. Exit code zero, a natural-language promise, or a passing subset of tests never means conflict resolved.

## Rollback protocol

Rollback is a required forward transaction from current postimage to captured preimage:

- it has its own exact operation manifest;
- compare-and-swap guards against newer user edits after application;
- it restores worktree bytes, modes, symlinks and index state separately;
- it never deletes a post-application user edit silently;
- it is rehearsed in isolation before canonical apply;
- it runs automatically on failed postimage, verification, visual, acceptance or quiescence gates;
- it emits `RollbackReceipt` with restored digest and any quarantined conflicts;
- rollback failure freezes all further mutation and exposes exact recovery artifacts.

No destructive Git reset or clean is required.

## Canonical commit policy

Integration acceptance does not imply a Git commit. Commit creation is a separate local publication action:

- only when the task contract authorizes commits;
- only after accepted postimage and clean transaction receipt;
- author, message and included paths are explicit;
- pre-existing user index state is preserved;
- the commit parent and tree are verified after creation;
- commit failure does not invalidate an accepted uncommitted integration but is reported honestly;
- agent-authored commits in isolated worktrees are candidate metadata, not canonical publication.

## Remote publication protocol

Remote effects include push, pull-request creation, deployment, upload, store submission, message, email, payment and public API mutation. They use `PublicationTransaction`:

```text
PublicationTransaction
  publicationID
  integrationReceiptID
  authorityReceiptID
  destinationIdentity
  exactPayloadDigest
  expectedRemotePrecondition
  idempotencyKey
  rollbackOrCompensationPlan
  status
```

Rules:

- default is local retention, not publication;
- a workspace access mode never grants remote publication;
- worker, reviewer and integrator cannot publish;
- destination and branch/resource identity are exact;
- remote precondition prevents overwriting newer remote state;
- intent is durably journaled before the effect;
- response is reconciled into an immutable receipt;
- unknown outcome triggers read-only reconciliation, not blind repeat;
- pull/fetch for evidence is separated from push/write authority;
- publication happens only after all applicable product and visual gates pass;
- a remote result never retroactively validates a candidate.

## Integration receipt

```text
IntegrationReceipt
  transactionID
  taskContractRevision
  planNodeContractDigest
  candidateID
  canonicalPreimageDigest
  mutationManifestDigest
  canonicalPostimageDigest
  unchangedPathProof
  candidateEvidenceDigest
  postIntegrationEvidenceDigest
  visualReviewReceiptIDs[]
  independentAcceptanceReceiptID
  rollbackReceiptOrPreparedDigest
  processQuiescenceReceiptID
  appliedAt
  status
```

Dependencies and final completion require an accepted receipt. Mutable node fields such as `status`, `lastReview`, `completedAt` or `workspacePath` are projections only.

## Crash recovery matrix

| Durable state | Observed filesystem | Recovery |
|---|---|---|
| proposed/preflighted | unchanged | discard or resume preflight |
| rollbackPrepared | unchanged | retain objects; retry apply only if still eligible |
| ApplyStarted | preimage | resume apply from first unapplied operation |
| ApplyStarted | partial postimage | reconcile each CAS operation, then finish or rollback |
| appliedUnverified | exact postimage | run postimage gates; never rerun worker |
| appliedUnverified | drifted | freeze and classify newer changes before rollback |
| postimageVerified | exact postimage | request independent acceptance |
| independentlyAccepted | exact postimage | record integration receipt and unlock dependents |
| rollingBack | partial preimage | reconcile rollback operations |
| publication intent | remote unknown | read-only remote reconciliation by idempotency key |

Recovery never launches the original worker to recreate accepted work and never uses stale node-ID markers as proof.

## Cleanup and retention

Cleanup is resource ownership, not incidental file deletion:

- seal candidate manifest, evidence and object references;
- stop and reap worker process tree;
- release simulators, servers, ports, brokers and power assertions;
- unregister Git worktree metadata cleanly;
- remove disposable directories only after reference count is zero;
- retain rejected candidates for bounded forensic duration without treating them as baselines;
- retain rollback objects until task acceptance plus configured recovery window;
- emit `CleanupReceipt` and `QuiescenceReceipt`;
- garbage collection is budgeted and never runs concurrently with heavy verification.

## Quantitative budgets

- one canonical mutation transaction at a time per workspace;
- zero worker remote-write capabilities by default;
- zero direct primary-workspace writes by conflict agents;
- zero hidden stash/reset/clean operations;
- zero lossy path normalization;
- at most one causal conflict-resolution candidate per manifest conflict class unless new evidence appears;
- preimage and rollback objects must cover 100% of touched entries;
- unchanged-path proof covers the full workspace manifest excluding declared ephemeral paths;
- every operation has both expected preimage and desired postimage;
- post-integration recipes bind to the exact canonical postimage;
- cleanup is not complete until owned process/resource count is zero;
- publication retry count is zero while remote outcome is unknown.

## Deterministic, fault-injection and property tests

1. Capability inspection never initializes or commits a repository.
2. Candidate worker cannot access configured push remotes.
3. Candidate worker cannot mutate canonical bytes.
4. Candidate worker cannot route a deployment through ordinary shell access.
5. Existing candidate directory is not removed before sealing.
6. Preimage records HEAD, index, worktree and untracked content separately.
7. Staged user intent survives accepted integration unchanged.
8. Ignored files remain untouched unless explicitly manifested.
9. Symlink escape is rejected.
10. Case-fold collision is rejected on case-insensitive volumes.
11. Unicode-equivalent path collision is rejected.
12. Rename records source and destination preimages.
13. Mode-only change is manifested and reversible.
14. Submodule change requires explicit operation and authority.
15. Empty scope cannot expand to workspace root.
16. Manifest operation outside scope rejects before apply.
17. Mutation budget overrun rejects before apply.
18. Newer user edit causes compare-and-swap conflict with zero canonical mutation.
19. Accepted sibling edit becomes a typed semantic conflict.
20. Binary candidate round-trips through content digests.
21. No-change receipt binds base, candidate and contract revision.
22. Stale node-ID marker cannot approve a new iteration.
23. Patch identity alone cannot produce integration acceptance.
24. Worker exit zero cannot resolve integration conflict.
25. Conflict resolver has no canonical write capability.
26. Conflict resolver output re-enters all candidate gates.
27. Failed postimage verification rolls back exact preimage.
28. Failed visual gate rolls back and retires visual strategy.
29. Failed independent review rolls back without rerunning worker.
30. Rollback preserves user edits made after apply by quarantining conflict.
31. Rollback rehearsal failure blocks canonical apply.
32. Crash before ApplyStarted leaves canonical unchanged.
33. Crash after each operation resumes idempotently or rolls back.
34. Crash after apply but before receipt does not duplicate changes.
35. Crash during rollback restores or freezes with complete recovery artifacts.
36. Dependency cannot run without accepted integration receipt.
37. Final completion cannot pass without integration and quiescence receipts.
38. Canonical commit cannot precede independent acceptance.
39. Canonical commit preserves pre-existing index intent.
40. Worker push does not become a trusted source of truth.
41. Publication without explicit destination authority is denied.
42. Publication precondition prevents non-fast-forward overwrite.
43. Unknown remote result is reconciled without repeat.
44. Remote publication cannot validate a failed product gate.
45. Cleanup waits for process and resource quiescence.
46. Cleanup preserves all object-store references required for rollback.
47. Property test: canonical state is always preimage, exact accepted postimage, or a journal-recoverable prefix.
48. Property test: every canonical byte change maps to one authorized manifest operation.
49. Property test: every completed node has an accepted integration/no-change receipt at current revision.
50. Vocabulary-invariance test: identical mutation/effect topology yields identical policy across unrelated task domains.

## Implementation boundary after the forensic gate

1. Add pure transaction types and reducer to the kernel.
2. Add content-addressed preimage/candidate/rollback storage and a journaled effect outbox.
3. Remove implicit Git initialization, forced candidate deletion and canonical stashing.
4. disable remotes and external-effect capabilities inside worker environments.
5. replace node-ID patches/markers with revision-addressed candidate manifests and receipts.
6. replace direct canonical conflict repair with isolated resolution candidates.
7. route all canonical writes through the deterministic transaction executor.
8. require integration receipts in scheduling and completion reducers.
9. implement separate commit and remote-publication authorization paths.
10. shadow-run manifests and receipts against existing integration tests before enforcement.

The central safety property is that an agent can propose bytes, but only a deterministic, journaled, reversible transaction can place accepted bytes in the user's canonical workspace—and no local success can silently publish them elsewhere.
