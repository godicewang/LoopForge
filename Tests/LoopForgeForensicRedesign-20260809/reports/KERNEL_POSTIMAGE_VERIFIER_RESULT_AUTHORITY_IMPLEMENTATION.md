# Kernel postimage-verifier result authority

Recorded at: `2026-08-12T01:51:01Z`

## Outcome

LoopForge now derives a content-addressed postimage result receipt only from one exact activation, launch, release identity, integration/apply/attempt lineage, requirement set, candidate source revision, verifier identity, retained stdout/stderr digests, canonical parse, deterministic mapping row, outcome, and completion time.

Containment schema v4 atomically records exactly one result state:

- a replay-reconstructable result receipt for complete mapped evidence; or
- a fail-red result-failure digest when output, parse, mapping, or natural completion is absent.

The durable receipt is evidence, not command authority. Its live wrapper has a private initializer and requires a file-owned, non-serializable journaled-runtime issuer token. The runtime returns that wrapper only after the exact release event is committed and read back from `RunJournal`, and after the runtime supervisor accepts the release. Decoding or fabricating the durable bytes cannot recreate the live capability.

Timeout and already-absent recovery paths return neither a durable result nor a live result capability. Reducer replay rejects a fabricated accepted result inserted into the timeout path. The ordinary `VerificationReceipt`, latest-red revocation, independent review, and integration acceptance paths remain deliberately separate and unimplemented.

## Verification

- Two focused deterministic result-authority tests passed.
- Eight journal/integration state-machine tests passed, including fail-red timeout/absence and injected-result rejection.
- The native journal scenario proved a second ratified verifier exits naturally, persists its accepted result inside the exact release, and returns the matching live wrapper bound to that release transaction.
- Complete Swift suite: **712 tests executed, 8 intentional environment skips, 0 failures**.
- Release `LoopForge` build: passed.
- Release `KernelSandboxGate` build: passed.
- Source snapshot SHA-256: `69c38850dbca09b40b77f101dd903221f3b55791f933a4f85a9c92549a6b00ab`.
- Release `LoopForge` SHA-256: `67eca1b10e5d5ae550fcae4e91e414d6e51630a5a0b307ff53bcc0c60dba202a`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Diff whitespace check: passed.
- No Swift build or verifier process remained.
- EasyBusiness status fingerprint remained unchanged and read-only.

## Proof boundary retained

The positive native natural-exit issuance path is now proven. The journal scenario independently ratifies a second recipe for the same applied candidate, launches it through the native sandbox, observes natural exit 0, canonically parses the retained bytes, selects the exact accepted mapping, persists the content-addressed result inside the exact release event, and returns a live wrapper whose transaction reads back that release. The same state contains no ordinary verification receipt and remains `appliedUnverified`.

No `VerificationReceipt`, latest-red revocation, canonical result-evidence batch, independent review, or integration acceptance was issued. Resident-memory enforcement, descriptor-atomic candidate handoff, native selector/start, current unlocked native UI verification, package/sign, clean commit, and push remain vetoed.

Final acceptance remains false.
