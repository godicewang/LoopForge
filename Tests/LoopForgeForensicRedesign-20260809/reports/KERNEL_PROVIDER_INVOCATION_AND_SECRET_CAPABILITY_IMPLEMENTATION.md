# Kernel Provider Invocation, Prompt, and Secret Transport Implementation

Status: **journal-owned prompt issuance, deterministic provider invocation, fixed-FD secret transport, and an unforgeable replayed provider-launch journal event are implemented; controller/reviewer/completion cutover remains vetoed**

Recorded: `2026-08-11T18:23:35Z`

## Closed authority breaks

`KernelProviderPromptArtifactIssuer` is now the only production constructor for
provider prompt authority. It creates a nonempty bounded prompt with
`openat(O_CREAT|O_EXCL|O_NOFOLLOW)` beneath the already-owned run directory,
writes and syncs exact bytes, changes the file to `0400`, syncs the directory,
and returns a non-serializable authority bound to run, attempt, digest, byte
count, device, and inode. Traversal, overwrite, symlinked run directories, and
empty or oversized prompts fail closed.

Immediately before spawn, the process adapter reopens stdin relative to the
owned directory descriptor, verifies regular-file/single-link/device/inode/size,
hashes the exact already-open descriptor, and rewinds it. A same-inode byte
change therefore rejects before any process or output file is created.

`KernelProviderInvocationCompiler` accepts only that prompt authority plus the
activated execution proof and a lowercase SHA-256 nonce. It constructs the
complete provider-neutral argv, disables plugins and hidden fan-out, binds the
ratified provider/reference/model/reasoning/sandbox/network policy, and retains
both argv and invocation digests. Remote-without-network and broad plugin
authority reject.

`KernelProviderSecretCapability` remains non-Codable, single-use, expiring,
memory-only, and bound to exact run/attempt/provider/invocation. Its maximum
payload is now 8 KiB, so a provider that never reads cannot force an unbounded
pipe write. The adapter creates CLOEXEC pipe ends away from the fixed protocol
FDs, duplicates only the read end to child FD 197, explicitly closes the write
end in the child, and closes the read end in the parent. The signed sandbox gate
marks only FD 198 close-on-exec; FD 197 survives the gate `execve` into the exact
provider target. Delivery occurs only after successful target-exec handshake.
Failure kills and reaps the exact owned process group and removes only
descriptor-owned output files.

The credential-free delivery receipt contains only capability ID, exact
binding, fixed target descriptor, and monotonic delivery time. It contains no
secret bytes, length, hash, argv, environment key, or disk location.

## Release cutover boundary

`JournaledProcessRuntime.prepareProviderInvocation` now creates the prompt
inside its own `RunJournal.runDirectory` and verifies that the exact activation
proof is still active. `admitAndLaunchProvider` accepts no caller argv,
environment, prompt path, sandbox profile, or I/O directory. It constructs the
specification from the authorized invocation, injects immutable prompt identity,
authorizes minimal environment, immutable executable staging, and native
sandbox, then revalidates the complete transport before admission and spawn.

After native spawn, sandbox attestation, and exact runtime binding, a dedicated
issuer consumes the original non-serializable provider-invocation authority and
creates `AuthorizedKernelProviderLaunch`. A decoded receipt cannot recreate this
command authority. One journal command then atomically writes an ordered
`runtimeBindingRecorded` event followed by `providerLaunchRecorded` in the same
hash-journal transaction, eliminating a spawn-record split window.

The provider-launch receipt is credential-free and replay-validates the exact
run, attempt, resource, lease, process identity, native sandbox attestation,
deterministic invocation, optional fixed-FD 197 delivery, monotonic observation,
and receipt digest. `RunJournal` supports exact typed lookup by receipt ID or
transaction after recovery. The strict result parser independently looks up that
same event and rejects substituted invocation digests, nonces, or secret
delivery evidence.

The returned launch receipt retains the replayed provider launch alongside
executable staging, minimal environment, native sandbox, process identity,
journal transaction, and exact I/O names. In non-DEBUG builds,
the generic `JournaledProcessRuntime.admitAndLaunch`, runtime `launch`, and
generic adapter `launch` APIs do not exist. A release build therefore cannot
materialize productive work without provider invocation authority.

The generic APIs remain compiled only for the transport characterization suites.
They cannot silently become a production bypass.

## Adversarial verification

- prompt/invocation/secret suite: **9 passed, 0 failed**;
- native sandbox and provider FD suite: **5 passed, 0 failed**;
- process-group adapter suite: **15 passed, 0 failed**;
- journaled runtime suite: **28 passed, 0 failed**, including a real provider API
  launch, atomic two-event transaction, recovery lookup, strict result binding,
  join, release, sandbox attestation, exact stdout, and zero in-doubt ownership;
- complete source suite: **682 tests, 8 skips, 0 failures**;
- non-DEBUG release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  process count after verification: **0**.

Exact source identities:

- provider prompt/invocation/secret authority: `02f9b67045893e3a27f6951a9df71690d332501b568f26c882792de30c6835d4`;
- process-group adapter: `65f727d2827789fef2654a0083939ab7a7f534b036d18b49a4a04ca17f120565`;
- journaled runtime: `3b309c96b612e0f2f2489ea307fc236ccb7c40478409572fb16a2eb12b6d29c8`;
- reducer/provider event: `8ec841b7a51ab9edff1e4b9c33021ee6210f1ae8bc02fdbbbea31c370dd0e933`;
- typed journal lookup: `89bcf35603d33fc85982bfe13cc3ff84a71d21eec847558ef15a3bc032b148f3`;
- sandbox gate: `26992ad7de51c567e6783ccfa685b13736d80eaa97385ad26f3cbdb43a6435a5`;
- provider fixture: `dd4ff1ae7813cb8110c3011870b67e7993a7eeedec7e46a215d5f95f0562ece0`;
- provider tests: `8458e7c59c85282d018ba5fa06763f13192e604465747739f0db9b8ac581675b`;
- native sandbox tests: `6c091d52ea0fa8666ae1a19b443c1e2aadb1c24ffa18549c184b55dfd52a8d67`;
- journaled runtime tests: `8d7cfe2ec132434864c70a63b89b6bea9fbf66bf155af5cbe6c803c9b0183344`.

## Remaining hard vetoes

This closes the provider launch authority/transport/replay boundary, not the
whole redesign. The controller still does not execute plans through the new
kernel; the legacy `CodexRunner` remains disconnected rather than migrated;
independent reviewer execution,
verification, visual review, transactional integration, and completion are not
yet composed end to end. The current source also has not been packaged into the
signed app/ZIP/DMG, verified through an unlocked native UI, committed, or
pushed. Final acceptance remains false. EasyBusiness remained permanently
stopped and read-only.
