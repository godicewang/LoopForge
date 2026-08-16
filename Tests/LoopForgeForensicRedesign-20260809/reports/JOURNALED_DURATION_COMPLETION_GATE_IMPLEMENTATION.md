# Journaled Duration Completion Gate

Status: **F-02 kernel lifecycle gate implemented and package-verified; production enrollment cutover pending**

Recorded: `2026-08-11T06:37:47Z`

## Defect confirmed

The preceding interval repair required an occurrence to reference an accepted
progress transaction, but closed occurrences were still supplied to
`IntervalLedger` outside the hash-chained run state. Completion decisions did
not consult duration coverage at all. A caller could therefore preserve a
valid journal while omitting closed time from replay, or request completion
before the contract's required duration had been accepted.

## Repair

- `recordOccurrence` is now a typed journal command and
  `occurrenceRecorded` is a replayed event;
- reducer state retains journal-ordered occurrence receipts and the exact
  command IDs whose causal progress result was accepted;
- the duration projection is derived only from replayed reducer state, not
  mutable controller fields or caller-supplied receipt sets;
- occurrence identity, boot/monotonic bounds, evidence, invocation metadata,
  duplicates, and progress bindings are validated before the event is
  admitted;
- missing or `accepted=false` progress may be recorded for diagnosis but
  contributes zero accepted duration;
- forged progress bindings that do not name an existing processed journal
  transaction are rejected;
- both completion request and completion authorization fail with typed
  `durationIncomplete` unless accepted projected duration satisfies the task
  contract;
- the native convergence sheet projects required, accepted, and excluded time
  plus the coverage-violation count from reducer replay.

## Adversarial verification

A duration-bound run records one accepted five-second occurrence and one
stagnant five-second occurrence. Replay preserves exactly five accepted and
five excluded seconds and the `acceptedWithoutProgress` violation. Completion
is rejected before accepted coverage reaches the contract threshold. Missing
progress is diagnostic-only, a nonexistent binding is rejected, and only the
exact accepted journal command authorizes the final five seconds.

## Verification

- reducer suite: **31 tests, 0 failures**;
- journal suite: **16 tests, 0 failures**;
- complete source suite: **601 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **601 tests, 8 environment-gated skips, 0 failures**;
- release build, ad-hoc signature, exact source/test manifest, ZIP, DMG,
  checksums, executable startup, cleanup, and zero residual packaged processes
  verified.

Receipts:

- source snapshot: `f23bee59c7f7f3fec4dfb2a472c4e3485bd9226ccc31fc6f224181a9a258c11c`
- reducer source: `42c4375f198cde5abcf886786c293d241de607f5bb9cf085e98bb88038c3ff39`
- journal source: `a0f71b8d6abe2f8ec8ddd321508bf027052906f0aeac794cadd169c2dc8687f6`
- interval source: `31e9a73b8c4f8e9d1c6815ba0ef1dd47647a67f48fe2df9a49ba8d5f1bc2b819`
- native view source: `ff771a56a4522fc13c2871f1932c3cc02e9e8d8eaada00f23041e991b978f7fd`
- reducer tests: `5e27702d3bc1656650c45677d53a096f8e2718bd3aae38c751f62bb08d9e0dd9`
- journal tests: `b56d9de7c3f02bf3bda3d173f3205724eb80a8acaa40119583fefeb9d20372e4`
- complete test log: `a9ef99ab2cb3cee839ceddce8ae70c3acc43de98e432402bbd3aadf0d5593bbd`
- package test log: `80c931ac698a5090f79db4992767da37d593f2de91be70442af3cb7d73d5431c`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `b66e3d785e2613c82a0c7bd7ddd41381ccc5b22486bef32e8dce8002124c8492`
- executable: `61b231ae5c8eec133c15c9e668dc0c301f40e3b723ce5e04323b0f31e699d788`
- ZIP: `a0ea12b9a2e1ee4d1faa9bfab65d316b9f6a0440b00344d89eb96b43e6f13927`
- DMG: `40fc09027d03986423b9afa817debcdbcf998cc8031d1b404c8c207160d4e2d2`
- CDHash: `316a6612b23dc331762ff8c2b1bd6a8ed65549a0`

## Boundary

This closes the kernel journal/replay and completion-veto portion of F-02.
Production task-contract enrollment, trusted occurrence issuance, and legacy
controller cutover remain pending. The current native walkthrough was attempted
through Computer Use but macOS was locked; no bypass was attempted and no
blocked time was counted. A clean commit and push also remain pending.

EasyBusiness remained permanently stopped and read-only.
