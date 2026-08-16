# Native Exact-Implementation Authority

Status: **native authoring, confirmation, enrollment, and activation retention implemented; current package and native walkthrough pending**

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

## Boundary

This closes the missing native B-05 population path at source and targeted-test
level. It does not make the full release acceptable. A clean current-source full
suite/package and real native composer/confirmation walkthrough remain pending,
as do unrelated mandatory Watcher, visual/final-completion, repository telemetry,
productive-provider, containment, and mutation-isolation gates. EasyBusiness was
used only as read-only forensic evidence and was not mutated.
