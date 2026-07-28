# LoopForge v1.0 release validation

Validated on Apple Silicon with macOS, Swift Package Manager, real child
processes, temporary Git repositories/worktrees, AppKit screenshots, and the
packaged LoopForge application.

## Scenario pass 1

| ID | Module | Scenario | Result |
| --- | --- | --- | --- |
| R1-01 | Single Loop | Build, run, audit, and generate the HTML delivery report for a dependency-free CLI | Pass |
| R1-02 | Single Loop | Recover a damaged primary task checkpoint from its atomic backup without counting offline time | Pass |
| R1-03 | Auto Graph | Hold all downstream work behind a complete, incrementally reviewed join group | Pass |
| R1-04 | Auto Graph | Resume an interrupted node without manufacturing an extra iteration | Pass |
| R1-05 | Watcher | Detect a sustained service error and suppress alert storms with cooldown | Pass |
| R1-06 | Watcher | Process 2,000 queued items over repeated idempotent passes with no duplicates | Pass |
| R1-07 | Watcher | Aggregate 1,000 security events without leaking IPs, tokens, or parent-process secrets | Pass |
| R1-08 | Watcher | Treat missing and stale signals as current-pass facts and keep informational events asleep | Pass |
| R1-09 | Watcher | Reject stale telemetry and a symlink that escapes the selected workspace | Pass |

## Scenario pass 2

| ID | Module | Scenario | Result |
| --- | --- | --- | --- |
| R2-01 | Single Loop | Carry a fresh real screenshot through visual inspection and the final evidence gate | Pass |
| R2-02 | Single Loop | Persist 150 rapid checkpoints and recover the exact latest durable state | Pass |
| R2-03 | Auto Graph | Retire an unsafe isolated branch, preserve its history, and start a traceable replacement | Pass |
| R2-04 | Auto Graph | Integrate disjoint text and binary results from real parallel Git worktrees | Pass |
| R2-05 | Watcher | Bound a 25 MB no-newline child stream without hanging or retaining unbounded output | Pass |
| R2-06 | Watcher | Reclaim a timed-out child and immediately reuse the process runner | Pass |
| R2-07 | Watcher | Reject oversized telemetry and checkpoint artifacts before decoding | Pass |
| R2-08 | Watcher | Prune 20,000 obsolete high-cardinality keys and avoid waking on routine information | Pass |

## Defects fixed during validation

- Current-pass telemetry must be freshly replaced; stale output can no longer
  masquerade as a successful run.
- Generated paths are resolved through existing symlinks and cannot escape the
  selected workspace.
- Pipeline verification commands are independently rerun by LoopForge.
- Child pipelines receive a minimal environment; unrelated API and CI secrets
  are not inherited.
- Signals, rules, events, paths, files, command arguments, and retained output
  now have explicit safety bounds.
- Duplicate rules, undeclared signal references, ambiguous review markers,
  revision regressions, and malformed telemetry are rejected.
- Missing-signal rules use the current pass instead of silently reusing history.
- Informational telemetry does not wake the Agent.
- Operation and scheduler tokens prevent a cancelled old task from clearing a
  newer task.
- The process line buffer was changed from repeated whole-buffer scans to a
  single-pass bounded stream parser. The 25 MB pressure scenario changed from a
  10-second timeout to a successful run in approximately 2.5 seconds.
- Python-style fractional RFC 3339 timestamps now decode consistently across
  macOS/Swift Foundation releases, including clean GitHub-hosted runners.
- Public-facing workspace paths are abbreviated with `~` to avoid exposing the
  local account name in screenshots.

## Final regression

```text
206 tests executed
0 failures
6 explicit external-environment skips
```

The six skips require credentials, an installed local model, or a real signed-in
browser session and are opt-in by design. The default suite still exercises a
real Codex child through the Responses/Chat bridge, real child-process timeout
handling, real Git worktree integration, and real screenshot inspection.
