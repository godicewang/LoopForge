# Kernel Execution Profile Ratification

Status: **provider-neutral profile and executable digest are user-visible, source-bound, journaled, and activation-enforced; provider execution remains vetoed**

Recorded: `2026-08-11T12:33:00Z`

## Closed authority gap

Native Auto Graph confirmation now ratifies an exact execution profile rather
than allowing the executor to choose identity after confirmation. The profile
contains, for both worker and independent reviewer:

- provider kind and credential-free stable provider reference;
- exact model identifier and optional reasoning effort;
- sandbox mode;
- network policy;
- plugin policy;
- environment policy; and
- exact executable-harness SHA-256.

The confirmation sheet renders these values before the single-use user action.
The canonical profile bytes are retained as an explicit user-authority source
artifact. The compiler requires one full-span binding and proves those bytes
equal the canonical contract profile. Changing a model while retaining the old
source therefore fails with `executionProfileSourceMismatch`; deleting the
binding fails with `executionProfileBindingMismatch`.

Because the complete task contract is carried by `runCreated`, successful
enrollment journals the exact profile. The production enrollment coordinator
rejects replay-compatible legacy contracts that lack a profile. This preserves
historical decode without letting old records gain new execution authority.

## Fail-closed policy

The independent reviewer is always read-only, offline, plugin-free, minimally
isolated, and required to have a distinct runtime actor lineage. Native
authoring grants no capability IDs. Therefore a selected Full Access worker is
rejected before confirmation and before journal creation. It is not silently
downgraded to workspace access.

Network, user-installed plugins, declared environment expansion, and Full
Access each require their own typed capability ID and out-of-band native grant
receipt. The current native issuer grants none of them.

## Activation enforcement now closed

Activation proof now binds the journaled worker profile and activation actor in
addition to run/attempt/node/strategy/transaction identity. The journaled
runtime compares that profile to current reducer state, hashes the executable
before admission, and causes the native adapter to hash it again immediately
before spawn. Cross-wired profile, actor, transaction, executable, and legacy
contract fixtures fail closed without a process.

## Remaining cutover vetoes

This closes profile ratification, not provider execution. Cutover is still
blocked until:

1. eliminate the residual pathname race with atomic descriptor execution or a
   kernel-owned immutable staged executable;
2. bind provider credentials without serializing secrets and enforce native
   sandbox attestations;
3. the worker environment is constructed from a kernel allow-list instead of
   `CodexRuntime.environment()`;
4. retained stdout/stderr are hashed and parsed by a bounded nonce-bound JSONL
   terminal-envelope parser; and
5. `recordExecution` is replaced by a receipt derived from the exact journaled
   native exit, runtime release, output digests, parser result, and invocation
   identity.

Legacy `CodexRunner` remains outside the new-kernel execution path and was not
connected by this change.

## Verification

- profile authoring suite: **8 tests, 0 failures**;
- enrollment/composition suite: **9 tests, 0 failures**;
- native app enrollment flow: **3 tests, 0 failures**;
- complete source suite: **638 tests, 8 skips, 0 failures**;
- package-owned suite: **638 tests, 8 skips, 0 failures**;
- signed package, ZIP, DMG, checksum, exact executable startup, cleanup, and
  zero residual packaged processes: passed.

Package source snapshot:
`2e5150851da1873a76a33f92687b6ad7ccdf71d0961a4595f1401810732434bd`.

EasyBusiness remained stopped and read-only. Native screenshot capture was not
retried because the previously observed macOS lock had no external state
change. Final acceptance remains false.
