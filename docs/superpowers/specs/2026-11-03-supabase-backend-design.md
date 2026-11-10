# Supabase Backend Integration

## Authorization and target

The user selected Supabase and authorized implementation and deployment. After the original organization's free-project quota was exhausted, the user connected the `tely` account and explicitly selected its empty organization. The independent project is `FL-Tiya` (`gpstwmffctwqlcakmvgw`), region `ap-southeast-1`, quoted at USD 0/month. Other projects are outside scope.

## Current delivery

- Native Apple identity-token verification through Supabase Auth; verified UUID is the app identity. First sign-in creates the profile automatically.
- SDK session refresh and Bundle-ID-scoped Keychain storage. Persist no tokens in UserDefaults, logs or the repository.
- Real profile discovery and editing, manually entered game cards, explicit friend requests and accepted-friend text conversations.
- SQL enforces authorization even if a caller bypasses the UI. Transactions serialize pair operations and assign sender identity on the server. Client UUIDs make message retries idempotent.
- Empty database states are real empty states. Development preview explicitly receives no live repository or authentication provider.
- Curated guides, reviewed video metadata and private immutable media buckets, wallets and permanent frame entitlements receive protected schema foundations. Their ingestion, review, payment and call workflows remain pending external configuration.

## Access rules

Every exposed application table uses RLS plus explicit grants. Signed-in actors require an active app account, a current Auth session and an Apple identity. Blocks apply in both directions. Profiles are available to active, unblocked app users; requests and conversations are participant-only; pending/rejected posts are owner-only. User metadata never grants permissions. Economic and moderation fields are server-only.

Privileged transactional functions stay in the unexposed `private` schema, with locked search paths, explicit checks and narrow execute grants. Public RPC wrappers use invoker security. No anonymous business reads or writes are enabled.

## Native integration

Pin official `supabase-swift` to exact version `2.55.6`; retain Swift 5 language mode and iOS 17 deployment target. Record package references only; no automatic dependency resolution or build is authorized. Bundle only the public project URL, publishable key and Apple-enabled flag. The button stays unavailable until the real Apple provider and matching App Bundle ID are configured.

The existing `SocialRepository` is the data boundary. Views own loading, empty/error state and explicit refresh. Message history is bounded to the latest 100 messages; discovery to 50 players and inboxes to 100 rows. Targeted relationship lookup does not infer friendship from a truncated inbox. Realtime, older-history pagination, clip upload/playback, production purchases and calls are not claimed in this increment.

## Verification

Inspect the empty target before migration, review source SQL, deploy via `apply_migration`, record the actual server migration version, execute transaction-scoped permission/behavior assertions and roll them back, then inspect advisors. Check project references, plist/XML/JSON and Swift grammar locally. Do not equate static checks with a compiled app or an end-to-end Apple sign-in.

## Outstanding setup

Apple team and final Bundle ID/provider configuration; actual contact mailbox; permitted guide sources; moderation operations; media pipeline; StoreKit products and server verification; voice/video service. These are explicit pending capabilities, not simulated successes.
