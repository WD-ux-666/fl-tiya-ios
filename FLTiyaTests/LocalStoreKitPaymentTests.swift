import Foundation
import XCTest
@testable import FLTiya

#if DEBUG && !DEVELOPMENT_PREVIEW
// Written before the implementation. Native execution is deferred by the
// no-build/no-XCTest constraint; grammar parsing is not an executed test.
@MainActor
final class LocalStoreKitPaymentTests: XCTestCase {
    func testLocalModeRequiresTheExactExplicitLaunchFlag() {
        XCTAssertFalse(LocalStoreKitTestingConfiguration.isEnabled(environment: [:]))
        XCTAssertFalse(LocalStoreKitTestingConfiguration.isEnabled(environment: ["FLTIYA_LOCAL_STOREKIT_TESTING": "true"]))
        XCTAssertTrue(LocalStoreKitTestingConfiguration.isEnabled(environment: ["FLTIYA_LOCAL_STOREKIT_TESTING": "1"]))
    }

    func testCatalogContainsOnlyNineDedicatedConsumableTestMappings() {
        let packs = LocalStoreKitTestingConfiguration.packs
        XCTAssertEqual(packs.count, 9)
        XCTAssertEqual(packs.map(\.sparks), SparksPack.draftPacks.map(\.sparks))
        XCTAssertEqual(packs.map(\.referencePriceUSD), SparksPack.draftPacks.map(\.referencePriceUSD))
        XCTAssertEqual(Set(packs.compactMap(\.storeProductID)).count, 9)
        XCTAssertTrue(packs.allSatisfy { $0.isActive && $0.storeProductID == "com.fltiya.local.sparks.\($0.sparks)" })
    }

    func testFreshStateUsesOnlyTheXcodeWalletAndLocalCatalog() async throws {
        let f = LocalPaymentFixture()
        let state = try await f.repository.loadState(for: f.alpha)
        XCTAssertEqual(state.environment, .xcode)
        XCTAssertTrue(state.purchasesEnabled)
        XCTAssertEqual(state.wallet.sparks, 0)
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertTrue(f.repository.isLocalStoreKitTesting)
    }

    func testFileJournalDistinguishesMissingStorageAndPersistsReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = LocalStoreKitFileJournal(directory: directory)
        XCTAssertNil(try storage.read())
        try storage.write(Data("first".utf8))
        try storage.write(Data("replacement".utf8))
        let reopened = LocalStoreKitFileJournal(directory: directory)
        XCTAssertEqual(try reopened.read(), Data("replacement".utf8))
    }

    func testVerifiedDeliveryPersistsBeforeAcknowledgementAndNeverStoresJWS() async throws {
        let f = LocalPaymentFixture()
        let response = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        XCTAssertEqual(response.disposition, .credited)
        XCTAssertEqual(response.wallet.sparks, 400)
        XCTAssertEqual(f.storage.writes, 1)
        let bytes = try XCTUnwrap(f.storage.data)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("transient-local-jws"))
        let reopened = LocalStoreKitPaymentRepository(verifiedUserID: { f.identity }, storage: f.storage)
        let loadedState1 = try await reopened.loadState(for: f.alpha)
        XCTAssertEqual(loadedState1.wallet.sparks, 400)
        let loadedState2 = try await reopened.loadState(for: f.alpha)
        XCTAssertEqual(loadedState2.history.count, 1)
    }

    func testDuplicateAfterReopeningCannotCreditTwice() async throws {
        let f = LocalPaymentFixture()
        _ = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        let reopened = LocalStoreKitPaymentRepository(verifiedUserID: { f.identity }, storage: f.storage)
        let duplicate = try await reopened.deliver(transaction: f.transaction(), for: f.alpha)
        XCTAssertEqual(duplicate.disposition, .alreadyCredited)
        XCTAssertEqual(duplicate.wallet.sparks, 400)
        XCTAssertEqual(f.storage.writes, 1)
    }

    func testLocalAccountsHaveSeparateBalancesAndCannotAdoptEachOthersTransaction() async throws {
        let f = LocalPaymentFixture()
        _ = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        f.identity = f.beta
        let loadedState3 = try await f.repository.loadState(for: f.beta)
        XCTAssertEqual(loadedState3.wallet.sparks, 0)
        do {
            _ = try await f.repository.deliver(transaction: f.transaction(), for: f.beta)
            XCTFail("Other-account transaction was accepted")
        } catch {}
        let loadedState4 = try await f.repository.loadState(for: f.beta)
        XCTAssertEqual(loadedState4.wallet.sparks, 0)
        f.identity = f.alpha
        let loadedState5 = try await f.repository.loadState(for: f.alpha)
        XCTAssertEqual(loadedState5.wallet.sparks, 400)
    }

    func testLiveEnvironmentUnknownProductWrongQuantityAndNonconsumableAreRejected() async throws {
        let f = LocalPaymentFixture()
        for transaction in [
            f.transaction(environment: "Production"), f.transaction(environment: "Sandbox"),
            f.transaction(product: "com.fltiya.real.sparks.400"),
            f.transaction(quantity: 2), f.transaction(isConsumable: false),
            f.transaction(id: ""), f.transaction(account: f.beta)
        ] {
            do {
                _ = try await f.repository.deliver(transaction: transaction, for: f.alpha)
                XCTFail("Invalid local transaction was accepted")
            } catch {}
        }
        XCTAssertEqual(f.storage.writes, 0)
    }

    func testReusingATransactionIDWithADifferentProductIsRejected() async throws {
        let f = LocalPaymentFixture()
        _ = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        do {
            _ = try await f.repository.deliver(transaction: f.transaction(product: "com.fltiya.local.sparks.800"), for: f.alpha)
            XCTFail("Conflicting transaction facts were accepted")
        } catch {}
        let loadedState6 = try await f.repository.loadState(for: f.alpha)
        XCTAssertEqual(loadedState6.wallet.sparks, 400)
    }

    func testFailedPersistenceCannotCreditAndRetryRemainsIdempotent() async throws {
        let f = LocalPaymentFixture()
        f.storage.failWrites = true
        do {
            _ = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
            XCTFail("Failed durable write was acknowledged")
        } catch {}
        XCTAssertNil(f.storage.data)
        let loadedState7 = try await f.repository.loadState(for: f.alpha)
        XCTAssertEqual(loadedState7.wallet.sparks, 0)
        f.storage.failWrites = false
        let retry = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        XCTAssertEqual(retry.wallet.sparks, 400)
    }

    func testCorruptJournalFailsClosedWithoutResettingStoredRecords() async throws {
        let f = LocalPaymentFixture()
        f.storage.data = Data("corrupt journal".utf8)
        do {
            _ = try await f.repository.loadState(for: f.alpha)
            XCTFail("Corrupt journal was silently reset")
        } catch {}
        XCTAssertEqual(f.storage.writes, 0)
    }

    func testRevokedFirstTransactionNeverCreatesCredit() async throws {
        let f = LocalPaymentFixture()
        let response = try await f.repository.deliver(transaction: f.transaction(revoked: true), for: f.alpha)
        XCTAssertEqual(response.disposition, .refunded)
        XCTAssertEqual(response.wallet.sparks, 0)
        let loadedState9 = try await f.repository.loadState(for: f.alpha)
        XCTAssertTrue(loadedState9.history.isEmpty)
    }

    func testFullLocalRevocationIsAppliedOnceAndCannotBeResurrectedByStaleReplay() async throws {
        let f = LocalPaymentFixture()
        _ = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        _ = try await f.repository.deliver(transaction: f.transaction(revoked: true), for: f.alpha)
        _ = try await f.repository.deliver(transaction: f.transaction(revoked: true), for: f.alpha)
        let stale = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
        XCTAssertEqual(stale.disposition, .refunded)
        XCTAssertEqual(stale.wallet.sparks, 0)
        let state = try await f.repository.loadState(for: f.alpha)
        XCTAssertEqual(state.history.count, 2)
        XCTAssertEqual(state.history.map(\.delta).sorted(), [-400, 400])
        XCTAssertEqual(f.storage.writes, 2)
    }

    func testMissingIdentityAndAccountSwitchDuringWriteNeverAcknowledgeAnotherAccount() async throws {
        let f = LocalPaymentFixture()
        f.identity = nil
        do {
            _ = try await f.repository.loadState(for: f.alpha)
            XCTFail("Missing identity was accepted")
        } catch {}
        f.identity = f.alpha
        f.storage.onWrite = { f.identity = f.beta }
        do {
            _ = try await f.repository.deliver(transaction: f.transaction(), for: f.alpha)
            XCTFail("Changed identity received acknowledgement")
        } catch {}
        let loadedState8 = try await f.repository.loadState(for: f.beta)
        XCTAssertEqual(loadedState8.wallet.sparks, 0)
    }

    func testPaymentStoreFinishesOnlyAfterLocalDurableCommit() async throws {
        let f = LocalPaymentFixture()
        let shop = LocalPaymentStorefrontDouble(transaction: f.transaction { f.finishCount += 1 })
        let store = PaymentStore(repository: f.repository, storefront: shop, verifiedUserID: { f.identity })
        store.setUserID(f.alpha.uuidString)
        await store.refresh()
        let pack = try XCTUnwrap(store.packs.first)
        XCTAssertTrue(store.isLocalStoreKitTesting)
        XCTAssertTrue(store.canPurchase(pack))
        f.storage.failWrites = true
        await store.purchase(pack)
        XCTAssertEqual(f.finishCount, 0)
        XCTAssertEqual(store.wallet?.sparks, 0)
        f.storage.failWrites = false
        await store.retryUnfinished()
        XCTAssertEqual(f.finishCount, 1)
        XCTAssertEqual(store.wallet?.sparks, 400)
    }

    func testLocalPendingCancelledAndUnverifiedTransactionsDoNotCreditOrFinish() async throws {
        let f = LocalPaymentFixture()
        let shop = LocalPaymentStorefrontDouble(transaction: f.transaction { f.finishCount += 1 })
        let store = PaymentStore(repository: f.repository, storefront: shop, verifiedUserID: { f.identity })
        store.setUserID(f.alpha.uuidString)
        await store.refresh()
        let pack = try XCTUnwrap(store.packs.first)
        for result in [PaymentPurchaseResult.pending, .cancelled, .transaction(.unverified)] {
            shop.result = result
            await store.purchase(pack)
            XCTAssertEqual(f.storage.writes, 0)
            XCTAssertEqual(f.finishCount, 0)
            XCTAssertEqual(store.wallet?.sparks, 0)
        }
    }
}

@MainActor
private final class LocalPaymentFixture {
    let alpha = UUID()
    let beta = UUID()
    var identity: UUID?
    var finishCount = 0
    let storage = LocalJournalStorageDouble()
    lazy var repository = LocalStoreKitPaymentRepository(verifiedUserID: { [weak self] in self?.identity }, storage: storage)
    init() { identity = alpha }
    func transaction(id: String = "42", product: String = "com.fltiya.local.sparks.400", account: UUID? = nil,
                     environment: String = "Xcode", quantity: Int = 1, isConsumable: Bool = true,
                     revoked: Bool = false, finish: @escaping @MainActor @Sendable () async -> Void = {}) -> PaymentTransaction {
        PaymentTransaction(id: id, productID: product, accountToken: account ?? alpha, environment: environment,
            isConsumable: isConsumable, quantity: quantity, signedTransaction: "transient-local-jws",
            revocationDate: revoked ? Date() : nil, finish: finish)
    }
}

@MainActor
private final class LocalJournalStorageDouble: LocalStoreKitJournalStorage {
    var data: Data?
    var writes = 0
    var failWrites = false
    var onWrite: (() -> Void)?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws {
        if failWrites { throw CocoaError(.fileWriteNoPermission) }
        self.data = data
        writes += 1
        onWrite?()
    }
}

@MainActor
private final class LocalPaymentStorefrontDouble: PaymentStorefront {
    let transaction: PaymentTransaction
    var result: PaymentPurchaseResult?
    init(transaction: PaymentTransaction) { self.transaction = transaction }
    func loadProducts(ids: Set<String>) async throws -> [PaymentProduct] {
        ids.map { PaymentProduct(id: $0, displayPrice: "$0.99", isConsumable: true) }
    }
    func purchase(productID: String, accountToken: UUID) async throws -> PaymentPurchaseResult { result ?? .transaction(.verified(transaction)) }
    func unfinishedTransactions() async -> [PaymentTransactionEvent] { [.verified(transaction)] }
    func transactionUpdates() -> AsyncStream<PaymentTransactionEvent> { AsyncStream { $0.finish() } }
}
#endif
