# Production Kernel Run Enrollment

Status: **journal-first ready enrollment invoked from Auto Graph; execution cutover pending**

Recorded: `2026-08-11T09:26:27Z`

## Enforced chain

`KernelRunEnrollmentCoordinator` accepts only compiler-sealed ratification,
verifies exact workspace identity/root digest and single-use receipt, appends
`runCreated` before registration, reads reducer authority back, and requires an
exact `ready` projection. A nonserializable enrollment proof gates durable
registry publication. Release code has no raw registration escape hatch.

The registry persists exact contract/revision, candidate digest, ratification
receipt, user lineage, create command, journal frame digest, and sequence.
Crash before publication can leave only an inert unregistered journal. Receipt
replay and workspace substitution fail before a second journal.

Auto Graph's real SwiftUI/AppModel path now calls this coordinator after exact
native confirmation. The receipt returns the reducer projection, which is
merged into read-only diagnostics. No strategy, worker, legacy task, or timer
starts. Cancellation has no journal or registry effect, and retry retains the
same ratification, run ID, command ID, and enrollment time.

## Verification

The focused **13-test** invocation suite and complete **618-test** development
and **619-test** package-owned suite passed with 8 environment skips and 0 failures. Exact
source snapshot, package test log, signature, archives, checksums, direct Mach-O
startup, cleanup, and zero residual processes passed.

Receipts: source snapshot
`1303cb7ec1a7f343cf2537825939771a7b0eb70d076f191ace601e0601a99734`;
enrollment source
`8645f5e7351c25cb9b6fbde0d30ab94cd4386274fe37fdf00a5d5b3adbf041bb`;
registry source
`d6422bf54e154113bf7e5202d3d41b499945b1ff36cbdbb76488c5e35b098b86`;
invocation tests
`8ab25c41ee46fb1f2a45053420f6c3e6aa04e5907139985325c2070e25f2d4c3`;
package test log
`afbaf096e4dc6f140ed1c81c567c117346e08fb05307d1fe426c4cd62cbd5448`;
executable
`3aa6db2cb2e0b938beec26b911dea2f77716cb3375457d28ea25443971f55dc5`;
CDHash `f2c50cea69e67c4eecde5fb7187c3cc26292d8f2`.

## Boundary

Ready enrollment is not execution. Historical Auto Graph resume is retired;
native planner, worker, timing, process, and integration replacement remains pending. The one
current native inspection was blocked by macOS lock, not bypassed or retried,
and counted zero. Current unlocked screenshots, complete execution cutover,
clean commit, and push remain required. Final acceptance is false.

EasyBusiness remained permanently stopped and read-only.
