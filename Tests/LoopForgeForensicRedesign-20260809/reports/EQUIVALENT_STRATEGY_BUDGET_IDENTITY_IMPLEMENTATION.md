# Equivalent-Strategy Budget Identity

Status: **F-01 kernel fingerprint and journal receipts present; production execution cutover pending**

Recorded: `2026-08-11T05:58:19Z`

## Defect confirmed

The new convergence kernel deliberately excluded node, thread, model, and
attempt IDs from `CausalStrategyDescriptor`, but its fingerprint still included
three non-causal proposal fields: expected-observation IDs, falsification
predicate IDs, and inherited-lesson digests. None is one of the declared nine
causal axes, and `changedAxes` correctly ignored them.

An Agent could therefore rename an observation or predicate, or attach another
lesson receipt, and receive a different strategy fingerprint without changing
hypothesis, action, topology, capability route, evidence source, measurement
boundary, oracle, mutation surface, baseline revision, or requirement
ownership. Equivalent attempts then consumed separate strategy slots.

## Repair

Strategy identity now contains only:

- the exact requirement-ID set;
- hypothesis class;
- action class;
- workspace topology;
- capability route;
- evidence sources;
- measurement boundary;
- verification oracles;
- mutation-surface digest; and
- baseline revision.

Prediction, falsification, and lesson metadata remain mandatory attempt and
replacement constraints, but are no longer allowed to mint identity or budget.
Their validation and receipt binding are unchanged.

## Adversarial verification

- a descriptor with renamed observation, renamed falsification predicate, and
  an added lesson remains structurally unequal but has the same fingerprint;
- while the first attempt is open, the renamed attempt is rejected as an
  equivalent active strategy and consumes no budget;
- after accepted progress closes the first attempt, journal replay admits the
  renamed attempt as another attempt of the same strategy;
- after a second replay, consumption is exactly two attempts and one strategy.

## Verification

- convergence suite: **16 tests, 0 failures**;
- journal suite: **15 tests, 0 failures**;
- complete source suite: **598 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **598 tests, 8 environment-gated skips, 0 failures**;
- release build, ad-hoc signature, exact source/test manifest, ZIP, DMG,
  checksums, executable startup, cleanup, and zero residual packaged processes
  verified.

Receipts:

- source snapshot: `f296d15a2513b0abb97885c62af2a32ad82e0fffcd00b857eab1a2420d8bac21`
- convergence source: `03058e1875526c6d5c2244ab47df2619796d0a2f3c72ff72f60d1c3a68e48f0a`
- convergence tests: `e11120427679b67a8c527f7b61ac06b67c397bd97263810de40e057946dec4d9`
- journal tests: `0e8ab6e57d85fe45bd400b8a6a55dc3c3af4ec2c3c469a9dfd5c19200ceb2b19`
- convergence log: `ae247b4fb5b14b4158803273b99a67c56f83b986bcf1d9e38297eef29115b3af`
- journal log: `4bffbdab4532bb5712c05ded4d58e3e5d283b671b96a165a71080c4e9f887582`
- package test log: `e149c31cd8f67390eafc82ee48676652072d773114930d4c2bfe7bd5c83af5ed`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `205c3d0c49383fb32b1b4ade482359b31cee31dd4abd98f8a0d1fd8c21d6409d`
- executable: `373d06b855d4d8dc93b0898a1dac571ff944dd52734488f1b3b4c931eb3dffd7`
- ZIP: `664cc425d9232230350129d2dd00ad1a7e06d1fb1d28fa965657ef675aee9575`
- DMG: `fdc05d5159ceb9f34d68364d9e375383854c73efe7af50133322a651e64dec37`
- CDHash: `12ff77a4fefdf3cb74257c1d7a915b1a8c035245`

## Boundary

This closes the kernel-level metadata-renaming escape and its crash/replay
path. Full F-01 acceptance still requires production task enrollment and
controller execution to use the journaled kernel rather than the legacy Graph
budget. Current unlocked native proof, a clean commit, and push also remain.

EasyBusiness remained permanently stopped and read-only.
