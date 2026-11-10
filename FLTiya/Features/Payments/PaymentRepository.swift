import Foundation
import Supabase

@MainActor
protocol PaymentRepository {
    var isLocalStoreKitTesting: Bool { get }
    func loadState(for userID: UUID) async throws -> PaymentState
    func deliver(transaction: PaymentTransaction, for userID: UUID) async throws -> PaymentAcknowledgement
}

extension PaymentRepository {
    var isLocalStoreKitTesting: Bool { false }
}

enum PaymentFailure: Error {
    case accountChanged, invalidResponse, productUnavailable
}

@MainActor
final class SupabasePaymentRepository: PaymentRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func loadState(for userID: UUID) async throws -> PaymentState {
        try requireUser(userID)
        let state: PaymentState = try await client.rpc("payment_state").execute().value
        try requireUser(userID)
        guard state.environment != .xcode else { throw PaymentFailure.invalidResponse }
        return state
    }

    func deliver(transaction: PaymentTransaction, for userID: UUID) async throws -> PaymentAcknowledgement {
        struct Receipt: Encodable { let signed_transaction: String }
        try requireUser(userID)
        // Local test JWS must never enter the live verification endpoint, even
        // if a caller or launch configuration selected the wrong repository.
        guard Self.permitsServerDelivery(transaction) else { throw PaymentFailure.invalidResponse }
        // SupabaseClient.functions uses the same SDK session and refresh path
        // as RPC. The server checks the live actor and queries Apple directly.
        let response: PaymentAcknowledgement = try await client.functions.invoke(
            "verify-apple-purchase", options: FunctionInvokeOptions(
                body: Receipt(signed_transaction: transaction.signedTransaction), timeoutInterval: 45
            )
        )
        try requireUser(userID)
        return response
    }

    static func permitsServerDelivery(_ transaction: PaymentTransaction) -> Bool {
        [PaymentEnvironment.production.rawValue, PaymentEnvironment.sandbox.rawValue].contains(transaction.environment)
            && !transaction.productID.hasPrefix("com.fltiya.local.")
    }

    private func requireUser(_ userID: UUID) throws {
        guard client.auth.currentUser?.id == userID else { throw PaymentFailure.accountChanged }
    }
}
