# External-Dependency Result Mapping

Status: **exact transport, canonical parse evidence, native exit, and one declared mapping row now compose deterministically; native launch and observation issuance remain pending**

Recorded: `2026-08-15T12:21:08Z`

## Result

LoopForge now has an inert, deterministic result-mapping boundary after the
external-dependency parser. The mapper accepts only the exact live activation,
ratified probe, canonical parse receipt, and native exit pair. It revalidates
the complete binding and selects exactly one declared mapping row by result
code, preserving the row ordinal and declared availability in a self-digested
mapping receipt.

The executable-probe contract now rejects substituted transport metadata at
validation time. Its environment digest must be the exact digest of the
declared minimal environment, and its capture digest must equal the immutable
shell-free private-request/private-output transport policy. A valid-looking
SHA-256 string can no longer stand in for either contract.

The parser receipt also has an exact self-validation predicate. The canonical
terminal envelope digest is recomputed from dependency, recipe, nonce, result,
and evidence identity; manually replacing that digest with another valid
SHA-256 no longer creates acceptable parse evidence.

## Authority boundary

`ExternalDependencyObservationResultMappingReceipt` is data, not authority. It
cannot start the executable, retain output, mint an observation, append a
journal event, or satisfy final completion. Native launch remains behind the
resident-memory readiness boundary. Ordinary macOS still has no trusted
Release issuer for the ratified hard physical-memory ceiling, so the production
path retains the pre-admission typed veto and creates no process or mapping
receipt.

## Verification

- five focused parser/contract/mapping tests passed with zero failures in
  0.005 seconds;
- substituted environment and capture digests reject during probe validation;
- native-exit mismatch, cross-wired nonce, forged canonical terminal digest,
  and invalid/substituted mapping contracts all reject;
- the exact source suite passed **804 tests**, with **8 intentional skips** and
  **0 failures**, in **53.764 test seconds**;
- the package-owned suite passed **804/8/0** in **58.864 test seconds**;
- non-DEBUG arm64 Release built in **96.09 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, and cleanup passed;
- source snapshot:
  `137063c4f1d6c4eee61a025ba3b14d0c2c2ee0fe6f7f437e99f5da834b030437`;
- packaged LoopForge SHA-256:
  `408461c04651b91a3779cceebb06a6fdd5c906890ee4864548cac3b7bfbc6b17`.

## Boundary

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or the deliberately
retained veto, journal-owned native launch with retained standard input,
bounded output and native-exit retention, observation issuance,
production-controller invocation, legacy retirement, current unlocked native
screenshots, a clean-commit rebuild, commit, and push remain required.
