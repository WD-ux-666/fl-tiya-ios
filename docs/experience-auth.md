# One-tap sign-in and device accounts

Updated 2026-11-09. Applies to `/Users/shangbao666/Desktop/fl-tiya-ios-main/fl-tiya-ios`.

## What the entry does

The regular login page opens both agreements independently. Its unchecked consent control must be selected before **One-tap sign in** is enabled. The client calls Supabase `signInAnonymously()` with no email, password, OTP, or custom metadata, and Supabase assigns a new Auth UUID. Legacy sessions may retain private `experience_email` metadata; it does not identify or recover an account. This uses the real [Supabase anonymous Auth API](https://supabase.com/docs/reference/swift/auth-signinanonymously).

A fresh device creates an independent account. Signing out, clearing the saved login, or losing the device means there is no credential to recover that account. This is an intentional limit of [anonymous accounts](https://supabase.com/docs/guides/auth/auth-anonymous).

The app restores an existing session on the same device instead of creating another account on every launch. The SDK stores credentials using `DeviceAuthStorage`, scoped by Bundle ID and Supabase project, with no iCloud synchronization and [device-only Keychain protection](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly). Existing local SDK Keychain entries are upgraded to that protection when read. No credentials or email addresses are stored in UserDefaults; the existing signed-out intent marker remains there.

## Authorization contract

- `UserSession.isExperience` is separate from the immutable `production` / `development` cohort. An experience account is a production account with a real anonymous Auth session; it is never a development-account reservation.
- App entry and restoration require a fresh Auth `/user` response followed by `session_context`. Its `user_id` must match Auth, and server-owned `is_experience` must match `/user.is_anonymous`. User-editable metadata cannot grant access.
- A missing `is_experience` field defaults to false for compatibility and cannot authorize an anonymous user. Experience classification is rejected for a development cohort.
- Apple availability gates Apple-linked production sessions. It does not disable server-verified experience sessions. Existing Apple and Debug development-code paths remain separate.
- Server rules own catalog visibility, account isolation, friend/call authorization and purchase eligibility. An experience account receives an independent, server-assigned identity.

## Available content and purchases

Experience accounts may read approved development clips and their exact private video/cover paths, plus published development guides. This is a narrow editorial-content exception; development profiles, game cards, friendships, conversations, messages, avatars and pending discovery data stay isolated. New experience accounts socialize with other eligible production accounts using their own UUIDs and normal friendship rules.

Home shows bundled “Shared by” credits on the ten curated imports when their social profiles aren't available to an experience account. The credit is display only: only an uploader returned by the server can open a profile or be followed. The three credit images are the fictional Jade portrait in `docs/assets/test-profiles`, the [snowy lake road by Nicholas Ang](https://www.pexels.com/photo/aerial-view-of-a-road-near-the-snowy-mountains-13074486/) and the [green mountain trail](https://www.pexels.com/photo/man-standing-atop-green-peak-overlooking-mountain-valley-16688865/). Original clip attribution remains in the share sheet.

Hosted purchases stay disabled for device accounts before a StoreKit purchase can start. The server returns `purchase_unavailable_reason: experience_account`, and Sparks explains this restriction. Running `FLTiya` from Xcode lets a verified one-tap account use a separate on-device test wallet. That route does not change its hosted wallet balance.

## Sign-out and deletion

Settings explains the account's recovery limit and confirms experience sign-out. Sign-out immediately locks the app and records intent before waiting for SDK/session/Keychain cleanup. A late or cancelled sign-in result cannot reopen the app or survive the next restoration. The restore-error fallback also warns before discarding cached anonymous credentials; cached state is used only for this warning.

Settings offers a separate permanent deletion action for experience accounts. Settings uses the shared `delete-account` endpoint with an empty JSON body and the current SDK access token. The server verifies and deletes the authenticated account. It never accepts or sends a target user ID. A successful response is `{"deleted":true}`; the app then records sign-out intent and clears its local session. Failure shows fixed safe copy and leaves retry available. The endpoint owns current-session authorization, server-data cleanup, call termination and session revocation. It must support completion after a partial deletion; the native client does not require an active-account RPC before retrying that endpoint.

Apple-linked account deletion and Apple authorization revocation remain a separate unfinished integration. The legacy experience-only endpoint rejects Apple and reserved development accounts.

## Verification scope

`ExperienceAuthenticationTests.swift` contains regressions for consent gating, server/Auth classification agreement, restore, safe errors, duplicate submissions, cancellation, late sign-out results, deletion authorization, cleanup and stale deletion errors. Xcode build, XCTest execution and app or simulator launches were not performed for this change. Swift type checking passed for Debug, Release, and Community Testing. A fresh hosted anonymous session confirmed account creation with no submitted credentials, same identity after token refresh, 10 approved clips, and isolation from sample development profiles. The temporary account was deleted through the same endpoint used in Settings.
