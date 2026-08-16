# Kernel postimage-verifier result parser implementation

Recorded at: `2026-08-12T00:39:45Z`

## Outcome

LoopForge now contains the byte-exact parser identified by schema-v2 verification recipes. It accepts exactly one UTF-8, sorted-key canonical JSON object followed by exactly one LF. The envelope has exactly three keys: `evidenceDigest`, `resultCode`, and `schemaVersion`. Schema must equal 1, evidence must be lowercase SHA-256, result code must be a bounded exact identity, and retained stderr must be empty.

The parser rehashes the exact stdout/stderr bytes and requires them to match the journal containment receipts. Its successful receipt binds run, activation, launch, resource, lease, parser implementation identity, both retained-output digests, the terminal-envelope digest, result code and evidence digest. The parser returns that receipt only inside a non-serializable capability; decoding durable bytes cannot recreate future result authority.

Unknown keys, missing or extra lines, narrative tails, CR/LF variants, whitespace variants, noncanonical key ordering, invalid UTF-8/JSON, nonempty stderr, byte-count or digest substitution, parser-identity substitution, unsupported schema, invalid result identity and invalid evidence digest all fail closed.

## Verification

- Four focused parser tests passed.
- Complete Swift suite: **708 tests executed, 8 intentional environment skips, 0 failures**.
- Release `LoopForge` build: passed.
- Release `KernelSandboxGate` build: passed.
- Source snapshot SHA-256: `b1a2154a4df10e394f13b3401942006cb80b6e9e1c007ea710de7e77dbdbcf03`.
- Release `LoopForge` SHA-256: `4d68c765974e48e8b698fd0413d0861503e4154045845fedeb3cc1ec64f03dc7`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Diff whitespace check: passed.
- EasyBusiness fingerprint: unchanged and read-only.

## Stop-the-line boundaries retained

The parser exists but is not yet composed into verifier completion or journal replay. It cannot evaluate the recipe's exit/result mapping, issue a verification receipt, revoke a later red result, change integration from `appliedUnverified`, or authorize review. Resident-memory enforcement, descriptor-atomic candidate handoff, independent review, native start, package/sign/native verification, commit and push also remain vetoed.

Final acceptance remains false.
