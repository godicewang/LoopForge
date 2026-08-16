# Kernel Verification and Review Command Authority

Status: **production receipt injection closed; deterministic verifier and independent reviewer issuers remain vetoed**

Recorded: `2026-08-11T18:55:51Z`

## Finding

The reducer validated verification and review receipt contents, but its command
surface accepted the durable `Codable` receipts directly. That distinction is
security-critical: a caller in the process could construct a matching actor,
lineage, revision, evidence digest, and approval decision, then submit the same
shape that replay legitimately decodes. Integration preflight and completion
subsequently consumed those receipts, so the downstream gates proved internal
consistency rather than the provenance of the verifier or reviewer execution.

`recordVerification` was weaker still: it did not bind the command context actor
at all. `recordReview` compared the receipt reviewer to the context actor and
required lineage separation, but the same caller could construct both values.

## Implemented fail-closed boundary

`RunCommand.recordVerification` now accepts
`AuthorizedKernelVerification`, and `RunCommand.recordReview` accepts
`AuthorizedKernelIndependentReview`. Both wrappers are:

- non-`Codable` and therefore impossible to recover from model or journal data;
- initialized only inside `RunReducer.swift`;
- unavailable to production callers because no Release issuer exists yet;
- constructible in DEBUG tests only, where all existing semantic reducer tests
  continue to exercise malformed, rejected, and accepted receipt cases.

The durable event and receipt schemas remain unchanged, so replay compatibility
is preserved. The reducer still performs the existing requirement, revision,
evidence, decision, worker-lineage, and reviewer checks after unwrapping the
authority.

This is deliberately not represented as verifier or reviewer completion.
Release code now cannot add new verification or independent-review facts until
a deterministic verification runtime and a separately activated, read-only
reviewer runtime mint these capabilities from exact journaled process and
retained-result provenance.

## Verification

- authority/reducer/integration/visual focused suite: **59 passed, 0 failed**;
- complete source suite: **684 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  executable count: **0**;
- EasyBusiness status was observed read-only and remained unchanged.

Source identities:

- `RunReducer.swift`: `4d6689c23c23de648bf4034879e17de5aee84f3e1fed2f7bf128d7df2cdd47c2`;
- `KernelRunReducerTests.swift`: `14b870bcbd7b4ef8f052acf83da60f932e6a4761dfaec4babc2b2cdc182eb7ef`;
- `IntegrationTransactionStateMachineTests.swift`: `6b5db157b96957a35151e5a08133d34858986ef2bdc2ed4e089414e91157ad3b`;
- `VisualGateJournalIntegrationTests.swift`: `a9138a04609224025b3af17ede70e0e5ca24ebe814c530fe5d9b0776b6637ea1`.

## Remaining vetoes

The deterministic verification issuer, independent reviewer activation and
issuer, visual candidate authority, integration acceptance authority,
occurrence/quiescence closure, completion authorization, native start action,
legacy Single/Parallel retirement, current-source package, unlocked native
proof, clean commit, and push remain absent. Final acceptance remains false.
