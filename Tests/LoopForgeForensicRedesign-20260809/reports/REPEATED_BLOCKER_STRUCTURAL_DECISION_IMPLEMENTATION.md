# Repeated Blocker Structural Decision

Status: **F-06 legacy source/controller and package receipts present; production fingerprint/reducer cutover pending**

Recorded: `2026-08-11T05:22:35Z`

## Defect confirmed

The legacy Graph path recognized three consecutive `LOOPFORGE_STATUS: BLOCKED`
worker turns and set `automaticRetryDisabled`, but it did not set
`strategyEscalationRequired`. An ordinary `planAdjustment` could then clear the
retry stop and reactivate the same node under a fresh thread. The node was not
forced into abandon/reframe/split/replace review until the separate six-
unapproved-decision counter was exhausted.

The existing regression test explicitly approved this bypass: it reconstructed
a legacy three-blocker warning, added a new plan sentence, and expected the
same node to return to `waiting`. That made a repeated blocker a temporary UI
pause rather than durable exhausted-budget evidence.

## Repair

Crossing the repeated-blocker threshold is now a structural state transition:

- the node becomes blocked;
- its active interval is closed;
- automatic retry is disabled;
- `strategyEscalationRequired` is persisted;
- the rejected worker thread is detached;
- the scheduler exposes the node through `pendingNodeID` before another worker
  launch;
- an explicit `planAdjustment` cannot reactivate the same node;
- Main Graph must abandon, reframe, split, or replace it through the existing
  structural retirement envelope.

Legacy checkpoints are also protected. The historical deterministic warning
prefix is treated as repeated-blocker stop provenance even when the newer
boolean was absent. Resume normalization therefore upgrades that checkpoint
to structural review before evaluating any stale plan adjustment.

Ordinary non-exhausted pauses remain distinct: when there is no repeated-
blocker provenance or other escalation condition, one explicit bounded replan
may still detach the stale thread and resume.

## Adversarial verification

- the third consecutive blocked turn freezes the thread and schedules
  structural review;
- the exhausted node is discoverable by the scheduler's strategy-review gate;
- a legacy warning-only checkpoint remains frozen after relaunch;
- adding a plan adjustment to that checkpoint does not clear exhaustion;
- applying the replan helper to an exhausted node leaves it blocked;
- an ordinary non-exhausted pause still accepts one bounded replan;
- productive sibling detection remains unchanged;
- the complete Graph, recovery, scheduler, transaction, visual, runtime, and
  packaging suites remain green.

## Verification

- focused Graph suite: **92 tests, 0 failures**;
- complete source suite: **594 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **594 tests, 8 environment-gated skips, 0 failures**;
- Release build, ad-hoc signature, exact source/test manifest, ZIP, DMG,
  checksums, executable startup, cleanup, and zero residual packaged processes
  verified.

Receipts:

- source snapshot: `7e67b828a8d5e17bac8b9d5c14d4dbc10a8c01751dd24b81607b9b4922d36ec9`
- Graph source: `bbed4e110672e2ae1ad446a24b3530696f47ed97c31a255b0b6c1d9fbcbe2d2a`
- Graph tests: `b8cb0a7408d6de98b239dde98393398b352c86786114cf0f2571744d97e8572f`
- focused log: `48cf9b11d8eda0e2147ea0841f0d0a030d8d30e2142ea03fce3c7c61770cd000`
- full source log: `b2853d30e1f602ef662c88df69cc7522e4c9dd7ceb142453ef1665235895edb9`
- package test log: `d0016ee9458ac1190652f45ca556539d34eafaaf431ae471c4a012bfc37ff14c`
- package command log: `c8fd18552826f5af376e9ba482f46e3f6c13a12aae68ea3a8f212e8d9adaf8e9`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `f8df837d150787ad13851f68eb88873ef889033a2263da8cfc50bb22965ac61c`
- executable: `dbbdaa28cfcb3a8631b788e38c9ec616cf72d496bde2b523ae17afa7ccdd992f`
- ZIP: `007d57c0917643e073fc8d8d380fe036d0a775ac5b5b9e2cd155ad2cbfc48310`
- DMG: `f26862818d92254a72fa7183d1af8998f6caf346b8a0275afa203363b326c846`
- CDHash: `a2293ed8acbc004a96bd1f3ceec54ba7df119fba`

## Boundary

Legacy detection still recognizes a worker's structured status marker rather
than a trusted, journal-issued blocker fingerprint. Full F-06 acceptance
requires the typed kernel reducer to own the production path so that one exact
blocker fingerprint consumes one durable budget across retries, relaunches,
replans, and replacements. It also requires current unlocked native proof, a
clean commit, and push.

EasyBusiness remained permanently stopped and read-only.
