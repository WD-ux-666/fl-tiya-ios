import SwiftUI

@MainActor
struct ChatView: View {
    let conversation: DirectConversation
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.callCoordinator) private var calls
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var pending: PendingMessage?
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sendError: String?
    @State private var loadID = UUID()
    @State private var conversationUnavailable = false
    @State private var isFriend = false
    @State private var hasVerifiedConnection = false
    @State private var canSendMessage = false
    @State private var reportPresentation: ReportPresentation?
    @State private var openedPlayerID: UUID?

    private var peerID: UUID {
        conversation.userLow == repository?.currentUserID ? conversation.userHigh : conversation.userLow
    }
    private var isPeerHidden: Bool { visibility?.isPlayerHidden(peerID) == true }
    private var isUnavailable: Bool { conversationUnavailable || isPeerHidden }
    private var messageBody: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var bodyLength: Int { messageBody.unicodeScalars.count }
    private var connectionNotice: String {
        if isLoading { return "Loading your messages and checking this connection…" }
        guard hasVerifiedConnection else { return "Refresh to check your messages and connection." }
        if isFriend { return "You can send unlimited messages to friends." }
        return canSendMessage ? "You can send one introduction before you're friends."
            : "Your introduction has been sent. Become friends to send more messages."
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if isUnavailable {
                        AppCard {
                            EmptyStateView(symbol: "bubble.left.and.bubble.right",
                                title: "Conversation unavailable",
                                message: "This conversation is no longer available. Go back to your messages.")
                        }
                    } else {
                        ConversationProfileLink {
                            guard !isUnavailable else { return }
                            openedPlayerID = peerID
                        } label: {
                            PlayerNameLabel(userID: peerID)
                        }
                        Text(connectionNotice)
                            .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                        if let callNotice {
                            Text(callNotice).font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                        }
                        if messages.count == 100 {
                            Text("Showing the latest 100 messages.").font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        }
                        SocialLoadFeedback(isLoading: isLoading, errorMessage: errorMessage) { Task { await load() } }
                        if hasVerifiedConnection, messages.isEmpty, !isLoading, errorMessage == nil {
                            Text(isFriend ? "Say hello to your friend." : "Send a short introduction to this player.").foregroundStyle(AppTheme.secondaryInk).padding(.vertical)
                        }
                        ForEach(messages, id: \.id) { message in
                            bubble(message).id(message.id)
                        }
                    }
                }.padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
            .onChange(of: messages.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .background { AppBackdrop() }
        .navigationTitle("Conversation")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedPlayerID) { PlayerProfileView(userID: $0) }
        .toolbar {
            if let reportTarget {
                ToolbarItem(placement: .topBarTrailing) {
                    ContentReportButton(target: reportTarget, compact: true) {
                        guard !isUnavailable, let reporterID = repository?.currentUserID else { return }
                        reportPresentation = ReportPresentation(target: reportTarget, reporterID: reporterID)
                    }
                }
            }
            if !isUnavailable {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ConversationCallButtons(canStart: canStartCall) { kind in
                        Task { await startCall(kind) }
                    }
                }
            }
        }
        .contentReportSheet(item: $reportPresentation, repository: repository)
        .safeAreaInset(edge: .bottom) {
            if !isUnavailable { composer }
        }
        .task(id: isPeerHidden) { await load() }
        .onChange(of: isPeerHidden) { _, hidden in
            if hidden { markConversationUnavailable() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        ConversationMessageBubble(text: message.body, date: Self.messageDate(message.createdAt),
                                  isMine: message.senderID == repository?.currentUserID)
    }

    private var canStartCall: Bool {
        guard let calls, let actor = repository?.currentUserID else { return false }
        return hasVerifiedConnection && isFriend && !isUnavailable && !isLoading
            && calls.currentUserID == actor && !calls.isWorking && calls.call == nil
    }

    private var callNotice: String? {
        guard hasVerifiedConnection else { return nil }
        if isFriend && (calls == nil || calls?.isServiceAvailable == false) {
            return "Voice and video calls are temporarily unavailable. Try again later."
        }
        return nil
    }

    private func startCall(_ kind: CallKind) async {
        guard canStartCall else { return }
        await calls?.startCall(to: peerID, kind: kind)
    }

    private var reportTarget: ReportTarget? {
        guard !isUnavailable, let currentUserID = repository?.currentUserID,
              conversation.userLow == currentUserID || conversation.userHigh == currentUserID,
              peerID != currentUserID else { return nil }
        return .conversation(peerID)
    }

    private var canCompose: Bool {
        !isUnavailable && hasVerifiedConnection && !isLoading && (canSendMessage || pending?.body == messageBody)
    }

    private var composer: some View {
        ConversationComposer(draft: $draft, isSending: isSending, errorMessage: sendError,
            canEdit: !isSending && repository != nil && hasVerifiedConnection && !isLoading && (canSendMessage || pending != nil),
            canSend: !isSending && repository != nil && canCompose && !messageBody.isEmpty && bodyLength <= 2_000,
            isTooLong: bodyLength > 2_000,
            sendLabel: sendError == nil ? "Send message" : "Retry sending message") {
                Task { await send() }
        }
    }

    private func load() async {
        guard !isPeerHidden else { return }
        guard let repository else { return }
        guard let actor = repository.currentUserID else { return }
        let id = UUID()
        loadID = id
        isLoading = true
        hasVerifiedConnection = false
        errorMessage = nil
        defer { if loadID == id { isLoading = false } }
        do {
            let result = try await repository.messages(conversationID: conversation.id)
            guard loadID == id, !Task.isCancelled, !isPeerHidden, repository.currentUserID == actor else { return }
            let state = try await repository.conversationMessagingState(conversationID: conversation.id)
            guard loadID == id, !Task.isCancelled, !isPeerHidden, repository.currentUserID == actor else { return }
            conversationUnavailable = false
            messages = result
            isFriend = state.isFriend
            canSendMessage = state.canSend
            hasVerifiedConnection = true
        } catch SocialDataFailure.conversationUnavailable {
            guard loadID == id, !Task.isCancelled, !isPeerHidden, repository.currentUserID == actor else { return }
            markConversationUnavailable()
        } catch {
            guard loadID == id, !Task.isCancelled, !isPeerHidden, repository.currentUserID == actor else { return }
            // Hide cached text after permission loss, including a new block.
            messages = []
            isFriend = false
            canSendMessage = false
            errorMessage = "We couldn't load messages. Check your connection and try again."
        }
    }

    private func send() async {
        guard let repository, let actor = repository.currentUserID, canCompose, !isSending, !messageBody.isEmpty, bodyLength <= 2000 else { return }
        // Retrying the same draft reuses the request ID after an uncertain response.
        let attempt = pending.flatMap { $0.body == messageBody ? $0 : nil }
            ?? PendingMessage(id: UUID(), body: messageBody)
        pending = attempt
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await repository.sendMessage(conversationID: conversation.id, id: attempt.id, body: attempt.body)
            guard !Task.isCancelled, !isUnavailable, pending?.id == attempt.id, repository.currentUserID == actor else { return }
            draft = ""
            pending = nil
            await load()
        } catch SocialDataFailure.introductionLimitReached {
            guard !Task.isCancelled, !isUnavailable, pending?.id == attempt.id, repository.currentUserID == actor else { return }
            pending = nil
            canSendMessage = false
            sendError = "You have already sent your introduction. Become friends to send more messages."
            await load()
        } catch SocialDataFailure.conversationUnavailable {
            if !Task.isCancelled, !isUnavailable, pending?.id == attempt.id, repository.currentUserID == actor { markConversationUnavailable() }
        } catch {
            if !Task.isCancelled, !isUnavailable, pending?.id == attempt.id, repository.currentUserID == actor {
                sendError = "Delivery couldn't be confirmed. Tap send again to retry this message."
            }
        }
    }

    private func markConversationUnavailable() {
        // Invalidate any earlier refresh so it cannot restore cached text or
        // turn a permission failure into the empty-conversation greeting.
        loadID = UUID()
        isLoading = false
        conversationUnavailable = true
        isFriend = false
        hasVerifiedConnection = false
        canSendMessage = false
        messages = []
        draft = ""
        pending = nil
        sendError = nil
        errorMessage = nil
    }

    private static func messageDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct PendingMessage {
        let id: UUID
        let body: String
    }
}

struct ConversationProfileLink<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            AppCard {
                HStack(spacing: 12) {
                    label()
                    GameGlyph(symbol: "arrow.up.right", size: 18)
                        .foregroundStyle(AppTheme.accent).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ConversationCallButtons: View {
    let canStart: Bool
    let onCall: (CallKind) -> Void

    var body: some View {
        callButton(.voice, title: "Voice call", symbol: "phone.fill")
        callButton(.video, title: "Video call", symbol: "video.fill")
    }

    private func callButton(_ kind: CallKind, title: String, symbol: String) -> some View {
        Button { onCall(kind) } label: {
            GameGlyph(symbol: symbol, size: 21)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(title)
        .disabled(!canStart)
    }
}

struct ConversationMessageBubble: View {
    let text: String
    let date: Date?
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 6) {
                Text(text).textSelection(.enabled).foregroundStyle(AppTheme.ink)
                if let date {
                    Text(date, style: .time).font(.caption2).foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .padding(14)
            .background(isMine ? AppTheme.accentSoft : AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isMine ? AppTheme.accent.opacity(0.3) : AppTheme.border, lineWidth: 1))
            if !isMine { Spacer(minLength: 36) }
        }
    }
}

struct ConversationComposer: View {
    @Binding var draft: String
    var isSending = false
    let errorMessage: String?
    let canEdit: Bool
    let canSend: Bool
    let isTooLong: Bool
    let sendLabel: String
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5).textFieldStyle(.plain).foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.border, lineWidth: 1))
                    .disabled(!canEdit)
                Button(action: onSend) {
                    Group {
                        if isSending { ProgressView().tint(AppTheme.onAccent) }
                        else { GameGlyph(symbol: "arrow.up", size: 24) }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(AppTheme.onAccent)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sendLabel)
                .disabled(!canSend)
                .opacity(canSend || isSending ? 1 : 0.5)
            }
            if isTooLong {
                Text("Messages can contain up to 2,000 characters.").font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(AppTheme.surface)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }
}
