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
                        title: "Local draft requires processing",
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
        .accessibilityIdentifier("dashboard.scroll")
        .background(AppBackdrop())
        // A hidden navigation bar leaves the scroll view extending behind the
        // status bar. Keep an opaque, fixed safe-area curtain above scrolling
        // content so oversized text never paints through the system status
        // items as the dashboard moves.
        .safeAreaInset(edge: .top, spacing: 0) {
            Rectangle()
                .fill(AppTheme.canvas)
                .frame(height: 1)
                .background(AppTheme.canvas.ignoresSafeArea(edges: .top))
                .accessibilityHidden(true)
        }
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

            Text("Plan with evidence. Operate with facts.")
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Assess before signing. Track sales and costs after opening.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var productIdentity: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "location.magnifyingglass")
                        .foregroundStyle(AppTheme.blue)
                    Text("EasyBusiness")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "location.magnifyingglass")
                        .foregroundStyle(AppTheme.blue)
                    Text("EasyBusiness")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("EasyBusiness")
    }

    private var trustLabel: some View {
        Label("Real Data First", systemImage: "checkmark.shield.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.mint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var assistantLines: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Choose a Workspace", caption: "Plan or operate")

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
            }
        }
    }

    private var openingAssistantModule: some View {
        AssistantModuleCard(
            phase: "Planning",
            title: "Site Advisor",
            detail: "Review demand, access, competition, and payback.",
            context: appStore.latestAdvisorReports.first.map { "Recent: \($0.place.name)" } ?? "No site yet",
            symbol: "mappin.and.ellipse",
            gradientEnd: AppTheme.blue,
            primaryTitle: "Assess a Site",
            primaryIdentifier: "dashboard.startEvaluation",
            primaryHint: "Start a site assessment using a real location",
            primaryAction: {
                if appStore.startNewEvaluation() {
                    startsEvaluation = true
                }
            },
            historyTitle: "View Chats",
            historyIdentifier: "dashboard.siteAdvisorHistory",
            historyAction: { opensSiteAdvisor = true }
        )
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 330)
        .accessibilityIdentifier("dashboard.siteAssistantModule")
    }

    private var operationsAssistantModule: some View {
        AssistantModuleCard(
            phase: "Running",
            title: "Operations Advisor",
            detail: "Track results and review weekly or monthly progress.",
            context: operationsStore.selectedProfile.map { "Recent: \($0.name)" } ?? "No store yet",
            symbol: "waveform.path.ecg.rectangle.fill",
            gradientEnd: AppTheme.blue,
            primaryTitle: operationsStore.workspace.profiles.isEmpty ? "Add Store" : "Open Dashboard",
            primaryIdentifier: "dashboard.openOperations",
            primaryHint: "Access weekly operations pulse, monthly reviews, and Operations Advisor",
            primaryAction: { opensOperations = true },
            historyTitle: "View Chats",
            historyIdentifier: "dashboard.operatingAdvisorHistory",
            historyAction: { opensOperatingAdvisor = true }
        )
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 330)
        .accessibilityIdentifier("dashboard.operationsAssistantModule")
    }

    private var integrityNotice: some View {
        InlineStatusCard(
            title: "Verify the site",
            detail: "Check conditions, lease terms, permits, and records.",
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
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.11), in: Capsule())
            }

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Label(context, systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)

            Spacer(minLength: 14)

            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    Text(primaryTitle)
                        .font(.caption.bold())
                        .fixedSize(horizontal: false, vertical: true)
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
            .accessibilityLabel(primaryTitle)
            .accessibilityHint(primaryHint)
            .accessibilityIdentifier(primaryIdentifier)

            Button(action: historyAction) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text(historyTitle)
                        .fixedSize(horizontal: false, vertical: true)
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
            .accessibilityLabel(historyTitle)
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
