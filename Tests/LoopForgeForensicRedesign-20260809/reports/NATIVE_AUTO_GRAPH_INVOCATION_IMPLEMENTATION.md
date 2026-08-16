# Native Auto Graph Invocation

Status: **native contract review and journal-first ready enrollment invoked from SwiftUI; legacy execution cutover and current unlocked UI proof pending**

Recorded: `2026-08-11T09:26:27Z`

## Production boundary now invoked

The public new-task path no longer lets Auto Graph call the legacy task creator
or `GraphLoopEngine`. Selecting Auto Graph and choosing either the original
objective or an optimized candidate now creates an immutable native confirmation
draft. The SwiftUI sheet displays the exact objective, canonical workspace,
relative read/write scopes, acceptance rules, and complete candidate digest
before the user can authorize enrollment.

Original text is recorded as `.user`. A model-written option can become
authority only as `.acceptedUserAmendment` after the user explicitly selects
it; `.modelProposal` is rejected by the native author. Cancellation clears the
draft and produces no journal, registration, task, or worker.

Confirmation is bound to the exact displayed candidate digest and user identity.
The confirmed contract, run ID, command ID, and enrollment time are retained
unchanged across a retry. Successful enrollment durably appends `runCreated`,
reads the reducer-owned projection back, requires exact phase `ready`, and only
then publishes recovery registration. The returned projection is rendered as a
read-only native diagnostics card. It explicitly says no legacy worker or
strategy has started.

## Adversarial proof

The new integration suite proves that:

1. Auto Graph review invokes native authoring and journal-first enrollment;
2. the result is an exact `ready` kernel projection with no legacy `LoopTask`;
3. the legacy controller start count remains zero;
4. selecting optimized text records accepted-user-amendment authority;
5. cancellation creates zero journal or recovery registration.

The focused invocation suite passed **13 tests with 0 failures**. The complete
development and package-owned suites passed **619 tests, 8 environment
skips, and 0 failures**. The exact-source arm64 bundle passed deep strict
signature verification, ZIP/DMG/checksum verification, direct Mach-O startup,
cleanup, and zero residual packaged processes.

## Receipts

- source snapshot: `1303cb7ec1a7f343cf2537825939771a7b0eb70d076f191ace601e0601a99734`
- AppModel: `c3d0df36d464025349bec9b775b17a1bfbab206a7e528734ab880ea0eb74e75e`
- SwiftUI views: `addfa8bd6489093a1ddcd34cc5bb00e6bddc989bb43ae7e82ceea90d98c48acd`
- native authoring: `c0169b7e8d5b0cf5b7e169a0eefb0a34f81f088342d1e0df062b8cd1cce58423`
- enrollment coordinator: `8645f5e7351c25cb9b6fbde0d30ab94cd4386274fe37fdf00a5d5b3adbf041bb`
- invocation tests: `8ab25c41ee46fb1f2a45053420f6c3e6aa04e5907139985325c2070e25f2d4c3`
- focused log: `ecae694b70ffa054d72e5116aeafbd22ecd71c942bb7f2cce5887f7e632a9fc8`
- full development log: `383913d1da1e49f362098042ef84f00dffed233e999047bbbee500a6970b5180`
- package test log: `afbaf096e4dc6f140ed1c81c567c117346e08fb05307d1fe426c4cd62cbd5448`
- package invocation log: `735ff6c2e02c03ed13ac57c3441d5c1c362d5e779d5d5bd383f4ebc728b480d4`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- executable: `3aa6db2cb2e0b938beec26b911dea2f77716cb3375457d28ea25443971f55dc5`
- ZIP: `b33307733b800612b960dad49e677f24b2a76cd46147d9c5fceb2fad31a8ef03`
- DMG: `a3181075e461c87a8bd23dae15e8f3b2c7ecdf7b0ac73537eb75d3c444d75b23`
- CDHash: `f2c50cea69e67c4eecde5fb7187c3cc26292d8f2`

## Remaining boundary

Enrollment intentionally does not start execution. Historical Auto Graph start
and resume are now retired at UI, AppModel, and controller boundaries. Native
planner, worker, timing, process, and integration replacement has not yet been
composed under reducer/journal authority. Single Loop and Parallel continue using
their legacy controllers and are not presented as native-kernel execution.

The one Computer Use inspection in this interval was blocked because macOS was
locked after physical input. No unlock bypass or repeat polling occurred and the
blocked interval counts zero. Current contract-sheet and ready-diagnostics
screenshots, complete controller/runtime cutover, clean commit, and push remain
mandatory. Final acceptance is false.

EasyBusiness remained permanently stopped and read-only.
