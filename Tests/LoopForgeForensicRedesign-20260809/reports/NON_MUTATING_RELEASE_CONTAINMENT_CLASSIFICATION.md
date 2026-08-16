# Non-Mutating Release Containment Classification

Status: **the ordinary macOS package is explicitly non-mutating and retains the exact pre-effect containment veto; package and native rebinding are pending**

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
variant with the same denied-write result. Package and native evidence will be
added only after a clean evidence revision is built, signed, hashed, launched
under the isolated inspection profile, and quit cleanly.

## Verification

- Provider-manifest classification tests: 8 executed, 0 failures, 0.013
  seconds in the focused run.
- Complete-candidate production veto path: 1 executed, 0 failures, 1.486
  seconds.
- Complete source suite: 886 executed, 8 environment-gated skips, 0 failures,
  81.035 XCTest seconds.
- `git diff --check`: passed before the implementation commit.
- Commit patch SHA-256:
  `ee437699f78720af2e24734fe4f2e4d2bfe3e5b91b0be2402364e4090965873b`.

EasyBusiness remained read-only on branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Gate result

This closes the Release-containment/mutation-isolation alternative at source
by retaining and explicitly classifying the non-mutation veto. Final release
remains false. Resolved repository-generation telemetry still requires a
separate explicit disposition for this non-mutating product classification.

