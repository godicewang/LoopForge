# Legacy Single/Parallel Execution Retirement

Status: **production execution ingress retired and verified; final release remains false**

Recorded: `2026-08-15T20:44:36Z`

## Boundary closed

The earlier cutover retired historical Auto Graph execution but left two controller-authoring surfaces able to reach the legacy Single Loop and Parallel Candidates engines. That was an authority gap: an old serialized mode or a UI/controller call could still select a non-journaled execution path even though new work was supposed to enter only through the ratified journal kernel.

LoopForge now treats every `LoopExecutionMode` value as historical decoding evidence only. Production `LoopController.start(taskID:)`, candidate selection, application startup recovery, explicit resume, and all task-start helpers route to one idempotent fail-closed retirement boundary. The boundary records a stable migration-required stage and blocker while creating no timer, agent, process, mutation, integration, candidate selection, or retry authority. The old execution implementation remains reachable only from a `#if DEBUG` characterization entry point and that entry point is absent from the Release executable.

New task authoring exposes one selected mode: `Journaled Auto Graph`. Attempts to author Single Loop or Parallel Candidates are rejected and reset to Auto Graph. Historical task and candidate views remain inspectable evidence, but offer neither Resume nor Keep This Result controls.

## Changed production surfaces

- `Models.swift` defines the common legacy-task retirement policy and keeps the old enum only for decoding and evidence labels.
- `LoopController.swift` removes the production legacy bypass, routes all starts and candidate selection to the blocker, and compiles the characterization implementation only in DEBUG.
- `AppModel.swift` defaults and resets authoring to Auto Graph, blocks every historical mode on launch/resume, and removes the legacy task-creation/start implementation.
- `Views.swift` removes Single/Parallel authoring controls and historical resume/selection actions while retaining explicit migration-required evidence.
- Lifecycle and task-store tests cover all three historical modes, idempotency, unchanged sentinel state, zero timer/process authority, rejected Single/Parallel authoring, and startup recovery.

## Verification receipts

The focused controller suite passed 7/0. The focused task-store suite passed 20/0. The complete source suite passed 835 tests with 8 explicit environment-gated skips and zero failures in 57.354 test seconds. The package-owned suite passed 835/8/0 in 60.796 seconds, including the real Codex bridge in 11.346 seconds. A non-DEBUG Release build, exact-source packaging, deep strict ad-hoc signing, hashes, ZIP and DMG validation, bounded Mach-O startup, cleanup, and smoke verification passed for source snapshot `8372af66fb258d45f50e42c8d00daa76bec261bcb4df2cc141232b16891c2b9b`.

`nm` and `strings` found no `startRetiredExecutionForTesting` symbol or string in the exact packaged Release executable. The packaged app executable SHA-256 is `99af7c3e1ba287b6e607598cdc04a5b689f54df3e1210a0d2191cc872cd83cab` and CDHash is `6feaa681be4bc5461700fa82d82ef0545e8db992`.

## Native evidence

Computer Use inspected the exact package through the real unlocked macOS UI. A historical EasyBusiness task displayed `Legacy Auto Graph Loop preserved · migration required` with no Resume control. A fresh composer displayed `Contract rigor`, one selected `Journaled Auto Graph` path, dual Workspace Only profiles, and the explicit statement that Single Loop and Parallel Candidates remain read-only historical evidence. No task was created and the app quit with zero packaged processes.

- `../screenshots/packaged-loopforge-journaled-auto-graph-retirement-current-20260815T203935Z.png`, SHA-256 `49c63b78891f7288ed4e110501846f483510bd8514c1a933af07bf0975562b53`
- `../screenshots/packaged-loopforge-retired-historical-task-current-20260815T204020Z.png`, SHA-256 `f66835153120e363d2b65398d1b04ddc291ba6537eed8f78f57b6cff4b049bb3`

## Remaining boundary

This closes legacy Single/Parallel execution ingress, not the entire release. Trusted Release containment or its retained launch veto, the separately packaged and ratified provider harness and network authority, mutation authority or retained vetoes, the complete native trait/window/baseline/candidate matrix, a rebuild from an exact clean commit, commit, and push remain pending. Final release is false. EasyBusiness was read only and was not resumed or mutated.
