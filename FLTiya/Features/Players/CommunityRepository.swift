import Foundation
import Supabase

/// A visible community entry and its relationship to the signed-in player.
struct CommunityPlayer: Decodable, Hashable, Identifiable, Sendable {
    enum Relationship: String, Decodable, Hashable, Sendable {
        case none, friends, incoming, outgoing
    }

    let id: UUID
    let handle: String
    let displayName: String
    let bio: String
    let avatarPath: String?
    let relationship: Relationship
    let requestID: UUID?
    let isSample: Bool?
    let sampleGameID: String?

    enum CodingKeys: String, CodingKey {
        case id, handle, bio, relationship
        case displayName = "display_name", avatarPath = "avatar_path", requestID = "request_id"
        case isSample = "is_sample", sampleGameID = "sample_game_id"
    }

    var profile: PlayerProfile {
        PlayerProfile(id: id, handle: handle, displayName: displayName, bio: bio, avatarPath: avatarPath)
    }
}

/// Only the owner of a block can read this limited identity projection. Normal
/// profile and avatar reads continue to exclude blocked people in both directions.
struct BlockedPlayer: Decodable, Identifiable, Sendable {
    static let pageSize = 50

    let id: UUID
    let handle: String
    let displayName: String
    let blockedAt: String

    enum CodingKeys: String, CodingKey {
        case id, handle
        case displayName = "display_name", blockedAt = "blocked_at"
    }
}

@MainActor
extension SocialRepository {
    func findSamplePlayer(id: UUID, gameID: String?, handle: String) async throws -> CommunityPlayer? {
        try await communityPlayers(gameID: gameID, query: handle)
            .first { $0.id == id && $0.isSample == true }
    }
}

@MainActor
extension SupabaseSocialRepository {
    func communityPlayers(gameID: String?, query: String) async throws -> [CommunityPlayer] {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Search: Encodable { let target_game_id: String?; let search_query: String }
        let result: [CommunityPlayer] = try await client.rpc("discover_community_players",
            params: Search(target_game_id: gameID, search_query: query)).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return result
    }

    func blockedPlayers(before: BlockedPlayer?) async throws -> [BlockedPlayer] {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Cursor: Encodable {
            let before_blocked_at: String?
            let before_user_id: UUID?
        }
        // Preserve the server timestamp verbatim: converting through Date can
        // lose microseconds and skip or repeat entries at a page boundary.
        let result: [BlockedPlayer] = try await client.rpc("list_blocked_players",
            params: Cursor(before_blocked_at: before?.blockedAt, before_user_id: before?.id)).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return result
    }

    func unblockUser(id: UUID) async throws {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        struct Target: Encodable { let target_user_id: UUID }
        try await client.rpc("unblock_user", params: Target(target_user_id: id)).execute()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        visibility?.recordUnblock(id, by: actor)
        try Task.checkCancellation()
    }
}
