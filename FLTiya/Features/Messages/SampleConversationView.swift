import SwiftUI

struct SampleIntroduction: Codable, Identifiable {
    let id: UUID
    let handle: String
    let gameID: String?
    let body: String
    let sentAt: Date
}

/// Sample interactions belong to the current one-tap account on this device.
/// They are never sent to an actual player or to a live social service.
@MainActor
@Observable
final class SampleMessageStore {
    private struct Inbox: Codable {
        let ownerID: UUID
        var introductions: [SampleIntroduction]
        var followedPublisherIDs: Set<UUID>? = nil
    }

    private var inbox: Inbox?
    private(set) var isUnavailable = false

    func introductions(for ownerID: UUID?) -> [SampleIntroduction] {
        guard let ownerID, inbox?.ownerID == ownerID else { return [] }
        return inbox?.introductions ?? []
    }

    func load(for ownerID: UUID) {
        inbox = nil
        isUnavailable = false
        do {
            let saved: Inbox?
            do {
                saved = try JSONDecoder().decode(Inbox.self, from: Data(contentsOf: Self.fileURL()))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                saved = nil
            }
            inbox = saved?.ownerID == ownerID ? saved : Inbox(ownerID: ownerID, introductions: [])
        } catch {
            isUnavailable = true
        }
    }

    func isReady(for ownerID: UUID?) -> Bool {
        guard let ownerID else { return false }
        return inbox?.ownerID == ownerID
    }

    func save(_ body: String, to player: CommunityPlayer, ownerID: UUID) throws {
        let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var updated = inbox, updated.ownerID == ownerID, player.isSample == true,
              !message.isEmpty, message.unicodeScalars.count <= 2_000 else { throw SaveError.unavailable }
        guard !updated.introductions.contains(where: { $0.id == player.id }) else { return }
        updated.introductions.insert(SampleIntroduction(id: player.id, handle: player.handle,
            gameID: player.sampleGameID, body: message, sentAt: .now), at: 0)
        try persist(updated)
    }

    func isFollowingPublisher(_ publisherID: UUID, ownerID: UUID?) -> Bool {
        guard isReady(for: ownerID) else { return false }
        return inbox?.followedPublisherIDs?.contains(publisherID) == true
    }

    func setPublisherFollow(_ publisher: CommunityPlayer, following: Bool, ownerID: UUID) throws {
        guard var updated = inbox, updated.ownerID == ownerID, publisher.id != ownerID,
              publisher.isSample == true else { throw SaveError.unavailable }
        var followed = updated.followedPublisherIDs ?? []
        if following {
            followed.insert(publisher.id)
        } else {
            followed.remove(publisher.id)
        }
        updated.followedPublisherIDs = followed
        try persist(updated)
    }

    private func persist(_ updated: Inbox) throws {
        let url = try Self.fileURL()
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(updated).write(to: url, options: [.atomic, .completeFileProtection])
        inbox = updated
    }

    static func clearSavedInbox() {
        if let url = try? fileURL() { try? FileManager.default.removeItem(at: url) }
    }

    private static func fileURL() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw SaveError.unavailable }
        return support.appendingPathComponent("SampleMessages", isDirectory: true)
            .appendingPathComponent("inbox.json")
    }

    private enum SaveError: Error { case unavailable }
}

private struct SampleMessageStoreKey: EnvironmentKey {
    static let defaultValue: SampleMessageStore? = nil
}

extension EnvironmentValues {
    var sampleMessages: SampleMessageStore? {
        get { self[SampleMessageStoreKey.self] }
        set { self[SampleMessageStoreKey.self] = newValue }
    }
}

@MainActor
struct SampleConversationView: View {
    let sample: CommunityPlayer
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.sampleMessages) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var verifiedPlayer: CommunityPlayer?
    @State private var verifiedOwnerID: UUID?
    @State private var draft = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var loadID = UUID()
    @State private var openedProfile = false
    @State private var reportPresentation: ReportPresentation?

    private var ownerID: UUID? { repository?.currentUserID }
    private var isHidden: Bool { visibility?.isPlayerHidden(sample.id) == true }
    private var player: CommunityPlayer? {
        !isHidden && ownerID == verifiedOwnerID ? verifiedPlayer : nil
    }
    private var introduction: SampleIntroduction? {
        store?.introductions(for: ownerID).first { $0.id == sample.id }
    }
    private var messageBody: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isTooLong: Bool { messageBody.unicodeScalars.count > 2_000 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let player {
                    ConversationProfileLink {
                        openedProfile = true
                    } label: {
                        HStack(spacing: 12) {
                            PlayerAvatarView(profile: player.profile, size: 50).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(player.displayName).font(.headline).foregroundStyle(AppTheme.ink)
                                Text("@\(player.handle)").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Text("Sample chat. You can save one introduction on this device. Sample players can’t receive messages or take calls.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    if let introduction {
                        ConversationMessageBubble(text: introduction.body, date: introduction.sentAt, isMine: true)
                        Text("Introduction saved.").font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    } else if store?.isUnavailable == true {
                        Text("Sample messages are unavailable on this device. Pull to refresh and try again.")
                            .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    }
                } else if !isLoading, loadError == nil {
                    Text("This sample conversation is no longer available.").foregroundStyle(AppTheme.secondaryInk)
                }
                SocialLoadFeedback(isLoading: isLoading, errorMessage: loadError) { Task { await load() } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AppBackdrop() }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let player {
                ToolbarItem(placement: .topBarTrailing) {
                    let target = ReportTarget.samplePlayer(player.id)
                    ContentReportButton(target: target, compact: true) {
                        guard self.player?.id == player.id, let ownerID else { return }
                        reportPresentation = ReportPresentation(target: target, reporterID: ownerID)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ConversationCallButtons(canStart: false) { _ in }
                }
            }
        }
        .contentReportSheet(item: $reportPresentation, repository: repository)
        .navigationDestination(isPresented: $openedProfile) { SamplePlayerDetailView(sample: sample) }
        .safeAreaInset(edge: .bottom) {
            if player != nil, introduction == nil, store?.isReady(for: ownerID) == true { composer }
        }
        .task(id: isHidden) { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private var composer: some View {
        ConversationComposer(draft: $draft, errorMessage: sendError, canEdit: !isLoading,
            canSend: !isLoading && !messageBody.isEmpty && !isTooLong, isTooLong: isTooLong,
            sendLabel: "Save introduction on this device", onSend: send)
    }

    private func load() async {
        let id = UUID()
        loadID = id
        verifiedPlayer = nil
        verifiedOwnerID = nil
        loadError = nil
        isLoading = false
        guard !isHidden, let repository, let ownerID, let store else { return }
        if !store.isReady(for: ownerID) { store.load(for: ownerID) }
        isLoading = true
        defer { if loadID == id { isLoading = false } }
        do {
            let candidate = try await repository.findSamplePlayer(id: sample.id, gameID: sample.sampleGameID, handle: sample.handle)
            guard loadID == id, !Task.isCancelled, repository.currentUserID == ownerID, !isHidden else { return }
            verifiedPlayer = candidate
            verifiedOwnerID = ownerID
        } catch {
            guard loadID == id, !Task.isCancelled, repository.currentUserID == ownerID, !isHidden else { return }
            loadError = "We couldn't check this sample conversation. Please try again."
        }
    }

    private func send() {
        guard !isLoading, let player, let ownerID, let store, introduction == nil,
              !messageBody.isEmpty, !isTooLong else { return }
        sendError = nil
        do {
            try store.save(messageBody, to: player, ownerID: ownerID)
            draft = ""
        } catch {
            sendError = "We couldn't save your introduction. Please try again."
        }
    }
}
