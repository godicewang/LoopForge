# External-Dependency Native Observation Composition

Status: **the complete native launch-to-observation chain is implemented and DEBUG-proven with exact retry and recovery replay; ordinary-macOS Release containment and production-controller invocation remain pending**

Recorded: `2026-08-15T14:43:49Z`

## Result

`JournaledProcessRuntime.completeExternalDependencyObservation` now composes the
previously separate external-observer boundaries without accepting any caller-
supplied output, timeout, parse, mapping, result, release, or observation fact.
It re-resolves the exact activation, probe, runtime launch, accepted binding,
and live lease from the hash journal, derives the wall deadline from activation
limits and native process start, naturally joins the owned process tree, and
journals release. An exact already-retained release transaction is accepted for
crash recovery; unrelated or ambiguous release history rejects.

The runtime reads stdout and stderr only through descriptor-relative `openat`,
rejects links and non-regular files, rechecks mode, size, device, and inode,
enforces bounded output, and requires empty stderr. It then performs the strict
nonce-bound canonical parse, exact declared native-exit/result mapping,
release-bound result issuance, and journal-owned external-dependency observation
append. The first successful command, same-command retry, and a retry through a
freshly recovered `RunJournal` resolve to the same durable result and
observation without recreating process authority.

A real raw-Darwin fixture consumed the immutable canonical request from stdin,
emitted one canonical sorted result line, exited naturally through the native
sandbox gate, and completed the entire chain. The final journal had the exact
release, result, and observation and retained zero runtime handles, in-doubt
resources, or supervisor leases. A native launch that emitted a noncanonical
marker was rejected at parse and appended no observation.

## Verification

- the exact composition suite passed **4 tests** with **0 failures** in
  **0.462 seconds**;
- the exact minimal-environment regression passed **1/0/0** in **0.605
  seconds** after removing Foundation from the raw fixture;
- the exact source suite passed **809 tests**, with **8 intentional skips** and
  **0 failures**, in **67.141 test seconds**;
- the package-owned suite passed **809/8/0** in **63.748 test seconds**;
- the real Codex child/Responses bridge passed in **20.432 seconds**;
- non-DEBUG arm64 Release built in **96.47 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, cleanup, and thermal checks passed;
- source snapshot:
  `f560dc26e1b074a1cb528ee26de11995ab5447f80926ea744e554303ce64bc15`;
- packaged LoopForge SHA-256:
  `477f037ad0dfe58fce22c1f9d767722b558e9aa2a82f261fc819d717654b8816`.

One full-suite diagnostic failed because importing Foundation in the raw fixture
introduced `__CF_USER_TEXT_ENCODING` into the deliberately exact four-variable
environment. The fixture was corrected to raw Darwin byte parsing, the exact
environment regression and both full suites then passed, and the failed run
counts zero in the strict ledger.

## Boundary

The native proof used the explicit DEBUG-only resident-memory capability.
Production still has no issuer for the required hard physical resident-memory
ceiling on ordinary macOS; the non-DEBUG path therefore retains its deterministic
pre-admission veto and no production observer ran. The new composition method is
not yet invoked by the production controller, and it creates no new Release
containment authority.

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its newline-delimited `-uall`
status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or the retained veto,
production-controller invocation, final-completion invocation, legacy
retirement, unlocked native screenshots, a clean-commit rebuild, commit, and
push remain required.
