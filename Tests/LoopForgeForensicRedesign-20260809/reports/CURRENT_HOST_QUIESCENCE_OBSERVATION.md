# Current Host Quiescence Observation

Status: read-only point-in-time observation captured at `2026-08-09T17:10:13Z`. This is forensic evidence that the stopped legacy task was inactive at the observation time. It is **not** a durable quiescence receipt and does not cure F-158 through F-166.

## Scope and authority

- The permanently retired EasyBusiness Graph task is `1ED2180F-FBE1-4BCA-9E79-701F40CC3483`.
- EasyBusiness remained read-only throughout this observation.
- No process was terminated, no launch agent was changed, and no host resource was acquired or released.
- Unrelated host activity was observed only to avoid falsely attributing heat to LoopForge.

## Observed task state

`~/Library/Application Support/LoopForge/tasks.json` is an array. The matching task record reported:

| Field | Observed value |
|---|---|
| `status` | `stopped` |
| `stage` | `Stopped · progress and project files are saved` |
| `resumeOnNextLaunch` | `false` |
| `updatedAt` | `2026-08-09T13:14:04Z` |
| `checkpoint` | `null` |

This proves only the persisted projection. It does not independently prove that all formerly owned processes, timers, tasks, and assertions terminated.

## Observed capability leases

`~/Library/Application Support/LoopForge/HostResourceLeases/leases.json` reported:

- active scope count: `0`;
- total lease records: `37`;
- released lease records: `37`;
- lease records belonging to the retired task: `37`;
- unreleased lease records belonging to the retired task: `0`.

This is consistent with successful resource release at observation time. The file is a mutable current-state projection rather than the hash-chained, run-scoped `QuiescenceReceipt` required by the redesign.

## Observed process and power state

The packaged LoopForge process was PID `68656` and reported:

- parent PID `1`;
- CPU `0.0%`;
- memory `0.6%`;
- elapsed time approximately `06:01:44`;
- direct child count `0`.

No process matching the retired task identifier, `xcodebuild`, `pytest`, or `loopforge-resource-broker` was found in the targeted process query. `pmset -g assertions` showed no LoopForge-owned `PreventUserIdleSystemSleep` or `PreventSystemSleep` assertion. The system-wide `PreventUserIdleSystemSleep` value was `1`, with visible assertions belonging to `powerd` and `coreaudiod`, not LoopForge.

## Unrelated load deliberately left untouched

One instantaneous CPU sample showed the highest load in unrelated processes, including:

- Clash Verge `verge-mihomo` PID `74884` at approximately `220.8%` CPU;
- a Google Chrome renderer PID `3476` at approximately `25.5%` CPU;
- `WindowServer` PID `401` at approximately `24.5%` CPU;
- FrostMI PID `67140` at approximately `12.2%` CPU.

These processes are not proven to be owned by the retired LoopForge task. They were not modified. The sample is not a sustained thermal profile and must not be used to absolve or accuse LoopForge outside this observation window.

The independent `com.easybusiness.local-backend` launch agent and CoreSimulator services seen in prior inspection were likewise not proven task-owned and remain untouched.

## Evidentiary conclusion

The stopped legacy task was operationally quiet at the captured instant: its persisted status was stopped, all 37 recorded leases were released, the LoopForge app consumed no sampled CPU, no direct children were visible, targeted worker/build/test/broker processes were absent, and LoopForge held no visible sleep assertion.

That is weaker than the required product guarantee. The current implementation cannot emit a signed or hash-chained run-wide receipt proving that:

1. every child task acknowledged cancellation;
2. every descendant PID was reaped or durably recorded as failed cleanup;
3. every timer, broker poller, permission scanner, Watcher operation, and inference service ended;
4. every lease and sleep assertion was released;
5. the journal and UI projection represent the same terminal sequence.

The target kernel must make those facts replayable and non-waivable. A future point-in-time `ps`, lease-file, or `pmset` sample remains corroborating diagnostics, never the authority that permits a terminal state.

