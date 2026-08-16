# Shared Repository Observation Cutover

Status: **implemented and source/package verified; accepted-generation population and current native telemetry remain pending**

## Finding

The journal-bound repository index made one evidence collection internally
consistent, but the synchronous audit path still maintained a second recursive
filesystem implementation. At common Loop and Graph review boundaries the
caller could independently request a snapshot, an audit, and evidence. That
meant as many as three observations of a changing tree, with no guarantee that
the prompt, gate, and evidence described the same bytes.

This was not only a performance defect. A file created between those scans
could be visible to one decision input but absent from another, weakening the
meaning of an audit receipt.

## Production change

`WorkspaceAuditor` no longer owns a recursive enumerator. It now creates a
`WorkspaceAuditObservation` from `WorkspaceRepositoryIndexer`, then projects
tree facts and log facts separately. The observation carries the deterministic
repository index, the projected audit snapshot, and any scan error.

The following live boundaries now pass the same observation to snapshot,
audit, prompt compilation, and evidence collection where applicable:

- initial and resumed Loop audit;
- post-turn Loop audit, evidence, prompt, status report, and final narrative;
- Graph candidate comparison and node review;
- incremental join review and batch transition;
- Graph final audit and final reporting;
- completed-Graph report refresh.

Deliberately different time boundaries remain separate. Examples include the
pre-worker fingerprint, an independent baseline capture, and an incident scan
after a quiescence failure. Those are distinct observations by contract.

`sharedObservation` is explicitly not a cache hit and grants no
cross-observation authority. Cross-observation reuse still requires the
canonical-root-bound tree-generation and journal-frame receipt introduced by
the repository-index slice. If the shared scan fails, the same error and empty
tree projection flow into evidence collection; it does not retry the directory
walk and cannot turn a partial observation into success.

## Adversarial verification

A new regression observes one file, creates a second file after the observation,
and then runs both audit and evidence from the shared observation. Both retain
the original byte boundary. A fresh observation sees the second file. This
proves same-boundary consistency and proves that evidence collection does not
hide a second scan.

Successful verification:

- 18 auditor/evidence tests;
- 84 Graph tests;
- 5 Loop lifecycle tests;
- complete source suite: **547 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **547 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, manifest/checksum validation, direct executable startup,
  cleanup, and zero residual packaged processes.

Package receipts:

- source snapshot: `dcc244946dcdf3786be9a8e59815eb515148b8fd6ae861ba8c3175bcb9bc1b26`
- executable: `285a919dd61cf91e69290c7c227e3afaad092145136276228a57f71439eeeabb`
- ZIP: `19ef2fa63e33f4494df7b0841b527b43f686c9eb168f3d21cf1fed6d00950c77`
- DMG: `ba16838d605da32b2a2afbfc0b20a803e49286e1cb4623f9e6f226413d0099f0`
- package test log: `fd7168c70925d56b6fc417c40c33f99a5ea33fdcc5d1117a3645dbe0ce81ceca`
- source full-test log: `93631f19f77a597d568dec4ec99a08a5b94ee31de3eebc903ba13cc1b95704ff`
- focused auditor log: `8ba7657cf078a807e5c33530e3d74fa42e48668a0f4b546cd1e245e1e1f1fb8c`
- focused Graph log: `08d59f6b28014d8f05ff4b52f8f49d5b2a22ad5efbf24143c6cedf608f0995bb`
- focused Loop log: `c9f02acbd1d4b00be451896c7e4cf0beabf388ca083bf42d361d085ab6e45f97`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- CDHash: `5366742e7b840cfec53992f896fd1c60e75a899a`

One full-suite compile failed after the new error-propagation branch used
invalid Swift `else do` syntax. It was corrected, rerun successfully, and both
the failed run and its time are excluded from verification and the strict
ledger.

## Boundary

This retires the synchronous duplicate tree scanner and makes the updated
legacy orchestration internally consistent per observation. It does not mint
new-kernel generation receipts, prove cache behavior through the currently
locked native UI, complete production kernel cutover, create a clean commit, or
push a revision. EasyBusiness remained permanently stopped and read-only.
