# Kernel postimage-verifier parser authority

Recorded at: `2026-08-12T00:31:03Z`

## Finding

The prior executable recipe still contained a descriptive parser gap. A parser contract accepted any trimmed ID, positive schema number and syntactically valid SHA-256. Those fields could preserve a label such as `accepted` without identifying any executable grammar or parser implementation. Treating that metadata as result authority would have recreated the forensic failure mode in which prose-shaped claims become facts.

## Implementation

New verification probes use schema version 2. Their parser contract must name the typed `canonicalJSONResultV1` format, parser schema version 1, and the exact built-in implementation identity digest for one canonical sorted-key JSON object followed by one line feed. Arbitrary digest-shaped metadata, missing format, unsupported probe versions and mismatched parser schema fail validation.

Native task authoring independently requires probe schema version 2. Postimage-verifier activation independently rechecks the schema, format and implementation digest before it can stage an executable or admit a process. Therefore a decoded legacy contract cannot be converted into new runtime authority by passing through a weaker boundary.

Schema-v1 parser metadata remains decodable so historical journals can be inspected and replayed read-only. It does not authorize new native authoring or verifier activation.

## Adversarial proof

- A v2 probe with its parser format removed and digest replaced by another valid SHA-256 is rejected before authoring.
- A schema-v1 descriptive parser decodes, but native authoring rejects it explicitly.
- A legacy parser JSON object without the new field decodes with no format, then fails v2 probe validation.
- Existing native enrollment, compiler, activation and exact crash-containment tests pass after all current fixtures move to the canonical parser identity.

## Verification

- Focused parser-authority matrix: 3 tests passed.
- Complete Swift suite: **704 tests executed, 8 intentional environment skips, 0 failures**.
- Release `LoopForge` build: passed.
- Release `KernelSandboxGate` build: passed.
- Source snapshot SHA-256: `66f642ab87104717842ef374dd5b9966bad3ac101aed67f2ac1e76b352564054`.
- Release `LoopForge` SHA-256: `d4a05d79c4d1a1f233f5dc97efa9accdb3847cf2f95e058d328ac474562b2ed2`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Diff whitespace check: passed.
- EasyBusiness fingerprint: unchanged and read-only.

## Stop-the-line boundaries retained

This change identifies the only parser that new recipes may request; it does not execute that parser. No output/result envelope, parsed receipt, exit/result mapping, verification receipt, latest-red revocation or accepted evidence batch exists yet. Resident-memory enforcement and descriptor-atomic candidate handoff also remain unresolved. Independent review, integration acceptance, native start, package/sign/native verification, commit and push remain vetoed.

Final acceptance remains false.
