# Completed-candidate postimage activation replay

Recorded: `2026-08-14T11:33:49Z`

## Result

The production completed-candidate chain now continues from its exact
`appliedUnverified` receipt through real postimage-verifier activation. A
contract-authorized deterministic recipe, distinct verifier lineage, accepted
candidate-postimage attestation, content-addressed read-only candidate tree,
staged executable, descriptor-relative argument binding, and exact apply
receipt are all journal-bound in the same synthetic registered run.

The verifier is not launched on ordinary macOS because LoopForge still has no
production issuer for its required resident-memory enforcement capability. The
runtime veto occurs before admission: there is no verifier lease, launch
receipt, verdict, verification, review, acceptance, publication, or completion,
and the integration remains visibly `appliedUnverified`.

## Crash-continuation defect closed

Activation is journal-first, while its invocation is deliberately non-Codable.
Previously, a crash or retained resident-memory veto after the activation frame
could strand the transaction: the original live invocation disappeared, but a
second activation of the same recipe was rejected.

Exact activation replay now requires all of the following:

1. the same deterministic command ID, activation receipt ID, transaction,
   apply receipt, attempt, requirement, recipe, verifier, activation time, and
   journal-retained activation frame;
2. a freshly materialized, non-Codable candidate input whose complete immutable
   snapshot identity and attestation match the retained activation, even when
   the fresh observation correctly reports `existingArtifact` rather than the
   original materialization method;
3. the same staged executable path, digest, byte count, device, and inode;
4. no accepted launch for the activation; and
5. current reducer state still at `appliedUnverified` with the same exact apply.

Only then does the coordinator reissue a live invocation bound to the original
receipt and transaction. It appends no duplicate frame and cannot select a new
candidate or executable. Different IDs, actor, recipe, tree, executable,
activation time, launched activation, or stale phase remain fail-closed.

## Verification

- The exact completed-candidate scenario closes and reopens `RunJournal`,
  rematerializes the sealed tree as an existing artifact, replays the original
  activation without a new journal frame, and proves receipt/transaction
  identity.
- The production runtime then rejects launch with
  `residentMemoryEnforcementUnavailable` before creating a lease or launch
  receipt.
- The focused enrolled-chain test passes.
- The 48 enrollment, materializer, and integration tests pass.
- The complete exact-source suite passes 766 tests with eight intentional
  environment skips and zero failures in 60.132 test seconds (60.180 wall).
- The production Release build passes in 88.41 seconds.
- Diff whitespace and owned-process cleanup pass. EasyBusiness remains
  untouched read-only evidence at commit
  `2ae40452e6d8661c46db466c43ea40bba3bfab04`.

## Still blocked

LoopForge has not issued a production resident-memory capability, so neither
the verifier nor the distinct independent reviewer is allowed to launch. No
verification or acceptance is inferred from activation. The production
rollback/failure continuation, native immutable design/visual/final authority,
legacy Single/Parallel retirement, current native walkthrough,
package/sign/hash, clean commit, and push remain pending. Final acceptance is
false.
