# Control Plane, Watcher, and Lifecycle Audit

Status: **forensic analysis in progress; production refactor gate remains closed**  
Scope reviewed here: task persistence, workspace audit/evidence, completion reports, Watcher policy/prompts/controller, application orchestration, and the single-loop controller.

## Governing conclusion

The current control plane can convert one unresolved condition into an expensive self-reinforcing cycle: a deterministic Watcher pass fails, the same Full Access Agent is awakened immediately, that Agent edits and self-verifies the pipeline, the controller schedules the next pass immediately, and an unchanged cause starts the cycle again. The nominal two-hour review floor and rule cooldown do not bound this path. The single-loop path has a related failure mode: when a numeric audit score stops improving, LoopForge resets the session after two rounds but does not retire the strategy or bound subsequent content mutations.

The acceptance layer is also not domain-neutral. It assigns requirements and scores from task categories, filenames, request words, and command-text substrings. Those heuristics make familiar historical scenarios appear well covered while unfamiliar but equivalent tasks can be misclassified.

## Defects

### F-089 — Critical — The evidence collector embeds historical product scenarios

Screenshot grouping and requirement coverage contain explicit game concepts (onboarding, gameplay, recruitment, settlement, world exploration, arena/PvP) and a separate browser-result branch selected by `.desktopAutomation` (`AuditEvidence.swift:215-388`). This production code is a direct vertical adaptation.

Required redesign: evidence requirements come from an immutable, typed acceptance contract. Artifact adapters may classify declared artifact types, but production policy must not contain genre, product, workflow, language, or customer vocabulary.

### F-090 — High — Visual state diversity is inferred from filenames

`screenshotStateKey` treats words in a path as semantic state and selects at most one image for each inferred group (`AuditEvidence.swift:255-293`). Renamed duplicates can appear diverse, while genuinely distinct states with similar names collapse. Image content, capture environment, state identity, and baseline lineage are not verified.

Required redesign: each capture has a machine-generated state receipt, environment receipt, image hash, baseline binding, and uniqueness check.

### F-091 — Critical — Workspace acceptance is category-, filename-, and keyword-scored

`WorkspaceAuditor` infers implementation, tests, documentation, results, entry points, successful verification, and measured outcomes from extensions, filenames, task categories, and log substrings (`WorkspaceAuditor.swift:3-218`). It includes bespoke interactive-image behavior and category branches for script, experiment, data, research, and optimization.

Required redesign: evaluate declared deliverables and verifier receipts. File discovery may propose candidates but can never establish a requirement or award completion credit by name alone.

### F-092 — High — Any later green command clears all earlier failures

A successful command sets `unresolvedVerificationFailures = 0` without binding success to the failed command, requirement, artifact tree, or environment (`WorkspaceAuditor.swift:69-97`). An unrelated lint or trivial test can erase a failed product build.

Required redesign: failures and successful reruns share a typed verifier identity, input tree hash, environment identity, and requirement binding. Only a causally equivalent successful rerun resolves a failure.

### F-093 — Critical — Completion reports overstate unverified counts

The report labels every retained command log as a “verification run,” the number of coverage strings as “requirement signals,” and any copied image as a “real screenshot” (`CompletionReportGenerator.swift:46-59,142-185`). A final call unconditionally renders “Completed and verified.” When no baseline exists, before/after silently initializes “before” from the current snapshot (`CompletionReportGenerator.swift:301-319`).

Required redesign: report only typed, resolved evidence receipts; distinguish candidate, verified, failed, stale, and rejected evidence; refuse final rendering unless a signed completion decision references the exact task contract and tree.

### F-094 — Critical — Main task persistence can fail or disappear silently

`TaskStore.save()` swallows write failures and `load()` converts an unrecoverable primary-plus-backup decode failure into an empty task list (`TaskStore.swift:197-339,341-364`). The comment claiming a future mutation will surface the error is not implemented.

Required redesign: durable-generation receipts, explicit checkpoint health, surfaced errors, fail-closed scheduling, and recovery that never presents “no tasks” as a valid state after unreadable storage.

### F-095 — High — Pending graph history is durable only after a 30-second flush

High-volume graph logs remain only in memory until a timer or another node mutation flushes them (`TaskStore.swift:9-188`). Pause/stop flushes, but crashes and abrupt exits can lose the last causal events that reviewers and recovery need.

Required redesign: append-only bounded event journal off the main actor, periodic compact snapshots, fsync policy proportional to risk, and deterministic reconstruction.

### F-096 — High — Watcher Overview fallback contains vertical vocabulary

When the manifest does not identify important signals, the UI searches for `candidate`, `excess`, `return`, `backlog`, and similar historical-scenario words (`WatcherFocusProjector.swift:194-209`). This silently favors specific prior workloads.

Required redesign: show only signals bound to goal anchors by the validated task contract. Missing bindings must remain a visible configuration gap.

### F-097 — High — Manifest normalization silently discards configuration

Generated paths, verification commands, signals, rules, dashboard keys, and assessment items are truncated to fixed prefixes (`WatcherPolicy.swift:91-110,138-211,328-360`). The Agent can believe all declared behavior is active while the runtime has silently removed the tail.

Required redesign: reject over-budget manifests with exact diagnostics or require an explicit, auditable reduction decision. Never silently change the executable contract.

### F-098 — High — A checkpoint is “valid” if a small file exists

Checkpoint validation checks only existence and an 8 MiB size ceiling (`WatcherPolicy.swift:397-413`). It does not validate schema, freshness, atomic generation, correspondence with telemetry, monotonic pass identity, or recoverability.

Required redesign: typed checkpoint schema, generation/hash binding, atomic receipt, dry-run recovery verification, and rollback to the last valid generation.

### F-099 — Critical — The declared workspace boundary is not enforced

Watcher prompts say parent and sibling paths are forbidden, but deterministic commands run without an OS sandbox. Absolute executables and arbitrary arguments are accepted, while the environment includes `HOME` and `SSH_AUTH_SOCK` (`WatcherPolicy.swift:244-290,702-718,825-847`; `WatcherController.swift:476-503`). A generated script can read or mutate outside the selected workspace and use the user's SSH agent.

Required redesign: process-level workspace sandbox, allowlisted environment from zero, no credential-bearing sockets, capability-granted external paths only, and path/authority receipts for every mutation.

### F-100 — Critical — Direct warning events bypass sustained evidence and cooldowns

Warning or critical telemetry events set `shouldWakeAgent` immediately (`WatcherPolicy.swift:508-536`). They do not use the rule's consecutive-match requirement or cooldown. A generated pipeline can therefore wake an expensive Agent every deterministic pass.

Required redesign: all adaptive wakes pass through one bounded wake policy keyed by causal issue identity, evidence novelty, cooldown, recurrence count, and global thermal/resource budget.

### F-101 — Critical — Failure → Agent review → immediate rerun is a tight loop

Every nonzero pipeline result adds a review reason and calls `performReview` immediately (`WatcherController.swift:523-615`). After any non-complete review, `nextRunAt` is set to the review completion time and scheduled immediately (`WatcherController.swift:54-57,774-819`). An unchanged failure can therefore alternate process and Agent turns without the normal cadence or review minimum.

Required redesign: causal failure fingerprinting, exponential backoff applied to the entire cycle, novelty requirement before another Agent turn, strategy retirement, and a terminal pause after a bounded attempt budget.

### F-102 — Critical — The same Full Access Agent authors, repairs, verifies, and approves a Watcher

Watcher setup always creates the selected Agent with Full Access (`AppModel.swift:490-523`). The same selection builds the pipeline, handles adaptive reviews, is permitted to repair implementation, writes `review.json`, runs its own verification commands, and returns the completion marker (`WatcherController.swift:347-430,662-828,997-1081`).

Required redesign: separate author and reviewer identities and enforce read-only review at the process layer. Generated verification is characterization evidence until an independent evaluator validates the contract.

### F-103 — Critical — Watcher completion is not bound to deterministic completion or issue coverage

An Agent can return `COMPLETE` even when telemetry did not set `completed`, active issues were not all assessed, and important goal anchors lack evidence. The controller accepts the marker after only pipeline self-verification and a structurally valid assessment (`WatcherController.swift:728-798`).

Required redesign: completion is a conjunction of task-contract requirements, deterministic completion receipt, zero unresolved required issues, exact evidence bindings, independent review, and safe resource cleanup.

Retirement status (2026-08-11): the production Watcher path now requires fresh
`completed`/`ok` telemetry over a successful issue-free run, SHA-256-bound
telemetry and physical JSON checkpoint evidence, verification-plan and
assessment digests, evidence for every declared goal anchor, and a fresh
read-only independent review bound to the exact typed completion receipt.
Startup revalidates the chain and current checkpoint, demoting legacy or
tampered completion without automatic resume. See
`WATCHER_DETERMINISTIC_COMPLETION_IMPLEMENTATION.md`. Native walkthrough and
clean revision/push receipts remain pending, so this is not final acceptance.

### F-104 — Medium — “Final status marker” need not be final

`WatcherReviewDecision.parse` searches the entire response with `contains` and accepts one marker anywhere (`WatcherPolicy.swift:801-822`). It does not validate the final non-empty line as promised by the prompt.

Required redesign: a structured response channel or exact final-record decoder; prose markers never control lifecycle state.

### F-105 — High — Review failure erases its own needs-attention state

`fail(... preserveSchedule: true)` first stores `.needsAttention`, then immediately overwrites it with `.active` (`WatcherController.swift:1148-1178`). Because a failed review does not update the assessment or last Agent decision, the attention overlay can also remain false.

Required redesign: operational scheduling and user-attention state must be separate persisted fields. Never encode two dimensions in one enum and overwrite one to preserve the other.

### F-106 — Critical — Shutdown does not synchronously prove child cleanup

Watcher shutdown cancels Swift tasks and immediately drops operation references (`WatcherController.swift:292-308`). Loop shutdown cancels the job, asks Ollama to terminate, and relies on a short asynchronous grace while the application may be exiting (`LoopController.swift:262-311`). There is no persisted child-process ownership inventory or terminal receipt proving every descendant exited before the UI reports stopped.

Required redesign: one process supervisor with task-scoped process groups, persisted ownership, awaited TERM/KILL escalation, exact PID-start-time verification, and a visible cleanup-failed state.

### F-107 — Critical — Single-loop persistence writes the full checkpoint every five seconds

The main timer fires every five seconds and checkpoints active time once 15 seconds have elapsed (`LoopController.swift:84-113`). Each checkpoint calls `TaskStore.update`, which atomically encodes and rewrites the full task array. The forensic snapshot measured approximately 10.7 MiB for the active checkpoint, making long runs generate sustained main-actor encoding and disk churn.

Required redesign: monotonic lightweight runtime journal, off-main compaction, dirty-field snapshots, measured write budget, and no timer-driven rewrite of historical evidence.

### F-108 — High — LoopForge disables idle system sleep for the entire task

Starting a loop creates a process activity with `.idleSystemSleepDisabled` and retains it until the controller exits (`LoopController.swift:130-150,203-225`). This can keep a long-running, stalled, or thermally unhealthy task awake indefinitely.

Required redesign: user-visible execution-power policy, short renewable leases only while verified productive work is active, automatic release on inactivity/thermal pressure, and no equivalence between screen lock and forced wakefulness.

### F-109 — Critical — Single-loop “stagnation recovery” never retires the strategy

If the numeric audit score fails to improve twice, LoopForge resets the Codex thread and sets `stagnantRounds` back to zero (`LoopController.swift:825-939`). There is no semantic strategy fingerprint, mutation budget, maximum recovery count, failure lesson, or terminal pause, so paraphrased repetitions can continue forever.

Required redesign: structured strategy identity, progress vector, causal failure signature, bounded mutation and retry budgets, persisted lessons, and mandatory alternative planning or safe stop.

### F-110 — High — Application launch can mutate completed external workspaces

`AppModel.init` scans completed Graph records and may regenerate their HTML report inside each task workspace before the user starts or resumes anything (`AppModel.swift:129-173`). This is an external mutation on ordinary application launch.

Required redesign: startup is read-only except for LoopForge-owned state. Workspace migration/report regeneration requires explicit scoped authorization and a reversible plan.

### F-111 — Critical — Auto Graph discards the user runtime target at task creation

`AppModel.createAndStart` writes `targetSeconds = 0` whenever execution mode is Auto Graph and tells the user that nodes have no artificial minimum (`AppModel.swift:941-976`). This is the direct runtime-target bypass already proven from the stopped EasyBusiness task.

Required redesign: immutable objective constraints—including duration when explicitly requested—must survive mode selection and remain in every planning, completion, and report contract.

## Required architectural direction

1. One immutable, typed task contract replaces category/keyword inference.
2. One event-sourced state machine owns attempts, causal failures, progress, mutation budgets, and terminal actions.
3. Author, executor, deterministic evaluator, and independent reviewer have separate identities and enforceable authority.
4. One process/resource supervisor owns child groups, host leases, power leases, cadence, thermal budget, and cleanup receipts.
5. Evidence, verification, visual captures, blockers, and completion decisions are hash-addressed records bound to a workspace tree and requirement IDs.
6. Watcher cadence and Auto Loop retries share bounded backoff, novelty, and strategy-retirement policy.
7. Persistence uses append-only journals plus off-main compaction; UI projections are never the source of truth.

These findings are evidence for the forthcoming architecture; they do not authorize production-source refactoring before the 36,000-second forensic gate.

The complete native presentation audit and findings F-112 through F-124 are recorded in `LOOPFORGE_NATIVE_UI_SYSTEM_AUDIT.md`.
