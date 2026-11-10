import SwiftUI

@MainActor
struct MessagesView: View {
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.sampleMessages) private var sampleMessages
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var conversations: [DirectConversation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var openedConversation: DirectConversation?
    @State private var openedSamplePlayer: CommunityPlayer?
    @State private var samplePlayers: [CommunityPlayer] = []
    @State private var sampleLoadID = UUID()
    @State private var isLoadingSamples = false
    @State private var sampleLoadFailed = false

    private var visibleConversations: [DirectConversation] {
        conversations.filter { isVisible($0) }
    }

    private var localIntroductions: [SampleIntroduction] {
        sampleMessages?.introductions(for: repository?.currentUserID)
            .filter { visibility?.isPlayerHidden($0.id) != true } ?? []
    }

    private var sampleListIdentity: [UUID] {
        localIntroductions.map(\.id)
    }

    private var visibleSamplePlayers: [CommunityPlayer] {
        let ids = Set(sampleListIdentity)
        return samplePlayers.filter { ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SocialThemeHero(theme: .messages, eyebrow: "COMMS", title: "Talk game.", subtitle: "")
                friendRequestsLink
                conversationsHeading
                if repository == nil {
                    conversationsEmptyState(title: "Messaging unavailable", message: "Not available in this preview.")
                } else {
                    SocialLoadFeedback(isLoading: isLoading, errorMessage: errorMessage) { Task { await load() } }
                    ForEach(visibleConversations, id: \.id) { conversation in
                        Button {
                            guard isVisible(conversation) else { return }
                            openedConversation = conversation
                        } label: {
                            SocialThemePanel(theme: .messages) {
                                HStack(spacing: 12) {
                                    PlayerNameLabel(userID: peerID(for: conversation))
                                    GameGlyph(symbol: "chevron.right", size: 16)
                                        .foregroundStyle(AppTheme.violet).accessibilityHidden(true)
                                }
                                .frame(minHeight: 44)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open conversation")
                    }
                    if visibleConversations.count == 100 {
                        Text("Showing the 100 most recent conversations.").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    }
                    sampleChats
                    if visibleConversations.isEmpty, visibleSamplePlayers.isEmpty,
                       !isLoadingSamples, !sampleLoadFailed, !isLoading, errorMessage == nil {
                        conversationsEmptyState(title: "No chats yet", message: "Open a player profile to send an introduction, or accept a friend request for unlimited messages.")
                    }
                }
            }
            .padding(20)
        }
        .background { SocialThemeBackdrop(theme: .messages) }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        // The active chat owns its report sheet even when its list row disappears.
        .navigationDestination(isPresented: Binding(
            get: { openedConversation != nil },
            set: { if !$0 { openedConversation = nil } }
        )) {
            if let openedConversation { ChatView(conversation: openedConversation) }
        }
        .navigationDestination(item: $openedSamplePlayer) { SampleConversationView(sample: $0) }
        .task { await load() }
        .task(id: sampleListIdentity) { await loadSampleChats() }
        .refreshable {
            await load()
            await loadSampleChats()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await load() }
                Task { await loadSampleChats() }
            }
        }
        .onChange(of: visibility?.playerRevision) {
            conversations = visibleConversations
        }
        .onChange(of: visibility?.unblockRevision) {
            Task { await load(showProgress: false) }
        }
    }

    @ViewBuilder
    private var sampleChats: some View {
        ForEach(visibleSamplePlayers) { player in
            Button {
                guard visibility?.isPlayerHidden(player.id) != true else { return }
                openedSamplePlayer = player
            } label: {
                SocialThemePanel(theme: .messages) {
                    HStack(spacing: 12) {
                        PlayerAvatarView(profile: player.profile, size: 44).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(player.displayName).font(.headline).foregroundStyle(AppTheme.ink)
                            Text("Sample chat").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        GameGlyph(symbol: "chevron.right", size: 16)
                            .foregroundStyle(AppTheme.violet).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open sample conversation")
        }
        SocialLoadFeedback(isLoading: isLoadingSamples,
                           errorMessage: sampleLoadFailed ? "We couldn't check all sample chats." : nil) {
            Task { await loadSampleChats() }
        }
    }

    private func loadSampleChats() async {
        let id = UUID()
        sampleLoadID = id
        samplePlayers = []
        isLoadingSamples = false
        sampleLoadFailed = false
        let introductions = localIntroductions
        guard let repository, let actor = repository.currentUserID, !introductions.isEmpty else { return }
        isLoadingSamples = true
        defer { if sampleLoadID == id { isLoadingSamples = false } }
        var result: [CommunityPlayer] = []
        var failed = false
        for introduction in introductions {
            guard sampleLoadID == id, !Task.isCancelled, repository.currentUserID == actor else { return }
            do {
                if let player = try await repository.findSamplePlayer(
                    id: introduction.id, gameID: introduction.gameID, handle: introduction.handle
                ) {
                    result.append(player)
                }
            } catch {
                failed = true
            }
        }
        guard sampleLoadID == id, !Task.isCancelled, repository.currentUserID == actor else { return }
        samplePlayers = result
        sampleLoadFailed = failed
    }

    private var friendRequestsLink: some View {
        NavigationLink { FriendRequestsView() } label: {
            SocialThemePanel(theme: .messages) {
                HStack(spacing: 14) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        SocialArtworkBadge(theme: .messages, size: 50).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Friend requests").font(.headline).foregroundStyle(AppTheme.ink)
                        Text("Accept or decline").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    GameGlyph(symbol: "chevron.right", size: 16)
                        .foregroundStyle(AppTheme.violet).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
        .buttonStyle(.plain)
    }

    private var conversationsHeading: some View {
        HStack(spacing: 10) {
            Text("Chats").font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Rectangle().fill(AppTheme.violet.opacity(0.25)).frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
    }

    private func conversationsEmptyState(title: String, message: String) -> some View {
        SocialThemePanel(theme: .messages) {
            HStack(alignment: .center, spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    SocialArtworkBadge(theme: .messages, size: 64)
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

    private func peerID(for conversation: DirectConversation) -> UUID {
        conversation.userLow == repository?.currentUserID ? conversation.userHigh : conversation.userLow
    }

    private func isVisible(_ conversation: DirectConversation) -> Bool {
        visibility?.isPlayerHidden(peerID(for: conversation)) != true
    }

    private func load(showProgress: Bool = true) async {
        guard let repository else { return }
        let actor = repository.currentUserID
        let unblockRevision = visibility?.unblockRevision
        let id = UUID()
        loadID = id
        if showProgress {
            isLoading = true
            errorMessage = nil
        }
        defer { if loadID == id { isLoading = false } }
        do {
            let result = try await repository.conversations()
            guard loadID == id, !Task.isCancelled, repository.currentUserID == actor,
                  visibility?.unblockRevision == unblockRevision else { return }
            conversations = result.filter { isVisible($0) }
            errorMessage = nil
        } catch {
            guard loadID == id, !Task.isCancelled, repository.currentUserID == actor,
                  visibility?.unblockRevision == unblockRevision else { return }
            if showProgress {
                conversations = []
                errorMessage = "We couldn't load conversations. Please try again."
            }
        }
    }
}

#Preview {
    NavigationStack { MessagesView() }.tint(AppTheme.accent)
}
