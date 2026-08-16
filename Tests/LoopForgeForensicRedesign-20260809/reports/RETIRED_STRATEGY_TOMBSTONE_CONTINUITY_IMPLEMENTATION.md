# Retired-Strategy Tombstone Continuity

Status: **F-04 legacy final-repair source/controller and package receipts present; production reducer cutover pending**

Recorded: `2026-08-11T05:46:36Z`

## Defect confirmed

The final-repair gate compared a proposal only with nodes whose status was
`superseded` **and** whose optional `strategyLesson` was present. Two real
retirement paths did not populate that field: incremental Main Graph
retirement and redundant final-repair cleanup. Older checkpoints can also
contain a durable `supersededAt` timestamp without either the lesson or the
restored terminal status.

Those records were visibly retired but absent from the anti-repeat set. A final
reviewer could therefore give the same causal route a new ID and admit it as a
fresh repair. The prompt's instruction not to repeat retired work had no
deterministic enforcement for these histories.

## Repair

- every node with `status == superseded` is a strategy tombstone regardless of
  optional lesson text;
- `supersededAt` alone is sufficient durable provenance, including the crash
  window before terminal-status restoration;
- tombstones are excluded from the current final-repair frontier as both
  dependency consumers and eligible predecessors;
- every new redundant-repair or incremental-review retirement persists a
  default anti-repeat lesson if no more specific lesson already exists;
- final-repair admission compares each proposal against **all** tombstones;
- legacy novelty remains fail-closed and causal-topology based: new IDs,
  titles, objectives, evidence nouns, and verification prose grant no novelty.

## Adversarial verification

The new legacy-checkpoint fixture leaves a retired read-only node in the
historically inconsistent state `waiting + supersededAt + no strategyLesson`.
A differently named final repair with different prose but the same read-only
topology is rejected. The durable-budget fixture additionally proves that new
redundant repair tombstones persist the inherited anti-repeat lesson through
JSON encode/decode.

## Verification

- focused Graph suite: **94 tests, 0 failures**;
- complete source suite: **596 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **596 tests, 8 environment-gated skips, 0 failures**;
- release build, ad-hoc signature, exact source/test manifest, ZIP, DMG,
  checksums, executable startup, cleanup, and zero residual packaged processes
  verified.

Receipts:

- source snapshot: `39636d3875c67602efdc966447d5f60e6852fda998aff1b4c315d9e965f3a8a4`
- Graph source: `1a9aef8336a2e0a30483df2e8dcc34e82b4c2125ed38f26eee6eae2dee7a3713`
- Graph tests: `d76b07921ba9a7d0cc631447248004555733218e33e622b57dc48560fbb10e28`
- focused log: `a85c341cf103c3668544b3cedddee28794af223ee6b49591efe5674bcb8bdcdd`
- package test log: `65ddd11080f66a8fe5880c89d89784bbad8b86e7ea6b7c829b3ba4006ec2e2cd`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `226ad7dbd8edfe92e049e7bd2604cb5ad9026f49fced7395814958f10bea4b1c`
- executable: `5a10fd4ac666c0814e6bde2252656b42e84d46ca866aef292d821bd1057e5a2e`
- ZIP: `ab8c541ae3ece6c99a613eee32722a823d1372c2e56176553acb975ff523079e`
- DMG: `e3809db5c9311cc15043c587bb7de33019f32470e5873adb1f11ac3ff8e04ecb`
- CDHash: `0b1ad098b332afd3a1b7f26c21d769025b7f7670`

## Boundary

This closes the concrete lessonless and partially persisted legacy tombstone
escape path. Full F-04 acceptance still requires the journal reducer's typed
strategy identity and retirement receipt to own production execution. Current
unlocked native proof, a clean commit, and push also remain pending.

EasyBusiness remained permanently stopped and read-only.
