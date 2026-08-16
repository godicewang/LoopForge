import CryptoKit
import Darwin
import Foundation

struct KernelPostimageVerifierCapturePolicy: Sendable {
    static let identityDigest = KernelPostimageVerifierActivationCompiler.digest(
        domain: "kernel-postimage-verifier-capture-v1",
        value: "private-owner-output-files|bounded-stdout-stderr|no-stdin|no-shell"
    )
}

struct KernelPostimageVerifierActivationReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var integrationTransactionID: IntegrationTransactionID
    var applyReceiptID: ReceiptID
    var attemptID: AttemptID
    var requirementID: RequirementID
    var requirementIDs: Set<RequirementID>
    var evidenceRecipeID: EvidenceRecipeID
    var candidateInputBindingID: String
    var candidateArtifactID: String
    /// Non-nil together only for a separately activated independent-review
    /// probe. Ordinary postimage verification must leave all four fields nil.
    var reviewedVerificationReceiptID: ReceiptID? = nil
    var reviewedVerificationEvidenceSetDigest: ContentDigest? = nil
    var reviewEvidenceInputBindingID: String? = nil
    var reviewEvidenceArtifactID: String? = nil
    var verifier: ActorIdentity
    var workerLineageDigest: ContentDigest
    var workspaceRootPath: String
    var workspaceRootPathDigest: ContentDigest
    var sourceRevision: ContentDigest
    var candidateMaterialization: WorkspaceCandidatePostimageMaterializationReceipt
    var executableStaging: KernelExecutableStagingReceipt
    var probeDigest: ContentDigest
    var resolvedArguments: [String]
    var argumentVectorDigest: ContentDigest
    var environmentIdentityDigest: ContentDigest
    var captureIdentityDigest: ContentDigest
    var parser: RequirementVerificationParserContract
    var resourceLimits: RequirementVerificationResourceLimits
    var sourceJournalSequence: UInt64
    var sourceJournalFrameDigest: ContentDigest
    var activatedAt: Date
}

/// Durable activation evidence is not launch authority. This wrapper is the
/// sole command capability accepted by the reducer and has no Release caller
/// initializer.
struct AuthorizedKernelPostimageVerifierActivation: Sendable {
    let receipt: KernelPostimageVerifierActivationReceipt

    private init(_ receipt: KernelPostimageVerifierActivationReceipt) {
        self.receipt = receipt
    }

    fileprivate static func issued(
        _ receipt: KernelPostimageVerifierActivationReceipt
    ) -> AuthorizedKernelPostimageVerifierActivation {
        AuthorizedKernelPostimageVerifierActivation(receipt)
    }

#if DEBUG
    static func testOnly(
        _ receipt: KernelPostimageVerifierActivationReceipt
    ) -> AuthorizedKernelPostimageVerifierActivation {
        AuthorizedKernelPostimageVerifierActivation(receipt)
    }
#endif
}

/// Live postimage-verifier invocation authority. It retains the exact
/// candidate capability, but deliberately exposes no launch or result-minting
/// API. A later runtime must revalidate both staged executable and candidate
/// immediately before journaled admission/spawn.
struct AuthorizedKernelPostimageVerifierInvocation: Sendable {
    let receipt: KernelPostimageVerifierActivationReceipt
    let activationTransaction: JournalTransactionReceipt
    let candidateInput: AuthorizedWorkspaceCandidatePostimageInput

    private init(
        receipt: KernelPostimageVerifierActivationReceipt,
        activationTransaction: JournalTransactionReceipt,
        candidateInput: AuthorizedWorkspaceCandidatePostimageInput
    ) {
        self.receipt = receipt
        self.activationTransaction = activationTransaction
        self.candidateInput = candidateInput
    }

    fileprivate static func activated(
        receipt: KernelPostimageVerifierActivationReceipt,
        activationTransaction: JournalTransactionReceipt,
        candidateInput: AuthorizedWorkspaceCandidatePostimageInput
    ) -> AuthorizedKernelPostimageVerifierInvocation {
        AuthorizedKernelPostimageVerifierInvocation(
            receipt: receipt,
            activationTransaction: activationTransaction,
            candidateInput: candidateInput
        )
    }
}

struct KernelPostimageVerifierLaunchReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var activationJournalFrameDigest: ContentDigest
    var integrationTransactionID: IntegrationTransactionID
    var applyReceiptID: ReceiptID
    var attemptID: AttemptID
    var evidenceRecipeID: EvidenceRecipeID
    var verifier: ActorIdentity
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var bindingReceiptID: ReceiptID
    var executableStaging: KernelExecutableStagingReceipt
    var candidateMaterialization: WorkspaceCandidatePostimageMaterializationReceipt
    var resolvedArguments: [String]
    var argumentVectorDigest: ContentDigest
    var processEnvironment: KernelProcessEnvironmentReceipt
    var processIOFiles: ManagedProcessIOFiles
    var nativeSandbox: KernelNativeSandboxAttestationReceipt
    var parser: RequirementVerificationParserContract
    var resourceLimits: RequirementVerificationResourceLimits
    var launchedAt: Date
}

/// Durable causal evidence that an activated verifier was intentionally
/// stopped before runtime admission. This is not a verification result and
/// cannot satisfy or reject a requirement; it exists so recovery can
/// distinguish a containment veto from a verifier that was never attempted.
struct KernelPostimageVerifierLaunchVetoReceipt: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var id: ReceiptID
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var activationJournalFrameDigest: ContentDigest
    var integrationTransactionID: IntegrationTransactionID
    var applyReceiptID: ReceiptID
    var attemptID: AttemptID
    var evidenceRecipeID: EvidenceRecipeID
    var verifier: ActorIdentity
    var requiredMaximumResidentBytes: UInt64
    var reason: KernelResidentMemoryEnforcementUnavailabilityReason
    var sourceJournalSequence: UInt64
    var observedAt: Date
}

/// Only the journal/process runtime can turn an active invocation and a
/// missing exact containment capability into a reducer command.
struct AuthorizedKernelPostimageVerifierLaunchVeto: Sendable {
    let receipt: KernelPostimageVerifierLaunchVetoReceipt

    private init(receipt: KernelPostimageVerifierLaunchVetoReceipt) {
        self.receipt = receipt
    }

    static func issuedByProcessRuntime(
        receipt: KernelPostimageVerifierLaunchVetoReceipt,
        issuer: JournaledProcessRuntimeCommandIssuer
    ) -> Self {
        Self(receipt: receipt)
    }

#if DEBUG
    static func testOnly(
        receipt: KernelPostimageVerifierLaunchVetoReceipt
    ) -> Self {
        Self(receipt: receipt)
    }
#endif
}

enum KernelPostimageVerifierContainmentDisposition: String, Codable, Hashable, Sendable {
    /// The complete process group exited before the journal-owned wall
    /// deadline and neither output stream exhausted its conservative quota.
    case naturalExit
    /// The journal owner reached the exact wall deadline and joined a late
    /// exit or terminated the still-live process group.
    case wallClockExceeded
    /// RLIMIT_FSIZE delivered SIGXFSZ, or a stream reached the exact
    /// conservative per-stream quota. This is always fail-red downstream.
    case outputLimitExceeded
    /// The process is gone but descriptor-relative retained-output validation
    /// failed. Ownership may be released; verification authority may not.
    case outputCaptureInvalid
    /// Recovery proved the exact journaled PID/start identity absent before a
    /// native exit could be observed. This releases ownership but is always
    /// fail-red and can never become verification authority.
    case recoveryProcessAbsent
    /// Application termination cancelled a still-live verifier before its
    /// deadline. The complete process group exited and ownership may be
    /// released, but this can never become verification authority.
    case runtimeCleanupTermination
}

struct KernelPostimageVerifierOutputFileReceipt: Codable, Hashable, Sendable {
    var fileName: String
    var byteCount: UInt64
    var contentDigest: ContentDigest
}

/// Replayable evidence that the journal owner, rather than a caller or model,
/// enforced the activated verifier's native process containment boundary.
/// This receipt is nested in the exact runtime release event, so release and
/// containment cannot diverge across a crash.
struct KernelPostimageVerifierContainmentReceipt: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var launchReceiptID: ReceiptID
    var bindingReceiptID: ReceiptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var processStartMonotonicNanoseconds: UInt64
    var wallDeadlineMonotonicNanoseconds: UInt64
    var maximumOutputFileBytes: UInt64
    var resourceLimits: RequirementVerificationResourceLimits
    var disposition: KernelPostimageVerifierContainmentDisposition
    var standardOutput: KernelPostimageVerifierOutputFileReceipt?
    var standardError: KernelPostimageVerifierOutputFileReceipt?
    var failureReasonDigest: ContentDigest?
    /// Schema-v2 containment records exactly one parser outcome: either a
    /// capability-originated canonical parse receipt or a fail-red digest.
    /// Optional fields preserve schema-v1 journal decoding.
    var resultParse: KernelPostimageVerifierResultParseReceipt? = nil
    var resultParseFailureDigest: ContentDigest? = nil
    /// Schema-v3 containment additionally records exactly one deterministic
    /// exit/result mapping or a fail-red mapping failure. This is evidence,
    /// never verification authority.
    var resultMapping: KernelPostimageVerifierResultMappingReceipt? = nil
    var resultMappingFailureDigest: ContentDigest? = nil
    /// Schema-v4 containment carries a complete replay-valid result or one
    /// fail-red issuance failure. The result remains distinct from ordinary
    /// verification and integration acceptance.
    var postimageResult: KernelPostimageVerifierResultReceipt? = nil
    var postimageResultFailureDigest: ContentDigest? = nil
    var observedAt: Date
    var observedAtMonotonicNanoseconds: UInt64
}

/// Binds a real native process identity to one exact verifier activation. The
/// process runtime owns the only Release issuer token; durable launch evidence
/// cannot be decoded back into command authority.
struct AuthorizedKernelPostimageVerifierLaunch: Sendable {
    let binding: RuntimeExternalBindingReceipt
    let receipt: KernelPostimageVerifierLaunchReceipt

    private init(
        binding: RuntimeExternalBindingReceipt,
        receipt: KernelPostimageVerifierLaunchReceipt
    ) {
        self.binding = binding
        self.receipt = receipt
    }

    static func issuedByProcessRuntime(
        binding: RuntimeExternalBindingReceipt,
        receipt: KernelPostimageVerifierLaunchReceipt,
        issuer: JournaledProcessRuntimeCommandIssuer
    ) -> AuthorizedKernelPostimageVerifierLaunch {
        AuthorizedKernelPostimageVerifierLaunch(
            binding: binding,
            receipt: receipt
        )
    }

#if DEBUG
    static func testOnly(
        binding: RuntimeExternalBindingReceipt,
        receipt: KernelPostimageVerifierLaunchReceipt
    ) -> AuthorizedKernelPostimageVerifierLaunch {
        AuthorizedKernelPostimageVerifierLaunch(
            binding: binding,
            receipt: receipt
        )
    }
#endif
}

struct KernelPostimageVerifierActivationRequest: Sendable {
    var workspaceRoot: URL
    var integrationTransactionID: IntegrationTransactionID
    var evidenceRecipeID: EvidenceRecipeID
    var verifier: ActorIdentity
    var candidateInput: AuthorizedWorkspaceCandidatePostimageInput
    var receiptID: ReceiptID
    var commandID: RunCommandID
    var activatedAt: Date
    /// Selects independent-review activation. The coordinator resolves this
    /// identifier from current journal state and binds its exact evidence-set
    /// digest into argv; caller-supplied receipt content is never accepted.
    var reviewedVerificationReceiptID: ReceiptID? = nil
}

enum KernelPostimageVerifierActivationError: Error, Equatable {
    case invalidActor
    case verifierNotIndependent
    case invalidRunState
    case integrationNotAwaitingPostimageVerification
    case recipeNotAuthorized
    case unsupportedInputBinding
    case environmentIdentityMismatch
    case captureIdentityMismatch
    case candidateAuthorityMismatch
    case candidateRevalidationFailed
    case stagedExecutableResolutionFailed
    case journalRejected(KernelRejection)
    case journalWriteFailed
    case journalReceiptMismatch
}

enum KernelPostimageVerifierActivationCompiler {
    /// Native spawn changes directory through the held root descriptor before
    /// executing the sandbox launcher, so `.` is object-bound, not path-bound.
    static let candidateInputDescriptorPath = "."

    static func digest(
        domain: String,
        value: String
    ) -> ContentDigest {
        let bytes = Data("\(domain)\0\(value)".utf8)
        return ContentDigest(KernelHex.encode(SHA256.hash(data: bytes)))
    }

    static func probeDigest(
        _ probe: RequirementVerificationExecutableProbe
    ) -> ContentDigest? {
        var data = Data("loopforge.postimage-probe.v2\0".utf8)
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            data.append(Data("\(bytes.count):".utf8))
            data.append(bytes)
        }
        append(String(probe.schemaVersion))
        append(probe.transport.rawValue)
        append(probe.executableContentDigest.rawValue)
        append(String(probe.fixedArguments.count))
        for argument in probe.fixedArguments { append(argument) }
        append(String(probe.inputBindings.count))
        for binding in probe.inputBindings {
            append(binding.id)
            append(binding.kind.rawValue)
            append(binding.artifactID)
            append(binding.argumentToken)
        }
        append(probe.environmentPolicy.rawValue)
        append(probe.environmentIdentityDigest.rawValue)
        append(probe.captureIdentityDigest.rawValue)
        append(probe.parser.id)
        append(String(probe.parser.schemaVersion))
        append(probe.parser.contentDigest.rawValue)
        append(probe.parser.format?.rawValue ?? "")
        append(String(probe.resultMappings.count))
        for mapping in probe.resultMappings {
            append(String(mapping.exitCode))
            append(mapping.parserResultCode)
            append(mapping.outcome.rawValue)
        }
        append(probe.unmatchedOutcome.rawValue)
        append(probe.networkPolicy.rawValue)
        append(String(probe.resourceLimits.maximumWallClockSeconds))
        append(String(probe.resourceLimits.maximumCapturedOutputBytes))
        append(String(probe.resourceLimits.maximumResidentBytes))
        append(String(probe.resourceLimits.maximumChildProcesses))
        return ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }

    static func receipt(
        _ receipt: KernelPostimageVerifierActivationReceipt,
        matches probe: RequirementVerificationExecutableProbe
    ) -> Bool {
        guard let probeDigest = probeDigest(probe),
              probe.inputBindings.count == 1 || probe.inputBindings.count == 2,
              let binding = probe.inputBindings.first(where: {
                $0.kind == .candidatePostimage
              }),
              probe.inputBindings.filter({
                $0.kind == .candidatePostimage
              }).count == 1 else {
            return false
        }
        let reviewBindings = probe.inputBindings.filter {
            $0.kind == .verificationEvidenceDigest
        }
        let isReview = receipt.reviewedVerificationReceiptID != nil
        guard (isReview && reviewBindings.count == 1
                && probe.inputBindings.count == 2
                && receipt.reviewedVerificationEvidenceSetDigest != nil)
                || (!isReview && reviewBindings.isEmpty
                    && probe.inputBindings.count == 1
                    && receipt.reviewedVerificationEvidenceSetDigest == nil),
              let reviewBinding = reviewBindings.first ?? (isReview ? nil : binding)
                else {
            return false
        }
        let expectedArguments = probe.fixedArguments.map {
            if $0 == binding.argumentToken {
                return candidateInputDescriptorPath
            }
            if isReview && $0 == reviewBinding.argumentToken {
                return receipt.reviewedVerificationEvidenceSetDigest!.rawValue
            }
            return $0
        }
        return receipt.probeDigest == probeDigest
            && receipt.candidateInputBindingID == binding.id
            && receipt.candidateArtifactID == binding.artifactID
            && receipt.reviewEvidenceInputBindingID ==
                (isReview ? reviewBinding.id : nil)
            && receipt.reviewEvidenceArtifactID ==
                (isReview ? reviewBinding.artifactID : nil)
            && receipt.executableStaging.contentDigest ==
                probe.executableContentDigest
            && receipt.resolvedArguments == expectedArguments
            && receipt.argumentVectorDigest ==
                KernelProviderInvocationCompiler.argumentVectorDigest(
                    expectedArguments
                )
            && receipt.environmentIdentityDigest ==
                probe.environmentIdentityDigest
            && receipt.captureIdentityDigest == probe.captureIdentityDigest
            && receipt.parser == probe.parser
            && receipt.resourceLimits == probe.resourceLimits
            && receipt.workspaceRootPath.hasPrefix("/")
            && receipt.workspaceRootPathDigest ==
                WorkspaceRepositoryIndexer.canonicalRootDigest(URL(
                    fileURLWithPath: receipt.workspaceRootPath,
                    isDirectory: true
                ))
            && receipt.sourceRevision ==
                receipt.candidateMaterialization.sourceRevision
            && receipt.applyReceiptID ==
                receipt.candidateMaterialization.applyReceiptID
            && validSHA256(receipt.sourceJournalFrameDigest)
    }

    static func validSHA256(_ digest: ContentDigest) -> Bool {
        let bytes = digest.rawValue.utf8
        return bytes.count == 64 && bytes.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66)
        }
    }

    static func launch(
        _ launch: KernelPostimageVerifierLaunchReceipt,
        matches activation: KernelPostimageVerifierActivationReceipt,
        binding: RuntimeExternalBindingReceipt
    ) -> Bool {
        let sandbox = launch.nativeSandbox.authorization
        let identity = binding.identity
        return launch.runID == activation.runID
            && launch.activationReceiptID == activation.id
            && validSHA256(launch.activationJournalFrameDigest)
            && launch.integrationTransactionID ==
                activation.integrationTransactionID
            && launch.applyReceiptID == activation.applyReceiptID
            && launch.attemptID == activation.attemptID
            && launch.evidenceRecipeID == activation.evidenceRecipeID
            && launch.verifier == activation.verifier
            && launch.resourceID == binding.resourceID
            && launch.leaseID == binding.leaseID
            && launch.bindingReceiptID == binding.id
            && launch.executableStaging.stagedExecutablePath ==
                activation.executableStaging.stagedExecutablePath
            && launch.executableStaging.contentDigest ==
                activation.executableStaging.contentDigest
            && launch.executableStaging.byteCount ==
                activation.executableStaging.byteCount
            && launch.executableStaging.deviceID ==
                activation.executableStaging.deviceID
            && launch.executableStaging.inode ==
                activation.executableStaging.inode
            && launch.candidateMaterialization ==
                activation.candidateMaterialization
            && launch.resolvedArguments == activation.resolvedArguments
            && launch.argumentVectorDigest == activation.argumentVectorDigest
            && launch.processEnvironment.environmentDigest ==
                activation.environmentIdentityDigest
            && launch.processEnvironment.policy == .minimalKernelAllowlist
            && launch.processIOFiles.standardInputFileName == nil
            && launch.processIOFiles.standardOutputFileName != nil
            && launch.processIOFiles.standardErrorFileName != nil
            && sandbox.sandbox == .readOnly
            && sandbox.networkPolicy == .disabled
            && sandbox.nativeAttestationRequired
            && sandbox.journalWritesDefaultDenied
            && launch.nativeSandbox.processID == identity.processID
            && launch.nativeSandbox.nativeSandboxCheckResult == 1
            && launch.nativeSandbox.gateObservedStopped
            && launch.nativeSandbox.targetExecHandshakeSucceeded
            && launch.nativeSandbox.candidateWorkingDirectory ==
                KernelCandidateWorkingDirectoryAttestationReceipt(
                    binding: .posixSpawnFileActionsFchdir,
                    deviceID: activation.candidateMaterialization.deviceID,
                    inode: activation.candidateMaterialization.inode
                )
            && identity.executableContentDigest ==
                activation.executableStaging.contentDigest
            && identity.environmentContentDigest ==
                activation.environmentIdentityDigest
            && identity.argumentVectorContentDigest ==
                activation.argumentVectorDigest
            && identity.nativeSandboxAttestation == launch.nativeSandbox
            && identity.kernelResourceLimits ==
                ManagedProcessKernelResourceLimits(
                    maximumOutputFileBytes:
                        activation.resourceLimits.maximumCapturedOutputBytes / 2,
                    maximumProcessCount: 1
                )
            && launch.parser == activation.parser
            && launch.resourceLimits == activation.resourceLimits
    }

    static func specification(
        _ specification: ManagedProcessSpecification,
        matches invocation: AuthorizedKernelPostimageVerifierInvocation
    ) -> Bool {
        let receipt = invocation.receipt
        guard let io = specification.ioFiles else { return false }
        return specification.executablePath ==
                receipt.executableStaging.stagedExecutablePath
            && specification.arguments == receipt.resolvedArguments
            && specification.environment ==
                KernelProcessEnvironmentAuthorizer.minimalEnvironment
            && io.standardInputFileName == nil
            && io.standardOutputFileName != nil
            && io.standardErrorFileName != nil
            && specification.expectedExecutableContentDigest ==
                receipt.executableStaging.contentDigest
            && specification.expectedEnvironmentContentDigest ==
                receipt.environmentIdentityDigest
            && specification.expectedArgumentVectorContentDigest ==
                receipt.argumentVectorDigest
            && specification.expectedProviderPromptArtifact == nil
            && specification.nativeSandbox?.receipt.sandbox == .readOnly
            && specification.nativeSandbox?.receipt.networkPolicy == .disabled
            && specification.kernelResourceLimits ==
                ManagedProcessKernelResourceLimits(
                    maximumOutputFileBytes:
                        receipt.resourceLimits.maximumCapturedOutputBytes / 2,
                    maximumProcessCount: 1
                )
    }

    static func containment(
        _ containment: KernelPostimageVerifierContainmentReceipt,
        activation: KernelPostimageVerifierActivationReceipt,
        probe: RequirementVerificationExecutableProbe,
        matches launch: KernelPostimageVerifierLaunchReceipt,
        binding: RuntimeExternalBindingReceipt,
        release: RuntimeReleaseOutcomeReceipt
    ) -> Bool {
        guard (containment.schemaVersion == 1
                || containment.schemaVersion == 2
                || containment.schemaVersion == 3
                || containment.schemaVersion == 4),
              KernelPostimageVerifierActivationCompiler.receipt(
                activation,
                matches: probe
              ),
              launch.activationReceiptID == activation.id,
              containment.runID == launch.runID,
              containment.activationReceiptID == launch.activationReceiptID,
              containment.launchReceiptID == launch.id,
              containment.bindingReceiptID == launch.bindingReceiptID,
              containment.resourceID == launch.resourceID,
              containment.leaseID == launch.leaseID,
              containment.resourceLimits == launch.resourceLimits,
              containment.maximumOutputFileBytes ==
                launch.resourceLimits.maximumCapturedOutputBytes / 2,
              containment.observedAt == release.observedAt,
              containment.observedAtMonotonicNanoseconds ==
                release.observedAtMonotonicNanoseconds,
              binding.id == launch.bindingReceiptID,
              binding.resourceID == launch.resourceID,
              binding.leaseID == launch.leaseID,
              binding.identity.processStartMonotonicNanoseconds ==
                containment.processStartMonotonicNanoseconds,
              containment.wallDeadlineMonotonicNanoseconds >=
                containment.processStartMonotonicNanoseconds,
              case .released = release.outcome else {
            return false
        }
        let stdoutName = launch.processIOFiles.standardOutputFileName
        let stderrName = launch.processIOFiles.standardErrorFileName
        let outputIsValid: Bool
        if let stdout = containment.standardOutput,
           let stderr = containment.standardError {
            let combined = stdout.byteCount.addingReportingOverflow(
                stderr.byteCount
            )
            outputIsValid = !combined.overflow
                && stdout.fileName == stdoutName
                && stderr.fileName == stderrName
                && stdout.byteCount <= containment.maximumOutputFileBytes
                && stderr.byteCount <= containment.maximumOutputFileBytes
                && combined.partialValue <=
                    containment.resourceLimits.maximumCapturedOutputBytes
                && validSHA256(stdout.contentDigest)
                && validSHA256(stderr.contentDigest)
                && containment.failureReasonDigest == nil
        } else {
            outputIsValid = containment.standardOutput == nil
                && containment.standardError == nil
                && (containment.disposition == .outputCaptureInvalid
                    || containment.disposition == .recoveryProcessAbsent)
                && containment.failureReasonDigest.map(validSHA256) == true
        }
        guard outputIsValid else { return false }

        if containment.schemaVersion == 1 {
            guard containment.resultParse == nil,
                  containment.resultParseFailureDigest == nil else {
                return false
            }
        } else if let parse = containment.resultParse,
                  let stdout = containment.standardOutput,
                  let stderr = containment.standardError {
            let expectation = KernelPostimageVerifierResultParseExpectation(
                runID: launch.runID,
                activationReceiptID: launch.activationReceiptID,
                launchReceiptID: launch.id,
                resourceID: launch.resourceID,
                leaseID: launch.leaseID,
                parser: launch.parser,
                standardOutput: stdout,
                standardError: stderr
            )
            guard containment.resultParseFailureDigest == nil,
                  KernelPostimageVerifierResultParser.receipt(
                    parse,
                    matches: expectation
                  ) else {
                return false
            }
        } else {
            guard containment.resultParse == nil,
                  containment.resultParseFailureDigest.map(
                    validSHA256
                  ) == true else {
                return false
            }
        }

        if containment.schemaVersion <= 2 {
            guard containment.resultMapping == nil,
                  containment.resultMappingFailureDigest == nil else {
                return false
            }
        } else {
            let nativeExit = release.managedProcessExit
            let expectedMapping: KernelPostimageVerifierResultMappingReceipt?
            if containment.disposition == .naturalExit,
               release.managedProcessTermination == nil,
               let nativeExit,
               nativeExit.terminationSignal == nil,
               let exitCode = nativeExit.exitCode,
               let parse = containment.resultParse {
                expectedMapping =
                    KernelPostimageVerifierResultMapper.expectedReceipt(
                        probe: probe,
                        nativeExitCode: exitCode,
                        parse: parse
                    )
            } else {
                expectedMapping = nil
            }
            if let expectedMapping {
                guard containment.resultMapping == expectedMapping,
                      containment.resultMappingFailureDigest == nil else {
                    return false
                }
            } else {
                guard containment.resultMapping == nil,
                      containment.resultMappingFailureDigest.map(
                        validSHA256
                      ) == true else {
                    return false
                }
            }
        }

        guard validResultAuthority(
            containment,
            activation: activation,
            launch: launch,
            release: release
        ) else { return false }

        let nativeExit = release.managedProcessTermination?.exit
            ?? release.managedProcessExit
        if containment.disposition == .recoveryProcessAbsent {
            return nativeExit == nil
                && release.managedProcessTermination == nil
                && release.managedProcessExit == nil
                && containment.observedAtMonotonicNanoseconds >=
                    containment.processStartMonotonicNanoseconds
        }
        guard let nativeExit,
              nativeExit.handle.runID == launch.runID,
              nativeExit.handle.resourceID == launch.resourceID,
              nativeExit.handle.leaseID == launch.leaseID else {
            return false
        }
        let quotaReached = containment.maximumOutputFileBytes > 0
            && [containment.standardOutput, containment.standardError]
                .compactMap { $0 }
                .contains(where: {
                    $0.byteCount == containment.maximumOutputFileBytes
                })
        switch containment.disposition {
        case .naturalExit:
            return release.managedProcessExit != nil
                && release.managedProcessTermination == nil
                && nativeExit.observedAtMonotonicNanoseconds <=
                    containment.wallDeadlineMonotonicNanoseconds
                && nativeExit.terminationSignal != SIGXFSZ
                && !quotaReached
        case .wallClockExceeded:
            return containment.observedAtMonotonicNanoseconds >=
                    containment.wallDeadlineMonotonicNanoseconds
                && (release.managedProcessTermination != nil
                    || nativeExit.observedAtMonotonicNanoseconds >
                        containment.wallDeadlineMonotonicNanoseconds)
        case .outputLimitExceeded:
            return nativeExit.terminationSignal == SIGXFSZ || quotaReached
        case .outputCaptureInvalid:
            return true
        case .recoveryProcessAbsent:
            return false
        case .runtimeCleanupTermination:
            return release.managedProcessTermination != nil
                && release.managedProcessExit == nil
        }
    }

    /// Kept out of the already-large containment predicate to avoid a Swift
    /// runtime metadata-instantiation overflow observed when decoding the
    /// nested optional verifier result types inside one monolithic generic
    /// expression.
    private static func validResultAuthority(
        _ containment: KernelPostimageVerifierContainmentReceipt,
        activation: KernelPostimageVerifierActivationReceipt,
        launch: KernelPostimageVerifierLaunchReceipt,
        release: RuntimeReleaseOutcomeReceipt
    ) -> Bool {
        if containment.schemaVersion <= 3 {
            return containment.postimageResult == nil
                && containment.postimageResultFailureDigest == nil
        }
        guard let mapping = containment.resultMapping,
              let parse = containment.resultParse,
              let stdout = containment.standardOutput,
              let stderr = containment.standardError else {
            return containment.postimageResult == nil
                && containment.postimageResultFailureDigest.map(
                    validSHA256
                ) == true
        }
        guard let expected =
                KernelPostimageVerifierResultAuthority.expectedReceipt(
                    activation: activation,
                    launch: launch,
                    releaseReceiptID: release.id,
                    standardOutput: stdout,
                    standardError: stderr,
                    parse: parse,
                    mapping: mapping,
                    completedAt: containment.observedAt
                ) else { return false }
        return containment.postimageResult == expected
            && containment.postimageResultFailureDigest == nil
    }
}

/// Journals a separately identified postimage-verifier activation over one
/// exact applied-but-unverified integration transaction. It stages no verdict;
/// the separately typed journal runtime alone may consume its invocation.
actor KernelPostimageVerifierActivationCoordinator {
    private let journal: RunJournal

    init(journal: RunJournal) {
        self.journal = journal
    }

    func activate(
        _ request: KernelPostimageVerifierActivationRequest
    ) async throws -> AuthorizedKernelPostimageVerifierInvocation {
        guard !request.verifier.id.rawValue.isEmpty,
              !request.verifier.role.isEmpty,
              !request.verifier.lineageDigest.rawValue.isEmpty else {
            throw KernelPostimageVerifierActivationError.invalidActor
        }
        let state = await journal.state
        guard state.runID == journal.runID,
              state.phase == .evaluating,
              let attempt = state.attempts.values.first(where: {
                $0.id == state.integrationTransactions[
                    request.integrationTransactionID
                ]?.proposal.attemptID
              }),
              attempt.disposition?.canEnterVerification == true else {
            throw KernelPostimageVerifierActivationError.invalidRunState
        }
        guard request.verifier.lineageDigest != attempt.worker.lineageDigest else {
            throw KernelPostimageVerifierActivationError.verifierNotIndependent
        }
        guard let integration = state.integrationTransactions[
            request.integrationTransactionID
        ],
        integration.phase == .appliedUnverified,
        let apply = integration.applyReceipt,
        request.verifier.lineageDigest != apply.executor.lineageDigest else {
            throw KernelPostimageVerifierActivationError
                .integrationNotAwaitingPostimageVerification
        }
        guard let contract = state.contract,
              let recipes = contract.requirementEvidenceRecipes,
              let recipe = recipes.first(where: {
                $0.id == request.evidenceRecipeID
              }),
              recipes.filter({ $0.id == request.evidenceRecipeID }).count == 1,
              recipe.requiresIndependentLineage,
              attempt.requirementIDs.contains(recipe.requirementID),
              let probe = recipe.executableProbe,
              probe.schemaVersion == 2,
              probe.parser.format == .canonicalJSONResultV1,
              probe.parser.contentDigest == probe.parser.format?
                .implementationIdentityDigest,
              probe.validationIssues().isEmpty,
              let probeDigest = KernelPostimageVerifierActivationCompiler
                .probeDigest(probe) else {
            throw KernelPostimageVerifierActivationError.recipeNotAuthorized
        }
        guard let binding = probe.inputBindings.first(where: {
                $0.kind == .candidatePostimage
              }),
              probe.inputBindings.filter({
                $0.kind == .candidatePostimage
              }).count == 1 else {
            throw KernelPostimageVerifierActivationError.unsupportedInputBinding
        }
        let reviewBindings = probe.inputBindings.filter {
            $0.kind == .verificationEvidenceDigest
        }
        let reviewedVerification: VerificationReceipt?
        let reviewedEvidenceDigest: ContentDigest?
        if let reviewedID = request.reviewedVerificationReceiptID {
            guard probe.inputBindings.count == 2,
                  reviewBindings.count == 1,
                  let target = state.verificationReceipts[reviewedID],
                  target.result == .accepted,
                  target.attemptID == attempt.id,
                  target.requirementIDs == [recipe.requirementID],
                  target.sourceRevision ==
                    request.candidateInput.receipt.sourceRevision,
                  let batch = target.postimageEvidenceBatch,
                  state.verificationIsEffective(
                    target,
                    requirementID: recipe.requirementID
                  ),
                  let targetResult = state.runtimeReleaseReceipts.values
                    .compactMap({
                        $0.postimageVerifierContainment?.postimageResult
                    })
                    .first(where: { $0.id == batch.postimageResultID }),
                  targetResult.evidenceSetDigest ==
                    batch.postimageResultEvidenceSetDigest,
                  targetResult.integrationTransactionID ==
                    request.integrationTransactionID,
                  targetResult.applyReceiptID == apply.id,
                  targetResult.sourceRevision ==
                    request.candidateInput.receipt.sourceRevision,
                  targetResult.verifier.lineageDigest !=
                    request.verifier.lineageDigest else {
                throw KernelPostimageVerifierActivationError
                    .unsupportedInputBinding
            }
            reviewedVerification = target
            reviewedEvidenceDigest = batch.evidenceSetDigest
        } else {
            guard probe.inputBindings.count == 1,
                  reviewBindings.isEmpty else {
                throw KernelPostimageVerifierActivationError
                    .unsupportedInputBinding
            }
            reviewedVerification = nil
            reviewedEvidenceDigest = nil
        }
        let expectedEnvironment = KernelProcessEnvironmentAuthorizer
            .environmentDigest(KernelProcessEnvironmentAuthorizer.minimalEnvironment)
        guard probe.environmentIdentityDigest == expectedEnvironment else {
            throw KernelPostimageVerifierActivationError
                .environmentIdentityMismatch
        }
        guard probe.captureIdentityDigest ==
                KernelPostimageVerifierCapturePolicy.identityDigest else {
            throw KernelPostimageVerifierActivationError.captureIdentityMismatch
        }

        let workspace = request.workspaceRoot.standardizedFileURL
            .resolvingSymlinksInPath()
        let latest = try await journal
            .latestAcceptedWorkspaceCandidatePostimageAttestation(
                workspaceID: request.candidateInput.receipt.workspaceID,
                root: workspace
            )
        guard case .accepted(let attestation) = latest,
              attestation.applyReceiptID == apply.id,
              attestation.applyReceiptID ==
                request.candidateInput.receipt.applyReceiptID,
              attestation.candidatePostimage.sourceRevision ==
                request.candidateInput.receipt.sourceRevision,
              attestation.candidatePostimage.capturePolicyDigest ==
                request.candidateInput.receipt.capturePolicyDigest,
              attestation.journalTransaction.frameDigest ==
                request.candidateInput.receipt
                    .attestationJournalFrameDigest else {
            throw KernelPostimageVerifierActivationError
                .candidateAuthorityMismatch
        }
        do {
            _ = try WorkspaceCandidatePostimageMaterializer().revalidate(
                request.candidateInput
            )
        } catch {
            throw KernelPostimageVerifierActivationError
                .candidateRevalidationFailed
        }

        let staging: KernelExecutableStagingReceipt
        do {
            staging = try KernelExecutableStager().resolveStaged(
                expectedDigest: probe.executableContentDigest,
                runDirectory: journal.runDirectory
            )
        } catch {
            throw KernelPostimageVerifierActivationError
                .stagedExecutableResolutionFailed
        }
        let priorActivations = (state.postimageVerifierActivationReceipts ?? [:])
            .values.filter {
                $0.integrationTransactionID == request.integrationTransactionID
                    && $0.evidenceRecipeID == request.evidenceRecipeID
            }
        if let prior = priorActivations.first {
            let replayCandidateInput: AuthorizedWorkspaceCandidatePostimageInput
            do {
                replayCandidateInput = try
                    WorkspaceCandidatePostimageMaterializer().replay(
                        request.candidateInput,
                        matching: prior.candidateMaterialization
                    )
            } catch {
                throw KernelPostimageVerifierActivationError
                    .candidateRevalidationFailed
            }
            let replayHead = await journal.headSnapshot()
            guard replayHead.sequence == state.sequence,
                  priorActivations.count == 1,
                  prior.id == request.receiptID,
                  prior.runID == state.runID,
                  prior.integrationTransactionID ==
                    request.integrationTransactionID,
                  prior.applyReceiptID == apply.id,
                  prior.attemptID == attempt.id,
                  prior.requirementID == recipe.requirementID,
                  prior.requirementIDs == [recipe.requirementID],
                  prior.verifier == request.verifier,
                  prior.reviewedVerificationReceiptID ==
                    reviewedVerification?.id,
                  prior.reviewedVerificationEvidenceSetDigest ==
                    reviewedEvidenceDigest,
                  prior.workspaceRootPath == workspace.path,
                  prior.sourceRevision ==
                    request.candidateInput.receipt.sourceRevision,
                  prior.executableStaging.sourceExecutablePath ==
                    staging.sourceExecutablePath,
                  prior.executableStaging.stagedExecutablePath ==
                    staging.stagedExecutablePath,
                  prior.executableStaging.contentDigest ==
                    staging.contentDigest,
                  prior.executableStaging.byteCount == staging.byteCount,
                  prior.executableStaging.deviceID == staging.deviceID,
                  prior.executableStaging.inode == staging.inode,
                  prior.activatedAt == request.activatedAt,
                  KernelPostimageVerifierActivationCompiler.receipt(
                    prior,
                    matches: probe
                  ),
                  !(state.postimageVerifierLaunchReceipts ?? [:]).values
                    .contains(where: {
                        $0.activationReceiptID == prior.id
                    }),
                  let transaction = await journal.transactionReceipt(
                    commandID: request.commandID
                  ),
                  await journal.postimageVerifierActivationReceipt(
                    transaction: transaction
                  ) == prior else {
                throw KernelPostimageVerifierActivationError.invalidRunState
            }
            return .activated(
                receipt: prior,
                activationTransaction: transaction,
                candidateInput: replayCandidateInput
            )
        }
        let resolvedArguments = probe.fixedArguments.map {
            if $0 == binding.argumentToken {
                return KernelPostimageVerifierActivationCompiler
                    .candidateInputDescriptorPath
            }
            if let reviewBinding = reviewBindings.first,
               $0 == reviewBinding.argumentToken,
               let reviewedEvidenceDigest {
                return reviewedEvidenceDigest.rawValue
            }
            return $0
        }
        let journalHead = await journal.headSnapshot()
        guard journalHead.sequence == state.sequence,
              let sourceFrameDigest = journalHead.frameDigest else {
            throw KernelPostimageVerifierActivationError.invalidRunState
        }
        let receipt = KernelPostimageVerifierActivationReceipt(
            id: request.receiptID,
            runID: state.runID,
            integrationTransactionID: request.integrationTransactionID,
            applyReceiptID: apply.id,
            attemptID: attempt.id,
            requirementID: recipe.requirementID,
            requirementIDs: [recipe.requirementID],
            evidenceRecipeID: recipe.id,
            candidateInputBindingID: binding.id,
            candidateArtifactID: binding.artifactID,
            reviewedVerificationReceiptID: reviewedVerification?.id,
            reviewedVerificationEvidenceSetDigest: reviewedEvidenceDigest,
            reviewEvidenceInputBindingID: reviewBindings.first?.id,
            reviewEvidenceArtifactID: reviewBindings.first?.artifactID,
            verifier: request.verifier,
            workerLineageDigest: attempt.worker.lineageDigest,
            workspaceRootPath: workspace.path,
            workspaceRootPathDigest:
                WorkspaceRepositoryIndexer.canonicalRootDigest(workspace),
            sourceRevision: request.candidateInput.receipt.sourceRevision,
            candidateMaterialization: request.candidateInput.receipt,
            executableStaging: staging,
            probeDigest: probeDigest,
            resolvedArguments: resolvedArguments,
            argumentVectorDigest: KernelProviderInvocationCompiler
                .argumentVectorDigest(resolvedArguments),
            environmentIdentityDigest: probe.environmentIdentityDigest,
            captureIdentityDigest: probe.captureIdentityDigest,
            parser: probe.parser,
            resourceLimits: probe.resourceLimits,
            sourceJournalSequence: journalHead.sequence,
            sourceJournalFrameDigest: sourceFrameDigest,
            activatedAt: request.activatedAt
        )
        let transaction: JournalTransactionReceipt
        do {
            transaction = try await journal.transactAtCurrentSequence(
                .activatePostimageVerifier(.issued(receipt)),
                commandID: request.commandID,
                issuedAt: request.activatedAt,
                actor: request.verifier
            )
        } catch RunJournalError.reducerRejected(let rejection) {
            throw KernelPostimageVerifierActivationError
                .journalRejected(rejection)
        } catch {
            throw KernelPostimageVerifierActivationError.journalWriteFailed
        }
        guard !transaction.duplicate,
              await journal.postimageVerifierActivationReceipt(
                transaction: transaction
              ) == receipt else {
            throw KernelPostimageVerifierActivationError
                .journalReceiptMismatch
        }
        return .activated(
            receipt: receipt,
            activationTransaction: transaction,
            candidateInput: request.candidateInput
        )
    }
}
