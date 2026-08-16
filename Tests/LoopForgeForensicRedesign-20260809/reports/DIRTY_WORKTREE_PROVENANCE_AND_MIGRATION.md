# Dirty Worktree Provenance and Migration Plan

Status: preserved forensic baseline; no tracked production edits were made by this audit.

## Provenance lock

- Git baseline: `6e9b99d` on `main`, equal to `origin/main` at inspection.
- Existing tracked delta: 24 files, 6,387 insertions, 263 deletions.
- Current binary-diff SHA-256: `b238cb0b677d44e7f222c3713e1668ff3944653024757af78e49e7b31756eaae`.
- Preserved patch: `evidence/loopforge-preexisting-tracked-changes-20260809T134109Z.patch`.
- Preserved patch SHA-256: `b238cb0b677d44e7f222c3713e1668ff3944653024757af78e49e7b31756eaae`.

The hashes match exactly. This proves the tracked dirty worktree has not changed during the forensic/report phase. `AGENTS.md` and this audit directory are new LoopForge-only governance/evidence artifacts.

## Tracked-delta concentration

| Area | Dominant files | Existing delta character |
|---|---|---|
| Graph convergence/integration | `GraphLoopEngine.swift` (+2,029/−120), `GraphLoopTests.swift` (+1,309/−4) | strategy-retirement patches, timing/history, integration recovery, workspace behavior |
| Watcher | controller/models/policy/prompt/views and `WatcherTests.swift` | assessment/dashboard layer, cadence/review behavior, reporting/presentation |
| Runtime/process | `CodexRunner.swift`, `ProcessRunner.swift`, `LoopController.swift`, lifecycle tests | active-time reconciliation, watchdogs, descendant termination, cleanup guidance |
| Persistence/UI | `TaskStore.swift`, `Views.swift`, `CompletionReportGenerator.swift`, tests | graph-log batching, checkpoint behavior, displayed total/current iteration time |
| App/permission/package | app lifecycle, permission automator, package script | close/quit behavior, permission safety, broker packaging |

The largest patch is precisely where the systemic defects are concentrated. Treating it as a stable foundation would preserve its prose contracts, lexical strategy comparison, mutable flags, and self-review semantics.

## Untracked state that must remain preserved

### Active code/resources already included in the full audit

- `Resources/bin/loopforge-host-resource-broker`
- `Sources/LoopForge/HostResourceLeases.swift`
- `Sources/LoopForge/WatcherFocusProjector.swift`
- `Sources/LoopForge/WatcherReportGenerator.swift`
- `Tests/LoopForgeTests/HostResourceLeaseTests.swift`

These files are part of the 64-file/37,444-line manifest and were fully reviewed.

### Large historical evidence suites

- `Tests/EasyBusinessUSGraph-20260802` — 2.4 MB
- `Tests/WatcherEvaluation-20260729` — 5.2 MB
- `Tests/WatcherMatrix-20260729` — 736 MB
- `Tests/WatcherQuantFactor-20260729` — 131 MB

They are historical evidence, not active package source. They must not be deleted, rewritten, or accidentally committed wholesale without a separate retention decision. Their original scenario/baseline artifacts must remain immutable.

## Migration disposition

### Preserve as immutable characterization evidence

- the exact tracked patch and baseline commit;
- all historical test/evidence directories;
- current `tasks.json`/Watcher/log evidence outside the repository;
- all 281-test characterization outputs;
- contradictory legacy states and review prose.

Do not “clean up” historical contradictions. Import them as untrusted legacy evidence.

### Reuse only after converting to typed primitives

- `ProcessRunner` descendant enumeration/escalation → process/session resource provider with quiescence receipts;
- host-resource borrowed/owned distinction → generic capability/resource lease protocol;
- graph iteration history and total/current timing → event-derived attempt ledger with accepted/excluded dispositions;
- worktree path-scope and unrelated-dirt protection → mutation transaction validator;
- stale/oversized Watcher telemetry checks → typed observation adapter;
- superseded-node history → durable strategy retirement events;
- atomic backup recovery → journal snapshot cache and replay.

### Replace, do not incrementally extend

- mutable Graph engine orchestration in the 6,539-line monolith;
- lexical strategy identity and fixed retry thresholds;
- Full Access default/access inference;
- prompt-only resource and scope enforcement;
- same-Agent review/approval/reporting;
- filename/path/keyword evidence coverage;
- generic command-success failure clearing;
- immediate post-review Watcher reruns;
- whole-store timer checkpointing;
- report and UI claims derived from mutable Booleans;
- vertical core branches and their active core tests.

### Keep only as adapters

- Chrome preflight;
- Photos permissions;
- iOS Simulator broker/provider;
- Codex/ChatGPT authentication UI;
- local/API model transport adapters.

## Safe implementation procedure after the analysis gate

1. Create a dedicated `codex/` branch from the current worktree without resetting or stashing user/pre-existing changes.
2. Retain the binary patch and manifest hashes as rollback evidence.
3. Add the new kernel beside the legacy engine; do not mass-edit the monolith first.
4. Route deterministic tests through the new journal/reducer before changing the UI.
5. Migrate reusable behavior behind typed interfaces and compare event projections with legacy characterization fixtures.
6. Disable—not delete—the legacy Graph entry only after deterministic replay proves the new path.
7. Replace active incident-specific tests with neutral core tests while preserving historical fixtures in the forensic pack.
8. Rebuild the UI from typed projections after the state/evidence model is authoritative.
9. Commit only reviewed LoopForge source/report/test changes; exclude large historical artifacts unless already intended for repository retention.
10. Push only after tests, package, signature/hash, native UI, resource quiescence, and dirty-path review all pass.

## Rollback boundary

At every implementation slice, rollback means restoring the exact pre-slice journal/source state while leaving the preserved preexisting patch and unrelated historical directories untouched. No operation may use broad reset, checkout, stash, or recursive deletion against the worktree.
