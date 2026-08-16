# Async Load and Quiescence Topology

Status: forensic design evidence only. No production refactor is authorized before the 36,000-second analysis gate.

## Executive finding

LoopForge has cancellation requests, process escalation, timer invalidation, and host-resource leases, but it does not have one authoritative lifecycle boundary that can prove the application is quiescent. Several controllers publish terminal-looking state before all owned tasks, process trees, timers, broker loops, persistence jobs, and resource leases have acknowledged shutdown. This is sufficient to explain the user's observation that LoopForge appears closed or stopped while the Mac remains hot.

The failure is architectural rather than a single missing `cancel()`: ownership is fragmented, cancellation is mostly fire-and-forget, cleanup is sometimes launched as new unstructured work, and the UI has no receipt-backed distinction between `stop requested`, `draining`, `resources releasing`, and `quiescent`.

## Runtime ownership map

| Owner | Runtime work | Cancellation path | Awaited before terminal UI? | Load / safety consequence |
|---|---|---|---|---|
| `LoopController` | one unstructured `job`, 5-second clock timer, sleep-prevention activity, permission scanner, Ollama | `job?.cancel()`, `graphEngine.cancel()`, timer stop | No general join; defer publishes terminal state | Terminal label can lead actual process/resource shutdown |
| `GraphLoopEngine` | per-node unstructured tasks, blocked-node timers, process turns, worktrees | registry `cancelAll()` and semaphore signal | Registry removes handles and does not await values | No proof all node tasks reached cancellation handlers |
| `ProcessRunner` | owned subprocess tree and pipe readers | SIGINT, then SIGTERM at +1s, SIGKILL at +3s | A caller awaiting `run` eventually observes termination; higher-level registries may discard their handles | Locally reasonable escalation is defeated by missing orchestration join |
| `GraphHostResourceExecutionScope` | one 20 Hz broker-inbox poller per active node | cancel and await broker task; then release scope | Yes inside an individual node scope | Structured locally, but application-level release can race still-draining nodes |
| `WatcherController` | one scheduled sleep and/or active operation per watcher | cancel tasks, immediately remove dictionaries/tokens/running IDs | No | Application thinks Watchers are gone while process-backed operations can still drain |
| `TaskStore` | delayed Graph-log flush tasks; whole-checkpoint saves for mutations | flush jobs cancelled opportunistically | Not represented in lifecycle status | Main-actor encoding and disk activity are not governed as a resource budget |
| `SystemPermissionAutomator` | repeating main-run-loop scan of other applications' AX trees | timer invalidate | Stopped by Loop defer, not a global quiescence barrier | Repeated cross-application traversal during Full Access tasks |
| `OllamaManager` | app-owned inference server and pipe reader | `process.terminate()`, ownership cleared immediately | No wait or escalation | Server/descendants can outlive the UI's ownership record |

## Exact defects

### F-157 — Isolation failure fails open into the canonical workspace

`GraphLoopEngine.swift:2914-2942` catches worktree preparation failure, changes the node to `.exclusiveWorkspace`, points it at the primary workspace, and launches the mutating node anyway. The log calls this downgrade “safe,” but there is no isolation receipt, transaction, rollback boundary, or proof that unrelated dirty work is protected.

Required correction: isolation failure must reject or replan the node. A task may use the canonical workspace only when the immutable task contract explicitly authorized that mode before execution.

### F-158 — Graph cancellation discards child handles instead of joining them

`GraphChildRegistry.cancelAll()` copies the tasks, removes every registry entry, then only calls `cancel()` (`GraphLoopEngine.swift:1725-1730`). It cannot later await those tasks or report which one failed to quiesce.

Required correction: the registry must retain ownership through `cancelAndJoin(deadline:)`, produce per-child termination receipts, and keep timed-out children visible as a blocking condition.

### F-159 — Loop terminal state is published before resource cleanup completes

`LoopController.runLoop` sets `runningTaskID = nil` and writes “no agent process is running” in its defer, then launches host-resource release in a new `Task` (`LoopController.swift:313-360`). `stop(taskID:)` also marks an inactive task stopped before launching an unawaited cleanup task (`LoopController.swift:188-200`).

Required correction: `stopped` and `paused` are terminal projections only after a `QuiescenceReceipt` confirms child tasks joined, process trees reaped, broker services stopped, timers invalidated, leases released or durably failed, and owned inference runtimes ended.

### F-160 — Watcher shutdown erases evidence of still-draining operations

`WatcherController.shutdown()` cancels task handles and immediately clears task dictionaries, tokens, and `runningWatcherIDs` (`WatcherController.swift:292-307`). `cancelWork` does the same per watcher (`WatcherController.swift:330-338`). Neither path awaits task completion or process escalation.

Required correction: Watcher operations must be members of the same lifecycle supervisor as Graph operations. Shutdown must await their acknowledgements and expose failures/timeouts rather than deleting ownership state.

### F-161 — Application termination uses elapsed grace instead of observed quiescence

The application gives cancellation a fixed 3.25- to 4-second window and then releases all host resources. It does not receive a complete inventory of outstanding Graph and Watcher child tasks. The fixed delay happens to overlap `ProcessRunner`'s escalation schedule, but time elapsed is not proof of process death.

Required correction: termination waits on an explicit supervisor drain result with a bounded deadline. Remaining owned PIDs and leases are recorded and escalated; application reply is based on receipts, not only a clock.

### F-162 — Sleep prevention is scoped to the entire task, not eligible work

`LoopController.start` begins `.idleSystemSleepDisabled` and `.automaticTerminationDisabled` activity before preparation and keeps it until the outer task ends (`LoopController.swift:130-150`). Retry sleeps, external waits, audits, and stalled control phases inherit the same assertion.

Required correction: screen lock may continue productive work, but sleep prevention must be a renewable, reasoned lease active only while eligible work or bounded cleanup is actually in flight. Blocked/idle states release it. This preserves lock-screen operation without turning dead time into thermal residency.

### F-163 — Persistence work remains coupled to high-frequency state mutation

`TaskStore.update` synchronously calls `save()` for every state mutation. Streaming Graph log classes are batched for 30 seconds, but node status/runtime updates and the Loop's 15-second active-time checkpoints still encode and persist the complete task collection on the main actor. UI publication and persistence remain partially coupled.

Required correction: append compact journal events off the UI actor, snapshot at bounded checkpoints, and independently throttle projections. Persistence rate, bytes written, and main-actor work become measured budgets.

### F-164 — The permission automator performs repeating cross-application UI traversal on the main actor

During every Full Access task, `SystemPermissionAutomator` repeatedly scans active applications, up to two windows per application and a bounded descendant tree, via a main-run-loop timer (`SystemPermissionAutomator.swift:80-110`). The scan is stopped only when the outer Loop defer executes.

Required correction: replace broad polling with an event-triggered or tightly leased permission interaction adapter; run no scan when no matching prompt is expected, and include its timer in the quiescence receipt.

### F-165 — Each active Graph node runs a 20 Hz filesystem broker poller

`serviceBrokerRequests` processes the broker directory then sleeps 50 ms (`HostResourceLeases.swift:375-383`). The local scope correctly cancels and awaits this task, but load scales with active node count even when no request exists.

Required correction: use filesystem events, an IPC channel, or an adaptive backoff with immediate wake-on-request. Broker service ownership remains structured and becomes observable in the resource ledger.

### F-166 — Owned Ollama shutdown clears ownership before termination is proven

`stopOwnedServer()` sends `terminate()`, then immediately sets `serverProcess = nil` and `serverOwnedByApp = false` (`OllamaManager.swift:327-331`). There is no wait, descendant capture, escalation, or receipt.

Required correction: treat the server as a process-tree lease; cancel pipe readers, await exit, escalate within a deadline, and retain failed ownership for recovery.

### F-167 — Report regeneration is part of the hot operational path

Watcher agent messages retained every 30 seconds call `refreshReport`, which regenerates the local report. Pipeline events and status changes also regenerate it. Reporting has no independent coalescing or I/O budget.

Required correction: journal events first; generate a debounced projection from a stable sequence number and never let presentation work compete with scheduling, process cleanup, or state persistence.

## Why existing process escalation is not enough

`ProcessRunner` correctly captures descendants and escalates SIGINT → SIGTERM → SIGKILL. That is a useful adapter-level mechanism. The problem is above it:

1. owners cancel and discard task handles;
2. terminal UI can be written before adapter completion;
3. cleanup can begin concurrently with still-draining work;
4. no run-wide inventory proves zero owned tasks/PIDs/timers/leases;
5. a fixed grace interval substitutes for acknowledgement.

The refactor should preserve the process-tree implementation but place it behind one structured runtime supervisor.

## Required lifecycle state machine

```text
running
  -> pauseRequested | stopRequested
  -> drainingAgents
  -> reapingProcesses
  -> releasingCapabilities
  -> flushingJournal
  -> verifyingQuiescence
  -> paused | stopped

Any timeout/failure -> cleanupBlocked (with durable ownership evidence)
```

`paused`, `stopped`, and application termination readiness require a `QuiescenceReceipt` containing:

- zero unjoined orchestration tasks;
- zero owned live PIDs or an exact durable failed-cleanup record;
- zero active timers, scheduled watcher operations, permission scanners, and broker services;
- zero unreleased capability leases except explicitly failed leases;
- flushed journal sequence and projection sequence;
- released sleep-prevention/activity assertions;
- cleanup start/end times and escalation actions.

## Thermal acceptance gates

1. Idle app with no active task has no repeating timer faster than 30 seconds and no polling broker.
2. Paused/stopped app reaches a receipt-backed zero-owned-process state within the bounded shutdown SLA.
3. Closing the last window and quitting exercise the same drain protocol.
4. A deliberately cancellation-resistant child is escalated, recorded, and prevents a false `stopped` state.
5. N parallel nodes do not create N fixed-frequency idle pollers.
6. Blocked and retry-delay intervals release sleep-prevention assertions.
7. Persistence and report generation remain under explicit rate/byte/main-actor budgets.
8. Relaunch reconciles durable failed cleanup before any new mutation is authorized.

## Refactor placement

This topology strengthens target-architecture slices 1, 4, 7, and 9:

- `RuntimeSupervisor` becomes the sole owner of orchestration tasks and process leases;
- `ResourceLedger` includes timers, sleep assertions, broker services, subprocess trees, and report/persistence jobs;
- `RunJournal` records lifecycle commands and acknowledgements;
- `RunReducer` alone projects terminal state after accepting a valid quiescence receipt;
- UI reports `Stopping…`, remaining owned resources, and cleanup failures truthfully.

No prompt instruction, audit score, model approval, runtime total, or report narrative can waive these gates.
