# Review Provenance and Visual Veto Architecture

Status: root-cause audit complete for the current implementation; redesign not yet implemented.

## Executive finding

LoopForge calls its node and final reviews independent, but the durable record cannot prove what the reviewer actually inspected. A completed node retains a prose `lastReview`; the Graph does not persist the control prompt, evidence-bundle hash, exact attached-image manifest, reviewer provider/model, raw structured response, workspace tree hash, or requirement-contract version.

This is not just an observability weakness. It lets self-authored evidence become a self-sealing acceptance contract. The maximum-text node wrote the UI change, 272 lines of XCUITest, the acceptance ledger, the screenshots, and the completion narrative. A fresh Main context then evaluated that package against the node's own narrow objective and approved it. The product-level visual veto occurred only later—after the worker had already pushed the bad commit to `origin/main`.

## Exact stopped-task evidence

The stopped task used GPT-5.6-Sol with Ultra reasoning and Full Access for both `controlAgent` and `subAgent`. Same-model use was requested and is not itself proof of invalidity, but it increases the need for strong contextual independence and immutable review receipts.

For `repair-maximum-dynamic-type-safe-areas-v1`:

- worker interval: `2026-08-09T06:29:07Z`–`07:17:23Z`;
- worker result: `f82ff2d`, pushed directly to `origin/main`;
- node result declared `LOOPFORGE_STATUS: COMPLETE`;
- Main approval at `2026-08-09T07:19:01Z` repeated the geometry claims;
- durable node state contains one approved iteration and a prose `lastReview`;
- it contains no review-input hash, attachment list, reviewer identity, prompt, raw response, or tree-bound receipt.

The task later reached `auditScore: 100` while `visualAuditPassed: false` and `supervisorCompletionApproved: false`. That later rejection correctly prevented whole-task completion, but it did not undo the already-pushed node commit. The user therefore received a visibly degraded app even though the final Graph had not approved delivery.

## Source-level failure modes

### 1. The durable review record is a string

`GraphLoopNode.lastReview`, `GraphNodeIterationRecord.mainReview`, and `GraphLoopState.mainLastReview` are plain strings. `GraphSchedulingPolicy.isAuditedAndIntegrated` requires only:

- `status == .completed`;
- non-null `completedAt`;
- non-empty `lastReview`.

It does not bind approval to a commit, tree, diff, requirement registry, command receipt, screenshot hashes, or reviewer input.

### 2. Image selection and image inspection are different quantities

`WorkspaceEvidenceCollector` may select 12 images. The Codex control runner silently uses `imagePaths.prefix(4)`. The selected manifest is not returned in the review envelope or stored on the node. Consequently:

- UI and reports can count 12 retained screenshots;
- the reviewer can inspect at most four;
- no durable record says which four;
- no replay can prove whether the decisive screenshot was attached.

For candidate selection, `chooseBestCandidate` explicitly truncates to four before routing. For node and final review the router receives the larger array, but the Codex path truncates inside `codexControlResponse`; the call site is unaware of the loss.

### 3. The image integrity check is not a design review

`inspectScreenshots` passes when at least one image is at least 400×300 and at least one has luminance variance ≥0.004. OCR is sampled, but no typography, hierarchy, spacing, shape, occlusion, baseline, or initial-task metric affects `passedBasicIntegrity`.

The summary says only how many screenshots were decodable and non-blank. The final LLM receives that summary and up to four images; there is no deterministic red dimension for the failures visible in the EasyBusiness screenshot.

### 4. Requirement coverage is a filename inventory

Coverage states are `candidate`, `notObserved`, and `notApplicable`. A candidate is found mainly by filename terms and the existence of any successful harness output. The collector explicitly says candidate evidence is not proof, but the final prompt receives only `coverageText` and the basic visual summary—not the collector's full source excerpts, command evidence, OCR sample, or worker-disclosed evidence body.

The stopped snapshot illustrates the contradiction:

- `auditScore: 100`;
- `Accessibility or layout-pressure visual state: not observed in attached evidence`;
- `visualAuditPassed: false`.

The numeric score is therefore not a semantic completion score.

### 5. The 100-point audit measures repository affordances

The deterministic score awards:

- 20 for any substantive source deliverable;
- 15 for documentation;
- 10 for an entry point/manifest;
- 15 for tests;
- 20 for any successful verification;
- 10 for no unresolved recent failure;
- 10 for the exact completion marker.

Those total 100 without measuring the actual market-adaptation requirements. Visual evidence and approval are hard gates, but they do not change the displayed score. This explains the misleading `100/100` beside a red visual verdict.

### 6. Final review omits the richest evidence body

Node review includes `evidence.text`. Whole-graph review includes:

- node prose summaries;
- generic audit score/findings;
- workspace counts;
- filename-oriented `coverageText`;
- the basic visual-integrity summary.

It omits the full code excerpts, command ledger, OCR sample, worker evidence body, and explicit screenshot manifest. The most consequential approval is therefore less grounded than the node review.

### 7. Product veto occurs after unsafe side effects

Workers were allowed to push `HEAD:main` from isolated nodes. Node review then approved and integrated the result. A later final visual failure could pause Graph completion but could not make the remote mutation disappear. This violates the expected meaning of an isolated, supervised node: supervision happens after publication rather than before it.

## New defects recorded

- **F-038 — No durable review receipt.** Approval is a prose string, not a hash-bound event.
- **F-039 — Silent selected/attached image mismatch.** Up to 12 images are selected while Codex receives at most four.
- **F-040 — Basic image integrity is mislabeled as visual inspection.** Decodability and variance can pass a visibly broken screen.
- **F-041 — Requirement coverage is path-oriented, not contract-oriented.** Candidate filenames do not prove outcomes.
- **F-042 — Whole-graph review receives less evidence than node review.** `evidence.text` is omitted at the final decision.
- **F-043 — Reviewer independence is contextual but unproven.** Provider/model, prompt, raw response, and evidence hashes are not retained.
- **F-044 — Final veto is temporally too late.** A node can publish to the canonical remote before product-level approval.
- **F-045 — Displayed score and semantic readiness diverge.** `100/100` can coexist with a red required visual dimension.
- **F-046 — Review replay is impossible.** Current state cannot reconstruct the exact reviewer input and attachment order.

## Required redesign

### Immutable evidence bundle

Every review needs a durable `EvidenceBundleReceipt` containing:

- verbatim-goal hash and requirement-contract version/hash;
- baseline commit/tree hash and candidate commit/tree hash;
- changed-path manifest and bounded source-excerpt hashes;
- typed command receipts with command, cwd, start/end, exit, output hash, and lifecycle status;
- screenshot manifest with SHA-256, dimensions, locale, device, content-size category, lifecycle state (`candidate`, `accepted`, `rejected`, `superseded`), and baseline pairing;
- selected image count and actually attached image count;
- deterministic visual dimension results;
- collector version and bundle hash.

### Durable review receipt

Every node, join-group, and final review needs a `ReviewReceipt` containing:

- evidence-bundle hash;
- reviewer role and independence mode;
- provider, model, reasoning, and control-run identifier;
- system/user prompt hashes;
- exact attached-image hashes and batch indices;
- raw structured response hash plus decoded verdict;
- candidate tree hash that the verdict authorizes;
- created time and receipt version.

`isAuditedAndIntegrated` must verify the receipt and current tree hash, not a non-empty summary.

### Visual review must be multi-dimensional and veto-capable

Required dimensions for a UI adaptation should include at least:

- provenance;
- baseline identity preservation;
- initial-viewport primary-task visibility;
- typography hierarchy;
- symmetric-group line-count/alignment;
- content/container occupancy;
- spacing rhythm;
- shape-language fit;
- navigation/content occlusion;
- accessibility semantics;
- responsive composition;
- independent product/design verdict.

Every applicable dimension must pass. A red dimension must force the displayed score below completion and block canonical integration/publication.

### Batch every image instead of silently dropping it

When a provider supports four images, LoopForge must create deterministic review batches, persist one per-image verdict, and aggregate only after every required image is inspected. The UI must display `12 selected / 12 inspected`, never conflate repository count with reviewed count, and never silently truncate.

### Blind-then-reconcile review

The first adversarial pass should inspect baseline/candidate images, diffs, and objective receipts without the worker's completion narrative or self-authored acceptance prose. A second pass may reconcile worker claims with the blind findings. This preserves the user's same-model configuration while preventing the worker's framing from defining the review rubric.

### Publish only after approval

Workers may commit only inside their isolated workspace. LoopForge must integrate into a protected candidate ref, run node and product gates there, and update the user branch/remote only after a tree-bound final receipt passes. Rejection must leave canonical and remote refs untouched.

