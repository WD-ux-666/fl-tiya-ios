import Foundation
import ImageIO
import Supabase
import UniformTypeIdentifiers

enum AvatarMediaFailure: Error {
    case invalidImage
    case invalidPath
}

/// Avatar objects are immutable, account-scoped JPEGs. Neither private URLs nor
/// original photo metadata are stored in a profile or handed to an image view.
enum AvatarMediaRules {
    static let maximumSourceBytes = 25 * 1_024 * 1_024
    static let maximumUploadBytes = 512 * 1_024
    static let maximumDownloadBytes = 5 * 1_024 * 1_024

    static func isValidPath(_ path: String, ownerID: UUID? = nil) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, path.utf8.count <= 150,
              let owner = UUID(uuidString: String(components[0])),
              ownerID == nil || ownerID == owner,
              String(components[0]) == owner.uuidString.lowercased() else { return false }
        let filename = String(components[1])
        let suffix = (filename as NSString).pathExtension
        let stem = (filename as NSString).deletingPathExtension
        guard ["jpg", "jpeg", "png", "webp"].contains(suffix),
              let identifier = UUID(uuidString: stem) else { return false }
        return stem == identifier.uuidString.lowercased()
    }

    static func validateUpload(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maximumUploadBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, width <= 512, width == height else { throw AvatarMediaFailure.invalidImage }
    }
}

/// ImageIO work is isolated from UI state. Only immutable Data crosses the actor
/// boundary, and a new image destination strips EXIF/location metadata.
actor AvatarImageProcessor {
    static let shared = AvatarImageProcessor()

    func normalizedJPEG(from data: Data) throws -> Data {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= AvatarMediaRules.maximumSourceBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000, height <= 16_000,
              Int64(width) * Int64(height) <= 120_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw AvatarMediaFailure.invalidImage }
        let edge = min(thumbnail.width, thumbnail.height)
        let crop = CGRect(x: CGFloat((thumbnail.width - edge) / 2), y: CGFloat((thumbnail.height - edge) / 2),
                          width: CGFloat(edge), height: CGFloat(edge))
        guard let square = thumbnail.cropping(to: crop) else { throw AvatarMediaFailure.invalidImage }
        let outputEdge = min(edge, 512)
        guard let context = CGContext(data: nil, width: outputEdge, height: outputEdge, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw AvatarMediaFailure.invalidImage
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let outputBounds = CGRect(x: 0, y: 0, width: CGFloat(outputEdge), height: CGFloat(outputEdge))
        context.fill(outputBounds)
        context.interpolationQuality = .high
        context.draw(square, in: outputBounds)
        guard let normalized = context.makeImage() else { throw AvatarMediaFailure.invalidImage }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AvatarMediaFailure.invalidImage
        }
        CGImageDestinationAddImage(destination, normalized, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AvatarMediaFailure.invalidImage }
        let encoded = result as Data
        try Task.checkCancellation()
        try AvatarMediaRules.validateUpload(encoded)
        return encoded
    }
}

extension SupabaseSocialRepository {
    func uploadAvatar(_ data: Data) async throws -> String {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        try Task.checkCancellation()
        try AvatarMediaRules.validateUpload(data)
        let path = "\(actor.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("avatars").upload(path, data: data,
            options: FileOptions(cacheControl: "0", contentType: "image/jpeg", upsert: false))
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        return path
    }

    func downloadAvatar(path: String) async throws -> Data {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        guard AvatarMediaRules.isValidPath(path) else { throw AvatarMediaFailure.invalidPath }
        try Task.checkCancellation()
        let data = try await client.storage.from("avatars").download(path: path, cacheNonce: UUID().uuidString)
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
        guard !data.isEmpty, data.count <= AvatarMediaRules.maximumDownloadBytes else { throw AvatarMediaFailure.invalidImage }
        return data
    }

    func updateProfile(displayName: String, bio: String, avatarPath: String) async throws {
        guard let actor = currentUserID else { throw AuthenticationFailure.invalidVerifiedUser }
        guard AvatarMediaRules.isValidPath(avatarPath, ownerID: actor) else { throw AvatarMediaFailure.invalidPath }
        struct Update: Encodable {
            let display_name: String
            let bio: String
            let avatar_path: String
        }
        try Task.checkCancellation()
        let _: PlayerProfile = try await client.from("profiles")
            .update(Update(display_name: displayName, bio: bio, avatar_path: avatarPath))
            .eq("id", value: actor.uuidString).select().single().execute().value
        try Task.checkCancellation()
        guard currentUserID == actor else { throw SocialDataFailure.accountChanged }
    }
}
