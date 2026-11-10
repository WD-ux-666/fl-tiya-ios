import ImageIO
import SwiftUI
import UIKit

/// Every avatar is fetched with the current user's Storage session. There is no
/// cross-account disk cache or reusable public/signed URL.
@MainActor
struct PlayerAvatarView: View {
    let profile: PlayerProfile
    var size: CGFloat = 54
    @Environment(\.socialRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var loadedIdentity: String?
    @State private var refreshID = UUID()

    private var identity: String {
        "\(repository?.currentUserID?.uuidString ?? "signed-out")|\(profile.id)|\(profile.avatarPath ?? "none")|\(refreshID)"
    }

    var body: some View {
        Group {
            if let image, loadedIdentity == identity {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.24)
                            .strokeBorder(AppTheme.accent.opacity(0.45), lineWidth: 1)
                    }
            } else {
                AvatarPlaceholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(profile.displayName)'s avatar")
        .task(id: identity) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshID = UUID() }
            else if phase == .background { image = nil; loadedIdentity = nil }
        }
    }

    private func load() async {
        image = nil
        loadedIdentity = nil
        let request = identity
        guard let repository, let actor = repository.currentUserID,
              let path = profile.avatarPath, AvatarMediaRules.isValidPath(path, ownerID: profile.id),
              !Task.isCancelled else { return }
        do {
            let data = try await repository.downloadAvatar(path: path)
            guard request == identity, !Task.isCancelled, repository.currentUserID == actor,
                  data.count <= AvatarMediaRules.maximumDownloadBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 4_096, height <= 4_096,
                  let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512
                  ] as CFDictionary) else { return }
            image = UIImage(cgImage: decoded)
            loadedIdentity = request
        } catch {
            // A denied or missing image falls back to the arcade avatar; profile
            // text remains usable and the next entry/foreground retries access.
            guard request == identity else { return }
            image = nil
            loadedIdentity = nil
        }
    }
}
