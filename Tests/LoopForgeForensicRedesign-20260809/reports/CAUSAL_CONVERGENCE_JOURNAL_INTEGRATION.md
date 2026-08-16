# Causal Convergence Journal Integration

Status: verified side-by-side transaction path; legacy execution remains disconnected.

## Result

The convergence governor is now part of `KernelRunState` and the single `RunJournal` command/event stream. These facts can no longer disappear on process restart:

- convergence epoch and immutable multidimensional budget;
- admitted attempt and strategy consumption;
- causal failure counts;
- active and retired strategies;
- visual/product damage events and admission freeze;
- external-condition waits;
- causal replacement authorization receipts;
- accepted or zero-progress attempt closure;
- consumed plan-expansion budget.

## Journal-first boundary

Seven typed command families preview the transition against a copy of the recovered governor and emit one causal delta only when accepted. `RunJournal` then appends and synchronizes the hash-chained frame before publishing the new reducer state. A duplicate command returns its original transaction receipt. A second journal actor on an obsolete head is rejected by the existing `flock` plus sequence/hash fence.

The event does **not** contain a serialized governor snapshot. Recovery replays the typed delta through the same pure transition. An invalid delta cannot advance the event sequence, so journal recovery rejects it as an invalid event sequence. This avoids reintroducing the history-sized checkpoint rewrite and high-frequency persistence amplification identified during the forensic audit.

## Fault tests

Three new journal tests prove:

1. attempt budget is durable before a worker could be launched, and duplicate command replay leaves attempt/strategy counts at one;
2. deterministic failure retirement, the causal failure count, replacement authorization receipt, and successor admission survive two fresh `RunJournal` constructions;
3. a stale concurrent journal actor cannot append a different strategy from the obsolete budget head, and recovery sees only one consumed attempt/strategy.

The admission frame is also inspected as text: it contains `attemptAdmitted` but not `activeStrategies`, `retiredStrategies`, or `replacementAuthorizationReceipts`, guarding against accidental snapshot write amplification.

## Verification

- Focused convergence/reducer/journal suite: 39 tests, 0 failures.
- Complete Swift suite: 394 tests, 6 environment-gated skips, 0 failures.
- `ConvergenceGovernor.swift`: 617 lines, SHA-256 `5cca24f544c6c7658ca7d7cdb4dd466f4fd68279bbd3326afcfb885705599767`.
- `RunReducer.swift`: 1,054 lines, SHA-256 `07727575b6e652a4fc1965dcbb9280e0c514002628b1b9c9e2823a73dddbf60e`.
- `RunJournal.swift`: 368 lines, SHA-256 `863b35a48aa05375301a7261436ab1d48c4cd988a6d240253abd4a451975b599`.
- `RunJournalTests.swift`: 544 lines, SHA-256 `69deb778bdea1b0ba017fdffd93c5424e28b662723ea3e0b202140e0f637b040`.

The first focused journal test build failed only because `await` appeared inside `XCTUnwrap`'s synchronous autoclosure. It did not execute production code and is excluded from the strict ledger. The test now awaits the actor snapshot before synchronous unwrapping.

## Open boundary

The legacy controllers do not yet call these commands, so this report is not a claim that Auto Graph currently benefits from the governor. Historical shadow replay, adapter/cutover work, native UI exposure, final packaging, native verification, commit, and push remain open.

