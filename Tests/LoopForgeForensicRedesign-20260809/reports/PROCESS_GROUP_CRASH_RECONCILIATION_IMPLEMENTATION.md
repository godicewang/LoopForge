# Process-Group Crash Reconciliation Implementation

Status: **exact bound-process recovery plus fresh-supervisor journal hydration implemented side-by-side; unbound launch window remains fail-closed; no controller cutover**

## Outcome

The native process adapter can now reattach after an in-process runtime owner
restart only when three independent facts match the journaled lease: exact PID,
the operating system's process start timestamp, and the requirement that the PID
is still its own process-group leader. It never searches by executable name and
never signals a process when any identity field is absent or mismatched.

New launches persist both the monotonic observation used for receipt ordering
and the OS process start timestamp used to detect PID reuse. The stable identity
digest is bound to the executable path, PID, and OS start timestamp. Recovered
processes use a non-child dispatch exit observer; they do not call `waitpid` on
a process they do not own as a child.

## Reconciliation outcomes

1. An exact PID/start/group match reattaches the journaled lease and permits
   exact group termination through the existing journal-first release path.
2. If the exact bound PID no longer exists, the bridge records a journal-first
   absence release before removing the supervisor lease.
3. If the PID exists with another start timestamp or is no longer its own group
   leader, the lease remains live and in doubt; no signal is sent.
4. A legacy binding without an OS start timestamp remains live and
   unverifiable; it is never treated as recovered or absent.
5. A journaled admission without any external binding remains live and in
   doubt. The implementation does not scan the host to guess which process, if
   any, belongs to it.

## Fault injection

- a live 30-second process is recovered by a fresh adapter using the exact
  journaled OS start identity, then terminated as one process group;
- a one-nanosecond start-identity substitution is rejected while the original
  process remains alive and untouched;
- a missing identity and an already exited PID produce distinct errors;
- the journal bridge reattaches an exact bound process and terminates it;
- a natively drained but logically bound process produces a journaled absence
  release;
- an unbound admission remains in the supervisor and journal with an in-doubt
  and failed-release marker.

## Verification

- process-adapter tests: 9 executed, 0 failures;
- journal/native bridge tests: 12 executed, 0 failures;
- complete Swift suite: 377 executed, 6 intentionally skipped integration
  tests, 0 failures;
- `git diff --check`: clean;
- no fault-injection child remained after verification;
- EasyBusiness remained read-only.

## Boundary

This does not make process creation and journal binding atomic. A host crash in
the interval after native spawn but before external binding still leaves an
unbound admission with insufficient identity to signal safely. Closing that
window requires a durable launch broker or helper handshake that publishes an
exact start identity and self-terminates on coordinator loss. Fresh-supervisor
journal hydration is now implemented and exercised by these reconciliation
tests. Legacy controller shadowing, other runtime adapters, and final cutover
remain outstanding.
