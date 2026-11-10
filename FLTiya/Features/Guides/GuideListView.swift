import SwiftUI

@MainActor
struct GuideListView: View {
    let model: GuideFeedModel
    let gameID: String
    let gameName: String
    let retry: () -> Void
    @Environment(\.socialRepository) private var repository

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if repository?.currentUserID == nil {
                AppCard {
                    EmptyStateView(symbol: "book.closed", title: "Game guides",
                                   message: "Sign in to read source-linked guides and game references.")
                        .frame(maxWidth: .infinity)
                }
            } else if model.loadedGameID == gameID, model.loadedUserID == repository?.currentUserID {
                SocialLoadFeedback(isLoading: model.isLoading, errorMessage: model.errorMessage, retry: retry)
                if model.guides.isEmpty, !model.isLoading, model.errorMessage == nil {
                    AppCard {
                        EmptyStateView(symbol: "book.closed", title: "No guides yet",
                                       message: "Reviewed guides for \(gameName) will appear here when available.")
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(model.guides) { guide in
                    if let url = guide.safeSourceURL {
                        GuideLinkCard(guide: guide, url: url)
                    }
                }
            } else {
                ProgressView("Loading guides…").frame(maxWidth: .infinity).padding()
            }
        }
    }
}

private struct GuideLinkCard: View {
    let guide: GameGuide
    let url: URL

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                if let game = GameCatalog.games.first(where: { $0.id == guide.gameID }) {
                    HStack(spacing: 10) {
                        GameArtworkView(game: game, kind: .icon)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                        Text(game.name).font(.caption.weight(.bold)).foregroundStyle(AppTheme.accent)
                        Spacer(minLength: 0)
                        GameGlyph(symbol: "book.closed", size: 24)
                            .foregroundStyle(AppTheme.violet).accessibilityHidden(true)
                    }
                }
                Text(verbatim: guide.title).font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
                if !guide.summary.isEmpty {
                    Text(verbatim: guide.summary).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                        .lineSpacing(4)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: guide.sourceName).font(.subheadline.weight(.semibold))
                    if let author = guide.sourceAuthor, !author.isEmpty {
                        Text(verbatim: "By \(author)").font(.caption)
                    }
                    if let date = guide.publicationDate {
                        Text("Added \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                    }
                }
                .foregroundStyle(AppTheme.secondaryInk)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(AppTheme.violet.opacity(0.6)).frame(width: 3)
                }
                Text(verbatim: guide.attribution)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .textSelection(.enabled)
                Link(destination: url) {
                    HStack {
                        Text("Read at source").font(.subheadline.weight(.bold))
                        Spacer()
                        GameGlyph(symbol: "arrow.up.right", size: 20)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel("Read \(guide.title) at \(guide.sourceName)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
struct GameGuidesView: View {
    let game: GameDescriptor
    @Environment(\.socialRepository) private var repository
    @State private var model = GuideFeedModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GameHeroCard(game: game)
                Text("Read guides and game references from their original sources. These are reading links, not verified details from your game account.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                GuideListView(model: model, gameID: game.id, gameName: game.name) {
                    Task { await reload() }
                }
            }
            .padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Guides & references")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(repository?.currentUserID?.uuidString ?? "signed-out")|\(game.id)") { await reload() }
        .refreshable { await reload() }
        .onDisappear { model.reset() }
    }

    private func reload() async {
        await model.load(gameID: game.id, repository: repository)
    }
}
