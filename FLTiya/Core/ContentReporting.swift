import SwiftUI

enum ReportTarget: Identifiable, Equatable {
    case video(UUID)
    case comment(UUID)
    case conversation(UUID)
    case samplePlayer(UUID)

    var id: String { "\(kind):\(targetID)" }

    var targetID: UUID {
        switch self {
        case .video(let id), .comment(let id), .conversation(let id), .samplePlayer(let id): id
        }
    }

    var kind: String {
        switch self {
        case .video: "video"
        case .comment: "comment"
        case .conversation: "conversation"
        case .samplePlayer: "sample_player"
        }
    }

    var title: String {
        switch self {
        case .video: "Report video"
        case .comment: "Report comment"
        case .conversation: "Report player"
        case .samplePlayer: "Report sample player"
        }
    }

    var privacyNote: String {
        switch self {
        case .video, .comment: "The moderation team can see your account, the reported item, and what you submit here."
        case .conversation: "The moderation team can see your account, the reported player, and what you submit here. Your chat history isn’t attached."
        case .samplePlayer: "This sample player and their content will be hidden for your account. Sample reports aren’t sent to moderation."
        }
    }

    var hiddenConfirmation: String {
        switch self {
        case .video: "This video is now hidden for you."
        case .comment: "This comment is now hidden for you."
        case .conversation, .samplePlayer: "This player and their content are now hidden for you."
        }
    }

    var isSamplePlayer: Bool {
        if case .samplePlayer = self { return true }
        return false
    }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case inappropriate
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .spam: "Spam or scams"
        case .harassment: "Harassment or threats"
        case .inappropriate: "Inappropriate content"
        case .other: "Something else"
        }
    }
}

enum ReportFailure: Error {
    case unavailable
}

struct ReportPresentation: Identifiable {
    let target: ReportTarget
    let reporterID: UUID
    var id: String { target.id }
}

/// Remembers successful safety actions so visible screens can update without
/// waiting for another fetch. The server also enforces these rules on new reads.
@MainActor
@Observable
final class SocialVisibility {
    private var accountID: UUID?
    private var reportedVideos: Set<UUID> = []
    private var reportedComments: Set<UUID> = []
    private var reportedPlayers: Set<UUID> = []
    private var blockedPlayers: Set<UUID> = []
    private(set) var playerRevision = 0
    private(set) var unblockRevision = 0

    func useAccount(_ id: UUID?) {
        guard accountID != id else { return }
        accountID = id
        reportedVideos.removeAll()
        reportedComments.removeAll()
        reportedPlayers.removeAll()
        blockedPlayers.removeAll()
        playerRevision &+= 1
    }

    func recordReport(_ target: ReportTarget, by account: UUID) {
        useAccount(account)
        switch target {
        case .video(let id):
            reportedVideos.insert(id)
        case .comment(let id):
            reportedComments.insert(id)
        case .conversation(let id), .samplePlayer(let id):
            if reportedPlayers.insert(id).inserted { playerRevision &+= 1 }
        }
    }

    func recordBlock(_ id: UUID, by account: UUID) {
        useAccount(account)
        if blockedPlayers.insert(id).inserted { playerRevision &+= 1 }
    }

    func recordUnblock(_ id: UUID, by account: UUID) {
        useAccount(account)
        blockedPlayers.remove(id)
        playerRevision &+= 1
        unblockRevision &+= 1
    }

    func isPlayerHidden(_ id: UUID) -> Bool {
        reportedPlayers.contains(id) || blockedPlayers.contains(id)
    }

    func isVideoHidden(_ id: UUID, authorID: UUID?) -> Bool {
        reportedVideos.contains(id) || (authorID.map { isPlayerHidden($0) } ?? false)
    }

    func isCommentHidden(_ id: UUID, authorID: UUID) -> Bool {
        reportedComments.contains(id) || isPlayerHidden(authorID)
    }
}

private struct SocialVisibilityKey: EnvironmentKey {
    static let defaultValue: SocialVisibility? = nil
}

extension EnvironmentValues {
    var socialVisibility: SocialVisibility? {
        get { self[SocialVisibilityKey.self] }
        set { self[SocialVisibilityKey.self] = newValue }
    }
}

struct ContentReportButton: View {
    let target: ReportTarget
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ReportBadge(compact: compact)
                .frame(width: compact ? 44 : 48, height: compact ? 44 : 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.title)
    }
}

extension View {
    func contentReportSheet(item: Binding<ReportPresentation?>, repository: (any SocialRepository)?) -> some View {
        sheet(item: item) { presentation in
            if let repository {
                ContentReportForm(target: presentation.target, reporterID: presentation.reporterID,
                                  repository: repository)
            }
        }
    }
}

private struct ContentReportForm: View {
    let target: ReportTarget
    let reporterID: UUID
    let repository: any SocialRepository

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var submission: Task<Void, Never>?
    @State private var inserted: Bool?
    @State private var errorMessage: String?

    private let detailsLimit = 500
    private var detailsCount: Int { details.unicodeScalars.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let inserted {
                        result(inserted: inserted)
                    } else {
                        form
                    }
                }
                .frame(maxWidth: 550)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background { AppBackdrop() }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if inserted == nil {
                        Button("Cancel") { dismiss() }
                            .disabled(submission != nil)
                    }
                }
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(submission != nil)
        .onDisappear { submission?.cancel() }
    }

    private var form: some View {
        Group {
            Text(target.privacyNote)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
            if !target.isSamplePlayer { reportInputs }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }
            Button(action: submit) {
                HStack(spacing: 8) {
                    if submission != nil { ProgressView().tint(AppTheme.onAccent) }
                    if submission != nil {
                        Text("Submitting…")
                    } else if target.isSamplePlayer {
                        Text("Report and hide")
                    } else {
                        Text("Submit report")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SocialEditorButtonStyle(isPrimary: true))
            .disabled((!target.isSamplePlayer && reason == nil) || detailsCount > detailsLimit || submission != nil)
        }
    }

    private var reportInputs: some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Why are you reporting this?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(ReportReason.allCases) { option in
                    Button {
                        reason = option
                        errorMessage = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: reason == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(reason == option ? AppTheme.accent : AppTheme.secondaryInk)
                                .accessibilityHidden(true)
                            Text(option.title).foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(AppTheme.surfaceRaised, in: SocialEditorButtonOutline())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(reason == option ? .isSelected : [])
                }
            }
            .disabled(submission != nil)

            VStack(alignment: .leading, spacing: 8) {
                Text("Details (optional)").font(.headline)
                TextField("Add context for the moderation team", text: $details, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(14)
                    .background(AppTheme.surfaceRaised, in: SocialEditorButtonOutline())
                    .accessibilityLabel("Details (optional)")
                    .disabled(submission != nil)
                Text("\(detailsCount) / \(detailsLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(detailsCount > detailsLimit ? Color.orange : AppTheme.secondaryInk)
                    .accessibilityLabel("\(detailsCount) of \(detailsLimit) characters")
            }
        }
    }

    private func result(inserted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportBadge(compact: false)
            Text(target.isSamplePlayer ? "Sample player hidden" : (inserted ? "Report submitted" : "Already reported"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if !target.isSamplePlayer {
                Text(inserted ? "Thanks. We’ve received your report." : "Your previous report is already on file.")
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Text(target.hiddenConfirmation)
                .foregroundStyle(AppTheme.secondaryInk)
            Button("Done") { dismiss() }
                .buttonStyle(SocialEditorButtonStyle(isPrimary: true))
        }
    }

    private func submit() {
        guard let reason = target.isSamplePlayer ? ReportReason.other : reason,
              submission == nil, detailsCount <= detailsLimit else { return }
        guard repository.currentUserID == reporterID else {
            errorMessage = "Your session has changed. Open this report again to continue."
            return
        }
        let note = details.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        submission = Task { @MainActor in
            defer { submission = nil }
            do {
                try Task.checkCancellation()
                guard repository.currentUserID == reporterID else { throw SocialDataFailure.accountChanged }
                inserted = try await repository.submitReport(target: target, reason: reason,
                                                             details: note.isEmpty ? nil : note)
            } catch is CancellationError {
                return
            } catch ReportFailure.unavailable {
                errorMessage = "This item can’t be reported right now. Reopen it and try again."
            } catch SocialDataFailure.accountChanged {
                errorMessage = "Your session has changed. Open this report again to continue."
            } catch {
                errorMessage = "Couldn’t send the report. Please try again."
            }
        }
    }
}

/// A hand drawn flag mark uses the dock artwork’s warm outline and violet shadow.
private struct ReportBadge: View {
    let compact: Bool

    var body: some View {
        let outline = SocialEditorButtonOutline()
        ZStack {
            outline.fill(AppTheme.violet.opacity(0.78)).offset(x: 2, y: 2)
            outline.fill(AppTheme.background)
            outline.stroke(AppTheme.accent.opacity(0.60), lineWidth: 1)
            Canvas { context, size in
                let scale = size.width / 24
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
                var flag = Path()
                flag.move(to: point(5, 4))
                flag.addLine(to: point(12, 2))
                flag.addLine(to: point(20, 6))
                flag.addLine(to: point(16, 10))
                flag.addLine(to: point(20, 14))
                flag.addLine(to: point(12, 12))
                flag.addLine(to: point(5, 14))
                flag.closeSubpath()
                var pole = Path()
                pole.move(to: point(5, 4))
                pole.addLine(to: point(5, 21))
                pole.move(to: point(2, 21))
                pole.addLine(to: point(9, 21))
                var stripe = Path()
                stripe.move(to: point(9, 7))
                stripe.addLine(to: point(14, 6))
                stripe.move(to: point(9, 10))
                stripe.addLine(to: point(12, 9))

                context.fill(flag, with: .color(SocialTheme.profile.tint))
                let edge = StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round)
                context.stroke(flag, with: .color(AppTheme.ink), style: edge)
                context.stroke(pole, with: .color(AppTheme.ink), style: edge)
                context.stroke(stripe, with: .color(AppTheme.violet), style: edge)
            }
            .frame(width: compact ? 23 : 26, height: compact ? 23 : 26)
        }
        .frame(width: compact ? 33 : 42, height: compact ? 33 : 42)
        .accessibilityHidden(true)
    }
}
