# Pre-apply candidate isolation — descriptor-retaining production activation

Recorded: `2026-08-12T15:07:14Z`

## Result

LoopForge production composition now consumes the original live pre-apply
candidate-isolation capability exactly once and retains an independently owned
root descriptor for the execution session. A decoded journal receipt cannot
activate mutation, duplicate activation cannot reuse the consumed descriptor,
and the canonical workspace remains outside the worker's mutation authority.

Readiness recognizes the accepted isolation receipt as the exact current
journal head but deliberately keeps the live-isolation blocker. Only the
production `activate` boundary can clear that blocker, and only when the
non-Codable capability matches the accepted receipt, attempt, node, strategy,
actor, contract, and journal state. Descriptor ownership transfers before
journaled preparation; failures close the transferred root rather than leave
two live owners.

## Descriptor-bound native boundary

The activated execution proof, session receipt, provider invocation receipt,
workspace-only native sandbox, and process runtime all carry the same exact
isolation receipt. Immediately before every provider spawn, the runtime:

1. rehashes the complete pristine candidate through the retained descriptor;
2. proves the candidate pathname still names the same device and inode;
3. validates the invocation receipt against the execution proof;
4. passes the retained descriptor to Darwin
   `posix_spawn_file_actions_addfchdir_np`; and
5. requires the stopped sandbox gate's native cwd attestation to equal the
   receipt's exact device and inode before resuming the worker.

Candidate storage is now an owner-private `execution/preapply-candidates`
sibling of the journal directory. The writable workspace-only sandbox can
therefore authorize candidate mutation without authorizing writes to the
hash-chained journal. Journal acceptance independently requires that exact
execution-parent provenance.

Production provider completion now resolves the post-binding lease from the
exact provider launch transaction. It no longer reuses the pre-binding
admission lease, whose missing native identity correctly caused ownership
divergence. The process-group resistance test also replaced an unbounded
Foundation `waitUntilExit` cleanup with bounded checks and exact-PID escalation,
eliminating a reproducible suite hang without broad process signalling.

## Adversarial verification

- Exact activation consumes the original capability and binds the session,
  execution proof, invocation, sandbox, and cwd attestation to one receipt.
- Substituted and stale capabilities reject before `startAttempt` and do not
  advance the journal.
- The real `KernelProcessFixture` launched under the production session with
  workspace-only sandboxing and exact candidate device/inode cwd attestation.
- Its deliberately non-worker terminal output was rejected only after a
  journaled natural release; runtime projection then contained no live handle
  and no in-doubt resource.
- The canonical workspace file remained byte-identical.
- Focused affected surface: 97 tests, zero skips, zero failures.
- Complete Swift suite: 761 tests, 8 intentional environment skips, zero
  failures.
- `git diff --check`, owned-process cleanup, and the unchanged read-only
  EasyBusiness fingerprint passed.

Failed compilations, failed launch diagnostics, the timed-out release attempt,
the interrupted hanging suite, all tests/builds, waits, polling, cleanup checks,
and report generation count zero in the strict active-work ledger.

## Still blocked

The worker can now mutate only the isolated candidate, but LoopForge still
lacks the post-worker content-complete logical candidate revision and the
acyclic delta/content-store/manifest/preparation/rollback/proposal/preflight
chain needed to authorize canonical integration. Resident-memory enforcement,
native immutable design-baseline and complete visual evidence authority, final
authorization, remaining legacy Single/Parallel retirement, unlocked native UI
verification, current package/sign/hash, clean commit, and push remain blocked.

