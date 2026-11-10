import AuthenticationServices
import Foundation
import Observation

/// Owns the UI session boundary. A native credential cannot unlock the app;
/// only a successful AuthenticationService verification may set the session.
@MainActor
@Observable
final class SessionStore {
    private(set) var isSigningIn = false
    private(set) var isSigningOut = false
    private(set) var isRestoringSession = false
    private(set) var isDeletingAccount = false
    private(set) var hasRestorationError = false
    private(set) var errorMessage: String?
    private(set) var hasAgreedToLegalDocuments = false
    private var userSession: UserSession?

    @ObservationIgnored private let authenticationService: any AuthenticationService
    @ObservationIgnored private var pendingAttempt: AppleSignInAttempt?
    @ObservationIgnored private var verificationID: UUID?
    @ObservationIgnored private var sessionGeneration = UUID()
    @ObservationIgnored private var restoreID: UUID?
    @ObservationIgnored private var hasAttemptedRestoration = false
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var deletionID: UUID?

    var isAuthenticated: Bool { userSession != nil }
    var userDisplayName: String? { userSession?.displayName }
    var verifiedUserID: String? { userSession?.verifiedUserID }
    var isDevelopmentSession: Bool { userSession?.cohort == .development }
    var isExperienceSession: Bool { userSession?.isExperience == true }
    var hasPendingAccountDeletion: Bool { authenticationService.hasPendingAccountDeletion }
    var requiresExperienceSignOutConfirmation: Bool {
        isExperienceSession || (hasRestorationError && authenticationService.hasPersistedExperienceSession)
    }
    var isSignInAvailable: Bool { authenticationService.isAvailable }
    var isExperienceSignInAvailable: Bool { authenticationService.isExperienceSignInAvailable }
    var isDevelopmentSignInAvailable: Bool {
        #if DEBUG
        authenticationService.isDevelopmentSignInAvailable
        #else
        false
        #endif
    }

    init() {
        authenticationService = UnavailableAuthenticationService()
    }

    init(authenticationService: any AuthenticationService) {
        self.authenticationService = authenticationService
    }

    func setLegalConsent(_ agreed: Bool) {
        guard !isAuthenticated, !isSigningIn, !isSigningOut, !isRestoringSession else { return }
        hasAgreedToLegalDocuments = agreed
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let signInRequest = beginSignIn() else { return }
        request.requestedScopes = [.fullName, .email]
        request.state = signInRequest.state
        request.nonce = signInRequest.hashedNonce
    }

    @discardableResult
    func beginSignIn() -> AppleSignInRequest? {
        guard !isAuthenticated, !isSigningIn, !isSigningOut, !isRestoringSession,
              !hasRestorationError, hasAgreedToLegalDocuments else { return nil }
        guard isSignInAvailable else {
            errorMessage = "Sign in with Apple is not available yet. Please check back later."
            return nil
        }

        errorMessage = nil
        do {
            let attempt = try AppleSignInAttempt()
            pendingAttempt = attempt
            isSigningIn = true
            return attempt.request
        } catch {
            errorMessage = Self.signInErrorMessage
            return nil
        }
    }

    func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        guard pendingAttempt != nil, verificationID == nil else { return }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                finishPendingAttempt(errorMessage: Self.signInErrorMessage)
                return
            }
            await completeSignIn(with: AppleSignInCredential(credential))
        case .failure(let error):
            let wasCancelled = error is CancellationError || (error as? ASAuthorizationError)?.code == .canceled
            finishPendingAttempt(errorMessage: wasCancelled ? nil : Self.signInErrorMessage)
        }
    }

    func completeSignIn(with credential: AppleSignInCredential) async {
        guard let attempt = pendingAttempt, verificationID == nil else { return }
        let payload: AppleAuthenticationPayload
        do {
            payload = try credential.validatedPayload(for: attempt)
        } catch {
            finishPendingAttempt(errorMessage: Self.signInErrorMessage)
            return
        }

        // Consume the request once. Further completion callbacks cannot reuse it.
        pendingAttempt = nil
        verificationID = attempt.id
        let generation = sessionGeneration
        defer {
            if verificationID == attempt.id {
                verificationID = nil
                isSigningIn = false
            }
        }

        do {
            let verifiedSession = try await authenticationService.verifyAppleSignIn(payload)
            guard generation == sessionGeneration else { return }
            guard !Task.isCancelled else {
                signOut()
                return
            }
            try verifiedSession.requireAllowedCohort()
            userSession = verifiedSession
            errorMessage = nil
        } catch is CancellationError {
            if generation == sessionGeneration { errorMessage = nil }
        } catch {
            // Service errors can include request bodies. Only fixed safe copy
            // reaches the UI; neither credentials nor raw errors are logged.
            if generation == sessionGeneration { errorMessage = Self.signInErrorMessage }
        }
    }

    func signInForDevelopment(accessCode: String) async {
        #if DEBUG
        guard !isAuthenticated, !isSigningIn, !isSigningOut, !isRestoringSession,
              !hasRestorationError else { return }
        guard isDevelopmentSignInAvailable else {
            errorMessage = Self.developmentSignInErrorMessage
            return
        }
        let code = accessCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.utf8.count <= 256 else {
            errorMessage = "Enter a valid development access code."
            return
        }
        let attemptID = UUID()
        let generation = sessionGeneration
        verificationID = attemptID
        isSigningIn = true
        errorMessage = nil
        defer {
            if verificationID == attemptID {
                verificationID = nil
                isSigningIn = false
            }
        }
        do {
            let verifiedSession = try await authenticationService.verifyDevelopmentAccessCode(code)
            guard generation == sessionGeneration else { return }
            guard !Task.isCancelled else {
                signOut()
                return
            }
            guard verifiedSession.cohort == .development else {
                signOut()
                errorMessage = Self.developmentSignInErrorMessage
                return
            }
            userSession = verifiedSession
        } catch is CancellationError {
            if generation == sessionGeneration { errorMessage = nil }
        } catch {
            if generation == sessionGeneration { errorMessage = Self.developmentSignInErrorMessage }
        }
        #else
        errorMessage = Self.signInErrorMessage
        #endif
    }

    func signInForExperience() async {
        guard !isAuthenticated, !isSigningIn, !isSigningOut, !isRestoringSession,
              !hasRestorationError, hasAgreedToLegalDocuments else { return }
        guard isExperienceSignInAvailable else {
            errorMessage = Self.experienceSignInErrorMessage
            return
        }
        let attemptID = UUID()
        let generation = sessionGeneration
        verificationID = attemptID
        isSigningIn = true
        errorMessage = nil
        defer {
            if verificationID == attemptID {
                verificationID = nil
                isSigningIn = false
            }
        }
        do {
            let verifiedSession = try await authenticationService.signInForExperience()
            guard generation == sessionGeneration else { return }
            guard !Task.isCancelled else {
                signOut()
                return
            }
            guard verifiedSession.isExperience, verifiedSession.cohort == .production else {
                signOut()
                errorMessage = Self.experienceSignInErrorMessage
                return
            }
            userSession = verifiedSession
        } catch is CancellationError {
            if generation == sessionGeneration { errorMessage = nil }
        } catch {
            if generation == sessionGeneration { errorMessage = Self.experienceSignInErrorMessage }
        }
    }

    func deleteExperienceAccount() async {
        guard isExperienceSession else { return }
        await performAccountDeletion { try await self.authenticationService.deleteExperienceAccount() }
    }

    func deleteAccount() async {
        await performAccountDeletion { try await self.authenticationService.deleteAccount() }
    }

    private func performAccountDeletion(_ delete: @MainActor () async throws -> Void) async {
        guard isAuthenticated, !isDeletingAccount, !isSigningOut else { return }
        let attemptID = UUID()
        let generation = sessionGeneration
        deletionID = attemptID
        isDeletingAccount = true
        errorMessage = nil
        defer {
            if deletionID == attemptID {
                deletionID = nil
                isDeletingAccount = false
            }
        }
        do {
            try await delete()
            guard generation == sessionGeneration else { return }
            // Deletion may already have completed on the server even if the
            // caller's task was cancelled. Always discard its local credentials.
            signOut()
        } catch AuthenticationFailure.appleDeletionUnavailable {
            guard generation == sessionGeneration else { return }
            errorMessage = "Apple account deletion isn't available until secure Apple authorization revocation is configured. Your account hasn't been deleted."
        } catch {
            guard generation == sessionGeneration else { return }
            errorMessage = "We couldn't confirm account deletion. Check your connection and try again. You can also sign out to clear this device; signing out doesn't confirm server deletion."
        }
    }

    func signOut() {
        sessionGeneration = UUID()
        if requiresExperienceSignOutConfirmation { SampleMessageStore.clearSavedInbox() }
        authenticationService.invalidateLocalSession()
        userSession = nil
        pendingAttempt = nil
        errorMessage = nil
        hasAgreedToLegalDocuments = false
        hasRestorationError = false
        hasAttemptedRestoration = true
        restoreID = nil
        isRestoringSession = false
        deletionID = nil
        isDeletingAccount = false
        // Keep an existing exchange serialized. Its eventual result is ignored
        // because sign-out has changed sessionGeneration.
        if verificationID == nil { isSigningIn = false }
        guard authenticationService.maintainsPersistentSession, !isSigningOut else { return }
        isSigningOut = true
        let service = authenticationService
        cleanupTask = Task { @MainActor [weak self] in
            do {
                try await service.signOut()
            } catch {
                // User intent is persisted even when remote invalidation fails.
                self?.errorMessage = "You are signed out. We couldn't finish clearing the previous session. Please sign in again."
            }
            self?.isSigningOut = false
            self?.cleanupTask = nil
        }
    }

    func restoreSession(force: Bool = false) async {
        guard !isAuthenticated, !isSigningIn, !isSigningOut, !isRestoringSession,
              force || !hasAttemptedRestoration else { return }
        let attemptID = UUID()
        let generation = sessionGeneration
        restoreID = attemptID
        hasAttemptedRestoration = true
        isRestoringSession = true
        hasRestorationError = false
        errorMessage = nil
        defer {
            if restoreID == attemptID {
                restoreID = nil
                isRestoringSession = false
            }
        }

        do {
            let verifiedSession = try await authenticationService.restoreSession()
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            try verifiedSession?.requireAllowedCohort()
            userSession = verifiedSession
        } catch AuthenticationFailure.developmentSessionNotAllowed {
            guard generation == sessionGeneration else { return }
            signOut()
        } catch is CancellationError {
            if generation == sessionGeneration { hasAttemptedRestoration = false }
        } catch {
            guard generation == sessionGeneration else { return }
            // Retain the stored session for a retry; never unlock from cached data
            // after a transient server-verification or token-refresh failure.
            hasRestorationError = true
            if authenticationService.hasPendingAccountDeletion {
                errorMessage = "We couldn't confirm account deletion. Try Again will retry with this device's saved session. If the account was already deleted, choose Sign in again to clear this device and start over."
            } else {
                errorMessage = "We couldn't restore your session. Check your connection and try again."
            }
        }
    }

    func observeAuthenticationChanges() async {
        await authenticationService.observeSignOut { [weak self] in
            guard let self, self.userSession != nil else { return }
            let wasDeletingAccount = self.isDeletingAccount
            self.signOut()
            if !wasDeletingAccount { self.errorMessage = "Your session ended. Please sign in again." }
        }
    }

    private func finishPendingAttempt(errorMessage: String?) {
        pendingAttempt = nil
        isSigningIn = false
        self.errorMessage = errorMessage
    }

    private static let signInErrorMessage = "We couldn't complete sign-in. Please try again."
    #if DEBUG && COMMUNITY_TESTING
    private static let developmentSignInErrorMessage = "We couldn't sign in to this test account. Check your connection and try again."
    #else
    private static let developmentSignInErrorMessage = "We couldn't sign in for testing. Check your access code and connection, then try again."
    #endif
    private static let experienceSignInErrorMessage = "We couldn't create your device account. Check your connection and try again."
}
