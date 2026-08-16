import Foundation

/// A provider- and domain-neutral stable identity used by the orchestration
/// kernel. The phantom domain prevents accidental cross-identity comparison
/// while the encoded representation remains a single string.
struct StableKernelID<Domain>: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum RunIDDomain: Sendable {}
enum ContractIDDomain: Sendable {}
enum RequirementIDDomain: Sendable {}
enum BaselineIDDomain: Sendable {}
enum EvidenceRecipeIDDomain: Sendable {}
enum CommandIDDomain: Sendable {}
enum EventIDDomain: Sendable {}
enum NodeIDDomain: Sendable {}
enum AttemptIDDomain: Sendable {}
enum ReceiptIDDomain: Sendable {}
enum ActorIDDomain: Sendable {}
enum StrategyIDDomain: Sendable {}
enum ResourceIDDomain: Sendable {}
enum OccurrenceIDDomain: Sendable {}
enum BootSessionIDDomain: Sendable {}
enum ScheduleIDDomain: Sendable {}
enum ResourceLeaseIDDomain: Sendable {}
enum DesignBaselineIDDomain: Sendable {}
enum NativeCaptureIDDomain: Sendable {}
enum VisualCellIDDomain: Sendable {}
enum DesignDebtIDDomain: Sendable {}
enum WorkspaceIDDomain: Sendable {}
enum MutationCandidateIDDomain: Sendable {}
enum IntegrationTransactionIDDomain: Sendable {}
enum PublicationTransactionIDDomain: Sendable {}
enum IntegrationEffectIntentIDDomain: Sendable {}
enum TaskContractSourceIDDomain: Sendable {}
enum TaskContractAmbiguityIDDomain: Sendable {}
enum ExternalDependencyIDDomain: Sendable {}
enum ExternalDependencyEvidenceRecipeIDDomain: Sendable {}

typealias KernelRunID = StableKernelID<RunIDDomain>
typealias TaskContractID = StableKernelID<ContractIDDomain>
typealias RequirementID = StableKernelID<RequirementIDDomain>
typealias BaselineID = StableKernelID<BaselineIDDomain>
typealias EvidenceRecipeID = StableKernelID<EvidenceRecipeIDDomain>
typealias RunCommandID = StableKernelID<CommandIDDomain>
typealias OrchestrationEventID = StableKernelID<EventIDDomain>
typealias KernelNodeID = StableKernelID<NodeIDDomain>
typealias AttemptID = StableKernelID<AttemptIDDomain>
typealias ReceiptID = StableKernelID<ReceiptIDDomain>
typealias ActorID = StableKernelID<ActorIDDomain>
typealias StrategyFingerprint = StableKernelID<StrategyIDDomain>
typealias OwnedResourceID = StableKernelID<ResourceIDDomain>
typealias OccurrenceID = StableKernelID<OccurrenceIDDomain>
typealias BootSessionID = StableKernelID<BootSessionIDDomain>
typealias ScheduleID = StableKernelID<ScheduleIDDomain>
typealias ResourceLeaseID = StableKernelID<ResourceLeaseIDDomain>
typealias DesignBaselineID = StableKernelID<DesignBaselineIDDomain>
typealias NativeCaptureID = StableKernelID<NativeCaptureIDDomain>
typealias VisualCellID = StableKernelID<VisualCellIDDomain>
typealias DesignDebtID = StableKernelID<DesignDebtIDDomain>
typealias WorkspaceID = StableKernelID<WorkspaceIDDomain>
typealias MutationCandidateID = StableKernelID<MutationCandidateIDDomain>
typealias IntegrationTransactionID = StableKernelID<IntegrationTransactionIDDomain>
typealias PublicationTransactionID = StableKernelID<PublicationTransactionIDDomain>
typealias IntegrationEffectIntentID = StableKernelID<IntegrationEffectIntentIDDomain>
typealias TaskContractSourceID = StableKernelID<TaskContractSourceIDDomain>
typealias TaskContractAmbiguityID = StableKernelID<TaskContractAmbiguityIDDomain>
typealias ExternalDependencyID = StableKernelID<ExternalDependencyIDDomain>
typealias ExternalDependencyEvidenceRecipeID =
    StableKernelID<ExternalDependencyEvidenceRecipeIDDomain>

struct ContentDigest: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

struct ActorIdentity: Codable, Hashable, Sendable {
    var id: ActorID
    var role: String
    var lineageDigest: ContentDigest
}

struct KernelCommandContext: Codable, Hashable, Sendable {
    var commandID: RunCommandID
    var expectedSequence: UInt64
    var issuedAt: Date
    var actor: ActorIdentity
}
