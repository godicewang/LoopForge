import Foundation

struct WorkspaceAuditor {
    private let ignoredDirectories: Set<String> = [
        ".git", ".build", "build", "dist", "DerivedData", "node_modules", "Pods", ".venv", "venv", "__pycache__"
    ]

    private let sourceExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "rs", "go", "py", "js", "jsx", "ts", "tsx", "vue", "svelte",
        "java", "kt", "kts", "dart", "rb", "php", "cs", "lua", "sh", "zsh", "html", "css", "scss", "sql", "ipynb"
    ]

    func snapshot(workspacePath: String, logs: [TaskLogEntry]) -> WorkspaceSnapshot {
        let root = URL(fileURLWithPath: workspacePath)
        var result = WorkspaceSnapshot()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return result }

        for case let fileURL as URL in enumerator {
            if ignoredDirectories.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            result.totalFiles += 1
            if result.samplePaths.count < 18 { result.samplePaths.append(relative) }

            let lower = fileURL.lastPathComponent.lowercased()
            let ext = fileURL.pathExtension.lowercased()
            if sourceExtensions.contains(ext) {
                result.sourceFiles += 1
                result.sourceBytes += Int64(values?.fileSize ?? 0)
                if isConventionalExecutionEntryPoint(fileURL: fileURL, relativePath: relative, extension: ext) {
                    result.executionEntryPointFiles += 1
                }
            }
            if lower.contains("test") || relative.lowercased().contains("tests/") || relative.lowercased().contains("spec/") {
                result.testFiles += 1
            }
            if ["readme.md", "readme", "usage.md", "docs.md", "report.md", "diagnosis.md", "audit.md"].contains(lower)
                || relative.lowercased().hasPrefix("docs/")
                || (ext == "md" && (lower.contains("report") || lower.contains("delivery") || lower.contains("diagnosis") || lower.contains("audit"))) {
                result.documentationFiles += 1
            }
            if ["package.json", "pyproject.toml", "setup.py", "requirements.txt", "package.swift", "cargo.toml", "go.mod", "makefile", "cmakelists.txt", "project.yml", "podfile"].contains(lower)
                || (lower == "project.pbxproj" && relative.lowercased().contains(".xcodeproj/"))
                || (lower == "contents.xcworkspacedata" && relative.lowercased().contains(".xcworkspace/")) {
                result.manifestFiles += 1
            }
            if ["csv", "json", "jsonl", "parquet", "png", "pdf", "md", "txt"].contains(ext) &&
                (relative.lowercased().contains("result") || relative.lowercased().contains("report") || relative.lowercased().contains("output")) {
                result.resultFiles += 1
            }
            if ["png", "jpg", "jpeg", "webp"].contains(ext) {
                if isVisualEvidencePath(relative) {
                    result.screenshotFiles += 1
                } else {
                    result.imageFiles += 1
                }
            }
        }

        for log in logs.suffix(160) where log.kind == .command || log.kind == .error {
            let text = log.message.lowercased()
            let verificationTerms = [
                "test", "pytest", "unittest", "swift build", "swift run", "xcodebuild", "npm run", "pnpm ", "yarn ",
                "cargo test", "cargo build", "go test", "make ", "cmake", "python -m", "python3 -m", "baseline", "benchmark",
                "python3 ", "python ", "node ", "bash ", "zsh ", "./", "lint", "typecheck", "type-check", "check ",
                "curl ", "verify", "build succeeded", "tests passed"
            ]
            let isVerification = verificationTerms.contains { text.contains($0) }
            let succeeded = isVerification
                && (text.contains("exit code 0") || text.contains("passed") || text.contains("build succeeded") || text.contains("tests passed"))
            let failed = isVerification
                && ((text.contains("exit code") && !text.contains("exit code 0"))
                    || text.contains("command failed") || text.contains("build failed") || text.contains("tests failed"))
            if succeeded {
                result.recentCommandSuccesses += 1
                result.lastVerificationSucceeded = true
                // A later successful real verification supersedes earlier
                // failures in the same bounded timeline. This avoids treating a
                // repaired build as unresolved simply because it needed several
                // failed attempts before the final green run.
                result.unresolvedVerificationFailures = 0
            }
            if failed {
                result.recentCommandFailures += 1
                result.lastVerificationSucceeded = false
                result.unresolvedVerificationFailures += 1
            }
        }
        return result
    }

    func audit(task: LoopTask, requireVisualApproval: Bool = true) -> AuditResult {
        // Auto Graph node loops retain their command evidence and completion
        // declaration on the node, not on the legacy single-loop task fields.
        // Audit one chronological evidence stream so a graph that has already
        // passed every node is not sent into a synthetic repair loop merely
        // because the task-level message/log arrays are intentionally sparse.
        let graphLogs = task.graphState?.nodes.flatMap(\.logs) ?? []
        let evidenceLogs = (task.logs + graphLogs).sorted { $0.timestamp < $1.timestamp }
        let snap = snapshot(workspacePath: task.workspacePath, logs: evidenceLogs)
        let graphResponses = task.graphState?.nodes.flatMap {
            [$0.lastAgentMessage, $0.lastReview]
        } ?? []
        let response = ([task.lastAgentMessage] + graphResponses)
            .joined(separator: "\n")
            .lowercased()
        let claimsComplete = response.contains("loopforge_status: complete")
        let authorization = TaskEstimator().inferAuthorization(task.request.lowercased())
        let requiresImplementation = authorization == .buildOrModify
        let isInteractiveAutomation = task.category == .desktopAutomation
        let expectedImageCount = expectedImageOutputCount(in: task.request)
        let hasInteractiveDeliverable = expectedImageCount.map { snap.imageFiles >= $0 } ?? (snap.imageFiles > 0)
        let hasImplementation = snap.sourceFiles > 0 && snap.sourceBytes >= 30
        let hasReportDeliverable = snap.documentationFiles > 0 || snap.resultFiles > 0
        let hasPrimaryDeliverable = isInteractiveAutomation
            ? hasInteractiveDeliverable
            : (requiresImplementation ? hasImplementation : hasReportDeliverable)
        let hasVerification = snap.recentCommandSuccesses > 0 || (isInteractiveAutomation && hasInteractiveDeliverable)
        let documentationSatisfied = isInteractiveAutomation || snap.documentationFiles > 0
        let hasEntryPoint = isInteractiveAutomation
            || !requiresImplementation
            || snap.manifestFiles > 0
            || (task.category == .script && hasImplementation)
            || snap.executionEntryPointFiles > 0
            || (hasImplementation && snap.documentationFiles > 0 && hasVerification)
        let hasRegressionEvidence = isInteractiveAutomation
            || snap.testFiles > 0
            || ((task.category == .experiment || task.category == .data || task.category == .research) && snap.resultFiles > 0)
        let requiresMeasuredResult = task.category == .optimization
            || task.category == .experiment
            || task.category == .data
            || task.category == .research
        let hasMeasuredResult = !requiresMeasuredResult || snap.resultFiles > 0
        let hasUnresolvedFailures = snap.unresolvedVerificationFailures > 0
        let hasVisualEvidence = !task.needsVisualAudit
            || snap.screenshotFiles > 0
            || (isInteractiveAutomation && snap.imageFiles > 0)
        let hasVisualApproval = !task.needsVisualAudit || !requireVisualApproval || task.visualAuditPassed == true

        var score = 0
        var findings: [String] = []
        var next: [String] = []

        if hasPrimaryDeliverable { score += 20 } else {
            if isInteractiveAutomation {
                let expected = expectedImageCount.map(String.init) ?? "the requested"
                findings.append("The browser workflow has not produced \(expected) downloaded or generated image result(s) in the workspace")
                next.append("Complete the actions in the exact user-named browser session and save every requested result into the workspace")
            } else {
                findings.append(requiresImplementation ? "No substantive implementation was found" : "No substantive report or result deliverable was found")
                next.append(requiresImplementation ? "Create or repair the runnable core deliverable" : "Produce the requested evidence-backed report or result artifact")
            }
        }
        if documentationSatisfied { score += 15 } else {
            findings.append("Reproducible usage or review documentation is missing")
            next.append("Document the exact setup, usage, assumptions, and verification path")
        }
        if hasEntryPoint { score += 10 } else {
            findings.append("A reproducible build, dependency, or execution entry point is missing")
            next.append("Add a manifest, build configuration, or one-command execution entry point")
        }

        if hasRegressionEvidence {
            score += 15
        } else if task.quality != .lightweight {
            findings.append("Automated regression coverage or reproducible result artifacts are missing")
            next.append(task.category == .experiment || task.category == .data || task.category == .research
                ? "Run the baseline and retain machine-readable results"
                : "Add automated regression coverage for the primary behavior")
        } else {
            score += 5
        }

        if hasVerification { score += 20 } else {
            findings.append("No successful real verification command was captured")
            next.append("Run the real primary-path build, test, experiment, or smoke command and retain its actual outcome")
        }
        if !hasMeasuredResult {
            findings.append("The task requires a retained result, report, metric, or benchmark artifact")
            next.append("Save reproducible machine-readable results or a clearly named benchmark/report artifact")
        }
        if !hasUnresolvedFailures { score += 10 } else {
            findings.append("Recent failed commands remain unresolved by successful verification")
            next.append("Fix the root cause, rerun the original failure, and then run an adjacent regression scenario")
        }
        if claimsComplete { score += 10 } else {
            findings.append("Codex has not made the exact evidence-backed completion declaration")
            next.append("Review every acceptance item and emit LOOPFORGE_STATUS: COMPLETE only after the evidence supports it")
        }
        if !hasVisualEvidence {
            findings.append("No real rendered-product screenshot was found for this visual task")
            next.append("Launch the actual UI and save fresh primary and important state screenshots under .loopforge/evidence/iteration-N")
        } else if requireVisualApproval && !hasVisualApproval {
            findings.append("The local visual supervisor has not approved the current screenshots against the user goal")
            next.append("Address the visual review findings, rerun the UI harness, and capture updated screenshots")
        }

        score = min(100, score)
        let hardGatesPassed = hasPrimaryDeliverable
            && documentationSatisfied
            && hasEntryPoint
            && hasVerification
            && !hasUnresolvedFailures
            && hasMeasuredResult
            && claimsComplete
            && hasVisualEvidence
            && hasVisualApproval
            && (task.quality == .lightweight || task.quality == .low || hasRegressionEvidence)
        let passed = hardGatesPassed && score >= task.quality.completionThreshold
        let summary = passed
            ? "All required \(task.quality.title) evidence gates passed."
            : "One or more \(task.quality.title) evidence gates still need verified work."
        return AuditResult(score: score, passed: passed, summary: summary, findings: findings, nextActions: next)
    }

    private func isVisualEvidencePath(_ relativePath: String) -> Bool {
        let lower = relativePath.lowercased()
        return lower.contains(".loopforge/evidence") || lower.contains("screenshot") || lower.contains("snapshot")
            || lower.contains("visual-evidence") || lower.contains("ui-test") || lower.contains("appshot")
    }

    private func expectedImageOutputCount(in request: String) -> Int? {
        let patterns = [
            #"(?i)(\d+)\s*(?:张|幅|images?|photos?|pictures?)"#,
            #"(?i)(?:一共|总共|共)\s*(\d+)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: request,
                    range: NSRange(request.startIndex..., in: request)
                  ),
                  let range = Range(match.range(at: 1), in: request),
                  let value = Int(request[range]),
                  value > 0 else { continue }
            return value
        }
        if request.contains("十张") || request.lowercased().contains("ten images")
            || request.lowercased().contains("ten photos") {
            return 10
        }
        return nil
    }

    private func isConventionalExecutionEntryPoint(fileURL: URL, relativePath: String, extension ext: String) -> Bool {
        let lowerPath = relativePath.lowercased()
        let lowerName = fileURL.lastPathComponent.lowercased()
        if lowerName == "__main__.py" || lowerPath == "index.html" || lowerName == "main.rs" || lowerName == "main.go" {
            return true
        }
        guard let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 256_000,
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        switch ext {
        case "py":
            return contents.contains("if __name__") && contents.contains("__main__")
        case "swift":
            return contents.contains("@main")
        case "js", "jsx", "ts", "tsx":
            return lowerName.hasPrefix("main.") || lowerName.hasPrefix("cli.")
        case "sh", "zsh":
            return contents.hasPrefix("#!")
        default:
            return false
        }
    }
}
