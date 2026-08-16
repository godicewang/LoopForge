# Failed-Ownership Executor Re-entry Retirement

Status: **implemented and regression-tested; explicit repair remains intentionally separate**

## Defect

The previous failure lifecycle correctly journaled an executor throw as
`cleanupFailed`, retained the canonical-root lease, and blocked quiescence. It
did not, however, make that durable failure an execution veto. While the
original lease remained valid, the next outbox recovery could validate the same
lease and enter the same executor again. After lease expiry, the same pending
entry could still be scanned repeatedly and fail at authority validation. This
was the same control-shape as the historical non-convergent loop: durable
failure was visible but did not retire the ordinary strategy.

The unsafe sequence was:

1. dispatch a pending workspace effect;
2. executor throws before returning a typed apply or rollback receipt;
3. journal and supervisor retain `cleanupFailed` ownership;
4. outbox entry remains `pending`;
5. later recovery scans the same entry and can re-enter the executor or repeat
   an authority rejection.

## Implementation

`JournaledWorkspaceMutationRuntime` now derives the exact canonical-root
resource identity and consults the journal's failed-release set before any new
executor entry. An effect with failed ownership returns the typed
`failedOwnershipRequiresRepair(resourceID)` error. Recorded apply or rollback
receipts remain ahead of this check so their existing idempotent release-only
recovery path is preserved.

`WorkspaceMutationEffectOutbox` schema v5 retains a durable `quarantined` state
with the canonical failure digest and quarantine timestamp. The dispatcher
quarantines `failedOwnershipRequiresRepair` entries on first observation and
reports their intent IDs. Quarantined entries remain reconstructable but are
excluded from `pending`; the next ordinary recovery scan is therefore empty.
They cannot be mislabeled as completed, and conflicting quarantine writes fail
closed. A persisted valid schema-v3 snapshot is now rewritten in the filesystem
test with a recomputed v3 digest, restarted through the current reader, and
upgraded to persisted schema v5 on the next successful write. The compatibility claim
therefore covers the real disk format, not only in-memory normalization.

This is strategy retirement, not repair. It deliberately creates no new lease,
does not clear failed ownership, does not inspect or overwrite the workspace,
and does not acknowledge the effect as completed. A separate, independently
evidenced repair workflow is still required.

## Verification

The authority integration test now stages journal/supervisor cleanup failure,
then proves all of the following:

- direct runtime replay returns the exact failed resource identity;
- the executor recovery directory is never created;
- first dispatcher recovery quarantines the intent;
- second dispatcher recovery scans zero entries;
- the durable entry remains `quarantined`, not `completed`;
- explicit journaled release can still reconcile the ownership afterward.

Focused integration/filesystem tests passed: 21 tests, 0 failures. The complete
suite passed: 506 tests, 8 environment-gated skips, 0 failures. The full log is
`/tmp/loopforge-full-tests-dispatch-retirement.log`, SHA-256
`4ddf34a741b69b5a04270907f5b08f0575fb21bc32cd27706aa3f924dfc4ac4d`.

The corrected current source was rebuilt as an arm64 release app. Deep strict
signature verification, plist lint, checksum-manifest verification, and DMG
CRC verification passed. Native UI capture remains blocked by the macOS lock
and is not claimed.

## Remaining boundary

The generic explicit repair/renewal protocol, non-expiry pre-effect rejection,
production run registry, startup dispatcher ownership, receipt-native UI,
legacy controller cutover, commit/push, and current native screenshots remain
unfinished. Legacy Graph remains disconnected, and EasyBusiness was not
mutated.
