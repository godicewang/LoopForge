import Foundation

/// Process-wide startup policy selected before any durable store or recovery
/// coordinator is constructed. The isolated profile is intentionally opt-in:
/// it gives native UI audits an empty Application Support root, so opening the
/// signed app cannot resume or rewrite a user's persisted tasks, Watchers,
/// leases, or kernel journals.
enum LoopForgeLaunchProfile: Equatable {
    static let isolatedInspectionArgument = "--isolated-inspection-profile"

    case standard
    case isolatedInspection(applicationSupportDirectory: URL)

    static let current = resolve(
        arguments: CommandLine.arguments,
        temporaryDirectory: FileManager.default.temporaryDirectory,
        processIdentifier: ProcessInfo.processInfo.processIdentifier
    )

    static func resolve(
        arguments: [String],
        temporaryDirectory: URL,
        processIdentifier: Int32
    ) -> LoopForgeLaunchProfile {
        guard arguments.contains(isolatedInspectionArgument) else {
            return .standard
        }
        let root = temporaryDirectory
            .standardizedFileURL
            .appendingPathComponent("LoopForgeInspection", isDirectory: true)
            .appendingPathComponent("Process-\(processIdentifier)", isDirectory: true)
        return .isolatedInspection(applicationSupportDirectory: root)
    }

    var isIsolatedInspection: Bool {
        if case .isolatedInspection = self { return true }
        return false
    }

    var applicationSupportDirectory: URL? {
        guard case let .isolatedInspection(directory) = self else { return nil }
        return directory
    }
}
