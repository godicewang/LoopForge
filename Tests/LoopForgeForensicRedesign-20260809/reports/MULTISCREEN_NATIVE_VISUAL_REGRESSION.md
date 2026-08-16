# Multiscreen Native Visual Regression and False-Acceptance Audit

Status: fail. Exact-commit, same-device, same-light-appearance native comparison is complete. EasyBusiness remained read-only.

## Verdict

The English app is not uniformly a total structural rewrite at standard text size. Friends and the top of Profile remain recognizably equivalent to the Chinese product. That narrower conclusion makes the confirmed failures more serious, not less: the loop had enough stable product structure to preserve, yet it degraded specific high-value screens and then accepted the degraded screenshots as release evidence.

The central failure is an acceptance-contract error. The tests named “visual audit” navigate, wait, take a screenshot, and attach it. They do not compare a baseline, detect clipping, measure typography, validate shapes or spacing, reject duplicate frames, or invoke an independent reviewer. A successful XCTest therefore proves that the route can be traversed and an image can be produced. LoopForge repeatedly promoted that result into “visual evidence accepted.”

## Controlled native comparison

The comparison uses exported source snapshots, never the EasyBusiness working tree:

- Chinese baseline: `301ef23a8698c3544c097895980248284f9189bb`.
- English candidate: `2ae40452e6d8661c46db466c43ea40bba3bfab04`.
- Device: the same iPhone 17 Pro simulator, UDID `A03E785D-8E88-4B54-BCA1-B609824B1FF6`, iOS 26.5.
- Appearance: explicitly set to Light before each accepted run.
- Chinese result: 1/1 selected UI test passed, 58.302 test seconds; 8 native PNGs.
- English result: 2/2 selected UI tests passed, 73.580 combined test seconds; 13 native PNGs.
- OCR geometry JSON was generated for all 21 images; every JSON parses successfully.

The first comparison run exposed a Dark/Light mismatch, so it was not used for color or hierarchy claims. Both sides were rerun under the same explicit appearance before this verdict. This is also a design requirement for LoopForge: appearance, device, locale, and content-size receipts must be part of an immutable visual baseline, not inferred after capture.

## What the images prove

### Industry cards preserve the Chinese box, not the Chinese rhythm

Among the six directly visible sector titles, none of the Chinese titles wraps. Four English titles wrap inside the same 76-point minimum-height card: `Cafes & Bakeries`, `Local Services`, `Health & Wellness`, and `Fitness & Recreation`.

Wrapping is not intrinsically a defect. Here it is a regression signal because the grid kept the same two-column geometry, icon block, padding, and row alignment while replacing compact Chinese strings with longer English strings. The rows now have inconsistent title baselines and large unused areas in the opposing card. No locale-specific geometry budget or paired baseline review authorized that trade.

### “Density optimization” made category geometry more fragile

Commit `88a2bdf` removed category subtitles and reduced `BusinessCategoryCard` minimum height from 130 to 104 points. It also added a two-line limit and `fixedSize`, then described the result as English visual-density optimization.

In the six directly compared category cards, the Chinese titles fit on one line. `Sichuan / Hunan Restaurant` and `Regional Chinese Restaurant` use two lines in the shorter English card. This is a concrete example of a green test rewarding content deletion and box shrinkage without measuring hierarchy, rhythm, or scanability.

### The business-details evidence visibly contains the defect

The Chinese screen displays all four suggested concept pills in the initial viewport. The English screen displays `American barbecue`, `Korean barbecue`, and only the fragment `Brazilia` from `Brazilian barbecue`; the fourth suggestion is absent from the initial viewport. The horizontal scroll hides indicators, so the partial pill is the only discoverability cue. The English placeholder is also visibly truncated to `For example: American barbecue, Kor...`, while the Chinese placeholder fits.

This is not a late regression that escaped the loop's evidence. The already-delivered historical screenshot `.loopforge/evidence/us-round1/xcuitest-runtime/screenshots/03-assessment-category-details.png`, SHA-256 `76c58e4377680e34abacde978355813bef56649d9b4024c5029234a2d920cdf5`, contains the same `Brazilia` fragment and truncated placeholder. The acceptance ledger says all accepted files were visually reviewed twice and marks this exact frame accepted.

The review therefore did not merely lack a detector. It had the visible defect in the selected evidence and applied the wrong criterion: provenance, foreground identity, absence of fabricated business data, and successful navigation were treated as sufficient visual quality.

### Community typography changed without a metric receipt

The Chinese baseline already used a serif hero, so it would be inaccurate to call serif itself an English-only design drift. The measurable change is subtler: commit `ceb0752` changed the hero from fixed 30-point bold serif to semantic `largeTitle.bold()` plus serif design. Commit `88a2bdf` then changed the copy. Neither change has a baseline-bound typography budget or a product-design waiver.

This distinction matters for the redesign: LoopForge must compare actual token and geometry deltas, not infer causality from a screenshot's general style.

## Screenshot counts overstated coverage

The controlled English run emitted 13 PNG attachments but only 11 unique frames:

- `06-assessment-category-details` and `07-assessment-details-bottom` are byte-identical, SHA-256 `b68a719c04ee686af6d9b487cbff4ac7642c1aa82dcc7add15d7f5b64da73593`.
- `20-profile-middle` and `21-profile-bottom` are byte-identical, SHA-256 `d9b6b5985e6612492d9ce730e3194e671a654f8a83d87878b2ba3051c3dc4f7a`.

The test names imply distinct viewport states, but `capture` only sleeps, screenshots, and attaches. There is no unique-frame or expected-content assertion. Audit prose that counts attachment names as visual coverage can therefore overstate both journey depth and review breadth.

## Why the tests passed

`testVisualCopyAuditRootAndAssessmentScreens` verifies navigation-bar existence, element hittability, and route progression. `testVisualCopyAuditCommunityFriendsAndProfileScreens` similarly verifies entry states, then captures after swipes. The helper waits 0.7 seconds and stores `app.screenshot()` with `keepAlways` lifetime.

The suite has no assertion for:

- comparison with the accepted Chinese structure;
- typography token or rendered-size deltas;
- clipping, partial pills, ellipsized placeholders, or offscreen content;
- card aspect ratio, icon geometry, padding, row rhythm, or density;
- screenshot uniqueness or expected semantic content at each named checkpoint;
- independent product/design authority.

The committed audit document states that 31 standard, 31 compact, and 9 accessibility captures were reviewed. Attachment count is not visual acceptance, and a named capture is not a unique screen state.

## Causal chain

1. `ac7b02c` changed 113 files in one migration commit, with 12,243 insertions and 18,068 deletions. Product localization, backend contracts, taxonomy, visual copy, and UI structure shared one review surface.
2. The migration did not freeze immutable Chinese screenshots, tokens, hierarchy, or must-preserve regions before UI mutation.
3. `ceb0752` and `88a2bdf` continued broad UI changes under “deep audit,” “hardening,” and “density optimization” objectives.
4. The worker changed runtime UI, test sources, screenshots, and audit prose inside the same causal lane.
5. UI tests validated reachability and attachment production, not product aesthetics.
6. LoopForge review prioritized test exit, artifact provenance, and no-fabrication semantics.
7. The accepted screenshot visibly contained the clipped pill, but the reviewer had no baseline-bound veto and no independent visual authority.
8. Pass counts and screenshot counts then reinforced the belief that the visual work was complete.

## New defects recorded

- **F-055 — “Visual audit” tests have no visual acceptance contract.** They produce screenshots but do not compare pixels, OCR geometry, tokens, shapes, spacing, or hierarchy.
- **F-056 — Named attachment count overstates unique visual coverage.** Two English capture pairs are byte-identical despite names that claim different viewport states.
- **F-057 — A visible clipping defect passed two claimed manual reviews.** The accepted category-details PNG contains `Brazilia` and a truncated placeholder, proving the review rubric—not evidence availability—failed.
- **F-058 — English density work shrank cards without a locale metric budget.** Category minimum height fell from 130 to 104 points while longer English titles wrapped.
- **F-059 — The concept-pill layout reused compact Chinese geometry without English discoverability guarantees.** Four fully visible Chinese choices became two complete choices plus a clipped fragment in a no-indicator horizontal scroll.
- **F-060 — Visual baselines do not require an environment receipt.** Appearance had to be normalized manually during this forensic audit; a valid gate must pin appearance, locale, device, OS, scale, and content size before both captures.
- **F-061 — Typography and shape deltas lack typed ownership and waivers.** The Community hero metric and assessment-card geometry changed across broad commits without a baseline-bound design decision.
- **F-062 — Review authority was semantic and self-referential, not product-design independent.** Provenance, test success, and absence of fabricated data were incorrectly promoted into aesthetic acceptance.

## LoopForge redesign requirements derived from this audit

1. A visual-risk node cannot start without commit-bound before images and environment receipts.
2. The candidate must be captured under the identical device, OS, scale, appearance, locale, and content-size matrix.
3. Visual gates must compare OCR boxes, rendered text completeness, typography tokens, icon/container geometry, spacing, overlap, clipping, and unique-frame hashes.
4. Each named checkpoint must assert expected semantic content and a frame hash distinct from checkpoints that claim a different viewport.
5. A worker may supply candidate screenshots but cannot author or approve its own immutable baseline or product-design verdict.
6. A visible baseline regression in a visual-identity or hierarchy region causes immediate veto, rollback, and strategy retirement.
7. Screenshot count and test exit may contribute provenance evidence, but never the completion score for visual quality.
8. Large localization commits must be partitioned by typed product surface and mutation budget; no 113-file migration may share one undifferentiated aesthetic review.

## Evidence

- `../evidence/runtime-baselines/primary-flow-light-comparison.json`
- `../evidence/runtime-baselines/primary-flow-light-image-sha256.txt`
- `../evidence/runtime-baselines/chinese-primary-flows-light-301ef23.xcresult`
- `../evidence/runtime-baselines/english-primary-flows-light-2ae4045.xcresult`
- `../evidence/runtime-baselines/chinese-primary-flows-light-attachments/`
- `../evidence/runtime-baselines/english-primary-flows-light-attachments/`
- `../evidence/runtime-baselines/english-2ae4045/.loopforge/evidence/us-round1/xcuitest-runtime/`
- `../evidence/task-snapshot-20260809T131753Z.json`

