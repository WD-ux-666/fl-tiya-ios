import Foundation
import Observation

@MainActor
@Observable
final class GuideFeedModel {
    private(set) var guides: [GameGuide] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedGameID: String?
    private(set) var loadedUserID: UUID?
    private var generation = UUID()

    func load(gameID: String, repository: (any SocialRepository)?) async {
        guard !Task.isCancelled else { return }
        guard let repository, let userID = repository.currentUserID else { reset(); return }
        let request = UUID()
        generation = request
        if loadedUserID != userID || loadedGameID != gameID { guides = [] }
        loadedUserID = userID
        loadedGameID = gameID
        isLoading = true
        errorMessage = nil
        do {
            let rows = try await repository.publishedGuides(gameID: gameID)
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else { reset(); return }
            guides = rows.filter { $0.gameID == gameID && $0.canBrowse }
            isLoading = false
        } catch {
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else { reset(); return }
            isLoading = false
            errorMessage = "Guides couldn't be loaded. Please try again."
        }
    }

    func reset() {
        generation = UUID()
        guides = []
        loadedGameID = nil
        loadedUserID = nil
        isLoading = false
        errorMessage = nil
    }
}

@MainActor
@Observable
final class GameClipFeedModel {
    private(set) var clips: [ApprovedClip] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedGameID: String?
    private(set) var loadedUserID: UUID?
    private var generation = UUID()

    func load(gameID: String, repository: (any SocialRepository)?) async {
        guard !Task.isCancelled else { return }
        guard let repository, let userID = repository.currentUserID else { reset(); return }
        let request = UUID()
        generation = request
        if loadedUserID != userID || loadedGameID != gameID { clips = [] }
        loadedUserID = userID
        loadedGameID = gameID
        isLoading = true
        errorMessage = nil
        do {
            let rows = try await repository.approvedClips(gameID: gameID)
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else { reset(); return }
            clips = rows.filter { $0.contentCategory == .gaming && $0.gameID == gameID && $0.canPlay }
            isLoading = false
        } catch {
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else { reset(); return }
            isLoading = false
            errorMessage = "Clips couldn't be loaded. Please try again."
        }
    }

    func reset() {
        generation = UUID()
        clips = []
        loadedGameID = nil
        loadedUserID = nil
        isLoading = false
        errorMessage = nil
    }
}
