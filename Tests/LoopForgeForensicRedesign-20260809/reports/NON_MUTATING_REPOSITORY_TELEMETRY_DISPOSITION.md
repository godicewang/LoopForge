# Non-Mutating Repository Telemetry Disposition

Status: **source implementation and adversarial verification pass; clean package and native disclosure pending**

Recorded: `2026-08-16T15:12:16Z`

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

## Remaining verification

This source decision closes the semantic contradiction: a package that cannot
accept workspace mutation is not required to manufacture the very transition
needed for resolved generation telemetry. Clean package-owned tests, exact
dual-manifest inspection, signing/hash/smoke verification, and real native UI
inspection still must bind this source decision before final release can be
claimed.
