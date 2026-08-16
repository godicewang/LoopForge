# Pre-effect Expired-Authority Retirement

Status: **implemented and regression-tested; explicit replan remains separate**

## Defect

The journaled workspace runtime checked wall and monotonic lease lifetime before
entering the filesystem executor, but an expired request only returned an
authority error. The admitted canonical-root lease remained live in the journal
and supervisor, and the durable outbox entry remained pending. Every ordinary
recovery scan could therefore rediscover the same request, reject it again, and
make no state transition. No file was changed, but the controller still had a
non-convergent retry strategy and could never become quiescent.

## Retirement protocol

Apply and rollback now prove that the request, preimage, intent, transaction,
workspace, canonical root, and admitted receipt all claim the same transported
lease before any expiry cleanup is possible. When the wall clock or the trusted
authority rejects that exact lease as expired, the runtime:

1. invokes the existing journal-first release using the original sealed release
   receipt and command identities;
2. requires the supervisor to reconcile the same release;
3. returns the typed `preEffectRejectedAndReleased(.leaseExpired)` result;
4. lets the dispatcher durably quarantine—not complete—the effect; and
5. excludes that effect from all later ordinary pending scans.

The protocol cannot renew or mint authority, does not enter the executor, does
not create a recovery directory, does not touch the workspace, and does not
pretend that the requested mutation completed. A new plan must explicitly
obtain fresh authority and a new intent.

## Verification

The integration fixture first releases the prior failed-ownership lease, then
admits a fresh short-lived lease through the real journal/supervisor authority.
It dispatches the exactly bound effect after both wall and monotonic expiry and
proves:

- first scan count is one and the typed failure is exact;
- the outbox entry is quarantined;
- the journal no longer owns the canonical-root lease;
- the supervisor has neither a live lease nor failed-release marker;
- the executor recovery root was never created; and
- the second ordinary recovery scan count is zero.

The same verification slice also persists a valid schema-v3 outbox snapshot
with its original digest, restarts through the v4 reader, and proves the next
successful write upgrades the persisted schema to v5. This is real on-disk
migration coverage rather than an in-memory normalization assertion.

Focused integration/filesystem tests passed: 21 tests, 0 failures. The complete
suite passed: 506 tests, 8 environment-gated skips, 0 failures. The full log is
`/tmp/loopforge-full-tests-dispatch-retirement.log`, SHA-256
`4ddf34a741b69b5a04270907f5b08f0575fb21bc32cd27706aa3f924dfc4ac4d`.

The corrected source was rebuilt as an arm64 release app. Deep strict signature
verification, plist lint, ZIP integrity, checksum-manifest verification, DMG
CRC verification, and model-weight exclusion all passed. Native UI verification
remains blocked by the macOS lock and is not claimed.

## Remaining boundary

Other pre-executor failures remain fail-closed and pending because they do not
yet have a generally safe cleanup proof. In particular, actor mismatch,
transaction absence, intent mismatch, missing authority, and non-expiry
authority rejection require separately typed retirement or repair protocols.
Production dispatcher startup ownership, evidence-bound failed-ownership repair,
legacy controller cutover, current native screenshots, commit, and push remain
unfinished. EasyBusiness was not mutated and its stopped Graph was not resumed.
