# Digest-Addressed Heavy Evidence Cache Implementation

Status: **implemented and regression/package verified; final native matrix and clean revision pending**

## Forensic finding

Acceptance row G-08 was still contradicted by the production evidence path.
`WorkspaceEvidenceCollector` rediscovered screenshots and then decoded every
selected image, sampled luminance, and ran Vision OCR on every review. The
completion report deleted and recopied the same retained screenshots every time
it regenerated. More broadly, LoopForge had typed artifact digests in several
new-kernel receipts but no reusable, bounded cache contract for repository
indexes, source projections, image inspection, visual-pair measurement, or
report projections.

This was a systemic identity problem, not an image-library problem: path,
filename, task label, mtime, or Agent prose cannot establish that heavy evidence
work is reusable. Cache identity has to be the immutable input bytes plus the
exact deterministic collector and parameters.

## Production retirement

`HeavyEvidenceCache` now provides one generic content-addressed boundary for
heavy deterministic projections:

- a key contains the operation, non-empty collector ID, positive collector
  version, uniquely named SHA-256 inputs, and a SHA-256 parameter digest;
- named inputs are canonically sorted, so enumeration order cannot create a
  second entry, while content, collector-version, role, operation, or parameter
  changes invalidate exactly the affected entry;
- concurrent identical misses share one computation;
- memory and persistent hits return typed receipts containing key digest,
  payload digest, size, and hit disposition;
- persistent entries are immutable private files, re-decoded and rehashed on
  disk load, and corruption fails closed instead of silently recomputing an
  authoritative projection;
- empty and oversized projections are rejected, memory and disk retention have
  explicit entry/byte ceilings, and deterministic oldest-first eviction occurs
  only on a miss rather than rewriting metadata on every hit;
- repository index, source projection, image inspection, visual-pair
  measurement, and report projection share the same domain-neutral contract.

The live screenshot collector is wired to this cache. It hashes each image,
then caches the decoded dimensions, luminance sample, and OCR result under the
image digest and exact inspection recipe. A second review of unchanged bytes
does not decode or OCR again; a same-name content change misses. The evidence
summary records the cache disposition and key prefix rather than hiding reuse.

Completion-report media is now stored under the full image SHA-256. Duplicate
bytes are retained once, an existing object is rehashed before reuse, a
conflicting object is rejected, and repeated HTML generation leaves the
verified media file untouched instead of delete-and-copy amplification.

## Adversarial verification

Nine new cache tests prove canonical identity, invalid-key rejection, one
computation across repeated and concurrent requests, cross-instance persistent
hits, precise content/version invalidation, tamper rejection without fallback
computation, bounded eviction, and payload-size enforcement. An integrated
collector test proves one decode/OCR computation followed by a digest hit. The
report test sets a sentinel media timestamp and proves a second generation does
not overwrite the content-addressed object.

The complete source suite passed **539 tests, 8 environment-gated skips, and 0
failures**. Packaging independently reran the same 539-test suite, built and
ad-hoc signed the exact-source arm64 app, ZIP, and DMG, and passed source/test
manifest binding, checksums, bundled-tool checks, exact Mach-O startup, and
zero-process cleanup.

Package receipts:

- source snapshot: `90613a8500756fad2ea3585a87f12cfc0405ecc725b133591d0f0713f37b3ac5`
- executable: `588ac449fd6c62ab914bd3c417ca5145fbc7357cb7b3d333a3927d0eff3c43a2`
- ZIP: `10a5313b3e667f94e6f23de40e57a6d35348c372a3195e96927f72d996e3de80`
- DMG: `096a7adb6d5d2a945db142490bb0bdf70b78baed48bbc3ac6aa841533352119e`
- package test log: `60f11d05d9032382bcb3edfc73aa93699852fd9ae14c9f1cce2d71cdbc4d42e5`
- source full-test log: `ea64c23c48b967e8113b817744cb9f641872b3072ce2b9f392ab6db1dc38caf8`
- CDHash: `29edae9054b2424d8db56b82cf0dd03208b84508`

Two initial focused compilations exposed asynchronous XCTest autoclosure use
and an ambiguous collection overload. Both were corrected; those failed runs
and their time are excluded from the strict ledger.

## Boundary

This advances G-08 at source/package level and retires repeated image
decode/OCR and repeated report-media copying for unchanged content. The cache
also establishes the production contract for repository and visual-pair
projections, but legacy call sites that do not yet possess an authoritative
tree-generation digest cannot manufacture one from filenames or mtimes; their
final receipt-native cutover remains part of the broader kernel migration.

This is not final acceptance. J-04, current unlocked native screenshots,
legacy kernel cutover, a clean commit, and push remain pending. EasyBusiness
remained permanently stopped and read-only.
