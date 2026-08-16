# Native Exact-Implementation Authority

Status: **native authoring, confirmation, enrollment, and activation retention implemented; clean package and real native confirmation passed**

## Forensic correction

The earlier B-05 receipt correctly described kernel enforcement but overstated the
remaining controller gap. The release application already constructs
`KernelProductionExecutionCoordinator`, retains the production execution session,
and routes the explicit native activation action through that coordinator. The
remaining B-05 defect was narrower and real: the native Journaled Auto Graph
composer could not author or confirm the opaque implementation identities already
required by `ExactImplementationConstraint`.

## Implementation

The native composer now accepts an optional comma/newline-separated set of exact
opaque implementation IDs. `NativeExactImplementationIdentityParser` trims and
sorts the values without interpreting product, provider, framework, filename, or
brand vocabulary. It deliberately preserves duplicates so the authoring boundary
can reject ambiguous authority rather than silently repairing it.

When the set is nonempty, native contract authoring now:

- rejects duplicate, empty, or non-trimmed direct values;
- includes the canonical identity bytes in the candidate identity digest;
- records those exact bytes in a distinct `.user` source artifact;
- creates one typed `.prohibitSubstitution` constraint bound to the mandatory
  requirement and the exact permitted set;
- binds that constraint to the user source span with explicit epistemic state;
- displays the exact identities in the immutable confirmation sheet; and
- retains the same typed constraint through journal-first enrollment and explicit
  production activation.

Empty input creates no substitution claim. Objective prose, model output, product
names, and repository vocabulary cannot populate or widen the set.

## Verification

- 17 `NativeTaskContractAuthoringTests` passed, including canonical parsing,
  duplicate preservation and rejection, whitespace rejection, user-source
  binding, typed constraint binding, and candidate-identity sensitivity.
- 14 `NativeKernelEnrollmentFlowTests` passed, including exact-identity retention
  through authoring, confirmation, enrollment, and explicit activation.
- 20 `TaskStoreTests` passed, including draft reset behavior.
- 24 `TaskContractCompilerTests` passed, preserving existing authority and
  source-binding invariants.
- `git diff --check` passed.

The clean current-source package at revision
`4bd9bf90272e575fa5d86fd80c4bbfc9cccb6610` then passed **875 tests,
8 skips, and 0 failures**. Its embedded manifest records `sourceDirty: false`,
source snapshot `9671afb3d2aa99990dab2163e122ac3597a0f4567f0b204318713b63f246dab1`,
and test-log digest
`9b74c22714e66e2862ea70415610095e017a3d8673a4fe4025f751b0504cd361`.
Deep-strict signing, ZIP integrity, DMG verification, checksum verification,
bounded exact-executable startup, and smoke verification passed.

Computer Use then exercised the real packaged composer against the bounded
LoopForge workspace `/Users/godice/Coding/LoopForge/Sources/KernelSandboxGate`.
Both worker and reviewer were read-only and worker network authority was off.
The immutable sheet displayed the canonical sorted exact set
`kernel-contract-v2`, `loopforge-native-authority-v1`, the exact verifier digest
`85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`,
and a zero-file/zero-byte mutation ceiling. The sheet was canceled before
enrollment: the sidebar remained at two historical tasks and no ready run or task
was created. The packaged process quit cleanly.

Two preceding attempts to capture the whole LoopForge root rejected symlink
entries before task creation. They demonstrate fail-closed handling but count zero
as acceptance evidence.

## Boundary

This closes the missing native B-05 population, package, and real confirmation
path. It does not make the full release acceptable: unrelated mandatory Watcher,
visual/final-completion, repository telemetry, productive-provider, containment,
and mutation-isolation gates remain. EasyBusiness was used only as read-only
forensic evidence and was not mutated.
