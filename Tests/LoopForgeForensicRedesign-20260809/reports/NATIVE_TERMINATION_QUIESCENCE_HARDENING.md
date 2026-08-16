# Native Termination and Quiescence Hardening

Status: **receipt-proven stop closure and normal-quit fail-closed retention passed; live-resource cleanup execution, unlocked current-package UI, and final release remain pending**

Recorded: `2026-08-16T01:52:26Z`

Historical stage note: this report records the fail-closed quit boundary before
live cleanup execution was implemented. The succeeding, current result is
[Native Runtime Cleanup Execution](NATIVE_RUNTIME_CLEANUP_EXECUTION.md).

## Defect found

The retained native execution path had a circular lifecycle precondition. An
activated attempt made `activeAttemptID` non-null. A stop request could move the
run to `stopRequested`, and the runtime could prove that no process, lease,
failed release, or queued cleanup remained. However, `recordQuiescence` still
required the active attempt to have been cleared first. No receipt-backed path
could clear that unfinished attempt after stop when no worker result existed.
The run therefore could remain durably `executing` across relaunch even though
its retained runtime was physically quiescent.

This was a systemic convergence and cleanup defect rather than a presentation
problem: the reducer required the conclusion before accepting the receipt that
proved the conclusion. It also exposed a replay gap because a decoded
`quiescenceRecorded` event was not independently rebound to the retained drain,
resource sets, monotonic ordering, run, phase, and intent before changing state.

## Repair

`RunReducer` now accepts pause/stop quiescence while an unfinished attempt is
active only when the runtime-owned receipt exactly matches the retained drain,
run, live resources, failed releases, monotonic ordering, current phase, and
intent. That accepted receipt atomically records quiescence and applies the
`interrupted` disposition to the active attempt before the following stopped or
paused event is reduced. Completion remains stricter and still requires no
active attempt.

Replay applies the same binding checks. A copied or tampered quiescence event
cannot interrupt an attempt or advance state. This preserves historical replay
while making the new stop closure deterministic and receipt-native.

The application delegate now routes normal app termination through `AppModel`
and every retained `KernelProductionExecutionSession` before shutting down the
legacy controller. Each session is preflighted against its exact supervisor
cleanup plan. A nonempty plan cancels quit and keeps the session alive; it is
not converted into a false terminal state or silently dropped. A physically
empty session receives an exact journaled stop drain and quiescence receipt,
must project `stopped` plus `quiescent`, and is only then removed from the
in-memory session table. Any journal, drain, quiescence, or projection failure
cancels termination. If an earlier quit already journaled `stopRequested` but
crashed before the runtime-drain frame was appended, the next quit validates
that exact retained stop boundary, appends the missing drain receipt without
replaying the stop command, and then continues to quiescence. A retry after the
drain frame also continues directly to quiescence; neither path issues an
invalid second stop.

This path deliberately does not claim to execute a nonempty cleanup plan. A
retained live-resource session keeps the app open until an authorized cleanup
path has released it. Production execution of every join/terminate/detach
action, including failure recovery, remains a release gap and is not hidden by
the new quit veto.

## Verification

- `KernelRunReducerTests`: 45 tests, 0 failures. New coverage proves a valid
  stop receipt interrupts the active attempt and replays to stopped, while an
  unbound replay event cannot alter the attempt.
- `NativeKernelEnrollmentFlowTests`: 12 tests, 0 failures in 13.431 seconds
  (13.432 wall).
  The new application-level test enrolls and activates a read-only run, invokes
  the exact normal-quit preparation path, proves stopped/quiescent replay with
  an interrupted disposition, and proves ready execution authority cannot be
  reconstructed. A second test proves termination resumes an already journaled
  stop request whose drain frame is missing and reaches stopped quiescence
  without replaying stop.
- Exact package-owned complete suite: 854 executed, 8 explicitly gated skips,
  0 failures in 69.023 test seconds (69.072 wall); the real Codex bridge passed
  in 12.221 seconds.

The signed package is bound to dirty-source snapshot
`9676fc71bfb02fbab6e4a781ac317d657337c8a097fcd08917228e523944a064`
and test-log digest
`25b8629e95ba1ad1ca51d202beb32ca18a8636059eaed557fe19413185d8acfa`.
Deep-strict signing, checksum verification, ZIP integrity, DMG verification,
mounted-DMG byte identity for all three Mach-O files, exact packaged startup,
and process cleanup passed. The app executable is
`479c7e160d6c4d5a925c58bc6ed31793336f4e91b897a83a514ef2942c843940`
with CDHash `4deafc84060fcac9aa3c82d7ac45c0b5286a8a87`.

Computer Use attempted the exact rebuilt package after signing. macOS remained
locked because physical input had paused automatic unlock. The lock was not
bypassed; no UI action or package process occurred and blocked time counts
zero. Existing screenshots remain prior-package evidence only.

EasyBusiness remained permanently stopped and read-only at branch
`codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, and NUL-delimited status digest
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Remaining boundary

The native quit deadlock is closed for physically quiescent retained sessions,
and a live cleanup plan now prevents unsafe application exit. Still pending are
authorized execution of nonempty cleanup plans, productive provider backend
ratification and native cutover, trusted Release containment or retained
vetoes, mutation preparation or retained vetoes, current-package unlocked UI,
the full native trait/window/baseline/candidate matrix, a clean-commit rebuild,
commit, and push. Final release is false.
