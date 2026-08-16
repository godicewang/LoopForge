# Kernel Postimage-Verifier Activation Implementation

Recorded: `2026-08-11T23:18:31Z`

Status: **journaled independent postimage-verifier activation implemented; process admission/spawn, output interpretation, verification verdicts, latest-red revocation, independent review, and native start remain vetoed**

## Outcome

LoopForge can now activate one exact retained executable verification recipe against one exact journal-attested and materialized candidate postimage after an integration transaction reaches `appliedUnverified`. The resulting live `AuthorizedKernelPostimageVerifierInvocation` is non-Codable, retains the candidate-input capability, and is bound to a reducer-accepted journal transaction.

This is deliberately not the ordinary preflight `VerificationReceipt` path. Ordinary candidate verification is a prerequisite for integration proposal and preflight; the journal-owned candidate-postimage attestation exists only after apply. Treating the new evidence as ordinary verification would create circular authority. The activation therefore belongs to the post-apply integration phase and leaves that phase exactly `appliedUnverified`.

No verifier process is started. No captured output is read. No parser or result mapping is evaluated. No `VerificationReceipt`, integration postimage-verification receipt, review receipt, green verdict, or completion fact is issued. EasyBusiness remained read-only.

## Activation authority

- Release callers cannot construct `AuthorizedKernelPostimageVerifierActivation`; the coordinator is the only production issuer accepted by the reducer.
- The run must be in `evaluating`, the exact attempt must have a completed disposition eligible for verification, and the exact integration transaction must be `appliedUnverified`.
- The verifier lineage must differ from both the worker lineage and the apply executor lineage.
- The retained contract must contain exactly one recipe with the requested ID, that recipe must own a requirement on the attempt, require independent lineage, and carry a valid executable probe.
- This slice accepts exactly one `candidatePostimage` input binding. Other input kinds or additional bindings fail closed until typed capability issuers exist.
- The probe's environment identity must equal the implemented four-variable minimal kernel environment identity.
- The probe's capture identity must equal the implemented private, bounded, no-stdin, no-shell capture policy identity.
- Run directories are created and tightened to owner-private mode before candidate or executable artifacts are accepted.

## Exact candidate and executable binding

The coordinator resolves the newest unambiguous candidate-postimage attestation from `RunJournal` for the exact workspace and compares its apply receipt, source revision, capture policy, and journal frame with the retained non-serializable candidate capability. It then fully revalidates the materialized candidate snapshot.

The exact verifier executable is copied or cloned into the owner-private journal run directory under its expected SHA-256 and independently rehashed. Candidate substitution replaces only the declared token in the fixed argument vector; no shell is involved. The receipt binds:

- run, integration transaction, apply, attempt, requirement, and recipe identities;
- candidate input binding and artifact identities;
- candidate materialization receipt and source revision;
- verifier and worker lineage identities;
- staged executable path, SHA-256, byte count, device, and inode;
- canonical executable-probe digest;
- resolved argv and canonical argv digest;
- environment and capture identities;
- parser and resource-limit contracts; and
- the exact live journal-head sequence and frame digest observed immediately before activation.

The reducer rechecks the complete relationship and rejects duplicates. A single recipe cannot be activated twice for the same applied transaction.

## Live journal-head correction

The first full-suite run exposed that `recoveryReport.lastFrameDigest` describes startup recovery and is not advanced by live journal appends. That failed run was excluded from the ledger. The coordinator now obtains an actor-isolated `JournalHeadSnapshot` containing the live state sequence and live last-frame digest, requires it to equal the earlier reducer snapshot, and carries both into the activation receipt. A concurrent journal advance therefore rejects safely rather than binding a stale or unrelated frame.

## Verification

- focused integration/replay test: **1 passed, 0 failed**;
- complete discovered Swift matrix: **702 tests**;
- complete Swift execution: **702 executed, 8 environment-gated skips, 0 failures**;
- non-DEBUG arm64 Release builds (`LoopForge` and `KernelSandboxGate`): **passed**;
- exact source snapshot: `af8926e8dc0d76daa1a908cd9217554673ca2da19ab444a69dbe9ba739dfccb3`;
- Release `LoopForge` SHA-256: `0f25799d8b245f477b55309590885c39c4f8000e2ddfe97c6626e4602706b094`;
- Release `KernelSandboxGate` SHA-256: `0e29463be4377b4d21c463e7ddb63e6256dd76abf30ff1690f0c5a482e985227`;
- diff whitespace validation: **passed**;
- owned Swift build/test processes after verification: **0**;
- EasyBusiness read-only status: **unchanged**.

The focused test rejects apply-executor self-activation, accepts an independent verifier, proves exact candidate and executable binding, resolves the exact activation event from its journal transaction, proves the ordinary verification map is unchanged, proves the integration phase remains `appliedUnverified`, rejects duplicate activation, and replays the receipt from disk.

All test/build execution, polling, waits, failed runs, and blocked time are excluded from the strict active-work ledger.

## Remaining stop-the-line dependencies

This closes activation-contract authority, not deterministic verification. Production verification and native start remain vetoed until LoopForge adds:

1. a journaled verifier process lease and runtime owner;
2. atomic candidate and executable revalidation composed with admission and spawn;
3. OS enforcement of wall-clock, captured-output, resident-memory, child-process, network, stdin, and environment limits;
4. bounded private stdout/stderr capture bound to the activation and native exit;
5. canonical parser execution and exact result-mapping/oracle evaluation;
6. a non-forgeable postimage verification result receipt bound to the complete chain;
7. latest-red revocation for the exact verification identity and journal sequence;
8. a canonical evidence batch; and
9. separately activated read-only independent review of that exact batch.

No package, commit, push, native walkthrough, or final acceptance is claimed.
