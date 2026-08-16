# Deterministic Verification Issuer Prerequisite Audit

Recorded: `2026-08-11T21:57:57Z`

Status: **confirmed stop-the-line architecture gap; production verifier issuer and native start remain vetoed**

## Decision

LoopForge cannot honestly add a production verification issuer from the current retained contract. The existing non-Codable verification authority is an effective receipt-injection boundary, but the data behind it is not yet an executable, independently attributable observation. Adding an issuer now would merely give production authority to worker prose or caller-selected receipt fields.

No LoopForge source, executable start path, or EasyBusiness file was changed during this audit. The exact-source 695-test and non-DEBUG Release receipts remain applicable because the source snapshot is unchanged at `4bf83237fce3658fece4df0687781f85f62e8222c43cc316c018879dade8bc47`.

## Confirmed gaps

1. **A retained evidence recipe is descriptive, not executable.** `TaskContractCompiler.swift:110-123` retains a recipe ID, requirement ID, verifier kind, expected-observation prose, and independent-lineage flag. It does not retain an executable/content digest, fixed arguments, input-artifact bindings, pinned environment, capture identity, parser/schema, deterministic result mapping, or resource bounds.
2. **A verification receipt is not recipe- or runtime-bound.** `RunReducer.swift:244-258` retains requirement IDs, source revision, environment, oracle, and result, but no recipe IDs, verifier actor/lineage, executable/probe identity, output evidence chain, parser identity, or journal sequence.
3. **The command-authority boundary is correctly fail-closed but has nothing deterministic to authorize.** `RunReducer.swift:271-287` makes verification authority non-Codable and provides no Release issuer. That prevents decoded or model-produced receipts from issuing facts; it does not establish the missing observation chain.
4. **A later red does not revoke an older green.** `RunReducer.swift:548-565` accepts a requirement when any historical accepted verification exists. Ordinary verification has no latest-by-identity rule, while visual evidence at `RunReducer.swift:567-595` already demonstrates journal-sequence supersession.
5. **Reducer validation is structural rather than evidentiary.** `RunReducer.swift:1461-1491` checks duplicate IDs, known attempts, requirement subsets, substitution, and collection cardinality. It does not require exact recipe binding, validate source/environment/oracle digests, bind an independent verifier context, validate executable output, or apply latest-red revocation.
6. **Independent review is not grounded in an exact evidence batch.** `RunReducer.swift:1493-1516` checks a prior accepted verification and reviewer lineage, but the review's `evidenceDigest` is not validated against a journal-owned verification batch or retained runtime evidence.
7. **Integration consumes ungrounded postimage claims.** `RunReducer.swift:2038-2079` compares proposal, verification, and review source revisions, but those receipt fields are not derived from a journal-owned candidate source-tree attestation. Equality here proves receipt consistency, not the actual postimage.
8. **Worker result parsing cannot substitute for candidate attestation.** `KernelWorkerResultParser.swift:46-67` explicitly retains only an untrusted `proposedResultDigest`. `JournaledProcessRuntime.swift:818-869` derives execution disposition from parsed receipts but does not attest a source tree or candidate postimage.

## Required causal prerequisites

The next implementation must close these dependencies in order:

1. Define a canonical executable verification recipe with an exact staged executable/content digest, fixed argv, explicit input-artifact bindings, pinned minimal environment and capture identity, parser identity/schema, deterministic output-to-result mapping, byte/time/resource ceilings, and shell/remote denial by default.
2. Produce a journal-owned candidate source-tree/postimage attestation at the mutation/executor boundary. A worker's proposed digest is never candidate authority.
3. Activate the verifier under a separate journal-owned process lease and actor lineage, independent from the worker and later reviewer.
4. Give verification an exact identity and journal sequence. A later red revokes older green evidence for that identity; a later green may supersede the red only for the exact same recipe, candidate, environment, and oracle identity.
5. Bind the verification receipt to the exact recipe IDs, staged process/release identity, captured output, parser, candidate revision, environment, oracle, and journal transaction.
6. Form a canonical verification-evidence batch digest. Only a separately activated, read-only independent reviewer may consume that exact batch.

## Veto

Until all six prerequisites are implemented and adversarially verified:

- no production verification issuer;
- no independent-review issuer;
- no integration preflight relying on verification green;
- no native start action;
- no package, commit, or push presented as final acceptance.

EasyBusiness remains permanently stopped and read-only.
