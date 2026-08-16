# Kernel Minimal Process Environment

Status: **credential-free minimal launch environment and strict result proposal are journal-bound; declared variables, provider secrets, sandbox, and disposition cutover remain vetoed**

Recorded: `2026-08-11T15:33:54Z`

## Closed authority path

The journaled runtime no longer accepts an environment dictionary as worker
authority. `KernelProcessEnvironmentAuthorizer` constructs one fixed,
credential-free environment from the ratified `minimalKernelAllowlist` policy:

- `LANG=C`
- `LC_ALL=C`
- `NO_COLOR=1`
- `PATH=/usr/bin:/bin:/usr/sbin:/sbin`

Every sorted UTF-8 name and value is length-prefixed before SHA-256 hashing, so
separators inside values cannot create an ambiguous representation. The exact
digest is
`e5a204343042c54829f3a41364ca4b85a37c7366a2d57ba707dc774d62309442`.
The retained receipt contains only the policy, sorted variable names, and
digest; it never serializes values or credentials.

`JournaledProcessRuntime` authorizes this environment before admission,
rejects every caller-supplied variable and every caller-supplied mismatching
environment digest, rewrites the managed process specification to the fixed
map, and returns the receipt with the launch receipt. The runtime external
identity now persists the executable and environment digests explicitly in
addition to its composite stable digest. Missing explicit fields remain
decodable as `nil` for old journals.

`ProcessGroupRuntimeAdapter` independently recomputes the environment digest
immediately before `posix_spawn` and rejects a mismatch before a native handle
exists. Thus a later adapter caller cannot substitute environment bytes after
journal authorization.

## Deliberate fail-closed boundaries

The ratified `declaredAllowlist` policy remains non-executable even when it is
inside the contract's authority ceiling. No trusted per-variable capability
issuer exists, so the kernel neither guesses values nor inherits host state.
Provider credentials require a separate opaque, non-Codable capability and
must never enter the environment receipt or journal. The retired
`CodexRuntime.environment()` path remains disconnected from this kernel path.

This change does not claim a native sandbox, network/plugin attestation, or
journal-derived execution disposition. Strict retained JSONL parsing, exact
output digests, and a nonce-bound terminal proposal now exist, but remain
proposal evidence until direct caller-selected disposition is retired. The
remaining boundaries are stop-the-line provider cutover vetoes.

## Adversarial and native verification

Dedicated tests prove that:

- the generated map contains exactly four variables and no host credentials;
- any caller-supplied name or secret fails before admission;
- a declared allow-list fails closed without a typed variable grant;
- the digest is ordering-independent and value-sensitive;
- a caller cannot replace the expected environment digest;
- the adapter rejects an environment mismatch before spawn;
- a real dependency-free Darwin worker observes exactly the four authorized
  variables and no stderr;
- the journal-bound lease carries the explicit environment digest; and
- legacy external identities decode with the new digest fields absent.

The Darwin fixture intentionally imports neither Foundation nor CoreFoundation:
CoreFoundation adds `__CF_USER_TEXT_ENCODING` during initialization, which is a
framework side effect rather than an input passed to `posix_spawn`. Reading the
raw `environ` in the dependency-free worker makes the launch boundary directly
observable.

The combined affected suites passed **83 tests, 0 failures**. The complete
development suite and package-owned suite each passed **660 tests**, with
**8** environment-gated skips and zero failures. Deep strict signature,
checksum, independent ZIP extraction, DMG verification/read-only mount,
identical executable hashes, exact packaged Mach-O startup, cleanup, and zero
residual packaged processes passed.

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

EasyBusiness remained stopped and read-only. Native screenshots were not
retried because the recorded macOS lock had no external state change. Final
acceptance remains false.
