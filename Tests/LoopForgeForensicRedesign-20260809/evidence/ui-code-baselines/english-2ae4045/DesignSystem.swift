import PhotosUI
import SwiftUI
import UIKit

/// Shared warm foundation palette. Assessment, advisory, and storefront
/// surfaces select accents by meaning without introducing a separate cold theme.
enum ProductPalette {
    static let primary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.52, blue: 0.43, alpha: 1)
            : UIColor(red: 0.69, green: 0.27, blue: 0.21, alpha: 1)
    })
    static let brandDark = Color(red: 0.18, green: 0.12, blue: 0.14)
    static let deepClay = Color(red: 0.34, green: 0.15, blue: 0.14)
    static let violet = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.84, green: 0.56, blue: 0.67, alpha: 1)
            : UIColor(red: 0.55, green: 0.32, blue: 0.42, alpha: 1)
    })
    static let positive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.72, blue: 0.61, alpha: 1)
            : UIColor(red: 0.15, green: 0.46, blue: 0.37, alpha: 1)
    })
    static let danger = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.45, blue: 0.49, alpha: 1)
            : UIColor(red: 0.74, green: 0.24, blue: 0.28, alpha: 1)
    })
    static let highlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.70, blue: 0.37, alpha: 1)
            : UIColor(red: 0.79, green: 0.43, blue: 0.10, alpha: 1)
    })
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.060, blue: 0.060, alpha: 1)
            : UIColor(red: 0.969, green: 0.946, blue: 0.905, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.115, green: 0.090, blue: 0.088, alpha: 1)
            : UIColor(red: 0.992, green: 0.976, blue: 0.945, alpha: 1)
    })
    static let raisedSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.150, green: 0.116, blue: 0.110, alpha: 1)
            : UIColor(red: 1.000, green: 0.994, blue: 0.980, alpha: 1)
    })
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor(red: 0.36, green: 0.22, blue: 0.17, alpha: 0.12)
    })
}

enum AppTheme {
    static let navy = ProductPalette.brandDark
    static let deepClay = ProductPalette.deepClay
    static let ink = Color(uiColor: .label)
    static let blue = ProductPalette.primary
    static let periwinkle = ProductPalette.violet
    static let mint = ProductPalette.positive
    static let amber = ProductPalette.highlight
    static let red = ProductPalette.danger
    static let canvas = ProductPalette.paper
    static let surface = ProductPalette.surface
    static let card = ProductPalette.raisedSurface
    static let border = ProductPalette.hairline
    static let muted = Color(uiColor: .secondaryLabel)

    static let solidBlue = ProductPalette.primary
    static let solidMint = ProductPalette.positive
}

/// A lightweight warm glow derived from the community background. Paper-like
/// surfaces remain dominant so color does not compete with reports or maps.
struct AppBackdrop: View {
    var accent: Color = AppTheme.blue

    var body: some View {
        ZStack(alignment: .topLeading) {
            AppTheme.canvas
            LinearGradient(
                colors: [
                    accent.opacity(0.075),
                    AppTheme.amber.opacity(0.040),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension ReportDecision {
    var tint: Color {
        switch self {
        case .recommended: AppTheme.mint
        case .cautious: AppTheme.amber
        case .notRecommended: AppTheme.red
        }
    }

    var softTint: Color {
        tint.opacity(0.13)
    }
}

extension EvidenceKind {
    var tint: Color {
        switch self {
        case .opportunity: AppTheme.mint
        case .risk: AppTheme.amber
        case .neutral: AppTheme.periwinkle
        }
    }

    var symbol: String {
        switch self {
        case .opportunity: "arrow.up.right.circle.fill"
        case .risk: "exclamationmark.circle.fill"
        case .neutral: "info.circle.fill"
        }
    }
}

extension DataConfidence {
    var tint: Color {
        switch level {
        case "A": AppTheme.mint
        case "B": AppTheme.amber
        default: AppTheme.red
        }
    }
}

extension View {
    func appCard(contentPadding: CGFloat = 16) -> some View {
        padding(contentPadding)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.060), radius: 16, y: 8)
    }
}

/// A subtle, system-like pressed state for custom cards that otherwise use a
/// plain button style. It gives touch confirmation without relying on motion.
struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SectionTitle: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleText
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 3) {
                titleText
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.headline.bold())
            .foregroundStyle(AppTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TagPill: View {
    let title: String
    var tint: Color = AppTheme.blue

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

struct PrimaryActionLabel: View {
    let title: String
    var systemImage: String = "arrow.right"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.bold())
            Spacer()
            Image(systemName: "arrow.right")
                .font(.caption.bold())
                .frame(width: 28, height: 28)
                .foregroundStyle(AppTheme.solidBlue)
                .background(.white, in: Circle())
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(
            LinearGradient(colors: [AppTheme.navy, AppTheme.solidBlue], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    var tint: Color = AppTheme.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(title)
            }
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct FinanceStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScoreBadge: View {
    let score: Int
    let decision: ReportDecision

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.28), lineWidth: 8)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(score)")
                    .font(.title2.bold())
                Text("Site Score")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 84, height: 84)
        .accessibilityLabel("Site Score: \(score)")
    }
}

struct FeatureIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.bold())
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct InlineStatusCard: View {
    let title: String
    let detail: String
    let tint: Color
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

struct ServiceStatusCard: View {
    let status: AnalysisServiceStatus
    var serviceName = "Analysis Service"
    var detail: String?
    var retry: (() -> Void)?

    private var tint: Color {
        switch status {
        case .ready: AppTheme.mint
        case .checking: AppTheme.periwinkle
        case .unconfigured: AppTheme.amber
        case .unavailable: AppTheme.red
        }
    }

    private var symbol: String {
        switch status {
        case .ready: "checkmark.icloud.fill"
        case .checking: "arrow.triangle.2.circlepath.icloud.fill"
        case .unconfigured: "network.slash"
        case .unavailable: "exclamationmark.icloud.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Group {
                    if case .checking = status {
                        ProgressView()
                    } else {
                        Image(systemName: symbol)
                    }
                }
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(serviceName): \(status.title)")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(
                        UserFacingCopy.externalMessage(
                            detail ?? status.detail,
                            fallback: "The service is temporarily unavailable. Try again."
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .unavailable = status, let retry {
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(tint)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

struct VisualEvidenceSection: View {
    @Environment(AppStore.self) private var appStore
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var consentGranted = false

    var body: some View {
        @Bindable var store = appStore
        let photoPickerTitle = store.visualEvidence.isEmpty ? "Select On-Site Photos" : "Add On-Site Photos"
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("On-Site Visual Evidence")
                    .font(.headline.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 12)
                Text("\(store.visualEvidence.count) / 3")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.blue)
            }
            Text("Optional, up to 3 photos")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Text("Add storefront, sidewalk, or entrance photos. Avoid identifiable people.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Label("Temporary; not saved in reports or drafts.", systemImage: "lock.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.periwinkle)
            if let notice = store.visualEvidenceNotice {
                Label(notice, systemImage: "checkmark.shield.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("I confirm I have authorization to use these images", isOn: $consentGranted)
                .font(.subheadline.weight(.medium))
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(1, 3 - store.visualEvidence.count),
                matching: .images
            ) {
                Label(
                    photoPickerTitle,
                    systemImage: "camera.viewfinder"
                )
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(!consentGranted || store.visualEvidence.count >= 3)
            .opacity(consentGranted && store.visualEvidence.count < 3 ? 1 : 0.48)
            ForEach(Array(store.visualEvidence.enumerated()), id: \.element.id) { index, evidence in
                HStack(spacing: 10) {
                    Image(systemName: "photo.fill")
                        .foregroundStyle(AppTheme.periwinkle)
                    Text("On-Site Photo \(index + 1) · Authorized")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Button(role: .destructive) {
                        store.removeVisualEvidence(id: evidence.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Remove On-Site Photo \(index + 1)")
                }
                .padding(10)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .appCard()
        .onChange(of: selectedPhotoItems) { _, items in
            let locationIDWhenChosen = store.selectedLocation?.id
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        appStore.lastError = .transport(message: "Unable to read selected on-site photo")
                        continue
                    }
                    guard appStore.selectedLocation?.id == locationIDWhenChosen else {
                        appStore.visualEvidenceNotice = "Candidate site changed; on-site photos from the previous site were not added."
                        break
                    }
                    appStore.addAuthorizedVisualEvidence(from: data)
                }
                selectedPhotoItems = []
            }
        }
        .onChange(of: store.visualEvidence.count) { oldCount, newCount in
            // A point change clears in-memory evidence in AppStore. Require an
            // explicit new acknowledgement before photos for the new point can
            // be selected, rather than carrying consent across locations.
            if oldCount > 0, newCount == 0 {
                consentGranted = false
            }
        }
        .onChange(of: store.selectedLocation?.id) { _, _ in
            // This also covers a point change while PhotosPicker is still
            // loading data and no evidence has been appended yet.
            consentGranted = false
        }
    }
}
