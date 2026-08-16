# External-Dependency Release-Bound Result Authority

Status: **exact retained output, natural native exit, mapping, and one journal release now compose into process-runtime-only result authority; launch and observation journaling remain pending**

Recorded: `2026-08-15T12:38:09Z`

## Result

LoopForge now has the authority boundary immediately after deterministic
external-dependency result mapping. The parser receipt binds the complete
newline-terminated standard-output digest and byte count as well as the
canonical terminal-envelope digest. Output identity therefore cannot be
detached from the bytes consumed by the strict parser.

`ExternalDependencyObservationResultAuthority` composes only when all of the
following agree exactly:

- the ratified executable probe and journaled activation;
- retained standard output and empty standard error within the declared cap;
- the strict nonce-bound parse receipt and its complete output identity;
- the unique declared result mapping row;
- one natural process-group exit with no termination signal;
- the exact run, resource, lease, process, release receipt, release sequence,
  and hash-journal frame; and
- a non-duplicate one-event release transaction completed after activation.

The resulting self-digested receipt retains every identity above, its mapping,
and an evidence-set digest. Cross-wired leases, duplicate release transactions,
forged output digests, signaled exits, mismatched mappings, oversized output,
and noncanonical parser evidence fail closed.

## Authority boundary

The durable receipt remains inert. Its non-Codable wrapper can be created in
Release only with the file-private `JournaledProcessRuntimeCommandIssuer`, so
decoded result or release data cannot reconstruct live authority. The wrapper
still cannot append an external-dependency observation by itself; a subsequent
journal-owned coordinator must re-resolve the exact activation and release,
derive the existing reducer observation receipt, append it atomically, and
verify exact readback.

Ordinary macOS still lacks the trusted Release resident-memory issuer required
before observer launch. The production path therefore retains the typed
pre-admission veto and creates no process, output, result authority, or
observation.

## Verification

- six focused probe/mapping/result-authority tests passed with zero failures
  in 0.008 seconds;
- the exact source suite passed **805 tests**, with **8 intentional skips** and
  **0 failures**, in **61.569 test seconds**;
- the package-owned suite passed **805/8/0** in **62.364 test seconds**;
- the real Codex child/Responses bridge passed in **18.981 seconds**;
- non-DEBUG arm64 Release built in **95.82 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, and cleanup passed;
- source snapshot:
  `20ebda0a6870940079d93b21bbc345636aaa8875cc970b3e2fea24685fd879be`;
- packaged LoopForge SHA-256:
  `527bf19893f81e0a23ffcd1f9ed6b285ac5f6142cf8ed025e1841101e8e66970`.

## Boundary

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or the retained veto,
journal-owned native launch/output/release composition, observation issuance,
production-controller invocation, legacy retirement, current unlocked native
screenshots, a clean-commit rebuild, commit, and push remain required.
