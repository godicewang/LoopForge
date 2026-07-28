# Changelog

All notable user-visible changes are documented here.

## [1.0.0] — 2026-07-28

### Added

- Native Auto Loop with editable active-runtime targets, evidence audits,
  checkpoint recovery, candidates, and self-contained HTML delivery reports.
- Dependency-gated Auto Graph with isolated Git worktrees, join-group reviews,
  incremental risk audits, retained replacement history, and inspectable node
  activity.
- Continuum Watcher for bounded, idempotent local pipelines with durable
  checkpoints, structured telemetry, anomaly rules, cooldowns, periodic Agent
  review, and adaptive repair.
- Official Codex, OpenAI-compatible API, and opt-in Ollama model routes for
  Loop Control and Sub Agent roles.

### Hardened

- Successful active-process time accounting; offline, failed, paused, control,
  and download time is excluded.
- Atomic persistence and safe interruption recovery.
- Watcher path, file, cardinality, output, timeout, freshness, revision, and
  environment-secret boundaries.
- Full graph predecessor, integration, and review gates before successor
  dispatch.

### Validated

- 17 comprehensive cross-module release scenarios.
- 205 tests executed with 0 failures and 6 explicit external-environment skips.

[1.0.0]: https://github.com/godicewang/LoopForge/releases/tag/v1.0.0
