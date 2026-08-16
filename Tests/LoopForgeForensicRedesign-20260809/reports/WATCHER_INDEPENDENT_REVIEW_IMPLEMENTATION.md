# Watcher Independent Review Implementation

Status: **implemented, current clean-package UI contract verified; heterogeneous-provider option and operation-free live fixture remain pending**

## Forensic finding

Acceptance row I-05 was a production control-plane defect, not a prompt-style
problem. `WatcherController.performReview` gave one writable Agent thread all
three authorities:

1. inspect and repair the monitored workspace/pipeline;
2. write `.loopforge/watcher/review.json` and its item dispositions;
3. emit `HEALTHY`, `REPAIRED`, `NEEDS_USER`, or `COMPLETE`, after which the
   controller promoted the same thread's assertion into native status, report,
   notification, and scheduling state.

Deterministic verification commands checked that declared commands succeeded,
but did not independently adjudicate whether the Agent's semantic conclusion,
repair rationale, dismissals, or completion claim were true. That made a
self-consistent error self-authorizing and allowed persisted legacy prose to
remain visually authoritative after relaunch.

## Production retirement

Every adaptive review now has two separately sandboxed stages:

- the existing author thread may inspect, repair, and write its candidate;
- a fresh thread is forced to `readOnly`, receives the exact candidate pipeline
  and merged assessment plus their SHA-256 digests, and returns one strict
  approve/reject marker without mutating the workspace.

The controller cannot promote any candidate state until it receives a typed
`WatcherIndependentReviewReceipt`. The receipt binds author thread, reviewer
thread, role-separated lineage digests, exact pipeline digest, exact assessment
digest, verdict, provider summary, time, and bounded evidence. Validation rejects
missing lineage, same-thread review, same lineage, digest drift, schema drift,
and reviewer rejection.

The accepted assessment is now a computed fail-closed projection. Reports,
task-focused Watcher overview, `NEEDS_USER` attention, repair status, and
completion status can consume Agent conclusions only while the persisted receipt
still validates against the exact retained artifacts. Old Watchers and tampered
receipts remain decodable but their Agent conclusions display as advisory only.
The technical report exposes the authority state, reviewer, and bound digests.

## Adversarial receipts

Five new tests prove:

- distinct fresh lineages over exact artifacts pass;
- same-thread self-approval fails;
- explicit independent rejection fails;
- pipeline revision/digest drift fails;
- ambiguous dual-marker output fails;
- a persisted unreviewed dismissal cannot hide an active finding or manufacture
  user attention after relaunch.

The complete Watcher suite passed 35 tests. The complete source suite and the
packaging-owned suite each passed 522 tests with 8 environment-gated skips and
0 failures. The corrected exact-source arm64 app, ZIP, and DMG were rebuilt;
deep signing, manifest/source/test bindings, archive hashes, bundled-tool probes,
direct executable startup liveness, and process cleanup passed.

Package receipts:

- source snapshot: `9cd1f634b2aba35f6b0f4bdbefb5628c3c77651d3c8da1ccfce4943751528263`
- executable: `6b32cee5ad3af5f17bb6284ed2d80b18628bd57220c761092b611fe632a1f293`
- ZIP: `0e5b5762342c8741350a1fc1291a11482311b94f22ed72473977fe6c6f845666`
- DMG: `3ed5f9d6f5deaf797641b3c61774b7c501f205764b74273f3f3288bf8343d51f`
- package test log: `12faf70e1adb046387b6490c7def4e777fa157b99be286d2d9d17d18a4565640`
- CDHash: `eff6e18c8ebe0db6524637c6b0c9ab87a9cfe0c3`

The initial direct package-script invocation failed because the script is not
executable; it was rerun explicitly with `zsh`. That failed interval is excluded
from the strict ledger.

## Boundary

This advances I-05 at source/package level and removes the reachable self-approval
path. It does not create final acceptance. The reviewer is a fresh read-only
conversation lineage using the configured model selection; heterogeneous-provider
review is not yet a mandatory product setting. I-06 deterministic requirement
closure, legacy kernel cutover, current unlocked native screenshots, clean commit,
and push remain pending. EasyBusiness remained stopped and read-only.

## Current native contract

Clean commit `0a40f5d` adds the exact reviewer-lineage, read-only, artifact-digest,
and fail-closed rules to the Watcher composer and guide. Source and package-owned
suites passed 878/8/0, and the signed package displayed the contract before
Build Watcher could be enabled. The launch also resumed a persisted unrelated
Watcher; that incident is disclosed in `WATCHER_AUTHORITY_NATIVE_CONTRACT.md`
and its native interval is excluded. Heterogeneous-provider review remains a
non-mandatory product option, so final acceptance remains false.
