# Journaled Occurrence Clock Issuer

Status: **F-02 trusted clock/interval issuer implemented and package-verified; owned-execution integration completed in follow-up**

Recorded: `2026-08-11T07:08:08Z`

## Defect confirmed

Progress and evidence provenance were journal-bound, but controllers could
still construct `OccurrenceReceipt` directly and choose monotonic bounds, wall
times, boot identity, discontinuities, and an accepted disposition. The reducer
could detect malformed values, but it could not prove they came from a real
clocked interval. A structurally valid invented interval could therefore reach
the duration projection if it cited valid progress.

## Repair

- added one `JournaledOccurrenceRecorder` actor as the clock-owning issuer for
  new-kernel intervals;
- `begin` creates a non-Codable, file-private nonce capability and samples the
  boot session, monotonic clock, and wall clock;
- callers cannot supply start/end times, boot identity, discontinuities, or an
  accepted/excluded disposition;
- `close` samples the clock again, derives outcome/invocation disposition,
  detects reboot, monotonic reset, and wall-versus-monotonic sleep gaps, then
  commits the exact occurrence to `RunJournal`;
- a token is single-use, conflicting opens are rejected, and an abandoned or
  crash-lost open token contributes no duration;
- journal rejection retains the open capability for explicit retry instead of
  silently dropping or counting the interval;
- the production boot identity is derived from Darwin `kern.boottime`, with a
  bounded process-uptime fallback.

## Adversarial verification

The recorder test uses deterministic clock samples. A five-second scheduled
interval is accepted without the caller ever providing clock bounds or a
disposition. Reusing its consumed token fails. A second five-second monotonic
interval with a fifteen-second wall gap is tagged `sleep` and excluded. Journal
reopen reproduces the exact five accepted and five excluded seconds.

## Verification

- recorder suite: **1 test, 0 failures**;
- complete source suite: **602 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **602 tests, 8 environment-gated skips, 0 failures**;
- exact-source release, ad-hoc signature, ZIP, DMG, checksum manifest,
  executable startup, cleanup, and zero residual packaged processes passed.

Receipts:

- source snapshot: `239329f16c7bdf63a3f3f0caeb9819e0791950898ec1bae47838caf6a5605856`
- recorder source: `f25a71c7f0f37c1ad3beb236cbced593f7446a8e5e2f3f6f10d1a0c39070d15e`
- recorder tests: `d7ae39ffe801876451f90eb7e1637202c1fd4c4551bf456e0ce50778695f28c7`
- complete test log: `63ee3c307835c03f145cfdf5698561f22d1b06a04cae5f44e8845b5b372e14b2`
- package test log: `e783c0280cd4b4b1d904dd9b2828a7ccbc35742fdb716b4f857c8e0ff2e94b3f`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `386e6d8e2ce8ffd99beaaf957255fe0d6d2bd2e3ea654888687a2276d5bc4b4a`
- executable: `4f19fc26a537b0bfdf469ad0796e31f4d33bbf1ad9fb84452a3eda2ea129de11`
- ZIP: `5d3d0f1d2fb7af228582bbd387ad8e705151f1dd3469baef6cb3083feb77aee4`
- DMG: `60a56250afcc7900f66e5b18c4b9fe0c660eef8a4d7d45f9cf93f03411482e01`
- CDHash: `f87c75d59488a0e4512579e66d4e6b35ae6f9900`

## Boundary

The clock and disposition are now issued by a non-serializable runtime
capability rather than controller fields. The exact owned-process/execution
bridge is now completed and separately verified in
`JOURNALED_OWNED_PROCESS_OCCURRENCE_BRIDGE_IMPLEMENTATION.md`. Production run
enrollment, legacy-controller removal, unlocked native proof, a clean commit,
and push remain pending.

EasyBusiness remained permanently stopped and read-only.
