# Completed candidate capture — logical revision, retained bytes, and crash replay

Recorded: `2026-08-12T15:51:40Z`

## Result

LoopForge now captures the exact post-worker candidate through the descriptor
retained by the production execution session. Capture is available only after
the exact worker release, terminal-result parse, and reducer-derived execution
receipt are journaled and the disposition is `completed`. The canonical
workspace is never reopened or mutated.

The durable receipt binds the ratified logical workspace identity to the
candidate's physical root, device, inode, entry manifest, source revision,
capture policy, content-object set, actor, and time. It also binds the exact
release, parse, and execution receipt IDs and their hash-journal frame digests.
The corresponding non-Codable capability retains every deduplicated immutable
file byte for downstream content-store composition. Crash replay reconstructs
the logical revision and complete physical/provenance receipt, but deliberately
cannot recreate byte authority.

## Stable logical projection

Capture walks the held candidate descriptor with no-follow opens and ratified
directory exclusions, reads bounded stable bytes, records physical metadata,
then independently re-enumerates and rehashes the full tree. It preserves the
ratified logical workspace ID and canonical-root digest while recording the
isolated physical root separately. Unchanged normalized modes project their
original logical modes; deliberate mode changes remain visible.

The production session derives an inert regular-file mutation operation set
against the exact enrolled source revision. Only the prepared node's exact
requirement IDs and writable paths are accepted, and every desired postimage
must exist in the retained candidate objects. A completed worker receives one
capture attempt: failure cannot authorize out-of-band mutation and retry under
the same completion provenance.

## Journal and runtime authority

`JournaledProcessRuntime` authorizes capture only when the exact release,
parse, and execution transactions are present and no adapter handle, in-doubt
resource, or supervisor-owned live/queued/failed resource remains. The pure
reducer accepts the receipt only while the run is evaluating, the attempt is
completed, and the node is awaiting verification under the same contract,
source, isolation, strategy, actor, and provenance. One hash-chained event
stores the self-digested receipt; replay is filesystem-inert.

## Adversarial verification

- Descriptor capture retained exact modified and created bytes, excluded
  `.build`, preserved logical workspace identity, and derived only the expected
  modify/create operations.
- Non-completed and mismatched completion evidence rejected.
- A real enrolled run accepted the completed-candidate event, reopened the
  latest journal, and recovered the complete receipt without mutating the
  canonical workspace.
- Complete Swift suite: 764 tests, 8 intentional environment skips, zero
  failures.
- `git diff --check`, owned-process cleanup, thermal checks, and the unchanged
  read-only EasyBusiness fingerprint passed.

Failed compile/test diagnostics, the transient pre-existing timeout, all
tests/builds, waits, polling, cleanup checks, and report generation count zero
in the strict active-work ledger.

## Still blocked

The candidate revision, exact delta, immutable bytes, and crash-replayable
capture provenance now exist. Canonical mutation remains fail-closed until the
captured bytes are composed through the content store and the remaining
manifest, preparation-facts, rollback, proposal, and preflight authority chain.
Tested resident-memory enforcement, native immutable design-baseline and
complete visual authority, final authorization, remaining legacy Single/
Parallel retirement, unlocked native UI verification, current package/sign/
hash, clean commit, and push also remain pending.
