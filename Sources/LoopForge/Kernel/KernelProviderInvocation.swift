import CryptoKit
import Darwin
import Dispatch
import Foundation
import Security

/// Retained identity for a prompt already created inside the journal-owned run
/// directory. Prompt bytes are deliberately absent: the invocation compiler
/// is authority and provenance plumbing, not a second prompt persistence path.
struct KernelProviderPromptArtifactReceipt: Codable, Hashable, Sendable {
    var runID: KernelRunID
    var attemptID: AttemptID
    var fileName: String
    var contentDigest: ContentDigest
    var byteCount: UInt64
    var deviceID: UInt64
    var inode: UInt64
}

/// Non-serializable authority for a prompt created through an exclusive,
/// descriptor-relative write in the journal-owned run directory. A decoded
/// receipt is evidence only and cannot be promoted back into launch authority.
struct AuthorizedKernelProviderPromptArtifact: Sendable {
    let receipt: KernelProviderPromptArtifactReceipt

    fileprivate init(receipt: KernelProviderPromptArtifactReceipt) {
        self.receipt = receipt
    }

#if DEBUG
    static func testOnly(
        receipt: KernelProviderPromptArtifactReceipt
    ) -> AuthorizedKernelProviderPromptArtifact {
        AuthorizedKernelProviderPromptArtifact(receipt: receipt)
    }
#endif
}

enum KernelProviderPromptArtifactError: Error, Equatable {
    case invalidPrompt
    case invalidFileName
    case invalidRunDirectory
    case createFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case durabilityFailed(errno: Int32)
    case metadataMismatch
}

/// Creates immutable prompt input without pathname redirection, overwrite, or
/// a second persistence channel. The returned inode identity is later retained
/// in the provider invocation receipt and rechecked by the runtime transport.
struct KernelProviderPromptArtifactIssuer: Sendable {
    static let maximumPromptBytes = 16 * 1_024 * 1_024

    func issue(
        prompt: Data,
        fileName: String,
        journalRunDirectory: URL,
        executionProof: JournaledKernelExecutionProof
    ) throws -> AuthorizedKernelProviderPromptArtifact {
        guard !prompt.isEmpty, prompt.count <= Self.maximumPromptBytes else {
            throw KernelProviderPromptArtifactError.invalidPrompt
        }
        guard KernelProviderInvocationCompiler.validFileName(fileName) else {
            throw KernelProviderPromptArtifactError.invalidFileName
        }
        let directoryDescriptor = Darwin.open(
            journalRunDirectory.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard directoryDescriptor >= 0 else {
            throw KernelProviderPromptArtifactError.invalidRunDirectory
        }
        defer { _ = Darwin.close(directoryDescriptor) }

        var directoryStatus = stat()
        guard Darwin.fstat(directoryDescriptor, &directoryStatus) == 0,
              directoryStatus.st_mode & S_IFMT == S_IFDIR else {
            throw KernelProviderPromptArtifactError.invalidRunDirectory
        }
        let descriptor = fileName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                0o600
            )
        }
        guard descriptor >= 0 else {
            throw KernelProviderPromptArtifactError.createFailed(errno: errno)
        }
        var committed = false
        defer {
            _ = Darwin.close(descriptor)
            if !committed {
                _ = fileName.withCString {
                    Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }

        do {
            try prompt.withUnsafeBytes { try Self.writeAll($0, to: descriptor) }
        } catch {
            throw error
        }
        guard Darwin.fchmod(descriptor, 0o400) == 0,
              Darwin.fsync(descriptor) == 0 else {
            throw KernelProviderPromptArtifactError.durabilityFailed(errno: errno)
        }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1,
              status.st_size == prompt.count else {
            throw KernelProviderPromptArtifactError.metadataMismatch
        }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw KernelProviderPromptArtifactError.durabilityFailed(errno: errno)
        }
        committed = true
        return AuthorizedKernelProviderPromptArtifact(
            receipt: KernelProviderPromptArtifactReceipt(
                runID: executionProof.runID,
                attemptID: executionProof.attemptID,
                fileName: fileName,
                contentDigest: Self.digest(prompt),
                byteCount: UInt64(prompt.count),
                deviceID: UInt64(bitPattern: Int64(status.st_dev)),
                inode: UInt64(status.st_ino)
            )
        )
    }

    private static func writeAll(
        _ buffer: UnsafeRawBufferPointer,
        to descriptor: Int32
    ) throws {
        var written = 0
        while written < buffer.count {
            let result = Darwin.write(
                descriptor,
                buffer.baseAddress?.advanced(by: written),
                buffer.count - written
            )
            if result > 0 {
                written += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                throw KernelProviderPromptArtifactError.writeFailed(errno: errno)
            }
        }
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}

/// Safe, credential-free evidence for the exact provider-harness protocol.
/// Every argument is retained because later launch authorization must compare
/// the caller's argv byte-for-byte instead of trusting provider labels.
struct KernelProviderInvocationReceipt: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var protocolVersion: Int
    var runID: KernelRunID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var strategyFingerprint: StrategyFingerprint
    var activationActor: ActorIdentity
    var executionProfile: KernelAgentExecutionProfile
    var preApplyCandidateIsolation:
        WorkspacePreApplyCandidateIsolationReceipt? = nil
    var promptArtifact: KernelProviderPromptArtifactReceipt
    var requestNonce: ContentDigest
    var credentialMode: KernelProviderCredentialMode
    var promptDescriptor: Int32
    /// Fixed inherited descriptor carrying the post-compilation invocation
    /// digest. Optional only so historical decoded evidence fails validation
    /// instead of failing to decode; every newly authorized receipt sets it.
    var invocationContextDescriptor: Int32? = nil
    var credentialDescriptor: Int32?
    var hiddenFanOutEnabled: Bool
    var arguments: [String]
    var argumentVectorDigest: ContentDigest
    var invocationDigest: ContentDigest
}

/// Canonical non-secret launch context created only after the invocation
/// digest exists. Keeping this value off argv avoids the digest/argv cycle:
/// argv binds the fixed descriptor, while this exact payload binds the final
/// digest and request nonce delivered through that descriptor.
struct KernelProviderInvocationContextPayload: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var runID: KernelRunID
    var attemptID: AttemptID
    var invocationDigest: ContentDigest
    var requestNonce: ContentDigest
}

/// Credential-free evidence that the exact canonical context bytes were
/// staged into the provider's inherited pipe before native spawn. It does not
/// claim that untrusted provider code consumed or honored those bytes.
struct KernelProviderInvocationContextTransportReceipt:
    Codable, Hashable, Sendable
{
    var schemaVersion: Int
    var targetDescriptor: Int32
    var contentDigest: ContentDigest
    var byteCount: UInt64
    var stagedAtMonotonicNanoseconds: UInt64

    static func issue(
        invocation: KernelProviderInvocationReceipt,
        stagedAtMonotonicNanoseconds: UInt64
    ) -> KernelProviderInvocationContextTransportReceipt? {
        guard let targetDescriptor = invocation.invocationContextDescriptor,
              let bytes = payloadBytes(for: invocation) else {
            return nil
        }
        return KernelProviderInvocationContextTransportReceipt(
            schemaVersion: 1,
            targetDescriptor: targetDescriptor,
            contentDigest: digest(bytes),
            byteCount: UInt64(bytes.count),
            stagedAtMonotonicNanoseconds: stagedAtMonotonicNanoseconds
        )
    }

    func isValid(for invocation: KernelProviderInvocationReceipt) -> Bool {
        guard schemaVersion == 1,
              targetDescriptor == invocation.invocationContextDescriptor,
              targetDescriptor ==
                KernelProviderInvocationCompiler.invocationContextDescriptor,
              byteCount > 0,
              byteCount <= UInt64(Self.maximumPayloadBytes),
              let bytes = Self.payloadBytes(for: invocation) else {
            return false
        }
        return byteCount == UInt64(bytes.count)
            && contentDigest == Self.digest(bytes)
    }

    static func payloadBytes(
        for invocation: KernelProviderInvocationReceipt
    ) -> Data? {
        guard invocation.invocationContextDescriptor ==
                KernelProviderInvocationCompiler.invocationContextDescriptor
        else {
            return nil
        }
        let payload = KernelProviderInvocationContextPayload(
            schemaVersion: 1,
            runID: invocation.runID,
            attemptID: invocation.attemptID,
            invocationDigest: invocation.invocationDigest,
            requestNonce: invocation.requestNonce
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var bytes = try? encoder.encode(payload) else { return nil }
        bytes.append(0x0a)
        guard bytes.count <= maximumPayloadBytes else { return nil }
        return bytes
    }

    static let maximumPayloadBytes = 4 * 1_024

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(
            SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }
}

/// Credential-free, replayable evidence that one exact provider invocation
/// crossed the native launch boundary and was bound to one owned process
/// lease. This is evidence rather than launch authority: decoded receipts can
/// be inspected and replayed, but cannot recreate either non-serializable
/// invocation authority or an ephemeral secret capability.
struct KernelProviderLaunchReceipt: Codable, Hashable, Sendable {
    var id: ReceiptID
    var schemaVersion: Int
    var runID: KernelRunID
    var attemptID: AttemptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var bindingReceiptID: ReceiptID
    var invocation: KernelProviderInvocationReceipt
    var invocationContextTransport:
        KernelProviderInvocationContextTransportReceipt? = nil
    var secretDelivery: KernelProviderSecretDeliveryReceipt?
    /// Exact in-process ceilings installed by KernelSandboxGate before the
    /// harness exec. Optional only so historical schema-v1 evidence remains
    /// decodable; current launch evidence rejects an absent value.
    var resourceLimits: ManagedProcessKernelResourceLimits? = nil
    var observedAtMonotonicNanoseconds: UInt64
    var receiptDigest: ContentDigest

    fileprivate static func issue(
        id: ReceiptID,
        binding: RuntimeExternalBindingReceipt,
        invocation: KernelProviderInvocationReceipt,
        invocationContextTransport:
            KernelProviderInvocationContextTransportReceipt,
        secretDelivery: KernelProviderSecretDeliveryReceipt?
    ) -> KernelProviderLaunchReceipt {
        let material = KernelProviderLaunchDigestMaterial(
            schemaVersion: 2,
            runID: binding.runID,
            attemptID: invocation.attemptID,
            resourceID: binding.resourceID,
            leaseID: binding.leaseID,
            bindingReceiptID: binding.id,
            invocation: invocation,
            invocationContextTransport: invocationContextTransport,
            secretDelivery: secretDelivery,
            resourceLimits: binding.identity.kernelResourceLimits,
            observedAtMonotonicNanoseconds:
                binding.observedAtMonotonicNanoseconds
        )
        return KernelProviderLaunchReceipt(
            id: id,
            schemaVersion: material.schemaVersion,
            runID: material.runID,
            attemptID: material.attemptID,
            resourceID: material.resourceID,
            leaseID: material.leaseID,
            bindingReceiptID: material.bindingReceiptID,
            invocation: material.invocation,
            invocationContextTransport:
                material.invocationContextTransport,
            secretDelivery: material.secretDelivery,
            resourceLimits: material.resourceLimits,
            observedAtMonotonicNanoseconds:
                material.observedAtMonotonicNanoseconds,
            receiptDigest: Self.digest(material)
        )
    }

    func isValid(binding: RuntimeExternalBindingReceipt) -> Bool {
        guard schemaVersion == 2,
              runID == binding.runID,
              attemptID == invocation.attemptID,
              resourceID == binding.resourceID,
              leaseID == binding.leaseID,
              bindingReceiptID == binding.id,
              binding.accepted,
              observedAtMonotonicNanoseconds ==
                binding.observedAtMonotonicNanoseconds,
              invocation.runID == runID,
              invocation.promptArtifact.runID == runID,
              invocation.promptArtifact.attemptID == attemptID,
              binding.identity.executableContentDigest ==
                invocation.executionProfile.executableContentDigest,
              binding.identity.argumentVectorContentDigest ==
                invocation.argumentVectorDigest,
              let resourceLimits,
              resourceLimits ==
                KernelProviderInvocationCompiler.requiredResourceLimits,
              binding.identity.kernelResourceLimits == resourceLimits,
              let attestation =
                binding.identity.nativeSandboxAttestation,
              attestation.processID == binding.identity.processID,
              attestation.authorization.sandbox ==
                invocation.executionProfile.sandbox,
              attestation.authorization.networkPolicy ==
                invocation.executionProfile.networkPolicy,
              attestation.nativeSandboxCheckResult == 1,
              attestation.gateObservedStopped,
              attestation.targetExecHandshakeSucceeded,
              attestation.observedAtMonotonicNanoseconds <=
                observedAtMonotonicNanoseconds,
              let invocationContextTransport,
              invocationContextTransport.isValid(for: invocation),
              invocationContextTransport.stagedAtMonotonicNanoseconds <=
                observedAtMonotonicNanoseconds,
              KernelProviderInvocationCompiler.receiptIsValid(invocation) else {
            return false
        }
        switch invocation.credentialMode {
        case .none:
            guard invocation.credentialDescriptor == nil,
                  secretDelivery == nil else { return false }
        case .opaqueProviderSecret:
            let expectedBinding = KernelProviderSecretBinding(
                runID: runID,
                attemptID: attemptID,
                providerReference:
                    invocation.executionProfile.providerReference,
                invocationDigest: invocation.invocationDigest
            )
            guard invocation.credentialDescriptor ==
                    KernelProviderInvocationCompiler.credentialDescriptor,
                  let secretDelivery,
                  !secretDelivery.capabilityID.isEmpty,
                  secretDelivery.binding == expectedBinding,
                  secretDelivery.targetDescriptor ==
                    invocation.credentialDescriptor,
                  secretDelivery.deliveredAtMonotonicNanoseconds <=
                    observedAtMonotonicNanoseconds else {
                return false
            }
        }
        let material = KernelProviderLaunchDigestMaterial(
            schemaVersion: schemaVersion,
            runID: runID,
            attemptID: attemptID,
            resourceID: resourceID,
            leaseID: leaseID,
            bindingReceiptID: bindingReceiptID,
            invocation: invocation,
            invocationContextTransport: invocationContextTransport,
            secretDelivery: secretDelivery,
            resourceLimits: resourceLimits,
            observedAtMonotonicNanoseconds:
                observedAtMonotonicNanoseconds
        )
        return receiptDigest == Self.digest(material)
    }

    private static func digest(
        _ material: KernelProviderLaunchDigestMaterial
    ) -> ContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else {
            return ContentDigest("")
        }
        return ContentDigest(
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

/// Non-serializable authority minted only after the runtime has both the
/// original invocation capability and an accepted native binding. A decoded
/// `KernelProviderLaunchReceipt` is deliberately unable to recreate this
/// command authority.
struct AuthorizedKernelProviderLaunch: Sendable {
    let binding: RuntimeExternalBindingReceipt
    let receipt: KernelProviderLaunchReceipt

    fileprivate init(
        binding: RuntimeExternalBindingReceipt,
        receipt: KernelProviderLaunchReceipt
    ) {
        self.binding = binding
        self.receipt = receipt
    }

#if DEBUG
    static func testOnly(
        binding: RuntimeExternalBindingReceipt,
        receipt: KernelProviderLaunchReceipt
    ) -> AuthorizedKernelProviderLaunch {
        AuthorizedKernelProviderLaunch(binding: binding, receipt: receipt)
    }
#endif
}

enum KernelProviderLaunchEvidenceError: Error, Equatable {
    case invalidEvidence
}

struct KernelProviderLaunchEvidenceIssuer: Sendable {
    func issue(
        id: ReceiptID,
        binding: RuntimeExternalBindingReceipt,
        invocation authorization: AuthorizedKernelProviderInvocation,
        invocationContextTransport:
            KernelProviderInvocationContextTransportReceipt,
        secretDelivery: KernelProviderSecretDeliveryReceipt?
    ) throws -> AuthorizedKernelProviderLaunch {
        let receipt = KernelProviderLaunchReceipt.issue(
            id: id,
            binding: binding,
            invocation: authorization.receipt,
            invocationContextTransport: invocationContextTransport,
            secretDelivery: secretDelivery
        )
        guard receipt.isValid(binding: binding) else {
            throw KernelProviderLaunchEvidenceError.invalidEvidence
        }
        return AuthorizedKernelProviderLaunch(
            binding: binding,
            receipt: receipt
        )
    }
}

private struct KernelProviderLaunchDigestMaterial: Codable {
    var schemaVersion: Int
    var runID: KernelRunID
    var attemptID: AttemptID
    var resourceID: OwnedResourceID
    var leaseID: ResourceLeaseID
    var bindingReceiptID: ReceiptID
    var invocation: KernelProviderInvocationReceipt
    var invocationContextTransport:
        KernelProviderInvocationContextTransportReceipt
    var secretDelivery: KernelProviderSecretDeliveryReceipt?
    var resourceLimits: ManagedProcessKernelResourceLimits?
    var observedAtMonotonicNanoseconds: UInt64
}

/// Non-serializable launch authority. Re-encoding a receipt cannot manufacture
/// an authorized invocation because only this file can create the wrapper.
struct AuthorizedKernelProviderInvocation: Sendable {
    let receipt: KernelProviderInvocationReceipt

    fileprivate init(receipt: KernelProviderInvocationReceipt) {
        self.receipt = receipt
    }
}

enum KernelProviderInvocationAuthorizationError: Error, Equatable {
    case invalidIdentity
    case unsupportedProviderProtocol
    case productiveProviderArchitectureUnavailable
    case invalidPromptArtifact
    case invalidRequestNonce
    case remoteProviderRequiresNetwork
    case unsupportedPluginAuthority
    case unsupportedEnvironmentAuthority
    case invalidCredentialAuthority
    case invalidArgumentVector
    case specificationMismatch
}

/// Profile-level authority that is still absent before an invocation can be
/// compiled. This assessment is deliberately narrower than launch readiness:
/// it does not claim that a prompt, nonce, transport, secret capability,
/// sandbox, lease, or process binding exists.
enum KernelProviderInvocationProfileBlocker: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case executionIdentityInvalid
    case providerHarnessProtocolUnavailable
    case providerHarnessProtocolObsolete
    /// Schema-v1 raw value retained for decoded readiness evidence. The
    /// semantic name is intentionally stronger: installing or relabeling a
    /// binary cannot establish the missing isolation and ratification product.
    case productiveProviderArchitectureUnavailable =
        "providerHarnessProductiveBackendUnavailable"
    case remoteProviderNetworkAuthorityMissing
    case userInstalledPluginAuthorityUnsupported
    case declaredEnvironmentAuthorityUnsupported
    case credentialAuthorityInvalid

    var displaySummary: String {
        switch self {
        case .executionIdentityInvalid:
            return "The worker provider, model, or executable SHA-256 identity is invalid."
        case .providerHarnessProtocolUnavailable:
            return "The exact worker executable is not ratified as a LoopForge Provider Harness V2."
        case .providerHarnessProtocolObsolete:
            return "The exact worker executable uses the retired Provider Harness V1 protocol."
        case .productiveProviderArchitectureUnavailable:
            return "The exact V2 harness transport is ratified, but this package has no separately isolated and ratified productive-provider architecture; installing or relabeling a binary cannot authorize execution."
        case .remoteProviderNetworkAuthorityMissing:
            return "Remote provider execution requires both an enabled network policy and a ratified kernel.network-access capability grant."
        case .userInstalledPluginAuthorityUnsupported:
            return "User-installed plugins have no exact manifest and capability issuer."
        case .declaredEnvironmentAuthorityUnsupported:
            return "Declared worker environment access has no exact per-name/value authority issuer."
        case .credentialAuthorityInvalid:
            return "The worker credential mode does not retain one exact valid credential authority."
        }
    }
}

struct KernelProviderInvocationProfileReadinessAssessment:
    Codable, Equatable, Sendable
{
    var schemaVersion: Int
    var workerExecutionProfile: KernelAgentExecutionProfile
    var authorityCapabilityIDs: [String]
    var blockers: [KernelProviderInvocationProfileBlocker]

    var canCompileProviderInvocation: Bool { blockers.isEmpty }
}

/// Compiles one provider-neutral harness protocol. It never calls legacy
/// `CodexRunner`, reads host configuration, selects an endpoint, or accepts an
/// argv fragment from a model/caller. Provider implementations may differ
/// behind the ratified executable digest, but their authority surface is exact.
struct KernelProviderInvocationCompiler: Sendable {
    static let protocolVersion = 2
    static let promptDescriptor: Int32 = STDIN_FILENO
    static let invocationContextDescriptor: Int32 = 196
    static let credentialDescriptor: Int32 = 197
    /// The canonical worker parser retains at most 16 MiB on stdout. Applying
    /// the same per-file native ceiling before exec also bounds stderr and any
    /// unexpected extra writes. A process count of one makes the harness the
    /// complete owned process tree and mechanically enforces no hidden fan-out.
    static let requiredResourceLimits = ManagedProcessKernelResourceLimits(
        maximumOutputFileBytes: UInt64(
            KernelWorkerResultParserLimits.production.maximumStdoutBytes
        ),
        maximumProcessCount: 1
    )

    static func profileReadiness(
        _ profile: KernelAgentExecutionProfile,
        authorityCeiling: KernelAuthorityCeiling
    ) -> KernelProviderInvocationProfileReadinessAssessment {
        var blockers: [KernelProviderInvocationProfileBlocker] = []
        if !validIdentity(profile.providerReference)
            || !validIdentity(profile.modelID)
            || !(profile.reasoningEffort.map(validIdentity) ?? true)
            || !validDigest(profile.executableContentDigest) {
            blockers.append(.executionIdentityInvalid)
        }
        switch profile.providerProtocol {
        case .unavailable:
            blockers.append(.providerHarnessProtocolUnavailable)
        case .loopForgeProviderHarnessV1:
            blockers.append(.providerHarnessProtocolObsolete)
        case .loopForgeProviderHarnessV2:
            if profile.providerHarnessMode != .productive {
                blockers.append(
                    .productiveProviderArchitectureUnavailable
                )
            }
        }
        if profile.provider != .local,
           profile.networkPolicy != .enabled
            || !authorityCeiling.capabilityIDs.contains(
                KernelExecutionProfile.networkCapabilityID
            ) {
            blockers.append(.remoteProviderNetworkAuthorityMissing)
        }
        if profile.pluginPolicy != .disabled {
            blockers.append(.userInstalledPluginAuthorityUnsupported)
        }
        if profile.environmentPolicy != .minimalKernelAllowlist {
            blockers.append(.declaredEnvironmentAuthorityUnsupported)
        }
        switch profile.credentialMode {
        case .none:
            if profile.credentialReference != nil {
                blockers.append(.credentialAuthorityInvalid)
            }
        case .opaqueProviderSecret:
            if profile.credentialReference?.isValid != true {
                blockers.append(.credentialAuthorityInvalid)
            }
        }
        return KernelProviderInvocationProfileReadinessAssessment(
            schemaVersion: 1,
            workerExecutionProfile: profile,
            authorityCapabilityIDs:
                authorityCeiling.capabilityIDs.sorted(),
            blockers: blockers
        )
    }

    func authorize(
        executionProof: JournaledKernelExecutionProof,
        promptArtifact authorization: AuthorizedKernelProviderPromptArtifact,
        requestNonce: ContentDigest
    ) throws -> AuthorizedKernelProviderInvocation {
        let promptArtifact = authorization.receipt
        try validateExecution(
            executionProof: executionProof,
            requestNonce: requestNonce
        )
        let profile = executionProof.workerExecutionProfile
        guard promptArtifact.runID == executionProof.runID,
              promptArtifact.attemptID == executionProof.attemptID,
              Self.validFileName(promptArtifact.fileName),
              Self.validDigest(promptArtifact.contentDigest),
              promptArtifact.byteCount > 0,
              promptArtifact.byteCount <= UInt64(KernelProviderPromptArtifactIssuer.maximumPromptBytes),
              promptArtifact.inode > 0 else {
            throw KernelProviderInvocationAuthorizationError.invalidPromptArtifact
        }
        let credentialMode = profile.credentialMode
        let credentialDescriptor = credentialMode == .opaqueProviderSecret
            ? Self.credentialDescriptor
            : nil
        let arguments = Self.arguments(
            profile: profile,
            promptArtifact: promptArtifact,
            requestNonce: requestNonce,
            credentialMode: credentialMode
        )
        guard arguments.allSatisfy(Self.validArgument) else {
            throw KernelProviderInvocationAuthorizationError.invalidArgumentVector
        }
        let argumentVectorDigest = Self.argumentVectorDigest(arguments)
        let material = KernelProviderInvocationDigestMaterial(
            schemaVersion: 1,
            protocolVersion: Self.protocolVersion,
            runID: executionProof.runID,
            attemptID: executionProof.attemptID,
            nodeID: executionProof.nodeID,
            strategyFingerprint: executionProof.strategyFingerprint,
            activationActor: executionProof.activationActor,
            executionProfile: profile,
            preApplyCandidateIsolation:
                executionProof.preApplyCandidateIsolation,
            promptArtifact: promptArtifact,
            requestNonce: requestNonce,
            credentialMode: credentialMode,
            promptDescriptor: Self.promptDescriptor,
            invocationContextDescriptor: Self.invocationContextDescriptor,
            credentialDescriptor: credentialDescriptor,
            hiddenFanOutEnabled: false,
            arguments: arguments,
            argumentVectorDigest: argumentVectorDigest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(material) else {
            throw KernelProviderInvocationAuthorizationError.invalidArgumentVector
        }
        let receipt = KernelProviderInvocationReceipt(
            schemaVersion: material.schemaVersion,
            protocolVersion: material.protocolVersion,
            runID: material.runID,
            attemptID: material.attemptID,
            nodeID: material.nodeID,
            strategyFingerprint: material.strategyFingerprint,
            activationActor: material.activationActor,
            executionProfile: material.executionProfile,
            preApplyCandidateIsolation:
                material.preApplyCandidateIsolation,
            promptArtifact: material.promptArtifact,
            requestNonce: material.requestNonce,
            credentialMode: material.credentialMode,
            promptDescriptor: material.promptDescriptor,
            invocationContextDescriptor:
                material.invocationContextDescriptor,
            credentialDescriptor: material.credentialDescriptor,
            hiddenFanOutEnabled: material.hiddenFanOutEnabled,
            arguments: material.arguments,
            argumentVectorDigest: material.argumentVectorDigest,
            invocationDigest: Self.digest(encoded)
        )
        return AuthorizedKernelProviderInvocation(receipt: receipt)
    }

    /// Fails before prompt materialization when the exact activated execution
    /// profile cannot enter the provider protocol. This keeps a rejected
    /// network, plugin, sandbox, or executable identity from leaving an
    /// orphaned immutable prompt in the journal-owned directory.
    func validateExecution(
        executionProof: JournaledKernelExecutionProof,
        requestNonce: ContentDigest
    ) throws {
        let profile = executionProof.workerExecutionProfile
        guard Self.validIdentity(profile.providerReference),
              Self.validIdentity(profile.modelID),
              profile.reasoningEffort.map(Self.validIdentity) ?? true,
              Self.validDigest(profile.executableContentDigest) else {
            throw KernelProviderInvocationAuthorizationError.invalidIdentity
        }
        guard profile.providerProtocol == .loopForgeProviderHarnessV2 else {
            throw KernelProviderInvocationAuthorizationError
                .unsupportedProviderProtocol
        }
        guard profile.providerHarnessMode == .productive else {
            throw KernelProviderInvocationAuthorizationError
                .productiveProviderArchitectureUnavailable
        }
        guard executionProof.preApplyCandidateIsolation == nil
                || profile.sandbox == .workspaceOnly else {
            throw KernelProviderInvocationAuthorizationError.invalidIdentity
        }
        guard Self.validDigest(requestNonce) else {
            throw KernelProviderInvocationAuthorizationError.invalidRequestNonce
        }
        if profile.provider != .local, profile.networkPolicy != .enabled {
            throw KernelProviderInvocationAuthorizationError.remoteProviderRequiresNetwork
        }
        switch profile.credentialMode {
        case .none:
            guard profile.credentialReference == nil else {
                throw KernelProviderInvocationAuthorizationError
                    .invalidCredentialAuthority
            }
        case .opaqueProviderSecret:
            guard profile.credentialReference?.isValid == true else {
                throw KernelProviderInvocationAuthorizationError
                    .invalidCredentialAuthority
            }
        }
        // User-installed plugins are represented in the contract, but there is
        // no scoped plugin manifest/grant issuer yet. Never translate that broad
        // label into executable authority.
        guard profile.pluginPolicy == .disabled else {
            throw KernelProviderInvocationAuthorizationError.unsupportedPluginAuthority
        }
        // The contract can reserve a declared allowlist, but no typed
        // per-name/value issuer exists yet. Reject before prompt materialization
        // instead of leaving an immutable orphan that can never launch.
        guard profile.environmentPolicy == .minimalKernelAllowlist else {
            throw KernelProviderInvocationAuthorizationError
                .unsupportedEnvironmentAuthority
        }
    }

    /// Future runtime composition calls this before admission. In particular,
    /// caller environment and arbitrary argv remain invalid even if an
    /// executable digest and native sandbox are otherwise correct.
    func validate(
        specification: ManagedProcessSpecification,
        against authorization: AuthorizedKernelProviderInvocation
    ) throws {
        let receipt = authorization.receipt
        guard specification.arguments == receipt.arguments,
              specification.environment.isEmpty,
              specification.expectedExecutableContentDigest == nil
                || specification.expectedExecutableContentDigest ==
                    receipt.executionProfile.executableContentDigest,
              specification.expectedArgumentVectorContentDigest == nil
                || specification.expectedArgumentVectorContentDigest ==
                    receipt.argumentVectorDigest,
              specification.expectedEnvironmentContentDigest == nil,
              specification.expectedProviderPromptArtifact == nil,
              specification.nativeSandbox == nil,
              specification.kernelResourceLimits == nil,
              specification.executableArgumentZero == nil,
              let io = specification.ioFiles,
              io.standardInputFileName == receipt.promptArtifact.fileName,
              io.standardOutputFileName != nil,
              io.standardErrorFileName != nil else {
            throw KernelProviderInvocationAuthorizationError.specificationMismatch
        }
    }

    /// Rechecks the post-authorization transport specification immediately
    /// before spawn. Kernel-injected staging/environment/sandbox fields may be
    /// present, but provider argv, executable identity, prompt, and their
    /// digests must now be mandatory rather than optional.
    func validateTransport(
        specification: ManagedProcessSpecification,
        against authorization: AuthorizedKernelProviderInvocation
    ) throws {
        let receipt = authorization.receipt
        guard specification.arguments == receipt.arguments,
              specification.expectedExecutableContentDigest ==
                receipt.executionProfile.executableContentDigest,
              specification.expectedArgumentVectorContentDigest ==
                receipt.argumentVectorDigest,
              specification.expectedProviderPromptArtifact ==
                receipt.promptArtifact,
              specification.kernelResourceLimits ==
                Self.requiredResourceLimits,
              specification.nativeSandbox.map(
                KernelNativeSandboxAuthorizer.configurationIsValid
              ) == true,
              let io = specification.ioFiles,
              io.standardInputFileName == receipt.promptArtifact.fileName,
              io.standardOutputFileName != nil,
              io.standardErrorFileName != nil else {
            throw KernelProviderInvocationAuthorizationError.specificationMismatch
        }
    }

    /// Recomputes every deterministic invocation field during reducer replay.
    /// This prevents a structurally valid decoded receipt from becoming launch
    /// evidence after any argument, profile, prompt, nonce, or digest change.
    static func receiptIsValid(_ receipt: KernelProviderInvocationReceipt) -> Bool {
        let isolationBindingIsValid = receipt.preApplyCandidateIsolation.map {
            receipt.executionProfile.sandbox == .workspaceOnly
                && $0.validationIssues().isEmpty
                && $0.runID == receipt.runID
                && $0.attemptID == receipt.attemptID
                && $0.nodeID == receipt.nodeID
                && $0.strategyFingerprint == receipt.strategyFingerprint
        } ?? true
        guard receipt.schemaVersion == 1,
              receipt.protocolVersion == protocolVersion,
              validIdentity(receipt.executionProfile.providerReference),
              validIdentity(receipt.executionProfile.modelID),
              receipt.executionProfile.reasoningEffort.map(validIdentity) ?? true,
              validDigest(receipt.executionProfile.executableContentDigest),
              receipt.promptArtifact.runID == receipt.runID,
              receipt.promptArtifact.attemptID == receipt.attemptID,
              validFileName(receipt.promptArtifact.fileName),
              validDigest(receipt.promptArtifact.contentDigest),
              receipt.promptArtifact.byteCount > 0,
              receipt.promptArtifact.byteCount <= UInt64(
                KernelProviderPromptArtifactIssuer.maximumPromptBytes
              ),
              receipt.promptArtifact.inode > 0,
              validDigest(receipt.requestNonce),
              receipt.executionProfile.providerProtocol
                == .loopForgeProviderHarnessV2,
              receipt.executionProfile.providerHarnessMode == .productive,
              receipt.executionProfile.pluginPolicy == .disabled,
              receipt.executionProfile.environmentPolicy
                == .minimalKernelAllowlist,
              receipt.executionProfile.provider == .local ||
                receipt.executionProfile.networkPolicy == .enabled,
              isolationBindingIsValid,
              receipt.promptDescriptor == promptDescriptor,
              receipt.invocationContextDescriptor ==
                invocationContextDescriptor,
              !receipt.hiddenFanOutEnabled else {
            return false
        }
        let expectedCredentialMode = receipt.executionProfile.credentialMode
        let credentialAuthorityIsValid: Bool
        switch expectedCredentialMode {
        case .none:
            credentialAuthorityIsValid =
                receipt.executionProfile.credentialReference == nil
        case .opaqueProviderSecret:
            credentialAuthorityIsValid =
                receipt.executionProfile.credentialReference?.isValid == true
        }
        guard receipt.credentialMode == expectedCredentialMode,
              credentialAuthorityIsValid,
              receipt.credentialDescriptor == (
                expectedCredentialMode == .opaqueProviderSecret
                    ? credentialDescriptor
                    : nil
              ) else {
            return false
        }
        let expectedArguments = arguments(
            profile: receipt.executionProfile,
            promptArtifact: receipt.promptArtifact,
            requestNonce: receipt.requestNonce,
            credentialMode: receipt.credentialMode
        )
        guard receipt.arguments == expectedArguments,
              receipt.arguments.allSatisfy(validArgument),
              receipt.argumentVectorDigest ==
                argumentVectorDigest(expectedArguments) else {
            return false
        }
        let material = KernelProviderInvocationDigestMaterial(
            schemaVersion: receipt.schemaVersion,
            protocolVersion: receipt.protocolVersion,
            runID: receipt.runID,
            attemptID: receipt.attemptID,
            nodeID: receipt.nodeID,
            strategyFingerprint: receipt.strategyFingerprint,
            activationActor: receipt.activationActor,
            executionProfile: receipt.executionProfile,
            preApplyCandidateIsolation:
                receipt.preApplyCandidateIsolation,
            promptArtifact: receipt.promptArtifact,
            requestNonce: receipt.requestNonce,
            credentialMode: receipt.credentialMode,
            promptDescriptor: receipt.promptDescriptor,
            invocationContextDescriptor:
                receipt.invocationContextDescriptor
                ?? -1,
            credentialDescriptor: receipt.credentialDescriptor,
            hiddenFanOutEnabled: receipt.hiddenFanOutEnabled,
            arguments: receipt.arguments,
            argumentVectorDigest: receipt.argumentVectorDigest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else { return false }
        return receipt.invocationDigest == digest(data)
    }

    private static func arguments(
        profile: KernelAgentExecutionProfile,
        promptArtifact: KernelProviderPromptArtifactReceipt,
        requestNonce: ContentDigest,
        credentialMode: KernelProviderCredentialMode
    ) -> [String] {
        [
            "--loopforge-provider-protocol", String(protocolVersion),
            "--provider", profile.provider.rawValue,
            "--provider-reference", profile.providerReference,
            "--model", profile.modelID,
            "--reasoning-effort", profile.reasoningEffort ?? "default",
            "--sandbox", profile.sandbox.rawValue,
            "--network", profile.networkPolicy.rawValue,
            "--plugins", "disabled",
            "--hidden-fan-out", "disabled",
            "--invocation-context-fd", String(invocationContextDescriptor),
            "--prompt-fd", String(promptDescriptor),
            "--prompt-digest", promptArtifact.contentDigest.rawValue,
            "--prompt-bytes", String(promptArtifact.byteCount),
            "--request-nonce", requestNonce.rawValue,
            "--credential-mode", credentialMode.rawValue,
            "--credential-fd", credentialMode == .opaqueProviderSecret
                ? String(credentialDescriptor)
                : "none"
        ]
    }

    private static func validIdentity(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.contains("\0")
    }

    private static func validArgument(_ value: String) -> Bool {
        !value.contains("\0")
    }

    static func argumentVectorDigest(_ arguments: [String]) -> ContentDigest {
        digestLengthPrefixed(arguments.map { Data($0.utf8) })
    }

    static func validFileName(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && value.utf8.count <= 255
            && !value.contains("/")
            && !value.contains("\0")
    }

    private static func validDigest(_ digest: ContentDigest) -> Bool {
        let bytes = digest.rawValue.utf8
        return bytes.count == 64 && bytes.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func digestLengthPrefixed(_ values: [Data]) -> ContentDigest {
        var hasher = SHA256()
        for value in values {
            var count = UInt64(value.count).bigEndian
            withUnsafeBytes(of: &count) { hasher.update(bufferPointer: $0) }
            hasher.update(data: value)
        }
        return ContentDigest(KernelHex.encode(hasher.finalize()))
    }

    private static func digest(_ data: Data) -> ContentDigest {
        ContentDigest(KernelHex.encode(SHA256.hash(data: data)))
    }
}

private struct KernelProviderInvocationDigestMaterial: Codable {
    var schemaVersion: Int
    var protocolVersion: Int
    var runID: KernelRunID
    var attemptID: AttemptID
    var nodeID: KernelNodeID
    var strategyFingerprint: StrategyFingerprint
    var activationActor: ActorIdentity
    var executionProfile: KernelAgentExecutionProfile
    var preApplyCandidateIsolation:
        WorkspacePreApplyCandidateIsolationReceipt?
    var promptArtifact: KernelProviderPromptArtifactReceipt
    var requestNonce: ContentDigest
    var credentialMode: KernelProviderCredentialMode
    var promptDescriptor: Int32
    var invocationContextDescriptor: Int32
    var credentialDescriptor: Int32?
    var hiddenFanOutEnabled: Bool
    var arguments: [String]
    var argumentVectorDigest: ContentDigest
}

struct KernelProviderSecretBinding: Codable, Hashable, Sendable {
    var runID: KernelRunID
    var attemptID: AttemptID
    var providerReference: String
    var invocationDigest: ContentDigest
}

/// Safe metadata; it proves only that an ephemeral capability was issued. It
/// contains no secret bytes, hash, environment-variable name, or disk path.
struct KernelProviderSecretCapabilityMetadata: Codable, Hashable, Sendable {
    var capabilityID: String
    var binding: KernelProviderSecretBinding
    var issuedAtMonotonicNanoseconds: UInt64
    var expiresAtMonotonicNanoseconds: UInt64
}

/// Credential-free proof that one exact capability was consumed into the
/// fixed provider descriptor. It intentionally excludes secret bytes, size,
/// digest, environment key, and disk location.
struct KernelProviderSecretDeliveryReceipt: Codable, Hashable, Sendable {
    var capabilityID: String
    var binding: KernelProviderSecretBinding
    var targetDescriptor: Int32
    var deliveredAtMonotonicNanoseconds: UInt64
}

enum KernelProviderSecretCapabilityError: Error, Equatable {
    case invalidSecret
    case invalidLifetime
    case credentialNotRequired
    case credentialReferenceMissing
    case credentialUnavailable(status: Int32)
    case executionBindingMismatch
    case bindingMismatch
    case expired
    case alreadyConsumed
    case invalidDescriptor
    case deliveryFailed(errno: Int32)
}

/// Opaque, single-use, memory-only provider authority. The only operation is a
/// length-prefixed descriptor delivery; callers cannot ask for the secret,
/// place it in argv/environment, encode it, or recover it after a restart.
final class KernelProviderSecretCapability: @unchecked Sendable {
    let metadata: KernelProviderSecretCapabilityMetadata

    private let lock = NSLock()
    private var bytes: [UInt8]
    private var consumed = false

    fileprivate init(
        metadata: KernelProviderSecretCapabilityMetadata,
        bytes: [UInt8]
    ) {
        self.metadata = metadata
        self.bytes = bytes
    }

    deinit {
        erase()
    }

    func deliver(
        to descriptor: Int32,
        targetDescriptor: Int32? = nil,
        for binding: KernelProviderSecretBinding,
        nowMonotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) throws -> KernelProviderSecretDeliveryReceipt {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else {
            throw KernelProviderSecretCapabilityError.invalidDescriptor
        }
        guard binding == metadata.binding else {
            throw KernelProviderSecretCapabilityError.bindingMismatch
        }
        guard !consumed else {
            throw KernelProviderSecretCapabilityError.alreadyConsumed
        }
        guard nowMonotonicNanoseconds <= metadata.expiresAtMonotonicNanoseconds else {
            consumed = true
            eraseLocked()
            throw KernelProviderSecretCapabilityError.expired
        }
        consumed = true
        _ = Darwin.fcntl(descriptor, F_SETNOSIGPIPE, 1)
        var count = UInt64(bytes.count).bigEndian
        do {
            try withUnsafeBytes(of: &count) { buffer in
                try Self.writeAll(buffer, to: descriptor)
            }
            try bytes.withUnsafeBytes { buffer in
                try Self.writeAll(buffer, to: descriptor)
            }
        } catch {
            eraseLocked()
            throw error
        }
        eraseLocked()
        return KernelProviderSecretDeliveryReceipt(
            capabilityID: metadata.capabilityID,
            binding: binding,
            targetDescriptor: targetDescriptor ?? descriptor,
            deliveredAtMonotonicNanoseconds: nowMonotonicNanoseconds
        )
    }

    private func erase() {
        lock.lock()
        defer { lock.unlock() }
        eraseLocked()
    }

    private func eraseLocked() {
        bytes.withUnsafeMutableBytes { buffer in
            if let base = buffer.baseAddress, buffer.count > 0 {
                _ = Darwin.memset(base, 0, buffer.count)
            }
        }
        bytes.removeAll(keepingCapacity: false)
    }

    private static func writeAll(
        _ buffer: UnsafeRawBufferPointer,
        to descriptor: Int32
    ) throws {
        var written = 0
        while written < buffer.count {
            let result = Darwin.write(
                descriptor,
                buffer.baseAddress?.advanced(by: written),
                buffer.count - written
            )
            if result > 0 {
                written += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                throw KernelProviderSecretCapabilityError.deliveryFailed(errno: errno)
            }
        }
    }
}

struct KernelProviderSecretIssuer: Sendable {
    // Kept below the minimum supported Darwin pipe capacity so a malicious or
    // broken provider that never reads cannot deadlock the supervisor thread.
    static let maximumSecretBytes = 8 * 1_024
    static let maximumLifetimeNanoseconds: UInt64 = 15 * 60 * 1_000_000_000

    private let credentialLookup:
        @Sendable (KernelProviderCredentialReference) throws -> Data

    init() {
        credentialLookup = { reference in
            try Self.keychainSecret(reference: reference)
        }
    }

    private init(
        credentialLookup: @escaping @Sendable
            (KernelProviderCredentialReference) throws -> Data
    ) {
        self.credentialLookup = credentialLookup
    }

#if DEBUG
    /// Allows deterministic tests of the stored-credential authority boundary
    /// without reading or mutating a developer's login keychain.
    static func testOnlyStoredCredential(
        _ credential: Data,
        reference: KernelProviderCredentialReference
    ) -> KernelProviderSecretIssuer {
        KernelProviderSecretIssuer { requestedReference in
            guard requestedReference == reference else {
                throw KernelProviderSecretCapabilityError
                    .credentialUnavailable(status: errSecItemNotFound)
            }
            return credential
        }
    }
#endif

#if DEBUG
    /// Raw bytes exist only for deterministic transport tests. Production
    /// composition has no caller-supplied secret boundary.
    func issue(
        secret: Data,
        for invocation: AuthorizedKernelProviderInvocation,
        executionProof: JournaledKernelExecutionProof,
        lifetimeNanoseconds: UInt64,
        issuedAtMonotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) throws -> KernelProviderSecretCapability {
        try issueResolvedSecret(
            secret,
            for: invocation,
            executionProof: executionProof,
            lifetimeNanoseconds: lifetimeNanoseconds,
            issuedAtMonotonicNanoseconds: issuedAtMonotonicNanoseconds
        )
    }
#endif

    /// Resolves only the exact credential reference retained in the ratified
    /// invocation profile. Callers supply neither secret bytes nor a keychain
    /// selector, preventing ambient-key and post-ratification substitution.
    func issueStoredCredential(
        for invocation: AuthorizedKernelProviderInvocation,
        executionProof: JournaledKernelExecutionProof,
        lifetimeNanoseconds: UInt64,
        issuedAtMonotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) throws -> KernelProviderSecretCapability {
        let receipt = invocation.receipt
        let binding = try validateAuthorization(
            receipt: receipt,
            executionProof: executionProof,
            lifetimeNanoseconds: lifetimeNanoseconds,
            issuedAtMonotonicNanoseconds: issuedAtMonotonicNanoseconds
        )
        guard let reference = receipt.executionProfile.credentialReference,
              reference.isValid,
              reference.source == .macOSKeychainGenericPassword else {
            throw KernelProviderSecretCapabilityError
                .credentialReferenceMissing
        }
        var secret = try credentialLookup(reference)
        defer {
            if !secret.isEmpty {
                secret.resetBytes(in: 0..<secret.count)
            }
        }
        guard !secret.isEmpty, secret.count <= Self.maximumSecretBytes else {
            throw KernelProviderSecretCapabilityError.invalidSecret
        }
        return KernelProviderSecretCapability(
            metadata: KernelProviderSecretCapabilityMetadata(
                capabilityID: UUID().uuidString.lowercased(),
                binding: binding,
                issuedAtMonotonicNanoseconds:
                    issuedAtMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds:
                    issuedAtMonotonicNanoseconds + lifetimeNanoseconds
            ),
            bytes: Array(secret)
        )
    }

    private static func keychainSecret(
        reference: KernelProviderCredentialReference
    ) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        guard status == errSecSuccess else {
            throw KernelProviderSecretCapabilityError
                .credentialUnavailable(status: status)
        }
        guard let secret = value as? Data else {
            throw KernelProviderSecretCapabilityError
                .credentialUnavailable(status: errSecDecode)
        }
        return secret
    }

    private func issueResolvedSecret(
        _ secret: Data,
        for invocation: AuthorizedKernelProviderInvocation,
        executionProof: JournaledKernelExecutionProof,
        lifetimeNanoseconds: UInt64,
        issuedAtMonotonicNanoseconds: UInt64
    ) throws -> KernelProviderSecretCapability {
        let receipt = invocation.receipt
        guard !secret.isEmpty, secret.count <= Self.maximumSecretBytes else {
            throw KernelProviderSecretCapabilityError.invalidSecret
        }
        let binding = try validateAuthorization(
            receipt: receipt,
            executionProof: executionProof,
            lifetimeNanoseconds: lifetimeNanoseconds,
            issuedAtMonotonicNanoseconds: issuedAtMonotonicNanoseconds
        )
        return KernelProviderSecretCapability(
            metadata: KernelProviderSecretCapabilityMetadata(
                capabilityID: UUID().uuidString.lowercased(),
                binding: binding,
                issuedAtMonotonicNanoseconds: issuedAtMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds:
                    issuedAtMonotonicNanoseconds + lifetimeNanoseconds
            ),
            bytes: Array(secret)
        )
    }

    private func validateAuthorization(
        receipt: KernelProviderInvocationReceipt,
        executionProof: JournaledKernelExecutionProof,
        lifetimeNanoseconds: UInt64,
        issuedAtMonotonicNanoseconds: UInt64
    ) throws -> KernelProviderSecretBinding {
        guard lifetimeNanoseconds > 0,
              lifetimeNanoseconds <= Self.maximumLifetimeNanoseconds,
              issuedAtMonotonicNanoseconds <= UInt64.max - lifetimeNanoseconds else {
            throw KernelProviderSecretCapabilityError.invalidLifetime
        }
        guard receipt.credentialMode == .opaqueProviderSecret else {
            throw KernelProviderSecretCapabilityError.credentialNotRequired
        }
        guard receipt.executionProfile.credentialReference?.isValid == true else {
            throw KernelProviderSecretCapabilityError
                .credentialReferenceMissing
        }
        guard receipt.runID == executionProof.runID,
              receipt.attemptID == executionProof.attemptID,
              receipt.nodeID == executionProof.nodeID,
              receipt.strategyFingerprint == executionProof.strategyFingerprint,
              receipt.activationActor == executionProof.activationActor,
              receipt.executionProfile == executionProof.workerExecutionProfile else {
            throw KernelProviderSecretCapabilityError.executionBindingMismatch
        }
        return KernelProviderSecretBinding(
            runID: receipt.runID,
            attemptID: receipt.attemptID,
            providerReference: receipt.executionProfile.providerReference,
            invocationDigest: receipt.invocationDigest
        )
    }
}
