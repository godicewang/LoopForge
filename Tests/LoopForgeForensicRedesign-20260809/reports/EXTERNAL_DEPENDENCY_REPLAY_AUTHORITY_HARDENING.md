# External-Dependency Replay Authority Hardening

Status: **decoded/tampered replay and duplicate-receipt overwrite fail closed; executable probe contract/parser subsequently added; observer runtime and controller cutover remain pending**

Recorded: `2026-08-14T21:35:52Z`

## Result

External-dependency observations now pass the same exact validation at both command admission and event replay. A raw decoded `externalDependencyObservationRecorded` event can no longer bypass the live-attempt, declared-contract, independent-observer, evidence-recipe, digest, or event-time rules that protect the command path.

The replay reducer also rejects any observation whose receipt ID already exists anywhere in the run. A later event therefore cannot replace an accepted unavailable receipt with an available receipt, or otherwise rewrite evidence while retaining the original identity.

One shared pure validator now checks:

- the exact active attempt exists and has no disposition;
- the dependency is the exact declared contract dependency;
- the dependency has a nonempty, exact requirement intersection;
- command admission binds the observer to the command actor, while both admission and replay require an authorized observer independent of the worker lineage;
- the evidence recipe is exact;
- the evidence digest is an exact lowercase SHA-256; and
- `observedAt` equals the accepted event/context time.

Invalid decoded events return the preceding reducer state unchanged. They cannot advance sequence, replace evidence, or create blocker authority.

## Verification

- `KernelRunReducerTests`: 42/42 passed, including direct tampered-event replay and duplicate-ID overwrite rejection.
- Current exact full source suite: **798 executed, 8 intentional environment skips, 0 failures**, 64.520 test seconds.
- Current package-owned full suite: **798 executed, 8 intentional environment skips, 0 failures**, 1012.583 test seconds.
- Current non-DEBUG arm64 Release build: **passed**, 114.67 seconds.
- Exact source snapshot: `c4667031cc136e0a780198f21053b79ea07f02760d9790933b7fc1bc6e2d3e30`.
- Packaged `LoopForge` SHA-256: `55a74ce8313e27eabd24d23b3cb6d575de6e6227a6bbe529d4ee86b67941033b`.
- Packaged `KernelSandboxGate` SHA-256: `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`.
- The current dirty-source app was packaged, ad-hoc signed, deep-strict verified, hashed, archived, imaged, launched through the bounded packaged runtime smoke, and cleaned up.

## Boundary

This closes a replay-authority gap; it does not create an observer. The later [executable-probe contract report](EXTERNAL_DEPENDENCY_EXECUTABLE_PROBE_CONTRACT_IMPLEMENTATION.md) records the now-mandatory executable recipe and strict nonce-bound parser. Descriptor-backed request staging, exact sandboxed launch, exit/mapping composition, journal-owned observation issuance, and controller invocation are still absent. Until those are implemented, unsupported observation remains fail-closed and final release remains false.

The current package is source-snapshot-bound but not clean-commit-bound. Unlocked native screenshots, legacy Single/Parallel retirement, clean-commit rebuild, commit, and push remain required. EasyBusiness was not used as an execution target and was not modified.
