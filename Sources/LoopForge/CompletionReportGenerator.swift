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
        let progress = isFinal
            ? 1
            : (
                task.resolvedExecutionMode != .singleLoop
                    ? task.progress
                    : min(1, task.accumulatedCodexSeconds / max(1, task.targetSeconds))
            )
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
        let evidenceCoverage = task.lastEvidenceCoverage ?? ["Evidence inventory will populate after the next control audit."]
        let coverageHTML = list(evidenceCoverage, itemClass: "evidence-item")
        let workspaceHTML = list(snapshot.samplePaths.prefix(20).map { "<code>\(html($0))</code>" }, alreadyEscaped: true)
        let auditLogs = reportLogs.filter { $0.kind == .audit }
        let commandLogs = reportLogs.filter { $0.kind == .command }
        let auditHTML = list(auditLogs.suffix(14).map(\.message))
        let commandHTML = list(commandLogs.suffix(14).map(\.message))
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
            <div class="score-row"><div class="score-copy"><strong>\(html(item.dimension))</strong><small>\(html(item.evidence))</small>
            <div class="score-track" aria-hidden="true"><i style="width:\(score)%"></i></div></div>
            <div class="score" aria-label="\(score) out of 100"><b>\(score)</b><span>/100</span></div></div>
            """
        }.joined(separator: "\n")
        let galleryHTML = gallery.enumerated().map { index, item in
            """
            <figure class="\(index == 0 ? "featured" : "")"><button type="button" class="shot" onclick="openShot(this)" aria-label="Open screenshot \(index + 1): \(htmlAttribute(item.name))"><img src="\(htmlAttribute(item.relativePath))" alt="Project evidence \(index + 1): \(htmlAttribute(item.name))" loading="\(index == 0 ? "eager" : "lazy")"></button>
            <figcaption><span>Evidence \(String(format: "%02d", index + 1))</span>\(html(item.name))</figcaption></figure>
            """
        }.joined(separator: "\n")

        let orchestrationFact: (label: String, value: String) = {
            switch task.resolvedExecutionMode {
            case .singleLoop:
                return ("Active target", task.targetSeconds.compactDuration)
            case .autoGraph:
                return (
                    "Graph concurrency",
                    "Up to \(task.graphState?.maxConcurrentNodes ?? 1) ready nodes"
                )
            case .parallelCandidates:
                return (
                    "Candidate branches",
                    "\(task.resolvedParallelCandidateCount) isolated Git worktrees"
                )
            }
        }()
        let screenshotCount = gallery.count
        let verificationCount = commandLogs.count
        let evidenceCount = evidenceCoverage.count

        let deltas = beforeAfterRows(baseline: baseline, snapshot: snapshot)
        let beforeAfterHTML = deltas.map { row in
            """
            <tr><td>\(html(row.name))</td><td>\(row.before)</td><td>\(row.after)</td>
            <td class="delta \(row.delta > 0 ? "positive" : "")">\(row.delta >= 0 ? "+" : "")\(row.delta)</td></tr>
            """
        }.joined(separator: "\n")

        let document = """
        <!doctype html>
        <html lang="en" data-loopforge-report-schema="3"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(html(task.displayTaskSummary)) · LoopForge Status</title>
        <style>
        :root{color-scheme:light dark;--bg:#f5f5f7;--surface:rgba(255,255,255,.84);--surface-solid:#fff;--ink:#1d1d1f;--muted:#6e6e73;--line:rgba(0,0,0,.085);--accent:#0a7aff;--accent-soft:rgba(10,122,255,.1);--ok:#248a3d;--ok-soft:rgba(36,138,61,.09);--danger:#c52b32;--shadow:0 22px 70px rgba(0,0,0,.065)}
        *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:radial-gradient(circle at 82% -9%,rgba(10,122,255,.17),transparent 31%),radial-gradient(circle at 8% 18%,rgba(126,87,194,.08),transparent 27%),var(--bg);font:15px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;color:var(--ink)}
        a{color:inherit}button{font:inherit}main{max-width:1180px;margin:auto;padding:28px 28px 100px}.report-nav{position:sticky;top:14px;z-index:5;display:flex;align-items:center;gap:8px;width:max-content;max-width:100%;overflow:auto;margin:0 auto 58px;padding:7px;border:1px solid var(--line);border-radius:999px;background:rgba(248,248,250,.72);backdrop-filter:blur(26px);box-shadow:0 12px 34px rgba(0,0,0,.07)}.report-nav a{text-decoration:none;color:var(--muted);font-size:12px;font-weight:650;padding:7px 11px;border-radius:999px;white-space:nowrap}.report-nav a:hover,.report-nav a:focus-visible{background:var(--accent-soft);color:var(--accent);outline:none}
        .top{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:34px;align-items:start}.eyebrow{display:flex;align-items:center;gap:8px;color:var(--accent);font-weight:760;letter-spacing:.1em;text-transform:uppercase;font-size:11px}.eyebrow:before{content:"∞";display:grid;place-items:center;width:24px;height:24px;border-radius:8px;background:linear-gradient(145deg,#7c5cff,#0a84ff);color:white;font-size:14px;letter-spacing:0}h1{font-size:clamp(42px,6vw,70px);line-height:1.01;letter-spacing:-.052em;margin:14px 0 18px;max-width:900px}h2{font-size:25px;line-height:1.16;letter-spacing:-.03em;margin:0 0 18px}h3{margin:0 0 5px;font-size:15px}.lead{font-size:20px;line-height:1.48;color:var(--muted);max-width:850px;margin-bottom:18px}.hero-meta{display:flex;gap:8px;flex-wrap:wrap}.hero-meta span{padding:6px 10px;border-radius:999px;background:rgba(128,128,128,.085);color:var(--muted);font-size:12px}.status{display:inline-flex;align-items:center;gap:9px;padding:9px 13px;border-radius:999px;font-weight:680;white-space:nowrap;border:1px solid currentColor}.status.ok{color:var(--ok);background:var(--ok-soft)}.status.working{color:var(--accent);background:var(--accent-soft)}.status.hold{color:var(--muted);background:rgba(128,128,128,.1)}.pulse{width:8px;height:8px;border-radius:50%;background:currentColor}.working .pulse{animation:pulse 1.3s infinite}
        .status{justify-self:end}
        section{scroll-margin-top:84px;margin-top:52px}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:13px;margin:38px 0}.metric,.card{background:var(--surface);border:1px solid var(--line);box-shadow:var(--shadow);backdrop-filter:blur(24px);border-radius:24px}.metric{padding:21px}.metric b{display:block;font-size:27px;line-height:1.15;letter-spacing:-.04em;font-variant-numeric:tabular-nums}.metric small,.score-row small{display:block;color:var(--muted)}.metric .metric-kicker{margin-bottom:8px;color:var(--accent);font-weight:720;font-size:10px;letter-spacing:.08em;text-transform:uppercase}.meter{height:6px;background:rgba(128,128,128,.15);border-radius:99px;overflow:hidden;margin-top:13px}.meter i{display:block;height:100%;border-radius:inherit;background:linear-gradient(90deg,#5a5bff,#0a84ff);width:\(Int(progress*100))%}.evidence-band{display:grid;grid-template-columns:1.5fr repeat(3,1fr);gap:1px;overflow:hidden;border:1px solid var(--line);border-radius:18px;background:var(--line);box-shadow:0 12px 36px rgba(0,0,0,.04)}.evidence-band>div{padding:16px 18px;background:var(--surface-solid)}.evidence-band strong{display:block;font-size:18px}.evidence-band small{color:var(--muted)}.evidence-note{display:flex;align-items:center;gap:9px;color:var(--ok);font-weight:680}
        .columns{display:grid;grid-template-columns:1fr 1fr;gap:16px}.card{padding:28px}.card p{white-space:normal}.card ul{list-style:none;padding:0;margin:0}.card li{position:relative;padding-left:22px}.card li:before{content:"";position:absolute;left:2px;top:.68em;width:7px;height:7px;border-radius:50%;background:var(--accent)}.card li+li{margin-top:10px}.outcome{background:linear-gradient(145deg,var(--surface),rgba(10,122,255,.055));border-color:rgba(10,122,255,.17)}.facts{display:grid;grid-template-columns:150px 1fr;gap:9px 14px}.facts dt{color:var(--muted)}.facts dd{margin:0;font-weight:570}.section-intro{display:flex;justify-content:space-between;gap:24px;align-items:end;margin-bottom:18px}.section-intro h2{margin:0}.section-intro p{margin:0;max-width:590px;color:var(--muted);font-size:13px;text-align:right}
        .table-wrap{overflow:auto;border:1px solid var(--line);border-radius:16px}table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:13px 14px;border-bottom:1px solid var(--line)}tbody tr:last-child td{border-bottom:0}th{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.06em}.delta{color:var(--muted);font-variant-numeric:tabular-nums}.delta.positive{color:var(--ok);font-weight:720}.score-row{display:flex;justify-content:space-between;gap:20px;padding:15px 0;border-top:1px solid var(--line)}.score-row:first-of-type{border-top:0}.score-copy{flex:1}.score{display:flex;align-items:baseline}.score b{font-size:26px;letter-spacing:-.04em}.score span{color:var(--muted);font-size:11px}.score-track{height:4px;background:rgba(128,128,128,.13);border-radius:99px;overflow:hidden;margin-top:9px}.score-track i{display:block;height:100%;background:linear-gradient(90deg,#5a5bff,var(--accent));border-radius:inherit}
        .gallery{display:grid;grid-template-columns:repeat(2,1fr);gap:18px}.gallery figure{margin:0}.gallery figure.featured{grid-column:1/-1}.shot{display:block;padding:0;border:0;background:none;cursor:zoom-in;width:100%;border-radius:21px}.shot:focus-visible{outline:3px solid var(--accent);outline-offset:4px}.gallery img{width:100%;max-height:640px;object-fit:cover;object-position:top;display:block;border-radius:21px;border:1px solid var(--line);box-shadow:0 18px 54px rgba(0,0,0,.11);background:var(--surface-solid)}figcaption{display:flex;gap:10px;padding:10px 4px;color:var(--muted);font-size:12px}figcaption span{color:var(--accent);font-weight:720;letter-spacing:.04em}.timeline{display:grid;grid-template-columns:38px 1fr;gap:14px;padding:17px 0;border-top:1px solid var(--line)}.timeline:first-of-type{border-top:0}.timeline>span{display:grid;place-items:center;width:30px;height:30px;border-radius:50%;background:var(--accent-soft);color:var(--accent);font-weight:760}.timeline p{margin:0;color:var(--muted);max-height:12em;overflow:auto}
        .graph-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}.graph-node{padding:19px;border:1px solid var(--line);border-radius:17px;background:rgba(128,128,128,.045)}.graph-node.ok{border-color:rgba(36,138,61,.28);background:var(--ok-soft)}.graph-node.blocked{border-color:rgba(197,43,50,.3);background:rgba(197,43,50,.055)}.graph-node-head,.graph-node-meta{display:flex;justify-content:space-between;gap:12px}.graph-node-head span,.graph-node-meta,.graph-node small{color:var(--muted);font-size:12px}.graph-node p{margin:9px 0}.graph-node-meta{justify-content:flex-start;flex-wrap:wrap}.graph-node small{display:block;margin-top:9px}.graph-metrics{margin:0 0 12px}.method{margin:0;color:var(--muted);font-size:12px}.evidence-item:before{background:var(--ok)!important}.empty{color:var(--muted)}
        details{border-top:1px solid var(--line);padding:17px 0}details:first-of-type{border-top:0}summary{cursor:pointer;font-weight:680;list-style:none;display:flex;align-items:center;justify-content:space-between}summary::-webkit-details-marker{display:none}summary:after{content:"+";color:var(--muted);font-size:20px;font-weight:400}details[open] summary:after{content:"−"}details .detail-body{padding-top:13px}
        footer{display:flex;justify-content:space-between;gap:20px;margin-top:60px;padding-top:22px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}.lightbox{width:min(96vw,1400px);max-width:none;padding:0;border:0;border-radius:22px;background:#101012;box-shadow:0 30px 100px rgba(0,0,0,.55)}.lightbox::backdrop{background:rgba(0,0,0,.82);backdrop-filter:blur(8px)}.lightbox img{display:block;max-width:96vw;max-height:88vh;margin:auto;border-radius:18px}.lightbox-close{position:absolute;right:12px;top:12px;width:34px;height:34px;border:0;border-radius:50%;background:rgba(0,0,0,.62);color:white;cursor:pointer;font-size:20px}
        @keyframes pulse{50%{opacity:.25;transform:scale(.72)}}@media(max-width:780px){main{padding:18px 18px 76px}.report-nav{margin-bottom:40px}.top{grid-template-columns:1fr}.status{width:max-content;justify-self:start}.grid{grid-template-columns:repeat(2,1fr)}.columns,.gallery,.graph-grid{grid-template-columns:1fr}.gallery figure.featured{grid-column:auto}.evidence-band{grid-template-columns:1fr 1fr}.section-intro{display:block}.section-intro p{text-align:left;margin-top:6px}.facts{grid-template-columns:120px 1fr}footer{display:block}}@media(max-width:470px){.grid,.evidence-band{grid-template-columns:1fr}.report-nav{width:100%}h1{font-size:40px}}
        @media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}.working .pulse{animation:none}}@media print{body{background:white}.report-nav,.lightbox{display:none!important}main{max-width:none;padding:0}.metric,.card{box-shadow:none;break-inside:avoid}.gallery img{box-shadow:none}section{margin-top:28px}}@media(prefers-color-scheme:dark){:root{--bg:#0b0b0d;--surface:rgba(31,31,34,.84);--surface-solid:#1d1d20;--ink:#f5f5f7;--muted:#a1a1a6;--line:rgba(255,255,255,.105);--accent-soft:rgba(10,132,255,.15);--ok-soft:rgba(48,209,88,.1);--shadow:0 22px 70px rgba(0,0,0,.22)}body{background:radial-gradient(circle at 82% -9%,rgba(10,122,255,.25),transparent 33%),radial-gradient(circle at 8% 18%,rgba(126,87,194,.13),transparent 27%),var(--bg)}.report-nav{background:rgba(27,27,30,.76)}}
        </style></head><body><main>
        <nav class="report-nav" aria-label="Report sections"><a href="#overview">Overview</a><a href="#evidence">Evidence</a><a href="#changes">Changes</a><a href="#verification">Verification</a><a href="#history">History</a></nav>
        <header class="top" id="overview"><div><div class="eyebrow">\(isFinal ? "LoopForge delivery report" : "LoopForge task status")</div><h1>\(html(task.displayTaskSummary))</h1>
        <p class="lead">\(html(groundedNarrative.executiveSummary))</p>
        <div class="hero-meta"><span>\(html(task.resolvedExecutionMode.title))</span><span>\(html(task.quality.title)) quality</span><span>\(html(task.reportGenerationProvider ?? "Evidence fallback"))</span></div></div>
        <div class="status \(statusClass)"><span class="pulse"></span>\(html(statusTitle))</div></header>
        <div class="grid">
          <div class="metric"><div class="metric-kicker">Active work</div><b>\(task.accumulatedCodexSeconds.compactDuration)</b><small>\(task.resolvedExecutionMode == .autoGraph ? "verified node-agent time" : (task.resolvedExecutionMode == .parallelCandidates ? "verified candidate time" : "verified Sub Agent time"))</small><div class="meter" aria-label="Task gate progress \(Int(progress * 100)) percent"><i></i></div></div>
          <div class="metric"><div class="metric-kicker">Control</div><b>\(task.officialInteractions)</b><small>\(task.resolvedExecutionMode == .autoGraph ? "Main Graph reviews" : (task.resolvedExecutionMode == .parallelCandidates ? "selection reviews" : "LoopForge instructions"))</small></div>
          <div class="metric"><div class="metric-kicker">Workspace</div><b>\(snapshot.sourceFiles)</b><small>source files now</small></div>
          <div class="metric"><div class="metric-kicker">Confidence</div><b>\(audit.score)/100</b><small>evidence audit</small></div>
        </div>
        <div class="evidence-band" aria-label="Retained evidence summary"><div class="evidence-note"><span>✓</span><span>Grounded in retained local evidence</span></div><div><strong>\(screenshotCount)</strong><small>real screenshots</small></div><div><strong>\(verificationCount)</strong><small>verification runs</small></div><div><strong>\(evidenceCount)</strong><small>requirement signals</small></div></div>
        <section class="columns"><div class="card outcome"><h2>Completion snapshot</h2><ul>\(completedHTML)</ul></div>
        <div class="card"><h2>Current experience</h2><p>\(html(groundedNarrative.currentExperience))</p></div></section>
        <section class="columns"><div class="card"><h2>Task contract</h2><p>\(html(task.originalRequest ?? task.request))</p></div>
        <div class="card"><h2>Delivery facts</h2><dl class="facts"><dt>Project</dt><dd>\(html(task.title))</dd><dt>Execution</dt><dd>\(html(task.resolvedExecutionMode.title))</dd><dt>Task quality</dt><dd>\(html(task.quality.title))</dd><dt>\(html(orchestrationFact.label))</dt><dd>\(html(orchestrationFact.value))</dd><dt>Sub Agent</dt><dd>\(html(task.resolvedSubAgent.summary))</dd><dt>Control Agent</dt><dd>\(html(task.resolvedControlAgent.summary))</dd><dt>Report reasoning</dt><dd>\(html(task.reportGenerationProvider ?? "Deterministic evidence fallback"))</dd></dl></div></section>
        \(graphHTML.isEmpty ? "" : "<section><div class=\"card\"><h2>\(task.resolvedExecutionMode == .parallelCandidates ? "Candidate comparison" : "Graph execution")</h2><div class=\"graph-grid\">\(graphHTML)</div></div></section>")
        \(graphPerformanceHTML)
        <section><div class="card"><h2>Before and now</h2><div class="table-wrap"><table><thead><tr><th>Verified workspace signal</th><th>Before</th><th>Now</th><th>Change</th></tr></thead><tbody>\(beforeAfterHTML)</tbody></table></div></div></section>
        <section class="columns" id="changes"><div class="card"><h2>What changed</h2><ul>\(changeHTML)</ul></div><div class="card"><h2>Product strengths and effect evaluation</h2>\(evaluationHTML.isEmpty ? "<p class=\"empty\">A scored model evaluation will appear in the final report.</p>" : evaluationHTML)</div></section>
        \(galleryHTML.isEmpty ? "<section id=\"evidence\"><div class=\"card\"><h2>Product evidence and real screenshots</h2><p class=\"empty\">No fresh screenshot passed the evidence collector yet. This is reported as a gap, not replaced by a mock image.</p></div></section>" : "<section id=\"evidence\"><div class=\"section-intro\"><h2>Product evidence and real screenshots</h2><p>Fresh files copied into this self-contained report. Select any image to inspect the original evidence at a larger size.</p></div><div class=\"gallery\">\(galleryHTML)</div></section>")
        <section class="columns"><div class="card"><h2>Requirement evidence coverage</h2><ul>\(coverageHTML)</ul></div><div class="card"><h2>Workspace highlights</h2><ul>\(workspaceHTML)</ul></div></section>
        <section class="columns"><div class="card"><h2>Known limitations</h2><ul>\(limitationHTML)</ul></div><div class="card"><h2>Recommended next steps</h2><ul>\(nextHTML)</ul></div></section>
        <section id="verification"><div class="card"><h2>Verification and audit trail</h2><details open><summary>Verification runs <small>\(verificationCount) retained</small></summary><div class="detail-body"><ul>\(commandHTML)</ul></div></details><details><summary>Audit decisions <small>\(auditLogs.count) retained</small></summary><div class="detail-body"><ul>\(auditHTML)</ul></div></details></div></section>
        <section id="history"><div class="card"><h2>LoopForge control history</h2><p class="method">Every displayed iteration is backed by a retained control instruction.</p><div>\(timelineHTML.isEmpty ? "<p class=\"empty\">The first instruction has not been dispatched yet.</p>" : timelineHTML)</div></div></section>
        <footer><span>Updated \(html(generated))</span><span>Generated from retained workspace and runtime evidence · missing proof stays visible</span></footer>
        </main><dialog class="lightbox" id="lightbox" onclick="closeFromBackdrop(event)"><button type="button" class="lightbox-close" aria-label="Close screenshot" onclick="closeShot()">×</button><img alt="Expanded project evidence"></dialog>
        <script>const box=document.getElementById('lightbox');function openShot(b){box.querySelector('img').src=b.querySelector('img').src;box.querySelector('img').alt=b.querySelector('img').alt;box.showModal()}function closeShot(){box.close()}function closeFromBackdrop(e){if(e.target===box)box.close()}addEventListener('keydown',e=>{if(e.key==='Escape'&&box.open)box.close()})</script>
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
            gallery.append((evidenceDisplayName(source), "media/\(filename)"))
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

    private func list<S: Sequence>(
        _ items: S,
        alreadyEscaped: Bool = false,
        itemClass: String? = nil
    ) -> String where S.Element == String {
        let values = Array(items)
        guard !values.isEmpty else { return "<li>No verified item is available yet.</li>" }
        let attribute = itemClass.map { " class=\"\(htmlAttribute($0))\"" } ?? ""
        return values.map { "<li\(attribute)>\(alreadyEscaped ? $0 : html($0))</li>" }.joined(separator: "\n")
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

    private func evidenceDisplayName(_ source: URL) -> String {
        let stem = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return "Project screenshot" }
        return stem
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
