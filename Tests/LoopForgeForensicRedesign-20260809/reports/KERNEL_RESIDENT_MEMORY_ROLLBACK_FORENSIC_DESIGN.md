# Resident-memory veto and rollback forensic design

Recorded: 2026-08-14T11:40:17Z

Status: both correction halves are implemented and verified; a trusted
ordinary-macOS Release containment issuer remains unavailable by design.

## Correction status (2026-08-14T13:05:24Z)

The typed launch-veto receipt and exact already-applied rollback recovery are
now implemented. Startup recovery validates the accepted veto and completed
apply envelope, admits a fresh exclusive rollback lease, persists a
deterministic rollback request, crash-replays the same identities, restores the
retained preimage, and converges to `rolledBack` with zero reentry. See
`KERNEL_POSTIMAGE_VERIFIER_VETO_ROLLBACK_RECOVERY_IMPLEMENTATION.md` and its
machine-readable scorecard.

Part 1 is now enforced by a non-serializable exact-run/transaction/contract
capability checked before supervisor construction, lease admission, apply
intent, or outbox persistence. Missing or cross-wired readiness leaves the
transaction `rollbackPrepared` with no mutation authority. See
`KERNEL_PREAPPLY_CONTAINMENT_READINESS_GATE_IMPLEMENTATION.md`. No Release
issuer exists, so ordinary-macOS production apply remains safely withheld.

## Finding

The remaining verifier block is not only an unavailable Darwin primitive. It
also exposes a lifecycle-ordering defect: the canonical workspace can reach
`appliedUnverified` before LoopForge proves that the independent verifier can
be admitted under every ratified containment limit.

The exact current sequence is:

1. `WorkspaceCompletedCandidateMutationApplyPreparationCoordinator` admits an
   exclusive apply lease, journals `IntegrationApplyIntent`, and persists a
   content-bearing apply effect.
2. Startup recovery dispatches that effect, records the exact apply receipt,
   releases the lease, and marks the apply envelope complete.
3. The candidate is materialized and the deterministic verifier activation is
   journaled.
4. `JournaledProcessRuntime.admitAndLaunchPostimageVerifier` checks the
   non-serializable `AuthorizedKernelResidentMemoryEnforcement` before runtime
   admission. Release has no production issuer, so it throws
   `residentMemoryEnforcementUnavailable` before creating a verifier lease.
5. Recovery correctly reports one unresolved integration transaction, but the
   outbox contains no executable rollback effect. The workspace therefore
   remains changed at `appliedUnverified` until a separate caller supplies a
   complete rollback request.

This is a systemic convergence failure: a mandatory downstream capability is
tested after the canonical effect it protects. Attention telemetry is honest,
but telemetry alone is not safe recovery.

## Evidence boundary

- `KernelResidentMemoryEnforcement.swift` has no Release issuer. Its exact
  source hash is
  `37f06153d90254cf07fbe76d49bc0b4f089c816ff0dad6f4607aa2362bbabcd8`.
- `JournaledProcessRuntime.swift` checks that capability before verifier
  admission. Its current source hash is
  `5092d47dec4c7054f353cac0be4ded8cf8a323b4d34777312ee52a563a9aec53`.
- `WorkspaceCompletedCandidateMutationApplyPreparation.swift` persists the
  canonical apply effect without a verifier-containment readiness proof. Its
  current source hash is
  `cf0aca7841def84225f89715806331cad6ccc14578a72500f413840f4e4eb71c`.
- `WorkspaceMutationRecoveryCoordinator.swift` replays only already-persisted
  apply or rollback envelopes; it does not derive a rollback envelope from an
  unlaunchable verifier activation. Its current source hash is
  `4055161a3c56cf3871a72643fd108f68a029e5a4b79bcc5ff5e86096c707cc66`.
- The exact completed-candidate production test proves the veto creates no
  verifier lease or launch and leaves the integration at
  `appliedUnverified`. Its current source hash is
  `0cf48543f00674dab775f22cec5b9caf6e1fde1d6587698b5bb4f8922f2bda4f`.
- EasyBusiness remained read-only at exact HEAD
  `2ae40452e6d8661c46db466c43ea40bba3bfab04` during this audit.

## Rejected shortcuts

The following are not acceptable repairs:

- treating `RLIMIT_RSS`, `RLIMIT_AS`, parent polling, or ordinary-process
  jetsam attributes as a hard physical-footprint ceiling;
- minting a rejected `IntegrationPostimageVerificationReceipt` when no
  verifier ran;
- reusing the expired/released apply lease for rollback;
- constructing rollback bytes from the live workspace instead of the exact
  preflight manifest and durable recovery artifact;
- changing `appliedUnverified` to a successful terminal phase;
- enqueuing rollback before its new exclusive lease and rollback intent are
  journaled;
- allowing a registry entry, model message, or legacy task snapshot to mint
  rollback authority.

Each shortcut either falsifies evidence, admits a race, or invents mutation
authority after the user-ratified transaction.

## Required two-part correction

### 1. Pre-apply containment readiness

Before the canonical apply lease or intent can be issued, the production
apply-preparation boundary must resolve every executable postimage recipe and
prove one exact launch-containment route. On ordinary macOS, where the required
resident-memory capability has no issuer, apply preparation must fail before
any canonical mutation, journaled effect, or outbox entry.

This gate must bind the run, contract revision, candidate transaction,
evidence-recipe identities, executable identities, and each resource ceiling.
It cannot be a Boolean feature flag or host-brand check. A future privileged
helper or container issuer may satisfy it only with an unforgeable capability
whose enforcement is installed before target exec.

### 2. Recovery for already-applied journals

Historical and crash-recovered runs may already be `appliedUnverified`, so a
pre-apply gate is insufficient. The runtime needs a durable, fail-red verifier
launch-veto receipt that binds:

- run, activation, apply, integration transaction, attempt, recipe, verifier,
  and source revision;
- the exact unavailable containment dimension and required byte ceiling;
- the unchanged activation journal frame and proof that no matching launch or
  verifier lease was accepted;
- runtime-owned observation time and a content digest of the veto reason.

A separate recovery coordinator may then consume only that accepted veto plus
the exact completed apply envelope and projected integration state. It must:

1. reload and validate the original apply request from the registered outbox;
2. require its completed state and exact match to the reducer-accepted apply
   receipt, preflight, rollback manifest, recovery artifact, workspace, actor,
   and transaction;
3. acquire a fresh exclusive rollback lease with a new identity and bounded
   lifetime;
4. derive `IntegrationRollbackIntent` from those retained facts;
5. journal `requestRollback` before persisting the rollback envelope;
6. replay the same intent and command identities across every crash window;
7. dispatch through the existing bounded rollback executor;
8. accept only exact preimage restoration, otherwise retain
   `rollbackFailedQuarantined` and the recovery artifact.

The coordinator must never derive rollback from activation absence alone:
absence can mean the launch was never attempted. The typed veto is the missing
causal receipt.

## Crash matrix required before acceptance

The implementation is not acceptable until native tests cover:

- veto before any verifier admission;
- crash after veto journal append;
- crash after rollback lease admission but before rollback intent;
- crash after intent but before outbox enqueue;
- crash after enqueue but before filesystem entry;
- crash after recovery-artifact creation and during partial rollback;
- restart after restored rollback with zero executor reentry;
- duplicate veto and duplicate rollback request exact replay;
- mismatched activation, apply receipt, recovery artifact, workspace,
  registration, actor, command, or lease rejection;
- unrelated workspace drift producing quarantine rather than overwrite;
- no live process or workspace lease after every terminal path.

## Acceptance consequence

No production resident-memory issuer was created and no rollback authority was
invented in this interval. The existing verifier/reviewer launch veto remains
correct. Final acceptance stays false. The next safe implementation slice is
the journaled launch-veto receipt and exact already-applied rollback recovery,
followed by moving containment readiness ahead of canonical apply.
