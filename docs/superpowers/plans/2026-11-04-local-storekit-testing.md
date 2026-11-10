# Local StoreKit Testing Implementation Plan

**Goal:** Enable a real Apple local test payment sheet with account-isolated on-device test Sparks.
**Architecture:** Debug-only scheme flag selects an atomic local payment journal; reuse StoreKit and PaymentStore. Live server data is never credited by local transactions.
**Tech Stack:** Existing SwiftUI, Swift 5, iOS 17+, StoreKit 2; no new dependencies.
**Spec:** docs/superpowers/specs/2026-11-04-local-storekit-testing-design.md.

## Global constraints
No native build/typecheck/XCTest execution/app or simulator launch, Git commit/push, paid resources or remote mutation. English source/UI/docs. Existing FLTiya and FLTiyaPreview semantics retained.

## Tasks
- [x] Native payment boundary: structured verified delivery, Xcode environment, Debug local catalog/journal/config, source regression tests first; review durable idempotence, identity/environment checks, cancellation, storage failure and cross-account callbacks. Worker owns payment runtime and native tests.
- [x] Root wiring/UI: select local repository only through guarded Debug flag and verified development cohort, show unmistakable local test wallet/banners and product loading failure guidance. Root owns app/root/SparksView.
- [x] Configuration: add standalone nine-consumable .storekit plus FLTiyaStoreKitTesting scheme through the deterministic generator; keep .storekit out of resources and Release actions. Root owns project/config/generator/static verifier.
- [x] Verify/review: static schema/catalog/scheme/Swift parsing, independent native isolation review and fixes, record evidence. No native execution.
- [x] Handoff: update English setup/manual testing docs and task records, provide concise Chinese scheme/run instructions.

## Completion evidence
On November 4, 2026 the generator produced 33 app sources and 5 test sources. Static verification passed all 38 Swift grammar files under Release/Debug/Preview, nine product mappings and scheme/resource isolation. Regeneration was byte-identical and retained all seven existing SwiftPM pins. Targeted whitespace checks and tracked Git diff checks passed. Independent review found a post-commit permission error edge case; it was fixed and re-reviewed with no remaining actionable findings. Added 16 local test methods and one server-boundary regression as unexecuted source. See `.planning/2026-11-03-supabase-backend/local-storekit-verification.json`. No native build, typecheck, XCTest execution or app/simulator launch occurred; actual Xcode product loading and payment sheet remain for user verification.

## Review focus
Local JWS must never reach Supabase/Apple Server API; Release/env flag misuse; unknown or real-environment product; duplicate/replayed credit after reload; account switching during a purchase; local journal write failure; cancelled/pending/unverified/revoked transaction; generator regeneration preserving the local scheme and SwiftPM lockfile.
