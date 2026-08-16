import SwiftUI
import SafariServices
import UIKit

struct AdvisorHomeView: View {
    @AppStorage("easybusiness.us.advisorLine") private var selectedLine = "site"
    private let initialLine: String?

    init(initialLine: String? = nil) {
        self.initialLine = initialLine
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Advisor Type", selection: $selectedLine) {
                Text("Site Advisor").tag("site")
                Text("Operations Advisor").tag("operations")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(AppTheme.canvas)
            .accessibilityIdentifier("advisor.linePicker")

            if selectedLine == "operations" {
                OperatingAdvisorHomeView()
            } else {
                SiteAdvisorHomeView()
            }
        }
        .navigationTitle("Advisor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let initialLine, ["site", "operations"].contains(initialLine) {
                selectedLine = initialLine
            }
        }
    }
}

private struct SiteAdvisorHomeView: View {
    @Environment(AppStore.self) private var appStore
    @State private var threadSearchText = ""
    @State private var startsEvaluation = false
    @State private var managesThreads = false
    @State private var selectedThreadPointIDs: Set<String> = []
    @State private var showsSelectedThreadDeletion = false
    @State private var expandedGroupIDs: Set<String> = []
    @State private var managedThread: AnalysisReport?
    @State private var groupEditor: ReportGroupEditorContext?
    @State private var groupPendingDeletion: ReportCollectionGroup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                if !appStore.advisorServiceStatus.isReady {
                    serviceNotice(appStore.advisorServiceStatus)
                }

                threadHeader

                if appStore.latestAdvisorReports.count > 4 {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.blue)
                        TextField("Search for sites or business categories", text: $threadSearchText)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("advisor.threadSearch")
                        if !threadSearchText.isEmpty {
                            Button {
                                threadSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear site search")
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 0.8)
                    }
                }

                if appStore.latestAdvisorReports.isEmpty {
                    emptyState
                } else if filteredAdvisorReports.isEmpty {
                    InlineStatusCard(
                        title: "No matching sites found",
                        detail: "Try location names, specific business types, or brand keywords.",
                        tint: AppTheme.amber,
                        symbol: "magnifyingglass"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(advisorSections) { section in
                            ReportGroupDisclosureHeader(
                                section: section,
                                isExpanded: sectionIsExpanded(section),
                                onToggle: { toggleSection(section.id) },
                                onRename: section.group.map { group in
                                    { groupEditor = ReportGroupEditorContext(group: group) }
                                },
                                onDelete: section.group.map { group in
                                    { groupPendingDeletion = group }
                                }
                            )

                            if sectionIsExpanded(section) {
                                ForEach(section.reports) { report in
                                    advisorReportEntry(report)
                                }
                            }
                        }
                    }
                }

                Text("Answers use this site’s latest report, recent chats, and cited public records. Verify findings in person.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(AppBackdrop(accent: AppTheme.periwinkle))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if managesThreads {
                threadManagementDock
            }
        }
        .refreshable { await appStore.refreshServiceStatus() }
        .navigationDestination(isPresented: $startsEvaluation) {
            BusinessTypePickerView()
        }
        .sheet(item: $managedThread) { report in
            AdvisorThreadManagementSheet(report: report)
        }
        .sheet(item: $groupEditor) { context in
            ReportGroupEditorSheet(context: context)
        }
        .confirmationDialog(
            "Delete “\(groupPendingDeletion?.name ?? "")” group?",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { if !$0 { groupPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                if let groupPendingDeletion {
                    appStore.deleteReportGroup(groupPendingDeletion)
                    expandedGroupIDs.remove(groupPendingDeletion.id)
                }
                self.groupPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { groupPendingDeletion = nil }
        } message: {
            Text("Assessment reports and Advisor chats in this group will move to “Ungrouped.” Nothing will be deleted.")
        }
        .confirmationDialog(
            "Delete selected advisor chats?",
            isPresented: $showsSelectedThreadDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedThreadPointIDs.count) chat(s)", role: .destructive) {
                deleteSelectedThreads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Assessment reports will remain available. You can start a new Advisor chat from the related report.")
        }
    }

    private var threadHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if !appStore.latestAdvisorReports.isEmpty {
                Button {
                    groupEditor = .create
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(AppTheme.blue)
                .accessibilityIdentifier("advisor.createGroup")
            }
            Spacer(minLength: 8)
            if !appStore.latestAdvisorReports.isEmpty {
                Button(managesThreads ? "Done" : "Manage") {
                    managesThreads.toggle()
                    if !managesThreads { selectedThreadPointIDs.removeAll() }
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(AppTheme.blue)
                .accessibilityIdentifier("advisor.manageThreads")
            }
        }
    }

    private func threadRow(_ report: AnalysisReport) -> some View {
        AdvisorThreadRow(
            report: report,
            conversation: appStore.advisorConversation(for: report),
            isRunning: appStore.isAdvisorResponding &&
                appStore.advisorActivePointID == report.place.id,
            isPinned: appStore.isAdvisorThreadPinned(report)
        )
    }

    private var threadManagementDock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedThreadPointIDs.count) selected")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("advisor.managementDock")
                    Button(allFilteredThreadsSelected ? "Deselect All" : "Select All in Current List") {
                        toggleSelectAllThreads()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Move to Ungrouped") { moveSelectedThreads(to: nil) }
                    ForEach(appStore.reportGroups) { group in
                        Button(group.name) { moveSelectedThreads(to: group.id) }
                    }
                } label: {
                    Label("Move", systemImage: "folder")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(selectedThreadPointIDs.isEmpty)
                .accessibilityIdentifier("advisor.moveSelectedThreads")
                Button(role: .destructive) {
                    showsSelectedThreadDeletion = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.red)
                .disabled(selectedThreadPointIDs.isEmpty)
                .accessibilityIdentifier("advisor.deleteSelectedThreads")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 0.8) }
        .shadow(color: AppTheme.navy.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var allFilteredThreadsSelected: Bool {
        let visibleIDs = Set(filteredAdvisorReports.map(\.place.id))
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedThreadPointIDs)
    }

    private func toggleThreadSelection(_ pointID: String) {
        if selectedThreadPointIDs.contains(pointID) {
            selectedThreadPointIDs.remove(pointID)
        } else {
            selectedThreadPointIDs.insert(pointID)
        }
    }

    private func toggleSelectAllThreads() {
        let visibleIDs = Set(filteredAdvisorReports.map(\.place.id))
        if allFilteredThreadsSelected {
            selectedThreadPointIDs.subtract(visibleIDs)
        } else {
            selectedThreadPointIDs.formUnion(visibleIDs)
        }
    }

    private func deleteSelectedThreads() {
        let reports = appStore.latestAdvisorReports.filter {
            selectedThreadPointIDs.contains($0.place.id)
        }
        appStore.deleteAdvisorThreads(reports)
        selectedThreadPointIDs.removeAll()
        if appStore.latestAdvisorReports.isEmpty { managesThreads = false }
    }

    private func moveSelectedThreads(to groupID: String?) {
        let reports = appStore.latestAdvisorReports.filter {
            selectedThreadPointIDs.contains($0.place.id)
        }
        appStore.moveReports(reports, toGroupID: groupID)
        selectedThreadPointIDs.removeAll()
    }

    private var filteredAdvisorReports: [AnalysisReport] {
        let query = threadSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appStore.latestAdvisorReports }
        return appStore.latestAdvisorReports.filter { report in
            [report.place.name, report.place.address ?? "", report.plan.businessDescription]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var advisorSections: [ReportCollectionSection] {
        appStore.reportCollectionSections(for: filteredAdvisorReports)
            .filter { threadSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.reports.isEmpty }
    }

    private func sectionIsExpanded(_ section: ReportCollectionSection) -> Bool {
        !threadSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || expandedGroupIDs.contains(section.id)
    }

    private func toggleSection(_ sectionID: String) {
        withAnimation(.snappy) {
            if expandedGroupIDs.contains(sectionID) {
                expandedGroupIDs.remove(sectionID)
            } else {
                expandedGroupIDs.insert(sectionID)
            }
        }
    }

    @ViewBuilder
    private func advisorReportEntry(_ report: AnalysisReport) -> some View {
        if managesThreads {
            Button {
                toggleThreadSelection(report.place.id)
            } label: {
                HStack(spacing: 10) {
                    SelectionMark(isSelected: selectedThreadPointIDs.contains(report.place.id))
                    threadRow(report)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("advisor.manageThread.\(report.place.id)")
            .accessibilityLabel("\(report.place.name),\(report.plan.businessDescription)")
            .accessibilityValue(selectedThreadPointIDs.contains(report.place.id) ? "Selected" : "Not Selected")
        } else {
            NavigationLink { AdvisorConversationView(report: report) } label: {
                threadRow(report)
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: 0.45) {
                managedThread = report
            }
            .accessibilityIdentifier("advisor.thread.\(report.place.id)")
            .accessibilityAction(named: "Manage Chats") { managedThread = report }
            .accessibilityAction(named: appStore.isAdvisorThreadPinned(report) ? "Unpin" : "Pin") {
                appStore.toggleAdvisorThreadPinned(report)
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            AgentOrb(size: 62, isActive: appStore.isAdvisorResponding)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text("Site Advisor")
                        .font(.title2.bold())
                    if appStore.advisorServiceStatus == .ready {
                        Label("Online", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.mint)
                    }
                }
                Text("Ask about completed site assessments and see the status of any source checks.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.navy, AppTheme.blue.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 1)
                .frame(width: 150, height: 150)
                .offset(x: 42, y: 54)
                .accessibilityHidden(true)
        }
        .clipped()
        .shadow(color: AppTheme.blue.opacity(0.18), radius: 24, y: 12)
    }

    private func serviceNotice(_ status: AnalysisServiceStatus) -> some View {
        ServiceStatusCard(
            status: status,
            serviceName: "Site Advisor",
            detail: advisorStatusDetail(status)
        ) {
            Task { await appStore.refreshServiceStatus() }
        }
    }

    private func advisorStatusDetail(_ status: AnalysisServiceStatus) -> String {
        switch status {
        case .ready:
            "Continue a site-specific conversation."
        case .checking:
            "Checking Site Advisor and source access."
        case .unconfigured:
            "New chats are unavailable. Saved reports remain available."
        case let .unavailable(message):
            UserFacingCopy.externalMessage(message, fallback: "Site Advisor is temporarily unavailable.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 64, height: 64)
                .background(AppTheme.blue.opacity(0.10), in: Circle())
            Text("No Assessments Yet").font(.headline)
            Text("Complete an assessment to start a site-specific chat.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
            Button {
                if appStore.startNewEvaluation() {
                    startsEvaluation = true
                }
            } label: {
                PrimaryActionLabel(title: "Assess a Site", systemImage: "location.magnifyingglass")
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityIdentifier("advisor.startEvaluation")
        }
        .frame(maxWidth: .infinity)
        .appCard(contentPadding: 24)
    }
}

private struct AdvisorThreadManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var appStore
    let report: AnalysisReport
    @State private var confirmsDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(AppTheme.border)
                    .frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 12) {
                    FeatureIcon(symbol: report.plan.category.symbol, tint: AppTheme.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.place.name)
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                        Text(report.plan.businessDescription)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.blue)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.canvas, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }

                Button {
                    appStore.toggleAdvisorThreadPinned(report)
                } label: {
                    managementRow(
                        title: appStore.isAdvisorThreadPinned(report) ? "Unpin" : "Pin this chat",
                        detail: appStore.isAdvisorThreadPinned(report) ? "Revert to sorting by most recent chat time" : "Keep this site at the top",
                        symbol: appStore.isAdvisorThreadPinned(report) ? "pin.slash.fill" : "pin.fill",
                        tint: AppTheme.amber
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Archive group")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Label("Linked to assessment reports", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }

                    groupChoice(title: "Ungrouped", groupID: nil, symbol: "tray.full.fill")
                    ForEach(appStore.reportGroups) { group in
                        groupChoice(title: group.name, groupID: group.id, symbol: "folder.fill")
                    }
                }
                .padding(14)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 0.8) }

                Button(role: .destructive) {
                    confirmsDeletion = true
                } label: {
                    managementRow(
                        title: "Delete this chat",
                        detail: "The assessment report will remain available. You can start another chat from it.",
                        symbol: "trash.fill",
                        tint: AppTheme.red
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("advisor.deleteManagedThread")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(AppBackdrop(accent: AppTheme.periwinkle))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(30)
        .confirmationDialog("Delete this advisor chat?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete chat", role: .destructive) {
                appStore.deleteAdvisorThread(report)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this Advisor chat will be deleted. The related assessment report will remain.")
        }
    }

    private var selectedGroupID: String? {
        appStore.reportGroup(for: report)?.id
    }

    private func groupChoice(title: String, groupID: String?, symbol: String) -> some View {
        Button {
            appStore.moveReport(report, toGroupID: groupID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(groupID == nil ? AppTheme.amber : AppTheme.blue)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if selectedGroupID == groupID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.mint)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Move to \(title)")
    }

    private func managementRow(title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                Text(detail).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.muted)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19).stroke(AppTheme.border, lineWidth: 0.8) }
    }
}

private struct AdvisorThreadRow: View {
    let report: AnalysisReport
    let conversation: AdvisorConversation
    let isRunning: Bool
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(rowTint.opacity(0.12))
                Image(systemName: isRunning ? "sparkles" : report.isStale ? "clock.badge.exclamationmark" : "mappin.and.ellipse")
                    .font(.title3.bold())
                    .foregroundStyle(rowTint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(report.place.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    Spacer()
                    if isPinned {
                        Label("Pin", systemImage: "pin.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.blue)
                    }
                    Text(conversation.messages.isEmpty ? "New chat" : conversation.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
                HStack(spacing: 6) {
                    Text(report.plan.businessDescription)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.blue)
                        .lineLimit(1)
                    if report.isStale {
                        Text("Pending review")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.amber)
                    }
                }
                Text(lastLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(report.place.name), \(report.plan.businessDescription), \(isPinned ? "pinned, " : "")\(isRunning ? "answering" : conversation.messages.isEmpty ? "new conversation" : "conversation history available")"
        )
    }

    private var rowTint: Color {
        report.isStale ? AppTheme.amber : report.decision?.tint ?? AppTheme.blue
    }

    private var lastLine: String {
        if isRunning { return "Site Advisor is analyzing questions about this site…" }
        return conversation.messages.last?.compactPreview
            ?? "Start with the report from \(report.generatedAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct AdvisorConversationView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(CommunityStore.self) private var communityStore
    @Environment(MessagingStore.self) private var messagingStore
    let report: AnalysisReport
    @State private var input = ""
    @State private var showsGroupContextPicker = false
    @State private var isAuthorizingSpend = false
    @FocusState private var composerFocused: Bool

    private var conversation: AdvisorConversation {
        appStore.advisorConversation(for: report)
    }

    private var isRunningHere: Bool {
        appStore.isAdvisorResponding && appStore.advisorActivePointID == report.place.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    pointContext

                    SharedGroupContextCard(
                        contexts: conversation.sharedGroupContexts,
                        onAdd: { showsGroupContextPicker = true },
                        onRemove: { appStore.removeGroupContext(groupID: $0, from: report) }
                    )

                    if conversation.messages.isEmpty {
                        welcomeMessage
                    } else {
                        ForEach(conversation.messages) { message in
                            AdvisorMessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    Color.clear.frame(height: 2).id("advisor-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
            .defaultScrollAnchor(conversation.messages.isEmpty ? .top : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) { _, _ in
                if let latest = conversation.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(latest.id, anchor: latest.role == "assistant" ? .top : .bottom)
                    }
                }
            }
        }
        .background(AppBackdrop(accent: AppTheme.periwinkle))
        .navigationTitle(report.place.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
        .onAppear { appStore.restoreAdvisorThread(report) }
        .task { await messagingStore.refresh(token: communityStore.messagingToken) }
        .sheet(isPresented: $showsGroupContextPicker) {
            NavigationStack {
                PersonalGroupHistoryPicker { context in
                    appStore.importGroupContext(context, into: report)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var pointContext: some View {
        HStack(alignment: .top, spacing: 12) {
            FeatureIcon(symbol: "mappin.and.ellipse", tint: AppTheme.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text("Business type · \(report.plan.businessDescription)")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("Site · \(report.place.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
                Text("Based on the site report from \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                if report.isStale {
                    Label("Old report. Checking recent sources.", systemImage: "clock.arrow.circlepath")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.amber)
                }
            }
            Spacer()
            if !report.isStale, let score = report.assessmentScores?.overall {
                Text(String(format: "%.1f", score))
                    .font(.title3.bold())
                    .foregroundStyle(report.decision?.tint ?? AppTheme.blue)
            }
        }
        .appCard(contentPadding: 14)
    }

    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AgentOrb(size: 38, isActive: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Site Advisor has learned about this site").font(.headline)
                    Text("I’ll use this report first and check current sources when needed.")
                        .font(.caption).foregroundStyle(AppTheme.muted)
                }
            }
            suggestionButton("Why is this site rated “\(report.decision?.title ?? "current")”?")
            suggestionButton("What should I verify on site?")
            suggestionButton("Check for recent business changes near this site.")
        }
        .appCard(contentPadding: 16)
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            send(text)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.up.right")
                Text(text).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.blue)
            .padding(12)
            .background(AppTheme.blue.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRunningHere)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let suggestions = conversation.messages.last?.suggestedQuestions,
               !suggestions.isEmpty, !isRunningHere {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { item in
                            Button(item) { send(item) }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.blue)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 44)
                                .background(AppTheme.blue.opacity(0.08), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(AppTheme.amber)
                Text("1 Easy Credit per successful reply · Failed attempts are automatically refunded")
                Spacer()
                Text("Balance \(communityStore.creditWallet?.balance ?? 0)")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 18)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Site Advisor about this site…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(composerFocused ? AppTheme.blue.opacity(0.55) : AppTheme.border, lineWidth: 1)
                    }
                    .accessibilityIdentifier("advisor.composer")
                Button {
                    send(input)
                } label: {
                    Image(systemName: isRunningHere ? "ellipsis" : "arrow.up")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(canSend ? AppTheme.solidBlue : AppTheme.muted.opacity(0.35), in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send question")
                .accessibilityIdentifier("advisor.send")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if isRunningHere, let progress = appStore.advisorProgress {
                ScrollView {
                    AdvisorProgressCard(progress: progress) {
                        appStore.cancelAdvisorResponse()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                }
                .frame(maxHeight: 500)
                .accessibilityIdentifier("advisor.progressPanel")
            } else if appStore.isAdvisorResponding {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("Site Advisor is busy with another site.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            } else if let error = appStore.advisorLastError,
                      appStore.advisorErrorPointID == report.place.id,
                      conversation.messages.last?.role == "user" {
                AdvisorErrorCard(error: error) {
                    retryLastQuestion()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            } else if conversation.messages.last?.role == "user" {
                AdvisorIncompleteCard {
                    retryLastQuestion()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            composer
        }
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        let count = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (2...2_000).contains(count) &&
            !appStore.isAdvisorResponding &&
            !isAuthorizingSpend
    }

    private func send(_ question: String) {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return }
        isAuthorizingSpend = true
        Task {
            defer { isAuthorizingSpend = false }
            guard let reservation = await communityStore.reserveCreditUsage(.siteAdvisorTurn) else {
                return
            }
            input = ""
            composerFocused = false
            if await appStore.sendAdvisorQuestion(normalized, about: report) {
                await communityStore.settleCreditUsage(reservation)
            } else {
                await communityStore.refundCreditUsage(reservation)
            }
        }
    }

    private func retryLastQuestion() {
        guard let question = conversation.messages.last?.content else { return }
        guard !isAuthorizingSpend else { return }
        isAuthorizingSpend = true
        Task {
            defer { isAuthorizingSpend = false }
            guard let reservation = await communityStore.reserveCreditUsage(.siteAdvisorTurn) else {
                return
            }
            if await appStore.sendAdvisorQuestion(question, about: report) {
                await communityStore.settleCreditUsage(reservation)
            } else {
                await communityStore.refundCreditUsage(reservation)
            }
        }
    }
}

struct AdvisorMessageBubble: View {
    let message: AdvisorMessage
    @State private var showsSources = false
    @State private var didCopy = false
    @State private var selectedSource: ResearchSource?

    private var citationSources: [Int: ResearchSource] {
        AdvisorCitationFormatter.sourceMap(content: message.content, sources: message.sources)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == "user" { Spacer(minLength: 42) }
            if message.role == "assistant" { AgentOrb(size: 30, isActive: false) }
            VStack(alignment: .leading, spacing: 10) {
                if message.role == "assistant" {
                    HStack(spacing: 8) {
                        Label("Site Advisor", systemImage: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.blue)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = message.content.replacingOccurrences(
                                of: #"\s*\[Resource \d{1,3}\]"#,
                                with: "",
                                options: .regularExpression
                            )
                            didCopy = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                didCopy = false
                            }
                        } label: {
                            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(didCopy ? AppTheme.mint : AppTheme.muted)
                        .accessibilityLabel(didCopy ? "Answer copied" : "Copy answer")
                    }
                    AdvisorRichText(
                        content: message.content,
                        sources: citationSources
                    ) { source in
                        selectedSource = source
                    }
                } else {
                    Text(message.content)
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !message.sources.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showsSources.toggle() }
                    } label: {
                        Label("Cites \(message.sources.count) public sources", systemImage: showsSources ? "chevron.up" : "link")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(message.role == "user" ? .white.opacity(0.8) : AppTheme.blue)
                    if showsSources {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(message.sources) { source in
                                if source.publicURL != nil {
                                    Button {
                                        selectedSource = source
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.title).font(.caption.bold()).lineLimit(2)
                                            Text(source.sourceLabel).font(.caption2).foregroundStyle(AppTheme.muted)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(AppTheme.blue)
                                    .accessibilityLabel("Open public source: \(source.title)")
                                    .accessibilityHint("Opens in-app. Close to return to the chat.")
                                    .accessibilityIdentifier("advisor.source.\(source.citationIndex ?? 0)")
                                }
                            }
                        }
                        .padding(10)
                        .background(AppTheme.canvas.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                message.role == "user" ? AppTheme.solidBlue : AppTheme.card,
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                if message.role == "assistant" {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            if message.role == "assistant" { Spacer(minLength: 4) }
        }
        .accessibilityIdentifier("advisor.message.\(message.role).\(message.id)")
        .sheet(item: $selectedSource) { source in
            if let url = source.publicURL {
                AdvisorSourceBrowser(url: url)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Unable to open this source", systemImage: "link.badge.plus")
            }
        }
    }
}

struct AdvisorRichText: View {
    let blocks: [AdvisorContentBlock]
    let sources: [Int: ResearchSource]
    let openSource: (ResearchSource) -> Void

    init(
        content: String,
        sources: [Int: ResearchSource],
        openSource: @escaping (ResearchSource) -> Void
    ) {
        blocks = AdvisorContentParser.parse(content)
        self.sources = sources
        self.openSource = openSource
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isFirst: index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(AppTheme.ink)
        .environment(\.openURL, OpenURLAction { url in
            guard let citationIndex = AdvisorCitationFormatter.citationIndex(from: url) else {
                return .systemAction
            }
            guard let source = sources[citationIndex] else { return .discarded }
            openSource(source)
            return .handled
        })
    }

    @ViewBuilder
    private func blockView(_ block: AdvisorContentBlock, isFirst: Bool) -> some View {
        switch block {
        case let .heading(level, text):
            inlineText(text)
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .foregroundStyle(level <= 2 ? AppTheme.navy : AppTheme.ink)
                .padding(.top, isFirst ? 0 : 5)
                .fixedSize(horizontal: false, vertical: true)
        case let .paragraph(text):
            inlineText(text)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedItem(text):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("•")
                    .font(.body.bold())
                    .foregroundStyle(AppTheme.blue)
                inlineText(text)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .orderedItem(number, text):
            HStack(alignment: .top, spacing: 9) {
                Text(number)
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(AppTheme.solidBlue, in: Circle())
                inlineText(text)
                    .font(.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .divider:
            Divider().opacity(0.55).padding(.vertical, 2)
        }
    }

    private func inlineText(_ value: String) -> Text {
        var attributed = (
            try? AttributedString(markdown: AdvisorCitationFormatter.inlineMarkdown(value))
        ) ?? AttributedString(value)
        for run in attributed.runs {
            guard let url = run.link,
                  AdvisorCitationFormatter.citationIndex(from: url) != nil else { continue }
            attributed[run.range].foregroundColor = AppTheme.blue
            attributed[run.range].backgroundColor = AppTheme.blue.opacity(0.12)
            attributed[run.range].font = .caption2.bold()
        }
        return Text(attributed)
    }
}

struct AdvisorSourceBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(AppTheme.blue)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct AdvisorProgressCard: View {
    let progress: AdvisorGenerationProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AgentOrb(size: 44, isActive: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.title).font(.headline)
                    Text(progress.detail).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text("\(progress.progressPercent)%")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.blue)
            }
            ProgressView(value: Double(progress.progressPercent), total: 100)
                .tint(AppTheme.blue)
                .accessibilityLabel("Task progress")
                .accessibilityValue("\(progress.progressPercent)%")

            if !progress.activities.isEmpty {
                VStack(spacing: 9) {
                    ForEach(progress.activities) { activity in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: activitySymbol(activity.state))
                                .foregroundStyle(activityTint(activity.state))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.title).font(.caption.bold())
                                Text(activity.detail).font(.caption2).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                        }
                    }
                }
            }

            if !progress.researchTraces.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Looking up").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                    ForEach(progress.researchTraces) { trace in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(trace.title, systemImage: trace.state == "completed" ? "checkmark" : "globe.americas")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trace.state == "failed" ? AppTheme.amber : AppTheme.ink)
                            ForEach(Array(trace.sourceURLs.prefix(3)), id: \.self) { rawURL in
                                if let url = safePublicURL(rawURL) {
                                    Link(destination: url) {
                                        Text(compactURL(url))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(AppTheme.muted)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(11)
                .background(AppTheme.canvas.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack {
                Text("Elapsed: \(progress.elapsedSeconds) sec")
                if progress.estimatedRemainingSeconds > 0 {
                    Text("· ~\(progress.estimatedRemainingSeconds) sec remaining")
                }
                Spacer()
                Button("Stop", role: .destructive, action: cancel)
                    .font(.caption.bold())
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 16)
        .accessibilityIdentifier("advisor.progress")
    }

    private func activitySymbol(_ state: String) -> String {
        switch state {
        case "completed": "checkmark.circle.fill"
        case "failed": "exclamationmark.circle.fill"
        default: "circle.dotted"
        }
    }

    private func activityTint(_ state: String) -> Color {
        switch state {
        case "completed": AppTheme.mint
        case "failed": AppTheme.amber
        default: AppTheme.blue
        }
    }

    private func safePublicURL(_ rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, ResearchSource.isPublicHost(host.lowercased()) else { return nil }
        return url
    }

    private func compactURL(_ url: URL) -> String {
        let value = (url.host ?? "") + url.path
        return value.count > 62 ? String(value.prefix(59)) + "…" : value
    }
}

struct AdvisorErrorCard: View {
    let error: APIClientError
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Response Incomplete", systemImage: "exclamationmark.bubble.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.red)
            Text(
                UserFacingCopy.externalMessage(
                    error.localizedDescription,
                    fallback: "Site Advisor could not complete this response."
                )
            )
            .font(.subheadline)
            .foregroundStyle(AppTheme.ink)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion).font(.caption).foregroundStyle(AppTheme.muted)
            }
            Button("Resend last question", action: retry)
                .font(.subheadline.bold())
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(contentPadding: 16)
    }
}

private struct AdvisorIncompleteCard: View {
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("This response is incomplete")
                    .font(.subheadline.bold())
                Text("Question saved. You can retry.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 8)
            Button("Retry", action: retry)
                .font(.caption.bold())
                .buttonStyle(.bordered)
        }
        .appCard(contentPadding: 14)
        .accessibilityIdentifier("advisor.incomplete")
    }
}

struct AgentOrb: View {
    let size: CGFloat
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [AppTheme.blue, AppTheme.amber, AppTheme.periwinkle, AppTheme.blue],
                        center: .center
                    )
                )
            Circle()
                .fill(AppTheme.navy.opacity(isActive ? 0.70 : 0.82))
                .padding(size * 0.12)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.31, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.blue.opacity(isActive ? 0.34 : 0.16), radius: isActive ? 12 : 6)
        .accessibilityHidden(true)
    }
}
