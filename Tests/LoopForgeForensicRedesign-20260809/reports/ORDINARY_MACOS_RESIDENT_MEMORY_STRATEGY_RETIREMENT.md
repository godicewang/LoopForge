# Ordinary-macOS resident-memory strategy retirement

Recorded: `2026-08-16T07:50:00Z`

Status: **the in-process ordinary-macOS issuer strategy is disproven and
retired; LoopForge now represents that platform result explicitly and retains
the pre-admission/pre-effect veto**

## Decision

LoopForge must not keep “trusted Release resident-memory issuer” on the
ordinary-app implementation backlog as though another syscall wrapper could
finish it. The ratified contract requires a hard physical-footprint ceiling
installed before the target executable can run. The available public
ordinary-macOS mechanisms do not provide that guarantee:

- In the installed macOS 26.5 SDK, `RLIMIT_RSS` is exactly the
  source-compatibility alias of `RLIMIT_AS`. The same header describes the
  primitive as address space, not a physical-footprint kill boundary.
- The installed `setrlimit(2)` manual describes `RLIMIT_RSS` as preferential
  reclamation only when memory is tight. It does not promise denial or
  termination at the declared byte value.
- `RLIMIT_DATA` bounds the `sbrk` data segment and cannot cover total physical
  footprint, mapped files, shared pages, allocator mappings, or subprocesses.
- `task_set_phys_footprint_limit` is the exact physical-footprint interface,
  expressed in MiB, but the current arm64 macOS 26.5.2 ordinary process
  received `KERN_NO_ACCESS` even for `mach_task_self()`. Probe output was
  `kern_return=8 name=(os/kern) no access old_limit_mib=-1`.
- The preceding native audit already demonstrated that accepted fatal
  `posix_spawnattr_setjetsam_ext` attributes did not terminate a target that
  touched and retained 512 MiB under a declared 128 MiB value in this macOS
  process class.
- Parent sampling (`task_info`, `proc_pidinfo`, or `getrusage`) is observation
  after allocation. It has a race before the first sample and cannot prove a
  ceiling installed before target execution.

The current package is ad-hoc signed and carries no entitlement payload. A
privileged helper, VM/container boundary, or another independently ratified
platform facility remains a valid future architecture. It is not an
in-process ordinary-app implementation detail and must not be inferred from
API presence or successful attribute setup.

## Source correction

Production resolution no longer overloads an optional closure and `nil` to
mean both “unsupported platform” and “resolver was not wired.”

- `KernelResidentMemoryEnforcementResolution` requires either exact
  non-serializable authority or the typed
  `ordinaryMacOSHasNoHardPreExecPhysicalFootprintLimit` decision.
- `KernelPostimageContainmentReadinessResolution` applies the same distinction
  to the complete contract recipe set before canonical mutation.
- External-observer, postimage-verifier, and mutation-preparation production
  APIs have non-optional default resolvers returning the terminal
  ordinary-macOS decision.
- A future privileged resolver must explicitly return `.authorized` with the
  existing exact activation/run/transaction/contract capability. It cannot
  gain authority by returning a Boolean, decoded receipt, or omitted result.
- Durable launch-veto case names now record the precise platform conclusion.
  Their raw values remain `residentMemoryEnforcementUnavailable` and
  `containmentReadinessUnavailable`, preserving schema-v1 journal decoding and
  deterministic replay.

No physical-memory enforcement is claimed. Default production still journals
the exact launch veto before any lease/process and the exact contract-wide
veto before any canonical workspace effect. The change retires an impossible
strategy while preserving a future unforgeable isolation route.

## Verification

- Exact platform: macOS 26.5.2 build 25F84, arm64; Xcode 26.6 build 17F113;
  SDK `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk`.
- SDK `sys/resource.h` SHA-256:
  `7d16930e6b75f11ba203238faa5580d31d48fcd4230f2b3f604aaa5fd7e86b58`.
- SDK `mach/task.defs` SHA-256:
  `f5c7269165d61c377164ee322da38a56493cdfc165bd16b1dc0706b9aff16ad7`.
- Current physical-footprint probe source SHA-256:
  `08aa0c4e25e2263c7091e32716e3591e142bebf4df0e51023d7e3be03fb4c542`;
  its expected no-access exit is forensic evidence and counts no successful
  runtime interval.
- Focused production-controller suite: 44 tests, 0 failures.
- Focused resolution/schema suite: 5 tests, 0 failures.
- Package-owned complete suite: 868 tests, 8 intentional environment skips,
  0 failures, 77.152 test seconds / 77.204 wall seconds.
- Dirty-source snapshot:
  `b941070c46a9547eed6233bc891a8a52756556b84a7952ab3fb0949d9c9fa549`.
- Signed application executable SHA-256:
  `4703466d894215ab0db2e94139bd60fbb3e2941a5ab01d31749cdeaabf25699d`;
  CDHash `f3eb06ad41ab48f101041612d8873d25a23758ac`.
- Direct and mounted startup, deep strict signing, all-three-Mach-O mounted
  byte identity, checksum verification, detach, and cleanup passed.
- Git diff whitespace passed. EasyBusiness remained read-only at branch
  `codex/USA_Version`, HEAD
  `2ae40452e6d8661c46db466c43ea40bba3bfab04`, with unchanged status
  fingerprint
  `2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.

## Acceptance boundary

The ordinary-macOS in-process issuer is no longer an unresolved coding task.
The retained veto is the accepted terminal behavior for the current product
architecture. Mutation-backed verifier/reviewer/observer execution requires a
separately designed and ratified privileged or virtualized isolation product
boundary. Productive provider backend ratification and native launch cutover,
the complete native trait/window/baseline/candidate matrix, clean-revision
rebuild, commit, and push remain pending. Final release remains false.
