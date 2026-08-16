# Kernel Workspace Source-Revision Collector

Status: **bounded content-complete revision evidence implemented; native user binding is now integrated while execution authority remains absent**

Recorded: `2026-08-11T21:14:30Z`

## Authority finding

The two remaining native start blockers cannot be filled honestly from an
objective string, Git revision, directory timestamp, or model claim. A causal
strategy and requirement-owned plan first need an exact source state that the
user can inspect and bind. This collector provides that evidence prerequisite.
The subsequent native-authority integration now retains, displays, rechecks,
user-confirms, and journals the artifact, but still creates no strategy, plan,
attempt, or start action.

## Implemented boundary

`WorkspaceSourceRevisionCollector` emits a Codable artifact containing:

- the opaque workspace identity and canonical-root digest;
- the digest of an explicit excluded-directory-name policy;
- every included regular file's sorted relative path, permission mode, exact
  byte length, and SHA-256 content digest;
- the total observed bytes; and
- a canonical SHA-256 revision over all of those fields.

The revision intentionally excludes Git metadata, mtimes, inode numbers, and
enumeration order. Timestamp-only changes therefore do not create false source
novelty, while path, content, permission, workspace identity, root, or capture
policy changes do.

Capture is bounded by positive file, per-file byte, and aggregate-byte
ceilings. The canonical root is held by an open no-follow directory descriptor;
every parent and final file is opened descriptor-relatively with
`O_NOFOLLOW`; only regular files are accepted; and device, inode, mode, size,
mtime, and observed byte count must remain stable across hashing. Enumeration
errors, traversal, symlinks, special files, overflow, and concurrent file
change fail closed.

An adversarial review found that the first implementation checked excluded
directory names before symlinks. A symlink with an excluded name could
therefore have been silently skipped. Symlink rejection now precedes exclusion,
and the regression uses an excluded `.build` symlink to prove the fail-closed
ordering.

## Verification

- collector-focused suite: **3 passed, 0 failed**;
- content, mode, path, root, workspace, policy, timestamp, ordinary symlink,
  excluded-name symlink, file-size, and file-count cases: **passed**;
- complete source suite after native-authority integration: **693 tests, 8 skipped, 0 failures**;
- non-DEBUG Release authority-audit build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and
  `KernelProcessFixture` processes: **0**;
- read-only EasyBusiness status: **unchanged**.

Source identities:

- collector: `271375bda759598807dbf43c2b0e4adaacccb849b251f227c569e4069800ee14`;
- tests: `7fb545cb64ee0f88ef60a9edc504ac10651155136cf6b5344b75cfc17e4a05d0`.

## Remaining vetoes

The native workflow now captures this artifact for the ratified workspace,
shows its exact policy and revision to the user, re-captures before confirmation,
seals a single-use user receipt over the whole candidate, and retains the
artifact in the hash journal. Both `causalStrategyAuthorityMissing` and
`executionPlanAuthorityMissing` nevertheless remain unchanged because source
state is not strategy or plan authority. Strategy/falsification authoring,
plan ownership, native start,
dependency observation, verification, independent review, visual evaluation,
integration, final authorization, complete cleanup, legacy Single/Parallel
retirement, current packaging, unlocked native proof, commit, and push remain
vetoed. EasyBusiness remained permanently stopped and read-only.
