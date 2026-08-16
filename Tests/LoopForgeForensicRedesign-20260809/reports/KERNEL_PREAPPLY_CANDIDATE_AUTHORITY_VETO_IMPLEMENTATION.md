# Pre-apply candidate authority and acyclic preflight veto

Recorded 2026-08-12T11:01:58Z. Final acceptance remains false.

## Structural defect confirmed

The next manifest/preflight audit proved that the retained candidate-byte chain
is post-apply: `WorkspaceJournaledCandidateContentCaptureReceipt` requires an
exact accepted integration apply, and its materializer consumes the attestation
from that event. Integration apply, however, requires an accepted preflight.
Those receipts therefore cannot be reused as the pre-apply source from which a
manifest is assembled. Doing so would create circular authority.

The same audit found that productive worker activation still bound a
`workspaceOnly` sandbox to the canonical workspace. A mutation-capable contract
could consequently report zero readiness blockers and enter an executing
session even though no journal-owned isolated candidate workspace, acyclic
manifest assembly, or production proposal/preflight issuer exists.

## Enforced boundary

`KernelPlanProposal.requiresWorkspaceMutation` now derives mutation capability
only from typed writable paths and file/byte budgets. Objective prose and
action labels cannot downgrade it. `TaskContract.requiresWorkspaceMutationAuthority`
conservatively includes the contract write ceiling, retained mutation budget,
and retained plan.

Mutation-capable readiness now retains two explicit blockers:

- `preApplyCandidateIsolationAuthorityMissing`; and
- `journaledMutationPreparationAuthorityMissing`.

The production composition coordinator rejects mutation before reducer
preparation, and the lower-level activation boundary repeats the same fail-closed
check before `startAttempt`. A rejected start appends no plan, node, attempt, or
process event. Contracts with an exact read-only plan, zero write ceiling, zero
file/byte budget, zero convergence mutation cost, read-only worker sandbox, and
zero attempt mutation cost remain eligible for the existing read-only session.

This slice does not issue candidate isolation, manifest, preparation facts,
proposal, preflight, filesystem-effect, publication, or native-start authority.

## Verification

- focused enrollment/readiness/composition tests: 31 passed, 0 failed;
- split main suite: 752 tests, 8 intentional environment skips, 0 failures;
- independently bounded process-group resistance case: 1 passed;
- combined coverage: 753 tests, 8 skips, 0 failures;
- Release LoopForge SHA-256: `df8f527a26cdde6e2c3bb20d42a2098d2b0ce61fa35fd933a2261359c78d05fa`;
- Release KernelSandboxGate SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`;
- source snapshot before report reconciliation: `03bbefcab0cc8469d4f4642799cfed0ce32a5ee07b4a6121aa21124c42e75325`;
- `git diff --check`, owned test-process cleanup, and the unchanged read-only
  EasyBusiness fingerprint passed.

The first read-only fixture run failed because its convergence and attempt
mutation costs remained non-zero. It was corrected and rerun, but that failed
diagnostic, all tests/builds, waits, polling, and reporting are excluded from
the strict ledger.

## Still blocked

A journal-owned candidate-isolation/materialization authority must run before
canonical apply, produce content-complete candidate bytes independently of an
apply receipt, and feed an acyclic chain for delta, content store, manifest,
preparation facts, rollback rehearsal, proposal, and preflight. Resident-memory
authority, native design/visual authority, final authorization, publication,
native start/UI, current-source packaging/signing, clean commit, and push also
remain blocked.
