# Kernel postimage-verifier containment implementation

Recorded at: `2026-08-12T00:07:40Z`

## Outcome

The activation-linked verifier runtime now contains the exact native verifier process before any parser or verdict authority exists. The journal owner derives the deadline from the attested native process start and the ratified recipe, joins only until that deadline, and terminates the exact owned process group when the wall-clock ceiling expires. The signed sandbox gate installs a per-stream `RLIMIT_FSIZE` ceiling and an `RLIMIT_NPROC` value of one before target execution, so retained stdout/stderr cannot exceed the conservative split quota and the verifier cannot create children.

Completion reads only the journal-owned stdout/stderr files through descriptor-relative, no-follow opens. It validates regular-file identity, link count, mode, size and before/after stability, hashes the exact retained bytes, and constructs a containment receipt bound to the activation, launch, process identity, kernel limits, deadline, exit or termination evidence, output identities, byte counts and digests. The containment receipt and lease release are journaled in one transaction; only then is supervisor state released. Reducer replay rejects missing, cross-wired or altered containment and continues to leave integration `appliedUnverified`.

The ordinary runtime join and termination entry points reject postimage-verifier leases. They must pass through this typed containment path, preventing a caller from bypassing output capture or inventing a release.

## Enforced boundaries

- Journal-derived wall deadline with exact process-group termination on timeout.
- Kernel-enforced maximum retained bytes for each stdout/stderr file through `RLIMIT_FSIZE`.
- Kernel-enforced zero-child verifier policy through `RLIMIT_NPROC = 1`.
- Exact resource limits included in the external process identity and stable identity digest.
- Descriptor-relative output validation, exact retained-byte hashing and fail-red capture classification.
- Atomic containment/release journal transaction and deterministic reducer replay.
- Missing, substituted, tampered and non-verifier containment evidence rejected.

The per-stream limit is intentionally one half of the recipe's combined-output ceiling. That conservative partition guarantees the two retained streams cannot jointly exceed the declared total; it does not dynamically share unused quota between streams.

## Verification

- Focused native gate test: passed. It proved output stopped at the declared file ceiling and a verifier child process was denied.
- Focused journaled verifier test: passed. A real sleeping process exceeded the wall deadline, was terminated by the journal owner, and produced an exact replayable fail-red containment receipt without producing a verification verdict.
- Tamper and omission reducer checks: passed.
- Complete Swift suite: **703 tests executed, 8 intentional environment skips, 0 failures**.
- Release `LoopForge` build: passed.
- Release `KernelSandboxGate` build: passed.
- Source snapshot SHA-256: `78c2aaeec12276f5227e6b563ab739c2453bff06e4b6443772457e0c6586e37b`.
- Release `LoopForge` SHA-256: `7344bdbf76daae5744fe24f8c75ae33a299a607298deff2140fd070f04fce90a`.
- Release `KernelSandboxGate` SHA-256: `21731107c0b85e03933bac526d5f0a705394579e9eb02a7665c950fe49949b99`.
- Diff whitespace check: passed.

## Stop-the-line boundaries retained

This is containment, not verification acceptance.

- Resident-memory enforcement is not implemented. The supervisor reservation is scheduling data, not a truthful per-child RSS ceiling; address-space limits are not being mislabeled as resident-memory enforcement.
- Reconciliation when the exact verifier PID is already absent after a crash is not implemented. The `recoveryProcessAbsent` receipt shape is reserved and validated but no production issuer exists.
- Candidate handoff at spawn is not yet descriptor-atomic.
- No canonical output parser, deterministic oracle, non-forgeable result receipt, latest-red revocation or accepted evidence batch exists.
- No separately activated adversarial reviewer, immutable visual-baseline selection, complete visual diff, integration reliance or native start exists.
- No new current-source package/sign/native walkthrough, commit or push is claimed.
- EasyBusiness remained read-only evidence; its repository was not mutated.

Final acceptance remains false.
