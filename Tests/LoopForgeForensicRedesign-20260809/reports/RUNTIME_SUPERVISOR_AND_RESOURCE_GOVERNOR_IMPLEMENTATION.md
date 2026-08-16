# Runtime Supervisor and Resource Governor Implementation

Status: **side-by-side supervisor, journaled lifecycle receipts, and first native adapter implemented; full suite green; no controller cutover**

## Outcome

The third cutover gate now has a domain-neutral owner registry and host-relative
admission governor. Existing Loop, Graph, and Watcher controllers remain on the
legacy path while this slice proves the lifecycle semantics independently.

Runtime admissions, external identity bindings, cleanup outcomes, drain
snapshots, and quiescence now have typed receipts accepted by the same reducer
and hash-chained journal as task lifecycle events. The journal projection
reconstructs live ownership, failed releases, drain intent, and terminal
quiescence without trusting controller booleans or cleanup prose.

Every runtime handle is represented by a stable run/resource/lease identity,
generic resource kind, purpose, ownership mode, release policy, optional
external identity, and seven-dimensional reservation vector. The actor retains
leases until an exact lease token is released; dropping a controller task or
forgetting a PID cannot remove ownership from its projection.

## Enforced behavior

1. Admission reserves CPU, memory, disk, GPU, network, GUI-session, and process
   capacity atomically; overflow or dimension overrun fails closed.
2. Fair/low-power policy halves heavy capacity without turning a zero-capacity
   dimension into nonzero authority.
3. Serious/critical/memory-critical pressure rejects new productive work while
   bounded cleanup can use unused nominal capacity.
4. A drain rejects new productive leases, cancels queued productive lease IDs,
   retains live ownership, preserves cleanup work, and can escalate from pause
   to stop/quit but cannot downgrade.
5. Quiescence is issued only during drain, with no live resources and no failed
   releases. A stale release token cannot erase the current owner.
6. Acquire and release are idempotent and return the original lease/receipt.
7. Borrowed resources require a nonempty stable external identity and
   detach-only release. Owned resources cannot use detach-only cleanup.
8. External identity binds once; the same PID with a different start identity
   cannot replace the original binding.
9. Cleanup plans distinguish await-join, graceful termination of owned
   resources, and borrowed detach; the supervisor describes actions but does not
   perform destructive operations itself.
10. Power assertions require a recent progress receipt, a future monotonic
    renewal deadline, a novel receipt for renewal, accepting phase, and
    non-serious pressure. Expiry, pressure, or drain makes release mandatory.
11. The bounded queue has stable cleanup/priority/FIFO order, explicit expiry,
    explicit idempotent cancellation, duplicate identity fences, thermal wait,
    admissible-small-request bypass, and drain cancellation evidence.
12. Pause, stop, and completion require an intent-matched drain receipt before
    quiescence. Completion has a distinct request/drain phase and cannot reuse a
    stop or pause receipt.
13. Receipt IDs are globally unique across verification, review, runtime, and
    quiescence facts. Mismatched requests, substituted resources, stale
    monotonic observations, cleanup failures, and forged empty receipts fail
    closed during replay.

## Verification

- targeted supervisor/governor suite: 34 tests, 0 failures;
- runtime/journal integration suite: 5 tests, 0 failures;
- complete Swift suite: 377 tests, 6 intentionally skipped integration tests,
  0 failures;
- supervisor source: 1,174 lines; reducer source: 819 lines; focused supervisor
  and runtime/journal tests: 1,026 lines;
- whitespace validation: clean;
- vertical-policy scan of the new source and focused tests: zero product,
  repository, provider, language, or UI-framework matches;
- EasyBusiness remained read-only.

## Boundary

The first real adapter now wraps exact owned POSIX process groups and has native
TERM/KILL/join fault injection, including leader-exit/descendant-survival and
unrelated-process isolation. Admission, external binding, native-launch failure
release, and normal release now use a journal-first side-by-side bridge. Task,
timer, observer, capability, native-session, persistence, evidence-work, and
power-assertion adapters plus a typed journaled queue, durable containment of
the unbound launch window, and legacy controller shadow/cutover remain mandatory
before this supervisor can be the production source of truth.
