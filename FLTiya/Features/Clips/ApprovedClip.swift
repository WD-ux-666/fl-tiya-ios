import Foundation

enum ClipContentCategory: String, Decodable, Sendable {
    case gaming
    case lifestyle
    case unsupported

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unsupported
    }
}

struct ApprovedClip: Decodable, Identifiable, Sendable {
    struct Game: Decodable, Sendable {
        let name: String
    }

    let id: UUID
    /// The importing account owns the row; it is not necessarily the source creator.
    let ownerID: UUID
    let gameID: String?
    let contentCategory: ClipContentCategory
    /// Retains provided creator/source credits and any documented usage terms.
    let caption: String
    let videoPath: String
    let thumbnailPath: String?
    let status: String
    let createdAt: String
    let approvedAt: String?
    let game: Game?

    enum CodingKeys: String, CodingKey {
        case id, caption, status, game
        case ownerID = "owner_id", gameID = "game_id", videoPath = "video_path"
        case thumbnailPath = "thumbnail_path", createdAt = "created_at", approvedAt = "approved_at"
        case contentCategory = "content_category"
    }

    init(id: UUID, ownerID: UUID, gameID: String?, caption: String, videoPath: String,
         thumbnailPath: String?, status: String, createdAt: String, approvedAt: String?, game: Game?,
         contentCategory: ClipContentCategory = .gaming) {
        self.id = id
        self.ownerID = ownerID
        self.gameID = gameID
        self.contentCategory = contentCategory
        self.caption = caption
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
        self.status = status
        self.createdAt = createdAt
        self.approvedAt = approvedAt
        self.game = game
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        gameID = try values.decodeIfPresent(String.self, forKey: .gameID)
        // Old server rows and source fixtures were all gaming clips. Explicit
        // null or unknown categories fail closed instead of inventing a game.
        contentCategory = values.contains(.contentCategory)
            ? try values.decodeIfPresent(ClipContentCategory.self, forKey: .contentCategory) ?? .unsupported
            : .gaming
        caption = try values.decode(String.self, forKey: .caption)
        videoPath = try values.decode(String.self, forKey: .videoPath)
        thumbnailPath = try values.decodeIfPresent(String.self, forKey: .thumbnailPath)
        status = try values.decode(String.self, forKey: .status)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        approvedAt = try values.decodeIfPresent(String.self, forKey: .approvedAt)
        game = try values.decodeIfPresent(Game.self, forKey: .game)
    }

    var contentTitle: String {
        switch contentCategory {
        case .gaming: gameTitle
        case .lifestyle: "Creators"
        case .unsupported: "Clips"
        }
    }

    var categoryTitle: String {
        switch contentCategory {
        case .gaming: "Gaming"
        case .lifestyle: "Lifestyle"
        case .unsupported: "Clips"
        }
    }

    var categorySymbol: String {
        contentCategory == .lifestyle ? "person.crop.rectangle" : "gamecontroller"
    }

    var gameTitle: String {
        if let name = game?.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        guard let gameID, !gameID.isEmpty else { return "Clips" }
        return gameID.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private var hasValidClassification: Bool {
        switch contentCategory {
        case .gaming:
            guard let gameID else { return false }
            return !gameID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .lifestyle: return gameID == nil
        case .unsupported: return false
        }
    }

    var canPlay: Bool {
        status == "approved" && hasValidClassification
            && ClipMediaRules.isValidStoragePath(videoPath, ownerID: ownerID, clipID: id)
    }
}

enum ClipMediaRules {
    // This first feed downloads short MP4s in memory before local playback.
    // Longer media needs a separate authenticated streaming implementation.
    static let maximumDownloadBytes = 32 * 1_024 * 1_024
    static let maximumThumbnailBytes = 2 * 1_024 * 1_024

    static func isValidStoragePath(_ path: String, ownerID: UUID? = nil, clipID: UUID? = nil) -> Bool {
        validObjectPath(path, extensions: ["mp4"], ownerID: ownerID, clipID: clipID)
    }

    static func isValidThumbnailPath(_ path: String, ownerID: UUID? = nil, clipID: UUID? = nil) -> Bool {
        validObjectPath(path, extensions: ["png", "jpg"], ownerID: ownerID, clipID: clipID)
    }

    private static func validObjectPath(_ path: String, extensions: Set<String>, ownerID: UUID?, clipID: UUID?) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 300 else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3,
              let pathOwner = UUID(uuidString: parts[0]),
              let pathClip = UUID(uuidString: parts[1]),
              parts[0].lowercased() == pathOwner.uuidString.lowercased(),
              parts[1].lowercased() == pathClip.uuidString.lowercased(),
              ownerID == nil || ownerID == pathOwner,
              clipID == nil || clipID == pathClip,
              let filename = parts.last,
              extensions.contains((filename as NSString).pathExtension.lowercased()) else { return false }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return parts.allSatisfy { part in
            !part.isEmpty && !part.hasPrefix(".") && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    static func validateDownload(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumDownloadBytes else {
            throw SocialDataFailure.invalidClipMedia
        }
    }

    static func validateThumbnail(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumThumbnailBytes else {
            throw SocialDataFailure.invalidClipMedia
        }
    }
}
