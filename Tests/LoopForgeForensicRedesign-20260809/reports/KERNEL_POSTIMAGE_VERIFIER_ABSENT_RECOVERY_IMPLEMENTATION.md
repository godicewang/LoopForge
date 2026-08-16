# Kernel postimage-verifier absent-process recovery

Recorded at: `2026-08-12T00:21:19Z`

## Outcome

The typed postimage-verifier completion path now closes the crash window in which the exact journaled verifier PID/start identity is already absent before a restarted runtime can observe a native exit. A fresh adapter may reattach only to the exact PID, process-group and system-start identity. When that identity is provably absent, completion does not invent an exit code or signal: it validates and hashes the bounded retained stdout/stderr files, publishes the permanently fail-red `recoveryProcessAbsent` disposition, and journals containment and lease release atomically.

If retained output cannot be validated after the crash, absence completion retains no output receipt and records a capture-failure digest. Both forms remain fail-red. The reducer accepts them only for the exact activation, launch, binding, resource, lease, limits and process-start identity, with no native exit or termination claim.

Generic process reconciliation now rejects postimage-verifier leases before reattachment or release. Only the exact verifier actor using the typed completion API can close this ownership boundary.

## Adversarial native proof

One test preserves an exact pre-completion journal snapshot and exercises two branches from the same launch evidence:

1. The live branch reaches its journal-derived wall deadline, terminates and reaps the exact process group, hashes retained output, and publishes wall-time containment.
2. The replay branch restarts from the pre-completion journal after that PID is gone. Generic reconciliation is rejected; typed completion proves exact absence, publishes no native exit, hashes the retained bounded streams, releases ownership, preserves integration as `appliedUnverified`, and replays identically.

This test structure proves recovery without weakening the already-tested live containment path or requiring a second verifier launch from one activation.

## Verification

- Focused live/absent journal test: passed.
- Complete Swift suite: **703 tests executed, 8 intentional environment skips, 0 failures**.
- Release `LoopForge` build: passed.
- Release `KernelSandboxGate` build: passed.
- Source snapshot SHA-256: `6794b9ba9a5a74ff35138b94a81dbe124ac8be6ba6b4fc0aa2b243541340c950`.
- Release `LoopForge` SHA-256: `83163e7affa5af25cfc75afcb032871dee8801cf7ba8e5a6f79416cd880ebe98`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Diff whitespace check: passed.
- Failed compile-only test attempt: excluded from the strict ledger.
- EasyBusiness status fingerprint: unchanged and read-only.

## Stop-the-line boundaries retained

- Resident memory remains a scheduling reservation, not enforced per-child RSS.
- Candidate handoff at spawn is not descriptor-atomic.
- No canonical parser, oracle, result receipt, latest-red revocation, canonical accepted evidence batch or independent review exists.
- Integration remains `appliedUnverified`; no native start exists.
- No current-source package/sign/native walkthrough, commit or push is claimed.

Final acceptance remains false.
