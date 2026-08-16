# Journal-Bound Accepted-Progress Time

Status: **F-02 kernel interval/journal receipts present; production enrollment cutover pending**

Recorded: `2026-08-11T06:12:11Z`

## Defect confirmed

`IntervalLedger` accepted an entire scheduled or interactive interval whenever
execution reported `succeeded` and attached any evidence receipt. It did not
require the convergence reducer to have evaluated a real progress delta.
Successful exit, screenshots, or Agent prose could therefore count time even
when no requirement closed, no blocker or verifier failure resolved, and no
accepted evidence or quality dimension advanced.

## Repair

- each closed occurrence may bind one explicit progress transaction receipt;
- `RunJournal` projects IDs only for hash-chained
  `progressEvaluated(accepted: true)` transactions;
- the ledger accepts duration only when the occurrence's exact progress ID is
  present in that authoritative projection;
- missing, legacy, forged, or `accepted: false` progress IDs fail closed as
  `excludedNoProgress` with `acceptedWithoutProgress` diagnostics;
- evidence binding, execution outcome, invocation class, duration policy,
  monotonic clock, duplicate, sleep, and downtime gates remain independently
  mandatory;
- live-attempt time stays provisional and separate from cumulative accepted
  time until a closed receipt passes every gate.

## Adversarial verification

A succeeded five-second scheduled occurrence with evidence but no accepted
progress contributes zero accepted seconds and five excluded-no-progress
seconds. Journal replay contains both an accepted progress transaction and a
later stagnant `accepted=false` transaction; only the former is projected as
time authority.

## Verification

- interval suite: **15 tests, 0 failures**;
- journal suite: **15 tests, 0 failures**;
- complete source suite: **599 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **599 tests, 8 environment-gated skips, 0 failures**;
- release build, ad-hoc signature, exact source/test manifest, ZIP, DMG,
  checksums, executable startup, cleanup, and zero residual packaged processes
  verified.

Receipts:

- source snapshot: `8bcfb543788451ffe5d5200b88ece67443824c60900a1a49d0c37c59293e2257`
- interval source: `31e9a73b8c4f8e9d1c6815ba0ef1dd47647a67f48fe2df9a49ba8d5f1bc2b819`
- journal source: `1e6303ba83a1a6ec192ac458264461894dde0e731c5d02f0c6bc6bfbe5b184e5`
- interval tests: `6f5b3488c055306b565cd6b211567dd68c6af9cfcae6e3c9adafbb2e689df811`
- journal tests: `748849c2735db721cd254e617107513d01e801165ab2e02b05307a6e33c52a56`
- interval log: `a5c898997d70bb0999096a20dee2676ef35c252dd9bbee2006c9993b5320ab11`
- journal log: `b39efd8dc183296b67f5fb104f950a421c582f13a0002859336cc6e5c9b6d8c7`
- package test log: `7e00b5c082688d9e9ca69ae96994a3ddae88f2482f9b1e7c92c3c3a8dab74959`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `5399f85d55b727addcc370fa8d86171a6328f9572792fffe2764bf0889228877`
- executable: `f9049dd361b0386959146752eb189e838e455e2a314911c562a21cf7b4ab568b`
- ZIP: `1da32f0404a655ca9d22dbe90f3902c4200f690c2176d5b4729dad55eda8a710`
- DMG: `f2f63f5114fb1cf26b21a30e0f769b2ac48fa3c5375477826130d4062af5b830`
- CDHash: `d3b1ac6410469444358ccab76040eb94cad3b058`

## Boundary

This closes the kernel-level success/evidence-without-progress accounting path.
Full F-02 acceptance still requires production task enrollment and controllers
to issue occurrences from this journal authority. Current unlocked native
proof, a clean commit, and push also remain pending.

EasyBusiness remained permanently stopped and read-only.
