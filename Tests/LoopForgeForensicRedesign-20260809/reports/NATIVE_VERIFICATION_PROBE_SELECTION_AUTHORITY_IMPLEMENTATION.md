# Native Verification Probe Selection Authority

Status: **implemented, confirmation-freshness hardened, packaged, and verified through the real native selector; activation-time rehash and full verifier execution remain separate gates**

Recorded: `2026-08-15T19:28:28Z`

## Closed authority gap

`NativeTaskContractAuthoring.prepare` already rejected Auto Graph confirmation unless it received one valid schema-v2 `RequirementVerificationExecutableProbe`. Before this change, the production native composer had no way to select that probe: only test/internal injection could populate it. The UI could therefore display verification requirements but could not reach the exact confirmation boundary.

The production composer now imports one schema-constrained JSON manifest through the native file panel. The manifest may select only an exact executable path, fixed arguments, result mappings, and three bounded resource ceilings. It cannot select transport, environment, output capture, parser implementation, network access, child-process policy, or arbitrary input bindings.

## Authority retained by code

`NativeVerificationProbeSelectionLoader` fixes the remaining contract to:

- local direct-process transport;
- one exact `@loopforge-input:candidate-postimage` binding;
- the minimal kernel environment and its implementation digest;
- the kernel output-capture implementation digest;
- canonical JSON result parser v1 and its implementation digest;
- disabled network, zero child processes, reject-unmatched behavior;
- wall-clock, captured-output, and resident-memory ceilings no wider than the code-owned maxima.

Both manifest and executable are opened with `O_NOFOLLOW`. Imports require stable regular files; the executable must have an execute bit, remain within the bounded import size, and retain the same descriptor/path identity, size, and modification time while it is hashed. The resulting probe retains the exact executable content digest. Immediately before production confirmation, LoopForge now reopens both files through the same loader, requires the complete refreshed selection and all compiled recipe probes to equal the reviewed values, and rejects drift before ratification or enrollment. Display paths are explicitly staging hints, not execution authority. The existing activation compiler must still re-stage and rehash the executable before it can mint live verifier authority.

Unknown JSON fields fail closed, including fields that would attempt to choose network or parser policy. Unknown input tokens, duplicate/non-accepted mappings, malformed paths, symlinks, non-executables, widened resource ceilings, and unstable files also fail closed.

## Native surface

Auto Graph now shows an `Exact postimage verifier` card below source-revision scope. The empty state exposes `Select Verifier Manifest…` with accessibility identifier `select-native-verifier-manifest-button`. A successful selection displays the executable filename and staging path, executable SHA-256, manifest filename, fixed-argv count, and mapping count, with explicit `Change` and `Remove` actions and copy explaining activation-time rehash.

## Verification receipts

- Focused selection suite: 5 tests, 0 failures, 0.017 test seconds.
- Adversarial AppModel confirmation-drift test: 1 test, 0 failures, 1.077 test seconds.
- Pre-package full suite: 829 tests, 8 intentional skips, 0 failures, 59.565 test seconds.
- Package-owned full suite: 829 tests, 8 intentional skips, 0 failures, 55.642 test seconds.
- Signed package snapshot: `cd020030c179bc2dc5580c6f5f3bfa03a53c810d2a768242ca9c6e3b20034c3a`.
- Packaged executable: `ebb1e8a96a93ecf6565607b06ae00ad591340e3727964755f17a2e27dc9ff8b7`.
- Application CDHash: `1f51eb4af0d3728c100b9cd42210de8b5a29287f`.

Computer Use inspected that exact packaged application. A current 1160×768 screenshot retains successful native selection of the exact packaged `KernelSandboxGate` executable with SHA-256 `85b881caa33ae85c2ff98473bcbf8a227bb18fbcc1fad0c781aeadcc91cf2ebd`, one fixed argument, and two result mappings. No estimate, confirmation, enrollment, or task creation was attempted; EasyBusiness was not selected, the application quit, and no packaged process remained. The gate is selector evidence only, not a claimed production verifier.

One otherwise valid manifest presented from `/tmp` was rejected at the stable-manifest boundary. That failed native attempt is retained as excluded evidence and is not generalized into a claim that every file-panel path works. The same bounded manifest retained under the forensic evidence directory imported successfully; unit coverage passes from isolated temporary directories. A later path-normalization investigation may narrow the file-panel `/tmp` behavior.

## Remaining boundary

This closes native selection and confirmation-time freshness, not production verifier execution. Activation-time staging/rehash, Release containment availability or the durable veto, candidate materialization, native runtime result parsing, integration reliance, full visual-matrix evidence, legacy retirement, clean-commit rebuild, commit, and push remain required. Final release is false. EasyBusiness remained read-only at HEAD `2ae40452e6d8661c46db466c43ea40bba3bfab04`.
