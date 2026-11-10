# Sparks Payments Implementation Plan

> For agentic workers: use subagent-driven-development for disjoint native and server tasks. Root owns integration, shared plan and deployment.

**Goal:** Implement native Apple consumable purchase with server-verified, idempotent Sparks delivery.
**Architecture:** StoreKit 2 transactions go to an authenticated Supabase Edge Function; the authenticated direct Apple HTTPS response establishes facts; service-only Postgres operations atomically credit or reverse the wallet.
**Tech Stack:** Existing SwiftUI/Swift 5/iOS 17, StoreKit 2, Supabase Postgres and TypeScript Edge Functions.
**Spec:** `docs/superpowers/specs/2026-11-03-sparks-payments-design.md`.

## Global constraints
- Work only in the correct nested repository. Preserve existing uncommitted source and actual SwiftPM lockfile.
- No iOS build/type check/XCTest execution/launch, commits/pushes, app publication or real purchase.
- Apple configuration unavailable: default disabled, no guessed active product IDs, preview offline.
- English UI/source/docs; no secrets, signed transactions or tokens in logs/files.

## Review focus
Cross-account callbacks; a lost response after durable credit; refund arrival before delivery; duplicate/out-of-order refund notifications; revoked sessions and deleted users.

## Task 1: Database accounting
- [x] Write rollback fixtures for actor reads, service-only delivery, idempotency/replay and refund ordering.
- [x] Add disabled settings/catalog metadata, accounting procedures and narrow grants in `supabase/schema/payments.sql`.
- [x] Review, deploy using apply_migration, preserve its real migration version, run fixtures and advisors.

## Task 2: Native StoreKit and Sparks UI
- [x] Define Codable contracts, payment repository and app-scoped observable store with generation guards.
- [x] Add source tests before implementation for delivery/pending/account behavior; leave native execution pending by user constraint.
- [x] Implement localized pack display, native purchase, server delivery, unfinished retry and lifetime observer.
- [x] Wire Profile, real session and explicitly offline preview, regenerate project metadata.

## Task 3: Apple verification endpoints
- [x] Implement fixed Apple HTTPS lookup, WebCrypto API authorization and typed validation; add negative/authentication tests.
- [x] Implement authenticated receipt endpoint and admission-gated notification reconciliation endpoint using the shared contracts in the spec.
- [x] Review and deploy disabled-by-configuration functions, verify deployed denial paths without fake Apple receipts.

## Task 4: Integration and handoff
- [x] Independent native/security reviews; fix actionable findings.
- [x] Run static verifier and backend tests, record exact scope/results and source hashes.
- [x] Update setup docs, task progress and final answer with Apple setup and native validation pending.

## Delivered scope and external gates

Implemented and deployed on2026-11-03; see current task payments-verification.json. All source/delivery tasks above are complete. This does not mark Apple setup, native compilation, XCTest execution, real purchase/refund testing or proportional refund support complete. Checkout remains disabled.
