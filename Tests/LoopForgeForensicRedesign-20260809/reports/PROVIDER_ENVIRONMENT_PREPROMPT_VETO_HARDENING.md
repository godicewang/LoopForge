# Provider Environment Pre-Prompt Veto Hardening

Status: **implemented and exact package verified; unsupported environment authority now fails before any immutable provider prompt is created**

Recorded: `2026-08-16T00:55:44Z`

## Defect

Provider execution ultimately accepted only the compiler-owned `minimalKernelAllowlist`, but a profile carrying `declaredAllowlist` was still reported ready by the provider projection, accepted by direct invocation authorization, and accepted by receipt replay. A caller entering through the lower `JournaledProcessRuntime` provider preparation path could also create the immutable prompt artifact before the later process-environment authorizer rejected the profile.

The eventual launch veto prevented an unsupported environment from reaching a child process, but the readiness, authorization, replay, and side-effect ordering layers contradicted that veto and could leave an orphan prompt for a policy that could never launch.

## Repair

- `profileReadiness` emits `declaredEnvironmentAuthorityUnsupported` unless the profile uses `minimalKernelAllowlist`.
- `validateExecution` throws `unsupportedEnvironmentAuthority` before prompt authorization for every unsupported policy.
- `receiptIsValid` independently rejects an invocation receipt whose profile does not retain the minimal compiler-owned policy.
- `JournaledProcessRuntime.prepareProviderInvocation` now performs the same validation before `KernelProviderPromptArtifactIssuer.issue`, including when a caller bypasses the higher execution-session precheck.

The runtime test asserts that the rejected prompt path does not exist. The invariant is therefore behavioral: unsupported environment authority is blocked before immutable prompt materialization, not merely before process launch.

## Verification

- focused provider compiler after the complete repair: 20 tests, zero failures;
- affected provider/environment/runtime/sandbox/enrollment/harness selection: 116 tests, zero failures in 21.194 seconds;
- independent complete source suite: 850 tests, 8 explicit skips, zero failures in 63.942 test seconds (63.991 wall), with the real Codex bridge passing in 10.536 seconds;
- exact package-owned complete suite: 850 tests, 8 skips, zero failures in 62.442 test seconds (62.491 wall), with the real Codex bridge passing in 8.671 seconds;
- Release build, nested and deep-strict signing, source/test manifest binding, harness identity, ZIP, DMG, checksums, exact packaged-Mach-O startup, cleanup, and zero residual packaged processes passed.

The exact dirty-source package binds snapshot `0bba91621c094254b083a07401e9e45c4157e1a29626da6d3a67a28b708fd025`, package-log SHA-256 `099d487bbef9710c9692d845fd166af91e234077bbb4c37e152a568f56bbd618`, application SHA-256 `1407e544dd40270660deb237e3b6d43610ef3a6dc28ccc9e182cb1bf93757f83`, and app CDHash `f45679b466871096ae1983551c596c42bc7d0888`.

Computer Use attempted the exact rebuilt package after smoke verification, but macOS remained locked after physical input. The lock was not bypassed and blocked time counts zero; the existing provider diagnostics screenshot remains prior-package evidence only.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04`, and unchanged NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`. Productive backend ratification, unlocked current-package UI, the full native matrix, clean-commit rebuild, commit, and push remain pending. Final release is false.
