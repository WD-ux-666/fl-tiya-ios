import SwiftUI

@MainActor
struct GameReferenceView: View {
    let game: GameDescriptor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GameHeroCard(game: game)
                officialCover
                if game.id == GameCatalog.zenlessZoneZero.id {
                    characterReferences
                }
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        resourceHeading("GUIDES & REFERENCES", symbol: "book.closed")
                        Text("Read, then make it your own")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Browse source-linked reading for your game. Your game card keeps the player details you choose to share.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                        NavigationLink {
                            GameGuidesView(game: game)
                        } label: {
                            HStack {
                                Text("Browse guides").font(.subheadline.weight(.bold))
                                Spacer()
                                GameGlyph(symbol: "arrow.up.right", size: 18)
                            }
                            .foregroundStyle(AppTheme.accent)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Game resources")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
    }

    private var officialCover: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                resourceHeading("OFFICIAL GAME PAGE", symbol: "photo")
                Text(game.name)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                GameArtworkView(game: game, kind: .cover)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.border))
                Text("Artwork identifies the game. Rights remain with the original publisher or project.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
                Link(destination: officialPageURL) {
                    Label("View official game page", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private var characterReferences: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 16) {
                resourceHeading("CHARACTER REFERENCE", symbol: "person.3")
                Text("Meet the Cunning Hares")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                ForEach(["Anby Demara", "Nicole Demara", "Billy Kid"], id: \.self) { name in
                    HStack(spacing: 12) {
                        if let portrait = GameArtworkCatalog.characterPortraitName(for: name) {
                            Image(portrait)
                                .resizable().scaledToFit()
                                .frame(width: 74, height: 74)
                                .background(AppTheme.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppTheme.violet.opacity(0.2)))
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                            Text("Cunning Hares")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(AppTheme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                }
                Link(destination: Self.charactersURL) {
                    Label("Official character profiles", systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44)
                }
                Text("Source: Zenless Zone Zero official character pages. Reference checked November 5, 2026. These are game references, not characters linked to your account.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }

    private func resourceHeading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            GameGlyph(symbol: symbol, size: 23)
                .frame(width: 38, height: 38)
                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1.6)
        }
        .foregroundStyle(AppTheme.accent)
    }

    private var officialPageURL: URL {
        let pages = [
            "zenless-zone-zero": "https://zenless.hoyoverse.com/en-us/",
            "minecraft": "https://www.minecraft.net/en-us/about-minecraft",
            "pubg-mobile": "https://www.pubgmobile.com/en-US/home.shtml",
            "zero-ad": "https://play0ad.com/",
            "minetest": "https://www.luanti.org/",
            "supertuxkart": "https://supertuxkart.net/",
            "freedoom": "https://freedoom.github.io/",
            "bobs-game": "https://bobsgame.com/",
            "guacamelee": "https://store.steampowered.com/app/214770/",
            "manifold-garden": "https://store.steampowered.com/app/473950/",
            "fantastic-contraption": "https://store.steampowered.com/app/386690/",
            "push-me-pull-you": "https://store.steampowered.com/app/362380/"
        ]
        return URL(string: pages[game.id] ?? "https://zenless.hoyoverse.com/en-us/")!
    }

    private static let charactersURL = URL(string: "https://zenless.hoyoverse.com/en-us/character")!
}
