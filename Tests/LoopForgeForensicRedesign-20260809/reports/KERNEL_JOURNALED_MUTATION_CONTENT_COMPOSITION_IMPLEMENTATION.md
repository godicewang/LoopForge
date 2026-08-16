# Kernel journaled mutation content composition

Recorded: 2026-08-12T08:36:37Z

Status: implemented and verified; content-store journal acceptance, preflight, publication, and native start remain absent.

## Accepted boundary

- One journal-aware issuer now composes the already accepted ratified-baseline and journaled-candidate live capabilities into the exact complete before/after byte set for one validated derivation.
- Composition resolves both durable capture receipts from current reducer state and requires exact run, integration transaction, workspace, canonical root, capture policy, derivation, base revision, candidate revision, receipt-digest, and live-byte agreement.
- The baseline partition must equal every unique `expectedPreimage`; the candidate partition must equal every unique `desiredPostimage`. Missing, unexpected, substituted, duplicated, corrupt, wrong-size, or conflicting shared objects fail closed.
- A shared digest is deduplicated only after both origin capabilities independently validate the same digest and bytes. The complete union is then rehashed by the existing exact-set verifier.
- Candidate attestation freshness is checked before and after exact-set verification. A newer in-flight, failed, or rollback transition invalidates the otherwise accepted capture receipt.
- The durable composition receipt binds both origin-receipt digests, both exact partitions, and the complete-set verification receipt. Only a non-Codable capability carries the merged bytes, and neither value can write a store or authorize a mutation.

## Adversarial correction

Review found that the candidate live capability previously validated its receipt bytes and its attestation independently but did not explicitly bind those two members to each other. Validation now requires exact transaction, workspace, root, apply receipt/frame, candidate revision, and policy equality between them before journal admission or composition.

## Deliberate non-authority

This slice does not journal-accept or materialize the content store, project HEAD/index/untracked, assemble `WorkspacePreimage` or a manifest, issue proposal/preflight/effect authority, permit publication, satisfy resident-memory enforcement, authorize native start, package, commit, or push.

## Verification

- The real integration-journal fixture now uses a modify delta with distinct old and new bytes. It proves exact two-origin composition, inert receipt round-trip, substituted accepted-origin rejection, and denial after a failed rollback makes the candidate stale.
- Exact split coverage passes: 744 tests with 8 intentional environment skips and 0 failures, plus the independently run process-group resistance case, for 745 covered tests and 0 failures.
- Release `LoopForge` SHA-256: `76002346811f87a16b8ac9cf0a395219191f64d25af3226d3003e634496f7596`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source snapshot SHA-256: `081fb2c226e8bab064d912c894ac70afe69627817b915cd82da576a803f24b12`.
- Diff whitespace, owned test-process cleanup, and the read-only EasyBusiness fingerprint passed unchanged. Two unrelated high-CPU processes were observed but not touched because they are outside LoopForge ownership.

All build/test execution, waits, polling, and report generation count zero in the strict ledger.
