import SwiftUI

/// Presentation is local; game IDs and player data remain owned by the repository.
struct GameAppearance {
    let accent: Color
    let background: Color
    let surface: Color
    let ink: Color
    let secondaryInk: Color
    let isDark: Bool
    let symbol: String

    init(game: GameDescriptor) {
        let palette: (UInt32, UInt32, UInt32, Bool, String)
        switch game.id {
        case "zenless-zone-zero": palette = (0xF5E600, 0x171819, 0x262829, true, "bolt.shield.fill")
        case "minecraft": palette = (0x9BD76B, 0x182B24, 0x263C31, true, "square.stack.3d.up.fill")
        case "pubg-mobile": palette = (0xFFC05A, 0x18232C, 0x263540, true, "scope")
        case "zero-ad": palette = (0xE4C080, 0x2B2520, 0x3B332A, true, "building.columns.fill")
        case "minetest": palette = (0x77D9C1, 0x132E2E, 0x20403E, true, "square.grid.3x3.fill")
        case "supertuxkart": palette = (0xF8AA3D, 0xEAF3FB, 0xFFFFFF, false, "flag.checkered")
        case "freedoom": palette = (0xF38472, 0x271D25, 0x3B2933, true, "flame.fill")
        case "bobs-game": palette = (0xCEADFA, 0x241D39, 0x352A50, true, "dpad.fill")
        case "guacamelee": palette = (0xF37A42, 0xF9EFD9, 0xFFFAEE, false, "sun.max.fill")
        case "manifold-garden": palette = (0x899BEB, 0xEDF0FA, 0xFFFFFF, false, "cube.transparent.fill")
        case "fantastic-contraption": palette = (0xACD168, 0x23312D, 0x34443C, true, "gearshape.2.fill")
        case "push-me-pull-you": palette = (0xD96B8E, 0xFBEDF2, 0xFFFFFF, false, "figure.2")
        default: palette = (0x63CBB4, 0x173732, 0x254A43, true, "gamecontroller.fill")
        }
        accent = Color(gameHex: palette.0)
        background = Color(gameHex: palette.1)
        surface = Color(gameHex: palette.2)
        isDark = palette.3
        symbol = palette.4
        ink = isDark ? .white : Color(gameHex: 0x202831)
        secondaryInk = ink.opacity(isDark ? 0.72 : 0.66)
    }
}

enum GameArtworkKind: Equatable { case icon, cover }

struct GameArtworkView: View {
    let game: GameDescriptor
    let kind: GameArtworkKind

    private var assetName: String? {
        switch kind {
        case .icon: GameArtworkCatalog.iconName(for: game.id) ?? GameArtworkCatalog.coverName(for: game.id)
        case .cover: GameArtworkCatalog.coverName(for: game.id)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if let assetName {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: kind == .icon && GameArtworkCatalog.iconName(for: game.id) != nil ? .fit : .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(GameAppearance(game: game).surface)
                    .clipped()
            } else {
                let theme = GameAppearance(game: game)
                ZStack {
                    theme.surface
                    GamePattern(game: game).foregroundStyle(theme.accent.opacity(0.2))
                    Text(game.monogram)
                        .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.23,
                                      weight: .black, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .accessibilityLabel(game.name)
    }
}

/// Original native motifs keep every game distinct even without publisher artwork.
struct GameThemeBackdrop: View {
    let game: GameDescriptor

    var body: some View {
        let theme = GameAppearance(game: game)
        ZStack {
            theme.background
            if GameArtworkCatalog.coverName(for: game.id) != nil {
                GameArtworkView(game: game, kind: .cover)
                    .opacity(0.38)
            }
            GamePattern(game: game)
                .foregroundStyle(theme.accent.opacity(0.18))
            LinearGradient(colors: [.clear, theme.background.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct GamePattern: View {
    let game: GameDescriptor

    var body: some View {
        Canvas { context, size in
            var path = Path()
            switch game.id {
            case "zenless-zone-zero", "pubg-mobile", "freedoom":
                for index in -2..<8 {
                    let x = CGFloat(index) * 90
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + 90, y: 0))
                    path.addLine(to: CGPoint(x: x - 70, y: size.height))
                    path.addLine(to: CGPoint(x: x - 160, y: size.height))
                    path.closeSubpath()
                }
            case "minecraft", "minetest", "manifold-garden":
                for row in 0..<6 {
                    for column in 0..<8 where (row + column) % 3 == 0 {
                        path.addRect(CGRect(x: CGFloat(column) * 62 - CGFloat(row % 2) * 20,
                                            y: CGFloat(row) * 62, width: 48, height: 48))
                    }
                }
            default:
                for index in 0..<6 {
                    let radius = CGFloat(index + 1) * 55
                    path.addEllipse(in: CGRect(x: size.width - radius, y: -radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
            if ["zenless-zone-zero", "pubg-mobile", "freedoom", "minecraft", "minetest", "manifold-garden"].contains(game.id) {
                context.fill(path, with: .foreground)
            } else {
                context.stroke(path, with: .foreground, lineWidth: 14)
            }
        }
    }
}

struct GameHeroCard: View {
    let game: GameDescriptor

    var body: some View {
        let theme = GameAppearance(game: game)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                GameArtworkView(game: game, kind: .icon)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2)))
                Spacer()
                Text("GAME SPACE")
                    .font(.caption2.weight(.black)).tracking(1.8)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(theme.isDark ? theme.background : theme.ink)
                    .background(theme.accent, in: Capsule())
            }
            Spacer(minLength: 16)
            Text(game.name)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(game.introduction)
                .font(.subheadline).foregroundStyle(theme.secondaryInk)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background { GameThemeBackdrop(game: game) }
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }
}

private extension Color {
    init(gameHex: UInt32) {
        self.init(.sRGB, red: Double((gameHex >> 16) & 255) / 255,
                  green: Double((gameHex >> 8) & 255) / 255,
                  blue: Double(gameHex & 255) / 255, opacity: 1)
    }
}
