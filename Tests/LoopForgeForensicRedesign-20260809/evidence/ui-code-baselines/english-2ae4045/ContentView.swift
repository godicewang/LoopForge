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
    @AppStorage("easybusiness.us.selectedRootTab") private var selectedTab = 0
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
            .tabItem { RootTabLabel(title: "Home", symbol: RootTabVisual.evaluation) }
            .tag(0)

            NavigationStack {
                StorefrontDiscoveryView()
            }
            .tabItem { RootTabLabel(title: "Storefronts", symbol: RootTabVisual.storefront) }
            .tag(2)

            NavigationStack {
                CommunityRootView()
            }
            .tabItem { RootTabLabel(title: "Community", symbol: RootTabVisual.community) }
            .tag(3)

            NavigationStack {
                FriendsRootView()
            }
            .tabItem { RootTabLabel(title: "Friends", symbol: RootTabVisual.friends) }
            .tag(5)

            NavigationStack {
                MyWorkspaceView()
            }
            .tabItem { RootTabLabel(title: "Me", symbol: RootTabVisual.profile) }
            .tag(4)
        }
        .tint(selectedTab == 3 ? CommunityTheme.cobalt : AppTheme.blue)
        // Do not let a tab's intrinsic scroll content size the root container.
        // A root-level canvas also prevents black gaps during scene restoration.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackdrop())
        .environment(
            \.dynamicTypeSize,
            accessibilityAuditSize ?? systemDynamicTypeSize
        )
        .preferredColorScheme(accessibilityAuditSize == nil ? nil : .dark)
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
            "How would you like to handle this assessment before leaving?",
            isPresented: $showsDraftExitPrompt,
            titleVisibility: .visible
        ) {
            Button("Save Draft and Go") {
                appStore.persistDraft()
                switchToPendingTab()
            }
            Button("Discard and Go", role: .destructive) {
                appStore.resetDraft()
                switchToPendingTab()
            }
            Button("Continue Editing") { pendingTab = nil }
        } message: {
            Text("Save to continue later in Me, or discard this category, site, and operating setup. Completed reports stay.")
        }
        .alert("Generating Report", isPresented: $showsGenerationTabBlocker) {
            Button("Keep Waiting", role: .cancel) {}
        } message: {
            Text("Finish or cancel the report before switching tabs.")
        }
        .alert(item: communityNoticeBinding) { notice in
            Alert(
                title: Text(notice.title),
                message: notice.detail.map(Text.init),
                dismissButton: .default(Text("Got it")) {
                    communityStore.notice = nil
                }
            )
        }
        .confirmationDialog(
            "Set up business reminders first?",
            isPresented: $showsOperationsReminderPrompt,
            titleVisibility: .visible
        ) {
            Button("Set Up and Go") {
                operationsStore.acknowledgeFirstReminderPrompt()
                showsOperationsReminderSetup = true
            }
            Button("Skip and Go") {
                operationsStore.acknowledgeFirstReminderPrompt()
                finishOperationsExit()
            }
            Button("Stay in Operations Advisor", role: .cancel) { pendingTab = nil }
        } message: {
            Text("Set daily, weekly, or monthly reminders. You can change them later in Business Settings.")
        }
        .sheet(isPresented: $showsOperationsReminderSetup, onDismiss: finishOperationsExit) {
            NavigationStack {
                OperatingReminderView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showsOperationsReminderSetup = false }
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
                await communityStore.refreshCreditWallet()
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

    private var accessibilityAuditSize: DynamicTypeSize? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-easybusiness-accessibility-maximum") {
            return .accessibility5
        }
        if ProcessInfo.processInfo.arguments.contains("-easybusiness-accessibility-audit") {
            return .accessibility3
        }
        return nil
        #else
        return nil
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
    @AppStorage("easybusiness.us.selectedRootTab") private var selectedTab = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                identityHero
                creditStrip
                decisionWorkspaceCard

                MyCenterSection(title: "Content & Stores", detail: "Listings and community activity") {
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
                                title: "Saved Listings",
                                detail: storefrontStore.favoriteIDs.isEmpty
                                    ? "No saved listings" : "\(storefrontStore.favoriteIDs.count) listings to compare",
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
                                title: "My Posts",
                                detail: communityStore.profile.map {
                                    "\($0.postCount) posts · Manage comments"
                                } ?? "Join to start posting",
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
                                title: "Replies",
                                detail: communityStore.unreadCount > 0
                                    ? "\(communityStore.unreadCount) unread" : "Comments, likes, and follows",
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
                                title: "My Listings",
                                detail: "View or remove listings",
                                symbol: "storefront.fill",
                                tint: AppTheme.mint
                            )
                        }
                        .accessibilityIdentifier("profile.myStorefronts")
                    }
                    .buttonStyle(PressFeedbackStyle())
                }

                MyCenterSection(title: "Services", detail: "Stores, messages, and privacy") {
                    VStack(spacing: 0) {
                        NavigationLink {
                            OperationsHomeView()
                        } label: {
                            MyCenterRow(
                                title: "Manage Stores",
                                detail: operationsStore.workspace.profiles.isEmpty
                                    ? "Add a store and log results"
                                    : "\(operationsStore.workspace.profiles.count) stores · Pulse and reviews",
                                symbol: "chart.line.uptrend.xyaxis",
                                tint: AppTheme.mint
                            )
                        }
                        MyCenterDivider()
                        NavigationLink {
                            FriendsRootView()
                        } label: {
                            MyCenterRow(
                                title: "Friends & Groups",
                                detail: "Messages, groups, and advisors",
                                symbol: "person.2.fill",
                                tint: CommunityTheme.cobalt
                            )
                        }
                        MyCenterDivider()
                        NavigationLink {
                            ProfileView()
                        } label: {
                            MyCenterRow(
                                title: "Data & Privacy",
                                detail: "Device data and service status",
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
        .navigationTitle("Me")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            communityStore.configurePersistence(modelContext)
            if communityStore.serviceState == .checking {
                await communityStore.bootstrap()
            } else if communityStore.serviceState == .ready {
                await communityStore.refreshCreditWallet()
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
                            Text(profile.nickname)
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                            Text(profile.role.title)
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.deepClay)
                            Text("View Personal Information")
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
                            title: "Following"
                        )
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(profile.followingCount)")
                                .font(.headline.bold().monospacedDigit())
                            Text("Following")
                                .font(.caption2)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 42, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Following \(profile.followingCount) people")

                    NavigationLink {
                        CommunityConnectionsView(
                            userID: profile.id,
                            kind: "followers",
                            title: "Followers"
                        )
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(profile.followerCount)")
                                .font(.headline.bold().monospacedDigit())
                            Text("Followers")
                                .font(.caption2)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .frame(minWidth: 42, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(profile.followerCount) followers")
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
                        Text("Create Founder Profile")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("Set a nickname to manage your profile and credits.")
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
    private var creditStrip: some View {
        if let wallet = communityStore.creditWallet {
            HStack(spacing: 10) {
                NavigationLink {
                    CreditCoinCenterView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(wallet.balance) Easy Credits")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text(
                                wallet.checkedInToday
                                    ? "Earned \(wallet.dailyEarned)/\(wallet.dailyEarnCap) today"
                                    : "Check-in +3 · \(wallet.checkInStreak)-day streak"
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        }
                        Spacer()
                        if wallet.checkedInToday {
                            Label("Checked In", systemImage: "checkmark.circle.fill")
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
                .accessibilityIdentifier("profile.creditCenter")

                if !wallet.checkedInToday {
                    Button {
                        Task { await communityStore.checkInCreditWallet() }
                    } label: {
                        Text("Check-in +3")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(AppTheme.deepClay, in: Capsule())
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .accessibilityIdentifier("profile.creditCheckIn")
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
                        Text("Site Dashboard")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Reports, candidate sites, and drafts")
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
                    DecisionMetric(value: "\(appStore.reports.count)", title: "Reports")
                    DecisionMetric(value: "\(unfinishedDecisionCount)", title: "Drafts")
                    DecisionMetric(
                        value: latestDecisionScore,
                        title: "Latest"
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
        if report.isStale { return "Pending review" }
        guard let score = report.assessmentScores?.overall else { return "Completed" }
        return String(format: "%.1f", score)
    }

    private var accountCompletionText: String {
        var completed = 1 // nickname
        if communityStore.profile?.avatarURL != nil { completed += 1 }
        if communityStore.profile?.bio.isEmpty == false { completed += 1 }
        return completed == 3 ? "Profile Complete" : "Profile \(completed)/3 · Tap to complete"
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
        .navigationTitle("Site Dashboard")
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
        .confirmationDialog("Delete selected assessment reports?", isPresented: $showsSelectedReportDeletion) {
            Button("Delete \(selectedReportIDs.count) reports", role: .destructive) {
                deleteSelectedReports()
            }
        } message: {
            Text("Also deletes local verification progress. This cannot be undone.")
        }
        .confirmationDialog("Delete lower-scoring reports?", isPresented: $showsLowScoreDeletion) {
            Button("Delete \(mediumAndLowScoreReports.count) reports", role: .destructive) {
                appStore.deleteReports(mediumAndLowScoreReports)
                selectedReportIDs.subtract(mediumAndLowScoreReports.map(\.id))
                if appStore.reports.isEmpty { managesReports = false }
            }
        } message: {
            Text("Deletes reports scored below 7. Higher scores and drafts remain.")
        }
        .confirmationDialog("Delete selected assessment drafts?", isPresented: $showsSelectedDraftDeletion) {
            Button("Delete \(selectedDraftIDs.count) drafts", role: .destructive) {
                deleteSelectedDrafts()
            }
        } message: {
            Text("Deletes local drafts only. Completed reports remain.")
        }
    }

    private var reportArchiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeader(
                title: "Assessment Reports",
                detail: appStore.reports.isEmpty ? "Completed reports appear here" : "Latest 3 · \(appStore.reports.count) total",
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
                        title: "No Reports Yet",
                        detail: "Complete an assessment to review, compare, or add field evidence.",
                        tint: AppTheme.periwinkle,
                        symbol: "doc.text.magnifyingglass"
                    )
                    if draftItems.isEmpty {
                        Button {
                            if appStore.startNewEvaluation() {
                                resumeRoute = .current(location: nil)
                            }
                        } label: {
                            PrimaryActionLabel(title: "Start Assessment", systemImage: "plus")
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
                        destinationTitle: "View full profiles and compare candidate sites"
                    )
                }
            }
        }
    }

    private var unfinishedDraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeader(
                title: "Assessment Drafts",
                detail: draftItems.isEmpty ? "No saved drafts" : "Latest 3 · Up to 10 saved",
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
                Text("Save an assessment draft to continue it here.")
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
                            draftsExpanded ? "Collapse drafts" : "Expand all \(draftItems.count)",
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
                    Text(managesReports ? "File Management" : "Draft Management")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("profile.managementDock")
                    Text(
                        managesReports
                            ? "\(selectedReportIDs.count) selected"
                            : "\(selectedDraftIDs.count) selected"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button("Done") {
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
                        Button("Move to Ungrouped") { moveSelectedReports(to: nil) }
                        ForEach(appStore.reportGroups) { group in
                            Button(group.name) { moveSelectedReports(to: group.id) }
                        }
                    } label: {
                        Label("Move", systemImage: "folder")
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
                    Label("Delete Selected", systemImage: "trash")
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
                        Label("Remove Scores Below 7", systemImage: "line.3.horizontal.decrease.circle")
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
                        isExpanded.wrappedValue ? "Collapse Files" : "Expand all \(count)",
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
                    placeName: appStore.selectedLocation?.name ?? "No site selected",
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
                placeName: draft.location?.name ?? "No site selected",
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
            SectionTitle(title, caption: detail)
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
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
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
                    ProgressView("Checking saved listings")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Saved Listings Unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Reload") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 12)
                } else if listings.isEmpty {
                    ContentUnavailableView {
                        Label("No saved stores yet", systemImage: "heart.slash")
                    } description: {
                        Text("Save interesting real listings from Store Finder to compare them here.")
                    } actions: {
                        NavigationLink("Go to Store Finder") {
                            StorefrontDiscoveryView()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 12)
                } else {
                    HStack {
                        Text("\(listings.count) saved")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("Expired listings are automatically hidden")
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
                                Label("Unsave", systemImage: "heart.slash")
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
        .navigationTitle("Saved Listings")
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
                ?? "Cannot connect to Store Finder service. Check your network and try again."
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
        case .posts: "My Posts"
        case .comments: "Comment History"
        case .replies: "Replies to You"
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
            Picker("Content Type", selection: $tab) {
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
        .navigationTitle("My Community Content")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: tab) { await loadSelectedTab() }
        .confirmationDialog(
            "Delete this post?",
            isPresented: Binding(
                get: { pendingPostDeletion != nil },
                set: { if !$0 { pendingPostDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Post", role: .destructive) {
                guard let post = pendingPostDeletion else { return }
                Task {
                    if await store.deletePost(post) {
                        posts.removeAll { $0.id == post.id }
                    }
                    pendingPostDeletion = nil
                }
            }
        } message: {
            Text("The post, images, and interactions will no longer be visible.")
        }
        .confirmationDialog(
            "Delete this comment?",
            isPresented: Binding(
                get: { pendingCommentDeletion != nil },
                set: { if !$0 { pendingCommentDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Comment", role: .destructive) {
                guard let comment = pendingCommentDeletion else { return }
                Task {
                    if await store.deleteMyComment(comment) {
                        comments.removeAll { $0.id == comment.id }
                    }
                    pendingCommentDeletion = nil
                }
            }
        } message: {
            Text("This action cannot be undone, but the original post will remain.")
        }
    }

    @ViewBuilder
    private var postContent: some View {
        if isLoading {
            ProgressView("Organizing my posts")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if posts.isEmpty {
            ContentUnavailableView(
                "No content posted yet",
                systemImage: "square.and.pencil",
                description: Text("Posts published in Founder Community can be viewed and deleted here.")
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
                                Label("Delete this post", systemImage: "trash")
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
            ProgressView("Organizing comment history")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comments.isEmpty {
            ContentUnavailableView(
                "No comment history yet",
                systemImage: "bubble.left",
                description: Text("Comments you leave in Founder Community are saved here chronologically.")
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
                            Text("Original post: \(comment.postExcerpt)")
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
                        Button("Delete", role: .destructive) {
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
        .navigationTitle("Personal Information")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPublicProfileEditor) {
            if let profile = store.profile {
                MyPublicProfileEditor(profile: profile)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await updateAvatar(from: item) }
        }
        .confirmationDialog("Profile Photo", isPresented: $showsRemoveAvatar) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Change Photo")
            }
            if store.profile?.avatarURL != nil {
                Button("Remove Photo", role: .destructive) {
                    Task {
                        if await store.updateAvatar(jpegData: nil) {
                            successMessage = "Photo removed"
                        }
                    }
                }
            }
        }
        .alert(
            "Saved",
            isPresented: Binding(
                get: { successMessage != nil },
                set: { if !$0 { successMessage = nil } }
            )
        ) {
            Button("Got it") { successMessage = nil }
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
                .accessibilityLabel("Change Photo")

                VStack(spacing: 4) {
                    Text(profile.nickname)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(profile.role.title)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }

                HStack(spacing: 0) {
                    AccountMetric(value: "\(profile.postCount)", title: "Post")
                    AccountMetric(value: "\(profile.followerCount)", title: "Followers")
                    AccountMetric(value: "\(profile.followingCount)", title: "Following")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .appCard(contentPadding: 20)
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            VStack(spacing: 0) {
                Button { showsPublicProfileEditor = true } label: {
                    MyCenterRow(
                        title: "Public Profile",
                        detail: publicProfileDetail,
                        symbol: "person.text.rectangle.fill",
                        tint: CommunityTheme.cobalt
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
            "Your community access credential is stored in this device's Keychain. EasyBusiness does not collect a phone number or government ID for profile verification. Cross-device account recovery is not available yet; deleting the account permanently removes its community data.",
            systemImage: "lock.shield.fill"
        )
        .font(.caption)
        .foregroundStyle(AppTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(15)
        .background(AppTheme.periwinkle.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
    }

    private var publicProfileDetail: String {
        guard let profile = store.profile else { return "Not set" }
        return profile.bio.isEmpty ? "Add industry, experience, or areas of interest" : profile.bio
    }

    private func updateAvatar(from item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard
            let sourceData = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: sourceData),
            let jpegData = image.squareAvatarJPEG()
        else {
            store.notice = CommunityNotice(
                title: "Unable to read this image",
                detail: "Please select a clear JPEG, PNG, or WebP image and try again."
            )
            return
        }
        if await store.updateAvatar(jpegData: jpegData) {
            successMessage = "Photo updated"
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
                Section("Community Nickname") {
                    TextField("2–24 characters", text: $nickname)
                    Text("\(nickname.count)/24")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Section("Primary Identity") {
                    Picker("Identity", selection: $role) {
                        ForEach(CommunityIdentityRole.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                }
                Section("Bio") {
                    TextField("Your industry, experience, or areas of interest", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                    Text("\(bio.count)/240")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackdrop(accent: AppTheme.amber))
            .navigationTitle("Edit Public Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isUpdatingAccount ? "Saving" : "Save") {
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

private struct CreditCoinCenterView: View {
    @Environment(CommunityStore.self) private var communityStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("easybusiness.us.selectedRootTab") private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let wallet = communityStore.creditWallet {
                    balanceHero(wallet)
                    usageSection
                    dailySection(wallet)
                    taskSection(wallet)
                    transactionSection
                    rulesSection
                } else {
                    InlineStatusCard(
                        title: "Activate Easy Credits account first",
                        detail: "Set a nickname in the Founder Community to claim 10 beginner bonus credits. The account only records your balance and tasks; it does not store your prompts, business parameters, or model responses.",
                        tint: AppTheme.amber,
                        symbol: "gift.fill"
                    )
                    Button {
                        dismiss()
                        selectedTab = 3
                    } label: {
                        PrimaryActionLabel(title: "Activate & Claim", systemImage: "arrow.right")
                    }
                    .buttonStyle(PressFeedbackStyle())
                }
            }
            .padding(20)
            .padding(.bottom, 104)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Easy Credits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await communityStore.refreshCreditWallet()
            await communityStore.loadCreditTransactions()
        }
        .refreshable {
            await communityStore.refreshCreditWallet()
            await communityStore.loadCreditTransactions()
        }
        .alert(item: noticeBinding) { notice in
            Alert(
                title: Text(notice.title),
                message: notice.detail.map(Text.init),
                dismissButton: .default(Text("Got it")) {
                    communityStore.notice = nil
                }
            )
        }
    }

    private func balanceHero(_ wallet: CreditWallet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Balance")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(wallet.balance)")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("credits")
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
                CreditMetric(title: "Total Earned", value: "\(wallet.lifetimeEarned)")
                Divider().overlay(.white.opacity(0.22)).frame(height: 28)
                CreditMetric(title: "Total Spent", value: "\(wallet.lifetimeSpent)")
                Divider().overlay(.white.opacity(0.22)).frame(height: 28)
                CreditMetric(title: "Consecutive Check-ins", value: "\(wallet.checkInStreak) days")
            }

            Button {
                Task { await communityStore.checkInCreditWallet() }
            } label: {
                Label(
                    wallet.checkedInToday ? "Checked in today" : "Daily Check-in · Claim 3 credits",
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
            SectionTitle("How to Use", caption: "Pre-deducted before launch; automatically refunded on failure")
            HStack(spacing: 10) {
                CreditUsageTile(
                    symbol: "bubble.left.and.bubble.right.fill",
                    title: "Ask Site Advisor",
                    detail: "Site selection, operations, or group chat",
                    cost: 1,
                    tint: AppTheme.blue
                )
                CreditUsageTile(
                    symbol: "sparkles",
                    title: "Advanced Capabilities",
                    detail: "Site evaluation or area-based store search",
                    cost: 3,
                    tint: AppTheme.deepClay
                )
            }
        }
    }

    private func dailySection(_ wallet: CreditWallet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Earnable Today")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("Daily tasks earn up to \(wallet.dailyEarnCap) credits. One-time rewards are separate.")
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

    private func taskSection(_ wallet: CreditWallet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Coin-Earning Tasks", caption: "Automatically credited upon completion")
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
                    Text(task.completed ? "Completed" : "+\(task.reward)")
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
            SectionTitle("Recent Activity")
            if communityStore.creditTransactions.isEmpty {
                Text("Details from check-ins, tasks, or using Site Advisor will appear here.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .appCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(communityStore.creditTransactions.prefix(12).enumerated()), id: \.element.id) { index, item in
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
                        if index < min(communityStore.creditTransactions.count, 12) - 1 {
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
            Label("Transparent Rules", systemImage: "shield.checkered")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
            ForEach(
                [
                    "Earn credits from app rewards and completed tasks. Purchases, transfers, and withdrawals are not available.",
                    "Check-in bonuses increase on days 3, 7, 14, and 30 of a streak.",
                    "Task fees are reserved up front and refunded if the task fails or is canceled. Failed tasks never receive substitute results.",
                ],
                id: \.self
            ) { rule in
                Label(rule, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard(contentPadding: 15)
    }

    private func transactionSymbol(_ item: CreditTransaction) -> String {
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

private struct CreditMetric: View {
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

private struct CreditUsageTile: View {
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
                Text("\(cost) credits/use")
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
                Button(managesItems ? "Done" : "Manage", action: onManage)
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
                Text(
                    item.isCurrent
                        ? "Currently editing"
                        : "Saved \((item.updatedAt ?? .now).formatted(date: .abbreviated, time: .shortened)) on this device"
                )
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
            .accessibilityLabel(isSelected ? "Selected" : "Not Selected")
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
