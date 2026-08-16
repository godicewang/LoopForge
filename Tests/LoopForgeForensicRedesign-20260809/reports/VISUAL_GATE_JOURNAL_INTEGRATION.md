# Visual Gate Journal Integration and Stable Frame v2

Status: verified reducer/journal authority path; legacy Graph and native capture adapters remain disconnected.

## Result

The immutable visual baseline is now a first-class command/event transaction, not an advisory test artifact. A product-design authority must freeze it against an exact preservation-required `TaskContract` baseline before any attempt starts. Every visual candidate—green or red—is deterministically evaluated and appended to the single hash-chained journal before it affects node or completion state.

For requirements protected by the visual baseline, acceptance is now a three-way intersection on the same attempt and candidate revision:

1. accepted deterministic verification;
2. independent ordinary review bound to that source revision;
3. latest journaled visual gate result for that requirement.

An earlier green cannot survive a later red. A review from another attempt or source revision cannot be joined by requirement name. Missing visual evidence leaves the requirement unaccepted even when ordinary verification and review are both green.

## Baseline freeze transaction

`freezeDesignBaseline` is accepted only while the run is ready, before any attempt exists, exactly once, and when the command actor equals the product-design authority. The reducer validates:

- contract and protected-baseline identity;
- preservation-required artifact digest;
- visual requirement membership in the task contract;
- authority receipt and freeze chronology;
- unique, complete, pre-freeze native captures;
- exact source/artifact/protocol provenance;
- complete protected-invariant capture coverage;
- unique invariants and well-formed known debt.

Recovery replays the same validation before installing the baseline in `KernelRunState`.

## Visual evaluation transaction

`evaluateVisualCandidate` stores the full typed candidate inputs plus a compact `VisualGateEvaluationReceipt`. The receipt binds the attempt, guarded requirements, baseline, candidate source and artifact, canonical evidence digest, evaluator, journal sequence, independent-review receipt, and all twelve dimension results.

During replay the reducer recomputes both the deterministic evidence digest and the complete visual result. A malformed event returns the prior state and causes journal recovery to reject the event sequence. The actual attempt worker lineage is authoritative: a candidate cannot invent a different `workerLineageDigest` to disguise worker self-review.

Node projection exposes whether a baseline is frozen, evaluation count, latest red/green status, and failing-dimension count. A red evaluation is a valid durable fact, sets the node to rejected, and blocks completion; it is not discarded as a rejected command.

## Journal frame v2 root-cause repair

The first crash-recovery test exposed a separate journal defect. Frame v1 recomputed a hash by JSON-encoding decoded events. `JSONEncoder.sortedKeys` sorts object keys but does not canonicalize `Set` iteration or dictionaries with typed non-string keys. The visual candidate contains both, so a valid ninth frame could be written and immediately fail recovery with `brokenHashChain` after collection order changed.

Frame v2 encodes the event array exactly once. Those exact bytes are stored as Base64 `encodedEvents` and are themselves part of the frame hash input. Recovery hashes the retained bytes before reducing their decoded events; it never re-encodes an unordered object to establish identity. This provides:

- byte-stable replay for arbitrary typed event payloads;
- tamper evidence over the exact serialized event input;
- no full state snapshot in journal frames;
- one-command/one-frame atomicity;
- continued duplicate-command and stale-writer fencing.

Recovery remains read-compatible with valid v1 frames. A dedicated test constructs a v1 frame with its legacy digest and restores it. Another test performs an equal-length, valid-JSON replacement of the candidate revision inside v2 `encodedEvents`; recovery rejects the unchanged frame digest as `brokenHashChain`.

## Adversarial tests

Fourteen visual journal integration tests prove:

- authority and protected-artifact baseline binding;
- no baseline freeze after execution starts;
- ordinary verification/review cannot bypass the visual requirement;
- durable red result and completion veto;
- green three-way acceptance;
- latest red revokes older green;
- verification revision mismatch blocks acceptance;
- malformed replay event cannot advance state;
- crash recovery recomputes and restores red status;
- duplicate command idempotency;
- stale writer cannot fork the visual verdict;
- one independent receipt cannot authorize two candidates;
- actual worker lineage defeats forged self-review;
- valid-JSON event-byte tampering breaks the v2 hash chain.

Fourteen `RunJournalTests` additionally pass, including v1 compatibility and decoded minimal-delta inspection. Twelve reducer tests pass. The complete suite executes 444 tests, skips 6 environment-gated tests, and has 0 failures.

## Excluded failures

Five intermediate invocations are excluded from the active-work ledger:

1. a Swift exclusivity compile error in node-status projection;
2. the crash-recovery tests that exposed v1 unordered-collection hash drift;
3. the obsolete outer-NDJSON plaintext assertion after v2 byte encapsulation;
4. a test-build syntax error in the new latest-receipt projection;
5. the first complete suite, whose three old reducer fixtures lacked the newly required matching review revision.

All five were repaired and independently rerun. The successful complete suite is the only full-suite interval counted.

## Exact artifacts

- `DesignBaselineGate.swift`: 736 lines, SHA-256 `34cc44ce9401b383dc45d1fb7b2eae53f15cc85106d1c9e59240dfbd2531cb87`.
- `RunReducer.swift`: 1,342 lines, SHA-256 `6b9019a93c3d5e688a4f63ce2de81bd0812369b2aa13edfd8e8801f8c3180b5b`.
- `RunJournal.swift`: 430 lines, SHA-256 `91d3f0950bc7ff02169bc21016cb2b908caaa84c320c9e6e540248310decec2e`.
- `VisualGateJournalIntegrationTests.swift`: 813 lines, SHA-256 `3d26c3d313c3c46780f4766f284709dd747d2494068b59fa35d25c9d5ec7b511`.
- `RunJournalTests.swift`: 611 lines, SHA-256 `9d96b1bd757e0f53361facada19732ddaaa492097eb4ba76b1f236e32fc2ac4c`.
- Successful full-suite log: `/tmp/loopforge-full-tests-visual-journal.log`.

## Open boundary

The authority path is available only in the side-by-side kernel. Legacy Graph controllers still use their existing mutable execution and evidence collectors. A trusted native capture adapter, Graph-to-kernel command adapter, transactional candidate integration/publication gate, historical shadow replay, receipt-native UI, latest package/sign/hash, native app verification, commit, and push remain open. No completion claim is made.

EasyBusiness remained read-only.

