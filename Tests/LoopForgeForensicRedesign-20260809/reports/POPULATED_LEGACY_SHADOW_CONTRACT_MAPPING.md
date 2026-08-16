# Populated Legacy Shadow Contract Mapping

Status: explicit projection-only compatibility manifest and populated historical shadow run verified; user-ratified task compilation and runtime cutover remain blocked.

## Result

LoopForge now has a fail-closed boundary between a retained legacy Graph snapshot and a populated reducer-authoritative shadow plan. Production code does not infer a contract from legacy prose. A caller must provide an explicit `LegacyGraphShadowContractManifest` bound to the exact snapshot digest, verbatim objective, objective digest, every active node digest, every retired node digest, exact topology, exact mutation scopes, finite mutation budgets, requirement ownership, evidence recipe identities, capability ceiling, provenance claim, and projection-only purpose.

The mapper validates the manifest, then submits only `createRun` and `proposePlan` to the pure reducer. It exposes no execution, mutation, integration, publication, or legacy-write method. The result records each of those permissions as false. Nodes remain `proposed`; there are no attempts, receipts, leases, accepted requirements, or accepted historical seconds.

The reducer also now rejects any plan whose declared capabilities exceed the task authority ceiling. Previously only writable paths were bounded, leaving a generic capability-escalation gap even in an otherwise scoped plan.

## Historical populated replay

The exact retained 8,465,712-byte stopped-task snapshot was re-read without mutation and projected through an explicit compatibility manifest:

- Input SHA-256: `bfc2a0749c1ba15ca17aed226df7d98c854ee6817f096fe192b10a7e1ba0ac29`.
- Legacy nodes: 19.
- Active nodes mapped exactly: 14.
- Superseded nodes retired explicitly: 5.
- Populated reducer events: 2 (`runCreated`, `planAccepted`).
- Kernel node state: 14 proposed, 0 authorized, 0 executing, 0 accepted.
- Accepted legacy time: 0 seconds.
- Accepted legacy receipts: 0.
- Critical divergences: 14: twelve legacy completion claims without kernel acceptance, one aggregate approval/evidence mismatch, and one stop without kernel quiescence.
- Missing-node, dependency, and mutation-scope divergence count: 0.
- Cutover blocked: true; writeback permitted: false.
- Canonical manifest digest: `7df5dad278ecde75a95fdd71f740b318531613772c77ea3dcaff4ee324b7e710`.

This proves topology-preserving compatibility projection, not semantic ratification of the old plan. Node objective claims become declared shadow requirements only inside the forensic manifest and do not become accepted user outcomes. A real compiler still must bind source spans, constraints, non-goals, baselines, ambiguities, evidence recipes, risk, and user authority before any mutation can be admitted.

## Reproducibility defect found and fixed

The first successful populated replay and full suite exposed a deeper defect: semantically identical scorecards had different SHA-256 values across independent Swift processes. `JSONEncoder.sortedKeys` sorts object keys but does not canonicalize `Set` enumeration; randomized hash seeds changed array order.

The mapper now recursively canonicalizes encoded JSON and sorts only fields whose Swift types are sets; ordered arrays such as reducer events and manifest declarations retain their semantic order. A new permutation test proves set ordering cannot change the manifest digest and independently proves changing declared node order does change it. Two separate retained-replay processes now generate the identical scorecard SHA-256 `395c9c90a9ea1e3d05cf93dd9c8c22941aaa6708d9008918f84bd6e5f8e76f3f`.

The pre-fix scorecard hashes and the first compile failure are excluded from authoritative evidence and strict active time.

## Adversarial verification

Nine mapper tests cover:

- exact populated projection with zero effects;
- snapshot/objective/objective-digest binding;
- projection-only purpose and nonempty provenance;
- remote publication denial;
- exact active and retired node coverage;
- duplicate mapping rejection;
- node digest, identity, objective, dependency, mutation scope, and budget preservation;
- nonempty evidence recipes and exactly one mandatory owner;
- deterministic reducer events and canonical manifest digest;
- real retained-snapshot replay.

The 12 reducer tests include capability-ceiling escalation rejection. The final complete Swift suite, with both historical replay tests enabled, executes 473 tests, skips 6 environment-gated tests, and reports 0 failures and no compiler warnings.

## Exact artifacts

- `Sources/LoopForge/LegacyGraphShadowContractMapper.swift`: 383 lines, SHA-256 `401186ed747038992845e215970d363b0c06824d6f326515cd2a26251ecd0107`.
- `Sources/LoopForge/Kernel/RunReducer.swift`: 1,413 lines, SHA-256 `a70ad86da7f71e571f9e82a46017c7347936f137f25572ac393a1b9a6909030f`.
- `Tests/LoopForgeTests/LegacyGraphShadowContractMapperTests.swift`: 515 lines, SHA-256 `abccae8fefbc1fa05ecac7b68b15fa4f6082aa56e5d35390c8bade2392b063fd`.
- `Tests/LoopForgeTests/KernelRunReducerTests.swift`: 585 lines, SHA-256 `35940c6ba64c6bd1dfc23ec4338c5bc8dd9e654a83d33acadb6ca3085d121e11`.
- Historical populated scorecard: SHA-256 `395c9c90a9ea1e3d05cf93dd9c8c22941aaa6708d9008918f84bd6e5f8e76f3f` in two independent processes.
- Final complete-suite log: `/tmp/loopforge-full-tests-populated-shadow-field-canonical.log`, SHA-256 `e4110f083c8ed5ee3834379d896ca895a9893c605db5dd4a3661f13d1caa8ae8`.

## Open boundary

The compatibility manifest is not connected to `TaskStore` or `GraphLoopEngine`, does not ratify the historical plan, and cannot schedule anything. A source-span-aware task compiler, user-authority ratification, immutable baseline binding, populated effect-free runtime shadow comparison, transactional mutation/integration/publication, controller migration, receipt-native UI, current package/native verification, commit, and push remain mandatory. EasyBusiness remained read-only.
