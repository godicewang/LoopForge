# Bounded Effect Dispatch Retirement

Status: **implemented and regression-tested; explicit repair remains separate**

## Defect

The outbox could durably quarantine failed ownership and expired authority, but
most other runtime errors remained `pending` forever. Deterministic invalid
requests were rescanned despite no possible state change. Journal, projection,
and release failures had legitimate crash-recovery value, but no durable retry
budget. An executor exception was first written as failed ownership yet still
needed a second dispatcher pass before retirement. These paths reproduced the
same unbounded control shape found in the stopped Graph.

## Error policy

The dispatcher now applies an exhaustive typed policy:

- deterministic pre-effect rejection (`actorMismatch`, missing transaction,
  intent mismatch, invalid phase, missing/rejected authority) is quarantined on
  its first observation;
- executor failures are quarantined on the same pass, because the runtime has
  already journaled failed ownership before returning those errors;
- failed ownership and expired-authority retirement remain immediate;
- journal write, journal projection, and authority release errors retain exact
  crash-replay semantics but consume one durable attempt; and
- the third retryable failure quarantines the entry, preventing a fourth
  ordinary dispatch.

Outbox schema v5 adds the `retryScheduled` state with canonical failure digest,
attempt count, and last-attempt timestamp. The maximum dispatch-attempt budget
is positive and explicit in `WorkspaceMutationEffectOutboxLimits`, defaults to
three, survives restart, and cannot be reset by re-enqueueing an identical
intent. Quarantine is still not completion, does not mint authority, and leaves
any unresolved ownership for explicit repair.

Valid schema-v3 and schema-v4 snapshots are verified using their own original
schema and digest before in-memory normalization. The next successful write
persists schema v5.

## Verification

The real dispatcher integration now proves a bad executor identity is
quarantined on the first scan and absent from the second scan. The filesystem
outbox test proves attempt counts one and two remain recoverable, the third
failure becomes quarantine, restart does not reset the budget, and pending is
empty after exhaustion. The persisted schema-v3 fixture also proves a
successful rewrite upgrades to schema v5.

Focused integration/filesystem tests passed: 21 tests, 0 failures. The complete
suite passed: 506 tests, 8 environment-gated skips, 0 failures. The full log is
`/tmp/loopforge-full-tests-dispatch-retirement.log`, SHA-256
`4ddf34a741b69b5a04270907f5b08f0575fb21bc32cd27706aa3f924dfc4ac4d`.

The corrected source was rebuilt as an arm64 release app. Deep strict signature,
plist, architecture, checksum manifest, ZIP, DMG, and model-weight exclusion
checks passed. Native UI remains blocked by the macOS lock and is not claimed.

## Remaining boundary

Quarantined entries need explicit evidence-bound repair/replan APIs and UI.
Production startup still does not own or invoke this dispatcher, and the legacy
controller remains disconnected from the new kernel. Current native screenshots,
commit, push, and revision-bound final package remain unfinished. EasyBusiness
was not mutated and the stopped Graph was not resumed.
