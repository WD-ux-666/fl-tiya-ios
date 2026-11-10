import AuthenticationServices
import CryptoKit
import XCTest
@testable import FLTiya

// Written before the authentication implementation. Execution is deferred until
// the user authorizes builds and XCTest execution.
@MainActor
final class SessionStoreTests: XCTestCase {
    func testUnconfiguredProviderCannotStartOrCreateSession() async {
        let session = SessionStore()
        session.setLegalConsent(true)

        XCTAssertFalse(session.isSignInAvailable)
        XCTAssertNil(session.beginSignIn())
        await session.completeSignIn(with: credential(state: "unrequested-state"))

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(session.userDisplayName)
        XCTAssertFalse(session.isSigningIn)
    }

    func testAppleSignInCannotStartBeforeLegalConsent() {
        let session = SessionStore(authenticationService: ImmediateVerifier())

        XCTAssertFalse(session.hasAgreedToLegalDocuments)
        XCTAssertNil(session.beginSignIn())
        XCTAssertFalse(session.isSigningIn)

        session.setLegalConsent(true)
        session.setLegalConsent(false)
        XCTAssertNil(session.beginSignIn())
        session.setLegalConsent(true)
        XCTAssertNotNil(session.beginSignIn())
    }

    func testNativeRequestContainsFreshStateAndHashedNonce() throws {
        let session = SessionStore(authenticationService: ImmediateVerifier())
        session.setLegalConsent(true)
        let firstRequest = ASAuthorizationAppleIDProvider().createRequest()
        session.prepareAppleRequest(firstRequest)
        let firstState = try XCTUnwrap(firstRequest.state)
        let firstNonce = try XCTUnwrap(firstRequest.nonce)

        XCTAssertFalse(firstState.isEmpty)
        XCTAssertEqual(firstNonce.count, 64)
        XCTAssertNotEqual(firstState, firstNonce)
        XCTAssertTrue(session.isSigningIn)

        session.signOut()
        XCTAssertFalse(session.hasAgreedToLegalDocuments)
        session.setLegalConsent(true)
        let secondRequest = ASAuthorizationAppleIDProvider().createRequest()
        session.prepareAppleRequest(secondRequest)

        XCTAssertNotEqual(firstState, secondRequest.state)
        XCTAssertNotEqual(firstNonce, secondRequest.nonce)
    }

    func testOnlyVerifierSuccessUnlocksAppAndSuppliesDisplayName() async throws {
        let verifier = ImmediateVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())

        XCTAssertFalse(session.isAuthenticated)
        await session.completeSignIn(with: credential(state: request.state))

        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.userDisplayName, "Verified Player")
        XCTAssertFalse(session.isSigningIn)
        XCTAssertNil(session.errorMessage)
        let payload = try XCTUnwrap(verifier.receivedPayloads.first)
        XCTAssertEqual(payload.userIdentifier, "apple-user")
        XCTAssertEqual(payload.identityToken, validToken)
        XCTAssertEqual(payload.authorizationCode, Data("authorization-code".utf8))
        XCTAssertFalse(payload.rawNonce.isEmpty)
        XCTAssertNotEqual(payload.rawNonce, request.hashedNonce)
        let expectedHash = SHA256.hash(data: Data(payload.rawNonce.utf8))
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(request.hashedNonce, expectedHash)
    }

    func testUnrequestedCredentialCannotAuthenticate() async {
        let verifier = ImmediateVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)

        await session.completeSignIn(with: credential(state: "unsolicited"))

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(verifier.receivedPayloads.isEmpty)
    }

    func testMissingOrMalformedTokensNeverReachVerifier() async throws {
        let verifier = ImmediateVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let invalidTokens: [Data?] = [nil, Data(), Data(" ".utf8), Data([0xff]), Data("not-a-jwt".utf8)]

        for token in invalidTokens {
            let request = try XCTUnwrap(session.beginSignIn())
            await session.completeSignIn(with: AppleSignInCredential(
                userIdentifier: "apple-user", identityToken: token,
                authorizationCode: Data("authorization-code".utf8), state: request.state
            ))
            XCTAssertFalse(session.isAuthenticated)
            XCTAssertFalse(session.isSigningIn)
            XCTAssertNotNil(session.errorMessage)
        }
        XCTAssertTrue(verifier.receivedPayloads.isEmpty)
    }

    func testMissingOrMalformedAuthorizationCodeNeverReachesVerifier() async throws {
        let verifier = ImmediateVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let invalidCodes: [Data?] = [nil, Data(), Data(" \n".utf8), Data([0xff])]

        for code in invalidCodes {
            let request = try XCTUnwrap(session.beginSignIn())
            await session.completeSignIn(with: AppleSignInCredential(
                userIdentifier: "apple-user", identityToken: validToken,
                authorizationCode: code, state: request.state
            ))
            XCTAssertFalse(session.isAuthenticated)
            XCTAssertFalse(session.isSigningIn)
        }
        XCTAssertTrue(verifier.receivedPayloads.isEmpty)
    }

    func testMissingOrMismatchedStateCannotAuthenticate() async throws {
        let verifier = ImmediateVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let invalidStates: [String?] = [nil, "", "different-state"]

        for invalidState in invalidStates {
            XCTAssertNotNil(session.beginSignIn())
            await session.completeSignIn(with: credential(state: invalidState))
            XCTAssertFalse(session.isAuthenticated)
            XCTAssertFalse(session.isSigningIn)
            XCTAssertNotNil(session.errorMessage)
        }
        XCTAssertTrue(verifier.receivedPayloads.isEmpty)
    }

    func testBlankAppleUserCannotReachVerifier() async throws {
        let verifier = ImmediateVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())

        await session.completeSignIn(with: AppleSignInCredential(
            userIdentifier: " \n", identityToken: validToken,
            authorizationCode: Data("authorization-code".utf8), state: request.state
        ))

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(verifier.receivedPayloads.isEmpty)
    }

    func testBlankVerifiedUserIsRejected() {
        XCTAssertThrowsError(try UserSession(verifiedUserID: " \n", displayName: "Name"))
    }

    func testVerifierFailureDoesNotExposeCredentialOrUnlockApp() async throws {
        let secret = String(decoding: validToken, as: UTF8.self)
        let verifier = ImmediateVerifier(result: .failure(NSError(
            domain: "Verifier", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Request rejected: \(secret)"]
        )))
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())

        await session.completeSignIn(with: credential(state: request.state))

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertFalse(session.isSigningIn)
        XCTAssertFalse(try XCTUnwrap(session.errorMessage).contains(secret))
    }

    func testAppleCancellationIsQuietAndAllowsAnotherAttempt() async {
        let session = SessionStore(authenticationService: ImmediateVerifier())
        session.setLegalConsent(true)
        XCTAssertNotNil(session.beginSignIn())

        await session.handleAppleResult(.failure(ASAuthorizationError(.canceled)))

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertFalse(session.isSigningIn)
        XCTAssertNil(session.errorMessage)
        XCTAssertNotNil(session.beginSignIn())
    }

    func testVerifierCancellationIsQuiet() async throws {
        let session = SessionStore(authenticationService: ImmediateVerifier(result: .failure(CancellationError())))
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())

        await session.completeSignIn(with: credential(state: request.state))

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertFalse(session.isSigningIn)
        XCTAssertNil(session.errorMessage)
    }

    func testPendingAttemptCannotBeReplacedBySecondAttempt() async throws {
        let session = SessionStore(authenticationService: ImmediateVerifier())
        session.setLegalConsent(true)
        let firstRequest = try XCTUnwrap(session.beginSignIn())

        XCTAssertNil(session.beginSignIn())
        await session.completeSignIn(with: credential(state: firstRequest.state))

        XCTAssertTrue(session.isAuthenticated)
    }

    func testInFlightVerificationKeepsAppLockedAndRejectsDuplicateSubmission() async throws {
        let verifier = SuspendedVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())
        let started = expectation(description: "Verification started")
        verifier.onStart = { started.fulfill() }
        let verification = Task { await session.completeSignIn(with: credential(state: request.state)) }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(session.isSigningIn)
        XCTAssertNil(session.beginSignIn())
        await session.completeSignIn(with: credential(state: request.state))
        XCTAssertEqual(verifier.receivedPayloads.count, 1)

        verifier.finish(with: try UserSession(verifiedUserID: "verified-user"))
        await verification.value
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertFalse(session.isSigningIn)
    }

    func testSignOutPreventsLateVerificationFromRestoringSession() async throws {
        let verifier = SuspendedVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())
        let started = expectation(description: "Verification started")
        verifier.onStart = { started.fulfill() }
        let verification = Task { await session.completeSignIn(with: credential(state: request.state)) }
        await fulfillment(of: [started], timeout: 1)

        session.signOut()
        XCTAssertNil(session.beginSignIn(), "Verification remains serialized until the previous call finishes.")
        verifier.finish(with: try UserSession(verifiedUserID: "verified-user"))
        await verification.value

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(session.userDisplayName)
        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(session.isSigningIn)
        XCTAssertFalse(session.hasAgreedToLegalDocuments)
        session.setLegalConsent(true)
        XCTAssertNotNil(session.beginSignIn())
    }

    func testSignOutClearsVerifiedSession() async throws {
        let session = SessionStore(authenticationService: ImmediateVerifier())
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())
        await session.completeSignIn(with: credential(state: request.state))

        session.signOut()

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(session.userDisplayName)
    }

    func testOnlyVerifiedRestorationUnlocksApp() async throws {
        let restored = try UserSession(verifiedUserID: "server-user", displayName: "Returning Player")
        let session = SessionStore(authenticationService: RestorationVerifier(result: .success(restored)))

        XCTAssertFalse(session.isAuthenticated)
        await session.restoreSession()

        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.verifiedUserID, "server-user")
        XCTAssertEqual(session.userDisplayName, "Returning Player")
        XCTAssertFalse(session.isRestoringSession)
    }

    func testTransientRestoreFailureKeepsAppLockedAndCanBeRetried() async throws {
        let verifier = RestorationVerifier(result: .failure(NSError(
            domain: "Restore", code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "private-refresh-token"]
        )))
        let session = SessionStore(authenticationService: verifier)

        await session.restoreSession()

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertTrue(session.hasRestorationError)
        XCTAssertNil(session.verifiedUserID)
        XCTAssertFalse(try XCTUnwrap(session.errorMessage).contains("private-refresh-token"))

        verifier.result = .success(try UserSession(verifiedUserID: "server-user"))
        await session.restoreSession(force: true)

        XCTAssertTrue(session.isAuthenticated)
        XCTAssertFalse(session.hasRestorationError)
    }

    func testSignOutClearsPersistenceAfterLateExchangeBeforeAnotherRestore() async throws {
        let verifier = PersistentSuspendedVerifier()
        let session = SessionStore(authenticationService: verifier)
        session.setLegalConsent(true)
        let request = try XCTUnwrap(session.beginSignIn())
        let started = expectation(description: "Persistent exchange started")
        let cleaned = expectation(description: "Persistent exchange cleaned after sign-out")
        verifier.onStart = { started.fulfill() }
        verifier.onSignOut = { cleaned.fulfill() }
        let verification = Task { await session.completeSignIn(with: credential(state: request.state)) }
        await fulfillment(of: [started], timeout: 1)

        session.signOut()
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(session.beginSignIn())
        verifier.finish(with: try UserSession(verifiedUserID: "late-user"))
        await verification.value
        await fulfillment(of: [cleaned], timeout: 1)
        // Simulate another app session reading the same service persistence.
        let relaunchedSession = SessionStore(authenticationService: verifier)
        await relaunchedSession.restoreSession()

        XCTAssertFalse(relaunchedSession.isAuthenticated)
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(verifier.persistedSession)
    }

    private var validToken: Data {
        Data("eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJhcHBsZS11c2VyIn0.c2lnbmF0dXJl".utf8)
    }

    private func credential(state: String?) -> AppleSignInCredential {
        AppleSignInCredential(
            userIdentifier: "apple-user", identityToken: validToken,
            authorizationCode: Data("authorization-code".utf8), state: state
        )
    }
}

@MainActor
private final class RestorationVerifier: AuthenticationService {
    let isAvailable = true
    var result: Result<UserSession?, Error>

    init(result: Result<UserSession?, Error>) { self.result = result }

    func restoreSession() async throws -> UserSession? { try result.get() }

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }
}

@MainActor
private final class PersistentSuspendedVerifier: AuthenticationService {
    let isAvailable = true
    let maintainsPersistentSession = true
    private(set) var persistedSession: UserSession?
    var onStart: (() -> Void)?
    var onSignOut: (() -> Void)?
    private var continuation: CheckedContinuation<UserSession, Error>?
    private var exchange: Task<UserSession, Error>?

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        let task = Task { @MainActor in
            let result: UserSession = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                onStart?()
            }
            persistedSession = result
            return result
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

@MainActor
private final class ImmediateVerifier: AuthenticationService {
    var isAvailable = true
    var receivedPayloads: [AppleAuthenticationPayload] = []
    private let result: Result<UserSession, Error>?

    init(result: Result<UserSession, Error>? = nil) {
        self.result = result
    }

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        receivedPayloads.append(payload)
        if let result { return try result.get() }
        return try UserSession(verifiedUserID: "verified-user", displayName: "Verified Player")
    }
}

@MainActor
private final class SuspendedVerifier: AuthenticationService {
    var isAvailable = true
    var receivedPayloads: [AppleAuthenticationPayload] = []
    var onStart: (() -> Void)?
    private var continuation: CheckedContinuation<UserSession, Error>?

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        receivedPayloads.append(payload)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onStart?()
        }
    }

    func finish(with session: UserSession) {
        continuation?.resume(returning: session)
        continuation = nil
    }
}
