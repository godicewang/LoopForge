# LoopForge Native UI System Audit

Status: complete source audit of `Views.swift` and `WatcherViews.swift`; evidence only. No production source was changed. EasyBusiness remained read-only.

## Scope and method

This audit reads every line of the two active SwiftUI surfaces (5,138 lines total) and relates the rendered presentation to the already-proven EasyBusiness regression. It does not judge isolated colors or personal taste. It checks whether LoopForge has enforceable systems for typography, geometry, density, evidence semantics, privilege disclosure, convergence visibility, and accessibility.

Mechanical inventory:

- the two files contain 73 literal numeric `cornerRadius` uses across ten distinct values (8–17), excluding variable radii;
- they contain 32 literal point-size font uses across 18 distinct sizes (8–38 pt), in addition to semantic fonts;
- major sheets/cards are fixed at 430, 510, 600, 650, 680, 760, 780, 900, 1,080, and 1,280 points, with many fixed or minimum row/card heights;
- no shared typography scale, spacing scale, shape-role taxonomy, compact-density mode, or viewport contract exists in either file.

The result is the same failure mode observed in EasyBusiness: individual rectangles remain technically valid while the hierarchy, density, and relationships drift.

## Findings

### F-112 — High — Literal typography values replace a coherent native type system

`Views.swift` uses literal sizes from 8 to 38 points for clocks, labels, headings, logs, badges, and editor content (`Views.swift:52-66,164-205,673-755,1211,1592,1725,3207-3469`). `WatcherViews.swift` independently defines another set from 17 to 30 points (`WatcherViews.swift:267,560,712-727,1008,1353-1542`). These values do not share named roles or scaling behavior.

Required redesign: a small semantic type-role system backed by native text styles, explicit monospaced data roles, minimum legibility policy, and screenshot gates at multiple content sizes and window widths.

### F-113 — High — Shape language is a pile of local constants, not a design contract

The two views use ten literal corner radii and several circles/capsules with unrelated padding, opacity, border, and height choices. Even nominally equivalent panels vary between radius 12, 13, and 14 and between material, control-background, primary-opacity, and accent-opacity fills (`Views.swift:1686-1687,2041-2042,2071-2072,2204-2205,2253-2254,2393-2394,2515-2516,2855-2856,3140-3141,3239-3240`; `WatcherViews.swift:1599-1617`).

Required redesign: role-based primitives such as canvas, panel, inset, control, status, and destructive state. Tokens must specify radius, padding, border, material, elevation, focus treatment, and accessibility contrast as one versioned contract.

### F-114 — High — Fixed geometry makes density and accessibility failures predictable

The primary surfaces use fixed widths/heights for onboarding cards, connection sheets, model management, prompt selection, graph nodes, inspectors, and the expanded graph (`Views.swift:201-205,289-291,604,831-832,1156,1255,1351,1764,2674,2690,2947`). Watcher creation and guide surfaces repeat fixed maximum widths, heights, and minimum card heights (`WatcherViews.swift:282,498,562-563,625,655,687-689,1366,1479`).

Required redesign: window-size classes, content-driven layouts, declared density budgets, adaptive column collapse, scroll-priority rules, and initial-viewport assertions. `minimumScaleFactor` and eventual scrolling are not substitutes for composition.

### F-115 — Critical — Presentation semantics certify evidence that the state model does not prove

Completed tasks are labeled “All required evidence is verified,” and Boolean fields produce green “Code review” and “Visual proof” gates (`Views.swift:2060-2085`), although the forensic audit proved those values can derive from self-authored tests and same-agent review. Any latest control audit is rendered with a green seal and green panel regardless of whether its decision is continue, recover, blocked, or reject (`Views.swift:3169-3191`).

Required redesign: UI status colors and language must be projections of typed, provenance-bound receipts. “Submitted,” “self-checked,” “independently verified,” “accepted with waiver,” and “rejected” are separate states; generic logs never receive a green approval treatment.

### F-116 — High — Prompt-refinement UI makes an unqualified correctness claim

The prompt chooser states “Every option passed exact-value and constraint preservation checks” (`Views.swift:1698-1701`) without showing requirement IDs, exact-value diff, evaluator identity, or audit receipt. The same control system that generated the options supplies the claim.

Required redesign: display requirement-preservation evidence per candidate, fail closed on any unmatched immutable constraint, and label generative similarity checks as advisory until independently evaluated.

### F-117 — High — Invisible gestures mutate the execution architecture

When Auto Graph is selected, tapping the plain “Single Loop Task Quality” heading or subtitle silently switches to Single Loop (`Views.swift:769-809`). The heading has no button affordance, role, focus treatment, or accessibility explanation.

Required redesign: execution mode changes only through explicit controls with visible selected state, keyboard support, an announced contract diff, and confirmation when immutable runtime or authority constraints would change.

### F-118 — Critical — Auto Graph UI advertises the runtime-target bypass as a feature

The estimate panel replaces the requested duration with “Evidence-gated graph” and “No artificial runtime minimum,” then promises the graph will repair nodes “until the integrated result passes” (`Views.swift:1583-1624`). This is the user-facing counterpart of F-111 and masks an unbounded, self-approved termination rule.

Required redesign: show every immutable user constraint, bounded total/attempt/mutation budgets, elapsed productive work, retired strategies, current failure signature, remaining authority, and independent completion state before start and throughout execution.

### F-119 — High — The graph visualization hides the dimensions required to diagnose non-convergence

Node cards now correctly show cumulative and current-iteration active time (`Views.swift:2716-2761`), but do not show attempt budget, strategy identity, repeated failure signature, evidence novelty, mutation footprint, rollback point, reviewer independence, or why another iteration is justified. A red branch says only “Stopped by plan review.”

Required redesign: each node exposes a compact convergence vector and an inspectable causal chain. Repeated equivalent strategies must be visually grouped, and a retired branch must retain its lesson and replacement rationale.

### F-120 — Critical — Watcher UI normalizes unconditional Full Access

The Watcher guide explains Full Access as a normal capability and the creation form displays a fixed orange “Full Access” badge with no access selector (`WatcherViews.swift:74-83,388-400`). This matches the controller behavior in F-102: the same Agent authors, repairs, verifies, and approves inside the project.

Required redesign: least privilege is the default; requested capabilities are derived from an explicit plan, reviewed by the user or policy engine, time-bounded, path-bounded, revocable, and separated between author/executor/reviewer.

### F-121 — Critical — Watcher “assessment” visually launders same-agent judgment

The overview renders confirmed, dismissed, and resolved issues with authoritative labels and green resolved styling (`WatcherViews.swift:848-937`), although the same Full Access Agent generated the pipeline and assessment. “No active anomalies” is also rendered from the projected state (`WatcherViews.swift:769-780`) without an independent coverage receipt.

Required redesign: distinguish pipeline observations, author opinion, independent adjudication, and user acceptance. Dismissal/resolution requires evidence provenance and a causal link to the original finding.

### F-122 — High — Watcher creation promises safety and wake restraint that runtime does not enforce

The guide says cadence tuning is safe, only signals/failures/scheduled reviews/user actions wake the Agent, and the first build has real verification (`WatcherViews.swift:63-83`). The build screen says intelligence wakes only when it adds value (`WatcherViews.swift:266-271`) and loading copy calls the first pipeline verified (`WatcherViews.swift:1194-1201`). F-100/F-101 already prove warnings and failures can bypass cadence and enter a tight review/rerun cycle.

Required redesign: product copy must be generated from enforced policy capabilities, not aspiration. Show the current causal wake reason, cooldown, backoff, novelty check, retry budget, and last cleanup receipt.

### F-123 — Medium — Domain-shaped dashboard presets leak vertical assumptions into core UI

The Watcher presentation hard-codes operations, batch, experiment, condition, research, and data-quality labels/symbols/colors (`WatcherViews.swift:1292-1338`) and creation examples privilege monitoring/batch/experiments (`WatcherViews.swift:288-307`). These are not plug-in capabilities; they are product taxonomy embedded in the core surface.

Required redesign: core UI renders typed capabilities and task-defined vocabulary. Optional domain packs may supply examples or projections through a documented extension boundary, never via core keyword/preset branches.

### F-124 — High — Continuity messaging conflates persistence with productive execution

The guide says closing the window does not stop Watchers and quitting resumes from checkpoint (`WatcherViews.swift:69-72`), while the creation screen repeats this (`WatcherViews.swift:379-382`). It does not disclose that sleep stops work, a checkpoint may be structurally weak (F-098), process cleanup may be unproven (F-106), or a lock-screen power lease has thermal cost (F-108).

Required redesign: separate UI states for scheduled, process running, productive, sleeping, locked-but-running, app unavailable, recovering, cleanup pending, and paused. Time/accounting claims must be based on monotonic verified intervals.

## Architectural conclusion

LoopForge currently has reusable SwiftUI components but not a product design system. More importantly, it uses visual polish to collapse uncertain internal states into confident green outcomes. The redesign must make the interface a strict projection of typed receipts and bounded control state. Aesthetic quality and operational truth are the same architectural problem: neither can be left to local constants or free-form Agent prose.

Before production refactoring, the remaining Graph engine and test corpus must be fully read so the new tokens, state projections, authority model, and convergence telemetry are designed against the complete behavioral surface rather than patched into these views.
