# Chinese → English UI Causal Map

Status: first-pass code and evidence attribution. Native recreation of the Chinese build remains pending.

## Baselines

| State | Commit | Meaning |
| --- | --- | --- |
| Chinese before-state | `301ef23a8698c3544c097895980248284f9189bb` | Direct parent of the first U.S. commit; exact last Chinese product state |
| First U.S. rewrite | `ac7b02cbe08eedd331cad678f7f1c138a67367d0` | +3,760 / -5,099 across 46 client/test files |
| English density pass | `88a2bdf9c5af4ac0ef97a6814d894fe58b50ba0b` | +794 / -450 across 29 client/test files |
| Maximum-text “fix” | `f82ff2d604e10e00de7f88e1dc6a86c50d0cc0e1` | +868 / -63 across 14 files, including 272 new UI-test lines and 3 accepted screenshots |
| Current committed English state | `2ae40452e6d8661c46db466c43ea40bba3bfab04` | Current read-only comparison target |

Exact source copies for seven primary UI files are stored under `evidence/ui-code-baselines`; their hashes were captured at extraction.

## What changed on the home screen

The base card geometry was mostly inherited rather than redesigned: both Chinese and current English use the same 52×52 icon container, 26-point outer card radius, 15/14-point button radii, and roughly the same two-workspace layout. That distinction matters: not every ugly result is caused by a new shape constant.

The visible degradation comes from three interacting changes:

1. **English expansion without layout re-composition.** Compact Chinese titles and descriptions were replaced by longer English phrases inside substantially the same geometry. `经营助手` became `Operations Advisor`; the trust label and integrity notice also expanded. The result is extra wrapping, inconsistent card rhythm, and a denser, more generic dashboard.
2. **Copy optimization without a design baseline.** Commit `88a2bdf` shortened many sentences, but its acceptance was textual density—not preservation of the Chinese hierarchy, shape balance, or visual identity. It reduced words without solving composition.
3. **Accessibility repair optimized only for non-intersection.** Commit `f82ff2d` removed Dynamic Type caps and scale-down behavior from identity/trust elements, replaced one-line/scale behavior with `fixedSize`, removed fixed card heights at accessibility sizes, and added a top safe-area curtain. Those changes preserve every glyph and enable scrolling, but allow typography to dominate the entire screen.

## Why screenshots 10–12 were wrongly accepted

The retained acceptance ledger explicitly defines success as:

- three decodable PNGs from one passing test;
- correct dimensions and hashes;
- no intersection with the status bar;
- target content can be scrolled above the floating tab bar;
- actions exist and are hittable.

The UI test checks frames, existence, hittability, minimum touch size, and exact labels. It does **not** reject:

- headings occupying most of the viewport;
- icon-to-label or label-to-button disproportion;
- excessive line counts and vertical travel;
- a floating tab bar visually covering or competing with content;
- loss of scan hierarchy;
- cards becoming oversized text canvases;
- divergence from the accepted Chinese visual language.

The Graph audit document even states that completion must not use a Dynamic Type upper bound, truncation, hiding, or smaller text. That rule was treated as absolute, with no companion constraint on responsive re-composition. The agent therefore found a locally testable optimum: keep every glyph at full Accessibility 5 scale, make everything scroll, and prove rectangles do not intersect. The screenshots look bad because the acceptance contract rewards exactly that outcome.

## Self-reinforcing review chain

1. XCUITest emits green geometry assertions.
2. Evidence tooling proves PNG origin, dimensions, UUIDs, and hashes.
3. Node documentation restates those measurable facts as a complete product-quality contract.
4. Main Graph consumes the node’s tests, screenshots, and self-authored audit as independent-looking evidence.
5. WorkspaceAuditor counts successful commands, regression files, screenshots, and completion declarations.
6. The final task displays `100/100` even though the independent visual verdict is false.

The chain contains several artifacts but too few independent judgments. Provenance integrity is strong; product judgment is weak.

## Required LoopForge redesign consequences

- A localization/market-adaptation task must capture an immutable UI baseline before any node edits.
- Longer translated copy must trigger layout re-composition review, not merely string replacement or sentence shortening.
- Accessibility gates need two independent dimensions: semantic/accessibility correctness and responsive visual coherence.
- Visual approval cannot be supplied by the same node that wrote the UI and its tests.
- Screenshot validity, geometry safety, and aesthetic/product acceptance must be separate states.
- Every high-churn UI commit needs a mutation-budget escalation and explicit evidence that product identity is preserved.
- A `100/100` score must be impossible while any required visual, supervisor, integration, or active-node gate is false.
