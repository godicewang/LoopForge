# Kernel integration reliance

Recorded at: `2026-08-12T04:36:46Z`

## Outcome

LoopForge now composes the ordinary postimage-verification fact and the separately issued independent-review fact into the integration transaction without granting publication or final-completion authority.

`JournaledProcessRuntime.recordIntegrationPostimageVerification` consumes the original non-serializable verifier-result capability and the exact journaled v2 verification identity. It reconstructs the current `appliedUnverified` transaction, apply receipt, complete attempt requirements, source revision, result/release transaction, verifier, and evidence batch. The resulting integration receipt records the exact ordinary verification receipt and uses that verifier release as the process-ended receipt; no caller supplies a verdict, evidence digest, postimage, actor, or timestamp.

`recordIntegrationIndependentAcceptance` consumes the original non-serializable reviewer-result capability and the exact journaled independent-review identity. It reconstructs the separately activated schema-v4 reviewer result, the ordinary verification batch reviewed by that result, integration/apply/source/requirement lineage, reviewer identity, and evidence digest. Approval or rejection is derived deterministically from the journaled review decision. A verifier capability cannot substitute for the reviewer capability, and a reviewer capability cannot substitute for the verifier capability.

Integration commands now carry their issuer class. The workspace-mutation runtime may issue only apply and rollback transitions; the process runtime may issue only postimage-verification and independent-acceptance transitions. Reducer replay independently reconstructs the complete source verification and review chains rather than trusting receipt shape. A later effective red verification automatically demotes a relying `postimageVerified` or `independentlyAccepted` transaction to `rollbackRequired`.

## Proof

- The real native journal scenario advanced the exact applied transaction through ordinary verification, separate adversarial review, integration postimage verification, and independent acceptance, then replayed the same `independentlyAccepted` state from disk.
- Negative capability-substitution paths fail at the earlier verifier-authority boundary.
- `permitsPublication` remains unconditionally false for every integration phase.
- Five result-authority tests, eight integration tests, 28 journaled-runtime tests, and 40 reducer tests passed in focused or whole-suite runs.
- Exact final-source split coverage passed: **718 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **719 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds passed before the test-only adversarial assertion change; product source did not change afterward.
- Release `LoopForge` SHA-256: `597ba7dd98995f5b8aeb873beb09d9efcfd77ea66d9f421d3cb1915ec696288a`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `c4341edbd0d89ee81fcdc9b300d8728918deaba9d3433a3d780bf7b9c8005318`.
- Diff whitespace, process cleanup, and the read-only EasyBusiness fingerprint passed.

## Boundary retained

This slice does not create integration proposal/preflight production issuers, a publication transition, final authorization, executable external-dependency observation, native immutable design-baseline authority, complete native visual evidence, or native start. Production verifier/reviewer launch still fails closed because Release has no tested resident-memory enforcement issuer. Historical Auto Graph remains permanently stopped; legacy Single Loop and Parallel Candidates remain uncut-over. Current-source package/sign, unlocked native UI verification, clean commit, and push remain pending.

Final acceptance remains false.
