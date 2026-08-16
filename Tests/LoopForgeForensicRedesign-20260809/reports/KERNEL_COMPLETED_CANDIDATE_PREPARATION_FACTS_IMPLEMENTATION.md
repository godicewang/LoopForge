# Completed candidate preparation facts — descriptor-observed and inert

Recorded: `2026-08-12T20:43:00Z`

## Result

LoopForge now derives and journals four exact preparation facts from one
accepted completed-candidate manifest proposal: least-path write scope, an
exact file/byte ceiling, candidate-scoped quiescence, and descriptor-observed
path resolution. Every fact carries the proposal's common
`MutationPreparationBinding`; all receipt IDs are derived from the proposal
digest rather than caller labels.

This remains an acyclic, inert boundary. The receipt has no rollback rehearsal,
candidate verification, independent review, visual acceptance, executable
`MutationManifest`, `AuthorizedMutationPreflight`, integration transaction, or
filesystem effect. Crash replay recovers historical facts only and cannot
reconstruct a live descriptor.

## Descriptor and journal authority

The coordinator requires the exact accepted proposal journal transaction and
the exact completed-candidate release frame. The reducer independently requires
an evaluating run, completed attempt, awaiting-verification node, exact
proposal/store/capture lineage, a successful candidate release, zero live or
failed leases, and zero integration effects.

The canonical root is opened component-by-component with `O_NOFOLLOW`. Every
existing proposal path is opened descriptor-relatively as a regular file and
its stable inode, mode, size, and SHA-256 are checked against the proposed
preimage. A create target must be absent beneath an existing no-follow parent.
Root and file identities are checked before and after observation. Duplicate
replay repeats the observation and rejects workspace drift.

## Adversarial verification

- A substituted proposal transaction rejects before path observation can be
  journaled.
- Replacing the canonical target with a symlink rejects; restoring the regular
  file permits exact preparation.
- Serialized preparation facts contain no rollback, verification, independent
  review, or visual authority.
- Duplicate append is receipt-exact and re-observes the canonical path.
- Close/reopen replay recovers the same inert receipt.
- The synthetic canonical workspace stays byte-identical and no integration
  transaction exists.
- The formerly crashing integration path and the preparation path passed in
  isolation. The complete Swift suite then passed 764 tests with 8 intentional
  environment skips and zero failures in 62.809 test seconds (62.858 seconds
  wall).

## Crash forensic

Seven failed validation runs reproduced signal 10 from the same oversized
cooperative-thread call chain. As incidental implementations changed, the
triggered frame moved through Swift metadata instantiation, Foundation URL
canonicalization, Darwin `realpath`, and Foundation variadic byte formatting;
the common caller remained the monolithic reducer release case. All seven
failed runs count zero. The two remaining verifier-result `String(format:)`
digest paths now use bounded locale-free `KernelHex`, and the exact release
predicates were extracted unchanged into a dedicated validator. This preserved
symlink-resolved canonical-root identity while bringing the stack below the
guard limit; the formerly crashing test and complete suite then passed.

## Still blocked

An exact rollback rehearsal must be performed and journaled before executable
manifest assembly. Preflight/integration authority, resident-memory authority,
native design/visual/final authority, native UI verification, package/sign/hash,
clean commit, and push remain pending.
