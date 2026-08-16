# Kernel Runtime Lifecycle Authority

Status: **journal-first production drain and supervisor-derived quiescence issuer implemented**

Recorded: `2026-08-11T19:58:13Z`

## Finding

The reducer already required non-`Codable` authority for runtime drain and
quiescence facts, but Release had no issuer. `RuntimeSupervisor` was the only
component that actually owned the live-resource, failed-release, queued-cleanup,
draining, wall-clock, and monotonic-clock state needed to issue those facts.
Allowing a caller to supply any of those values would have reopened the exact
receipt-injection boundary that the reducer wrapper closed.

The lifecycle request and supervisor transition also form a two-boundary
operation. If the supervisor entered draining before the lifecycle request was
durable, replay could lose the reason. If the drain event was written before
the supervisor closed admission, productive work could enter after the
purported snapshot.

## Implemented authority

`JournaledRuntimeLifecycleAuthority` is composed from the same `RunJournal`,
`RuntimeSupervisor`, and ratified actor identity as the production process
session. Its caller supplies only the requested lifecycle intent and fresh
command/receipt identities. The authority owns all clocks and observed sets.

Drain order is now:

1. journal the reducer-accepted pause, completion, or stop request;
2. ask the supervisor to enter fail-closed draining and obtain its real
   live-resource, failed-release, and queued-cleanup snapshot;
3. mint the drain command with a file-private, non-serializable issuer token
   and append it to the same journal;
4. return the supervisor's exact bounded cleanup plan.

If step 3 fails, the supervisor remains draining and refuses new productive
leases. The authority also rejects any journal transaction returned as a
duplicate instead of treating command-ID idempotency as proof that the new
payload was written. An adversarial reused-ID test proves that the journal
stops at `stopRequested`, the supervisor remains `.draining(.stop)`, and the
API reports failure. This is a visible, recoverable stop-the-line state rather
than a silently reopened runtime. `.quit` is intentionally rejected because the
current reducer lifecycle semantics recognize pause, complete, and stop but do
not have a matching quit request phase.

Quiescence is never caller-selected. The authority samples its own clocks and
asks the draining supervisor for a verdict. It emits a journal command only
when live resources, failed releases, and queued cleanup are all empty;
otherwise it returns the supervisor's exact typed blocking set. Durable event
and recovery schemas remain unchanged.

`KernelProductionExecutionSession` privately retains this authority and now
exposes bounded drain and quiescence operations. It does not expose the issuer
token, raw supervisor, journal, clocks, observed sets, or verdict constructor.

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
- `JournaledRuntimeLifecycleAuthority.swift`: `c897aa93569a64b10191c4d54c40cc9eff0435c4216eeb8fc056e2ef41ea8ea8`;
- `KernelProductionExecutionCoordinator.swift`: `a4dd7ff41fdcb8863f2169455393956275c19ca8ebbbe61a4d7dc00fe06054f5`;
- runtime-journal integration tests: `6268a60d27602eae8091745a1bcfa1f159987ece1aa18f976a29bdc9dd3bd859`.

## Remaining vetoes

The external-dependency observer remains absent. Native plan/start,
deterministic verification and independent review, native baseline and complete
visual evaluation, integration proposal/preflight/postimage/acceptance and
final authorization, cleanup execution across every owned resource type,
legacy Single/Parallel retirement, current-source package/sign/hash, unlocked
native proof, clean commit, and push remain pending. Final acceptance is false.
