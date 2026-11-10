/// Bundled publisher artwork used to identify each game. Asset names are
/// returned only when an image set is included in this target's resources.
enum GameArtworkCatalog {
    static func iconName(for gameID: String) -> String? {
        switch gameID {
        case "zenless-zone-zero": "GameIconZenlessZoneZero"
        case "minecraft": "GameIconMinecraft"
        case "pubg-mobile": "GameIconPUBGMobile"
        case "zero-ad": "GameIconZeroAD"
        case "minetest": "GameIconMinetest"
        case "supertuxkart": "GameIconSuperTuxKart"
        case "freedoom": "GameIconFreedoom"
        case "bobs-game": "GameIconBobsGame"
        default: nil
        }
    }

    static func coverName(for gameID: String) -> String? {
        switch gameID {
        case "zenless-zone-zero": "GameCoverZenlessZoneZero"
        case "minecraft": "GameCoverMinecraft"
        case "pubg-mobile": "GameCoverPUBGMobile"
        case "zero-ad": "GameCoverZeroAD"
        case "supertuxkart": "GameCoverSuperTuxKart"
        case "freedoom": "GameCoverFreedoom"
        case "guacamelee": "GameCoverGuacamelee"
        case "manifold-garden": "GameCoverManifoldGarden"
        case "fantastic-contraption": "GameCoverFantasticContraption"
        case "push-me-pull-you": "GameCoverPushMePullYou"
        default: nil
        }
    }

    static func characterPortraitName(for characterName: String) -> String? {
        switch characterName {
        case "Anby Demara": "ZZZCharacterAnbyDemara"
        case "Nicole Demara": "ZZZCharacterNicoleDemara"
        case "Billy Kid": "ZZZCharacterBillyKid"
        default: nil
        }
    }
}
