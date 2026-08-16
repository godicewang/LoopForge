import Foundation

struct WatcherReportGenerator {
    func generate(watcher: ContinuumWatcher) throws -> String {
        let reportDirectory = URL(fileURLWithPath: watcher.workspacePath, isDirectory: true)
            .appendingPathComponent(".loopforge/watcher/report", isDirectory: true)
        try FileManager.default.createDirectory(
            at: reportDirectory,
            withIntermediateDirectories: true
        )
        let reportURL = reportDirectory.appendingPathComponent("index.html")
        let pipeline = watcher.pipeline
        let selection = watcher.agentSelection
        let independentReview = watcher.latestIndependentReview
        let completionReceipt = watcher.latestCompletionReceipt
        let requestedPoll = watcher.requestedPollIntervalSeconds
            ?? pipeline?.pollIntervalSeconds
            ?? 900
        let requestedReview = watcher.requestedReviewIntervalSeconds
            ?? pipeline?.reviewIntervalSeconds
            ?? 14_400
        let signals = pipeline?.signals.map { signal in
            let value = watcher.runtime.latestSignals[signal.key]
                .map { $0.formatted(.number.precision(.fractionLength(0...3))) }
                ?? "Waiting"
            return """
            <tr><td>\(html(signal.title))</td><td>\(html(value)) \(html(signal.unit))</td>\
            <td>\(html(signal.description))</td></tr>
            """
        }.joined() ?? ""
        let events = watcher.events.suffix(40).reversed().map { event in
            """
            <li class="\(event.severity.rawValue)"><time>\(html(event.timestamp.formatted(date: .abbreviated, time: .standard)))</time>\
            <div><b>\(html(event.kind.reportTitle))</b><p>\(html(event.message))</p></div></li>
            """
        }.joined()
        let generated = pipeline?.generatedPaths.map {
            "<li><code>\(html($0))</code></li>"
        }.joined() ?? ""
        let focus = WatcherFocusProjector.snapshot(for: watcher)
        let findings = focus.pipelineIssues.map { issue in
            """
            <article class="issue \(issue.severity.rawValue)">
              <div><b>\(html(issue.title))</b><p>\(html(issue.detail))</p></div>
              <span>\(focus.pendingIssues.contains(where: { $0.id == issue.id }) ? "Awaiting Agent" : "Reviewed")</span>
            </article>
            """
        }.joined()
        let confirmed = assessmentHTML(
            title: "Confirmed",
            cssClass: "warning",
            issues: focus.confirmedIssues
        )
        let dismissed = assessmentHTML(
            title: "Dismissed",
            cssClass: "dismissed",
            issues: focus.dismissedIssues
        )
        let resolved = assessmentHTML(
            title: "Resolved",
            cssClass: "resolved",
            issues: focus.resolvedIssues
        )
        let important = focus.importantInformation.map { information in
            let value: String
            if let raw = information.value,
               let key = information.signalKey,
               let signal = pipeline?.signals.first(where: { $0.key == key }) {
                value = "<strong>\(html(WatcherFocusProjector.format(raw, signal: signal)))</strong>"
            } else if let raw = information.value {
                let unit = information.unit.map { " \(html($0))" } ?? ""
                value = "<strong>\(html(raw.formatted(.number.precision(.fractionLength(0...2)))))\(unit)</strong>"
            } else {
                value = ""
            }
            return """
            <article class="information \(information.severity.rawValue)">
              \(value)<b>\(html(information.title))</b><p>\(html(information.detail))</p>
              \(information.userActionRequired ? "<span>Needs you</span>" : "")
            </article>
            """
        }.joined()
        let statusClass = watcher.requiresUserAttention ? "critical"
            : (watcher.isDeterministicallyCompleted ? "complete" : "active")
        let htmlDocument = """
        <!doctype html><html lang="en" data-loopforge-watcher-report="1"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(html(watcher.displayTitle)) · LoopForge Watcher</title>
        <style>
        :root{color-scheme:light dark;--bg:#f5f5f7;--surface:rgba(255,255,255,.78);--ink:#1d1d1f;--muted:#6e6e73;--line:rgba(0,0,0,.09);--blue:#0a84ff;--green:#30a14e;--red:#d1242f;--orange:#b85c00}
        *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:radial-gradient(circle at 80% -10%,rgba(10,132,255,.18),transparent 32%),var(--bg);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
        main{max-width:1120px;margin:auto;padding:44px 28px 100px}header{display:grid;grid-template-columns:1fr auto;gap:24px;align-items:start;margin-bottom:30px}.eyebrow{color:var(--blue);font-size:12px;font-weight:750;letter-spacing:.08em;text-transform:uppercase}h1{font-size:42px;line-height:1.08;letter-spacing:-.04em;margin:8px 0 12px}h2{font-size:19px;margin:0 0 16px}.target{max-width:780px;color:var(--muted);font-size:17px}.status{padding:8px 13px;border-radius:999px;background:rgba(10,132,255,.12);color:var(--blue);font-weight:700}.status.complete{background:rgba(48,161,78,.13);color:var(--green)}.status.critical{background:rgba(209,36,47,.12);color:var(--red)}
        .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:22px 0}.card{background:var(--surface);border:1px solid var(--line);border-radius:22px;padding:22px;box-shadow:0 18px 60px rgba(0,0,0,.055);backdrop-filter:blur(24px)}.metric b{display:block;font-size:26px;letter-spacing:-.03em}.metric small,.muted{color:var(--muted)}.columns{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:14px}.facts{display:grid;grid-template-columns:150px 1fr;gap:10px 16px;margin:0}.facts dt{color:var(--muted)}.facts dd{margin:0;font-weight:620;overflow-wrap:anywhere}code{font-family:"SF Mono",ui-monospace,monospace;font-size:12px}
        .focus-head{margin:8px 0 18px}.focus-head h2{font-size:28px;letter-spacing:-.025em;margin-bottom:7px}.focus-head p{margin:0;color:var(--muted);max-width:850px}.focus-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:14px}.focus-grid .metric{min-height:122px}.focus-grid .metric b{font-size:24px}.section-kicker{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.08em;font-weight:750}.stack{display:grid;gap:10px}.issue,.assessment,.information{display:grid;grid-template-columns:1fr auto;gap:16px;padding:14px;border:1px solid var(--line);border-radius:14px}.issue p,.assessment p,.information p{margin:3px 0 0;color:var(--muted)}.issue span,.information span{align-self:start;padding:4px 8px;border-radius:999px;background:rgba(10,132,255,.1);color:var(--blue);font-size:11px;font-weight:700}.issue.critical{border-color:rgba(209,36,47,.35)}.issue.warning,.assessment.warning{border-color:rgba(184,92,0,.28)}.assessment.dismissed{opacity:.72}.assessment.resolved{border-color:rgba(48,161,78,.3)}.information strong{grid-row:1/3;grid-column:2;align-self:center;font-size:21px}.empty{padding:18px;border:1px dashed var(--line);border-radius:14px;color:var(--muted)}.detail-title{margin:34px 0 10px;font-size:12px;color:var(--muted);letter-spacing:.08em;text-transform:uppercase}
        table{width:100%;border-collapse:collapse}th,td{text-align:left;padding:11px 9px;border-bottom:1px solid var(--line)}th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.06em}.timeline{list-style:none;padding:0;margin:0}.timeline li{display:grid;grid-template-columns:150px 1fr;gap:18px;padding:14px 0;border-top:1px solid var(--line)}.timeline li:first-child{border-top:0}.timeline time{color:var(--muted);font-size:12px}.timeline b{font-size:12px}.timeline p{margin:3px 0 0}.timeline .warning b{color:var(--orange)}.timeline .critical b{color:var(--red)}
        @media(max-width:760px){header{grid-template-columns:1fr}.grid,.focus-grid{grid-template-columns:1fr}.columns{grid-template-columns:1fr}.timeline li{grid-template-columns:1fr;gap:4px}}@media(max-width:440px){main{padding:28px 18px 70px}.grid{grid-template-columns:1fr}h1{font-size:34px}}
        @media(prefers-color-scheme:dark){:root{--bg:#0b0b0d;--surface:rgba(30,30,33,.82);--ink:#f5f5f7;--muted:#a1a1a6;--line:rgba(255,255,255,.1)}body{background:radial-gradient(circle at 80% -10%,rgba(10,132,255,.25),transparent 35%),var(--bg)}}
        </style></head><body><main>
        <header><div><div class="eyebrow">LoopForge · Live Watcher report</div><h1>\(html(watcher.displayTitle))</h1>\
        <div class="target">\(html(watcher.request))</div></div><div class="status \(statusClass)">\(html(watcher.operationalStatusTitle))</div></header>
        <section class="card focus-head">
          <div class="section-kicker">Task-focused overview</div>
          <h2>\(html(focus.headline))</h2><p>\(html(focus.summary))</p>
        </section>
        <section class="focus-grid">
          <div class="card metric"><small>Pipeline findings</small><b>\(focus.pipelineIssues.count)</b><span class="muted">\(focus.pendingIssues.count) await Agent judgment</span></div>
          <div class="card metric"><small>Agent assessment</small><b>\(focus.confirmedIssues.count) confirmed</b><span class="muted">\(focus.dismissedIssues.count) dismissed · \(focus.resolvedIssues.count) resolved</span></div>
          <div class="card metric"><small>Important for you</small><b>\(focus.importantInformation.count)</b><span class="muted">\(focus.needsUserActionCount == 0 ? "Nothing requires action" : "\(focus.needsUserActionCount) require action")</span></div>
        </section>
        <section class="columns">
          <div class="card"><h2>Pipeline findings</h2><div class="stack">\(findings.isEmpty ? "<div class=\"empty\">No active anomaly in the latest bounded pass.</div>" : findings)</div></div>
          <div class="card"><h2>Agent assessment</h2><div class="stack">\(confirmed + dismissed + resolved == "" ? "<div class=\"empty\">No item-level Agent decision is pending.</div>" : confirmed + dismissed + resolved)</div></div>
        </section>
        <section class="card" style="margin-top:14px"><h2>Important for your target</h2><div class="stack">\(important.isEmpty ? "<div class=\"empty\">Nothing important changed. Technical signals remain below.</div>" : important)</div></section>
        <div class="detail-title">Technical details and evidence</div>
        <section class="grid">
          <div class="card metric"><small>Pipeline runs</small><b>\(watcher.runtime.totalRuns)</b></div>
          <div class="card metric"><small>Agent wakeups</small><b>\(watcher.runtime.agentWakeups)</b></div>
          <div class="card metric"><small>Consecutive failures</small><b>\(watcher.runtime.consecutiveFailures)</b></div>
          <div class="card metric"><small>Pipeline revision</small><b>\(pipeline?.revision ?? 0)</b></div>
        </section>
        <section class="columns">
          <div class="card"><h2>Configuration</h2><dl class="facts">
          <dt>Agent</dt><dd>\(html(selection?.summary ?? watcher.lastProvider ?? "Not selected"))</dd>
          <dt>Reasoning</dt><dd>\(html(selection?.reasoningEffort?.capitalized ?? "Provider default"))</dd>
          <dt>Access</dt><dd>\(html(selection?.accessMode.title ?? "Workspace"))</dd>
          <dt>Requested pass</dt><dd>\(requestedPoll.compactDuration)</dd>
          <dt>Requested review</dt><dd>\(requestedReview.compactDuration)</dd>
          <dt>Effective pass</dt><dd>\((pipeline?.pollIntervalSeconds ?? requestedPoll).compactDuration)</dd>
          <dt>Effective review</dt><dd>\((pipeline?.reviewIntervalSeconds ?? requestedReview).compactDuration)</dd>
          <dt>Notifications</dt><dd>\(watcher.notificationsEnabled ? "On" : "Off")</dd>
          <dt>Launch at login</dt><dd>\(watcher.launchAtLogin ? "On" : "Off")</dd>
          </dl></div>
          <div class="card"><h2>Solidified pipeline</h2><dl class="facts">
          <dt>Command</dt><dd><code>\(html(pipeline?.command.joined(separator: " ") ?? "Building…"))</code></dd>
          <dt>Last result</dt><dd>\(html(watcher.runtime.lastSummary))</dd>
          <dt>Last provider</dt><dd>\(html(watcher.lastProvider ?? "—"))</dd>
          <dt>Assessment authority</dt><dd>\(watcher.independentlyApprovedAssessment != nil ? "Independently approved" : "Advisory only")</dd>
          <dt>Reviewer</dt><dd>\(html(independentReview?.reviewerProvider ?? "—"))</dd>
          <dt>Pipeline digest</dt><dd><code>\(html(independentReview?.pipelineDigest.rawValue ?? "—"))</code></dd>
          <dt>Assessment digest</dt><dd><code>\(html(independentReview?.assessmentDigest.rawValue ?? "—"))</code></dd>
          <dt>Completion authority</dt><dd>\(watcher.isDeterministicallyCompleted ? "Deterministically verified" : "Not verified")</dd>
          <dt>Completion run</dt><dd>\(completionReceipt.map { "Pipeline revision \($0.observation.pipelineRevision), run \($0.observation.pipelineRunNumber)" } ?? "—")</dd>
          <dt>Completion telemetry</dt><dd><code>\(html(completionReceipt?.observation.telemetryDigest.rawValue ?? "—"))</code></dd>
          <dt>Completion checkpoint</dt><dd><code>\(html(completionReceipt?.observation.checkpointDigest.rawValue ?? "—"))</code></dd>
          <dt>Verification plan</dt><dd><code>\(html(completionReceipt?.verificationPlanDigest.rawValue ?? "—"))</code></dd>
          <dt>Covered goal anchors</dt><dd>\(html(completionReceipt?.coveredGoalAnchorIDs.joined(separator: ", ") ?? "—"))</dd>
          <dt>Generated</dt><dd><ul>\(generated.isEmpty ? "<li>Waiting for pipeline build</li>" : generated)</ul></dd>
          </dl></div>
        </section>
        <section class="card" style="margin-top:14px"><h2>Live signals</h2>\
        \(signals.isEmpty ? "<p class=\"muted\">Signal definitions will appear after the pipeline is verified.</p>" : "<table><thead><tr><th>Signal</th><th>Latest</th><th>Meaning</th></tr></thead><tbody>\(signals)</tbody></table>")</section>
        <section class="card" style="margin-top:14px"><h2>Auditable timeline</h2><ol class="timeline">\(events)</ol></section>
        </main></body></html>
        """
        try Data(htmlDocument.utf8).write(to: reportURL, options: .atomic)
        return reportURL.path
    }

    private func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func assessmentHTML(
        title: String,
        cssClass: String,
        issues: [WatcherAgentIssueAssessment]
    ) -> String {
        issues.map { issue in
            """
            <article class="assessment \(cssClass)">
              <div><span class="section-kicker">\(title)</span><br><b>\(html(issue.title))</b>\
              <p>\(html(issue.detail))</p><p>Evidence: \(html(issue.evidence))</p></div>
              \(issue.userActionRequired ? "<span>Needs you</span>" : "")
            </article>
            """
        }.joined()
    }
}

private extension WatcherEventKind {
    var reportTitle: String {
        switch self {
        case .created: return "Watcher created"
        case .agentProgress: return "Agent progress"
        case .pipelineRun: return "Pipeline pass"
        case .threshold: return "Threshold"
        case .anomaly: return "Anomaly"
        case .staleSignal: return "Stale signal"
        case .pipelineFailure: return "Pipeline failure"
        case .scheduledReview: return "Agent review"
        case .manualReview: return "Manual review"
        case .repaired: return "Pipeline verified"
        case .notification: return "Notification"
        case .lifecycle: return "Lifecycle"
        case .completed: return "Completed"
        }
    }
}
