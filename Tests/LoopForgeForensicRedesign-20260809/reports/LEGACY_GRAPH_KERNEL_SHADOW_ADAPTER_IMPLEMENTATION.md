# Legacy Graph to Kernel Shadow Adapter

Status: read-only shadow adapter, per-node parity, and retained stopped-task replay verified; populated kernel mapping and execution-path cutover remain open.

## Result

LoopForge now has an explicit boundary between the mutable legacy Graph checkpoint and the receipt-authoritative kernel. The adapter does not upgrade `LoopTask`, `GraphLoopState`, `GraphLoopNode`, status, prose review, elapsed time, visual flags, or integration fields into kernel truth. It snapshots them as digest-bound claims and compares only presentation projections.

The source audit found that legacy Graph still writes phase, node status, integration state, audit state, completion state, and report state directly into `TaskStore`. Shadow mode therefore cannot safely emit `RunCommand`, schedule work, integrate a candidate, publish, resume, write the legacy store, or create a receipt. The new API intentionally has no such methods.

## Conservative import

Each snapshot retains:

- a deterministic digest of the complete legacy task checkpoint;
- the historical task and node identifiers;
- objective, dependency, scope, verification, status, review, visual-pass, phase, iteration, and duration claims;
- per-node checkpoint digests;
- structural issues for duplicate identifiers, unknown dependencies, cycles, and empty objectives.

Every imported duration has `acceptedActiveSeconds = 0`. Every task and node has an empty accepted-receipt set. `mayAutoResume`, `mayWriteLegacyState`, `mayAuthorizeEffects`, `maySchedule`, and `mayIntegrate` are always false.

## Projection-only divergence rules

Comparison against `KernelRunProjection` emits stable typed divergences. The projection now includes deterministic per-node requirement, dependency, mutation-scope, capability, attempt, strategy, receipt, visual, and acceptance state. Cutover is blocked when legacy claims:

- completion without kernel completion authority;
- completion or stop without kernel quiescence;
- more completed nodes than kernel-accepted mandatory requirements;
- active nodes with no matching kernel node contract;
- dependency or mutation-scope contracts that differ from the kernel;
- node completion without kernel requirement acceptance;
- running nodes without an active kernel attempt;
- visual approval without a green kernel visual gate;
- structurally invalid graph topology.

When the kernel is ahead of the legacy view, the divergence is informational and still cannot write back. A canonical comparison digest binds the legacy checkpoint, kernel run/sequence, and ordered divergence set.

## Adversarial verification

Eleven focused tests prove claims-only import, zero accepted duration, zero receipts, disabled effects, digest sensitivity, duplicate/unknown/cyclic topology rejection, completion/quiescence veto, exact node/dependency/mutation parity, work-without-attempt veto, visual-pass veto, stop/quiescence veto, informational kernel-ahead behavior, rejection of tasks without a graph, and byte-preserving replay of the retained stopped-task snapshot.

The retained 8,465,712-byte snapshot contains 19 node claims, including 12 completed claims. Replay imports zero accepted seconds and zero receipts, produces 16 critical divergences, blocks cutover, forbids writeback, and leaves the input SHA-256 unchanged. The warning-free complete Swift suite executes 464 tests, skips 6 environment-gated tests, and reports 0 failures.

The first focused invocation contained one fixture error: it attempted to use the ignored second copy of an already-invalid duplicate identifier as independent cycle evidence. That invocation is excluded from the strict ledger. The repaired fixture uses a separate two-node cycle, and both focused and complete suites pass.

## Exact artifacts

- `Sources/LoopForge/Kernel/RunReducer.swift`: 1,408 lines, SHA-256 `617e2fff5e47f0078b2c2feac783f35df02486ecc5695fe932e651fc4c1fb568`.
- `Sources/LoopForge/LegacyGraphKernelShadowAdapter.swift`: 371 lines, SHA-256 `86aa4729c1da2bfadbcff7fb86ef2bbcb3e2b2b5644cd784de83919a4600b9ea`.
- `Tests/LoopForgeTests/LegacyGraphKernelShadowAdapterTests.swift`: 395 lines, SHA-256 `2a7124e30cee32b2ad29f78b524f9e4581c7077e2ff2c659f7840271f3db1742`.
- Replay scorecard: `HISTORICAL_GRAPH_SHADOW_REPLAY_SCORECARD.json`, SHA-256 `d29554038d65ed52d2ef3f30daf08c75e5490089df558c088106d6a159609334`.
- Warning-free replay log: `/tmp/loopforge-historical-graph-shadow-replay.log`.
- Warning-free complete-suite log: `/tmp/loopforge-full-tests-node-parity-replay.log`.

## Open boundary

The adapter is not yet connected to `TaskStore` or `GraphLoopEngine`, and no comparison result may influence execution. Per-node/per-requirement projection and retained snapshot replay are complete, but replay intentionally used an empty kernel projection because no typed legacy-to-new contract compiler or populated new run exists. Before cutover, LoopForge must create that mapping, execute it in effect-free shadow mode, retain deterministic parity scorecards, and prove no target effects or legacy writes. Transactional mutation/integration, concrete native harness connection, controller migration, receipt-native UI, latest package/sign/hash, native verification, commit, and push remain mandatory.

EasyBusiness remained read-only.
