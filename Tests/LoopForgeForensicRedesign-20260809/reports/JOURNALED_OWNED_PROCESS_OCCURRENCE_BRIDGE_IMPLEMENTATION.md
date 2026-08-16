# Journaled Owned-Process Occurrence Bridge

Status: **F-02 exact owned-process/execution bridge implemented and package-verified; production enrollment pending**

Recorded: `2026-08-11T07:44:24Z`

## Defect closed

The clock issuer prevented a controller from inventing interval bounds, but its
start capability was not yet tied to a real owned execution. A controller could
open the clock without proving a new productive process lease, exact PID/process
group binding, native exit, and durable release. Release-journal latency could
also extend the sampled interval beyond the process's actual exit.

## Enforcement

- `JournaledOwnedProcessOccurrenceBridge` accepts only a non-duplicate,
  productive, owned `processTree` admission with an occurrence identity;
- admission and binding wrappers must each name the exact single-event,
  hash-journal transaction that published their typed receipt;
- run, resource, lease, PID, process-group leader, and external process-start
  identity must agree across admission, binding, native handle, and current
  journal ownership, while `RuntimeSupervisor` must project the same bound
  lease;
- bridge tokens are non-Codable, nonce-backed, single-use capabilities;
- close requires the same native handle in both termination and exit receipts,
  a non-duplicate exact lease release, the exact single-event release journal
  transaction, and absence of the released live lease from both journal and
  supervisor;
- the adapter-observed native termination is embedded in the hash-journaled
  release event; a real release can no longer be paired with a fabricated exit;
- execution disposition is derived from native exit code/signal. A caller
  cannot label a failed, signalled, or unverified process as successful;
- the occurrence end is clamped to the native exit monotonic timestamp. Wall
  time is back-projected from the journaled release clock, so journal and
  supervisor release latency cannot become accepted execution;
- a mismatched or cross-wired receipt leaves the capability open for an exact
  retry and contributes no closed duration.

`RunJournal` now exposes typed transaction-to-event resolution for admission,
binding, and release. Merely combining two individually real but unrelated
transactions no longer creates a valid evidence chain.

## Adversarial verification

The end-to-end process test launches a real owned `/bin/sleep` process group,
opens the occurrence from its journaled start, and verifies that:

1. a binding transaction substituted for the admission transaction is rejected;
2. a forged lease ID in the native termination handle is rejected by both the
   bridge and reducer-level release provenance validation;
3. a binding transaction substituted for the release transaction is rejected;
4. every rejection retains exactly one open execution capability;
5. the exact release closes once, derives `succeeded`, and records an end equal
   to the native exit timestamp;
6. the lease and bridge capability are both absent after success.

## Verification receipts

- focused bridge test: **1 test, 0 failures**;
- complete source suite: **604 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **604 tests, 8 environment-gated skips, 0 failures**;
- exact-source arm64 release build, deep strict ad-hoc signature, ZIP, DMG,
  checksum manifest, packaged executable startup, cleanup, and zero residual
  packaged processes passed.

Hashes:

- source snapshot: `813ae2b5306ae6b8b36e02bd55bf1b3ac5e61b4c5b2add626bc69a8ff3b5c879`
- bridge source: `ab9aae3b9b9475ae863448086e75b0e9fd245319eb52e0939cc58667ff1d75ec`
- recorder source: `6213e0080de14c82837d2dcb73b66d8aded65b50b393ec94147eb18244d9b58f`
- bridge test source: `e7e2e070ca6a95206cea4dd201ed131154bc9eedc7ab234b066b9cb57c8cbfd0`
- native-release reducer test source: `11201b8d88556ed063c4f6f0572c49ab00d531ab59e3af1d93d53436481f0947`
- complete test log: `083168c4ec49bcc1d3b59dc727672d18cf012623fd9c564df07fd75889ccc436`
- package test log: `24e2023dbb499a1ad686710845c6fad35bc4306d64a65da77d3e0c2ea4e8ce64`
- executable: `cdca3ee2c2aa463816439b71db877f1cb90bab28b6699289441ed2c55f57c0d6`
- ZIP: `82a952c8bca8c3d05cd73a6e81e7d04f322bd26ac58b4dbc47fec2fcef46e8b6`
- DMG: `04a871a9b2a55f0c1f0a7c696858378b7d059bec973e6afbb1d8bf1bad981862`
- CDHash: `93a995ca86fabf553966180c0e1e205cf3f35296`

## Boundary

This closes the exact owned-process/execution integration gap for the new
kernel issuer. Trusted production task enrollment, legacy timing/controller
removal, an unlocked current-package native walkthrough, clean commit, and push
remain mandatory. Final acceptance is still false.

EasyBusiness remained permanently stopped and read-only.
