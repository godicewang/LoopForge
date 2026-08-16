# Immutable Visual Baseline and Design Gate Implementation

Status: pure kernel verified side-by-side; legacy Graph execution and native capture harness are not cut over.

## Result

LoopForge now has a domain-neutral, fail-closed visual acceptance kernel derived from the stopped-run evidence. It replaces “a screenshot exists, decodes, and is non-blank” with an immutable baseline contract and twelve independent gates. A candidate is accepted only when every applicable deterministic dimension passes, every required native pair is present and comparable, every review batch is complete, known design debt moves only in its authorized direction, and a revision-bound independent review passes.

There is no weighted average. `unknown` vetoes. One pixel of new occlusion vetoes. A green accessibility result cannot waive broken composition, and eleven green dimensions cannot average away one typography failure.

## Immutable evidence boundary

`DesignBaselineBundle` binds the task contract, source tree, built artifact, capture protocol, semantic surface manifest, token snapshot, protected invariants, known debt, design authority, captures, and freeze time. The candidate mutation must begin after the authority-approved freeze.

Each native capture binds:

- semantic visual cell identity;
- source tree, built artifact, capture protocol, full image and accessibility-tree digests;
- exact viewport, scale, OS, orientation, locale, calendar, layout direction, appearance, contrast, reduced motion, bold text, content-size category, and fixture;
- navigation recipe, optional component/token traces, exact image dimensions, clean-install state, harness identity, process exit, and capture time.

The candidate cannot declare a smaller global-token capture matrix: `allBaselineCellIDs` must equal the contracted invariant surface. Missing, duplicate, stale, partial, differently configured, post-hoc, or non-zero-exit captures fail provenance.

## Twelve hard dimensions

The evaluator emits one typed result for each normative dimension:

1. provenance and comparability;
2. product identity continuity;
3. initial task hierarchy;
4. typography hierarchy;
5. symmetry and alignment;
6. spacing rhythm and density;
7. shape language and content fit;
8. collision, occlusion, and safe area;
9. responsive composition;
10. accessibility semantics and operation;
11. localization quality and slot fit;
12. independent product/design verdict.

Every result retains failed cells, evidence receipt IDs, and stable reason codes. The platform defaults preserve the ratified 10% typography and shape tolerances, 0.5-line-height alignment tolerance, one-point-or-10% spacing rule, 15% occupancy ceiling, and zero new occlusion pixels. Invalid or non-finite thresholds fail provenance instead of relaxing policy.

## Review completeness and independence

`VisualReviewBatchPlanner` sorts capture IDs and deterministically partitions every required image. Acceptance rejects incomplete batches, duplicate batch IDs, duplicate images across batches, silent image truncation, and any mismatch among selected, attached, inspected, and verdict-recorded sets.

The independent receipt is not a role label. It binds:

- baseline and candidate revisions;
- worker and reviewer lineage separation;
- provider, model, context, system prompt, user prompt, and evidence-bundle digests;
- exact baseline/candidate capture IDs and ordered full-resolution image digests;
- a per-image verdict and a per-pair verdict;
- exact deterministic evidence digest;
- exact batch receipts, inspected cells, blind-review mode, raw response, and final decision.

Changing a candidate image, a deterministic measurement, mutation scope, protected invariant, known debt, or amendment expires the review. The deterministic evidence digest canonicalizes unordered collections before SHA-256 so crash replay cannot invalidate an otherwise identical receipt merely because a set iterated differently.

## Design debt and amendment safety

Known debt is separate from protected identity. `notWorse` debt may stay flat or improve; `improveOnly` debt must strictly improve; closure-required debt must reach zero. Missing, negative, non-finite, excessive, flat-when-improvement-required, or worsening severity vetoes the debt's dimension. Large pixel difference remains advisory when a legitimate repair preserves every protected invariant.

An amendment must target the exact baseline and candidate, name affected dimensions, carry product-design authority and a non-empty reason. Invalid or worker-authored amendments fail provenance. This slice intentionally does not let a valid amendment silently waive a gate; replacement predicates and authority workflow remain part of cutover work.

## Adversarial verification

The focused suite executed 35 tests with zero failures. It covers the 24 normative cases plus stronger receipt and replay cases, including:

- post-mutation baseline freeze and trait/revision mismatch;
- missing capture, forged global matrix, incomplete/duplicate batches, and deterministic batching;
- absent primary task, typography inversion/ratio breach, asymmetric wrapping/alignment, spacing/density regression, undeclared token, shape overfill, one-pixel occlusion, responsive failure, accessibility failure, and localization overflow;
- design-debt improvement, forbidden flatness, and worsening;
- blind reviewer veto, same-lineage reviewer, missing per-image verdict, attachment reorder, image replacement, measurement replacement, and stale review digest;
- hard-AND aggregation and `unknown` veto;
- canonical digest stability across collection ordering;
- a historical numeric degradation specimen that independently trips typography, symmetry, density, and occlusion without putting application vocabulary in production policy.

After journal integration, the complete Swift suite executed 444 tests, skipped 6 environment-gated tests, and reported zero failures. `git diff --check` passed. Production-source vocabulary scanning found no EasyBusiness, market, screen, or device special case in the new gate.

Three intermediate test invocations failed because of test-fixture construction or deliberately strengthened receipt semantics. They are excluded from the strict active-work ledger. Every repaired path was rerun successfully.

## Exact artifacts

- `Sources/LoopForge/Kernel/DesignBaselineGate.swift`: 736 lines, SHA-256 `34cc44ce9401b383dc45d1fb7b2eae53f15cc85106d1c9e59240dfbd2531cb87`.
- `Tests/LoopForgeTests/DesignBaselineGateTests.swift`: 637 lines, SHA-256 `d93ac822caa3ac48279551a92bd8d5b54f63622c0ea817136b05bea188aa9009`.
- `Sources/LoopForge/Kernel/KernelIdentity.swift`: 102 lines, SHA-256 `0f52a8bdf21b557aee201dda40202dd2496ba766abb1223b7e832dbf2fd60794`.
- Focused log: `/tmp/loopforge-design-gate-tests-canonical.log`.
- Complete-suite log: `/tmp/loopforge-full-tests-design-gate.log`.

## Open boundary

This is not a claim that current Auto Graph is protected. The pure reducer/journal now records baseline and gate transactions, but legacy controllers do not create these receipts or call the kernel, and no trusted native capture adapter has been connected. Historical shadow replay, capture-harness adapters, transactional rollback/integration, receipt-native UI, packaging of the latest source, native verification, commit, and push remain mandatory before cutover.

EasyBusiness remained read-only throughout this implementation.
