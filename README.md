# TIYA

Native iOS app for an English-language gaming community.

## Open in Xcode

Open **FLTiya.xcodeproj** and select **FLTiya**. On2026-11-05 the Debug app compiled and ran on the existing iPhone17Pro/iOS26 simulator;141native unit tests passed. The Supabase and LiveKit dependency pins are unchanged. Physical-device and real two-device calls remain unverified. The November6 social/avatar/community update below has static and hosted-backend verification only; the earlier build does not verify this newer snapshot.

- SwiftUI, Swift 5 language mode, iOS 17+, iPhone.
- Xcode 26.0.1; official `supabase-swift` pinned to exact `2.55.6` and LiveKit `client-sdk-swift` exact `2.18.0`. All ten existing pins were preserved during successful strict-lock resolution. SwiftPM pruned unused documentation/test dependencies from this app's graph.
- The regular app uses `im.seex.sao`. Preview and Community Testing retain their separate development Bundle IDs.
- Signing team is unset. The Apple entitlement is prepared; matching capability and provisioning still need configuration.

### If package downloads time out

If GitHub HTTPS access times out while the Mac's existing system proxy works, save and quit Xcode, then double-click `OpenFLTiyaWithProxy.command` beside the project. It reads the enabled macOS HTTPS proxy and launches Xcode with proxy settings scoped to that process; it does not persist Git settings or change account credentials. Opening uses the existing package cache without requiring a separate network probe. Keep the proxy app running. Then choose **File > Packages > Resolve Package Versions** in Xcode, and select **FLTiyaPreview** for the offline preview.

`./OpenFLTiyaWithProxy.command --check` probes the pinned public Supabase and LiveKit tags. It does not launch Xcode, download package checkouts, build or run the app. The2026-11-05 package failure was traced to direct GitHub timeouts while fetching LiveKit and its `protocol` submodule. A process-scoped proxy resolution completed successfully with all ten pins unchanged; both binary archives matched the upstream SHA-256 checksums. That dependency-only repair did not build or launch the app; the later authorized UI review below did. Evidence: `.planning/2026-11-03-supabase-backend/package-resolution-verification-2026-11-05.json`.

## Development preview

Select **FLTiyaPreview** and an iPhone simulator in Xcode. Running it opens the five independent tabs directly, with a **Development preview / No live services** banner. The distinct app identity is **FL-Tiya Preview**.

Preview uses an unavailable authentication service and no social repository. It creates no fake account or verified session. **Exit preview** returns to login. Run the **FLTiyaPreview** scheme again to reopen it. Both schemes Archive/Profile with Release. No launch argument or persisted flag bypasses production login.

The separate offline Preview scheme has grammar validation only. The authorized runtime review used the live Debug app, not an invented preview account.

## Live development testing

Select **FLTiya** in Xcode for regular one-tap device sign-in. To test the seeded communities and friend requests, run **FLTiyaCommunityTesting-Local** and choose Ethan Cole or Maya Reed at sign-in. It installs as **FL-Tiya Social Test** alongside the regular app, with its own sign-in state. See the [two-account walkthrough](supabase/LIVE_TESTING.md#community-testing-on-the-same-simulator).

Development Alpha/Beta and 36 fictional community players are isolated from device accounts and other production users. The server owns the account cohort and its expiry; client flags and editable user metadata cannot grant access. Release refuses development sessions. Offline preview remains separate and makes no service requests. Raw access codes are kept in private local files outside this repository; use them only in an unshared local Xcode scheme.

See [the manual test walkthrough](supabase/LIVE_TESTING.md) for profile/card persistence, two-account friend and chat tests, refresh behavior and current limitations. These accounts cannot verify Apple sign-in or real StoreKit purchases; their wallet is a separate Sandbox balance with checkout disabled.

## Local Apple payment testing

Choose **FLTiya** and an iPhone simulator in Xcode, stop the old app and Run again. Keep the current signed-in account, or use **One-tap sign in**, then open **Profile > Sparks wallet**. The wallet shows **Your test Sparks** and the **Local test** badge. Test purchases do not incur real charges. The nine packs use a standalone Xcode StoreKit configuration; verified local transactions affect only a persisted account-specific wallet on this device. They never credit Supabase.

**FLTiyaStoreKitTesting** uses the same local payment setup for Run. Archive/Profile use Release, which uses the hosted wallet and cannot enable the local repository through a launch flag. See [local payment test steps](StoreKit/README.md). This change was checked statically; verify the native payment sheet and the test transaction during your Xcode run.

## Supabase connection and authentication

The independent hosted project is [FL-Tiya](https://supabase.com/dashboard/project/gpstwmffctwqlcakmvgw), in the user-selected new organization, Singapore region. The bundled `SupabaseConfig.plist` contains only its public API URL, publishable key and availability flag. Never add a secret/service-role key, Apple private key or password here. See [backend schema and deployment notes](supabase/README.md).

`SessionStore` prepares secure per-attempt state and nonce, serializes verification and accepts only a verified app UUID. `SupabaseAuthenticationService` exchanges the native Apple ID token and raw nonce, verifies the resulting user with Auth and the server's `session_context`, and uses device-only, Bundle-ID-scoped Keychain persistence through the SDK storage interface. Restoration requires server verification; transient failures offer retry. Sign-out records intent before clearing persistent sessions, including a late exchange. No tokens enter UserDefaults or repository files. Apple-linked authorization requires the Apple identity and a server-recorded OAuth session. The separately approved device-account path uses a fresh, server-verified anonymous Auth session and immutable experience attestation; editable email metadata never grants access. Keep unrelated OAuth providers disabled.

**One-tap device sign-in:** review the **User Agreement** and **Privacy Policy**, then check the consent box to enable **One-tap sign in**. The first tap creates a real Supabase device account without email, password, or verification code. Reopening the app restores the account while its saved session remains. Signing out, clearing the saved login, or changing devices makes that device account unrecoverable. See [device authentication](docs/experience-auth.md).

**Apple sign-in:** the native button and token exchange are ready, with the availability flag off. Select the team that owns `im.seex.sao` in Xcode and enable Sign in with Apple for that App ID. Configure the Supabase Apple provider with that same Client ID. A Services ID or private key does not belong in the app. The Apple sign-in flow remains untested, and Apple-linked self-deletion needs a server-side revocation integration before public use.

**Legal documents:** Tap **Privacy Policy** or **User Agreement** on the login screen or in Settings to open the matching PDF inside the app. The app gets the URLs from the [public document index](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy/documents) and offers a readable app copy if the PDF cannot load.

References: [Supabase native Apple setup](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple), [Swift SDK 2.55.6](https://github.com/supabase/supabase-swift/releases/tag/v2.55.6), [Apple capability](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple).

## Current data paths

- Five independent tabs: Home, Games, Players, Messages, Profile.
- Game-community player discovery, viewing/editing profiles with private photo avatars, manually entered game cards.
- Independent following, friend requests with recipient acceptance, one lifetime introductory message per sender/recipient before friendship, continuous accepted-friend chat and paged blocklist/unblocking.
- Server transactions and RLS assign identity and enforce permissions independently of UI.
- Loading, errors, empty state and refresh; chat refreshes manually/on foreground without a Realtime claim.
- Discovery returns up to 50 players; inboxes/latest history up to 100. Three clearly labeled fictional development accounts have game cards in all12communities for manual friend-request tests; requests are never automatically accepted.
- Featured game: Zenless Zone Zero; game cards are manually entered, not automatically verified game-account data.
- Readable draft Privacy Policy and User Agreement, Settings blacklist and support information.

Sparks recharge now has a native StoreKit 2 purchase/delivery retry flow and a Supabase wallet/accounting backend. The nine packs remain inactive with no registered Apple product IDs; Apple API secrets and real login are not configured. See [payment setup and verification boundaries](supabase/PAYMENTS.md). Preview stays offline and cannot simulate a paid balance.

Home now presents approved hosted videos as a vertical short-video feed: one clip per page, muted autoplay/loop, swipe to switch and tap to pause. Author avatars open profiles; another publisher's avatar has a follow control. Source attribution remains in stored captions/share text; the Home Source & credits/mute row has been removed. Real covers show during private media preparation; only the current visible foreground page prepares playback. The approved Home catalog now contains10clips with real covers, including5retained game clips and5user-provided Lifestyle clips; see [video testing](supabase/CLIPS.md). Games loads per-game videos and eight reviewed ZZZ guides/references. All twelve game entries have bundled identifying artwork, distinct native palettes and motifs, and artwork-first introductions. Profile game cards scroll horizontally into a themed per-game page using actual saved player name, days and progress. Guides show their game icon. ZZZ resources include three official reference portraits; its official video card shows the exact poster before opening the publisher's player. This external trailer stays separate from the hosted clip catalog. See [artwork sources](docs/artwork-sources.md). A six-hour official RSS job collects private pending candidates; it never publishes them. See [guide sources and review workflow](supabase/GUIDES.md). User upload/review UI, automatic game syncing and frame purchase/equipping remain pending. Native rendering and foreground playback were observed in the later UI review; production Apple auth, real transactions, physical-camera capture and two-device calls remain unverified.

The current10Homeclips are shared by **[TEST] Ember** (4), **[TEST] Harbor** (3), and **[TEST] Summit** (3). Stay signed in as Development Alpha to test the avatar follow control and author-profile friend requests. Existing requests are preserved; signing into the recipient with its private development code is required to accept manually. IDs, game/creator alternation, original captions and media bytes are unchanged. The exact guarded transfer and rollback snapshot is [the publisher manifest](supabase/content/development-clip-publishers-2026-11-06.json); older import manifests describe historical ownership. Latest transfer HTTP/static checks do not establish a native UI run.

Each of these10clips also has two approved English comments by the two other clearly labeled fictional test accounts (20comments total). These are actual development-cohort records submitted through the normal authenticated comment RPC and reviewed before approval; counts come from the server. Open or reload Comments as Alpha to read them. Exact UUIDs/content and limited cleanup/approval SQL are in [the comment manifest](supabase/content/development-home-fixture-comments-2026-11-06.json). The author profile now reuses the illustrated Profile editor backdrop, angular panels and amber buttons; relationship, message and friends-only call rules are retained. This UI change has source/static verification only.

## Friends and calls

Profiles support Add friend, request acceptance and a separate Remove friend action. Removal cancels the old relationship request, retains history, restores nonfriend messaging limits and invalidates calls; adding again requires a fresh accepted request. Block remains a persistent contact restriction.

Friend profiles and conversations now have voice/video actions with an app-wide incoming call screen, decline/cancel/end, microphone, speaker, camera and flip controls. Server state/token authorization and revocation cleanup are deployed. **Real media is unavailable until LiveKit Cloud secrets are configured.** The current live readiness endpoint returns `available: false`, and call creation fails explicitly without ringing. This version is foreground-only; background/logout ends the call. No CallKit/PushKit/background incoming calls or recording are implemented. Home playback pauses while a call is presented.

See [LiveKit setup and two-account checks](supabase/CALLS.md). The Debug app now compiles and launches with the embedded LiveKit framework. This does not prove a real two-device media call.

The user-provided contact is `fltiya.support@gmail.com` (mail delivery has not been tested). The policy remains a draft until the actual operator and production disclosures are finalized. An original opaque1024px gaming/chat app icon is included.

## Source layout

```text
FLTiya/App/                       Entry, verified session gate, tab shell
FLTiya/Core/                      Theme, public config and social repository
FLTiya/Features/Authentication/    Native Apple and Supabase session lifecycle
FLTiya/Features/Social/            Player profiles, manual cards and editors
FLTiya/Features/Messages/          Friend requests, conversations and text chat
FLTiya/Features/Legal/             Shared draft privacy policy
FLTiya/Resources/                 Assets, public Supabase config and entitlement
FLTiya/Features/Payments/          StoreKit, verified delivery and Sparks wallet
FLTiyaTests/                      Authentication and payment regression source
supabase/                         Schema, payment functions and boundary tests
docs/superpowers/                 Approved scope and design
```

Local verification evidence (`.planning/`), deployment receipts, private Xcode schemes and third-party test portraits are kept outside the Git snapshot. The Xcode project does not depend on them. Some historical content tools need the original local inputs to rebuild fixtures.

## Verification

The November5 UI request explicitly authorized building/running the app and customer-role reviews. The Debug app was built, installed and launched;141 XCTest cases executed with0failures. Three independent review roles checked source and actual screenshots. See [the UI review record](.planning/2026-11-03-supabase-backend/ui-review-2026-11-05/README.md) for the tested snapshot, corrected issues and remaining manual checks. The following script remains a static check only:

```bash
python3 scripts/verify_project.py
```

Grammar parsing does not resolve SwiftUI types or prove compilation, signing or runtime behavior. Backend SQL permission tests are separate from native tests. Physical-camera capture, remote calls, real Apple login and real payments still require external setup and device verification.

## November5 gaming UI and device checks

Midnight surfaces, mint/violet accents, original vector gaming glyphs and a custom five-page dock now cover login, games, player discovery, social profiles/messages, wallet and settings. Each game retains its own sourced artwork and palette. All user-facing copy remains English.

Home now has exactly10approved hosted clips:5retained game clips and5user-provided portrait clips with honest Lifestyle classification and original credits. Seven older entries were archived without deleting originals. Game pages still select gaming-only entries. This supersedes the earlier12clip catalog description above.

In a Debug live session, open **Players > Device test friend > Test voice / Test video**. This local tool requests real hardware permissions; it creates no remote friend, call, message or fake answer. Voice shows live microphone input; video additionally tries your own camera. Nothing is recorded or sent. Close/End test stops capture, as do background/account changes and an incoming real call. The simulator microphone worked; its camera was unavailable and the app displayed that limitation. Use a physical iPhone to verify camera images and a configured second device for a real call.

After adding sources outside Xcode, this standard-library script regenerates project metadata and the pinned package reference without resolving dependencies or building:

```bash
python3 scripts/generate_xcode_project.py
```

## November6 social page themes and Home order

Players now uses a mint party radar, Messages a violet communications console, and Profile an amber/violet player credential. Their original vector artwork and angular panels retain readable labels, real content, search, editing and navigation. Decorative artwork is static and never represents online presence, a rank or an achievement.

Home alternates the existing gaming and Lifestyle clips, starting with gaming. Server order is retained within each category; a longer category continues after the other is exhausted. The existing catalog remains ten approved clips, with no media or moderation changes. Game pages keep their game-only filtering.

This increment is checked statically. The November5 native build/runtime evidence applies to that earlier snapshot; the new layouts and ordering tests have not yet been built or run.

## November6 social actions and avatar update

Home now shows the visible app uploader and avatar, real like state/counts, reviewed comments and native source sharing, without a page counter. Profile uses blended artwork and themed editing with a photo picker. Players filters actual saved game-card communities and offers friend requests plus a paged owner-only blocklist. Only the local microphone/camera test entry was closed; Messages retains its empty-chat card and actual friend call controls remain. See [feature behavior and manual checks](supabase/SOCIAL_FEATURES.md).

Five rolled-back SQL suites passed with 177 ASSERT statements; read-only HTTP checks covered all ten clip interaction contracts, community queries, blocklist cursors and anonymous denials. The native snapshot passed grammar/resource/project checks and independent source review, with no build, typecheck, XCTest or Simulator run in this increment.

## November6 Settings and public privacy policy

Settings now uses matching generated gear, privacy-shield and support-headset stickers. About was removed. Support shows the supplied contact email. Authenticated experience and development accounts can request permanent self-deletion from **Profile > Settings > Delete Account**; the offline preview can only exit. Deleting a development account also removes its uploaded test clips and permanently retires its access code.

The [public privacy draft](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy) is available before sign-in. The app opens the PDF returned by the public document index in its own WebView and keeps an explicitly labelled bundled fallback. See [Settings, deletion and policy behavior](supabase/SETTINGS_AND_PRIVACY.md) for retained records, cache boundaries and manual checks. This increment passed hosted deletion/HTTP and static checks; no new native build or run was performed.
