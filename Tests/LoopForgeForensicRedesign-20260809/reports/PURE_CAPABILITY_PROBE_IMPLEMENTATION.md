# Pure Capability Probe and No Implicit Git Initialization

Status: **C-03 and D-08 source/package receipts present; production kernel cutover and current native proof pending**

## Defect confirmed

`GraphWorkspaceCoordinator.candidateCapability` was not a capability probe. For
an empty non-Git user directory it ran `git init` and created an empty commit
with a LoopForge identity. This durable mutation happened before a node,
transaction, lease, or integration receipt existed. It violated both the pure
probe requirement and the rule that parallel-isolation metadata must not be
manufactured inside the user's canonical workspace.

## Repair

Candidate capability discovery now delegates to the same read-only observation
path as ordinary workspace discovery. An empty directory is not interpreted as
authority to initialize a repository. Git observations run with both the
`--no-optional-locks` command option and `GIT_OPTIONAL_LOCKS=0`, preventing an
otherwise read-only status query from opportunistically refreshing the index.

The mutation-capable Git helper remains separate and is used only by explicit
preparation and integration paths.

For a non-Git parallel-candidate task, LoopForge now atomically creates a
task-owned snapshot repository under Application Support. The repository is
outside the canonical workspace, carries an explicit ownership bit in the
capability value, and is reused rather than silently recreated when a persisted
candidate graph resumes. Candidate worktrees branch from that owned baseline.
The selected result returns through the existing binary-safe, path-scoped patch
integration; non-Git canonical workspaces correctly skip the Git branch-alignment
optimization. Loser worktrees and the owned repository are explicitly removed
after selection or discard.

Copy, initialization, publication, or verification failure removes staging and
fails closed before graph creation or node launch. A persisted graph whose owned
repository disappeared is blocked rather than rebound to a new baseline.

## Adversarial verification

- probing an empty non-Git directory leaves its exact entry manifest empty and
  does not create `.git`;
- probing a nonempty non-Git directory leaves its entry manifest unchanged;
- probing a clean Git repository retains the exact `.git/index` bytes and full
  recursive path manifest;
- a clean committed repository remains eligible for existing worktree
  isolation;
- a non-Git workspace receives an application-owned repository outside its
  path, while its own manifest and bytes remain unchanged before candidate
  integration;
- a candidate changes text and binary content only inside its worktree; the
  selected binary-safe patch applies to the canonical non-Git workspace without
  creating `.git`, and the owned repository is removed;
- missing canonical input fails isolation creation and leaves neither a
  canonical mutation nor an owned staging repository;
- the complete source and packaging-owned suites preserve existing Graph,
  worktree, integration, recovery, and kernel behavior.

## Verification

- focused probe/isolation suite: **4 tests, 0 failures**;
- complete source suite: **589 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **589 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `a85be17828fae3463d23d314c4032f7d21387a0f7f4c0b41d3a55e7d00f3350e`
- focused log: `5daa3191b27e136776b75b3e795442bcce1ae733144f052eb679f19d9b75f734`
- full source log: `8a7a38249b7972e4891f6ab671dab2adc04913ef60b800380c33cad36ba8cebb`
- package test log: `0aa774ec7a0206464388572b8920f098134adc3d8138fc0fb3e865cce068551a`
- package command log: `1102c14f0e6f61f0b8818d1a49daeeea318bef0e067269df787612e66e76a3f3`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `60ee87086fbb99f601adcce248ab76a462ceb0edda6b3fce3f769cd33262608a`
- executable: `e91ea9d58f02017a7e1e2f2601f85eeed25cf0519e205e09903652f244953258`
- ZIP: `6b4b6dc96aef341d2547744169ee23c516831e2f6112d41e8badea465fccbd97`
- DMG: `86f4e90d98e11766122614d107edcf200d6c8da9b704b31be1912dbe8a765c56`
- CDHash: `a822489070f01bcd0d0274b8dd60caee6e4ac465`

## Boundary

This advances source-level C-03 and D-08 with package receipts, and the
isolation-creation failure path advances C-04. The application-owned repository
is still part of the legacy Graph controller rather than the journaled
production kernel, so production enrollment, durable lifecycle receipts,
current unlocked native proof, a clean commit, and push remain mandatory.
EasyBusiness remained permanently stopped and read-only.
