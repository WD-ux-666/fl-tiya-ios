# Settings, account deletion and privacy

Scope: `/Users/shangbao666/Desktop/fl-tiya-ios-main/fl-tiya-ios`, updated 2026-11-10.
Authorized hosted project: `gpstwmffctwqlcakmvgw` (FL-Tiya, tely).

## Settings

The gear, Privacy Policy and Support icons are original illustrated arcade stickers. The About route is removed; the small version footer remains. Support uses the supplied `fltiya.support@gmail.com` email and opens the device mail app. Delivery to that mailbox has not been tested.

## Permanent self-deletion

**Profile > Settings > Delete Account** opens an explicit destructive confirmation. This supports device accounts, previously confirmed email/password accounts, and reserved development accounts. Preview does not simulate a successful server deletion. Sign Out remains a separate action.

The Edge handler accepts only authenticated `POST {}`. It checks the Auth user and a real current server session; no body field can select another account. Service-only RPCs validate account cohort, anonymous AMR where required and account state. They deny business access and new uploads, stop active calls, revoke other sessions, and preserve the deletion driver for retry. Owned media is removed through the Storage API before the final checked transaction deletes Auth and cascading profile, game-card, social, messaging and uploaded-content rows.

Development access codes are permanently disabled, with a reservation tombstone preventing the same reserved identity from being recreated. In particular, deleting Development Alpha removes its owned feed videos. Use a newly created disposable device account for a manual deletion walkthrough, rather than a shared content account.

Financial uniqueness/audit records remain with their user association removed by existing foreign-key rules. Minimal call/RTC cleanup metadata and retired development reservations remain separately. Copies already retrieved into devices or provider caches can persist until expiry. In the live fixture, a fresh deleted-image request was denied immediately; a warmed URL returned cached content before invalidation, then was denied within the observation window. This is not immediate deletion from every cache.

A failure keeps a UUID-only local deletion intent. Retry resumes only for that same verified account. A missing/invalid session is never reported as proof of successful deletion; the recovery screen offers **Try Again** and **Sign in again** to clear local credentials explicitly. Linked Apple accounts are refused before destructive changes until secure Apple authorization revocation is configured. Apple sign-in remains disabled.

Migration: `20261106060045_self_service_account_deletion.sql`.
Confirmed password-account access and self-deletion were added by `20261109075147_verified_email_password_accounts.sql`.
New endpoint: `delete-account` version 1. Anonymous-only compatibility endpoint: `delete-experience-account` version 2.

## Hosted policy and agreement drafts

- [Readable policy](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy)
- [Privacy Policy JSON](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy?format=json)
- [Document index JSON](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy/documents) returns both current PDF URLs and document versions.
- [Privacy Policy PDF](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy/privacy-policy.pdf) and [User Agreement PDF](https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy/user-agreement.pdf)
- Both PDFs are version `2026-11-09-draft-2`, deployed on the public Edge function version 5. Canonical text is in `FLTiya/Resources/PrivacyPolicy.json` and `FLTiya/Resources/UserAgreement.json`.
- To regenerate, run `python3 scripts/generate_legal_pdfs.py` and then `python3 scripts/sync_legal_edge_assets.py`.

The default response is readable plain text, intentionally compatible with the Supabase Edge gateway. GET/HEAD/OPTIONS require no authentication; writes and unsupported format parameters are rejected. The handler accesses no database or environment secrets. The hosting layer was observed to set the `__cf_bm` security cookie; the application handler sets none.

On the login screen and in Settings, either document opens in an in-app WebView. The app fetches the public URL index with no account credentials, validates the returned HTTPS URL against the corresponding PDF route, and uses a WebView with a nonpersistent store and JavaScript disabled. If the index or PDF cannot load, the reader offers **Try again** and **Read app copy**. The offline development preview uses the bundled text without fetching a PDF.

The actual operator, effective date, target regions, age requirements, production retention schedule and international-processing disclosures remain undecided. Publishing the draft does not finalize these legal facts.

## November 9 verification

All eight legal endpoint unit tests and nine anonymous hosted HTTP checks passed. Both PDF responses matched the generated files byte for byte. Hosted password-authorization and self-deletion assertions passed and rolled back. Native Swift sources were type-checked without a build, launch, or test run.

## Earlier November 6 verification

- Three transactional SQL suites passed and rolled back: account deletion, experience accounts and live-development permissions.
- Nineteen Edge tests passed: privacy 6, account deletion 5, compatibility experience handlers 8.
- A fresh anonymous fixture uploaded and read back its own private avatar, rejected unauthenticated/identity-selecting deletion, then deleted itself through the deployed endpoint. Auth and business access were denied afterwards; Storage was removed and cached access expired. Original baseline retained: 3 Auth/profile/active accounts and 10 approved clips; fixture/deleting/avatar-object counts are zero.
- Public policy HTTP checks passed all 9 cases without API keys or sign-in, including exact hosted/bundled JSON equality.
- Static checks: 68 app sources, 11 test sources, 79 Swift grammar files in Release/Debug/Preview, 43 asset JSON files, one bundled policy JSON, project references/schemes/resources valid.
- Security advisors were reviewed: no new migration-specific finding; existing anonymous-access notices reflect intentionally supported server-verified device accounts, private no-policy tables deny direct access, and leaked-password protection remains an external setting for password-based authentication.

No native build, typecheck, XCTest, app launch or Simulator run was performed for this increment. In Xcode, manually inspect the Settings artwork, open Support, open the policy online/offline, cancel deletion, and finally delete only a disposable account. Apple-linked deletion and two-device RTC still depend on their external configurations.

Repeatable hosted checks: `python3 scripts/verify_privacy_policy.py` (read-only), and `python3 scripts/verify_account_deletion.py` (creates and deletes only its own new fixture). Evidence and source hashes are under `.planning/2026-11-03-supabase-backend/`.
