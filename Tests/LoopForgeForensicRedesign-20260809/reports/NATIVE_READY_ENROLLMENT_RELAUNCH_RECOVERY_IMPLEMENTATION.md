# Native Ready-Enrollment Relaunch Recovery

Status: **implemented, source/package verified, and proven through the exact packaged native UI; final release remains false**

Recorded: `2026-08-15T21:19:35Z`

## Defect

Startup recovery already replayed a durable ready `KernelRunProjection`, but `AppModel.latestKernelEnrollmentReceipt` remained absent after relaunch. The diagnostics surface could display the recovered run while withholding the only retained enrollment capability used by the explicit native activation control. A second authority gap allowed a protected run to appear ready without the live, non-Codable design-baseline authority that activation would later require.

## Repair

`KernelProductionExecutionCoordinator.recoverReadyEnrollment(runID:)` now reconstructs only an inert enrollment receipt from exact durable evidence:

- one ratified registry record for the requested run;
- the original `runCreated` journal transaction, exact command/frame identities, sequence, event count, and current journal head;
- a ready reducer projection with no admitted node or attempt;
- exact contract, run, workspace, actor, registration, and verifier-staging identities.

Recovery rejects executing or changed runs. It does not recreate provider, process, mutation, retry, verification-staging, or protected-design-baseline capability.

`AppModel` now waits for the startup recovery report, recovers only attention-free ready runs, deterministically selects the newest durable registration, restores the enrollment receipt, and recomputes readiness. The protected-design path has a new `designBaselineAuthorityMissing` blocker. It is removed only when the live `AuthorizedKernelDesignBaseline` exactly matches the run, ratification receipt, enrollment journal frame, and contract.

## Adversarial coverage

- relaunch recovery chooses the newest ready read-only enrollment and can explicitly activate it;
- an executing run cannot reconstruct a ready enrollment capability;
- a protected run is blocked without its exact live design authority and unblocked only by the matching live capability;
- recovery does not synthesize verifier staging or any execution/mutation capability.

The focused native enrollment suite passed 10 tests with zero failures in 11.354 seconds. The focused design-baseline authority test passed 1/0 in 0.027 seconds. The full source suite passed **837 tests, 8 explicit skips, 0 failures** in 65.853 test seconds (65.902 wall); its real Codex bridge passed in 12.792 seconds.

Two failed focused invocations count zero: the first used an insufficient yield-only wait, and the second exposed an invalid assumption that the ratifying user actor and enrollment actor must be identical. The final implementation retains both distinct, nonempty actor lineages and exact durable registry/journal proof.

## Package proof

Release packaging and smoke passed for dirty-source snapshot `c974a26156aaf25a645c2a033433c25249e54a77c26791a413b8c5c7786758b8`. The package-owned suite passed **837/8/0** in 61.558 test seconds (61.607 wall), with the real Codex bridge passing in 9.060 seconds. The app and gate passed deep strict ad-hoc signing; ZIP, DMG, checksum-manifest, embedded source/test binding, exact packaged-Mach-O startup, cleanup, and Release absence of `startRetiredExecutionForTesting` passed.

## Native relaunch proof

Computer Use operated `/Users/godice/Coding/LoopForge/dist/LoopForge.app` directly. It selected the LoopForge workspace, bound the exact packaged `KernelSandboxGate` verifier (`85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`), confirmed a source-bound Journaled Auto Graph contract, and enrolled native run `native-run-c2070190-a24a-42bf-a9f5-fee696aea42c` at journal sequence 1.

Because the public composer intentionally offers Workspace Only or Full Access—not internal graph-node Read Only—the run correctly remained ready with two mutation-authority blockers and a disabled `Activate Native Attempt` control. After a real quit and exact-package relaunch, the same run ID, sequence, ready phase, blocker set, and activation control were present. The before/after JPEGs are byte-identical (`d2b154efb5972459a6ac0459a0156e97f80e7251cd6e59977be9c5b4b9c5d7e3`), which proves the recovered native projection and control state did not drift.

- [Before relaunch](../screenshots/packaged-loopforge-ready-run-before-relaunch-20260815T205200Z.jpeg)
- [After relaunch](../screenshots/packaged-loopforge-recovered-ready-run-after-relaunch-20260815T205200Z.jpeg)

The native read-only activation path is covered by the adversarial XCTest because Read Only is deliberately not a project-wide picker option. The packaged UI proof therefore verifies durable restart recovery and fail-closed mutation readiness, not a production worker launch.

## Remaining boundary

The complete native trait/window/baseline/candidate matrix, trusted Release containment or retained vetoes, a packaged/ratified V2 provider harness with exact network authority, mutation preparation or retained vetoes, a clean-commit rebuild, commit, and push remain pending. Final release is false. EasyBusiness remained read-only evidence throughout.
