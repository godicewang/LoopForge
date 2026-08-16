import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(OperationsStore.self) private var operationsStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var startsEvaluation = false
    @State private var opensOperations = false
    @State private var opensSiteAdvisor = false
    @State private var opensOperatingAdvisor = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !appStore.serviceStatus.isReady {
                    ServiceStatusCard(status: appStore.serviceStatus) {
                        Task { await appStore.refreshServiceStatus() }
                    }
                }
                if let storageNotice = appStore.storageNotice {
                    InlineStatusCard(
                        title: "本机草稿需要处理",
                        detail: storageNotice,
                        tint: AppTheme.amber,
                        symbol: "externaldrive.badge.exclamationmark"
                    )
                }
                assistantLines
                integrityNotice
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            // The iOS 26 floating tab bar can overlay the end of a ScrollView.
            // Keep enough trailing room for the final transparency notice to be
            // scrolled fully above it.
            .padding(.bottom, 132)
        }
        .background(AppBackdrop())
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $startsEvaluation) {
            BusinessTypePickerView()
        }
        .navigationDestination(isPresented: $opensOperations) {
            OperationsHomeView()
        }
        .navigationDestination(isPresented: $opensSiteAdvisor) {
            AdvisorHomeView(initialLine: "site")
        }
        .navigationDestination(isPresented: $opensOperatingAdvisor) {
            AdvisorHomeView(initialLine: "operations")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 9) {
                    productIdentity
                    trustLabel
                }
            } else {
                HStack {
                    productIdentity
                    Spacer()
                    trustLabel
                }
            }

            Text("从开店判断，到经营改善")
                .font(.title.weight(.bold))
                .minimumScaleFactor(0.82)
                .foregroundStyle(AppTheme.ink)

            Text("开店前判断位置，开店后看清流水、成本与顾客变化；两条线各自独立，又能持续积累。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var productIdentity: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.magnifyingglass")
                .foregroundStyle(AppTheme.blue)
            Text("EasyBusiness")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var trustLabel: some View {
        Label("真实数据优先", systemImage: "checkmark.shield.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.mint)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    private var assistantLines: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("选择你的助手", caption: "开店前判断 · 开店后经营")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 14) {
                    openingAssistantModule
                    operationsAssistantModule
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    openingAssistantModule
                    operationsAssistantModule
                }
                .frame(height: 330)
            }
        }
    }

    private var openingAssistantModule: some View {
        AssistantModuleCard(
            phase: "开店前",
            title: "开店助手",
            detail: "判断位置、客群、竞争、收益与回本。",
            context: appStore.latestAdvisorReports.first.map { "最近：\($0.place.name)" } ?? "从一个真实位置开始",
            symbol: "mappin.and.ellipse",
            gradientEnd: AppTheme.blue,
            primaryTitle: "开始新评估",
            primaryIdentifier: "dashboard.startEvaluation",
            primaryHint: "开始一次新的真实选址评估",
            primaryAction: {
                if appStore.startNewEvaluation() {
                    startsEvaluation = true
                }
            },
            historyTitle: "点位对话",
            historyIdentifier: "dashboard.siteAdvisorHistory",
            historyAction: { opensSiteAdvisor = true }
        )
        .accessibilityIdentifier("dashboard.siteAssistantModule")
    }

    private var operationsAssistantModule: some View {
        AssistantModuleCard(
            phase: "开店后",
            title: "经营助手",
            detail: "跟踪流水、成本、复购，完成周脉搏与月复盘。",
            context: operationsStore.selectedProfile.map { "最近：\($0.name)" } ?? "先建立一份门店档案",
            symbol: "waveform.path.ecg.rectangle.fill",
            gradientEnd: AppTheme.blue,
            primaryTitle: operationsStore.workspace.profiles.isEmpty ? "建立门店" : "进入经营台",
            primaryIdentifier: "dashboard.openOperations",
            primaryHint: "进入每周经营脉搏、每月复盘和经营顾问",
            primaryAction: { opensOperations = true },
            historyTitle: "门店对话",
            historyIdentifier: "dashboard.operatingAdvisorHistory",
            historyAction: { opensOperatingAdvisor = true }
        )
        .accessibilityIdentifier("dashboard.operationsAssistantModule")
    }

    private var integrityNotice: some View {
        InlineStatusCard(
            title: "把建议用作经营核验清单",
            detail: "重要决定仍应结合现场情况、真实账目与最新经营信息复核。",
            tint: AppTheme.periwinkle,
            symbol: "shield.lefthalf.filled"
        )
    }
}

private struct AssistantModuleCard: View {
    let phase: String
    let title: String
    let detail: String
    let context: String
    let symbol: String
    let gradientEnd: Color
    let primaryTitle: String
    let primaryIdentifier: String
    let primaryHint: String
    let primaryAction: () -> Void
    let historyTitle: String
    let historyIdentifier: String
    let historyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 0.8)
                    }
                Spacer(minLength: 8)
                Text(phase)
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.11), in: Capsule())
            }

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.top, 16)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Label(context, systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.top, 13)

            Spacer(minLength: 14)

            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 3)
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                }
                .foregroundStyle(AppTheme.navy)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityHint(primaryHint)
            .accessibilityIdentifier(primaryIdentifier)

            Button(action: historyAction) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text(historyTitle)
                    Spacer(minLength: 3)
                    Image(systemName: "chevron.right")
                }
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                }
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityIdentifier(historyIdentifier)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [AppTheme.navy, AppTheme.deepClay, gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: AppTheme.navy.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
    }
}
