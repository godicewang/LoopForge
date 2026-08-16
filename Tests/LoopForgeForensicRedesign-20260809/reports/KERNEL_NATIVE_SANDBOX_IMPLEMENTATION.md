# Kernel Native Sandbox Implementation

Status: **read-only and workspace-only native process isolation is enforced and attested before journal binding; unsafe Full Access fails closed**

Recorded: `2026-08-11T17:01:12Z`

## Closed defect

The journaled runtime previously bound a user-confirmed sandbox enum but launched
the worker without a native policy. A same-user worker could therefore edit the
journal files whose bytes later authorize parsing, execution derivation, review,
and completion. User confirmation text was being mistaken for enforcement.

LoopForge now compiles a deny-default Seatbelt profile for every journal-owned
worker. `readOnly` grants no pathname writes. `workspaceOnly` grants writes only
beneath the exact physical workspace path. Both variants permit reads and the
minimum process operations, deny network unless the ratified profile enables it,
and permit data writes only to `/dev/null` plus the exact parent-opened stdout and
stderr files. The journal path is digest-bound as evidence but never receives an
allow rule.

Seatbelt allow rules compose additively, so a global write allow cannot be
narrowed by a later journal deny. `fullAccess` therefore rejects before runtime
admission, executable staging, or native spawn. LoopForge does not publish a
misleading protection receipt for an isolation policy macOS cannot express.

## Pre-exec attestation

The signed package now contains a 77,280-byte `KernelSandboxGate` executable.
The adapter launches `/usr/bin/sandbox-exec`, which enters the profile and starts
that gate. The gate:

1. marks a dedicated handshake descriptor close-on-exec;
2. stops itself before target execution;
3. preserves the exact kernel-issued environment and argument vector; and
4. calls `execve`, returning the exact errno over the handshake on failure.

While the gate is stopped, the parent requires all of the following before
continuing it:

- the expected PID is its own process-group leader;
- `sandbox_check(pid, nil, 0) == 1`;
- launcher, gate, profile, parameter, workspace, journal, and output digests
  match the authorization receipt; and
- the process start identity is captured while the PID is stable.

After resume, EOF on the close-on-exec handshake proves target `exec` succeeded.
Only then can `JournaledProcessRuntime` publish the external binding. The full
attestation is part of `RuntimeExternalIdentity`, journal replay, recovery, and
the composite stable process digest. Short-lived targets reuse the identity
captured at the stopped gate, so a successful instant exit is not misclassified
as a failed launch.

## Journal evidence protection

The parent creates stdout and stderr descriptor-relatively and makes their
path permissions `0400`; the inherited descriptors remain writable to the
worker, while reopening the same path is denied by both POSIX mode and the
sandbox. A native regression proved that the worker can create a workspace file
under `workspaceOnly` but cannot create a journal sibling. The retained output
contained the expected `status:0:1` result and both evidence files remained
read-only.

Physical directory identity is derived from an open directory descriptor with
`F_GETPATH`, not lexical Foundation canonicalization. Workspace/journal overlap,
symlink redirection, unknown profile parameters, altered profile bytes, altered
digests, missing launchers, and mismatched I/O directories all fail closed.

## Verification

- native sandbox tests: **3 passed, 0 failed**;
- process-group adapter tests: **13 passed, 0 failed**;
- journaled runtime tests: **27 passed, 0 failed**;
- complete development suite: **668 tests, 8 skips, 0 failures**;
- package-owned suite: **668 tests, 8 skips, 0 failures**;
- exact-source app, ZIP, read-only DMG, signatures, checksums, direct Mach-O
  startup, cleanup, and zero residual LoopForge/gate processes: passed.

Package identities:

- source snapshot: `16506452a6dd8c7d067ee74bf782c47067829257e5ca6052fc658c931a60ad3f`;
- package test log: `ec8dd2fc6ad83a4e61897fea80d48790fddf9ba749edc0455bee4c40529f37f5`;
- build manifest: `074d69354794ec7abde342f948153970fdb8d17f0a9367967a520ad280bd1d06`;
- main executable: `1217f26e74cbf42a32f396dc17ce974852106bc8d5dc33a7e019eee3dd901c8e`;
- sandbox gate: `11570aa19dd28134444bf7490dd7395e6f189389a833d877214e9d397d3c0641`;
- ZIP: `46f6e1521810f612f2dfcc754870a17b980751461b6cc810cbfb573c883fd65b`;
- DMG: `af730b3ae7cca12062256b0f6459ac8ccad8e9cd3924985d05b712ed38a953f6`;
- checksum manifest: `6392e47bc3ec1a40e7473844fcd4faa216df67ecea24883f641f18587794a514`;
- app CDHash: `9b837e4d1aea972f8944518e67b5a9d79e993a38`;
- gate CDHash: `fed6f262dcbba80109821956d99871954ad69f9a`.

Provider secrets, declared environment capabilities, deterministic provider
invocation, independent review/verification/integration/completion composition,
current unlocked native screenshots, clean commit-bound packaging, commit, and
push remain unresolved. Final acceptance remains false. EasyBusiness remained
stopped and read-only.
