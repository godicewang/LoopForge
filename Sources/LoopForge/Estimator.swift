import Foundation

struct TaskEstimator {
    func estimate(
        request: String,
        quality: QualityTier,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        workspacePath: String? = nil
    ) -> TaskEstimate {
        let text = request.lowercased()
        let category = classify(text)
        let authorization = inferAuthorization(text)
        let visualAuditRequired = requiresVisualAudit(request: request, category: category)
        var score = baseScore(for: category)

        let complexTerms = [
            "完整", "全自动", "生产", "上线", "发布", "多人", "实时", "支付", "登录", "权限", "同步",
            "数据库", "后端", "前端", "api", "部署", "打包", "性能", "安全", "baseline", "实验", "训练",
            "修复", "排查", "崩溃", "重构", "优化", "提速", "迁移", "升级", "bug", "debug", "refactor", "optimize",
            "complete", "production", "release", "realtime", "authentication", "database", "backend", "frontend", "deploy",
            "migration", "accessibility", "benchmark", "security", "package", "integration", "end-to-end"
        ]
        let scopeTerms = ["以及", "并且", "同时", "还要", "包括", "等等", "and", "also", "with"]
        score += min(30, complexTerms.filter { text.contains($0) }.count * 4)
        score += min(12, scopeTerms.filter { text.contains($0) }.count * 3)
        score += min(12, request.count / 80)
        score = min(100, score)

        let baseMinutes: Double
        switch category {
        case .script: baseMinutes = 28
        case .desktopAutomation: baseMinutes = 45
        case .library: baseMinutes = 55
        case .maintenance: baseMinutes = 75
        case .optimization: baseMinutes = 110
        case .research: baseMinutes = 70
        case .experiment: baseMinutes = 85
        case .data: baseMinutes = 110
        case .web: baseMinutes = 100
        case .miniProgram: baseMinutes = 120
        case .game: baseMinutes = 135
        case .nativeApp: baseMinutes = 150
        case .general: baseMinutes = 90
        }

        let qualityMultiplier: Double
        switch quality {
        case .lightweight: qualityMultiplier = 0.42
        case .low: qualityMultiplier = 0.65
        case .medium: qualityMultiplier = 1.35
        case .high: qualityMultiplier = 3.0
        }
        let scopeMultiplier = 0.8 + (Double(score) / 100.0)
        let workspace = workspaceScale(at: workspacePath)
        let workloadMinutes = baseMinutes * qualityMultiplier * scopeMultiplier * workspace.multiplier
        let additiveFactor: Double
        switch quality {
        case .lightweight: additiveFactor = 0.30
        case .low: additiveFactor = 0.50
        case .medium: additiveFactor = 0.75
        case .high: additiveFactor = 1.0
        }
        var minutes = Double(quality.defaultRuntimeMinutes) + workloadMinutes * additiveFactor
        minutes = min(Double(quality.maximumRecommendedRuntimeMinutes), minutes)
        minutes = (minutes / 15).rounded(.up) * 15

        let model = chooseModel(
            category: category,
            authorization: authorization,
            quality: quality,
            complexity: score,
            physicalMemory: physicalMemory,
            visualAuditRequired: visualAuditRequired
        )
        let workspaceEvidence = workspace.description.map { " Workspace evidence: \($0)." } ?? ""
        let modeDefault = TimeInterval(quality.defaultRuntimeMinutes * 60).compactDuration
        let explanation = "Classified as \(category.title) · \(authorization.title), complexity \(score)/100. The estimate starts from the \(quality.title) default of \(modeDefault), then adds task scope, project scale, and expected official-Codex iteration time. You can raise or lower the final hard target before starting.\(workspaceEvidence)"
        return TaskEstimate(
            category: category,
            authorization: authorization,
            recommendedSeconds: minutes * 60,
            model: model,
            complexityScore: score,
            explanation: explanation + (visualAuditRequired ? " Visual implementation was detected, so screenshot-based review is mandatory." : ""),
            visualAuditRequired: visualAuditRequired
        )
    }

    func requiresVisualAudit(request: String, category: TaskCategory) -> Bool {
        if category.normallyRequiresVisualAudit { return true }
        let text = request.lowercased()
        let visualTerms = [
            "user interface", "interface", "layout", "visual", "design", "screenshot", "screen",
            "swiftui", "uikit", "appkit", "frontend", "front-end", "responsive", "animation",
            "界面", "页面", "布局", "视觉", "设计", "截图", "交互", "动效", "前端"
        ]
        if visualTerms.contains(where: text.contains) { return true }
        let tokens = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return !tokens.isDisjoint(with: ["ui", "ux", "css"])
    }

    func classify(_ text: String) -> TaskCategory {
        if isInteractiveSurfaceAutomation(text) { return .desktopAutomation }
        if containsAny(text, ["性能优化", "提升性能", "提升效率", "运行效率", "加速", "提速", "降低内存", "降低延迟", "吞吐", "profile", "profiling", "optimize", "performance"]){ return .optimization }
        if containsAny(text, [
            "修复", "排查", "报错", "崩溃", "bug", "debug", "重构", "refactor", "代码审查", "review code", "依赖升级", "版本升级", "迁移代码", "补测试", "改造现有",
            "fix", "repair", "defect", "crash", "failing test", "regression", "upgrade dependency", "migrate existing"
        ]){ return .maintenance }
        if containsAny(text, ["小程序", "wechat", "微信"]){ return .miniProgram }
        if containsAny(text, ["游戏", "game", "关卡", "玩法"]){ return .game }
        if containsAny(text, ["实验", "baseline", "benchmark", "消融", "论文复现"]){ return .experiment }
        if containsAny(text, ["调研", "研究报告", "技术选型", "literature review", "research report", "research", "compare options"]){ return .research }
        let hasExplicitNativeSurface = containsAny(text, [
            "mac app", "ios app", "android app", "swiftui", "uikit", "appkit",
            "xcode project", "桌面应用", "手机应用", "原生应用"
        ])
        if hasExplicitNativeSurface { return .nativeApp }
        if containsAny(text, [
            "网站", "web app", "web application", "网页", "dashboard", "后台",
            "管理系统", "h5", "html/css", "html", "frontend"
        ]) {
            return .web
        }
        if containsAny(text, ["macos", "ios", "android"]){ return .nativeApp }
        if containsAny(text, ["数据", "dataset", "机器学习", "深度学习", "训练", "模型", "爬虫"]){ return .data }
        if containsAny(text, ["脚本", "script", "自动化", "批处理", "一次性"]){ return .script }
        if containsAny(text, ["cli", "命令行", "sdk", "library", "库", "package"]){ return .library }
        return .general
    }

    func inferAuthorization(_ text: String) -> TaskAuthorization {
        let explicitReadOnly = containsAny(text, [
            "do not fix", "don't fix", "do not change", "no code changes", "read-only", "report only", "only report",
            "不要修复", "不要修改", "不要改代码", "只诊断", "仅诊断", "只审计", "仅审计", "只报告"
        ])
        if explicitReadOnly && containsAny(text, ["diagnose", "investigate", "root cause", "why", "诊断", "排查", "定位", "为什么"]) {
            return .diagnosis
        }
        if explicitReadOnly && containsAny(text, ["audit", "review", "inspect", "评审", "审计", "代码审查", "检查代码"]) {
            return .audit
        }
        let changeTerms = [
            "build", "create", "implement", "fix", "repair", "refactor", "optimize", "upgrade", "migrate", "add ", "change ",
            "构建", "创建", "开发", "实现", "修复", "改造", "重构", "优化", "升级", "迁移", "新增", "修改"
        ]
        if containsAny(text, changeTerms) { return .buildOrModify }
        if containsAny(text, ["audit", "review", "inspect", "评审", "审计", "代码审查", "检查代码"]){ return .audit }
        if containsAny(text, ["diagnose", "investigate", "root cause", "why does", "诊断", "排查原因", "定位原因", "为什么"]){ return .diagnosis }
        if containsAny(text, ["research", "compare", "report", "baseline", "experiment", "调研", "研究", "报告", "实验", "选型"]){ return .research }
        return .buildOrModify
    }

    private func baseScore(for category: TaskCategory) -> Int {
        switch category {
        case .script: return 18
        case .desktopAutomation: return 34
        case .library: return 32
        case .maintenance: return 42
        case .optimization: return 55
        case .research: return 40
        case .experiment: return 45
        case .data: return 52
        case .web: return 48
        case .miniProgram: return 54
        case .game: return 58
        case .nativeApp: return 62
        case .general: return 40
        }
    }

    private func chooseModel(
        category: TaskCategory,
        authorization: TaskAuthorization,
        quality: QualityTier,
        complexity: Int,
        physicalMemory: UInt64,
        visualAuditRequired: Bool
    ) -> ModelProfile {
        let memoryGB = Double(physicalMemory) / 1_073_741_824
        if visualAuditRequired {
            if memoryGB >= 40 { return .advancedVisualAuditor }
            if memoryGB >= 20 { return .visualAuditor }
        }
        if memoryGB < 20 { return .ecoCoder }
        if visualAuditRequired { return .visualAuditor }
        if (quality == .lightweight || quality == .low) && complexity < 62 { return .ecoCoder }
        if category == .experiment || category == .data || category == .research || authorization == .research { return .balancedAgent }
        // Software delivery benefits more from a coding-specialized agent than
        // from a similarly light active-parameter general model. On a 48 GB M4
        // the 19 GB MoE coder leaves ample headroom while only activating ~3.3B.
        if memoryGB >= 32 { return .deepCoder }
        return complexity >= 68 ? .balancedAgent : .ecoCoder
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func isInteractiveSurfaceAutomation(_ text: String) -> Bool {
        let surfaces = [
            "google chrome", "chrome浏览器", "google浏览器", "当前浏览器", "浏览器中", "浏览器里",
            "chatgpt.com", "当前网页", "已打开的网页", "existing chrome", "current browser", "open browser",
            "finder", "xcode中", "在xcode", "桌面软件", "desktop app"
        ]
        let actions = [
            "打开", "点击", "输入", "新窗口", "窗口", "标签页", "tab", "登录账号", "当前账号",
            "下载", "保存图片", "生成图片", "生成一张", "open ", "click", "type", "new window",
            "new tab", "signed-in", "logged-in", "download", "use my account"
        ]
        return containsAny(text, surfaces) && containsAny(text, actions)
    }

    private func workspaceScale(at path: String?) -> (multiplier: Double, description: String?) {
        guard let path, !path.isEmpty else { return (1.0, nil) }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let ignored: Set<String> = [".git", ".build", "build", "dist", "node_modules", "Pods", ".venv", "venv", "__pycache__"]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return (1.0, nil) }

        var files = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            if ignored.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
            if files >= 2_000 { break }
        }

        let multiplier: Double
        if files <= 10 && bytes <= 50_000 {
            multiplier = 0.45
        } else if files <= 80 && bytes <= 2_000_000 {
            multiplier = 0.70
        } else if files <= 400 && bytes <= 15_000_000 {
            multiplier = 0.90
        } else {
            multiplier = 1.10
        }
        return (multiplier, "\(files) project files, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) sampled")
    }
}
