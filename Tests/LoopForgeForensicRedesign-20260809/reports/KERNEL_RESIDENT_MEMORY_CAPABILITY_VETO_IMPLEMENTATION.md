# Kernel resident-memory capability veto

Recorded at: `2026-08-12T02:58:12Z`

## Outcome

LoopForge no longer permits a postimage verifier to reach runtime admission while its declared resident-memory ceiling is only scheduler reservation data. `JournaledProcessRuntime.admitAndLaunchPostimageVerifier` now requires a non-serializable `AuthorizedKernelResidentMemoryEnforcement` bound to the exact run, activation receipt, and byte ceiling. A wrong activation or byte ceiling cannot reuse it. Release builds contain no issuer, so the production-shaped verifier path fails closed before lease admission, spawn, output creation, or journal mutation.

The DEBUG-only issuer is explicitly synthetic. It exists solely to keep the downstream native journal, result, verification, revocation, and recovery composition executable in deterministic tests; it is compiled out of release and cannot substantiate a native-containment claim.

## Disproven native strategies

The audit tested each apparent Darwin primitive instead of accepting API presence as enforcement:

- `RLIMIT_RSS` is an alias of `RLIMIT_AS` in the macOS SDK. The manual describes preferential reclamation under memory pressure, not a hard physical-footprint barrier. A low address-space limit was rejected when below the process's existing virtual mapping and is not an RSS contract.
- `RLIMIT_DATA` was rejected with `EINVAL` for the tested Swift process and would constrain only `sbrk` data space, not total physical footprint.
- `task_set_phys_footprint_limit` is the exact physical-footprint API, in MiB, but this ordinary process received `KERN_NO_ACCESS` even for its own task.
- `posix_spawnattr_setjetsam_ext` accepted fatal active/inactive 128 MiB attributes and spawned successfully, but an adversarial target touched and retained 512 MiB for three seconds and still exited zero. Therefore an attribute-success return is not treated as proof for this macOS process class.
- Parent-side polling/sampling was rejected because it observes allocation after the fact, has an unavoidable sampling gap, and does not prove an inherited pre-exec kernel ceiling.

## Verification

- Focused native sandbox suite: 6 tests, 0 failures.
- Journal/integration suite: 8 tests, 0 failures; it proves unavailable authority creates no runtime lease and exact-activation authority cannot be cross-wired.
- Complete Swift suite: 715 tests executed, 8 intentional environment skips, 0 failures.
- Non-DEBUG release `LoopForge` SHA-256: `2e739ec12592f4a7acec11c7d2065150bc730498b886359fb45dc9cbb4cf3c2b`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Exact source snapshot SHA-256: `69e8f5d2ee7c2a8e7e2e4f1a1c0a05428fe5ff1516d691102b51b1ea0d706f6a`.
- Diff whitespace passed; no owned verifier/gate/LoopForge process remained; EasyBusiness status fingerprint remained unchanged and read-only.

## Boundary retained

This does not implement resident-memory enforcement. It prevents the missing enforcement from being bypassed or mislabeled. A future production issuer must be backed by a tested privileged helper/container/platform facility that enforces the exact bound before target execution and binds the same run/activation/limit identity.

Descriptor-atomic candidate handoff, production independent review, integration reliance, native baseline/visual authority, native start/UI verification, packaging/signing, clean commit, and push remain vetoed. Final acceptance remains false.
