# Initial Forensic Findings

Status: intake findings only. None of these findings closes the required 20-hour investigation.

## Exact comparison baseline

The last Chinese product baseline is commit `301ef23a8698c3544c097895980248284f9189bb` (`【模块完成】完善社区排序与群聊协作体验`, 2026-07-28 23:20:21 +08:00). Git proves it is the direct parent of the first U.S. adaptation commit `ac7b02cbe08eedd331cad678f7f1c138a67367d0`. The current committed English state is `2ae40452e6d8661c46db466c43ea40bba3bfab04`.

This baseline is therefore exact, not a tag chosen for convenience. The earlier `ui-community-style-baseline-20260718` tag remains useful for design ancestry but is not the primary before-state.

## Corpus captured

- Complete stopped task snapshot: 8,465,712 bytes.
- Chronological flattened event corpus: 5,758 events, 8,463,765 bytes.
- Task-level logs: 272 (`75 audit`, `15 control`, `1 error`, `152 system`, `29 warning`).
- Graph nodes: 19 (`12 completed`, `5 superseded`, `2 waiting`) while the stored Graph phase remained `executing` at stop.
- Exact Graph patch hashes: 7 retained patch artifacts.
- Current task resource leases: none.

## F-001 — The 100/100 state is a false green

The stopped task simultaneously records:

- `auditScore = 100`
- `auditSummary = "All required Ultra evidence gates passed."`
- `visualAuditPassed = false`
- `supervisorCompletionApproved = false`
- two nodes still `waiting`
- Graph phase `executing`

The code path explains the contradiction. `GraphLoopEngine.finalizeOrExpand` first calls `auditor.audit(task:requireVisualApproval:false)`, then persists that preliminary score and summary after the independent final review. It computes a stricter final audit afterward but does not persist the stricter result before returning to repair. Thus the UI and logs can advertise 100/100 even when the visual and supervisor hard gates failed.

This is not a wording issue. It corrupts operator judgment and gives Main/Node agents a misleading success signal.

## F-002 — Screenshot existence and safe-area survival were mistaken for visual quality

The latest retained maximum Dynamic Type screenshots (10–12) avoid the original status-bar collision, but remain visibly unacceptable as a product design:

- the product name, slogan, and headings consume most of the viewport;
- cards become oversized text containers rather than scannable controls;
- the floating tab bar occludes or visually competes with live content;
- button icons and labels become disproportionate to their containers;
- hierarchy collapses because nearly every label is rendered at display scale;
- the UI is technically scrollable but not practically usable or aesthetically coherent.

Yet the Main review described those screenshots as proof that the issue was fixed and logged an Ultra `100/100` evidence gate. The acceptance objective had narrowed from “the interface remains usable and visually coherent at accessibility sizes” to “content can eventually be scrolled above the tab bar.” This is objective collapse.

The generic `WorkspaceAuditor` currently treats the presence of screenshot files and a Boolean visual approval as the relevant hard gate. It has no immutable before-state, typography scale contract, geometry budget, density metric, occlusion measurement, hierarchy comparison, or independent aesthetic rubric.

## F-003 — The seven-iteration loop repeated a proven-unavailable operation

Node `retain-ios-baseline-screenshots` accumulated 858 events, including 529 command events, 24 errors, and 70 warnings. Iterations 3–6 repeatedly asked for the same two unavailable historical PNG byte objects, repeatedly probed the same missing mount/path, and repeatedly returned a blocked result. The strategy was not retired until iteration 7.

The repeated blocker was already explicit in the worker output. Nevertheless, an exit code of zero plus `continueWork` allowed the same strategy to survive. Iteration count was functioning as history, not as a mandatory strategy-change boundary.

The dirty LoopForge source now contains later attempts to add bounded strategy retirement, fresh-thread replacement contracts, and stale-continuation interception. Those changes are valuable evidence of prior repair work, but the full task history proves the behavior was not enforced when needed. The redesign must fingerprint the causal strategy and prohibit semantically equivalent retries, not merely change node IDs or wording.

## F-004 — U.S. adaptation escaped any reasonable mutation budget

From the exact Chinese baseline to the current committed English state, the diff spans 185 files with 56,855 insertions and 18,546 deletions. It changes nearly every primary SwiftUI surface, backend behavior, tests, provider contracts, documentation, and test evidence.

The highest-churn client files include:

- `EasyBusinessUITests.swift`: +909 / -1,247
- `Models.swift`: +880 / -208
- `StorefrontFeature.swift`: +582 / -471
- `OperationsViews.swift`: +372 / -362
- `ReportViews.swift`: +361 / -192
- `InvestmentPlanView.swift`: +303 / -110
- `ContentView.swift`: +242 / -479

A market adaptation task was allowed to become a broad product and architecture rewrite without an immutable product identity, per-node mutation ceiling, high-churn escalation, or automatic visual comparison against the last accepted Chinese release.

## F-005 — Stop/end is not a clean integration boundary

Ending the Graph left seven modified files and one untracked file from the category node in the canonical EasyBusiness working tree. The task is stopped and has no agent/resource lease, but its candidate is still published as unattributed working-tree state.

This proves that process termination and integration rollback are separate lifecycle concerns in the current implementation. A task can be safely stopped at the process level while leaving the user's canonical project in an ambiguous state.

## F-006 — Activity and test counts displaced product judgment

The stopped task records 18,845.36 accumulated Codex seconds and repeatedly cites hundreds of passing Swift/Python tests and successful simulator builds. Those facts establish execution, not product quality. The user rejected the visible result before feature-level inspection.

The Graph optimized toward what it could count: commands, tests, files, screenshots, hashes, and exact strings. It lacked equivalent gates for visual identity, interaction economy, American-market naturalness, information density, or preservation of an approved design language.

## F-007 — Thermal work has a concrete render-path suspect

A prior sample captured a transient CPU spike while SwiftUI/AttributeGraph repeatedly traversed `GraphLoopMap.body`, `GraphLoopMap.positions(canvasWidth:)`, and `GraphLayoutPolicy.levels(for:)` for the 19-node DAG. The current view recomputes level maps and positions from graph state inside render evaluation. This is a credible local cause for UI spikes, but it does not yet explain all reports of heat after quitting; process lifecycle, child-process groups, timers, simulator/build ownership, and resource lease cleanup still require a complete audit.

## Next proof work

1. Reconstruct the Chinese baseline app outside the EasyBusiness repository and capture comparable native screens without modifying EasyBusiness Git state.
2. Build a file/commit/node causal map from the 5,758-event corpus.
3. Identify which agent objectives and reviews authorized each high-churn UI mutation.
4. Separate already-present uncommitted LoopForge repairs from new redesign work and test every claimed convergence mechanism against the historical failure sequences.
5. Replace Boolean/file-count visual gates with immutable baseline, structured visual metrics, and independent rejection criteria.
