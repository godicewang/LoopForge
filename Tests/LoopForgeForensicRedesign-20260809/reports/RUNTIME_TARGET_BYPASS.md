# Auto Graph Runtime Target Bypass

Status: confirmed systemic defect. This report records the historical contract failure and the current source path that caused it; it does not declare the redesign complete.

## Finding

Auto Graph does not merely fail to reach the configured runtime target. It deletes the target when the task is created.

The stopped EasyBusiness task was logged as an Ultra task whose estimate started at `10h 00m`, with visual review mandatory. Its startup log then said that control-agent time would not count toward the "hard Sub Agent runtime." The persisted task contradicts both statements:

- `targetSeconds` is exactly `0`;
- all 19 nodes together retain `18,845.36` seconds of nominal node-agent time;
- 12 nodes are completed, five superseded, two waiting;
- the task has audit score `100`, supervisor approval `false`, and no passed visual gate.

The `18,845.36` seconds are not accepted as valid duration evidence. The status-accounting audit already proved that blocked and rejected work can be included in the current total. The important fact here is more fundamental: no nonzero parent target survived task creation, so the engine had no duration contract it could enforce.

## Source-level causal chain

The bypass exists in committed `HEAD` as well as the current dirty worktree.

1. `AppModel.createAndStart` exempts Auto Graph from the minimum-runtime guard (`Sources/LoopForge/AppModel.swift:941-946`).
2. The same function explicitly persists `targetSeconds: 0` for Auto Graph (`Sources/LoopForge/AppModel.swift:951-955`).
3. The UI hides the editable runtime and replaces it with “Evidence-gated graph” and “No artificial runtime minimum” (`Sources/LoopForge/Views.swift:1583-1611`). This removes the user's ability to verify or correct the loss before starting.
4. Each Auto Graph worker task is also constructed with `targetSeconds: 0`; only Parallel Candidates inherits the parent target (`Sources/LoopForge/GraphLoopEngine.swift:5785-5800`).
5. `finalizeOrExpand` checks reviewer approval, workspace audit, and the visual Boolean, but never checks `targetSeconds` or any accepted task-level runtime (`Sources/LoopForge/GraphLoopEngine.swift:5194-5404`). Once those Boolean gates pass, it writes `status = completed` directly.
6. `LoopTask.progress` uses completed-node fraction for every non-single-loop mode and ignores time (`Sources/LoopForge/Models.swift:761-768`). A changing plan denominator can therefore move progress independently of the user's hard constraint.
7. Completion reports describe Auto Graph only by concurrency, not by the configured runtime or whether it was satisfied (`Sources/LoopForge/CompletionReportGenerator.swift:126-139`).

This is a deterministic design choice, not a transient provider failure.

## Two separate contract losses

There are two independent failures and both must be fixed.

### Operator-to-task loss

The outer assignment required a long-running two-pass process, but the `originalRequest` persisted inside task `1ED2180F-FBE1-4BCA-9E79-701F40CC3483` contains only the first-round product assignment. It does not contain the ten-hour minimum or the full second-pass LoopForge-improvement contract. The operator compressed a multi-phase requirement into a narrower node objective before Auto Graph saw it.

### UI-to-engine loss

Even if the operator had configured a ten-hour runtime in the start screen, Auto Graph would still have written zero. The startup estimate is displayed and logged, but the persisted engine contract is discarded by mode-specific code.

The second failure makes the first one harder to detect: neither the task detail nor the final report can show that a requested duration disappeared.

## Misleading observability

The task log repeatedly says:

> Control-agent review time never counts toward the hard Sub Agent runtime.

That sentence implies a nonzero denominator and an exclusion policy. Auto Graph has neither at task level. The log records a guarantee the engine cannot evaluate.

The graph overview currently labels a sum as “Node-agent work.” In the dirty repair it additionally shows per-node “All iterations” and “This iteration,” which responds to the user's observability request, but `liveActiveSeconds` still includes rejected, blocked, superseded, and pending iteration records. More detailed display of an invalid total would improve visibility while preserving false accounting.

## Required redesign contract

The corrected design must make runtime a task-level invariant, not a worker prompt decoration:

1. Persist the user-confirmed target for every execution mode, including Auto Graph.
2. Store an immutable runtime contract with metric type, target, source, confirmation time, and exclusions. For this product the default metric should be successful non-overlapping active wall time; parallel agent-seconds must be a separately labelled diagnostic.
3. Maintain an append-only interval ledger at task level. Only intervals with typed successful dispositions may contribute.
4. Never sum overlapping parallel nodes into the hard wall-time target.
5. Require `acceptedRuntime >= targetSeconds` as an independent conjunction in final completion. Review, audit, visual, requirements, and runtime gates must all pass.
6. Keep node goals bounded; when useful work is exhausted before the target, pause for an explicit scope decision rather than manufacture churn to consume time.
7. Show target, accepted total, current eligible interval, excluded totals, and remaining time in the native UI and generated report.
8. Quarantine legacy Auto Graph tasks with `targetSeconds == 0` when their creation logs contain a nonzero estimate or their original assignment contains a duration requirement. Do not silently invent a migrated value.
9. Add deterministic tests proving that Auto Graph start, persistence, relaunch, finalization, and reporting retain and enforce the exact target.

## Acceptance tests implied by this finding

- Starting Auto Graph with 36,000 seconds persists exactly 36,000 seconds.
- A fully approved graph at 35,999 accepted seconds remains non-completable.
- A graph with 36,000 summed parallel agent-seconds but only 18,000 non-overlapping active wall seconds remains below target.
- Blocked, rejected, failed, interrupted, idle, sleep, and reviewer intervals never advance accepted runtime.
- Relaunch reconstructs accepted runtime from durable intervals without adding offline time.
- The native UI and HTML report expose the same target, accepted, excluded, live-current, and remaining values.

The machine-readable companion is `RUNTIME_TARGET_SCORECARD.json`.
