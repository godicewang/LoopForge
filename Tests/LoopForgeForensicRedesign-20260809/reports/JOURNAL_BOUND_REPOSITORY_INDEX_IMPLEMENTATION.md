# Journal-Bound Repository Index Implementation

Status: **implemented and source/package verified; legacy snapshot cutover and current native telemetry remain pending**

## Forensic finding

The first G-08 cache slice retired repeated image decode/OCR and repeated report
media copies, but repository evidence still had no honest reuse boundary. One
`WorkspaceEvidenceCollector.collect` call recursively enumerated the same tree
three times: once for its after-fingerprint, once for recently modified source
selection, and once for screenshot discovery. Enumeration errors were swallowed.
The separate synchronous legacy `WorkspaceAuditor.snapshot` path also still
enumerates independently.

A path, directory mtime, task label, Agent statement, or Git HEAD cannot prove
the generation of a dirty tree. Reusing an index under any of those identities
would make stale evidence look authoritative.

## Production implementation

`WorkspaceRepositoryIndexer` now produces one sorted, deterministic metadata
projection per observation. The projection carries canonical-root binding,
relative paths, size and modification metadata, and a SHA-256 observation
digest. Generated dependency/build directories and symbolic links are excluded;
filesystem enumeration errors and path escape fail closed.

Cross-observation caching requires `WorkspaceTreeGenerationReceipt`. That typed
receipt binds:

- stable workspace identity;
- canonical workspace-root digest;
- immutable source-tree generation digest;
- journaled mutation-commit or recovery-reconciliation authority;
- exact journal command, event IDs, sequence interval, and frame digest.

The cache key contains workspace identity, tree generation, journal frame, and
the exact index recipe. Root mismatch, malformed SHA-256 fields, missing journal
events, duplicate event IDs, or inconsistent sequence arithmetic reject before
lookup. Mtime remains derived observation metadata and never cache authority.

When a legacy caller has no accepted generation receipt, the indexer performs
one uncached scan and emits `uncachedObservation; no authoritative
tree-generation receipt`. It cannot report memory, disk, or coalesced hits.
`WorkspaceEvidenceCollector` now uses that single projection for the after
fingerprint, recent-source priority, and screenshot candidates. Its before
fingerprint remains a deliberately separate pre-mutation observation.

## Adversarial verification

Five new tests prove that an unchanged journal-bound generation computes once
then hits memory, a changed generation recomputes, receipt reuse against a
different canonical root fails, incomplete journal provenance cannot mint
authority, receipt-free calls never enter the cache and observe changes, and
generated trees/symbolic links are excluded. All 17 existing auditor/evidence
tests also passed, including screenshot diversity, deletion evidence, and
digest-addressed OCR reuse.

The complete source suite and packaging-owned suite each passed **546 tests,
8 environment-gated skips, and 0 failures**. The exact dirty-source snapshot was
rebuilt into an ad-hoc signed arm64 app, ZIP, and DMG. Manifest binding,
checksums, direct packaged-Mach-O startup, cleanup, and zero residual packaged
processes passed.

Package receipts:

- source snapshot: `3b22d84b331d8966812bfc2d6e28646915f7dd04675c21e9deefcd98e0ac376f`
- executable: `afffd372ff9e9456c77b9d399090776b546c788c3ccae8400fb4d06552ef10e3`
- ZIP: `d204ca1fa1d77e90c819e2485ff3e6d5c39451ada187574f1785054f5aabfd94`
- DMG: `2c7ce251e0296fcfafc9760ddb6b1d8dfd3af5f42bf943a8e1e6db2aded3beb0`
- package test log: `f388166e5e11ef2583f7dd274bdb7e96d5d4968afb09909807e82a827c3017ca`
- source full-test log: `bc6775e9d0e47532beef4eaa81a3426f8a1efd8bfd5a58ba2f80c62b6d9315f4`
- focused index tests: `2462dc7f99bca4f382ceb758406ded5347718112f9ca1bf99fc6b1684d2f772f`
- auditor tests: `b00013003754d7717c4df5cd692c5f978e9bf4e87c7c38b3cb0ac14cae0b0190`
- CDHash: `3be754b3bfed7265c8de4da2b54310e70c218d5a`

An initial selector compiled successfully but matched zero tests. It is not used
as verification evidence and its interval is excluded from the strict ledger.

## Boundary

This retires repeated same-observation repository enumeration inside the live
evidence collector and establishes an authority-correct cache API for new-kernel
callers. It does not manufacture receipts for legacy Loop/Graph paths. The
separate synchronous `WorkspaceAuditor.snapshot` scans must be split into a
tree projection plus cheap log projection during production kernel cutover, and
new-kernel mutation/recovery call sites must pass their accepted generation
receipts. Current native cache telemetry, clean commit, and push remain pending.

EasyBusiness remained permanently stopped and read-only.
