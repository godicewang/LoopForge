# Native Provider Prompt Authority and Protocol Gate

Status: **exact journal-derived provider input is present; direct provider executables remain launch-ineligible until a ratified LoopForge harness exists**

Recorded: `2026-08-15T17:05:00Z`

## Result

`KernelProductionExecutionSession` no longer accepts arbitrary productive
provider prompt bytes. Its new `prepareNativeProviderInvocation` boundary
accepts only a fresh canonical UUID. It revalidates the unchanged executing
journal, active attempt, node, strategy, contract, plan, admission, execution
profile, activation frame, empty launch set, and empty live-lease set before it
can create one immutable prompt artifact.

The prompt is canonical sorted-key JSON followed by one LF. It contains the
exact ratified contract, plan, admission, worker profile, active workspace,
journal sequence and frame, request nonce, and code-owned canonical-JSONL
result protocol. The session permits exactly one preparation per attempt.
Callers cannot add prose, paths, capabilities, network, plugins, budgets,
strategy, output syntax, or hidden fan-out.

A newly typed `KernelProviderProtocol` now distinguishes evidence for an
installed direct provider executable from an executable that actually
implements LoopForge's descriptor, fixed-FD credential, immutable-prompt, and
canonical-result harness. Recovered and app-authored direct executable
profiles default to `unavailable`. The invocation compiler now requires
`loopForgeProviderHarnessV2` before prompt creation, so the currently selected
Codex executable cannot be fed incompatible harness argv or leave an orphaned
prompt. Native provider launch therefore remains honestly blocked rather than
being reported as ready.

V2 also closes the post-compilation identity cycle: the kernel stages canonical
invocation digest and nonce context on fixed descriptor 196 before native
spawn, binds that transport into the provider launch receipt, and revalidates
it before strict output parsing. See
`KERNEL_PROVIDER_INVOCATION_CONTEXT_TRANSPORT_IMPLEMENTATION.md` for the exact
transport and adversarial proof. Historical V1 remains decodable but is invalid
for a current launch.

## Verification

- the focused provider, sandbox, production-session, and runtime set passed
  **59/0** in **5.417 test seconds**;
- the V2 transport-focused set passed **14/0** in **1.047 test seconds**, and
  the separate historical-decode test passed **1/0**;
- the exact final package-owned source suite passed **819 tests**, with **8
  intentional skips** and **0 failures**, in **64.873 test seconds**;
- the real Codex child/Responses bridge passed in **19.135 seconds**;
- non-DEBUG arm64 Release built successfully; this packaging invocation did
  not separately time the build;
- source snapshot:
  `bff4173a795286a7b895f053a990692982905f1211e44d655d94b5fe5f059f6f`;
- packaged LoopForge SHA-256:
  `b2e4c9463676fdd8c6151da83d1e64be21d27dc645b64e7fec6ddf70a53e3647`;
- deep-strict signing, ZIP, DMG, checksum manifest, embedded source/test
  binding, exact packaged-Mach-O startup, and zero residual packaged
  processes passed.

## Boundary

The full production launch is still false. Kernel-owned invocation-digest
context transport is now present and real-sandbox tested. A packaged,
independently ratified V2 provider harness and exact network authority are
absent. Exact profile-ratified Keychain credential resolution is now present;
the native app therefore retains
`providerProtocol = unavailable`. Mutation-backed
execution also retains its isolation/preparation vetoes. Legacy Single and
Parallel retirement, current unlocked native screenshots, a clean-commit
rebuild, commit, and push remain pending.

EasyBusiness remained stopped and read only at
`2ae40452e6d8661c46db466c43ea40bba3bfab04`. Its current read-only status
fingerprint was
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`;
this interval attributes no EasyBusiness mutation to LoopForge work.
Final release remains false.
