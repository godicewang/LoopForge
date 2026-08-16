# Kernel Candidate-Postimage Materialization Implementation

Recorded: `2026-08-11T22:56:45Z`

Status: **content-addressed read-only candidate input capability implemented; verifier activation, atomic admission/spawn, result receipt chain, latest-red revocation, independent review, and native start remain vetoed**

## Outcome

LoopForge can now consume the opaque candidate-postimage attestation issued by `RunJournal` and materialize those exact bytes outside the workspace into an owner-private content-addressed tree. The returned `AuthorizedWorkspaceCandidatePostimageInput` is non-Codable, has no caller-accessible initializer in Release, and binds the exact attestation to a byte-revalidated snapshot receipt.

This boundary starts no process, grants no verification verdict, and cannot be reconstructed from report JSON. EasyBusiness remained read-only.

## Materialization boundary

- The journal-owned attestation is validated for the exact canonical workspace before storage is opened.
- Storage equal to, inside, or containing the workspace is rejected.
- The live workspace is recaptured against the complete attested source revision before staging and again after every file is copied.
- The run and staging directories must be no-follow, owner-owned, owner-private directories. A nonblocking private lock serializes cooperating materializers.
- Every included source file is opened through descriptor-relative, component-validated, `O_NOFOLLOW` traversal.
- Every destination is created exclusively beneath a new private temporary directory.
- Streaming copy binds exact byte count and SHA-256 while source device, inode, mode, size, and nanosecond mtime are rechecked after EOF.
- The temporary tree is independently recaptured with no exclusions. Exact sorted paths, normalized read-only modes, sizes, per-file digests, and total bytes must equal the attestation.
- Files and directories are sealed without write bits, synchronized, and atomically renamed to `candidate-postimages/<source-revision>`.
- Existing content-addressed trees are never trusted by name: their root type, owner, mode, device/inode identity, complete entry manifest, and all content digests are revalidated before reuse.

Symlinked sources, drifted workspaces, overlapping storage, unsafe directories, changed files, extra/missing snapshot entries, tampered existing trees, and ambiguous system-call failures fail closed without returning input authority.

## Honest immutability boundary

The tree is content-addressed and read-only, but an owner process can restore write permission on an ordinary local filesystem. LoopForge therefore does **not** call the filesystem absolutely immutable.

`WorkspaceCandidatePostimageMaterializer.revalidate(_:)` reopens the sealed root with `O_NOFOLLOW`, independently rehashes the complete tree, verifies the original root device/inode and receipt, and fails after any tested tampering. A future verifier runtime must compose this revalidation immediately with its own admission and spawn boundary. A path retained after an earlier successful check is not sufficient authority.

## Verification

- materialization adversarial suite: **3 passed, 0 failed**;
- complete discovered Swift matrix: **702 tests**;
- complete Swift execution: **702 executed, 8 environment-gated skips, 0 failures**;
- non-DEBUG arm64 Release builds (`LoopForge` and `KernelSandboxGate`): **passed**;
- exact source snapshot: `237710714e09714a459bb602b64bdebfa08f259447e8bd17aed246aba9c19f31`;
- Release `LoopForge` SHA-256: `232133ace65ee2c5634948a997aad2c920f574577421b05e9a9d60d04a0648ed`;
- Release `KernelSandboxGate` SHA-256: `0e29463be4377b4d21c463e7ddb63e6256dd76abf30ff1690f0c5a482e985227`;
- diff whitespace validation: **passed**;
- owned Swift build/test processes after verification: **0**;
- EasyBusiness read-only status: **unchanged**.

All test/build execution, polling, waits, and failed attempts are excluded from the strict active-work ledger.

## Remaining stop-the-line dependencies

This closes the candidate-byte materialization prerequisite, not deterministic verification. Production verification and native start remain vetoed until LoopForge adds:

1. separately activated verifier process authority and independent actor lineage;
2. direct recipe substitution of this exact candidate capability and the already staged executable;
3. revalidation composed atomically with admission/spawn rather than a stale path handoff;
4. an exact receipt chain binding recipe, executable, argv/input artifacts, attestation, environment, capture, parser, output, oracle, runtime, and integration transaction;
5. verification identity and journal sequence with latest-red revocation;
6. a canonical verification-evidence batch; and
7. separately activated read-only independent review of that exact batch.

No package, commit, push, native walkthrough, or final acceptance is claimed.
