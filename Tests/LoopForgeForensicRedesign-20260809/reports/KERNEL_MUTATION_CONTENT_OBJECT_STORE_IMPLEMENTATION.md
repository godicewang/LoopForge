# Kernel mutation content-object store implementation

Recorded at: `2026-08-12T06:28:00Z`

## Outcome

LoopForge can now retain the exact verified mutation delta byte set in an owner-private, content-addressed store outside the workspace. `WorkspaceMutationContentObjectStore` binds the upstream verification receipt, derivation and object-set digests, exact artifact manifest, absolute artifact path, byte and object totals, installed directory device/inode identity, materialization mechanism, reuse status, and a canonical receipt digest.

Each SHA-256-named regular file is created with descriptor-relative exclusive no-follow I/O, streamed from the already rehashed object set, sealed `0400`, and synced. Its temporary parent is sealed `0500`, then installed with exclusive `renameatx_np` and the store directory is synced. Exact existing artifacts may be reused only after a fresh directory enumeration, file type/owner/mode/size verification, byte rehash, second enumeration, and stable directory/file identity and modification-time checks.

## Authority boundary

The result is durable inert evidence, not origin, journal, manifest, preflight, or effect authority. It proves that bytes matching the exact upstream verified set were durably installed and remain byte-exact when revalidated. It does not prove how the caller obtained those bytes, that a trusted workspace observation produced them, or that a journal accepted the capture. The store receipt contains no journal receipt IDs and exposes no capability that can construct a mutation manifest, issue preflight authority, apply a filesystem mutation, publish, or complete a run.

The optimized Release executable remains byte-identical because this component is deliberately disconnected from production issuance and native start.

## Fail-closed controls

- storage must resolve outside the workspace and be owner-only, owner-readable/writable/searchable, and opened by an absolute descriptor-relative no-follow walk;
- store, lock, temporary artifact, installed artifact, and content objects are validated by held descriptors rather than trusted pathname traversal;
- the lock is a single-link owner-owned `0600` regular file and acquisition is nonblocking;
- symlinked store or artifact entries, non-directories, wrong owners, permissive roots, writable installed artifacts, non-regular objects, wrong names, missing objects, extra objects, and duplicates reject;
- input count, exact digest set, sizes, total bytes, and every object rehash must still match the upstream verifier receipt;
- first installation writes through a private temporary directory, syncs content and metadata, and uses exclusive atomic rename so an existing artifact is never replaced;
- failed-install cleanup uses only the already-held temporary and store descriptors;
- existing-artifact validation enumerates twice and rechecks file and directory identity, mode, size, modification time, and digest;
- canonical receipts include the artifact device/inode and independently recompute their own digest.

## Proof

- 4 focused tests pass with multiple adversarial assertions covering unordered first materialization, exact reuse, read-only bytes, tampered same-size bytes, unexpected artifact entries, changed input bytes, workspace overlap, unsafe storage permissions, symlinked store directories, and symlinked artifact identities.
- Exact current-source split coverage passes: **737 tests, 8 intentional environment skips, 0 failures**, plus the independently run process-group resistance case, for **738 covered tests and 0 failures**.
- Non-DEBUG `LoopForge` and `KernelSandboxGate` builds pass.
- Release `LoopForge` SHA-256: `8472a2ea03722764ed904c39dc5941ad70d4167f51c1f17e519eb82d06faa567`.
- Release `KernelSandboxGate` SHA-256: `1b7ba433fe915b0dd916aceafe62342d246bcf6bbddcfc5425b0d09fba0fbeaa`.
- Exact source/test snapshot SHA-256: `ca01bfdcc5c2c65e1d905775616add50a8013c54c0c2caf027e4be8cb74d4317`.
- Store source SHA-256: `8151f634e7d85d29fbab1d01ca36b75cc598c598509c5fbe165faf649f6c4f1f`.
- Store tests SHA-256: `ff5a1325bbbd96a7a25d42787e4ca97a576f12a9f4d6660b4da5be2d83aee7bb`.
- Diff whitespace and process cleanup pass. The read-only EasyBusiness fingerprint is unchanged.

## Boundary retained

The next required boundary is journal-attributed content capture and replay: the trusted observer must own byte origin, write this store through a journal-first runtime, and bind acceptance/recovery to the exact storage receipt. HEAD, index, and untracked preimage planes; repository-metadata and ignored-path policy authority; canonical `WorkspacePreimage` assembly; manifest assembly; proposal/preflight issuance; resident-memory authority; publication; native baseline/visual authority; final authorization; native start/UI; package/sign; clean commit; and push remain blocked.

One stale product-name Release command and one failed no-follow path-walk diagnostic are explicitly excluded from the ledger. Final acceptance remains false.
