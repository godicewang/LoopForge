import AppKit
import Foundation
import Vision

struct WorkspaceFileStamp: Equatable, Sendable {
    let size: Int64
    let modifiedAt: TimeInterval
}

struct VisualInspection: Equatable, Sendable {
    let passedBasicIntegrity: Bool
    let summary: String
    let recognizedText: [String]
}

enum EvidenceCoverageState: String, Equatable, Sendable {
    case candidate = "candidate evidence attached"
    case notObserved = "not observed in attached evidence"
    case notApplicable = "not applicable"
}

struct EvidenceCoverageItem: Equatable, Sendable {
    let requirement: String
    let state: EvidenceCoverageState
    let evidence: [String]
}

struct AuditEvidence: Equatable, Sendable {
    let text: String
    let screenshotPaths: [String]
    let visualInspection: VisualInspection?
    let coverage: [EvidenceCoverageItem]

    init(
        text: String,
        screenshotPaths: [String],
        visualInspection: VisualInspection?,
        coverage: [EvidenceCoverageItem] = []
    ) {
        self.text = text
        self.screenshotPaths = screenshotPaths
        self.visualInspection = visualInspection
        self.coverage = coverage
    }

    var coverageText: String {
        guard !coverage.isEmpty else { return "No deterministic coverage inventory was available." }
        return coverage.map { item in
            let paths = item.evidence.isEmpty ? "none attached" : item.evidence.joined(separator: ", ")
            return "- \(item.requirement): \(item.state.rawValue) · \(paths)"
        }.joined(separator: "\n")
    }
}

struct WorkspaceEvidenceCollector {
    private let ignoredDirectories: Set<String> = [
        ".git", ".build", "build", "dist", "DerivedData", "node_modules", "Pods", ".venv", "venv", "__pycache__"
    ]
    private let reviewableExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "rs", "go", "py", "js", "jsx", "ts", "tsx", "vue",
        "svelte", "java", "kt", "dart", "rb", "php", "cs", "lua", "sh", "html", "css", "scss", "sql",
        "json", "toml", "yaml", "yml", "md"
    ]

    func fingerprint(workspacePath: String) -> [String: WorkspaceFileStamp] {
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        var result: [String: WorkspaceFileStamp] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return result }
        for case let url as URL in enumerator {
            if ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            let relative = relativePath(url, root: root)
            result[relative] = WorkspaceFileStamp(
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            )
        }
        return result
    }

    func collect(
        task: LoopTask,
        workerFeedback: String,
        audit: AuditResult,
        before: [String: WorkspaceFileStamp]
    ) async -> AuditEvidence {
        let workspacePath = task.workspacePath
        let logs = task.logs
        return await Task.detached(priority: .utility) {
            let after = fingerprint(workspacePath: workspacePath)
            let allPaths = Set(before.keys).union(after.keys)
            let changed = allPaths.filter { before[$0] != after[$0] }.sorted()
            let deleted = changed.filter { after[$0] == nil }
            let existingChanged = changed.filter { after[$0] != nil }
            let reviewTargets = boundedReviewTargets(
                changedPaths: existingChanged,
                workspacePath: workspacePath
            )
            let excerpts = sourceExcerpts(paths: reviewTargets, workspacePath: workspacePath)
            let screenshots = screenshotEvidence(
                in: workspacePath,
                changedPaths: before.isEmpty ? nil : Set(changed),
                includeAllImages: task.category == .desktopAutomation
            )
            let visual = task.needsVisualAudit ? inspectScreenshots(screenshots) : nil
            let harness = CommandEvidenceLedger.render(logs: logs)
            let findings = audit.findings.isEmpty ? "None from deterministic scanner." : audit.findings.map { "- \($0)" }.joined(separator: "\n")
            let visualText = visual.map { "\($0.summary)\nOCR sample: \($0.recognizedText.prefix(20).joined(separator: " | "))" }
                ?? "Visual audit is not required for this task."
            let coverage = evidenceCoverage(
                task: task,
                reviewTargets: reviewTargets,
                screenshots: screenshots,
                harness: harness
            )
            let coverageText = coverage.map { item in
                let paths = item.evidence.isEmpty ? "none attached" : item.evidence.joined(separator: ", ")
                return "- \(item.requirement): \(item.state.rawValue) · \(paths)"
            }.joined(separator: "\n")
            let evidenceText = """
            ORIGINAL USER GOAL
            \(task.request)

            SUB AGENT STAGE FEEDBACK
            \(workerFeedback.isEmpty ? "No final worker message was captured." : String(workerFeedback.prefix(12_000)))

            DETERMINISTIC AUDIT
            \(audit.summary)
            \(findings)

            WORKSPACE DELTA
            Changed or newly created files: \(reviewTargets.isEmpty ? "none detected" : reviewTargets.joined(separator: ", "))
            Deleted files: \(deleted.isEmpty ? "none detected" : deleted.joined(separator: ", "))

            RELEVANT CODE AND CONFIG EXCERPTS
            \(excerpts.isEmpty ? "No bounded text excerpt was available." : excerpts)

            HARNESS / BUILD / TEST EVIDENCE
            \(harness.isEmpty ? "No command evidence was captured." : harness)

            VISUAL EVIDENCE
            Paths: \(screenshots.isEmpty ? "none" : screenshots.joined(separator: ", "))
            \(visualText)
            Evidence semantics: dimensions reported above belong to the full rendered screenshot canvas. They are not source-asset dimensions and must never be used to infer an individual building, character, icon, or texture's resolution. Asset-level claims require direct file metadata or source inspection.

            REQUIREMENT-TO-EVIDENCE INVENTORY
            Candidate means the evidence is available for review, not that the requirement is proven.
            “Not observed” means this bounded bundle does not show it; it must never be reported as absent from the product without a targeted workspace inspection.
            \(coverageText)
            """
            return AuditEvidence(
                text: String(evidenceText.prefix(80_000)),
                screenshotPaths: screenshots,
                visualInspection: visual,
                coverage: coverage
            )
        }.value
    }

    private func recentlyModifiedPaths(in workspacePath: String) -> [String] {
        let files = fingerprint(workspacePath: workspacePath)
        return files.keys.sorted { (files[$0]?.modifiedAt ?? 0) > (files[$1]?.modifiedAt ?? 0) }
            .filter { reviewableExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
    }

    private func boundedReviewTargets(changedPaths: [String], workspacePath: String) -> [String] {
        let changedSource = changedPaths.filter {
            reviewableExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }
        let recent = recentlyModifiedPaths(in: workspacePath)
        let stablePriority = recent.filter { path in
            let lower = path.lowercased()
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            return ["readme.md", "package.swift", "package.json", "pyproject.toml", "cargo.toml", "go.mod", "project.yml"]
                .contains(name)
                || lower.contains("/tests/")
                || lower.contains("/test/")
                || name.contains("test")
                || name.contains("spec")
        }
        var result: [String] = []
        var seen = Set<String>()
        for path in changedSource + stablePriority + recent where seen.insert(path).inserted {
            result.append(path)
            if result.count == 18 { break }
        }
        return result
    }

    private func sourceExcerpts(paths: [String], workspacePath: String) -> String {
        var remaining = 48_000
        var sections: [String] = []
        for relative in paths where remaining > 0 {
            let url = URL(fileURLWithPath: workspacePath, isDirectory: true).appendingPathComponent(relative)
            guard reviewableExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  (values.fileSize ?? 0) <= 512_000,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let excerpt = String(text.prefix(min(8_000, remaining)))
            sections.append("--- \(relative) ---\n\(excerpt)")
            remaining -= excerpt.count
        }
        return sections.joined(separator: "\n")
    }

    private func screenshotEvidence(
        in workspacePath: String,
        changedPaths: Set<String>?,
        includeAllImages: Bool
    ) -> [String] {
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var candidates: [(path: String, relative: String, modified: TimeInterval, changed: Bool)] = []
        for case let url as URL in enumerator {
            if ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "webp"].contains(ext) else { continue }
            let relative = relativePath(url, root: root)
            let lower = relative.lowercased()
            guard includeAllImages
                    || lower.contains(".loopforge/evidence")
                    || lower.contains("screenshot")
                    || lower.contains("snapshot")
                    || lower.contains("visual-evidence")
                    || lower.contains("ui-test")
                    || lower.contains("appshot") else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            candidates.append((url.path, relative, modified, changedPaths?.contains(relative) == true))
        }
        let ordered = candidates.sorted {
            if $0.changed != $1.changed { return $0.changed && !$1.changed }
            return $0.modified > $1.modified
        }
        var selected: [String] = []
        var selectedSet = Set<String>()
        var coveredStates = Set<String>()

        // First preserve semantic state diversity across all retained evidence.
        // A later iteration must not erase onboarding, world, failure, or
        // accessibility proof merely because only one new screenshot changed.
        for candidate in ordered {
            let state = screenshotStateKey(candidate.relative)
            guard coveredStates.insert(state).inserted else { continue }
            selected.append(candidate.path)
            selectedSet.insert(candidate.path)
            if selected.count == 12 { return selected }
        }
        // Then fill the bounded bundle with the freshest remaining frames.
        for candidate in ordered where !selectedSet.contains(candidate.path) {
            selected.append(candidate.path)
            if selected.count == 12 { break }
        }
        return selected
    }

    private func screenshotStateKey(_ relativePath: String) -> String {
        let lower = relativePath.lowercased()
        let groups: [(String, [String])] = [
            ("onboarding", ["onboard", "tutorial", "intro", "guide", "引导"]),
            ("core-gameplay", ["battle", "gameplay", "mission", "survival", "tower", "combat", "关卡"]),
            ("building", ["settlement", "city", "build", "home", "领地", "建造"]),
            ("recruitment", ["hero", "recruit", "roster", "招募", "英雄"]),
            ("exploration", ["world", "map", "route", "explore", "世界", "探索"]),
            ("competitive", ["arena", "pvp", "match", "rank", "对战", "竞技"]),
            ("recovery", ["failure", "error", "empty", "offline", "recover", "corrupt", "失败", "空"]),
            ("success", ["success", "complete", "reward", "成功", "奖励"]),
            ("accessibility", ["accessibility", "voiceover", "large-text", "ax3", "reduce-motion"]),
            ("responsive", ["ipad", "iphone", "desktop", "mobile", "narrow", "wide", "responsive"])
        ]
        if let group = groups.first(where: { $0.1.contains(where: lower.contains) }) {
            return group.0
        }
        let stem = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent.lowercased()
            .replacingOccurrences(of: #"^[0-9_-]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        return String(stem.prefix(32))
    }

    private func evidenceCoverage(
        task: LoopTask,
        reviewTargets: [String],
        screenshots: [String],
        harness: String
    ) -> [EvidenceCoverageItem] {
        func sourceCandidates(_ terms: [String]) -> [String] {
            reviewTargets.filter { path in
                let lower = path.lowercased()
                return terms.contains(where: lower.contains)
            }
        }
        func screenshotCandidates(_ terms: [String]) -> [String] {
            screenshots.filter { path in
                let lower = path.lowercased()
                return terms.contains(where: lower.contains)
            }
        }
        func item(_ requirement: String, _ candidates: [String], applicable: Bool = true) -> EvidenceCoverageItem {
            EvidenceCoverageItem(
                requirement: requirement,
                state: applicable ? (candidates.isEmpty ? .notObserved : .candidate) : .notApplicable,
                evidence: Array(candidates.prefix(8))
            )
        }

        let verificationEvidence = harness.lowercased().contains("exit code 0")
            || harness.lowercased().contains("passed")
            || harness.lowercased().contains("build succeeded")
        let interactiveAutomation = task.category == .desktopAutomation
        var result = [
            item(
                interactiveAutomation ? "Requested browser result assets" : "Workspace implementation or primary deliverable",
                interactiveAutomation ? screenshots : reviewTargets
            ),
            item(
                interactiveAutomation ? "Direct target-surface verification" : "Reproducible verification",
                verificationEvidence
                    ? ["captured successful harness output"]
                    : (interactiveAutomation && !screenshots.isEmpty ? ["captured browser result assets"] : [])
            ),
            item(
                "Documentation and handoff",
                sourceCandidates(["readme", "docs/", "report", "delivery"]),
                applicable: !interactiveAutomation
            ),
            item(
                "Regression or recovery coverage",
                sourceCandidates(["test", "spec", "recover", "migration"]),
                applicable: !interactiveAutomation && task.quality != .lightweight
            )
        ]

        if task.needsVisualAudit {
            result.append(item("Running-product primary visual state", screenshots))
            result.append(item(
                "Failure, empty, offline, or recovery visual state",
                screenshotCandidates(["failure", "error", "empty", "offline", "recover", "corrupt", "失败"]),
                applicable: task.quality != .lightweight
            ))
            result.append(item(
                "Accessibility or layout-pressure visual state",
                screenshotCandidates(["accessibility", "voiceover", "large-text", "ipad", "iphone", "responsive", "narrow", "wide"]),
                applicable: task.quality == .high
            ))
        }

        if task.category == .game {
            let request = task.request.lowercased()
            let mentionsOnboarding = ["onboard", "tutorial", "intro", "guide", "story", "引导", "教程", "剧情"]
                .contains(where: request.contains)
            let mentionsProgression = ["recruit", "hero", "building", "build", "progress", "upgrade", "招募", "英雄", "建造", "升级", "领地"]
                .contains(where: request.contains)
            let mentionsWorldOrCompetition = ["world", "explore", "map", "pvp", "battle other", "世界", "探索", "对战", "竞技"]
                .contains(where: request.contains)
            result.append(item(
                "Onboarding or guided introduction",
                screenshotCandidates(["onboard", "tutorial", "intro", "guide", "引导"]),
                applicable: mentionsOnboarding || task.quality != .lightweight
            ))
            result.append(item("Playable core loop", screenshotCandidates(["battle", "gameplay", "mission", "survival", "tower", "combat", "关卡"])))
            result.append(item(
                "Recruitment, building, or progression",
                screenshotCandidates(["hero", "recruit", "settlement", "city", "build", "roster", "招募", "建造"]),
                applicable: mentionsProgression
            ))
            result.append(item(
                "World exploration or competitive play",
                screenshotCandidates(["world", "map", "route", "explore", "arena", "pvp", "match", "世界", "探索", "对战"]),
                applicable: mentionsWorldOrCompetition
            ))
        }
        return result
    }

    private func inspectScreenshots(_ paths: [String]) -> VisualInspection {
        var valid = 0
        var nonBlank = 0
        var descriptions: [String] = []
        var recognized: [String] = []
        for path in paths {
            guard let image = NSImage(contentsOfFile: path),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let width = cgImage.width
            let height = cgImage.height
            let variance = luminanceVariance(of: image)
            if width >= 400 && height >= 300 { valid += 1 }
            if variance >= 0.004 { nonBlank += 1 }
            descriptions.append("\(URL(fileURLWithPath: path).lastPathComponent): \(width)x\(height), luminance variance \(String(format: "%.4f", variance))")

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage)
            if (try? handler.perform([request])) != nil {
                recognized.append(contentsOf: (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.prefix(12))
            }
        }
        let passed = valid > 0 && nonBlank > 0
        let summary = paths.isEmpty
            ? "No real UI screenshot was found in a screenshot/evidence path."
            : "Inspected \(paths.count) screenshot candidate(s); \(valid) had usable dimensions and \(nonBlank) were non-blank. \(descriptions.joined(separator: "; "))"
        return VisualInspection(passedBasicIntegrity: passed, summary: summary, recognizedText: recognized)
    }

    private func luminanceVariance(of image: NSImage) -> Double {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return 0 }
        let stepX = max(1, bitmap.pixelsWide / 32)
        let stepY = max(1, bitmap.pixelsHigh / 24)
        var values: [Double] = []
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                values.append(0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent)
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolvedPath.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(resolvedPath.dropFirst(prefix.count))
    }
}

enum CommandEvidenceLedger {
    static func render(logs: [TaskLogEntry]) -> String {
        let relevant = logs.filter {
            $0.kind == .command || $0.kind == .error || $0.kind == .audit
        }
        guard !relevant.isEmpty else { return "" }

        // Retain both the setup proof and the final verification proof. A pure
        // suffix previously discarded early environment/path checks, while a
        // pure prefix discarded exit codes and test summaries.
        let selected: [TaskLogEntry]
        if relevant.count <= 40 {
            selected = relevant
        } else {
            selected = Array(relevant.prefix(8)) + Array(relevant.suffix(32))
        }

        var rendered: [String] = []
        var seen = Set<String>()
        for entry in selected {
            let clean = sanitizedLogText(entry.message)
            let firstLine = clean.split(separator: "\n", maxSplits: 1)
                .first
                .map(String.init) ?? clean
            let exit = clean
                .split(separator: "\n")
                .last(where: { $0.lowercased().hasPrefix("exit code ") })
                .map(String.init) ?? "exit code not reported"
            let identity = "\(entry.kind.rawValue)|\(firstLine)|\(exit)"
            guard seen.insert(identity).inserted else { continue }
            rendered.append(
                "[\(entry.kind.rawValue)] \(bounded(clean, limit: 2_000))"
            )
        }
        return bounded(rendered.joined(separator: "\n\n"), limit: 48_000)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let headCount = max(1, limit * 2 / 5)
        let tailCount = max(1, limit - headCount - 100)
        return """
        \(text.prefix(headCount))
        … \(text.count - headCount - tailCount) evidence characters omitted; head and tail retained …
        \(text.suffix(tailCount))
        """
    }
}
