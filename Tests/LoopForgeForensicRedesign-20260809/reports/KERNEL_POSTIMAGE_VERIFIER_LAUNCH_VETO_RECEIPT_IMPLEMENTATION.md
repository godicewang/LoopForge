# Journaled postimage-verifier launch-veto receipt

Recorded: 2026-08-14T12:03:27Z

Status: implemented and verified; rollback recovery and pre-apply containment
readiness remain pending.

## Boundary closed

LoopForge can now distinguish an activated verifier that was deliberately
stopped by the exact resident-memory containment gate from a verifier whose
launch was never attempted.

`JournaledProcessRuntime` still checks resident-memory authority before any
verifier admission. When the capability is absent or does not authorize the
exact activation, the runtime now journals a schema-v1
`KernelPostimageVerifierLaunchVetoReceipt` before returning
`residentMemoryEnforcementUnavailable`.

The receipt binds the exact:

- run and activation receipt;
- activation journal-frame digest;
- integration transaction and apply receipt;
- attempt, evidence recipe, and independent verifier actor;
- required maximum resident bytes;
- resident-memory-unavailable typed reason;
- source journal sequence and runtime-owned observation time.

It is causal failure evidence only. It is not a `VerificationReceipt`, cannot
reject or satisfy a requirement, does not advance integration, and cannot
authorize publication or completion.

## Non-forgeability and reducer replay

Release callers cannot construct the authorized command wrapper. The private
initializer can be reached only with the file-owned
`JournaledProcessRuntimeCommandIssuer`.

The reducer accepts the veto only while the matching integration is exactly
`appliedUnverified`, the apply and activation identities match, the verifier
is the command actor, the byte ceiling equals the activated recipe, the source
sequence and command time are exact, and no launch or prior veto already names
that activation. Receipt identities participate in global duplicate checking
and accepted occurrence evidence.

`KernelRunState` retains an optional veto map for backward-compatible journal
decoding. `RunJournal` exposes exact receipt and exact single-event transaction
lookups. Reopening the journal reconstructs the same receipt without invoking
the verifier or creating a lease.

## Request hardening

The veto runs before ordinary process admission, so malformed launch requests
must not be able to manufacture causal evidence or exploit duplicate command
identity. Runtime validation now requires:

- nonempty lease and resource identities;
- distinct nonempty stdout and stderr names;
- five nonempty, mutually distinct admission/binding/launch/failure/veto
  receipt identities;
- four nonempty, mutually distinct admission/binding/failure/veto command
  identities.

An invalid request fails as `invalidSpecification` before the activation or
containment decision is journaled.

## Verification

- The production missing-capability path journals the exact veto and still
  creates no verifier lease.
- A cross-wired DEBUG containment capability records the veto for the
  attempted activation, never the capability's different activation.
- The completed-candidate production path records the exact activation frame,
  apply identity, recipe ceiling, and typed reason, remains
  `appliedUnverified`, and reconstructs the same veto after a fresh
  `RunJournal` open.
- 44 focused integration/enrollment tests passed.
- The exact final-source full suite passed 766 tests with 8 intentional
  environment skips and zero failures in 70.323 test seconds.
- The Release build passed in 98.01 seconds.
- Diff whitespace and owned Swift/process cleanup passed.
- EasyBusiness remained read-only at exact HEAD
  `2ae40452e6d8661c46db466c43ea40bba3bfab04`.

One initial test compilation failed because XCTest autoclosures cannot contain
`await`; it was corrected by awaiting before unwrapping. Two later full-suite
runs encountered the existing suite-order-sensitive provider natural-exit
timeout; the exact failing test immediately passed alone, and the next complete
exact-source run passed. All three failed runs and their time counted zero.

## Exact source identities

- `KernelPostimageVerifierActivation.swift`:
  `bc9fc98dd1a56a103f57bb9b284eba9001a90a3d00e9f76cce83f2e227792df9`
- `JournaledProcessRuntime.swift`:
  `920509ad4a5a95a59a8de38d312182bcde8a6aa8e2ec9aa5cf9d77896fcead15`
- `RunReducer.swift`:
  `82ce4baaab1814b756c168f28a3ca15eaa04c153e08ec70e3b9e27faa52c386b`
- `RunJournal.swift`:
  `d5b8215f81326dac0c0539f86173dd56419495bb976489d202065d506c533734`
- `IntegrationTransactionStateMachineTests.swift`:
  `00e5a9a902f0399eb1b5e543d9056a4e0ef952b0765b28bada26c15891f2485a`
- `KernelRunEnrollmentCoordinatorTests.swift`:
  `34ee6d49355b875030a67ebd7043b68d0c7b519944f01a43f004421d317d2745`
- Release executable:
  `4295304e69be6e807bb05911865d37a9528e8e59824489921f854ce3d9d59ea6`

## Remaining safety boundary

The accepted veto is now sufficient causal input for a rollback recovery
coordinator, but that coordinator does not yet exist. It must still reload the
exact completed apply envelope, require no later verifier launch, acquire a
fresh exclusive rollback lease, journal the exact rollback intent before the
outbox effect, and quarantine any drift or identity ambiguity. Future
canonical apply must separately be gated on exact containment readiness.

Final acceptance remains false.
