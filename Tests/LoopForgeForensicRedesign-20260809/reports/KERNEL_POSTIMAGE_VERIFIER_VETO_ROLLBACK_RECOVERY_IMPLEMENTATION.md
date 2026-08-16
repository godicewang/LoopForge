# Postimage-verifier veto rollback recovery

Recorded: 2026-08-14T13:05:24Z

Status: implemented and verified for already-applied transactions; the later
pre-apply containment gate is also enforced, while its Release issuer remains
unavailable.

## Boundary closed

Startup recovery can now convert one exact reducer-accepted resident-memory
launch veto into an exact rollback of the already-applied candidate. It does
not infer failure from an absent launch, invent verification evidence, inspect
EasyBusiness, or derive restoration bytes from the live workspace.

`WorkspacePostimageVerifierVetoRollbackPreparationCoordinator` scans only
transactions whose reducer phase is `appliedUnverified`. It requires exactly
one matching accepted veto, the exact retained activation, no launch for that
activation, one completed source apply envelope, and exact registration,
actor, workspace, preflight, rollback-manifest, apply-intent, apply-receipt,
recovery-artifact, and root-identity bindings.

The retained apply request supplies the original content-complete preimage,
manifests, recovery root, executor, and limits. The coordinator admits a fresh
exclusive rollback lease and persists a rollback request in the registered
external outbox. Its lease, admission, intent, dispatch, release, and failure
identities are deterministic SHA-256 functions of the run, transaction, apply
receipt, and veto receipt. A crash after admission or enqueue therefore
replays the same authority and payload rather than minting a second rollback.

The ordinary dispatcher remains the only component that journals
`requestRollback` before filesystem entry. Successful restore records the
reducer-owned rollback receipt, releases the fresh lease, completes the outbox
envelope, and makes the next startup recovery a zero-effect no-op.

## Systemic defects found and corrected

Three cross-component assumptions prevented the rollback from converging:

1. Effect completion digests used a generic encoder even though receipts may
   contain semantically unordered collections. The dispatcher now uses the
   outbox canonical codec for durable receipt identity.
2. A completed-candidate apply receipt records the full policy-bound source
   revision, while rollback compared only the affected-path digest. Rollback
   now recaptures the full current source revision under the exact recorded
   policy and limits; policy or digest drift quarantines.
3. Supervisor restore rejected a fresh rollback lease merely because a
   different, durably released apply lease named the same workspace resource.
   Restore now distinguishes lease identities while still rejecting live and
   released identity overlap or duplicate live resource ownership.

The veto is terminal for its exact activation. The reducer and process runtime
reject a later launch even if a caller later obtains a matching memory
capability, preventing a post-veto process side effect.

Full-suite verification exposed another lifecycle defect: `kill -0` treats a
zombie as present, so the executable startup probe could false-pass a crashed
child. The probe now observes process state, treats absent or zombie children
as early exits, reports the real status, and still reaps accepted live children.

## Crash replay verification

The completed-candidate production test proves apply, typed veto, fresh lease,
pending rollback, crash/reopen, duplicate exact preparation, production
dispatch, exact baseline restoration, reducer phase `rolledBack`, complete
lease cleanup, and a zero-effect second recovery in a synthetic registered
workspace. A dedicated supervisor test proves same-resource reacquisition only
after a distinct prior lease is durably released. Integration tests prove a
vetoed activation remains unlaunchable and creates no process lease.

## Verification

- Exact final-source suite: 767 tests, 8 intentional environment skips, zero
  failures, 63.824 test seconds.
- Focused executable-probe regression passed and reaped its live child.
- Release build passed in 97.55 seconds.
- Diff whitespace and owned Swift/process cleanup passed.
- EasyBusiness remained read-only at exact HEAD
  `2ae40452e6d8661c46db466c43ea40bba3bfab04`.

Two diagnostic full-suite runs exposed the zombie-observation defect and
counted zero. Only the corrected focused run and final complete run count.

## Exact source identities

- `WorkspacePostimageVerifierVetoRollbackPreparation.swift`: `3d2f9cb312dbe1ff9896ada01e5fa88ac77df004724a477b1416a21be5fbc7c3`
- `WorkspaceMutationRecoveryCoordinator.swift`: `338efae91ed0de277d3bb04ffff59cf0612452e41dc3f1c8ab453d923c7f9407`
- `WorkspaceMutationEffectOutbox.swift`: `1e95899d9daec8564b3c4f80a4bcd3cc36d1d26ba892d8e14d1e1c69285c5968`
- `JournaledWorkspaceMutationRuntime.swift`: `2821e651411d46acea7a61a53384702583cad79636023f2f7175d2164a60e75f`
- `WorkspaceMutationFilesystemExecutor.swift`: `348e59ac130046f227bbcd4faac72caac38f7138b5bae78e8585bb7b8c86a71f`
- `RuntimeSupervisor.swift`: `ca1ee26d4ecf2517ae3c5de301e7ca8b9a5fb98791a5a68390c80325dec1ffa7`
- `RunReducer.swift`: `bad6f7001091a46dc8ea44f75469858dc875d6d03426914aa95918d2d80dc480`
- `JournaledProcessRuntime.swift`: `31530b666438bd2f875339409111f6e22821bec83e7aec32d99ba455f4f40bec`
- `probe_executable_startup.sh`: `f77b60991b2313c5567c6d3570a47c56646b2fbe58c1e040554d56b8d7e64f2a`
- Release executable: `06cfe1ce175f77a8c1e01e1851ab7956a56d3d951bb2bff9dafed5de3b6c497e`

## Remaining safety boundary

Future canonical apply is now gated before lease admission by the exact
non-serializable containment-readiness capability. No ordinary-macOS Release
issuer exists, so the production result is a pre-apply veto with no canonical
mutation. A tested privileged/container resident-memory issuer remains the
only route to safely opening that gate.

Native immutable design/visual authority, final authorization, production
kernel cutover, current-source package/sign/hash, unlocked native verification,
clean commit, and push also remain pending. Final acceptance remains false.
