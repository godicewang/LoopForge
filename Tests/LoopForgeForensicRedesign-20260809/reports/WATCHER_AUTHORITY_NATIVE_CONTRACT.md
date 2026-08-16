# Watcher Authority and Completion Native Contract

Status: **current clean package exposes the fail-closed contract; a persisted Watcher resumed during launch, so the walkthrough is not classified as operation-free**

Recorded: `2026-08-16T13:03:43Z`

## Product closure

Commit `0a40f5dda28b5a846fd28bb0273a4f4eee2851e3` adds one explicit
`Authority & completion` surface to the Watcher composer and one `Verify
authority` step to the native guide. The UI now says, before Build Watcher can
be enabled, that:

- a fresh read-only reviewer with a distinct conversation lineage checks the
  exact pipeline and assessment digests;
- deterministic completion binds telemetry, checkpoint bytes, verification
  results, goal evidence, and independent approval;
- an Agent `COMPLETE` marker is only a proposal; missing, stale, altered,
  self-approved, or rejected evidence cannot complete the Watcher.

This is a truthful projection of the already-enforced I-05 and I-06 receipt
chains. It does not claim heterogeneous-provider independence: the reviewer is
a fresh lineage using the configured model selection.

## Verification

The focused guide test passed 1/0. The complete source suite passed 878 tests
with 8 environment-gated skips and 0 failures. The clean package-owned suite
again passed 878/8/0, then rebuilt and signed the exact-source app, ZIP, and
DMG. The package is bound to clean revision `0a40f5d…e2851e3`, source snapshot
`77ea9ecbf492a68fdc571f87dc90042fb799633d3c0f90390c026e3f970d1b46`,
and package test log
`a599c001d59bffbe4cb52648f2c0da5a53e65986974fec9dc6aaee24c64d22ec`.

Computer Use opened the exact signed package without entering a target,
selecting a project, changing a model, or invoking Build Watcher. The
[composer](../screenshots/packaged-loopforge-watcher-authority-completion-20260816T1257Z.png),
[lower safeguard card](../screenshots/packaged-loopforge-watcher-authority-completion-lower-20260816T1257Z.png),
and [guide step](../screenshots/packaged-loopforge-watcher-authority-guide-20260816T1258Z.png)
are retained with SHA-256 values
`8c7131bf3500d1128fb27718e01abbd8b2bc906964ce442ede49dc39d813373e`,
`5b44fe9a7265c0e27da29c124a1176678cdef8d6a6904c2e2d1ed2eaeb888226`,
and `dba8b3eb4a6bfc66af4e40285c96dc4a85755230d4c98101afe162c66447c260`.

## Native recovery incident

Launching the app also restored a previously active Watcher for
`Tests/WatcherQuantFactor-20260729`. The UI first showed `Agent is reviewing`,
then returned to `Watching` / `Scheduler ready`; files in that pre-existing
untracked fixture received new timestamps between `20:58:07` and `20:59:59`
local time. No new Watcher was created, but this makes the walkthrough neither
read-only nor operation-free. Those unrelated untracked files remain unstaged
and were not rewritten or reverted because no trusted pre-launch byte baseline
was available. The native interval is excluded from accepted ledger time.

Cmd-Q left zero `LoopForge`, provider-harness, sandbox-gate, or fixture-owned
processes and zero LoopForge verification mounts. EasyBusiness remained
read-only: branch `codex/USA_Version`, HEAD `2ae4045…bfab04`, NUL-delimited
status digest `2fe574a1…5033a`, and all existing changed-file mtimes remained
`2026-08-09T20:55:34Z`.

## Boundary

I-05 and I-06 now have current clean-package UI-contract proof in addition to
their production enforcement and adversarial tests. Final acceptance remains
false. Heterogeneous-provider review is not mandatory, and an operational live
completion-chain exercise must use an explicitly disposable fixture with all
persisted Watchers paused first. J-04 still awaits resolved repository-cache
telemetry after a separately ratified mutation/isolation path.
