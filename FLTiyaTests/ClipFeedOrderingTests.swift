import XCTest
@testable import FLTiya

@MainActor
final class ClipFeedOrderingTests: XCTestCase {
    func testHomeStartsWithGamingAndAlternatesAllTenClipsInStableGroupOrder() async {
        let repository = HomeClipRepositoryDouble()
        // Server recency can put all creator imports before the gaming imports.
        repository.clips = [
            clip("Creator 1", category: .lifestyle), clip("Creator 2", category: .lifestyle),
            clip("Creator 3", category: .lifestyle), clip("Creator 4", category: .lifestyle),
            clip("Creator 5", category: .lifestyle), clip("Game 1"), clip("Game 2"),
            clip("Game 3"), clip("Game 4"), clip("Game 5")
        ]
        let model = ClipFeedModel()

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.caption), [
            "Game 1", "Creator 1", "Game 2", "Creator 2", "Game 3", "Creator 3",
            "Game 4", "Creator 4", "Game 5", "Creator 5"
        ])
        XCTAssertEqual(Set(model.clips.map(\.id)), Set(repository.clips.map(\.id)))
        XCTAssertEqual(model.clips.count, 10)
    }

    func testRemainingGamingClipsStayAfterTheAlternatingPairs() async {
        let repository = HomeClipRepositoryDouble()
        repository.clips = [clip("Game 1"), clip("Game 2"), clip("Game 3"),
                            clip("Creator 1", category: .lifestyle)]
        let model = ClipFeedModel()

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.caption), ["Game 1", "Creator 1", "Game 2", "Game 3"])
    }

    func testRemainingCreatorClipsStayAfterTheAlternatingPairs() async {
        let repository = HomeClipRepositoryDouble()
        repository.clips = [clip("Creator 1", category: .lifestyle), clip("Game 1"),
                            clip("Creator 2", category: .lifestyle), clip("Creator 3", category: .lifestyle)]
        let model = ClipFeedModel()

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.caption), ["Game 1", "Creator 1", "Creator 2", "Creator 3"])
    }

    func testSingleCategoryFeedsKeepTheirOriginalOrder() async {
        let repository = HomeClipRepositoryDouble()
        let model = ClipFeedModel()
        repository.clips = [clip("Game 1"), clip("Game 2")]

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.caption), ["Game 1", "Game 2"])

        repository.clips = [clip("Creator 1", category: .lifestyle), clip("Creator 2", category: .lifestyle)]

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.caption), ["Creator 1", "Creator 2"])
    }

    func testNonPlayableClipsNeverOccupyAlternatingSlots() async {
        let repository = HomeClipRepositoryDouble()
        repository.clips = [
            clip("Pending game", status: "pending"), clip("Game 1"),
            clip("Pending creator", category: .lifestyle, status: "pending"),
            clip("Creator 1", category: .lifestyle), clip("Unknown", category: .unsupported),
            clip("Unsafe creator", category: .lifestyle, path: "https://example.com/clip.mp4"),
            clip("Game 2"), clip("Creator 2", category: .lifestyle)
        ]
        let model = ClipFeedModel()

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.caption), ["Game 1", "Creator 1", "Game 2", "Creator 2"])
    }

    func testEmptyRefreshRemovesThePreviousRotation() async {
        let repository = HomeClipRepositoryDouble()
        repository.clips = [clip("Game 1"), clip("Creator 1", category: .lifestyle)]
        let model = ClipFeedModel()
        await model.load(repository: repository)
        repository.clips = []

        await model.load(repository: repository)

        XCTAssertTrue(model.clips.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    private func clip(_ title: String, category: ClipContentCategory = .gaming,
                      status: String = "approved", path: String? = nil) -> ApprovedClip {
        let id = UUID(), owner = UUID()
        return ApprovedClip(id: id, ownerID: owner,
            gameID: category == .gaming ? "test-game" : nil, caption: title,
            videoPath: path ?? "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased())/clip.mp4",
            thumbnailPath: nil, status: status, createdAt: "2026-11-06T00:00:00Z",
            approvedAt: status == "approved" ? "2026-11-06T00:00:01Z" : nil,
            game: nil, contentCategory: category)
    }
}

@MainActor
private final class HomeClipRepositoryDouble: SocialRepository {
    var currentUserID: UUID? = UUID()
    var clips: [ApprovedClip] = []

    func approvedClips() async throws -> [ApprovedClip] { clips }
    func approvedClips(gameID: String) async throws -> [ApprovedClip] { throw UnusedCall.unexpected }
    func publishedGuides(gameID: String) async throws -> [GameGuide] { throw UnusedCall.unexpected }
    func downloadClip(path: String) async throws -> Data { throw UnusedCall.unexpected }
    func downloadClipThumbnail(path: String) async throws -> Data { throw UnusedCall.unexpected }
    func players(query: String) async throws -> [PlayerProfile] { throw UnusedCall.unexpected }
    func communityPlayers(gameID: String?, query: String) async throws -> [CommunityPlayer] { throw UnusedCall.unexpected }
    func blockedPlayers(before: BlockedPlayer?) async throws -> [BlockedPlayer] { throw UnusedCall.unexpected }
    func unblockUser(id: UUID) async throws { throw UnusedCall.unexpected }
    func uploadAvatar(_ data: Data) async throws -> String { throw UnusedCall.unexpected }
    func downloadAvatar(path: String) async throws -> Data { throw UnusedCall.unexpected }
    func updateProfile(displayName: String, bio: String, avatarPath: String) async throws { throw UnusedCall.unexpected }
    func clipSocialState(clipID: UUID) async throws -> ClipSocialState { throw UnusedCall.unexpected }
    func setClipLiked(clipID: UUID, liked: Bool) async throws -> ClipSocialState { throw UnusedCall.unexpected }
    func clipComments(clipID: UUID) async throws -> [ClipComment] { throw UnusedCall.unexpected }
    func addClipComment(clipID: UUID, commentID: UUID, body: String) async throws -> ClipComment { throw UnusedCall.unexpected }
    func deleteClipComment(id: UUID) async throws { throw UnusedCall.unexpected }
    func profile(id: UUID) async throws -> PlayerProfile { throw UnusedCall.unexpected }
    func playerFollowState(userID: UUID) async throws -> PlayerFollowState { throw UnusedCall.unexpected }
    func setPlayerFollowed(userID: UUID, followed: Bool) async throws -> PlayerFollowState { throw UnusedCall.unexpected }
    func openConversation(with userID: UUID) async throws -> DirectConversation { throw UnusedCall.unexpected }
    func conversationMessagingState(conversationID: UUID) async throws -> ConversationMessagingState { throw UnusedCall.unexpected }
    func connection(with userID: UUID) async throws -> PlayerConnection { throw UnusedCall.unexpected }
    func updateProfile(displayName: String, bio: String) async throws { throw UnusedCall.unexpected }
    func gameCards(userID: UUID) async throws -> [PlayerGameCard] { throw UnusedCall.unexpected }
    func saveGameCard(gameID: String, playerName: String, daysPlayed: Int?, progress: String) async throws { throw UnusedCall.unexpected }
    func friendRequests() async throws -> [FriendRequest] { throw UnusedCall.unexpected }
    func sendFriendRequest(to userID: UUID) async throws { throw UnusedCall.unexpected }
    func respondToFriendRequest(id: UUID, accept: Bool) async throws { throw UnusedCall.unexpected }
    func removeFriend(id: UUID) async throws { throw UnusedCall.unexpected }
    func conversations() async throws -> [DirectConversation] { throw UnusedCall.unexpected }
    func messages(conversationID: UUID) async throws -> [ChatMessage] { throw UnusedCall.unexpected }
    func sendMessage(conversationID: UUID, id: UUID, body: String) async throws { throw UnusedCall.unexpected }
    func blockUser(id: UUID) async throws { throw UnusedCall.unexpected }

    private enum UnusedCall: Error { case unexpected }
}
