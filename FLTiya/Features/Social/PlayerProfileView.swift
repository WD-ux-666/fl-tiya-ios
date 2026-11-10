import SwiftUI

@MainActor
struct PlayerProfileView: View {
    let userID: UUID
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.dismiss) private var dismiss
    @Environment(\.callCoordinator) private var calls
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var profile: PlayerProfile?
    @State private var cards: [PlayerGameCard] = []
    @State private var request: FriendRequest?
    // Navigation owns its snapshot; profile refreshes must not clear it.
    @State private var routedConversation: DirectConversation?
    @State private var isFriend = false
    @State private var followState: PlayerFollowState?
    @State private var showConversation = false
    @State private var isLoading = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var confirmBlock = false
    @State private var confirmRemoveFriend = false

    private var isOwnProfile: Bool { repository?.currentUserID == userID }
    private var isPlayerHidden: Bool { !isOwnProfile && visibility?.isPlayerHidden(userID) == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isPlayerHidden {
                    SocialThemePanel(theme: .profile) {
                        EmptyStateView(symbol: "person.crop.circle", title: "Profile unavailable",
                            message: "This player profile is no longer available.")
                    }
                } else {
                    profileFeedback
                    if let profile {
                        PlayerProfileHeader(profile: profile, followerCount: followState?.followerCount, isFriend: isFriend)
                        if !profile.bio.isEmpty {
                            PlayerProfileSection(title: "About") {
                                Text(profile.bio).font(.body).foregroundStyle(AppTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !isOwnProfile { connectionActions }
                        gameCardsSection
                    }
                }
            }
            .padding(20).padding(.bottom, 28)
        }
        .background { SocialThemeBackdrop(theme: .profile) }
        .safeAreaInset(edge: .top, spacing: 0) {
            PlayerProfileToolbar(isWorking: isWorking, onBack: { dismiss() },
                                 onBlock: isOwnProfile || isPlayerHidden || profile == nil ? nil : { confirmBlock = true })
        }
        .navigationTitle("Player profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Block this player?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block player", role: .destructive) { Task { await block() } }
        } message: {
            Text("They will be removed from your connections. Neither of you can send friend requests, messages or calls to the other. Manage blocked players from Settings > Blacklist.")
        }
        .confirmationDialog("Remove this friend?", isPresented: $confirmRemoveFriend, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) { Task { await removeFriend() } }
        } message: {
            Text("Calls will end. Each person can send one introduction while not friends, if they haven't used it before. You can add them again.")
        }
        .navigationDestination(isPresented: $showConversation) {
            if let routedConversation { ChatView(conversation: routedConversation) }
        }
        .task(id: isPlayerHidden) { await load() }
        .onChange(of: isPlayerHidden) { _, hidden in
            if hidden {
                // Keep the current chat route mounted so its report sheet can finish.
                loadID = UUID()
                isLoading = false
                clearProfile()
                errorMessage = nil
                confirmBlock = false
                confirmRemoveFriend = false
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var profileFeedback: some View {
        if isLoading {
            ProgressView().tint(SocialTheme.profile.tint)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        if let errorMessage {
            SocialThemePanel(theme: .profile) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(errorMessage).font(.subheadline)
                        .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.62))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                        .disabled(isWorking || isLoading)
                }
            }
        }
    }

    private var connectionActions: some View {
        PlayerProfileSection(title: "Connect") {
            VStack(alignment: .leading, spacing: 16) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { contactButtons }
                } else {
                    HStack(spacing: 12) { contactButtons }
                }
                Rectangle().fill(SocialTheme.profile.tint.opacity(0.18)).frame(height: 1)
                if isFriend {
                    Button("Remove friend", role: .destructive) { confirmRemoveFriend = true }
                        .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                } else if let request, request.status == "pending" {
                    if request.recipientID == repository?.currentUserID {
                        Text("Wants to connect with you").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 12) { requestButtons(request) }
                        } else {
                            HStack(spacing: 12) { requestButtons(request) }
                        }
                    } else {
                        Label("Friend request sent", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(SocialTheme.profile.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Button { Task { await sendRequest() } } label: {
                        SocialActionLabel(title: "Add friend", symbol: "person.badge.plus")
                    }.buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                }
                Text(isFriend ? "You can send unlimited messages to friends."
                    : "You can each send one introduction. Friendship unlocks unlimited messages.")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(SocialTheme.profile.tint.opacity(0.18)).frame(height: 1)
                FriendCallActions(canStart: canStartCall, notice: callNotice) { kind in
                    Task { await startCall(kind) }
                }
                if isWorking { ProgressView().tint(SocialTheme.profile.tint) }
            }.disabled(isWorking || isLoading)
        }
    }

    @ViewBuilder
    private var contactButtons: some View {
        if let followState {
            Button { Task { await toggleFollow() } } label: {
                SocialActionLabel(title: followState.isFollowing ? "Following" : "Follow",
                    symbol: followState.isFollowing ? "checkmark" : "plus")
            }
            .buttonStyle(SocialEditorButtonStyle(isPrimary: !followState.isFollowing))
        }
        Button { Task { await openMessage() } } label: {
            SocialActionLabel(title: "Message", symbol: "bubble.left.fill")
        }.buttonStyle(SocialEditorButtonStyle(isPrimary: true))
    }

    private func requestButtons(_ request: FriendRequest) -> some View {
        Group {
            Button { Task { await respond(to: request, accept: true) } } label: {
                SocialActionLabel(title: "Accept", symbol: "checkmark")
            }.buttonStyle(SocialEditorButtonStyle(isPrimary: true))
            Button { Task { await respond(to: request, accept: false) } } label: {
                SocialActionLabel(title: "Decline", symbol: "xmark")
            }.buttonStyle(SocialEditorButtonStyle(isPrimary: false))
        }
    }

    private var canStartCall: Bool {
        guard let calls, let actor = repository?.currentUserID else { return false }
        return isFriend && !isPlayerHidden && !isOwnProfile && !isLoading && !isWorking
            && calls.currentUserID == actor && !calls.isWorking && calls.call == nil
    }

    private var callNotice: String? {
        if isLoading { return "Checking your friendship…" }
        if !isFriend { return "Voice and video calls are available once you're friends. Following doesn't unlock calls." }
        if calls == nil || calls?.isServiceAvailable == false {
            return "Voice and video calls are temporarily unavailable. Try again later."
        }
        return nil
    }

    private func startCall(_ kind: CallKind) async {
        guard canStartCall else { return }
        await calls?.startCall(to: userID, kind: kind)
    }

    private var gameCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlayerProfileSectionTitle(title: "Game cards")
            if cards.isEmpty {
                SocialThemePanel(theme: .profile) {
                    Text("No games shared yet").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(cards, id: \.gameID) { card in
                            let game = gameDescriptor(for: card)
                            NavigationLink {
                                PersonalGameDetailView(game: game, userID: card.userID, cards: cards)
                                    .toolbar(.visible, for: .navigationBar)
                            } label: {
                                gameCard(card, game: game)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(game.name), \(card.playerName). Open game profile")
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func gameCard(_ card: PlayerGameCard, game: GameDescriptor) -> some View {
        SocialThemePanel(theme: .profile) {
            VStack(alignment: .leading, spacing: 12) {
                GameArtworkView(game: game, kind: .cover)
                    .frame(width: 216, height: 126).clipped().accessibilityHidden(true)
                HStack(alignment: .top, spacing: 10) {
                    Text(game.name).font(.headline).foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    GameGlyph(symbol: "arrow.up.right", size: 16).foregroundStyle(SocialTheme.profile.tint)
                        .accessibilityHidden(true)
                }
                Text(card.playerName).font(.subheadline).foregroundStyle(AppTheme.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let days = card.daysPlayed {
                    Text("\(days.formatted()) days played").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                }
                if !card.progress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(card.progress).font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(width: 252)
    }

    private func gameDescriptor(for card: PlayerGameCard) -> GameDescriptor {
        GameCatalog.games.first { $0.id == card.gameID }
            ?? GameDescriptor(id: card.gameID, name: card.gameID, monogram: "GAME", introduction: "A personal game profile.")
    }

    private func load(isAfterMutation: Bool = false) async {
        guard !isPlayerHidden, let repository, !isWorking || isAfterMutation else { return }
        let actor = repository.currentUserID
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        defer { if loadID == id { isLoading = false } }
        do {
            let loadedProfile = try await repository.profile(id: userID)
            guard loadID == id, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            let loadedCards = try await repository.gameCards(userID: userID)
            guard loadID == id, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            let loadedFollow = isOwnProfile ? nil : try await repository.playerFollowState(userID: userID)
            guard loadID == id, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            let connection: PlayerConnection
            if isOwnProfile {
                connection = PlayerConnection(request: nil, conversation: nil, isFriend: false)
            } else {
                connection = try await repository.connection(with: userID)
            }
            guard loadID == id, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            profile = loadedProfile
            followState = loadedFollow
            cards = loadedCards
            request = connection.request
            isFriend = connection.isFriend
        } catch {
            guard loadID == id, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            clearProfile()
            errorMessage = "We couldn't load this profile. Please try again."
        }
    }

    private func clearProfile() {
        profile = nil
        followState = nil
        cards = []
        request = nil
        isFriend = false
    }

    private func beginMutation() {
        loadID = UUID()
        isLoading = false
        isWorking = true
    }

    private func toggleFollow() async {
        guard !isPlayerHidden, let repository, let actor = repository.currentUserID, actor != userID,
              let followState, !isWorking, !isLoading else { return }
        beginMutation()
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await repository.setPlayerFollowed(userID: userID, followed: !followState.isFollowing)
            guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
            self.followState = result
        } catch {
            if !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor { errorMessage = "We couldn't update your follow. Please try again." }
        }
    }

    private func openMessage() async {
        guard !isPlayerHidden, let repository, let actor = repository.currentUserID, actor != userID, !isWorking, !isLoading else { return }
        beginMutation()
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await repository.openConversation(with: userID)
            guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
            routedConversation = result
            showConversation = true
        } catch {
            if !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor { errorMessage = "We couldn't open this conversation. Please try again." }
        }
    }

    private func sendRequest() async {
        guard !isPlayerHidden, let repository, let actor = repository.currentUserID, !isWorking else { return }
        beginMutation()
        defer { isWorking = false }
        do {
            try await repository.sendFriendRequest(to: userID)
            guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
            await load(isAfterMutation: true)
        } catch {
            if !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor { errorMessage = "We couldn't send the request. Please try again." }
        }
    }

    private func respond(to request: FriendRequest, accept: Bool) async {
        guard !isPlayerHidden, let repository, let actor = repository.currentUserID, !isWorking,
              request.recipientID == actor, request.status == "pending" else { return }
        beginMutation()
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await repository.respondToFriendRequest(id: request.id, accept: accept)
        } catch {
            if !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor { errorMessage = "We couldn't update this request. Please refresh and try again." }
            return
        }
        guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
        self.request = nil
        isFriend = accept
        await load(isAfterMutation: true)
        guard accept, repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
        do {
            let result = try await repository.openConversation(with: userID)
            guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
            routedConversation = result
            showConversation = true
        } catch {
            if !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor { errorMessage = "You're now friends. Tap Message to try again." }
        }
    }

    private func block() async {
        guard !isPlayerHidden, let repository, let actor = repository.currentUserID, !isWorking else { return }
        beginMutation()
        defer { isWorking = false }
        do {
            try await repository.blockUser(id: userID)
            guard repository.currentUserID == actor, !Task.isCancelled else { return }
            await calls?.friendshipRemoved(with: userID)
            guard repository.currentUserID == actor, !Task.isCancelled else { return }
            dismiss()
        } catch {
            if !Task.isCancelled, repository.currentUserID == actor { errorMessage = "We couldn't block this player. Please try again." }
        }
    }

    private func removeFriend() async {
        guard !isPlayerHidden, let repository, let actor = repository.currentUserID, isFriend, !isWorking else { return }
        beginMutation()
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await repository.removeFriend(id: userID)
            guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
            await calls?.friendshipRemoved(with: userID)
            guard repository.currentUserID == actor, !Task.isCancelled, !isPlayerHidden else { return }
            request = nil
            isFriend = false
            await load(isAfterMutation: true)
        } catch {
            if !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor { errorMessage = "We couldn't remove this friend. Please refresh and try again." }
        }
    }
}

@MainActor
struct PlayerProfileToolbar: View {
    let isWorking: Bool
    let onBack: () -> Void
    let onBlock: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(isWorking: Bool, onBack: @escaping () -> Void, onBlock: (() -> Void)?) {
        self.isWorking = isWorking
        self.onBack = onBack
        self.onBlock = onBlock
    }

    var body: some View {
        VStack(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Player profile").font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
            }
            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                    .accessibilityIdentifier("playerProfile.back")
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Player profile").font(.headline).foregroundStyle(AppTheme.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let onBlock {
                    Button("Block", role: .destructive, action: onBlock)
                        .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                        .disabled(isWorking)
                        .accessibilityIdentifier("playerProfile.block")
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(AppTheme.background.opacity(0.96))
    }
}

@MainActor
struct PlayerProfileHeader: View {
    let profile: PlayerProfile
    let followerCount: Int?
    let isFriend: Bool
    let isSample: Bool

    init(profile: PlayerProfile, followerCount: Int?, isFriend: Bool, isSample: Bool = false) {
        self.profile = profile
        self.followerCount = followerCount
        self.isFriend = isFriend
        self.isSample = isSample
    }

    var body: some View {
        VStack(spacing: 14) {
            PlayerAvatarView(profile: profile, size: 104)
                .overlay {
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(SocialTheme.profile.tint.opacity(0.7), lineWidth: 2)
                }
                .accessibilityHidden(true)
            VStack(spacing: 7) {
                Text(profile.displayName).font(.title2.weight(.heavy)).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("@\(profile.handle)").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Handle @\(profile.handle)")
                if let followerCount {
                    Text("\(followerCount) followers")
                        .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                }
                if isSample {
                    Text("Sample player")
                        .font(.caption.weight(.heavy)).foregroundStyle(SocialTheme.profile.tint)
                }
                if isFriend {
                    Label("Friends", systemImage: "checkmark")
                        .font(.caption.weight(.heavy)).foregroundStyle(SocialTheme.profile.tint)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 16).frame(maxWidth: .infinity)
    }
}

@MainActor
struct PlayerProfileSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlayerProfileSectionTitle(title: title)
            SocialThemePanel(theme: .profile) { content }
        }
    }
}

private struct PlayerProfileSectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased()).font(.system(.caption, design: .monospaced, weight: .heavy))
            .tracking(1.5).foregroundStyle(SocialTheme.profile.tint)
            .accessibilityAddTraits(.isHeader)
    }
}

struct FriendCallActions: View {
    let canStart: Bool
    let notice: String?
    let onCall: (CallKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { callButtons }
                VStack(spacing: 12) { callButtons }
            }
            .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
            .disabled(!canStart)
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var callButtons: some View {
        Button { onCall(.voice) } label: {
            SocialActionLabel(title: "Voice call", symbol: "phone.fill")
        }
        Button { onCall(.video) } label: {
            SocialActionLabel(title: "Video call", symbol: "video.fill")
        }
    }
}
