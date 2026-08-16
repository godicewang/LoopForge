import SwiftUI
import UIKit

/// 创业圈使用低饱和暖色体系：陶土色承担主要行动，琥珀用于少量高光，
/// 奶油白承托长内容。整体有温度但不追求发光感或高饱和撞色。
enum CommunityTheme {
    static let cobalt = ProductPalette.primary
    static let indigo = ProductPalette.brandDark
    static let deepClay = ProductPalette.deepClay
    static let violet = ProductPalette.violet
    static let aqua = ProductPalette.positive
    static let coral = ProductPalette.danger
    static let warm = ProductPalette.highlight
    static let paper = ProductPalette.paper
    static let surface = ProductPalette.surface
    static let raisedSurface = ProductPalette.raisedSurface
    static let hairline = ProductPalette.hairline

}

struct CommunityBackdrop: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            CommunityTheme.paper
            LinearGradient(
                colors: [
                    CommunityTheme.cobalt.opacity(0.075),
                    CommunityTheme.warm.opacity(0.040),
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

struct CommunityBrandMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CommunityTheme.cobalt, CommunityTheme.warm],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: size * 0.70, height: size * 0.70)
            Image(systemName: "person.2.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: size, height: size)
        .shadow(color: CommunityTheme.cobalt.opacity(0.17), radius: 11, y: 6)
        .accessibilityHidden(true)
    }
}

struct CommunityIconButton: View {
    let symbol: String
    var accent: Bool = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(accent ? CommunityTheme.warm : AppTheme.ink)
            .frame(width: 44, height: 44)
            .background(
                accent ? AnyShapeStyle(CommunityTheme.indigo) : AnyShapeStyle(CommunityTheme.raisedSurface),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent ? Color.clear : CommunityTheme.hairline, lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(accent ? 0.13 : 0.035), radius: 8, y: 4)
    }
}

struct CommunitySectionHeading: View {
    let title: String
    var caption: String?
    var symbol: String?
    var tint: Color = CommunityTheme.cobalt

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 4)
            }
            if let caption {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, symbol == nil ? 0 : 25)
            }
        }
    }
}

struct CommunityRoleBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CommunityTheme.cobalt)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(CommunityTheme.cobalt.opacity(0.075), in: Capsule())
            .overlay { Capsule().stroke(CommunityTheme.cobalt.opacity(0.14), lineWidth: 0.6) }
    }
}

private struct CommunitySurfaceModifier: ViewModifier {
    let radius: CGFloat
    let elevated: Bool
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                elevated ? CommunityTheme.raisedSurface : CommunityTheme.surface,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(CommunityTheme.hairline, lineWidth: elevated ? 0.8 : 0.6)
            }
            .shadow(
                color: Color.black.opacity(elevated ? 0.065 : 0.018),
                radius: elevated ? 16 : 5,
                y: elevated ? 8 : 2
            )
    }
}

extension View {
    func communitySurface(
        radius: CGFloat = 22,
        elevated: Bool = false,
        padding: CGFloat = 16
    ) -> some View {
        modifier(CommunitySurfaceModifier(radius: radius, elevated: elevated, padding: padding))
    }
}

extension CommunityPostType {
    var communityTint: Color {
        switch self {
        case .experience: CommunityTheme.aqua
        case .question: CommunityTheme.cobalt
        case .project: CommunityTheme.violet
        case .investment: CommunityTheme.warm
        case .resource: CommunityTheme.coral
        }
    }
}
