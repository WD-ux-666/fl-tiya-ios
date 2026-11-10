import SwiftUI

@MainActor
struct ClipCommentsView: View {
    let clip: ApprovedClip
    let repository: any SocialRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.socialVisibility) private var visibility
    @State private var comments: [ClipComment] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var deletingID: UUID?
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var retrySubmission: Submission?
    @State private var reportPresentation: ReportPresentation?
    @State private var sampleAuthorRefreshID = UUID()
    @State private var resolvedSampleAuthors: ResolvedSampleAuthors?

    private struct Submission {
        let id: UUID
        let body: String
    }

    private struct SampleAuthorLookup: Equatable {
        let viewerID: UUID?
        let refreshID: UUID
        let credits: Set<ClipComment.SampleAuthorCredit>
    }

    private struct ResolvedSampleAuthors {
        let viewerID: UUID
        var players: [ClipComment.SampleAuthorCredit: CommunityPlayer] = [:]
    }

    private var cleanDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool {
        !cleanDraft.isEmpty && cleanDraft.unicodeScalars.count <= 1000 && !isSending
            && deletingID == nil && repository.currentUserID != nil
    }

    var body: some View {
        let visibleComments = comments.filter { comment in
            let authorID = sampleAuthor(for: comment)?.id ?? comment.author.id
            return visibility?.isCommentHidden(comment.id, authorID: authorID) != true
        }
        let sampleLookup = SampleAuthorLookup(
            viewerID: repository.currentUserID, refreshID: sampleAuthorRefreshID,
            credits: Set(comments.compactMap(\.sampleAuthorCredit))
        )
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text("Comments are reviewed before they appear to other players.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                    if isLoading && visibleComments.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage).font(.subheadline)
                            Button("Reload comments") { Task { await load() } }
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                    if visibleComments.isEmpty && !isLoading && errorMessage == nil {
                        VStack(spacing: 14) {
                            Image("DockMessages").resizable().scaledToFit().frame(width: 76, height: 76)
                                .accessibilityHidden(true)
                            Text("Start the conversation").font(.headline)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    ForEach(visibleComments) { comment in commentRow(comment) }
                    if comments.count == 100 && !visibleComments.isEmpty {
                        Text("Showing \(visibleComments.count) recent comments.")
                            .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minHeight: 44)
                }
            }
            .navigationDestination(for: UUID.self) { id in PlayerProfileView(userID: id) }
            .navigationDestination(for: CommunityPlayer.self) { SamplePlayerDetailView(sample: $0) }
            .task(id: repository.currentUserID) {
                comments = []
                retrySubmission = nil
                draft = ""
                await load()
            }
            .task(id: sampleLookup) { await resolveSampleAuthors(for: sampleLookup) }
            .refreshable { await load() }
            .onChange(of: repository.currentUserID) { _, _ in
                loadID = UUID()
                comments = []
                resolvedSampleAuthors = nil
                draft = ""
                dismiss()
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .contentReportSheet(item: $reportPresentation, repository: repository)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func commentRow(_ comment: ClipComment) -> some View {
        let sample = sampleAuthor(for: comment)
        return HStack(alignment: .top, spacing: 12) {
            if let sample {
                NavigationLink(value: sample) {
                    PlayerAvatarView(profile: sample.profile, size: 40)
                }
                .accessibilityLabel("View \(sample.displayName)'s sample profile")
            } else if comment.hasAuthorProfile {
                NavigationLink(value: comment.author.id) {
                    PlayerAvatarView(profile: comment.author, size: 40)
                }
                .accessibilityLabel("View \(comment.author.displayName)'s profile")
            } else {
                AvatarPlaceholder(size: 40).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let sample {
                        NavigationLink(value: sample) {
                            Text(verbatim: comment.author.displayName).font(.subheadline.weight(.semibold))
                        }
                    } else if comment.hasAuthorProfile {
                        NavigationLink(value: comment.author.id) {
                            Text(verbatim: comment.author.displayName).font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Text(verbatim: comment.author.displayName).font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(AppTheme.ink)
                Text(verbatim: comment.body)
                    .font(.subheadline).foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if comment.isPending {
                        Text("Pending review").foregroundStyle(SocialTheme.profile.tint)
                    }
                    if comment.author.id == repository.currentUserID {
                        Button("Delete", role: .destructive) { Task { await delete(comment) } }
                            .disabled(deletingID != nil || isSending)
                            .frame(minHeight: 44)
                    }
                    if deletingID == comment.id { ProgressView() }
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let viewerID = repository.currentUserID, comment.author.id != viewerID,
               comment.status == "approved" {
                ContentReportButton(target: .comment(comment.id), compact: true) {
                    reportPresentation = ReportPresentation(target: .comment(comment.id), reporterID: viewerID)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func sampleAuthor(for comment: ClipComment) -> CommunityPlayer? {
        guard let credit = comment.sampleAuthorCredit, let resolvedSampleAuthors,
              resolvedSampleAuthors.viewerID == repository.currentUserID else { return nil }
        return resolvedSampleAuthors.players[credit]
    }

    private func resolveSampleAuthors(for lookup: SampleAuthorLookup) async {
        guard let viewerID = lookup.viewerID, repository.currentUserID == viewerID,
              !Task.isCancelled else { return }
        if resolvedSampleAuthors?.viewerID != viewerID {
            resolvedSampleAuthors = ResolvedSampleAuthors(viewerID: viewerID)
        }
        for credit in lookup.credits {
            guard !Task.isCancelled, repository.currentUserID == viewerID,
                  sampleAuthorRefreshID == lookup.refreshID else { return }
            // The comment RPC supplies only a reviewed lookup hint. The
            // community RPC independently decides whether this identity is visible.
            guard let players = try? await repository.communityPlayers(gameID: credit.gameID, query: credit.handle),
                  !Task.isCancelled, repository.currentUserID == viewerID,
                  sampleAuthorRefreshID == lookup.refreshID else { continue }
            let exact = players.filter {
                $0.isSample == true && $0.sampleGameID == credit.gameID
                    && $0.handle.caseInsensitiveCompare(credit.handle) == .orderedSame
            }
            resolvedSampleAuthors?.players[credit] = exact.count == 1 ? exact.first : nil
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(AppTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Comment")
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending { ProgressView().tint(AppTheme.background) }
                        else { Image(systemName: "arrow.up").font(.headline.weight(.bold)) }
                    }
                    .frame(width: 46, height: 46)
                    .foregroundStyle(AppTheme.background)
                    .background(canSend ? AppTheme.accent : AppTheme.secondaryInk, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Submit comment for review")
            }
            if draft.unicodeScalars.count > 900 {
                Text("\(draft.unicodeScalars.count)/1000")
                    .font(.caption).foregroundStyle(draft.unicodeScalars.count > 1000 ? .red : AppTheme.secondaryInk)
            }
        }
        .padding(16)
        .background(AppTheme.surface)
    }

    private func load() async {
        guard !Task.isCancelled, !isSending, deletingID == nil,
              let actor = repository.currentUserID else { return }
        let request = UUID()
        loadID = request
        isLoading = true
        errorMessage = nil
        defer { if loadID == request { isLoading = false } }
        do {
            let result = try await repository.clipComments(clipID: clip.id)
            guard loadID == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            comments = result
            sampleAuthorRefreshID = UUID()
        } catch {
            guard loadID == request, !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "Couldn't load comments. Please try again."
        }
    }

    private func send() async {
        guard canSend, let actor = repository.currentUserID else { return }
        let text = cleanDraft
        let submission = retrySubmission?.body == text ? retrySubmission! : Submission(id: UUID(), body: text)
        retrySubmission = submission
        isSending = true
        errorMessage = nil
        // A late read must not erase this newly confirmed pending comment.
        loadID = UUID()
        isLoading = false
        defer { isSending = false }
        do {
            let comment = try await repository.addClipComment(clipID: clip.id, commentID: submission.id, body: submission.body)
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            comments.removeAll { $0.id == comment.id }
            comments.insert(comment, at: 0)
            if cleanDraft == text { draft = "" }
            retrySubmission = nil
        } catch {
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "Couldn't submit your comment. Your text is saved here; tap send to retry."
        }
    }

    private func delete(_ comment: ClipComment) async {
        guard deletingID == nil, !isSending, let actor = repository.currentUserID,
              comment.author.id == actor else { return }
        deletingID = comment.id
        errorMessage = nil
        loadID = UUID()
        isLoading = false
        defer { deletingID = nil }
        do {
            try await repository.deleteClipComment(id: comment.id)
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            comments.removeAll { $0.id == comment.id }
        } catch {
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            errorMessage = "Couldn't delete this comment. Please try again."
        }
    }
}
