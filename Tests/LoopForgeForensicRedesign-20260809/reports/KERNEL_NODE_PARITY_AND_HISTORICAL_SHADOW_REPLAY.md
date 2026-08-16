# Kernel Node Parity and Historical Shadow Replay

Status: deterministic node projection and retained stopped-task replay verified; populated kernel mapping and runtime cutover remain blocked.

## Result

The kernel projection now exposes exact, sorted per-node state derived only from reducer authority: requirement identifiers, accepted requirements, dependency identifiers, writable paths, file/byte mutation ceilings, capability identifiers, node status, attempt identifiers, active attempt, causal strategy fingerprint/retirement, receipt counts, latest visual acceptance, and all-requirements acceptance.

The legacy Graph shadow comparator uses that projection to detect missing kernel contracts and exact dependency/mutation-scope mismatches. It also rejects legacy completion without kernel acceptance and legacy work without a kernel attempt. Legacy fields remain read-only claims: the adapter accepts zero historical seconds, creates zero receipts, authorizes no effects, and cannot write back.

## Retained stopped-task replay

The environment-gated replay test decoded the exact retained 8,465,712-byte stopped-task snapshot at `Tests/LoopForgeForensicRedesign-20260809/evidence/task-snapshot-20260809T131753Z.json`, compared it with an empty receipt-authoritative kernel projection, then re-read and byte-compared the input.

- Input SHA-256: `bfc2a0749c1ba15ca17aed226df7d98c854ee6817f096fe192b10a7e1ba0ac29`.
- Input unchanged: true.
- Legacy nodes: 19; completed claims: 12; working claims: 0.
- Imported authority: 0 accepted seconds and 0 accepted receipts.
- Structural issues: 0.
- Critical divergences: 16: fourteen `legacy-active-node-missing-kernel-contract`, one `legacy-node-approval-exceeds-kernel-evidence`, and one `legacy-stop-without-kernel-quiescence`.
- Cutover blocked: true; writeback permitted: false.

This replay deliberately does not fabricate new node contracts from legacy objectives. It proves the old snapshot cannot manufacture kernel authority; it does not prove equivalence or convergence. A future typed contract compiler must create a populated new run before exact parity can pass.

## Chronological forensic context

The retained event corpus contains 5,758 events from `2026-08-02T14:09:30Z` through `2026-08-09T13:14:04Z`: 4,124 commands, 684 system events, 469 agent events, 178 warnings, 129 audits, 97 controls, and 77 errors. Of these, 5,486 are node-scoped and 272 are task-scoped.

- Event corpus SHA-256: `b2a162e426063f635bb1e500efd879a5dac97281c0494951355b208969f9d1af`.
- Graph summary SHA-256: `5a6b46e8fac7ce01ad43f10a352a890f5e133d52b80d5b5fa5f56411af7c27b5`.

The event corpus remains chronological forensic evidence. This slice replayed the exact task checkpoint through the adapter; it did not reinterpret event prose as commands or receipts.

## Verification

- Focused historical replay: 11 tests, 0 failures.
- Complete Swift suite with retained replay enabled: 464 tests, 6 environment-gated skips, 0 failures.
- Full-suite log SHA-256: `40aa35e584e1e71c8458d8646500734d272cd11cc0fa959cce9463a52a41ab3a`.
- Replay log SHA-256: `17ef9b8a07b8483d67ae897300446208eb705abd3f7215afd30ed61f17f1196a`.
- No compiler `warning:` or `error:` lines occurred in either successful log.

## Exact implementation artifacts

- `Sources/LoopForge/Kernel/RunReducer.swift`: 1,408 lines, SHA-256 `617e2fff5e47f0078b2c2feac783f35df02486ecc5695fe932e651fc4c1fb568`.
- `Sources/LoopForge/LegacyGraphKernelShadowAdapter.swift`: 371 lines, SHA-256 `86aa4729c1da2bfadbcff7fb86ef2bbcb3e2b2b5644cd784de83919a4600b9ea`.
- `Tests/LoopForgeTests/LegacyGraphKernelShadowAdapterTests.swift`: 395 lines, SHA-256 `2a7124e30cee32b2ad29f78b524f9e4581c7077e2ff2c659f7840271f3db1742`.
- Replay scorecard: `HISTORICAL_GRAPH_SHADOW_REPLAY_SCORECARD.json`, SHA-256 `d29554038d65ed52d2ef3f30daf08c75e5490089df558c088106d6a159609334`.

## Open boundary

No production runtime consumes this comparison. A later slice now provides an explicit projection-only compatibility manifest and a populated shadow kernel run, but it deliberately does not constitute user-ratified semantic task compilation. Source-span-aware contract ratification, allow-listed native harness connection, transactional mutation/integration/publication, controller migration, receipt-native UI, current package/native verification, commit, and push remain required. EasyBusiness remained read-only.
