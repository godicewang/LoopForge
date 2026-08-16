# Kernel Worker Process Transport

Status: **secure journal-private file transport and natural-exit release implemented, full-regression verified, packaged, signed, and runtime-smoke verified; production Codex provider remains deliberately disconnected**

Recorded: `2026-08-11T10:44:45Z`

## Forensic defect

The execution-composition boundary could issue an exact activation proof and the
managed runtime could own a PID and process group, but it could not yet carry a
worker prompt or retain a worker result. `ProcessGroupRuntimeAdapter` connected
stdin, stdout, and stderr to `/dev/null`. The only existing model runner with
usable pipes was the legacy `ProcessRunner`, which does not participate in the
new hash journal, runtime supervisor, activation-proof check, resource leases,
or occurrence accounting.

Reusing that runner would have restored a second execution authority. Adding
shell redirection would also have introduced path traversal, symlink following,
evidence overwrite, and incomplete cleanup risks. A second gap appeared at the
other end of execution: a normally exiting worker had no journal-first release
path. It could be terminated artificially or disappear natively while leaving
logical ownership and active-time state unresolved.

## Implemented boundary

- `ManagedProcessIOFiles` names one exact directory plus three basename-only,
  distinct stdin/stdout/stderr files.
- The managed adapter opens the directory with `O_DIRECTORY`, `O_NOFOLLOW`, and
  `O_CLOEXEC`, then opens all files relative to that directory with `openat`.
- Input is read-only and no-follow. Output and error are regular-file-only,
  exclusive, no-follow, mode `0600`, and cannot overwrite prior evidence.
- Traversal components, absolute filenames, NULs, non-normalized names,
  duplicates, final-component symlinks, and non-regular files fail before
  process launch. Spawn failure removes only outputs created by that attempt.
- No shell, shell redirection, workspace-relative resolution, or legacy runner
  is used.
- `JournaledProcessRuntime` independently requires the I/O directory to resolve
  to the exact journal run directory before productive admission or launch.
  Activation proof, journal state, runtime lease, PID/process-group identity,
  and I/O confinement are therefore conjunctive rather than caller promises.
- `joinAndRelease` now joins the complete owned process group, records an exact
  native exit receipt, journals release before supervisor commit, and preserves
  logical ownership when join, journal, or supervisor commit is uncertain.
- Release receipts distinguish natural exit from managed termination and reject
  a receipt claiming both.
- The occurrence bridge closes a natural completion only from the same open
  token, handle, native exit, journal transaction, and released lease. The
  interval ends at native exit, excluding later release latency. An unjournaled
  or cross-wired exit counts zero.

No EasyBusiness byte, task record, process, Git ref, or working-tree state was
changed. The historical Auto Graph remained stopped.

## Adversarial verification

New tests prove that:

1. an exact prompt reaches `/bin/cat`, exact output/error evidence is retained,
   and created files are `0600`;
2. an existing output cannot be overwritten;
3. traversal and symlink input fail before launch;
4. even a valid activation proof cannot direct evidence outside the private
   journal directory;
5. a natural process exit journals release, removes both journal and supervisor
   leases, and closes exactly one successful occurrence;
6. cross-wired natural-exit provenance and a release claiming both exit and
   termination are reducer-rejected.

The focused suites passed **35 tests, 0 failures**. The complete development
suite passed **630 tests, 8 environment skips, 0 failures**. The package-owned
suite independently passed the same **630 tests, 8 skips, 0 failures**.

## Package and integrity receipts

- release source snapshot: `6a47a7b8c5b22bc699f2b55abbfda300032124fe63c69182efeedf5f5d2ad603`
- focused test log: `f072078996906531abd17838ebac26f5c5da9fe9a2c074ef064c152a86820120`
- development test log: `c688fe549abde2e39fea1b32c5b5e4752d2bab513d9eded717ccef34241d2439`
- package test log: `dd820a582d51d0f144d65eba3468a043221376e5ea7d96b9ed66ccf66106b6d3`
- package log: `d730e6789dd513607bcd74749caa07ffe7d8486310f03a99ee806f670e2f0d2b`
- build manifest: `ec7cc0968a940148049fdc655f228f05580f277516b75b21c815b7509505c063`
- executable: `7f53c72014fc40f490a1e24d6e0b496d16be925b0652c186b99bb3c33918308d`
- ZIP: `b0f434674363a92eb0f868f29a9de3da8400bcdd596e6cf9905ce491caed2ffc`
- DMG: `8884262e0ddd309d09ce56ee4197ef796b3ace1f1b2d911e196898d27bcd3102`
- checksum manifest: `ea170f3b1a67c546d46dbfa19778211643b5cd7e303ef5a3cb5c50751588b698`
- runtime smoke: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- CDHash: `fe709f38264effbb7bbd11962002eaedd22a1e06`
- residual exact packaged processes: `0`

## Remaining boundary

This is the safe transport substrate, not a worker-provider cutover. There is no
production compiler from a kernel node/attempt into a Codex invocation, no
provider result parser, no execution-result journal command, and no end-to-end
planner/worker/verification/visual/integration/completion loop. Those pieces
must consume the existing activation proof and this transport without importing
legacy `ProcessRunner` authority. Current unlocked native UI screenshots, a
clean commit-bound rebuild, commit, and push remain pending. Final acceptance is
false.

