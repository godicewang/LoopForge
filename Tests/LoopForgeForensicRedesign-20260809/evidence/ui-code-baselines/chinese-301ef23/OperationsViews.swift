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
                        serviceName: "经营顾问",
                        detail: "日/周记录仍可离线填写并保存在本机；联网建议与单据结构化暂不可用。"
                    ) {
                        Task { await store.refreshServiceStatus() }
                    }
                }
                if let notice = store.storageNotice {
                    InlineStatusCard(
                        title: "经营档案尚未保存",
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
        .navigationTitle("经营助手")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    requestExit()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("返回")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { createsProfile = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新增门店档案")
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
                            Button("完成") { showsFirstReminderSetup = false }
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
        .alert("每天记录有点吃力？", isPresented: $showsCadenceReminder) {
            if let profile = store.selectedProfile {
                Button("改为每周记录") { store.setRecordingCadence(.weekly, for: profile.id) }
            }
            Button("继续每日记录", role: .cancel) {}
        } message: {
            Text("最近 7 天的日记录较少。改成每周集中核对不会丢失已有数据，系统仍会按月自动汇总。")
        }
        .confirmationDialog(
            "先设置经营提醒吗？",
            isPresented: $showsFirstReminderPrompt,
            titleVisibility: .visible
        ) {
            Button("现在设置") {
                store.acknowledgeFirstReminderPrompt()
                showsFirstReminderSetup = true
            }
            Button("暂不设置并退出") {
                store.acknowledgeFirstReminderPrompt()
                store.endOperationsAssistantSession()
                dismiss()
            }
            Button("继续使用经营助手", role: .cancel) {}
        } message: {
            Text("按你的记录习惯设置日记录、周脉搏和月复盘提醒，能减少漏记。此提示只出现一次，之后可在“经营设置”中随时修改。")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            AgentOrb(size: 58, isActive: store.isResponding)
            VStack(alignment: .leading, spacing: 7) {
                Text("把流水变成下一步")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("每周看变化，每月看利润；所有金额先按你确认的记录复算，再交给小易给建议。")
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
                Button("编辑当前门店") { editsProfile = profile }
                Button("新增门店") { createsProfile = true }
            } label: {
                Label("切换", systemImage: "chevron.down")
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
                    Text("经营数据怎么记").font(.headline).foregroundStyle(AppTheme.ink)
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
                    Text("今天先做一件事").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                    Text(readiness.title).font(.headline).foregroundStyle(AppTheme.ink)
                    Text(readiness.detail).font(.caption).foregroundStyle(AppTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                readinessPill("周脉搏 \(readiness.confirmedWeeks)", ready: readiness.confirmedWeeks > 0)
                readinessPill("月汇总 \(readiness.confirmedMonths)", ready: readiness.confirmedMonths > 0)
                readinessPill("利润可复算", ready: readiness.canExplainProfit)
            }
            if readiness.canExplainProfit {
                NavigationLink { OperatingAdvisorConversationView(profile: profile) } label: {
                    Label("让小易给出优先动作", systemImage: "arrow.right")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.blue)
            } else {
                NavigationLink {
                    ledgerEntryDestination(profile)
                } label: {
                    Label(store.recordingCadence(for: profile.id) == .daily ? "去记录今天" : "去完善上周记录", systemImage: "arrow.right")
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
            SectionTitle("每周经营脉搏", caption: cadence == .daily ? "由每日记录自动汇总" : (latest == nil ? "尚未记录" : "最近已确认"))
            if let latest {
                let profit = latest.metrics.operatingProfit
                HStack(spacing: 10) {
                    OperatingMetricCell(title: "周流水", value: latest.revenue?.currencyYuan ?? "未记录", tint: AppTheme.blue)
                    OperatingMetricCell(
                        title: "经营结余",
                        value: profit?.currencyYuan ?? (latest.revenue == nil ? "待补流水" : "待补成本"),
                        tint: profit.map { $0 >= 0 ? AppTheme.mint : AppTheme.red } ?? AppTheme.muted
                    )
                    OperatingMetricCell(title: "客单价", value: latest.metrics.averageTicket?.currencyYuan ?? "待补订单", tint: AppTheme.amber)
                }
                if cadence == .weekly {
                    NavigationLink {
                        OperatingLedgerEditorView(mode: .weekly(storeID: profile.id, existing: latest))
                    } label: {
                        Label("查看并更新最近一周", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.blue)
                }
            } else {
                Text("录入流水、订单和实际成本后，系统才会计算利润率与成本占比，不会用行业数字替代你的账。")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            if cadence == .daily {
                NavigationLink {
                    OperatingLedgerEditorView(mode: .daily(storeID: profile.id, existing: store.dailyRecord(for: profile.id)))
                } label: {
                    PrimaryActionLabel(
                        title: store.dailyRecord(for: profile.id) == nil ? "记录今天的经营数据" : "继续完善今天的记录",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("operations.addDaily")
            } else if current?.id != latest?.id {
                NavigationLink {
                    OperatingLedgerEditorView(mode: .weekly(storeID: profile.id, existing: current))
                } label: {
                    PrimaryActionLabel(title: current == nil ? "记录上周经营脉搏" : "继续完善上周记录", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("operations.addWeekly")
            }
            if latest != nil {
                NavigationLink { OperatingAdvisorConversationView(profile: profile, focus: .weeklyReview) } label: {
                    Label("和经营顾问复盘上周", systemImage: "bubble.left.and.text.bubble.right.fill")
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
            SectionTitle("每月经营复盘", caption: previousMonth.formatted(.dateTime.year().month()) + " · 系统自动汇总")
            if let latest {
                let profit = latest.metrics.operatingProfit
                HStack(spacing: 10) {
                    OperatingMetricCell(title: "月流水", value: latest.revenue?.currencyYuan ?? "未记录", tint: AppTheme.blue)
                    OperatingMetricCell(title: "总成本", value: latest.costs.total?.currencyYuan ?? "未补齐", tint: AppTheme.amber)
                    OperatingMetricCell(
                        title: "经营利润",
                        value: profit?.currencyYuan ?? (latest.revenue == nil ? "待补流水" : "待补成本"),
                        tint: profit.map { $0 >= 0 ? AppTheme.mint : AppTheme.red } ?? AppTheme.muted
                    )
                }
                Label("已汇总 \(coverage.actual) / \(coverage.expected) \(coverage.unit)；缺失项不会用平均值补齐", systemImage: coverage.actual >= coverage.expected ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(coverage.actual >= coverage.expected ? AppTheme.mint : AppTheme.amber)
            } else {
                Text("上月还没有可汇总的已确认记录。系统不会要求你再抄一遍月账，也不会用行业平均值补空白。")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            NavigationLink {
                OperatingAdvisorConversationView(profile: profile, focus: .monthlyReview)
            } label: {
                Label("和经营顾问复盘上月", systemImage: "bubble.left.and.text.bubble.right.fill")
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
            SectionTitle("经营设置", caption: "提醒、实验与顾问原则")
            HStack(spacing: 10) {
                NavigationLink { OperatingExperimentListView(profile: profile) } label: {
                    OperationsActionTile(title: "行动实验", detail: "验证打法是否有效", symbol: "checkmark.seal", tint: AppTheme.mint)
                }
                NavigationLink { OperatingReminderView() } label: {
                    OperationsActionTile(title: "主动提醒", detail: "日记录、周/月复盘", symbol: "bell.badge", tint: AppTheme.amber)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                NavigationLink { OperatingMemoryView(profile: profile) } label: {
                    OperationsActionTile(title: "顾问原则", detail: "目标、约束与边界", symbol: "list.bullet.clipboard.fill", tint: AppTheme.periwinkle)
                }
                NavigationLink { OperatingReviewHistoryView(profile: profile) } label: {
                    OperationsActionTile(title: "复盘报告", detail: "查看周/月历史", symbol: "doc.text.magnifyingglass", tint: AppTheme.blue)
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
                SectionTitle("经营趋势", caption: "点击指标切换")
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
                    Text("最新 \(trendMetric.title)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Text(points.last?.value.formatted(.number.precision(.fractionLength(0...2))) ?? "—")
                        .font(.headline.bold())
                        .foregroundStyle(AppTheme.deepClay)
                        .monospacedDigit()
                    Spacer()
                    Text("\(points.count) 个有效记录")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.muted)
                }
                Chart(points) { point in
                    if points.count > 1 {
                        AreaMark(
                            x: .value("账期", point.date),
                            y: .value(trendMetric.title, point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [AppTheme.blue.opacity(0.24), AppTheme.blue.opacity(0.01)], startPoint: .top, endPoint: .bottom)
                        )
                        LineMark(
                            x: .value("账期", point.date),
                            y: .value(trendMetric.title, point.value)
                        )
                        .foregroundStyle(AppTheme.blue)
                        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    PointMark(
                        x: .value("账期", point.date),
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
                .accessibilityLabel("\(trendMetric.title)趋势图，包含 \(points.count) 个账期")
            } else {
                ContentUnavailableView(
                    "这个时间段还没有\(trendMetric.title)数据",
                    systemImage: "chart.xyaxis.line",
                    description: Text("确认 1 天或 1 周的记录后就会显示，不需要等到第二期。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            }
            Text("空白账期不会连线或补平均值；发现缺失或冲突时，请回到账期记录核对。")
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
            SectionTitle("向经营顾问问生意", caption: "带着真实流水直接聊下一步")
            NavigationLink { OperatingGrowthPlaybookView(profile: profile) } label: {
                HStack(spacing: 13) {
                    FeatureIcon(symbol: "person.2.wave.2.fill", tint: AppTheme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("开始一次经营对话").font(.headline).foregroundStyle(AppTheme.ink)
                        Text("直接问，或先选流水复盘、获客、利润、顾客等问题。")
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
                SectionTitle("历史记录", caption: "复盘报告与原始账期分开保存")
                ForEach(reports.prefix(3)) { report in
                    NavigationLink { OperatingReviewDetailView(report: report) } label: {
                        HStack(spacing: 12) {
                            FeatureIcon(symbol: report.kind == .weekly ? "doc.text.fill" : "calendar.badge.checkmark", tint: AppTheme.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(report.kind.title)
                                    .font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text(report.periodStart.formatted(.dateTime.year().month().day()) + " · 已归档")
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
                                Text(record.day.formatted(.dateTime.year().month().day()) + " 日记录")
                                    .font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text("流水 \(record.revenue?.currencyYuan ?? "未记录") · \(record.state.title)")
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
                                Text(record.weekStart.formatted(.dateTime.year().month().day()) + " 当周")
                                    .font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text("流水 \(record.revenue?.currencyYuan ?? "未记录") · \(record.state.title)")
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
                    Text("旧版手填月账已保留，可在历史数据迁移中核对；新的月复盘只从日/周记录自动汇总。")
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
            Text("先建立你的真实经营档案").font(.title3.bold())
            Text("只需门店名、品类和所在城市。没有确认过的流水与成本时，小易不会替你编造经营结果。")
                .font(.subheadline).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button("创建第一家门店") { createsProfile = true }
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
                Text("自选经营趋势时间")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("开始和结束日期都包含在图表中；没有记录的日期不会补数。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            VStack(spacing: 0) {
                DatePicker("开始日期", selection: $start, in: ...Date.now, displayedComponents: .date)
                    .padding(.vertical, 12)
                Divider()
                DatePicker("结束日期", selection: $end, in: ...Date.now, displayedComponents: .date)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 15)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("将展示 \(min(start, end).formatted(.dateTime.year().month().day())) 至 \(max(start, end).formatted(.dateTime.year().month().day()))")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.blue)
            Button(action: apply) {
                PrimaryActionLabel(title: "查看这段时间", systemImage: "chart.xyaxis.line")
            }
            .buttonStyle(PressFeedbackStyle())
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(AppBackdrop(accent: AppTheme.blue))
        .navigationTitle("选择时间")
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
        _areaText = State(initialValue: profile.areaSquareMeters.map { String(format: "%.0f", $0) } ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("经营档案只保存到本机；对话时会把已确认的经营摘要发送给服务端。")
                    .font(.caption).foregroundStyle(AppTheme.muted)
                fieldCard("门店基本信息") {
                    labeledField("门店名", placeholder: "营业执照名或日常称呼", text: $profile.name)
                    labeledField("经营品类", placeholder: "例如：社区咖啡、川味小炒", text: $profile.category)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("常用品类")
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
                                .accessibilityValue(profile.category == value ? "已选择" : "未选择")
                            }
                        }
                    }
                    Text("可直接选择常用品类，也可以在上方写得更具体。品类会决定经营助手建议记录的细分指标。")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                    NavigationLink {
                        LocationPickerView { location in
                            acceptMapLocation(location)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            FeatureIcon(symbol: "map.fill", tint: AppTheme.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.location == nil ? "在地图上确认门店" : "已确认真实门店位置")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.ink)
                                Text(profile.location.map { location in
                                    [location.name, location.conciseAddress]
                                        .compactMap { $0 }
                                        .joined(separator: " · ")
                                } ?? "与开店助手使用同一套搜索、点按和最近地址体验")
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
                    labeledField("城市", placeholder: "例如：成都", text: $profile.city)
                    labeledField("区 / 县", placeholder: "例如：双流区", text: $profile.district)
                    labeledField("具体地址（可选）", placeholder: "用于查询当地经营信息", text: $profile.address)
                    labeledField("营业面积（可选）", placeholder: "平方米", text: $areaText, keyboard: .decimalPad)
                }
                fieldCard("经营重点") {
                    labeledField("当前最想解决的问题（可选）", placeholder: "例如：提高工作日晚餐复购", text: $profile.primaryGoal)
                    Text("已有渠道").font(.caption.bold()).foregroundStyle(AppTheme.muted)
                    OperatingFlowLayout(spacing: 8) {
                        ForEach(["到店", "外卖", "团购", "微信私域", "抖音", "小红书"], id: \.self) { value in
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
                        Label("删除这家门店及本机经营数据", systemImage: "trash")
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
        .navigationTitle(profile.name.isEmpty ? "新建经营档案" : "编辑经营档案")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "删除“\(profile.name)”？",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("删除门店档案", role: .destructive) {
                store.deleteProfile(profile.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除本机保存的日/周记录、复盘报告、行动实验、经营对话和顾问原则，且无法撤销。")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    profile.areaSquareMeters = Double(areaText)
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
        if profile.district.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.district = administrativeHint.district ?? profile.district
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
            profile.district = placemark.subLocality ?? profile.district
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
        case .daily: "每日经营记录"
        case .weekly: "每周经营脉搏"
        case .monthly: "历史月账"
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
    @State private var newPrivateCustomers: Int?
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
            _newPrivateCustomers = State(initialValue: existing?.newPrivateDomainCustomers)
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
            _newPrivateCustomers = State(initialValue: existing?.newPrivateDomainCustomers)
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
            _newPrivateCustomers = State(initialValue: initial.newPrivateDomainCustomers)
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
                PrimaryActionLabel(title: state == .confirmed ? "确认并保存" : "保存为待确认", systemImage: state == .confirmed ? "checkmark.shield.fill" : "square.and.arrow.down")
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
                DatePicker(mode.isDaily ? "记录日期" : "账单月份", selection: $date, in: ...Date.now, displayedComponents: .date)
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
                    Text("本期数据完整度").font(.subheadline.bold())
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
                Text("本周开始日 · \(start.formatted(.dateTime.month().day()))").font(.headline)
                Spacer()
                Label(isLastWeek ? "当前：上周数据" : "当前：所选账期", systemImage: dateSelectionConfirmed ? "calendar.badge.checkmark" : "calendar")
                    .font(.caption.bold())
                    .foregroundStyle(dateSelectionConfirmed ? AppTheme.blue : AppTheme.amber)
            }
            DatePicker(
                "点击日期定位整周",
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
                    .accessibilityLabel(day.formatted(.dateTime.year().month().day().weekday(.wide)) + (selected ? "，已选" : "，同一账期"))
                }
            }
            Text("只可选择已经完整结束的 7 天；最近不足 7 天的日期不可选。")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
            Button {
                confirmSelectedWeek(start)
            } label: {
                Label(dateSelectionConfirmed ? "已确定这 7 天" : "确定这 7 天", systemImage: dateSelectionConfirmed ? "checkmark.circle.fill" : "calendar.badge.checkmark")
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
        newPrivateCustomers = existing?.newPrivateDomainCustomers
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
        newPrivateCustomers = existing?.newPrivateDomainCustomers
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
                    Text("导入经营凭证").font(.headline)
                    Text("可选：帮你少打字，也可以直接手动填写").font(.caption).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if store.isImporting { ProgressView() }
            }
            Text("支持照片、截图、PDF、CSV 和 XLSX；识别结果只填入空白项，保存前由你核对。")
                .font(.caption).foregroundStyle(AppTheme.muted)
            OperatingFlowLayout(spacing: 10) {
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showsCamera = true
                    } else {
                        localImportError = "当前设备没有可用相机；模拟器中可用“选照片”测试识别。"
                    }
                } label: {
                    Label("拍照", systemImage: "camera.fill")
                }
                .buttonStyle(.bordered)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("选照片", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                Button { showsFileImporter = true } label: {
                    Label("选文件", systemImage: "doc.badge.plus")
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
            Label("已识别，等待你核对", systemImage: "doc.text.magnifyingglass")
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
                draft.revenue.map { "流水 \($0.currencyYuan)" },
                draft.orders.map { "订单 \($0) 单" },
                draft.costs.hasAnyValue ? "已识别成本 \(draft.costs.knownTotal.currencyYuan)" : nil,
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.bold()).foregroundStyle(AppTheme.ink)
            ForEach(draft.warnings, id: \.self) { warning in
                Text("• \(warning)").font(.caption2).foregroundStyle(AppTheme.amber)
            }
            DisclosureGroup("查看识别原文") {
                Text(draft.extractedTextPreview)
                    .font(.caption2.monospaced()).foregroundStyle(AppTheme.muted)
                    .textSelection(.enabled).padding(.top, 4)
            }
            .font(.caption.bold()).tint(AppTheme.blue)
            if hasImportableValues {
                Button("填入表单后继续核对") { applyImport(draft) }
                    .font(.caption.bold()).buttonStyle(.borderedProminent).tint(AppTheme.blue)
            } else {
                Text("没有可安全自动填入的数字，请参考上方提示后手动填写。")
                    .font(.caption.bold()).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .background(AppTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var revenueCard: some View {
        OperatingFormCard(title: "收入与订单", caption: "按实际结算口径填写") {
            optionalMoneyField("营业流水", value: $revenue, previous: previousPeriod?.revenue)
            optionalIntegerField("完成订单", value: $orders, previous: previousPeriod?.orders)
            if mode.isMonthly {
                optionalMoneyField("期末可用现金", value: $cashBalance)
                Text("可用现金不参与利润计算，仅用于判断资金安全垫。")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
        }
    }

    private var costCard: some View {
        OperatingFormCard(title: "实际成本", caption: "不要只填进货成本") {
            if let previous = previousPeriod?.costs, [previous.labor, previous.rent, previous.utilities, previous.other].contains(where: { $0 != nil }) {
                Button {
                    if costs.labor == nil { costs.labor = previous.labor }
                    if costs.rent == nil { costs.rent = previous.rent }
                    if costs.utilities == nil { costs.utilities = previous.utilities }
                    if costs.other == nil { costs.other = previous.other }
                } label: {
                    Label("沿用上一期固定成本", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered).tint(AppTheme.blue)
                Text("只填入当前仍为空白的人工、房租、水电和其他成本；保存前请按本期账单核对。")
                    .font(.caption2).foregroundStyle(AppTheme.muted)
            }
            optionalMoneyField("商品 / 原材料", value: $costs.goods, previous: previousPeriod?.costs.goods)
            optionalMoneyField("人工", value: $costs.labor, previous: previousPeriod?.costs.labor)
            optionalMoneyField("房租分摊", value: $costs.rent, previous: previousPeriod?.costs.rent)
            optionalMoneyField("平台扣点与配送", value: $costs.platform, previous: previousPeriod?.costs.platform)
            optionalMoneyField("推广与优惠", value: $costs.marketing, previous: previousPeriod?.costs.marketing)
            optionalMoneyField("水电能耗", value: $costs.utilities, previous: previousPeriod?.costs.utilities)
            optionalMoneyField("其他", value: $costs.other, previous: previousPeriod?.costs.other)
        }
    }

    private var customerCard: some View {
        OperatingFormCard(title: "顾客变化", caption: "空白表示未记录；确实为 0 时请明确填 0") {
            optionalIntegerField("到店 / 服务顾客", value: $customerVisits)
            optionalIntegerField("新增私域顾客", value: $newPrivateCustomers)
            optionalIntegerField("复购顾客", value: $repeatCustomers)
        }
    }

    private var customMetricsCard: some View {
        let profile = store.workspace.profiles.first { $0.id == mode.storeID }
        let presets = OperatingMetricPreset.suggestions(category: profile?.category ?? "", channels: profile?.channels ?? [])
        return OperatingFormCard(title: "经营细分指标", caption: "按你的业态选填，帮助判断动作是否真的有效") {
            if customMetrics.isEmpty {
                Text("例如夜间订单、售出杯数或堂食桌数。这里只记录你能核对的事实，不套行业平均值。")
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
                    TextField("指标名", text: $customMetrics[index].name)
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    TextField("数值", value: $customMetrics[index].value, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 76)
                    TextField("单位", text: $customMetrics[index].unit)
                        .multilineTextAlignment(.center).frame(width: 46)
                    Button(role: .destructive) { customMetrics.remove(at: index) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("删除\(customMetrics[index].name)")
                }
                .padding(10)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if customMetrics.count < 12 {
                Button {
                    customMetrics.append(OperatingCustomMetric(name: "", unit: "次"))
                } label: {
                    Label("添加其他指标", systemImage: "plus.circle")
                }
                .font(.caption.bold()).buttonStyle(.plain).foregroundStyle(AppTheme.blue)
            }
        }
    }

    private var noteCard: some View {
        OperatingFormCard(title: "本期发生了什么", caption: "天气、活动、停业、涨价、人员变化等") {
            TextEditor(text: $note)
                .frame(minHeight: 100)
                .padding(9)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if mode.isWeekly {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label("下周目标", systemImage: "scope")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.blue)
                    TextField("例如：工作日晚餐订单提升 10%，营销费不增加", text: $nextPeriodGoal, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .padding(11)
                        .background(AppTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("尽量写成一个可核验的结果：指标 + 目标值 + 不突破的成本边界。")
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
            SectionTitle("公式复算", caption: "只使用上方已填数据")
            HStack(spacing: 10) {
                OperatingMetricCell(title: "经营结余", value: metrics.operatingProfit?.currencyYuan ?? calculationMissingLabel, tint: metrics.operatingProfit.map { $0 >= 0 ? AppTheme.mint : AppTheme.red } ?? AppTheme.muted)
                OperatingMetricCell(title: "利润率", value: metrics.operatingMargin.map { $0.percentText } ?? calculationMissingLabel, tint: AppTheme.blue)
                OperatingMetricCell(title: "客单价", value: metrics.averageTicket?.currencyYuan ?? "待填订单", tint: AppTheme.amber)
            }
        }
        .appCard(contentPadding: 17)
    }

    private var recordValidation: OperatingRecordValidation {
        let base = OperatingRecordValidation.evaluate(
            revenue: revenue,
            orders: orders,
            customerVisits: customerVisits,
            newPrivateDomainCustomers: newPrivateCustomers,
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
        if revenue == nil { return "待填流水" }
        if !costs.isComplete { return "待补成本" }
        return "暂不可算"
    }

    @ViewBuilder
    private var validationCard: some View {
        let validation = recordValidation
        if !validation.blockers.isEmpty || !validation.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Label(
                    validation.blockers.isEmpty ? "保存前建议再核对" : "暂不能标记为已确认",
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
                    Text("你仍可切换为“待确认”保存，补齐后再让经营顾问使用。")
                        .font(.caption2).foregroundStyle(AppTheme.muted)
                }
            }
            .appCard(contentPadding: 16)
        }
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("记录状态", selection: $state) {
                Text("待确认").tag(OperatingRecordState.draft)
                Text("我已核对").tag(OperatingRecordState.confirmed)
            }
            .pickerStyle(.segmented)
            Text(state == .confirmed ? "确认后数据会进入经营顾问的长期上下文。" : "待确认记录会保存在本机，但不会用于经营判断。")
                .font(.caption).foregroundStyle(AppTheme.muted)
        }
        .appCard(contentPadding: 17)
    }

    private func optionalMoneyField(_ title: String, value: Binding<Double?>, previous: Double? = nil) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text("¥").foregroundStyle(AppTheme.muted)
            TextField(
                "",
                value: value,
                format: .number.precision(.fractionLength(0...2)),
                prompt: Text(previous.map { "上期 \($0.formatted(.number.precision(.fractionLength(0...2))))" } ?? "未填写")
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
                prompt: Text(previous.map { "上期 \($0)" } ?? "未填写")
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
            await store.parseDocument(fileName: "所选经营凭证照片", kind: .recognizedText(text: text, mimeType: "image/jpeg"))
        } catch {
            localImportError = error.localizedDescription
        }
    }

    private func handleCapturedPhoto(_ data: Data) async {
        localImportError = nil
        do {
            let text = try await OperatingDocumentProcessor.recognize(imageData: data)
            await store.parseDocument(fileName: "拍摄的经营凭证", kind: .recognizedText(text: text, mimeType: "image/jpeg"))
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
            localImportError = "表单中已有的金额未被自动覆盖，请对照凭证手动确认是否需要相加或替换。"
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
                    newPrivateDomainCustomers: newPrivateCustomers,
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
                    newPrivateDomainCustomers: newPrivateCustomers,
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
                    newPrivateDomainCustomers: newPrivateCustomers,
                    repeatCustomers: repeatCustomers,
                    customMetrics: customMetrics.isEmpty ? nil : customMetrics,
                    costs: costs, cashBalance: cashBalance, note: note, sourceDocumentNames: sourceNames, state: state,
                    createdAt: existing?.createdAt ?? .now
                )
            )
        }
        if state == .confirmed, let savedRecordID {
            Task {
                await communityStore.recordFortuneEvent(
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
    @State private var saveResultTitle = "保存成功"
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
                        Text("锁屏不展示经营隐私")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text("通知只提示“该记录或复盘”，不会显示门店名、流水、成本和利润。你可随时在系统设置中关闭通知。")
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
        .navigationTitle("主动提醒")
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
                    Text(isSaving ? "正在保存" : "保存提醒设置")
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
            Button("知道了", role: .cancel) {}
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
                Text("让复盘按时发生")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("按你的记录节奏提醒；每日提醒默认开启，周和月提醒由你决定。")
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
            title: "每日经营记录",
            detail: "当天收尾时提醒核对流水、订单和实际成本",
            symbol: "sunset.fill",
            tint: AppTheme.amber,
            isEnabled: $settings.dailyEnabled
        ) {
            hourPicker(title: "提醒时间", hour: $settings.dailyHour)
        }
    }

    private var weeklyReminderCard: some View {
        reminderCard(
            title: "每周经营脉搏",
            detail: "提醒查看本周变化，并和经营顾问确定下周动作",
            symbol: "waveform.path.ecg",
            tint: AppTheme.blue,
            isEnabled: $settings.weeklyEnabled
        ) {
            settingRow("提醒日期") {
                Picker("提醒日期", selection: $settings.weeklyWeekday) {
                    ForEach(Array(["周日", "周一", "周二", "周三", "周四", "周五", "周六"].enumerated()), id: \.offset) { index, value in
                        Text(value).tag(index + 1)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            hourPicker(title: "提醒时间", hour: $settings.weeklyHour)
        }
    }

    private var monthlyReminderCard: some View {
        reminderCard(
            title: "每月经营复盘",
            detail: "提醒查看系统汇总的环比、同比和利润变化",
            symbol: "calendar.badge.clock",
            tint: AppTheme.mint,
            isEnabled: $settings.monthlyEnabled
        ) {
            settingRow("每月日期") {
                Picker("每月日期", selection: $settings.monthlyDay) {
                    ForEach(1...28, id: \.self) { Text("第 \($0) 天").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            hourPicker(title: "提醒时间", hour: $settings.monthlyHour)
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
                    .accessibilityLabel(title == "每日经营记录" ? "每日提醒" : "\(title)提醒")
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
            saveResultDetail = store.reminderNotice ?? "提醒设置已经保存。"
            saveResultTitle = saveResultDetail.contains("没有允许通知") ? "设置已保存，通知未开启" : "保存成功"
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
    case privateDomain
    case retention
    case cost
    case inventory
    case staffing
    case pricing

    var id: String { rawValue }
    static var actionCases: [Self] { [.cashflow, .nextWeek, .acquisition, .privateDomain, .retention, .cost, .inventory, .staffing, .pricing] }
    var reviewKind: OperatingReviewKind? {
        switch self {
        case .weeklyReview: .weekly
        case .monthlyReview: .monthly
        default: nil
        }
    }
    var title: String {
        switch self {
        case .weeklyReview: "本周复盘"
        case .monthlyReview: "上月复盘"
        case .cashflow: "复盘流水"
        case .nextWeek: "下周怎么做"
        case .acquisition: "获客与推广"
        case .privateDomain: "私域经营"
        case .retention: "顾客复购"
        case .cost: "降本增利"
        case .inventory: "库存损耗"
        case .staffing: "人员排班"
        case .pricing: "定价与套餐"
        }
    }
    var caption: String {
        switch self {
        case .weeklyReview: "找出变化与下周动作"
        case .monthlyReview: "同比环比与下月计划"
        case .cashflow: "收入、渠道和异常波动"
        case .nextWeek: "排出最值得做的三件事"
        case .acquisition: "预算、转化与停止条件"
        case .privateDomain: "加粉、触达和成交闭环"
        case .retention: "召回、投诉与老客维护"
        case .cost: "原料、人工、平台和房租"
        case .inventory: "采购、周转与报损"
        case .staffing: "峰谷客流与人效"
        case .pricing: "客单价、毛利和产品组合"
        }
    }
    var symbol: String {
        switch self {
        case .weeklyReview, .monthlyReview, .cashflow: "chart.line.uptrend.xyaxis"
        case .nextWeek: "list.bullet.clipboard.fill"
        case .acquisition: "megaphone.fill"
        case .privateDomain: "person.2.wave.2.fill"
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
        case .privateDomain, .retention: AppTheme.periwinkle
        case .cost, .inventory, .staffing: AppTheme.mint
        }
    }
    var suggestedQuestions: [String] {
        switch self {
        case .weeklyReview:
            ["结合上周流水、成本和顾客变化，先指出最关键的两个变化。", "哪些结论有数据支撑，哪些还需要我补充？", "把下周行动压缩成三个可验证步骤。"]
        case .monthlyReview:
            ["对比最近两个月，利润变化主要由什么驱动？", "上月哪些增长是可持续的，哪些可能只是活动波动？", "请给出下月目标、预算上限和停止条件。"]
        case .cashflow:
            ["帮我拆解最近流水变化来自客流、客单价还是渠道。", "检查是否有重复统计、退款或充值导致的口径问题。", "哪个收入渠道最值得继续投入？"]
        case .nextWeek:
            ["结合当前数据，排出下周最重要的三件事。", "每件事应该观察什么指标和停止条件？", "哪些事情现在不值得做？"]
        case .acquisition:
            ["我该优先做哪种获客方式，预算上限是多少？", "怎样拆曝光、到店、下单和复购评估推广？", "帮我设计一个一周可验证的拉新实验。"]
        case .privateDomain:
            ["顾客为什么愿意加入私域，我该提供什么价值？", "如何分层触达而不打扰顾客？", "私域活动怎样衡量真实到店和复购？"]
        case .retention:
            ["哪些顾客最值得优先召回？", "怎样处理投诉后再争取复购？", "给我一套不只靠打折的老客维护动作。"]
        case .cost:
            ["哪项成本最值得先降，而且不伤害顾客体验？", "把固定成本和随流水变化的成本分开分析。", "帮我设置一周降本实验及停止条件。"]
        case .inventory:
            ["怎样找出采购、库存和报损的异常？", "哪些商品应该降库存或提高周转？", "帮我设计每日可执行的盘点口径。"]
        case .staffing:
            ["结合峰谷时段，排班哪里可能过重或不足？", "怎样用人效判断是否需要调整班次？", "调整排班时如何避免服务质量下降？"]
        case .pricing:
            ["当前客单价和毛利是否支持现有定价？", "哪些套餐可能提高客单价但不会透支毛利？", "帮我设计一个不依赖大额折扣的价格实验。"]
        }
    }
}

struct OperatingGrowthPlaybookView: View {
    let profile: OperatingStoreProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("直接问小易", systemImage: "sparkles")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Text("小易会先读取“\(profile.name)”已经确认的经营记录，再联想你现在最值得追问的问题。")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.76))
                    NavigationLink { OperatingAdvisorConversationView(profile: profile) } label: {
                        Label("开始对话", systemImage: "arrow.right")
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

                SectionTitle("你现在最想解决什么", caption: "选择后会预置对应追问，不会直接套一段教程")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                    ForEach(OperatingAdvisorFocus.actionCases) { focus in
                        NavigationLink { OperatingAdvisorConversationView(profile: profile, focus: focus) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                FeatureIcon(symbol: focus.symbol, tint: focus.tint)
                                Text(focus.title).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Text(focus.caption).font(.caption2).foregroundStyle(AppTheme.muted).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
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
        .navigationTitle("问经营顾问")
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
                Text("每次只验证一个经营假设，先写指标和停止条件；实验结果会进入经营顾问的长期上下文。")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Section("行动实验") {
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
                    ContentUnavailableView("还没有行动实验", systemImage: "checkmark.seal", description: Text("从一个具体问题开始，例如‘工作日晚餐套餐能否提高客单价’。"))
                }
            }
        }
        .navigationTitle("行动实验")
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
            Section("要验证什么") {
                TextField("实验名称", text: $experiment.title)
                TextField("假设：做什么会带来什么变化", text: $experiment.hypothesis, axis: .vertical)
            }
            Section("怎样判断") {
                TextField("主指标，例如：工作日晚餐订单", text: $experiment.metric)
                TextField("目标与停止条件", text: $experiment.target, axis: .vertical)
                DatePicker("开始", selection: $experiment.startsAt, displayedComponents: .date)
                DatePicker("结束", selection: $experiment.endsAt, in: experiment.startsAt..., displayedComponents: .date)
            }
            Section("状态与结果") {
                Picker("状态", selection: $experiment.state) { ForEach(OperatingExperimentState.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField("结束后填写观察结果", text: $experiment.result, axis: .vertical)
            }
            if !canSave {
                Section {
                    Text("请补齐实验名称、经营假设、主指标，以及目标与停止条件，避免执行后无法判断是否有效。")
                        .font(.caption).foregroundStyle(AppTheme.amber)
                }
            }
        }
        .navigationTitle(experiment.title.isEmpty ? "新建行动实验" : "编辑行动实验")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { store.saveExperiment(experiment); dismiss() }
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
            Section("经营顾问要遵守的目标") {
                if memory.confirmedGoals.isEmpty { Text("尚未设置").foregroundStyle(AppTheme.muted) }
                ForEach(memory.confirmedGoals, id: \.self) { Text($0) }
            }
            Section("经营顾问不能越过的边界") {
                if memory.confirmedConstraints.isEmpty { Text("尚未设置").foregroundStyle(AppTheme.muted) }
                ForEach(memory.confirmedConstraints, id: \.self) { Text($0) }
            }
            Section {
                Text("这里可以留空。金额、订单与成本只从你确认的日/周记录读取；顾问不会用对话内容改写账目。")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .navigationTitle("顾问原则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") { editsMemory = true }
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
            Section("经营目标") {
                TextEditor(text: $goals).frame(minHeight: 110)
                Text("每行一条，例如：三个月内把工作日复购率提升到 30%。")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Section("经营约束") {
                TextEditor(text: $constraints).frame(minHeight: 110)
                Text("只写你已经确认的边界，例如预算上限、不能延长营业时间或人员限制。")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
            Section {
                Text("这些原则会约束后续经营对话；模型建议不会自动写入或修改。")
                    .font(.caption).foregroundStyle(AppTheme.muted)
            }
        }
        .navigationTitle("编辑顾问原则")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let memory = store.memory(for: profile.id)
            goals = memory.confirmedGoals.joined(separator: "\n")
            constraints = memory.confirmedConstraints.joined(separator: "\n")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
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
                        Text("小易 · 经营助手").font(.title2.bold()).foregroundStyle(.white)
                        Text("按门店读取已确认账期、经营目标和行动实验，必要时查阅当地公开资料。")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.78))
                    }
                }
                .padding(20)
                .background(LinearGradient(colors: [AppTheme.deepClay, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                if !store.serviceStatus.isReady {
                    ServiceStatusCard(status: store.serviceStatus, serviceName: "经营顾问", detail: store.serviceStatus.detail) {
                        Task { await store.refreshServiceStatus() }
                    }
                }
                SectionTitle("选择经营中的门店", caption: "一店一段长期对话")
                if store.workspace.profiles.isEmpty {
                    VStack(spacing: 12) {
                        Text("还没有经营档案").font(.headline)
                        Text("先建立门店档案，再逐周积累真实经营记录。")
                            .font(.subheadline).foregroundStyle(AppTheme.muted)
                        Button("创建经营档案") { createsProfile = true }
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
                                Button("清空这段经营对话", systemImage: "trash", role: .destructive) {
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
            "清空“\(clearsConversationFor?.name ?? "")”的经营对话？",
            isPresented: Binding(
                get: { clearsConversationFor != nil },
                set: { if !$0 { clearsConversationFor = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("只清空对话", role: .destructive) {
                if let profile = clearsConversationFor { store.clearConversation(for: profile.id) }
                clearsConversationFor = nil
            }
            Button("对话与摘要一起清空", role: .destructive) {
                if let profile = clearsConversationFor { store.clearConversation(for: profile.id, alsoClearSummary: true) }
                clearsConversationFor = nil
            }
            Button("取消", role: .cancel) { clearsConversationFor = nil }
        } message: {
            Text("门店档案、日/周记录、复盘报告和顾问原则不会被删除。")
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
                HStack { Text(profile.name).font(.headline).foregroundStyle(AppTheme.ink); Spacer(); Text(conversation.messages.isEmpty ? "新对话" : conversation.updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(AppTheme.muted) }
                Text([profile.category, profile.locationLabel].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption.bold()).foregroundStyle(AppTheme.blue)
                Text(conversation.messages.last?.compactPreview ?? "从本周经营脉搏开始提问").font(.caption).foregroundStyle(AppTheme.muted).lineLimit(2)
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
                    "还没有归档复盘",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("完成一次周或月复盘对话，再点击“结束复盘并生成报告”。")
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
        .navigationTitle("复盘报告")
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
                    Text("数据覆盖 \(report.sourceRecordCount) / \(report.expectedRecordCount) 期")
                        .font(.caption.bold()).foregroundStyle(.white.opacity(0.86))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(LinearGradient(colors: [AppTheme.deepClay, AppTheme.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))

                HStack(spacing: 10) {
                    OperatingMetricCell(title: "流水", value: report.metrics.revenue?.currencyYuan ?? "不完整", tint: AppTheme.blue)
                    OperatingMetricCell(title: "经营结余", value: report.metrics.operatingProfit?.currencyYuan ?? "不完整", tint: AppTheme.mint)
                    OperatingMetricCell(title: "客单价", value: report.metrics.averageTicket?.currencyYuan ?? "不完整", tint: AppTheme.amber)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("数据总结").font(.headline)
                    Text(report.factualSummary).font(.subheadline).foregroundStyle(AppTheme.ink)
                }
                .appCard(contentPadding: 17)
                VStack(alignment: .leading, spacing: 8) {
                    Text("经营顾问结论").font(.headline)
                    Text(report.advisorConclusion.isEmpty ? "本次对话没有形成可归档的顾问结论。" : report.advisorConclusion)
                        .font(.subheadline).foregroundStyle(report.advisorConclusion.isEmpty ? AppTheme.muted : AppTheme.ink)
                        .textSelection(.enabled)
                }
                .appCard(contentPadding: 17)
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(AppBackdrop(accent: AppTheme.blue))
        .navigationTitle("阅读复盘")
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
                        Label("查看顾问原则", systemImage: "list.bullet.clipboard.fill")
                    }
                    if !conversation.messages.isEmpty {
                        Button("清空当前对话", systemImage: "trash", role: .destructive) {
                            showsClearDialog = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("清空当前经营对话？", isPresented: $showsClearDialog, titleVisibility: .visible) {
            Button("清空对话", role: .destructive) { store.clearConversation(for: profile.id) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("日/周记录与顾问原则会保留；这只清空当前门店的对话。")
        }
        .confirmationDialog("结束本次复盘并生成阅读报告？", isPresented: $showsFinishReview, titleVisibility: .visible) {
            Button("结束并生成报告") { finishReview() }
            Button("继续对话", role: .cancel) {}
        } message: {
            Text("报告会保存本期可复算数据和最后一条经营顾问结论，之后可在复盘历史中查看。")
        }
        .safeAreaInset(edge: .bottom) { bottomPanel }
    }

    private var contextCard: some View {
        let readiness = store.dataReadiness(for: profile.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack { Label(profile.category, systemImage: "storefront.fill").font(.headline); Spacer(); NavigationLink("顾问原则") { OperatingMemoryView(profile: profile) }.font(.caption.bold()) }
            Text(profile.locationLabel).font(.caption).foregroundStyle(AppTheme.muted)
            let confirmedWeeks = store.effectiveWeeklyRecords(for: profile.id).filter { $0.state == .confirmed }.count
            let confirmedDays = store.dailyRecords(for: profile.id).filter { $0.state == .confirmed }.count
            Text("已确认 \(confirmedDays) 份日记录 · \(confirmedWeeks) 份周脉搏")
                .font(.caption.bold()).foregroundStyle(AppTheme.blue)
            if confirmedWeeks + confirmedDays == 0 {
                Text("还没有确认过的账期。可以先问记录方法，但涉及利润和趋势时不会生成替代数字。")
                    .font(.caption).foregroundStyle(AppTheme.amber)
            } else if !readiness.canExplainProfit {
                Label(readiness.title, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(AppTheme.amber)
                Text(readiness.detail).font(.caption2).foregroundStyle(AppTheme.muted)
            } else {
                Label("流水与成本已足够复算经营结余", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(AppTheme.mint)
            }
        }
        .appCard(contentPadding: 15)
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("你可以这样问", systemImage: "sparkles").font(.headline).foregroundStyle(AppTheme.blue)
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
            Text("选一个问题开始，也可以在下方直接补充你的具体情况。")
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
                    Label("结束本次复盘并生成报告", systemImage: "checkmark.seal.fill")
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
                Text("每次有效回复 1 财神币 · 失败自动退回")
                Spacer()
                Text("余额 \(communityStore.fortuneWallet?.balance ?? 0)")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 18)
            HStack(alignment: .bottom, spacing: 9) {
                TextField("问经营、成本、流量或顾客问题", text: $input, axis: .vertical)
                    .lineLimit(1...5).focused($focused).padding(12)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 17).stroke(focused ? AppTheme.blue.opacity(0.5) : AppTheme.border) }
                    .accessibilityIdentifier("operations.advisor.composer")
                Button { send(input) } label: {
                    Image(systemName: "arrow.up").font(.headline.bold()).foregroundStyle(.white).frame(width: 44, height: 44).background(canSend ? AppTheme.blue : AppTheme.muted.opacity(0.35), in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("发送经营问题")
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
            guard let reservation = await communityStore.reserveFortuneUsage(.operationsAdvisorTurn) else {
                return
            }
            input = ""
            focused = false
            if await store.sendQuestion(question, storeID: profile.id) {
                await communityStore.settleFortuneUsage(reservation)
            } else {
                await communityStore.refundFortuneUsage(reservation)
            }
        }
    }
    private func retry() {
        guard let value = conversation.messages.last?.content else { return }
        guard !isAuthorizingSpend else { return }
        isAuthorizingSpend = true
        Task {
            defer { isAuthorizingSpend = false }
            guard let reservation = await communityStore.reserveFortuneUsage(.operationsAdvisorTurn) else {
                return
            }
            if await store.sendQuestion(value, storeID: profile.id) {
                await communityStore.settleFortuneUsage(reservation)
            } else {
                await communityStore.refundFortuneUsage(reservation)
            }
        }
    }

    private func finishReview() {
        guard let kind = focus?.reviewKind else { return }
        let conclusion = conversation.messages.last(where: { $0.role == "assistant" })?.content ?? ""
        finishedReport = store.saveReviewReport(kind: kind, for: profile.id, advisorConclusion: conclusion)
        if let finishedReport {
            Task {
                await communityStore.recordFortuneEvent(
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
    var currencyYuan: String {
        formatted(.currency(code: "CNY").precision(.fractionLength(0...2)))
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
