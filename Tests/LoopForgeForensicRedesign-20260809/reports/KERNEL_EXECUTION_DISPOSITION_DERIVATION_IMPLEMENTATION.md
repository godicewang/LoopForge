# Kernel Execution-Disposition Derivation

Status: **caller-selected execution authority retired; parser/native-exit derivation is journal-bound**

Recorded: `2026-08-11T16:10:33Z`

## Closed authority gap

New writes can no longer submit `completed`, `continuationNeeded`, `blocked`,
`failed`, `interrupted`, `malformed`, or an arbitrary reason digest through
`recordExecution`. The command remains decodable in source only as an explicit
migration tombstone and the reducer rejects every invocation with
`legacyExecutionAuthorityRetired`. Historical `executionRecorded` events still
replay, so the migration does not rewrite or reinterpret existing journals.

Strict parser output now crosses the journal boundary in a non-Codable
`KernelAuthorizedWorkerResultParse` capability. Its initializer is file-private
to the parser implementation; a copied, decoded, or caller-authored Codable
receipt cannot be submitted as a command. The reducer still independently
binds the authorized receipt to the active attempt and the exact accepted
runtime binding, released lease, successful native exit, retained-output
digests, invocation digest, nonce, parser identity, and closed resource.

`deriveExecution` accepts only a new receipt identity plus a source receipt
identity. The reducer—not the caller—maps the source into the disposition. A
worker parse maps its terminal proposal exactly, and blocked/failed/malformed
reasons are the parser-bound result digest. An unavailable external-dependency
observation maps to the exact observation identity and evidence digest. The
result is a durable `KernelExecutionDerivationReceipt` recording run, attempt,
source, source-evidence digest, derived disposition, and journal time. It closes
the active attempt only when the source is present, exact, unconsumed, and bound
to that attempt.

`JournaledProcessRuntime.deriveReleasedWorkerExecution` composes the real native
path without accepting a disposition. It requires the exact transaction that
journaled the strict parse, emits the reducer derivation command, resolves the
exact single-event transaction, and preserves idempotent replay.

## Adversarial and recovery evidence

- direct caller-selected execution rejects without changing active-attempt state;
- all six worker proposals map to exactly one reducer-owned disposition;
- callers cannot replace the reason digest for blocked, failed, or malformed output;
- missing and cross-wired source receipts reject without state advance;
- an available dependency cannot manufacture an unavailable blocker;
- an unavailable dependency derives its reason from exact observed evidence;
- derived events survive Codable round-trip and deterministic reducer replay;
- a disposition/evidence-tampered derived event is rejected during recovery
  without advancing sequence or changing state;
- a real dependency-free native child exits, is released, is strictly parsed,
  derives completion, replays idempotently, and rejects a later cross-wired parse;
- downstream visual and integration journal tests now use full typed process,
  parse, and derivation provenance instead of the retired shortcut.

The complete development suite and the package-owned suite each passed **664
tests**, with **8** environment-gated skips and zero failures.

## Exact package evidence

- Git revision: `6e9b99d12e61c5a4fce2d867d7986cb56c75a1a0` (dirty exact-source binding);
- source snapshot: `149770e482dcbf9acdee8aebc11538b3dc2106f5c03564dfa37e39f5eec8c66c`;
- package test log: `379a682cc7c370ad0cd29881e4ca2dfe336935bfd5eff2a752843b77056b95cc`;
- build manifest: `04c07aef0fb427c3ed2f1a0d527d06ce6d64824fa21d70762357339d8a4e4cbf`;
- executable: `df605b9ea3845d64312771b0153d1ed4f4f8f2b751d93ec241e41c595422f8be`;
- ZIP: `ec6d08b4a43adeee30ca12d02ac33210802fe26522c63b8ecc6fefce4e05a236`;
- DMG: `e4e035091690a67c2873776aa7f8040c7ec6966a8411d27bd3aa3f9586568fa3`;
- checksum manifest: `f921e2462ae2413cd83efbce3b6f4d3a9a72e1de234d21dbcfbd689b991bb643`;
- CDHash: `5de04342d8abb34d5890a4de30cea2d80f4dc1b3`.

Deep signature, checksum, exact packaged Mach-O startup, independent ZIP
extraction, DMG verification and read-only mount, identical executable hashes,
temporary-directory cleanup, zero exact residual processes, and zero exact DMG
attachments passed.

## Remaining stop-the-line boundaries

A native sandbox and same-user evidence-path protection are not yet enforced.
Provider-secret/declared-variable capabilities and provider, verification,
visual, integration, and completion composition remain disconnected. The
legacy `CodexRunner` remains disconnected. Current native screenshots, a clean
commit-bound rebuild, commit, and push remain required. Final acceptance is
false. EasyBusiness remained stopped and read-only.
