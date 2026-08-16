# Non-Mutating Repository Telemetry Disposition

Status: **source, clean package, and real native disclosure pass; release disposition closed without manufacturing a workspace transition**

Recorded: `2026-08-16T15:20:26Z`

## Decision

Resolved repository-generation telemetry is not a release prerequisite for
LoopForge's ordinary non-mutating macOS bundle. The bundle cannot create a
journal-accepted workspace transition, so an exact run without such a
transition remains truthfully `notApplicable`. A resolved generation or cache
hit must never be seeded merely to make a release scorecard green.

This is a release-policy disposition, not a replacement for per-run journal
evidence. A genuine historical accepted transition may still resolve through
`RunJournal` and the repository indexer. The new classification neither mints
that transition nor converts `notApplicable`, ambiguous, pending, or failed
states into resolved telemetry.

## Typed package boundary

Commit `7a6e1d6c20c4ccfe3260803cdeef6d1bac989920` adds
`LoopForgeRepositoryGenerationTelemetryDisposition` with only
`nonMutatingNotApplicable` and `unavailableFailClosed`. Both declare
`resolvedTelemetryRequiredForRelease == false`; there is deliberately no case
that claims a resolved transition or cache hit.

Both package manifests must declare:

- `repositoryGenerationTelemetryDisposition = nonMutatingNotApplicable`; and
- `resolvedRepositoryGenerationTelemetryRequired = false`.

The package-owned loader requires the exact keys and cross-validates them with
the existing `nonMutatingContainmentVeto` and
`workspaceMutationAvailable=false` declarations. It rejects a forged resolved
telemetry requirement, a relabeled unavailable disposition, unknown keys,
missing keys, or any mutation-capable manifest claim.

## Existing runtime proof retained

The journal/index path remains stricter than the release classification:

- `RunJournal` is the sole Release issuer of an opaque accepted generation;
- the cache key binds canonical root, workspace identity, generation, journal
  frame, and recipe;
- the focused indexer test computes once and returns a memory hit only when the
  identical opaque generation is presented again;
- a changed generation recomputes;
- absent generation authority performs uncached observation twice and records
  zero cache lookups or computations;
- cross-root receipt reuse and incomplete journal provenance fail closed.

The native exact-run projection continues to distinguish
`No accepted workspace transition` from `Resolved journal generation`. The new
root banner will disclose the release-level disposition without altering those
run-local states.

## Source verification

- Manifest and adversarial classification suite: 10 executed, 0 failures,
  0.016 XCTest seconds.
- Repository indexer suite: 5 executed, 0 failures, 0.010 XCTest seconds.
- Exact-run presentation suite: 4 executed, 0 failures, 0.001 XCTest seconds.
- Complete source suite: 888 executed, 8 environment-gated skips, 0 failures,
  87.936 XCTest seconds.
- `git diff --check`: passed before commit.
- Commit patch SHA-256:
  `d40c75dc664e4cb6db40a15983950dd0b7ff9b6e6800e7a23091a4403af28bf3`.

EasyBusiness remained read-only on branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status SHA-256
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Clean package and native verification

Clean evidence revision `e8b245d88031c338c2ef0a883c5546fa8e3d49ad`
was packaged with `sourceDirty=false` and source snapshot
`98268af60e4bd80e42a7019c73adc97261de9db00f79bff94a5318ca906617bc`.
The package-owned suite passed 888/8/0 in 84.319 XCTest seconds. Release
compilation, deep-strict signing, ZIP/DMG/checksum validation, embedded
source/test binding, provider self-test, and isolated startup smoke passed.

Both embedded manifests carry the exact telemetry disposition and false
requirement alongside the existing non-mutation declaration. Computer Use
opened the exact signed package under `--isolated-inspection-profile`; the
Accessibility tree exposed:

- `Repository telemetry not required`;
- `This package cannot create an accepted workspace transition; exact runs
  without one remain not applicable.`;
- the non-productive and workspace-mutation veto banners;
- zero persisted Watchers, the authority/completion contract, and disabled
  Build Watcher.

The [1052×746 native receipt](../screenshots/packaged-loopforge-nonmutating-repository-telemetry-20260816T1518Z.png)
has SHA-256
`aa6cd6e1a20b0bd82e0b3e5285d65753b04af7894aed5802e3528f1330a58024`.
The user's primary and backup Watcher stores retained SHA-256
`a59ca5375c6ee3c78de63773df68b20e80106ef15ad1fd7b85776ba78a584d71`,
891807 bytes, and mtime epoch 1786885277. Cmd-Q left zero packaged/helper
processes and zero verification mounts.

Package artifacts:

- executable: 26,687,568 bytes,
  `8cd9ae5615ca2ea128a8a4ff850f6385430e8a59371b753933cd98c204c2d1fc`;
- ZIP: 253,533,070 bytes,
  `038a3c90cf9e3b80b929508084491fac6431267cf049c775cfca977391271d5f`;
- DMG: 285,755,544 bytes,
  `45463fd73e960caf1f26563985528a3018b360f6ce622ac58e8472625a071493`;
- build manifest: 736 bytes,
  `3ab2c60d07a3a28cfe8de2782751dec41c116b588245cf085e3867e9ebcee457`;
- provider manifest: 686 bytes,
  `ec43d7d7d1c19037bc8ca908af5da4c5941ac4a5a85b899ed6040a25ed4d2b9a`;
- package test log: 254,721 bytes,
  `208f2aa4fb8b383c3571c427c460c13aee18c1947ecb7c41cbf2f60a3ac6739f`;
- app CDHash: `7d45bc877396330a8cb265504ff553994d778f9f`.

## Gate result

This closes the semantic contradiction and the last global release gate: a
package that cannot accept workspace mutation is not required to manufacture
the very transition needed for resolved generation telemetry. The real cache
implementation remains receipt-gated and tested, while the current native
state stays honestly not applicable. EasyBusiness remained stopped and
read-only.
