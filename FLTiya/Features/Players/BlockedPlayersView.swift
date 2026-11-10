import SwiftUI

@MainActor
struct BlockedPlayersView: View {
    @Environment(\.socialRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @State private var players: [BlockedPlayer] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var nextCursor: BlockedPlayer?
    @State private var loadMoreError: String?
    @State private var workingID: UUID?
    @State private var confirmation: BlockedPlayer?
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SocialThemeHero(theme: .players, eyebrow: "PLAYER SAFETY", title: "Your blocklist.",
                    subtitle: "Blocked players can't send you friend requests, messages or calls.")
                SocialLoadFeedback(isLoading: isLoading, errorMessage: errorMessage) {
                    Task { await load() }
                }
                ForEach(players) { player in
                    SocialThemePanel(theme: .players) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 12) {
                                AvatarPlaceholder(size: 44).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(player.displayName)
                                        .font(.headline).foregroundStyle(AppTheme.ink)
                                    Text("@\(player.handle)")
                                        .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                                        .lineLimit(2).truncationMode(.middle)
                                        .accessibilityLabel("Handle @\(player.handle)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack {
                                if workingID == player.id { ProgressView().tint(AppTheme.accent) }
                                Spacer(minLength: 0)
                                Button("Unblock") { confirmation = player }
                                    .font(.subheadline.weight(.bold))
                                    .frame(minHeight: 36)
                                    .buttonStyle(.bordered).tint(AppTheme.accent)
                                    .disabled(workingID != nil || isLoading)
                                    .accessibilityLabel("Unblock \(player.displayName)")
                            }
                        }
                    }
                }
                if players.isEmpty, !isLoading, errorMessage == nil {
                    SocialThemePanel(theme: .players) {
                        HStack(spacing: 16) {
                            ArcadeSticker(kind: .players, size: 56)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No blocked players")
                                    .font(.headline).foregroundStyle(AppTheme.ink)
                                Text("You can block someone from their player profile.")
                                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("Unblocking won't restore a friendship or reset message limits. Calls require a new accepted friend request.")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let loadMoreError {
                    Text(loadMoreError)
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
                if canLoadMore {
                    Button { Task { await loadMore() } } label: {
                        HStack(spacing: 10) {
                            if isLoadingMore { ProgressView().tint(AppTheme.accent) }
                            Text(loadMoreError == nil ? "Load more" : "Try loading more")
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(AppTheme.accent)
                    .disabled(isLoading || isLoadingMore || workingID != nil)
                }
            }
            .padding(20)
        }
        .background { SocialThemeBackdrop(theme: .players) }
        .navigationTitle("Blacklist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Unblock this player?", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible) {
            if let player = confirmation {
                Button("Unblock \(player.displayName)") {
                    confirmation = nil
                    Task { await unblock(player) }
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text("They can find your profile and send a new request. Unblocking doesn't add them as a friend.")
        }
        .task(id: repository?.currentUserID) { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func load() async {
        guard let repository, let actor = repository.currentUserID else { return }
        let id = UUID()
        loadID = id
        isLoading = true
        isLoadingMore = false
        canLoadMore = false
        nextCursor = nil
        loadMoreError = nil
        errorMessage = nil
        defer { if loadID == id { isLoading = false } }
        do {
            let result = try await repository.blockedPlayers(before: nil)
            guard loadID == id, repository.currentUserID == actor, !Task.isCancelled else { return }
            players = result
            nextCursor = result.last
            canLoadMore = result.count == BlockedPlayer.pageSize
        } catch {
            guard loadID == id, repository.currentUserID == actor, !Task.isCancelled else { return }
            errorMessage = "We couldn't load your blocklist. Please try again."
        }
    }

    private func loadMore() async {
        guard let repository, let actor = repository.currentUserID, let cursor = nextCursor,
              canLoadMore, !isLoading, !isLoadingMore, workingID == nil else { return }
        let id = loadID
        isLoadingMore = true
        loadMoreError = nil
        defer { if loadID == id { isLoadingMore = false } }
        do {
            let result = try await repository.blockedPlayers(before: cursor)
            guard loadID == id, repository.currentUserID == actor, !Task.isCancelled else { return }
            let existingIDs = Set(players.map(\.id))
            players.append(contentsOf: result.filter { !existingIDs.contains($0.id) })
            nextCursor = result.last
            canLoadMore = result.count == BlockedPlayer.pageSize
        } catch {
            guard loadID == id, repository.currentUserID == actor, !Task.isCancelled else { return }
            loadMoreError = "We couldn't load older blocks. Please try again."
        }
    }

    private func unblock(_ player: BlockedPlayer) async {
        guard let repository, let actor = repository.currentUserID, workingID == nil else { return }
        workingID = player.id
        errorMessage = nil
        defer { workingID = nil }
        do {
            try await repository.unblockUser(id: player.id)
            guard repository.currentUserID == actor, !Task.isCancelled else { return }
            // A successful deletion changes the page boundaries. Start again
            // from page one so older entries are never skipped after removal.
            players.removeAll { $0.id == player.id }
            await load()
        } catch {
            guard repository.currentUserID == actor, !Task.isCancelled else { return }
            errorMessage = "We couldn't unblock this player. Please try again."
        }
    }
}
