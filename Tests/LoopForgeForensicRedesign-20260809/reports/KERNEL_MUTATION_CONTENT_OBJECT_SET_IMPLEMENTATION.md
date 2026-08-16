# Kernel mutation content-object set implementation

Recorded at: `2026-08-12T06:01:30Z`

## Outcome

LoopForge can now verify that the exact mutation delta's complete unique before/after content-reference set was supplied as bytes. `WorkspaceMutationContentObjectSetVerifier` binds the canonical derivation receipt, base and candidate source revisions, every digest and expected size, the executor-compatible staged-object-set digest, object count, total bytes, configured limits, and a canonical receipt digest.

Every object is SHA-256 rehashed. The verifier requires exact set equality: no missing object, extra object, duplicate digest, corrupt same-length bytes, or wrong-size bytes can produce a receipt. Count, per-object, cumulative, overflow, and malformed-limit boundaries fail closed.

## Authority boundary

The result is durable inert evidence, not provenance or effect authority. It proves that the caller supplied a complete byte set matching the already validated delta; it does not prove where those bytes came from, that they were stored through a no-follow descriptor, that they remain available, or that a journal accepted them. It contains no receipt IDs, cannot construct a mutation manifest, cannot issue preflight authority, and cannot start apply.

The optimized Release executable hash remained unchanged after this disconnected slice. That directly confirms the verifier has not been wired into a production issuer or native start path.

## Fail-closed controls

- invalid derivation receipt rejects;
- invalid or internally contradictory limits reject before byte processing;
- the complete derivation reference set is required exactly once;
- unexpected, missing, and duplicate objects produce typed errors;
- actual byte length must equal the derivation's exact size;
- exact bytes must hash to the declared content digest;
- object count, per-object bytes, cumulative bytes, and arithmetic overflow are bounded;
- input order does not affect canonical object-set or receipt identity;
- receipt validation recomputes all canonical bindings.

## Proof

- 4 focused tests pass, covering complete unordered input, missing/extra bytes, duplicate digest, corrupt same-size bytes, wrong-size bytes, count ceiling, object ceiling, and cumulative ceiling.
- Exact current-source split coverage passes: **733 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **734 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass.
- Release `LoopForge` SHA-256: `8472a2ea03722764ed904c39dc5941ad70d4167f51c1f17e519eb82d06faa567`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `1eb3e8b7cb3fecfbff2c844e399d5580f8f3da1f1a17630024334f8f4f9795ec`.
- Diff whitespace and process cleanup pass. The read-only EasyBusiness fingerprint is unchanged.

## Boundary retained

The next required content boundary is provenance-bearing, descriptor-relative, content-addressed byte storage for both base and candidate objects, followed by journal capture/replay. HEAD/index/untracked preimage planes, complete `WorkspacePreimage` assembly, repository metadata/ignored policy authority, manifest assembly, proposal/preflight issuance, resident-memory authority, publication, native baseline/visual authority, final authorization, native start/UI, package/sign, clean commit, and push remain blocked.

The failed first focused run used an invalid test limit configuration and is explicitly excluded from the ledger. Final acceptance remains false.
