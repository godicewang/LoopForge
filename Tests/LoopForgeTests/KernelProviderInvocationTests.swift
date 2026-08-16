import Darwin
import Foundation
import XCTest
@testable import LoopForge

final class KernelProviderInvocationTests: XCTestCase {
    func testProfileReadinessNamesEveryCurrentProviderAuthorityGap() {
        var profile = executionProof(
            provider: .api,
            network: .disabled,
            providerProtocol: .unavailable
        ).workerExecutionProfile
        profile.pluginPolicy = .userInstalled
        profile.environmentPolicy = .declaredAllowlist
        profile.credentialMode = .opaqueProviderSecret
        profile.credentialReference = nil
        let readiness = KernelProviderInvocationCompiler.profileReadiness(
            profile,
            authorityCeiling: .readOnly
        )

        XCTAssertFalse(readiness.canCompileProviderInvocation)
        XCTAssertEqual(
            readiness.blockers,
            [
                .providerHarnessProtocolUnavailable,
                .remoteProviderNetworkAuthorityMissing,
                .userInstalledPluginAuthorityUnsupported,
                .declaredEnvironmentAuthorityUnsupported,
                .credentialAuthorityInvalid,
            ]
        )
        XCTAssertTrue(readiness.authorityCapabilityIDs.isEmpty)
    }

    func testProfileReadinessAcceptsOnlyRatifiedLocalV2Profile() {
        let profile = executionProof(
            provider: .local,
            network: .disabled,
            providerProtocol: .loopForgeProviderHarnessV2
        ).workerExecutionProfile
        let readiness = KernelProviderInvocationCompiler.profileReadiness(
            profile,
            authorityCeiling: .readOnly
        )

        XCTAssertTrue(readiness.canCompileProviderInvocation)
        XCTAssertTrue(readiness.blockers.isEmpty)
    }

    func testTransportVetoHarnessCannotClaimProductiveReadiness() {
        var profile = executionProof(
            provider: .local,
            network: .disabled,
            providerProtocol: .loopForgeProviderHarnessV2
        ).workerExecutionProfile
        profile.providerHarnessMode = .transportVetoOnly

        let readiness = KernelProviderInvocationCompiler.profileReadiness(
            profile,
            authorityCeiling: .readOnly
        )

        XCTAssertFalse(readiness.canCompileProviderInvocation)
        XCTAssertEqual(
            readiness.blockers,
            [.productiveProviderArchitectureUnavailable]
        )
        XCTAssertEqual(
            readiness.blockers.first?.rawValue,
            "providerHarnessProductiveBackendUnavailable"
        )
    }

    func testTransportVetoHarnessCannotAuthorizeOrValidateInvocation() throws {
        let proof = executionProof(
            provider: .local,
            network: .disabled,
            providerProtocol: .loopForgeProviderHarnessV2,
            providerHarnessMode: .transportVetoOnly
        )

        XCTAssertThrowsError(try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("transport-veto-authorization")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .productiveProviderArchitectureUnavailable
            )
        }

        let productiveProof = executionProof(
            provider: .local,
            network: .disabled,
            providerProtocol: .loopForgeProviderHarnessV2,
            providerHarnessMode: .productive
        )
        let authorized = try KernelProviderInvocationCompiler().authorize(
            executionProof: productiveProof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("transport-veto-replay")
        )
        var relabeled = authorized.receipt
        relabeled.executionProfile.providerHarnessMode = .transportVetoOnly
        XCTAssertFalse(
            KernelProviderInvocationCompiler.receiptIsValid(relabeled)
        )
    }

    func testCompilerProducesStableExactArgumentVectorWithoutLegacyAuthority() throws {
        let proof = executionProof(provider: .api, network: .enabled)
        let prompt = promptArtifact()
        let nonce = digest("nonce")
        let compiler = KernelProviderInvocationCompiler()

        let first = try compiler.authorize(
            executionProof: proof,
            promptArtifact: prompt,
            requestNonce: nonce
        )
        let second = try compiler.authorize(
            executionProof: proof,
            promptArtifact: prompt,
            requestNonce: nonce
        )

        XCTAssertEqual(first.receipt, second.receipt)
        XCTAssertEqual(first.receipt.credentialMode, .opaqueProviderSecret)
        XCTAssertEqual(first.receipt.credentialDescriptor, 197)
        XCTAssertEqual(first.receipt.invocationContextDescriptor, 196)
        XCTAssertFalse(first.receipt.hiddenFanOutEnabled)
        XCTAssertTrue(first.receipt.arguments.contains("--plugins"))
        XCTAssertTrue(first.receipt.arguments.contains("disabled"))
        XCTAssertFalse(first.receipt.arguments.contains("--enable"))
        XCTAssertFalse(first.receipt.arguments.contains("--config"))
        XCTAssertFalse(first.receipt.arguments.contains("--sandbox-dangerously-bypass-approvals-and-sandbox"))
        XCTAssertTrue(first.receipt.arguments.contains("--invocation-context-fd"))
        XCTAssertTrue(first.receipt.arguments.contains("196"))
        XCTAssertEqual(first.receipt.invocationDigest.rawValue.count, 64)
        XCTAssertEqual(first.receipt.argumentVectorDigest.rawValue.count, 64)
        XCTAssertTrue(
            KernelProviderInvocationCompiler.receiptIsValid(first.receipt)
        )
        let contextBytes = try XCTUnwrap(
            KernelProviderInvocationContextTransportReceipt.payloadBytes(
                for: first.receipt
            )
        )
        let context = try JSONDecoder().decode(
            KernelProviderInvocationContextPayload.self,
            from: Data(contextBytes.dropLast())
        )
        XCTAssertEqual(context.invocationDigest, first.receipt.invocationDigest)
        XCTAssertEqual(context.requestNonce, nonce)
        XCTAssertEqual(context.runID, first.receipt.runID)
        XCTAssertEqual(context.attemptID, first.receipt.attemptID)

        var tampered = first.receipt
        tampered.arguments.append("--ambient-authority")
        XCTAssertFalse(
            KernelProviderInvocationCompiler.receiptIsValid(tampered)
        )
    }

    func testProviderLaunchReceiptBindsInvocationSecretAndNativeProcessEvidence() throws {
        let proof = executionProof(provider: .api, network: .enabled)
        let authorization = try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("launch-nonce")
        )
        let invocation = authorization.receipt
        let binding = providerBinding(invocation: invocation)
        let secretBinding = KernelProviderSecretBinding(
            runID: invocation.runID,
            attemptID: invocation.attemptID,
            providerReference: invocation.executionProfile.providerReference,
            invocationDigest: invocation.invocationDigest
        )
        let delivery = KernelProviderSecretDeliveryReceipt(
            capabilityID: "ephemeral-capability",
            binding: secretBinding,
            targetDescriptor: 197,
            deliveredAtMonotonicNanoseconds: 490
        )
        let contextTransport = try XCTUnwrap(
            KernelProviderInvocationContextTransportReceipt.issue(
                invocation: invocation,
                stagedAtMonotonicNanoseconds: 475
            )
        )
        let receipt = try KernelProviderLaunchEvidenceIssuer().issue(
            id: ReceiptID("provider-launch"),
            binding: binding,
            invocation: authorization,
            invocationContextTransport: contextTransport,
            secretDelivery: delivery
        ).receipt
        XCTAssertEqual(receipt.schemaVersion, 2)
        XCTAssertEqual(
            receipt.resourceLimits,
            KernelProviderInvocationCompiler.requiredResourceLimits
        )
        XCTAssertTrue(receipt.isValid(binding: binding))

        var missingLimits = receipt
        missingLimits.resourceLimits = nil
        XCTAssertFalse(missingLimits.isValid(binding: binding))

        var broadenedLimits = receipt
        broadenedLimits.resourceLimits?.maximumProcessCount = 2
        XCTAssertFalse(broadenedLimits.isValid(binding: binding))

        var unboundedBinding = binding
        unboundedBinding.identity.kernelResourceLimits = nil
        XCTAssertFalse(receipt.isValid(binding: unboundedBinding))

        var wrongDescriptor = receipt
        wrongDescriptor.secretDelivery?.targetDescriptor = 196
        XCTAssertFalse(wrongDescriptor.isValid(binding: binding))

        var wrongContext = receipt
        wrongContext.invocationContextTransport?.contentDigest = digest("wrong-context")
        XCTAssertFalse(wrongContext.isValid(binding: binding))

        var lateContext = receipt
        lateContext.invocationContextTransport?.stagedAtMonotonicNanoseconds = 501
        XCTAssertFalse(lateContext.isValid(binding: binding))

        var wrongInvocation = receipt
        wrongInvocation.invocation.requestNonce = digest("other-nonce")
        XCTAssertFalse(wrongInvocation.isValid(binding: binding))

        var wrongProcess = binding
        wrongProcess.identity.processID = 43
        XCTAssertFalse(receipt.isValid(binding: wrongProcess))
    }

    func testCompilerRejectsRemoteProviderWithoutNetworkAndBroadPlugins() throws {
        let compiler = KernelProviderInvocationCompiler()
        XCTAssertThrowsError(try compiler.authorize(
            executionProof: executionProof(provider: .api, network: .disabled),
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .remoteProviderRequiresNetwork
            )
        }

        XCTAssertThrowsError(try compiler.authorize(
            executionProof: executionProof(
                provider: .local,
                network: .disabled,
                plugins: .userInstalled
            ),
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .unsupportedPluginAuthority
            )
        }
    }

    func testDeclaredEnvironmentRejectsBeforePromptAuthorizationAndOnReplay() throws {
        let proof = executionProof(
            provider: .local,
            network: .disabled,
            environment: .declaredAllowlist
        )
        let readiness = KernelProviderInvocationCompiler.profileReadiness(
            proof.workerExecutionProfile,
            authorityCeiling: KernelAuthorityCeiling(
                readableScopes: [],
                writableScopes: [],
                capabilityIDs: [
                    KernelExecutionProfile.declaredEnvironmentCapabilityID
                ],
                permitsExternalPublication: false
            )
        )
        XCTAssertFalse(readiness.canCompileProviderInvocation)
        XCTAssertEqual(
            readiness.blockers,
            [.declaredEnvironmentAuthorityUnsupported]
        )
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("declared-environment-authorization")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .unsupportedEnvironmentAuthority
            )
        }

        let productive = try KernelProviderInvocationCompiler().authorize(
            executionProof: executionProof(
                provider: .local,
                network: .disabled
            ),
            promptArtifact: promptArtifact(),
            requestNonce: digest("declared-environment-replay")
        )
        var relabeled = productive.receipt
        relabeled.executionProfile.environmentPolicy = .declaredAllowlist
        XCTAssertFalse(
            KernelProviderInvocationCompiler.receiptIsValid(relabeled)
        )
    }

    func testCompilerRejectsDirectProviderExecutableWithoutRatifiedHarnessProtocol() {
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().authorize(
            executionProof: executionProof(
                provider: .local,
                network: .disabled,
                providerProtocol: .unavailable
            ),
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .unsupportedProviderProtocol
            )
        }
    }

    func testCompilerRejectsLegacyHarnessWithoutInvocationContextTransport() {
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().authorize(
            executionProof: executionProof(
                provider: .local,
                network: .disabled,
                providerProtocol: .loopForgeProviderHarnessV1
            ),
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .unsupportedProviderProtocol
            )
        }
    }

    func testCompilerRequiresExactCredentialAuthorityInsteadOfProviderInference() {
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().authorize(
            executionProof: executionProof(
                provider: .api,
                network: .enabled,
                includeCredentialReference: false
            ),
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .invalidCredentialAuthority
            )
        }

        let credentialFreeRemote = executionProof(
            provider: .codex,
            network: .enabled,
            credentialMode: KernelProviderCredentialMode.none
        )
        let invocation = try? KernelProviderInvocationCompiler().authorize(
            executionProof: credentialFreeRemote,
            promptArtifact: promptArtifact(),
            requestNonce: digest("credential-free-session")
        )
        XCTAssertEqual(
            invocation?.receipt.credentialMode,
            KernelProviderCredentialMode.none
        )
        XCTAssertNil(invocation?.receipt.credentialDescriptor)
        XCTAssertNil(
            invocation?.receipt.executionProfile.credentialReference
        )
    }

    func testHistoricalReceiptWithoutContextFieldsDecodesAsInvalidEvidence() throws {
        let proof = executionProof(provider: .api, network: .enabled)
        let authorization = try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("historical-context")
        )
        let binding = providerBinding(invocation: authorization.receipt)
        let context = try XCTUnwrap(
            KernelProviderInvocationContextTransportReceipt.issue(
                invocation: authorization.receipt,
                stagedAtMonotonicNanoseconds: 475
            )
        )
        let secretDelivery = KernelProviderSecretDeliveryReceipt(
            capabilityID: "historical-secret",
            binding: KernelProviderSecretBinding(
                runID: authorization.receipt.runID,
                attemptID: authorization.receipt.attemptID,
                providerReference:
                    authorization.receipt.executionProfile.providerReference,
                invocationDigest: authorization.receipt.invocationDigest
            ),
            targetDescriptor: 197,
            deliveredAtMonotonicNanoseconds: 490
        )
        let launch = try KernelProviderLaunchEvidenceIssuer().issue(
            id: ReceiptID("historical-launch"),
            binding: binding,
            invocation: authorization,
            invocationContextTransport: context,
            secretDelivery: secretDelivery
        ).receipt
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(launch)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "invocationContextTransport")
        var invocationObject = try XCTUnwrap(
            object["invocation"] as? [String: Any]
        )
        invocationObject.removeValue(forKey: "invocationContextDescriptor")
        invocationObject["providerProtocol"] = nil
        if var profile = invocationObject["executionProfile"] as? [String: Any] {
            profile["providerProtocol"] = "loopForgeProviderHarnessV1"
            profile.removeValue(forKey: "credentialMode")
            profile.removeValue(forKey: "credentialReference")
            invocationObject["executionProfile"] = profile
        }
        object["invocation"] = invocationObject
        let historical = try JSONDecoder().decode(
            KernelProviderLaunchReceipt.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(historical.invocation.invocationContextDescriptor)
        XCTAssertNil(historical.invocationContextTransport)
        XCTAssertFalse(
            KernelProviderInvocationCompiler.receiptIsValid(
                historical.invocation
            )
        )
        XCTAssertFalse(historical.isValid(binding: binding))
    }

    func testCompilerRejectsUnicodeHexLookalikeDigest() throws {
        var prompt = promptArtifact().receipt
        prompt.contentDigest = ContentDigest(String(repeating: "１", count: 64))
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().authorize(
            executionProof: executionProof(provider: .local, network: .disabled),
            promptArtifact: .testOnly(receipt: prompt),
            requestNonce: digest("nonce")
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderInvocationAuthorizationError,
                .invalidPromptArtifact
            )
        }
    }

    func testSpecificationValidationRejectsArbitraryArgumentsEnvironmentAndPrompt() throws {
        let authorization = try KernelProviderInvocationCompiler().authorize(
            executionProof: executionProof(provider: .local, network: .disabled),
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )
        let valid = ManagedProcessSpecification(
            executablePath: "/usr/bin/true",
            arguments: authorization.receipt.arguments,
            environment: [:],
            ioFiles: ManagedProcessIOFiles(
                directoryPath: "/tmp/journal",
                standardInputFileName: "prompt.json",
                standardOutputFileName: "stdout.jsonl",
                standardErrorFileName: "stderr.txt"
            ),
            expectedArgumentVectorContentDigest:
                authorization.receipt.argumentVectorDigest
        )
        XCTAssertNoThrow(try KernelProviderInvocationCompiler().validate(
            specification: valid,
            against: authorization
        ))

        var injected = valid
        injected.arguments.append(contentsOf: ["--enable", "plugins"])
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().validate(
            specification: injected,
            against: authorization
        ))

        var ambient = valid
        ambient.environment["PRIVATE_API_KEY"] = "must-not-cross"
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().validate(
            specification: ambient,
            against: authorization
        ))

        var crossWiredPrompt = valid
        crossWiredPrompt.ioFiles?.standardInputFileName = "other-prompt.json"
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().validate(
            specification: crossWiredPrompt,
            against: authorization
        ))

        var callerSuppliedLimits = valid
        callerSuppliedLimits.kernelResourceLimits =
            KernelProviderInvocationCompiler.requiredResourceLimits
        XCTAssertThrowsError(try KernelProviderInvocationCompiler().validate(
            specification: callerSuppliedLimits,
            against: authorization
        ))

        var transport = valid
        transport.expectedProviderPromptArtifact =
            authorization.receipt.promptArtifact
        transport.nativeSandbox = ManagedProcessNativeSandbox(
            receipt: KernelNativeSandboxReceipt(
                schemaVersion: 1,
                sandbox: authorization.receipt.executionProfile.sandbox,
                networkPolicy:
                    authorization.receipt.executionProfile.networkPolicy,
                launcherPath: KernelNativeSandboxAuthorizer.launcherPath,
                launcherContentDigest: digest("launcher"),
                gateExecutablePath: "/tmp/gate",
                gateExecutableContentDigest: digest("gate"),
                profileDigest: digest("profile"),
                parameterDigest: digest("parameters"),
                workspaceRootPathDigest: digest("workspace"),
                journalRunDirectoryPathDigest: digest("journal"),
                standardOutputPathDigest: digest("stdout"),
                standardErrorPathDigest: digest("stderr"),
                journalWritesDefaultDenied: true,
                nativeAttestationRequired: true
            ),
            profile: "invalid-test-profile",
            parameters: [:]
        )
        transport.kernelResourceLimits =
            KernelProviderInvocationCompiler.requiredResourceLimits
        XCTAssertThrowsError(
            try KernelProviderInvocationCompiler().validateTransport(
                specification: transport,
                against: authorization
            )
        )
    }

    func testOpaqueSecretDeliversLengthPrefixedBytesExactlyOnceWithoutSerialization() throws {
        let proof = executionProof(provider: .api, network: .enabled)
        let authorization = try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )
        let secret = Data("not-for-argv-environment-or-disk".utf8)
        let capability = try KernelProviderSecretIssuer().issue(
            secret: secret,
            for: authorization,
            executionProof: proof,
            lifetimeNanoseconds: 1_000,
            issuedAtMonotonicNanoseconds: 100
        )
        let encodedMetadata = try JSONEncoder().encode(capability.metadata)
        XCTAssertNil(String(data: encodedMetadata, encoding: .utf8)?.range(
            of: "not-for-argv-environment-or-disk"
        ))

        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(Darwin.pipe(&descriptors), 0)
        defer {
            _ = Darwin.close(descriptors[0])
            _ = Darwin.close(descriptors[1])
        }
        let delivery = try capability.deliver(
            to: descriptors[1],
            for: capability.metadata.binding,
            nowMonotonicNanoseconds: 101
        )
        XCTAssertEqual(delivery.targetDescriptor, descriptors[1])
        _ = Darwin.close(descriptors[1])
        descriptors[1] = -1

        var payload = [UInt8](repeating: 0, count: secret.count + 8)
        let count = payload.withUnsafeMutableBytes {
            Darwin.read(descriptors[0], $0.baseAddress, $0.count)
        }
        XCTAssertEqual(count, payload.count)
        let length = payload.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        XCTAssertEqual(length, UInt64(secret.count))
        XCTAssertEqual(Data(payload.dropFirst(8)), secret)

        XCTAssertThrowsError(try capability.deliver(
            to: STDOUT_FILENO,
            for: capability.metadata.binding,
            nowMonotonicNanoseconds: 102
        )) { error in
            XCTAssertEqual(error as? KernelProviderSecretCapabilityError, .alreadyConsumed)
        }
    }

    func testStoredCredentialIssuerResolvesOnlyTheRatifiedReference() throws {
        let proof = executionProof(provider: .api, network: .enabled)
        let authorization = try KernelProviderInvocationCompiler().authorize(
            executionProof: proof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("stored-credential")
        )
        let reference = try XCTUnwrap(
            authorization.receipt.executionProfile.credentialReference
        )
        let secret = Data("exact-keychain-secret".utf8)
        let issuer = KernelProviderSecretIssuer.testOnlyStoredCredential(
            secret,
            reference: reference
        )
        let capability = try issuer.issueStoredCredential(
            for: authorization,
            executionProof: proof,
            lifetimeNanoseconds: 1_000,
            issuedAtMonotonicNanoseconds: 100
        )
        let encodedMetadata = try JSONEncoder().encode(capability.metadata)
        XCTAssertNil(String(data: encodedMetadata, encoding: .utf8)?.range(
            of: "exact-keychain-secret"
        ))

        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(Darwin.pipe(&descriptors), 0)
        defer {
            _ = Darwin.close(descriptors[0])
            if descriptors[1] >= 0 { _ = Darwin.close(descriptors[1]) }
        }
        _ = try capability.deliver(
            to: descriptors[1],
            for: capability.metadata.binding,
            nowMonotonicNanoseconds: 101
        )
        _ = Darwin.close(descriptors[1])
        descriptors[1] = -1
        var payload = [UInt8](repeating: 0, count: secret.count + 8)
        let count = payload.withUnsafeMutableBytes {
            Darwin.read(descriptors[0], $0.baseAddress, $0.count)
        }
        XCTAssertEqual(count, payload.count)
        XCTAssertEqual(Data(payload.dropFirst(8)), secret)

        let wrongReferenceIssuer =
            KernelProviderSecretIssuer.testOnlyStoredCredential(
                secret,
                reference: KernelProviderCredentialReference(
                    source: .macOSKeychainGenericPassword,
                    service: reference.service,
                    account: "other-account"
                )
            )
        XCTAssertThrowsError(try wrongReferenceIssuer.issueStoredCredential(
            for: authorization,
            executionProof: proof,
            lifetimeNanoseconds: 1_000,
            issuedAtMonotonicNanoseconds: 100
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderSecretCapabilityError,
                .credentialUnavailable(status: errSecItemNotFound)
            )
        }

        let credentialFreeProof = executionProof(
            provider: .codex,
            network: .enabled,
            credentialMode: KernelProviderCredentialMode.none
        )
        let credentialFreeAuthorization = try
            KernelProviderInvocationCompiler().authorize(
                executionProof: credentialFreeProof,
                promptArtifact: promptArtifact(),
                requestNonce: digest("no-stored-credential")
            )
        XCTAssertThrowsError(try issuer.issueStoredCredential(
            for: credentialFreeAuthorization,
            executionProof: credentialFreeProof,
            lifetimeNanoseconds: 1_000,
            issuedAtMonotonicNanoseconds: 100
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderSecretCapabilityError,
                .credentialNotRequired
            )
        }
    }

    func testSecretCapabilityRejectsCrossWiringExpiryAndLocalProvider() throws {
        let remoteProof = executionProof(provider: .api, network: .enabled)
        let remote = try KernelProviderInvocationCompiler().authorize(
            executionProof: remoteProof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )
        let capability = try KernelProviderSecretIssuer().issue(
            secret: Data("secret".utf8),
            for: remote,
            executionProof: remoteProof,
            lifetimeNanoseconds: 10,
            issuedAtMonotonicNanoseconds: 100
        )
        var wrong = capability.metadata.binding
        wrong.attemptID = AttemptID("other-attempt")
        XCTAssertThrowsError(try capability.deliver(
            to: STDOUT_FILENO,
            for: wrong,
            nowMonotonicNanoseconds: 101
        )) { error in
            XCTAssertEqual(error as? KernelProviderSecretCapabilityError, .bindingMismatch)
        }

        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(Darwin.pipe(&descriptors), 0)
        defer {
            _ = Darwin.close(descriptors[0])
            _ = Darwin.close(descriptors[1])
        }
        XCTAssertThrowsError(try capability.deliver(
            to: descriptors[1],
            for: capability.metadata.binding,
            nowMonotonicNanoseconds: 111
        )) { error in
            XCTAssertEqual(error as? KernelProviderSecretCapabilityError, .expired)
        }

        let localProof = executionProof(provider: .local, network: .disabled)
        let local = try KernelProviderInvocationCompiler().authorize(
            executionProof: localProof,
            promptArtifact: promptArtifact(),
            requestNonce: digest("nonce")
        )
        XCTAssertThrowsError(try KernelProviderSecretIssuer().issue(
            secret: Data("unneeded".utf8),
            for: local,
            executionProof: localProof,
            lifetimeNanoseconds: 10,
            issuedAtMonotonicNanoseconds: 100
        )) { error in
            XCTAssertEqual(
                error as? KernelProviderSecretCapabilityError,
                .credentialNotRequired
            )
        }
    }

    private func executionProof(
        provider: KernelExecutionProvider,
        network: KernelNetworkPolicy,
        plugins: KernelPluginPolicy = .disabled,
        environment: KernelEnvironmentPolicy = .minimalKernelAllowlist,
        providerProtocol: KernelProviderProtocol = .loopForgeProviderHarnessV2,
        providerHarnessMode: KernelProviderHarnessMode? = nil,
        credentialMode: KernelProviderCredentialMode? = nil,
        includeCredentialReference: Bool = true
    ) -> JournaledKernelExecutionProof {
        let resolvedCredentialMode = credentialMode
            ?? (provider == .local ? .none : .opaqueProviderSecret)
        let credentialReference = resolvedCredentialMode == .opaqueProviderSecret
            && includeCredentialReference
            ? KernelProviderCredentialReference(
                source: .macOSKeychainGenericPassword,
                service: "test.loopforge.provider",
                account: "test-provider-account"
            )
            : nil
        return JournaledKernelExecutionProof.testOnly(
            runID: KernelRunID("provider-run"),
            attemptID: AttemptID("provider-attempt"),
            nodeID: KernelNodeID("provider-node"),
            strategyFingerprint: StrategyFingerprint("provider-strategy"),
            workerExecutionProfile: KernelAgentExecutionProfile(
                provider: provider,
                providerReference: provider == .local ? "local-profile" : "remote-profile",
                executableContentDigest: digest("executable"),
                modelID: "model-v1",
                reasoningEffort: "high",
                sandbox: .workspaceOnly,
                networkPolicy: network,
                pluginPolicy: plugins,
                environmentPolicy: environment,
                providerProtocol: providerProtocol,
                providerHarnessMode: providerHarnessMode ?? (
                    providerProtocol == .loopForgeProviderHarnessV2
                        ? .productive
                        : .unavailable
                ),
                credentialMode: resolvedCredentialMode,
                credentialReference: credentialReference
            ),
            workspaceRoot: URL(fileURLWithPath: "/tmp/provider-workspace", isDirectory: true),
            activationActor: ActorIdentity(
                id: ActorID("provider-actor"),
                role: "worker",
                lineageDigest: digest("actor")
            ),
            activationTransaction: JournalTransactionReceipt(
                commandID: RunCommandID("activate-provider"),
                startingSequence: 1,
                endingSequence: 1,
                eventIDs: [OrchestrationEventID("provider-event")],
                frameDigest: digest("frame"),
                duplicate: false
            )
        )
    }

    func testPromptIssuerCreatesImmutableJournalOwnedArtifactWithInodeIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ProviderPrompt-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let proof = executionProof(provider: .local, network: .disabled)
        let prompt = Data("journal-owned exact prompt".utf8)

        let authorization = try KernelProviderPromptArtifactIssuer().issue(
            prompt: prompt,
            fileName: "provider-prompt.json",
            journalRunDirectory: root,
            executionProof: proof
        )

        XCTAssertEqual(authorization.receipt.runID, proof.runID)
        XCTAssertEqual(authorization.receipt.attemptID, proof.attemptID)
        XCTAssertEqual(authorization.receipt.byteCount, UInt64(prompt.count))
        XCTAssertEqual(authorization.receipt.contentDigest, digest("journal-owned exact prompt"))
        XCTAssertGreaterThan(authorization.receipt.inode, 0)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("provider-prompt.json")),
            prompt
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("provider-prompt.json").path
        )
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o400)
        XCTAssertThrowsError(try KernelProviderPromptArtifactIssuer().issue(
            prompt: Data("replacement".utf8),
            fileName: "provider-prompt.json",
            journalRunDirectory: root,
            executionProof: proof
        )) { error in
            guard case .createFailed(let failure) =
                    error as? KernelProviderPromptArtifactError else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(failure, EEXIST)
        }
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("provider-prompt.json")),
            prompt
        )
    }

    func testPromptIssuerRejectsTraversalAndSymlinkRunDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LoopForge-ProviderPrompt-Symlink-\(UUID().uuidString)",
            isDirectory: true
        )
        let real = root.appendingPathComponent("real", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)
        defer { try? FileManager.default.removeItem(at: root) }
        let issuer = KernelProviderPromptArtifactIssuer()
        let proof = executionProof(provider: .local, network: .disabled)

        XCTAssertThrowsError(try issuer.issue(
            prompt: Data("prompt".utf8),
            fileName: "../escape",
            journalRunDirectory: real,
            executionProof: proof
        )) { error in
            XCTAssertEqual(error as? KernelProviderPromptArtifactError, .invalidFileName)
        }
        XCTAssertThrowsError(try issuer.issue(
            prompt: Data("prompt".utf8),
            fileName: "prompt.json",
            journalRunDirectory: link,
            executionProof: proof
        )) { error in
            XCTAssertEqual(error as? KernelProviderPromptArtifactError, .invalidRunDirectory)
        }
    }

    private func promptArtifact() -> AuthorizedKernelProviderPromptArtifact {
        .testOnly(receipt: KernelProviderPromptArtifactReceipt(
            runID: KernelRunID("provider-run"),
            attemptID: AttemptID("provider-attempt"),
            fileName: "prompt.json",
            contentDigest: digest("prompt"),
            byteCount: 128,
            deviceID: 1,
            inode: 1
        ))
    }

    private func providerBinding(
        invocation: KernelProviderInvocationReceipt
    ) -> RuntimeExternalBindingReceipt {
        let sandbox = KernelNativeSandboxReceipt(
            schemaVersion: 1,
            sandbox: invocation.executionProfile.sandbox,
            networkPolicy: invocation.executionProfile.networkPolicy,
            launcherPath: "/usr/bin/sandbox-exec",
            launcherContentDigest: digest("sandbox-exec"),
            gateExecutablePath: "/tmp/provider-gate",
            gateExecutableContentDigest: digest("provider-gate"),
            profileDigest: digest("profile"),
            parameterDigest: digest("parameters"),
            workspaceRootPathDigest: digest("workspace"),
            journalRunDirectoryPathDigest: digest("journal"),
            standardOutputPathDigest: digest("stdout"),
            standardErrorPathDigest: digest("stderr"),
            journalWritesDefaultDenied: true,
            nativeAttestationRequired: true
        )
        return RuntimeExternalBindingReceipt(
            id: ReceiptID("provider-binding"),
            runID: invocation.runID,
            resourceID: OwnedResourceID("provider-resource"),
            leaseID: ResourceLeaseID("provider-lease"),
            identity: RuntimeExternalIdentity(
                stableDigest: digest("provider-process"),
                processID: 42,
                processStartMonotonicNanoseconds: 480,
                processStartSystemNanoseconds: 480,
                parentResourceID: nil,
                executableContentDigest:
                    invocation.executionProfile.executableContentDigest,
                environmentContentDigest: digest("environment"),
                argumentVectorContentDigest:
                    invocation.argumentVectorDigest,
                nativeSandboxAttestation:
                    KernelNativeSandboxAttestationReceipt(
                        authorization: sandbox,
                        processID: 42,
                        observedAtMonotonicNanoseconds: 485,
                        nativeSandboxCheckResult: 1,
                        gateObservedStopped: true,
                        targetExecHandshakeSucceeded: true
                    ),
                kernelResourceLimits:
                    KernelProviderInvocationCompiler.requiredResourceLimits
            ),
            accepted: true,
            observedAt: Date(timeIntervalSince1970: 1),
            observedAtMonotonicNanoseconds: 500
        )
    }

    private func digest(_ value: String) -> ContentDigest {
        KernelWorkerResultParser.contentDigest(Data(value.utf8))
    }
}
