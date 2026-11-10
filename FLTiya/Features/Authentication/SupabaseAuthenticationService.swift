import Foundation
import Security
import Supabase

/// Owns the SDK's persisted session boundary. SDK events alone never unlock UI.
@MainActor
final class SupabaseAuthenticationService: AuthenticationService {
    let maintainsPersistentSession = true
    var isAvailable: Bool { configuration.appleSignInEnabled }
    let isExperienceSignInAvailable = true
    var hasPersistedExperienceSession: Bool { client.auth.currentUser?.isAnonymous == true }
    var hasPendingAccountDeletion: Bool {
        guard let pending = preferences.string(forKey: deletionPreferenceKey), UUID(uuidString: pending) != nil else { return false }
        return client.auth.currentUser.map { $0.id.uuidString == pending } ?? true
    }
    var isDevelopmentSignInAvailable: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private let client: SupabaseClient
    private let configuration: BackendConfiguration
    private let keychainService: String
    private let preferences: UserDefaults
    private let signedOutPreferenceKey: String
    private var deletionPreferenceKey: String { signedOutPreferenceKey + ".deleting-user" }
    private var confirmedAccountDeletion = false
    private var generation = UUID()
    private var activeOperation: Task<UserSession?, Error>?
    private var signOutTask: Task<Void, Error>?
    private var isSigningOut = false

    init(client: SupabaseClient, configuration: BackendConfiguration) {
        self.client = client
        self.configuration = configuration
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.fltiya.ios"
        keychainService = configuration.keychainService(bundleIdentifier: bundleIdentifier)
        preferences = .standard
        signedOutPreferenceKey = configuration.signedOutPreferenceKey(bundleIdentifier: bundleIdentifier)
    }

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        guard isAvailable,
              let idToken = String(data: payload.identityToken, encoding: .utf8),
              !payload.rawNonce.isEmpty else { throw AuthenticationFailure.unavailable }
        let attemptGeneration = generation
        do {
            let result = try await performOperation {
                let sdkSession = try await self.client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: payload.rawNonce)
                )
                try self.requireCurrent(attemptGeneration)
                // Auth's storage layer reports Keychain failures only to its
                // logger. Require its persisted identity to match the response
                // before sharing this client with authenticated repositories.
                guard self.client.auth.currentSession?.accessToken == sdkSession.accessToken else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                var user = try await self.client.auth.user(jwt: sdkSession.accessToken)
                try self.requireCurrent(attemptGeneration)
                guard user.id == sdkSession.user.id else { throw AuthenticationFailure.invalidVerifiedUser }

                // Apple supplies this only on first authorization, outside its JWT.
                // Failure to save a name does not undo an already verified login.
                if let components = payload.fullName {
                    let formattedName = PersonNameComponentsFormatter().string(from: components)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = String(String.UnicodeScalarView(formattedName.unicodeScalars.prefix(80)))
                    if !name.isEmpty {
                        do {
                            user = try await self.client.auth.update(user: UserAttributes(data: ["full_name": .string(name)]))
                            try self.requireCurrent(attemptGeneration)
                            // Fill only the initial placeholder. A customized
                            // profile name must survive Apple reauthorization.
                            _ = try? await self.client.from("profiles")
                                .update(["display_name": name])
                                .eq("id", value: user.id)
                                .eq("display_name", value: "Player")
                                .execute()
                        } catch {
                            try self.requireCurrent(attemptGeneration)
                        }
                    }
                }
                try self.requireCurrent(attemptGeneration)
                let appSession = try await self.appSession(for: user, generation: attemptGeneration)
                guard appSession.cohort == .production, !appSession.isExperience else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                self.preferences.set(false, forKey: self.signedOutPreferenceKey)
                return appSession
            }
            guard let result else { throw AuthenticationFailure.invalidVerifiedUser }
            return result
        } catch {
            // A failed/cancelled verification must not leave an SDK-created login
            // available to the next launch. Explicit sign-out also owns this path.
            if generation == attemptGeneration, !isSigningOut {
                invalidateLocalSession()
                try? await signOut()
            }
            throw error
        }
    }

    func signInForExperience() async throws -> UserSession {
        let attemptGeneration = generation
        do {
            let result = try await performOperation {
                // No email sign-in, identity lookup or linking occurs here.
                // Auth assigns a fresh UUID and stores its session in Keychain.
                let sdkSession = try await self.client.auth.signInAnonymously()
                try self.requireCurrent(attemptGeneration)
                guard self.client.auth.currentSession?.accessToken == sdkSession.accessToken else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                let user = try await self.client.auth.user(jwt: sdkSession.accessToken)
                try self.requireCurrent(attemptGeneration)
                guard user.id == sdkSession.user.id, user.isAnonymous else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                let session = try await self.appSession(for: user, generation: attemptGeneration)
                guard session.isExperience, session.cohort == .production else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                self.preferences.set(false, forKey: self.signedOutPreferenceKey)
                return session
            }
            guard let result else { throw AuthenticationFailure.invalidVerifiedUser }
            return result
        } catch {
            if generation == attemptGeneration, !isSigningOut {
                invalidateLocalSession()
                try? await signOut()
            }
            throw error
        }
    }

    func deleteExperienceAccount() async throws {
        try await deleteAccount(using: "delete-experience-account", requiresAnonymous: true)
    }

    func deleteAccount() async throws {
        try await deleteAccount(using: "delete-account", requiresAnonymous: false)
    }

    private func deleteAccount(using function: String, requiresAnonymous: Bool) async throws {
        let attemptGeneration = generation
        _ = try await performOperation {
            try await self.deleteCurrentAccount(using: function, requiresAnonymous: requiresAnonymous,
                                                generation: attemptGeneration)
            return nil
        }
    }

    private func deleteCurrentAccount(using function: String, requiresAnonymous: Bool,
                                      generation expectedGeneration: UUID) async throws {
        let sdkSession = try await client.auth.session
        try requireCurrent(expectedGeneration)
        let user = try await client.auth.user(jwt: sdkSession.accessToken)
        try requireCurrent(expectedGeneration)
        guard user.id == sdkSession.user.id, client.auth.currentUser?.id == user.id,
              !requiresAnonymous || user.isAnonymous else { throw AuthenticationFailure.invalidVerifiedUser }
        // A confirmed intent is tied to the exact verified UUID. After a restart
        // restore can finish deletion without reopening this account's app data.
        preferences.set(user.id.uuidString, forKey: deletionPreferenceKey)
        // Do not call session_context: deleting accounts intentionally fail it.
        struct Request: Encodable {}
        struct Response: Decodable { let deleted: Bool }
        do {
            let response: Response = try await client.functions.invoke(
                function, options: FunctionInvokeOptions(body: Request())
            )
            guard response.deleted else { throw AuthenticationFailure.invalidVerifiedUser }
            confirmedAccountDeletion = true
        } catch let FunctionsError.httpError(_, data) {
            struct Failure: Decodable { let error: String }
            if (try? JSONDecoder().decode(Failure.self, from: data))?.error == "apple_revocation_configuration_required" {
                // The server guarantees this rejection precedes every mutation.
                preferences.removeObject(forKey: deletionPreferenceKey)
                throw AuthenticationFailure.appleDeletionUnavailable
            }
            throw AuthenticationFailure.unavailable
        }
        // Successful server deletion still needs local cleanup if cancelled.
        guard generation == expectedGeneration, !isSigningOut else { throw CancellationError() }
    }

    func verifyDevelopmentAccessCode(_ accessCode: String) async throws -> UserSession {
        #if DEBUG
        guard isDevelopmentSignInAvailable, !accessCode.isEmpty, accessCode.utf8.count <= 256 else {
            throw AuthenticationFailure.unavailable
        }
        let attemptGeneration = generation
        do {
            let result = try await performOperation {
                struct Request: Encodable { let access_code: String }
                struct Response: Decodable {
                    let access_token: String
                    let refresh_token: String
                    let user_id: UUID
                    let display_name: String
                }
                let response: Response = try await self.client.functions.invoke(
                    "development-login", options: FunctionInvokeOptions(body: Request(access_code: accessCode))
                )
                try self.requireCurrent(attemptGeneration)
                guard !response.access_token.isEmpty, !response.refresh_token.isEmpty else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                let sdkSession = try await self.client.auth.setSession(
                    accessToken: response.access_token, refreshToken: response.refresh_token
                )
                try self.requireCurrent(attemptGeneration)
                guard self.client.auth.currentSession?.accessToken == sdkSession.accessToken,
                      sdkSession.user.id == response.user_id else {
                    throw AuthenticationFailure.invalidVerifiedUser
                }
                let user = try await self.client.auth.user(jwt: sdkSession.accessToken)
                try self.requireCurrent(attemptGeneration)
                guard user.id == response.user_id else { throw AuthenticationFailure.invalidVerifiedUser }
                let appSession = try await self.appSession(for: user, generation: attemptGeneration)
                guard appSession.cohort == .development else { throw AuthenticationFailure.invalidVerifiedUser }
                self.preferences.set(false, forKey: self.signedOutPreferenceKey)
                return appSession
            }
            guard let result else { throw AuthenticationFailure.invalidVerifiedUser }
            return result
        } catch {
            if ProcessInfo.processInfo.environment["FLTIYA_UI_REVIEW_ACCESS_CODE"] != nil {
                let failure = error as NSError
                NSLog("UIReview auth failure type=%@ domain=%@ code=%ld", String(reflecting: type(of: error)),
                      failure.domain, failure.code)
            }
            if generation == attemptGeneration, !isSigningOut {
                invalidateLocalSession()
                try? await signOut()
            }
            throw error
        }
        #else
        throw AuthenticationFailure.unavailable
        #endif
    }

    func restoreSession() async throws -> UserSession? {
        if preferences.bool(forKey: signedOutPreferenceKey) {
            // The marker survives process termination and a late token exchange.
            try? await signOut()
            return nil
        }
        let restoreGeneration = generation
        var resumedDeletion = false
        do {
            let restored = try await performOperation {
                let sdkSession: Session
                do {
                    sdkSession = try await self.client.auth.session
                } catch AuthError.sessionMissing {
                    return nil
                }
                try self.requireCurrent(restoreGeneration)
                // A locally cached, unexpired JWT alone cannot restore the app UI.
                let user = try await self.client.auth.user(jwt: sdkSession.accessToken)
                try self.requireCurrent(restoreGeneration)
                guard user.id == sdkSession.user.id else { throw AuthenticationFailure.invalidVerifiedUser }
                if self.preferences.string(forKey: self.deletionPreferenceKey) == user.id.uuidString {
                    try await self.deleteCurrentAccount(using: "delete-account", requiresAnonymous: false,
                                                        generation: restoreGeneration)
                    resumedDeletion = true
                    return nil
                }
                return try await self.appSession(for: user, generation: restoreGeneration)
            }
            if resumedDeletion {
                invalidateLocalSession()
                try await signOut()
            }
            return restored
        } catch AuthenticationFailure.developmentSessionNotAllowed {
            // Debug and Release can share a bundle's Keychain. Release must
            // remove a persisted development session before showing sign-in.
            invalidateLocalSession()
            try await signOut()
            return nil
        }
    }

    func invalidateLocalSession() {
        preferences.set(true, forKey: signedOutPreferenceKey)
        generation = UUID()
        isSigningOut = true
        activeOperation?.cancel()
    }

    func signOut() async throws {
        if let signOutTask {
            return try await signOutTask.value
        }
        if !isSigningOut { invalidateLocalSession() }
        let pendingOperation = activeOperation
        let cleanup = Task { @MainActor in
            // Auth exchanges persist their result inside the SDK. Wait for that
            // write before deleting it, even when cancellation was ignored.
            if let pendingOperation { _ = await pendingOperation.result }
            var remoteFailed = false
            do {
                try await self.client.auth.signOut(scope: .local)
            } catch {
                remoteFailed = true
            }
            // The SDK logs storage errors internally; perform an explicit removal
            // so local deletion failure is observable without exposing raw errors.
            let status = SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.keychainService,
                kSecAttrAccount as String: self.configuration.authStorageKey
            ] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw AuthenticationFailure.signOutIncomplete
            }
            self.preferences.removeObject(forKey: self.deletionPreferenceKey)
            if remoteFailed && !self.confirmedAccountDeletion { throw AuthenticationFailure.signOutIncomplete }
            self.confirmedAccountDeletion = false
        }
        signOutTask = cleanup
        defer {
            signOutTask = nil
            isSigningOut = false
        }
        try await cleanup.value
    }

    func observeSignOut(_ onSignOut: @escaping @MainActor () -> Void) async {
        for await (event, _) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            if event == .signedOut || event == .userDeleted { onSignOut() }
        }
    }

    private func performOperation(
        _ operation: @escaping @MainActor () async throws -> UserSession?
    ) async throws -> UserSession? {
        guard !isSigningOut, activeOperation == nil else { throw AuthenticationFailure.operationInProgress }
        let task = Task { @MainActor in try await operation() }
        activeOperation = task
        defer { activeOperation = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func requireCurrent(_ expectedGeneration: UUID) throws {
        try Task.checkCancellation()
        guard generation == expectedGeneration, !isSigningOut else { throw CancellationError() }
    }

    private func appSession(for user: User, generation: UUID) async throws -> UserSession {
        guard client.auth.currentUser?.id == user.id else {
            throw AuthenticationFailure.invalidVerifiedUser
        }
        // This RPC rejects inactive accounts and untrusted identities using the
        // current SDK session. User-editable metadata cannot classify an actor.
        let context: VerifiedSessionContext = try await client.rpc("session_context").execute().value
        try requireCurrent(generation)
        guard client.auth.currentUser?.id == user.id else { throw AuthenticationFailure.invalidVerifiedUser }
        return try context.verifiedSession(for: user.id, isAnonymous: user.isAnonymous)
    }
}
