import SwiftUI

@MainActor
struct GameCardEditorView: View {
    let cards: [PlayerGameCard]
    @Environment(\.socialRepository) private var repository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var gameID: String
    @State private var playerName: String
    @State private var daysPlayed: String
    @State private var progress: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(cards: [PlayerGameCard], initialGameID: String = GameCatalog.zenlessZoneZero.id) {
        self.cards = cards
        let initialID = initialGameID
        let card = cards.first { $0.gameID == initialID }
        _gameID = State(initialValue: initialID)
        _playerName = State(initialValue: card?.playerName ?? "")
        _daysPlayed = State(initialValue: card?.daysPlayed.map(String.init) ?? "")
        _progress = State(initialValue: card?.progress ?? "")
    }

    private var cleanName: String { playerName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanDays: String { daysPlayed.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasValidDays: Bool {
        cleanDays.isEmpty || (Int(cleanDays).map { $0 >= 0 && $0 <= Int(Int32.max) } ?? false)
    }
    private var isValid: Bool {
        !cleanName.isEmpty && cleanName.unicodeScalars.count <= 80 && hasValidDays && progress.unicodeScalars.count <= 1000
    }

    private var selectedGame: GameDescriptor {
        GameCatalog.games.first { $0.id == gameID } ?? GameCatalog.zenlessZoneZero
    }

    private var canSave: Bool { isValid && !isSaving && repository != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                editorField(title: "Game") { gamePicker }

                if gameID == GameCatalog.zenlessZoneZero.id {
                    editorField(title: "Game resources") {
                        NavigationLink {
                            GameReferenceView(game: GameCatalog.zenlessZoneZero)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            HStack(spacing: 12) {
                                ArcadeSticker(kind: .search, size: 34)
                                Text("Cover, characters & guides")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                GameGlyph(symbol: "chevron.right", size: 16)
                                    .foregroundStyle(SocialTheme.profile.tint)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gameCard.resources")
                    }
                }

                editorField(title: "Player name") {
                    TextField("Player name in this game", text: $playerName)
                        .font(.headline)
                        .accessibilityLabel("Player name in this game")
                        .accessibilityIdentifier("gameCard.playerName")
                    fieldFooter("1–80 characters", isInvalid: cleanName.unicodeScalars.count > 80)
                }

                editorField(title: "Days played") {
                    TextField("Days played (optional)", text: $daysPlayed)
                        .keyboardType(.numberPad).font(.headline)
                        .accessibilityLabel("Days played, optional")
                        .accessibilityIdentifier("gameCard.daysPlayed")
                    fieldFooter(hasValidDays ? "Optional" : "Enter a whole number of days, or leave this field empty.",
                                isInvalid: !hasValidDays)
                }

                editorField(title: "Progress") {
                    TextField("Progress, favorite characters or play style", text: $progress, axis: .vertical)
                        .lineLimit(3...8).font(.body)
                        .accessibilityLabel("Progress, favorite characters or play style")
                        .accessibilityIdentifier("gameCard.progress")
                    fieldFooter("\(progress.unicodeScalars.count)/1,000 characters",
                                isInvalid: progress.unicodeScalars.count > 1000)
                }

                Text("Shared on your profile. Details are entered by you and aren't connected to or verified by the game.")
                    .font(.footnote).lineSpacing(3).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Text(errorMessage).font(.subheadline)
                        .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.62))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gameCard.saveError")
                }
            }
            .padding(20).padding(.bottom, 28).disabled(isSaving)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { SocialThemeBackdrop(theme: .profile) }
        .safeAreaInset(edge: .top, spacing: 0) { editorToolbar }
        .toolbar(.hidden, for: .navigationBar)
        .interactiveDismissDisabled(isSaving)
        .onChange(of: gameID) { _, selectedID in
            let card = cards.first { $0.gameID == selectedID }
            playerName = card?.playerName ?? ""
            daysPlayed = card?.daysPlayed.map(String.init) ?? ""
            progress = card?.progress ?? ""
        }
    }

    private var editorToolbar: some View {
        VStack(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Game card").font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
            }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(SocialEditorButtonStyle(isPrimary: false))
                    .disabled(isSaving).accessibilityIdentifier("gameCard.cancel")
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Game card").font(.headline).foregroundStyle(AppTheme.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { Task { await save() } } label: {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().tint(AppTheme.onAccent) }
                        Text(isSaving ? "Saving" : "Save")
                    }
                }
                .buttonStyle(SocialEditorButtonStyle(isPrimary: true))
                .disabled(!canSave).accessibilityIdentifier("gameCard.save")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(AppTheme.background.opacity(0.96))
    }

    private var gamePicker: some View {
        Menu {
            Picker("Game", selection: $gameID) {
                ForEach(GameCatalog.games) { game in Text(game.name).tag(game.id) }
            }
        } label: {
            HStack(spacing: 14) {
                GameArtworkView(game: selectedGame, kind: .icon)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text(selectedGame.name).font(.headline).foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                GameGlyph(symbol: "chevron.down", size: 18).foregroundStyle(SocialTheme.profile.tint)
            }
            .frame(minHeight: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose game")
        .accessibilityValue(selectedGame.name)
        .accessibilityIdentifier("gameCard.chooseGame")
    }

    private func editorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.system(.caption, design: .monospaced, weight: .heavy))
                .tracking(1.5).foregroundStyle(SocialTheme.profile.tint)
            SocialThemePanel(theme: .profile) {
                VStack(alignment: .leading, spacing: 16, content: content)
                    .foregroundStyle(AppTheme.ink).tint(SocialTheme.profile.tint)
            }
        }
    }

    private func fieldFooter(_ text: String, isInvalid: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
            Text(text).font(.caption)
                .foregroundStyle(isInvalid ? Color.red : AppTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() async {
        guard let repository, isValid, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await repository.saveGameCard(gameID: gameID, playerName: cleanName,
                daysPlayed: cleanDays.isEmpty ? nil : Int(cleanDays), progress: progress)
            guard !Task.isCancelled else { return }
            dismiss()
        } catch {
            if !Task.isCancelled { errorMessage = "We couldn't save your game card. Please try again." }
        }
    }
}
