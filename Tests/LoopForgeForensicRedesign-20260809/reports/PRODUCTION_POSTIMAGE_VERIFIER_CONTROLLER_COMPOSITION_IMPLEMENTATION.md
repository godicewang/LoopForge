# Production Postimage-Verifier Controller Composition

Status: **durable production containment veto and exact live launch composition passed; final release remains pending**

Recorded: `2026-08-16T04:47:31Z`

## Closed authority gap

The lower process runtime already failed closed when ordinary macOS could not
provide a non-serializable capability proving enforcement of the ratified
resident-memory ceiling. The application session, however, exposed only a
DEBUG-only helper that injected test authority and returned a start receipt.
Production had no controller boundary that could activate the exact recipe,
retain the missing-containment veto, distinguish a cross-wired authority, or
surface the durable reason to its caller.

`KernelProductionExecutionSession.launchPostimageVerifier` now owns that
complete transition. Its caller provides one typed activation/runtime request
and an optional non-Codable containment resolver. The session activates the
exact journal-owned evidence recipe, resolves containment immediately before
admission, and returns one of two typed outcomes:

- an exact, durable `KernelPostimageVerifierLaunchVetoReceipt` plus its
  activation and journal transactions; or
- the runtime-owned native start receipt for later completion or application
  cleanup.

The former DEBUG launch helper was removed. Tests may supply a DEBUG-only
activation-bound capability through the same production method; Release still
has no ordinary-macOS issuer and therefore follows the production veto path.

## Fail-closed invariants

- Activation, runtime receipt, and command identities must all be nonempty and
  pairwise distinct before the journal advances.
- A returned memory capability must authorize the exact run, activation
  receipt, and maximum-resident-byte ceiling. A cross-wired capability rejects
  without admission, launch, lease, or a misleading missing-authority veto.
- Nil containment enters the existing process-runtime boundary, which journals
  the veto before any admission. The session accepts that result only after
  re-reading the exact command transaction and checking every activation,
  integration, apply, attempt, recipe, verifier, frame-digest, byte-ceiling,
  and reason field.
- Retrying the same activation returns the original veto and transaction. It
  does not call around the veto, create another receipt, or reach admission.
- Exact test containment launches with the independent verifier actor, but the
  original session runtime retains the native handle. Application termination
  can therefore kill and durably release the exact PID without gaining verdict
  authority.

## Native proof

The live production-session test now ratifies two independent deterministic
recipes over the same applied postimage. It proves, in order:

1. a colliding identity request rejects before activation;
2. ordinary production journals a resident-memory veto with no lease or
   process launch;
3. retry returns the exact original veto transaction;
4. a capability from the first activation cannot authorize the second and
   produces no lease, launch, or veto;
5. an exact DEBUG capability passed through the production API launches the
   second real verifier;
6. the real AppModel termination boundary kills that live PID, journals
   `runtimeCleanupTermination`, mints no result authority, empties ownership,
   and reaches stopped quiescence.

The focused proof passed, all 44 production-enrollment tests passed, and the
Release build succeeded. The exact package-owned complete suite then passed
861 tests with 8 intentionally gated skips and 0 failures in 81.525 test
seconds (81.575 wall); the real Codex child bridge passed in 15.438 seconds.

## Package binding

- Source snapshot:
  `059dba47ad44d1ead84edbf4094fae8d7040084d2d2337cf00c616a00039f414`.
- Package test log:
  `f5776d9f5da9f5fb178692e565fe168a6918f31c7504f111a5780fe8b19dd941`.
- Signed app executable:
  `3b657f94e3be6bb157debc71ef9e52ba4c534c609c82212b35a1168f30fa68ed`,
  CDHash `73e0af7d1f9885d13b0927ae2f89ee164cac5f4b`.
- ZIP:
  `21e1388edf3993c78ad6559772e6db3d8401d8cc9dbd36a1508151fcd3b65806`.
- DMG:
  `fb69ea1378b7b5fea79b65353f4ec83101bef72459c06e47a94e11c057d6ae2e`.
- Deep-strict signing, checksum/source/test binding, direct startup, mounted-DMG
  identity for all three Mach-O files, mounted signature/startup, exact detach,
  and zero residual package/verifier processes or mounts passed.

This is a controller/lifecycle change with no visible UI delta, so no prior
screenshot is relabeled as current. EasyBusiness remained read-only on branch
`codex/USA_Version`, HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged NUL-delimited
status digest
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Boundary

This closes production-session retention and surfacing of the
postimage-verifier resident-memory veto. A trusted Release issuer for physical
resident-memory containment remains unavailable on ordinary macOS, so Release
correctly remains fail-closed. Productive provider backend ratification and
cutover, the native mutation-preparation controller, join-only recovery
without a retained handle, the complete native visual matrix, a clean-commit
rebuild, commit, and push remain pending. Final release is false.
