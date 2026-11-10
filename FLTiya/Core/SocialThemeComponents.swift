import SwiftUI

/// Original raster artwork gives each social page its own arcade-club identity.
enum SocialTheme {
    case players
    case messages
    case profile

    var tint: Color {
        switch self {
        case .players: AppTheme.accent
        case .messages: AppTheme.violet
        case .profile: Color(red: 1.0, green: 0.79, blue: 0.43)
        }
    }

    var secondaryTint: Color {
        switch self {
        case .players: Color(red: 0.25, green: 0.72, blue: 1.0)
        case .messages: Color(red: 0.96, green: 0.48, blue: 0.79)
        case .profile: AppTheme.violet
        }
    }

    var artwork: String {
        switch self {
        case .players: "SocialPlayersArtwork"
        case .messages: "SocialMessagesArtwork"
        case .profile: "SocialProfileArtwork"
        }
    }

    var badge: String {
        switch self {
        case .players: "DockPlayers"
        case .messages: "DockMessages"
        case .profile: "DockProfile"
        }
    }
}

struct SocialThemeBackdrop: View {
    let theme: SocialTheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                AppTheme.background
                Image(theme.artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(0.19)
                LinearGradient(colors: [AppTheme.background.opacity(0.20), AppTheme.background.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [AppTheme.background.opacity(0.65), .clear],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SocialThemeHero: View {
    let theme: SocialTheme
    let eyebrow: String
    let title: String
    let subtitle: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow.uppercased())
                .font(.system(.caption2, design: .monospaced, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(theme.tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.system(.title, design: .rounded, weight: .black))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 0 : 130)
        .padding(22)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 210 : 168, alignment: .leading)
        .background {
            GeometryReader { geometry in
                ZStack {
                    Image(theme.artwork)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    LinearGradient(stops: [
                        .init(color: AppTheme.background.opacity(0.94), location: 0),
                        .init(color: AppTheme.background.opacity(0.72), location: 0.43),
                        .init(color: AppTheme.background.opacity(dynamicTypeSize.isAccessibilitySize ? 0.65 : 0.05), location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .clipShape(SocialPanelOutline())
        .overlay {
            SocialPanelOutline().strokeBorder(theme.tint.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SocialThemePanel<Content: View>: View {
    let theme: SocialTheme
    private let content: Content

    init(theme: SocialTheme, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                GeometryReader { geometry in
                    ZStack {
                        AppTheme.surface
                        Image(theme.artwork)
                            .resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .opacity(0.11)
                        LinearGradient(colors: [AppTheme.surface.opacity(0.72), AppTheme.surface.opacity(0.30)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .clipShape(SocialPanelOutline())
            .overlay {
                SocialPanelOutline()
                    .strokeBorder(LinearGradient(colors: [theme.tint.opacity(0.40), AppTheme.border,
                                                           theme.secondaryTint.opacity(0.20)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// A generated sticker, decorative alongside a native, accessible text label.
struct SocialArtworkBadge: View {
    let theme: SocialTheme
    var size: CGFloat = 64

    var body: some View {
        Image(theme.badge)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Small, original raster marks shared by discovery, default avatars and Sparks.
enum ArcadeStickerKind: String {
    case search = "StickerSearch"
    case players = "StickerPlayers"
    case avatar = "StickerAvatar"
    case device = "StickerDevice"
    case sparks = "StickerSparks"
    case settings = "StickerSettings"
    case privacy = "StickerPrivacy"
    case support = "StickerSupport"
}

struct ArcadeSticker: View {
    let kind: ArcadeStickerKind
    var size: CGFloat = 32

    var body: some View {
        Image(kind.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SocialPanelOutline: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut: CGFloat = min(14, min(bounds.width, bounds.height) * 0.15)
        var path = Path()
        path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX - cut, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + cut))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX + cut, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - cut))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var result = self
        result.insetAmount += amount
        return result
    }
}

/// Angular edges and an offset ink layer echo the artwork; the title and tap
/// target remain native and accessible.
struct SocialEditorButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(isPrimary ? AppTheme.onAccent : AppTheme.ink)
            .padding(.horizontal, 18).frame(minHeight: 44)
            .background {
                SocialEditorButtonOutline().fill(isPrimary ? SocialTheme.profile.tint : AppTheme.surfaceRaised)
                    .shadow(color: isPrimary ? AppTheme.violet.opacity(0.75) : .black.opacity(0.7), radius: 0,
                            x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            }
            .overlay {
                SocialEditorButtonOutline().stroke(isPrimary ? AppTheme.ink.opacity(0.75) : SocialTheme.profile.tint.opacity(0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(0..<3) { _ in
                        Rectangle().fill(isPrimary ? AppTheme.onAccent.opacity(0.5) : SocialTheme.profile.tint.opacity(0.65))
                            .frame(width: 3, height: 5).rotationEffect(.degrees(28))
                    }
                }
                .padding(.leading, 11).padding(.top, 4)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.45).contentShape(Rectangle())
    }
}

struct SocialEditorButtonOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let cut: CGFloat = 9
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}
