# FL-Tiya Native Foundation Implementation Plan

> **For agentic workers:** Use the execution and review practices of superpowers:executing-plans, with user constraints taking precedence over build, test, commit, and worktree defaults.

**Goal:** Deliver a local native SwiftUI iOS foundation that opens in Xcode, preserves mandatory Apple-only authentication and includes five independent tab pages.

**Architecture:** The App owns an observable session boundary. Authenticated content is a native TabView with an independent NavigationStack for each page. Service interfaces explicitly represent integrations that are unavailable.

**Tech Stack:** Swift 5 language mode, SwiftUI, AuthenticationServices, iOS 17+, Xcode 26.0.1, zero third-party packages.

**Spec:** docs/superpowers/specs/2026-11-03-native-foundation-design.md

## Global Constraints

- Repository: /Users/shangbao666/Desktop/fl-tiya-ios-main/fl-tiya-ios.
- All product copy, source identifiers and filenames are English.
- Do not build, execute XCTest, run an app, start a simulator, install dependencies, commit, push or publish.
- Do not use other GitHub accounts or alter global Git configuration.
- Preserve mandatory sign-in; never treat Apple credentials alone as a verified app session.
- No invented live data, server writes, successful purchases or game account statistics.
- Use local static checks and a fresh independent source review; report compilation and runtime as unverified.

## Review Focus

1. An unconfigured auth provider cannot unlock the app, including error and cancellation paths.
2. Missing Apple token/code cannot create a session; credentials must not be logged or persisted.
3. Each tab has independent navigation; login and Settings share a dismissible privacy screen.
4. Empty/unavailable integrations do not imply that refresh, search, requests or purchases succeeded.
5. Every source, asset and scheme reference resolves, with no dependency on absolute local paths.

## Task 1: Session boundary and Apple-only login

**Files:** FLTiya/Features/Authentication/*.swift; FLTiyaTests/SessionStoreTests.swift.

**Interfaces:** SessionStore is @MainActor/@Observable, initialized with an injected AuthenticationService. It exposes isAuthenticated, userDisplayName, isSignInAvailable, isSigningIn, a user-facing error, and native Apple request/result methods. LoginView receives SessionStore and presents PrivacyPolicyView. AppTabView consumes no fake session fixtures.

- [x] Write meaningful authentication regression cases before implementation; leave execution deferred under the no-build instruction.
- [x] Implement the unavailable provider, credential validation and session-only-after-verification behavior.
- [x] Implement the approved login composition and native Apple sign-in control.
- [x] Review cancellation, double submission and missing credential paths statically.

## Task 2: Theme, app shell and independent pages

**Files:** FLTiya/App/*.swift; FLTiya/Core/*.swift; FLTiya/Features/{Home,Games,Players,Messages,Profile,Settings,Legal}/*.swift.

**Interfaces:** AppTheme supplies background, surface, accent, accentSoft, ink, secondaryInk and border colors. ScreenContainer wraps scrollable page content; EmptyStateView displays an icon, title and message. AppTab has stable English cases, labels and symbols. SessionStore gates AppTabView at RootView.

- [x] Add the jade/light theme, reusable cards, buttons, avatars and a native abstract login illustration.
- [x] Implement five independent pages with relevant titles, local search/category selection and honest unavailable states.
- [x] Add game details/guide sections, Settings and the shared readable draft policy.
- [x] Add isolated SwiftUI previews for the login and tabs; never add a production bypass.

## Task 3: Standard Xcode project and static verification

**Files:** FLTiya.xcodeproj/project.pbxproj; FLTiya.xcodeproj/xcshareddata/xcschemes/FLTiya.xcscheme; FLTiya/Resources/*; README.md; .gitignore.

**Interfaces:** iOS app product FLTiya.app; module FLTiya; deployment iOS 17.0; Swift 5; generated Info.plist; development Bundle ID com.fltiya.ios.development; no team or real credentials.

- [x] Write the standard project, resources, shared scheme and optional unit test target.
- [x] Document Xcode opening, source layout, signing placeholders and current integration limits.
- [x] Validate project/plist/JSON syntax, target/source/scheme references and whitespace without compiling.
- [x] Obtain one independent whole-change source review and resolve material findings.
- [x] Update the task record with exact verification results and unverified build/runtime limits.

## Outcome

Completed 2026-11-03. Standard project, login/session boundary and five independent page frameworks delivered. Static validation passed (17 app sources, 1 test source, 2 JSON assets, XML and entitlements). Sixteen auth regression cases remain unexecuted. Independent source review found no actionable defects. No builds, type checks, app/simulator launches, commits or pushes were performed. Evidence: .planning/2026-11-03-native-foundation/verification.json and code-review.md.

## Task 4: Approved development preview follow-up

Approved by the user on 2026-11-03 after seeing the intentionally disabled sign-in button in their simulator. This follow-up adds no build/run authorization.

**Files:** App/DevelopmentPreviewView.swift; App/RootView.swift; Authentication/LoginView.swift; Settings/SettingsView.swift; project generator, static verifier, generated project/schemes and README.

**Interfaces:** Debug-only RootView state controls an isolated DevelopmentPreviewView(onExit:). The preview owns its own unavailable SessionStore and publishes an optional debug-only exit callback to Settings. No production session is fabricated or altered.

- [x] Add a labeled preview shell with top-banner exit and Settings exit back to login.
- [x] Add the debug-only Preview app entry and Preview-only automatic startup.
- [x] Add a distinct Preview identity and shared FLTiyaPreview scheme; preserve Release Archive/Profile actions.
- [x] Validate sources, project graph and Release/Debug/Preview grammar statically.
- [x] Complete independent source review and final handoff.
