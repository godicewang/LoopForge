# Native Verifier Enrollment Staging and Activation Resolution

Status: **the confirmed verifier is imported before the run is journaled, and activation no longer accepts a caller executable path; trusted Release containment and a production verifier run remain separate gates**

Recorded: `2026-08-15T19:58:40Z`

## Closed authority gap

The confirmation boundary re-opened and rehashed the selected manifest and executable, while the activation boundary independently compared a caller-supplied path with the confirmed digest. Digest mismatch prevented different bytes from executing, but the caller still selected where activation looked and a removed source could prevent a confirmed run from continuing after restart. That made the selected path operationally durable despite the UI correctly describing it as non-authoritative.

The handoff is now content-addressed and journal-owned:

1. `NativeVerificationProbeSelection` is immutable and has a file-private initializer. Only the schema-constrained native loader can construct it.
2. The native AppModel passes its confirmation-time refreshed selection into `KernelRunEnrollmentRequest`.
3. Before `runCreated` is appended, `KernelRunEnrollmentCoordinator` requires exact set equality between the selected probes and the contract's executable recipes, rejects duplicate or unmatched capabilities, revalidates every selection again at the enrollment boundary, and imports each unique executable into the private run directory.
4. The import path is `runtime-executables/<confirmed SHA-256>`. Existing artifacts are accepted only after descriptor-relative no-follow validation, owner/private-mode checks, regular-file and link-count checks, executable-mode checks, bounded size, and a fresh content digest.
5. Enrollment receipts record the resulting device, inode, size, digest, materialization, and staged path. A failure occurs before `runCreated` or registry publication; any partial artifact is inert and unregistered.
6. `KernelPostimageVerifierActivationRequest` no longer contains `executablePath`. Activation resolves only the digest-named artifact already inside the journal's run directory. Resolution never creates a directory, imports bytes, or consults a later caller path.

Internal synthetic tests may still enroll without a native selection, but such a run has no staged artifact and activation deterministically rejects. Non-DEBUG native AppModel enrollment already requires a real selection.

## Adversarial evidence

- `KernelExecutableStagerTests`: 8 tests, 0 failures. New cases prove restart-style resolution returns the exact imported inode, missing resolution imports nothing, and modified staged bytes fail digest validation.
- `NativeKernelEnrollmentFlowTests`: 8 tests, 0 failures. The new production-composition case selects a manifest, confirms and enrolls it, proves one receipt-bound import, replaces the original executable, reopens the journal, and resolves the unchanged staged bytes without consulting the source.
- `IntegrationTransactionStateMachineTests`: the complete journaled postimage chain first attempts activation with no staged artifact and receives `stagedExecutableResolutionFailed`; only an explicit enrollment-equivalent import permits activation. No request path exists to restore the old behavior.
- `KernelRunEnrollmentCoordinatorTests`: crash-replayable completed-candidate activation resolves the staged artifact and preserves exact executable digest evidence.
- Full source suite: 833 tests, 8 intentional environment skips, 0 failures, 56.340 test seconds on the final visible full run.
- Package-owned suite: 833 tests, 8 intentional environment skips, 0 failures, 57.850 test seconds.

Intermediate compile/test invocations used while migrating the request shape failed before the final focused evidence and count zero. A later read-only validation command invoked `source_snapshot.sh` from the wrong directory; the already-successful package smoke had independently recomputed the embedded snapshot, the corrected checksum verification passed, and the failed invocation counts zero.

## Exact package receipt

The rebuilt ad-hoc-signed app was produced at `2026-08-15T19:57:02Z` from dirty-source snapshot `3911520f6e62444ea8afc6923b0b61bf8f3ca688767182af6ce95a064f366ce7`.

- executable SHA-256: `de2585e93964d6c685fec7a2cde9c0a96a76672194970466cc61de6330dffddb`;
- app CDHash: `ac5b3e6c5dbce4a11e6fe1c81b72f50eb1ffbb95`;
- ZIP SHA-256: `f0b53fcd85c397399b818c102835d0569ab90df697f327a3c8b8db63fd6e3ba3`;
- DMG SHA-256: `28f7ce80178e4496434ef69120675c8fffbac251f31b78f9f39f1350f43dbcbc`;
- package-test log SHA-256: `afd3ff90c367495566a437bf7078f360de9309d1a33583202f64ec6a58be1384`;
- build-manifest SHA-256: `6ab0c13d3102a112d94f8d04f2d053352992db73da8a960661847f236b49d9e7`.

Deep strict signing, source/test manifest binding, checksum-manifest verification, ZIP and DMG verification, exact packaged-Mach-O bounded startup, cleanup, and zero residual exact packaged processes passed.

## Remaining boundary

This closes confirmation-to-activation executable continuity. It does not invent trusted resident-memory containment: ordinary macOS Release therefore retains the existing pre-admission verifier launch veto. A real production verifier launch/result, separately packaged and ratified provider harness, exact network authority, mutation authority or retained veto, legacy Single/Parallel retirement, the complete current native visual matrix, clean-commit rebuild, commit, and push remain required. Final release is false.

EasyBusiness remained stopped and read-only at HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04` with the established NUL-delimited status fingerprint `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
