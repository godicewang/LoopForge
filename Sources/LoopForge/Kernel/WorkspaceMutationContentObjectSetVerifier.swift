import CryptoKit
import Foundation

struct WorkspaceMutationContentObjectSetLimits: Codable, Hashable, Sendable {
    var maximumObjectCount: Int
    var maximumObjectBytes: UInt64
    var maximumTotalBytes: UInt64

    static let conservative = WorkspaceMutationContentObjectSetLimits(
        maximumObjectCount: 200_000,
        maximumObjectBytes: 512 * 1_024 * 1_024,
        maximumTotalBytes: 4 * 1_024 * 1_024 * 1_024
    )

    func validationIssues() -> [String] {
        var issues: [String] = []
        if maximumObjectCount <= 0 { issues.append("maximumObjectCount must be positive") }
        if maximumObjectBytes == 0 { issues.append("maximumObjectBytes must be positive") }
        if maximumTotalBytes == 0 { issues.append("maximumTotalBytes must be positive") }
        if maximumObjectBytes > maximumTotalBytes {
            issues.append("maximumObjectBytes must not exceed maximumTotalBytes")
        }
        return issues
    }
}

/// Durable evidence that an exact mutation delta's complete before/after
/// content-reference set was supplied and byte-rehashed. This is inert data:
/// it carries no journal provenance and cannot authorize staging or apply.
struct WorkspaceMutationContentObjectSetReceipt:
    Codable,
    Hashable,
    Sendable
{
    var schemaVersion: Int
    var derivationDigest: ContentDigest
    var baseSourceRevision: ContentDigest
    var candidateSourceRevision: ContentDigest
    var contentObjects: [WorkspaceMutationContentReference]
    var objectSetDigest: ContentDigest
    var objectCount: Int
    var totalBytes: UInt64
    var limits: WorkspaceMutationContentObjectSetLimits
    var receiptDigest: ContentDigest

    func validationIssues() -> [String] {
        var issues: [String] = []
        if schemaVersion != 1 { issues.append("unsupported content-object-set schema") }
        issues.append(contentsOf: limits.validationIssues())
        for digest in [
            derivationDigest,
            baseSourceRevision,
            candidateSourceRevision,
            objectSetDigest
        ] where !Self.isSHA256(digest) {
            issues.append("content-object-set authority digests must be SHA-256")
        }
        if contentObjects != contentObjects.sorted(by: {
            $0.contentDigest.rawValue < $1.contentDigest.rawValue
        }) || Set(contentObjects.map(\.contentDigest)).count != contentObjects.count {
            issues.append("content references must be uniquely digest-sorted")
        }
        if objectCount != contentObjects.count
            || objectCount <= 0
            || objectCount > limits.maximumObjectCount {
            issues.append("content object count is inconsistent")
        }
        var observedTotal: UInt64 = 0
        for object in contentObjects {
            if !Self.isSHA256(object.contentDigest) {
                issues.append("content reference digest must be SHA-256")
            }
            if object.size > limits.maximumObjectBytes {
                issues.append("content reference exceeds per-object limit")
            }
            let (next, overflow) = observedTotal.addingReportingOverflow(object.size)
            if overflow {
                issues.append("content reference total overflowed")
                observedTotal = .max
            } else {
                observedTotal = next
            }
        }
        if observedTotal != totalBytes || totalBytes > limits.maximumTotalBytes {
            issues.append("content object total bytes are inconsistent")
        }
        if Self.digest(for: self) != receiptDigest {
            issues.append("content-object-set receipt digest mismatch")
        }
        return issues
    }

    fileprivate static func digest(
        for receipt: WorkspaceMutationContentObjectSetReceipt
    ) -> ContentDigest? {
        let material = DigestMaterial(
            schemaVersion: receipt.schemaVersion,
            derivationDigest: receipt.derivationDigest,
            baseSourceRevision: receipt.baseSourceRevision,
            candidateSourceRevision: receipt.candidateSourceRevision,
            contentObjects: receipt.contentObjects,
            objectSetDigest: receipt.objectSetDigest,
            objectCount: receipt.objectCount,
            totalBytes: receipt.totalBytes,
            limits: receipt.limits
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(material) else { return nil }
        return ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
    }

    private static func isSHA256(_ digest: ContentDigest) -> Bool {
        digest.rawValue.count == 64 && digest.rawValue.allSatisfy {
            $0.isNumber || ("a"..."f").contains(String($0))
        }
    }

    private struct DigestMaterial: Codable {
        var schemaVersion: Int
        var derivationDigest: ContentDigest
        var baseSourceRevision: ContentDigest
        var candidateSourceRevision: ContentDigest
        var contentObjects: [WorkspaceMutationContentReference]
        var objectSetDigest: ContentDigest
        var objectCount: Int
        var totalBytes: UInt64
        var limits: WorkspaceMutationContentObjectSetLimits
    }
}

enum WorkspaceMutationContentObjectSetVerificationError:
    Error,
    Equatable,
    Sendable
{
    case invalidDerivation
    case invalidLimits
    case objectCountLimitExceeded(actual: Int, maximum: Int)
    case duplicateObject(ContentDigest)
    case missingObject(ContentDigest)
    case unexpectedObject(ContentDigest)
    case objectSizeLimitExceeded(
        digest: ContentDigest,
        actual: UInt64,
        maximum: UInt64
    )
    case objectSizeMismatch(
        digest: ContentDigest,
        actual: UInt64,
        expected: UInt64
    )
    case corruptObject(ContentDigest)
    case totalByteLimitExceeded(actual: UInt64, maximum: UInt64)
    case encodingFailed
}

struct WorkspaceMutationContentObjectSetVerifier: Sendable {
    func verify(
        derivation: WorkspaceMutationOperationDerivationReceipt,
        objects: [WorkspaceMutationContentObject],
        limits: WorkspaceMutationContentObjectSetLimits = .conservative
    ) throws -> WorkspaceMutationContentObjectSetReceipt {
        guard derivation.validationIssues().isEmpty else {
            throw WorkspaceMutationContentObjectSetVerificationError
                .invalidDerivation
        }
        guard limits.validationIssues().isEmpty else {
            throw WorkspaceMutationContentObjectSetVerificationError.invalidLimits
        }
        guard objects.count <= limits.maximumObjectCount else {
            throw WorkspaceMutationContentObjectSetVerificationError
                .objectCountLimitExceeded(
                    actual: objects.count,
                    maximum: limits.maximumObjectCount
                )
        }
        let expected = Dictionary(uniqueKeysWithValues: derivation.contentObjects.map {
            ($0.contentDigest, $0.size)
        })
        var observed: [ContentDigest: UInt64] = [:]
        var totalBytes: UInt64 = 0
        for object in objects {
            guard observed[object.digest] == nil else {
                throw WorkspaceMutationContentObjectSetVerificationError
                    .duplicateObject(object.digest)
            }
            guard let expectedSize = expected[object.digest] else {
                throw WorkspaceMutationContentObjectSetVerificationError
                    .unexpectedObject(object.digest)
            }
            let actualSize = UInt64(object.data.count)
            guard actualSize <= limits.maximumObjectBytes else {
                throw WorkspaceMutationContentObjectSetVerificationError
                    .objectSizeLimitExceeded(
                        digest: object.digest,
                        actual: actualSize,
                        maximum: limits.maximumObjectBytes
                    )
            }
            guard actualSize == expectedSize else {
                throw WorkspaceMutationContentObjectSetVerificationError
                    .objectSizeMismatch(
                        digest: object.digest,
                        actual: actualSize,
                        expected: expectedSize
                    )
            }
            guard WorkspaceMutationFilesystemExecutor.contentDigest(object.data)
                    == object.digest else {
                throw WorkspaceMutationContentObjectSetVerificationError
                    .corruptObject(object.digest)
            }
            let (next, overflow) = totalBytes.addingReportingOverflow(actualSize)
            guard !overflow, next <= limits.maximumTotalBytes else {
                throw WorkspaceMutationContentObjectSetVerificationError
                    .totalByteLimitExceeded(
                        actual: overflow ? UInt64.max : next,
                        maximum: limits.maximumTotalBytes
                    )
            }
            totalBytes = next
            observed[object.digest] = actualSize
        }
        if let missing = expected.keys.sorted(by: {
            $0.rawValue < $1.rawValue
        }).first(where: { observed[$0] == nil }) {
            throw WorkspaceMutationContentObjectSetVerificationError
                .missingObject(missing)
        }
        let canonicalObjects = objects.sorted {
            $0.digest.rawValue < $1.digest.rawValue
        }
        var receipt = WorkspaceMutationContentObjectSetReceipt(
            schemaVersion: 1,
            derivationDigest: derivation.derivationDigest,
            baseSourceRevision: derivation.baseSourceRevision,
            candidateSourceRevision: derivation.candidateSourceRevision,
            contentObjects: derivation.contentObjects,
            objectSetDigest: WorkspaceMutationFilesystemExecutor.objectSetDigest(
                canonicalObjects
            ),
            objectCount: objects.count,
            totalBytes: totalBytes,
            limits: limits,
            receiptDigest: ContentDigest("")
        )
        guard let digest = WorkspaceMutationContentObjectSetReceipt.digest(
            for: receipt
        ) else {
            throw WorkspaceMutationContentObjectSetVerificationError.encodingFailed
        }
        receipt.receiptDigest = digest
        return receipt
    }
}
