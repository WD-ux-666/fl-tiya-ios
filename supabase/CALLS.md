# Friends and LiveKit calls

Updated 2026-11-09. Applies only to FL-Tiya `gpstwmffctwqlcakmvgw` under the authorized tely account.

## Current state

- Add/request/accept, ordinary removal and Block are separate real server actions. Removed friends keep their message history. Each can send an introduction only if they have not used it for that player before. Calling and unlimited messages require an accepted friend request.
- Profile and chat actions start one-to-one voice or video calls. The app-wide foreground incoming screen supports accept/decline; outgoing calls cancel, and accepted calls hang up. Media controls provide mute, speaker, camera off/on and camera flip.
- LiveKit Swift SDK is pinned to2.18.0 with the host Swift5/iOS17 settings. The complete ten-package graph and binary artifacts resolved with unchanged pins. The November5 Debug app compiled and launched on iPhone17Pro/iOS26 Simulator, and141native unit tests passed. The generator now includes `@executable_path/Frameworks` so embedded LiveKitWebRTC loads at runtime. No real peer media call has been verified.
- Supabase `call-service` v2 is deployed with internal Auth verification (`verify_jwt=false` intentionally). LiveKit secrets are absent; authenticated availability is false and create/accept/token fail503. No fake ringing or connected state is supplied.

## Configure the external service

1. Create or sign into your own [LiveKit Cloud](https://cloud.livekit.io/) account and create a project for FL-Tiya. The [pricing page](https://livekit.com/pricing) currently offers a Build plan at$0/month without a card; confirm the plan and included usage in your account before any upgrade. No LiveKit account/project or paid plan has been created by the assistant.
2. In that project's settings, obtain its WebSocket project URL, API key and API secret. Use an endpoint shaped `wss://YOUR-PROJECT.livekit.cloud`. Only LiveKit Cloud is accepted because this implementation relies on Cloud token revocation.
3. Open [FL-Tiya Edge Function Secrets](https://supabase.com/dashboard/project/gpstwmffctwqlcakmvgw/functions/secrets) and add these exact names: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`. Paste values directly into the provider dashboard. Do not paste secrets into chat, the iOS plist, source files, screenshots or Git. [Supabase secret setup](https://supabase.com/docs/guides/functions/secrets) explains the dashboard path. The server reads these environment variables at request time.
4. Reopen the app or retry a call. `availability` validates the server session and returns true only when the environment has a valid Cloud URL and nonempty credentials. This is a configuration-presence check, not a credential/connectivity probe. Incorrect credentials are detected when the server prepares the room or connects. No client API secret is required.
5. Complete the two-device checks below before claiming working voice/video. Production Apple sign-in remains a separate Apple Developer/provider setup.

## Manual two-account check

Use two separate app instances with regular one-tap accounts, or two instances of **FLTiyaCommunityTesting-Local** signed into Ethan Cole and Maya Reed. See [Live Development Testing](LIVE_TESTING.md) for the configured test scheme. Prefer two real iPhones for microphone, camera, and audio routing. A sample player or offline Preview cannot accept a request or join a call.

1. On the first account, open **Players → Change → All players**, find the other account and tap **Add friend**. Before acceptance, the Voice call and Video call buttons are disabled. On the second account, open **Messages → Friend requests** and tap **Accept**. Refresh each side and open the profile; it should say **Friends**.
2. Before RTC setup, tap Voice call and Video call: the app must show the setup-required message and must not create a ringing call. Privacy Policy remains readable.
3. After RTC setup, keep both apps open. Start Voice call from the friend profile or chat. Beta should receive the full-screen call within the five-second idle polling interval. Only a deliberate start/accept may request microphone access. Accept, speak both ways, mute/unmute, change speaker and end. Verify denial, decline, cancel and unanswered timeout separately.
4. Repeat Video call. Camera permission is also requested. Check remote video, local preview, camera off/on, flip, mute and end. A voice call must never enable the camera.
5. Background or sign out of one app: capture should stop locally and the peer call should end. There is no background/terminated-app incoming-call delivery in this version.
6. Remove friend in the profile and refresh both sides: Add friend should return, old messages stay visible, and calling is disabled. Sending falls back to the one-introduction limit. Removal or blocking also closes any existing server call. To undo a block, open **Profile → Settings → Blacklist**; the two players still need to become friends again.
7. Re-add/accept to restore calling. The old accepted request cannot restore friendship. On an extra device logged into the same account, a stale acceptance or cancellation must not hang up the selected device's call.

## Authorization and cleanup

`private.calls` and `private.call_cleanup` have RLS with no client policies. The public `call_action` wrapper is executable only by `service_role`; the Edge verifies Auth user/JWT then the database independently validates live session, eligible account, immutable cohort, friendship and blocks. Calls are bound to their creating/accepting sessions. Busy and per-minute admission limits are server enforced. Ringing times out after45seconds; accepted calls require both heartbeats within45seconds. Native polls active calls every3seconds and idle incoming calls every5seconds, so delivery is foreground polling rather than Realtime/APNs.

Tokens grant only a single opaque room/participant identity, microphone and (for video) camera. They last120seconds and have no room-admin/data-publish/metadata-update grants. The server creates rooms limited to2participants and rechecks authorization after room preparation/token signing. Neither API secrets nor other participants' opaque identities are returned by ordinary state reads.

Unfriend/block/session/account changes transactionally close call state and enqueue durable cleanup. The worker explicitly revokes both identities' Cloud tokens, then deletes the room; failures remain queued. Immediate pg_net dispatch is backed by a once-per-minute Cron sweep. Cleanup repeats for12minutes to cover LiveKit's refreshed reconnect tokens. [Token expiry alone does not disconnect an active participant, and deleting a room alone can allow recreation with an old token](https://docs.livekit.io/frontends/reference/tokens-grants/). Revocation depends on provider/network availability; it is not a zero-latency distributed guarantee. Native stops capture on local permission loss/end/background/logout, and fails closed when active server confirmation is lost.

The worker token is generated inside Vault and never bundled in the app. As with existing guide discovery, managed `net` request headers may be visible to trusted direct database logins; net is outside the Data API and app roles have no direct login. No webhook or call recording is enabled.

## Verification

- Deployed rollback fixtures:19remove-friend assertions plus57call assertions passed; synthetic state was rolled back.
- Edge suite:87individual pass events,0failures across8files, including15call cases. REPL host did not emit its aggregate final stream-end event; per-case counts matched all declarations.
- Real authenticated HTTP: availability/state for both development accounts, explicit unavailable voice/video creation, anonymous denial and service-only RPC denial. See selected task evidence JSON.
- Static native source/project/grammar validation across Release/Debug/Preview; Debug compilation and141native unit tests passed. Simulator local voice permissions/input worked. Camera permissions were requested, followed by the truthful no-camera-device state. Real physical-camera and peer media tests remain pending.
- Advisors:14intentional private-table RLS/no-client-policy INFO; existing disabled leaked-password-protection WARN remains. See [official password protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance notices are unused-index INFO only. No plan/security setting was changed.

Further release work includes background CallKit/PushKit/APNs, account deletion workflow, finalized retention/operator/contact disclosures and real two-device/network/audio-route testing.
