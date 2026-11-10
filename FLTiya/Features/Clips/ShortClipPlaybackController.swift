import AVFoundation
import Combine
import Observation

@MainActor
@Observable
final class ShortClipPlaybackController {
    private(set) var player: AVPlayer?
    private(set) var isPreparing = false
    private(set) var isPaused = false
    private(set) var errorMessage: String?

    private let playback: ClipPlaybackModel
    private let checkPlayable: @MainActor (URL) async throws -> Bool
    private var generation = UUID()
    private var wantsPlayback = false
    private var muted = true
    private var reachedEnd = false
    private var userID: UUID?
    private var repository: (any SocialRepository)?
    @ObservationIgnored private var endObservation: AnyCancellable?
    @ObservationIgnored private var failureObservation: AnyCancellable?
    @ObservationIgnored private var statusObservation: AnyCancellable?

    init(playback: ClipPlaybackModel? = nil,
         checkPlayable: (@MainActor (URL) async throws -> Bool)? = nil) {
        self.playback = playback ?? ClipPlaybackModel()
        self.checkPlayable = checkPlayable ?? Self.isPlayable
    }

    func prepare(clip: ApprovedClip, repository: any SocialRepository, isActive: Bool, isMuted: Bool) async {
        // A retired SwiftUI task may enter after a replacement task started.
        // It must not tear down that newer request before checking cancellation.
        guard !Task.isCancelled else { return }
        stop()
        guard isActive, !Task.isCancelled, let userID = repository.currentUserID else { return }
        self.repository = repository
        self.userID = userID
        muted = isMuted
        wantsPlayback = true
        isPreparing = true
        let request = generation

        await playback.load(clip: clip, repository: repository, presentingUserID: userID)
        guard current(request, repository: repository, userID: userID) else { return }
        guard let file = playback.fileURL else {
            fail(playback.errorMessage ?? "This clip couldn't be opened. Please try again.")
            return
        }
        do {
            let playable = try await checkPlayable(file)
            guard current(request, repository: repository, userID: userID) else { return }
            guard playback.fileURL == file, playable else { throw SocialDataFailure.invalidClipMedia }
            // Only the protected local file reaches AVPlayer. No remote URL,
            // user token or SDK authorization header enters the video layer.
            let item = AVPlayerItem(url: file)
            let player = AVPlayer(playerItem: item)
            player.isMuted = muted
            player.actionAtItemEnd = .pause
            self.player = player
            observe(item, request: request)
            player.play()
        } catch {
            guard current(request, repository: repository, userID: userID) else { return }
            fail("This video couldn't be played. Please try again.")
        }
    }

    func markReady(for player: AVPlayer) {
        guard self.player === player else { return }
        guard canPlayNow else { stop(); return }
        isPreparing = false
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        if wantsPlayback && !canPlayNow { stop(); return }
        player?.isMuted = muted
    }

    func togglePause() {
        guard canPlayNow else { stop(); return }
        guard let player else { return }
        isPaused.toggle()
        if isPaused {
            player.pause()
        } else if reachedEnd, let item = player.currentItem {
            rewindAndPlay(item, request: generation)
        } else {
            player.play()
        }
    }

    func stopIfIdentityChanged(_ currentUserID: UUID?) {
        if userID != currentUserID { stop() }
    }

    func stop() {
        generation = UUID()
        wantsPlayback = false
        endObservation?.cancel()
        failureObservation?.cancel()
        statusObservation?.cancel()
        endObservation = nil
        failureObservation = nil
        statusObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playback.clear()
        repository = nil
        userID = nil
        reachedEnd = false
        isPreparing = false
        isPaused = false
        errorMessage = nil
    }

    private var canPlayNow: Bool {
        wantsPlayback && userID != nil && repository?.currentUserID == userID
    }

    private func current(_ request: UUID, repository: any SocialRepository, userID: UUID) -> Bool {
        guard generation == request else { return false }
        guard wantsPlayback, !Task.isCancelled, repository.currentUserID == userID else {
            stop()
            return false
        }
        return true
    }

    private func observe(_ item: AVPlayerItem, request: UUID) {
        endObservation = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .sink { [weak self, weak item] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.matches(item, request: request) else { return }
                    self.reachedEnd = true
                    if !self.isPaused { self.rewindAndPlay(item, request: request) }
                }
            }
        failureObservation = NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .sink { [weak self, weak item] _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.matches(item, request: request) else { return }
                    self.fail("This video couldn't be played. Please try again.")
                }
            }
        statusObservation = item.publisher(for: \.status).sink { [weak self, weak item] status in
            guard status == .failed else { return }
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.matches(item, request: request) else { return }
                self.fail("This video couldn't be played. Please try again.")
            }
        }
    }

    private func matches(_ item: AVPlayerItem, request: UUID) -> Bool {
        guard generation == request, player?.currentItem === item else { return false }
        guard canPlayNow else { stop(); return false }
        return true
    }

    private func rewindAndPlay(_ item: AVPlayerItem, request: UUID) {
        guard matches(item, request: request), !isPaused, let player else { return }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player, weak item] finished in
            Task { @MainActor [weak self, weak player, weak item] in
                guard finished, let self, let player, let item,
                      self.matches(item, request: request), self.player === player, !self.isPaused else { return }
                self.reachedEnd = false
                player.play()
            }
        }
    }

    private func fail(_ message: String) {
        stop()
        errorMessage = message
    }

    private static func isPlayable(_ file: URL) async throws -> Bool {
        try await AVURLAsset(url: file).load(.isPlayable)
    }
}
