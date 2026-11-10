import Foundation
import Observation
import SwiftUI

/// App lifetime owner of verified wallet state and StoreKit delivery. UI state
/// stays on the main actor; the SDKs perform their asynchronous network work.
@MainActor
@Observable
final class PaymentStore {
    private(set) var wallet: SparksWallet?
    private(set) var environment: PaymentEnvironment?
    private(set) var packs: [SparksPack] = []
    private(set) var history: [SparksActivity] = []
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRetrying = false
    private(set) var errorMessage: String?
    private(set) var purchaseStatus: PaymentPurchaseStatus = .idle
    private(set) var purchasesEnabled = false
    private(set) var purchaseUnavailableReason: String?
    var isLocalStoreKitTesting: Bool { repository.isLocalStoreKitTesting }
    private var products: [String: PaymentProduct] = [:]

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let storefront: any PaymentStorefront
    @ObservationIgnored private let verifiedUserID: () -> UUID?
    @ObservationIgnored private var userID: UUID?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var walletRevision = 0
    @ObservationIgnored private var deliveryIDs: Set<String> = []
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var deliveryTail: Task<Void, Never>?
    @ObservationIgnored private var deliveryTailID: UUID?

    init(repository: any PaymentRepository, storefront: any PaymentStorefront,
         verifiedUserID: @escaping () -> UUID?) {
        self.repository = repository
        self.storefront = storefront
        self.verifiedUserID = verifiedUserID
    }

    deinit { observer?.cancel() }

    func setUserID(_ verifiedID: String?) {
        let id = verifiedID.flatMap(UUID.init(uuidString:))
        guard id != userID else { return }
        generation = UUID()
        loadID = UUID()
        userID = id
        wallet = nil
        environment = nil
        packs = []
        history = []
        products = [:]
        purchasesEnabled = false
        purchaseUnavailableReason = nil
        isLoading = false
        isPurchasing = false
        isRetrying = false
        errorMessage = nil
        purchaseStatus = .idle
        walletRevision += 1
    }

    func startObserving() {
        guard observer == nil else { return }
        let stream = storefront.transactionUpdates()
        observer = Task { @MainActor [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.deliver(event)
                // An update can arrive before the first wallet load supplies
                // its environment. The winning load must then retry delivery.
                await self?.refreshAndRetry()
            }
        }
    }

    func refreshAndRetry() async {
        await refresh()
        await retryUnfinished()
    }

    func refresh() async {
        guard let userID, verifiedUserID() == userID else { return }
        let expectedGeneration = generation
        let request = UUID()
        let revision = walletRevision
        loadID = request
        isLoading = true
        purchasesEnabled = false
        errorMessage = nil
        defer { if loadID == request { isLoading = false } }
        do {
            let state = try await repository.loadState(for: userID)
            guard isCurrent(userID, expectedGeneration), loadID == request,
                  revision == walletRevision, !Task.isCancelled else { return }
            guard state.wallet.isValid,
                  Set(state.packs.map(\.id)).count == state.packs.count,
                  state.packs.allSatisfy({ $0.sparks > 0 }) else { throw PaymentFailure.invalidResponse }
            wallet = state.wallet
            environment = state.environment
            packs = state.packs.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
            history = state.history
            purchaseUnavailableReason = state.purchaseUnavailableReason
            products = [:]
            // Only active, unambiguous server product mappings are purchasable.
            let ids = Set(state.packs.filter(\.isActive).compactMap(\.storeProductID).filter { !$0.isEmpty })
            if !ids.isEmpty {
                let loaded = try await storefront.loadProducts(ids: ids)
                guard isCurrent(userID, expectedGeneration), loadID == request,
                      revision == walletRevision, !Task.isCancelled else { return }
                for product in loaded where ids.contains(product.id) && product.isConsumable {
                    guard state.packs.filter({ $0.storeProductID == product.id }).count == 1 else { continue }
                    products[product.id] = product
                }
            }
            purchasesEnabled = state.purchasesEnabled
        } catch {
            guard isCurrent(userID, expectedGeneration), loadID == request, !Task.isCancelled else { return }
            products = [:]
            purchasesEnabled = false
            errorMessage = "We couldn't refresh Sparks. Check your connection and try again."
        }
    }

    func price(for pack: SparksPack) -> String? {
        guard let id = pack.storeProductID else { return nil }
        return products[id]?.displayPrice
    }

    func canPurchase(_ pack: SparksPack) -> Bool {
        guard let userID, verifiedUserID() == userID, purchasesEnabled, wallet != nil,
              !isLoading, !isPurchasing, !isRetrying, pack.isActive,
              packs.contains(pack), let id = pack.storeProductID else { return false }
        return products[id]?.isConsumable == true
    }

    func purchase(_ pack: SparksPack) async {
        guard canPurchase(pack), let userID, let productID = pack.storeProductID else { return }
        let expectedGeneration = generation
        isPurchasing = true
        purchaseStatus = .idle
        defer { if generation == expectedGeneration { isPurchasing = false } }
        do {
            let result = try await storefront.purchase(productID: productID, accountToken: userID)
            guard isCurrent(userID, expectedGeneration), !Task.isCancelled else { return }
            switch result {
            case .cancelled: purchaseStatus = .cancelled
            case .pending: purchaseStatus = .pendingApproval
            case .transaction(let event):
                await deliver(event)
                if isCurrent(userID, expectedGeneration) { await refresh() }
            }
        } catch is CancellationError {
            // A possibly paid transaction stays in StoreKit's unfinished queue.
            if isCurrent(userID, expectedGeneration) { purchaseStatus = .deliveryPending }
        } catch {
            if isCurrent(userID, expectedGeneration) { purchaseStatus = .failed }
        }
    }

    func retryUnfinished() async {
        guard let userID, verifiedUserID() == userID, environment != nil, !isRetrying else { return }
        let expectedGeneration = generation
        isRetrying = true
        defer { if generation == expectedGeneration { isRetrying = false } }
        let events = await storefront.unfinishedTransactions()
        guard isCurrent(userID, expectedGeneration), !Task.isCancelled else { return }
        for event in events {
            guard isCurrent(userID, expectedGeneration), !Task.isCancelled else { return }
            await deliver(event)
        }
        if !events.isEmpty, isCurrent(userID, expectedGeneration) { await refresh() }
    }

    private func deliver(_ event: PaymentTransactionEvent) async {
        // Serialize distinct deliveries as well as duplicate IDs. Otherwise a
        // slower, older response could replace a more recent wallet snapshot.
        let predecessor = deliveryTail
        let operationID = UUID()
        let operation = Task { @MainActor [weak self] in
            await predecessor?.value
            guard !Task.isCancelled else { return }
            await self?.performDelivery(event)
        }
        deliveryTail = operation
        deliveryTailID = operationID
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        if deliveryTailID == operationID {
            deliveryTail = nil
            deliveryTailID = nil
        }
    }

    private func performDelivery(_ event: PaymentTransactionEvent) async {
        guard let userID, verifiedUserID() == userID, let environment else { return }
        guard case .verified(let transaction) = event else {
            purchaseStatus = .verificationFailed
            return
        }
        // Retired products can still be delivered: the server owns catalog
        // eligibility. Never acknowledge a different app account or environment.
        guard transaction.accountToken == userID else { return }
        guard transaction.environment == environment.rawValue,
              transaction.isConsumable, transaction.quantity == 1,
              !transaction.id.isEmpty, !transaction.signedTransaction.isEmpty else {
            purchaseStatus = .verificationFailed
            return
        }
        let expectedGeneration = generation
        let key = "\(expectedGeneration.uuidString):\(environment.rawValue):\(transaction.id)"
        guard deliveryIDs.insert(key).inserted else { return }
        defer { deliveryIDs.remove(key) }
        do {
            let acknowledgement = try await repository.deliver(transaction: transaction, for: userID)
            guard isCurrent(userID, expectedGeneration), !Task.isCancelled else { return }
            guard acknowledgement.transactionID == transaction.id,
                  acknowledgement.environment == environment, self.environment == environment,
                  acknowledgement.creditedSparks >= 0, acknowledgement.wallet.isValid else {
                throw PaymentFailure.invalidResponse
            }
            walletRevision += 1
            wallet = acknowledgement.wallet
            purchaseStatus = .delivered(acknowledgement.disposition)
            // This is the sole finish path: a matching durable repository
            // acknowledgement (server or explicitly local test journal) is
            // required before acknowledging delivery, including refunded rows.
            await transaction.finish()
        } catch {
            guard isCurrent(userID, expectedGeneration), !Task.isCancelled else { return }
            purchaseStatus = .deliveryPending
        }
    }

    private func isCurrent(_ id: UUID, _ expectedGeneration: UUID) -> Bool {
        generation == expectedGeneration && userID == id && verifiedUserID() == id
    }
}

private struct PaymentStoreKey: EnvironmentKey {
    static let defaultValue: PaymentStore? = nil
}

extension EnvironmentValues {
    var paymentStore: PaymentStore? {
        get { self[PaymentStoreKey.self] }
        set { self[PaymentStoreKey.self] = newValue }
    }
}
