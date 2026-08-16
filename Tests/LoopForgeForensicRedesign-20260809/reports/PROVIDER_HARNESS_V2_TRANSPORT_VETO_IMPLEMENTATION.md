# Provider Harness V2 Transport-Veto Spine

Status: **implemented, signed package verified, and intentionally non-productive; productive provider execution and final release remain false**

Recorded: `2026-08-16T00:55:44Z`

## Defect closed

The native contract previously retained the SHA-256 of an installed provider executable while truthfully marking its provider protocol unavailable. That was safe, but it left no separately packaged executable implementing LoopForge's fixed-descriptor V2 boundary. Relabeling the Codex CLI would have been false: it does not implement LoopForge's canonical context, prompt, credential, or JSONL-result protocol.

## Implementation

`LoopForgeProviderHarness` is now a separate executable product and signed nested Mach-O. It accepts only the compiler's exact ordered 16-flag V2 argument vector; reads one canonical, newline-terminated invocation context from FD 196; reads exactly the declared prompt bytes from stdin and verifies SHA-256 plus EOF; optionally consumes one length-prefixed credential from FD 197 and zeroizes it; and emits only canonical sorted-key JSON.

The current executable deliberately has no productive provider backend and cannot spawn or mutate. A valid invocation emits one terminal proposal with `proposedDisposition: blocked`; malformed arguments, context, prompt, or credential data exit nonzero and emit no proposal. Its self-test declares `operationalMode: transport-veto-only` and an empty `productiveProviderBackends` array.

The package writes a separate exact manifest containing protocol version, final signed executable SHA-256 and byte count, operational mode, empty productive-backend list, and canonical self-test digest. The native loader accepts only one owner-controlled regular file with one link, no symlink, no group/world write, exact manifest keys, exact signed-byte identity, and the independently compiled self-test digest. Native authoring may therefore retain V2 transport identity, but readiness adds `providerHarnessProductiveBackendUnavailable`; transport ratification cannot become productive readiness.

Nested helpers are signed before their hashes are recorded. The enclosing application is then signed without recursively rewriting those bytes. The independent smoke gate caught the earlier incorrect order because deep signing changed the harness hash after manifest creation.

## Verification

The initial focused provider suite passed **24 tests with zero failures**. After removing the unsafe source-construction default, the broader provider/runtime/sandbox/enrollment selection passed **100 tests with zero failures**. Coverage includes exact self-test identity, manifest digest/self-test tamper rejection, symlink rejection, productive-mode relabel rejection, real FD 196 transport through `open`/`dup2`/`execv`, canonical blocked output, prompt-digest rejection with zero stdout, and the explicit non-productive readiness blocker.

After the mode and environment-authorization hardening, the exact final package-owned run passed **850 tests, 8 explicit skips, and 0 failures** in 62.442 test seconds (62.491 wall); its real Codex bridge passed in 8.671 seconds. Failed descriptor-wrapper, post-sign hash-order, direct-script permission, and transient test invocations were repaired or independently rerun and count zero.

## Exact package

The signed package binds Git revision `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0`, dirty-source snapshot `0bba91621c094254b083a07401e9e45c4157e1a29626da6d3a67a28b708fd025`, and package-log digest `099d487bbef9710c9692d845fd166af91e234077bbb4c37e152a568f56bbd618`.

The final signed harness is 145,952 bytes with SHA-256 `d4de4d8b38a59186f8f184ddf1c54ea7f63bd5084d18df0bb37fa7edd19154ac`, CDHash `48feeb5fe9cc97be5b540394b5875e1042754c22`, and self-test SHA-256 `5d51b54ded7050c79bce97086321ba73743de97e75476cfdebddd45b26f7b26b`. The app CDHash is `f45679b466871096ae1983551c596c42bc7d0888`. Strict deep verification, manifest identity, every release checksum, ZIP, DMG, canonical self-test, bounded app startup, and zero residual packaged processes passed.

## Boundary

This closes only the separately packaged V2 descriptor/credential/canonical-result transport spine. There is no productive Codex, local, or API backend in the harness, so no provider prompt can enter productive launch readiness and no successful worker result can be proposed. Readiness, direct authorization, and decoded-receipt replay now all independently require productive mode; see [Provider Harness Mode Authorization Hardening](PROVIDER_HARNESS_MODE_AUTHORIZATION_HARDENING.md). Unsupported environment policy additionally rejects at readiness, direct authorization, replay, and lower runtime preflight before any immutable prompt artifact; see [Provider Environment Pre-Prompt Veto Hardening](PROVIDER_ENVIRONMENT_PREPROMPT_VETO_HARDENING.md). The current-package unlocked walkthrough was blocked by the macOS lock, so the preceding disabled-activation screenshot remains prior-package evidence only. Productive backend ratification, native launch cutover, trusted Release containment or retained vetoes, mutation preparation or retained vetoes, current-package unlocked UI, the full native matrix, clean-commit rebuild, commit, and push remain pending. Final release is false.

EasyBusiness remained read-only at branch `codex/USA_Version`, HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
