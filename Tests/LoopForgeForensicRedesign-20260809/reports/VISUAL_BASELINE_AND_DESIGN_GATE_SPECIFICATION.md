# Visual Baseline and Design Gate Specification

Status: pre-implementation normative design. EasyBusiness remains read-only. Production refactoring remains forbidden before the 36,000-second forensic gate.

## Executive conclusion

The EasyBusiness regression is not subjective noise. Same-device native captures from exact Chinese and English commits show measurable hierarchy, typography, symmetry, and viewport regressions. Yet the accepted Graph node optimized a narrower contract—retain every glyph, avoid specific frame intersections, and prove eventual scroll reachability—and its own tests made that local objective green.

LoopForge needs a visual gate that distinguishes:

- immutable product/design baseline identity;
- known baseline debt that may be repaired but not preserved as a defect;
- deterministic geometry/accessibility checks;
- relational typography, shape, density, and hierarchy checks;
- provenance-complete native capture;
- independent product/design review;
- explicit baseline amendment authority.

Passing build, UI automation, screenshot existence, pixel decodability, non-blank luminance, or scroll reachability never implies design approval.

## Forensic validation example

The domain-neutral gate below is derived from, but not specialized for, EasyBusiness. The measured example demonstrates why each dimension exists:

| Same-device measure | Chinese baseline | English candidate | Consequence |
|---|---:|---:|---|
| standard hero lines | 1 | 2 | dominant copy consumes a second hierarchy row |
| standard hero span | 106.7 px | 183.1 px | +71.6% occupied height |
| standard workspace-heading top | 625.0 px | 735.5 px | primary decision content shifts down 110.5 px |
| symmetric card-title lines | 1 / 1 | 1 / 2 | left/right internal rhythm diverges |
| maximum-size hero lines | 2 | 4 | candidate doubles dominant line count |
| maximum-size hero span | 383.7 px | 770.2 px | candidate consumes 2.01× baseline height |
| primary workspace heading above navigation at maximum size | yes | no | initial task entry disappears |
| persistent navigation/content overlap | yes | yes | inherited baseline debt remains unresolved |

The Chinese maximum-size baseline was already red. Therefore “pixel similarity to baseline” would be wrong: the candidate is allowed to repair the overlap, but it may not worsen hierarchy and hide the primary task. The gate needs protected invariants plus a known-debt ledger.

## Immutable `DesignBaselineBundle`

Before any UI-affecting mutation, a trusted capture harness creates:

```swift
struct DesignBaselineBundle: Codable, Sendable {
    let contractID: ContractID
    let sourceTree: Digest
    let builtArtifact: Digest
    let captureProtocol: Digest
    let designTokenSnapshot: Digest
    let semanticSurfaceManifest: Digest
    let captures: [NativeCaptureReceipt]
    let protectedInvariants: [DesignInvariant]
    let knownDebt: [DesignDebt]
    let baselineAuthority: AuthorityReceipt
}
```

Every `NativeCaptureReceipt` includes:

- semantic surface/state ID, not a filename guess;
- source tree, app binary, build, and launch-recipe hashes;
- device class, exact viewport pixels/points, scale, OS/runtime, orientation;
- locale, calendar, layout direction, appearance, contrast, motion, bold-text, and content-size category;
- clean-install/data-fixture identity and navigation steps;
- full-viewport PNG hash and dimensions;
- native accessibility-tree/frame artifact hash;
- optional component-boundary and design-token trace hashes;
- capture time, harness identity/version, and process exit state.

The bundle is stored outside the target repository under content-addressed LoopForge artifacts. An executor cannot replace, crop, rename, or recapture the baseline after seeing its candidate.

## Baseline debt is explicit

A `DesignDebt` records:

- dimension and surface/state/trait scope;
- baseline evidence hash;
- severity and user impact;
- permitted direction of change;
- whether the current task is required to close it;
- maximum tolerated interim severity;
- amendment authority.

Rules:

1. A candidate must not worsen any known debt.
2. If the task touches the causal component/token, the contract decides whether debt closure is mandatory.
3. Repairing debt may diverge greatly in pixels while still preserving protected identity and hierarchy.
4. A debt item cannot be created after candidate capture merely to excuse a regression.
5. An Agent may propose debt classification; only baseline authority accepts it.

## Semantic design-token snapshot

The gate snapshots relationships, not only literal constants:

| Token family | Recorded semantics |
|---|---|
| typography | role, font family/design, weight, base size, Dynamic Type scaling behavior, line height, tracking, line limits, minimum scale, hierarchy rank |
| spacing | semantic token name, value, parent/child relationship, safe-area behavior, grid/gap rhythm |
| shape | component role, corner-radius/size ratio, stroke width, capsule/circle/rounded-rectangle family, clipping behavior |
| color/material | semantic foreground/background/accent role, contrast, opacity, material, appearance variants |
| control | role, minimum target, padding, label/icon alignment, enabled/disabled/focus states |
| layout | container, ordering, alignment group, responsive breakpoint/variant, fixed/flexible dimensions |
| navigation | persistent/transient role, occupied inset, safe-area reservation, overlap behavior |

Literal token changes are not automatically bad. A candidate fails when it introduces an undeclared token, breaks a semantic relationship, causes cross-surface inconsistency, or changes a protected role without a baseline amendment.

## Capture matrix

The immutable task contract declares applicable surfaces, states, and traits. The planner can propose a risk-minimized matrix, but deterministic policy requires at least:

1. every changed primary surface at standard content size;
2. every changed primary surface at the maximum supported accessibility size;
3. every affected width/layout class and orientation breakpoint;
4. each supported appearance whose tokens changed;
5. each supported locale whose string expansion or layout direction is affected;
6. loading, empty, populated, error, disabled, keyboard/focus, and permission states when the mutation can affect them;
7. baseline and candidate captured with the identical protocol and fixture.

Pairwise/risk selection may reduce combinatorial explosion, but it emits an explicit omitted-state receipt and may never omit a state directly affected by changed code/tokens.

## Visual gate dimensions

Each applicable dimension produces `pass`, `fail`, or `notApplicable` with evidence. `unknown` is a blocking result.

### VG-01 — Provenance and comparability

Baseline/candidate must match capture protocol, device/viewport, OS, locale, traits, fixture, semantic surface/state, and full-viewport bounds unless an accepted compatibility transform exists. Missing or silently truncated images fail.

### VG-02 — Product identity continuity

Protected navigation structure, information architecture, component roles, visual identity tokens, and task flow remain recognizable. Pixel similarity is advisory; semantic role deletion/reordering requires amendment.

### VG-03 — Initial task hierarchy

At standard sizes, every declared primary surface keeps at least one primary task/action in the initial viewport when the baseline did. At accessibility sizes, the primary task heading/action must appear within the initial viewport or the first bounded scroll quantum declared by the platform contract; persistent navigation may not hide it.

### VG-04 — Typography hierarchy

- semantic roles cannot invert hierarchy rank;
- candidate role-size/line-height ratios remain within 10% of protected baseline ratios unless recomposition is approved;
- body/support text cannot become display-scale merely because Dynamic Type is large;
- line truncation, scaling, and wrapping are evaluated by role and content, not prohibited globally;
- localized copy expansion beyond the slot budget requires an explicit responsive composition variant.

### VG-05 — Symmetry and alignment groups

For a declared symmetric group, corresponding title/body/context/action anchors stay within 0.5 of the relevant line height unless the candidate intentionally switches to an asymmetric layout variant. Title line-count difference is zero for strict peers; otherwise the layout must reserve equivalent semantic rows.

### VG-06 — Spacing rhythm and density

Protected semantic gaps remain within one platform point or 10% (whichever is larger). Content-to-container occupancy may not increase more than 15% without an accepted density/recomposition rationale. Empty space and crowding are evaluated across the full component, not by isolated frame intersections.

### VG-07 — Shape language

Component shape family and radius/size ratios remain within 10% for protected peers. New radii/strokes must map to an existing or explicitly added semantic token. Text expansion that makes a shape proportionally awkward is a failure even if the numeric radius is unchanged.

### VG-08 — Collision, occlusion, and safe area

No newly visible overlap, clipping, underlap, offscreen interactive target, or safe-area violation is allowed. Persistent overlays must reserve or dynamically account for their occupied region. One-pixel curtains and eventual scrolling do not repair covered content.

### VG-09 — Responsive composition

The candidate must use a composition suitable for each trait, not merely allow unlimited vertical growth. The gate checks ordering, grouping, task prominence, navigation behavior, content density, and action reachability at every required breakpoint.

### VG-10 — Accessibility semantics and operation

Labels, traits, focus order, target sizes, contrast, reduced-motion behavior, keyboard/switch control where applicable, and Dynamic Type are tested independently. Accessibility success cannot waive visual hierarchy or responsive composition; visual approval cannot waive semantic accessibility.

### VG-11 — Localization quality and slot fit

Copy is reviewed for native tone, precision, verbosity, domain fit, and redundant explanation. Deterministic checks report expansion, line count, orphaned words, duplicated labels, and inconsistent terminology. A concise slot-specific rewrite is permitted when it preserves meaning; literal translation is not privileged.

### VG-12 — Independent product/design verdict

A read-only reviewer evaluates every required baseline/candidate pair and deterministic dimension. The first pass is blind to worker completion prose and self-authored tests. Its receipt binds the exact images, tree, semantic manifest, deterministic results, provider/model/run identity, and structured rationale.

## Threshold and amendment policy

The numeric tolerances above are default risk controls, not universal aesthetic law. A task contract may define stronger platform/product thresholds. Relaxing a protected threshold requires `DesignBaselineAmendment` containing:

- affected invariant/dimension and exact baseline/candidate evidence;
- user/product-design authority;
- reason and tradeoff;
- replacement acceptance predicate;
- surfaces/traits that must be recaptured;
- expiry or permanent-version semantics.

The executor, its tests, or the reviewing model cannot self-authorize the amendment. If no baseline authority is available, the system preserves the baseline and pauses on material ambiguity.

## Native geometry evidence

Use three independent evidence channels:

1. **accessibility/layout trace:** semantic IDs, roles, frames, hittability, focus order, safe areas, scroll containers, and overlay bounds;
2. **image analysis:** full-viewport pixel artifacts, OCR boxes, line grouping, luminance/contrast, alignment, occupancy, salience, and perceptual diff;
3. **source/token trace:** exact revision, changed components, styles/tokens, localization slots, responsive branches, and fixture/navigation recipe.

OCR and image heuristics propose measurements; they do not invent semantic state IDs or approve design. Native semantic traces establish geometry identity, and independent review resolves aesthetic/compositional judgment.

## Screenshot completeness and batching

- The evidence bundle lists `required`, `captured`, `decoded`, `selected`, `attached`, `inspected`, and `verdictRecorded` counts separately.
- Provider image limits cause deterministic batches, never `prefix(4)` truncation.
- Every image has a per-image verdict and every baseline/candidate pair has a pair verdict.
- Aggregation fails if a required image/pair lacks inspection.
- Contact sheets are navigation aids only; full-resolution originals remain the evidence.
- The worker cannot choose the only images shown to the reviewer.

## Visual mutation budget

Every UI node declares:

- component/surface/token mutation scope;
- expected affected capture set;
- maximum new semantic tokens;
- maximum hierarchy/order changes;
- copy slots and expansion budget;
- baseline-debt items addressed;
- rollback candidate identity.

Changing a global typography, shape, spacing, color, or navigation token expands the affected surface set automatically. If the recapture/review budget cannot cover that set, the mutation is rejected or split before execution.

## Acceptance logic

```text
visualAccepted =
  every applicable deterministic dimension == pass
  AND every required capture/pair inspected
  AND no protected invariant changed without amendment
  AND no known debt worsened
  AND independent product/design verdict == pass
  AND receipt revision == candidate revision
```

There is no weighted average. One red applicable dimension vetoes integration, remote publication, completion, and a green overall score. The UI displays the exact red dimension and evidence, never `100/100` beside a required failure.

## Required deterministic and native tests

1. baseline recapture attempt after candidate creation is rejected;
2. mismatched device/locale/trait pair is incomparable;
3. provider limit batches all images and records all verdicts;
4. missing full-viewport image blocks aggregation;
5. primary action pushed below initial standard viewport fails;
6. persistent navigation occludes content by one pixel and fails;
7. symmetric peer title wraps while the other does not;
8. typography hierarchy inversion fails despite no overlap;
9. unchanged radius with overfilled content fails shape fit;
10. new undeclared spacing/radius token fails consistency;
11. literal localized copy exceeds slot budget and triggers recomposition;
12. accessibility semantics pass while composition fails; aggregate stays red;
13. visual composition passes while focus order fails; aggregate stays red;
14. known baseline debt improves with large pixel diff and passes protected invariants;
15. known baseline debt worsens and cannot be excused post hoc;
16. worker-authored screenshot selection omits a required state and fails;
17. blind reviewer veto differs from worker narrative; veto is preserved;
18. global token mutation expands the required capture matrix;
19. stale candidate revision invalidates all prior visual receipts;
20. baseline amendment without product/design authority is rejected;
21. standard and maximum Dynamic Type native smoke run uses exact artifact hashes;
22. report shows exact selected/attached/inspected counts and source sequence;
23. two equivalent UI tasks with different vocabulary use identical gate policy;
24. no product, industry, screen-name, or customer vocabulary exists in production visual-policy code.

## Implementation boundary after the forensic gate

1. Add generic design-baseline, capture, dimension, debt, amendment, and verdict types.
2. Make native capture a trusted adapter with exact artifact and environment receipts.
3. Introduce source/token/semantic manifests and provider-limit batching.
4. Implement deterministic geometry dimensions against synthetic fixtures first.
5. Add blind independent review as a separate read-only process role.
6. Shadow-evaluate existing visual tasks without changing integration behavior.
7. Enforce veto before candidate integration and any remote publication.
8. Replace category/filename/image-count heuristics and aggregate visual scores.
9. Verify LoopForge's own native UI through the same generic protocol before package release.

The resulting gate protects design intent without freezing inherited defects or encoding EasyBusiness-specific rules into LoopForge.

