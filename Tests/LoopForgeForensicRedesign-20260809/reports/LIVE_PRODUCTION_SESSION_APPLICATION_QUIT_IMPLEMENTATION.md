# Live Production Session Application Quit

Status: **passed for an exact live productive provider process; companion live postimage-verifier quit is now separately passed**

Recorded: `2026-08-16T03:20:51Z`

Companion verifier proof updated: `2026-08-16T04:05:14Z`

## Closed evidence gap

The lower process runtime already proved exact process-group cleanup, and the
application model already proved empty-session termination and cleanup-only
relaunch recovery. Neither proof placed a genuinely live productive provider
inside a retained `KernelProductionExecutionSession` and then exercised the
real `AppModel.prepareKernelSessionsForApplicationTermination()` boundary.

The new end-to-end test ratifies a domain-neutral local worker profile using
the V2 provider protocol, creates the exact pre-apply candidate isolation,
activates the production session, prepares the native invocation, and launches
the real `KernelProcessFixture` through `KernelProductionExecutionSession`.
The fixture holds only the exact synthetic model
`fixture-live-termination-model` open for 30 seconds. The test proves the PID
is alive before application termination and never calls the normal provider
completion path.

## Application-level result

The already-activated session is retained by a DEBUG-only AppModel test seam;
the symbol is absent from the Release executable. The production AppModel quit
coordinator then:

- preflights the exact nonempty cleanup plan;
- journals stop and runtime drain;
- terminates the exact PID/process group;
- records a released runtime outcome with managed-process termination
  provenance bound to that PID;
- clears the supervisor and journal live lease;
- marks the active attempt `interrupted`;
- reaches `stopped` and receipt-proven quiescence; and
- removes the retained application session only after those facts hold.

The provider is absent after quit with `ESRCH`; no completion proposal,
candidate capture, mutation, review, retry, or completion authority is used.

## Verification and package binding

- Dedicated focused proof: 1 test, 0 failures in 1.127 seconds.
- Package-owned repeat of the same proof: passed in 1.108 seconds.
- Complete package-owned suite: 860 executed, 8 intentionally gated skips,
  0 failures in 74.652 test seconds (74.703 wall).
- Real Codex child bridge: passed in 12.037 seconds.
- Dirty-source snapshot:
  `7ca002e7a5fedee480c52b26b77f6c6a84d0b25cd7169538f165cada4cb3f19d`.
- Signed app executable:
  `d5c69f39b31d62e6053ef02b591f728fdfe26a91380432236b28ba61835f8593`,
  CDHash `17f174f2d962cb77111c33d5697c998f3afa3b02`.
- Deep-strict signing, source/test manifest binding, checksum manifest, ZIP,
  DMG, all-three-Mach-O mounted-DMG byte identity, direct and mounted exact
  startup, detach, and zero residual package/provider processes passed.

Computer Use inspected the exact signed package while unlocked and retained
[that package's 1159×768 screenshot](../screenshots/packaged-loopforge-current-live-production-quit-package-20260816T031933Z.jpeg),
SHA-256 `fa2301cb2f1b289a4ded75ce063fa3826454e74b9c82a5b1766fa1b06fb33b12`.
The historical EasyBusiness task remained visibly stopped and was not opened,
resumed, or modified. A real UI quit followed and left zero exact packaged
processes.

## Boundary

This closes the dedicated live-production-session normal-quit gap. The
companion verifier gap is closed by
[Live Postimage Verifier Application Quit](LIVE_POSTIMAGE_VERIFIER_APPLICATION_QUIT_IMPLEMENTATION.md).
Join-only recovery without a retained handle, productive provider backend ratification/cutover, native
mutation preparation or retained vetoes, the complete native visual matrix,
clean-commit rebuild, commit, and push remain pending. Final release is false.
