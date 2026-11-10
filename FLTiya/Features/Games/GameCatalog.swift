import Foundation

struct GameDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let monogram: String
    let introduction: String
}

enum GameCatalog {
    static let zenlessZoneZero = GameDescriptor(
        id: "zenless-zone-zero",
        name: "Zenless Zone Zero",
        monogram: "ZZZ",
        introduction: "A shared space for your game moments."
    )

    // IDs match the server's games table and filter both clips and guides.
    static let games: [GameDescriptor] = [
        zenlessZoneZero,
        GameDescriptor(id: "minecraft", name: "Minecraft", monogram: "MC", introduction: "Share builds, adventures and moments with other players."),
        GameDescriptor(id: "pubg-mobile", name: "PUBG MOBILE", monogram: "PUBG", introduction: "Discover battle royale moments and meet squadmates."),
        GameDescriptor(id: "zero-ad", name: "0 A.D.", monogram: "0AD", introduction: "Gameplay and source-linked reading from this game's community."),
        GameDescriptor(id: "minetest", name: "Minetest", monogram: "MT", introduction: "Gameplay and source-linked reading from this game's community."),
        GameDescriptor(id: "supertuxkart", name: "SuperTuxKart", monogram: "STK", introduction: "Watch game moments and explore community sources."),
        GameDescriptor(id: "freedoom", name: "Freedoom", monogram: "FD", introduction: "Watch game moments and explore community sources."),
        GameDescriptor(id: "bobs-game", name: "bob's game", monogram: "BG", introduction: "Watch game moments and explore community sources."),
        GameDescriptor(id: "guacamelee", name: "Guacamelee!", monogram: "G!", introduction: "Watch game moments and explore community sources."),
        GameDescriptor(id: "manifold-garden", name: "Manifold Garden", monogram: "MG", introduction: "Watch game moments and explore community sources."),
        GameDescriptor(id: "fantastic-contraption", name: "Fantastic Contraption", monogram: "FC", introduction: "Watch game moments and explore community sources."),
        GameDescriptor(id: "push-me-pull-you", name: "Push Me Pull You", monogram: "PMPY", introduction: "Watch game moments and explore community sources.")
    ]
}
