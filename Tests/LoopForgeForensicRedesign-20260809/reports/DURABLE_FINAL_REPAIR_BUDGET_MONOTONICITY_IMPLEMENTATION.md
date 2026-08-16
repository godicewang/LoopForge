# Durable Final-Repair Budget Monotonicity

Status: **F-07 legacy final-repair source/controller and package receipts present; production reducer cutover pending**

Recorded: `2026-08-11T05:33:20Z`

## Defect confirmed

The legacy final-audit controller incremented `finalRepairRounds` once when it
created a repair batch. If later whole-graph approval made multiple pending
repair nodes redundant, cleanup deleted those nodes and decremented the round
counter by the number of nodes. A single round containing two nodes therefore
refunded two rounds. Deleting the nodes also refunded capacity under the
32-node ceiling.

Because `GraphLoopState` persists the already-refunded values, a crash or
relaunch preserved the reopened budget rather than the work actually consumed.
The system could cycle through create, approve, delete, refund, and recreate
without a monotonic lifetime bound.

## Repair

Final-repair budgets are now durable and monotonic:

- the eight-round limit is a named policy constant;
- one policy function checks both cumulative historical node count and the
  persisted round count;
- redundant pending repair nodes are cleaned up operationally but retained in
  graph history as `superseded` tombstones;
- each tombstone records its retirement timestamp and reason, clears active and
  blocked clocks, disables retry, and detaches its thread;
- `finalRepairRounds` is never decremented;
- the historical node array is never shortened to refund the node ceiling;
- active scheduling and terminal presentation continue to ignore superseded
  nodes while forensic reconstruction keeps them;
- JSON encode/decode replay preserves the exhausted round and cumulative node
  budgets.

## Adversarial verification

A synthetic graph starts at the eighth and final repair round with one completed
frontier and two redundant pending repairs created by the same round. Retirement
must:

- return both exact IDs in deterministic order;
- leave `finalRepairRounds == 8` rather than subtracting two;
- retain all three historical nodes;
- mark both repairs superseded at the exact supplied time;
- reject further final repair creation;
- encode and decode to the same exhausted state;
- continue rejecting repair creation after replay.

The complete Graph, scheduling, recovery, integration, visual, mutation,
runtime, reporting, and package suites remain green.

## Verification

- focused Graph suite: **93 tests, 0 failures**;
- complete source suite: **595 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **595 tests, 8 environment-gated skips, 0 failures**;
- Release build, ad-hoc signature, exact source/test manifest, ZIP, DMG,
  checksums, executable startup, cleanup, and zero residual packaged processes
  verified.

Receipts:

- source snapshot: `dda1d99d37a447ab71ee22a10f38c9c4cabbe121c28c25876299ea16c873a4ab`
- Graph source: `29d84f2f9aae48cea6a618bcb072eacdf504776f1f1bb217341539615aa9b5c5`
- Graph tests: `a4574dad68f1795159ed9a3e697732ece559dcad20893ae2031a22a4d0511699`
- focused log: `8ddd325a0ca7bfe97f0c69c3e64ab74046c41c6d3976ad1bc2484bc255ea7862`
- full source log: `693bb679c2c8241dbeb262c0a36b31e163111a8dd2efa3e104057ee300a5f9e8`
- package test log: `f1f9a46fa6cea869cf7eb3b10b15dd8f5a3bda11694fa9aa598ef5d6921a4952`
- package command log: `1eb915ab8d392015378052f629893c620f0a4274fddf1dfb11580a29a78bcdcf`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `eb071a1464372d799b0a0e36ba882fc9a58388c8d97c5531476a6e08d5aed4d9`
- executable: `53fe51fa71cb67fec750460cd6919858dcfa041731f15f99e51ed6122bc1142d`
- ZIP: `3088b21e3280eb18fda0351ff416211c10007ba21a477daf2b65dc21fb333dd0`
- DMG: `4df1ecf02710f1f0cdc5d8ec20cef666c8b6bb6d29f1bf6cf36fec529397390a`
- CDHash: `7d4f7873eaa3db85860380a747a83cacd7f83e1a`

## Boundary

This closes the concrete legacy final-repair refund and replay path. Full F-07
acceptance still requires the journal reducer's typed strategy, attempt,
failure, damage, and replacement-lineage budgets to own production execution;
the legacy graph continues to use coarse round/node counts rather than causal
cost. Current unlocked native proof, a clean commit, and push also remain.

EasyBusiness remained permanently stopped and read-only.
