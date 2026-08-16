# Live Postimage Verifier Application Quit

Status: **passed for an exact live postimage-verifier process; final release remains pending**

Recorded: `2026-08-16T04:47:31Z`

## Closed evidence gap

The application-termination path already proved exact cleanup for a productive
provider, while the lower runtime had a fail-red postimage-verifier cleanup
implementation. The missing composition proof was a genuinely live verifier
launched by the production session and then terminated through
`AppModel.prepareKernelSessionsForApplicationTermination()`.

The new end-to-end test runs a real productive provider to natural completion,
captures its exact candidate, advances the retained production journal to an
applied-but-unverified integration transaction, stages and materializes the
candidate postimage, and launches `KernelProcessFixture` as the exact
postimage verifier. The fixture emits a syntactically accepted result and then
sleeps for 30 seconds. The test proves its PID is alive before quit.

## Authority and lifecycle repair

Production execution and verifier verdict authority intentionally use distinct
actors. The runtime previously assumed they must be identical even during
application-owned cleanup. That assumption was valid for productive verifier
completion but prevented the application session from releasing a verifier it
had actually admitted, bound, and retained.

Cleanup now resolves the exact verifier actor from the journaled launch and
uses it only to revalidate activation/launch ownership. Productive completion
still requires the runtime's verifier actor before any result can become
verification authority. Application termination therefore gains no verdict
power: it can terminate and release the exact owned process, but its retained
output is permanently fail-red.

The DEBUG-only launch helper has now been removed. The test supplies only an
exact activation-bound resident-memory capability to the same typed production
controller used by Release. That controller also proves the ordinary-macOS
nil-capability veto and cross-wired-authority rejection before the live launch.
Journal activation, admission, native binding, PID ownership, termination,
containment, and release remain in the real production session and runtime.

## Result

- The verifier PID is live before application quit and absent with `ESRCH`
  afterward.
- The process group receives managed termination bound to the exact PID.
- The release is journaled with `runtimeCleanupTermination` containment.
- No natural-exit receipt or postimage result authority is minted.
- A failure digest is retained and no postimage verification batch appears.
- Runtime live leases and failed releases are empty.
- The run reaches `stopped` and receipt-proven quiescence before AppModel
  removes the retained session.

## Verification and package binding

- Focused proof: 1 test, 0 failures.
- Package-owned repeat: passed in 1.346 seconds.
- Complete package-owned suite: 861 executed, 8 intentionally gated skips,
  0 failures in 81.525 test seconds (81.575 wall).
- Real Codex child bridge: passed in 15.438 seconds.
- Dirty-source snapshot:
  `059dba47ad44d1ead84edbf4094fae8d7040084d2d2337cf00c616a00039f414`.
- Signed executable:
  `3b657f94e3be6bb157debc71ef9e52ba4c534c609c82212b35a1168f30fa68ed`,
  CDHash `73e0af7d1f9885d13b0927ae2f89ee164cac5f4b`.
- Deep-strict signing, source/test manifest binding, checksum validation, ZIP,
  DMG verification, all-three-Mach-O mounted-DMG byte identity, direct and
  mounted exact startup, detach, and zero residual package/provider/verifier
  processes passed.

This change does not alter visible UI. The prior exact-package native screenshot
remains historical evidence and is not relabeled as the current package.
EasyBusiness remained read-only on branch `codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status digest
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Boundary

This closes the retained-session live postimage-verifier normal-quit gap.
The production resident-memory veto is now retained and surfaced by the typed
session controller. Join-only recovery without a retained handle, a trusted
Release containment issuer, productive provider backend ratification/cutover,
native mutation preparation, the complete native visual matrix, clean-commit
rebuild, commit, and push remain pending. Final release is false.
