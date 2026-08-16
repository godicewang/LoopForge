# Process-Group Runtime Adapter Implementation

Status: **side-by-side native adapter plus admission/binding/release and exact bound-process recovery implemented; 21 focused tests and full suite green; no controller cutover**

## Outcome

LoopForge now has a domain-neutral native process adapter behind the new runtime
lease model. It launches only an exact owned `processTree` lease, creates a new
POSIX process group, records a stable external identity, observes the group
leader with a dispatch process-exit source, and retains ownership until the
whole group—not merely its leader—has disappeared.

The adapter now has a side-by-side journal-first bridge for admission, external
binding, launch-failure release, and normal release. It is not connected to the
legacy Loop, Graph, or Watcher execution paths. This isolates correctness work
from production behavior until journaled shadow comparison and explicit cutover
gates are complete.

## Failure found during implementation

The first implementation treated leader exit as process-tree exit. A shell can
exit while a background descendant remains in the same process group; releasing
the lease at that point would manufacture quiescence and recreate the exact
cleanup defect identified in the forensic audit. The adapter now uses the
leader's event-driven exit receipt only as one fact and separately requires
`kill(-pgid, 0)` to prove that the process group no longer exists. The bounded
backoff check runs only while joining or draining a specific owned group; there
is no global PID scan or permanent polling loop.

## Enforced behavior

1. Only absolute executable paths and exact owned `processTree` leases using
   `gracefulThenTerminate` can launch.
2. Every child is spawned with `POSIX_SPAWN_SETPGROUP` and closed inherited file
   descriptors; standard streams point to `/dev/null` and only the explicitly
   supplied environment is inherited.
3. One resource ID has one lease identity. Repeating the same lease is
   idempotent; a conflicting lease fails closed.
4. Join waits on a dispatch process source and does not release the record until
   the entire process group is gone.
5. Termination signals the negative process-group ID, waits for graceful drain,
   escalates to `SIGKILL` when necessary, and retains ownership on timeout.
6. A stale lease token cannot join, signal, or erase an owned group.
7. No executable-name scan, broad `pkill`, borrowed-resource destruction, or
   unrelated-process cleanup is authorized.
8. Spawn setup reports the actual POSIX error code and cleans partially
   initialized attributes; C-string allocation failure is explicit.

## Fault injection

- invalid path, borrowed ownership, and wrong resource kind reject before spawn;
- a naturally exiting process joins with exit code zero;
- a leader that exits while a 30-second descendant survives causes join timeout
  and keeps the lease visible;
- an exact stale lease cannot terminate the live group;
- a TERM-resistant shell group escalates to SIGKILL and is proven absent;
- an unrelated live `/bin/sleep` process remains running while the owned group
  is terminated;
- duplicate launch with the same lease returns the same handle, while a
  different lease for that resource is rejected.

## Verification

- process-adapter tests: 9 executed, 0 failures;
- bridge race/failure/reconciliation tests: 12 executed, 0 failures;
- complete Swift suite: 377 executed, 6 intentionally skipped integration
  tests, 0 failures;
- adapter source: 558 lines; fault-injection tests: 326 lines;
- whitespace validation: clean;
- new implementation contains no product, repository, provider, language, or
  UI-framework policy (the test target's required `LoopForge` module import is
  the only project-name occurrence);
- EasyBusiness remained read-only.

## Boundary

This slice proves native process-group ownership, drain mechanics, and
journal-first admission/binding/release, including real native launch-failure
compensation. Legacy controller shadowing, task/timer/observer/native-session
adapters, cancellation races, the unbound spawn-before-binding crash window,
typed journaled runtime queues, production cutover, and a revision-bound final
package remain mandatory.
