# Provider Native Resource Boundary

Status: **implemented, package verified, and exercised by a real sandboxed provider fixture; a production provider harness remains absent and final release remains false**

Recorded: `2026-08-15T22:41:00Z`

## Defect

Provider launch receipts claimed `hiddenFanOutEnabled: false`, but the provider specification carried no kernel-owned `ManagedProcessKernelResourceLimits`. The native sandbox profile intentionally permits process operations so the signed gate can execute its target; without an independent process-count ceiling, that receipt described policy rather than mechanically proving it. Provider output files were likewise bounded only by parser/capture behavior after launch rather than by an operating-system file-size limit at the process boundary.

## Repair

Current provider launches now require launch-receipt schema 2 and bind an exact compiler-owned native resource limit:

- `maximumProcessCount = 1`, which permits the one provider process and denies child creation;
- `maximumOutputFileBytes = 16,777,216`, equal to the production retained-stdout parser ceiling;
- no caller-supplied resource limits are accepted before authorization;
- after the kernel constructs executable, environment, and sandbox authority, it injects exactly this limit and revalidates the complete transport before admission and spawn;
- the launch receipt digest and external-process identity both bind the same exact limit;
- missing, historical schema-1, broadened, substituted, or removed limits fail current receipt validation.

The V2 provider fixture consumes the prompt, invocation context, and credential descriptors, then attempts to spawn `/usr/bin/true`. It exits with an explicit failure if that child succeeds. Its accepted completion therefore exercises the actual native process-count boundary rather than trusting a Boolean declaration.

## Tests

The focused `KernelProviderInvocationTests`, `KernelNativeSandboxTests`, and `JournaledProcessRuntimeTests` run passed **50 tests with zero failures** in 4.929 test seconds (4.933 wall). It covers caller-limit rejection, exact post-authorization transport validation, schema-2 receipt binding, missing and broadened limits, external-identity continuity, an unbounded native launch veto, and the sandboxed fixture's child-spawn denial.

An independent complete source suite passed **839 tests, 8 explicit skips, and 0 failures** in 60.324 test seconds (60.372 wall). The exact package then ran its own complete suite and passed **839 tests, 8 skips, and 0 failures** in 62.976 test seconds (63.024 wall); the real Codex child/Responses bridge passed in 10.628 seconds.

## Exact package

The signed package binds Git revision `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`, dirty-source snapshot `c5f368373f837697f161fbc6692fc80b7f53319edf943901f80e735266730111`, and package test-log digest `4471efb4916f73c0f2cd11fe68735f3648c2576c025579b99c6ab212580ff132` in `LoopForgeBuildManifest.json`.

Both Release products built. Deep strict signing, every checksum-manifest entry, ZIP integrity, DMG verification, embedded source/test binding, exact packaged-Mach-O bounded startup, Release test-hook absence, cleanup, and zero residual packaged processes passed. The app executable is `ce59a8999f5a5cc5593a9903951f8d64e77413683469a6f6766891b18067a6c6` with CDHash `0144ee068f0dd7f88bd3a746ddb98f6f3ccd16a9`; the sandbox gate is `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`.

## Native proof

Computer Use opened the exact packaged application and its real Kernel diagnostics sheet. Ready run `native-run-c2070190-a24a-42bf-a9f5-fee696aea42c` retained two mutation-preparation blockers and disabled activation. Provider diagnostics separately retained the missing ratified V2 harness and remote network authority constraints. No activation, prompt preparation, provider, verifier, worker, mutation, or legacy execution was attempted. The app quit and zero exact packaged processes remained.

Screenshot: [Packaged provider resource boundary](../screenshots/packaged-loopforge-provider-resource-boundary-20260815T223700Z.png), 860×760, SHA-256 `d164fd0e327c44352c3c51500e37b0e583b92390a3d63e3fc85d38304d06136a`.

## Boundary

This closes the false implication that `hiddenFanOutEnabled: false` alone enforced provider containment. It does not package or independently ratify a production V2 provider harness, grant network authority, prepare a real provider prompt, launch a production provider, supply trusted Release resident-memory containment, complete the full native trait/window/baseline/candidate matrix, rebuild from a clean commit, commit, or push. Final release remains false. EasyBusiness remained read-only at HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04` on `codex/USA_Version`, with unchanged NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
