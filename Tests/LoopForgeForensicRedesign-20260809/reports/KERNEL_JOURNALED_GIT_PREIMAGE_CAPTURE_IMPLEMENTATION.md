# Journaled Git preimage capture

Recorded 2026-08-12T10:02:57Z. Final acceptance remains false.

## Implemented boundary

`WorkspaceJournaledGitPreimageCaptureIssuer` now observes the exact ratified
workspace through a bounded read-only Git executable and emits one atomic
non-Codable capability for HEAD, index, and untracked planes. HEAD and index
content is rehashed from exact Git blobs; untracked content is matched to the
descriptor-stable, content-complete source revision. Ignored-but-untracked
files are included because ignored classification is not silently substituted
for untracked membership.

Before issuance, the issuer verifies the production enrollment, recovery
registration, hash-journal transaction, reducer-owned contract, workspace/root
identity, and complete ratified source revision. It repeats the canonical Git
root, Git-directory identity, HEAD commit, complete NUL-delimited tree/index/
untracked listings, every referenced blob, and the complete workspace revision.
Unborn HEAD, conflicted index stages, symlinks or submodules, unsupported modes,
noncanonical paths, duplicate paths, bounds overflow, command failure, timeout,
and any repository/workspace drift reject the whole capture.

Each plane is an explicit canonical artifact, including an observed empty
plane. Absence is never interpreted as empty. The durable receipt binds the
run, contract, ratification, enrollment frame, actor/time, workspace/root,
source revision, capture policy, Git executable, Git-directory identity, HEAD
commit, no-excludes untracked-observation policy, all three artifact digests,
and one repository-observation digest.

`RunJournal` accepts only the live capability and persists only the inert
receipt. The pure reducer performs no Git or filesystem I/O; recovery reproduces
the three accepted artifacts. Exact duplicate replay returns the retained
receipt, while same-command rebinding and decoded artifact substitution reject
without journal advance. This receipt issues no repository-metadata verdict,
ignored-path classification, `WorkspacePreimage`, manifest, preflight, or effect
authority.

## Adversarial verification

Real temporary Git repositories prove distinct committed HEAD bytes, staged
index bytes, ordinary untracked bytes, ignored-but-untracked bytes, explicit
three-plane emptiness, journal replay, exact idempotency, command conflict,
tamper rejection without journal advance, complete four-plane coverage when
combined with the confirmed worktree artifact, and atomic rejection of a
conflicted index.

The current split gate passed 747 tests with 8 intentional environment skips
and zero failures, plus the independently run process-group resistance case:
748 covered tests and zero failures.

Fresh Release and source bindings:

- LoopForge: `527a2425030159b526ac332bc1e1f8ed25f182a5e21fc51af47b39f7db27a4cf`
- KernelSandboxGate: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`
- exact source snapshot before final report reconciliation: `431b28851a31524d63a09950350a8489234b1e6f9878ab4a71927f8094577b43`

All builds, tests, waits, failed diagnostics, and report generation are excluded
from the strict ledger. EasyBusiness remained read-only and its fingerprint was
unchanged.

## Still blocked

Repository-metadata and ignored-path-policy authority; canonical
`WorkspacePreimage`; manifest assembly; proposal/preflight issuance;
resident-memory authority; publication; native design/visual authority; final
authorization; native start/UI; package/sign; clean commit; and push remain
blocked.
