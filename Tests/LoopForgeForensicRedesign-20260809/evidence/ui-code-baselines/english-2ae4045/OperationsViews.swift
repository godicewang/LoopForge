import CoreLocation
import Charts
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OperationsHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OperationsStore.self) private var store
    @State private var createsProfile = false
    @State private var editsProfile: OperatingStoreProfile?
    @State private var showsCadenceReminder = false
    @State private var trendMetric: OperatingTrendMetric = .revenue
    @State private var trendRange: OperatingTrendRange = .week
    @State private var customTrendStart = OperatingCalendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customTrendEnd = Date.now
    @State private var showsCustomTrendRange = false
    @State private var showsFirstReminderPrompt = false
    @State private var showsFirstReminderSetup = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if !store.serviceStatus.isReady {
                    ServiceStatusCard(
                        status: store.serviceStatus,
                        serviceName: "Operations Advisor",
                        detail: "Local records stay available. Online advice is offline."
                    ) {
                        Task { await store.refreshServiceStatus() }
                    }
                }
                if let notice = store.storageNotice {
                    InlineStatusCard(
                        title: "Business records not saved",
                        detail: notice,
                        tint: AppTheme.amber,
                        symbol: "externaldrive.badge.exclamationmark"
                    )
                }
                if let profile = store.selectedProfile {
                    storePicker(profile)
                    cadenceControl(profile)
                    todayPrioritySection(profile)
                    pulseSection(profile)
                    reviewSection(profile)
                    trendSection(profile)
                    quickActions(profile)
                    growthSection(profile)
                    recentRecords(profile)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Operations Advisor")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestExit()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { createsProfile = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Store Profile")
            }
        }
        .sheet(isPresented: $createsProfile) {
            NavigationStack { OperatingProfileEditorView(profile: OperatingStoreProfile()) }
        }
        .sheet(item: $editsProfile) { profile in
            NavigationStack { OperatingProfileEditorView(profile: profile) }
        }
        .sheet(isPresented: $showsFirstReminderSetup) {
            NavigationStack {
                OperatingReminderView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showsFirstReminderSetup = false }
                        }
                    }
            }
        }
        .task { await store.refreshServiceStatus() }
        .onAppear {
            store.beginOperationsAssistantSession()
            evaluateDailyCadenceReminder()
        }
        .onChange(of: store.workspace.selectedStoreID) { _, _ in evaluateDailyCadenceReminder() }
        .alert("Finding daily logging tough?", isPresented: $showsCadenceReminder) {
            if let profile = store.selectedProfile {
                Button("Switch to weekly logging") { store.setRecordingCadence(.weekly, for: profile.id) }
            }
            Button("Keep daily logging", role: .cancel) {}
        } message: {
            Text("Few daily records exist. Weekly logging keeps existing data and still supports monthly summaries.")
        }
        .confirmationDialog(
            "Set up business reminders first?",
            isPresented: $showsFirstReminderPrompt,
            titleVisibility: .visible
        ) {
            Button("Set up now") {
                store.acknowledgeFirstReminderPrompt()
                showsFirstReminderSetup = true
            }
            Button("Skip and exit") {
                store.acknowledgeFirstReminderPrompt()
                store.endOperationsAssistantSession()
                dismiss()
            }
            Button("Continue in Advisor", role: .cancel) {}
        } message: {
            Text("Set daily, weekly, or monthly reminders. Change them anytime in Business Settings.")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            AgentOrb(size: 58, isActive: store.isResponding)
            VStack(alignment: .leading, spacing: 7) {
                Text("Turn revenue into action")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Track weekly changes and monthly profit from confirmed records.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.deepClay, AppTheme.blue.opacity(0.92), AppTheme.amber.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: AppTheme.deepClay.opacity(0.18), radius: 22, y: 10)
    }

    private func storePicker(_ profile: OperatingStoreProfile) -> some View {
        HStack(spacing: 12) {
            FeatureIcon(symbol: "storefront.fill", tint: AppTheme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.headline).foregroundStyle(AppTheme.ink)
                Text([profile.category, profile.locationLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Menu {
                ForEach(store.workspace.profiles) { item in
                    Button(item.name) { store.selectStore(item.id) }
                }
                Divider()
                Button("Edit Current Store") { editsProfile = profile }
                Button("Add Store") { createsProfile = true }
            } label: {
                Label("Switch", systemImage: "chevron.down")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.blue)
        }
        .appCard(contentPadding: 14)
    }

    private func cadenceControl(_ profile: OperatingStoreProfile) -> some View {
        let cadence = store.recordingCadence(for: profile.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("How to log business data").font(.headline).foregroundStyle(AppTheme.ink)
                    Text(cadence.detail).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Menu {
                    ForEach(OperatingRecordingCadence.allCases) { option in
                        Button {
                            store.setRecordingCadence(option, for: profile.id)
                        } label: {
                            Label(option.title, systemImage: option == cadence ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label(cadence.title, systemImage: "slider.horizontal.3")
                        .font(.caption.bold())
                        .padding(.horizontal, 11)
                        .frame(minHeight: 40)
                        .background(AppTheme.blue.opacity(0.09), in: Capsule())
                }
                .tint(AppTheme.blue)
                .accessibilityIdentifier("operations.cadenceMenu")
            }
        }
        .appCard(contentPadding: 15)
    }

    @ViewBuilder
    private func todayPrioritySection(_ profile: OperatingStoreProfile) -> some View {
        let readiness = store.dataReadiness(for: profile.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                FeatureIcon(symbol: readiness.canExplainProfit ? "sparkles" : "scope", tint: readiness.canExplainProfit ? AppTheme.blue : AppTheme.amber)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Do one thing today").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                    Text(readiness.title).font(.headline).foregroundStyle(AppTheme.ink)
                    Text(readiness.detail).font(.caption).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                readinessPill("Weekly Pulse \(readiness.confirmedWeeks)", ready: readiness.confirmedWeeks > 0)
                readinessPill("Monthly Summary \(readiness.confirmedMonths)", ready: readiness.confirmedMonths > 0)
                readinessPill("Profit recalculable", ready: readiness.canExplainProfit)
            }
            if readiness.canExplainProfit {
                NavigationLink { OperatingAdvisorConversationView(profile: profile) } label: {
                    Label("Get Priority Actions", systemImage: "arrow.right")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.blue)
            } else {
                NavigationLink {
                    ledgerEntryDestination(profile)
                } label: {
                    Label(store.recordingCadence(for: profile.id) == .daily ? "Log today" : "Complete last week’s log", systemImage: "arrow.right")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.amber)
            }
        }
        .appCard(contentPadding: 17)
        .accessibilityIdentifier("operations.todayPriority")
    }

    @ViewBuilder
    private func ledgerEntryDestination(_ profile: OperatingStoreProfile) -> some View {
        if store.recordingCadence(for: profile.id) == .daily {
            OperatingLedgerEditorView(mode: .daily(storeID: profile.id, existing: store.dailyRecord(for: profile.id)))
        } else {
            OperatingLedgerEditorView(mode: .weekly(storeID: profile.id, existing: store.weeklyRecord(for: profile.id)))
        }
    }

    private func readinessPill(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption2.bold())
            .foregroundStyle(ready ? AppTheme.mint : AppTheme.muted)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background((ready ? AppTheme.mint : AppTheme.muted).opacity(0.08), in: Capsule())
    }

    private func pulseSection(_ profile: OperatingStoreProfile) -> some View {
        let cadence = store.recordingCadence(for: profile.id)
        let records = store.effectiveWeeklyRecords(for: profile.id)
        let latest = records.first(where: { $0.state == .confirmed })
        let current = store.weeklyRecord(for: profile.id)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Weekly Business Pulse", caption: cadence == .daily ? "Automatically summarized from daily logs" : (latest == nil ? "Not yet recorded" : "Recently confirmed"))
            if let latest {
                let profit = latest.metrics.operatingProfit
                HStack(spacing: 10) {
                    OperatingMetricCell(title: "Weekly revenue", value: latest.revenue?.currencyUSD ?? "Not recorded", tint: AppTheme.blue)
                    OperatingMetricCell(
                        title: "Operating Profit",
                        value: profit?.currencyUSD ?? (latest.revenue == nil ? "Missing revenue" : "Missing costs"),
                        tint: profit.map { $0 >= 0 ? AppTheme.mint : AppTheme.red } ?? AppTheme.muted
                    )
                    OperatingMetricCell(title: "Average Order Value", value: latest.metrics.averageTicket?.currencyUSD ?? "Missing orders", tint: AppTheme.amber)
                }
                if cadence == .weekly {
                    NavigationLink {
                        OperatingLedgerEditorView(mode: .weekly(storeID: profile.id, existing: latest))
                    } label: {
                        Label("Review Past Week", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.blue)
                }
            } else {
                Text("Enter revenue, orders, and actual costs to calculate margins. No industry averages are substituted.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            if cadence == .daily {
                NavigationLink {
                    OperatingLedgerEditorView(mode: .daily(storeID: profile.id, existing: store.dailyRecord(for: profile.id)))
                } label: {
                    PrimaryActionLabel(
                        title: store.dailyRecord(for: profile.id) == nil ? "Log today’s business data" : "Continue completing today’s log",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("operations.addDaily")
            } else if current?.id != latest?.id {
                NavigationLink {
                    OperatingLedgerEditorView(mode: .weekly(storeID: profile.id, existing: current))
                } label: {
                    PrimaryActionLabel(title: current == nil ? "Log last week’s business pulse" : "Continue completing last week’s log", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("operations.addWeekly")
            }
            if latest != nil {
                NavigationLink { OperatingAdvisorConversationView(profile: profile, focus: .weeklyReview) } label: {
                    Label("Discuss Last Week", systemImage: "bubble.left.and.text.bubble.right.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.blue)
            }
        }
        .appCard(contentPadding: 18)
    }

    private func reviewSection(_ profile: OperatingStoreProfile) -> some View {
        let previousMonth = OperatingCalendar.current.date(byAdding: .month, value: -1, to: Date.now) ?? .now
        let latest = store.automaticMonthlyRecord(for: profile.id, monthContaining: previousMonth)
        let coverage = store.automaticMonthCoverage(for: profile.id, monthContaining: previousMonth)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Monthly Business Review", caption: previousMonth.formatted(.dateTime.year().month()) + " · Auto-summarized by system")
            if let latest {
                let profit = latest.metrics.operatingProfit
                HStack(spacing: 10) {
                    OperatingMetricCell(title: "Monthly revenue", value: latest.revenue?.currencyUSD ?? "Not recorded", tint: AppTheme.blue)
                    OperatingMetricCell(title: "Total Cost", value: latest.costs.total?.currencyUSD ?? "Incomplete", tint: AppTheme.amber)
                    OperatingMetricCell(
                        title: "Operating profit",
                        value: profit?.currencyUSD ?? (latest.revenue == nil ? "Missing revenue" : "Missing costs"),
                        tint: profit.map { $0 >= 0 ? AppTheme.mint : AppTheme.red } ?? AppTheme.muted
                    )
                }
                Label("\(coverage.actual) / \(coverage.expected) \(coverage.unit) summarized · gaps stay empty", systemImage: coverage.actual >= coverage.expected ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(coverage.actual >= coverage.expected ? AppTheme.mint : AppTheme.amber)
            } else {
                Text("No confirmed records exist for last month. Gaps are not filled with industry averages.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            NavigationLink {
                OperatingAdvisorConversationView(profile: profile, focus: .monthlyReview)
            } label: {
                Label("Discuss Last Month", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.blue)
            .accessibilityIdentifier("operations.addMonthly")
        }
        .appCard(contentPadding: 18)
    }

    private func quickActions(_ profile: OperatingStoreProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Business Settings", caption: "Reminders, experiments, and advisor principles")
            HStack(spacing: 10) {
                NavigationLink { OperatingExperimentListView(profile: profile) } label: {
                    OperationsActionTile(title: "Action Experiments", detail: "Validate strategy effectiveness", symbol: "checkmark.seal", tint: AppTheme.mint)
                }
                NavigationLink { OperatingReminderView() } label: {
                    OperationsActionTile(title: "Proactive Reminders", detail: "Daily logs, weekly/monthly reviews", symbol: "bell.badge", tint: AppTheme.amber)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                NavigationLink { OperatingMemoryView(profile: profile) } label: {
                    OperationsActionTile(title: "Advisor Principles", detail: "Goals, constraints, and boundaries", symbol: "list.bullet.clipboard.fill", tint: AppTheme.periwinkle)
                }
                NavigationLink { OperatingReviewHistoryView(profile: profile) } label: {
                    OperationsActionTile(title: "Review Report", detail: "View weekly/monthly history", symbol: "doc.text.magnifyingglass", tint: AppTheme.blue)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func trendSection(_ profile: OperatingStoreProfile) -> some View {
        let visible = trendRange.filter(
            store.trendData(for: profile.id),
            customStart: customTrendStart,
            customEnd: customTrendEnd
        )
        let points = visible.compactMap { datum -> OperatingTrendPoint? in
            guard let value = trendMetric.value(for: datum) else { return nil }
            return OperatingTrendPoint(date: datum.date, value: value)
        }
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Business Trends", caption: "Tap metrics to switch")
                Spacer()
                Menu {
                    ForEach(OperatingTrendRange.allCases) { range in
                        Button {
                            if range == .custom {
                                showsCustomTrendRange = true
                            } else {
                                trendRange = range
                            }
                        } label: {
                            Label(range.title, systemImage: trendRange == range ? "checkmark" : "calendar")
                        }
                    }
                } label: {
                    Label(trendRange.title, systemImage: "calendar")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.blue)
                }
                .accessibilityIdentifier("operations.trendRange")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(OperatingTrendMetric.allCases) { metric in
                        Button(metric.title) { trendMetric = metric }
                            .font(.caption.bold())
                            .foregroundStyle(trendMetric == metric ? .white : AppTheme.ink)
                            .padding(.horizontal, 11)
                            .frame(minHeight: 36)
                            .background(trendMetric == metric ? AppTheme.blue : AppTheme.canvas, in: Capsule())
                    }
                }
            }
            if !points.isEmpty {
                HStack {
                    Text("Latest \(trendMetric.title)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Text(points.last?.value.formatted(.number.precision(.fractionLength(0...2))) ?? "—")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.deepClay)
                        .monospacedDigit()
                    Spacer()
                    Text("\(points.count) valid records")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.muted)
                }
                Chart(points) { point in
                    if points.count > 1 {
                        AreaMark(
                            x: .value("Billing Period", point.date),
                            y: .value(trendMetric.title, point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [AppTheme.blue.opacity(0.24), AppTheme.blue.opacity(0.01)], startPoint: .top, endPoint: .bottom)
                        )
                        LineMark(
                            x: .value("Billing Period", point.date),
                            y: .value(trendMetric.title, point.value)
                        )
                        .foregroundStyle(AppTheme.blue)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    PointMark(
                        x: .value("Billing Period", point.date),
                        y: .value(trendMetric.title, point.value)
                    )
                    .foregroundStyle(AppTheme.deepClay)
                    .symbolSize(points.count == 1 ? 110 : 58)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(points.count, 5))) { _ in
                        AxisGridLine().foregroundStyle(AppTheme.border.opacity(0.55))
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 190)
                .accessibilityLabel("\(trendMetric.title) trend chart, covering \(points.count) billing periods")
            } else {
                ContentUnavailableView(
                    "No \(trendMetric.title) data available for this period",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Data appears after confirming daily or weekly records; no need to wait for the next period.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            }
            Text("Empty periods are not connected or averaged. Review any missing or conflicting records.")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 17)
        .accessibilityIdentifier("operations.trend")
        .sheet(isPresented: $showsCustomTrendRange) {
            NavigationStack {
                OperatingTrendRangePicker(
                    start: $customTrendStart,
                    end: $customTrendEnd
                ) {
                    trendRange = .custom
                    showsCustomTrendRange = false
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func requestExit() {
        if store.shouldOfferFirstReminderSetup {
            store.acknowledgeFirstReminderPrompt()
            showsFirstReminderPrompt = true
        } else {
            store.endOperationsAssistantSession()
            dismiss()
        }
    }

    private func growthSection(_ profile: OperatingStoreProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Ask Operations Advisor", caption: "Use your actual records")
            NavigationLink { OperatingGrowthPlaybookView(profile: profile) } label: {
                HStack(spacing: 13) {
                    FeatureIcon(symbol: "person.2.wave.2.fill", tint: AppTheme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start a Consultation").font(.headline).foregroundStyle(AppTheme.ink)
                        Text("Ask about records, customers, profit, or next steps.")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                }
                .appCard(contentPadding: 15)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func recentRecords(_ profile: OperatingStoreProfile) -> some View {
        let reports = store.reviewReports(for: profile.id)
        let days = store.dailyRecords(for: profile.id)
        let weeks = store.weeklyRecords(for: profile.id)
        let months = store.monthlyRecords(for: profile.id)
        if !reports.isEmpty || !days.isEmpty || !weeks.isEmpty || !months.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("History", caption: "Review reports are saved separately from raw billing period data")
                ForEach(reports.prefix(3)) { report in
                    NavigationLink { OperatingReviewDetailView(report: report) } label: {
                        HStack(spacing: 12) {
                            FeatureIcon(symbol: report.kind == .weekly ? "doc.text.fill" : "calendar.badge.checkmark", tint: AppTheme.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(report.kind.title)
                                    .font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text(report.periodStart.formatted(.dateTime.year().month().day()) + " · Archived")
                                    .font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                        }
                        .appCard(contentPadding: 13)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(days.prefix(3)) { record in
                    NavigationLink { OperatingLedgerEditorView(mode: .daily(storeID: profile.id, existing: record)) } label: {
                        HStack(spacing: 12) {
                            FeatureIcon(symbol: record.state == .confirmed ? "checkmark.circle.fill" : "pencil.circle.fill", tint: record.state == .confirmed ? AppTheme.mint : AppTheme.amber)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.day.formatted(.dateTime.year().month().day()) + " Daily Records")
                                    .font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text("Revenue \(record.revenue?.currencyUSD ?? "not recorded") · \(record.state.title)")
                                    .font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                        }
                        .appCard(contentPadding: 13)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(weeks.prefix(3)) { record in
                    NavigationLink { OperatingLedgerEditorView(mode: .weekly(storeID: profile.id, existing: record)) } label: {
                        HStack(spacing: 12) {
                            FeatureIcon(symbol: record.state == .confirmed ? "checkmark.circle.fill" : "pencil.circle.fill", tint: record.state == .confirmed ? AppTheme.mint : AppTheme.amber)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.weekStart.formatted(.dateTime.year().month().day()) + " This Week")
                                    .font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text("Revenue \(record.revenue?.currencyUSD ?? "not recorded") · \(record.state.title)")
                                    .font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                        }
                        .appCard(contentPadding: 13)
                    }
                    .buttonStyle(.plain)
                }
                if !months.isEmpty {
                    Text("Legacy monthly entries remain available for review. New monthly results use confirmed daily or weekly records.")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private func evaluateDailyCadenceReminder() {
        guard let profile = store.selectedProfile,
              store.recordingCadence(for: profile.id) == .daily else {
            showsCadenceReminder = false
            return
        }
        let cutoff = OperatingCalendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recent = store.dailyRecords(for: profile.id).filter { $0.state == .confirmed && $0.day >= cutoff }
        let hasStartedDaily = !store.dailyRecords(for: profile.id).isEmpty
        showsCadenceReminder = hasStartedDaily && recent.count < 3
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            FeatureIcon(symbol: "storefront.fill", tint: AppTheme.amber)
            Text("Add Your First Store").font(.title3.bold())
            Text("Add a name, category, and city. Only confirmed records are analyzed.")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button("Create Store") { createsProfile = true }
                .buttonStyle(.borderedProminent).tint(AppTheme.blue)
                .accessibilityIdentifier("operations.createProfile")
        }
        .frame(maxWidth: .infinity)
        .appCard(contentPadding: 24)
    }
}

private struct OperatingMetricCell: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.muted)
            Text(value).font(.subheadline.bold()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct OperatingTrendPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

private struct OperatingTrendRangePicker: View {
    @Binding var start: Date
    @Binding var end: Date
    let apply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Customize Business Trend Timeline")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("Both start and end dates are included in the chart; dates without records are not filled in.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            VStack(spacing: 0) {
                DatePicker("Start Date", selection: $start, in: ...Date.now, displayedComponents: .date)
                    .padding(.vertical, 12)
                Divider()
                DatePicker("End Date", selection: $end, in: ...Date.now, displayedComponents: .date)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 15)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Showing \(min(start, end).formatted(.dateTime.year().month().day())) to \(max(start, end).formatted(.dateTime.year().month().day()))")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.blue)
            Button(action: apply) {
                PrimaryActionLabel(title: "View This Period", systemImage: "chart.xyaxis.line")
            }
            .buttonStyle(PressFeedbackStyle())
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(AppBackdrop(accent: AppTheme.blue))
        .navigationTitle("Select Time")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OperationsActionTile: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            FeatureIcon(symbol: symbol, tint: tint)
            Text(title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
            Text(detail).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .appCard(contentPadding: 14)
    }
}

struct OperatingProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OperationsStore.self) private var store
    @State var profile: OperatingStoreProfile
    @State private var areaText: String
    @State private var confirmsDeletion = false
    @State private var isResolvingAdministrativeArea = false
    @State private var administrativeResolutionID = UUID()

    init(profile: OperatingStoreProfile) {
        _profile = State(initialValue: profile)
        _areaText = State(initialValue: profile.areaSquareFeet.map { String(format: "%.0f", $0) } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("Profiles stay on this device. Chats send only your selected summary.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
                fieldCard("Store Details") {
                    labeledField("Store Name", placeholder: "Legal or common name", text: $profile.name)
                    labeledField("Business Category", placeholder: "e.g., Coffee Shop or Fast Casual", text: $profile.category)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Common Categories")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                        OperatingFlowLayout(spacing: 8) {
                            ForEach(OperatingCategoryPreset.common, id: \.self) { value in
                                Button {
                                    profile.category = value
                                } label: {
                                    HStack(spacing: 5) {
                                        if profile.category == value {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(value)
                                    }
                                    .font(.caption.bold())
                                    .frame(minHeight: 32)
                                }
                                .buttonStyle(.bordered)
                                .tint(profile.category == value ? AppTheme.blue : AppTheme.muted)
                                .accessibilityValue(profile.category == value ? "Selected" : "Not Selected")
                            }
                        }
                    }
                    Text("Choose a common category or enter a more specific one.")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                    NavigationLink {
                        LocationPickerView { location in
                            acceptMapLocation(location)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            FeatureIcon(symbol: "map.fill", tint: AppTheme.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.location == nil ? "Confirm Location on Map" : "Location Verified")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.ink)
                                Text(profile.location.map { location in
                                    [location.name, location.conciseAddress]
                                        .compactMap { $0 }
                                        .joined(separator: " · ")
                                } ?? "Search, tap the map, or use a recent address")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 6)
                            if isResolvingAdministrativeArea {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(AppTheme.muted)
                            }
                        }
                        .padding(13)
                        .background(AppTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("operations.profile.mapLocation")
                    labeledField("City", placeholder: "e.g., Chicago", text: $profile.city)
                    labeledField("County or equivalent", placeholder: "e.g., Cook County or Orleans Parish", text: $profile.county)
                    labeledField("Street Address (Optional)", placeholder: "For local business research", text: $profile.address)
                    labeledField("Area (sq ft, Optional)", placeholder: "sq ft", text: $areaText, keyboard: .decimalPad)
                }
                fieldCard("Business focus") {
                    labeledField("Current Priority (Optional)", placeholder: "e.g., Improve weekday repeat visits", text: $profile.primaryGoal)
                    Text("Existing channels").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                    OperatingFlowLayout(spacing: 8) {
                        ForEach(["In-Store", "DoorDash", "Uber Eats", "Grubhub", "Website", "Email", "SMS", "TikTok", "Instagram"], id: \.self) { value in
                            Button {
                                if profile.channels.contains(value) { profile.channels.removeAll { $0 == value } }
                                else { profile.channels.append(value) }
                            } label: {
                                Label(value, systemImage: profile.channels.contains(value) ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(profile.channels.contains(value) ? AppTheme.blue : AppTheme.muted)
                        }
                    }
                }
                if profileAlreadyExists {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Label("Delete Store & Local Data", systemImage: "trash")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.red)
                }
            }
            .padding(20)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle(profile.name.isEmpty ? "New Store" : "Edit Store")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete “\(profile.name)”?",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete store profile", role: .destructive) {
                store.deleteProfile(profile.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes this store’s local logs, reviews, experiments, chats, and advisor settings. This cannot be undone.")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profile.areaSquareFeet = Double(areaText)
                    store.saveProfile(profile)
                    dismiss()
                }
                .disabled(!profile.isComplete || isResolvingAdministrativeArea)
            }
        }
    }

    private var profileAlreadyExists: Bool {
        store.workspace.profiles.contains { $0.id == profile.id }
    }

    private func acceptMapLocation(_ location: LocationCandidate) {
        profile.location = location
        profile.address = location.address ?? location.name
        let administrativeHint = location.administrativeAreaHint
        if profile.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.city = administrativeHint.city ?? profile.city
        }
        let resolutionID = UUID()
        administrativeResolutionID = resolutionID
        isResolvingAdministrativeArea = true
        Task {
            defer {
                if administrativeResolutionID == resolutionID {
                    isResolvingAdministrativeArea = false
                }
            }
            let coordinate = location.coordinate.clLocationCoordinate
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ).first,
            administrativeResolutionID == resolutionID,
            profile.location?.id == location.id else { return }
            profile.city = placemark.locality ?? placemark.administrativeArea ?? profile.city
            profile.county = placemark.subAdministrativeArea ?? profile.county
        }
    }

    private func fieldCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .appCard(contentPadding: 17)
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.bold()).foregroundStyle(AppTheme.muted)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

enum OperatingLedgerEditorMode {
    case daily(storeID: UUID, existing: DailyOperatingRecord?)
    case weekly(storeID: UUID, existing: WeeklyOperatingRecord?)
    case monthly(storeID: UUID, existing: MonthlyOperatingRecord?)

    var storeID: UUID {
        switch self { case let .daily(id, _), let .weekly(id, _), let .monthly(id, _): id }
    }
    var isWeekly: Bool { if case .weekly = self { true } else { false } }
    var isDaily: Bool { if case .daily = self { true } else { false } }
    var isMonthly: Bool { if case .monthly = self { true } else { false } }
    var title: String {
        switch self {
        case .daily: "Daily business log"
        case .weekly: "Weekly Business Pulse"
        case .monthly: "Historical monthly statements"
        }
    }
}

struct OperatingLedgerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OperationsStore.self) private var store
    @Environment(CommunityStore.self) private var communityStore
    let mode: OperatingLedgerEditorMode
    @State private var date: Date
    @State private var pendingDate: Date
    @State private var dateSelectionConfirmed: Bool
    @State private var activeDailyRecord: DailyOperatingRecord?
    @State private var activeWeeklyRecord: WeeklyOperatingRecord?
    @State private var revenue: Double?
    @State private var orders: Int?
    @State private var customerVisits: Int?
    @State private var newOptInCustomers: Int?
    @State private var repeatCustomers: Int?
    @State private var customMetrics: [OperatingCustomMetric]
    @State private var cashBalance: Double?
    @State private var costs: OperatingCostBreakdown
    @State private var note: String
    @State private var nextPeriodGoal: String
    @State private var sourceNames: [String]
    @State private var state: OperatingRecordState
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var showsFileImporter = false
    @State private var localImportError: String?

    init(mode: OperatingLedgerEditorMode) {
        self.mode = mode
        switch mode {
        case let .daily(_, existing):
            let initialDate = existing?.day ?? .now
            _date = State(initialValue: initialDate)
            _pendingDate = State(initialValue: initialDate)
            _dateSelectionConfirmed = State(initialValue: true)
            _activeDailyRecord = State(initialValue: existing)
            _activeWeeklyRecord = State(initialValue: nil)
            _revenue = State(initialValue: existing?.revenue)
            _orders = State(initialValue: existing?.orders)
            _customerVisits = State(initialValue: existing?.customerVisits)
            _newOptInCustomers = State(initialValue: existing?.newOptInCustomers)
            _repeatCustomers = State(initialValue: existing?.repeatCustomers)
            _customMetrics = State(initialValue: existing?.customMetrics ?? [])
            _cashBalance = State(initialValue: nil)
            _costs = State(initialValue: existing?.costs ?? .init())
            _note = State(initialValue: existing?.note ?? "")
            _nextPeriodGoal = State(initialValue: "")
            _sourceNames = State(initialValue: existing?.sourceDocumentNames ?? [])
            _state = State(initialValue: existing?.state ?? .draft)
        case let .weekly(_, existing):
            let calendar = OperatingCalendar.current
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            let initialDate = existing?.weekStart ?? (calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart)
            _date = State(initialValue: initialDate)
            _pendingDate = State(initialValue: initialDate)
            _dateSelectionConfirmed = State(initialValue: existing != nil)
            _activeDailyRecord = State(initialValue: nil)
            _activeWeeklyRecord = State(initialValue: existing)
            _revenue = State(initialValue: existing?.revenue)
            _orders = State(initialValue: existing?.orders)
            _customerVisits = State(initialValue: existing?.customerVisits)
            _newOptInCustomers = State(initialValue: existing?.newOptInCustomers)
            _repeatCustomers = State(initialValue: existing?.repeatCustomers)
            _customMetrics = State(initialValue: existing?.customMetrics ?? [])
            _cashBalance = State(initialValue: nil)
            _costs = State(initialValue: existing?.costs ?? .init())
            _note = State(initialValue: existing?.note ?? "")
            _nextPeriodGoal = State(initialValue: existing?.nextPeriodGoal ?? "")
            _sourceNames = State(initialValue: existing?.sourceDocumentNames ?? [])
            _state = State(initialValue: existing?.state ?? .draft)
        case let .monthly(storeID, existing):
            let initial = existing ?? MonthlyOperatingRecord(storeID: storeID, monthStart: .now)
            _date = State(initialValue: initial.monthStart)
            _pendingDate = State(initialValue: initial.monthStart)
            _dateSelectionConfirmed = State(initialValue: true)
            _activeDailyRecord = State(initialValue: nil)
            _activeWeeklyRecord = State(initialValue: nil)
            _revenue = State(initialValue: initial.revenue)
            _orders = State(initialValue: initial.orders)
            _customerVisits = State(initialValue: initial.customerVisits)
            _newOptInCustomers = State(initialValue: initial.newOptInCustomers)
            _repeatCustomers = State(initialValue: initial.repeatCustomers)
            _customMetrics = State(initialValue: initial.customMetrics ?? [])
            _cashBalance = State(initialValue: initial.cashBalance)
            _costs = State(initialValue: initial.costs)
            _note = State(initialValue: initial.note)
            _nextPeriodGoal = State(initialValue: "")
            _sourceNames = State(initialValue: initial.sourceDocumentNames)
            _state = State(initialValue: initial.state)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                ledgerHeader
                importCard
                revenueCard
                costCard
                customerCard
                customMetricsCard
                noteCard
                computedCard
                validationCard
                confirmationCard
            }
            .padding(20)
            .padding(.bottom, 92)
        }
        .background(AppBackdrop(accent: mode.isWeekly ? AppTheme.mint : AppTheme.amber))
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            coverageBar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
            } label: {
                PrimaryActionLabel(title: state == .confirmed ? "Confirm and save" : "Save as pending confirmation", systemImage: state == .confirmed ? "checkmark.shield.fill" : "square.and.arrow.down")
            }
            .buttonStyle(PressFeedbackStyle())
            .disabled((state == .confirmed && !recordValidation.canConfirm) || (mode.isWeekly && !dateSelectionConfirmed))
            .opacity((state == .confirmed && !recordValidation.canConfirm) || (mode.isWeekly && !dateSelectionConfirmed) ? 0.48 : 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.image, .pdf, .commaSeparatedText, .plainText, .spreadsheet],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFile(result) }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            OperatingCameraPicker { data in
                showsCamera = false
                guard let data else { return }
                Task { await handleCapturedPhoto(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePhoto(item) }
        }
        .onDisappear {
            store.importDraft = nil
            store.importError = nil
        }
    }

    private var ledgerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode.isWeekly {
                weeklyDateSelector
            } else {
                DatePicker(mode.isDaily ? "Log date" : "Statement month", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .onChange(of: date) { _, newDate in
                        if mode.isDaily { loadSelectedDay(newDate) }
                    }
            }
        }
        .appCard(contentPadding: 17)
    }

    private var coverageBar: some View {
        let filled = [revenue != nil, orders != nil, costs.goods != nil, costs.labor != nil, costs.rent != nil, costs.platform != nil, costs.marketing != nil, costs.utilities != nil, costs.other != nil].filter { $0 }.count
        let percent = Int((Double(filled) / 9 * 100).rounded())
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Data completeness for this period").font(.subheadline.bold())
                    Text("\(filled) / 9").font(.caption).foregroundStyle(AppTheme.muted)
                }
                ProgressView(value: Double(filled), total: 9)
                    .tint(filled == 9 ? AppTheme.mint : AppTheme.blue)
            }
            Text("\(percent)%")
                .font(.headline.bold())
                .foregroundStyle(filled == 9 ? AppTheme.mint : AppTheme.blue)
                .monospacedDigit()
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 58)
        .background(AppTheme.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(AppTheme.border, lineWidth: 0.8) }
        .shadow(color: AppTheme.navy.opacity(0.09), radius: 12, y: 5)
        .accessibilityIdentifier("operations.ledgerCoverage")
    }

    private var weeklyDateSelector: some View {
        let calendar = OperatingCalendar.current
        let latestAllowedStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        let start = calendar.dateInterval(of: .weekOfYear, for: pendingDate)?.start ?? calendar.startOfDay(for: pendingDate)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let lastWeek = store.lastCompletedWeekStart()
        let isLastWeek = calendar.isDate(start, inSameDayAs: lastWeek)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Week start · \(start.formatted(.dateTime.month().day()))").font(.headline)
                Spacer()
                Label(isLastWeek ? "Current: Last week’s data" : "Current: Selected statement period", systemImage: dateSelectionConfirmed ? "calendar.badge.checkmark" : "calendar")
                    .font(.caption.bold())
                    .foregroundStyle(dateSelectionConfirmed ? AppTheme.blue : AppTheme.amber)
            }
            DatePicker(
                "Tap a date to locate the full week",
                selection: $pendingDate,
                in: ...latestAllowedStart,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .onChange(of: pendingDate) { _, _ in dateSelectionConfirmed = false }
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: pendingDate)
                    VStack(spacing: 5) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.bold())
                        Text(day.formatted(.dateTime.day()))
                            .font(.caption.bold())
                            .monospacedDigit()
                    }
                    .foregroundStyle(selected ? .white : AppTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(selected ? AppTheme.blue : AppTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(selected ? AppTheme.blue : AppTheme.blue.opacity(0.14), lineWidth: 0.8)
                    }
                    .accessibilityLabel(day.formatted(.dateTime.year().month().day().weekday(.wide)) + (selected ? ", selected" : ", same statement period"))
                }
            }
            Text("You can only select fully completed 7-day periods. Dates with fewer than 7 days are not selectable.")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
            Button {
                confirmSelectedWeek(start)
            } label: {
                Label(dateSelectionConfirmed ? "Confirm these 7 days" : "Select these 7 days", systemImage: dateSelectionConfirmed ? "checkmark.circle.fill" : "calendar.badge.checkmark")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(dateSelectionConfirmed ? AppTheme.mint : AppTheme.blue)
            .accessibilityIdentifier("operations.confirmWeek")
        }
    }

    private func confirmSelectedWeek(_ weekStart: Date) {
        let existing = store.weeklyRecord(for: mode.storeID, containing: weekStart)
        activeWeeklyRecord = existing
        date = weekStart
        revenue = existing?.revenue
        orders = existing?.orders
        customerVisits = existing?.customerVisits
        newOptInCustomers = existing?.newOptInCustomers
        repeatCustomers = existing?.repeatCustomers
        customMetrics = existing?.customMetrics ?? []
        costs = existing?.costs ?? .init()
        note = existing?.note ?? ""
        nextPeriodGoal = existing?.nextPeriodGoal ?? ""
        sourceNames = existing?.sourceDocumentNames ?? []
        state = existing?.state ?? .draft
        dateSelectionConfirmed = true
    }

    private func loadSelectedDay(_ selectedDate: Date) {
        let existing = store.dailyRecord(for: mode.storeID, on: selectedDate)
        activeDailyRecord = existing
        revenue = existing?.revenue
        orders = existing?.orders
        customerVisits = existing?.customerVisits
        newOptInCustomers = existing?.newOptInCustomers
        repeatCustomers = existing?.repeatCustomers
        customMetrics = existing?.customMetrics ?? []
        costs = existing?.costs ?? .init()
        note = existing?.note ?? ""
        sourceNames = existing?.sourceDocumentNames ?? []
        state = existing?.state ?? .draft
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import business documents").font(.headline)
                    Text("Optional: reduces typing; you can also enter data manually").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if store.isImporting { ProgressView() }
            }
            Text("Supports images, PDF, CSV, and XLSX. Imports fill blank fields only; review before saving.")
                .font(.caption).foregroundStyle(AppTheme.muted)
            OperatingFlowLayout(spacing: 10) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showsCamera = true
                    } else {
                        localImportError = "No camera available on this device. Use “Choose Photo” in the simulator to test recognition."
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
                .buttonStyle(.bordered)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                Button { showsFileImporter = true } label: {
                    Label("Select File", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
            }
            .tint(AppTheme.blue)
            if let error = localImportError ?? store.importError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(AppTheme.red)
            }
            if let draft = store.importDraft {
                importDraftCard(draft)
            }
        }
        .appCard(contentPadding: 17)
    }

    private func importDraftCard(_ draft: OperatingImportDraft) -> some View {
        let hasImportableValues = draft.revenue != nil || draft.orders != nil || draft.costs.hasAnyValue
        return VStack(alignment: .leading, spacing: 8) {
            Label("Recognized. Please review.", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.bold()).foregroundStyle(AppTheme.amber)
            HStack(spacing: 7) {
                Text(draft.documentType)
                    .font(.caption2.bold()).foregroundStyle(AppTheme.blue)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppTheme.blue.opacity(0.09), in: Capsule())
                if let period = draft.periodLabel {
                    Text(period).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(1)
                }
            }
            Text(draft.fileName).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(1)
            Text([
                draft.revenue.map { "Revenue \($0.currencyUSD)" },
                draft.orders.map { "Orders: \($0)" },
                draft.costs.hasAnyValue ? "Recognized Costs: \(draft.costs.knownTotal.currencyUSD)" : nil,
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.bold()).foregroundStyle(AppTheme.ink)
            ForEach(draft.warnings, id: \.self) { warning in
                Text("• \(warning)").font(.caption2).foregroundStyle(AppTheme.amber)
            }
            DisclosureGroup("View Original Text") {
                Text(draft.extractedTextPreview)
                    .font(.caption2.monospaced()).foregroundStyle(AppTheme.muted)
                    .textSelection(.enabled).padding(.top, 4)
            }
            .font(.caption.bold()).tint(AppTheme.blue)
            if hasImportableValues {
                Button("Fill Blank Fields") { applyImport(draft) }
                    .font(.caption.bold()).buttonStyle(.borderedProminent).tint(AppTheme.blue)
            } else {
                Text("No safe values found. Enter them manually.")
                    .font(.caption.bold()).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .background(AppTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var revenueCard: some View {
        OperatingFormCard(title: "Revenue & Orders", caption: "Enter according to actual settlement standards.") {
            optionalMoneyField("Gross Sales", value: $revenue, previous: previousPeriod?.revenue)
            optionalIntegerField("Completed Orders", value: $orders, previous: previousPeriod?.orders)
            if mode.isMonthly {
                optionalMoneyField("Available Cash (End of Period)", value: $cashBalance)
                Text("Available cash affects runway, not profit.")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
        }
    }

    private var costCard: some View {
        OperatingFormCard(title: "Actual Costs", caption: "Do not enter only inventory costs.") {
            if let previous = previousPeriod?.costs, [previous.labor, previous.rent, previous.utilities, previous.other].contains(where: { $0 != nil }) {
                Button {
                    if costs.labor == nil { costs.labor = previous.labor }
                    if costs.rent == nil { costs.rent = previous.rent }
                    if costs.utilities == nil { costs.utilities = previous.utilities }
                    if costs.other == nil { costs.other = previous.other }
                } label: {
                    Label("Reuse Prior Fixed Costs", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered).tint(AppTheme.blue)
                Text("Fill blank costs only, then verify them against this period’s bills.")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
            optionalMoneyField("Products / Raw Materials", value: $costs.goods, previous: previousPeriod?.costs.goods)
            optionalMoneyField("Manual", value: $costs.labor, previous: previousPeriod?.costs.labor)
            optionalMoneyField("Rent Allocation", value: $costs.rent, previous: previousPeriod?.costs.rent)
            optionalMoneyField("Platform Commission and Delivery", value: $costs.platform, previous: previousPeriod?.costs.platform)
            optionalMoneyField("Promotion and Discounts", value: $costs.marketing, previous: previousPeriod?.costs.marketing)
            optionalMoneyField("Utilities", value: $costs.utilities, previous: previousPeriod?.costs.utilities)
            optionalMoneyField("Other", value: $costs.other, previous: previousPeriod?.costs.other)
        }
    }

    private var customerCard: some View {
        OperatingFormCard(title: "Customer Changes", caption: "Leave blank if unrecorded; enter 0 explicitly if the value is zero.") {
            optionalIntegerField("In-Store / Served Customers", value: $customerVisits)
            optionalIntegerField("New CRM Opt-Ins", value: $newOptInCustomers)
            optionalIntegerField("Repeat Customers", value: $repeatCustomers)
        }
    }

    private var customMetricsCard: some View {
        let profile = store.workspace.profiles.first { $0.id == mode.storeID }
        let presets = OperatingMetricPreset.suggestions(category: profile?.category ?? "", channels: profile?.channels ?? [])
        return OperatingFormCard(title: "Detailed Business Metrics", caption: "Select metrics relevant to your business type to help evaluate whether actions are truly effective.") {
            if customMetrics.isEmpty {
                Text("Examples: late-night orders, cups sold, or tables served. Record facts, not industry averages.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            let available = presets.filter { preset in !customMetrics.contains(where: { $0.name == preset.name }) }
            if !available.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(available) { preset in
                            Button {
                                customMetrics.append(preset)
                            } label: {
                                Label(preset.name, systemImage: "plus")
                            }
                            .font(.caption.bold()).buttonStyle(.bordered).tint(AppTheme.blue)
                        }
                    }
                }
            }
            ForEach(Array(customMetrics.enumerated()), id: \.element.id) { index, _ in
                HStack(spacing: 8) {
                    TextField("Metric Name", text: $customMetrics[index].name)
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    TextField("Value", value: $customMetrics[index].value, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 76)
                    TextField("Unit", text: $customMetrics[index].unit)
                        .multilineTextAlignment(.center).frame(width: 46)
                    Button(role: .destructive) { customMetrics.remove(at: index) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Delete \(customMetrics[index].name)")
                }
                .padding(10)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if customMetrics.count < 12 {
                Button {
                    customMetrics.append(OperatingCustomMetric(name: "", unit: "Times"))
                } label: {
                    Label("Add Other Metrics", systemImage: "plus.circle")
                }
                .font(.caption.bold()).buttonStyle(.plain).foregroundStyle(AppTheme.blue)
            }
        }
    }

    private var noteCard: some View {
        OperatingFormCard(title: "What Happened This Period?", caption: "Weather, promotions, closures, price increases, staffing changes, etc.") {
            TextEditor(text: $note)
                .frame(minHeight: 100)
                .padding(9)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if mode.isWeekly {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label("Next Week’s Goals", systemImage: "scope")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.blue)
                    TextField("Example: Increase weekday dinner orders by 10% without increasing marketing spend.", text: $nextPeriodGoal, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .padding(11)
                        .background(AppTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("State goals as verifiable outcomes: Metric + Target Value + Cost Constraint.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    private var computedCard: some View {
        let metrics = OperatingMetrics(
            revenue: revenue,
            orders: orders,
            repeatCustomers: repeatCustomers,
            customerVisits: customerVisits,
            costs: costs
        )
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Recalculate Formula", caption: "Use only the data entered above.")
            HStack(spacing: 10) {
                OperatingMetricCell(title: "Operating Profit", value: metrics.operatingProfit?.currencyUSD ?? calculationMissingLabel, tint: metrics.operatingProfit.map { $0 >= 0 ? AppTheme.mint : AppTheme.red } ?? AppTheme.muted)
                OperatingMetricCell(title: "Profit Margin", value: metrics.operatingMargin.map { $0.percentText } ?? calculationMissingLabel, tint: AppTheme.blue)
                OperatingMetricCell(title: "Average Order Value", value: metrics.averageTicket?.currencyUSD ?? "Pending Orders", tint: AppTheme.amber)
            }
        }
        .appCard(contentPadding: 17)
    }

    private var recordValidation: OperatingRecordValidation {
        let base = OperatingRecordValidation.evaluate(
            revenue: revenue,
            orders: orders,
            customerVisits: customerVisits,
            newOptInCustomers: newOptInCustomers,
            repeatCustomers: repeatCustomers,
            costs: costs,
            note: note,
            customMetrics: customMetrics,
            periodStart: date
        )
        let audit = OperatingPeriodComparisonAudit.evaluate(
            revenue: revenue,
            orders: orders,
            previousRevenue: previousPeriod?.revenue,
            previousOrders: previousPeriod?.orders
        )
        return OperatingRecordValidation(blockers: base.blockers, warnings: base.warnings + audit.warnings)
    }

    private var previousPeriod: (revenue: Double?, orders: Int?, costs: OperatingCostBreakdown)? {
        switch mode {
        case let .daily(storeID, existing):
            return store.dailyRecords(for: storeID)
                .first { $0.state == .confirmed && $0.id != (activeDailyRecord?.id ?? existing?.id) && $0.day < date }
                .map { ($0.revenue, $0.orders, $0.costs) }
        case let .weekly(storeID, existing):
            return store.weeklyRecords(for: storeID)
                .first { $0.state == .confirmed && $0.id != (activeWeeklyRecord?.id ?? existing?.id) && $0.weekStart < date }
                .map { ($0.revenue, $0.orders, $0.costs) }
        case let .monthly(storeID, existing):
            return store.monthlyRecords(for: storeID)
                .first { $0.state == .confirmed && $0.id != existing?.id && $0.monthStart < date }
                .map { ($0.revenue, $0.orders, $0.costs) }
        }
    }

    private var calculationMissingLabel: String {
        if revenue == nil { return "Sales pending entry" }
        if !costs.isComplete { return "Missing costs" }
        return "Calculation unavailable"
    }

    @ViewBuilder
    private var validationCard: some View {
        let validation = recordValidation
        if !validation.blockers.isEmpty || !validation.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    validation.blockers.isEmpty ? "Please double-check before saving" : "Cannot be marked as confirmed yet",
                    systemImage: validation.blockers.isEmpty ? "exclamationmark.triangle.fill" : "xmark.shield.fill"
                )
                .font(.headline)
                .foregroundStyle(validation.blockers.isEmpty ? AppTheme.amber : AppTheme.red)
                ForEach(validation.blockers, id: \.self) { value in
                    Text("• \(value)").font(.caption).foregroundStyle(AppTheme.red)
                }
                ForEach(validation.warnings, id: \.self) { value in
                    Text("• \(value)").font(.caption).foregroundStyle(AppTheme.amber)
                }
                if !validation.blockers.isEmpty {
                    Text("You can still save it as “Pending Confirmation” and let Operations Advisor use it once the data is complete.")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            .appCard(contentPadding: 16)
        }
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Record Status", selection: $state) {
                Text("Pending Confirmation").tag(OperatingRecordState.draft)
                Text("I have verified").tag(OperatingRecordState.confirmed)
            }
            .pickerStyle(.segmented)
            Text(state == .confirmed ? "Once confirmed, the data will be included in Operations Advisor’s long-term context." : "Records marked as pending confirmation are saved locally but are not used for business analysis.")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 17)
    }

    private func optionalMoneyField(_ title: String, value: Binding<Double?>, previous: Double? = nil) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text("$").foregroundStyle(AppTheme.muted)
            TextField(
                "",
                value: value,
                format: .number.precision(.fractionLength(0...2)),
                prompt: Text(previous.map { "Previous \($0.formatted(.number.precision(.fractionLength(0...2))))" } ?? "Not Provided")
                    .foregroundStyle(AppTheme.muted.opacity(0.72))
            )
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 130)
        }
        .padding(.vertical, 4)
    }

    private func optionalIntegerField(_ title: String, value: Binding<Int?>, previous: Int? = nil) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            TextField(
                "",
                value: value,
                format: .number,
                prompt: Text(previous.map { "Previous \($0)" } ?? "Not Provided")
                    .foregroundStyle(AppTheme.muted.opacity(0.72))
            )
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 130)
        }
        .padding(.vertical, 4)
    }

    private func handlePhoto(_ item: PhotosPickerItem) async {
        localImportError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw OperatingDocumentError.unreadable }
            let text = try await OperatingDocumentProcessor.recognize(imageData: data)
            await store.parseDocument(fileName: "Selected business receipt photos", kind: .recognizedText(text: text, mimeType: "image/jpeg"))
        } catch {
            localImportError = error.localizedDescription
        }
    }

    private func handleCapturedPhoto(_ data: Data) async {
        localImportError = nil
        do {
            let text = try await OperatingDocumentProcessor.recognize(imageData: data)
            await store.parseDocument(fileName: "Captured business receipts", kind: .recognizedText(text: text, mimeType: "image/jpeg"))
        } catch {
            localImportError = error.localizedDescription
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) async {
        localImportError = nil
        do {
            guard let url = try result.get().first else { return }
            let kind = try await OperatingDocumentProcessor.read(url: url)
            await store.parseDocument(fileName: url.lastPathComponent, kind: kind)
        } catch {
            localImportError = error.localizedDescription
        }
    }

    private func applyImport(_ draft: OperatingImportDraft) {
        var preservedExistingValue = false
        if let value = draft.revenue {
            if revenue == nil { revenue = value } else { preservedExistingValue = true }
        }
        if let value = draft.orders {
            if orders == nil { orders = value } else { preservedExistingValue = true }
        }
        mergeImportedCost(draft.costs.goods, into: &costs.goods, preservedExistingValue: &preservedExistingValue)
        mergeImportedCost(draft.costs.labor, into: &costs.labor, preservedExistingValue: &preservedExistingValue)
        mergeImportedCost(draft.costs.rent, into: &costs.rent, preservedExistingValue: &preservedExistingValue)
        mergeImportedCost(draft.costs.platform, into: &costs.platform, preservedExistingValue: &preservedExistingValue)
        mergeImportedCost(draft.costs.marketing, into: &costs.marketing, preservedExistingValue: &preservedExistingValue)
        mergeImportedCost(draft.costs.utilities, into: &costs.utilities, preservedExistingValue: &preservedExistingValue)
        mergeImportedCost(draft.costs.other, into: &costs.other, preservedExistingValue: &preservedExistingValue)
        if !sourceNames.contains(draft.fileName) { sourceNames.append(draft.fileName) }
        if preservedExistingValue {
            localImportError = "Existing amounts in the form were not automatically overwritten. Please manually verify against the receipts whether to add or replace them."
        }
        store.importDraft = nil
    }

    private func mergeImportedCost(_ imported: Double?, into existing: inout Double?, preservedExistingValue: inout Bool) {
        guard let imported else { return }
        if existing == nil { existing = imported } else { preservedExistingValue = true }
    }

    private func save() {
        var savedRecordID: UUID?
        switch mode {
        case let .daily(storeID, existing):
            let selected = activeDailyRecord ?? existing
            let recordID = selected?.id ?? UUID()
            savedRecordID = recordID
            store.saveDaily(
                DailyOperatingRecord(
                    id: recordID, storeID: storeID, day: date,
                    revenue: revenue, orders: orders,
                    customerVisits: customerVisits,
                    newOptInCustomers: newOptInCustomers,
                    repeatCustomers: repeatCustomers,
                    customMetrics: customMetrics.isEmpty ? nil : customMetrics,
                    costs: costs, note: note, sourceDocumentNames: sourceNames, state: state,
                    createdAt: selected?.createdAt ?? .now
                )
            )
        case let .weekly(storeID, existing):
            let selected = activeWeeklyRecord ?? existing
            let recordID = selected?.id ?? UUID()
            savedRecordID = recordID
            store.saveWeekly(
                WeeklyOperatingRecord(
                    id: recordID, storeID: storeID, weekStart: date,
                    revenue: revenue, orders: orders,
                    customerVisits: customerVisits,
                    newOptInCustomers: newOptInCustomers,
                    repeatCustomers: repeatCustomers,
                    customMetrics: customMetrics.isEmpty ? nil : customMetrics,
                    costs: costs, note: note,
                    nextPeriodGoal: nextPeriodGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nextPeriodGoal,
                    sourceDocumentNames: sourceNames, state: state,
                    createdAt: selected?.createdAt ?? .now
                )
            )
        case let .monthly(storeID, existing):
            let recordID = existing?.id ?? UUID()
            savedRecordID = recordID
            store.saveMonthly(
                MonthlyOperatingRecord(
                    id: recordID, storeID: storeID, monthStart: date,
                    revenue: revenue, orders: orders,
                    customerVisits: customerVisits,
                    newOptInCustomers: newOptInCustomers,
                    repeatCustomers: repeatCustomers,
                    customMetrics: customMetrics.isEmpty ? nil : customMetrics,
                    costs: costs, cashBalance: cashBalance, note: note, sourceDocumentNames: sourceNames, state: state,
                    createdAt: existing?.createdAt ?? .now
                )
            )
        }
        if state == .confirmed, let savedRecordID {
            Task {
                await communityStore.recordCreditEvent(
                    kind: "operating_record_confirmed",
                    eventID: savedRecordID.uuidString
                )
            }
        }
        dismiss()
    }
}

private struct OperatingCameraPicker: UIViewControllerRepresentable {
    let completion: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (Data?) -> Void

        init(completion: @escaping (Data?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.88)
            completion(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}

private struct OperatingFormCard<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content
    init(title: String, caption: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title, caption: caption)
            content
        }
        .appCard(contentPadding: 17)
    }
}

struct OperatingReminderView: View {
    @Environment(OperationsStore.self) private var store
    @State private var settings: OperatingReminderSettings
    @State private var isSaving = false
    @State private var showsSaveResult = false
    @State private var saveResultTitle = "Saved"
    @State private var saveResultDetail = ""

    init() {
        _settings = State(initialValue: OperatingReminderSettings())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                reminderHero
                dailyReminderCard
                weeklyReminderCard
                monthlyReminderCard
                HStack(alignment: .top, spacing: 12) {
                    FeatureIcon(symbol: "lock.shield.fill", tint: AppTheme.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hide business details on lock screen")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text("Notifications show only “Record or Review,” never store or financial data. Disable them in Settings.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .appCard(contentPadding: 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Proactive Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { settings = store.reminderSettings }
        .safeAreaInset(edge: .bottom) {
            Button {
                save()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isSaving ? "Saving" : "Save Reminder Settings")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    LinearGradient(
                        colors: [AppTheme.deepClay, AppTheme.amber],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
            }
            .buttonStyle(PressFeedbackStyle())
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("operations.reminder.save")
        }
        .alert(saveResultTitle, isPresented: $showsSaveResult) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(saveResultDetail)
        }
    }

    private var reminderHero: some View {
        HStack(alignment: .top, spacing: 15) {
            ZStack {
                Circle().fill(.white.opacity(0.14))
                Image(systemName: "bell.badge.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text("Keep reviews on schedule")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Daily reminders start on. Weekly and monthly reminders are optional.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(19)
        .background(
            LinearGradient(
                colors: [AppTheme.deepClay, AppTheme.amber.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: AppTheme.deepClay.opacity(0.14), radius: 18, y: 8)
    }

    private var dailyReminderCard: some View {
        reminderCard(
            title: "Daily business log",
            detail: "Remind me to verify sales, orders, and actual costs at day’s end",
            symbol: "sunset.fill",
            tint: AppTheme.amber,
            isEnabled: $settings.dailyEnabled
        ) {
            hourPicker(title: "Reminder Time", hour: $settings.dailyHour)
        }
    }

    private var weeklyReminderCard: some View {
        reminderCard(
            title: "Weekly Business Pulse",
            detail: "Remind me to review this week’s changes and confirm next week’s actions with Operations Advisor",
            symbol: "waveform.path.ecg",
            tint: AppTheme.blue,
            isEnabled: $settings.weeklyEnabled
        ) {
            settingRow("Reminder Day") {
                Picker("Reminder Day", selection: $settings.weeklyWeekday) {
                    ForEach(Array(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"].enumerated()), id: \.offset) { index, value in
                        Text(value).tag(index + 1)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            hourPicker(title: "Reminder Time", hour: $settings.weeklyHour)
        }
    }

    private var monthlyReminderCard: some View {
        reminderCard(
            title: "Monthly Business Review",
            detail: "Remind me to review system-summarized month-over-month, year-over-year, and profit changes",
            symbol: "calendar.badge.clock",
            tint: AppTheme.mint,
            isEnabled: $settings.monthlyEnabled
        ) {
            settingRow("Day of Month") {
                Picker("Day of Month", selection: $settings.monthlyDay) {
                    ForEach(1...28, id: \.self) { Text("\($0)th").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            hourPicker(title: "Reminder Time", hour: $settings.monthlyHour)
        }
    }

    private func reminderCard<Content: View>(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        isEnabled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                FeatureIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                    Text(detail).font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .tint(tint)
                    .accessibilityLabel(title == "Daily business log" ? "Daily Reminder" : "\(title) Reminder")
            }
            if isEnabled.wrappedValue {
                Divider()
                content()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEnabled.wrappedValue)
        .appCard(contentPadding: 17)
    }

    private func hourPicker(title: String, hour: Binding<Int>) -> some View {
        settingRow(title) {
            Picker(title, selection: hour) {
                ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(AppTheme.ink)
            Spacer()
            content()
                .font(.subheadline.bold())
                .tint(AppTheme.blue)
        }
        .frame(minHeight: 40)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await store.updateReminderSettings(settings)
            saveResultDetail = store.reminderNotice ?? "Reminder settings saved."
            saveResultTitle = saveResultDetail.contains("Notifications not allowed") ? "Settings saved, but notifications are disabled" : "Saved"
            isSaving = false
            showsSaveResult = true
        }
    }
}

enum OperatingAdvisorFocus: String, CaseIterable, Identifiable {
    case weeklyReview
    case monthlyReview
    case cashflow
    case nextWeek
    case acquisition
    case ownedAudience
    case retention
    case cost
    case inventory
    case staffing
    case pricing

    var id: String { rawValue }
    static var actionCases: [Self] { [.cashflow, .nextWeek, .acquisition, .ownedAudience, .retention, .cost, .inventory, .staffing, .pricing] }
    var reviewKind: OperatingReviewKind? {
        switch self {
        case .weeklyReview: .weekly
        case .monthlyReview: .monthly
        default: nil
        }
    }
    var title: String {
        switch self {
        case .weeklyReview: "This Week’s Review"
        case .monthlyReview: "Last Month Review"
        case .cashflow: "Transaction History"
        case .nextWeek: "Next Week’s Plan"
        case .acquisition: "Customer Acquisition & Promotion"
        case .ownedAudience: "Owned Audience"
        case .retention: "Customer Retention"
        case .cost: "Cost Reduction & Profit Growth"
        case .inventory: "Inventory Shrinkage"
        case .staffing: "Staff Scheduling"
        case .pricing: "Pricing & Bundles"
        }
    }
    var caption: String {
        switch self {
        case .weeklyReview: "Identify Changes & Next Steps"
        case .monthlyReview: "YoY/MoM Analysis & Next Month Plan"
        case .cashflow: "Revenue, Channels, and Anomalies"
        case .nextWeek: "Top Three Priorities"
        case .acquisition: "Budget, Conversion, and Stop-Loss Criteria"
        case .ownedAudience: "Consent, CRM Opt-Ins, and Retention"
        case .retention: "Win-Back, Complaints, and Loyalty"
        case .cost: "Ingredients, Labor, Platforms, and Rent"
        case .inventory: "Procurement, Turnover, and Write-offs"
        case .staffing: "Peak/Off-Peak Traffic & Labor Efficiency"
        case .pricing: "Avg. Order Value, Gross Margin, and Product Mix"
        }
    }
    var symbol: String {
        switch self {
        case .weeklyReview, .monthlyReview, .cashflow: "chart.line.uptrend.xyaxis"
        case .nextWeek: "list.bullet.clipboard.fill"
        case .acquisition: "megaphone.fill"
        case .ownedAudience: "person.2.wave.2.fill"
        case .retention: "heart.text.square.fill"
        case .cost: "scalemass.fill"
        case .inventory: "shippingbox.fill"
        case .staffing: "person.3.fill"
        case .pricing: "tag.fill"
        }
    }
    var tint: Color {
        switch self {
        case .weeklyReview, .monthlyReview, .cashflow: AppTheme.blue
        case .nextWeek, .acquisition, .pricing: AppTheme.amber
        case .ownedAudience, .retention: AppTheme.periwinkle
        case .cost, .inventory, .staffing: AppTheme.mint
        }
    }
    var suggestedQuestions: [String] {
        switch self {
        case .weeklyReview:
            ["Based on last week’s transactions, costs, and customer changes, identify the two most critical shifts.", "Which conclusions are data-backed, and which need my input?", "Condense next week’s actions into three verifiable steps."]
        case .monthlyReview:
            ["Comparing the last two months, what primarily drove profit changes?", "Which growth from last month is sustainable, and which was likely just promotional fluctuation?", "Please provide next month’s targets, budget caps, and stop-loss criteria."]
        case .cashflow:
            ["Break down recent transaction changes by foot traffic, average order value, or channel.", "Check for accounting discrepancies due to double-counting, refunds, or prepaid credits.", "Which revenue channel deserves continued investment?"]
        case .nextWeek:
            ["Based on current data, list the top three priorities for next week.", "What metrics and stop-loss criteria should be monitored for each task?", "Which tasks are not worth doing right now?"]
        case .acquisition:
            ["Which acquisition method should I prioritize, and what is the budget cap?", "How should I evaluate promotions by breaking down impressions, store visits, orders, and repeat purchases?", "Help me design a one-week verifiable new-customer acquisition experiment."]
        case .ownedAudience:
            ["Why would customers join my private channel, and what value should I offer?", "How can I segment outreach without disturbing customers?", "How do I measure true store visits and repeat purchases from private channel activities?"]
        case .retention:
            ["Which customers should be prioritized for win-back campaigns?", "How to win back repeat business after resolving complaints?", "Give me a customer retention strategy that doesn’t rely on discounts."]
        case .cost:
            ["Which cost should I cut first without hurting the customer experience?", "Analyze fixed costs separately from variable costs.", "Help me set up a one-week cost-reduction experiment with stop conditions."]
        case .inventory:
            ["How do I spot anomalies in procurement, inventory, and shrinkage?", "Which items should have reduced inventory or faster turnover?", "Help me design a daily inventory counting procedure."]
        case .staffing:
            ["Based on peak and off-peak hours, where might staffing be too heavy or insufficient?", "How can I use labor productivity to decide if shift adjustments are needed?", "How to avoid a drop in service quality when adjusting schedules?"]
        case .pricing:
            ["Do the current average order value and gross margin support existing pricing?", "Which bundles could raise average order value without eroding gross margin?", "Help me design a pricing experiment that doesn’t rely on deep discounts."]
        }
    }
}

struct OperatingGrowthPlaybookView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let profile: OperatingStoreProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ask Operations Advisor", systemImage: "sparkles")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Text("Operations Advisor will first review the confirmed operational records in \"\(profile.name)\", then suggest the most relevant questions for you to ask next.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.76))
                    NavigationLink { OperatingAdvisorConversationView(profile: profile) } label: {
                        Label("Start Conversation", systemImage: "arrow.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.navy)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(PressFeedbackStyle())
                }
                .padding(18)
                .background(
                    LinearGradient(colors: [AppTheme.deepClay, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )

                SectionTitle("What do you want to solve?", caption: "Choose a focus for tailored questions")
                LazyVGrid(
                    columns: dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 11
                ) {
                    ForEach(OperatingAdvisorFocus.actionCases) { focus in
                        NavigationLink { OperatingAdvisorConversationView(profile: profile, focus: focus) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                FeatureIcon(symbol: focus.symbol, tint: focus.tint)
                                Text(focus.title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text(focus.caption)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 128,
                                alignment: .leading
                            )
                            .appCard(contentPadding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Ask Operations Advisor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OperatingExperimentListView: View {
    @Environment(OperationsStore.self) private var store
    let profile: OperatingStoreProfile
    @State private var editing: OperatingExperiment?
    @State private var creates = false

    var body: some View {
        List {
            Section {
                Text("Test one hypothesis at a time. Set a metric and stop conditions before starting.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Section("Action Experiments") {
                ForEach(store.experiments(for: profile.id)) { item in
                    Button { editing = item } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(item.title).font(.headline); Spacer(); Text(item.state.title).font(.caption.bold()).foregroundStyle(AppTheme.blue) }
                            Text([item.metric, item.target].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(AppTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { store.deleteExperiments(at: $0, for: profile.id) }
                if store.experiments(for: profile.id).isEmpty {
                    ContentUnavailableView("No active experiments yet", systemImage: "checkmark.seal", description: Text("Start with a specific question, such as “Can weekday dinner bundles increase average order value?”"))
                }
            }
        }
        .navigationTitle("Action Experiments")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { creates = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $creates) { NavigationStack { OperatingExperimentEditorView(experiment: OperatingExperiment(storeID: profile.id, title: "")) } }
        .sheet(item: $editing) { item in NavigationStack { OperatingExperimentEditorView(experiment: item) } }
    }
}

struct OperatingExperimentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OperationsStore.self) private var store
    @State var experiment: OperatingExperiment
    var body: some View {
        Form {
            Section("What to Validate") {
                TextField("Experiment Name", text: $experiment.title)
                TextField("Hypothesis: What action will drive what change", text: $experiment.hypothesis, axis: .vertical)
            }
            Section("How to Judge") {
                TextField("Primary Metric, e.g., Weekday Dinner Orders", text: $experiment.metric)
                TextField("Goals & Stop Conditions", text: $experiment.target, axis: .vertical)
                DatePicker("Start", selection: $experiment.startsAt, displayedComponents: .date)
                DatePicker("End", selection: $experiment.endsAt, in: experiment.startsAt..., displayedComponents: .date)
            }
            Section("Status & Results") {
                Picker("Status", selection: $experiment.state) { ForEach(OperatingExperimentState.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField("Fill in observations after completion", text: $experiment.result, axis: .vertical)
            }
            if !canSave {
                Section {
                    Text("Add a name, hypothesis, primary metric, goal, and stop conditions.")
                        .font(.caption).foregroundStyle(AppTheme.amber)
                }
            }
        }
        .navigationTitle(experiment.title.isEmpty ? "New Action Experiment" : "Edit Action Experiment")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.saveExperiment(experiment); dismiss() }
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        [experiment.title, experiment.hypothesis, experiment.metric, experiment.target]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct OperatingMemoryView: View {
    @Environment(OperationsStore.self) private var store
    let profile: OperatingStoreProfile
    @State private var editsMemory = false
    var body: some View {
        let memory = store.memory(for: profile.id)
        List {
            Section("Goals for the Operations Advisor") {
                if memory.confirmedGoals.isEmpty { Text("Not Set").foregroundStyle(AppTheme.muted) }
                ForEach(memory.confirmedGoals, id: \.self) { Text($0) }
            }
            Section("Boundaries the Operations Advisor Must Not Cross") {
                if memory.confirmedConstraints.isEmpty { Text("Not Set").foregroundStyle(AppTheme.muted) }
                ForEach(memory.confirmedConstraints, id: \.self) { Text($0) }
            }
            Section {
                Text("Optional. Revenue, orders, and costs come only from confirmed records; chat cannot alter them.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .navigationTitle("Advisor Principles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editsMemory = true }
            }
        }
        .sheet(isPresented: $editsMemory) {
            NavigationStack { OperatingMemoryEditorView(profile: profile) }
        }
    }
}

private struct OperatingMemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(OperationsStore.self) private var store
    let profile: OperatingStoreProfile
    @State private var goals = ""
    @State private var constraints = ""

    var body: some View {
        Form {
            Section("Business Goals") {
                TextEditor(text: $goals).frame(minHeight: 110)
                Text("One per line, e.g., Increase weekday repeat purchase rate to 30% within three months.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Section("Operating Constraints") {
                TextEditor(text: $constraints).frame(minHeight: 110)
                Text("List only confirmed boundaries, such as budget caps, inability to extend operating hours, or staffing limits.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Section {
                Text("These rules guide later advice. Suggestions cannot change them automatically.")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .navigationTitle("Edit Advisor Principles")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let memory = store.memory(for: profile.id)
            goals = memory.confirmedGoals.joined(separator: "\n")
            constraints = memory.confirmedConstraints.joined(separator: "\n")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var memory = store.memory(for: profile.id)
                    memory.confirmedGoals = lines(goals)
                    memory.confirmedConstraints = lines(constraints)
                    store.updateMemory(memory, for: profile.id)
                    dismiss()
                }
            }
        }
    }

    private func lines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct OperatingAdvisorHomeView: View {
    @Environment(OperationsStore.self) private var store
    @State private var createsProfile = false
    @State private var clearsConversationFor: OperatingStoreProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    AgentOrb(size: 58, isActive: store.isResponding)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Operations Advisor").font(.title2.bold()).foregroundStyle(.white)
                        Text("Uses confirmed records, goals, and experiments. Checks local public data when needed.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.78))
                    }
                }
                .padding(20)
                .background(LinearGradient(colors: [AppTheme.deepClay, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                if !store.serviceStatus.isReady {
                    ServiceStatusCard(status: store.serviceStatus, serviceName: "Operations Advisor", detail: store.serviceStatus.detail) {
                        Task { await store.refreshServiceStatus() }
                    }
                }
                SectionTitle("Choose a Store", caption: "One chat per store")
                if store.workspace.profiles.isEmpty {
                    VStack(spacing: 12) {
                        Text("No Store Profile").font(.headline)
                        Text("Create a profile, then add real operating records.")
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                        Button("Create Profile") { createsProfile = true }
                            .buttonStyle(.borderedProminent).tint(AppTheme.blue)
                    }
                    .frame(maxWidth: .infinity).appCard(contentPadding: 22)
                } else {
                    ForEach(store.workspace.profiles.sorted { lhs, rhs in
                        store.conversation(for: lhs.id).updatedAt > store.conversation(for: rhs.id).updatedAt
                    }) { profile in
                        NavigationLink { OperatingAdvisorConversationView(profile: profile) } label: {
                            OperatingAdvisorThreadRow(profile: profile)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("operations.advisor.thread.\(profile.id.uuidString)")
                        .contextMenu {
                            if !store.conversation(for: profile.id).messages.isEmpty {
                                Button("Clear This Business Chat", systemImage: "trash", role: .destructive) {
                                    clearsConversationFor = profile
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .refreshable { await store.refreshServiceStatus() }
        .sheet(isPresented: $createsProfile) { NavigationStack { OperatingProfileEditorView(profile: OperatingStoreProfile()) } }
        .confirmationDialog(
            "Clear the business chat for \"\(clearsConversationFor?.name ?? "")\"?",
            isPresented: Binding(
                get: { clearsConversationFor != nil },
                set: { if !$0 { clearsConversationFor = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear Chat Only", role: .destructive) {
                if let profile = clearsConversationFor { store.clearConversation(for: profile.id) }
                clearsConversationFor = nil
            }
            Button("Clear Chat and Summary", role: .destructive) {
                if let profile = clearsConversationFor { store.clearConversation(for: profile.id, alsoClearSummary: true) }
                clearsConversationFor = nil
            }
            Button("Cancel", role: .cancel) { clearsConversationFor = nil }
        } message: {
            Text("Store profile, daily/weekly records, review reports, and advisor principles will not be deleted.")
        }
        .task { await store.refreshServiceStatus() }
    }
}

private struct OperatingAdvisorThreadRow: View {
    @Environment(OperationsStore.self) private var store
    let profile: OperatingStoreProfile
    var body: some View {
        let conversation = store.conversation(for: profile.id)
        HStack(spacing: 13) {
            FeatureIcon(symbol: "storefront.fill", tint: AppTheme.amber)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(profile.name).font(.headline).foregroundStyle(AppTheme.ink); Spacer(); Text(conversation.messages.isEmpty ? "New chat" : conversation.updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(AppTheme.muted) }
                Text([profile.category, profile.locationLabel].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.bold()).foregroundStyle(AppTheme.blue)
                Text(conversation.messages.last?.compactPreview ?? "Start Questions from This Week's Business Pulse").font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 14)
    }
}

struct OperatingReviewHistoryView: View {
    @Environment(OperationsStore.self) private var store
    let profile: OperatingStoreProfile

    var body: some View {
        List {
            let reports = store.reviewReports(for: profile.id)
            if reports.isEmpty {
                ContentUnavailableView(
                    "No Archived Reviews",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Complete a weekly or monthly review chat, then tap \"End Review and Generate Report.\"")
                )
            } else {
                ForEach(reports) { report in
                    NavigationLink { OperatingReviewDetailView(report: report) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(report.kind.title).font(.headline)
                                Spacer()
                                Text(report.generatedAt.formatted(.dateTime.month().day()))
                                    .font(.caption).foregroundStyle(AppTheme.muted)
                            }
                            Text("\(report.periodStart.formatted(.dateTime.year().month().day()))—\(report.periodEnd.formatted(.dateTime.month().day()))")
                                .font(.caption.bold()).foregroundStyle(AppTheme.blue)
                            Text(report.factualSummary).font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Review Report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OperatingReviewDetailView: View {
    let report: OperatingReviewReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.kind.title).font(.title2.bold()).foregroundStyle(.white)
                    Text("\(report.periodStart.formatted(.dateTime.year().month().day()))—\(report.periodEnd.formatted(.dateTime.year().month().day()))")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.78))
                    Text("Data covers period \(report.sourceRecordCount) / \(report.expectedRecordCount)")
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.86))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(LinearGradient(colors: [AppTheme.deepClay, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))

                HStack(spacing: 10) {
                    OperatingMetricCell(title: "Gross Sales", value: report.metrics.revenue?.currencyUSD ?? "Incomplete", tint: AppTheme.blue)
                    OperatingMetricCell(title: "Operating Profit", value: report.metrics.operatingProfit?.currencyUSD ?? "Incomplete", tint: AppTheme.mint)
                    OperatingMetricCell(title: "Average Order Value", value: report.metrics.averageTicket?.currencyUSD ?? "Incomplete", tint: AppTheme.amber)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Summary").font(.headline)
                    Text(report.factualSummary).font(.subheadline).foregroundStyle(AppTheme.ink)
                }
                .appCard(contentPadding: 17)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Operations Advisor Conclusions").font(.headline)
                    Text(report.advisorConclusion.isEmpty ? "No archivable advisor conclusions were formed in this chat." : report.advisorConclusion)
                        .font(.subheadline).foregroundStyle(report.advisorConclusion.isEmpty ? AppTheme.muted : AppTheme.ink)
                        .textSelection(.enabled)
                }
                .appCard(contentPadding: 17)
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(AppBackdrop(accent: AppTheme.blue))
        .navigationTitle("Read Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OperatingAdvisorConversationView: View {
    @Environment(OperationsStore.self) private var store
    @Environment(CommunityStore.self) private var communityStore
    @Environment(MessagingStore.self) private var messagingStore
    let profile: OperatingStoreProfile
    var focus: OperatingAdvisorFocus? = nil
    @State private var input = ""
    @State private var showsClearDialog = false
    @State private var showsGroupContextPicker = false
    @State private var showsFinishReview = false
    @State private var finishedReport: OperatingReviewReport?
    @State private var reviewSessionStartCount: Int?
    @State private var isAuthorizingSpend = false
    @FocusState private var focused: Bool

    private var conversation: OperatingConversation { store.conversation(for: profile.id) }
    private var runningHere: Bool { store.isResponding && store.activeAdvisorStoreID == profile.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    contextCard
                    SharedGroupContextCard(
                        contexts: conversation.sharedGroupContexts,
                        onAdd: { showsGroupContextPicker = true },
                        onRemove: { store.removeGroupContext(groupID: $0, from: profile.id) }
                    )
                    if let focus { focusSuggestionCard(focus) }
                    else if conversation.messages.isEmpty { welcomeCard }
                    ForEach(conversation.messages) { message in
                        AdvisorMessageBubble(message: message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("operations-advisor-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("operations-advisor-bottom", anchor: .bottom) }
            }
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle(focus?.title ?? profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if reviewSessionStartCount == nil { reviewSessionStartCount = conversation.messages.count }
        }
        .task { await messagingStore.refresh(token: communityStore.messagingToken) }
        .sheet(isPresented: $showsGroupContextPicker) {
            NavigationStack {
                PersonalGroupHistoryPicker { context in
                    store.importGroupContext(context, into: profile.id)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $finishedReport) { report in
            NavigationStack { OperatingReviewDetailView(report: report) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        OperatingMemoryView(profile: profile)
                    } label: {
                        Label("View Advisor Principles", systemImage: "list.bullet.clipboard.fill")
                    }
                    if !conversation.messages.isEmpty {
                        Button("Clear Current Chat", systemImage: "trash", role: .destructive) {
                            showsClearDialog = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Clear current business chat?", isPresented: $showsClearDialog, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive) { store.clearConversation(for: profile.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps records and advisor rules; clears this store’s chat only.")
        }
        .confirmationDialog("Finish this review and save a report?", isPresented: $showsFinishReview, titleVisibility: .visible) {
            Button("End and Generate Report") { finishReview() }
            Button("Continue Chat", role: .cancel) {}
        } message: {
            Text("Saves this period’s recalculable data and latest advisor conclusion.")
        }
        .safeAreaInset(edge: .bottom) { bottomPanel }
    }

    private var contextCard: some View {
        let readiness = store.dataReadiness(for: profile.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack { Label(profile.category, systemImage: "storefront.fill").font(.headline); Spacer(); NavigationLink("Advisor Principles") { OperatingMemoryView(profile: profile) }.font(.caption.bold()) }
            Text(profile.locationLabel).font(.caption).foregroundStyle(AppTheme.muted)
            let confirmedWeeks = store.effectiveWeeklyRecords(for: profile.id).filter { $0.state == .confirmed }.count
            let confirmedDays = store.dailyRecords(for: profile.id).filter { $0.state == .confirmed }.count
            Text("Confirmed \(confirmedDays) daily records · \(confirmedWeeks) weekly pulses")
                .font(.caption.bold()).foregroundStyle(AppTheme.blue)
            if confirmedWeeks + confirmedDays == 0 {
                Text("No confirmed periods yet. You can ask about logging, but profit and trend figures remain unavailable.")
                    .font(.caption).foregroundStyle(AppTheme.amber)
            } else if !readiness.canExplainProfit {
                Label(readiness.title, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(AppTheme.amber)
                Text(readiness.detail).font(.caption2).foregroundStyle(AppTheme.muted)
            } else {
                Label("Operating profit can be recalculated.", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(AppTheme.mint)
            }
        }
        .appCard(contentPadding: 15)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("You can ask like this", systemImage: "sparkles").font(.headline).foregroundStyle(AppTheme.blue)
            ForEach(focus?.suggestedQuestions ?? store.suggestedQuestions(for: profile.id), id: \.self) { question in
                Button(question) { send(question) }
                    .font(.subheadline).buttonStyle(.bordered).tint(AppTheme.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(contentPadding: 16)
    }

    private func focusSuggestionCard(_ focus: OperatingAdvisorFocus) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(focus.title, systemImage: focus.symbol).font(.headline).foregroundStyle(focus.tint)
            Text("Pick a question to start, or add your specific situation below.")
                .font(.caption).foregroundStyle(AppTheme.muted)
            ForEach(focus.suggestedQuestions, id: \.self) { question in
                Button(question) { send(question) }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                    .tint(focus.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(contentPadding: 16)
    }

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if focus?.reviewKind != nil,
               conversation.messages.last?.role == "assistant",
               conversation.messages.count > (reviewSessionStartCount ?? conversation.messages.count),
               !runningHere {
                Button { showsFinishReview = true } label: {
                    Label("Finish Review", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.mint)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("operations.finishReview")
            }
            if runningHere, let progress = store.advisorProgress {
                AdvisorProgressCard(progress: progress) { store.cancelResponse() }
                    .padding(.horizontal, 12)
            } else if let error = store.advisorLastError, conversation.messages.last?.role == "user" {
                AdvisorErrorCard(error: error) { retry() }.padding(.horizontal, 12)
            } else if let questions = conversation.messages.last?.suggestedQuestions, !questions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(questions, id: \.self) { value in Button(value) { send(value) }.font(.caption.bold()).buttonStyle(.bordered).tint(AppTheme.blue) } }
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
            HStack(alignment: .bottom, spacing: 9) {
                TextField("Ask about operations, costs, foot traffic, or customers", text: $input, axis: .vertical)
                    .lineLimit(1...5).focused($focused).padding(12)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 17).stroke(focused ? AppTheme.blue.opacity(0.5) : AppTheme.border) }
                    .accessibilityIdentifier("operations.advisor.composer")
                Button { send(input) } label: {
                    Image(systemName: "arrow.up").font(.headline.bold()).foregroundStyle(.white).frame(width: 44, height: 44).background(canSend ? AppTheme.blue : AppTheme.muted.opacity(0.35), in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send operation question")
                .accessibilityIdentifier("operations.advisor.send")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8).padding(.bottom, 8).background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        let count = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (2...2_000).contains(count) &&
            !store.isResponding &&
            !isAuthorizingSpend
    }
    private func send(_ value: String) {
        let question = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.count >= 2 else { return }
        isAuthorizingSpend = true
        Task {
            defer { isAuthorizingSpend = false }
            guard let reservation = await communityStore.reserveCreditUsage(.operationsAdvisorTurn) else {
                return
            }
            input = ""
            focused = false
            if await store.sendQuestion(question, storeID: profile.id) {
                await communityStore.settleCreditUsage(reservation)
            } else {
                await communityStore.refundCreditUsage(reservation)
            }
        }
    }
    private func retry() {
        guard let value = conversation.messages.last?.content else { return }
        guard !isAuthorizingSpend else { return }
        isAuthorizingSpend = true
        Task {
            defer { isAuthorizingSpend = false }
            guard let reservation = await communityStore.reserveCreditUsage(.operationsAdvisorTurn) else {
                return
            }
            if await store.sendQuestion(value, storeID: profile.id) {
                await communityStore.settleCreditUsage(reservation)
            } else {
                await communityStore.refundCreditUsage(reservation)
            }
        }
    }

    private func finishReview() {
        guard let kind = focus?.reviewKind else { return }
        let conclusion = conversation.messages.last(where: { $0.role == "assistant" })?.content ?? ""
        finishedReport = store.saveReviewReport(kind: kind, for: profile.id, advisorConclusion: conclusion)
        if let finishedReport {
            Task {
                await communityStore.recordCreditEvent(
                    kind: kind == .weekly
                        ? "weekly_review_completed"
                        : "monthly_review_completed",
                    eventID: finishedReport.id.uuidString
                )
            }
        }
    }
}

private extension Double {
    var currencyUSD: String {
        formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
    var percentText: String { formatted(.percent.precision(.fractionLength(1))) }
}

private struct OperatingFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
