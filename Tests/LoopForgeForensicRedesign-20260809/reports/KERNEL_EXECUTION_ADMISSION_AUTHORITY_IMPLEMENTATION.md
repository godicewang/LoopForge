# Kernel Execution Admission Authority

Status: **implemented, full-regression verified, packaged, signed, and runtime-smoke verified; native UI refresh pending**

Recorded: `2026-08-11T09:50:00Z`

## Forensic defect

The journal reducer previously treated node authorization as sufficient to
accept `startAttempt`. Causal convergence admission existed, but it was a
parallel subsystem: an attempt could skip its prediction, falsification,
rollback, cost, strategy-retirement, and external-effect budget checks and
still move the run to `executing`.

The native process boundary had a second, independent bypass. A
`RuntimeResourceLease` proved capacity and ownership but
`JournaledProcessRuntime` accepted it as authority to materialize an OS process
even when the journal did not name the request's attempt as active. This made
the intended chain advisory:

`ratified contract -> accepted plan -> node authorization -> causal admission -> active attempt -> runtime lease -> OS process`

## Implemented authority chain

- `ConvergenceGovernor` exposes an admitted request only from replayed,
  accepted typed transitions.
- `RunReducer.startAttempt` now requires the exact attempt ID to have an
  accepted causal admission whose computed strategy fingerprint and
  requirement set exactly equal the authorized node.
- Renaming an attempt, supplying an unrelated admitted strategy, or omitting
  convergence initialization fails closed without advancing the journal.
- `JournaledProcessRuntime.admitAndLaunch` and its lower-level `launch` path
  independently require the journal projection to be `executing`, the lease's
  run and attempt to equal the active attempt, the attempt to remain open, and
  the causal strategy/requirements to match.
- A runtime lease remains capacity and ownership only; it is no longer an
  execution capability.
- Visual-gate, integration-transaction, and managed-process fixtures now use
  the complete typed admission chain instead of synthetic opaque strategy
  strings.

No EasyBusiness bytes, task state, Git state, or process were changed.

## Adversarial evidence

Two new tests directly exercise the removed bypasses:

1. an authorized node without an exact causal admission cannot start;
2. a valid productive process request against a merely created run cannot
   journal an admission, acquire a supervisor lease, or materialize a process.

The migrated focused suites passed:

- reducer: 33 tests, 0 failures;
- visual journal integration: 14 tests, 0 failures;
- integration transaction state machine: 8 tests, 0 failures;
- journaled process runtime: 14 tests, 0 failures.

The complete source and package-owned suites each passed **621 tests, 8
environment skips, and 0 failures**. The exact dirty-source snapshot was
packaged, signed, archived, checksummed, launched as its packaged Mach-O, and
reaped with no residual packaged process. Native UI receipts still require an
unlocked session.

## Receipts

- convergence governor: `15e8ffce1bcdcfc70cec336201426f36b0753d8a39432a79ba015e8369bcd65e`
- run reducer: `a0498354c3876d127bfc36edf049d90dac075e231090ea0a6df5795841f38472`
- journaled process runtime: `445db87e2a3c25d4ad91d39ccfb3a2937a960757f94bfb977b364a76077a8740`
- reducer tests: `10956979446de3c47d650d861f2e81cc479337a483ff9c89f4314fa59387f39d`
- visual journal tests: `b884b88cdfe1a46efdf7b318a97b03365d2e09329ceaf221b5b926750aaa5bbb`
- integration transaction tests: `af1a2fa067ed4b8df7effa8b93204e83164c0bea08c3bb0955d4c70db13839bf`
- journaled process tests: `b73ec6b6e2a107e9391fdb275bb14811c3054434982211f2c62e7341cf24de87`
- release source snapshot: `5c469ab2501469107489699fa6f97b1ad6f12668e1a79700ce8bb3b38778b044`
- package test log: `8cb1ffbed9ea99a0f7902bc6abb83623f63e97d236e36b653910aa938600aacd`
- build manifest: `19def77fdd61f76ff1625730d91bf9eee76761452bde02ade9467b206bd193a4`
- executable: `2e8e2b7c69dd1dd1fbbec50a1819e825b0c321f594f5272a2270a39c699b3c9d`
- ZIP: `2e7ddd532552404c5942093c763149ea6c75cd21f912f73a1cd8302cd1f5f68e`
- DMG: `aa6f48167914752ebe7864421630c04c14a95de896e7326dc5c50a698146c251`
- checksum manifest: `f808a07d5a6409e7ecd090820182ae1811ef00b0af398931d51a0bd342032861`
- runtime smoke: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- CDHash: `11778eea9102851ce9343218adb4467a3defae47`

## Remaining boundary

This closes execution *admission*, not the entire replacement executor. The
production coordinator that turns a newly ratified Auto Graph contract into a
plan, causal admission, bounded worker request, occurrence, verification,
visual decision, and transactional integration is still absent. The historical
Graph remains retired. Native unlocked UI verification, commit, and push remain
pending; final acceptance is false.
