import Foundation

enum LoopForgeError: LocalizedError {
    case executableMissing(String)
    case processFailed(String, Int32, String)
    case invalidWorkspace
    case insufficientDiskSpace(requiredGB: Double, availableGB: Double)
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let name): return "The app is missing the \(name) executable. Reinstall the complete build."
        case .processFailed(let name, let code, let detail): return "\(name) exited with code \(code): \(detail)"
        case .invalidWorkspace: return "The selected project folder is invalid or not writable."
        case .insufficientDiskSpace(let required, let available):
            return String(format: "The local model needs approximately %.1fGB of free space; %.1fGB is available.", required, available)
        case .runtimeUnavailable(let detail): return detail
        }
    }
}

enum PathResolver {
    static func bundledExecutable(named name: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let direct = resourceURL.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
            let bin = resourceURL.appendingPathComponent("bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: bin.path) { return bin }
            let runtime = resourceURL.appendingPathComponent("ollama-runtime/\(name)")
            if FileManager.default.isExecutableFile(atPath: runtime.path) { return runtime }
        }
        return nil
    }

    static func executable(named name: String, fallbacks: [String] = []) -> URL? {
        if let bundled = bundledExecutable(named: name) { return bundled }
        for path in fallbacks where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for directory in pathDirectories {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

func safeProjectName(from request: String) -> String {
    let firstLine = request.components(separatedBy: .newlines).first ?? "New Project"
    let replaced = firstLine.replacingOccurrences(of: "[^\\p{L}\\p{N} _-]", with: "", options: .regularExpression)
    let compact = replaced.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    return String((compact.isEmpty ? "New Project" : compact).prefix(28))
}

func sanitizedLogText(_ text: String) -> String {
    var sanitized = text
        .replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        .replacingOccurrences(of: "\u{001B}\\][^\u{0007}]*(\u{0007}|\u{001B}\\\\)", with: "", options: .regularExpression)
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized = sanitized.replacingOccurrences(
        of: #"(?i)\bsk-[a-z0-9._-]{12,}\b"#,
        with: "[REDACTED_API_KEY]",
        options: .regularExpression
    )
    let secretPatterns = [
        #"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s"',}]+"#,
        #"(?i)((?:x-api-key|api[_-]?key|apikey)\s*["']?\s*[:=]\s*["']?)[a-z0-9._-]{12,}"#
    ]
    for pattern in secretPatterns {
        sanitized = sanitized.replacingOccurrences(
            of: pattern,
            with: "$1[REDACTED]",
            options: .regularExpression
        )
    }
    return sanitized
}
