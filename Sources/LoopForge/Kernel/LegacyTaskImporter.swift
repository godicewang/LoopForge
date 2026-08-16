import CryptoKit
import Foundation

struct LegacyClaim: Codable, Hashable, Sendable {
    var field: String
    var value: String
}

struct LegacyDurationObservation: Codable, Hashable, Sendable {
    var field: String
    var rawSeconds: Double
    var acceptedSeconds: Double
    var disposition: String
}

struct LegacyTaskObservation: Codable, Hashable, Sendable {
    var rawArtifactDigest: ContentDigest
    var historicalID: String?
    var objectiveClaim: String?
    var claims: [LegacyClaim]
    var durationObservations: [LegacyDurationObservation]
    var acceptedReceiptIDs: Set<ReceiptID>
    var mayAutoResume: Bool
}

enum LegacyTaskImporterError: Error, Equatable {
    case invalidTopLevel
}

/// Imports old snapshots as read-only claims. It intentionally does not decode
/// them into authoritative KernelRunState or infer acceptance from prose,
/// status, dates, scores, command exits, or elapsed-duration fields.
enum LegacyTaskImporter {
    static func importRaw(_ data: Data) throws -> [LegacyTaskObservation] {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let records: [[String: Any]]
        if let array = object as? [[String: Any]] {
            records = array
        } else if let dictionary = object as? [String: Any] {
            records = [dictionary]
        } else {
            throw LegacyTaskImporterError.invalidTopLevel
        }

        let digest = ContentDigest(SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined())
        return records.map { record in
            let historicalID = scalarString(record["id"])
            let objective = scalarString(record["originalRequest"])
                ?? scalarString(record["request"])
            let claimFields = [
                "status", "stage", "lastAgentMessage", "auditSummary",
                "lastReview", "reportPath", "threadID"
            ]
            let claims = claimFields.compactMap { field -> LegacyClaim? in
                guard let value = scalarString(record[field]), !value.isEmpty else { return nil }
                return LegacyClaim(field: field, value: value)
            }
            let durationFields = [
                "targetSeconds", "accumulatedCodexSeconds", "activeRuntimeSeconds",
                "coveredSeconds", "durationSeconds"
            ]
            let durations = durationFields.compactMap { field -> LegacyDurationObservation? in
                guard let number = record[field] as? NSNumber else { return nil }
                return LegacyDurationObservation(
                    field: field,
                    rawSeconds: number.doubleValue,
                    acceptedSeconds: 0,
                    disposition: "unverifiedLegacyObservation"
                )
            }
            return LegacyTaskObservation(
                rawArtifactDigest: digest,
                historicalID: historicalID,
                objectiveClaim: objective,
                claims: claims,
                durationObservations: durations,
                acceptedReceiptIDs: [],
                mayAutoResume: false
            )
        }
    }

    private static func scalarString(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}
