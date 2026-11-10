import XCTest
@testable import FLTiya

@MainActor
final class ShortClipPlaybackTests: XCTestCase {
    func testAlreadyCancelledRetiredTaskCannotClearCurrentPreparation() async {
        let fixture = ShortClipFixture()
        let started = expectation(description: "Current validation suspended")
        fixture.suspendsValidation = true
        fixture.onValidation = { started.fulfill() }
        let current = Task { await fixture.prepare() }
        await fulfillment(of: [started], timeout: 1)

        let retired = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await fixture.prepare()
        }
        await retired.value
        XCTAssertTrue(fixture.controller.isPreparing)
        XCTAssertEqual(fixture.repository.downloadCount, 1)
        XCTAssertTrue(fixture.files.removed.isEmpty)

        fixture.completeValidation(false)
        await current.value
        XCTAssertEqual(fixture.files.removed, fixture.files.written)
    }

    func testInactivePageNeverDownloadsOrCreatesPlayer() async {
        let fixture = ShortClipFixture()
        await fixture.controller.prepare(clip: fixture.clip, repository: fixture.repository,
                                         isActive: false, isMuted: true)
        XCTAssertEqual(fixture.repository.downloadCount, 0)
        XCTAssertNil(fixture.controller.player)
        XCTAssertFalse(fixture.controller.isPreparing)
    }

    func testDeactivateDuringDownloadCannotWriteOrCreatePlayer() async {
        let fixture = ShortClipFixture()
        let started = expectation(description: "Video download suspended")
        fixture.repository.suspendsDownload = true
        fixture.repository.onDownload = { started.fulfill() }
        let request = Task { await fixture.prepare() }
        await fulfillment(of: [started], timeout: 1)
        fixture.controller.stop()
        fixture.repository.completeDownload()
        await request.value
        XCTAssertTrue(fixture.files.written.isEmpty)
        XCTAssertNil(fixture.controller.player)
        XCTAssertFalse(fixture.controller.isPreparing)
    }

    func testDeactivateDuringAssetValidationRemovesFileAndRejectsLatePlayableResult() async {
        let fixture = ShortClipFixture()
        let started = expectation(description: "Local media validation suspended")
        fixture.suspendsValidation = true
        fixture.onValidation = { started.fulfill() }
        let request = Task { await fixture.prepare() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(fixture.files.written.count, 1)
        fixture.controller.stop()
        fixture.completeValidation(true)
        await request.value
        XCTAssertEqual(fixture.files.removed, fixture.files.written)
        XCTAssertNil(fixture.playback.fileURL)
        XCTAssertNil(fixture.controller.player)
        XCTAssertFalse(fixture.controller.isPreparing)
    }

    func testAccountChangeDuringValidationCleansUpWithoutLatePlayback() async {
        let fixture = ShortClipFixture()
        let started = expectation(description: "Local media validation suspended")
        fixture.suspendsValidation = true
        fixture.onValidation = { started.fulfill() }
        let request = Task { await fixture.prepare() }
        await fulfillment(of: [started], timeout: 1)
        fixture.repository.currentUserID = UUID()
        fixture.completeValidation(true)
        await request.value
        XCTAssertEqual(fixture.files.removed, fixture.files.written)
        XCTAssertNil(fixture.controller.player)
        XCTAssertNil(fixture.playback.fileURL)
    }

    func testCancelledValidationCannotCreatePlayerAndRemovesTemporaryFile() async {
        let fixture = ShortClipFixture()
        let started = expectation(description: "Local media validation suspended")
        fixture.suspendsValidation = true
        fixture.onValidation = { started.fulfill() }
        let request = Task { await fixture.prepare() }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        fixture.completeValidation(true)
        await request.value
        XCTAssertEqual(fixture.files.removed, fixture.files.written)
        XCTAssertNil(fixture.controller.player)
        XCTAssertFalse(fixture.controller.isPreparing)
    }

    func testInvalidMediaShowsRetryableErrorAndDeletesFile() async {
        let fixture = ShortClipFixture()
        await fixture.prepare()
        XCTAssertNotNil(fixture.controller.errorMessage)
        XCTAssertNil(fixture.controller.player)
        XCTAssertNil(fixture.playback.fileURL)
        XCTAssertEqual(fixture.files.removed, fixture.files.written)
        fixture.controller.stop()
        XCTAssertNil(fixture.controller.errorMessage)
    }
}

@MainActor
private final class ShortClipFixture {
    let repository = ShortClipRepositoryDouble()
    let files = ShortClipFilesDouble()
    lazy var playback = ClipPlaybackModel(files: files)
    lazy var controller = ShortClipPlaybackController(playback: playback, checkPlayable: { [weak self] _ in
        guard let self else { return false }
        if self.suspendsValidation {
            return try await withCheckedThrowingContinuation { self.validation = $0; self.onValidation?() }
        }
        return false
    })
    var suspendsValidation = false
    var onValidation: (() -> Void)?
    private var validation: CheckedContinuation<Bool, Error>?
    let clip: ApprovedClip = {
        let owner = UUID()
        let id = UUID()
        return ApprovedClip(id: id, ownerID: owner, gameID: "test-game", caption: "A real clip title\nSource credits.",
            videoPath: "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased())/clip.mp4",
            thumbnailPath: nil, status: "approved", createdAt: "2026-11-04T08:00:00Z", approvedAt: nil, game: nil)
    }()
    func prepare() async {
        await controller.prepare(clip: clip, repository: repository, isActive: true, isMuted: true)
    }
    func completeValidation(_ playable: Bool) { validation?.resume(returning: playable); validation = nil }
}

@MainActor
private final class ShortClipFilesDouble: ClipPlaybackFileStore {
    var written: [URL] = []
    var removed: [URL] = []
    func write(_ data: Data, userID: UUID, presentationID: UUID) throws -> URL {
        let file = URL(fileURLWithPath: "/tmp/short-clip-tests/\(userID)/\(presentationID)/clip.mp4")
        written.append(file)
        return file
    }
    func remove(_ url: URL) { removed.append(url) }
}

@MainActor
private final class ShortClipRepositoryDouble: SocialRepository {
    func approvedClips(gameID: String) async throws -> [ApprovedClip] { throw UnusedCall.unexpected }
    func publishedGuides(gameID: String) async throws -> [GameGuide] { throw UnusedCall.unexpected }
    var currentUserID: UUID? = UUID()
    var downloadCount = 0
    var suspendsDownload = false
    var onDownload: (() -> Void)?
    private var download: CheckedContinuation<Data, Error>?
    func downloadClip(path: String) async throws -> Data {
        downloadCount += 1
        if suspendsDownload {
            return try await withCheckedThrowingContinuation { download = $0; onDownload?() }
        }
        return Data([1, 2, 3])
    }
    func completeDownload() { download?.resume(returning: Data([1, 2, 3])); download = nil }
    func approvedClips() async throws -> [ApprovedClip] { [] }
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
