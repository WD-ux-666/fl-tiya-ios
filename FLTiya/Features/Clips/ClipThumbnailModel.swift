import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ClipThumbnailModel {
    private(set) var image: UIImage?
    private(set) var loadedUserID: UUID?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private let decode: @MainActor (Data) -> UIImage?

    init(decode: (@MainActor (Data) -> UIImage?)? = nil) {
        self.decode = decode ?? Self.decodeImage
    }

    func load(clip: ApprovedClip, repository: (any SocialRepository)?) async {
        clear()
        let request = generation
        guard !Task.isCancelled, let repository, let userID = repository.currentUserID,
              clip.canPlay, let path = clip.thumbnailPath else { return }
        guard ClipMediaRules.isValidThumbnailPath(path, ownerID: clip.ownerID, clipID: clip.id) else {
            errorMessage = "Cover unavailable. You can still watch this clip."
            return
        }
        isLoading = true
        do {
            let data = try await repository.downloadClipThumbnail(path: path)
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else {
                clear()
                return
            }
            try ClipMediaRules.validateThumbnail(data)
            // Image decoding stays on MainActor and happens only after the
            // current account, request generation and cancellation checks.
            guard let decoded = decode(data) else { throw SocialDataFailure.invalidClipMedia }
            guard generation == request, !Task.isCancelled, repository.currentUserID == userID else {
                if generation == request { clear() }
                return
            }
            image = decoded
            loadedUserID = userID
            isLoading = false
        } catch {
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == userID else {
                clear()
                return
            }
            isLoading = false
            errorMessage = "Cover couldn't be loaded. You can still watch this clip."
        }
    }

    func clear() {
        generation = UUID()
        image = nil
        loadedUserID = nil
        isLoading = false
        errorMessage = nil
    }

    private static func decodeImage(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        // Small compressed files must not become unbounded decoded images.
        guard width > 0, height > 0, width <= 4_096, height <= 4_096 else { return nil }
        return image
    }
}
