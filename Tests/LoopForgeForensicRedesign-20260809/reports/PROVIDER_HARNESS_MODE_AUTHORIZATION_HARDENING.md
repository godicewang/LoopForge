# Provider Harness Mode Authorization Hardening

Status: **implemented and package verified; transport-only profiles cannot authorize or replay productive invocations**

Recorded: `2026-08-16T00:55:44Z`

## Defect

The Provider Harness V2 readiness projection correctly named `providerHarnessProductiveBackendUnavailable` for `transportVetoOnly`, but the lower-level invocation authorizer checked only the V2 protocol label. A caller that bypassed the projection could therefore mint an invocation receipt for the deliberately non-productive harness. Replay validation also failed to require productive mode.

This did not make the packaged harness productive: the executable itself still emitted only a canonical blocked proposal. It was nevertheless an authority-layer contradiction because readiness and authorization disagreed about the same exact profile.

## Fix

`KernelProviderInvocationCompiler.validateExecution` now requires both `loopForgeProviderHarnessV2` and `providerHarnessMode == productive`. A transport-veto or unavailable mode throws the explicit `providerHarnessProductiveBackendUnavailable` authorization error before prompt authorization can cross the provider boundary.

`receiptIsValid` independently requires productive mode, so a decoded or relabeled receipt cannot recover launch evidence merely because its executable retains the V2 transport label. Productive fixtures remain explicit; no default or historical decode is promoted.

## Verification

- focused provider compiler: 18 tests, zero failures;
- provider/runtime/sandbox/enrollment boundary: 94 tests, zero failures in 9.563 seconds;
- package-owned complete suite after the environment-policy extension: 850 tests, 8 explicit skips, zero failures in 62.442 test seconds (62.491 wall);
- real Codex child bridge: 8.671 seconds;
- strict deep signing, exact source/test manifest binding, harness manifest/self-test identity, ZIP, DMG, checksums, packaged executable startup, cleanup, and zero residual packaged processes passed.

The rebuilt package binds dirty-source snapshot `0bba91621c094254b083a07401e9e45c4157e1a29626da6d3a67a28b708fd025`, package-log SHA-256 `099d487bbef9710c9692d845fd166af91e234077bbb4c37e152a568f56bbd618`, executable SHA-256 `1407e544dd40270660deb237e3b6d43610ef3a6dc28ccc9e182cb1bf93757f83`, and app CDHash `f45679b466871096ae1983551c596c42bc7d0888`. The subsequent [environment-policy repair](PROVIDER_ENVIRONMENT_PREPROMPT_VETO_HARDENING.md) extends the same fail-closed agreement through readiness, authorization, replay, and pre-prompt runtime ordering.

The Mac locked before a new unlocked walkthrough could be captured. The immediately preceding screenshot remains prior-package evidence only; blocked lock time counts zero. Productive backend ratification, current-package unlocked native UI verification, the full native matrix, clean-commit rebuild, commit, and push remain pending. Final release is false.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
