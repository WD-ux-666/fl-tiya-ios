import Foundation

#if DEBUG && !DEVELOPMENT_PREVIEW
enum LocalStoreKitTestingConfiguration {
    static var isEnabled: Bool { isEnabled(environment: ProcessInfo.processInfo.environment) }

    static func isEnabled(environment: [String: String]) -> Bool {
        environment["FLTIYA_LOCAL_STOREKIT_TESTING"] == "1"
    }

    static let packs: [SparksPack] = SparksPack.draftPacks.map { draft in
        SparksPack(id: "local_\(draft.sparks)", name: draft.name, sparks: draft.sparks,
            storeProductID: "com.fltiya.local.sparks.\(draft.sparks)", isActive: true,
            referencePriceUSD: draft.referencePriceUSD, sortOrder: draft.sortOrder)
    }
}

@MainActor
protocol LocalStoreKitJournalStorage: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// On-device test data only. No receipt, session, credential or server wallet is
/// persisted here. Atomic replacement precedes the acknowledgement/finish path.
@MainActor
final class LocalStoreKitFileJournal: LocalStoreKitJournalStorage {
    private let directory: URL?
    private var file: URL? { directory?.appendingPathComponent("wallets-v1.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first?.appendingPathComponent("LocalStoreKitTesting", isDirectory: true)
    }

    func read() throws -> Data? {
        guard let file else { throw CocoaError(.fileReadUnknown) }
        do { return try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
    }

    func write(_ data: Data) throws {
        guard let directory, let file else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        // Atomic replacement is the commit point. Permission hardening cannot
        // roll that commit back or turn its durable credit into a write failure.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// Selected only by the guarded local scheme factory. Its identity closure must
/// return an ID only for the current server-verified account. All operations
/// execute serially on MainActor with no suspension during read/modify/write.
@MainActor
final class LocalStoreKitPaymentRepository: PaymentRepository {
    let isLocalStoreKitTesting = true
    private let verifiedUserID: () -> UUID?
    private let storage: any LocalStoreKitJournalStorage

    init(verifiedUserID: @escaping () -> UUID?, storage: (any LocalStoreKitJournalStorage)? = nil) {
        self.verifiedUserID = verifiedUserID
        self.storage = storage ?? LocalStoreKitFileJournal()
    }

    func loadState(for userID: UUID) async throws -> PaymentState {
        try requireUser(userID)
        let journal = try readJournal()
        let state = try state(for: userID, journal: journal)
        try requireUser(userID)
        return state
    }

    func deliver(transaction: PaymentTransaction, for userID: UUID) async throws -> PaymentAcknowledgement {
        try requireUser(userID)
        guard transaction.accountToken == userID, transaction.environment == PaymentEnvironment.xcode.rawValue,
              transaction.isConsumable, transaction.quantity == 1,
              !transaction.signedTransaction.isEmpty,
              UInt64(transaction.id) != nil, !transaction.id.isEmpty,
              let pack = LocalStoreKitTestingConfiguration.packs.first(where: { $0.storeProductID == transaction.productID }) else {
            throw PaymentFailure.invalidResponse
        }
        var journal = try readJournal()
        let now = timestamp()
        let disposition: PaymentDisposition
        var changed = false
        if var record = journal.transactions[transaction.id] {
            guard record.userID == userID, record.productID == transaction.productID, record.sparks == pack.sparks else {
                throw PaymentFailure.invalidResponse
            }
            if transaction.revocationDate != nil, record.revokedAt == nil {
                record.revokedAt = now
                record.refundActivityID = UUID()
                journal.transactions[transaction.id] = record
                changed = true
            }
            // Local full revocation is monotonic. A stale unrevoked StoreKit
            // callback never restores test credit; refund reversal is not modeled.
            disposition = record.revokedAt == nil ? .alreadyCredited : .refunded
        } else {
            let revoked = transaction.revocationDate != nil
            journal.transactions[transaction.id] = Record(userID: userID, productID: transaction.productID,
                sparks: pack.sparks, creditActivityID: UUID(), creditedAt: revoked ? nil : now,
                refundActivityID: revoked ? UUID() : nil, revokedAt: revoked ? now : nil)
            disposition = revoked ? .refunded : .credited
            changed = true
        }
        // Validate the resulting balance and encode before touching persistent
        // storage. Failed writes leave no cached credited wallet to acknowledge.
        let result = try state(for: userID, journal: journal)
        if changed {
            let data = try JSONEncoder().encode(journal)
            guard data.count <= 8 * 1024 * 1024 else { throw PaymentFailure.invalidResponse }
            try storage.write(data)
        }
        try requireUser(userID)
        return PaymentAcknowledgement(environment: .xcode, transactionID: transaction.id,
            disposition: disposition, creditedSparks: pack.sparks, wallet: result.wallet)
    }

    private struct Journal: Codable {
        var version = 1
        var transactions: [String: Record] = [:]
    }

    private struct Record: Codable {
        let userID: UUID
        let productID: String
        let sparks: Int64
        let creditActivityID: UUID
        let creditedAt: String?
        var refundActivityID: UUID?
        var revokedAt: String?
    }

    private func readJournal() throws -> Journal {
        guard let data = try storage.read() else { return Journal() }
        // Corruption or an unsupported format fails closed; never silently
        // reset transaction IDs, which would permit duplicate local credit.
        guard data.count <= 8 * 1024 * 1024 else { throw PaymentFailure.invalidResponse }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        guard journal.version == 1 else { throw PaymentFailure.invalidResponse }
        for (id, record) in journal.transactions {
            guard UInt64(id) != nil,
                  let pack = LocalStoreKitTestingConfiguration.packs.first(where: { $0.storeProductID == record.productID }),
                  record.sparks == pack.sparks,
                  record.creditedAt != nil || record.revokedAt != nil,
                  (record.revokedAt == nil) == (record.refundActivityID == nil) else {
                throw PaymentFailure.invalidResponse
            }
        }
        return journal
    }

    private func state(for userID: UUID, journal: Journal) throws -> PaymentState {
        var balance: Int64 = 0
        var activity: [SparksActivity] = []
        for record in journal.transactions.values where record.userID == userID {
            if record.creditedAt != nil, record.revokedAt == nil {
                let (sum, overflow) = balance.addingReportingOverflow(record.sparks)
                guard !overflow else { throw PaymentFailure.invalidResponse }
                balance = sum
            }
            if let creditedAt = record.creditedAt {
                activity.append(SparksActivity(id: record.creditActivityID, delta: record.sparks,
                    reason: "local_storekit_recharge", createdAt: creditedAt))
                if let revokedAt = record.revokedAt, let id = record.refundActivityID {
                    activity.append(SparksActivity(id: id, delta: -record.sparks,
                        reason: "local_storekit_refund", createdAt: revokedAt))
                }
            }
        }
        activity.sort { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
        return PaymentState(environment: .xcode, purchasesEnabled: true,
            wallet: SparksWallet(sparks: balance, refundDebtSparks: 0),
            packs: LocalStoreKitTestingConfiguration.packs, history: Array(activity.prefix(50)))
    }

    private func requireUser(_ id: UUID) throws {
        guard verifiedUserID() == id else { throw PaymentFailure.accountChanged }
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
#endif
