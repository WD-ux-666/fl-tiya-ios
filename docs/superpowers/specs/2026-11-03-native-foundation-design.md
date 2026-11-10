# FL-Tiya Native iOS Foundation

## Approved scope

On 2026-11-03 the user approved beginning the native iOS client: an Xcode project, the approved English Apple sign-in page, five independent pages and bottom navigation. This supersedes the earlier static-design-only stage. The user requires a project that opens directly in Xcode.

## Product and visual direction

- Overseas gaming social app; English UI and source identifiers.
- Tabs, in order: Home, Games, Players, Messages, Profile.
- Warm off-white background, deep jade accents, rounded cards and dark ink text (approved light option B).
- Sign-in copy: FL-Tiya; Watch. Share. Connect.; Game clips and shared interests. Meet people who love your games.
- Apple is the only sign-in method; no registration screen or guest access.
- First game: Zenless Zone Zero. Game catalog structure must allow more games later.
- Assets can follow later. Use native artwork placeholders without presenting sample media as published content.

## Approaches and implementation choice

The repository has no existing app or stack. Native Swift/SwiftUI is the implementation choice for the user's Xcode requirement; it keeps the first client small and needs no third-party dependencies. UIKit is possible but adds unnecessary screen scaffolding here. A web wrapper would not meet the requested native client structure.

## Architecture

- Swift, SwiftUI, iOS 17+, standard Xcode project and shared scheme.
- App entry owns a session store; only a verified session can show the main tabs.
- Each tab owns its NavigationStack and local selection/search state.
- Authentication uses an injected service; the initial unavailable service cannot authenticate anyone. The native Apple button remains unavailable until a real verifier is configured.
- Public game metadata is local and non-sensitive. Social lists start unavailable/empty without fabricated users, balances, messages, likes or successful writes.
- The login and Settings screens can both open the same readable draft privacy policy. Contact is explicitly a placeholder, fltiya.support@example.com, and must be replaced before release.
- SwiftUI previews may show isolated screens without granting production guest access.

## Limits and external setup

Backend exchange, account creation, session persistence, friend requests, messaging, calls, media upload/review, guide aggregation, game account binding, StoreKit and avatar purchases are later integration work. No unknown API endpoints or SDKs will be guessed.

The backend configuration file will not be copied or read for this foundation. The final Apple team, Bundle ID and capabilities are unverified. Use an unmistakable development Bundle ID and leave the signing team unset.

## Verification and authorization

Work only in /Users/shangbao666/Desktop/fl-tiya-ios-main/fl-tiya-ios. The current clean main checkout is the user-selected project location. Keep changes local and uncommitted. Do not alter GitHub authentication or global Git settings. No builds, test execution, app launch or simulator use is authorized; use static project, plist, JSON, reference and diff checks. Report these limits explicitly.

## Approved development preview follow-up

On 2026-11-03 the user approved a development version for browsing the existing page framework in the simulator before backend integration. Add FLTiyaPreview with a Preview build configuration and a separate development Bundle ID/display name. It opens the tab shell automatically and shows a persistent Development preview / No live services banner. Exit returns to login, which offers a debug-only Preview app entry. Settings can exit this preview too.

The preview owns an isolated unavailable SessionStore and never creates a verified user. Debug-only UI is excluded from Release; archive/profile actions use Release. No production login bypass, persisted preview flag, live services or simulated successful social/purchase actions are added. The user still has not authorized the assistant to build or run the app.
