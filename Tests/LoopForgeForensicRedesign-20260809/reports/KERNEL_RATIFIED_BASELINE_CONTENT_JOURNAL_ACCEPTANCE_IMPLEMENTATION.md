# Kernel ratified baseline content journal acceptance

Recorded: 2026-08-12T07:28:10Z

Status: implemented and verified; candidate origin, complete object-set composition, preflight, publication, and native start remain absent.

## Accepted boundary

- `RunCommand.recordRatifiedBaselineContentCapture` accepts only the live, non-Codable `AuthorizedWorkspaceRatifiedBaselineContent` capability. A decoded `WorkspaceRatifiedBaselineContentCaptureReceipt` is inert and has no production command constructor.
- The receipt now durably binds the exact workspace identity, canonical-root digest, capturing actor lineage, and capture time in addition to run, contract, ratification, enrollment frame, derivation, base revision, policy, root device/inode, content references, and object-set digest.
- Command admission rehashes and cardinality-checks the live bytes, checks actor/time against journal context, checks every content reference against the ratified source revision, and rejects terminal, cross-run, cross-contract, cross-workspace, cross-root, cross-revision, cross-policy, or substituted capability data.
- One derivation digest may receive one accepted baseline capture. Command idempotency returns a duplicate only when the retained event contains the exact same receipt; reuse for a different capture raises an explicit conflict.
- The hash-chained event persists only the receipt. Recovery reconstructs the reducer-owned derivation-to-capture projection without serializing the capability bytes or recreating byte authority.

## Deliberate non-authority

This slice does not capture candidate bytes, compose the complete before/after object set, write the content store, project HEAD/index/untracked planes, assemble `WorkspacePreimage` or a mutation manifest, issue preflight/effect authority, permit publication, satisfy resident-memory enforcement, authorize native start, package, commit, or push.

## Verification

- Seven baseline-origin and journal-focused tests pass, including durable recovery, corrupt-byte rejection without journal advance, exact idempotency, changed/symlinked baseline rejection, cross-workspace rejection, and enrollment substitution rejection.
- Exact current-source split coverage passes: 744 tests with 8 intentional environment skips and 0 failures, plus the independently run process-group resistance case, for 745 covered tests and 0 failures.
- Release `LoopForge` SHA-256: `46d6d91a51de9e267176f39e678401318fd059e9a472b8bf07c6dceefeeeb253`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source snapshot SHA-256: `d881135bfc635bcb4a2b7e31235e89ab20b471510a8741a2d38563cf1a615e89`.
- Diff whitespace, process cleanup, and the read-only EasyBusiness fingerprint passed unchanged.

One focused runtime failure exposed an over-strict fixture-lineage validation, and one test compilation attempt exposed async XCTest autoclosures. Both diagnostic attempts, all test/build execution, waits, polling, and reporting time count zero in the strict ledger.
