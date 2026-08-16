# Evidence Provenance, Independent Review, and Report Truth Specification

Status: pre-implementation normative design; production refactor remains unauthorized until the forensic gate.

## Executive conclusion

LoopForge currently assembles review context, not evidence provenance. File changes are inferred from size and modification time, command outcomes are reconstructed from log substrings, screenshots are discovered by filename and recency, source is truncated to selected prefixes, and reviewer citations are accepted if merely non-empty. A model then judges a bounded bundle and its prose is promoted into task state and a polished HTML report.

This architecture can honestly say that evidence is “candidate” while still allowing proxy presence, truncation, lexical matches, omitted intervals and self-authored framing to control approval. It explains how extensive tests and screenshots coexisted with an obviously degraded UI: the evidence system proved that artifacts existed, not that each protected product requirement remained true.

The replacement uses immutable, typed, source-revision-bound evidence records; complete command and capture receipts; explicit omission manifests; blind requirement-addressed review packets; enforceable reviewer independence; contradiction-preserving claim reduction; and reports generated only from accepted receipts. Narrative remains useful as explanation but never becomes lifecycle authority.

## Measured current evidence surface

### Workspace observations

- `WorkspaceEvidenceCollector.fingerprint` records only file size and modification time.
- changed paths are derived from those stamps rather than content, mode, identity or Git state.
- at most eighteen review targets are selected using changed paths, filename heuristics and recency.
- source excerpts include at most 48,000 characters total and at most the first 8,000 characters of a selected file.
- the full assembled evidence text is truncated to 80,000 characters.

### Command observations

- `WorkspaceAuditor` examines only the last 160 command/error logs.
- a verification is inferred from command-message keywords.
- success is inferred from `exit code 0`, `passed`, `build succeeded` or `tests passed` substrings.
- any later inferred success resets all unresolved verification failures, even if it exercised a different command or requirement.
- `CommandEvidenceLedger` retains either all forty or the first eight and last thirty-two relevant entries.
- deduplication uses kind, first line and final `exit code` line; materially different middle output can collapse.
- each rendered entry is bounded to 2,000 characters and the combined ledger to 48,000.

### Visual observations

- screenshot candidates are discovered from extensions, path keywords, modification time and category exceptions.
- at most twelve paths are retained, grouped by domain-specific filename terms.
- a local reviewer receives at most six base64 images; another control path may use four.
- screenshot integrity means one image is at least 400×300 and has luminance variance at least 0.004.
- OCR uses fast recognition and up to twelve strings per image.
- there is no capture session, app/process identity, route/state identity, viewport, locale, accessibility setting, source revision, animation-settle proof or baseline binding.

### Coverage and review

- coverage items use generated English labels rather than stable user requirement IDs.
- source and screenshot candidates are inferred from path-name substrings.
- harness coverage is inferred from success words in rendered logs.
- special game-domain rules add requirements based on vertical keywords.
- a reviewer sees worker feedback before much of the bounded raw evidence.
- “independent” is prompt text; provider, model, session, evidence-selection and organizational independence are not validated.
- returned citations are only checked for non-empty strings, not resolved to supplied records.
- any non-empty external-dependency list can support any `externally_blocked` coverage entry.
- a model coverage map is compared by normalized label text, not typed IDs.

### Reporting

- the HTML report displays scalar confidence, screenshot counts, verification counts and “requirement signals.”
- deterministic fallback text can say every graph node passed retained evidence gates without a universal receipt chain.
- only bounded command logs and a subset of screenshots are embedded.
- model narrative and mutable audit summaries become delivery facts without claim provenance.

## Defects added by this analysis

### F-201 — Workspace deltas use mutable metadata instead of content identity

Equal size/mtime can hide changed bytes; mtime-only changes can create false deltas; modes, links, renames, index state and untracked ownership are not represented.

### F-202 — Evidence selection is filename- and recency-driven

The most recently modified or conveniently named files can displace the files that actually implement a mandatory requirement.

### F-203 — Truncation has no semantic omission contract

Heads and tails are retained, but reviewers are not given typed knowledge of which requirements, commands, failures, source spans or screenshots were omitted.

### F-204 — Command success is reconstructed from prose

Substrings such as `passed` and `exit code 0` are not structured process receipts and can appear in quoted, nested, stale or mixed-success output.

### F-205 — Unrelated success can erase a causal failure

A later green command resets the unresolved-failure counter without proving it reran the failed command, exercised the same requirement or used the same revision.

### F-206 — Screenshot provenance is absent

Any suitably named nonblank image can enter the bundle without proving it came from the running target, current source revision, requested state or declared environment.

### F-207 — Visual integrity is mistaken for visual evidence quality

Dimensions and luminance variance distinguish a nonblank canvas from an empty file; they say nothing about hierarchy, typography, geometry, overlap, clipping or baseline regression.

### F-208 — Review independence is aspirational

The same selected control path can share provider, model biases, prompts, evidence selection and task narratives. No receipt proves separation from the worker or earlier reviews.

### F-209 — Citations are not referentially validated

A non-empty citation string can name a nonexistent path, paraphrase an unseen command or point at a screenshot the reviewer did not receive.

### F-210 — External blocker coverage is not requirement-specific

One listed dependency can legitimize unrelated `externally_blocked` statuses because dependency identity is not bound to requirement and enablement evidence.

### F-211 — Reports flatten claims into facts

Worker claims, reviewer judgments, deterministic observations, accepted receipts and missing evidence are rendered with insufficient provenance distinction.

### F-212 — Evidence policy contains vertical special cases

Game-specific filename and product-state rules violate general-purpose scheduling and can reward domain vocabulary rather than actual contract structure.

## Evidence object model

All evidence is immutable and content-addressed:

```text
EvidenceRecord
  evidenceID
  kind
  producerPrincipal
  producerIdentity
  taskContractRevision
  planNodeContractDigest
  candidateOrCanonicalRevision
  environmentDigest
  startedAt
  endedAt
  sourceObjectDigests[]
  payloadDigest
  payloadLocation
  requirementIDs[]
  freshnessClass
  confidenceClass
  signatureOrMAC
  supersedesEvidenceIDs[]
```

Kinds include `fileObservation`, `processExecution`, `testProtocol`, `nativeCapture`, `geometryMeasurement`, `perceptualComparison`, `resourceObservation`, `externalObservation`, `reviewDecision`, `integration`, `rollback`, `publication`, `quiescence` and `userAuthority`.

Evidence records are observations, not conclusions. A receipt is a validated conclusion produced by a named verifier from exact input evidence IDs.

## File and workspace evidence

`FileObservation` records:

- repository-relative normalized path;
- file kind, mode, size and content digest;
- symlink target or submodule identity;
- HEAD, index and worktree identity where applicable;
- ownership class and preimage/postimage relation;
- read timestamp and any read error;
- exact byte ranges included in a review packet;
- requirement IDs served by the observation.

Workspace deltas are manifest differences, not size/mtime differences. Rename inference never erases create/delete facts. Unreadable or oversized files remain explicit entries with `unobservedContent`, not silent omissions.

Source review is requirement-addressed. The compiler maps a requirement to candidate source symbols, configuration keys, tests and runtime states. If the packet cannot include all relevant spans, it carries an `OmissionManifest` with excluded evidence IDs, byte ranges, reasons and the requirements that remain unassessed.

## Process and command receipts

Every process launch creates a durable `ProcessIntent` before execution and a `ProcessExecutionReceipt` after reconciliation:

```text
ProcessExecutionReceipt
  processReceiptID
  executableDigest
  argv[]
  environmentAllowlistDigest
  cwdIdentity
  stdinDigest
  start/end monotonic and wall timestamps
  processGroupIdentity
  descendantIdentities[]
  stdoutObjectDigest
  stderrObjectDigest
  outputTruncationManifest
  exitKind                 exited | signaled | timedOut | cancelled | unknown
  exitCodeOrSignal
  resourceUsage
  cleanupReceiptID
```

Success is evaluated by an `EvidenceRecipe`, not a substring. A recipe can require exit code zero plus structured test results, expected files, schema checks, runtime responses, absence of named failures, or before/after measurements. One success supersedes a failure only when both receipts share recipe ID, requirement ID, canonical revision, environment equivalence and causal rerun lineage.

Nested shell output never masquerades as the outer process status. Complete stdout/stderr objects remain retained even when the UI renders a bounded preview.

## Test protocol receipts

Where frameworks support it, adapters parse native machine-readable output such as XCTest result bundles, JUnit XML, Swift Testing events, pytest JSON/JUnit, TAP or compiler diagnostics. The receipt contains:

- suite and selector identity;
- discovered, executed, passed, failed, skipped and cancelled cases;
- case-level failure IDs;
- retries and flakes;
- duration and environment;
- code/source revision;
- artifact links;
- parser identity and parse errors.

Plain exit-code tests remain possible, but the lower evidence grade is explicit. A newly passing unrelated suite cannot clear a failed primary recipe.

## Native capture receipt

A screenshot becomes visual evidence only through `NativeCaptureReceipt`:

```text
NativeCaptureReceipt
  captureID
  appBundleOrProcessIdentity
  sourceRevision
  buildPackageDigest
  routeAndStateID
  datasetOrFixtureIdentity
  deviceOrWindowIdentity
  viewportAndScale
  localeAndRegion
  contentSizeOrDynamicType
  appearanceAndContrast
  accessibilitySettings
  reducedMotionSetting
  launchAndNavigationTranscriptDigest
  readinessAndAnimationSettleProof
  imageDigest
  capturedAt
  cleanupReceiptID
```

Asset files, mockups, stale screenshots, simulator home screens and images copied from another revision are distinct kinds and cannot satisfy a running-product recipe.

Freshness is contract-specific. A capture is stale after any change to source/build/data/environment inputs relevant to its state, not merely after wall-clock time.

## Visual measurement and review

Basic decoding, dimensions, entropy and OCR are preflight only. Visual acceptance consumes:

- immutable baseline capture IDs;
- semantic screen/state requirements;
- geometry extraction and overlap/clipping results;
- typography role, scale and wrapping measurements;
- shape/token and spacing measurements;
- perceptual and structural image comparisons;
- accessibility composition checks;
- a blind independent visual decision over all required cells of the capture matrix.

Provider image limits are handled through deterministic batches. Each batch receipt lists included captures; a final reducer refuses approval until every required capture ID has a valid dimension verdict. No unseen seventh image may be implied by a six-image review.

## Evidence graph and contradiction handling

Evidence forms a directed acyclic provenance graph:

```text
source object -> observation -> recipe evaluation -> review decision ->
integration receipt -> completion receipt -> report claim
```

Edges are exact IDs. A later record may supersede another only through an explicit relation and compatible scope. Contradictions remain visible:

- pass and fail at different revisions are not contradictory;
- pass and fail for the same recipe/revision require reconciliation;
- worker claim versus deterministic receipt is a claim conflict, never evidence erasure;
- missing evidence produces `notAssessed`, never `supported` or `absent`;
- externally blocked requires a typed blocker receipt bound to that exact requirement.

## Review packet construction

Packets are built from requirements, not recency:

```text
ReviewPacket
  packetID
  contractRevision
  reviewerRole
  requirementIDs[]
  evidenceIDs[]
  baselineIDs[]
  contradictionIDs[]
  omissionManifest
  priorDecisionVisibility
  workerNarrativeVisibility
  packetDigest
```

Default order for adversarial acceptance review:

1. immutable user contract and requirement IDs;
2. baseline bindings and known debt;
3. raw deterministic receipts and contradictions;
4. candidate/canonical manifest;
5. visual captures and measurements;
6. only then, optionally, worker narrative and earlier review rationale.

This reduces anchoring and self-reinforcement. A summary never replaces a raw receipt; it links to it.

## Enforceable reviewer independence

`ReviewIndependencePolicy` records and checks:

- reviewer principal differs from worker and integrator;
- no shared model session/thread;
- no inherited worker memory;
- reviewer did not select or mutate evidence;
- reviewer cannot write workspace, modify contract, integrate or publish;
- review packet digest is fixed before launch;
- hidden comparison labels prevent candidate-order bias where applicable;
- a second adversarial role is required for high-risk visual, destructive, security, privacy or public effects;
- a deterministic veto cannot be overridden by model confidence;
- malformed/timeout/unavailable review means unassessed, not approval.

Using the same model family is not automatically invalid, but independence grade is lower and must satisfy separate sessions, blind packets and deterministic vetoes. High-risk publication requires an independent grade defined by policy, not provider availability.

## Typed review decision

```text
ReviewDecision
  reviewID
  packetDigest
  reviewerIdentity
  independenceReceipt
  perRequirement[]
  perConstraint[]
  perVisualDimension[]
  contradictions[]
  blockerReceipts[]
  proposedNextActions[]
  confidenceCalibration
  decision              accept | reject | notAssessed

RequirementDecision
  requirementID
  state                 supported | contradicted | partial | notAssessed | externallyBlocked
  evidenceIDs[]
  reasoning
```

Every cited evidence ID must exist in the packet or in an explicitly permitted immutable baseline bundle. Free-form path/command strings are display annotations only. `externallyBlocked` requires a blocker receipt whose `requirementID`, unavailable capability, attempts, safe local preparation, enablement predicate and retry eligibility all match.

## Bounded context without truth loss

Context and image limits are real, but omission must be governed:

- complete evidence objects remain stored outside the prompt;
- deterministic reducers operate on all records before model review;
- packet construction prioritizes mandatory requirements and contradictions;
- each omitted record is named in the omission manifest;
- no omitted requirement can be accepted;
- batches have disjoint or explicitly overlapping evidence IDs;
- final aggregation is mechanical and requires all expected batch receipts;
- summaries state their source set and never introduce facts;
- UI preview truncation has zero authority impact.

## Report truth model

Every user-facing report statement is a typed claim:

```text
ReportClaim
  claimID
  claimType              observation | acceptedConclusion | modelInterpretation | limitation
  text
  requirementIDs[]
  supportingReceiptIDs[]
  contradictingReceiptIDs[]
  revision
  freshness
```

Rules:

- only `acceptedConclusion` may state completion;
- observations describe exact measurements without extrapolation;
- model interpretations are labeled and cannot become facts through formatting;
- limitations and missing cells remain prominent;
- counts identify what was observed, not confidence;
- scalar confidence is never rendered as a quality score;
- screenshot galleries show capture metadata and baseline pairing;
- command previews link to full retained receipt objects;
- reports fail closed if a referenced receipt is missing or stale;
- regenerated reports from the same journal and object store are deterministic except presentation timestamp;
- HTML escaping and content embedding never alter claim semantics.

## Evidence retention and privacy

- evidence inherits workspace sensitivity and task privacy policy;
- secrets are redacted through a reversible-to-authorized-view policy before model packets, while original protected objects remain local when needed;
- remote model transmission is an explicit evidence-use capability;
- screenshots and logs with accounts, tokens or personal data require classification before upload;
- object-store references are retained through rollback and report windows;
- garbage collection preserves any object reachable from an active contract, transaction, receipt or report;
- deletion is journaled and produces a retention receipt.

## Quantitative budgets

- 100% of mandatory requirements appear in packet or omission manifest;
- 100% of citations resolve to evidence IDs;
- 100% of command receipts retain full output digests and exit kind;
- zero inferred success from free-form output substrings;
- zero failure clearing without same-recipe causal rerun;
- 100% of visual captures bind source/build/environment/state identity;
- all capture-matrix cells receive explicit verdicts;
- zero reviewer write/integration/publication authority;
- zero approval when required evidence is omitted;
- zero report completion claims without completion receipt;
- evidence preview limits affect presentation only;
- domain nouns do not change coverage policy.

## Deterministic, adversarial and property tests

1. Same size and mtime with changed bytes produces a delta.
2. Mtime-only change with identical bytes does not claim semantic mutation.
3. Mode, symlink, rename, submodule and untracked state are preserved.
4. Relevant unchanged source can be selected by requirement mapping.
5. Filename `test` alone does not prove regression coverage.
6. Filename `screenshot` alone does not prove a native capture.
7. Oversized/unreadable evidence appears in omission manifest.
8. Source-tail implementation is not hidden by prefix-only excerpting.
9. Middle command failure remains addressable despite preview limits.
10. Two commands with same first line/exit code retain distinct output digests.
11. Quoted `exit code 0` does not mark outer process success.
12. Output `0 passed, 1 failed` cannot satisfy a passing recipe.
13. Exit zero without expected observation does not satisfy a recipe.
14. Later unrelated command success does not clear a failure.
15. Same-recipe causal rerun can supersede the earlier failure.
16. Unknown process outcome remains unknown after restart.
17. Machine-readable test adapter retains case-level failures and skips.
18. Stale test receipt cannot close a new canonical revision.
19. Nonblank arbitrary image fails running-product provenance.
20. Asset image cannot satisfy native UI capture recipe.
21. Capture from wrong app/process fails.
22. Capture from wrong source/build revision fails.
23. Capture from wrong route/state fails.
24. Accessibility capture records exact content-size and settings.
25. Animation/unsettled capture fails readiness policy.
26. Seven required screenshots reviewed in six-image batches require a second batch.
27. Missing final capture cell vetoes visual approval.
28. Geometry overlap veto cannot be overridden by model confidence.
29. Reviewer does not see worker narrative before raw evidence by default.
30. Reviewer session cannot equal worker session.
31. Reviewer cannot mutate evidence selection after packet sealing.
32. Reviewer citation to absent path/evidence ID is rejected.
33. One external dependency cannot block an unrelated requirement.
34. Externally blocked receipt includes exact enablement predicate.
35. Missing evidence maps to notAssessed, not absent.
36. Contradictory same-revision receipts prevent acceptance.
37. Earlier valid receipt remains visible after later failure.
38. Omitted mandatory requirement prevents approval.
39. All requirement batches must be present before aggregation.
40. Summary cannot introduce a fact absent from source receipts.
41. Worker claim cannot supersede deterministic receipt.
42. Report observation distinguishes candidate from canonical state.
43. Report scalar counts cannot produce a completion statement.
44. Missing receipt makes report regeneration fail closed.
45. Report shows stale and contradicted evidence explicitly.
46. Screenshot gallery exposes capture and baseline metadata.
47. Remote evidence transmission requires explicit capability.
48. Secret-bearing screenshot is classified before model upload.
49. Crash/replay preserves provenance graph and contradictions.
50. Property test: every accepted requirement has a path to fresh immutable evidence.
51. Property test: every report fact is derivable from cited receipts.
52. Property test: preview truncation cannot change reducer outcome.
53. Property test: no principal can both produce candidate bytes and independently accept them.
54. Vocabulary-invariance test: equivalent requirements in unrelated domains produce the same evidence topology.

## Implementation boundary after the forensic gate

1. Add typed evidence, process, capture, review and claim values to the pure kernel.
2. Make `ProcessRunner` produce durable structured receipts rather than log-derived outcomes.
3. Replace metadata fingerprints with content-addressed workspace manifests.
4. Add requirement-addressed packet builder and explicit omission manifests.
5. Add native capture harness receipts and visual matrix batching.
6. enforce reviewer independence and evidence-ID citation validation.
7. replace generated label coverage with requirement-ID decisions.
8. replace `WorkspaceAuditor` failure reset and proxy scoring with recipe reducers.
9. generate HTML and machine reports only from typed claims and receipts.
10. shadow-evaluate current tasks to quantify disagreements before enforcement.

The decisive change is that the system must preserve the complete chain from immutable source to observation to verifier to acceptance to report. A persuasive summary, green substring or attractive report cannot substitute for that chain.
