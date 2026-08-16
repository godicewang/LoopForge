# Legacy Auto Graph Execution Retirement

Status: **historical Auto Graph start, automatic resume, candidate-selection bypass, and startup report rewrite retired; native execution replacement pending**

Recorded: `2026-08-11T09:26:27Z`

## Production retirement boundary

Historical `LoopTask` Graph checkpoints were created under narrative authority
and cannot be imported into the ratified journaled kernel. They remain visible
as evidence but are no longer executable:

- AppModel initialization immediately clears every historical Auto Graph
  `resumeOnNextLaunch` candidate and marks it migration-required;
- automatic recovery excludes Auto Graph before any Codex readiness decision;
- the user-facing detail view has no Resume button for a historical Auto Graph;
- an AppModel resume request returns a migration explanation;
- `LoopController.start` independently refuses Auto Graph before acquiring a
  running slot, starting a timer/activity, checking permissions, launching an
  agent/process, or entering `GraphLoopEngine`;
- repeated blocked start requests are idempotent and do not append log noise;
- candidate selection requires exact `.parallelCandidates` mode;
- AppModel startup no longer regenerates `.loopforge/reports` inside completed
  Graph workspaces without an explicit user action.

The block changes only LoopForge's retained task status and log. Workspace,
graph, checkpoint, and report bytes are preserved. Stop-time resource cleanup
remains available and does not admit worker execution.

## Adversarial verification

The controller fixture records a workspace sentinel, attempts a direct start on
a resumable Auto Graph, and proves: no running task ID, no clock ticker, exact
blocked migration state, cleared auto-resume, unchanged sentinel bytes, no
architecture/worker log, and idempotent repeated denial.

The static production call graph finds two `graphEngine.run` sites: one can only
follow exact Parallel candidate selection; the ordinary run site can only be
reached after `LoopController.start`, whose Auto Graph denial precedes running
slot and job creation. All three AppModel `controller.start` sites are therefore
covered by the low-level guard, while new Auto Graph creation never constructs
a legacy `LoopTask`.

Focused lifecycle tests passed **6/6**. The complete development and
package-owned suites passed **619 tests, 8 environment skips, 0 failures**.
The exact-source arm64 app passed deep strict signature, ZIP/DMG/checksum,
direct Mach-O startup, cleanup, and zero-residual-process verification.

## Receipts

- source snapshot: `1303cb7ec1a7f343cf2537825939771a7b0eb70d076f191ace601e0601a99734`
- AppModel: `c3d0df36d464025349bec9b775b17a1bfbab206a7e528734ab880ea0eb74e75e`
- LoopController: `fa2293333a87df913df7e63548e174274b11eaa0a27f360dd59a3c2675e4c06b`
- SwiftUI views: `addfa8bd6489093a1ddcd34cc5bb00e6bddc989bb43ae7e82ceea90d98c48acd`
- lifecycle tests: `cd3a001ce7c0af32f5d77e77fdf6e9672b6523d26b55bb713011b541499a031f`
- focused log: `55bbcbaad9e7c2380a3a723169bc5a41c8ac6037c01b415192617d56cedd3ae3`
- full log: `e3f9a0c9aa9e95153f390a40ea8656ed2ca1898cca192c6450d1ae080b5f7280`
- production call graph: `30a9cfba9d01f2591afd1c8f3d50dac3bfb2191c7e99ab0a4db522c76d8f1760`
- package test log: `afbaf096e4dc6f140ed1c81c567c117346e08fb05307d1fe426c4cd62cbd5448`
- build manifest: `5651eaa4ceabac2460b41f74ce14a8492239b30c5f9935937dd4ed3acd640933`
- runtime smoke: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- executable: `3aa6db2cb2e0b938beec26b911dea2f77716cb3375457d28ea25443971f55dc5`
- ZIP: `b33307733b800612b960dad49e677f24b2a76cd46147d9c5fceb2fad31a8ef03`
- DMG: `a3181075e461c87a8bd23dae15e8f3b2c7ecdf7b0ac73537eb75d3c444d75b23`
- CDHash: `f2c50cea69e67c4eecde5fb7187c3cc26292d8f2`

## Remaining boundary

Retirement is not replacement. New-kernel planning, strategy admission, worker
execution, occurrence timing, verification, visual gates, and integration are
not yet composed into a runnable production coordinator. Single Loop and
Parallel remain legacy. Current unlocked native screenshots, clean-commit-bound
rebuild, commit, and push also remain required. Final acceptance is false.

EasyBusiness remained permanently stopped and read-only.
