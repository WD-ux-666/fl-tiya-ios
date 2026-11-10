# Anonymous experience accounts

Implemented November 5, 2026 for the authorized FL-Tiya project `gpstwmffctwqlcakmvgw`.

## Identity and sessions

The email entry validates format locally and calls Supabase `signInAnonymously`. It creates a genuine Auth user and server session. The entered address is unverified private `user_metadata.experience_email`; it is never `auth.users.email`, a public profile field, an identity lookup, or an authorization claim. Entering the same address on another device creates a separate UUID with separate data. A lost/signed-out anonymous session cannot recover the original account through that address.

The Auth creation trigger sets immutable `private.accounts.is_experience` only from the server's `auth.users.is_anonymous`. Its cohort is always `production`; development reservations remain separate. Eligibility requires the actual anonymous Auth row, an active application account, a matching unexpired `auth.sessions` row and server-recorded `anonymous` AMR for that session. JWT anonymity must match the attestation. Editable metadata cannot enable experience access. Linking this account into another auth kind is outside this flow and fails eligibility rather than silently changing account type.

`session_context()` includes `is_experience: Boolean`. Existing Apple production accounts return false and retain their Apple identity/OAuth session checks. Reserved development accounts retain their enabled/unexpired exact reservation checks. Call Edge authentication opts into anonymous validation; its database checks independently require the selected eligible server session. Payment Edge authentication continues rejecting anonymous sessions by default.

## Content and data boundaries

Experience accounts have ordinary production own-profile, card, friendship, messaging and foreground call behavior. Existing cohort and block predicates still protect social data. They cannot read development profiles, cards, avatars, friendships, conversations or messages, including those belonging to the reserved test accounts.

One deliberate read-only exception permits **approved** development `video_posts` and the exact private clip video/thumbnail paths referenced by those posts. Pending/rejected posts, arbitrary objects, object listing/signing, development writes and public buckets are not enabled. The twelve reviewed development clips become visible without promoting or copying their rows. A matching content-only exception permits published development guides/reference links; draft guides and private collection/review queues remain inaccessible. Existing publication/source validation and trusted editorial writes remain enforced.

Anonymous production checkout is disabled in `payment_state` (`purchase_unavailable_reason: experience_account`) and in the service-only credit function, even if another identity or OAuth AMR were later attached. Production wallets remain independent zero-initialized accounts. Reserved development StoreKit Sandbox behavior is unchanged.

## Current-account deletion

Authenticated `POST /functions/v1/delete-experience-account` accepts **only `{}`** and returns `{"deleted":true}` on completion. It does not accept a user ID, email or session ID from the request body.

1. Auth `/user` verifies the access JWT. The database independently locks and verifies that same current user/session, actual anonymous Auth type, production experience attestation and active/deleting account state.
2. Prepare marks the account deleting, immediately closes calls and queues durable RTC cleanup, and revokes other sessions. The current session remains solely to permit deletion retries; ordinary app access is denied while deleting.
3. The server obtains at most 500 owned `avatars`/`clips` paths per pass and removes them through the Storage API using server-only credentials. Paths are constrained to the current UUID. The handler repeats up to ten passes per request; larger or failed cleanup can be retried.
4. A checked database transaction verifies no owned Storage objects remain and hard-deletes this Auth user. Existing FK cascades remove sessions, profile, cards, wallet, posts, social edges, conversations and messages. The call cleanup outbox has no Auth FK and survives to revoke/disconnect RTC access.

A Storage insert trigger locks the Auth parent and active account before admitting objects in app buckets, serializing uploads against deletion. No direct Storage table deletion is used by the endpoint. Rollback fixtures reassign only synthetic object ownership to exercise the final empty-ownership check; real API removal is verified separately.

If network/service failure interrupts deletion before completion, the account stays deleting and the same current session can retry. A response lost after successful hard deletion cannot authenticate again; the client must clear its local session rather than treat the original email as recovery. The endpoint never deletes Apple or reserved development accounts.

## Configuration and verification

Anonymous Sign-Ins is enabled in Auth settings. No new secret is required: the Edge uses existing Supabase server environment variables. `verify_jwt=false` is intentional because the function verifies Auth `/user` itself and then actual server session state; a publishable API key alone cannot delete anything.

Sources: [Supabase Anonymous Sign-Ins](https://supabase.com/docs/guides/auth/auth-anonymous), [Managing user data and Storage ownership](https://supabase.com/docs/guides/auth/managing-user-data), [Storage remove](https://supabase.com/docs/reference/javascript/storage-from-remove). Supabase's anonymous cleanup guide explicitly supports deletion from `auth.users`; the endpoint uses a locked service-only transaction so conversion/session changes cannot race the final check.

Migration: `20261105091558_anonymous_experience_accounts.sql`. Canonical source: `schema/experience_accounts.sql`, applied after the foreground call migration. Verification evidence: `../.planning/2026-11-03-supabase-backend/experience-accounts-verification.json`. Native build, simulator and paid purchases are outside this verification.

## Deployed verification

Auth public settings reports anonymous users enabled. Migration history version `20261105091558` matches the local filename. `delete-experience-account` is active version 1; `call-service` is active version 2. Six deployed-schema rollback suites passed 236 explicit SQL assertions plus exception-denial checks. Nine Edge test files produced 95 passing test events and zero failures in the native Node test runner; the persistent REPL host does not emit an aggregate stream completion event, so that limitation is retained in evidence.

Two real temporary anonymous users with the same unverified metadata email received independent UUIDs, read twelve approved clips and eight published guides, and successfully read all 24 private clip/cover objects using 64-byte authenticated range GETs. Own profile/card/avatar, friendship and messaging worked. Anonymous purchase verification returned 401, a cross-development-cohort request returned 403, and caller-selected deletion was denied. Both users self-deleted through the deployed endpoint; the uploaded avatar was removed through the Storage API, stale app access was denied, and profile/social/message cascades were confirmed. Final counts returned to two original users, one original session, 24 original media objects and zero temporary anonymous users, experience accounts, calls or cleanup jobs.

LiveKit is still unconfigured: authenticated call availability correctly returns false. Actual RTC connectivity, native runtime, Apple Sign-In, StoreKit transactions and persistent deletion retry after app restart were not exercised. Raw HEAD requests to the authenticated media route returned 400; the actual authenticated range GET playback route passed all 24 objects. No signed/public media URLs were introduced.
