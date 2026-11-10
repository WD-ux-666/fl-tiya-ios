import SwiftUI

@MainActor
struct RootView: View {
    let session: SessionStore
    var payments: PaymentStore? = nil
    var calls: CallCoordinator? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var isConfirmingExperienceSignOut = false

    #if DEBUG
    @State private var isShowingDevelopmentPreview = DevelopmentPreviewConfiguration.opensAutomatically
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if isShowingDevelopmentPreview {
                DevelopmentPreviewView {
                    isShowingDevelopmentPreview = false
                }
                .environment(\.socialRepository, nil)
                .environment(\.paymentStore, nil)
                .environment(\.callCoordinator, nil)
            } else {
                authenticatedContent
            }
            #else
            authenticatedContent
            #endif
        }
        .background(AppTheme.background)
        .task { payments?.startObserving() }
        .task(id: paymentUserID) {
            await calls?.monitor(userID: paymentUserID.flatMap(UUID.init(uuidString:)))
        }
        .onChange(of: paymentUserID, initial: true) { _, id in
            payments?.setUserID(id)
        }
        .task(id: paymentUserID) {
            payments?.setUserID(paymentUserID)
            await payments?.refreshAndRetry()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await payments?.refreshAndRetry() } }
            if phase == .background { Task { await calls?.setForeground(false) } }
            else if phase == .active { Task { await calls?.setForeground(true) } }
        }
        .fullScreenCover(item: Binding(get: { calls?.call }, set: { value in
            if value == nil, calls?.call != nil { Task { await calls?.finish() } }
        })) { _ in
            if let calls { CallScreen(coordinator: calls) }
        }
        .alert("Call", isPresented: Binding(get: { calls?.call == nil && calls?.errorMessage != nil }, set: { if !$0 { calls?.errorMessage = nil } })) {
            Button("OK", role: .cancel) { calls?.errorMessage = nil }
        } message: { Text(calls?.errorMessage ?? "") }
    }

    private var paymentUserID: String? {
        #if DEBUG
        if isShowingDevelopmentPreview { return nil }
        #endif
        return session.verifiedUserID
    }

    private var authenticatedContent: some View {
        sessionContent
            .environment(\.paymentStore, payments)
            .environment(\.callCoordinator, calls)
            .task {
                await session.restoreSession()
                #if DEBUG && !DEVELOPMENT_PREVIEW && !COMMUNITY_TESTING
                // Opt-in local UI review uses the existing server-verified test
                // login; it never creates a fake session or ships in Release.
                if !session.isAuthenticated, !session.hasRestorationError,
                   let accessCode = ProcessInfo.processInfo.environment["FLTIYA_UI_REVIEW_ACCESS_CODE"],
                   !accessCode.isEmpty {
                    await session.signInForDevelopment(accessCode: accessCode)
                }
                #endif
            }
            .task { await session.observeAuthenticationChanges() }
    }

    @ViewBuilder
    private var sessionContent: some View {
        if session.isRestoringSession || session.isSigningOut {
            VStack(spacing: 14) {
                ProgressView().tint(AppTheme.accent)
                Text(session.isSigningOut ? "Signing out…" : "Restoring your session…")
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.hasRestorationError {
            VStack(spacing: 18) {
                Text(session.hasPendingAccountDeletion ? "Couldn't confirm deletion" : "Couldn't restore your session")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(session.errorMessage ?? "Please try again.")
                    .foregroundStyle(AppTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await session.restoreSession(force: true) }
                }
                .buttonStyle(.borderedProminent)
                Button("Sign in again") {
                    if session.requiresExperienceSignOutConfirmation {
                        isConfirmingExperienceSignOut = true
                    } else {
                        session.signOut()
                    }
                }
                    .frame(minHeight: 44)
            }
            .confirmationDialog("Leave this device account?", isPresented: $isConfirmingExperienceSignOut,
                                titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { session.signOut() }
                Button("Keep account", role: .cancel) {}
            } message: {
                Text("Your account is saved on this device. Signing out removes access to it. Try restoring your session first if you want to keep your data.")
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if session.isAuthenticated {
            AppTabView(session: session)
                .id(session.verifiedUserID)
        } else {
            LoginView(session: session)
        }
    }

}

#Preview("App entry") {
    RootView(session: SessionStore())
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
}
