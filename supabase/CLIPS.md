# Hosted Video Feed

## Current catalog — November 5 replacement

The latest catalog contains **10 approved videos: five game clips and five user-provided creator clips**, with ten real frame covers. Home alternates gaming and creator clips, gaming first, preserving each category's server order. This section supersedes the historical 12-video totals below.

Retained game clips: **Minecraft, PUBG MOBILE, SuperTuxKart, Guacamelee! and Manifold Garden**. The seven older/niche clips (both 0 A.D. videos, Minetest, Freedoom, Bob's Game, Fantastic Contraption and Push Me Pull You) are archived with `status=rejected` and explicit **catalog archive, not safety rejection** audit notes. Their rows, prior review records and all fourteen private video/cover objects are retained. They are absent from the approved Home feed and inaccessible to development peers and experience readers.

| Creator attribution from supplied CSV | Video duration | Original codec | Provided source |
| --- | --- | --- | --- |
| Addison Rae | 15.033 s | HEVC (`hvc1`) | [TikTok](https://www.tiktok.com/@addisonre/video/7402810473412037934) |
| Brooke Monk | 13.700 s | H.264 (`avc1`) | [YouTube Shorts](https://www.youtube.com/watch?v=krZt5pSdbmI) |
| Dasha Taran | 14.767 s | HEVC (`hvc1`) | [TikTok](https://www.tiktok.com/@tarankaaa/video/7702436802958855431) |
| Danya Milokhin | 10.600 s | HEVC (`hvc1`) | [TikTok](https://www.tiktok.com/@danya_milokhin/video/7637091746899397906) |
| Vinnie Hacker | 10.267 s | HEVC (`hvc1`) | [TikTok](https://www.tiktok.com/@vhackerr/video/7639393995159866638) |

The user supplied these five local MP4s and the source CSV and explicitly requested their import into this test catalog. Creator names, original titles, source links and source dates are preserved **as supplied metadata**. No new CC license, independent identity verification or licensed public-release claim is asserted. The original MP4/audio bytes are unchanged; only real frame covers were extracted. The import account owns the app rows and is not represented as the original creator. Files and derived media remain in the existing private bucket.

People clips use `content_category=lifestyle` and `game_id=NULL`. They do not create a fabricated game in the twelve-game catalog. Migration `20261105103531_clip_content_categories.sql` preserves the real game FK and enforces gaming/non-null-game versus lifestyle/null-game combinations. The existing moderation, cohort, active-session and exact-media-path policies apply to both categories. Home reads both approved categories; game-specific video queries explicitly select gaming and the real game ID.

Preparation used existing macOS avconvert/Quick Look and Python standard-library helpers, with no installed dependencies. Original container/codec/duration/dimensions were inspected, start/middle/end segments decoded, and those frames plus covers visually inspected. All files fit the current native byte/dimension limits. Two covers use clearer actual start frames. **Audio was not listened to and native AVPlayer execution was not run.** Sample decoding is not exhaustive frame-by-frame moderation.

The five rows were inserted pending, ten immutable objects uploaded without upsert, and all ten full authenticated readbacks matched the frozen SHA-256 values. Both a development peer and a real temporary experience reader saw no pending metadata and were denied all ten pending objects. One guarded transaction approved the new five and archived the old seven, enforcing the exact final ten IDs. Final normal Home queries returned ten rows for both reader types, with five gaming and five lifestyle records; the experience reader downloaded all ten videos and ten covers in full and matched every frozen hash. Both readers were denied the seven archived rows and fourteen archived objects. Unauthenticated, public-object and signed-URL probes remained denied.

Final state: **17 preserved post rows, 10 approved, 7 archived/rejected, 0 pending, 34 private clip objects**. The temporary experience verification user self-deleted; fresh import-only development sessions were logged out locally. The existing user and social data were not changed.

Reproducible artifacts:

- [Frozen five-file manifest](content/development-creator-clips-2026-11-05.json) with source CSV hash, original hashes, real cover hashes, decoded samples and honest review limits.
- [Original catalog snapshot](content/development-catalog-before-2026-11-05.json) and [final snapshot](content/development-catalog-after-2026-11-05.json), including object metadata and review history.
- [Pending SQL](content/development-creator-clips-2026-11-05-pending.sql), [atomic approval/archive SQL](content/development-creator-clips-2026-11-05-approve.sql), and [guarded compensating restore SQL](content/development-creator-clips-2026-11-05-restore.sql). Restore is inert and was exercised only in a rollback transaction; exact final IDs, immutable fields and unchanged review history are checked before it can restore prior approvals. A count-preserving wrong-ID test was rejected.
- [Verification evidence](../.planning/2026-11-03-supabase-backend/creator-clips-verification-2026-11-05.json).

## Test in Xcode

1. Stop the existing app and Run the updated **FLTiya** or **FLTiyaStoreKitTesting** scheme. Keep the latter for local payment testing. Offline Preview has no hosted feed.
2. Use **Continue with email**, then open **Home**. The **For You** feed shows one full-height clip at a time. Use the header refresh button to reload the real feed.
3. The current clip prepares and autoplays muted, with its real cover shown while opening. Swipe up/down to switch clips, tap the video to pause/resume, and use the speaker button to change sound. The existing landscape clips keep their original aspect ratio.
4. Open **Source & credits** to read the complete creator/source/license/modification text; playback stops while it is open. Check closing the sheet, changing tabs, backgrounding, returning and refreshing. Inactive pages must not play or retain protected media files. Opening failures offer **Try again**; cover failures do not block video preparation.

The latest November6 social UI snapshot has not been built or launched. The November5 authorized native review applies only to its earlier snapshot. Actual new overlay rendering and device lifecycle behavior still need your run. Likes and reviewed comments now persist through real RPCs; no engagement counts or follower rankings are fabricated. User video upload/moderation screens remain pending. See [SOCIAL_FEATURES.md](SOCIAL_FEATURES.md).

## Imported material

| Clip | Video creator / game artwork | Imported duration | MP4 bytes | Source |
| --- | --- | --- | --- | --- |
| 0 A.D. - Village and Resource Gathering | PantheraLeo1359531 / Wildfire Games | 20.000 s | 9,009,076 | [Commons file](https://commons.wikimedia.org/wiki/File:4K-Gameplayausschnitt_0AD_20221001_001.webm) |
| Minetest - Flowing Lava | PantheraLeo1359531 / Perttu Ahola and The Minetest Team | 19.633 s | 3,261,762 | [Commons file](https://commons.wikimedia.org/wiki/File:Devtest_Minetest_5.6.1_Lava_block_2023.01.04_-_20.29.08.02.webm) |
| 0 A.D. - Winter 2007 Gameplay Preview | Wildfire Games | 20.000 s | 4,662,136 | [Commons file](https://commons.wikimedia.org/wiki/File:0_A.D._-_Gameplay_Preview_-_Winter_2007.ogv) |

The source file pages state **CC BY-SA 3.0** for the media/artwork. The imported derivatives retain [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/), creator and source credits, and a first-20-seconds/H.264-conversion notice. The title/source URL, attribution and license link remain readable in **Source & credits**. Code licensing on the game file pages is separate from the video/artwork license.

Exact original/transcode URLs, source and uploaded SHA-256 hashes, post IDs, immutable storage paths and captions are in [the manifest](content/development-clips-2026-11-04.json). The import account owns the App row and is not presented as the original creator. The videos are confined to the existing development author cohort by current access policies.

## Import and review boundary

No schema or policy change was required. Each post was inserted as pending before an authenticated no-upsert upload to the private clips bucket. Original MOV transcodes were fetched from Wikimedia and converted with the preinstalled macOS avconvert utility; no media dependency was installed. H.264 markers, movie duration, decoded Quick Look thumbnails and source licensing/credits were checked. Complete authenticated downloads matched the reviewed MP4 hashes. This is not a claim of exhaustive frame-by-frame moderation or native app playback.

Only after those checks, a trusted database transaction recorded three private.video_reviews and approved the exact matching immutable objects. Pending and approval DML snapshots are preserved beside the manifest; do not replay them blindly. The import helper never auto-approves content, follows redirects, exposes credentials, makes objects public or requests signed playback URLs. It opens separate development sessions and logs out only those sessions.

The client explicitly queries approved posts, downloads through the current SDK session with a fresh cacheNonce to avoid reusing an old authenticated HTTP response, and plays a per-account/per-presentation local MP4. The 32 MiB file acceptance limit is checked after the SDK download; this increment is for the small imported clips, not bounded-memory streaming of arbitrary long uploads. Local files are protected and cleaned on normal player dismissal/logout; an interrupted process may leave temporary data for the operating system to purge.

## Observed verification

- Owner authenticated upload and full-byte download: HTTP 200, matching SHA-256 for all three files.
- Before approval: peer unfiltered metadata query returned HTTP 200 with none of the imported IDs; all three media reads were denied with HTTP 400.
- After approval: the other development account sees all three IDs and reads matching media with HTTP 200.
- The exact native feed selection/order/join returned all three records with matching full captions and game names. The pinned SDK's cacheNonce download route returned HTTP 200 with matching MP4 bytes.
- Before and after approval: anonymous feed HTTP 401; anonymous media, public object URLs and signed URL requests HTTP 400.
- Python importer syntax and a synthetic redirect regression were checked; the redirected destination was not requested.
- Native test sources are not executed. Project metadata and Swift grammar results are recorded separately in `.planning/2026-11-03-supabase-backend/clips-verification.json`.

Existing Supabase advisory state is unchanged: seven INFO entries for intentionally server-only private tables and the previously documented leaked-password-protection WARN. Its [official remediation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains separate from this content import; no Auth settings or paid resources were changed.

## Real covers, November 4 follow-up

The three covers are actual frames extracted from the imported MP4s with the preinstalled macOS Quick Look utility. Their original dimensions are 640×360, 640×360 and 480×360. The original card implementation cropped these to 16:9; the subsequent vertical feed preserves the cover/video aspect ratio. No new artwork was added. Cover attribution, source and CC BY-SA 3.0 remain with each clip, and the caption identifies the extracted-frame modification. Exact PNG dimensions, byte sizes, hashes and private paths are recorded in the content manifest.

Existing approved development rows were temporarily returned to pending for the immutable cover upload, then reapproved in one guarded transaction after visual inspection and authenticated full-byte verification. Three cover-specific review records were appended; the three original video reviews remain. The exact-row DML snapshots are `development-covers-2026-11-04-pending.sql` and `development-covers-2026-11-04-approve.sql`. The cover helper cannot approve posts, overwrite objects or change access policies.

Hosted checks observed owner upload/readback HTTP200 with matching bytes, peer pending metadata hidden and cover HTTP400, then peer approved metadata/path/caption and cover HTTP200 with matching hashes. Anonymous feed remained401; anonymous, public and signing cover requests remained400. The bucket remains private and production still has zero approved imported clips.

Native covers use a fresh authenticated cache nonce, exact owner/post paths, a 2MiB post-download acceptance limit and a decoded-image dimension limit of4096 pixels per side. UIImage state belongs to each visible cover and is cleared on departure/account changes; images are not written to disk. The SDK still buffers a response before the byte limit is checked. Missing/failed covers leave video playback available. Nine additional cover test methods were reviewed as source only (23 clip test methods total). At the cover checkpoint,39 app and6 test files passed grammar-only parsing in Release, Debug and Preview. Build, type checking, native tests and actual cover rendering were not run. Historical frozen source hashes and hosted evidence are recorded in `.planning/2026-11-03-supabase-backend/covers-verification.json`.

## Vertical short-video presentation

The user's later correction replaces the cover-card list with a full-height vertical feed. Home's header is an overlay; zero-spacing pages match the available content viewport below the existing development banner and above bottom navigation. Refresh preserves a valid selected clip. Only the selected visible Home page in the foreground prepares and plays; background pages never begin a media download. Switching pages/tabs, opening credits or backgrounding stops the player and removes its protected presentation file. Returning prepares the current page again; this first implementation does not prefetch neighboring videos or implement long-video streaming.

The native AVPlayerLayer surface keeps landscape gameplay intact with aspect-fit presentation. Autoplay is initially muted; tap pauses/resumes, the speaker control changes mute, and the current item loops. Complete attribution is available through Source & credits. No fake likes, comments or follower counters were added. Existing share/upload UI remains explicitly unavailable.

Independent review found no blocking source issues, including pre-canceled task entry, late asset/seek callbacks and identity changes. Seven additional lifecycle tests were added as source only. Final project membership is41 app+7 test files; all48 Swift files passed Release/Debug/Preview grammar parsing, metadata and existing scheme isolation checks. No native build/typecheck/tests/run occurred. Actual viewport layout, swiping, AVPlayer readiness/loop/audio and device lifecycle behavior remain manual Xcode checks. See `.planning/2026-11-03-supabase-backend/vertical-clips-verification.json` for frozen source hashes. No backend policy, data or object was changed in this presentation update.

## Initial catalog expansion, November 4

The catalog now has **10 approved development clips and 10 real covers**. The original three above remain intact; seven reviewed additions follow.

| Game | Video creator | Duration | Source |
| --- | --- | --- | --- |
| SuperTuxKart | SuperTux Kart-Autoren | 20.0 s | [Commons file](https://commons.wikimedia.org/wiki/File:Benchmark_SuperTux_Kart_Base_Profile_2025.07.04_-_10.19.10.02.webm) |
| Freedoom | CapoFantasma97 | 20.0 s | [Commons file](https://commons.wikimedia.org/wiki/File:Freedoom_-_Short_gameplay.webm) |
| Bob's Game | Bobsgame | 20.0 s | [Commons file](https://commons.wikimedia.org/wiki/File:Bob%27s_game_puzzle_gameplay.webm) |
| Guacamelee! Super Turbo Championship Edition | DrinkBox Studios | 20.0 s | [Commons file](https://commons.wikimedia.org/wiki/File:Guacamelee%21_STCE_B-roll_gameplay.webm) |
| Manifold Garden | William Chyr | 20.0 s | [Commons file](https://commons.wikimedia.org/wiki/File:ManifoldGarden_BRoll02_E3_V01.webm) |
| Fantastic Contraption | Sarah Northway | 20.003 s | [Commons file](https://commons.wikimedia.org/wiki/File:Fantastic_Contraption_gameplay_condensed.webm) |
| Push Me Pull You | House House | 7.233 s | [Commons file](https://commons.wikimedia.org/wiki/File:Push_Me_Pull_You_gameplay_1.webm) |

Exact source licenses, permanent source revisions, creator/developer permission evidence, original and derivative hashes, selected offsets and immutable paths are in [the seven-video manifest](content/development-seed-clips-2026-11-04.json). The SuperTuxKart segment uses seconds30–50 because its opening showed settings instead of racing. Captions retain each CC BY-SA3.0/4.0 media license and modification notice. Underlying game artwork rights are recorded separately; the Freedoom BSD copyright, conditions and disclaimer are bundled as readable app credits, and SuperTuxKart's mixed artwork licenses link to the individual source credits. These permissions cover the selected footage, not all artwork from these games.

All14 new objects uploaded under the development owner with no upsert; complete authenticated readbacks matched the reviewed SHA-256. Before approval, Beta saw zero imported IDs and all14 media reads were denied. A trusted transaction appended7 video reviews and approved only exact owner/game/caption/path/MIME/byte matches. The6 earlier video/cover reviews remain, for13 total. The bucket remains private; anonymous/public/signing probes remain denied. Post-approval peer verification is recorded with this checkpoint.

Games > select a game > Videos loads the real server-filtered game feed with covers and the private native player. Home keeps its vertical short-video feed. Native rendering/playback still needs the user's Xcode run; no native build or tests were executed.

## Recognizable games and Zenless Zone Zero, November 5 follow-up

The development catalog now has **12 approved hosted clips with 12 real covers**. The two newest rows show first in Home, and each also appears under its game in Games > Videos. The other ten reviewed clips remain available.

| Game | Content and honest source date | Creator | Duration | License and source |
| --- | --- | --- | --- | --- |
| Minecraft | Actual Xbox México gameplay, 2023 | Xbox México | 8.8 s | [Commons file](https://commons.wikimedia.org/wiki/File:Minecraft_Gameplay.webm), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| PUBG MOBILE | Official fifth-anniversary Erangel promotion, 2023; selected source seconds 45–65 | PUBG MOBILE | 20.0 s | [Commons file](https://commons.wikimedia.org/wiki/File:PUBG_MOBILE_-_Erangel%27s_New_Imagination_Plaza.webm), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |

The Minecraft Commons page identifies the particular Xbox México depiction as CC BY material; it does not grant blanket rights to Minecraft media. The PUBG MOBILE file has a separate Commons source-license review. Captions give the creator, original file page, license and trim/conversion/cover changes. Both media files are H.264 MP4 from Commons QuickTime transcodes. Real frame covers were inspected. The six local source/video/cover hashes, byte counts, selected offsets and immutable private paths are in [the frozen manifest](content/development-popular-clips-2026-11-04.json). Review covered decoded output samples at the beginning, middle and end plus both covers and source-license pages; the PUBG audio track was detected but its content was not listened to. This is not an exhaustive frame-by-frame or native playback check.

Both posts were inserted **pending** and four immutable private objects were uploaded by the development owner with no upsert. Full authenticated download hashes matched the reviewed local files. Before approval, the other development account saw no imported metadata and received HTTP 400 for all four objects. Only after that boundary check were two exact rows approved with two review records. Afterwards the other account saw both rows and downloaded all four objects with HTTP 200 and matching hashes; anonymous, public URL and signing attempts remained denied. The app's Home query returned all 12 approved rows with PUBG MOBILE and Minecraft first, and each game-filtered query returned its one new clip. The production cohort still has zero approved imported clips. Evidence is in `.planning/2026-11-03-supabase-backend/popular-clips-pending-http.jsonl` and `popular-clips-approved-http.jsonl`.

The Zenless Zone Zero Games hero now shows the sourced [game wordmark](../docs/artwork-sources.md) instead of the `ZZZ` placeholder. Its Videos section offers a [HoYoverse official Version 3.3 video](https://www.hoyoverse.com/en-us/news/166759) in an in-app Safari view of the publisher-linked YouTube player. It is labeled as a **trailer** and is not uploaded, counted as a hosted clip, or represented as a player's video. Network playback and the updated native UI remain for the user's Xcode run to check. The card also exposes the publisher announcement as a separate source link.

## November 5 experience access

[Anonymous experience accounts](EXPERIENCE_ACCOUNTS.md) have a deliberate read-only exception for approved development clips and their exact authenticated video/cover paths. This supersedes the development-only audience statement above for these accounts; development profiles and social data remain isolated. Rows are not promoted or copied.
