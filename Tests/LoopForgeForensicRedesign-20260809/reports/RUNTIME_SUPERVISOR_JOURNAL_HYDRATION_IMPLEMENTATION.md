# Runtime Supervisor Journal Hydration Implementation

Status: **journal-head-bound hydration implemented side-by-side; 34 supervisor tests and full suite green; no controller cutover**

## Outcome

A fresh runtime supervisor can now reconstruct its authoritative in-process
ownership registry from the recovered hash-chained journal. The recovery
snapshot is bound to the run ID, journal sequence, and last frame digest. It
contains the retained phase, every live lease, durable successful-release
receipts needed for idempotency, and every failed-release resource.

Recovery is allowed only into a pristine supervisor. It cannot overwrite a
supervisor that has admitted, queued, released, failed, drained, or already
recovered from another journal head. Replaying the exact same head is
idempotent and returns a duplicate recovery receipt; a different head rejects.

## Fail-closed rules

1. Run mismatch rejects before mutation.
2. Duplicate resource IDs, duplicate live lease IDs, duplicate released lease
   IDs, overlap between live and released lease IDs, invalid lease contracts,
   released receipts for live resources, or failed releases without live
   ownership reject the entire snapshot.
3. Recovery retains live reservations even when they exceed the current host
   budget; a lower post-restart budget cannot erase resource debt.
4. A recovered drain phase continues rejecting new productive work.
5. Queued work is not reconstructed because the current journal has no
   queue-admission receipt protocol. Recovery therefore mints no queued work.

## Cross-restart verification

The process reconciliation tests now create a genuinely fresh supervisor,
hydrate it from the journal head, and then:

- keep an unbound admission live and in doubt;
- reattach an exact bound PID/start/group identity and terminate it through the
  journal-first release path;
- journal an absence release when the exact previously bound process has
  already drained.

## Verification

- supervisor/governor suite: 34 executed, 0 failures;
- journal/native reconciliation suite: 12 executed, 0 failures;
- complete Swift suite: 377 executed, 6 intentionally skipped integration
  tests, 0 failures;
- `git diff --check`: clean;
- EasyBusiness remained read-only.

## Boundary

Hydration does not close the spawn-before-binding crash window. That requires a
durable launch broker or helper handshake with coordinator-loss self-cleanup.
The journal also needs a typed queue protocol before queued work can survive a
restart without being guessed. Legacy controller shadow comparison, remaining
runtime adapters, and production cutover remain outstanding.
