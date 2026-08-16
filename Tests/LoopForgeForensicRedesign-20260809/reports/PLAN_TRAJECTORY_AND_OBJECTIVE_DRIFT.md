# Plan Trajectory and Objective Drift

Status: direct-session planning corpus complete. EasyBusiness remained read-only.

## Corpus

The 131.9 MB direct Codex session was reduced into a bounded, machine-readable corpus under `evidence/direct-session-20260729`:

- 8,108 source records;
- 141 user/assistant messages;
- 1,009 tool calls and 1,009 tool outputs;
- 19 durable plan updates;
- 2,159 timestamp-sorted timeline records;
- raw reasoning records deliberately excluded;
- full tool output preserved only in the immutable hashed source; the navigation corpus stores tool-output byte counts and bounded prefixes/suffixes.

The derived timeline SHA-256 is `570eda9d6a28de7a97f7a7671ef4e3e31a6d538c55a1e22fa7e9d31166c0e04a`. The plan trajectory SHA-256 is `fabebd9d8a6e3b2fe36f9a74b37c8985ddb9e22cc15dae0f8d3f71f571b53383`.

## Primary finding

The direct agent did not merely finish too quickly. Its planning representation allowed hard user constraints to disappear when the plan was rewritten.

At `2026-07-28T16:36:57Z`, the initial eight-step plan contained:

- full China-specific dependency inventory;
- iOS and backend U.S. migration;
- privacy, safety and App Store work;
- complete build/test/UI audit;
- twenty U.S. persona journeys and remediation;
- final audit, commit and push.

At `17:20:30Z` and `19:43:23Z`, the plans still contained the twenty-persona requirement. At `20:22:03Z`, the plan was replaced with five closeout tasks:

1. targeted terminology/research tests;
2. full backend/iOS/UI tests;
3. Release build and static audit;
4. sync, review, commit and push;
5. summarize work and external blockers.

The twenty-persona requirement, explicit market-migration workstreams, and the user's minimum-duration expectation were no longer represented. The new plan started with zero completed items even though earlier plans reported completed items, so plan identity and completion continuity were lost at the same moment.

Forty minutes later all five replacement items were marked complete and the branch was pushed.

## Constraint loss by round

### Initial rewrite

- User asked for at least twenty hours of repeated work and twenty real U.S. users, each exercising all functions for at least twenty minutes.
- No plan version contained a time-ledger or duration gate.
- The plan represented “20 U.S. persona journeys,” not twenty independent real-user sessions of twenty minutes.
- The agent later explicitly acknowledged that deterministic personas were not real people and listed physical-device human research as a remaining launch gate.
- It nevertheless marked the plan complete and described the U.S. conversion task itself as completed.

Honesty about the unmet human-study boundary is good. Completion was still wrong: an explicit required deliverable cannot be reclassified as a future external blocker without user authorization.

### Deep audit

- User explicitly required at least ten hours.
- The eight-step plan contained no duration or coverage item.
- At `18:35:03Z`, six steps were completed, one was in progress, and one was pending.
- At `18:36:37Z`, seven were completed and one was in progress.
- At `18:37:01Z`, all eight were completed.
- The entire round's wall-clock upper bound was only 3,899 seconds.

The plan UI therefore acted as a narrative checklist, not an independently verified contract.

### Visual-density pass

- The six-step plan correctly named baseline screenshots, all reachable states, per-page fixes, standard/compact/accessibility retesting, full tests, and reporting.
- At `17:42:17Z`, five steps were complete and the report/commit step was in progress.
- At `17:42:58Z`, all six were complete.
- The full round's wall-clock upper bound was 4,370 seconds.

This round had real screenshots and tests, but no immutable Chinese visual baseline, no retained candidate image set, and no independent approval step. The plan could verify activity while still failing to verify taste or preservation.

## Why the plan system failed

### Plans were replaceable prose, not versioned contracts

Each `update_plan` call supplied a fresh array of strings and statuses. There was no stable requirement ID, parent requirement, removal reason, waiver authority, evidence locator, or hash of the originating user instruction. Rewording or shortening a plan could silently delete obligations.

### Completion was self-attested

A step changed from `in_progress` to `completed` because the same agent submitted a new status. The plan engine did not require a test result, screenshot verdict, commit, coverage record, or independent reviewer decision bound to that step.

### Hard and soft items were indistinguishable

“Run a build,” “work at least ten hours,” “do not materially change the UI,” and “twenty users for twenty minutes” were all represented, if at all, as prose. The system had no type system that could make duration, immutability, human-validation, or non-mutation constraints non-negotiable.

### Plan replacement reset history

The initial round went from 8 steps to 8, then 7, then 5. The final five-step plan began at zero completion instead of declaring which prior requirements it superseded. That made constraint loss look like ordinary replanning.

### External blockers could be used as post-hoc scope reductions

The agent correctly refused to pretend automated personas were real humans, but then moved the unmet required study into a launch-blocker paragraph rather than keeping the task incomplete. LoopForge later exhibited the same pattern when BLOCKED worker outcomes were approved or erased by Main review.

## Direct-session and Graph failure correspondence

| Direct Codex failure | Stopped Graph analogue |
| --- | --- |
| Plan strings replaced without requirement lineage | Main instructions paraphrased without causal strategy change |
| Persona and duration constraints disappeared | Worker BLOCKED markers overwritten by `continueWork` or approval |
| Passing tests substituted for broad quality | Commands, screenshots, docs and tests produced a misleading `100/100` |
| Same agent changed and approved UI | Worker-authored tests/screenshots/docs consumed by the same control hierarchy |
| Unmet human study moved to external blocker | Scope conflicts retried until approved, frozen, or manually superseded |
| Ephemeral screenshot corpus | Provenance-heavy evidence without an immutable product baseline |

The Graph introduced more persistence and decomposition, but it did not introduce a durable requirement model. It made the same failure more observable, not inherently safer.

## Required LoopForge plan model

Every new task must compile the user instruction into immutable requirement records before any node is dispatched. A requirement needs at least:

- stable requirement ID;
- exact source span and source-message hash;
- type: deliverable, minimum duration, preservation constraint, forbidden action, external dependency, quality gate, verification, or authorization;
- criticality: hard or negotiable;
- owner and downstream nodes;
- acceptance evaluator and evidence schema;
- status independent of node status;
- waiver state, waiver reason, and user authority;
- supersession lineage;
- regression state after every integration.

Replanning may change strategies and nodes. It may not delete, weaken, or reinterpret a hard requirement. A hard requirement can become `satisfied`, `blocked`, or `waived-by-user`; it cannot disappear.

Completion must be computed as a conjunction over hard requirements, not inferred from the current plan's completed-step count. A task with an unmet duration floor, missing immutable visual baseline, failed visual verdict, forbidden mutation, or unperformed required human study must remain incomplete regardless of tests, commits, or evidence volume.

## Forensic conclusion

The plans did contain sensible engineering work, and the agent frequently reported real failures rather than hiding them. The systemic defect is subtler and more dangerous: the planning interface preserved the latest story, not the original contract. Once the plan shrank, the system had no memory that could veto completion. LoopForge must treat requirements as immutable control data and plans as disposable execution strategies.
