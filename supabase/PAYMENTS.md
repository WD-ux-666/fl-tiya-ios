# Sparks payments

## Implemented flow
Profile > Sparks loads the authenticated wallet, nine pack definitions and the newest 50 ledger entries. Native StoreKit 2 supplies real localized product prices. Each consumable purchase uses the verified Supabase user UUID as `appAccountToken`. Only a matching backend delivery acknowledgement permits `Transaction.finish()`; network failures stay in StoreKit's unfinished queue for login, foreground and manual retry. A cancelled purchase and pending approval never credit the wallet.

Production and Sandbox use separate wallets and ledger filters. No transaction can move between accounts; environment plus transaction ID remains unique after account deletion. The client has no economic write grant. Retired product mappings remain valid for delivery of already paid transactions. Checkout availability does not disable delivery/refund reconciliation.

`schema/core.sql` remains the foundation. Apply `schema/payments.sql` afterwards for a new installation. The existing hosted project has the exact payment migration preserved as `migrations/20261103084151_sparks_payment_accounting.sql`; do not replay either script on it.

## Current setup

Deployed on 2026-11-03 to FL-Tiya `gpstwmffctwqlcakmvgw`: `verify-apple-purchase` v1 and `apple-payment-notifications` v1 are ACTIVE. Missing-auth/invalid-token requests returned401; wrong methods405; notification configuration absent503. Payment and core permission SQL fixtures passed and rolled back. The server suite passed45/45tests. The35Swiftfiles passed grammar/metadata checks for all three configurations;16paymentXCTest cases were authored but not executed. These results do not establish real Apple verification or native compilation.
The catalog contains all nine agreed draft amounts with inactive rows and **null** App Store product IDs. `private.payment_settings` has null Apple identifiers and purchases disabled. Real Apple login is also disabled. Offline preview displays reference prices and an unavailable balance; it cannot call the payment backend or simulate a paid credit.

| Draft USD | Sparks | Catalog ID |
| --- | ---: | --- |
| 0.99 | 400 | sparks_400 |
| 1.99 | 800 | sparks_800 |
| 4.99 | 2,450 | sparks_2450 |
| 9.99 | 5,150 | sparks_5150 |
| 19.99 | 10,800 | sparks_10800 |
| 29.99 | 16,800 | sparks_16800 |
| 49.99 | 29,400 | sparks_29400 |
| 69.99 | 42,700 | sparks_42700 |
| 99.99 | 63,700 | sparks_63700 |

These are draft commercial references. A purchase button always uses `Product.displayPrice`, not the draft USD field. Catalog names/order/amounts and product mappings are server-managed. Keep a delivered product's unit amount stable: create a new product/pack for a changed amount rather than reinterpreting an old purchase. Keep retired mappings for unfinished delivery and later refunds.

## Server verification boundary
`verify-apple-purchase` authenticates the exact user access token with Supabase Auth and checks its issuer, audience, subject and session. SQL rechecks that the user has a live Apple identity/session and an active application account before crediting. The user supplies only a JWS routing hint, never an amount or beneficiary.

The server creates a fresh ES256 authorization JWT with WebCrypto and calls the fixed Apple HTTPS Get Transaction Info endpoint. Redirects, invalid responses, unexpected bundle/environment/transaction ID, non-consumables, quantity other than one and ownership/account mismatches fail closed. Only the transaction payload received directly from Apple through this authenticated TLS request supplies economic facts. Incoming client/notification JWS values are **not independently signature or certificate-chain verified** and never supply trusted credit/refund facts. This explicit HTTPS provenance design avoids the current Supabase Node X509 incompatibility; there is no fallback that accepts a decoded client receipt.

`apple-payment-notifications` requires a high-entropy URL admission token before any database or Apple lookup, then accepts an incoming V2 envelope solely as a request to recheck a transaction ID. It ignores the envelope's claimed event type, time, account and amount. A fresh Apple API lookup determines current revocation state. SQL processes that state by transaction, with Apple's returned `signedDate` ordering. Refunds before delivery leave an uncredited tombstone. Full refunds debit once; a full refund reversal restores previously delivered Sparks once. If refunded units have already been spent by a future spending feature, a separate refund adjustment is offset by later credits. Sandbox never affects production entitlements.

**Supported refund scope:** legacy full revocations and explicit `REFUND_FULL`/100% revocations. Apple proportional refunds and unknown revocation types return `503 unsupported_refund_state` for investigation rather than incorrectly deducting a full pack. Automatic proportional accounting is not implemented. No consumption-history response, refund-request UI or reconciliation scheduler is included. A notification without transaction data, such as Apple's test notification, returns 400 and cannot prove the transaction flow; verify it separately from a real Sandbox purchase/refund.

Both functions use `verify_jwt = false` at the gateway. The purchase handler performs its own mandatory Supabase Auth verification; the notification handler requires its separate admission token and establishes transaction facts through the Apple API lookup. A publishable key or forged JWT cannot credit a wallet. No service-role key or Apple private key is bundled in the app or committed to source.

## Apple configuration checklist
The user currently has no Apple Developer account. Complete these steps later; no credential was invented or requested in chat:

1. Confirm the real production bundle ID and Apple app, configure native Apple login and Supabase Apple provider, and complete the applicable App Store Connect agreements.
2. Create **consumable** in-app purchase products for the catalog. Enter the actual registered product IDs in `public.spark_packs.store_product_id`; enable only the intended rows. Do not reuse the unrelated legacy configuration's product IDs without verifying the actual Apple app.
3. Create an App Store Server API/In-App Purchase key and add the following **Supabase Edge Function secrets through the dashboard**, never to the repository or chat:
   - `APPLE_IAP_ISSUER_ID`: the key issuer UUID.
   - `APPLE_IAP_KEY_ID`: the ten-character key ID.
   - `APPLE_IAP_PRIVATE_KEY`: the actual PKCS8 PEM with real line breaks.
   - `APPLE_IAP_NOTIFICATION_TOKEN`: a random base64url secret of at least 32 bytes (43 characters). Generate it locally when configuring the actual account; never paste it in chat. It gates notification admission before Apple quota is used.
   Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` automatically on the server. Do not copy their values into native configuration.
4. Set `private.payment_settings.bundle_id` to the confirmed app bundle ID. `app_apple_id` is optional positive numeric metadata for this HTTPS API path. For Sandbox, set `allow_sandbox = true`, `store_environment = 'Sandbox'`. Keep production checkout disabled until there is a usable Sparks spending feature and Sandbox checks pass. The current development bundle is not a confirmed release identity.
5. Set the App Store Server Notifications **V2** URLs to the deployed `apple-payment-notifications?token=<the notification secret>` URL in the appropriate App Store Connect fields. Treat the complete URL as a secret: do not log or copy it into source, and rotate the server secret and App Store Connect URL together if exposed. Keep Sandbox allowed while testing its callbacks. Never point this app at another project's function.
6. After explicit native test authorization, use a real Sandbox tester to check cancellation, pending approval, completed purchase, network loss after payment, app restart retry, account switch, duplicate delivery and refund/reversal. Xcode-local StoreKit transactions are not accepted by the live backend. Do not label consumables as restorable purchases: retry unfinished deliveries instead.
7. Switch `store_environment` to `Production` for the release configuration, ensure production product availability and enable checkout only after end-to-end verification. Leaving purchase availability off still permits delivery of a paid transaction when its environment is selected and verification configuration remains available.

## Verification commands and limits

`tests/payments.sql` and `tests/core_permissions.sql` run as rollback-only synthetic fixtures on the authorized project. They prove database boundaries and accounting behavior, not an Apple signature, Apple login, real payment or concurrent multi-connection race.

The `.mjs` tests use existing Node and ephemeral signing keys, mocked HTTP and mocked service boundaries. They test actual WebCrypto signing, fixed destinations, failed Auth, malformed requests, ownership/environment checks, current Apple-state-only reconciliation and response acknowledgement. They do not call Apple with a real key. Native `PaymentStoreTests.swift` is source coverage only until XCTest execution is authorized. The static project verifier checks metadata and Swift grammar for Release/Debug/Preview; it does not type-check, compile or launch.

Official references checked on 2026-11-03: [Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info), [API authorization JWT](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests), [appAccountToken](https://developer.apple.com/documentation/storekit/transaction/appaccounttoken), [unfinished transactions](https://developer.apple.com/documentation/storekit/transaction/unfinished), [verification JWS](https://developer.apple.com/documentation/storekit/verificationresult/jwsrepresentation-21vgo). Runtime issue evidence: [Supabase Edge X509 issue](https://github.com/supabase/edge-runtime/issues/761). The use of direct HTTPS provenance is an implementation decision; Apple does not endorse skipping independent JWS verification in these references.

## Local Xcode test follow-up,2026-11-04

A separate **FLTiyaStoreKitTesting** Debug scheme now selects a local-only repository and `StoreKit/FLTiya.storekit`. It uses real development Auth for account selection but no Supabase payment delivery or wallet mutation. Local product IDs and balances cannot substitute for registered Apple products, Apple server verification or real Sandbox/Production testing. See [setup and limits](../StoreKit/README.md). The assistant did not build or execute the native flow.
