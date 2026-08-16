# Kernel ratified baseline content capture implementation

Recorded at: `2026-08-12T07:01:18Z`

## Outcome

LoopForge can now issue a non-serializable capability carrying the exact mutation preimage bytes observed from the baseline bound by a production-enrolled, user-ratified task contract. `WorkspaceRatifiedBaselineContentCaptureIssuer` reloads the exact recovery registration, replays the run journal, requires the original enrollment transaction and contract, matches the derivation to the contract's complete source revision, recaptures the full workspace before and after extraction, and reads each required preimage through a held no-follow root descriptor.

The durable receipt binds run, contract, ratification receipt, enrollment journal frame, derivation, base source revision, capture policy, sorted digest-size references, executor-compatible object-set digest, byte/object totals, root device/inode, and a canonical receipt digest. The receipt is inert; only the issuer-created non-Codable value carries bytes.

## Authority boundary

This closes only the ratified **baseline** byte-origin boundary. It does not capture candidate postimage bytes, cannot create the complete before/after object set, does not write the durable object store, has no content-capture journal event or replay projection, and cannot construct a mutation manifest or issue proposal/preflight/effect authority.

The asymmetry is deliberate. `expectedPreimage` digests are selected from the ratified baseline, while candidate `desiredPostimage` bytes are never accepted from caller data. Complete object-set verification remains impossible until a separate journal-authorized candidate source exists and both planes are composed by a journal-first runtime.

## Fail-closed controls

- the supplied enrollment must equal the registry's exact production-ratified registration;
- enrollment provenance must match the ratification receipt, contract, original journal frame, and ending sequence;
- the original enrollment transaction and current reducer-owned contract must replay exactly;
- workspace, canonical root, capture policy, and base revision must agree across contract, registration, and derivation;
- the complete baseline is recaptured before and after byte extraction;
- the canonical root is opened through a `realpath`-normalized absolute component walk using `openat`, `O_DIRECTORY`, and `O_NOFOLLOW`;
- each selected file is opened descriptor-relative with no-follow parent traversal, then mode, size, device, inode, modification time, and SHA-256 are checked across the read;
- root identity and modification time must remain stable across the complete operation;
- missing digest-size references, changed bytes, symlinks, another workspace's derivation, and caller-substituted enrollment data reject;
- receipt replay alone cannot reconstruct the non-Codable capability.

## Proof

- 4 focused authority tests pass, covering exact preimage-only extraction, changed and symlinked baseline rejection, cross-workspace derivation rejection, and substituted enrollment rejection.
- Exact current-source split coverage passes: **741 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **742 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass.
- Release `LoopForge` SHA-256: `6e713a17b1762b1f8913801508f8ebbc4e9bd1e888ac34caeec37abc1223ab60`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `d86b4d251e3747118f788b3c0d4173999aceb98cc8fc22d74a14d142a5d16d06`.
- Issuer source SHA-256: `0b5bca1ec9aec2711a6e014f0de54809ea2a27ba759740c83883c273086b8baa`.
- Enrollment test source SHA-256: `c0a0bea247f076edca2b5b813734c9337a6d6c543c463f914573da250e755b45`.
- Diff whitespace, process cleanup, and the unchanged read-only EasyBusiness fingerprint pass.

## Boundary retained

Candidate source authorization and byte capture; complete before/after object-set composition; journal-first capture/store events and replay; HEAD, index, and untracked preimage planes; repository-metadata and ignored-path policy authority; canonical `WorkspacePreimage` and manifest assembly; proposal/preflight issuance; resident-memory authority; publication; native baseline/visual authority; final authorization; native start/UI; package/sign; clean commit; and push remain blocked. Failed intermediate test assertions and path diagnostics, all tests/builds, waits, polling, and reporting are excluded from the ledger. Final acceptance remains false.
