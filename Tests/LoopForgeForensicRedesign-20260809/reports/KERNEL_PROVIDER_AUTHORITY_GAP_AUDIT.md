# Kernel Provider Authority Gap Audit

Status: **journal-owned prompt issuance, mandatory release provider invocation, fixed-FD secret transport, atomic replayed provider-launch evidence, execution profile, staged executable, minimal environment, native sandbox, strict retained result, and reducer-derived disposition exist; controller/reviewer/completion cutover remains vetoed**

Recorded: `2026-08-11T18:23:35Z`

## Scope

This audit follows the new-kernel path from native contract confirmation through
enrollment, execution preparation, activation, managed process transport,
provider invocation, result parsing, execution disposition, and occurrence
accounting. It does not launch Codex, create a task, resume Graph, or touch the
forensic EasyBusiness workspace.

## Blocking findings

### 1. Worker profile was not part of confirmed authority — resolved

The task-creation surface collects worker/control provider, model, reasoning,
and access selections. `prepareNativeAutoGraphContract`, however, forwards only
objective, workspace, read/write scopes, duration, and user actor into
`NativeTaskContractAuthoringRequest`. The confirmation sheet displays only
objective, workspace scopes, acceptance, and the contract digest.

The audited version therefore did not bind:

- provider kind or endpoint identity;
- executable content identity;
- model or reasoning effort;
- sandbox/access mode;
- plugin/tool-loading policy;
- environment allow-list;
- network policy; or
- independent reviewer-provider separation.

This gap is now closed at authoring, confirmation, compilation, and enrollment.
A provider-neutral worker/reviewer profile is displayed, canonicalized into an
exact user source artifact, semantically checked against the contract, included
in the candidate digest, and journaled in `runCreated`. Production enrollment
rejects legacy contracts with no profile. The reviewer is ratified as read-only,
offline, plugin-free, minimally isolated, and distinct-lineage-required. Full
Access without a native capability grant fails before confirmation rather than
silently downgrading. Activation and process materialization now enforce the
exact journaled worker profile, activation actor, active causal attempt, and
executable digest. The authorized executable is materialized as a content-
addressed independent inode inside the journal-private run directory before
admission; the launch receipt binds its digest, device, inode, byte count, and
materialization. This closes the mutable workspace-path race under the scoped
kernel model. The native sandbox now prevents the journal-path attack for
read-only and workspace-only workers. Provider execution remains disconnected.

### 2. Legacy Codex execution bypasses the kernel

`CodexRunner.runTurn` is built around `ProcessRunner`, mutable `LoopTask`,
callbacks, and legacy watchdog/accounting state. It creates/resumes Codex
threads directly and can use compatibility bridges and host-resource helpers
that are not represented by the new kernel's activation proof or journal.

It cannot be wrapped as the production kernel provider. Reuse must be limited to
pure argument/event-decoding logic after those parts are separated from process
ownership and authority.

### 3. Ambient environment was overbroad — resolved for the minimal policy

`CodexRuntime.environment()` begins with the complete application environment
and then edits `NO_COLOR` and `PATH`. Passing that map into a journal-owned
worker would expose unrelated credentials and configuration that the confirmed
contract never named. The journaled runtime now rejects every caller-supplied
environment and generates exactly `LANG=C`, `LC_ALL=C`, `NO_COLOR=1`, and the
fixed system `PATH`. A length-prefixed canonical SHA-256 is returned in the
launch receipt, persisted explicitly in the external identity, included in the
composite process identity, and independently recomputed immediately before
spawn. A dependency-free Darwin child observed exactly those four variables.

The declared-variable policy remains fail-closed until a typed per-variable
grant issuer exists. Provider secrets now have a separate opaque,
non-serialized, one-use descriptor-delivery capability bound to the exact run,
attempt, provider reference, and deterministic invocation digest. It never
enters the environment, argv, disk, or a recoverable receipt. The secret now
crosses a dedicated inherited pipe at fixed child FD 197 through the signed
sandbox gate only after target-exec handshake. The child write end and parent
read end are closed, failure kills and reaps the exact owned group, and the
delivery receipt contains no secret bytes, size, or hash. The legacy ambient
environment helper remains disconnected.

### 3a. Caller-supplied provider argv was unbound — resolved at the release process boundary

Executable identity did not constrain arguments, and the stable process digest
omitted argv. A caller could therefore reuse the ratified executable while
requesting different provider/model/reasoning/sandbox/plugin/fan-out behavior.

The new compiler accepts only the activated proof, a non-serializable journal-
issued prompt artifact authority, and a request nonce. It emits one exact provider-neutral
harness protocol; remote-without-network and broad plugin authority reject, and
hidden fan-out is always disabled. The argument-vector digest is recomputed
before spawn, persisted explicitly in external identity, and included in the
stable process digest. The prompt is created exclusively and descriptor-
relatively beneath the run journal, bound to device/inode/digest/size, and the
already-open stdin descriptor is rehashed and rewound immediately before spawn.
Release builds expose only `prepareProviderInvocation` and
`admitAndLaunchProvider`; generic runtime and adapter launch APIs are DEBUG-only.

### 4. Caller-supplied execution disposition — resolved

The audited `RunCommand.recordExecution(attemptID:disposition:)` accepted a
caller-selected `completed`, `continuationNeeded`, `blocked`, `failed`,
`malformed`, or `interrupted` disposition. That new-write authority is now
retired: every invocation rejects with `legacyExecutionAuthorityRetired` and
cannot advance journal sequence or state. Historical `executionRecorded`
events retain replay semantics only.

The former path did not require:

- the exact journaled natural-exit or termination receipt;
- the runtime lease and process binding for the same attempt;
- stdout/stderr/result-envelope digests;
- a strict response nonce/digest;
- executable/profile/prompt identity; or
- a parser receipt issued from the retained JSONL bytes.

The strict parser produces a typed proposal receipt whose exact binding,
release, natural exit, invocation, nonce, stdout digest, stderr digest,
terminal-envelope digest, result digest, and worker thread are journaled. A
cross-wired release receipt is rejected without advancing the journal. The
receipt deliberately leaves attempt disposition `nil`. New parser commands now
require a non-Codable parser-issued authorization whose initializer is
file-private; copied or decoded receipt values are not command authority.

The reducer alone maps the exact journaled parse receipt to a disposition and
persists `KernelExecutionDerivationReceipt` with run, attempt, source,
source-evidence digest, derived disposition, and time. Blocked, failed, and
malformed reasons are the parser-bound result digest. External dependency
blocking is likewise derived from an exact unavailable observation and its
evidence digest. `JournaledProcessRuntime` composes this path idempotently from
the exact parse transaction without accepting a disposition argument.

### 5. Strict retained-result parser — resolved as proposal evidence

The legacy `CodexEventCollector` still tolerates non-JSON presentation events,
but it is disconnected from kernel control. The new bounded parser now:

1. hashes exact stdout/stderr bytes before parsing;
2. rejects truncation, duplicate terminal events, trailing semantic data, and
   inconsistent thread identities;
3. accepts exactly one final schema envelope bound to the invocation digest and
   nonce;
4. treats all model status/evidence fields as proposals;
5. maps native nonzero/signal exits independently; and
6. journals a parser receipt before any execution transition.

Every stdout line must be exact canonical sorted-key JSON with only known keys.
It rejects narrative text, noncanonical encoding, invalid UTF-8, truncation,
oversize input, sequence gaps, thread changes, nonce/invocation mismatch,
duplicate or nonfinal terminal envelopes, traversal, symlinks, and nonzero
native exit. It reads journal-owned files descriptor-relatively with no-follow
and pre/post metadata checks. The parser attests exactly observed bytes; native
sandbox enforcement now excludes that same-user journal-path writer attack.

### 6. Native process sandbox was only declared — resolved for safe policies

The ratified sandbox enum previously affected receipts but not the OS launch.
The journaled path now executes through a deny-default Seatbelt profile and a
signed self-stopping gate. Before resuming the gate, the parent observes
`sandbox_check == 1`, exact process-group ownership, exact launcher, gate,
profile and parameter digests, and a stable PID start identity. A close-on-exec
pipe proves the target replaced the gate before any journal binding can be
published; exec failure returns exact errno and cleans up without a binding.

Read-only workers receive no pathname write rule. Workspace-only workers receive
one exact physical workspace-subpath rule. The journal path is digest-bound but
never allowed. Parent-opened stdout and stderr descriptors remain usable while
their paths are `0400`. An adversarial native test created a workspace file and
failed to create a journal sibling. Because Seatbelt allow rules cannot express
global writes followed by a narrower journal deny, Full Access fails before
admission, staging, or spawn rather than issuing a false protection receipt.

## Cleanup race discovered and fixed

The prior transport correctly opened output evidence relative to a no-follow
directory descriptor, but spawn-failure cleanup stored absolute path strings and
called `unlink`. A rename/replacement between open and cleanup could redirect
deletion into a new unrelated directory containing the same filename.

Cleanup now retains the original directory descriptor and calls `unlinkat` with
validated basename-only entries. It never resolves the supplied path again.
The adversarial test renames the original directory, recreates the old path,
places an unrelated same-name sentinel there, and submits a traversal cleanup
name. Only the file in the descriptor-owned original directory is removed; the
replacement sentinel and outside file survive.

## Required cutover sequence

1. **Done:** add a provider-neutral, user-visible worker/reviewer execution
   profile and bind its canonical user source through confirmation and
   `runCreated`.
2. **Done through native pre-spawn:** bind the profile, activation actor, and
   executable content digest through confirmation, activation proof, journal
   state, content-addressed journal-private staging, runtime admission, and
   adapter launch.
3. **Done for the credential-free minimal policy:** construct and digest-bind
   the child environment in the journaled runtime; reject caller dictionaries
   and declared variables without typed grants.
4. **Done for native process isolation:** enforce and attest read-only or exact
   workspace-only Seatbelt policy before worker exec; unsafe Full Access fails
   closed.
5. **Done at the release process boundary:** compile a deterministic
   provider-neutral invocation with plugins and hidden fan-out disabled, exact
   prompt/nonce/profile binding and pre-spawn argv digest verification, and
   require the non-serializable wrapper in the release provider launch path.
6. **Done for launch I/O:** create prompt and output artifacts with descriptor-
   relative exclusive I/O in the journal directory; recheck prompt inode and
   exact bytes before spawn.
7. **Done as proposal evidence:** parse retained JSONL through the strict
   nonce-bound schema and journal exact output digests.
8. **Done:** retire direct `recordExecution` writes and derive a durable
   execution receipt from the exact journaled runtime release and parser output.
9. Only then connect planning, worker execution, independent review,
   verification, mutation integration, and completion.

## Verification

- native sandbox suite: **5 tests, 0 failures**;
- process-group adapter suite: **15 tests, 0 failures**;
- provider invocation and secret capability suite: **9 tests, 0 failures**;
- journaled runtime suite: **28 tests, 0 failures**;
- real journaled provider fixture launch/join/release: **passed**;
- complete development suite: **682 tests, 8 skips, 0 failures**;
- non-DEBUG release build: **passed**;
- package-owned suite: **668 tests, 8 skips, 0 failures**;
- exact-source signed package, ZIP, DMG, checksum manifest, executable startup,
  cleanup, and zero residual packaged processes: passed.

Prior package identities (superseded by current unbundled source changes):

- source snapshot: `16506452a6dd8c7d067ee74bf782c47067829257e5ca6052fc658c931a60ad3f`
- package test log: `ec8dd2fc6ad83a4e61897fea80d48790fddf9ba749edc0455bee4c40529f37f5`
- build manifest: `074d69354794ec7abde342f948153970fdb8d17f0a9367967a520ad280bd1d06`
- executable: `1217f26e74cbf42a32f396dc17ce974852106bc8d5dc33a7e019eee3dd901c8e`
- sandbox gate: `11570aa19dd28134444bf7490dd7395e6f189389a833d877214e9d397d3c0641`
- ZIP: `46f6e1521810f612f2dfcc754870a17b980751461b6cc810cbfb573c883fd65b`
- DMG: `af730b3ae7cca12062256b0f6459ac8ccad8e9cd3924985d05b712ed38a953f6`
- checksum manifest: `6392e47bc3ec1a40e7473844fcd4faa216df67ecea24883f641f18587794a514`
- app CDHash: `9b837e4d1aea972f8944518e67b5a9d79e993a38`
- gate CDHash: `fed6f262dcbba80109821956d99871954ad69f9a`

Final acceptance remains false. The provider launch receipt is now an
unforgeable first-class replayed journal event, atomically recorded with the
runtime binding and independently required by strict result parsing. The
production controller, independent reviewer, verification, visual review,
integration, and completion paths are not composed through this provider
boundary; current-source packaging, native
screenshots, clean commit, and push remain required.
