import SwiftUI

@main
@MainActor
struct FLTiyaApp: App {
    @State private var session: SessionStore
    @State private var payments: PaymentStore?
    @State private var calls: CallCoordinator?
    @State private var socialVisibility: SocialVisibility
    private let socialRepository: (any SocialRepository)?

    init() {
        let visibility = SocialVisibility()
        _socialVisibility = State(initialValue: visibility)
        let client = SupabaseClientFactory.makeClient()
        if let client, let configuration = BackendConfiguration.load() {
            let session = SessionStore(authenticationService:
                SupabaseAuthenticationService(client: client, configuration: configuration)
            )
            _session = State(initialValue: session)
            let paymentRepository: any PaymentRepository
            let paymentUserID: () -> UUID? = { session.verifiedUserID.flatMap(UUID.init(uuidString:)) }
            #if DEBUG && !DEVELOPMENT_PREVIEW
            if LocalStoreKitTestingConfiguration.isEnabled {
                // The explicit Xcode scheme uses a local wallet for the verified account.
                paymentRepository = LocalStoreKitPaymentRepository(verifiedUserID: paymentUserID)
            } else {
                paymentRepository = SupabasePaymentRepository(client: client)
            }
            #else
            paymentRepository = SupabasePaymentRepository(client: client)
            #endif
            _payments = State(initialValue: PaymentStore(
                repository: paymentRepository, storefront: StoreKitPaymentStorefront(),
                verifiedUserID: paymentUserID
            ))
            socialRepository = SupabaseSocialRepository(client: client, visibility: visibility)
            _calls = State(initialValue: CallCoordinator(service: SupabaseCallService(client: client), media: LiveCallMedia()))
        } else {
            _session = State(initialValue: SessionStore())
            _payments = State(initialValue: nil)
            socialRepository = nil
            _calls = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, payments: payments, calls: calls)
                .environment(\.socialRepository, socialRepository)
                .environment(\.socialVisibility, socialVisibility)
                .onChange(of: session.verifiedUserID, initial: true) { _, id in
                    socialVisibility.useAccount(id.flatMap(UUID.init(uuidString:)))
                }
                .tint(AppTheme.accent)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en"))
        }
    }
}
