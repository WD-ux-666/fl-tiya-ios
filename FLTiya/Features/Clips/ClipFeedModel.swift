import Foundation
import Observation

@MainActor
@Observable
final class ClipFeedModel {
    private(set) var clips: [ApprovedClip] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private var loadedUserID: UUID?

    func load(repository: (any SocialRepository)?) async {
        let request = UUID()
        generation = request
        guard let repository, let userID = repository.currentUserID else {
            reset()
            return
        }
        if loadedUserID != userID { clips = [] }
        loadedUserID = userID
        isLoading = true
        errorMessage = nil

        do {
            let response = try await repository.approvedClips()
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else {
                reset()
                return
            }
            // RLS can also return the owner's pending/rejected posts. The query
            // filters approved status and this boundary keeps those out of the UI.
            clips = Self.interleaved(response.filter(\.canPlay))
            isLoading = false
        } catch {
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else {
                reset()
                return
            }
            isLoading = false
            errorMessage = "Clips couldn't be loaded. Please try again."
        }
    }

    private static func interleaved(_ clips: [ApprovedClip]) -> [ApprovedClip] {
        let gaming = clips.filter { $0.contentCategory == .gaming }
        let lifestyle = clips.filter { $0.contentCategory == .lifestyle }
        var ordered: [ApprovedClip] = []
        ordered.reserveCapacity(clips.count)

        // Start Home with gaming, then a creator clip. Keep server order within
        // each category and append any remaining clips when one category ends.
        for index in 0..<max(gaming.count, lifestyle.count) {
            if index < gaming.count { ordered.append(gaming[index]) }
            if index < lifestyle.count { ordered.append(lifestyle[index]) }
        }
        return ordered
    }

    func reset() {
        generation = UUID()
        loadedUserID = nil
        clips = []
        isLoading = false
        errorMessage = nil
    }
}
