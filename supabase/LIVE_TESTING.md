# Live Development Testing

## Start in Xcode

1. Open `FLTiya.xcodeproj` and choose the **FLTiya** scheme, which uses Debug for Run. **FLTiyaPreview** opens the offline preview instead.
2. Run the app yourself on an iPhone simulator. The assistant has not compiled or launched this source snapshot.
3. On the login page, open either agreement if you want to read it, then check the consent box and tap **One-tap sign in**. A device account needs no email, password, or verification code. The saved session is restored on the same device; signing out through **Profile > Settings** makes that device account unrecoverable.
4. Both schemes share the five signed-in pages. Use the isolated scheme below to switch between the reserved Ethan and Maya accounts. The local Apple payment sheet uses the [FLTiyaStoreKitTesting scheme](../StoreKit/README.md).

## Community testing on the same simulator

1. On the configured Mac, choose **FLTiyaCommunityTesting-Local** in Xcode's scheme selector. If it is missing from the list, close and reopen `FLTiya.xcodeproj`.
2. Select your iPhone simulator and press **⌘R**. The scheme installs **TIYA Social Test** beside the regular app. On its sign-in screen, choose **Ethan Cole** or **Maya Reed** to fill that test account's email. Check the consent box, then tap **Continue with email**.
3. In **Players**, use **Change** to select **Zenless Zone Zero** and find **Jade Park**, **Tessa Morgan**, and **Kai Lin**. In **Home**, all ten clips have 2–5 fixture likes and six approved fixture comments each as of November 9, before applying the current viewer's visibility filters.
4. To change test accounts, open **Profile > Settings > Sign Out**, then choose the other name and continue. For a friend-request test, send a request to Maya from Ethan, switch to Maya, and open **Messages > Friend requests**. You can also run the same local scheme on a second simulator and select the other account there.

If an older test build is still signed into a device account, it restores that session until you explicitly sign out. The test sign-in screen accepts only the configured test emails. If it cannot find the accounts while launched from Xcode, quit Xcode completely with **⌘Q**, reopen the project, select **FLTiyaCommunityTesting-Local**, and run again. Closing just the project window may leave older launch settings in memory.

The configured iPhone 17 Pro simulator also has the private account list in its Social Test app data. Once it runs the updated build, it can be reopened from the simulator home screen after sign-out. For another simulator or after uninstalling, first install and run the test build on that simulator, then run `python3 -B scripts/configure_community_test_simulator.py` from the project root and reopen the app. If multiple simulators are booted, pass the intended device UDID. The helper only writes the private list into the installed test app's data container.

On another Mac, duplicate the shared **FLTiyaCommunityTesting** template via **Product > Scheme > Manage Schemes**, name the copy **FLTiyaCommunityTesting-Local**, and keep **Shared** unchecked. Under **Edit Scheme > Run > Arguments**, set and enable `FLTIYA_COMMUNITY_TEST_ACCOUNTS` on the private copy. Its value is standard Base64 of a UTF-8 JSON array, with one object per authorized reservation and the fields `displayName`, `email`, and `accessCode`. Keep the shared template blank. The configured Mac already has an owner-only personal scheme outside the repository.

Regular one-tap device sign-in can browse the same ten curated clips and their sample engagement: 2–5 fixture likes and six approved fixture comments per clip before the viewer's visibility filters. In **Players**, each of the 12 game communities has three marked sample players with photo avatars. On Home, an approved sample publisher's avatar opens the same profile layout as a community sample, and its plus button shares the local Follow state. **Add friend** saves the sample **Requested** state. **Message** lets you save one device-only introduction. Sample players do not accept requests, reply, or join calls. For two-sided friendship and messaging, choose **Players > Change > All players** to find another real one-tap account, or use the two reserved accounts in the local community scheme.

The local credentials file is outside Git at `/Users/shangbao666/.codex/private/fl-tiya-ios/development-access.json`, with owner-only file permissions. Both reservations expire on December 3, 2026 (UTC). Treat the codes as passwords: each one opens its own real hosted account. Do not share or commit the file. Expired or disabled reservations lose business-data access, including through existing sessions.

The current social/avatar/community paths and verification boundaries are in [SOCIAL_FEATURES.md](SOCIAL_FEATURES.md).

Current community memberships and profile text are keyed by UUID in [the disjoint rosters](content/development-community-rosters-2026-11-06.json). Current avatar pointers for all 38 development accounts are in [the November 9 scenic mix overlay](content/development-scenic-avatars-2026-11-09.json). Earlier avatar overlays and the original initialization, publisher transfer, and fixture comment manifests record historical snapshots. Private development login labels remain stable.

### Current fictional development profiles — November 6, 2026

| Private login reservation | Display name | Handle |
| --- | --- | --- |
| Development Alpha | Ethan Cole | @ethan_cole |
| Development Beta | Maya Reed | @maya_reed |
| Development TEST Ember | Jade Park | @jade_park |
| Development TEST Harbor | Leo Brooks | @leo_brooks |
| Development TEST Summit | Nina Vega | @nina_vega |

The 38 test accounts use distinct photographs. Alpha, Beta, and six community members retain their previous portraits. The other 30 use 13 scenery photos, 11 back views or silhouettes, and six everyday snapshots. Names, bios, and activity are fictional. Profile fields other than the avatar path, account IDs, video and comment ownership, likes, and friend requests were preserved.

Reopen the app to reload the hosted profile data. No rebuild is required. The 38 development avatars are 256 × 256 JPEGs in private Storage. [Sources, crops, and per-account hashes](../docs/assets/development-scenic-avatars/provenance.json) record the new mix and the eight retained files. The normal user-selected photo upload is unchanged.

## Distinct community fixtures — November 6, 2026

This increment supersedes the shared three-player membership seed and the two-comments-per-video fixture count. There are 36 fictional community members: three different profiles for each of 12 games, including 33 newly reserved Auth accounts. Every profile has a distinct photo avatar and a fictional English game-interest bio. The source accounts remain in the development cohort. The November 9 curated roster shares only approved snapshots and their exact avatars with one-tap device accounts; it does not grant access to the source accounts.

| Game community | Fictional members |
| --- | --- |
| Bob's Game | Luca West, Emma Rowan, Ezra Cole |
| Fantastic Contraption | Iris Shaw, Sam Archer, Leah Quinn |
| Freedoom | Dante Knox, Naomi Chase, Alex Rivers |
| Guacamelee! Super Turbo Championship Edition | Diego Cruz, Ruby Navarro, Max Turner |
| Manifold Garden | Ava Sterling, Felix Quinn, Sofia Hart |
| Minecraft | Nina Vega, Owen Brooks, Chloe Bennett |
| Minetest | Milo Stone, Aria Finch, Ben Ellis |
| PUBG MOBILE | Leo Brooks, Zara Hayes, Marcus Reed |
| Push Me Pull You | Mina Flores, Caleb Price, Zoe Avery |
| SuperTuxKart | Poppy Lane, Noah Wells, Isla Fox |
| Zenless Zone Zero | Jade Park, Tessa Morgan, Kai Lin |
| 0 A.D. | Adrian Vale, Amara Blake, Theo Grant |

Each fixture has exactly one saved game membership. Baseline Ethan/Maya accounts and unrelated real user cards are preserved. Home retains its ten existing clips and original three publishers. Four additional reviewed comments by new fixtures join the existing two on each clip, for six fixture comments per clip (60 total); all 33 new accounts author at least one comment. Existing comments, likes, requests, follows, messages and wallet balances are preserved.

New private login codes are in `/Users/shangbao666/.codex/private/fl-tiya-ios/community-expanded-access-2026-11-06.json` (owner-only). Match `label`/`user_id` to the roster for internal fixture verification. Existing Jade/Leo/Nina codes remain in `community-test-access-2026-11-06.json`; Alpha/Beta codes remain in `development-access.json`. No code is recorded in the project.

For the friend-request walkthrough, send a request to a chosen community member from Alpha; switch to that member's separate Debug review session and accept/decline in Messages > Friend requests; return to Alpha and refresh. Fixtures do not automatically accept, reply, follow or place calls. Following alone does not grant unlimited chat or calls. LiveKit still requires its configured service and a second connected device for a real call.

Run `python3 -B scripts/replace_development_lifestyle_avatars.py verify` to check current hosted avatars and their use in communities, video bylines, and comments. `scripts/expand_development_communities.py verify` delegates to that verifier. Earlier overlays and their assets are historical and must not be replayed; prior private objects are retained for rollback. All account activity remains isolated test data.

This is a hosted data update: reopen the app or pull to refresh communities and comments. No rebuild is required. Native rendering was not launched for this increment; the hosted HTTP evidence is recorded in the selected plan directory.

## Walkthrough

| Step | Action | Expected result |
| --- | --- | --- |
| Profile | In Profile, edit display name and bio, save, leave and return | The saved details reload from Supabase |
| Game card | Games > My Card > Edit game card; enter a player name, days played and progress, then save | The selected game's card appears; Profile shows the same card |
| Persistence | Close and reopen the app | The real session is revalidated; saved profile/card remain |
| Find a player | Players: choose **All players**, search for Maya Reed and open the profile | The reserved Beta identity is visible under its new display name; Jade, Leo and Nina are fictional development fixtures |
| Request | Send Beta a friend request | Messages shows an outgoing request |
| Switch account | Sign out via Profile > Settings, choose Maya Reed on the test login screen, then tap Continue with email | Alpha's tab state, cached messages and wallet clear before Beta opens |
| Accept | Beta: Messages, refresh and accept Alpha's request | A conversation becomes available to both accepted friends |
| Chat | Open the conversation and send text; switch to Alpha, open Messages and refresh | The saved message loads from the server; Alpha can reply |
| Reload | Leave and return, or pull to refresh | Current server records load; messaging does not claim Realtime delivery |
| Wallet in FLTiya | Profile > Sparks | The nine draft packs are listed; the hosted test wallet is Sandbox, initially zero, and purchases are unavailable |
| Local payment test | Run FLTiyaStoreKitTesting, then Profile > Sparks | Localized test prices can open the local Apple test sheet; confirmed local credits stay on this device, separate from the hosted wallet |
| Block, last | From the other player's profile, block that player | Their discovery/profile and mutual chat access are denied; friendship is removed |

To unblock, open **Profile > Settings > Blocked players**. A new friend request must be accepted before messaging/calling resumes; a reverse block remains effective. There is no automatic reset of records you create while testing. To keep the other account searchable, leave its initial display name unchanged until you finish the discovery step, or search its new name.

## What can be tested now

- Real Auth session creation, validation, restoration and sign-out.
- Profile reads/edits, player discovery and manual game-card save/reload.
- Friend request, acceptance/decline, accepted-friend text messages, ordinary removal/re-friending and blocking.
- Sandbox wallet/catalog reads, unavailable checkout and readable draft privacy policy.
- Offline preview as a separate mode, without a fake authenticated account.

## Approved test videos

Sign in with a reserved account in **FLTiyaCommunityTesting-Local** or with one-tap sign-in in **FLTiya**, then open **Home**. The ten curated clips have covers, alternating five game clips and five supplied creator clips. Swipe up or down to switch clips and tap to pause or resume. Use the publisher avatar, comments, and likes to check the interactions. See [CLIPS.md](CLIPS.md) for sources and verification limits.

## Still pending

- Real Apple login: Apple Developer Team, final Bundle ID/capability and Supabase Apple provider setup.
- Real purchases: registered Apple consumable products, matching IDs, Apple server credentials and an eligible Apple-authenticated session. Test access-code login cannot prove payment delivery.
- User video upload/moderation UI, a guide/comment review administration screen, frames and automatic game-account synchronization. Avatar upload is implemented; this latest social UI snapshot still needs your Xcode build/run.
- LiveKit Cloud configuration and two-device voice/video testing. The native entry/screens/media code and server call lifecycle are implemented; missing service credentials deliberately produce an unavailable message. See [CALLS.md](CALLS.md). Background incoming calls are not implemented.
- Realtime chat, Apple-account deletion/revocation and a working support mailbox. Device-account deletion exists separately.

Game days and progress are manually entered. Games > Zenless Zone Zero > Guides loads eight reviewed source-linked entries. My Card > Game resources (also in the card editor) opens the official Steam page preview, three factual character references and shared Guides. Check refresh, source links, back navigation, switching games and sign-out. The official preview can fail on the device network and offers retry/source fallback. No follower ranking is supplied; Home like counts and reviewed comment counts now come from actual server rows. See [GUIDES.md](GUIDES.md) for discovery and review boundaries.

## Server boundaries

`development-login` accepts only a high-entropy access code and uses server-only SHA256 reservations. It creates only the exact reserved Auth UUID/email, never adopts another account or resets a password, then verifies the issued Auth session and `session_context` before returning tokens. Raw codes are never stored in database rows. The endpoint performs its own authentication, so gateway JWT verification is disabled intentionally.

The immutable account cohort survives reservation deletion. Eligibility, active server sessions and cohort checks protect social/Storage data; guides are assigned their own server cohort. Production Apple sessions require a real Apple identity and server-recorded OAuth AMR. Separately approved device accounts require server-verified anonymous Auth/AMR; editable metadata never grants either identity. OAuth AMR does not encode the provider: keep all production OAuth providers other than Apple disabled.

Development `payment_state` always selects the Sandbox ledger/wallet and disables checkout. Production wallet reads and Production purchase credit are denied to development accounts. No credits, accepted friendships or private messages are seeded. The explicitly authorized November 6 development community cards and reviewed fictional clip comments are listed below. The final November5 catalog has ten approved videos (five game and five supplied creator clips), seven preserved archives and eight published ZZZ guides/references. The November6 native ordering alternates game/creator clips, gaming first. The automated collector keeps new candidates private and pending.

## Verification record, November 3, 2026

- `core_permissions.sql`, `payments.sql` and `live_development.sql` executed successfully against the authorized project; all synthetic fixtures rolled back.
- Real HTTPS checks verified both reserved Auth identities, repeat login, refresh, peer discovery, profile write/peer read, card insert/upsert/peer read, Sandbox wallet/catalog, production wallet hiding and revoked-session denial. Temporary profile/card changes were restored/deleted and verification sessions signed out. Both accounts are clean for manual testing.
- The combined Edge/Apple API Node suite passed 54 tests. Native metadata, plist/XML/JSON and grammar checks passed for 36 Swift source files across Release, Debug and Preview. No native compilation, XCTest execution or app run occurred.
- The security advisor reports seven informational entries for intentionally server-only private tables and one warning for disabled leaked-password protection. The reserved access codes are generated with 256 bits of randomness; Auth protection settings and the plan were not changed. Review the [Supabase password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) before introducing user-selected passwords. Performance advice contains only unused-index information in the new database.

The original migration/fixture evidence is kept in `deployment.json` and `.planning/2026-11-03-supabase-backend/`; newer follow-up results do not retroactively change the initial foundation snapshot.
