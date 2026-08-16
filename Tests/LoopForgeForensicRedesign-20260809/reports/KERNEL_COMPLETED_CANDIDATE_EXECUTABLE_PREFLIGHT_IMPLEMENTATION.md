# Completed candidate executable mutation preflight

Recorded: `2026-08-14T00:30:50Z`

## Result

LoopForge now has a production issuer for the exact completed-candidate
mutation proposal and deterministic preflight. The issuer consumes the live,
journal-accepted owner-private rollback-rehearsal authority; decoded receipts,
caller-selected manifest/context values, and replayed state cannot mint it.

Immediately before issuance, the coordinator revalidates the canonical
affected paths, recaptures the complete current worktree under the ratified
source policy, revalidates the sealed external content objects, and resolves
the exact accepted contract, node, attempt, verification, independent review,
visual gate, preparation facts, and rollback rehearsal from the journal. It
projects the immutable protected-baseline bindings from the contract and
constructs no caller-controlled acceptance set.

The ordinary integration state machine journals the exact proposal and then
the admitted preflight plus deterministic inverse as one preflighted two-frame
batch. Recovery is receipt-only and reaches `rollbackPrepared`; exact duplicate
issuance returns both retained frames, while a crash after only the proposal
can resume only the matching preflight frame. Publication remains false and no
apply intent, mutation lease, filesystem effect, or canonical-workspace write
authority is issued.

## Regressions and verification

- The enrolled completed-candidate test now exercises proposal, preflight,
  exact duplicate resolution, close/reopen replay, and a byte-identical
  canonical fixture.
- Integration path containment correctly treats each declared writable scope
  as a scope, rather than requiring affected paths to be literal scope strings.
- The exact prior cooperative-stack regression remains green.
- The complete final-source Swift suite passes 766 tests with eight intentional
  environment skips and zero failures in 57.462 test seconds (57.507 wall).

## Still blocked

No canonical apply authority has been composed. Resident-memory authority,
native design/visual/final authority, legacy Single/Parallel retirement,
native walkthrough, final package/sign/hash, clean commit, and push remain
pending. Final acceptance remains false.
