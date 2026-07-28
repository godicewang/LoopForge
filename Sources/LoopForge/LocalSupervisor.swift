import Foundation

struct SupervisorDecision: Codable, Equatable {
    let status: String
    let completionApproved: Bool
    let findings: [String]
    let nextInstruction: String
    let verification: [String]
    let visualPassed: Bool?
    let visualSummary: String?
    var requirementCoverage: [String: String]? = nil
    var externalDependencies: [String]? = nil
    var evidenceCitations: [String]? = nil
    var confidence: Double? = nil
    var gapKeys: [String]? = nil

    static let unavailable = SupervisorDecision(
        status: "continue",
        completionApproved: false,
        findings: ["The Loop Control Agent audit was unavailable."],
        nextInstruction: "Re-inspect the user goal, real workspace, current failures, and acceptance gates. Continue with the highest-value verified improvement.",
        verification: ["Run the real primary path and retain its exact result."],
        visualPassed: nil,
        visualSummary: nil
    )

    var workerBrief: String {
        let findingText = findings.isEmpty ? "- No additional finding." : findings.map { "- \($0)" }.joined(separator: "\n")
        let verificationText = verification.isEmpty ? "- Re-run the real primary path." : verification.map { "- \($0)" }.joined(separator: "\n")
        let coverageText = (requirementCoverage ?? [:]).isEmpty
            ? "- No model-authored coverage map was returned."
            : (requirementCoverage ?? [:]).sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        let dependencyText = (externalDependencies ?? []).isEmpty
            ? "- None identified from verified evidence."
            : (externalDependencies ?? []).map { "- \($0)" }.joined(separator: "\n")
        let citationText = (evidenceCitations ?? []).isEmpty
            ? "- No specific citation returned."
            : (evidenceCitations ?? []).map { "- \($0)" }.joined(separator: "\n")
        return """
        LOCAL SUPERVISOR DECISION: \(status.uppercased())
        COMPLETION APPROVED: \(completionApproved ? "yes" : "no")

        FINDINGS
        \(findingText)

        REQUIRED NEXT DEVELOPMENT ACTION
        \(nextInstruction)

        REQUIRED VERIFICATION
        \(verificationText)

        REQUIREMENT COVERAGE
        \(coverageText)

        EXTERNAL DEPENDENCIES
        \(dependencyText)

        EVIDENCE CITATIONS
        \(citationText)

        CONFIDENCE
        \(confidence.map { String(format: "%.2f", $0) } ?? "Not supplied")

        VISUAL REVIEW
        \(visualSummary ?? "Not required or no visual decision available.")
        """
    }
}

struct ProjectIdentity: Codable, Equatable {
    let displayName: String
    let shortName: String
}

struct MissionRewriteCandidate: Codable, Equatable, Sendable {
    let id: String
    let rewrittenRequest: String
    let preservationNotes: [String]
}

struct MissionCandidateAssessment: Codable, Equatable, Sendable {
    let id: String
    let meaningPreserved: Bool
    let materialOmissions: [String]
    let unauthorizedAdditions: [String]
    let contradictions: [String]
    let score: Double
}

struct MissionRewriteAudit: Codable, Equatable, Sendable {
    let assessments: [MissionCandidateAssessment]
    let recommendedCandidateID: String?
    let retryRequired: Bool
    let summary: String
}

struct MissionRefinementResult: Equatable, Sendable {
    let selectedRequest: String
    let selectedCandidateID: String?
    let attempts: Int
    let auditSummary: String
    let usedOriginalFallback: Bool
}

/// The selected control model is an outer-loop reviewer. It receives bounded
/// code, harness, worker-feedback, and screenshot evidence, but never edits the
/// project. Its structured decision becomes the next Sub Agent instruction.
struct LocalSupervisor {
    private struct Message: Codable {
        let role: String
        let content: String
        let images: [String]?
        let thinking: String?

        init(role: String, content: String, images: [String]?, thinking: String? = nil) {
            self.role = role
            self.content = content
            self.images = images
            self.thinking = thinking
        }
    }

    private struct ChatRequest: Codable {
        struct Options: Codable {
            let temperature: Double
            let num_ctx: Int
            let num_predict: Int
        }

        let model: String
        let messages: [Message]
        let stream: Bool
        let think: Bool
        let format: String
        let options: Options
    }

    private struct ChatResponse: Codable {
        let message: Message
    }

    let endpoint: URL
    private let processRunner = ProcessRunner()
    private let ollama: OllamaManager

    init(endpoint: URL? = nil, ollama: OllamaManager = OllamaManager()) {
        self.endpoint = endpoint ?? URL(string: "http://\(AppConstants.ollamaHost)/api/chat")!
        self.ollama = ollama
    }

    /// A bounded text/JSON generation surface used by LoopForge itself for
    /// prompt refinement, stall diagnosis, and delivery-report narration.
    /// It does not edit the workspace and its time is never counted as Sub
    /// Agent runtime.
    func auxiliaryResponse(
        task: LoopTask,
        selection: AgentSelection,
        system: String,
        user: String,
        imagePaths: [String] = [],
        maxTokens: Int = 4_096,
        outputSchema: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        switch selection.provider {
        case .codex:
            return try await codexControlResponse(
                task: task,
                selection: selection,
                system: system,
                user: user,
                imagePaths: imagePaths,
                outputSchema: outputSchema,
                timeout: timeout ?? 600
            )
        case .api:
            guard let connection = selection.apiConnection,
                  let key = APIKeyVault.get(for: connection.id) else {
                throw LoopForgeError.runtimeUnavailable("The configured API key is unavailable.")
            }
            return try await OpenAICompatibleClient().complete(
                system: system,
                user: user,
                connection: connection,
                apiKey: key,
                reasoningEffort: selection.reasoningEffort,
                imagePaths: selection.supportsVision ? imagePaths : [],
                maxTokens: maxTokens,
                timeout: timeout ?? 120
            )
        case .local:
            guard let profile = selection.localProfile else {
                throw LoopForgeError.runtimeUnavailable("The configured local model is unavailable.")
            }
            try await ensureLocalRuntime(profile)
            let encodedImages = profile.supportsVision
                ? imagePaths.prefix(6).compactMap {
                    try? Data(contentsOf: URL(fileURLWithPath: $0)).base64EncodedString()
                }
                : []
            let payload = ChatRequest(
                model: profile.ollamaName,
                messages: [
                    Message(role: "system", content: system, images: nil),
                    Message(role: "user", content: user, images: encodedImages.isEmpty ? nil : encodedImages)
                ],
                stream: false,
                think: false,
                format: "json",
                options: .init(
                    temperature: 0.12,
                    num_ctx: min(profile.contextWindow, 32_768),
                    num_predict: maxTokens
                )
            )
            return try await responseContent(for: payload, timeout: timeout ?? 300)
        }
    }

    /// Keeps code-heavy evidence plus multimodal image tokens inside the
    /// 32K context used by the lightweight local reviewers. The head retains
    /// the goal and worker claim; the tail retains harness and visual evidence.
    static func boundedReviewText(_ text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        let marker = "\n\n[… \(text.count - limit) characters omitted to fit the local review context …]\n\n"
        let available = max(0, limit - marker.count)
        let headCount = Int(Double(available) * 0.58)
        let tailCount = available - headCount
        return String(text.prefix(headCount)) + marker + String(text.suffix(tailCount))
    }

    static func reviewUserMessage(
        task: LoopTask,
        deterministicBrief: String,
        phase: String,
        evidence: AuditEvidence
    ) -> String {
        let brief = boundedReviewText(deterministicBrief, limit: 8_000)
        let evidenceText = boundedReviewText(evidence.text, limit: 20_000)
        return """
        PHASE
        \(boundedReviewText(phase, limit: 500))

        LOOP CONTROL AGENT
        \(task.resolvedControlAgent.summary)

        SUB AGENT HARD ACTIVE-RUNTIME TARGET
        \(task.targetSeconds.compactDuration)

        AUTHORITATIVE LOOP BRIEF
        \(brief)

        POST-TURN EVIDENCE BUNDLE
        \(evidenceText)

        DETERMINISTIC REQUIREMENT-TO-EVIDENCE INVENTORY
        \(boundedReviewText(evidence.coverageText, limit: 6_000))
        """
    }

    func review(
        task: LoopTask,
        deterministicBrief: String,
        phase: String,
        evidence: AuditEvidence
    ) async throws -> SupervisorDecision {
        let system = """
        You are LoopForge's independent Loop Control Agent. You never edit the workspace. After every Sub Agent stage, you must skeptically compare the original user goal with the Sub Agent's feedback, the actual code/config excerpts, changed files, harness/build/test results, deterministic findings, and—when required—the real screenshots.

        Decide what is truly complete, what is only claimed, which defect or gap matters most, and the exact next development instruction for the Sub Agent. Audit correctness, real behavior, efficiency, robustness, security, accessibility, documentation, and scope as applicable. Audit strategic goal fit and the core product or experiment choice before rewarding implementation polish. For greenfield games in particular, require evidence that multiple mechanically distinct concepts were compared and that the chosen core loop has defensible novelty, replay depth, retention potential, solo-developer feasibility, and a playable or simulated validation; do not approve a familiar first idea merely because its UI and tests are polished. For visual work, inspect every supplied screenshot for goal alignment, hierarchy, spacing, clipping, state coverage, readability, consistency, affordances, and obvious placeholder quality. A screenshot's mere existence is never visual approval.

        Build an explicit requirement-coverage map. Use only these judgments: supported, partial, contradicted, not_assessed, or externally_blocked. Absence from the bounded screenshot set is not evidence that a feature is absent from the product. When the deterministic inventory says “not observed,” mark it not_assessed and request a targeted workspace or runtime inspection before declaring a product gap. Never discard older but still relevant evidence merely because a newer screenshot exists.

        Every material finding must cite a concrete path, command outcome, harness record, or screenshot identifier in evidenceCitations. Give a 0...1 confidence score. Never infer an individual asset's pixel dimensions, alpha quality, or source resolution from the dimensions of a composite screenshot; screenshot dimensions describe only the rendered capture. Inspect the actual asset metadata or source before making an asset-level claim. If model judgment conflicts with deterministic file metadata or a successful command, treat the deterministic evidence as authoritative and explicitly reconcile the contradiction.

        Give each open issue a stable, concise gap key in gapKeys. Do not repeat a previously issued action unless new evidence shows that it failed or remains incomplete. When evidence is unchanged, choose a different high-value verification or improvement instead of rephrasing the same instruction.

        Separate implementation gaps from external operating dependencies. Signing identities, publisher accounts, paid quota, production service credentials, legal acceptance, unavailable hardware, and user-owned datasets are not ordinary code defects. Identify them in externalDependencies. Require the Sub Agent to finish safe in-workspace preparation, contracts, mocks, tests, and handoff documentation, but do not repeatedly demand an impossible live integration or expand the user's scope without verified authority and credentials. A fully prepared workspace may be approved while requirements are marked externally_blocked, provided the dependency and handoff are directly evidenced.

        Preserve the user's chosen interaction surface and account boundary. When the goal names an existing signed-in browser, desktop app, website session, or UI workflow, judge completion on direct actions in that exact surface. Never reinterpret it as API integration, Selenium/WebDriver development, a new automation project, credential extraction, or a different model/service unless the user explicitly authorized that substitution. A ChatGPT website session is not an API credential. Never invent GPT-3.5 or any other model name absent from the goal and verified UI. If a browser extension, Browser/Chrome tool, Accessibility grant, or app-specific developer setting is genuinely missing, require one precise capability report and the smallest enabling action; do not issue speculative code work or consume time repeating the blocker.

        Do not require real-user retention metrics, a live public audience, production App Store analytics, or real opponents from a project that has not been released. Before launch, judge replay and retention claims from reproducible simulations, balance tests, hands-on sessions, prototype comparison, telemetry contracts, and clearly labeled projections. Record real-user validation as a post-release external dependency, not an endlessly repeated implementation defect.

        Completion approval is exceptional: set it true only when the preliminary deterministic gates pass and the evidence directly supports the entire user goal. For visual work, the preliminary scan intentionally omits its own visual-approval gate; you must independently decide that gate from the fresh attached screenshots. Completion still requires usable screenshots and a visually acceptable implementation. Never approve from a completion claim alone.

        Return only one JSON object with exactly these keys:
        {"status":"continue|approve","completionApproved":false,"findings":["..."],"nextInstruction":"...","verification":["..."],"visualPassed":null,"visualSummary":null,"requirementCoverage":{"requirement":"supported|partial|contradicted|not_assessed|externally_blocked"},"externalDependencies":["..."],"evidenceCitations":["path or exact command result"],"confidence":0.0,"gapKeys":["stable-gap-key"]}
        `visualPassed` and `visualSummary` must be non-null for visual tasks. Keep the next instruction concrete, prioritized, and executable.
        """
        let user = Self.reviewUserMessage(
            task: task,
            deterministicBrief: deterministicBrief,
            phase: phase,
            evidence: evidence
        )
        let selection = task.resolvedControlAgent
        var content = try await reviewContent(
            task: task,
            selection: selection,
            system: system,
            user: user,
            evidence: evidence
        )
        if Self.decodeDecision(from: content) == nil {
            let repairUser = """
            Your previous audit response was not valid against the required JSON contract.
            Re-evaluate nothing and add no prose. Return the same decision as exactly one
            valid JSON object with every required key.

            PREVIOUS INVALID RESPONSE
            \(Self.boundedReviewText(content, limit: 6_000))

            ORIGINAL AUDIT INPUT
            \(user)
            """
            content = try await reviewContent(
                task: task,
                selection: selection,
                system: system,
                user: repairUser,
                evidence: evidence
            )
        }
        // Some Qwen3-VL/Ollama builds place a schema-formatted final response
        // in `thinking` even when thinking is disabled. Accept that field only
        // when normal content is empty; the strict decision decoder below still
        // rejects prose, partial reasoning, or any malformed response.
        guard let decision = Self.decodeDecision(from: content) else {
            throw LoopForgeError.runtimeUnavailable("The Loop Control Agent returned malformed audit JSON after one repair attempt: \(content.prefix(500))")
        }
        let coverageValidated = Self.enforcingCoverageForApproval(decision, evidence: evidence)
        if task.needsVisualAudit, coverageValidated.visualPassed == nil {
            return SupervisorDecision(
                status: "continue",
                completionApproved: false,
                findings: coverageValidated.findings + ["The local visual reviewer omitted its required screenshot verdict."],
                nextInstruction: coverageValidated.nextInstruction,
                verification: coverageValidated.verification + ["Re-capture the running UI and obtain an explicit local visual verdict."],
                visualPassed: false,
                visualSummary: coverageValidated.visualSummary ?? "Visual approval was denied because the local model did not return a required verdict.",
                requirementCoverage: coverageValidated.requirementCoverage,
                externalDependencies: coverageValidated.externalDependencies,
                evidenceCitations: coverageValidated.evidenceCitations,
                confidence: coverageValidated.confidence,
                gapKeys: coverageValidated.gapKeys
            )
        }
        return coverageValidated
    }

    /// For a Local Deployment control model, produces three independent mission
    /// rewrites concurrently, then performs a separate semantic-equivalence audit
    /// against the verbatim user request. Codex and API control agents bypass this
    /// pipeline and use the original request unchanged. No local rewrite can reach
    /// the worker unless the independent assessment proves that it preserved scope,
    /// constraints, quantities, tools, and authority.
    func refineMission(for task: LoopTask) async -> MissionRefinementResult {
        guard task.resolvedControlAgent.provider == .local else {
            return MissionRefinementResult(
                selectedRequest: task.request,
                selectedCandidateID: nil,
                attempts: 0,
                auditSummary: "Parallel mission rewriting is not required for Codex or API Loop Control Agents. The original request is used verbatim.",
                usedOriginalFallback: true
            )
        }
        guard task.request.count <= 40_000 else {
            return MissionRefinementResult(
                selectedRequest: task.request,
                selectedCandidateID: nil,
                attempts: 0,
                auditSummary: "The verbatim request exceeds the bounded semantic-audit context. LoopForge preserved it unchanged instead of risking a lossy rewrite.",
                usedOriginalFallback: true
            )
        }
        let selection = task.resolvedControlAgent
        if let profile = selection.localProfile {
            do {
                try await ensureLocalRuntime(profile)
            } catch {
                return MissionRefinementResult(
                    selectedRequest: task.request,
                    selectedCandidateID: nil,
                    attempts: 0,
                    auditSummary: "Mission refinement could not prepare the selected control model. The original request was preserved verbatim: \(sanitizedLogText(error.localizedDescription))",
                    usedOriginalFallback: true
                )
            }
        }

        var lastSummary = "No rewrite round completed."
        for attempt in 1...3 {
            do {
                async let coverage = rewriteCandidate(
                    id: "coverage",
                    strategy: "Coverage-first: organize every explicit outcome, constraint, quantity, named tool or surface, quality expectation, and acceptance condition without changing any of them.",
                    task: task,
                    selection: selection
                )
                async let execution = rewriteCandidate(
                    id: "execution",
                    strategy: "Execution-first: make the requested actions, artifacts, boundaries, and evidence testable while preserving the exact original meaning and authorization.",
                    task: task,
                    selection: selection
                )
                async let risk = rewriteCandidate(
                    id: "boundary",
                    strategy: "Boundary-first: clarify ambiguity conservatively and foreground prohibitions, account/session constraints, non-goals, and failure conditions without adding scope.",
                    task: task,
                    selection: selection
                )
                let candidates = try await [coverage, execution, risk]
                let audit = try await auditMissionRewrites(
                    original: task.request,
                    candidates: candidates,
                    task: task,
                    selection: selection
                )
                lastSummary = audit.summary
                if let selected = Self.bestConsistentCandidate(candidates: candidates, audit: audit) {
                    return MissionRefinementResult(
                        selectedRequest: selected.rewrittenRequest,
                        selectedCandidateID: selected.id,
                        attempts: attempt,
                        auditSummary: audit.summary,
                        usedOriginalFallback: false
                    )
                }
            } catch {
                lastSummary = "Rewrite round \(attempt) failed its independent generation or audit contract: \(sanitizedLogText(error.localizedDescription))"
            }
        }

        return MissionRefinementResult(
            selectedRequest: task.request,
            selectedCandidateID: nil,
            attempts: 3,
            auditSummary: "\(lastSummary) No candidate was allowed through; the original request is the safe authoritative execution brief.",
            usedOriginalFallback: true
        )
    }

    static func bestConsistentCandidate(
        candidates: [MissionRewriteCandidate],
        audit: MissionRewriteAudit
    ) -> MissionRewriteCandidate? {
        guard candidates.count == 3, !audit.retryRequired else { return nil }
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let eligible = audit.assessments.filter { assessment in
            candidateByID[assessment.id] != nil
                && assessment.meaningPreserved
                && assessment.materialOmissions.isEmpty
                && assessment.unauthorizedAdditions.isEmpty
                && assessment.contradictions.isEmpty
                && assessment.score >= 0.90
        }
        guard !eligible.isEmpty else { return nil }
        let best = eligible.sorted {
            if $0.score == $1.score {
                let lhsRecommended = $0.id == audit.recommendedCandidateID
                let rhsRecommended = $1.id == audit.recommendedCandidateID
                return lhsRecommended == rhsRecommended ? $0.id < $1.id : lhsRecommended
            }
            return $0.score > $1.score
        }.first
        return best.flatMap { candidateByID[$0.id] }
    }

    private func rewriteCandidate(
        id: String,
        strategy: String,
        task: LoopTask,
        selection: AgentSelection
    ) async throws -> MissionRewriteCandidate {
        let system = """
        You are one of three independent mission editors. Rewrite the user's request into a precise execution brief, but do not solve it and do not inspect or edit the workspace.

        Preserve every explicit outcome, action, artifact, quantity, named product/model/browser/app/account/session, language, destination, timing choice, quality bar, constraint, permission boundary, prohibition, and acceptance condition. Do not invent APIs, technologies, credentials, models, deliverables, or authority. Do not delete unusual details merely to make the request simpler. Resolve ordinary wording ambiguity only with a conservative reversible assumption and label that assumption.

        Return only JSON:
        {"rewrittenRequest":"complete execution brief","preservationNotes":["specific original constraint retained"]}
        """
        let user = """
        INDEPENDENT EDITING STRATEGY
        \(strategy)

        VERBATIM ORIGINAL REQUEST
        <original_user_request>
        \(Self.boundedReviewText(task.request, limit: 20_000))
        </original_user_request>
        """
        let content = try await reviewContent(
            task: task,
            selection: selection,
            system: system,
            user: user,
            evidence: Self.emptyEvidence,
            ensureLocalRuntime: false
        )
        struct Payload: Codable {
            let rewrittenRequest: String
            let preservationNotes: [String]
        }
        guard let payload = Self.decodeJSONObject(Payload.self, from: content) else {
            throw LoopForgeError.runtimeUnavailable("Mission rewrite \(id) returned malformed JSON.")
        }
        let rewritten = payload.rewrittenRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewritten.isEmpty else {
            throw LoopForgeError.runtimeUnavailable("Mission rewrite \(id) was empty.")
        }
        return MissionRewriteCandidate(
            id: id,
            rewrittenRequest: Self.boundedReviewText(rewritten, limit: 24_000),
            preservationNotes: Array(payload.preservationNotes.prefix(20))
        )
    }

    private func auditMissionRewrites(
        original: String,
        candidates: [MissionRewriteCandidate],
        task: LoopTask,
        selection: AgentSelection
    ) async throws -> MissionRewriteAudit {
        let system = """
        You are LoopForge's independent semantic-contract auditor. You did not author any candidate. Compare the verbatim original request with all three rewrites. Eloquence, length, and implementation preference do not matter; semantic fidelity does.

        A candidate is inconsistent if it omits, weakens, contradicts, or silently changes any explicit outcome, action, artifact, quantity, named product/model/browser/app/account/session, language, destination, timing choice, quality bar, constraint, permission boundary, prohibition, or acceptance condition. It is also inconsistent if it invents a technology, API, credential, model, deliverable, destructive permission, or materially broader scope. Conservative structure and explicit acceptance evidence are allowed only when they do not change the requested outcome.

        Score each candidate from 0 to 1. `meaningPreserved` may be true only when all material meaning is retained. Recommend the highest-scoring fully consistent candidate. If none scores at least 0.90 with empty omission, addition, and contradiction lists, set retryRequired to true and recommend null.

        Return only JSON:
        {"assessments":[{"id":"coverage","meaningPreserved":true,"materialOmissions":[],"unauthorizedAdditions":[],"contradictions":[],"score":0.0}],"recommendedCandidateID":null,"retryRequired":false,"summary":"concise comparison"}
        """
        let encodedCandidates = String(
            data: try JSONEncoder().encode(candidates),
            encoding: .utf8
        ) ?? "[]"
        let user = """
        VERBATIM ORIGINAL REQUEST
        <original_user_request>
        \(Self.boundedReviewText(original, limit: 20_000))
        </original_user_request>

        THREE INDEPENDENT CANDIDATES
        \(Self.boundedReviewText(encodedCandidates, limit: 60_000))
        """
        let content = try await reviewContent(
            task: task,
            selection: selection,
            system: system,
            user: user,
            evidence: Self.emptyEvidence,
            ensureLocalRuntime: false
        )
        guard let audit = Self.decodeJSONObject(MissionRewriteAudit.self, from: content),
              Set(audit.assessments.map(\.id)).isSuperset(of: Set(candidates.map(\.id))) else {
            throw LoopForgeError.runtimeUnavailable("The independent mission audit returned malformed or incomplete JSON.")
        }
        return audit
    }

    private static let emptyEvidence = AuditEvidence(
        text: "No workspace evidence is permitted during mission rewriting.",
        screenshotPaths: [],
        visualInspection: nil
    )

    private static func decodeJSONObject<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        let stripped = strippedCodeFence(raw)
        if let data = stripped.data(using: .utf8),
           let direct = try? JSONDecoder().decode(T.self, from: data) {
            return direct
        }
        guard let object = firstJSONObject(in: stripped),
              let data = object.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func reviewContent(
        task: LoopTask,
        selection: AgentSelection,
        system: String,
        user: String,
        evidence: AuditEvidence,
        ensureLocalRuntime: Bool = true
    ) async throws -> String {
        switch selection.provider {
        case .local:
            guard let profile = selection.localProfile else {
                throw LoopForgeError.runtimeUnavailable("The selected local Loop Control Agent is missing.")
            }
            if ensureLocalRuntime { try await self.ensureLocalRuntime(profile) }
            let encodedImages: [String]?
            if profile.supportsVision {
                let images = evidence.screenshotPaths.prefix(6).compactMap { path in
                    try? Data(contentsOf: URL(fileURLWithPath: path)).base64EncodedString()
                }
                encodedImages = images.isEmpty ? nil : images
            } else {
                encodedImages = nil
            }
            let payload = ChatRequest(
                model: profile.ollamaName,
                messages: [
                    Message(role: "system", content: system, images: nil),
                    Message(role: "user", content: user, images: encodedImages)
                ],
                stream: false,
                think: false,
                format: "json",
                options: .init(temperature: 0.10, num_ctx: profile.contextWindow, num_predict: 4_096)
            )
            return try await responseContent(for: payload, timeout: 300)
        case .api:
            guard let connection = selection.apiConnection,
                  let key = APIKeyVault.get(for: connection.id) else {
                throw LoopForgeError.runtimeUnavailable("The selected Loop Control Agent API key is missing from macOS Keychain.")
            }
            return try await OpenAICompatibleClient().complete(
                system: system,
                user: user,
                connection: connection,
                apiKey: key,
                reasoningEffort: selection.reasoningEffort,
                imagePaths: selection.supportsVision ? evidence.screenshotPaths : [],
                maxTokens: 4_096
            )
        case .codex:
            return try await codexControlResponse(
                task: task,
                selection: selection,
                system: system,
                user: user,
                imagePaths: selection.supportsVision ? evidence.screenshotPaths : []
            )
        }
    }

    static func enforcingCoverageForApproval(
        _ decision: SupervisorDecision,
        evidence: AuditEvidence
    ) -> SupervisorDecision {
        guard decision.completionApproved || decision.status.lowercased() == "approve" else { return decision }
        let required = evidence.coverage.filter { $0.state != .notApplicable }
        let returned = (decision.requirementCoverage ?? [:]).reduce(into: [String: String]()) { result, item in
            result[item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = item.value.lowercased()
        }
        let hasExternalEvidence = !(decision.externalDependencies ?? []).isEmpty
        let unsupported = required.compactMap { item -> String? in
            let status = returned[item.requirement.lowercased()]
            return status == "supported" || (status == "externally_blocked" && hasExternalEvidence)
                ? nil
                : item.requirement
        }
        let citations = (decision.evidenceCitations ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !required.isEmpty, unsupported.isEmpty, !citations.isEmpty else {
            let detail = required.isEmpty
                ? "The supervisor did not return the required requirement-coverage map."
                : (!unsupported.isEmpty
                    ? "Completion lacks direct supported coverage for: \(unsupported.joined(separator: ", "))."
                    : "Completion approval did not cite any concrete path, command result, harness record, or screenshot.")
            return SupervisorDecision(
                status: "continue",
                completionApproved: false,
                findings: decision.findings + [detail],
                nextInstruction: decision.nextInstruction,
                verification: decision.verification + ["Inspect and directly verify every not_assessed, partial, or contradicted requirement before requesting approval. For externally blocked items, verify the local handoff and cite the dependency once."],
                visualPassed: decision.visualPassed,
                visualSummary: decision.visualSummary,
                requirementCoverage: decision.requirementCoverage,
                externalDependencies: decision.externalDependencies,
                evidenceCitations: decision.evidenceCitations,
                confidence: decision.confidence,
                gapKeys: decision.gapKeys
            )
        }
        return decision
    }

    static func decodeDecision(from raw: String) -> SupervisorDecision? {
        let stripped = strippedCodeFence(raw)
        if let data = stripped.data(using: .utf8),
           let direct = try? JSONDecoder().decode(SupervisorDecision.self, from: data) {
            return direct
        }
        guard let object = firstJSONObject(in: stripped),
              let data = object.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SupervisorDecision.self, from: data)
    }

    private static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }

    func projectIdentity(for task: LoopTask) async throws -> ProjectIdentity {
        let system = """
        You write compact, useful labels for a macOS engineering-agent sidebar.
        Return only JSON:
        {"displayName":"a memorable 2 to 5 word project or product name","shortName":"a 3 to 7 word plain-language description of the task"}

        shortName is not an acronym, code, brand, or initials. It must let a user
        distinguish this task at a glance by stating the concrete action and
        subject, for example "Fix Unity package errors", "Build wuxia NPC memory",
        or "Profile image pipeline latency". Preserve the request's language when
        that is clearer. Do not invent scope.
        """
        let workspaceName = URL(fileURLWithPath: task.workspacePath).lastPathComponent
        let user = "WORKSPACE: \(workspaceName)\nGOAL:\n\(Self.boundedReviewText(task.request, limit: 4_000))"
        let selection = task.resolvedControlAgent
        let content: String
        switch selection.provider {
        case .local:
            guard let profile = selection.localProfile else {
                throw LoopForgeError.runtimeUnavailable("The selected local Loop Control Agent is missing.")
            }
            try await ensureLocalRuntime(profile)
            let payload = ChatRequest(
                model: profile.ollamaName,
                messages: [
                    Message(role: "system", content: system, images: nil),
                    Message(role: "user", content: user, images: nil)
                ],
                stream: false,
                think: false,
                format: "json",
                options: .init(temperature: 0.2, num_ctx: min(profile.contextWindow, 8_192), num_predict: 256)
            )
            content = try await responseContent(for: payload, timeout: 120)
        case .api:
            guard let connection = selection.apiConnection,
                  let key = APIKeyVault.get(for: connection.id) else {
                throw LoopForgeError.runtimeUnavailable("The selected Loop Control Agent API key is missing from macOS Keychain.")
            }
            content = try await OpenAICompatibleClient().complete(
                system: system, user: user, connection: connection, apiKey: key,
                reasoningEffort: selection.reasoningEffort, maxTokens: 256
            )
        case .codex:
            content = try await codexControlResponse(
                task: task, selection: selection, system: system, user: user, imagePaths: []
            )
        }
        guard let data = content.data(using: .utf8),
              let identity = try? JSONDecoder().decode(ProjectIdentity.self, from: data) else {
            throw LoopForgeError.runtimeUnavailable("The local supervisor returned malformed project naming JSON.")
        }
        let name = identity.displayName
            .replacingOccurrences(of: "[^A-Za-z0-9 &'’-]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let taskSummary = identity.shortName
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2, name.count <= 48 else {
            throw LoopForgeError.runtimeUnavailable("The local supervisor returned an unusable project identity.")
        }
        let usableSummary = taskSummary.count >= 5 && taskSummary.count <= 64
            ? taskSummary
            : TaskNamePolicy.descriptiveSummary(request: task.request, fallback: name)
        return ProjectIdentity(displayName: name, shortName: usableSummary)
    }

    private func ensureLocalRuntime(_ profile: ModelProfile) async throws {
        try await ollama.ensureReady(contextWindow: profile.contextWindow) { _ in }
        try await ollama.requireInstalledModel(profile)
    }

    private func responseContent(for payload: ChatRequest, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "No response body"
            throw LoopForgeError.runtimeUnavailable("The local supervisor returned an invalid response: \(detail.prefix(400))")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let responseText = decoded.message.content.isEmpty
            ? (decoded.message.thinking ?? "")
            : decoded.message.content
        var content = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```"), let firstNewline = content.firstIndex(of: "\n") {
            content = String(content[content.index(after: firstNewline)...])
            if content.hasSuffix("```") { content = String(content.dropLast(3)) }
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func codexControlResponse(
        task: LoopTask,
        selection: AgentSelection,
        system: String,
        user: String,
        imagePaths: [String],
        outputSchema: String? = nil,
        timeout: TimeInterval = 600
    ) async throws -> String {
        guard let executable = CodexRuntime.executable else {
            throw LoopForgeError.executableMissing("Codex")
        }
        var arguments = [
            "exec", "--json", "--ephemeral", "--color", "never", "--skip-git-repo-check",
            "--disable", "plugins", "--disable", "multi_agent", "--ignore-user-config",
            "--model", selection.modelID,
            "--sandbox", selection.accessMode.sandboxMode,
            "--cd", task.workspacePath,
            "--config", "approval_policy=\"never\"",
            "--config", "sandbox_workspace_write.network_access=true",
            "--config", "project_root_markers=[]"
        ]
        if let reasoning = selection.reasoningEffort, !reasoning.isEmpty {
            arguments.append(contentsOf: ["--config", "model_reasoning_effort=\"\(reasoning)\""])
        }
        for path in imagePaths.prefix(4) where FileManager.default.fileExists(atPath: path) {
            arguments.append(contentsOf: ["--image", path])
        }
        var schemaURL: URL?
        if let outputSchema {
            let data = Data(outputSchema.utf8)
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw LoopForgeError.runtimeUnavailable("LoopForge supplied an invalid Codex output schema.")
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LoopForgeControlSchemas", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appendingPathComponent("\(UUID().uuidString).json")
            try data.write(to: url, options: .atomic)
            schemaURL = url
            arguments.append(contentsOf: ["--output-schema", url.path])
        }
        defer {
            if let schemaURL {
                try? FileManager.default.removeItem(at: schemaURL)
            }
        }
        arguments.append("-")
        let prompt = "\(system)\n\nCONTROL INPUT\n\(user)"
        let result = try await processRunner.run(
            executable: executable,
            arguments: arguments,
            environment: CodexRuntime.environment(),
            currentDirectory: URL(fileURLWithPath: task.workspacePath, isDirectory: true),
            stdin: Data(prompt.utf8),
            // Whole-graph evidence bundles can legitimately require several
            // minutes at Ultra reasoning. The node event stream still has its
            // independent 30-minute semantic watchdog; this bounded control
            // call simply must not manufacture repair work at three minutes.
            timeout: timeout
        )
        guard result.exitCode == 0 else {
            throw LoopForgeError.processFailed("Codex control review", result.exitCode, String(result.stderr.suffix(600)))
        }
        var lastMessage = ""
        for line in result.stdout.components(separatedBy: .newlines) {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["type"] as? String == "item.completed",
                  let item = event["item"] as? [String: Any],
                  item["type"] as? String == "agent_message",
                  let text = item["text"] as? String else { continue }
            lastMessage = text
        }
        guard !lastMessage.isEmpty else {
            throw LoopForgeError.runtimeUnavailable("Codex returned no structured control decision.")
        }
        return Self.strippedCodeFence(lastMessage)
    }

    private static func strippedCodeFence(_ raw: String) -> String {
        var content = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.hasPrefix("```"), let firstNewline = content.firstIndex(of: "\n") {
            content = String(content[content.index(after: firstNewline)...])
            if content.hasSuffix("```") { content = String(content.dropLast(3)) }
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
