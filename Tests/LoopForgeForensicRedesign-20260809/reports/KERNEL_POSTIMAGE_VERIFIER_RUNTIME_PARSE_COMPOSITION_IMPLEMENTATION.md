# Kernel postimage-verifier runtime parse composition

Recorded at: \`2026-08-12T00:59:46Z\`

## Outcome

LoopForge now parses the exact retained verifier bytes inside the typed completion boundary and journals the parse outcome atomically with containment and lease release. The descriptor-relative output reader returns both the content receipt and the same bytes used to compute that receipt, so parsing does not reopen a path or cross a second byte boundary.

Schema-v2 containment records exactly one result-parser outcome:

- a canonical parse receipt bound to the activated parser, run, launch, resource, lease, stdout digest, stderr digest, result code, and evidence digest; or
- a deterministic fail-red parse-failure digest.

Schema-v1 containment remains decodable for historical replay but cannot carry parser evidence. Replay reconstructs the canonical envelope from the durable result fields and requires its SHA-256 to equal the captured terminal-envelope digest. Changing \`resultCode\` or \`evidenceDigest\` while retaining the old digest is rejected.

The result is deliberately not verdict authority. A native verifier fixture emits a valid canonical \`"accepted"\` envelope and then exceeds its wall deadline. Completion retains and parses the envelope, but the containment disposition remains \`wallClockExceeded\`, no \`VerificationReceipt\` is created, and the integration transaction remains \`appliedUnverified\`. Recovery from an earlier journal snapshot records either the complete parse or a parse-failure digest according to the exact bytes retained at that snapshot; it never invents missing output or exit evidence.

## Verification

- Four focused parser tests passed.
- The native timeout/recovery integration test passed.
- Complete Swift suite: **708 tests executed, 8 intentional environment skips, 0 failures**.
- Release \`LoopForge\` build: passed.
- Release \`KernelSandboxGate\` build: passed.
- Source snapshot SHA-256: \`357094dc3fcd04b436d0e543d866f719e5fb8a4b033ade1ee69cdca6880291b0\`.
- Release \`LoopForge\` SHA-256: \`b885455303c157c9905c6e1936c1b595847bd2057f16c5e4dcfc3b6105ba4568\`.
- Release \`KernelSandboxGate\` SHA-256: \`21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99\`.
- Diff whitespace check: passed.
- No Swift build or verifier process remained.
- EasyBusiness status fingerprint remained unchanged and read-only.

## Stop-the-line boundaries retained

No exit/result mapping is evaluated and no non-forgeable postimage result or verification receipt exists. A parsed \`"accepted"\` value therefore cannot authorize review, acceptance, publication, or native start. Latest-red revocation, resident-memory enforcement, descriptor-atomic candidate handoff, independent review, integration reliance, current unlocked native verification, package/sign, clean commit, and push remain vetoed.

Final acceptance remains false.
