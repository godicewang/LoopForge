# Kernel Provider Stored-Credential Authority

Status: **exact ratified Keychain credential authority is present; provider launch remains gated on a separately packaged harness and exact network authority**

Recorded: `2026-08-15T17:33:44Z`

## Result

Provider authentication is now explicit contract data. `KernelAgentExecutionProfile`
retains either `none` with no reference or `opaqueProviderSecret` with one exact
valid `macOSKeychainGenericPassword` service/account reference. Historical
profiles decode to no credential authority. Provider kind no longer infers
whether a credential exists: a Codex signed-in session can be credential-free,
an API profile can require the exact stored reference, and a malformed or
cross-wired pair fails contract and invocation validation.

The native authoring path maps an API connection to the same safe Keychain
service/account identity already used by `APIKeyVault`; local and signed-in
Codex selections retain no secret authority. No credential bytes enter the
contract, prompt, arguments, environment, receipts, journal, recovery state,
or reports.

The production execution session no longer accepts caller-supplied secret
bytes or a caller-selected Keychain query. `KernelProviderSecretIssuer`
revalidates the exact authorized invocation and execution proof, resolves only
the ratified generic-password reference with `SecItemCopyMatching`, bounds the
returned bytes, copies them into the existing one-shot expiring capability,
and zeroes its local mutable buffer. The capability still crosses only fixed
descriptor 197 after native spawn, is bound to run/attempt/provider/invocation,
and erases itself after delivery or expiry. The raw-byte issuer and deterministic
credential resolver exist only in DEBUG tests; the non-DEBUG production API
contains only stored-reference resolution.

Adversarial tests prove that missing API credential authority is rejected,
credential-free remote execution does not acquire a credential descriptor,
the exact ratified reference resolves and delivers the expected length-prefixed
bytes, a different reference returns `errSecItemNotFound`, metadata contains no
secret, and credential-free invocations cannot mint a capability. Historical
evidence missing the new fields remains decodable but invalid for current
launch.

## Verification

- focused provider suite: **14 tests**, **0 failures**, **0.012 test seconds**;
- exact source suite: **821 tests**, **8 intentional skips**, **0 failures**,
  **60.343 test seconds**;
- package-owned suite: **821 tests**, **8 intentional skips**, **0 failures**,
  **65.832 test seconds**;
- real Codex child/Responses bridge: **21.377 seconds**;
- source snapshot:
  `7a620530a0c5d68750f8d73dc26d57d6a2ad3f3980d81708513e1c7a090f94e6`;
- packaged LoopForge SHA-256:
  `5c872798ee3dbeb50e8e48421ebe7c9523b53fca1e275dd217646c3a30cbeee9`;
- package test log SHA-256:
  `9b869db5031e19e00631e339cad26db4a7d4f60003f101497d00f6cb10787a23`;
- both non-DEBUG arm64 products built; deep-strict signing, ZIP, DMG,
  checksum manifest, exact source/test binding, bounded packaged-Mach-O
  startup, and cleanup passed.

## Boundary

This closes credential selection and delivery authority; it does not claim a
production provider launch. Native Codex/local/API selections remain typed
`providerProtocol = unavailable`, because no separately packaged and
independently ratified LoopForge V2 provider harness exists. Exact network
authority is also not yet issued. The launch veto therefore remains correct.
Native mutation preparation or its retained veto, trusted Release containment
or its retained vetoes, legacy Single/Parallel retirement, unlocked current
native screenshots, a clean-commit rebuild, commit, and push remain pending.

EasyBusiness was only re-read. HEAD remained
`2ae40452e6d8661c46db466c43ea40bba3bfab04`, and its read-only status
fingerprint remained
`2fe574a1dc8aec8b8df4bfd02da0d698b53ac941076553d58389f01daa35033a`.
Final release remains false.
