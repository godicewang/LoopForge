# Kernel Strict Retained Worker-Result Parser

Status: **exact retained stdout/stderr parsing and proposal receipt are journal-bound; execution disposition cutover remains vetoed**

Recorded: `2026-08-11T15:33:54Z`

## Closed result-evidence path

The disconnected journaled worker path now has a bounded parser for retained
JSONL. It opens the journal-owned output directory and files with no-follow,
descriptor-relative operations, verifies owner/type/link count/mode/size before
and after bounded reads, and hashes the exact stdout and stderr bytes that were
observed. It accepts output only after a journaled natural exit with exit code
zero and no signal.

Every stdout line must be the exact sorted-key, slash-stable canonical encoding
of one known schema. Unknown keys, prose, Markdown, noncanonical whitespace,
invalid UTF-8, empty lines, missing final newline, negative or internally
inconsistent limits, oversized files or lines,
more than 4,096 envelopes, discontinuous sequence numbers, mixed threads,
non-ASCII or non-lowercase digests, wrong invocation digest, wrong request
nonce, duplicate terminal envelopes,
data after the terminal envelope, and a missing terminal envelope all fail
closed. Exactly one terminal envelope must be last. Its disposition and result
digest are retained as **worker proposals**, never reducer authority.

`JournaledProcessRuntime.parseReleasedWorkerResult` requires the exact launch,
binding, release, attempt, resource, lease, invocation, nonce, native-exit, and
journal-owned I/O identities. `RunReducer.recordWorkerResultParse` independently
matches those fields against accepted binding and release receipts, requires the
resource to be no longer live, and journals `workerResultParsed`. It does not
set `AttemptState.disposition`. Idempotent replay returns the original exact
transaction without rereading or appending output.

## Adversarial coverage

Dedicated tests prove canonical event plus terminal parsing; exact byte hashes;
nonce, invocation, sequence, and single-thread binding; canonical-key closure;
truncation and terminal rules; size and count bounds; traversal and symlink
rejection; nonzero native-exit rejection; journal replay; idempotent parsing;
and unchanged journal sequence/state when an otherwise valid receipt is copied
but cross-wired to an unrelated release receipt. A real dependency-free native
fixture emitted the terminal envelope through the journal-owned stdout file,
exited naturally, was released, parsed, and replayed while its attempt
disposition remained `nil`.

The focused kernel/runtime/journal combination passed **87 tests, 0 failures**.
The complete development and package-owned suites each passed **660 tests**, with
**8** environment-gated skips and zero failures.

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

Deep signature, checksum, exact packaged Mach-O startup, independent ZIP
extraction, DMG verification and read-only mount, identical executable hashes,
temporary-directory cleanup, zero exact residual processes, and zero exact DMG
attachments passed.

## Remaining stop-the-line boundaries

The legacy direct `recordExecution` command still accepts caller-selected
disposition and has not been retired for new writes. No provider-secret
capability or native sandbox attestation exists. A same-user process is not yet
prevented by the OS from modifying retained journal-path files; this parser
attests exactly what it observed but does not claim to solve that trust boundary.
The legacy `CodexRunner` remains disconnected. Current native screenshots,
provider and verification composition, clean commit-bound rebuild, commit, and
push remain required. Final acceptance is false. EasyBusiness remained stopped
and read-only.
