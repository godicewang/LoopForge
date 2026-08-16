# External-Dependency Journaled Activation

Status: **exact observer bytes and one immutable nonce request are journal-bound; native launch and observation issuance remain pending**

Recorded: `2026-08-15T11:35:36Z`

## Result

LoopForge now compiles one declared external-dependency probe into an inert,
replayable activation. The production coordinator resolves the exact active
attempt and contract, verifies an independently authorized observer lineage,
rechecks the canonical workspace binding, stages the executable by its
ratified SHA-256 inside the owner-private journal run directory, and derives a
fresh request nonce from the run, attempt, dependency, recipe, observer,
receipt, journal sequence, and journal-frame digest.

The request envelope is canonical sorted-key JSON with one trailing newline.
It is created descriptor-relative with `openat`, `O_EXCL`, and `O_NOFOLLOW`,
made read-only, synced with its directory, and retained with byte, SHA-256,
device, and inode identity. Crash retry accepts existing bytes only when the
complete envelope and receipt remain exact. A symlink, writable replacement,
changed byte, unsafe directory mode, stale nonce, or substituted journal frame
fails closed.

The reducer and decoded-event replay share the same pure activation validator.
They bind the activation to the active undisposed attempt, exact requirement
intersection, observer/worker lineage separation, executable probe, resolved
`/dev/stdin` argument, parser, result mapping, network policy, resource limits,
workspace digest, source sequence/frame, and event time. One attempt/dependency
pair can retain only one activation. Durable replay reconstructs a receipt, not
the live request capability.

## Deliberately absent authority

Activation starts no process, admits no resource lease, grants no native
sandbox, reads no result, maps no exit status, and cannot mint an
`ExternalDependencyObservationReceipt`. The full source and recovery test uses
`/bin/echo` only as immutable staging input and proves that activation leaves
both live-resource and dependency-observation collections empty.

The next boundary must consume the live activation in the journal-owned process
runtime, open the retained request as standard input, enforce the declared
native sandbox/network/resource ceiling, retain native exit and bounded output,
apply the exact declared result mapping, and issue the only observation
capability. Controller invocation remains after that composition.

## Verification

- four activation tests cover end-to-end coordinator activation and recovery,
  exact retry, immutable canonical bytes, tamper and symlink rejection, and
  owner-private directory enforcement;
- one reducer test proves exact command acceptance and tampered decoded-event
  replay rejection;
- the exact source suite passed **803 tests**, with **8 intentional skips** and
  **0 failures**, in **56.422 test seconds**;
- the package-owned suite passed the same **803/8/0** set in **60.837 test
  seconds**;
- non-DEBUG arm64 Release built in **95.24 seconds**;
- deep-strict ad-hoc signing, embedded source/test manifest, ZIP, DMG,
  checksums, exact packaged-Mach-O bounded startup, and cleanup passed;
- source snapshot: `48c4ee6d8b6af062d3109e064b328ecae5041d9bc872aa4f8784724c14c196e6`;
- packaged LoopForge SHA-256:
  `418355aaaa37d26d3f98615b27ac84d769f310c985cd1d331ae95ef3ef682c96`.

## Boundary

EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`. Final release remains false.
Native dependency launch/result composition, observation issuance, production
controller invocation, legacy retirement, unlocked native screenshots, a
clean-commit rebuild, commit, and push are still required.
