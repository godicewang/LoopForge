# Redesign Acceptance Matrix

Status: pre-implementation acceptance contract.

The redesign is not accepted because it compiles or because the legacy 281-test suite stays green. It is accepted only when every mandatory gate below has a machine-readable receipt tied to the tested source revision.

## A. State machine and replay

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| A-01 | Only journal events change authoritative state | Attempt direct snapshot mutation from controller/view/timer | compile/API boundary plus reducer event log |
| A-02 | Replay is deterministic | Replay the same event sequence 100 times and after randomized snapshot deletion | identical state digest |
| A-03 | Invalid outcome/review combinations are rejected | `blocked + approved`, `failed + integrated`, `releaseFailed + complete` | typed command rejection |
| A-04 | Events are idempotent | Deliver every event twice and reorder concurrently produced command submissions | one logical effect, stable digest |
| A-05 | Crash recovery excludes offline time | Crash during live attempt, advance wall clock, replay | accepted-active total unchanged |
| A-06 | Pause/stop wins over later Agent/reviewer results | Inject completion response after stop request | terminal stopped projection, late receipt retained but ineffective |
| A-07 | Legacy contradictions stay untrusted | Import blocked+approved historical node | contradiction visible; no accepted review receipt |

## B. Task and product contracts

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| B-01 | Verbatim objective is immutable | Agent proposes a shorter objective that omits a constraint | proposal rejected or explicit owner amendment required |
| B-02 | Every node owns requirement IDs | Plan returns useful-looking node with no requirement mapping | plan rejected |
| B-03 | Baselines cannot be mutated by workers | Worker edits baseline manifest/artifacts | executor denial and failed attempt |
| B-04 | Deliverable cardinality is typed | Request 10 arbitrary artifacts without using image keywords | exact 10 requirement enforced generically |
| B-05 | Forbidden substitutions are provider-neutral | Named surface is replaced by a different adapter | verification rejection independent of brand words |
| B-06 | External dependencies are typed and evidenced | Reviewer invents an unavailable credential blocker | no accepted blocker receipt |
| B-07 | Core behavior is domain-neutral | Run neutral fixtures from unrelated repositories/domains | identical policy decisions for equivalent contracts |

## C. Authority and capability leases

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| C-01 | Default authority is read-only/minimal | Create new Graph/Watcher task without explicit access choice | no Full Access lease |
| C-02 | Prose cannot grant capability | Put `browser`, `photo`, `simulator`, or uppercase handoff tokens in objective | no capability added |
| C-03 | Pure probe does not mutate | Probe empty non-Git workspace | byte/file manifest unchanged |
| C-04 | Isolation failure fails closed | Inject worktree/copy creation failure for writer | node not launched; canonical workspace unchanged |
| C-05 | Scope is executor-enforced | Worker writes an undeclared path before returning | write denied or isolated candidate rejected before evidence review |
| C-06 | Review roles cannot mutate | Reviewer attempts file/process/network mutation | capability denial recorded |
| C-07 | Environment starts empty/allowlisted | Parent contains unrelated secrets | child environment receipt excludes them |
| C-08 | Capability lease expires and releases | Cancel, crash, timeout, stop, app quit | release receipt or explicit releaseFailed terminal block |

## D. Workspace mutation and integration

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| D-01 | User dirt is immutable unless explicitly authorized | unrelated tracked and untracked edits exist | hashes unchanged after candidate/integration |
| D-02 | Mutation budget is enforced | candidate changes extra files/large UI surface | transaction rejected |
| D-03 | Verification binds exact candidate revision | verify revision A, mutate to B, request integrate | stale receipts rejected |
| D-04 | Review binds exact evidence and contract | change evidence attachment or requirement after review | review expires |
| D-05 | Integration is atomic | fail halfway through apply/postimage check | baseline restored and rollback receipt retained |
| D-06 | Conflict repair re-enters all gates | repair Agent exits zero but creates different patch | not integrated without new verification/review |
| D-07 | Publication is separately authorized | node pushes remote before final approval | remote operation denied |
| D-08 | No implicit Git initialization | parallel capability requested in empty user directory | external directory unchanged; isolation owned by LoopForge |

## E. Evidence and independent review

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| E-01 | Transport accepts exactly one strict envelope | prose, examples, two JSON objects, trailing semantic payload | rejected as malformed/ambiguous |
| E-02 | Evidence includes complete attachment manifest | select 12 images while transport cap is four | review blocked; no silent truncation |
| E-03 | Later success closes only matching failure | fail command A, pass unrelated command B | A remains unresolved |
| E-04 | Reviewer independence is provable | same actor/context/model lineage tries to approve own mutation where independence is required | receipt rejected |
| E-05 | Deterministic veto cannot be waived | model says approved while scope/baseline/process gate is red | terminal state remains red |
| E-06 | Requirement closure uses IDs, not filenames | rename screenshots to imply missing states | coverage unchanged |
| E-07 | Reports contain only receipt-backed facts | narrative claims 100 tests when receipt says 42 | claim rejected/labeled untrusted |
| E-08 | Exact review can be replayed | delete UI cache and regenerate report | identical evidence/reviewer input digest |

## F. Causal convergence

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| F-01 | Equivalent strategies share one budget | paraphrase objective, change node ID/model/thread, restart app | same fingerprint and attempt ledger |
| F-02 | No-progress work is excluded | turn returns blocked/rejected with zero evidence delta | accepted-active time unchanged |
| F-03 | Risk weights retry/mutation budget | compare read-only research with broad visual mutation | smaller damage budget for mutation |
| F-04 | Retired strategy cannot reappear in final repair | final reviewer proposes renamed retired action | proposal rejected with inherited lesson |
| F-05 | Replacement is causally different | change only wording while tools/scope/evidence route match | not materially different |
| F-06 | Repeated blocker forces structural decision | same blocker reaches policy threshold | no worker relaunch before split/replace/reframe/typed external decision |
| F-07 | Budgets survive resume/relaunch | crash at last allowed attempt | next replay remains exhausted |
| F-08 | Final audit cannot widen scope | final gap with missing scopes | fail closed; no `.` fallback |

## G. Lifecycle, thermal, and persistence

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| G-01 | Process ownership follows durable session | launcher PID detaches/reparents/relaunches | owned durable process found and reclaimed |
| G-02 | Resource ownership survives nodes/restarts | later node sees earlier task resource | remains task-owned, never relabeled pre-existing |
| G-03 | Stop/quit waits for quiescence | child tree + broker + model + app session + timer active | all released or explicit failure; no false stopped state |
| G-04 | Borrowed resources are not destroyed | pre-existing shared adapter resource | release detaches lease without destructive cleanup |
| G-05 | Owned created resources are deleted when required | create/boot/shutdown device-like fixture | durable object absent after cleanup |
| G-06 | Broker is event-driven/backed off | three idle node scopes for 30 minutes simulated | bounded scan/wakeup count |
| G-07 | Persistence has a write-amplification budget | 150 rapid updates and high-volume logs | coalesced bytes/fsync/publications within budget |
| G-08 | Heavy evidence work is cached by digest | unchanged repo/images reviewed twice | no repeated scan/decode/OCR |
| G-09 | Cadence triggers coalesce | schedule + warning + review completion arrive together | one eligible pass, quiet period honored |
| G-10 | Thermal governor throttles heavy parallelism | high thermal state with three heavy candidates | concurrency reduced and reason retained |
| G-11 | Background continuation is visible and explicit | close last window during work | declared behavior; no invisible surprise workload |

## H. Visual and product-design acceptance

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| H-01 | Capture environment is pinned | compare different locale/appearance/device | comparison rejected |
| H-02 | Named captures are unique states | duplicate bytes under two screen names | state coverage remains one |
| H-03 | Typography uses semantic/token contract | introduce literal point-size divergence | design-token gate fails |
| H-04 | Shape and spacing are relational | content overflows otherwise valid radius/frame | geometry gate fails |
| H-05 | Initial viewport preserves primary task | typography pushes all primary actions below fold | viewport gate fails |
| H-06 | Symmetric components preserve hierarchy | one card wraps asymmetrically in a grid | locale/density gate fails or explicit layout migration required |
| H-07 | Accessibility and aesthetics are separate | every glyph survives but composition collapses | accessibility may pass; composition remains red |
| H-08 | Baseline divergence requires waiver | product hierarchy/shape changes during localization | integration blocked without design migration receipt |
| H-09 | Independent aesthetic veto is mandatory | worker/reviewer approve flat or visibly clipped screenshot | visual acceptance remains red |

## I. Watcher

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| I-01 | Pipeline is sandboxed to declared paths/capabilities | script reads parent/unrelated secret or writes outside generated paths | denied and recorded |
| I-02 | Checkpoint is semantically valid | small non-empty garbage checkpoint | invalid |
| I-03 | Warning events cannot bypass sustained/cooldown policy | direct warning every pass | bounded Agent wakeups |
| I-04 | Review cannot immediately recurse | healthy/failed review finishes before cadence | no immediate pass unless typed critical override |
| I-05 | Agent cannot self-repair/self-approve | same assessment proposes and verifies repair | independent review required |
| I-06 | Completion binds deterministic state and requirement closure | marker says repaired but issues remain | not complete |
| I-07 | Review failure preserves attention | malformed/timeout review while attention exists | attention remains visible |

## J. UI, report, package, and native verification

| ID | Mandatory invariant | Adversarial scenario | Pass receipt |
|---|---|---|---|
| J-01 | UI wording follows typed proof | missing receipt with model-authored “verified” prose | UI labels it claim/pending |
| J-02 | Node time separates accepted total/current/excluded | blocked and rejected attempts plus live work | exact three-way values |
| J-03 | Mode/privilege controls are explicit | gesture-only or hidden mode change attempted | impossible |
| J-04 | Graph exposes convergence diagnosis | retired/repeated strategy fixture | fingerprint, budget, lesson, mutation/evidence deltas visible |
| J-05 | Native UI meets token/geometry gates | standard + accessibility + narrow window | all mandatory H gates pass |
| J-06 | Package matches tested revision | build, sign, archive, hash | revision and binary hashes linked |
| J-07 | Smoke test proves executable success | packaged executable fails while directory exists | smoke test fails |
| J-08 | Terminal package run is quiescent | launch/use/quit packaged app | no owned child/resource/lease remains |

## Completion rule

Every mandatory matrix row must produce a receipt in the final scorecard. Rows cannot be waived by aggregate score, elapsed time, passing legacy tests, or Agent prose. Any red row keeps the redesign incomplete.
