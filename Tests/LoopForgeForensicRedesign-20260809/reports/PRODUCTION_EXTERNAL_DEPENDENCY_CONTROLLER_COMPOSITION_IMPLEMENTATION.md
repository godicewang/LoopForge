# Production External-Dependency Controller Composition

Status: **the production execution session invokes the exact activation, containment, launch, completion, and observation boundaries; ordinary-macOS Release retains its pre-admission veto and native app start cutover remains pending**

Recorded: `2026-08-15T15:05:54Z`

## Result

`KernelProductionExecutionSession.observeExternalDependency` is now the single
production-controller method for one ratified external dependency. The request
contains only opaque journal identities, the explicitly authorized observer and
executable path, and private output basenames. The session activates the exact
contract probe, resolves resident-memory containment immediately before
admission, and either returns the durable launch veto or runs the complete
native launch-to-observation composition.

The resident-memory resolver accepts the live activation receipt and may return
only the non-Codable activation-exact enforcement capability. No Release issuer
exists on ordinary macOS, so the default resolver is nil. The production-path
test therefore journaled `residentMemoryEnforcementUnavailable` and created no
admission, lease, sandbox, process, runtime launch, result, or observation.

With the DEBUG-only capability, the same production session used the real
sandbox gate and raw-Darwin fixture to consume the immutable canonical request,
emit the canonical result, naturally release, parse, map, issue the release-
bound result, and append the journal-owned observation. The method returns only
the completed durable authority, not a partial live process handle. An exact
controller retry resolved the retained launch and replayed the same completion;
a substituted launch receipt ID rejected with no journal advance.

`JournaledProcessRuntime` now treats the exact live readiness capability as the
resident-memory proof for external observers. Its internal revalidation already
binds that capability to the activation, journal transaction, request artifact,
active attempt, observer actor, and absence of prior veto/result; it no longer
requires a duplicate construction-time copy that cannot exist before activation.
The independent postimage-verifier path retains its separate construction-time
containment requirement unchanged.

## Verification

- the two new production-session tests passed **2/0/0** in **0.410 seconds**;
- the complete production-enrollment suite passed **40 tests** with **0
  failures** in **5.070 seconds**;
- the exact source suite passed **811 tests**, with **8 intentional skips** and
  **0 failures**, in **60.075 test seconds**;
- the package-owned suite passed **811/8/0** in **59.388 test seconds**;
- the real Codex child/Responses bridge passed in **16.571 seconds**;
- non-DEBUG arm64 Release built in **101.53 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, cleanup, and thermal checks passed;
- source snapshot:
  `9a749dd8152f96b495ca222b1bfa172831220603af586e174908dd130136ade5`;
- packaged LoopForge SHA-256:
  `2422ba105e343a813ae8c5e30492b6711104a1b5ba4ea86582c8e58eb72a8663`.

Two incorrect packaging shell invocations failed before work because the
zsh-only script is intentionally non-executable and uses zsh parameter
expansion. The exact `zsh` invocation then passed. Both failed invocations count
zero in the strict ledger.

## Boundary

This closes the production execution-session composition gap, not the native
app start/cutover gap. `AppModel` still enrolls and reports readiness without
constructing an execution session, and ordinary-macOS Release has no trusted
physical resident-memory issuer. Consequently no production observer ran and
the deterministic veto remains the correct Release result.

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its newline-delimited `-uall`
status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted containment or the retained veto, native
app execution cutover, final-completion invocation, legacy retirement, unlocked
native screenshots, a clean-commit rebuild, commit, and push remain required.
