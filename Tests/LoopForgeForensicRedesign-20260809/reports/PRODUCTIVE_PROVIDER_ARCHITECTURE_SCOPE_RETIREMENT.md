# Productive provider architecture scope retirement

Status: **ordinary-app “install a backend and cut over” strategy retired; typed architecture veto, exact package, and native UI evidence passed**

## Decision

Productive provider execution is not a missing plug-in inside the current
ordinary macOS application. The package owns a signed V2 transport harness,
but its manifest, self-test, executable behavior, native loader, readiness
compiler, and runtime replay all deliberately authorize only
`transportVetoOnly`. A productive provider would additionally need the
privileged or virtualized isolation product identified by the resident-memory
strategy audit, independent ratification of that product and its executable
identity, and an end-to-end resource boundary. None can be minted by changing
one manifest field or installing another binary.

The old release-gap wording—“productive provider backend ratification and
native launch cutover”—made the missing boundary sound like ordinary packaging
work. That was misleading. For the current product, the correct terminal state
is an explicit product-architecture veto. A separately scoped isolation
product may later return exact non-serializable authority, but it is not an
unfinished code path in this package.

## Evidence chain

1. `NativeProviderHarnessSelectionLoader` accepts only the package-owned exact
   executable whose manifest declares `transportVetoOnly`, an empty productive
   backend list, and the fixed canonical self-test identity.
2. The harness accepts the V2 descriptor, fixed FD-196 context, exact stdin
   prompt, optional FD-197 credential, and canonical result transport, but a
   valid request can propose only `blocked`.
3. Provider readiness, direct authorization, and decoded-receipt replay all
   require `productive`; the current native authoring path obtains only the
   loader's transport-veto mode.
4. The ordinary-macOS containment audit proves that this application cannot
   issue the required hard pre-exec physical-footprint capability. Therefore a
   productive manifest without a separate isolation product would be an
   authority forgery even if the executable hash were exact.
5. The strengthened adversarial fixture declares productive mode, a Codex
   backend, a self-consistent productive self-test, and the exact harness
   executable identity. Native selection still rejects it as
   `manifestInvalid`.

## Source correction

- The semantic profile blocker is now
  `productiveProviderArchitectureUnavailable`. Its durable schema-v1 raw value
  remains `providerHarnessProductiveBackendUnavailable`, so recovered
  readiness evidence is compatible.
- The direct authorization error uses the same architecture-level meaning.
- User-visible diagnostics now explain that installing or relabeling a binary
  cannot authorize execution without separately isolated and ratified
  architecture.
- Task-contract and loader comments state that `productive` is reserved for a
  separate privileged or virtualized product, not an editable package mode.

## Verification

- Focused provider compiler/selection suites: **23 passed, 0 failed**.
- Complete Swift suite: **868 executed, 8 skipped, 0 failures**.
- Package-owned suite: **868 executed, 8 skipped, 0 failures**.
- Exact source snapshot:
  `4ec4c6aba1c46410eb322909657b84d3a68797e00e451f7575a7caee4af0fd44`.
- Release compilation, deep strict ad-hoc signing, ZIP/DMG/checksum validation,
  direct startup, mounted startup, all-three-Mach-O mounted byte identity,
  detach, and cleanup passed.
- A newly enrolled inert native ready run displayed the exact architecture
  veto, kept **Activate Native Attempt** disabled, and admitted no native
  attempt. LoopForge, `KernelSandboxGate`, and `LoopForgeProviderHarness` were
  all stopped after UI quit.

Native screenshot:
[packaged architecture veto](../screenshots/packaged-loopforge-productive-architecture-veto-20260816T081700Z.png),
SHA-256
`664944cc600d13cde571e1b2f3b5bf3a217a450938fd8a75de4a6c36c9d14d9e`,
860×760 pixels.

## Package identity

- app executable: 26,296,976 bytes,
  `2fe6039993b643d5907a38e0e8622c6baa301150d245bb6f5022ebafcb56ec75`,
  CDHash `0ac5ef7b776e853300887b1ae41efc5647181bc0`;
- sandbox gate: 78,512 bytes,
  `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`;
- provider harness: 145,952 bytes,
  `d4de4d8b38a59186f8f184ddf1c54ea7f63bd5084d18df0bb37fa7edd19154ac`;
- ZIP:
  `dd1cdabfe1d08527abc1dea0cd1db859bbcd026951c86a42045bf8a6e3793bde`;
- DMG:
  `76ee84729fa9a1b49081a9af68a9f6875392c6b3f16497d9da148ad73989317e`;
- package test log:
  `86bb36bcb3edc80d7b04e7b8262f11fa6ebf3abfbea02c341cb114388e344ee7`.

## Remaining release work

The current package truthfully remains non-productive. Creating a separate
privileged/virtualized execution product would be a new product authorization,
not a remaining step in this ordinary-app audit. The complete current native
trait/window/baseline/candidate matrix, an exact clean-commit package rebuild,
commit, and push remain. Final release is false. EasyBusiness remained stopped
and read-only.
