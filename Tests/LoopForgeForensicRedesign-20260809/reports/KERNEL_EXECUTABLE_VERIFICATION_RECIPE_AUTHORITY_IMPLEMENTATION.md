# Kernel Executable Verification Recipe Authority Implementation

Recorded: `2026-08-11T22:22:38Z`

Status: **contract/compiler/native-confirmation authority implemented; verifier runtime, candidate attestation, receipt chain, review, and native start remain vetoed**

## Outcome

LoopForge no longer ratifies a requirement-evidence recipe that consists only of a verifier label and expected-observation prose. A new recipe must bind a bounded direct-process probe into the exact compiler candidate and whole-candidate native user confirmation.

The implementation intentionally does not launch the probe, issue a verification receipt, add a native start control, or infer a command from the objective. Production AppModel starts with no verification probe selected and fails before confirmation or journal creation. A future native selector must supply the exact typed probe.

## Sealed authority

Each executable probe now retains and validates:

- schema version and the only supported transport, `localDirectProcess`;
- exact lowercase SHA-256 of the executable content;
- at most 64 fixed argv elements with no NUL data or shell interpretation;
- at most 64 uniquely identified input bindings;
- exactly one candidate-postimage input;
- an exact `@loopforge-input:<id>` argv token for every input, occurring once;
- the minimal kernel environment plus exact environment and capture identity digests;
- a parser identity, positive schema version, and exact parser content digest;
- at most 64 unique exit-code/parser-result mappings with at least one explicit accepted mapping;
- mandatory rejected outcome for every unmatched result;
- disabled network;
- positive wall-clock, captured-output, and resident-memory ceilings;
- zero child processes; and
- independent verifier lineage.

Shell commands, remote transports, provider/model calls, ambient environments, network access, child fan-out, unmatched green fallbacks, missing candidate inputs, and descriptive-only legacy recipes cannot be expressed as valid new authority.

## Control-path changes

- `TaskContractCompiler.swift` defines the canonical probe schema and rejects missing, malformed, non-independent, networked, unbounded, ambiguous, or fail-open recipes.
- `TaskContract.swift` includes executable-probe validity in durable complete-provenance checks.
- `NativeTaskContractAuthoring.swift` accepts only a separately supplied exact probe, marks the recipe deterministic, and never synthesizes it from objective text or agent profiles.
- `AppModel.swift` provides a typed draft boundary whose production default is nil. Missing configuration creates no confirmation, task, journal, or process.
- `Views.swift` renders every probe field in the whole-candidate confirmation sheet.
- `KernelRunEnrollmentCoordinator.swift` rechecks complete durable recipe provenance and contract validity before journal creation.

Legacy descriptive recipes remain decodable only for forensic recovery and fail compilation/durable validation.

## Verification

- focused compiler/native-authoring/enrollment/production-preparation matrix: **52 passed, 0 failed**;
- complete Swift suite: **698 executed, 8 environment-gated skips, 0 failures**;
- non-DEBUG arm64 Release build: **passed**;
- exact source snapshot: `3335064bc48870502e40e6185717314df82eaffc5cae332aedbeeda546c4b537`;
- diff whitespace validation: **passed**;
- EasyBusiness read-only status: **unchanged**.

The initial integration-focused run that exposed three old AppModel tests assuming an invented recipe, and a later compile-only test attempt against immutable ratification data, are excluded from the ledger. Test/build execution and polling/wait time are also excluded.

## Remaining stop-the-line dependencies

This closes only the first causal prerequisite from the deterministic-verifier audit. Native start and production verification remain vetoed until LoopForge adds:

1. journal-owned candidate source-tree/postimage attestation at the mutation/executor boundary;
2. a separately activated verifier process lease and actor lineage;
3. an exact receipt chain binding recipe, executable, argv/input artifacts, candidate, environment, capture, parser, output, oracle, and transaction;
4. verification identity and journal sequence with latest-red revocation;
5. a canonical verification-evidence batch; and
6. separately activated read-only independent review of that exact batch.

No package, commit, push, or final acceptance is claimed.
