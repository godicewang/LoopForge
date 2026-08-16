# Kernel postimage verification issuance and latest-red revocation

Recorded at: `2026-08-12T02:30:29Z`

## Outcome

LoopForge now converts a live, journal-bound schema-v4 postimage result into an ordinary `VerificationReceipt` without letting durable result bytes, a model response, or caller-selected receipt fields authorize that conversion.

`JournaledProcessRuntime.recordPostimageVerification` accepts only the non-serializable result capability returned after exact release commit/readback. It independently re-reads the non-duplicate release transaction and reconstructs activation, launch, integration, apply, attempt, requirement, source-revision, verifier, process-environment, and oracle bindings from journal state. The caller supplies only a command ID. Receipt identity, result, requirements, source, environment, oracle, release ordering, and evidence-set identity are deterministic.

The v2 canonical evidence batch binds:

- the content-addressed postimage result ID and its evidence digest;
- exact release receipt and command IDs;
- exact release ending sequence and frame digest;
- attempt and sorted requirement IDs;
- source revision, environment digest, oracle digest, and outcome.

Reducer admission recomputes the full batch digest. A valid-looking stored SHA-256 cannot hide a changed result, release sequence/frame, requirement set, source, environment, oracle, or outcome. Legacy receipts remain decodable; once a v2 red exists for an exact attempt/requirement/source/environment/oracle identity, a legacy green cannot remain a fallback.

For each exact verification identity, a later release-sequence red revokes every earlier green. A newer green can restore verification authority, but cannot reuse the old independent review. `IndependentReviewReceipt` now has a separate optional `verificationEvidenceSetDigest`; this preserves the reviewer's own evidence digest while binding any v2 review to the exact green batch. A red demotes a previously accepted node back to `awaitingVerification`. Integration preflight also refuses referenced verification receipts that are no longer effective.

## Native and adversarial proof

- The real journal/integration scenario ran the ratified verifier through the native read-only/offline sandbox, produced the exact natural-exit accepted result, issued the derived v2 verification event, read it back from its exact transaction, and proved duplicate command replay returns the identical event.
- The integration transaction remained `appliedUnverified`; ordinary verification does not authorize the separate integration state machine.
- Deterministic authority tests prove exact batch reproduction and reject duplicate/cross-wired releases, cross-wired result IDs, and release-sequence tampering.
- Reducer tests prove latest-red revocation, oracle isolation, legacy-green suppression, newer-green restoration, node demotion, and mandatory review rebinding.
- Complete Swift suite: **715 tests executed, 8 intentional environment skips, 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds passed.
- Source snapshot SHA-256: `2a51935fae8030ac4f7ce8f9687105dc3b1d6285abd60eed68788463d3e4927d`.
- Release `LoopForge` SHA-256: `df95c69a9463160125d09ace39d7bcefbfddbf23037dc45993d5d291d05fa095`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Diff whitespace check passed; no Swift build or verifier process remained.
- EasyBusiness status fingerprint remained unchanged and read-only.

## Boundary retained

No independent-review production issuer exists. No v2 verification fact advances `IntegrationTransactionStateMachine`, publishes a candidate, authorizes final completion, or enables native start. Per-child resident-memory enforcement and descriptor-atomic candidate handoff remain unresolved. Native design-baseline selection, complete visual evidence, executable external-dependency observation, legacy Single/Parallel retirement, current unlocked native UI verification, package/sign, clean commit, and push remain vetoed.

Final acceptance remains false.
