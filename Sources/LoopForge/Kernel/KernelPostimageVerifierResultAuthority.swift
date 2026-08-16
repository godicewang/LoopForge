import CryptoKit
import Foundation

struct KernelPostimageVerifierResultReceipt: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var id: ReceiptID
    var runID: KernelRunID
    var activationReceiptID: ReceiptID
    var launchReceiptID: ReceiptID
    var releaseReceiptID: ReceiptID
    var integrationTransactionID: IntegrationTransactionID
    var applyReceiptID: ReceiptID
    var attemptID: AttemptID
    var requirementIDs: Set<RequirementID>
    var evidenceRecipeID: EvidenceRecipeID
    var sourceRevision: ContentDigest
    var verifier: ActorIdentity
    var standardOutputContentDigest: ContentDigest
    var standardErrorContentDigest: ContentDigest
    var terminalEnvelopeDigest: ContentDigest
    var parsedEvidenceDigest: ContentDigest
    var mappingOrdinal: UInt64
    var nativeExitCode: Int32
    var parserResultCode: String
    var outcome: RequirementVerificationOutcome
    var evidenceSetDigest: ContentDigest
    var completedAt: Date
}

/// Live result authority exists only after the exact release event is committed
/// by RunJournal. Durable result bytes alone cannot recreate this capability.
struct AuthorizedKernelPostimageVerifierResult: Sendable {
    let receipt: KernelPostimageVerifierResultReceipt
    let releaseTransaction: JournalTransactionReceipt

    private init(
        receipt: KernelPostimageVerifierResultReceipt,
        releaseTransaction: JournalTransactionReceipt
    ) {
        self.receipt = receipt
        self.releaseTransaction = releaseTransaction
    }

    static func issuedByProcessRuntime(
        receipt: KernelPostimageVerifierResultReceipt,
        releaseTransaction: JournalTransactionReceipt,
        issuer: JournaledProcessRuntimeCommandIssuer
    ) -> AuthorizedKernelPostimageVerifierResult {
        AuthorizedKernelPostimageVerifierResult(
            receipt: receipt,
            releaseTransaction: releaseTransaction
        )
    }
}

struct KernelPostimageVerifierResultAuthority: Sendable {
    private struct EvidenceMaterial: Codable {
        var schemaVersion: Int
        var runID: KernelRunID
        var activationReceiptID: ReceiptID
        var launchReceiptID: ReceiptID
        var releaseReceiptID: ReceiptID
        var integrationTransactionID: IntegrationTransactionID
        var applyReceiptID: ReceiptID
        var attemptID: AttemptID
        var requirementIDs: [RequirementID]
        var evidenceRecipeID: EvidenceRecipeID
        var sourceRevision: ContentDigest
        var verifier: ActorIdentity
        var standardOutputContentDigest: ContentDigest
        var standardErrorContentDigest: ContentDigest
        var terminalEnvelopeDigest: ContentDigest
        var parsedEvidenceDigest: ContentDigest
        var mappingOrdinal: UInt64
        var nativeExitCode: Int32
        var parserResultCode: String
        var outcome: RequirementVerificationOutcome
        var completedAt: Date
    }

    static func expectedReceipt(
        activation: KernelPostimageVerifierActivationReceipt,
        launch: KernelPostimageVerifierLaunchReceipt,
        releaseReceiptID: ReceiptID,
        standardOutput: KernelPostimageVerifierOutputFileReceipt,
        standardError: KernelPostimageVerifierOutputFileReceipt,
        parse: KernelPostimageVerifierResultParseReceipt,
        mapping: KernelPostimageVerifierResultMappingReceipt,
        completedAt: Date
    ) -> KernelPostimageVerifierResultReceipt? {
        guard !releaseReceiptID.rawValue.isEmpty,
              launch.runID == activation.runID,
              launch.activationReceiptID == activation.id,
              launch.integrationTransactionID ==
                activation.integrationTransactionID,
              launch.applyReceiptID == activation.applyReceiptID,
              launch.attemptID == activation.attemptID,
              launch.evidenceRecipeID == activation.evidenceRecipeID,
              launch.verifier == activation.verifier,
              parse.runID == activation.runID,
              parse.activationReceiptID == activation.id,
              parse.launchReceiptID == launch.id,
              parse.resourceID == launch.resourceID,
              parse.leaseID == launch.leaseID,
              parse.standardOutputContentDigest ==
                standardOutput.contentDigest,
              parse.standardErrorContentDigest ==
                standardError.contentDigest,
              mapping.schemaVersion == 1,
              mapping.probeDigest == activation.probeDigest,
              mapping.parserResultCode == parse.resultCode,
              mapping.parsedEvidenceDigest == parse.evidenceDigest,
              mapping.terminalEnvelopeDigest ==
                parse.terminalEnvelopeDigest,
              completedAt >= launch.launchedAt else {
            return nil
        }
        let material = EvidenceMaterial(
            schemaVersion: 1,
            runID: activation.runID,
            activationReceiptID: activation.id,
            launchReceiptID: launch.id,
            releaseReceiptID: releaseReceiptID,
            integrationTransactionID: activation.integrationTransactionID,
            applyReceiptID: activation.applyReceiptID,
            attemptID: activation.attemptID,
            requirementIDs: activation.requirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            evidenceRecipeID: activation.evidenceRecipeID,
            sourceRevision: activation.sourceRevision,
            verifier: activation.verifier,
            standardOutputContentDigest: standardOutput.contentDigest,
            standardErrorContentDigest: standardError.contentDigest,
            terminalEnvelopeDigest: parse.terminalEnvelopeDigest,
            parsedEvidenceDigest: parse.evidenceDigest,
            mappingOrdinal: mapping.mappingOrdinal,
            nativeExitCode: mapping.nativeExitCode,
            parserResultCode: mapping.parserResultCode,
            outcome: mapping.outcome,
            completedAt: completedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(material) else { return nil }
        let digest = ContentDigest(KernelHex.encode(SHA256.hash(data: bytes)))
        return KernelPostimageVerifierResultReceipt(
            schemaVersion: 1,
            id: ReceiptID("postimage-result:\(digest.rawValue)"),
            runID: material.runID,
            activationReceiptID: material.activationReceiptID,
            launchReceiptID: material.launchReceiptID,
            releaseReceiptID: material.releaseReceiptID,
            integrationTransactionID: material.integrationTransactionID,
            applyReceiptID: material.applyReceiptID,
            attemptID: material.attemptID,
            requirementIDs: Set(material.requirementIDs),
            evidenceRecipeID: material.evidenceRecipeID,
            sourceRevision: material.sourceRevision,
            verifier: material.verifier,
            standardOutputContentDigest:
                material.standardOutputContentDigest,
            standardErrorContentDigest:
                material.standardErrorContentDigest,
            terminalEnvelopeDigest: material.terminalEnvelopeDigest,
            parsedEvidenceDigest: material.parsedEvidenceDigest,
            mappingOrdinal: material.mappingOrdinal,
            nativeExitCode: material.nativeExitCode,
            parserResultCode: material.parserResultCode,
            outcome: material.outcome,
            evidenceSetDigest: digest,
            completedAt: material.completedAt
        )
    }
}

/// Deterministically converts one live, journal-bound postimage result into a
/// verification fact. The caller supplies no receipt identity, verdict,
/// requirement set, source revision, environment, oracle, or ordering value.
struct KernelPostimageVerificationAuthority: Sendable {
    private struct BatchMaterial: Codable {
        var schemaVersion: Int
        var postimageResultID: ReceiptID
        var postimageReleaseReceiptID: ReceiptID
        var postimageReleaseCommandID: RunCommandID
        var postimageReleaseEndingSequence: UInt64
        var postimageReleaseFrameDigest: ContentDigest
        var resultEvidenceSetDigest: ContentDigest
        var attemptID: AttemptID
        var requirementIDs: [RequirementID]
        var sourceRevision: ContentDigest
        var environmentDigest: ContentDigest
        var oracleDigest: ContentDigest
        var outcome: RequirementVerificationOutcome
    }

    static func expectedReceipt(
        result: KernelPostimageVerifierResultReceipt,
        releaseTransaction: JournalTransactionReceipt,
        environmentDigest: ContentDigest,
        oracleDigest: ContentDigest
    ) -> VerificationReceipt? {
        guard result.schemaVersion == 1,
              result.id.rawValue ==
                "postimage-result:\(result.evidenceSetDigest.rawValue)",
              result.releaseReceiptID.rawValue.isEmpty == false,
              releaseTransaction.duplicate == false,
              releaseTransaction.startingSequence ==
                releaseTransaction.endingSequence,
              releaseTransaction.eventIDs.count == 1,
              releaseTransaction.endingSequence > 0,
              validDigest(result.evidenceSetDigest),
              validDigest(releaseTransaction.frameDigest),
              validDigest(result.sourceRevision),
              validDigest(environmentDigest),
              validDigest(oracleDigest) else {
            return nil
        }
        let material = BatchMaterial(
            schemaVersion: 1,
            postimageResultID: result.id,
            postimageReleaseReceiptID: result.releaseReceiptID,
            postimageReleaseCommandID: releaseTransaction.commandID,
            postimageReleaseEndingSequence:
                releaseTransaction.endingSequence,
            postimageReleaseFrameDigest: releaseTransaction.frameDigest,
            resultEvidenceSetDigest: result.evidenceSetDigest,
            attemptID: result.attemptID,
            requirementIDs: result.requirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            sourceRevision: result.sourceRevision,
            environmentDigest: environmentDigest,
            oracleDigest: oracleDigest,
            outcome: result.outcome
        )
        guard let digest = evidenceDigest(material) else { return nil }
        let batch = KernelVerificationEvidenceBatch(
            schemaVersion: material.schemaVersion,
            postimageResultID: material.postimageResultID,
            postimageResultEvidenceSetDigest:
                material.resultEvidenceSetDigest,
            postimageReleaseReceiptID:
                material.postimageReleaseReceiptID,
            postimageReleaseCommandID:
                material.postimageReleaseCommandID,
            postimageReleaseEndingSequence:
                material.postimageReleaseEndingSequence,
            postimageReleaseFrameDigest:
                material.postimageReleaseFrameDigest,
            evidenceSetDigest: digest
        )
        return VerificationReceipt(
            id: ReceiptID("verification:\(digest.rawValue)"),
            attemptID: material.attemptID,
            requirementIDs: Set(material.requirementIDs),
            sourceRevision: material.sourceRevision,
            environmentDigest: material.environmentDigest,
            oracleDigest: material.oracleDigest,
            result: material.outcome == .accepted ? .accepted : .rejected,
            postimageEvidenceBatch: batch
        )
    }

    static func batchMatchesVerification(
        _ verification: VerificationReceipt
    ) -> Bool {
        guard let batch = verification.postimageEvidenceBatch,
              batch.schemaVersion == 1,
              batch.postimageResultID.rawValue ==
                "postimage-result:\(batch.postimageResultEvidenceSetDigest.rawValue)",
              batch.postimageReleaseReceiptID.rawValue.isEmpty == false,
              batch.postimageReleaseCommandID.rawValue.isEmpty == false,
              batch.postimageReleaseEndingSequence > 0,
              verification.requirementIDs.isEmpty == false,
              validDigest(batch.postimageResultEvidenceSetDigest),
              validDigest(batch.postimageReleaseFrameDigest),
              validDigest(batch.evidenceSetDigest),
              validDigest(verification.sourceRevision),
              validDigest(verification.environmentDigest),
              validDigest(verification.oracleDigest) else {
            return false
        }
        guard expectedEvidenceSetDigest(verification) ==
                batch.evidenceSetDigest else {
            return false
        }
        return verification.id.rawValue ==
            "verification:\(batch.evidenceSetDigest.rawValue)"
    }

    static func expectedEvidenceSetDigest(
        _ verification: VerificationReceipt
    ) -> ContentDigest? {
        guard let batch = verification.postimageEvidenceBatch else {
            return nil
        }
        let material = BatchMaterial(
            schemaVersion: batch.schemaVersion,
            postimageResultID: batch.postimageResultID,
            postimageReleaseReceiptID:
                batch.postimageReleaseReceiptID,
            postimageReleaseCommandID:
                batch.postimageReleaseCommandID,
            postimageReleaseEndingSequence:
                batch.postimageReleaseEndingSequence,
            postimageReleaseFrameDigest:
                batch.postimageReleaseFrameDigest,
            resultEvidenceSetDigest:
                batch.postimageResultEvidenceSetDigest,
            attemptID: verification.attemptID,
            requirementIDs: verification.requirementIDs.sorted {
                $0.rawValue < $1.rawValue
            },
            sourceRevision: verification.sourceRevision,
            environmentDigest: verification.environmentDigest,
            oracleDigest: verification.oracleDigest,
            outcome: verification.result == .accepted ? .accepted : .rejected
        )
        return evidenceDigest(material)
    }

    private static func evidenceDigest(
        _ material: BatchMaterial
    ) -> ContentDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(material) else { return nil }
        return ContentDigest(KernelHex.encode(SHA256.hash(data: bytes)))
    }

    private static func validDigest(_ digest: ContentDigest) -> Bool {
        digest.rawValue.utf8.count == 64 && digest.rawValue.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }
    }
}
