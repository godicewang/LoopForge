# Systemic Root-Cause Synthesis

Status: evidence-backed synthesis after the complete 37,444-line active-code audit. Production refactor remains locked behind the 36,000-second forensic-analysis gate.

## Executive conclusion

The EasyBusiness failure was not caused by one weak prompt or one bad Agent. LoopForge currently has no authoritative boundary between a proposal, an authorized mutation, an independently verified result, and a product-approved outcome. Those concepts are represented by prose, mutable flags, filenames, generic command successes, and the judgments of the same configured Agent.

That missing boundary creates a self-reinforcing system:

1. task prose is classified by keywords;
2. keyword-derived categories and incident-specific prompts select tools and behaviors;
3. broadly privileged nodes mutate without a baseline-bound transaction;
4. the worker creates its own tests and evidence;
5. the same model family reviews that evidence;
6. a later green command or model-authored Boolean closes earlier gaps;
7. integration/push may happen before independent product approval;
8. mutable checkpoint flags become the next round’s “facts”;
9. activity time, iteration count, screenshot count, and test count create apparent progress;
10. retry thresholds change wording or node IDs without changing the causal strategy;
11. the UI reports completion and hides the dimensions needed to see non-convergence;
12. timers, polling, process leaks, full-store writes, and immediate reruns continue consuming resources.

This explains why the Graph could work for many hours, pass tests, accumulate screenshots, report 100/100, and make the product worse.

## Root causes

### RC-01 — No authoritative event-sourced state machine

Evidence: F-008, F-022–F-030, F-094–F-105, F-109, F-111, F-124, F-131, F-133, F-149–F-150.

Task, graph, node, iteration, review, integration, persistence, and presentation state are mutated across closures and snapshots. Invalid combinations—blocked and approved, completed without an integration receipt, needs-attention overwritten by active, strategy-retired but runnable—remain representable. Restart behavior is a set of migrations and precedence rules, not deterministic replay.

Required foundation: append-only typed events, a single pure reducer, explicit commands, state invariants, idempotency keys, and deterministic replay tests.

### RC-02 — User intent and product invariants are prose, not immutable contracts

Evidence: F-004, F-047–F-054, F-063–F-067, F-073, F-082–F-083, F-089–F-091, F-096, F-125–F-126, F-134, F-141, F-144, F-154–F-156.

The system does not create a durable typed objective, requirement set, design baseline, deliverable cardinality, forbidden substitution list, external-dependency boundary, or acceptance authority before execution. Keyword classifiers and historical examples therefore become the effective specification.

Required foundation: immutable `TaskContract`, requirement ownership, typed deliverables, baseline hashes, authority ceiling, and explicit owner-approved contract amendments.

### RC-03 — Authority is broad, inferred, and checked after mutation

Evidence: F-016, F-066, F-069, F-072, F-079, F-099, F-102, F-120, F-127–F-128, F-132, F-135, F-145–F-146.

Full Access is a default and a UI norm. Tool/resource needs can be inferred from words. Write scope is often a prompt followed by a post-hoc patch check. Isolation failure can fall back to the canonical workspace. Capability discovery may initialize Git. Reviewers can inherit mutating authority.

Required foundation: least-privilege capability leases, read-only pure probes, execution-enforced filesystem/process/network boundaries, fail-closed isolation, and separate review authority.

### RC-04 — Worker, verifier, reviewer, and reporter are not independent

Evidence: F-001–F-002, F-006, F-013, F-027–F-029, F-038–F-046, F-050, F-057, F-062, F-070–F-071, F-087–F-088, F-092–F-093, F-102–F-105, F-115, F-121, F-129–F-130, F-136–F-139, F-143.

The same configured Agent or model family can implement, create tests, choose screenshots, describe evidence, review, waive requirements, and write the final narrative. Raw review inputs and attachment order are not durably bound. A prose decoder can select an embedded JSON object. Generic strings are later presented as facts.

Required foundation: role-separated review identities, evidence/context isolation, strict structured transport, hash-bound review receipts, deterministic gates, adversarial vetoes, and reports generated only from accepted receipts.

### RC-05 — Visual quality has no immutable baseline or compositional acceptance model

Evidence: F-002, F-004, F-009, F-031–F-046, F-048, F-055–F-062, F-071, F-089–F-090, F-112–F-123, F-136, F-151–F-152.

Screenshot presence, file integrity, text survival, safe areas, and filenames are promoted into visual approval. Typography, shape vocabulary, spacing, hierarchy, density, locale expansion, initial-viewport usefulness, and baseline divergence are not separate gates. The LoopForge UI itself uses fragmented literal type/shape constants and visually certifies unproven state.

Required foundation: immutable visual-baseline manifests, pinned environment receipts, semantic screen requirements, native geometry and perceptual diffs, design-token invariants, accessibility composition gates, and an independent visual veto before integration/publication.

### RC-06 — Convergence is measured by counts and wording, not causal progress

Evidence: F-003, F-025–F-026, F-049, F-051–F-054, F-078–F-080, F-086, F-101, F-109, F-119, F-142, F-148.

Retries use fixed counts, blocker markers, normalized text, and node IDs. Relaunch can reset in-memory budgets. A renamed or paraphrased strategy can repeat the same environment, tool route, mutation class, and unavailable evidence request. There is no objective-distance vector, novelty receipt, evidence delta, damage budget, or expected-value test.

Required foundation: causal strategy fingerprints, progress vectors, persistent attempt budgets, risk-weighted mutation budgets, diminishing-return detection, typed abandon/reframe/split/replace decisions, and permanent retirement inheritance.

### RC-07 — Workspace integration is not a closed reversible transaction

Evidence: F-005, F-012, F-029, F-044, F-079, F-110, F-127–F-132, F-145–F-146.

Worktrees and scope checks offer partial protection, but preparation can downgrade, conflict recovery trusts exit zero, remote publication may precede final approval, capability state is sticky, and exact dirty content may be stashed/fast-forwarded without a durable owner baseline and rollback receipt.

Required foundation: immutable preimage, explicit mutation manifest, isolated candidate, mandatory verification receipts, independent approval, atomic apply, postimage verification, rollback proof, and remote publication as a separately authorized terminal transaction.

### RC-08 — Process, resource, persistence, and cadence lifecycles are not closed

Evidence: F-007, F-010–F-021, F-068, F-074, F-076–F-077, F-084, F-095, F-101, F-106–F-108, F-133, F-140–F-141, F-148–F-149.

PID ownership is lost after detachment; resources are modeled by proxies; cleanup can return before reaping; Ollama and bridge lifetimes are weak; broker polling, OCR/image scans, full-store writes, no-sleep assertions, and immediate Watcher reruns can sustain heat. Existing tests cover isolated components but not terminal quiescence.

Required foundation: task-wide resource ledger, durable provider identities, process-group/session ownership, synchronous cleanup barrier, event-driven brokers, adaptive persistence, a single cadence governor, thermal/load budgets, and a terminal quiescence receipt.

### RC-09 — Verification and evidence are not bound to revision, requirement, and environment

Evidence: F-011, F-013, F-028–F-029, F-038–F-046, F-053, F-055–F-060, F-087, F-090–F-098, F-103, F-115, F-124, F-138–F-140.

Files, generic command logs, scores, and Booleans lack a common identity tuple. A later unrelated green command can close a failure. A small checkpoint file can be “valid.” Selected screenshots can differ from attached screenshots. Reports cannot reconstruct exact evidence and reviewer inputs.

Required foundation: evidence graph keyed by task contract, requirement, source revision, workspace, environment, collector, artifact hash, reviewer, and supersession edge.

### RC-10 — Proxy metrics displaced product judgment

Evidence: F-001, F-006, F-008–F-011, F-031–F-037, F-045, F-052, F-080, F-086, F-093, F-103, F-111, F-118–F-119, F-124, F-139.

Duration, iterations, tests, screenshots, source-file counts, and audit scores are treated as achievement metrics. They do not answer whether the original product is better, unchanged where required, visually coherent, or safely integrated. Auto Graph even discards the user’s runtime target while advertising continuous work.

Required foundation: requirement closure and baseline preservation are terminal criteria; operational metrics remain diagnostics and may never substitute for acceptance.

### RC-11 — The tests characterize unsafe implementation details instead of adversarial acceptance

Evidence: F-024, F-055, F-081, F-134–F-156.

The suite has valuable unit checks but canonizes vertical phrases, Full Access, self-review, basic-integrity visual approval, permissive JSON, implicit Git initialization, prompt wording, immediate reruns, and static model catalogs. It has no deterministic full-engine replay or protected design baseline.

Required foundation: pure invariants, typed adapter contract kits, deterministic orchestration replay, transactional mutation tests, independent acceptance tests, and operational-budget tests.

### RC-12 — The product UI hides unsafe semantics instead of exposing them

Evidence: F-001, F-006, F-031–F-037, F-045, F-093, F-105, F-111–F-124.

The UI can show 100/100 beside missing visual proof, expose invisible execution-mode gestures, normalize Full Access, claim prompt correctness, advertise ignored runtime targets, and omit causal strategy/evidence/mutation information. Its own typography and shape system is fragmented.

Required foundation: UI generated from typed state, explicit privilege and mode controls, accepted/excluded/live time separation, strategy and mutation history, evidence provenance, honest uncertainty, and one coherent native design system.

## Causal dependency order for the redesign

The order matters. Fixing later layers first would recreate the current local patches.

1. **Event log + reducer + invariants** — nothing else can be made durable without this.
2. **Immutable task/product contracts** — defines what planning and acceptance mean.
3. **Authority/resource capability model** — constrains what execution may do.
4. **Transactional workspace/mutation model** — makes changes attributable and reversible.
5. **Evidence graph + independent review receipts** — separates claims from proof.
6. **Convergence governor** — reasons over durable strategies, progress, risk, and budgets.
7. **Lifecycle and thermal governor** — guarantees bounded operational behavior and quiescence.
8. **Visual/design acceptance subsystem** — enforces protected baselines before integration.
9. **Truthful reporting and native UI** — presents only states that lower layers prove.
10. **Adapter/test migration** — removes vertical residue and proves the new core across unrelated domains.

## Non-solutions

The following would not solve the failure:

- increasing model quality or reasoning effort;
- adding more prompt warnings;
- increasing the retry limit;
- changing the seventh-cycle threshold;
- adding more screenshots without baseline comparison;
- adding another same-model reviewer;
- counting more hours or tests;
- deleting only the EasyBusiness strings;
- polishing the current UI while keeping the same unproven state fields;
- killing individual PIDs without durable resource ownership;
- wrapping the current mutable engine in another supervisory loop.

The system must be rebuilt around typed authority, immutable contracts, replayable state, independent evidence, causal convergence, and closed lifecycle transactions.
