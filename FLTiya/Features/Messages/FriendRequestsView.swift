import SwiftUI

@MainActor
struct FriendRequestsView: View {
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.scenePhase) private var scenePhase
    @State private var requests: [FriendRequest] = []
    @State private var isLoading = false
    @State private var workingID: UUID?
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var openedConversation: DirectConversation?
    @State private var showConversation = false
    @State private var openedPlayerID: UUID?

    private var visibleRequests: [FriendRequest] {
        requests.filter { isVisible($0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                GameHeroHeader(eyebrow: "PARTY INVITES", title: "Make a connection.",
                    subtitle: "Accept an invite for unlimited messages and friend calls.", symbol: "person.badge.plus")
                if repository == nil {
                    AppCard {
                        EmptyStateView(symbol: "person.badge.plus", title: "New connections belong here",
                            message: "Friend requests aren't available in this preview.")
                    }
                } else {
                    SocialLoadFeedback(isLoading: isLoading, errorMessage: errorMessage) { Task { await load() } }
                    ForEach(visibleRequests, id: \.id) { request in
                        requestCard(request)
                    }
                    if visibleRequests.count == 100 {
                        Text("Showing the 100 most recent requests.").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    }
                    if visibleRequests.isEmpty, !isLoading, errorMessage == nil {
                        AppCard {
                            EmptyStateView(symbol: "person.badge.plus", title: "No requests yet",
                                message: "Visit a player's profile to send a friend request.")
                        }
                    }
                }
            }.padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Friend requests")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedPlayerID) { PlayerProfileView(userID: $0) }
        .navigationDestination(isPresented: $showConversation) {
            if let openedConversation { ChatView(conversation: openedConversation) }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .onChange(of: visibility?.playerRevision) {
            requests = visibleRequests
        }
        .onChange(of: visibility?.unblockRevision) {
            Task { await load(showProgress: false) }
        }
    }

    private func requestCard(_ request: FriendRequest) -> some View {
        let incoming = request.recipientID == repository?.currentUserID
        let peerID = incoming ? request.senderID : request.recipientID
        return AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    guard isVisible(request) else { return }
                    openedPlayerID = peerID
                } label: {
                    PlayerNameLabel(userID: peerID)
                }.buttonStyle(.plain)
                if incoming, request.status == "pending" {
                    Text("Wants to connect with you").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    HStack(spacing: 12) {
                        Button { Task { await respond(request, accept: true) } } label: {
                            SocialActionLabel(title: "Accept", symbol: "checkmark")
                        }.buttonStyle(.borderedProminent).foregroundStyle(AppTheme.onAccent)
                        Button { Task { await respond(request, accept: false) } } label: {
                            SocialActionLabel(title: "Decline", symbol: "xmark")
                        }.buttonStyle(.bordered).tint(AppTheme.secondaryInk)
                        if workingID == request.id { ProgressView() }
                    }.disabled(workingID != nil || isLoading)
                } else {
                    Text(request.status == "pending" ? "Request sent · Pending" : request.status.capitalized)
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
    }

    private func isVisible(_ request: FriendRequest) -> Bool {
        let peerID = request.senderID == repository?.currentUserID ? request.recipientID : request.senderID
        return visibility?.isPlayerHidden(peerID) != true
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
            let result = try await repository.friendRequests()
            guard loadID == id, !Task.isCancelled, repository.currentUserID == actor,
                  visibility?.unblockRevision == unblockRevision else { return }
            requests = result.filter { isVisible($0) }
            errorMessage = nil
        } catch {
            guard loadID == id, !Task.isCancelled, repository.currentUserID == actor,
                  visibility?.unblockRevision == unblockRevision else { return }
            if showProgress {
                requests = []
                errorMessage = "We couldn't load friend requests. Please try again."
            }
        }
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        guard let repository, let actor = repository.currentUserID, workingID == nil,
              request.recipientID == actor, request.status == "pending", isVisible(request) else { return }
        workingID = request.id
        defer { workingID = nil }
        do {
            try await repository.respondToFriendRequest(id: request.id, accept: accept)
        } catch {
            if !Task.isCancelled, repository.currentUserID == actor, isVisible(request) { errorMessage = "We couldn't update this request. Please refresh and try again." }
            return
        }
        guard repository.currentUserID == actor, !Task.isCancelled else { return }
        requests.removeAll { $0.id == request.id }
        await load(showProgress: false)
        guard accept, repository.currentUserID == actor, !Task.isCancelled, isVisible(request) else { return }
        do {
            let result = try await repository.openConversation(with: request.senderID)
            guard repository.currentUserID == actor, !Task.isCancelled, isVisible(request) else { return }
            openedConversation = result
            showConversation = true
        } catch {
            guard repository.currentUserID == actor, !Task.isCancelled, isVisible(request) else { return }
            errorMessage = "You're now friends. Open their profile and tap Message to try again."
        }
    }
}
