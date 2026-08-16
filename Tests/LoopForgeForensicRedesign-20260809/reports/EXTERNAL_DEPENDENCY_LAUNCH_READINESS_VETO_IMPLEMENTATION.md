# External-Dependency Launch-Readiness Veto

Status: **unsafe native admission now fails closed before any lease or process; a trusted Release resident-memory issuer remains unavailable**

Recorded: `2026-08-15T11:58:00Z`

## Result

LoopForge now has an explicit production boundary between the journaled inert
external-dependency activation and resource admission. The readiness
coordinator resolves the exact live activation transaction, active undisposed
attempt, retained request artifact, and content-addressed executable. It
revalidates request bytes, SHA-256, device, inode, owner-private journal
directory, staged executable path, digest, byte count, device, and inode before
it can return any readiness decision.

Readiness requires a non-Codable
`AuthorizedKernelResidentMemoryEnforcement` bound to the exact run, activation
receipt, and positive declared resident-memory ceiling. No production issuer
exists on ordinary macOS because the available same-user process mechanisms do
not install the required hard physical resident-memory limit before target
`exec`. The Release path therefore records one deterministic typed veto instead
of weakening the declared resource contract.

The veto is reducer-owned and replay-validated against the exact activation,
source journal-frame digest, attempt, dependency, observer actor, declared
maximum resident bytes, source sequence, and event time. It consumes a globally
unique receipt ID, is exactly retryable through its command transaction, and
cannot be replaced by a second veto. Durable recovery retains causal evidence
of why launch did not happen; it reconstructs no live capability.

## Safety ordering

The missing-containment path creates no runtime admission receipt, no resource
lease, no sandbox profile, no process, no output artifact, and no external
dependency observation. This closes the previous temptation to compose the
generic runtime launch path first and treat the resource ceiling as a
post-launch assertion.

An exact DEBUG-only containment capability proves the positive composition
path without claiming a host kernel guarantee. Cross-wired activation identity
is rejected. A future privileged helper or container may provide a Release
issuer, but the coordinator and reducer boundary must remain unchanged.

## Verification

- the end-to-end activation test now proves exact readiness, cross-wired
  containment rejection, missing-capability veto, zero admission/lease/result
  effects, exact retry, and crash replay;
- the reducer test proves valid veto admission and rejects a tampered decoded
  event with a substituted resident-memory ceiling;
- the exact source suite passed **803 tests**, with **8 intentional skips** and
  **0 failures**, in **61.267 test seconds**;
- the package-owned suite passed **803/8/0** in **55.982 test seconds**;
- non-DEBUG arm64 Release built in **104.81 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, and cleanup passed;
- source snapshot:
  `d33b9c3dabfb24b3d7d8d0bf16dc0cd2283b1278ad85a6193c1b7003f28ce36e`;
- packaged LoopForge SHA-256:
  `6423500ac387207251ed6eb7c63c045345fc0e8d6def24fde3c05185cfa4e625`.

## Boundary

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or a deliberately
retained launch veto, actual journal-owned native launch/result composition,
observation issuance, production-controller invocation, legacy retirement,
current unlocked native screenshots, a clean-commit rebuild, commit, and push
remain required.
