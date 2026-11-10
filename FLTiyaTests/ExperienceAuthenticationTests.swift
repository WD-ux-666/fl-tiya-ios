import Foundation
import XCTest
@testable import FLTiya

// Native XCTest execution remains deferred; the app source can be checked statically.
@MainActor
final class ExperienceAuthenticationTests: XCTestCase {
    func testAddressFormatAcceptsCommonAddressesAndTrimsOuterWhitespace() {
        XCTAssertEqual(ExperienceEmailAddress.normalized(" \nPlayer+clips@example.co.uk \n"), "Player+clips@example.co.uk")
        XCTAssertEqual(ExperienceEmailAddress.normalized("first.last@sub.example.com"), "first.last@sub.example.com")
    }

    func testOneTapDoesNotCreateAnAccountUntilConsentIsChecked() async {
        let provider = ExperienceVerifier()
        let store = SessionStore(authenticationService: provider)

        XCTAssertFalse(store.hasAgreedToLegalDocuments)
        await store.signInForExperience()
        store.setLegalConsent(true)
        store.setLegalConsent(false)
        await store.signInForExperience()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isSigningIn)
        XCTAssertEqual(provider.loginCount, 0)
    }

    func testUnavailableProviderCannotCreateDeviceAccount() async {
        let store = SessionStore()
        store.setLegalConsent(true)
        XCTAssertFalse(store.isExperienceSignInAvailable)
        await store.signInForExperience()
        XCTAssertFalse(store.isAuthenticated)
    }

    func testVerifiedDeviceAccountWorksWhileAppleIsUnavailable() async {
        let provider = ExperienceVerifier()
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        XCTAssertFalse(store.isSignInAvailable)

        await store.signInForExperience()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertTrue(store.isExperienceSession)
        XCTAssertFalse(store.isDevelopmentSession)
        XCTAssertEqual(provider.loginCount, 1)
        XCTAssertNil(store.errorMessage)
    }

    func testExperienceSubmissionRejectsAnUnclassifiedResult() async throws {
        let provider = ExperienceVerifier()
        provider.loginSession = try UserSession(verifiedUserID: UUID().uuidString)
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)

        await store.signInForExperience()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isExperienceSession)
    }

    func testDevelopmentAccountCannotClaimExperienceClassification() {
        XCTAssertThrowsError(try UserSession(verifiedUserID: UUID().uuidString,
                                            cohort: .development, isExperience: true))
    }

    func testContextRequiresAnonymousAuthAndServerExperienceFlagToAgree() throws {
        let experienceContext = try context(isExperience: true)
        XCTAssertThrowsError(try experienceContext.verifiedSession(for: fixtureID, isAnonymous: false))
        XCTAssertTrue(try experienceContext.verifiedSession(for: fixtureID, isAnonymous: true).isExperience)
        let regularContext = try context(isExperience: false)
        XCTAssertThrowsError(try regularContext.verifiedSession(for: fixtureID, isAnonymous: true))
    }

    func testLegacyContextDoesNotClassifyAnonymousSessionAsTrusted() throws {
        let json = """
        {"user_id":"\(fixtureID)","display_name":"Player","cohort":"production"}
        """
        let value = try JSONDecoder().decode(VerifiedSessionContext.self, from: Data(json.utf8))
        XCTAssertFalse(try value.verifiedSession(for: fixtureID).isExperience)
        XCTAssertThrowsError(try value.verifiedSession(for: fixtureID, isAnonymous: true))
    }

    func testVerifiedExperienceRestoresFromExistingSessionWhileAppleIsUnavailable() async throws {
        let provider = ExperienceVerifier()
        provider.persistedSession = try experienceSession()
        let store = SessionStore(authenticationService: provider)

        await store.restoreSession()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertTrue(store.isExperienceSession)
        XCTAssertEqual(provider.loginCount, 0)
    }

    func testRestoreFailureOnlyUsesCachedAnonymousStateForSignOutWarning() async {
        let provider = ExperienceVerifier()
        provider.restoreFailure = AuthenticationFailure.invalidVerifiedUser
        provider.hasPersistedExperienceSession = true
        let store = SessionStore(authenticationService: provider)

        await store.restoreSession()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertTrue(store.hasRestorationError)
        XCTAssertTrue(store.requiresExperienceSignOutConfirmation)
    }

    func testAuthFailureDoesNotExposeRawServiceErrors() async throws {
        let provider = ExperienceVerifier()
        provider.loginFailure = NSError(domain: "Auth", code: 400,
            userInfo: [NSLocalizedDescriptionKey: "private-session-token"])
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)

        await store.signInForExperience()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(try XCTUnwrap(store.errorMessage).contains("private-session-token"))
    }

    func testPendingExperienceSignInRejectsDuplicateAndAppleSubmission() async throws {
        let provider = ExperienceVerifier()
        provider.suspendsLogin = true
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        let started = expectation(description: "Anonymous exchange started")
        provider.onLogin = { started.fulfill() }
        let login = Task { await store.signInForExperience() }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertTrue(store.isSigningIn)
        XCTAssertNil(store.beginSignIn())
        await store.signInForExperience()
        XCTAssertEqual(provider.loginCount, 1)

        provider.finishLogin(with: try experienceSession())
        await login.value
        XCTAssertTrue(store.isAuthenticated)
    }

    func testSignOutClearsLateAnonymousPersistenceAndDoesNotRestore() async throws {
        let provider = ExperienceVerifier()
        provider.suspendsLogin = true
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        let started = expectation(description: "Anonymous exchange started")
        let cleaned = expectation(description: "Late persisted session cleared")
        provider.onLogin = { started.fulfill() }
        provider.onSignOut = { cleaned.fulfill() }
        let login = Task { await store.signInForExperience() }
        await fulfillment(of: [started], timeout: 1)

        store.signOut()
        provider.finishLogin(with: try experienceSession())
        await login.value
        await fulfillment(of: [cleaned], timeout: 1)
        let relaunched = SessionStore(authenticationService: provider)
        await relaunched.restoreSession()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(relaunched.isAuthenticated)
        XCTAssertNil(provider.persistedSession)
    }

    func testCancelledAnonymousExchangeCannotUnlockApp() async throws {
        let provider = ExperienceVerifier()
        provider.suspendsLogin = true
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        let started = expectation(description: "Anonymous exchange started")
        let cleaned = expectation(description: "Cancelled exchange cleared")
        provider.onLogin = { started.fulfill() }
        provider.onSignOut = { cleaned.fulfill() }
        let login = Task { await store.signInForExperience() }
        await fulfillment(of: [started], timeout: 1)

        login.cancel()
        provider.finishLogin(with: try experienceSession())
        await login.value
        await fulfillment(of: [cleaned], timeout: 1)

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.errorMessage)
    }

    func testAnonymousDeletionNeverRunsForRegularAccount() async throws {
        let provider = ExperienceVerifier()
        provider.persistedSession = try UserSession(verifiedUserID: fixtureID.uuidString)
        let store = SessionStore(authenticationService: provider)
        await store.restoreSession()

        await store.deleteExperienceAccount()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(provider.deletionCount, 0)
    }

    #if DEBUG
    func testUnifiedDeletionRunsForDevelopmentAccountAndClearsSession() async throws {
        let provider = ExperienceVerifier()
        provider.persistedSession = try UserSession(verifiedUserID: fixtureID.uuidString, cohort: .development)
        let store = SessionStore(authenticationService: provider)
        let cleaned = expectation(description: "Development account session cleared")
        provider.onSignOut = { cleaned.fulfill() }
        await store.restoreSession()

        await store.deleteAccount()
        await fulfillment(of: [cleaned], timeout: 1)

        XCTAssertEqual(provider.genericDeletionCount, 1)
        XCTAssertEqual(provider.deletionCount, 0)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(provider.persistedSession)
    }
    #endif

    func testUnifiedDeletionDoesNotRunWithoutAuthenticatedSession() async {
        let provider = ExperienceVerifier()
        let store = SessionStore(authenticationService: provider)

        await store.deleteAccount()

        XCTAssertEqual(provider.genericDeletionCount, 0)
        XCTAssertNil(store.errorMessage)
    }

    func testAppleRevocationUnavailableKeepsAccountAndExplainsNoDeletion() async throws {
        let provider = ExperienceVerifier()
        provider.persistedSession = try UserSession(verifiedUserID: fixtureID.uuidString)
        provider.deletionFailure = AuthenticationFailure.appleDeletionUnavailable
        let store = SessionStore(authenticationService: provider)
        await store.restoreSession()

        await store.deleteAccount()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertFalse(store.isDeletingAccount)
        XCTAssertTrue(try XCTUnwrap(store.errorMessage).contains("hasn't been deleted"))
    }

    func testUnconfirmedDeletionRestoreOffersRetryAndExplicitLocalExit() async throws {
        let provider = ExperienceVerifier()
        provider.hasPendingAccountDeletion = true
        provider.restoreFailure = AuthenticationFailure.invalidVerifiedUser
        let store = SessionStore(authenticationService: provider)

        await store.restoreSession()

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertTrue(store.hasRestorationError)
        XCTAssertTrue(store.hasPendingAccountDeletion)
        let message = try XCTUnwrap(store.errorMessage)
        XCTAssertTrue(message.contains("couldn't confirm account deletion"))
        XCTAssertTrue(message.contains("Sign in again"))
    }

    func testFailedDeletionKeepsAccountOpenAndShowsSafeError() async throws {
        let provider = ExperienceVerifier()
        provider.deletionFailure = NSError(domain: "Delete", code: 500,
            userInfo: [NSLocalizedDescriptionKey: "private-token"])
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        await store.signInForExperience()

        await store.deleteExperienceAccount()

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertFalse(store.isDeletingAccount)
        XCTAssertFalse(try XCTUnwrap(store.errorMessage).contains("private-token"))
    }

    func testSuccessfulDeletionClearsDeviceSession() async {
        let provider = ExperienceVerifier()
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        let cleaned = expectation(description: "Deleted account session cleared")
        provider.onSignOut = { cleaned.fulfill() }
        await store.signInForExperience()

        await store.deleteExperienceAccount()
        await fulfillment(of: [cleaned], timeout: 1)

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isDeletingAccount)
        XCTAssertEqual(provider.deletionCount, 1)
        XCTAssertNil(provider.persistedSession)
    }

    func testDeletionIsSerializedAndLateFailureCannotChangeNewSession() async throws {
        let provider = ExperienceVerifier()
        provider.suspendsDeletion = true
        let store = SessionStore(authenticationService: provider)
        store.setLegalConsent(true)
        await store.signInForExperience()
        let started = expectation(description: "Deletion started")
        let cleaned = expectation(description: "Signed out during deletion")
        provider.onDeletion = { started.fulfill() }
        provider.onSignOut = { cleaned.fulfill() }
        let deletion = Task { await store.deleteExperienceAccount() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(store.isDeletingAccount)
        await store.deleteExperienceAccount()
        XCTAssertEqual(provider.deletionCount, 1)

        store.signOut()
        await fulfillment(of: [cleaned], timeout: 1)
        XCTAssertFalse(store.hasAgreedToLegalDocuments)
        store.setLegalConsent(true)
        await store.signInForExperience()
        let newUserID = store.verifiedUserID
        provider.finishDeletion(throwing: AuthenticationFailure.invalidVerifiedUser)
        await deletion.value

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.verifiedUserID, newUserID)
        XCTAssertNil(store.errorMessage)
    }

    private let fixtureID = UUID(uuidString: "924047f6-5523-4444-af76-472259bff115")!

    private func experienceSession() throws -> UserSession {
        try UserSession(verifiedUserID: fixtureID.uuidString, displayName: "Player", isExperience: true)
    }

    private func context(isExperience: Bool) throws -> VerifiedSessionContext {
        let json = """
        {"user_id":"\(fixtureID)","display_name":"Player","cohort":"production","is_experience":\(isExperience)}
        """
        return try JSONDecoder().decode(VerifiedSessionContext.self, from: Data(json.utf8))
    }
}

@MainActor
private final class ExperienceVerifier: AuthenticationService {
    let isAvailable = false
    let isExperienceSignInAvailable = true
    let maintainsPersistentSession = true
    var hasPersistedExperienceSession = false
    var hasPendingAccountDeletion = false
    private(set) var loginCount = 0
    var persistedSession: UserSession?
    var loginSession: UserSession?
    var loginFailure: Error?
    var restoreFailure: Error?
    var deletionFailure: Error?
    var suspendsLogin = false
    var suspendsDeletion = false
    var onLogin: (() -> Void)?
    var onSignOut: (() -> Void)?
    var onDeletion: (() -> Void)?
    private(set) var deletionCount = 0
    private(set) var genericDeletionCount = 0
    private var loginContinuation: CheckedContinuation<UserSession, Error>?
    private var deletionContinuation: CheckedContinuation<Void, Error>?
    private var pendingLogin: Task<UserSession, Error>?

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }

    func signInForExperience() async throws -> UserSession {
        loginCount += 1
        if let loginFailure { throw loginFailure }
        if suspendsLogin {
            let task = Task { @MainActor in
                let session: UserSession = try await withCheckedThrowingContinuation { continuation in
                    loginContinuation = continuation
                    onLogin?()
                }
                persistedSession = session
                return session
            }
            pendingLogin = task
            defer { pendingLogin = nil }
            return try await task.value
        }
        let session = try loginSession ?? UserSession(verifiedUserID: UUID().uuidString, isExperience: true)
        persistedSession = session
        return session
    }

    func restoreSession() async throws -> UserSession? {
        if let restoreFailure { throw restoreFailure }
        return persistedSession
    }

    func signOut() async throws {
        if let pendingLogin { _ = await pendingLogin.result }
        persistedSession = nil
        onSignOut?()
    }

    func deleteExperienceAccount() async throws {
        deletionCount += 1
        try await performDeletion()
    }

    func deleteAccount() async throws {
        genericDeletionCount += 1
        try await performDeletion()
    }

    private func performDeletion() async throws {
        if let deletionFailure { throw deletionFailure }
        if suspendsDeletion {
            try await withCheckedThrowingContinuation { continuation in
                deletionContinuation = continuation
                onDeletion?()
            }
        }
    }

    func finishLogin(with session: UserSession) {
        loginContinuation?.resume(returning: session)
        loginContinuation = nil
    }

    func finishDeletion(throwing error: Error) {
        deletionContinuation?.resume(throwing: error)
        deletionContinuation = nil
    }
}
