import SwiftUI

@MainActor
struct ClipThumbnailView: View {
    let clip: ApprovedClip
    let repository: (any SocialRepository)?
    let onPlay: () -> Void

    @State private var model = ClipThumbnailModel()
    @State private var retryID = UUID()

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: onPlay) {
                ZStack {
                    AppTheme.accentSoft
                    if let image = model.image, model.loadedUserID == repository?.currentUserID {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                    } else if !model.isLoading && model.errorMessage == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title2)
                            Text("No cover available")
                                .font(.caption)
                        }
                        .foregroundStyle(AppTheme.secondaryInk)
                        .offset(y: 46)
                    }
                    GameGlyph(symbol: "play.fill", size: 40)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(.black.opacity(0.55), in: Circle())
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(repository?.currentUserID == nil)
            .accessibilityLabel("Watch \(clip.contentTitle) clip")

            if model.isLoading {
                ProgressView("Loading cover…")
                    .font(.caption)
                    .padding(8)
                    .background(AppTheme.surface.opacity(0.95), in: Capsule())
                    .padding(10)
            } else if let message = model.errorMessage {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    Button("Retry cover") { retryID = UUID() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Retry loading \(clip.contentTitle) cover")
                }
                .padding(8)
                .background(AppTheme.surface.opacity(0.95))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: loadID) { await model.load(clip: clip, repository: repository) }
        .onDisappear { model.clear() }
    }

    private var loadID: String {
        let account = repository?.currentUserID?.uuidString ?? "signed-out"
        return "\(account)|\(clip.id)|\(clip.thumbnailPath ?? "no-cover")|\(retryID)"
    }
}
