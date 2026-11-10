# Artwork sources

## Zenless Zone Zero wordmark

- Asset: `FLTiya/Resources/Assets.xcassets/ZenlessZoneZeroWordmark.imageset/wordmark.png`
- Source: [Wikimedia Commons, *Zenless Zone Zero wordmark.svg*](https://commons.wikimedia.org/wiki/File:Zenless_Zone_Zero_wordmark.svg)
- Source revision: [permanent file description](https://commons.wikimedia.org/w/index.php?title=File:Zenless_Zone_Zero_wordmark.svg&oldid=1115398860)
- Raster source: `https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1e/Zenless_Zone_Zero_wordmark.svg/960px-Zenless_Zone_Zero_wordmark.svg.png`, fetched through `wsrv.nl` when the original host was unreachable. The bundled PNG is the proxy's raster rendition (960 × 304), not a byte-for-byte copy of the Commons thumbnail.
- Credit on source page: miHoYo/HoYoverse; SVG vectorization by VulcanSphere.
- Copyright status on source page: `PD-textlogo` (simple text/geometric logo). Commons also flags the wordmark as a trademark. Display it only to identify the game and avoid suggesting that FL-Tiya is endorsed by HoYoverse.
- Bundled PNG SHA-256: `2bf0d741c86fd56e12346dfbf6c5f22f813acd70e583372143d14c53ff892453`.

The asset has transparent pixels and a black wordmark. Place it on a light background at a legible size; do not crop, recolor, or add effects to the mark.

## Bundled game identification artwork — November 5, 2026

These images identify the games in the local catalog and personal game cards. The source pages below are publisher listings or the official game/project websites and repositories. Publisher art and trademarks retain their original ownership; the source links document provenance, not a new license or endorsement. No permission to redistribute unrelated game content is inferred.

- The three mobile icons were obtained from the publishers' Apple App Store listings through Apple's public lookup metadata.
- The four Steam headers were obtained from each developer's published Steam store metadata, with the app name and developer checked before download.
- The Minetest icon is pinned to the official project's `5.9.1` release to match the catalog's legacy Minetest name; the project is now called Luanti.
- The 0 A.D. hero was decoded from the official site's WebP into PNG for the asset catalog. No crop, recolor, or generated replacement was applied. All other files are the downloaded source bytes.
- `GameIconBobsGame` is the official 32 × 32 pixel-art favicon, not a high-resolution app icon. `GameIconSuperTuxKart` is the official horizontal logo.
- Only included resources are returned by `GameArtworkCatalog`; missing dedicated icons/covers return `nil`. All 12 catalog games have at least one genuine identifying image.

### Source inventory

#### GameIconZenlessZoneZero

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconZenlessZoneZero.imageset/artwork.jpg` (512 × 512; 55,957 bytes).
- Credit: COGNOSPHERE / HoYoverse.
- [Official source page](https://apps.apple.com/us/app/zenless-zone-zero/id1606356401); [downloaded image](https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/c8/ee/27/c8ee2769-fe15-e1ea-aeb7-2247a535767a/AppIcon-0-0-1x_U007emarketing-0-8-0-85-220.png/512x512bb.jpg).
- SHA-256: `19fa9259f303ed2d9b6ceb031f74bd0bf887725452fcc0a284a910c7d206119d`.

#### GameIconMinecraft

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconMinecraft.imageset/artwork.jpg` (512 × 512; 12,798 bytes).
- Credit: Mojang / Microsoft.
- [Official source page](https://apps.apple.com/us/app/minecraft-play-with-friends/id479516143); [downloaded image](https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/fb/a7/be/fba7bef5-248f-e255-da11-dd06a30e3828/AppIcon-0-0-1x_U007emarketing-0-10-0-85-220.png/512x512bb.jpg).
- SHA-256: `821e6443ea74f7ec86c60b247998ae9b3f51678d72b282766d17f1161863fbcb`.

#### GameIconPUBGMobile

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconPUBGMobile.imageset/artwork.jpg` (512 × 512; 72,318 bytes).
- Credit: Tencent Mobile International / KRAFTON.
- [Official source page](https://apps.apple.com/us/app/pubg-mobile/id1330123889); [downloaded image](https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/6d/98/24/6d9824dd-f75f-9bd6-221e-33324fedecb2/AppIcon-0-0-1x_U007emarketing-0-7-0-85-220.png/512x512bb.jpg).
- SHA-256: `2d787984ef1611a78fc7c9dca861f7cdb1f9316e1043b7ff5c8350a3d86cecf0`.

#### GameIconZeroAD

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconZeroAD.imageset/artwork.png` (128 × 128; 65,896 bytes).
- Credit: Wildfire Games.
- [Official source page](https://play0ad.com/); [downloaded image](https://play0ad.com/img/icon.png).
- SHA-256: `087d5e2fab85a7c84a57c3cc397b3ea26716fb399c9bd8e37d86d3bf1d59dca4`.

#### GameIconMinetest

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconMinetest.imageset/artwork.png` (128 × 128; 8,068 bytes).
- Credit: Minetest / Luanti project contributors.
- [Official source page](https://github.com/luanti-org/luanti/tree/5.9.1/misc); [downloaded image](https://raw.githubusercontent.com/luanti-org/luanti/5.9.1/misc/minetest-xorg-icon-128.png).
- SHA-256: `2187cac4bff86348994c7e78b64c09b12182777b0de2442b3669fb3f07f14032`.

#### GameIconSuperTuxKart

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconSuperTuxKart.imageset/artwork.png` (512 × 256; 125,201 bytes).
- Credit: SuperTuxKart project contributors.
- [Official source page](https://supertuxkart.net/); [downloaded image](https://supertuxkart.net/assets/images/logo.png).
- SHA-256: `27469b6b9da933322263b04e193693bac75c69195fd7297160586a005b9b6c72`.

#### GameIconFreedoom

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconFreedoom.imageset/artwork.png` (576 × 696; 2,396 bytes).
- Credit: Freedoom project contributors.
- [Official source page](https://freedoom.github.io/); [downloaded image](https://freedoom.github.io/mugshot.png).
- SHA-256: `0120ee55633e99c4aa03ac9e6d65fce20d876e01e797aa3d4e52f3760cbbe15b`.

#### GameIconBobsGame

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameIconBobsGame.imageset/artwork.png` (32 × 32; 127 bytes).
- Credit: bob's game / Robert Pelloni.
- [Official source page](https://bobsgame.com/); [downloaded image](https://bobsgame.com/bobsgame.png).
- SHA-256: `385d3b9bc1659ed349bdb787475cafdaf2f9bd4975e51d35892eea490961377a`.

#### GameCoverZenlessZoneZero

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverZenlessZoneZero.imageset/artwork.jpg` (1280 × 720; 273,431 bytes).
- Credit: COGNOSPHERE / HoYoverse.
- [Official source page](https://www.youtube.com/watch?v=4G2ZnN7kSDg); [downloaded image](https://i.ytimg.com/vi/4G2ZnN7kSDg/maxresdefault.jpg).
- SHA-256: `6fe8e1a8e0cfa3b2005112c0b34876da9487454b2ad74b74397a8d27ac5a8062`.

#### GameCoverMinecraft

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverMinecraft.imageset/artwork.jpg` (570 × 321; 197,817 bytes).
- Credit: Mojang / Microsoft.
- [Official source page](https://www.minecraft.net/en-us/about-minecraft); [downloaded image](https://www.minecraft.net/content/dam/minecraftnet/games/minecraft/key-art/About-Minecraft_Featured-Image-0_570x321.jpg).
- SHA-256: `b30a85d8aa61069421494c45247f9be67176a0d221de3aabe7a58f94f666af80`.

#### GameCoverPUBGMobile

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverPUBGMobile.imageset/artwork.png` (1318 × 776; 1,686,570 bytes).
- Credit: KRAFTON / Proxima Beta / Tencent.
- [Official source page](https://www.pubgmobile.com/en-US/home.shtml); [downloaded image](https://www.pubgmobile.com/images/event/home/s3_play1.png?v=1.0).
- SHA-256: `03ceecd47fc61e7f17e678abc420abc3a275ae263646f397b58267179234a2b0`.

#### GameCoverZeroAD

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverZeroAD.imageset/artwork.png` (2000 × 1125; 4,677,355 bytes).
- Credit: Wildfire Games.
- [Official source page](https://play0ad.com/); [downloaded image](https://play0ad.com/wp-content/gallery/screenshots/BabylonParadise_hu_41ee1bf3e406447c.webp).
- SHA-256: `d9691d57f7b9b400b992b0f4aedf3c7acb503a04b39471f816d1a835fff9b197`.

#### GameCoverSuperTuxKart

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverSuperTuxKart.imageset/artwork.jpg` (800 × 450; 48,879 bytes).
- Credit: SuperTuxKart project contributors.
- [Official source page](https://supertuxkart.net/Gallery); [downloaded image](https://supertuxkart.net/generated/assets/gallery/STKEvolution_1-800-17bc58c4e.jpg).
- SHA-256: `21fe904fbf4c615dada3dcdf0940c8457b0a655e3def03851fa42332857d2ccd`.

#### GameCoverFreedoom

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverFreedoom.imageset/artwork.png` (1600 × 1200; 63,371 bytes).
- Credit: Freedoom project contributors.
- [Official source page](https://freedoom.github.io/screenshots.html); [downloaded image](https://freedoom.github.io/img/screenshots/p1_3.png).
- SHA-256: `ca6505d1199ff09a645d0e6f7da641a5dbf3208ee4dc1ef5a93d483351619c29`.

#### GameCoverGuacamelee

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverGuacamelee.imageset/artwork.jpg` (460 × 215; 40,563 bytes).
- Credit: Drinkbox Studios.
- [Official source page](https://store.steampowered.com/app/214770/); [downloaded image](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/214770/header.jpg?t=1762522710).
- SHA-256: `f84b8218be0c6911a081bc99a4f9bc0e0505e82a7c3e1f468607abccb3cc5617`.

#### GameCoverManifoldGarden

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverManifoldGarden.imageset/artwork.jpg` (460 × 215; 33,884 bytes).
- Credit: William Chyr Studio.
- [Official source page](https://store.steampowered.com/app/473950/); [downloaded image](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/473950/header.jpg?t=1603220474).
- SHA-256: `e1cc2f849afd7bc88816312bf95f1429f54d5ede4066f000fa3e37df03a7d3f1`.

#### GameCoverFantasticContraption

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverFantasticContraption.imageset/artwork.jpg` (460 × 215; 44,168 bytes).
- Credit: Northway Games / Radial Games.
- [Official source page](https://store.steampowered.com/app/386690/); [downloaded image](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/386690/header.jpg?t=1684873262).
- SHA-256: `5aad21214451064520ca73fcff32e3ee07b3da820ddb9fe0bac6e2ca38e8f314`.

#### GameCoverPushMePullYou

- Bundled file: `FLTiya/Resources/Assets.xcassets/GameCoverPushMePullYou.imageset/artwork.jpg` (460 × 215; 13,947 bytes).
- Credit: House House.
- [Official source page](https://store.steampowered.com/app/362380/); [downloaded image](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/362380/header.jpg).
- SHA-256: `fdaa48de95b55ffa05df7a07c860e0d290b3e738b28ac2243909245a35fd1f28`.

#### OfficialVideoZZZMechaCover

- Bundled file: `FLTiya/Resources/Assets.xcassets/OfficialVideoZZZMechaCover.imageset/artwork.jpg` (1280 × 720; 273,431 bytes).
- Credit: COGNOSPHERE / HoYoverse.
- [Official source page](https://www.youtube.com/watch?v=4G2ZnN7kSDg); [downloaded image](https://i.ytimg.com/vi/4G2ZnN7kSDg/maxresdefault.jpg).
- SHA-256: `6fe8e1a8e0cfa3b2005112c0b34876da9487454b2ad74b74397a8d27ac5a8062`.

### Exact official video identity

[YouTube's official oEmbed response](https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D4G2ZnN7kSDg&format=json) identifies the video as **Version 3.3 Teaser - "Journey to the Sky" | Zenless Zone Zero**, published by **Zenless Zone Zero** ([`@ZZZ_Official`](https://www.youtube.com/@ZZZ_Official)). The bundled 1280 × 720 image is that exact video's thumbnail. `OfficialVideoZZZMechaCover` retains the integration asset name, but the verified title does not call it a mecha preview.

The previously bundled black transparent `ZenlessZoneZeroWordmark` is unchanged.

### Cunning Hares character reference portraits

Publisher website character CMS records, linked by the official [character page](https://zenless.hoyoverse.com/en-us/character). Credit: COGNOSPHERE / HoYoverse. Copyright remains with the publisher; these are identifying reference portraits, not a claim that the app owns the characters.

- **Billy Kid** — `ZZZCharacterBillyKid`; CMS record `102184`; [official record list](https://sg-public-api-static.hoyoverse.com/content_v2_user/app/3e9196a4b9274bd7/getContentList?iChanId=287&iPageSize=100&iPage=1&sLangKey=en-us); [publisher image](https://webstatic.hoyoverse.com/upload/op-public/2022/05/19/eea067cdceeda7b8cf45fd776f74e13a_4226709793790517741.png); pixelWidth: 397; pixelHeight: 335; SHA-256 `a729ff74d8d096694c0b2c7da8e1d110a04d77630ae4ea1e3a4b67f03aecf05b`.

- **Nicole Demara** — `ZZZCharacterNicoleDemara`; CMS record `102183`; [official record list](https://sg-public-api-static.hoyoverse.com/content_v2_user/app/3e9196a4b9274bd7/getContentList?iChanId=287&iPageSize=100&iPage=1&sLangKey=en-us); [publisher image](https://webstatic.hoyoverse.com/upload/op-public/2022/05/19/1a82a5a83749ca6b128c81381fe94063_1074261892080967189.png); pixelWidth: 397; pixelHeight: 335; SHA-256 `b0979ed92874ffeb2d9c21f54f797158ea353cde11691ab3161a468c624e9d32`.

- **Anby Demara** — `ZZZCharacterAnbyDemara`; CMS record `102103`; [official record list](https://sg-public-api-static.hoyoverse.com/content_v2_user/app/3e9196a4b9274bd7/getContentList?iChanId=287&iPageSize=100&iPage=1&sLangKey=en-us); [publisher image](https://webstatic.hoyoverse.com/upload/op-public/2022/05/18/ba3e92bf0ea390a702969b204ae562f3_3515216936997121656.png); pixelWidth: 397; pixelHeight: 335; SHA-256 `57c147ad4872ce2b0b79e86884077bd1fb08ba12c92553112588b4fcfc44667f`.

## Original FL-Tiya app icon — November 5, 2026

- Asset: `FLTiya/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- Original AI-generated gaming/social mark: controller and speech-bubble silhouette, electric mint with violet rim on a midnight background. No third-party game artwork is used in this app identity.
- Prepared as a full-bleed opaque RGB PNG,1024×1024. The operating system applies the icon mask. Selected as AppIcon in all app configurations.
- SHA-256: `503281dd38c5b237a02ce556351511f8c7de1e484e788a125fe2b623f82da9e2`.
- This supersedes the quiet emerald/ivory draft generated earlier the same day, following the user's stronger gaming-style direction.

## TIYA login illustration — November 10, 2026

- Asset: `FLTiya/Resources/Assets.xcassets/SocialThemeArt/LoginArcadeArtwork.imageset/LoginArcadeArtwork.jpg` (1440 × 960).
- Original image generated for TIYA: two space arcade pilots, a vintage cabinet, and halftone textures. The left side leaves room for the native login title.
- SHA-256: `596a5a44d656de2f3378c0bcd64f4f544f13ca2429b291f48229c9b1e3a1cfcc`.

Two original ImageGen illustrations complement the hero. Both are transparent PNGs in the same asset group.

- `LoginArcadeMarquee` (1086 × 280): handheld arcade console, checkered flag, and star. SHA-256: `ef5256e262423a0206d69cc9b46f7601dcaac1395d116127ab8da2633aaa9f43`.
- `LoginArcadeAfterglow` (1086 × 260): arcade tokens, joystick, and halftone trails. SHA-256: `c47e3a3607f3ac91d70411e3da2e86a3f726fee91a292ef9ba17fa42c889f80f`.
