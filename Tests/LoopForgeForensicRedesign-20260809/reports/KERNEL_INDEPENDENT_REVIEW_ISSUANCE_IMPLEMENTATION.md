# Kernel independent-review issuance

Recorded at: `2026-08-12T04:11:21Z`

## Outcome

LoopForge now has a production issuer for an ordinary independent-review fact. It does not reuse the candidate verifier's activation or result, and it does not accept caller-constructed review fields.

A new `verificationEvidenceDigest` recipe input is legal only in a separately activated two-input adversarial probe. `KernelPostimageVerifierActivationCoordinator` resolves the caller's opaque verification receipt ID from current journal state, requires an accepted and still-effective v2 verification for the same attempt, requirement, source revision, integration transaction, and apply receipt, reconstructs its exact schema-v4 result, requires a reviewer lineage different from both the worker and the original verifier, and substitutes only the journal-owned evidence-set digest into the probe's exact argv token. The candidate input remains the descriptor-bound `.` object.

`JournaledProcessRuntime.recordPostimageVerification` now rejects every review-designated live result. `recordIndependentReview` accepts only the separate post-release live capability, re-reads its exact schema-v4 release, activation, reviewed verification, original result, integration, apply, source, requirement, and lineage bindings, then derives every `IndependentReviewReceipt` field. An accepted reviewer result maps to `approveCandidate`; a rejected result maps to `rejectCandidate`. Receipt identity, reviewer evidence, source revision, requirement set, decision, and reviewed evidence-set digest are not caller-selectable. Exact transaction readback is mandatory and duplicate command replay is content-checked.

## Native and adversarial proof

- The real journal/integration scenario first issued an accepted v2 verification from one verifier lineage, then separately activated an adversarial reviewer lineage over the same descriptor-bound candidate and the exact verification evidence-set digest.
- The real read-only/offline native reviewer exited naturally, produced a schema-v4 live result, failed when presented to ordinary verification issuance, and succeeded only through independent-review issuance.
- The exact review event was read back from its transaction, and integration remained `appliedUnverified`.
- Unit tests reject an argv digest substituted after activation and reject the two-input review probe when no journaled target verification identity is present.
- Five result-authority tests, 28 journaled-runtime tests, and the focused native journal scenario passed.
- A suite-order run stalled in an existing process-group resistance XCTest and was interrupted, counted as zero, and not described as passing. That exact test then passed independently. The remaining suite passed with **717 tests executed, 8 intentional environment skips, and 0 failures**. Combined coverage is 718 tests, 8 skips, 0 failures.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds passed.
- Release `LoopForge` SHA-256: `9fae7152bdc4e9831eca7c64cc2e3d1cad2f3fa3cc8727c5cca24a54411ea361`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Source snapshot SHA-256: `f0ac41f51f63e748555ee4536156822c3b585f1ae10f4da2a4361546bb9da59d`.
- Diff whitespace and relevant process cleanup passed; EasyBusiness status remained unchanged and read-only.

## Boundary retained

Independent review does not advance `IntegrationTransactionStateMachine`, publish a candidate, authorize final completion, or enable native start. Production verifier/reviewer launch still fails closed because the host has no tested resident-memory enforcement issuer. Integration postimage-verification and independent-acceptance issuers, native immutable design-baseline selection, complete visual evidence, executable external-dependency observation, final authorization, legacy Single/Parallel retirement, current unlocked native UI verification, package/sign, clean commit, and push remain blocked.

Final acceptance remains false.
