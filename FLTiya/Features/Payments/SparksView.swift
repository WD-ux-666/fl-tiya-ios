import SwiftUI

@MainActor
struct SparksView: View {
    @Environment(\.paymentStore) private var store
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]
    private var packs: [SparksPack] { store?.packs ?? SparksPack.draftPacks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GameHeroHeader(eyebrow: "SPARKS VAULT", title: "A little extra spark.",
                    subtitle: "Your wallet, packs and purchase activity in one place.", symbol: "sparkles")
                wallet
                feedback
                catalog
                if store != nil { activity }
            }
            .padding(20)
        }
        .background { AppBackdrop() }
        .navigationTitle("Sparks")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store?.refreshAndRetry() }
        .refreshable { await store?.refreshAndRetry() }
        .toolbar {
            if let store {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAndRetry() }
                    } label: {
                        GameGlyph(symbol: "arrow.clockwise", size: 22).frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(store.isLoading || store.isRetrying)
                    .accessibilityLabel("Refresh Sparks")
                }
            }
        }
    }

    private var wallet: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WALLET BALANCE").font(.caption2.weight(.heavy)).tracking(2)
                            .foregroundStyle(AppTheme.secondaryInk)
                        Text(store?.isLocalStoreKitTesting == true ? "Your test Sparks" : "Your Sparks")
                            .font(.headline).foregroundStyle(AppTheme.accent)
                    }
                    Spacer()
                    ArcadeSticker(kind: .sparks, size: 58)
                        .accessibilityHidden(true)
                }
                if store?.isLocalStoreKitTesting == true || store?.environment == .sandbox {
                    Text(store?.isLocalStoreKitTesting == true ? "Local test" : "Sandbox")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.violet)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(AppTheme.accentSoft, in: Capsule())
                }
                if let wallet = store?.wallet {
                    Text(wallet.sparks.formatted())
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy)).foregroundStyle(AppTheme.ink)
                        .monospacedDigit()
                        .accessibilityLabel("\(wallet.sparks.formatted()) Sparks available")
                    if wallet.refundDebtSparks > 0 {
                        Text("Refund adjustment: \(wallet.refundDebtSparks.formatted()) Sparks. Future credits first cover this adjustment.")
                            .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                    }
                } else {
                    Text("Balance unavailable")
                        .font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
                }
                if store?.isLocalStoreKitTesting == true {
                    Text("Each account has its own test balance on this device.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                } else if store?.environment == .sandbox {
                    Text("Test purchases and test Sparks are separate from your live wallet.")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                } else if store == nil {
                    Text("Offline preview · No live balance or purchases")
                        .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
                }
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let store {
            VStack(alignment: .leading, spacing: 12) {
                if store.isLoading || store.isRetrying {
                    HStack(spacing: 10) {
                        ProgressView().tint(AppTheme.accent)
                        Text(store.isRetrying ? "Checking unfinished purchases…" : "Refreshing Sparks…")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    }
                } else if store.isPurchasing {
                    HStack(spacing: 10) {
                        ProgressView().tint(AppTheme.accent)
                        Text("Confirming purchase…")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                if let error = store.errorMessage {
                    Text(error).font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                }
                if let message = store.purchaseStatus.message {
                    Text(message)
                        .font(.subheadline).foregroundStyle(AppTheme.ink)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("Retry purchase delivery") {
                    Task { await store.refreshAndRetry() }
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoading || store.isRetrying || store.isPurchasing)
                Text("Checks existing purchases without starting a new charge.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: 14) {
            SocialSectionHeading(title: store == nil ? "Draft Sparks packs" : "Get Sparks", symbol: "sparkles")
            if let store, !store.purchasesEnabled, !store.isLoading {
                Text(store.purchaseUnavailableReason == "experience_account"
                     ? "Purchases aren't available for device accounts. Pack amounts and reference USD prices are shown for information."
                     : "Purchases are not available yet. Pack amounts and reference USD prices are shown for information.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            } else if store == nil {
                Text("Draft USD prices are references. Live purchases will show your App Store's localized price.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(packs) { pack in
                    SparksPackCard(pack: pack, price: store?.price(for: pack),
                        canPurchase: store?.canPurchase(pack) ?? false) {
                        Task { await store?.purchase(pack) }
                    }
                }
            }
            if let store, store.isLocalStoreKitTesting, !store.isLoading,
               store.packs.contains(where: { store.price(for: $0) == nil }) {
                Text("Test prices are missing. Run TIYA from Xcode with its StoreKit configuration enabled.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            }
            if let store, store.packs.isEmpty, !store.isLoading {
                Text("No Sparks packs are available right now.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            }
            Text(store?.isLocalStoreKitTesting == true
                ? "Confirm a purchase in Apple's local test payment sheet. Only verified Xcode test transactions can add test Sparks."
                : "Sparks are virtual items for TIYA. Purchases use your Apple Account and are delivered after verification.")
                .font(.footnote).foregroundStyle(AppTheme.secondaryInk)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SocialSectionHeading(title: "Recent activity", symbol: "clock.arrow.circlepath")
            if let store, store.wallet != nil {
                if store.history.isEmpty {
                    Text("No Sparks activity yet.").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                } else {
                    AppCard {
                        VStack(spacing: 16) {
                            ForEach(store.history) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.title).font(.subheadline.weight(.semibold))
                                        if let date = entry.date {
                                            Text(date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                                .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Text(entry.delta > 0 ? "+\(entry.delta.formatted())" : entry.delta.formatted())
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                }
                                .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }
            } else {
                Text("Activity will appear when your wallet is available.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
            }
        }
    }
}

private struct SparksPackCard: View {
    let pack: SparksPack
    let price: String?
    let canPurchase: Bool
    let purchase: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                ArcadeSticker(kind: .sparks, size: 58)
                    .accessibilityHidden(true)
                Text(pack.sparks.formatted())
                    .font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
                Text("Sparks").font(.subheadline).foregroundStyle(AppTheme.secondaryInk)
                if let price {
                    Button(action: purchase) {
                        Text(price).font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.onAccent)
                    .disabled(!canPurchase)
                    .accessibilityLabel("Buy \(pack.sparks.formatted()) Sparks for \(price)")
                } else {
                    Text("Reference USD $\(pack.referencePriceUSD)")
                        .font(.caption).foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Unavailable").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Offline Sparks draft") {
    NavigationStack { SparksView() }.tint(AppTheme.accent)
}
