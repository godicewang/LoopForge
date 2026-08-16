# Kernel postimage-verifier exit/result mapping

Recorded at: \`2026-08-12T01:24:51Z\`

## Outcome

LoopForge now deterministically derives one recipe-owned mapping receipt from an exact natural native exit code and an exact canonical parser result. Runtime completion retrieves the ratified executable probe from journal state; reducer replay independently retrieves the same probe from the retained task contract. Callers cannot supply or widen the mapping.

Containment schema v3 atomically records exactly one mapping outcome:

- one exact recipe row selected by \`(nativeExitCode, parserResultCode)\`; or
- a fail-red mapping-failure digest.

A mapping exists only for natural exit with no termination signal, a valid canonical parse, a valid probe, and exactly one matching row. Timeout, output failure, process absence, parse failure, unmatched pairs, and malformed probes cannot acquire a mapping. Schema v1/v2 remain replay-compatible but cannot carry mapping evidence.

The mapping remains deliberately inert. It is not a \`VerificationReceipt\`, does not change the integration phase, and cannot authorize review or publication. A canonical \`"accepted"\` parse followed by wall timeout records only a mapping-failure digest and remains \`appliedUnverified\`. Reducer replay rejects an injected accepted mapping on that timeout path.

## Verification

- Two focused mapping tests passed.
- The native timeout/recovery integration test passed.
- Complete Swift suite: **710 tests executed, 8 intentional environment skips, 0 failures**.
- Release \`LoopForge\` build: passed.
- Release \`KernelSandboxGate\` build: passed.
- Source snapshot SHA-256: \`fd9a8e5ca33c7961f9719f035f01cce0d2ecd76252c5cb8d92a24a83c401208a\`.
- Release \`LoopForge\` SHA-256: \`2cb8f2fca889929463a40165a2f3425ab581134bb2063e92692629ab01aac1c2\`.
- Release \`KernelSandboxGate\` SHA-256: \`21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99\`.
- Diff whitespace check: passed.
- No Swift build or verifier process remained.
- EasyBusiness status fingerprint remained unchanged and read-only.

## Stop-the-line boundaries retained

No non-forgeable postimage result or verification receipt issuer exists, and no latest-red revocation or canonical result-evidence batch has been implemented. Resident-memory enforcement, descriptor-atomic candidate handoff, independent review, integration reliance, current unlocked native verification, package/sign, clean commit, and push remain vetoed.

Final acceptance remains false.
