# Worker Status, Time Accounting, and Convergence Failure

Status: forensic finding. This documents the historical failure and audits the uncommitted repair already present in the LoopForge worktree; it does not declare the redesign complete.

## Historical task evidence

The stopped EasyBusiness task contains 51 recorded node iterations across 19 nodes. Eleven nodes contain at least one worker summary with `LOOPFORGE_STATUS: BLOCKED`. Eight of those nodes nevertheless reached `completed`, contributing 13,129.89 stored active seconds while recording only 73.08 blocked seconds.

This is not limited to rejected intermediate turns. Seven approved turns themselves carry a `BLOCKED` marker:

- `reproduce-ios-us-baseline`: iteration 5 was approved even though the worker ended blocked.
- `reproduce-backend-us-baseline`: iteration 2 was approved with a blocked marker.
- `implement-bailian-json-contract`: all 11 turns, including the approved turn, ended blocked.
- `repair-us-financial-report-contracts`: both turns, including approval, ended blocked.
- `verify-us-ios-xcuitest-runtime-evidence-v1`: its only turn was both blocked and approved.
- `community-entry-external-watchdog-v1`: its only turn was both blocked and approved.
- `repair-us-category-direct-substitute-ontol`: its only turn was both blocked and approved.

`inventory-prior-us-evidence` is the eighth completed node containing blocked history: iterations 1–5 were blocked and continued, while iteration 6 was approved without a blocked marker.

In every listed completed node, `consecutiveFailures` ended at zero. Most also retained zero `accumulatedBlockedSeconds`. Thus the persisted state erased the very signal needed for convergence control.

## Root cause

The historical engine treated process exit code zero as successful work. A terminal Codex response with `LOOPFORGE_STATUS: BLOCKED` still exited cleanly, entered Main Graph review, could be returned as `continueWork` indefinitely, and could eventually be approved. The reviewer's semantic decision and the worker's explicit execution status were not reconciled as a typed state machine.

Three distinct concepts were collapsed:

1. **Transport success** — Codex returned a parseable terminal response.
2. **Work outcome** — the worker completed, needs continuation, or is blocked.
3. **Evidence judgment** — the independent reviewer approves or rejects the retained result.

Because transport success was used as a proxy for work success, blocked turns inflated active time, reset failure state, and remained eligible for same-thread continuation. This is a direct mechanism for both false duration and non-convergence.

## Audit of the current dirty-source repair

The current uncommitted LoopForge worktree already introduces `GraphWorkerRuntimePolicy` and `GraphRejectedTurnPolicy`. Those are directionally correct:

- a blocked marker is no longer provisionally added to `accumulatedActiveSeconds`;
- rejected nominally successful turns are subtracted after review;
- three consecutive blocked continuations freeze a node;
- replacement plans detach from the stale worker thread.

However, the present repair remains internally inconsistent:

1. `reviewAdjustment(for:approved:)` adds the full eligible duration back when a blocked worker result is approved. The included unit test explicitly expects `117` seconds for `BLOCKED + approved`. This recreates the historical false-green path whenever the reviewer approves an external-boundary narrative.
2. `performNodeTurn` stores `eligibleElapsed` into the per-iteration `activeSeconds` before review, regardless of the worker marker or review result.
3. `GraphLoopNode.liveActiveSeconds` sums every per-iteration duration—approved, rejected, blocked, superseded, and pending—then adds a legacy baseline. Consequently the node UI can still display rejected/blocked time as total active work even when `accumulatedActiveSeconds` was reconciled downward.
4. The repeated-blocker rule only recognizes the exact free-form marker and only counts prior records whose review decision is `continueWork`. It does not establish a durable typed worker outcome, and approval can still overwrite the contradiction.
5. Completed historical nodes decode without migration or a contradiction flag, so old impossible states remain visually indistinguishable from valid completion.

## Required redesign contract

The refactor must model these signals separately and make invalid combinations unrepresentable:

- `executionStatus`: `completed | continue | blocked | failed | interrupted | malformed`;
- `reviewStatus`: `approved | rejected | externalDependencyAccepted | needsReplan`;
- `timeDisposition`: `countedActive | excludedBlocked | excludedRejected | excludedFailure`;
- a blocked execution may never become ordinary `approved`; it may only become `externalDependencyAccepted`, and only after deterministic evidence classification;
- rejected and blocked durations remain in an audit ledger but never contribute to accepted active-work totals;
- the UI shows accepted total time and the current eligible live segment separately, with excluded time disclosed separately;
- three equivalent blocked/rejected strategies trigger retirement by causal fingerprint, not merely by identical wording;
- checkpoint migration marks contradictory historical records and recomputes display totals without rewriting the source evidence.

The machine-readable companion scorecard is `STATUS_ACCOUNTING_SCORECARD.json`; the raw per-node derivation is `evidence/node-iteration-metrics.json`.
