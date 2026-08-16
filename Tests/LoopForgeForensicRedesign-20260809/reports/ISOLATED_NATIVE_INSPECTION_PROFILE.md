# Isolated Native Inspection Profile

Status: **current clean package provides operation-free native inspection without loading persisted work; final release remains false**

Recorded: `2026-08-16T13:39:36Z`

## Incident-driven hardening

The prior package inspection unintentionally resumed a persisted Watcher. Clean
commit `edb3a96c9bdd406b30636d190359b10e7c45e4b2` closes that verification
hazard with one explicit `--isolated-inspection-profile` launch mode.

Before constructing stores or the production recovery registry, the flag
redirects LoopForge-owned Application Support state to one process-specific
temporary root. Watcher, task, model, host-resource, and kernel-recovery state
therefore cannot resolve to the user's persisted records. Startup skips
permission onboarding, Codex connection, and Watcher scheduling. New Watcher
builds, new task enrollment, and native activation also fail closed. A visible
banner states `Isolated inspection profile · Persisted work and startup
automation are not loaded.`

Normal launch behavior is unchanged. The isolation contract is opt-in and the
resolver test proves that omitting the exact argument selects the standard
profile.

## Verification

Two focused tests passed with zero failures. The complete source suite passed
880 tests with 8 environment-gated skips and 0 failures in 92.965 seconds. The
clean package-owned suite passed 880/8/0 in 77.681 seconds, then rebuilt and
signed the exact-source app, ZIP, and DMG.

The package binds clean revision `edb3a96…e4b2`, source snapshot
`6ffbc1a8839ff5948d8d6b8dcff3f797fc034aaef58de6e4a25ca7392ad15d1c`,
and package-test digest
`30ab90fd3f3d21e50957191eee26bc379af711f3bd3c04c23400516fe70fcec6`.
The executable SHA-256 is
`889e341268c107dbaf37271df8857c5fe6da8eaae1662eef6490d718fa1c3d4a`
and its ad-hoc CDHash is `e1b1a17c2870b2954242d27b3a14b83fa28c266c`.

## Native proof

Computer Use launched the exact packaged executable with only the explicit
inspection argument. The real 1060×752 native window showed:

- the isolated-profile banner;
- an empty Watcher list and `Scheduler ready`;
- the current authority/completion contract; and
- disabled `Build Watcher` with no target or project selected.

The [native screenshot](../screenshots/packaged-loopforge-isolated-inspection-profile-20260816T1335Z.png)
has SHA-256
`5ce9c28cb06acbc9ff6e63fb5108029fc7e581d79fb12cd1beea2a66beb58a76`.
The process used isolated root
`/var/folders/t6/252rjfwd1wj51c3_kgc4wwym0000gn/T/LoopForgeInspection/Process-64143`.
Only empty recovery locks and the isolated empty host-resource lease registry
were created there.

Before, during, and after the walkthrough, the user's primary and backup
`watchers.json` files retained SHA-256
`a59ca5375c6ee3c78de63773df68b20e80106ef15ad1fd7b85776ba78a584d71`,
size `891807`, and mtime epoch `1786885277`. The previously affected
`Tests/WatcherQuantFactor-20260729` fixture retained aggregate SHA-256
`04fa44cbfb2f72ffc002b937e6d597e22836747b87bc41c949d438353b062794`.
Cmd-Q left zero LoopForge, provider-harness, or sandbox-gate processes and zero
verification mounts.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, and NUL-delimited status digest
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Boundary

This closes operation-free package inspection and makes future native UI
audits reproducible without pausing or rewriting user Watchers. It does not
exercise the live Watcher review/completion chain, create repository-generation
telemetry, install a productive provider, or supply the intentionally absent
Release containment and mutation-isolation authorities. Those release gates
remain pending.
