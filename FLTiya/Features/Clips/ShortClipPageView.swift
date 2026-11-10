import AVFoundation
import SwiftUI
import UIKit

@MainActor
struct ShortClipPageView: View {
    let clip: ApprovedClip
    let repository: any SocialRepository
    let isActive: Bool
    @Binding var isMuted: Bool
    let importedPublisherCredit: ImportedPublisherCredit?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.sampleMessages) private var sampleMessages
    @State private var controller = ShortClipPlaybackController()
    @State private var cover = ClipThumbnailModel()
    @State private var retryID = UUID()
    @State private var coverRetryID = UUID()
    @State private var social = ClipSocialModel()
    @State private var socialSheet: SocialSheet?
    @State private var sampleLookup: SampleLookup?
    @State private var sampleRetryID = UUID()
    @State private var sampleLookupFailed = false
    @State private var sampleFollowMessage: String?

    private struct SampleLookup {
        let viewerID: UUID
        let publisherID: UUID
        let player: CommunityPlayer?
    }

    private enum SocialSheet: String, Identifiable {
        case comments, share
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                coverSurface
                if let player = controller.player {
                    ShortClipPlayerSurface(player: player) {
                        controller.markReady(for: player)
                    }
                    .opacity(controller.isPreparing ? 0 : 1)
                    .allowsHitTesting(false)
                }
                playbackTapTarget
                playbackFeedback
                metadata(compact: geometry.size.height < 460)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .task(id: playbackID) {
            await controller.prepare(clip: clip, repository: repository, isActive: effectiveActive, isMuted: isMuted)
        }
        .task(id: coverID) {
            guard !Task.isCancelled else { return }
            if effectiveActive {
                await cover.load(clip: clip, repository: repository)
            } else {
                cover.clear()
            }
        }
        .task(id: socialID) {
            if effectiveActive { await social.load(clipID: clip.id, repository: repository) }
        }
        .task(id: sampleLookupID) {
            if effectiveActive { await loadSamplePublisher() }
        }
        .onChange(of: effectiveActive) { _, active in
            if !active {
                stop()
                sampleFollowMessage = nil
            }
        }
        .onChange(of: repository.currentUserID) { _, userID in
            controller.stopIfIdentityChanged(userID)
            socialSheet = nil
            social.reset()
            sampleLookup = nil
            sampleLookupFailed = false
            sampleFollowMessage = nil
        }
        .onChange(of: isMuted) { _, muted in controller.setMuted(muted) }
        .onDisappear { stop() }
        .sheet(item: $socialSheet, onDismiss: {
            Task { await social.load(clipID: clip.id, repository: repository) }
        }) { sheet in
            switch sheet {
            case .comments: ClipCommentsView(clip: clip, repository: repository)
            case .share: ClipShareSheet(text: ClipShareContent.text(for: clip))
            }
        }
    }

    private var effectiveActive: Bool { isActive && scenePhase == .active && socialSheet == nil }

    private var socialID: String {
        "\(repository.currentUserID?.uuidString ?? "signed-out")|\(clip.id)|\(clip.ownerID)|\(effectiveActive)"
    }

    private var sampleLookupID: String {
        "\(socialID)|\(visibility?.playerRevision ?? 0)|\(sampleRetryID)"
    }

    private var visibleSampleLookup: SampleLookup? {
        guard let sampleLookup, sampleLookup.viewerID == repository.currentUserID,
              sampleLookup.publisherID == clip.ownerID, visibility?.isPlayerHidden(clip.ownerID) != true else {
            return nil
        }
        return sampleLookup
    }

    private var fallbackPublisherCredit: ImportedPublisherCredit? {
        guard visibleSampleLookup == nil, visibility?.isPlayerHidden(clip.ownerID) != true else { return nil }
        return importedPublisherCredit
    }

    private var playbackID: String {
        "\(repository.currentUserID?.uuidString ?? "signed-out")|\(clip.id)|\(clip.videoPath)|\(effectiveActive)|\(retryID)"
    }

    private var coverID: String {
        "\(repository.currentUserID?.uuidString ?? "signed-out")|\(clip.id)|\(clip.thumbnailPath ?? "no-cover")|\(effectiveActive)|\(coverRetryID)"
    }

    private var coverSurface: some View {
        GeometryReader { geometry in
            if let image = cover.image, cover.loadedUserID == repository.currentUserID {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    private var playbackTapTarget: some View {
        Button {
            controller.togglePause()
        } label: {
            ZStack {
                Color.clear
                if controller.isPaused {
                    GameGlyph(symbol: "play.fill", size: 40)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(24)
                        .background(.black.opacity(0.45), in: Circle())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!effectiveActive || controller.player == nil)
        .accessibilityLabel(controller.isPaused ? "Play clip" : "Pause clip")
        .accessibilityHint("Double tap to change playback")
    }

    @ViewBuilder
    private var playbackFeedback: some View {
        if let message = controller.errorMessage {
            VStack(spacing: 14) {
                GameGlyph(symbol: "play.rectangle", size: 30)
                    .font(.title2)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Button("Try again") { retryID = UUID() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
            .padding(28)
        } else if controller.isPreparing && effectiveActive {
            ProgressView("Opening clip…")
                .font(.subheadline)
                .tint(.white)
                .foregroundStyle(.white)
                .padding(16)
                .background(.black.opacity(0.55), in: Capsule())
                .allowsHitTesting(false)
        }
    }

    private func metadata(compact: Bool) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    uploaderName
                    if !title.isEmpty {
                        Text(verbatim: title)
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                    Text(clip.contentTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.white.opacity(0.13), in: Capsule())
                    if let error = social.errorMessage {
                        Button {
                            Task { await social.load(clipID: clip.id, repository: repository) }
                        } label: {
                            Text(error).font(.caption).multilineTextAlignment(.leading)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .disabled(social.isLoading || social.isUpdatingLike)
                    }
                    if let sampleFollowMessage {
                        Text(sampleFollowMessage)
                            .font(.caption)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    if sampleLookupFailed && fallbackPublisherCredit != nil && social.state?.uploader == nil {
                        Button("Retry publisher profile") { sampleRetryID = UUID() }
                            .font(.caption)
                            .frame(minHeight: 44)
                    }
                    if let message = cover.errorMessage, controller.player == nil {
                        Button {
                            coverRetryID = UUID()
                        } label: {
                            Label("Retry cover", systemImage: "arrow.clockwise")
                                .font(.caption)
                                .frame(minHeight: 44)
                        }
                        .accessibilityHint(message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actionRail(compact: compact)
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
            .padding(.horizontal, 20)
            .padding(.top, compact ? 8 : 70)
            .padding(.bottom, compact ? 12 : 22)
            .background {
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var uploaderName: some View {
        if let profile = social.state?.uploader {
            NavigationLink {
                PlayerProfileView(userID: profile.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared by").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text(verbatim: profile.displayName).font(.headline).lineLimit(1)
                }
            }
            .accessibilityLabel("View uploader \(profile.displayName)'s profile")
        } else if let sample = visibleSampleLookup?.player {
            NavigationLink {
                SamplePlayerDetailView(sample: sample)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared by").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text(verbatim: sample.displayName).font(.headline).lineLimit(1)
                }
            }
            .accessibilityLabel("View sample publisher \(sample.displayName)'s profile")
        } else if let importedPublisherCredit = fallbackPublisherCredit {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shared by").font(.caption2).foregroundStyle(.white.opacity(0.7))
                Text(verbatim: importedPublisherCredit.displayName).font(.headline).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(social.isLoading ? "" : "Imported clip").font(.headline)
        }
    }

    private func actionRail(compact: Bool) -> some View {
        let layout = compact
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
            : AnyLayout(VStackLayout(spacing: 18))
        return layout {
            if let profile = social.state?.uploader {
                VStack(spacing: -12) {
                    NavigationLink {
                        PlayerProfileView(userID: profile.id)
                    } label: {
                        PlayerAvatarView(profile: profile, size: 50)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                            // The decorative fallback sticker ignores hits. Define
                            // the link's entire touch area above the playback button.
                            .frame(width: 54, height: 54)
                            .contentShape(Circle())
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("View uploader \(profile.displayName)'s profile")
                    .accessibilityIdentifier("clip.uploaderAvatar.\(clip.id.uuidString)")
                    if profile.id != repository.currentUserID {
                        followButton(
                            displayName: profile.displayName,
                            following: social.state?.isFollowing == true,
                            updating: social.isUpdatingFollow
                        ) {
                            Task { await social.toggleFollow(clipID: clip.id, repository: repository) }
                        }
                        .disabled(social.isLoading || social.isUpdatingFollow || social.isUpdatingLike)
                    }
                }
            } else if let sample = visibleSampleLookup?.player {
                VStack(spacing: -12) {
                    NavigationLink {
                        SamplePlayerDetailView(sample: sample)
                    } label: {
                        PlayerAvatarView(profile: sample.profile, size: 50)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                            .frame(width: 54, height: 54)
                            .contentShape(Circle())
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("View sample publisher \(sample.displayName)'s profile")
                    .accessibilityIdentifier("clip.uploaderAvatar.\(clip.id.uuidString)")

                    if let sampleMessages, let viewerID = repository.currentUserID, sample.id != viewerID {
                        followButton(displayName: sample.displayName,
                                     following: sampleMessages.isFollowingPublisher(sample.id, ownerID: viewerID)) {
                            toggleSampleFollow(sample, store: sampleMessages, viewerID: viewerID)
                        }
                        .accessibilityHint("Sample follows are saved only on this device.")
                    }
                }
            } else if let importedPublisherCredit = fallbackPublisherCredit {
                Image(importedPublisherCredit.avatarAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                    .frame(width: 54, height: 54)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Button {
                Task { await social.toggleLike(clipID: clip.id, repository: repository) }
            } label: {
                railLabel(symbol: "heart.fill", title: social.state.map { String($0.likeCount) } ?? "—",
                          color: social.state?.isLiked == true ? .pink : .white)
            }
            .disabled(social.state == nil || social.isUpdatingLike || social.isUpdatingFollow || social.isLoading)
            .accessibilityLabel(social.state?.isLiked == true ? "Unlike clip" : "Like clip")
            .accessibilityValue(social.state.map { "\($0.likeCount) likes" } ?? "Not loaded")
            Button { socialSheet = .comments } label: {
                railLabel(symbol: "bubble.right.fill", title: social.state.map { String($0.commentCount) } ?? "—")
            }
            .accessibilityLabel("Comments")
            .accessibilityValue(social.state.map { "\($0.commentCount) approved comments" } ?? "Not loaded")
            Button { socialSheet = .share } label: {
                railLabel(symbol: "arrowshape.turn.up.right.fill", title: "Share")
            }
            .accessibilityLabel("Share clip source and credits")
        }
        .frame(width: compact ? nil : 54)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.bottom, compact ? 0 : 10)
    }

    private func followButton(
        displayName: String, following: Bool, updating: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if updating {
                    ProgressView().tint(AppTheme.background).scaleEffect(0.7)
                } else {
                    Image(systemName: following ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .black))
                }
            }
            .foregroundStyle(AppTheme.background)
            .frame(width: 24, height: 24)
            .background(AppTheme.accent, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(following ? "Unfollow \(displayName)" : "Follow \(displayName)")
        .accessibilityIdentifier("clip.follow.\(clip.id.uuidString)")
    }

    private func loadSamplePublisher() async {
        guard let importedPublisherCredit, let viewerID = repository.currentUserID,
              visibility?.isPlayerHidden(clip.ownerID) != true else { return }
        let revision = visibility?.playerRevision
        sampleLookupFailed = false
        do {
            let sample = try await repository.findSamplePlayer(
                id: clip.ownerID, gameID: importedPublisherCredit.sampleGameID, handle: importedPublisherCredit.sampleHandle
            )
            try Task.checkCancellation()
            guard viewerID == repository.currentUserID, visibility?.playerRevision == revision,
                  visibility?.isPlayerHidden(clip.ownerID) != true else { return }
            let verified = sample.flatMap { player in
                player.handle == importedPublisherCredit.sampleHandle &&
                    player.sampleGameID == importedPublisherCredit.sampleGameID ? player : nil
            }
            sampleLookup = SampleLookup(viewerID: viewerID, publisherID: clip.ownerID, player: verified)
        } catch {
            guard !Task.isCancelled, viewerID == repository.currentUserID,
                  visibility?.playerRevision == revision else { return }
            sampleLookupFailed = true
        }
    }

    private func toggleSampleFollow(_ sample: CommunityPlayer, store: SampleMessageStore, viewerID: UUID) {
        guard viewerID == repository.currentUserID, visibleSampleLookup?.player?.id == sample.id else { return }
        if !store.isReady(for: viewerID) { store.load(for: viewerID) }
        let following = !store.isFollowingPublisher(sample.id, ownerID: viewerID)
        do {
            try store.setPublisherFollow(sample, following: following, ownerID: viewerID)
            sampleFollowMessage = following ? "Sample follow saved on this device." : "Sample follow removed."
        } catch {
            sampleFollowMessage = "Couldn't save the sample follow. Try again."
        }
    }

    private func railLabel(symbol: String, title: String, color: Color = .white) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 29, weight: .semibold)).foregroundStyle(color)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white)
        }
        .frame(width: 54)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private var title: String {
        clip.caption.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private func stop() {
        controller.stop()
        cover.clear()
    }
}

@MainActor
private struct ShortClipPlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let onReady: () -> Void

    func makeUIView(context: Context) -> ShortClipPlayerHost {
        ShortClipPlayerHost()
    }

    func updateUIView(_ uiView: ShortClipPlayerHost, context: Context) {
        uiView.show(player: player, onReady: onReady)
    }

    static func dismantleUIView(_ uiView: ShortClipPlayerHost, coordinator: ()) {
        uiView.clear()
    }
}

@MainActor
private final class ShortClipPlayerHost: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var readyObservation: NSKeyValueObservation?
    private var onReady: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { return nil }

    func show(player: AVPlayer, onReady: @escaping () -> Void) {
        self.onReady = onReady
        guard playerLayer.player !== player else { return }
        readyObservation?.invalidate()
        playerLayer.player = player
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak player] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.playerLayer.player === player else { return }
                self.onReady?()
            }
        }
    }

    func clear() {
        readyObservation?.invalidate()
        readyObservation = nil
        onReady = nil
        playerLayer.player = nil
    }
}
