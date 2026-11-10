import Foundation

struct GameGuide: Decodable, Identifiable, Sendable {
    let id: UUID
    let gameID: String
    let title: String
    let summary: String
    let sourceURL: String
    let sourceName: String
    let sourceAuthor: String?
    let attribution: String
    let status: String
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, attribution, status
        case gameID = "game_id", sourceURL = "source_url", sourceName = "source_name"
        case sourceAuthor = "source_author", publishedAt = "published_at"
    }

    var safeSourceURL: URL? { GuideSourceRules.url(sourceURL) }
    var canBrowse: Bool {
        status == "published" && publishedAt?.isEmpty == false && safeSourceURL != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var publicationDate: Date? {
        guard let publishedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: publishedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: publishedAt)
    }
}

enum GuideSourceRules {
    static func url(_ value: String) -> URL? {
        guard !value.isEmpty, value.utf8.count <= 2048,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              let host = parts.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              let url = parts.url else { return nil }
        return url
    }
}
