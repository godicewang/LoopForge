# Causal Convergence Governor Implementation

Status: side-by-side kernel and hash-journal integration verified; legacy Graph cutover is not authorized by this report.

## Outcome

LoopForge now has a pure, codable convergence governor that makes the stopped run's seven-turn failure structurally finite. It does not inspect prompt wording and does not treat a new node, attempt, thread, model, or title as strategy novelty.

The implementation is in `Sources/LoopForge/Kernel/ConvergenceGovernor.swift`. Fourteen focused tests are in `Tests/LoopForgeTests/ConvergenceGovernorTests.swift`.

## Enforced invariants

1. Strategy identity is a SHA-256 digest over length-prefixed, sorted, typed causal fields: requirement ownership, hypothesis, action, workspace topology, capability route, evidence sources, measurement boundary, verification oracles, mutation surface, baseline revision, expected observations, falsification predicates, and inherited lessons.
2. Display prose, attempt/node/thread/model identity, and set insertion order cannot alter that fingerprint.
3. Every worker admission consumes a durable attempt token before work and requires a predicted observation, falsification predicate, rollback point, and remaining mutation/verification/external-effect budget.
4. Two equivalent attempts cannot be live concurrently.
5. A deterministic implementation failure retires its strategy immediately. A successor cannot start until a durable replacement authorization receipt proves a machine-checkable causal-axis change related to the failure.
6. The same causal failure has a global ceiling of three observations across replacement strategies. The third retires the current strategy and prevents another replacement authorization.
7. Confirmed authority/scope/topology mismatch, authoritative evidence absence, and protected invariant/baseline regression never receive an ordinary worker retry.
8. A protected visual/product regression requires rollback, retires the damaging strategy, consumes damage budget, and can freeze all later mutation admission.
9. Reviewer protocol/transport failure never relaunches the worker. Two reviewer retries are allowed; the third enters a non-runnable protocol-repair wait.
10. External-service and host-capacity waits consume no new attempt token and cannot wake until a different condition receipt is observed.
11. Plan expansion consumes a finite token and cannot mint attempt, strategy, mutation, verification, damage, or side-effect budget.
12. Codable round-trip and hash-journal replay preserve consumption, retired strategies, causal failure counts, waits, and replacement authorization receipts.
13. Progress is a partial order with hard vetoes: a protected-invariant regression, requirement regression, new blocker, or new verifier failure cannot be offset by unrelated positive counts.
14. Journal events carry minimal typed deltas rather than full governor snapshots, preventing history-sized write amplification.
15. Duplicate commands replay their original receipt without consuming another token; an actor on a stale journal head cannot fork strategy or attempt budget.

## Historical failure mapping

| Stopped-run failure | New decision |
|---|---|
| immutable write scope or wrong worktree/cwd | retire on first confirmed fingerprint; require topology/capability/mutation-surface delta |
| missing historical PNG bytes | retire and wait for a new evidence-source receipt; no polling worker |
| damaging typography/shape/density change | rollback, retire, consume damage budget, freeze when exhausted |
| unchanged deterministic verifier failure | distinct causal replacement only; third equivalent failure is terminal for automatic replacement |
| reviewer parse/provider failure | retry reviewer only; third enters protocol-repair wait |
| thermal/resource pressure | host-state wait with no worker, power lease, or accepted-time credit |
| renamed node/thread/attempt or paraphrased objective | identical causal fingerprint and unchanged durable budget |

## Verification

- Focused suite: 14 tests, 0 failures.
- Full Swift suite: 394 tests executed, 6 environment-gated skips, 0 failures.
- Source: 617 lines, SHA-256 `5cca24f544c6c7658ca7d7cdb4dd466f4fd68279bbd3326afcfb885705599767`.
- Tests: 455 lines, SHA-256 `df3f87b2c98810aa5732183d18e20e967ea48d4a016f55174b2c468ab25dece4`.
- Journal integration: `RunReducer.swift` 1,054 lines / `07727575b6e652a4fc1965dcbb9280e0c514002628b1b9c9e2823a73dddbf60e`; `RunJournal.swift` 368 lines / `863b35a48aa05375301a7261436ab1d48c4cd988a6d240253abd4a451975b599`; `RunJournalTests.swift` 544 lines / `69deb778bdea1b0ba017fdffd93c5424e28b662723ea3e0b202140e0f637b040`.
- `git diff --check`: clean.

One focused run exposed that replacement-delta rejection was evaluated before the global visual-damage freeze. That failed run is excluded from the active-work ledger. The gate order was corrected, and both the focused and complete suites then passed.

## Deliberate boundary

This slice is not wired into `GraphLoopEngine`, `LoopController`, Single Loop, or Watcher. It has not modified EasyBusiness. It does not claim that the current packaged app contains this source revision. Remaining required work includes historical shadow replay, controller cutover, receipt-native UI, immutable visual gates, transactional mutation/integration, a new signed package, native verification, commit, and push.
