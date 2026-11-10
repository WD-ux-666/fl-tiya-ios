import Foundation
import Observation

struct ClipSocialState: Decodable, Sendable {
    /// The app uploader, when their profile is visible to this account. Source
    /// creators remain credited separately in the immutable clip caption.
    let uploader: PlayerProfile?
    let likeCount: Int
    let commentCount: Int
    let isLiked: Bool
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case uploader
        case isFollowing = "is_following"
        case likeCount = "like_count", commentCount = "comment_count", isLiked = "is_liked"
    }
}

/// Display credits and lookup hints for the curated launch clips. The
/// community endpoint must verify the sample player before opening a profile.
struct ImportedPublisherCredit {
    let displayName: String
    let avatarAssetName: String
    let sampleHandle: String
    let sampleGameID: String

    static func forClip(id: UUID) -> Self? {
        // Exact posts listed in development-clip-publishers-2026-11-06.json.
        switch id.uuidString.lowercased() {
        case "86916319-1668-569a-8fd0-8ff991d483c4",
             "bc761749-e6fd-5f5f-8a1d-4d396ac3d208",
             "6920e768-4d0a-5af1-a003-10ea2eeca518",
             "2e2427e1-3045-5770-8217-f47fe942efa1":
            return Self(displayName: "Jade Park", avatarAssetName: "ImportedPublisherJade",
                        sampleHandle: "jade_park", sampleGameID: "zenless-zone-zero")
        case "d18a4edb-2345-5269-b1ea-7cb96882f31b",
             "89630fe1-6fbe-5d05-aafe-6b29afb38fb5",
             "3f6877fa-0e13-59d4-8316-afafba965d25":
            return Self(displayName: "Leo Brooks", avatarAssetName: "ImportedPublisherLeo",
                        sampleHandle: "leo_brooks", sampleGameID: "pubg-mobile")
        case "084d6071-d274-52b3-8f24-62b731a741cb",
             "51628a69-1010-5201-b5bc-20346473161f",
             "0266cd87-d7a3-53a6-8a08-6f454c48a6a5":
            return Self(displayName: "Nina Vega", avatarAssetName: "ImportedPublisherNina",
                        sampleHandle: "nina_vega", sampleGameID: "minecraft")
        default:
            return nil
        }
    }
}

struct ClipComment: Decodable, Identifiable, Sendable {
    struct SampleAuthorCredit: Hashable, Sendable {
        let handle: String
        let gameID: String
    }

    let id: UUID
    let clipID: UUID
    let author: PlayerProfile
    let body: String
    let createdAt: String
    let status: String
    private let isSample: Bool?
    private let sampleHandle: String?
    private let sampleGameID: String?

    var isPending: Bool { status == "pending" }
    var hasAuthorProfile: Bool { isSample != true }
    var sampleAuthorCredit: SampleAuthorCredit? {
        guard isSample == true, let sampleHandle, !sampleHandle.isEmpty,
              let sampleGameID, !sampleGameID.isEmpty else { return nil }
        return SampleAuthorCredit(handle: sampleHandle, gameID: sampleGameID)
    }

    enum CodingKeys: String, CodingKey {
        case id, author, body, status
        case clipID = "clip_id", createdAt = "created_at"
        case isSample = "is_sample"
        case sampleHandle = "sample_handle", sampleGameID = "sample_game_id"
    }
}

@MainActor
@Observable
final class ClipSocialModel {
    private(set) var state: ClipSocialState?
    private(set) var isLoading = false
    private(set) var isUpdatingLike = false
    private(set) var isUpdatingFollow = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private var loadedUserID: UUID?

    func load(clipID: UUID, repository: any SocialRepository) async {
        guard !Task.isCancelled, let actor = repository.currentUserID else { return }
        if loadedUserID != actor { reset() }
        guard !isUpdatingLike, !isUpdatingFollow else { return }
        loadedUserID = actor
        let request = UUID()
        generation = request
        isLoading = true
        errorMessage = nil
        defer { if generation == request { isLoading = false } }
        do {
            let result = try await repository.clipSocialState(clipID: clipID)
            guard generation == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            state = result
        } catch {
            guard generation == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "Couldn't load interactions. Tap to retry."
        }
    }

    func toggleLike(clipID: UUID, repository: any SocialRepository) async {
        guard let actor = repository.currentUserID, actor == loadedUserID,
              let state, !isUpdatingLike, !isUpdatingFollow, !isLoading else { return }
        let request = generation
        isUpdatingLike = true
        errorMessage = nil
        defer { if generation == request { isUpdatingLike = false } }
        do {
            let result = try await repository.setClipLiked(clipID: clipID, liked: !state.isLiked)
            guard generation == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            self.state = result
        } catch {
            guard generation == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "Couldn't update your like. Please try again."
        }
    }

    func toggleFollow(clipID: UUID, repository: any SocialRepository) async {
        guard let actor = repository.currentUserID, actor == loadedUserID,
              let state, let uploader = state.uploader, uploader.id != actor,
              !isUpdatingLike, !isUpdatingFollow, !isLoading else { return }
        let request = generation
        isUpdatingFollow = true
        errorMessage = nil
        defer { if generation == request { isUpdatingFollow = false } }
        do {
            let result = try await repository.setPlayerFollowed(userID: uploader.id, followed: !state.isFollowing)
            guard generation == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            self.state = ClipSocialState(uploader: state.uploader, likeCount: state.likeCount,
                commentCount: state.commentCount, isLiked: state.isLiked, isFollowing: result.isFollowing)
        } catch {
            guard generation == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "Couldn't update your follow. Please try again."
        }
    }

    func reset() {
        generation = UUID()
        loadedUserID = nil
        state = nil
        isLoading = false
        isUpdatingLike = false
        isUpdatingFollow = false
        errorMessage = nil
    }
}

enum ClipShareContent {
    /// Sharing carries the published source and attribution, never the private
    /// Storage object path, an access token or an expiring download URL.
    static func text(for clip: ApprovedClip) -> String {
        "\(clip.contentTitle) · TIYA\n\n\(clip.caption)"
    }
}
