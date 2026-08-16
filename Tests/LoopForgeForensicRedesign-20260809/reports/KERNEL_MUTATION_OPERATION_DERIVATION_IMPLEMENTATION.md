# Kernel mutation-operation derivation implementation

Recorded at: `2026-08-12T05:39:21Z`

## Outcome

LoopForge can now derive an exact regular-file mutation delta from two validated, content-complete `WorkspaceSourceRevisionArtifact` snapshots. The derivation is deterministic and domain-neutral: it compares canonical workspace identity, canonical root, capture policy, sorted paths, permission modes, byte lengths, and SHA-256 content digests. It does not consume model prose or infer intent.

The output is a content-addressed `WorkspaceMutationOperationDerivationReceipt`, not a `MutationManifest`. It deliberately contains no journal receipt IDs and cannot authorize a filesystem effect. A production runtime must still re-establish the bound artifacts, bind the receipt to one ratified node, journal the preparation facts, assemble the manifest, rehearse rollback, and issue the non-serializable preflight capability.

## Supported exact delta

- regular-file create beneath a parent directory already proven by the base artifact;
- regular-file delete;
- content modify with unchanged mode;
- mode change with unchanged content;
- deterministic path ordering and contiguous operation sequence;
- exact requirement ownership and exact write-path containment;
- deduplicated, digest-sorted preimage/postimage content-size references.

## Explicitly retired inference

- Identical content at two different paths is represented as delete plus create; it is never inferred to be a rename.
- New directory topology is rejected because source-revision artifacts do not enumerate directories and the executor does not create them.
- Simultaneous content and mode change is rejected because the current manifest/executor compare-and-swap model cannot safely encode both against one initial tree.
- Symbolic links, submodules, special files, and directory operations remain outside this derivation because the source collector rejects or does not represent them.
- Case-folded path collisions, root/workspace/policy substitution, invalid authority paths, empty requirement authority, outside-scope paths, and empty deltas fail closed with typed errors.

## Proof

- 5 focused derivation tests pass, including exact create/modify/delete/chmod output, no rename inference, combined content/mode rejection, new-parent rejection, path-authority rejection, and root substitution rejection.
- Exact current-source split coverage passes: **725 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **726 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass.
- Release `LoopForge` SHA-256: `c37d268ff262b0a235c98f60178b471881826a04fafe3c7d45d26ba2174f68a9`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `1a16627ade603bb9cf5cce3ed7f5d4ce990de6b1a726bb0b2af601960ce6881f`.
- Diff whitespace and process cleanup pass. The read-only EasyBusiness fingerprint is unchanged.

## Boundary retained

This slice closes deterministic regular-file operation derivation only. It does not capture a canonical multi-plane `WorkspacePreimage`, copy or attest content-object bytes, assemble a manifest from journal state, journal/replay preparation facts, issue proposal/preflight authority, or enable publication. The resident-memory veto, native design-baseline/visual authority gap, native start/UI prohibition, package/sign prohibition, and commit/push prohibition remain unchanged.

Final acceptance remains false.
