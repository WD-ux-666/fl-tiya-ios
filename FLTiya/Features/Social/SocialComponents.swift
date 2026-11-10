import SwiftUI

struct PlayerSummaryRow: View {
    let profile: PlayerProfile

    var body: some View {
        HStack(spacing: 14) {
            PlayerAvatarView(profile: profile, size: 54).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName).font(.headline).foregroundStyle(AppTheme.ink)
                Text("@\(profile.handle)").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Handle @\(profile.handle)")
                if !profile.bio.isEmpty {
                    Text(profile.bio).font(.subheadline).foregroundStyle(AppTheme.secondaryInk).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            GameGlyph(symbol: "chevron.right", size: 16)
                .foregroundStyle(AppTheme.secondaryInk).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SocialSectionHeading: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            if symbol == "sparkles" {
                ArcadeSticker(kind: .sparks, size: 32)
            } else if symbol == "person.2" || symbol == "person.2.fill" {
                ArcadeSticker(kind: .players, size: 32)
            } else {
                GameGlyph(symbol: symbol, size: 20).foregroundStyle(AppTheme.accent)
                    .accessibilityHidden(true)
            }
            Text(title).font(.title3.weight(.bold)).foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
        .padding(.top, 4)
    }
}

struct SocialActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            GameGlyph(symbol: symbol, size: 22).accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct SocialLoadFeedback: View {
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        if isLoading { ProgressView().tint(AppTheme.accent).frame(maxWidth: .infinity).padding() }
        if let errorMessage {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(errorMessage).foregroundStyle(AppTheme.secondaryInk)
                    Button("Try again", action: retry).frame(minHeight: 44)
                }
            }
        }
    }
}

@MainActor
struct PlayerGameCardsSection: View {
    let cards: [PlayerGameCard]
    var showsTitle = true
    var onCardsChanged: (() async -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                SocialSectionHeading(title: "Game cards", symbol: "gamecontroller.fill")
            }
            if cards.isEmpty {
                AppCard {
                    HStack(spacing: 16) {
                        GameGlyph(symbol: "gamecontroller", size: 28)
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 60, height: 60)
                            .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("No games shared yet").font(.headline).foregroundStyle(AppTheme.ink)
                            Text("Game cards bring a player's name, progress and play style together.")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(cards, id: \.gameID) { card in
                            let game = descriptor(for: card)
                            NavigationLink {
                                PersonalGameDetailView(game: game, userID: card.userID, cards: cards,
                                                       onCardsChanged: onCardsChanged)
                            } label: {
                                gameCard(card, game: game)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(game.name), \(card.playerName). Open game profile")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func gameCard(_ card: PlayerGameCard, game: GameDescriptor) -> some View {
        let appearance = GameAppearance(game: game)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                GameArtworkView(game: game, kind: .cover)
                    .frame(width: 264, height: 148).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 10) {
                    GameArtworkView(game: game, kind: .icon)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    Text(game.name).font(.headline).foregroundStyle(.white).lineLimit(2)
                }
                .padding(14)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.playerName).font(.headline).foregroundStyle(appearance.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    GameGlyph(symbol: "arrow.up.right", size: 16)
                        .foregroundStyle(appearance.isDark ? appearance.accent : appearance.ink)
                }
                if let days = card.daysPlayed {
                    Label("\(days.formatted()) days played", systemImage: "clock")
                        .font(.caption).foregroundStyle(appearance.secondaryInk)
                } else {
                    Text("Personal game profile").font(.caption).foregroundStyle(appearance.secondaryInk)
                }
                if !card.progress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(card.progress).font(.caption).lineLimit(2).foregroundStyle(appearance.secondaryInk)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 264, alignment: .leading)
        .background(appearance.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(appearance.accent.opacity(0.25), lineWidth: 1))
    }

    private func descriptor(for card: PlayerGameCard) -> GameDescriptor {
        GameCatalog.games.first { $0.id == card.gameID }
            ?? GameDescriptor(id: card.gameID, name: card.gameID, monogram: "GAME", introduction: "A personal game profile.")
    }
}

@MainActor
struct PlayerNameLabel: View {
    let userID: UUID
    @Environment(\.socialRepository) private var repository
    @State private var profile: PlayerProfile?

    var body: some View {
        HStack(spacing: 12) {
            if let profile {
                PlayerAvatarView(profile: profile, size: 50).accessibilityHidden(true)
            } else {
                AvatarPlaceholder(size: 50).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.displayName ?? "Player").font(.headline).foregroundStyle(AppTheme.ink)
                if let profile {
                    Text("@\(profile.handle)").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Handle @\(profile.handle)")
                }
            }
            Spacer(minLength: 0)
        }
        .task(id: userID) {
            profile = nil
            guard let repository else { return }
            let actor = repository.currentUserID
            let result = try? await repository.profile(id: userID)
            guard !Task.isCancelled, repository.currentUserID == actor else { return }
            profile = result
        }
    }
}
