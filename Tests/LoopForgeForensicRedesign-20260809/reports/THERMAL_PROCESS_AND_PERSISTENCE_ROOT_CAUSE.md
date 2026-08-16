# Thermal, Process, and Persistence Root-Cause Audit

Status: confirmed systemic defects; redesign not complete  
Scope: stopped EasyBusiness Graph task, build 133 runtime sample, committed LoopForge baseline, and the current uncommitted repair  
EasyBusiness handling: read-only evidence only

## Executive finding

The user's heat report is explained by a compound lifecycle failure, not one runaway command. LoopForge combined concurrent heavyweight workers with prompt-only resource discipline, incomplete ownership of detached resources, fire-and-forget process termination, repeated full-checkpoint serialization, uncached repository/image inspection, and no thermal/load governor. The current dirty repair closes part of the original leak, but introduces a new 20 Hz-per-node filesystem polling loop and still cannot prove that every process or model runner has quiesced.

The current stopped state is safe at the instant inspected: build 133 was at `0.0%` CPU, no Codex worker, `xcodebuild`, Ollama, or Qwen process was found, all 37 durable host-resource leases were `released`, and LoopForge owned no power assertion. That point-in-time result does not invalidate the historical defect. It shows the stopped runtime is presently idle after the audit removed the exactly attributable detached Simulator process; it does not make the lifecycle design sound.

## 1. The resource broker busy-polls even when no request exists

The current uncommitted `GraphHostResourceLeaseRegistry.serviceBrokerRequests` performs this loop for every active node scope:

1. list and inspect the scope's broker directory;
2. sleep for 50 ms;
3. repeat until cancellation.

That is 20 directory scans per second per node. The normal Auto Graph cap is three non-local workers, so an otherwise idle frontier can perform about 60 directory scans per second merely to discover that there is no request.

The native build 133 sample captured the mechanism directly:

- sample duration: 2.37 seconds at 1 ms intervals;
- current physical footprint: 129.7 MB;
- recorded peak physical footprint: 685.6 MB;
- four cooperative-thread groups contained `GraphHostResourceExecutionScope.run` stacks;
- their sampled work entered `GraphHostResourceLeaseRegistry.processBrokerRequests`, `FileManager.contentsOfDirectory`, URL standardization, `stat`, `lstat`, and directory enumeration;
- the main thread was mostly sleeping in the application event loop, so this was background broker activity rather than user interaction.

The polling load is not enough by itself to explain all thermal pressure, but it is continuous, scales with node concurrency, and runs while remote agents may otherwise be waiting. A repair intended to prevent resource leaks therefore added a permanent background tax to every active node.

## 2. Process termination returns before cleanup is proven

The current dirty `ProcessRunner` improves the committed implementation by snapshotting descendants and sending `SIGINT`, `SIGTERM` one second later, then `SIGKILL` two seconds after that. The improvement remains asynchronous:

- timeout and watchdog paths call `stopProcessWithEscalation` and immediately resume their continuation with an error;
- the Graph scheduler can therefore proceed while the prior tree is still inside its three-second escalation window;
- cancellation has no durable completion receipt stating which PIDs exited;
- the captured identity is only a PID, without process birth time or audit token, so a reused PID can theoretically be signalled during delayed escalation;
- a child that double-forks, activates a GUI singleton, submits to launchd, or otherwise reparents before capture remains outside the tree;
- normal termination calls `readToEnd()` on both pipes. A missed descendant retaining a write descriptor can keep that completion path blocked.

The already documented Simulator chain is the concrete historical instance: the node retained launcher PID `40779`, the durable GUI became launchd-owned PID `40917`, cleanup proved only `40779` absent, and PID `40917` survived for days.

The dirty application delegate now waits up to four seconds during app termination and makes closing the last window terminate the app. Both changes are necessary. The committed baseline did the opposite: closing the final window deliberately left multi-hour workers running invisibly. Even with the new grace window, process cleanup still lacks an awaited, typed quiescence result.

## 3. Resource ownership remains prompt-enforced and incomplete

The stopped task retained 4,124 node command log entries. Because start and completion records both retain command text, those entries are not 4,124 unique invocations. They nevertheless prove a large host-tool surface:

- 104 retained command entries mention Simulator application launch or `simctl boot`, `bootstatus`, or `shutdown`;
- 58 mention `simctl boot`;
- 41 mention `simctl shutdown`;
- 32 match an `open` command;
- 14 mention `launchctl`;
- 2 mention `nohup`.

The current broker supports only one resource kind: `iosSimulatorBoot`. It does not own device creation/deletion, Simulator application sessions, ports, HTTP servers, watchers, launch agents, build daemons, or local-model runners.

More importantly, Full Access workers are merely *told* to use the broker. The operational prompt simultaneously tells them to start long-lived tools in the background and retain `$!`. Nothing mechanically prevents direct `xcrun simctl boot`, `open`, `nohup`, server launch, or `launchctl`. If the worker crashes or loses context before its promised cleanup, the prompt is not a recovery system.

## 4. Ollama shutdown and model unload are not closed-loop

`OllamaManager` sets `OLLAMA_KEEP_ALIVE=5m`, one loaded model, and one parallel request. Ordinary local supervisor chat requests do not override `keep_alive`, so a large local model may remain resident for five minutes after the last review.

If LoopForge starts the server, `stopOwnedServer()` only calls `Process.terminate()` on the immediate `ollama serve` process, clears its references immediately, and never:

- waits for exit;
- escalates termination;
- enumerates/reaps model-runner descendants;
- calls an unload endpoint and verifies zero loaded runners;
- records a cleanup failure.

If LoopForge connects to a pre-existing Ollama service, it correctly must not terminate the user's service, but it also has no borrowed-resource contract to unload only the model instance it loaded. This is a credible explanation for heat that continues for minutes after task activity appears to stop, especially with a high-context local model.

## 5. Every ordinary state mutation still rewrites the complete checkpoint

The durable task store is `@MainActor`. Every `update` invokes `save`, and `save`:

1. reads the complete current `tasks.json`;
2. decodes all tasks to validate the old checkpoint;
3. atomically writes the complete old bytes to a backup;
4. pretty-prints and encodes every task;
5. atomically writes the complete new checkpoint.

At inspection time both the main and backup files were about 10.7 MB. The stopped EasyBusiness task alone contains 19 nodes and 5,486 node log entries, and its serialized snapshot is about 8.1 MB. Repeating read/decode/write/encode on the main actor also publishes a new task array, rebuilding large SwiftUI Graph/detail trees.

The dirty repair batches agent, command, and system node logs for 30 seconds. That is directionally useful, but it does not change the storage architecture: status, review, eligibility, timing, thread, and integration updates still rewrite the entire store. It also exchanges write amplification for up to 30 seconds of non-durable in-memory logs.

## 6. Evidence collection repeatedly scans and decodes without a cache

The current Graph has five evidence-collection call sites. Each passes `before: [:]`, so changed-file provenance is disabled. A collection then:

- fingerprints the workspace;
- fingerprints it again through `recentlyModifiedPaths`;
- enumerates the workspace again to locate images;
- loads up to 12 images;
- converts each through AppKit bitmap paths;
- computes luminance samples;
- runs a Vision OCR request on every selected image.

There is no content-addressed cache keyed by file hash, no repository generation ID, and no heavy-tool concurrency budget. Multiple reviews can therefore rescan the same repository and rerun OCR over the same high-resolution screenshots. This wastes CPU while also producing weak provenance, because freshness by filename/mtime is not equivalent to evidence from the current commit or run.

## 7. There is no thermal or load governor

No LoopForge source observes `ProcessInfo.thermalState`, low-power mode, battery/power source, aggregate owned-process CPU, memory pressure, or concurrent heavyweight phases. Normal non-local Auto Graph allows three node workers, each of which can independently build, test, launch Simulator, retain screenshots, and trigger review/evidence work.

While a task runs, `beginActivity` intentionally disables idle system sleep so lock-screen work can continue. That fulfills the user's earlier lock-screen requirement, but without a thermal governor it also guarantees that an overloaded task remains awake and hot rather than yielding.

## Current point-in-time safety check

At `2026-08-09T15:01:11Z`:

- LoopForge build 133 PID `68656`: `0.0%` CPU, about `0.6%` memory;
- no matching Codex worker, `xcodebuild`, Ollama, or Qwen process;
- host-resource registry: 0 open scopes, 37 released leases, 0 active leases;
- CoreSimulator helper processes remained at `0.0%` CPU;
- LoopForge owned no `pmset` assertion;
- active sleep assertions belonged to Chrome, ChatGPT, audio, and `powerd`, not LoopForge.

This check must not be generalized into “the bug is gone.” It is an instantaneous stopped-state observation after forensic cleanup.

## Required redesign gates

1. Replace 50 ms directory polling with event-driven broker IPC or filesystem events, with bounded fallback backoff and one broker service per task rather than per node.
2. Make process stop an awaited operation returning identities, signals, exit states, elapsed grace, surviving descendants, and quiescence verification.
3. Launch worker commands inside a durable per-turn ownership boundary; pair PID with start time/audit identity and prevent scheduler reuse until cleanup completes.
4. Expand typed resources to Simulator device lifecycle, GUI sessions, local servers/ports, watchers, launch agents, build services, and model runners.
5. Make direct acquisition of managed resources impossible or a typed task failure under Full Access; prose is not enforcement.
6. Replace full-store rewrite-on-mutation with an append-only event journal plus compact snapshots, background serialization, checksums, and bounded compaction.
7. Introduce content-addressed evidence caching and pass real before/after repository generations to every collector.
8. Serialize or budget heavy phases: build/test, Simulator, OCR/image decoding, local inference, and integration must not overlap merely because node objectives are independent.
9. Add an adaptive thermal governor using thermal state, power mode, owned CPU/memory, and recent load. Reduce concurrency, back off, or pause safely before serious thermal pressure.
10. Add explicit Ollama model unload and owned-server tree reaping; borrowed services need per-model release without terminating the user's server.
11. Do not report pause/stop/exit complete until all typed resources are released or a durable `releaseFailed` state blocks success.
12. Test close-window, quit, timeout, cancellation, crash recovery, double-fork/reparent, inherited pipe descriptors, PID reuse, loaded-model release, and stopped-state CPU/resource quiescence.

## Defect classification

| ID | Severity | Defect | Consequence |
|---|---:|---|---|
| F-014 | High | Per-node broker busy-polls the filesystem at 20 Hz | Continuous avoidable work; about 60 scans/s at the normal three-node cap |
| F-015 | Critical | Stop escalation is fire-and-forget and returns before reaping | Old and new work can overlap; cleanup success has no proof |
| F-016 | Critical | Full Access resource discipline is prompt-only | Direct/background resources can bypass durable ownership |
| F-017 | High | Ollama model/server release is not verified | Large model runners can remain resident after visible work stops |
| F-018 | High | 10.7 MB store is fully decoded/encoded/written on ordinary updates | Main-actor CPU, I/O, memory, and SwiftUI invalidation scale with history |
| F-019 | High | Repository scans, image decoding, and OCR are uncached | Repeated heavy local work with weak current-run provenance |
| F-020 | Critical | No thermal/load governor exists | Three “independent” nodes may contend across every heavyweight subsystem |
| F-021 | High | Committed last-window behavior kept workers invisible | A user could believe LoopForge exited while autonomous work continued |

## Evidence

- `evidence/build133-cpu-spike.sample.txt`
- `evidence/task-snapshot-20260809T131753Z.json`
- `reports/PROCESS_AND_SIMULATOR_LIFECYCLE.md`
- `Sources/LoopForge/HostResourceLeases.swift`
- `Sources/LoopForge/ProcessRunner.swift`
- `Sources/LoopForge/LoopForgeApp.swift`
- `Sources/LoopForge/TaskStore.swift`
- `Sources/LoopForge/AuditEvidence.swift`
- `Sources/LoopForge/OllamaManager.swift`
- `Sources/LoopForge/GraphLoopEngine.swift`

