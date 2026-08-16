# Provider-Neutral Substitution Contract Implementation

Status: **typed contract and verifier enforcement implemented; production compiler cutover pending**

## Root cause

The legacy system warned agents in prose not to replace a named browser,
desktop app, account session, model, adapter, or other interaction surface. The
kernel task contract had no typed identity binding and verification receipts had
no field capable of proving which implementation was actually exercised.
Consequently, a persuasive green verification could satisfy a requirement after
silently replacing the requested surface.

This was not a provider-routing defect. It was an acceptance-authority defect:
the verifier could attest outcomes without attesting the implementation identity
that the immutable contract required.

## Implementation

`ConstraintContract.Kind.prohibitSubstitution` now carries an
`ExactImplementationConstraint` that binds known requirement IDs to a non-empty
set of exact permitted implementation IDs. IDs are opaque values supplied by
the contract compiler; the reducer contains no provider, product, framework, or
brand dictionary.

An accepted `VerificationReceipt` covering a bound requirement must contain
exactly one `ExactImplementationObservation` for each relevant constraint. The
observation includes the constraint ID, observed implementation ID, and evidence
digest. Missing, duplicate, unrelated, empty-evidence, whitespace-normalized,
or non-permitted identities are rejected before a verification event can enter
the journal. Rejected verification receipts remain able to describe failures
without manufacturing acceptance evidence.

Legacy constraints and verification receipts without the new optional fields
still decode. They cannot satisfy a newly declared substitution constraint,
which is the intended fail-closed migration behavior.

## Adversarial verification

- malformed typed constraints with absent rules, unknown requirements, or
  blank identities fail contract validation;
- two unrelated opaque-name fixtures reject different substituted identities
  through the same reducer policy, proving the decision does not depend on
  brand words;
- an accepted receipt with no binding observation is rejected;
- the exact permitted identity plus evidence digest is accepted;
- legacy field-absent constraint and receipt encodings decode;
- 16 focused kernel tests passed;
- the complete suite and packaging-owned suite each passed 517 tests with 8
  environment-gated skips and 0 failures;
- the rebuilt signed package passed source/test binding, checksum, and exact
  executable startup verification with zero residual packaged processes.

## Boundary

This advances B-05 at the kernel enforcement layer. Final acceptance still
requires production contract-compilation/cutover to populate these bindings,
a clean revision-bound build and push receipt, and the current native UI matrix.
EasyBusiness remained stopped and read-only.
