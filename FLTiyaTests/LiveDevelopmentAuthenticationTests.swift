
import Foundation
import XCTest
@testable import FLTiya

// Regression sources written before the live-development implementation.
// Build, typecheck and XCTest execution remain deferred by user instruction.
@MainActor
final class LiveDevelopmentAuthenticationTests: XCTestCase {
    func testDefaultProviderDoesNotOfferDevelopmentAccess() async {
        let store = SessionStore()
        XCTAssertFalse(store.isDevelopmentSignInAvailable)
        await store.signInForDevelopment(accessCode: "fixture-code")
        XCTAssertFalse(store.isAuthenticated)
    }

    func testContextRejectsAnIdentityMismatch() throws {
        let context = try decodeContext(cohort: "production")
        XCTAssertThrowsError(try context.verifiedSession(for: UUID(uuidString: "82d6c0f7-7fc2-4b61-a318-856cd57417f6")!))
    }

    func testContextRejectsUnknownCohort() {
        XCTAssertThrowsError(try decodeContext(cohort: "administrator"))
    }

    func testProductionContextUsesServerDisplayName() throws {
        let context = try decodeContext(cohort: "production")
        let session = try context.verifiedSession(for: fixtureID)
        XCTAssertEqual(session.verifiedUserID, fixtureID.uuidString)
        XCTAssertEqual(session.displayName, "Server Player")
        XCTAssertEqual(session.cohort, .production)
    }

    #if DEBUG
    func testDevelopmentAccessWorksWhileAppleButtonIsUnavailable() async throws {
        let store = SessionStore(authenticationService: DevelopmentVerifier())
        XCTAssertFalse(store.isSignInAvailable)
        XCTAssertTrue(store.isDevelopmentSignInAvailable)

        await store.signInForDevelopment(accessCode: "fixture-code")

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertTrue(store.isDevelopmentSession)
        XCTAssertEqual(store.userDisplayName, "Test Player")
        XCTAssertNil(store.errorMessage)
    }

    func testDevelopmentRestorationWorksWhileAppleButtonIsUnavailable() async throws {
        let verifier = DevelopmentVerifier()
        verifier.persistedSession = try developmentSession()
        let store = SessionStore(authenticationService: verifier)

        await store.restoreSession()

        XCTAssertFalse(store.isSignInAvailable)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertTrue(store.isDevelopmentSession)
    }

    func testBlankAndOversizedCodesDoNotAuthenticate() async {
        let store = SessionStore(authenticationService: DevelopmentVerifier())
        for code in [" \n", String(repeating: "x", count: 257)] {
            await store.signInForDevelopment(accessCode: code)
            XCTAssertFalse(store.isAuthenticated)
            XCTAssertFalse(store.isSigningIn)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testDevelopmentFailureShowsSafeErrorWhileAppleIsOff() async throws {
        let verifier = DevelopmentVerifier()
        verifier.failure = NSError(domain: "Login", code: 401,
            userInfo: [NSLocalizedDescriptionKey: "private-fixture-code"])
        let store = SessionStore(authenticationService: verifier)

        await store.signInForDevelopment(accessCode: "private-fixture-code")

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isSigningIn)
        XCTAssertFalse(try XCTUnwrap(store.errorMessage).contains("private-fixture-code"))
    }

    func testDevelopmentSubmissionRejectsProductionResult() async throws {
        let verifier = DevelopmentVerifier()
        verifier.loginSession = try UserSession(verifiedUserID: fixtureID.uuidString)
        let store = SessionStore(authenticationService: verifier)

        await store.signInForDevelopment(accessCode: "fixture-code")

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isDevelopmentSession)
    }

    func testSignOutPreventsLateDevelopmentLoginAndPersistentRestore() async throws {
        let verifier = SuspendedDevelopmentVerifier()
        let store = SessionStore(authenticationService: verifier)
        let started = expectation(description: "Development exchange started")
        let cleaned = expectation(description: "Development persistence cleared")
        verifier.onStart = { started.fulfill() }
        verifier.onSignOut = { cleaned.fulfill() }
        let login = Task { await store.signInForDevelopment(accessCode: "fixture-code") }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertTrue(store.isSigningIn)
        XCTAssertFalse(store.isAuthenticated)
        await store.signInForDevelopment(accessCode: "second-fixture-code")
        store.signOut()
        verifier.finish(with: try developmentSession())
        await login.value
        await fulfillment(of: [cleaned], timeout: 1)

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isSigningIn)
        XCTAssertFalse(store.isDevelopmentSession)
        let relaunched = SessionStore(authenticationService: verifier)
        await relaunched.restoreSession()
        XCTAssertFalse(relaunched.isAuthenticated)
    }

    func testCancelledDevelopmentTaskCannotUnlockApp() async throws {
        let verifier = SuspendedDevelopmentVerifier()
        let store = SessionStore(authenticationService: verifier)
        let started = expectation(description: "Development exchange started")
        let cleaned = expectation(description: "Cancelled exchange cleared")
        verifier.onStart = { started.fulfill() }
        verifier.onSignOut = { cleaned.fulfill() }
        let login = Task { await store.signInForDevelopment(accessCode: "fixture-code") }
        await fulfillment(of: [started], timeout: 1)

        login.cancel()
        verifier.finish(with: try developmentSession())
        await login.value
        await fulfillment(of: [cleaned], timeout: 1)

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isDevelopmentSession)
        XCTAssertNil(store.errorMessage)
    }
    #else
    func testReleaseRejectsDevelopmentContext() throws {
        let context = try decodeContext(cohort: "development")
        XCTAssertThrowsError(try context.verifiedSession(for: fixtureID))
    }

    func testReleaseRefusesDevelopmentLoginEvenWhenProviderOffersIt() async {
        let store = SessionStore(authenticationService: DevelopmentVerifier())
        XCTAssertFalse(store.isDevelopmentSignInAvailable)
        await store.signInForDevelopment(accessCode: "fixture-code")
        XCTAssertFalse(store.isAuthenticated)
    }

    func testReleaseClearsDevelopmentRestoration() async throws {
        let verifier = DevelopmentVerifier()
        verifier.persistedSession = try developmentSession()
        let cleaned = expectation(description: "Development restoration cleared")
        verifier.onSignOut = { cleaned.fulfill() }
        let store = SessionStore(authenticationService: verifier)

        await store.restoreSession()
        await fulfillment(of: [cleaned], timeout: 1)

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertFalse(store.isDevelopmentSession)
        let relaunched = SessionStore(authenticationService: verifier)
        await relaunched.restoreSession()
        XCTAssertFalse(relaunched.isAuthenticated)
    }
    #endif

    private let fixtureID = UUID(uuidString: "f4104ca9-3a76-4114-b2c8-de118c31c8c9")!

    private func decodeContext(cohort: String) throws -> VerifiedSessionContext {
        let json = """
        {"user_id":"f4104ca9-3a76-4114-b2c8-de118c31c8c9","display_name":"Server Player","cohort":"\(cohort)"}
        """
        return try JSONDecoder().decode(VerifiedSessionContext.self, from: Data(json.utf8))
    }

    private func developmentSession() throws -> UserSession {
        try UserSession(verifiedUserID: fixtureID.uuidString, displayName: "Test Player", cohort: .development)
    }
}

@MainActor
private final class DevelopmentVerifier: AuthenticationService {
    let isAvailable = false
    let isDevelopmentSignInAvailable = true
    let maintainsPersistentSession = true
    var persistedSession: UserSession?
    var loginSession: UserSession?
    var failure: Error?
    var onSignOut: (() -> Void)?

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }

    func verifyDevelopmentAccessCode(_ accessCode: String) async throws -> UserSession {
        if let failure { throw failure }
        let session = try loginSession ?? UserSession(verifiedUserID: "f4104ca9-3a76-4114-b2c8-de118c31c8c9",
            displayName: "Test Player", cohort: .development)
        persistedSession = session
        return session
    }

    func restoreSession() async throws -> UserSession? { persistedSession }
    func signOut() async throws {
        persistedSession = nil
        onSignOut?()
    }
}

@MainActor
private final class SuspendedDevelopmentVerifier: AuthenticationService {
    let isAvailable = false
    let isDevelopmentSignInAvailable = true
    let maintainsPersistentSession = true
    var onStart: (() -> Void)?
    var onSignOut: (() -> Void)?
    private var continuation: CheckedContinuation<UserSession, Error>?
    private var exchange: Task<UserSession, Error>?
    private var persistedSession: UserSession?

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }

    func verifyDevelopmentAccessCode(_ accessCode: String) async throws -> UserSession {
        let task = Task { @MainActor in
            let session: UserSession = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                onStart?()
            }
            persistedSession = session
            return session
        }
        exchange = task
        defer { exchange = nil }
        return try await task.value
    }

    func restoreSession() async throws -> UserSession? { persistedSession }
    func signOut() async throws {
        if let exchange { _ = await exchange.result }
        persistedSession = nil
        onSignOut?()
    }

    func finish(with session: UserSession) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}
