import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var appStore
    @Environment(OperationsStore.self) private var operationsStore
    @Environment(CommunityStore.self) private var communityStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @AppStorage("easybusiness.selectedRootTab") private var selectedTab = 0
    @State private var pendingTab: Int?
    @State private var showsDraftExitPrompt = false
    @State private var showsGenerationTabBlocker = false
    @State private var showsOperationsReminderPrompt = false
    @State private var showsOperationsReminderSetup = false

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                DashboardView()
            }
            .tabItem { RootTabLabel(title: "首页", symbol: RootTabVisual.evaluation) }
            .tag(0)

            NavigationStack {
                StorefrontDiscoveryView()
            }
            .tabItem { RootTabLabel(title: "找旺铺", symbol: RootTabVisual.storefront) }
            .tag(2)

            NavigationStack {
                CommunityRootView()
            }
            .tabItem { RootTabLabel(title: "创业圈", symbol: RootTabVisual.community) }
            .tag(3)

            NavigationStack {
                FriendsRootView()
            }
            .tabItem { RootTabLabel(title: "好友", symbol: RootTabVisual.friends) }
            .tag(5)

            NavigationStack {
                MyWorkspaceView()
            }
            .tabItem { RootTabLabel(title: "我的", symbol: RootTabVisual.profile) }
            .tag(4)
        }
        .tint(selectedTab == 3 ? CommunityTheme.cobalt : AppTheme.blue)
        // Do not let a tab's intrinsic scroll content size the root container.
        // A root-level canvas also prevents black gaps during scene restoration.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
        .environment(
            \.dynamicTypeSize,
            isAccessibilityAudit ? .accessibility3 : systemDynamicTypeSize
        )
        .preferredColorScheme(isAccessibilityAudit ? .dark : nil)
        .onAppear {
            // UI regression runs use an in-memory model container but
            // @AppStorage is process-global. Reset only the test launch to the
            // product's first tab so a prior manual session cannot make an
            // otherwise deterministic journey start in Advisor or Profile.
            if ProcessInfo.processInfo.arguments.contains("-easybusiness-ui-regression") {
                selectedTab = 0
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-easybusiness-profile-regression") {
                selectedTab = 4
            }
            #endif
            if selectedTab == 1 { selectedTab = 0 }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-easybusiness-community-regression") {
                selectedTab = 3
            }
            #endif
        }
        .confirmationDialog(
            "离开前如何处理这份评估？",
            isPresented: $showsDraftExitPrompt,
            titleVisibility: .visible
        ) {
            Button("保留草稿并前往") {
                appStore.persistDraft()
                switchToPendingTab()
            }
            Button("放弃本次填写并前往", role: .destructive) {
                appStore.resetDraft()
                switchToPendingTab()
            }
            Button("继续填写") { pendingTab = nil }
        } message: {
            Text("保留后可在“我的”继续填写；放弃将清除本次品类、点位和经营参数，已生成报告不受影响。")
        }
        .alert("报告正在生成", isPresented: $showsGenerationTabBlocker) {
            Button("继续等待", role: .cancel) {}
        } message: {
            Text("为避免丢失当前分析进度，报告完成或主动取消前暂不能切换模块。")
        }
        .alert(item: communityNoticeBinding) { notice in
            Alert(
                title: Text(notice.title),
                message: notice.detail.map(Text.init),
                dismissButton: .default(Text("知道了")) {
                    communityStore.notice = nil
                }
            )
        }
        .confirmationDialog(
            "先设置经营提醒吗？",
            isPresented: $showsOperationsReminderPrompt,
            titleVisibility: .visible
        ) {
            Button("设置后前往") {
                operationsStore.acknowledgeFirstReminderPrompt()
                showsOperationsReminderSetup = true
            }
            Button("暂不设置并前往") {
                operationsStore.acknowledgeFirstReminderPrompt()
                finishOperationsExit()
            }
            Button("留在经营助手", role: .cancel) { pendingTab = nil }
        } message: {
            Text("日记录、周脉搏和月复盘提醒能减少漏记。此提示只出现一次，之后可在经营设置中随时修改。")
        }
        .sheet(isPresented: $showsOperationsReminderSetup, onDismiss: finishOperationsExit) {
            NavigationStack {
                OperatingReminderView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { showsOperationsReminderSetup = false }
                        }
                    }
            }
        }
        .task {
            appStore.configurePersistence(modelContext)
            operationsStore.configurePersistence(modelContext)
            communityStore.configurePersistence(modelContext)
            async let analysisStatus: Void = appStore.refreshServiceStatus()
            async let operationsStatus: Void = operationsStore.refreshServiceStatus()
            _ = await (analysisStatus, operationsStatus)
            if communityStore.serviceState == .checking {
                await communityStore.bootstrap()
            } else if communityStore.serviceState == .ready {
                await communityStore.refreshFortuneWallet()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A local development service or a production API can restart while
            // the app is in the background. Recheck on return instead of leaving
            // a stale service state on the next actionable screen.
            guard phase == .active else { return }
            Task {
                async let analysisStatus: Void = appStore.refreshServiceStatus()
                async let operationsStatus: Void = operationsStore.refreshServiceStatus()
                _ = await (analysisStatus, operationsStatus)
            }
        }
    }

    /// Intercept the requested tab before SwiftUI removes the current screen.
    /// An `onChange` observer runs too late: the form's `onDisappear` may have
    /// already cleared its editing flag, silently bypassing draft protection.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { requestedTab in
                guard requestedTab != selectedTab else { return }
                if appStore.isGeneratingReport {
                    showsGenerationTabBlocker = true
                    return
                }
                if appStore.isEditingOperatingPlan, appStore.hasIncompleteDraft {
                    pendingTab = requestedTab
                    showsDraftExitPrompt = true
                    return
                }
                if operationsStore.shouldOfferFirstReminderSetup {
                    operationsStore.acknowledgeFirstReminderPrompt()
                    pendingTab = requestedTab
                    showsOperationsReminderPrompt = true
                    return
                }
                selectedTab = requestedTab
            }
        )
    }

    private func switchToPendingTab() {
        guard let pendingTab else { return }
        appStore.isEditingOperatingPlan = false
        self.pendingTab = nil
        selectedTab = pendingTab
    }

    private func finishOperationsExit() {
        operationsStore.endOperationsAssistantSession()
        switchToPendingTab()
    }

    private var isAccessibilityAudit: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-easybusiness-accessibility-audit")
        #else
        false
        #endif
    }

    private var communityNoticeBinding: Binding<CommunityNotice?> {
        Binding(
            get: { communityStore.notice },
            set: { communityStore.notice = $0 }
        )
    }
}

enum RootTabVisual {
    static let evaluation = "house.fill"
    static let advisor = "wand.and.stars"
    static let storefront = "storefront"
    static let community = "person.2"
    static let friends = "message.fill"
    static let profile = "person.crop.circle"
    static let allSymbols = [evaluation, storefront, community, friends, profile]
}

/// Give every root destination the same optical canvas. SF Symbols intentionally
/// have different intrinsic widths, so a shared frame prevents a wide community
/// glyph from appearing larger than the other four destinations.
private struct RootTabLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .imageScale(.medium)
                .frame(width: 24, height: 24)
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("root.tab.\(title)")
    }
}

private struct MyWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var appStore
    @Environment(OperationsStore.self) private var operationsStore
    @Environment(CommunityStore.self) private var communityStore
    @Environment(StorefrontStore.self) private var storefrontStore
    @AppStorage("easybusiness.selectedRootTab") private var selectedTab = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                identityHero
                fortuneStrip
                decisionWorkspaceCard

                MyCenterSection(title: "内容与店铺", detail: "收藏、发布和互动集中管理") {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12
                    ) {
                        NavigationLink {
                            MyFavoriteStorefrontsView()
                        } label: {
                            MyCenterTile(
                                title: "收藏店铺",
                                detail: storefrontStore.favoriteIDs.isEmpty
                                    ? "还没有收藏" : "\(storefrontStore.favoriteIDs.count) 家待比较",
                                symbol: "heart.fill",
                                tint: AppTheme.red
                            )
                        }
                        .accessibilityIdentifier("profile.favoriteStorefronts")

                        NavigationLink {
                            if communityStore.profile == nil {
                                CommunityOnboardingView()
                            } else {
                                MyCommunityContentView()
                            }
                        } label: {
                            MyCenterTile(
                                title: "我的创业内容",
                                detail: communityStore.profile.map {
                                    "\($0.postCount) 篇发帖 · 评论可管理"
                                } ?? "加入创业圈后管理",
                                symbol: "text.bubble.fill",
                                tint: CommunityTheme.cobalt
                            )
                        }
                        .accessibilityIdentifier("profile.communityContent")

                        NavigationLink {
                            if communityStore.profile == nil {
                                CommunityOnboardingView()
                            } else {
                                CommunityNotificationsView(initialKind: "comments")
                            }
                        } label: {
                            MyCenterTile(
                                title: "回复与互动",
                                detail: communityStore.unreadCount > 0
                                    ? "\(communityStore.unreadCount) 条未读消息" : "评论、点赞和关注",
                                symbol: "bell.badge.fill",
                                tint: AppTheme.amber,
                                badge: communityStore.unreadCount
                            )
                        }
                        .accessibilityIdentifier("profile.communityReplies")

                        NavigationLink {
                            StorefrontMyListingsView()
                        } label: {
                            MyCenterTile(
                                title: "我的铺源",
                                detail: "查看、下架已发布店铺",
                                symbol: "storefront.fill",
                                tint: AppTheme.mint
                            )
                        }
                        .accessibilityIdentifier("profile.myStorefronts")
                    }
                    .buttonStyle(PressFeedbackStyle())
                }

                MyCenterSection(title: "常用服务", detail: "从结果和记录继续下一步") {
                    VStack(spacing: 0) {
                        NavigationLink {
                            OperationsHomeView()
                        } label: {
                            MyCenterRow(
                                title: "经营门店",
                                detail: operationsStore.workspace.profiles.isEmpty
                                    ? "创建门店并开始记录经营数据"
                                    : "\(operationsStore.workspace.profiles.count) 家门店 · 查看脉搏与复盘",
                                symbol: "chart.line.uptrend.xyaxis",
                                tint: AppTheme.mint
                            )
                        }
                        MyCenterDivider()
                        NavigationLink {
                            FriendsRootView()
                        } label: {
                            MyCenterRow(
                                title: "好友与群组",
                                detail: "继续创业伙伴、群聊和顾问协作",
                                symbol: "person.2.fill",
                                tint: CommunityTheme.cobalt
                            )
                        }
                        MyCenterDivider()
                        NavigationLink {
                            ProfileView()
                        } label: {
                            MyCenterRow(
                                title: "使用与数据设置",
                                detail: "本机数据、服务状态与隐私说明",
                                symbol: "lock.doc.fill",
                                tint: AppTheme.periwinkle
                            )
                        }
                        .accessibilityIdentifier("profile.dataSettings")
                    }
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AppTheme.border, lineWidth: 0.8)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 112)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            communityStore.configurePersistence(modelContext)
            if communityStore.serviceState == .checking {
                await communityStore.bootstrap()
            } else if communityStore.serviceState == .ready {
                async let wallet: Void = communityStore.refreshFortuneWallet()
                async let account: Void = communityStore.refreshAccountProfile()
                _ = await (wallet, account)
            }
        }
    }

    @ViewBuilder
    private var identityHero: some View {
        if let profile = communityStore.profile {
            HStack(spacing: 15) {
                NavigationLink {
                    MyAccountInformationView()
                } label: {
                    HStack(spacing: 13) {
                        CommunityAvatar(profile: profile, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Text(profile.nickname)
                                    .font(.title3.bold())
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                if communityStore.accountProfile?.identityStatus == .verified {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundStyle(AppTheme.mint)
                                        .accessibilityLabel("已实名认证")
                                }
                            }
                            Text(profile.role.title)
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.deepClay)
                            Text("查看个人信息")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 2)

                HStack(spacing: 15) {
                    NavigationLink {
                        CommunityConnectionsView(
                            userID: profile.id,
                            kind: "following",
                            title: "关注"
                        )
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(profile.followingCount)")
                                .font(.headline.bold().monospacedDigit())
                            Text("关注")
                                .font(.caption2)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 42, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("关注 \(profile.followingCount) 人")

                    NavigationLink {
                        CommunityConnectionsView(
                            userID: profile.id,
                            kind: "followers",
                            title: "粉丝"
                        )
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(profile.followerCount)")
                                .font(.headline.bold().monospacedDigit())
                            Text("粉丝")
                                .font(.caption2)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 42, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("粉丝 \(profile.followerCount) 人")
                }
            }
            .appCard(contentPadding: 16)
            .accessibilityIdentifier("profile.personalInformation")
        } else {
            Button {
                selectedTab = 3
            } label: {
                HStack(spacing: 15) {
                    FeatureIcon(symbol: "person.crop.circle.badge.plus", tint: AppTheme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("建立你的创业身份")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("设置昵称后可管理头像、联系方式、内容与财神币。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(AppTheme.deepClay)
                }
                .appCard(contentPadding: 16)
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityIdentifier("profile.personalInformation")
        }
    }

    @ViewBuilder
    private var fortuneStrip: some View {
        if let wallet = communityStore.fortuneWallet {
            HStack(spacing: 10) {
                NavigationLink {
                    FortuneCoinCenterView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(wallet.balance) 财神币")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text(
                                wallet.checkedInToday
                                    ? "今日已获得 \(wallet.dailyEarned)/\(wallet.dailyEarnCap) 枚"
                                    : "签到 +3 · 连签 \(wallet.checkInStreak) 天"
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        if wallet.checkedInToday {
                            Label("已签到", systemImage: "checkmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.mint)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("profile.fortuneCenter")

                if !wallet.checkedInToday {
                    Button {
                        Task { await communityStore.checkInFortuneWallet() }
                    } label: {
                        Text("签到 +3")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(AppTheme.deepClay, in: Capsule())
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .accessibilityIdentifier("profile.fortuneCheckIn")
                }
            }
            .padding(14)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.amber.opacity(0.18), lineWidth: 0.9)
            }
        }
    }

    private var decisionWorkspaceCard: some View {
        NavigationLink {
            MyDecisionWorkspaceView()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("我的开店决策台")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("评估档案、候选点与未完成方案")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.14), in: Circle())
                }
                HStack(spacing: 10) {
                    DecisionMetric(value: "\(appStore.reports.count)", title: "评估档案")
                    DecisionMetric(value: "\(unfinishedDecisionCount)", title: "待完善")
                    DecisionMetric(
                        value: latestDecisionScore,
                        title: "最新结论"
                    )
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [AppTheme.deepClay, AppTheme.navy],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: AppTheme.deepClay.opacity(0.17), radius: 18, y: 10)
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityIdentifier("profile.decisionWorkspace")
    }

    private var unfinishedDecisionCount: Int {
        appStore.archivedDrafts.count + (appStore.hasIncompleteDraft ? 1 : 0)
    }

    private var latestDecisionScore: String {
        guard let report = appStore.reports.first else { return "—" }
        if report.isStale { return "待复核" }
        guard let score = report.assessmentScores?.overall else { return "已完成" }
        return String(format: "%.1f", score)
    }

    private var accountCompletionText: String {
        var completed = 1 // nickname
        if communityStore.profile?.avatarURL != nil { completed += 1 }
        if communityStore.profile?.bio.isEmpty == false { completed += 1 }
        if communityStore.accountProfile?.phoneMasked != nil { completed += 1 }
        if let identityStatus = communityStore.accountProfile?.identityStatus,
           identityStatus != .notSubmitted {
            completed += 1
        }
        return completed == 5 ? "个人资料已完善" : "个人资料 \(completed)/5 · 点击继续完善"
    }
}

private struct MyDecisionWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppStore.self) private var appStore
    @State private var resumeRoute: DraftResumeRoute?
    @State private var reportsExpanded = false
    @State private var draftsExpanded = false
    @State private var managesReports = false
    @State private var managesDrafts = false
    @State private var selectedReportIDs: Set<UUID> = []
    @State private var selectedDraftIDs: Set<String> = []
    @State private var showsSelectedReportDeletion = false
    @State private var showsLowScoreDeletion = false
    @State private var showsSelectedDraftDeletion = false

    private let currentDraftID = "current-opening-plan"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                reportArchiveSection
                unfinishedDraftSection
            }
            .padding(20)
            // The root tab bar is intentionally floating on newer iOS
            // versions. Reserve room so the final settings row remains fully
            // readable and tappable rather than sitting beneath it.
            .padding(.bottom, 104)
        }
        .background(AppBackdrop(accent: AppTheme.periwinkle))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if managesReports || managesDrafts {
                workspaceManagementDock
            }
        }
        .navigationTitle("开店决策台")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            appStore.configurePersistence(modelContext)
        }
        .navigationDestination(item: $resumeRoute) { route in
            if route.location != nil {
                InvestmentPlanView()
            } else {
                BusinessTypePickerView()
            }
        }
        .confirmationDialog("删除已选评估档案？", isPresented: $showsSelectedReportDeletion) {
            Button("删除 \(selectedReportIDs.count) 份档案", role: .destructive) {
                deleteSelectedReports()
            }
        } message: {
            Text("将同时删除这些报告在本机保存的核验进度；此操作无法恢复。")
        }
        .confirmationDialog("一键删除中低分档案？", isPresented: $showsLowScoreDeletion) {
            Button("删除 \(mediumAndLowScoreReports.count) 份档案", role: .destructive) {
                appStore.deleteReports(mediumAndLowScoreReports)
                selectedReportIDs.subtract(mediumAndLowScoreReports.map(\.id))
                if appStore.reports.isEmpty { managesReports = false }
            }
        } message: {
            Text("将删除综合分低于 7 分的报告。高分报告和未完成评估不会受影响。")
        }
        .confirmationDialog("删除已选未完成评估？", isPresented: $showsSelectedDraftDeletion) {
            Button("删除 \(selectedDraftIDs.count) 份草稿", role: .destructive) {
                deleteSelectedDrafts()
            }
        } message: {
            Text("只删除本机草稿；已经生成的评估档案不会受影响。")
        }
    }

    private var reportArchiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeader(
                title: "评估档案",
                detail: appStore.reports.isEmpty ? "完成研判后会保存在这里" : "最新 3 份优先展示 · 共 \(appStore.reports.count) 份",
                managesItems: managesReports,
                canManage: !appStore.reports.isEmpty,
                manageIdentifier: "profile.manageReports"
            ) {
                managesReports.toggle()
                if managesReports {
                    reportsExpanded = true
                    managesDrafts = false
                    selectedDraftIDs.removeAll()
                }
                if !managesReports {
                    reportsExpanded = false
                    selectedReportIDs.removeAll()
                }
            }

            if appStore.reports.isEmpty {
                VStack(spacing: 12) {
                    InlineStatusCard(
                        title: "还没有评估档案",
                        detail: "完成一次小易 Agent 深度研判后，可在这里回看、比较或继续补充现场证据。",
                        tint: AppTheme.periwinkle,
                        symbol: "doc.text.magnifyingglass"
                    )
                    if draftItems.isEmpty {
                        Button {
                            if appStore.startNewEvaluation() {
                                resumeRoute = .current(location: nil)
                            }
                        } label: {
                            PrimaryActionLabel(title: "新建一次评估", systemImage: "plus")
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .accessibilityIdentifier("profile.startEvaluation")
                    }
                }
            } else {
                ForEach(displayedReports) { report in
                    if managesReports {
                        Button {
                            toggleReportSelection(report.id)
                        } label: {
                            HStack(spacing: 10) {
                                SelectionMark(isSelected: selectedReportIDs.contains(report.id))
                                ReportRow(report: report, groupName: appStore.reportGroup(for: report)?.name)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink { ReportDetailView(report: report) } label: {
                            ReportRow(report: report, groupName: appStore.reportGroup(for: report)?.name)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !managesReports {
                    collectionFooter(
                        count: appStore.reports.count,
                        isExpanded: $reportsExpanded,
                        destinationTitle: "进入完整档案与候选点对比"
                    )
                }
            }
        }
    }

    private var unfinishedDraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeader(
                title: "未完成的评估",
                detail: draftItems.isEmpty ? "没有待继续的草稿" : "最新 3 份优先展示 · 最多保留 10 份",
                managesItems: managesDrafts,
                canManage: !draftItems.isEmpty,
                manageIdentifier: "profile.manageDrafts"
            ) {
                managesDrafts.toggle()
                if managesDrafts {
                    draftsExpanded = true
                    managesReports = false
                    selectedReportIDs.removeAll()
                }
                if !managesDrafts {
                    draftsExpanded = false
                    selectedDraftIDs.removeAll()
                }
            }

            if draftItems.isEmpty {
                Text("新建评估后，离开填写流程时选择“保留草稿”，即可从这里继续。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .appCard()
            } else {
                ForEach(displayedDrafts) { item in
                    if managesDrafts {
                        Button {
                            toggleDraftSelection(item.id)
                        } label: {
                            HStack(spacing: 10) {
                                SelectionMark(isSelected: selectedDraftIDs.contains(item.id))
                                DraftWorkspaceRow(item: item)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            resume(item)
                        } label: {
                            DraftWorkspaceRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            item.isCurrent ? "profile.resumeCurrentDraft" : "profile.resumeArchivedDraft.\(item.id)"
                        )
                    }
                }

                if !managesDrafts, draftItems.count > 3 {
                    Button {
                        withAnimation(.snappy) { draftsExpanded.toggle() }
                    } label: {
                        Label(
                            draftsExpanded ? "收起未完成评估" : "展开全部 \(draftItems.count) 份",
                            systemImage: draftsExpanded ? "chevron.up" : "chevron.down"
                        )
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var workspaceManagementDock: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(managesReports ? "档案管理" : "草稿管理")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("profile.managementDock")
                    Text(
                        managesReports
                            ? "已选 \(selectedReportIDs.count) 份"
                            : "已选 \(selectedDraftIDs.count) 份"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button("完成") {
                    withAnimation(.snappy) {
                        managesReports = false
                        managesDrafts = false
                        reportsExpanded = false
                        draftsExpanded = false
                        selectedReportIDs.removeAll()
                        selectedDraftIDs.removeAll()
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(AppTheme.blue)
            }

            HStack(spacing: 10) {
                if managesReports {
                    Menu {
                        Button("移到未分组") { moveSelectedReports(to: nil) }
                        ForEach(appStore.reportGroups) { group in
                            Button(group.name) { moveSelectedReports(to: group.id) }
                        }
                    } label: {
                        Label("移动", systemImage: "folder")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedReportIDs.isEmpty)
                    .accessibilityIdentifier("profile.moveSelectedReports")
                }
                Button(role: .destructive) {
                    if managesReports {
                        showsSelectedReportDeletion = true
                    } else {
                        showsSelectedDraftDeletion = true
                    }
                } label: {
                    Label("删除已选", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
                .disabled(managesReports ? selectedReportIDs.isEmpty : selectedDraftIDs.isEmpty)
                .accessibilityIdentifier("profile.deleteSelected")

                if managesReports {
                    Button(role: .destructive) {
                        showsLowScoreDeletion = true
                    } label: {
                        Label("清理中低分", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mediumAndLowScoreReports.isEmpty)
                    .accessibilityIdentifier("profile.deleteLowScoreReports")
                }
            }
            .font(.caption.bold())
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 0.8) }
        .shadow(color: AppTheme.navy.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func collectionFooter(
        count: Int,
        isExpanded: Binding<Bool>,
        destinationTitle: String
    ) -> some View {
        VStack(spacing: 8) {
            if count > 3 {
                Button {
                    withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
                } label: {
                    Label(
                        isExpanded.wrappedValue ? "收起档案" : "展开全部 \(count) 份",
                        systemImage: isExpanded.wrappedValue ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                ReportsView()
            } label: {
                Label(destinationTitle, systemImage: "arrow.left.arrow.right.circle")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.reportArchive")
        }
    }

    private var displayedReports: [AnalysisReport] {
        (reportsExpanded || managesReports) ? appStore.reports : Array(appStore.reports.prefix(3))
    }

    private var mediumAndLowScoreReports: [AnalysisReport] {
        appStore.reports.filter { !$0.isStale && ($0.assessmentScores?.overall ?? 10) < 7 }
    }

    private func moveSelectedReports(to groupID: String?) {
        let reports = appStore.reports.filter { selectedReportIDs.contains($0.id) }
        appStore.moveReports(reports, toGroupID: groupID)
        selectedReportIDs.removeAll()
    }

    private var draftItems: [WorkspaceDraftItem] {
        var items: [WorkspaceDraftItem] = []
        if appStore.hasIncompleteDraft {
            items.append(
                WorkspaceDraftItem(
                    id: currentDraftID,
                    businessDescription: appStore.draft.businessDescription,
                    categorySymbol: appStore.draft.category.symbol,
                    placeName: appStore.selectedLocation?.name ?? "尚未选择点位",
                    updatedAt: nil,
                    isCurrent: true,
                    savedDraft: nil
                )
            )
        }
        items.append(contentsOf: appStore.archivedDrafts.map { draft in
            WorkspaceDraftItem(
                id: draft.id,
                businessDescription: draft.plan.businessDescription,
                categorySymbol: draft.plan.category.symbol,
                placeName: draft.location?.name ?? "尚未选择点位",
                updatedAt: draft.updatedAt,
                isCurrent: false,
                savedDraft: draft
            )
        })
        return Array(items.prefix(10))
    }

    private var displayedDrafts: [WorkspaceDraftItem] {
        (draftsExpanded || managesDrafts) ? draftItems : Array(draftItems.prefix(3))
    }

    private func resume(_ item: WorkspaceDraftItem) {
        if item.isCurrent {
            resumeRoute = .current(location: appStore.selectedLocation)
        } else if let draft = item.savedDraft, appStore.resumeArchivedDraft(draft) {
            resumeRoute = .archived(draft)
        }
    }

    private func toggleReportSelection(_ id: UUID) {
        if selectedReportIDs.contains(id) {
            selectedReportIDs.remove(id)
        } else {
            selectedReportIDs.insert(id)
        }
    }

    private func toggleDraftSelection(_ id: String) {
        if selectedDraftIDs.contains(id) {
            selectedDraftIDs.remove(id)
        } else {
            selectedDraftIDs.insert(id)
        }
    }

    private func deleteSelectedReports() {
        appStore.deleteReports(appStore.reports.filter { selectedReportIDs.contains($0.id) })
        selectedReportIDs.removeAll()
        if appStore.reports.isEmpty { managesReports = false }
    }

    private func deleteSelectedDrafts() {
        if selectedDraftIDs.contains(currentDraftID) {
            appStore.resetDraft()
        }
        appStore.deleteArchivedDrafts(
            appStore.archivedDrafts.filter { selectedDraftIDs.contains($0.id) }
        )
        selectedDraftIDs.removeAll()
        if draftItems.isEmpty { managesDrafts = false }
    }
}

private struct MyCenterSection<Content: View>: View {
    let title: String
    let detail: String
    let content: Content

    init(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            content
        }
    }
}

private struct MyCenterTile: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var badge = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: symbol)
                    .font(.headline.bold())
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 22)
                        .background(AppTheme.red, in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(15)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.border, lineWidth: 0.8)
        }
    }
}

private struct MyCenterRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }
}

private struct MyCenterDivider: View {
    var body: some View {
        Divider()
            .overlay(AppTheme.border)
            .padding(.leading, 64)
    }
}

private struct DecisionMetric: View {
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct MyFavoriteStorefrontsView: View {
    @Environment(StorefrontStore.self) private var store
    @State private var listings: [StorefrontListing] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if isLoading {
                    ProgressView("正在核对收藏铺源")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("收藏暂未完成更新", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("重新加载") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 12)
                } else if listings.isEmpty {
                    ContentUnavailableView {
                        Label("还没有收藏店铺", systemImage: "heart.slash")
                    } description: {
                        Text("在找旺铺中收藏感兴趣的真实铺源，之后可从这里集中比较。")
                    } actions: {
                        NavigationLink("去找旺铺") {
                            StorefrontDiscoveryView()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 12)
                } else {
                    HStack {
                        Text("已收藏 \(listings.count) 家")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("失效铺源会自动从列表隐藏")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    ForEach(listings) { listing in
                        VStack(spacing: 8) {
                            NavigationLink {
                                StorefrontDetailView(listing: listing)
                            } label: {
                                StorefrontListingCard(listing: listing)
                            }
                            .buttonStyle(PressFeedbackStyle())
                            Button {
                                store.toggleFavorite(listing)
                                withAnimation(.snappy) {
                                    listings.removeAll { $0.id == listing.id }
                                }
                            } label: {
                                Label("取消收藏", systemImage: "heart.slash")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.deepClay)
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("收藏店铺")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            listings = try await store.fetchListings(ids: Array(store.favoriteIDs).sorted())
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "无法连接旺铺服务，请检查网络后重试。"
        }
        isLoading = false
    }
}

private enum MyCommunityContentTab: String, CaseIterable, Identifiable {
    case posts
    case comments
    case replies

    var id: String { rawValue }
    var title: String {
        switch self {
        case .posts: "我的发帖"
        case .comments: "历史评论"
        case .replies: "别人回复"
        }
    }
}

private struct MyCommunityContentView: View {
    @Environment(CommunityStore.self) private var store
    @State private var tab: MyCommunityContentTab = .posts
    @State private var posts: [CommunityPost] = []
    @State private var comments: [MyCommunityComment] = []
    @State private var isLoading = true
    @State private var pendingPostDeletion: CommunityPost?
    @State private var pendingCommentDeletion: MyCommunityComment?

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容类型", selection: $tab) {
                ForEach(MyCommunityContentTab.allCases) {
                    Text($0.title).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .tint(CommunityTheme.cobalt)
            .padding(16)
            .accessibilityIdentifier("profile.communityContentPicker")

            Group {
                switch tab {
                case .posts:
                    postContent
                case .comments:
                    commentContent
                case .replies:
                    CommunityNotificationsView(
                        initialKind: "comments",
                        showsKindPicker: false
                    )
                }
            }
        }
        .background(CommunityBackdrop())
        .navigationTitle("我的创业内容")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tab) { await loadSelectedTab() }
        .confirmationDialog(
            "删除这篇发帖？",
            isPresented: Binding(
                get: { pendingPostDeletion != nil },
                set: { if !$0 { pendingPostDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除发帖", role: .destructive) {
                guard let post = pendingPostDeletion else { return }
                Task {
                    if await store.deletePost(post) {
                        posts.removeAll { $0.id == post.id }
                    }
                    pendingPostDeletion = nil
                }
            }
        } message: {
            Text("删除后帖子、图片和相关互动将不再对其他用户可见。")
        }
        .confirmationDialog(
            "删除这条评论？",
            isPresented: Binding(
                get: { pendingCommentDeletion != nil },
                set: { if !$0 { pendingCommentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除评论", role: .destructive) {
                guard let comment = pendingCommentDeletion else { return }
                Task {
                    if await store.deleteMyComment(comment) {
                        comments.removeAll { $0.id == comment.id }
                    }
                    pendingCommentDeletion = nil
                }
            }
        } message: {
            Text("删除后无法恢复，但不会删除原帖。")
        }
    }

    @ViewBuilder
    private var postContent: some View {
        if isLoading {
            ProgressView("正在整理我的发帖")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if posts.isEmpty {
            ContentUnavailableView(
                "还没有发布内容",
                systemImage: "square.and.pencil",
                description: Text("在创业圈发布后，可以在这里统一查看和删除。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(posts) { post in
                        VStack(spacing: 0) {
                            CommunityPostCard(post: post)
                            Button(role: .destructive) {
                                pendingPostDeletion = post
                            } label: {
                                Label("删除这篇发帖", systemImage: "trash")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity, minHeight: 42)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.deepClay)
                            .background(AppTheme.card)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
        }
    }

    @ViewBuilder
    private var commentContent: some View {
        if isLoading {
            ProgressView("正在整理历史评论")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comments.isEmpty {
            ContentUnavailableView(
                "还没有历史评论",
                systemImage: "bubble.left",
                description: Text("你在创业圈留下的评论会按时间保存在这里。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(comments) { comment in
                    NavigationLink {
                        CommunityPostLoaderView(postID: comment.postID)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(comment.content)
                                .font(.body.weight(.medium))
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("原帖：\(comment.postExcerpt)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(2)
                            Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(.vertical, 7)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            pendingCommentDeletion = comment
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func loadSelectedTab() async {
        guard tab != .replies else {
            isLoading = false
            return
        }
        isLoading = true
        if tab == .posts {
            posts = await store.myPosts()
        } else if tab == .comments {
            comments = await store.myComments()
        }
        isLoading = false
    }
}

private struct MyAccountInformationView: View {
    @Environment(CommunityStore.self) private var store
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsPublicProfileEditor = false
    @State private var showsPhoneEditor = false
    @State private var showsIdentityEditor = false
    @State private var showsRemoveAvatar = false
    @State private var successMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                accountHero
                informationSection
                privacyCard
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("个人信息")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.accountProfile == nil {
                await store.refreshAccountProfile()
            }
        }
        .sheet(isPresented: $showsPublicProfileEditor) {
            if let profile = store.profile {
                MyPublicProfileEditor(profile: profile)
            }
        }
        .sheet(isPresented: $showsPhoneEditor) {
            MyPhoneEditor {
                successMessage = "联系电话已更新"
            }
        }
        .sheet(isPresented: $showsIdentityEditor) {
            MyIdentityEditor {
                successMessage = "实名资料已提交，等待权威认证通道核验"
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await updateAvatar(from: item) }
        }
        .confirmationDialog("头像管理", isPresented: $showsRemoveAvatar) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("更换头像")
            }
            if store.profile?.avatarURL != nil {
                Button("移除头像", role: .destructive) {
                    Task {
                        if await store.updateAvatar(jpegData: nil) {
                            successMessage = "头像已移除"
                        }
                    }
                }
            }
        }
        .alert(
            "保存成功",
            isPresented: Binding(
                get: { successMessage != nil },
                set: { if !$0 { successMessage = nil } }
            )
        ) {
            Button("知道了") { successMessage = nil }
        } message: {
            Text(successMessage ?? "")
        }
    }

    private var accountHero: some View {
        VStack(spacing: 14) {
            if let profile = store.profile {
                Button {
                    showsRemoveAvatar = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        CommunityAvatar(profile: profile, size: 88)
                        Image(systemName: "camera.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(AppTheme.deepClay, in: Circle())
                            .overlay { Circle().stroke(AppTheme.card, lineWidth: 3) }
                    }
                }
                .buttonStyle(PressFeedbackStyle())
                .disabled(store.isUpdatingAccount)
                .accessibilityLabel("更换头像")

                VStack(spacing: 4) {
                    Text(profile.nickname)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(profile.role.title)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }

                HStack(spacing: 0) {
                    AccountMetric(value: "\(profile.postCount)", title: "发帖")
                    AccountMetric(value: "\(profile.followerCount)", title: "粉丝")
                    AccountMetric(value: "\(profile.followingCount)", title: "关注")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .appCard(contentPadding: 20)
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资料与认证")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            VStack(spacing: 0) {
                Button { showsPublicProfileEditor = true } label: {
                    MyCenterRow(
                        title: "公开名片",
                        detail: publicProfileDetail,
                        symbol: "person.text.rectangle.fill",
                        tint: CommunityTheme.cobalt
                    )
                }
                MyCenterDivider()
                Button { showsPhoneEditor = true } label: {
                    MyCenterRow(
                        title: "联系电话",
                        detail: phoneDetail,
                        symbol: "phone.fill",
                        tint: AppTheme.mint
                    )
                }
                MyCenterDivider()
                Button { showsIdentityEditor = true } label: {
                    MyCenterRow(
                        title: "实名认证",
                        detail: identityDetail,
                        symbol: store.accountProfile?.identityStatus.symbol
                            ?? "person.badge.shield.checkmark.fill",
                        tint: identityTint
                    )
                }
            }
            .buttonStyle(PressFeedbackStyle())
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppTheme.border, lineWidth: 0.8)
            }
        }
    }

    private var privacyCard: some View {
        Label(
            "联系电话和实名资料仅用于账号安全与必要的交易信任，不会显示在公开社区名片中。当前实名资料只完成格式校验，权威核验完成前不会展示“已实名”。",
            systemImage: "lock.shield.fill"
        )
        .font(.caption)
        .foregroundStyle(AppTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(15)
        .background(AppTheme.periwinkle.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
    }

    private var publicProfileDetail: String {
        guard let profile = store.profile else { return "未设置" }
        return profile.bio.isEmpty ? "补充行业、经验或关注方向" : profile.bio
    }

    private var phoneDetail: String {
        guard let account = store.accountProfile else { return "加载中" }
        return account.phoneMasked.map {
            "\($0) · \(account.phoneStatus.title)"
        } ?? "未填写 · 仅自己可见"
    }

    private var identityDetail: String {
        guard let account = store.accountProfile else { return "加载中" }
        if let name = account.identityNameMasked,
           let suffix = account.identityNumberLastFour {
            return "\(name) · 证件尾号 \(suffix) · \(account.identityStatus.title)"
        }
        return account.identityStatus.title
    }

    private var identityTint: Color {
        switch store.accountProfile?.identityStatus {
        case .verified: AppTheme.mint
        case .pendingAuthoritativeVerification: AppTheme.amber
        case .rejected: AppTheme.red
        default: AppTheme.periwinkle
        }
    }

    private func updateAvatar(from item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard
            let sourceData = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: sourceData),
            let jpegData = image.squareAvatarJPEG()
        else {
            store.notice = CommunityNotice(
                title: "无法读取这张图片",
                detail: "请选择清晰的 JPEG、PNG 或 WebP 图片后重试。"
            )
            return
        }
        if await store.updateAvatar(jpegData: jpegData) {
            successMessage = "头像已更新"
        }
    }
}

private struct AccountMetric: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(AppTheme.ink)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MyPublicProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityStore.self) private var store
    @State private var nickname: String
    @State private var role: CommunityIdentityRole
    @State private var bio: String

    init(profile: CommunityProfile) {
        _nickname = State(initialValue: profile.nickname)
        _role = State(initialValue: profile.role)
        _bio = State(initialValue: profile.bio)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("社区昵称") {
                    TextField("2–24 个字", text: $nickname)
                    Text("\(nickname.count)/24")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Section("主要身份") {
                    Picker("身份", selection: $role) {
                        ForEach(CommunityIdentityRole.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Section("个人介绍") {
                    TextField("你的行业、经验或关注方向", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                    Text("\(bio.count)/240")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackdrop(accent: AppTheme.amber))
            .navigationTitle("编辑公开名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isUpdatingAccount ? "保存中" : "保存") {
                        Task {
                            if await store.updateMyProfile(
                                nickname: nickname,
                                role: role,
                                bio: bio
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        !(2...24).contains(
                            nickname.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).count
                        ) || bio.count > 240 || store.isUpdatingAccount
                    )
                }
            }
        }
    }
}

private struct MyPhoneEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityStore.self) private var store
    @State private var phone = ""
    @State private var showsRemoval = false
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("中国内地手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .privacySensitive()
                } header: {
                    Text("联系电话")
                } footer: {
                    Text("只保存脱敏号码。本次填写不会被当作短信实名核验，也不会公开给其他用户。")
                }
                if store.accountProfile?.phoneMasked != nil {
                    Section {
                        Button("移除联系电话", role: .destructive) {
                            showsRemoval = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackdrop(accent: AppTheme.mint))
            .navigationTitle("联系电话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isUpdatingAccount ? "保存中" : "保存") {
                        Task {
                            if await store.updateContactPhone(phone) {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValidPhone || store.isUpdatingAccount)
                }
            }
            .confirmationDialog("移除联系电话？", isPresented: $showsRemoval) {
                Button("移除", role: .destructive) {
                    Task {
                        if await store.clearContactPhone() {
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var isValidPhone: Bool {
        let value = phone.replacingOccurrences(
            of: #"[+\s-]"#,
            with: "",
            options: .regularExpression
        )
        return value.range(
            of: #"^(?:86)?1[3-9]\d{9}$"#,
            options: .regularExpression
        ) != nil
    }
}

private struct MyIdentityEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityStore.self) private var store
    @State private var realName = ""
    @State private var identityNumber = ""
    @State private var acknowledgesBoundary = false
    @State private var showsRemoval = false
    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let account = store.accountProfile,
                   account.identityStatus != .notSubmitted {
                    Section("当前状态") {
                        Label(
                            account.identityStatus.title,
                            systemImage: account.identityStatus.symbol
                        )
                        Text(account.verificationNote)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                Section {
                    TextField("真实姓名", text: $realName)
                        .textContentType(.name)
                        .privacySensitive()
                    TextField("18 位身份证号码", text: $identityNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .privacySensitive()
                } header: {
                    Text("实名资料")
                } footer: {
                    Text("服务端只保存姓名掩码、证件尾号和核验状态；原始姓名与证件号不会落库。")
                }
                Section {
                    Toggle(
                        "我了解：当前仅校验证件格式，权威认证完成前不会显示“已实名”",
                        isOn: $acknowledgesBoundary
                    )
                    .font(.subheadline)
                }
                if store.accountProfile?.identityStatus != .notSubmitted {
                    Section {
                        Button("撤回已提交资料", role: .destructive) {
                            showsRemoval = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackdrop(accent: AppTheme.amber))
            .navigationTitle("实名认证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isUpdatingAccount ? "提交中" : "提交核验") {
                        Task {
                            if await store.submitIdentity(
                                realName: realName,
                                identityNumber: identityNumber.uppercased()
                            ) {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        realName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).count < 2 ||
                        identityNumber.count != 18 ||
                        !acknowledgesBoundary ||
                        store.isUpdatingAccount
                    )
                }
            }
            .confirmationDialog("撤回实名资料？", isPresented: $showsRemoval) {
                Button("撤回", role: .destructive) {
                    Task {
                        if await store.clearIdentity() {
                            onSaved()
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("撤回后会删除姓名掩码、证件尾号和当前核验状态。")
            }
        }
    }
}

private extension UIImage {
    func squareAvatarJPEG() -> Data? {
        let side = min(size.width, size.height)
        guard side > 0 else { return nil }
        let cropOrigin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let outputSize = CGSize(width: 640, height: 640)
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let rendered = renderer.image { _ in
            draw(
                in: CGRect(
                    x: -cropOrigin.x * outputSize.width / side,
                    y: -cropOrigin.y * outputSize.height / side,
                    width: size.width * outputSize.width / side,
                    height: size.height * outputSize.height / side
                )
            )
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

private struct FortuneCoinCenterView: View {
    @Environment(CommunityStore.self) private var communityStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("easybusiness.selectedRootTab") private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let wallet = communityStore.fortuneWallet {
                    balanceHero(wallet)
                    usageSection
                    dailySection(wallet)
                    taskSection(wallet)
                    transactionSection
                    rulesSection
                } else {
                    InlineStatusCard(
                        title: "先激活财神币账户",
                        detail: "在创业圈设置昵称后，可领取 10 枚新手赠币。账户只记录余额与任务，不记录你的提示词、经营参数或模型回复。",
                        tint: AppTheme.amber,
                        symbol: "gift.fill"
                    )
                    Button {
                        dismiss()
                        selectedTab = 3
                    } label: {
                        PrimaryActionLabel(title: "去激活并领取", systemImage: "arrow.right")
                    }
                    .buttonStyle(PressFeedbackStyle())
                }
            }
            .padding(20)
            .padding(.bottom, 104)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("财神币")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await communityStore.refreshFortuneWallet()
            await communityStore.loadFortuneTransactions()
        }
        .refreshable {
            await communityStore.refreshFortuneWallet()
            await communityStore.loadFortuneTransactions()
        }
        .alert(item: noticeBinding) { notice in
            Alert(
                title: Text(notice.title),
                message: notice.detail.map(Text.init),
                dismissButton: .default(Text("知道了")) {
                    communityStore.notice = nil
                }
            )
        }
    }

    private func balanceHero(_ wallet: FortuneWallet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前余额")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(wallet.balance)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("枚")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(AppTheme.amber, .white.opacity(0.26))
            }

            HStack(spacing: 0) {
                FortuneMetric(title: "累计获得", value: "\(wallet.lifetimeEarned)")
                Divider().overlay(.white.opacity(0.22)).frame(height: 28)
                FortuneMetric(title: "累计使用", value: "\(wallet.lifetimeSpent)")
                Divider().overlay(.white.opacity(0.22)).frame(height: 28)
                FortuneMetric(title: "连续签到", value: "\(wallet.checkInStreak) 天")
            }

            Button {
                Task { await communityStore.checkInFortuneWallet() }
            } label: {
                Label(
                    wallet.checkedInToday ? "今天已签到" : "今日签到 · 领取 3 枚",
                    systemImage: wallet.checkedInToday ? "checkmark.circle.fill" : "calendar.badge.plus"
                )
                .font(.subheadline.bold())
                .foregroundStyle(wallet.checkedInToday ? .white.opacity(0.76) : AppTheme.deepClay)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    wallet.checkedInToday ? .white.opacity(0.13) : .white,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            }
            .buttonStyle(PressFeedbackStyle())
            .disabled(wallet.checkedInToday || communityStore.isCheckingIn)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.deepClay, AppTheme.amber],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: AppTheme.deepClay.opacity(0.16), radius: 22, y: 10)
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("怎么使用", caption: "启动前预扣，失败自动退回")
            HStack(spacing: 10) {
                FortuneUsageTile(
                    symbol: "bubble.left.and.bubble.right.fill",
                    title: "问小易",
                    detail: "选址、经营或群聊",
                    cost: 1,
                    tint: AppTheme.blue
                )
                FortuneUsageTile(
                    symbol: "sparkles",
                    title: "深度能力",
                    detail: "选址研判或区域找铺",
                    cost: 3,
                    tint: AppTheme.deepClay
                )
            }
        }
    }

    private func dailySection(_ wallet: FortuneWallet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("今天还能赚")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("日常任务每天最多 \(wallet.dailyEarnCap) 枚；一次性成就不占上限。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text("\(wallet.dailyEarned)/\(wallet.dailyEarnCap)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(AppTheme.deepClay)
            }
            ProgressView(
                value: Double(wallet.dailyEarned),
                total: Double(max(1, wallet.dailyEarnCap))
            )
            .tint(AppTheme.amber)
        }
        .appCard(contentPadding: 16)
    }

    private func taskSection(_ wallet: FortuneWallet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("赚币任务", caption: "真实完成后自动到账")
            ForEach(wallet.tasks) { task in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill((task.completed ? AppTheme.mint : AppTheme.amber).opacity(0.12))
                        Image(systemName: task.completed ? "checkmark" : "flag.fill")
                            .font(.caption.bold())
                            .foregroundStyle(task.completed ? AppTheme.mint : AppTheme.amber)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(task.detail)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(2)
                        if task.target > 1, !task.completed {
                            ProgressView(
                                value: Double(task.progress),
                                total: Double(task.target)
                            )
                            .tint(AppTheme.amber)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(task.completed ? "已完成" : "+\(task.reward)")
                        .font(.caption.bold())
                        .foregroundStyle(task.completed ? AppTheme.mint : AppTheme.deepClay)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            (task.completed ? AppTheme.mint : AppTheme.amber).opacity(0.10),
                            in: Capsule()
                        )
                }
                .padding(13)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 0.8)
                }
            }
        }
    }

    @ViewBuilder
    private var transactionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("最近明细")
            if communityStore.fortuneTransactions.isEmpty {
                Text("完成签到、任务或使用小易后，明细会出现在这里。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .appCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(communityStore.fortuneTransactions.prefix(12).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: transactionSymbol(item))
                                .foregroundStyle(item.delta >= 0 ? AppTheme.mint : AppTheme.deepClay)
                                .frame(width: 30, height: 30)
                                .background(
                                    (item.delta >= 0 ? AppTheme.mint : AppTheme.deepClay).opacity(0.10),
                                    in: Circle()
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Text("\(item.delta > 0 ? "+" : "")\(item.delta)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(item.delta >= 0 ? AppTheme.mint : AppTheme.deepClay)
                        }
                        .padding(.vertical, 12)
                        if index < min(communityStore.fortuneTransactions.count, 12) - 1 {
                            Divider()
                        }
                    }
                }
                .appCard(contentPadding: 15)
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("透明规则", systemImage: "shield.checkered")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
            Text("财神币目前只来自系统赠送和真实任务，不支持充值、转赠或提现。连续签到第 3、7、14、30 天会额外奖励。模型任务启动前预扣；服务失败或任务取消会原路退回，不会用假结果换取消耗。")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard(contentPadding: 15)
    }

    private func transactionSymbol(_ item: FortuneTransaction) -> String {
        switch item.kind {
        case "usage": "sparkles"
        case "refund": "arrow.uturn.backward.circle.fill"
        case "check_in": "calendar.badge.checkmark"
        case "welcome": "gift.fill"
        default: "circle.hexagongrid.fill"
        }
    }

    private var noticeBinding: Binding<CommunityNotice?> {
        Binding(
            get: { communityStore.notice },
            set: { communityStore.notice = $0 }
        )
    }
}

private struct FortuneMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FortuneUsageTile: View {
    let symbol: String
    let title: String
    let detail: String
    let cost: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Spacer()
                Text("\(cost) 币/次")
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.10), in: Capsule())
            }
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(contentPadding: 14)
    }
}

private struct WorkspaceSectionHeader: View {
    let title: String
    let detail: String
    let managesItems: Bool
    let canManage: Bool
    let manageIdentifier: String
    let onManage: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            if canManage {
                Button(managesItems ? "完成" : "管理", action: onManage)
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .tint(AppTheme.blue)
                    .accessibilityIdentifier(manageIdentifier)
            }
        }
    }
}

private struct WorkspaceDraftItem: Identifiable {
    let id: String
    let businessDescription: String
    let categorySymbol: String
    let placeName: String
    let updatedAt: Date?
    let isCurrent: Bool
    let savedDraft: SavedOpeningDraft?
}

private struct DraftWorkspaceRow: View {
    let item: WorkspaceDraftItem

    var body: some View {
        HStack(spacing: 13) {
            FeatureIcon(symbol: item.categorySymbol, tint: AppTheme.blue)
            VStack(alignment: .leading, spacing: 6) {
                Label(item.businessDescription, systemImage: item.categorySymbol)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.blue)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.blue.opacity(0.10), in: Capsule())
                Text(item.placeName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(item.isCurrent ? "当前填写中" : "保存于 \(item.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "本机")")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 14)
    }
}

struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? AppTheme.blue : AppTheme.muted)
            .accessibilityLabel(isSelected ? "已选择" : "未选择")
    }

}

private enum DraftResumeRoute: Identifiable, Hashable {
    case current(location: LocationCandidate?)
    case archived(SavedOpeningDraft)

    var id: String {
        switch self {
        case let .current(location): "current-\(location?.id ?? "business")"
        case let .archived(draft): "archived-\(draft.id)"
        }
    }

    var location: LocationCandidate? {
        switch self {
        case let .current(location): location
        case let .archived(draft): draft.location
        }
    }

    static func == (lhs: DraftResumeRoute, rhs: DraftResumeRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct DecisionHubRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            FeatureIcon(symbol: symbol, tint: AppTheme.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                Text(detail).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
        }
        .appCard()
    }
}
