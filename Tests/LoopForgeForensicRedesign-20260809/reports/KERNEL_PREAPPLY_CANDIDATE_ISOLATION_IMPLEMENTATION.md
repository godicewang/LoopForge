# Pre-apply candidate isolation — inert capability implementation

Recorded: 2026-08-12T11:23:28Z

## Result

LoopForge can now create one owner-private writable candidate root before any
attempt, process, integration apply, or canonical-workspace mutation. The
candidate begins as an exact byte-for-byte copy of the content-complete source
revision retained by the user-ratified contract.

This is intentionally an **inert capability**, not reducer-owned activation
authority. Issuance does not append a journal frame, prepare a node, start an
attempt, clear either mutation-readiness blocker, launch a worker, issue a
manifest or preflight, or authorize an effect. Production mutation therefore
remains fail-closed.

## Authority and filesystem boundary

`WorkspacePreApplyCandidateIsolationCoordinator` reopens the exact durable
recovery registration and hash journal. It requires the original production
enrollment evidence, original enrollment journal head, reducer-retained
contract, exact source revision, exact mutation-capable retained plan/node,
workspace identity, and canonical root binding. Any later journal advance,
existing plan/attempt state, source drift, registration substitution, wrong
node, read-only contract, or mismatched workspace rejects before a capability
is issued.

The audited candidate materializer creates `preapply-candidates` beneath the
owner-private journal run directory, outside and disjoint from the canonical
workspace. It uses a nonblocking owned lock, descriptor-relative `O_NOFOLLOW`
source opens, exclusive destination creation, bounded streaming, exact mode,
size, content-hash, and stable-source checks, sync plus atomic install, and an
independent descriptor-relative tree walk. Only the source-revision entries
are copied; Git metadata and policy-excluded generated trees cannot be smuggled
into the candidate.

The durable receipt binds run, contract, attempt, node, strategy, ratified
source revision, capture policy, enrollment frame, physical candidate root,
entry manifest, byte/file totals, root device/inode, time, and a self-digest.
The live capability is non-Codable and holds the exact no-follow root descriptor
across future journal acceptance. Pristine revalidation rejects altered bytes,
tampered receipts, closed authority, and candidate-path replacement even when
the original directory object remains open.

## Adversarial coverage

Three new production-enrollment tests prove:

- exact writable candidate bytes exist only outside the canonical workspace;
- modifying the candidate leaves the canonical source unchanged and invalidates
  pristine revalidation;
- source drift rejects before the candidate directory is created;
- replacing the candidate pathname cannot redirect the held live capability;
- the reducer journal remains at the original enrollment sequence with no nodes
  or attempts; and
- both mutation blockers remain present after inert issuance.

Exact final-source verification passed:

- focused enrollment/isolation/readiness tests: 30 passed, zero failures;
- complete Swift suite: 756 unique tests, 8 intentional environment skips,
  zero failures;
- independently repeated process-group resistance case: 1 passed (already one
  of the 756 unique suite tests and therefore not added to the unique total);
- Release LoopForge SHA-256:
  `39079a40cf72f0acc595b2ecff0df2e1ace065fb499819b1402843124c2da7b8`;
- Release KernelSandboxGate SHA-256:
  `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`;
- source snapshot before report reconciliation:
  `4a5e1677bb7e581f8fce8b231210be339ea11c45157c91860a22fb3c894fc1d0`;
- `git diff --check`, owned-process cleanup, and the unchanged read-only
  EasyBusiness fingerprint passed.

Two failed compile diagnostics, one failed test-compilation diagnostic, all
tests and builds, polls, waits, cleanup checks, and report generation count
zero in the strict ledger.

## Still blocked

The inert isolation receipt must next enter the pure reducer and hash journal
through exact live-capability validation. Activation must then consume that
accepted authority, retain the root descriptor, and bind the worker sandbox to
the candidate instead of the canonical workspace. A post-worker content-complete
candidate revision must preserve the logical ratified workspace identity while
separately proving its physical isolated root. Only then can an acyclic delta,
content store, manifest, preparation facts, rollback rehearsal, proposal, and
preflight be issued. Resident-memory enforcement, native design/visual/final
authority, native start, current packaging/signing, native UI verification,
clean commit, and push remain blocked.

