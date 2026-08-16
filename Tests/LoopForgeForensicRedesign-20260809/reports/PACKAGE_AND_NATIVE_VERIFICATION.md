# Package and Native Verification

Status: **current dirty-source package and four-cell native matrix passed independent review; clean-commit rebuild remains pending**

Recorded: `2026-08-16T10:05:20Z`

## Current package result

Packaging bound Git revision `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`, dirty-source snapshot `3870639da9fa122df044658f68608fbfed8385fccd341fb7ee2d872d2be57845`, and the package-owned **874-test, 8-skip, 0-failure** log digest `9c16fe6f7a10f94c2a71a472c813ef291011dc7c19e15c1001325115c24edf45` inside `LoopForgeBuildManifest.json` before signing. Smoke verification independently recomputed the same source snapshot and test-log digest from the package.

The package-owned suite completed in 78.937 test seconds (78.992 wall). All three non-DEBUG arm64 products built. Strict deep ad-hoc signature verification, plist parsing, ZIP integrity, DMG verification, every checksum-manifest entry, embedded source/test binding, exact signed-harness manifest identity, model-weight exclusion, direct and mounted exact packaged Mach-O bounded startup, mounted-DMG byte identity for all three Mach-O files, detach, and cleanup passed.

Artifacts:

- executable: 26,401,120 bytes, `530a0eaeb39fb68f97becc8a8157b0ca6805a0b950f3280ed43da459dd427c36`;
- sandbox gate: 78,512 bytes, `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`;
- provider harness: 145,952 bytes, `d4de4d8b38a59186f8f184ddf1c54ea7f63bd5084d18df0bb37fa7edd19154ac`;
- ZIP: 253,473,698 bytes, `7e5af93ea939e96a9ae2530f8106498396353df9027fccfd5b8108b43a29eb58`;
- DMG: 285,780,239 bytes, `128d41d4d034b34c874ac1a3ce93227dbb5b177e6ddd5970244eb469cf42e184`;
- package test log: 250,860 bytes, `9c16fe6f7a10f94c2a71a472c813ef291011dc7c19e15c1001325115c24edf45`;
- checksum manifest: 278 bytes, `c898eb9346c0b39ef1ec8d5369f0ffd21449b7fe3f85fae57add87c694d5ac49`;
- build manifest: 352 bytes, `af592316528d7b21a601acd70d4b54002b0edbd1fa415babb24f139ef1a05667`;
- app CDHash: `c8bab45483ba49959d16bd4aeef86e5b40d5b60a`;
- gate CDHash: `138982f66022e1d20d76823282ff6a9fc507d3b6`.

## Provider Harness V2 transport-veto package

The package now contains a separately signed V2 harness and exact manifest. It validates the fixed FD-196 context, exact stdin prompt, optional FD-197 credential, ordered flags, and canonical terminal JSONL. Its manifest and self-test explicitly declare `transportVetoOnly` with no productive provider backends. Native readiness now reports the semantically exact `productiveProviderArchitectureUnavailable` while preserving the schema-v1 raw value `providerHarnessProductiveBackendUnavailable`; a valid harness invocation can propose only `blocked`. An adversarial manifest with productive mode, a Codex backend, a self-consistent productive self-test, and the exact executable identity was rejected. The current ordinary app cannot mint productive authority by installation or relabeling; a future route requires a separately scoped privileged or virtualized isolation product. Details are in [Productive Provider Architecture Scope Retirement](PRODUCTIVE_PROVIDER_ARCHITECTURE_SCOPE_RETIREMENT.md) and [Provider Harness V2 Transport-Veto Spine](PROVIDER_HARNESS_V2_TRANSPORT_VETO_IMPLEMENTATION.md).

The bounded direct and mounted startup probes launched this exact package and cleanup proved zero residual processes. Computer Use then opened the same exact package while unlocked, enrolled one read-only inert ready run over the bounded `KernelSandboxGate` source fixture, and retained a hash-bound 860×760 Kernel-diagnostics screenshot. Enrollment created no attempt or worker. **Activate Native Attempt** remained disabled; the diagnostics displayed the exact productive-provider architecture veto and separate network-authority constraint. A real Cmd-Q left zero packaged processes or verification mounts. The preserved historical EasyBusiness task remained stopped and untouched; no prompt, provider, verifier, mutation, or legacy execution was launched. [Productive Provider Architecture Scope Retirement](PRODUCTIVE_PROVIDER_ARCHITECTURE_SCOPE_RETIREMENT.md), [current-package status](CURRENT_PACKAGED_NATIVE_UI_VERIFICATION.md), and [terminal strategy-history implementation](TERMINAL_STRATEGY_HISTORY_PRESENTATION_IMPLEMENTATION.md).

The exact packaged Release executable contains no XCTest, LoopForgeTests, `startRetiredExecutionForTesting`, or test-hook marker.

## Runtime release-policy compatibility and exact mutation join

The shared supervisor now treats release policy as part of resource identity:
borrowed resources detach, owned process trees gracefully terminate, and every
other owned resource joins through its exact typed owner. Incompatible direct
admission returns `invalidReleasePolicy`; queue validation and recovery
snapshots use the same rule. A historical process-tree join lease therefore
fails closed instead of entering a cleanup projection, and a non-process
resource cannot masquerade as gracefully terminable. The only production
non-process join issuer found is the typed workspace-mutation lease authority.
The production composition now retains its exact non-Codable join handle,
preflights the complete plan set, dispatches only the already-authorized
envelope, and requires exact release, empty ownership, and
`appliedUnverified` journal proof before removing the handle. Startup recovery
and quit share one retained recovery task, so they cannot race. Details are in
[Runtime Release-Policy Compatibility Hardening](RUNTIME_RELEASE_POLICY_COMPATIBILITY_HARDENING.md)
and [Workspace Mutation Normal-Quit Join](WORKSPACE_MUTATION_NORMAL_QUIT_JOIN_IMPLEMENTATION.md).

## Ordinary-macOS containment strategy retirement

Production resident-memory resolution no longer uses an optional resolver and
`nil` to ambiguously mean either unsupported platform or missing wiring. Every
external-observer, postimage-verifier, and complete-contract resolver now
returns exact non-serializable authority or the typed
`ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit` decision. Default
production returns the latter and retains the pre-admission/pre-effect veto.
Durable raw values remain schema-v1 compatible.

The installed SDK defines `RLIMIT_RSS` as `RLIMIT_AS`; the current ordinary
arm64 process received `KERN_NO_ACCESS` from
`task_set_phys_footprint_limit(mach_task_self(), ...)`. Address-space limits,
data-segment limits, jetsam attributes disproven for this process class, and
parent sampling are not relabeled as hard physical-footprint enforcement. The
ordinary-app issuer strategy is therefore retired. A future route requires a
separately ratified privileged or virtualized isolation boundary. Details are
in [Ordinary-macOS Resident-Memory Strategy Retirement](ORDINARY_MACOS_RESIDENT_MEMORY_STRATEGY_RETIREMENT.md).

This change has no visible UI effect. The retained native screenshots remain
exact evidence for the preceding `0e42de36…21da7` package and are not current
package evidence.

## Native network-authority authoring

Native Journaled Auto Graph authoring now exposes one explicit worker-network toggle, off by default. Enabling it creates exactly `kernel.network-access` across the user source binding, authority ceiling, causal strategy, plan node, and a non-Codable grant receipt bound to the whole ceiling and compiled-candidate identity. Missing, dormant, unknown, model-serialized, stale, wrong-user, and mismatched grants fail closed. The independent reviewer remains offline.

In the preceding package, Computer Use observed the default-off toggle plus exact worker-only, reviewer-offline, and no-harness-ratification copy. No toggle escalation, confirmation, enrollment, activation, prompt, process, mutation, legacy execution, or EasyBusiness action occurred. [That prior-package 1160×768 screenshot](../screenshots/packaged-loopforge-network-authority-default-off-20260815T230946Z.jpeg) has SHA-256 `6ab38b1acbd7bb8752ef05e42a1a4e926ebd214b5ab3e85f83dc94cdf0a3790b`. Details are in [Native Worker-Network Authority Authoring](NATIVE_NETWORK_AUTHORITY_AUTHORING_IMPLEMENTATION.md).

## Provider native resource boundary and diagnostics

Current provider launch receipts are schema 2 and bind exact native ceilings of one process and 16,777,216 bytes per output file. The runtime rejects caller limits, injects only the compiler-owned limits after executable/environment/sandbox authorization, and revalidates the final transport. The real V2 provider fixture attempts to spawn a child and completes only when native process-count enforcement denies it. Missing or broadened limits fail before launch. Details are in [Provider Native Resource Boundary](PROVIDER_NATIVE_RESOURCE_BOUNDARY_IMPLEMENTATION.md).

The provider compiler now also rejects every environment policy except `minimalKernelAllowlist` at readiness, direct authorization, receipt replay, and lower runtime preflight. Runtime preflight happens before immutable prompt issuance, and the adversarial filesystem test proves zero prompt artifacts for a rejected declared environment. Details are in [Provider Environment Pre-Prompt Veto Hardening](PROVIDER_ENVIRONMENT_PREPROMPT_VETO_HARDENING.md).

The prior-package unlocked diagnostics still demonstrate the provider compiler's fail-closed projection before native activation. The retained ready Workspace Only run showed two mutation-preparation blockers plus two distinct historical provider-profile constraints: the selected executable was not a ratified LoopForge Provider Harness V2, and remote execution lacked the required enabled network policy plus `kernel.network-access` grant. Computer Use retained [the prior-package 860×760 diagnostics screenshot](../screenshots/packaged-loopforge-provider-resource-boundary-20260815T223700Z.png), SHA-256 `d164fd0e327c44352c3c51500e37b0e583b92390a3d63e3fc85d38304d06136a`. It is not attributed to the current snapshot. No activation or provider action was attempted; the app quit and zero exact packaged processes remained.

## Native read-only activation

The Main Graph independent reviewer now truthfully exposes only Read Only. The Node Loop worker exposes Read Only, Workspace Only, and Full Access while retaining Workspace Only as the default. The exact package selected Read Only for the worker, confirmed no writable paths and a 0-file/0-byte mutation ceiling, enrolled `native-run-48b4997c-4d31-4c02-909f-f3d30dd71b70` at sequence 1, and displayed an enabled explicit activation control.

Activation advanced the exact run to epoch `native-dea35366-1b45-4d0c-9ccd-53f18a3cd3ae-epoch`, sequence 6, phase `executing`, with `Mutation Δ 0`, `verification Δ 1`, external effects 0, and failures 0. The native receipt stated no legacy task or Graph worker was created and provider launch remained separately receipt-gated. The preceding UI package demonstrated that quit/relaunch could leave the run durably executing even though no ready activation capability was reconstructed. That observation became the defect receipt for the stop repair. In the current source and package, receipt-proven stop quiescence atomically interrupts an unfinished active attempt, replays to stopped, and prevents ready-authority reconstruction. Normal quit now preflights every retained native session before changing any session, executes an unchanged exact cleanup plan, recovers bound graceful processes by PID/start identity, journals every release, and requires an empty remaining plan before stopped quiescence. After a full app relaunch, exact `executing` and `stopRequested` journals now regain only this cleanup ownership; no productive execution proof, provider, mutation, review, retry, or completion authority is reconstructed. A mismatch remains a retained quit blocker. Unbound or otherwise ambiguous ownership remains retained and cancels quit. Automated runtime and application-level coverage proves the exact lifecycle and generic process cleanup paths; unlocked UI inspection and UI quit passed on the preceding exact package. The dedicated test launched only its synthetic productive provider fixture; UI inspection launched no provider, verifier, worker, legacy execution, or canonical-workspace mutation.

Crash recovery additionally proves that an exact retained `stopRequested`
transaction with no drain frame resumes by appending the missing drain without
replaying stop, then reaches receipt-proven quiescence.

The dedicated application-level live production proof launches a ratified productive provider and proves its PID live. The full-app crash proof then creates a new AppModel with no productive-session handoff: startup reconstructs only cleanup authority, reattaches the exact PID/start identity, terminates it, journals release commands under the distinct `native-crash-recovery-*` namespace, interrupts the attempt, and reaches stopped quiescence. Exact empty and missing-drain crash windows do the same, while stale, ambiguous, and generic join-only ownership remains retained without journal advance. Native process launch rejects join-only release policy, so it cannot manufacture an unrecoverable live process. The companion postimage proof enters through a typed production controller and quit cleanup terminates fail-red without minting a verdict or verification batch. Details are in [Application Crash Reconciliation](APPLICATION_CRASH_RECONCILIATION_IMPLEMENTATION.md), [Production Postimage-Verifier Controller Composition](PRODUCTION_POSTIMAGE_VERIFIER_CONTROLLER_COMPOSITION_IMPLEMENTATION.md), [Live Production Session Application Quit](LIVE_PRODUCTION_SESSION_APPLICATION_QUIT_IMPLEMENTATION.md), [Live Postimage Verifier Application Quit](LIVE_POSTIMAGE_VERIFIER_APPLICATION_QUIT_IMPLEMENTATION.md), [Native Read-Only Authoring and Activation](NATIVE_READ_ONLY_AUTHORING_AND_ACTIVATION_IMPLEMENTATION.md), [Native Termination and Quiescence Hardening](NATIVE_TERMINATION_QUIESCENCE_HARDENING.md), [Native Runtime Cleanup Execution](NATIVE_RUNTIME_CLEANUP_EXECUTION.md), and [Application Relaunch Cleanup Ownership](APPLICATION_RELAUNCH_CLEANUP_OWNERSHIP_IMPLEMENTATION.md).

The final pre-effect mutation boundary is now production-controller composed.
Ordinary-macOS Release resolves no trusted physical resident-memory readiness,
so the coordinator journals one exact contract/transaction/preflight/recipe-set
veto while integration remains `rollbackPrepared`. Collision, retained-receipt
substitution, cross-wired capability, and inner-request capability smuggling
all reject. Journal reopen and unchanged retry recover the exact receipt and
transaction with no workspace lease, apply intent, outbox entry, or canonical
write. An exact DEBUG capability passed through the same production resolver
prepares and exactly replays the already bounded apply. Details are in
[Production Mutation-Preparation Controller and Durable Pre-Effect Veto](PRODUCTION_MUTATION_PREPARATION_CONTROLLER_IMPLEMENTATION.md).

Prior-package screenshots retained for the preceding read-only activation proof:

- [Read-only contract](../screenshots/packaged-loopforge-read-only-contract-20260815T212900Z.png)
- [Ready and activatable](../screenshots/packaged-loopforge-read-only-ready-and-activatable-20260815T212900Z.png)
- [Activated and executing](../screenshots/packaged-loopforge-read-only-activated-executing-20260815T212900Z.png)
- [Executing after relaunch](../screenshots/packaged-loopforge-executing-run-not-recovered-as-ready-20260815T212900Z.png)

## Current native baseline/candidate matrix

The exact package was captured through the real native UI in four matched
standard/accessibility and expanded/narrow cells. The initial independent
review vetoed redundant chrome, task-title demotion, dense metadata, and
clipped graph nodes at confidence 0.97. After the first bounded correction, a
second independent review retained a confidence-0.97 H-04 veto because three
cells bisected lower graph cards. The final whole-row, top-aligned graph
viewport exposes explicit `Next levels` and `More nodes below` continuation
boundaries. A third independent review passed H-04, H-05, H-06, H-07, and H-09
at confidence 0.94 with no required changes. Both veto receipts remain
preserved. The display was restored to the user's original 1168×755 scaled
setting and the application was quit with no residual package process.

See [Native Baseline/Candidate Matrix Verification](NATIVE_BASELINE_CANDIDATE_MATRIX_VERIFICATION.md),
[the machine-readable scorecard](NATIVE_BASELINE_CANDIDATE_MATRIX_SCORECARD.json),
and [the final contact sheet](../screenshots/loopforge-native-matrix-whole-row-20260816T100000Z-contact-sheet.jpg).

## Boundary

Native read-only authoring, explicit activation, receipt-proven stop closure, exact bound-process execution and recovery of nonempty cleanup plans, cleanup-only full-app relaunch ownership, exact crash auto-interruption without productive-authority reconstruction, fail-closed retention of ambiguous ownership, the dedicated live-provider test path, typed production postimage-verifier veto/live-launch composition, production mutation-preparation veto/exact-authority composition, exact workspace-mutation live-handle-aware normal-quit join, truthful terminal strategy-history presentation, current packaged architecture-veto inspection/quit, current direct and mounted startup, worker-network authority authoring, provider no-child/output-file ceilings, the V2 transport-veto package spine, productive-mode enforcement, environment-policy enforcement before prompt issuance, shared resource/release-policy compatibility, explicit ordinary-macOS in-process containment-strategy retirement, explicit ordinary-app productive-provider architecture-scope retirement, and the current four-cell native baseline/candidate matrix are closed. The current product retains both typed vetoes; mutation-backed execution requires a separately scoped privileged or virtualized isolation product. A rebuild from an exact clean committed revision, final clean-package verification, commit, and push remain required. Final release is false. EasyBusiness remained stopped and read-only at observed HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04`.
