import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.035, green: 0.051, blue: 0.086)
    static let surface = Color(red: 0.078, green: 0.106, blue: 0.169)
    static let surfaceRaised = Color(red: 0.110, green: 0.149, blue: 0.220)
    static let accent = Color(red: 0.271, green: 0.957, blue: 0.773)
    static let violet = Color(red: 0.588, green: 0.455, blue: 1.000)
    static let accentSoft = Color(red: 0.066, green: 0.184, blue: 0.176)
    static let ink = Color(red: 0.941, green: 0.957, blue: 1.000)
    static let secondaryInk = Color(red: 0.616, green: 0.667, blue: 0.757)
    static let border = Color(red: 0.165, green: 0.208, blue: 0.294)
    static let onAccent = Color(red: 0.020, green: 0.090, blue: 0.078)
}

struct AppBackdrop: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.background
            RadialGradient(colors: [AppTheme.violet.opacity(0.11), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 440)
            RadialGradient(colors: [AppTheme.accent.opacity(0.055), .clear], center: .leading,
                           startRadius: 0, endRadius: 350)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GameHeroHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var sticker: ArcadeStickerKind? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.3).foregroundStyle(AppTheme.accent)
                Text(title).font(.system(.largeTitle, design: .rounded, weight: .black))
                    .tracking(-0.8).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).lineSpacing(3)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let sticker {
                ArcadeSticker(kind: sticker, size: 84)
                    .padding(.top, 4)
            } else if symbol == "sparkles" {
                ArcadeSticker(kind: .sparks, size: 68)
                    .frame(width: 68, height: 76)
                    .padding(.top, 10)
            } else {
                GameGlyph(symbol: symbol, size: 40)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 68, height: 76)
                    .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.accent.opacity(0.28)))
                    .rotationEffect(.degrees(8))
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

struct AppCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [AppTheme.surfaceRaised.opacity(0.65), AppTheme.surface],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(LinearGradient(colors: [AppTheme.border, AppTheme.border.opacity(0.45)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26).fill(AppTheme.violet.opacity(0.07))
                    .frame(width: 112, height: 112).rotationEffect(.degrees(15))
                RoundedRectangle(cornerRadius: 26).stroke(AppTheme.violet.opacity(0.2), lineWidth: 1)
                    .frame(width: 112, height: 112).rotationEffect(.degrees(15))
                RoundedRectangle(cornerRadius: 22).fill(AppTheme.accentSoft)
                    .frame(width: 86, height: 86)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.accent.opacity(0.2), lineWidth: 1))
                GameGlyph(symbol: symbol, size: 42).foregroundStyle(AppTheme.accent)
            }
            .padding(.bottom, 6)
            .accessibilityHidden(true)
            Text(title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(AppTheme.ink)
            Text(message).font(.subheadline).lineSpacing(4).foregroundStyle(AppTheme.secondaryInk)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 310)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 38)
        .accessibilityElement(children: .combine)
    }
}

struct FeatureUnavailableView: View {
    let title: String
    let symbol: String
    let message: String
    var body: some View {
        ScrollView { EmptyStateView(symbol: symbol, title: title, message: message).padding(.top, 40) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background { AppBackdrop() }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct AvatarPlaceholder: View {
    var size: CGFloat = 72
    var body: some View {
        ArcadeSticker(kind: .avatar, size: size)
    }
}
