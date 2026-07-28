import AppKit
import Combine
import Foundation

struct CodexReasoningOption: Codable, Equatable, Identifiable {
    let effort: String
    let description: String

    var id: String { effort }
    var title: String {
        switch effort {
        case "xhigh": return "Extra High"
        case "ultra": return "Ultra"
        case "max": return "Maximum"
        default: return effort.capitalized
        }
    }
}

struct CodexModelOption: Codable, Equatable, Identifiable {
    let slug: String
    let displayName: String
    let description: String
    let supportedReasoningLevels: [CodexReasoningOption]
    let visibility: String
    let priority: Int

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case description
        case supportedReasoningLevels = "supported_reasoning_levels"
        case visibility
        case priority
    }

    static let fallback = CodexModelOption(
        slug: AppConstants.officialWorkerModel,
        displayName: "GPT-5.6 Sol",
        description: "Latest frontier agentic coding model.",
        supportedReasoningLevels: [
            CodexReasoningOption(effort: "low", description: "Fast responses with lighter reasoning"),
            CodexReasoningOption(effort: "medium", description: "Balanced reasoning"),
            CodexReasoningOption(effort: "high", description: "Deeper reasoning for complex tasks"),
            CodexReasoningOption(effort: "xhigh", description: "Very deep reasoning"),
            CodexReasoningOption(effort: "max", description: "Maximum single-agent reasoning"),
            CodexReasoningOption(effort: "ultra", description: "Maximum reasoning with automatic task delegation")
        ],
        visibility: "list",
        priority: 1
    )
}

enum CodexCatalog {
    private struct Envelope: Decodable { let models: [CodexModelOption] }
    private static let strengthOrder = ["ultra", "max", "xhigh", "high", "medium", "low", "minimal", "none"]

    static func decode(_ data: Data) throws -> [CodexModelOption] {
        let decoded = try JSONDecoder().decode(Envelope.self, from: data).models
        return decoded
            .filter { $0.visibility == "list" }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.slug < rhs.slug : lhs.priority < rhs.priority
            }
    }

    static func strongestReasoning(for model: CodexModelOption) -> String {
        for effort in strengthOrder where model.supportedReasoningLevels.contains(where: { $0.effort == effort }) {
            return effort
        }
        return model.supportedReasoningLevels.last?.effort ?? "high"
    }

    static func recommendedModel(in models: [CodexModelOption]) -> CodexModelOption {
        models.first(where: { $0.slug == AppConstants.officialWorkerModel })
            ?? models.first
            ?? .fallback
    }
}

enum CodexConnectionPhase: Int, Equatable {
    case idle
    case locating
    case checkingVersion
    case checkingAuthentication
    case loadingModels
    case signingIn
    case ready
    case failed

    var title: String {
        switch self {
        case .idle: return "Waiting"
        case .locating: return "Finding Codex"
        case .checkingVersion: return "Checking version"
        case .checkingAuthentication: return "Verifying sign-in"
        case .loadingModels: return "Loading capabilities"
        case .signingIn: return "Waiting for sign-in"
        case .ready: return "Codex is ready"
        case .failed: return "Connection needed"
        }
    }
}

enum CodexCatalogSource: String {
    case live = "Live catalog"
    case bundled = "Version catalog"
    case fallback = "Built-in fallback"
}

enum CodexRuntime {
    static var executable: URL? {
        let hostCandidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        for path in hostCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return PathResolver.bundledExecutable(named: "codex")
    }

    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        let usefulPaths = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        environment["PATH"] = (usefulPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
        return environment
    }
}

@MainActor
final class CodexConnectionManager: ObservableObject {
    @Published private(set) var phase: CodexConnectionPhase = .idle
    @Published private(set) var detail = "Preparing the official Codex connection"
    @Published private(set) var version = ""
    @Published private(set) var authentication = ""
    @Published private(set) var models: [CodexModelOption] = [.fallback]
    @Published private(set) var catalogSource: CodexCatalogSource = .fallback
    @Published private(set) var executablePath = ""
    @Published private(set) var errorMessage: String?
    @Published var gateDismissed: Bool

    private let runner = ProcessRunner()
    private let defaults: UserDefaults
    private var connectionTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.gateDismissed = defaults.bool(forKey: AppConstants.codexOnboardingKey)
    }

    var isConnected: Bool { phase == .ready }
    var shouldBlockInterface: Bool { !gateDismissed || phase == .signingIn }
    var recommendedModel: CodexModelOption { CodexCatalog.recommendedModel(in: models) }
    var recommendedReasoning: String { CodexCatalog.strongestReasoning(for: recommendedModel) }

    func start() {
        guard connectionTask == nil else { return }
        connectionTask = Task { [weak self] in
            await self?.connect()
            self?.connectionTask = nil
        }
    }

    func reconnect(showProgress: Bool = true) {
        connectionTask?.cancel()
        connectionTask = nil
        if showProgress { gateDismissed = false }
        start()
    }

    func presentStatus() { gateDismissed = false }

    func dismissReadyState() {
        guard isConnected else { return }
        gateDismissed = true
        defaults.set(true, forKey: AppConstants.codexOnboardingKey)
    }

    func continueWithoutCodex() {
        guard phase == .failed else { return }
        gateDismissed = true
        defaults.set(true, forKey: AppConstants.codexOnboardingKey)
    }

    func signIn() {
        guard connectionTask == nil, let executable = CodexRuntime.executable else {
            fail("The official Codex executable could not be found.")
            return
        }
        gateDismissed = false
        phase = .signingIn
        detail = "Complete the secure ChatGPT sign-in in your browser"
        errorMessage = nil
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await runner.run(
                    executable: executable,
                    arguments: ["login", "--device-auth"],
                    environment: CodexRuntime.environment(),
                    onStdout: { line in
                        let clean = sanitizedLogText(line)
                        guard !clean.isEmpty else { return }
                        Task { @MainActor [weak self] in self?.detail = clean }
                    },
                    onStderr: { line in
                        let clean = sanitizedLogText(line)
                        guard !clean.isEmpty else { return }
                        Task { @MainActor [weak self] in self?.detail = clean }
                    }
                )
                guard result.exitCode == 0 else {
                    fail("Sign-in did not finish. Try again or use the manual command below.")
                    connectionTask = nil
                    return
                }
                await connect()
            } catch {
                fail("Sign-in could not start: \(error.localizedDescription)")
            }
            connectionTask = nil
        }
    }

    func copyManualCommand() {
        let executable = CodexRuntime.executable?.path ?? "codex"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\"\(executable)\" login", forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        detail = "The sign-in command was copied. Paste it into Terminal and press Return."
    }

    private func connect() async {
        errorMessage = nil
        phase = .locating
        detail = "Finding the bundled or installed Codex CLI"
        guard let executable = CodexRuntime.executable else {
            fail("LoopForge could not find its bundled Codex CLI or an installed Codex executable.")
            return
        }
        executablePath = executable.path

        do {
            phase = .checkingVersion
            detail = "Checking Codex version"
            let versionResult = try await runner.run(
                executable: executable,
                arguments: ["--version"],
                environment: CodexRuntime.environment()
            )
            guard versionResult.exitCode == 0 else {
                fail("Codex was found but could not be started.")
                return
            }
            version = sanitizedLogText(versionResult.stdout).trimmingCharacters(in: .whitespacesAndNewlines)

            phase = .checkingAuthentication
            detail = "Verifying your ChatGPT sign-in"
            let loginResult = try await runner.run(
                executable: executable,
                arguments: ["login", "status"],
                environment: CodexRuntime.environment()
            )
            authentication = sanitizedLogText([loginResult.stdout, loginResult.stderr].joined(separator: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard loginResult.exitCode == 0 else {
                fail("Codex is installed, but it is not signed in.")
                return
            }

            phase = .loadingModels
            detail = "Loading models and reasoning levels"
            let live = try await runner.run(
                executable: executable,
                arguments: ["debug", "models"],
                environment: CodexRuntime.environment()
            )
            if live.exitCode == 0,
               let data = live.stdout.data(using: .utf8),
               let decoded = try? CodexCatalog.decode(data), !decoded.isEmpty {
                models = decoded
                catalogSource = .live
            } else {
                let bundled = try await runner.run(
                    executable: executable,
                    arguments: ["debug", "models", "--bundled"],
                    environment: CodexRuntime.environment()
                )
                if bundled.exitCode == 0,
                   let data = bundled.stdout.data(using: .utf8),
                   let decoded = try? CodexCatalog.decode(data), !decoded.isEmpty {
                    models = decoded
                    catalogSource = .bundled
                } else {
                    models = [.fallback]
                    catalogSource = .fallback
                }
            }

            phase = .ready
            detail = "\(recommendedModel.displayName) · \(recommendedReasoning.capitalized) reasoning"
            if !defaults.bool(forKey: AppConstants.codexOnboardingKey) {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if !Task.isCancelled { dismissReadyState() }
            }
        } catch {
            fail("Codex connection failed: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        phase = .failed
        detail = "Codex needs a quick setup"
        errorMessage = message
        gateDismissed = false
    }
}
