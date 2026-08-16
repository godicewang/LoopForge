# Protected Workspace Baseline Enforcement

Status: **contract, plan, and transaction enforcement package verified; native baseline authoring and production issuer cutover remain closed**

## Root cause closed

The visual gate already froze native captures, source/build digests, design-token
snapshots, semantic surfaces, protected invariants, known debt, and product-design
authority. That protected final evaluation, but the mutation preflight had no
typed knowledge of workspace-resident baseline manifests or artifacts. If a
protected path appeared in an otherwise valid write authority set, a worker
could modify it and only fail much later—after the reference itself was no
longer trustworthy.

The immutable task contract can now declare exact or subtree-protected
workspace entries under a preservation-required baseline. Each entry binds a
canonical repository-relative path and content digest to one baseline ID.
Malformed paths, empty digests, empty declarations, non-preserving ownership,
and duplicate path ownership fail contract validation.

## Shared path semantics

Planning and transaction preflight now use one pure `WorkspacePathPolicy` for
canonical Unicode, traversal, absolute-path, empty-component, and glob
rejection plus ancestor/descendant overlap. This removes the previous risk that
the planner and executor interpret the same scope differently.

The plan reducer rejects a node before `planAccepted` when any requested write
scope contains or intersects a protected entry. The typed rejection includes
the node, baseline, protected path, and requested write scope.

## Transaction fail-closed behavior

The mutation kernel independently enforces exact contract-projected bindings:

- an exact protected entry must still match its frozen content digest;
- pre-existing drift fails as `baselineMismatch` before mutation eligibility;
- any create, modify, delete, rename, chmod, symlink, or submodule operation on
  an exact protected entry is denied even with otherwise valid write authority;
- a protected subtree denies every descendant path; and
- malformed or duplicate runtime bindings fail closed before operation review.

The new context field is optional solely for decoding earlier contexts that
declared no workspace-resident protected baseline. It cannot make an existing
binding writable. Production enrollment must project the exact current
contract bindings; that issuer remains closed until the native contract path is
implemented.

## Verification

- focused reducer and transaction suite: **39 tests, 0 failures**;
- complete source suite: **571 tests, 8 environment-gated skips, 0 failures**;
- packaging-owned suite: **571 tests, 8 environment-gated skips, 0 failures**;
- signed app, ZIP, DMG, exact source/test manifest, checksum validation,
  direct executable startup, cleanup, and zero residual packaged processes.

Receipts:

- source snapshot: `d1b32027409e530d48202a62aec67f20eebae33be69291156b18677cc6e5ed2d`
- focused log: `16e1711402e7b12c74bcda46017122ad1409cf54ec55456ebb9c41d49cffef0e`
- full source log: `55557e0994101f15c2583cff9a6c1929fe59987dd1ac0c7bc02daf1810c24b27`
- package test log: `7b144ea2a82baec86f28353caf0426c7a95c5fe8e64d99ef6da87f803126a5fb`
- package command log: `68b7bf3d74c5d375b1b8f296e10e95ae038444807004038d906389be6cef0891`
- runtime smoke log: `19ca5a88d6b8dd555765052c62cf3c3759d72f65575e98d8ced40f79d76e6fc5`
- executable: `c8732db40d9b34df275fc6dbe97a3647bb6236f5d3ca6cacbe669dff37aea8ad`
- ZIP: `4fc2edeedc13806f958337524cab66c456180d7fc3d2160fc402cdd6d202bb46`
- DMG: `46361924b93262efc4a61075a7385f4a4093f4e2747e946437705f5797e41e28`
- CDHash: `1de9d92dcf12b7fc6e3cecd23c91905bf163326c`

The first compatibility-focused compile failed because its Swift raw-string
fixture used the wrong multiline delimiter. The fixture was corrected and all
verification layers were rerun; that failed run and its time are excluded.

## Boundary

This advances source-level acceptance row B-03. It does not prove native
baseline selection, contract confirmation, production binding issuance,
controller cutover, current native UI behavior, a clean revision, or push.
EasyBusiness remained permanently stopped and read-only.
