# Kernel Provider Invocation Context Transport

Status: **exact post-compilation invocation identity crosses a kernel-owned fixed descriptor; production provider launch remains gated on a separately packaged harness and exact network authority**

Recorded: `2026-08-15T17:05:00Z`

## Result

The provider-output parser requires the worker to echo the exact invocation
digest and request nonce, but the invocation digest does not exist until after
the compiler has sealed the prompt, execution profile, executable, arguments,
transport policy, and request identity. LoopForge now closes that cycle without
placing the digest in caller-controlled arguments or environment.

`KernelProviderInvocationCompiler` assigns fixed descriptor **196** and emits
provider protocol `loopForgeProviderHarnessV2`. Immediately before native
spawn, `ProcessGroupRuntimeAdapter` derives a canonical sorted-key JSON context
payload solely from the authorized compiled invocation. The payload contains
only schema version, run ID, attempt ID, invocation digest, and request nonce,
is followed by one LF, is bounded to 4 KiB, and is completely written to a
CLOEXEC pipe before spawn. The signed sandbox gate inherits only the read end
at descriptor 196. Provider argv contains the descriptor number, never the
digest.

The adapter returns a deterministic transport receipt binding the target
descriptor, exact content digest, byte count, and staging monotonic time.
`KernelProviderLaunchReceipt` requires that receipt to match the compiled
invocation and to have been staged no later than the launch evidence. The
journaled runtime retains and revalidates the same receipt before parsing
output. This proves that the kernel staged the exact bytes before spawn; it does
not overclaim proof that an arbitrary untrusted child read them.

The real native sandbox fixture requires V2, reads descriptor 196 to EOF,
validates the digest and nonce against the invocation, consumes the immutable
prompt and optional credential descriptor, and emits canonical terminal JSONL
using the exact context values. Its output passed the strict retained-byte
parser and deterministic result derivation through `JournaledProcessRuntime`.

Historical V1 receipts remain decodable as evidence, but current validation and
compilation reject them. Missing context, wrong descriptor, changed digest,
changed nonce, late staging, substituted launch evidence, and decoded live
authority all fail closed.

## Verification

- V2 provider/context/sandbox/runtime focused set: **14 tests**, **0 failures**,
  **1.047 test seconds**;
- historical V1 decode/evidence-only test: **1 test**, **0 failures**;
- exact source suite before packaging: **819 tests**, **8 intentional skips**,
  **0 failures**, **63.145 test seconds**;
- package-owned source suite: **819 tests**, **8 intentional skips**, **0
  failures**, **64.873 test seconds**;
- real Codex child/Responses bridge: **19.135 seconds**;
- source snapshot:
  `bff4173a795286a7b895f053a990692982905f1211e44d655d94b5fe5f059f6f`;
- packaged LoopForge SHA-256:
  `b2e4c9463676fdd8c6151da83d1e64be21d27dc645b64e7fec6ddf70a53e3647`;
- deep-strict signature, ZIP, DMG, checksum manifest, embedded source/test
  binding, bounded exact packaged-Mach-O startup, and zero residual packaged
  processes passed.

## Boundary

Full production provider launch remains false. The transport is production
code and its real sandbox route is exercised, but the selected native
Codex/local/API executable is intentionally typed `unavailable`; no separately
packaged and independently ratified LoopForge V2 provider harness exists.
Exact profile-ratified Keychain credential resolution and fixed-descriptor
delivery are now present; remote execution still requires exact network
authority or must retain its veto. Mutation preparation/containment, trusted Release
external-observer containment or its veto, legacy Single/Parallel retirement,
unlocked current-source native screenshots, a clean-commit rebuild, commit, and
push remain pending.

EasyBusiness was only re-read. Its HEAD remained
`2ae40452e6d8661c46db466c43ea40bba3bfab04`; its current read-only status
fingerprint was
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
No EasyBusiness mutation is attributed to this interval. Final release remains
false.
