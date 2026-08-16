# External-Dependency Runtime Launch Journal Boundary

Status: **activation-bound native-process launch evidence is now atomic and replay-stable; production native spawn remains vetoed without trusted resident-memory enforcement**

Recorded: `2026-08-15T13:31:10Z`

## Result

LoopForge now has one durable boundary between an activated external-dependency
observer and the exact native process claimed to execute it.
`ExternalDependencyObservationRuntimeLaunchReceipt` binds the activation receipt
and activation journal frame; run, attempt, dependency, evidence recipe, and
observer; productive owned process-tree resource and lease; runtime binding;
content-addressed staged executable; immutable request artifact; shell-free
arguments and digest; minimal environment; private standard input, output, and
error files; native sandbox attestation; parser, result mapping, network policy,
resource limits, and the exact resident-memory ceiling.

The process runtime may create reducer command authority only while retaining
the non-Codable activation readiness and resident-memory capabilities. Decoding
the launch or binding receipts cannot recreate either authority. The launch
compiler rechecks accepted binding, exact PID/start/executable/environment/argv
identity, one-process kernel limits, stopped-gate sandbox attestation, nil
candidate working directory, exact private I/O basenames and output path
digests, and every ratified activation field.

Reducer admission appends the runtime binding and launch as one two-event
hash-journal transaction. It requires the undisposed active attempt, live
productive owned process-tree lease, graceful-then-terminate policy, exact
actor/time, and no earlier launch, veto, or observation. Decoded replay runs
the same binding and launch checks. `RunJournal` can read back the exact launch
from that transaction.

The observation issuer now requires exactly one matching launch, its accepted
binding, and natural-exit process identity before it can compose a durable
observation. A result whose release predates launch, names another lease or
resource, or exits under another process identity fails closed.

## Verification

- the focused external-dependency suite passed **14 tests** with **0 failures**;
- the exact source suite passed **807 tests**, with **8 intentional skips** and
  **0 failures**, in **59.543 test seconds**;
- the package-owned suite passed **807/8/0** in **65.538 test seconds**;
- the real Codex child/Responses bridge passed in **22.600 seconds**;
- non-DEBUG arm64 Release built in **105.20 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, and cleanup passed;
- source snapshot:
  `24aafeca731a6ca1104b44b42541e20c1140bb46ef8443de401cb8ddbde05f6e`;
- packaged LoopForge SHA-256:
  `42f8a80f2700a1cd3216e4aaf277f39a723c127a67c1af398e9fc7318cc11898`.

## Boundary

This interval does not claim that a production external observer ran. The
tests use explicit DEBUG-only synthetic launch authority to prove atomic
journaling, exact readback, cross-wire rejection, close/reopen replay, and the
downstream observation boundary. Ordinary macOS still supplies no trusted
Release issuer that installs the required hard physical resident-memory limit
before target exec. The production readiness path therefore retains its typed
pre-admission veto and creates no resource admission, sandboxed observer
process, output, release result, or observation.

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its newline-delimited `-uall`
status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or the retained veto,
actual native spawn/output/release composition, production-controller
invocation, legacy retirement, current unlocked native screenshots, a
clean-commit rebuild, commit, and push remain required.
