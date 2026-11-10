import Foundation

enum PaymentEnvironment: String, Decodable, Sendable {
    case production = "Production"
    case sandbox = "Sandbox"
    case xcode = "Xcode"
}

struct SparksWallet: Decodable, Equatable, Sendable {
    let sparks: Int64
    let refundDebtSparks: Int64
    var isValid: Bool { sparks >= 0 && refundDebtSparks >= 0 }
    enum CodingKeys: String, CodingKey {
        case sparks
        case refundDebtSparks = "refund_debt_sparks"
    }
}

struct SparksPack: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let sparks: Int64
    let storeProductID: String?
    let isActive: Bool
    let referencePriceUSD: String
    let sortOrder: Int
    enum CodingKeys: String, CodingKey {
        case id, name, sparks
        case storeProductID = "store_product_id", isActive = "is_active"
        case referencePriceUSD = "reference_price_usd", sortOrder = "sort_order"
    }

    // An offline catalog communicates the agreed draft only. It never supplies
    // a product identifier, purchasable product, wallet or authenticated user.
    static let draftPacks: [SparksPack] = zip(
        [400, 800, 2450, 5150, 10800, 16800, 29400, 42700, 63700] as [Int64],
        ["0.99", "1.99", "4.99", "9.99", "19.99", "29.99", "49.99", "69.99", "99.99"]
    ).enumerated().map { index, pair in
        SparksPack(id: "draft_\(pair.0)", name: "\(pair.0) Sparks", sparks: pair.0,
            storeProductID: nil, isActive: false, referencePriceUSD: pair.1, sortOrder: index)
    }
}

struct SparksActivity: Decodable, Identifiable, Sendable {
    let id: UUID
    let delta: Int64
    let reason: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, delta, reason
        case createdAt = "created_at"
    }

    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt)
    }

    var title: String {
        switch reason {
        case "storekit_recharge": "Sparks purchase"
        case "storekit_refund": "Purchase refund"
        case "storekit_refund_reversal": "Refund reversed"
        case "local_storekit_recharge": "Local test purchase"
        case "local_storekit_refund": "Local test refund"
        default: "Wallet adjustment"
        }
    }
}

struct PaymentState: Decodable, Sendable {
    let environment: PaymentEnvironment
    let purchasesEnabled: Bool
    let wallet: SparksWallet
    let packs: [SparksPack]
    let history: [SparksActivity]
    var purchaseUnavailableReason: String? = nil
    enum CodingKeys: String, CodingKey {
        case environment, wallet, packs, history
        case purchasesEnabled = "purchases_enabled"
        case purchaseUnavailableReason = "purchase_unavailable_reason"
    }
}

enum PaymentDisposition: String, Decodable, Sendable {
    case credited
    case alreadyCredited = "already_credited"
    case refunded
}

struct PaymentAcknowledgement: Decodable, Sendable {
    let environment: PaymentEnvironment
    let transactionID: String
    let disposition: PaymentDisposition
    let creditedSparks: Int64
    let wallet: SparksWallet
    enum CodingKeys: String, CodingKey {
        case environment, disposition, wallet
        case transactionID = "transaction_id", creditedSparks = "credited_sparks"
    }
}

struct PaymentProduct: Sendable {
    let id: String
    let displayPrice: String
    let isConsumable: Bool
}

struct PaymentTransaction: Sendable {
    let id: String
    let productID: String
    let accountToken: UUID?
    let environment: String
    let isConsumable: Bool
    let quantity: Int
    // Transient JWS: never persisted or logged by the client.
    let signedTransaction: String
    let revocationDate: Date?
    let finish: @MainActor @Sendable () async -> Void

    init(id: String, productID: String, accountToken: UUID?, environment: String,
         isConsumable: Bool, quantity: Int, signedTransaction: String,
         revocationDate: Date? = nil, finish: @escaping @MainActor @Sendable () async -> Void) {
        self.id = id
        self.productID = productID
        self.accountToken = accountToken
        self.environment = environment
        self.isConsumable = isConsumable
        self.quantity = quantity
        self.signedTransaction = signedTransaction
        self.revocationDate = revocationDate
        self.finish = finish
    }
}

enum PaymentTransactionEvent: Sendable {
    case verified(PaymentTransaction)
    case unverified
}

enum PaymentPurchaseResult: Sendable {
    case transaction(PaymentTransactionEvent)
    case pending
    case cancelled
}

enum PaymentPurchaseStatus: Equatable {
    case idle, pendingApproval, cancelled, verificationFailed, deliveryPending, unavailable, failed
    case delivered(PaymentDisposition)

    var message: String? {
        switch self {
        case .idle, .cancelled: nil
        case .pendingApproval: "Your purchase is awaiting App Store approval. Sparks will arrive after approval and verification."
        case .verificationFailed: "We couldn't verify this purchase. No Sparks have been added. Please try again later."
        case .deliveryPending: "Your purchase hasn't been confirmed yet. Retry delivery to check it safely; you won't be charged again."
        case .unavailable: "This pack is currently unavailable. Refresh and try again later."
        case .failed: "The App Store couldn't complete the purchase. Please try again."
        case .delivered(.credited): "Your purchase was verified and your wallet is updated."
        case .delivered(.alreadyCredited): "This purchase was already delivered. Your wallet is up to date."
        case .delivered(.refunded): "This purchase was refunded. No Sparks were added."
        }
    }
}
