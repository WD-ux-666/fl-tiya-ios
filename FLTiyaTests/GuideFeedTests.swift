import XCTest
@testable import FLTiya

@MainActor
final class GuideFeedTests: XCTestCase {
    func testGuideWireFieldsPreserveFullSourceAttribution() throws {
        let data = Data(#"{"id":"91323ff3-6613-4fe6-aa73-c560e75b5c01","game_id":"zenless-zone-zero","title":"Starter reference","summary":"Original summary.","source_url":"https://example.com/reference","source_name":"Publisher","source_author":"Source author","attribution":"Original creator credit.","status":"published","published_at":"2026-11-04T08:00:00.000Z"}"#.utf8)
        let result = try JSONDecoder().decode(GameGuide.self, from: data)
        XCTAssertEqual(result.gameID, "zenless-zone-zero")
        XCTAssertEqual(result.sourceAuthor, "Source author")
        XCTAssertEqual(result.attribution, "Original creator credit.")
        XCTAssertNotNil(result.publicationDate)
        XCTAssertTrue(result.canBrowse)
    }

    func testSourceLinksRejectCredentialsSchemesPortsAndControlCharacters() {
        let rejected = [
            "http://example.com/guide", "javascript:alert(1)", "file:///tmp/guide",
            "https://user:password@example.com/guide", "https://example.com:8443/guide",
            "https:///guide", " https://example.com/guide", "https://example.com/guide\n"
        ]
        for value in rejected { XCTAssertNil(GuideSourceRules.url(value), value) }
        XCTAssertEqual(GuideSourceRules.url("https://example.com:443/guide?q=game#build")?.host, "example.com")
    }

    func testPublishedFeedRejectsDraftOtherGameAndUnsafeSourceRows() async {
        let repository = GuideRepositoryDouble()
        repository.guides = [guide(), guide(status: "draft"), guide(gameID: "other-game"),
                             guide(source: "https://user@example.com/guide")]
        let expected = repository.guides[0].id
        let model = GuideFeedModel()
        await model.load(gameID: "zenless-zone-zero", repository: repository)
        XCTAssertEqual(model.guides.map(\.id), [expected])
        XCTAssertEqual(repository.requestedGuideGames, ["zenless-zone-zero"])
    }

    func testLateGuideResponseCannotRepopulateAfterAccountChanges() async {
        let repository = GuideRepositoryDouble()
        repository.suspendsGuides = true
        let started = expectation(description: "Guide request suspended")
        repository.onGuideRequest = { started.fulfill() }
        let model = GuideFeedModel()
        let request = Task { await model.load(gameID: "zenless-zone-zero", repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.currentUserID = UUID()
        repository.completeGuides([guide()])
        await request.value
        XCTAssertTrue(model.guides.isEmpty)
        XCTAssertNil(model.loadedUserID)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderGameResponseCannotReplaceNewGameGuides() async {
        let repository = GuideRepositoryDouble()
        repository.suspendsGuides = true
        let started = expectation(description: "Old game request suspended")
        repository.onGuideRequest = { started.fulfill() }
        let model = GuideFeedModel()
        let old = Task { await model.load(gameID: "zenless-zone-zero", repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.suspendsGuides = false
        repository.guides = [guide(gameID: "minetest")]
        let expected = repository.guides[0].id
        await model.load(gameID: "minetest", repository: repository)
        repository.completeGuides([guide()])
        await old.value
        XCTAssertEqual(model.guides.map(\.id), [expected])
        XCTAssertEqual(model.loadedGameID, "minetest")
    }

    func testAlreadyCancelledGuideLoadPreservesCurrentRequest() async {
        let repository = GuideRepositoryDouble()
        repository.suspendsGuides = true
        let started = expectation(description: "Current request suspended")
        repository.onGuideRequest = { started.fulfill() }
        let model = GuideFeedModel()
        let current = Task { await model.load(gameID: "zenless-zone-zero", repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        let retired = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(gameID: "minetest", repository: repository)
        }
        await retired.value
        repository.completeGuides([guide()])
        await current.value
        XCTAssertEqual(model.guides.count, 1)
        XCTAssertEqual(model.loadedGameID, "zenless-zone-zero")
        XCTAssertEqual(repository.requestedGuideGames, ["zenless-zone-zero"])
    }

    func testFailedRefreshRetainsSameAccountGuidesAndAllowsRetry() async {
        let repository = GuideRepositoryDouble()
        repository.guides = [guide()]
        let model = GuideFeedModel()
        await model.load(gameID: "zenless-zone-zero", repository: repository)
        let expected = model.guides[0].id
        repository.failGuides = true
        await model.load(gameID: "zenless-zone-zero", repository: repository)
        XCTAssertEqual(model.guides.map(\.id), [expected])
        XCTAssertNotNil(model.errorMessage)
        repository.failGuides = false
        await model.load(gameID: "zenless-zone-zero", repository: repository)
        XCTAssertNil(model.errorMessage)
    }

    func testResetDiscardsLateGuideResponse() async {
        let repository = GuideRepositoryDouble()
        repository.suspendsGuides = true
        let started = expectation(description: "Request suspended")
        repository.onGuideRequest = { started.fulfill() }
        let model = GuideFeedModel()
        let request = Task { await model.load(gameID: "zenless-zone-zero", repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        model.reset()
        repository.completeGuides([guide()])
        await request.value
        XCTAssertTrue(model.guides.isEmpty)
        XCTAssertNil(model.loadedGameID)
    }

    func testGameClipFeedRequestsSpecificGameAndRejectsOtherGameAndPendingRows() async {
        let repository = GuideRepositoryDouble()
        repository.clips = [clip(), clip(gameID: "minetest"), clip(status: "pending")]
        let expected = repository.clips[0].id
        let model = GameClipFeedModel()
        await model.load(gameID: "zenless-zone-zero", repository: repository)
        XCTAssertEqual(repository.requestedClipGames, ["zenless-zone-zero"])
        XCTAssertEqual(model.clips.map(\.id), [expected])
    }

    func testGameClipFeedRejectsLifestyleAndMissingGameClassifications() async {
        let repository = GuideRepositoryDouble()
        let gaming = clip()
        repository.clips = [gaming, clip(gameID: nil, category: .lifestyle),
                            clip(gameID: "zenless-zone-zero", category: .lifestyle), clip(gameID: nil)]
        let model = GameClipFeedModel()

        await model.load(gameID: "zenless-zone-zero", repository: repository)

        XCTAssertEqual(model.clips.map(\.id), [gaming.id])
    }

    func testGameClipFeedDiscardsLateResponseAfterAccountChange() async {
        let repository = GuideRepositoryDouble()
        repository.suspendsClips = true
        let started = expectation(description: "Clip request suspended")
        repository.onClipRequest = { started.fulfill() }
        let model = GameClipFeedModel()
        let request = Task { await model.load(gameID: "zenless-zone-zero", repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.currentUserID = UUID()
        repository.completeClips([clip()])
        await request.value
        XCTAssertTrue(model.clips.isEmpty)
        XCTAssertNil(model.loadedUserID)
    }

    func testOlderGameVideoResponseCannotReplaceCurrentGame() async {
        let repository = GuideRepositoryDouble()
        repository.suspendsClips = true
        let started = expectation(description: "Old game's video request suspended")
        repository.onClipRequest = { started.fulfill() }
        let model = GameClipFeedModel()
        let old = Task { await model.load(gameID: "zenless-zone-zero", repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.suspendsClips = false
        repository.clips = [clip(gameID: "minetest")]
        let expected = repository.clips[0].id
        await model.load(gameID: "minetest", repository: repository)
        repository.completeClips([clip()])
        await old.value
        XCTAssertEqual(model.clips.map(\.id), [expected])
        XCTAssertEqual(model.loadedGameID, "minetest")
    }

    func testAlreadyCancelledVideoLoadCannotClearCurrentFeed() async {
        let repository = GuideRepositoryDouble()
        repository.clips = [clip()]
        let model = GameClipFeedModel()
        await model.load(gameID: "zenless-zone-zero", repository: repository)
        let expected = model.clips[0].id
        let retired = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(gameID: "minetest", repository: repository)
        }
        await retired.value
        XCTAssertEqual(model.clips.map(\.id), [expected])
        XCTAssertEqual(model.loadedGameID, "zenless-zone-zero")
        XCTAssertEqual(repository.requestedClipGames, ["zenless-zone-zero"])
    }

    private func guide(gameID: String = "zenless-zone-zero", status: String = "published",
                       source: String = "https://example.com/guide") -> GameGuide {
        GameGuide(id: UUID(), gameID: gameID, title: "Build basics", summary: "An original short summary.",
                  sourceURL: source, sourceName: "Source publisher", sourceAuthor: "Author",
                  attribution: "Read the original guide at its source.", status: status,
                  publishedAt: "2026-11-04T08:00:00Z")
    }

    private func clip(gameID: String? = "zenless-zone-zero", status: String = "approved",
                      category: ClipContentCategory = .gaming) -> ApprovedClip {
        let owner = UUID(), id = UUID()
        return ApprovedClip(id: id, ownerID: owner, gameID: gameID, caption: "Gameplay\nSource credits.",
            videoPath: "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased())/clip.mp4",
            thumbnailPath: nil, status: status, createdAt: "2026-11-04T08:00:00Z", approvedAt: nil, game: nil,
            contentCategory: category)
    }
}

@MainActor
private final class GuideRepositoryDouble: SocialRepository {
    var currentUserID: UUID? = UUID()
    var guides: [GameGuide] = []
    var clips: [ApprovedClip] = []
    var requestedGuideGames: [String] = []
    var requestedClipGames: [String] = []
    var suspendsGuides = false
    var suspendsClips = false
    var failGuides = false
    var onGuideRequest: (() -> Void)?
    var onClipRequest: (() -> Void)?
    private var guideContinuation: CheckedContinuation<[GameGuide], Error>?
    private var clipContinuation: CheckedContinuation<[ApprovedClip], Error>?
    func publishedGuides(gameID: String) async throws -> [GameGuide] {
        requestedGuideGames.append(gameID)
        if suspendsGuides {
            return try await withCheckedThrowingContinuation { guideContinuation = $0; onGuideRequest?() }
        }
        if failGuides { throw UnusedCall.unexpected }
        return guides
    }
    func approvedClips(gameID: String) async throws -> [ApprovedClip] {
        requestedClipGames.append(gameID)
        if suspendsClips {
            return try await withCheckedThrowingContinuation { clipContinuation = $0; onClipRequest?() }
        }
        return clips
    }
    func completeGuides(_ rows: [GameGuide]) { guideContinuation?.resume(returning: rows); guideContinuation = nil }
    func completeClips(_ rows: [ApprovedClip]) { clipContinuation?.resume(returning: rows); clipContinuation = nil }
    func approvedClips() async throws -> [ApprovedClip] { throw UnusedCall.unexpected }
    func downloadClip(path: String) async throws -> Data { throw UnusedCall.unexpected }
    func downloadClipThumbnail(path: String) async throws -> Data { throw UnusedCall.unexpected }
    func players(query: String) async throws -> [PlayerProfile] { [] }
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
    func gameCards(userID: UUID) async throws -> [PlayerGameCard] { [] }
    func saveGameCard(gameID: String, playerName: String, daysPlayed: Int?, progress: String) async throws { throw UnusedCall.unexpected }
    func friendRequests() async throws -> [FriendRequest] { [] }
    func sendFriendRequest(to userID: UUID) async throws { throw UnusedCall.unexpected }
    func respondToFriendRequest(id: UUID, accept: Bool) async throws { throw UnusedCall.unexpected }
    func removeFriend(id: UUID) async throws { throw UnusedCall.unexpected }
    func conversations() async throws -> [DirectConversation] { [] }
    func messages(conversationID: UUID) async throws -> [ChatMessage] { [] }
    func sendMessage(conversationID: UUID, id: UUID, body: String) async throws { throw UnusedCall.unexpected }
    func blockUser(id: UUID) async throws { throw UnusedCall.unexpected }
    private enum UnusedCall: Error { case unexpected }
}
