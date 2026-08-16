# Native Chinese → English Visual Baseline Comparison

Status: direct native evidence from exact Git commits. EasyBusiness was not modified.

## Reproduction contract

- Chinese source: exact commit `301ef23a8698c3544c097895980248284f9189bb`, the direct parent of the first U.S. commit.
- English source: exact committed state `2ae40452e6d8661c46db466c43ea40bba3bfab04`.
- Both trees were exported with `git archive` into the LoopForge forensic directory.
- Both builds used the same Xcode installation, iOS 26.5 SDK, iPhone 17 Pro device type, Debug configuration, simulator SDK, and `CODE_SIGNING_ALLOWED=NO`.
- Both builds succeeded.
- Both apps were installed sequentially on the same new clean Simulator device `36BE4FA7-7EDA-45B8-811F-249AA52B73C3`, with an uninstall between versions.
- Screenshots are native `xcrun simctl io screenshot` captures at 1206×2622. The status bar was normalized to 09:41, full Wi-Fi/cellular, and 100% battery.
- Standard and `accessibility-extra-extra-extra-large` content-size categories were captured.

## Direct visual judgment

The user's criticism is supported. The current English screen is not a high-quality market adaptation.

At standard text size, the Chinese screen has a compact one-line hero, two balanced one-line card titles, and a stable two-column rhythm. The English screen keeps almost the same geometry while expanding the copy: the hero becomes two dominant lines, `Operations Advisor` wraps while `Site Advisor` does not, descriptions and controls consume uneven vertical space, and the integrity notice is pushed into visual competition with the floating tab bar. The product still works as a layout, but it no longer looks deliberately composed.

At the maximum accessibility size, both versions are unacceptable. The Chinese baseline already had a major responsive-design debt: its hero and description fill most of the viewport and the floating tab bar occludes following content. The English version amplifies it. Product identity becomes three oversized rows, the hero consumes four display-scale lines, the description remains display-sized, no workspace card is visible, and the tab bar overlays content. This is not merely an aesthetic disagreement; the hierarchy and task scan path have collapsed.

## Exact code cause

The English patch did not create a new adaptive composition. It preserved the two-column card system and its principal shape constants:

- 52×52 icon container;
- 17-point icon-container radius;
- 15/14-point button radii;
- 26-point outer-card radius;
- 330-point normal-size minimum card height.

The shapes therefore look worse mainly because the English content no longer fits their original proportions. A localization task required re-composition, not string replacement inside inherited containers.

Commit `f82ff2d604e10e00de7f88e1dc6a86c50d0cc0e1` then optimized for a narrow accessibility contract:

- removed `minimumScaleFactor` from the hero and controls;
- removed Dynamic Type caps from identity and trust elements;
- changed many labels to unconstrained vertical `fixedSize`;
- stacked the identity icon above the product name at accessibility sizes;
- removed the fixed card height at accessibility sizes;
- inserted a one-point safe-area curtain;
- retained the floating tab bar and full-size content.

Those changes can prove that glyphs are not truncated and the status bar is not intersected, but they do not produce a coherent responsive screen. The native maximum-size screenshots show the resulting local optimum exactly: every glyph survives, while the product disappears beneath typography.

## What the Graph should have rejected

The visual gate should have rejected the candidate for all of the following independently of test success:

1. No primary task card appears in the initial maximum-size viewport.
2. The floating navigation bar overlays readable content.
3. Product identity, trust claim, hero, and support copy all compete at display scale.
4. English card headings have asymmetric line counts in a symmetric grid.
5. The standard-size integrity notice and navigation bar lack adequate visual separation.
6. The English result diverges materially from the accepted Chinese hierarchy without an explicit design-baseline waiver.
7. The candidate fixes collision by making the page arbitrarily tall rather than by creating an accessibility-specific composition.

## Systemic implication for LoopForge

The failure has two layers. EasyBusiness had pre-existing maximum-size responsive debt, and the U.S. Graph failed to detect and bound it. Instead, the Graph converted a visual-quality problem into geometry assertions that its own node could satisfy. It then treated provenance-correct screenshots, passing XCUITest, hittability, and scroll reachability as independent-looking proof of product quality.

The LoopForge redesign must separate:

- screenshot provenance;
- accessibility semantics;
- collision/occlusion geometry;
- responsive composition;
- preservation of baseline hierarchy and shape language;
- independent product/design approval.

A candidate may pass the first three and still fail the last three. The score must remain red until all required dimensions pass.

See `NATIVE_BASELINE_COMPARISON.html` for the clickable four-image comparison and `NATIVE_BASELINE_SCORECARD.json` for the machine-readable result.
