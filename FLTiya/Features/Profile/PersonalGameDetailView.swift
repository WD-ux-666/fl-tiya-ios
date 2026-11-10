import SwiftUI

/// Personal, player-entered details for one game. Artwork is decorative; the
/// only game information shown here is the card stored by its actual owner.
@MainActor
struct PersonalGameDetailView: View {
    let game: GameDescriptor
    let userID: UUID
    var onCardsChanged: (() async -> Void)?
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.scenePhase) private var scenePhase
    @State private var cards: [PlayerGameCard]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadID = UUID()
    @State private var editor: EditorRoute?
    @ScaledMetric(relativeTo: .largeTitle) private var daysNumberSize: CGFloat = 42

    init(game: GameDescriptor, userID: UUID, cards: [PlayerGameCard],
         onCardsChanged: (() async -> Void)? = nil) {
        self.game = game
        self.userID = userID
        self.onCardsChanged = onCardsChanged
        _cards = State(initialValue: cards.filter { $0.userID == userID })
    }

    private var appearance: GameAppearance { GameAppearance(game: game) }
    private var card: PlayerGameCard? { cards.first { $0.gameID == game.id && $0.userID == userID } }
    private var isOwner: Bool { repository?.currentUserID == userID }
    private var isPlayerHidden: Bool { !isOwner && visibility?.isPlayerHidden(userID) == true }
    private var canEdit: Bool { isOwner && GameCatalog.games.contains { $0.id == game.id } }
    private var actionInk: Color { appearance.isDark ? appearance.accent : appearance.ink }
    private var loadIdentity: String {
        "\(userID)|\(repository?.currentUserID?.uuidString ?? "signed-out")|\(isPlayerHidden)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isPlayerHidden {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Game profile unavailable").font(.title3.weight(.bold)).foregroundStyle(appearance.ink)
                        Text("This player's game profile is no longer available.")
                            .foregroundStyle(appearance.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                    .background(appearance.surface, in: RoundedRectangle(cornerRadius: 24))
                    .padding(20)
                } else {
                    hero
                    VStack(alignment: .leading, spacing: 24) {
                        if isLoading { ProgressView().tint(appearance.accent).frame(maxWidth: .infinity) }
                        if let errorMessage { errorNotice(errorMessage) }
                        if let card {
                            playerIdentity(card)
                            progressSection(card)
                            sourceNote
                        } else if !isLoading, errorMessage == nil {
                            emptyState
                        }
                        gameLibrary
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(appearance.background.ignoresSafeArea())
        .tint(actionInk)
        .navigationTitle(game.monogram)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(appearance.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(appearance.isDark ? .dark : .light, for: .navigationBar)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = EditorRoute(id: game.id) } label: {
                        Image(systemName: "square.and.pencil").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Edit your \(game.name) game card")
                    .disabled(isLoading || errorMessage != nil)
                }
            }
        }
        .task(id: loadIdentity) { await load() }
        .refreshable { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .sheet(item: $editor, onDismiss: {
            Task {
                await load()
                await onCardsChanged?()
            }
        }) { route in
            NavigationStack {
                GameCardEditorView(cards: cards, initialGameID: route.id)
            }
            .tint(AppTheme.accent)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameThemeBackdrop(game: game)
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.86)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 18) {
                Text("PERSONAL GAME PROFILE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(2.2)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: Capsule())
                HStack(alignment: .bottom, spacing: 16) {
                    GameArtworkView(game: game, kind: .icon)
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(game.name).font(.system(.largeTitle, design: .rounded, weight: .black))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(isOwner ? "Your story in this game" : "A player's story in this game")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(minHeight: 300)
        .clipped()
        .overlay(alignment: .bottom) { Rectangle().fill(appearance.accent).frame(height: 5) }
    }

    private func playerIdentity(_ card: PlayerGameCard) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionEyebrow("PLAYER NAME")
                    Text(card.playerName)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(appearance.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                GameGlyph(symbol: "gamecontroller.fill", size: 29)
                    .foregroundStyle(actionInk)
                    .frame(width: 50, height: 50)
                    .background(appearance.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
            Rectangle().fill(appearance.ink.opacity(0.1)).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    daysNumber(card).fixedSize()
                    daysLabel(card)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    daysNumber(card).lineLimit(1).minimumScaleFactor(0.25)
                    daysLabel(card)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(appearance.accent.opacity(0.2), lineWidth: 1))
    }

    private func progressSection(_ card: PlayerGameCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Progress & play style").font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(appearance.ink)
                Spacer()
                GameGlyph(symbol: "text.alignleft", size: 24).foregroundStyle(actionInk).accessibilityHidden(true)
            }
            if card.progress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A story still being written").font(.headline).foregroundStyle(appearance.ink)
                    Text(canEdit ? "Share your progress, favorite characters or the way you like to play."
                         : "No progress or play style has been shared yet.")
                        .font(.subheadline).foregroundStyle(appearance.secondaryInk)
                }
            } else {
                Text(card.progress).font(.body).lineSpacing(6).foregroundStyle(appearance.ink)
                    .textSelection(.enabled)
            }
            if canEdit {
                Button { editor = EditorRoute(id: game.id) } label: {
                    Label("Edit game profile", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.bold)).frame(minHeight: 44)
                }
                .disabled(isLoading || errorMessage != nil)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(appearance.accent.opacity(0.16)))
    }

    private var sourceNote: some View {
        Label("Shared by the player. Details aren't linked to or verified by the game.", systemImage: "info.circle")
            .font(.caption).foregroundStyle(appearance.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var gameLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Game library").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(appearance.ink)
            if game.id == GameCatalog.zenlessZoneZero.id {
                Text("Character references").font(.subheadline).foregroundStyle(appearance.secondaryInk)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(["Anby Demara", "Nicole Demara", "Billy Kid"], id: \.self) { name in
                            NavigationLink { GameReferenceView(game: game) } label: {
                                VStack(spacing: 8) {
                                    if let portrait = GameArtworkCatalog.characterPortraitName(for: name) {
                                        Image(portrait).resizable().scaledToFit()
                                            .frame(width: 80, height: 80)
                                            .background(appearance.surface, in: RoundedRectangle(cornerRadius: 18))
                                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(appearance.accent.opacity(0.22)))
                                    }
                                    Text(name).font(.caption.weight(.semibold))
                                        .foregroundStyle(appearance.ink)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            NavigationLink { GameReferenceView(game: game) } label: {
                libraryLink("Artwork & game references", symbol: "photo.on.rectangle")
            }
            NavigationLink { GameGuidesView(game: game) } label: {
                libraryLink("Guides & reading", symbol: "book.closed")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(appearance.accent.opacity(0.16)))
    }

    private func libraryLink(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            GameGlyph(symbol: symbol, size: 23)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).accessibilityHidden(true)
        }
        .foregroundStyle(actionInk).frame(minHeight: 44)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No game card shared").font(.title3.weight(.bold)).foregroundStyle(appearance.ink)
            Text(canEdit ? "Add your player name and the details you'd like to share."
                 : "No details are currently shared for this game.")
                .foregroundStyle(appearance.secondaryInk)
            if canEdit {
                Button("Add game card") { editor = EditorRoute(id: game.id) }
                    .frame(minHeight: 44)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func errorNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.subheadline).foregroundStyle(appearance.ink)
            Button("Try again") { Task { await load() } }.frame(minHeight: 44)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(1.8).foregroundStyle(appearance.secondaryInk)
    }

    private func daysNumber(_ card: PlayerGameCard) -> some View {
        Text(card.daysPlayed.map { $0.formatted() } ?? "—")
            .font(.system(size: daysNumberSize, weight: .black, design: .rounded))
            .foregroundStyle(actionInk)
    }

    private func daysLabel(_ card: PlayerGameCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DAYS PLAYED").font(.caption.weight(.heavy)).tracking(1)
                .foregroundStyle(appearance.ink)
            if card.daysPlayed == nil {
                Text(canEdit ? "Add this when you're ready" : "Not shared")
                    .font(.caption).foregroundStyle(appearance.secondaryInk)
            }
        }
    }

    private func load() async {
        if isPlayerHidden {
            loadID = UUID()
            isLoading = false
            cards = []
            errorMessage = nil
            return
        }
        guard let repository, let actor = repository.currentUserID else {
            loadID = UUID()
            isLoading = false
            cards = []
            errorMessage = "Sign in to view this game profile."
            return
        }
        let revision = UUID()
        loadID = revision
        isLoading = true
        errorMessage = nil
        defer { if loadID == revision { isLoading = false } }
        do {
            let loaded = try await repository.gameCards(userID: userID)
            guard loadID == revision, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            cards = loaded.filter { $0.userID == userID }
        } catch {
            guard loadID == revision, !Task.isCancelled, !isPlayerHidden, repository.currentUserID == actor else { return }
            cards = []
            errorMessage = "We couldn't load this game profile. Please try again."
        }
    }

    private struct EditorRoute: Identifiable { let id: String }
}
