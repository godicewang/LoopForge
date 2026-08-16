# Typed Interval Ledger Implementation

Status: **implemented side-by-side; fourteen focused tests and full suite green**

## Outcome

The third kernel slice implements the duration semantics that the stopped Graph
and the user-visible node cards lacked. It projects two different values:

1. cumulative accepted duration across every closed accepted round;
2. the current attempt's retained duration plus its live monotonic segment.

The live segment advances only when an owned execution exists, the invocation
and provisional disposition are eligible for the immutable policy, the boot
session matches, and the supplied monotonic instant is not earlier than the
segment start. A pause retains the current attempt's completed segments without
animating. Relaunch, reboot, sleep, wall-clock movement, or absence of a live
segment cannot invent time.

## Typed adjudication

Every closed occurrence carries invocation kind, boot/session-bound monotonic
clock receipt, outcome, interval disposition, and evidence receipt IDs. The fold
enforces these rules:

- scheduled-only policy rejects manual work;
- recovery, verification, adaptive review, and owner amendment never satisfy
  ordinary execution coverage;
- failed, cancelled, blocked, empty, unverified, sleep, downtime, duplicate, and
  invalid intervals are excluded under distinct reasons;
- an accepted outcome without evidence is reclassified as unverified;
- a duplicate occurrence cannot be counted twice;
- a wall-clock shift does not alter monotonic elapsed time;
- a reboot or monotonic reset breaks live coverage;
- a cadence gap or missing ordinal starts a new continuity segment but never
  fabricates elapsed duration;
- every contribution names its occurrence, receipt, predecessor, segment, and
  exact monotonic subtraction formula.

All arithmetic is saturating at `UInt64.max`, eliminating underflow and overflow
as sources of false coverage.

## Verification

- targeted interval suite: 14 tests, 0 failures;
- full Swift suite: 354 tests, 6 intentionally skipped integration tests,
  0 failures;
- cumulative-versus-current, pause, reboot, manual/scheduled separation,
  interactive policy, non-execution invocations, typed failures, discontinuity,
  clock shift, cadence gap, ordinal gap, duplicate, underflow, and evidence
  binding are covered;
- vertical-policy scan: zero application, industry, repository, UI genre, or
  provider-specific matches;
- EasyBusiness remained read-only.

## Boundary

The legacy `GraphLoopNode` view helper still uses `Date`; this new ledger is the
ratified replacement but is deliberately side-by-side until the runtime
supervisor can emit real occurrence receipts. Wiring a view directly to the new
types before that event source exists would merely repaint legacy guesses.
