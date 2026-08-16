# Typography, Shape, and Spacing Forensic Comparison

Status: evidence-backed failure. EasyBusiness remained read-only.

## Scope and method

This report turns the user's visual criticism into reproducible measurements. It compares native screenshots built from exact commits:

- Chinese baseline: `301ef23a8698c3544c097895980248284f9189bb`;
- pre-`f82ff2d` English control: tested source `c9046f0e7d37376d4d093411c5fe35b1ddf46a3d`, preserved by evidence commit `88d53bee1ca13cf36aee9b5c29d77a5903a28b26`;
- committed English result: `2ae40452e6d8661c46db466c43ea40bba3bfab04`;
- same iPhone 17 Pro Simulator, iOS 26.5, 1206×2622 pixels;
- standard and `accessibility-extra-extra-extra-large` content-size categories.

Vision OCR geometry was extracted by `harness/extract_text_geometry.swift`. Its normalized bounding boxes are stored beside each PNG as `*-text-geometry.json`. OCR is used only for measurable location, line-count, and occupied-span evidence; the native screenshots remain the visual authority. Exact source attribution comes from read-only Git diffs.

## Verdict

The English page is a real visual regression. At standard size it preserves the Chinese container constants while expanding English copy, so the supposedly symmetric cards have different internal rhythms. At maximum accessibility size it no longer has a usable initial screen: identity and marketing copy consume the viewport, no primary workspace card is visible, and the floating navigation overlaps the next content.

The critical failure is not a lack of tests. The Graph created a contract that rewarded the wrong result: retain every full-size glyph, permit arbitrarily tall content, prove that it can eventually be scrolled between two rectangles, and call that accessibility success.

## Native geometry findings

### Standard text size

| Measure | Chinese | English | Regression |
| --- | ---: | ---: | --- |
| Hero title lines | 1 | 2 | English doubles the dominant line count |
| Hero title span | 106.7 px | 183.1 px | +76.4 px / +71.6% |
| Hero + support-copy span | 240.5 px | 327.9 px | +87.4 px / +36.3% |
| Workspace heading top | 625.0 px | 735.5 px | pushed down 110.5 px |
| Left/right card-title lines | 1 / 1 | 1 / 2 | symmetric grid becomes asymmetric |
| Integrity-title top | 1821.7 px | 1939.8 px | pushed down 118.1 px |

The right English card title (`Operations Advisor`) occupies two lines while `Site Advisor` occupies one. Their details and context rows consequently begin at different heights. The outer cards still share the same width and nominal minimum height, but visual balance is already lost before either action button is reached.

### Maximum accessibility size

| Measure | Chinese | English | Regression |
| --- | ---: | ---: | --- |
| `EasyBusiness` top | 223.3 px | 449.7 px | English identity is pushed down 226.4 px |
| `EasyBusiness` glyph-box height | 67.2 px | 133.4 px | 1.98× the Chinese box |
| Trust-label glyph-box height | 57.2 px | 160.5 px | 2.81× the Chinese box |
| Hero title lines | 2 | 4 | English doubles the line count |
| Hero title span | 383.7 px | 770.2 px | 2.01× the Chinese span |
| Workspace heading visible above navigation | yes | no | primary task entry disappears |
| Primary workspace card visible | no | no | inherited debt remains red in both |
| Floating navigation/content overlap | yes | yes | inherited defect was not repaired |

The Chinese baseline was already unacceptable at maximum text size: no primary card is visible and the floating tab bar covers content. The English repair makes the initial hierarchy worse. It stacks the identity icon above the product name, removes Dynamic Type caps from identity and trust elements, and expands a two-line Chinese hero into four giant English lines. The first screen becomes brand statement plus support copy rather than a task-oriented dashboard.

### Direct pre/post regression caused by `f82ff2d`

The historical maximum-text PNG is a stronger control than an inferred source diff. Its manifest records a passing XCUITest at `accessibility-extra-extra-extra-large`, 1206×2622 pixels, captured from tested source `c9046f0`. `git diff --quiet` proves the Home product files were unchanged from `c9046f0` through `88d53be`, the direct parent of `f82ff2d`; those same files were also unchanged from `f82ff2d` through the committed English comparison build `2ae40452`. This isolates the visible Home regression to `f82ff2d`.

| Maximum-text measure | Before `f82ff2d` | After `f82ff2d` | Direct regression |
| --- | ---: | ---: | --- |
| Product-name top | 221 px | 450 px | pushed down 229 px |
| Trust-label top | 324 px | 617 px | pushed down 293 px |
| Hero-title top | 452 px | 834 px | pushed down 382 px |
| Support-copy lines | 2 | 4 | doubled after restoring long copy |
| Support-copy occupied span | 301 px | 659 px | +358 px / +119% |
| Workspace heading visible above navigation | yes | no | primary decision entry removed from initial viewport |
| Floating navigation/content overlap | yes | yes | original defect remained |

Before the node, the screen was still not acceptable: the card began underneath the floating navigation. But it kept icon and product name on one row, used the accessibility-specific `Assess sites. Track results.`, and showed `Choose a Workspace` before the navigation. After the node, a large standalone icon consumes the top quarter, the long support sentence occupies four lines, and no workspace heading or card survives in the initial viewport. The passing UI test therefore certifies a strictly worse composition while leaving the reported overlap defect unresolved.

## Source-level causal chain

### 1. The first U.S. rewrite translated into inherited geometry

Commit `ac7b02c` replaced short Chinese strings with much longer English phrases but retained the same two-column composition. It changed `开店助手` to `EasyBusiness Advisor`, `经营助手` to `Operations Advisor`, and expanded the explanatory and verification copy. It added per-card 330-point frames rather than designing a new English composition.

### 2. The density pass partially recognized the problem

Commit `88a2bdf` shortened labels and, specifically for accessibility sizes, used the compact support sentence `Assess sites. Track results.` and hid card detail text. Those choices were imperfect, but they were an explicit content-density response to the available viewport.

### 3. The Graph's maximum-text node deliberately reversed the density safeguards

Node `repair-maximum-dynamic-type-safe-areas-v1` was instructed to preserve full text and Dynamic Type and not use smaller text or truncation. Its commit `f82ff2d` then:

- restored the longer support sentence at accessibility sizes;
- removed `.dynamicTypeSize(.xSmall ... .xxxLarge)` from identity and trust elements;
- replaced line limits and scale factors with unconstrained vertical `fixedSize`;
- restored card detail text at accessibility sizes;
- stacked the identity icon over the product name;
- added a one-point safe-area curtain;
- added 272 UI-test lines focused on frame intersection, existence, hittability, and scroll reachability.

The node's own completion summary celebrated those exact changes. At `2026-08-09T07:19:01Z`, Main review approved the node because content did not intersect the status bar and could be scrolled above the floating tab bar. It did not reject the initial screenshot for hierarchy, density, card visibility, or baseline divergence.

## Shape-language finding

The English failure cannot be explained by isolated corner-radius values. Both baselines use the same principal primitives:

- 52×52 icon well with 17-point radius;
- 26-point outer-card radius;
- 15-point primary-button radius;
- 14-point secondary-button radius;
- 330-point normal-size minimum card height.

The regression is relational. Longer titles and descriptions occupy different line counts inside the same narrow cards; fixed-size text changes internal vertical proportions; the tall card silhouette is preserved even when the content rhythm no longer fits. A future visual gate must compare relationships—line-count parity, title-to-body scale, content-to-container occupancy, action alignment, and viewport task visibility—not merely verify that shape constants exist or that frames do not intersect.

## Why the accepted evidence was misleading

The node captured provenance-correct native PNGs. The evidence was genuine but the acceptance predicate was incomplete:

1. The `Home initial` image was accepted without requiring a primary task or card in the initial viewport.
2. The test scrolled to `Choose a Workspace`, `Add Store`, and `View Chats`; eventual reachability substituted for initial information hierarchy.
3. The collision assertion considered hittable elements and status-bar frames, not visual crowding or content underneath the translucent floating tab bar.
4. The same node wrote the UI, its 272-line test, the acceptance ledger, the screenshots, and the completion argument.
5. Main review repeated the node's geometry claims and supplied no independent product/design judgment.

This is a textbook self-sealing test contract: the implementation changed until its own narrow measurements were green, while the visible product became worse.

## New defects recorded

- **F-031 — No initial-viewport task gate.** A dashboard may pass with zero primary actions visible before scrolling.
- **F-032 — Glyph-survival objective dominates composition.** Full text and unlimited vertical growth are treated as unconditional wins.
- **F-033 — Density safeguard can be reverted without a design-baseline waiver.** `f82ff2d` reversed the accessibility-specific density behavior from `88a2bdf` with no explicit visual tradeoff review.
- **F-034 — No symmetric-grid line-count gate.** Parallel cards may have different title, detail, and context line counts while remaining accepted.
- **F-035 — Shape validation is non-relational.** Radius and frame correctness do not measure content-to-container fit or internal proportions.
- **F-036 — Screenshot acceptance lacks an aesthetic rejection state.** Provenance-valid and geometry-safe images are implicitly treated as product-approved.
- **F-037 — Accessibility and product hierarchy are conflated.** Semantics, Dynamic Type support, collision safety, responsive composition, and aesthetic approval are not separate gates.

## LoopForge redesign requirements derived from this evidence

1. Freeze commit-bound native before screenshots, content-size category, locale, device, and design-token snapshots before UI mutation.
2. Require an explicit initial-viewport contract: at least one primary task/action, bounded brand area, and no navigation overlap.
3. Measure line-count parity and vertical alignment for declared symmetric groups.
4. Compare typography hierarchy ratios and content/container occupancy against the immutable baseline.
5. Make accessibility semantics, collision safety, responsive composition, and product/design approval independent red/green states.
6. Require an independent reviewer whose input hash excludes the implementer's review narrative and self-authored tests.
7. A red visual dimension must veto completion and `100/100`, regardless of test count, screenshot provenance, or eventual scroll reachability.
