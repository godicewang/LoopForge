# Native Source-Revision Capture Policy Authority

Status: **source, Release, package integrity, and targeted unlocked native proof passed**

Recorded: `2026-08-15T18:23:09Z`

## Problem closed

The exact source collector already bound excluded directory names, limits, and a policy digest into every captured revision, displayed the canonical policy during contract review, and repeated the same policy during confirmation-time recapture. Native authoring nevertheless supplied one hard-coded default and exposed no control before capture. A repository containing a generated artifact tree with an internal symlink therefore failed closed, but the user had no safe way to declare that generated tree outside the task's source authority.

## Implementation

- `NativeTaskContractAuthoringRequest` now carries one typed `WorkspaceCandidatePostimageCapturePolicy` instead of independent exclusion and limit fields.
- Native preparation validates the complete policy before opening the workspace. Noncanonical components, paths, traversal, duplicates, invalid limits, or an unencodable policy reject before capture and create no task.
- The Auto Graph composer now exposes `Exact source-revision scope` as a user-visible field. It accepts comma- or newline-separated directory **names** applying at any depth; it does not infer names from repository layout, Git ignores, an error path, or model prose.
- The pure parser canonicalizes ordering while deliberately retaining duplicates so validation rejects ambiguous input rather than silently deduplicating it.
- AppModel passes only that explicit native selection into contract preparation and restores the conservative defaults when the draft resets.
- The collector's no-follow behavior is unchanged. A selected real directory is skipped before any descendant is opened, but a symlink occupying the selected directory name, a symlink outside an excluded real tree, special files, traversal, bounds overflow, or capture-time change still fails closed.
- Contract review continues to display the exact canonical exclusions, limits, source revision, and policy digest. Confirmation recaptures through the exact retained policy; no decoded or later-edited policy can replace it.

This is domain-neutral. No production branch names LoopForge, EasyBusiness, `dist`, a package format, language, build system, or product category. The native walkthrough's `dist` veto is covered only as a synthetic test selection.

## Verification

- Focused affected run: 19 tests, 0 failures, 0.995 test seconds.
- New direct cases prove canonical parsing, duplicate rejection, path-shaped exclusion rejection, explicit generated-tree exclusion over an internal symlink, exact policy-digest binding, confirmation-time recapture, and draft reset.
- Existing collector tests still prove that non-excluded symlinks and even symlinks occupying an excluded directory name fail closed.
- Complete source suite: 823 tests executed, 8 intentional environment skips, 0 failures, 64.329 test seconds.
- Real Codex child/Responses bridge: passed in 19.184 seconds.
- arm64 non-DEBUG Release build: passed in 102.90 seconds.
- Current source snapshot: `ac7bcb60011f460f02721f3f6b6d692d3eb7a1c6660a375b8e5bd5658374ecf3`.
- Diff whitespace validation passed.

One malformed orchestration call before the focused run executed no shell command and counts zero.

## Remaining boundary

The corrected source was packaged as snapshot `ac7bcb60011f460f02721f3f6b6d692d3eb7a1c6660a375b8e5bd5658374ecf3`. Its package-owned suite passed 823 tests with 8 intentional skips and 0 failures in 56.923 test seconds; deep strict signing, ZIP/DMG/checksum validation, embedded source/test binding, exact packaged-Mach-O startup, and cleanup passed. The executable digest is `0af59069d8d77f4f6691004dffabba1f0a310410cbf923e06f19f12fc80d2a3b` and the application CDHash is `1dab7c409391452d18eafbc63c919c519ea61cf2`.

An unlocked Computer Use walkthrough of that exact package exposed the `Exact source-revision scope` field and fail-closed policy copy, then retained a second screenshot with an explicit `dist` selection. This proves the packaged user-visible authority; automated tests remain the authority for parsing, digest binding, generated-tree exclusion, and confirmation-time recapture. No native enrollment was attempted and no task was created.

The field removes the source-scope dead end only after the user explicitly amends and confirms the policy. Executable verifier selection, provider harness/network authority, mutation preparation/containment, legacy retirement, the full native visual matrix, clean-commit rebuild, commit, and push remain unresolved. Final release is false.

EasyBusiness was not modified. Its read-only HEAD remained `2ae40452e6d8661c46db466c43ea40bba3bfab04` and its established `git status --porcelain=v1 -z -uall` fingerprint remained `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
