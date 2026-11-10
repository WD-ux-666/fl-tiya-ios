import Foundation
import Observation

@MainActor
protocol ClipPlaybackFileStore {
    func write(_ data: Data, userID: UUID, presentationID: UUID) throws -> URL
    func remove(_ url: URL)
}

@MainActor
struct ClipTemporaryFileStore: ClipPlaybackFileStore {
    private let root: URL

    init(root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("FLTiyaClipPlayback", isDirectory: true)) {
        self.root = root
    }

    func write(_ data: Data, userID: UUID, presentationID: UUID) throws -> URL {
        // Every component is generated locally, never taken from the server path.
        let folder = root.appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(presentationID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("clip.mp4")
        do {
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            return file
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func remove(_ url: URL) {
        // Only a URL created for this store's own presentation may be deleted.
        let folder = url.deletingLastPathComponent()
        let account = folder.deletingLastPathComponent()
        guard url.isFileURL, url.lastPathComponent == "clip.mp4",
              UUID(uuidString: folder.lastPathComponent) != nil,
              UUID(uuidString: account.lastPathComponent) != nil,
              account.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
        // Avoid leaving an empty per-account directory behind.
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: account.path), contents.isEmpty {
            try? FileManager.default.removeItem(at: account)
        }
    }
}

@MainActor
@Observable
final class ClipPlaybackModel {
    private(set) var fileURL: URL?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let files: any ClipPlaybackFileStore
    private let presentationID = UUID()
    private var generation = UUID()

    init(files: (any ClipPlaybackFileStore)? = nil) {
        self.files = files ?? ClipTemporaryFileStore()
    }

    func load(clip: ApprovedClip, repository: any SocialRepository, presentingUserID: UUID) async {
        clear()
        let request = generation
        guard !Task.isCancelled, repository.currentUserID == presentingUserID else { return }
        guard clip.canPlay else {
            errorMessage = "This clip is unavailable. Please refresh the feed."
            return
        }
        isLoading = true
        do {
            let data = try await repository.downloadClip(path: clip.videoPath)
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == presentingUserID else {
                clear()
                return
            }
            try ClipMediaRules.validateDownload(data)
            let file = try files.write(data, userID: presentingUserID, presentationID: presentationID)
            guard generation == request, !Task.isCancelled, repository.currentUserID == presentingUserID else {
                files.remove(file)
                if generation == request { clear() }
                return
            }
            fileURL = file
            isLoading = false
        } catch {
            guard generation == request else { return }
            guard !Task.isCancelled, repository.currentUserID == presentingUserID else {
                clear()
                return
            }
            isLoading = false
            errorMessage = "This clip couldn't be opened. Check your connection and try again."
        }
    }

    func clear() {
        generation = UUID()
        if let fileURL { files.remove(fileURL) }
        fileURL = nil
        isLoading = false
        errorMessage = nil
    }
}
