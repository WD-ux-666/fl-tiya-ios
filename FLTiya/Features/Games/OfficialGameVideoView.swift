import SafariServices
import SwiftUI

@MainActor
struct OfficialGameVideoCard: View {
    @State private var isShowingVideo = false

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    GameGlyph(symbol: "play.rectangle", size: 25)
                    Text("OFFICIAL GAME VIDEO")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.7)
                }
                .foregroundStyle(AppTheme.accent)

                Button { isShowingVideo = true } label: {
                    Image("OfficialVideoZZZMechaCover")
                        .resizable().scaledToFit()
                        .overlay {
                            GameGlyph(symbol: "play.fill", size: 29)
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 62, height: 62)
                                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.accent.opacity(0.6)))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Watch Journey to the Sky, the official Zenless Zone Zero teaser")

                Text("Version 3.3 Teaser · Journey to the Sky")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)

                Text("Watch the official Zenless Zone Zero teaser in the publisher’s YouTube player.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)

                Button {
                    isShowingVideo = true
                } label: {
                    HStack(spacing: 10) {
                        GameGlyph(symbol: "play.fill", size: 21)
                        Text("Watch official video").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Link(destination: Self.publisherURL) {
                    Label("Source: HoYoverse announcement", systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .frame(minHeight: 44)
                }
            }
        }
        .sheet(isPresented: $isShowingVideo) {
            OfficialVideoBrowser(url: Self.videoURL)
                .ignoresSafeArea()
        }
    }

    private static let publisherURL = URL(string: "https://www.hoyoverse.com/en-us/news/166759")!
    private static let videoURL = URL(string: "https://www.youtube.com/watch?v=4G2ZnN7kSDg")!
}

private struct OfficialVideoBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
