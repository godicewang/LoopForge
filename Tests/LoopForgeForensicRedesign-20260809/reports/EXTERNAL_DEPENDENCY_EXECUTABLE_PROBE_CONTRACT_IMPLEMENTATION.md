# External-Dependency Executable Probe Contract

Status: **ratified executable recipe and strict nonce-bound parser present; journal-owned staging, launch, exit mapping, observation issuance, and controller invocation remain pending**

Recorded: `2026-08-14T21:35:52Z`

## Result

An external dependency can no longer enter a newly valid task contract with only an opaque recipe label. Every declared dependency must retain one complete executable observation probe:

- direct local-process transport with an exact executable SHA-256;
- bounded shell-free argv containing exactly one private request token;
- the kernel minimal environment and exact environment/capture identities;
- explicit network policy;
- a canonical parser identity bound to the built-in parser implementation digest;
- unique exit/result mappings covering both `available` and `unavailable`; and
- positive wall/output/resident ceilings with child processes forbidden.

The optional field exists only so historical contracts remain decodable for forensic recovery. Missing or malformed probe material fails new `TaskContract` validation and cannot enroll.

## Strict result grammar

`ExternalDependencyObservationProbe` accepts exactly one newline-terminated canonical sorted-key JSON object. Its six exact keys bind dependency ID, recipe ID, fresh SHA-256 request nonce, result code, evidence SHA-256, and schema version. It rejects extra keys, extra lines, CR bytes, missing newline, invalid UTF-8/JSON, noncanonical key order or escaping, stale/mismatched identity or nonce, unsupported schema, invalid result identity, and non-SHA evidence.

The parser returns a non-Codable authority containing an inert parse receipt. It does not issue a reducer observation. Native exit, exact launch identity, the declared exit/result mapping, and a journal-owned issuer must still be composed before availability can enter authoritative state.

Reducer observation admission now also requires a full lowercase SHA-256 evidence digest; a merely nonempty string is no longer evidence.

## Verification

- New strict probe/parser tests: 4/4 passed.
- Affected contract, reducer, and completion suites: 75/75 passed.
- Exact accepted full source suite: **798 executed, 8 intentional environment skips, 0 failures**, 64.520 test seconds.
- Package-owned full suite: **798 executed, 8 intentional environment skips, 0 failures**, 1012.583 test seconds.
- Non-DEBUG arm64 Release build: **passed**, 114.67 seconds.
- Exact source snapshot: `c4667031cc136e0a780198f21053b79ea07f02760d9790933b7fc1bc6e2d3e30`.
- Packaged `LoopForge` SHA-256: `55a74ce8313e27eabd24d23b3cb6d575de6e6227a6bbe529d4ee86b67941033b`.
- Packaged `KernelSandboxGate` SHA-256: `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`.
- Current dirty-source package signing, hashes, ZIP, DMG, embedded manifest, bounded exact-Mach-O startup, and cleanup passed.

## Boundary

This is the immutable recipe and parse-authority prerequisite, not an executable production observer. No new release launch API was exposed, no external process was started by this authority, and no parsed bytes can directly mint an observation. The next authority slice must stage the exact executable, materialize a descriptor-backed nonce request, launch under an owned resource lease and native sandbox, capture exact output, bind native exit to the declared mapping, and append through one journal-owned issuer.

Production-controller invocation, legacy Single/Parallel retirement, unlocked native screenshots, clean-commit rebuild, commit, and push also remain required. Final release is false. EasyBusiness was not modified.
