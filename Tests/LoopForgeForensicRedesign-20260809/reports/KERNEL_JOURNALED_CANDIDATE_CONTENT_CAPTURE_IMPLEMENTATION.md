# Kernel journaled candidate content capture

Recorded: 2026-08-12T07:59:30Z

Status: implemented and verified; complete-set composition, store acceptance, preflight, publication, and native start remain absent.

## Accepted boundary

- Candidate bytes can be issued only from the opaque, non-Codable materialization input projected from the newest exact reducer-accepted apply event. Caller byte arrays and the mutable workspace are not capture inputs.
- The issuer revalidates the held read-only snapshot descriptor, reads only derivation `desiredPostimage` objects through descriptor-relative no-follow opens, checks stable metadata and SHA-256, revalidates the complete snapshot, and confirms that journal authority is still newest after reading.
- Capture identity binds run, integration transaction, apply receipt and frame, workspace/root/policy/candidate revision, materialization digest, snapshot device/inode/manifest, apply executor, time, derivation, exact references, object-set digest, count, bytes, and canonical receipt digest.
- `RunCommand.recordJournaledCandidateContentCapture` accepts only the live capability. Reducer replay stores one inert receipt per derivation and never recreates bytes or descriptor authority.
- Journal admission rechecks latest-transition authority immediately before append. Exact replay is idempotent; reusing a command ID for different receipt content is an explicit conflict. A later in-flight, failed, or rollback transition makes the older attestation stale.

## Deliberate non-authority

This slice does not compose the baseline and candidate captures into the complete before/after set, journal the object store, project HEAD/index/untracked, assemble `WorkspacePreimage` or a manifest, issue proposal/preflight/effect authority, permit publication, satisfy resident-memory enforcement, authorize native start, package, commit, or push.

## Verification

- The real integration-journal fixture proves exact candidate bytes, malformed-capability rejection without journal advance, exact replay idempotency, same-command conflict detection, receipt-only recovery, and denial after failed-rollback ambiguity.
- Exact split coverage passes: 744 tests with 8 intentional environment skips and 0 failures, plus the independently run process-group resistance case, for 745 covered tests and 0 failures.
- Release `LoopForge` SHA-256: `53340e78e0070579f3019d73e240731210b4a78b4152dca5117fdbd0018ee182`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source snapshot SHA-256: `e657be558301799fa19d4cb92315e25367f5c5c21789d5db3bc225021fefa788`.
- Diff whitespace, process cleanup, and the read-only EasyBusiness fingerprint passed unchanged.

Async-XCTest compilation, read-only-fixture teardown, and wrong-interpreter snapshot diagnostics, plus all build/test/wait/reporting time, count zero in the strict ledger.
