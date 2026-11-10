import AVKit
import Combine
import SwiftUI

@MainActor
struct ClipPlaybackView: View {
    let clip: ApprovedClip
    let repository: any SocialRepository
    let presentingUserID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ClipPlaybackModel()
    @State private var playback: PreparedClipPlayback?
    @State private var playbackError: String?
    @State private var reloadID = UUID()
    @State private var generation = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    playerSurface
                    Text(clip.contentTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    ClipCreditsView(clip: clip)
                }
                .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(clip.contentCategory == .lifestyle ? "Creator clip" : "Game clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        stopAndCleanUp()
                        dismiss()
                    }
                }
            }
        }
        .tint(AppTheme.accent)
        .task(id: reloadID) { await preparePlayback() }
        .onDisappear { stopAndCleanUp() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback?.player.pause() }
            if repository.currentUserID != presentingUserID {
                stopAndCleanUp()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        if let playback {
            VideoPlayer(player: playback.player)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onReceive(playback.item.publisher(for: \.status)) { status in
                    if status == .failed { showPlaybackFailure() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
                    guard let item = notification.object as? AVPlayerItem, item === playback.item else { return }
                    showPlaybackFailure()
                }
        } else {
            AppCard {
                VStack(spacing: 14) {
                    if let message = playbackError ?? model.errorMessage {
                        GameGlyph(symbol: "play.rectangle", size: 30)
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                        Button("Try again") { reloadID = UUID() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        ProgressView()
                        Text("Opening clip…")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }

    private func preparePlayback() async {
        stopAndCleanUp()
        playbackError = nil
        let request = generation
        await model.load(clip: clip, repository: repository, presentingUserID: presentingUserID)
        guard generation == request, !Task.isCancelled else { return }
        guard repository.currentUserID == presentingUserID else {
            stopAndCleanUp()
            dismiss()
            return
        }
        guard let file = model.fileURL else { return }
        do {
            // AVPlayer only receives a local URL, never an authenticated remote URL.
            let asset = AVURLAsset(url: file)
            let isPlayable = try await asset.load(.isPlayable)
            guard generation == request, !Task.isCancelled else { return }
            guard repository.currentUserID == presentingUserID else {
                stopAndCleanUp()
                dismiss()
                return
            }
            guard model.fileURL == file else { return }
            guard isPlayable else { throw SocialDataFailure.invalidClipMedia }
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            playback = PreparedClipPlayback(player: player, item: item)
            if scenePhase == .active { player.play() }
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            guard repository.currentUserID == presentingUserID else {
                stopAndCleanUp()
                dismiss()
                return
            }
            showPlaybackFailure()
        }
    }

    private func showPlaybackFailure() {
        stopAndCleanUp()
        playbackError = "This video couldn't be played. Please try again."
    }

    private func stopAndCleanUp() {
        generation = UUID()
        playback?.player.pause()
        playback?.player.replaceCurrentItem(with: nil)
        playback = nil
        model.clear()
    }
}

private struct PreparedClipPlayback {
    let player: AVPlayer
    let item: AVPlayerItem
}

struct ClipCreditsView: View {
    let clip: ApprovedClip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(clip.categoryTitle, systemImage: clip.categorySymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("About this clip · Source & credits")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryInk)
            // Plain, selectable text preserves the complete attribution and source
            // URL without interpreting third-party captions as Markdown or commands.
            Text(verbatim: clip.caption)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let notice = supplementalNotice {
                Divider().padding(.vertical, 8)
                Text("Game artwork license notice")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                Text(verbatim: notice)
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var supplementalNotice: String? {
        switch clip.id {
        case ClipSupplementalLicenses.freedoomPostID:
            return ClipSupplementalLicenses.freedoomNotice
                ?? "The bundled Freedoom license notice couldn't be opened."
        case ClipSupplementalLicenses.superTuxKartPostID:
            return ClipSupplementalLicenses.superTuxKartNotice
        default:
            return nil
        }
    }
}

private enum ClipSupplementalLicenses {
    static let freedoomPostID = UUID(uuidString: "df55c5a2-7441-54fa-acd8-8429d331bda9")!
    static let superTuxKartPostID = UUID(uuidString: "0266cd87-d7a3-53a6-8a08-6f454c48a6a5")!
    static let freedoomNotice: String? = {
        guard let file = Bundle.main.url(forResource: "FreedoomLicense", withExtension: "txt") else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }()
    static let superTuxKartNotice = """
    Game artwork: SuperTuxKart contributors.
    Recording contributor / uploader: PantheraLeo1359531.

    Game assets use mixed open licenses, including CC BY-SA 3.0/4.0, CC0 and GPL. The recording's CC BY-SA 4.0 license does not describe every underlying game asset. Retain the individual file credits and asset license information linked by the source.

    SuperTuxKart artwork credits and licensing:
    https://supertuxkart.net/Licensing
    """
}
