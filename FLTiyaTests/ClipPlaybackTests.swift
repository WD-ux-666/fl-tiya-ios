import XCTest
import UIKit
@testable import FLTiya

@MainActor
final class ClipPlaybackTests: XCTestCase {
    func testWireContractPreservesSourceCreditsAndGameName() throws {
        let payload = Data(#"{"id":"A7B19CE3-EEFA-4088-8550-93C5DF3CEFA0","owner_id":"D4886EC3-970E-4404-A466-38FC2DC2D244","game_id":"licensed-game","caption":"Source creator: Example Studio. License: CC BY 4.0. Source: https://example.com/clip","video_path":"d4886ec3-970e-4404-a466-38fc2dc2d244/a7b19ce3-eefa-4088-8550-93c5df3cefa0/gameplay.mp4","thumbnail_path":null,"status":"approved","created_at":"2026-11-04T08:00:00Z","approved_at":"2026-11-04T08:00:01Z","game":{"name":"Licensed Game"}}"#.utf8)
        let clip = try JSONDecoder().decode(ApprovedClip.self, from: payload)
        XCTAssertTrue(clip.canPlay)
        XCTAssertEqual(clip.gameTitle, "Licensed Game")
        XCTAssertEqual(clip.contentCategory, .gaming)
        XCTAssertTrue(clip.caption.contains("Source creator: Example Studio"))
        XCTAssertTrue(clip.caption.contains("https://example.com/clip"))
    }

    func testLifestyleWireContractAllowsNoGameAndKeepsProvidedSourceText() throws {
        let clip = try decodeCategoryClip(category: "lifestyle", gameID: nil)
        XCTAssertNil(clip.gameID)
        XCTAssertNil(clip.game)
        XCTAssertEqual(clip.contentCategory, .lifestyle)
        XCTAssertEqual(clip.contentTitle, "Creators")
        XCTAssertEqual(clip.categoryTitle, "Lifestyle")
        XCTAssertTrue(clip.canPlay)
        XCTAssertEqual(clip.caption, "Creator: Provided creator. Source: https://example.com/source")
        XCTAssertFalse(clip.caption.contains("CC BY"))
    }

    func testInvalidCategoryAndGameCombinationsCannotPlay() throws {
        let combinations: [(String, String?)] = [("gaming", nil), ("gaming", ""), ("lifestyle", "licensed-game"),
                                               ("unsupported-category", nil), ("unsupported-category", "licensed-game")]
        for (category, gameID) in combinations {
            XCTAssertFalse(try decodeCategoryClip(category: category, gameID: gameID).canPlay)
        }
    }

    func testNullCategoryIsNotTreatedAsLegacyGaming() throws {
        let clip = try decodeCategoryClip(category: nil, gameID: "licensed-game")
        XCTAssertEqual(clip.contentCategory, .unsupported)
        XCTAssertFalse(clip.canPlay)
    }

    func testGeneralFeedIncludesGamingAndLifestyleButRejectsInvalidClassification() async throws {
        let gaming = clip()
        let lifestyle = try decodeCategoryClip(category: "lifestyle", gameID: nil)
        let repository = ClipRepositoryDouble()
        repository.clips = [gaming, lifestyle, try decodeCategoryClip(category: "lifestyle", gameID: "licensed-game"),
                            try decodeCategoryClip(category: "gaming", gameID: nil)]
        let model = ClipFeedModel()

        await model.load(repository: repository)

        XCTAssertEqual(model.clips.map(\.id), [gaming.id, lifestyle.id])
    }

    func testInvalidCategoryAndUnsafeLifestylePathsNeverDownload() async throws {
        let valid = try decodeCategoryClip(category: "lifestyle", gameID: nil)
        let mismatched = try decodeCategoryClip(category: "lifestyle", gameID: "licensed-game")
        let unsafe = ApprovedClip(id: valid.id, ownerID: valid.ownerID, gameID: nil, caption: valid.caption,
            videoPath: "https://example.com/clip.mp4", thumbnailPath: nil, status: "approved",
            createdAt: valid.createdAt, approvedAt: valid.approvedAt, game: nil, contentCategory: .lifestyle)
        let repository = ClipRepositoryDouble()
        let model = ClipPlaybackModel(files: ClipFileStoreDouble())

        for row in [mismatched, unsafe] {
            await model.load(clip: row, repository: repository, presentingUserID: repository.currentUserID!)
        }

        XCTAssertEqual(repository.downloadCount, 0)
        XCTAssertNil(model.fileURL)
    }

    func testFeedRejectsPendingRejectedAndMismatchedObjectPaths() async {
        let repository = ClipRepositoryDouble()
        let approved = clip()
        repository.clips = [approved, clip(status: "pending"), clip(status: "rejected"),
                            clip(path: "\(UUID())/\(UUID())/clip.mp4")]
        let model = ClipFeedModel()
        await model.load(repository: repository)
        XCTAssertEqual(model.clips.map(\.id), [approved.id])
    }

    func testFeedDiscardsResponseAfterAccountChanges() async {
        let repository = ClipRepositoryDouble()
        let started = expectation(description: "Feed request suspended")
        repository.suspendFeed = true
        repository.onFeedSuspend = { started.fulfill() }
        let model = ClipFeedModel()
        let request = Task { await model.load(repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.currentUserID = UUID()
        repository.completeFeed([clip()])
        await request.value
        XCTAssertTrue(model.clips.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testOlderFeedResponseCannotReplaceNewRefresh() async {
        let repository = ClipRepositoryDouble()
        let started = expectation(description: "Old feed request suspended")
        repository.suspendFeed = true
        repository.onFeedSuspend = { started.fulfill() }
        let model = ClipFeedModel()
        let oldRequest = Task { await model.load(repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.suspendFeed = false
        let newest = clip()
        repository.clips = [newest]
        await model.load(repository: repository)
        repository.completeFeed([clip()])
        await oldRequest.value
        XCTAssertEqual(model.clips.map(\.id), [newest.id])
    }

    func testUnsafeOrUnapprovedPathsNeverStartDownload() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        let model = ClipPlaybackModel(files: files)
        let unsafePaths = ["https://example.com/clip.mp4", "/absolute/clip.mp4",
                           "\(owner)/\(clipID)/../clip.mp4", "\(owner)/\(clipID)/%2e%2e/clip.mp4",
                           "\(owner)/\(clipID)/clip.mp4?token=secret", "\(owner)/\(clipID)/clip.mov",
                           "\(UUID())/\(clipID)/clip.mp4", "\(owner)/\(UUID())/clip.mp4"]
        for path in unsafePaths {
            await model.load(clip: clip(path: path), repository: repository,
                             presentingUserID: repository.currentUserID!)
        }
        await model.load(clip: clip(status: "pending"), repository: repository,
                         presentingUserID: repository.currentUserID!)
        XCTAssertEqual(repository.downloadCount, 0)
        XCTAssertTrue(files.written.isEmpty)
        XCTAssertNil(model.fileURL)
    }

    func testNetworkFailureHasSafeRetryAndDoesNotExposeServiceError() async {
        let repository = ClipRepositoryDouble()
        repository.downloadError = NSError(domain: "token=must-not-appear", code: 403)
        let model = ClipPlaybackModel(files: ClipFileStoreDouble())
        await model.load(clip: clip(), repository: repository, presentingUserID: repository.currentUserID!)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.errorMessage?.contains("token=") ?? true)
        XCTAssertNil(model.fileURL)
        repository.downloadError = nil
        await model.load(clip: clip(), repository: repository, presentingUserID: repository.currentUserID!)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.fileURL)
    }

    func testLogoutDuringDownloadDiscardsBytesWithoutWritingFile() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        let model = ClipPlaybackModel(files: files)
        let started = expectation(description: "Download suspended")
        repository.suspendDownload = true
        repository.onDownloadSuspend = { started.fulfill() }
        let userID = repository.currentUserID!
        let download = Task { await model.load(clip: clip(), repository: repository, presentingUserID: userID) }
        await fulfillment(of: [started], timeout: 1)
        repository.currentUserID = nil
        repository.completeDownload()
        await download.value
        XCTAssertNil(model.fileURL)
        XCTAssertTrue(files.written.isEmpty)
    }

    func testDismissDuringDownloadDiscardsLateBytes() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        let model = ClipPlaybackModel(files: files)
        let started = expectation(description: "Download suspended")
        repository.suspendDownload = true
        repository.onDownloadSuspend = { started.fulfill() }
        let download = Task { await model.load(clip: clip(), repository: repository,
                                               presentingUserID: repository.currentUserID!) }
        await fulfillment(of: [started], timeout: 1)
        model.clear()
        repository.completeDownload()
        await download.value
        XCTAssertNil(model.fileURL)
        XCTAssertTrue(files.written.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testCancelledTaskCannotWriteDownloadedFile() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        let model = ClipPlaybackModel(files: files)
        let started = expectation(description: "Download suspended")
        repository.suspendDownload = true
        repository.onDownloadSuspend = { started.fulfill() }
        let download = Task { await model.load(clip: clip(), repository: repository,
                                               presentingUserID: repository.currentUserID!) }
        await fulfillment(of: [started], timeout: 1)
        download.cancel()
        repository.completeDownload()
        await download.value
        XCTAssertNil(model.fileURL)
        XCTAssertTrue(files.written.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testEmptyAndOversizedDownloadsAreNotWritten() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        let model = ClipPlaybackModel(files: files)
        for data in [Data(), Data(count: ClipMediaRules.maximumDownloadBytes + 1)] {
            repository.bytes = data
            await model.load(clip: clip(), repository: repository,
                             presentingUserID: repository.currentUserID!)
            XCTAssertNil(model.fileURL)
            XCTAssertNotNil(model.errorMessage)
        }
        XCTAssertTrue(files.written.isEmpty)
    }

    func testStorageFailureDoesNotExposeFileForPlayback() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        files.writeError = CocoaError(.fileWriteOutOfSpace)
        let model = ClipPlaybackModel(files: files)
        await model.load(clip: clip(), repository: repository, presentingUserID: repository.currentUserID!)
        XCTAssertNil(model.fileURL)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testClearRemovesPresentationFileAndDoesNotReuseAcrossAccounts() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        let first = ClipPlaybackModel(files: files)
        let firstUserID = repository.currentUserID!
        await first.load(clip: clip(), repository: repository, presentingUserID: firstUserID)
        let firstURL = first.fileURL
        first.clear()
        XCTAssertEqual(files.removed, firstURL.map { [$0] } ?? [])
        XCTAssertNil(first.fileURL)

        let secondUserID = UUID()
        repository.currentUserID = secondUserID
        let second = ClipPlaybackModel(files: files)
        await second.load(clip: clip(), repository: repository, presentingUserID: secondUserID)
        XCTAssertNotEqual(firstURL, second.fileURL)
        XCTAssertEqual(files.accounts, [firstUserID, secondUserID])
        XCTAssertEqual(repository.downloadCount, 2)
    }

    func testIdentityChangeDuringFileWriteRemovesNewFile() async {
        let repository = ClipRepositoryDouble()
        let files = ClipFileStoreDouble()
        files.onWrite = { repository.currentUserID = UUID() }
        let model = ClipPlaybackModel(files: files)
        await model.load(clip: clip(), repository: repository, presentingUserID: repository.currentUserID!)
        XCTAssertNil(model.fileURL)
        XCTAssertEqual(files.removed, files.written)
    }

    func testTemporaryFileUsesControlledAccountAndPresentationPathAndIsDeleted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = ClipTemporaryFileStore(root: folder)
        let userID = UUID()
        let presentationID = UUID()
        let bytes = Data([1, 2, 3])
        let url = try files.write(bytes, userID: userID, presentationID: presentationID)
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.lastPathComponent, "clip.mp4")
        XCTAssertTrue(url.path.contains(userID.uuidString.lowercased()))
        XCTAssertTrue(url.path.contains(presentationID.uuidString.lowercased()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        files.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testThumbnailPathsAcceptOnlyOwnedPNGOrJPGObjects() {
        let prefix = "\(owner.uuidString.lowercased())/\(clipID.uuidString.lowercased())/"
        XCTAssertTrue(ClipMediaRules.isValidThumbnailPath(prefix + "cover.png", ownerID: owner, clipID: clipID))
        XCTAssertTrue(ClipMediaRules.isValidThumbnailPath(prefix + "cover.jpg", ownerID: owner, clipID: clipID))
        for path in [prefix + "clip.mp4", prefix + "cover.svg", prefix + "png", prefix + "../cover.png",
                     prefix + "%2e%2e/cover.png", prefix + "cover.png?token=secret",
                     "https://example.com/cover.png", "\(UUID())/\(clipID)/cover.png",
                     "\(owner)/\(UUID())/cover.png"] {
            XCTAssertFalse(ClipMediaRules.isValidThumbnailPath(path, ownerID: owner, clipID: clipID))
        }
    }

    func testMissingOrUnapprovedCoverNeverStartsThumbnailDownload() async {
        let repository = ClipRepositoryDouble()
        let model = ClipThumbnailModel(decode: { _ in UIImage() })
        await model.load(clip: clip(), repository: repository)
        await model.load(clip: thumbnailClip(status: "pending"), repository: repository)
        XCTAssertEqual(repository.thumbnailDownloadCount, 0)
        XCTAssertNil(model.image)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testThumbnailAccountChangeDiscardsBytesBeforeImageDecode() async {
        let repository = ClipRepositoryDouble()
        let started = expectation(description: "Cover request suspended")
        repository.suspendThumbnail = true
        repository.onThumbnailSuspend = { started.fulfill() }
        var decodeCount = 0
        let model = ClipThumbnailModel(decode: { _ in decodeCount += 1; return UIImage() })
        let request = Task { await model.load(clip: thumbnailClip(), repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.currentUserID = UUID()
        repository.completeThumbnail()
        await request.value
        XCTAssertEqual(decodeCount, 0)
        XCTAssertNil(model.image)
        XCTAssertFalse(model.isLoading)
    }

    func testThumbnailDisappearanceDiscardsLateBytesBeforeDecode() async {
        let repository = ClipRepositoryDouble()
        let started = expectation(description: "Cover request suspended")
        repository.suspendThumbnail = true
        repository.onThumbnailSuspend = { started.fulfill() }
        var decodeCount = 0
        let model = ClipThumbnailModel(decode: { _ in decodeCount += 1; return UIImage() })
        let request = Task { await model.load(clip: thumbnailClip(), repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        model.clear()
        repository.completeThumbnail()
        await request.value
        XCTAssertEqual(decodeCount, 0)
        XCTAssertNil(model.image)
        XCTAssertFalse(model.isLoading)
    }

    func testCancelledThumbnailRequestCannotDecodeOrDisplayImage() async {
        let repository = ClipRepositoryDouble()
        let started = expectation(description: "Cover request suspended")
        repository.suspendThumbnail = true
        repository.onThumbnailSuspend = { started.fulfill() }
        var decodeCount = 0
        let model = ClipThumbnailModel(decode: { _ in decodeCount += 1; return UIImage() })
        let request = Task { await model.load(clip: thumbnailClip(), repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        repository.completeThumbnail()
        await request.value
        XCTAssertEqual(decodeCount, 0)
        XCTAssertNil(model.image)
        XCTAssertFalse(model.isLoading)
    }

    func testThumbnailFailureCanRetryWithoutExposingServiceError() async {
        let repository = ClipRepositoryDouble()
        repository.thumbnailError = NSError(domain: "token=must-not-appear", code: 403)
        let model = ClipThumbnailModel(decode: { _ in UIImage() })
        await model.load(clip: thumbnailClip(), repository: repository)
        XCTAssertNil(model.image)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.errorMessage?.contains("token=") ?? true)
        repository.thumbnailError = nil
        await model.load(clip: thumbnailClip(), repository: repository)
        XCTAssertNotNil(model.image)
        XCTAssertNil(model.errorMessage)
        model.clear()
        XCTAssertNil(model.image)
    }

    func testEmptyAndOversizedThumbnailsAreRejectedBeforeDecode() async {
        let repository = ClipRepositoryDouble()
        var decodeCount = 0
        let model = ClipThumbnailModel(decode: { _ in decodeCount += 1; return UIImage() })
        for data in [Data(), Data(count: ClipMediaRules.maximumThumbnailBytes + 1)] {
            repository.thumbnailBytes = data
            await model.load(clip: thumbnailClip(), repository: repository)
            XCTAssertNil(model.image)
            XCTAssertNotNil(model.errorMessage)
        }
        XCTAssertEqual(decodeCount, 0)
    }

    func testInvalidImageBytesShowCoverFailureWithoutAffectingPlayback() async {
        let repository = ClipRepositoryDouble()
        let model = ClipThumbnailModel(decode: { _ in nil })
        let playable = thumbnailClip()
        await model.load(clip: playable, repository: repository)
        XCTAssertNil(model.image)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(playable.canPlay)
    }

    func testSupersededThumbnailResponseCannotReplaceNewImage() async {
        let repository = ClipRepositoryDouble()
        let started = expectation(description: "Old cover request suspended")
        repository.suspendThumbnail = true
        repository.onThumbnailSuspend = { started.fulfill() }
        var decodeCount = 0
        let model = ClipThumbnailModel(decode: { _ in decodeCount += 1; return UIImage() })
        let oldRequest = Task { await model.load(clip: thumbnailClip(), repository: repository) }
        await fulfillment(of: [started], timeout: 1)
        repository.suspendThumbnail = false
        await model.load(clip: thumbnailClip(), repository: repository)
        let latest = model.image
        repository.completeThumbnail()
        await oldRequest.value
        XCTAssertEqual(decodeCount, 1)
        XCTAssertTrue(model.image === latest)
    }

    private let owner = UUID(uuidString: "D4886EC3-970E-4404-A466-38FC2DC2D244")!
    private let clipID = UUID(uuidString: "A7B19CE3-EEFA-4088-8550-93C5DF3CEFA0")!

    private func decodeCategoryClip(category: String?, gameID: String?) throws -> ApprovedClip {
        let id = UUID()
        var row: [String: Any] = [
            "id": id.uuidString, "owner_id": owner.uuidString,
            "content_category": category.map { $0 as Any } ?? NSNull(),
            "caption": "Creator: Provided creator. Source: https://example.com/source",
            "game_id": gameID.map { $0 as Any } ?? NSNull(), "game": NSNull(), "thumbnail_path": NSNull(),
            "status": "approved", "created_at": "2026-11-05T08:00:00Z", "approved_at": "2026-11-05T08:00:01Z"
        ]
        row["video_path"] = "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased())/clip.mp4"
        return try JSONDecoder().decode(ApprovedClip.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private func clip(status: String = "approved", path: String? = nil) -> ApprovedClip {
        let id = path == nil && status == "approved" ? UUID() : clipID
        return ApprovedClip(id: id, ownerID: owner, gameID: "licensed-game", caption: "Source creator and license.",
            videoPath: path ?? "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased())/clip.mp4",
            thumbnailPath: nil, status: status, createdAt: "2026-11-04T08:00:00Z", approvedAt: nil, game: nil)
    }

    private func thumbnailClip(status: String = "approved") -> ApprovedClip {
        let prefix = "\(owner.uuidString.lowercased())/\(clipID.uuidString.lowercased())/"
        return ApprovedClip(id: clipID, ownerID: owner, gameID: "licensed-game", caption: "Source creator and license.",
            videoPath: prefix + "clip.mp4", thumbnailPath: prefix + "cover.png", status: status,
            createdAt: "2026-11-04T08:00:00Z", approvedAt: nil, game: nil)
    }
}

@MainActor
private final class ClipFileStoreDouble: ClipPlaybackFileStore {
    var written: [URL] = []
    var removed: [URL] = []
    var accounts: [UUID] = []
    var writeError: Error?
    var onWrite: (() -> Void)?
    func write(_ data: Data, userID: UUID, presentationID: UUID) throws -> URL {
        if let writeError { throw writeError }
        let url = URL(fileURLWithPath: "/tmp/clip-tests/\(userID)/\(presentationID)/clip.mp4")
        written.append(url)
        accounts.append(userID)
        onWrite?()
        return url
    }
    func remove(_ url: URL) { removed.append(url) }
}

@MainActor
private final class ClipRepositoryDouble: SocialRepository {
    func approvedClips(gameID: String) async throws -> [ApprovedClip] { throw UnusedCall.unexpected }
    func publishedGuides(gameID: String) async throws -> [GameGuide] { throw UnusedCall.unexpected }
    var currentUserID: UUID? = UUID()
    var clips: [ApprovedClip] = []
    var bytes = Data([1, 2, 3])
    var downloadCount = 0
    var downloadError: Error?
    var suspendDownload = false
    var onDownloadSuspend: (() -> Void)?
    var suspendFeed = false
    var onFeedSuspend: (() -> Void)?
    private var downloadContinuation: CheckedContinuation<Data, Error>?
    private var feedContinuation: CheckedContinuation<[ApprovedClip], Error>?
    var thumbnailBytes = Data([1, 2, 3])
    var thumbnailDownloadCount = 0
    var thumbnailError: Error?
    var suspendThumbnail = false
    var onThumbnailSuspend: (() -> Void)?
    private var thumbnailContinuation: CheckedContinuation<Data, Error>?

    func approvedClips() async throws -> [ApprovedClip] {
        if suspendFeed {
            return try await withCheckedThrowingContinuation { feedContinuation = $0; onFeedSuspend?() }
        }
        return clips
    }
    func completeFeed(_ clips: [ApprovedClip]) { feedContinuation?.resume(returning: clips); feedContinuation = nil }
    func downloadClip(path: String) async throws -> Data {
        downloadCount += 1
        if let downloadError { throw downloadError }
        if suspendDownload {
            return try await withCheckedThrowingContinuation { downloadContinuation = $0; onDownloadSuspend?() }
        }
        return bytes
    }
    func completeDownload() { downloadContinuation?.resume(returning: bytes); downloadContinuation = nil }
    func downloadClipThumbnail(path: String) async throws -> Data {
        thumbnailDownloadCount += 1
        if let thumbnailError { throw thumbnailError }
        if suspendThumbnail {
            return try await withCheckedThrowingContinuation { thumbnailContinuation = $0; onThumbnailSuspend?() }
        }
        return thumbnailBytes
    }
    func completeThumbnail() { thumbnailContinuation?.resume(returning: thumbnailBytes); thumbnailContinuation = nil }

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
