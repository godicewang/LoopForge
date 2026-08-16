# Receipt-Native Convergence Diagnostics Implementation

Recorded: `2026-08-11T01:00:28Z`

Status: **source, journal replay, native UI path, full regression, package, and executable-startup receipts present; unlocked native screenshot pending**

## Defect retired

Acceptance row J-04 required Graph to expose a causal convergence diagnosis.
The kernel already retained strategy fingerprints, budgets, failure actions, and
replacement receipts, but `KernelRunProjection` reduced them to aggregate
attempt, strategy, retirement, and damage counts. The production UI therefore
had no receipt-native route for the strategy fingerprint, budget, lesson,
mutation/evidence delta, or replacement cause. The visible legacy Graph fields
were mutable Agent-authored prose and could not safely fill that gap.

## Implementation

`ConvergenceGovernor` now produces a deterministic
`ConvergenceDiagnosticProjection` from accepted reducer state. It contains:

- the exact convergence epoch and journal source sequence;
- maximum, consumed, and remaining multidimensional budgets;
- each admitted strategy's causal fingerprint, requirements, lifecycle,
  attempt identities, mutation/verification/external-effect cost, failure and
  waiting-condition digests, retirement action, and lesson digest;
- the latest accepted or rejected progress delta, including requirements and
  evidence added, blockers/verifier failures/claims resolved, quality
  dimensions added, and protected-invariant regressions introduced;
- replacement authorization receipt identity, predecessor/successor
  fingerprints, failure digests, changed causal axes, predicted observations,
  inherited lessons, and whether the authorization was consumed;
- a canonical projection digest bound to the source sequence.

The optional diagnostic bookkeeping is replayed from typed attempt and progress
events and remains backward-decodable for older snapshots. It is not populated
from node titles, task labels, model output, review prose, filenames, or legacy
Graph checkpoint fields.

Registered new-kernel startup recovery now carries the current
`KernelRunProjection` read from the hash-chained `RunJournal`. `AppModel`
publishes only those recovered projections. When at least one registered run
contains convergence state, the native module header exposes a compact
`Convergence` action and a read-only diagnostic sheet. The sheet renders exact
budget ratios, strategy fingerprints, costs, evidence deltas, retirement
reasons and lessons, replacement axes, authority label, source sequence, and
projection digest. No legacy task can create this button or sheet content.

## Verification

Twenty focused convergence and recovery tests passed. New adversarial coverage
proves that:

1. budget, per-strategy cost, accepted evidence, resolved blockers, retirement
   action, lesson, and replacement axes survive governor encoding and produce
   the same projection digest;
2. changing the source journal sequence changes the projection digest;
3. a registry recovery pass exposes the diagnosis only after replaying typed
   journal transactions;
4. the startup report round-trips with the exact projection intact.

The complete source suite and the packaging-owned suite each passed **541
tests, 8 environment-gated skips, and 0 failures**.

- focused log: `/tmp/loopforge-j04-focused-tests.log`, SHA-256
  `53bf2b7472f0b5d5a435163f7a5a9a2a5fdd0e606348e09d796ad6da541465b4`;
- full source log: `/tmp/loopforge-full-tests-j04-final.log`, SHA-256
  `9cf3f571a42a2eec5b76dd320bb44d6d1080e168b278ee6af28e0cbca9a2887a`;
- package test log: `dist/LoopForge-package-tests.log`, SHA-256
  `f96a45f1248aadf937d01eb77d8123eb78b3b037aeb41bd6d073ff0a858bd085`;
- source snapshot: `6831b8702f374b4a405c8d93977002f621a48126a5dcb682ff186fdd1e4205ba`;
- executable: `4adcab6a40636c6b52989fb8943db361a0693296559462b1dd04eb69ceee3d09`;
- runtime smoke: `/tmp/loopforge-runtime-smoke-j04-final.log`, SHA-256
  `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`.

## Boundary

This retires J-04's source-level authority and visibility contradiction for
registered new-kernel runs. It does not grant legacy Graph state convergence
authority, perform kernel execution cutover, or prove the current sheet through
an unlocked native screenshot. The latest known macOS state remains locked;
no unlock bypass or repeated polling was attempted. Clean commit, push,
current-package native screenshot matrix, and remaining cutover gates are still
required. EasyBusiness remained stopped and read-only.
