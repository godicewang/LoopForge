# Completed candidate content store — preflight-side immutable bytes

Recorded: `2026-08-12T16:16:32Z`

## Result

LoopForge now composes the exact ratified baseline bytes and exact completed
candidate bytes into the existing immutable content-addressed store before any
integration apply event exists. This is a new, explicitly preflight-side
receipt chain; it does not reuse the older post-apply candidate-content path
and cannot issue a manifest, rollback, preflight, staging, apply, or canonical
workspace mutation capability.

The coordinator requires the live non-Codable completed-candidate capability,
the exact journal transaction that accepted it, and a live ratified-baseline
capability already accepted for the same derivation. It resolves the exact
expected-preimage and desired-postimage partitions, rejects missing, extra,
corrupt, conflicting, oversized, wrong-workspace, wrong-revision, and
scope-widened bytes, then atomically installs the verified set outside the
workspace.

## Independent reducer and journal authority

The durable receipt carries the complete derivation, content-set verification,
object-store artifact identity, baseline/candidate origin digests, exact
completed-candidate capture frame digest, actor, time, and a self digest. The
pure reducer independently checks the completed attempt, node, contract,
ratified source, exact requirement ownership, writable-path containment,
before/after partitions, and actor/time. `RunJournal` revalidates the external
artifact and both live byte capabilities before first append and duplicate
replay. Crash recovery restores only inert receipt evidence.

## Verification

- A substituted capture transaction was rejected before the store directory
  existed.
- The exact baseline and candidate bytes were installed outside the canonical
  workspace and revalidated from the immutable artifact.
- Exact command replay was idempotent and still revalidated the artifact.
- Journal close/reopen recovered the full store receipt without byte authority.
- The affected content/integration/enrollment surface passed 52 tests.
- The complete Swift suite passed 764 tests with 8 intentional environment
  skips and zero failures.
- Diff whitespace, owned-process cleanup, thermal checks, and the unchanged
  read-only EasyBusiness fingerprint passed.

The initial compile diagnostic, one cleanup-permission test diagnostic, all
tests/builds, waits, polling, cleanup checks, and report generation count zero
in the strict ledger.

## Still blocked

The exact bytes now have durable pre-apply object-store provenance. Canonical
mutation remains fail-closed until LoopForge issues an acyclic mutation
manifest, preparation facts, rollback rehearsal, proposal, and preflight chain
from this receipt. Resident-memory authority, native design/visual/final
authority, native UI verification, package/sign/hash, clean commit, and push
also remain pending.
