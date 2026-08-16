# Kernel Runtime-Fact Command Authority

Status: **direct admission, binding, and release receipt injection closed; real process and workspace cleanup issuers preserved**

Recorded: `2026-08-11T19:36:06Z`

## Finding

`RunCommand.recordRuntimeAdmission`, `recordRuntimeBinding`, and
`recordRuntimeRelease` still accepted ordinary `Codable` receipts. Reducer
checks bound run, lease, resource, monotonic ordering, external identity, native
exit, and termination data, but a module caller could construct the receipt
whose values were checked. This left a provenance gap at the command boundary.

Unlike the issuerless drain and quiescence paths, these commands have two
legitimate production sources that must survive recovery:

- `JournaledProcessRuntime` journals process admissions, native bindings,
  natural/forced/absent releases, and cleanup failures;
- `JournaledWorkspaceMutationLeaseAuthority` journals the exclusive mutation
  lease admission, release, and release failure.

Removing either source would break crash cleanup or leave logical ownership
permanently live.

## Implemented issuer-token boundary

The three reducer commands now require non-`Codable` authority wrappers. Each
wrapper has a private receipt initializer. Production factories require one of
two empty, non-serializable issuer-token types:

- `JournaledProcessRuntimeCommandIssuer`, constructible only inside
  `JournaledProcessRuntime.swift`;
- `JournaledWorkspaceMutationRuntimeCommandIssuer`, constructible only inside
  `JournaledWorkspaceMutationLeaseAuthority.swift`.

Admission and release accept either token. Binding accepts only the process
runtime token. Neither token is returned by an API or represented in journal,
model, environment, provider output, recovery data, or task state. A caller
with a decoded receipt can call neither production factory because it cannot
construct the required token.

Every real process and workspace-mutation callsite now wraps its receipt at the
last journal boundary. DEBUG tests use explicit test-only `RunCommand`
factories. Durable runtime events and replay schemas are unchanged: recovery
can still project already-recorded admissions, bindings, releases, and failures
without recreating a live command capability.

## Crash and cleanup preservation

The change preserves the existing journal-first order:

1. the trusted runtime previews a supervisor receipt;
2. it mints a source-token-bound command capability and commits the journal;
3. only then does it apply the receipt to the in-memory supervisor;
4. failed journal or supervisor commits retain live/in-doubt ownership and
   continue to block quiescence.

Focused tests cover native launch and binding, natural exit, forced
termination, spawn-failure compensation, absent-process recovery, cleanup
failure, stale journal writers, exclusive mutation lease admission/release,
and rollback quarantine.

## Verification

- focused reducer/process/runtime/integration/filesystem suite: **93 passed, 0 failed**;
- complete source suite: **684 tests, 8 skipped, 0 failures**;
- non-DEBUG Release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  executable count: **0**;
- EasyBusiness remained stopped and was observed read-only.

Source identities:

- `RunReducer.swift`: `de3744047cbfb785521325b73a6dbe621f55ef697d7a87457aa1c5dd8a0e8744`;
- `JournaledProcessRuntime.swift`: `f5938ab9c42320ad64973c300f59f1424a019b978d4b6ead6ec634708a8ad713`;
- `JournaledWorkspaceMutationLeaseAuthority.swift`: `d36fe8506b38de4bb9d94ca256585d2234da2483fe6bc4561f005c09fdbe6d9f`;
- reducer tests: `c232c60606063a8f805cfa929f00b42e9b9f7fabe7547b8309559570ba236140`;
- runtime-journal integration tests: `ad71c37c2d08e7181848ccd4d1109ce37fd71be1ac73ac21e08c6d8ba2c34358`;
- process-runtime tests: `9db274ffb1ccc35032d91123de111f1b36343c7e05fbd4d306413e74a0c33dd4`;
- integration state-machine tests: `323987924ddc972a0c2b1e53b91b2223fcf7d6e2103bdc5b2538e3841ec51783`;
- execution test support: `b7291fb319add132b096a3320652034aa810b4cb1b404654d6f3d38a597ceaf9`.

## Remaining vetoes

External-dependency observation, runtime-drain, and quiescence production
issuers remain absent. Native plan/start, deterministic verification and
independent review, native baseline and complete visual evaluation,
integration proposal/preflight/postimage/acceptance and final authorization,
legacy Single/Parallel retirement, current-source package/sign/hash, unlocked
native proof, clean commit, and push remain pending. Final acceptance is false.
