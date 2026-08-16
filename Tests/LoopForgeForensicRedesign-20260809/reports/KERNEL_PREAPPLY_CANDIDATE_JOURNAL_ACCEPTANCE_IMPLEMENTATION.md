# Pre-apply candidate isolation — reducer and hash-journal acceptance

Recorded: 2026-08-12T11:56:27Z

## Result

LoopForge now accepts the exact live pre-apply candidate-isolation capability
through the pure reducer and hash journal. The journal persists only its inert,
self-digested receipt; replay never reconstructs the held root descriptor,
candidate bytes, or process authority.

This is deliberately still not activation authority. Acceptance advances the
journal by one event while leaving the run `ready`, with no planned nodes,
attempts, process lease, effect, publication, or canonical-workspace mutation.
Both mutation execution boundaries retain their explicit isolation veto.

## Exact acceptance boundary

The receipt now binds the production enrollment actor in addition to run,
contract, attempt, node, causal strategy, source revision, capture policy,
enrollment frame, candidate path/root digest, candidate entry manifest,
file/byte totals, root device/inode, timestamp, and receipt digest.

Before first append or duplicate resolution, `RunJournal` revalidates the live
non-Codable capability through its still-held no-follow root descriptor. The
entire writable candidate tree must remain the exact ratified source bytes and
modes, the descriptor device/inode must remain stable, the current pathname
must resolve to that same directory object, the path must remain beneath this
run's private `preapply-candidates` directory, and the receipt must match the
source artifact's exact manifest and counts.

First acceptance is pinned to the exact enrollment journal-frame digest. The
pure reducer independently binds the receipt to the active mutation-capable
contract and retained initial plan/node, source revision, workspace root,
actor, and command time. It stores one receipt per attempt. The live descriptor
never enters reducer state or a Codable event.

Duplicate delivery is intentionally stricter than ordinary receipt replay:
the live capability is revalidated first. A modified, replaced, or closed
candidate therefore cannot use an old command ID to retrieve a successful
duplicate receipt. If live authority is still pristine, the duplicate must
name the exact retained receipt; another attempt or candidate conflicts without
journal advance.

## Adversarial coverage

Three new tests prove:

- first acceptance appends exactly one receipt-only hash-journal event;
- recovery deterministically reconstructs that receipt and transaction;
- serialized journal data contains neither a root-descriptor field nor the
  candidate file bytes;
- the run remains `ready` with no nodes or attempts;
- accepted receipt evidence still cannot start mutation execution;
- exact duplicate delivery is idempotent only while the held candidate remains
  pristine; and
- modified live authority and same-command different-attempt substitution both
  reject with no journal advance.

Exact final-source verification passed:

- focused pre-apply isolation family: 6 tests, zero failures;
- complete Swift suite: 759 tests, 8 intentional environment skips, zero
  failures;
- Release LoopForge SHA-256:
  `bb3a011ffacb9d9af3cc87eb860410519101c79ac7251f65281b65dfe0208d84`;
- Release KernelSandboxGate SHA-256:
  `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`;
- source snapshot before report reconciliation:
  `661566da74ebcd051e1b7be1b2d3de1772cfee9507f953a6ffddf94f7c21f82c`;
- `git diff --check`, owned-process cleanup, and the unchanged read-only
  EasyBusiness fingerprint passed.

One failed test-compilation diagnostic, all focused/full tests, Release build,
polls, waits, cleanup checks, and report generation count zero in the strict
active-work ledger.

## Still blocked

Activation must consume the original live capability, retain its root
descriptor for the whole attempt, and bind the worker's workspace-only sandbox
and launch working directory to the isolated candidate rather than the
canonical workspace. A recovered receipt is intentionally insufficient for
that transition. A post-worker content-complete logical candidate revision and
the acyclic delta/content-store/manifest/preparation/rollback/proposal/preflight
chain remain absent. Resident-memory enforcement, native design/visual/final
authority, native start, current packaging/signing, unlocked native UI
verification, clean commit, and push remain blocked.
