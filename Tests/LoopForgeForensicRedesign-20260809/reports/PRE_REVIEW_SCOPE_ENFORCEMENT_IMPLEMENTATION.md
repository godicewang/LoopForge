# Pre-review Isolated Scope Enforcement

Status: **C-05 source/controller and package receipts present; production executor cutover and current native proof pending**

## Defect confirmed

Both the ordinary Graph node path and the parallel-candidate path sent a
successful worker result to `reviewNode` before `GraphWorkspaceCoordinator`
checked the isolated repository delta against the node's declared write
scopes. The later integration boundary could reject an undeclared path, but by
then the Main Graph model had already read and potentially endorsed those
bytes as evidence. A worker could therefore manufacture its own review input
outside the authority it was given.

This was a sequencing defect, not a prompt-quality defect. Model self-review
cannot turn an unauthorized effect into valid evidence.

## Repair

`GraphWorkspaceCoordinator.validateDeclaredChanges` now performs a read-only
observation of the complete isolated delta before any model review:

- tracked, staged, and unstaged names are obtained from a diff against the
  exact integration base;
- untracked names are obtained separately;
- both commands use `--no-optional-locks` and NUL-delimited output;
- changed paths are de-duplicated and checked through the same declared-scope
  policy used by integration;
- a missing worktree, missing base, command failure, or path violation fails
  closed.

The ordinary and parallel completion handlers invoke that gate before
`reviewNode`. A violation records a deterministic recovery decision, blocks
the node, disables automatic retry, requires strategy escalation, detaches the
worker thread, and leaves the isolated bytes quarantined. It does not invoke
the model reviewer and does not integrate any canonical path. Other ordinary
Graph branches may remain schedulable; a parallel candidate is excluded from
selection.

## Adversarial verification

- an allowed new file plus an out-of-scope binary file is rejected;
- the out-of-scope filename contains a literal newline, proving the change
  list is NUL-safe rather than line-split;
- the canonical repository never receives the rejected path;
- tracked and untracked changes wholly under an allowed subtree produce the
  exact complete sorted delta;
- deleting the isolated workspace makes the gate unavailable and therefore
  fail closed;
- the complete source and packaging-owned suites preserve existing Graph,
  worktree, integration, recovery, and kernel behavior.

## Verification

- focused scope suite: **2 tests, 0 failures**;
- complete source suite: **591 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **591 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `baa8ea05dfe8de6a8aef94f5b91175ee82777c5d4da6ce32fc421d5e82af427f`
- focused log: `d49ef9383fe1a83a7e35b0b024c6864ca5f7e1c43bb244dba44389ac73cd6c4f`
- full source log: `3c28930212ebd39e80781cc6d05ceb1fe5ca05e0b995fc1ba1c16f074a343119`
- package test log: `a2a09ab292cac48df93e301a475a3e0b98ce9b9899a44ad85b314a467c4ca2c7`
- package command log: `038785af8ecf1afe72204d8734353d6a88f7bbde8723ed1c0056d55197058e2f`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `101af272cde5ad7d375030130f94efa2f43be4787bd5318e847bfd25d108b31d`
- executable: `25b3468a75a4fc774496c966853607fc107e7620a874b52805b77685d376b0e7`
- ZIP: `f8b64abcd61810f1bf2a70b951b81208fb688bd90f135e98b75f21707c83779e`
- DMG: `d2215b51536b9a1bc347eb9205e4744a3449f81e9064e0483b2fefceb70df187`
- CDHash: `3656fb17ff7d373facf993983056d10d3cb51cbd`

## Boundary

This advances the isolated-result half of C-05 at the legacy Graph controller
boundary: unauthorized candidate bytes are rejected before evidence review or
integration. It is not yet an operating-system write denial and is not
journaled production-executor enforcement. Production-kernel enrollment,
trusted executor authority, current unlocked native proof, a clean commit, and
push remain mandatory. EasyBusiness remained permanently stopped and
read-only.
