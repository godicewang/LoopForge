# Git Integration, Remote Side Effects, and Split Source of Truth

Status: confirmed systemic defect. This report treats every EasyBusiness Git/worktree state as read-only evidence and audits the current uncommitted LoopForge repair; it does not declare the redesign complete.

## Historical behavior

The stopped Graph did not have one integration authority. Isolated Sub Agents committed and pushed directly to the canonical remote while LoopForge's workspace coordinator simultaneously expected to integrate their results as patches.

Across the retained node logs:

- 11 nodes issued a direct `git push ... HEAD:main` command;
- 15 completed push attempts are recorded;
- 10 succeeded;
- five failed with non-fast-forward rejection;
- 12 successful `git commit` command invocations were made by 10 nodes;
- the canonical history gained 12 commits between the Graph's inherited English baseline `88a2bdf` and stopped-state `2ae4045`.

This is not harmless duplication. Once one isolated node advances `origin/main`, every sibling created from an older integration snapshot is now divergent. A later sibling can have a correct local patch and still fail its required push, or it can push before the coordinator has integrated another accepted sibling. The Graph then mistakes a Git topology race for a product blocker and creates integration/recovery work.

The final three-way divergence is preserved as evidence:

- canonical EasyBusiness branch: `2ae4045`, with uncommitted category-ontology files from an unfinished node;
- `integrate-operations-regression-v1`: detached `73ea993`;
- `repair-operations-us-financial-language-v1`: detached `43045bf`;
- `repair-primary-action-bars-max-dynamic-typ`: detached `07af30e`;
- `repair-us-category-direct-substitute-ontol` was locally committed as `a2df137` and its push was rejected.

The worktrees must remain untouched during this audit because they are the only durable proof of the split integration state.

## Causal mechanism

### Original-goal leakage into every node

The parent request said to commit and push the round. `nodePrompt` repeats the entire original request to every bounded node. There is no explicit rule saying that only the Graph coordinator may commit or push. A conscientious Sub Agent therefore interprets the global delivery instruction as its own responsibility.

### File scopes do not constrain remote refs

`GraphPlanNodeProposal.writeScopes` limits repository-relative paths. It does not limit Git ref updates, remote pushes, branch creation, stashes, or worktree administration. `GraphNodeAccessPolicy` deliberately retains the parent Full Access selection. Thus a node can satisfy every path check while changing `refs/remotes/origin/main`, the shared integration base for every sibling.

### Coordinator assumes a different transaction model

`GraphWorkspaceCoordinator.integrate` commits local worktree changes when needed, creates a binary patch from `integrationBaseCommit..HEAD`, validates the changed paths, and applies that patch to the primary workspace. This is a patch-based transaction model.

Direct worker pushes create a second commit-based transaction model outside the coordinator. The historical engine had no reconciliation path for this; the current dirty worktree adds `alignCanonicalWorkspaceToPublishedNode`, which attempts to fast-forward the primary branch after a node has already published.

## Audit of the current dirty repair

The new canonical-alignment code is careful in several ways:

- it requires the node commit to be an ancestor of the configured upstream;
- it requires the canonical branch to be fast-forwardable;
- it refuses unrelated dirty paths;
- duplicate local content must match a published tree byte-for-byte;
- it uses `--ff-only` and retains a safety stash if canonical duplicate content exists.

Those checks reduce data loss after an uncontrolled push. They do not restore a single authority.

Open defects remain:

1. Nodes are still allowed to push directly. Reconciliation happens after the remote side effect and cannot protect concurrent siblings or external collaborators observing the intermediate remote state.
2. A published node only has to be an ancestor of the latest upstream. Fast-forwarding to that upstream can absorb other commits that the current node did not review, making node integration causality ambiguous.
3. The coordinator can create a stash and leave it retained rather than restoring or presenting a typed recovery transaction. Even duplicate graph content hidden in a stash is a user-visible state transition that needs an explicit receipt.
4. Conflict recovery launches a fresh Codex turn directly in the primary workspace and treats process exit code zero as successful integration (`GraphLoopEngine.swift:5581-5627`). It has no mechanical path scope, no independent semantic review, no before/after manifest, and no rollback transaction.
5. After a conflict-repair turn, the engine can mark the original node completed without proving that every intended commit/path was integrated and that unrelated primary content stayed byte-identical.
6. Task stop does not own a complete worktree/ref cleanup transaction; multiple task worktrees and branches remain after the task is stopped.
7. Individual nodes repeatedly spend time fetching, comparing, pushing, diagnosing non-fast-forward failures, and documenting remote state. This is orchestration overhead falsely presented as product work.

## Required redesign contract

1. Establish one Git transaction authority per Graph. Workers may edit and test isolated trees but may not push, merge, rebase, stash, switch the canonical branch, or update shared refs.
2. Strip global delivery operations from node prompts and replace them with explicit capability denial. Enforce it mechanically in the worker environment, not only with prose.
3. Represent every node output as an immutable integration candidate: base commit, result commit/tree, exact changed paths, preimage hashes, artifact hashes, test identities, and requirement IDs.
4. Integrate only through a coordinator-owned transaction with preflight, deterministic apply/merge, postimage manifest, independent review, and rollback receipt.
5. Keep the canonical workspace and remote untouched until a complete verified frontier is atomically integrated. Push once from the coordinator after all final gates pass, or pause for user approval if remote mutation was not explicitly authorized.
6. Never run an unconstrained conflict-repair agent in the canonical workspace. Produce an isolated merge worktree with declared inputs and scopes; independently review the resolved tree before advancing the canonical ref.
7. Distinguish `workerCommit`, `integratedCommit`, `publishedCommit`, and `verifiedCommit`. A node cannot be completed merely because one of them exists.
8. On stop, preserve evidence but release active worktree/process leases through a manifest. Archival references must be explicit and cleanup must not depend on a worker's terminal prose.
9. Add concurrency tests with two successful sibling commits, one remote advance, binary files, dirty canonical duplicates, an external collaborator commit, relaunch between apply and state persistence, and rollback after failed final verification.

The machine-readable companion is `GIT_INTEGRATION_SCORECARD.json`.
