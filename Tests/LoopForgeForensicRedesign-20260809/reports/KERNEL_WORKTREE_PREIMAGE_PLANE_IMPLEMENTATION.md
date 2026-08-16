# Kernel worktree-preimage plane implementation

Recorded at: `2026-08-12T05:51:20Z`

## Outcome

LoopForge can now project the initial worktree plane from the exact content-complete `WorkspaceSourceRevisionArtifact` bound by user-confirmed contract authority. The plane artifact retains the workspace/root/source/policy identities, every sorted regular-file path, mode, byte size, content SHA-256, initial ownership, deduplicated content-size references, and a canonical artifact digest.

The projection is intentionally one plane only. A source revision proves the included worktree bytes but contains no Git HEAD tree, index-stage data, or untracked classification. `WorkspacePreimagePlaneCoverageAssessment` therefore accepts exactly the provided validated planes and returns `.head`, `.index`, and `.untracked` as missing when only the source-revision worktree projection exists. Empty planes are never inferred from absence.

## Authority boundary

`WorkspacePreimagePlaneArtifact` is inert, Codable evidence. It cannot construct `WorkspacePreimage`, issue a mutation manifest, satisfy the preflight plane-completeness check, or authorize filesystem effects. Production still needs separately journal-owned HEAD/index/untracked observations with exact identity and replay semantics, plus repository-metadata and ignored-path-policy authority.

The projection labels initial entries `userExisting` because its only accepted provenance is the exact source revision confirmed before task mutation. Later accepted task mutations require a distinct journal-generation projection and are not silently relabeled by this component.

## Fail-closed controls

- invalid or tampered source revisions reject;
- plane artifacts bind exact SHA-256 workspace-root, source-revision, and capture-policy identities;
- entries must be unique, path-sorted, regular-file worktree snapshots with exact modes/digests;
- content references must uniquely and exactly cover entry digests and sizes;
- duplicate plane artifacts reject rather than increasing coverage;
- artifacts with mismatched workspace/root/revision identities reject;
- empty required-plane sets reject;
- decoding or tampering cannot preserve the canonical artifact digest.

## Proof

- 4 focused tests pass, proving exact projection, deduplicated content objects, explicit three-plane incompleteness, tamper rejection, and duplicate-plane rejection.
- Exact current-source split coverage passes: **729 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **730 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass.
- Release `LoopForge` SHA-256: `8472a2ea03722764ed904c39dc5941ad70d4167f51c1f17e519eb82d06faa567`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `07ec6f286430a6918dc27b1ebee79762de18fe0c0f103cb98c96aecd8e65fa60`.
- Diff whitespace and process cleanup pass. The read-only EasyBusiness fingerprint is unchanged.

## Boundary retained

This slice does not run Git, trust Git porcelain, capture HEAD/index/untracked planes, mint repository-metadata or ignored-policy authority, compose `WorkspacePreimage`, journal/replay preimage evidence, or issue proposal/preflight authority. Resident-memory, publication, native design-baseline/visual authority, final authorization, native start/UI, package/sign, clean commit, and push remain blocked.

Final acceptance remains false.
