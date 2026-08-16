# Exact-Run Repository Diagnostics

Status: **implemented, clean-package verified, and native exact-run status binding passed; resolved cache telemetry remains pending**

Recorded: `2026-08-16T12:37:13Z`

## Defect

The diagnostics sheet rendered kernel projections first and repository recovery
reports afterward. `notApplicable` reports were filtered out entirely. A user
could therefore see a run and separately see repository telemetry, but could
not prove that the two projections described the same exact native run. The
absence of an accepted workspace transition was also invisible, which made a
missing authority look like missing UI.

## Correction

The sheet now forms one deterministic union of kernel and recovery run IDs,
sorts it by the opaque run identity, and renders one explicit
`Exact native run` group per identity. Each group contains its reducer-derived
run state and its matching repository-generation report. `notApplicable` is
no longer dropped. It is named **No accepted workspace transition** and states
that no repository generation or cache-reuse authority exists.

A current-session run with no retained startup report receives a separate
fail-closed **Unavailable in current session** card. Only a genuinely resolved
journal generation may render entry count, cache disposition, sequence,
authority, generation digest, and observed-metadata digest. The change creates
no cache receipt and weakens no provider, containment, or mutation veto.

## Verification

- focused presentation suite: 4 tests, 0 failures;
- complete source suite: 878 tests, 8 environment-gated skips, 0 failures;
- clean package-owned suite: 878 tests, 8 skips, 0 failures in 84.564 test
  seconds (84.614 wall);
- clean package revision: `7655bb132bd979b12315780f08d8b88c8b11d310`;
- source snapshot: `1b3cc8cf8d391a4861b1c44b4b4a9a7d5d2e09cd2fe36486bde66252b5136bb4`;
- package test log: `a8c439f815a043e03318738c1a0c07694584aa457b6c9e394cd52b9081da1446`;
- executable: `932b60fee705eb70521d013d2021867979f35f701a3f0bf17e847365ef101504`;
- ZIP: `5e55b53b50930965c8dae5cb13749d1cf0da97d4de8038dde07d94351400c7e2`;
- DMG: `8b39d09b80c2e65e886e5e0eb72b40325c5a6cadae85f585e03799d99ea75db0`;
- app CDHash: `68f10f7b4135cb62e13cf460885876f7d95a9377`.

Computer Use opened the exact signed package and the real Kernel diagnostics
sheet. All three retained run identities appeared once as exact groups. Each
group carried its own `Repository generation` card and the typed
`No accepted workspace transition` status. The terminal run's mutation delta,
verification delta, external effects, failures, journal projection, and
repository status remained visible together. The sheet launched no attempt,
provider, verifier, worker, legacy execution, or mutation. Cmd-Q left zero
packaged processes or verification mounts.

Native receipts:

- [upper diagnostics](../screenshots/packaged-loopforge-exact-run-repository-diagnostics-20260816T1235Z.png), SHA-256 `262f1ca1df00d57262bcaa8c666b2b65bb8969d7585e4abd28daa996cda323b5`;
- [lower diagnostics](../screenshots/packaged-loopforge-exact-run-repository-diagnostics-lower-20260816T1235Z.png), SHA-256 `313f032fa43293288245fec2163750c34e152ebd2876ead44357df6e344b2ec7`.

## Boundary

This closes the UI attribution defect and the current unlocked native
repository-status walkthrough. It does not claim resolved cache telemetry:
the exact retained runs have no journal-accepted workspace transition. A
resolved native receipt remains gated on a separately ratified production
mutation/isolation path. Manufacturing or seeding a success would invalidate
the forensic result. Current Watcher native walkthroughs and the other global
release gates also remain pending. EasyBusiness remained read-only with its
exact branch, HEAD, and status fingerprint unchanged.
