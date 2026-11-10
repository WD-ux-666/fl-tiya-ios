import Foundation
import SwiftUI
import Supabase

struct PlayerProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String
    let bio: String
    let avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id, handle, bio
        case displayName = "display_name"
        case avatarPath = "avatar_path"
    }
}

struct PlayerGameCard: Codable, Sendable {
    let userID: UUID
    let gameID: String
    let playerName: String
    let daysPlayed: Int?
    let progress: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", gameID = "game_id", playerName = "player_name"
        case daysPlayed = "days_played", progress
    }

    // Explicit null lets an existing optional value be cleared during upsert.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(userID, forKey: .userID)
        try values.encode(gameID, forKey: .gameID)
        try values.encode(playerName, forKey: .playerName)
        try values.encode(daysPlayed, forKey: .daysPlayed)
        try values.encode(progress, forKey: .progress)
    }
}

struct FriendRequest: Decodable, Identifiable, Sendable {
    let id: UUID
    let senderID: UUID
    let recipientID: UUID
    let status: String
    enum CodingKeys: String, CodingKey {
        case id, status
        case senderID = "sender_id", recipientID = "recipient_id"
    }
}

struct DirectConversation: Decodable, Identifiable, Sendable {
    let id: UUID
    let userLow: UUID
    let userHigh: UUID
    enum CodingKeys: String, CodingKey {
        case id
        case userLow = "user_low", userHigh = "user_high"
    }
}

struct ChatMessage: Decodable, Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let senderID: UUID
    let body: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, body
        case conversationID = "conversation_id", senderID = "sender_id", createdAt = "created_at"
    }
}

struct PlayerConnection: Sendable {
    let request: FriendRequest?
    let conversation: DirectConversation?
    let isFriend: Bool
}

struct PlayerFollowState: Decodable, Sendable {
    let isFollowing: Bool
    let followerCount: Int
    enum CodingKeys: String, CodingKey {
        case isFollowing = "is_following", followerCount = "follower_count"
    }
}

struct ConversationMessagingState: Decodable, Sendable {
    let isFriend: Bool
    let canSend: Bool
    let hasSentIntroduction: Bool
    enum CodingKeys: String, CodingKey {
        case isFriend = "is_friend", canSend = "can_send", hasSentIntroduction = "has_sent_introduction"
    }
}

enum SocialDataFailure: Error {
    case conversationUnavailable
    case introductionLimitReached
    case accountChanged
    case invalidClipMedia
}

@MainActor
protocol SocialRepository {
    var currentUserID: UUID? { get }
    func approvedClips() async throws -> [ApprovedClip]
    func approvedClips(gameID: String) async throws -> [ApprovedClip]
    func publishedGuides(gameID: String) async throws -> [GameGuide]
    func downloadClip(path: String) async throws -> Data
    func downloadClipThumbnail(path: String) async throws -> Data
    func players(query: String) async throws -> [PlayerProfile]
    func communityPlayers(gameID: String?, query: String) async throws -> [CommunityPlayer]
    func blockedPlayers(before: BlockedPlayer?) async throws -> [BlockedPlayer]
    func unblockUser(id: UUID) async throws
    func profile(id: UUID) async throws -> PlayerProfile
    func playerFollowState(userID: UUID) async throws -> PlayerFollowState
    func setPlayerFollowed(userID: UUID, followed: Bool) async throws -> PlayerFollowState
    func openConversation(with userID: UUID) async throws -> DirectConversation
    func conversationMessagingState(conversationID: UUID) async throws -> ConversationMessagingState
    func connection(with userID: UUID) async throws -> PlayerConnection
    func updateProfile(displayName: String, bio: String) async throws
    func updateProfile(displayName: String, bio: String, avatarPath: String) async throws
    func uploadAvatar(_ data: Data) async throws -> String
    func downloadAvatar(path: String) async throws -> Data
    func clipSocialState(clipID: UUID) async throws -> ClipSocialState
    func setClipLiked(clipID: UUID, liked: Bool) async throws -> ClipSocialState
    func clipComments(clipID: UUID) async throws -> [ClipComment]
    func addClipComment(clipID: UUID, commentID: UUID, body: String) async throws -> ClipComment
    func deleteClipComment(id: UUID) async throws
    func submitReport(target: ReportTarget, reason: ReportReason, details: String?) async throws -> Bool
    func gameCards(userID: UUID) async throws -> [PlayerGameCard]
    func saveGameCard(gameID: String, playerName: String, daysPlayed: Int?, progress: String) async throws
    func friendRequests() async throws -> [FriendRequest]
    func sendFriendRequest(to userID: UUID) async throws
    func respondToFriendRequest(id: UUID, accept: Bool) async throws
    func removeFriend(id: UUID) async throws
    func conversations() async throws -> [DirectConversation]
    func messages(conversationID: UUID) async throws -> [ChatMessage]
    func sendMessage(conversationID: UUID, id: UUID, body: String) async throws
    func blockUser(id: UUID) async throws
}

extension SocialRepository {
    func submitReport(target: ReportTarget, reason: ReportReason, details: String?) async throws -> Bool {
        throw ReportFailure.unavailable
    }
}

private struct SocialRepositoryKey: EnvironmentKey {
    static let defaultValue: (any SocialRepository)? = nil
}

extension EnvironmentValues {
    var socialRepository: (any SocialRepository)? {
        get { self[SocialRepositoryKey.self] }
        set { self[SocialRepositoryKey.self] = newValue }
    }
}

/// A configured repository always uses the user's SDK session. No service key,
/// local identity override, demo records or client-assigned author is accepted.
@MainActor
final class SupabaseSocialRepository: SocialRepository {
    let client: SupabaseClient
    let visibility: SocialVisibility?
    var currentUserID: UUID? { client.auth.currentUser?.id }

    init(client: SupabaseClient, visibility: SocialVisibility? = nil) {
        self.client = client
        self.visibility = visibility
    }

    func submitReport(target: ReportTarget, reason: ReportReason, details: String?) async throws -> Bool {
        struct Parameters: Encodable {
            let p_target_type: String
            let p_target_id: UUID
            let p_reason: String
            let p_details: String?
        }
        struct SampleParameters: Encodable {
            let target_user_id: UUID
        }

        guard let actor = currentUserID else { throw ReportFailure.unavailable }
        do {
            let inserted: Bool
            if case .samplePlayer(let playerID) = target {
                inserted = try await client.rpc("report_curated_sample_player", params: SampleParameters(
                    target_user_id: playerID
                )).execute().value
            } else {
                inserted = try await client.rpc("submit_content_report", params: Parameters(
                    p_target_type: target.kind, p_target_id: target.targetID,
                    p_reason: reason.rawValue, p_details: details
                )).execute().value
            }
            guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
            visibility?.recordReport(target, by: actor)
            try Task.checkCancellation()
            return inserted
        } catch let error as PostgrestError where error.code == "42501" {
            throw ReportFailure.unavailable
        }
    }

    func approvedClips() async throws -> [ApprovedClip] {
        guard let userID = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let clips: [ApprovedClip] = try await client.from("video_posts")
            .select("id,owner_id,game_id,content_category,caption,video_path,thumbnail_path,status,created_at,approved_at,game:games(name)")
            .eq("status", value: "approved")
            .order("created_at", ascending: false).order("id", ascending: false)
            .limit(50).execute().value
        try Task.checkCancellation()
        guard currentUserID == userID else { throw SocialDataFailure.accountChanged }
        return clips.filter(\.canPlay)
    }

    func approvedClips(gameID: String) async throws -> [ApprovedClip] {
        guard let userID = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let clips: [ApprovedClip] = try await client.from("video_posts")
            .select("id,owner_id,game_id,content_category,caption,video_path,thumbnail_path,status,created_at,approved_at,game:games(name)")
            .eq("game_id", value: gameID).eq("content_category", value: "gaming").eq("status", value: "approved")
            .order("created_at", ascending: false).order("id", ascending: false)
            .limit(50).execute().value
        try Task.checkCancellation()
        guard currentUserID == userID else { throw SocialDataFailure.accountChanged }
        return clips.filter { $0.contentCategory == .gaming && $0.gameID == gameID && $0.canPlay }
    }

    func publishedGuides(gameID: String) async throws -> [GameGuide] {
        guard let userID = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        // Editorial content has a server-owned cohort and publication status.
        // Clients can read it, but cannot publish or change its provenance.
        let guides: [GameGuide] = try await client.from("guides")
            .select("id,game_id,title,summary,source_url,source_name,source_author,attribution,status,published_at")
            .eq("game_id", value: gameID).eq("status", value: "published")
            .order("published_at", ascending: false).order("id", ascending: false)
            .limit(50).execute().value
        try Task.checkCancellation()
        guard currentUserID == userID else { throw SocialDataFailure.accountChanged }
        return guides.filter { $0.gameID == gameID && $0.canBrowse }
    }

    func downloadClip(path: String) async throws -> Data {
        guard let userID = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        guard ClipMediaRules.isValidStoragePath(path) else { throw SocialDataFailure.invalidClipMedia }
        // The private bucket evaluates Storage RLS with the SDK's current user
        // session. Tokens and signed/public URLs never enter AVPlayer or the UI.
        // A fresh URL forces a new authorization decision instead of reusing a
        // previous account's cached HTTP response for this private object.
        let data = try await client.storage.from("clips")
            .download(path: path, cacheNonce: UUID().uuidString)
        try Task.checkCancellation()
        guard currentUserID == userID else { throw SocialDataFailure.accountChanged }
        try ClipMediaRules.validateDownload(data)
        return data
    }

    func downloadClipThumbnail(path: String) async throws -> Data {
        guard let userID = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        guard ClipMediaRules.isValidThumbnailPath(path) else { throw SocialDataFailure.invalidClipMedia }
        // The private bucket rechecks this session for every cover request; a
        // unique nonce avoids reusing another account's cached HTTP response.
        let data = try await client.storage.from("clips")
            .download(path: path, cacheNonce: UUID().uuidString)
        try Task.checkCancellation()
        guard currentUserID == userID else { throw SocialDataFailure.accountChanged }
        try ClipMediaRules.validateThumbnail(data)
        return data
    }

    func players(query: String) async throws -> [PlayerProfile] {
        struct Search: Encodable { let search_query: String }
        return try await client.rpc("discover_players", params: Search(search_query: query))
            .execute().value
    }

    func profile(id: UUID) async throws -> PlayerProfile {
        try await client.from("profiles").select().eq("id", value: id.uuidString)
            .single().execute().value
    }

    func playerFollowState(userID: UUID) async throws -> PlayerFollowState {
        struct Target: Encodable { let target_user_id: UUID }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let result: PlayerFollowState = try await client.rpc("player_follow_state", params: Target(target_user_id: userID)).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return result
    }

    func setPlayerFollowed(userID: UUID, followed: Bool) async throws -> PlayerFollowState {
        struct Follow: Encodable { let target_user_id: UUID; let followed: Bool }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        guard actor != userID else { throw SocialDataFailure.conversationUnavailable }
        let result: PlayerFollowState = try await client.rpc("set_player_followed", params: Follow(target_user_id: userID, followed: followed)).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return result
    }

    func openConversation(with userID: UUID) async throws -> DirectConversation {
        struct Target: Encodable { let target_user_id: UUID }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        guard actor != userID else { throw SocialDataFailure.conversationUnavailable }
        let result: DirectConversation = try await client.rpc("open_direct_conversation", params: Target(target_user_id: userID)).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return result
    }

    func conversationMessagingState(conversationID: UUID) async throws -> ConversationMessagingState {
        struct Target: Encodable { let target_conversation_id: UUID }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        do {
            let result: ConversationMessagingState = try await client.rpc("conversation_messaging_state", params: Target(target_conversation_id: conversationID)).execute().value
            try Task.checkCancellation()
            guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
            return result
        } catch let error as PostgrestError where error.code == "42501" {
            throw SocialDataFailure.conversationUnavailable
        }
    }

    func connection(with userID: UUID) async throws -> PlayerConnection {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        // RLS restricts these to the actor's rows; filtering by the peer avoids
        // inferring a missing relationship from a paginated inbox snapshot.
        let peer = userID.uuidString
        let requests: [FriendRequest] = try await client.from("friend_requests").select()
            .or("sender_id.eq.\(peer),recipient_id.eq.\(peer)")
            .in("status", values: ["pending", "accepted"])
            .order("created_at", ascending: false).order("id", ascending: false).limit(1).execute().value
        let conversations: [DirectConversation] = try await client.from("conversations").select()
            .or("user_low.eq.\(peer),user_high.eq.\(peer)").limit(1).execute().value
        // Conversation history survives ordinary removal. Only the current
        // friendship row authorizes friend actions, regardless of old requests.
        struct Friendship: Decodable { let user_low: UUID }
        let pair = [actor.uuidString, peer].sorted()
        let friendships: [Friendship] = try await client.from("friendships").select("user_low")
            .eq("user_low", value: pair[0]).eq("user_high", value: pair[1])
            .limit(1).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return PlayerConnection(request: requests.first, conversation: conversations.first, isFriend: !friendships.isEmpty)
    }

    func updateProfile(displayName: String, bio: String) async throws {
        struct Update: Encodable { let display_name: String; let bio: String }
        guard let id = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        // Returning a single row detects a denied/no-op update instead of displaying success.
        let _: PlayerProfile = try await client.from("profiles")
            .update(Update(display_name: displayName, bio: bio))
            .eq("id", value: id.uuidString).select().single().execute().value
    }

    func gameCards(userID: UUID) async throws -> [PlayerGameCard] {
        try await client.from("game_cards").select().eq("user_id", value: userID.uuidString)
            .order("game_id").limit(50).execute().value
    }

    func saveGameCard(gameID: String, playerName: String, daysPlayed: Int?, progress: String) async throws {
        guard let userID = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let card = PlayerGameCard(userID: userID, gameID: gameID, playerName: playerName,
                                  daysPlayed: daysPlayed, progress: progress)
        let _: PlayerGameCard = try await client.from("game_cards")
            .upsert(card, onConflict: "user_id,game_id").select().single().execute().value
    }

    func friendRequests() async throws -> [FriendRequest] {
        try await client.from("friend_requests").select().order("created_at", ascending: false)
            .limit(100).execute().value
    }

    func sendFriendRequest(to userID: UUID) async throws {
        struct Target: Encodable { let target_user_id: UUID }
        try await client.rpc("send_friend_request", params: Target(target_user_id: userID)).execute()
    }

    func respondToFriendRequest(id: UUID, accept: Bool) async throws {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Response: Encodable { let request_id: UUID; let accept: Bool }
        try await client.rpc("respond_friend_request", params: Response(request_id: id, accept: accept)).execute()
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
    }

    func removeFriend(id: UUID) async throws {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Target: Encodable { let target_user_id: UUID }
        try await client.rpc("remove_friend", params: Target(target_user_id: id)).execute()
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
    }

    func conversations() async throws -> [DirectConversation] {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let result: [DirectConversation] = try await client.from("conversations").select().order("created_at", ascending: false)
            .limit(100).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return result
    }

    func messages(conversationID: UUID) async throws -> [ChatMessage] {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct ConversationID: Decodable { let id: UUID }
        let visible: [ConversationID] = try await client.from("conversations").select("id")
            .eq("id", value: conversationID.uuidString).limit(1).execute().value
        guard !visible.isEmpty else { throw SocialDataFailure.conversationUnavailable }
        let newest: [ChatMessage] = try await client.from("messages").select()
            .eq("conversation_id", value: conversationID.uuidString)
            .order("created_at", ascending: false).order("id", ascending: false)
            .limit(100).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return Array(newest.reversed())
    }

    func sendMessage(conversationID: UUID, id: UUID, body: String) async throws {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Message: Encodable {
            let target_conversation_id: UUID
            let message_id: UUID
            let message_body: String
        }
        do {
            try await client.rpc("send_message", params: Message(target_conversation_id: conversationID,
                message_id: id, message_body: body)).execute()
            try Task.checkCancellation()
            guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        } catch let error as PostgrestError where error.code == "P0001" && error.message == "stranger_message_limit" {
            throw SocialDataFailure.introductionLimitReached
        } catch let error as PostgrestError where error.code == "42501" {
            throw SocialDataFailure.conversationUnavailable
        }
    }

    func blockUser(id: UUID) async throws {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Target: Encodable { let target_user_id: UUID }
        try await client.rpc("block_user", params: Target(target_user_id: id)).execute()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        visibility?.recordBlock(id, by: actor)
        try Task.checkCancellation()
    }
}
