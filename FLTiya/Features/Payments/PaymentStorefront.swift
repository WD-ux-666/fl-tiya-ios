import Foundation
import StoreKit

@MainActor
protocol PaymentStorefront {
    func loadProducts(ids: Set<String>) async throws -> [PaymentProduct]
    func purchase(productID: String, accountToken: UUID) async throws -> PaymentPurchaseResult
    func unfinishedTransactions() async -> [PaymentTransactionEvent]
    func transactionUpdates() -> AsyncStream<PaymentTransactionEvent>
}

@MainActor
final class StoreKitPaymentStorefront: PaymentStorefront {
    private var products: [String: Product] = [:]
    private var loadID = UUID()

    func loadProducts(ids: Set<String>) async throws -> [PaymentProduct] {
        products = [:]
        let request = UUID()
        loadID = request
        let loaded = try await Product.products(for: ids)
        guard loadID == request, !Task.isCancelled else { throw CancellationError() }
        var result: [PaymentProduct] = []
        for product in loaded where ids.contains(product.id) {
            products[product.id] = product
            result.append(PaymentProduct(id: product.id, displayPrice: product.displayPrice,
                isConsumable: product.type == .consumable))
        }
        return result
    }

    func purchase(productID: String, accountToken: UUID) async throws -> PaymentPurchaseResult {
        guard let product = products[productID], product.type == .consumable else {
            throw PaymentFailure.productUnavailable
        }
        switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
        case .success(let result): return .transaction(Self.event(result))
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw PaymentFailure.productUnavailable
        }
    }

    func unfinishedTransactions() async -> [PaymentTransactionEvent] {
        var events: [PaymentTransactionEvent] = []
        for await result in Transaction.unfinished {
            guard !Task.isCancelled else { break }
            events.append(Self.event(result))
        }
        return events
    }

    func transactionUpdates() -> AsyncStream<PaymentTransactionEvent> {
        AsyncStream { continuation in
            let observer = Task { @MainActor in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    continuation.yield(Self.event(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in observer.cancel() }
        }
    }

    private static func event(_ result: VerificationResult<Transaction>) -> PaymentTransactionEvent {
        guard case .verified(let transaction) = result else { return .unverified }
        let environment: String
        // Internal wire names are stable; Apple's typed environment constants
        // select them without assuming the SDK's raw string casing.
        if transaction.environment == .xcode { environment = PaymentEnvironment.xcode.rawValue }
        else if transaction.environment == .sandbox { environment = PaymentEnvironment.sandbox.rawValue }
        else if transaction.environment == .production { environment = PaymentEnvironment.production.rawValue }
        else { environment = "Unsupported" }
        return .verified(PaymentTransaction(id: String(transaction.id), productID: transaction.productID,
            accountToken: transaction.appAccountToken, environment: environment,
            isConsumable: transaction.productType == .consumable, quantity: transaction.purchasedQuantity,
            signedTransaction: result.jwsRepresentation, revocationDate: transaction.revocationDate,
            finish: { await transaction.finish() }))
    }
}
