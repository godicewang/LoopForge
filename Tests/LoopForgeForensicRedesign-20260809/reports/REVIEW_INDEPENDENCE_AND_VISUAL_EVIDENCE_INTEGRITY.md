# Review Independence and Visual-Evidence Integrity

Status: confirmed systemic defect. EasyBusiness remained read-only while this finding was reconstructed from the stopped task snapshot, retained evidence manifests, and the current LoopForge source.

## Finding

The Graph calls its Main decisions “independent”, but independence is not an enforced property of the decision. The stopped task used GPT-5.6-Sol/Ultra/Full Access for both the Main Graph Agent and every node worker. Control calls are fresh ephemeral Codex processes, so there is no hidden conversational memory between them; however, LoopForge records no reviewer identity, provider diversity, adversarial role, blinded evidence set, disagreement, or second verdict. Planning, node review, join review, strategy retirement, final review, and format repair all prefer `task.resolvedControlAgent`. This gives process separation, not epistemic independence, and leaves correlated model preferences and framing errors unchallenged.

The final Graph contract is also materially weaker than the ordinary Loop supervisor contract. `GraphFinalReviewEnvelope` contains only approval, a prose summary, one next instruction, a visual boolean, and proposed nodes. It has no requirement IDs, per-requirement judgments, evidence citations, confidence, contradiction list, reviewer identity, inspected-image manifest, or baseline comparison. The ordinary `LocalSupervisor` has a requirement-coverage map and calls `enforcingCoverageForApproval`; Graph final review bypasses that enforcement completely.

## The final reviewer did not receive the evidence it was told to audit

`WorkspaceEvidenceCollector` constructs an up-to-80,000-character evidence body containing worker feedback, workspace delta, source excerpts, command-ledger output, screenshot paths, OCR, and coverage. The Graph final prompt does not include `evidence.text`. It includes only:

- node status/review summaries;
- a generic deterministic score and findings;
- workspace file counts;
- generic coverage labels and paths;
- image dimensions/luminance text.

Thus the prompt tells Main to compare the integrated workspace, tests, failure paths, and screenshots while withholding the actual bounded source excerpts and command ledger that would support those claims. Node reviews receive the fuller evidence body, but final approval is supposed to detect integration-level defects that no isolated node can prove.

Every Graph collector call used for candidate, node, join, transition, and final review passes `before: [:]`. That disables changed-file and changed-image provenance. When `before` is empty, every retained image in any matching evidence/screenshot path is a candidate; selection is by semantic filename bucket and modification time, not by node, commit, capture run, acceptance status, or current UI tree.

## Historical evidence contamination is directly proven

The stopped task retained 12 paths in `visualEvidencePaths`. Two were explicitly rejected historical pre-fix frames:

- `08-maximum-dynamic-type-home.png` — the current canonical `behavior-coverage-matrix.md` says Workspace content is behind the floating tab bar and labels it “Historical before evidence; not current acceptance”.
- `09-maximum-dynamic-type-actions.png` — the same matrix says Advisor is painted through the status-bar frame and labels it “Historical before evidence; not current acceptance”.

They nevertheless occupied positions 12 and 5 in the final candidate array. The collector has no acceptance/rejection parser, so the presence of an explicit rejection ledger cannot exclude a frame.

There is a second mismatch: the collector selects up to 12 screenshots, but Codex control attaches only the first four (`imagePaths.prefix(4)`), while a local model attaches at most six. In the stopped final audit the first four were screenshots 12, 11, map guidance 02, and storefront failure 01. The current Home initial safe-area frame 10 and eight other listed candidates were not visually attached to the Codex reviewer. LoopForge still persisted all 12 as `visualEvidencePaths` and the deterministic summary said all 12 had been “inspected”; that inspection only checked dimensions, luminance variance, and OCR, not layout quality.

Basic visual integrity passes whenever at least one image is at least 400×300 and has luminance variance at least 0.004. It does not measure typography scale, baseline alignment, icon/shape geometry, spacing rhythm, clipping, safe-area collision, density, hierarchy, brand fidelity, or difference from the Chinese product baseline. A broken but nonblank screen therefore satisfies the deterministic visual integrity gate.

## Why this produced aesthetic regression

1. The same model family proposes, implements, and judges the design language, so a shared preference for explanatory copy, oversized cards, rounded geometry, or test-friendly layout is never challenged by a genuinely independent design authority.
2. The final decision sees summaries of earlier model judgments rather than a pinned baseline and complete current evidence. This creates self-reinforcing review: each summary becomes the next review's premise.
3. Old screenshots remain in the pool indefinitely and are selected for semantic diversity even when a repository ledger declares them rejected.
4. Only a provider-dependent prefix is visually attached. “12 screenshot candidates” can mean “four images actually seen”.
5. No immutable baseline binds typography, icon geometry, spacing, hierarchy, density, or information architecture. Passing reachability and accessibility tests can therefore reward a visually destructive rewrite.
6. A single boolean compresses visual quality. There is no per-screen, per-state, per-baseline, or per-design-token verdict and no uncertainty budget.
7. Reusable approval is keyed to stored booleans and a non-empty `mainLastReview`, not to a cryptographic evidence-set identity. The review text can also be overwritten by later incremental review, weakening the meaning of “durable whole-graph approval”.

## Required redesign contract

1. Pin an immutable product/design baseline before mutation: exact commit/tree, native screenshots, locale, device, content-size category, appearance, viewport, test data, design tokens, and hashes.
2. Give every screenshot a signed manifest: task, node, iteration, commit/tree, capture command/run ID, state ID, locale, viewport, accessibility settings, timestamp, hash, and lifecycle state (`candidate`, `accepted`, `rejected`, `superseded`, `baseline`). Never infer acceptance from filename or mtime.
3. Attach exactly the images named in the review manifest. If a provider cannot inspect them all, split the review into deterministic batches and require one verdict per image before aggregation. UI must display “12 selected / 4 actually inspected” rather than claiming all were seen.
4. Replace the final boolean with typed per-requirement and per-screen judgments, citations, confidence, contradiction status, baseline-diff metrics, and explicit inspected evidence IDs. Deterministically refuse approval when any mandatory item is missing, partial, contradicted, stale, or uninspected.
5. Include commit-bound source excerpts and command receipts in final review, not only node prose. Final review must independently reproduce high-risk integration checks in a read-only verified worktree.
6. Enforce reviewer independence as a policy: fresh session plus adversarial prompt, blinded worker conclusion, separate reviewer identity, and for visual/product changes either a different model/provider or two independent verdicts with a deterministic disagreement escalation.
7. Add native visual gates for typography, safe areas, icon/shape geometry, spacing, density, hierarchy, Dynamic Type, and baseline perceptual change. Thresholds must be screen- and region-specific; pixel similarity alone is not sufficient.
8. Bind approval reuse to a content-addressed review receipt containing original requirement registry hash, integrated tree hash, test receipt hashes, screenshot manifest hashes, reviewer identities, policy version, and verdicts. Any change invalidates it.
9. Preserve rejected evidence for audit but never place it in an acceptance bundle unless the review explicitly requests a before/after pair and labels both roles.
10. Add regression tests for rejected-but-newer screenshots, stale copied mtimes, more images than a provider limit, identical filenames from different commits, partial visual attachment, old approval reuse after incremental review, and a nonblank but catastrophically clipped UI.

This finding explains how LoopForge could retain abundant screenshots and multiple reviews while still driving EasyBusiness toward a visibly worse interface. The failure was not “the model failed to notice one ugly screen”; the review system did not establish what evidence was current, what the reviewer actually saw, what baseline must remain invariant, or who was allowed to declare convergence.

