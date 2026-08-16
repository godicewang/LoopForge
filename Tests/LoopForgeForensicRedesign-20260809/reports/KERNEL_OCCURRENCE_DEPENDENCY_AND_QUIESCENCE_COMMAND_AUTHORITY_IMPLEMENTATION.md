# Kernel Occurrence, Dependency, Drain, and Quiescence Command Authority

Status: **direct receipt injection closed; clock-owned occurrence and supervisor-owned lifecycle issuers present; dependency observer remains vetoed**

Recorded: `2026-08-11T19:58:13Z`

## Finding

The reducer already validated occurrence evidence, dependency contracts,
runtime-drain snapshots, and quiescence snapshots. However, all four
`RunCommand` cases still accepted ordinary `Codable` receipt values. A caller
could therefore construct the value whose clocks, observer identity, live
resource set, failed-release set, or queued-lease set the reducer compared.
Those checks established internal consistency, not that the clock-owning
recorder, dependency observer, or runtime supervisor actually observed the
fact.

Production callsite audit found one real issuer: `JournaledOccurrenceRecorder`
owns the boot, monotonic, and wall-clock samples and is the only Release source
that records an occurrence. There is currently no Release callsite for a new
external-dependency observation, runtime-drain receipt, or quiescence receipt.
Generic runtime admission, binding, and release commands remain a separate
boundary because their valid crash-cleanup issuers span multiple journaled
runtime files.

## Implemented authority boundary

`RunCommand.recordOccurrence` now requires the non-`Codable`
`AuthorizedKernelOccurrence`. Its initializer and production factory are
file-private to `JournaledOccurrenceRecorder.swift`, so only the component
that actually samples and closes the interval can mint the command. A decoded
`OccurrenceReceipt` cannot recreate that capability.

External-dependency observation, runtime drain, and quiescence each require
their own non-serializable authority wrapper. Dependency observation still has
only a DEBUG test factory and therefore fails closed in Release.

Drain and quiescence now have a real production issuer:
`JournaledRuntimeLifecycleAuthority`. It is composed from the same journal,
supervisor, and ratified actor as the production process session. It journals
the lifecycle request before entering draining, obtains all clocks and resource
sets from the supervisor, and uses a file-private issuer token to journal the
drain. If that second write fails, the supervisor remains safely closed to new
productive work. Duplicate journal receipts are rejected as failures rather
than accepted as proof of a new drain payload. Quiescence is emitted only from a draining supervisor with no
live resources, failed releases, or queued cleanup. Callers cannot supply those
sets, clocks, or the verdict. `.quit` remains rejected because the reducer has
no matching quit lifecycle-request phase.

Durable `OrchestrationEventPayload` receipt schemas are unchanged. Journal
replay continues to validate and project existing events without needing live
capabilities; capability is required only to create a new fact.

## Verification

- focused lifecycle/reducer/supervisor/enrollment suite: **92 passed, 0 failed**;
- complete source suite: **686 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  executable count: **0**;
- EasyBusiness remained stopped and was observed read-only.

Source identities:

- `RunReducer.swift`: `988f0de1521166a7e12654fa15dc488910244be99fc7ab6b083716b8294ccdec`;
- `JournaledOccurrenceRecorder.swift`: `06d3cdccaeb3012abf42e6f062f075ee1cd48ea8c4ff835be596a6fef7ae6c4c`;
- lifecycle authority: `c897aa93569a64b10191c4d54c40cc9eff0435c4216eeb8fc056e2ef41ea8ea8`;
- production execution coordinator: `a4dd7ff41fdcb8863f2169455393956275c19ca8ebbbe61a4d7dc00fe06054f5`;
- runtime integration tests: `6268a60d27602eae8091745a1bcfa1f159987ece1aa18f976a29bdc9dd3bd859`.

## Remaining vetoes

The external-dependency observer remains absent. Native plan/start,
deterministic verification and independent review, native baseline and visual
evaluation, complete integration/final authorization and cleanup composition,
legacy Single/Parallel retirement, current-source package/sign/hash, unlocked
native proof, clean commit, and push remain pending. Final acceptance is false.
