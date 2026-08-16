# Kernel Execution Composition

Status: **implemented as a fail-closed production composition boundary, full-regression verified, packaged, signed, and runtime-smoke verified; worker-provider cutover and native UI refresh pending**

Recorded: `2026-08-11T10:20:40Z`

## Forensic defect

The prior execution-admission correction made `startAttempt` and productive
process launch enforce causal reducer state, but it left two composition gaps:

1. native enrollment returned a registered `ready` run without a trusted path
   that assembled plan, optional immutable design baseline, convergence budget,
   node authorization, and causal attempt admission;
2. a process runtime could inspect an apparently valid executing projection but
   did not have to prove that its caller possessed the exact journal transaction
   that activated that attempt.

Those gaps did not resume the retired Graph, but they made any future executor
integration vulnerable to rebuilding a side channel around the reducer.

## Implemented boundary

- `KernelExecutionPreparationCoordinator.prepare` accepts only the exact
  ratified enrollment registration and its hash-journal evidence.
- Preparation is restricted to a pristine enrolled `ready` projection. It
  validates exact plan node, requirement ownership, causal strategy fingerprint,
  attempt identity, and optional baseline command pairing.
- Plan, optional design baseline, convergence initialization, node
  authorization, and causal admission are reducer-preflighted before any frame
  is appended. Command ID reuse is rejected before partial preparation.
- Sequence contexts advance from the reducer's actual next state rather than
  assuming that commands will always emit one event.
- Successful preparation remains inert: phase `ready`, no active attempt, no
  process, no agent, no timer, no runtime lease, and no external effect.
- Activation requires the unchanged exact prepared sequence and reducer
  projection. Only then may it journal `startAttempt` and produce a
  non-`Codable` `JournaledKernelExecutionProof`.
- `JournaledProcessRuntime` now requires that proof for both admission-and-launch
  and its lower-level launch entry. It resolves the proof's transaction back to
  the exact single `attemptStarted` event in the hash journal, then compares the
  event, current executing attempt, node, strategy, requirements, and productive
  lease request.
- A matching state snapshot, lease, or well-shaped unrelated transaction cannot
  authorize an OS process. Reconciliation remains available without productive
  launch authority.
- The enrollment runtime exposes the preparation coordinator but does not launch
  work by construction.

The batch guarantee is deliberately bounded: a reducer rejection or command-ID
conflict writes no preparation frame. A low-level filesystem failure may leave a
prefix of inert preparation frames; the pristine-state check then refuses
activation until recovery or explicit repair. No external effect occurs in the
preparation batch.

No EasyBusiness byte, task record, process, Git ref, or working-tree state was
changed.

## Adversarial verification

New tests prove that:

1. preparation remains inert until the exact activation request;
2. a rejected later preparation command leaves the enrolled journal unchanged;
3. reusing enrollment command authority leaves the run unchanged;
4. a productive process without a causal activation proof is rejected before
   journal admission, resource acquisition, or native launch;
5. a proof cross-wired to an unrelated valid journal transaction is also
   rejected before any effect.

Focused enrollment/composition and process-runtime suites passed **23 tests,
0 failures**. The complete development suite passed **625 tests, 8 environment
skips, 0 failures**. The package-owned suite independently passed the same **625
tests, 8 skips, 0 failures**.

## Package and integrity receipts

- release source snapshot: `b071542d3fd3ae5db3dcc9adacb212067334801813abd1ab5676b54eb5bf444a`
- development test log: `f82fbdda72076080c84d43f07a5cf55500c5295d1df864f2899faf62b3e8f627`
- package test log: `33e2abef9f136e85e6953f09b35e0bd57362baf9c62994ecf0b9e50653b3a38d`
- package log: `a85f015fceb99f059ea11d64f37186b4ae1b967b60a6ea4bc5010cb882930b86`
- build manifest: `075961408c035a0726f5a95031a168cd82f3fe688ccb7b183541a1ba1494203b`
- executable: `4de81db71c6f999cb0a8ed51b7558f628831c1a8ce36b9524f1f640170d9c00f`
- ZIP: `615518bf301d4e0cc9a250cbf12b65d160a6ab74534dcafae21b2023dc4754aa`
- DMG: `1b7026f5c460df9d873fc7f8fc840d183d262d7c2ed1f7ce0c01ce495bfd5b3e`
- checksum manifest: `131a6e746ca9a6ad11b427378eb8a835bddf8acd363a4cd334c1623696014c96`
- runtime smoke: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- CDHash: `f88c35d490a9470dd2d40b0602518a9fd801a1e9`
- residual exact packaged processes: `0`

## Remaining boundary

This implements safe preparation and activation capabilities; it does not yet
instantiate a production planner/worker provider or drive node work,
verification, visual adjudication, transactional integration, and completion
through the new kernel. The historical Auto Graph remains retired. Current
unlocked native UI screenshots, provider cutover, a clean commit-bound rebuild,
commit, and push remain pending. Final acceptance remains false.

