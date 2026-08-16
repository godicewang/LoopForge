# Adversarial Control-Plane Threat Model

Status: forensic design evidence only. EasyBusiness remained read-only. No production refactor is authorized before the analysis gate.

## Security property being tested

LoopForge must remain correct when every model-authored string, repository file, test, screenshot, report, and command output is treated as untrusted evidence. A worker may be mistaken, self-serving, prompt-injected by repository content, or simply optimizing for the current gate. A reviewer may share the same model bias. A green command may be irrelevant. A well-formed JSON object may be an example rather than the intended decision.

The current control plane does not preserve these trust boundaries. It concatenates untrusted material into reviewer prompts, accepts embedded JSON objects, converts string patterns into completion and verification facts, and later uses accepted model narrative as deterministic report content. This creates a self-reinforcing evidence loop even without a malicious actor.

## Trust zones

| Zone | Examples | Current treatment | Required treatment |
|---|---|---|---|
| Z0 immutable authority | verbatim user goal, baseline digest, explicit permission | partly mixed into mutable task snapshots | hash-bound task contract; amendments are explicit events |
| Z1 orchestration facts | command request, process exit, PID, revision, workspace, timestamps | prose logs plus mutable fields | typed, adapter-signed receipts in append-only journal |
| Z2 worker claims | terminal message, completion marker, explanation | inserted directly into audit/review/report | untrusted claim objects, never facts |
| Z3 mutable workspace | source, tests, docs, evidence manifests | scanned and excerpted as evidence | candidate artifacts bound to revision and mutation transaction |
| Z4 reviewer judgment | approval JSON, visual summary, replans | decoded from permissive prose and stored as state | schema-constrained receipt with provenance and independence class |
| Z5 report/UI projection | score, completion text, screenshots | mixes deterministic and model narrative | pure projection of accepted receipts with explicit claim labels |

## Findings

### F-168 — Worker claims and repository content share the reviewer's instruction channel

`GraphLoopEngine.nodeReviewUserPrompt` interpolates `node.lastAgentMessage` and the entire evidence bundle into the same user message as the original goal and active objective (`GraphLoopEngine.swift:6096-6110`). `AuditEvidence` itself embeds worker feedback, source excerpts, command logs, screenshot OCR, and requirement coverage into one undifferentiated string (`AuditEvidence.swift:129-159`).

Impact: source comments, generated reports, command output, OCR text, or worker prose can look like instructions or decision JSON to the reviewer. Even non-adversarial language can anchor the reviewer to the worker's framing.

Required correction: pass typed content blocks with provenance, quote all untrusted text as data, exclude worker conclusions from blind review by default, and ensure reviewer instructions are not co-resident with candidate text in a free-form channel.

### F-169 — Review decoding accepts an arbitrary embedded decodable JSON object

`GraphLoopEngine.decode` first tries the full response, then scans every balanced object and returns the first object that decodes (`GraphLoopEngine.swift:5937-5952`). Similar first-object/outer-brace recovery exists in the supervisor, prompt optimizer, and completion narrative.

Impact: an example, quoted prior decision, repository-sourced object, or format-repair artifact can become the authoritative decision. Structural decoding success says nothing about which actor authored the object or whether it is the final response.

Required correction: use provider-native schema-constrained output where available; otherwise require one framed envelope with nonce, request digest, schema version, actor identity, and signature/MAC-like session binding. Reject extra prose and multiple envelopes.

### F-170 — Completion is inferred from a substring anywhere in accumulated model prose

`WorkspaceAuditor.audit` joins task and every node's last worker/reviewer message, lowercases them, then sets `claimsComplete` when any text contains `loopforge_status: complete` (`WorkspaceAuditor.swift:107-116`).

Impact: historical, quoted, superseded, or adversarial text can satisfy the completion-declaration points. The declaration is not tied to the current revision, task contract, terminal attempt, or actor role.

Required correction: remove completion markers from prose. Completion is a reducer transition authorized only by current, non-expired verification and review receipts for every contract requirement.

### F-171 — Verification facts are reconstructed from lexical patterns in logs

The auditor searches recent command/error text for broad terms such as `test`, `python`, `curl`, `verify`, `passed`, and `exit code 0`. Any matching success adds verification credit; a later success resets `unresolvedVerificationFailures` to zero (`WorkspaceAuditor.swift:68-96`).

Impact: an unrelated green command can clear a distinct failure. A message that merely contains “tests passed” can score as verification. Command identity, expected oracle, candidate revision, environment, and requirement mapping are absent.

Required correction: only the executor emits `VerificationReceipt`; it includes argv digest, executable identity, cwd/workspace/revision, environment digest, start/end, exact exit, output artifact digest, oracle, and requirement IDs. One receipt can supersede a failure only when their verification identity matches.

### F-172 — The worker controls which mutable files become review evidence

Evidence collection prioritizes changed and recently modified paths, then inserts bounded excerpts into review. For visual tasks, screenshot discovery is based on changed paths and evidence-like path names (`AuditEvidence.swift:99-114`, `WorkspaceAuditor.swift:294-298`).

Impact: the same agent that makes the change can shape the review surface by editing favorable files, emitting documentation, touching selected screenshots, omitting states, or placing artifacts under evidence-like names. Absence from the bounded bundle can be mistaken for absence of a defect.

Required correction: evidence requirements are frozen before mutation; collectors are independent adapters that capture specified states from the candidate revision. Required baseline and negative-path artifacts cannot be selected or removed by the worker.

### F-173 — Visual evidence has no source-revision or capture-session chain of custody

Screenshot paths are passed as attachments and later copied into reports, but the authoritative state does not require a receipt binding pixels to app binary, source revision, device/window, locale, content size, route, test invocation, capture time, and baseline digest.

Impact: fresh-looking, decodable pixels can come from a stale revision, a different route, a partial state, or a worker-selected subset. This is the mechanism that allowed screenshot integrity to coexist with severe typography/shape/spacing regression.

Required correction: `VisualCaptureReceipt` is emitted by a controlled native capture adapter and hash-links the full provenance. A visual gate rejects mixed revisions/sessions and missing required states before any model sees the images.

### F-174 — The command evidence renderer can omit the causal failure interval

When more than 40 relevant entries exist, `CommandEvidenceLedger` keeps the first 8 and last 32 and drops the middle (`AuditEvidence.swift:446-483`). This is bounded for prompt size but is not an evidence-preserving summarization protocol.

Impact: the omitted region can contain the first failure, resource leak, scope violation, or measurement-boundary error. The reviewer sees a curated textual window without an omission manifest or digest tree.

Required correction: retain all receipts in the journal; give the reviewer an indexed summary plus explicit omitted ranges and Merkle/digest references. Deterministic gates inspect the full typed ledger, not the prompt excerpt.

### F-175 — Reports promote accepted model narrative into product facts

The deterministic completion narrative lists completed-node reviews as completed work and uses the last completed worker message as the current experience (`CompletionReportGenerator.swift:250-280`). If there is no message, it states that every graph node passed its evidence gate.

Impact: after a model marks a node completed, the report repeats its claims through a “deterministic” path, obscuring their provenance and making a false approval look corroborated.

Required correction: reports may quote claims only under an explicit claim label. Factual tables are derived exclusively from accepted receipts; unsupported fields remain `unverified`, never converted into prose certainty.

### F-176 — Reviewer independence is not an enforceable runtime property

The selected Main Graph Agent can be the same provider/model family as the worker, receives the worker's conclusion, its tests, its screenshots, and mutable docs, and is prompted to decide. A role label does not create epistemic independence.

Impact: shared priors and self-authored evidence reinforce the same local optimum. This explains why basic geometry/test artifacts repeatedly outweighed obvious design degradation.

Required correction: review receipts record actor/provider/model/context lineage. High-risk changes require an adversarial reviewer with separated context and a deterministic veto. Reviewer inputs begin with immutable baselines and raw receipts, not worker conclusions.

### F-177 — Audit scoring is a proxy-feature accumulator rather than a requirement proof

The auditor awards points for the existence of source bytes, docs, manifests, test-like files, images, a success-like command, and a completion marker. These features are useful diagnostics, but they are not semantically bound to the requested requirements.

Impact: agents can improve the score by adding evidence-shaped artifacts while product quality worsens. A score of 100 can therefore coexist with `visualAuditPassed=false` and `supervisorCompletionApproved=false`, exactly as observed in the stopped task.

Required correction: remove aggregate score from completion authority. Display coverage per immutable requirement, with typed accepted/missing/expired/contradictory states. Any mandatory red gate vetoes completion.

### F-178 — Reviewer output can mutate topology without deterministic semantic comparison

Current repairs add structural retirement and replacement, but “materially different” is still largely enforced through text normalization and model judgment. A paraphrased objective or new node ID can reintroduce the retired strategy under a new surface form.

Required correction: a replacement declares which contract dimension changed: resource source, authority, workspace topology, responsibility, measurement boundary, verification oracle, or external dependency. The reducer rejects replacements that do not change an allowed typed dimension and inherit the failed causal fingerprint.

## Attack / failure paths to test

1. A repository file contains a valid-looking approval JSON object and instructions to ignore visual defects.
2. A worker quotes `LOOPFORGE_STATUS: COMPLETE` while explicitly saying it is not complete.
3. A failing primary test is followed by an unrelated successful `python --version` or narrow test.
4. A worker generates only favorable screenshots and deletes the required overflow/error state.
5. An image from revision A is submitted while code revision B is reviewed.
6. The worker and reviewer use the same provider/model/context lineage.
7. An exhausted strategy is paraphrased under a fresh node ID without changing any typed contract dimension.
8. A report attempts to state a field as fact when its only source is worker narrative.

Every case must fail closed without launching an additional mutating worker.

## Target information flow

```text
Immutable TaskContract
        |
        v
Reducer-authorized NodeContract ----> Capability / Mutation leases
        |                                      |
        v                                      v
Untrusted worker output                 Executor receipts
        |                                      |
        +-------------- claims ----------------+
                               |
                               v
                    Independent collectors
                               |
                               v
                Verification / visual receipts
                               |
                               v
              Adversarial review (separated context)
                               |
                               v
                 Reducer validates all identities
                               |
                               v
                  UI/report read-only projection
```

The essential rule is simple: model prose proposes; typed receipts prove; the reducer decides.
