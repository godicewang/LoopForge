# Kernel Activation and Executable Authority

Status: **exact worker profile, staged executable, minimal environment, and strict result proposal enforced; provider/disposition cutover remains vetoed**

Recorded: `2026-08-11T15:33:54Z`

## Closed authority path

The confirmed `KernelAgentExecutionProfile` now contains the SHA-256 of the
exact executable harness selected by the native app. The digest is rendered in
the confirmation sheet, canonicalized into the user-authority execution-profile
source, included in the candidate digest, and persisted in `runCreated` with
the rest of the contract. A malformed or non-lowercase SHA-256 fails contract
validation. A pre-digest persisted profile remains decodable for forensic
recovery, receives an empty digest, and cannot validate or launch.

`KernelExecutionPreparationCoordinator.activate` now issues a non-serializable
proof that binds all of the following:

- run, attempt, node, and causal strategy fingerprint;
- the exact worker execution profile from the journaled contract;
- the exact activation actor identity and lineage; and
- the exact journal transaction that entered `executing`.

`JournaledProcessRuntime` rejects a productive process unless the proof,
runtime actor, journal contract profile, active reducer attempt, convergence
admission, and productive lease all agree. It now materializes the exact
profile-authorized executable in the journal's owner-private run directory
before admission. The launch path is content-addressed by SHA-256 and backed by
an independently rehashed APFS clone-on-write inode, or by a bounded rehashed
stream copy when cloning is unavailable. `ProcessGroupRuntimeAdapter`
independently hashes that staged file again immediately before `posix_spawn`.
The launch receipt retains the source and staged paths, digest, size, device,
inode, materialization, and reuse decision. A caller cannot omit or replace the
expected digest to weaken the check.

This boundary remains disconnected from the retired `CodexRunner` path. No
provider was launched and no EasyBusiness process or file was touched.

## Adversarial results

The runtime suite proves that:

- a proof from an unrelated journal transaction cannot launch;
- a proof carrying another provider/model/executable profile cannot launch;
- a runtime actor with another identity or lineage cannot consume the proof;
- a different executable with a valid path and permissions fails before
  admission, leaving journal sequence, supervisor leases, and native processes
  unchanged;
- a symlinked staging directory or wrong existing content-addressed artifact
  fails before admission;
- removing or mutating the source pathname after staging cannot alter or
  prevent execution of the staged artifact;
- a legacy contract without an execution profile cannot materialize; and
- a content-authorized but invalid native executable still follows the normal
  journaled admission/release compensation path after `posix_spawn` fails.

The runtime/staging focused suites passed **26 tests** with zero failures; the
runtime/staging/host-resource total passed **45 tests** with zero failures. The
complete development suite and package-owned suite each passed **660 tests**, with **8**
environment-gated skips and zero failures.

## Deliberately open vetoes

The mutable workspace/sandbox source-path race is closed under the scoped
kernel model: launch now uses a journal-private, content-addressed independent
inode. This does not claim atomic descriptor execution. macOS `posix_spawn`
still consumes a pathname, so an arbitrary unsandboxed process running as the
same user could attack the journal-private path before spawn. Native sandbox
attestation and denial of journal-tree writes therefore remain production
cutover vetoes.

Other mandatory vetoes remain:

1. issue provider-secret and declared-variable capabilities without serializing
   credentials (the credential-free minimal environment is enforced);
2. enforce sandbox/network/plugin policy with native attestations;
3. **Done as proposal evidence:** retain and hash stdout/stderr in
   journal-owned files and parse exactly one nonce-bound terminal JSONL
   envelope; and
4. replace caller-supplied `recordExecution` with a receipt derived from the
   exact native exit, release, output digests, parser identity, and invocation.

## Exact package evidence

- source snapshot: `35d6cd61867312057a6fb8573b0d96e14f2755a0bf7e4256a70e9858eeedb887`;
- package tests: `1009c28a5e601aa3eb04608dce07b66cce589742b69c4e295ca07b123f2f9bab`;
- build manifest: `fb9d3762b1b81cdd6b1e94578707a93dc9d47c7b2ca75b09fdb74f8bc58e5985`;
- executable: `13723385439da402b6734614bad196f74d502cc3d61a36e6762f3b5b452cbabf`;
- ZIP: `ccf30edfb56062c3450ef8a2ce3f6a631bfab0a948a6fc701ff0ab39a6940394`;
- DMG: `a2c968a21c99fccb5a9d6e804522df4df98f8c7b9eab6f94e8f3875e9addb27f`;
- checksum manifest: `dec4e6326193ba631727efc5511cff826a7e7cd1f64707278060ee864bc34ab9`;
- CDHash: `7647be1bff2cde029abf1b7de86b4d25a90e3809`.

Deep signature verification, ZIP extraction, DMG verification, checksum
verification, exact executable startup, cleanup, and a zero residual packaged
process count passed. Native screenshots were not retried because the known
macOS lock had no external state change. Final acceptance remains false.
