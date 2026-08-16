# Kernel Native Source-Revision Authority

Status: **exact bounded source revision displayed, freshness-checked, user-confirmed, journal-retained, and bound to the confirmed strategy and plan; native start remains absent**

Recorded: `2026-08-11T21:50:33Z`

## Authority result

The native Auto Graph contract now contains the complete bounded workspace
revision produced by `WorkspaceSourceRevisionCollector`. The artifact remains a
workspace observation rather than a user-authored fact. User authority arises
only when the confirmation sheet displays the exact revision, capture policy,
limits, workspace, scopes, objective, profiles, budgets, and complete candidate
digest and the native user confirms that candidate.

This closes the source-state prerequisite without allowing LoopForge, a model,
Git metadata, or timestamps to authorize a strategy or plan. Native authoring
now separately displays and explicit-user-binds the complete strategy,
mechanical falsifiers, and requirement-owned plan to this exact revision. The
read-only readiness gate reports zero missing-authority blockers. No start
control exists, and confirmation creates no attempt or worker.

## Implemented boundary

- `TaskContract` retains an optional `WorkspaceSourceRevisionArtifact`; old
  journals remain decodable, while newly authored native contracts require the
  artifact to validate and match the exact workspace identity and canonical
  root digest.
- The artifact retains its sorted excluded-directory names and exact file,
  aggregate-byte, and per-file limits. Validation recomputes the capture-policy
  digest, every entry constraint, aggregate bytes, and canonical revision.
- `TaskContractCompiler` requires one full-span `.workspaceObservation` source
  whose canonical bytes exactly equal the retained artifact. A missing binding,
  user/model authority substitution, malformed artifact, or changed bytes fail
  closed.
- Native authoring captures the selected canonical workspace once, displays the
  exact revision and policy, and seals the revision into the candidate digest.
- Confirmation re-captures the workspace under the displayed policy before it
  issues the single-use user receipt. Any content, path, mode, root, policy, or
  bounded-enumeration change after display rejects confirmation and creates no
  journal entry.
- Enrollment and durable reload retain the exact confirmed artifact. Repository
  evidence and enrollment now use the same canonical-root digest rather than
  two incompatible path-derived identities.

Git status, mtimes, inode numbers, enumeration order, and model prose still
mint no source authority. The scan is one-shot, no-follow, bounded, and has no
agent, network, process, or product-workspace mutation side effect.

## Adversarial finding repaired

The first integration compared the collector's canonical repository-root
identity with a separate raw-path hash in enrollment. A correctly captured
contract could therefore fail as `workspaceBindingMismatch`. Enrollment now
uses `WorkspaceRepositoryIndexer.canonicalRootDigest` as the single root
identity, and its regression fixtures use the same authority boundary.

A second fence prevents a displayed capture from becoming stale while the
confirmation sheet is open. The regression mutates a file after preparation
and proves confirmation returns `displayedSourceRevisionChanged`.

## Verification

- strategy/plan authoring, enrollment, and preparation suite: **27 passed, 0 failed**;
- displayed artifact, observed-source binding, tampering, wrong authority,
  durable replay, canonical-root identity, and post-display mutation cases:
  **passed**;
- complete source suite: **695 tests, 8 skipped, 0 failures**;
- non-DEBUG Release authority-audit build: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and
  `KernelProcessFixture` processes: **0**;
- read-only EasyBusiness status: **unchanged**.

Source identities:

- collector: `271375bda759598807dbf43c2b0e4adaacccb849b251f227c569e4069800ee14`;
- task contract: `53d451bd42dda4b24dae4efcc0d26b5293d306ff96f4527f044aba9e0b481f86`;
- compiler/confirmation: `f5efdaf1a66145be928b6d459201599b18ab66dead9288d57d9ec95054e3500f`;
- native authoring: `7c7e4188d132c16813b173e36a69355ad0be8b1a217e61d5b97649d3e5add51d`;
- enrollment: `ea6472485504b5109e058e98f62987b97501b9d9466de48fea7cee1197f63345`;
- AppModel: `662900025156fcef7aa6e480c2e491c0029cb6c9286ffd28f0d7a511eef30013`;
- native views: `d27d13cccac06002bfee557c51840b3fd94c2c65acd33f346877982ce4fe4559`.

## Remaining vetoes

The strategy and plan boundary is now closed; see
`KERNEL_NATIVE_STRATEGY_AND_PLAN_AUTHORITY_IMPLEMENTATION.md`. Native start
remains unavailable until deterministic dependency observation, verification,
independent review, design/visual evaluation, integration, final authorization,
and complete cleanup are composed. Legacy Single/Parallel retirement, current
packaging, unlocked native proof, commit, and push remain incomplete.
EasyBusiness stayed permanently stopped and read-only.
