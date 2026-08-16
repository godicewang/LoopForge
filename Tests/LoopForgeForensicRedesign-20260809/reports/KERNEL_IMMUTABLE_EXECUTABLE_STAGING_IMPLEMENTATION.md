# Kernel Immutable Executable Staging

Status: **content-addressed journal-private executable staging and strict result proposal enforced; provider/disposition cutover remains vetoed**

Recorded: `2026-08-11T15:33:54Z`

## Closed boundary

`JournaledProcessRuntime` no longer verifies one workspace pathname and then
hands that same mutable pathname to `posix_spawn`. Before admission, it asks
`KernelExecutableStager` to materialize the exact profile-authorized SHA-256 in
`<run>/runtime-executables/<sha256>`, then rewrites the launch specification to
that artifact. The original invocation identity is retained as `argv[0]`, and
the launch receipt records the source path, staged path, digest, byte count,
device, inode, materialization method, and reuse decision.

The staging directory is opened relative to the already trusted run directory
with `O_DIRECTORY | O_NOFOLLOW`, must be owned by the effective user, and must
deny every group/other permission. Source and staged artifacts are regular
files opened with `O_NOFOLLOW`. Existing content-addressed artifacts must be
single-link, owner-executable, non-group/other-writable, bounded, and byte-for-
byte digest-correct.

Materialization prefers APFS clone-on-write through `fclonefileat`. The clone is
an independent inode and is hashed again before admission. If cloning is not
supported, the fallback uses a bounded 64 KiB streaming copy, hashes the bytes
as they are written, and proves that the source device, inode, size, and total
byte count did not change. Both paths have a 512 MiB hard limit. The temporary
artifact is mode `0500`, file-synced, installed without overwrite by
descriptor-relative `linkat`, unlinked by descriptor, and followed by a
directory `fsync`.

`ProcessGroupRuntimeAdapter` still hashes the staged artifact immediately
before spawn. Its external process identity now binds staged path, preserved
`argv[0]`, executable digest, PID, and native start time. The stager is invoked
once per authorization path; admission and launch consume that same typed
authorization rather than staging twice.

## Adversarial verification

Five dedicated staging tests prove:

- exact materialization and content-addressed reuse retain one staged inode;
- the staged test worker still executes after its source pathname disappears;
- source mutation after staging cannot change staged bytes;
- a symlink replacing the staging directory fails closed; and
- wrong bytes at the content-addressed destination fail closed.

The journaled runtime suite additionally proves that an unsafe staging
directory fails before admission, leaving the journal sequence, supervisor
lease set, and native process set unchanged. The test worker is a tiny package
fixture with no external dependencies because copied Apple platform binaries
are rejected by macOS AMFI outside their protected system location; the
production boundary was not weakened to accommodate that behavior.

Focused staging/runtime suites passed **26 tests** with zero failures. The
combined staging/runtime/host-resource suites passed **45 tests** with zero
failures. The complete development suite and package-owned suite each passed
**660 tests**, with **8** environment-gated skips and zero failures.

## Threat-model limit

This closes the workspace/sandbox source-path replacement race under the
kernel's scoped process model: after authorization, launch no longer depends on
the mutable workspace executable. It is deliberately not described as an
atomic descriptor-execution primitive. macOS `posix_spawn` still consumes the
journal-private pathname, so an arbitrary unsandboxed process running as the
same user could attack that path before spawn. Production cutover therefore
still requires the native sandbox/authority boundary to prevent untrusted
workers from writing the journal tree.

## Still-open production vetoes

1. issue declared-variable and provider-secret capabilities without
   serialization (the credential-free minimal child environment is enforced);
2. enforce sandbox, network, and plugin policy with native attestations;
3. **Done as proposal evidence:** retain and hash stdout/stderr in journal-owned
   files and parse exactly one nonce-bound terminal JSONL envelope;
4. derive execution disposition from exact native exit, lease release, output
   digests, parser identity, and invocation; and
5. retire the legacy `CodexRunner` execution path before provider cutover.

The old EasyBusiness Graph remained stopped and disconnected. No EasyBusiness
file, task, process, Git state, or worktree was modified.

## Exact package evidence

- Git revision: `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0` (dirty exact-source binding);
- source snapshot: `35d6cd61867312057a6fb8573b0d96e14f2755a0bf7e4256a70e9858eeedb887`;
- package test log: `1009c28a5e601aa3eb04608dce07b66cce589742b69c4e295ca07b123f2f9bab`;
- build manifest: `fb9d3762b1b81cdd6b1e94578707a93dc9d47c7b2ca75b09fdb74f8bc58e5985`;
- executable: `13723385439da402b6734614bad196f74d502cc3d61a36e6762f3b5b452cbabf`;
- ZIP: `ccf30edfb56062c3450ef8a2ce3f6a631bfab0a948a6fc701ff0ab39a6940394`;
- DMG: `a2c968a21c99fccb5a9d6e804522df4df98f8c7b9eab6f94e8f3875e9addb27f`;
- checksum manifest: `dec4e6326193ba631727efc5511cff826a7e7cd1f64707278060ee864bc34ab9`;
- CDHash: `7647be1bff2cde029abf1b7de86b4d25a90e3809`.

Deep signature verification, checksum verification, independent ZIP extraction,
DMG verification and read-only mount, identical executable hashes across all
three copies, exact Mach-O startup, cleanup, and zero residual packaged
processes passed. Three unmounted read-only devices left by repeated DMG
verification were identified by exact image path and detached; the explicit
temporary extraction directory was removed. Native UI screenshots were not retried because the recorded
macOS lock had no external state change. Final acceptance remains false.
