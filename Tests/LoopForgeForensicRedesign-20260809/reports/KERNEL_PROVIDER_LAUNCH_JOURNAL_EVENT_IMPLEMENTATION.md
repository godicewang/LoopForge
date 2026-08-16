# Kernel Provider Launch Journal Event Implementation

Status: **implemented and replay-verified; production controller composition remains vetoed**

Recorded: `2026-08-11T18:23:35Z`

## Closed defect

The previous runtime returned provider invocation and secret-delivery metadata
beside a journal transaction, but the provider launch itself was not a typed
event. Recovery could therefore prove a process binding without independently
proving which deterministic provider invocation and credential-free delivery
were authorized for that process.

The command boundary is now deliberately asymmetric. Runtime code receives the
original non-serializable `AuthorizedKernelProviderInvocation`, completes real
spawn and native attestation, then asks `KernelProviderLaunchEvidenceIssuer` for
`AuthorizedKernelProviderLaunch`. The durable receipt is Codable for replay;
the authority wrapper is not, and decoding the receipt cannot recreate command
authority.

## Atomic journal boundary

`recordProviderRuntimeBinding` writes exactly two ordered events in one
hash-journal transaction:

1. `runtimeBindingRecorded`;
2. `providerLaunchRecorded`.

The reducer accepts the command only for the exact active attempt, productive
owned process lease, resource, binding, actor lineage, execution profile,
deterministic invocation, native sandbox attestation, and optional fixed-FD 197
delivery. The projection retains provider launch receipts and their count.

`RunJournal` can retrieve the provider receipt by receipt ID or by the exact
two-event transaction and performs the same recovered frame, event ID, and
sequence checks as runtime binding lookup. A fresh journal instance replays the
receipt exactly.

## Result-chain enforcement

The strict retained-result parser now looks up the same journaled provider
launch before accepting output. It rejects a caller-supplied launch receipt when
its invocation digest, prompt nonce, process identity, or secret-delivery
metadata differs from the replayed event.

## Verification

- provider authority suite: **9 passed, 0 failed**;
- journaled runtime suite: **28 passed, 0 failed**;
- complete suite: **682 tests, 8 skipped, 0 failures**;
- non-DEBUG release build: **passed**;
- `git diff --check`: **passed**;
- exact residual `LoopForge`, `KernelSandboxGate`, and `KernelProcessFixture`
  processes: **0**.

Source identities:

- `KernelProviderInvocation.swift`: `02f9b67045893e3a27f6951a9df71690d332501b568f26c882792de30c6835d4`;
- `JournaledProcessRuntime.swift`: `3b309c96b612e0f2f2489ea307fc236ccb7c40478409572fb16a2eb12b6d29c8`;
- `RunReducer.swift`: `8ec841b7a51ab9edff1e4b9c33021ee6210f1ae8bc02fdbbbea31c370dd0e933`;
- `RunJournal.swift`: `89bcf35603d33fc85982bfe13cc3ff84a71d21eec847558ef15a3bc032b148f3`;
- provider tests: `8458e7c59c85282d018ba5fa06763f13192e604465747739f0db9b8ac581675b`;
- journaled runtime tests: `8d7cfe2ec132434864c70a63b89b6bea9fbf66bf155af5cbe6c803c9b0183344`.

## Remaining veto

This is not production cutover. `LoopController` still directly holds legacy
`CodexRunner` and `GraphLoopEngine` execution paths. Worker, independent
reviewer, verification, visual review, transactional integration, and
completion must be composed through the new journaled provider boundary before
the current source is packaged, native-verified, committed, or pushed.
EasyBusiness remained permanently stopped and read-only.
