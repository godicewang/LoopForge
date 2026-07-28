import Foundation

/// Converts a short user request into a stable, evidence-oriented work order.
/// The original request is preserved verbatim (escaped only for delimiters);
/// generated guidance may clarify it but never silently replace it.
struct PromptCompiler {
    private let estimator = TaskEstimator()

    func authorization(for task: LoopTask) -> TaskAuthorization {
        estimator.inferAuthorization(task.request.lowercased())
    }

    func initialPrompt(for task: LoopTask) -> String {
        let authorization = authorization(for: task)
        let refinedMission: String
        let rewriteAudit: String
        if task.resolvedControlAgent.provider != .local {
            refinedMission = "<mission_refinement mode=\"not-required-for-\(task.resolvedControlAgent.provider.rawValue)\" />"
            rewriteAudit = "Not applicable. Codex and API Loop Control Agents use the original request verbatim."
        } else if task.effectiveRequest == task.request {
            refinedMission = "<audited_execution_brief fallback=\"original-verbatim\">\(xmlEscaped(task.request))</audited_execution_brief>"
            rewriteAudit = task.missionRewriteAuditSummary ?? "No local-model rewrite passed; the original goal remains authoritative."
        } else {
            refinedMission = "<audited_execution_brief independently_verified=\"true\">\(xmlEscaped(task.effectiveRequest))</audited_execution_brief>"
            rewriteAudit = task.missionRewriteAuditSummary ?? "The local-model rewrite passed independent semantic review."
        }
        return """
        <loopforge_work_order version="2">
        <mission_contract>
        <original_goal>\(xmlEscaped(task.request))</original_goal>
        \(refinedMission)
        <mission_rewrite_audit>\(xmlEscaped(rewriteAudit))</mission_rewrite_audit>
        <task_mode>\(authorization.title)</task_mode>
        <task_mode_boundary>\(authorization.boundary)</task_mode_boundary>
        <project_type>\(task.category.title)</project_type>
        <quality_level>\(task.quality.title)</quality_level>
        <definition_of_done>\(task.quality.contract)</definition_of_done>
        <specialized_playbook>\(categoryGuidance(for: task.category, authorization: authorization))</specialized_playbook>
        <workspace>\(xmlEscaped(task.workspacePath))</workspace>
        <minimum_active_codex_runtime>\(task.targetSeconds.compactDuration)</minimum_active_codex_runtime>
        </mission_contract>

        You are LoopForge's selected Sub Agent running inside the Codex engineering harness. A separate Loop Control Agent performs a skeptical evidence audit after every stage. Deliver the user's actual outcome through an inspect → research → design → implement → verify → repair → deliver cycle. Do not stop at advice, examples, pseudocode, or an unverified claim when the authorized mode requires an artifact.

        OPERATING RULES
        1. Inspect the workspace, its instructions, current state, and existing tests before changing anything. Treat existing user work as valuable. Do not overwrite an architecture or unrelated changes merely because a clean rewrite is easier.
        2. Use the audited execution brief as a structured interpretation of the verbatim original goal. If any conflict remains, the original goal wins. Atomize it into a private working checklist: goal, relevant context, constraints, assumptions, acceptance criteria, and explicit non-goals. Newer requirements supersede older decisions across UI, code, data, tests, and docs—not just at the visible surface.
        3. Keep facts, assumptions, deterministic calculations, and model judgment separate. Verify mutable or high-risk facts from authoritative sources when the task permits it. Never invent precision, successful commands, benchmark numbers, or external evidence.
        4. \(scopeRule(for: task))
        5. Produce material, reviewable progress in every turn: implementation, diagnosis, reproducible experiment, real verification, recovery behavior, documentation, or directly relevant product polish.
        6. Establish the fastest useful check first, then test the real primary path. After a failure, fix the general contract or mechanism, rerun the original failing scenario, and add an adjacent or unfamiliar scenario to guard against a one-off patch.
        7. Cover the product states appropriate to the task: initial, loading, empty, partial success, recoverable failure, unavailable/offline, and permission denial. For UI work, also check accessibility, keyboard reachability, layout pressure, and clear action wording.
        8. The runtime minimum is an external gate, not quality evidence. Never use sleep, empty loops, repetitive rewrites, fake progress, or meaningless work to consume time. If the artifact appears complete, deepen it with relevant edge cases, tests, review, performance, security, accessibility, packaging, or reproducibility work.
        9. \(artifactRule(for: task))
        10. Ask no questions for ordinary ambiguity: make a safe, reversible assumption and record it. Use `LOOPFORGE_STATUS: BLOCKED` only for a genuine external blocker that requires new authority, credentials, payment, legal acceptance, unavailable hardware, or data the workspace cannot contain.
        11. Distinguish “not shown in the latest evidence bundle” from “not implemented.” Search the workspace, tests, documentation, and retained screenshots before declaring a requirement absent. Do not delete or redo working features because a bounded audit omitted their evidence.
        12. Distinguish code work from operating dependencies. If the goal ultimately needs a publisher account, production backend, signing identity, paid quota, private dataset, or service credential, complete all safe in-workspace contracts, adapters, local substitutes, tests, and handoff material first. Do not repeatedly probe the same unavailable dependency or fabricate a live integration.

        INTERACTIVE SURFACE RULE
        \(interactiveSurfaceRule(for: task))

        SYSTEM PERMISSION RULE
        \(systemPermissionRule(for: task))

        VISUAL WORK RULE
        \(visualRule(for: task))

        ACCEPTANCE EVIDENCE
        \(acceptanceRequirements(for: task, authorization: authorization))

        At the end of the turn, give a concise evidence ledger with goal coverage, files changed or inspected, exact verification commands and outcomes, unresolved risks, and the next highest-value action. Finish with exactly one marker:
        - `LOOPFORGE_STATUS: COMPLETE` only when the original goal and definition of done are actually satisfied and verified.
        - `LOOPFORGE_STATUS: CONTINUE` when useful in-scope work remains.
        - `LOOPFORGE_STATUS: BLOCKED` only for the external blockers defined above.

        Start now. Inspect first, then execute as much of the complete loop as this turn permits.
        </loopforge_work_order>
        """
    }

    func continuationPrompt(
        for task: LoopTask,
        audit: AuditResult,
        snapshot: WorkspaceSnapshot
    ) -> String {
        let remaining = max(0, task.targetSeconds - task.accumulatedCodexSeconds)
        let runtimeGate = remaining > 0
            ? "The external runtime gate has \(remaining.compactDuration) remaining. Continue only with useful work that raises delivery confidence."
            : "The external runtime gate is satisfied. Completion still requires every acceptance gate to pass."
        let findings = audit.findings.isEmpty ? "- No blocking automated finding." : audit.findings.map { "- \($0)" }.joined(separator: "\n")
        let actions = audit.nextActions.isEmpty
            ? "- Perform a skeptical final review and prove the weakest remaining area."
            : audit.nextActions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let failures = recentFailureEvidence(from: task.logs)
        let workspacePaths = snapshot.samplePaths.isEmpty ? "(none found)" : snapshot.samplePaths.joined(separator: ", ")
        let previousReview = task.lastSupervisorReview.map {
            LocalSupervisor.boundedReviewText($0, limit: 4_500)
        } ?? "No prior structured control review is retained."
        let gapKeys = (task.lastControlGapKeys ?? []).isEmpty
            ? "none"
            : (task.lastControlGapKeys ?? []).joined(separator: ", ")

        return """
        <loopforge_audit_followup version="2" iteration="\(task.iteration + 1)">
        This is an automated evidence-based follow-up. Do not ask the user to decide the next step.

        AUTHORITATIVE MISSION
        Verbatim original: \(task.request)
        Independently audited execution brief: \(task.effectiveRequest)
        If these conflict, the verbatim original wins.

        RUNTIME GATE
        \(runtimeGate)

        INDEPENDENT ACCEPTANCE RESULT
        Score: \(audit.score)/100; required: \(task.quality.completionThreshold)/100; passed: \(audit.passed ? "yes" : "no")
        \(findings)

        VERIFIED WORKSPACE SNAPSHOT
        Files: \(snapshot.totalFiles) total, \(snapshot.sourceFiles) source, \(snapshot.testFiles) test, \(snapshot.documentationFiles) documentation, \(snapshot.manifestFiles) build/dependency manifests, \(snapshot.resultFiles) result artifacts, \(snapshot.screenshotFiles) UI screenshot evidence files.
        Verification evidence: \(snapshot.recentCommandSuccesses) successful check(s), \(snapshot.recentCommandFailures) failed check(s).
        Sample paths: \(workspacePaths)

        RECENT FAILURE EVIDENCE
        \(failures)

        PREVIOUS CONTROL DECISION
        \(previousReview)
        Stable open-gap keys: \(gapKeys)

        PRIORITIZED NEXT ACTIONS
        \(actions)

        AUDITOR DIRECTIVE
        Re-read the real files and command outcomes before acting. Address the highest-priority unmet gate, not the easiest cosmetic task. If a previous claim said the work was complete, challenge it with a real primary-path run and a distinct edge or regression scenario. Fix the general cause, rerun the original failure, then run a neighboring or previously unseen case. Preserve unrelated user work and honor the original task-mode boundary. Do not repeat an earlier gap-key action unless current evidence proves that it remains open; when evidence has changed, say exactly how.

        Treat evidence coverage conservatively in both directions: attached candidate evidence still requires inspection, while an unrepresented requirement is not automatically absent. Search the workspace before expanding scope. When progress depends on publisher credentials, paid quota, private data, legal acceptance, or unavailable hardware, finish feasible local preparation once, retain proof, and report the precise external dependency rather than entering a repetitive loop.

        SYSTEM PERMISSION RULE
        \(systemPermissionRule(for: task))

        If all automated gates already pass while runtime remains, use this iteration's deliberate deepening focus: \(deepeningFocus(for: task)). Do not churn completed code or manufacture changes.

        End with the evidence ledger and exactly one `LOOPFORGE_STATUS` marker defined in the original work order.
        </loopforge_audit_followup>
        """
    }

    private func acceptanceRequirements(for task: LoopTask, authorization: TaskAuthorization) -> String {
        var requirements = [
            "- A discoverable final deliverable that directly answers the original goal.",
            "- Reproducible usage or review documentation.",
            "- At least one real verification command with its actual outcome; a completion statement is not evidence.",
            "- No unresolved command failure after the final successful verification.",
            "- A concise record of assumptions, boundaries, and remaining risks."
        ]
        if authorization == .buildOrModify, task.category != .desktopAutomation {
            requirements.insert("- Runnable implementation in the selected workspace with a repeatable build or execution entry point.", at: 1)
        }
        if task.category == .desktopAutomation {
            requirements.insert("- Complete the requested actions in the exact browser or desktop surface named by the user, preserving its current signed-in session.", at: 1)
            requirements.append("- Save every requested downloaded or generated result into the selected workspace and verify the exact requested count.")
            requirements.append("- Retain direct UI evidence showing the target surface, successful submissions, and completed results; a script proposal or API response is not equivalent.")
        }
        if task.quality != .lightweight {
            requirements.append("- Automated regression coverage or reproducible result artifacts appropriate to the task.")
            requirements.append("- Recovery behavior for important invalid, empty, or failed states.")
        }
        if task.quality == .high {
            requirements.append("- A release-grade pass over performance, security, accessibility, packaging, and documentation where relevant.")
            requirements.append("- Verification of both the primary path and at least one materially different edge scenario.")
        }
        if task.needsVisualAudit {
            requirements.append("- Launch the real UI and save current screenshots under `.loopforge/evidence/iteration-N/`; asset images or design mockups do not count.")
            requirements.append("- Visually verify hierarchy, spacing, clipping, state coverage, readability, accessibility, and alignment with the original request.")
        }
        return requirements.joined(separator: "\n")
    }

    private func visualRule(for task: LoopTask) -> String {
        guard task.needsVisualAudit else {
            return "This task does not currently require screenshot evidence. If it develops a user-facing UI, begin capturing and reviewing real rendered states."
        }
        if task.category == .desktopAutomation {
            return "Operate the exact browser or desktop app named by the user and capture fresh evidence under `.loopforge/evidence/iteration-\(task.iteration + 1)/`. For image-generation or download tasks, the requested images are primary deliverables and must also be visually inspected. Do not substitute a new app, static mockup, API call, Selenium/WebDriver project, or different account/session for the requested live surface."
        }
        return "This is a visual task. Build and launch the real product, exercise the relevant state with an appropriate UI harness (for example Playwright, XCTest, simulator tooling, or a native smoke harness), and save fresh screenshots in `.loopforge/evidence/iteration-\(task.iteration + 1)/`. Inspect the rendered result—not source code alone. Capture the primary state and any important failure/empty/responsive state. Do not substitute a static mockup, icon, or asset for a running-product screenshot."
    }

    private func systemPermissionRule(for task: LoopTask) -> String {
        guard task.workerAccessMode == .fullAccess else {
            return "Workspace Only is selected. Do not broaden filesystem, network, app-control, or privacy access beyond the selected project. Report a genuinely required permission once with exact evidence."
        }
        return """
        Full Access authorizes ordinary, task-necessary macOS and application permission interactions. Prefer public request APIs and the narrowest scope. When a standard Allow, OK, Continue, or Open System Settings prompt is directly required for the user’s stated task, operate it through the available UI channel; LoopForge also runs a narrowly-scoped permission-prompt helper. Never edit the TCC database, bypass System Integrity Protection, enter passwords or Touch ID, grant administrator privileges, accept legal/license/payment/subscription terms, select unrelated private files, weaken security settings, or approve an action whose relationship to the task is unclear. Secure macOS privacy toggles still require the user; emit one exact `LOOPFORGE_STATUS: BLOCKED` explanation only after the public request and direct UI path have both been attempted and verified unavailable.
        """
    }

    private func categoryGuidance(for category: TaskCategory, authorization: TaskAuthorization) -> String {
        if authorization == .diagnosis {
            return "Reproduce the symptom, isolate the layer and root cause, distinguish evidence from hypotheses, and produce a minimal evidence-backed diagnosis without silently implementing a fix."
        }
        if authorization == .audit {
            return "Review behavior and code against the stated goal, rank findings by impact, include exact reproduction evidence, and do not turn the audit into an unauthorized rewrite."
        }
        switch category {
        case .maintenance:
            return "Reproduce or isolate the root cause before editing. Make the smallest complete fix, preserve unrelated changes, add a regression test, and prove the original failure no longer reproduces."
        case .optimization:
            return "Freeze a reproducible correctness and performance baseline before optimizing. Identify the bottleneck and report comparable before/after latency, memory, or throughput without trading away correctness."
        case .experiment, .data:
            return "Pin environment, data provenance, seeds, metrics, and comparison rules. Run the baseline, retain machine-readable results, and explain failures, uncertainty, and conclusions."
        case .research:
            return "Define decision variables, use current primary sources when available, search for disconfirming evidence, state stopping conditions, and deliver a recommendation with trade-offs and a switch condition."
        case .game:
            return "Do not let production polish lock in the first familiar mechanic. Before full implementation, research the intended audience and current market from authoritative sources, develop at least three mechanically distinct concepts, compare novelty, learnability, replay depth, retention hooks, solo-developer scope, and production risk, then prototype or simulate the top two interaction loops when feasible. Record the evidence-based concept decision. After selection, deliver a coherent journey, accessible controls, recovery states, a runnable build, and hands-on gameplay verification."
        case .desktopAutomation:
            return "Treat the named live browser or desktop app as the product surface and the user's existing signed-in session as a hard constraint. Perform the requested clicks, typing, navigation, generation, downloads, and verification directly in that surface. Do not convert a ChatGPT website task into GPT API work, do not invent a model such as GPT-3.5, and do not prescribe Selenium, WebDriver, credential extraction, cookie access, or a replacement script unless the user explicitly requested that approach. If the direct UI bridge is unavailable, report the exact missing Chrome extension, browser permission, Accessibility permission, or application setting once; never fabricate completion or silently change surfaces."
        case .web, .nativeApp, .miniProgram:
            return "Deliver a coherent user journey, real states and recovery paths, consistent visual tokens, accessible interaction, a runnable build, and end-to-end verification from entry to result."
        case .script, .library:
            return "Provide a clear command or API, deterministic behavior, safe input validation, useful failure messages, tests, and copy-pasteable usage examples."
        case .general:
            return "Choose the smallest complete workflow that fits the goal, preserve useful existing work, and use a runnable artifact plus real verification as completion evidence."
        }
    }

    private func scopeRule(for task: LoopTask) -> String {
        if task.category == .desktopAutomation {
            return "Use only the user-named browser or desktop app, its current signed-in session, and the selected workspace for downloaded results and evidence. Do not inspect cookies, passwords, session storage, or unrelated tabs and files."
        }
        return "Work only inside the selected workspace. Public project dependencies may be installed when necessary. Do not read or modify unrelated user data outside the workspace."
    }

    private func artifactRule(for task: LoopTask) -> String {
        if task.category == .desktopAutomation {
            return "Use the available direct browser or desktop-control tools for the real interaction. Save requested outputs into the workspace and re-open or inspect them before verification. Creating code is optional and never substitutes for completing the live UI task."
        }
        return "Use official Codex tools normally, including patch/file and shell tools. Write actual workspace files, then re-open or diff them before verification; merely printing a proposal is not a file change."
    }

    private func interactiveSurfaceRule(for task: LoopTask) -> String {
        guard task.category == .desktopAutomation else {
            return "Not applicable. Follow the selected project's normal implementation or analysis workflow."
        }
        return "The original browser, app, account session, requested destination, and interaction method are acceptance constraints—not suggestions. ChatGPT website access and API access are separate products. Never request or synthesize an API key merely because the user is signed into ChatGPT. Never downgrade or rename the user's selected model. When direct control is unavailable, stop before consuming the runtime gate and return one precise capability blocker with the smallest user action needed to enable the requested surface."
    }

    private func deepeningFocus(for task: LoopTask) -> String {
        let common = [
            "re-run the primary path from a clean state and improve recovery from the most likely real failure",
            "add a materially different regression or edge scenario and fix any general weakness it reveals",
            "review the diff and runtime behavior for correctness, security, data loss, and unintended scope expansion",
            "improve reproducibility, onboarding, accessibility, and packaging, then verify the documented path exactly"
        ]
        if task.category == .optimization {
            return "repeat the frozen benchmark, check correctness equivalence, inspect variance and memory pressure, and document a fair before/after comparison"
        }
        if task.category == .experiment || task.category == .data || task.category == .research {
            return "challenge the conclusion with a counterexample or alternate baseline, verify provenance and reproducibility, and tighten uncertainty and limitations"
        }
        return common[task.iteration % common.count]
    }

    private func recentFailureEvidence(from logs: [TaskLogEntry]) -> String {
        let messages = logs.reversed().compactMap { entry -> String? in
            guard entry.kind == .error || (entry.kind == .command && isFailedCommand(entry.message)) else { return nil }
            return String(sanitizedLogText(entry.message).prefix(600))
        }.prefix(3)
        return messages.isEmpty ? "- No recent failed command captured." : messages.map { "- \($0)" }.joined(separator: "\n")
    }

    private func isFailedCommand(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("command failed") || lower.contains("build failed") || lower.contains("test failed") { return true }
        guard let range = lower.range(of: "exit code ") else { return false }
        let suffix = lower[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber || $0 == "-" }
        return (Int(String(digits)) ?? 0) != 0
    }

    private func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
