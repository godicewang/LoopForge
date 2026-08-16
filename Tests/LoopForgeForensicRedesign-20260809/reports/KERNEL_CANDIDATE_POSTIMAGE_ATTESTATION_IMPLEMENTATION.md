# Kernel Candidate-Postimage Attestation Implementation

Recorded: `2026-08-11T22:36:52Z`

Status: **journal-owned candidate source-tree attestation implemented; immutable input materialization, verifier runtime, receipt chain, latest-red verification, review, and native start remain vetoed**

## Outcome

LoopForge can now distinguish an affected-path mutation digest from the exact content-complete workspace revision a deterministic verifier is allowed to inspect.

An exact apply may carry a full `WorkspaceSourceRevisionArtifact`, but that executor evidence has no authority by itself. Only `RunJournal`, after matching the exact reducer-accepted `applyRecorded` payload to recovered journal bytes and confirming that it is the newest unambiguous workspace transition, can issue the opaque `WorkspaceCandidatePostimageAttestationReceipt`.

No verifier process was launched, no verification receipt was issued, no native start action was added, and EasyBusiness remained read-only.

## Policy and capture boundary

- `WorkspaceCandidatePostimageCapturePolicy` retains the unique sorted exclusion set and finite file/total/file-size limits used by the existing content-complete collector.
- `IntegrationApplyIntent` seals the policy digest before a workspace effect.
- `WorkspaceMutationExecutionRequest` must carry the matching policy; missing/extra/mismatched policy authority rejects before mutation.
- For a ratified native contract with a retained source revision, `RunReducer` requires the candidate policy digest to equal the user-confirmed baseline policy. Callers cannot silently exclude more directories or reduce limits after confirmation.
- After affected paths equal the manifest postimage and unrelated workspace state remains unchanged, the filesystem executor captures the complete included source tree while its exclusive cross-process mutation lock is still held.
- The candidate artifact binds workspace identity, canonical root, exclusions, limits, sorted paths, permission modes, sizes, per-file SHA-256 values, total bytes, policy digest, and revision digest.
- Exact replay recaptures and compares the same candidate revision. Capture failure cannot produce an exact attested apply.

Legacy intents and receipts without a policy remain decodable for recovery, but they cannot produce candidate-postimage attestation authority.

## Journal authority and revocation

`RunJournal` now retains the candidate artifact and apply receipt ID only in the exact accepted mutation-generation event. The public receipt has a private initializer and binds:

- workspace identity and canonical root;
- the validated content-complete candidate artifact;
- the exact apply receipt ID; and
- the command, event IDs, sequence range, and frame digest of the accepting journal transaction.

Attestation is withheld when the newest workspace transition is:

- an apply or rollback still in flight;
- a failed or in-doubt apply;
- a failed rollback;
- a restored rollback;
- an exact legacy apply without the full candidate artifact; or
- otherwise ambiguous.

The resolver never falls back to an older green candidate after newer workspace activity. Journal replay reconstructs the same attestation from exact durable facts.

## Verification

- candidate executor and outbox matrix: **14 passed, 0 failed**;
- integration/journal/recovery matrix: **8 passed, 0 failed**;
- complete Swift suite: **699 executed, 8 environment-gated skips, 0 failures**;
- non-DEBUG arm64 Release builds (`LoopForge` and `KernelSandboxGate`): **passed**;
- exact source snapshot: `db94931697d862a54edcebcdfdd3948b88ad6218934c27794537f1a222276daa`;
- complete-suite log SHA-256: `5c32e9667d464d8b7ee773c626d3a854eba22b96fd64e149eb9588250553b9d9`;
- Release log SHA-256: `211b8c4b264245f7c58ce712524d7432acd1e9c9312827df1e9f4916598656c4`;
- diff whitespace validation: **passed**;
- EasyBusiness read-only status: **unchanged**.

All test/build execution, failed attempts, polling, and waits are excluded from the strict active-work ledger.

## Remaining stop-the-line dependencies

This closes the second deterministic-verifier prerequisite, not the verification system. Native start and production verification remain vetoed until LoopForge adds:

1. immutable candidate input materialization or exact live-tree revalidation against this attestation;
2. a separately activated verifier process lease and independent actor lineage;
3. an exact receipt chain binding recipe, executable, argv/input artifacts, attestation, environment, capture, parser, output, oracle, and integration transaction;
4. verification identity and journal sequence with latest-red revocation;
5. a canonical verification-evidence batch; and
6. separately activated read-only independent review of that exact batch.

No package, commit, push, native walkthrough, or final acceptance is claimed.
