# Pre-apply verifier/reviewer containment readiness gate

Recorded: 2026-08-14T13:27:19Z

Status: implemented and verified; ordinary-macOS production apply remains
correctly withheld because no Release containment issuer exists.

## Boundary closed

Canonical mutation preparation can no longer acquire a workspace lease,
journal an apply intent, or persist an apply effect before LoopForge has exact
non-serializable proof that every ratified verifier and reviewer recipe has an
installable pre-exec containment route.

`AuthorizedKernelPostimageContainmentReadiness` binds the exact run,
integration transaction, contract identity, objective digest, and a sorted
complete projection of every retained evidence recipe. Each projected binding
contains its requirement, verifier kind, canonical full-probe digest,
executable digest, resident-memory ceiling, and zero-child-process ceiling.
The full probe digest also binds argv, input artifacts, parser, environment,
capture, network policy, result mapping, and the remaining resource limits.

The capability is neither `Codable` nor publicly constructible. It has no
Release issuer on ordinary macOS. Consequently the production apply boundary
fails as `containmentReadinessUnavailable` while the transaction remains
`rollbackPrepared`, with no runtime lease and no outbox entry. A future
privileged helper or container may issue the capability only from this file's
trusted boundary after proving the exact pre-exec enforcement route.

The apply coordinator checks this capability after revalidating the accepted
preflight, registered workspace, canonical root, immutable content objects,
and reducer projection, but before constructing or restoring a supervisor.
Thus missing or cross-wired readiness has no mutation-authority side effect.
Exact replay still requires the same run/transaction/contract recipe set.

## Verification

The completed-candidate production-chain test now proves three cases in order:

1. absent readiness is rejected while phase stays `rollbackPrepared`, the
   workspace lease is absent, and the outbox is empty;
2. a capability for a different transaction is rejected identically;
3. the DEBUG-only exact capability covers every retained recipe and admits the
   existing apply/veto/crash/rollback chain.

The exact final-source suite passed 767 tests with 8 intentional environment
skips and zero failures in 67.228 test seconds. The Release build passed in
89.60 seconds and contains no test issuer. Diff whitespace and owned process
cleanup passed. EasyBusiness remained read-only at exact HEAD
`2ae40452e6d8661c46db466c43ea40bba3bfab04`.

One test compilation diagnostic placed actor awaits inside XCTest autoclosures;
it counted zero and was corrected by awaiting into local values before the
assertions.

## Exact source identities

- `KernelResidentMemoryEnforcement.swift`: `b96872b80349db4d3f37270d9e9b3b20ecfc21737b83a8624ced2e66bf4fb4c9`
- `WorkspaceCompletedCandidateMutationApplyPreparation.swift`: `6b4a676106c67c7701464532397c194788cf41b0898033226bf904a406fcc1ed`
- `KernelRunEnrollmentCoordinatorTests.swift`: `ed0999924bfb37e706b50b694d0890a912c9646c78b698ebd978617fbe2e8132`
- Release executable: `71cef336bde555b2a5ec4fbd18d60bdef45a883af5a0a9ebc724e5707966edf5`

## Remaining boundary

LoopForge now has both safe halves: future apply is vetoed before canonical
mutation when containment is unavailable, and previously applied journals
recover through exact fresh-lease rollback. A real privileged/container issuer
is still required before ordinary-macOS production can execute mutation-backed
verification. Until then, withholding mutation is the intended safe result.

Native immutable design/visual authority, final authorization, production
kernel cutover, current-source package/sign/hash, unlocked native verification,
clean commit, and push remain pending. Final acceptance remains false.
