# Minimum Authority and Release Provenance Implementation

## Defects retired

The acceptance audit found three live contradictions:

1. new Main and worker roles defaulted to Full Access;
2. model recommendation, desktop-automation classification, Watcher creation,
   and legacy Watcher recovery silently granted Full Access;
3. the release smoke test never launched LoopForge and the package did not bind
   its exact dirty source snapshot to packaging-owned test evidence.

These were systemic authority and evidence defects, not copy defects.

## Authority changes

New task roles now default to Workspace Only. Recommended models change model
and reasoning choices but never authority. Category inference may route a model
but cannot grant capabilities. An explicit user Full Access selection remains
stable across estimation. Continuum Watcher and its legacy recovery fallback now
use Workspace Only, and the UI badge/help text accurately describe that scope.
The access picker lists the safer choice first.

The regression contract includes a test proving defaults remain Workspace Only
and a separate test proving recommendation/category inference cannot escalate a
minimal choice or erase an explicit Full Access choice.

## Release provenance changes

Packaging now owns the full 517-test run. It computes a deterministic SHA-256
over release-relevant sources, tests, scripts, resources, and untracked kernel
files; embeds revision, dirty flag, source digest, test-log digest, build time,
and version into the signed bundle; preserves the test log; and atomically
hashes the ZIP, DMG, and test log.

The smoke verifier checks source and test-log binding, every checksum, bundled
tools, signature, plist, absence of model weights, and launches the exact signed
Mach-O. A bounded liveness probe catches startup aborts, and an exit trap prevents
orphaned verification processes. A deliberately crashing fixture proves the
probe fails closed, and a live fixture proves successful cleanup reaps the PID.

## Verification

- focused authority tests: 19 passed, 0 failed;
- package-owned full suite: 517 executed, 8 skipped, 0 failed;
- executable-probe negative and cleanup fixture: passed;
- deep strict signature: passed;
- revision/source/test manifest: passed;
- ZIP, DMG, and test-log checksum verification: passed;
- exact packaged executable startup: passed;
- packaged LoopForge processes after smoke: 0.

## Remaining boundary

The source snapshot is exact but dirty, so it is not yet a clean commit. The
screen remains locked, so current-package screenshot/accessibility proof is not
claimed. Nothing in EasyBusiness was changed or resumed.
