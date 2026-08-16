# External-Dependency Journal Observation Issuer

Status: **a live release-bound result can now become one exact hash-journal observation; native observer launch remains vetoed on ordinary macOS**

Recorded: `2026-08-15T12:54:37Z`

## Result

LoopForge now closes the authority gap between the process-runtime-only
external-dependency result capability and the reducer's durable observation.
`ExternalDependencyObservationJournalCoordinator` accepts only the
non-Codable `AuthorizedExternalDependencyObservationResult`, re-resolves the
active attempt, exact activation, ratified dependency and executable probe,
and then revalidates the complete release-bound result authority.

Before append it independently requires the exact release transaction and its
single-event hash-journal frame. The observation is derived from the strict
parse and declared mapping rather than supplied by a caller. Its durable
receipt records the source result ID, result evidence-set digest, release
receipt ID, and release-frame digest. A file-owned issuer token is required to
form the reducer command, so ordinary production callers cannot construct
observation command authority from decoded receipts.

Exact command retry returns the retained transaction only when its single
event equals the newly derived observation. A prior observation for the same
attempt/dependency, a launch veto for the activation, forged mapping evidence,
substituted release evidence, stale attempt state, or mismatched readback all
fail closed. Journal close/reopen replay retains the exact observation and
provenance without reconstructing the live result capability.

## Compatibility boundary

The four provenance fields are optional only so older journals remain
forensically replayable. Every observation produced by this new production
issuer carries all four fields, and the reducer rejects partial provenance,
invalid SHA-256 digests, or release/frame references absent from current
state. Legacy decoded observations remain inert evidence; they cannot mint the
non-Codable result or journal-command capabilities.

## Verification

- the new full synthetic journal integration test passed **1 test** with
  **0 failures** in **0.028 seconds**;
- the exact source suite passed **806 tests**, with **8 intentional skips** and
  **0 failures**, in **58.240 test seconds**;
- the package-owned suite passed **806/8/0** in **56.055 test seconds**;
- the real Codex child/Responses bridge passed in **12.994 seconds**;
- non-DEBUG arm64 Release built in **102.82 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, and cleanup passed;
- source snapshot:
  `1202013e297e0ab265cf357d94a98d25994be09a04481f5bcb2ab0ac56be8f6b`;
- packaged LoopForge SHA-256:
  `d2d7a8e1bfcace15deff112f759aa34c45187b70cfe3556acb6a68c0bb93dcdc`.

## Boundary

This interval does not claim a production observation was executed. The test
uses the explicit test-only synthetic runtime chain to prove the coordinator,
retry, forgery rejection, and replay boundaries. Ordinary macOS still has no
trusted Release resident-memory issuer, so production retains the typed
pre-admission veto and creates no observer process.

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its newline-delimited `-uall`
status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or the retained veto,
journal-owned native launch and retained-output/release composition,
production-controller invocation, legacy retirement, current unlocked native
screenshots, a clean-commit rebuild, commit, and push remain required.
