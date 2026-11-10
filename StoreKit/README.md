# Local StoreKit Testing

## Run it yourself in Xcode

1. Open `FLTiya.xcodeproj`. Select **FLTiya** in the scheme selector beside the Run button, then choose an iPhone simulator.
2. Stop the currently running app and Run again from Xcode. Debug Run enables `StoreKit/FLTiya.storekit` and the local-testing launch flag. Opening the existing app from the simulator Home Screen does not apply the Xcode launch settings.
3. Keep the current signed-in account, or accept the agreements and choose **One-tap sign in**. The local wallet uses the verified TIYA account ID. Social data still uses the hosted backend.
4. Open **Profile > Sparks wallet**. Confirm the wallet shows **Your test Sparks** and the **Local test** badge.
5. Tap the localized price for a pack. Xcode StoreKit should display Apple's local test payment sheet. Cancel to test cancellation; confirm to create an Xcode test transaction.
6. A verified and durably saved local transaction updates only this account's on-device test balance/activity. Buy the 400 pack twice to expect 800 test Sparks. Refresh or reopen the app to check persistence.
7. To test account isolation, repeat with a different account. Each account has its own local test wallet. Signing out of a one-tap account can prevent you from returning to that account.

This change was checked statically. Verify product loading, the payment sheet and the test transaction in Xcode. Test confirmations incur no real charge. The local test does not validate Apple's sandbox or production servers, Supabase purchase verification or real-money delivery.

## Schemes

| Scheme | Auth/social | Sparks |
| --- | --- | --- |
| FLTiya (Run) | Verified hosted account, including one-tap sign-in | Apple local StoreKit sheet and an on-device per-account test wallet |
| FLTiyaStoreKitTesting (Run) | Verified hosted account, including one-tap sign-in | Same local test setup as FLTiya Run |
| FLTiyaPreview | Offline, no real session | Draft catalog, no purchases or wallet |

Archive and Profile always use Release and the hosted wallet. Release ignores the local-testing flag and excludes the local repository implementation. The `.storekit` file is not copied into app resources. When testing the App Store sandbox separately, use a Run configuration without the local StoreKit file and flag.

## If prices or the sheet are missing

- Verify the selected scheme is **FLTiya** or **FLTiyaStoreKitTesting**. Stop the previous app and Run again from Xcode.
- Open **Product > Scheme > Edit Scheme > Run > Options**. The StoreKit Configuration should be **FLTiya.storekit**. The scheme's Run environment contains `FLTIYA_LOCAL_STOREKIT_TESTING=1`.
- The config's **Disable Dialogs** option must stay off. The checked-in file has dialogs enabled and injected purchase/load/verification failures disabled.
- Confirm that sign-in succeeded. The test wallet needs a verified account; the offline preview has no account and cannot open it.
- Pull to refresh on Sparks. If no localized test prices load, do not enable hosted packs or change server balances as a workaround.

## Data boundaries

Nine dedicated IDs `com.fltiya.local.sparks.<amount>` match the existing agreed pack sizes and reference USD prices. They are local test products, not App Store Connect registrations. Local code uses StoreKit's verified transaction facts, the exact app account token, Xcode environment, consumable type and quantity. Replayed transactions do not add credit twice. A failure before the journal's atomic commit does not grant credit or finish the transaction; delivery can retry. File-permission hardening after that commit is best-effort and cannot turn a successful commit into a reported delivery failure.

An observed full revocation removes the corresponding local credit once. Replayed older callbacks cannot restore it. Historical refunds that occurred while the app was closed, partial refunds and refund reversals are not reconciled by this local harness. Do not treat it as complete refund testing.

The on-device journal contains only account UUIDs, transaction/product facts and test activity. It stores no Auth token, access code or raw signed transaction. It is separate from Supabase wallets and ledgers. Clearing/reinstalling app data can remove this local journal; local test balances are not cloud-synced. No reset button is provided because clearing a delivery journal independently of StoreKit history can cause test transactions to be replayed.

## References and configuration evidence

The scheme path syntax and consumable JSON shape follow [Apple's StoreKit sample](https://docs-assets.developer.apple.com/published/623bce0ddaba/ImplementingAStoreInYourAppUsingTheStoreKitAPI.zip). `../../StoreKit/FLTiya.storekit` follows the sample's relative path structure. Configuration JSON version 6.3, dialogs enabled and nine consumables are checked statically. Xcode loading is unverified until the user runs it.

See [Apple setup](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode) and [testing environments](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox).
