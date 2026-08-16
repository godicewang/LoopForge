# Completed candidate rollback rehearsal — exact, owner-private, and journaled

Recorded: `2026-08-13T16:00:31Z`

## Result

LoopForge now performs the exact forward mutation and deterministic inverse in
an owner-private replica outside the canonical workspace. The live coordinator
selects exactly one effective accepted verification receipt and one matching
independent approval; a visual receipt is mandatory when the immutable design
baseline intersects the changed requirements. It then builds an inert manifest
from the accepted proposal and preparation facts, executes every regular-file
create, modify, delete, and mode inverse, verifies exact affected-path state
restoration, removes the replica, revalidates the canonical paths, and journals
the self-digested receipt.

The receipt binds both complete manifests, their digests, content-object set,
proposal and preparation frames, initial/applied/restored state digests, exact
affected paths and operation counts, actor, and time. It grants no executable
canonical-workspace preflight, integration, publication, or effect authority.

## Adversarial and recovery checks

- Rehearsal storage inside the canonical workspace is rejected.
- Owner-private storage, exact forward/inverse application, and cleanup pass.
- Initial and restored state digests are identical; applied state differs.
- The reducer requires the post-review accepted node and the exact effective
  verifier/reviewer chain; an unrequired visual receipt is rejected.
- First append revalidates the external artifact and canonical workspace.
- Duplicate append is receipt-exact and re-executes the private rehearsal.
- Close/reopen journal replay recovers the exact receipt and no live authority.
- Proposal retry remains idempotent after review advances the node to accepted.
- The canonical fixture remains byte-identical and no integration transaction
  is created.

## Stack-safety regression found during proportional verification

The rich new command/event payload exposed an existing cooperative-thread stack
limit in unrelated postimage-verifier release validation. Six failed runs were
excluded. The production reducer now dispatches runtime-release validation
before entering its monolithic command switch, preserving every containment
predicate while removing that switch frame from the deep native validation
call chain. The exact former crash test passes, as does a size guard over the
central command/event envelopes.

## Verification

The rollback executor tests, journal enrollment/idempotency/replay test, and
former verifier-release crash test pass. The complete final-source Swift suite
passes 766 tests with eight intentional environment skips and zero failures in
60.861 test seconds (60.907 seconds wall).

## Still blocked

Executable manifest assembly and proposal/preflight authority remain absent.
Resident-memory authority, native design/visual/final authority, production
legacy cutover, native walkthrough, final package/sign/hash, clean commit, and
push also remain pending.
