import SwiftUI

@MainActor
struct GamesView: View {
    @Environment(\.socialRepository) private var repository
    @Environment(\.socialVisibility) private var visibility
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedGameID = GameCatalog.zenlessZoneZero.id
    @State private var selectedSection: GameSection = .videos
    @State private var cards: [PlayerGameCard] = []
    @State private var isLoadingCards = false
    @State private var cardErrorMessage: String?
    @State private var cardLoadID = UUID()
    @State private var isShowingCardEditor = false
    @State private var guideModel = GuideFeedModel()
    @State private var videoModel = GameClipFeedModel()
    @State private var playingClip: GameClipPresentation?

    private var selectedGame: GameDescriptor {
        GameCatalog.games.first { $0.id == selectedGameID } ?? GameCatalog.zenlessZoneZero
    }

    private var hidesPlayingClip: Bool {
        playingClip.map { isClipHidden($0.clip) } == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GameHeroHeader(eyebrow: "Choose your world", title: "Game space",
                               subtitle: "Clips, guides and a player card for every game you love.",
                               symbol: "gamecontroller.fill")
                gamePicker
                sectionPicker
                gameBanner
                sectionContent
            }
            .padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: contentLoadIdentity) { await reloadVisibleSection() }
        .refreshable { await reloadVisibleSection() }
        .onChange(of: selectedGameID) { _, _ in
            playingClip = nil
        }
        .onChange(of: selectedSection) { _, _ in
            playingClip = nil
        }
        .onChange(of: hidesPlayingClip) { _, hidden in
            if hidden { playingClip = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reloadVisibleSection() } }
        }
        .onChange(of: repository?.currentUserID) { _, _ in
            playingClip = nil
            cards = []
            cardLoadID = UUID()
        }
        .sheet(isPresented: $isShowingCardEditor, onDismiss: { Task { await loadCards() } }) {
            NavigationStack {
                GameCardEditorView(cards: cards, initialGameID: selectedGameID)
            }
            .tint(AppTheme.accent)
        }
        .sheet(item: $playingClip) { presentation in
            ClipPlaybackView(clip: presentation.clip, repository: presentation.repository,
                             presentingUserID: presentation.userID)
        }
        .onDisappear {
            guideModel.reset()
            videoModel.reset()
        }
    }

    private var gamePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SELECT GAME")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(2)
                    .foregroundStyle(AppTheme.secondaryInk)
                Spacer()
                Menu {
                    Picker("Choose a game", selection: $selectedGameID) {
                        ForEach(GameCatalog.games) { game in
                            Text(game.name).tag(game.id)
                        }
                    }
                } label: {
                    Label("All games", systemImage: "chevron.down")
                        .font(.caption.weight(.bold)).frame(minHeight: 44)
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityLabel("Choose game. Current game: \(selectedGame.name)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(GameCatalog.games) { game in
                        Button { selectedGameID = game.id } label: {
                            VStack(spacing: 9) {
                                GameArtworkView(game: game, kind: .icon)
                                    .frame(width: 62, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 17))
                                    .padding(5)
                                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                                    .overlay(RoundedRectangle(cornerRadius: 21)
                                        .strokeBorder(game.id == selectedGameID ? AppTheme.accent : AppTheme.border, lineWidth: 1.5))
                                Text(game.monogram).font(.caption.weight(.bold))
                                    .foregroundStyle(game.id == selectedGameID ? AppTheme.accent : AppTheme.secondaryInk)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(game.name)
                        .accessibilityAddTraits(game.id == selectedGameID ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 6) {
            ForEach(GameSection.allCases) { section in
                Button { selectedSection = section } label: {
                    Text(section.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selectedSection == section ? AppTheme.onAccent : AppTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(selectedSection == section ? AppTheme.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(5)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(AppTheme.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game section")
    }

    private var gameBanner: some View {
        NavigationLink {
            GameDetailsView(game: selectedGame)
        } label: {
            GameHeroCard(game: selectedGame)
                .overlay(alignment: .topTrailing) {
                    // The whole cover is a navigation target.
                    GameGlyph(symbol: "arrow.up.right", size: 19)
                        .foregroundStyle(.white)
                        .padding(10).background(.black.opacity(0.55), in: Circle())
                        .padding(18).offset(y: 66)
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Explore game resources and your game profile")
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .videos:
            videosSection
        case .guides:
            GuideListView(model: guideModel, gameID: selectedGameID, gameName: selectedGame.name) {
                Task { await reloadVisibleSection() }
            }
        case .myCard:
            myCardSection
        }
    }

    @ViewBuilder
    private var myCardSection: some View {
        if repository == nil {
            AppCard {
                EmptyStateView(
                    symbol: "person.crop.rectangle",
                    title: "Your game card",
                    message: "Sign in to share your player name, days played and progress. Cards use details you enter yourself."
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                SocialLoadFeedback(isLoading: isLoadingCards, errorMessage: cardErrorMessage) {
                    Task { await loadCards() }
                }
                if !isLoadingCards, cardErrorMessage == nil {
                    let selectedCards = cards.filter { $0.gameID == selectedGameID }
                    if selectedCards.isEmpty {
                        AppCard {
                            EmptyStateView(
                                symbol: "person.crop.rectangle", title: "Your \(selectedGame.name) card",
                                message: "Share the player name, days played and progress you choose to add."
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        PlayerGameCardsSection(cards: selectedCards)
                    }
                }
                Button {
                    isShowingCardEditor = true
                } label: {
                    Label("Edit game card", systemImage: "pencil")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
                .disabled(isLoadingCards || cardErrorMessage != nil)
                if selectedGameID == GameCatalog.zenlessZoneZero.id {
                    NavigationLink { GameReferenceView(game: selectedGame) } label: {
                        Label("Game reference", systemImage: "book.closed")
                            .frame(minHeight: 44)
                    }
                    Text("Read source-linked guides and character references. Your card stays based on details you enter.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
    }

    @ViewBuilder
    private var videosSection: some View {
        if repository?.currentUserID == nil {
            AppCard {
                EmptyStateView(symbol: "play.rectangle", title: "Game clips",
                               message: "Sign in to watch the live game video catalog.")
                    .frame(maxWidth: .infinity)
            }
        } else if videoModel.loadedGameID == selectedGameID, videoModel.loadedUserID == repository?.currentUserID {
            let visibleClips = videoModel.clips.filter { !isClipHidden($0) }
            VStack(alignment: .leading, spacing: 16) {
                if selectedGameID == GameCatalog.zenlessZoneZero.id {
                    OfficialGameVideoCard()
                }
                SocialLoadFeedback(isLoading: videoModel.isLoading, errorMessage: videoModel.errorMessage) {
                    Task { await reloadVisibleSection() }
                }
                if visibleClips.isEmpty, !videoModel.isLoading, videoModel.errorMessage == nil,
                   selectedGameID != GameCatalog.zenlessZoneZero.id {
                    AppCard {
                        EmptyStateView(symbol: "play.rectangle", title: "No clips yet",
                                       message: "Approved videos for \(selectedGame.name) will appear here when available.")
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(visibleClips) { clip in
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            ClipThumbnailView(clip: clip, repository: repository) { openClip(clip) }
                            Text(verbatim: clip.caption.split(whereSeparator: \.isNewline).first.map(String.init) ?? clip.gameTitle)
                                .font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(AppTheme.ink)
                            Button { openClip(clip) } label: {
                                Label("Watch clip & credits", systemImage: "play.circle")
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
        } else {
            ProgressView("Loading clips…").frame(maxWidth: .infinity).padding()
        }
    }

    private var contentLoadIdentity: String {
        let actor = repository?.currentUserID?.uuidString ?? "signed-out"
        let revision = selectedSection == .videos ? (visibility?.unblockRevision ?? 0) : 0
        return "\(actor)|\(selectedGameID)|\(selectedSection.rawValue)|\(revision)"
    }

    private func reloadVisibleSection() async {
        guard !Task.isCancelled else { return }
        switch selectedSection {
        case .videos: await videoModel.load(gameID: selectedGameID, repository: repository)
        case .guides: await guideModel.load(gameID: selectedGameID, repository: repository)
        case .myCard: await loadCards()
        }
    }

    private func openClip(_ clip: ApprovedClip) {
        guard let repository, let userID = repository.currentUserID,
              clip.gameID == selectedGameID, clip.canPlay, !isClipHidden(clip) else { return }
        playingClip = GameClipPresentation(clip: clip, repository: repository, userID: userID)
    }

    private func isClipHidden(_ clip: ApprovedClip) -> Bool {
        visibility?.isVideoHidden(clip.id, authorID: clip.ownerID) == true
    }

    private func loadCards() async {
        guard !Task.isCancelled else { return }
        guard let repository, let userID = repository.currentUserID else { return }
        let id = UUID()
        cardLoadID = id
        isLoadingCards = true
        cardErrorMessage = nil
        defer { if cardLoadID == id { isLoadingCards = false } }
        do {
            let loadedCards = try await repository.gameCards(userID: userID)
            guard cardLoadID == id, !Task.isCancelled, repository.currentUserID == userID else { return }
            cards = loadedCards
        } catch {
            guard cardLoadID == id, !Task.isCancelled, repository.currentUserID == userID else { return }
            cards = []
            cardErrorMessage = "We couldn't load your game cards. Please try again."
        }
    }
}

private struct GameClipPresentation: Identifiable {
    let clip: ApprovedClip
    let repository: any SocialRepository
    let userID: UUID
    var id: UUID { clip.id }
}

private enum GameSection: String, CaseIterable, Identifiable {
    case videos = "Videos"
    case guides = "Guides"
    case myCard = "My Card"

    var id: Self { self }
}

private struct GameDetailsView: View {
    let game: GameDescriptor
    @Environment(\.socialRepository) private var repository
    private var theme: GameAppearance { GameAppearance(game: game) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GameHeroCard(game: game)
                Text("MAKE THIS GAME YOURS")
                    .font(.caption.weight(.black)).tracking(1.8)
                    .foregroundStyle(theme.secondaryInk)
                if let userID = repository?.currentUserID {
                    NavigationLink {
                        PersonalGameDetailView(game: game, userID: userID, cards: [])
                    } label: {
                        destinationCard(title: "Your game profile", subtitle: "Player name, days played and your story", symbol: "person.crop.rectangle")
                    }
                }
                NavigationLink { GameReferenceView(game: game) } label: {
                    destinationCard(title: "Game resources", subtitle: "Artwork and source-linked game references", symbol: "photo.on.rectangle")
                }
                NavigationLink { GameGuidesView(game: game) } label: {
                    destinationCard(title: "Guides & reading", subtitle: "Reviewed summaries with original sources", symbol: "book.closed")
                }
                Text("Watch this game's clips in the Videos section of Games. Personal profiles use the details each player chooses to share.")
                    .font(.footnote).foregroundStyle(theme.secondaryInk)
            }
            .padding(20)
        }
        .buttonStyle(.plain)
        .background(theme.background.ignoresSafeArea())
        .tint(theme.isDark ? theme.accent : theme.ink)
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
    }

    private func destinationCard(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            GameGlyph(symbol: symbol, size: 28)
                .foregroundStyle(theme.isDark ? theme.accent : theme.ink)
                .frame(width: 50, height: 54)
                .background(theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline).foregroundStyle(theme.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(theme.secondaryInk)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.accent.opacity(0.2)))
    }
}

#Preview {
    NavigationStack {
        GamesView()
    }
    .tint(AppTheme.accent)
}
