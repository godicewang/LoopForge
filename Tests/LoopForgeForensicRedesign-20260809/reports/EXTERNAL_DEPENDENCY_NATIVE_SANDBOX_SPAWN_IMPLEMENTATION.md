# External-Dependency Native Sandbox Spawn

Status: **activation-bound native spawn, admission, attestation, journaling, request delivery, natural exit, and cleanup are implemented and DEBUG-proven; ordinary-macOS Release remains vetoed without trusted resident-memory enforcement**

Recorded: `2026-08-15T14:14:08Z`

## Result

`JournaledProcessRuntime` can now consume one live
`AuthorizedExternalDependencyObservationLaunchReadiness` capability and launch
the exact activated observer. The caller supplies identifiers and private output
basenames only. The runtime revalidates the immutable request and staged
executable, derives the minimal environment, read-only/offline native sandbox,
private stdin/stdout/stderr, one-process and output-file limits, wall deadline,
and resource reservation, then journals admission before native spawn.

Immediately before spawn it rechecks the live readiness, request descriptor, and
executable inode/digest. `ProcessGroupRuntimeAdapter` accepts this route only
through a typed external-observer API and rehashes the exact open request
descriptor before handing it to standard input. The stopped sandbox gate must
attest the exact process, profile, physical workspace/journal/output paths,
kernel limits, successful target exec, and nil candidate working directory.
Only then does the runtime atomically journal the accepted process binding and
activation-bound launch receipt and apply the supervisor binding.

The successful integration test used the real native sandbox gate and a staged
raw-Darwin fixture. The fixture consumed the immutable request from `/dev/stdin`,
wrote the exact retained output, exited naturally, and was joined and released.
Journal and supervisor projections then contained no live resource. This is an
actual native spawn test, not a synthetic launch-receipt test.

Two adversarial defects were found and corrected during the exercise. macOS
Foundation path resolution can retain `/var` while `F_GETPATH` reports
`/private/var`, so activation, sandbox parameters, durable path digests, and I/O
now share descriptor-resolved physical directory identity. Standard-error
evidence also now uses its own error-domain digest rather than the standard-
output digest domain.

## Verification

- the focused external-dependency suite passed **15 tests** with **0 failures**;
- the exact source suite passed **808 tests**, with **8 intentional skips** and
  **0 failures**, in **57.480 test seconds**;
- the package-owned suite passed **808/8/0** in **61.394 test seconds**;
- the real Codex child/Responses bridge passed in **17.538 seconds**;
- non-DEBUG arm64 Release built in **104.23 seconds**;
- deep-strict ad-hoc signing, source/test manifest binding, ZIP, DMG,
  checksums, exact packaged-Mach-O startup, and cleanup passed;
- source snapshot:
  `adb6c28701fb72e6f93a4f62cd8a59eebffb5b778dedcab20f1a45f303ac9972`;
- packaged LoopForge SHA-256:
  `6af8d949007ac7d5e08774ab64fb6aec4a8396cf9953e9d864a18cfc5e711bc1`.

## Boundary

The actual native observer ran only in DEBUG with an explicit test-only
resident-memory capability. No production issuer exists on ordinary macOS for
the required hard physical resident-memory ceiling. Release code contains the
typed path but cannot reach admission without a trusted non-Codable issuer, so
the production readiness coordinator continues to journal the exact veto and
starts no process.

This interval proves start-through-natural-release transport. Production
composition of retained output parsing, release-bound result authority, and the
journal observation coordinator remains to be wired from the native controller;
those downstream boundaries already exist but were not promoted by this test.
EasyBusiness remained stopped and read-only at commit
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its newline-delimited `-uall`
status fingerprint remained
`a640615bfb23f0d3a9fefe222294663302b40cca54e23b2f4ae0029f5e4bcfd7`.
Final release remains false. Trusted Release containment or the retained veto,
production composition/controller invocation, legacy retirement, unlocked
native screenshots, a clean-commit rebuild, commit, and push remain required.
