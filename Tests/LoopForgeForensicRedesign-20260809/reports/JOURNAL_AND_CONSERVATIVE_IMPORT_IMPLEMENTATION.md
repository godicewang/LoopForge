# Journal and Conservative Import Implementation

Status: **implemented side-by-side; ten journal/import tests green; no legacy cutover**

## Outcome

The second kernel slice replaces mutable-snapshot assumptions with a compact,
append-only transaction journal. One command and every event produced by that
command are encoded in one sorted-JSON newline frame. Each frame binds the run,
command, prior frame digest, complete event list, and its own SHA-256 digest.
Recovery accepts a complete transaction or ignores only an unterminated final
fragment; a complete malformed frame, broken chain, duplicate command, duplicate
event, run mismatch, or event-sequence mismatch fails closed.

The journal is an actor and also takes an advisory file lock before every append.
While holding the lock it replays the on-disk head and compares both sequence and
digest with its in-memory head. Two actors or processes therefore cannot fork a
run from the same sequence. A stale writer is poisoned after the rejected write.
The writer also refuses to append behind an unresolved partial frame, preventing
a valid transaction from being concatenated into corrupt trailing bytes.

Idempotency is receipt-based: a repeated command ID returns the original event
and frame receipt without reevaluating the command or appending another frame.
Boundary durability calls `synchronize()` before publishing the next in-memory
state.

## Legacy boundary

`LegacyTaskImporter` hashes raw bytes and imports selected legacy fields only as
claims and duration observations. It never creates kernel state, receipt IDs,
accepted seconds, or auto-resume authority. Scalar top-level JSON is rejected.
This preserves forensic evidence without granting old prose, status, scores, or
wall-clock durations causal authority.

## Verification

- targeted journal/import suite: 10 tests, 0 failures;
- latest complete Swift suite: 377 tests, 6 intentionally skipped integration
  tests, 0 failures;
- cross-actor stale-head, trailing-fragment, duplicate-frame, corruption,
  transaction atomicity, replay, idempotency, and legacy-import cases covered;
- vertical-policy scan: zero application, industry, repository, or UI-specific
  terms in the kernel slice;
- EasyBusiness remained read-only and was not invoked by this implementation.

Three early journal test attempts exposed a multiline literal compile error, an
async XCTest-autoclosure error, and missing scalar-fragment normalization. They
were repaired and explicitly excluded from accepted verification time.

## Boundary

The journal now has a side-by-side process admission/binding/release bridge,
including an explicit release transaction for native launch failure, but it is
not wired into the legacy Loop, Graph, or Watcher controllers. No automatic
migration or execution cutover occurs. Exact bound-process reconciliation is
implemented, and a fresh supervisor can hydrate from the journal head. Snapshot
compaction, a typed runtime queue protocol, the unbound launch crash window,
remaining runtime adapters, and controller shadowing remain gates.
