# Non-Mutating Release Containment Classification

Status: **the ordinary macOS package is explicitly non-mutating, retains the exact pre-effect containment veto, passes package/native verification, and is included in the final accepted release**

Recorded: `2026-08-16T14:48:15Z`

## Decision

LoopForge's ordinary macOS bundle has no privileged helper, VM, or container
that can truthfully issue the non-serializable physical-memory containment
authority required before canonical workspace mutation. The accepted release
alternative is therefore the retained veto, not a fabricated in-process
issuer.

Commit `4c6bbf8694f4b7caaf9723e2bca6e2a96d1010ba` makes that
boundary machine-readable. `LoopForgeReleaseMutationCapabilityClassification`
contains only `nonMutatingContainmentVeto` and `unavailableFailClosed`; neither
permits workspace mutation. There is deliberately no mutation-capable enum
case in the ordinary application.

## Manifest and loader binding

Both package manifests must declare:

- `releaseMutationCapabilityClassification = nonMutatingContainmentVeto`; and
- `workspaceMutationAvailable = false`.

The package-owned provider-manifest loader rejects an availability Boolean of
`true`, a relabeled unavailable classification, a missing field, or any
cross-field inconsistency. A manifest edit therefore cannot mint the live
contract/run/transaction-exact capability consumed by the production
coordinator.

## Controller boundary retained

The complete-candidate production path still resolves ordinary macOS to the
typed terminal containment-unavailable result. It journals one exact
`KernelProductionMutationApplyVetoReceipt` while the integration remains
`rollbackPrepared`, before workspace lease admission, apply intent, outbox
persistence, or canonical filesystem effects. The existing strategy-level
test passed through that full production composition in 1.486 seconds.

This classification grants no mutation authority and does not weaken the
separately tested DEBUG fixture capability. If a future product ships a
privileged/container issuer, it requires a separately isolated and ratified
architecture rather than another ordinary-app enum state.

## Native disclosure

The root view now exposes a distinct release-mutation banner:

`Workspace mutation vetoed · No privileged or container containment issuer is packaged; canonical workspace writes are denied.`

Missing or invalid packaged metadata displays an unavailable fail-closed
variant with the same denied-write result.

The exact clean evidence revision
`6fabd99e94d73d6e21faf17e9e576515843b362a` was packaged with
`sourceDirty=false` and source snapshot
`7db21a46bdfe9f2795695eafc91c91af71e1163c4557c6620905b92e64253c39`.
Both embedded manifests carry the exact non-mutation declaration. The
package-owned suite passed 886/8/0 in 83.689 XCTest seconds; Release
compilation, deep-strict signing, ZIP/DMG/checksum validation, provider
self-test, source/test binding, and isolated startup smoke passed.

Computer Use inspected that signed package under
`--isolated-inspection-profile`. The Accessibility tree simultaneously exposed
the non-productive, workspace-mutation-veto, and isolated-profile banners; the
Watcher list was empty, the authority/completion contract remained visible,
and Build Watcher was disabled. The
[1060×752 native receipt](../screenshots/packaged-loopforge-nonmutating-release-containment-20260816T1455Z.png)
has SHA-256
`b0129b04db012154429b1ece2a7424ae8970490aca3f96637c60eebad8e55063`.

The user's primary and backup Watcher stores retained SHA-256
`a59ca5375c6ee3c78de63773df68b20e80106ef15ad1fd7b85776ba78a584d71`,
891807 bytes, and mtime epoch 1786885277. Quit left zero packaged/helper
processes and zero verification mounts.

## Verification

- Provider-manifest classification tests: 8 executed, 0 failures, 0.013
  seconds in the focused run.
- Complete-candidate production veto path: 1 executed, 0 failures, 1.486
  seconds.
- Complete source suite: 886 executed, 8 environment-gated skips, 0 failures,
  81.035 XCTest seconds.
- Clean package-owned suite: 886 executed, 8 environment-gated skips, 0
  failures, 83.689 XCTest seconds.
- `git diff --check`: passed before the implementation commit.
- Commit patch SHA-256:
  `ee437699f78720af2e24734fe4f2e4d2bfe3e5b91b0be2402364e4090965873b`.

EasyBusiness remained read-only on branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Gate result

This closes the Release-containment/mutation-isolation alternative across
source, exact package manifests, smoke policy, and the real native UI by
retaining and explicitly classifying the non-mutation veto. The formerly
remaining repository-generation question is closed by the
[non-mutating repository-telemetry disposition](NON_MUTATING_REPOSITORY_TELEMETRY_DISPOSITION.md),
which does not invent an accepted transition or cache hit.
