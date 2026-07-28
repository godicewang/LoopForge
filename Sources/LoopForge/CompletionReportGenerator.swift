import Foundation

struct ReportEvaluationItem: Codable, Equatable {
    let dimension: String
    let score: Int
    let evidence: String
}

struct CompletionReportNarrative: Codable, Equatable {
    let executiveSummary: String
    let completedWork: [String]
    let currentExperience: String
    let notableChanges: [String]
    let evaluation: [ReportEvaluationItem]
    let limitations: [String]
    let recommendedNextSteps: [String]
}

struct CompletionReportGenerator {
    func generate(
        task: LoopTask,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot,
        narrative: CompletionReportNarrative? = nil,
        isFinal: Bool = true
    ) throws -> String {
        let root = URL(fileURLWithPath: task.workspacePath, isDirectory: true)
            .appendingPathComponent(".loopforge/reports/\(task.id.uuidString.lowercased())", isDirectory: true)
        let media = root.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

        let gallery = try copiedGallery(task: task, media: media)
        let baseline = task.reportBaseline
        let progress = task.resolvedExecutionMode != .singleLoop
            ? task.progress
            : min(1, task.accumulatedCodexSeconds / max(1, task.targetSeconds))
        let statusTitle = isFinal ? "Completed and verified" : task.status.title
        let statusClass = isFinal ? "ok" : (task.status.isWorking ? "working" : "hold")
        let generated = ISO8601DateFormatter().string(from: Date())

        let groundedNarrative = narrative ?? deterministicNarrative(task: task, audit: audit)
        let graphLogs = task.graphState?.nodes.flatMap(\.logs) ?? []
        let reportLogs = (task.logs + graphLogs).sorted { $0.timestamp < $1.timestamp }
        let completedHTML = list(groundedNarrative.completedWork)
        let changeHTML = list(groundedNarrative.notableChanges)
        let limitationHTML = list(groundedNarrative.limitations.isEmpty ? ["No verified limitation was retained."] : groundedNarrative.limitations)
        let nextHTML = list(groundedNarrative.recommendedNextSteps.isEmpty ? audit.nextActions : groundedNarrative.recommendedNextSteps)
        let coverageHTML = list(task.lastEvidenceCoverage ?? ["Evidence inventory will populate after the next control audit."])
        let workspaceHTML = list(snapshot.samplePaths.prefix(20).map { "<code>\(html($0))</code>" }, alreadyEscaped: true)
        let auditHTML = list(reportLogs.filter { $0.kind == .audit }.suffix(14).map(\.message))
        let commandHTML = list(reportLogs.filter { $0.kind == .command }.suffix(14).map(\.message))
        let timelineHTML = reportLogs.filter { $0.kind == .control }.suffix(20).enumerated().map { index, entry in
            """
            <article class="timeline"><span>\(index + 1)</span><div><h3>Instruction \(index + 1)</h3><p>\(html(entry.message))</p></div></article>
            """
        }.joined(separator: "\n")
        let graphHTML = task.graphState?.nodes.map { node in
            let statusClass = node.status == .completed
                ? "ok"
                : (
                    node.status == .blocked
                        || node.status == .failed
                        || node.status == .superseded
                        ? "blocked"
                        : "working"
                )
            return """
            <article class="graph-node \(statusClass)">
              <div class="graph-node-head"><strong>\(html(node.title))</strong><span>\(html(node.status.title))</span></div>
              <p>\(html(node.objective))</p>
              <div class="graph-node-meta"><span>Iterations \(node.iteration)</span><span>\(node.accumulatedActiveSeconds.compactDuration) active</span><span>\(html(node.workspaceStrategy?.title ?? "Workspace"))</span></div>
              \(node.lastReview.isEmpty ? "" : "<small>\(html(node.lastReview))</small>")
              \(node.supersededReason.map { "<small>Replanned: \(html($0))</small>" } ?? "")
              \((node.supersededByNodeIDs ?? []).isEmpty ? "" : "<small>Replacement: \(html((node.supersededByNodeIDs ?? []).joined(separator: ", ")))</small>")
            </article>
            """
        }.joined(separator: "\n") ?? ""
        let graphPerformanceHTML: String
        if let graph = task.graphState, !graph.nodes.isEmpty {
            let totalIterations = graph.nodes.reduce(0) { $0 + $1.iteration }
            let totalActive = graph.nodes.reduce(0) { $0 + $1.accumulatedActiveSeconds }
            let criticalPath = criticalPathActiveSeconds(nodes: graph.nodes)
            let parallelFactor = criticalPath > 0 ? totalActive / criticalPath : 1
            graphPerformanceHTML = """
            <section><div class="card"><h2>\(task.resolvedExecutionMode == .parallelCandidates ? "Candidate performance" : "Graph performance")</h2><div class="grid graph-metrics">
              <div class="metric"><b>\(graph.nodes.count)</b><small>\(task.resolvedExecutionMode == .parallelCandidates ? "independent candidates" : "materialized nodes")</small></div>
              <div class="metric"><b>\(totalIterations)</b><small>\(task.resolvedExecutionMode == .parallelCandidates ? "candidate iterations" : "Sub Agent iterations")</small></div>
              <div class="metric"><b>\(criticalPath.compactDuration)</b><small>dependency critical path</small></div>
              <div class="metric"><b>\(String(format: "%.2f×", parallelFactor))</b><small>parallel work factor</small></div>
            </div><p class="method">Total node-active work: \(totalActive.compactDuration). The factor compares summed node-active time with the longest dependency path; it is not a claim about model cost or wall-clock speedup.</p></div></section>
            """
        } else {
            graphPerformanceHTML = ""
        }
        let evaluationHTML = groundedNarrative.evaluation.map { item in
            let score = min(100, max(0, item.score))
            return """
            <div class="score-row"><div><strong>\(html(item.dimension))</strong><small>\(html(item.evidence))</small></div>
            <div class="score"><b>\(score)</b><span>/100</span></div></div>
            """
        }.joined(separator: "\n")
        let galleryHTML = gallery.map {
            """
            <figure><button class="shot" onclick="openShot(this)"><img src="\(htmlAttribute($0.relativePath))" alt="Real project evidence"></button>
            <figcaption>\(html($0.name))</figcaption></figure>
            """
        }.joined(separator: "\n")

        let deltas = beforeAfterRows(baseline: baseline, snapshot: snapshot)
        let beforeAfterHTML = deltas.map { row in
            """
            <tr><td>\(html(row.name))</td><td>\(row.before)</td><td>\(row.after)</td>
            <td class="delta \(row.delta > 0 ? "positive" : "")">\(row.delta >= 0 ? "+" : "")\(row.delta)</td></tr>
            """
        }.joined(separator: "\n")

        let document = """
        <!doctype html>
        <html lang="en" data-loopforge-report-schema="2"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(html(task.displayTaskSummary)) · LoopForge Status</title>
        <style>
        :root{color-scheme:light dark;--bg:#f5f5f7;--card:rgba(255,255,255,.82);--ink:#1d1d1f;--muted:#6e6e73;--line:rgba(0,0,0,.08);--accent:#007aff;--ok:#248a3d;--warn:#b45f06}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:radial-gradient(circle at 78% -12%,rgba(0,122,255,.14),transparent 32%),var(--bg);font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;color:var(--ink)}main{max-width:1180px;margin:auto;padding:64px 28px 100px}.top{display:flex;justify-content:space-between;gap:24px;align-items:flex-start}.eyebrow{color:var(--accent);font-weight:750;letter-spacing:.09em;text-transform:uppercase;font-size:11px}h1{font-size:clamp(40px,6vw,68px);line-height:1.03;letter-spacing:-.045em;margin:11px 0 16px;max-width:850px}h2{font-size:26px;letter-spacing:-.025em;margin:0 0 18px}h3{margin:0 0 4px}.lead{font-size:19px;color:var(--muted);max-width:830px}.status{display:inline-flex;align-items:center;gap:8px;padding:8px 12px;border-radius:999px;font-weight:650;white-space:nowrap}.status.ok{color:var(--ok);background:rgba(36,138,61,.11)}.status.working{color:var(--accent);background:rgba(0,122,255,.11)}.status.hold{color:var(--muted);background:rgba(128,128,128,.12)}.pulse{width:8px;height:8px;border-radius:50%;background:currentColor}.working .pulse{animation:pulse 1.3s infinite}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:34px 0}.metric,.card{background:var(--card);border:1px solid var(--line);box-shadow:0 18px 52px rgba(0,0,0,.055);backdrop-filter:blur(22px);border-radius:22px}.metric{padding:20px}.metric b{display:block;font-size:25px;letter-spacing:-.035em}.metric small,.score-row small{display:block;color:var(--muted)}.meter{height:6px;background:rgba(128,128,128,.15);border-radius:99px;overflow:hidden;margin-top:12px}.meter i{display:block;height:100%;background:var(--accent);width:\(Int(progress*100))%}.columns{display:grid;grid-template-columns:1fr 1fr;gap:16px}section{margin-top:48px}.card{padding:27px}.card p{white-space:normal}.card ul{padding-left:20px}.card li+li{margin-top:8px}.facts{display:grid;grid-template-columns:150px 1fr;gap:8px 14px}.facts dt{color:var(--muted)}.facts dd{margin:0;font-weight:550}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:12px 10px;border-bottom:1px solid var(--line)}th{font-size:12px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}.delta{color:var(--muted);font-variant-numeric:tabular-nums}.delta.positive{color:var(--ok);font-weight:700}.score-row{display:flex;justify-content:space-between;gap:20px;padding:14px 0;border-top:1px solid var(--line)}.score{display:flex;align-items:baseline}.score b{font-size:24px}.score span{color:var(--muted);font-size:11px}.gallery{display:grid;grid-template-columns:repeat(2,1fr);gap:16px}.gallery figure{margin:0}.shot{padding:0;border:0;background:none;cursor:zoom-in;width:100%}.gallery img{width:100%;display:block;border-radius:18px;border:1px solid var(--line);box-shadow:0 14px 40px rgba(0,0,0,.08)}figcaption{padding:8px 3px;color:var(--muted);font-size:12px}.timeline{display:grid;grid-template-columns:36px 1fr;gap:14px;padding:16px 0;border-top:1px solid var(--line)}.timeline>span{display:grid;place-items:center;width:28px;height:28px;border-radius:50%;background:rgba(0,122,255,.11);color:var(--accent);font-weight:750}.timeline p{margin:0;color:var(--muted);max-height:12em;overflow:auto}.graph-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}.graph-node{padding:18px;border:1px solid var(--line);border-radius:16px;background:rgba(128,128,128,.045)}.graph-node.ok{border-color:rgba(36,138,61,.28);background:rgba(36,138,61,.055)}.graph-node.blocked{border-color:rgba(220,38,38,.3);background:rgba(220,38,38,.055)}.graph-node-head,.graph-node-meta{display:flex;justify-content:space-between;gap:12px}.graph-node-head span,.graph-node-meta,.graph-node small{color:var(--muted);font-size:12px}.graph-node p{margin:8px 0}.graph-node-meta{justify-content:flex-start;flex-wrap:wrap}.empty{color:var(--muted)}footer{margin-top:58px;color:var(--muted);font-size:12px}.lightbox{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;place-items:center;padding:28px;z-index:10}.lightbox.open{display:grid}.lightbox img{max-width:96vw;max-height:92vh;border-radius:15px}@keyframes pulse{50%{opacity:.25;transform:scale(.72)}}@media(max-width:780px){main{padding-top:38px}.top{display:block}.status{margin-top:18px}.grid{grid-template-columns:repeat(2,1fr)}.columns,.gallery,.graph-grid{grid-template-columns:1fr}}@media(prefers-color-scheme:dark){:root{--bg:#0b0b0d;--card:rgba(31,31,34,.82);--ink:#f5f5f7;--muted:#a1a1a6;--line:rgba(255,255,255,.10)}body{background:radial-gradient(circle at 78% -12%,rgba(0,122,255,.25),transparent 34%),var(--bg)}}
        </style></head><body><main>
        <div class="top"><div><div class="eyebrow">\(isFinal ? "LoopForge delivery report" : "LoopForge task status")</div><h1>\(html(task.displayTaskSummary))</h1>
        <p class="lead">\(html(groundedNarrative.executiveSummary))</p></div>
        <div class="status \(statusClass)"><span class="pulse"></span>\(html(statusTitle))</div></div>
        <div class="grid">
          <div class="metric"><b>\(task.accumulatedCodexSeconds.compactDuration)</b><small>\(task.resolvedExecutionMode == .autoGraph ? "active node-agent work" : (task.resolvedExecutionMode == .parallelCandidates ? "total candidate work" : "active Sub Agent work"))</small><div class="meter"><i></i></div></div>
          <div class="metric"><b>\(task.officialInteractions)</b><small>\(task.resolvedExecutionMode == .autoGraph ? "Main Graph reviews" : (task.resolvedExecutionMode == .parallelCandidates ? "selection reviews" : "LoopForge instructions"))</small></div>
          <div class="metric"><b>\(snapshot.sourceFiles)</b><small>source files now</small></div>
          <div class="metric"><b>\(audit.score)/100</b><small>evidence audit</small></div>
        </div>
        <section class="columns"><div class="card"><h2>Completion snapshot</h2><ul>\(completedHTML)</ul></div>
        <div class="card"><h2>Current experience</h2><p>\(html(groundedNarrative.currentExperience))</p></div></section>
        <section class="columns"><div class="card"><h2>Task contract</h2><p>\(html(task.originalRequest ?? task.request))</p></div>
        <div class="card"><h2>Delivery facts</h2><dl class="facts"><dt>Project</dt><dd>\(html(task.title))</dd><dt>Execution</dt><dd>\(html(task.resolvedExecutionMode.title))</dd><dt>Task quality</dt><dd>\(html(task.quality.title))</dd><dt>Sub Agent</dt><dd>\(html(task.resolvedSubAgent.summary))</dd><dt>Control Agent</dt><dd>\(html(task.resolvedControlAgent.summary))</dd><dt>Report reasoning</dt><dd>\(html(task.reportGenerationProvider ?? "Deterministic evidence fallback"))</dd></dl></div></section>
        \(graphHTML.isEmpty ? "" : "<section><div class=\"card\"><h2>\(task.resolvedExecutionMode == .parallelCandidates ? "Candidate comparison" : "Graph execution")</h2><div class=\"graph-grid\">\(graphHTML)</div></div></section>")
        \(graphPerformanceHTML)
        <section><div class="card"><h2>Before and now</h2><div class="table-wrap"><table><thead><tr><th>Verified workspace signal</th><th>Before</th><th>Now</th><th>Change</th></tr></thead><tbody>\(beforeAfterHTML)</tbody></table></div></div></section>
        <section class="columns"><div class="card"><h2>What changed</h2><ul>\(changeHTML)</ul></div><div class="card"><h2>Product strengths and effect evaluation</h2>\(evaluationHTML.isEmpty ? "<p class=\"empty\">A scored model evaluation will appear in the final report.</p>" : evaluationHTML)</div></section>
        \(galleryHTML.isEmpty ? "<section><div class=\"card\"><h2>Product evidence and real screenshots</h2><p class=\"empty\">No fresh screenshot passed the evidence collector yet. This is reported as a gap, not replaced by a mock image.</p></div></section>" : "<section><h2>Product evidence and real screenshots</h2><div class=\"gallery\">\(galleryHTML)</div></section>")
        <section class="columns"><div class="card"><h2>Requirement evidence coverage</h2><ul>\(coverageHTML)</ul></div><div class="card"><h2>Workspace highlights</h2><ul>\(workspaceHTML)</ul></div></section>
        <section class="columns"><div class="card"><h2>Known limitations</h2><ul>\(limitationHTML)</ul></div><div class="card"><h2>Recommended next steps</h2><ul>\(nextHTML)</ul></div></section>
        <section><div class="card"><h2>LoopForge control history</h2>\(timelineHTML.isEmpty ? "<p class=\"empty\">The first instruction has not been dispatched yet.</p>" : timelineHTML)</div></section>
        <section class="columns"><div class="card"><h2>Verification runs</h2><ul>\(commandHTML)</ul></div><div class="card"><h2>Audit decisions</h2><ul>\(auditHTML)</ul></div></section>
        <footer>Updated \(html(generated)) · This page is generated from retained workspace and runtime evidence. Missing proof is shown as missing.</footer>
        </main><div class="lightbox" onclick="this.classList.remove('open')"><img alt="Expanded project evidence"></div>
        <script>function openShot(b){const l=document.querySelector('.lightbox');l.querySelector('img').src=b.querySelector('img').src;l.classList.add('open')}</script>
        </body></html>
        """

        let destination = root.appendingPathComponent("index.html")
        guard let data = document.data(using: .utf8) else {
            throw LoopForgeError.runtimeUnavailable("The task status page could not be encoded.")
        }
        try data.write(to: destination, options: .atomic)
        return destination.path
    }

    private func criticalPathActiveSeconds(nodes: [GraphLoopNode]) -> TimeInterval {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var memo: [String: TimeInterval] = [:]
        var visiting = Set<String>()

        func visit(_ id: String) -> TimeInterval {
            if let cached = memo[id] { return cached }
            guard let node = byID[id], visiting.insert(id).inserted else { return 0 }
            let predecessor = node.dependencies.map(visit).max() ?? 0
            visiting.remove(id)
            let total = predecessor + node.accumulatedActiveSeconds
            memo[id] = total
            return total
        }

        return nodes.map { visit($0.id) }.max() ?? 0
    }

    static func decodeNarrative(_ raw: String) -> CompletionReportNarrative? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        }
        if let data = text.data(using: .utf8),
           let direct = try? JSONDecoder().decode(CompletionReportNarrative.self, from: data) {
            return direct
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              start <= end,
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CompletionReportNarrative.self, from: data)
    }

    private func deterministicNarrative(task: LoopTask, audit: AuditResult) -> CompletionReportNarrative {
        let completedNodes = task.graphState?.nodes.filter { $0.status == .completed } ?? []
        let graphLogs = task.graphState?.nodes.flatMap(\.logs) ?? []
        let reportLogs = (task.logs + graphLogs).sorted { $0.timestamp < $1.timestamp }
        let completedWork = completedNodes.isEmpty
            ? (audit.findings.isEmpty
                ? ["The retained evidence audit has no unresolved deterministic finding."]
                : audit.findings)
            : completedNodes.map {
                $0.lastReview.isEmpty ? $0.objective : "\($0.title): \($0.lastReview)"
            }
        let experience = completedNodes.last(where: { !$0.lastAgentMessage.isEmpty })?.lastAgentMessage
            ?? task.lastAgentMessage
        return CompletionReportNarrative(
            executiveSummary: audit.summary,
            completedWork: completedWork,
            currentExperience: experience.isEmpty
                ? "Every graph node passed its retained evidence gate."
                : String(experience.prefix(4_000)),
            notableChanges: completedNodes.isEmpty
                ? reportLogs.filter { $0.kind == .command }.suffix(8).map(\.message)
                : completedNodes.map(\.objective),
            evaluation: [
                ReportEvaluationItem(
                    dimension: "Evidence completion",
                    score: audit.score,
                    evidence: audit.summary
                )
            ],
            limitations: audit.passed ? [] : audit.findings,
            recommendedNextSteps: audit.nextActions
        )
    }

    private func copiedGallery(task: LoopTask, media: URL) throws -> [(name: String, relativePath: String)] {
        var gallery: [(String, String)] = []
        for (index, path) in (task.visualEvidencePaths ?? []).prefix(12).enumerated() {
            let source = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
            let filename = String(format: "evidence-%02d.%@", index + 1, ext)
            let destination = media.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            gallery.append((source.lastPathComponent, "media/\(filename)"))
        }
        return gallery
    }

    private func beforeAfterRows(
        baseline: ReportWorkspaceBaseline?,
        snapshot: WorkspaceSnapshot
    ) -> [(name: String, before: Int, after: Int, delta: Int)] {
        let before = baseline ?? ReportWorkspaceBaseline(
            capturedAt: Date(),
            totalFiles: snapshot.totalFiles,
            sourceFiles: snapshot.sourceFiles,
            testFiles: snapshot.testFiles,
            documentationFiles: snapshot.documentationFiles,
            screenshotFiles: snapshot.screenshotFiles
        )
        return [
            ("All project files", before.totalFiles, snapshot.totalFiles, snapshot.totalFiles - before.totalFiles),
            ("Source files", before.sourceFiles, snapshot.sourceFiles, snapshot.sourceFiles - before.sourceFiles),
            ("Test files", before.testFiles, snapshot.testFiles, snapshot.testFiles - before.testFiles),
            ("Documentation files", before.documentationFiles, snapshot.documentationFiles, snapshot.documentationFiles - before.documentationFiles),
            ("Screenshot evidence", before.screenshotFiles, snapshot.screenshotFiles, snapshot.screenshotFiles - before.screenshotFiles)
        ]
    }

    private func list<S: Sequence>(_ items: S, alreadyEscaped: Bool = false) -> String where S.Element == String {
        let values = Array(items)
        guard !values.isEmpty else { return "<li>No verified item is available yet.</li>" }
        return values.map { "<li>\(alreadyEscaped ? $0 : html($0))</li>" }.joined(separator: "\n")
    }

    private func html(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func htmlAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
