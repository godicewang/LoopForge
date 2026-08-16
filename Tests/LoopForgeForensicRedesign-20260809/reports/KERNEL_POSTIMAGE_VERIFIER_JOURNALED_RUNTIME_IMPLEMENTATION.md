# Kernel Postimage-Verifier Journaled Runtime Implementation

Recorded: `2026-08-11T23:35:11Z`

Status: **activation-linked journaled verifier lease, sandboxed native launch, retained I/O, exit, release, and replay implemented; hard runtime ceilings, parsing, verdict issuance, latest-red revocation, independent review, and native start remain vetoed**

## Outcome

LoopForge can now consume one live `AuthorizedKernelPostimageVerifierInvocation` and launch the exact deterministic verifier executable as a real owned process group. The launch is not routed through worker/provider authority or the DEBUG-only generic adapter. A new Release path accepts only the activation capability and journals a distinct postimage-verifier launch event alongside the exact external process binding.

The runtime starts no provider, delivers no credential, reads no output, executes no parser or oracle, and issues no verification or review verdict. The integration transaction stays `appliedUnverified`. EasyBusiness remained read-only.

## Runtime authority

- The runtime actor identity must exactly equal the activation verifier; a different actor is rejected before runtime admission.
- The activation transaction is resolved back to its exact journal event, and its sequence must immediately follow the source journal head bound by activation.
- The run must still be `evaluating`, the integration transaction must still be `appliedUnverified`, the apply receipt must match, and the attempt must remain verification-eligible.
- A prior native launch for the activation revokes the live invocation path. One activation cannot launch twice.
- The candidate capability receipt must exactly equal the activation materialization receipt.

## Admission and immediate revalidation

The runtime constructs rather than accepts the productive process lease request. It fixes owned process-tree semantics, graceful-then-terminate cleanup, the exact attempt, one process reservation, zero network/GPU/GUI reservation, the recipe's maximum resident bytes, and a renewal deadline derived from the recipe wall-clock limit.

Candidate bytes are fully revalidated before admission and again after the journal/supervisor accept the lease. The staged executable is independently rehashed and its path, digest, size, device, and inode must still equal activation; the adapter hashes executable, environment, and argv again at its immediate spawn boundary.

This materially narrows the race window but is not described as atomic filesystem immutability. A same-owner process can still modify candidate bytes after the final path-based revalidation. Descriptor/capability composition at spawn remains required.

## Native isolation and binding

- The child receives the exact staged executable and fixed activation argv without a shell.
- The environment is generated solely from the four-variable minimal kernel allowlist and rehashed at spawn.
- Stdin is absent.
- Stdout and stderr are exclusive owner-private files under the journal run directory.
- The runtime synthesizes only a deterministic safety profile from ratified recipe facts: read-only sandbox, disabled network, disabled plugins, minimal environment, and the exact executable digest.
- The signed `KernelSandboxGate` must be observed stopped inside native Seatbelt, keep a stable process-group identity, and prove successful target `exec` before binding.
- The runtime journals the generic binding and `KernelPostimageVerifierLaunchReceipt` in one transaction before committing the external identity to the supervisor.

The launch receipt binds activation frame, run, integration, apply, attempt, recipe, verifier, resource, lease, binding, candidate materialization, executable staging, resolved argv, environment, retained I/O, sandbox attestation, parser contract, resource ceilings, and launch time. Reducer replay rechecks the complete relationship and reconstructs the launch.

## Real native proof

The exact `/usr/bin/true` digest was retained as the recipe executable. The test:

1. rejected a different actor before admission;
2. admitted the exact independent verifier under the runtime budget;
3. revalidated candidate and executable twice;
4. launched through the signed read-only/offline sandbox gate;
5. proved executable, environment, argv, and sandbox identities;
6. proved absent stdin and empty retained stdout/stderr;
7. journaled native binding and activation-linked launch;
8. journaled natural exit code `0` and exact lease release;
9. proved zero live adapter handles and zero in-doubt resources;
10. rejected a second launch from the same activation; and
11. recovered an identical reducer state and launch receipt from disk.

No ordinary `VerificationReceipt` was added and the integration phase remained `appliedUnverified` throughout.

## Verification

- focused native launch/integration/replay test: **1 passed, 0 failed**;
- complete discovered Swift matrix: **702 tests**;
- complete Swift execution: **702 executed, 8 environment-gated skips, 0 failures**;
- non-DEBUG arm64 Release builds (`LoopForge` and `KernelSandboxGate`): **passed**;
- exact source snapshot: `4ef53f87676da9f8c0ada00f16ca0d56c30ac7b271c43a7bb220be22bc27a829`;
- Release `LoopForge` SHA-256: `c10ff8d82a9b73cfcb1c2cdbf50e4a880ecce1e874ebd0de2cc15398af54bd3b`;
- Release `KernelSandboxGate` SHA-256: `0e29463be4377b4d21c463e7ddb63e6256dd76abf30ff1690f0c5a482e985227`;
- diff whitespace validation: **passed**;
- owned Swift build/test processes after verification: **0**;
- EasyBusiness read-only status: **unchanged**.

All test/build execution, polling, waits, and blocked time are excluded from the strict active-work ledger.

## Honest resource-limit boundary

The recipe's wall-clock, output, memory, and child-process ceilings are retained in activation and launch receipts. Admission reserves one process and the full declared resident-memory amount; the lease deadline derives from the wall-clock ceiling. These are evidence and scheduling controls, not yet complete OS enforcement:

- the launch call does not itself own a bounded join/timeout/termination transaction;
- stdout/stderr file growth is not capped during execution;
- resident memory is not constrained with a native hard limit;
- the declared zero-child rule is not yet enforced by the sandbox or a process-group monitor; and
- retained output has not been safely bounded and hashed into a result receipt.

Consequently this runtime is not wired to a native start control and cannot issue results.

## Remaining stop-the-line dependencies

1. one runtime-owned execute/join/timeout/terminate boundary using the exact wall limit;
2. hard combined stdout/stderr capture limits with prompt cleanup on overflow;
3. native memory and zero-child enforcement or fail-closed unsupported-platform rejection;
4. candidate descriptor/capability revalidation atomically composed with spawn;
5. bounded output hashing and an exact native-exit evidence receipt;
6. canonical parser and result-mapping/oracle execution;
7. a non-forgeable postimage verification result receipt;
8. latest-red revocation and canonical evidence batching; and
9. separately activated read-only independent review.

No package, commit, push, native walkthrough, or final acceptance is claimed.
