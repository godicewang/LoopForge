import Foundation

/// Canonical, repository-relative path semantics shared by planning and
/// mutation enforcement. It performs no filesystem access and grants no
/// authority.
enum WorkspacePathPolicy {
    static func canonical(_ path: String) -> String? {
        let normalized = path.precomposedStringWithCanonicalMapping
        if path == "." { return "." }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              path.utf8.elementsEqual(normalized.utf8),
              !path.contains("\0"),
              !path.contains(where: { "*?[".contains($0) }) else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components.joined(separator: "/")
    }

    static func contains(scope: String, path: String) -> Bool {
        guard canonical(scope) == scope, canonical(path) == path else { return false }
        if scope == "." { return true }
        return path == scope || path.hasPrefix(scope + "/")
    }

    static func overlaps(_ first: String, _ second: String) -> Bool {
        contains(scope: first, path: second) || contains(scope: second, path: first)
    }
}
