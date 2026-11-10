import SwiftUI

struct LoginIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                AppTheme.surface
                RadialGradient(colors: [AppTheme.violet.opacity(0.3), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: width)
                Canvas { context, size in
                    var path = Path()
                    for index in 0...12 {
                        let x = CGFloat(index) * 32
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        let y = CGFloat(index) * 32
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(path, with: .color(AppTheme.accent.opacity(0.07)), lineWidth: 0.7)
                }
                RoundedRectangle(cornerRadius: 36)
                    .fill(AppTheme.violet.opacity(0.12)).frame(width: width * 0.59, height: height * 0.64)
                    .rotationEffect(.degrees(20)).offset(x: 12, y: -4)
                RoundedRectangle(cornerRadius: 32)
                    .fill(LinearGradient(colors: [AppTheme.surfaceRaised, AppTheme.background],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(AppTheme.accent.opacity(0.45), lineWidth: 1.3))
                    .frame(width: width * 0.6, height: height * 0.63)
                    .rotationEffect(.degrees(-12))
                    .shadow(color: AppTheme.accent.opacity(0.13), radius: 25)
                GameGlyph(symbol: "gamecontroller", size: width * 0.37)
                    .foregroundStyle(AppTheme.accent).rotationEffect(.degrees(-12))
                    .offset(x: -width * 0.03, y: -height * 0.025)
                GameGlyph(symbol: "bubble.left", size: 32)
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 64, height: 64)
                    .background(AppTheme.violet, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.24)))
                    .rotationEffect(.degrees(12))
                    .offset(x: width * 0.29, y: height * 0.19)
                HStack(spacing: 6) {
                    GameGlyph(symbol: "sparkle", size: 12)
                    Text("PLAYER CONNECT").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.5)
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(AppTheme.background, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.accent.opacity(0.3)))
                .offset(x: -width * 0.16, y: height * 0.34)
                GameGlyph(symbol: "sparkle", size: 19).foregroundStyle(AppTheme.violet)
                    .offset(x: -width * 0.34, y: -height * 0.29)
            }
        }
        .aspectRatio(1.2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(AppTheme.border))
        .accessibilityHidden(true)
    }
}

#Preview { LoginIllustration().padding(24).background(AppTheme.background) }
