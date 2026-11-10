import XCTest
@testable import FLTiya

// Source tests precede the implementation. Native execution is intentionally
// deferred: this task does not authorize builds, type checks or XCTest runs.
@MainActor
final class PaymentStoreTests: XCTestCase {
    func testDisabledCatalogAndNonconsumableProductsCannotStartPurchase() async {
        let fixture = PaymentFixture()
        fixture.repository.state = fixture.state(enabled: false)
        await fixture.load()
        XCTAssertFalse(fixture.store.canPurchase(fixture.pack))
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
        XCTAssertEqual(fixture.shop.purchaseCount, 0)

        fixture.repository.state = fixture.state(enabled: true)
        fixture.shop.products = [PaymentProduct(id: "registered.pack", displayPrice: "$0.99", isConsumable: false)]
        await fixture.store.refresh()
        XCTAssertFalse(fixture.store.canPurchase(fixture.pack))
    }

    func testPendingAndCancellationDoNotCreditOrFinish() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.shop.result = .pending
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.store.purchaseStatus, .pendingApproval)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
        XCTAssertEqual(fixture.repository.deliveries.count, 0)

        fixture.shop.result = .cancelled
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.store.purchaseStatus, .cancelled)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
    }

    func testOnlyMatchingDurableAcknowledgementFinishesAndUpdatesWallet() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.shop.result = .transaction(fixture.transaction())
        fixture.repository.response = fixture.acknowledgement(.credited, balance: 400)
        fixture.repository.onDelivery = { fixture.repository.state = fixture.state(balance: 400) }
        await fixture.store.purchase(fixture.pack)

        XCTAssertEqual(fixture.repository.deliveries, ["transient-test-jws"])
        XCTAssertEqual(fixture.shop.lastAccountToken, fixture.userID)
        XCTAssertEqual(fixture.finishCount, 1)
        XCTAssertEqual(fixture.store.wallet?.sparks, 400)
        XCTAssertEqual(fixture.store.purchaseStatus, .delivered(.credited))
    }

    func testLostDeliveryResponseKeepsTransactionUnfinishedThenRetriesIdempotently() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.shop.result = .transaction(fixture.transaction())
        fixture.repository.deliveryError = URLError(.networkConnectionLost)
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.finishCount, 0)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
        XCTAssertEqual(fixture.store.purchaseStatus, .deliveryPending)

        fixture.repository.deliveryError = nil
        fixture.repository.response = fixture.acknowledgement(.alreadyCredited, balance: 400)
        fixture.repository.onDelivery = { fixture.repository.state = fixture.state(balance: 400) }
        fixture.shop.unfinished = [fixture.transaction()]
        await fixture.store.retryUnfinished()
        XCTAssertEqual(fixture.finishCount, 1)
        XCTAssertEqual(fixture.store.wallet?.sparks, 400)
        XCTAssertEqual(fixture.store.purchaseStatus, .delivered(.alreadyCredited))
    }

    func testRefundedAcknowledgementFinishesWithoutInventingCredit() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.repository.response = fixture.acknowledgement(.refunded, balance: 0)
        fixture.shop.result = .transaction(fixture.transaction())
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.finishCount, 1)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
        XCTAssertEqual(fixture.store.purchaseStatus, .delivered(.refunded))
    }

    func testUnverifiedAndOtherAccountTransactionsNeverReachBackendOrFinish() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.shop.result = .transaction(.unverified)
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.store.purchaseStatus, .verificationFailed)

        fixture.shop.result = .transaction(fixture.transaction(account: UUID()))
        await fixture.store.purchase(fixture.pack)
        XCTAssertTrue(fixture.repository.deliveries.isEmpty)
        XCTAssertEqual(fixture.finishCount, 0)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
    }

    func testWrongTransactionOrEnvironmentAcknowledgementNeverFinishes() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.shop.result = .transaction(fixture.transaction())
        fixture.repository.response = fixture.acknowledgement(.credited, balance: 400, transactionID: "other")
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.finishCount, 0)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)

        fixture.repository.response = fixture.acknowledgement(.credited, balance: 400, environment: .sandbox)
        await fixture.store.purchase(fixture.pack)
        XCTAssertEqual(fixture.finishCount, 0)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
    }

    func testLogoutDuringDeliveryDiscardsLateWalletAndDoesNotFinish() async {
        let fixture = PaymentFixture()
        await fixture.load()
        let started = expectation(description: "Server delivery suspended")
        fixture.repository.onSuspend = { started.fulfill() }
        fixture.repository.suspendsDelivery = true
        fixture.shop.result = .transaction(fixture.transaction())
        let purchase = Task { await fixture.store.purchase(fixture.pack) }
        await fulfillment(of: [started], timeout: 1)
        fixture.identity = nil
        fixture.store.setUserID(nil)
        fixture.repository.completeDelivery(fixture.acknowledgement(.credited, balance: 400))
        await purchase.value
        XCTAssertNil(fixture.store.wallet)
        XCTAssertEqual(fixture.finishCount, 0)
        XCTAssertEqual(fixture.store.purchaseStatus, .idle)
    }

    func testSupersededAccountLoadCannotShowPreviousWallet() async {
        let fixture = PaymentFixture()
        let started = expectation(description: "State load suspended")
        fixture.repository.onLoadSuspend = { started.fulfill() }
        fixture.repository.suspendsLoad = true
        let load = Task { await fixture.store.refresh() }
        await fulfillment(of: [started], timeout: 1)
        fixture.identity = UUID()
        fixture.store.setUserID(fixture.identity?.uuidString)
        fixture.repository.completeLoad(fixture.state(balance: 777))
        await load.value
        XCTAssertNil(fixture.store.wallet)
        XCTAssertFalse(fixture.store.canPurchase(fixture.pack))
    }

    func testSandboxTransactionsCannotEnterProductionWallet() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.shop.unfinished = [fixture.transaction(environment: .sandbox)]
        await fixture.store.retryUnfinished()
        XCTAssertTrue(fixture.repository.deliveries.isEmpty)
        XCTAssertEqual(fixture.finishCount, 0)
        XCTAssertEqual(fixture.store.wallet?.sparks, 0)
    }

    func testLocalTransactionsAndDedicatedProductIDsCannotEnterServerDelivery() {
        let account = UUID()
        func transaction(environment: PaymentEnvironment, product: String) -> PaymentTransaction {
            PaymentTransaction(id: "42", productID: product, accountToken: account,
                environment: environment.rawValue, isConsumable: true, quantity: 1,
                signedTransaction: "transient-test-jws", finish: {})
        }
        XCTAssertTrue(SupabasePaymentRepository.permitsServerDelivery(transaction(environment: .production, product: "registered.pack")))
        XCTAssertTrue(SupabasePaymentRepository.permitsServerDelivery(transaction(environment: .sandbox, product: "registered.pack")))
        XCTAssertFalse(SupabasePaymentRepository.permitsServerDelivery(transaction(environment: .xcode, product: "registered.pack")))
        XCTAssertFalse(SupabasePaymentRepository.permitsServerDelivery(transaction(environment: .sandbox, product: "com.fltiya.local.sparks.400")))
    }

    func testChangedLiveIdentityWithoutViewCallbackStillBlocksDelivery() async {
        let fixture = PaymentFixture()
        await fixture.load()
        fixture.identity = UUID()
        fixture.shop.unfinished = [fixture.transaction()]
        await fixture.store.retryUnfinished()
        XCTAssertFalse(fixture.store.canPurchase(fixture.pack))
        XCTAssertTrue(fixture.repository.deliveries.isEmpty)
        XCTAssertEqual(fixture.finishCount, 0)
    }

    func testSingleObserverDeliversRetiredTransactionEvenWhenNewPurchasesDisabled() async {
        let fixture = PaymentFixture()
        fixture.repository.state = PaymentState(environment: .production, purchasesEnabled: false,
            wallet: SparksWallet(sparks: 0, refundDebtSparks: 0), packs: [], history: [])
        await fixture.load()
        let finished = expectation(description: "Existing paid transaction finished")
        fixture.onFinish = { finished.fulfill() }
        fixture.store.startObserving()
        fixture.store.startObserving()
        fixture.shop.updates?.yield(fixture.transaction())
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(fixture.shop.observerCount, 1)
        XCTAssertEqual(fixture.finishCount, 1)
        XCTAssertFalse(fixture.store.canPurchase(fixture.pack))
    }

    func testDistinctObserverDeliveriesWaitForPreviousServerAcknowledgement() async {
        let fixture = PaymentFixture()
        await fixture.load()
        let firstStarted = expectation(description: "First delivery started")
        let bothFinished = expectation(description: "Both deliveries finished")
        bothFinished.expectedFulfillmentCount = 2
        fixture.repository.suspendsDelivery = true
        fixture.repository.onSuspend = { firstStarted.fulfill() }
        fixture.onFinish = { bothFinished.fulfill() }
        fixture.store.startObserving()
        fixture.shop.result = .transaction(fixture.transaction())
        let purchase = Task { await fixture.store.purchase(fixture.pack) }
        await fulfillment(of: [firstStarted], timeout: 1)
        fixture.shop.updates?.yield(fixture.transaction(id: "43"))
        fixture.repository.suspendsDelivery = false
        fixture.repository.response = fixture.acknowledgement(.credited, balance: 800, transactionID: "43")
        fixture.repository.onDelivery = { fixture.repository.state = fixture.state(balance: 800) }
        fixture.repository.completeDelivery(fixture.acknowledgement(.credited, balance: 400))
        await purchase.value
        await fulfillment(of: [bothFinished], timeout: 1)
        XCTAssertEqual(fixture.finishCount, 2)
        XCTAssertEqual(fixture.store.wallet?.sparks, 800)
    }

    func testStaleStateLoadCannotOverwriteAcknowledgedWallet() async {
        let fixture = PaymentFixture()
        await fixture.load()
        let loadStarted = expectation(description: "Old wallet read suspended")
        let finished = expectation(description: "Purchase acknowledged")
        fixture.repository.suspendsLoad = true
        fixture.repository.onLoadSuspend = { loadStarted.fulfill() }
        fixture.onFinish = { finished.fulfill() }
        let oldLoad = Task { await fixture.store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        fixture.repository.suspendsLoad = false
        fixture.repository.onDelivery = { fixture.repository.state = fixture.state(balance: 400) }
        fixture.store.startObserving()
        fixture.shop.updates?.yield(fixture.transaction())
        await fulfillment(of: [finished], timeout: 1)
        fixture.repository.completeLoad(fixture.state(balance: 777))
        await oldLoad.value
        XCTAssertEqual(fixture.store.wallet?.sparks, 400)
    }

    func testObserverRetriesApprovalWhenItsStateLoadSupersedesInitialLoginLoad() async {
        let fixture = PaymentFixture()
        let loginLoadStarted = expectation(description: "Initial login state read suspended")
        let observerLoadStarted = expectation(description: "Observer state read supersedes login read")
        let finished = expectation(description: "Approval delivered without manual refresh")
        var suspendedReads = 0
        fixture.repository.suspendsLoad = true
        fixture.repository.onLoadSuspend = {
            suspendedReads += 1
            if suspendedReads == 1 { loginLoadStarted.fulfill() }
            if suspendedReads == 2 { observerLoadStarted.fulfill() }
        }
        fixture.repository.onDelivery = { [weak fixture] in
            guard let fixture else { return }
            fixture.repository.state = fixture.state(balance: 400)
        }
        fixture.onFinish = { [weak fixture] in
            fixture?.shop.unfinished = []
            finished.fulfill()
        }
        fixture.shop.unfinished = [fixture.transaction()]
        fixture.store.startObserving()

        let login = Task { await fixture.store.refreshAndRetry() }
        await fulfillment(of: [loginLoadStarted], timeout: 1)
        fixture.shop.updates?.yield(fixture.transaction())
        await fulfillment(of: [observerLoadStarted], timeout: 1)

        // R1 is stale because R2 owns loadID. Its retry sees no environment.
        fixture.repository.completeLoad(fixture.state())
        await login.value
        XCTAssertNil(fixture.store.environment)
        XCTAssertTrue(fixture.repository.deliveries.isEmpty)
        XCTAssertEqual(fixture.finishCount, 0)

        // Completing only the winning observer read must recover the approved
        // transaction. No foreground event or manual retry follows this point.
        fixture.repository.suspendsLoad = false
        fixture.repository.completeLoad(fixture.state())
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(fixture.repository.deliveries, ["transient-test-jws"])
        XCTAssertEqual(fixture.store.wallet?.sparks, 400)
        XCTAssertEqual(fixture.finishCount, 1)
    }

    func testWireContractDecodesSandboxAndKnownActivityReasons() throws {
        let payload = Data(#"{"environment":"Sandbox","purchases_enabled":false,"wallet":{"sparks":400,"refund_debt_sparks":12},"packs":[{"id":"sparks_400","name":"400 Sparks","sparks":400,"store_product_id":null,"is_active":false,"reference_price_usd":"0.99","sort_order":1}],"history":[{"id":"9CFE7959-BC59-4717-957E-4A080B77C8BB","delta":400,"reason":"storekit_recharge","created_at":"2026-11-03T08:00:00.123Z"}]}"#.utf8)
        let state = try JSONDecoder().decode(PaymentState.self, from: payload)
        XCTAssertEqual(state.environment, .sandbox)
        XCTAssertEqual(state.wallet.refundDebtSparks, 12)
        XCTAssertEqual(state.packs.first?.referencePriceUSD, "0.99")
        XCTAssertEqual(state.history.first?.title, "Sparks purchase")
        XCTAssertNotNil(state.history.first?.date)
    }
}

@MainActor
private final class PaymentFixture {
    let userID = UUID()
    var identity: UUID?
    let repository = PaymentRepositoryDouble()
    let shop = PaymentStorefrontDouble()
    var finishCount = 0
    var onFinish: (() -> Void)?
    lazy var store = PaymentStore(repository: repository, storefront: shop, verifiedUserID: { [weak self] in self?.identity })
    let pack = SparksPack(id: "sparks_400", name: "400 Sparks", sparks: 400,
        storeProductID: "registered.pack", isActive: true, referencePriceUSD: "0.99", sortOrder: 1)

    init() {
        identity = userID
        repository.state = state()
        repository.response = acknowledgement(.credited, balance: 400)
        store.setUserID(userID.uuidString)
    }

    func load() async { await store.refresh() }
    func state(enabled: Bool = true, balance: Int64 = 0) -> PaymentState {
        PaymentState(environment: .production, purchasesEnabled: enabled,
            wallet: SparksWallet(sparks: balance, refundDebtSparks: 0), packs: [pack], history: [])
    }
    func acknowledgement(_ disposition: PaymentDisposition, balance: Int64,
                         transactionID: String = "42", environment: PaymentEnvironment = .production) -> PaymentAcknowledgement {
        PaymentAcknowledgement(environment: environment, transactionID: transactionID,
            disposition: disposition, creditedSparks: 400,
            wallet: SparksWallet(sparks: balance, refundDebtSparks: 0))
    }
    func transaction(account: UUID? = nil, environment: PaymentEnvironment = .production, id: String = "42") -> PaymentTransactionEvent {
        .verified(PaymentTransaction(id: id, productID: "registered.pack", accountToken: account ?? userID,
            environment: environment.rawValue, isConsumable: true, quantity: 1,
            signedTransaction: "transient-test-jws", finish: { [weak self] in
                self?.finishCount += 1
                self?.onFinish?()
            }))
    }
}

@MainActor
private final class PaymentRepositoryDouble: PaymentRepository {
    var state: PaymentState!
    var response: PaymentAcknowledgement!
    var deliveryError: Error?
    var deliveries: [String] = []
    var onDelivery: (() -> Void)?
    var suspendsDelivery = false
    var onSuspend: (() -> Void)?
    var suspendsLoad = false
    var onLoadSuspend: (() -> Void)?
    private var deliveryContinuation: CheckedContinuation<PaymentAcknowledgement, Error>?
    private var loadContinuations: [CheckedContinuation<PaymentState, Error>] = []
    func loadState(for userID: UUID) async throws -> PaymentState {
        if suspendsLoad {
            return try await withCheckedThrowingContinuation { loadContinuations.append($0); onLoadSuspend?() }
        }
        return state
    }
    func deliver(transaction: PaymentTransaction, for userID: UUID) async throws -> PaymentAcknowledgement {
        deliveries.append(transaction.signedTransaction)
        if let deliveryError { throw deliveryError }
        if suspendsDelivery {
            return try await withCheckedThrowingContinuation { deliveryContinuation = $0; onSuspend?() }
        }
        onDelivery?()
        return response
    }
    func completeDelivery(_ response: PaymentAcknowledgement) {
        deliveryContinuation?.resume(returning: response); deliveryContinuation = nil
    }
    func completeLoad(_ state: PaymentState) {
        guard !loadContinuations.isEmpty else { return }
        loadContinuations.removeFirst().resume(returning: state)
    }
}

@MainActor
private final class PaymentStorefrontDouble: PaymentStorefront {
    var products = [PaymentProduct(id: "registered.pack", displayPrice: "$0.99", isConsumable: true)]
    var result: PaymentPurchaseResult = .cancelled
    var unfinished: [PaymentTransactionEvent] = []
    var purchaseCount = 0
    var lastAccountToken: UUID?
    var updates: AsyncStream<PaymentTransactionEvent>.Continuation?
    var observerCount = 0
    func loadProducts(ids: Set<String>) async throws -> [PaymentProduct] { products }
    func purchase(productID: String, accountToken: UUID) async throws -> PaymentPurchaseResult {
        purchaseCount += 1; lastAccountToken = accountToken
        return result
    }
    func unfinishedTransactions() async -> [PaymentTransactionEvent] { unfinished }
    func transactionUpdates() -> AsyncStream<PaymentTransactionEvent> {
        observerCount += 1
        return AsyncStream { updates = $0 }
    }
}
