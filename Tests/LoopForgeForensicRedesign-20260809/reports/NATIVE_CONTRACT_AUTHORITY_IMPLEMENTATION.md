# Native Contract Authority Implementation

Status: **native authoring, explicit confirmation, and SwiftUI/AppModel invocation implemented; execution cutover pending**

Recorded: `2026-08-11T09:26:27Z`

## Authority chain

- Native authoring records verbatim objective, canonical workspace, relative
  scopes, and optional accepted duration as independent UTF-8 source artifacts.
- Original objective text carries `.user` authority. Model-written text is
  rejected as `.modelProposal` and can become authoritative only after explicit
  selection as `.acceptedUserAmendment`.
- The contract binds workspace identifier and canonical-root digest. Scope `.`
  means the selected root, not a narrative wildcard.
- The native confirmation sheet exposes the exact objective, workspace, scopes,
  acceptance rules, and full candidate digest.
- Confirmation requires that exact displayed digest and user identity.
- Ratification receipts are persistently single-use and workspace substitution
  fails before journal creation.
- Cancellation produces zero journal, registration, legacy task, or worker.

## Invoked native boundary

Auto Graph's public new-task path now invokes this authoring and confirmation
chain. It cannot invoke the legacy create/start helper. Confirmation performs
journal-first enrollment and returns an exact reducer-owned `ready` projection;
it deliberately starts no worker or strategy. The projection appears in a
read-only diagnostics card. Single Loop and Parallel remain legacy and are not
misrepresented as native-kernel execution.

## Verification

The 13-test invocation suite and the complete **619-test** package-owned
package-owned suites passed with 8 environment skips and 0 failures. The signed
exact-source app, ZIP, DMG, checksum manifest, direct Mach-O startup, cleanup,
and zero residual process checks passed.

Receipts: source snapshot
`1303cb7ec1a7f343cf2537825939771a7b0eb70d076f191ace601e0601a99734`;
authoring
`c0169b7e8d5b0cf5b7e169a0eefb0a34f81f088342d1e0df062b8cd1cce58423`;
focused log
`ecae694b70ffa054d72e5116aeafbd22ecd71c942bb7f2cce5887f7e632a9fc8`;
package log
`afbaf096e4dc6f140ed1c81c567c117346e08fb05307d1fe426c4cd62cbd5448`;
executable
`3aa6db2cb2e0b938beec26b911dea2f77716cb3375457d28ea25443971f55dc5`;
CDHash `f2c50cea69e67c4eecde5fb7187c3cc26292d8f2`.

## Boundary

Historical Auto Graph start/resume is retired; native planning, worker, timing,
process, and integration replacement is not yet composed. The one current Computer Use attempt was blocked by macOS
lock; it was not bypassed or polled again and counts zero. Current unlocked
screenshots, complete execution cutover, clean commit, and push remain required.
Final acceptance is false. EasyBusiness remained stopped and read-only.
