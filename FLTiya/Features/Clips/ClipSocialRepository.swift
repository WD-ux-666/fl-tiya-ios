import Foundation
import Supabase

extension SupabaseSocialRepository {
    func clipSocialState(clipID: UUID) async throws -> ClipSocialState {
        struct Target: Encodable { let target_clip_id: UUID }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let value: ClipSocialState = try await client.rpc("clip_social_state", params: Target(target_clip_id: clipID))
            .execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return value
    }

    func setClipLiked(clipID: UUID, liked: Bool) async throws -> ClipSocialState {
        struct Like: Encodable { let target_clip_id: UUID; let liked: Bool }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let value: ClipSocialState = try await client.rpc("set_clip_liked", params: Like(target_clip_id: clipID, liked: liked))
            .execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return value
    }

    func clipComments(clipID: UUID) async throws -> [ClipComment] {
        struct Target: Encodable { let target_clip_id: UUID }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let value: [ClipComment] = try await client.rpc("clip_comments", params: Target(target_clip_id: clipID))
            .execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return value
    }

    func addClipComment(clipID: UUID, commentID: UUID, body: String) async throws -> ClipComment {
        struct Comment: Encodable { let target_clip_id: UUID; let comment_id: UUID; let comment_body: String }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        let value: ClipComment = try await client.rpc("add_clip_comment", params: Comment(target_clip_id: clipID,
            comment_id: commentID, comment_body: body)).execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return value
    }

    func deleteClipComment(id: UUID) async throws {
        struct Target: Encodable { let comment_id: UUID }
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        try await client.rpc("delete_clip_comment", params: Target(comment_id: id)).execute()
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
    }
}
