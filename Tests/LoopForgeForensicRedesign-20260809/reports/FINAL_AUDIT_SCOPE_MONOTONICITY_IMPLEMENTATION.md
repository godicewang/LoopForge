# Final-audit Scope Monotonicity

Status: **F-08 source/controller and package receipts present; typed user-authority cutover and current native proof pending**

## Defect confirmed

The whole-graph audit path treated a missing or invalid reviewer repair plan as
permission to create `conservativeFinalRepairProposal`. That function always
returned a writable node with `writeScopes:["."]`. The fallback therefore
expanded an ambiguous review into whole-workspace mutation authority. If a
reviewer supplied stale or future dependency IDs, the controller deliberately
discarded those IDs and launched this global repair instead.

The existing characterization test asserted `.` as the expected safe result.
This encoded a non-convergent privilege escalation as a regression contract:
every failed final audit could manufacture a new all-repository writer and
feed its mutations into the next audit.

## Repair

Final-audit repair scope is now monotonic:

- a read-only successor must retain an empty write-scope set;
- a writable successor must declare at least one exact repository-relative
  scope;
- narrative, absolute, escaping, control-character, and missing scopes fail
  closed;
- every proposed scope must be equal to or contained by a write scope already
  materialized in the graph;
- a broader parent, including `.`, is rejected unless that exact breadth was
  already materialized;
- the dependency-recovery fallback is optional and can only retain the exact
  already-authorized scopes from a reviewer proposal;
- no proposal means no synthesized writer;
- when no bounded repair survives, the graph blocks with an explicit warning
  instead of widening authority or continuing repair churn.

`finalRepairBatchNodes` applies the same monotonic check to direct reviewer
proposals, so bypassing the fallback cannot expand scope.

## Adversarial verification

- missing proposals cannot synthesize a repair;
- empty writer scope, `.`, a broader parent, `..`, and prose scope all reject;
- a strict descendant of an existing writer scope is accepted;
- a read-only successor with no write scopes remains valid;
- invalid dependency references can be removed only while retaining a bounded
  inherited scope;
- terminal-branch rebasing and legacy truncated dependency IDs still work
  when their repair scopes are authorized;
- the complete source and packaging-owned suites preserve Graph scheduling,
  integration, strategy retirement, recovery, and kernel behavior.

## Verification

- focused Graph suite: **90 tests, 0 failures**;
- complete source suite: **592 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **592 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `a1b3ca660c14f617e4e8791b4197aaa28daefa0304cace0674be020e47b12ef6`
- focused log: `80e98d1938257ded5f33ccbf4b889e1e7405aa8c97ecdbc8df3f91a0b5da48fd`
- full source log: `0e781532eeca2ee271c8636e545c5c30ded454c287eecdf9805d1f656a25a951`
- package test log: `ba5901cc0f6e2ac356f901580921d136185c1b854e63fd3de0ad640d56a06a05`
- package command log: `a84591f6ab29a692f137f74cf904701ba58fdab2ee177944f2497cba2f9e94c5`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- build manifest: `0e42dff668dd11bada5cd2a63a34df5f54338dda3a938ef5b6928659341095c0`
- executable: `ab3b87b984cf5e8cde790f0b2e85009eacef4a11d52b3c92a1bc21a110a6b806`
- ZIP: `b413b946f01e4ddd7de1f4f5d040c45f7db4665d6deb59189770a8a7d14687e6`
- DMG: `b887874756a090c1eac98112b86aaeebce7e6ee4306cc38029b58b8ed72cce21`
- CDHash: `e048dd0dda76c585e2c29bd628124e0278684bcb`

## Boundary

This advances source-level F-08 and removes the legacy controller's explicit
whole-workspace fallback. Existing graph scopes remain legacy plan data rather
than receipts derived from the ratified task contract, so production-kernel
enrollment, typed user-authority binding, current unlocked native proof, a
clean commit, and push remain mandatory. EasyBusiness remained permanently
stopped and read-only.
