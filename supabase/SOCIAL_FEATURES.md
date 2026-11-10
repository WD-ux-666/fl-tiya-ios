# Social Features — November 6, 2026

Applies to `/Users/shangbao666/Desktop/fl-tiya-ios-main/fl-tiya-ios` and the authorized FL-Tiya project `gpstwmffctwqlcakmvgw` only.

## Current behavior

| Entry | Behavior and data |
| --- | --- |
| Home | Ten existing approved clips retain gaming-first interleaving. No page counter or shared development banner. The right rail shows a real visible uploader avatar, likes, reviewed comments and Share. |
| Uploader | App uploader identity is separate from original source authorship. Cross-cohort imported media can be visible without disclosing its private development uploader. That case says Imported clip; credits remain accessible. |
| Likes | One persisted like per account/clip, idempotent set/unset RPC. Counts include visible active same-cohort users; blocks apply in either direction. Failed requests retain the last confirmed state. |
| Comments | New comments are pending review. Authors can see/delete their pending submissions; others see approved comments only. The shared count is approved-only. Same UUID/body retries deduplicate; deletion erases text and prevents retry resurrection. Latest 100 visible comments are shown. |
| Share | User-initiated iOS share sheet contains the title, original source and credits. It does not export protected video bytes, Storage paths or signed playback links. |
| Profile > Edit profile | Themed Cancel/Save, photo picker and preview. Crop to a square 512px JPEG, remove source metadata, upload a new immutable private object, then save avatar path/name/bio together. Metadata-save retry reuses the uploaded path. |
| Avatars | Current attached avatar is readable only through authenticated profile visibility policies. No overwrite, public URL or durable image cache. Missing/denied images retain the illustrated fallback. Unreferenced uploads need future trusted cleanup. |
| Players | Choose a game or All players. Game communities are actual saved game-card owners. Add/Requested/Accept/Decline/Friends states use real server relationships. Discovery returns up to 50 matching members; name search narrows the results. |
| Player profile > Block | Immediately hides the player and their clips, comments, and chat. Removes friendship and denies mutual profile/message/call access. |
| Settings > Blacklist | Owner-only limited identity list, 50 per page with timestamp/UUID keyset pagination. Unblock never restores friendship, reverses a report, or defeats a reverse block. |
| Messages | The No chats yet card is retained. Only the Players local microphone/camera hardware-test entry is closed. Actual calls remain friends-only and still require configured LiveKit for remote media. |
| Sign out | Profile > Settings. Removing the shared banner does not change session verification or account separation. |

## Content reports

The arcade flag in Home reports the current video. The flag beside a comment reports that specific comment. The flag to the left of the call buttons in a conversation reports the other player, including before a first message or an accepted friend request. These three entries use the same reason picker and optional 500-character note.

The server accepts reports only from an active signed-in account and checks target visibility, ownership and existing block rules. The same account's retry is acknowledged without replacing the first report, even after its target is hidden. Conversation reports store a peer identifier without attaching message history.

Reporting a video or comment hides that item for the reporter. Reporting a player from a conversation hides their profile, posts, comments, and conversation for the reporter, and stops calls between the two players. The reporter's view updates immediately after success and stays filtered on later reads. A report does not remove the content for other viewers, add the player to Blacklist, or disappear when the player is unblocked.

The private queue was added to FL-Tiya by migration `20261109064322_content_reporting.sql`. The authorized project administrator can review pending items in the Supabase SQL Editor. Reports contain private information; avoid copying them into shared logs.

Migration `20261109072018_report_visibility.sql` applies personal hiding to new and existing reports. The hosted report visibility and reporting rollback suites passed. All three preexisting reports were retained and their personal hides were backfilled. The Swift app passed CommunityTesting type checking and source/project checks across four configurations; no simulator interaction was performed for this update.

```sql
select target_type, target_id, reporter_id, subject_id, reason, details, created_at
from private.content_reports
where reviewed_at is null
order by created_at, reporter_id, target_type, target_id
limit 50;
```

For a manual check, report one video, one approved comment, and one player from a conversation. Each target should disappear for that account as soon as submission succeeds and remain hidden after relaunch. A separate permitted account should still see those items. Verify the three target types in the review queue. The feature does not add an in-app review screen.

## Manual checks in Xcode

1. Build/run the updated FLTiya or FLTiyaStoreKitTesting scheme yourself. The latest snapshot has not been compiled or run by the assistant.
2. Home: check paging, no counter/banner, uploader profile navigation, like/unlike and reload persistence. Open comments and Share; playback should stop while either sheet is visible and return correctly afterward.
3. Submit a comment: it should appear as Pending review only for its author. Reopen/reload, then delete it. A separate trusted reviewer must approve it before another account can see it; no review admin screen was added.
4. Profile: inspect the edge-to-edge faded art. Edit name/bio, select a photo, Cancel and verify no change. Reopen, select a photo and Save; leave/return, restart, and inspect that avatar from another permitted account. Test denied/cancelled picker and network retry.
5. On each real test account, add the same game through Profile > My games. Players > that community should show the other account with Add friend. Check outgoing/incoming states, accept/decline and refresh. All players does not require a game card.
6. Block a friend, verify their profile and content disappear, then open Settings > Blacklist and unblock. Independently reported items should remain hidden. Verify a fresh accepted request is required for chat/calls. No automatic data reset is performed for manual tests.
7. Confirm Messages still shows its empty-state card, the local hardware test entry is absent, and logout remains reachable in Settings.

## Hosted/static verification

- Exact deployed migrations: `20261106043823_experience_content_block_rules.sql`, `20261106043824_clip_social_interactions.sql`, `20261106043826_community_discovery_blocklist.sql`.
- Five rolled-back suites: clip_social, community_blocklist, experience_content_blocks, core_permissions and experience_accounts; 177 ASSERT statements plus expected-denial exception checks. The community fixture includes 55 blocks with the same timestamp to verify full pagination without duplicates or gaps.
- Read-only HTTP checks: ten clip state/comment response contracts, selected/all communities, default/explicit blocklist cursor and four unauthenticated denials. Temporary verification login session was signed out. No business rows were changed.
- Final database: three original profiles/accounts, ten approved clips, zero fixture reservations, zero likes/comments/avatar changes from verification.
- Native: 67 app + 11 test Swift files parse under Release/Debug/Preview; project references, resources, 40 asset JSON files, schemes, entitlements and nine local StoreKit products validate. Independent source review found no remaining definite issue.
- Not verified this increment: native type checking/build, XCTest execution, actual PhotosPicker/Storage rendering, new layout/touch behavior, VoiceOver/Dynamic Type runtime or real two-device calls. No Git commit/push or App Store publishing.

Private interaction tables intentionally have RLS with no direct client policies/grants; only checked RPCs expose them. The advisor's informational [RLS-without-policy notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) reflects that boundary. Existing anonymous-sign-in and password-protection notices were not new settings changes. Verification evidence is under `.planning/2026-11-03-supabase-backend/social-features-verification-2026-11-06.json`.
