# Journaled Process Runtime Bridge Implementation

Status: **journal-first admission/binding/release plus exact bound-process reconciliation implemented side-by-side; twelve focused tests and full suite green; no controller cutover**

## Outcome

The native process-group adapter is now connected to the hash-chained run
journal through a side-by-side coordination actor. Admission is previewed
without mutation, durably journaled, and only then committed to the runtime
supervisor. A process launch can proceed only when the journal and supervisor
contain the identical run/resource/lease record. The bridge then journals the
exact external process identity before committing that binding to the
supervisor.

On termination, native whole-group drain occurs first, but logical ownership is
released journal-first. If the journal cannot durably publish the release, the
supervisor keeps the lease and marks cleanup as failed. Native cleanup success
therefore cannot silently turn a stale or poisoned writer into false
quiescence.

## Enforced behavior

1. Journal and supervisor ownership must match byte-for-byte before native
   launch or termination.
2. Command sequence is captured inside the journal actor, eliminating the race
   created by reading sequence outside the single writer.
3. External identity binding is previewed without mutation, written as a
   boundary-durable journal transaction, then committed to the supervisor.
4. Release is previewed without mutation, journaled, and only then removes the
   supervisor lease.
5. Binding-write failure compensates the newly launched process group and keeps
   the logical lease plus an in-doubt/failed-release marker.
6. Release-write failure leaves the journal and supervisor lease live even when
   the native group was already drained.
7. Native termination failure generates a deterministic, non-secret type
   digest and attempts to journal a cleanup-failure receipt before returning.
8. A separate in-doubt projection makes partial coordination visible; it is not
   interpreted as success or auto-retried.
9. Invalid process specifications reject before admission; durable admission
   rejection never invokes the native launcher.
10. If native spawn fails after admission, an explicit journal-first release
    transaction removes the unmaterialized lease from the supervisor. The
    failure cannot leave invisible capacity reserved.
11. Recovery reattaches only to an exact PID/OS-start/process-group identity;
    absence journals a release, while missing or mismatched identity stays
    live and in doubt without signalling.

## Adversarial verification

- happy path replays a bound external identity and an exact release from a new
  journal instance;
- substituted lease identity rejects before any native process is launched;
- a second journal writer advances the on-disk head immediately before binding:
  the stale writer fails, the process is compensated, and ownership remains;
- a second writer advances the head immediately before release: the process
  drains, but journal and supervisor ownership remain live and failed rather
  than manufacturing an empty projection.
- a second writer advances the head immediately before admission: neither the
  supervisor nor the native launcher is mutated;
- an executable file with valid permissions but invalid contents drives the
  real `posix_spawn` failure path, records an exact release, and frees the
  reservation on replay;
- a durably rejected admission never reaches native launch.

## Verification

- bridge race/failure/reconciliation suite: 12 tests, 0 failures;
- native process-group suite: 9 tests, 0 failures;
- complete Swift suite: 377 tests, 6 intentionally skipped integration tests,
  0 failures;
- journal-first bridge source: 431 lines; bridge tests: 662 lines;
- `git diff --check`: clean;
- EasyBusiness remained read-only.

## Boundary

Exact bound identities now reconcile without executable-name scans, but a crash
after native spawn and before binding still leaves an unbound admission that
cannot safely identify a process. Fresh-supervisor journal hydration is now
implemented; a durable launch broker/helper handshake remains required. Other
runtime adapters, legacy controller shadow comparison, and production cutover
remain outstanding.
