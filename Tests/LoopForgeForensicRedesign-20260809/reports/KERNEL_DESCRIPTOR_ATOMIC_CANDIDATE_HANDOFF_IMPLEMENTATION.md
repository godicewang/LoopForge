# Kernel descriptor-atomic candidate handoff

Recorded at: `2026-08-12T03:25:52Z`

## Outcome

Postimage-verifier admission no longer revalidates a candidate pathname and
then lets the child reopen that pathname. Immediately after admission, the
runtime opens the sealed candidate root with `O_DIRECTORY | O_NOFOLLOW`,
checks the materialization receipt's exact device/inode, and validates every
directory entry, file mode, size, and content digest through that held root
descriptor. A second descriptor-relative tree listing plus root-stat check
rejects mutation during validation.

The resulting non-Codable capability stays open across the spawn boundary.
The process adapter verifies it against the exact activation materialization,
then orders `posix_spawn_file_actions_addfchdir_np` before the sandbox launcher
executes. The verifier recipe binds its sole candidate input to `.`. This makes
candidate lookup derive from the held directory object, while
`POSIX_SPAWN_CLOEXEC_DEFAULT` removes the source descriptor from the child.
The stopped sandbox gate is inspected with `PROC_PIDVNODEPATHINFO`; launch
evidence records the observed current-directory device/inode and the
`posixSpawnFileActionsFchdir` mechanism. Replay requires those values to equal
the activation materialization receipt.

## Retired strategies

- Passing the materialized absolute path was retired because replacement
  after revalidation could redirect the verifier.
- Passing `/dev/fd/N` was tested through the real native sandbox chain and
  retired because this macOS runtime does not permit a directory descriptor to
  be reopened through that pathname.
- Inheriting an open directory into the signed gate and calling `fchdir` there
  was retired because the sandboxed gate did not reach its stopped-attestation
  boundary on the tested host.
- Explicitly closing the source descriptor after the spawn `fchdir` action was
  retired because Darwin rejected that action composition; the already-enabled
  CLOEXEC-default policy provides the correct non-inheritance semantics.

## Verification

- Candidate materializer tests: 4 tests, 0 failures, including held-root
  survival after pathname replacement and rejection of a replacement root.
- Native journal/integration scenario: 1 focused scenario and 8-test suite,
  including timeout and natural-exit verifier branches, 0 failures.
- Process adapter: 15 tests, 0 failures.
- Journaled runtime: 28 tests, 0 failures.
- Native sandbox: 6 tests, 0 failures.
- Result authority: 3 tests, 0 failures.
- Complete Swift suite: 716 tests executed, 8 intentional environment skips,
  0 failures.
- Release LoopForge SHA-256:
  `03ee0592b9669fb4c48d23664cd73ae394ba94e53c1e4bf7177208be2ccf9e82`.
- Release KernelSandboxGate SHA-256:
  `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source snapshot SHA-256:
  `addb2a39ef96281ce4024790a0bd43656b395b2ad839e440f838c283bfa0bc8e`.

## Boundary retained

This closes candidate identity handoff only. Production verifier launch still
fails closed because no tested resident-memory enforcement issuer exists.
Independent review, integration reliance, native baseline/visual authority,
native start/UI verification, package/sign, clean commit, and push remain
vetoed. EasyBusiness remained read-only.
