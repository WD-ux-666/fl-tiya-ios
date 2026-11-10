import SwiftUI

@MainActor
struct PlayersView: View {
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var searchIsFocused: Bool
    @State private var searchText = ""
    @State private var players: [CommunityPlayer] = []
    @State private var selectedGameID: String? = GameCatalog.zenlessZoneZero.id
    @State private var workingPlayers: Set<UUID> = []
    @State private var actionErrors: [UUID: String] = [:]
    @State private var hasAppeared = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var openedPlayerID: UUID?
    @State private var openedSamplePlayer: CommunityPlayer?

    private var visiblePlayers: [CommunityPlayer] {
        players.filter { visibility?.isPlayerHidden($0.id) != true }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SocialThemeHero(theme: .players, eyebrow: "PLAYER SELECT", title: "Find your crew.", subtitle: "")
                communityPicker
                playerSearch
                discoveryHeading
                if repository == nil {
                    discoveryEmptyState(title: "Discovery unavailable", message: "Not available in this preview.")
                } else {
                    SocialLoadFeedback(isLoading: isLoading, errorMessage: errorMessage) {
                        Task { await load() }
                    }
                    ForEach(visiblePlayers) { player in
                        communityPlayerCard(player)
                    }
                    if visiblePlayers.isEmpty, !isLoading, errorMessage == nil {
                        if !normalizedSearch.isEmpty {
                            discoveryEmptyState(title: "No players found", message: selectedGameID == nil
                                ? "Try another name or handle."
                                : "Try another name or handle, or search in All players.")
                        } else if selectedGameID == nil {
                            discoveryEmptyState(title: "No players found", message: "Other players will appear here when available.")
                        } else {
                            discoveryEmptyState(title: "No community members yet",
                                message: "Players who add this game to their profile will appear here. Try another community or All players.")
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { SocialThemeBackdrop(theme: .players) }
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $openedPlayerID) { PlayerProfileView(userID: $0) }
        .navigationDestination(item: $openedSamplePlayer) { SamplePlayerDetailView(sample: $0) }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if hasAppeared { Task { await load() } }
            hasAppeared = true
        }
        .task(id: discoveryIdentity) {
            players = []
            actionErrors = [:]
            errorMessage = nil
            isLoading = true
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await load()
        }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onChange(of: visibility?.playerRevision) {
            players = visiblePlayers
        }
        .onChange(of: visibility?.unblockRevision) {
            Task { await load(showProgress: false) }
        }
    }

    private var normalizedSearch: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.hasPrefix("@") ? String(query.dropFirst()) : query
    }

    private var playerSearch: some View {
        SocialThemePanel(theme: .players) {
            HStack(spacing: 10) {
                ArcadeSticker(kind: .search, size: 32)
                    .accessibilityHidden(true)
                TextField("Name or handle", text: $searchText)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .tint(AppTheme.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchIsFocused)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Search players")
                    .accessibilityHint("Search by name or handle")
                    .onSubmit { searchIsFocused = false }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchIsFocused = true
                    } label: {
                        GameGlyph(symbol: "xmark", size: 16)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear player search")
                }
            }
        }
    }

    private var discoveryIdentity: String {
        "\(repository?.currentUserID?.uuidString ?? "signed-out")|\(selectedGameID ?? "all")|\(normalizedSearch)"
    }

    private var selectedCommunityName: String {
        selectedGameID.flatMap { id in GameCatalog.games.first { $0.id == id }?.name } ?? "All players"
    }

    private var communityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GAME COMMUNITIES")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .tracking(1.3).foregroundStyle(AppTheme.accent)
                Spacer()
                Menu {
                    Button("All players", action: showAllPlayers)
                    ForEach(GameCatalog.games) { game in
                        Button(game.name) { selectedGameID = game.id }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Change")
                        GameGlyph(symbol: "chevron.down", size: 13)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Choose game community")
            }
            SocialThemePanel(theme: .players) {
                HStack(spacing: 14) {
                    if let id = selectedGameID, let game = GameCatalog.games.first(where: { $0.id == id }) {
                        GameArtworkView(game: game, kind: .icon)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    } else {
                        ArcadeSticker(kind: .players, size: 52)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selectedCommunityName)
                            .font(.headline).foregroundStyle(AppTheme.ink)
                        Text(selectedGameID == nil ? "Find players across all games." : "Add a game to your profile to appear in its community.")
                            .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func showAllPlayers() {
        searchIsFocused = false
        selectedGameID = nil
    }

    private var discoveryHeading: some View {
        SocialSectionHeading(title: normalizedSearch.isEmpty ? "Community players" : "Search results", symbol: "person.2")
            .padding(.top, 2)
    }

    private func communityPlayerCard(_ player: CommunityPlayer) -> some View {
        SocialThemePanel(theme: .players) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    guard visibility?.isPlayerHidden(player.id) != true else { return }
                    if player.isSample == true {
                        openedSamplePlayer = player
                    } else {
                        openedPlayerID = player.id
                    }
                } label: {
                    playerRow(player)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open player profile")
                HStack(spacing: 12) {
                    if workingPlayers.contains(player.id) {
                        ProgressView().tint(AppTheme.accent)
                    }
                    Spacer(minLength: 0)
                    communityAction(player)
                }
                if let message = actionErrors[player.id] {
                    Text(message).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func communityAction(_ player: CommunityPlayer) -> some View {
        switch player.relationship {
        case .friends:
            Label("Friends", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                .frame(minHeight: 44)
        case .outgoing:
            Label("Requested", systemImage: "clock")
                .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                .frame(minHeight: 44)
        case .incoming:
            HStack(spacing: 12) {
                Button("Decline") { Task { await updateConnection(player, accept: false) } }
                    .buttonStyle(.bordered).tint(AppTheme.secondaryInk)
                Button("Accept") { Task { await updateConnection(player, accept: true) } }
                    .buttonStyle(.borderedProminent).tint(AppTheme.accent).foregroundStyle(AppTheme.onAccent)
            }
            .frame(minHeight: 44)
            .disabled(player.requestID == nil || workingPlayers.contains(player.id) || isLoading)
        case .none:
            Button { Task { await updateConnection(player, accept: nil) } } label: {
                Label("Add friend", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.bold)).frame(minHeight: 36)
            }
            .buttonStyle(.borderedProminent).tint(AppTheme.accent).foregroundStyle(AppTheme.onAccent)
            .disabled(workingPlayers.contains(player.id) || isLoading)
        }
    }

    private func playerRow(_ player: CommunityPlayer) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                PlayerAvatarView(profile: player.profile, size: 48).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(player.displayName)
                    .font(.headline).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if player.isSample == true {
                    SamplePlayerBadge()
                }
                Text("@\(player.handle)")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    .lineLimit(2).truncationMode(.middle)
                    .accessibilityLabel("Handle @\(player.handle)")
                if !player.bio.isEmpty {
                    Text(player.bio).font(.subheadline).foregroundStyle(AppTheme.secondaryInk).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            GameGlyph(symbol: "chevron.right", size: 16)
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 14)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func updateConnection(_ player: CommunityPlayer, accept: Bool?) async {
        guard let repository, let actor = repository.currentUserID, !workingPlayers.contains(player.id),
              visibility?.isPlayerHidden(player.id) != true else { return }
        workingPlayers.insert(player.id)
        actionErrors[player.id] = nil
        defer { workingPlayers.remove(player.id) }
        do {
            if let accept {
                guard let requestID = player.requestID else { return }
                try await repository.respondToFriendRequest(id: requestID, accept: accept)
            } else {
                try await repository.sendFriendRequest(to: player.id)
            }
            guard !Task.isCancelled, repository.currentUserID == actor,
                  visibility?.isPlayerHidden(player.id) != true else { return }
            await load()
        } catch {
            guard !Task.isCancelled, repository.currentUserID == actor,
                  visibility?.isPlayerHidden(player.id) != true else { return }
            actionErrors[player.id] = "We couldn't update this connection. Refresh and try again."
        }
    }

    private func discoveryEmptyState(title: String, message: String) -> some View {
        SocialThemePanel(theme: .players) {
            HStack(alignment: .center, spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    SocialArtworkBadge(theme: .players, size: 64)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline).foregroundStyle(AppTheme.ink)
                    Text(message)
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func load(showProgress: Bool = true) async {
        guard let repository else { return }
        let id = UUID()
        let query = normalizedSearch
        let gameID = selectedGameID
        let actor = repository.currentUserID
        let unblockRevision = visibility?.unblockRevision
        loadID = id
        if showProgress {
            isLoading = true
            errorMessage = nil
        }
        defer { if loadID == id { isLoading = false } }
        do {
            let result = try await repository.communityPlayers(gameID: gameID, query: query)
            guard loadID == id, query == normalizedSearch, gameID == selectedGameID,
                  visibility?.unblockRevision == unblockRevision,
                  repository.currentUserID == actor, !Task.isCancelled else { return }
            players = result.filter { visibility?.isPlayerHidden($0.id) != true }
            errorMessage = nil
        } catch {
            guard loadID == id, query == normalizedSearch, gameID == selectedGameID,
                  visibility?.unblockRevision == unblockRevision,
                  repository.currentUserID == actor, !Task.isCancelled else { return }
            if showProgress {
                players = []
                errorMessage = "We couldn't load players. Please try again."
            }
        }
    }
}

struct SamplePlayerBadge: View {
    var body: some View {
        Text("Sample player")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.accent.opacity(0.12), in: Capsule())
    }
}

@MainActor
struct SamplePlayerDetailView: View {
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.sampleMessages) private var sampleMessages
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let sample: CommunityPlayer
    @State private var player: CommunityPlayer?
    @State private var isWorking = false
    @State private var requestSent = false
    @State private var confirmBlock = false
    @State private var errorMessage: String?

    init(sample: CommunityPlayer) {
        self.sample = sample
        _player = State(initialValue: sample)
    }

    private var isHidden: Bool { visibility?.isPlayerHidden(sample.id) == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let errorMessage {
                    SocialThemePanel(theme: .profile) {
                        Text(errorMessage).font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                if let player, !isHidden {
                    PlayerProfileHeader(profile: player.profile, followerCount: nil, isFriend: false, isSample: true)
                    if !player.bio.isEmpty {
                        PlayerProfileSection(title: "About") {
                            Text(player.bio).foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    requestPanel(player)
                    if let gameID = player.sampleGameID,
                       let game = GameCatalog.games.first(where: { $0.id == gameID }) {
                        PlayerProfileSection(title: "Game cards") {
                            HStack(spacing: 10) {
                                GameArtworkView(game: game, kind: .icon)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityHidden(true)
                                Text(game.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                } else {
                    SocialThemePanel(theme: .profile) {
                        EmptyStateView(symbol: "person.crop.circle", title: "Profile unavailable",
                            message: "This sample player is no longer available.")
                    }
                }
            }
            .padding(20).padding(.bottom, 28)
        }
        .background { SocialThemeBackdrop(theme: .profile) }
        .safeAreaInset(edge: .top, spacing: 0) {
            PlayerProfileToolbar(isWorking: isWorking, onBack: { dismiss() },
                onBlock: player != nil && !isHidden ? { confirmBlock = true } : nil)
        }
        .navigationTitle("Player profile")
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Block this sample player?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
        } message: {
            Text("You can unblock them in Settings > Blacklist.")
        }
        .task(id: repository?.currentUserID) {
            await reload()
        }
        .refreshable { await reload() }
    }

    private func requestPanel(_ player: CommunityPlayer) -> some View {
        PlayerProfileSection(title: "Connect") {
            VStack(alignment: .leading, spacing: 16) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { contactButtons(player) }
                } else {
                    HStack(spacing: 12) { contactButtons(player) }
                }
                Rectangle().fill(SocialTheme.profile.tint.opacity(0.18)).frame(height: 1)
                if requestSent || player.relationship == .outgoing {
                    Label("Friend request sent", systemImage: "clock").foregroundStyle(SocialTheme.profile.tint)
                } else if player.relationship == .none {
                    Button { Task { await sendRequest() } } label: {
                        SocialActionLabel(title: "Add friend", symbol: "person.badge.plus")
                    }
                    .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                    .disabled(isWorking)
                }
                Text("You can send one sample introduction on this device. Sample players can’t accept requests or reply.")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(SocialTheme.profile.tint.opacity(0.18)).frame(height: 1)
                FriendCallActions(canStart: false, notice: "Voice and video calls unlock when a real player accepts your friend request.") { _ in }
                if isWorking { ProgressView().tint(SocialTheme.profile.tint) }
            }
        }
    }

    @ViewBuilder
    private func contactButtons(_ player: CommunityPlayer) -> some View {
        if let sampleMessages, let actor = repository?.currentUserID {
            let following = sampleMessages.isFollowingPublisher(player.id, ownerID: actor)
            Button {
                guard repository?.currentUserID == actor, !isHidden else { return }
                do {
                    try sampleMessages.setPublisherFollow(player, following: !following, ownerID: actor)
                    errorMessage = nil
                } catch {
                    errorMessage = "We couldn't save your follow on this device. Please try again."
                }
            } label: {
                SocialActionLabel(title: following ? "Following" : "Follow", symbol: following ? "checkmark" : "plus")
            }
            .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
            .disabled(!sampleMessages.isReady(for: actor))
            .accessibilityHint("Saved on this device for this sample player")
            NavigationLink {
                SampleConversationView(sample: player)
            } label: {
                SocialActionLabel(title: "Message", symbol: "bubble.left.fill")
            }
            .buttonStyle(SocialEditorButtonStyle(isPrimary: true))
        }
    }

    private func reload() async {
        guard !isWorking, !isHidden, let repository, let actor = repository.currentUserID else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        await refresh(using: repository, actor: actor)
    }

    private func sendRequest() async {
        guard !isWorking, !isHidden, !requestSent, let player, player.relationship == .none,
              let repository, let actor = repository.currentUserID else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await repository.sendFriendRequest(to: sample.id)
            guard repository.currentUserID == actor, !isHidden, !Task.isCancelled else { return }
            requestSent = true
            await refresh(using: repository, actor: actor)
        } catch {
            if repository.currentUserID == actor, !isHidden, !Task.isCancelled {
                errorMessage = "We couldn't send the request. Please try again."
            }
        }
    }

    private func refresh(using repository: any SocialRepository, actor: UUID) async {
        do {
            let result = try await repository.findSamplePlayer(id: sample.id, gameID: sample.sampleGameID, handle: sample.handle)
            guard repository.currentUserID == actor, !isHidden, !Task.isCancelled else { return }
            player = result
            requestSent = false
        } catch {
            if repository.currentUserID == actor, !isHidden, !Task.isCancelled {
                errorMessage = "We couldn't refresh this profile. Pull to refresh and try again."
            }
        }
    }

    private func block() async {
        guard !isWorking, !isHidden, player != nil, let repository, let actor = repository.currentUserID else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await repository.blockUser(id: sample.id)
            guard repository.currentUserID == actor, !Task.isCancelled else { return }
            dismiss()
        } catch {
            if repository.currentUserID == actor, !isHidden, !Task.isCancelled {
                errorMessage = "We couldn't block this player. Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack { PlayersView() }.tint(AppTheme.accent)
}
