# Journaled canonical workspace preimage

Recorded 2026-08-12T10:42:53Z. Final acceptance remains false.

## Implemented boundary

`WorkspaceJournaledCanonicalPreimageIssuer` now resolves the exact previously
journal-accepted Git capture, reobserves it on both sides of repository-policy
capture, projects the confirmed worktree artifact, and composes the four exact
HEAD/index/worktree/untracked planes into one canonical `WorkspacePreimage`.

The embedded repository-metadata digest binds the accepted HEAD commit, Git
directory and common-directory identities, Git executable, object format,
symbolic or detached HEAD state, shallow state, three-plane observation, exact
worktree `.gitignore` source-revision entries, and the descriptor-stable
repository `info/exclude` bytes resolved by Git. Global and system Git config
are disabled. Sparse checkout and any effective external excludes file reject
fail closed rather than extending the read boundary.

Every captured untracked path receives an exact effective ignored/not-ignored
classification through bounded direct Git invocation. An empty classification
list is explicit evidence for an observed empty untracked plane. The ignore
policy digest binds the observation policy, exact policy-source bytes, and all
classifications.

Policy-file reads use an owner-controlled no-follow descriptor, bounded size,
two complete reads, and stable device/inode/size/mtime/ctime checks. Complete
Git and source observations repeat around metadata capture; drift rejects the
whole issuance.

`RunJournal` accepts only the live non-Codable capability and persists only the
inert receipt. Pure reducer replay composes no filesystem or Git facts, exact
duplicate commands return the retained receipt, same-command substitution
conflicts, and decoded tampering cannot advance state. The receipt issues no
manifest, preparation fact, preflight, write, publication, or start authority.

## Adversarial verification

Three real-repository tests prove mixed ignored/nonignored untracked paths,
exact metadata and four-plane composition, explicit empty classification,
receipt encode/decode stability, journal recovery, exact idempotency, command
conflict, tamper rejection without advance, and fail-closed external ignore
authority.

Exact final-source split coverage passed: 750 tests with 8 intentional
environment skips and zero failures, plus the independently run process-group
resistance case, for 751 covered tests and zero failures.

Fresh Release and source bindings:

- LoopForge: `c17a96a6b369563210ac8639be8591ef7a3b5b3286bdcf88a7e15c7a6210f125`
- KernelSandboxGate: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`
- source snapshot before final report reconciliation: `97d15fcf07edde857b714a543175e4ec096d6a950f155e7583032fbe0b67fcfd`

All compilation, tests, builds, waits, failed diagnostics, and reporting are
excluded from the strict ledger. EasyBusiness remained read-only with its exact
prior fingerprint.

## Still blocked

Manifest assembly; proposal/preflight issuance; resident-memory authority;
publication; native design/visual authority; final authorization; native
start/UI; current-source packaging/signing; clean commit; and push remain
blocked.
