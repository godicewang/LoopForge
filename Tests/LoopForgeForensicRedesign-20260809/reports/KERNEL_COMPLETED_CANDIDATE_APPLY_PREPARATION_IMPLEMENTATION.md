# Completed candidate apply preparation

Recorded: `2026-08-14T01:21:02Z`

## Result

LoopForge now converts one exact live completed-candidate executable preflight
into a journal-first, durable pending apply request. It does not dispatch the
filesystem executor and does not mutate the canonical workspace.

The coordinator resolves the exact registered recovery roots and accepted
proposal/preflight frames, then revalidates canonical affected paths and the
sealed external content objects. It restores the runtime supervisor from the
journal, durably admits one exclusive mutation lease, constructs the exact
policy-bound apply intent, journals `startApply`, and only then persists the
complete content-bearing executor request in the external effect outbox.

The lease lane is keyed by logical workspace identity. The live root inode is
still sealed into the execution lease and checked by the executor, but inode
replacement cannot create a second lane for the same workspace. Exact replay
after a crash reconstructs the already-journaled live admission and reuses the
same intent. Reopening the outbox also recognizes the same canonical payload;
JSON-decoding differences in URL base metadata cannot create a false duplicate
conflict.

## Authority boundary

- The apply intent and exclusive lease are journaled before effect dispatch.
- The complete exact request is pending in a registered external durable
  outbox before any executor invocation.
- No apply receipt, postimage verification, independent acceptance,
  publication, or completion authority is issued by preparation.
- A failure after the intent but before outbox persistence is visible and
  fail-closed; finishing that boundary still requires the same live preflight
  capability.

## Regressions and verification

- The enrolled completed-candidate test now reaches `applying`, proves the
  exact pending outbox request, replays lease and intent identity, reopens the
  journal and outbox, and confirms the canonical fixture is byte-identical.
- The lease-authority test proves exact admission replay after supervisor loss.
- All 14 filesystem-executor/outbox tests pass, including idempotent enqueue
  through a newly decoded outbox instance.
- The complete final-source Swift suite passes 766 tests with eight intentional
  environment skips and zero failures in 59.654 test seconds (59.698 wall).

## Still blocked

The prepared effect is not dispatched by this coordinator. Postimage
verification and independent acceptance must be composed for its resulting
receipt, and any failure or expiry path must journal cleanup without hiding an
in-doubt lease. Resident-memory authority, native design/visual/final
authority, legacy Single/Parallel retirement, native walkthrough, final
package/sign/hash, clean commit, and push remain pending. Final acceptance
remains false.
